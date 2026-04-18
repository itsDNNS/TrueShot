# SV Rotation Reference

## Sources

| Tier | Source | URL | Stamp |
| --- | --- | --- | --- |
| primary | Azortharion - Icy Veins SV Hunter Rotation | https://www.icy-veins.com/wow/survival-hunter-pve-dps-rotation-cooldowns-abilities | Guide 2026-03-27 / Patch 12.0.4 |
| cross-check | SimC midnight branch | https://github.com/simulationcraft/simc/tree/midnight/ActionPriorityLists/default `hunter_survival.simc` | Midnight default APL (plst, plcleave, sentst, sentcleave) |
| cross-check | Wowhead SV Rotation | https://www.wowhead.com/guide/classes/hunter/survival/rotation-cooldowns-pve-dps | Patch 12.0.1, updated 2026-03-24 |

**Last reviewed: 2026-04-18** against the sources above.

This document is the authoritative shipped-rule reference for:

- `Profiles/SV_PackLeader.lua`
- `Profiles/SV_Sentinel.lua`

It describes the intentional `TrueShot` layer for Survival under the current legal Midnight API.

## Product Boundary

Survival contains several attractive mechanics that `TrueShot` should **not** fake.

That includes:

- Tip of the Spear stack precision
- Sentinel's Mark proc state
- Fury / hidden buff-state modeling
- exact cooldown truth through hidden state
- full resource simulation

Blizzard Assisted Combat stays responsible for the hidden-state-heavy baseline.

`TrueShot` adds targeted Survival value through:

- Takedown burst-window awareness
- conservative Wildfire Bomb charge-cap protection
- Boomstick timing inside the Takedown window
- hero-path-specific sequencing where cast events make it defensible

## SV Pack Leader

### Intent

Pack Leader's highest-value override is narrow and clear:

1. **Stampede sequencing immediately after Takedown**
2. **Do not waste Wildfire Bomb charges**
3. **Surface Boomstick / Flamefang in contexts where the legal signals support it**

### Shipped override baseline

| Rule | Type | Shipped condition | Why it exists |
| --- | --- | --- | --- |
| Kill Command immediately after Takedown | `PIN` | `takedown_active AND NOT kc_cast_in_takedown` | Capture the high-value first-KC-in-window behavior. |
| Wildfire Bomb at cap | `PREFER` | `wfb_charges == 2` | Conservative charge protection only. |
| Boomstick during Takedown | `PREFER` | `takedown_active AND NOT boomstick_on_cd` | Push Boomstick into the burst window without inventing exact cooldown truth. |
| Flamefang Pitch when AC already wants it | `PREFER` | `ac_suggested(Flamefang Pitch)` | Keep the gate legal and conservative. |

### Legal signal basis

| Mechanic | Signal class | Source |
| --- | --- | --- |
| Takedown was cast | direct | `UNIT_SPELLCAST_SUCCEEDED` |
| Kill Command already used in current Takedown | direct | `UNIT_SPELLCAST_SUCCEEDED` + local flag |
| Boomstick local cooldown gate | heuristic | bounded local timer from player cast |
| Wildfire Bomb cap | direct enough for shipped use | validated `currentCharges` from `C_Spell.GetSpellCharges` |
| Flamefang readiness gate | direct enough for shipped use | `ac_suggested(Flamefang Pitch)` |

### Explicit non-goals

- Do not use shared spell-ID tricks that can accidentally suppress Survival `Kill Command`
- Do not use raw `IsSpellUsable()` as cooldown truth for Flamefang
- Do not model hidden proc or resource state to overfit the window

## SV Sentinel

### Intent

Sentinel is similar in structure, but the shipped profile is intentionally more conservative than earlier design drafts.

The value lane is:

1. **Wildfire Bomb charge-cap prevention**
2. **Boomstick inside Takedown**
3. **Moonlight Chakram early in the Takedown window**
4. **Flamefang only when AC already surfaces it**

### Shipped override baseline

| Rule | Type | Shipped condition | Why it exists |
| --- | --- | --- | --- |
| Wildfire Bomb at cap | `PREFER` | `spell_charges >= 2` | Conservative charge protection without recharge-timing assumptions. |
| Boomstick during Takedown | `PIN` | `takedown_active AND NOT boomstick_on_cd` | High-value burst-window pin. |
| Moonlight Chakram early in Takedown | `PREFER` | `takedown_active AND takedown_just_cast(5)` | Bounded burst-window hint only. |
| Flamefang Pitch when AC already wants it | `PREFER` | `ac_suggested(Flamefang Pitch)` | Conservative legal gate. |

### Legal signal basis

| Mechanic | Signal class | Source |
| --- | --- | --- |
| Takedown was cast | direct | `UNIT_SPELLCAST_SUCCEEDED` |
| Takedown burst window | heuristic | bounded local timer after cast |
| Boomstick local cooldown gate | heuristic | bounded local timer from player cast |
| Wildfire Bomb cap | direct enough for shipped use | validated `currentCharges` from `C_Spell.GetSpellCharges` |
| Moonlight Chakram / Flamefang readiness gate | direct enough for shipped use | `ac_suggested(...)` via Blizzard Assisted Combat |

### Explicit non-goals

- Do not depend on unvalidated `GetSpellCharges()` recharge timing fields in shipped logic
- Do not try to reconstruct Sentinel's Mark fishing logic from hidden state
- Do not force Chakram or Flamefang outside their bounded, explainable windows

## Release Rule

For Survival, `1.0` should mean:

- the shipped conservative charge-cap path is still true in code
- no hidden-state simulation or raw cooldown-truth shortcuts have crept back in
- the pending live checks in `HUNTER_VALIDATION_MATRIX.md` are passed
