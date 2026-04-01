-- HunterFlow Settings: native Game Options category for lightweight addon config

HunterFlow = HunterFlow or {}

local settingsCategory

local function OpenRegisteredCategory()
    if not settingsCategory or not Settings or not Settings.OpenToCategory then return end
    if settingsCategory.GetID then
        Settings.OpenToCategory(settingsCategory:GetID())
    elseif settingsCategory.ID then
        Settings.OpenToCategory(settingsCategory.ID)
    else
        Settings.OpenToCategory("HunterFlow")
    end
end

local function CreateCheckbox(parent, label, description, relativeTo, x, y, key)
    local check = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    check:SetPoint("TOPLEFT", relativeTo, "BOTTOMLEFT", x, y)
    check.Text:SetText(label)

    local desc = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", check.Text, "BOTTOMLEFT", 0, -2)
    desc:SetPoint("RIGHT", parent, "RIGHT", -24, 0)
    desc:SetJustifyH("LEFT")
    desc:SetText(description)

    check:SetScript("OnClick", function(self)
        HunterFlow.SetOpt(key, self:GetChecked() and true or false)
        if key == "locked" and HunterFlow.Display and HunterFlow.Display.SetClickThrough then
            HunterFlow.Display:SetClickThrough(self:GetChecked())
        end
    end)

    check.sync = function()
        check:SetChecked(HunterFlow.GetOpt(key))
    end

    return check, desc
end

local function CreateSettingsPanel()
    local panel = CreateFrame("Frame", "HunterFlowSettingsPanel", UIParent)
    panel.name = "HunterFlow"
    panel:SetSize(640, 480)

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    title:SetText("HunterFlow")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Midnight-compatible hunter overlay on top of Blizzard Assisted Combat. Keep the panel lean: settings here should stay practical and low-overhead.")

    local lockCheck, lockDesc = CreateCheckbox(
        panel,
        "Lock overlay frame",
        "Disable dragging and make the overlay click-through during combat.",
        subtitle, 0, -18, "locked"
    )

    local castCheck, castDesc = CreateCheckbox(
        panel,
        "Show cast success feedback",
        "Flash the recommended icon briefly when your successful cast matches the displayed recommendation.",
        lockDesc, 0, -18, "showCastFeedback"
    )

    local cooldownCheck = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    cooldownCheck:SetPoint("TOPLEFT", castDesc, "BOTTOMLEFT", 0, -18)
    cooldownCheck.Text:SetText("Show cooldown swipes (best-effort)")

    local cooldownDesc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    cooldownDesc:SetPoint("TOPLEFT", cooldownCheck.Text, "BOTTOMLEFT", 0, -2)
    cooldownDesc:SetPoint("RIGHT", panel, "RIGHT", -24, 0)
    cooldownDesc:SetJustifyH("LEFT")
    cooldownDesc:SetText("Use readable spell cooldown data when available and suppress obvious GCD-only churn. This is visual feedback, not a promise of exact Midnight cooldown truth.")

    cooldownCheck:SetScript("OnClick", function(self)
        HunterFlow.SetOpt("showCooldownSwipe", self:GetChecked() and true or false)
    end)

    local whyCheck, whyDesc = CreateCheckbox(
        panel,
        "Show recommendation reason",
        "Display a short label below the primary icon explaining why it was recommended (e.g. Withering Fire, Charge Dump, AoE). Hidden when Assisted Combat passthrough is active.",
        cooldownDesc, 0, -18, "showWhyOverlay"
    )

    local phaseCheck, phaseDesc = CreateCheckbox(
        panel,
        "Show rotation phase",
        "Display the current rotation phase above the overlay (Burst, AoE, Charge Dump). Hidden during normal single-target rotation.",
        whyDesc, 0, -18, "showPhaseIndicator"
    )

    local overrideCheck, overrideDesc = CreateCheckbox(
        panel,
        "Show AC override indicator",
        "Tint the primary icon border blue when HunterFlow is overriding Assisted Combat. Normal border when AC passthrough is active.",
        phaseDesc, 0, -18, "showOverrideIndicator"
    )

    local diagnosticsCheck, diagnosticsDesc = CreateCheckbox(
        panel,
        "Enable probe diagnostics",
        "Keep the heavier signal probe commands off by default. Turn this on only when you explicitly want `/hf probe ...` for API validation or debugging.",
        overrideDesc, 0, -18, "enableDiagnostics"
    )

    local unlockButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    unlockButton:SetSize(160, 24)
    unlockButton:SetPoint("TOPLEFT", diagnosticsDesc, "BOTTOMLEFT", 0, -18)
    unlockButton:SetText("Unlock And Recenter")
    unlockButton:SetScript("OnClick", function()
        HunterFlow.SetOpt("locked", false)
        if HunterFlow.Display and HunterFlow.Display.ResetPosition then
            HunterFlow.Display:ResetPosition()
            HunterFlow.Display:SetClickThrough(false)
        end
        lockCheck:SetChecked(false)
    end)

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", unlockButton, "BOTTOMLEFT", 0, -10)
    hint:SetPoint("RIGHT", panel, "RIGHT", -24, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("For profile logic, keep using `/hf debug`. Probe commands stay behind the diagnostics toggle above, or `/hf diagnostics on`, so they only run when you explicitly need them.")

    panel:SetScript("OnShow", function()
        lockCheck.sync()
        castCheck.sync()
        cooldownCheck:SetChecked(HunterFlow.GetOpt("showCooldownSwipe"))
        whyCheck.sync()
        phaseCheck.sync()
        overrideCheck.sync()
        diagnosticsCheck.sync()
    end)

    return panel
end

local function RegisterSettingsPanel()
    if settingsCategory or not Settings or not Settings.RegisterCanvasLayoutCategory or not Settings.RegisterAddOnCategory then
        return
    end

    local panel = CreateSettingsPanel()
    settingsCategory = Settings.RegisterCanvasLayoutCategory(panel, "HunterFlow")
    Settings.RegisterAddOnCategory(settingsCategory)
end

function HunterFlow.OpenSettingsPanel()
    RegisterSettingsPanel()
    OpenRegisteredCategory()
end

RegisterSettingsPanel()

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    RegisterSettingsPanel()
end)
