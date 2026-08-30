-- luacheck: globals wipe CopyTable C_PerksActivities
--
-- Unit tests for the Traveler's Log provider, run against the SHIPPED source rather than a copy.
-- Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_endeavors.lua
--
-- THIS FILE EXISTS BECAUSE OF ONE BUG. Endeavors:DebugLine built its format string from four
-- concatenated pieces carrying nine specifiers and handed :format eight arguments, so it raised
-- on EVERY call. UI/Commands.lua wraps each provider's DebugLine in a pcall, so /eqot status
-- printed "DebugLine raised" where the instrument should have been - and this is the instrument
-- for the project's top open item, dead in the one command it exists to serve.
--
-- Nothing could see it. luacheck reads 0/0 because it cannot check format arity, the file parses,
-- and no harness touched this provider. A single call is the whole guard, which is why the cases
-- below are mostly "does it raise" across every shape the client can hand back.
--
-- The second reason: DebugLine must REPORT rather than raise. It is read from /eqot status behind
-- that pcall, so anything it cannot handle has to come back as text.

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
_G.CopyTable = function(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = (type(v) == "table") and _G.CopyTable(v) or v end
    return out
end

local function build(opts)
    opts = opts or {}
    local mods = {}

    _G.C_PerksActivities = opts.absent and nil or {
        GetTrackedPerksActivities = function()
            if opts.trackedRaises then error("secret value") end
            return opts.tracked
        end,
        GetPerksActivityInfo = function(id)
            if opts.infoRaises then error("secret value") end
            return (opts.info or {})[id]
        end,
        AddTrackedPerksActivity = function() end,
        RemoveTrackedPerksActivity = function() end,
    }
    if _G.C_PerksActivities and opts.plural ~= false then
        _G.C_PerksActivities.GetPerksActivitiesInfo = opts.plural
    end

    local ns = { Has = { PerksActivities = not opts.absent,
                         PerksActivityInfo = not opts.absent } }
    function ns:RegisterModule(n, t) mods[n] = t return t end
    function ns:GetModule(n) return mods[n] end

    assert(loadfile(repoFile("Data/Entry.lua")))("EQObjectiveTracker", ns)
    assert(loadfile(repoFile("Core/Util.lua")))("EQObjectiveTracker", ns)

    local captured
    mods.Registry = { Register = function(_, p) captured = p end }
    mods.Events   = { On = function() end }

    assert(loadfile(repoFile("Data/Providers/Endeavors.lua")))("EQObjectiveTracker", ns)
    return captured
end

-- Calls DebugLine for real. pcall is used to CATCH a raise and turn it into a failure, never to
-- swallow one - a probe that prints "RAISED" and carries on is how the arity bug survived.
local function line(p)
    local okCall, res = pcall(p.DebugLine, p)
    if not okCall then return nil, tostring(res) end
    return res
end

local function has(s, sub) return s and s:find(sub, 1, true) ~= nil end

-- ------------------------------------------------------------------ DebugLine never raises

local SHAPES = {
    { name = "nothing tracked, no plural call",
      tracked = { trackedIDs = {} } },
    { name = "two tracked and both resolve",
      tracked = { trackedIDs = { 101, 102 } },
      info = { [101] = { activityName = "Earn Honor", requirementsList = {} },
               [102] = { activityName = "Cook 5 Meals", requirementsList = {} } } },
    { name = "tracked ids that will not resolve",
      tracked = { trackedIDs = { 777 } }, info = {} },
    { name = "the trackedIDs field renamed underneath us",
      tracked = { activityIDs = { 55 }, someFlag = true } },
    { name = "GetTrackedPerksActivities returns nil outright",
      tracked = nil },
    { name = "the live shape: a month with no activities left in it",
      tracked = { trackedIDs = {} },
      plural = function() return { activePerksMonth = 8, activities = {},
        displayMonthName = "August: Showdown", secondsRemaining = 0,
        thresholds = { 1, 2, 3, 4, 5 } } end },
    { name = "the plural call nests its array one field down",
      tracked = { trackedIDs = {} },
      plural = function() return { activities = { { ID = 7, activityName = "Fish 20" } } } end },
    { name = "the plural call raises",
      tracked = { trackedIDs = {} },
      plural = function() error("bad arg") end },
    -- Every shape above hands back a VALUE, so the two calls that can RAISE were never made to.
    -- Both were unguarded while their neighbours were pcall'd, which is the shape this file's
    -- own header calls out.
    { name = "GetTrackedPerksActivities itself raises",
      trackedRaises = true },
    { name = "GetPerksActivityInfo raises on a tracked id",
      tracked = { trackedIDs = { 909 } }, infoRaises = true },
}

for _, shape in ipairs(SHAPES) do
    local p = build(shape)
    local text, err = line(p)
    ok(text ~= nil, "DebugLine does not raise: " .. shape.name .. " -> " .. tostring(err))
    if text then
        ok(has(text, "endeavors:"), "and it is the endeavors line: " .. shape.name)
    end
end

-- SHAPES[3] is "tracked ids that will not resolve" and only ever asserted that a line came
-- back, so blanking the marker left this file green and an unresolved id printed as resolved.
ok(has(line(build(SHAPES[3])), "777:UNREADABLE"),
   "an id that will not resolve is NAMED unreadable: " .. tostring(line(build(SHAPES[3]))))
ok(has(line(build(SHAPES[2])), "101:Earn Honor"),
   "while one that resolves prints its name: " .. tostring(line(build(SHAPES[2]))))

-- The whole point of the instrument is naming which of the two empty cases applies, so the
-- month and the seconds left are read as VALUES rather than left as field names.
local p = build(SHAPES[6])
ok(has(line(p), "month August: Showdown, 0 seconds left"),
   "an empty activities array says which month it is empty for: " .. tostring(line(p)))

-- Truncating in silence is what hid `tasks` and `tracked` from two earlier readings.
p = build({ tracked = { trackedIDs = {} }, plural = function()
    local t = {}
    for i = 1, 40 do t["field" .. i] = i end
    t.activities = {}
    return t
end })
ok(has(line(p), "MORE, cap"), "a truncated field list says so rather than hiding it")

-- ------------------------------------------------------------------ the absent client

p = build({ absent = true })
local text = line(p)
ok(text ~= nil, "DebugLine does not raise with the namespace gone")
ok(has(text, "absent"), "and it says the API is absent: " .. tostring(text))
ok(not p:IsAvailable(), "and the provider reports itself unavailable")

-- ------------------------------------------------------------------ entries

p = build(SHAPES[2])
local entries = p:GetEntries()
ok(#entries == 2, "both tracked activities emit, got " .. #entries)
ok(entries[1].groupID == "endeavors", "into the endeavors group")

p = build(SHAPES[3])
ok(#p:GetEntries() == 0, "an id that will not resolve emits nothing rather than a blank row")

p = build(SHAPES[5])
ok(#p:GetEntries() == 0, "a nil return emits nothing")

-- Core/Util.lua owns the requirement cleaner and both providers share it.
p = build({ tracked = { trackedIDs = { 1 } },
            info = { [1] = { activityName = "Walk", requirementsList = {
                { requirementText = "- 1 / 15 Quests completed", completed = false } } } } })
entries = p:GetEntries()
ok(entries[1].lines[1].text == "1/15 Quests completed",
   "the shared cleaner strips the bullet and the padded fraction: "
   .. tostring(entries[1].lines[1].text))

print(string.format("test_endeavors: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
