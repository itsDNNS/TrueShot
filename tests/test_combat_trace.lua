local now = 1000
_G.GetTime = function() return now end

TrueShot = {
    Engine = {
        activeProfile = {
            rotationalSpells = { [101] = true, [202] = true },
        },
    },
}

dofile("CombatTrace.lua")

local trace = TrueShot.CombatTrace
trace:Reset()

trace:RecordCast(202, 101, "ac", nil, { 101, 202 }, {
    reasonCode = "AC_PRIMARY",
    rawACStatus = "available",
    strictState = true,
    rotationCatalogRole = "context_only",
})

local summary = trace:GetFightSummary()
assert(summary.softMatches == 0, "rotation-catalog context must not count as a soft match")
assert(summary.misses == 1, "a non-primary cast remains a miss")

now = now + 1
trace:RecordCast(101, 101, "ac", nil, { 101, 202 }, {
    reasonCode = "AC_PRIMARY",
    rawACStatus = "available",
    strictState = true,
    rotationCatalogRole = "context_only",
})

summary = trace:GetFightSummary()
assert(summary.matches == 1, "the displayed primary still counts as a match")

local recent = trace:GetRecentEvents(1)
assert(recent[1].displayedReasonCode == "AC_PRIMARY")
assert(recent[1].rawACStatus == "available")
assert(recent[1].strictState == true)

print("6 passed, 0 failed")
