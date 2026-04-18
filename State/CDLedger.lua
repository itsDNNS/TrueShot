-- TrueShot State/CDLedger: central cooldown tracker for Hunter rotational spells
--
-- Replaces scattered per-profile timer constants (BW_COOLDOWN, WT_COOLDOWN,
-- BOOMSTICK_COOLDOWN) with a single data-driven, haste-aware ledger driven by
-- UNIT_SPELLCAST_SUCCEEDED. Exposes engine conditions `cd_ready` and
-- `cd_remaining` so profiles can drop their local `*_on_cd`-shaped conditions.
--
-- PRIMARY SIGNALS
--   UNIT_SPELLCAST_SUCCEEDED (player)  - cast detection, timer start
--   GetSpellBaseCooldown(spellID)      - unmodified base CD in ms (non-secret,
--                                        Patch 4.3.0+, confirmed readable on
--                                        Midnight 12.0.4 per warcraft.wiki.gg)
--   UnitSpellHaste("player")           - haste scaling, guarded by issecretvalue
--                                        (wiki lists SecretArguments flag, so we
--                                        degrade to "no scaling" when secret)
--
-- NOT USED
--   C_Spell.GetSpellCooldown is per-spell gated by
--   C_Secrets.ShouldSpellCooldownBeSecret on Midnight with no published Hunter
--   whitelist. Reading it would tie the ledger to secret-gate drift every patch.
--   The cast-event + base-CD path is deterministic and survives any gate change.
--
-- STRATEGY
--   Cast-event local timer is PRIMARY. Live base-CD + haste are read through
--   pcall+issecretvalue guards and fall back to hardcoded defaults if the API
--   returns 0/nil/secret. This matches the "degrade safely" rule in
--   docs/FRAMEWORK.md and the "heuristic state" model in docs/API_CONSTRAINTS.md.

TrueShot = TrueShot or {}
TrueShot.CDLedger = TrueShot.CDLedger or {}

local CDLedger = TrueShot.CDLedger

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

------------------------------------------------------------------------
-- Spec (data-driven, one entry per tracked spell)
--
-- base_ms       : fallback if GetSpellBaseCooldown returns 0/nil/secret
-- haste_scaled  : apply (1 + haste/100) divisor to the base CD
-- reset_by      : list of spellIDs whose cast fully clears this spell's timer
-- reduce_by     : map of spellID -> seconds subtracted from the remaining CD
--
-- Sources per entry are cited inline (URL + guide date + patch).
------------------------------------------------------------------------

CDLedger.spec = {
    -- Bestial Wrath (BM): 30s flat. Source: Azortharion, Icy Veins BM Hunter
    -- Rotation, guide updated 2026-04-10, Patch 12.0.4.
    -- URL: https://www.icy-veins.com/wow/beast-mastery-hunter-pve-dps-rotation-cooldowns-abilities
    [19574]   = { base_ms = 30000, haste_scaled = false },

    -- Wild Thrash (BM): 8s flat. Source: Azortharion 2026-04-10 (same URL),
    -- "8s CD = 100% Beast Cleave uptime if used on CD" (BM Rotation Reference).
    [1264359] = { base_ms = 8000,  haste_scaled = false },

    -- Boomstick (SV): 30s flat. Source: Azortharion, Icy Veins SV Hunter
    -- Rotation, guide updated 2026-03-27, Patch 12.0.4.
    -- URL: https://www.icy-veins.com/wow/survival-hunter-pve-dps-rotation-cooldowns-abilities
    [1261193] = { base_ms = 30000, haste_scaled = false },
}

-- Per-spell ledger state. Keyed by spellID; cleared entry means "not on CD".
-- cast_time      : GetTime() at OnSpellCastSucceeded
-- expected_ready : GetTime() + effective CD seconds
CDLedger.state = {}

------------------------------------------------------------------------
-- Base CD resolution
--
-- Prefer the live GetSpellBaseCooldown read (it already reflects talent CD
-- reductions for the player) with graceful fallback to the hardcoded base_ms.
------------------------------------------------------------------------

local function ResolveBaseSeconds(spellID)
    local entry = CDLedger.spec[spellID]
    if not entry then return nil end

    local liveMs = nil
    if GetSpellBaseCooldown then
        local ok, cdMs, _gcdMs = pcall(GetSpellBaseCooldown, spellID)
        if ok and type(cdMs) == "number" and cdMs > 0 and not IsSecret(cdMs) then
            liveMs = cdMs
        end
    end

    local baseMs = liveMs or entry.base_ms
    local seconds = baseMs / 1000

    if entry.haste_scaled and UnitSpellHaste then
        local ok, hastePct = pcall(UnitSpellHaste, "player")
        if ok and type(hastePct) == "number" and not IsSecret(hastePct) then
            seconds = seconds / (1 + hastePct / 100)
        end
        -- else: degrade silently to "no haste scaling" rather than lie
    end

    return seconds
end

------------------------------------------------------------------------
-- Cast-event dispatch
--
-- Called from Core.lua's UNIT_SPELLCAST_SUCCEEDED handler for the local player.
-- Same input as Engine:OnSpellCast, so the two calls run alongside each other.
------------------------------------------------------------------------

function CDLedger:OnSpellCastSucceeded(spellID)
    if not spellID or IsSecret(spellID) then return end

    local now = GetTime()

    -- Start this spell's CD if we track it.
    local entry = self.spec[spellID]
    if entry then
        local cdSeconds = ResolveBaseSeconds(spellID)
        if cdSeconds and cdSeconds > 0 then
            self.state[spellID] = {
                cast_time = now,
                expected_ready = now + cdSeconds,
            }
        end
    end

    -- Apply resets/reductions keyed by the spell we just observed.
    for targetID, targetSpec in pairs(self.spec) do
        if targetSpec.reset_by and targetSpec.reset_by[spellID] then
            self.state[targetID] = nil
        end
        if targetSpec.reduce_by and targetSpec.reduce_by[spellID] then
            local st = self.state[targetID]
            if st then
                st.expected_ready = st.expected_ready - targetSpec.reduce_by[spellID]
                if st.expected_ready <= now then
                    self.state[targetID] = nil
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- Query surface (used by Engine conditions cd_ready / cd_remaining)
------------------------------------------------------------------------

function CDLedger:IsOnCooldown(spellID)
    local st = self.state[spellID]
    if not st then return false end
    return GetTime() < st.expected_ready
end

function CDLedger:SecondsUntilReady(spellID)
    local st = self.state[spellID]
    if not st then return 0 end
    local remaining = st.expected_ready - GetTime()
    if remaining > 0 then return remaining end
    return 0
end

-- Seconds since the most recent observed cast of `spellID`, or nil if the
-- ledger has never seen a cast of that spell. Used by profiles that need the
-- cast-timestamp semantic (e.g. a "Burst" phase that outlasts the CD window).
function CDLedger:SecondsSinceCast(spellID)
    local st = self.state[spellID]
    if not st then return nil end
    return GetTime() - st.cast_time
end

------------------------------------------------------------------------
-- Lifecycle
--
-- Intentionally NO reset on combat end: a Bestial Wrath cast near the end of a
-- pull is still on cooldown when the next pull starts. OnCombatEnd is kept for
-- future per-spec reset flags.
------------------------------------------------------------------------

function CDLedger:Reset()
    self.state = {}
end

function CDLedger:OnCombatEnd()
    -- no-op by design
end

------------------------------------------------------------------------
-- Debug surface
------------------------------------------------------------------------

function CDLedger:GetDebugLines()
    local lines = {}
    for spellID, st in pairs(self.state) do
        local name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or tostring(spellID)
        local remaining = st.expected_ready - GetTime()
        if remaining > 0 then
            lines[#lines + 1] = string.format("  %s (%d): %.1fs remaining", name, spellID, remaining)
        end
    end
    return lines
end

return CDLedger
