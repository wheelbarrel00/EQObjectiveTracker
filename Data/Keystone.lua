local _, ns = ...

local Keystone = ns:RegisterModule("Keystone", {})

local _issecret = _G.issecretvalue

-- Enum.WorldElapsedTimerTypes.ChallengeMode, for a client that does not carry the enum
local CHALLENGE_TIMER = 1
-- Shares of the time limit. Blizzard draws neither, so these are the figures Mythic+ timer
-- addons use, not a value read from the client.
local PLUS_TWO, PLUS_THREE = 0.8, 0.6
local MAX_AFFIXES = 4

-- What the sample key in /eqot mplus test starts at: twenty seconds before +3 runs out, or
-- with "late" fifteen before the whole timer does, so each change shows within a minute.
local TEST_LEAD, TEST_LATE_LEAD = 20, 15
local TEST_LIMIT, TEST_LEVEL = 1800, 12
local TEST_DEATHS, TEST_LOST = 3, 15
-- Tyrannical and Fortified, for a client that lists no current affixes
local TEST_AFFIXES = { 9, 10 }

-- Reused, since Scenarios:GetEntries refills it on every render
local key = { active = false, affixes = {}, affixN = 0 }
local affixInfo = {}
local stopped = {}
local lastTimerID, lastElapsed, lastStamp
local note = "not read yet"
local secretField
local test

local function plain(v, field)
    if _issecret and _issecret(v) then
        secretField = secretField or field
        return nil
    end
    return v
end

local function num(v, field)
    v = plain(v, field)
    return type(v) == "number" and v or nil
end

local function timerType()
    local E = Enum and Enum.WorldElapsedTimerTypes
    return (E and num(E.ChallengeMode)) or CHALLENGE_TIMER
end

-- Walks GetWorldElapsedTimers' ids without packing them into a table, the way Blizzard's own
-- CheckTimers does. Skipping a timer the server has stopped is ours.
local function scanTimers(want, ok, id, ...)
    if not ok or id == nil then return nil end
    id = num(id, "timer id")
    if id and not stopped[id] then
        local okT, _, elapsed, kind = pcall(GetWorldElapsedTime, id)
        elapsed = okT and num(elapsed, "elapsed") or nil
        if okT and num(kind, "timer type") == want and elapsed then return id, elapsed end
    end
    return scanTimers(want, true, ...)
end

-- Only a named answer is cached. GetAffixInfo may answer nothing, and that affix is asked
-- again on the next read.
local function affix(id)
    local a = affixInfo[id]
    if a then return a end
    local ok, name, description, icon = pcall(C_ChallengeMode.GetAffixInfo, id)
    if not ok then return nil end
    name = plain(name, "affix name")
    if type(name) ~= "string" then return nil end
    description = plain(description, "affix description")
    icon = plain(icon, "affix icon")
    a = {
        id          = id,
        name        = name,
        description = type(description) == "string" and description or nil,
        icon        = (type(icon) == "number" or type(icon) == "string") and icon or nil,
    }
    affixInfo[id] = a
    return a
end

local function readAffixes(list)
    for i = #key.affixes, 1, -1 do key.affixes[i] = nil end
    key.affixN = 0
    list = plain(list, "affixes")
    if type(list) ~= "table" then return end
    for i = 1, #list do
        local id = num(list[i], "affix id")
        local a = id and affix(id)
        if a and key.affixN < MAX_AFFIXES then
            key.affixN = key.affixN + 1
            key.affixes[key.affixN] = a
        end
    end
end

local function mapInfo(mapID)
    local ok, name, _, limit = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
    if not ok then return nil, nil end
    name = plain(name, "map name")
    return type(name) == "string" and name or nil, num(limit, "time limit")
end

-- A re-read is not a new reading: stamped only when the elapsed figure or the timer moves, so
-- a repaint between ticks cannot set the clock back by however long the reading had stood.
local function stamp(timerID, elapsed)
    if timerID ~= lastTimerID or elapsed ~= lastElapsed then
        lastTimerID, lastElapsed, lastStamp = timerID, elapsed, GetTime()
    end
    key.elapsed, key.elapsedAt = lastElapsed, lastStamp
end

local function setLimit(limit)
    key.timeLimit = limit
    key.plusTwo   = limit * PLUS_TWO
    key.plusThree = limit * PLUS_THREE
end

-- The reads Blizzard's key timer makes: a running challenge timer on an active keystone map.
-- The time limit test is ours, since the bar needs one.
function Keystone:Read()
    key.active, key.test, note, secretField = false, nil, nil, nil
    if not ns.Has.ChallengeTimer then
        note = "not on this client"
        return key
    end

    local okMap, mapID = pcall(C_ChallengeMode.GetActiveChallengeMapID)
    mapID = okMap and num(mapID, "map id") or nil
    if not mapID then
        note = okMap and "no key running" or "map read raised"
        return key
    end
    key.mapID = mapID

    local timerID, elapsed = scanTimers(timerType(), pcall(GetWorldElapsedTimers))
    if not timerID then
        note = "no challenge timer running"
        return key
    end

    local mapName, limit = mapInfo(mapID)
    if not (limit and limit > 0) then
        note = "no time limit for this map"
        return key
    end

    local okKey, level, affixes, energized = pcall(C_ChallengeMode.GetActiveKeystoneInfo)
    key.level = okKey and num(level, "level") or nil
    -- Only a plain false marks the key depleted. Blizzard marks nil too, but plain() turns a
    -- secret into nil, so marking it would be a guess.
    key.depleted = okKey and plain(energized, "energized") == false or false
    readAffixes(okKey and affixes or nil)

    local okD, deaths, lost = pcall(C_ChallengeMode.GetDeathCount)
    key.deaths   = okD and num(deaths, "deaths") or 0
    key.timeLost = okD and num(lost, "time lost") or 0

    key.mapName = mapName
    setLimit(limit)
    stamp(timerID, elapsed)
    key.active = true
    return key
end

-- Nothing read this pass, and why. Without it the status line would keep the last key.
function Keystone:Idle(why)
    key.active, key.test, note, secretField = false, nil, why, nil
    return key
end

-- A made-up key for /eqot mplus test, drawn only while no real scenario is up. The dungeon and
-- affixes are real reads where the client answers, so the names and icons are its own.
function Keystone:ReadTest()
    key.active, key.test, note, secretField = false, test, nil, nil
    if not test then return key end

    local mapID, mapName, limit
    local CM = C_ChallengeMode
    local okMaps, maps = pcall(CM and CM.GetMapTable)
    maps = okMaps and plain(maps) or nil
    if type(maps) == "table" then mapID = num(maps[1]) end
    if mapID then mapName, limit = mapInfo(mapID) end
    limit = (limit and limit > 0) and limit or TEST_LIMIT

    key.mapID, key.mapName, key.level = mapID, mapName, TEST_LEVEL
    key.depleted = test.late
    key.deaths, key.timeLost = TEST_DEATHS, TEST_LOST

    local ids = TEST_AFFIXES
    local okA, current = pcall(C_MythicPlus and C_MythicPlus.GetCurrentAffixes)
    current = okA and plain(current) or nil
    if type(current) == "table" and #current > 0 then
        ids = {}
        for i = 1, #current do
            local c = current[i]
            ids[#ids + 1] = type(c) == "table" and c.id or c
        end
    end
    readAffixes(ids)

    setLimit(limit)
    if not test.start then
        test.start = test.late and (limit - TEST_LATE_LEAD) or (key.plusThree - TEST_LEAD)
        test.stamp = GetTime()
    end
    key.elapsed, key.elapsedAt = test.start, test.stamp
    key.active = true
    return key
end

function Keystone:SetTest(mode)
    if mode == "test" or mode == "late" then
        test = { late = (mode == "late") }
    else
        test = nil
    end
    return test ~= nil
end

function Keystone:IsTesting()
    return test ~= nil
end

function Keystone:TestMode()
    if not test then return nil end
    return test.late and "late" or "test"
end

-- A start rebases the clock, as Blizzard's StartTimer does, even when the figure read matches
-- the last reading
function Keystone:TimerStarted(id)
    id = num(id)
    if id then stopped[id] = nil end
    lastElapsed = nil
end

function Keystone:TimerStopped(id)
    id = num(id)
    if id then stopped[id] = true end
end

-- A new key or a loading screen. Blizzard checks its timers again on both and trusts the list,
-- so the stops this session has seen are forgotten and the clock is rebased.
function Keystone:Started()
    wipe(stopped)
    lastElapsed = nil
end

-- A backup for WORLD_STATE_TIMER_STOP: a finished or reset run must not keep counting on
-- screen if that event never arrives.
function Keystone:Finished()
    if lastTimerID then stopped[lastTimerID] = true end
end

function Keystone:DebugLine()
    if not ns.Has.ChallengeTimer then return "mythic+: not on this client" end
    if not key.active then
        return ("mythic+: %s%s"):format(note or "no key running",
            secretField and (" | secret: " .. secretField) or "")
    end
    local ids = {}
    for i = 1, key.affixN do ids[i] = tostring(key.affixes[i].id) end
    local elapsed = key.elapsed or 0
    if key.elapsedAt then elapsed = elapsed + (GetTime() - key.elapsedAt) end
    return ("mythic+: %s+%s %s (map %s) | timer %s, %ds of %ds, +2 by %ds, +3 by %ds | deaths %d, %ds lost | affixes %s | depleted %s%s"):format(
        key.test and "TEST " or "", tostring(key.level), tostring(key.mapName),
        tostring(key.mapID), key.test and "none" or tostring(lastTimerID),
        math.floor(elapsed), key.timeLimit or 0,
        math.floor(key.plusTwo or 0), math.floor(key.plusThree or 0),
        key.deaths or 0, key.timeLost or 0,
        key.affixN > 0 and table.concat(ids, ",") or "none",
        key.depleted and "yes" or "no",
        secretField and (" | secret: " .. secretField) or "")
end
