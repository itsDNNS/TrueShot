-- TrueShot Profile Template
-- Copy this file when starting a new class/spec profile.
-- Replace the example values with your class, spec, and hero path.
-- Add the file to TrueShot.toc (after Engine.lua, before Core.lua) when ready.
--
-- Examples:
--   Hunter BM Dark Ranger: specID=253, markerSpell=466930 (Black Arrow)
--   Demon Hunter Havoc:    specID=577, markerSpell=nil (or hero-specific)

local Engine = TrueShot.Engine

local Profile = {
    id = "Class.Spec.HeroPath",  -- e.g. "DemonHunter.Havoc.AldrachiReaver"
    specID = 0,                   -- WoW spec ID (GetSpecializationInfo)
    markerSpell = nil,            -- hero-path exclusive spell for auto-detection (optional)

    -- Keep state small, explicit, and tied to observable signals.
    state = {
        burstWindowUntil = 0,
        trackedSpellAvailable = false,
        lastTrackedCast = 0,
    },

    rules = {
        -- Example rules (uncomment and adapt):
        -- { type = "BLACKLIST", spellID = 0 },  -- filter utility spells
        -- {
        --     type = "PREFER",
        --     spellID = 0,
        --     reason = "Burst Window",  -- shown in Why overlay
        --     condition = { type = "in_burst_window" },
        -- },
    },
}

function Profile:ResetState()
    self.state.burstWindowUntil = 0
    self.state.trackedSpellAvailable = false
    self.state.lastTrackedCast = 0
end

function Profile:OnSpellCast(spellID)
    local now = GetTime()
    local s = self.state

    -- Replace with cast-driven transitions only.
    if spellID == 0 then
        s.trackedSpellAvailable = true
        s.lastTrackedCast = now
    else
        -- Keep the default branch explicit.
    end
end

function Profile:OnCombatEnd()
    -- Reset only the state that must not survive combat.
end

function Profile:EvalCondition(cond)
    local s = self.state

    if cond.type == "tracked_spell_ready" then
        return s.trackedSpellAvailable

    elseif cond.type == "in_burst_window" then
        return GetTime() < s.burstWindowUntil
    end

    return nil
end

function Profile:GetDebugLines()
    local s = self.state
    return {
        "  Tracked spell ready: " .. tostring(s.trackedSpellAvailable),
        "  Burst window until: " .. string.format("%.1f", s.burstWindowUntil),
    }
end

Engine:RegisterProfile(Profile)
