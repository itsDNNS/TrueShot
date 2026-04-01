# HunterFlow

`HunterFlow` is a World of Warcraft addon for Retail `Midnight` that layers a hunter-focused recommendation UI on top of Blizzard's `Assisted Combat` system.

The addon does not try to recreate old full-state rotation engines. Instead, it uses Blizzard-provided rotation signals plus lightweight cast-event heuristics where that is still legal and reliable.

`HunterFlow` is also intended to grow into a framework:

- one engine
- multiple spec profiles
- explicit rules about what Blizzard's API still allows and what it does not

The overall project goals are documented in [Project Goals](docs/PROJECT_GOALS.md).

## Status

`HunterFlow` is currently an `alpha`.

Current implementation:

- Beast Mastery Hunter with two hero-path profiles:
  - **Dark Ranger** - full cast-event state machine (Black Arrow, Withering Fire, Wailing Arrow timing, Barbed Shot charge dump)
  - **Pack Leader** - streamlined profile (BW management, charge dump, Nature's Ally weaving, Wild Thrash AoE)
- Automatic hero-path detection via `IsPlayerSpell` marker (switches on talent change)
- AoE support via nameplate counting (best-effort, threshold >= 3)

Planned direction:

- Marksmanship Hunter profiles (signal probes built, viability assessed)
- additional spec-aware heuristics where the available API makes them defensible

## What It Does

- Shows a compact hunter rotation queue on screen
- Uses Blizzard `C_AssistedCombat` as the base recommendation source
- Filters obvious utility noise such as `Call Pet` and `Revive Pet`
- Supports BM-specific cast-tracked state (Dark Ranger: Black Arrow, Bestial Wrath, Wailing Arrow; Pack Leader: BW management, Wild Thrash AoE)
- Nature's Ally Kill Command weaving (both profiles)
- Barbed Shot charge dump before Bestial Wrath (validated via `C_Spell.GetSpellCharges`)
- Shows cast-success feedback when a displayed recommendation is actually cast
- Supports best-effort cooldown swipes for readable non-GCD lockouts
- Keeps interrupt logic out of the primary queue by default
- Supports click-through while locked
- Registers a native `HunterFlow` category in the in-game Settings UI
- Keeps signal probe diagnostics disabled by default unless you explicitly enable them

## Design Constraints

`HunterFlow` is intentionally built around the current Retail API reality:

- primary combat state is heavily restricted in `Midnight`
- cooldown values are not broadly safe to depend on
- `Assisted Combat` remains the most reliable legal baseline

That means this addon aims to be:

- practical
- conservative
- transparent about what is heuristic vs. guaranteed

It does **not** claim to be a full replacement for legacy full-state rotation simulation.

## Framework Docs

The framework direction is documented here:

- [Project Goals](docs/PROJECT_GOALS.md)
- [API Constraints](docs/API_CONSTRAINTS.md)
- [Framework Model](docs/FRAMEWORK.md)
- [Profile Contract](docs/PROFILE_CONTRACT.md)
- [Profile Authoring Guide](docs/PROFILE_AUTHORING.md)

These docs are meant to capture the hard-won findings from the `Midnight` API changes so future class/spec integrations do not repeat the same mistakes.
They describe the target architecture, not a claim that the current alpha is already fully modularized.

## Commands

- `/hf lock`
- `/hf unlock`
- `/hf options`
- `/hf burst`
- `/hf hide`
- `/hf show`
- `/hf debug`
- `/hf diagnostics on|off`
- `/hf probe ...` (only when diagnostics are enabled)
- `/hunterflow`

## Installation

1. Copy the `HunterFlow` folder into:

```text
World of Warcraft/_retail_/Interface/AddOns/
```

2. Restart WoW or run `/reload`.
3. Log into a hunter.

## Current Scope Notes

BM Hunter is alpha-solid with both hero paths covered:

- Dark Ranger and Pack Leader profiles auto-detected and validated in-game
- cast-event timers (BW cooldown, Withering Fire window, BA cooldown) are heuristic estimates, not exact cooldown reads -- Midnight restricts direct cooldown access
- AoE target counting uses nameplate enumeration which is best-effort: it counts all visible hostile nameplates, not only mobs in active combat (documented as PARTIAL in `docs/SIGNAL_VALIDATION.md`)
- Pack Leader is intentionally leaner than Dark Ranger because the rotation has fewer decision points

If you use another hunter spec today, the addon will stay inactive instead of pretending to support behavior it does not yet model.

## Long-Term Direction

Near-term:

- Marksmanship Hunter profiles (signal probes and viability assessment already built)
- keep documenting which mechanics can be implemented directly, heuristically, or not at all

If the project eventually becomes truly class-agnostic beyond hunters, the framework contract should already support that. The current public branding, however, is still intentionally hunter-focused.

## Provenance

The current `HunterFlow` codebase is an original standalone addon repository built around:

- Blizzard `Assisted Combat`
- direct in-game testing on Retail `Midnight`
- cast-event-based heuristics developed during the initial BM alpha work

It is not presented as a continuation of any prior branded addon. Historical research into older rotation addons informed design decisions, but this repository ships as its own project with its own code and release history.

## License

Licensed under `GPL-3.0-or-later`. See [LICENSE](LICENSE).
