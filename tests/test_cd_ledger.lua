-- TrueShot State/CDLedger logic tests
--
-- Drives the ledger through cast events, time advances, resets, reductions,
-- haste scaling, and non-tracked spells to cover the surfaces the pilot BM PL
-- migration depends on plus the architectural hooks for follow-up spell
-- additions.
--
-- Run from the addon root: lua tests/test_cd_ledger.lua

------------------------------------------------------------------------
-- WoW client stubs
------------------------------------------------------------------------

local _time = 1000.0
local function set_time(t) _time = t end
local function advance_time(dt) _time = _time + dt end

_G.GetTime = function() return _time end
_G.issecretvalue = function(_) return false end
_G.pcall = pcall

-- The ledger's ResolveBaseSeconds path prefers the live GetSpellBaseCooldown
-- read when it returns a positive, non-secret millisecond value. Tests flip
-- between hardcoded-only, live-override, and secret to exercise all branches.
local _base_cd_override = {}
local _base_cd_returns_secret = false
_G.GetSpellBaseCooldown = function(spellID)
    if _base_cd_returns_secret then
        return "SECRET_MARKER", 0
    end
    local override = _base_cd_override[spellID]
    if override then return override, 0 end
    return 0, 0 -- ledger falls back to spec.base_ms
end

-- Haste stub: number of percent points (e.g. 30 == 30% haste). nil disables
-- the API entirely so the ledger's "UnitSpellHaste == nil" branch is covered.
local _player_haste = 0
local _haste_api_present = true
_G.UnitSpellHaste = nil
local function install_haste_api()
    _G.UnitSpellHaste = function(unit)
        if unit ~= "player" then return 0 end
        return _player_haste
    end
    _haste_api_present = true
end
local function remove_haste_api()
    _G.UnitSpellHaste = nil
    _haste_api_present = false
end
install_haste_api()

-- C_Spell stub: only needed for the debug helper that looks up spell names.
_G.C_Spell = _G.C_Spell or {}
_G.C_Spell.GetSpellName = function(id) return "Spell#" .. tostring(id) end

TrueShot = {}

dofile("State/CDLedger.lua")
local CDLedger = TrueShot.CDLedger

------------------------------------------------------------------------
-- Test harness
------------------------------------------------------------------------

local passed, failed = 0, 0

local function test(name, fn)
    CDLedger:Reset()
    set_time(1000.0)
    _base_cd_override = {}
    _base_cd_returns_secret = false
    _player_haste = 0
    install_haste_api()

    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. name .. " -- " .. tostring(err))
    end
end

local function assert_true(v, msg)
    if not v then error((msg or "expected true") .. " got " .. tostring(v)) end
end

local function assert_false(v, msg)
    if v then error((msg or "expected false") .. " got " .. tostring(v)) end
end

local function assert_near(a, b, tolerance, msg)
    if math.abs(a - b) > tolerance then
        error((msg or "") .. " expected ~" .. tostring(b) .. " got " .. tostring(a))
    end
end

------------------------------------------------------------------------
-- Spec coverage
------------------------------------------------------------------------

test("Spec covers Bestial Wrath, Wild Thrash, Boomstick", function()
    assert_true(CDLedger.spec[19574],   "Bestial Wrath (19574) in spec")
    assert_true(CDLedger.spec[1264359], "Wild Thrash (1264359) in spec")
    assert_true(CDLedger.spec[1261193], "Boomstick (1261193) in spec")
end)

test("Non-tracked spell is ignored on cast", function()
    CDLedger:OnSpellCastSucceeded(123456789)
    assert_false(CDLedger:IsOnCooldown(123456789),
        "Ledger must not invent state for unknown spells")
end)

------------------------------------------------------------------------
-- Base-CD path (no live override)
------------------------------------------------------------------------

test("Bestial Wrath triggers 30s timer from spec fallback", function()
    CDLedger:OnSpellCastSucceeded(19574)
    assert_true(CDLedger:IsOnCooldown(19574), "BW should be on CD immediately after cast")
    assert_near(CDLedger:SecondsUntilReady(19574), 30, 0.01, "initial remaining")
    advance_time(15)
    assert_near(CDLedger:SecondsUntilReady(19574), 15, 0.01, "after 15s advance")
    advance_time(20)
    assert_false(CDLedger:IsOnCooldown(19574), "should be ready after 35s")
end)

test("Wild Thrash 8s flat CD", function()
    CDLedger:OnSpellCastSucceeded(1264359)
    advance_time(7)
    assert_true(CDLedger:IsOnCooldown(1264359))
    advance_time(2)
    assert_false(CDLedger:IsOnCooldown(1264359))
end)

test("Boomstick 30s flat CD", function()
    CDLedger:OnSpellCastSucceeded(1261193)
    advance_time(29)
    assert_true(CDLedger:IsOnCooldown(1261193))
    advance_time(2)
    assert_false(CDLedger:IsOnCooldown(1261193))
end)

------------------------------------------------------------------------
-- Live GetSpellBaseCooldown path
------------------------------------------------------------------------

test("Live GetSpellBaseCooldown overrides the hardcoded base", function()
    -- Simulate a talent that reduces BW CD to 25s.
    _base_cd_override[19574] = 25000
    CDLedger:OnSpellCastSucceeded(19574)
    assert_near(CDLedger:SecondsUntilReady(19574), 25, 0.01,
        "Live API value should win over spec fallback")
end)

test("Zero live base falls back to spec", function()
    _base_cd_override[19574] = nil -- stub returns 0
    CDLedger:OnSpellCastSucceeded(19574)
    assert_near(CDLedger:SecondsUntilReady(19574), 30, 0.01,
        "0 from API must trigger spec fallback, not a 0s CD")
end)

test("Secret live base is ignored, spec fallback used", function()
    _base_cd_returns_secret = true
    -- issecretvalue stub returns false for all values; flip just for the
    -- millisecond return here.
    local prev = _G.issecretvalue
    _G.issecretvalue = function(v) return v == "SECRET_MARKER" end
    CDLedger:OnSpellCastSucceeded(19574)
    _G.issecretvalue = prev
    assert_near(CDLedger:SecondsUntilReady(19574), 30, 0.01,
        "Secret API return must degrade to spec fallback")
end)

------------------------------------------------------------------------
-- Haste scaling (no haste-scaled spells in the current spec; validate the
-- path by inserting a temporary spec entry so the architecture is covered)
------------------------------------------------------------------------

test("Haste scaling divides CD when haste_scaled flag is set", function()
    local sentinel_id = 999001
    CDLedger.spec[sentinel_id] = { base_ms = 10000, haste_scaled = true }
    _player_haste = 100 -- 100% haste halves the CD
    CDLedger:OnSpellCastSucceeded(sentinel_id)
    assert_near(CDLedger:SecondsUntilReady(sentinel_id), 5, 0.01,
        "10s base at 100% haste should resolve to 5s")
    CDLedger.spec[sentinel_id] = nil
end)

test("Haste API absent degrades to no scaling", function()
    local sentinel_id = 999002
    CDLedger.spec[sentinel_id] = { base_ms = 10000, haste_scaled = true }
    remove_haste_api()
    CDLedger:OnSpellCastSucceeded(sentinel_id)
    assert_near(CDLedger:SecondsUntilReady(sentinel_id), 10, 0.01,
        "Without UnitSpellHaste the CD must stay at base")
    install_haste_api()
    CDLedger.spec[sentinel_id] = nil
end)

test("Secret haste value is ignored, CD stays at base", function()
    local sentinel_id = 999003
    CDLedger.spec[sentinel_id] = { base_ms = 10000, haste_scaled = true }
    _player_haste = 100
    local prev = _G.issecretvalue
    _G.issecretvalue = function(v) return type(v) == "number" and v == 100 end
    CDLedger:OnSpellCastSucceeded(sentinel_id)
    _G.issecretvalue = prev
    assert_near(CDLedger:SecondsUntilReady(sentinel_id), 10, 0.01,
        "Secret haste read must not be applied; CD stays at unscaled base")
    CDLedger.spec[sentinel_id] = nil
end)

test("haste_scaled=false ignores haste", function()
    _player_haste = 100
    CDLedger:OnSpellCastSucceeded(19574) -- BW is not haste-scaled
    assert_near(CDLedger:SecondsUntilReady(19574), 30, 0.01,
        "Flat CDs must not be scaled by haste")
end)

------------------------------------------------------------------------
-- Reset / reduce hooks (architecture; not yet wired on shipped spells)
------------------------------------------------------------------------

test("reset_by clears the target spell's CD", function()
    local resetter = 999100
    local target   = 999101
    CDLedger.spec[target] = {
        base_ms = 30000,
        haste_scaled = false,
        reset_by = { [resetter] = true },
    }
    CDLedger:OnSpellCastSucceeded(target)
    assert_true(CDLedger:IsOnCooldown(target))
    CDLedger:OnSpellCastSucceeded(resetter)
    assert_false(CDLedger:IsOnCooldown(target),
        "Resetter cast must fully clear the target timer")
    CDLedger.spec[target] = nil
end)

test("reduce_by subtracts seconds from remaining CD", function()
    local reducer = 999200
    local target  = 999201
    CDLedger.spec[target] = {
        base_ms = 30000,
        haste_scaled = false,
        reduce_by = { [reducer] = 10 },
    }
    CDLedger:OnSpellCastSucceeded(target)
    assert_near(CDLedger:SecondsUntilReady(target), 30, 0.01)
    CDLedger:OnSpellCastSucceeded(reducer)
    assert_near(CDLedger:SecondsUntilReady(target), 20, 0.01,
        "Reducer should shave 10s off the remaining CD")
    CDLedger.spec[target] = nil
end)

test("reduce_by past the remaining CD clears the timer", function()
    local reducer = 999300
    local target  = 999301
    CDLedger.spec[target] = {
        base_ms = 5000,
        haste_scaled = false,
        reduce_by = { [reducer] = 10 },
    }
    CDLedger:OnSpellCastSucceeded(target)
    CDLedger:OnSpellCastSucceeded(reducer) -- -10s from 5s remaining -> ready
    assert_false(CDLedger:IsOnCooldown(target),
        "Over-reduction must clear the entry entirely")
    CDLedger.spec[target] = nil
end)

test("Combined reset_by + reduce_by on the same source cast: reset wins", function()
    local source = 999400
    local target = 999401
    CDLedger.spec[target] = {
        base_ms = 30000,
        haste_scaled = false,
        reset_by  = { [source] = true },
        reduce_by = { [source] = 5 },
    }
    CDLedger:OnSpellCastSucceeded(target)
    CDLedger:OnSpellCastSucceeded(source)
    -- reset runs first, clearing state. The reduce path then finds no entry
    -- and must not reintroduce a phantom timer.
    assert_false(CDLedger:IsOnCooldown(target),
        "When a single cast both resets and reduces, reset must win cleanly " ..
        "without the reduce branch resurrecting state")
    CDLedger.spec[target] = nil
end)

------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------

test("OnCombatEnd does NOT reset timers", function()
    CDLedger:OnSpellCastSucceeded(19574)
    CDLedger:OnCombatEnd()
    assert_true(CDLedger:IsOnCooldown(19574),
        "Cooldowns must persist across PLAYER_REGEN_ENABLED (a BW cast near " ..
        "end of pull is still on CD at the next pull)")
end)

test("Reset clears all tracked timers", function()
    CDLedger:OnSpellCastSucceeded(19574)
    CDLedger:OnSpellCastSucceeded(1264359)
    assert_true(CDLedger:IsOnCooldown(19574))
    assert_true(CDLedger:IsOnCooldown(1264359))
    CDLedger:Reset()
    assert_false(CDLedger:IsOnCooldown(19574))
    assert_false(CDLedger:IsOnCooldown(1264359))
end)

test("SecondsUntilReady is 0 for non-tracked spells", function()
    assert_near(CDLedger:SecondsUntilReady(99999999), 0, 0.0)
end)

test("SecondsSinceCast returns nil before any cast, and elapsed time after", function()
    assert_true(CDLedger:SecondsSinceCast(19574) == nil,
        "No cast observed yet should return nil (not 0)")
    CDLedger:OnSpellCastSucceeded(19574)
    advance_time(4)
    assert_near(CDLedger:SecondsSinceCast(19574), 4, 0.01)
end)

------------------------------------------------------------------------
-- Secret spellID protection
------------------------------------------------------------------------

test("Secret spellID is ignored on cast", function()
    local prev = _G.issecretvalue
    _G.issecretvalue = function(_) return true end
    CDLedger:OnSpellCastSucceeded(19574)
    _G.issecretvalue = prev
    assert_false(CDLedger:IsOnCooldown(19574),
        "Secret spellID payload must not trigger a timer (defends against " ..
        "future API changes that surface secret spellIDs via UNIT_SPELLCAST_SUCCEEDED)")
end)

------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
