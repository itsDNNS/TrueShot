-- Executable regressions for committed display decision-source metadata.

local now = 1000
local secretReason

_G.GetTime = function() return now end
_G.UnitAffectingCombat = function() return true end
_G.UnitExists = function() return false end
_G.UnitCanAttack = function() return false end
_G.issecretvalue = function(value) return value ~= nil and value == secretReason end
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
    }, objectMeta)
end

function objectMethods:CreateTexture() return newObject("Texture") end
function objectMethods:CreateFontString()
    local object = newObject("FontString")
    fontStrings[#fontStrings + 1] = object
    return object
end
function objectMethods:CreateMaskTexture() return newObject("MaskTexture") end
function objectMethods:CreateAnimationGroup() return newObject("AnimationGroup") end
function objectMethods:CreateAnimation() return newObject("Animation") end
function objectMethods:GetFrameLevel() return 1 end
function objectMethods:GetName() return "Stub" end
function objectMethods:GetPoint() return "CENTER", UIParent, "CENTER", 0, 0 end
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

_G.CreateFrame = function(_, name)
    local object = newObject("Frame")
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
    overlayScale = 1,
    overlayOpacity = 1,
    locked = false,
}

local liveMeta = {
    source = "none",
    reason = nil,
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
local reasonMarker = "reason-text-probe"
liveMeta.source = "pin"
liveMeta.reason = reasonMarker
liveMeta.reasonCode = "EXPERIMENTAL_OVERRIDE"
liveMeta.strictState = false
Display:RenderQueueNow({ 999001 })

local reasonText
for _, fontString in ipairs(fontStrings) do
    if fontString:IsShown() and fontString:GetText() == "Experimental: " .. reasonMarker then
        reasonText = fontString
        break
    end
end
assert(reasonText, "reasonText font string not found after controlled render")
local passed, failed = 0, 0

local function set_meta(source, reason, reasonCode, strictState)
    liveMeta.source = source
    liveMeta.reason = reason
    liveMeta.reasonCode = reasonCode
    liveMeta.strictState = strictState
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

local function assert_glow(expected, message)
    local icon = _G.TrueShotIcon1
    assert_eq(icon and icon.glow and icon.glow.shown, expected, message or "primary glow")
end

local function assert_label(expected, message)
    assert_eq(reasonText.shown, expected ~= nil, (message or "decision label") .. " visibility")
    if expected ~= nil then
        assert_eq(reasonText.text, expected, (message or "decision label") .. " text")
    end
end

local function assert_text_color(r, g, b, a, message)
    local actual = reasonText.textColor or {}
    assert_eq(actual[1], r, (message or "decision label color") .. " red")
    assert_eq(actual[2], g, (message or "decision label color") .. " green")
    assert_eq(actual[3], b, (message or "decision label color") .. " blue")
    assert_eq(actual[4], a, (message or "decision label color") .. " alpha")
end

local function test(name, fn)
    Display:ResetQueueStabilization()
    now = 1000
    secretReason = nil
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. name .. " -- " .. tostring(err))
    end
end

test("pending AC metadata does not replace committed experimental presentation", function()
    set_meta("pin", "KC Proc", "EXPERIMENTAL_OVERRIDE", false)
    Display:RenderQueueNow({ 101 })
    assert_label("Experimental: KC Proc")
    assert_glow(true)

    set_meta("ac", nil, "AC_PRIMARY", false)
    Display:ConsumeQueueUpdate({ 202 }, true)
    assert_label("Experimental: KC Proc", "pending decision label")
    assert_glow(true, "pending primary glow")

    Display:ConsumeQueueUpdate({ 202 }, true)
    assert_label("Assisted Combat", "committed decision label")
    assert_glow(false, "committed primary glow")

    local snapshot = Display:GetDecisionSourceSnapshot()
    assert_eq(snapshot.shown, true, "snapshot shown")
    assert_eq(snapshot.label, "Assisted Combat", "snapshot label")
    assert_eq(snapshot.source, "ac", "snapshot source")
    assert_eq(snapshot.reasonCode, "AC_PRIMARY", "snapshot reason code")
    assert_eq(snapshot.strictState, false, "snapshot strict state")
end)

test("pending experimental metadata does not glow until commit", function()
    set_meta("ac", nil, "AC_PRIMARY", false)
    Display:RenderQueueNow({ 301 })
    assert_label("Assisted Combat")
    assert_glow(false)

    set_meta("prefer", "Focus cap", "EXPERIMENTAL_OVERRIDE", false)
    Display:ConsumeQueueUpdate({ 302 }, true)
    assert_label("Assisted Combat", "pending decision label")
    assert_glow(false, "pending primary glow")

    Display:ConsumeQueueUpdate({ 302 }, true)
    assert_label("Experimental: Focus cap", "committed decision label")
    assert_glow(true, "committed primary glow")
end)

test("same queue reconfirms changed decision source without changing icon", function()
    set_meta("pin", "KC Proc", "EXPERIMENTAL_OVERRIDE", false)
    Display:RenderQueueNow({ 401 })

    set_meta("ac", nil, "AC_PRIMARY", false)
    Display:ConsumeQueueUpdate({ 401 }, true)

    assert_label("Assisted Combat")
    assert_glow(false)
    assert_eq(Display:GetStabilizationSnapshot().displayedPrimary, 401, "displayed primary")
end)

test("strict mode never shows decision label or glow", function()
    set_meta("pin", "KC Proc", "EXPERIMENTAL_OVERRIDE", true)
    Display:RenderQueueNow({ 501 })
    assert_label(nil)
    assert_glow(false)
end)

test("empty queue with no AC primary hides decision source", function()
    set_meta("pin", "KC Proc", "EXPERIMENTAL_OVERRIDE", false)
    Display:RenderQueueNow({ 550 })
    assert_label("Experimental: KC Proc", "precondition decision label")
    assert_glow(true, "precondition primary glow")

    set_meta("none", nil, "NO_AC_PRIMARY", false)
    Display:RenderQueueNow({})
    assert_label(nil, "empty queue decision label")
    assert_glow(false, "empty queue primary glow")
end)

test("experimental reason is limited to 24 characters", function()
    local longReason = string.rep("A", 40)
    set_meta("pin", longReason, "EXPERIMENTAL_OVERRIDE", false)
    Display:RenderQueueNow({ 601 })
    assert_label("Experimental: " .. string.rep("A", 24) .. "…")

    local unicodeBoundaryReason = string.rep("A", 23) .. "ä" .. string.rep("B", 16)
    set_meta("pin", unicodeBoundaryReason, "EXPERIMENTAL_OVERRIDE", false)
    Display:RenderQueueNow({ 602 })
    assert_label("Experimental: " .. string.rep("A", 23) .. "ä…",
        "UTF-8 decision label")
end)

test("experimental reason validates UTF-8 after the truncation boundary", function()
    local invalidTrailingReason = string.rep("A", 24) .. string.char(0xFF)
    set_meta("pin", invalidTrailingReason, "EXPERIMENTAL_OVERRIDE", false)
    Display:RenderQueueNow({ 603 })
    assert_label("Experimental override", "invalid trailing UTF-8 reason label")
end)

test("non-string and secret reasons use the generic experimental label", function()
    set_meta("prefer", { hidden = true }, "EXPERIMENTAL_OVERRIDE", false)
    Display:RenderQueueNow({ 701 })
    assert_label("Experimental override", "non-string reason label")

    secretReason = "Hidden rule reason"
    set_meta("hybrid", secretReason, "EXPERIMENTAL_OVERRIDE", false)
    Display:RenderQueueNow({ 702 })
    assert_label("Experimental override", "secret reason label")
end)

test("empty experimental reason uses the generic experimental label", function()
    set_meta("pin", "", "EXPERIMENTAL_OVERRIDE", false)
    Display:RenderQueueNow({ 703 })
    assert_label("Experimental override", "empty reason label")
end)

test("decision-source tiers use distinct text colors", function()
    set_meta("ac", nil, "AC_PRIMARY", false)
    Display:RenderQueueNow({ 801 })
    assert_text_color(0.75, 0.85, 1.0, 0.9, "Assisted Combat color")

    set_meta("pin", "KC Proc", "EXPERIMENTAL_OVERRIDE", false)
    Display:RenderQueueNow({ 802 })
    assert_text_color(1.0, 0.72, 0.2, 0.9, "experimental color")
end)

test("rendered labels never expose internal decision codes", function()
    local renderedLabels = {}

    set_meta("ac", nil, "AC_PRIMARY", false)
    Display:RenderQueueNow({ 901 })
    renderedLabels[#renderedLabels + 1] = reasonText.text

    for index, source in ipairs({ "pin", "prefer", "hybrid" }) do
        set_meta(source, "Readable rule", "EXPERIMENTAL_OVERRIDE", false)
        Display:RenderQueueNow({ 901 + index })
        renderedLabels[#renderedLabels + 1] = reasonText.text
    end

    for _, label in ipairs(renderedLabels) do
        assert_not_contains(label, "AC_PRIMARY")
        assert_not_contains(label, "pin")
        assert_not_contains(label, "prefer")
        assert_not_contains(label, "hybrid")
    end
end)

test("missing queue metadata commits a cleared strict snapshot", function()
    set_meta("pin", "Stale override", "EXPERIMENTAL_OVERRIDE", false)
    liveMeta.rawACStatus = "ready"
    liveMeta.rotationCatalogRole = "primary"
    Display:RenderQueueNow({ 950 })

    TrueShot.Engine.lastQueueMeta = nil
    Display:RenderQueueNow({ 951 })
    local snapshot = Display:GetDecisionSourceSnapshot()

    local recordedSource
    local recordedMeta
    TrueShot.CombatTrace = {
        RecordCast = function(_, _, _, source, _, _, meta)
            recordedSource = source
            recordedMeta = {
                source = meta.source,
                reason = meta.reason,
                reasonCode = meta.reasonCode,
                rawACStatus = meta.rawACStatus,
                strictState = meta.strictState,
                rotationCatalogRole = meta.rotationCatalogRole,
            }
        end,
    }
    Display:OnSpellCastSucceeded(951)

    TrueShot.Engine.lastQueueMeta = liveMeta
    TrueShot.CombatTrace = nil
    liveMeta.rawACStatus = nil
    liveMeta.rotationCatalogRole = nil

    assert_eq(snapshot.shown, false, "nil-meta snapshot shown")
    assert_eq(snapshot.label, nil, "nil-meta snapshot label")
    assert_eq(snapshot.source, "none", "nil-meta snapshot source")
    assert_eq(snapshot.reasonCode, nil, "nil-meta snapshot reason code")
    assert_eq(snapshot.strictState, true, "nil-meta snapshot strict state")
    assert(recordedMeta, "nil-meta cast metadata was not recorded")
    assert_eq(recordedSource, "none", "nil-meta positional cast source")
    assert_eq(recordedMeta.source, "none", "nil-meta cast source")
    assert_eq(recordedMeta.reason, nil, "nil-meta cast reason")
    assert_eq(recordedMeta.reasonCode, nil, "nil-meta cast reason code")
    assert_eq(recordedMeta.rawACStatus, nil, "nil-meta cast raw AC status")
    assert_eq(recordedMeta.strictState, true, "nil-meta cast strict state")
    assert_eq(recordedMeta.rotationCatalogRole, nil, "nil-meta cast catalog role")
end)

test("settings describe the user-facing decision source", function()
    local settings = read_file("SettingsPanel.lua")
    assert_contains(settings, "Experimental: show decision source",
        "settings should name the decision-source display")
    assert_contains(settings,
        "label the primary icon as Blizzard's Assisted Combat recommendation or an experimental override with a short rule reason.",
        "settings should explain both decision-source tiers")
    assert_not_contains(settings, "Experimental: show override reason",
        "settings should not retain the override-only title")
end)

if failed > 0 then error(string.format("%d passed, %d failed", passed, failed)) end
print(string.format("%d passed, %d failed", passed, failed))
