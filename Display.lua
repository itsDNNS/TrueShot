-- TrueShot Display: presentation layer for the queue overlay

local Engine = TrueShot.Engine
local GetTime = GetTime
local C_Spell_GetSpellTexture = C_Spell and C_Spell.GetSpellTexture
local C_Spell_GetSpellCooldown = C_Spell and C_Spell.GetSpellCooldown
local C_Spell_GetSpellCharges = C_Spell and C_Spell.GetSpellCharges

TrueShot.Display = {}
local Display = TrueShot.Display

local SUCCESS_FLASH_DURATION = 0.35
local MIN_COOLDOWN_SWIPE_DURATION = 2.0
local CONTAINER_PADDING_X = 8
local CONTAINER_PADDING_Y = 6
local ICON_TEXTURE_INSET = 3

------------------------------------------------------------------------
-- Container frame
------------------------------------------------------------------------

local container = CreateFrame("Frame", "TrueShotFrame", UIParent,
    "BackdropTemplate")
container:SetSize(200, 50)
container:SetPoint("CENTER", UIParent, "CENTER", 0, -50)
container:SetMovable(true)
container:EnableMouse(true)
container:SetClampedToScreen(true)
container:RegisterForDrag("LeftButton")
container:SetScript("OnDragStart", function(self)
    if not TrueShot.GetOpt("locked") then self:StartMoving() end
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

Display.container = container
container:Hide()

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

local keybindCache = {}
local keybindCacheDirty = true

local function GetKeyForSlot(slot)
    local btn = (slot - 1) % 12 + 1
    local bar = math.ceil(slot / 12)
    local key = GetBindingKey("ACTIONBUTTON" .. btn)
    if not key and bar >= 2 and bar <= 6 then
        key = GetBindingKey("MULTIACTIONBAR" .. (bar - 1) .. "BUTTON" .. btn)
    end
    return key
end

local function RebuildKeybindCache()
    wipe(keybindCache)
    for slot = 1, 120 do
        local actionType, id = GetActionInfo(slot)
        local spellID = nil

        if (actionType == "spell" or actionType == "macro") and id then
            spellID = id
        end

        if spellID then
            local key = GetKeyForSlot(slot)
            if key and not keybindCache[spellID] then
                keybindCache[spellID] = key
            end
        end
    end
    keybindCacheDirty = false
end

local keybindFrame = CreateFrame("Frame")
keybindFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
keybindFrame:RegisterEvent("UPDATE_BINDINGS")
keybindFrame:RegisterEvent("SPELLS_CHANGED")
keybindFrame:SetScript("OnEvent", function() keybindCacheDirty = true end)

local function GetKeybindForSpell(spellID)
    if keybindCacheDirty then RebuildKeybindCache() end
    return keybindCache[spellID]
end

local function CreateIcon(index)
    local size = TrueShot.GetOpt("iconSize")
    local spacing = TrueShot.GetOpt("iconSpacing")

    local frame = CreateFrame("Frame", "TrueShotIcon" .. index,
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

    -- Charge cooldown: renders beneath primary CD for charge-based spells
    frame.chargeCooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.chargeCooldown:ClearAllPoints()
    frame.chargeCooldown:SetPoint("TOPLEFT", frame, "TOPLEFT", ICON_TEXTURE_INSET, -ICON_TEXTURE_INSET)
    frame.chargeCooldown:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -ICON_TEXTURE_INSET, ICON_TEXTURE_INSET)
    frame.chargeCooldown:SetHideCountdownNumbers(true)
    if frame.chargeCooldown.SetDrawBling then frame.chargeCooldown:SetDrawBling(false) end
    if frame.chargeCooldown.SetDrawEdge then frame.chargeCooldown:SetDrawEdge(false) end
    if frame.chargeCooldown.SetSwipeColor then frame.chargeCooldown:SetSwipeColor(0, 0, 0, 0.4) end
    frame.chargeCooldown:SetFrameLevel(frame.cooldown:GetFrameLevel() - 1)
    frame.chargeCooldown:Hide()

    frame.chargeCount = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    frame.chargeCount:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    frame.chargeCount:SetJustifyH("RIGHT")
    frame.chargeCount:Hide()

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

local ORIENTATION_CONFIG = {
    LEFT  = { anchor = "LEFT",   axis = "x", sign =  1 },
    RIGHT = { anchor = "RIGHT",  axis = "x", sign = -1 },
    UP    = { anchor = "BOTTOM", axis = "y", sign =  1 },
    DOWN  = { anchor = "TOP",    axis = "y", sign = -1 },
}

local function LayoutIcons()
    local size = TrueShot.GetOpt("iconSize")
    local spacing = TrueShot.GetOpt("iconSpacing")
    local firstScale = TrueShot.GetOpt("firstIconScale") or 1.3
    local orient = TrueShot.GetOpt("orientation") or "LEFT"
    local cfg = ORIENTATION_CONFIG[orient] or ORIENTATION_CONFIG.LEFT

    local effectiveFirst = size * firstScale

    for index, frame in ipairs(icons) do
        frame:SetSize(size, size)
        frame:ClearAllPoints()

        local isFirst = (index == 1)
        frame:SetScale(isFirst and firstScale or 1.0)

        if isFirst then
            frame:SetAlpha(1)
        else
            frame:SetAlpha(0.7)
        end

        local offset
        if isFirst then
            offset = 0
        else
            offset = effectiveFirst + spacing + (index - 2) * (size + spacing)
        end

        local dx = cfg.axis == "x" and (offset * cfg.sign) or 0
        local dy = cfg.axis == "y" and (offset * cfg.sign) or 0
        frame:SetPoint(cfg.anchor, content, cfg.anchor, dx, dy)
    end
end

local function EnsureIcons()
    local count = TrueShot.GetOpt("iconCount")
    while #icons < count do
        icons[#icons + 1] = CreateIcon(#icons + 1)
    end
end

function Display:UpdateContainerSize()
    local count = TrueShot.GetOpt("iconCount")
    local size = TrueShot.GetOpt("iconSize")
    local spacing = TrueShot.GetOpt("iconSpacing")
    local firstScale = TrueShot.GetOpt("firstIconScale") or 1.3
    local orient = TrueShot.GetOpt("orientation") or "LEFT"
    local isVertical = (orient == "UP" or orient == "DOWN")

    local effectiveFirst = size * firstScale
    local totalLength = effectiveFirst + (count - 1) * size + (count - 1) * spacing
    local thickness = math.max(effectiveFirst, size)

    local w, h
    if isVertical then
        w = thickness + (CONTAINER_PADDING_X * 2)
        h = totalLength + (CONTAINER_PADDING_Y * 2)
    else
        w = totalLength + (CONTAINER_PADDING_X * 2)
        h = thickness + (CONTAINER_PADDING_Y * 2)
    end
    container:SetSize(w, h)

    if isVertical then
        content:SetSize(thickness, totalLength)
    else
        content:SetSize(totalLength, thickness)
    end

    reasonText:ClearAllPoints()
    phaseText:ClearAllPoints()
    if isVertical then
        reasonText:SetPoint("LEFT", container, "RIGHT", 4, 0)
        reasonText:SetJustifyH("LEFT")
        phaseText:SetPoint("RIGHT", container, "LEFT", -4, 0)
        phaseText:SetJustifyH("RIGHT")
    else
        reasonText:SetPoint("TOP", container, "BOTTOM", 0, -2)
        reasonText:SetJustifyH("CENTER")
        phaseText:SetPoint("BOTTOM", container, "TOP", 0, 2)
        phaseText:SetJustifyH("CENTER")
    end

    LayoutIcons()
end

function Display:ApplyOptions()
    self:UpdateContainerSize()
    container:EnableMouse(not TrueShot.GetOpt("locked"))
    container:SetScale(TrueShot.GetOpt("overlayScale") or 1.0)
    container:SetAlpha(TrueShot.GetOpt("overlayOpacity") or 1.0)

    if TrueShot.GetOpt("showBackdrop") then
        container:SetBackdropColor(0.04, 0.04, 0.04, 0.92)
        container:SetBackdropBorderColor(0.55, 0.55, 0.55, 0.95)
    else
        container:SetBackdropColor(0, 0, 0, 0)
        container:SetBackdropBorderColor(0, 0, 0, 0)
    end
end

function Display:UpdateCooldown(icon, spellID)
    if not icon or not icon.cooldown then return end
    if not TrueShot.GetOpt("showCooldownSwipe") or not spellID or not C_Spell_GetSpellCooldown then
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

function Display:UpdateChargeCooldown(icon, spellID)
    if not icon or not icon.chargeCooldown then return end
    if not TrueShot.GetOpt("showCooldownSwipe") or not spellID or not C_Spell_GetSpellCharges then
        icon.chargeCooldown:Hide()
        if icon.chargeCount then icon.chargeCount:Hide() end
        return
    end

    local ok, charges = pcall(C_Spell_GetSpellCharges, spellID)
    if not ok or not charges or not charges.maxCharges or charges.maxCharges <= 1 then
        icon.chargeCooldown:Hide()
        if icon.chargeCount then icon.chargeCount:Hide() end
        return
    end

    local current = charges.currentCharges or 0
    local maxC = charges.maxCharges or 1

    if issecretvalue and (issecretvalue(current) or issecretvalue(maxC)) then
        icon.chargeCooldown:Hide()
        if icon.chargeCount then icon.chargeCount:Hide() end
        return
    end

    icon.chargeCount:SetText(current)
    icon.chargeCount:Show()

    if current < maxC and charges.cooldownStartTime and charges.cooldownDuration then
        local modRate = charges.chargeModRate or 1.0
        if issecretvalue and issecretvalue(modRate) then modRate = 1.0 end
        icon.chargeCooldown:SetCooldown(
            charges.cooldownStartTime,
            charges.cooldownDuration,
            modRate
        )
        icon.chargeCooldown:Show()
    else
        icon.chargeCooldown:Hide()
    end
end

function Display:UpdateCastFeedback(icon, now)
    if not icon or not icon.success then return end
    if not TrueShot.GetOpt("showCastFeedback") then
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
    local count = TrueShot.GetOpt("iconCount")
    local now = GetTime()

    for i = 1, count do
        local icon = icons[i]
        local spellID = queue[i]

        if spellID then
            local texture = C_Spell_GetSpellTexture and C_Spell_GetSpellTexture(spellID)
            if texture then
                icon.texture:SetTexture(texture)

                -- Keybinds toggle
                if TrueShot.GetOpt("showKeybinds") then
                    local key = GetKeybindForSpell(spellID)
                    icon.keybind:SetText(key or "")
                else
                    icon.keybind:SetText("")
                end

                -- Range indicator: desaturate when target is out of range
                if TrueShot.GetOpt("showRangeIndicator") and i == 1 and UnitExists("target") then
                    local outOfRange = false
                    if C_Spell and C_Spell.IsSpellInRange then
                        local ok, result = pcall(C_Spell.IsSpellInRange, spellID, "target")
                        if ok and result == false then outOfRange = true end
                    end
                    if outOfRange then
                        icon.texture:SetDesaturated(true)
                        icon.texture:SetVertexColor(0.8, 0.3, 0.3)
                    else
                        icon.texture:SetDesaturated(false)
                        icon.texture:SetVertexColor(1, 1, 1)
                    end
                else
                    icon.texture:SetDesaturated(false)
                    icon.texture:SetVertexColor(1, 1, 1)
                end

                icon.spellID = spellID
                self:UpdateCooldown(icon, spellID)
                self:UpdateChargeCooldown(icon, spellID)
                self:UpdateCastFeedback(icon, now)
                icon:Show()
            else
                icon.spellID = nil
                ClearCooldown(icon)
                if icon.chargeCooldown then icon.chargeCooldown:Hide() end
                if icon.chargeCount then icon.chargeCount:Hide() end
                icon.success:Hide()
                icon:Hide()
            end
        else
            icon.spellID = nil
            ClearCooldown(icon)
            if icon.chargeCooldown then icon.chargeCooldown:Hide() end
            if icon.chargeCount then icon.chargeCount:Hide() end
            icon.success:Hide()
            icon:Hide()
        end
    end

    for i = count + 1, #icons do
        local icon = icons[i]
        icon.spellID = nil
        ClearCooldown(icon)
        if icon.chargeCooldown then icon.chargeCooldown:Hide() end
        if icon.chargeCount then icon.chargeCount:Hide() end
        icon.success:Hide()
        icon:Hide()
    end

    local meta = Engine.lastQueueMeta

    -- Why overlay: show reason for position 1
    if TrueShot.GetOpt("showWhyOverlay") and meta and meta.reason then
        reasonText:SetText(meta.reason)
        reasonText:Show()
    else
        reasonText:Hide()
    end

    -- Phase indicator: show current rotation phase above overlay
    if TrueShot.GetOpt("showPhaseIndicator") and meta and meta.phase then
        phaseText:SetText(meta.phase)
        phaseText:Show()
    else
        phaseText:Hide()
    end

    -- Override indicator: tint primary icon border when TrueShot overrides AC
    if TrueShot.GetOpt("showOverrideIndicator") and icons[1] and icons[1].border then
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
    if not TrueShot.GetOpt("showCastFeedback") then return end
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
    container:EnableMouse(not TrueShot.GetOpt("locked"))
    container:Show()
    container:SetScript("OnUpdate", function(_, elapsed)
        timeSinceUpdate = timeSinceUpdate + elapsed
        if timeSinceUpdate < UPDATE_INTERVAL then return end
        timeSinceUpdate = 0

        local queue = Engine:ComputeQueue(TrueShot.GetOpt("iconCount"))
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

TrueShot.RegisterOptCallback(function(key)
    Display:ApplyOptions()
    if key == "combatOnly" or key == "enemyTargetOnly" or key == "hidden" then
        -- Defer to Core.lua's ReconcileVisibility via a zero-delay timer
        -- (Core.lua defines ReconcileVisibility after Display loads)
        C_Timer.After(0, function()
            if TrueShot.ReconcileVisibility then
                TrueShot.ReconcileVisibility()
            end
        end)
    end
end)
