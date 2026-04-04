-- TrueShot Profile: Arcane / Spellslinger (Spec 62)
-- Fallback profile -- not meta, minimal rules

local Engine = TrueShot.Engine

local SURGE_DURATION = 12

local Profile = {
    id = "Mage.Arcane.Spellslinger",
    displayName = "Arcane Spellslinger",
    specID = 62,
    -- No markerSpell: fallback when Sunfury's Arcane Pulse not detected

    state = {
        surgeWindowUntil = 0,
    },

    rules = {
        { type = "BLACKLIST", spellID = 118 },     -- Polymorph
        { type = "BLACKLIST", spellID = 30449 },   -- Spellsteal
    },
}

function Profile:ResetState()
    self.state.surgeWindowUntil = 0
end

function Profile:OnSpellCast(spellID)
    if spellID == 365350 then -- Arcane Surge
        self.state.surgeWindowUntil = GetTime() + SURGE_DURATION
    end
end

function Profile:OnCombatEnd()
    self.state.surgeWindowUntil = 0
end

function Profile:EvalCondition(cond)
    if cond.type == "in_surge" then
        return GetTime() < self.state.surgeWindowUntil
    end
    return nil
end

function Profile:GetDebugLines()
    local surgeRemaining = self.state.surgeWindowUntil - GetTime()
    return {
        "  Arcane Surge: " .. (surgeRemaining > 0
            and string.format("%.1fs remaining", surgeRemaining)
            or "inactive"),
    }
end

function Profile:GetPhase()
    if not UnitAffectingCombat("player") then return nil end
    if GetTime() < self.state.surgeWindowUntil then return "Burst" end
    return nil
end

Engine:RegisterProfile(Profile)
