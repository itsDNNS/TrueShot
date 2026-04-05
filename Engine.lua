-- TrueShot Engine: generic queue computation and condition evaluation
-- Profile-agnostic - delegates spec-specific conditions to the active profile

TrueShot = TrueShot or {}
TrueShot.Engine = {}

local Engine = TrueShot.Engine

Engine.burstModeActive = false
Engine.combatStartTime = nil
Engine.activeProfile = nil
Engine.lastQueueMeta = { source = "ac", reason = nil }

local function IsSecret(val)
    return issecretvalue and issecretvalue(val) or false
end

-- Per-tick hostile nameplate cache (invalidated each ComputeQueue call)
local _hostileCount = 0
local _hostileCountTick = 0

local function GetHostileCount()
    local now = GetTime()
    if _hostileCountTick == now then return _hostileCount end
    _hostileCountTick = now
    if not C_NamePlate or not C_NamePlate.GetNamePlates then
        _hostileCount = 0
        return 0
    end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or not plates or IsSecret(plates) then
        _hostileCount = 0
        return 0
    end
    local count = 0
    for _, plate in ipairs(plates) do
        local unit = plate.namePlateUnitToken or plate.unitToken
        if unit and UnitExists(unit) and UnitCanAttack("player", unit) then
            count = count + 1
        end
    end
    _hostileCount = count
    return count
end

------------------------------------------------------------------------
-- Condition evaluator (generic conditions only)
------------------------------------------------------------------------

function Engine:EvalCondition(cond)
    if not cond then return true end

    if cond.type == "usable" then
        if C_Spell and C_Spell.IsSpellUsable then
            local ok, result = pcall(C_Spell.IsSpellUsable, cond.spellID)
            return ok and result == true
        end
        return false

    elseif cond.type == "target_casting" then
        if UnitExists("target") then
            local ok1, casting = pcall(UnitCastingInfo, "target")
            local ok2, channeling = pcall(UnitChannelInfo, "target")
            if not ok1 and not ok2 then return false end
            if IsSecret(casting) or IsSecret(channeling) then return false end
            return (ok1 and casting ~= nil) or (ok2 and channeling ~= nil)
        end
        return false

    elseif cond.type == "in_combat" then
        return UnitAffectingCombat("player")

    elseif cond.type == "target_count" then
        local count = GetHostileCount()
        if cond.op == ">=" then return count >= cond.value end
        if cond.op == ">" then return count > cond.value end
        return false

    elseif cond.type == "spell_charges" then
        if C_Spell and C_Spell.GetSpellCharges then
            local ok, info = pcall(C_Spell.GetSpellCharges, cond.spellID)
            if ok and info then
                local charges = info.currentCharges
                if IsSecret(charges) then return false end
                if cond.op == ">=" then return charges >= cond.value end
                if cond.op == ">"  then return charges >  cond.value end
                if cond.op == "==" then return charges == cond.value end
                if cond.op == "<"  then return charges <  cond.value end
                if cond.op == "<=" then return charges <= cond.value end
            end
        end
        return false

    elseif cond.type == "burst_mode" then
        return self.burstModeActive

    elseif cond.type == "combat_opening" then
        if not self.combatStartTime then return false end
        return (GetTime() - self.combatStartTime) <= (cond.duration or 2)

    elseif cond.type == "not" then
        return not self:EvalCondition(cond.inner)

    elseif cond.type == "and" then
        return self:EvalCondition(cond.left) and self:EvalCondition(cond.right)

    elseif cond.type == "or" then
        return self:EvalCondition(cond.left) or self:EvalCondition(cond.right)
    end

    -- Delegate to active profile for profile-specific conditions
    if self.activeProfile and self.activeProfile.EvalCondition then
        local result = self.activeProfile:EvalCondition(cond)
        if result ~= nil then return result end
    end

    return false
end

------------------------------------------------------------------------
-- Spell legality gate
------------------------------------------------------------------------

function Engine:IsSpellCastable(spellID)
    if not spellID then return false end
    local known = IsPlayerSpell(spellID)
    if not known then return false end
    if C_Spell and C_Spell.IsSpellUsable then
        local ok, result = pcall(C_Spell.IsSpellUsable, spellID)
        return ok and result == true
    end
    return false
end

------------------------------------------------------------------------
-- Queue computation
------------------------------------------------------------------------

local blacklistedSpells = {}

function Engine:RebuildBlacklist()
    wipe(blacklistedSpells)
    if not self.activeProfile then return end
    for _, rule in ipairs(self.activeProfile.rules) do
        if rule.type == "BLACKLIST" then
            blacklistedSpells[rule.spellID] = true
        end
    end
end

-- Reusable tables to reduce GC churn in OnUpdate
local _queue = {}
local _condBlacklist = {}
local _seen = {}
local _aoeCondition = { type = "target_count", op = ">=", value = 3 }
local SV_SPEC_ID = 255
local SV_HATCHET_TOSS_NAME = "Hatchet Toss"
local SV_MELEE_RANGE_CHECK_IDS = {
    186270, -- Raptor Strike
    259387, -- Mongoose Bite
}

local function IsBlocked(spellID)
    return blacklistedSpells[spellID] or _condBlacklist[spellID]
end

local function IsSpellName(spellID, expectedName)
    if not spellID or not expectedName or not C_Spell or not C_Spell.GetSpellName then
        return false
    end
    local ok, spellName = pcall(C_Spell.GetSpellName, spellID)
    return ok and spellName == expectedName
end

local function IsOutOfMeleeRange()
    if not UnitExists("target") or not UnitCanAttack("player", "target") then
        return false
    end
    if not C_Spell or not C_Spell.IsSpellInRange then return false end

    local hadReadableProbe = false
    for _, spellID in ipairs(SV_MELEE_RANGE_CHECK_IDS) do
        local ok, inRange = pcall(C_Spell.IsSpellInRange, spellID, "target")
        if ok and inRange ~= nil and not IsSecret(inRange) then
            hadReadableProbe = true
            if inRange == true then
                return false
            end
        end
    end

    return hadReadableProbe
end

function Engine:IsSuppressedBySpecRules(spellID)
    local profile = self.activeProfile
    if not profile or profile.specID ~= SV_SPEC_ID then return false end

    if IsSpellName(spellID, SV_HATCHET_TOSS_NAME) then
        return not IsOutOfMeleeRange()
    end

    return false
end

function Engine:ComputeQueue(iconCount)
    wipe(_queue)
    local queue = _queue
    local profile = self.activeProfile
    if not profile then
        self.lastQueueMeta.source = "ac"
        self.lastQueueMeta.reason = nil
        self.lastQueueMeta.phase = nil
        return queue
    end

    if not C_AssistedCombat or not C_AssistedCombat.IsAvailable() then
        self.lastQueueMeta.source = "ac"
        self.lastQueueMeta.reason = nil
        self.lastQueueMeta.phase = nil
        return queue
    end

    local baseSpell = C_AssistedCombat.GetNextCastSpell()

    -- Build conditional blacklist for this frame
    wipe(_condBlacklist)
    local condBlacklist = _condBlacklist
    for _, rule in ipairs(profile.rules) do
        if rule.type == "BLACKLIST_CONDITIONAL" and self:EvalCondition(rule.condition) then
            condBlacklist[rule.spellID] = true
        end
    end

    -- IsBlocked uses module-level tables (blacklistedSpells + _condBlacklist)

    -- PIN rules (highest priority, first match wins)
    local pinnedSpell = nil
    local firedRule = nil
    for _, rule in ipairs(profile.rules) do
        if rule.type == "PIN" and self:EvalCondition(rule.condition) then
            if self:IsSpellCastable(rule.spellID) and not IsBlocked(rule.spellID) then
                pinnedSpell = rule.spellID
                firedRule = rule
                break
            end
        end
    end

    -- PREFER rules (only if no PIN fired)
    local preferredSpell = nil
    if not pinnedSpell then
        for _, rule in ipairs(profile.rules) do
            if rule.type == "PREFER" and self:EvalCondition(rule.condition) then
                if self:IsSpellCastable(rule.spellID) and not IsBlocked(rule.spellID) then
                    preferredSpell = rule.spellID
                    firedRule = rule
                    break
                end
            end
        end
    end

    -- Position 1
    if baseSpell and IsBlocked(baseSpell) then baseSpell = nil end
    local pos1 = pinnedSpell or preferredSpell or baseSpell
    local queuedPos1 = nil
    if pos1 and not IsBlocked(pos1) and not self:IsSuppressedBySpecRules(pos1) then
        queue[#queue + 1] = pos1
        queuedPos1 = pos1
    end

    -- Store metadata for display features
    local source = "ac"
    local reason = nil
    if firedRule then
        source = firedRule.type == "PIN" and "pin" or "prefer"
        reason = firedRule.reason
    end

    -- Phase detection: profile-specific first, then engine-level AoE
    local phase = nil
    if profile.GetPhase then
        phase = profile:GetPhase()
    end
    if not phase then
        if self:EvalCondition(_aoeCondition) then phase = "AoE" end
    end

    self.lastQueueMeta.source = source
    self.lastQueueMeta.reason = reason
    self.lastQueueMeta.phase = phase

    -- Positions 2+ from GetRotationSpells()
    local rotSpells = C_AssistedCombat.GetRotationSpells()
    if rotSpells then
        wipe(_seen)
        local seen = _seen
        if queuedPos1 then seen[queuedPos1] = true end

        for _, entry in ipairs(rotSpells) do
            if #queue >= iconCount then break end

            local spellID = entry
            if type(entry) == "table" then
                spellID = entry.spellID or entry[1]
            end

            if spellID
                and not seen[spellID]
                and not IsBlocked(spellID)
                and not self:IsSuppressedBySpecRules(spellID)
                and self:IsSpellCastable(spellID)
            then
                queue[#queue + 1] = spellID
                seen[spellID] = true
            end
        end
    end

    return queue
end

------------------------------------------------------------------------
-- Profile management
------------------------------------------------------------------------

TrueShot.Profiles = {}

function Engine:RegisterProfile(profile)
    local specID = profile.specID
    if not TrueShot.Profiles[specID] then
        TrueShot.Profiles[specID] = {}
    end
    table.insert(TrueShot.Profiles[specID], profile)
end

function Engine:ActivateProfile(specID)
    local candidates = TrueShot.Profiles[specID]
    if not candidates or #candidates == 0 then
        self.activeProfile = nil
        return false
    end

    local prev = self.activeProfile

    -- Match by markerSpell (hero path detection via IsPlayerSpell)
    for _, profile in ipairs(candidates) do
        if profile.markerSpell and IsPlayerSpell(profile.markerSpell) then
            self.activeProfile = profile
            if profile ~= prev then
                if profile.ResetState then profile:ResetState() end
            end
            self:RebuildBlacklist()
            return true
        end
    end

    -- Fallback: first profile without a marker, or first profile overall
    for _, profile in ipairs(candidates) do
        if not profile.markerSpell then
            self.activeProfile = profile
            if profile ~= prev then
                if profile.ResetState then profile:ResetState() end
            end
            self:RebuildBlacklist()
            return true
        end
    end

    -- No marker matched and no markerless fallback: stay inactive
    self.activeProfile = nil
    return false
end

function Engine:OnSpellCast(spellID)
    if self.activeProfile and self.activeProfile.OnSpellCast then
        self.activeProfile:OnSpellCast(spellID)
    end
end

function Engine:OnCombatEnd()
    if self.activeProfile and self.activeProfile.OnCombatEnd then
        self.activeProfile:OnCombatEnd()
    end
end
