# Display JAC-Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade TrueShot's queue overlay to match Just Assisted Combat's standard queue look and feel (Masque, first-icon-scale, orientation, glow, charge cooldown, backdrop toggle).

**Architecture:** All changes are in the Display layer. Engine and Profile code is untouched. New settings are added to Core.lua DEFAULTS and exposed via SettingsPanel.lua. Display.lua gets the bulk of the work: Masque init, reworked CreateIcon/LayoutIcons, glow AnimationGroup, charge cooldown frame, and backdrop toggle.

**Tech Stack:** WoW Lua (Interface 120000), Masque (optional via LibStub), Blizzard Atlas textures, AnimationGroup API, C_Spell.GetSpellCharges.

---

## File Structure

| File | Role | Changes |
|------|------|---------|
| `Core.lua` | Defaults & saved vars | Add 3 new defaults |
| `TrueShot.toc` | Addon manifest | Add `## OptionalDeps: Masque` |
| `Display.lua` | Queue rendering | Masque init, CreateIcon (charge CD, glow overlay), LayoutIcons (orientation + first-icon-scale), UpdateQueue (charge CD, glow, backdrop), backdrop toggle |
| `SettingsPanel.lua` | Options UI | Add firstIconScale slider, orientation dropdown, showBackdrop checkbox |

---

### Task 1: Add new defaults and TOC OptionalDeps

**Files:**
- Modify: `Core.lua:12-30`
- Modify: `TrueShot.toc:1-7`

- [ ] **Step 1: Add three new defaults to Core.lua DEFAULTS table**

In `Core.lua`, add these entries inside the `DEFAULTS` table (after `overlayOpacity`):

```lua
    firstIconScale = 1.3,
    orientation = "LEFT",
    showBackdrop = true,
```

- [ ] **Step 2: Add OptionalDeps to TrueShot.toc**

Add this line after `## SavedVariables: TrueShotDB`:

```
## OptionalDeps: Masque
```

- [ ] **Step 3: Commit**

```bash
git add Core.lua TrueShot.toc
git commit -m "feat: add display upgrade defaults and Masque OptionalDeps"
```

---

### Task 2: Backdrop toggle

**Files:**
- Modify: `Display.lua:34-42` (container backdrop setup)
- Modify: `Display.lua:224-229` (ApplyOptions)
- Modify: `SettingsPanel.lua` (new checkbox)

This is the simplest visual change and can be verified immediately in-game.

- [ ] **Step 1: Add backdrop toggle to ApplyOptions in Display.lua**

Replace the current `Display:ApplyOptions` function at line 224:

```lua
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
```

- [ ] **Step 2: Add showBackdrop checkbox to SettingsPanel.lua**

After the last checkbox in the settings panel, add:

```lua
local showBackdropCheck = CreateCheckbox(panel, "Show Backdrop",
    "Show the dark background behind the queue overlay.",
    lastCheckbox, "showBackdrop")
```

(Where `lastCheckbox` is the preceding checkbox's variable name -- follow the existing pattern in the file.)

- [ ] **Step 3: In-game test**

Load addon, toggle `/ts` settings. Verify:
- Backdrop visible by default
- Unchecking hides backdrop but icons/text remain fully visible
- Re-checking restores backdrop

- [ ] **Step 4: Commit**

```bash
git add Display.lua SettingsPanel.lua
git commit -m "feat: add optional backdrop toggle for clean floating-icons look"
```

---

### Task 3: Queue orientation and first-icon-scale in LayoutIcons

**Files:**
- Modify: `Display.lua:125-222` (CreateIcon, LayoutIcons, UpdateContainerSize)
- Modify: `Display.lua:53-63` (reasonText/phaseText anchors)
- Modify: `SettingsPanel.lua` (orientation dropdown, firstIconScale slider)

- [ ] **Step 1: Rewrite LayoutIcons to support orientation and first-icon-scale**

Replace the `LayoutIcons()` function at line 189:

```lua
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

        -- Offset: first icon at 0, icon 2 at effectiveFirst + spacing,
        -- icon N at effectiveFirst + spacing + (N-2) * (size + spacing)
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
```

- [ ] **Step 2: Rewrite UpdateContainerSize for orientation**

Replace `Display:UpdateContainerSize` at line 211:

```lua
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

    -- Reposition reason/phase labels based on orientation
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
```

- [ ] **Step 3: Add settings panel controls**

Add to SettingsPanel.lua:

Orientation dropdown (after existing controls):
```lua
local orientLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
orientLabel:SetPoint("TOPLEFT", lastControl, "BOTTOMLEFT", 0, -18)
orientLabel:SetText("Queue Orientation")

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
```

First-icon-scale slider (after orientation):
```lua
local scaleLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
scaleLabel:SetPoint("TOPLEFT", orientDropdown, "BOTTOMLEFT", 16, -18)
scaleLabel:SetText("First Icon Scale")

local scaleSlider = CreateFrame("Slider", "TrueShotFirstIconScale", panel,
    "OptionsSliderTemplate")
scaleSlider:SetPoint("TOPLEFT", scaleLabel, "BOTTOMLEFT", 0, -12)
scaleSlider:SetMinMaxValues(1.0, 2.0)
scaleSlider:SetValueStep(0.1)
scaleSlider:SetObeyStepOnDrag(true)
scaleSlider:SetValue(TrueShot.GetOpt("firstIconScale"))
scaleSlider.Low:SetText("1.0")
scaleSlider.High:SetText("2.0")
scaleSlider.Text:SetText(string.format("%.1f", TrueShot.GetOpt("firstIconScale")))
scaleSlider:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value * 10 + 0.5) / 10
    TrueShot.SetOpt("firstIconScale", value)
    self.Text:SetText(string.format("%.1f", value))
end)
```

- [ ] **Step 4: In-game test**

- Toggle each orientation (LEFT/RIGHT/UP/DOWN) with 2 and 4 icons
- Set firstIconScale to 1.0 (no change) and 2.0 (double size) and verify no overlap
- Verify reason/phase labels reposition for vertical orientations

- [ ] **Step 5: Commit**

```bash
git add Display.lua SettingsPanel.lua
git commit -m "feat: add queue orientation and first-icon-scale support"
```

---

### Task 4: Charge cooldown frame

**Files:**
- Modify: `Display.lua:125-187` (CreateIcon -- add chargeCooldown frame)
- Modify: `Display.lua:280-337` (UpdateQueue -- charge CD logic)

- [ ] **Step 1: Add chargeCooldown frame to CreateIcon**

In `CreateIcon()`, after the primary cooldown frame block (after line 162), add:

```lua
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
```

- [ ] **Step 2: Add charge cooldown helper**

Add a new method after `Display:UpdateCooldown`:

```lua
local C_Spell_GetSpellCharges = C_Spell and C_Spell.GetSpellCharges

function Display:UpdateChargeCooldown(icon, spellID)
    if not icon or not icon.chargeCooldown then return end
    if not TrueShot.GetOpt("showCooldownSwipe") or not spellID or not C_Spell_GetSpellCharges then
        icon.chargeCooldown:Hide()
        icon.chargeCount:Hide()
        return
    end

    local ok, charges = pcall(C_Spell_GetSpellCharges, spellID)
    if not ok or not charges or not charges.maxCharges or charges.maxCharges <= 1 then
        icon.chargeCooldown:Hide()
        icon.chargeCount:Hide()
        return
    end

    local current = charges.currentCharges or 0
    local maxC = charges.maxCharges or 1

    if issecretvalue and (issecretvalue(current) or issecretvalue(maxC)) then
        icon.chargeCooldown:Hide()
        icon.chargeCount:Hide()
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
```

- [ ] **Step 3: Call UpdateChargeCooldown in UpdateQueue**

In `Display:UpdateQueue`, after line 322 (`self:UpdateCooldown(icon, spellID)`), add:

```lua
                self:UpdateChargeCooldown(icon, spellID)
```

And in the hide paths (lines 327 and 332), add cleanup:

```lua
                icon.chargeCooldown:Hide()
                icon.chargeCount:Hide()
```

- [ ] **Step 4: Add ClearChargeCooldown to existing clear paths**

In the `ClearCooldown` function and the hide-all-icons loops (lines 339-345), also hide charge elements:

```lua
    if icon.chargeCooldown then icon.chargeCooldown:Hide() end
    if icon.chargeCount then icon.chargeCount:Hide() end
```

- [ ] **Step 5: In-game test**

- Target a dummy, verify Barbed Shot shows charge count (2)
- Use a charge, verify swipe appears at 0.4 opacity
- When full charges, no swipe
- Toggle showCooldownSwipe off: both primary and charge swipes hidden

- [ ] **Step 6: Commit**

```bash
git add Display.lua
git commit -m "feat: add charge cooldown display for multi-charge spells"
```

---

### Task 5: Glow system (AnimationGroup)

**Files:**
- Modify: `Display.lua:125-187` (CreateIcon -- add glow overlay)
- Modify: `Display.lua:365-374` (UpdateQueue -- replace border tint with glow)

- [ ] **Step 1: Add glow overlay and AnimationGroup to CreateIcon**

In `CreateIcon()`, after the `border` texture (after line 179), add:

```lua
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
```

- [ ] **Step 2: Add glow helper functions**

Add after the CreateIcon function:

```lua
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
```

- [ ] **Step 3: Replace border-tint logic in UpdateQueue**

Replace the override indicator block (lines 365-374) with:

```lua
    -- Override glow: pulse position 1 when TrueShot overrides AC
    if TrueShot.GetOpt("showOverrideIndicator") and icons[1] then
        if meta and (meta.source == "pin" or meta.source == "prefer") then
            ShowGlow(icons[1], meta.source)
        else
            HideGlow(icons[1])
        end
    elseif icons[1] then
        HideGlow(icons[1])
    end
```

Also reset the old border tint to white so it doesn't linger:

```lua
    if icons[1] and icons[1].border then
        icons[1].border:SetVertexColor(1.0, 1.0, 1.0, 1.0)
    end
```

- [ ] **Step 4: In-game test**

- Enable a Dark Ranger profile with Black Arrow PIN rule
- During Withering Fire: position 1 should pulse cyan
- During PREFER (BA ready, no WF): position 1 should pulse soft blue
- When AC controls position 1: no glow
- Toggle showOverrideIndicator off: glow disappears

- [ ] **Step 5: Commit**

```bash
git add Display.lua
git commit -m "feat: replace border tint with pulsing glow for PIN/PREFER overrides"
```

---

### Task 6: Masque integration

**Files:**
- Modify: `Display.lua:1-9` (module-level Masque init)
- Modify: `Display.lua:125-187` (CreateIcon -- Masque button registration)

This is last because it touches the most icon layers and benefits from all prior CreateIcon changes being in place.

- [ ] **Step 1: Add Masque init at module level**

At the top of `Display.lua`, after the existing local declarations (after line 6), add:

```lua
local C_Spell_GetSpellCharges = C_Spell and C_Spell.GetSpellCharges
local Masque = _G.LibStub and _G.LibStub("Masque", true)
local MasqueGroup = Masque and Masque:Group("TrueShot", "Queue")
```

(Also remove the duplicate `C_Spell_GetSpellCharges` local from Task 4 if it was added lower in the file -- there should be one declaration at the top.)

- [ ] **Step 2: Register icons with Masque in CreateIcon**

At the end of `CreateIcon()`, before `frame:Hide()` and `return frame`, add:

```lua
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
```

- [ ] **Step 3: Add Masque callback for keybind re-anchoring**

After the MasqueGroup creation, add:

```lua
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
```

(This must be after the `icons` table is declared at line 69.)

- [ ] **Step 4: In-game test**

**Without Masque installed:**
- Verify addon loads without errors
- Icons look identical to before (native atlas textures)

**With Masque installed:**
- Verify icons are skinned by the active Masque skin
- No double borders or backgrounds
- Keybind text stays anchored top-right after skin changes
- Cooldown swipes render correctly through Masque

- [ ] **Step 5: Commit**

```bash
git add Display.lua
git commit -m "feat: add optional Masque integration for icon skinning"
```

---

### Task 7: Final integration test and version bump

**Files:**
- Modify: `TrueShot.toc:5` (version bump)

- [ ] **Step 1: Full integration test**

Test matrix:
- [ ] All 4 orientations with firstIconScale 1.0 and 1.5
- [ ] Backdrop on/off in each orientation
- [ ] Masque enabled/disabled (if available)
- [ ] Charge cooldown with Barbed Shot during combat
- [ ] Glow transitions (PIN -> AC -> PREFER -> AC)
- [ ] All new settings persist across `/reload`
- [ ] No Lua errors in `/console scriptErrors 1`

- [ ] **Step 2: Version bump**

In `TrueShot.toc`, change:
```
## Version: 0.4.2-alpha
```
to:
```
## Version: 0.5.0-alpha
```

- [ ] **Step 3: Commit**

```bash
git add TrueShot.toc
git commit -m "chore: bump version to 0.5.0-alpha (display JAC parity)"
```
