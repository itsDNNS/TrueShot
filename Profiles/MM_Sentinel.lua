-- TrueShot Profile: Marksmanship / Sentinel (Spec 254)
-- Cast-event state machine for Trueshot window, Volley anti-overlap,
-- and Moonlight Chakram filler timing

local Engine = TrueShot.Engine

local TRUESHOT_DURATION = 19  -- Sentinel gets 19s (not 15s); timer is fallback only

-- Prefer aura check over timer (handles spell replacement + variable duration)
local function IsTrueshotBuffActive(state)
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, 288613)
        if ok then return aura ~= nil end
    end
    return GetTime() < state.trueshotUntil
end

------------------------------------------------------------------------
-- Spell IDs
------------------------------------------------------------------------

local SPELLS = {
    Trueshot         = 288613,
    RapidFire        = 257044,
    AimedShot        = 19434,
    Volley           = 260243,
    MoonlightChakram = 1264902,
    CounterShot      = 147362,
    CallPet1         = 883,
    RevivePet        = 982,
}

------------------------------------------------------------------------
-- Profile definition
------------------------------------------------------------------------

local Profile = {
    id = "Hunter.MM.Sentinel",
    displayName = "MM Sentinel",
    specID = 254,
    -- No markerSpell: this profile serves as the MM fallback
    -- when Dark Ranger's Black Arrow marker does not match
    version = 1,

    state = {
        lastRapidFireCast = 0,
        lastTrueshotCast = 0,
        trueshotUntil = 0,
        lastVolleyCast = 0,
    },

    rotationalSpells = {
        [288613]  = true, -- Trueshot
        [257044]  = true, -- Rapid Fire
        [260243]  = true, -- Volley
        [19434]   = true, -- Aimed Shot
        [1264902] = true, -- Moonlight Chakram
        [56641]   = true, -- Steady Shot
        [53351]   = true, -- Kill Shot
        [185358]  = true, -- Arcane Shot
    },

    rules = {
        -- Filter utility spells
        { type = "BLACKLIST", spellID = SPELLS.CallPet1 },
        { type = "BLACKLIST", spellID = SPELLS.RevivePet },
        { type = "BLACKLIST", spellID = SPELLS.CounterShot },

        -- Anti-overlap: never Trueshot right after Volley (Double Tap waste)
        {
            type = "BLACKLIST_CONDITIONAL",
            spellID = SPELLS.Trueshot,
            condition = { type = "volley_recent", seconds = 2 },
        },
        -- Anti-overlap: never Volley right after Trueshot
        {
            type = "BLACKLIST_CONDITIONAL",
            spellID = SPELLS.Volley,
            condition = { type = "trueshot_just_cast", seconds = 2 },
        },

        -- Trueshot: only after Rapid Fire and not after Volley
        {
            type = "PIN",
            spellID = SPELLS.Trueshot,
            reason = "Post-RF Window",
            condition = {
                type = "and",
                left  = { type = "trueshot_ready" },
                right = {
                    type = "and",
                    left  = { type = "rapid_fire_recent", seconds = 3 },
                    right = { type = "not", inner = { type = "volley_recent", seconds = 2 } },
                },
            },
        },

        -- Block Moonlight Chakram outside Trueshot window (AC may still recommend it)
        {
            type = "BLACKLIST_CONDITIONAL",
            spellID = SPELLS.MoonlightChakram,
            condition = { type = "not", inner = { type = "trueshot_active" } },
        },

        -- Moonlight Chakram: filler late in Trueshot when out of Aimed Shots
        {
            type = "PREFER",
            spellID = SPELLS.MoonlightChakram,
            reason = "Chakram",
            condition = {
                type = "and",
                left  = { type = "chakram_ready" },
                right = {
                    type = "and",
                    left  = { type = "trueshot_active" },
                    right = { type = "not", inner = { type = "aimed_shot_ready" } },
                },
            },
        },
    },
}

------------------------------------------------------------------------
-- State machine
------------------------------------------------------------------------

function Profile:ResetState()
    self.state.lastRapidFireCast = 0
    self.state.lastTrueshotCast = 0
    self.state.trueshotUntil = 0
    self.state.lastVolleyCast = 0
end

function Profile:OnSpellCast(spellID)
    local now = GetTime()
    local s = self.state

    if spellID == SPELLS.Trueshot then
        s.lastTrueshotCast = now
        s.trueshotUntil = now + TRUESHOT_DURATION

    elseif spellID == SPELLS.RapidFire then
        s.lastRapidFireCast = now

    elseif spellID == SPELLS.Volley then
        s.lastVolleyCast = now
    end
end

function Profile:OnCombatEnd()
    self.state.trueshotUntil = 0
end

------------------------------------------------------------------------
-- Profile-specific condition evaluation
------------------------------------------------------------------------

function Profile:EvalCondition(cond)
    local s = self.state
    local now = GetTime()

    if cond.type == "trueshot_ready" then
        if C_Spell and C_Spell.IsSpellUsable then
            local ok, usable = pcall(C_Spell.IsSpellUsable, SPELLS.Trueshot)
            if ok then return usable end
        end
        return false

    elseif cond.type == "trueshot_just_cast" then
        local threshold = cond.seconds or 2
        return s.lastTrueshotCast > 0 and (now - s.lastTrueshotCast) <= threshold

    elseif cond.type == "trueshot_active" then
        return IsTrueshotBuffActive(s)

    elseif cond.type == "rapid_fire_recent" then
        local threshold = cond.seconds or 3
        return s.lastRapidFireCast > 0 and (now - s.lastRapidFireCast) <= threshold

    elseif cond.type == "volley_recent" then
        local threshold = cond.seconds or 2
        return s.lastVolleyCast > 0 and (now - s.lastVolleyCast) <= threshold

    elseif cond.type == "chakram_ready" then
        if C_Spell and C_Spell.IsSpellUsable then
            local ok, usable = pcall(C_Spell.IsSpellUsable, SPELLS.MoonlightChakram)
            if ok then return usable end
        end
        return false

    elseif cond.type == "aimed_shot_ready" then
        if C_Spell and C_Spell.GetSpellCharges then
            local ok, info = pcall(C_Spell.GetSpellCharges, SPELLS.AimedShot)
            if ok and info and info.currentCharges then
                if issecretvalue and issecretvalue(info.currentCharges) then
                    return false
                end
                return info.currentCharges > 0
            end
        end
        return false
    end

    return nil
end

------------------------------------------------------------------------
-- Debug output
------------------------------------------------------------------------

function Profile:GetDebugLines()
    local s = self.state
    local now = GetTime()
    local buffActive = IsTrueshotBuffActive(s)
    local tsRemaining = s.trueshotUntil - now
    return {
        "  Trueshot: " .. (buffActive
            and (tsRemaining > 0 and string.format("active (%.1fs timer)", tsRemaining) or "active (buff)")
            or "inactive"),
        "  RF recent: " .. (s.lastRapidFireCast > 0
            and string.format("%.1fs ago", now - s.lastRapidFireCast)
            or "not cast"),
        "  Volley recent: " .. (s.lastVolleyCast > 0
            and string.format("%.1fs ago", now - s.lastVolleyCast)
            or "not cast"),
    }
end

------------------------------------------------------------------------
-- Phase detection
------------------------------------------------------------------------

function Profile:GetPhase()
    if not UnitAffectingCombat("player") then return nil end
    if IsTrueshotBuffActive(self.state) then return "Burst" end
    return nil
end

------------------------------------------------------------------------
-- Register
------------------------------------------------------------------------

Engine:RegisterProfile(Profile)

if TrueShot.CustomProfile then
    TrueShot.CustomProfile.RegisterConditionSchema("Hunter.MM.Sentinel", {
        { id = "trueshot_ready",    label = "Trueshot Ready",    params = {} },
        { id = "trueshot_just_cast", label = "Trueshot Just Cast",
          params = { { field = "seconds", fieldType = "number", default = 2, label = "Seconds window" } } },
        { id = "trueshot_active",   label = "Trueshot Active",   params = {} },
        { id = "rapid_fire_recent", label = "Rapid Fire Recent",
          params = { { field = "seconds", fieldType = "number", default = 3, label = "Seconds window" } } },
        { id = "volley_recent",     label = "Volley Recent",
          params = { { field = "seconds", fieldType = "number", default = 2, label = "Seconds window" } } },
        { id = "chakram_ready",     label = "Moonlight Chakram Ready", params = {} },
        { id = "aimed_shot_ready",  label = "Aimed Shot Ready",  params = {} },
    })
end
