<p align="center">
  <img src="icon.svg" width="128" height="128" alt="TrueShot Logo">
</p>

# TrueShot

A World of Warcraft addon for Retail Midnight that corrects known blind spots in Blizzard's Assisted Combat system.

Blizzard's built-in rotation helper gets you started, but it has gaps: wrong AoE priorities, missing shatter combos, stuck cooldown suggestions, and more. TrueShot identifies these cases and overrides them with cast-event-tracked heuristics, validated against WarcraftLogs data from top-performing players.

## Supported Classes

### Hunter (Primary Shipping Target)

TrueShot is built for Hunters first. Hunter is the class that should deliver clear practical value today, and all three specs are the standard the addon should be judged against.

All six Hunter profiles are source-cited against Azortharion's current Midnight Season 1 rotation guides on Icy Veins (BM 2026-04-10, MM 2026-04-09, SV 2026-03-27), cross-checked against the SimC `midnight` branch default APL and the Wowhead Midnight rotation guides. Every rotational rule carries an `[src §<section> #N]` tag pointing at the priority step it implements; utility blacklists (pet / counter-shot / harpoon) are grouped without per-rule tags. The full source table per spec lives in [BM](docs/BM_ROTATION_REFERENCE.md) / [MM](docs/MM_ROTATION_REFERENCE.md) / [SV](docs/SV_ROTATION_REFERENCE.md) rotation references.

The current release-readiness baseline for Hunter lives in [Hunter Validation Matrix](docs/HUNTER_VALIDATION_MATRIX.md). That document separates static confidence from the remaining live combat checks still needed for a clean `1.0` claim.

| Spec | Hero Path | Key Overrides |
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

All 20 profiles across 4 classes support automatic hero path detection via `IsPlayerSpell` markers, but only Hunter should currently be read as the primary productized support lane.

## How It Works

TrueShot is not a full rotation engine. It's an overlay:

1. **Blizzard Assisted Combat** provides the base recommendation via `C_AssistedCombat.GetNextCastSpell()`
2. **TrueShot PIN rules** override position 1 when a specific condition is met (e.g. "Black Arrow during Withering Fire")
3. **TrueShot PREFER rules** elevate a spell to position 1 as a softer suggestion
4. **Remaining positions** are filled from `C_AssistedCombat.GetRotationSpells()`

State tracking is purely event-driven via `UNIT_SPELLCAST_SUCCEEDED`. No buff reading, no resource tracking, no hidden state simulation.

## Display Features

- Compact queue overlay with configurable icon count and position
- **AoE hint icon** with bounce animation for AoE abilities (e.g. Wild Thrash)
- **Queue stabilization** prevents icon flicker from AC instability
- **Masque support** for icon skinning (optional, zero-dependency)
- **First-icon scale** (1.0x - 2.0x) for visual hierarchy
- **Queue orientation** (LEFT / RIGHT / UP / DOWN)
- **Override glow** with pulsing animation (cyan for PIN, blue for PREFER)
- **Charge cooldown** edge ring for multi-charge spells
- **Keybind display** with macro and ElvUI action bar support
- Cast success feedback, range indicator, cooldown swipes
- Optional backdrop toggle for clean floating-icons look
- Settings panel via `/ts options` with X/Y position controls
- Tiered update rates (10Hz combat, 2Hz idle, 0Hz hidden)

## Installation

1. Copy the `TrueShot` folder into:

```text
World of Warcraft/_retail_/Interface/AddOns/
```

2. Restart WoW or `/reload`.
3. Log into a supported class (Hunter, Demon Hunter, Druid, or Mage).

## Commands

| Command | Description |
|---------|-------------|
| `/ts options` | Open settings panel |
| `/ts lock` / `unlock` | Lock/unlock overlay position |
| `/ts burst` | Toggle burst mode |
| `/ts hide` / `show` | Toggle visibility |
| `/ts debug` | Show profile state |
| `/ts diagnostics on\|off` | Enable signal probes |
| `/ts probe ...` | Run signal probes (requires diagnostics) |

## Design Philosophy

TrueShot is built around the Midnight API reality:

- Primary combat state (buffs, resources, exact cooldowns) is restricted via secret values
- Assisted Combat remains the most reliable legal baseline
- Cast events (`UNIT_SPELLCAST_SUCCEEDED`) and spell charges (`C_Spell.GetSpellCharges`) are the primary non-secret signals

The addon is:
- **Conservative**: only overrides AC where it's demonstrably wrong
- **Transparent**: shows why it overrode AC (reason labels, phase indicators)
- **Fail-safe**: degrades gracefully to pure AC passthrough if signals are unavailable

## Framework Docs

- [Project Goals](docs/PROJECT_GOALS.md)
- [API Constraints](docs/API_CONSTRAINTS.md)
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
