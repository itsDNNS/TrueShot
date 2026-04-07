-- TrueShot Profile: Frost / Frostfire (Spec 64)
-- Shatter combo enforcement + Frozen Orb burst tracking

local Engine = TrueShot.Engine

local FROZEN_ORB_DURATION = 10

local Profile = {
    id = "Mage.Frost.Frostfire",
    displayName = "Frost Frostfire",
    specID = 64,
    -- No markerSpell: default Frost profile (100% meta usage)

    state = {
        frozenOrbActiveUntil = 0,
        lastCastWasFlurry = false,
    },

    rules = {
        { type = "BLACKLIST", spellID = 118 },     -- Polymorph
        { type = "BLACKLIST", spellID = 30449 },   -- Spellsteal
        { type = "BLACKLIST", spellID = 1459 },    -- Arcane Intellect

        -- Brain Freeze: PREFER Flurry when proc is active (glow detection)
        {
            type = "PREFER",
            spellID = 44614, -- Flurry
            reason = "Brain Freeze",
            condition = { type = "spell_glowing", spellID = 44614 },
        },

        -- Shatter combo: Ice Lance after Flurry (WCL: 66% natural, boost remaining 34%)
        {
            type = "PREFER",
            spellID = 30455, -- Ice Lance
            reason = "Shatter",
            condition = { type = "last_cast_was_flurry" },
        },

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
    self.state.lastCastWasFlurry = false
end

function Profile:OnSpellCast(spellID)
    local s = self.state

    if spellID == 84714 then -- Frozen Orb
        s.frozenOrbActiveUntil = GetTime() + FROZEN_ORB_DURATION
    end

    s.lastCastWasFlurry = (spellID == 44614) -- Flurry
end

function Profile:OnCombatEnd()
    self.state.frozenOrbActiveUntil = 0
    self.state.lastCastWasFlurry = false
end

function Profile:EvalCondition(cond)
    if cond.type == "frozen_orb_active" then
        return GetTime() < self.state.frozenOrbActiveUntil
    elseif cond.type == "last_cast_was_flurry" then
        return self.state.lastCastWasFlurry
    end
    return nil
end

function Profile:GetDebugLines()
    local s = self.state
    local orbRemaining = s.frozenOrbActiveUntil - GetTime()
    return {
        "  Frozen Orb: " .. (orbRemaining > 0
            and string.format("%.1fs remaining", orbRemaining)
            or "inactive"),
        "  Last cast Flurry: " .. tostring(s.lastCastWasFlurry),
    }
end

function Profile:GetPhase()
    if not UnitAffectingCombat("player") then return nil end
    if GetTime() < self.state.frozenOrbActiveUntil then return "Burst" end
    return nil
end

Engine:RegisterProfile(Profile)
