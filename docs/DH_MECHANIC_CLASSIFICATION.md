# Demon Hunter Mechanic Classification for TrueShot

Priority source: Icy Veins Midnight Season 1 guides (extracted 2026-04-03)

## Havoc (specID: 577)

Hero Paths: Aldrachi Reaver, Fel-Scarred

### Havoc Key Mechanics

| Mechanic | Signal | Class | Observable? | Keep? |
|---|---|---|---|---|
| Blade Dance / Death Sweep priority | C_AssistedCombat | direct | yes | yes (base AC) |
| Eye Beam / Abyssal Gaze windows | UNIT_SPELLCAST_SUCCEEDED | heuristic | player cast event | yes |
| Metamorphosis burst window | UNIT_SPELLCAST_SUCCEEDED | heuristic | player cast event + timer | yes |
| Demonsurge proc tracking | hidden buff state | impossible | no | no |
| Fury resource management | hidden (like Focus) | impossible | no | no |
| Essence Break timing in Meta | UNIT_SPELLCAST_SUCCEEDED | heuristic | player cast + Meta timer | yes |
| Immolation Aura charge management | C_Spell.GetSpellCharges | direct | yes | yes |
| Vengeful Retreat / Initiative / Exergy | UNIT_SPELLCAST_SUCCEEDED | heuristic | player cast event | partial |
| Inertia trigger (Felblade before Eye Beam) | UNIT_SPELLCAST_SUCCEEDED | heuristic | player cast sequence | yes |
| Reaver's Glaive (Aldrachi) | C_AssistedCombat + IsPlayerSpell | direct | hero path marker | yes |
| Reaver's Mark uptime | hidden debuff | impossible | no | no |
| The Hunt usage | C_AssistedCombat | direct | yes | yes (base AC) |
| AoE target switching | nameplate count | direct (partial) | best-effort | yes |
| Throw Glaive suppression (Screaming Brutality) | talent check | direct | IsPlayerSpell | yes |

### Havoc Profile Rules (Implementable)

**Aldrachi Reaver (markerSpell: Reaver's Glaive - need spell ID):**
- BLACKLIST: utility spells (Imprison, etc.)
- PIN: Eye Beam when Metamorphosis is active (heuristic: Meta cast event + 30s timer)
- PREFER: Essence Break during Metamorphosis window
- PREFER: Blade Dance (high priority filler)
- BLACKLIST_CONDITIONAL: Immolation Aura when at 0 charges (use charge API)

**Fel-Scarred (markerSpell: need spec-exclusive spell ID):**
- Similar to Aldrachi but with Demonsurge interactions (mostly handled by AC)
- PIN: Eye Beam when Meta window active
- PREFER: Essence Break during Meta
- BLACKLIST_CONDITIONAL: Throw Glaive (Screaming Brutality handles it)

### Havoc Limitations
- Fury is secret - cannot optimize spend/build decisions
- Demonsurge procs are hidden buffs - cannot track consumption
- Exact Metamorphosis duration/CD unknown - use cast-event timer only
- Inertia buff state is hidden - can only track the Vengeful Retreat cast

## Devourer (specID: TBD - new Midnight spec)

Hero Paths: Annihilator, Void-Scarred

### Devourer Key Mechanics

| Mechanic | Signal | Class | Observable? | Keep? |
|---|---|---|---|---|
| Void Metamorphosis window | UNIT_SPELLCAST_SUCCEEDED | heuristic | player cast + timer | yes |
| Reap on cooldown / Voidfall stacks | hidden buff stacks | impossible | no | no |
| Voidfall 3-stack threshold | hidden buff | impossible | no | no |
| Soul Fragment count (30 for Collapsing Star) | hidden resource | impossible | no | no |
| Collapsing Star timing | UNIT_SPELLCAST_SUCCEEDED | heuristic | cast event | partial |
| Fury management (100+ for Void Ray) | hidden resource | impossible | no | no |
| Pierce the Veil / Voidblade combo | UNIT_SPELLCAST_SUCCEEDED | heuristic | cast sequence | partial |
| Moment of Craving proc | hidden buff | impossible | no | no |
| Cull charge management | C_Spell.GetSpellCharges | direct | maybe | yes if works |
| Emptiness extension | hidden buff duration | impossible | no | no |
| AoE target switching | nameplate count | direct (partial) | best-effort | yes |

### Devourer Profile Rules (Implementable)

**The Devourer spec is heavily resource-dependent (Souls, Fury, Voidfall stacks). Most core rotation decisions depend on hidden state. TrueShot can only provide:**

- BLACKLIST: utility spells
- Void Metamorphosis window tracking (cast event + timer)
- AoE phase detection (nameplate count)
- Otherwise lean heavily on C_AssistedCombat baseline

### Devourer Limitations
- Souls are a hidden resource - cannot track 30-soul threshold for Collapsing Star
- Voidfall stacks are hidden buffs - cannot track 3-stack threshold for Reap/Cull
- Fury is hidden - cannot optimize Void Ray timing
- Moment of Craving is a hidden proc
- This spec will be much more AC-reliant than Havoc

## Spell IDs Needed

Must be validated in-game on the .46 machine:
- Havoc specID: 577
- Devourer specID: (new, needs lookup)
- Aldrachi Reaver marker spell (Reaver's Glaive): needs ID
- Fel-Scarred marker spell: needs ID
- Annihilator marker spell: needs ID
- Void-Scarred marker spell: needs ID
- Key Havoc spells: Eye Beam, Metamorphosis, Blade Dance, Death Sweep, Essence Break, Immolation Aura, Vengeful Retreat, The Hunt, Chaos Strike, Annihilation, Felblade, Fel Rush
- Key Devourer spells: Void Metamorphosis, Reap, Void Ray, Collapsing Star, Cull, Consume, Devour, Voidblade, Pierce the Veil
