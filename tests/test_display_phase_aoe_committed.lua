-- Executable regressions for committed phase and AoE-hint presentation.

local now = 1000

_G.GetTime = function() return now end
_G.UnitAffectingCombat = function() return true end
_G.UnitExists = function() return false end
_G.UnitCanAttack = function() return false end
_G.issecretvalue = function() return false end
_G.UIParent = {}
_G.C_Timer = { After = function(_, fn) fn() end }
_G.C_Spell = {
    GetSpellTexture = function(id) return 1000 + id end,
}

local fontStrings = {}
local objectMethods = {}
local objectMeta = {
    __index = function(t, key)
        if objectMethods[key] then return objectMethods[key] end
        return function() return t end
    end,
}

local function newObject(kind)
    return setmetatable({
        kind = kind,
        shown = false,
        text = nil,
        textureValue = nil,
        playing = false,
        points = {},
    }, objectMeta)
end

function objectMethods:CreateTexture()
    return newObject("Texture")
end
function objectMethods:CreateFontString()
    local object = newObject("FontString")
    fontStrings[#fontStrings + 1] = object
    return object
end
function objectMethods:CreateMaskTexture() return newObject("MaskTexture") end
function objectMethods:CreateAnimationGroup() return newObject("AnimationGroup") end
function objectMethods:CreateAnimation() return newObject("Animation") end
function objectMethods:GetFrameLevel() return 1 end
function objectMethods:GetName() return self.name or "Stub" end
function objectMethods:GetPoint(index)
    local point = self.points[index or 1]
    if point then return table.unpack(point) end
    return "CENTER", UIParent, "CENTER", 0, 0
end
function objectMethods:IsShown() return self.shown end
function objectMethods:Show() self.shown = true end
function objectMethods:Hide() self.shown = false end
function objectMethods:IsPlaying() return self.playing end
function objectMethods:Play() self.playing = true end
function objectMethods:Stop() self.playing = false end
function objectMethods:SetText(text) self.text = text end
function objectMethods:GetText() return self.text end
function objectMethods:SetTexture(texture) self.textureValue = texture end
function objectMethods:SetPoint(...)
    self.points[#self.points + 1] = { ... }
end
function objectMethods:ClearAllPoints() self.points = {} end

_G.CreateFrame = function(_, name)
    local object = newObject("Frame")
    object.name = name
    if name then _G[name] = object end
    return object
end

local options = {
    iconCount = 1,
    iconSize = 40,
    iconSpacing = 4,
    firstIconScale = 1.3,
    orientation = "LEFT",
    showCooldownSwipe = false,
    showCooldownText = false,
    showCastFeedback = false,
    showKeybinds = false,
    showRangeIndicator = false,
    showWhyOverlay = false,
    showPhaseIndicator = false,
    showOverrideIndicator = false,
    showAoeHint = false,
    showHeartbeat = false,
    showBackdrop = false,
    showIdleState = false,
    overlayScale = 1,
    overlayOpacity = 1,
    locked = false,
}

local liveMeta = {
    source = "none",
    reasonCode = "NO_AC_PRIMARY",
    strictState = false,
}

TrueShot = {
    Engine = {
        lastQueueMeta = liveMeta,
        ComputeQueue = function() return {} end,
    },
    GetOpt = function(key) return options[key] end,
    SetOpt = function(key, value) options[key] = value end,
    RegisterOptCallback = function() end,
    DiagnosticsEnabled = function() return false end,
}

dofile("Display.lua")

local Display = TrueShot.Display
local passed, failed = 0, 0

local function assert_eq(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual), 2)
    end
end

local function find_shown_text(text)
    for _, fontString in ipairs(fontStrings) do
        if fontString:IsShown() and fontString:GetText() == text then
            return fontString
        end
    end
end

local function assert_phase(expected, message)
    local shown = find_shown_text(expected)
    assert(shown, (message or "phase") .. " not shown: " .. tostring(expected))
    return shown
end

local function assert_phase_hidden(message)
    for _, fontString in ipairs(fontStrings) do
        if fontString:IsShown() and fontString:GetText() ~= nil then
            error((message or "phase") .. " unexpectedly showed "
                .. tostring(fontString:GetText()), 2)
        end
    end
end

local function assert_hint(spellID, message)
    local hint = _G.TrueShotAoeHint
    assert_eq(hint and hint:IsShown(), true, (message or "AoE hint") .. " visibility")
    assert_eq(hint.texture.textureValue, 1000 + spellID,
        (message or "AoE hint") .. " texture")
    return hint
end

local function assert_hint_hidden(message)
    local hint = _G.TrueShotAoeHint
    assert_eq(hint == nil or not hint:IsShown(), true, message or "AoE hint hidden")
end

local function reset()
    options.showAoeHint = false
    options.showPhaseIndicator = false
    liveMeta.source = "none"
    liveMeta.reasonCode = "NO_AC_PRIMARY"
    liveMeta.strictState = false
    liveMeta.phase = nil
    liveMeta.aoeHintSpell = nil
    TrueShot.Engine.lastQueueMeta = liveMeta
    _G.issecretvalue = function() return false end
    Display:RenderQueueNow({})
    Display:Disable()
    Display:ResetQueueStabilization()
    now = 1000
end

local function test(name, fn)
    reset()
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. name .. " -- " .. tostring(err))
    end
end

test("T1 pending phase does not replace committed phase", function()
    options.showPhaseIndicator = true
    options.showAoeHint = false
    liveMeta.phase = "Single"
    Display:RenderQueueNow({ 201 })
    local phaseText = assert_phase("Single")

    liveMeta.phase = "Burst"
    Display:ConsumeQueueUpdate({ 202 }, true)
    assert_eq(phaseText:IsShown(), true, "committed phase visibility")
    assert_eq(phaseText:GetText(), "Single", "committed phase text")
end)

test("T2 nil pending phase does not hide committed phase", function()
    options.showPhaseIndicator = true
    options.showAoeHint = false
    liveMeta.phase = "Burst"
    Display:RenderQueueNow({ 201 })
    local phaseText = assert_phase("Burst")

    liveMeta.phase = nil
    Display:ConsumeQueueUpdate({ 202 }, true)
    assert_eq(phaseText:IsShown(), true, "committed phase visibility")
    assert_eq(phaseText:GetText(), "Burst", "committed phase text")
end)

test("T3 pending empty queue keeps the committed AoE hint", function()
    options.showPhaseIndicator = false
    options.showAoeHint = true
    liveMeta.aoeHintSpell = 777001
    Display:RenderQueueNow({ 201 })
    Display:RenderQueueNow({ 201 })
    assert_hint(777001, "committed hint")

    liveMeta.aoeHintSpell = 777002
    for tick = 1, 4 do
        Display:ConsumeQueueUpdate({}, true)
        assert_hint(777001, "pending hide tick " .. tick)
    end
end)

test("T4 empty commit hides an unchanged live AoE hint", function()
    options.showPhaseIndicator = false
    options.showAoeHint = true
    liveMeta.aoeHintSpell = 777001
    Display:RenderQueueNow({ 201 })
    Display:RenderQueueNow({ 201 })
    assert_hint(777001, "precondition")

    Display:RenderQueueNow({})
    assert_hint_hidden("empty commit hint")
end)

test("T5 a hint can reappear after empty commits", function()
    options.showPhaseIndicator = false
    options.showAoeHint = true
    liveMeta.aoeHintSpell = 777003
    Display:RenderQueueNow({})
    Display:RenderQueueNow({})
    Display:RenderQueueNow({ 201 })
    assert_hint(777003, "hint after hidden primary")
end)

test("T6 malformed and secret phase values fail closed", function()
    options.showPhaseIndicator = true
    options.showAoeHint = false
    liveMeta.phase = 42
    Display:RenderQueueNow({ 201 })
    assert_phase_hidden("numeric phase")

    _G.issecretvalue = function(value) return value == "SECRET_PHASE" end
    liveMeta.phase = "SECRET_PHASE"
    Display:RenderQueueNow({ 201 })
    assert_phase_hidden("secret phase")
end)

test("T7 malformed and secret AoE-hint values fail closed", function()
    options.showPhaseIndicator = false
    options.showAoeHint = true
    liveMeta.aoeHintSpell = "1264359"
    Display:RenderQueueNow({ 201 })
    Display:RenderQueueNow({ 201 })
    assert_hint_hidden("string hint")

    _G.issecretvalue = function(value) return value == 1264359 end
    liveMeta.aoeHintSpell = 1264359
    Display:RenderQueueNow({ 201 })
    Display:RenderQueueNow({ 201 })
    assert_hint_hidden("secret hint")
end)

test("T8 Disable and Enable cannot leave a same-spell hint stuck hidden", function()
    options.showPhaseIndicator = false
    options.showAoeHint = true
    Display:Enable()
    liveMeta.aoeHintSpell = 777001
    Display:RenderQueueNow({ 201 })
    Display:RenderQueueNow({ 201 })
    assert_hint(777001, "precondition")

    Display:Disable()
    Display:Enable()
    Display:RenderQueueNow({ 201 })
    assert_hint(777001, "hint after re-enable")
end)

test("T9 strict committed state suppresses phase and AoE hint", function()
    options.showPhaseIndicator = true
    options.showAoeHint = true
    liveMeta.strictState = true
    liveMeta.phase = "X"
    liveMeta.aoeHintSpell = 777001
    Display:RenderQueueNow({ 201 })
    Display:RenderQueueNow({ 201 })
    assert_phase_hidden("strict phase")
    assert_hint_hidden("strict hint")
end)

test("commit and reconfirm update phase synchronously", function()
    options.showPhaseIndicator = true
    options.showAoeHint = false
    liveMeta.phase = "Single"
    Display:RenderQueueNow({ 201 })
    assert_phase("Single", "initial commit")

    liveMeta.phase = "Burst"
    Display:RenderQueueNow({ 201 })
    assert_phase("Burst", "second commit")

    liveMeta.phase = "Execute"
    Display:ConsumeQueueUpdate({ 201 }, true)
    assert_phase("Execute", "reconfirm")
end)

test("phase labels truncate after 24 UTF-8 codepoints", function()
    options.showPhaseIndicator = true
    options.showAoeHint = false
    liveMeta.phase = string.rep("ä", 25)
    Display:RenderQueueNow({ 201 })
    assert_phase(string.rep("ä", 24) .. "…", "truncated phase")
end)

test("invalid UTF-8 phase labels fail closed", function()
    options.showPhaseIndicator = true
    options.showAoeHint = false
    liveMeta.phase = "bad\255phase"
    Display:RenderQueueNow({ 201 })
    assert_phase_hidden("invalid UTF-8 phase")
end)

test("phase and AoE options always hide their presentations", function()
    options.showPhaseIndicator = true
    options.showAoeHint = true
    liveMeta.phase = "Burst"
    liveMeta.aoeHintSpell = 777001
    Display:RenderQueueNow({ 201 })
    Display:RenderQueueNow({ 201 })
    assert_phase("Burst", "precondition")
    assert_hint(777001, "precondition")

    options.showPhaseIndicator = false
    options.showAoeHint = false
    Display:RenderQueueNow({ 201 })
    assert_phase_hidden("disabled phase")
    assert_hint_hidden("disabled hint")
end)

test("non-nil AoE-hint changes retain two-tick stabilization", function()
    options.showPhaseIndicator = false
    options.showAoeHint = true
    liveMeta.aoeHintSpell = 777001
    Display:RenderQueueNow({ 201 })
    Display:RenderQueueNow({ 201 })
    assert_hint(777001, "initial hint")

    liveMeta.aoeHintSpell = 777002
    Display:RenderQueueNow({ 201 })
    assert_hint(777001, "first switch tick")
    Display:RenderQueueNow({ 201 })
    assert_hint(777002, "second switch tick")
end)

test("five-tick hide commit hides phase and AoE hint with the primary", function()
    options.showPhaseIndicator = true
    options.showAoeHint = true
    liveMeta.phase = "Execute"
    liveMeta.aoeHintSpell = 777001
    Display:RenderQueueNow({ 201 })
    Display:RenderQueueNow({ 201 })
    local phaseText = assert_phase("Execute", "precondition")
    assert_hint(777001, "precondition")

    for tick = 1, 4 do
        Display:ConsumeQueueUpdate({}, true)
        assert_eq(phaseText:IsShown(), true, "phase pending tick " .. tick)
        assert_hint(777001, "hint pending tick " .. tick)
    end
    Display:ConsumeQueueUpdate({}, true)
    assert_eq(phaseText:IsShown(), false, "phase at hide commit")
    assert_hint_hidden("hint at hide commit")
end)

if failed > 0 then error(string.format("%d passed, %d failed", passed, failed)) end
print(string.format("%d passed, %d failed", passed, failed))
