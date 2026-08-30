-- luacheck: globals wipe CopyTable C_NeighborhoodInitiative
--
-- Unit tests for the neighborhood initiative provider, run against the SHIPPED source rather
-- than a copy. Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_initiative.lua
--
-- The task shape here is the one measured on a live Midnight character on 2026-08-30. The
-- fixture carries every field the real table has so a future reader starts from the real shape,
-- but only six of them are load-bearing and only those six are asserted: ID, taskName, tracked,
-- completed, and requirementsList's requirementText and completed. Deleting the other eight from
-- this fixture does NOT fail these cases, and claiming otherwise would be a lie in a header.
--
-- Known equivalent, so nobody chases it: deleting Entry.BeginLines changes nothing while
-- EndLines runs, because EndLines clears _nlines and PushLine restarts from nil. Deleting
-- EndLines DOES change behavior and is covered below.
--
-- The cases that earn this file:
--
--   1. The filter is the PER-TASK `tracked` flag. `inProgress` was the obvious candidate and is
--      wrong: six tasks carried it and only one of the six was on Blizzard's tracker, while the
--      three carrying `tracked` were exactly the three drawn. A test that cannot tell those two
--      apart would let the wrong one back in, and it would look plausible on screen.
--   2. GetTrackedInitiativeTasks answered 0 the whole time. Nothing may read it.
--   3. IsAvailable is a CAPABILITY probe. Whether the player is in a neighborhood changes
--      mid-session and IsAvailable is answered once, so the content gate belongs in GetEntries
--      or the section stays dead for the rest of the session.
--   4. The fetch is asynchronous, so it is issued from the event path only. GetEntries runs
--      inside Tracker:Render and must not make a call that answers later.

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
end

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end

_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

-- Blizzard globals Data/Entry.lua leans on. CopyTable is a deep copy there, and the store uses
-- it to seed each entry from the provider's defaults table.
_G.CopyTable = function(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = (type(v) == "table") and _G.CopyTable(v) or v end
    return out
end

-- The measured shape. taskType, sortOrder, supersedes, timesCompleted and rewardQuestID are
-- carried even though nothing reads them yet, so a future reader starts from the real table.
local function task(id, name, flags, reqs)
    return {
        ID = id, taskName = name,
        tracked    = flags.tracked or false,
        inProgress = flags.inProgress or false,
        completed  = flags.completed or false,
        taskType = 2, sortOrder = id, supersedes = 0, timesCompleted = 0,
        rewardQuestID = 0, progressContributionAmount = 25,
        description = name .. " description",
        criteriaList = {},
        requirementsList = reqs or { { requirementText = "- 0 / 100 things", completed = false } },
    }
end

local requested, dirty, handlers, mods = 0, 0, {}, {}
-- The ns each build creates, so a case can make one of its shared helpers raise.
local lastNs

local function build(opts)
    opts = opts or {}
    requested, dirty, handlers, mods = 0, 0, {}, {}

    if opts.absent then
        _G.C_NeighborhoodInitiative = nil
    else
        _G.C_NeighborhoodInitiative = {
            GetNeighborhoodInitiativeInfo = function() return opts.info end,
            IsInitiativeEnabled = function() return opts.enabled ~= false end,
            PlayerHasInitiativeAccess = function() return opts.access ~= false end,
            RequestNeighborhoodInitiativeInfo = function() requested = requested + 1 end,
            -- Measured at 0 while three tasks were tracked and drawn. Nothing may read it, and
            -- this raises rather than returning empty so anything that does is caught here.
            GetTrackedInitiativeTasks = function() error("GetTrackedInitiativeTasks was read") end,
        }
    end

    local ns = { Has = {} }
    function ns:RegisterModule(n, t) mods[n] = t return t end
    function ns:GetModule(n) return mods[n] end
    lastNs = ns

    -- Both register themselves through ns:RegisterModule, so the return value is nil and
    -- assigning it would blank the module the provider then indexes.
    assert(loadfile(repoFile("Data/Entry.lua")))("EQObjectiveTracker", ns)
    assert(loadfile(repoFile("Core/Util.lua")))("EQObjectiveTracker", ns)

    local captured
    mods.Registry = { Register = function(_, p) captured = p end }
    mods.Events   = { On = function(_, e, fn) handlers[e] = fn end }

    assert(loadfile(repoFile("Data/Providers/Initiative.lua")))("EQObjectiveTracker", ns)
    captured:Enable(function() dirty = dirty + 1 end)
    return captured
end

-- Never index the entry map directly. A mutant that stops emitting an entry would otherwise
-- abort the file on `nil.lines`, and an aborted run proves nothing about any assertion in it -
-- the mutation driver reports that as CRASHED rather than caught for exactly this reason.
local MISSING = { title = "<missing>", state = "<missing>", lines = {}, isTracked = "<missing>" }
local function pick(map, name) return map[name] or MISSING end
local function lineAt(e, i) return e.lines[i] or { text = "<no line>", completed = "<no line>" } end

local function titles(entries)
    local out = {}
    for i = 1, #entries do out[i] = entries[i].title end
    table.sort(out)
    return table.concat(out, ", ")
end

-- ------------------------------------------------------------------ the measured live set

local INFO = {
    isLoaded = true, title = "Knock-off Amani", currentProgress = 750, progressRequired = 1000,
    milestones = { {}, {}, {}, {} },
    tasks = {
        task(1, "Kill Raid Bosses",              { inProgress = true }),
        task(2, "Earn Honor",                    { tracked = true }),
        task(3, "Cursed Surge Scourge",          { inProgress = true }),
        task(4, "Delve Diver: The Coiled Isle",  { inProgress = true }),
        task(5, "Venom Master",                  { tracked = true, inProgress = true }),
        task(6, "No Fang-ks",                    { inProgress = true }),
        task(7, "Corrosive Collector",           { tracked = true }),
        task(8, "Gather Resources: The Coiled Isle", { inProgress = true }),
        task(9, "Home: Be a Good Neighbor",      {}),
    },
}

local p = build({ info = INFO })

-- The provider caches the initiative graph now, because rebuilding the whole thing on every
-- repaint was too expensive to keep doing. Blizzard fires NEIGHBORHOOD_INITIATIVE_UPDATED whenever
-- that graph changes, so a case that EDITS the fixture has to fire it too - editing without it
-- models a client that cannot exist. The cache's own coverage is at the bottom of this file,
-- where the event is deliberately withheld.
-- Guarded, not because the handler is optional but because a mutant that DELETES the
-- subscription must fail an assertion here rather than abort the file on a nil call. An
-- aborted run has no summary line, and the mutation battery reports that as a crash it cannot
-- classify instead of the caught mutant it is.
local function rebuild()
    local fn = handlers.NEIGHBORHOOD_INITIATIVE_UPDATED
    if fn then fn() end
    return p:GetEntries()
end

local entries = rebuild()

ok(#entries == 3, "three tracked tasks emit three entries, got " .. #entries)
ok(titles(entries) == "Corrosive Collector, Earn Honor, Venom Master",
   "and they are exactly the three the stock tracker draws: " .. titles(entries))

-- The mutant that matters. Six tasks carry inProgress and only one of them is on screen.
local prog = 0
for i = 1, #INFO.tasks do if INFO.tasks[i].inProgress then prog = prog + 1 end end
ok(prog == 6, "the fixture really does carry six inProgress tasks, or the case above proves nothing")
ok(#entries ~= prog, "the filter is not inProgress")

ok(entries[1].groupID == "endeavors",
   "entries carry the endeavors group id, so Feed buckets them beside the Traveler's Log")
-- The OTHER half of the same interlock, and the one that decides whether a section header and an
-- options row appear. Registry builds its group set from `groups`, Feed buckets on entry.groupID,
-- and they are consumed independently - so asserting one proves nothing about the other.
ok(#p.groups == 1 and p.groups[1] == "endeavors",
   "and the provider DECLARES that group, so no section of its own is created")
ok(p.id == "initiative", "the provider id is stable, it keys stats and disable/enable")
ok(p.idSpace == nil,
   "no idSpace: task ids are their own space and must not contend with quest claims")
ok(p.priority == 45, "priority encodes product intent, not load order")

-- ------------------------------------------------------------------ lines and state

local byTitle = {}
for i = 1, #entries do byTitle[entries[i].title] = entries[i] end
local honor = pick(byTitle, "Earn Honor")
ok(lineAt(honor, 1).text == "0/100 things",
   "the requirement bullet and the padded fraction are both stripped: "
   .. tostring(lineAt(honor, 1).text))
ok(honor.state == "active", "an unfinished task is active")

INFO.tasks[2].completed = true
INFO.tasks[2].requirementsList[1].completed = true
entries = rebuild()
for i = 1, #entries do byTitle[entries[i].title] = entries[i] end
ok(pick(byTitle, "Earn Honor").state == "complete", "a completed task reports complete")
INFO.tasks[2].completed = false
INFO.tasks[2].requirementsList[1].completed = false

-- Derived rather than assumed absent: the measured table carries `completed`, but a task that
-- omits it must still resolve from its own requirements.
INFO.tasks[2].completed = nil
INFO.tasks[2].requirementsList[1].completed = true
entries = rebuild()
for i = 1, #entries do byTitle[entries[i].title] = entries[i] end
ok(pick(byTitle, "Earn Honor").state == "complete",
   "with no completed flag, all requirements met still reads complete")
INFO.tasks[2].completed = false
INFO.tasks[2].requirementsList[1].completed = false

-- ------------------------------------------------------------------ the objective run

-- Entry.BeginLines/EndLines exist so a SHORTER run cannot inherit a longer one's tail, which is
-- the named trap in this project's Entry contract. Nothing here ever shrank a requirement list,
-- so deleting either call left every assertion green.
local shrink = task(20, "Shrinking Task", { tracked = true }, {
    { requirementText = "- 0 / 1 first",  completed = false },
    { requirementText = "- 0 / 1 second", completed = false },
    { requirementText = "- 0 / 1 third",  completed = false },
})
INFO.tasks[#INFO.tasks + 1] = shrink
entries = rebuild()
for i = 1, #entries do byTitle[entries[i].title] = entries[i] end
ok(#pick(byTitle, "Shrinking Task").lines == 3, "three requirements draw three lines")

shrink.requirementsList = { { requirementText = "- 0 / 1 only", completed = false } }
entries = rebuild()
for i = 1, #entries do byTitle[entries[i].title] = entries[i] end
ok(#pick(byTitle, "Shrinking Task").lines == 1,
   "and one requirement draws ONE line, with no tail left over from the longer run, got "
   .. #pick(byTitle, "Shrinking Task").lines)

-- A task with no requirements at all is not "all of its requirements are met". Without the
-- total > 0 half of that test it renders complete, which is a green title on an untouched task.
local bare = task(21, "No Requirements", { tracked = true }, {})
bare.completed = nil
INFO.tasks[#INFO.tasks + 1] = bare
entries = rebuild()
for i = 1, #entries do byTitle[entries[i].title] = entries[i] end
ok(pick(byTitle, "No Requirements").state == "active",
   "a task with an empty requirement list is active, not complete")

-- Blizzard's own flag wins when it is present. Only an ABSENT flag falls back to the tally, so
-- an explicit false with every requirement met must still read active.
local denied = task(24, "Says Not Done", { tracked = true }, {
    { requirementText = "- 1 / 1 done", completed = true },
})
INFO.tasks[#INFO.tasks + 1] = denied
entries = rebuild()
for i = 1, #entries do byTitle[entries[i].title] = entries[i] end
ok(pick(byTitle, "Says Not Done").state == "active",
   "an explicit completed=false is not overridden by the requirement tally, got "
   .. tostring(pick(byTitle, "Says Not Done").state))
INFO.tasks[#INFO.tasks] = nil

-- A plain regression guard on the rebuilt run, NOT a test of BeginLines. Deleting BeginLines
-- provably changes nothing while EndLines runs, which this file's own header and the mutation
-- battery both record as equivalent - and a comment claiming otherwise sent a reader looking
-- for discrimination that cannot exist.
rebuild()
entries = rebuild()
for i = 1, #entries do byTitle[entries[i].title] = entries[i] end
ok(#pick(byTitle, "Earn Honor").lines == 1,
   "a rebuilt entry restarts its objective run rather than appending to it, got "
   .. #pick(byTitle, "Earn Honor").lines)

-- The store default. Nothing else sets it, and with it false every row would vanish under the
-- show-only-watched filter.
ok(pick(byTitle, "Earn Honor").isTracked == true,
   "entries report themselves tracked, or the watched filter hides the whole section")

-- The id fallback, which only runs for a task the API hands back without a name.
local unnamed = task(23, "placeholder", { tracked = true })
unnamed.taskName = nil
INFO.tasks[#INFO.tasks + 1] = unnamed
entries = rebuild()
local titles23 = {}
for i = 1, #entries do titles23[entries[i].title] = true end
ok(titles23["Task 23"] == true,
   "a task with no name falls back to its id rather than to an empty row")
INFO.tasks[#INFO.tasks] = nil

INFO.tasks[#INFO.tasks] = nil
INFO.tasks[#INFO.tasks] = nil

-- ------------------------------------------------------------------ the instrument

-- DebugLine is read from /eqot status behind a pcall that would swallow a raise, and it had no
-- assertion at all. pcall here CATCHES a raise into a failure, never swallows one.
local function dbg(prov)
    local okCall, res = pcall(prov.DebugLine, prov)
    return okCall and res or nil, okCall and nil or tostring(res)
end

local text, err = dbg(p)
ok(text ~= nil, "DebugLine does not raise: " .. tostring(err))
ok(text and text:find("3 tracked (3 with an id)", 1, true) ~= nil,
   "it counts the ids GetEntries actually needs, not just the tracked flag: " .. tostring(text))

local noID = task(22, "No Id At All", { tracked = true })
noID.ID = nil
INFO.tasks[#INFO.tasks + 1] = noID
text = dbg(p)
ok(text and text:find("4 tracked (3 with an id)", 1, true) ~= nil,
   "a tracked task with no id is visible as the gap it is: " .. tostring(text))
if handlers.NEIGHBORHOOD_INITIATIVE_UPDATED then
    handlers.NEIGHBORHOOD_INITIATIVE_UPDATED()
end
local okBuild, built = pcall(p.GetEntries, p)
ok(okBuild, "a tracked task with no id does not reach store:Acquire(nil): " .. tostring(built))
ok(okBuild and #built == 3, "and it emits nothing, so the two numbers explain each other")
INFO.tasks[#INFO.tasks] = nil

ok(dbg(build({ absent = true })) ~= nil, "nor does it raise with the namespace gone")

local raiser = build({ info = INFO })
C_NeighborhoodInitiative.IsInitiativeEnabled = function() error("boom") end
ok(dbg(raiser) ~= nil, "nor when an API it asks raises")

-- The case above raises the one call already behind ask()'s pcall, so it passed while the GRAPH
-- read beside it was bare. That is the call this whole line exists to report on, and a raise in
-- it printed "DebugLine raised" in place of the diagnosis.
raiser = build({ info = INFO })
C_NeighborhoodInitiative.GetNeighborhoodInitiativeInfo = function() error("secret value") end
local raisedText = dbg(raiser)
ok(raisedText ~= nil, "nor when the graph read itself raises")
ok(raisedText and raisedText:find("loaded=raised", 1, true) ~= nil,
   "and the line says the graph read is what failed: " .. tostring(raisedText))
-- build() installs the stubbed globals, so the raising one above stays installed until the next
-- build replaces it. Everything after this point needs a clean client.
p = build({ info = INFO })

-- ------------------------------------------------------------------ the gates

ok(p:IsAvailable(), "available when the namespace and the getter are there")

p = build({ info = INFO, enabled = false })
ok(p:IsAvailable(), "IsAvailable is a capability probe and does NOT ask whether it is enabled")
ok(build({ info = nil }):IsAvailable(),
   "nor whether the info has streamed in - that changes mid-session and IsAvailable is answered once")
ok(#p:GetEntries() == 0, "but a disabled initiative emits nothing")

p = build({ info = INFO, access = false })
ok(#p:GetEntries() == 0, "nor does one this character has no access to")

p = build({ info = nil })
ok(#p:GetEntries() == 0, "nor does one whose info has not streamed in")

p = build({ info = { isLoaded = true } })
ok(#p:GetEntries() == 0, "nor does info with no tasks array at all")

p = build({ absent = true })
ok(not p:IsAvailable(), "unavailable when the namespace is missing entirely")

-- ------------------------------------------------------------------ the async fetch

p = build({ info = INFO })
ok(requested == 0, "no fetch is issued at load")
p:GetEntries()
p:GetEntries()
ok(requested == 0, "and none from the render path, however many times it runs")
ok(handlers.NEIGHBORHOOD_INITIATIVE_UPDATED ~= nil, "the update event is subscribed")
handlers.PLAYER_ENTERING_WORLD()
ok(requested == 1, "the fetch is issued from the event path")
ok(dirty >= 1, "and a repaint is asked for after it")
ok(handlers.NEIGHBORHOOD_INITIATIVE_UPDATED ~= nil, "the update event is subscribed at all")
if handlers.NEIGHBORHOOD_INITIATIVE_UPDATED then handlers.NEIGHBORHOOD_INITIATIVE_UPDATED() end
ok(dirty >= 2, "the update event asks for a repaint too")

-- ------------------------------------------------------------------ the graph cache

-- GetEntries runs inside Tracker:Render, which repaints several times a second, and
-- GetNeighborhoodInitiativeInfo builds the WHOLE graph fresh on every call - root, task array,
-- and per task a criteriaList, a requirementsList and every requirement under it. Rebuilt per
-- repaint that is a whole graph per frame of tracker activity. The count below is the only
-- thing that can tell a working cache from a rebuild: the ENTRIES are identical either way.
local function graphReads(prov)
    local okCall, line = pcall(prov.DebugLine, prov)
    return okCall and tonumber(tostring(line):match("(%d+) graph reads")) or -1
end

p = build({ info = INFO })
p:GetEntries()
local afterFirst = graphReads(p)
ok(afterFirst == 1, "the first build reads the graph once, got " .. afterFirst)

for _ = 1, 20 do p:GetEntries() end
ok(graphReads(p) == 1,
   "twenty more repaints with nothing changed read it no further times, got " .. graphReads(p))

if handlers.NEIGHBORHOOD_INITIATIVE_UPDATED then
    handlers.NEIGHBORHOOD_INITIATIVE_UPDATED()
end
p:GetEntries()
ok(graphReads(p) == 2,
   "and the update event is what lets the next one through, got " .. graphReads(p))

-- A repaint that skips the read must still hand back the SAME entries, or the cache trades one
-- bug for a worse one.
local before = #p:GetEntries()
ok(#p:GetEntries() == before and before == 3,
   "a cached pass returns the entries rather than an empty store, got " .. before)

-- The content gates are deliberately NOT cached with the graph: both are cheap boolean reads
-- and both change mid-session, which is the whole reason they sit in GetEntries rather than in
-- IsAvailable. A cached `live` would put the section to sleep for the session.
local gate = build({ info = INFO })
gate:GetEntries()
ok(#gate:GetEntries() == 3, "three tracked tasks while the initiative is live")
C_NeighborhoodInitiative.IsInitiativeEnabled = function() return false end
ok(#gate:GetEntries() == 0,
   "switching the initiative off empties the section with no event fired")
C_NeighborhoodInitiative.IsInitiativeEnabled = function() return true end
ok(#gate:GetEntries() == 3, "and switching it back on refills it, again with no event")

p = build({ info = INFO })

-- ------------------------------------------------- what the cache must NOT hold on to

-- The fetch is asynchronous, so the pass right after login routinely reads nothing at all.
-- Caching that answer pinned an empty section until an event happened by; without the cache
-- the next repaint picked the data up on its own, which is what hid the dependency.
local late = build({ info = nil })
ok(#late:GetEntries() == 0, "nothing to read yet, so nothing is emitted")
C_NeighborhoodInitiative.GetNeighborhoodInitiativeInfo = function() return INFO end
ok(#late:GetEntries() == 3,
   "and the data arriving is picked up WITHOUT an event, got " .. #late:GetEntries())

-- Blizzard's own not-ready flag says the same thing a nil does.
local half = build({ info = { isLoaded = false, tasks = {} } })
ok(#half:GetEntries() == 0, "an unloaded answer emits nothing")
C_NeighborhoodInitiative.GetNeighborhoodInitiativeInfo = function() return INFO end
ok(#half:GetEntries() == 3, "and is not cached either, got " .. #half:GetEntries())

-- A raise inside the walk must not latch. store:Begin has already wiped the bookkeeping by the
-- time one happens, and only store:Finish trims the array the cached branch hands back, so
-- clearing the flag before the walk pinned the pre-error entries for the session.
local boom = build({ info = INFO })
ok(#boom:GetEntries() == 3, "three to start")
local realClean = lastNs.Util.CleanRequirement
lastNs.Util.CleanRequirement = function() error("secret value") end
-- Invalidated first, or the cached branch returns without ever reaching the walk and the case
-- proves nothing. Guarded so a mutant that deletes the subscription fails an assertion here
-- rather than aborting the file on a nil call.
if handlers.NEIGHBORHOOD_INITIATIVE_UPDATED then
    handlers.NEIGHBORHOOD_INITIATIVE_UPDATED()
end
ok(not pcall(boom.GetEntries, boom), "the rebuild raises")
lastNs.Util.CleanRequirement = realClean
ok(#boom:GetEntries() == 3,
   "and the next pass rebuilds rather than serving the half-built answer, got "
   .. #boom:GetEntries())

p = build({ info = INFO })

-- ------------------------------------------------------------------ entry reuse

-- Entries are provider-owned and valid only until the next GetEntries. The store has to prune,
-- or a task that stops being tracked keeps rendering.
p = build({ info = INFO })
ok(#rebuild() == 3, "three to start")
INFO.tasks[2].tracked = false
ok(#rebuild() == 2, "untracking one drops it on the next build")
INFO.tasks[2].tracked = true
ok(#rebuild() == 3, "and tracking it again brings it back")

print(string.format("test_initiative: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
