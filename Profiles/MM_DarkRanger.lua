-- TrueShot Profile: Marksmanship / Dark Ranger (specID 254)
-- Hero path: Dark Ranger (marker: Black Arrow 466930 via IsPlayerSpell)
-- Cast-event state machine for Black Arrow, Trueshot window, Wailing Arrow,
-- and Volley/Trueshot anti-overlap.
--
-- PRIMARY SOURCE
--   Author:        Azortharion
--   Guide:         Marksmanship Hunter DPS Rotation, Cooldowns, and Abilities - Midnight Season 1
--   URL:           https://www.icy-veins.com/wow/marksmanship-hunter-pve-dps-rotation-cooldowns-abilities
--   Guide updated: 2026-04-09
--   Verified:      2026-04-18
--   Patch:         12.0.4 (Midnight Season 1)
--
-- CROSS-CHECK SOURCES
--   SimC midnight branch: ActionPriorityLists/default/hunter_marksmanship.simc
--   Wowhead:              https://www.wowhead.com/guide/classes/hunter/marksmanship/rotation-cooldowns-pve-dps
--                         (Patch 12.0.1, updated 2026/04/15)
--
-- DESIGN SCOPE
--   Overlay profile on Blizzard Assisted Combat.
--   Dark Ranger is the Black-Arrow-as-Kill-Shot lane; the rules below focus on
--   the Trueshot -> BA -> WA -> BA opener, WF proc-window BA priority, and the
--   Trueshot <-> Volley anti-overlap (Double Tap).
--   Inline tags "[src §<section> #N]" reference the priority number in the primary source.

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
    displayName = "MM Dark Ranger",
    specID = 254,
    markerSpell = SPELLS.BlackArrow,
    version = 1,

    rotationalSpells = {
        [466930]  = true, -- Black Arrow
        [392060]  = true, -- Wailing Arrow
        [288613]  = true, -- Trueshot
        [257044]  = true, -- Rapid Fire
        [260243]  = true, -- Volley
        [19434]   = true, -- Aimed Shot
        [56641]   = true, -- Steady Shot
        [53351]   = true, -- Kill Shot
        [185358]  = true, -- Arcane Shot
    },

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
        -- Filter utility spells (never part of the damage rotation).
        { type = "BLACKLIST", spellID = SPELLS.CallPet1 },
        { type = "BLACKLIST", spellID = SPELLS.RevivePet },
        { type = "BLACKLIST", spellID = SPELLS.CounterShot },

        -- [src §Sequencing "anti-overlap"] "Never cast Volley and Trueshot back-
        -- to-back in any order, as this wastes Double Tap." Enforced in both
        -- directions below.
        {
            type = "BLACKLIST_CONDITIONAL",
            spellID = SPELLS.Trueshot,
            condition = { type = "volley_recent", seconds = 2 },
        },
        {
            type = "BLACKLIST_CONDITIONAL",
            spellID = SPELLS.Volley,
            condition = { type = "trueshot_just_cast", seconds = 2 },
        },

        -- [src §DR-Burst] "Trueshot -> Black Arrow -> Wailing Arrow -> Black
        -- Arrow sequence maximizes proc utilization within cooldown windows."
        -- Step 1: BA immediately after Trueshot (the free opener proc).
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

        -- [src §DR-Burst step 3] Wailing Arrow after the first BA is spent
        -- (procs the second free BA while still inside the Trueshot window).
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

        -- [src §ST #1] "Black Arrow (cast on cooldown)" - Dark Ranger ranks BA as
        -- the top-line spell. This PIN covers the extended BA-ready window the
        -- profile models after Trueshot (see state.witheringFireUntil).
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

        -- [src §ST #2 / issue #89] Trueshot is the MM major cooldown and the
        -- guide's "main cooldown" priority. Surface it whenever AC treats the
        -- spell as castable and we are in combat. The anti-overlap BLACKLIST
        -- above already handles the Volley -> Trueshot Double Tap case; the
        -- trueshot_just_cast BLACKLIST on Volley handles the reverse order,
        -- so after a pinned Trueshot the queue naturally spends one filler
        -- GCD before showing Volley again, matching the guide's
        -- "one cast between Volley and Trueshot" rule.
        --
        -- The prior gate on rapid_fire_recent(3) was removed: it treated the
        -- Azortharion "Rapid Fire -> Trueshot -> Aimed Shot" sequence as a
        -- hard precondition, but RF (~20s CD) and Trueshot (~2-3min CD) do
        -- not synchronise in practice, so the PIN never fired for players
        -- who opened without Rapid Fire. Reported as issue #89.
        {
            type = "PIN",
            spellID = SPELLS.Trueshot,
            reason = "Trueshot",
            condition = {
                type = "and",
                left  = { type = "ac_suggested", spellID = SPELLS.Trueshot },
                right = { type = "in_combat" },
            },
        },

        -- [src §ST #1 outside WF] BA outside the modelled WF proc window is a
        -- soft hint, not an override: PREFER only. If AC already surfaces BA the
        -- rule is a no-op; otherwise the queue bumps BA ahead of plain filler.
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

if TrueShot.CustomProfile then
    TrueShot.CustomProfile.RegisterConditionSchema("Hunter.MM.DarkRanger", {
        { id = "ba_ready",          label = "Black Arrow Ready",       params = {} },
        { id = "in_withering_fire", label = "In Withering Fire",       params = {} },
        { id = "wa_available",      label = "Wailing Arrow Available", params = {} },
        { id = "trueshot_just_cast", label = "Trueshot Just Cast",
          params = { { field = "seconds", fieldType = "number", default = 2, label = "Seconds window" } } },
        { id = "trueshot_active",   label = "Trueshot Active",         params = {} },
        { id = "rapid_fire_recent", label = "Rapid Fire Recent",
          params = { { field = "seconds", fieldType = "number", default = 3, label = "Seconds window" } } },
        { id = "volley_recent",     label = "Volley Recent",
          params = { { field = "seconds", fieldType = "number", default = 2, label = "Seconds window" } } },
    })
end
