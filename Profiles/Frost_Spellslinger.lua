-- TrueShot Profile: Frost / Spellslinger (Spec 64)
-- Fallback profile -- not meta, minimal rules

local Engine = TrueShot.Engine

local Profile = {
    id = "Mage.Frost.Spellslinger",
    displayName = "Frost Spellslinger",
    specID = 64,
    markerSpell = 443722, -- Frost Splinter (Spellslinger exclusive)
    -- Inverted from Fire/Arcane pattern: Frostfire is the unmarked fallback
    -- because it covers 100% of top parses. This marker ensures Spellslinger
    -- only activates for the rare players who actually talent into it.
    version = 1,

    state = {},

    rules = {
        { type = "BLACKLIST", spellID = 118 },     -- Polymorph
        { type = "BLACKLIST", spellID = 30449 },   -- Spellsteal
        { type = "BLACKLIST", spellID = 1459 },    -- Arcane Intellect

        -- Brain Freeze: PREFER Flurry when proc is active (glow detection)
        {
            type = "PREFER",
            spellID = 44614, -- Flurry
            reason = "Brain Freeze",
            condition = { type = "spell_glowing", spellID = 44614 },
        },
    },
}

function Profile:ResetState() end
function Profile:OnSpellCast(_spellID) end
function Profile:OnCombatEnd() end
function Profile:EvalCondition(_cond) return nil end
function Profile:GetDebugLines() return { "  (Spellslinger: AC-reliant)" } end

function Profile:GetPhase()
    return nil
end

Engine:RegisterProfile(Profile)

if TrueShot.CustomProfile then
    TrueShot.CustomProfile.RegisterConditionSchema("Mage.Frost.Spellslinger", {
    })
end
