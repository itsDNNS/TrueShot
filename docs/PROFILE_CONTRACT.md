# Profile Contract

This document defines how a class/spec module plugs into `TrueShot`.

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
- a shared presentation layer in `Display.lua`
- multiple shipped profile modules across Hunter and foundation classes

That means this contract is not hypothetical.
It describes the actual shape new profile modules are expected to follow.

What is still intentionally narrow is not the module count, but the product promise:

- Hunter is still the primary shipping target
- Hunter is the class family being pushed toward `1.0`
- future profile work still needs its own validated signal surface before it should be treated as productized support

## Public Rule Language

Longer-term, profiles should be expressible in a compact declarative form.

Example direction:

```text
PIN BlackArrow WHEN ba_ready AND in_withering_fire
PREFER WailingArrow WHEN wa_available AND wf_ending_lt_3
SUPPRESS KillCommand WHEN last_cast_was_kc
```

But the framework should only expose a declarative rule when the engine has a real, legal signal behind it.

## Engine-level State Conditions

Some conditions are owned by the `State/` layer rather than by individual profiles. They are registered by the engine or by a `State/` module and are available in every profile context.

| Condition | Owner | Meaning |
| --- | --- | --- |
| `ac_suggested(spellID)` | `Engine` | Assisted Combat currently surfaces this spell in its primary or rotation suggestions. |
| `spell_charges(spellID, op, value)` | `Engine` | Charge-count read through `C_Spell.GetSpellCharges` (validated non-secret). |
| `spell_glowing(spellID)` | `Engine` | Blizzard's proc-glow overlay is active on this spell. |
| `target_count(op, value)` | `Engine` | Hostile nameplate count via `C_NamePlate.GetNamePlates`. |
| `target_casting` | `Engine` | `UnitCastingInfo("target")` / `UnitChannelInfo("target")` is non-nil. |
| `in_combat` | `Engine` | `UnitAffectingCombat("player")`. |
| `usable(spellID)` | `Engine` | `C_Spell.IsSpellUsable` passthrough (CD-blind, use with care). |
| `resource(powerType, op, value)` | `Engine` | `UnitPower("player", powerType)` - treat as heuristic until validated. |
| **`cd_ready(spellID)`** | **`State/CDLedger`** | **Tracked spell is not on cooldown.** |
| **`cd_remaining(spellID, op, value)`** | **`State/CDLedger`** | **Seconds until the tracked spell is ready, compared against `value`.** |

New profile rules that depend on cooldown readiness should use `cd_ready` or `cd_remaining` rather than a profile-local `*_on_cd` timer. Profile-local `*_on_cd` conditions remain valid as backward-compat shims, but new code should not add them.
