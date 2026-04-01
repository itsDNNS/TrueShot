-- HunterFlow Profile: Beast Mastery / Dark Ranger (Spec 253)
-- Cast-event state machine for Black Arrow, Bestial Wrath, Wailing Arrow

local Engine = HunterFlow.Engine

local BA_COOLDOWN = 10
local BW_COOLDOWN_ESTIMATE = 29

------------------------------------------------------------------------
-- Profile definition
------------------------------------------------------------------------

local Profile = {
    id = "Hunter.BM.DarkRanger",
    specID = 253,

    state = {
        blackArrowReady = true,
        lastBlackArrowCast = 0,
        lastBWCast = 0,
        witheringFireUntil = 0,
        wailingArrowAvailable = false,
        lastCastWasKC = false,
    },

    rules = {
        -- Filter utility spells
        { type = "BLACKLIST", spellID = 883 },    -- Call Pet 1
        { type = "BLACKLIST", spellID = 982 },    -- Revive Pet
        { type = "BLACKLIST", spellID = 147362 }, -- Counter Shot (user preference)

        -- Bestial Wrath: suppress when recently cast
        {
            type = "BLACKLIST_CONDITIONAL",
            spellID = 19574,
            condition = { type = "bw_on_cd" },
        },

        -- During Withering Fire: Black Arrow is highest DPS priority
        {
            type = "PIN",
            spellID = 466930, -- Black Arrow
            condition = {
                type = "and",
                left  = { type = "ba_ready" },
                right = { type = "in_withering_fire" },
            },
        },

        -- Wailing Arrow near end of Withering Fire
        {
            type = "PREFER",
            spellID = 392060, -- Wailing Arrow
            condition = {
                type = "and",
                left  = { type = "wa_available" },
                right = { type = "wf_ending", seconds = 4 },
            },
        },

        -- Outside Withering Fire: prefer Black Arrow when ready
        {
            type = "PREFER",
            spellID = 466930, -- Black Arrow
            condition = {
                type = "and",
                left  = { type = "ba_ready" },
                right = { type = "not", inner = { type = "in_withering_fire" } },
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
    self.state.blackArrowReady = true
    self.state.lastBlackArrowCast = 0
    self.state.lastBWCast = 0
    self.state.witheringFireUntil = 0
    self.state.wailingArrowAvailable = false
    self.state.lastCastWasKC = false
end

function Profile:OnSpellCast(spellID)
    local now = GetTime()
    local s = self.state

    if spellID == 466930 then -- Black Arrow
        s.blackArrowReady = false
        s.lastBlackArrowCast = now
        s.lastCastWasKC = false

    elseif spellID == 19574 then -- Bestial Wrath
        s.blackArrowReady = true
        s.lastBWCast = now
        s.witheringFireUntil = now + 10
        s.wailingArrowAvailable = true
        s.lastCastWasKC = false

    elseif spellID == 392060 then -- Wailing Arrow
        s.blackArrowReady = true
        s.wailingArrowAvailable = false
        s.lastCastWasKC = false

    elseif spellID == 34026 then -- Kill Command
        s.lastCastWasKC = true

    else
        s.lastCastWasKC = false
    end

    -- Timer fallback: if BA CD elapsed, assume ready
    if not s.blackArrowReady and s.lastBlackArrowCast > 0 then
        if (now - s.lastBlackArrowCast) >= BA_COOLDOWN then
            s.blackArrowReady = true
        end
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

    if cond.type == "ba_ready" then
        if not s.blackArrowReady and s.lastBlackArrowCast > 0 then
            if (GetTime() - s.lastBlackArrowCast) >= BA_COOLDOWN then
                s.blackArrowReady = true
            end
        end
        return s.blackArrowReady

    elseif cond.type == "in_withering_fire" then
        return GetTime() < s.witheringFireUntil

    elseif cond.type == "wf_ending" then
        local threshold = cond.seconds or 4
        local remaining = s.witheringFireUntil - GetTime()
        return remaining > 0 and remaining <= threshold

    elseif cond.type == "wa_available" then
        return s.wailingArrowAvailable

    elseif cond.type == "last_cast_was_kc" then
        return s.lastCastWasKC

    elseif cond.type == "bw_on_cd" then
        if s.lastBWCast == 0 then return false end
        return (GetTime() - s.lastBWCast) < BW_COOLDOWN_ESTIMATE
    end

    return nil -- not handled by this profile
end

------------------------------------------------------------------------
-- Debug output
------------------------------------------------------------------------

function Profile:GetDebugLines()
    local s = self.state
    local wfRemaining = s.witheringFireUntil - GetTime()
    return {
        "  BA ready: " .. tostring(s.blackArrowReady),
        "  Withering Fire: " .. (wfRemaining > 0
            and string.format("%.1fs remaining", wfRemaining)
            or "inactive"),
        "  Wailing Arrow: " .. (s.wailingArrowAvailable and "available" or "not available"),
        "  Last cast was KC: " .. tostring(s.lastCastWasKC),
    }
end

------------------------------------------------------------------------
-- Register
------------------------------------------------------------------------

Engine:RegisterProfile(Profile)
