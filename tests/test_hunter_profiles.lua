-- TrueShot Hunter profile logic tests
-- Drives each of the 6 Hunter profiles through the scenarios its shipped rules
-- claim to cover and checks the resulting state machine transitions.
--
-- Run from the addon root: lua tests/test_hunter_profiles.lua
--
-- Scope:
--   - BM_DarkRanger:   Bestial Wrath, Black Arrow, Wailing Arrow, Kill Command state
--   - BM_PackLeader:   Bestial Wrath, Stampede arming/consumption, Nature's Ally weave
--   - MM_DarkRanger:   Trueshot, Black Arrow, Wailing Arrow, Rapid Fire, Volley state
--   - MM_Sentinel:     Trueshot, Rapid Fire, Volley state
--   - SV_PackLeader:   Takedown burst window, Stampede Kill Command flag, Boomstick CD
--   - SV_Sentinel:     Takedown burst window, Boomstick CD
--
-- These are pure logic tests: no WoW client, no Engine wiring, no UI. They
-- replace the Engine with a lightweight capturer that hands back the registered
-- Profile table, then exercise it directly. GetTime() is a mutable stub so
-- tests can move time forward deterministically.

------------------------------------------------------------------------
-- WoW client stubs
------------------------------------------------------------------------

local _time = 1000.0
local function set_time(t) _time = t end
local function advance_time(dt) _time = _time + dt end

_G.GetTime = function() return _time end
_G.UnitAffectingCombat = function(_) return true end
local SECRET = {}
_G.issecretvalue = function(value) return value == SECRET end
_G.pcall = pcall

-- CDLedger probes GetSpellBaseCooldown (non-secret on Midnight 12.0.4) and
-- UnitSpellHaste (SecretArguments flag, ledger degrades to zero haste when
-- secret). Tests default to "base from spec table, zero haste" unless a
-- specific test overrides these.
_G.GetSpellBaseCooldown = function(_) return 0, 0 end
_G.UnitSpellHaste = function(_) return 0 end

-- Minimal C_Spell stub: treat charges as a plain table keyed by spellID so tests
-- can drive `spell_charges` conditions deterministically.
local _charges = {}
local _spell_usable = {}
local _spell_cooldowns = {}
local function set_charges(spellID, current, max)
    _charges[spellID] = { currentCharges = current, maxCharges = max or current }
end
_G.C_Spell = _G.C_Spell or {}
_G.C_Spell.GetSpellCharges = function(spellID) return _charges[spellID] end
_G.C_Spell.GetSpellCooldown = function(spellID)
    return _spell_cooldowns[spellID] or { startTime = 0, duration = 0, modRate = 1 }
end

-- MM Sentinel probes the player Trueshot aura as the primary signal, with a
-- timer fallback only when the API is absent. Tests drive both paths by
-- swapping the stub.
_G.C_UnitAuras = _G.C_UnitAuras or {}
local _auras_by_spell = {}
local _buffs_by_index = {}
local function set_player_aura(spellID, aura)
    _auras_by_spell[spellID] = aura
end
local function set_player_buff(index, aura)
    _buffs_by_index[index] = aura
end
_G.C_UnitAuras.GetPlayerAuraBySpellID = function(spellID)
    return _auras_by_spell[spellID]
end
_G.C_UnitAuras.GetBuffDataByIndex = function(_, index)
    return _buffs_by_index[index]
end

-- Engine.lua expects CreateFrame at load time for an internal glow-tracker.
-- Return a minimal no-op frame that accepts RegisterEvent / SetScript calls.
_G.CreateFrame = function(_frameType, _name)
    return {
        RegisterEvent = function() end,
        SetScript = function() end,
    }
end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.IsPlayerSpell = function(_) return true end
local _unit_power = 100
local function set_power(value) _unit_power = value end
_G.UnitPower = function(_unit, _powerType) return _unit_power end
_G.UnitExists = function(_) return false end
_G.UnitCanAttack = function(_, _) return false end
_G.C_NamePlate = _G.C_NamePlate or { GetNamePlates = function() return {} end }
local _ac_available = false
local _ac_next_spell = nil
local _ac_rotation_spells = {}
local function set_ac_state(available, next_spell, rotation_spells)
    _ac_available = available == true
    _ac_next_spell = next_spell
    _ac_rotation_spells = rotation_spells or {}
end
_G.C_AssistedCombat = _G.C_AssistedCombat or {
    IsAvailable = function() return _ac_available end,
    GetNextCastSpell = function() return _ac_next_spell end,
    GetRotationSpells = function() return _ac_rotation_spells end,
}
_G.C_SpellActivationOverlay = _G.C_SpellActivationOverlay or {
    IsSpellOverlayed = function() return false end,
}
_G.UnitCastingInfo = function(_) return nil end
_G.UnitChannelInfo = function(_) return nil end
_G.C_Spell.IsSpellUsable = function(spellID)
    local usable = _spell_usable[spellID]
    if usable == nil then return true end
    return usable == true
end

------------------------------------------------------------------------
-- Minimal Engine + CustomProfile stubs that capture registered profiles
------------------------------------------------------------------------

TrueShot = { strictCompliance = false }
local registered = {}

-- Placeholder captured before Engine.lua loads. The real Engine overwrites the
-- namespace when its file is dofile'd below; we preserve the RegisterProfile
-- capture by wrapping it after load.

TrueShot.CustomProfile = {
    RegisterConditionSchema = function(_, _) end,
}

------------------------------------------------------------------------
-- Load Engine + CDLedger + all Hunter profiles into the capture table
------------------------------------------------------------------------

dofile("SignalRegistry.lua")
dofile("Engine.lua")

-- Override RegisterProfile so each profile file's load-time registration
-- lands in the test capture table. The real Engine:RegisterProfile also
-- keeps its internal TrueShot.Profiles keying; we do not depend on that
-- here, so a plain capture is sufficient.
TrueShot.Engine.RegisterProfile = function(_, profile)
    registered[profile.id] = profile
end

dofile("State/CDLedger.lua")

dofile("Profiles/BM_DarkRanger.lua")
dofile("Profiles/BM_PackLeader.lua")
dofile("Profiles/MM_DarkRanger.lua")
dofile("Profiles/MM_Sentinel.lua")
dofile("Profiles/SV_PackLeader.lua")
dofile("Profiles/SV_Sentinel.lua")

-- Mirror Core.lua: every OnSpellCast on a profile also dispatches to the ledger
-- so migrated profiles (BM Pack Leader today, more later) see consistent state.
for _, p in pairs(registered) do
    local original = p.OnSpellCast
    if original then
        p.OnSpellCast = function(profile, spellID)
            if TrueShot.CDLedger and TrueShot.CDLedger.OnSpellCastSucceeded then
                TrueShot.CDLedger:OnSpellCastSucceeded(spellID)
            end
            return original(profile, spellID)
        end
    end
end

local function P(id)
    local p = registered[id]
    if not p then error("profile not registered: " .. id) end
    return p
end

------------------------------------------------------------------------
-- Test harness
------------------------------------------------------------------------

local passed, failed = 0, 0

local function test(name, fn)
    -- Reset each profile's state between tests so they do not leak.
    for _, p in pairs(registered) do
        if p.ResetState then p:ResetState() end
    end
    if TrueShot.CDLedger and TrueShot.CDLedger.Reset then
        TrueShot.CDLedger:Reset()
    end
    set_time(1000.0)
    _charges = {}
    _spell_usable = {}
    _spell_cooldowns = {}
    _auras_by_spell = {}
    _buffs_by_index = {}
    _ac_available = false
    _ac_next_spell = nil
    _ac_rotation_spells = {}
    _unit_power = 100

    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. name .. " -- " .. tostring(err))
    end
end

local function assert_eq(a, b, msg)
    if a ~= b then
        error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a))
    end
end

local function assert_true(v, msg)
    if not v then error((msg or "expected true") .. " got " .. tostring(v)) end
end

local function assert_false(v, msg)
    if v then error((msg or "expected false") .. " got " .. tostring(v)) end
end

------------------------------------------------------------------------
-- BM Dark Ranger
------------------------------------------------------------------------

test("BM DR: Bestial Wrath opens Withering Fire and arms Wailing Arrow", function()
    local p = P("Hunter.BM.DarkRanger")
    p:OnSpellCast(19574) -- Bestial Wrath
    assert_true(p:EvalCondition({ type = "in_withering_fire" }), "WF should be active immediately after BW")
    assert_true(p:EvalCondition({ type = "wa_available" }), "Wailing Arrow should be available after BW")
    assert_true(p:EvalCondition({ type = "ba_ready" }), "BW resets Black Arrow readiness")
end)

test("BM DR: Black Arrow cast clears ba_ready", function()
    local p = P("Hunter.BM.DarkRanger")
    p:OnSpellCast(19574) -- Bestial Wrath (arms BA)
    assert_true(p:EvalCondition({ type = "ba_ready" }))
    p:OnSpellCast(466930) -- Black Arrow
    assert_false(p:EvalCondition({ type = "ba_ready" }), "BA should be on CD after cast")
end)

test("BM DR: Wailing Arrow cast re-arms Black Arrow and consumes WA", function()
    local p = P("Hunter.BM.DarkRanger")
    p:OnSpellCast(19574)  -- BW
    p:OnSpellCast(466930) -- BA (spend first proc)
    assert_false(p:EvalCondition({ type = "ba_ready" }))
    p:OnSpellCast(392060) -- Wailing Arrow
    assert_true(p:EvalCondition({ type = "ba_ready" }), "WA should re-arm BA")
    assert_false(p:EvalCondition({ type = "wa_available" }), "WA should be consumed")
end)

test("BM DR: Withering Fire expires after 10s", function()
    local p = P("Hunter.BM.DarkRanger")
    p:OnSpellCast(19574)
    advance_time(9)
    assert_true(p:EvalCondition({ type = "in_withering_fire" }), "WF still active at 9s")
    advance_time(2) -- total 11s after BW
    assert_false(p:EvalCondition({ type = "in_withering_fire" }), "WF expired after 10s")
end)

test("BM DR: wf_ending fires only inside the final tail of WF", function()
    local p = P("Hunter.BM.DarkRanger")
    p:OnSpellCast(19574)
    assert_false(p:EvalCondition({ type = "wf_ending", seconds = 2.5 }),
        "wf_ending should be false at the start of WF")
    advance_time(8) -- 2s remaining on WF
    assert_true(p:EvalCondition({ type = "wf_ending", seconds = 2.5 }),
        "wf_ending should fire in the last 2.5s of WF")
end)

test("BM DR: Kill Command sets Nature's Ally anti-repeat flag", function()
    local p = P("Hunter.BM.DarkRanger")
    p:OnSpellCast(34026) -- KC
    assert_true(p:EvalCondition({ type = "last_cast_was_kc" }))
    p:OnSpellCast(217200) -- Barbed Shot (valid NA filler)
    assert_false(p:EvalCondition({ type = "last_cast_was_kc" }),
        "Non-KC, non-WT cast should clear the NA flag")
end)

test("BM DR: Wild Thrash does NOT clear Nature's Ally flag (invalid weave)", function()
    local p = P("Hunter.BM.DarkRanger")
    p:OnSpellCast(34026)   -- KC
    p:OnSpellCast(1264359) -- Wild Thrash
    assert_true(p:EvalCondition({ type = "last_cast_was_kc" }),
        "KC -> WT -> KC is an invalid weave; NA flag must remain true")
end)

------------------------------------------------------------------------
-- BM Pack Leader (Stampede rule is the new v0.24.0 addition)
------------------------------------------------------------------------

test("BM PL: Bestial Wrath arms Stampede and clears NA flag", function()
    local p = P("Hunter.BM.PackLeader")
    p:OnSpellCast(34026) -- KC first, to set NA flag
    assert_true(p:EvalCondition({ type = "last_cast_was_kc" }))
    p:OnSpellCast(19574) -- BW
    assert_true(p:EvalCondition({ type = "stampede_available" }),
        "BW must arm Stampede for the next KC")
    assert_false(p:EvalCondition({ type = "last_cast_was_kc" }),
        "BW clears the NA anti-repeat flag so the follow-up KC is legal")
end)

test("BM PL: first KC after BW consumes Stampede", function()
    local p = P("Hunter.BM.PackLeader")
    p:OnSpellCast(19574) -- BW
    assert_true(p:EvalCondition({ type = "stampede_available" }))
    p:OnSpellCast(34026) -- KC
    assert_false(p:EvalCondition({ type = "stampede_available" }),
        "First KC after BW must consume the Stampede flag")
end)

test("BM PL: Stampede rearms on next Bestial Wrath", function()
    local p = P("Hunter.BM.PackLeader")
    p:OnSpellCast(19574) -- BW
    p:OnSpellCast(34026) -- KC (consumes)
    assert_false(p:EvalCondition({ type = "stampede_available" }))
    p:OnSpellCast(19574) -- next BW
    assert_true(p:EvalCondition({ type = "stampede_available" }),
        "Next BW must re-arm Stampede")
end)

test("BM PL: Combat end clears Stampede flag", function()
    local p = P("Hunter.BM.PackLeader")
    p:OnSpellCast(19574)
    assert_true(p:EvalCondition({ type = "stampede_available" }))
    p:OnCombatEnd()
    assert_false(p:EvalCondition({ type = "stampede_available" }),
        "OnCombatEnd must clear Stampede to avoid stale arming between fights")
end)

test("BM PL: Stampede experimental PIN is ordered before the KC Proc experimental PIN (first-match-wins)", function()
    local p = P("Hunter.BM.PackLeader")
    local stampedeIdx, kcProcIdx = nil, nil
    for i, rule in ipairs(p.rules) do
        if rule.type == "EXPERIMENTAL_PIN" and rule.spellID == 34026 then
            if rule.reason == "Stampede" then stampedeIdx = i
            elseif rule.reason == "KC Proc" then kcProcIdx = i end
        end
    end
    assert_true(stampedeIdx, "Stampede EXPERIMENTAL_PIN rule must exist")
    assert_true(kcProcIdx, "KC Proc EXPERIMENTAL_PIN rule must exist")
    assert_true(stampedeIdx < kcProcIdx,
        "Engine ComputeQueue iterates rules in order and takes the first experimental PIN whose " ..
        "condition is true. To make the post-BW queue surface " ..
        "reason='Stampede', the Stampede rule must be declared before the KC Proc rule.")
end)

test("BM PL: bw_on_cd uses the local Bestial Wrath cast timer", function()
    local p = P("Hunter.BM.PackLeader")
    p:OnSpellCast(19574)
    advance_time(10)
    assert_true(p:EvalCondition({ type = "bw_on_cd" }),
        "Pack Leader BW suppression should stay active during the local 30s window")
    advance_time(25)
    assert_false(p:EvalCondition({ type = "bw_on_cd" }),
        "After 35s total, the local BW timer must report ready again")
end)

test("BM PL: local BW timer wins even if the ledger is stale", function()
    local p = P("Hunter.BM.PackLeader")
    local Engine = TrueShot.Engine
    Engine.activeProfile = p
    Engine:RebuildBlacklist()

    p:OnSpellCast(19574)
    advance_time(30.1)

    TrueShot.CDLedger.state[19574] = {
        cast_time = GetTime(),
        expected_ready = GetTime() + 999,
    }

    assert_false(p:EvalCondition({ type = "bw_on_cd" }),
        "After 30s, the local BW timer must report ready even if the ledger still looks stale")

    set_ac_state(true, 56641, { 56641, 34026, 217200 })
    local queue = Engine:ComputeQueue(3)
    assert_eq(queue[1], 19574,
        "A stale ledger entry must not stop Pack Leader from resurfacing BW once the local timer is ready")
end)

test("BM PL: GetPhase reads CDLedger:SecondsSinceCast for the 15s burst window", function()
    local p = P("Hunter.BM.PackLeader")
    assert_true(p:GetPhase() == nil,
        "Fresh profile has no BW cast -> no Burst phase")
    p:OnSpellCast(19574)
    assert_true(p:GetPhase() == "Burst",
        "Immediately after BW cast the profile must report Burst phase")
    advance_time(14)
    assert_true(p:GetPhase() == "Burst",
        "Still inside the 15s window")
    advance_time(2)
    assert_true(p:GetPhase() == nil,
        "After 16s the 15s Burst window has closed even though the 30s CD is still running")
end)

test("issue #93 BM PL: ComputeQueue pins Bestial Wrath even when AC omits the recast", function()
    local p = P("Hunter.BM.PackLeader")
    local Engine = TrueShot.Engine
    Engine.activeProfile = p
    Engine:RebuildBlacklist()
    set_ac_state(true, 56641, { 56641, 34026, 217200 })

    local queue = Engine:ComputeQueue(3)
    assert_eq(queue[1], 19574,
        "Pack Leader must actively pin Bestial Wrath when it is ready, even if Blizzard AC omits it")
    assert_eq(Engine.lastQueueMeta.source, "hybrid")
    assert_eq(Engine.lastQueueMeta.reason, "Bestial Wrath")
    assert_eq(Engine.lastQueueMeta.bucket, "cooldown")
end)

test("issue #93 BM PL: local BW cast suppresses the BW pin and hands slot 1 to Stampede", function()
    local p = P("Hunter.BM.PackLeader")
    local Engine = TrueShot.Engine
    Engine.activeProfile = p
    Engine:RebuildBlacklist()

    p:OnSpellCast(19574)
    set_ac_state(true, 56641, { 56641, 34026, 217200 })

    assert_true(p:EvalCondition({ type = "bw_on_cd" }),
        "After the local cast event, the Pack Leader local BW timer must be active immediately")

    local queue = Engine:ComputeQueue(3)
    assert_eq(queue[1], 34026,
        "After BW starts its cooldown, the post-BW Stampede Kill Command should take over slot 1")
    assert_eq(Engine.lastQueueMeta.reason, "Stampede")
end)

test("issue #93 BM PL: unusable AC Kill Command must not occupy queue slot 1", function()
    local p = P("Hunter.BM.PackLeader")
    local Engine = TrueShot.Engine
    Engine.activeProfile = p
    Engine:RebuildBlacklist()

    p:OnSpellCast(19574)   -- BW
    p:OnSpellCast(34026)   -- consume Stampede, arm KC anti-repeat
    p:OnSpellCast(217200)  -- real filler clears anti-repeat; BW stays on CD

    _spell_usable[34026] = false -- KC still on cooldown in the live client
    set_ac_state(true, 34026, { 34026, 217200, 56641 })

    local queue = Engine:ComputeQueue(3)
    assert_true(queue[1] ~= 34026,
        "An unusable AC primary spell must be dropped instead of occupying slot 1")
end)

test("issue #93 BM PL: cooldown snapshot blocks AC Kill Command even when IsSpellUsable stays true", function()
    local p = P("Hunter.BM.PackLeader")
    local Engine = TrueShot.Engine
    Engine.activeProfile = p
    Engine:RebuildBlacklist()

    p:OnSpellCast(19574)
    p:OnSpellCast(34026)
    p:OnSpellCast(217200)

    _spell_cooldowns[34026] = {
        startTime = GetTime() - 1,
        duration = 3,
        modRate = 1,
    }
    _spell_usable[34026] = true
    set_ac_state(true, 34026, { 34026, 217200, 56641 })

    local queue = Engine:ComputeQueue(3)
    assert_true(queue[1] ~= 34026,
        "Readable cooldown state must override the misleading IsSpellUsable=true result for KC")
end)

test("issue #93 BM PL: Barbed Shot with one charge stays castable despite recharge timer", function()
    local p = P("Hunter.BM.PackLeader")
    local Engine = TrueShot.Engine
    Engine.activeProfile = p
    Engine:RebuildBlacklist()

    p:OnSpellCast(19574)
    p:OnSpellCast(34026)
    p:OnSpellCast(56641) -- filler clears KC anti-repeat while BW stays on CD

    set_charges(217200, 1, 2)
    _spell_cooldowns[217200] = {
        startTime = GetTime() - 2,
        duration = 12,
        modRate = 1,
    }
    _spell_usable[217200] = true
    set_ac_state(true, 217200, { 217200, 56641, 34026 })

    local queue = Engine:ComputeQueue(3)
    assert_eq(queue[1], 217200,
        "A charge-based spell with one available charge must stay castable even while its second charge is recharging")
end)

test("issue #93 BM PL: prefer Barbed Shot when KC is not castable", function()
    local p = P("Hunter.BM.PackLeader")
    local Engine = TrueShot.Engine
    Engine.activeProfile = p
    Engine:RebuildBlacklist()

    p:OnSpellCast(19574)
    p:OnSpellCast(34026)
    p:OnSpellCast(56641) -- clear NA anti-repeat while BW stays on CD

    _spell_cooldowns[34026] = {
        startTime = GetTime() - 1,
        duration = 3,
        modRate = 1,
    }
    _spell_usable[34026] = true
    set_charges(217200, 1, 2)
    set_ac_state(true, 34026, { 34026, 217200, 56641 })

    local queue = Engine:ComputeQueue(3)
    assert_eq(queue[1], 217200,
        "Pack Leader should surface Barbed Shot as the first filler when KC is not currently castable")
    assert_eq(Engine.lastQueueMeta.source, "hybrid")
    assert_eq(Engine.lastQueueMeta.reason, "Barbed Shot Filler")
    assert_eq(Engine.lastQueueMeta.bucket, "barbed_filler")
end)

test("issue #93 BM PL: prefer Cobra Shot when KC is not castable and Barbed Shot has no charge", function()
    local p = P("Hunter.BM.PackLeader")
    local Engine = TrueShot.Engine
    Engine.activeProfile = p
    Engine:RebuildBlacklist()

    p:OnSpellCast(19574)
    p:OnSpellCast(34026)
    p:OnSpellCast(217200)

    _spell_cooldowns[34026] = {
        startTime = GetTime() - 1,
        duration = 3,
        modRate = 1,
    }
    _spell_usable[34026] = true
    set_charges(217200, 0, 2)
    _spell_usable[217200] = false
    set_ac_state(true, 34026, { 34026, 217200, 56641 })

    local queue = Engine:ComputeQueue(3)
    assert_eq(queue[1], 56641,
        "Cobra Shot should be the fallback filler when KC is not castable and Barbed Shot is unavailable")
    assert_eq(Engine.lastQueueMeta.source, "hybrid")
    assert_eq(Engine.lastQueueMeta.reason, "Cobra Shot Filler")
    assert_eq(Engine.lastQueueMeta.bucket, "cobra_filler")
end)

test("issue #93 BM PL: low-focus Cobra blacklist must not fire when KC only looks usable", function()
    local p = P("Hunter.BM.PackLeader")
    local Engine = TrueShot.Engine
    Engine.activeProfile = p
    Engine:RebuildBlacklist()

    p:OnSpellCast(19574)
    p:OnSpellCast(34026)
    p:OnSpellCast(217200)

    set_power(40)
    _spell_cooldowns[34026] = {
        startTime = GetTime() - 1,
        duration = 3,
        modRate = 1,
    }
    _spell_usable[34026] = true
    set_charges(217200, 0, 2)
    _spell_usable[217200] = false
    set_ac_state(true, 34026, { 34026, 217200, 56641 })

    local queue = Engine:ComputeQueue(3)
    assert_eq(queue[1], 56641,
        "The Cobra focus-pool guard must key off true castability, not IsSpellUsable=true on a cooling-down KC")
    assert_eq(Engine.lastQueueMeta.source, "hybrid")
    assert_eq(Engine.lastQueueMeta.bucket, "cobra_filler")
end)

test("issue #93 BM PL: Barbed Shot gets a dedicated BW setup bucket inside the final 3s", function()
    local p = P("Hunter.BM.PackLeader")
    local Engine = TrueShot.Engine
    Engine.activeProfile = p
    Engine:RebuildBlacklist()

    p.state.lastBWCast = GetTime() - 27.5 -- ~2.5s left on the local 30s BW cooldown
    set_charges(217200, 1, 2)
    set_ac_state(true, 56641, { 56641, 217200, 34026 })

    local queue = Engine:ComputeQueue(3)
    assert_eq(queue[1], 217200,
        "When BW is due within 3s, Barbed Shot should surface from the BW-setup bucket")
    assert_eq(Engine.lastQueueMeta.source, "hybrid")
    assert_eq(Engine.lastQueueMeta.reason, "BW Setup")
    assert_eq(Engine.lastQueueMeta.bucket, "bw_setup")
end)

test("issue #93 BM PL: Barbed Shot recent guard hands the next filler to Cobra Shot", function()
    local p = P("Hunter.BM.PackLeader")
    local Engine = TrueShot.Engine
    Engine.activeProfile = p
    Engine:RebuildBlacklist()

    p:OnSpellCast(19574)
    p:OnSpellCast(34026)
    p:OnSpellCast(217200)

    _spell_cooldowns[34026] = {
        startTime = GetTime() - 1,
        duration = 3,
        modRate = 1,
    }
    _spell_usable[34026] = true
    set_charges(217200, 1, 2)
    set_ac_state(true, 217200, { 217200, 56641, 34026 })

    assert_true(p:EvalCondition({ type = "barbed_recent" }),
        "Immediately after Barbed Shot, the profile should mark it as recent")

    local queue = Engine:ComputeQueue(3)
    assert_eq(queue[1], 56641,
        "Immediately after casting Barbed Shot, the overlay should advance to Cobra Shot instead of sticking on Barbed Shot")
    assert_eq(Engine.lastQueueMeta.reason, "Cobra Shot Filler")
end)

test("issue #93 BM PL: Barbed Shot recent guard expires and allows Barbed Shot again", function()
    local p = P("Hunter.BM.PackLeader")
    local Engine = TrueShot.Engine
    Engine.activeProfile = p
    Engine:RebuildBlacklist()

    p:OnSpellCast(19574)
    p:OnSpellCast(34026)
    p:OnSpellCast(217200)

    _spell_cooldowns[34026] = {
        startTime = GetTime() - 1,
        duration = 3,
        modRate = 1,
    }
    _spell_usable[34026] = true
    set_charges(217200, 1, 2)
    set_ac_state(true, 217200, { 217200, 56641, 34026 })

    advance_time(1.5)
    assert_false(p:EvalCondition({ type = "barbed_recent" }),
        "The recent Barbed Shot guard should be short-lived and expire after the immediate post-cast window")

    local queue = Engine:ComputeQueue(3)
    assert_eq(queue[1], 217200,
        "Once the short Barbed Shot recent window expires, Barbed Shot may surface again if KC is still not castable")
    assert_eq(Engine.lastQueueMeta.reason, "Barbed Shot Filler")
end)

test("BM PL: Wild Thrash timer persists across OnCombatEnd (ledger-owned)", function()
    local p = P("Hunter.BM.PackLeader")
    p:OnSpellCast(1264359)
    assert_true(p:EvalCondition({ type = "wt_on_cd" }))
    p:OnCombatEnd()
    -- Intentional semantic change vs pre-v0.25.0: CDs persist across combat
    -- end because real in-game cooldowns do. The old profile-local timer
    -- reset here; the ledger intentionally does not.
    assert_true(p:EvalCondition({ type = "wt_on_cd" }),
        "Post-v0.25.0: Wild Thrash CD must survive combat end, mirroring " ..
        "real WoW cooldown behaviour")
end)

test("BM PL: Wild Thrash does NOT clear Nature's Ally flag", function()
    local p = P("Hunter.BM.PackLeader")
    p:OnSpellCast(34026)
    p:OnSpellCast(1264359) -- WT
    assert_true(p:EvalCondition({ type = "last_cast_was_kc" }),
        "WT must not be treated as a Nature's Ally filler")
end)

------------------------------------------------------------------------
-- MM Dark Ranger
------------------------------------------------------------------------

test("MM DR: Trueshot arms BA readiness, WF timer, and Wailing Arrow", function()
    local p = P("Hunter.MM.DarkRanger")
    p:OnSpellCast(288613) -- Trueshot
    assert_true(p:EvalCondition({ type = "ba_ready" }))
    assert_true(p:EvalCondition({ type = "in_withering_fire" }))
    assert_true(p:EvalCondition({ type = "wa_available" }))
    assert_true(p:EvalCondition({ type = "trueshot_active" }))
    assert_true(p:EvalCondition({ type = "trueshot_just_cast", seconds = 2 }))
end)

test("MM DR: trueshot_just_cast decays after its window", function()
    local p = P("Hunter.MM.DarkRanger")
    p:OnSpellCast(288613)
    advance_time(3)
    assert_false(p:EvalCondition({ type = "trueshot_just_cast", seconds = 2 }),
        "trueshot_just_cast window should have elapsed")
    assert_true(p:EvalCondition({ type = "trueshot_active" }),
        "Trueshot buff should still be active well before the 15s duration ends")
end)

test("MM DR: Rapid Fire recency is bounded by the seconds arg", function()
    local p = P("Hunter.MM.DarkRanger")
    p:OnSpellCast(257044) -- Rapid Fire
    assert_true(p:EvalCondition({ type = "rapid_fire_recent", seconds = 3 }))
    advance_time(4)
    assert_false(p:EvalCondition({ type = "rapid_fire_recent", seconds = 3 }))
end)

test("MM DR: Volley anti-overlap signal decays after seconds", function()
    local p = P("Hunter.MM.DarkRanger")
    p:OnSpellCast(260243) -- Volley
    assert_true(p:EvalCondition({ type = "volley_recent", seconds = 2 }))
    advance_time(3)
    assert_false(p:EvalCondition({ type = "volley_recent", seconds = 2 }))
end)

test("issue #89 MM DR: ComputeQueue pins Trueshot even when AC omits it", function()
    local p = P("Hunter.MM.DarkRanger")
    local Engine = TrueShot.Engine
    Engine.activeProfile = p
    Engine:RebuildBlacklist()
    set_ac_state(true, 185358, { 185358, 56641 })

    local queue = Engine:ComputeQueue(3)
    assert_eq(queue[1], 288613,
        "Trueshot must pin from cd_ready even when Blizzard AC never suggests it")
    assert_eq(Engine.lastQueueMeta.source, "pin")
    assert_eq(Engine.lastQueueMeta.reason, "Trueshot")
end)

test("issue #89 MM DR: local cast event suppresses Trueshot while cooldown runs", function()
    local p = P("Hunter.MM.DarkRanger")
    local Engine = TrueShot.Engine
    Engine.activeProfile = p
    Engine:RebuildBlacklist()
    p:OnSpellCast(288613)
    set_ac_state(true, 185358, { 185358, 56641 })
    assert_false(Engine:EvalCondition({ type = "cd_ready", spellID = 288613 }),
        "After the local cast event, cd_ready(Trueshot) must flip false immediately")

    local queue = Engine:ComputeQueue(3)
    assert_eq(queue[1], 466930,
        "After Trueshot starts its cooldown, Dark Ranger should fall into the BA opener instead of repinning Trueshot")
    assert_eq(Engine.lastQueueMeta.reason, "TS Opener BA")
end)

test("issue #89 MM DR: Volley anti-overlap still blocks a ready Trueshot pin", function()
    local p = P("Hunter.MM.DarkRanger")
    local Engine = TrueShot.Engine
    Engine.activeProfile = p
    Engine:RebuildBlacklist()
    p:OnSpellCast(260243)
    set_ac_state(true, 185358, { 185358, 56641 })

    local queue = Engine:ComputeQueue(3)
    assert_eq(queue[1], 466930,
        "The existing Volley -> Trueshot guard must still win even with the new cd_ready pin")
    assert_eq(Engine.lastQueueMeta.reason, "BA Ready")
end)

------------------------------------------------------------------------
-- MM Sentinel
------------------------------------------------------------------------

test("MM Sentinel: trueshot_active reads live aura when present", function()
    local p = P("Hunter.MM.Sentinel")
    p:OnSpellCast(288613)
    set_player_aura(288613, { spellId = 288613 }) -- Trueshot aura live
    assert_true(p:EvalCondition({ type = "trueshot_active" }),
        "With a live aura the primary signal should resolve true")
end)

test("MM Sentinel: trueshot_active is false when the aura is gone", function()
    local p = P("Hunter.MM.Sentinel")
    p:OnSpellCast(288613)
    -- No aura set => API returns nil => primary signal says inactive.
    assert_false(p:EvalCondition({ type = "trueshot_active" }),
        "Primary aura signal takes precedence over the timer fallback")
end)

test("MM Sentinel: timer fallback engages when C_UnitAuras API is absent", function()
    local p = P("Hunter.MM.Sentinel")
    local saved = _G.C_UnitAuras.GetPlayerAuraBySpellID
    _G.C_UnitAuras.GetPlayerAuraBySpellID = nil
    p:OnSpellCast(288613)
    assert_true(p:EvalCondition({ type = "trueshot_active" }),
        "With the aura API missing, the 19s timer must cover the Trueshot window")
    advance_time(20)
    assert_false(p:EvalCondition({ type = "trueshot_active" }),
        "Timer fallback should expire after the 19s Sentinel Trueshot window")
    _G.C_UnitAuras.GetPlayerAuraBySpellID = saved
end)

test("MM Sentinel: aimed_shot_ready reads non-secret charges", function()
    local p = P("Hunter.MM.Sentinel")
    set_charges(19434, 2, 2)
    assert_true(p:EvalCondition({ type = "aimed_shot_ready" }))
    set_charges(19434, 0, 2)
    assert_false(p:EvalCondition({ type = "aimed_shot_ready" }))
end)

test("issue #89 MM Sentinel: ComputeQueue pins Trueshot even when AC omits it", function()
    local p = P("Hunter.MM.Sentinel")
    local Engine = TrueShot.Engine
    Engine.activeProfile = p
    Engine:RebuildBlacklist()
    set_ac_state(true, 185358, { 185358, 56641 })

    local queue = Engine:ComputeQueue(3)
    assert_eq(queue[1], 288613,
        "Sentinel Trueshot must pin from cd_ready even when Blizzard AC omits it")
    assert_eq(Engine.lastQueueMeta.source, "pin")
    assert_eq(Engine.lastQueueMeta.reason, "Trueshot")
end)

test("issue #89 MM Sentinel: Moonlight Chakram can surface without AC suggestion", function()
    local p = P("Hunter.MM.Sentinel")
    local Engine = TrueShot.Engine
    Engine.activeProfile = p
    Engine:RebuildBlacklist()
    p:OnSpellCast(288613)
    set_player_aura(288613, { spellId = 288613 })
    set_charges(19434, 0, 2)
    set_ac_state(true, 185358, { 185358, 56641 })

    local queue = Engine:ComputeQueue(3)
    assert_eq(queue[1], 1264902,
        "Moonlight Chakram should surface from the local Sentinel window even when AC does not suggest it")
    assert_eq(Engine.lastQueueMeta.source, "prefer")
    assert_eq(Engine.lastQueueMeta.reason, "Chakram")
end)

test("issue #89 MM Sentinel: Moonlight Chakram stays suppressed outside trueshot_active", function()
    local p = P("Hunter.MM.Sentinel")
    local Engine = TrueShot.Engine
    Engine.activeProfile = p
    Engine:RebuildBlacklist()
    p:OnSpellCast(288613)
    set_charges(19434, 0, 2)
    set_ac_state(true, 185358, { 185358, 56641 })

    local queue = Engine:ComputeQueue(3)
    assert_eq(queue[1], 185358,
        "Without a live Trueshot window, the Chakram safety-net must keep it out of the queue")
end)

------------------------------------------------------------------------
-- SV Pack Leader
------------------------------------------------------------------------

test("SV PL: Takedown opens 8s burst window", function()
    local p = P("Hunter.SV.PackLeader")
    p:OnSpellCast(1250646) -- Takedown
    assert_true(p:EvalCondition({ type = "takedown_active" }))
    assert_false(p:EvalCondition({ type = "kc_cast_in_takedown" }))
    advance_time(9)
    assert_false(p:EvalCondition({ type = "takedown_active" }),
        "Takedown burst window is 8s; should be closed at +9s")
end)

test("SV PL: first KC inside Takedown sets kc_cast_in_takedown", function()
    local p = P("Hunter.SV.PackLeader")
    p:OnSpellCast(1250646) -- Takedown
    p:OnSpellCast(259489)  -- SV Kill Command (259489, distinct from BM 34026)
    assert_true(p:EvalCondition({ type = "kc_cast_in_takedown" }),
        "KC cast inside Takedown window must set the Stampede-consumed flag")
end)

test("SV PL: KC outside Takedown does NOT set kc_cast_in_takedown", function()
    local p = P("Hunter.SV.PackLeader")
    p:OnSpellCast(1250646)
    advance_time(9) -- Takedown window closed
    p:OnSpellCast(259489)
    assert_false(p:EvalCondition({ type = "kc_cast_in_takedown" }),
        "Late KC should not retroactively flag a consumed Stampede")
end)

test("SV PL: Boomstick tracks its own 30s CD signal", function()
    local p = P("Hunter.SV.PackLeader")
    p:OnSpellCast(1261193) -- Boomstick
    assert_true(p:EvalCondition({ type = "boomstick_on_cd" }))
    advance_time(31)
    assert_false(p:EvalCondition({ type = "boomstick_on_cd" }))
end)

test("SV PL: WFB charges condition respects operators", function()
    local p = P("Hunter.SV.PackLeader")
    set_charges(259495, 2, 2)
    assert_true(p:EvalCondition({ type = "wfb_charges", op = "==", value = 2 }))
    set_charges(259495, 1, 2)
    assert_false(p:EvalCondition({ type = "wfb_charges", op = "==", value = 2 }))
    assert_true(p:EvalCondition({ type = "wfb_charges", op = ">=", value = 1 }))
end)

test("SV PL: exposes Raptor Swipe in rotational spell catalog", function()
    local p = P("Hunter.SV.PackLeader")
    assert_true(p.rotationalSpells and p.rotationalSpells[1259019] == true,
        "Raptor Swipe must be selectable from Survival Pack Leader custom rules")
end)

test("SV PL: Tip of the Spear stack condition reads safe player buff stacks", function()
    local p = P("Hunter.SV.PackLeader")
    set_player_buff(7, { name = "Tip of the Spear", spellId = 260286, applications = 2 })
    assert_true(p:EvalCondition({ type = "tip_of_the_spear_stacks", op = ">=", value = 2 }))
    assert_false(p:EvalCondition({ type = "tip_of_the_spear_stacks", op = ">", value = 2 }))
end)

test("SV PL: Tip of the Spear stack condition fails closed on secret stacks", function()
    local p = P("Hunter.SV.PackLeader")
    set_player_buff(3, { name = "Tip of the Spear", spellId = 260286, applications = SECRET })
    assert_false(p:EvalCondition({ type = "tip_of_the_spear_stacks", op = ">=", value = 1 }))
end)

------------------------------------------------------------------------
-- SV Sentinel
------------------------------------------------------------------------

test("SV Sentinel: Takedown opens its 8s burst window", function()
    local p = P("Hunter.SV.Sentinel")
    p:OnSpellCast(1250646)
    assert_true(p:EvalCondition({ type = "takedown_active" }))
    assert_true(p:EvalCondition({ type = "takedown_just_cast", seconds = 5 }))
    advance_time(6)
    assert_false(p:EvalCondition({ type = "takedown_just_cast", seconds = 5 }))
    assert_true(p:EvalCondition({ type = "takedown_active" }),
        "takedown_active spans the full 8s even after takedown_just_cast's 5s hint expires")
end)

test("SV Sentinel: Boomstick cooldown gate tracks cast recency", function()
    local p = P("Hunter.SV.Sentinel")
    p:OnSpellCast(1261193)
    assert_true(p:EvalCondition({ type = "boomstick_on_cd" }))
    advance_time(31)
    assert_false(p:EvalCondition({ type = "boomstick_on_cd" }))
end)

test("SV Sentinel: OnCombatEnd clears Takedown window", function()
    local p = P("Hunter.SV.Sentinel")
    p:OnSpellCast(1250646)
    p:OnCombatEnd()
    assert_false(p:EvalCondition({ type = "takedown_active" }),
        "Combat-end must not leave stale Takedown burst state")
end)

test("SV Sentinel: exposes Raptor Swipe in rotational spell catalog", function()
    local p = P("Hunter.SV.Sentinel")
    assert_true(p.rotationalSpells and p.rotationalSpells[1259019] == true,
        "Raptor Swipe must be selectable from Survival Sentinel custom rules")
end)

test("SV Sentinel: Tip of the Spear stack condition reads safe player buff stacks", function()
    local p = P("Hunter.SV.Sentinel")
    set_player_buff(7, { name = "Tip of the Spear", spellId = 260286, applications = 3 })
    assert_true(p:EvalCondition({ type = "tip_of_the_spear_stacks", op = ">=", value = 3 }))
    assert_false(p:EvalCondition({ type = "tip_of_the_spear_stacks", op = "==", value = 2 }))
end)

------------------------------------------------------------------------
-- Strict compliance mode
------------------------------------------------------------------------

test("Strict mode: BM Pack Leader falls back to AC and ignores hybrid overrides", function()
    local previous = TrueShot.strictCompliance
    TrueShot.strictCompliance = true

    local p = P("Hunter.BM.PackLeader")
    local Engine = TrueShot.Engine
    Engine.activeProfile = p
    Engine:RebuildBlacklist()

    set_ac_state(true, 56641, { 56641, 34026, 217200 })

    local queue = Engine:ComputeQueue(3)
    assert_eq(queue[1], 56641,
        "Strict mode must not replace AC slot 1 with local BW/hybrid logic")
    assert_eq(Engine.lastQueueMeta.source, "ac")
    assert_eq(Engine.lastQueueMeta.reasonCode, "AC_PRIMARY")

    TrueShot.strictCompliance = previous
end)

test("Strict mode: unsafe condition signals fail closed", function()
    local previous = TrueShot.strictCompliance
    TrueShot.strictCompliance = true

    local Engine = TrueShot.Engine
    set_charges(217200, 2, 2)
    set_power(100)

    assert_false(Engine:EvalCondition({ type = "spell_charges", spellID = 217200, op = ">=", value = 1 }),
        "spell_charges is not allowed to drive strict-mode decisions")
    assert_false(Engine:EvalCondition({ type = "resource", powerType = 2, op = ">=", value = 10 }),
        "resource is not allowed to drive strict-mode decisions")
    assert_false(Engine:EvalCondition({ type = "cd_ready", spellID = 19574 }),
        "CDLedger readiness is not allowed to drive strict-mode decisions")

    TrueShot.strictCompliance = previous
end)

test("Strict mode: AC queue survives without risky combat APIs", function()
    local previousStrict = TrueShot.strictCompliance
    local previousUnitPower = _G.UnitPower
    local previousUnitCastingInfo = _G.UnitCastingInfo
    local previousUnitChannelInfo = _G.UnitChannelInfo
    local previousNamePlate = _G.C_NamePlate
    local previousAuras = _G.C_UnitAuras
    local previousCooldown = _G.C_Spell.GetSpellCooldown
    local previousCharges = _G.C_Spell.GetSpellCharges

    TrueShot.strictCompliance = true
    _G.UnitPower = nil
    _G.UnitCastingInfo = nil
    _G.UnitChannelInfo = nil
    _G.C_NamePlate = nil
    _G.C_UnitAuras = nil
    _G.C_Spell.GetSpellCooldown = nil
    _G.C_Spell.GetSpellCharges = nil

    local p = P("Hunter.MM.DarkRanger")
    local Engine = TrueShot.Engine
    Engine.activeProfile = p
    Engine:RebuildBlacklist()
    set_ac_state(true, 257044, { 257044, 19434, 56641 })

    local queue = Engine:ComputeQueue(3)
    assert_eq(queue[1], 257044,
        "Strict mode must render the AC primary without resource/aura/cooldown/nameplate APIs")
    assert_eq(queue[2], 19434)
    assert_eq(queue[3], 56641)
    assert_eq(Engine.lastQueueMeta.reasonCode, "AC_PRIMARY")

    TrueShot.strictCompliance = previousStrict
    _G.UnitPower = previousUnitPower
    _G.UnitCastingInfo = previousUnitCastingInfo
    _G.UnitChannelInfo = previousUnitChannelInfo
    _G.C_NamePlate = previousNamePlate
    _G.C_UnitAuras = previousAuras
    _G.C_Spell.GetSpellCooldown = previousCooldown
    _G.C_Spell.GetSpellCharges = previousCharges
end)

test("Experimental rule types only fire outside strict mode", function()
    local previous = TrueShot.strictCompliance
    local Engine = TrueShot.Engine
    local profile = {
        id = "Test.Experimental",
        rules = {
            {
                type = "EXPERIMENTAL_PIN",
                spellID = 19574,
                reason = "Experimental BW",
                condition = { type = "ac_suggested", spellID = 19574 },
            },
        },
    }

    Engine.activeProfile = profile
    Engine:RebuildBlacklist()
    set_ac_state(true, 56641, { 56641, 19574 })

    TrueShot.strictCompliance = true
    local strictQueue = Engine:ComputeQueue(2)
    assert_eq(strictQueue[1], 56641,
        "Strict mode must ignore EXPERIMENTAL_PIN and keep AC primary")

    TrueShot.strictCompliance = false
    local experimentalQueue = Engine:ComputeQueue(2)
    assert_eq(experimentalQueue[1], 19574,
        "Experimental mode may fire EXPERIMENTAL_PIN")
    assert_eq(Engine.lastQueueMeta.reasonCode, "EXPERIMENTAL_OVERRIDE")

    TrueShot.strictCompliance = previous
end)

test("Strict mode: legacy PIN/PREFER do not reorder AC even with strict-safe conditions", function()
    local previous = TrueShot.strictCompliance
    local Engine = TrueShot.Engine
    local profile = {
        id = "Test.StrictNoLegacyOverride",
        rules = {
            {
                type = "PREFER",
                spellID = 19574,
                reason = "Strict-safe AC suggested prefer",
                condition = { type = "ac_suggested", spellID = 19574 },
            },
        },
    }

    Engine.activeProfile = profile
    Engine:RebuildBlacklist()
    set_ac_state(true, 56641, { 56641, 19574 })

    TrueShot.strictCompliance = true
    local strictQueue = Engine:ComputeQueue(2)
    assert_eq(strictQueue[1], 56641,
        "Strict mode must not let legacy PREFER reorder the AC primary")

    TrueShot.strictCompliance = false
    local experimentalQueue = Engine:ComputeQueue(2)
    assert_eq(experimentalQueue[1], 19574,
        "Experimental mode keeps legacy PREFER behavior")

    TrueShot.strictCompliance = previous
end)

test("Hunter shipped profiles do not use legacy PIN/PREFER rule types", function()
    local hunterProfiles = {
        "Hunter.BM.DarkRanger",
        "Hunter.BM.PackLeader",
        "Hunter.MM.DarkRanger",
        "Hunter.MM.Sentinel",
        "Hunter.SV.PackLeader",
        "Hunter.SV.Sentinel",
    }

    for _, id in ipairs(hunterProfiles) do
        local profile = P(id)
        for _, rule in ipairs(profile.rules) do
            assert_true(rule.type ~= "PIN" and rule.type ~= "PREFER",
                id .. " must use EXPERIMENTAL_PIN/EXPERIMENTAL_PREFER for live overrides")
        end
    end
end)

test("MM Sentinel fails closed when Trueshot aura is secret", function()
    local profile = P("Hunter.MM.Sentinel")
    profile:OnSpellCast(288613)
    set_player_aura(288613, SECRET)
    assert_false(profile:EvalCondition({ type = "trueshot_active" }),
        "a secret aura must not branch as active or fall back to the cast timer")
end)

test("MM and SV charge helpers fail closed on secret values", function()
    _charges[19434] = { currentCharges = SECRET, maxCharges = 2 }
    assert_false(P("Hunter.MM.Sentinel"):EvalCondition({ type = "aimed_shot_ready" }))

    _charges[259495] = SECRET
    assert_false(P("Hunter.SV.PackLeader"):EvalCondition({
        type = "wfb_charges", op = ">=", value = 1,
    }))

    local sentinelLines = P("Hunter.SV.Sentinel"):GetDebugLines()
    assert_true(type(sentinelLines) == "table", "secret charge debug path must not throw")
end)

------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
