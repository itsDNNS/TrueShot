-- TrueShot Profile: Frost / Frostfire (Spec 64)
-- Ice Lance proc-driven rotation with Glacial Spike shatter combos

local Engine = TrueShot.Engine

local FROZEN_ORB_DURATION = 10

local Profile = {
    id = "Mage.Frost.Frostfire",
    displayName = "Frost Frostfire",
    specID = 64,
    -- No markerSpell: default Frost profile (100% meta usage)

    state = {
        frozenOrbActiveUntil = 0,
    },

    rules = {
        { type = "BLACKLIST", spellID = 118 },     -- Polymorph
        { type = "BLACKLIST", spellID = 30449 },   -- Spellsteal

        -- Blizzard: AoE preference when 3+ targets
        {
            type = "PREFER",
            spellID = 190356, -- Blizzard
            reason = "AoE 3+",
            condition = { type = "target_count", op = ">=", value = 3 },
        },
    },
}

function Profile:ResetState()
    self.state.frozenOrbActiveUntil = 0
end

function Profile:OnSpellCast(spellID)
    if spellID == 84714 then -- Frozen Orb
        self.state.frozenOrbActiveUntil = GetTime() + FROZEN_ORB_DURATION
    end
end

function Profile:OnCombatEnd()
    self.state.frozenOrbActiveUntil = 0
end

function Profile:EvalCondition(cond)
    if cond.type == "frozen_orb_active" then
        return GetTime() < self.state.frozenOrbActiveUntil
    end
    return nil
end

function Profile:GetDebugLines()
    local orbRemaining = self.state.frozenOrbActiveUntil - GetTime()
    return {
        "  Frozen Orb: " .. (orbRemaining > 0
            and string.format("%.1fs remaining", orbRemaining)
            or "inactive"),
    }
end

function Profile:GetPhase()
    if not UnitAffectingCombat("player") then return nil end
    if GetTime() < self.state.frozenOrbActiveUntil then return "Burst" end
    return nil
end

Engine:RegisterProfile(Profile)
