-- HunterFlow Display: presentation layer for the queue overlay

local Engine = HunterFlow.Engine

HunterFlow.Display = {}
local Display = HunterFlow.Display

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

Display.container = container

------------------------------------------------------------------------
-- Icons
------------------------------------------------------------------------

local icons = {}

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
        container, "BackdropTemplate")
    frame:SetSize(size, size)
    frame:SetPoint("LEFT", container, "LEFT",
        (index - 1) * (size + spacing), 0)

    frame.texture = frame:CreateTexture(nil, "ARTWORK")
    frame.texture:SetAllPoints()
    frame.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    frame.keybind = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    frame.keybind:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    frame.keybind:SetJustifyH("RIGHT")

    -- TODO: GCD sweep needs SecureDelegate research

    frame.border = frame:CreateTexture(nil, "OVERLAY")
    frame.border:SetAllPoints()
    frame.border:SetAtlas("UI-HUD-ActionBar-IconFrame")

    if index > 1 then
        frame:SetAlpha(0.7)
    end

    frame:Hide()
    return frame
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
    container:SetSize(count * size + (count - 1) * spacing, size)
end

function Display:UpdateQueue(queue)
    EnsureIcons()
    local count = HunterFlow.GetOpt("iconCount")

    for i = 1, count do
        local icon = icons[i]
        local spellID = queue[i]

        if spellID then
            local texture = C_Spell.GetSpellTexture(spellID)
            if texture then
                icon.texture:SetTexture(texture)
                local key = GetKeybindForSpell(spellID)
                icon.keybind:SetText(key or "")
                icon:Show()
            else
                icon:Hide()
            end
        else
            icon:Hide()
        end
    end
end

------------------------------------------------------------------------
-- Update throttle
------------------------------------------------------------------------

local UPDATE_INTERVAL = 0.1
local timeSinceUpdate = 0

function Display:Enable()
    self:UpdateContainerSize()
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
