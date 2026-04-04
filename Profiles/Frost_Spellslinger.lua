-- TrueShot Profile: Frost / Spellslinger (Spec 64)
-- Fallback profile -- not meta, minimal rules

local Engine = TrueShot.Engine

local Profile = {
    id = "Mage.Frost.Spellslinger",
    displayName = "Frost Spellslinger",
    specID = 64,
    markerSpell = 443722, -- Frost Splinter (Spellslinger exclusive)

    state = {},

    rules = {
        { type = "BLACKLIST", spellID = 118 },     -- Polymorph
        { type = "BLACKLIST", spellID = 30449 },   -- Spellsteal
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
