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

local function CreateCoordinateEditBox(parent, anchorTo, xOffset)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(84, 20)
    box:SetAutoFocus(false)
    box:SetPoint("LEFT", anchorTo, "RIGHT", xOffset, 0)
    box:SetTextInsets(4, 4, 0, 0)
    return box
end

local function CreateSettingsPanel()
    local panel = CreateFrame("Frame", "TrueShotSettingsPanel", UIParent)
    panel.name = "TrueShot"
    panel:SetSize(640, 800)

    -- ScrollFrame wrapping all content
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 0)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(600, 1)
    scrollFrame:SetScrollChild(scrollChild)

    -- Track scroll child width to match scroll frame after layout
    scrollFrame:SetScript("OnSizeChanged", function(self, w)
        scrollChild:SetWidth(w)
    end)

    -- All controls parent to scrollChild instead of panel
    local content = scrollChild

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -16)
    title:SetText("TrueShot")

    local subtitle = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetPoint("RIGHT", content, "RIGHT", -16, 0)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Midnight-compatible rotation overlay on top of Blizzard Assisted Combat.")

    -- Display
    local lockCheck, lockDesc = CreateCheckbox(
        content,
        "Lock overlay frame",
        "Disable dragging and make the overlay click-through.",
        subtitle, "locked"
    )

    local enemyCheck, enemyDesc = CreateCheckbox(
        content,
        "Show only on enemy target",
        "Show the overlay only when you have a hostile target selected. Implies combat-only behavior.",
        lockDesc, "enemyTargetOnly"
    )

    local combatCheck, combatDesc = CreateCheckbox(
        content,
        "Show only in combat",
        "Hide the overlay outside of combat. Ignored when 'Show only on enemy target' is active.",
        enemyDesc, "combatOnly"
    )

    local scaleSlider, scaleDesc = CreateSlider(
        content, "Overlay scale", "Size of the overlay icons.",
        combatDesc, "overlayScale", 0.5, 2.0, 0.1
    )

    local opacitySlider, opacityDesc = CreateSlider(
        content, "Overlay opacity", "Transparency of the overlay.",
        scaleDesc, "overlayOpacity", 0.3, 1.0, 0.1
    )

    -- Features
    local castCheck, castDesc = CreateCheckbox(
        content,
        "Show cast success feedback",
        "Flash the icon briefly when your cast matches the recommendation.",
        opacityDesc, "showCastFeedback"
    )

    local cooldownCheck, cooldownDesc = CreateCheckbox(
        content,
        "Show cooldown swipes (best-effort)",
        "Display cooldown sweep when readable. Not a promise of exact Midnight cooldown truth.",
        castDesc, "showCooldownSwipe"
    )

    local keybindCheck, keybindDesc = CreateCheckbox(
        content,
        "Show keybindings",
        "Display the keybinding text on each icon.",
        cooldownDesc, "showKeybinds"
    )

    local rangeCheck, rangeDesc = CreateCheckbox(
        content,
        "Show range indicator",
        "Tint the primary icon red when your target is out of range.",
        keybindDesc, "showRangeIndicator"
    )

    local whyCheck, whyDesc = CreateCheckbox(
        content,
        "Show recommendation reason",
        "Display a label below the primary icon explaining why it was recommended (e.g. Withering Fire, Charge Dump).",
        rangeDesc, "showWhyOverlay"
    )

    local backdropCheck, backdropDesc = CreateCheckbox(
        content,
        "Show Backdrop",
        "Show the dark background behind the queue overlay.",
        whyDesc, "showBackdrop"
    )

    local coordInputsLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    coordInputsLabel:SetPoint("TOPLEFT", backdropDesc, "BOTTOMLEFT", 0, -10)
    coordInputsLabel:SetText("Position offsets (UIParent)")

    local coordInputsRow = CreateFrame("Frame", nil, content)
    coordInputsRow:SetSize(420, 22)
    coordInputsRow:SetPoint("TOPLEFT", coordInputsLabel, "BOTTOMLEFT", 0, -6)

    local xLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    xLabel:SetPoint("LEFT", coordInputsRow, "LEFT", 0, 0)
    xLabel:SetText("X")

    local xEdit = CreateCoordinateEditBox(content, xLabel, 6)

    local yLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    yLabel:SetPoint("LEFT", xEdit, "RIGHT", 14, 0)
    yLabel:SetText("Y")

    local yEdit = CreateCoordinateEditBox(content, yLabel, 6)

    local applyCoordsButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    applyCoordsButton:SetSize(92, 20)
    applyCoordsButton:SetPoint("LEFT", yEdit, "RIGHT", 14, 0)
    applyCoordsButton:SetText("Apply")

    local function SyncPositionEditBoxes()
        if xEdit:HasFocus() or yEdit:HasFocus() then
            return
        end

        local display = TrueShot.Display
        if not display or not display.GetPositionOffsets then
            xEdit:SetText("")
            yEdit:SetText("")
            return
        end

        local point, _relativeName, _relativePoint, xOfs, yOfs = display:GetPositionOffsets()
        if not point then
            xEdit:SetText("")
            yEdit:SetText("")
            return
        end

        xEdit:SetText(string.format("%.2f", xOfs or 0))
        yEdit:SetText(string.format("%.2f", yOfs or 0))
    end

    local function ApplyPositionFromInputs()
        local xVal = tonumber(xEdit:GetText() or "")
        local yVal = tonumber(yEdit:GetText() or "")
        if not xVal or not yVal then
            return
        end

        local display = TrueShot.Display
        if display and display.SetPositionOffsets and display:SetPositionOffsets(xVal, yVal) then
            SyncPositionEditBoxes()
        end
    end

    xEdit:SetScript("OnEnterPressed", function(self)
        ApplyPositionFromInputs()
        self:ClearFocus()
    end)
    yEdit:SetScript("OnEnterPressed", function(self)
        ApplyPositionFromInputs()
        self:ClearFocus()
    end)
    xEdit:SetScript("OnEditFocusLost", ApplyPositionFromInputs)
    yEdit:SetScript("OnEditFocusLost", ApplyPositionFromInputs)
    applyCoordsButton:SetScript("OnClick", ApplyPositionFromInputs)

    -- Orientation
    local orientLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    orientLabel:SetPoint("TOPLEFT", coordInputsRow, "BOTTOMLEFT", 0, -16)
    orientLabel:SetText("Queue Orientation")

    local orientDropdown = CreateFrame("Frame", "TrueShotOrientDropdown", content,
        "UIDropDownMenuTemplate")
    orientDropdown:SetPoint("TOPLEFT", orientLabel, "BOTTOMLEFT", -16, -4)
    UIDropDownMenu_SetWidth(orientDropdown, 120)

    local orientOptions = { "LEFT", "RIGHT", "UP", "DOWN" }
    UIDropDownMenu_Initialize(orientDropdown, function(self, level)
        for _, opt in ipairs(orientOptions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt
            info.checked = (TrueShot.GetOpt("orientation") == opt)
            info.func = function()
                TrueShot.SetOpt("orientation", opt)
                UIDropDownMenu_SetText(orientDropdown, opt)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(orientDropdown, TrueShot.GetOpt("orientation"))

    -- First Icon Scale
    local fisLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fisLabel:SetPoint("TOPLEFT", orientDropdown, "BOTTOMLEFT", 16, -18)
    fisLabel:SetText("First Icon Scale")

    local fisSlider = CreateFrame("Slider", "TrueShotFirstIconScale", content,
        "OptionsSliderTemplate")
    fisSlider:SetPoint("TOPLEFT", fisLabel, "BOTTOMLEFT", 0, -12)
    fisSlider:SetSize(180, 16)
    fisSlider:SetMinMaxValues(1.0, 2.0)
    fisSlider:SetValueStep(0.1)
    fisSlider:SetObeyStepOnDrag(true)
    fisSlider:SetValue(TrueShot.GetOpt("firstIconScale"))
    fisSlider.Low:SetText("1.0")
    fisSlider.High:SetText("2.0")
    fisSlider.Text:SetText(string.format("%.1f", TrueShot.GetOpt("firstIconScale")))
    fisSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value * 10 + 0.5) / 10
        TrueShot.SetOpt("firstIconScale", value)
        self.Text:SetText(string.format("%.1f", value))
    end)

    -- Utility
    local unlockButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    unlockButton:SetSize(160, 24)
    unlockButton:SetPoint("TOPLEFT", fisSlider, "BOTTOMLEFT", 0, -18)
    unlockButton:SetText("Unlock And Recenter")
    unlockButton:SetScript("OnClick", function()
        TrueShot.SetOpt("locked", false)
        if TrueShot.Display and TrueShot.Display.ResetPosition then
            TrueShot.Display:ResetPosition()
            TrueShot.Display:SetClickThrough(false)
        end
        lockCheck:SetChecked(false)
    end)

    local hint = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", unlockButton, "BOTTOMLEFT", 0, -10)
    hint:SetPoint("RIGHT", content, "RIGHT", -24, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("For diagnostics and debugging, use /ts debug and /ts probe commands.")

    -- Dynamically size scroll child height from content
    local function UpdateScrollChildHeight()
        local top = scrollChild:GetTop()
        local bottom = hint:GetBottom()
        if top and bottom then
            scrollChild:SetHeight(top - bottom + 30)
        end
    end

    panel:SetScript("OnShow", function()
        C_Timer.After(0, UpdateScrollChildHeight)
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
        backdropCheck.sync()
        SyncPositionEditBoxes()
        UIDropDownMenu_SetText(orientDropdown, TrueShot.GetOpt("orientation"))
        local fis = TrueShot.GetOpt("firstIconScale") or 1.3
        fisSlider:SetValue(fis)
        fisSlider.Text:SetText(string.format("%.1f", fis))
    end)

    panel:SetScript("OnUpdate", function(_, elapsed)
        panel._coordsElapsed = (panel._coordsElapsed or 0) + elapsed
        if panel._coordsElapsed < 0.2 then return end
        panel._coordsElapsed = 0
        SyncPositionEditBoxes()
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
