-- TrueShot Profile: Survival / Pack Leader (Spec 255)
-- Cast-event state machine for Takedown window, Stampede sequencing,
-- WFB charge management, and Flamefang Pitch timing

local Engine = TrueShot.Engine

local TAKEDOWN_DURATION = 8
local BOOMSTICK_COOLDOWN = 30

------------------------------------------------------------------------
-- Spell IDs
------------------------------------------------------------------------

local SPELLS = {
    KillCommand    = 259489,  -- SV Kill Command (different from BM!)
    WildfireBomb   = 259495,
    Takedown       = 1250646,
    Boomstick      = 1261193,
    FlamefangPitch = 1251592,
    RaptorStrike   = 186270,
    Harpoon        = 190925,
    HatchetToss    = 259489,
    CallPet1       = 883,
    RevivePet      = 982,
}

-- Melee range probe spells (if any returns in_range=true, player is in melee)
local MELEE_PROBE_SPELLS = { SPELLS.RaptorStrike }

------------------------------------------------------------------------
-- Profile definition
------------------------------------------------------------------------

local Profile = {
    id = "Hunter.SV.PackLeader",
    displayName = "SV Pack Leader",
    specID = 255,
    -- No markerSpell: this profile serves as the SV fallback
    version = 1,

    state = {
        lastTakedownCast = 0,
        takedownUntil = 0,
        kcCastInTakedown = false,
        lastBoomstickCast = 0,
    },

    rotationalSpells = {
        [259489]  = true, -- Kill Command (SV)
        [259495]  = true, -- Wildfire Bomb
        [1250646] = true, -- Takedown
        [1261193] = true, -- Boomstick
        [1251592] = true, -- Flamefang Pitch
        [186270]  = true, -- Raptor Strike
        [53351]   = true, -- Kill Shot
    },

    rules = {
        -- Filter utility spells
        { type = "BLACKLIST", spellID = SPELLS.Harpoon },
        { type = "BLACKLIST", spellID = SPELLS.CallPet1 },
        { type = "BLACKLIST", spellID = SPELLS.RevivePet },

        -- Hatchet Toss: suppress when in melee range
        {
            type = "BLACKLIST_CONDITIONAL",
            spellID = SPELLS.HatchetToss,
            condition = { type = "in_melee_range" },
        },

        -- Stampede: first KC after Takedown triggers Stampede
        {
            type = "PIN",
            spellID = SPELLS.KillCommand,
            reason = "Stampede",
            condition = {
                type = "and",
                left  = { type = "takedown_active" },
                right = { type = "not", inner = { type = "kc_cast_in_takedown" } },
            },
        },

        -- Wildfire Bomb: spend at charge cap
        {
            type = "PREFER",
            spellID = SPELLS.WildfireBomb,
            reason = "Charge Cap",
            condition = { type = "wfb_charges", op = "==", value = 2 },
        },

        -- Boomstick: burst during Takedown window (suppress when on CD)
        {
            type = "PREFER",
            spellID = SPELLS.Boomstick,
            reason = "Takedown Burst",
            condition = {
                type = "and",
                left  = { type = "takedown_active" },
                right = { type = "not", inner = { type = "boomstick_on_cd" } },
            },
        },

        -- Flamefang Pitch: use when ready
        {
            type = "PREFER",
            spellID = SPELLS.FlamefangPitch,
            reason = "Flamefang",
            condition = { type = "flamefang_ready" },
        },
    },
}

------------------------------------------------------------------------
-- State machine
------------------------------------------------------------------------

function Profile:ResetState()
    self.state.lastTakedownCast = 0
    self.state.takedownUntil = 0
    self.state.kcCastInTakedown = false
    self.state.lastBoomstickCast = 0
end

function Profile:OnSpellCast(spellID)
    local now = GetTime()
    local s = self.state

    if spellID == SPELLS.Takedown then
        s.lastTakedownCast = now
        s.takedownUntil = now + TAKEDOWN_DURATION
        s.kcCastInTakedown = false

    elseif spellID == SPELLS.Boomstick then
        s.lastBoomstickCast = now

    elseif spellID == SPELLS.KillCommand then
        if now < s.takedownUntil then
            s.kcCastInTakedown = true
        end
    end
end

function Profile:OnCombatEnd()
    self.state.takedownUntil = 0
    self.state.kcCastInTakedown = false
    self.state.lastTakedownCast = 0
    self.state.lastBoomstickCast = 0
end

------------------------------------------------------------------------
-- Profile-specific condition evaluation
------------------------------------------------------------------------

function Profile:EvalCondition(cond)
    local s = self.state
    local now = GetTime()

    if cond.type == "takedown_just_cast" then
        local threshold = cond.seconds or 2
        return s.lastTakedownCast > 0 and (now - s.lastTakedownCast) <= threshold

    elseif cond.type == "takedown_active" then
        return now < s.takedownUntil

    elseif cond.type == "kc_cast_in_takedown" then
        return s.kcCastInTakedown

    elseif cond.type == "boomstick_on_cd" then
        if s.lastBoomstickCast == 0 then return false end
        return (now - s.lastBoomstickCast) < BOOMSTICK_COOLDOWN

    elseif cond.type == "in_melee_range" then
        -- Check if any melee probe spell is in range; fallback: false (don't suppress)
        if not C_Spell or not C_Spell.IsSpellInRange then return false end
        if not UnitExists("target") then return false end
        for _, probeID in ipairs(MELEE_PROBE_SPELLS) do
            local ok, inRange = pcall(C_Spell.IsSpellInRange, probeID, "target")
            if ok and inRange == true then return true end
        end
        return false

    elseif cond.type == "wfb_charges" then
        if C_Spell and C_Spell.GetSpellCharges then
            local ok, info = pcall(C_Spell.GetSpellCharges, SPELLS.WildfireBomb)
            if ok and info and info.currentCharges then
                if issecretvalue and issecretvalue(info.currentCharges) then
                    return false
                end
                local op = cond.op or "=="
                local val = cond.value or 0
                if op == "==" then return info.currentCharges == val
                elseif op == ">=" then return info.currentCharges >= val
                elseif op == ">"  then return info.currentCharges > val
                elseif op == "<=" then return info.currentCharges <= val
                elseif op == "<"  then return info.currentCharges < val
                end
            end
        end
        return false

    elseif cond.type == "flamefang_ready" then
        if C_Spell and C_Spell.IsSpellUsable then
            local ok, usable = pcall(C_Spell.IsSpellUsable, SPELLS.FlamefangPitch)
            if ok then return usable end
        end
        return false
    end

    return nil -- not handled by this profile
end

------------------------------------------------------------------------
-- Debug output
------------------------------------------------------------------------

function Profile:GetDebugLines()
    local s = self.state
    local now = GetTime()
    local tdRemaining = s.takedownUntil - now
    local wfbCharges = "?"
    if C_Spell and C_Spell.GetSpellCharges then
        local ok, info = pcall(C_Spell.GetSpellCharges, SPELLS.WildfireBomb)
        if ok and info and info.currentCharges then
            if not (issecretvalue and issecretvalue(info.currentCharges)) then
                wfbCharges = tostring(info.currentCharges)
            end
        end
    end
    return {
        "  Takedown: " .. (tdRemaining > 0
            and string.format("%.1fs remaining", tdRemaining)
            or "inactive"),
        "  KC in Takedown: " .. tostring(s.kcCastInTakedown),
        "  WFB charges: " .. wfbCharges,
    }
end

------------------------------------------------------------------------
-- Phase detection (for overlay display)
------------------------------------------------------------------------

function Profile:GetPhase()
    if not UnitAffectingCombat("player") then return nil end
    local now = GetTime()
    local s = self.state
    if now < s.takedownUntil then return "Burst" end
    return nil
end

------------------------------------------------------------------------
-- Register
------------------------------------------------------------------------

Engine:RegisterProfile(Profile)

if TrueShot.CustomProfile then
    TrueShot.CustomProfile.RegisterConditionSchema("Hunter.SV.PackLeader", {
        { id = "takedown_just_cast", label = "Takedown Just Cast",
          params = { { field = "seconds", fieldType = "number", default = 2, label = "Seconds window" } } },
        { id = "takedown_active",    label = "Takedown Active",          params = {} },
        { id = "kc_cast_in_takedown", label = "KC Cast In Takedown",     params = {} },
        { id = "boomstick_on_cd",    label = "Boomstick On Cooldown",    params = {} },
        { id = "in_melee_range",     label = "In Melee Range",           params = {} },
        { id = "wfb_charges",        label = "Wildfire Bomb Charges",
          params = {
              { field = "op",    fieldType = "string", default = "==", label = "Operator" },
              { field = "value", fieldType = "number", default = 2,    label = "Charge count" },
          } },
        { id = "flamefang_ready",    label = "Flamefang Pitch Ready",    params = {} },
    })
end
