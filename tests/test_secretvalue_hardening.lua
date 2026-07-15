-- Focused contracts for fail-closed secret-value ordering at UI/API seams.

local function read_file(path)
    local f = assert(io.open(path, "r"))
    local text = f:read("*a")
    f:close()
    return text
end

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1 else
        failed = failed + 1
        print("FAIL: " .. name .. " -- " .. tostring(err))
    end
end
local function assert_contains(text, needle, message)
    if not text:find(needle, 1, true) then error(message or ("missing: " .. needle)) end
end
local function assert_not_contains(text, needle, message)
    if text:find(needle, 1, true) then error(message or ("unexpected: " .. needle)) end
end

test("Display never passes secret charge values to text setters", function()
    local display = read_file("Display.lua")
    assert_not_contains(display, "Secret: passthrough count for display")
    assert_not_contains(display, "chargeCount:SetText(current)\n        icon.chargeCount:Show()\n        icon.chargeCooldown:Hide()")
    assert_contains(display, "ClearChargeDisplay")
end)

test("Display guards cooldown values before type and formatting", function()
    local display = read_file("Display.lua")
    assert_contains(display, "IsSecretValue(startTime) or IsSecretValue(duration)")
    assert_contains(display, "IsSecretValue(remaining)")
end)

test("shipped charge helpers use central readable charge extraction", function()
    for _, path in ipairs({
        "Profiles/BM_PackLeader.lua",
        "Profiles/MM_Sentinel.lua",
        "Profiles/SV_PackLeader.lua",
        "Profiles/SV_Sentinel.lua",
    }) do
        local source = read_file(path)
        assert_not_contains(source, "info and info.currentCharges",
            path .. " branches on currentCharges before a secret guard")
        assert_not_contains(source, "charges and type(charges.currentCharges)",
            path .. " reads/types currentCharges before a secret guard")
    end
end)

if failed > 0 then error(string.format("%d passed, %d failed", passed, failed)) end
print(string.format("%d passed, %d failed", passed, failed))
