-- Executable queue-stabilization regression tests.

local now = 1000
_G.GetTime = function() return now end
_G.UnitAffectingCombat = function() return true end
_G.UnitExists = function() return false end
_G.UnitCanAttack = function() return false end
_G.issecretvalue = function() return false end
_G.UIParent = {}
_G.C_Timer = { After = function(_, fn) fn() end }

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
    overlayScale = 1,
    overlayOpacity = 1,
    locked = false,
}

TrueShot = {
    Engine = {
        lastQueueMeta = { source = "ac", reason = nil },
        ComputeQueue = function() return {} end,
    },
    GetOpt = function(key) return options[key] end,
    SetOpt = function(key, value) options[key] = value end,
    RegisterOptCallback = function() end,
    DiagnosticsEnabled = function() return true end,
}

dofile("Display.lua")

local Display = TrueShot.Display
Display.UpdateQueue = function() end

local passed, failed = 0, 0
local function assert_eq(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end
local function test(name, fn)
    Display:ResetQueueStabilization()
    now = 1000
    local ok, err = pcall(fn)
    if ok then passed = passed + 1 else
        failed = failed + 1
        print("FAIL: " .. name .. " -- " .. tostring(err))
    end
end

test("A/B/A/B oscillation commits newest candidate by absolute stale deadline", function()
    Display:RenderQueueNow({ 900 })

    now = 1000.00
    Display:ConsumeQueueUpdate({ 101 }, true)
    now = 1000.10
    Display:ConsumeQueueUpdate({ 202 }, true)
    now = 1000.20
    Display:ConsumeQueueUpdate({ 101 }, true)

    local pending = Display:GetStabilizationSnapshot()
    assert_eq(pending.displayedPrimary, 900)
    assert_eq(pending.pendingPrimary, 101)
    assert_eq(pending.pendingTicks, 1)
    assert_eq(pending.staleDeadlineForcedLastCommit, false)

    now = 1000.30
    Display:ConsumeQueueUpdate({ 202 }, true)

    local committed = Display:GetStabilizationSnapshot()
    assert_eq(committed.displayedPrimary, 202)
    assert_eq(committed.pendingPrimary, nil)
    assert_eq(committed.pendingTicks, 0)
    assert_eq(committed.staleDeadlineForcedLastCommit, true)
end)

test("explicit flush still commits immediately", function()
    Display:RenderQueueNow({ 303 })
    Display:FlushQueueStabilization()
    now = 1000.01
    Display:ConsumeQueueUpdate({ 404 }, true)
    local snapshot = Display:GetStabilizationSnapshot()
    assert_eq(snapshot.displayedPrimary, 404)
    assert_eq(snapshot.staleDeadlineForcedLastCommit, false)
end)

test("explicit reset permits the next combat update immediately", function()
    Display:RenderQueueNow({ 505 })
    Display:ResetQueueStabilization()
    now = 1000.01
    Display:ConsumeQueueUpdate({ 606 }, true)
    local snapshot = Display:GetStabilizationSnapshot()
    assert_eq(snapshot.displayedPrimary, 606)
    assert_eq(snapshot.pendingTicks, 0)
end)

if failed > 0 then error(string.format("%d passed, %d failed", passed, failed)) end
print(string.format("%d passed, %d failed", passed, failed))
