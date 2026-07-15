<p align="center">
  <img src="icon.svg" width="128" height="128" alt="TrueShot Logo">
</p>

# TrueShot

A World of Warcraft addon for Retail Midnight that presents and explains Blizzard's Assisted Combat system with Hunter-focused training, profile hints, and optional signal-gated experiments.

Blizzard's built-in rotation helper gets you started, but Midnight's addon model limits what third-party addons can safely know and decide during combat. TrueShot's shippable baseline is an Assisted Combat presentation layer: it makes the recommendation easier to read, adds keybinds and context, and provides Hunter-specific learning views without bypassing secret-value restrictions.

Current development target: WoW Retail `12.0.7.68453` / Interface `120007`. Existing client-smoke records remain tied to the builds named in their validation documents.

Some existing override rules are retained as experimental research while their signals are validated. They are not the product baseline for a clean Midnight-compliant release.

## Supported Classes

### Hunter (Primary Shipping Target)

TrueShot is built for Hunters first. Hunter is the class that should deliver clear practical value today, and all three specs are the standard the addon should be judged against.

All six Hunter profiles are source-cited against Azortharion's current Midnight Season 1 rotation guides on Icy Veins (BM 2026-04-10, MM 2026-04-09, SV 2026-03-27), cross-checked against the SimC `midnight` branch default APL and the Wowhead Midnight rotation guides. Every rotational rule carries an `[src §<section> #N]` tag pointing at the priority step it implements; utility blacklists (pet / counter-shot / harpoon) are grouped without per-rule tags. The full source table per spec lives in [BM](docs/BM_ROTATION_REFERENCE.md) / [MM](docs/MM_ROTATION_REFERENCE.md) / [SV](docs/SV_ROTATION_REFERENCE.md) rotation references.

The current release-readiness baseline for Hunter lives in [Hunter Validation Matrix](docs/HUNTER_VALIDATION_MATRIX.md). That document separates strict baseline support from experimental signal-gated heuristics and the remaining live combat checks still needed for a clean `1.0` claim.

| Spec | Hero Path | Experimental Signals / Training Focus |
|------|-----------|---------------|
| **Beast Mastery** | Dark Ranger | Black Arrow during Withering Fire, Wailing Arrow sequencing, AoE hint for Wild Thrash |
| **Beast Mastery** | Pack Leader | Stampede pin (first KC after Bestial Wrath), Nature's Ally KC weaving, Wild Thrash AoE hint |
| **Marksmanship** | Dark Ranger | Trueshot opener sequence, Volley/Trueshot anti-overlap, Withering Fire BA priority |
| **Marksmanship** | Sentinel | Post-Rapid Fire Trueshot gating, Volley anti-overlap, Moonlight Chakram filler timing |
| **Survival** | Pack Leader | Stampede KC sequencing, Boomstick CD tracking, Takedown burst window, Flamefang timing |
| **Survival** | Sentinel | WFB charge-cap spend, Boomstick CD tracking, Moonlight Chakram timing, Flamefang timing |

### Demon Hunter, Druid, Mage (Foundation / Alpha)

These classes exist as framework groundwork and early profile lanes. They are useful for proving that the architecture can grow beyond Hunter, but they are not the main product promise yet.

We currently treat them as opportunistic expansion paths: they can improve over time, especially when they become classes we actively play ourselves, but Hunter polish comes first.

**If you play one of these classes and notice something off or want to suggest changes, please [open an issue](https://github.com/itsDNNS/TrueShot/issues).**

| Class | Specs | Profiles | Notes |
|-------|-------|----------|-------|
| **Demon Hunter** | Havoc, Devourer | 4 | Metamorphosis burst tracking. Devourer is heavily AC-reliant. |
| **Druid** | Feral, Balance | 4 | Tiger's Fury/Berserk and Celestial Alignment burst tracking. Resource-dependent (Energy, Astral Power) limits overrides. |
| **Mage** | Fire, Frost, Arcane | 6 | Combustion, Frozen Orb, Arcane Surge burst windows. Frost shatter combo (Flurry > Ice Lance). |

All 20 profiles across 4 classes support automatic hero path detection via `C_ClassTalents.GetActiveHeroTalentSpec()` subtree IDs. Where a profile still carries a reliable exclusive `markerSpell`, that path now exists only as a fallback when the hero-talent API is temporarily unavailable during activation. Hunter should still be read as the primary productized support lane.

## How It Works

TrueShot is not a full rotation engine. It is an overlay/trainer:

1. **Blizzard Assisted Combat** provides the base recommendation via `C_AssistedCombat.GetNextCastSpell()`
2. **TrueShot presentation rules** label, stabilize, and explain the recommendation
3. **Profile hints** provide manually selected Hunter learning context such as openers and burst checklists
4. **Supporting positions** can show entries from `C_AssistedCombat.GetRotationSpells()` as rotation-catalog context only, behind a valid current recommendation

Hunter live overrides are explicitly marked as `EXPERIMENTAL_PIN` / `EXPERIMENTAL_PREFER`. The target release posture is fail-safe: if a signal is unavailable, secret, or unvalidated, TrueShot degrades to AC presentation instead of inventing a recommendation.

Strict compliance mode is the default. Legacy live overrides are treated as experimental while their signals are reviewed.

## Display Features

- Compact queue overlay with configurable icon count and position
- **AoE hint icon** with bounce animation for AoE abilities (e.g. Wild Thrash)
- **Queue stabilization** prevents icon flicker from AC instability
- **Masque support** for icon skinning (optional, zero-dependency)
- **First-icon scale** (1.0x - 2.0x) for visual hierarchy
- **Queue orientation** (LEFT / RIGHT / UP / DOWN)
- **Override glow** with pulsing animation for experimental PIN/PREFER output
- **Charge cooldown** edge ring for multi-charge spells
- **Keybind display** with macro and ElvUI action bar support
- Cast success feedback, range indicator, cooldown swipes
- Optional backdrop toggle for clean floating-icons look
- Settings panel via `/ts options` with X/Y position controls
- Tiered update rates (10Hz combat, 2Hz idle, 0Hz hidden)

## Installation

Manual installation:

1. Copy the `TrueShot` folder into:

```text
World of Warcraft/_retail_/Interface/AddOns/
```

2. Restart WoW or `/reload`.
3. Log into a supported class (Hunter, Demon Hunter, Druid, or Mage).

Developer installation from this repo:

```sh
scripts/install_wow_addon.sh
scripts/wow_static_check.sh
```

The install script creates `World of Warcraft/_retail_/Interface/AddOns/TrueShot` as a symlink to this checkout. It refuses to overwrite a non-symlink addon folder.

## Commands

| Command | Description |
|---------|-------------|
| `/ts options` | Open settings panel |
| `/ts lock` / `unlock` | Lock/unlock overlay position |
| `/ts burst` | Toggle burst mode |
| `/ts hide` / `show` | Toggle visibility |
| `/ts debug` | Show profile state |
| `/ts smoke` | Run in-client strict compliance smoke test |
| `/ts combat-smoke` | Run strict compliance smoke test that requires player combat |
| `/ts diagnostics on\|off` | Enable signal probes |
| `/ts strict on\|off` | Toggle strict compliance / experimental override mode |
| `/ts probe ...` | Run signal probes (requires diagnostics) |

Smoke reports are written to `TrueShotDB.smokeReport` and can be read after `/reload` or logout:

```sh
scripts/read_wow_smoke.sh
```

To wait while testing in the client:

```sh
scripts/watch_wow_smoke.sh
```

For combat validation, enter combat on a target dummy and run `/ts combat-smoke` before `/reload`.

## Verification

Local release gate:

```sh
scripts/release_gate.sh
```

Local release gate including the installed WoW client and the latest SavedVariables smoke history:

```sh
scripts/release_gate.sh --wow
```

Build release artifact:

```sh
scripts/build_package.sh --wow
```

The package is written to `dist/TrueShot-<version>.zip` and excludes tests, scripts, local metadata, and other development-only files.

Install the built artifact into the local WoW client for final package smoke:

```sh
scripts/install_wow_artifact.sh
```

To return to live development mode, re-run `scripts/install_wow_addon.sh` to restore the repo symlink.

## Design Philosophy

TrueShot is built around the Midnight API reality:

- Primary combat state (buffs, resources, exact cooldowns) is restricted via secret values
- Assisted Combat remains the most reliable legal baseline
- Cast events and spell charge reads require per-signal validation before they may affect live recommendations

The addon is:
- **Conservative**: defaults to AC presentation when a signal is unavailable, secret, or unvalidated
- **Transparent**: shows why it displayed a hint or recommendation (reason labels, phase indicators)
- **Fail-safe**: degrades gracefully to pure AC passthrough if signals are unavailable

## State Layer

Starting in v0.25.0, TrueShot has a `State/` layer that owns class-agnostic shared state multiple profiles can query through engine conditions. The first module is `State/CDLedger.lua`, a central cooldown tracker fed by `UNIT_SPELLCAST_SUCCEEDED` with `GetSpellBaseCooldown` as the base-CD source and haste-aware scaling for spells flagged `haste_scaled`.

Under the current Midnight compliance plan, this layer is treated as experimental for primary recommendation changes until its signals are explicitly reviewed and gated. See [Midnight Compliance Audit](docs/MIDNIGHT_COMPLIANCE_AUDIT.md).

## Framework Docs

- [Project Goals](docs/PROJECT_GOALS.md)
- [API Constraints](docs/API_CONSTRAINTS.md)
- [Midnight Project Plan](docs/MIDNIGHT_PROJECT_PLAN.md)
- [Midnight Compliance Audit](docs/MIDNIGHT_COMPLIANCE_AUDIT.md)
- [Known Limitations](docs/KNOWN_LIMITATIONS.md)
- [PTR Smoke Matrix](docs/PTR_SMOKE_MATRIX.md)
- [Framework Model](docs/FRAMEWORK.md)
- [Profile Contract](docs/PROFILE_CONTRACT.md)
- [Profile Authoring Guide](docs/PROFILE_AUTHORING.md)
- [Signal Validation](docs/SIGNAL_VALIDATION.md)
- [Hunter Validation Matrix](docs/HUNTER_VALIDATION_MATRIX.md)
- [BM Rotation Reference](docs/BM_ROTATION_REFERENCE.md)
- [MM Rotation Reference](docs/MM_ROTATION_REFERENCE.md)
- [SV Rotation Reference](docs/SV_ROTATION_REFERENCE.md)

## License

Licensed under `GPL-3.0-or-later`. See [LICENSE](LICENSE).
