# Changelog

## v0.19.0 - 2026-04-09

### Added
- **Visual Rule Builder** (`/ts rules`): In-game UI for creating and editing profile rules without writing Lua
  - Two-panel split frame: scrollable rule list with spell icons and type badges, detail editor with dropdowns and text inputs
  - Condition builder with nested AND/OR/NOT tree, inline dropdowns, and visual connecting lines
  - Custom state variables with cast-event triggers and automatic timer resets
  - Preset condition templates (Spell Proc, AoE, Burst Mode, Combat Opening, Spell Charges)
  - Fork model: customize built-in profiles with full ownership, reset to built-in at any time
  - Drift detection when built-in profiles are updated after customization
  - Spell validation warnings for unknown spells (non-blocking)
- Condition schema registry for profile-specific condition discovery
- Profile version tracking for drift detection
- "Open Rule Builder" button in Settings > Profiles tab

## v0.18.0 - 2026-04-08

### Changed
- **Settings panel restructured**: Replaced single scrollable list with 5 subcategory tabs in the Game Options sidebar (General, Appearance, Features, Position, Profiles). Uses native `Settings.RegisterCanvasLayoutSubcategory` API.
- **New Profiles tab**: Read-only overview of all 22 registered profiles grouped by class (Hunter, Demon Hunter, Druid, Mage) with active profile highlighted in green.
- **Landing page**: Shows addon version and currently active profile at a glance.
- Scorecard and Heartbeat settings grouped under a "Performance Tracking" section header in the Features tab.

## v0.17.0 - 2026-04-08

### Added
- **Rotation Scorecard**: Post-combat alignment report showing how well your casts matched TrueShot's recommendations. Measures recommendation adherence with match/soft-match/miss classification. Gated to fights longer than 8 seconds with 5+ scored casts.
- **GCD Heartbeat**: Real-time scrolling rhythm strip below the queue overlay. Each cast appears as a colored bar: green (matched), cyan (soft match), yellow (miss), red (GCD gap), gray (utility/unscored). Freezes briefly after combat as a mini-replay.
- `/ts score` command to view recent fight alignment history.
- `rotationalSpells` tables on all Hunter profiles for accurate cast classification.

## v0.16.3 - 2026-04-07

### Added
- BM Dark Ranger / Pack Leader: Buffed Kill Command (proc glow) now pinned as priority 1
- Dark Ranger: KC proc respects Withering Fire window (BA stays higher during WF)

## v0.15.0 - 2026-04-07

### Changed
- Action bar cooldown durations used for overlay (more accurate than spell API)

## v0.14.7 - 2026-04-05

### Changed
- Chat messages on login/profile switch now disabled by default
- New setting: "Show chat messages on login"

## v0.14.6 - 2026-04-05

### Changed
- Override glow now enabled by default (cyan pulse for PIN, blue for PREFER)
- New setting: "Show override glow"

### Removed
- 95% accuracy claim from README

## v0.14.5 - 2026-04-05

### Added
- **X/Y position controls** in settings panel (PR #64 by @jmusick)
- Position now persists across /reload and relog via SavedVariables

### Fixed
- Settings panel OnUpdate no longer polls when panel is hidden
- Coordinate input no longer double-applies on Enter + focus-lost
- SetPositionOffsets preserves current anchor target instead of hardcoding UIParent

## v0.14.0 - 2026-04-05

### Added
- **AoE hint icon**: Secondary icon shows AoE abilities (e.g. Wild Thrash) when 2+ hostile nameplates are detected, with bounce + orange pulse animation. Position adapts to queue orientation.
- **ElvUI keybind support**: Keybind labels now work with ElvUI action bars (bars 1-15)
- **Settings**: "Show AoE hint icon" toggle

### Changed
- Wild Thrash moved from main queue PIN to AoE hint icon for BM profiles
- Improved queue stabilization: hiding requires 5 stable ticks (500ms) to prevent flicker during passive combat phases
- Fixed icon scaling on Enable: icons now get correct firstIconScale immediately after reload

### Fixed
- Fixed strobe-like icon flickering during passive combat (pets fighting, player idle)
- Enable/Disable cycle no longer resets queue stabilization when already active
- Icons retain last known texture when spell API intermittently returns nil

## v0.11.0 - 2026-04-04

### Added
- **Mage Support**: Fire, Frost, and Arcane with hero path detection
  - Fire Sunfury: Combustion burst window tracking, Flamestrike AoE gating
  - Fire Frostfire: Fallback profile
  - Frost Frostfire: Frozen Orb tracking, Blizzard AoE gating
  - Frost Spellslinger: Fallback profile
  - Arcane Sunfury: Arcane Surge + Touch of the Magi burst tracking
  - Arcane Spellslinger: Fallback profile

## v0.10.0 - 2026-04-04

### Changed
- Removed unsupported Essence Break rule from Havoc DH profiles (WCL-validated)

## v0.9.0 - 2026-04-03

### Changed
- Removed BW charge-dump gating from BM profiles (WCL-validated: top players press BW immediately)
- Removed Charge Dump phase detection and related logic

## v0.8.0 - 2026-04-02

### Added
- **Demon Hunter Support**: Havoc and Devourer with hero path detection
- **Druid Support**: Feral and Balance with hero path detection
- Metamorphosis, Tiger's Fury/Berserk, Celestial Alignment burst tracking

## v0.7.1 - 2026-04-02

### Improved
- Friendly startup message with human-readable profile names
- Single-line chat output on login instead of two lines
- Updated README with full documentation

## v0.7.0 - 2026-04-02

### Added
- **Survival Hunter**: Pack Leader and Sentinel profiles
  - Stampede KC sequencing after Takedown (Pack Leader)
  - WFB charge management with near-cap cutoff (Sentinel)
  - Moonlight Chakram timing in Takedown window (Sentinel)
  - Takedown burst window tracking (8s)
  - Flamefang Pitch support
- All three Hunter specs now covered (BM, MM, SV) with 6 profiles total

## v0.6.0 - 2026-04-02

### Added
- **Marksmanship Hunter**: Dark Ranger and Sentinel profiles
  - Trueshot opener sequence: TS > BA > WA > BA (Dark Ranger)
  - Volley/Trueshot anti-overlap to prevent Double Tap waste
  - Post-Rapid Fire Trueshot gating for Bulletstorm uptime
  - Moonlight Chakram filler timing gated by Aimed Shot charges (Sentinel)

## v0.5.2 - 2026-04-02

### Added
- Tiered update rates: 10Hz combat, 2Hz idle, 0Hz hidden
- Instant event response on target change, spell cast, combat transitions
- DurationObject cooldown path for secret-safe rendering
- Charge edge ring for multi-charge spells

### Improved
- Cooldown swipe opacity reduced from 80% to 60%
- GCD filtering preserved on DurationObject path

### Fixed
- Scrollable settings panel
- Charge count only shown when regenerating

## v0.5.1 - 2026-04-02

### Added
- DurationObject cooldown rendering (C_Spell.GetSpellCooldownDuration)
- Charge cooldown edge ring (SetDrawSwipe false, SetDrawEdge true)

## v0.5.0 - 2026-04-02

### Added
- **Masque integration** for icon skinning (optional, zero-dependency)
- **First-icon scale** (1.0x - 2.0x) for visual hierarchy
- **Queue orientation** (LEFT, RIGHT, UP, DOWN)
- **Override glow** with pulsing animation (cyan PIN, blue PREFER)
- **Charge cooldown** display for multi-charge spells
- **Backdrop toggle** for clean floating-icons look

## v0.4.2 - 2026-04-01

### Added
- Macro keybind support

## v0.4.1 - 2026-04-01

### Fixed
- Bestial Wrath cooldown tracking fixes

### Improved
- Performance optimizations

## v0.4.0 - 2026-04-01

### Changed
- Renamed from HunterFlow to TrueShot
- Full UX overhaul

### Added
- BM Dark Ranger profile (Black Arrow, Withering Fire, Wailing Arrow state machine)
- BM Pack Leader profile (BW management, Nature's Ally, Wild Thrash AoE)
- Hero path auto-detection via IsPlayerSpell
- Settings panel in Game Options
- Cast success feedback
- Cooldown swipes (best-effort)
- Keybind display
- Range indicator
- Phase and reason overlay
