# BM Dark Ranger Rotation Reference

Source: Icy Veins BM Hunter PvE Guide (Midnight Season 1)

This document is the authoritative reference for rule ordering in `Profiles/BM_DarkRanger.lua`. When profile rules are changed, verify them against this priority list.

## Single-Target Rotation

Icy Veins priority (# column) vs TrueShot implementation. Note: Icy Veins numbers don't map 1:1 to rule order because TrueShot uses blacklists and AC passthrough instead of explicit PREFER rules for some priorities.

| # | Icy Veins Priority | TrueShot Implementation | Mechanism |
|---|-------------------|------------------------|-----------|
| 1 | Activate BW (all BS charges spent first) | BW blacklisted when on CD or charges > 0 | BLACKLIST_CONDITIONAL |
| 2 | KC on CD with Nature's Ally | KC anti-repeat blacklist. AC handles KC timing. | BLACKLIST_CONDITIONAL |
| 3 | BA during Withering Fire | PIN BA when ba_ready AND in_wf | PIN (highest rule prio) |
| 4 | WA at 7s left on BW | PREFER WA when wa_available AND wf_ending(3s) | PREFER |
| 5 | Barbed Shot as filler | AC passthrough | -- |
| 6 | BA outside WF | PREFER BA when ba_ready AND NOT in_wf | PREFER |
| 7 | Cobra Shot filler | AC passthrough | -- |

### Actual Rule Order in Profile (PIN/PREFER only)

This is the order rules are evaluated in `BM_DarkRanger.lua`:

1. PIN BA "Withering Fire" (ba_ready AND in_wf)
2. PREFER WA "WF Ending" (wa_available AND wf_ending)
3. PREFER BA "BA Ready" (ba_ready AND NOT in_wf)
4. PREFER BS "Charge Dump" (charges > 0 AND bw_nearly_ready)
5. PREFER Wild Thrash "AoE 3+" (target_count >= 3)

### Single-Target Opener

1. Barbed Shot x2 (dump charges)
2. Bestial Wrath
3. Kill Command
4. Black Arrow
5. Kill Command
6. Barbed Shot
7. Continue normal rotation. WA at 7s left on BW.

Note: opener sequence is not explicitly modeled. AC handles the first spells, profile rules take over once state machine has data.

## AoE Rotation

Same rule set as ST applies in AoE. The difference is that Wild Thrash PREFER fires when target_count >= 3.

| # | Icy Veins Priority | TrueShot Implementation | Mechanism |
|---|-------------------|------------------------|-----------|
| 1 | BA if Beast Cleave expiring | Not modeled (Beast Cleave buff is secret) | -- |
| 2 | Activate BW (Beast Cleave up) | BW blacklist (same as ST) | BLACKLIST_CONDITIONAL |
| 3 | Wild Thrash on CD | PREFER when target_count >= 3 | PREFER |
| 4 | KC on CD with Nature's Ally | KC anti-repeat blacklist | BLACKLIST_CONDITIONAL |
| 5 | BA during WF | PIN BA (same as ST) | PIN |
| 6 | WA at WF < 2.5s, then BA | PREFER WA (same as ST, 3s threshold) | PREFER |
| 7 | Barbed Shot on CD | AC passthrough | -- |
| 8 | Wailing Arrow | AC passthrough | -- |
| 9 | BA outside WF | PREFER BA (same as ST) | PREFER |
| 10 | Cobra Shot filler | AC passthrough | -- |

### AoE Opener

1. Black Arrow
2. Barbed Shot
3. Wild Thrash (if Beast Cleave needed)
4. Bestial Wrath
5. Kill Command
6. Black Arrow
7. Kill Command
8. Barbed Shot
9. Continue rotation. WA when out of BS/KC.

## Key Mechanics

### Nature's Ally
Buffs Kill Command after using non-KC abilities. Never cast KC twice in a row. Always weave other abilities between KC casts.

### Withering Fire
Active for the first 10 seconds of Bestial Wrath. Black Arrow is highest priority during this window.

### Wailing Arrow Timing
Cast at ~7s remaining on BW (= ~3s remaining on WF). Procs Black Arrow, follow up with BA.

### Bestial Wrath Prep
Always spend all Barbed Shot charges before casting BW. BW CD is 90s base, reduced by Barbed Shot casts (variable).

## Not Modeled (Intentional)

| Element | Reason |
|---------|--------|
| Beast Cleave uptime | Buff tracking is secret |
| Focus management | Focus is secret |
| Opener sequence | AC handles initial spells, state machine needs cast events |
| Trinket usage | External to rotation logic |
| Hunter's Mark | Passive/manual, not a queue decision |
