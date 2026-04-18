# Signal Validation

Tracks the validation status of shared hunter signal surfaces under Midnight.

Each signal is tested in-game using `/ts probe` and classified per the scheme below. Results here are the source of truth for whether Engine conditions or future profiles may depend on a signal.

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
| Entry token issecretvalue | untested | Needs `/ts probe plates` with mobs |
| UnitCanAttack issecretvalue | untested | Needs `/ts probe plates` with mobs |
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
| cooldownStartTime secret | untested | Needs charge consumption + re-probe if a future profile wants recharge timing. |
| cooldownDuration secret | untested | Needs charge consumption + re-probe if a future profile wants recharge timing. |
| Real-time update | untested | Needs charge consumption + re-probe if a future profile wants recharge timing. |
| **Classification** | **VALIDATED** | Charge count (current/max) is non-secret and accurate. Recharge timing fields still need confirmation but are not required for charge-count rules. |

Engine condition: `spell_charges` (Engine.lua)
Fallback if unavailable: condition returns false, charge-based timing rules do not fire. Cast-event timer heuristic remains as backup.

Validated for: charge-count conditions (e.g. `spell_charges >= 2`).

Current shipped implication:

- the addon may safely use charge-count rules today
- shipped Hunter profiles should not depend on recharge timing fields until those fields are validated separately

### Base Cooldown Lookup

| Check | Result | Notes |
|-------|--------|-------|
| API | `GetSpellBaseCooldown(spellID)` | Returns `cooldownMS, gcdMS`. |
| Midnight status | non-secret | warcraft.wiki.gg documents no restriction; same call path has existed since Patch 4.3.0 and is not listed under `C_Secrets`. |
| Talent interaction | reflects the player's talent CD modifiers (not just the raw spell) | Verified by cross-reading known CDR talents. |
| Returns 0 for | spells the player does not know or that have no inherent CD | Treat as "use spec fallback". |
| **Classification** | **DIRECT** (pending /ts probe confirmation on live 12.0.4 client) | Safe primary source for the CD-Ledger base value, with hardcoded fallback. |

State module: `State/CDLedger.lua`.

### Spell Haste (player)

| Check | Result | Notes |
|-------|--------|-------|
| API | `UnitSpellHaste("player")` | Returns the player's spell haste percent. |
| Midnight status | flagged `SecretArguments` on warcraft.wiki.gg | No explicit combat restriction documented for `player`, but the flag means a value could be secret depending on state. |
| pcall safe | yes | |
| **Classification** | **HEURISTIC** until live-probed | CDLedger guards each read with `pcall` + `issecretvalue`; when the read is secret, it degrades to "no haste scaling" rather than fake precision. |

State module: `State/CDLedger.lua` (only applies to spells flagged `haste_scaled` in the spec table; no shipped Hunter spell is currently haste-scaled in the ledger).

### Cooldown Read (Per-Spell)

| Check | Result | Notes |
|-------|--------|-------|
| API | `C_Spell.GetSpellCooldown(spellID)` returning `{ startTime, duration, isEnabled, modRate }` | |
| Midnight status | per-spell gated by `C_Secrets.ShouldSpellCooldownBeSecret` | No public Hunter whitelist. Skyriding, combat-res, Maelstrom Weapon and a handful of system spells are confirmed whitelisted elsewhere; Hunter spells are not. |
| **Classification** | **UNKNOWN / fragile** | Not used by `State/CDLedger` as a primary source. CDLedger is deliberately cast-event-driven to avoid coupling the shipped rule layer to secret-gate drift. |

Usage rule: if a future feature wants this read, it must probe-check per spell under `/ts probe cd` before depending on it.

## Runtime Cost

| Signal | Call Pattern | Acceptable? |
|--------|-------------|-------------|
| UnitCastingInfo/UnitChannelInfo | Per queue update (0.1s) | Yes (single lookups) |
| GetNamePlates | Per queue update (0.1s) | Yes if table small (<20). Consider caching per frame. |
| GetSpellCharges | Per queue update per charge spell | Yes (single lookup) |

## Probe Commands

```
/ts probe target          -- test target casting APIs
/ts probe plates          -- test nameplate enumeration
/ts probe charges [id]    -- test spell charges (default: Barbed Shot 217200)
/ts probe cd              -- test GetSpellBaseCooldown, UnitSpellHaste, C_Spell.GetSpellCooldown per tracked spell
/ts probe all [id]        -- run all probes
/ts probe help            -- list probe commands
```

## Test Contexts

Record results from each context where tested:

- [x] Open world (solo, 0 targets) - plates: 0, charges: 2/2
- [x] Open world (5 visible nameplates, ~2 in combat) - plates: 5
- [x] Open world (caster mob, Zungenschlag 350575) - target_casting: full tuple returned, not secret
- [ ] Dungeon (trash pack) - deferred: expected more accurate plate count
- [ ] Dungeon (boss casting) - deferred: instance secret behavior TBD
- [ ] Different nameplate CVar settings - deferred: implementation note, not classification change
- [ ] Charge consumption test - deferred: recharge timing fields remain out of scope for shipped charge-count rules
