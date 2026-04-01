-- HunterFlow Display: presentation layer for the queue overlay

local Engine = HunterFlow.Engine
local GetTime = GetTime
local C_Spell_GetSpellTexture = C_Spell and C_Spell.GetSpellTexture
local C_Spell_GetSpellCooldown = C_Spell and C_Spell.GetSpellCooldown

HunterFlow.Display = {}
local Display = HunterFlow.Display

local SUCCESS_FLASH_DURATION = 0.35
local MIN_COOLDOWN_SWIPE_DURATION = 2.0
local CONTAINER_PADDING_X = 8
local CONTAINER_PADDING_Y = 6
local ICON_TEXTURE_INSET = 3

------------------------------------------------------------------------
-- Container frame
------------------------------------------------------------------------

local container = CreateFrame("Frame", "HunterFlowFrame", UIParent,
    "BackdropTemplate")
container:SetSize(200, 50)
container:SetPoint("CENTER", UIParent, "CENTER", 0, -50)
container:SetMovable(true)
container:EnableMouse(true)
container:SetClampedToScreen(true)
container:RegisterForDrag("LeftButton")
container:SetScript("OnDragStart", function(self)
    if not HunterFlow.GetOpt("locked") then self:StartMoving() end
end)
container:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
end)
container:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
container:SetBackdropColor(0.04, 0.04, 0.04, 0.92)
container:SetBackdropBorderColor(0.55, 0.55, 0.55, 0.95)

local content = CreateFrame("Frame", nil, container)
content:SetPoint("TOPLEFT", container, "TOPLEFT", CONTAINER_PADDING_X, -CONTAINER_PADDING_Y)
content:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -CONTAINER_PADDING_X, CONTAINER_PADDING_Y)

Display.container = container

container:SetClipsChildren(false)

local reasonText = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
reasonText:SetPoint("TOP", container, "BOTTOM", 0, -2)
reasonText:SetJustifyH("CENTER")
reasonText:SetTextColor(0.75, 0.85, 1.0, 0.9)
reasonText:Hide()

local phaseText = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
phaseText:SetPoint("BOTTOM", container, "TOP", 0, 2)
phaseText:SetJustifyH("CENTER")
phaseText:SetTextColor(1.0, 0.82, 0.0, 0.9)
phaseText:Hide()

------------------------------------------------------------------------
-- Icons
------------------------------------------------------------------------

local icons = {}

local function ClearCooldown(icon)
    if not icon or not icon.cooldown then return end
    if icon.cooldown.Clear then
        icon.cooldown:Clear()
    elseif icon.cooldown.SetCooldown then
        icon.cooldown:SetCooldown(0, 0)
    end
    icon.cooldown:Hide()
end

local function GetKeybindForSpell(spellID)
    for slot = 1, 120 do
        local actionType, id = GetActionInfo(slot)
        if actionType == "spell" and id == spellID then
            local key = GetBindingKey("ACTIONBUTTON" .. ((slot - 1) % 12 + 1))
            if not key then
                local bar = math.ceil(slot / 12)
                local btn = (slot - 1) % 12 + 1
                if bar == 1 then
                    key = GetBindingKey("ACTIONBUTTON" .. btn)
                elseif bar <= 6 then
                    key = GetBindingKey("MULTIACTIONBAR" .. (bar - 1) .. "BUTTON" .. btn)
                end
            end
            if key then return key end
        end
    end
    return nil
end

local function CreateIcon(index)
    local size = HunterFlow.GetOpt("iconSize")
    local spacing = HunterFlow.GetOpt("iconSpacing")

    local frame = CreateFrame("Frame", "HunterFlowIcon" .. index,
        content)
    frame:SetSize(size, size)
    frame:SetPoint("LEFT", content, "LEFT",
        (index - 1) * (size + spacing), 0)

    frame.slotBackground = frame:CreateTexture(nil, "BACKGROUND")
    frame.slotBackground:SetAllPoints()
    frame.slotBackground:SetAtlas("UI-HUD-ActionBar-IconFrame-Background")

    frame.texture = frame:CreateTexture(nil, "ARTWORK")
    frame.texture:SetPoint("TOPLEFT", frame, "TOPLEFT", ICON_TEXTURE_INSET, -ICON_TEXTURE_INSET)
    frame.texture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -ICON_TEXTURE_INSET, ICON_TEXTURE_INSET)
    frame.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    if frame.CreateMaskTexture and frame.texture.AddMaskTexture and frame.slotBackground.AddMaskTexture then
        local mask = frame:CreateMaskTexture(nil, "ARTWORK")
        mask:SetPoint("TOPLEFT", frame, "TOPLEFT", -6, 6)
        mask:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 6, -6)
        mask:SetAtlas("UI-HUD-ActionBar-IconFrame-Mask", false)
        frame.texture:AddMaskTexture(mask)
        frame.slotBackground:AddMaskTexture(mask)
        frame.mask = mask
    end

    frame.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.cooldown:ClearAllPoints()
    frame.cooldown:SetPoint("TOPLEFT", frame, "TOPLEFT", ICON_TEXTURE_INSET, -ICON_TEXTURE_INSET)
    frame.cooldown:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -ICON_TEXTURE_INSET, ICON_TEXTURE_INSET)
    frame.cooldown:SetHideCountdownNumbers(true)
    if frame.cooldown.SetDrawBling then frame.cooldown:SetDrawBling(false) end
    if frame.cooldown.SetDrawEdge then frame.cooldown:SetDrawEdge(false) end
    if frame.cooldown.SetSwipeColor then frame.cooldown:SetSwipeColor(0, 0, 0, 0.8) end
    frame.cooldown:Hide()

    frame.keybind = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    frame.keybind:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    frame.keybind:SetJustifyH("RIGHT")

    frame.success = frame:CreateTexture(nil, "OVERLAY")
    frame.success:SetAllPoints()
    frame.success:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover")
    frame.success:SetVertexColor(0.20, 1.00, 0.35, 1.0)
    frame.success:SetBlendMode("ADD")
    frame.success:Hide()
    frame.successUntil = 0
    frame.spellID = nil

    frame.border = frame:CreateTexture(nil, "OVERLAY")
    frame.border:SetAllPoints()
    frame.border:SetAtlas("UI-HUD-ActionBar-IconFrame")

    if index > 1 then
        frame:SetAlpha(0.7)
    end

    frame:Hide()
    return frame
end

local function LayoutIcons()
    local size = HunterFlow.GetOpt("iconSize")
    local spacing = HunterFlow.GetOpt("iconSpacing")
    for index, frame in ipairs(icons) do
        frame:SetSize(size, size)
        frame:ClearAllPoints()
        frame:SetPoint("LEFT", content, "LEFT", (index - 1) * (size + spacing), 0)
        if index > 1 then
            frame:SetAlpha(0.7)
        else
            frame:SetAlpha(1)
        end
    end
end

local function EnsureIcons()
    local count = HunterFlow.GetOpt("iconCount")
    while #icons < count do
        icons[#icons + 1] = CreateIcon(#icons + 1)
    end
end

function Display:UpdateContainerSize()
    local count = HunterFlow.GetOpt("iconCount")
    local size = HunterFlow.GetOpt("iconSize")
    local spacing = HunterFlow.GetOpt("iconSpacing")
    local width = count * size + (count - 1) * spacing
    container:SetSize(
        width + (CONTAINER_PADDING_X * 2),
        size + (CONTAINER_PADDING_Y * 2)
    )
    content:SetSize(width, size)
    LayoutIcons()
end

function Display:ApplyOptions()
    self:UpdateContainerSize()
    container:EnableMouse(not HunterFlow.GetOpt("locked"))
end

function Display:UpdateCooldown(icon, spellID)
    if not icon or not icon.cooldown then return end
    if not HunterFlow.GetOpt("showCooldownSwipe") or not spellID or not C_Spell_GetSpellCooldown then
        ClearCooldown(icon)
        return
    end

    local ok, cooldown = pcall(C_Spell_GetSpellCooldown, spellID)
    if not ok or not cooldown then
        ClearCooldown(icon)
        return
    end

    local startTime = cooldown.startTime or 0
    local duration = cooldown.duration or 0

    if issecretvalue and (issecretvalue(startTime) or issecretvalue(duration)) then
        ClearCooldown(icon)
        return
    end

    if startTime <= 0 or duration < MIN_COOLDOWN_SWIPE_DURATION then
        ClearCooldown(icon)
        return
    end

    if icon.cooldown.SetCooldown then
        icon.cooldown:SetCooldown(startTime, duration, cooldown.modRate or 1)
    end
    icon.cooldown:Show()
end

function Display:UpdateCastFeedback(icon, now)
    if not icon or not icon.success then return end
    if not HunterFlow.GetOpt("showCastFeedback") then
        icon.success:Hide()
        icon.successUntil = 0
        return
    end

    if icon.successUntil > now then
        local remaining = icon.successUntil - now
        icon.success:SetAlpha(remaining / SUCCESS_FLASH_DURATION)
        icon.success:Show()
    else
        icon.success:Hide()
    end
end

function Display:UpdateQueue(queue)
    EnsureIcons()
    local count = HunterFlow.GetOpt("iconCount")
    local now = GetTime()

    for i = 1, count do
        local icon = icons[i]
        local spellID = queue[i]

        if spellID then
            local texture = C_Spell_GetSpellTexture and C_Spell_GetSpellTexture(spellID)
            if texture then
                icon.texture:SetTexture(texture)
                local key = GetKeybindForSpell(spellID)
                icon.keybind:SetText(key or "")
                icon.spellID = spellID
                self:UpdateCooldown(icon, spellID)
                self:UpdateCastFeedback(icon, now)
                icon:Show()
            else
                icon.spellID = nil
                ClearCooldown(icon)
                icon.success:Hide()
                icon:Hide()
            end
        else
            icon.spellID = nil
            ClearCooldown(icon)
            icon.success:Hide()
            icon:Hide()
        end
    end

    for i = count + 1, #icons do
        local icon = icons[i]
        icon.spellID = nil
        ClearCooldown(icon)
        icon.success:Hide()
        icon:Hide()
    end

    local meta = Engine.lastQueueMeta

    -- Why overlay: show reason for position 1
    if HunterFlow.GetOpt("showWhyOverlay") and meta and meta.reason then
        reasonText:SetText(meta.reason)
        reasonText:Show()
    else
        reasonText:Hide()
    end

    -- Phase indicator: show current rotation phase above overlay
    if HunterFlow.GetOpt("showPhaseIndicator") and meta and meta.phase then
        phaseText:SetText(meta.phase)
        phaseText:Show()
    else
        phaseText:Hide()
    end

    -- Override indicator: tint primary icon border when HunterFlow overrides AC
    if HunterFlow.GetOpt("showOverrideIndicator") and icons[1] and icons[1].border then
        if meta and (meta.source == "pin" or meta.source == "prefer") then
            icons[1].border:SetVertexColor(0.30, 0.85, 1.0, 1.0)
        else
            icons[1].border:SetVertexColor(1.0, 1.0, 1.0, 1.0)
        end
    elseif icons[1] and icons[1].border then
        icons[1].border:SetVertexColor(1.0, 1.0, 1.0, 1.0)
    end
end

function Display:OnSpellCastSucceeded(spellID)
    if not HunterFlow.GetOpt("showCastFeedback") then return end
    local now = GetTime()
    for _, icon in ipairs(icons) do
        if icon.spellID == spellID then
            icon.successUntil = now + SUCCESS_FLASH_DURATION
            self:UpdateCastFeedback(icon, now)
        end
    end
end

------------------------------------------------------------------------
-- Update throttle
------------------------------------------------------------------------

local UPDATE_INTERVAL = 0.1
local timeSinceUpdate = 0

function Display:Enable()
    self:ApplyOptions()
    EnsureIcons()
    container:EnableMouse(not HunterFlow.GetOpt("locked"))
    container:Show()
    container:SetScript("OnUpdate", function(_, elapsed)
        timeSinceUpdate = timeSinceUpdate + elapsed
        if timeSinceUpdate < UPDATE_INTERVAL then return end
        timeSinceUpdate = 0

        local queue = Engine:ComputeQueue(HunterFlow.GetOpt("iconCount"))
        Display:UpdateQueue(queue)
    end)
end

function Display:Disable()
    container:SetScript("OnUpdate", nil)
    container:Hide()
end

function Display:SetClickThrough(locked)
    container:EnableMouse(not locked)
end

function Display:ResetPosition()
    container:ClearAllPoints()
    container:SetPoint("CENTER", UIParent, "CENTER", 0, -50)
end

HunterFlow.RegisterOptCallback(function()
    Display:ApplyOptions()
end)
