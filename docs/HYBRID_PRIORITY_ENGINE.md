# Hybrid Priority Engine

## Purpose

This document defines the target architecture for moving `TrueShot` from a
pure `PIN` / `PREFER` overlay model toward a hybrid decision pipeline:

1. hard gates
2. priority buckets
3. score / tiebreak selection inside an allowed bucket

The goal is not to replace class logic with opaque math. The goal is to make
the queue more stable and more guide-aligned when multiple legal filler
choices exist, while keeping critical windows explicit and explainable.

## Why Not Pure Spell Scores

The wrong model is:

- every spell gets one static value
- the addon always picks the highest currently available value

That model fails in WoW because spell value is not fixed. It changes with:

- short buff windows
- proc state
- anti-repeat mechanics
- cooldown alignment
- charge pressure / overcap risk
- target count
- next-GCD planning

Example: BM Pack Leader

- `Kill Command` is not always highest value
- `Barbed Shot` becomes more valuable when `Bestial Wrath` is about to come up
- `Cobra Shot` is normally filler, but is still better than idling
- `Kill Command` can be illegal or low-value immediately after another `Kill Command`

Therefore the target model is not "score everything". It is:

- explicit hard constraints first
- explicit priority windows second
- score only among legal candidates within the same decision class

## Decision Pipeline

This pipeline applies only when Strict Compliance is disabled. Every
experimental queue recompute should resolve in this order:

1. Build candidate set
2. Apply hard gates
3. Evaluate priority buckets
4. Pick the highest-score candidate within the winning bucket
5. Use Blizzard's readable current recommendation if no local bucket wins
6. Behind a valid primary, show rotation-catalog entries as context only

### 1. Candidate Set

Candidates may come from:

- Blizzard primary recommendation
- Blizzard rotation catalog (membership context, not ordered future actions)
- profile rotational spell list
- profile-declared local candidates

The initial implementation should stay conservative:

- keep Blizzard as the visible queue backbone
- let profiles nominate additional candidate spells only when justified

## Hard Gates

Hard gates answer: "may this spell be considered at all right now?"

Examples:

- spell not known
- spell not castable
- repeated `Kill Command` blocked by `Nature's Ally`
- utility spell blacklisted from the damage queue
- spell on a profile-local suppression window

Hard gates must remain:

- explainable
- deterministic
- legal under current API constraints

Hard gates are the right place for:

- `BLACKLIST`
- `BLACKLIST_CONDITIONAL`
- legality checks such as `castable`
- anti-repeat / anti-clip / anti-overwrite rules

## Priority Buckets

Buckets answer: "if this class of decision is active, what general family of
action outranks other families?"

Buckets are explicit and ordered. Example target ordering:

1. mandatory cooldown / unlock windows
2. proc exploitation windows
3. charge protection / overcap prevention
4. core rotational actions
5. filler actions
6. Blizzard fallback

Important: bucket order must stay human-readable. If a profile author cannot
tell why a bucket exists, the system is too opaque.

## Score / Tiebreak

Score is allowed only inside a bucket.

That means score should answer questions like:

- which filler is better right now?
- which charge spender is safer right now?
- which of two legal non-critical actions is the better bridge spell?

Score must not replace hard windows like:

- "cast `Bestial Wrath` now"
- "consume the post-BW `Stampede` KC"
- "do not cast `Kill Command` twice in a row"

### Score Inputs

Allowed inputs:

- observed cast recency
- event-tracked cooldown heuristics
- charge counts
- Blizzard proc glow
- Blizzard Assisted Combat suggestions
- coarse target count

Heuristic inputs:

- `resource()` while it remains only partially validated

Forbidden inputs:

- hidden aura state treated as exact
- hidden cooldown truth treated as exact
- hidden proc state treated as exact

## BM Pack Leader Pilot

The first pilot for the hybrid engine should be BM Pack Leader only.

Reason:

- it is the current failing profile
- the user is actively live-testing it
- the rotational structure is simple enough to pilot safely
- the spec exposes the exact kind of filler ambiguity the hybrid model should solve

### BM Hard Gates

Hard gates that should remain explicit:

- `Kill Command` anti-repeat (`Nature's Ally`)
- `Bestial Wrath` cooldown suppression
- post-`Bestial Wrath` Stampede KC availability
- castability / legality
- utility spell blacklist

### BM Buckets

Initial target buckets for the pilot:

1. `Bestial Wrath` / mandatory cooldown window
2. post-BW `Stampede` KC
3. proc or buffed `Kill Command`
4. charge-protection / setup `Barbed Shot`
5. filler (`Barbed Shot` vs `Cobra Shot`)
6. Blizzard fallback

### BM Tiebreaks

Expected early score signals:

- `Barbed Shot` charge pressure
- `Kill Command` castability
- recent cast suppression
- short setup window before `Bestial Wrath`
- Blizzard AC agreement as a small positive signal, not authority

## Data Trust Model

The hybrid engine must preserve the existing framework distinction:

- guaranteed state
- heuristic state
- display state

Score must never erase that distinction. If a score uses heuristic data, that
does not upgrade the result to "optimal". It remains a heuristic display choice.

## Debug Requirements

The system is only shippable if it explains itself.

For the chosen top spell, debug output should be able to show:

- candidate bucket
- winning reason
- relevant hard gates
- score components, if score was used

Example:

```text
Queue 1: Cobra Shot
Bucket: filler
Reason: KC blocked (anti-repeat), BS recent, BS charges=1 but recent suppress active
Score: filler_base=10, bs_recent_penalty=-20, cobra_ready_bonus=5
```

## Compatibility Constraints

The current ecosystem expects rules to be visible in:

- `RuleBuilder.lua`
- `ProfileIO.lua`
- custom profile schema

That means the hybrid migration must be incremental:

- do not delete current rule types first
- add new engine behavior behind backward-compatible profile fields
- only expose new public authoring forms once the engine semantics are stable

## Current Touch Points

The hybrid migration affects these files directly:

- `Engine.lua`
  - owns `EvalCondition`
  - owns `ComputeQueue`
  - owns `lastQueueMeta`
  - is the primary place for candidate assembly, hard gates, bucket evaluation,
    score/tiebreak selection, and fallback behavior

- `Profiles/BM_PackLeader.lua`
  - pilot profile
  - will be the first consumer of bucketed local decision logic
  - should keep critical windows explicit instead of burying them inside score math

- `Display.lua`
  - reads `Engine.lastQueueMeta`
  - will need richer metadata once buckets and score reasons exist

- `Core.lua`
  - drives queue recomputation and debug output paths
  - may need only metadata plumbing, not decision changes

- `CustomProfile.lua`
  - registers public condition schemas
  - wraps built-in profiles
  - must stay backward-compatible while new engine features are still private

- `RuleBuilder.lua`
  - currently understands rule types such as `PIN`, `PREFER`, and blacklist variants
  - should not expose bucket/score authoring until the pilot semantics are stable

- `ProfileIO.lua`
  - validates and serializes custom profile structures
  - any new public profile fields must be explicitly added to its allowlist and validator

- `tests/test_hunter_profiles.lua`
  - current best home for the BM Pack Leader pilot regressions
  - should gain bucket/score behavior tests before any live claim is made

- `tests/test_condition_registry.lua`
  - relevant if new public condition IDs are introduced
  - not needed if the first hybrid pilot stays engine-private

## Migration Boundary

The first hybrid pilot should remain engine-private:

- no new RuleBuilder authoring primitives
- no new public ProfileIO schema surface
- no custom profile serialization changes

That keeps the first two migration phases focused on runtime correctness rather
than editing UX.

## Validation Strategy

There is no honest "100% correctness" Lua skill or MCP guarantee in the current
environment. Reliability must come from layered verification:

1. `luac -p` syntax validation
2. deterministic logic tests
3. queue decision golden tests
4. replay-style regressions for known live bugs
5. in-game validation against `/ts debug`
6. stronger static analysis once a Lua analyzer is added locally

Current local environment:

- present: `lua`, `luac`
- missing: `luacheck`, `stylua`, `lua-language-server`

## Migration Rules

1. Do not switch the whole addon at once.
2. Keep Blizzard's current `GetNextCastSpell()` recommendation as the direct AC primary; never substitute the rotation catalog for it.
3. Migrate one profile first.
4. Add tests before widening profile coverage.
5. Keep profile logic explainable.
6. Prefer explicit buckets over large undocumented score formulas.

## Initial Recommendation

The recommended implementation order is:

1. add engine support for bucketed candidate evaluation
2. keep existing rules as hard gates
3. let a profile optionally declare bucket evaluators
4. pilot BM Pack Leader
5. add debug + tests
6. only then consider wider adoption
