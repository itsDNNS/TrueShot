-- Executable regressions for the committed empty-queue presentation.

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
        textColor = nil,
        vertexColor = nil,
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
function objectMethods:SetTextColor(r, g, b, a) self.textColor = { r, g, b, a } end
function objectMethods:SetVertexColor(r, g, b, a) self.vertexColor = { r, g, b, a } end
function objectMethods:SetAtlas(atlas) self.atlas = atlas end
function objectMethods:SetSize(width, height) self.width, self.height = width, height end
function objectMethods:SetScale(scale) self.scale = scale end
function objectMethods:SetWordWrap(enabled) self.wordWrap = enabled end
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
    showWhyOverlay = true,
    showPhaseIndicator = false,
    showOverrideIndicator = true,
    showAoeHint = false,
    showHeartbeat = false,
    showBackdrop = false,
    showIdleState = true,
    overlayScale = 1,
    overlayOpacity = 1,
    locked = false,
}

local liveMeta = {
    source = "none",
    reason = nil,
    reasonCode = "NO_AC_PRIMARY",
    strictState = false,
    fallbackDropReason = "raw_ac_nil",
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
local IDLE_WAITING = "Waiting for Assisted Combat"
local IDLE_FILTERED = "No action (filtered)"

liveMeta.source = "pin"
liveMeta.reason = "reason-text-probe"
liveMeta.reasonCode = "EXPERIMENTAL_OVERRIDE"
liveMeta.strictState = false
Display:RenderQueueNow({ 999001 })

local reasonText
for _, fontString in ipairs(fontStrings) do
    if fontString:IsShown() and fontString:GetText() == "Experimental: reason-text-probe" then
        reasonText = fontString
        break
    end
end
assert(reasonText, "reasonText font string not found after controlled render")

local passed, failed = 0, 0

local function set_meta(strictState, fallbackDropReason)
    liveMeta.source = "none"
    liveMeta.reason = nil
    liveMeta.reasonCode = "NO_AC_PRIMARY"
    liveMeta.strictState = strictState
    liveMeta.fallbackDropReason = fallbackDropReason
    liveMeta.phase = nil
    liveMeta.rotationCatalogSnapshot = nil
    TrueShot.Engine.lastQueueMeta = liveMeta
end

local function assert_eq(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual), 2)
    end
end

local function assert_contains(text, needle, message)
    if not text:find(needle, 1, true) then
        error(message or ("missing expected text: " .. needle), 2)
    end
end

local function assert_not_contains(text, needle, message)
    if text:find(needle, 1, true) then
        error(message or ("unexpected text: " .. needle), 2)
    end
end

local function read_file(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local function find_shown_text(text)
    for _, fontString in ipairs(fontStrings) do
        if fontString:IsShown() and fontString:GetText() == text then
            return fontString
        end
    end
end

local function assert_idle(expected, message)
    local idleFrame = _G.TrueShotIdleFrame
    local idleText = find_shown_text(expected)
    assert_eq(idleFrame and idleFrame:IsShown(), true, (message or "idle state") .. " frame")
    assert(idleText, (message or "idle state") .. " text not shown")
    return idleFrame, idleText
end

local function assert_idle_hidden(message)
    local idleFrame = _G.TrueShotIdleFrame
    assert_eq(idleFrame == nil or not idleFrame:IsShown(), true,
        (message or "idle state") .. " frame hidden")
    for _, fontString in ipairs(fontStrings) do
        if fontString:IsShown() then
            assert_eq(fontString:GetText() == IDLE_WAITING or fontString:GetText() == IDLE_FILTERED,
                false, (message or "idle state") .. " text hidden")
        end
    end
end

local function test(name, fn)
    Display:ResetQueueStabilization()
    now = 1000
    options.showIdleState = true
    options.showPhaseIndicator = false
    set_meta(false, "raw_ac_nil")
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. name .. " -- " .. tostring(err))
    end
end

test("committed empty queue lazily creates the muted idle presentation", function()
    assert_eq(_G.TrueShotIdleFrame, nil, "idle frame should be lazy")
    Display:RenderQueueNow({})

    local idleFrame, idleText = assert_idle(IDLE_WAITING)
    assert(idleText ~= reasonText, "idle status must not reuse reasonText")
    assert_eq(idleText.wordWrap, false, "idle text word wrapping")
    assert_eq(idleText.textColor[1], 0.6, "idle text red")
    assert_eq(idleText.textColor[2], 0.6, "idle text green")
    assert_eq(idleText.textColor[3], 0.6, "idle text blue")
    assert_eq(idleText.textColor[4], 0.9, "idle text alpha")
    assert_eq(idleFrame.slotBackground.atlas,
        "UI-HUD-ActionBar-IconFrame-Background", "idle background atlas")
    assert_eq(idleFrame.border.atlas, "UI-HUD-ActionBar-IconFrame", "idle border atlas")
    assert_eq(rawget(idleFrame, "texture"), nil, "idle frame texture")
    assert_eq(rawget(idleFrame, "keybind"), nil, "idle frame keybind")
    assert_eq(rawget(idleFrame, "glow"), nil, "idle frame glow")
    assert_eq(idleFrame.scale, options.firstIconScale, "idle frame primary scale")
    assert_eq(idleFrame.points[1][2], _G.TrueShotIcon1, "idle frame primary anchor")
end)

test("filtered committed drops use the filtered label", function()
    for _, reason in ipairs({ "raw_ac_blacklisted", "raw_ac_locally_uncastable" }) do
        set_meta(false, reason)
        Display:RenderQueueNow({})
        assert_idle(IDLE_FILTERED, reason)
    end
end)

test("waiting drop classes and unknown values use the waiting label", function()
    local reasons = {
        "raw_ac_nil",
        "raw_ac_secret",
        "raw_ac_error",
        "raw_ac_invalid",
        "assisted_combat_unavailable",
        "no_active_profile",
        "unexpected_code",
        42,
    }
    for _, reason in ipairs(reasons) do
        set_meta(false, reason)
        Display:RenderQueueNow({})
        assert_idle(IDLE_WAITING, tostring(reason))
    end
    set_meta(false, nil)
    Display:RenderQueueNow({})
    assert_idle(IDLE_WAITING, "nil reason")

    set_meta(true, "raw_ac_blacklisted")
    Display:RenderQueueNow({})
    assert_idle(IDLE_WAITING, "strict state")
end)

test("pending metadata does not replace committed idle status", function()
    set_meta(false, "raw_ac_nil")
    Display:RenderQueueNow({})
    local _, idleText = assert_idle(IDLE_WAITING, "committed waiting state")

    set_meta(false, "raw_ac_blacklisted")
    Display:ConsumeQueueUpdate({ 101 }, true)
    assert_eq(idleText:IsShown(), true, "pending idle text visibility")
    assert_eq(idleText:GetText(), IDLE_WAITING, "pending idle text")
end)

test("phase text is hidden for an empty committed queue", function()
    options.showPhaseIndicator = true
    liveMeta.phase = "Phase text probe"
    Display:RenderQueueNow({ 201 })
    local phaseText = find_shown_text("Phase text probe")
    assert(phaseText, "phaseText font string not found after primary render")

    liveMeta.phase = "Phase text probe"
    Display:RenderQueueNow({})
    assert_eq(phaseText:IsShown(), false, "phase text on empty committed queue")
end)

test("nil live metadata commits a cleared idle snapshot", function()
    set_meta(false, "raw_ac_blacklisted")
    Display:RenderQueueNow({})

    TrueShot.Engine.lastQueueMeta = nil
    Display:RenderQueueNow({})
    assert_idle(IDLE_WAITING, "nil metadata")

    local recordedMeta
    TrueShot.CombatTrace = {
        RecordCast = function(_, _, _, _, _, _, meta)
            recordedMeta = meta
        end,
    }
    Display:OnSpellCastSucceeded(301)
    TrueShot.CombatTrace = nil
    TrueShot.Engine.lastQueueMeta = liveMeta

    assert(recordedMeta, "nil metadata snapshot was not recorded")
    assert_eq(recordedMeta.fallbackDropReason, nil, "nil metadata fallback reason")
end)

test("empty queue honors five-tick hide stabilization", function()
    Display:RenderQueueNow({ 401 })
    assert_idle_hidden("primary precondition")

    for tick = 1, 4 do
        Display:ConsumeQueueUpdate({}, true)
        assert_idle_hidden("hide stabilization tick " .. tick)
    end
    Display:ConsumeQueueUpdate({}, true)
    assert_idle(IDLE_WAITING, "hide stabilization commit")
end)

test("a committed primary hides every idle artifact", function()
    Display:RenderQueueNow({})
    local idleFrame, idleText = assert_idle(IDLE_WAITING, "idle precondition")

    Display:RenderQueueNow({ 501 })
    assert_eq(idleFrame:IsShown(), false, "idle frame after primary")
    assert_eq(idleText:IsShown(), false, "idle text after primary")
end)

test("rotation catalog snapshots are never rendered as idle status", function()
    local catalogMarker = "rotationCatalogSnapshot fallback raw_ac_blacklisted"
    set_meta(false, "raw_ac_nil")
    liveMeta.rotationCatalogSnapshot = catalogMarker
    Display:RenderQueueNow({})
    assert_idle(IDLE_WAITING)

    for _, fontString in ipairs(fontStrings) do
        if fontString:IsShown() and fontString:GetText() then
            assert_not_contains(fontString:GetText(), catalogMarker)
        end
    end
end)

test("idle labels never expose internal codes", function()
    for _, reason in ipairs({ "raw_ac_blacklisted", "raw_ac_nil", "fallback" }) do
        set_meta(false, reason)
        Display:RenderQueueNow({})
        local label = assert_idle(reason == "raw_ac_blacklisted" and IDLE_FILTERED or IDLE_WAITING)
        local idleText = find_shown_text(reason == "raw_ac_blacklisted" and IDLE_FILTERED or IDLE_WAITING)
        assert(label and idleText, "idle presentation missing")
        assert_not_contains(idleText:GetText(), "raw_ac")
        assert_not_contains(idleText:GetText(), "NO_AC_PRIMARY")
        assert_not_contains(idleText:GetText(), "fallback")
    end
end)

test("showIdleState false preserves the blank-overlay behavior", function()
    options.showIdleState = false
    Display:RenderQueueNow({})
    assert_idle_hidden("disabled idle option")
end)

test("Disable hides both idle artifacts", function()
    Display:RenderQueueNow({})
    local idleFrame, idleText = assert_idle(IDLE_WAITING, "disable precondition")
    Display:Disable()
    assert_eq(idleFrame:IsShown(), false, "disabled idle frame")
    assert_eq(idleText:IsShown(), false, "disabled idle text")
end)

test("settings expose the idle-state option", function()
    local settings = read_file("SettingsPanel.lua")
    assert_contains(settings, "Show idle placeholder",
        "settings should name the idle-state option")
    assert_contains(settings,
        "When no legal recommendation exists, show a muted empty slot and a short status line instead of a blank overlay.",
        "settings should explain the idle-state option")
end)

if failed > 0 then error(string.format("%d passed, %d failed", passed, failed)) end
print(string.format("%d passed, %d failed", passed, failed))
