-- TrueShot Settings: native Game Options with subcategory tabs

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

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

-- Run callback after WoW's Settings canvas finishes its own initialization.
-- OnShow fires before the Settings system has fully laid out the subcategory
-- panel, and GetTop() returns values immediately from anchors. We skip a
-- fixed number of frames to let the canvas settle, then run the sync.
local function RunAfterLayout(panel, _, callback)
    local frames = 0
    panel:SetScript("OnUpdate", function(self)
        frames = frames + 1
        if frames >= 3 then
            self:SetScript("OnUpdate", nil)
            callback()
        end
    end)
end

------------------------------------------------------------------------
-- Widget factories (shared across all panels)
------------------------------------------------------------------------

local function CreateSectionHeader(parent, text, relativeTo, yOffset)
    local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header:SetPoint("TOPLEFT", relativeTo, "BOTTOMLEFT", 0, yOffset or -20)
    header:SetText(text)
    return header
end

local function CreateCheckbox(parent, label, description, relativeTo, key)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(26, 26)
    check:SetPoint("TOPLEFT", relativeTo, "BOTTOMLEFT", 0, -14)
    check:SetChecked(TrueShot.GetOpt(key))

    local text = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", check, "RIGHT", 4, 0)
    text:SetText(label)
    check.Text = text
    -- Extend clickable area to cover the label text
    check:SetHitRectInsets(0, -text:GetStringWidth() - 8, 0, 0)

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

local function CreatePanelFrame()
    local panel = CreateFrame("Frame")
    panel:SetSize(640, 800)
    panel:Hide()  -- prevent premature OnShow during RegisterCanvasLayoutSubcategory
    return panel
end

local function CreatePanelTitle(parent, titleText, subtitleText)
    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -16)
    title:SetText(titleText)

    local subtitle = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText(subtitleText)

    return title, subtitle
end

------------------------------------------------------------------------
-- Tab 1: General
------------------------------------------------------------------------

local function CreateGeneralPanel()
    local panel = CreatePanelFrame()
    local _, subtitle = CreatePanelTitle(panel, "General",
        "Basic overlay behavior and visibility.")

    local lockCheck, lockDesc = CreateCheckbox(
        panel, "Lock overlay frame",
        "Disable dragging and make the overlay click-through.",
        subtitle, "locked"
    )

    local enemyCheck, enemyDesc = CreateCheckbox(
        panel, "Show only on enemy target",
        "Show the overlay when you have a hostile target or are in combat. Hides outside combat without an enemy target.",
        lockDesc, "enemyTargetOnly"
    )

    local combatCheck, combatDesc = CreateCheckbox(
        panel, "Show only in combat",
        "Hide the overlay outside of combat. Ignored when 'Show only on enemy target' is active.",
        enemyDesc, "combatOnly"
    )

    local loginCheck, loginDesc = CreateCheckbox(
        panel, "Show chat messages on login",
        "Display profile activation and switch messages in the chat window.",
        combatDesc, "showLoginMessage"
    )

    -- Utility section
    local utilHeader = CreateSectionHeader(panel, "Utility", loginDesc, -20)

    local unlockButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    unlockButton:SetSize(160, 24)
    unlockButton:SetPoint("TOPLEFT", utilHeader, "BOTTOMLEFT", 0, -10)
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
        RunAfterLayout(panel, nil, function()
            lockCheck.sync()
            enemyCheck.sync()
            combatCheck.sync()
            loginCheck.sync()
        end)
    end)

    return panel
end

------------------------------------------------------------------------
-- Tab 2: Appearance
------------------------------------------------------------------------

local function CreateAppearancePanel()
    local panel = CreatePanelFrame()
    local _, subtitle = CreatePanelTitle(panel, "Appearance",
        "Size, transparency, and layout of the overlay.")

    local scaleSlider, scaleDesc = CreateSlider(
        panel, "Overlay scale", "Size of the overlay icons.",
        subtitle, "overlayScale", 0.5, 2.0, 0.1
    )

    local opacitySlider, opacityDesc = CreateSlider(
        panel, "Overlay opacity", "Transparency of the overlay.",
        scaleDesc, "overlayOpacity", 0.3, 1.0, 0.1
    )

    local backdropCheck, backdropDesc = CreateCheckbox(
        panel, "Show Backdrop",
        "Show the dark background behind the queue overlay.",
        opacityDesc, "showBackdrop"
    )

    -- Orientation
    local orientLabel = CreateSectionHeader(panel, "Queue Orientation", backdropDesc, -20)

    local orientDropdown = CreateFrame("Frame", "TrueShotOrientDropdown", panel,
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
    local fisLabel = CreateSectionHeader(panel, "First Icon Scale", orientDropdown, -18)

    local fisSlider = CreateFrame("Slider", "TrueShotFirstIconScale", panel,
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

    -- Queue layout section
    local queueHeader = CreateSectionHeader(panel, "Queue Layout", fisSlider, -18)

    local countLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    countLabel:SetPoint("TOPLEFT", queueHeader, "BOTTOMLEFT", 0, -10)
    countLabel:SetText("Icon count")

    local countSlider = CreateFrame("Slider", "TrueShotIconCount", panel,
        "OptionsSliderTemplate")
    countSlider:SetPoint("TOPLEFT", countLabel, "BOTTOMLEFT", 0, -6)
    countSlider:SetSize(180, 16)
    countSlider:SetMinMaxValues(1, 4)
    countSlider:SetValueStep(1)
    countSlider:SetObeyStepOnDrag(true)
    countSlider:SetValue(TrueShot.GetOpt("iconCount"))
    countSlider.Low:SetText("1")
    countSlider.High:SetText("4")
    countSlider.Text:SetText(tostring(TrueShot.GetOpt("iconCount")))
    countSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        TrueShot.SetOpt("iconCount", value)
        self.Text:SetText(tostring(value))
    end)

    local sizeLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sizeLabel:SetPoint("TOPLEFT", countSlider, "BOTTOMLEFT", 0, -14)
    sizeLabel:SetText("Icon size")

    local sizeSlider = CreateFrame("Slider", "TrueShotIconSize", panel,
        "OptionsSliderTemplate")
    sizeSlider:SetPoint("TOPLEFT", sizeLabel, "BOTTOMLEFT", 0, -6)
    sizeSlider:SetSize(180, 16)
    sizeSlider:SetMinMaxValues(24, 64)
    sizeSlider:SetValueStep(4)
    sizeSlider:SetObeyStepOnDrag(true)
    sizeSlider:SetValue(TrueShot.GetOpt("iconSize"))
    sizeSlider.Low:SetText("24")
    sizeSlider.High:SetText("64")
    sizeSlider.Text:SetText(tostring(TrueShot.GetOpt("iconSize")))
    sizeSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / 4 + 0.5) * 4
        TrueShot.SetOpt("iconSize", value)
        self.Text:SetText(tostring(value))
    end)

    local spacingLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    spacingLabel:SetPoint("TOPLEFT", sizeSlider, "BOTTOMLEFT", 0, -14)
    spacingLabel:SetText("Icon spacing")

    local spacingSlider = CreateFrame("Slider", "TrueShotIconSpacing", panel,
        "OptionsSliderTemplate")
    spacingSlider:SetPoint("TOPLEFT", spacingLabel, "BOTTOMLEFT", 0, -6)
    spacingSlider:SetSize(180, 16)
    spacingSlider:SetMinMaxValues(0, 12)
    spacingSlider:SetValueStep(1)
    spacingSlider:SetObeyStepOnDrag(true)
    spacingSlider:SetValue(TrueShot.GetOpt("iconSpacing"))
    spacingSlider.Low:SetText("0")
    spacingSlider.High:SetText("12")
    spacingSlider.Text:SetText(tostring(TrueShot.GetOpt("iconSpacing")))
    spacingSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        TrueShot.SetOpt("iconSpacing", value)
        self.Text:SetText(tostring(value))
    end)

    panel:SetScript("OnShow", function()
        RunAfterLayout(panel, scaleSlider, function()
            scaleSlider.sync()
            opacitySlider.sync()
            backdropCheck.sync()
            UIDropDownMenu_SetText(orientDropdown, TrueShot.GetOpt("orientation"))
            local fis = TrueShot.GetOpt("firstIconScale") or 1.3
            fisSlider:SetValue(fis)
            fisSlider.Text:SetText(string.format("%.1f", fis))
            countSlider:SetValue(TrueShot.GetOpt("iconCount"))
            countSlider.Text:SetText(tostring(TrueShot.GetOpt("iconCount")))
            sizeSlider:SetValue(TrueShot.GetOpt("iconSize"))
            sizeSlider.Text:SetText(tostring(TrueShot.GetOpt("iconSize")))
            spacingSlider:SetValue(TrueShot.GetOpt("iconSpacing"))
            spacingSlider.Text:SetText(tostring(TrueShot.GetOpt("iconSpacing")))
        end)
    end)

    return panel
end

------------------------------------------------------------------------
-- Tab 3: Features
------------------------------------------------------------------------

local function CreateFeaturesPanel()
    local panel = CreatePanelFrame()

    -- ScrollFrame wrapping all content
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 0)

    local sc = CreateFrame("Frame", nil, scrollFrame)
    sc:SetSize(600, 1)
    scrollFrame:SetScrollChild(sc)

    scrollFrame:SetScript("OnSizeChanged", function(self, w)
        sc:SetWidth(w)
    end)

    local _, subtitle = CreatePanelTitle(sc, "Features",
        "Toggle overlay features and visual feedback.")

    local castCheck, castDesc = CreateCheckbox(
        sc, "Show cast success feedback",
        "Flash the icon briefly when your cast matches the recommendation.",
        subtitle, "showCastFeedback"
    )

    local cooldownCheck, cooldownDesc = CreateCheckbox(
        sc, "Show cooldown swipes (best-effort)",
        "Display cooldown sweep when readable. Not a promise of exact Midnight cooldown truth.",
        castDesc, "showCooldownSwipe"
    )

    local keybindCheck, keybindDesc = CreateCheckbox(
        sc, "Show keybindings",
        "Display the keybinding text on each icon.",
        cooldownDesc, "showKeybinds"
    )

    local rangeCheck, rangeDesc = CreateCheckbox(
        sc, "Show range indicator",
        "Tint the primary icon red when your target is out of range.",
        keybindDesc, "showRangeIndicator"
    )

    local whyCheck, whyDesc = CreateCheckbox(
        sc, "Show recommendation reason",
        "Display a label below the primary icon explaining why it was recommended (e.g. Withering Fire, Charge Dump).",
        rangeDesc, "showWhyOverlay"
    )

    local aoeHintCheck, aoeHintDesc = CreateCheckbox(
        sc, "Show AoE hint icon",
        "Display a secondary icon below the primary icon when an AoE ability is recommended (e.g. Wild Thrash at 2+ targets).",
        whyDesc, "showAoeHint"
    )

    local glowCheck, glowDesc = CreateCheckbox(
        sc, "Show override glow",
        "Pulsing glow on the first icon when TrueShot overrides Assisted Combat (cyan for PIN, blue for PREFER).",
        aoeHintDesc, "showOverrideIndicator"
    )

    local phaseCheck, phaseDesc = CreateCheckbox(
        sc, "Show phase indicator",
        "Display the current rotation phase label above the overlay (e.g. Opener, Cooldowns, Execute).",
        glowDesc, "showPhaseIndicator"
    )

    -- Performance section
    local perfHeader = CreateSectionHeader(sc, "Performance Tracking", phaseDesc, -20)

    local scorecardCheck, scorecardDesc = CreateCheckbox(
        sc,
        "Show alignment scorecard",
        "Display a rotation alignment report in chat after each combat (min 8s fight, 5+ casts).",
        perfHeader, "showScorecard"
    )

    local heartbeatCheck, heartbeatDesc = CreateCheckbox(
        sc,
        "Show GCD heartbeat",
        "Display a scrolling rhythm strip below the overlay showing cast alignment in real-time.",
        scorecardDesc, "showHeartbeat"
    )

    -- Positioning section
    local posHeader = CreateSectionHeader(sc, "Element Positioning", heartbeatDesc, -20)

    local reasonPosLabel = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    reasonPosLabel:SetPoint("TOPLEFT", posHeader, "BOTTOMLEFT", 0, -10)
    reasonPosLabel:SetText("Reason text position")

    local reasonPosDropdown = CreateFrame("Frame", "TrueShotReasonPosDD", sc, "UIDropDownMenuTemplate")
    reasonPosDropdown:SetPoint("TOPLEFT", reasonPosLabel, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(reasonPosDropdown, 100)

    local reasonPosOptions = { "BELOW", "ABOVE" }
    UIDropDownMenu_Initialize(reasonPosDropdown, function()
        for _, opt in ipairs(reasonPosOptions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt
            info.checked = (TrueShot.GetOpt("reasonPosition") == opt)
            info.func = function()
                TrueShot.SetOpt("reasonPosition", opt)
                UIDropDownMenu_SetText(reasonPosDropdown, opt)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    local reasonPosDesc = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    reasonPosDesc:SetPoint("TOPLEFT", reasonPosDropdown, "BOTTOMLEFT", 16, -2)
    reasonPosDesc:SetText("   Show the recommendation reason (e.g. Withering Fire) above or below the icon.")

    local aoeHintPosLabel = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    aoeHintPosLabel:SetPoint("TOPLEFT", reasonPosDesc, "BOTTOMLEFT", 0, -10)
    aoeHintPosLabel:SetText("AoE hint position")

    local aoeHintPosDropdown = CreateFrame("Frame", "TrueShotAoeHintPosDD", sc, "UIDropDownMenuTemplate")
    aoeHintPosDropdown:SetPoint("TOPLEFT", aoeHintPosLabel, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(aoeHintPosDropdown, 100)

    local aoeHintPosOptions = { "BELOW", "LEFT" }
    UIDropDownMenu_Initialize(aoeHintPosDropdown, function()
        for _, opt in ipairs(aoeHintPosOptions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt
            info.checked = (TrueShot.GetOpt("aoeHintPosition") == opt)
            info.func = function()
                TrueShot.SetOpt("aoeHintPosition", opt)
                UIDropDownMenu_SetText(aoeHintPosDropdown, opt)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    local aoeHintPosDesc = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    aoeHintPosDesc:SetPoint("TOPLEFT", aoeHintPosDropdown, "BOTTOMLEFT", 16, -2)
    aoeHintPosDesc:SetText("   Show the AoE hint icon (e.g. Wild Thrash) below the main icon or to its left.")

    -- Update scroll child height on show
    panel:SetScript("OnShow", function()
        RunAfterLayout(panel, sc, function()
            castCheck.sync()
            cooldownCheck.sync()
            keybindCheck.sync()
            rangeCheck.sync()
            whyCheck.sync()
            aoeHintCheck.sync()
            glowCheck.sync()
            phaseCheck.sync()
            scorecardCheck.sync()
            heartbeatCheck.sync()
            UIDropDownMenu_SetText(reasonPosDropdown, TrueShot.GetOpt("reasonPosition") or "BELOW")
            UIDropDownMenu_SetText(aoeHintPosDropdown, TrueShot.GetOpt("aoeHintPosition") or "BELOW")

            local top = sc:GetTop()
            local bottom = aoeHintPosDesc:GetBottom()
            if top and bottom then
                sc:SetHeight(top - bottom + 30)
            end
        end)
    end)

    return panel
end

------------------------------------------------------------------------
-- Tab 4: Position
------------------------------------------------------------------------

local function CreatePositionPanel()
    local panel = CreatePanelFrame()
    local _, subtitle = CreatePanelTitle(panel, "Position",
        "Overlay frame position and reset controls.")

    local coordInputsLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    coordInputsLabel:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -16)
    coordInputsLabel:SetText("Position offsets (UIParent)")

    local coordInputsRow = CreateFrame("Frame", nil, panel)
    coordInputsRow:SetSize(420, 22)
    coordInputsRow:SetPoint("TOPLEFT", coordInputsLabel, "BOTTOMLEFT", 0, -6)

    local xLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    xLabel:SetPoint("LEFT", coordInputsRow, "LEFT", 0, 0)
    xLabel:SetText("X")

    local xEdit = CreateCoordinateEditBox(panel, xLabel, 6)

    local yLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    yLabel:SetPoint("LEFT", xEdit, "RIGHT", 14, 0)
    yLabel:SetText("Y")

    local yEdit = CreateCoordinateEditBox(panel, yLabel, 6)

    local applyCoordsButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
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

    local applyingFromEnter = false
    xEdit:SetScript("OnEnterPressed", function(self)
        applyingFromEnter = true
        ApplyPositionFromInputs()
        self:ClearFocus()
        applyingFromEnter = false
    end)
    yEdit:SetScript("OnEnterPressed", function(self)
        applyingFromEnter = true
        ApplyPositionFromInputs()
        self:ClearFocus()
        applyingFromEnter = false
    end)
    xEdit:SetScript("OnEditFocusLost", function()
        if not applyingFromEnter then ApplyPositionFromInputs() end
    end)
    yEdit:SetScript("OnEditFocusLost", function()
        if not applyingFromEnter then ApplyPositionFromInputs() end
    end)
    applyCoordsButton:SetScript("OnClick", ApplyPositionFromInputs)

    panel:SetScript("OnShow", function()
        panel._coordsNeedSync = true
    end)

    panel:SetScript("OnUpdate", function(_, elapsed)
        if not panel:IsShown() then return end
        -- Sync immediately on first frame after show, then every 0.2s
        if panel._coordsNeedSync then
            panel._coordsNeedSync = false
            panel._coordsElapsed = 0
            SyncPositionEditBoxes()
            return
        end
        panel._coordsElapsed = (panel._coordsElapsed or 0) + elapsed
        if panel._coordsElapsed < 0.2 then return end
        panel._coordsElapsed = 0
        SyncPositionEditBoxes()
    end)

    return panel
end

------------------------------------------------------------------------
-- Tab 5: Profiles
------------------------------------------------------------------------

-- Spec ID to class/spec display names
local SPEC_INFO = {
    [253]  = { class = "Hunter",       spec = "Beast Mastery" },
    [254]  = { class = "Hunter",       spec = "Marksmanship" },
    [255]  = { class = "Hunter",       spec = "Survival" },
    [577]  = { class = "Demon Hunter", spec = "Havoc" },
    [1480] = { class = "Demon Hunter", spec = "Devourer" },
    [102]  = { class = "Druid",        spec = "Balance" },
    [103]  = { class = "Druid",        spec = "Feral" },
    [62]   = { class = "Mage",         spec = "Arcane" },
    [63]   = { class = "Mage",         spec = "Fire" },
    [64]   = { class = "Mage",         spec = "Frost" },
}

-- Class display order
local CLASS_ORDER = { "Hunter", "Demon Hunter", "Druid", "Mage" }

-- Class colors (WoW standard)
local CLASS_COLORS = {
    ["Hunter"]       = "abd473",
    ["Demon Hunter"] = "a330c9",
    ["Druid"]        = "ff7c0a",
    ["Mage"]         = "3fc7eb",
}

local MAX_PROFILE_ROWS = 30  -- pre-allocate pool (22 profiles + headroom)

local function CreateProfilesPanel()
    local panel = CreatePanelFrame()

    -- ScrollFrame for profile list
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 0)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(600, 1)
    scrollFrame:SetScrollChild(scrollChild)

    scrollFrame:SetScript("OnSizeChanged", function(self, w)
        scrollChild:SetWidth(w)
    end)

    local _, subtitle = CreatePanelTitle(scrollChild, "Profiles",
        "All registered rotation profiles. The active profile is highlighted.")

    local ruleBuilderButton = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
    ruleBuilderButton:SetSize(180, 24)
    ruleBuilderButton:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -8, -16)
    ruleBuilderButton:SetText("Open Rule Builder")
    ruleBuilderButton:SetScript("OnClick", function()
        if TrueShot.RuleBuilder and TrueShot.RuleBuilder.Toggle then
            TrueShot.RuleBuilder:Toggle()
        end
    end)

    -- Pre-allocate class header pool (one per class)
    local classHeaders = {}
    for i = 1, #CLASS_ORDER do
        local header = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        header:Hide()
        classHeaders[i] = header
    end

    -- Pre-allocate row pool
    local rowPool = {}
    for i = 1, MAX_PROFILE_ROWS do
        local row = CreateFrame("Frame", nil, scrollChild)
        row:SetSize(560, 20)
        row:Hide()

        row.nameText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.nameText:SetPoint("LEFT", row, "LEFT", 12, 0)

        row.specText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.specText:SetPoint("LEFT", row, "LEFT", 260, 0)

        rowPool[i] = row
    end

    local emptyText = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    emptyText:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -16)
    emptyText:SetText("No profiles registered.")
    emptyText:Hide()

    local function SyncProfileList()
        -- Hide all pooled elements
        for _, header in ipairs(classHeaders) do header:Hide() end
        for _, row in ipairs(rowPool) do row:Hide() end
        emptyText:Hide()

        local lastElement = subtitle
        local activeProfile = TrueShot.Engine and TrueShot.Engine.activeProfile
        local rowIndex = 0
        local headerIndex = 0
        local hasProfiles = false

        -- Group profiles by class
        local byClass = {}
        for specID, profiles in pairs(TrueShot.Profiles or {}) do
            local info = SPEC_INFO[specID]
            if info then
                if not byClass[info.class] then
                    byClass[info.class] = {}
                end
                for _, profile in ipairs(profiles) do
                    table.insert(byClass[info.class], {
                        profile = profile,
                        spec = info.spec,
                    })
                end
            end
        end

        for _, className in ipairs(CLASS_ORDER) do
            local profiles = byClass[className]
            if profiles and #profiles > 0 then
                hasProfiles = true
                local color = CLASS_COLORS[className] or "ffffff"

                headerIndex = headerIndex + 1
                local classHeader = classHeaders[headerIndex]
                if classHeader then
                    classHeader:ClearAllPoints()
                    classHeader:SetPoint("TOPLEFT", lastElement, "BOTTOMLEFT", 0, -18)
                    classHeader:SetText("|cff" .. color .. className .. "|r")
                    classHeader:Show()
                    lastElement = classHeader
                end

                -- Sort profiles by spec then display name
                table.sort(profiles, function(a, b)
                    if a.spec ~= b.spec then return a.spec < b.spec end
                    return (a.profile.displayName or a.profile.id) < (b.profile.displayName or b.profile.id)
                end)

                for _, entry in ipairs(profiles) do
                    rowIndex = rowIndex + 1
                    if rowIndex > MAX_PROFILE_ROWS then break end

                    local p = entry.profile
                    local isActive = (p == activeProfile)
                        or (activeProfile and activeProfile._baseProfile == p)
                    local name = p.displayName or p.id or "Unknown"

                    local row = rowPool[rowIndex]
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", lastElement, "BOTTOMLEFT", 0, -6)

                    local fontObj = isActive
                        and GameFontGreen
                        or GameFontHighlight
                    row.nameText:SetFontObject(fontObj)

                    if isActive and TrueShot.CustomProfile
                        and TrueShot.CustomProfile.HasCustomData(p.id) then
                        row.nameText:SetText(name .. "  |cff00ff00(active, customized)|r")
                    elseif isActive then
                        row.nameText:SetText(name .. "  |cff00ff00(active)|r")
                    else
                        row.nameText:SetText(name)
                    end

                    row.specText:SetText("|cffaaaaaa" .. entry.spec .. "|r")
                    row:Show()
                    lastElement = row
                end
            end
        end

        if not hasProfiles then
            emptyText:Show()
            lastElement = emptyText
        end

        -- Update scroll child height (layout already settled from outer RunAfterLayout)
        C_Timer.After(0, function()
            local top = scrollChild:GetTop()
            local bottom = lastElement and lastElement:GetBottom()
            if top and bottom then
                scrollChild:SetHeight(top - bottom + 30)
            end
        end)
    end

    panel:SetScript("OnShow", function()
        RunAfterLayout(panel, scrollChild, function()
            SyncProfileList()
        end)
    end)

    return panel
end

------------------------------------------------------------------------
-- Landing page (main category)
------------------------------------------------------------------------

local function CreateLandingPanel()
    local panel = CreatePanelFrame()
    local _, subtitle = CreatePanelTitle(panel, "TrueShot",
        "Midnight-compatible rotation overlay on top of Blizzard Assisted Combat.")

    local versionText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    versionText:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -16)

    local version = C_AddOns and C_AddOns.GetAddOnMetadata
        and C_AddOns.GetAddOnMetadata("TrueShot", "Version")
        or (GetAddOnMetadata and GetAddOnMetadata("TrueShot", "Version"))
        or "unknown"
    versionText:SetText("Version: |cffffff00" .. version .. "|r")

    local profileLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    profileLabel:SetPoint("TOPLEFT", versionText, "BOTTOMLEFT", 0, -8)

    local helpText = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    helpText:SetPoint("TOPLEFT", profileLabel, "BOTTOMLEFT", 0, -20)
    helpText:SetPoint("RIGHT", panel, "RIGHT", -24, 0)
    helpText:SetJustifyH("LEFT")
    helpText:SetText("Use the subcategories in the sidebar to configure TrueShot.\n\nSlash commands: /ts help")

    panel:SetScript("OnShow", function()
        local active = TrueShot.Engine and TrueShot.Engine.activeProfile
        if active then
            local name = active.displayName or active.id or "unknown"
            profileLabel:SetText("Active profile: |cff00ff00" .. name .. "|r")
        else
            profileLabel:SetText("Active profile: |cffaaaaaa(none)|r")
        end
    end)

    return panel
end

------------------------------------------------------------------------
-- Registration
------------------------------------------------------------------------

local function RegisterSettingsPanel()
    if settingsCategory or not Settings
        or not Settings.RegisterCanvasLayoutCategory
        or not Settings.RegisterAddOnCategory
        or not Settings.RegisterCanvasLayoutSubcategory then
        return
    end

    local landingPanel = CreateLandingPanel()
    settingsCategory = Settings.RegisterCanvasLayoutCategory(landingPanel, "TrueShot")
    Settings.RegisterAddOnCategory(settingsCategory)

    local tabs = {
        { name = "General",    factory = CreateGeneralPanel },
        { name = "Appearance", factory = CreateAppearancePanel },
        { name = "Features",   factory = CreateFeaturesPanel },
        { name = "Position",   factory = CreatePositionPanel },
        { name = "Profiles",   factory = CreateProfilesPanel },
    }

    for _, tab in ipairs(tabs) do
        local panel = tab.factory()
        Settings.RegisterCanvasLayoutSubcategory(settingsCategory, panel, tab.name)
    end
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
