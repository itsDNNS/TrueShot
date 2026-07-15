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
--   This profile is the first consumer of State/CDLedger. Wild Thrash still
--   uses the ledger-owned timer. Bestial Wrath originally migrated too, but
--   issue #93 moved BW back to a profile-local cast timer after live Pack
--   Leader reports showed the ledger-backed BW resurfacing path was unreliable
--   in this profile. Legacy `bw_on_cd` / `wt_on_cd` conditions remain so
--   user-forked custom profiles in SavedVariables keep working.

local Engine = TrueShot.Engine
local BW_COOLDOWN = 30
local BARBED_RECENT_WINDOW = 1.35

local function ReadCurrentCharges(spellID)
    if not C_Spell or not C_Spell.GetSpellCharges then return nil end
    local ok, charges = pcall(C_Spell.GetSpellCharges, spellID)
    if not ok or (issecretvalue and issecretvalue(charges)) then return nil end
    if charges == nil or type(charges) ~= "table" then return nil end
    local currentCharges = charges.currentCharges
    if issecretvalue and issecretvalue(currentCharges) then return nil end
    if type(currentCharges) ~= "number" then return nil end
    return currentCharges
end

------------------------------------------------------------------------
-- Profile definition
------------------------------------------------------------------------

local Profile = {
    id = "Hunter.BM.PackLeader",
    displayName = "BM Pack Leader",
    specID = 253,
    heroTalentSubTreeID = 43,
    -- No markerSpell: this profile serves as the BM fallback
    -- when Dark Ranger's Black Arrow marker does not match
    version = 6,

    state = {
        lastCastWasKC = false,
        lastBWCast = 0,
        lastBarbedShotCast = 0,
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

    -- Hybrid pilot: keep BLACKLIST* rules as hard gates, but choose slot 1 from
    -- explicit buckets plus lightweight filler tiebreaks instead of pure
    -- Experimental PIN/PREFER first-match-wins.
    hybrid = {
        enabled = true,
        bucketOrder = {
            "cooldown",
            "bw_setup",
            "stampede",
            "proc",
            "barbed_filler",
            "cobra_filler",
        },
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
            condition = { type = "bw_on_cd" },
        },

        -- Re-surface Bestial Wrath even when Blizzard AC omits later recasts.
        -- Pack Leader now uses the same local cast-timer pattern as BM Dark
        -- Ranger for BW because the ledger-backed path proved unreliable live
        -- in this profile.
        {
            type = "EXPERIMENTAL_PIN",
            spellID = 19574, -- Bestial Wrath
            reason = "Bestial Wrath",
            condition = { type = "not", inner = { type = "bw_on_cd" } },
        },

        -- [src §ST #2b] Stampede: "your next Kill Command will spawn a Stampede"
        -- after Bestial Wrath. Pin the first KC in the post-BW window to surface
        -- the Stampede trigger even if AC has not prioritised KC yet.
        -- Nature's Ally is satisfied because BW itself clears last_cast_was_kc.
        {
            type = "EXPERIMENTAL_PIN",
            spellID = 34026, -- Kill Command
            reason = "Stampede",
            condition = { type = "stampede_available" },
        },

        -- [src §ST #1] "Kill Command on cooldown with Nature's Ally up" - the KC
        -- proc glow (Alpha Predator / Call of the Wild / Howl of the Pack Leader)
        -- is a direct non-secret signal for a Nature's-Ally-buffed KC that AC does
        -- not always prioritise on position 1.
        {
            type = "EXPERIMENTAL_PIN",
            spellID = 34026, -- Kill Command
            reason = "KC Proc",
            condition = {
                type = "and",
                left  = { type = "spell_glowing", spellID = 34026 },
                right = { type = "not", inner = { type = "last_cast_was_kc" } },
            },
        },

        -- [src §ST #4] Once BW / Stampede / KC proc windows are handled, Barbed
        -- Shot is the first Pack Leader filler. Surface it proactively when KC
        -- is not currently the right immediate cast: either because we just
        -- pressed KC and need a Nature's Ally weave, or because KC is not
        -- actually castable yet.
        {
            type = "EXPERIMENTAL_PREFER",
            spellID = 217200, -- Barbed Shot
            reason = "Barbed Shot Filler",
            condition = {
                type = "and",
                left = {
                    type = "or",
                    left  = { type = "last_cast_was_kc" },
                    right = { type = "not", inner = { type = "castable", spellID = 34026 } },
                },
                right = {
                    type = "and",
                    left  = { type = "spell_charges", spellID = 217200, op = ">=", value = 1 },
                    right = { type = "not", inner = { type = "barbed_recent" } },
                },
            },
        },

        -- [src §ST #5] Cobra Shot is the final fallback filler. Use it when
        -- KC is not the immediate play and Barbed Shot has no available charge.
        {
            type = "EXPERIMENTAL_PREFER",
            spellID = 56641, -- Cobra Shot
            reason = "Cobra Shot Filler",
            condition = {
                type = "and",
                left = {
                    type = "or",
                    left  = { type = "last_cast_was_kc" },
                    right = { type = "not", inner = { type = "castable", spellID = 34026 } },
                },
                right = {
                    type = "or",
                    left = { type = "barbed_recent" },
                    right = {
                        type = "not",
                        inner = { type = "spell_charges", spellID = 217200, op = ">=", value = 1 },
                    },
                },
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

        -- Focus no longer hard-blacklists Cobra Shot in the hybrid pilot.
        -- The BM Focus read remains heuristic under docs/API_CONSTRAINTS.md, so
        -- it may only influence low-confidence scoring, never legality.
    },
}

------------------------------------------------------------------------
-- State machine
------------------------------------------------------------------------

function Profile:ResetState()
    self.state.lastCastWasKC = false
    self.state.lastBWCast = 0
    self.state.lastBarbedShotCast = 0
    self.state.stampedeAvailable = false
end

function Profile:OnSpellCast(spellID)
    local now = GetTime()
    local s = self.state

    if spellID == 19574 then -- Bestial Wrath
        s.lastBWCast = now
        s.lastCastWasKC = false
        s.stampedeAvailable = true -- first KC after BW will trigger Stampede

    elseif spellID == 217200 then -- Barbed Shot
        s.lastBarbedShotCast = now
        s.lastCastWasKC = false

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
-- `bw_on_cd` / `wt_on_cd` remain for backward-compat. `bw_on_cd` is profile-
-- local because the ledger-backed BW path regressed live in BM Pack Leader;
-- `wt_on_cd` still delegates to the ledger.
------------------------------------------------------------------------

function Profile:EvalCondition(cond)
    local s = self.state

    if cond.type == "last_cast_was_kc" then
        return s.lastCastWasKC

    elseif cond.type == "stampede_available" then
        return s.stampedeAvailable

    elseif cond.type == "bw_on_cd" then
        if s.lastBWCast == 0 then return false end
        return (GetTime() - s.lastBWCast) < BW_COOLDOWN

    elseif cond.type == "barbed_recent" then
        if s.lastBarbedShotCast == 0 then return false end
        return (GetTime() - s.lastBarbedShotCast) < (cond.seconds or BARBED_RECENT_WINDOW)

    elseif cond.type == "wt_on_cd" then
        -- Legacy shim: Wild Thrash on cooldown.
        if TrueShot.CDLedger then
            return TrueShot.CDLedger:IsOnCooldown(1264359)
        end
        return false

    end

    return nil -- not handled by this profile
end

function Profile:GetBestialWrathRemaining()
    if not self.state.lastBWCast or self.state.lastBWCast == 0 then
        return 0
    end
    return math.max(0, BW_COOLDOWN - (GetTime() - self.state.lastBWCast))
end

------------------------------------------------------------------------
-- Debug output
------------------------------------------------------------------------

function Profile:GetDebugLines()
    local s = self.state
    local bwRemaining = self:GetBestialWrathRemaining()
    return {
        "  BW CD: " .. (bwRemaining > 0
            and string.format("%.1fs remaining", bwRemaining)
            or "ready"),
        "  Barbed recent: " .. tostring(self:EvalCondition({ type = "barbed_recent" })),
        "  Last cast was KC: " .. tostring(s.lastCastWasKC),
        "  Stampede armed: " .. tostring(s.stampedeAvailable),
    }
end

function Profile:GetHybridBucket(spellID, context)
    local kcUnavailable = self.state.lastCastWasKC or not Engine:IsSpellCastable(34026)
    local barbedReady = Engine:EvalCondition({ type = "spell_charges", spellID = 217200, op = ">=", value = 1 })
    local barbedRecent = self:EvalCondition({ type = "barbed_recent" })
    local bwRemaining = self:GetBestialWrathRemaining()

    if spellID == 19574 and not self:EvalCondition({ type = "bw_on_cd" }) then
        return "cooldown"
    end

    if spellID == 217200 and barbedReady and not barbedRecent and bwRemaining > 0 and bwRemaining <= 3 then
        return "bw_setup"
    end

    if spellID == 34026 and self.state.stampedeAvailable then
        return "stampede"
    end

    if spellID == 34026 and Engine:IsSpellGlowing(34026) then
        return "proc"
    end

    if spellID == 217200 and kcUnavailable and barbedReady and not barbedRecent then
        return "barbed_filler"
    end

    if spellID == 56641 and kcUnavailable and (barbedRecent or not barbedReady) then
        return "cobra_filler"
    end

    return nil
end

function Profile:GetHybridScore(spellID, bucketName, context)
    if bucketName == "cooldown" then
        return 100, "Bestial Wrath", "bucket=cooldown"
    end

    if bucketName == "bw_setup" then
        local score = 95
        if context.baseSpell == spellID then
            score = score + 1
        end
        return score, "BW Setup", "bucket=bw_setup bw_remaining=" .. string.format("%.1f", self:GetBestialWrathRemaining())
    end

    if bucketName == "stampede" then
        return 100, "Stampede", "bucket=stampede"
    end

    if bucketName == "proc" then
        local score = 80
        if context.baseSpell == spellID then
            score = score + 5
        end
        return score, "KC Proc", "bucket=proc glow=1"
    end

    if bucketName == "barbed_filler" then
        local score = 20
        local chargeBonus = 0
        chargeBonus = ReadCurrentCharges(217200) or 0
        score = score + chargeBonus
        if context.baseSpell == spellID then
            score = score + 1
        end
        return score, "Barbed Shot Filler", "bucket=barbed_filler charges=" .. tostring(chargeBonus)
    end

    if bucketName == "cobra_filler" then
        local score = 10
        local lowFocus = Engine:EvalCondition({
            type = "resource",
            powerType = 2,
            op = "<",
            value = 65,
        })
        if lowFocus then
            score = score - 2
        end
        if context.baseSpell == spellID then
            score = score + 1
        end
        return score, "Cobra Shot Filler", "bucket=cobra_filler low_focus=" .. tostring(lowFocus)
    end

    return 0, nil, nil
end

------------------------------------------------------------------------
-- Phase detection (for overlay display)
--
-- "Burst" while the Bestial Wrath buff window is assumed active (~15s after
-- the cast). Uses the profile-local BW cast timestamp; this keeps the visible
-- burst window aligned with the same signal that gates BW resurfacing.
------------------------------------------------------------------------

function Profile:GetPhase()
    if not UnitAffectingCombat("player") then return nil end
    if self.state.lastBWCast > 0 and (GetTime() - self.state.lastBWCast) < 15 then
        return "Burst"
    end
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
        { id = "barbed_recent",      label = "Barbed Shot Cast Recently",          params = { "seconds?" } },
        { id = "bw_on_cd",           label = "Bestial Wrath On Cooldown (legacy, use cd_remaining)", params = {} },
        { id = "wt_on_cd",           label = "Wild Thrash On Cooldown (legacy, use cd_remaining)",   params = {} },
    })
end
