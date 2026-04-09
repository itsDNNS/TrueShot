-- TrueShot Display: presentation layer for the queue overlay

local Engine = TrueShot.Engine
local GetTime = GetTime
local C_Spell_GetSpellTexture = C_Spell and C_Spell.GetSpellTexture
local C_Spell_GetSpellCooldown = C_Spell and C_Spell.GetSpellCooldown
local C_Spell_GetSpellCharges = C_Spell and C_Spell.GetSpellCharges
local C_Spell_GetSpellCooldownDuration = C_Spell and C_Spell.GetSpellCooldownDuration
local C_Spell_GetSpellChargeDuration = C_Spell and C_Spell.GetSpellChargeDuration
local C_ActionBar_GetActionCooldown = C_ActionBar and C_ActionBar.GetActionCooldown
local C_ActionBar_GetActionCooldownDuration = C_ActionBar and C_ActionBar.GetActionCooldownDuration
local C_ActionBar_GetActionChargeDuration = C_ActionBar and C_ActionBar.GetActionChargeDuration

local Masque = _G.LibStub and _G.LibStub("Masque", true)
local MasqueGroup = Masque and Masque:Group("TrueShot", "Queue")

TrueShot.Display = {}
local Display = TrueShot.Display

local SUCCESS_FLASH_DURATION = 0.35
local MIN_COOLDOWN_SWIPE_DURATION = 2.0
local CONTAINER_PADDING_X = 8
local CONTAINER_PADDING_Y = 6
local ICON_TEXTURE_INSET = 3
local QUEUE_STABILIZATION_TICKS = 2
local QUEUE_HIDE_STABILIZATION_TICKS = 5  -- slower fade-out: require 5 stable ticks before hiding

local displayedQueueState = { count = 0 }
local pendingQueueState = { count = 0 }
local pendingQueueTicks = 0
local allowImmediateQueueUpdate = false
local displayEnabled = false

-- Committed metadata snapshot (persisted alongside displayedQueueState)
local committedMeta = { source = "ac", reason = nil }

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
    if not TrueShot.GetOpt("locked") then
        self:StartMoving()
    end
end)
container:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    Display:SaveCurrentPosition()
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

if MasqueGroup then
    MasqueGroup:RegisterCallback(function()
        for _, icon in ipairs(icons) do
            if icon.keybind then
                icon.keybind:ClearAllPoints()
                icon.keybind:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -2, -2)
            end
        end
    end)
end

local function ClearCooldown(icon)
    if not icon or not icon.cooldown then return end
    if icon.cooldown.Clear then
        icon.cooldown:Clear()
    elseif icon.cooldown.SetCooldown then
        icon.cooldown:SetCooldown(0, 0)
    end
    icon.cooldown:Hide()
end

local function ResetStoredQueue(state)
    local prevCount = state.count or 0
    for i = 1, prevCount do
        state[i] = nil
    end
    state.count = 0
end

local function StoreQueue(state, queue, count)
    local prevCount = state.count or 0
    for i = 1, count do
        state[i] = queue[i]
    end
    for i = count + 1, prevCount do
        state[i] = nil
    end
    state.count = count
end

local function QueuesMatch(state, queue, count)
    if (state.count or 0) ~= count then return false end
    for i = 1, count do
        if state[i] ~= queue[i] then
            return false
        end
    end
    return true
end

local function ClearPendingQueue()
    ResetStoredQueue(pendingQueueState)
    pendingQueueTicks = 0
end

local keybindCache = {}
local keybindNameCache = {}
local keybindTextureCache = {}
local actionSlotCache = {}
local actionSlotNameCache = {}
local actionSlotTextureCache = {}
local keybindCacheDirty = true

local ACTION_BUTTON_BINDINGS = {
    { prefix = "ActionButton", commandPrefix = "ACTIONBUTTON" },
    { prefix = "MultiBarBottomLeftButton", commandPrefix = "MULTIACTIONBAR1BUTTON" },
    { prefix = "MultiBarBottomRightButton", commandPrefix = "MULTIACTIONBAR2BUTTON" },
    { prefix = "MultiBarRightButton", commandPrefix = "MULTIACTIONBAR3BUTTON" },
    { prefix = "MultiBarLeftButton", commandPrefix = "MULTIACTIONBAR4BUTTON" },
    { prefix = "MultiBar5Button", commandPrefix = "MULTIACTIONBAR5BUTTON" },
    { prefix = "MultiBar6Button", commandPrefix = "MULTIACTIONBAR6BUTTON" },
    { prefix = "MultiBar7Button", commandPrefix = "MULTIACTIONBAR7BUTTON" },
}

-- ElvUI support: click-binding format "CLICK ElvUI_BarXButtonY:LeftButton"
for i = 1, 15 do
    ACTION_BUTTON_BINDINGS[#ACTION_BUTTON_BINDINGS + 1] = {
        prefix = "ElvUI_Bar" .. i .. "Button",
        commandPrefix = "CLICK ElvUI_Bar" .. i .. "Button",
        commandSuffix = ":LeftButton",
    }
end

local LegacyGetActionTexture = rawget(_G, "GetActionTexture")

local function NormalizeSpellName(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil end
    return name:lower()
end

local function ResolveSpellNameFromID(spellID)
    if not spellID then return nil end
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if ok and name then
            return NormalizeSpellName(name)
        end
    end
    return nil
end

local function ResolveSpellIDFromIdentifier(spellIdentifier)
    if type(spellIdentifier) == "number" then
        return spellIdentifier
    end
    if type(spellIdentifier) ~= "string" then
        return nil
    end

    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellIdentifier)
        if ok and info and info.spellID then
            return info.spellID
        end
    end

    return nil
end

local function ResolveSpellFromMacro(macroID)
    if not macroID then
        return nil, nil
    end

    if GetMacroSpell then
        local macroSpell = GetMacroSpell(macroID)
        local spellID = ResolveSpellIDFromIdentifier(macroSpell)
        if spellID then
            return spellID, ResolveSpellNameFromID(spellID)
        end
        if type(macroSpell) == "string" then
            return nil, NormalizeSpellName(macroSpell)
        end
    end

    if not GetMacroBody then
        return nil, nil
    end

    local body = GetMacroBody(macroID)
    if type(body) ~= "string" or body == "" then
        return nil, nil
    end

    for line in body:gmatch("[^\r\n]+") do
        local command, args = line:match("^%s*/(%S+)%s+(.+)$")
        if command and args then
            command = command:lower()
            if command == "cast" or command == "castsequence" then
                args = args:gsub("%b[]", "")
                -- Strip castsequence reset options (e.g. "reset=target/combat")
                args = args:gsub("^%s*reset=[^%s]*%s*", "")
                local token = args:match("^%s*([^,;]+)")
                if token then
                    token = token:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^!", "")
                    local spellID = ResolveSpellIDFromIdentifier(tonumber(token) or token)
                    if spellID then
                        return spellID, ResolveSpellNameFromID(spellID)
                    end
                    local nameKey = NormalizeSpellName(token)
                    if nameKey then
                        return nil, nameKey
                    end
                end
            end
        end
    end

    return nil, nil
end

local function ResolveActionSlotFromButton(button)
    if not button then return nil end
    if button.CalculateAction then
        local ok, slot = pcall(button.CalculateAction, button)
        if ok and slot then return slot end
    end
    return button.action
end

local function GetPreferredBindingKey(command)
    local a, b = GetBindingKey(command)
    if b and type(b) == "string" and b:find("%-") and (not a or (type(a) == "string" and not a:find("%-"))) then
        return b
    end
    return a or b
end

local function GetPreferredBindingFromBindingEntry(key1, key2)
    if key2 and type(key2) == "string" and key2:find("%-") and (not key1 or (type(key1) == "string" and not key1:find("%-"))) then
        return key2
    end
    return key1 or key2
end

local function CacheSpellKeybind(spellID, spellNameKey, key)
    if not key then return end
    if spellID and not keybindCache[spellID] then
        keybindCache[spellID] = key
    end
    if spellNameKey and not keybindNameCache[spellNameKey] then
        keybindNameCache[spellNameKey] = key
    end
end

local function CacheSpellActionSlot(spellID, spellNameKey, texture, slot)
    if not slot then return end
    if spellID and not actionSlotCache[spellID] then
        actionSlotCache[spellID] = slot
    end
    if spellNameKey and not actionSlotNameCache[spellNameKey] then
        actionSlotNameCache[spellNameKey] = slot
    end
    if texture and not actionSlotTextureCache[texture] then
        actionSlotTextureCache[texture] = slot
    end
end

local function RebuildKeybindCache()
    wipe(keybindCache)
    wipe(keybindNameCache)
    wipe(keybindTextureCache)
    wipe(actionSlotCache)
    wipe(actionSlotNameCache)
    wipe(actionSlotTextureCache)

    for _, bar in ipairs(ACTION_BUTTON_BINDINGS) do
        for btn = 1, 12 do
            local bindCmd = bar.commandSuffix
                and (bar.commandPrefix .. btn .. bar.commandSuffix)
                or (bar.commandPrefix .. btn)
            local key = GetPreferredBindingKey(bindCmd)
            if key then
                local button = _G[bar.prefix .. btn]
                local slot = ResolveActionSlotFromButton(button)
                if slot then
                    local actionType, id = GetActionInfo(slot)
                    if actionType == "spell" and id then
                        local nameKey = ResolveSpellNameFromID(id)
                        local texture = LegacyGetActionTexture and LegacyGetActionTexture(slot)
                        CacheSpellKeybind(id, nameKey, key)
                        CacheSpellActionSlot(id, nameKey, texture, slot)
                    elseif actionType == "macro" and id then
                        local spellID, spellNameKey = ResolveSpellFromMacro(id)
                        local texture = LegacyGetActionTexture and LegacyGetActionTexture(slot)
                        CacheSpellKeybind(spellID, spellNameKey, key)
                        CacheSpellActionSlot(spellID, spellNameKey, texture, slot)
                        if not spellID and not spellNameKey and texture then
                            if not keybindTextureCache[texture] then
                                keybindTextureCache[texture] = key
                            end
                            if not actionSlotTextureCache[texture] then
                                actionSlotTextureCache[texture] = slot
                            end
                        end
                    end
                end
            end
        end
    end

    -- Also support direct keybindings to macros (not on action bars).
    if GetNumBindings and GetBinding and GetMacroIndexByName then
        for i = 1, GetNumBindings() do
            local command, _cat, key1, key2 = GetBinding(i)
            if type(command) == "string" and command:find("^MACRO ") then
                local macroName = command:sub(7)
                local macroID = GetMacroIndexByName(macroName)
                if macroID and macroID > 0 then
                    local spellID, spellNameKey = ResolveSpellFromMacro(macroID)
                    local key = GetPreferredBindingFromBindingEntry(key1, key2)
                    CacheSpellKeybind(spellID, spellNameKey, key)
                end
            end
        end
    end

    keybindCacheDirty = false
end

local keybindFrame = CreateFrame("Frame")
keybindFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
keybindFrame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
keybindFrame:RegisterEvent("UPDATE_BINDINGS")
keybindFrame:RegisterEvent("SPELLS_CHANGED")
keybindFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
keybindFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
keybindFrame:SetScript("OnEvent", function() keybindCacheDirty = true end)

local function GetKeybindForSpell(spellID)
    if keybindCacheDirty then RebuildKeybindCache() end
    local key = keybindCache[spellID]
    if key then return key end
    local nameKey = ResolveSpellNameFromID(spellID)
    if nameKey then
        key = keybindNameCache[nameKey]
        if key then return key end
    end

    -- Best-effort texture fallback: icon IDs are not unique per spell,
    -- so this can misattribute a keybind when spells share an icon.
    if C_Spell_GetSpellTexture then
        local texture = C_Spell_GetSpellTexture(spellID)
        if texture then
            key = keybindTextureCache[texture]
            if key then
                keybindCache[spellID] = key
                if nameKey then
                    keybindNameCache[nameKey] = key
                end
                return key
            end
        end
    end
    return nil
end

local function GetActionSlotForSpell(spellID)
    if keybindCacheDirty then RebuildKeybindCache() end
    local slot = actionSlotCache[spellID]
    if slot then return slot end
    local nameKey = ResolveSpellNameFromID(spellID)
    if nameKey then
        slot = actionSlotNameCache[nameKey]
        if slot then return slot end
    end
    if C_Spell_GetSpellTexture then
        local texture = C_Spell_GetSpellTexture(spellID)
        if texture then
            slot = actionSlotTextureCache[texture]
            if slot then
                actionSlotCache[spellID] = slot
                if nameKey then
                    actionSlotNameCache[nameKey] = slot
                end
                return slot
            end
        end
    end
    return nil
end

local function FormatKeybindForDisplay(key)
    if type(key) ~= "string" then
        return ""
    end
    key = key:gsub("SHIFT%-", "S-")
    key = key:gsub("CTRL%-", "C-")
    key = key:gsub("ALT%-", "A-")
    return key
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
    if frame.cooldown.SetSwipeColor then frame.cooldown:SetSwipeColor(0, 0, 0, 0.6) end
    frame.cooldown:Hide()

    -- Charge cooldown: edge ring above primary CD for charge-based spells
    frame.chargeCooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.chargeCooldown:ClearAllPoints()
    frame.chargeCooldown:SetPoint("TOPLEFT", frame, "TOPLEFT", ICON_TEXTURE_INSET, -ICON_TEXTURE_INSET)
    frame.chargeCooldown:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -ICON_TEXTURE_INSET, ICON_TEXTURE_INSET)
    frame.chargeCooldown:SetHideCountdownNumbers(true)
    if frame.chargeCooldown.SetDrawBling then frame.chargeCooldown:SetDrawBling(false) end
    if frame.chargeCooldown.SetDrawSwipe then frame.chargeCooldown:SetDrawSwipe(false) end
    if frame.chargeCooldown.SetDrawEdge then frame.chargeCooldown:SetDrawEdge(true) end
    frame.chargeCooldown:SetFrameLevel(frame.cooldown:GetFrameLevel() + 1)
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

    -- Override glow: pulsing overlay when TrueShot overrides AC
    frame.glow = frame:CreateTexture(nil, "OVERLAY", nil, 2)
    frame.glow:SetAllPoints()
    frame.glow:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover")
    frame.glow:SetBlendMode("ADD")
    frame.glow:SetAlpha(0)
    frame.glow:Hide()

    frame.glowAnim = frame.glow:CreateAnimationGroup()
    frame.glowAnim:SetLooping("BOUNCE")
    local fadeIn = frame.glowAnim:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0.3)
    fadeIn:SetToAlpha(0.9)
    fadeIn:SetDuration(0.4)
    fadeIn:SetOrder(1)
    fadeIn:SetSmoothing("IN_OUT")

    if MasqueGroup then
        -- Masque owns background and border; hide native versions
        frame.slotBackground:Hide()
        frame.border:Hide()

        MasqueGroup:AddButton(frame, {
            Icon = frame.texture,
            Cooldown = frame.cooldown,
            ChargeCooldown = frame.chargeCooldown,
            HotKey = frame.keybind,
            Normal = frame.border,
        }, "Frame")
    end

    if index > 1 then
        frame:SetAlpha(0.7)
    end

    frame:Hide()
    return frame
end

local GLOW_COLORS = {
    pin    = { 0.0, 0.8, 1.0 },
    prefer = { 0.4, 0.6, 1.0 },
}

local function HideGlow(icon)
    if not icon or not icon.glow then return end
    icon.glowAnim:Stop()
    icon.glow:Hide()
end

local function ShowGlow(icon, source)
    if not icon or not icon.glow then return end
    local color = GLOW_COLORS[source]
    if not color then
        HideGlow(icon)
        return
    end
    icon.glow:SetVertexColor(color[1], color[2], color[3], 1.0)
    icon.glow:Show()
    if not icon.glowAnim:IsPlaying() then
        icon.glowAnim:Play()
    end
end

------------------------------------------------------------------------
-- AoE hint sub-icon (anchored below icon 1)
------------------------------------------------------------------------

local aoeHintIcon
local aoeHintDisplayed = nil   -- currently shown spell
local aoeHintPending = nil     -- candidate spell awaiting stabilization
local aoeHintPendingTicks = 0

local function CreateAoeHintIcon()
    local size = TrueShot.GetOpt("iconSize") or 40
    local frame = CreateFrame("Frame", "TrueShotAoeHint", content)
    frame:SetSize(size, size)

    frame.slotBackground = frame:CreateTexture(nil, "BACKGROUND")
    frame.slotBackground:SetAllPoints()
    frame.slotBackground:SetAtlas("UI-HUD-ActionBar-IconFrame-Background")

    frame.texture = frame:CreateTexture(nil, "ARTWORK")
    frame.texture:SetPoint("TOPLEFT", frame, "TOPLEFT", ICON_TEXTURE_INSET, -ICON_TEXTURE_INSET)
    frame.texture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -ICON_TEXTURE_INSET, ICON_TEXTURE_INSET)
    frame.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    frame.border = frame:CreateTexture(nil, "OVERLAY")
    frame.border:SetAllPoints()
    frame.border:SetAtlas("UI-HUD-ActionBar-IconFrame")

    frame.keybind = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    frame.keybind:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    frame.keybind:SetJustifyH("RIGHT")

    -- Pulsing AoE glow
    frame.glow = frame:CreateTexture(nil, "OVERLAY", nil, 2)
    frame.glow:SetAllPoints()
    frame.glow:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover")
    frame.glow:SetVertexColor(1.0, 0.5, 0.1, 1.0) -- orange
    frame.glow:SetBlendMode("ADD")
    frame.glow:SetAlpha(0)
    frame.glow:Hide()

    frame.glowAnim = frame.glow:CreateAnimationGroup()
    frame.glowAnim:SetLooping("BOUNCE")
    local glowFade = frame.glowAnim:CreateAnimation("Alpha")
    glowFade:SetFromAlpha(0.25)
    glowFade:SetToAlpha(0.75)
    glowFade:SetDuration(0.5)
    glowFade:SetOrder(1)
    glowFade:SetSmoothing("IN_OUT")

    -- Scale bounce on appear
    frame.bounceAnim = frame:CreateAnimationGroup()
    local scaleUp = frame.bounceAnim:CreateAnimation("Scale")
    scaleUp:SetScale(1.35, 1.35)
    scaleUp:SetDuration(0.12)
    scaleUp:SetOrder(1)
    scaleUp:SetSmoothing("OUT")
    local scaleDown = frame.bounceAnim:CreateAnimation("Scale")
    scaleDown:SetScale(1 / 1.35, 1 / 1.35)
    scaleDown:SetDuration(0.15)
    scaleDown:SetOrder(2)
    scaleDown:SetSmoothing("IN")

    frame:SetAlpha(1)
    frame:Hide()
    return frame
end

local function RenderAoeHint(spellID)
    local wasHidden = not aoeHintIcon or not aoeHintIcon:IsShown()
    local prevSpell = aoeHintDisplayed
    aoeHintDisplayed = spellID

    if not spellID then
        if aoeHintIcon then
            if aoeHintIcon.glowAnim then aoeHintIcon.glowAnim:Stop() end
            if aoeHintIcon.glow then aoeHintIcon.glow:Hide() end
            aoeHintIcon:Hide()
        end
        return
    end

    if not aoeHintIcon then
        aoeHintIcon = CreateAoeHintIcon()
    end

    local texture = C_Spell_GetSpellTexture and C_Spell_GetSpellTexture(spellID)
    if not texture then
        aoeHintIcon.glowAnim:Stop()
        aoeHintIcon.glow:Hide()
        aoeHintIcon:Hide()
        return
    end

    -- Only show when icon 1 is visible
    if not icons[1] or not icons[1]:IsShown() then
        aoeHintIcon.glowAnim:Stop()
        aoeHintIcon.glow:Hide()
        aoeHintIcon:Hide()
        return
    end

    local iconSize = TrueShot.GetOpt("iconSize") or 40
    local spacing = TrueShot.GetOpt("iconSpacing") or 4
    local orient = TrueShot.GetOpt("orientation") or "LEFT"
    aoeHintIcon:SetSize(iconSize, iconSize)
    aoeHintIcon:SetAlpha(1)
    aoeHintIcon:ClearAllPoints()
    if orient == "DOWN" then
        aoeHintIcon:SetPoint("RIGHT", icons[1], "LEFT", -spacing, 0)
    elseif orient == "UP" then
        aoeHintIcon:SetPoint("LEFT", icons[1], "RIGHT", spacing, 0)
    else
        aoeHintIcon:SetPoint("TOP", icons[1], "BOTTOM", 0, -spacing)
    end

    aoeHintIcon.texture:SetTexture(texture)

    if TrueShot.GetOpt("showKeybinds") then
        local key = GetKeybindForSpell(spellID)
        aoeHintIcon.keybind:SetText(FormatKeybindForDisplay(key))
    else
        aoeHintIcon.keybind:SetText("")
    end

    aoeHintIcon:Show()

    -- Animate on first appear or spell change
    if wasHidden or prevSpell ~= spellID then
        aoeHintIcon.glow:Show()
        if not aoeHintIcon.glowAnim:IsPlaying() then
            aoeHintIcon.glowAnim:Play()
        end
        aoeHintIcon.bounceAnim:Stop()
        aoeHintIcon.bounceAnim:Play()
    end
end

local function UpdateAoeHintIcon(spellID)
    if not TrueShot.GetOpt("showAoeHint") then
        RenderAoeHint(nil)
        aoeHintPending = nil
        aoeHintPendingTicks = 0
        return
    end

    -- Same spell as currently displayed: nothing to stabilize
    if spellID == aoeHintDisplayed then
        aoeHintPending = nil
        aoeHintPendingTicks = 0
        return
    end

    -- New candidate: require QUEUE_STABILIZATION_TICKS consecutive ticks
    if spellID == aoeHintPending then
        aoeHintPendingTicks = aoeHintPendingTicks + 1
    else
        aoeHintPending = spellID
        aoeHintPendingTicks = 1
    end

    if aoeHintPendingTicks >= QUEUE_STABILIZATION_TICKS then
        RenderAoeHint(spellID)
        aoeHintPending = nil
        aoeHintPendingTicks = 0
    end
end

local function ResetAoeHintStabilization()
    aoeHintPending = nil
    aoeHintPendingTicks = 0
end

------------------------------------------------------------------------
-- HeartbeatStrip: scrolling GCD rhythm visualization
------------------------------------------------------------------------

local HEARTBEAT_BAR_COUNT = 30
local HEARTBEAT_TIME_WINDOW = 15
local HEARTBEAT_BAR_WIDTH = 4
local HEARTBEAT_BAR_HEIGHT_RATIO = 0.5
local HEARTBEAT_FREEZE_DURATION = 5

local heartbeatHasCustomPos = false

-- Heartbeat strip frame (independent of container for separate positioning)
local heartbeatFrame = CreateFrame("Frame", "TrueShotHeartbeat", UIParent, "BackdropTemplate")
heartbeatFrame:SetSize(200, 20)
heartbeatFrame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
})
heartbeatFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.7)
heartbeatFrame:SetMovable(true)
heartbeatFrame:SetClampedToScreen(true)
heartbeatFrame:RegisterForDrag("LeftButton")
heartbeatFrame:SetScript("OnDragStart", function(self)
    if not TrueShot.GetOpt("locked") then
        self:StartMoving()
    end
end)
heartbeatFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    TrueShot.SetOpt("heartbeatPosPoint", point)
    TrueShot.SetOpt("heartbeatPosRelPoint", relPoint)
    TrueShot.SetOpt("heartbeatPosX", x)
    TrueShot.SetOpt("heartbeatPosY", y)
    heartbeatHasCustomPos = true
end)
heartbeatFrame:Hide()

local function RestoreHeartbeatPosition()
    local point = TrueShot.GetOpt("heartbeatPosPoint")
    local relPoint = TrueShot.GetOpt("heartbeatPosRelPoint")
    local x = TrueShot.GetOpt("heartbeatPosX")
    local y = TrueShot.GetOpt("heartbeatPosY")
    if point and relPoint and x and y then
        heartbeatFrame:ClearAllPoints()
        heartbeatFrame:SetPoint(point, UIParent, relPoint, x, y)
        heartbeatHasCustomPos = true
    else
        heartbeatHasCustomPos = false
    end
end

RestoreHeartbeatPosition()

local heartbeatThrottle = 0

local heartbeatBars = {}
for i = 1, HEARTBEAT_BAR_COUNT do
    local bar = heartbeatFrame:CreateTexture(nil, "ARTWORK")
    bar:SetSize(HEARTBEAT_BAR_WIDTH, 16)
    bar:SetColorTexture(1, 1, 1, 1)
    bar:Hide()
    heartbeatBars[i] = bar
end

local HEARTBEAT_COLORS = {
    match      = { 0.2, 0.9, 0.3, 0.9 },
    soft_match = { 0.3, 0.8, 0.9, 0.9 },
    miss       = { 0.9, 0.8, 0.2, 0.9 },
    unscored   = { 0.5, 0.5, 0.5, 0.35 },
    gap        = { 0.9, 0.2, 0.2, 0.8 },
}

local heartbeatFrozenUntil = 0

local function UpdateHeartbeatStrip()
    if not TrueShot.GetOpt("showHeartbeat") then
        heartbeatFrame:Hide()
        return
    end

    -- Hide if overlay is explicitly disabled during combat (e.g. /ts hide)
    -- but allow post-combat freeze to play out
    if not displayEnabled and UnitAffectingCombat("player") then
        heartbeatFrame:Hide()
        heartbeatFrozenUntil = 0
        return
    end

    local trace = TrueShot.CombatTrace
    if not trace or trace:GetEventCount() == 0 then
        heartbeatFrame:Hide()
        return
    end

    local now = GetTime()

    local inCombat = UnitAffectingCombat("player")
    if not inCombat then
        if heartbeatFrozenUntil == 0 then
            heartbeatFrozenUntil = now + HEARTBEAT_FREEZE_DURATION
        end
        if now > heartbeatFrozenUntil then
            heartbeatFrame:Hide()
            heartbeatFrozenUntil = 0
            return
        end
    else
        heartbeatFrozenUntil = 0
    end

    local recentEvents = trace:GetRecentEvents(HEARTBEAT_BAR_COUNT)
    local barHeight = math.max(12, (TrueShot.GetOpt("iconSize") or 40) * HEARTBEAT_BAR_HEIGHT_RATIO)

    local stripWidth = HEARTBEAT_BAR_COUNT * (HEARTBEAT_BAR_WIDTH + 1)
    heartbeatFrame:SetSize(stripWidth, barHeight)

    -- Only set default position if user hasn't dragged it somewhere custom
    if not heartbeatHasCustomPos then
        heartbeatFrame:ClearAllPoints()
        local orient = TrueShot.GetOpt("orientation") or "LEFT"
        local anchorBelow = (aoeHintIcon and aoeHintIcon:IsShown()) and aoeHintIcon or container
        if orient == "UP" then
            heartbeatFrame:SetPoint("TOP", anchorBelow, "BOTTOM", 0, -4)
        elseif orient == "DOWN" then
            heartbeatFrame:SetPoint("BOTTOM", anchorBelow, "TOP", 0, 4)
        else
            heartbeatFrame:SetPoint("TOPLEFT", anchorBelow, "BOTTOMLEFT", 0, -4)
        end
    end

    -- Match container scale
    heartbeatFrame:SetScale(TrueShot.GetOpt("overlayScale") or 1.0)

    local referenceTime = inCombat and now or (heartbeatFrozenUntil - HEARTBEAT_FREEZE_DURATION)

    for i = 1, HEARTBEAT_BAR_COUNT do
        local bar = heartbeatBars[i]
        local event = recentEvents[#recentEvents - i + 1]

        if event and event.t > 0 then
            local age = referenceTime - event.t
            if age >= 0 and age <= HEARTBEAT_TIME_WINDOW then
                local color = HEARTBEAT_COLORS[event.classification] or HEARTBEAT_COLORS.unscored
                bar:SetVertexColor(color[1], color[2], color[3], color[4])
                bar:SetSize(HEARTBEAT_BAR_WIDTH, barHeight)

                local xPos = stripWidth - (age / HEARTBEAT_TIME_WINDOW) * stripWidth
                bar:ClearAllPoints()
                bar:SetPoint("BOTTOM", heartbeatFrame, "BOTTOMLEFT", xPos, 0)
                bar:Show()
            else
                bar:Hide()
            end
        else
            bar:Hide()
        end
    end

    heartbeatFrame:EnableMouse(not TrueShot.GetOpt("locked"))
    heartbeatFrame:Show()
end

-- Self-update: keeps heartbeat alive when container is hidden (post-combat freeze)
heartbeatFrame:SetScript("OnUpdate", function(_, elapsed)
    heartbeatThrottle = heartbeatThrottle + elapsed
    if heartbeatThrottle < 0.1 then return end
    heartbeatThrottle = 0
    if not container:IsShown() then
        UpdateHeartbeatStrip()
    end
end)

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
    local showWhyAboveIcon = TrueShot.GetOpt("showWhyAboveIcon") and true or false
    if isVertical then
        reasonText:SetPoint("LEFT", container, "RIGHT", 4, -8)
        reasonText:SetJustifyH("LEFT")
        phaseText:SetPoint("LEFT", container, "RIGHT", 4, 8)
        phaseText:SetJustifyH("LEFT")
    else
        if showWhyAboveIcon then
            reasonText:SetPoint("BOTTOM", container, "TOP", 0, 2)
            phaseText:SetPoint("BOTTOM", container, "TOP", 0, 14)
        else
            reasonText:SetPoint("TOP", container, "BOTTOM", 0, -2)
            phaseText:SetPoint("BOTTOM", container, "TOP", 0, 2)
        end
        reasonText:SetJustifyH("CENTER")
        phaseText:SetJustifyH("CENTER")
    end

    LayoutIcons()
end

function Display:GetPositionOffsets()
    local point, relativeTo, relativePoint, xOfs, yOfs = container:GetPoint(1)
    if not point then
        return nil
    end

    local relativeName
    if relativeTo and relativeTo.GetName then
        relativeName = relativeTo:GetName()
    end
    if not relativeName or relativeName == "" then
        relativeName = "UIParent"
    end

    return point, relativeName, relativePoint, xOfs or 0, yOfs or 0
end

function Display:SetPositionOffsets(xOfs, yOfs)
    xOfs = tonumber(xOfs)
    yOfs = tonumber(yOfs)
    if not xOfs or not yOfs then
        return false
    end

    local point, relativeTo, relativePoint = container:GetPoint(1)
    point = point or "CENTER"
    relativePoint = relativePoint or point
    relativeTo = relativeTo or UIParent

    container:ClearAllPoints()
    container:SetPoint(point, relativeTo, relativePoint, xOfs, yOfs)

    TrueShot.SetOpt("posPoint", point)
    TrueShot.SetOpt("posRelPoint", relativePoint)
    TrueShot.SetOpt("posX", xOfs)
    TrueShot.SetOpt("posY", yOfs)
    return true
end

function Display:SaveCurrentPosition()
    local point, _, relativePoint, xOfs, yOfs = container:GetPoint(1)
    if point then
        TrueShot.SetOpt("posPoint", point)
        TrueShot.SetOpt("posRelPoint", relativePoint or point)
        TrueShot.SetOpt("posX", xOfs or 0)
        TrueShot.SetOpt("posY", yOfs or 0)
    end
end

function Display:RestorePosition()
    local point = TrueShot.GetOpt("posPoint")
    local relPoint = TrueShot.GetOpt("posRelPoint")
    local x = TrueShot.GetOpt("posX")
    local y = TrueShot.GetOpt("posY")
    if point and x and y then
        container:ClearAllPoints()
        container:SetPoint(point, UIParent, relPoint or point, x, y)
    end
end

function Display:ApplyOptions()
    self:UpdateContainerSize()
    self:RestorePosition()
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
    if not TrueShot.GetOpt("showCooldownSwipe") or not spellID then
        ClearCooldown(icon)
        return
    end

    local actionSlot = GetActionSlotForSpell(spellID)

    -- Prefer slot-based cooldown state when available; this matches the visible
    -- action button more closely than spell-based secret cooldown data.
    local shouldShow = false
    local actionBarResolved = false
    if actionSlot and C_ActionBar_GetActionCooldown then
        local ok, cooldown = pcall(C_ActionBar_GetActionCooldown, actionSlot)
        if ok and cooldown then
            if cooldown.isActive ~= nil and not (issecretvalue and issecretvalue(cooldown.isActive)) then
                shouldShow = cooldown.isActive == true
                actionBarResolved = true
            else
                local startTime = cooldown.startTime or 0
                local duration = cooldown.duration or 0
                if not (issecretvalue and (issecretvalue(startTime) or issecretvalue(duration))) then
                    shouldShow = startTime > 0 and duration >= MIN_COOLDOWN_SWIPE_DURATION
                    actionBarResolved = true
                end
            end
        end
    end
    if not actionBarResolved and C_Spell_GetSpellCooldown then
        local ok, cooldown = pcall(C_Spell_GetSpellCooldown, spellID)
        if ok and cooldown then
            local startTime = cooldown.startTime or 0
            local duration = cooldown.duration or 0
            -- If values are secret, still allow DurationObject path (it handles secrets)
            local valuesReadable = not (issecretvalue and
                (issecretvalue(startTime) or issecretvalue(duration)))
            if valuesReadable then
                shouldShow = startTime > 0 and duration >= MIN_COOLDOWN_SWIPE_DURATION
            else
                shouldShow = true  -- trust DurationObject to handle it
            end
        end
    end

    if not shouldShow then
        ClearCooldown(icon)
        return
    end

    -- Prefer DurationObject path (secret-safe, available since build 66562)
    if actionSlot and C_ActionBar_GetActionCooldownDuration and icon.cooldown.SetCooldownFromDurationObject then
        local ok, durObj = pcall(C_ActionBar_GetActionCooldownDuration, actionSlot)
        if ok and durObj then
            icon.cooldown:SetCooldownFromDurationObject(durObj)
            icon.cooldown:Show()
            return
        end
    end

    if C_Spell_GetSpellCooldownDuration and icon.cooldown.SetCooldownFromDurationObject then
        local ok, durObj = pcall(C_Spell_GetSpellCooldownDuration, spellID)
        if ok and durObj then
            icon.cooldown:SetCooldownFromDurationObject(durObj)
            icon.cooldown:Show()
            return
        end
    end

    -- Fallback: direct SetCooldown (pre-66562 or if DurationObject unavailable)
    if not C_Spell_GetSpellCooldown then
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
    if not TrueShot.GetOpt("showCooldownSwipe") or not spellID then
        icon.chargeCooldown:Hide()
        if icon.chargeCount then icon.chargeCount:Hide() end
        return
    end

    local actionSlot = GetActionSlotForSpell(spellID)

    -- Read charge info
    if not C_Spell_GetSpellCharges then
        icon.chargeCooldown:Hide()
        if icon.chargeCount then icon.chargeCount:Hide() end
        return
    end

    local ok, charges = pcall(C_Spell_GetSpellCharges, spellID)
    if not ok or not charges or not charges.maxCharges then
        icon.chargeCooldown:Hide()
        if icon.chargeCount then icon.chargeCount:Hide() end
        return
    end

    local current = charges.currentCharges
    local maxC = charges.maxCharges

    -- Secret check before any comparison (Finding 3: maxCharges > 1
    -- must not run on a secret value)
    if issecretvalue and (issecretvalue(current) or issecretvalue(maxC)) then
        -- Secret: passthrough count for display, skip edge ring
        icon.chargeCount:SetText(current)
        icon.chargeCount:Show()
        icon.chargeCooldown:Hide()
        return
    end

    if (maxC or 0) <= 1 then
        icon.chargeCooldown:Hide()
        if icon.chargeCount then icon.chargeCount:Hide() end
        return
    end

    -- Show charge count and edge ring only when regenerating
    if current < maxC then
        icon.chargeCount:SetText(current)
        icon.chargeCount:Show()

        -- Prefer DurationObject for the edge ring (secret-safe)
        if actionSlot and C_ActionBar_GetActionChargeDuration and icon.chargeCooldown.SetCooldownFromDurationObject then
            local durOk, durObj = pcall(C_ActionBar_GetActionChargeDuration, actionSlot)
            if durOk and durObj then
                icon.chargeCooldown:SetCooldownFromDurationObject(durObj)
                icon.chargeCooldown:Show()
                return
            end
        end

        if C_Spell_GetSpellChargeDuration and icon.chargeCooldown.SetCooldownFromDurationObject then
            local durOk, durObj = pcall(C_Spell_GetSpellChargeDuration, spellID)
            if durOk and durObj then
                icon.chargeCooldown:SetCooldownFromDurationObject(durObj)
                icon.chargeCooldown:Show()
                return
            end
        end

        -- Fallback: direct SetCooldown with secret guards (Finding 2)
        local startTime = charges.cooldownStartTime
        local duration = charges.cooldownDuration
        if startTime and duration then
            if issecretvalue and (issecretvalue(startTime) or issecretvalue(duration)) then
                icon.chargeCooldown:Hide()
                return
            end
            local modRate = charges.chargeModRate or 1.0
            if issecretvalue and issecretvalue(modRate) then modRate = 1.0 end
            icon.chargeCooldown:SetCooldown(startTime, duration, modRate)
            icon.chargeCooldown:Show()
        else
            icon.chargeCooldown:Hide()
        end
    else
        icon.chargeCooldown:Hide()
        icon.chargeCount:Hide()
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

            -- If texture is nil (Midnight secret/intermittent), keep existing
            -- texture visible instead of hiding the icon
            if texture then
                icon.texture:SetTexture(texture)
            end

            if texture or (icon:IsShown() and icon.spellID == spellID) then
                -- Keybinds toggle
                if TrueShot.GetOpt("showKeybinds") then
                    local key = GetKeybindForSpell(spellID)
                    icon.keybind:SetText(FormatKeybindForDisplay(key))
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

    -- AoE hint sub-icon
    UpdateAoeHintIcon(meta and meta.aoeHintSpell)

    -- Override glow: pulse position 1 when TrueShot overrides AC
    if icons[1] and icons[1].border then
        icons[1].border:SetVertexColor(1.0, 1.0, 1.0, 1.0)
    end
    if TrueShot.GetOpt("showOverrideIndicator") and icons[1] then
        if meta and (meta.source == "pin" or meta.source == "prefer") then
            ShowGlow(icons[1], meta.source)
        else
            HideGlow(icons[1])
        end
    elseif icons[1] then
        HideGlow(icons[1])
    end

end

function Display:RenderQueueNow(queue)
    self:UpdateQueue(queue)
    StoreQueue(displayedQueueState, queue, TrueShot.GetOpt("iconCount"))
    -- Snapshot committed metadata for analytics
    local meta = Engine.lastQueueMeta
    committedMeta.source = meta.source
    committedMeta.reason = meta.reason
    ClearPendingQueue()
    allowImmediateQueueUpdate = false
end

function Display:ResetQueueStabilization()
    ClearPendingQueue()
    allowImmediateQueueUpdate = false
end

function Display:FlushQueueStabilization()
    ClearPendingQueue()
    allowImmediateQueueUpdate = true
end

function Display:ConsumeQueueUpdate(queue, inCombat)
    local count = TrueShot.GetOpt("iconCount")

    if not inCombat then
        self:RenderQueueNow(queue)
        return
    end

    if allowImmediateQueueUpdate then
        self:RenderQueueNow(queue)
        return
    end

    if QueuesMatch(displayedQueueState, queue, count) then
        ClearPendingQueue()
        -- Still run UpdateQueue for per-tick visuals (cooldown swipes, cast feedback, range tint)
        self:UpdateQueue(queue)
        return
    end

    if QueuesMatch(pendingQueueState, queue, count) then
        pendingQueueTicks = pendingQueueTicks + 1
    else
        StoreQueue(pendingQueueState, queue, count)
        pendingQueueTicks = 1
    end

    -- Hiding (empty queue) requires more ticks than switching spells
    local isHiding = (#queue == 0) and (displayedQueueState.count or 0) > 0
    local threshold = isHiding and QUEUE_HIDE_STABILIZATION_TICKS or QUEUE_STABILIZATION_TICKS

    if pendingQueueTicks >= threshold then
        self:RenderQueueNow(queue)
    else
        -- Pending but not stable yet: refresh visuals with currently displayed spells
        self:UpdateQueue(displayedQueueState)
    end
end

function Display:OnSpellCastSucceeded(spellID)
    -- Record cast for analytics BEFORE queue recompute
    -- icons[1].spellID is the committed, stabilized recommendation the player saw
    if TrueShot.CombatTrace and UnitAffectingCombat("player") then
        local displayedSpell = icons[1] and icons[1].spellID or 0
        -- Build dense queue (no holes) for reliable soft-match iteration
        local displayedQueue = {}
        local count = TrueShot.GetOpt("iconCount")
        for i = 1, count do
            if icons[i] and icons[i].spellID then
                displayedQueue[#displayedQueue + 1] = icons[i].spellID
            end
        end
        -- Use committedMeta (snapshotted at RenderQueueNow) not Engine.lastQueueMeta
        TrueShot.CombatTrace:RecordCast(
            spellID,
            displayedSpell,
            committedMeta.source or "ac",
            committedMeta.reason,
            displayedQueue
        )
    end

    if TrueShot.GetOpt("showCastFeedback") then
        local now = GetTime()
        for _, icon in ipairs(icons) do
            if icon.spellID == spellID then
                icon.successUntil = now + SUCCESS_FLASH_DURATION
                self:UpdateCastFeedback(icon, now)
            end
        end
    end

    self:FlushQueueStabilization()

    if container:IsShown() then
        local queue = Engine:ComputeQueue(TrueShot.GetOpt("iconCount"))
        self:ConsumeQueueUpdate(queue, UnitAffectingCombat("player"))
    end
end

------------------------------------------------------------------------
-- Update throttle (tiered: combat 10Hz, idle 2Hz, hidden 0Hz)
------------------------------------------------------------------------

local COMBAT_INTERVAL = 0.1      -- 10 Hz in combat or hostile target
local IDLE_INTERVAL = 0.5        -- 2 Hz out of combat with no hostile target
local timeSinceUpdate = 0

-- Force next tick to fire immediately by resetting the throttle timer.
function Display:MarkDirty()
    timeSinceUpdate = IDLE_INTERVAL
end

local UnitAffectingCombat = UnitAffectingCombat
local UnitExists = UnitExists
local UnitCanAttack = UnitCanAttack

local function OnUpdateHandler(_, elapsed)
    timeSinceUpdate = timeSinceUpdate + elapsed

    if not container:IsShown() then return end

    local inCombat = UnitAffectingCombat("player")
    local hasHostile = UnitExists("target") and UnitCanAttack("player", "target")
    local interval = (inCombat or hasHostile) and COMBAT_INTERVAL or IDLE_INTERVAL

    if timeSinceUpdate < interval then return end
    timeSinceUpdate = 0

    local queue = Engine:ComputeQueue(TrueShot.GetOpt("iconCount"))
    Display:ConsumeQueueUpdate(queue, inCombat)
    UpdateHeartbeatStrip()
end

function Display:Enable()
    if displayEnabled then return end
    displayEnabled = true
    EnsureIcons()
    self:ApplyOptions()
    container:EnableMouse(not TrueShot.GetOpt("locked"))
    container:Show()
    self:FlushQueueStabilization()
    timeSinceUpdate = IDLE_INTERVAL
    container:SetScript("OnUpdate", OnUpdateHandler)
end

function Display:Disable()
    if not displayEnabled then return end
    displayEnabled = false
    self:ResetQueueStabilization()
    ResetStoredQueue(displayedQueueState)
    container:SetScript("OnUpdate", nil)
    -- Don't kill heartbeat here -- self-OnUpdate handles post-combat freeze
    container:Hide()
    if aoeHintIcon then aoeHintIcon:Hide() end
end

function Display:SetClickThrough(locked)
    container:EnableMouse(not locked)
end

function Display:ResetPosition()
    container:ClearAllPoints()
    container:SetPoint("CENTER", UIParent, "CENTER", 0, -50)
    TrueShot.SetOpt("posPoint", nil)
    TrueShot.SetOpt("posRelPoint", nil)
    TrueShot.SetOpt("posX", nil)
    TrueShot.SetOpt("posY", nil)
end

TrueShot.RegisterOptCallback(function(key)
    Display:ApplyOptions()
    Display:MarkDirty()
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
