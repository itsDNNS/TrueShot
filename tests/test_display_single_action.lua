-- Executable regressions for the single-action display hierarchy.

local now = 1000

_G.GetTime = function() return now end
_G.UnitAffectingCombat = function() return false end
_G.UnitExists = function() return false end
_G.UnitCanAttack = function() return false end
_G.GetBindingKey = function(command)
    if command == "ACTIONBUTTON1" then return "3" end
    if command == "ACTIONBUTTON2" then return "4" end
    return nil
end
_G.GetActionInfo = function(slot)
    if slot == 1 then return "spell", 101 end
    if slot == 2 then return "spell", 202 end
    return nil
end
_G.issecretvalue = function() return false end
_G.wipe = function(t)
    for key in pairs(t) do t[key] = nil end
    return t
end
_G.UIParent = {}
_G.C_Timer = { After = function(_, fn) fn() end }
_G.C_Spell = {
    GetSpellName = function(id) return "Spell " .. id end,
    GetSpellTexture = function(id) return 1000 + id end,
}
_G.ActionButton1 = { action = 1 }
_G.ActionButton2 = { action = 2 }

local objectMethods = {}
local objectMeta = {
    __index = function(t, key)
        if objectMethods[key] then return objectMethods[key] end
        return function() return t end
    end,
}

local function newObject(name)
    return setmetatable({ name = name, shown = false, text = nil }, objectMeta)
end

function objectMethods:CreateTexture() return newObject() end
function objectMethods:CreateFontString() return newObject() end
function objectMethods:CreateMaskTexture() return newObject() end
function objectMethods:CreateAnimationGroup() return newObject() end
function objectMethods:CreateAnimation() return newObject() end
function objectMethods:GetFrameLevel() return 1 end
function objectMethods:GetName() return self.name or "Stub" end
function objectMethods:GetPoint() return "CENTER", UIParent, "CENTER", 0, 0 end
function objectMethods:IsShown() return self.shown end
function objectMethods:Show() self.shown = true end
function objectMethods:Hide() self.shown = false end
function objectMethods:IsPlaying() return false end
function objectMethods:SetText(text) self.text = text end

_G.CreateFrame = function(_, name)
    local object = newObject(name)
    if name then _G[name] = object end
    return object
end

local options = {
    iconCount = 2,
    iconSize = 40,
    iconSpacing = 4,
    firstIconScale = 1.3,
    orientation = "LEFT",
    showCooldownSwipe = false,
    showCooldownText = false,
    showCastFeedback = true,
    showKeybinds = true,
    showRangeIndicator = false,
    showWhyOverlay = false,
    showPhaseIndicator = false,
    showOverrideIndicator = false,
    showAoeHint = false,
    showHeartbeat = false,
    showBackdrop = false,
    overlayScale = 1,
    overlayOpacity = 1,
    locked = false,
}

TrueShot = {
    Engine = {
        lastQueueMeta = { source = "ac" },
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

local function read_file(path)
    local f = assert(io.open(path, "r"))
    local text = f:read("*a")
    f:close()
    return text
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

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. name .. " -- " .. tostring(err))
    end
end

test("keybind renders only on the action icon", function()
    Display:UpdateQueue({ 101, 202 })
    assert_eq(_G.TrueShotIcon1.keybind.text, "3", "action icon keybind")
    assert_eq(_G.TrueShotIcon2.keybind.text, "", "context icon keybind")
end)

test("cast-success flash only on the action icon", function()
    Display:UpdateQueue({ 101, 202 })
    Display:OnSpellCastSucceeded(202)
    assert_eq(_G.TrueShotIcon2.success.shown, false, "context icon success texture")
    assert_eq(_G.TrueShotIcon2.successUntil, 0, "context icon success deadline")

    Display:OnSpellCastSucceeded(101)
    assert_eq(_G.TrueShotIcon1.success.shown, true, "action icon success texture")
end)

test("single-action default", function()
    local core = read_file("Core.lua")
    assert_contains(core, "iconCount = 1", "Core should default to one action icon")
    assert_not_contains(core, "iconCount = 2", "Core should not default to two icons")
end)

test("settings copy demotes context icons", function()
    local settings = read_file("SettingsPanel.lua")
    assert_not_contains(settings, "Queue Layout", "settings should rename Queue Layout")
    assert_contains(settings, "Icons (first = next action, rest = context)",
        "settings should identify additional icons as context")
end)

if failed > 0 then error(string.format("%d passed, %d failed", passed, failed)) end
print(string.format("%d passed, %d failed", passed, failed))
