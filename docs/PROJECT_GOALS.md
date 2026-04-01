# Project Goals

`HunterFlow` needs explicit product goals so framework work, profile work, and UI work do not drift into contradictory directions.

## Primary Goal

Build a hunter-focused recommendation framework for Retail `Midnight` that is:

- lightweight
- performant on the live client
- honest about API limits
- still functionally useful enough that players can rely on it as a real rotational aid

In short:

`HunterFlow` should aim for the highest practical gameplay value per unit of client overhead.

## Product Principles

### 1. Performance is a feature

The addon should feel cheap to run.

That means:

- prefer event-driven state over constant recomputation
- prefer short, explainable rule evaluation over broad simulation
- avoid expensive per-frame work unless it is directly tied to visible output
- avoid unnecessary allocations, scans, or duplicate API calls in combat
- keep the UI small and responsive

### 2. Lightweight does not mean useless

The goal is not a tiny toy addon.

The goal is to stay lightweight **while still delivering the full practical functionality that is defensible under the `Midnight` API**.

That means `HunterFlow` should still try to provide:

- a reliable recommendation queue
- spec-aware profile behavior where signals are legal and validated
- configurable, understandable overrides
- useful debug visibility
- graceful fallback behavior when a signal is unavailable

### 3. Full functionality has a boundary

`HunterFlow` should pursue broad functionality inside the legal API surface, not outside it.

So "full functionality" does **not** mean:

- recreating a legacy full-state simulation engine
- pretending hidden resources, cooldowns, or aura state are known
- piling on features that require constant heavy polling or opaque inference

### 4. Explainability beats cleverness

Every rule should be understandable.

If a feature needs too much invisible state, too much CPU, or too much guesswork to justify itself, it should be reduced, deferred, or rejected.

### 5. Degrade safely

When a signal cannot be trusted:

- the profile should fall back cleanly
- the engine should prefer Blizzard `Assisted Combat`
- the addon should become simpler rather than wrong

## Engineering Implications

These goals imply a few concrete defaults:

- engine work should bias toward shared, reusable, low-overhead logic
- profiles should own narrowly scoped, validated rule/state logic
- UI should stay compact and cheap instead of becoming a heavyweight configuration surface
- new features should justify both their gameplay value and their runtime cost
- probe work and signal validation should happen before adding expensive or speculative behavior

## Non-Goals

`HunterFlow` is not trying to become:

- a kitchen-sink UI addon
- a hidden-state combat simulator
- a feature pile that grows faster than its validation model
- a framework that treats performance as something to optimize later

## Review Standard

A change is aligned only if it can answer both questions well:

1. Does this improve practical player value?
2. Does this preserve the lightweight, low-overhead character of the addon?

If the answer to either is weak, the change should be challenged before it lands.
