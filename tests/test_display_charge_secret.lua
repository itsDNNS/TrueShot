-- Executable SecretValue regressions for the real Display charge path.

local SECRET = {}
local chargeResult = nil

_G.GetTime = function() return 1000 end
_G.UnitAffectingCombat = function() return false end
_G.UnitExists = function() return false end
_G.UnitCanAttack = function() return false end
_G.GetBindingKey = function() return nil end
_G.issecretvalue = function(value) return value == SECRET end
_G.wipe = function(t) for key in pairs(t) do t[key] = nil end return t end
_G.UIParent = {}
_G.C_Timer = { After = function(_, fn) fn() end }
_G.C_Spell = {
    GetSpellCharges = function() return chargeResult end,
}

local objectMethods = {}
local objectMeta = {
    __index = function(t, key)
        if objectMethods[key] then return objectMethods[key] end
        return function() return t end
    end,
}

local function newObject()
    return setmetatable({ shown = false }, objectMeta)
end

function objectMethods:CreateTexture() return newObject() end
function objectMethods:CreateFontString() return newObject() end
function objectMethods:CreateMaskTexture() return newObject() end
function objectMethods:CreateAnimationGroup() return newObject() end
function objectMethods:CreateAnimation() return newObject() end
function objectMethods:GetFrameLevel() return 1 end
function objectMethods:GetName() return "Stub" end
function objectMethods:GetPoint() return "CENTER", UIParent, "CENTER", 0, 0 end
function objectMethods:IsShown() return self.shown end
function objectMethods:Show() self.shown = true end
function objectMethods:Hide() self.shown = false end
function objectMethods:IsPlaying() return false end

_G.CreateFrame = function() return newObject() end

local options = {
    showCooldownSwipe = true,
    locked = false,
}

TrueShot = {
    Engine = {},
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
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function newIcon()
    local chargeCount = { shown = true, values = {} }
    function chargeCount:SetText(value)
        if value == SECRET then error("secret value reached SetText") end
        self.values[#self.values + 1] = value
    end
    function chargeCount:Show() self.shown = true end
    function chargeCount:Hide() self.shown = false end

    local chargeCooldown = { shown = true, setCalls = {} }
    function chargeCooldown:SetCooldown(startTime, duration, modRate)
        self.setCalls[#self.setCalls + 1] = { startTime, duration, modRate }
    end
    function chargeCooldown:Show() self.shown = true end
    function chargeCooldown:Hide() self.shown = false end

    return { chargeCount = chargeCount, chargeCooldown = chargeCooldown }
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

test("secret charge result clears and hides without reaching SetText", function()
    chargeResult = SECRET
    local icon = newIcon()
    Display:UpdateChargeCooldown(icon, 101)
    assert_eq(icon.chargeCount.values[#icon.chargeCount.values], "")
    assert_eq(icon.chargeCount.shown, false)
    assert_eq(icon.chargeCooldown.shown, false)
end)

test("secret currentCharges clears and hides without reaching SetText", function()
    chargeResult = { currentCharges = SECRET, maxCharges = 2 }
    local icon = newIcon()
    Display:UpdateChargeCooldown(icon, 202)
    assert_eq(icon.chargeCount.values[#icon.chargeCount.values], "")
    assert_eq(icon.chargeCount.shown, false)
    assert_eq(icon.chargeCooldown.shown, false)
end)

test("readable charges retain count and cooldown behavior", function()
    chargeResult = {
        currentCharges = 1,
        maxCharges = 2,
        cooldownStartTime = 10,
        cooldownDuration = 6,
        chargeModRate = 1,
    }
    local icon = newIcon()
    Display:UpdateChargeCooldown(icon, 303)
    assert_eq(icon.chargeCount.values[#icon.chargeCount.values], 1)
    assert_eq(icon.chargeCount.shown, true)
    assert_eq(#icon.chargeCooldown.setCalls, 1)
    assert_eq(icon.chargeCooldown.setCalls[1][1], 10)
    assert_eq(icon.chargeCooldown.setCalls[1][2], 6)
    assert_eq(icon.chargeCooldown.setCalls[1][3], 1)
    assert_eq(icon.chargeCooldown.shown, true)
end)

if failed > 0 then error(string.format("%d passed, %d failed", passed, failed)) end
print(string.format("%d passed, %d failed", passed, failed))
