-- HunterFlow Profile: Beast Mastery / Pack Leader (Spec 253)
-- Simpler than Dark Ranger: BW management, Nature's Ally weaving, charge dump

local Engine = HunterFlow.Engine

local BW_COOLDOWN_ESTIMATE = 29

------------------------------------------------------------------------
-- Profile definition
------------------------------------------------------------------------

local Profile = {
    id = "Hunter.BM.PackLeader",
    specID = 253,
    -- No markerSpell: this profile serves as the BM fallback
    -- when Dark Ranger's Black Arrow marker does not match

    state = {
        lastBWCast = 0,
        lastCastWasKC = false,
    },

    rules = {
        -- Filter utility spells
        { type = "BLACKLIST", spellID = 883 },    -- Call Pet 1
        { type = "BLACKLIST", spellID = 982 },    -- Revive Pet
        { type = "BLACKLIST", spellID = 147362 }, -- Counter Shot (user preference)

        -- Bestial Wrath: suppress when on CD or when Barbed Shot charges remain
        {
            type = "BLACKLIST_CONDITIONAL",
            spellID = 19574,
            condition = {
                type = "or",
                left  = { type = "bw_on_cd" },
                right = { type = "spell_charges", spellID = 217200, op = ">", value = 0 },
            },
        },

        -- Barbed Shot charge dump: spend charges when BW is nearly ready
        {
            type = "PREFER",
            spellID = 217200, -- Barbed Shot
            condition = {
                type = "and",
                left  = { type = "spell_charges", spellID = 217200, op = ">", value = 0 },
                right = { type = "bw_nearly_ready" },
            },
        },

        -- Nature's Ally: never Kill Command twice in a row
        {
            type = "BLACKLIST_CONDITIONAL",
            spellID = 34026,
            condition = { type = "last_cast_was_kc" },
        },
    },
}

------------------------------------------------------------------------
-- State machine
------------------------------------------------------------------------

function Profile:ResetState()
    self.state.lastBWCast = 0
    self.state.lastCastWasKC = false
end

function Profile:OnSpellCast(spellID)
    local s = self.state

    if spellID == 19574 then -- Bestial Wrath
        s.lastBWCast = GetTime()
        s.lastCastWasKC = false

    elseif spellID == 34026 then -- Kill Command
        s.lastCastWasKC = true

    else
        s.lastCastWasKC = false
    end
end

function Profile:OnCombatEnd()
    self.state.lastCastWasKC = false
end

------------------------------------------------------------------------
-- Profile-specific condition evaluation
------------------------------------------------------------------------

function Profile:EvalCondition(cond)
    local s = self.state

    if cond.type == "last_cast_was_kc" then
        return s.lastCastWasKC

    elseif cond.type == "bw_on_cd" then
        if s.lastBWCast == 0 then return false end
        return (GetTime() - s.lastBWCast) < BW_COOLDOWN_ESTIMATE

    elseif cond.type == "bw_nearly_ready" then
        if s.lastBWCast == 0 then return true end
        return (GetTime() - s.lastBWCast) >= (BW_COOLDOWN_ESTIMATE - 3)
    end

    return nil -- not handled by this profile
end

------------------------------------------------------------------------
-- Debug output
------------------------------------------------------------------------

function Profile:GetDebugLines()
    local s = self.state
    local bwElapsed = s.lastBWCast > 0 and (GetTime() - s.lastBWCast) or 0
    return {
        "  BW CD: " .. (s.lastBWCast > 0
            and string.format("%.1fs elapsed (est ~%ds)", bwElapsed, BW_COOLDOWN_ESTIMATE)
            or "not cast yet"),
        "  Last cast was KC: " .. tostring(s.lastCastWasKC),
    }
end

------------------------------------------------------------------------
-- Register
------------------------------------------------------------------------

Engine:RegisterProfile(Profile)
