-- TrueShot Profile: Devourer / Annihilator (Spec 1480)
-- Devourer rotation is heavily AC-reliant due to hidden resource state
-- (Souls, Voidfall stacks, Fury). Profile provides Void Metamorphosis
-- window tracking and phase detection only.

local Engine = TrueShot.Engine

local VOID_META_DURATION = 20 -- approximate, needs in-game validation

------------------------------------------------------------------------
-- Profile definition
------------------------------------------------------------------------

local Profile = {
    id = "DemonHunter.Devourer.Annihilator",
    displayName = "Devourer Annihilator",
    specID = 1480,
    markerSpell = 1253304, -- Voidfall (Annihilator exclusive keystone)
    version = 1,

    state = {
        lastVoidMetaCast = 0,
        voidMetaUntil = 0,
    },

    rules = {
        -- Filter utility spells
        { type = "BLACKLIST", spellID = 217832 }, -- Imprison
    },
}

------------------------------------------------------------------------
-- State machine
------------------------------------------------------------------------

function Profile:ResetState()
    self.state.lastVoidMetaCast = 0
    self.state.voidMetaUntil = 0
end

function Profile:OnSpellCast(spellID)
    local now = GetTime()
    local s = self.state

    if spellID == 1217607 then -- Void Metamorphosis
        s.lastVoidMetaCast = now
        s.voidMetaUntil = now + VOID_META_DURATION
    end
end

function Profile:OnCombatEnd()
    self.state.voidMetaUntil = 0
end

------------------------------------------------------------------------
-- Profile-specific condition evaluation
------------------------------------------------------------------------

function Profile:EvalCondition(cond)
    local s = self.state

    if cond.type == "in_void_meta" then
        return GetTime() < s.voidMetaUntil
    end

    return nil -- not handled by this profile
end

------------------------------------------------------------------------
-- Debug output
------------------------------------------------------------------------

function Profile:GetDebugLines()
    local s = self.state
    local voidMetaRemaining = s.voidMetaUntil - GetTime()
    return {
        "  Void Meta: " .. (voidMetaRemaining > 0
            and string.format("%.1fs remaining", voidMetaRemaining)
            or "inactive"),
    }
end

------------------------------------------------------------------------
-- Phase detection (for overlay display)
------------------------------------------------------------------------

function Profile:GetPhase()
    if not UnitAffectingCombat("player") then return nil end
    local s = self.state
    if GetTime() < s.voidMetaUntil then return "Void Meta" end
    return nil
end

------------------------------------------------------------------------
-- Register
------------------------------------------------------------------------

Engine:RegisterProfile(Profile)

if TrueShot.CustomProfile then
    TrueShot.CustomProfile.RegisterConditionSchema("DemonHunter.Devourer.Annihilator", {
        { id = "in_void_meta", label = "In Void Metamorphosis", params = {} },
    })
end
