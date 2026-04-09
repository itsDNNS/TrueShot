-- TrueShot Profile: Fire / Frostfire (Spec 63)
-- Fallback profile when Sunfury marker not detected

local Engine = TrueShot.Engine

local COMBUSTION_DURATION = 12

local Profile = {
    id = "Mage.Fire.Frostfire",
    displayName = "Fire Frostfire",
    specID = 63,
    -- No markerSpell: fallback when Sunfury's Emberwing Heatwave not detected
    version = 1,

    state = {
        lastCombustionCast = 0,
        combustionWindowUntil = 0,
    },

    rules = {
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
    },
}

function Profile:ResetState()
    self.state.lastCombustionCast = 0
    self.state.combustionWindowUntil = 0
end

function Profile:OnSpellCast(spellID)
    if spellID == 190319 then -- Combustion
        local now = GetTime()
        self.state.lastCombustionCast = now
        self.state.combustionWindowUntil = now + COMBUSTION_DURATION
    end
end

function Profile:OnCombatEnd()
    self.state.combustionWindowUntil = 0
end

function Profile:EvalCondition(cond)
    if cond.type == "in_combustion" then
        return GetTime() < self.state.combustionWindowUntil
    end
    return nil
end

function Profile:GetDebugLines()
    local combRemaining = self.state.combustionWindowUntil - GetTime()
    return {
        "  Combustion: " .. (combRemaining > 0
            and string.format("%.1fs remaining", combRemaining)
            or "inactive"),
    }
end

function Profile:GetPhase()
    if not UnitAffectingCombat("player") then return nil end
    if GetTime() < self.state.combustionWindowUntil then return "Burst" end
    return nil
end

Engine:RegisterProfile(Profile)

if TrueShot.CustomProfile then
    TrueShot.CustomProfile.RegisterConditionSchema("Mage.Fire.Frostfire", {
        { id = "in_combustion", label = "In Combustion", params = {} },
    })
end
