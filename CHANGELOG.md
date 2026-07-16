# Changelog

## Unreleased

### Added
- **Honest idle presentation**. Empty committed queues can now show a muted placeholder slot with a short Assisted Combat or filtered-action status.

### Fixed
- **Committed decision-source presentation**. The source label and override glow now follow the committed, visible primary slot instead of a newer engine snapshot.
- **Strict Assisted Combat primary integrity**. Strict Compliance now preserves a readable, non-secret Blizzard current recommendation unchanged in Slot 1, including diagnostic recomputes with no active profile. A nil, secret, invalid, errored, or unavailable primary leaves the Strict queue empty instead of promoting a rotation-catalog entry.
- **Bounded display stabilization**. Queue smoothing now commits the newest oscillating candidate after at most 0.30 seconds, while cast and lifecycle flushes remain immediate.
- **Secret-value handling**. Aura, charge, cooldown-number, and charge-text paths now fail closed before comparisons, formatting, or UI setters.

### Changed
- **Decision-source labeling**. The label now distinguishes Blizzard's Assisted Combat recommendation from experimental overrides in user-readable, length-limited text.
- **Single-action default**. The default icon count is now one instead of two; existing saved user settings continue to take precedence.
- **Action-icon keybind**. Keybind text now appears only on the first, next-action icon.
- **Action-icon cast feedback**. Cast-success flashes are now restricted to the first, next-action icon.
- **Context labeling**. Settings and README copy now describe additional icons as unordered rotation-catalog context.
- **Rotation catalog labeling**. Supporting icons from `GetRotationSpells()` are context only, not predicted future casts; casts of those icons never receive `soft_match` classification in Strict or Experimental mode.
- **Experimental primary correctness**. A blacklisted or locally uncastable raw primary may leave Slot 1 empty; rotation-catalog context is never promoted to replace it.
- **Settings clarity**. Added a Strict Compliance checkbox and visibly disabled experimental-only display controls while Strict is active.

### Tests
- Added committed idle-state coverage for metadata isolation, filtered and waiting labels, queue stabilization, phase visibility, option fallback, and artifact cleanup.

## v0.27.0 - 2026-05-01

### Added
- **Survival custom rules**. Added `Raptor Swipe` (`1259019`) to both Survival Hunter rotational spell catalogs so it can be selected in custom profile rules.
- **Tip of the Spear stack condition**. Added a Survival-specific `Tip of the Spear Stacks` condition backed by the validated player buff signal (`260286`). The condition reads stack counts defensively and fails closed when aura data is secret or unavailable.

### Changed
- Promoted the 0.27 line to a stable release while keeping the Midnight strict-compliance baseline from `v0.27.0-alpha.1`.

### Tests
- Added Hunter profile coverage for `Raptor Swipe` catalog exposure and `Tip of the Spear Stacks` evaluation, including the secret-stack fail-closed path.
- Local release validation: `scripts/run_tests.sh`, `luac -p`, and `git diff --check` passed.

## v0.27.0-alpha.1 - 2026-04-23

### Added
- **Midnight strict compliance baseline**. Added `SignalRegistry.lua` and default-on strict compliance mode so unvalidated live combat signals fail closed and Hunter strict output remains Blizzard Assisted Combat primary.
- **In-client smoke gates**. Added `/ts smoke` and `/ts combat-smoke`; reports are persisted to `TrueShotDB.smokeReport` and appended to `TrueShotDB.smokeHistory`.
- **Release gate automation**. Added `scripts/release_gate.sh`, `scripts/check_wow_smoke.lua`, and WoW install/read/watch helpers for repeatable local and live-client verification.
- **Package build**. Added `VERSION`, `.pkgmeta`, and `scripts/build_package.sh` to produce a clean `dist/TrueShot-0.27.0-alpha.1.zip` artifact.

### Changed
- **Hunter strict product posture**. All six Hunter hero profiles now use explicit `EXPERIMENTAL_PIN` / `EXPERIMENTAL_PREFER` for live override behavior. Strict mode ignores those paths and preserves `source=ac`, `reasonCode=AC_PRIMARY`.
- **Midnight positioning**. README and project docs now describe TrueShot as a Hunter-first Assisted Combat presentation layer/trainer, not an optimal Hekili-style live solver.
- **CI**. GitHub Actions now runs the unified release gate.

### Validation
- Local gate: `scripts/release_gate.sh` passed.
- Live-client gate: `scripts/release_gate.sh --wow` passed against WoW `12.0.5.67114`, Interface `120005`.
- All six Hunter hero paths passed `/ts smoke` and `/ts combat-smoke` with `strict=true`, `acAvailable=true`, `queue=2`, `source=ac`, and `reasonCode=AC_PRIMARY`.
- Test suite: 128 passed, 0 failed.

## v0.26.1 - 2026-04-23

### Fixed
- **BM Pack Leader queue stability and filler fallthrough** (reported as [#93](https://github.com/itsDNNS/TrueShot/issues/93)). `BM Pack Leader` no longer depends on a single first-match `PIN` / `PREFER` chain for the `Bestial Wrath` follow-up path. The profile now runs through a hybrid local decision pipeline in `Engine.lua`: hard gates first, then explicit priority buckets, then score/tiebreak selection only inside the active bucket. For Pack Leader this means `Bestial Wrath`, the short `Barbed Shot` setup window before `Bestial Wrath`, Stampede-triggering `Kill Command`, proc-driven `Kill Command`, and the fallback choice between `Barbed Shot` and `Cobra Shot` are evaluated as separate windows instead of competing as flat rules. This closes the recurring state where `Kill Command` or `Barbed Shot` could linger too long on queue slot 1 while a better legal filler already existed.

### Added
- **Hybrid priority engine pilot**. `docs/HYBRID_PRIORITY_ENGINE.md` documents the new queue model and its intended migration boundary. `BM Pack Leader` is the first pilot profile using that path.
- **Lua validation entrypoint**. `scripts/validate_lua.ps1` now runs `luac`, `luacheck` when present, and the core Lua test suite in one reproducible command.

### Changed
- **BM Pack Leader queue semantics**. `Focus` is no longer treated as a hard legality gate for `Cobra Shot`; it only affects scoring as a soft signal. Queue debug metadata now records hybrid `bucket`, `score`, and `scoreBreakdown` so the live choice is easier to audit.
- **Display glow handling**. `Display.lua` treats hybrid local decisions like other local overrides, so the primary suggestion still renders with explicit overlay emphasis.

### Tests
- `tests/test_hunter_profiles.lua` now covers the hybrid `BM Pack Leader` buckets, including the dedicated `Barbed Shot` setup window before `Bestial Wrath`, the `Kill Command` proc/stampede path, and the filler fallback to `Cobra Shot` when `Kill Command` is not truly available.
- Full release verification before tagging: `powershell -ExecutionPolicy Bypass -File .\scripts\validate_lua.ps1` => `tests/test_hunter_profiles.lua` 50/50, `tests/test_cd_ledger.lua` 27/27, `tests/test_condition_registry.lua` 12/12, `tests/test_engine_hero_talent.lua` 10/10, `tests/test_base64_decode.lua` 8/8.

## v0.26.0 - 2026-04-23

### Fixed
- **Feral Wildstalker hero-tree activation** (reported as [#92](https://github.com/itsDNNS/TrueShot/issues/92)). The Wildstalker profile no longer relies on `Bloodseeker Vines`, which is proc-driven hidden state and therefore not a reliable spellbook marker. `Profiles/Feral_Wildstalker.lua` now declares Blizzard's authoritative `heroTalentSubTreeID = 22`, while `Profiles/Feral_DruidOfTheClaw.lua` declares `heroTalentSubTreeID = 21` and keeps `Ravage` only as a legacy fallback when the hero-talent API is unavailable.
- **Feral Berserk / Incarnation cooldown handling**. `State/CDLedger.lua` now tracks `Berserk (106951)` and `Incarnation: Avatar of Ashamane (102543)` as a shared cooldown pair, so Feral queue rules stop resurfacing Berserk while Incarnation is already on cooldown. Both Feral profiles also treat Incarnation as the longer 20-second burst window in profile state.
- **Feral queue spam / utility leakage**. The Feral profiles now suppress `Rake` on the same target until the local Pandemic refresh window, and they filter `Cat Form` and `Mark of the Wild` from the queue while those states are already active on the player.

### Added
- **Feral regression suite**. New `tests/test_druid_profiles.lua` covers Wildstalker burst windows, shared Berserk/Incarnation cooldown behavior, same-target Rake suppression, Cat Form filtering, and Mark of the Wild filtering.

### Changed
- **Feral release posture**. These fixes make the Wildstalker activation path and the specific follow-up regressions above meaningfully safer, but Feral support remains alpha overall and is still not positioned as ready for serious play.

### Tests
- `tests/test_engine_hero_talent.lua` now covers the Druid hero-tree activation path for Wildstalker and Druid of the Claw, including subtree precedence over legacy marker spells.
- `tests/test_cd_ledger.lua` now covers Berserk / Incarnation shared cooldown behavior and cooldown-API reseeding for that pair.
- Full release verification before tagging: `lua tests/test_druid_profiles.lua` => 8/8, `lua tests/test_cd_ledger.lua` => 27/27, `lua tests/test_engine_hero_talent.lua` => 14/14, `lua tests/test_hunter_profiles.lua` => 39/39, `lua tests/test_condition_registry.lua` => 12/12, `lua tests/test_base64_decode.lua` => 8/8.

## v0.25.2 - 2026-04-20

### Fixed
- **MM Hunter: Trueshot and Moonlight Chakram not surfaced in Queue 1** (reported as [#89](https://github.com/itsDNNS/TrueShot/issues/89)). Blizzard Assisted Combat does not include Trueshot or Moonlight Chakram in its suggestion stream, so the previous `ac_suggested(...)` gate on both spells prevented the MM Dark Ranger and MM Sentinel profiles from ever pinning them. The MM Dark Ranger and MM Sentinel Trueshot PINs now gate on `cd_ready(Trueshot) AND in_combat` using the cast-tracked CD ledger, and the Sentinel Moonlight Chakram PREFER rule gates on the local Trueshot window (`trueshot_active AND NOT aimed_shot_ready`). The existing Volley anti-overlap `BLACKLIST_CONDITIONAL` and the `NOT trueshot_active` Chakram safety net both remain in place; `Engine:IsSpellCastable` enforces the final legality check at queue-build time.
- **Cooldown ledger survives `/reload` mid-cooldown**. Before this release an addon reload during an in-flight Trueshot cooldown dropped the ledger state, so `cd_ready(Trueshot)` flipped back to true until `C_Spell.IsSpellUsable` happened to block the PIN. `State/CDLedger.lua` now exposes `ReseedFromCooldownAPI`, called from the `PLAYER_ENTERING_WORLD` handler in `Core.lua`, which reads `C_Spell.GetSpellCooldown` for every spell in `CDLedger.spec` and reseeds the remaining cooldown using wall-clock semantics (`remaining = startTime + duration - now`). `modRate` is carried as API metadata only and deliberately does not shorten the ledger lifetime. Secret values and non-numeric fields from the API fall through to an empty ledger rather than guessing.

### Added
- **`CDLedger.spec[288613]`**: Trueshot is now tracked by the central cooldown ledger with a 120 s baseline (source: Azortharion, Icy Veins MM Hunter Rotation, guide updated 2026-04-09, Patch 12.0.4). `GetSpellBaseCooldown` reads still override the hardcoded baseline when talents modify it.

### Tests
- New scenarios in `tests/test_cd_ledger.lua`: Trueshot 120 s flat CD, `ReseedFromCooldownAPI` restores an in-flight cooldown after reload, `ReseedFromCooldownAPI` treats `duration` as wall-clock even when `modRate` differs, and secret snapshots are ignored.
- New scenarios in `tests/test_hunter_profiles.lua`: MM Dark Ranger pins Trueshot even when AC omits it, a local Trueshot cast flips `cd_ready(Trueshot)` to false immediately and stops repinning Trueshot, the Volley anti-overlap guard still blocks a ready Trueshot PIN, MM Sentinel pins Trueshot even when AC omits it, Moonlight Chakram surfaces from the local Sentinel window without AC backing, and Moonlight Chakram stays suppressed outside `trueshot_active`.
- Full test suite now reports 39 Hunter profile + 25 CD ledger + 12 condition registry + 10 engine hero talent + 8 base64 = 94 passing.

## v0.25.1 - 2026-04-19

### Fixed
- **Frost Mage hero-talent detection** (reported as [#88](https://github.com/itsDNNS/TrueShot/issues/88)). Frost Mage players running the Spellslinger hero tree had the addon activate the Frostfire profile instead. The Frost Spellslinger marker this addon tried to use was a proc-driven buff effect, so the legacy `IsPlayerSpell(markerSpell)` activation path could not identify the tree. `Engine:ActivateProfile` now first resolves the player's hero tree via `C_ClassTalents.GetActiveHeroTalentSpec()` and matches it against the new optional `heroTalentSubTreeID` profile field; the existing `markerSpell` path is kept as a fallback so no other profile needed to change. `Profiles/Frost_Spellslinger.lua` switches to `heroTalentSubTreeID = 40`, which is the Blizzard `TraitSubTree` identifier for Spellslinger.
- **Tests**: new `tests/test_engine_hero_talent.lua` covers the hero-tree activation path end to end with structural guards (Frost_Spellslinger must declare the correct SubTreeID and must not keep the old proc-buff marker) plus behavioural guards (Spellslinger active -> Spellslinger profile wins, Frostfire SubTreeID -> Frostfire fallback, no active hero talent -> Frostfire fallback, Hunter markerSpell path still works for regression). API-missing, secret-value, and pcall-error paths are all exercised so the engine degrades cleanly when the `C_ClassTalents` surface is unavailable. Full test suite now reports 33 Hunter + 21 CD ledger + 12 condition registry + 9 engine hero talent + 8 base64 = 83 passing.

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
