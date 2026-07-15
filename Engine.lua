-- TrueShot Engine: generic queue computation and condition evaluation
-- Profile-agnostic - delegates spec-specific conditions to the active profile

TrueShot = TrueShot or {}
TrueShot.Engine = {}

local Engine = TrueShot.Engine
local IsStrictMode

Engine.burstModeActive = false
Engine.combatStartTime = nil
Engine.activeProfile = nil
Engine.lastQueueMeta = {
    source = "none",
    reason = nil,
    bucket = nil,
    score = nil,
    scoreBreakdown = nil,
    phase = nil,
    aoeHintSpell = nil,
    reasonCode = "NO_AC_PRIMARY",
    rawACSpell = nil,
    rawACStatus = "unavailable",
    finalPrimarySpell = nil,
    fallbackDropReason = "assisted_combat_unavailable",
    strictState = true,
    rotationCatalogSnapshot = {},
    rotationCatalogRole = "context_only",
}

function Engine:ResetQueueMeta()
    local meta = self.lastQueueMeta
    meta.source = "none"
    meta.reason = nil
    meta.bucket = nil
    meta.score = nil
    meta.scoreBreakdown = nil
    meta.phase = nil
    meta.aoeHintSpell = nil
    meta.reasonCode = "NO_AC_PRIMARY"
    meta.rawACSpell = nil
    meta.rawACStatus = "unavailable"
    meta.finalPrimarySpell = nil
    meta.fallbackDropReason = "assisted_combat_unavailable"
    meta.strictState = IsStrictMode() == true
    wipe(meta.rotationCatalogSnapshot)
    meta.rotationCatalogRole = "context_only"
end

local function IsSecret(val)
    return issecretvalue and issecretvalue(val) or false
end

IsStrictMode = function()
    return TrueShot.SignalRegistry and TrueShot.SignalRegistry:IsStrictMode()
end

local function IsConditionAllowed(cond)
    if not TrueShot.SignalRegistry then return true end
    return TrueShot.SignalRegistry:IsConditionAllowed(cond)
end

-- Per-tick caches: use a monotonic frame counter instead of GetTime() floats
-- to guarantee exactly one recompute per ComputeQueue call.
local _computeTick = 0

local _hostileCount = 0
local _hostileCountTick = -1

local function IsAttackableUnitToken(unit)
    if type(unit) ~= "string" or unit == "" or IsSecret(unit) then
        return false
    end

    local okExists, exists = pcall(UnitExists, unit)
    if not okExists or not exists or IsSecret(exists) then
        return false
    end

    local okAttack, canAttack = pcall(UnitCanAttack, "player", unit)
    if not okAttack or IsSecret(canAttack) then
        return false
    end

    return canAttack == true
end

local _hostileCountTime = 0

local function GetHostileCount()
    local now = GetTime()
    if _hostileCountTick == _computeTick and _hostileCountTime == now then
        return _hostileCount
    end
    _hostileCountTick = _computeTick
    _hostileCountTime = now
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
        if IsAttackableUnitToken(unit) then
            count = count + 1
        end
    end
    _hostileCount = count
    return count
end

------------------------------------------------------------------------
-- Spell overlay glow tracking (proc detection)
------------------------------------------------------------------------

local _glowingSpells = {}

local _glowFrame = CreateFrame("Frame")
_glowFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
_glowFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
_glowFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
_glowFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
_glowFrame:SetScript("OnEvent", function(_, event, spellID)
    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then
        -- Clear stale glow state on lifecycle boundaries (guards against missed GLOW_HIDE)
        wipe(_glowingSpells)
        return
    end
    if not spellID or IsSecret(spellID) then return end
    if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
        _glowingSpells[spellID] = true
    else
        _glowingSpells[spellID] = nil
    end
end)

function Engine:IsSpellGlowing(spellID)
    -- Always revalidate via poll (guards against stale cache)
    if C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed then
        local ok, result = pcall(C_SpellActivationOverlay.IsSpellOverlayed, spellID)
        if ok and not IsSecret(result) then
            _glowingSpells[spellID] = result == true or nil
            return result == true
        end
    end
    -- Fallback to cached event state if poll unavailable
    return _glowingSpells[spellID] == true
end

------------------------------------------------------------------------
-- Assisted Combat suggestion cache
------------------------------------------------------------------------

local _acSuggestionTick = -1
local _acPrimarySpell = nil
local _acSuggestedSpells = {}
local _acRotationCatalog = {}
local _acRawStatus = "unavailable"

local _acSuggestionTime = 0

local function GetCatalogSpellID(entry)
    if IsSecret(entry) then return nil end
    if type(entry) == "number" then return entry end
    if type(entry) ~= "table" then return nil end

    local spellID = entry.spellID
    if IsSecret(spellID) then return nil end
    if spellID == nil then
        spellID = entry[1]
        if IsSecret(spellID) then return nil end
    end
    if type(spellID) ~= "number" then return nil end
    return spellID
end

local function RefreshACSuggestions()
    local now = GetTime()
    if _acSuggestionTick == _computeTick and _acSuggestionTime == now then
        return
    end
    _acSuggestionTick = _computeTick
    _acSuggestionTime = now
    _acPrimarySpell = nil
    _acRawStatus = "unavailable"
    wipe(_acSuggestedSpells)
    wipe(_acRotationCatalog)

    if not C_AssistedCombat or not C_AssistedCombat.IsAvailable then
        return
    end

    local okAvailable, available = pcall(C_AssistedCombat.IsAvailable)
    if not okAvailable then
        _acRawStatus = "error"
        return
    end
    if IsSecret(available) then
        return
    end
    if available ~= true then
        return
    end
    if not C_AssistedCombat.GetNextCastSpell then
        return
    end

    local okPrimary, baseSpell = pcall(C_AssistedCombat.GetNextCastSpell)
    if not okPrimary then
        _acRawStatus = "error"
    elseif IsSecret(baseSpell) then
        _acRawStatus = "secret"
    elseif baseSpell == nil then
        _acRawStatus = "nil"
    elseif type(baseSpell) == "number" then
        _acRawStatus = "available"
        _acPrimarySpell = baseSpell
        _acSuggestedSpells[baseSpell] = true
    else
        _acRawStatus = "invalid"
    end

    if not C_AssistedCombat.GetRotationSpells then
        return
    end

    local okRotation, rotSpells = pcall(C_AssistedCombat.GetRotationSpells)
    if not okRotation or IsSecret(rotSpells) then return end
    if rotSpells == nil or type(rotSpells) ~= "table" then return end

    for _, entry in ipairs(rotSpells) do
        local spellID = GetCatalogSpellID(entry)
        if spellID then
            _acRotationCatalog[#_acRotationCatalog + 1] = spellID
            _acSuggestedSpells[spellID] = true
        end
    end
end

function Engine:IsSpellSuggestedByAC(spellID)
    if not spellID then return false end
    RefreshACSuggestions()
    return _acSuggestedSpells[spellID] == true
end

------------------------------------------------------------------------
-- Condition evaluator (generic conditions only)
------------------------------------------------------------------------

function Engine:EvalCondition(cond)
    if not cond then return true end
    if not IsConditionAllowed(cond) then return false end

    if cond.type == "usable" then
        if C_Spell and C_Spell.IsSpellUsable then
            local ok, result = pcall(C_Spell.IsSpellUsable, cond.spellID)
            return ok and result == true
        end
        return false

    elseif cond.type == "castable" then
        return self:IsSpellCastable(cond.spellID)

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

    elseif cond.type == "spell_glowing" then
        return self:IsSpellGlowing(cond.spellID)

    elseif cond.type == "ac_suggested" then
        return self:IsSpellSuggestedByAC(cond.spellID)

    elseif cond.type == "target_count" then
        local count = GetHostileCount()
        if cond.op == ">=" then return count >= cond.value end
        if cond.op == ">" then return count > cond.value end
        return false

    elseif cond.type == "resource" then
        local powerType = cond.powerType or 0
        local ok, current = pcall(UnitPower, "player", powerType)
        if ok and not IsSecret(current) then
            if cond.op == ">=" then return current >= cond.value end
            if cond.op == ">"  then return current >  cond.value end
            if cond.op == "==" then return current == cond.value end
            if cond.op == "<"  then return current <  cond.value end
            if cond.op == "<=" then return current <= cond.value end
        end
        return false

    elseif cond.type == "spell_charges" then
        if C_Spell and C_Spell.GetSpellCharges then
            local ok, info = pcall(C_Spell.GetSpellCharges, cond.spellID)
            if ok and not IsSecret(info) and info ~= nil and type(info) == "table" then
                local charges = info.currentCharges
                if IsSecret(charges) then return false end
                if type(charges) ~= "number" then return false end
                if cond.op == ">=" then return charges >= cond.value end
                if cond.op == ">"  then return charges >  cond.value end
                if cond.op == "==" then return charges == cond.value end
                if cond.op == "<"  then return charges <  cond.value end
                if cond.op == "<=" then return charges <= cond.value end
            end
        end
        return false

    elseif cond.type == "cd_ready" then
        if TrueShot.CDLedger then
            return TrueShot.CDLedger:IsOnCooldown(cond.spellID) == false
        end
        return false

    elseif cond.type == "cd_remaining" then
        if not TrueShot.CDLedger then return false end
        local remaining = TrueShot.CDLedger:SecondsUntilReady(cond.spellID)
        if cond.op == ">=" then return remaining >= cond.value end
        if cond.op == ">"  then return remaining >  cond.value end
        if cond.op == "==" then return remaining == cond.value end
        if cond.op == "<"  then return remaining <  cond.value end
        if cond.op == "<=" then return remaining <= cond.value end
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
    if IsStrictMode() then return true end

    -- Charge-bearing spells are directly readable enough for shipped use.
    -- If at least one charge is available, treat the spell as castable even
    -- while recharge timing is ticking in the background.
    if C_Spell and C_Spell.GetSpellCharges then
        local okCharges, info = pcall(C_Spell.GetSpellCharges, spellID)
        if okCharges and not IsSecret(info) and info ~= nil then
            local charges = info.currentCharges
            if not IsSecret(charges) and type(charges) == "number" then
                if charges <= 0 then
                    return false
                end
                return true
            end
        end
    end

    -- Non-charge spells: if cooldown data is readable and shows an active CD,
    -- the spell is not castable now. This avoids stale AC primaries such as
    -- Kill Command sitting in slot 1 while still cooling down.
    if C_Spell and C_Spell.GetSpellCooldown then
        local okCd, cooldown = pcall(C_Spell.GetSpellCooldown, spellID)
        if okCd and not IsSecret(cooldown) and type(cooldown) == "table" then
            local startTime = cooldown.startTime
            local duration = cooldown.duration
            local modRate = cooldown.modRate
            if not IsSecret(startTime) and not IsSecret(duration) and not IsSecret(modRate) then
                if startTime == nil then startTime = 0 end
                if duration == nil then duration = 0 end
                if modRate == nil then modRate = 1 end
                if type(startTime) == "number" and type(duration) == "number" and type(modRate) == "number"
                    and startTime > 0 and duration > 0 and modRate > 0 then
                    if (startTime + duration) > GetTime() then
                        return false
                    end
                end
            end
        end
    end

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

function Engine:InvalidatePerTickCaches()
    _computeTick = _computeTick + 1
end

-- Reusable tables to reduce GC churn in OnUpdate
local _queue = {}
local _condBlacklist = {}
local _seen = {}
local _hybridCandidates = {}
local _aoeCondition = { type = "target_count", op = ">=", value = 3 }

local DECISION_HISTORY_SIZE = 40
local _decisionHistory = {}
local _decisionHistoryHead = 0
local _decisionHistoryCount = 0
local _lastDecisionSignature = nil

local function CopySafeSpellArray(destination, source)
    wipe(destination)
    for _, spellID in ipairs(source or {}) do
        if not IsSecret(spellID) and type(spellID) == "number" then
            destination[#destination + 1] = spellID
        end
    end
end

local function DiagnosticsEnabled()
    return TrueShot.DiagnosticsEnabled and TrueShot.DiagnosticsEnabled() == true
end

function Engine:ClearDecisionHistory()
    wipe(_decisionHistory)
    _decisionHistoryHead = 0
    _decisionHistoryCount = 0
    _lastDecisionSignature = nil
end

function Engine:GetDecisionHistoryCount()
    return _decisionHistoryCount
end

function Engine:GetRecentDecisions(count)
    local result = {}
    count = math.min(count or _decisionHistoryCount, _decisionHistoryCount)
    for offset = count - 1, 0, -1 do
        local index = ((_decisionHistoryHead - offset - 1) % DECISION_HISTORY_SIZE) + 1
        result[#result + 1] = _decisionHistory[index]
    end
    return result
end

local function BuildDecisionSignature(meta)
    local catalog = table.concat(meta.rotationCatalogSnapshot, ",")
    return table.concat({
        meta.rawACStatus or "",
        meta.rawACSpell or 0,
        meta.finalPrimarySpell or 0,
        meta.source or "",
        meta.reasonCode or "",
        meta.fallbackDropReason or "",
        meta.strictState and 1 or 0,
        catalog,
    }, "|")
end

local function CopyDisplaySnapshot()
    local display = TrueShot.Display
    if not display or not display.GetStabilizationSnapshot then return nil end
    local snapshot = display:GetStabilizationSnapshot()
    if IsSecret(snapshot) or type(snapshot) ~= "table" then return nil end

    local copy = {}
    for _, key in ipairs({ "displayedPrimary", "pendingPrimary", "pendingTicks", "pendingAge" }) do
        local value = snapshot[key]
        if not IsSecret(value) and (value == nil or type(value) == "number") then
            copy[key] = value
        end
    end
    local forced = snapshot.staleDeadlineForcedLastCommit
    if not IsSecret(forced) then
        copy.staleDeadlineForcedLastCommit = forced == true
    end
    return copy
end

function Engine:RecordDecisionChange()
    if not DiagnosticsEnabled() then
        if _decisionHistoryCount > 0 then self:ClearDecisionHistory() end
        return
    end

    local meta = self.lastQueueMeta
    local signature = BuildDecisionSignature(meta)
    if signature == _lastDecisionSignature then return end
    _lastDecisionSignature = signature

    _decisionHistoryHead = (_decisionHistoryHead % DECISION_HISTORY_SIZE) + 1
    if _decisionHistoryCount < DECISION_HISTORY_SIZE then
        _decisionHistoryCount = _decisionHistoryCount + 1
    end

    local entry = {
        timestamp = GetTime(),
        rawStatus = meta.rawACStatus,
        rawACSpell = meta.rawACSpell,
        finalPrimarySpell = meta.finalPrimarySpell,
        source = meta.source,
        reason = IsSecret(meta.reason) and nil or meta.reason,
        reasonCode = meta.reasonCode,
        fallbackDropReason = meta.fallbackDropReason,
        strictState = meta.strictState == true,
        rotationCatalog = {},
        displayStabilization = CopyDisplaySnapshot(),
    }
    CopySafeSpellArray(entry.rotationCatalog, meta.rotationCatalogSnapshot)
    _decisionHistory[_decisionHistoryHead] = entry
end

local function IsBlocked(spellID)
    return blacklistedSpells[spellID] or _condBlacklist[spellID]
end

local function AddCandidate(candidates, seen, spellID)
    if type(spellID) ~= "number" or IsSecret(spellID) or seen[spellID] then
        return
    end
    candidates[#candidates + 1] = spellID
    seen[spellID] = true
end

function Engine:CollectHybridCandidates(profile, baseSpell, rotSpells)
    if not profile or not profile.hybrid or profile.hybrid.enabled ~= true then
        return nil
    end

    wipe(_hybridCandidates)
    wipe(_seen)
    local candidates = _hybridCandidates
    local seen = _seen

    AddCandidate(candidates, seen, baseSpell)

    if rotSpells then
        for _, entry in ipairs(rotSpells) do
            local spellID = entry
            if type(entry) == "table" then
                spellID = entry.spellID or entry[1]
            end
            AddCandidate(candidates, seen, spellID)
        end
    end

    if profile.rotationalSpells then
        for spellID in pairs(profile.rotationalSpells) do
            AddCandidate(candidates, seen, spellID)
        end
    end

    if profile.GetHybridCandidates then
        local extra = profile:GetHybridCandidates({
            baseSpell = baseSpell,
            rotationSpells = rotSpells,
            candidates = candidates,
        })
        if type(extra) == "table" then
            for _, spellID in ipairs(extra) do
                AddCandidate(candidates, seen, spellID)
            end
        end
    end

    return candidates
end

function Engine:SelectHybridDecision(profile, baseSpell, rotSpells)
    if IsStrictMode() then
        return nil
    end
    if not profile or not profile.hybrid or profile.hybrid.enabled ~= true then
        return nil
    end
    if not profile.hybrid.bucketOrder or not profile.GetHybridBucket then
        return nil
    end

    local candidates = self:CollectHybridCandidates(profile, baseSpell, rotSpells)
    if not candidates or #candidates == 0 then
        return nil
    end

    local bucketRanks = {}
    for i, bucketName in ipairs(profile.hybrid.bucketOrder) do
        bucketRanks[bucketName] = i
    end

    local context = {
        baseSpell = baseSpell,
        rotationSpells = rotSpells,
        candidates = candidates,
    }

    local best = nil
    local bestBucketRank = math.huge
    local bestScore = -math.huge

    for _, spellID in ipairs(candidates) do
        if not IsBlocked(spellID) and self:IsSpellCastable(spellID) then
            local bucketName = profile:GetHybridBucket(spellID, context)
            local bucketRank = bucketRanks[bucketName]
            if bucketRank then
                local score, reason, breakdown = 0, nil, nil
                if profile.GetHybridScore then
                    score, reason, breakdown = profile:GetHybridScore(spellID, bucketName, context)
                    if type(score) ~= "number" then
                        score = 0
                    end
                end

                local beatsCurrent = false
                if bucketRank < bestBucketRank then
                    beatsCurrent = true
                elseif bucketRank == bestBucketRank then
                    if score > bestScore then
                        beatsCurrent = true
                    elseif score == bestScore and spellID == baseSpell and (not best or best.spellID ~= baseSpell) then
                        beatsCurrent = true
                    end
                end

                if beatsCurrent then
                    best = {
                        spellID = spellID,
                        bucket = bucketName,
                        score = score,
                        reason = reason,
                        scoreBreakdown = breakdown,
                    }
                    bestBucketRank = bucketRank
                    bestScore = score
                end
            end
        end
    end

    return best
end

function Engine:ComputeQueue(iconCount)
    _computeTick = _computeTick + 1
    wipe(_queue)
    local queue = _queue
    local profile = self.activeProfile
    RefreshACSuggestions()
    local strict = IsStrictMode() == true
    local rawSpell = _acPrimarySpell
    local baseSpell = rawSpell
    local rotSpells = _acRotationCatalog
    local fallbackDropReason = nil
    iconCount = type(iconCount) == "number" and math.max(1, math.floor(iconCount)) or 1

    if _acRawStatus == "nil" then
        fallbackDropReason = "raw_ac_nil"
    elseif _acRawStatus == "secret" then
        fallbackDropReason = "raw_ac_secret"
    elseif _acRawStatus == "error" then
        fallbackDropReason = "raw_ac_error"
    elseif _acRawStatus == "invalid" then
        fallbackDropReason = "raw_ac_invalid"
    elseif _acRawStatus == "unavailable" then
        fallbackDropReason = "assisted_combat_unavailable"
    end

    if not profile and fallbackDropReason == nil then
        fallbackDropReason = "no_active_profile"
    end

    -- Build conditional blacklist for this frame
    wipe(_condBlacklist)
    local condBlacklist = _condBlacklist
    if profile and not strict then
        for _, rule in ipairs(profile.rules) do
            if rule.type == "BLACKLIST_CONDITIONAL" and self:EvalCondition(rule.condition) then
                condBlacklist[rule.spellID] = true
            end
        end
    end

    -- IsBlocked uses module-level tables (blacklistedSpells + _condBlacklist)

    if not strict and baseSpell and IsBlocked(baseSpell) then
        baseSpell = nil
        fallbackDropReason = "raw_ac_blacklisted"
    end
    if not strict and baseSpell and not self:IsSpellCastable(baseSpell) then
        baseSpell = nil
        fallbackDropReason = "raw_ac_locally_uncastable"
    end

    local pos1 = nil
    local source = "none"
    local reason = nil
    local bucket = nil
    local score = nil
    local scoreBreakdown = nil

    local hybridDecision = nil
    if profile and not strict then
        hybridDecision = self:SelectHybridDecision(profile, baseSpell, rotSpells)
    end
    if strict then
        if _acRawStatus == "available" then
            pos1 = rawSpell
            source = "ac"
            fallbackDropReason = nil
        end
    elseif hybridDecision then
        pos1 = hybridDecision.spellID
        source = "hybrid"
        reason = hybridDecision.reason or hybridDecision.bucket
        bucket = hybridDecision.bucket
        score = hybridDecision.score
        scoreBreakdown = hybridDecision.scoreBreakdown
    else
        -- PIN rules (highest priority, first match wins). EXPERIMENTAL_PIN is
        -- only reachable when strict mode is disabled. Existing PIN/PREFER
        -- rules are treated as experimental until strict-safe presentation
        -- rule types exist.
        local pinnedSpell = nil
        local firedRule = nil
        if profile then
            for _, rule in ipairs(profile.rules) do
                if (rule.type == "PIN" or rule.type == "EXPERIMENTAL_PIN")
                    and self:EvalCondition(rule.condition) then
                    if self:IsSpellCastable(rule.spellID) and not IsBlocked(rule.spellID) then
                        pinnedSpell = rule.spellID
                        firedRule = rule
                        break
                    end
                end
            end
        end

        -- PREFER rules (only if no PIN fired). EXPERIMENTAL_PREFER is only
        -- reachable when strict mode is disabled.
        local preferredSpell = nil
        if profile and not pinnedSpell then
            for _, rule in ipairs(profile.rules) do
                if (rule.type == "PREFER" or rule.type == "EXPERIMENTAL_PREFER")
                    and self:EvalCondition(rule.condition) then
                    if self:IsSpellCastable(rule.spellID) and not IsBlocked(rule.spellID) then
                        preferredSpell = rule.spellID
                        firedRule = rule
                        break
                    end
                end
            end
        end

        pos1 = pinnedSpell or preferredSpell or baseSpell
        if firedRule then
            source = (firedRule.type == "PIN" or firedRule.type == "EXPERIMENTAL_PIN") and "pin" or "prefer"
            reason = firedRule.reason
        elseif pos1 then
            source = "ac"
        end
    end

    -- A surviving raw AC primary was not dropped, even when no profile exists.
    if source == "ac" and pos1 == rawSpell and _acRawStatus == "available" then
        fallbackDropReason = nil
    end

    if pos1 and (strict or not IsBlocked(pos1)) then
        queue[#queue + 1] = pos1
    end

    -- Phase detection: profile-specific first, then engine-level AoE
    local phase = nil
    if profile and not strict and profile.GetPhase then
        phase = profile:GetPhase()
    end
    if profile and not strict and not phase then
        if self:EvalCondition(_aoeCondition) then phase = "AoE" end
    end

    -- AoE hint: profile declares a spell to show in secondary icon when AoE detected
    local aoeHintSpell = nil
    if profile and not strict and profile.aoeHint and self:EvalCondition(profile.aoeHint.condition) then
        local hintID = profile.aoeHint.spellID
        if hintID and self:IsSpellCastable(hintID) and not IsBlocked(hintID) then
            aoeHintSpell = hintID
        end
    end

    -- Rotation catalog entries are context only and never create a primary.
    if pos1 and #queue > 0 then
        wipe(_seen)
        local seen = _seen
        seen[pos1] = true

        for _, spellID in ipairs(rotSpells) do
            if #queue >= iconCount then break end
            if spellID
                and not seen[spellID]
                and (strict or (not IsBlocked(spellID) and self:IsSpellCastable(spellID)))
            then
                queue[#queue + 1] = spellID
                seen[spellID] = true
            end
        end
    end

    local meta = self.lastQueueMeta
    meta.source = source
    meta.reason = IsSecret(reason) and nil or reason
    meta.bucket = bucket
    meta.score = score
    meta.scoreBreakdown = scoreBreakdown
    meta.phase = phase
    meta.aoeHintSpell = aoeHintSpell
    meta.rawACSpell = _acRawStatus == "available" and rawSpell or nil
    meta.rawACStatus = _acRawStatus
    meta.finalPrimarySpell = pos1
    meta.fallbackDropReason = fallbackDropReason
    meta.strictState = strict
    meta.rotationCatalogRole = "context_only"
    CopySafeSpellArray(meta.rotationCatalogSnapshot, rotSpells)
    if source == "ac" and pos1 then
        meta.reasonCode = "AC_PRIMARY"
    elseif source == "pin" or source == "prefer" or source == "hybrid" then
        meta.reasonCode = "EXPERIMENTAL_OVERRIDE"
    else
        meta.reasonCode = "NO_AC_PRIMARY"
    end

    self:RecordDecisionChange()

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

-- Resolve the player's active hero talent tree via Blizzard's authoritative
-- API. Returns a numeric SubTreeID or nil. The call is guarded with pcall
-- and issecretvalue so profile activation stays safe when the API is
-- unavailable or returns a secret value.
local function GetActiveHeroTalentSubTreeID()
    if not C_ClassTalents or not C_ClassTalents.GetActiveHeroTalentSpec then
        return nil
    end
    local ok, subTreeID = pcall(C_ClassTalents.GetActiveHeroTalentSpec)
    if not ok then return nil end
    if IsSecret(subTreeID) then return nil end
    if type(subTreeID) ~= "number" then return nil end
    return subTreeID
end

function Engine:ActivateProfile(specID)
    local candidates = TrueShot.Profiles[specID]
    if not candidates or #candidates == 0 then
        self.activeProfile = nil
        return false
    end

    local prev = self.activeProfile

    local function adopt(profile)
        self.activeProfile = profile
        if profile ~= prev then
            if profile.ResetState then profile:ResetState() end
        end
        self:RebuildBlacklist()
        return true
    end

    -- First pass: match by heroTalentSubTreeID via C_ClassTalents. Hero trees
    -- whose signature talents are passives or procs (for example Spellslinger)
    -- cannot be identified via IsPlayerSpell, because those spells never land
    -- in the player spellbook. The SubTreeID check short-circuits that case.
    local activeSubTreeID = GetActiveHeroTalentSubTreeID()
    if activeSubTreeID then
        for _, profile in ipairs(candidates) do
            if profile.heroTalentSubTreeID == activeSubTreeID then
                return adopt(profile)
            end
        end
    end

    -- Second pass: match by markerSpell (legacy spellbook-based detection).
    for _, profile in ipairs(candidates) do
        if profile.markerSpell and IsPlayerSpell(profile.markerSpell) then
            return adopt(profile)
        end
    end

    -- Fallback: first profile without markerSpell. Profiles that already
    -- declare heroTalentSubTreeID but intentionally omit markerSpell still
    -- need a deterministic fallback path when C_ClassTalents is unavailable.
    for _, profile in ipairs(candidates) do
        if not profile.markerSpell then
            return adopt(profile)
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
