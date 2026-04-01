-- HunterFlow Profile Template
-- Copy this file when starting a new profile module.
-- Do not add the file to HunterFlow.toc until the profile is ready to load.

local Engine = HunterFlow.Engine

local Profile = {
    id = "Hunter.MM.ExampleHero",
    class = "HUNTER",
    specID = 254,
    hero = "ExampleHero",

    -- Keep state small, explicit, and tied to observable signals.
    state = {
        burstWindowUntil = 0,
        trackedSpellAvailable = false,
        lastTrackedCast = 0,
    },

    rules = {
        -- Example:
        -- {
        --     type = "PREFER",
        --     spellID = 0,
        --     condition = { type = "tracked_spell_ready" },
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
