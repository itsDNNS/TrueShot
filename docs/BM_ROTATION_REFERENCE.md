# BM Rotation Reference

## Sources

| Tier | Source | URL | Stamp |
| --- | --- | --- | --- |
| primary | Azortharion - Icy Veins BM Hunter Rotation | https://www.icy-veins.com/wow/beast-mastery-hunter-pve-dps-rotation-cooldowns-abilities | Guide 2026-04-10 / Patch 12.0.4 |
| primary | Azortharion - BM Video Guide | https://youtu.be/GQiL-H8IZwA | Midnight Season 1 |
| cross-check | SimC midnight branch | https://github.com/simulationcraft/simc/tree/midnight/ActionPriorityLists/default `hunter_beast_mastery.simc` | Midnight default APL |
| cross-check | Wowhead - Tarlo | https://www.wowhead.com/guide/classes/hunter/beast-mastery/rotation-cooldowns-pve-dps | Patch 12.0.1, updated 2026-03-21 |
| supplementary | WCL parse analysis (40+ raid, 157 M+) | private notes | aggregated prior to Midnight Season 1 |

**Last reviewed: 2026-04-18** against the sources above.

This document is the authoritative reference for rule ordering in `Profiles/BM_DarkRanger.lua` and `Profiles/BM_PackLeader.lua`. When profile rules are changed, verify them against this priority list.

---

## Core Mechanic: Nature's Ally

Buffs Kill Command by 30% after casting any non-KC ability. **Never cast KC twice in a row.** Always weave at least one other ability between KC casts.

Critical: **Wild Thrash does NOT grant Nature's Ally.** KC -> WT -> KC is NOT a valid weave. You need a real filler (BS, BA, Cobra) between Kill Commands.

---

## Pack Leader

### Single-Target Priority

| # | Priority | Notes |
|---|----------|-------|
| 1 | Kill Command (with Nature's Ally) | Highest priority. Always alternate with fillers. |
| 2 | Barbed Shot | Always over Cobra Shot. Keep off 2 charges. |
| 3 | Cobra Shot | Filler when BS unavailable. |

The rotation is: KC -> BS -> KC -> BS/Cobra -> KC -> repeat. Never sit idle; if nothing else is available, Cobra Shot.

### Single-Target Opener

1. Puzzle Box (~2s pre-pull)
2. Barbed Shot x2 (dump all charges)
3. Bestial Wrath
4. Kill Command
5. Barbed Shot (as it comes back)
6. Kill Command
7. Continue normal rotation

### AoE Rotation

Same as ST but add **Wild Thrash every 8 seconds on cooldown**. Wild Thrash:
- Gives Beast Cleave (all pet attacks do AoE for 8s)
- Also does massive direct damage
- 8s CD = 100% Beast Cleave uptime if used on CD
- Is NOT a Nature's Ally filler (do not treat as weave between KCs)

**AoE priority: Wild Thrash on CD > KC with Nature's Ally > BS off 2 charges > Cobra Shot**

**BW in AoE**: Only press BW when Beast Cleave is already active (from Wild Thrash). BW itself needs to be buffed by Beast Cleave for AoE damage.

### AoE Opener

1. Puzzle Box (if possible)
2. Barbed Shot x2
3. Wild Thrash
4. Bestial Wrath
5. Kill Command
6. Continue rotation, Wild Thrash every 8s

### Bestial Wrath Timing

- 30s CD, 15s duration
- Dump all BS charges before BW. Holding a KC charge to enter BW with 2 is worth it.
- TrueShot: BW only blacklisted when on CD, NOT gated by BS charges (AC handles BS dump sequencing)

### TrueShot Profile Rules (BM_PackLeader.lua)

| Rule | Type | Condition | Rationale |
|------|------|-----------|-----------|
| Call Pet / Revive Pet / Counter Shot | BLACKLIST | always | Utility, never rotation |
| BW on CD | BLACKLIST_CONDITIONAL | bw_on_cd | Suppress when on CD |
| **Stampede (first KC after BW)** | **PIN** | **stampede_available** | **[src Azortharion 2026-04-10] "Activate Bestial Wrath. Once activated, your next Kill Command will spawn a Stampede." Flag is armed on BW cast, cleared on the next KC cast.** |
| KC proc glow | PIN | spell_glowing(KC) AND NOT last_cast_was_kc | Alpha Predator / Call of the Wild / Howl of the Pack Leader proc |
| Wild Thrash AoE | AoE Hint | in_combat AND target_count >= 2 AND NOT wt_on_cd | On CD in multi-target |
| KC anti-repeat | BLACKLIST_CONDITIONAL | last_cast_was_kc | Nature's Ally enforcement |
| Cobra Shot Focus pool | BLACKLIST_CONDITIONAL | focus<65 AND KC usable | Avoid depleting Focus before KC |

---

## Dark Ranger

### Single-Target Priority

| # | Priority | Notes |
|---|----------|-------|
| 1 | Trinkets | Stat-granting on-use trinkets right before BW (buffs up-front damage). |
| 2 | Bestial Wrath | Dump all BS charges before casting. Holding a KC charge to enter BW with 2 is worth it. |
| 3 | Kill Command (with Nature's Ally) | On CD. "KC is more powerful than BA in virtually every circumstance." |
| 4 | Black Arrow (in Withering Fire) | During first 10s of BW only. |
| 5 | Wailing Arrow | When 7s left on BW (~2.5s left on WF). Procs a free BA - follow up with it. |
| 6 | Barbed Shot | Filler. Keep off 2 charges. |
| 7 | Black Arrow (outside WF) | Lower prio than BS as filler. |
| 8 | Cobra Shot | Last resort filler. |

"The main thing that can catch you out is trying to over-prioritize Black Arrow."

### Withering Fire Window (first 10s of BW)

During Withering Fire:
1. Black Arrow is highest DPS priority (procs from BW activation)
2. Wailing Arrow when WF is less than 2.5s from ending (~7s left on BW)
3. WA procs a free Black Arrow -- use it immediately

### Single-Target Opener

1. Hunter's Mark active on target
2. Puzzle Box (~2s pre-pull)
3. Barbed Shot
4. Potion, Racials, etc.
5. Bestial Wrath
6. Kill Command
7. Black Arrow
8. Kill Command
9. Continue rotation. WA when 7s left on BW.

### AoE Rotation

| # | Priority | Notes |
|---|----------|-------|
| 1 | Black Arrow | If Beast Cleave is expiring. BA gives Beast Cleave (DR exclusive). |
| 2 | Bestial Wrath | Ensure Beast Cleave is up first. |
| 3 | Wild Thrash | On cooldown. Primary AoE damage + Beast Cleave. |
| 4 | Kill Command (with Nature's Ally) | On CD. Banking a charge for BW is a minor DPS increase. |
| 5 | Black Arrow (in Withering Fire) | During first 10s of BW. |
| 6 | Barbed Shot (if on 2 charges) | Prevent charge cap. |
| 7 | Wailing Arrow | When WF less than 2.5s from ending, follow up with BA. |
| 8 | Barbed Shot | On CD. |
| 9 | Wailing Arrow | Outside WF. |
| 10 | Black Arrow | Outside WF. |
| 11 | Cobra Shot | Filler. |

### AoE Opener (Dark Ranger specific!)

Different from Pack Leader because Black Arrow provides initial Beast Cleave:
1. Hunter's Mark active on target
2. Puzzle Box (if possible, often skipped in M+ pulls)
3. **Black Arrow** (gives Beast Cleave first!)
4. Barbed Shot
5. (If tank still gathering pull, coast with baseline rotation until stacked)
6. Potion, Racials, etc.
7. Wild Thrash (if Beast Cleave needed, otherwise after BW)
8. Bestial Wrath
9. Kill Command
10. Barbed Shot
11. Kill Command
12. Black Arrow
13. Continue rotation. WA when no more BS or KC available.

### Bestial Wrath Timing

Dump all BS charges before BW. Holding a KC charge to enter BW with 2 is worth it.

### TrueShot Profile Rules (BM_DarkRanger.lua)

| Rule | Type | Condition | Rationale |
|------|------|-----------|-----------|
| Call Pet / Revive Pet / Counter Shot | BLACKLIST | always | Utility, never rotation |
| BW on CD | BLACKLIST_CONDITIONAL | bw_on_cd | Suppress when on CD |
| BA during Withering Fire | PIN | ba_ready AND in_wf | Highest DPS during burst |
| WA near end of WF | PREFER | wa_available AND wf_ending(2.5s) | Sneak extra BA proc into window |
| BA outside WF | PREFER | ba_ready AND NOT in_wf | Filler priority over Cobra |
| Wild Thrash AoE | AoE Hint | in_combat AND target_count >= 2 AND NOT wt_on_cd | On CD in multi-target |
| KC anti-repeat | BLACKLIST_CONDITIONAL | last_cast_was_kc | Nature's Ally enforcement |

---

## Not Modeled (Intentional)

| Element | Reason |
|---------|--------|
| Beast Cleave uptime | Buff tracking is secret. Wild Thrash on CD provides 100% uptime. |
| Focus management | `UnitPower("player", 2)` is currently called via the `resource` condition type in Engine for a conservative Focus-pool heuristic. docs/API_CONSTRAINTS.md classifies Focus as secret/unsafe; a prior local note claimed the call was readable (2026-04-10) but this has not been re-probed under `/ts probe`. Treat the behaviour as heuristic until signal status is re-validated. |
| Opener sequence | AC handles initial spells, profile rules take over after first cast events. |
| Black Arrow availability (>80% HP / proc) | Proc state is secret. AC handles BA availability. |
| Trinket usage | External to rotation logic. |
| Hunter's Mark | Passive/manual, not a queue decision. |
| Barbed Shot charge timing vs BA priority | Would need focus + CD interaction modeling. AC handles this tradeoff. |
| Wild Thrash as invalid Nature's Ally source | Handled: WT cast does not clear lastCastWasKC flag, so KC -> WT -> KC is correctly blocked by the anti-repeat blacklist. |

---

## WCL Validation Summary

Based on 40 raid parses (4 bosses) + 157 M+ parses (8 dungeons):

- KC: 16-18 CPM, avg 3.4s gap (on CD)
- Nature's Ally compliance: 94-99% (even top players occasionally break it)
- BW: Guide now recommends dumping BS charges before BW (updated from earlier WCL findings)
- Wild Thrash M+: 3.58 CPM avg, 79% on CD rate, 100% of runs use it
- Wild Thrash Raid: Boss-dependent (0 on pure ST, 2.6 on AoE)
- BS before BW: Guide says dump charges; earlier WCL showed 18-24% compliance (meta may have shifted)
