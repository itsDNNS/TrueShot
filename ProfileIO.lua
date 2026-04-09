-- TrueShot ProfileIO: import/export custom profiles as shareable strings
-- Zero external dependencies. Custom serializer + Base64 codec.

TrueShot = TrueShot or {}
TrueShot.ProfileIO = {}

local ProfileIO = TrueShot.ProfileIO
local CustomProfile = TrueShot.CustomProfile

local VERSION_HEADER = "!TS1!"

------------------------------------------------------------------------
-- Base64 Codec
------------------------------------------------------------------------

local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_ENCODE = {}
local B64_DECODE = {}

for i = 1, 64 do
    local c = B64_CHARS:sub(i, i)
    B64_ENCODE[i - 1] = c
    B64_DECODE[c:byte()] = i - 1
end

local function Base64Encode(data)
    local out = {}
    local len = #data
    for i = 1, len, 3 do
        local b1 = data:byte(i)
        local b2 = i + 1 <= len and data:byte(i + 1) or 0
        local b3 = i + 2 <= len and data:byte(i + 2) or 0

        out[#out + 1] = B64_ENCODE[math.floor(b1 / 4)]
        out[#out + 1] = B64_ENCODE[(b1 % 4) * 16 + math.floor(b2 / 16)]

        if i + 1 <= len then
            out[#out + 1] = B64_ENCODE[(b2 % 16) * 4 + math.floor(b3 / 64)]
        else
            out[#out + 1] = "="
        end

        if i + 2 <= len then
            out[#out + 1] = B64_ENCODE[b3 % 64]
        else
            out[#out + 1] = "="
        end
    end
    return table.concat(out)
end

local function Base64Decode(data)
    -- Strip whitespace and padding
    data = data:gsub("%s", ""):gsub("=+$", "")
    local out = {}
    local len = #data
    for i = 1, len, 4 do
        local c1 = B64_DECODE[data:byte(i)] or 0
        local c2 = i + 1 <= len and (B64_DECODE[data:byte(i + 1)] or 0) or 0
        local c3 = i + 2 <= len and (B64_DECODE[data:byte(i + 2)] or 0) or 0
        local c4 = i + 3 <= len and (B64_DECODE[data:byte(i + 3)] or 0) or 0

        out[#out + 1] = string.char(c1 * 4 + math.floor(c2 / 16))
        if i + 2 <= len then
            out[#out + 1] = string.char((c2 % 16) * 16 + math.floor(c3 / 4))
        end
        if i + 3 <= len then
            out[#out + 1] = string.char((c3 % 4) * 64 + c4)
        end
    end
    return table.concat(out)
end

------------------------------------------------------------------------
-- Serializer: Lua table -> string (known schema, BNF grammar)
------------------------------------------------------------------------

local function SerializeValue(val, depth)
    if depth > 20 then return "nil" end
    local vtype = type(val)

    if vtype == "nil" then
        return "nil"
    elseif vtype == "boolean" then
        return val and "true" or "false"
    elseif vtype == "number" then
        -- Reject non-finite numbers
        if val ~= val or val == math.huge or val == -math.huge then
            return "0"
        end
        -- Use integer format when possible
        if val == math.floor(val) and val >= -2147483648 and val <= 2147483647 then
            return string.format("%d", val)
        end
        return string.format("%.6g", val)
    elseif vtype == "string" then
        -- Escape special characters
        local escaped = val:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\t", "\\t")
        return '"' .. escaped .. '"'
    elseif vtype == "table" then
        local parts = {}
        local nextDepth = depth + 1

        -- Detect if this is an array (contiguous 1-based numeric keys)
        local isArray = true
        local maxKey = 0
        local count = 0
        for k in pairs(val) do
            count = count + 1
            if type(k) == "number" and k == math.floor(k) and k >= 1 then
                if k > maxKey then maxKey = k end
            else
                isArray = false
            end
        end
        if maxKey ~= count then isArray = false end

        if isArray and count > 0 then
            -- Serialize as array
            for i = 1, count do
                parts[#parts + 1] = SerializeValue(val[i], nextDepth)
            end
        else
            -- Serialize as dictionary (sorted keys for deterministic output)
            local keys = {}
            for k in pairs(val) do keys[#keys + 1] = k end
            table.sort(keys, function(a, b)
                if type(a) == type(b) then return tostring(a) < tostring(b) end
                return type(a) < type(b)
            end)
            for _, k in ipairs(keys) do
                local v = val[k]
                local keyStr
                if type(k) == "number" then
                    keyStr = "[" .. SerializeValue(k, nextDepth) .. "]"
                elseif type(k) == "string" and k:match("^[a-zA-Z_][a-zA-Z0-9_]*$") then
                    keyStr = k
                else
                    keyStr = "[" .. SerializeValue(tostring(k), nextDepth) .. "]"
                end
                parts[#parts + 1] = keyStr .. "=" .. SerializeValue(v, nextDepth)
            end
        end

        return "{" .. table.concat(parts, ",") .. "}"
    end

    return "nil"
end

------------------------------------------------------------------------
-- Deserializer: string -> Lua table (recursive descent parser)
------------------------------------------------------------------------

local function CreateParser(input)
    local pos = 1
    local len = #input
    local depth = 0
    local MAX_DEPTH = 20

    local function peek()
        return input:sub(pos, pos)
    end

    local function advance(n)
        pos = pos + (n or 1)
    end

    local function skipWhitespace()
        while pos <= len do
            local c = input:byte(pos)
            if c == 32 or c == 9 or c == 10 or c == 13 then -- space, tab, newline, cr
                pos = pos + 1
            else
                break
            end
        end
    end

    local function expect(char)
        skipWhitespace()
        if peek() ~= char then
            return nil, "Expected '" .. char .. "' at position " .. pos
        end
        advance()
        return true
    end

    local function parseString()
        skipWhitespace()
        if peek() ~= '"' then return nil, "Expected string at position " .. pos end
        advance() -- skip opening quote
        local parts = {}
        while pos <= len do
            local c = peek()
            if c == '"' then
                advance() -- skip closing quote
                return table.concat(parts)
            elseif c == '\\' then
                advance()
                local escaped = peek()
                if escaped == '\\' then parts[#parts + 1] = '\\'
                elseif escaped == '"' then parts[#parts + 1] = '"'
                elseif escaped == 'n' then parts[#parts + 1] = '\n'
                elseif escaped == 't' then parts[#parts + 1] = '\t'
                else parts[#parts + 1] = escaped
                end
                advance()
            else
                parts[#parts + 1] = c
                advance()
            end
        end
        return nil, "Unterminated string at position " .. pos
    end

    local function parseNumber()
        skipWhitespace()
        local startPos = pos
        if peek() == '-' then advance() end
        if pos > len or not input:sub(pos, pos):match("%d") then
            return nil, "Expected number at position " .. startPos
        end
        while pos <= len and input:sub(pos, pos):match("%d") do advance() end
        if pos <= len and peek() == '.' then
            advance()
            while pos <= len and input:sub(pos, pos):match("%d") do advance() end
        end
        local numStr = input:sub(startPos, pos - 1)
        local val = tonumber(numStr)
        if not val then return nil, "Invalid number at position " .. startPos end
        return val
    end

    -- Forward declare parseValue
    local parseValue

    local function parseTable()
        skipWhitespace()
        local ok, err = expect("{")
        if not ok then return nil, err end

        depth = depth + 1
        if depth > MAX_DEPTH then return nil, "Max nesting depth exceeded at position " .. pos end

        local result = {}
        local arrayIndex = 0
        skipWhitespace()

        if peek() == "}" then
            advance()
            depth = depth - 1
            return result
        end

        while true do
            skipWhitespace()
            local key = nil

            -- Check for explicit key: [number]= or identifier=
            local savedPos = pos
            if peek() == "[" then
                advance()
                local numKey, numErr = parseNumber()
                if numKey then
                    skipWhitespace()
                    if peek() == "]" then
                        advance()
                        skipWhitespace()
                        if peek() == "=" then
                            advance()
                            key = numKey
                        end
                    end
                end
                if not key then pos = savedPos end -- backtrack
            end

            if not key then
                -- Try identifier=
                local identStart = pos
                while pos <= len and input:sub(pos, pos):match("[a-zA-Z0-9_]") do advance() end
                if pos > identStart then
                    skipWhitespace()
                    if peek() == "=" then
                        key = input:sub(identStart, pos - 1)
                        advance() -- skip =
                    else
                        pos = identStart -- backtrack, treat as array value
                    end
                end
            end

            -- Parse value
            local val, valErr = parseValue()
            if val == nil and valErr then return nil, valErr end

            if key then
                result[key] = val
            else
                arrayIndex = arrayIndex + 1
                result[arrayIndex] = val
            end

            skipWhitespace()
            if peek() == "," then
                advance()
            elseif peek() == "}" then
                advance()
                depth = depth - 1
                return result
            else
                return nil, "Expected ',' or '}' at position " .. pos
            end
        end
    end

    parseValue = function()
        skipWhitespace()
        if pos > len then return nil, "Unexpected end of input" end

        local c = peek()

        if c == '{' then
            return parseTable()
        elseif c == '"' then
            return parseString()
        elseif c == '-' or (c >= '0' and c <= '9') then
            return parseNumber()
        elseif input:sub(pos, pos + 3) == "true" then
            advance(4)
            return true
        elseif input:sub(pos, pos + 4) == "false" then
            advance(5)
            return false
        elseif input:sub(pos, pos + 2) == "nil" then
            advance(3)
            return nil -- Note: this makes nil indistinguishable from error; callers check err
        else
            return nil, "Unexpected character '" .. c .. "' at position " .. pos
        end
    end

    return {
        parse = function()
            local result, err = parseValue()
            if err then return nil, err end
            skipWhitespace()
            if pos <= len then
                return nil, "Trailing data at position " .. pos
            end
            return result
        end
    }
end

------------------------------------------------------------------------
-- Public API: Serialize / Deserialize / Encode / Decode
------------------------------------------------------------------------

function ProfileIO.Serialize(tbl)
    return SerializeValue(tbl, 0)
end

function ProfileIO.Deserialize(str)
    local parser = CreateParser(str)
    return parser.parse()
end

function ProfileIO.Encode(profileData)
    local serialized = ProfileIO.Serialize(profileData)
    local encoded = Base64Encode(serialized)
    return VERSION_HEADER .. encoded
end

function ProfileIO.Decode(importString)
    -- Check version header
    if not importString or type(importString) ~= "string" then
        return nil, "Invalid input"
    end
    local version, payload = importString:match("^!TS(%d+)!(.+)$")
    if not version or not payload then
        return nil, "Invalid format: missing !TS1! header"
    end
    if version ~= "1" then
        return nil, "Unsupported version: TS" .. version
    end

    -- Base64 decode
    local decoded = Base64Decode(payload)
    if not decoded or decoded == "" then
        return nil, "Base64 decode failed"
    end

    -- Deserialize
    local data, err = ProfileIO.Deserialize(decoded)
    if not data then
        return nil, "Deserialize failed: " .. (err or "unknown error")
    end

    if type(data) ~= "table" then
        return nil, "Expected table, got " .. type(data)
    end

    -- Strip unknown top-level keys
    local ALLOWED_KEYS = {
        schemaVersion = true, profileId = true, specID = true,
        markerSpell = true, displayName = true, rules = true,
        stateVarDefs = true, triggers = true, rotationalSpells = true,
    }
    for k in pairs(data) do
        if not ALLOWED_KEYS[k] then
            data[k] = nil
        end
    end

    return data
end

------------------------------------------------------------------------
-- Validation
------------------------------------------------------------------------

local SCHEMA_VERSION = 1

local VALID_RULE_TYPES = {
    PIN = true, PREFER = true, BLACKLIST = true, BLACKLIST_CONDITIONAL = true,
}

local VALID_VAR_TYPES = {
    boolean = true, number = true, timestamp = true,
}

local RESERVED_CONDITION_NAMES = {
    ["and"] = true, ["or"] = true, ["not"] = true,
}

local ENGINE_CONDITION_IDS = {
    spell_glowing = true, target_count = true, spell_charges = true,
    usable = true, target_casting = true, in_combat = true,
    burst_mode = true, combat_opening = true,
}

-- Validate array: contiguous 1-based numeric keys, no mixed string keys
local function ValidateArray(tbl, fieldName)
    if type(tbl) ~= "table" then
        return false, fieldName .. " must be a table"
    end
    local maxKey = 0
    local count = 0
    for k in pairs(tbl) do
        count = count + 1
        if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then
            return false, fieldName .. " has non-integer key: " .. tostring(k)
        end
        if k > maxKey then maxKey = k end
    end
    if maxKey ~= count then
        return false, fieldName .. " has holes (max key " .. maxKey .. ", count " .. count .. ")"
    end
    return true
end

-- Validate a condition tree (recursive)
local function ValidateConditionTree(cond, depth, allowedConditions)
    if cond == nil then return true end
    if type(cond) ~= "table" then return false, "Condition must be a table" end
    if depth > 4 then return false, "Condition nesting too deep (max 4)" end

    local condType = cond.type
    if type(condType) ~= "string" or condType == "" then
        return false, "Condition missing type"
    end

    if condType == "and" or condType == "or" then
        local ok, err = ValidateConditionTree(cond.left, depth + 1, allowedConditions)
        if not ok then return false, err end
        return ValidateConditionTree(cond.right, depth + 1, allowedConditions)
    elseif condType == "not" then
        return ValidateConditionTree(cond.inner, depth + 1, allowedConditions)
    else
        -- Primitive: must be in allowed set
        if allowedConditions and not allowedConditions[condType] then
            return false, "Unknown condition type: " .. condType
        end
        -- Validate param types if present
        if cond.spellID ~= nil and type(cond.spellID) ~= "number" then
            return false, "Condition spellID must be a number"
        end
        if cond.op ~= nil and type(cond.op) ~= "string" then
            return false, "Condition op must be a string"
        end
        if cond.value ~= nil and type(cond.value) ~= "number" then
            return false, "Condition value must be a number"
        end
        if cond.duration ~= nil and type(cond.duration) ~= "number" then
            return false, "Condition duration must be a number"
        end
        if cond.seconds ~= nil and type(cond.seconds) ~= "number" then
            return false, "Condition seconds must be a number"
        end
        return true
    end
end

-- Build the allowed condition set for a given profile + imported state vars
local function BuildAllowedConditions(profileId, stateVarDefs)
    local allowed = {}
    -- Engine conditions
    for id in pairs(ENGINE_CONDITION_IDS) do
        allowed[id] = true
    end
    -- Base profile conditions (source == profileId only)
    local allSchemas = CustomProfile.GetAllConditionSchemas()
    for id, schema in pairs(allSchemas) do
        if schema.source == profileId then
            allowed[id] = true
        end
    end
    -- Imported state var names
    if stateVarDefs then
        for _, def in ipairs(stateVarDefs) do
            if def.name then allowed[def.name] = true end
        end
    end
    return allowed
end

-- Resolve the local base profile by profileId
local function ResolveBaseProfile(profileId)
    for specID, profiles in pairs(TrueShot.Profiles or {}) do
        for _, profile in ipairs(profiles) do
            if profile.id == profileId then
                return profile
            end
        end
    end
    return nil
end

-- Full validation pipeline
-- Returns: isValid (bool), errors (array of strings), warnings (array of strings)
function ProfileIO.Validate(data)
    local errors = {}
    local warnings = {}

    ------------------------------------------------------------------
    -- Phase 2: Schema Validation
    ------------------------------------------------------------------

    -- Required fields
    if type(data.schemaVersion) ~= "number" or data.schemaVersion < 1 then
        errors[#errors + 1] = "Missing or invalid schemaVersion"
    elseif data.schemaVersion > SCHEMA_VERSION then
        errors[#errors + 1] = "Schema version " .. data.schemaVersion .. " is newer than supported (v" .. SCHEMA_VERSION .. ")"
    end

    if type(data.profileId) ~= "string" or data.profileId == "" then
        errors[#errors + 1] = "Missing profileId"
    end

    if type(data.specID) ~= "number" or data.specID <= 0 then
        errors[#errors + 1] = "Missing or invalid specID"
    end

    if type(data.rules) ~= "table" then
        errors[#errors + 1] = "Missing rules table"
        return #errors == 0, errors, warnings
    end

    -- Array validation
    local arrayFields = { { data.rules, "rules" } }
    if data.stateVarDefs then
        arrayFields[#arrayFields + 1] = { data.stateVarDefs, "stateVarDefs" }
    end
    if data.triggers then
        arrayFields[#arrayFields + 1] = { data.triggers, "triggers" }
    end
    for _, pair in ipairs(arrayFields) do
        local ok, err = ValidateArray(pair[1], pair[2])
        if not ok then errors[#errors + 1] = err end
    end

    -- Validate rotationalSpells
    if data.rotationalSpells then
        if type(data.rotationalSpells) ~= "table" then
            errors[#errors + 1] = "rotationalSpells must be a table"
        else
            for k, v in pairs(data.rotationalSpells) do
                if type(k) ~= "number" or k <= 0 or k ~= math.floor(k) then
                    errors[#errors + 1] = "rotationalSpells has invalid key: " .. tostring(k)
                    break
                end
                if v ~= true then
                    errors[#errors + 1] = "rotationalSpells values must be true"
                    break
                end
            end
        end
    end

    -- Build allowed condition set (needs stateVarDefs for primitive validation)
    local allowedConditions = nil
    if data.profileId and type(data.profileId) == "string" then
        allowedConditions = BuildAllowedConditions(data.profileId, data.stateVarDefs)
    end

    -- Validate each rule
    for i, rule in ipairs(data.rules) do
        if type(rule) ~= "table" then
            errors[#errors + 1] = "Rule " .. i .. " is not a table"
        else
            if not rule.type or not VALID_RULE_TYPES[rule.type] then
                errors[#errors + 1] = "Rule " .. i .. ": invalid type '" .. tostring(rule.type) .. "'"
            end
            if type(rule.spellID) ~= "number" or rule.spellID <= 0 then
                errors[#errors + 1] = "Rule " .. i .. ": invalid spellID"
            end
            if rule.reason ~= nil and type(rule.reason) ~= "string" then
                errors[#errors + 1] = "Rule " .. i .. ": reason must be a string"
            end
            if rule.condition then
                local ok, err = ValidateConditionTree(rule.condition, 0, allowedConditions)
                if not ok then
                    errors[#errors + 1] = "Rule " .. i .. " condition: " .. err
                end
            end
        end
    end

    -- Validate stateVarDefs
    local varNames = {}
    if data.stateVarDefs then
        for i, def in ipairs(data.stateVarDefs) do
            if type(def) ~= "table" then
                errors[#errors + 1] = "stateVarDef " .. i .. " is not a table"
            else
                if type(def.name) ~= "string" or not def.name:match("^[a-zA-Z_][a-zA-Z0-9_]*$") then
                    errors[#errors + 1] = "stateVarDef " .. i .. ": invalid name '" .. tostring(def.name) .. "'"
                end
                if not VALID_VAR_TYPES[def.varType] then
                    errors[#errors + 1] = "stateVarDef " .. i .. ": invalid varType '" .. tostring(def.varType) .. "'"
                end
                -- Type-check default value
                if def.varType == "boolean" and type(def.default) ~= "boolean" then
                    errors[#errors + 1] = "stateVarDef " .. i .. ": default must be boolean"
                elseif (def.varType == "number" or def.varType == "timestamp") and type(def.default) ~= "number" then
                    errors[#errors + 1] = "stateVarDef " .. i .. ": default must be a number"
                end
                if def.name then varNames[def.name] = (varNames[def.name] or 0) + 1 end
            end
        end
    end

    -- Validate triggers
    if data.triggers then
        for i, trig in ipairs(data.triggers) do
            if type(trig) ~= "table" then
                errors[#errors + 1] = "Trigger " .. i .. " is not a table"
            else
                if type(trig.spellID) ~= "number" or trig.spellID <= 0 then
                    errors[#errors + 1] = "Trigger " .. i .. ": invalid spellID"
                end
                if type(trig.varName) ~= "string" or not varNames[trig.varName] then
                    errors[#errors + 1] = "Trigger " .. i .. ": varName '" .. tostring(trig.varName) .. "' not found in stateVarDefs"
                end
                if trig.guard then
                    local ok, err = ValidateConditionTree(trig.guard, 0, allowedConditions)
                    if not ok then
                        errors[#errors + 1] = "Trigger " .. i .. " guard: " .. err
                    end
                end
            end
        end
    end

    ------------------------------------------------------------------
    -- Phase 3: Semantic Validation
    ------------------------------------------------------------------

    -- State var name conflicts
    if data.stateVarDefs then
        for _, def in ipairs(data.stateVarDefs) do
            local name = def.name
            if name then
                if RESERVED_CONDITION_NAMES[name] then
                    errors[#errors + 1] = "State var '" .. name .. "' conflicts with reserved operator"
                end
                if ENGINE_CONDITION_IDS[name] then
                    errors[#errors + 1] = "State var '" .. name .. "' conflicts with engine condition"
                end
                -- Check base profile conditions (source == profileId only)
                if data.profileId then
                    local allSchemas = CustomProfile.GetAllConditionSchemas()
                    for id, schema in pairs(allSchemas) do
                        if schema.source == data.profileId and id == name then
                            errors[#errors + 1] = "State var '" .. name .. "' conflicts with profile condition"
                        end
                    end
                end
                if varNames[name] and varNames[name] > 1 then
                    errors[#errors + 1] = "Duplicate state var name: " .. name
                end
            end
        end
    end

    -- Profile resolution
    if data.profileId and type(data.profileId) == "string" then
        local baseProfile = ResolveBaseProfile(data.profileId)
        if not baseProfile then
            errors[#errors + 1] = "Profile '" .. data.profileId .. "' not available on this character"
        else
            if data.specID and baseProfile.specID ~= data.specID then
                errors[#errors + 1] = "specID mismatch: import has " .. data.specID .. ", local profile has " .. baseProfile.specID
            end
            if data.markerSpell and baseProfile.markerSpell and data.markerSpell ~= baseProfile.markerSpell then
                errors[#errors + 1] = "markerSpell mismatch"
            end
        end
    end

    ------------------------------------------------------------------
    -- Phase 4: Warnings
    ------------------------------------------------------------------

    -- SpellID availability
    if IsPlayerSpell then
        for _, rule in ipairs(data.rules) do
            if rule.spellID and not IsPlayerSpell(rule.spellID) then
                local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(rule.spellID) or rule.spellID
                warnings[#warnings + 1] = "Spell " .. tostring(name) .. " not known by this character"
                break -- one warning is enough
            end
        end
    end

    -- Different spec warning
    local currentSpecID = nil
    if GetSpecialization and GetSpecializationInfo then
        local specIndex = GetSpecialization()
        if specIndex then currentSpecID = GetSpecializationInfo(specIndex) end
    end
    if data.specID and currentSpecID and data.specID ~= currentSpecID then
        warnings[#warnings + 1] = "Profile targets a different spec (will activate when you switch)"
    end

    return #errors == 0, errors, warnings
end

-- Normalize imported data for storage
function ProfileIO.Normalize(data)
    local baseProfile = ResolveBaseProfile(data.profileId)
    if not baseProfile then return nil, "Profile not found" end

    local normalized = {
        schemaVersion = SCHEMA_VERSION,
        baseProfileId = data.profileId,
        baseProfileVersion = baseProfile.version or 0,
        rules = data.rules or {},
        stateVarDefs = data.stateVarDefs or {},
        triggers = data.triggers or {},
        rotationalSpells = data.rotationalSpells or {},
    }
    return normalized
end
