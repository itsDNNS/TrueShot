# API Constraints

This document is the source of truth for what `TrueShot` may and may not rely on under Retail `Midnight`.

See also:

- [Midnight Compliance Audit](MIDNIGHT_COMPLIANCE_AUDIT.md)

## Current PM Decision

`TrueShot` must default to an Assisted Combat presentation/training layer, not a Hekili/APL-style live solver.

The existing live heuristics are useful research and may remain as experimental, signal-gated behavior, but the shippable baseline must work without using hidden or reconstructed combat state to choose the next action.

Runtime enforcement starts in `SignalRegistry.lua`: strict mode defaults on, unknown signals fail closed, and unsafe engine conditions are blocked from driving rule decisions unless strict mode is explicitly disabled for experimental testing.

The core rule is simple:

- prefer Blizzard-provided recommendation surfaces
- prefer direct event evidence over inferred hidden state
- avoid pretending secret or unstable state is trustworthy

## Guiding Principle

`TrueShot` should only build presentation behavior on top of data that is either:

- directly readable
- observable through player-owned events
- or intentionally exposed through Blizzard's recommendation APIs

If a mechanic depends on combat state that cannot be read safely, the framework must:

- degrade gracefully
- mark the logic as heuristic
- or not implement that rule at all

For strict mode, "observable through player-owned events" is not enough by itself to change the primary recommendation. Cast-event state may explain a hint or phase label, but it must not become a hidden cooldown/buff solver unless that signal has passed a specific API/compliance review.

## Confirmed Usable Signals

These are currently safe enough to build baseline presentation behavior on:

### Blizzard recommendation APIs

- `C_AssistedCombat.IsAvailable()`
- `C_AssistedCombat.GetNextCastSpell()`
- `C_AssistedCombat.GetRotationSpells()`

Use:

- `GetNextCastSpell()` is the current Blizzard recommendation and the only
  Assisted Combat source that may fill Strict Slot 1.
- `GetRotationSpells()` is a rotation catalog. Its order is not a documented
  priority list, future queue, or sequence of predicted casts.
- Catalog entries may appear only as supporting context behind an existing
  valid primary; they must never be promoted into an empty Slot 1 in either
  Strict or Experimental mode, and never count as combat-trace `soft_match`.

### Spell ownership / availability checks

- `IsPlayerSpell(spellID)`
- selected `C_Spell` helpers where validated in practice

Use:

- legality gates
- display filtering
- profile activation checks

Strict-mode caveat:

- do not use spell ownership/availability helpers as a substitute for live cooldown, resource, aura, or castability truth.

### Player-owned cast events

- `UNIT_SPELLCAST_SUCCEEDED` for `player`

Use:

- cast-tracked state machines
- estimated cooldown heuristics
- proc-window modeling when the proc source is not directly readable but the enabling cast is

Strict-mode caveat:

- player cast events may be used for diagnostics, user-visible explanations, training cards, or experimental overrides.
- player cast events must not drive a shippable primary next-action solver by default.

### Target-side surface that may be usable experimentally

- `UnitCastingInfo("target")`
- `UnitChannelInfo("target")`
- hostile nameplate enumeration

Use:

- interrupt reminders
- coarse AoE switching

These must be treated as best-effort until validated per use case.

Strict-mode caveat:

- target cast state and nameplate count must not alter the primary action recommendation.

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
- strict-mode primary recommendation filtering

## Framework Rules

When implementing a profile rule:

1. If Blizzard already exposes the recommendation directly, prefer that.
2. If the rule needs cooldown truth, require an event-tracked heuristic or skip it.
3. If the rule needs exact hidden resource state, do not fake precision.
4. If the rule depends on target information, make it optional and degradable.
5. If a rule can only be implemented dishonestly, reject it.

## Approved Heuristic Patterns

These are acceptable only when their output is non-authoritative, display-only, or explicitly experimental:

- "Spell X was cast by the player, so start a local timer."
- "Spell Y unlocks Spell Z, so mark Z as available until consumed."
- "Assisted Combat's current primary equals Spell X, so an experimental rule may record that direct recommendation." Rotation-catalog membership alone is context, not readiness or future-cast evidence.
- "The target is casting, so interrupt can be surfaced."
- "Nameplate count is at least N, so prefer an AoE branch."
- "Spell X was cast, `GetSpellBaseCooldown` returns 30000ms (non-secret), and we observed cast success, so Spell X is on cooldown until `GetTime() + 30`." This is the `State/CDLedger` pattern. Live `GetSpellBaseCooldown` values are preferred (they reflect talent CDR), with hardcoded `spec.base_ms` as a fallback when the API returns 0, nil, or secret. Haste scaling is applied through `UnitSpellHaste("player")` only for spells explicitly flagged `haste_scaled`, and degrades cleanly to "no scaling" when the read is secret.
- "DurationObject and direct `C_Spell.GetSpellCooldown` reads are both unavailable for the action-button swipe, so render the swipe from the `CDLedger` cast-event snapshot as a tier-3 visual fallback." Used purely for the cooldown swipe animation when the preferred readers cannot render. This does not promote the local timer into rotation truth: strict-mode `cd_ready` / `cd_remaining` consumers still go through the same event-tracked seam with the heuristic caveats above. `SPELL_UPDATE_COOLDOWN` triggers `CDLedger:ReconcileFromCooldownAPI`, which only prunes entries when a non-secret API read authoritatively reports "not on cooldown" - secret responses leave the local timer (and its visual fallback) intact.

Strict-mode baseline:

- A readable, non-secret `GetNextCastSpell()` result drives Strict Slot 1 unchanged.
- If that result is nil, secret, errors, or is unavailable, Strict Slot 1 remains empty; the rotation catalog cannot fill it.
- `GetRotationSpells()` entries may be displayed only as supporting rotation context behind that valid primary.
- Experimental blacklisting or local castability gating may remove the raw primary and leave Slot 1 empty; catalog context does not replace it.
- Profile data may annotate, label, suppress duplicates, or show static hints.
- Local timer and charge heuristics must not independently replace AC position 1.

## Rejected Patterns

These are not acceptable:

- guessing exact cooldown remaining from hidden state
- pretending a secret resource value is known
- assuming a proc happened when the framework has no observable evidence
- describing heuristic output as optimal or exact
- marketing the addon as an optimal live Hekili replacement under Midnight
- using combat log, chat/addon comms, nameplates, resources, auras, target casts, or local cooldown ledgers to compute a strict-mode best next spell

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
