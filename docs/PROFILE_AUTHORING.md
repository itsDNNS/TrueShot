# Profile Authoring Guide

This guide turns the current `HunterFlow` framework into a repeatable authoring workflow for new hunter profiles and hero-path variants.

Use this together with:

- [Project Goals](PROJECT_GOALS.md)
- [API Constraints](API_CONSTRAINTS.md)
- [Framework Model](FRAMEWORK.md)
- [Profile Contract](PROFILE_CONTRACT.md)

The goal is not to encode every desirable idea from a guide.
The goal is to ship a profile that is:

- legal under `Midnight`
- lightweight on the client
- explainable in review
- honest about fallbacks

## Quick Start

1. Copy [`HunterProfileTemplate.lua`](templates/HunterProfileTemplate.lua).
2. Rename it for the target profile, for example `Profiles/MM_Sentinel.lua`.
3. Write down the guide or priority source you are translating.
4. Classify each desired mechanic as:
   - `direct`
   - `heuristic`
   - `impossible`
   - `unknown`
5. Keep only the mechanics that survive the API and runtime-cost checks.
6. Implement state and rules for those mechanics.
7. Add the profile file to `HunterFlow.toc` only when it is ready to register.
8. Test with `/hf debug` before claiming the profile is usable.

## Rule Classification

Every desired mechanic must be classified before it becomes code.

### `direct`

Use this when the rule depends on data that is intentionally available.

Examples:

- Blizzard `C_AssistedCombat` recommendations
- `IsPlayerSpell(spellID)`
- `UNIT_SPELLCAST_SUCCEEDED` for `player`

### `heuristic`

Use this when the rule depends on a legal inference from observable events.

Examples:

- "Bestial Wrath was cast 8 seconds ago, so the Withering Fire window is probably still active."
- "Black Arrow was cast 11 seconds ago, so it is probably ready again."

Every heuristic must document:

- what event starts it
- what event clears it
- what timer or fallback bounds it
- what happens if it becomes uncertain

### `impossible`

Use this when the mechanic depends on state that `HunterFlow` should not fake.

Examples:

- exact hidden cooldown remaining
- exact `Focus`
- hidden buff stack counts

`Impossible` mechanics are not "later features".
They are rejected until Blizzard exposes a legal signal.

### `unknown`

Use this when the signal might be usable, but has not been proven yet.

Examples:

- target counting on a spec that has not been validated in live AoE yet
- a charge API that has not been tested on the relevant spell

`Unknown` mechanics must become explicit probe work, not speculative code.

## Runtime-Cost Filter

Before writing a rule, answer these:

1. Is the signal event-driven or does it require repeated polling?
2. Does the rule add meaningful gameplay value or only theoretical fidelity?
3. Can the rule degrade safely if the signal disappears?
4. Is the same result already good enough through Blizzard `Assisted Combat`?
5. Would this rule still be worth it if the addon must stay lightweight in combat?

If the answer is weak, do not implement the rule yet.

## Authoring Worksheet

Fill this out before coding a new profile:

| Desired mechanic | Source | Class | Runtime cost | Fallback | Keep? |
| --- | --- | --- | --- | --- | --- |
| Example: burst window | player cast event | heuristic | low | timer expires, fall back to AC | yes |
| Example: exact proc stacks | hidden buff | impossible | n/a | none | no |

## Worked Example: BM / Dark Ranger

Guide-style intention:

1. Use `Black Arrow` aggressively during `Withering Fire`.
2. Spend `Wailing Arrow` near the end of `Withering Fire`.
3. Avoid repeating `Kill Command` back-to-back.

Translation:

| Mechanic | Class | Why |
| --- | --- | --- |
| `Bestial Wrath` opens a 10s burst window | `heuristic` | player cast event plus bounded timer |
| `Black Arrow` becomes ready again after `Bestial Wrath` / `Wailing Arrow` | `heuristic` | reset source is observable through player casts |
| `Wailing Arrow` available after `Bestial Wrath` | `heuristic` | unlocked by observable cast, cleared by observable cast |
| `Kill Command` anti-repeat weaving | `heuristic` | last player cast is observable |
| exact Deathblow proc state | `impossible` or bounded fallback | proc source is not directly trustworthy, so only timer-based fallback is acceptable |

Resulting rules:

```text
PIN Black Arrow WHEN ba_ready AND in_withering_fire
PREFER Wailing Arrow WHEN wa_available AND wf_ending_lt_4
BLACKLIST_CONDITIONAL Kill Command WHEN last_cast_was_kc
```

Why this is acceptable:

- every active rule is backed by observable casts or a bounded local timer
- nothing claims exact hidden resource or buff knowledge
- when the heuristic is uncertain, Blizzard AC remains the baseline

## Fallback Rules

Every profile must state what happens when supporting signals fail.

Examples:

- If target casting is unavailable, do not surface interrupt guidance.
- If target counting is unavailable, do not enable AoE preference logic.
- If a cast-tracked timer becomes uncertain, fall back to Blizzard AC instead of forcing a speculative recommendation.

## File Layout

Current pattern for a real profile file:

```text
HunterFlow/
  Engine.lua
  Display.lua
  Core.lua
  Profiles/
    BM_DarkRanger.lua
```

Authoring template:

- [`HunterProfileTemplate.lua`](templates/HunterProfileTemplate.lua)

Only add a new profile to `HunterFlow.toc` when the module is ready to register and be loaded by the addon.

## Review Standard

A new profile or hero-path rule is only ready if a reviewer can answer:

1. Which signal makes this legal?
2. Why is this lightweight enough to keep?
3. What is the fallback when the signal is missing or uncertain?

If those answers are not crisp, the profile is not ready yet.
