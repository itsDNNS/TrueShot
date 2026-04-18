# Hunter Validation Matrix

This document is the release-readiness baseline for Hunter support in `TrueShot`.

Its purpose is simple:

- make the current Hunter promise explicit
- separate static confidence from live combat proof
- give each Hunter profile a repeatable checklist before `1.0`

**Last source review: 2026-04-18** against the primary sources listed in each spec's rotation reference. Patch: 12.0.4 (Midnight Season 1). Primary author: Azortharion (Icy Veins).

Use this together with:

- [Project Goals](PROJECT_GOALS.md)
- [API Constraints](API_CONSTRAINTS.md)
- [Signal Validation](SIGNAL_VALIDATION.md)
- [BM Rotation Reference](BM_ROTATION_REFERENCE.md)
- [MM Rotation Reference](MM_ROTATION_REFERENCE.md)
- [SV Rotation Reference](SV_ROTATION_REFERENCE.md)

## Readiness Model

Each Hunter profile should be judged on two axes:

1. **Static readiness**
   - code path is reviewed
   - rule logic matches the intended legal signal model
   - known unsafe API use is removed
   - profile-specific conditions / custom rules / import paths are structurally sound
2. **Live readiness**
   - profile loads in the client without Lua/runtime issues
   - key override cases trigger in real combat
   - fallback to Blizzard Assisted Combat remains sane when signals disappear or become uncertain

`1.0` should require both.

## Current Overall Status

Hunter is the primary shipping target and the quality bar for the addon.

Current honest status:

- **Static Hunter baseline:** strong
- **Live Hunter proof for 1.0:** incomplete

That means Hunter is currently the only class family that should be treated as productized support, but it is not yet fully proven to a `1.0` standard until the pending live checks are closed.

## Shared Hunter Baseline

These checks apply to all six Hunter profiles.

| Check | Status | Notes |
| --- | --- | --- |
| No cooldown-sensitive priority logic on raw `C_Spell.IsSpellUsable()` | PASS | Replaced with safer Assisted Combat suggestion gates where needed. |
| Shared engine conditions follow documented API constraints | PASS | `ac_suggested`, `spell_charges`, `target_count`, `target_casting` fit the current legal model. |
| Condition registry / custom profile schema isolation | PASS | Duplicate condition IDs across profiles no longer overwrite each other. |
| Import / export hardening for custom profile data | PASS | Invalid Base64 and schema conflicts are now rejected more cleanly. |
| Per-tick engine caches are robust under repeated combat evaluation | PASS | Float-time equality path was replaced by explicit compute-tick invalidation. |
| Live combat verification on current patch | PENDING | Required before a `1.0` claim. |

## Profile Matrix

### Beast Mastery

| Profile | Static | Live | Notes |
| --- | --- | --- | --- |
| `Hunter.BM.DarkRanger` | PASS | PENDING | Best-covered Hunter lane. Has an explicit rotation reference in `BM_ROTATION_REFERENCE.md`. |
| `Hunter.BM.PackLeader` | PASS | PENDING | Shares the BM reference baseline, but still needs live confirmation of current override timing on the shipped build. |

### Marksmanship

| Profile | Static | Live | Notes |
| --- | --- | --- | --- |
| `Hunter.MM.DarkRanger` | PASS | PENDING | Assisted Combat gating cleanup landed. Still needs real combat proof for Trueshot / Black Arrow timing windows. |
| `Hunter.MM.Sentinel` | PASS | PENDING | Static rule model is cleaner now, but live confirmation is still required for Trueshot / Volley / Chakram behavior. |

### Survival

| Profile | Static | Live | Notes |
| --- | --- | --- | --- |
| `Hunter.SV.PackLeader` | PASS | PENDING | Earlier `Kill Command` / shared-ID blacklist regression was fixed. Live confirmation still needed for Stampede / Flamefang timing. |
| `Hunter.SV.Sentinel` | PASS | PENDING | The shipped profile now uses the conservative `spell_charges >= 2` path for `Wildfire Bomb` instead of recharge-timing heuristics. |

## Blocking Live Checks For `1.0`

These are the minimum live checks still needed before Hunter can honestly be called `1.0`-ready.

### All Hunter Profiles

- Profile loads cleanly on login, `/reload`, and spec/profile switches
- No stuck icon / stale override / disappearing queue regression in routine combat
- If a profile-specific heuristic becomes uncertain, the queue falls back cleanly to Blizzard Assisted Combat

### BM Dark Ranger

- `Black Arrow` pins during the expected `Withering Fire` window
- `Wailing Arrow` sequencing behaves as intended near the tail of the burst window

### BM Pack Leader

- `Nature's Ally` / `Kill Command` weaving still behaves correctly in combat
- `Bestial Wrath` timing and debug output align with the shipped profile behavior
- **Stampede PIN**: first `Kill Command` after `Bestial Wrath` is surfaced as `reason = "Stampede"` in the queue; `stampedeAvailable` clears on that KC and re-arms on the next `Bestial Wrath` cast (shipped v0.24.0, sourced to Azortharion 2026-04-10).

### MM Dark Ranger

- `Trueshot` opener sequencing is correct in live combat
- `Black Arrow` priority behavior during burst windows matches expectation

### MM Sentinel

- `Trueshot` / `Volley` anti-overlap logic is correct in live play
- `Moonlight Chakram` filler timing does not stick or pre-empt stronger actions

### SV Pack Leader

- `Stampede` / `Kill Command` sequencing behaves correctly after the blacklist fix
- `Flamefang` timing still adds value without wrong priority spikes

### SV Sentinel

- `Wildfire Bomb` charge-cap spend behaves correctly in practice
- `Moonlight Chakram` / `Flamefang` timing behaves correctly

## Non-Hunter Isolation

Non-Hunter profiles (Demon Hunter, Druid, Mage - foundation/alpha) ship in the same addon and register themselves alongside Hunter profiles, but they cannot affect Hunter loading or runtime. The isolation is mechanical, not advisory:

1. `Engine:RegisterProfile(profile)` stores each profile under its own `specID` in `TrueShot.Profiles[specID]`.
2. `Engine:ActivateProfile(specID)` only considers `TrueShot.Profiles[specID]` for the current spec.
3. A Hunter on `253/254/255` therefore never sees Havoc (`577`), Feral (`103`), Fire (`63`), etc. as activation candidates.

Profile files contain no top-level API calls beyond registration, so a non-Hunter profile failing cannot break the load chain for Hunter profiles. `luac -p` is run on every profile in `Profiles/` as a static syntax gate before release.

If a non-Hunter profile ever needs to be shipped-but-disabled for a Hunter-only release, the surgical path is to remove its line from `TrueShot.toc` - not to edit the profile file.

## Release Rule

Until the pending live checks above are closed, the honest release posture is:

- Hunter is the primary, productized support lane
- Hunter is also the only class family being pushed toward `1.0`
- but `TrueShot` should still avoid claiming fully proven `1.0` Hunter support yet
