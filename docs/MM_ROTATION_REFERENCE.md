# MM Rotation Reference

## Sources

| Tier | Source | URL | Stamp |
| --- | --- | --- | --- |
| primary | Azortharion - Icy Veins MM Hunter Rotation | https://www.icy-veins.com/wow/marksmanship-hunter-pve-dps-rotation-cooldowns-abilities | Guide 2026-04-09 / Patch 12.0.4 |
| cross-check | SimC midnight branch | https://github.com/simulationcraft/simc/tree/midnight/ActionPriorityLists/default `hunter_marksmanship.simc` | Midnight default APL |
| cross-check | Wowhead MM Rotation | https://www.wowhead.com/guide/classes/hunter/marksmanship/rotation-cooldowns-pve-dps | Patch 12.0.1, updated 2026-04-15 |
| spec fact | Wowhead Sentinel Hero | https://www.wowhead.com/guide/classes/hunter/marksmanship/hero-talents | Sentinel: Moonlight Chakram replaces the Trueshot button while Trueshot is active |

**Last reviewed: 2026-04-18** against the sources above.

This document is the authoritative shipped-rule reference for:

- `Profiles/MM_DarkRanger.lua`
- `Profiles/MM_Sentinel.lua`

Its job is narrower than a full class guide.
It defines what `TrueShot` is intentionally trying to do for Marksmanship under the current legal Midnight API.

## Product Boundary

`TrueShot` is not trying to simulate full MM rotational state.

It deliberately does **not** attempt to model:

- Precise Shots
- Lock and Load
- Bulletstorm stacks
- exact cooldown truth through hidden state
- exact Focus planning

Those stay with Blizzard Assisted Combat.

The MM override layer is intentionally focused on:

- burst-window timing
- anti-overlap cleanup
- Black Arrow / Wailing Arrow sequencing where Dark Ranger provides legal cast-event anchors
- Moonlight Chakram surfacing only when the current legal signals support it

## MM Dark Ranger

### Intent

Dark Ranger adds the clearest override value in two places:

1. **Trueshot burst sequencing**
2. **Black Arrow / Wailing Arrow management during the Trueshot + Withering Fire window**

### Shipped override baseline

| Rule | Type | Shipped condition | Why it exists |
| --- | --- | --- | --- |
| Trueshot right after Volley blocked | `BLACKLIST_CONDITIONAL` | `volley_recent(2)` | Avoid wasteful anti-synergy between Volley and Trueshot. |
| Volley right after Trueshot blocked | `BLACKLIST_CONDITIONAL` | `trueshot_just_cast(2)` | Same anti-overlap in the other direction. |
| Black Arrow immediately after Trueshot | `PIN` | `ba_ready AND trueshot_just_cast(2)` | Spend the free opener proc cleanly. |
| Wailing Arrow inside Trueshot opener | `PIN` | `wa_available AND NOT ba_ready AND trueshot_active` | Preserve the intended `TS -> BA -> WA -> BA` flow. |
| Black Arrow during Withering Fire | `PIN` | `ba_ready AND in_withering_fire` | Highest-value BA window in the Dark Ranger lane. |
| Trueshot on the main cooldown | `PIN` | `ac_suggested(Trueshot) AND in_combat` | Surface Trueshot whenever Assisted Combat treats it as castable; the anti-overlap BLACKLIST rules still force a single interleaving GCD around Volley. Replaces a prior `rapid_fire_recent(3)` gate that treated the "Rapid Fire -> Trueshot -> Aimed Shot" guidance as a hard precondition and caused Trueshot to never surface for openers that did not begin with Rapid Fire (issue #89). |
| Black Arrow outside Withering Fire | `PREFER` | `ba_ready AND NOT in_withering_fire` | Soft nudge only, not a full hard-override outside burst. |

### Legal signal basis

| Mechanic | Signal class | Source |
| --- | --- | --- |
| Trueshot was cast | direct | `UNIT_SPELLCAST_SUCCEEDED` |
| Rapid Fire was cast recently | direct | `UNIT_SPELLCAST_SUCCEEDED` |
| Volley was cast recently | direct | `UNIT_SPELLCAST_SUCCEEDED` |
| Withering Fire window | heuristic | bounded local timer after Trueshot cast |
| Black Arrow readiness fallback | heuristic | bounded local timer plus cast-driven resets |
| Trueshot readiness gate | direct enough for shipped use | `ac_suggested(Trueshot)` via Blizzard Assisted Combat |

### Explicit non-goals

- Do not force exact cooldown planning through `C_Spell.IsSpellUsable()`
- Do not model hidden proc state beyond what cast events legally unlock
- Do not over-prioritize Black Arrow outside the clearly bounded burst windows

## MM Sentinel

### Intent

Sentinel is intentionally leaner.

Its override layer is mainly about:

1. **Post-Rapid-Fire Trueshot timing**
2. **Blocking bad Trueshot / Volley overlap**
3. **Treating Moonlight Chakram as a late Trueshot-window filler rather than a general priority spell**

### Shipped override baseline

| Rule | Type | Shipped condition | Why it exists |
| --- | --- | --- | --- |
| Trueshot right after Volley blocked | `BLACKLIST_CONDITIONAL` | `volley_recent(2)` | Avoid overlap waste. |
| Volley right after Trueshot blocked | `BLACKLIST_CONDITIONAL` | `trueshot_just_cast(2)` | Same anti-overlap in the other direction. |
| Trueshot on the main cooldown | `PIN` | `ac_suggested(Trueshot) AND in_combat` | Sentinel surfaces Trueshot whenever Assisted Combat treats it as castable. Azortharion lists Volley as ST #1 for Sentinel; when both are simultaneously ready the PIN now surfaces Trueshot first and the anti-overlap BLACKLIST on Volley forces at least one intervening cast in typical play before Volley is shown again, which stays within the guide's anti-back-to-back rule. Replaces a prior `rapid_fire_recent(3)` gate that caused Trueshot to never surface for openers that did not start with Rapid Fire (issue #89). |
| Moonlight Chakram outside Trueshot blocked | `BLACKLIST_CONDITIONAL` | `NOT trueshot_active` | Keep Chakram from surfacing in the wrong context. |
| Moonlight Chakram as late Trueshot filler | `PREFER` | `ac_suggested(MoonlightChakram) AND trueshot_active AND NOT aimed_shot_ready` | Only elevate it when the safer filler window is present. |

### Legal signal basis

| Mechanic | Signal class | Source |
| --- | --- | --- |
| Trueshot was cast | direct | `UNIT_SPELLCAST_SUCCEEDED` |
| Rapid Fire was cast recently | direct | `UNIT_SPELLCAST_SUCCEEDED` |
| Volley was cast recently | direct | `UNIT_SPELLCAST_SUCCEEDED` |
| Trueshot active | heuristic with direct upgrade | player aura check first, timer fallback second |
| Aimed Shot availability | direct enough for shipped use | validated charge count from `C_Spell.GetSpellCharges` |
| Trueshot / Chakram readiness gate | direct enough for shipped use | `ac_suggested(...)` via Blizzard Assisted Combat |

### Explicit non-goals

- Do not force Chakram as a general-purpose priority spell
- Do not infer hidden proc windows beyond what the cast/aura surface makes defensible
- Do not claim full MM optimization; the goal is targeted correction of obvious AC blind spots

## Release Rule

For Marksmanship, `1.0` should mean:

- the shipped override layer above is still true in code
- no raw `IsSpellUsable()` dependency is reintroduced for cooldown-sensitive priority
- the pending live checks in `HUNTER_VALIDATION_MATRIX.md` are passed
