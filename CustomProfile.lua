-- TrueShot CustomProfile: condition registry, profile forking, compiled wrappers
-- Zero Engine.lua changes -- wraps Engine:ActivateProfile at load time

TrueShot = TrueShot or {}
TrueShot.CustomProfile = {}

local CustomProfile = TrueShot.CustomProfile

local SCHEMA_VERSION = 1

------------------------------------------------------------------------
-- Condition Schema Registry
------------------------------------------------------------------------

local _conditionSchemas = {}

function CustomProfile.RegisterConditionSchema(source, schemas)
    for _, schema in ipairs(schemas) do
        _conditionSchemas[schema.id] = {
            id = schema.id,
            label = schema.label,
            params = schema.params or {},
            source = source,
        }
    end
end

function CustomProfile.GetConditionSchema(conditionId)
    return _conditionSchemas[conditionId]
end

function CustomProfile.GetAllConditionSchemas()
    return _conditionSchemas
end

function CustomProfile.GetConditionSchemasForProfile(profileId)
    local result = {}
    for id, schema in pairs(_conditionSchemas) do
        if schema.source == "_engine" or schema.source == profileId or schema.source == "_custom" then
            result[#result + 1] = schema
        end
    end
    table.sort(result, function(a, b) return a.label < b.label end)
    return result
end

------------------------------------------------------------------------
-- Register generic engine conditions at load time
------------------------------------------------------------------------

CustomProfile.RegisterConditionSchema("_engine", {
    { id = "spell_glowing",   label = "Spell Proc Active",
      params = { { field = "spellID", fieldType = "spell", label = "Spell" } } },
    { id = "target_count",    label = "Target Count",
      params = {
          { field = "op",    fieldType = "operator", choices = {">=", ">", "==", "<", "<="}, default = ">=" },
          { field = "value", fieldType = "number", default = 2, label = "Count" },
      }},
    { id = "spell_charges",   label = "Spell Charges",
      params = {
          { field = "spellID", fieldType = "spell", label = "Spell" },
          { field = "op",      fieldType = "operator", choices = {">=", ">", "==", "<", "<="}, default = ">=" },
          { field = "value",   fieldType = "number", default = 2, label = "Charges" },
      }},
    { id = "usable",          label = "Spell Usable",
      params = { { field = "spellID", fieldType = "spell", label = "Spell" } } },
    { id = "target_casting",  label = "Target Is Casting",     params = {} },
    { id = "in_combat",       label = "In Combat",             params = {} },
    { id = "burst_mode",      label = "Burst Mode Active",     params = {} },
    { id = "combat_opening",  label = "Combat Opening",
      params = { { field = "duration", fieldType = "number", default = 2, label = "Seconds" } } },
})

------------------------------------------------------------------------
-- Storage (SavedVariables)
------------------------------------------------------------------------

local function DeepCopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = DeepCopy(v)
    end
    return copy
end

function CustomProfile.GetCustomData(profileId)
    if not TrueShotDB.customProfiles then return nil end
    return TrueShotDB.customProfiles[profileId]
end

function CustomProfile.HasCustomData(profileId)
    return CustomProfile.GetCustomData(profileId) ~= nil
end

function CustomProfile.SaveCustomData(profileId, data)
    TrueShotDB.customProfiles = TrueShotDB.customProfiles or {}
    data.schemaVersion = SCHEMA_VERSION
    TrueShotDB.customProfiles[profileId] = data
end

function CustomProfile.DeleteCustomData(profileId)
    if TrueShotDB.customProfiles then
        TrueShotDB.customProfiles[profileId] = nil
    end
end

------------------------------------------------------------------------
-- Fork built-in profile into editable custom data
------------------------------------------------------------------------

function CustomProfile.ForkProfile(baseProfile)
    local data = {
        schemaVersion = SCHEMA_VERSION,
        baseProfileId = baseProfile.id,
        baseProfileVersion = baseProfile.version or 0,
        rules = DeepCopy(baseProfile.rules),
        stateVarDefs = {},
        triggers = {},
        rotationalSpells = DeepCopy(baseProfile.rotationalSpells or {}),
    }
    CustomProfile.SaveCustomData(baseProfile.id, data)
    return data
end

------------------------------------------------------------------------
-- Schema migration
------------------------------------------------------------------------

local MIGRATIONS = {}

function CustomProfile.MigrateIfNeeded(data)
    local version = data.schemaVersion or 0
    if version > SCHEMA_VERSION then
        return nil, "Custom profile uses schema v" .. version .. " (current: v" .. SCHEMA_VERSION .. "). Falling back to built-in."
    end
    while version < SCHEMA_VERSION do
        local migrator = MIGRATIONS[version]
        if migrator then
            data = migrator(data)
        end
        version = version + 1
        data.schemaVersion = version
    end
    return data, nil
end

------------------------------------------------------------------------
-- Compiled Profile Wrapper
------------------------------------------------------------------------

local _wrapperCache = {}
local _driftWarned = {}

local function BuildStateFromDefs(stateVarDefs)
    local state = {}
    for _, def in ipairs(stateVarDefs) do
        state[def.name] = def.default
    end
    return state
end

local function FindVarDef(stateVarDefs, varName)
    for _, def in ipairs(stateVarDefs) do
        if def.name == varName then return def end
    end
    return nil
end

function CustomProfile.Compile(baseProfile, customData)
    local profileId = baseProfile.id

    local wrapper = _wrapperCache[profileId]
    if not wrapper then
        wrapper = {}
        _wrapperCache[profileId] = wrapper
    end

    wrapper.id = baseProfile.id
    wrapper.displayName = baseProfile.displayName .. " (custom)"
    wrapper.specID = baseProfile.specID
    wrapper.markerSpell = baseProfile.markerSpell
    wrapper.version = baseProfile.version

    wrapper.rules = customData.rules or {}

    local merged = {}
    if baseProfile.rotationalSpells then
        for k, v in pairs(baseProfile.rotationalSpells) do merged[k] = v end
    end
    if customData.rotationalSpells then
        for k, v in pairs(customData.rotationalSpells) do merged[k] = v end
    end
    wrapper.rotationalSpells = merged

    wrapper.aoeHint = baseProfile.aoeHint

    local customDefs = customData.stateVarDefs or {}
    local customTriggers = customData.triggers or {}
    wrapper.state = BuildStateFromDefs(customDefs)

    wrapper._baseProfile = baseProfile
    wrapper._customData = customData
    wrapper._customDefs = customDefs
    wrapper._customTriggers = customTriggers

    function wrapper:ResetState()
        for _, def in ipairs(self._customDefs) do
            self.state[def.name] = def.default
        end
        for k in pairs(self.state) do
            if type(k) == "string" and k:sub(1, 1) == "_" then
                self.state[k] = nil
            end
        end
        if self._baseProfile.ResetState then
            self._baseProfile:ResetState()
        end
    end

    function wrapper:OnSpellCast(spellID)
        local now = GetTime()
        for _, trigger in ipairs(self._customTriggers) do
            if trigger.spellID == spellID then
                if trigger.guard then
                    local Engine = TrueShot.Engine
                    if not Engine:EvalCondition(trigger.guard) then
                        goto continue
                    end
                end
                local varName = trigger.varName
                if trigger.setNow then
                    self.state[varName] = now
                else
                    self.state[varName] = trigger.value
                end
                if trigger.resetAfter then
                    self.state["_resetTime_" .. varName] = now
                    self.state["_resetAfter_" .. varName] = trigger.resetAfter
                    self.state["_resetValue_" .. varName] = trigger.resetValue
                else
                    self.state["_resetTime_" .. varName] = nil
                    self.state["_resetAfter_" .. varName] = nil
                    self.state["_resetValue_" .. varName] = nil
                end
                ::continue::
            end
        end
        if self._baseProfile.OnSpellCast then
            self._baseProfile:OnSpellCast(spellID)
        end
    end

    function wrapper:OnCombatEnd()
        if self._baseProfile.OnCombatEnd then
            self._baseProfile:OnCombatEnd()
        end
    end

    function wrapper:EvalCondition(cond)
        if not cond then return true end

        local varName = cond.type
        local def = FindVarDef(self._customDefs, varName)
        if def then
            local resetTime = self.state["_resetTime_" .. varName]
            local resetAfter = self.state["_resetAfter_" .. varName]
            if resetTime and resetAfter then
                if (GetTime() - resetTime) >= resetAfter then
                    local resetValue = self.state["_resetValue_" .. varName]
                    if resetValue ~= nil then
                        self.state[varName] = resetValue
                    else
                        self.state[varName] = def.default
                    end
                    self.state["_resetTime_" .. varName] = nil
                    self.state["_resetAfter_" .. varName] = nil
                    self.state["_resetValue_" .. varName] = nil
                end
            end
            local val = self.state[varName]
            if def.varType == "boolean" then
                return val == true
            elseif def.varType == "timestamp" then
                return val and val > 0
            else
                return val ~= nil and val ~= 0
            end
        end

        if self._baseProfile.EvalCondition then
            local result = self._baseProfile:EvalCondition(cond)
            if result ~= nil then return result end
        end

        return nil
    end

    function wrapper:GetPhase()
        if self._baseProfile.GetPhase then
            return self._baseProfile:GetPhase()
        end
        return nil
    end

    function wrapper:GetDebugLines()
        local lines = {}
        for _, def in ipairs(self._customDefs) do
            lines[#lines + 1] = "  [custom] " .. def.label .. ": " .. tostring(self.state[def.name])
        end
        if self._baseProfile.GetDebugLines then
            for _, line in ipairs(self._baseProfile:GetDebugLines()) do
                lines[#lines + 1] = line
            end
        end
        return lines
    end

    return wrapper
end

------------------------------------------------------------------------
-- Activation Wrapping (zero Engine changes)
------------------------------------------------------------------------

local _originalActivateProfile = nil

function CustomProfile.WrapActivation()
    local Engine = TrueShot.Engine
    if _originalActivateProfile then return end

    _originalActivateProfile = Engine.ActivateProfile

    Engine.ActivateProfile = function(self, specID)
        local result = _originalActivateProfile(self, specID)

        local baseProfile = self.activeProfile
        if not baseProfile then return result end

        local customData = CustomProfile.GetCustomData(baseProfile.id)
        if not customData then
            _wrapperCache[baseProfile.id] = nil
            return result
        end

        local migrated, err = CustomProfile.MigrateIfNeeded(customData)
        if not migrated then
            if err and not _driftWarned["_migration_" .. baseProfile.id] then
                print("|cffffff00[TrueShot]|r " .. err)
                _driftWarned["_migration_" .. baseProfile.id] = true
            end
            return result
        end
        customData = migrated

        if baseProfile.version and customData.baseProfileVersion then
            if baseProfile.version ~= customData.baseProfileVersion then
                if not _driftWarned[baseProfile.id] then
                    print("|cffffff00[TrueShot]|r Built-in profile updated since customization. /ts rules to review.")
                    _driftWarned[baseProfile.id] = true
                end
            end
        end

        local compiled = CustomProfile.Compile(baseProfile, customData)

        local prev = self.activeProfile
        self.activeProfile = compiled
        if compiled ~= prev then
            compiled:ResetState()
        end
        self:RebuildBlacklist()

        return true
    end
end

function CustomProfile.RegisterCustomConditions(profileId, stateVarDefs)
    local schemas = {}
    for _, def in ipairs(stateVarDefs or {}) do
        schemas[#schemas + 1] = {
            id = def.name,
            label = def.label or def.name,
            params = {},
        }
    end
    if #schemas > 0 then
        CustomProfile.RegisterConditionSchema("_custom", schemas)
    end
end

function CustomProfile.InvalidateWrapper(profileId)
    _wrapperCache[profileId] = nil
end

-- Initialize: wrap activation on load
CustomProfile.WrapActivation()
