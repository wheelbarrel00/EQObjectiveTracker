-- luacheck: globals C_Timer QuestUtil C_LFGList LFGListUtil_FindQuestGroup geterrorhandler
--
-- Unit tests for Data/QuestGroups.lua, run against the SHIPPED source.
-- Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_quest_groups.lua
--
-- Data/QuestGroups.lua loads WHOLE here. It creates no frame and calls no quest API, so a table
-- with RegisterModule on it plus C_Timer and one of the two group APIs is a complete stand-in.
--
-- THE CASE THAT EARNS THIS FILE. DebugLine counted the cache and counted pending and never said
-- how many answers were TRUE, so `quest groups: 29 cached, 0 pending` read identically whether
-- every quest genuinely refused a group or the eye had stopped drawing. Those want opposite
-- hunts, and reading that line cost a whole session on 2026-09-07 before the answer turned out
-- to be 29 real noes. The names are the fix and this file is what holds them there.
--
-- THE OTHER THING MEASURED HERE, because two comments in this repo asserted the opposite:
-- CanCreate answers FALSE for a lookup that has not come back, never nil, so entry.canGroup is
-- never nil on a provider-built entry.
--
-- OUT OF SCOPE BY CONSTRUCTION: whether QuestUtil.CanCreateQuestGroup answers correctly, whether
-- LFGListUtil_FindQuestGroup opens anything, and the taint question behind the deferral. Only
-- the cache, its resolution and what DebugLine says about them are measured.

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
end

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end

local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
geterrorhandler = function() return function(e) print("  handler: " .. tostring(e)) end end

-- Runs every timer currently queued, once. A drain that queues another timer leaves it for the
-- next call rather than looping, so a test can count rounds.
local function tick()
    local queue = timers
    timers = {}
    for i = 1, #queue do queue[i]() end
    return #queue
end

-- A fresh module per block: cache, pending and listeners are all file-locals, so the only
-- honest way to get a clean one is to load the file again.
local function fresh(eligible, opts)
    opts = opts or {}
    timers = {}
    local asked = {}
    local function answer(id)
        asked[#asked + 1] = id
        return eligible[id] or false
    end
    QuestUtil = (not opts.noQuestUtil) and { CanCreateQuestGroup = answer } or nil
    C_LFGList = opts.lfgList and { CanCreateQuestGroup = answer } or nil

    local QG
    local ns = { RegisterModule = function(_, _, t) QG = t return t end }
    assert(loadfile(repoFile("Data/QuestGroups.lua")))("QuestGroups", ns)
    assert(QG, "Data/QuestGroups.lua never registered its module")
    return QG, asked
end

local function line(QG)
    local okCall, res = pcall(QG.DebugLine, QG)
    ok(okCall, "DebugLine does not raise" .. (okCall and "" or (" - " .. tostring(res))))
    return okCall and res or ""
end

-- ------------------------------------------------------------------------------- cases

print("== an empty cache says none rather than drawing empty brackets")
do
    local QG = fresh({})
    local s = line(QG)
    ok(s:find("0 cached", 1, true) ~= nil, "reports nothing cached: " .. s)
    ok(s:find("0 can group (none)", 1, true) ~= nil, "and names none rather than a blank pair")
    ok(s:find("0 pending", 1, true) ~= nil, "with nothing outstanding")
end

print("== the true answers are NAMED, which is the whole reason this line changed")
do
    local QG = fresh({ [111] = true, [999] = true })
    for _, id in ipairs({ 999, 222, 111, 333 }) do QG:CanCreate(id) end
    tick() tick()

    local s = line(QG)
    ok(s:find("4 cached", 1, true) ~= nil, "every answer is counted: " .. s)
    ok(s:find("2 can group", 1, true) ~= nil, "and the eligible ones are counted separately")
    ok(s:find("(111 999)", 1, true) ~= nil, "named, and sorted rather than in pairs order")
    ok(s:find("222", 1, true) == nil, "a quest that refused is not named")
    ok(s:find("0 pending", 1, true) ~= nil, "and nothing is left outstanding")
end

print("== two readings of an unchanged cache are byte-identical")
do
    -- pairs order is unspecified, so without the sort two consecutive readings of a cache
    -- nothing touched can differ, and a diagnostic that moves on its own is unreadable.
    local QG = fresh({ [5] = true, [77] = true, [3] = true, [1200] = true })
    for _, id in ipairs({ 1200, 3, 77, 5 }) do QG:CanCreate(id) end
    tick() tick()
    local first = line(QG)
    ok(first == line(QG), "the same cache reads the same twice: " .. first)
    ok(first:find("(3 5 77 1200)", 1, true) ~= nil,
       "sorted NUMERICALLY rather than as text, or 1200 would sort before 3: " .. first)
end

print("== CanCreate answers false while unresolved, never nil")
do
    -- Load-bearing: entry.canGroup is assigned straight from this, and UI/Row.lua's eye plus
    -- both providers' menu gates are plain truth tests. A nil here would still gate correctly
    -- but two comments in this repo claimed nil and built reasoning on it.
    local QG = fresh({ [42] = true })
    local first = QG:CanCreate(42)
    ok(first == false, "the first ask is false, not nil: " .. tostring(first))
    ok(type(first) == "boolean", "and it is a boolean, so a provider can store it as one")
    -- pcall'd, or dropping the guard reaches the client stub with nil and ABORTS the run
    -- instead of failing this case, which a battery reads as CRASHED rather than caught.
    local okNil, nilAnswer = pcall(QG.CanCreate, QG, nil)
    ok(okNil and nilAnswer == false,
       "a nil quest id answers false rather than raising: " .. tostring(okNil and nilAnswer))

    tick()
    ok(QG:CanCreate(42) == true, "once the timer runs the real answer is cached")
end

print("== the cache answers without asking the client again")
do
    local QG, asked = fresh({ [7] = true })
    QG:CanCreate(7)
    tick()
    local before = #asked
    for _ = 1, 5 do QG:CanCreate(7) end
    ok(#asked == before, "five more reads cost no client call: " .. #asked .. " against " .. before)
end

print("== a false is re-asked exactly once, and a true never is")
do
    -- A false is either a real no or activity data that has not streamed in, and the two are
    -- indistinguishable here. Unbounded re-asking risks being throttled by that API.
    local QG, asked = fresh({ [8] = true })
    QG:CanCreate(8)
    QG:CanCreate(9)
    tick()
    tick()
    tick()

    local n8, n9 = 0, 0
    for i = 1, #asked do
        if asked[i] == 8 then n8 = n8 + 1 elseif asked[i] == 9 then n9 = n9 + 1 end
    end
    ok(n8 == 1, "the quest that answered true was asked once: " .. n8)
    ok(n9 == 2, "the one that answered false was asked twice and then left alone: " .. n9)
    ok(line(QG):find("2 cached, 1 can group (8)", 1, true) ~= nil, "and both are cached")
end

print("== listeners fire when an answer moves, and on no other drain")
do
    local QG = fresh({ [21] = true })
    local fired = 0
    QG:OnResolved(function() fired = fired + 1 end)
    QG:CanCreate(21)
    tick()
    ok(fired == 1, "a resolved answer notifies once: " .. fired)
    ok(line(QG):find("1 listener(s)", 1, true) ~= nil, "the count reaches the status line")

    -- Driven with a FALSE deliberately. A true is never re-asked, so it schedules no second
    -- drain and the changed guard is never reached - a true here let the guard be deleted with
    -- this file green. Only the single recheck of a false produces a drain that can run and
    -- change nothing.
    local quiet = fresh({})
    local again = 0
    quiet:OnResolved(function() again = again + 1 end)
    quiet:CanCreate(22)
    tick()
    ok(again == 1, "the first answer moved and notified: " .. again)
    tick()
    ok(again == 1, "and the recheck found it unchanged and notified nobody: " .. again)
end

print("== a raising listener does not stop the others or strand the drain")
do
    local QG = fresh({ [31] = true })
    local second = 0
    QG:OnResolved(function() error("listener blew up", 0) end)
    QG:OnResolved(function() second = second + 1 end)
    QG:CanCreate(31)
    local okTick = pcall(tick)
    ok(okTick, "the drain survives a listener that raises")
    ok(second == 1, "and the listener after it still runs: " .. second)
end

print("== Forget drops an id so a recycled quest cannot inherit its answer")
do
    local QG = fresh({ [61] = true, [62] = true })
    QG:CanCreate(61) QG:CanCreate(62)
    tick() tick()
    ok(line(QG):find("(61 62)", 1, true) ~= nil, "both are named while they are live")

    QG:Forget(61)
    local s = line(QG)
    ok(s:find("1 cached", 1, true) ~= nil, "a forgotten id leaves the cache: " .. s)
    ok(s:find("1 can group (62)", 1, true) ~= nil, "and leaves the named list with it")
    QG:Forget(62)
    ok(line(QG):find("0 can group (none)", 1, true) ~= nil,
       "back to none rather than an empty pair of brackets")
    ok(QG:Forget(nil) == nil, "and forgetting nil is a no-op rather than a raise")
end

print("== PruneExcept keeps what its predicate keeps, for BOTH providers")
do
    -- The predicate has to answer for the quest log AND the world quest store. Pruning against
    -- one provider's entries alone evicts the other's, which re-asks on its next pass and
    -- rearms the timer, so the eye flickers and the cache never settles.
    local QG = fresh({ [71] = true, [72] = true, [73] = true })
    QG:CanCreate(71) QG:CanCreate(72) QG:CanCreate(73)
    tick() tick()
    ok(line(QG):find("3 cached", 1, true) ~= nil, "three cached before the prune")

    QG:PruneExcept(function(qid) return qid ~= 72 end)
    local s = line(QG)
    ok(s:find("2 cached", 1, true) ~= nil, "the id the predicate refused is gone: " .. s)
    ok(s:find("(71 73)", 1, true) ~= nil, "and the survivors are still named")
end

print("== the client APIs are asked in order, and a missing one degrades")
do
    local QG = fresh({ [81] = true }, { noQuestUtil = true, lfgList = true })
    QG:CanCreate(81)
    tick()
    ok(line(QG):find("1 can group (81)", 1, true) ~= nil,
       "with QuestUtil absent the C_LFGList fallback answers")

    local bare = fresh({ [82] = true }, { noQuestUtil = true })
    bare:CanCreate(82)
    tick()
    ok(line(bare):find("0 can group (none)", 1, true) ~= nil,
       "and with neither present nothing can group, which is the Classic reading")
end

print(("test_quest_groups: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
