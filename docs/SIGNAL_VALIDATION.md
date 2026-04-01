# Signal Validation

Tracks the validation status of shared hunter signal surfaces under Midnight.

Each signal is tested in-game using `/hf probe` and classified per the scheme below. Results here are the source of truth for whether Engine conditions or future profiles may depend on a signal.

## Classification Scheme

| Classification | Meaning | Engine Action |
|----------------|---------|---------------|
| **DIRECT** | Non-secret, accurate, stable across contexts | Safe as hard dependency in rules |
| **HEURISTIC** | Works but with caveats (e.g. CVar-dependent) | Use with documented assumptions |
| **IMPOSSIBLE** | Secret, errors, or missing API | Cannot use; fallback only |
| **UNKNOWN** | Not yet tested | Do not depend on |

## Signal Matrix

### Target Casting

| Check | Result | Notes |
|-------|--------|-------|
| API | `UnitCastingInfo("target")` / `UnitChannelInfo("target")` | |
| pcall safe | | |
| issecretvalue | | |
| Value accuracy | | Test while target is casting |
| Instance behavior | | Test in dungeon/raid |
| **Classification** | **UNKNOWN** | |

Engine condition: `target_casting` (Engine.lua)
Fallback if unavailable: condition returns false, interrupt hints do not fire.

### Nameplate Count

| Check | Result | Notes |
|-------|--------|-------|
| API | `C_NamePlate.GetNamePlates()` | |
| Namespace present | | `C_NamePlate` exists? |
| pcall safe | | |
| Table issecretvalue | | Top-level table |
| Entry token issecretvalue | | `plate.namePlateUnitToken` per entry |
| UnitCanAttack issecretvalue | | Per hostile unit |
| Hostile filter accuracy | | Pull 2+ mobs, verify count |
| CVar sensitivity | | Test with different nameplate settings |
| Instance behavior | | Test in dungeon/raid |
| **Classification** | **UNKNOWN** | |

Engine condition: `target_count` (Engine.lua)
Fallback if unavailable: condition returns false, AoE PREFER rules do not fire, single-target AC passthrough.

### Spell Charges

| Check | Result | Notes |
|-------|--------|-------|
| API | `C_Spell.GetSpellCharges(spellID)` | |
| Test spell | Barbed Shot (217200) | |
| pcall safe | | |
| currentCharges secret | | |
| maxCharges secret | | |
| cooldownStartTime secret | | Recharge timing may be restricted |
| cooldownDuration secret | | |
| Real-time update | | Consume charge, re-probe |
| **Classification** | **UNKNOWN** | |

Engine condition: `spell_charges` (Engine.lua)
Fallback if unavailable: condition returns false, charge-based timing rules do not fire. Cast-event timer heuristic remains as backup.

## Runtime Cost

| Signal | Call Pattern | Acceptable? |
|--------|-------------|-------------|
| UnitCastingInfo/UnitChannelInfo | Per queue update (0.1s) | Yes (single lookups) |
| GetNamePlates | Per queue update (0.1s) | Yes if table small (<20). Consider caching per frame. |
| GetSpellCharges | Per queue update per charge spell | Yes (single lookup) |

## Probe Commands

```
/hf probe target          -- test target casting APIs
/hf probe plates          -- test nameplate enumeration
/hf probe charges [id]    -- test spell charges (default: Barbed Shot 217200)
/hf probe all [id]        -- run all probes
/hf probe help            -- list probe commands
```

## Test Contexts

Record results from each context where tested:

- [ ] Open world (solo, 1 target)
- [ ] Open world (2+ hostile mobs)
- [ ] Dungeon (trash pack)
- [ ] Dungeon (boss - casting check)
- [ ] Different nameplate CVar settings
