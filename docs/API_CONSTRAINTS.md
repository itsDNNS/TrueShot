# API Constraints

This document is the source of truth for what `TrueShot` may and may not rely on under Retail `Midnight`.

The core rule is simple:

- prefer Blizzard-provided recommendation surfaces
- prefer direct event evidence over inferred hidden state
- avoid pretending secret or unstable state is trustworthy

## Guiding Principle

`TrueShot` should only build heuristics on top of data that is either:

- directly readable
- observable through player-owned events
- or intentionally exposed through Blizzard's recommendation APIs

If a mechanic depends on combat state that cannot be read safely, the framework must:

- degrade gracefully
- mark the logic as heuristic
- or not implement that rule at all

## Confirmed Usable Signals

These are currently safe enough to build framework behavior on:

### Blizzard recommendation APIs

- `C_AssistedCombat.IsAvailable()`
- `C_AssistedCombat.GetNextCastSpell()`
- `C_AssistedCombat.GetRotationSpells()`

Use:

- base queue
- lookahead queue
- fallback recommendation source

### Spell ownership / availability checks

- `IsPlayerSpell(spellID)`
- selected `C_Spell` helpers where validated in practice

Use:

- legality gates
- display filtering
- profile activation checks

### Player-owned cast events

- `UNIT_SPELLCAST_SUCCEEDED` for `player`

Use:

- cast-tracked state machines
- estimated cooldown heuristics
- proc-window modeling when the proc source is not directly readable but the enabling cast is

### Target-side surface that may be usable

- `UnitCastingInfo("target")`
- `UnitChannelInfo("target")`
- hostile nameplate enumeration

Use:

- interrupt reminders
- coarse AoE switching

These must be treated as best-effort until validated per use case.

## Confirmed Unsafe Or Incomplete Signals

These must not be treated as authoritative:

### Secret or effectively hidden combat state

- primary resource values such as `Focus` for BM Hunter
- cooldown remaining / precise cooldown duration
- aura state that Blizzard now protects
- old combat-log-driven simulation assumptions

### Misleading helpers

- `C_Spell.IsSpellUsable()` is **not** equivalent to "castable now"
- it can remain `true` while the spell is on cooldown

Allowed use:

- coarse "spell is generally available to the player"

Not allowed use:

- cooldown-sensitive priority decisions

## Framework Rules

When implementing a profile rule:

1. If Blizzard already exposes the recommendation directly, prefer that.
2. If the rule needs cooldown truth, require an event-tracked heuristic or skip it.
3. If the rule needs exact hidden resource state, do not fake precision.
4. If the rule depends on target information, make it optional and degradable.
5. If a rule can only be implemented dishonestly, reject it.

## Approved Heuristic Patterns

These are acceptable:

- "Spell X was cast by the player, so start a local timer."
- "Spell Y unlocks Spell Z, so mark Z as available until consumed."
- "Assisted Combat currently surfaces Spell X in its primary or rotation suggestions, so use that as a legal readiness gate for an override."
- "The target is casting, so interrupt can be surfaced."
- "Nameplate count is at least N, so prefer an AoE branch."
- "Spell X was cast, `GetSpellBaseCooldown` returns 30000ms (non-secret), and we observed cast success, so Spell X is on cooldown until `GetTime() + 30`." This is the `State/CDLedger` pattern. Live `GetSpellBaseCooldown` values are preferred (they reflect talent CDR), with hardcoded `spec.base_ms` as a fallback when the API returns 0, nil, or secret. Haste scaling is applied through `UnitSpellHaste("player")` only for spells explicitly flagged `haste_scaled`, and degrades cleanly to "no scaling" when the read is secret.

## Rejected Patterns

These are not acceptable:

- guessing exact cooldown remaining from hidden state
- pretending a secret resource value is known
- assuming a proc happened when the framework has no observable evidence
- describing heuristic output as optimal or exact

## Current Example

The current BM / Dark Ranger implementation uses:

- `C_AssistedCombat` as the base queue
- `UNIT_SPELLCAST_SUCCEEDED` for:
  - `Black Arrow`
  - `Bestial Wrath`
  - `Wailing Arrow`
- local state to model:
  - `Withering Fire` window
  - `Black Arrow` availability
  - `Wailing Arrow` availability
  - `Kill Command` anti-repeat weaving

That is the model future profiles should follow:

- observable signals first
- heuristics second
- hidden state never
