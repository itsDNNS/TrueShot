-- TrueShot Profile: Survival / Sentinel (Spec 255)
-- Cast-event state machine for Takedown burst window,
-- Wildfire Bomb charge management, and Moonlight Chakram timing

local Engine = TrueShot.Engine

local TAKEDOWN_DURATION = 8
local BOOMSTICK_COOLDOWN = 30

------------------------------------------------------------------------
-- Spell IDs
------------------------------------------------------------------------

local SPELLS = {
    Takedown         = 1250646,
    Boomstick        = 1261193,
    WildfireBomb     = 259495,
    MoonlightChakram = 1264902,
    FlamefangPitch   = 1251592,
    Harpoon          = 190925,
    CallPet1         = 883,
    RevivePet        = 982,
}

------------------------------------------------------------------------
-- Profile definition
------------------------------------------------------------------------

local Profile = {
    id = "Hunter.SV.Sentinel",
    displayName = "SV Sentinel",
    specID = 255,
    markerSpell = SPELLS.MoonlightChakram,

    state = {
        lastTakedownCast = 0,
        takedownUntil = 0,
        lastBoomstickCast = 0,
    },

    rules = {
        -- Filter utility spells
        { type = "BLACKLIST", spellID = SPELLS.Harpoon },
        { type = "BLACKLIST", spellID = SPELLS.CallPet1 },
        { type = "BLACKLIST", spellID = SPELLS.RevivePet },

        -- Prevent capping WFB charges while fishing Sentinel's Mark procs
        {
            type = "PREFER",
            spellID = SPELLS.WildfireBomb,
            reason = "Charge Cap",
            condition = { type = "wfb_near_cap", seconds = 5 },
        },

        -- Boomstick pinned during Takedown burst (suppress when on CD)
        {
            type = "PIN",
            spellID = SPELLS.Boomstick,
            reason = "Takedown Burst",
            condition = {
                type = "and",
                left  = { type = "takedown_active" },
                right = { type = "not", inner = { type = "boomstick_on_cd" } },
            },
        },

        -- Moonlight Chakram early in Takedown window (long damage)
        {
            type = "PREFER",
            spellID = SPELLS.MoonlightChakram,
            reason = "Chakram",
            condition = {
                type = "and",
                left  = { type = "takedown_active" },
                right = { type = "takedown_just_cast", seconds = 5 },
            },
        },

        -- Flamefang Pitch when ready
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
    self.state.lastBoomstickCast = 0
end

function Profile:OnSpellCast(spellID)
    local now = GetTime()
    local s = self.state

    if spellID == SPELLS.Takedown then
        s.lastTakedownCast = now
        s.takedownUntil = now + TAKEDOWN_DURATION

    elseif spellID == SPELLS.Boomstick then
        s.lastBoomstickCast = now
    end
end

function Profile:OnCombatEnd()
    self.state.takedownUntil = 0
    self.state.lastBoomstickCast = 0
end

------------------------------------------------------------------------
-- Profile-specific condition evaluation
------------------------------------------------------------------------

function Profile:EvalCondition(cond)
    local s = self.state
    local now = GetTime()

    if cond.type == "takedown_just_cast" then
        local threshold = cond.seconds or 5
        return s.lastTakedownCast > 0 and (now - s.lastTakedownCast) <= threshold

    elseif cond.type == "takedown_active" then
        return now < s.takedownUntil

    elseif cond.type == "boomstick_on_cd" then
        if s.lastBoomstickCast == 0 then return false end
        return (now - s.lastBoomstickCast) < BOOMSTICK_COOLDOWN

    elseif cond.type == "wfb_near_cap" then
        if C_Spell and C_Spell.GetSpellCharges then
            local ok, info = pcall(C_Spell.GetSpellCharges, SPELLS.WildfireBomb)
            if ok and info and info.currentCharges then
                if issecretvalue and issecretvalue(info.currentCharges) then
                    return false
                end
                if info.currentCharges >= 2 then return true end
                if info.currentCharges == 1 then
                    local startTime = info.cooldownStartTime
                    local duration = info.cooldownDuration
                    if not startTime or not duration then return false end
                    if issecretvalue and (issecretvalue(startTime) or issecretvalue(duration)) then
                        return false
                    end
                    local threshold = cond.seconds or 5
                    local timeToRecharge = (startTime + duration) - now
                    return timeToRecharge <= threshold
                end
                return false
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

    return nil
end

------------------------------------------------------------------------
-- Debug output
------------------------------------------------------------------------

function Profile:GetDebugLines()
    local s = self.state
    local now = GetTime()
    local tdRemaining = s.takedownUntil - now

    local wfbLine = "unknown"
    if C_Spell and C_Spell.GetSpellCharges then
        local ok, info = pcall(C_Spell.GetSpellCharges, SPELLS.WildfireBomb)
        if ok and info and info.currentCharges then
            if not (issecretvalue and issecretvalue(info.currentCharges)) then
                local timeToCap = ""
                if info.currentCharges < info.maxCharges then
                    local rechargeIn = (info.cooldownStartTime + info.cooldownDuration) - now
                    timeToCap = string.format(", %.1fs to next", rechargeIn)
                end
                wfbLine = string.format("%d/%d%s", info.currentCharges, info.maxCharges, timeToCap)
            end
        end
    end

    return {
        "  Takedown: " .. (tdRemaining > 0
            and string.format("%.1fs remaining", tdRemaining)
            or "inactive"),
        "  WFB: " .. wfbLine,
    }
end

------------------------------------------------------------------------
-- Phase detection
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
