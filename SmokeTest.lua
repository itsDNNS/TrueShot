-- TrueShot SmokeTest: in-client checks for strict-mode runtime behavior.

TrueShot = TrueShot or {}
TrueShot.SmokeTest = TrueShot.SmokeTest or {}

local SmokeTest = TrueShot.SmokeTest

local function Add(checks, name, ok, detail)
    checks[#checks + 1] = {
        name = name,
        ok = ok and true or false,
        detail = detail,
    }
end

local function SafeCall(fn, ...)
    if not fn then return false, nil end
    return pcall(fn, ...)
end

local function SafeDetail(value)
    if issecretvalue and issecretvalue(value) then return "<secret>" end
    if value == nil then return "nil" end
    if type(value) == "string" or type(value) == "number" or type(value) == "boolean" then
        return tostring(value)
    end
    return "unavailable"
end

function SmokeTest:Run(options)
    options = options or {}
    local checks = {}
    local buildVersion, buildNumber, buildDate, interfaceVersion = GetBuildInfo()
    local mode = options.mode or "load"

    Add(checks, "SignalRegistry loaded", TrueShot.SignalRegistry ~= nil)
    Add(checks, "Engine loaded", TrueShot.Engine ~= nil)
    Add(checks, "Display loaded", TrueShot.Display ~= nil)
    Add(checks, "Strict mode enabled", TrueShot.GetOpt and TrueShot.GetOpt("strictCompliance") ~= false)

    local inCombat = false
    if UnitAffectingCombat then
        local okCombat, combat = SafeCall(UnitAffectingCombat, "player")
        inCombat = okCombat and combat == true
    end
    if options.requireCombat then
        Add(checks, "Player is in combat", inCombat, tostring(inCombat))
    end

    local acAvailable = false
    if C_AssistedCombat and C_AssistedCombat.IsAvailable then
        local ok, available = SafeCall(C_AssistedCombat.IsAvailable)
        local readable = not (issecretvalue and issecretvalue(available))
        acAvailable = ok and readable and available == true
        Add(checks, "Assisted Combat availability checked", ok and readable, SafeDetail(available))
    else
        Add(checks, "Assisted Combat API exists", false, "C_AssistedCombat missing")
    end

    local profile = TrueShot.Engine and TrueShot.Engine.activeProfile
    Add(checks, "Active profile resolved", profile ~= nil, profile and (profile.displayName or profile.id) or "none")

    local queueOk, queue = false, nil
    if TrueShot.Engine and TrueShot.Engine.ComputeQueue and TrueShot.GetOpt then
        queueOk, queue = pcall(TrueShot.Engine.ComputeQueue, TrueShot.Engine, TrueShot.GetOpt("iconCount"))
    end
    local queueCount = type(queue) == "table" and #queue or 0
    Add(checks, "ComputeQueue pcall", queueOk, queueOk and ("items=" .. tostring(queueCount)) or tostring(queue))

    local meta = TrueShot.Engine and TrueShot.Engine.lastQueueMeta
    local strict = TrueShot.GetOpt and TrueShot.GetOpt("strictCompliance") ~= false
    if strict and meta then
        local hasRawPrimary = meta.rawACStatus == "available"
        local expectedSource = hasRawPrimary and "ac" or "none"
        local expectedReason = hasRawPrimary and "AC_PRIMARY" or "NO_AC_PRIMARY"
        Add(checks, "Strict source matches raw AC status", meta.source == expectedSource, SafeDetail(meta.source))
        Add(checks, "Strict reasonCode matches raw AC status", meta.reasonCode == expectedReason, SafeDetail(meta.reasonCode))
        Add(checks, "Strict primary is unchanged raw AC",
            (hasRawPrimary and meta.finalPrimarySpell == meta.rawACSpell)
                or (not hasRawPrimary and meta.finalPrimarySpell == nil),
            SafeDetail(meta.finalPrimarySpell))
        if not hasRawPrimary then
            Add(checks, "Strict catalog did not become primary", queueCount == 0, "items=" .. tostring(queueCount))
        end
    end

    if TrueShot.SignalRegistry then
        Add(checks, "resource blocked in strict", not TrueShot.SignalRegistry:IsConditionAllowed({ type = "resource", powerType = 2, op = ">=", value = 1 }))
        Add(checks, "cd_ready blocked in strict", not TrueShot.SignalRegistry:IsConditionAllowed({ type = "cd_ready", spellID = 19574 }))
        Add(checks, "spell_charges blocked in strict", not TrueShot.SignalRegistry:IsConditionAllowed({ type = "spell_charges", spellID = 217200, op = ">=", value = 1 }))
    end

    local failed = 0
    for _, check in ipairs(checks) do
        if not check.ok then failed = failed + 1 end
    end

    local report = {
        timestamp = date and date("!%Y-%m-%dT%H:%M:%SZ") or tostring(GetServerTime and GetServerTime() or GetTime()),
        buildVersion = buildVersion,
        buildNumber = buildNumber,
        buildDate = buildDate,
        interfaceVersion = interfaceVersion,
        mode = mode,
        inCombat = inCombat,
        acAvailable = acAvailable,
        profileID = profile and profile.id or nil,
        profile = profile and (profile.displayName or profile.id) or nil,
        specID = profile and profile.specID or nil,
        heroTalentSubTreeID = profile and profile.heroTalentSubTreeID or nil,
        queueCount = queueCount,
        source = meta and meta.source or nil,
        reasonCode = meta and meta.reasonCode or nil,
        rawACStatus = meta and meta.rawACStatus or nil,
        rawACSpell = meta and meta.rawACSpell or nil,
        finalPrimarySpell = meta and meta.finalPrimarySpell or nil,
        fallbackDropReason = meta and meta.fallbackDropReason or nil,
        strict = strict,
        passed = failed == 0,
        failed = failed,
        total = #checks,
        checks = checks,
    }

    TrueShotDB = TrueShotDB or {}
    TrueShotDB.smokeReport = report
    TrueShotDB.smokeHistory = TrueShotDB.smokeHistory or {}
    table.insert(TrueShotDB.smokeHistory, report)
    while #TrueShotDB.smokeHistory > 50 do
        table.remove(TrueShotDB.smokeHistory, 1)
    end

    print("|cff00ff00[TS Smoke]|r " .. tostring(#checks - failed) .. "/" .. tostring(#checks) .. " passed.")
    if failed > 0 then
        for _, check in ipairs(checks) do
            if not check.ok then
                print("|cffff0000[TS Smoke]|r FAIL: " .. check.name .. (check.detail and (" (" .. tostring(check.detail) .. ")") or ""))
            end
        end
    end

    return report
end
