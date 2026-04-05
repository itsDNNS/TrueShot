-- TrueShot Profile: Beast Mastery / Pack Leader (Spec 253)
-- Simpler than Dark Ranger: BW management, Nature's Ally weaving

local Engine = TrueShot.Engine

local BW_COOLDOWN = 30
local WT_COOLDOWN = 8

------------------------------------------------------------------------
-- Profile definition
------------------------------------------------------------------------

local Profile = {
    id = "Hunter.BM.PackLeader",
    displayName = "BM Pack Leader",
    specID = 253,
    -- No markerSpell: this profile serves as the BM fallback
    -- when Dark Ranger's Black Arrow marker does not match

    state = {
        lastBWCast = 0,
        lastCastWasKC = false,
        lastWildThrashCast = 0,
    },

    rules = {
        -- Filter utility spells
        { type = "BLACKLIST", spellID = 883 },    -- Call Pet 1
        { type = "BLACKLIST", spellID = 982 },    -- Revive Pet
        { type = "BLACKLIST", spellID = 147362 }, -- Counter Shot (user preference)

        -- Wild Thrash: highest AoE priority at 2+ targets, only in combat (WCL: 79% on-CD in M+)
        {
            type = "PIN",
            spellID = 1264359, -- Wild Thrash
            reason = "AoE 2+",
            condition = {
                type = "and",
                left  = { type = "in_combat" },
                right = {
                    type = "and",
                    left  = { type = "target_count", op = ">=", value = 2 },
                    right = { type = "not", inner = { type = "wt_on_cd" } },
                },
            },
        },

        -- Bestial Wrath: suppress only when on CD (WCL data: top players press BW
        -- immediately, even with BS charges available -- 26-55% of BW casts had charges)
        {
            type = "BLACKLIST_CONDITIONAL",
            spellID = 19574,
            condition = { type = "bw_on_cd" },
        },

        -- Nature's Ally: never Kill Command twice in a row
        {
            type = "BLACKLIST_CONDITIONAL",
            spellID = 34026,
            condition = { type = "last_cast_was_kc" },
        },
    },
}

------------------------------------------------------------------------
-- State machine
------------------------------------------------------------------------

function Profile:ResetState()
    self.state.lastCastWasKC = false
    self.state.lastWildThrashCast = 0
end

function Profile:OnSpellCast(spellID)
    local s = self.state

    if spellID == 19574 then -- Bestial Wrath
        s.lastBWCast = GetTime()
        s.lastCastWasKC = false

    elseif spellID == 1264359 then -- Wild Thrash
        s.lastWildThrashCast = GetTime()
        s.lastCastWasKC = false

    elseif spellID == 34026 then -- Kill Command
        s.lastCastWasKC = true

    else
        s.lastCastWasKC = false
    end
end

function Profile:OnCombatEnd()
    self.state.lastCastWasKC = false
    self.state.lastWildThrashCast = 0
end

------------------------------------------------------------------------
-- Profile-specific condition evaluation
------------------------------------------------------------------------

function Profile:EvalCondition(cond)
    local s = self.state

    if cond.type == "last_cast_was_kc" then
        return s.lastCastWasKC

    elseif cond.type == "bw_on_cd" then
        if s.lastBWCast == 0 then return false end
        return (GetTime() - s.lastBWCast) < BW_COOLDOWN

    elseif cond.type == "wt_on_cd" then
        if s.lastWildThrashCast == 0 then return false end
        return (GetTime() - s.lastWildThrashCast) < WT_COOLDOWN

    end

    return nil -- not handled by this profile
end

------------------------------------------------------------------------
-- Debug output
------------------------------------------------------------------------

function Profile:GetDebugLines()
    local s = self.state
    local bwElapsed = s.lastBWCast > 0 and (GetTime() - s.lastBWCast) or 0
    return {
        "  BW CD: " .. (s.lastBWCast > 0
            and string.format("%.1fs elapsed (est ~%ds)", bwElapsed, 60)
            or "not cast yet"),
        "  Last cast was KC: " .. tostring(s.lastCastWasKC),
    }
end

------------------------------------------------------------------------
-- Phase detection (for overlay display)
------------------------------------------------------------------------

function Profile:GetPhase()
    if not UnitAffectingCombat("player") then return nil end
    local s = self.state
    if s.lastBWCast > 0 and (GetTime() - s.lastBWCast) < 15 then return "Burst" end
    return nil
end

------------------------------------------------------------------------
-- Register
------------------------------------------------------------------------

Engine:RegisterProfile(Profile)
