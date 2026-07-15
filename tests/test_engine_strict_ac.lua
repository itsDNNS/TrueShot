-- Behavioral regression tests for Strict Assisted Combat primary handling.

local now = 1000
local SECRET = {}
local acAvailable = true
local acNext = nil
local acRotation = {}
local acNextErrors = false
local knownSpells = {}
local usableSpells = {}
local diagnostics = false
local strictMode = true

_G.GetTime = function() return now end
_G.issecretvalue = function(value) return value == SECRET end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.UnitAffectingCombat = function() return false end
_G.UnitExists = function() return false end
_G.UnitCanAttack = function() return false end
_G.UnitPower = function() return 0 end
_G.UnitCastingInfo = function() return nil end
_G.UnitChannelInfo = function() return nil end
_G.IsPlayerSpell = function(spellID) return knownSpells[spellID] == true end
_G.CreateFrame = function()
    return { RegisterEvent = function() end, SetScript = function() end }
end

_G.C_NamePlate = { GetNamePlates = function() return {} end }
_G.C_AssistedCombat = {
    IsAvailable = function() return acAvailable end,
    GetNextCastSpell = function()
        if acNextErrors then error("protected API failure") end
        return acNext
    end,
    GetRotationSpells = function() return acRotation end,
}
_G.C_SpellActivationOverlay = { IsSpellOverlayed = function() return false end }
_G.C_Spell = {
    IsSpellUsable = function(spellID) return usableSpells[spellID] == true end,
    GetSpellCharges = function() return nil end,
    GetSpellCooldown = function() return { startTime = 0, duration = 0, modRate = 1 } end,
}

TrueShot = {
    DiagnosticsEnabled = function() return diagnostics end,
    SignalRegistry = {
        IsStrictMode = function() return strictMode end,
        IsConditionAllowed = function() return true end,
    },
}

dofile("Engine.lua")

local Engine = TrueShot.Engine
local profile = {
    id = "Test.Strict",
    rules = {
        { type = "BLACKLIST", spellID = 101 },
    },
    rotationalSpells = {},
}

local passed, failed = 0, 0

local function assert_eq(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function assert_table_eq(actual, expected, message)
    assert_eq(#actual, #expected, (message or "table length") .. " length")
    for i = 1, #expected do
        assert_eq(actual[i], expected[i], (message or "table value") .. " at " .. i)
    end
end

local function test(name, fn)
    acAvailable = true
    acNext = nil
    acRotation = {}
    acNextErrors = false
    knownSpells = {}
    usableSpells = {}
    diagnostics = false
    strictMode = true
    Engine.activeProfile = profile
    Engine:RebuildBlacklist()
    Engine:ClearDecisionHistory()
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. name .. " -- " .. tostring(err))
    end
end

test("blacklisted raw AC remains Strict slot 1", function()
    acNext = 101
    acRotation = { 202 }
    knownSpells[101], knownSpells[202] = true, true
    usableSpells[101], usableSpells[202] = true, true

    local queue = Engine:ComputeQueue(2)
    assert_table_eq(queue, { 101, 202 })
    assert_eq(Engine.lastQueueMeta.rawACSpell, 101)
    assert_eq(Engine.lastQueueMeta.rawACStatus, "available")
    assert_eq(Engine.lastQueueMeta.finalPrimarySpell, 101)
    assert_eq(Engine.lastQueueMeta.source, "ac")
    assert_eq(Engine.lastQueueMeta.reasonCode, "AC_PRIMARY")
    assert_eq(Engine.lastQueueMeta.fallbackDropReason, nil)
    assert_eq(Engine.lastQueueMeta.strictState, true)
end)

test("readable raw AC remains Strict slot 1 without an active profile", function()
    Engine.activeProfile = nil
    acNext = 111
    acRotation = { 222 }

    local queue = Engine:ComputeQueue(2)
    assert_table_eq(queue, { 111, 222 })
    assert_eq(Engine.lastQueueMeta.rawACSpell, 111)
    assert_eq(Engine.lastQueueMeta.rawACStatus, "available")
    assert_eq(Engine.lastQueueMeta.finalPrimarySpell, 111)
    assert_eq(Engine.lastQueueMeta.source, "ac")
    assert_eq(Engine.lastQueueMeta.reasonCode, "AC_PRIMARY")
    assert_eq(Engine.lastQueueMeta.fallbackDropReason, nil)
end)

test("readable raw AC remains Experimental slot 1 without contradictory no-profile drop", function()
    strictMode = false
    Engine.activeProfile = nil
    acNext = 333
    acRotation = { 444 }
    knownSpells[333], knownSpells[444] = true, true
    usableSpells[333], usableSpells[444] = true, true

    local queue = Engine:ComputeQueue(2)
    assert_table_eq(queue, { 333, 444 })
    assert_eq(Engine.lastQueueMeta.rawACSpell, 333)
    assert_eq(Engine.lastQueueMeta.rawACStatus, "available")
    assert_eq(Engine.lastQueueMeta.finalPrimarySpell, 333)
    assert_eq(Engine.lastQueueMeta.source, "ac")
    assert_eq(Engine.lastQueueMeta.reasonCode, "AC_PRIMARY")
    assert_eq(Engine.lastQueueMeta.fallbackDropReason, nil)
end)

test("ResetQueueMeta preserves explicit Experimental false state", function()
    strictMode = false
    Engine:ResetQueueMeta()
    assert_eq(Engine.lastQueueMeta.strictState, false)
end)

test("locally unknown and uncastable raw AC remains Strict slot 1", function()
    acNext = 303
    acRotation = { 404 }
    knownSpells[303] = false
    usableSpells[303] = false
    knownSpells[404], usableSpells[404] = true, true

    local queue = Engine:ComputeQueue(2)
    assert_table_eq(queue, { 303, 404 })
    assert_eq(Engine.lastQueueMeta.finalPrimarySpell, 303)
    assert_eq(Engine.lastQueueMeta.source, "ac")
end)

test("nil raw AC does not promote rotation catalog", function()
    acNext = nil
    acRotation = { 202, 303 }
    knownSpells[202], knownSpells[303] = true, true
    usableSpells[202], usableSpells[303] = true, true

    local queue = Engine:ComputeQueue(3)
    assert_table_eq(queue, {})
    assert_eq(Engine.lastQueueMeta.rawACSpell, nil)
    assert_eq(Engine.lastQueueMeta.rawACStatus, "nil")
    assert_eq(Engine.lastQueueMeta.finalPrimarySpell, nil)
    assert_eq(Engine.lastQueueMeta.source, "none")
    assert_eq(Engine.lastQueueMeta.reasonCode, "NO_AC_PRIMARY")
    assert_eq(Engine.lastQueueMeta.fallbackDropReason, "raw_ac_nil")
end)

test("secret raw AC does not promote or enter metadata", function()
    acNext = SECRET
    acRotation = { 202 }
    knownSpells[202], usableSpells[202] = true, true

    local queue = Engine:ComputeQueue(2)
    assert_table_eq(queue, {})
    assert_eq(Engine.lastQueueMeta.rawACSpell, nil)
    assert_eq(Engine.lastQueueMeta.rawACStatus, "secret")
    assert_eq(Engine.lastQueueMeta.finalPrimarySpell, nil)
    assert_eq(Engine.lastQueueMeta.source, "none")
    assert_eq(Engine.lastQueueMeta.reasonCode, "NO_AC_PRIMARY")
    assert_eq(Engine.lastQueueMeta.fallbackDropReason, "raw_ac_secret")
end)

test("raw API error fails closed without promoting catalog", function()
    acNextErrors = true
    acRotation = { 202 }
    knownSpells[202], usableSpells[202] = true, true

    local queue = Engine:ComputeQueue(2)
    assert_table_eq(queue, {})
    assert_eq(Engine.lastQueueMeta.rawACStatus, "error")
    assert_eq(Engine.lastQueueMeta.rawACSpell, nil)
    assert_eq(Engine.lastQueueMeta.fallbackDropReason, "raw_ac_error")
end)

test("invalid raw AC result reports truthful status and drop reason", function()
    Engine.activeProfile = nil
    acNext = "not-a-spell-id"
    acRotation = { 202 }
    knownSpells[202], usableSpells[202] = true, true

    local queue = Engine:ComputeQueue(2)
    assert_table_eq(queue, {})
    assert_eq(Engine.lastQueueMeta.rawACStatus, "invalid")
    assert_eq(Engine.lastQueueMeta.rawACSpell, nil)
    assert_eq(Engine.lastQueueMeta.finalPrimarySpell, nil)
    assert_eq(Engine.lastQueueMeta.source, "none")
    assert_eq(Engine.lastQueueMeta.reasonCode, "NO_AC_PRIMARY")
    assert_eq(Engine.lastQueueMeta.fallbackDropReason, "raw_ac_invalid")
end)

test("Experimental rotation catalog never creates slot 1", function()
    strictMode = false
    Engine.activeProfile = nil
    acNext = nil
    acRotation = { 202, 303 }
    knownSpells[202], knownSpells[303] = true, true
    usableSpells[202], usableSpells[303] = true, true

    local queue = Engine:ComputeQueue(3)
    assert_table_eq(queue, {})
    assert_eq(Engine.lastQueueMeta.rawACStatus, "nil")
    assert_eq(Engine.lastQueueMeta.finalPrimarySpell, nil)
    assert_eq(Engine.lastQueueMeta.source, "none")
    assert_eq(Engine.lastQueueMeta.reasonCode, "NO_AC_PRIMARY")
    assert_eq(Engine.lastQueueMeta.fallbackDropReason, "raw_ac_nil")
end)

test("valid raw AC leads catalog context and metadata snapshot", function()
    acNext = 505
    acRotation = { 505, { spellID = 606 }, { 707 } }
    knownSpells[505], knownSpells[606], knownSpells[707] = true, true, true
    usableSpells[505], usableSpells[606], usableSpells[707] = true, true, true

    local queue = Engine:ComputeQueue(3)
    assert_table_eq(queue, { 505, 606, 707 })
    assert_table_eq(Engine.lastQueueMeta.rotationCatalogSnapshot, { 505, 606, 707 })
    assert_eq(Engine.lastQueueMeta.rotationCatalogRole, "context_only")
    assert_eq(Engine.lastQueueMeta.rawACSpell, 505)
    assert_eq(Engine.lastQueueMeta.rawACStatus, "available")
    assert_eq(Engine.lastQueueMeta.finalPrimarySpell, 505)
    assert_eq(Engine.lastQueueMeta.source, "ac")
    assert_eq(Engine.lastQueueMeta.reasonCode, "AC_PRIMARY")
end)

test("diagnostic decision history is bounded to changes and clears when disabled", function()
    diagnostics = true
    acNext = 808
    acRotation = { 909 }
    Engine:ComputeQueue(2)
    Engine:ComputeQueue(2)
    assert_eq(Engine:GetDecisionHistoryCount(), 1, "unchanged decisions should not duplicate")

    now = now + 0.1
    acNext = SECRET
    Engine:ComputeQueue(2)
    assert_eq(Engine:GetDecisionHistoryCount(), 2)
    local recent = Engine:GetRecentDecisions(1)
    assert_eq(recent[1].rawStatus, "secret")
    assert_eq(recent[1].rawACSpell, nil, "secret spell must not enter diagnostic history")

    diagnostics = false
    Engine:ComputeQueue(2)
    assert_eq(Engine:GetDecisionHistoryCount(), 0, "disabled diagnostics should clear history")
end)

if failed > 0 then
    error(string.format("%d passed, %d failed", passed, failed))
end

print(string.format("%d passed, %d failed", passed, failed))
