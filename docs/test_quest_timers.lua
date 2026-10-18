-- Unit tests for the timed-quest countdown, Classic and retail, run against the SHIPPED source
-- rather than a copy. Run from the repo root with the game's own Lua version:
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
-- RETAIL AND WOW FOREVER (2026-10-16, reported by frkstram). Retail never drew a countdown for a
-- timed quest: Blizzard's own tracker draws it as a bar, and this addon hides that tracker.
-- Data/Providers/Quests.lua now reads C_QuestLog.GetTimeAllowed, the pair that bar is drawn
-- from, and /eqot timer test lays a two-minute sample over one quest. Its reader, the sample's
-- toggle and its status line are sliced together over the REAL Data/Entry.lua store, and the
-- command's branch is sliced out of UI/Commands.lua and driven. The fast tick is no longer
-- gated to Classic, since a retail quest timer counts its last minute in seconds too. The row
-- tooltip's faction and Time Left lines (UI/RewardTooltip.lua) are sliced in and driven as well.
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

-- ns.Has.QuestLog is the tree's standing Classic-quest-log test. The fast rate was once gated on
-- its absence, so this stub drives BOTH flavors to hold that it no longer is.
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

-- ---- retail takes the fast rate too, since its quest log timers count seconds ----
-- It was refused there while retail's only deadlines were world quests stamped in whole minutes.
hasQuestLog = true
T = freshTicker()
tick(T, true, NOW + 40)
ok(created[1] == 5, "a retail deadline inside the window takes the fast rate")
T = freshTicker()
tick(T, true, NOW + 10)
ok(created[1] == 5, "and so does one about to expire")
T = freshTicker()
tick(T, true, NOW + 91)
ok(created[1] == 30, "while one outside the window keeps the slow rate")
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

-- ===================================================================== the retail reader

local entryMod
do
    local echunk = assert(loadfile(repoFile("Data/Entry.lua")))
    setfenv(echunk, setmetatable({
        wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
        CopyTable = function(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end,
    }, { __index = _G }))
    echunk("EQObjectiveTracker", { RegisterModule = function(_, _, m) entryMod = m return m end })
end
assert(entryMod and entryMod.STATE and entryMod.NewStore, "Data/Entry.lua defined STATE and NewStore")
local STATE = entryMod.STATE

local sliceQuests = slicer("Data/Providers/Quests.lua")
local retailSrc = sliceQuests("-- /eqot timer test's sample", "-- Unlike 1.15.9, this bound is safe")
               .. sliceQuests("-- /eqot status and /eqot timer:", "-- Undocumented, like /eqot flavorprobe")

-- What GetTimeAllowed answers per quest, and every quest it was asked for. It raises on an id that
-- is not a number, as the client's APIs do, and is taken away where the flag reads false.
local limits, asked = {}, {}
local function getTimeAllowed(id)
    if type(id) ~= "number" then error("bad quest id", 0) end
    asked[#asked + 1] = id
    local l = limits[id]
    if l then return l[1], l[2] end
    return nil, nil
end
local rHas = { QuestTimeAllowed = true }
local rQuestLog = { GetTimeAllowed = getTimeAllowed }
-- Every timer the sample starts, never run on its own: a case fires one when its time is up.
local sampleTimers = {}
-- A timer the sample started, or one that fails the case where none was.
local function sampleTimer(i)
    local t = sampleTimers[i]
    return t and t.fn or function() error("no sample timer " .. i .. " was started", 0) end
end
local renv = setmetatable({
    ns = { Has = rHas },
    time = function() return NOW end,
    C_QuestLog = rQuestLog,
    C_Timer = { After = function(delay, fn) sampleTimers[#sampleTimers + 1] = { delay = delay, fn = fn } end },
}, { __index = _G })

local RQuests = {}
local rstore = entryMod.NewStore({ groupID = "quests", icon = { kind = entryMod.ICON.QUESTPOI }, tags = {} })
local retailChunk = assert(loadstring(
    "local Quests, store, STATE = ...\nlocal primed, dirtyAll, dirtyObjectives = false, false, false\n"
    .. retailSrc
    .. "\nreturn fillTimer, function() return primed, dirtyAll, dirtyObjectives end,"
    .. " function(p) primed, dirtyAll, dirtyObjectives = p, false, false end", "retail-timer-slice"))
setfenv(retailChunk, renv)
local rFill, rFlags, rPrime = retailChunk(RQuests, rstore, STATE)
assert(type(rFill) == "function" and type(RQuests.ToggleTimerTest) == "function"
       and type(RQuests.TimerLine) == "function", "the retail slice defined fillTimer, the toggle and the line")

-- One entry carrying every field the provider sets on a quest, run through the real reader.
local function retailEntry(id, state, stale)
    local entry = { id = id, title = "Quest " .. id, state = state, isTracked = true, isFocused = false,
                    level = 30, zone = "Elwynn Forest", groupID = "quests", addedAt = 0, tags = {},
                    expiresAt = stale }
    asked = {}
    local okCall, err = pcall(rFill, entry, id)
    ok(okCall, "the retail fillTimer does not raise" .. (okCall and "" or (" - " .. tostring(err))))
    return entry
end

limits = { [101] = { 1799, 0.4 } }
local re = retailEntry(101, STATE.ACTIVE)
ok(re.expiresAt == NOW + 1798, "a running limit stamps the whole seconds left, rounded down: "
   .. tostring(re.expiresAt and re.expiresAt - NOW))
ok(#asked == 1 and asked[1] == 101, "and asks for its own quest, once")
limits = { [102] = { 160, 100.9 } }
ok(retailEntry(102, STATE.ACTIVE).expiresAt == NOW + 59, "the last minute is stamped to the second")
limits = { [103] = { 300, 300 } }
ok(retailEntry(103, STATE.ACTIVE).expiresAt == nil, "no time left draws no countdown")
limits = { [104] = { 300, 301 } }
ok(retailEntry(104, STATE.ACTIVE).expiresAt == nil, "and neither does a limit already passed")
limits = { [105] = { 0, 0 } }
ok(retailEntry(105, STATE.ACTIVE).expiresAt == nil, "a quest the client answers 0 and 0 for has no timer")
limits = {}
re = retailEntry(106, STATE.ACTIVE, NOW + 50)
ok(re.expiresAt == nil, "a quest with no limit clears a pooled entry's old deadline")
ok(#asked == 1 and asked[1] == 106, "after asking for that quest")

limits = { [107] = { 600, 30 } }
re = retailEntry(107, STATE.COMPLETE, NOW + 50)
ok(re.expiresAt == nil, "a finished quest draws no countdown, as Blizzard's tracker draws none")
ok(#asked == 0, "and is not asked for at all")
re = retailEntry(107, STATE.FAILED, NOW + 50)
ok(re.expiresAt == nil and #asked == 0, "and neither does a failed one")
ok(retailEntry(107, STATE.ACTIVE).expiresAt == NOW + 570, "while the same quest in progress does")

limits = { [108] = { "600", "100" } }
ok(retailEntry(108, STATE.ACTIVE).expiresAt == NOW + 500, "string figures are taken as numbers")
limits = { [109] = { "x", {} } }
ok(retailEntry(109, STATE.ACTIVE).expiresAt == nil, "and junk is refused rather than raising")

rHas.QuestTimeAllowed, rQuestLog.GetTimeAllowed = false, nil
limits = { [110] = { 600, 0 } }
re = retailEntry(110, STATE.ACTIVE, NOW + 50)
ok(re.expiresAt == nil, "a client without GetTimeAllowed draws no countdown and clears an old one")
rHas.QuestTimeAllowed, rQuestLog.GetTimeAllowed = true, getTimeAllowed

-- ---- /eqot timer test's sample, over the real store ----

local notifies = 0
local function logOf(list)
    rstore:Begin()
    for _, q in ipairs(list) do
        local qe = rstore:Acquire(q.id)
        qe.title, qe.state, qe.isTracked = q.title, q.state, q.tracked
        qe.level, qe.zone, qe.addedAt, qe.groupID, qe.isFocused = 30, "Elwynn Forest", 0, "quests", false
        local okCall, err = pcall(rFill, qe, q.id)
        ok(okCall, "the reader does not raise on " .. q.title .. (okCall and "" or (" - " .. tostring(err))))
    end
    rstore:Finish()
end
local function toggle()
    local okCall, title, why = pcall(RQuests.ToggleTimerTest, RQuests)
    ok(okCall, "ToggleTimerTest does not raise" .. (okCall and "" or (" - " .. tostring(title))))
    if not okCall then return RAISED end
    return title, why
end
local function timerLine()
    local okCall, out = pcall(RQuests.TimerLine, RQuests)
    ok(okCall, "TimerLine does not raise" .. (okCall and "" or (" - " .. tostring(out))))
    return okCall and out or RAISED
end
local function deadline(id) local got = rstore:Get(id) return got and got.expiresAt end

local LOG = {
    { id = 301, title = "Done and tracked", state = STATE.COMPLETE, tracked = true },
    { id = 302, title = "Open, untracked", state = STATE.ACTIVE, tracked = false },
    { id = 303, title = "Open and tracked", state = STATE.ACTIVE, tracked = true },
    { id = 304, title = "Also open and tracked", state = STATE.ACTIVE, tracked = true },
}

limits = {}
RQuests._notifyDirty = nil
logOf(LOG)
local title, why = toggle()
ok(title == nil and why == "off", "with the provider switched off there is no sample")
logOf(LOG)
ok(deadline(303) == nil, "and none is stamped")

RQuests._notifyDirty = function() notifies = notifies + 1 end
logOf({})
title, why = toggle()
ok(title == nil and why == "empty", "an empty log has no quest to put a sample on")
ok(notifies == 0, "and asks for no repaint")

limits = { [304] = { 900, 0 } }
logOf(LOG)
rPrime(true)
title, why = toggle()
ok(title == "Open and tracked" and why == nil, "the sample goes on the first tracked quest in progress: "
   .. tostring(title))
ok(notifies == 1, "and asks for one repaint")
local primedNow, allNow, objNow = rFlags()
ok(objNow == true and allNow == false and primedNow == true, "through the cheap refresh once the log is primed")
logOf(LOG)
ok(deadline(303) == NOW + 120, "the next pass stamps a two-minute sample on that quest: "
   .. tostring(deadline(303) and deadline(303) - NOW))
ok(deadline(304) == NOW + 900, "while a real limit beside it keeps its own deadline")
ok(deadline(302) == nil and deadline(301) == nil, "and the quests without one stay without")
ok(timerLine() == "quest timers: GetTimeAllowed, 2 counting down (303:120s 304:900s) | sample 303",
   "the status line lists both and names the sample: " .. tostring(timerLine()))

title, why = toggle()
ok(title == nil and why == nil, "a second run clears the sample")
ok(notifies == 2, "with a repaint of its own")
logOf(LOG)
ok(deadline(303) == nil, "and the next pass takes the sample away")
ok(timerLine() == "quest timers: GetTimeAllowed, 1 counting down (304:900s) | sample off",
   "the line says so: " .. tostring(timerLine()))

-- Between quest events nothing re-reads the log, so a countdown that runs out still sits on its
-- entry until the next pass, and the line must not list it.
local beforeRunOut = NOW
NOW = NOW + 901
ok(timerLine() == "quest timers: GetTimeAllowed, 0 counting down | sample off",
   "a countdown that ran out since the last pass is not listed: " .. tostring(timerLine()))
NOW = beforeRunOut

-- Before the first full pass only the full rebuild runs, so that is the flag a sample must set.
rPrime(false)
title = toggle()
ok(title == "Open and tracked", "a sample can start before the log is primed")
local _, allEarly, objEarly = rFlags()
ok(allEarly == true and objEarly == false, "and asks for the full rebuild then")
toggle()

-- A sample that has run out is not on, so the next run starts a new one rather than clearing.
rPrime(true)
toggle()
local saved = NOW
NOW = NOW + 121
logOf(LOG)
ok(deadline(303) == nil, "a sample that has run out stamps nothing")
ok(timerLine():find("| sample off", 1, true) ~= nil, "and reads as off")
title = toggle()
ok(title == "Open and tracked", "so the next run starts a fresh one")
logOf(LOG)
ok(deadline(303) == NOW + 120, "two minutes from now, not from the first run")
toggle()
NOW = saved

-- The pre-ship scan of 2026-10-17: a sample laid over a quest with a REAL limit hid that quest's own
-- countdown for good once it ran out, and no quest event re-read the log when it did.
for i = #sampleTimers, 1, -1 do sampleTimers[i] = nil end
limits = { [303] = { 600, 0 } }
rPrime(true)
logOf(LOG)
ok(deadline(303) == NOW + 600, "a quest with a real limit counts its own time")
local startNotifies = notifies
title = toggle()
ok(title == "Open and tracked", "the sample lands on it")
ok(#sampleTimers == 1 and sampleTimers[1].delay == 121,
   "and one timer is started for a second after the sample runs out: "
   .. tostring(sampleTimers[1] and sampleTimers[1].delay))
logOf(LOG)
ok(deadline(303) == NOW + 120, "while the sample runs it takes the quest's row")
saved = NOW
NOW = saved + 119
logOf(LOG)
ok(deadline(303) == NOW + 1, "with one second of it left, still the sample's")
NOW = saved + 120
logOf(LOG)
ok(deadline(303) == NOW + 600, "and at the second it runs out, the real limit's")
NOW = saved + 121
logOf(LOG)
ok(deadline(303) == NOW + 600, "once it has run out the real countdown comes back on the next pass: "
   .. tostring(deadline(303) and deadline(303) - NOW))
rPrime(true)
local before = notifies
local okFire = pcall(sampleTimer(1))
ok(okFire, "the sample's timer does not raise")
ok(notifies == before + 1, "its end asks for one repaint")
local _, endAll, endObj = rFlags()
ok(endObj == true and endAll == false, "through the cheap refresh once the log is primed")
ok(timerLine():find("| sample off", 1, true) ~= nil, "and the sample reads as off")
ok(notifies - startNotifies == 2, "two repaints in all: the start and the end")
rPrime(false)
pcall(sampleTimer(1))
local _, allLate = rFlags()
ok(notifies == before + 1 and allLate == false, "a timer firing again after its sample is gone does nothing")
NOW = saved

-- Started before the first full pass, the sample's end asks for the full rebuild, as its start does.
for i = #sampleTimers, 1, -1 do sampleTimers[i] = nil end
rPrime(false)
toggle()
rPrime(false)
pcall(sampleTimer(1))
local _, coldAll, coldObj = rFlags()
ok(coldAll == true and coldObj == false, "a cold log's sample end asks for the full rebuild")
rPrime(true)

-- A timer left over from a sample that was cleared and started again must not end the new one.
for i = #sampleTimers, 1, -1 do sampleTimers[i] = nil end
rPrime(true)
toggle()
NOW = NOW + 30
toggle()
toggle()
ok(#sampleTimers == 2, "each start sets a timer of its own: " .. #sampleTimers)
before = notifies
pcall(sampleTimer(1))
ok(notifies == before, "the first sample's timer leaves the second sample alone")
logOf(LOG)
ok(deadline(303) == NOW + 120, "which still counts down from its own start")
ok(timerLine():find("| sample 303", 1, true) ~= nil, "and still reads as on")
toggle()
NOW = saved
limits = {}

-- The store hands its entries out in pairs order, so the line sorts them, as text. These four ids
-- come out of the store as 61, 33, 7, 512, which is neither their text order nor their number order.
limits = { [7] = { 100, 0 }, [61] = { 200, 0 }, [512] = { 300, 0 }, [33] = { 400, 0 } }
logOf({ { id = 7, title = "Seven", state = STATE.ACTIVE, tracked = true },
        { id = 61, title = "Sixty-one", state = STATE.ACTIVE, tracked = true },
        { id = 512, title = "Five hundred twelve", state = STATE.ACTIVE, tracked = true },
        { id = 33, title = "Thirty-three", state = STATE.ACTIVE, tracked = true } })
ok(timerLine() == "quest timers: GetTimeAllowed, 4 counting down (33:400s 512:300s 61:200s 7:100s) | sample off",
   "every countdown listed in text order: " .. tostring(timerLine()))
limits = {}

-- With no tracked quest in progress the first quest in the log takes it, finished or not.
logOf({ LOG[1], LOG[2] })
title = toggle()
ok(title == "Done and tracked", "with no tracked quest in progress, the first quest takes it: " .. tostring(title))
toggle()

rHas.QuestTimeAllowed = false
logOf(LOG)
ok(timerLine() == "quest timers: no GetTimeAllowed, 0 counting down | sample off",
   "a client without the call says so: " .. tostring(timerLine()))
rHas.QuestTimeAllowed = true

-- ---- the command ----

local sliceCmd = slicer("UI/Commands.lua")
local cmdBranch = sliceCmd('        elseif cmd == "timer" then', '        elseif cmd == "importeq" then')
local cchunk = assert(loadstring("local tracker, ns, strtrim = ...\nreturn function(cmd, rest)\n    if false then\n"
                                 .. cmdBranch .. "    end\nend", "timer-command-slice"))

local printed, renders, builds
local blizzard, provider = false, nil
local cmdNs, cmdRegistry, cmdFeed = {}, {}, {}
function cmdRegistry:Get(id)
    assert(self == cmdRegistry, "Registry:Get called without self")
    return id == "quests" and provider or nil
end
function cmdFeed:Build() assert(self == cmdFeed, "Feed:Build called without self") builds = builds + 1 end
function cmdNs:GetModule(name)
    assert(self == cmdNs, "ns:GetModule called without self")
    if name == "Registry" then return cmdRegistry end
    if name == "Feed" then return cmdFeed end
end
function cmdNs:UsesBlizzardTracker() assert(self == cmdNs, "UsesBlizzardTracker called without self") return blizzard end
function cmdNs:Print(s) assert(self == cmdNs, "ns:Print called without self") printed[#printed + 1] = s end
local TR = {}
function TR:Render() assert(self == TR, "Tracker:Render called without self") renders = renders + 1 end
local runCmd = cchunk(function() return TR end, cmdNs,
                      function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end)

local function cmd(rest)
    printed, renders, builds = {}, 0, 0
    local okCall, err = pcall(runCmd, "timer", rest)
    ok(okCall, "/eqot timer " .. tostring(rest) .. " does not raise" .. (okCall and "" or (" - " .. tostring(err))))
    return printed[1]
end

-- A stand-in provider recording what the command asked of it.
local toggles, stubAnswer, stubLine
local function stubProvider()
    local p = { id = "quests" }
    function p:ToggleTimerTest() assert(self == p, "ToggleTimerTest called without self") toggles = toggles + 1 return stubAnswer[1], stubAnswer[2] end
    function p:TimerLine() assert(self == p, "TimerLine called without self") if stubLine == RAISED then error("boom", 0) end return stubLine end
    return p
end

provider = nil
ok(cmd("test") == "timer: not available on this client", "no quests provider: not available")
provider = { id = "quests" }
ok(cmd("test") == "timer: not available on this client", "a quests provider with no sample, as on Classic: not available")

provider, toggles = stubProvider(), 0
blizzard = true
ok(cmd("test") == "timer: off, Blizzard's tracker in use", "under Blizzard's tracker it says so")
ok(toggles == 0, "and starts no sample")
blizzard = false

stubAnswer = { nil, "off" }
ok(cmd("test") == "timer: the quests provider is switched off (/eqot modules).", "a switched-off provider is named")
stubAnswer = { nil, "empty" }
ok(cmd("test") == "timer: the quest log is empty, so there is no quest to put a sample on.", "an empty log is named")
stubAnswer = { "Red Linen Goods", nil }
ok(cmd("test") == "timer test: on. A two-minute sample countdown is on Red Linen Goods. "
   .. "Type /eqot timer test again to clear it.", "a sample names its quest")
stubAnswer = { nil, nil }
ok(cmd("test") == "timer test: off.", "and a cleared one says off")
toggles = 0
stubAnswer = { "Red Linen Goods", nil }
cmd("  TEST ")
ok(toggles == 1, "the word is read trimmed and in any case")

stubLine, toggles = "quest timers: GetTimeAllowed, 0 counting down | sample off", 0
ok(cmd("") == stubLine, "with no word it prints the provider's line")
ok(renders == 1 and builds == 1, "after a fresh render and feed build, as /eqot status does")
ok(toggles == 0, "and starts no sample")
ok(cmd("late") == stubLine and toggles == 0, "any other word prints the line too, never a sample")
stubLine = RAISED
ok(cmd("") == "|cffff5555TimerLine raised|r boom", "a raising line is reported, not thrown")

-- And the real provider behind it, end to end through the slice above.
provider = RQuests
logOf(LOG)
ok(cmd("test") == "timer test: on. A two-minute sample countdown is on Open and tracked. "
   .. "Type /eqot timer test again to clear it.", "the real provider's sample is named by the command")
ok(cmd("test") == "timer test: off.", "and cleared by it")

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

-- The retail half's seams. Both paths stamp the deadline, each straight before the objectives and
-- after the state the reader checks, or a finished quest is read as still running.
local _, questsSrc = slicer("Data/Providers/Quests.lua")
has(questsSrc, '                fillTimer(e, id)\n                fillLines(e, id)\n',
    "the full rebuild stamps the retail deadline straight before the objectives")
has(questsSrc, '        fillTimer(e, id)\n        fillLines(e, id)\n    end\n',
    "and so does the cheap refresh")
local retailCalls = select(2, questsSrc:gsub("\n[ ]+fillTimer%(e, id%)\n", "\n"))
ok(retailCalls == 2, "exactly those two calls: " .. retailCalls)
local function stateBeforeTimer(fromAnchor, toAnchor)
    local a = questsSrc:find(fromAnchor, 1, true)
    local b = a and questsSrc:find(toAnchor, a, true)
    local s = a and questsSrc:find("e.state     = questState(id)", a, true)
    local t = a and questsSrc:find("fillTimer(e, id)", a, true)
    return a and b and s and t and s < t and t < b
end
ok(stateBeforeTimer("local function fullRebuild()", "local function refreshDynamic()"),
   "the full rebuild writes the state before it stamps the deadline")
ok(stateBeforeTimer("local function refreshDynamic()", "function Quests:IsAvailable()"),
   "and so does the cheap refresh")

has(compatSrc, 'Has.QuestTimeAllowed    = method(C_QuestLog, "GetTimeAllowed")\n',
    "the retail capability probes GetTimeAllowed on C_QuestLog, anchored on the line ending")

local timerBlock = '            if p.TimerLine then\n                local ok, line = pcall(p.TimerLine, p)\n'
    .. '                ns:Print("      " .. (ok and (line or "")\n'
    .. '                    or ("|cffff5555TimerLine raised|r " .. tostring(line))))\n            end\n'
local timerAt = cmdSrc:find(timerBlock, 1, true)
local debugAt = cmdSrc:find("            if p.DebugLine then\n", 1, true)
local filtersAt = cmdSrc:find('    debugLine("Filter", nil, "FiltersLine")', 1, true)
ok(timerAt ~= nil, "/eqot status prints each provider's timer line under a pcall")
ok(timerAt and debugAt and filtersAt and debugAt < timerAt and timerAt < filtersAt,
   "inside the providers loop, after its status line")
has(cmdSrc, 'mplus [test|late], popup [test], timer [test], importeq',
    "the usage line lists the timer command")

-- ===================================================================== the row's tooltip

-- The pre-ship scans of 2026-10-17: the tooltip's faction and Time Left lines, which every timed
-- quest now reaches, had no harness, and Time Left floored to minutes drew nothing through the
-- last minute. Everything from the redraw's budget to _DrawEntry is sliced from UI/RewardTooltip.lua,
-- the real redraw included, and run over the real Util loaded above, entered the way a hover
-- enters it, through the row's own paintTooltip sliced out of UI/Row.lua.
local rtSrc = slicer("UI/RewardTooltip.lua")("local REDRAW_DELAY = 0.4", "function RT:Hide()")
local rtChunk = assert(loadstring("local RT, ns, Util, L, pickAnchor, renderLines = ...\n" .. rtSrc,
                                  "entry-tooltip-slice"))
-- Each redraw the tooltip arms, run by a case when it wants the redraw to happen.
local redraws = {}
setfenv(rtChunk, setmetatable({
    time = function() return NOW end,
    C_Timer = { After = function(_, fn) redraws[#redraws + 1] = fn end },
}, { __index = _G }))
local tipLines, factions, drewObjectives, sawReward = {}, {}, true, true
local tipStub = {}
function tipStub:SetOwner(owner) self.owner = owner end
function tipStub:GetOwner() return self.owner end
function tipStub:IsShown() return true end
function tipStub:SetText(text) tipLines = { { text = text } } end
function tipStub:AddLine(text, r, g, b) tipLines[#tipLines + 1] = { text = text, r = r, g = g, b = b } end
function tipStub:Show() end
local QRStub = {}
-- The game has no title for 503 yet, so the entry's own has to stand in.
function QRStub:Title(id) if id ~= 503 then return "Quest " .. id end end
function QRStub:FactionName(id) return factions[id] end
local RTmod = {}
local tipUtil = setmetatable({ Tooltip = function() return tipStub end }, { __index = Util })
rtChunk(RTmod, { GetModule = function(_, n) if n == "QuestRewards" then return QRStub end end }, tipUtil,
        setmetatable({}, { __index = function(_, k) return k end }),
        function() return "ANCHOR_RIGHT" end,
        function() return drewObjectives, sawReward end)
local function joined()
    local texts = {}
    for i, l in ipairs(tipLines) do texts[i] = l.text end
    return table.concat(texts, "|")
end
-- The owner is the row, which the redraw asks still holds the quest.
local lastOwner
local function drawTip(id, expiresAt, hint, entryTitle)
    tipLines = {}
    lastOwner = { _entry = { id = id } }
    local okCall, err = pcall(RTmod.ShowForEntry, RTmod, lastOwner,
                              { id = id, title = entryTitle or ("Quest " .. id), expiresAt = expiresAt }, hint or false)
    ok(okCall, "the entry tooltip does not raise" .. (okCall and "" or (" - " .. tostring(err))))
    return joined(), tipLines
end
local function lineColor(l)
    if not (l and l.r and l.g and l.b) then return "no color" end
    return ("%.2f,%.2f,%.2f"):format(l.r, l.g, l.b)
end

factions = { [501] = "The Assembly of the Deeps" }
ok(drawTip(501, nil) == "Quest 501", "with no deadline: no faction line and no time left")
local text, lines = drawTip(501, NOW + 3900)
ok(text == "Quest 501|The Assembly of the Deeps| |Time Left: 1h 5m",
   "a deadline brings the faction under the title, then a gap and the time left: " .. text)
ok(lineColor(lines[2]) == "0.70,0.70,0.70", "the faction in gray")
ok(lineColor(lines[4]) == "1.00,0.65,0.10", "an hour and five minutes in the under-two-hours orange: "
   .. tostring(lineColor(lines[4])))
text, lines = drawTip(501, NOW + 45)
ok(text == "Quest 501|The Assembly of the Deeps| |Time Left: 45s",
   "the last minute counts in seconds rather than going blank: " .. text)
ok(lineColor(lines[4]) == "1.00,0.25,0.25",
   "in the row's under-half-an-hour red, never the red of no time left: " .. tostring(lineColor(lines[4])))
text, lines = drawTip(501, NOW + 60)
ok(text:find("|Time Left: 1m", 1, true) ~= nil and lineColor(lines[4]) == "1.00,0.25,0.25",
   "a minute is a minute, in the same red: " .. text)
text, lines = drawTip(501, NOW + 1799)
ok(text:find("|Time Left: 29m", 1, true) ~= nil and lineColor(lines[4]) == "1.00,0.25,0.25",
   "29 and a half minutes reads 29m in the under-half-an-hour red, as the row floors it: " .. text)
ok(drawTip(501, NOW) == "Quest 501|The Assembly of the Deeps", "at no time left there is no time line")
ok(drawTip(501, NOW - 5) == "Quest 501|The Assembly of the Deeps", "nor past it")
ok(drawTip(502, NOW + 45) == "Quest 502| |Time Left: 45s", "a quest with no faction has no faction line")
drewObjectives = false
ok(drawTip(502, NOW + 45) == "Quest 502|Time Left: 45s", "and with nothing drawn above it, no gap")
drewObjectives = true
text = drawTip(501, NOW + 45, true)
ok(text == "Quest 501|The Assembly of the Deeps| |Time Left: 45s| "
   .. "|Click the icon to focus this quest, or again to clear it.|Click the title to open the quest log.",
   "the click hint comes last, after the time left: " .. text)

ok(drawTip(503, nil, false, "From the entry") == "From the entry",
   "a quest the game has no title for yet shows the entry's own")

-- Rewards still loading arm a redraw, run through the real one, which has to draw the same
-- deadline, hint and title again.
local function runRedraw()
    tipLines = {}
    local okCall, err = pcall(redraws[1] or function() error("no redraw was armed", 0) end)
    ok(okCall, "the redraw does not raise" .. (okCall and "" or (" - " .. tostring(err))))
    return joined()
end
for i = #redraws, 1, -1 do redraws[i] = nil end
drawTip(501, NOW + 45)
ok(#redraws == 0, "a tooltip with its rewards in hand arms no redraw")
sawReward = false
drawTip(501, NOW + 45, true)
ok(#redraws == 1, "one with its rewards still loading arms one: " .. #redraws)
ok(runRedraw() == "Quest 501|The Assembly of the Deeps| |Time Left: 45s| "
   .. "|Click the icon to focus this quest, or again to clear it.|Click the title to open the quest log.",
   "and the redraw keeps the faction, the time left and the click hint: " .. joined())
for i = #redraws, 1, -1 do redraws[i] = nil end
drawTip(503, NOW + 45, false, "From the entry")
ok(runRedraw():find("^From the entry|") ~= nil, "and the entry's own title when the game still has none")
for i = #redraws, 1, -1 do redraws[i] = nil end
drawTip(501, NOW + 45)
lastOwner._entry = { id = 999 }
ok(runRedraw() == "", "a row recycled onto another quest inside the delay draws nothing")
sawReward = true

-- The hover itself: the row hands its own entry and hint to the tooltip.
local paintSrc = slicer("UI/Row.lua")("local function paintTooltip(row)",
                                      "-- The cursor crosses between the icon and the title")
local rowChunk = assert(loadstring(paintSrc .. "\nreturn paintTooltip", "row-tooltip-slice"))
local rowProviders = { quests = { idSpace = "quest" } }
local rowNs = { Util = tipUtil }
function rowNs:GetModule(name)
    assert(self == rowNs, "ns:GetModule without self")
    if name == "Registry" then
        return { Get = function(_, id) return rowProviders[id] end }
    end
    if name == "RewardTooltip" then return RTmod end
end
setfenv(rowChunk, setmetatable({ ns = rowNs }, { __index = _G }))
local paintTooltip = rowChunk()
local function hoverRow(entry, hint)
    tipLines = {}
    local okCall, err = pcall(paintTooltip, { _providerID = "quests", _entry = entry, _hintShown = hint })
    ok(okCall, "the row's tooltip does not raise" .. (okCall and "" or (" - " .. tostring(err))))
    return joined()
end
ok(hoverRow({ id = 501, title = "Quest 501", expiresAt = NOW + 45 }, false)
   == "Quest 501|The Assembly of the Deeps| |Time Left: 45s",
   "hovering a timed quest's row draws its faction and its time left")
ok(hoverRow({ id = 501, title = "Quest 501", expiresAt = NOW + 45 }, true):find("|Click the title to open the quest log.", 1, true)
   ~= nil, "and hands its click hint on")
ok(hoverRow({ id = 501, title = "Quest 501" }, false) == "Quest 501", "and a quest with no deadline draws neither")

print(("test_quest_timers: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
