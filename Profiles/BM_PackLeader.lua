-- TrueShot Profile: Beast Mastery / Pack Leader (specID 253)
-- Hero path: Pack Leader (no markerSpell — BM fallback when Dark Ranger's Black Arrow marker is not known)
--
-- PRIMARY SOURCE
--   Author:        Azortharion
--   Guide:         Beast Mastery Hunter DPS Rotation, Cooldowns, and Abilities - Midnight Season 1
--   URL:           https://www.icy-veins.com/wow/beast-mastery-hunter-pve-dps-rotation-cooldowns-abilities
--   Guide updated: 2026-04-10
--   Verified:      2026-04-18
--   Patch:         12.0.4 (Midnight Season 1)
--
-- CROSS-CHECK SOURCES
--   SimC midnight branch: ActionPriorityLists/default/hunter_beast_mastery.simc
--   Wowhead:              https://www.wowhead.com/guide/classes/hunter/beast-mastery/rotation-cooldowns-pve-dps
--                         (Tarlo, Patch 12.0.1, updated 2026-03-21)
--
-- DESIGN SCOPE
--   Overlay profile on Blizzard Assisted Combat.
--   Does NOT simulate hidden buff/resource state (see docs/API_CONSTRAINTS.md).
--   Inline tags "[src §<section> #N]" reference the priority number in the primary source.
--
-- PILOT MIGRATION (v0.25.0, issue #84)
--   This profile is the first consumer of State/CDLedger. Cooldown tracking for
--   Bestial Wrath and Wild Thrash no longer lives on profile-local timestamps;
--   the ledger owns `cd_remaining(spellID, op, value)`. The legacy
--   `bw_on_cd` / `wt_on_cd` conditions remain as thin EvalCondition shims so
--   user-forked custom profiles in SavedVariables keep working.

local Engine = TrueShot.Engine

------------------------------------------------------------------------
-- Profile definition
------------------------------------------------------------------------

local Profile = {
    id = "Hunter.BM.PackLeader",
    displayName = "BM Pack Leader",
    specID = 253,
    -- No markerSpell: this profile serves as the BM fallback
    -- when Dark Ranger's Black Arrow marker does not match
    version = 3,

    state = {
        lastCastWasKC = false,
        -- Stampede: armed by Bestial Wrath, consumed on the next Kill Command.
        -- Source: Azortharion 2026-04-10 - "Activate Bestial Wrath. Once activated,
        -- your next Kill Command will spawn a Stampede."
        stampedeAvailable = false,
    },

    rotationalSpells = {
        [34026]   = true, -- Kill Command
        [19574]   = true, -- Bestial Wrath
        [1264359] = true, -- Wild Thrash
        [56641]   = true, -- Cobra Shot
        [217200]  = true, -- Barbed Shot
        [120360]  = true, -- Barrage
        [53351]   = true, -- Kill Shot
    },

    -- [src §AoE #3] Wild Thrash on cooldown in multi-target.
    aoeHint = {
        spellID = 1264359, -- Wild Thrash
        condition = {
            type = "and",
            left  = { type = "in_combat" },
            right = {
                type = "and",
                left  = { type = "target_count", op = ">=", value = 2 },
                right = { type = "cd_ready", spellID = 1264359 },
            },
        },
    },

    rules = {
        -- Filter utility spells (never part of the damage rotation).
        { type = "BLACKLIST", spellID = 883 },    -- Call Pet 1
        { type = "BLACKLIST", spellID = 982 },    -- Revive Pet
        { type = "BLACKLIST", spellID = 147362 }, -- Counter Shot (user preference)

        -- [src §ST #2] "Activate Bestial Wrath" - leave BW available unless on CD.
        -- The shipped profile does NOT gate BW on Barbed Shot charges: v0.9.0 removed
        -- that gate after a prior WCL parse showed top players press BW immediately.
        -- Azortharion text still recommends "dump charges first" - treat that as a
        -- LIVE-verification follow-up rather than a static re-introduction.
        {
            type = "BLACKLIST_CONDITIONAL",
            spellID = 19574,
            condition = { type = "cd_remaining", spellID = 19574, op = ">", value = 0 },
        },

        -- [src §ST #2b] Stampede: "your next Kill Command will spawn a Stampede"
        -- after Bestial Wrath. Pin the first KC in the post-BW window to surface
        -- the Stampede trigger even if AC has not prioritised KC yet.
        -- Nature's Ally is satisfied because BW itself clears last_cast_was_kc.
        {
            type = "PIN",
            spellID = 34026, -- Kill Command
            reason = "Stampede",
            condition = { type = "stampede_available" },
        },

        -- [src §ST #1] "Kill Command on cooldown with Nature's Ally up" - the KC
        -- proc glow (Alpha Predator / Call of the Wild / Howl of the Pack Leader)
        -- is a direct non-secret signal for a Nature's-Ally-buffed KC that AC does
        -- not always prioritise on position 1.
        {
            type = "PIN",
            spellID = 34026, -- Kill Command
            reason = "KC Proc",
            condition = {
                type = "and",
                left  = { type = "spell_glowing", spellID = 34026 },
                right = { type = "not", inner = { type = "last_cast_was_kc" } },
            },
        },

        -- [src §ST "Nature's Ally"] "Never cast Kill Command twice in a row."
        -- Wild Thrash is NOT a valid Nature's Ally filler - the state machine
        -- explicitly preserves last_cast_was_kc across WT casts.
        {
            type = "BLACKLIST_CONDITIONAL",
            spellID = 34026,
            condition = { type = "last_cast_was_kc" },
        },

        -- [src §ST #6 / Focus pooling] Suppress Cobra Shot when Focus is too low
        -- to keep Kill Command castable afterwards. Gate also requires KC to be
        -- castable, so a blocked KC (Nature's Ally, CD) does not leave the queue
        -- empty.
        -- NOTE: The underlying `resource` condition reads UnitPower("player", 2).
        -- docs/API_CONSTRAINTS.md lists BM Focus as secret; docs/BM_ROTATION_REFERENCE.md
        -- "Not Modeled" has a conflicting 2026-04-10 note that the call is readable.
        -- This rule predates the Hunter-1.0 citation pass and is kept as-is pending
        -- a live Focus probe run under `/ts probe`; treat the behaviour as heuristic.
        {
            type = "BLACKLIST_CONDITIONAL",
            spellID = 56641, -- Cobra Shot
            reason = "Focus Pool",
            condition = {
                type = "and",
                left  = { type = "resource", powerType = 2, op = "<", value = 65 },
                right = { type = "usable", spellID = 34026 }, -- KC is castable
            },
        },
    },
}

------------------------------------------------------------------------
-- State machine
------------------------------------------------------------------------

function Profile:ResetState()
    self.state.lastCastWasKC = false
    self.state.stampedeAvailable = false
end

function Profile:OnSpellCast(spellID)
    local s = self.state

    if spellID == 19574 then -- Bestial Wrath
        s.lastCastWasKC = false
        s.stampedeAvailable = true -- first KC after BW will trigger Stampede

    elseif spellID == 1264359 then -- Wild Thrash
        -- NOTE: Wild Thrash does NOT grant Nature's Ally.
        -- Do NOT clear lastCastWasKC here. KC -> WT -> KC is invalid.

    elseif spellID == 34026 then -- Kill Command
        s.lastCastWasKC = true
        s.stampedeAvailable = false -- consumed the Stampede proc window

    else
        s.lastCastWasKC = false
    end
end

function Profile:OnCombatEnd()
    self.state.lastCastWasKC = false
    self.state.stampedeAvailable = false
end

------------------------------------------------------------------------
-- Profile-specific condition evaluation
--
-- `bw_on_cd` / `wt_on_cd` are kept as backward-compat shims that delegate to
-- the CDLedger. User-forked custom profiles stored in SavedVariables may still
-- reference these IDs; new rules should use `cd_remaining(spellID, op, value)`.
------------------------------------------------------------------------

function Profile:EvalCondition(cond)
    local s = self.state

    if cond.type == "last_cast_was_kc" then
        return s.lastCastWasKC

    elseif cond.type == "stampede_available" then
        return s.stampedeAvailable

    elseif cond.type == "bw_on_cd" then
        -- Legacy shim: Bestial Wrath on cooldown.
        if TrueShot.CDLedger then
            return TrueShot.CDLedger:IsOnCooldown(19574)
        end
        return false

    elseif cond.type == "wt_on_cd" then
        -- Legacy shim: Wild Thrash on cooldown.
        if TrueShot.CDLedger then
            return TrueShot.CDLedger:IsOnCooldown(1264359)
        end
        return false

    end

    return nil -- not handled by this profile
end

------------------------------------------------------------------------
-- Debug output
------------------------------------------------------------------------

function Profile:GetDebugLines()
    local s = self.state
    local bwRemaining = TrueShot.CDLedger and TrueShot.CDLedger:SecondsUntilReady(19574) or 0
    return {
        "  BW CD: " .. (bwRemaining > 0
            and string.format("%.1fs remaining", bwRemaining)
            or "ready"),
        "  Last cast was KC: " .. tostring(s.lastCastWasKC),
        "  Stampede armed: " .. tostring(s.stampedeAvailable),
    }
end

------------------------------------------------------------------------
-- Phase detection (for overlay display)
--
-- "Burst" while the Bestial Wrath buff window is assumed active (~15s after
-- the cast). Uses CDLedger's cast-timestamp rather than a duplicated profile
-- timer.
------------------------------------------------------------------------

function Profile:GetPhase()
    if not UnitAffectingCombat("player") then return nil end
    if not TrueShot.CDLedger then return nil end
    local sinceCast = TrueShot.CDLedger:SecondsSinceCast(19574)
    if sinceCast and sinceCast < 15 then return "Burst" end
    return nil
end

------------------------------------------------------------------------
-- Register
------------------------------------------------------------------------

Engine:RegisterProfile(Profile)

if TrueShot.CustomProfile then
    -- Schema includes deprecated `bw_on_cd` / `wt_on_cd` so Visual Rule Builder
    -- nodes authored before v0.25.0 still round-trip through the picker. New
    -- rules should prefer the engine-level `cd_ready` / `cd_remaining` entries
    -- (registered in CustomProfile). The shim EvalCondition cases above
    -- delegate both legacy IDs to the CDLedger.
    TrueShot.CustomProfile.RegisterConditionSchema("Hunter.BM.PackLeader", {
        { id = "last_cast_was_kc",   label = "Last Cast Was Kill Command",         params = {} },
        { id = "stampede_available", label = "Stampede Armed (first KC after BW)", params = {} },
        { id = "bw_on_cd",           label = "Bestial Wrath On Cooldown (legacy, use cd_remaining)", params = {} },
        { id = "wt_on_cd",           label = "Wild Thrash On Cooldown (legacy, use cd_remaining)",   params = {} },
    })
end
