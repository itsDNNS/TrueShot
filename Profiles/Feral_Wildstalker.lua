-- TrueShot Profile: Feral / Wildstalker (Spec 103)
-- Cast-event state machine for Tiger's Fury and Berserk burst windows.
--
-- Limitations: Feral is heavily resource-dependent on Energy and Combo Points,
-- both of which are hidden from addon inspection in TrueShot's model.
-- DoT snapshot state (Rip/Rake empowerment) is also opaque. Wildstalker's
-- unique mechanic (Bloodseeker Vines) is proc-based hidden state that
-- TrueShot cannot track. This profile handles burst windows only.

local Engine = TrueShot.Engine

local TIGERS_FURY_DURATION = 10
local BERSERK_DURATION = 15

------------------------------------------------------------------------
-- Profile definition
------------------------------------------------------------------------

local Profile = {
    id = "Druid.Feral.Wildstalker",
    displayName = "Feral Wildstalker",
    specID = 103,
    markerSpell = 439531, -- Bloodseeker Vines (Wildstalker exclusive)

    state = {
        tigersFuryUntil = 0,
        berserkUntil = 0,
    },

    rules = {
        -- Filter utility spells
        { type = "BLACKLIST", spellID = 106839 }, -- Skull Bash

        -- Apex Predator: PREFER Ferocious Bite when proc is active (glow detection)
        {
            type = "PREFER",
            spellID = 22568, -- Ferocious Bite
            reason = "Apex Predator",
            condition = { type = "spell_glowing", spellID = 22568 },
        },

        -- Prefer Berserk during Tiger's Fury for maximum burst alignment
        {
            type = "PREFER",
            spellID = 106951, -- Berserk
            reason = "TF Burst",
            condition = { type = "in_tigers_fury" },
        },
    },
}

------------------------------------------------------------------------
-- State machine
------------------------------------------------------------------------

function Profile:ResetState()
    self.state.tigersFuryUntil = 0
    self.state.berserkUntil = 0
end

function Profile:OnSpellCast(spellID)
    local now = GetTime()
    local s = self.state

    if spellID == 5217 then -- Tiger's Fury
        s.tigersFuryUntil = now + TIGERS_FURY_DURATION

    elseif spellID == 106951 then -- Berserk
        s.berserkUntil = now + BERSERK_DURATION
    end
end

function Profile:OnCombatEnd()
    self.state.tigersFuryUntil = 0
    self.state.berserkUntil = 0
end

------------------------------------------------------------------------
-- Profile-specific condition evaluation
------------------------------------------------------------------------

function Profile:EvalCondition(cond)
    local s = self.state

    if cond.type == "in_tigers_fury" then
        return GetTime() < s.tigersFuryUntil

    elseif cond.type == "in_berserk" then
        return GetTime() < s.berserkUntil
    end

    return nil -- not handled by this profile
end

------------------------------------------------------------------------
-- Debug output
------------------------------------------------------------------------

function Profile:GetDebugLines()
    local s = self.state
    local tfRemaining = s.tigersFuryUntil - GetTime()
    local bsRemaining = s.berserkUntil - GetTime()
    return {
        "  Tiger's Fury: " .. (tfRemaining > 0
            and string.format("%.1fs remaining", tfRemaining)
            or "inactive"),
        "  Berserk: " .. (bsRemaining > 0
            and string.format("%.1fs remaining", bsRemaining)
            or "inactive"),
    }
end

------------------------------------------------------------------------
-- Phase detection (for overlay display)
------------------------------------------------------------------------

function Profile:GetPhase()
    if not UnitAffectingCombat("player") then return nil end
    local s = self.state
    if GetTime() < s.berserkUntil then return "Berserk" end
    if GetTime() < s.tigersFuryUntil then return "Tiger's Fury" end
    return nil
end

------------------------------------------------------------------------
-- Register
------------------------------------------------------------------------

Engine:RegisterProfile(Profile)
