-- HunterFlow: AssistedCombat rotation overlay with cast-tracked state
-- Copyright (C) 2026 itsDNNS
-- Licensed under GPL-3.0-or-later. See LICENSE.

------------------------------------------------------------------------
-- Global namespace & saved variables
------------------------------------------------------------------------

HunterFlow = HunterFlow or {}

HunterFlowDB = HunterFlowDB or {}

local DEFAULTS = {
    iconCount = 2,
    iconSize = 40,
    iconSpacing = 4,
    locked = false,
    enableDiagnostics = false,
    showCooldownSwipe = true,
    showCastFeedback = true,
    showWhyOverlay = false,
}

local optionCallbacks = {}

function HunterFlow.GetOpt(key)
    if HunterFlowDB[key] ~= nil then return HunterFlowDB[key] end
    return DEFAULTS[key]
end

function HunterFlow.SetOpt(key, value)
    local prev = HunterFlow.GetOpt(key)
    if prev == value then return end
    HunterFlowDB[key] = value
    for _, callback in ipairs(optionCallbacks) do
        callback(key, value, prev)
    end
end

function HunterFlow.RegisterOptCallback(callback)
    optionCallbacks[#optionCallbacks + 1] = callback
end

function HunterFlow.DiagnosticsEnabled()
    return HunterFlow.GetOpt("enableDiagnostics") and true or false
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
    Engine = HunterFlow.Engine
    Display = HunterFlow.Display

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

    Display:Enable()
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
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    Engine = HunterFlow.Engine
    Display = HunterFlow.Display

    if event == "PLAYER_ENTERING_WORLD" then
        if TryActivate() then
            local profile = Engine.activeProfile
            local name = profile and profile.id or "unknown"
            print("|cff00ff00[HunterFlow]|r loaded. Profile: " .. name)
            print("|cffaaaaaa  /hf lock|unlock|options|burst|help|r")
        else
            local specID = GetActiveSpecID()
            if not HunterFlow.Profiles[specID or 0] then
                print("|cffaaaaaa[HunterFlow]|r No profile for current spec. Addon inactive.")
            else
                print("|cffff0000[HunterFlow]|r Assisted Combat not available.")
            end
        end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit == "player" and spellID then
            Engine:OnSpellCast(spellID)
            if Display and Display.OnSpellCastSucceeded then
                Display:OnSpellCastSucceeded(spellID)
            end
        end

    elseif event == "PLAYER_REGEN_DISABLED" then
        Engine.combatStartTime = GetTime()
        if Engine.activeProfile and not Display.container:IsShown() then
            Display:Enable()
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        Engine.combatStartTime = nil
        Engine:OnCombatEnd()

    elseif event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "PLAYER_TALENT_UPDATE"
        or event == "SPELLS_CHANGED" then
        local prev = Engine.activeProfile
        TryActivate()
        local curr = Engine.activeProfile
        if curr and curr ~= prev then
            local name = curr.id or "unknown"
            print("|cff00ff00[HunterFlow]|r Profile switched: " .. name)
        end
    end
end)

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------

SLASH_HUNTERFLOW1 = "/hf"
SLASH_HUNTERFLOW2 = "/hunterflow"
SlashCmdList["HUNTERFLOW"] = function(msg)
    Engine = HunterFlow.Engine
    Display = HunterFlow.Display
    msg = msg:lower():trim()

    if msg == "lock" then
        HunterFlow.SetOpt("locked", true)
        Display:SetClickThrough(true)
        print("|cff00ff00[HF]|r Frame locked (click-through).")

    elseif msg == "unlock" then
        HunterFlow.SetOpt("locked", false)
        Display:SetClickThrough(false)
        print("|cff00ff00[HF]|r Frame unlocked. Drag to reposition.")

    elseif msg == "burst" then
        Engine.burstModeActive = not Engine.burstModeActive
        if Engine.burstModeActive then
            print("|cff00ff00[HF]|r Burst mode ON")
        else
            print("|cff00ff00[HF]|r Burst mode OFF")
        end

    elseif msg == "hide" then
        Display:Disable()
        print("|cff00ff00[HF]|r Hidden. /hf show to restore.")

    elseif msg == "show" then
        Display:Enable()

    elseif msg == "options" or msg == "config" then
        if HunterFlow.OpenSettingsPanel then
            HunterFlow.OpenSettingsPanel()
        else
            print("|cffff0000[HF]|r Settings panel unavailable.")
        end

    elseif msg == "diagnostics on" or msg == "diag on" then
        HunterFlow.SetOpt("enableDiagnostics", true)
        print("|cff00ff00[HF]|r Diagnostics enabled. `/hf probe ...` is now available.")

    elseif msg == "diagnostics off" or msg == "diag off" then
        HunterFlow.SetOpt("enableDiagnostics", false)
        print("|cff00ff00[HF]|r Diagnostics disabled.")

    elseif msg == "diagnostics" or msg == "diag" then
        local state = HunterFlow.DiagnosticsEnabled() and "ON" or "OFF"
        print("|cff00ff00[HF]|r Diagnostics: " .. state)
        print("  Use `/hf diagnostics on` or `/hf diagnostics off`.")

    elseif msg == "debug" then
        local queue = Engine:ComputeQueue(HunterFlow.GetOpt("iconCount"))
        print("|cff00ff00[HF] Queue:|r")
        for i, id in ipairs(queue) do
            local name = C_Spell.GetSpellName(id) or "?"
            local castable = Engine:IsSpellCastable(id) and "usable" or "not usable"
            print("  " .. i .. ": " .. name .. " (" .. id .. ") [" .. castable .. "]")
        end
        local profile = Engine.activeProfile
        if profile and profile.GetDebugLines then
            print("|cff00ff00[HF] Profile State:|r")
            for _, line in ipairs(profile:GetDebugLines()) do
                print(line)
            end
        end
        print("  Burst mode: " .. tostring(Engine.burstModeActive))

    elseif msg:sub(1, 5) == "probe" then
        if not HunterFlow.DiagnosticsEnabled() then
            print("|cffffff00[HF]|r Probe diagnostics are disabled. Enable them via `/hf diagnostics on` or in `/hf options`.")
            return
        end
        local probeArgs = msg:sub(7) or ""
        HunterFlow.SignalProbe:HandleCommand(probeArgs)

    elseif msg == "help" then
        print("|cff00ff00[HunterFlow]|r Commands:")
        print("  /hf lock    - Lock frame (click-through)")
        print("  /hf unlock  - Unlock frame for dragging")
        print("  /hf options - Open the HunterFlow settings panel")
        print("  /hf burst   - Toggle burst mode")
        print("  /hf hide    - Hide the display")
        print("  /hf show    - Show the display")
        print("  /hf debug   - Print queue and profile state")
        print("  /hf diagnostics on|off - Enable or disable probe diagnostics")
        print("  /hf probe   - Signal validation probes (only when diagnostics are enabled)")

    else
        print("|cff00ff00[HunterFlow]|r Use /hf help for commands.")
    end
end
