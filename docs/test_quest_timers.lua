-- Unit tests for the Classic timed-quest countdown, run against the SHIPPED source rather than
-- a copy. Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_quest_timers.lua
--
-- WHY THIS FILE EXISTS. Blizzard draws a floating QuestTimerFrame for any timed quest, a THIRD
-- frame that is a sibling of neither tracker, so an Era escort quest gave a stray Blizzard timer
-- box beside an EQOT row that said nothing about the timer. UI/Blizzard.lua hides that frame
-- now, which makes the countdown on the row the ONLY timer a Classic player has - so the two
-- halves ship together and this file is what holds the reading half to that bargain.
--
-- Three pieces, in three files, and the seam between them is where the bugs would be:
--   * Data/Providers/QuestsClassic.lua reads GetQuestTimers, the pair Blizzard's own frame
--     reads, and stamps entry.expiresAt
--   * Core/Util.lua formats it, and the sub-minute case is the whole point: flooring to whole
--     minutes draws NOTHING through the last 59 seconds, which is the stretch a countdown is for
--   * UI/Tracker.lua picks the tick rate from the soonest deadline, so a seconds readout is not
--     half a minute stale
--
-- The frame-hiding half is covered by docs/test_blizzard.lua, which loads UI/Blizzard.lua whole.
--
-- Neither UI/Tracker.lua nor Data/Providers/QuestsClassic.lua can be loaded whole without the
-- game, so both are sliced out by TEXT ANCHORS rather than line numbers, which drift. If an
-- anchor stops matching, fix the anchor here rather than deleting the test.
--
-- The row's own countdown block is sliced in as a fourth piece, because the COLOR is derived
-- there rather than in Util: Row floors the seconds remaining to whole minutes and hands that to
-- Util.TimeColor, whose first band means no time LEFT and is a different color from the urgent
-- one below it. Five separate ways of breaking that derivation - timeMins pinned to zero among
-- them, which draws every timed row on both flavors in the expired color - left all 22 harnesses
-- in this tree green, so the floor, the clamp and the five bands are driven here now.
--
-- OUT OF SCOPE BY CONSTRUCTION: how the row DRAWS what it computed. UI/Row.lua's timer
-- FontString, its anchoring and its repaint gate are reached by no assertion here.

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
end

local function readFile(rel)
    local fh = assert(io.open(repoFile(rel), "r"))
    local s = fh:read("*a")
    fh:close()
    return s
end

local function slicer(path)
    local src = readFile(path)
    return function(fromAnchor, toAnchor)
        local from = src:find(fromAnchor, 1, true)
        local to   = src:find(toAnchor, 1, true)
        assert(from, "anchor not found in " .. path .. ": " .. fromAnchor)
        assert(to,   "anchor not found in " .. path .. ": " .. toAnchor)
        assert(to > from, "anchors are out of order in " .. path .. ": " .. fromAnchor)
        return src:sub(from, to - 1)
    end, src
end

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end

-- Every call into a slice below goes through a helper that pcalls it and asserts on the result.
-- A mutant that makes the code under test RAISE has to FAIL a case rather than abort the file:
-- every battery in this tree reads a missing summary line as a mutant that SURVIVED, so an
-- unprotected call reports a crash as a coverage hole. Helpers answer this rather than nil on a
-- raise, because an assertion written `== false` would pass against a nil.
local RAISED = "RAISED"

-- ===================================================================== the provider's reader

local sliceProvider = slicer("Data/Providers/QuestsClassic.lua")
local readerSrc = sliceProvider("local timerSecs = {}",
                                "-- isComplete arrives nil while in progress")

local pchunk = assert(loadstring(readerSrc .. "\nreturn readTimers, fillTimer",
                                 "quest-timers-slice"))

local NOW = 10000

local hasTimers          -- what ns.Has.QuestTimers answers
local timerValues        -- what GetQuestTimers returns, in slot order
local indexForSlot       -- slot -> quest log index
local calls
local raiseTimers, raiseIndex, raiseValue

local penv = setmetatable({
    ns = setmetatable({}, { __index = function(_, k)
        if k == "Has" then return { QuestTimers = hasTimers } end
    end }),
    time = function() return NOW end,
    wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
    -- Raises on a slot that is not a number, the way a client API does rather than politely
    -- answering nil. A forgiving stub would let the type guard be deleted with the file green.
    GetQuestIndexForTimer = function(slot)
        calls.index = calls.index + 1
        if type(slot) ~= "number" then error("bad timer slot", 0) end
        if raiseIndex then error("GetQuestIndexForTimer raised", 0) end
        return indexForSlot[slot]
    end,
    GetQuestTimers = function()
        calls.timers = calls.timers + 1
        if raiseTimers then error(raiseValue or "GetQuestTimers raised", 0) end
        return unpack(timerValues)
    end,
}, { __index = _G })

setfenv(pchunk, penv)
local readTimers, fillTimer = pchunk()
assert(type(readTimers) == "function", "the slice defined no readTimers")
assert(type(fillTimer)  == "function", "the slice defined no fillTimer")

local function reset(opts)
    opts         = opts or {}
    hasTimers    = opts.hasTimers ~= false
    timerValues  = opts.timers or {}
    indexForSlot = opts.indexes or {}
    raiseTimers  = opts.raiseTimers or false
    raiseValue   = opts.raiseValue
    raiseIndex   = opts.raiseIndex or false
    calls        = { timers = 0, index = 0 }
end

-- Protected, and the result asserted, because a mutant that makes the slice RAISE would
-- otherwise kill this file before its summary line - and every battery in this tree reads a
-- missing summary as a SURVIVOR, so the crash would report as a coverage hole instead.
local function read()
    local okCall, res = pcall(readTimers)
    ok(okCall, "readTimers did not raise")
    return okCall and res or {}
end

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- fillTimer is the other half of the same slice, and it indexes the table readTimers hands back,
-- so a mutant that drops its guard raises rather than stamping the wrong deadline.
local function fill(e, timers, index)
    local okCall, err = pcall(fillTimer, e, timers, index)
    ok(okCall, "fillTimer does not raise" .. (okCall and "" or (" - " .. tostring(err))))
    return e
end

-- ---- the slot to log-index mapping, which is the load-bearing arithmetic ----
-- GetQuestTimers answers one value per RUNNING timer, and slot N of that return corresponds to
-- GetQuestIndexForTimer(N). Getting that off by one would read a real number against the wrong
-- quest, which draws a confident countdown on a quest that has none.
reset({ timers = { 300, 45 }, indexes = { [1] = 7, [2] = 3 } })
local map = read()
ok(map[7] == 300, "slot 1 maps to its own quest log index")
ok(map[3] == 45,  "slot 2 maps to its own quest log index")
ok(count(map) == 2, "two running timers produce exactly two entries")
ok(calls.timers == 1, "GetQuestTimers is asked once per read")
ok(calls.index == 2, "GetQuestIndexForTimer is asked once per running timer")

-- Deliberately asserts the WRONG pairing does not hold, because a same-valued fixture would
-- pass whichever way round the mapping went.
ok(map[3] ~= 300, "the second slot did not take the first slot's seconds")

-- ---- no timers at all, which is the overwhelmingly common case ----
reset({ timers = {} })
map = read()
ok(count(map) == 0, "a log with no running timer produces no entries")
ok(calls.index == 0, "no quest log index is asked for when nothing is running")

-- ---- the client's documented return shape, which is STRINGS of seconds ----
-- Both shipped Classic flavors document this API as answering strings, Blizzard's own frame
-- never type-tests it (it coerces through SecondsToTime), and no reading of a real running
-- timer has settled it either way. Both values therefore go through tonumber. A numeric
-- fixture alone cannot tell that apart from the type test it replaced, which is why these
-- cases exist: refusing a real timer here costs a countdown while the frame is already hidden.
reset({ timers = { "300", "45" }, indexes = { [1] = 7, [2] = 3 } })
map = read()
ok(map[7] == 300, "a STRING seconds value is accepted, and arrives as a number")
ok(map[3] == 45,  "and so does the second slot's")
ok(count(map) == 2, "a string return produces the same two entries a numeric one does")

reset({ timers = { "300" }, indexes = { [1] = "7" } })
map = read()
ok(map[7] == 300, "a STRING quest log index keys the table numerically")
ok(map["7"] == nil, "and leaves no string key, which the walk's numeric index could never match")

-- tonumber is the guard the type test used to be, so anything that is not a number and cannot
-- become one must still be refused rather than reaching the arithmetic below it.
reset({ timers = { {}, "abc", "60" }, indexes = { [1] = 5, [2] = 6, [3] = 9 } })
map = read()
ok(map[9] == 60, "a real timer beside a table and a non-numeric string is still taken")
ok(count(map) == 1, "and neither junk value produced an entry")

-- ---- the capability gate ----
reset({ hasTimers = false, timers = { 300 }, indexes = { [1] = 7 } })
map = read()
ok(count(map) == 0, "the reader answers empty when GetQuestTimers is absent")
ok(calls.timers == 0, "and reaches no client call at all on such a client")

-- ---- the reused table is WIPED, not appended to ----
-- A stale index surviving a read is a countdown on a quest whose timer has ended.
reset({ timers = { 300 }, indexes = { [1] = 7 } })
read()
timerValues, indexForSlot = { 60 }, { [1] = 2 }
map = read()
ok(map[7] == nil, "an index from the previous read does not survive the next one")
ok(map[2] == 60,  "and the current read is present")
ok(count(map) == 1, "exactly one entry after the second read")

-- ---- refusals ----
reset({ timers = { 0, -5, "soon", 120 }, indexes = { [1] = 1, [2] = 2, [3] = 3, [4] = 4 } })
map = read()
ok(map[1] == nil, "a zero-second timer is refused")
ok(map[2] == nil, "a negative timer is refused")
ok(map[3] == nil, "a non-number timer value is refused")
ok(map[4] == 120, "and a real timer beside them is still taken")

reset({ timers = { 300, 300 }, indexes = { [1] = 0, [2] = 5 } })
map = read()
ok(map[0] == nil, "a quest log index of 0 is refused")
ok(map[5] == 300, "a real index beside it is still taken")

reset({ timers = { 300 }, indexes = {} })
map = read()
ok(count(map) == 0, "a slot the client cannot name an index for is dropped")

-- ---- a raise costs nothing ----
-- This runs inside GetEntries, so a raise here would cost the whole render rather than the
-- countdown, which is the trap this project has recorded on the delve model.
reset({ raiseTimers = true, timers = { 300 }, indexes = { [1] = 7 } })
local okRead, res = pcall(readTimers)
ok(okRead, "a raising GetQuestTimers does not escape the reader")
ok(okRead and count(res) == 0, "and produces no entries")

-- pcall's SECOND return is the error value, and a numeric one is indistinguishable from a
-- timer once the ok flag is ignored. With a string error, which is what a client actually
-- raises, the type guard below refuses it either way and dropping the ok test is invisible.
reset({ raiseTimers = true, raiseValue = 300, timers = {}, indexes = { [1] = 7 } })
map = read()
ok(count(map) == 0, "a raise's own error value is not mistaken for a running timer")
ok(calls.index == 0, "and no quest log index is asked for after a raise")

reset({ raiseIndex = true, timers = { 300, 300 }, indexes = { [1] = 7, [2] = 8 } })
okRead, res = pcall(readTimers)
ok(okRead, "a raising GetQuestIndexForTimer does not escape the reader")
ok(okRead and count(res) == 0, "and drops the slots it could not name")

-- ---- fillTimer stamps an ABSOLUTE deadline ----
reset({ timers = { 300 }, indexes = { [1] = 7 } })
map = read()
local e = fill({}, map, 7)
ok(e.expiresAt == NOW + 300, "expiresAt is the current time plus the seconds remaining")

-- ---- the pooled-entry case, which is the one that would ship as a bug ----
-- Entries are pooled and handed out again, so a quest whose timer has ENDED inherits whatever
-- the previous occupant of that table left behind unless the field is assigned every pass.
e = fill({ expiresAt = NOW + 999 }, map, 4)
ok(e.expiresAt == nil, "a quest with no running timer clears a pooled entry's old deadline")

e = fill({ expiresAt = NOW + 999 }, map, nil)
ok(e.expiresAt == nil, "and so does a quest with no quest log index at all")

e = fill({ expiresAt = NOW + 999 }, map, 7)
ok(e.expiresAt == NOW + 300, "a quest that still has a timer is restamped rather than left")

-- ===================================================================== the formatter

-- Loaded WHOLE rather than sliced: Core/Util.lua creates no frame and calls no quest API at
-- file scope, so a namespace table is a complete stand-in.
local uchunk = assert(loadfile(repoFile("Core/Util.lua")))
local uns = {
    RegisterModule = function(self, name, tbl) self[name] = tbl return tbl end,
}
local uenv = setmetatable({}, { __index = _G })
setfenv(uchunk, uenv)
uchunk("EQObjectiveTracker", uns)
local Util = uns.Util
assert(type(Util) == "table", "Core/Util.lua defined no ns.Util")
assert(type(Util.TimeShortSecs) == "function", "Core/Util.lua defined no TimeShortSecs")
assert(type(Util.TimeColor) == "function", "Core/Util.lua defined no TimeColor")

-- A nil reaches all three of these on a real render, so a mutant that drops a nil guard raises
-- rather than answering wrongly.
local function guarded(fn, name)
    return function(v)
        local okCall, out = pcall(fn, v)
        ok(okCall, name .. " does not raise" .. (okCall and "" or (" - " .. tostring(out))))
        -- Written as an if rather than `okCall and out or RAISED`, which can never yield a
        -- FALSE or nil answer - the and/or trap this project has already paid for once.
        if not okCall then return RAISED end
        return out
    end
end
local secs = guarded(Util.TimeShortSecs, "TimeShortSecs")
local mins = guarded(Util.TimeShort,     "TimeShort")

-- The case the whole change exists for. Before it, Row floored to whole minutes and drew an
-- EMPTY string through the last 59 seconds of a quest timer - and with Blizzard's own frame
-- now hidden, that stretch would have had no timer on screen anywhere.
ok(secs(59) == "59s", "59 seconds left reads as seconds, not as nothing")
ok(secs(1)  == "1s",  "one second left still reads")
ok(mins(math.floor(59 / 60)) == "",
   "which is exactly what the minutes formatter alone could not do")

ok(secs(60)  == "1m", "a full minute crosses to the minutes form")
ok(secs(119) == "1m", "and rounds down inside that minute")
ok(secs(300) == "5m", "five minutes reads as minutes")
ok(secs(3600) == "1h", "an hour delegates to the hours form")
ok(secs(86400) == "1d", "a day delegates to the days form")

ok(secs(0)   == "", "an expired timer formats to nothing")
ok(secs(-30) == "", "and so does one already past")
ok(secs(nil) == "", "and a missing value does not raise")

-- The world quest path is unchanged, which is what keeps this additive: TimeShort still takes
-- MINUTES and still answers exactly what it always did.
ok(mins(90) == "1h", "TimeShort still reads its argument as minutes")

-- ===================================================================== the countdown's color

-- TimeColor is what tints the countdown, and it takes MINUTES. Its five bands had no assertion
-- anywhere in this tree, so any of them could be widened, narrowed or swapped outright with
-- every harness green. The first band is the one that matters most: it is the color for no time
-- LEFT rather than for very little of it, and the row's clamp exists to keep a live sub-minute
-- countdown out of it.
local function band(m)
    local okCall, r, g, b = pcall(Util.TimeColor, m)
    ok(okCall, "TimeColor does not raise" .. (okCall and "" or (" - " .. tostring(r))))
    if not okCall then return RAISED end
    return ("%.2f,%.2f,%.2f"):format(r, g, b)
end

-- Written as literals rather than read back off the function under test. An expected value taken
-- FROM the code under test passes at every value that code could possibly return, which is a
-- defect a battery has already caught in this tree once.
local EXPIRED, URGENT, SOON, LATER, PLENTY =
    "1.00,0.10,0.10", "1.00,0.25,0.25", "1.00,0.65,0.10", "1.00,1.00,0.40", "0.50,1.00,0.50"

ok(EXPIRED ~= URGENT,
   "the expired color and the urgent one are genuinely different, or the row's clamp buys nothing")

ok(band(0) == EXPIRED, "no time left has a color of its own")
ok(band(-5) == EXPIRED, "and so does a deadline already past")
ok(band(nil) == EXPIRED, "and a missing value falls to it rather than raising")

-- Each band is read at both ends, because a single reading inside one passes against a boundary
-- moved either way.
ok(band(1) == URGENT, "one minute left is urgent, which is NOT the expired color")
ok(band(29) == URGENT, "and the last minute of that band still is")
ok(band(30) == SOON, "thirty minutes crosses into the next band")
ok(band(119) == SOON, "which runs to just under two hours")
ok(band(120) == LATER, "two hours crosses again")
ok(band(719) == LATER, "and that band runs to just under twelve")
ok(band(720) == PLENTY, "twelve hours or more is the calmest band")
ok(band(99999) == PLENTY, "however far away the deadline is")

-- ============================================================== the row's own derivation

-- The color above is only ever as good as the number handed to it, and that number is derived in
-- UI/Row.lua rather than in Util. Sliced out here because the COMPOSITION is where the bug was:
-- the text moved to seconds resolution and the color stayed at whole minutes, so a live
-- countdown drew in the expired color for its entire last minute - a window that drew nothing at
-- all before this feature existed, which is why nobody had ever seen it.
local sliceRow = slicer("UI/Row.lua")
local rowBlock = sliceRow("    local timeText, timeMins", '    local Card = ns:GetModule("Card")')

local rchunk = assert(loadstring(
    "local entry, Util, time = ...\n" .. rowBlock .. "\nreturn timeText, timeMins",
    "row-countdown-slice"))

-- Answers the pair the row goes on to draw with, and the color that pair resolves to, so the
-- two halves are asserted together rather than each against its own fixture.
local function countdown(expiresAt)
    local okCall, text, m = pcall(rchunk, { expiresAt = expiresAt }, Util,
                                  function() return NOW end)
    ok(okCall, "the row's countdown block does not raise"
       .. (okCall and "" or (" - " .. tostring(text))))
    if not okCall then return { text = RAISED, mins = RAISED, color = RAISED } end
    return { text = text, mins = m, color = m ~= nil and band(m) or nil }
end

local halfMin = countdown(NOW + 30)
ok(halfMin.text == "30s", "half a minute out draws a seconds countdown")
ok(halfMin.mins == 1, "and clamps to one minute rather than flooring to zero")
ok(halfMin.color == URGENT, "so it takes the urgent color, not the one for no time left")

local oneSec = countdown(NOW + 1)
ok(oneSec.text == "1s", "one second out still draws")
ok(oneSec.mins == 1, "and is still clamped")
ok(oneSec.color == URGENT, "and still reads as running rather than as expired")

local lastMin = countdown(NOW + 59)
ok(lastMin.mins == 1, "the far end of the last minute is clamped too")
ok(lastMin.color == URGENT, "so no part of that minute draws in the expired color")

-- Above a minute the clamp must not fire, or every timed row on the tracker takes one color.
local oneMin = countdown(NOW + 60)
ok(oneMin.text == "1m", "a full minute crosses to the minutes form")
ok(oneMin.mins == 1, "and reads one minute")

local anHour = countdown(NOW + 3600)
ok(anHour.mins == 60, "an hour out is sixty minutes, not one")
ok(anHour.color == SOON, "and takes its own band rather than the urgent one")

-- Every fixture above is a whole number of minutes, so floor and ceil agree on all of them and
-- swapping one for the other survived this file green. These two are the ones that discriminate,
-- and the second is why it matters rather than being a tidiness point: rounding UP inside the
-- last minute of a band moves the row into the NEXT band, so a quest 29 minutes and 59 seconds
-- out would stop being drawn as urgent a whole minute early.
local partMin = countdown(NOW + 90)
ok(partMin.text == "1m", "a minute and a half reads as one minute")
ok(partMin.mins == 1, "and floors to one rather than rounding up to two")

local bandEdge = countdown(NOW + 1799)
ok(bandEdge.mins == 29, "one second under thirty minutes floors to twenty-nine")
ok(bandEdge.color == URGENT, "so it is still drawn urgent, rather than rounding into the next band")

local aDay = countdown(NOW + 86400)
ok(aDay.mins == 1440, "a day out is a day's worth of minutes")
ok(aDay.color == PLENTY, "and takes the calmest band")

-- An expired deadline draws nothing at all, and the row hides the FontString on a nil text.
local justGone = countdown(NOW)
ok(justGone.text == nil, "a deadline exactly now draws no countdown")
ok(justGone.mins == 0, "and is not clamped, because the clamp is for LIVE countdowns only")
ok(justGone.color == EXPIRED, "so it would tint expired, which is what that band is for")

local longGone = countdown(NOW - 300)
ok(longGone.text == nil, "and neither does one long past")
ok(longGone.mins == -5, "whose minutes value goes negative rather than being clamped up")

local noDeadline = countdown(nil)
ok(noDeadline.text == nil, "a row with no deadline draws nothing")
ok(noDeadline.mins == nil, "and derives no minutes at all, so the row never tints it")

-- ===================================================================== the tick rate

local sliceTracker = slicer("UI/Tracker.lua")
local tickerSrc = sliceTracker("local TICK_SLOW, TICK_FAST, FAST_WINDOW",
                               "-- Records intent and lets Visibility do the painting")

local cancels, created
local FakeTicker = {}
FakeTicker.__index = FakeTicker
function FakeTicker:Cancel() cancels = cancels + 1 self.canceled = true end

-- ns.Has.QuestLog is the tree's standing Classic-quest-log test, and the fast rate is gated on
-- its absence, so this stub is what lets the cases below drive BOTH flavors.
local hasQuestLog = false
local tenv = setmetatable({
    Tracker = {},
    ns = setmetatable({}, { __index = function() return { QuestLog = hasQuestLog } end }),
    time = function() return NOW end,
    C_Timer = {
        NewTicker = function(interval)
            created[#created + 1] = interval
            return setmetatable({ interval = interval }, FakeTicker)
        end,
    },
}, { __index = _G })

local tchunk = assert(loadstring(tickerSrc .. "\nreturn Tracker, TICK_SLOW, TICK_FAST, FAST_WINDOW",
                                 "ticker-slice"))
setfenv(tchunk, tenv)
local Tracker, TICK_SLOW, TICK_FAST, FAST_WINDOW = tchunk()
assert(type(Tracker._EnsureTimerTicker) == "function", "the slice defined no _EnsureTimerTicker")

-- Written as literals rather than read back out of the slice. An assertion that takes its
-- expected value FROM the constant under test passes at every value of that constant, which is
-- the defect a battery caught in this tree once already.
ok(TICK_SLOW == 30,   "the slow tick is 30 seconds")
ok(TICK_FAST == 5,    "the fast tick is 5 seconds")
ok(FAST_WINDOW == 90, "the fast window is the last 90 seconds")

local function freshTicker()
    cancels, created = 0, {}
    return {}
end

-- _EnsureTimerTicker is the call most likely to abort this file: it indexes ns.Has and reaches
-- into C_Timer, so a mutant that drops either raises rather than choosing the wrong rate.
local function tick(T, wanted, soonest)
    local okCall, err = pcall(Tracker._EnsureTimerTicker, T, wanted, soonest)
    ok(okCall, "_EnsureTimerTicker does not raise"
       .. (okCall and "" or (" - " .. tostring(err))))
end

-- ---- nothing timed on screen ----
local T = freshTicker()
tick(T, false, nil)
ok(#created == 0, "no ticker is created while nothing on screen has a deadline")
ok(T._timerTicker == nil, "and none is stored")

-- ---- a distant deadline takes the slow rate ----
T = freshTicker()
tick(T, true, NOW + 3600)
ok(#created == 1 and created[1] == 30, "an hour away ticks at 30 seconds")

-- ---- and stays there rather than rebuilding on every render ----
-- The rate is compared against the rate the LIVE ticker was created with. Comparing against the
-- request instead would cancel and rebuild the ticker on every single render.
tick(T, true, NOW + 3599)
tick(T, true, NOW + 3598)
ok(#created == 1, "a second render at the same rate creates no second ticker")
ok(cancels == 0,  "and cancels nothing")

-- ---- crossing into the last 90 seconds speeds up, once ----
T = freshTicker()
tick(T, true, NOW + 300)
ok(created[1] == 30, "five minutes out is still the slow rate")
tick(T, true, NOW + 89)
ok(#created == 2 and created[2] == 5, "inside the window it drops to the fast rate")
ok(cancels == 1, "and the slow ticker is canceled rather than left running beside it")
tick(T, true, NOW + 40)
tick(T, true, NOW + 10)
ok(#created == 2, "two more renders inside the window create no further tickers")
ok(cancels == 1, "and cancel nothing")

-- ---- the boundary, from both sides ----
T = freshTicker()
tick(T, true, NOW + 90)
ok(created[1] == 5, "exactly 90 seconds out is already the fast rate")
T = freshTicker()
tick(T, true, NOW + 91)
ok(created[1] == 30, "and 91 seconds out is still the slow one")

-- ---- the row going away stops it ----
T = freshTicker()
tick(T, true, NOW + 30)
ok(created[1] == 5, "a timed row inside the window ticks fast")
tick(T, false, nil)
ok(cancels == 1, "the ticker is canceled when the last timed row goes")
ok(T._timerTicker == nil, "and the handle is dropped")
tick(T, false, nil)
ok(cancels == 1, "a second render with nothing timed cancels nothing further")

-- ---- retail never takes the fast rate, because it can never show a seconds countdown ----
-- expiresAt is re-stamped from whole minutes on every render there, so the label reads the
-- same at 5s as at 30s and the faster tick is pure render cost.
hasQuestLog = true
T = freshTicker()
tick(T, true, NOW + 40)
ok(created[1] == 30, "a retail deadline inside the window still takes the slow rate")
T = freshTicker()
tick(T, true, NOW + 10)
ok(created[1] == 30, "and so does one about to expire")
hasQuestLog = false

-- ---- an expired deadline still on screen takes the fast rate, not the slow one ----
T = freshTicker()
tick(T, true, NOW - 10)
ok(created[1] == 5, "a deadline already past is inside the window rather than outside it")

-- ---- a timed row with NO deadline resolved falls back to the slow rate ----
-- wanted true with soonest nil is reachable: noteExpiry feeds both, but a provider could set
-- hasTimed through a path that never recorded one, and 30 seconds is the safe answer there.
T = freshTicker()
tick(T, true, nil)
ok(created[1] == 30, "a timed row with no resolved deadline takes the slow rate")

-- ===================================================================== the soonest deadline

-- noteExpiry sits well above the ticker and outside its slice, so until this block existed
-- both its comparison and its return value were deletable with this file green. Flipping the
-- comparison hands the ticker the LATEST deadline, which drops a seconds countdown back to a
-- 30 second redraw - the exact staleness TimeShortSecs exists to prevent.
local noteSrc = sliceTracker("local soonestExpiry",
                             "function Tracker:_RenderPinnedWorldQuests")

local nchunk = assert(loadstring(
    noteSrc .. "\nreturn noteExpiry, function() return soonestExpiry end," ..
               " function() soonestExpiry = nil end", "note-slice"))
setfenv(nchunk, setmetatable({}, { __index = _G }))
local noteExpiry, soonest, resetSoonest = nchunk()
assert(type(noteExpiry) == "function", "the slice defined no noteExpiry")

-- The if is load-bearing here rather than stylistic: noteExpiry answers FALSE for a row with
-- no deadline, and `okCall and res or RAISED` turns that into the sentinel, which failed a
-- correct build on this file's first run.
local function note(entry)
    local okCall, out = pcall(noteExpiry, entry)
    ok(okCall, "noteExpiry does not raise" .. (okCall and "" or (" - " .. tostring(out))))
    if not okCall then return RAISED end
    return out
end

resetSoonest()
ok(note({}) == false, "a row with no deadline is not a timed row")
ok(soonest() == nil, "and records nothing")

ok(note({ expiresAt = NOW + 500 }) == true, "a row with a deadline is a timed row")
ok(soonest() == NOW + 500, "and records it")

-- The order matters in both directions, or a single case passes with the comparison flipped.
note({ expiresAt = NOW + 20 })
ok(soonest() == NOW + 20, "a nearer deadline replaces a farther one")
note({ expiresAt = NOW + 9000 })
ok(soonest() == NOW + 20, "and a farther one does not replace a nearer one")

-- The pairing the ticker actually consumes: a Classic quest timer beside a world quest.
resetSoonest()
note({ expiresAt = NOW + 18000 })
note({ expiresAt = NOW + 20 })
T = freshTicker()
tick(T, true, soonest())
ok(created[1] == 5, "a quest timer beside a world quest still takes the fast rate")

resetSoonest()
ok(soonest() == nil, "the reset clears it, or it could only ever fall")

-- ===================================================================== the wiring

-- Everything above slices one function out of three files, so all of it passes with the feature
-- switched off at the seams BETWEEN them. These are those seams. Greps rather than assertions
-- because driving them needs the game, and each one is a place where the halves could be
-- individually correct and jointly useless - which is the shape this project has recorded
-- against itself more than once.

local _, providerSrc = slicer("Data/Providers/QuestsClassic.lua")
local _, trackerSrc  = slicer("UI/Tracker.lua")
local _, rowSrc      = slicer("UI/Row.lua")

local function has(src, needle, msg)
    ok(src:find(needle, 1, true) ~= nil, msg)
end

-- Both provider paths must stamp it. The full rebuild is where a newly accepted timed quest
-- arrives, and the dynamic path is where a timer STARTING on a quest already in the log does,
-- and that is the commoner of the two.
local fillCalls = select(2, providerSrc:gsub("fillTimer%(e, timers, i%)", ""))
ok(fillCalls == 2, "both quest log paths stamp the deadline, not just the full rebuild")
-- COUNTED, not merely present: neutering one of the two to `local timers = {}` leaves this
-- grep matching and switches the countdown off on that path with every harness green. luacheck
-- catches an outright deletion (timers becomes an undefined global) and not this.
local readCalls = select(2, providerSrc:gsub("local timers = readTimers%(%)", ""))
ok(readCalls == 2, "both quest log paths READ the timer table, not just the full rebuild")

-- The row has to ask for the SECONDS form. Left on TimeShort it floors to whole minutes and
-- draws nothing through the last 59 seconds, which is the regression this change exists to
-- avoid now that Blizzard's own frame is hidden.
has(rowSrc, "Util.TimeShortSecs(secs)", "the row formats the countdown in seconds")
ok(rowSrc:find("if secs > 0 then", 1, true) ~= nil,
   "and shows it while any time at all remains, not only whole minutes")
ok(rowSrc:find("if timeMins > 0 then", 1, true) == nil,
   "and the whole-minutes gate it replaced is gone")

-- The color is taken from the same countdown the text is. TimeColor treats zero as no
-- time LEFT, a different color from its urgent band, so a live sub-minute row would
-- otherwise draw in the expired color for the whole stretch this feature exists for.
ok(rowSrc:find("if timeMins < 1 then timeMins = 1 end", 1, true) ~= nil,
   "a live countdown under a minute is not colored as an expired one")

-- The tick rate is chosen from the soonest deadline, so the deadline has to reach it.
has(trackerSrc, "self:_EnsureTimerTicker(hasTimed, soonestExpiry)",
    "the soonest deadline is handed to the ticker rather than only a boolean")
-- By OFFSET rather than presence, because the message above used to assert an ordering it
-- never checked: moved below the loops the reset still greps clean, soonestExpiry is nil by the
-- time the ticker reads it, and the 5 second rate can never be entered at all. The battery
-- cannot express a MOVE as one edit, so this is the assertion that closes it.
-- Every offset is taken from the start of Render, because the pinned region's own noteExpiry
-- is written 200 lines ABOVE the reset and runs 70 lines below it - lexical position is not
-- execution order once a helper is involved, and a whole-file search reads the wrong one.
local renderAt = trackerSrc:find("function Tracker:Render()", 1, true)
ok(renderAt ~= nil, "Render is found")
local resetAt  = renderAt and trackerSrc:find("soonestExpiry  = nil", renderAt, true)
local loopNote = renderAt and trackerSrc:find("if noteExpiry(entry) then", renderAt, true)
local pinnedAt = renderAt and trackerSrc:find("self:_RenderPinnedWorldQuests(", renderAt, true)
local tickerAt = trackerSrc:find("self:_EnsureTimerTicker(hasTimed, soonestExpiry)", 1, true)
ok(resetAt ~= nil, "the soonest deadline is reset inside Render")
ok(resetAt and loopNote and resetAt < loopNote,
   "before Render's own loop feeds it, or it only ever falls")
ok(resetAt and pinnedAt and resetAt < pinnedAt,
   "and before the pinned region, which feeds it from a helper")
ok(loopNote and pinnedAt and tickerAt and loopNote < tickerAt and pinnedAt < tickerAt,
   "and both feeders run before the ticker reads it")
-- Anchored on the CALL rather than the bare name, which also matches the definition. Counting
-- that too read 3 where 2 was meant and failed a correct build - the same shape as the grep in
-- test_quest_link.lua that a comment naming its own binding once tripped.
local noteCalls = select(2, trackerSrc:gsub("if noteExpiry%(entry%) then", ""))
ok(noteCalls == 2, "both render loops feed the soonest deadline")

-- The capability flag itself. Both names are BARE GLOBALS with no C_QuestLog twin, and the six
-- surrounding lines in Core/Compat.lua are all method(C_QuestLog, ...) - so the wrong edit is
-- the locally idiomatic one, it reads false on every client forever, and it takes the
-- suppression and the countdown with it. The identical swap shipped in v1.22.0.
local _, compatSrc = slicer("Core/Compat.lua")
has(compatSrc,
    'Has.QuestTimers         = global("GetQuestTimers") and global("GetQuestIndexForTimer")\n',
    "the timer capability probes both bare globals, and is anchored on the line ending")

-- The one instrument that says whether the suppression resolved, and the only way to tell a
-- Classic refusal from a retail no-op. Deletable from the status dump with every suite green.
local _, cmdSrc = slicer("UI/Commands.lua")
has(cmdSrc, 'debugLine("Blizzard", nil, "QuestTimerLine")',
    "the quest timer line is printed by /eqot status")

print(("test_quest_timers: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
