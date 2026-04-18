-- TrueShot Profile: Survival / Sentinel (specID 255)
-- Hero path: Sentinel (marker: Moonlight Chakram 1264902 via IsPlayerSpell)
-- Cast-event state machine for Takedown burst window,
-- Wildfire Bomb charge management, and Moonlight Chakram timing.
--
-- PRIMARY SOURCE
--   Author:        Azortharion
--   Guide:         Survival Hunter DPS Rotation, Cooldowns, and Abilities - Midnight Season 1
--   URL:           https://www.icy-veins.com/wow/survival-hunter-pve-dps-rotation-cooldowns-abilities
--   Guide updated: 2026-03-27
--   Verified:      2026-04-18
--   Patch:         12.0.4 (Midnight Season 1)
--
-- CROSS-CHECK SOURCES
--   SimC midnight branch: ActionPriorityLists/default/hunter_survival.simc
--                         (sentst / sentcleave action lists)
--   Wowhead:              https://www.wowhead.com/guide/classes/hunter/survival/rotation-cooldowns-pve-dps
--                         (Patch 12.0.1, updated 2026-03-24)
--
-- DESIGN SCOPE
--   Overlay profile on Blizzard Assisted Combat.
--   Sentinel's Mark proc state is hidden; the shipped profile uses the
--   charge-count only path (`spell_charges >= 2`) for WFB and lets AC handle the
--   Mark-driven timing. Boomstick is a PIN inside Takedown (with a local-timer
--   CD gate), Moonlight Chakram is a PREFER early in the Takedown window.
--   Inline tags "[src §<section> #N]" reference the priority number in the primary source.

local Engine = TrueShot.Engine

local TAKEDOWN_DURATION = 8
local BOOMSTICK_COOLDOWN = 30

------------------------------------------------------------------------
-- Spell IDs
------------------------------------------------------------------------

local SPELLS = {
    Takedown         = 1250646,
    Boomstick        = 1261193,
    WildfireBomb     = 259495,
    MoonlightChakram = 1264902,
    FlamefangPitch   = 1251592,
    Harpoon          = 190925,
    CallPet1         = 883,
    RevivePet        = 982,
}

------------------------------------------------------------------------
-- Profile definition
------------------------------------------------------------------------

local Profile = {
    id = "Hunter.SV.Sentinel",
    displayName = "SV Sentinel",
    specID = 255,
    markerSpell = SPELLS.MoonlightChakram,
    version = 1,

    rotationalSpells = {
        [1250646] = true, -- Takedown
        [1261193] = true, -- Boomstick
        [259495]  = true, -- Wildfire Bomb
        [1264902] = true, -- Moonlight Chakram
        [1251592] = true, -- Flamefang Pitch
        [186270]  = true, -- Raptor Strike
        [259489]  = true, -- Kill Command (SV)
        [53351]   = true, -- Kill Shot
    },

    state = {
        lastTakedownCast = 0,
        takedownUntil = 0,
        lastBoomstickCast = 0,
    },

    rules = {
        -- Filter utility spells (never part of the damage rotation).
        { type = "BLACKLIST", spellID = SPELLS.Harpoon },
        { type = "BLACKLIST", spellID = SPELLS.CallPet1 },
        { type = "BLACKLIST", spellID = SPELLS.RevivePet },

        -- [src §Sentinel ST #3] "Wildfire Bomb with Sentinel's Mark proc or <4
        -- sec until 2 charges." Mark proc and precise recharge timing are hidden
        -- state; ship the conservative "at 2 charges" charge-count path (validated
        -- non-secret in docs/SIGNAL_VALIDATION.md) and let AC handle the
        -- Mark-driven timing via its own internal state.
        {
            type = "PREFER",
            spellID = SPELLS.WildfireBomb,
            reason = "Charge Cap",
            condition = { type = "spell_charges", spellID = SPELLS.WildfireBomb, op = ">=", value = 2 },
        },

        -- [src §Sentinel ST #2] "Boomstick (high priority if Takedown unavailable,
        -- no Sentinel's Mark proc)." Shipped PIN is narrower: only inside the
        -- Takedown burst window and only when the local-timer CD gate permits,
        -- since Boomstick readiness outside the burst depends on hidden state.
        {
            type = "PIN",
            spellID = SPELLS.Boomstick,
            reason = "Takedown Burst",
            condition = {
                type = "and",
                left  = { type = "takedown_active" },
                right = { type = "not", inner = { type = "boomstick_on_cd" } },
            },
        },

        -- [src §Sentinel ST #5] "Moonlight Chakram." Shipped profile scopes the
        -- PREFER to the early Takedown window (takedown_just_cast < 5s) to avoid
        -- fighting AC when Chakram would naturally surface later. Conservative
        -- by design.
        {
            type = "PREFER",
            spellID = SPELLS.MoonlightChakram,
            reason = "Chakram",
            condition = {
                type = "and",
                left  = { type = "takedown_active" },
                right = { type = "takedown_just_cast", seconds = 5 },
            },
        },

        -- [src §Sentinel ST #6] "Flamefang Pitch on cooldown." Gate the PREFER
        -- on ac_suggested so the override stays legal under the CD-secret API.
        {
            type = "PREFER",
            spellID = SPELLS.FlamefangPitch,
            reason = "Flamefang",
            condition = { type = "ac_suggested", spellID = SPELLS.FlamefangPitch },
        },
    },
}

------------------------------------------------------------------------
-- State machine
------------------------------------------------------------------------

function Profile:ResetState()
    self.state.lastTakedownCast = 0
    self.state.takedownUntil = 0
    self.state.lastBoomstickCast = 0
end

function Profile:OnSpellCast(spellID)
    local now = GetTime()
    local s = self.state

    if spellID == SPELLS.Takedown then
        s.lastTakedownCast = now
        s.takedownUntil = now + TAKEDOWN_DURATION

    elseif spellID == SPELLS.Boomstick then
        s.lastBoomstickCast = now
    end
end

function Profile:OnCombatEnd()
    self.state.takedownUntil = 0
    self.state.lastBoomstickCast = 0
end

------------------------------------------------------------------------
-- Profile-specific condition evaluation
------------------------------------------------------------------------

function Profile:EvalCondition(cond)
    local s = self.state
    local now = GetTime()

    if cond.type == "takedown_just_cast" then
        local threshold = cond.seconds or 5
        return s.lastTakedownCast > 0 and (now - s.lastTakedownCast) <= threshold

    elseif cond.type == "takedown_active" then
        return now < s.takedownUntil

    elseif cond.type == "boomstick_on_cd" then
        if s.lastBoomstickCast == 0 then return false end
        return (now - s.lastBoomstickCast) < BOOMSTICK_COOLDOWN

    end

    return nil
end

------------------------------------------------------------------------
-- Debug output
------------------------------------------------------------------------

function Profile:GetDebugLines()
    local s = self.state
    local now = GetTime()
    local tdRemaining = s.takedownUntil - now

    local wfbLine = "unknown"
    if C_Spell and C_Spell.GetSpellCharges then
        local ok, info = pcall(C_Spell.GetSpellCharges, SPELLS.WildfireBomb)
        if ok and info and info.currentCharges then
            if not (issecretvalue and issecretvalue(info.currentCharges)) then
                wfbLine = string.format("%d/%d", info.currentCharges, info.maxCharges)
            end
        end
    end

    return {
        "  Takedown: " .. (tdRemaining > 0
            and string.format("%.1fs remaining", tdRemaining)
            or "inactive"),
        "  WFB: " .. wfbLine,
    }
end

------------------------------------------------------------------------
-- Phase detection
------------------------------------------------------------------------

function Profile:GetPhase()
    if not UnitAffectingCombat("player") then return nil end
    local now = GetTime()
    local s = self.state
    if now < s.takedownUntil then return "Burst" end
    return nil
end

------------------------------------------------------------------------
-- Register
------------------------------------------------------------------------

Engine:RegisterProfile(Profile)

if TrueShot.CustomProfile then
    TrueShot.CustomProfile.RegisterConditionSchema("Hunter.SV.Sentinel", {
        { id = "takedown_just_cast", label = "Takedown Just Cast",
          params = { { field = "seconds", fieldType = "number", default = 5, label = "Seconds window" } } },
        { id = "takedown_active",   label = "Takedown Active",           params = {} },
        { id = "boomstick_on_cd",   label = "Boomstick On Cooldown",     params = {} },
    })
end
