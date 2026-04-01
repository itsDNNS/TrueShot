# Profile Contract

This document defines how a class/spec module should plug into `TrueShot` once the alpha is split into explicit profile modules.

A profile is a data-and-state package, not a second engine.

## Required Profile Fields

Target shape for a modularized profile:

```lua
{
  id = "Hunter.BM.DarkRanger",
  class = "HUNTER",
  specID = 253,
  markerSpell = 466930,  -- hero-path exclusive spell for auto-detection
  hero = "DarkRanger",
  state = { ... },
  rules = { ... },
}
```

### markerSpell (optional)

When multiple profiles share the same `specID`, the engine uses `markerSpell` to pick the correct one. The engine calls `IsPlayerSpell(markerSpell)` during activation and selects the first profile whose marker is known to the player. Profiles without a `markerSpell` serve as fallback.

## Required Behavior

Each profile must answer:

1. When is this profile active?
2. Which spells matter for tracked state?
3. Which observed casts cause state transitions?
4. Which queue rules are justified by observable data?
5. What happens when supporting signals are unavailable?

## Activation Contract

A profile may activate only when:

- class matches
- spec matches
- any required sub-branch or hero context is known well enough

If hero/talent context cannot be proven safely, the profile must:

- remain inactive
- or fall back to a less specific profile

## State Hooks

Profiles should expose hooks like:

```lua
profile:ResetState()
profile:OnSpellCast(spellID)
profile:OnCombatEnd()
profile:EvalCondition(condition)
profile:GetDebugLines()
```

This keeps spec-specific logic out of the generic queue engine.

## Rule Authoring Rules

A profile rule is only valid if it satisfies one of these:

- it depends on Blizzard recommendation output
- it depends on directly observed player cast events
- it depends on coarse target-side information that can degrade safely

A profile rule is invalid if it depends on:

- exact hidden cooldown values
- hidden primary resource values
- hidden aura state
- unverifiable proc assumptions

## Spec Author Checklist

Before adding a new class/spec profile:

1. Write down the priority source you are using.
2. Mark each desired rule as:
   - direct
   - heuristic
   - impossible
3. List all spells that must be cast-tracked.
4. List every reset/proc source you can actually observe.
5. Define fallback behavior for missing signals.
6. Ask whether each rule is worth its runtime cost.
7. Test the profile with `/ts debug` output before claiming correctness.

## BM / Dark Ranger Example

Observed events:

- `Bestial Wrath`
- `Black Arrow`
- `Wailing Arrow`
- `Kill Command`

Profile state:

- `blackArrowReady`
- `witheringFireUntil`
- `wailingArrowAvailable`
- `lastCastWasKC`
- estimated `Bestial Wrath` suppression window

Rule examples:

- `PIN Black Arrow` during `Withering Fire` when locally tracked as ready
- `PREFER Wailing Arrow` near end of `Withering Fire`
- conditionally suppress repeated `Kill Command`

## Current State

The current addon now has:

- a generic `Engine.lua`
- a presentation layer in `Display.lua`
- a real BM profile module in `Profiles/BM_DarkRanger.lua`

That means this contract is no longer hypothetical.
It describes the actual direction new profile modules should follow.

What is still intentionally narrow:

- only one shipped hunter profile exists today
- hero-path specificity is still encoded in that one BM profile module
- future specs still need their own validated signal surface before implementation

## Public Rule Language

Longer-term, profiles should be expressible in a compact declarative form.

Example direction:

```text
PIN BlackArrow WHEN ba_ready AND in_withering_fire
PREFER WailingArrow WHEN wa_available AND wf_ending_lt_3
SUPPRESS KillCommand WHEN last_cast_was_kc
```

But the framework should only expose a declarative rule when the engine has a real, legal signal behind it.
