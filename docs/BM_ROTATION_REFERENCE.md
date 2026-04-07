# BM Rotation Reference

Source: Gingi (top world Hunter) BM Guide for Midnight Season 1
Video: https://youtu.be/GQiL-H8IZwA
Supplementary: WCL analysis (40+ raid parses, 157 M+ parses), Icy Veins

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
- WCL data: 78%+ of top players press BW immediately, even with BS charges available
- "If in doubt, don't hold it. Only hold for something blindingly obvious."
- TrueShot: BW only blacklisted when on CD, NOT gated by BS charges

### TrueShot Profile Rules (BM_PackLeader.lua)

| Rule | Type | Condition | Rationale |
|------|------|-----------|-----------|
| Call Pet / Revive Pet / Counter Shot | BLACKLIST | always | Utility, never rotation |
| BW on CD | BLACKLIST_CONDITIONAL | bw_on_cd | Suppress when on CD |
| Wild Thrash AoE | AoE Hint | in_combat AND target_count >= 2 AND NOT wt_on_cd | On CD in multi-target |
| KC anti-repeat | BLACKLIST_CONDITIONAL | last_cast_was_kc | Nature's Ally enforcement |

---

## Dark Ranger

### Single-Target Priority

| # | Priority | Notes |
|---|----------|-------|
| 1 | Kill Command (with Nature's Ally) | Always highest. "KC is more powerful than BA in virtually every circumstance." |
| 2 | Barbed Shot (if on 2 charges) | Prevent charge cap. Higher prio than BA when capped. |
| 3 | Black Arrow | Great filler, NOT main ability. Available on CD, >80% HP target, or proc. |
| 4 | Cobra Shot | Last resort filler. |

"The main thing that can catch you out is trying to over-prioritize Black Arrow."

### Withering Fire Window (first 10s of BW)

During Withering Fire:
1. Black Arrow is highest DPS priority (procs from BW activation)
2. Wailing Arrow near end of WF window (~7s left on BW = ~3s WF remaining)
3. WA procs a free Black Arrow -- use it immediately
4. "Think of Wailing Arrow as a Black Arrow replacement" when BA not available

### Single-Target Opener

1. Puzzle Box (~2s pre-pull)
2. Barbed Shot x2
3. Bestial Wrath
4. Kill Command
5. Black Arrow
6. Kill Command
7. Barbed Shot
8. Continue rotation. WA within WF window.

### AoE Rotation

Same core rotation as ST, plus:
- **Wild Thrash every 8 seconds on CD** (for damage, not just Beast Cleave)
- Black Arrow also gives Beast Cleave (DR exclusive)
- Wild Thrash damage is the primary reason to use it; Beast Cleave is secondary for DR

**DR AoE priority: Wild Thrash on CD > KC with Nature's Ally > BA (if BS not on 2 charges) > BS on 2 charges > Cobra**

### AoE Opener (Dark Ranger specific!)

Different from Pack Leader because Black Arrow provides initial Beast Cleave:
1. Puzzle Box (if possible)
2. **Black Arrow** (gives Beast Cleave first!)
3. Barbed Shot
4. Bestial Wrath (Beast Cleave already active from BA)
5. Wild Thrash (buffed by BW)
6. Kill Command
7. Continue rotation

### Bestial Wrath Timing

Same as Pack Leader: press immediately, don't hold.

### TrueShot Profile Rules (BM_DarkRanger.lua)

| Rule | Type | Condition | Rationale |
|------|------|-----------|-----------|
| Call Pet / Revive Pet / Counter Shot | BLACKLIST | always | Utility, never rotation |
| BW on CD | BLACKLIST_CONDITIONAL | bw_on_cd | Suppress when on CD |
| BA during Withering Fire | PIN | ba_ready AND in_wf | Highest DPS during burst |
| WA near end of WF | PREFER | wa_available AND wf_ending(3s) | Sneak extra BA proc into window |
| BA outside WF | PREFER | ba_ready AND NOT in_wf | Filler priority over Cobra |
| Wild Thrash AoE | AoE Hint | in_combat AND target_count >= 2 AND NOT wt_on_cd | On CD in multi-target |
| KC anti-repeat | BLACKLIST_CONDITIONAL | last_cast_was_kc | Nature's Ally enforcement |

---

## Not Modeled (Intentional)

| Element | Reason |
|---------|--------|
| Beast Cleave uptime | Buff tracking is secret. Wild Thrash on CD provides 100% uptime. |
| Focus management | Focus is secret (validated: ShouldUnitPowerBeSecret = true). Leave 40 focus for WT in AoE is not enforceable. |
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
- BW: 78%+ pressed immediately without BS dump (charge-dump rule was wrong)
- Wild Thrash M+: 3.58 CPM avg, 79% on CD rate, 100% of runs use it
- Wild Thrash Raid: Boss-dependent (0 on pure ST, 2.6 on AoE)
- BS before BW: Only 18-24% of BW casts had prior BS dump
