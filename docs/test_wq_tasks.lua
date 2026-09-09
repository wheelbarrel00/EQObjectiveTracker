-- Unit tests for Data/Providers/WorldQuests.lua's tasks-table source, run against the SHIPPED
-- source rather than a copy. Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_wq_tasks.lua
--
-- WHY THIS FILE EXISTS. Reported by Entmoot on 2026-09-07: a Temple Patrol bonus objective was
-- drawn by the game and absent from this tracker. His /eqot status read worldquests 0 with
-- "0 task/bonus", so nothing in the addon had found it. Measured on the author's own client
-- 2026-09-08, standing near one:
--
--     95580  IsQuestTask true   IsWorldQuest false   GetLogIndexForQuestID 29, isHidden TRUE
--
-- A bonus objective IS in the quest log, but only as a HIDDEN entry. That is the fact the whole
-- feature turns on: both quest providers gate on `not info.isHidden`, so addQuestLogTaskQuests's
-- own gate is exactly what excluded it, and no map list carried it either. An earlier reading
-- here was of 95580, which is a `[DNT]` developer stub rather than a bonus objective and which
-- GetTaskInfo answers nothing for. Blizzard's Blizzard_BonusObjectiveTracker.lua reads
-- GetTasksTable and
-- NOTHING else - no map lists, no quest log - and gates each entry on GetTaskInfo's
-- numObjectives and isInArea. addTaskTableQuests reproduces that, and this file holds it to it.
--
-- What earns the file:
--   * a bonus objective in range is PUSHED, which is the report
--   * a WORLD QUEST in the same table is not, which is what keeps this strictly additive: it
--     must never start listing world quests for a player who has autoListZoneWorldQuests off,
--     and Entmoot is exactly that player
--   * the isInArea and numObjectives gates, which are what the author's own reading measured
--     (area nil, obj nil, standing outside the area) and are the difference between a live
--     bonus objective and one merely registered nearby
--   * every client call is pcall'd, because a raise here costs GetEntries and so the render
--
-- Data/Providers/WorldQuests.lua cannot be loaded whole without stubbing the quest log, the
-- entry store and the group cache, so the source is sliced out by TEXT ANCHORS rather than line
-- numbers, which drift. If an anchor stops matching, fix the anchor here rather than deleting
-- the test.
--
-- OUT OF SCOPE BY CONSTRUCTION: everything downstream of push. Whether a pushed candidate
-- survives the emit loop's title, logOwned and expiry gates is reached by no assertion here.

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
end

local fh = assert(io.open(repoFile("Data/Providers/WorldQuests.lua"), "r"))
local src = fh:read("*a")
fh:close()

local function sliceBetween(fromAnchor, toAnchor)
    local from = src:find(fromAnchor, 1, true)
    local to   = src:find(toAnchor, 1, true)
    assert(from, "anchor not found in Data/Providers/WorldQuests.lua: " .. fromAnchor)
    assert(to,   "anchor not found in Data/Providers/WorldQuests.lua: " .. toAnchor)
    assert(to > from, "anchors are out of order: " .. fromAnchor)
    return src:sub(from, to - 1)
end

-- isWorldQuest comes with it rather than being restated. It is the gate that keeps this source
-- additive, and a reimplementation here would be free to agree with the test while disagreeing
-- with the build - which is the defect this project has recorded four times over.
local sourceSrc = sliceBetween("local function isWorldQuest(qid)",
                               "-- Lists every world quest on the map you are standing in")

local chunk = assert(loadstring(sourceSrc .. "\nreturn addTaskTableQuests, isWorldQuest",
                                "wq-tasks-slice"))

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end

-- ------------------------------------------------------------------------- the client stubs

local SECRET_VALUE = setmetatable({}, { __tostring = function() return "<secret>" end })

local pushed          -- ids the source handed on, in order
local tasks           -- what GetTasksTable answers
local taskInfo        -- per id: { isInArea, isOnMap, numObjectives }
local worldQuests     -- ids C_QuestLog.IsWorldQuest calls world quests
local calls           -- how many times each client API was reached
local raiseTable, raiseInfo

local env = setmetatable({
    ns = { Has = { TasksTable = true, TaskInfo = true } },
    -- Recorded rather than counted: a counter cannot tell the source pushing the world quest
    -- and skipping the bonus objective from doing it the right way round.
    push = function(qid) pushed[#pushed + 1] = qid end,
    -- A Midnight secret value raises when it is MATCHED rather than when it is read, which is
    -- why the source guards the truth test and not only the pcall around the call. Modeled
    -- with a sentinel because plain Lua has no value that raises on a truth test, and Lua 5.1
    -- does not honor debug.setmetatable on a boolean.
    _issecret = function(v) return v == SECRET_VALUE end,
    C_QuestLog = {
        -- Raises on anything that is not a quest id, the way a client API does rather than
        -- politely answering nil. A forgiving stub let the `qid and` guard be deleted with the
        -- file green, because a nil simply fell through every branch below it unnoticed.
        IsWorldQuest = function(qid)
            if type(qid) ~= "number" then error("bad quest id", 0) end
            return worldQuests[qid] == true
        end,
    },
    GetTasksTable = function()
        calls.table = calls.table + 1
        if raiseTable then error("GetTasksTable raised", 0) end
        return tasks
    end,
    -- Returns FIVE values in Blizzard's own order, the way the shipped API does:
    -- isInArea, isOnMap, numObjectives, taskName, displayAsObjective. A stub with the wrong
    -- arity is this project's recorded false-result generator - the source reads the THIRD
    -- return, so a three-value stub would silently feed it isOnMap.
    GetTaskInfo = function(qid)
        calls.info = calls.info + 1
        if type(qid) ~= "number" then error("bad quest id", 0) end
        if raiseInfo then error("GetTaskInfo raised", 0) end
        local t = taskInfo[qid]
        if not t then return nil, nil, nil, nil, nil end
        return t[1], t[2], t[3], t[4], t[5]
    end,
}, { __index = _G })

setfenv(chunk, env)
local addTaskTableQuests, isWorldQuest = chunk()
assert(type(addTaskTableQuests) == "function", "the slice defined no addTaskTableQuests")
assert(type(isWorldQuest) == "function", "the slice defined no isWorldQuest")

-- The ONLY way the cases below reach production. A raise has to FAIL a case rather than kill
-- the run: the summary line would never print, and every battery in this tree reads a missing
-- summary as a mutant that SURVIVED, so a crash would report as a coverage hole instead.
local function run(msg)
    pushed = {}
    calls  = { table = 0, info = 0 }
    local okCall, err = pcall(addTaskTableQuests)
    ok(okCall, msg .. ": addTaskTableQuests raised - " .. tostring(err))
    return pushed
end

local function reset()
    tasks, taskInfo, worldQuests = {}, {}, {}
    raiseTable, raiseInfo = false, false
    env.ns.Has.TasksTable, env.ns.Has.TaskInfo = true, true
    -- One case below drops this to model a pre-Midnight client, so it is restored here rather
    -- than by that case, which would leak into everything after it if the case ever raised.
    env._issecret = function(v) return v == SECRET_VALUE end
end

-- isInArea, isOnMap, numObjectives, taskName, displayAsObjective - Blizzard's order.
-- displayAsObjective read TRUE for the measured quest and the source deliberately does not
-- gate on it, because Blizzard's own AddQuest does not either.
local function inArea(n)    return { true,  true,  n or 1, "A Bonus Objective", true } end
local function outOfArea()  return { false, true,  1,      "A Bonus Objective", true } end
-- What the author's own client actually answered for a task he was near but not inside:
-- every field nil. Not false - ABSENT.
local function unreadable() return { nil,   nil,   nil,    nil,                 nil  } end

local function only(list, id) return #list == 1 and list[1] == id end

-- ------------------------------------------------------------------------------- the cases

print("== the report: a bonus objective in range is picked up")
do
    reset()
    tasks = { 95580 }
    taskInfo[95580] = inArea(1)
    local got = run("bonus objective in range")
    ok(only(got, 95580),
       "a task quest the player is inside, with objectives, is pushed - which is the whole bug")
    ok(calls.table == 1, "the tasks table is read exactly once per pass")
end

print("== a world quest in the same table is left alone")
do
    reset()
    tasks = { 91804 }
    worldQuests[91804] = true
    taskInfo[91804] = inArea(1)
    local got = run("world quest skipped")
    ok(#got == 0,
       "a world quest is never pushed here, so this cannot list one for a player with " ..
       "autoListZoneWorldQuests switched off")
    ok(calls.info == 0, "and it is refused before GetTaskInfo is paid for at all")
end

print("== the two gates the author's own reading measured")
do
    reset()
    tasks = { 95580 }
    taskInfo[95580] = unreadable()
    ok(#run("area nil") == 0,
       "a task the client answers all-nil for is skipped, which is the reading taken " ..
       "standing outside one")

    reset()
    tasks = { 95580 }
    taskInfo[95580] = outOfArea()
    ok(#run("isInArea false") == 0, "isInArea false is skipped even with objectives present")

    reset()
    tasks = { 95580 }
    taskInfo[95580] = { true, true, nil, "A Bonus Objective" }
    ok(#run("no objectives") == 0, "no objective count is skipped even while inside the area")
end

print("== zero objectives is TRUTHY in Lua, and that is deliberate parity with Blizzard")
do
    reset()
    tasks = { 95580 }
    taskInfo[95580] = inArea(0)
    -- Blizzard's own gate is `if numObjectives and treatAsInArea`, so a zero passes there too.
    -- Asserted rather than left implicit: 0 being truthy has bitten this codebase twice, and a
    -- future reader tightening this to `> 0` would be diverging from the tracker being matched.
    ok(only(run("zero objectives"), 95580),
       "zero objectives still passes, exactly as it does in Blizzard's own bonus tracker")
end

print("== a mixed table keeps order and picks only the right entries")
do
    reset()
    tasks = { 91804, 95580, 95580, 96528 }
    worldQuests[91804], worldQuests[96528] = true, true
    taskInfo[95580] = inArea(1)
    taskInfo[95580] = inArea(2)
    taskInfo[91804] = inArea(1)
    taskInfo[96528] = inArea(1)
    local got = run("mixed table")
    ok(#got == 2 and got[1] == 95580 and got[2] == 95580,
       "both bonus objectives are pushed, in table order, and neither world quest is")
end

print("== the client is never trusted to behave")
do
    reset()
    tasks = { 95580 }
    taskInfo[95580] = inArea(1)
    raiseTable = true
    ok(#run("GetTasksTable raises") == 0,
       "a raising GetTasksTable costs nothing - it must not take GetEntries and the section")

    reset()
    tasks = { 95580, 95580 }
    taskInfo[95580] = inArea(1)
    taskInfo[95580] = inArea(1)
    raiseInfo = true
    ok(#run("GetTaskInfo raises") == 0, "and neither does a raising GetTaskInfo")

    reset()
    tasks = nil
    ok(#run("nil tasks table") == 0, "a client answering no table at all is refused")

    reset()
    tasks = "not a table"
    ok(#run("tasks table is not a table") == 0, "and so is one answering something else")

    reset()
    -- A junk entry mid-table. Written as false rather than nil deliberately: { a, nil, b }
    -- leaves # undefined in Lua 5.1, so the case would turn on table internals rather than on
    -- the guard under test. Both stubs above raise on a non-id, so dropping `qid and` fails
    -- this rather than falling through unnoticed.
    tasks = { 95580, false, 95580 }
    taskInfo[95580] = inArea(1)
    taskInfo[95580] = inArea(1)
    local got = run("junk entry mid-table")
    ok(#got == 2 and got[1] == 95580 and got[2] == 95580,
       "an entry that is not a quest id is stepped over, and what follows it is not lost")
end

print("== a client without the API is not called at all")
do
    reset()
    tasks = { 95580 }
    taskInfo[95580] = inArea(1)
    env.ns.Has.TasksTable = false
    ok(#run("no GetTasksTable") == 0, "no tasks table means no rows")
    ok(calls.table == 0, "and the API is not reached, rather than reached and refused")

    reset()
    tasks = { 95580 }
    taskInfo[95580] = inArea(1)
    env.ns.Has.TaskInfo = false
    ok(#run("no GetTaskInfo") == 0, "the gate needs BOTH globals, since it reads both")
    ok(calls.table == 0, "and neither is reached without the other")
end

print("== a secret value is refused rather than matched")
do
    reset()
    tasks = { 95580 }
    taskInfo[95580] = { SECRET_VALUE, true, 1, "A Bonus Objective", true }
    local got = run("secret isInArea")
    ok(#got == 0,
       "a secret isInArea is refused rather than matched, which is where it would raise")
end

do
    reset()
    tasks = { 95580 }
    taskInfo[95580] = { true, true, SECRET_VALUE, "A Bonus Objective" }
    local got = run("secret numObjectives")
    ok(#got == 0, "and a secret objective count is refused the same way")
end

do
    reset()
    tasks = { 95580, 95581 }
    taskInfo[95580] = { SECRET_VALUE, true, 1, "A Bonus Objective", true }
    taskInfo[95581] = inArea(1)
    local got = run("a secret entry beside an ordinary one")
    ok(only(got, 95581),
       "one secret entry costs that entry rather than the rest of the table")
end

do
    reset()
    -- issecretvalue is absent on every client before Midnight, and the guard degrades to a
    -- plain truth test there rather than refusing everything.
    env._issecret = nil
    tasks = { 95580 }
    taskInfo[95580] = inArea(1)
    local got = run("no issecretvalue on this client")
    ok(only(got, 95580),
       "a client with no issecretvalue still lists an ordinary bonus objective")
end

print("== the section split: a bonus objective is not a world quest")
do
    -- The emit loop is outside the slice, so these are read off the shipped source. Both halves
    -- are needed and they live in different places: declaring the group without choosing it per
    -- entry draws nothing new, and choosing it without declaring it makes Entry:Validate refuse
    -- the entry in debug builds.
    ok(src:find('groups   = { "worldquests", "bonusobjectives" }', 1, true) ~= nil,
       "the provider DECLARES both groups, or a bonus objective is an undeclared groupID")
    ok(src:find('e.groupID = wq and "worldquests" or "bonusobjectives"', 1, true) ~= nil,
       "and the emit loop picks the group per entry, so a bonus objective draws under a header " ..
       "of its own rather than beside the world quests")
end

print("== the source is reachable at all: the flags, the call site and the secret alias")
do
    -- Everything below is UPSTREAM of the slice, so the cases above pass with the whole feature
    -- switched off. Each of these was proved by hand: the harness read 44 passed, 0 failed with
    -- the flags probed wrong, with the flag name misspelled, with the call site deleted, and
    -- with the secret alias typo'd.
    local cf = assert(io.open(repoFile("Core/Compat.lua"), "r"))
    local compat = cf:read("*a")
    cf:close()
    -- BARE globals with no C_ twin. The six probes around these read method(C_TaskQuest, ...),
    -- so that is the edit to expect, and it makes both flags false on every client forever.
    ok(compat:find('Has.TasksTable          = global("GetTasksTable")', 1, true) ~= nil,
       "GetTasksTable is probed as a bare global, or the flag is false on every client")
    ok(compat:find('Has.TaskInfo            = global("GetTaskInfo")', 1, true) ~= nil,
       "and so is GetTaskInfo")
    ok(src:find('currentSource = "tasktable"; addTaskTableQuests()', 1, true) ~= nil,
       "the source is CALLED - sliced and driven here, it is dead code without this line")
    -- Read off _G rather than declared in the slice, so env._issecret stands in for it here and
    -- a typo in the shipped alias is invisible to every case above.
    -- The trailing newline is load-bearing: without it this is a PREFIX match, and a typo that
    -- APPENDS to the global name still satisfies it. Proved by breaking it exactly that way.
    ok(src:find("local _issecret = _G.issecretvalue\n", 1, true) ~= nil,
       "the secret alias is spelled right, or every guard in the file degrades to nil")
end

print("== the section the split sends them to actually exists")
do
    -- The other two of the four load-bearing places. A typo'd title draws the raw group id as
    -- the header, and a missing DEFAULT_ORDER entry costs a new profile its position.
    local sf = assert(io.open(repoFile("UI/Sections.lua"), "r"))
    local sections = sf:read("*a")
    sf:close()
    ok(sections:find("bonusobjectives = TRACKER_HEADER_BONUS_OBJECTIVES,", 1, true) ~= nil,
       "the section has a title, or Sections:Title falls back to drawing the raw group id")
    ok(sections:find('"quests", "bonusobjectives"', 1, true) ~= nil,
       "and a place in DEFAULT_ORDER after quests, where the stock tracker draws it")
end

print("== a bonus objective is offered neither track verb, and no world quest icon")
do
    -- Newly reachable: nothing in the addon could emit a bonus objective before this release,
    -- so the row menu had never been asked about one. Track dispatches AddWorldQuestWatch.
    ok(src:find('local isWQ = entry.groupID ~= "bonusobjectives"', 1, true) ~= nil,
       "GetEntryMenu asks which group the row is in")
    ok(src:find("    if isWQ then\n        menuOut[#menuOut + 1] = { id = tracked and \"untrack\" or \"track\", order = 10 }",
                1, true) ~= nil,
       "and offers the track pair only on a world quest, never on a bonus objective")
    ok(src:find("e.icon.kind  = wq and ICON.WORLDQUEST or ICON.NONE", 1, true) ~= nil,
       "and the emit loop writes the icon kind on BOTH branches, so a pooled entry cannot " ..
       "keep the world quest ring from whatever it drew last")
end

print("== isWorldQuest comes from the shipped file rather than being restated here")
do
    reset()
    worldQuests[91804] = true
    ok(isWorldQuest(91804) == true, "the sliced helper answers true for a world quest")
    ok(isWorldQuest(95580) == false, "and false for a bonus objective")
end

print(("test_wq_tasks: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
