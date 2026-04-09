-- TrueShot Profile: Arcane / Sunfury (Spec 62)
-- Arcane Surge + Touch of the Magi burst window tracking

local Engine = TrueShot.Engine

local SURGE_DURATION = 12
local TOUCH_DURATION = 10

local Profile = {
    id = "Mage.Arcane.Sunfury",
    displayName = "Arcane Sunfury",
    specID = 62,
    markerSpell = 1241462, -- Arcane Pulse (Sunfury exclusive, high M+ usage)
    version = 1,

    state = {
        surgeWindowUntil = 0,
        touchActiveUntil = 0,
    },

    rules = {
        { type = "BLACKLIST", spellID = 118 },     -- Polymorph
        { type = "BLACKLIST", spellID = 30449 },   -- Spellsteal
        { type = "BLACKLIST", spellID = 1459 },    -- Arcane Intellect

        -- Clearcasting: PREFER Arcane Missiles when proc is active (glow detection)
        {
            type = "PREFER",
            spellID = 5143, -- Arcane Missiles
            reason = "Clearcasting",
            condition = { type = "spell_glowing", spellID = 5143 },
        },
    },
}

function Profile:ResetState()
    self.state.surgeWindowUntil = 0
    self.state.touchActiveUntil = 0
end

function Profile:OnSpellCast(spellID)
    local now = GetTime()
    local s = self.state

    if spellID == 365350 then -- Arcane Surge
        s.surgeWindowUntil = now + SURGE_DURATION
    elseif spellID == 321507 then -- Touch of the Magi
        s.touchActiveUntil = now + TOUCH_DURATION
    end
end

function Profile:OnCombatEnd()
    self.state.surgeWindowUntil = 0
    self.state.touchActiveUntil = 0
end

function Profile:EvalCondition(cond)
    local s = self.state

    if cond.type == "in_surge" then
        return GetTime() < s.surgeWindowUntil
    elseif cond.type == "touch_active" then
        return GetTime() < s.touchActiveUntil
    end

    return nil
end

function Profile:GetDebugLines()
    local s = self.state
    local surgeRemaining = s.surgeWindowUntil - GetTime()
    local touchRemaining = s.touchActiveUntil - GetTime()
    return {
        "  Arcane Surge: " .. (surgeRemaining > 0
            and string.format("%.1fs remaining", surgeRemaining)
            or "inactive"),
        "  Touch of the Magi: " .. (touchRemaining > 0
            and string.format("%.1fs remaining", touchRemaining)
            or "inactive"),
    }
end

function Profile:GetPhase()
    if not UnitAffectingCombat("player") then return nil end
    local s = self.state
    if GetTime() < s.surgeWindowUntil then return "Burst" end
    if GetTime() < s.touchActiveUntil then return "Burst" end
    return nil
end

Engine:RegisterProfile(Profile)

if TrueShot.CustomProfile then
    TrueShot.CustomProfile.RegisterConditionSchema("Mage.Arcane.Sunfury", {
        { id = "in_surge",      label = "In Arcane Surge",       params = {} },
        { id = "touch_active",  label = "Touch of the Magi Active", params = {} },
    })
end
