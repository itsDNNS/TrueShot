-- TrueShot Profile: Balance / Keeper of the Grove (Spec 102)
-- Cast-event state machine for Celestial Alignment / Incarnation burst windows.
--
-- Limitations: Balance is heavily dependent on Astral Power and Eclipse state,
-- both of which are hidden from addon inspection in TrueShot's model. This
-- profile tracks burst cooldown windows only; AC handles the rest.

local Engine = TrueShot.Engine

local BURST_DURATION = 20

------------------------------------------------------------------------
-- Profile definition
------------------------------------------------------------------------

local Profile = {
    id = "Druid.Balance.KeeperOfTheGrove",
    displayName = "Balance Keeper of the Grove",
    specID = 102,
    markerSpell = 428731, -- Harmony of the Grove (Keeper exclusive)
    version = 1,

    state = {
        burstUntil = 0,
    },

    rules = {
        -- Filter utility spells
        { type = "BLACKLIST", spellID = 78675 }, -- Solar Beam
    },
}

------------------------------------------------------------------------
-- State machine
------------------------------------------------------------------------

function Profile:ResetState()
    self.state.burstUntil = 0
end

function Profile:OnSpellCast(spellID)
    local now = GetTime()
    local s = self.state

    if spellID == 194223 then -- Celestial Alignment
        s.burstUntil = now + BURST_DURATION

    elseif spellID == 102560 then -- Incarnation: Chosen of Elune
        s.burstUntil = now + BURST_DURATION
    end
end

function Profile:OnCombatEnd()
    self.state.burstUntil = 0
end

------------------------------------------------------------------------
-- Profile-specific condition evaluation
------------------------------------------------------------------------

function Profile:EvalCondition(cond)
    local s = self.state

    if cond.type == "in_burst" then
        return GetTime() < s.burstUntil
    end

    return nil -- not handled by this profile
end

------------------------------------------------------------------------
-- Debug output
------------------------------------------------------------------------

function Profile:GetDebugLines()
    local s = self.state
    local burstRemaining = s.burstUntil - GetTime()
    return {
        "  Burst: " .. (burstRemaining > 0
            and string.format("%.1fs remaining", burstRemaining)
            or "inactive"),
    }
end

------------------------------------------------------------------------
-- Phase detection (for overlay display)
------------------------------------------------------------------------

function Profile:GetPhase()
    if not UnitAffectingCombat("player") then return nil end
    local s = self.state
    if GetTime() < s.burstUntil then return "Burst" end
    return nil
end

------------------------------------------------------------------------
-- Register
------------------------------------------------------------------------

Engine:RegisterProfile(Profile)

if TrueShot.CustomProfile then
    TrueShot.CustomProfile.RegisterConditionSchema("Druid.Balance.KeeperOfTheGrove", {
        { id = "in_burst", label = "In Burst Window", params = {} },
    })
end
