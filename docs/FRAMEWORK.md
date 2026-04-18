# Framework Model

`TrueShot` is structured around four layers:

1. `Engine`
2. `State`
3. `Profile`
4. `Presentation`

The current addon already uses this split in code. The framework remains intentionally conservative in runtime scope, but it is no longer in a single-profile early alpha state.

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

## 2. State

The `State/` layer owns shared, class-agnostic state that multiple profiles can query through engine conditions. It exists because profile-local timers were drifting into near-duplicate implementations of the same heuristics.

Current `State/` modules:

- `State/CDLedger.lua` - central cooldown tracker. Listens to `UNIT_SPELLCAST_SUCCEEDED`, resolves the base CD through `GetSpellBaseCooldown` with a hardcoded `spec.base_ms` fallback, applies haste scaling through `UnitSpellHaste("player")` when a spell is flagged `haste_scaled`. Exposes `cd_ready(spellID)` and `cd_remaining(spellID, op, value)` engine conditions. Profiles migrate off their `*_on_cd` shims onto these over time; shipped `Hunter.BM.PackLeader` is the first consumer as of v0.25.0.

The `State/` layer is:

- event-driven, no per-frame polling
- conservative about live API calls - every read goes through `pcall` + `issecretvalue` and degrades to a sane default when the client returns secret values
- class-agnostic - spell-specific entries are data, not module code

## 3. Profile

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

The same contract already supports non-Hunter groundwork profiles today, and it remains the intended shape if the project broadens further:

- `Mage.Fire.Sunfury`
- `Paladin.Ret.HeraldOfTheSun`

That said, the current public product promise is still Hunter-first. Other classes prove the framework can scale, but they are not the current quality bar.

## 4. Presentation

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

Today, `TrueShot` already has the broader framework shape in production code:

- one shared engine
- multiple shipped profile modules across several classes
- one shared presentation layer

The current reality is not "BM-only alpha" anymore.
The real constraint is different:

- Hunter remains the primary shipping target
- Hunter is the class family that should justify a future `1.0`
- other classes exist as foundation and early expansion lanes, not as equal product promises

The purpose of this document is to keep that broader codebase aligned without losing its lightweight character.
