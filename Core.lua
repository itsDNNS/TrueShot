-- TrueShot: AssistedCombat rotation overlay with cast-tracked state
-- Copyright (C) 2026 itsDNNS
-- Licensed under GPL-3.0-or-later. See LICENSE.

------------------------------------------------------------------------
-- Global namespace & saved variables
------------------------------------------------------------------------

TrueShot = TrueShot or {}

TrueShotDB = TrueShotDB or {}

local DEFAULTS = {
    iconCount = 2,
    iconSize = 40,
    iconSpacing = 4,
    locked = false,
    enableDiagnostics = false,
    showCooldownSwipe = true,
    showCastFeedback = true,
    showWhyOverlay = false,
    showPhaseIndicator = false,
    showOverrideIndicator = true,
    showKeybinds = true,
    showRangeIndicator = true,
    combatOnly = false,
    enemyTargetOnly = false,
    overlayScale = 1.0,
    overlayOpacity = 1.0,
    hidden = false,
    firstIconScale = 1.3,
    orientation = "LEFT",
    showBackdrop = true,
    showAoeHint = true,
    showLoginMessage = false,
    showScorecard = true,
    showHeartbeat = false,
}

local optionCallbacks = {}

function TrueShot.GetOpt(key)
    if TrueShotDB[key] ~= nil then return TrueShotDB[key] end
    return DEFAULTS[key]
end

function TrueShot.SetOpt(key, value)
    local prev = TrueShot.GetOpt(key)
    if prev == value then return end
    TrueShotDB[key] = value
    for _, callback in ipairs(optionCallbacks) do
        callback(key, value, prev)
    end
end

function TrueShot.RegisterOptCallback(callback)
    optionCallbacks[#optionCallbacks + 1] = callback
end

function TrueShot.DiagnosticsEnabled()
    return TrueShot.GetOpt("enableDiagnostics") and true or false
end

------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------

local Engine  -- resolved after all files load
local Display

local function GetActiveSpecID()
    local specIndex = GetSpecialization()
    if not specIndex then return nil end
    return GetSpecializationInfo(specIndex)
end

local function TryActivate()
    Engine = TrueShot.Engine
    Display = TrueShot.Display

    local specID = GetActiveSpecID()
    if not specID then
        Display:Disable()
        return false
    end

    if not Engine:ActivateProfile(specID) then
        Display:Disable()
        return false
    end

    if not C_AssistedCombat or not C_AssistedCombat.IsAvailable() then
        Display:Disable()
        return false
    end

    -- Visibility handled by ReconcileVisibility after activation
    return true
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
eventFrame:RegisterEvent("SPELLS_CHANGED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")

local function ShouldShowOverlay()
    if TrueShot.GetOpt("hidden") then return false end
    if not C_AssistedCombat or not C_AssistedCombat.IsAvailable() then return false end
    if TrueShot.GetOpt("enemyTargetOnly") then
        if UnitAffectingCombat("player") then return true end
        return UnitExists("target") and UnitCanAttack("player", "target")
    end
    if TrueShot.GetOpt("combatOnly") then
        return UnitAffectingCombat("player")
    end
    return true
end

local function ReconcileVisibility()
    if not TrueShot.Engine or not TrueShot.Engine.activeProfile then return end
    if not TrueShot.Display then return end
    if ShouldShowOverlay() then
        TrueShot.Display:Enable()
    else
        TrueShot.Display:Disable()
    end
end

TrueShot.ReconcileVisibility = ReconcileVisibility

eventFrame:SetScript("OnEvent", function(self, event, ...)
    Engine = TrueShot.Engine
    Display = TrueShot.Display

    if event == "PLAYER_ENTERING_WORLD" then
        if TryActivate() then
            if TrueShot.GetOpt("showLoginMessage") then
                local profile = Engine.activeProfile
                local name = profile and (profile.displayName or profile.id) or "unknown"
                print("|cff00ff00[TrueShot]|r Ready. |cffffff00" .. name .. "|r active. Type |cffffff00/ts help|r for commands.")
            end
        else
            if TrueShot.GetOpt("showLoginMessage") then
                local specID = GetActiveSpecID()
                if not TrueShot.Profiles[specID or 0] then
                    print("|cffaaaaaa[TrueShot]|r No profile for current spec. Addon inactive.")
                else
                    print("|cffff0000[TrueShot]|r Assisted Combat not available.")
                end
            end
        end
        ReconcileVisibility()

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit == "player" and spellID then
            Engine:OnSpellCast(spellID)
            if Display then
                if Display.OnSpellCastSucceeded then
                    Display:OnSpellCastSucceeded(spellID)
                end
                if Display.MarkDirty then Display:MarkDirty() end
            end
        end

    elseif event == "PLAYER_REGEN_DISABLED" then
        Engine.combatStartTime = GetTime()
        if TrueShot.CombatTrace then TrueShot.CombatTrace:Reset() end
        if Display and Display.ResetQueueStabilization then
            Display:ResetQueueStabilization()
        end
        if Display and Display.MarkDirty then Display:MarkDirty() end
        ReconcileVisibility()

    elseif event == "PLAYER_REGEN_ENABLED" then
        if TrueShot.Scorecard and Engine.combatStartTime then
            local combatDuration = GetTime() - Engine.combatStartTime
            TrueShot.Scorecard:OnCombatEnd(combatDuration)
        end
        Engine.combatStartTime = nil
        Engine:OnCombatEnd()
        if Display and Display.ResetQueueStabilization then
            Display:ResetQueueStabilization()
        end
        if Display and Display.MarkDirty then Display:MarkDirty() end
        ReconcileVisibility()

    elseif event == "PLAYER_TARGET_CHANGED" then
        if Display and Display.MarkDirty then Display:MarkDirty() end
        ReconcileVisibility()

    elseif event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "PLAYER_TALENT_UPDATE"
        or event == "SPELLS_CHANGED" then
        local prev = Engine.activeProfile
        TryActivate()
        local curr = Engine.activeProfile
        if curr and curr ~= prev and TrueShot.GetOpt("showLoginMessage") then
            local name = curr.displayName or curr.id or "unknown"
            print("|cff00ff00[TrueShot]|r Profile switched: " .. name)
        end
        ReconcileVisibility()
        -- Force immediate display refresh after any spell/talent change
        if Display and Display.container and Display.container:IsShown() then
            local queue = Engine:ComputeQueue(TrueShot.GetOpt("iconCount"))
            if Display.RenderQueueNow then
                Display:RenderQueueNow(queue)
            else
                Display:UpdateQueue(queue)
            end
        end
        -- Delayed re-check: spellbook may still be updating
        C_Timer.After(0.5, function()
            local prevDelayed = Engine.activeProfile
            TryActivate()
            local currDelayed = Engine.activeProfile
            if currDelayed and currDelayed ~= prevDelayed and TrueShot.GetOpt("showLoginMessage") then
                print("|cff00ff00[TrueShot]|r Profile switched: " .. (currDelayed.displayName or currDelayed.id or "unknown"))
            end
            ReconcileVisibility()
            if Display and Display.container and Display.container:IsShown() then
                local queue = Engine:ComputeQueue(TrueShot.GetOpt("iconCount"))
                if Display.RenderQueueNow then
                    Display:RenderQueueNow(queue)
                else
                    Display:UpdateQueue(queue)
                end
            end
        end)
    end
end)

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------

SLASH_TRUESHOT1 = "/ts"
SLASH_TRUESHOT2 = "/trueshot"
SlashCmdList["TRUESHOT"] = function(msg)
    Engine = TrueShot.Engine
    Display = TrueShot.Display
    msg = strtrim(msg:lower())

    if msg == "lock" then
        TrueShot.SetOpt("locked", true)
        Display:SetClickThrough(true)
        print("|cff00ff00[TS]|r Frame locked (click-through).")

    elseif msg == "unlock" then
        TrueShot.SetOpt("locked", false)
        Display:SetClickThrough(false)
        print("|cff00ff00[TS]|r Frame unlocked. Drag to reposition.")

    elseif msg == "burst" then
        Engine.burstModeActive = not Engine.burstModeActive
        if Display and Display.MarkDirty then Display:MarkDirty() end
        if Engine.burstModeActive then
            print("|cff00ff00[TS]|r Burst mode ON")
        else
            print("|cff00ff00[TS]|r Burst mode OFF")
        end

    elseif msg == "hide" then
        TrueShot.SetOpt("hidden", true)
        Display:Disable()
        print("|cff00ff00[TS]|r Hidden. /ts show to restore.")

    elseif msg == "show" then
        TrueShot.SetOpt("hidden", false)
        ReconcileVisibility()
        if not Display.container:IsShown() then
            print("|cff00ff00[TS]|r Overlay will show when conditions are met (target/combat).")
        end

    elseif msg == "options" or msg == "config" then
        if TrueShot.OpenSettingsPanel then
            TrueShot.OpenSettingsPanel()
        else
            print("|cffff0000[TS]|r Settings panel unavailable.")
        end

    elseif msg == "diagnostics on" or msg == "diag on" then
        TrueShot.SetOpt("enableDiagnostics", true)
        print("|cff00ff00[TS]|r Diagnostics enabled. `/ts probe ...` is now available.")

    elseif msg == "diagnostics off" or msg == "diag off" then
        TrueShot.SetOpt("enableDiagnostics", false)
        print("|cff00ff00[TS]|r Diagnostics disabled.")

    elseif msg == "diagnostics" or msg == "diag" then
        local state = TrueShot.DiagnosticsEnabled() and "ON" or "OFF"
        print("|cff00ff00[TS]|r Diagnostics: " .. state)
        print("  Use `/ts diagnostics on` or `/ts diagnostics off`.")

    elseif msg == "debug" then
        local queue = Engine:ComputeQueue(TrueShot.GetOpt("iconCount"))
        print("|cff00ff00[TS] Queue:|r")
        for i, id in ipairs(queue) do
            local name = C_Spell.GetSpellName(id) or "?"
            local castable = Engine:IsSpellCastable(id) and "usable" or "not usable"
            print("  " .. i .. ": " .. name .. " (" .. id .. ") [" .. castable .. "]")
        end
        local profile = Engine.activeProfile
        if profile and profile.GetDebugLines then
            print("|cff00ff00[TS] Profile State:|r")
            for _, line in ipairs(profile:GetDebugLines()) do
                print(line)
            end
        end
        print("  Burst mode: " .. tostring(Engine.burstModeActive))

    elseif msg:sub(1, 5) == "probe" then
        if not TrueShot.DiagnosticsEnabled() then
            print("|cffffff00[TS]|r Probe diagnostics are disabled. Enable them via `/ts diagnostics on` or in `/ts options`.")
            return
        end
        local probeArgs = msg:sub(7) or ""
        TrueShot.SignalProbe:HandleCommand(probeArgs)

    elseif msg == "score" or msg == "scores" then
        if TrueShot.Scorecard then
            TrueShot.Scorecard:PrintHistory(5)
        else
            print("|cff00ff00[TS]|r Scorecard not loaded.")
        end

    elseif msg == "help" then
        print("|cff00ff00[TrueShot]|r Commands:")
        print("  /ts lock    - Lock frame (click-through)")
        print("  /ts unlock  - Unlock frame for dragging")
        print("  /ts options - Open the TrueShot settings panel")
        print("  /ts burst   - Toggle burst mode")
        print("  /ts hide    - Hide the display")
        print("  /ts show    - Show the display")
        print("  /ts debug   - Print queue and profile state")
        print("  /ts score   - Show recent alignment scores")
        print("  /ts diagnostics on|off - Enable or disable probe diagnostics")
        print("  /ts probe   - Signal validation probes (only when diagnostics are enabled)")

    else
        print("|cff00ff00[TrueShot]|r Use /ts help for commands.")
    end
end
