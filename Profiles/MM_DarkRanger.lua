-- TrueShot Profile: Marksmanship / Dark Ranger (Spec 254)
-- Cast-event state machine for Black Arrow, Trueshot window, Wailing Arrow,
-- and Volley/Trueshot anti-overlap

local Engine = TrueShot.Engine

local BA_COOLDOWN = 10
local TRUESHOT_DURATION = 15
local WF_DURATION = 10

------------------------------------------------------------------------
-- Spell IDs
------------------------------------------------------------------------

local SPELLS = {
    BlackArrow    = 466930,
    WailingArrow  = 392060,
    Trueshot      = 288613,
    RapidFire     = 257044,
    Volley        = 260243,
    CounterShot   = 147362,
    CallPet1      = 883,
    RevivePet     = 982,
}

------------------------------------------------------------------------
-- Profile definition
------------------------------------------------------------------------

local Profile = {
    id = "Hunter.MM.DarkRanger",
    specID = 254,
    markerSpell = SPELLS.BlackArrow,

    state = {
        blackArrowReady = true,
        lastBlackArrowCast = 0,
        lastRapidFireCast = 0,
        lastTrueshotCast = 0,
        trueshotUntil = 0,
        witheringFireUntil = 0,
        wailingArrowAvailable = false,
        lastVolleyCast = 0,
    },

    rules = {
        -- Filter utility spells
        { type = "BLACKLIST", spellID = SPELLS.CallPet1 },
        { type = "BLACKLIST", spellID = SPELLS.RevivePet },
        { type = "BLACKLIST", spellID = SPELLS.CounterShot },

        -- Anti-overlap: never Trueshot right after Volley (Double Tap waste)
        {
            type = "BLACKLIST_CONDITIONAL",
            spellID = SPELLS.Trueshot,
            condition = { type = "volley_recent", seconds = 2 },
        },
        -- Anti-overlap: never Volley right after Trueshot
        {
            type = "BLACKLIST_CONDITIONAL",
            spellID = SPELLS.Volley,
            condition = { type = "trueshot_just_cast", seconds = 2 },
        },

        -- TS Opener: Black Arrow immediately after Trueshot (free proc)
        {
            type = "PIN",
            spellID = SPELLS.BlackArrow,
            reason = "TS Opener BA",
            condition = {
                type = "and",
                left  = { type = "ba_ready" },
                right = { type = "trueshot_just_cast", seconds = 2 },
            },
        },

        -- TS Opener: Wailing Arrow after spending the first BA proc
        {
            type = "PIN",
            spellID = SPELLS.WailingArrow,
            reason = "TS Wailing",
            condition = {
                type = "and",
                left  = { type = "wa_available" },
                right = {
                    type = "and",
                    left  = { type = "not", inner = { type = "ba_ready" } },
                    right = { type = "trueshot_active" },
                },
            },
        },

        -- General Withering Fire: Black Arrow is highest priority
        {
            type = "PIN",
            spellID = SPELLS.BlackArrow,
            reason = "Withering Fire",
            condition = {
                type = "and",
                left  = { type = "ba_ready" },
                right = { type = "in_withering_fire" },
            },
        },

        -- Trueshot: only after Rapid Fire and not after Volley
        {
            type = "PIN",
            spellID = SPELLS.Trueshot,
            reason = "Post-RF Window",
            condition = {
                type = "and",
                left  = { type = "trueshot_ready" },
                right = {
                    type = "and",
                    left  = { type = "rapid_fire_recent", seconds = 3 },
                    right = { type = "not", inner = { type = "volley_recent", seconds = 2 } },
                },
            },
        },

        -- Outside Withering Fire: prefer Black Arrow when ready
        {
            type = "PREFER",
            spellID = SPELLS.BlackArrow,
            reason = "BA Ready",
            condition = {
                type = "and",
                left  = { type = "ba_ready" },
                right = { type = "not", inner = { type = "in_withering_fire" } },
            },
        },
    },
}

------------------------------------------------------------------------
-- State machine
------------------------------------------------------------------------

function Profile:ResetState()
    self.state.blackArrowReady = true
    self.state.lastBlackArrowCast = 0
    self.state.lastRapidFireCast = 0
    self.state.lastTrueshotCast = 0
    self.state.trueshotUntil = 0
    self.state.witheringFireUntil = 0
    self.state.wailingArrowAvailable = false
    self.state.lastVolleyCast = 0
end

function Profile:OnSpellCast(spellID)
    local now = GetTime()
    local s = self.state

    if spellID == SPELLS.BlackArrow then
        s.blackArrowReady = false
        s.lastBlackArrowCast = now

    elseif spellID == SPELLS.Trueshot then
        s.lastTrueshotCast = now
        s.trueshotUntil = now + TRUESHOT_DURATION
        s.blackArrowReady = true
        s.witheringFireUntil = now + WF_DURATION
        s.wailingArrowAvailable = true

    elseif spellID == SPELLS.WailingArrow then
        s.blackArrowReady = true
        s.wailingArrowAvailable = false

    elseif spellID == SPELLS.RapidFire then
        s.lastRapidFireCast = now

    elseif spellID == SPELLS.Volley then
        s.lastVolleyCast = now
    end

    -- Timer fallback: if BA CD elapsed, assume ready
    if not s.blackArrowReady and s.lastBlackArrowCast > 0 then
        if (now - s.lastBlackArrowCast) >= BA_COOLDOWN then
            s.blackArrowReady = true
        end
    end
end

function Profile:OnCombatEnd()
    self.state.witheringFireUntil = 0
    self.state.trueshotUntil = 0
    self.state.wailingArrowAvailable = false
end

------------------------------------------------------------------------
-- Profile-specific condition evaluation
------------------------------------------------------------------------

function Profile:EvalCondition(cond)
    local s = self.state
    local now = GetTime()

    if cond.type == "ba_ready" then
        if not s.blackArrowReady and s.lastBlackArrowCast > 0 then
            if (now - s.lastBlackArrowCast) >= BA_COOLDOWN then
                s.blackArrowReady = true
            end
        end
        return s.blackArrowReady

    elseif cond.type == "in_withering_fire" then
        return now < s.witheringFireUntil

    elseif cond.type == "wa_available" then
        return s.wailingArrowAvailable

    elseif cond.type == "trueshot_ready" then
        if C_Spell and C_Spell.IsSpellUsable then
            local ok, usable = pcall(C_Spell.IsSpellUsable, SPELLS.Trueshot)
            if ok then return usable end
        end
        return false

    elseif cond.type == "trueshot_just_cast" then
        local threshold = cond.seconds or 2
        return s.lastTrueshotCast > 0 and (now - s.lastTrueshotCast) <= threshold

    elseif cond.type == "trueshot_active" then
        return now < s.trueshotUntil

    elseif cond.type == "rapid_fire_recent" then
        local threshold = cond.seconds or 3
        return s.lastRapidFireCast > 0 and (now - s.lastRapidFireCast) <= threshold

    elseif cond.type == "volley_recent" then
        local threshold = cond.seconds or 2
        return s.lastVolleyCast > 0 and (now - s.lastVolleyCast) <= threshold
    end

    return nil
end

------------------------------------------------------------------------
-- Debug output
------------------------------------------------------------------------

function Profile:GetDebugLines()
    local s = self.state
    local now = GetTime()
    local wfRemaining = s.witheringFireUntil - now
    local tsRemaining = s.trueshotUntil - now
    return {
        "  BA ready: " .. tostring(s.blackArrowReady),
        "  Trueshot: " .. (tsRemaining > 0
            and string.format("%.1fs remaining", tsRemaining)
            or "inactive"),
        "  Withering Fire: " .. (wfRemaining > 0
            and string.format("%.1fs remaining", wfRemaining)
            or "inactive"),
        "  Wailing Arrow: " .. (s.wailingArrowAvailable and "available" or "not available"),
        "  RF recent: " .. (s.lastRapidFireCast > 0
            and string.format("%.1fs ago", now - s.lastRapidFireCast)
            or "not cast"),
        "  Volley recent: " .. (s.lastVolleyCast > 0
            and string.format("%.1fs ago", now - s.lastVolleyCast)
            or "not cast"),
    }
end

------------------------------------------------------------------------
-- Phase detection
------------------------------------------------------------------------

function Profile:GetPhase()
    if not UnitAffectingCombat("player") then return nil end
    local now = GetTime()
    local s = self.state
    if now < s.trueshotUntil then return "Burst" end
    return nil
end

------------------------------------------------------------------------
-- Register
------------------------------------------------------------------------

Engine:RegisterProfile(Profile)
