-- TrueShot Profile: Havoc / Aldrachi Reaver (Spec 577)
-- Cast-event state machine for Metamorphosis burst window

local Engine = TrueShot.Engine

local META_DURATION = 30

------------------------------------------------------------------------
-- Profile definition
------------------------------------------------------------------------

local Profile = {
    id = "DemonHunter.Havoc.AldrachiReaver",
    displayName = "Havoc Aldrachi Reaver",
    specID = 577,
    markerSpell = 442294, -- Reaver's Glaive (Aldrachi Reaver exclusive)

    state = {
        lastMetaCast = 0,
        metaWindowUntil = 0,
        lastEyeBeamCast = 0,
        lastVRCast = 0,
    },

    rules = {
        -- Filter utility spells
        { type = "BLACKLIST", spellID = 217832 }, -- Imprison

        -- Essence Break: highest priority during Metamorphosis
        {
            type = "PIN",
            spellID = 258860, -- Essence Break
            reason = "Meta Burst",
            condition = { type = "in_meta_window" },
        },
    },
}

------------------------------------------------------------------------
-- State machine
------------------------------------------------------------------------

function Profile:ResetState()
    self.state.lastMetaCast = 0
    self.state.metaWindowUntil = 0
    self.state.lastEyeBeamCast = 0
    self.state.lastVRCast = 0
end

function Profile:OnSpellCast(spellID)
    local now = GetTime()
    local s = self.state

    if spellID == 191427 then -- Metamorphosis
        s.lastMetaCast = now
        s.metaWindowUntil = now + META_DURATION
        s.lastEyeBeamCast = 0
        s.lastVRCast = 0

    elseif spellID == 198013 then -- Eye Beam
        s.lastEyeBeamCast = now

    elseif spellID == 198793 then -- Vengeful Retreat
        s.lastVRCast = now
    end
end

function Profile:OnCombatEnd()
    self.state.metaWindowUntil = 0
end

------------------------------------------------------------------------
-- Profile-specific condition evaluation
------------------------------------------------------------------------

function Profile:EvalCondition(cond)
    local s = self.state

    if cond.type == "in_meta_window" then
        return GetTime() < s.metaWindowUntil
    end

    return nil -- not handled by this profile
end

------------------------------------------------------------------------
-- Debug output
------------------------------------------------------------------------

function Profile:GetDebugLines()
    local s = self.state
    local metaRemaining = s.metaWindowUntil - GetTime()
    return {
        "  Meta window: " .. (metaRemaining > 0
            and string.format("%.1fs remaining", metaRemaining)
            or "inactive"),
        "  Last Eye Beam: " .. (s.lastEyeBeamCast > 0
            and string.format("%.1fs ago", GetTime() - s.lastEyeBeamCast)
            or "n/a"),
        "  Last VR: " .. (s.lastVRCast > 0
            and string.format("%.1fs ago", GetTime() - s.lastVRCast)
            or "n/a"),
    }
end

------------------------------------------------------------------------
-- Phase detection (for overlay display)
------------------------------------------------------------------------

function Profile:GetPhase()
    if not UnitAffectingCombat("player") then return nil end
    local s = self.state
    if GetTime() < s.metaWindowUntil then return "Burst" end
    return nil
end

------------------------------------------------------------------------
-- Register
------------------------------------------------------------------------

Engine:RegisterProfile(Profile)
