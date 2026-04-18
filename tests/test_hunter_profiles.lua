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
_G.issecretvalue = function(_) return false end
_G.pcall = pcall

-- Minimal C_Spell stub: treat charges as a plain table keyed by spellID so tests
-- can drive `spell_charges` conditions deterministically.
local _charges = {}
local function set_charges(spellID, current, max)
    _charges[spellID] = { currentCharges = current, maxCharges = max or current }
end
_G.C_Spell = _G.C_Spell or {}
_G.C_Spell.GetSpellCharges = function(spellID) return _charges[spellID] end

-- MM Sentinel probes the player Trueshot aura as the primary signal, with a
-- timer fallback only when the API is absent. Tests drive both paths by
-- swapping the stub.
_G.C_UnitAuras = _G.C_UnitAuras or {}
local _auras_by_spell = {}
local function set_player_aura(spellID, aura)
    _auras_by_spell[spellID] = aura
end
_G.C_UnitAuras.GetPlayerAuraBySpellID = function(spellID)
    return _auras_by_spell[spellID]
end

------------------------------------------------------------------------
-- Minimal Engine + CustomProfile stubs that capture registered profiles
------------------------------------------------------------------------

TrueShot = {}
local registered = {}

TrueShot.Engine = {
    RegisterProfile = function(_, profile)
        registered[profile.id] = profile
    end,
}

TrueShot.CustomProfile = {
    RegisterConditionSchema = function(_, _) end,
}

------------------------------------------------------------------------
-- Load all Hunter profiles into the capture table
------------------------------------------------------------------------

dofile("Profiles/BM_DarkRanger.lua")
dofile("Profiles/BM_PackLeader.lua")
dofile("Profiles/MM_DarkRanger.lua")
dofile("Profiles/MM_Sentinel.lua")
dofile("Profiles/SV_PackLeader.lua")
dofile("Profiles/SV_Sentinel.lua")

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
    set_time(1000.0)
    _charges = {}
    _auras_by_spell = {}

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

test("BM PL: Stampede PIN is ordered before the KC Proc PIN (first-match-wins)", function()
    local p = P("Hunter.BM.PackLeader")
    local stampedeIdx, kcProcIdx = nil, nil
    for i, rule in ipairs(p.rules) do
        if rule.type == "PIN" and rule.spellID == 34026 then
            if rule.reason == "Stampede" then stampedeIdx = i
            elseif rule.reason == "KC Proc" then kcProcIdx = i end
        end
    end
    assert_true(stampedeIdx, "Stampede PIN rule must exist")
    assert_true(kcProcIdx, "KC Proc PIN rule must exist")
    assert_true(stampedeIdx < kcProcIdx,
        "Engine ComputeQueue iterates rules in order and takes the first PIN whose " ..
        "condition is true (Engine.lua:337). To make the post-BW queue surface " ..
        "reason='Stampede', the Stampede rule must be declared before the KC Proc rule.")
end)

test("BM PL: bw_on_cd blocks re-cast inside the 30s window", function()
    local p = P("Hunter.BM.PackLeader")
    p:OnSpellCast(19574)
    advance_time(10)
    assert_true(p:EvalCondition({ type = "bw_on_cd" }), "BW should be on CD at +10s")
    advance_time(25) -- total 35s, past the 30s CD
    assert_false(p:EvalCondition({ type = "bw_on_cd" }), "BW should be off CD at +35s")
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

------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
