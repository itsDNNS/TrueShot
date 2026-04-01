-- HunterFlow Engine: generic queue computation and condition evaluation
-- Profile-agnostic - delegates spec-specific conditions to the active profile

HunterFlow = HunterFlow or {}
HunterFlow.Engine = {}

local Engine = HunterFlow.Engine

Engine.burstModeActive = false
Engine.combatStartTime = nil
Engine.activeProfile = nil

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
            local casting = UnitCastingInfo("target")
            local channeling = UnitChannelInfo("target")
            return (casting ~= nil) or (channeling ~= nil)
        end
        return false

    elseif cond.type == "target_count" then
        local plates = C_NamePlate.GetNamePlates() or {}
        local count = 0
        for _, plate in ipairs(plates) do
            local unit = plate.namePlateUnitToken
            if unit and UnitExists(unit) and UnitCanAttack("player", unit) then
                count = count + 1
            end
        end
        if cond.op == ">=" then return count >= cond.value end
        if cond.op == ">" then return count > cond.value end
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

function Engine:ComputeQueue(iconCount)
    local queue = {}
    local profile = self.activeProfile
    if not profile then return queue end

    if not C_AssistedCombat or not C_AssistedCombat.IsAvailable() then
        return queue
    end

    local baseSpell = C_AssistedCombat.GetNextCastSpell()

    -- Build conditional blacklist for this frame
    local condBlacklist = {}
    for _, rule in ipairs(profile.rules) do
        if rule.type == "BLACKLIST_CONDITIONAL" and self:EvalCondition(rule.condition) then
            condBlacklist[rule.spellID] = true
        end
    end

    local function IsBlocked(spellID)
        return blacklistedSpells[spellID] or condBlacklist[spellID]
    end

    -- PIN rules (highest priority, first match wins)
    local pinnedSpell = nil
    for _, rule in ipairs(profile.rules) do
        if rule.type == "PIN" and self:EvalCondition(rule.condition) then
            if self:IsSpellCastable(rule.spellID) and not IsBlocked(rule.spellID) then
                pinnedSpell = rule.spellID
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
                    break
                end
            end
        end
    end

    -- Position 1
    if baseSpell and IsBlocked(baseSpell) then baseSpell = nil end
    local pos1 = pinnedSpell or preferredSpell or baseSpell
    if pos1 and not IsBlocked(pos1) then
        queue[#queue + 1] = pos1
    end

    -- Positions 2+ from GetRotationSpells()
    local rotSpells = C_AssistedCombat.GetRotationSpells()
    if rotSpells then
        local seen = {}
        if pos1 then seen[pos1] = true end

        for _, entry in ipairs(rotSpells) do
            if #queue >= iconCount then break end

            local spellID = entry
            if type(entry) == "table" then
                spellID = entry.spellID or entry[1]
            end

            if spellID
                and not seen[spellID]
                and not IsBlocked(spellID)
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

HunterFlow.Profiles = {}

function Engine:RegisterProfile(profile)
    HunterFlow.Profiles[profile.specID] = profile
end

function Engine:ActivateProfile(specID)
    local profile = HunterFlow.Profiles[specID]
    if profile then
        self.activeProfile = profile
        if profile.ResetState then profile:ResetState() end
        self:RebuildBlacklist()
        return true
    end
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
