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
-- Probe: secrecy audit
------------------------------------------------------------------------

-- Key spells to check across all supported classes
local SECRECY_SPELLS = {
    -- BM Hunter
    { id = 272790, name = "Frenzy",          type = "aura",     note = "Barbed Shot stacks" },
    { id = 118455, name = "Beast Cleave",     type = "aura",     note = "AoE cleave buff" },
    { id = 19574,  name = "Bestial Wrath",    type = "both",     note = "30s burst CD" },
    { id = 217200, name = "Barbed Shot",      type = "cooldown", note = "2-charge" },
    { id = 34026,  name = "Kill Command",     type = "cooldown", note = "primary" },
    { id = 1264359,name = "Wild Thrash",      type = "cooldown", note = "AoE 8s CD" },
    { id = 466930, name = "Black Arrow",      type = "cooldown", note = "Dark Ranger" },
    -- Frost Mage
    { id = 190446, name = "Brain Freeze",     type = "aura",     note = "Flurry proc" },
    { id = 44544,  name = "Fingers of Frost", type = "aura",     note = "Ice Lance proc" },
    { id = 84714,  name = "Frozen Orb",       type = "cooldown", note = "burst CD" },
    -- Fire Mage
    { id = 48108,  name = "Hot Streak",       type = "aura",     note = "Pyroblast proc" },
    { id = 48107,  name = "Heating Up",       type = "aura",     note = "pre-Hot Streak" },
    { id = 190319, name = "Combustion",       type = "both",     note = "burst CD" },
    -- Arcane Mage
    { id = 365350, name = "Arcane Surge",     type = "cooldown", note = "burst CD" },
    -- SV Hunter
    { id = 1250646,name = "Takedown",         type = "cooldown", note = "burst CD" },
    { id = 1261193,name = "Boomstick",        type = "cooldown", note = "burst" },
    -- Feral Druid
    { id = 5217,   name = "Tiger's Fury",     type = "both",     note = "burst CD" },
    { id = 106951, name = "Berserk",          type = "both",     note = "burst CD" },
    -- DH Havoc
    { id = 191427, name = "Metamorphosis",    type = "both",     note = "burst CD" },
    -- General
    { id = 0,      name = "Focus (power)",    type = "power",    note = "Hunter resource" },
}

function Probe:SecrecyAudit()
    PrintHeader("secrecy audit (C_Secrets per-spell checks)")

    if not C_Secrets then
        PrintResult("status", "C_Secrets namespace not available")
        PrintClassification("IMPOSSIBLE - API missing")
        return
    end

    -- General checks
    if C_Secrets.HasSecretRestrictions then
        local ok, has = pcall(C_Secrets.HasSecretRestrictions)
        PrintResult("HasSecretRestrictions", ok and tostring(has) or "ERROR")
    end
    if C_Secrets.ShouldAurasBeSecret then
        local ok, val = pcall(C_Secrets.ShouldAurasBeSecret)
        PrintResult("ShouldAurasBeSecret (general)", ok and tostring(val) or "ERROR")
    end
    if C_Secrets.ShouldCooldownsBeSecret then
        local ok, val = pcall(C_Secrets.ShouldCooldownsBeSecret)
        PrintResult("ShouldCooldownsBeSecret (general)", ok and tostring(val) or "ERROR")
    end

    -- Focus power check
    if C_Secrets.ShouldUnitPowerBeSecret then
        local ok, val = pcall(C_Secrets.ShouldUnitPowerBeSecret, "player", 2) -- 2 = Focus
        PrintResult("Focus power secret", ok and tostring(val) or "ERROR")
        local ok2, val2 = pcall(C_Secrets.ShouldUnitPowerBeSecret, "player", 0) -- 0 = Mana
        PrintResult("Mana power secret", ok2 and tostring(val2) or "ERROR")
    end

    print(" ")
    print("|cff00ff00[[TS Probe]|r Per-spell secrecy:")
    print(string.format("  %-20s %-8s %-15s %-15s %s", "Spell", "Type", "Aura Secret?", "CD Secret?", "Note"))
    print("  " .. string.rep("-", 75))

    for _, spell in ipairs(SECRECY_SPELLS) do
        if spell.type == "power" then
            -- Already handled above
        else
            local auraResult = "n/a"
            local cdResult = "n/a"

            if (spell.type == "aura" or spell.type == "both") and C_Secrets.ShouldSpellAuraBeSecret then
                local ok, val = pcall(C_Secrets.ShouldSpellAuraBeSecret, spell.id)
                if ok then
                    auraResult = tostring(val)
                else
                    auraResult = "ERROR"
                end
            end

            if (spell.type == "cooldown" or spell.type == "both") and C_Secrets.ShouldSpellCooldownBeSecret then
                local ok, val = pcall(C_Secrets.ShouldSpellCooldownBeSecret, spell.id)
                if ok then
                    cdResult = tostring(val)
                else
                    cdResult = "ERROR"
                end
            end

            -- Also try GetSpellAuraSecrecy for the level
            local auraLevel = ""
            if (spell.type == "aura" or spell.type == "both") and C_Secrets.GetSpellAuraSecrecy then
                local ok, level = pcall(C_Secrets.GetSpellAuraSecrecy, spell.id)
                if ok then
                    if level == 0 then auraLevel = " [NEVER]"
                    elseif level == 1 then auraLevel = " [ALWAYS]"
                    elseif level == 2 then auraLevel = " [CONTEXT]"
                    else auraLevel = " [" .. tostring(level) .. "]" end
                end
            end

            print(string.format("  %-20s %-8s %-15s %-15s %s",
                spell.name, spell.type, auraResult .. auraLevel, cdResult, spell.note))
        end
    end

    print(" ")
    print("|cff00ff00[[TS Probe]|r Non-secret auras can be read with C_UnitAuras.GetAuraDataBySpellName()")
    print("  Non-secret cooldowns can be read with C_Spell.GetSpellCooldown()")
end

------------------------------------------------------------------------
-- Probe: aura read (validate actual aura data retrieval)
------------------------------------------------------------------------

local AURA_TEST_SPELLS = {
    { id = 272790, names = { "Frenzy", "Raserei" }, note = "Barbed Shot stacks" },
    { id = 118455, names = { "Beast Cleave", "Bestiale Spaltung" }, note = "AoE buff" },
    { id = 19574,  names = { "Bestial Wrath", "Zorn des Wildtiers" }, note = "Burst buff" },
}

function Probe:AuraRead()
    PrintHeader("aura read (all player buffs)")

    if not C_UnitAuras or not C_UnitAuras.GetBuffDataByIndex then
        PrintResult("status", "C_UnitAuras.GetBuffDataByIndex not available")
        return
    end

    local anyFound = false

    -- Method 1: C_UnitAuras.GetBuffDataByIndex
    print("  Method 1: GetBuffDataByIndex")
    for i = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetBuffDataByIndex, "player", i)
        if not ok then
            PrintResult("  index " .. i, "ERROR: " .. tostring(aura))
            break
        end
        if aura == nil then break end
        if IsSecret(aura) then
            PrintResult("  index " .. i, "SECRET TABLE")
            anyFound = true
        else
            local name = aura.name or "?"
            local sid = aura.spellId or 0
            local stacks = aura.applications or 0
            PrintResult("  " .. i, tostring(name) .. " (" .. tostring(sid) .. ") stacks=" .. tostring(stacks)
                .. " [nameS:" .. SecretLabel(aura.name) .. " stackS:" .. SecretLabel(aura.applications) .. "]")
            anyFound = true
        end
    end
    if not anyFound then print("    (nothing returned)") end

    -- Method 2: legacy UnitBuff
    print(" ")
    print("  Method 2: UnitBuff (legacy)")
    if UnitBuff then
        for i = 1, 10 do
            local ok, name, icon, count, dispelType, duration, expires, source, isStealable, nameplateShowPersonal, spellId = pcall(UnitBuff, "player", i)
            if not ok then
                PrintResult("  index " .. i, "ERROR: " .. tostring(name))
                break
            end
            if name == nil then break end
            PrintResult("  " .. i, tostring(name) .. " (" .. tostring(spellId) .. ") count=" .. tostring(count)
                .. " [nameS:" .. SecretLabel(name) .. " countS:" .. SecretLabel(count) .. "]")
            anyFound = true
        end
    else
        print("    UnitBuff not available")
    end

    -- Method 3: AuraUtil.ForEachAura
    print(" ")
    print("  Method 3: AuraUtil.ForEachAura")
    if AuraUtil and AuraUtil.ForEachAura then
        local count = 0
        local ok, err = pcall(AuraUtil.ForEachAura, "player", "HELPFUL", nil, function(aura)
            count = count + 1
            if count <= 10 then
                if IsSecret(aura) then
                    PrintResult("  " .. count, "SECRET")
                else
                    PrintResult("  " .. count, tostring(aura.name) .. " (" .. tostring(aura.spellId) .. ")"
                        .. " stacks=" .. tostring(aura.applications)
                        .. " [S:" .. SecretLabel(aura.name) .. "]")
                end
            end
        end)
        if not ok then PrintResult("  error", tostring(err)) end
        if count == 0 then print("    (nothing returned)") end
    else
        print("    AuraUtil.ForEachAura not available")
    end

    -- Also try reading cooldowns
    print(" ")
    PrintHeader("cooldown read (C_Spell.GetSpellCooldown)")
    local cdSpells = {
        { id = 19574,  name = "Bestial Wrath" },
        { id = 217200, name = "Barbed Shot" },
        { id = 34026,  name = "Kill Command" },
        { id = 1264359,name = "Wild Thrash" },
    }
    for _, spell in ipairs(cdSpells) do
        if C_Spell and C_Spell.GetSpellCooldown then
            local ok, cd = pcall(C_Spell.GetSpellCooldown, spell.id)
            if ok and cd then
                local start = cd.startTime or 0
                local dur = cd.duration or 0
                PrintResult(spell.name, "start=" .. tostring(start)
                    .. " dur=" .. tostring(dur)
                    .. " startSecret=" .. SecretLabel(start)
                    .. " durSecret=" .. SecretLabel(dur))
            elseif ok then
                PrintResult(spell.name, "nil")
            else
                PrintResult(spell.name, "ERROR: " .. tostring(cd))
            end
        end
    end

    if not anyFound then
        print(" ")
        print("|cffffcc00Keine Buffs aktiv. Cast Barbed Shot fuer Frenzy und fuehr nochmal aus.|r")
    end
end

------------------------------------------------------------------------
-- Probe: spell overlay (proc glow detection)
------------------------------------------------------------------------

local OVERLAY_SPELLS = {
    -- Spells that glow when their proc is active
    -- Hunter
    { id = 34026,  name = "Kill Command",   proc = "Nature's Ally / reset" },
    { id = 19574,  name = "Bestial Wrath",  proc = "ready" },
    { id = 217200, name = "Barbed Shot",    proc = "charge ready" },
    { id = 1264359,name = "Wild Thrash",    proc = "ready" },
    { id = 466930, name = "Black Arrow",    proc = "ready / Withering Fire" },
    { id = 392060, name = "Wailing Arrow",  proc = "available during BW" },
    -- Frost Mage
    { id = 44614,  name = "Flurry",         proc = "Brain Freeze" },
    { id = 30455,  name = "Ice Lance",      proc = "Fingers of Frost" },
    { id = 199786, name = "Glacial Spike",  proc = "Icicles full" },
    -- Fire Mage
    { id = 11366,  name = "Pyroblast",      proc = "Hot Streak" },
    { id = 108853, name = "Fire Blast",     proc = "Heating Up / charge" },
    -- Arcane Mage
    { id = 5143,   name = "Arcane Missiles",proc = "Clearcasting" },
    -- SV Hunter
    { id = 259489, name = "Kill Command SV",proc = "reset" },
    { id = 1261193,name = "Boomstick",      proc = "Takedown" },
    -- Feral
    { id = 22568,  name = "Ferocious Bite", proc = "Apex Predator" },
    -- DH
    { id = 162794, name = "Chaos Strike",   proc = "Meta / refund" },
}

function Probe:SpellOverlay()
    PrintHeader("spell overlay / proc glow (C_SpellActivationOverlay)")

    if not C_SpellActivationOverlay or not C_SpellActivationOverlay.IsSpellOverlayed then
        PrintResult("status", "C_SpellActivationOverlay.IsSpellOverlayed not available")
        PrintClassification("IMPOSSIBLE - API missing")
        return
    end

    print(string.format("  %-20s %-7s %-8s %s", "Spell", "Glowing", "Secret?", "Proc"))
    print("  " .. string.rep("-", 60))

    local anyGlowing = false
    for _, spell in ipairs(OVERLAY_SPELLS) do
        local ok, result = pcall(C_SpellActivationOverlay.IsSpellOverlayed, spell.id)
        if ok then
            local glowing = result == true
            local secretStr = SecretLabel(result)
            if glowing then anyGlowing = true end
            print(string.format("  %-20s %-7s %-8s %s",
                spell.name, glowing and "YES" or "no", secretStr, spell.proc))
        else
            print(string.format("  %-20s ERROR: %s", spell.name, tostring(result)))
        end
    end

    print(" ")
    if anyGlowing then
        PrintClassification("DIRECT - overlay glow is readable! Proc detection possible.")
    else
        print("  No procs active right now. Test during combat with active procs.")
        print("  Also registering event listener for SPELL_ACTIVATION_OVERLAY_GLOW_SHOW...")
    end

    -- Register a temporary event listener to catch proc events
    if not self._overlayFrame then
        self._overlayFrame = CreateFrame("Frame")
        self._overlayFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
        self._overlayFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
        self._overlayFrame:SetScript("OnEvent", function(_, event, spellID)
            local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID) or "?"
            print("|cff00ff00[[TS Overlay]|r " .. event .. ": " .. tostring(name) .. " (" .. tostring(spellID) .. ")"
                .. " secret=" .. SecretLabel(spellID))
        end)
        print("  Listener active - cast spells to see proc events. /reload to stop.")
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
    elseif sub == "secrecy" then
        self:SecrecyAudit()
    elseif sub == "aura" then
        self:AuraRead()
    elseif sub == "overlay" then
        self:SpellOverlay()
    elseif sub == "all" then
        local spellID = tonumber(args:match("%S+%s+(%d+)"))
        self:RunAll(spellID)
    elseif sub == "help" then
        print("|cff00ff00[[TS Probe]|r Signal validation commands:")
        print("  /ts probe target   - Test UnitCastingInfo / UnitChannelInfo")
        print("  /ts probe plates   - Test C_NamePlate.GetNamePlates")
        print("  /ts probe charges [spellID]  - Test C_Spell.GetSpellCharges (default: Barbed Shot)")
        print("  /ts probe secrecy  - Audit per-spell aura/cooldown secrecy levels")
        print("  /ts probe aura     - Read actual aura + cooldown data (cast Barbed Shot first)")
        print("  /ts probe overlay  - Test proc glow detection (cast in combat to trigger procs)")
        print("  /ts probe all [spellID]      - Run all probes")
    else
        print("|cff00ff00[[TS Probe]|r Unknown probe: " .. sub .. ". Use /ts probe help")
    end
end
