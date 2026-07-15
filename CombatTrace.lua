-- TrueShot CombatTrace: combat event recording and classification
-- Single source of truth for rotation analytics (Scorecard + HeartbeatStrip)

TrueShot = TrueShot or {}
TrueShot.CombatTrace = {}

local CombatTrace = TrueShot.CombatTrace
local GetTime = GetTime

------------------------------------------------------------------------
-- Configuration
------------------------------------------------------------------------

local RING_SIZE = 60             -- ring buffer for heartbeat display
local GAP_MULTIPLIER = 1.5      -- inter-cast idle threshold = GCD * this
local DEFAULT_GCD = 1.5          -- fallback GCD (haste unknown in Midnight)

------------------------------------------------------------------------
-- Ring buffer (fixed pool, wraps around for heartbeat display)
------------------------------------------------------------------------

local ring = {}
local ringHead = 0               -- next write position (1-based, wraps)
local ringCount = 0              -- total entries in ring (capped at RING_SIZE)
local lastCastTime = 0

-- Pre-allocate ring slots
for i = 1, RING_SIZE do
    ring[i] = {
        t = 0,
        castSpellID = 0,
        displayedSpellID = 0,
        displayedSource = "ac",
        displayedReason = nil,
        displayedReasonCode = nil,
        rawACStatus = nil,
        strictState = nil,
        classification = "unscored",
        gapDuration = nil,
    }
end

------------------------------------------------------------------------
-- Rolling summary counters (never stop counting, independent of ring)
------------------------------------------------------------------------

local summary = {
    matches = 0,
    softMatches = 0,
    misses = 0,
    unscored = 0,
    gaps = 0,
    totalGapTime = 0,
}

local totalEvents = 0  -- total events recorded this fight (including wrapped)

------------------------------------------------------------------------
-- Reusable result table for GetRecentEvents (avoids per-tick allocation)
------------------------------------------------------------------------

local recentResult = {}

------------------------------------------------------------------------
-- Classification
------------------------------------------------------------------------

local function ClassifyCast(castSpellID, displayedSpellID, displayedQueue, profile, decisionMeta)
    if profile and profile.rotationalSpells then
        if not profile.rotationalSpells[castSpellID] then
            return "unscored"
        end
    end

    if castSpellID == displayedSpellID then
        return "match"
    end

    -- Rotation-catalog icons are context, not predicted or recommended future
    -- casts, so they do not earn a soft match.
    if displayedQueue and (not decisionMeta or decisionMeta.rotationCatalogRole ~= "context_only") then
        for i = 2, #displayedQueue do
            if displayedQueue[i] == castSpellID then
                return "soft_match"
            end
        end
    end

    return "miss"
end

------------------------------------------------------------------------
-- Internal: write one event to the ring and update counters
------------------------------------------------------------------------

local function WriteEvent(t, castSpellID, displayedSpellID, displayedSource, displayedReason, classification, gapDuration, decisionMeta)
    ringHead = (ringHead % RING_SIZE) + 1
    if ringCount < RING_SIZE then
        ringCount = ringCount + 1
    end
    totalEvents = totalEvents + 1

    local slot = ring[ringHead]
    slot.t = t
    slot.castSpellID = castSpellID
    slot.displayedSpellID = displayedSpellID
    slot.displayedSource = displayedSource
    slot.displayedReason = displayedReason
    slot.displayedReasonCode = decisionMeta and decisionMeta.reasonCode or nil
    slot.rawACStatus = decisionMeta and decisionMeta.rawACStatus or nil
    slot.strictState = decisionMeta and decisionMeta.strictState == true or false
    slot.classification = classification
    slot.gapDuration = gapDuration

    -- Update rolling counters
    if classification == "match" then
        summary.matches = summary.matches + 1
    elseif classification == "soft_match" then
        summary.softMatches = summary.softMatches + 1
    elseif classification == "miss" then
        summary.misses = summary.misses + 1
    elseif classification == "unscored" then
        summary.unscored = summary.unscored + 1
    elseif classification == "gap" then
        summary.gaps = summary.gaps + 1
        summary.totalGapTime = summary.totalGapTime + (gapDuration or 0)
    end
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------

function CombatTrace:Reset()
    ringHead = 0
    ringCount = 0
    totalEvents = 0
    lastCastTime = 0
    summary.matches = 0
    summary.softMatches = 0
    summary.misses = 0
    summary.unscored = 0
    summary.gaps = 0
    summary.totalGapTime = 0
end

function CombatTrace:RecordCast(castSpellID, displayedSpellID, displayedSource, displayedReason, displayedQueue, decisionMeta)
    local now = GetTime()
    local profile = TrueShot.Engine and TrueShot.Engine.activeProfile

    -- Insert gap event if inter-cast idle time exceeds threshold
    if lastCastTime > 0 then
        local idleTime = now - lastCastTime
        if idleTime > (DEFAULT_GCD * GAP_MULTIPLIER) then
            WriteEvent(
                lastCastTime + DEFAULT_GCD,
                0,
                displayedSpellID or 0,
                displayedSource or "ac",
                nil,
                "gap",
                idleTime - DEFAULT_GCD,
                decisionMeta
            )
        end
    end

    -- Record the actual cast
    local classification = ClassifyCast(castSpellID, displayedSpellID, displayedQueue, profile, decisionMeta)
    WriteEvent(
        now,
        castSpellID,
        displayedSpellID or 0,
        displayedSource or "ac",
        displayedReason,
        classification,
        nil,
        decisionMeta
    )

    lastCastTime = now
end

function CombatTrace:GetRecentEvents(count)
    -- Reuse table to avoid per-tick allocation
    for i = 1, #recentResult do
        recentResult[i] = nil
    end

    count = math.min(count, ringCount)
    if count == 0 then return recentResult end

    -- Walk backwards from ringHead to get the most recent 'count' events
    for i = 0, count - 1 do
        local idx = ((ringHead - 1 - i) % RING_SIZE) + 1
        recentResult[count - i] = ring[idx]
    end

    return recentResult
end

function CombatTrace:GetFightSummary()
    local scoredCasts = summary.matches + summary.softMatches + summary.misses
    local alignmentScore = 0
    if scoredCasts > 0 then
        alignmentScore = ((summary.matches + 0.5 * summary.softMatches) / scoredCasts) * 100
    end

    return {
        alignmentScore = alignmentScore,
        matches = summary.matches,
        softMatches = summary.softMatches,
        misses = summary.misses,
        unscored = summary.unscored,
        scoredCasts = scoredCasts,
        totalCasts = totalEvents - summary.gaps,
        gapCount = summary.gaps,
        totalGapTime = summary.totalGapTime,
    }
end

function CombatTrace:GetEventCount()
    return totalEvents
end
