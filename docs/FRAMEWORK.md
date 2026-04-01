# Framework Model

`HunterFlow` is now structured around three layers:

1. `Engine`
2. `Profile`
3. `Presentation`

The current addon already uses this split in code, but the framework is still early and intentionally narrow in runtime scope.

## 1. Engine

The engine owns:

- base queue acquisition from `C_AssistedCombat`
- event registration
- local state tracking
- rule evaluation
- queue filtering / override application
- safe degradation behavior

The engine must stay class-agnostic where possible.

Core engine responsibilities:

- fetch Blizzard recommendations
- evaluate framework-safe conditions
- apply profile rules in deterministic order
- expose debug state

## 2. Profile

A profile is the only place that should know class/spec-specific logic in the target architecture.

A profile defines:

- activation scope
- tracked spells
- state transitions
- rule list
- optional display hints

Examples:

- `Hunter.BM.DarkRanger`
- `Hunter.MM.Sentinel`
- `Hunter.SV.PackLeader`

If the project ever broadens beyond hunters, the same contract can hold:

- `Mage.Fire.Sunfury`
- `Paladin.Ret.HeraldOfTheSun`

That said, the current public branding is still hunter-focused. If the long-term goal becomes truly all classes, the product name should eventually be revisited.

## 3. Presentation

Presentation owns:

- icon count
- positioning
- click-through behavior
- future cooldown/GCD sweep rendering when a lightweight legal implementation exists
- text overlays / keybind overlays

Presentation must not own combat logic.

## Queue Decision Order

Every frame update should conceptually resolve in this order:

1. Get Blizzard base recommendation
2. Build dynamic blockers for the current frame
3. Apply `PIN` rules
4. Apply `PREFER` rules
5. Fall back to Blizzard recommendation
6. Fill remaining queue from Blizzard rotation list

## Rule Classes

Supported rule types today:

- `BLACKLIST`
- `BLACKLIST_CONDITIONAL`
- `PIN`
- `PREFER`

Potential future rule types:

- `DEFER`
- `SIDE_TRACK`
- `PROMOTE_IF`
- `SUPPRESS_IF`

Rules must remain explainable. If a user cannot understand why a rule fired, the framework is becoming too opaque.

## State Model

The framework should distinguish between:

- `guaranteed state`
- `heuristic state`
- `display state`

### Guaranteed state

Derived from directly observed events.

Example:

- "player cast `Bestial Wrath` at time T"

### Heuristic state

Derived from legal inference.

Example:

- "`Black Arrow` is probably ready because:
  - `Bestial Wrath` reset it, or
  - the last observed cast was more than 10s ago"

### Display state

What the addon chooses to show.

Example:

- queue of top 2 icons
- interrupt pin
- GCD sweep

## Degradation Rules

Every profile feature must define its fallback:

- if target casting cannot be trusted, interrupt pin simply does not fire
- if nameplate count is unavailable, AoE preference does not fire
- if cast tracking breaks, fall back to Blizzard AC base queue

The engine should never fail hard when a profile-specific heuristic cannot run.

## Current Reality

Today, `HunterFlow` is still earlier than the eventual broader framework goal:

- one shared engine
- one shipped BM profile path
- one compact display implementation

That is acceptable for the alpha. The purpose of this document is to define how the code should keep expanding without losing its lightweight character.
