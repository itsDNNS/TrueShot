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

Current implementation focus:

- Beast Mastery Hunter
- BM heuristics currently tuned around a tested Dark Ranger build

Planned direction:

- broader hunter support over time
- more configurable overlays and profiles
- additional spec-aware heuristics where the available API makes them defensible
- frameworkized profile modules instead of one hard-coded alpha profile

## What It Does

- Shows a compact hunter rotation queue on screen
- Uses Blizzard `C_AssistedCombat` as the base recommendation source
- Filters obvious utility noise such as `Call Pet` and `Revive Pet`
- Supports BM-specific cast-tracked state for:
  - `Black Arrow`
  - `Bestial Wrath`
  - `Wailing Arrow`
  - `Nature's Ally`-style `Kill Command` weaving
- Keeps interrupt logic out of the primary queue by default
- Supports click-through while locked

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

These docs are meant to capture the hard-won findings from the `Midnight` API changes so future class/spec integrations do not repeat the same mistakes.
They describe the target architecture, not a claim that the current alpha is already fully modularized.

## Commands

- `/hf lock`
- `/hf unlock`
- `/hf burst`
- `/hf hide`
- `/hf show`
- `/hf debug`
- `/hunterflow`

## Installation

1. Copy the `HunterFlow` folder into:

```text
World of Warcraft/_retail_/Interface/AddOns/
```

2. Restart WoW or run `/reload`.
3. Log into a hunter.

## Current Scope Notes

The current alpha is honest but narrow:

- branding is hunter-wide
- the initial shipped profile is BM Hunter
- the current BM heuristics were tested primarily against a Dark Ranger build

If you use another hunter spec today, the addon will stay inactive instead of pretending to support behavior it does not yet model.

## Long-Term Direction

Near-term:

- support more hunter specs and hero paths through explicit profiles
- factor the current BM logic into a clearer profile module boundary
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
