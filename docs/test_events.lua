-- luacheck: globals CreateFrame C_Timer GetTime InCombatLockdown geterrorhandler tremove
--
-- Unit tests for Core/Events.lua, run against the SHIPPED source.
-- Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_events.lua
--
-- Core/Events.lua loads WHOLE here. It creates one frame and calls no quest API, so a table with
-- RegisterEvent, UnregisterEvent and SetScript on it is a complete stand-in.
--
-- The case that earns this file:
--
--   A DEBOUNCE KEY IS DISARMED ONLY BY ITS OWN TIMER CALLBACK. Before the recovery below, a
--   C_Timer.After that never fired left the key armed for the session, and every later Debounce
--   on it replaced d.fn, returned false and scheduled NOTHING - so the work never ran, nothing
--   errored, and the repaint channel was dead until the player reloaded. Read off a user's
--   client: the quest sound scan had not run for 39 minutes while the events driving it kept
--   firing, and on that same client a manual Tracker:Refresh() did nothing where
--   Tracker:Render() worked. Only the scan is carried by a counter of its own; the dead repaint
--   is read off that Refresh/Render split rather than measured directly.
--
--   THREE halves have to be tested together, not two. A recovery that never fires leaves the
--   original bug. One that fires too eagerly turns off the burst collapse this exists to do. And
--   one whose stray timer can still serve a later arming runs the key twice per window for the
--   rest of the session, which is the render rate v1.17.0 was released to cut.

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
end

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end

-- Every assertion-bearing call into production goes through this. A raise has to FAIL a case,
-- never kill the run: the summary line would not print and every battery here reads a missing
-- summary as a mutant that SURVIVED, which sends the next reader hunting a coverage hole that is
-- not there. Two calls sit outside it and each is guarded its own way - load()'s chunk(), under
-- an assert, and advance()'s timer callbacks, which carry the pcall described below.
local function call(fn, ...)
    local packed = { pcall(fn, ...) }
    ok(packed[1], "the call does not raise" .. (packed[1] and "" or (" - " .. tostring(packed[2]))))
    return packed[2]
end

-- Every case below INDEXES what DebugLine returns, so a build that answered nothing would kill
-- the file on the next line rather than failing a case. The empty-string default is safe here
-- precisely because it makes every find() below FAIL rather than quietly pass.
local function debugLine(E)
    local s = call(E.DebugLine, E)
    ok(type(s) == "string", "DebugLine answers a string")
    return type(s) == "string" and s or ""
end

-- ---------------------------------------------------------------------- the client stubs

local now, timers, dropNext, errors, escaped

-- Advanceable rather than constant. The whole feature is "how long has this key been armed", so
-- a fixed clock would make every age exactly 0 and the overdue test could not fail.
--
-- The tick is pcall'd and counted rather than called bare: debounceTick guards its own callback,
-- and a bare call here would let a build that dropped that guard KILL this file instead of
-- failing a case - which every battery in this tree reads as a mutant that SURVIVED.
local function advance(secs)
    now = now + secs
    local due = {}
    for i = #timers, 1, -1 do
        if timers[i].at <= now then
            table.insert(due, 1, timers[i])
            table.remove(timers, i)
        end
    end
    for i = 1, #due do
        if not pcall(due[i].fn) then escaped = escaped + 1 end
    end
    return #due
end

local eventHandler, frameStub

local function reset()
    now, timers, dropNext, errors, escaped = 1000, {}, false, {}, 0
    eventHandler = nil
    -- Restored here rather than left to the last case that touched it, so the combat cases can
    -- be reordered or added to without a later case inheriting a client that is still in combat.
    _G.InCombatLockdown = function() return false end
    frameStub = {
        registered = {}, unregistered = {}, attempts = {},
        RegisterEvent = function(self, e)
            self.attempts[e] = (self.attempts[e] or 0) + 1
            -- RegisterEvent RAISES on an event the client does not know, which is the whole
            -- reason Events:On pcalls it. A forgiving stub cannot reach that branch.
            if e:find("^BOGUS") then error("unknown event " .. e) end
            self.registered[e] = (self.registered[e] or 0) + 1
        end,
        UnregisterEvent = function(self, e) self.unregistered[e] = true end,
        SetScript = function(_, script, fn) if script == "OnEvent" then eventHandler = fn end end,
    }
end

_G.GetTime = function() return now end
_G.InCombatLockdown = function() return false end
_G.geterrorhandler = function() return function(e) errors[#errors + 1] = tostring(e) end end
_G.tremove = table.remove
_G.CreateFrame = function() return frameStub end
_G.C_Timer = {
    After = function(delay, fn)
        if dropNext then dropNext = false return end
        timers[#timers + 1] = { at = now + delay, fn = fn }
    end,
}

-- A fresh module per case: _debounce, _debOrder and the recovery counters are file-locals and a
-- case must not inherit any of them from the case before it.
local function load()
    reset()
    local ns = {
        modules = {},
        RegisterModule = function(self, n, t) self.modules[n] = t or {} return self.modules[n] end,
        GetModule = function(self, n) return self.modules[n] end,
    }
    local chunk = assert(loadfile(repoFile("Core/Events.lua")))
    chunk("EQObjectiveTracker", ns)
    return ns:GetModule("Events")
end

local SRC = (function()
    local f = assert(io.open(repoFile("Core/Events.lua"), "r"))
    local s = f:read("*a")
    f:close()
    return s
end)()

-- ------------------------------------------------------------------------------ the cases

print("== the shipped slack is the number these cases are written against")
do
    -- Written as a literal below rather than read out of the file, because a case that measures
    -- against the constant under test grows and shrinks with it and can never fail. This one
    -- assertion is what makes a deliberate change fail loudly BY NAME instead.
    -- Captured and compared whole rather than found as a substring: "local LOST_SLACK = 3" is
    -- also a substring of 3.9, 30 and 300, so the one signpost written to fail BY NAME would
    -- stay silent and leave an unexplained behavioural failure below it instead.
    ok(SRC:match("\nlocal LOST_SLACK = ([%d%.]+)") == "3",
       "LOST_SLACK is exactly 3 in the shipped source - if this changed on purpose, fix the "
       .. "cases below, which are written against 3 as a literal")
end

print("== an ordinary burst collapses to one call carrying the LAST function")
do
    local E = load()
    local ran = {}
    ok(call(E.Debounce, E, "k", 0.25, function() ran[#ran + 1] = "first" end) == true,
       "the first request arms the key")
    ok(call(E.Debounce, E, "k", 0.25, function() ran[#ran + 1] = "second" end) == false,
       "a request inside the window is collapsed")
    ok(call(E.Debounce, E, "k", 0.25, function() ran[#ran + 1] = "third" end) == false,
       "and so is the next one")
    ok(#timers == 1, "one timer is outstanding, not three")
    advance(0.3)
    ok(#ran == 1, "the work runs once")
    ok(ran[1] == "third", "and it is the LAST function handed over, not the first")
end

print("== the KEY is part of the identity")
do
    -- The recorded stub bug: a Debounce that discarded its key let production debounce the quest
    -- sound scan on the tracker's own repaint key with a green suite, one silently cancelling
    -- the other. Two keys have to be independently armable.
    local E = load()
    local a, b = 0, 0
    ok(call(E.Debounce, E, "alpha", 0.25, function() a = a + 1 end) == true, "alpha arms")
    ok(call(E.Debounce, E, "beta", 0.25, function() b = b + 1 end) == true,
       "beta arms too rather than collapsing into alpha")
    advance(0.3)
    ok(a == 1 and b == 1, "both keys did their own work")
end

print("== a dropped timer no longer strands the key for the session")
do
    local E = load()
    local ran = 0
    dropNext = true
    ok(call(E.Debounce, E, "eqot.render", 0.25, function() ran = ran + 1 end) == true,
       "the request arms the key")
    ok(#timers == 0, "and its timer was lost")
    advance(0.3)
    ok(ran == 0, "so nothing ran, which is the symptom the user reported")

    -- Still inside the slack: the key is armed and not yet overdue, so this must COLLAPSE.
    advance(2)
    ok(call(E.Debounce, E, "eqot.render", 0.25, function() ran = ran + 1 end) == false,
       "a request inside the slack is still collapsed, not treated as lost")
    ok(#timers == 0, "and schedules nothing")

    -- Past delay + LOST_SLACK: the timer is overdue and the key is re-armed.
    advance(2)
    ok(call(E.Debounce, E, "eqot.render", 0.25, function() ran = ran + 1 end) == true,
       "a request past the slack recovers the key")
    ok(#timers == 1, "and schedules a fresh timer")
    advance(0.3)
    ok(ran == 1, "the work finally runs")

    -- The point of the fix: the key is healthy again rather than dead for the session.
    ok(call(E.Debounce, E, "eqot.render", 0.25, function() ran = ran + 1 end) == true,
       "and the key arms normally from then on")
    -- The recovery has to re-stamp, not just re-arm. Left holding the ORIGINAL stamp the key
    -- reads permanently overdue, so it recovers on every request and never collapses again.
    ok(call(E.Debounce, E, "eqot.render", 0.25, function() ran = ran + 1 end) == false,
       "and collapses a burst again, so the recovery re-stamped rather than only re-arming")
    advance(0.3)
    ok(ran == 2, "so later requests are served")
end

print("== the overdue test measures from the DEADLINE, not from the arming")
do
    -- delay 0.25 plus LOST_SLACK 3 puts the boundary at 3.25s after arming. At 3.1s a key is
    -- late by 2.85 and must still collapse. Dropping the delay term from that subtraction makes
    -- it read 3.1 and recover early, which is a burst collapse quietly turned off.
    local E = load()
    dropNext = true
    call(E.Debounce, E, "k", 0.25, function() end)
    advance(3.1)
    ok(call(E.Debounce, E, "k", 0.25, function() end) == false,
       "3.1s after arming is inside delay + slack, so the key still collapses")
    advance(0.3)
    ok(call(E.Debounce, E, "k", 0.25, function() end) == true,
       "and 3.4s after arming it is past the deadline and recovers")
end

print("== a stray timer left by a recovery cannot steal a later window")
do
    -- Recovering leaves the lost timer outstanding, so two are in flight on one key. If the
    -- stray one took the work and disarmed on its way past, the next request would arm a second
    -- timer of its own and the key would run twice per window from then on - measured at a
    -- sustained 2x, which is the render rate v1.17.0 was released to cut.
    -- The tick closure is memoized per key, so this one function is what EVERY timer on that key
    -- calls and firing it by hand is exactly what a stray arrival does.
    local E = load()
    local ran = {}
    call(E.Debounce, E, "k", 0.25, function() ran[#ran + 1] = "first" end)
    local stray = table.remove(timers, 1)

    advance(10)
    ok(call(E.Debounce, E, "k", 0.25, function() ran[#ran + 1] = "second" end) == true,
       "the overdue key recovers")
    call(stray.fn)
    ok(#ran == 0, "a stray arriving before the new deadline runs nothing")
    ok(#errors == 0 and escaped == 0, "and returns rather than reaching for the slot")

    advance(0.3)
    ok(#ran == 1 and ran[1] == "second",
       "the arming's own timer does the work, once, at its own deadline")
    ok(#timers == 0, "and leaves no timer outstanding")

    -- The other ordering, which is where the empty-slot guard earns its keep: pcall(nil) does
    -- not raise, it answers false, so a build that dropped the guard would reach the error
    -- handler rather than the run counter and the count above would not notice.
    call(stray.fn)
    ok(#ran == 1, "a stray arriving after the key was served runs nothing either")
    ok(#errors == 0, "and reports no error, because it never reached for the empty slot")

    ok(call(E.Debounce, E, "k", 0.25, function() ran[#ran + 1] = "third" end) == true,
       "the next request arms a timer")
    ok(#timers == 1, "exactly one, not two")
    ok(call(E.Debounce, E, "k", 0.25, function() ran[#ran + 1] = "fourth" end) == false,
       "with a burst behind it still collapsing")
    advance(0.3)
    ok(#ran == 2, "so a recovered key runs at its ordinary rate, not twice per window")
end

print("== the recovery counters only move on a real recovery")
do
    local E = load()
    call(E.Debounce, E, "k", 0.25, function() end)
    call(E.Debounce, E, "k", 0.25, function() end)
    advance(0.3)
    local line = debugLine(E)
    ok(line:find("recovered 0", 1, true) ~= nil,
       "an ordinary collapse is not counted as a recovery")

    dropNext = true
    call(E.Debounce, E, "k", 0.25, function() end)
    advance(600)
    call(E.Debounce, E, "k", 0.25, function() end)
    line = debugLine(E)
    ok(line:find("recovered 1", 1, true) ~= nil, "a real recovery is counted")
    -- The worst-late figure is what separates ordinary timer jitter from a key that was genuinely
    -- dead, which is the whole reason this number is reported rather than only the count.
    ok(line:find("worst 600s late", 1, true) ~= nil,
       "and it reports HOW overdue the worst one was")
end

print("== DebugLine names an armed key and its age")
do
    local E = load()
    local line = debugLine(E)
    ok(line:find("armed now: none", 1, true) ~= nil, "nothing armed reads as none")
    ok(line:find("debounce: 0 keys", 1, true) ~= nil, "and no key has been seen yet")

    dropNext = true
    call(E.Debounce, E, "eqot.render", 0.25, function() end)
    advance(612)
    line = debugLine(E)
    ok(line:find("eqot.render 612s", 1, true) ~= nil,
       "an armed key is named with its age, which is what a 39 minute strand looks like")
    ok(line:find("debounce: 1 keys", 1, true) ~= nil, "and the key count moved")

    advance(1)
    call(E.Debounce, E, "eqot.render", 0.25, function() end)
    advance(0.3)
    line = debugLine(E)
    ok(line:find("armed now: none", 1, true) ~= nil, "a served key stops being reported as armed")
end

print("== a raising callback cannot strand its own key")
do
    -- debounceTick clears armed BEFORE it calls fn, and pcalls it. If either half went, one bad
    -- handler would kill that key for the session - the exact failure this file exists for.
    local E = load()
    call(E.Debounce, E, "k", 0.25, function() error("boom") end)
    advance(0.3)
    ok(#errors == 1, "the raise reaches the error handler rather than being swallowed")
    ok(escaped == 0, "and is caught inside the tick rather than escaping the timer callback")
    local ran = 0
    ok(call(E.Debounce, E, "k", 0.25, function() ran = ran + 1 end) == true,
       "and the key is not armed, so the next request arms it normally")
    advance(0.3)
    ok(ran == 1, "and its work runs")
end

print("== an unknown event is refused, recorded and never re-registered")
do
    local E = load()
    ok(call(E.On, E, "GOOD_EVENT", function() end) == true, "a known event registers")
    ok(frameStub.registered.GOOD_EVENT == 1, "once")
    ok(call(E.On, E, "BOGUS_EVENT", function() end) == false, "an unknown event is refused")
    ok(call(E.On, E, "BOGUS_EVENT", function() end) == false, "and stays refused")
    ok(frameStub.registered.BOGUS_EVENT == nil, "with no listener installed")
    -- The refusal is REMEMBERED, not re-derived. Without the unknown set the second call raises
    -- inside the client again, which answers false either way and so hides the difference.
    ok(frameStub.attempts.BOGUS_EVENT == 1, "and the client is only asked once, ever")

    local line = debugLine(E)
    ok(line:find("1 unknown on this client - BOGUS_EVENT", 1, true) ~= nil,
       "and the status names it, because a silent subsystem otherwise reads as a clean zero")
end

print("== dispatch isolates handlers and passes the payload through")
do
    local E = load()
    local seen = {}
    call(E.On, E, "QUEST_ACCEPTED", function() error("first handler blew up") end)
    call(E.On, E, "QUEST_ACCEPTED", function(ev, a, b) seen = { ev, a, b } end)
    ok(eventHandler ~= nil, "the OnEvent script is installed")
    call(eventHandler, frameStub, "QUEST_ACCEPTED", 19, 469)
    ok(#errors == 1, "the raising handler is reported")
    ok(seen[1] == "QUEST_ACCEPTED" and seen[2] == 19 and seen[3] == 469,
       "and the handler after it still runs, with the full payload")
end

print("== Off removes one handler and unregisters when the last one goes")
do
    local E = load()
    local hits = 0
    local one = function() hits = hits + 1 end
    local two = function() hits = hits + 1 end
    call(E.On, E, "QUEST_LOG_UPDATE", one)
    call(E.On, E, "QUEST_LOG_UPDATE", two)
    call(E.Off, E, "QUEST_LOG_UPDATE", one)
    call(eventHandler, frameStub, "QUEST_LOG_UPDATE")
    ok(hits == 1, "only the remaining handler runs")
    ok(frameStub.unregistered.QUEST_LOG_UPDATE == nil, "and the event stays registered")
    call(E.Off, E, "QUEST_LOG_UPDATE", two)
    ok(frameStub.unregistered.QUEST_LOG_UPDATE == true, "the last one taken off unregisters it")
end

print("== combat deferral runs now, or in arrival order when combat ends")
do
    local E = load()
    local order = {}
    ok(call(E.RunWhenOutOfCombat, E, "a", function() order[#order + 1] = "immediate" end) == true,
       "out of combat it runs straight away")
    ok(order[1] == "immediate", "and really did run")

    _G.InCombatLockdown = function() return true end
    ok(call(E.RunWhenOutOfCombat, E, "first", function() order[#order + 1] = "first" end) == false,
       "in combat it defers")
    call(E.RunWhenOutOfCombat, E, "second", function() order[#order + 1] = "second" end)
    -- Re-deferring a key keeps its FIRST arrival slot. A deferred reset and a deferred stopDrag
    -- both write the tracker position, and which one won used to be pairs() order.
    call(E.RunWhenOutOfCombat, E, "first", function() order[#order + 1] = "first again" end)
    ok(#order == 1, "nothing ran while combat was up")

    _G.InCombatLockdown = function() return false end
    call(eventHandler, frameStub, "PLAYER_REGEN_ENABLED")
    ok(order[2] == "first again" and order[3] == "second",
       "the re-deferred key keeps its original slot and carries the NEWER function")
    ok(#order == 3, "and each key runs once")

    call(eventHandler, frameStub, "PLAYER_REGEN_ENABLED")
    ok(#order == 3, "a second combat end replays nothing")

    -- A key deferred, flushed, and deferred AGAIN has to queue a second time. The flush empties
    -- the order list either way, so leaving the key's own entry behind is invisible until here:
    -- RunWhenOutOfCombat then reads it as already queued, appends nothing, and the work is
    -- accepted and silently never runs.
    _G.InCombatLockdown = function() return true end
    call(E.RunWhenOutOfCombat, E, "first", function() order[#order + 1] = "third round" end)
    _G.InCombatLockdown = function() return false end
    call(eventHandler, frameStub, "PLAYER_REGEN_ENABLED")
    ok(order[4] == "third round", "the same key deferred again after a flush still runs")
end

print("== the delay is honored, and at a value other than the tracker's own")
do
    -- Every other case here debounces at 0.25, so the delay handed to C_Timer.After was only
    -- ever exercised at one value and could be replaced by a constant - or by zero, which turns
    -- the burst collapse off entirely - with the file green. 2.0 is the world quest repaint.
    local E = load()
    local ran = 0
    call(E.Debounce, E, "eqot.wqPoi", 2.0, function() ran = ran + 1 end)
    advance(1.9)
    ok(ran == 0, "the work has not run before its delay has elapsed")
    advance(0.2)
    ok(ran == 1, "and runs once the delay is up")
end

print("== lateness is measured against the delay the key was ARMED with")
do
    -- d.delay is stamped per arming. Read back from the CALLER instead, a key armed at 2.0 and
    -- then asked for at 0.25 measures its lateness against the wrong deadline, in both
    -- directions: a live key recovers early, and a genuinely stranded one is not noticed.
    local E = load()
    dropNext = true
    call(E.Debounce, E, "k", 2.0, function() end)
    advance(4)
    ok(call(E.Debounce, E, "k", 0.25, function() end) == false,
       "2s past a 2.0s deadline is inside the slack, so a shorter later delay cannot recover it")

    local F = load()
    dropNext = true
    call(F.Debounce, F, "k", 0.25, function() end)
    advance(4)
    ok(call(F.Debounce, F, "k", 2.0, function() end) == true,
       "and 3.75s past a 0.25s deadline still recovers, so a longer one cannot mask it")
end

print("== a key is counted once however many times it arms")
do
    -- The count is the first field of the debounce status line. Appended on every arm rather
    -- than on creation it climbs forever on the busiest key in the addon, and the line a user
    -- pastes reads "debounce: 400 keys" against an addon that has five.
    local E = load()
    for _ = 1, 4 do call(E.Debounce, E, "eqot.render", 0.25, function() end) advance(0.3) end
    ok(debugLine(E):find("debounce: 1 keys", 1, true) ~= nil, "four arms of one key is one key")
    call(E.Debounce, E, "widgets", 0.2, function() end)
    ok(debugLine(E):find("debounce: 2 keys", 1, true) ~= nil, "and a second key makes it two")
end

print("== the status line reads correctly when nothing is wrong")
do
    -- The happy-path wording is what a user pastes in the normal case and no case asserted it,
    -- so it could be replaced with anything at all.
    local E = load()
    call(E.On, E, "QUEST_LOG_UPDATE", function() end)
    local line = debugLine(E)
    ok(line:find("events: every registration accepted by this client", 1, true) == 1,
       "a client that knew every event says so, on the first line")
    ok(line:find("recovered 0, worst 0s late", 1, true) ~= nil, "with nothing rescued")
end

print("== a raising deferred callback does not lose the keys queued behind it")
do
    -- flushDeferred pcalls each callback for the same reason the dispatch loop does, and nothing
    -- tested it. Called bare, the raise escapes into the dispatch's own pcall, reaches the error
    -- handler and so LOOKS handled, while every key after it in the queue is silently abandoned.
    -- The queue routinely carries the deferred drag stop and the deferred position reset.
    local E = load()
    local order = {}
    _G.InCombatLockdown = function() return true end
    call(E.RunWhenOutOfCombat, E, "first", function() order[#order + 1] = "first" end)
    call(E.RunWhenOutOfCombat, E, "boom", function() error("deferred handler blew up") end)
    call(E.RunWhenOutOfCombat, E, "last", function() order[#order + 1] = "last" end)
    _G.InCombatLockdown = function() return false end
    call(eventHandler, frameStub, "PLAYER_REGEN_ENABLED")
    ok(#errors == 1, "the raise is reported")
    ok(order[1] == "first" and order[2] == "last" and #order == 2,
       "and the key queued behind it still runs")
end

print("== a key deferred DURING a flush lands in the next flush, not the one running")
do
    -- The order list is emptied in a first pass before any callback runs, so a callback that
    -- defers goes into a fresh queue rather than being consumed by the loop it is inside.
    -- Collapsed into one loop, that key runs immediately and its combat gate means nothing.
    local E = load()
    local order = {}
    _G.InCombatLockdown = function() return true end
    call(E.RunWhenOutOfCombat, E, "outer", function()
        order[#order + 1] = "outer"
        _G.InCombatLockdown = function() return true end
        E:RunWhenOutOfCombat("inner", function() order[#order + 1] = "inner" end)
    end)
    _G.InCombatLockdown = function() return false end
    call(eventHandler, frameStub, "PLAYER_REGEN_ENABLED")
    ok(order[1] == "outer" and #order == 1, "the callback ran and its own deferral did not")
    _G.InCombatLockdown = function() return false end
    call(eventHandler, frameStub, "PLAYER_REGEN_ENABLED")
    ok(order[2] == "inner" and #order == 2, "the next combat end runs it")
end

print("== the flush is subscribed, once")
do
    local E = load()
    _G.InCombatLockdown = function() return true end
    for i = 1, 5 do call(E.RunWhenOutOfCombat, E, "k" .. i, function() end) end
    ok(frameStub.registered.PLAYER_REGEN_ENABLED == 1,
       "five deferrals subscribe the flush to one event registration, not five")
end

print("== InCombat answers a boolean either way")
do
    -- Read by UI/ItemButtons.lua to decide whether a secure button applies now or defers, and
    -- covered by nothing. The client's own answer is not always a boolean, hence the normalize.
    local E = load()
    ok(call(E.InCombat, E) == false, "out of combat it is false, not nil")
    _G.InCombatLockdown = function() return 1 end
    ok(call(E.InCombat, E) == true, "and a truthy non-boolean from the client reads as true")
end

print("== taking the last handler off an event lets a later one re-register it")
do
    -- Off nils the listener list so the next On sees no list and registers again. Left as an
    -- empty table, On appends to it, skips RegisterEvent, and that handler never fires - the
    -- silent-subsystem shape this whole file exists for.
    local E = load()
    local hits = 0
    local one = function() hits = hits + 1 end
    call(E.On, E, "QUEST_TURNED_IN", one)
    call(E.Off, E, "QUEST_TURNED_IN", one)
    ok(call(E.On, E, "QUEST_TURNED_IN", function() hits = hits + 1 end) == true,
       "re-subscribing after the last handler went answers true")
    ok(frameStub.registered.QUEST_TURNED_IN == 2, "and really re-registers with the client")
    call(eventHandler, frameStub, "QUEST_TURNED_IN")
    ok(hits == 1, "so the new handler fires")
end

print(("test_events: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
