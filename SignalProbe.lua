-- SignalProbe: in-game validation harness for shared signal surfaces
-- Run /ts probe <signal> to test API surfaces before profiles depend on them.
-- Results feed into docs/SIGNAL_VALIDATION.md classification.

TrueShot = TrueShot or {}
TrueShot.SignalProbe = {}

local Probe = TrueShot.SignalProbe

local BARBED_SHOT_ID = 217200  -- BM charge-based spell for default testing

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local function IsSecret(val)
    return issecretvalue and issecretvalue(val) or false
end

local function SecretLabel(val)
    if not issecretvalue then return "n/a (no issecretvalue)" end
    if issecretvalue(val) then return "SECRET" end
    return "not secret"
end

local function PrintHeader(name)
    print("|cff00ff00[[TS Probe]|r Testing: |cffffcc00" .. name .. "|r")
end

local function PrintResult(key, value)
    print("  " .. key .. ": " .. tostring(value))
end

local function PrintClassification(label)
    print("  => |cffffcc00Classification hint: " .. label .. "|r")
end

------------------------------------------------------------------------
-- Probe: target casting
------------------------------------------------------------------------

function Probe:TargetCasting()
    PrintHeader("target_casting (UnitCastingInfo / UnitChannelInfo)")

    if not UnitExists("target") then
        PrintResult("status", "no target selected")
        PrintClassification("select a target and retry")
        return
    end

    PrintResult("target", UnitName("target") or "?")

    -- UnitCastingInfo
    local ok1, casting = pcall(UnitCastingInfo, "target")
    PrintResult("pcall UnitCastingInfo", ok1 and "ok" or "ERROR: " .. tostring(casting))
    if ok1 then
        PrintResult("casting name", tostring(casting))
        PrintResult("casting secret", SecretLabel(casting))
    end

    -- UnitChannelInfo
    local ok2, channeling = pcall(UnitChannelInfo, "target")
    PrintResult("pcall UnitChannelInfo", ok2 and "ok" or "ERROR: " .. tostring(channeling))
    if ok2 then
        PrintResult("channeling name", tostring(channeling))
        PrintResult("channeling secret", SecretLabel(channeling))
    end

    -- Classification hint
    if not ok1 and not ok2 then
        PrintClassification("IMPOSSIBLE - both APIs error")
    elseif (ok1 and IsSecret(casting)) or (ok2 and IsSecret(channeling)) then
        PrintClassification("SECRET - returns secret values")
    elseif ok1 or ok2 then
        PrintClassification("likely DIRECT - test while target is casting to confirm value changes")
    end
end

------------------------------------------------------------------------
-- Probe: nameplate count
------------------------------------------------------------------------

function Probe:NameplateCount()
    PrintHeader("target_count (C_NamePlate.GetNamePlates)")

    if not C_NamePlate or not C_NamePlate.GetNamePlates then
        PrintResult("status", "C_NamePlate.GetNamePlates not available")
        PrintClassification("IMPOSSIBLE - API missing")
        return
    end

    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    PrintResult("pcall GetNamePlates", ok and "ok" or "ERROR: " .. tostring(plates))
    if not ok then
        PrintClassification("IMPOSSIBLE - API errors")
        return
    end

    PrintResult("table secret", SecretLabel(plates))
    if IsSecret(plates) then
        PrintClassification("SECRET - table itself is secret")
        return
    end

    local total = #plates
    PrintResult("total nameplates", total)

    local hostile = 0
    local anyEntrySecret = false
    for i, plate in ipairs(plates) do
        local unit = plate.namePlateUnitToken
        PrintResult("  plate " .. i .. " token", tostring(unit))
        PrintResult("  plate " .. i .. " token secret", SecretLabel(unit))
        if IsSecret(unit) then
            anyEntrySecret = true
        elseif unit and UnitExists(unit) then
            local name = UnitName(unit) or "?"
            local canAttack = UnitCanAttack("player", unit)
            PrintResult("  plate " .. i .. " name", name)
            PrintResult("  plate " .. i .. " canAttack", tostring(canAttack))
            PrintResult("  plate " .. i .. " canAttack secret", SecretLabel(canAttack))
            if IsSecret(canAttack) then
                anyEntrySecret = true
            elseif canAttack then
                hostile = hostile + 1
            end
        end
    end
    PrintResult("hostile count", hostile)

    -- Classification hint
    if total == 0 then
        PrintClassification("INCONCLUSIVE - no nameplates visible. Pull 2+ mobs and retry.")
    elseif anyEntrySecret then
        PrintClassification("PARTIAL - table readable but some entry fields are secret")
    elseif hostile > 0 then
        PrintClassification("likely DIRECT - verify count matches visible hostile mobs")
    else
        PrintClassification("PARTIAL - nameplates returned but no hostile units found")
    end
end

------------------------------------------------------------------------
-- Probe: spell charges
------------------------------------------------------------------------

function Probe:SpellCharges(spellID)
    spellID = spellID or BARBED_SHOT_ID
    local spellName = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID) or "?"
    PrintHeader("spell_charges (C_Spell.GetSpellCharges) - " .. spellName .. " (" .. spellID .. ")")

    if not C_Spell or not C_Spell.GetSpellCharges then
        PrintResult("status", "C_Spell.GetSpellCharges not available")
        PrintClassification("IMPOSSIBLE - API missing")
        return
    end

    local ok, info = pcall(C_Spell.GetSpellCharges, spellID)
    PrintResult("pcall GetSpellCharges", ok and "ok" or "ERROR: " .. tostring(info))
    if not ok then
        PrintClassification("IMPOSSIBLE - API errors for this spell")
        return
    end

    if not info then
        PrintResult("status", "nil (spell may not be charge-based or not known)")
        PrintClassification("check that you have this spell talented")
        return
    end

    PrintResult("currentCharges", tostring(info.currentCharges))
    PrintResult("currentCharges secret", SecretLabel(info.currentCharges))
    PrintResult("maxCharges", tostring(info.maxCharges))
    PrintResult("maxCharges secret", SecretLabel(info.maxCharges))
    PrintResult("cooldownStartTime", tostring(info.cooldownStartTime))
    PrintResult("cooldownStartTime secret", SecretLabel(info.cooldownStartTime))
    PrintResult("cooldownDuration", tostring(info.cooldownDuration))
    PrintResult("cooldownDuration secret", SecretLabel(info.cooldownDuration))

    -- Classification hint
    if IsSecret(info.currentCharges) then
        PrintClassification("SECRET - charge count is secret")
    elseif IsSecret(info.cooldownStartTime) then
        PrintClassification("PARTIAL - charges readable but recharge timing is secret")
    elseif info.currentCharges and info.maxCharges then
        PrintClassification("likely DIRECT - verify by consuming a charge and re-running")
    end
end

------------------------------------------------------------------------
-- Probe: run all
------------------------------------------------------------------------

function Probe:RunAll(chargeSpellID)
    self:TargetCasting()
    print(" ")
    self:NameplateCount()
    print(" ")
    self:SpellCharges(chargeSpellID)
end

------------------------------------------------------------------------
-- Slash command integration
------------------------------------------------------------------------

function Probe:HandleCommand(args)
    local sub = args:match("^(%S+)") or "all"
    sub = sub:lower()

    if sub == "target" then
        self:TargetCasting()
    elseif sub == "plates" then
        self:NameplateCount()
    elseif sub == "charges" then
        local spellID = tonumber(args:match("%S+%s+(%d+)"))
        self:SpellCharges(spellID)
    elseif sub == "all" then
        local spellID = tonumber(args:match("%S+%s+(%d+)"))
        self:RunAll(spellID)
    elseif sub == "help" then
        print("|cff00ff00[[TS Probe]|r Signal validation commands:")
        print("  /ts probe target   - Test UnitCastingInfo / UnitChannelInfo")
        print("  /ts probe plates   - Test C_NamePlate.GetNamePlates")
        print("  /ts probe charges [spellID]  - Test C_Spell.GetSpellCharges (default: Barbed Shot)")
        print("  /ts probe all [spellID]      - Run all probes")
    else
        print("|cff00ff00[[TS Probe]|r Unknown probe: " .. sub .. ". Use /ts probe help")
    end
end
