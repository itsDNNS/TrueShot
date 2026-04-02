# Display Upgrade: JAC-Compatible Look and Feel

**Date**: 2026-04-02
**Status**: Approved
**Scope**: Standard Queue visual parity with Just Assisted Combat (JAC)
**Future**: Option B (JAC LibStub hook integration) deferred for later evaluation

## Context

TrueShot layers PIN/PREFER rotation fixes on top of Blizzard's Assisted
Combat. The current Display.lua renders a functional queue overlay but
lacks the visual polish that JAC users expect: Masque skinning, scalable
first icon, orientation options, proper glow effects, and charge cooldown
tracking.

This spec upgrades the Standard Queue display to match JAC's look and feel
without adding JAC's extra engines (Burst, GapCloser, Defensive, Interrupt).
The Engine and Profile layers remain untouched.

## Changes

### 1. Masque Integration

**What**: Register a Masque group so users can skin TrueShot icons with any
Masque skin (ElvUI, Serenity, Shadow, etc.).

**How**:
- Soft-depend on Masque via `## OptionalDeps: Masque` in TOC
- On load, guard with `_G.LibStub and LibStub("Masque", true)` (TrueShot
  does not embed LibStub; if neither Masque nor any other addon loads it,
  the global will be nil)
- Register group `"TrueShot"` via `Masque:Group("TrueShot", "Queue")`
- In `CreateIcon()`, call `MasqueGroup:AddButton(button, layerMap)` with:
  - `Icon` = button.texture
  - `Cooldown` = button.cooldown
  - `ChargeCooldown` = button.chargeCooldown (new, see section 5)
  - `HotKey` = button.keybind
  - `Normal` = button.border (atlas: UI-HUD-ActionBar-IconFrame)
- **Layer ownership**: When Masque is active, hide native `slotBackground`
  and `border` atlas textures (Masque replaces them). The `success` overlay,
  `mask`, and `keybind` remain under TrueShot's control. When Masque is
  absent, all native textures render as before (zero visual change).
- Masque callback re-applies keybind anchor after skin changes

**Files**: Display.lua, TrueShot.toc

### 2. First-Icon-Scale

**What**: Position 1 icon rendered larger than positions 2+ for visual
hierarchy, matching JAC's `firstIconScale` behavior.

**How**:
- New saved variable `firstIconScale` (number, default 1.3, range 1.0-2.0)
- `LayoutIcons()` applies scale to position 1 frame via `:SetScale()`
- Positions 2+ remain at scale 1.0
- Existing alpha reduction (0.7) for positions 2+ is preserved
- **Layout math**: Icon 2 must be anchored relative to icon 1's effective
  (scaled) edge, not the unscaled size. Effective first icon width =
  `iconSize * firstIconScale`. Position 2 offset =
  `iconSize * firstIconScale + spacing`. Remaining icons use normal
  `iconSize + spacing` offsets.
- Container size calculation uses the effective first icon width
- For vertical orientations, the same logic applies to height instead

**Files**: Display.lua, SettingsPanel.lua, Core.lua (default)

### 3. Queue Orientation

**What**: User-selectable queue growth direction (horizontal or vertical).

**How**:
- New saved variable `orientation` (string, default "LEFT")
- Four options: `LEFT` (grows right), `RIGHT` (grows left), `UP`, `DOWN`
- Only `LayoutIcons()` changes:
  - `LEFT`: anchor LEFT, offset on X axis (current behavior)
  - `RIGHT`: anchor RIGHT, negative X offset
  - `UP`: anchor BOTTOM, positive Y offset
  - `DOWN`: anchor TOP, negative Y offset
- Container dimensions swap width/height for vertical orientations
- Reason/phase labels reposition: horizontal = below/above container,
  vertical = to the right of the container
- First-icon-scale applies along the orientation axis (width for
  horizontal, height for vertical)
- Settings panel exposes dropdown selector

**Files**: Display.lua, SettingsPanel.lua, Core.lua (default)

### 4. Glow System

**What**: Replace the current border-tint override indicator with a proper
glow effect when TrueShot's PIN or PREFER overrides Blizzard AC.

**How**:
- Use a custom `AnimationGroup` with alpha-pulsing border overlay texture.
  Blizzard's 12.0 action-bar alert system uses
  `ActionButtonSpellAlertManager` which is template-based and not designed
  for non-ActionButton frames. The legacy `ActionButton_ShowOverlayGlow`
  global may not exist in 12.0. A lightweight custom glow avoids this
  dependency entirely.
- Implementation: create an overlay texture per icon (atlas
  `UI-HUD-ActionBar-IconFrame-Mouseover`), tint it to the desired color,
  animate alpha between 0.3 and 0.9 with a 0.8s cycle via AnimationGroup.
  Show/hide per frame based on `lastQueueMeta.source`.
- Applied to position 1 icon when `lastQueueMeta.source` is `"pin"` or
  `"prefer"`
- Glow color: cyan `(0.0, 0.8, 1.0)` for PIN, soft blue `(0.4, 0.6, 1.0)`
  for PREFER
- Glow removed when source reverts to `"ac"`
- Existing reason text below the queue is preserved as complementary info

**Files**: Display.lua

### 5. Charge Cooldown

**What**: Show charge regeneration timer for multi-charge spells (Barbed
Shot has 2 charges). JAC shows this as a separate cooldown swipe.

**How**:
- Each icon gets a second CooldownFrame: `button.chargeCooldown`
- In `UpdateQueue()`, for the displayed spell: call
  `C_Spell.GetSpellCharges(spellID)`
- If charges exist and currentCharges < maxCharges:
  - Set charge swipe via `chargeCooldown:SetCooldown(chargeStart,
    chargeDuration, chargeModRate)` (chargeModRate from GetSpellCharges,
    defaults to 1.0 if absent)
  - Show charge swipe with reduced opacity (0.4) to distinguish from
    primary cooldown
  - Display charge count via small font string (bottom-right corner)
- If charges are full or spell has no charges: hide chargeCooldown frame
- Charge cooldown respects the existing `showCooldownSwipe` setting; when
  that option is off, both primary and charge swipes are hidden
- Layering: chargeCooldown renders beneath the primary cooldown frame so
  GCD swipes visually overlay charge regen
- Registered with Masque layer map (section 1)

**Files**: Display.lua

### 6. Optional Container Backdrop

**What**: Allow hiding the dark container background for a cleaner,
floating-icons look.

**How**:
- New saved variable `showBackdrop` (boolean, default true)
- When false: `container:SetBackdropColor(0, 0, 0, 0)` and
  `container:SetBackdropBorderColor(0, 0, 0, 0)` (alpha-only, does not
  cascade to child frames; icons and text remain fully visible)
- When true: restore original colors `(0.04, 0.04, 0.04, 0.92)` and
  `(0.55, 0.55, 0.55, 0.95)`
- Toggled via checkbox in settings panel

**Files**: Display.lua, SettingsPanel.lua, Core.lua (default)

## Out of Scope

- Nameplate overlay rendering
- Burst/GapCloser/Defensive/Interrupt engines
- Health bar display
- Grab tab drag handle (current full-frame drag is sufficient)
- Proc glow detection (would require buff tracking beyond current signals)
- LibCustomGlow / ActionButton_ShowOverlayGlow (12.0 API uncertain; custom
  AnimationGroup glow is simpler and dependency-free)

## Files Affected

| File | Changes |
|------|---------|
| Display.lua | Masque init, CreateIcon layers, LayoutIcons orientation, glow system, charge cooldown, backdrop toggle |
| SettingsPanel.lua | New options: firstIconScale slider, orientation dropdown, showBackdrop checkbox |
| Core.lua | New defaults in saved variables table |
| TrueShot.toc | `## OptionalDeps: Masque` |

## Testing

- Verify with and without Masque installed (graceful fallback)
- Test all 4 orientations with 1-4 icon counts
- Test firstIconScale at min (1.0) and max (2.0)
- Confirm glow appears/disappears correctly on PIN/PREFER transitions
- Verify charge cooldown with Barbed Shot (2 charges) and Kill Command
- Toggle backdrop on/off mid-combat
