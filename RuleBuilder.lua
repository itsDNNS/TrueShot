-- TrueShot Rule Builder: visual rule editor for custom profiles
-- Two-panel split frame (WeakAuras pattern)

TrueShot = TrueShot or {}
TrueShot.RuleBuilder = {}

local RuleBuilder = TrueShot.RuleBuilder
local CustomProfile = TrueShot.CustomProfile

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------

local FRAME_WIDTH = 780
local FRAME_HEIGHT = 520
local LEFT_PANEL_WIDTH = 280
local RULE_ROW_HEIGHT = 28
local MAX_RULE_ROWS = 80  -- generous cap; profiles rarely exceed 20 rules

local TYPE_COLORS = {
    PIN                  = { r = 1.0, g = 0.4, b = 0.4 },
    PREFER               = { r = 0.4, g = 0.4, b = 1.0 },
    BLACKLIST             = { r = 0.6, g = 0.6, b = 0.6 },
    BLACKLIST_CONDITIONAL = { r = 0.6, g = 0.6, b = 0.6 },
}

local TYPE_LABELS = {
    PIN                  = "PIN",
    PREFER               = "PREFER",
    BLACKLIST             = "BL",
    BLACKLIST_CONDITIONAL = "BL?",
}

local TYPE_ORDER = { "PIN", "PREFER", "BLACKLIST", "BLACKLIST_CONDITIONAL" }

local CONDITION_PRESETS = {
    { label = "Spell Proc Active",      template = { type = "spell_glowing", spellID = nil } },
    { label = "AoE (2+ targets)",       template = { type = "target_count", op = ">=", value = 2 } },
    { label = "Burst Mode Active",      template = { type = "burst_mode" } },
    { label = "Combat Opening",         template = { type = "combat_opening", duration = 2 } },
    { label = "Spell Charges At/Above", template = { type = "spell_charges", spellID = nil, op = ">=", value = 2 } },
}

local MAX_CONDITION_DEPTH = 4
local INDENT_PER_DEPTH = 16

local _ddCounter = 0
local function NextDropdownName(prefix)
    _ddCounter = _ddCounter + 1
    return prefix .. _ddCounter
end

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------

local _mainFrame = nil
local _leftScrollChild = nil
local _rightPanel = nil
local _ruleRows = {}
local _stateVarRows = {}
local _sectionHeaders = {}  -- left panel section header labels
local _selectedIndex = nil
local _selectedVarIndex = nil  -- index into stateVarDefs, or nil
local _editingData = nil  -- the custom data being edited
local _isCustomized = false
local _editorFrames = {}  -- tracked frames for editor cleanup
local RenderConditionTree  -- forward declaration for recursive rendering

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

-- Recursively check if a condition tree references a given condition type ID
local function ConditionReferencesType(condition, typeId)
    if not condition then return false end
    if condition.type == typeId then return true end
    if condition.type == "and" or condition.type == "or" then
        return ConditionReferencesType(condition.left, typeId)
            or ConditionReferencesType(condition.right, typeId)
    end
    if condition.type == "not" then
        return ConditionReferencesType(condition.inner, typeId)
    end
    return false
end

-- Recursively nullify references to a condition type ID (replace with nil)
-- Returns the cleaned condition (nil if the node itself was the reference)
local function RemoveConditionType(condition, typeId)
    if not condition then return nil end
    if condition.type == typeId then return nil end
    if condition.type == "and" or condition.type == "or" then
        condition.left = RemoveConditionType(condition.left, typeId)
        condition.right = RemoveConditionType(condition.right, typeId)
        -- If one side is nil, collapse to the other
        if not condition.left and not condition.right then return nil end
        if not condition.left then return condition.right end
        if not condition.right then return condition.left end
        return condition
    end
    if condition.type == "not" then
        condition.inner = RemoveConditionType(condition.inner, typeId)
        if not condition.inner then return nil end
        return condition
    end
    return condition
end

local function GetSpellDisplay(spellID)
    if not spellID then return nil, "Unknown" end
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID) or "Spell " .. spellID
    local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID) or 134400
    return icon, name
end

local function DeepCopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = DeepCopy(v)
    end
    return copy
end

local function GetRotationalSpellList()
    if not _editingData or not _editingData.rotationalSpells then return {} end
    local list = {}
    for spellID in pairs(_editingData.rotationalSpells) do
        if type(spellID) == "number" then
            list[#list + 1] = spellID
        end
    end
    table.sort(list)
    return list
end

local function GetProfileId()
    local Engine = TrueShot.Engine
    local profile = Engine and Engine.activeProfile
    if not profile then return nil end
    local base = profile._baseProfile or profile
    return base.id
end

------------------------------------------------------------------------
-- Frame Creation
------------------------------------------------------------------------

local function CreateMainFrame()
    local f = CreateFrame("Frame", "TrueShotRuleBuilder", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.08, 0.08, 0.12, 0.95)
    f:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    -- Title bar (draggable)
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetHeight(28)
    titleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    local titleText = titleBar:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    titleText:SetPoint("LEFT", titleBar, "LEFT", 8, 0)
    titleText:SetText("|cffabd473TrueShot|r Rule Builder")
    f._titleText = titleText

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Profile name label
    local profileLabel = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    profileLabel:SetPoint("LEFT", titleText, "RIGHT", 12, 0)
    f._profileLabel = profileLabel

    -- Divider line below title
    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -34)
    divider:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -34)
    divider:SetColorTexture(0.3, 0.3, 0.3, 1)

    -- Left panel (rule list)
    local leftPanel = CreateFrame("Frame", nil, f)
    leftPanel:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -38)
    leftPanel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 44)
    leftPanel:SetWidth(LEFT_PANEL_WIDTH)

    local leftScroll = CreateFrame("ScrollFrame", "TrueShotRBLeftScroll", leftPanel, "UIPanelScrollFrameTemplate")
    leftScroll:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 0, 0)
    leftScroll:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -22, 0)

    _leftScrollChild = CreateFrame("Frame", nil, leftScroll)
    _leftScrollChild:SetWidth(LEFT_PANEL_WIDTH - 22)
    _leftScrollChild:SetHeight(1)
    leftScroll:SetScrollChild(_leftScrollChild)

    -- Vertical divider between panels
    local vdivider = f:CreateTexture(nil, "ARTWORK")
    vdivider:SetWidth(1)
    vdivider:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 4, 0)
    vdivider:SetPoint("BOTTOMLEFT", leftPanel, "BOTTOMRIGHT", 4, 0)
    vdivider:SetColorTexture(0.3, 0.3, 0.3, 1)

    -- Right panel
    _rightPanel = CreateFrame("Frame", nil, f)
    _rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 10, 0)
    _rightPanel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 44)

    -- Bottom bar
    local bottomBar = CreateFrame("Frame", nil, f)
    bottomBar:SetHeight(36)
    bottomBar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 4)
    bottomBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 4)

    -- Bottom divider
    local bdivider = f:CreateTexture(nil, "ARTWORK")
    bdivider:SetHeight(1)
    bdivider:SetPoint("BOTTOMLEFT", bottomBar, "TOPLEFT", 0, 0)
    bdivider:SetPoint("BOTTOMRIGHT", bottomBar, "TOPRIGHT", 0, 0)
    bdivider:SetColorTexture(0.3, 0.3, 0.3, 1)

    -- Customize / Apply / Reset buttons
    local customizeBtn = CreateFrame("Button", nil, bottomBar, "UIPanelButtonTemplate")
    customizeBtn:SetSize(100, 22)
    customizeBtn:SetPoint("LEFT", bottomBar, "LEFT", 0, 0)
    customizeBtn:SetText("Customize")
    customizeBtn:SetScript("OnClick", function()
        RuleBuilder:OnCustomize()
    end)
    f._customizeBtn = customizeBtn

    local applyBtn = CreateFrame("Button", nil, bottomBar, "UIPanelButtonTemplate")
    applyBtn:SetSize(80, 22)
    applyBtn:SetPoint("RIGHT", bottomBar, "RIGHT", 0, 0)
    applyBtn:SetText("Apply")
    applyBtn:SetScript("OnClick", function()
        RuleBuilder:OnApply()
    end)
    f._applyBtn = applyBtn

    local resetBtn = CreateFrame("Button", nil, bottomBar, "UIPanelButtonTemplate")
    resetBtn:SetSize(110, 22)
    resetBtn:SetPoint("RIGHT", applyBtn, "LEFT", -6, 0)
    resetBtn:SetText("Reset to Built-in")
    resetBtn:SetScript("OnClick", function()
        StaticPopup_Show("TRUESHOT_RESET_CUSTOM")
    end)
    f._resetBtn = resetBtn

    local addRuleBtn = CreateFrame("Button", nil, bottomBar, "UIPanelButtonTemplate")
    addRuleBtn:SetSize(80, 22)
    addRuleBtn:SetPoint("LEFT", customizeBtn, "RIGHT", 6, 0)
    addRuleBtn:SetText("+ Add Rule")
    addRuleBtn:SetScript("OnClick", function()
        RuleBuilder:OnAddRule()
    end)
    f._addRuleBtn = addRuleBtn

    local addVarBtn = CreateFrame("Button", nil, bottomBar, "UIPanelButtonTemplate")
    addVarBtn:SetSize(100, 22)
    addVarBtn:SetPoint("LEFT", addRuleBtn, "RIGHT", 6, 0)
    addVarBtn:SetText("+ State Var")
    addVarBtn:SetScript("OnClick", function()
        RuleBuilder:OnAddStateVar()
    end)
    f._addVarBtn = addVarBtn

    f:Hide()
    return f
end

-- Static popup for reset confirmation
StaticPopupDialogs["TRUESHOT_RESET_CUSTOM"] = {
    text = "Reset to built-in profile? All custom rules and state variables will be deleted.",
    button1 = "Reset",
    button2 = "Cancel",
    OnAccept = function()
        RuleBuilder:OnReset()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

------------------------------------------------------------------------
-- Rule Row Pool
------------------------------------------------------------------------

local function CreateRuleRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(LEFT_PANEL_WIDTH - 22, RULE_ROW_HEIGHT)
    row:EnableMouse(true)

    -- Selection highlight
    local highlight = row:CreateTexture(nil, "BACKGROUND")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.08)
    highlight:Hide()
    row._highlight = highlight

    -- Selected indicator
    local selected = row:CreateTexture(nil, "BACKGROUND")
    selected:SetAllPoints()
    selected:SetColorTexture(0.3, 0.5, 0.3, 0.2)
    selected:Hide()
    row._selected = selected

    -- Type badge
    local badge = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    badge:SetPoint("LEFT", row, "LEFT", 4, 0)
    badge:SetWidth(30)
    badge:SetJustifyH("LEFT")
    row._badge = badge

    -- Spell icon
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("LEFT", badge, "RIGHT", 4, 0)
    row._icon = icon

    -- Spell name + reason
    local nameText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    nameText:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    nameText:SetPoint("RIGHT", row, "RIGHT", -50, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    row._nameText = nameText

    -- Up button
    local upBtn = CreateFrame("Button", nil, row)
    upBtn:SetSize(14, 14)
    upBtn:SetPoint("RIGHT", row, "RIGHT", -18, 4)
    upBtn:SetNormalTexture("Interface\\Buttons\\Arrow-Up-Up")
    upBtn:SetHighlightTexture("Interface\\Buttons\\Arrow-Up-Highlight")
    upBtn:SetScript("OnClick", function()
        RuleBuilder:MoveRule(index, -1)
    end)
    row._upBtn = upBtn

    -- Down button
    local downBtn = CreateFrame("Button", nil, row)
    downBtn:SetSize(14, 14)
    downBtn:SetPoint("RIGHT", row, "RIGHT", -18, -4)
    downBtn:SetNormalTexture("Interface\\Buttons\\Arrow-Down-Up")
    downBtn:SetHighlightTexture("Interface\\Buttons\\Arrow-Down-Highlight")
    downBtn:SetScript("OnClick", function()
        RuleBuilder:MoveRule(index, 1)
    end)
    row._downBtn = downBtn

    -- Delete button
    local delBtn = CreateFrame("Button", nil, row)
    delBtn:SetSize(14, 14)
    delBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    local delTex = delBtn:CreateTexture(nil, "ARTWORK")
    delTex:SetAllPoints()
    delTex:SetColorTexture(0.8, 0.2, 0.2, 0.6)
    delBtn:SetScript("OnClick", function()
        RuleBuilder:DeleteRule(index)
    end)
    row._delBtn = delBtn

    -- Hover scripts
    row:SetScript("OnEnter", function() highlight:Show() end)
    row:SetScript("OnLeave", function() highlight:Hide() end)
    row:SetScript("OnClick", function()
        RuleBuilder:SelectRule(index)
    end)

    row:Hide()
    return row
end

local function CreateStateVarRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(LEFT_PANEL_WIDTH - 22, RULE_ROW_HEIGHT)
    row:EnableMouse(true)

    local highlight = row:CreateTexture(nil, "BACKGROUND")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.08)
    highlight:Hide()
    row._highlight = highlight

    local selected = row:CreateTexture(nil, "BACKGROUND")
    selected:SetAllPoints()
    selected:SetColorTexture(0.5, 0.3, 0.7, 0.2)
    selected:Hide()
    row._selected = selected

    -- Type badge (var type abbreviation)
    local badge = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    badge:SetPoint("LEFT", row, "LEFT", 4, 0)
    badge:SetWidth(30)
    badge:SetJustifyH("LEFT")
    row._badge = badge

    -- Var name
    local nameText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    nameText:SetPoint("LEFT", badge, "RIGHT", 4, 0)
    nameText:SetPoint("RIGHT", row, "RIGHT", -18, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    row._nameText = nameText

    -- Delete button
    local delBtn = CreateFrame("Button", nil, row)
    delBtn:SetSize(14, 14)
    delBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    local delTex = delBtn:CreateTexture(nil, "ARTWORK")
    delTex:SetAllPoints()
    delTex:SetColorTexture(0.8, 0.2, 0.2, 0.6)
    delBtn:SetScript("OnClick", function()
        RuleBuilder:DeleteStateVar(index)
    end)
    row._delBtn = delBtn

    row:SetScript("OnEnter", function() highlight:Show() end)
    row:SetScript("OnLeave", function() highlight:Hide() end)
    row:SetScript("OnClick", function()
        RuleBuilder:SelectStateVar(index)
    end)

    row:Hide()
    return row
end

------------------------------------------------------------------------
-- Rule List Rendering
------------------------------------------------------------------------

local SECTION_HEADER_HEIGHT = 22

local function GetOrCreateSectionHeader(key, parent, text)
    if not _sectionHeaders[key] then
        local hdr = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        hdr:SetText(text)
        _sectionHeaders[key] = hdr
    end
    return _sectionHeaders[key]
end

function RuleBuilder:RefreshRuleList()
    local rules = _editingData and _editingData.rules or {}
    local vars  = _editingData and _editingData.stateVarDefs or {}

    ----------------------------------------------------------------
    -- Section: Rules
    ----------------------------------------------------------------
    local rulesHeader = GetOrCreateSectionHeader("rules", _leftScrollChild, "|cffaaaaaa Rules|r")
    rulesHeader:SetPoint("TOPLEFT", _leftScrollChild, "TOPLEFT", 4, 0)
    rulesHeader:Show()

    -- Ensure enough rule rows
    while #_ruleRows < math.min(#rules, MAX_RULE_ROWS) do
        local idx = #_ruleRows + 1
        _ruleRows[idx] = CreateRuleRow(_leftScrollChild, idx)
    end

    -- Update rule rows
    for i = 1, MAX_RULE_ROWS do
        local row = _ruleRows[i]
        if not row then break end

        if i <= #rules then
            local rule = rules[i]
            local tc = TYPE_COLORS[rule.type] or TYPE_COLORS.BLACKLIST
            local tl = TYPE_LABELS[rule.type] or "?"

            row._badge:SetText("|cff" .. string.format("%02x%02x%02x", tc.r * 255, tc.g * 255, tc.b * 255) .. tl .. "|r")

            local spellIcon, spellName = GetSpellDisplay(rule.spellID)
            row._icon:SetTexture(spellIcon)
            row._nameText:SetText(spellName .. (rule.reason and (" - " .. rule.reason) or ""))

            if i == _selectedIndex then
                row._selected:Show()
            else
                row._selected:Hide()
            end

            if _isCustomized then
                row._upBtn:SetShown(i > 1)
                row._downBtn:SetShown(i < #rules)
                row._delBtn:Show()
            else
                row._upBtn:Hide()
                row._downBtn:Hide()
                row._delBtn:Hide()
            end

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", _leftScrollChild, "TOPLEFT", 0, -(SECTION_HEADER_HEIGHT + (i - 1) * RULE_ROW_HEIGHT))
            row:Show()
        else
            row:Hide()
        end
    end

    local rulesSectionHeight = SECTION_HEADER_HEIGHT + #rules * RULE_ROW_HEIGHT

    ----------------------------------------------------------------
    -- Section: State Variables
    ----------------------------------------------------------------
    local varsHeader = GetOrCreateSectionHeader("vars", _leftScrollChild, "|cffaaaaaa State Variables|r")
    varsHeader:ClearAllPoints()
    varsHeader:SetPoint("TOPLEFT", _leftScrollChild, "TOPLEFT", 4, -(rulesSectionHeight + 6))
    varsHeader:Show()

    -- Ensure enough state var rows
    while #_stateVarRows < #vars do
        local idx = #_stateVarRows + 1
        _stateVarRows[idx] = CreateStateVarRow(_leftScrollChild, idx)
    end

    local VAR_TYPE_SHORT = { boolean = "BOL", number = "NUM", timestamp = "TS" }

    for i = 1, #_stateVarRows do
        local row = _stateVarRows[i]
        if i <= #vars then
            local def = vars[i]
            local abbr = VAR_TYPE_SHORT[def.varType] or "?"
            row._badge:SetText("|cff8888ff" .. abbr .. "|r")
            row._nameText:SetText(def.label or def.name or "?")

            if i == _selectedVarIndex then
                row._selected:Show()
            else
                row._selected:Hide()
            end

            if _isCustomized then
                row._delBtn:Show()
            else
                row._delBtn:Hide()
            end

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", _leftScrollChild, "TOPLEFT", 0,
                -(rulesSectionHeight + 6 + SECTION_HEADER_HEIGHT + (i - 1) * RULE_ROW_HEIGHT))
            row:Show()
        else
            row:Hide()
        end
    end

    local varsSectionHeight = SECTION_HEADER_HEIGHT + #vars * RULE_ROW_HEIGHT
    local totalHeight = rulesSectionHeight + 6 + varsSectionHeight + 8
    _leftScrollChild:SetHeight(math.max(1, totalHeight))
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------

function RuleBuilder:Toggle()
    if not _mainFrame then
        _mainFrame = CreateMainFrame()
    end
    if _mainFrame:IsShown() then
        _mainFrame:Hide()
    else
        self:Open()
    end
end

function RuleBuilder:Open()
    if not _mainFrame then
        _mainFrame = CreateMainFrame()
    end

    local Engine = TrueShot.Engine
    local profile = Engine and Engine.activeProfile
    if not profile then
        print("|cffff0000[TS]|r No active profile.")
        return
    end

    -- Determine base profile (unwrap if customized)
    local baseProfile = profile._baseProfile or profile
    local profileId = baseProfile.id

    -- Update title
    _mainFrame._profileLabel:SetText("|cffaaaaaa" .. (baseProfile.displayName or profileId) .. "|r")

    -- Load existing custom data or show built-in rules read-only
    local customData = CustomProfile.GetCustomData(profileId)
    if customData then
        _editingData = DeepCopy(customData)  -- work on a copy, not the live SavedVariables
        _isCustomized = true
    else
        -- Read-only view of built-in rules
        _editingData = {
            rules = baseProfile.rules or {},
            stateVarDefs = {},
            triggers = {},
            rotationalSpells = baseProfile.rotationalSpells or {},
        }
        _isCustomized = false
    end

    _selectedIndex = nil
    _selectedVarIndex = nil
    self:RefreshRuleList()
    self:UpdateButtonStates()
    self:ClearRightPanel()
    _mainFrame:Show()
end

function RuleBuilder:UpdateButtonStates()
    if not _mainFrame then return end
    _mainFrame._customizeBtn:SetShown(not _isCustomized)
    _mainFrame._applyBtn:SetShown(_isCustomized)
    _mainFrame._resetBtn:SetShown(_isCustomized)
    _mainFrame._addRuleBtn:SetShown(_isCustomized)
    _mainFrame._addVarBtn:SetShown(_isCustomized)
end

local _hintText = nil  -- reusable hint FontString

function RuleBuilder:ClearRightPanel()
    -- Clear all children of the right panel
    if not _rightPanel then return end
    ClearEditorFrames()
    for _, child in pairs({ _rightPanel:GetChildren() }) do
        child:Hide()
        child:SetParent(nil)
    end
    -- Hide reusable hint
    if _hintText then _hintText:Hide() end

    if not _isCustomized then
        if not _hintText then
            _hintText = _rightPanel:CreateFontString(nil, "ARTWORK", "GameFontDisable")
        end
        _hintText:ClearAllPoints()
        _hintText:SetPoint("CENTER", _rightPanel, "CENTER")
        _hintText:SetText("Read-only view.\nClick 'Customize' to edit.")
        _hintText:Show()
    elseif not _selectedIndex and not _selectedVarIndex then
        if not _hintText then
            _hintText = _rightPanel:CreateFontString(nil, "ARTWORK", "GameFontDisable")
        end
        _hintText:ClearAllPoints()
        _hintText:SetPoint("CENTER", _rightPanel, "CENTER")
        _hintText:SetText("Select a rule or state variable to edit,\nor add a new one.")
        _hintText:Show()
    end
end

------------------------------------------------------------------------
-- Actions
------------------------------------------------------------------------

function RuleBuilder:OnCustomize()
    local Engine = TrueShot.Engine
    local profile = Engine and Engine.activeProfile
    if not profile then return end

    local baseProfile = profile._baseProfile or profile
    local customData = CustomProfile.ForkProfile(baseProfile)
    _editingData = customData
    _isCustomized = true
    _selectedIndex = nil
    _selectedVarIndex = nil
    self:RefreshRuleList()
    self:UpdateButtonStates()
    self:ClearRightPanel()
    print("|cff00ff00[TS]|r Profile customized. Edit rules and click Apply.")
end

function RuleBuilder:OnApply()
    if not _editingData or not _isCustomized then return end

    local Engine = TrueShot.Engine
    local profile = Engine and Engine.activeProfile
    if not profile then return end

    -- Validate rules before saving
    for i, rule in ipairs(_editingData.rules or {}) do
        if not rule.spellID or type(rule.spellID) ~= "number" then
            print("|cffff0000[TS]|r Rule " .. i .. " has no valid spell selected. Fix before applying.")
            return
        end
        if not rule.type then
            print("|cffff0000[TS]|r Rule " .. i .. " has no type selected. Fix before applying.")
            return
        end
    end
    -- Validate triggers
    for i, trig in ipairs(_editingData.triggers or {}) do
        if not trig.spellID or type(trig.spellID) ~= "number" then
            print("|cffff0000[TS]|r Trigger " .. i .. " has no valid spell selected. Fix before applying.")
            return
        end
        if not trig.varName or trig.varName == "" then
            print("|cffff0000[TS]|r Trigger " .. i .. " has no variable assigned. Fix before applying.")
            return
        end
    end

    local baseProfile = profile._baseProfile or profile
    -- Save a copy so continued editing doesn't mutate SavedVariables
    CustomProfile.SaveCustomData(baseProfile.id, DeepCopy(_editingData))
    CustomProfile.InvalidateWrapper(baseProfile.id)

    -- Register custom conditions
    CustomProfile.RegisterCustomConditions(baseProfile.id, _editingData.stateVarDefs)

    -- Re-activate to pick up changes
    local specID = baseProfile.specID
    Engine:ActivateProfile(specID)

    print("|cff00ff00[TS]|r Custom rules applied.")
end

function RuleBuilder:OnReset()
    local Engine = TrueShot.Engine
    local profile = Engine and Engine.activeProfile
    if not profile then return end

    local baseProfile = profile._baseProfile or profile
    CustomProfile.DeleteCustomData(baseProfile.id)
    CustomProfile.InvalidateWrapper(baseProfile.id)

    -- Re-activate to revert to built-in
    Engine:ActivateProfile(baseProfile.specID)

    -- Refresh UI
    self:Open()
    print("|cff00ff00[TS]|r Reset to built-in profile.")
end

function RuleBuilder:SelectRule(index)
    _selectedIndex = index
    _selectedVarIndex = nil
    self:RefreshRuleList()
    self:ShowRuleEditor(index)
end

function RuleBuilder:SelectStateVar(index)
    _selectedVarIndex = index
    _selectedIndex = nil
    self:RefreshRuleList()
    self:ShowStateVarEditor(index)
end

function RuleBuilder:DeleteStateVar(index)
    if not _editingData or not _isCustomized then return end
    -- Capture varName before removing the def
    local varName = (_editingData.stateVarDefs[index] or {}).name
    table.remove(_editingData.stateVarDefs, index)
    if varName then
        -- Remove all triggers for the deleted var
        local triggers = _editingData.triggers or {}
        for i = #triggers, 1, -1 do
            if triggers[i].varName == varName then
                table.remove(triggers, i)
            end
        end
        -- Remove all condition references in rules
        for _, rule in ipairs(_editingData.rules or {}) do
            rule.condition = RemoveConditionType(rule.condition, varName)
        end
        -- Remove guard references in remaining triggers
        for _, trig in ipairs(_editingData.triggers or {}) do
            if trig.guard and trig.guard.type == varName then
                trig.guard = nil
            end
        end
    end
    if _selectedVarIndex == index then
        _selectedVarIndex = nil
        self:ClearRightPanel()
    elseif _selectedVarIndex and _selectedVarIndex > index then
        _selectedVarIndex = _selectedVarIndex - 1
    end
    self:RefreshRuleList()
end

function RuleBuilder:MoveRule(index, direction)
    if not _editingData or not _isCustomized then return end
    local rules = _editingData.rules
    local newIndex = index + direction
    if newIndex < 1 or newIndex > #rules then return end
    rules[index], rules[newIndex] = rules[newIndex], rules[index]
    _selectedIndex = newIndex
    self:RefreshRuleList()
    -- Update row click handlers for swapped indices
    if _ruleRows[index] then
        _ruleRows[index]:SetScript("OnClick", function() RuleBuilder:SelectRule(index) end)
    end
    if _ruleRows[newIndex] then
        _ruleRows[newIndex]:SetScript("OnClick", function() RuleBuilder:SelectRule(newIndex) end)
    end
end

function RuleBuilder:DeleteRule(index)
    if not _editingData or not _isCustomized then return end
    table.remove(_editingData.rules, index)
    if _selectedIndex == index then
        _selectedIndex = nil
        self:ClearRightPanel()
    elseif _selectedIndex and _selectedIndex > index then
        _selectedIndex = _selectedIndex - 1
    end
    self:RefreshRuleList()
end

function RuleBuilder:OnAddRule()
    if not _editingData or not _isCustomized then return end
    local newRule = {
        type = "PIN",
        spellID = nil,
        reason = "",
        condition = nil,
    }
    table.insert(_editingData.rules, newRule)
    _selectedIndex = #_editingData.rules
    self:RefreshRuleList()
    self:ShowRuleEditor(_selectedIndex)
end

function RuleBuilder:OnAddStateVar()
    if not _editingData or not _isCustomized then return end
    local newVar = {
        name    = "var" .. (#_editingData.stateVarDefs + 1),
        label   = "New Variable",
        varType = "boolean",
        default = false,
    }
    table.insert(_editingData.stateVarDefs, newVar)
    _selectedVarIndex = #_editingData.stateVarDefs
    _selectedIndex = nil
    self:RefreshRuleList()
    self:ShowStateVarEditor(_selectedVarIndex)
end

------------------------------------------------------------------------
-- Right Panel: Rule Editor with Condition Builder
------------------------------------------------------------------------

local function ClearEditorFrames()
    for _, frame in ipairs(_editorFrames) do
        frame:Hide()
        frame:SetParent(nil)
    end
    wipe(_editorFrames)
end

local function TrackFrame(frame)
    _editorFrames[#_editorFrames + 1] = frame
    return frame
end

------------------------------------------------------------------------
-- Condition Node Rendering
------------------------------------------------------------------------

local function CreateNodeDeleteButton(parent, onDelete)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(14, 14)
    btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetColorTexture(0.8, 0.2, 0.2, 0.6)
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER")
    label:SetText("x")
    btn:SetScript("OnClick", onDelete)
    btn:SetScript("OnEnter", function() tex:SetColorTexture(1.0, 0.3, 0.3, 0.8) end)
    btn:SetScript("OnLeave", function() tex:SetColorTexture(0.8, 0.2, 0.2, 0.6) end)
    return btn
end

local function CreateBadge(parent, text, r, g, b)
    local badge = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    badge:SetText("|cff" .. string.format("%02x%02x%02x", r * 255, g * 255, b * 255) .. text .. "|r")
    return badge
end

local function CreateConditionTypeDropdown(parent, condition, profileId, onChange)
    local ddName = NextDropdownName("TrueShotRBCondType_")
    local dd = CreateFrame("Frame", ddName, parent, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(dd, 130)

    local schemas = CustomProfile.GetConditionSchemasForProfile(profileId)

    UIDropDownMenu_Initialize(dd, function()
        for _, schema in ipairs(schemas) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = schema.label
            info.checked = (condition.type == schema.id)
            info.func = function()
                condition.type = schema.id
                -- Apply defaults from new schema
                for _, param in ipairs(schema.params) do
                    if condition[param.field] == nil and param.default ~= nil then
                        condition[param.field] = param.default
                    end
                end
                UIDropDownMenu_SetText(dd, schema.label)
                if onChange then onChange() end
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    -- Set initial text
    local currentSchema
    for _, s in ipairs(schemas) do
        if s.id == condition.type then currentSchema = s break end
    end
    UIDropDownMenu_SetText(dd, currentSchema and currentSchema.label or condition.type or "(select)")

    return dd
end

local function CreateParamInputs(parent, condition, schema, anchorTo, onChange)
    if not schema or not schema.params then return anchorTo end

    local lastAnchor = anchorTo
    for _, param in ipairs(schema.params) do
        if param.fieldType == "spell" then
            -- Spell dropdown from rotational spells
            local ddName = NextDropdownName("TrueShotRBParam_")
            local dd = CreateFrame("Frame", ddName, parent, "UIDropDownMenuTemplate")
            TrackFrame(dd)
            dd:SetPoint("TOPLEFT", lastAnchor, "BOTTOMLEFT", 0, -2)
            UIDropDownMenu_SetWidth(dd, 130)

            local spellList = GetRotationalSpellList()
            UIDropDownMenu_Initialize(dd, function()
                for _, sid in ipairs(spellList) do
                    local sIcon, sName = GetSpellDisplay(sid)
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = sName
                    info.icon = sIcon
                    info.checked = (condition[param.field] == sid)
                    info.func = function()
                        condition[param.field] = sid
                        UIDropDownMenu_SetText(dd, sName)
                        if onChange then onChange() end
                    end
                    UIDropDownMenu_AddButton(info)
                end
            end)

            local _, curName = GetSpellDisplay(condition[param.field])
            UIDropDownMenu_SetText(dd, curName)
            lastAnchor = dd

        elseif param.fieldType == "operator" then
            local ddName = NextDropdownName("TrueShotRBOp_")
            local dd = CreateFrame("Frame", ddName, parent, "UIDropDownMenuTemplate")
            TrackFrame(dd)
            dd:SetPoint("TOPLEFT", lastAnchor, "BOTTOMLEFT", 0, -2)
            UIDropDownMenu_SetWidth(dd, 60)

            local choices = param.choices or { ">=", ">", "==", "<", "<=" }
            UIDropDownMenu_Initialize(dd, function()
                for _, op in ipairs(choices) do
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = op
                    info.checked = (condition[param.field] == op)
                    info.func = function()
                        condition[param.field] = op
                        UIDropDownMenu_SetText(dd, op)
                        if onChange then onChange() end
                    end
                    UIDropDownMenu_AddButton(info)
                end
            end)
            UIDropDownMenu_SetText(dd, condition[param.field] or choices[1] or "")
            lastAnchor = dd

        elseif param.fieldType == "number" then
            local container = CreateFrame("Frame", nil, parent)
            TrackFrame(container)
            container:SetSize(200, 22)
            container:SetPoint("TOPLEFT", lastAnchor, "BOTTOMLEFT", 0, -4)

            local label = container:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            label:SetPoint("LEFT", container, "LEFT", 0, 0)
            label:SetText((param.label or param.field) .. ":")

            local editBox = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
            editBox:SetSize(60, 20)
            editBox:SetPoint("LEFT", label, "RIGHT", 6, 0)
            editBox:SetAutoFocus(false)
            editBox:SetNumeric(false)
            editBox:SetText(tostring(condition[param.field] or param.default or ""))

            local function ApplyValue()
                local val = tonumber(editBox:GetText())
                if val then
                    condition[param.field] = val
                    if onChange then onChange() end
                end
            end
            editBox:SetScript("OnEnterPressed", function(self)
                ApplyValue()
                self:ClearFocus()
            end)
            editBox:SetScript("OnEditFocusLost", ApplyValue)

            lastAnchor = container
        end
    end
    return lastAnchor
end

------------------------------------------------------------------------
-- Recursive Condition Tree Renderer
------------------------------------------------------------------------

-- RenderConditionTree returns the last anchored frame and total height used
-- parent: the scroll child or container frame
-- condition: the condition table node
-- depth: current nesting depth (0-based)
-- path: string path for unique naming (e.g., "root_L_R")
-- onChange: callback when condition changes (triggers re-render)
-- getConditionRef: function() returns the parent table and key holding this condition
--                  so we can replace/delete it

RenderConditionTree = function(parent, condition, depth, path, onChange, anchorFrame, anchorOffset)
    local profileId = GetProfileId()

    if not condition then
        -- No condition set: show "Set condition" and "Preset" buttons
        local container = CreateFrame("Frame", nil, parent)
        TrackFrame(container)
        container:SetSize(400, 26)
        if anchorFrame then
            container:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, anchorOffset or -4)
        else
            container:SetPoint("TOPLEFT", parent, "TOPLEFT", depth * INDENT_PER_DEPTH, 0)
        end

        local addBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
        addBtn:SetSize(110, 20)
        addBtn:SetPoint("LEFT", container, "LEFT", 0, 0)
        addBtn:SetText("+ Set Condition")
        addBtn:SetScript("OnClick", function()
            -- Default: create a burst_mode primitive
            return onChange({ type = "burst_mode" })
        end)

        local presetBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
        presetBtn:SetSize(90, 20)
        presetBtn:SetPoint("LEFT", addBtn, "RIGHT", 4, 0)
        presetBtn:SetText("+ Preset...")
        presetBtn:SetScript("OnClick", function()
            local menuFrame = CreateFrame("Frame", NextDropdownName("TrueShotRBPreset_"), UIParent, "UIDropDownMenuTemplate")
            UIDropDownMenu_Initialize(menuFrame, function()
                for _, preset in ipairs(CONDITION_PRESETS) do
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = preset.label
                    info.notCheckable = true
                    info.func = function()
                        onChange(DeepCopy(preset.template))
                    end
                    UIDropDownMenu_AddButton(info)
                end
            end, "MENU")
            ToggleDropDownMenu(1, nil, menuFrame, "cursor", 0, 0)
        end)

        return container, 26
    end

    local nodeType = condition.type

    ---------- AND / OR combinator ----------
    if nodeType == "and" or nodeType == "or" then
        local container = CreateFrame("Frame", nil, parent)
        TrackFrame(container)
        container:SetSize(400, 22)
        if anchorFrame then
            container:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, anchorOffset or -4)
        else
            container:SetPoint("TOPLEFT", parent, "TOPLEFT", depth * INDENT_PER_DEPTH, 0)
        end

        -- Combinator badge
        local badgeColor = nodeType == "and" and { 0.2, 0.7, 0.7 } or { 0.3, 0.5, 0.9 }
        local badge = CreateBadge(container, string.upper(nodeType), badgeColor[1], badgeColor[2], badgeColor[3])
        badge:SetPoint("LEFT", container, "LEFT", 0, 0)

        -- Toggle AND/OR dropdown
        local ddName = NextDropdownName("TrueShotRBComb_")
        local dd = CreateFrame("Frame", ddName, container, "UIDropDownMenuTemplate")
        dd:SetPoint("LEFT", badge, "RIGHT", 0, 0)
        UIDropDownMenu_SetWidth(dd, 60)
        UIDropDownMenu_Initialize(dd, function()
            for _, op in ipairs({ "and", "or" }) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = string.upper(op)
                info.checked = (condition.type == op)
                info.func = function()
                    condition.type = op
                    UIDropDownMenu_SetText(dd, string.upper(op))
                    onChange(nil) -- re-render, no replacement
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
        UIDropDownMenu_SetText(dd, string.upper(nodeType))

        -- Delete button
        CreateNodeDeleteButton(container, function()
            onChange(nil, true) -- signal deletion
        end)

        -- Render left child
        local totalHeight = 22
        local leftContainer = CreateFrame("Frame", nil, parent)
        TrackFrame(leftContainer)
        leftContainer:SetSize(400 - INDENT_PER_DEPTH, 20)
        leftContainer:SetPoint("TOPLEFT", container, "BOTTOMLEFT", INDENT_PER_DEPTH, -2)

        -- Vertical connecting line
        local vline = leftContainer:CreateTexture(nil, "BACKGROUND")
        vline:SetWidth(1)
        vline:SetPoint("TOPLEFT", leftContainer, "TOPLEFT", -6, 2)
        vline:SetColorTexture(0.4, 0.4, 0.4, 0.6)

        local leftLabel = leftContainer:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        leftLabel:SetPoint("TOPLEFT", leftContainer, "TOPLEFT", 0, 0)
        leftLabel:SetText("|cff888888L:|r")

        local lastLeft, leftH = RenderConditionTree(parent, condition.left, depth + 1, path .. "_L", function(replacement, isDelete)
            if isDelete then
                -- Replace combinator with right child
                onChange(condition.right)
            elseif replacement then
                condition.left = replacement
                onChange(nil) -- re-render
            else
                onChange(nil) -- re-render
            end
        end, leftLabel, -2)
        totalHeight = totalHeight + leftH + 4

        -- Render right child
        local rightLabelFrame = CreateFrame("Frame", nil, parent)
        TrackFrame(rightLabelFrame)
        rightLabelFrame:SetSize(20, 14)
        rightLabelFrame:SetPoint("TOPLEFT", lastLeft, "BOTTOMLEFT", 0, -4)
        local rightLabel = rightLabelFrame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        rightLabel:SetPoint("LEFT", rightLabelFrame, "LEFT", 0, 0)
        rightLabel:SetText("|cff888888R:|r")

        local lastRight, rightH = RenderConditionTree(parent, condition.right, depth + 1, path .. "_R", function(replacement, isDelete)
            if isDelete then
                -- Replace combinator with left child
                onChange(condition.left)
            elseif replacement then
                condition.right = replacement
                onChange(nil)
            else
                onChange(nil)
            end
        end, rightLabelFrame, -2)
        totalHeight = totalHeight + rightH + 6

        -- Extend vertical line
        vline:SetPoint("BOTTOMLEFT", lastRight, "BOTTOMLEFT", -6 - INDENT_PER_DEPTH, 0)

        return lastRight, totalHeight

    ---------- NOT combinator ----------
    elseif nodeType == "not" then
        local container = CreateFrame("Frame", nil, parent)
        TrackFrame(container)
        container:SetSize(400, 22)
        if anchorFrame then
            container:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, anchorOffset or -4)
        else
            container:SetPoint("TOPLEFT", parent, "TOPLEFT", depth * INDENT_PER_DEPTH, 0)
        end

        local badge = CreateBadge(container, "NOT", 0.9, 0.3, 0.3)
        badge:SetPoint("LEFT", container, "LEFT", 0, 0)

        CreateNodeDeleteButton(container, function()
            -- When deleting NOT, unwrap to inner
            onChange(condition.inner)
        end)

        local totalHeight = 22

        local innerContainer = CreateFrame("Frame", nil, parent)
        TrackFrame(innerContainer)
        innerContainer:SetSize(400 - INDENT_PER_DEPTH, 20)
        innerContainer:SetPoint("TOPLEFT", container, "BOTTOMLEFT", INDENT_PER_DEPTH, -2)

        local lastInner, innerH = RenderConditionTree(parent, condition.inner, depth + 1, path .. "_N", function(replacement, isDelete)
            if isDelete then
                onChange(nil, true) -- delete the NOT too
            elseif replacement then
                condition.inner = replacement
                onChange(nil)
            else
                onChange(nil)
            end
        end, innerContainer, 0)
        totalHeight = totalHeight + innerH + 4

        return lastInner, totalHeight

    ---------- Primitive condition ----------
    else
        local container = CreateFrame("Frame", nil, parent)
        TrackFrame(container)
        container:SetSize(400, 26)
        if anchorFrame then
            container:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, anchorOffset or -4)
        else
            container:SetPoint("TOPLEFT", parent, "TOPLEFT", depth * INDENT_PER_DEPTH, 0)
        end

        -- Condition type dropdown
        local typeDd = CreateConditionTypeDropdown(container, condition, profileId, function()
            onChange(nil) -- re-render to update param inputs
        end)
        TrackFrame(typeDd)
        typeDd:SetPoint("TOPLEFT", container, "TOPLEFT", -16, 0)

        -- Delete button
        CreateNodeDeleteButton(container, function()
            onChange(nil, true) -- delete this node
        end)

        -- Parameter inputs based on schema
        local schema
        local schemas = CustomProfile.GetConditionSchemasForProfile(profileId)
        for _, s in ipairs(schemas) do
            if s.id == condition.type then schema = s break end
        end

        local lastParam = CreateParamInputs(container, condition, schema, typeDd, function()
            onChange(nil)
        end)

        -- Wrap buttons (AND, OR, NOT) - only if under max depth
        local wrapRow = CreateFrame("Frame", nil, parent)
        TrackFrame(wrapRow)
        wrapRow:SetSize(300, 20)
        wrapRow:SetPoint("TOPLEFT", lastParam, "BOTTOMLEFT", 0, -4)

        if depth < MAX_CONDITION_DEPTH then
            local wrapAndBtn = CreateFrame("Button", nil, wrapRow, "UIPanelButtonTemplate")
            wrapAndBtn:SetSize(55, 18)
            wrapAndBtn:SetPoint("LEFT", wrapRow, "LEFT", 0, 0)
            wrapAndBtn:SetText("+ AND")
            wrapAndBtn:SetScript("OnClick", function()
                local wrapped = { type = "and", left = DeepCopy(condition), right = { type = "burst_mode" } }
                onChange(wrapped)
            end)

            local wrapOrBtn = CreateFrame("Button", nil, wrapRow, "UIPanelButtonTemplate")
            wrapOrBtn:SetSize(50, 18)
            wrapOrBtn:SetPoint("LEFT", wrapAndBtn, "RIGHT", 4, 0)
            wrapOrBtn:SetText("+ OR")
            wrapOrBtn:SetScript("OnClick", function()
                local wrapped = { type = "or", left = DeepCopy(condition), right = { type = "burst_mode" } }
                onChange(wrapped)
            end)

            local wrapNotBtn = CreateFrame("Button", nil, wrapRow, "UIPanelButtonTemplate")
            wrapNotBtn:SetSize(55, 18)
            wrapNotBtn:SetPoint("LEFT", wrapOrBtn, "RIGHT", 4, 0)
            wrapNotBtn:SetText("+ NOT")
            wrapNotBtn:SetScript("OnClick", function()
                local wrapped = { type = "not", inner = DeepCopy(condition) }
                onChange(wrapped)
            end)

            local presetBtn = CreateFrame("Button", nil, wrapRow, "UIPanelButtonTemplate")
            presetBtn:SetSize(75, 18)
            presetBtn:SetPoint("LEFT", wrapNotBtn, "RIGHT", 4, 0)
            presetBtn:SetText("Preset...")
            presetBtn:SetScript("OnClick", function()
                local menuFrame = CreateFrame("Frame", NextDropdownName("TrueShotRBPresetP_"), UIParent, "UIDropDownMenuTemplate")
                UIDropDownMenu_Initialize(menuFrame, function()
                    for _, preset in ipairs(CONDITION_PRESETS) do
                        local info = UIDropDownMenu_CreateInfo()
                        info.text = preset.label
                        info.notCheckable = true
                        info.func = function()
                            -- Wrap current condition with AND + preset
                            local wrapped = { type = "and", left = DeepCopy(condition), right = DeepCopy(preset.template) }
                            onChange(wrapped)
                        end
                        UIDropDownMenu_AddButton(info)
                    end
                end, "MENU")
                ToggleDropDownMenu(1, nil, menuFrame, "cursor", 0, 0)
            end)
        else
            local depthWarn = wrapRow:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
            depthWarn:SetPoint("LEFT", wrapRow, "LEFT", 0, 0)
            depthWarn:SetText("|cff888888Max nesting depth reached|r")
        end

        -- Estimate height (dropdown ~26, params variable, wrap row ~20)
        local paramCount = schema and #schema.params or 0
        local estHeight = 26 + (paramCount * 28) + 24
        return wrapRow, estHeight
    end
end

------------------------------------------------------------------------
-- ShowRuleEditor - builds the full right panel for a selected rule
------------------------------------------------------------------------

function RuleBuilder:ShowRuleEditor(index)
    self:ClearRightPanel()
    ClearEditorFrames()

    if not _rightPanel or not _editingData or not _isCustomized then return end
    local rules = _editingData.rules
    local rule = rules and rules[index]
    if not rule then return end

    local profileId = GetProfileId()
    local rightWidth = math.max(_rightPanel:GetWidth(), FRAME_WIDTH - LEFT_PANEL_WIDTH - 26)

    -- Scroll frame for right panel content
    local scrollFrame = CreateFrame("ScrollFrame", NextDropdownName("TrueShotRBRScroll_"), _rightPanel, "UIPanelScrollFrameTemplate")
    TrackFrame(scrollFrame)
    scrollFrame:SetPoint("TOPLEFT", _rightPanel, "TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", _rightPanel, "BOTTOMRIGHT", -22, 0)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(rightWidth - 30)
    scrollChild:SetHeight(1) -- will be updated
    scrollFrame:SetScrollChild(scrollChild)

    -- Re-render helper (rebuilds the entire right panel)
    local function Rerender()
        RuleBuilder:ShowRuleEditor(index)
    end

    ----------------------------------------------------------------
    -- 1. Rule header
    ----------------------------------------------------------------
    local headerLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    headerLabel:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 4, 0)
    headerLabel:SetText("Rule #" .. index)

    ----------------------------------------------------------------
    -- 2. Rule Type Dropdown
    ----------------------------------------------------------------
    local typeLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    typeLabel:SetPoint("TOPLEFT", headerLabel, "BOTTOMLEFT", 0, -10)
    typeLabel:SetText("Type:")

    local typeDd = CreateFrame("Frame", NextDropdownName("TrueShotRBType_"), scrollChild, "UIDropDownMenuTemplate")
    TrackFrame(typeDd)
    typeDd:SetPoint("TOPLEFT", typeLabel, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(typeDd, 180)

    UIDropDownMenu_Initialize(typeDd, function()
        for _, rtype in ipairs(TYPE_ORDER) do
            local tc = TYPE_COLORS[rtype]
            local info = UIDropDownMenu_CreateInfo()
            info.text = rtype
            if tc then
                info.colorCode = "|cff" .. string.format("%02x%02x%02x", tc.r * 255, tc.g * 255, tc.b * 255)
            end
            info.checked = (rule.type == rtype)
            info.func = function()
                rule.type = rtype
                UIDropDownMenu_SetText(typeDd, rtype)
                RuleBuilder:RefreshRuleList()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(typeDd, rule.type or "PIN")

    ----------------------------------------------------------------
    -- 3. Spell Selector
    ----------------------------------------------------------------
    local spellLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    spellLabel:SetPoint("TOPLEFT", typeDd, "BOTTOMLEFT", 16, -8)
    spellLabel:SetText("Spell:")

    local spellDd = CreateFrame("Frame", NextDropdownName("TrueShotRBSpell_"), scrollChild, "UIDropDownMenuTemplate")
    TrackFrame(spellDd)
    spellDd:SetPoint("TOPLEFT", spellLabel, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(spellDd, 180)

    local spellList = GetRotationalSpellList()
    UIDropDownMenu_Initialize(spellDd, function()
        for _, sid in ipairs(spellList) do
            local sIcon, sName = GetSpellDisplay(sid)
            local info = UIDropDownMenu_CreateInfo()
            info.text = sName
            info.icon = sIcon
            info.checked = (rule.spellID == sid)
            info.func = function()
                rule.spellID = sid
                UIDropDownMenu_SetText(spellDd, sName)
                RuleBuilder:RefreshRuleList()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    local _, curSpellName = GetSpellDisplay(rule.spellID)
    UIDropDownMenu_SetText(spellDd, curSpellName)

    -- Manual spellID input
    local manualRow = CreateFrame("Frame", nil, scrollChild)
    TrackFrame(manualRow)
    manualRow:SetSize(300, 22)
    manualRow:SetPoint("TOPLEFT", spellDd, "BOTTOMLEFT", 16, -4)

    local manualLabel = manualRow:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    manualLabel:SetPoint("LEFT", manualRow, "LEFT", 0, 0)
    manualLabel:SetText("or SpellID:")

    local manualEdit = CreateFrame("EditBox", nil, manualRow, "InputBoxTemplate")
    manualEdit:SetSize(80, 20)
    manualEdit:SetPoint("LEFT", manualLabel, "RIGHT", 6, 0)
    manualEdit:SetAutoFocus(false)
    manualEdit:SetText(rule.spellID and tostring(rule.spellID) or "")

    local spellWarning = manualRow:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    spellWarning:SetPoint("LEFT", manualEdit, "RIGHT", 8, 0)
    spellWarning:SetText("")

    local function ApplyManualSpell()
        local val = tonumber(manualEdit:GetText())
        if val and val > 0 then
            rule.spellID = val
            local _, name = GetSpellDisplay(val)
            UIDropDownMenu_SetText(spellDd, name)
            -- Check if spell is known
            if IsPlayerSpell and not IsPlayerSpell(val) then
                spellWarning:SetText("|cffffff00Not known|r")
            else
                spellWarning:SetText("")
            end
            RuleBuilder:RefreshRuleList()
        end
    end
    manualEdit:SetScript("OnEnterPressed", function(self)
        ApplyManualSpell()
        self:ClearFocus()
    end)
    manualEdit:SetScript("OnEditFocusLost", ApplyManualSpell)

    -- Show warning on initial load
    if rule.spellID and IsPlayerSpell and not IsPlayerSpell(rule.spellID) then
        spellWarning:SetText("|cffffff00Not known|r")
    end

    ----------------------------------------------------------------
    -- 4. Reason Text
    ----------------------------------------------------------------
    local reasonLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    reasonLabel:SetPoint("TOPLEFT", manualRow, "BOTTOMLEFT", 0, -10)
    reasonLabel:SetText("Reason:")

    local reasonEdit = CreateFrame("EditBox", nil, scrollChild, "InputBoxTemplate")
    TrackFrame(reasonEdit)
    reasonEdit:SetSize(220, 20)
    reasonEdit:SetPoint("TOPLEFT", reasonLabel, "BOTTOMLEFT", 0, -2)
    reasonEdit:SetAutoFocus(false)
    reasonEdit:SetText(rule.reason or "")

    local function ApplyReason()
        local text = reasonEdit:GetText() or ""
        rule.reason = (text ~= "") and text or nil
        RuleBuilder:RefreshRuleList()
    end
    reasonEdit:SetScript("OnEnterPressed", function(self)
        ApplyReason()
        self:ClearFocus()
    end)
    reasonEdit:SetScript("OnEditFocusLost", ApplyReason)

    ----------------------------------------------------------------
    -- 5. Condition Builder
    ----------------------------------------------------------------
    local condHeader = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    condHeader:SetPoint("TOPLEFT", reasonEdit, "BOTTOMLEFT", 0, -16)
    condHeader:SetText("Condition")

    local condDivider = scrollChild:CreateTexture(nil, "ARTWORK")
    condDivider:SetHeight(1)
    condDivider:SetPoint("TOPLEFT", condHeader, "BOTTOMLEFT", 0, -4)
    condDivider:SetPoint("RIGHT", scrollChild, "RIGHT", -8, 0)
    condDivider:SetColorTexture(0.3, 0.3, 0.3, 0.8)

    local condArea = CreateFrame("Frame", nil, scrollChild)
    TrackFrame(condArea)
    condArea:SetPoint("TOPLEFT", condDivider, "BOTTOMLEFT", 0, -6)
    condArea:SetPoint("RIGHT", scrollChild, "RIGHT", -4, 0)
    condArea:SetHeight(400)

    local lastFrame, treeHeight = RenderConditionTree(
        condArea,
        rule.condition,
        0,
        "root",
        function(replacement, isDelete)
            if isDelete then
                rule.condition = nil
            elseif replacement then
                rule.condition = replacement
            end
            -- Re-render the editor
            Rerender()
        end,
        nil,
        0
    )

    -- Update condition area height
    condArea:SetHeight(math.max(treeHeight or 30, 30))

    ----------------------------------------------------------------
    -- Update scroll child height: rough estimate, then measure post-layout
    ----------------------------------------------------------------
    local totalHeight = 24 + 40 + 40 + 26 + 40 + 30 + (treeHeight or 30) + 60
    scrollChild:SetHeight(math.max(totalHeight, 200))
    -- Post-layout measurement for accurate scroll height
    C_Timer.After(0, function()
        if not scrollChild:GetParent() then return end
        local top = scrollChild:GetTop()
        local bottom = condArea:GetBottom()
        if top and bottom then
            scrollChild:SetHeight(math.max(top - bottom + 40, 200))
        end
    end)
end

------------------------------------------------------------------------
-- ShowStateVarEditor - right panel for a selected state variable
------------------------------------------------------------------------

function RuleBuilder:ShowStateVarEditor(varIndex)
    self:ClearRightPanel()
    ClearEditorFrames()

    if not _rightPanel or not _editingData or not _isCustomized then return end
    local defs = _editingData.stateVarDefs
    local def = defs and defs[varIndex]
    if not def then return end

    local rightWidth = math.max(_rightPanel:GetWidth(), FRAME_WIDTH - LEFT_PANEL_WIDTH - 26)

    -- Scroll container
    local scrollFrame = CreateFrame("ScrollFrame", NextDropdownName("TrueShotRBVarScroll_"), _rightPanel, "UIPanelScrollFrameTemplate")
    TrackFrame(scrollFrame)
    scrollFrame:SetPoint("TOPLEFT", _rightPanel, "TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", _rightPanel, "BOTTOMRIGHT", -22, 0)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(rightWidth - 30)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    local function Rerender()
        RuleBuilder:ShowStateVarEditor(varIndex)
    end

    ----------------------------------------------------------------
    -- Section header
    ----------------------------------------------------------------
    local hdr = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    hdr:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 4, 0)
    hdr:SetText("State Variable #" .. varIndex)

    ----------------------------------------------------------------
    -- Name (identifier)
    ----------------------------------------------------------------
    local nameLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    nameLabel:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -10)
    nameLabel:SetText("Name (ID):")

    local nameEdit = CreateFrame("EditBox", nil, scrollChild, "InputBoxTemplate")
    TrackFrame(nameEdit)
    nameEdit:SetSize(180, 20)
    nameEdit:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -2)
    nameEdit:SetAutoFocus(false)
    nameEdit:SetText(def.name or "")

    -- Lock name if any trigger or condition references it (prevents wiring breakage)
    local hasReferences = false
    if _editingData then
        -- Check triggers
        for _, trig in ipairs(_editingData.triggers or {}) do
            if trig.varName == def.name then hasReferences = true; break end
            if trig.guard and ConditionReferencesType(trig.guard, def.name) then hasReferences = true; break end
        end
        -- Check rule conditions
        if not hasReferences then
            for _, rule in ipairs(_editingData.rules or {}) do
                if ConditionReferencesType(rule.condition, def.name) then hasReferences = true; break end
            end
        end
    end

    local nameHint = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    nameHint:SetPoint("TOPLEFT", nameEdit, "BOTTOMLEFT", 0, -2)

    if hasReferences then
        nameEdit:Disable()
        nameEdit:SetTextColor(0.5, 0.5, 0.5)
        nameHint:SetText("|cff888888Locked (referenced by triggers)|r")
    else
        nameHint:SetText("|cff888888Alphanumeric + underscore, used as condition ID|r")
        local function ApplyName()
            local raw = nameEdit:GetText() or ""
            -- Strip invalid chars: only a-z A-Z 0-9 _
            local clean = raw:gsub("[^%w_]", "")
            if clean == "" then clean = "var" .. varIndex end
            def.name = clean
            nameEdit:SetText(clean)
            RuleBuilder:RefreshRuleList()
        end
        nameEdit:SetScript("OnEnterPressed", function(self) ApplyName(); self:ClearFocus() end)
        nameEdit:SetScript("OnEditFocusLost", ApplyName)
    end

    ----------------------------------------------------------------
    -- Label (display name)
    ----------------------------------------------------------------
    local labelLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    labelLabel:SetPoint("TOPLEFT", nameHint, "BOTTOMLEFT", 0, -10)
    labelLabel:SetText("Label:")

    local labelEdit = CreateFrame("EditBox", nil, scrollChild, "InputBoxTemplate")
    TrackFrame(labelEdit)
    labelEdit:SetSize(220, 20)
    labelEdit:SetPoint("TOPLEFT", labelLabel, "BOTTOMLEFT", 0, -2)
    labelEdit:SetAutoFocus(false)
    labelEdit:SetText(def.label or "")

    local function ApplyLabel()
        local text = labelEdit:GetText() or ""
        def.label = (text ~= "") and text or def.name
        RuleBuilder:RefreshRuleList()
    end
    labelEdit:SetScript("OnEnterPressed", function(self) ApplyLabel(); self:ClearFocus() end)
    labelEdit:SetScript("OnEditFocusLost", ApplyLabel)

    ----------------------------------------------------------------
    -- Type dropdown
    ----------------------------------------------------------------
    local typeLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    typeLabel:SetPoint("TOPLEFT", labelEdit, "BOTTOMLEFT", 0, -10)
    typeLabel:SetText("Type:")

    local VAR_TYPES = { "boolean", "number", "timestamp" }
    local typeDd = CreateFrame("Frame", NextDropdownName("TrueShotRBVarType_"), scrollChild, "UIDropDownMenuTemplate")
    TrackFrame(typeDd)
    typeDd:SetPoint("TOPLEFT", typeLabel, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(typeDd, 120)

    UIDropDownMenu_Initialize(typeDd, function()
        for _, vt in ipairs(VAR_TYPES) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = vt
            info.checked = (def.varType == vt)
            info.func = function()
                def.varType = vt
                -- Reset default to a sane value for the new type
                if vt == "boolean" then
                    def.default = false
                elseif vt == "number" then
                    def.default = 0
                else
                    def.default = 0
                end
                UIDropDownMenu_SetText(typeDd, vt)
                Rerender()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(typeDd, def.varType or "boolean")

    ----------------------------------------------------------------
    -- Default value (adapts to type)
    ----------------------------------------------------------------
    local defLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    defLabel:SetPoint("TOPLEFT", typeDd, "BOTTOMLEFT", 16, -8)
    defLabel:SetText("Default:")

    local lastAnchorAfterDefault = defLabel

    if def.varType == "boolean" then
        local defChk = CreateFrame("CheckButton", nil, scrollChild, "UICheckButtonTemplate")
        TrackFrame(defChk)
        defChk:SetSize(22, 22)
        defChk:SetPoint("TOPLEFT", defLabel, "BOTTOMLEFT", 0, -2)
        defChk:SetChecked(def.default == true)
        defChk:SetScript("OnClick", function(self)
            def.default = self:GetChecked()
        end)
        lastAnchorAfterDefault = defChk
    else
        local defEdit = CreateFrame("EditBox", nil, scrollChild, "InputBoxTemplate")
        TrackFrame(defEdit)
        defEdit:SetSize(80, 20)
        defEdit:SetPoint("TOPLEFT", defLabel, "BOTTOMLEFT", 0, -2)
        defEdit:SetAutoFocus(false)
        defEdit:SetNumeric(false)
        defEdit:SetText(tostring(def.default or 0))
        local function ApplyDefault()
            local val = tonumber(defEdit:GetText())
            if val then def.default = val end
        end
        defEdit:SetScript("OnEnterPressed", function(self) ApplyDefault(); self:ClearFocus() end)
        defEdit:SetScript("OnEditFocusLost", ApplyDefault)
        lastAnchorAfterDefault = defEdit
    end

    ----------------------------------------------------------------
    -- Divider + Triggers section header
    ----------------------------------------------------------------
    local trigDivider = scrollChild:CreateTexture(nil, "ARTWORK")
    trigDivider:SetHeight(1)
    trigDivider:SetPoint("TOPLEFT", lastAnchorAfterDefault, "BOTTOMLEFT", 0, -12)
    trigDivider:SetPoint("RIGHT", scrollChild, "RIGHT", -8, 0)
    trigDivider:SetColorTexture(0.3, 0.3, 0.3, 0.8)

    local trigHeader = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    trigHeader:SetPoint("TOPLEFT", trigDivider, "BOTTOMLEFT", 0, -6)
    trigHeader:SetText("Triggers")

    ----------------------------------------------------------------
    -- Trigger list for this var
    ----------------------------------------------------------------
    local triggers = _editingData.triggers or {}
    local myTriggers = {}
    local myTriggerOrigIdx = {}
    for i, t in ipairs(triggers) do
        if t.varName == def.name then
            local n = #myTriggers + 1
            myTriggers[n] = t
            myTriggerOrigIdx[n] = i
        end
    end

    local TRIG_ROW_H = 26
    local lastTrigAnchor = trigHeader
    local lastTrigOffset = -8

    for ti, trig in ipairs(myTriggers) do
        local origIdx = myTriggerOrigIdx[ti]

        local trigRow = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
        TrackFrame(trigRow)
        trigRow:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        trigRow:SetBackdropColor(0.1, 0.1, 0.15, 0.8)
        trigRow:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
        trigRow:SetSize(rightWidth - 50, TRIG_ROW_H)
        trigRow:SetPoint("TOPLEFT", lastTrigAnchor, "BOTTOMLEFT", 0, lastTrigOffset)

        -- Spell icon
        local sIcon, sName = GetSpellDisplay(trig.spellID)
        local iconTex = trigRow:CreateTexture(nil, "ARTWORK")
        iconTex:SetSize(18, 18)
        iconTex:SetPoint("LEFT", trigRow, "LEFT", 4, 0)
        iconTex:SetTexture(sIcon)

        -- Summary text
        local valStr
        if def.varType == "boolean" then
            valStr = trig.value and "true" or "false"
        elseif def.varType == "timestamp" then
            valStr = trig.setNow and "GetTime()" or tostring(trig.value or 0)
        else
            valStr = tostring(trig.value or 0)
        end
        local resetStr = trig.resetAfter and (" | reset " .. trig.resetAfter .. "s") or ""
        local summaryText = trigRow:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        summaryText:SetPoint("LEFT", iconTex, "RIGHT", 4, 0)
        summaryText:SetPoint("RIGHT", trigRow, "RIGHT", -36, 0)
        summaryText:SetJustifyH("LEFT")
        summaryText:SetWordWrap(false)
        summaryText:SetText(sName .. " -> " .. valStr .. resetStr)

        -- Edit button
        local editBtn = CreateFrame("Button", nil, trigRow, "UIPanelButtonTemplate")
        editBtn:SetSize(30, 18)
        editBtn:SetPoint("RIGHT", trigRow, "RIGHT", -2, 0)
        editBtn:SetText("Edit")
        editBtn:SetScript("OnClick", function()
            RuleBuilder:ShowTriggerEditor(varIndex, origIdx)
        end)

        lastTrigAnchor = trigRow
        lastTrigOffset = -4
    end

    -- + Add Trigger button
    local addTrigBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
    TrackFrame(addTrigBtn)
    addTrigBtn:SetSize(100, 22)
    addTrigBtn:SetPoint("TOPLEFT", lastTrigAnchor, "BOTTOMLEFT", 0, lastTrigOffset - 2)
    addTrigBtn:SetText("+ Add Trigger")
    addTrigBtn:SetScript("OnClick", function()
        if not _editingData.triggers then _editingData.triggers = {} end
        local newTrig = {
            spellID    = nil,
            varName    = def.name,
            value      = (def.varType == "boolean") and true or 0,
            setNow     = (def.varType == "timestamp"),
            guard      = nil,
            resetAfter = nil,
            resetValue = nil,
        }
        table.insert(_editingData.triggers, newTrig)
        RuleBuilder:ShowTriggerEditor(varIndex, #_editingData.triggers)
    end)

    ----------------------------------------------------------------
    -- Estimate scroll height
    ----------------------------------------------------------------
    local estHeight = 24 + 16 + 26 + 16 + 26 + 50 + 36 + 20 + 30 + (#myTriggers * (TRIG_ROW_H + 4)) + 50
    scrollChild:SetHeight(math.max(estHeight, 300))
    C_Timer.After(0, function()
        if not scrollChild:GetParent() then return end
        local top = scrollChild:GetTop()
        local bottom = addTrigBtn:GetBottom()
        if top and bottom then
            scrollChild:SetHeight(math.max(top - bottom + 30, 300))
        end
    end)
end

------------------------------------------------------------------------
-- ShowTriggerEditor - inline right panel for editing one trigger
------------------------------------------------------------------------

function RuleBuilder:ShowTriggerEditor(varIndex, trigIndex)
    self:ClearRightPanel()
    ClearEditorFrames()

    if not _rightPanel or not _editingData or not _isCustomized then return end
    local def = _editingData.stateVarDefs and _editingData.stateVarDefs[varIndex]
    local trig = _editingData.triggers and _editingData.triggers[trigIndex]
    if not def or not trig then return end

    local rightWidth = math.max(_rightPanel:GetWidth(), FRAME_WIDTH - LEFT_PANEL_WIDTH - 26)
    local profileId = GetProfileId()

    local scrollFrame = CreateFrame("ScrollFrame", NextDropdownName("TrueShotRBTrigScroll_"), _rightPanel, "UIPanelScrollFrameTemplate")
    TrackFrame(scrollFrame)
    scrollFrame:SetPoint("TOPLEFT", _rightPanel, "TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", _rightPanel, "BOTTOMRIGHT", -22, 0)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(rightWidth - 30)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    local function Rerender()
        RuleBuilder:ShowTriggerEditor(varIndex, trigIndex)
    end

    ----------------------------------------------------------------
    -- Header + back link
    ----------------------------------------------------------------
    local hdr = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    hdr:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 4, 0)
    hdr:SetText("Trigger Editor  |cffaaaaaa(var: " .. (def.label or def.name) .. ")|r")

    local backBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
    TrackFrame(backBtn)
    backBtn:SetSize(60, 20)
    backBtn:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -6)
    backBtn:SetText("< Back")
    backBtn:SetScript("OnClick", function()
        RuleBuilder:ShowStateVarEditor(varIndex)
    end)

    ----------------------------------------------------------------
    -- Spell selector
    ----------------------------------------------------------------
    local spellLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    spellLabel:SetPoint("TOPLEFT", backBtn, "BOTTOMLEFT", 0, -10)
    spellLabel:SetText("On Spell Cast:")

    local spellList = GetRotationalSpellList()
    local spellDd = CreateFrame("Frame", NextDropdownName("TrueShotRBTrigSpell_"), scrollChild, "UIDropDownMenuTemplate")
    TrackFrame(spellDd)
    spellDd:SetPoint("TOPLEFT", spellLabel, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(spellDd, 180)

    UIDropDownMenu_Initialize(spellDd, function()
        for _, sid in ipairs(spellList) do
            local sIcon, sName = GetSpellDisplay(sid)
            local info = UIDropDownMenu_CreateInfo()
            info.text = sName
            info.icon = sIcon
            info.checked = (trig.spellID == sid)
            info.func = function()
                trig.spellID = sid
                UIDropDownMenu_SetText(spellDd, sName)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    local _, curSpellName = GetSpellDisplay(trig.spellID)
    UIDropDownMenu_SetText(spellDd, curSpellName)

    -- Manual spellID
    local manualRow = CreateFrame("Frame", nil, scrollChild)
    TrackFrame(manualRow)
    manualRow:SetSize(280, 22)
    manualRow:SetPoint("TOPLEFT", spellDd, "BOTTOMLEFT", 16, -4)

    local manualLabel = manualRow:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    manualLabel:SetPoint("LEFT", manualRow, "LEFT", 0, 0)
    manualLabel:SetText("or SpellID:")

    local manualEdit = CreateFrame("EditBox", nil, manualRow, "InputBoxTemplate")
    manualEdit:SetSize(80, 20)
    manualEdit:SetPoint("LEFT", manualLabel, "RIGHT", 6, 0)
    manualEdit:SetAutoFocus(false)
    manualEdit:SetText(trig.spellID and tostring(trig.spellID) or "")

    local function ApplyManualTrigSpell()
        local val = tonumber(manualEdit:GetText())
        if val and val > 0 then
            trig.spellID = val
            local _, nm = GetSpellDisplay(val)
            UIDropDownMenu_SetText(spellDd, nm)
        end
    end
    manualEdit:SetScript("OnEnterPressed", function(self) ApplyManualTrigSpell(); self:ClearFocus() end)
    manualEdit:SetScript("OnEditFocusLost", ApplyManualTrigSpell)

    ----------------------------------------------------------------
    -- Value assignment (depends on varType)
    ----------------------------------------------------------------
    local valSectionLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    valSectionLabel:SetPoint("TOPLEFT", manualRow, "BOTTOMLEFT", 0, -10)
    valSectionLabel:SetText("Set Value To:")

    local lastAnchorAfterValue = valSectionLabel

    if def.varType == "boolean" then
        local valChk = CreateFrame("CheckButton", nil, scrollChild, "UICheckButtonTemplate")
        TrackFrame(valChk)
        valChk:SetSize(22, 22)
        valChk:SetPoint("TOPLEFT", valSectionLabel, "BOTTOMLEFT", 0, -2)
        valChk:SetChecked(trig.value == true)
        valChk:SetScript("OnClick", function(self)
            trig.value = self:GetChecked()
        end)
        local valChkLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        valChkLabel:SetPoint("LEFT", valChk, "RIGHT", 4, 0)
        valChkLabel:SetText("true")
        lastAnchorAfterValue = valChk

    elseif def.varType == "timestamp" then
        local setNowChk = CreateFrame("CheckButton", nil, scrollChild, "UICheckButtonTemplate")
        TrackFrame(setNowChk)
        setNowChk:SetSize(22, 22)
        setNowChk:SetPoint("TOPLEFT", valSectionLabel, "BOTTOMLEFT", 0, -2)
        setNowChk:SetChecked(trig.setNow == true)
        setNowChk:SetScript("OnClick", function(self)
            trig.setNow = self:GetChecked()
        end)
        local setNowLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        setNowLabel:SetPoint("LEFT", setNowChk, "RIGHT", 4, 0)
        setNowLabel:SetText("Use GetTime() (record cast time)")
        lastAnchorAfterValue = setNowChk

    else
        -- number
        local valEdit = CreateFrame("EditBox", nil, scrollChild, "InputBoxTemplate")
        TrackFrame(valEdit)
        valEdit:SetSize(80, 20)
        valEdit:SetPoint("TOPLEFT", valSectionLabel, "BOTTOMLEFT", 0, -2)
        valEdit:SetAutoFocus(false)
        valEdit:SetText(tostring(trig.value or 0))
        local function ApplyTrigValue()
            local val = tonumber(valEdit:GetText())
            if val then trig.value = val end
        end
        valEdit:SetScript("OnEnterPressed", function(self) ApplyTrigValue(); self:ClearFocus() end)
        valEdit:SetScript("OnEditFocusLost", ApplyTrigValue)
        lastAnchorAfterValue = valEdit
    end

    ----------------------------------------------------------------
    -- Reset After (optional)
    ----------------------------------------------------------------
    local resetLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    resetLabel:SetPoint("TOPLEFT", lastAnchorAfterValue, "BOTTOMLEFT", 0, -10)
    resetLabel:SetText("Reset After (seconds, 0 = no reset):")

    local resetEdit = CreateFrame("EditBox", nil, scrollChild, "InputBoxTemplate")
    TrackFrame(resetEdit)
    resetEdit:SetSize(60, 20)
    resetEdit:SetPoint("TOPLEFT", resetLabel, "BOTTOMLEFT", 0, -2)
    resetEdit:SetAutoFocus(false)
    resetEdit:SetText(tostring(trig.resetAfter or 0))

    local function ApplyResetAfter()
        local val = tonumber(resetEdit:GetText())
        if val and val > 0 then
            trig.resetAfter = val
        else
            trig.resetAfter = nil
        end
    end
    resetEdit:SetScript("OnEnterPressed", function(self) ApplyResetAfter(); self:ClearFocus() end)
    resetEdit:SetScript("OnEditFocusLost", ApplyResetAfter)

    -- Reset value (only shown if resetAfter is set)
    local resetValLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    resetValLabel:SetPoint("TOPLEFT", resetEdit, "BOTTOMLEFT", 0, -8)
    resetValLabel:SetText("Reset To Value (blank = use default):")

    local resetValEdit = CreateFrame("EditBox", nil, scrollChild, "InputBoxTemplate")
    TrackFrame(resetValEdit)
    resetValEdit:SetSize(80, 20)
    resetValEdit:SetPoint("TOPLEFT", resetValLabel, "BOTTOMLEFT", 0, -2)
    resetValEdit:SetAutoFocus(false)
    resetValEdit:SetText(trig.resetValue ~= nil and tostring(trig.resetValue) or "")

    local function ApplyResetValue()
        local text = resetValEdit:GetText()
        local val = tonumber(text)
        if text == "" then
            trig.resetValue = nil
        elseif def.varType == "boolean" then
            trig.resetValue = (val ~= nil and val ~= 0) or (text == "true")
        else
            trig.resetValue = val
        end
    end
    resetValEdit:SetScript("OnEnterPressed", function(self) ApplyResetValue(); self:ClearFocus() end)
    resetValEdit:SetScript("OnEditFocusLost", ApplyResetValue)

    ----------------------------------------------------------------
    -- Guard condition (simplified: condition type only)
    ----------------------------------------------------------------
    local guardDivider = scrollChild:CreateTexture(nil, "ARTWORK")
    guardDivider:SetHeight(1)
    guardDivider:SetPoint("TOPLEFT", resetValEdit, "BOTTOMLEFT", 0, -10)
    guardDivider:SetPoint("RIGHT", scrollChild, "RIGHT", -8, 0)
    guardDivider:SetColorTexture(0.3, 0.3, 0.3, 0.8)

    local guardHeader = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    guardHeader:SetPoint("TOPLEFT", guardDivider, "BOTTOMLEFT", 0, -6)
    guardHeader:SetText("Guard Condition  |cffaaaaaa(optional, trigger only fires if true)|r")

    local schemas = CustomProfile.GetConditionSchemasForProfile(profileId)

    local clearGuardBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
    TrackFrame(clearGuardBtn)
    clearGuardBtn:SetSize(80, 20)
    clearGuardBtn:SetPoint("TOPLEFT", guardHeader, "BOTTOMLEFT", 0, -6)
    clearGuardBtn:SetText("Clear Guard")
    clearGuardBtn:SetScript("OnClick", function()
        trig.guard = nil
        Rerender()
    end)

    local guardDd = CreateFrame("Frame", NextDropdownName("TrueShotRBGuard_"), scrollChild, "UIDropDownMenuTemplate")
    TrackFrame(guardDd)
    guardDd:SetPoint("LEFT", clearGuardBtn, "RIGHT", 4, 0)
    UIDropDownMenu_SetWidth(guardDd, 150)

    local guardCondition = trig.guard or {}
    UIDropDownMenu_Initialize(guardDd, function()
        for _, schema in ipairs(schemas) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = schema.label
            info.checked = (guardCondition.type == schema.id)
            info.func = function()
                trig.guard = { type = schema.id }
                UIDropDownMenu_SetText(guardDd, schema.label)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    -- Set initial text
    local curGuardLabel = "(none)"
    if trig.guard and trig.guard.type then
        for _, s in ipairs(schemas) do
            if s.id == trig.guard.type then curGuardLabel = s.label; break end
        end
    end
    UIDropDownMenu_SetText(guardDd, curGuardLabel)

    ----------------------------------------------------------------
    -- Save / Delete buttons
    ----------------------------------------------------------------
    local btnRow = CreateFrame("Frame", nil, scrollChild)
    TrackFrame(btnRow)
    btnRow:SetSize(300, 26)
    btnRow:SetPoint("TOPLEFT", guardDd, "BOTTOMLEFT", 16, -14)

    local saveBtn = CreateFrame("Button", nil, btnRow, "UIPanelButtonTemplate")
    saveBtn:SetSize(100, 22)
    saveBtn:SetPoint("LEFT", btnRow, "LEFT", 0, 0)
    saveBtn:SetText("Save Trigger")
    saveBtn:SetScript("OnClick", function()
        -- Flush focus so OnEditFocusLost fires
        RuleBuilder:ShowStateVarEditor(varIndex)
    end)

    local delTrigBtn = CreateFrame("Button", nil, btnRow, "UIPanelButtonTemplate")
    delTrigBtn:SetSize(100, 22)
    delTrigBtn:SetPoint("LEFT", saveBtn, "RIGHT", 8, 0)
    delTrigBtn:SetText("Delete Trigger")
    delTrigBtn:SetScript("OnClick", function()
        if _editingData.triggers then
            table.remove(_editingData.triggers, trigIndex)
        end
        RuleBuilder:ShowStateVarEditor(varIndex)
    end)

    ----------------------------------------------------------------
    -- Scroll height estimate
    ----------------------------------------------------------------
    local estHeight = 24 + 26 + 16 + 50 + 26 + 16 + 30 + 16 + 30 + 16 + 30 + 50 + 30 + 40
    scrollChild:SetHeight(math.max(estHeight, 300))
    C_Timer.After(0, function()
        if not scrollChild:GetParent() then return end
        local top = scrollChild:GetTop()
        local bottom = btnRow:GetBottom()
        if top and bottom then
            scrollChild:SetHeight(math.max(top - bottom + 30, 300))
        end
    end)
end
