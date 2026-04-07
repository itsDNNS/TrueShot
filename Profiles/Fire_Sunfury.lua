-- TrueShot Profile: Fire / Sunfury (Spec 63)
-- Cast-event state machine for Combustion burst window

local Engine = TrueShot.Engine

local COMBUSTION_DURATION = 12

------------------------------------------------------------------------
-- Profile definition
------------------------------------------------------------------------

local Profile = {
    id = "Mage.Fire.Sunfury",
    displayName = "Fire Sunfury",
    specID = 63,
    markerSpell = 1250508, -- Emberwing Heatwave (Sunfury exclusive)

    state = {
        lastCombustionCast = 0,
        combustionWindowUntil = 0,
    },

    rules = {
        -- Filter utility spells
        { type = "BLACKLIST", spellID = 118 },     -- Polymorph
        { type = "BLACKLIST", spellID = 30449 },   -- Spellsteal
        { type = "BLACKLIST", spellID = 1459 },    -- Arcane Intellect

        -- Hot Streak: PREFER Pyroblast when proc is active (glow detection)
        {
            type = "PREFER",
            spellID = 11366, -- Pyroblast
            reason = "Hot Streak",
            condition = { type = "spell_glowing", spellID = 11366 },
        },

        -- Flamestrike: AoE preference when 3+ targets
        {
            type = "PREFER",
            spellID = 2120, -- Flamestrike
            reason = "AoE 3+",
            condition = { type = "target_count", op = ">=", value = 3 },
        },
    },
}

------------------------------------------------------------------------
-- State machine
------------------------------------------------------------------------

function Profile:ResetState()
    self.state.lastCombustionCast = 0
    self.state.combustionWindowUntil = 0
end

function Profile:OnSpellCast(spellID)
    local now = GetTime()
    local s = self.state

    if spellID == 190319 then -- Combustion
        s.lastCombustionCast = now
        s.combustionWindowUntil = now + COMBUSTION_DURATION
    end
end

function Profile:OnCombatEnd()
    self.state.combustionWindowUntil = 0
end

------------------------------------------------------------------------
-- Profile-specific condition evaluation
------------------------------------------------------------------------

function Profile:EvalCondition(cond)
    local s = self.state

    if cond.type == "in_combustion" then
        return GetTime() < s.combustionWindowUntil
    end

    return nil
end

------------------------------------------------------------------------
-- Debug output
------------------------------------------------------------------------

function Profile:GetDebugLines()
    local s = self.state
    local combRemaining = s.combustionWindowUntil - GetTime()
    return {
        "  Combustion: " .. (combRemaining > 0
            and string.format("%.1fs remaining", combRemaining)
            or "inactive"),
    }
end

------------------------------------------------------------------------
-- Phase detection
------------------------------------------------------------------------

function Profile:GetPhase()
    if not UnitAffectingCombat("player") then return nil end
    if GetTime() < self.state.combustionWindowUntil then return "Burst" end
    return nil
end

------------------------------------------------------------------------
-- Register
------------------------------------------------------------------------

Engine:RegisterProfile(Profile)
