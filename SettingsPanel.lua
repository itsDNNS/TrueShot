-- TrueShot Settings: native Game Options category for lightweight addon config

TrueShot = TrueShot or {}

local settingsCategory

local function OpenRegisteredCategory()
    if not settingsCategory or not Settings or not Settings.OpenToCategory then return end
    if settingsCategory.GetID then
        Settings.OpenToCategory(settingsCategory:GetID())
    elseif settingsCategory.ID then
        Settings.OpenToCategory(settingsCategory.ID)
    else
        Settings.OpenToCategory("TrueShot")
    end
end

local function CreateCheckbox(parent, label, description, relativeTo, key)
    local check = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    check:SetPoint("TOPLEFT", relativeTo, "BOTTOMLEFT", 0, -14)
    check.Text:SetText(label)

    local desc = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 0, -2)
    desc:SetPoint("RIGHT", parent, "RIGHT", -24, 0)
    desc:SetJustifyH("LEFT")
    desc:SetText("   " .. description)

    check:SetScript("OnClick", function(self)
        TrueShot.SetOpt(key, self:GetChecked() and true or false)
        if key == "locked" and TrueShot.Display and TrueShot.Display.SetClickThrough then
            TrueShot.Display:SetClickThrough(self:GetChecked())
        end
    end)

    check.sync = function()
        check:SetChecked(TrueShot.GetOpt(key))
    end

    return check, desc
end

local function CreateSlider(parent, label, description, relativeTo, key, minVal, maxVal, step)
    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", relativeTo, "BOTTOMLEFT", 0, -14)
    container:SetSize(200, 40)

    local text = container:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)

    local slider = CreateFrame("Slider", nil, container, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -4)
    slider:SetSize(180, 16)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    if slider.Low then slider.Low:SetText(tostring(minVal)) end
    if slider.High then slider.High:SetText(tostring(maxVal)) end

    local desc = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -6)
    desc:SetPoint("RIGHT", parent, "RIGHT", -24, 0)
    desc:SetJustifyH("LEFT")
    desc:SetText(description)

    local function UpdateLabel(val)
        text:SetText(label .. ": " .. string.format("%.0f%%", val * 100))
    end

    slider:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val / step + 0.5) * step
        TrueShot.SetOpt(key, val)
        UpdateLabel(val)
    end)

    slider.sync = function()
        local val = TrueShot.GetOpt(key) or 1.0
        slider:SetValue(val)
        UpdateLabel(val)
    end

    return slider, desc
end

local function CreateSettingsPanel()
    local panel = CreateFrame("Frame", "TrueShotSettingsPanel", UIParent)
    panel.name = "TrueShot"
    panel:SetSize(640, 800)

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    title:SetText("TrueShot")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Midnight-compatible rotation overlay on top of Blizzard Assisted Combat.")

    -- Display
    local lockCheck, lockDesc = CreateCheckbox(
        panel,
        "Lock overlay frame",
        "Disable dragging and make the overlay click-through.",
        subtitle, "locked"
    )

    local enemyCheck, enemyDesc = CreateCheckbox(
        panel,
        "Show only on enemy target",
        "Show the overlay only when you have a hostile target selected. Implies combat-only behavior.",
        lockDesc, "enemyTargetOnly"
    )

    local combatCheck, combatDesc = CreateCheckbox(
        panel,
        "Show only in combat",
        "Hide the overlay outside of combat. Ignored when 'Show only on enemy target' is active.",
        enemyDesc, "combatOnly"
    )

    local scaleSlider, scaleDesc = CreateSlider(
        panel, "Overlay scale", "Size of the overlay icons.",
        combatDesc, "overlayScale", 0.5, 2.0, 0.1
    )

    local opacitySlider, opacityDesc = CreateSlider(
        panel, "Overlay opacity", "Transparency of the overlay.",
        scaleDesc, "overlayOpacity", 0.3, 1.0, 0.1
    )

    -- Features
    local castCheck, castDesc = CreateCheckbox(
        panel,
        "Show cast success feedback",
        "Flash the icon briefly when your cast matches the recommendation.",
        opacityDesc, "showCastFeedback"
    )

    local cooldownCheck, cooldownDesc = CreateCheckbox(
        panel,
        "Show cooldown swipes (best-effort)",
        "Display cooldown sweep when readable. Not a promise of exact Midnight cooldown truth.",
        castDesc, "showCooldownSwipe"
    )

    local keybindCheck, keybindDesc = CreateCheckbox(
        panel,
        "Show keybindings",
        "Display the keybinding text on each icon.",
        cooldownDesc, "showKeybinds"
    )

    local rangeCheck, rangeDesc = CreateCheckbox(
        panel,
        "Show range indicator",
        "Tint the primary icon red when your target is out of range.",
        keybindDesc, "showRangeIndicator"
    )

    local whyCheck, whyDesc = CreateCheckbox(
        panel,
        "Show recommendation reason",
        "Display a label below the primary icon explaining why it was recommended (e.g. Withering Fire, Charge Dump).",
        rangeDesc, "showWhyOverlay"
    )

    -- Utility
    local unlockButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    unlockButton:SetSize(160, 24)
    unlockButton:SetPoint("TOPLEFT", whyDesc, "BOTTOMLEFT", 0, -18)
    unlockButton:SetText("Unlock And Recenter")
    unlockButton:SetScript("OnClick", function()
        TrueShot.SetOpt("locked", false)
        if TrueShot.Display and TrueShot.Display.ResetPosition then
            TrueShot.Display:ResetPosition()
            TrueShot.Display:SetClickThrough(false)
        end
        lockCheck:SetChecked(false)
    end)

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", unlockButton, "BOTTOMLEFT", 0, -10)
    hint:SetPoint("RIGHT", panel, "RIGHT", -24, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("For diagnostics and debugging, use /ts debug and /ts probe commands.")

    panel:SetScript("OnShow", function()
        lockCheck.sync()
        enemyCheck.sync()
        combatCheck.sync()
        scaleSlider.sync()
        opacitySlider.sync()
        castCheck.sync()
        cooldownCheck.sync()
        keybindCheck.sync()
        rangeCheck.sync()
        whyCheck.sync()
    end)

    return panel
end

local function RegisterSettingsPanel()
    if settingsCategory or not Settings or not Settings.RegisterCanvasLayoutCategory or not Settings.RegisterAddOnCategory then
        return
    end

    local panel = CreateSettingsPanel()
    settingsCategory = Settings.RegisterCanvasLayoutCategory(panel, "TrueShot")
    Settings.RegisterAddOnCategory(settingsCategory)
end

function TrueShot.OpenSettingsPanel()
    RegisterSettingsPanel()
    OpenRegisteredCategory()
end

RegisterSettingsPanel()

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    RegisterSettingsPanel()
end)
