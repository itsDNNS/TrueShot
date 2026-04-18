# Changelog

## v0.25.0 - 2026-04-18

### Added
- **`State/CDLedger.lua`**: central, data-driven cooldown tracker for Hunter rotational spells. Listens to `UNIT_SPELLCAST_SUCCEEDED`, resolves base cooldown through `GetSpellBaseCooldown` (with hardcoded `spec.base_ms` fallback), applies haste scaling through `UnitSpellHaste("player")` for spells flagged `haste_scaled`. Every live API read is guarded with `pcall` + `issecretvalue` and degrades cleanly to the spec fallback when the client returns secret values. Closes [#84](https://github.com/itsDNNS/TrueShot/issues/84).
- **Engine conditions `cd_ready(spellID)` and `cd_remaining(spellID, op, value)`**: new first-class condition types available to every profile and to the Visual Rule Builder. Registered in `CustomProfile` so they show up in the picker alongside `spell_charges`, `spell_glowing`, etc.
- **`State/` framework layer**: documented in `docs/FRAMEWORK.md`. Owns shared, class-agnostic state that multiple profiles query through engine conditions.
- **`/ts probe cd`**: new probe command that reports `GetSpellBaseCooldown`, `UnitSpellHaste("player")`, and `C_Spell.GetSpellCooldown` values (plus secrecy) for every spell the ledger tracks. Feeds into `docs/SIGNAL_VALIDATION.md` classifications.
- **`tests/test_cd_ledger.lua`**: 19 scenario tests covering spec coverage, base-CD resolution (spec fallback, live override, secret-guard), haste scaling (flag on/off, API present/absent), reset and reduction hooks, lifecycle (OnCombatEnd does not reset, Reset clears all), and secret-spellID protection.

### Changed
- **`Profiles/BM_PackLeader.lua` pilot migration**: drops `BW_COOLDOWN`, `WT_COOLDOWN`, `lastBWCast`, and `lastWildThrashCast` in favour of ledger-owned timing. Rules now use `cd_ready` / `cd_remaining` directly. Phase detection ("Burst" window) reads `CDLedger:SecondsSinceCast(Bestial Wrath)` instead of a profile-local timestamp. Legacy `bw_on_cd` / `wt_on_cd` conditions remain as thin backward-compat shims that delegate to the ledger, and their schema entries are kept (marked legacy) so Visual Rule Builder nodes authored before v0.25.0 still round-trip through the picker. User-forked custom profiles in SavedVariables keep evaluating correctly.
- **Intentional semantic shift**: the ledger preserves cooldown state across `PLAYER_REGEN_ENABLED` (real in-game cooldowns persist across combat end). The pre-v0.25.0 `BM_PackLeader` cleared `lastWildThrashCast` on combat end; the new ledger-owned timer stays through. The `OnCombatEnd` no-op is covered by a test.
- **`docs/SIGNAL_VALIDATION.md`** adds three new signal entries (Base Cooldown Lookup, Spell Haste, Cooldown Read Per-Spell) and lists `/ts probe cd` under the probe commands.
- **`docs/PROFILE_CONTRACT.md`** enumerates the engine-level state conditions and documents `cd_ready` / `cd_remaining` as the preferred path for new rules.
- **`docs/API_CONSTRAINTS.md`** adds the CDLedger pattern to the approved-heuristic list.

## v0.24.0 - 2026-04-18

### Added
- **BM Pack Leader Stampede rule**: First `Kill Command` after `Bestial Wrath` is now pinned as `reason = "Stampede"`. The flag arms on `Bestial Wrath` cast, clears on the next `Kill Command`, and resets on combat end. Sourced to Azortharion, Icy Veins BM Hunter Rotation, guide updated 2026-04-10: "Activate Bestial Wrath. Once activated, your next Kill Command will spawn a Stampede."
- **Hunter profile source citations**: Every Hunter profile file (BM DR, BM PL, MM DR, MM Sentinel, SV PL, SV Sentinel) now carries a structured header block with primary source URL, guide-update date, verified-on date, patch, and cross-check references (SimC midnight branch + Wowhead). Rotational rules carry inline `[src §<section> #N]` tags pointing at the priority step they implement; utility blacklists (pet / counter-shot / harpoon) are grouped without per-rule tags.
- **Hunter logic test suite** (`tests/test_hunter_profiles.lua`): 30 scenario tests covering cast-event state machines and `EvalCondition` behavior for all six Hunter profiles, including the new Stampede arming/consumption path, the Nature's Ally anti-repeat guarantee, and a structural-ordering guard that the Stampede PIN precedes the KC Proc PIN in the rules array (first-match-wins in `Engine:ComputeQueue`).

### Changed
- **BM/MM/SV rotation reference docs**: Each now carries an explicit `Sources` table with tier (primary / cross-check / supplementary), URL, and stamp (guide-update date + patch). `Last reviewed: 2026-04-18` is recorded at the top of each doc.
- **HUNTER_VALIDATION_MATRIX.md**: Expanded with a "Non-Hunter Isolation" section that documents the mechanical guarantee (specID routing in `Engine:ActivateProfile`) that foundation profiles cannot affect Hunter loading. BM Pack Leader validation now lists the Stampede PIN as a new live-check item.

## v0.23.7 - 2026-04-15

### Changed
- **Hunter release-readiness docs**: Added a Hunter validation matrix plus explicit MM/SV reference docs so the shipped Hunter support baseline is documented more evenly.
- **Workflow maintenance**: GitHub Actions checkout steps now use the current `actions/checkout` line.

### Fixed
- **Release packaging**: Addon packages now exclude repo-only documentation and local metadata instead of shipping them in the release zip.

## v0.23.6 - 2026-04-15

### Changed
- **Condition schema registry**: Profile-specific condition schemas now coexist safely even when multiple profiles use the same condition ID.
- **Per-tick cache invalidation**: Engine-side hostile-count and Assisted Combat suggestion caches now use a robust compute-tick invalidation path instead of fragile float-time equality.
- **Release packaging**: Test files and local repo metadata are now excluded from packaged addon zips.

### Fixed
- **Custom rule validation**: Imported state variable names now reliably detect conflicts with profile conditions even when duplicate condition IDs exist across profiles.
- **Import hardening**: Malformed Base64 payloads are rejected early with explicit validation errors instead of being decoded into corrupt bytes.

## v0.23.0 - 2026-04-12

### Added
- **Assisted Combat suggestion gate**: New `ac_suggested` engine condition allows profiles and custom rules to key off Blizzard's live recommendation surface instead of direct spell-usable checks.
- **Phase and queue layout controls**: Settings wiring now exposes the phase indicator plus queue icon count, size, and spacing options in the live UI.

### Changed
- **Hunter-first scope**: README and project goals now define Hunter as the current shipping target, while other classes remain foundation/alpha support.
- **MM/SV readiness rules**: Marksmanship and Survival cooldown-sensitive overrides now follow Assisted Combat suggestions instead of direct `IsSpellUsable()` readiness checks.
- **SV Sentinel Wildfire Bomb handling**: Charge-cap logic now relies only on validated charge-count signals.

### Fixed
- **Enemy-target-only visibility**: Overlay visibility now matches the setting text while preserving the documented combat fallback.
- **Survival spell routing**: Removed the old Hatchet Toss blacklist path that could suppress `Kill Command` through a shared spell ID in melee.
- **BM Pack Leader debug output**: Bestial Wrath cooldown debug text now reflects the actual configured cooldown.

## v0.20.0 - 2026-04-09

### Added
- **Profile Import/Export** (`/ts export`, `/ts import`): Share custom profiles as copy-paste strings
  - Zero external dependencies (custom serializer + Base64 codec)
  - 4-phase validation: format, schema, semantic, warnings
  - Preview before import with validation results
  - Strict security: no code execution, whitelist-based parsing
  - Export/Import buttons in the Rule Builder
  - Profiles are tied to their target spec and only activate on the matching character
- **Profile Library**: Multiple custom profiles per spec with instant switching
  - Import adds to library instead of overwriting
  - Profile selector dropdown in Rule Builder when 2+ profiles exist
  - Delete individual profiles from the library
  - Auto-migration from previous single-profile storage format
- **Profile Browser** (`/ts profiles`): Hierarchical view of all registered profiles
  - Collapsible tree: Class > Spec > Hero Talent
  - Shows all profiles across all classes, not just the current spec
  - View button opens the Rule Builder for the selected profile
  - Export button for profiles with custom data
  - Active/customized/variant indicators per profile
  - Accessible from Rule Builder ("Browse All" button) or slash command
- **Reason text position** (#75): Option to show recommendation reason above or below the icon
- **AoE hint position** (#76): Option to show AoE hint icon to the left of the main icon or below it

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
