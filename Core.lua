-- TrueShot: AssistedCombat rotation overlay with cast-tracked state
-- Copyright (C) 2026 itsDNNS
-- Licensed under GPL-3.0-or-later. See LICENSE.

------------------------------------------------------------------------
-- Global namespace & saved variables
------------------------------------------------------------------------

TrueShot = TrueShot or {}

TrueShotDB = TrueShotDB or {}

local DEFAULTS = {
    iconCount = 1,
    iconSize = 40,
    iconSpacing = 4,
    locked = false,
    enableDiagnostics = false,
    showCooldownSwipe = true,
    showCooldownText = false,
    showCastFeedback = true,
    showWhyOverlay = false,
    showPhaseIndicator = false,
    showOverrideIndicator = true,
    showKeybinds = true,
    showRangeIndicator = true,
    showIdleState = true,
    combatOnly = false,
    enemyTargetOnly = false,
    overlayScale = 1.0,
    overlayOpacity = 1.0,
    hidden = false,
    firstIconScale = 1.3,
    orientation = "LEFT",
    showBackdrop = true,
    showAoeHint = true,
    reasonPosition = "BELOW",   -- BELOW or ABOVE
    aoeHintPosition = "BELOW",  -- BELOW or LEFT
    showLoginMessage = false,
    showScorecard = true,
    showHeartbeat = false,
    strictCompliance = true,
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

TrueShot.RegisterOptCallback(function(key, value)
    if key == "enableDiagnostics" and value ~= true
        and TrueShot.Engine and TrueShot.Engine.ClearDecisionHistory then
        TrueShot.Engine:ClearDecisionHistory()
    end
end)

local function AssistedCombatAvailable()
    if not C_AssistedCombat or not C_AssistedCombat.IsAvailable then return false end
    local ok, available = pcall(C_AssistedCombat.IsAvailable)
    if not ok or (issecretvalue and issecretvalue(available)) then return false end
    return available == true
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

    if not AssistedCombatAvailable() then
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
eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")

local function ShouldShowOverlay()
    if TrueShot.GetOpt("hidden") then return false end
    if not AssistedCombatAvailable() then return false end
    if TrueShot.GetOpt("enemyTargetOnly") then
        if UnitExists("target") and UnitCanAttack("player", "target") then return true end
        return UnitAffectingCombat("player")
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
        if TrueShot.CDLedger and TrueShot.CDLedger.ReseedFromCooldownAPI then
            TrueShot.CDLedger:ReseedFromCooldownAPI()
        end
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
            -- CDLedger runs alongside the profile dispatch so timer state is
            -- updated before any condition (including the one that just fired
            -- this cast through MarkDirty) re-evaluates.
            if TrueShot.CDLedger and TrueShot.CDLedger.OnSpellCastSucceeded then
                TrueShot.CDLedger:OnSpellCastSucceeded(spellID)
            end
            Engine:OnSpellCast(spellID)
            if Display then
                if Display.OnSpellCastSucceeded then
                    Display:OnSpellCastSucceeded(spellID)
                end
                if Display.MarkDirty then Display:MarkDirty() end
            end
        end

    elseif event == "SPELL_UPDATE_COOLDOWN" then
        -- Best-effort reconcile: prunes ledger entries whose cooldowns are
        -- demonstrably finished per a non-secret C_Spell read. Cast-event
        -- entries with secret/unreadable responses are left intact so the
        -- tier-3 visual swipe fallback keeps animating.
        if TrueShot.CDLedger and TrueShot.CDLedger.ReconcileFromCooldownAPI then
            TrueShot.CDLedger:ReconcileFromCooldownAPI()
        end
        if Display and Display.MarkDirty then Display:MarkDirty() end

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

local function SafeDebugText(value, fallback)
    if issecretvalue and issecretvalue(value) then return "<secret>" end
    if value == nil then return fallback or "none" end
    local valueType = type(value)
    if valueType == "string" or valueType == "number" or valueType == "boolean" then
        return tostring(value)
    end
    return fallback or "unavailable"
end

local function SafeDebugSpell(spellID)
    if issecretvalue and issecretvalue(spellID) then return "<secret>" end
    if spellID == nil or type(spellID) ~= "number" then return "none" end
    local name = nil
    if C_Spell and C_Spell.GetSpellName then
        local ok, result = pcall(C_Spell.GetSpellName, spellID)
        if ok and not (issecretvalue and issecretvalue(result)) and type(result) == "string" then
            name = result
        end
    end
    return (name or "Spell") .. " (" .. tostring(spellID) .. ")"
end

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

    elseif msg == "strict on" then
        TrueShot.SetOpt("strictCompliance", true)
        if Display and Display.MarkDirty then Display:MarkDirty() end
        print("|cff00ff00[TS]|r Strict compliance mode ON. Experimental overrides disabled.")

    elseif msg == "strict off" or msg == "experimental on" then
        TrueShot.SetOpt("strictCompliance", false)
        if Display and Display.MarkDirty then Display:MarkDirty() end
        print("|cffffff00[TS]|r Experimental override mode ON. Use only for validation.")

    elseif msg == "strict" or msg == "experimental" then
        local strict = TrueShot.GetOpt("strictCompliance") ~= false
        print("|cff00ff00[TS]|r Strict compliance mode: " .. (strict and "ON" or "OFF"))
        print("  /ts strict on  - Disable experimental overrides")
        print("  /ts strict off - Enable experimental overrides for validation")

    elseif msg == "debug" then
        local queue = Engine:ComputeQueue(TrueShot.GetOpt("iconCount"))
        print("|cff00ff00[TS] Queue:|r")
        for i, id in ipairs(queue) do
            local castable = Engine:IsSpellCastable(id) and "usable" or "not usable"
            print("  " .. i .. ": " .. SafeDebugSpell(id) .. " [" .. castable .. "]")
        end
        local meta = Engine.lastQueueMeta or {}
        print("|cff00ff00[TS] Decision:|r")
        print("  Raw AC: " .. SafeDebugSpell(meta.rawACSpell)
            .. " [" .. SafeDebugText(meta.rawACStatus, "unavailable") .. "]")
        print("  Final primary: " .. SafeDebugSpell(meta.finalPrimarySpell))
        print("  Source/reason: " .. SafeDebugText(meta.source)
            .. " / " .. SafeDebugText(meta.reasonCode))
        print("  Detail: reason=" .. SafeDebugText(meta.reason)
            .. ", fallback/drop=" .. SafeDebugText(meta.fallbackDropReason))
        local catalog = meta.rotationCatalogSnapshot
        local catalogCount = 0
        if not (issecretvalue and issecretvalue(catalog)) and type(catalog) == "table" then
            catalogCount = #catalog
        end
        print("  Strict: " .. SafeDebugText(meta.strictState)
            .. ", rotation catalog context: " .. tostring(catalogCount))
        if Display and Display.GetStabilizationSnapshot then
            local stabilization = Display:GetStabilizationSnapshot()
            if not (issecretvalue and issecretvalue(stabilization)) and type(stabilization) == "table" then
                print("  Display: shown=" .. SafeDebugSpell(stabilization.displayedPrimary)
                    .. ", pending=" .. SafeDebugSpell(stabilization.pendingPrimary)
                    .. ", ticks=" .. SafeDebugText(stabilization.pendingTicks, "0")
                    .. ", age=" .. SafeDebugText(stabilization.pendingAge, "0")
                    .. ", deadlineForced=" .. SafeDebugText(stabilization.staleDeadlineForcedLastCommit, "false"))
            end
        end
        local recentCount = Engine.GetDecisionHistoryCount and Engine:GetDecisionHistoryCount() or 0
        print("  Diagnostic decision changes retained: " .. tostring(recentCount))
        local profile = Engine.activeProfile
        if profile and profile.GetDebugLines then
            print("|cff00ff00[TS] Profile State:|r")
            for _, line in ipairs(profile:GetDebugLines()) do
                print(line)
            end
        end
        print("  Burst mode: " .. tostring(Engine.burstModeActive))

    elseif msg == "smoke" then
        if TrueShot.SmokeTest and TrueShot.SmokeTest.Run then
            TrueShot.SmokeTest:Run()
        else
            print("|cffff0000[TS]|r SmokeTest not loaded.")
        end

    elseif msg == "combat-smoke" or msg == "combat smoke" then
        if TrueShot.SmokeTest and TrueShot.SmokeTest.Run then
            TrueShot.SmokeTest:Run({ mode = "combat", requireCombat = true })
        else
            print("|cffff0000[TS]|r SmokeTest not loaded.")
        end

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

    elseif msg == "export" then
        if TrueShot.ProfileIO and TrueShot.ProfileIO.ShowExport then
            TrueShot.ProfileIO:ShowExport()
        else
            print("|cffff0000[TS]|r ProfileIO not loaded.")
        end

    elseif msg == "import" then
        if TrueShot.ProfileIO and TrueShot.ProfileIO.ShowImport then
            TrueShot.ProfileIO:ShowImport()
        else
            print("|cffff0000[TS]|r ProfileIO not loaded.")
        end

    elseif msg == "rules" then
        if TrueShot.RuleBuilder and TrueShot.RuleBuilder.Toggle then
            TrueShot.RuleBuilder:Toggle()
        else
            print("|cffff0000[TS]|r Rule Builder not loaded.")
        end

    elseif msg == "profiles" then
        if TrueShot.RuleBuilder and TrueShot.RuleBuilder.Toggle then
            TrueShot.RuleBuilder:Toggle()
        else
            print("|cffff0000[TS]|r Rule Builder not loaded.")
        end

    elseif msg == "browse" then
        if TrueShot.ProfileIO and TrueShot.ProfileIO.ToggleBrowser then
            TrueShot.ProfileIO:ToggleBrowser()
        else
            print("|cffff0000[TS]|r ProfileIO not loaded.")
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
        print("  /ts smoke   - Run in-client strict compliance smoke test")
        print("  /ts combat-smoke - Run strict compliance smoke test requiring combat")
        print("  /ts score   - Show recent alignment scores")
        print("  /ts rules   - Open the Visual Rule Builder")
        print("  /ts profiles - Open the Visual Rule Builder (alias for /ts rules)")
        print("  /ts browse  - Browse all profiles (Class > Spec > Hero Talent)")
        print("  /ts export  - Export custom profile as shareable string")
        print("  /ts import  - Import a profile from a shared string")
        print("  /ts diagnostics on|off - Enable or disable probe diagnostics")
        print("  /ts strict on|off - Toggle strict compliance / experimental override mode")
        print("  /ts probe   - Signal validation probes (only when diagnostics are enabled)")

    else
        print("|cff00ff00[TrueShot]|r Use /ts help for commands.")
    end
end
