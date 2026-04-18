-- TrueShot Profile: Survival / Pack Leader (specID 255)
-- Hero path: Pack Leader (no markerSpell - SV fallback when Sentinel's Moonlight Chakram marker is not known)
-- Cast-event state machine for Takedown window, Stampede sequencing,
-- WFB charge management, and Flamefang Pitch timing.
--
-- PRIMARY SOURCE
--   Author:        Azortharion
--   Guide:         Survival Hunter DPS Rotation, Cooldowns, and Abilities - Midnight Season 1
--   URL:           https://www.icy-veins.com/wow/survival-hunter-pve-dps-rotation-cooldowns-abilities
--   Guide updated: 2026-03-27
--   Verified:      2026-04-18
--   Patch:         12.0.4 (Midnight Season 1)
--
-- CROSS-CHECK SOURCES
--   SimC midnight branch: ActionPriorityLists/default/hunter_survival.simc
--                         (plst / plcleave action lists)
--   Wowhead:              https://www.wowhead.com/guide/classes/hunter/survival/rotation-cooldowns-pve-dps
--                         (Patch 12.0.1, updated 2026-03-24)
--
-- DESIGN SCOPE
--   Overlay profile on Blizzard Assisted Combat.
--   Pack Leader's highest-value override is the Stampede/Howl-of-the-Pack-Leader
--   trigger: "Takedown immediately procs Howl of the Pack Leader, causing your
--   next Kill Command to summon a Beast. Your first Kill Command inside Takedown
--   will also launch a Stampede." (Azortharion §PL Takedown Burst Window.)
--   Tip-of-the-Spear stacks, Sentinel's Mark, and Fury-of-the-Wyvern are hidden
--   buff state and are deliberately not modelled (see docs/API_CONSTRAINTS.md).
--   Inline tags "[src §<section> #N]" reference the priority number in the primary source.

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
    Harpoon        = 190925,
    CallPet1       = 883,
    RevivePet      = 982,
}

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
        -- Filter utility spells (never part of the damage rotation).
        { type = "BLACKLIST", spellID = SPELLS.Harpoon },
        { type = "BLACKLIST", spellID = SPELLS.CallPet1 },
        { type = "BLACKLIST", spellID = SPELLS.RevivePet },

        -- [src §PL Takedown Burst] "Your first Kill Command inside Takedown will
        -- also launch a Stampede." Pin KC for the first cast inside the 8s
        -- Takedown buff window; once KC has fired inside that window the flag
        -- flips and this rule no-ops until the next Takedown.
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

        -- [src §PL ST "Wildfire Bomb only to extend Fury of the Wyvern"] The
        -- Wyvern-extension heuristic would need hidden buff state; ship the
        -- conservative charge-cap proxy instead, which keeps the "never waste a
        -- charge" intent under the Midnight API surface.
        {
            type = "PREFER",
            spellID = SPELLS.WildfireBomb,
            reason = "Charge Cap",
            condition = { type = "wfb_charges", op = "==", value = 2 },
        },

        -- [src §PL ST #4 / AoE #5] "Boomstick" - generally high priority per
        -- Azortharion. Shipped profile only PREFERs it inside Takedown (with a
        -- local-timer CD gate) because outside the burst window AC already
        -- surfaces it well; a wider PIN would fight AC more than it helps.
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

        -- [src §PL ST #3] "Flamefang Pitch on cooldown" - gate the PREFER on
        -- ac_suggested so the override does not fire when AC already knows the
        -- spell is not castable (keeps the rule legal under the CD-secret API).
        {
            type = "PREFER",
            spellID = SPELLS.FlamefangPitch,
            reason = "Flamefang",
            condition = { type = "ac_suggested", spellID = SPELLS.FlamefangPitch },
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
        { id = "wfb_charges",        label = "Wildfire Bomb Charges",
          params = {
              { field = "op",    fieldType = "string", default = "==", label = "Operator" },
              { field = "value", fieldType = "number", default = 2,    label = "Charge count" },
          } },
    })
end
