-- TrueShot Druid profile logic tests
--
-- Focused regression coverage for the shipped Feral burst window rules and
-- the Wildstalker hero-tree activation fix. In particular, Berserk /
-- Incarnation must stop surfacing once the cooldown starts.
--
-- Run from the addon root: lua tests/test_druid_profiles.lua

------------------------------------------------------------------------
-- WoW client stubs
------------------------------------------------------------------------

local _time = 1000.0
local function set_time(t) _time = t end
local function advance_time(dt) _time = _time + dt end
local _target_exists = true
local _target_guid = "target-1"
local _form_id = 1
local _auras_by_spell = {}
local _ac_next_spell = 22568
local _ac_rotation_spells = { 22568 }

_G.GetTime = function() return _time end
_G.UnitAffectingCombat = function(_) return true end
_G.UnitExists = function(unit) return unit == "target" and _target_exists or false end
_G.UnitCanAttack = function(_, _) return false end
_G.UnitGUID = function(unit)
    if unit == "target" and _target_exists then return _target_guid end
    return nil
end
_G.UnitPower = function(_, _) return 0 end
_G.UnitCastingInfo = function(_) return nil end
_G.UnitChannelInfo = function(_) return nil end
_G.issecretvalue = function(_) return false end
_G.pcall = pcall
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.GetSpellBaseCooldown = function(spellID)
    if spellID == 106951 or spellID == 102543 then
        return 180000, 0
    end
    return 0, 0
end
_G.UnitSpellHaste = function(_) return 0 end
_G.GetShapeshiftFormID = function() return _form_id end
_G.GetNumShapeshiftForms = function() return 1 end
_G.GetShapeshiftFormInfo = function(index)
    if index ~= 1 then return nil end
    return nil, "Cat Form", _form_id == 1, true, 768
end
_G.IsPlayerSpell = function(spellID)
    return spellID == 1126
        or spellID == 5217
        or spellID == 106951
        or spellID == 102543
        or spellID == 22568
        or spellID == 1822
        or spellID == 768
end

_G.C_ClassTalents = _G.C_ClassTalents or {}
_G.C_ClassTalents.GetActiveHeroTalentSpec = function()
    return 22
end

_G.C_NamePlate = _G.C_NamePlate or { GetNamePlates = function() return {} end }
_G.C_AssistedCombat = _G.C_AssistedCombat or {
    IsAvailable = function() return true end,
    GetNextCastSpell = function() return _ac_next_spell end,
    GetRotationSpells = function() return _ac_rotation_spells end,
}
_G.C_SpellActivationOverlay = _G.C_SpellActivationOverlay or {
    IsSpellOverlayed = function() return false end,
}
_G.C_Spell = _G.C_Spell or {}
_G.C_Spell.IsSpellUsable = function(spellID)
    return spellID == 1126 or spellID == 106951 or spellID == 22568 or spellID == 1822 or spellID == 768
end
_G.C_Spell.GetSpellCharges = function(_) return nil end
_G.C_Spell.GetSpellName = function(id) return "Spell#" .. tostring(id) end
_G.C_Spell.GetSpellCooldown = function(spellID)
    if spellID == 106951 or spellID == 102543 then
        return { startTime = 0, duration = 0, isEnabled = true, modRate = 1 }
    end
    return { startTime = 0, duration = 0, isEnabled = true, modRate = 1 }
end
_G.C_UnitAuras = _G.C_UnitAuras or {}
_G.C_UnitAuras.GetPlayerAuraBySpellID = function(spellID)
    return _auras_by_spell[spellID]
end

_G.CreateFrame = function(_frameType, _name)
    return {
        RegisterEvent = function() end,
        RegisterUnitEvent = function() end,
        SetScript = function() end,
    }
end

TrueShot = { strictCompliance = false }
TrueShot.CustomProfile = { RegisterConditionSchema = function(_, _) end }

dofile("SignalRegistry.lua")
dofile("Engine.lua")
dofile("State/CDLedger.lua")
dofile("Profiles/Feral_Wildstalker.lua")

local Engine = TrueShot.Engine
local CDLedger = TrueShot.CDLedger

------------------------------------------------------------------------
-- Test harness
------------------------------------------------------------------------

local passed, failed = 0, 0

local function test(name, fn)
    CDLedger:Reset()
    set_time(1000.0)
    Engine.activeProfile = nil
    _target_exists = true
    _target_guid = "target-1"
    _form_id = 1
    _auras_by_spell = {}
    _ac_next_spell = 22568
    _ac_rotation_spells = { 22568 }
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

local function assert_eq(a, b, msg)
    if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a)) end
end

local function P(id)
    local profiles = TrueShot.Profiles[103]
    for _, p in ipairs(profiles) do
        if p.id == id then
            if p.ResetState then p:ResetState() end
            return p
        end
    end
    error("profile not registered: " .. id)
end

------------------------------------------------------------------------
-- Wildstalker
------------------------------------------------------------------------

test("Wildstalker: Berserk is preferred during Tiger's Fury only when cooldown is ready", function()
    local p = P("Druid.Feral.Wildstalker")
    Engine.activeProfile = p
    Engine:RebuildBlacklist()
    p:OnSpellCast(5217) -- Tiger's Fury

    local queue = Engine:ComputeQueue(2)
    assert_eq(queue[1], 106951, "Ready Berserk should surface during Tiger's Fury")
    assert_eq(Engine.lastQueueMeta.reason, "TF Burst")
end)

test("Wildstalker: Incarnation cast starts the shared cooldown and removes Berserk from slot 1", function()
    local p = P("Druid.Feral.Wildstalker")
    Engine.activeProfile = p
    Engine:RebuildBlacklist()

    p:OnSpellCast(5217)      -- Tiger's Fury
    CDLedger:OnSpellCastSucceeded(102543) -- Incarnation: Avatar of Ashamane
    p:OnSpellCast(102543)

    assert_false(Engine:EvalCondition({ type = "cd_ready", spellID = 106951 }),
        "Incarnation should block the Berserk cooldown gate the profile uses")

    local queue = Engine:ComputeQueue(2)
    assert_eq(queue[1], 22568,
        "Once Incarnation/Berserk is on cooldown, the queue must fall back instead of sticking on slot 1")
end)

test("Wildstalker: Incarnation uses the 20s active window in profile state", function()
    local p = P("Druid.Feral.Wildstalker")
    p:OnSpellCast(102543)
    advance_time(19)
    assert_true(p:EvalCondition({ type = "in_berserk" }),
        "Incarnation should keep the burst window active for 20 seconds")
    advance_time(2)
    assert_false(p:EvalCondition({ type = "in_berserk" }),
        "Incarnation burst window should expire after 20 seconds")
end)

test("Wildstalker: Rake is suppressed on the same target until the pandemic window", function()
    local p = P("Druid.Feral.Wildstalker")
    Engine.activeProfile = p
    Engine:RebuildBlacklist()
    _ac_next_spell = 1822
    _ac_rotation_spells = { 1822, 22568 }

    p:OnSpellCast(1822)

    assert_true(p:EvalCondition({ type = "rake_active_on_target" }),
        "Freshly applied Rake should count as active on the current target")

    local queue = Engine:ComputeQueue(2)
    assert_eq(queue[1], nil,
        "A blocked raw primary must not cause a rotation-catalog entry to be promoted into slot 1")
    assert_eq(Engine.lastQueueMeta.fallbackDropReason, "raw_ac_blacklisted")
end)

test("Wildstalker: Rake becomes refreshable inside the 4.5s pandemic window", function()
    local p = P("Druid.Feral.Wildstalker")
    Engine.activeProfile = p
    Engine:RebuildBlacklist()
    _ac_next_spell = 1822
    _ac_rotation_spells = { 1822, 22568 }

    p:OnSpellCast(1822)
    advance_time(11.0) -- 4.0s remaining on a 15s Rake

    assert_false(p:EvalCondition({ type = "rake_active_on_target" }),
        "Rake should stop being blacklisted once it reaches the pandemic refresh window")

    local queue = Engine:ComputeQueue(2)
    assert_eq(queue[1], 1822,
        "Rake should be allowed again when the local timer reaches refresh range")
end)

test("Wildstalker: changing target allows Rake again even if the old target still has it", function()
    local p = P("Druid.Feral.Wildstalker")
    Engine.activeProfile = p
    Engine:RebuildBlacklist()
    _ac_next_spell = 1822
    _ac_rotation_spells = { 1822, 22568 }

    p:OnSpellCast(1822)
    _target_guid = "target-2"

    assert_false(p:EvalCondition({ type = "rake_active_on_target" }),
        "The local Rake timer must be target-specific, not global")

    local queue = Engine:ComputeQueue(2)
    assert_eq(queue[1], 1822,
        "Rake should be allowed immediately on a different target")
end)

test("Wildstalker: Cat Form is suppressed from the queue while already in Cat Form", function()
    local p = P("Druid.Feral.Wildstalker")
    Engine.activeProfile = p
    Engine:RebuildBlacklist()
    _form_id = 1
    _ac_next_spell = 22568
    _ac_rotation_spells = { 22568, 768, 1822 }

    assert_true(p:EvalCondition({ type = "cat_form_active" }),
        "The profile should recognize that the player is already in Cat Form")

    local queue = Engine:ComputeQueue(3)
    assert_eq(queue[1], 22568, "Primary damage suggestion should stay unchanged")
    assert_eq(queue[2], 1822,
        "Cat Form should be skipped from secondary slots while it is already active")
end)

test("Wildstalker: Mark of the Wild is suppressed while the player buff is active", function()
    local p = P("Druid.Feral.Wildstalker")
    Engine.activeProfile = p
    Engine:RebuildBlacklist()
    _auras_by_spell[1126] = { spellId = 1126 }
    _ac_next_spell = 22568
    _ac_rotation_spells = { 22568, 1126, 1822 }

    assert_true(p:EvalCondition({ type = "mark_of_the_wild_active" }),
        "The profile should recognize the live Mark of the Wild player buff")

    local queue = Engine:ComputeQueue(3)
    assert_eq(queue[1], 22568, "Primary damage suggestion should stay unchanged")
    assert_eq(queue[2], 1822,
        "Mark of the Wild should be skipped from secondary slots while the buff is already active")
end)

------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
