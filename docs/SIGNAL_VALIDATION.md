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
| pcall safe | yes | No errors |
| issecretvalue | no (not secret) | Returns full cast tuple with readable values |
| Value accuracy | accurate | Returns spell name, spell ID, start/end timestamps, cast GUID. Tested: Zungenschlag (350575), two consecutive casts correctly distinguished. |
| Instance behavior | untested | Open world validated; dungeon/raid TBD |
| **Classification** | **VALIDATED** | Non-secret in open world. Returns complete cast info including spell name, ID, timing, and interruptible flag. Instance behavior not yet confirmed. |

Engine condition: `target_casting` (Engine.lua)
Fallback if unavailable: condition returns false, interrupt hints do not fire.

### Nameplate Count

| Check | Result | Notes |
|-------|--------|-------|
| API | `C_NamePlate.GetNamePlates()` | |
| Namespace present | yes | `C_NamePlate` exists on live client |
| pcall safe | yes | No errors |
| Table issecretvalue | no (not secret) | Top-level table readable |
| Entry token issecretvalue | untested | Needs `/hf probe plates` with mobs |
| UnitCanAttack issecretvalue | untested | Needs `/hf probe plates` with mobs |
| Hostile filter accuracy | overcounts | Returns all visible nameplates, not just combat targets. Test: 5 plates visible, only ~2 in active combat. |
| CVar sensitivity | assumed yes | Count depends on nameplate visibility settings and render distance |
| Instance behavior | untested | Expected more accurate in dungeons (all visible = all pulled) |
| **Classification** | **PARTIAL** | API works and is not secret, but counts all visible hostile nameplates, not only mobs in combat range. Usable as best-effort AoE hint, not as hard rule dependency. |

Engine condition: `target_count` (Engine.lua)
Fallback if unavailable: condition returns false, AoE PREFER rules do not fire, single-target AC passthrough.

Note: A more precise filter could add `UnitAffectingCombat(unit)` per nameplate, but that call may be secret in instances. For now, treat nameplate count as a coarse heuristic that is more reliable in dungeon pulls than open world.

### Spell Charges

| Check | Result | Notes |
|-------|--------|-------|
| API | `C_Spell.GetSpellCharges(spellID)` | |
| Test spell | Barbed Shot (217200) | |
| pcall safe | yes | No errors |
| currentCharges secret | no (not secret) | Returned `2` |
| maxCharges secret | no (not secret) | Returned `2` |
| cooldownStartTime secret | untested | Needs charge consumption + re-probe |
| cooldownDuration secret | untested | Needs charge consumption + re-probe |
| Real-time update | untested | Needs charge consumption + re-probe |
| **Classification** | **VALIDATED** | Charge count (current/max) is non-secret and accurate. Recharge timing fields still need confirmation but are not required for charge-count rules. |

Engine condition: `spell_charges` (Engine.lua)
Fallback if unavailable: condition returns false, charge-based timing rules do not fire. Cast-event timer heuristic remains as backup.

Validated for: charge-count conditions (e.g. `spell_charges >= 2`). Recharge timing usability TBD.

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

- [x] Open world (solo, 0 targets) - plates: 0, charges: 2/2
- [x] Open world (5 visible nameplates, ~2 in combat) - plates: 5
- [x] Open world (caster mob, Zungenschlag 350575) - target_casting: full tuple returned, not secret
- [ ] Dungeon (trash pack) - deferred: expected more accurate plate count
- [ ] Dungeon (boss casting) - deferred: instance secret behavior TBD
- [ ] Different nameplate CVar settings - deferred: implementation note, not classification change
- [ ] Charge consumption test - deferred: recharge timing fields not needed for charge-count rules
