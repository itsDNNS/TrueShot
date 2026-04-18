-- TrueShot Profile: Marksmanship / Sentinel (specID 254)
-- Hero path: Sentinel (no markerSpell - MM fallback when Dark Ranger's Black Arrow marker is not known)
-- Cast-event state machine for Trueshot window, Volley anti-overlap,
-- and Moonlight Chakram filler timing.
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
--   Wowhead MM Hero:      https://www.wowhead.com/guide/classes/hunter/marksmanship/hero-talents
--                         "When you activate Trueshot, the Trueshot button itself will turn
--                          into Moonlight Chakram, a filler ability that does heavy damage."
--                         => Chakram is castable only inside the Trueshot window on Sentinel;
--                            the BLACKLIST_CONDITIONAL below mirrors that spell-availability fact.
--
-- DESIGN SCOPE
--   Overlay profile on Blizzard Assisted Combat.
--   Sentinel lane is intentionally leaner than Dark Ranger: Trueshot/Volley anti-
--   overlap, post-Rapid-Fire Trueshot timing, and Moonlight Chakram as a late
--   Trueshot-window filler only.
--   Inline tags "[src §<section> #N]" reference the priority number in the primary source.

local Engine = TrueShot.Engine

local TRUESHOT_DURATION = 19  -- Sentinel gets 19s (not 15s); timer is fallback only

-- Prefer aura check over timer (handles spell replacement + variable duration)
local function IsTrueshotBuffActive(state)
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, 288613)
        if ok then return aura ~= nil end
    end
    return GetTime() < state.trueshotUntil
end

------------------------------------------------------------------------
-- Spell IDs
------------------------------------------------------------------------

local SPELLS = {
    Trueshot         = 288613,
    RapidFire        = 257044,
    AimedShot        = 19434,
    Volley           = 260243,
    MoonlightChakram = 1264902,
    CounterShot      = 147362,
    CallPet1         = 883,
    RevivePet        = 982,
}

------------------------------------------------------------------------
-- Profile definition
------------------------------------------------------------------------

local Profile = {
    id = "Hunter.MM.Sentinel",
    displayName = "MM Sentinel",
    specID = 254,
    -- No markerSpell: this profile serves as the MM fallback
    -- when Dark Ranger's Black Arrow marker does not match
    version = 1,

    state = {
        lastRapidFireCast = 0,
        lastTrueshotCast = 0,
        trueshotUntil = 0,
        lastVolleyCast = 0,
    },

    rotationalSpells = {
        [288613]  = true, -- Trueshot
        [257044]  = true, -- Rapid Fire
        [260243]  = true, -- Volley
        [19434]   = true, -- Aimed Shot
        [1264902] = true, -- Moonlight Chakram
        [56641]   = true, -- Steady Shot
        [53351]   = true, -- Kill Shot
        [185358]  = true, -- Arcane Shot
    },

    rules = {
        -- Filter utility spells (never part of the damage rotation).
        { type = "BLACKLIST", spellID = SPELLS.CallPet1 },
        { type = "BLACKLIST", spellID = SPELLS.RevivePet },
        { type = "BLACKLIST", spellID = SPELLS.CounterShot },

        -- [src §Sequencing "anti-overlap"] "Never cast Volley and Trueshot back-
        -- to-back in any order." Enforced in both directions.
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

        -- [src §Sequencing "Rapid Fire into Trueshot"] "Ideal setup follows
        -- pattern: Rapid Fire -> Trueshot -> Aimed Shot." Pair the RF-recency
        -- signal with the legal ac_suggested readiness gate for TS.
        {
            type = "PIN",
            spellID = SPELLS.Trueshot,
            reason = "Post-RF Window",
            condition = {
                type = "and",
                left  = { type = "ac_suggested", spellID = SPELLS.Trueshot },
                right = {
                    type = "and",
                    left  = { type = "rapid_fire_recent", seconds = 3 },
                    right = { type = "not", inner = { type = "volley_recent", seconds = 2 } },
                },
            },
        },

        -- [src §Sentinel Hero, Wowhead] Moonlight Chakram replaces the Trueshot
        -- button during the Trueshot buff, so it can only be cast inside the TS
        -- window on Sentinel. Mirror that spell-availability fact by blacklisting
        -- Chakram outside trueshot_active (guards against stray AC recommendations).
        {
            type = "BLACKLIST_CONDITIONAL",
            spellID = SPELLS.MoonlightChakram,
            condition = { type = "not", inner = { type = "trueshot_active" } },
        },

        -- [src §ST #7] "Moonlight Chakram (filler when no Aimed Shots)" - elevate
        -- Chakram only when AC already recommends it AND Aimed Shot has no
        -- charges. PREFER (not PIN) so AC's own ordering wins when it already
        -- leads with Chakram.
        {
            type = "PREFER",
            spellID = SPELLS.MoonlightChakram,
            reason = "Chakram",
            condition = {
                type = "and",
                left  = { type = "ac_suggested", spellID = SPELLS.MoonlightChakram },
                right = {
                    type = "and",
                    left  = { type = "trueshot_active" },
                    right = { type = "not", inner = { type = "aimed_shot_ready" } },
                },
            },
        },
    },
}

------------------------------------------------------------------------
-- State machine
------------------------------------------------------------------------

function Profile:ResetState()
    self.state.lastRapidFireCast = 0
    self.state.lastTrueshotCast = 0
    self.state.trueshotUntil = 0
    self.state.lastVolleyCast = 0
end

function Profile:OnSpellCast(spellID)
    local now = GetTime()
    local s = self.state

    if spellID == SPELLS.Trueshot then
        s.lastTrueshotCast = now
        s.trueshotUntil = now + TRUESHOT_DURATION

    elseif spellID == SPELLS.RapidFire then
        s.lastRapidFireCast = now

    elseif spellID == SPELLS.Volley then
        s.lastVolleyCast = now
    end
end

function Profile:OnCombatEnd()
    self.state.trueshotUntil = 0
end

------------------------------------------------------------------------
-- Profile-specific condition evaluation
------------------------------------------------------------------------

function Profile:EvalCondition(cond)
    local s = self.state
    local now = GetTime()

    if cond.type == "trueshot_just_cast" then
        local threshold = cond.seconds or 2
        return s.lastTrueshotCast > 0 and (now - s.lastTrueshotCast) <= threshold

    elseif cond.type == "trueshot_active" then
        return IsTrueshotBuffActive(s)

    elseif cond.type == "rapid_fire_recent" then
        local threshold = cond.seconds or 3
        return s.lastRapidFireCast > 0 and (now - s.lastRapidFireCast) <= threshold

    elseif cond.type == "volley_recent" then
        local threshold = cond.seconds or 2
        return s.lastVolleyCast > 0 and (now - s.lastVolleyCast) <= threshold

    elseif cond.type == "aimed_shot_ready" then
        if C_Spell and C_Spell.GetSpellCharges then
            local ok, info = pcall(C_Spell.GetSpellCharges, SPELLS.AimedShot)
            if ok and info and info.currentCharges then
                if issecretvalue and issecretvalue(info.currentCharges) then
                    return false
                end
                return info.currentCharges > 0
            end
        end
        return false
    end

    return nil
end

------------------------------------------------------------------------
-- Debug output
------------------------------------------------------------------------

function Profile:GetDebugLines()
    local s = self.state
    local now = GetTime()
    local buffActive = IsTrueshotBuffActive(s)
    local tsRemaining = s.trueshotUntil - now
    return {
        "  Trueshot: " .. (buffActive
            and (tsRemaining > 0 and string.format("active (%.1fs timer)", tsRemaining) or "active (buff)")
            or "inactive"),
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
    if IsTrueshotBuffActive(self.state) then return "Burst" end
    return nil
end

------------------------------------------------------------------------
-- Register
------------------------------------------------------------------------

Engine:RegisterProfile(Profile)

if TrueShot.CustomProfile then
    TrueShot.CustomProfile.RegisterConditionSchema("Hunter.MM.Sentinel", {
        { id = "trueshot_just_cast", label = "Trueshot Just Cast",
          params = { { field = "seconds", fieldType = "number", default = 2, label = "Seconds window" } } },
        { id = "trueshot_active",   label = "Trueshot Active",   params = {} },
        { id = "rapid_fire_recent", label = "Rapid Fire Recent",
          params = { { field = "seconds", fieldType = "number", default = 3, label = "Seconds window" } } },
        { id = "volley_recent",     label = "Volley Recent",
          params = { { field = "seconds", fieldType = "number", default = 2, label = "Seconds window" } } },
        { id = "aimed_shot_ready",  label = "Aimed Shot Ready",  params = {} },
    })
end
