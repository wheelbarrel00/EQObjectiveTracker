-- Unit tests for the zone headers, run against the SHIPPED source rather than a copy.
-- Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_zone_headers.lua
--
-- WHAT THE FEATURE IS. With "Show zone headers" on, the Quests and Campaign sections group their
-- quests under the quest log heading each one sits under (entry.zone), one header per heading,
-- each collapsing on its own. The heading holding a quest on the player's map comes first, then
-- the rest in quest log order, or every heading A to Z. The sort still applies inside a zone, and
-- a Manual drag stays inside its zone.
--
-- WHAT IS HELD HERE. Data/ZoneGroups.lua WHOLE: the runs, their order in both modes (Alphabetical
-- with and without the client's strcmputf8i, stubbed), the counts, the current flag asked quest by
-- quest, later passes on the same module (each fixture leaves a current flag, a place, a total or a
-- run behind where it would show), and the status line with both sections and one that grouped
-- nothing. Data/Feed.lua WHOLE over stub modules, so the tally sees filtered quests in provider
-- order, each section's own, never a duplicate another provider showed, and the grouping runs after
-- the sort. UI/ZoneHeaders.lua WHOLE over stub frames that record the frame type and each region's
-- draw layer: a Button, the bar under the divider under the text, the bar's white texture, the
-- divider's height and edges, the header text and its anchors edge to edge, count, sign, look on all
-- three strings, height (an empty string measures 0, so styling before the text shows), the render
-- generation, pooling, showing again, and the collapse click with its render before its scroll.
-- UI/DragDrop.lua WHOLE for the drag scope, Campaign's included. The row loop SLICED out of
-- Tracker:Render and driven (at a gap and indent unlike the defaults, both sections, the settings
-- handed to each header, the row builder, item buttons and countdowns), and scrollIntoView sliced
-- with its two callers. The DB module is Core/DB.lua's own accessors, sliced, and the tracker
-- stub's Render must be called as a method, so a dot call raises here as it does in game.
--
-- OUT OF SCOPE BY CONSTRUCTION: the rest of Render is too large to drive, so its share (the pool
-- reset and sweep, the indent and the zone tops read once per pass) is pinned by comment-stripped
-- whole statements at the end, with the zone label in Row (the statement and a count of its
-- writes), the status line, the defaults and the TOC lines. How the headers look on screen is an
-- in-game question.

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
end

local function readFile(rel)
    local fh = assert(io.open(repoFile(rel), "r"))
    local src = fh:read("*a")
    fh:close()
    return src
end

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end

local function case(name, fn)
    print("== " .. name)
    local good, err = pcall(fn)
    ok(good, name .. " raised: " .. tostring(err))
end

local function count(src, needle)
    local n, from = 0, 1
    while true do
        local i = src:find(needle, from, true)
        if not i then return n end
        n, from = n + 1, i + 1
    end
end

local function stripComments(src)
    src = src:gsub("%-%-%[(=*)%[.-%]%1%]", "")
    return (src:gsub("%-%-[^\n]*", ""))
end

local function slice(rel, fromAnchor, toAnchor)
    local src = readFile(rel)
    local function only(anchor)
        local n = count(src, anchor)
        assert(n == 1, ("anchor matched %d times in %s (need exactly 1): %s"):format(n, rel, anchor))
        return src:find(anchor, 1, true)
    end
    local from, to = only(fromAnchor), only(toAnchor)
    assert(to > from, "anchors are out of order in " .. rel .. ": " .. fromAnchor)
    return src:sub(from, to - 1)
end

local function wipe(t)
    for k in pairs(t) do t[k] = nil end
    return t
end

-- A module table per name, the way ns:RegisterModule hands them out.
local function newNS(mods)
    mods = mods or {}
    local ns = {
        modules = mods,
        Util = {},
        L = setmetatable({}, { __index = function(_, k) return k end }),
    }
    function ns:RegisterModule(name, t) mods[name] = t; return t end
    function ns:GetModule(name) return mods[name] end
    return ns
end

local function load(rel, ns, env)
    local chunk = assert(loadfile(repoFile(rel)))
    setfenv(chunk, setmetatable(env or {}, { __index = _G }))
    chunk("EQObjectiveTracker", ns)
end

-- Core/DB.lua's own DB:Tracker, DB:General and DB:Char, sliced, over a stub profile. Each reads
-- through self, so a call written DB.Char() raises here as it does in game. st.cfg and st.char
-- are read at every call, so a case may swap either table.
local accessors
local function realDB(st)
    if not accessors then
        local src = readFile("Core/DB.lua")
        local found = {}
        for _, name in ipairs({ "Tracker", "General", "Char" }) do
            local head = "\nfunction DB:" .. name .. "()\n"
            local a = src:find(head, 1, true)
            local b = a and src:find("\nend\n", a + 1, true)
            assert(a and b and not src:find(head, a + 1, true), "Core/DB.lua defines DB:" .. name .. " once")
            local holder = {}
            local chunk = assert(loadstring(src:sub(a + 1, b + 4), "DB:" .. name))
            setfenv(chunk, { DB = holder })
            chunk()
            found[name] = holder[name]
        end
        accessors = found
    end
    local saved = setmetatable({}, { __index = function(_, k)
        if k == "profile" then return { tracker = st.cfg, general = st.general } end
        if k == "char" then return st.char end
    end })
    local DB = { db = saved }
    for name, fn in pairs(accessors) do DB[name] = fn end
    return DB
end

-- ------------------------------------------------------------------- Data/ZoneGroups.lua

local function entry(id, zone, title, providerID, groupID)
    return { id = id, zone = zone, title = title or tostring(id), providerID = providerID or "quests",
             groupID = groupID or "quests" }
end

-- current maps a zone to what IsCurrentZone answers for its quests. A zone not in it answers false.
-- opts.byID answers by quest id instead, so two quests in one heading can differ. opts.cmp stands in
-- for the client's strcmputf8i, which plain Lua does not have.
local function zoneRig(cfg, current, opts)
    opts = opts or {}
    local st = { cfg = cfg, char = { zonesCollapsed = {} }, asked = 0, compared = 0 }
    local provider = { id = "quests" }
    if not opts.noIsCurrent then
        function provider:IsCurrentZone(e)
            st.asked = st.asked + 1
            if opts.byID then return opts.byID[e.id] == true end
            if current[e.zone] ~= nil then return current[e.zone] end
            return false
        end
    end
    st.feedGroups = {}
    local mods = {
        DB = realDB(st),
        Registry = { Get = function(_, id) if id == "quests" then return provider end end },
        Feed = { Group = function(_, id) return st.feedGroups[id] end },
    }
    local ns = newNS(mods)
    local env = { wipe = wipe }
    if opts.cmp then
        env.strcmputf8i = function(a, b)
            st.compared = st.compared + 1
            return opts.cmp(a, b)
        end
    end
    load("Data/ZoneGroups.lua", ns, env)
    st.Z = mods.ZoneGroups
    return st
end

-- One Feed pass by hand: every emitted entry noted in log order, the visible ones in the order the
-- sort left them, then the grouping.
local function zonePass(st, groups)
    st.Z:Begin()
    local byGroup = {}
    for id, spec in pairs(groups) do
        for _, e in ipairs(spec.log) do st.Z:Note(id, e) end
        local g = spec.g or { id = id, entries = {} }
        g.visibleCount = #spec.shown
        for i, e in ipairs(spec.shown) do g.entries[i] = e end
        byGroup[id] = g
    end
    st.Z:Build(byGroup, st.cfg)
    return byGroup
end

local function zonesOf(g)
    local out = {}
    for r = 1, g.zoneCount or 0 do out[r] = g.zoneRuns[r].zone end
    return table.concat(out, ",")
end

local function idsOf(g, from, to)
    local out = {}
    for i = from or 1, to or g.visibleCount do out[#out + 1] = tostring(g.entries[i].id) end
    return table.concat(out, ",")
end

-- The fixture is built so three orders all differ. The log lists Zeta, Alpha, Mid. A to Z is
-- Alpha, Mid, Zeta. The sort shows Mid's first quest before anything else.
local function fixture()
    local z1, z2 = entry(1, "Zeta", "b"), entry(2, "Zeta", "x")
    local a1     = entry(3, "Alpha", "c")
    local m1, m2 = entry(4, "Mid", "a"), entry(5, "Mid", "d")
    return {
        log   = { z1, z2, a1, m1, m2 },
        shown = { m1, z1, a1, m2 },
    }
end

case("off, nothing is grouped and the sorted order stands", function()
    local st = zoneRig({ zoneHeaders = false }, { Alpha = true })
    local g = zonePass(st, { quests = fixture() }).quests
    ok(g.zoneCount == 0, "no runs: " .. tostring(g.zoneCount))
    ok(idsOf(g) == "4,1,3,5", "the sort's order is untouched: " .. idsOf(g))
    local unset = zoneRig({}, { Alpha = true })
    ok(zonePass(unset, { quests = fixture() }).quests.zoneCount == 0, "and unset reads as off")
end)

case("current zone first, then the rest in quest log order", function()
    local st = zoneRig({ zoneHeaders = true }, { Alpha = true })
    local g = zonePass(st, { quests = fixture() }).quests
    ok(zonesOf(g) == "Alpha,Zeta,Mid", "the current heading leads, then log order: " .. zonesOf(g))
    ok(idsOf(g) == "3,1,4,5", "each zone's quests sit together in that order: " .. idsOf(g))
    local r = g.zoneRuns
    ok(r[1].first == 1 and r[1].last == 1 and r[2].first == 2 and r[2].last == 2
       and r[3].first == 3 and r[3].last == 4, "and each run names its own slice of the entries")
    ok(r[1].current == true and r[2].current == false and r[3].current == false,
       "only the heading with a quest on the map is current")
end)

case("unset order reads as current zone first, and nothing current falls to log order", function()
    local st = zoneRig({ zoneHeaders = true, zoneHeaderOrder = "bogus" }, {})
    local g = zonePass(st, { quests = fixture() }).quests
    ok(zonesOf(g) == "Zeta,Alpha,Mid", "log order with nothing current: " .. zonesOf(g))
end)

case("alphabetical ignores the current zone", function()
    local st = zoneRig({ zoneHeaders = true, zoneHeaderOrder = "alpha" }, { Zeta = true })
    local g = zonePass(st, { quests = fixture() }).quests
    ok(zonesOf(g) == "Alpha,Mid,Zeta", "A to Z: " .. zonesOf(g))
    ok(g.zoneRuns[3].current == true, "though the current flag is still worked out")
    local v1, v2 = entry(1, "Voidstorm"), entry(2, "Void Assaults")
    local st2 = zoneRig({ zoneHeaders = true, zoneHeaderOrder = "alpha" }, {})
    local g2 = zonePass(st2, { quests = { log = { v1, v2 }, shown = { v1, v2 } } }).quests
    ok(zonesOf(g2) == "Void Assaults,Voidstorm", "byte order, as the Zone sort uses: " .. zonesOf(g2))
    local lo, up = entry(3, "alpha"), entry(4, "Beta")
    local st3 = zoneRig({ zoneHeaders = true, zoneHeaderOrder = "alpha" }, {})
    local g3 = zonePass(st3, { quests = { log = { lo, up }, shown = { lo, up } } }).quests
    ok(zonesOf(g3) == "Beta,alpha", "with no client compare, byte order puts capitals first: " .. zonesOf(g3))
end)

-- A stand-in for the client's compare for translated names. It folds case and reads the two bytes
-- of a capital O with two dots as an o, so its order differs from byte order. Whether the real one
-- sorts that letter beside O is unmeasured: one strcmputf8i call on a German client settles it. It
-- answers -2 and 3 rather than -1 and 1, since only the sign is promised.
local OUML = string.char(195, 150)
local function fold(s) return (s:gsub(OUML, "o"):lower()) end
local function utf8cmp(a, b)
    local x, y = fold(a), fold(b)
    if x < y then return -2 elseif x > y then return 3 end
    return 0
end

case("alphabetical goes by the client's compare where the client has one", function()
    local w, o = entry(1, "Westfall"), entry(2, OUML .. "stliche")
    local b, a = entry(3, "Beta"), entry(4, "alpha")
    local st = zoneRig({ zoneHeaders = true, zoneHeaderOrder = "alpha" }, {}, { cmp = utf8cmp })
    local g = zonePass(st, { quests = { log = { w, o, b, a }, shown = { w, o, b, a } } }).quests
    local want = table.concat({ "alpha", "Beta", OUML .. "stliche", "Westfall" }, ",")
    ok(zonesOf(g) == want, "case folded, the accented name with its base letter: " .. zonesOf(g))
    ok(st.compared > 0, "and the compare was asked")

    local m1, m2, a1 = entry(5, "mid"), entry(6, "Mid"), entry(7, "alpha")
    local st2 = zoneRig({ zoneHeaders = true, zoneHeaderOrder = "alpha" }, {}, { cmp = utf8cmp })
    local g2 = zonePass(st2, { quests = { log = { m1, m2, a1 }, shown = { m1, m2, a1 } } }).quests
    ok(zonesOf(g2) == "alpha,Mid,mid", "two names it calls equal fall back to byte order: " .. zonesOf(g2))

    local even = function() return 0 end
    local x1, x2, x3, x4 = entry(8, "mid"), entry(9, "Mid"), entry(10, "alpha"), entry(11, "Beta")
    local st3 = zoneRig({ zoneHeaders = true, zoneHeaderOrder = "alpha" }, {}, { cmp = even })
    local g3 = zonePass(st3, { quests = { log = { x1, x2, x3, x4 }, shown = { x1, x2, x3, x4 } } }).quests
    ok(zonesOf(g3) == "Beta,Mid,alpha,mid", "a compare that calls every pair equal leaves byte order: " .. zonesOf(g3))

    local cur = zoneRig({ zoneHeaders = true }, { Westfall = true }, { cmp = utf8cmp })
    local g4 = zonePass(cur, { quests = { log = { w, o, b, a }, shown = { w, o, b, a } } }).quests
    ok(zonesOf(g4) == table.concat({ "Westfall", OUML .. "stliche", "Beta", "alpha" }, ",") and cur.compared == 0,
       "and current zone first never asks it: " .. zonesOf(g4))
end)

case("a heading's place is where the log first shows it", function()
    local z1, a1, z2 = entry(1, "Zeta"), entry(2, "Alpha"), entry(3, "Zeta")
    local st = zoneRig({ zoneHeaders = true }, {})
    local g = zonePass(st, { quests = { log = { z1, a1, z2 }, shown = { a1, z1, z2 } } }).quests
    ok(zonesOf(g) == "Zeta,Alpha", "a heading seen again later keeps its first place: " .. zonesOf(g))
end)

case("a shown quest the tally never saw goes after every heading it did", function()
    local z1, a1, x1 = entry(1, "Zeta"), entry(2, "Alpha"), entry(3, "Stray")
    local st = zoneRig({ zoneHeaders = true }, {})
    local g = zonePass(st, { quests = { log = { z1, a1 }, shown = { x1, a1, z1 } } }).quests
    ok(zonesOf(g) == "Zeta,Alpha,Stray", "last, with no place of its own: " .. zonesOf(g))
end)

case("the sort still applies inside a zone", function()
    local m1, m2, m3 = entry(1, "Mid", "c"), entry(2, "Mid", "a"), entry(3, "Mid", "b")
    local st = zoneRig({ zoneHeaders = true }, {})
    local g = zonePass(st, { quests = { log = { m1, m2, m3 }, shown = { m2, m3, m1 } } }).quests
    ok(idsOf(g) == "2,3,1", "the zone keeps the order the sort gave it: " .. idsOf(g))
end)

case("counts: shown in the zone, out of every quest the zone was handed", function()
    local st = zoneRig({ zoneHeaders = true }, { Alpha = true })
    local g = zonePass(st, { quests = fixture() }).quests
    local byZone = {}
    for r = 1, g.zoneCount do byZone[g.zoneRuns[r].zone] = g.zoneRuns[r] end
    ok(byZone.Zeta.count == 1 and byZone.Zeta.total == 2, "a filtered quest counts in the total only: "
       .. byZone.Zeta.count .. "/" .. byZone.Zeta.total)
    ok(byZone.Mid.count == 2 and byZone.Mid.total == 2, "Mid 2/2")
    ok(byZone.Alpha.count == 1 and byZone.Alpha.total == 1, "Alpha 1/1")
end)

case("a heading whose quests are all filtered draws no header", function()
    local h1 = entry(9, "Hidden")
    local f = fixture()
    table.insert(f.log, 1, h1)
    local st = zoneRig({ zoneHeaders = true }, { Alpha = true })
    local g = zonePass(st, { quests = f }).quests
    ok(zonesOf(g) == "Alpha,Zeta,Mid", "no run for it: " .. zonesOf(g))
end)

case("several current headings keep quest log order among themselves", function()
    local st = zoneRig({ zoneHeaders = true }, { Mid = true, Zeta = true })
    local g = zonePass(st, { quests = fixture() }).quests
    ok(zonesOf(g) == "Zeta,Mid,Alpha", "both current ones first, in log order: " .. zonesOf(g))
end)

case("only a true answer makes a heading current", function()
    local st = zoneRig({ zoneHeaders = true }, { Mid = "yes" })
    local g = zonePass(st, { quests = fixture() }).quests
    ok(zonesOf(g) == "Zeta,Alpha,Mid", "a truthy non-true answer is not current: " .. zonesOf(g))
    local st2 = zoneRig({ zoneHeaders = true }, {}, { noIsCurrent = true })
    local good = pcall(function() zonePass(st2, { quests = fixture() }) end)
    ok(good, "a provider with no IsCurrentZone is not asked")
end)

case("a heading asks the map once it is known to be current", function()
    local a1, a2, a3 = entry(1, "Alpha"), entry(2, "Alpha"), entry(3, "Alpha")
    local st = zoneRig({ zoneHeaders = true }, { Alpha = true })
    zonePass(st, { quests = { log = { a1, a2, a3 }, shown = { a1, a2, a3 } } })
    ok(st.asked == 1, "one question for three quests: " .. st.asked)
end)

case("a heading is current when a later quest in it is on the map, not only its first", function()
    local z1, a1, a2 = entry(1, "Zeta"), entry(2, "Alpha"), entry(3, "Alpha")
    local st = zoneRig({ zoneHeaders = true }, {}, { byID = { [3] = true } })
    local g = zonePass(st, { quests = { log = { z1, a1, a2 }, shown = { z1, a1, a2 } } }).quests
    ok(zonesOf(g) == "Alpha,Zeta" and g.zoneRuns[1].current == true,
       "the second Alpha quest makes Alpha current: " .. zonesOf(g))
    ok(st.asked == 3, "every quest asked until one answers: " .. st.asked)
end)

case("only Quests and Campaign are grouped", function()
    local st = zoneRig({ zoneHeaders = true }, { Alpha = true })
    local c1, c2 = entry(1, "Camp B", nil, "quests", "campaign"), entry(2, "Camp A", nil, "quests", "campaign")
    local w1 = entry(3, "Alpha", nil, "quests", "achievements")
    local byGroup = zonePass(st, {
        campaign     = { log = { c1, c2 }, shown = { c1, c2 } },
        achievements = { log = { w1 }, shown = { w1 } },
    })
    ok(byGroup.campaign.zoneCount == 2, "Campaign is grouped")
    ok(byGroup.achievements.zoneCount == 0 and idsOf(byGroup.achievements) == "3",
       "any other section is left alone")
end)

case("an empty section has no runs, and entries past the count are never moved", function()
    local st = zoneRig({ zoneHeaders = true }, {})
    local stale = entry(99, "Alpha")
    local g = { id = "quests", entries = { [1] = stale } }
    local byGroup = zonePass(st, { quests = { log = {}, shown = {}, g = g } })
    ok(byGroup.quests.zoneCount == 0, "no runs for nothing shown")
    local m1, m2 = entry(1, "Mid"), entry(2, "Alpha")
    local g2 = { id = "quests", entries = { m1, m2, stale } }
    local b2 = zonePass(st, { quests = { log = { m1, m2 }, shown = { m1, m2 }, g = g2 } })
    ok(b2.quests.zoneCount == 2 and b2.quests.entries[3] == stale, "a leftover past the count stays where it was")
end)

case("a quest with no heading groups under an empty name", function()
    local n1, a1 = entry(1, nil), entry(2, "Alpha")
    local st = zoneRig({ zoneHeaders = true }, {})
    local g = zonePass(st, { quests = { log = { n1, a1 }, shown = { a1, n1 } } }).quests
    ok(zonesOf(g) == ",Alpha", "its run comes where the log put it, named empty: " .. zonesOf(g))
end)

-- Each fixture leaves something from the pass before where it would change the answer: a run that
-- was current, a slot ranked or counted another way, a leftover run that would sort first.
case("a second pass on the same module starts clean", function()
    local a1, a2, m1, z1 = entry(1, "Alpha"), entry(4, "Alpha"), entry(2, "Mid"), entry(3, "Zeta")
    local cur = { Mid = true, Zeta = true }
    local st = zoneRig({ zoneHeaders = true }, cur)
    zonePass(st, { quests = { log = { a1, m1, z1 }, shown = { a1, m1, z1 } } })
    cur.Mid, cur.Zeta = nil, nil
    local g = zonePass(st, { quests = { log = { a1 }, shown = { a1 } } }).quests
    ok(zonesOf(g) == "Alpha" and g.entries[1] == a1,
       "a heading gone from the log is gone, and no run from the pass before sorts in: " .. zonesOf(g))
    ok(#g.zoneRuns == 1, "and the run list is trimmed to it: " .. #g.zoneRuns)

    local here = { Alpha = true }
    local st2 = zoneRig({ zoneHeaders = true }, here)
    zonePass(st2, { quests = { log = { a1, m1 }, shown = { a1, m1 } } })
    here.Alpha = nil
    local g2 = zonePass(st2, { quests = { log = { a1, m1 }, shown = { m1, a1 } } }).quests
    ok(zonesOf(g2) == "Alpha,Mid" and g2.zoneRuns[1].current == false and g2.zoneRuns[2].current == false,
       "a slot that was current is not current now, so log order: " .. zonesOf(g2))

    local st3 = zoneRig({ zoneHeaders = true }, {})
    zonePass(st3, { quests = { log = { a1, m1 }, shown = { a1, m1 } } })
    local g3 = zonePass(st3, { quests = { log = { m1, a1 }, shown = { a1, m1 } } }).quests
    ok(zonesOf(g3) == "Mid,Alpha", "the log order is this pass's, not the slot's old place: " .. zonesOf(g3))

    local st4 = zoneRig({ zoneHeaders = true }, {})
    zonePass(st4, { quests = { log = { a1 }, shown = { a1 } } })
    local g4 = zonePass(st4, { quests = { log = { a1, a2 }, shown = { a1 } } }).quests
    ok(g4.zoneRuns[1].total == 2, "totals are this pass's, not the slot's old one: " .. g4.zoneRuns[1].total)

    local x1, x2, x3 = entry(7, "X"), entry(8, "X"), entry(9, "X")
    zonePass(st, { quests = { log = { x1, x2, x3 }, shown = { x1, x2, x3 } } })
    local g5 = zonePass(st, { quests = { log = { x1 }, shown = { x1 } } }).quests
    local run = g5.zoneRuns[1]
    ok(run.count == 1 and run.entries[2] == nil and run.entries[3] == nil,
       "a run that shrinks keeps no quest from the pass before")
    ok(run.entries[1] == x1 and g5.entries[1] == x1,
       "and its first slot holds this pass's quest, not the one a reused run kept")
    local off = zonePass(zoneRig({ zoneHeaders = false }, {}), { quests = fixture() }).quests
    ok(off.zoneCount == 0, "and switched off, a pass leaves no runs")
end)

case("the status line", function()
    local st = zoneRig({ zoneHeaders = false }, {})
    ok(st.Z:DebugLine() == "zone headers: off", "off: " .. st.Z:DebugLine())
    local cur = zoneRig({ zoneHeaders = true }, { Alpha = true })
    cur.char.zonesCollapsed = { ["quests:Mid"] = true, ["quests:Gone"] = false }
    cur.feedGroups = zonePass(cur, { quests = fixture() })
    local line = cur.Z:DebugLine()
    ok(line == "zone headers: on, order current zone first, 1 collapsed | quests 3 zone(s), current: Alpha",
       "on: " .. line)
    cur.feedGroups.campaign = { zoneCount = 0, zoneRuns = {} }
    local skipped = cur.Z:DebugLine()
    ok(skipped == line, "a section that grouped nothing is not listed: " .. skipped)
    local both = zoneRig({ zoneHeaders = true }, { Alpha = true, Camp = true })
    local c1, c2 = entry(21, "Camp", nil, "quests", "campaign"), entry(22, "Other", nil, "quests", "campaign")
    both.feedGroups = zonePass(both, { quests = fixture(), campaign = { log = { c1, c2 }, shown = { c2, c1 } } })
    local two = both.Z:DebugLine()
    ok(two == "zone headers: on, order current zone first, 0 collapsed | campaign 2 zone(s), current: Camp"
       .. " | quests 3 zone(s), current: Alpha", "Campaign first, then Quests: " .. two)
    cur.cfg.zoneHeaderOrder = "alpha"
    ok(cur.Z:DebugLine():find("order alphabetical, ", 1, true) ~= nil, "names the alphabetical order")
    local none = zoneRig({ zoneHeaders = true }, {})
    none.feedGroups = {}
    ok(none.Z:DebugLine() == "zone headers: on, order current zone first, 0 collapsed | nothing grouped",
       "nothing drawn: " .. none.Z:DebugLine())
    local nowhere = zoneRig({ zoneHeaders = true }, {})
    nowhere.feedGroups = zonePass(nowhere, { quests = fixture() })
    ok(nowhere.Z:DebugLine():find("current: none", 1, true) ~= nil, "and says when no heading is current")
end)

-- ------------------------------------------------------------------- Data/Feed.lua, whole

-- opts.wq is a world quest list from a provider ahead of the quests one in the same id space, so a
-- quest it shows is a duplicate when the quests provider hands it over too.
local function feedRig(cfg, opts)
    opts = opts or {}
    local st = { cfg = cfg, char = {} }
    local provider = { id = "quests", _available = true, idSpace = "quest", list = opts.list or {} }
    function provider:GetEntries() return self.list end
    function provider:IsCurrentZone(e) return e.zone == (opts.current or "Alpha") end
    local active, byID = { provider }, { quests = provider }
    if opts.wq then
        local wq = { id = "worldquests", _available = true, idSpace = "quest", list = opts.wq }
        function wq:GetEntries() return self.list end
        table.insert(active, 1, wq)
        byID.worldquests = wq
    end
    local mods = {
        DB = realDB(st),
        Registry = {
            Active = function() return active end,
            Get = function(_, id) return byID[id] end,
        },
        Filter = { BeginPass = function() end, Visible = function(_, e) return not e.filtered end },
        Sort = { For = function() return function(a, b) return a.title < b.title end end },
        Entry = { Validate = function() return true end },
        ManualOrder = { Get = function() return nil end },
        Distance = { Sync = function() end },
    }
    local ns = newNS(mods)
    load("Data/ZoneGroups.lua", ns, { wipe = wipe })
    load("Data/Feed.lua", ns, { wipe = wipe })
    st.Feed = mods.Feed
    return st
end

case("Feed tallies every quest in log order and groups after the sort", function()
    local z1, z2 = entry(1, "Zeta", "b"), entry(2, "Zeta", "x")
    z2.filtered = true
    local a1     = entry(3, "Alpha", "c")
    local m1, m2 = entry(4, "Mid", "a"), entry(5, "Mid", "d")
    local st = feedRig({ zoneHeaders = true }, { list = { z1, z2, a1, m1, m2 } })
    local g = st.Feed:Build().quests
    ok(zonesOf(g) == "Alpha,Zeta,Mid", "current first, then the provider's own order: " .. zonesOf(g))
    ok(idsOf(g) == "3,1,4,5", "and the runs hold the sorted quests: " .. idsOf(g))
    ok(g.zoneRuns[2].zone == "Zeta" and g.zoneRuns[2].total == 2, "the filtered Zeta quest is in its total")
    ok(g.visibleCount == 4 and g.totalCount == 5, "the section's own counts are unchanged")

    st.cfg.zoneHeaderOrder = "alpha"
    local again = st.Feed:Build().quests
    ok(zonesOf(again) == "Alpha,Mid,Zeta", "alphabetical through Feed too")
    local zeta
    for r = 1, again.zoneCount or 0 do
        if again.zoneRuns[r].zone == "Zeta" then zeta = again.zoneRuns[r] end
    end
    ok(zeta and zeta.total == 2, "a second build counts afresh: " .. tostring(zeta and zeta.total))

    st.cfg.zoneHeaders = false
    local off = st.Feed:Build().quests
    ok(off.zoneCount == 0 and idsOf(off) == "4,1,3,5", "off, Feed hands back the sort alone: " .. idsOf(off))
end)

case("Feed tallies each quest under its own section", function()
    local a1 = entry(1, "Alpha", "a")
    local c1 = entry(2, "Alpha", "b", nil, "campaign")
    local c2 = entry(3, "Alpha", "c", nil, "campaign")
    c2.filtered = true
    local st = feedRig({ zoneHeaders = true }, { list = { c1, a1, c2 } })
    local byGroup = st.Feed:Build()
    local q, c = byGroup.quests, byGroup.campaign
    ok(q.zoneCount == 1 and q.zoneRuns[1].count == 1 and q.zoneRuns[1].total == 1,
       "Quests' Alpha holds its one quest: " .. tostring(q.zoneRuns[1] and q.zoneRuns[1].total))
    ok(c and c.zoneCount == 1 and c.zoneRuns[1].count == 1 and c.zoneRuns[1].total == 2,
       "Campaign's Alpha holds its two, one filtered: " .. tostring(c and c.zoneRuns[1] and c.zoneRuns[1].total))
end)

case("a quest another provider already shows is not tallied again", function()
    local w7 = entry(7, "Alpha", "w", nil, "worldquests")
    local q7, a1 = entry(7, "Alpha", "q"), entry(1, "Alpha", "a")
    local st = feedRig({ zoneHeaders = true }, { list = { q7, a1 }, wq = { w7 } })
    local q = st.Feed:Build().quests
    ok(q.totalCount == 1 and q.visibleCount == 1, "the duplicate is not the section's either: " .. q.totalCount)
    ok(q.zoneCount == 1 and q.zoneRuns[1].total == 1,
       "and Alpha counts the one quest it shows: " .. tostring(q.zoneRuns[1] and q.zoneRuns[1].total))
end)

-- ------------------------------------------------------------------- UI/ZoneHeaders.lua

local function texture()
    local t = { shown = true, points = {} }
    function t:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
    function t:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a } end
    function t:SetGradient(dir, c1, c2) self.gradient = { dir, c1, c2 } end
    function t:SetAllPoints(rel) self.all = rel end
    function t:SetHeight(h) self.h = h end
    function t:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function t:Show() self.shown = true end
    function t:Hide() self.shown = false end
    function t:IsShown() return self.shown end
    return t
end

-- An empty string measures 0, as the client's does, and a string the font never sized answers nil.
local function fontString()
    local s = { points = {} }
    function s:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function s:SetJustifyH(j) self.justify = j end
    function s:SetWordWrap(w) self.wrap = w end
    function s:SetText(t) self.text = t end
    function s:GetText() return self.text end
    function s:SetTextColor(r, g, b) self.color = { r, g, b } end
    function s:GetStringHeight()
        if self.text == nil or self.text == "" then return 0 end
        return self.size
    end
    return s
end

-- Each region records the draw layer it was made on.
local function button(parent)
    local f = { parent = parent, shown = true, points = {}, scripts = {}, h = 0 }
    function f:SetHeight(h) self.h = h end
    function f:GetHeight() return self.h end
    function f:RegisterForClicks(...) self.clicks = { ... } end
    function f:CreateTexture(_, layer)
        local t = texture()
        t.layer = layer
        return t
    end
    function f:CreateFontString(_, layer, template)
        local s = fontString()
        s.layer, s.template = layer, template
        return s
    end
    function f:SetScript(e, fn) self.scripts[e] = fn end
    function f:GetParent() return self.parent end
    function f:SetParent(p) self.parent = p end
    function f:ClearAllPoints() self.points = {} end
    function f:SetPoint(p, rel, relP, x, y) self.points[#self.points + 1] = { p, rel, relP, x, y } end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    return f
end

local function color(r, g, b, a)
    local c = { r, g, b, a }
    function c:SetRGBA(r2, g2, b2, a2) self[1], self[2], self[3], self[4] = r2, g2, b2, a2 end
    return c
end

-- A string measures 15 plus its size offset, plus opts.frac, and opts.noHeight leaves it unsized.
-- opts.noClass is a client with no class color to give. st.calls holds the tracker's renders and
-- scrolls in the order they came, and st.kinds the frame type of every header built.
local function headerRig(cfg, opts)
    opts = opts or {}
    local st = { cfg = cfg or {}, char = {}, renders = 0, scrolled = {}, calls = {}, built = 0, clickThrough = false,
                 kinds = {} }
    local mods = {
        DB = realDB(st),
        Media = { ApplyFont = function(_, fs, delta)
            fs.delta = delta
            if opts.noHeight then fs.size = nil else fs.size = 15 + (delta or 0) + (opts.frac or 0) end
        end },
        Tracker = {
            Render = function(self)
                assert(self == st.mods.Tracker, "Tracker:Render is called as a method")
                st.renders = st.renders + 1
                st.calls[#st.calls + 1] = "render"
            end,
            ScrollZoneIntoView = function(_, k)
                st.scrolled[#st.scrolled + 1] = k
                st.calls[#st.calls + 1] = "scroll " .. k
            end,
            IsClickThrough = function(self) st.askedBy = self; return st.clickThrough end,
        },
    }
    local ns = newNS(mods)
    ns.Util.GetPlayerClassColor = function()
        if opts.noClass then return nil end
        return 0.1, 0.2, 0.3
    end
    load("UI/ZoneHeaders.lua", ns, {
        CreateFrame = function(kind, _, parent)
            st.built = st.built + 1
            st.kinds[#st.kinds + 1] = kind
            return button(parent)
        end,
        CreateColor = color,
        wipe = wipe,
    })
    st.H, st.mods = mods.ZoneHeaders, mods
    return st
end

local function run(zone, cnt, total) return { zone = zone, count = cnt, total = total } end

local function near(a, b) return math.abs(a - b) < 1e-6 end
local function rgb(c, r, g, b)
    return type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number"
        and near(c[1], r) and near(c[2], g) and near(c[3], b)
end

-- The sticky band copies a zone's header from the pooled one it was drawn into this pass.
case("Place hands back the header it used, and a band copy mirrors it", function()
    local st = headerRig({})
    local content = button()
    st.H:Begin()
    local _, _, h1 = st.H:Place(content, "quests", run("Alpha", 2, 3), 0, st.cfg)
    local _, folded, h2 = st.H:Place(content, "campaign", run("Alpha", 1, 1), 30, st.cfg)
    ok(h1 == st.H.frames[1] and h2 == st.H.frames[2] and folded == false, "the pooled header it drew into")
    local copy = st.H:NewHeader(button())
    ok(st.H:Mirror(copy, "quests:Alpha") == true, "a zone drawn this pass can be mirrored")
    ok(copy.text.text == "Alpha" and copy.count.text == "2/3" and copy.collapse.text == "-",
       "its text, count and sign copied")
    ok(copy.groupID == "quests" and copy.zone == "Alpha", "and what a click on the copy collapses")
    st.H:Mirror(copy, "campaign:Alpha")
    ok(copy.groupID == "campaign" and copy.count.text == "1/1", "each zone keyed by its own section")
    ok(st.H:Mirror(copy, "quests:Mid") == false, "a zone that drew nothing cannot be")
    st.H:Begin()
    ok(st.H:Mirror(copy, "quests:Alpha") == false, "and a new pass forgets the last one's headers")
    st.H:Begin()
    st.H:Place(content, "quests", run("Mid", 1, 1), 0, st.cfg)
    ok(st.H:Mirror(copy, "quests:Mid") == true and copy.text.text == "Mid", "the header slot it reused now mirrors Mid")
    local outside = st.H:NewHeader(button())
    st.H:Draw(outside, content, "quests", run("Gone", 1, 1), 0, st.cfg)
    ok(st.H:Mirror(copy, "quests:Gone") == false, "a header drawn outside the pool is never mirrored")
end)

-- The Appearance preview draws its own headers through this pair, never through the pool.
case("a header made outside the pool is drawn the way a pooled one is", function()
    local st = headerRig({})
    local parent, content = button(), button()
    local h = st.H:NewHeader(parent)
    ok(st.built == 1 and #st.H.frames == 0, "made, and kept out of the pool")
    ok(h.parent == parent and type(h.scripts.OnClick) == "function", "a whole header, click and all")
    local height, folded = st.H:Draw(h, content, "quests", run("Ashwood Glen", 2, 2), 30, st.cfg)
    ok(height == 21 and folded == false, "answers its height and that it is open")
    ok(h.text.text == "Ashwood Glen" and h.count.text == "2/2" and h.collapse.text == "-", "carries the run")
    ok(h.parent == content and h.points[1][5] == -30 and h.shown, "placed in the content it was handed, at its y")
    st.H:Begin()
    st.H:Place(content, "quests", run("Mid", 1, 1), 0, st.cfg)
    st.H:Sweep()
    ok(st.H.frames[1] ~= h and h.shown, "the pool never takes it over, and a sweep never hides it")
end)

case("a header shows its zone, its count and its sign, at its place", function()
    local st = headerRig({})
    local content = button()
    st.H:Begin()
    local h1, folded = st.H:Place(content, "quests", run("Eversong Woods", 3, 5), 40, st.cfg)
    local f = st.H.frames[1]
    ok(f.text.text == "Eversong Woods", "the zone name: " .. tostring(f.text.text))
    ok(f.count.text == "3/5", "shown out of total while the count option is unset: " .. tostring(f.count.text))
    ok(f.collapse.text == "-" and folded == false, "expanded, a minus")
    ok(h1 == 21 and f.h == 21, "as tall as the text and four: " .. tostring(h1) .. ", " .. tostring(f.h))
    local p = f.points
    ok(#p == 2 and p[1][1] == "TOPLEFT" and p[1][2] == content and p[1][3] == "TOPLEFT" and p[1][4] == 0
       and p[1][5] == -40 and p[2][1] == "TOPRIGHT" and p[2][2] == content and p[2][3] == "TOPRIGHT"
       and p[2][4] == 0 and p[2][5] == -40,
       "spans the content edge to edge at the y it was handed")
    ok(f.shown and f.groupID == "quests" and f.zone == "Eversong Woods", "shown, and knows what it heads")
    ok(f.clicks and f.clicks[1] == "LeftButtonUp" and f.clicks[2] == nil, "takes left clicks only")
    ok(f.text.wrap == false and f.text.justify == "LEFT", "the zone name sits on one line, left aligned")
    local tp, cp, kp = f.text.points, f.count.points, f.collapse.points
    ok(#tp == 2 and tp[1][1] == "LEFT" and tp[1][2] == 4 and tp[1][3] == 0, "the name starts 4px in")
    ok(tp[2] and tp[2][1] == "RIGHT" and tp[2][2] == f.count and tp[2][3] == "LEFT" and tp[2][4] == -6
       and tp[2][5] == 0, "and stops 6px short of the count, so a long name never runs under it")
    ok(#kp == 1 and kp[1][1] == "RIGHT" and kp[1][2] == -4 and kp[1][3] == 0, "the sign sits 4px in from the right")
    ok(#cp == 1 and cp[1][1] == "RIGHT" and cp[1][2] == f.collapse and cp[1][3] == "LEFT" and cp[1][4] == -6
       and cp[1][5] == 0, "and the count 6px left of it")

    st.cfg.showQuestTotal = false
    st.char.zonesCollapsed = { ["quests:Eversong Woods"] = true }
    st.H:Begin()
    local _, folded2 = st.H:Place(content, "quests", run("Eversong Woods", 3, 5), 0, st.cfg)
    ok(f.count.text == "3", "the shown count alone with the total switched off: " .. tostring(f.count.text))
    ok(f.collapse.text == "+" and folded2 == true, "collapsed, a plus, and says so")
    st.H:Begin()
    local _, folded3 = st.H:Place(content, "campaign", run("Eversong Woods", 1, 1), 0, st.cfg)
    ok(folded3 == false and f.collapse.text == "-", "the same zone in another section collapses apart")
end)

-- The bar sits under the divider and both under the text, so neither covers the zone name.
case("a header is a Button, its regions on their own layers", function()
    local st = headerRig({ zoneHeaderBar = true, zoneHeaderDivider = true })
    st.H:Begin()
    st.H:Place(button(), "quests", run("A", 1, 1), 0, st.cfg)
    st.H:NewHeader(button())
    ok(#st.kinds == 2 and st.kinds[1] == "Button" and st.kinds[2] == "Button",
       "pooled or not, a Button, so it takes a click: " .. table.concat(st.kinds, ","))
    local f = st.H.frames[1]
    ok(f.bar.layer == "BACKGROUND" and f.line.layer == "ARTWORK" and f.text.layer == "OVERLAY"
       and f.count.layer == "OVERLAY" and f.collapse.layer == "OVERLAY",
       "the bar, then the divider, then the text: " .. tostring(f.bar.layer) .. "," .. tostring(f.line.layer)
       .. "," .. tostring(f.text.layer) .. "," .. tostring(f.count.layer) .. "," .. tostring(f.collapse.layer))
    local c = f.bar.color
    ok(c and c[1] == 1 and c[2] == 1 and c[3] == 1 and c[4] == 1, "the bar is a white texture for its color to tint")
    ok(f.line.h == 1, "the divider is 1px tall: " .. tostring(f.line.h))
    local lp = f.line.points
    ok(#lp == 2 and lp[1][1] == "BOTTOMLEFT" and lp[1][2] == 0 and lp[1][3] == 0
       and lp[2][1] == "BOTTOMRIGHT" and lp[2][2] == 0 and lp[2][3] == 0,
       "and runs along the bottom edge, end to end")
end)

case("the height has a floor", function()
    local st = headerRig({ zoneHeaderSizeDelta = -12 })
    st.H:Begin()
    ok(st.H:Place(button(), "quests", run("A", 1, 1), 0, st.cfg) == 16, "a tiny font still gets 16")
    local none = headerRig({}, { noHeight = true })
    none.H:Begin()
    ok(none.H:Place(button(), "quests", run("A", 1, 1), 0, none.cfg) == 16, "and so does a string never sized (nil)")
    ok(none.H:Height() == 16, "Height reads the last one")
    local tall = headerRig({ zoneHeaderSizeDelta = 5 })
    tall.H:Begin()
    ok(tall.H:Place(button(), "quests", run("A", 1, 1), 0, tall.cfg) == 24 and tall.H:Height() == 24,
       "Height reads the height the last header was drawn at, not the floor: " .. tostring(tall.H:Height()))
    tall.cfg.zoneHeaderSizeDelta = 0
    tall.H:Begin()
    tall.H:Place(button(), "quests", run("A", 1, 1), 0, tall.cfg)
    ok(tall.H:Height() == 19, "and follows it down: " .. tostring(tall.H:Height()))
    local frac = headerRig({}, { frac = 0.3 })
    frac.H:Begin()
    local fh = frac.H:Place(button(), "quests", run("A", 1, 1), 0, frac.cfg)
    ok(fh == 22 and frac.H.frames[1].h == 22, "a part pixel of text rounds up, never down: " .. tostring(fh))
end)

case("every pass moves the render generation on by one", function()
    local st = headerRig({})
    ok(st.H.gen == 0, "it starts at 0: " .. tostring(st.H.gen))
    st.H:Begin()
    ok(st.H.gen == 1, "the first pass makes it 1: " .. tostring(st.H.gen))
    st.H:Begin()
    st.H:Begin()
    ok(st.H.gen == 3, "and each pass after adds one: " .. tostring(st.H.gen))
end)

case("a header hidden once is shown again the next time it is drawn", function()
    local st = headerRig({})
    local content = button()
    st.H:Begin()
    st.H:Place(content, "quests", run("A", 1, 1), 0, st.cfg)
    st.H:Place(content, "quests", run("B", 1, 1), 30, st.cfg)
    st.H:Begin()
    st.H:Place(content, "quests", run("A", 1, 1), 0, st.cfg)
    st.H:Sweep()
    local second = st.H.frames[2]
    ok(second and not second.shown, "the sweep hid the header nothing drew")
    st.H:Begin()
    st.H:Place(content, "quests", run("A", 1, 1), 0, st.cfg)
    st.H:Place(content, "quests", run("B", 1, 1), 30, st.cfg)
    ok(second and second.shown, "drawn again, it shows")
    local first = st.H.frames[1]
    first:Hide()
    st.H:Begin()
    local _, _, h = st.H:Place(content, "quests", run("A", 1, 1), 0, st.cfg)
    ok(h == first and first.shown, "and so does one hidden for the band")
    local outside = st.H:NewHeader(button())
    outside:Hide()
    st.H:Draw(outside, content, "quests", run("C", 1, 1), 0, st.cfg)
    ok(outside.shown, "and one outside the pool")
end)

case("headers are pooled by position, and a shorter pass hides the rest", function()
    local st = headerRig({})
    local content = button()
    st.H:Begin()
    for i = 1, 3 do st.H:Place(content, "quests", run("Z" .. i, 1, 1), i * 10, st.cfg) end
    st.H:Sweep()
    local first = st.H.frames[1]
    ok(st.built == 3, "three made: " .. st.built)
    st.H:Begin()
    st.H:Place(content, "quests", run("Q", 1, 1), 0, st.cfg)
    st.H:Sweep()
    ok(st.built == 3 and st.H.frames[1] == first, "reused, none made")
    ok(st.H.frames[1].shown and not st.H.frames[2].shown and not st.H.frames[3].shown,
       "the two left over are hidden")
    local other = button()
    st.H:Begin()
    st.H:Place(other, "quests", run("Q", 1, 1), 0, st.cfg)
    ok(st.H.frames[1].parent == other, "and a header follows the content it is placed in")
end)

case("the look: size, color, bar and divider", function()
    local st = headerRig({})
    st.H:Begin()
    st.H:Place(button(), "quests", run("A", 1, 1), 0, st.cfg)
    local f = st.H.frames[1]
    ok(f.text.delta == 2 and f.count.delta == -2 and f.collapse.delta == 2,
       "unset, the text is Font Size +2 and the count 4 smaller: "
       .. tostring(f.text.delta) .. "," .. tostring(f.count.delta) .. "," .. tostring(f.collapse.delta))
    ok(rgb(f.text.color, 1, 0.82, 0), "unset, gold")
    ok(rgb(f.count.color, 1, 0.82, 0) and rgb(f.collapse.color, 1, 0.82, 0), "count and sign match it")
    ok(not f.bar.shown and not f.line.shown, "no bar and no divider")

    st.cfg = { zoneHeaderSizeDelta = 5, zoneHeaderColor = { r = 0.5, g = 0.6, b = 0.7 },
               zoneHeaderBar = true, zoneHeaderBarColor = { r = 1, g = 0.5, b = 0.25, a = 0.6 },
               zoneHeaderDivider = true, zoneHeaderDividerColor = { r = 0.2, g = 0.3, b = 0.4, a = 0.9 } }
    st.H:Begin()
    st.H:Place(button(), "quests", run("A", 1, 1), 0, st.cfg)
    ok(f.text.delta == 5 and f.count.delta == 1, "the size offset is the saved one")
    ok(rgb(f.text.color, 0.5, 0.6, 0.7), "the picked color")
    ok(rgb(f.count.color, 0.5, 0.6, 0.7) and rgb(f.collapse.color, 0.5, 0.6, 0.7), "on the count and sign as well")
    local gr = f.bar.gradient
    ok(f.bar.shown and gr and gr[1] == "HORIZONTAL", "a horizontal gradient bar")
    ok(gr and near(gr[2][1], 1) and near(gr[2][2], 0.5) and near(gr[2][3], 0.25) and near(gr[2][4], 0.6),
       "bright at the start, in the bar color")
    ok(gr and near(gr[3][1], 0.4) and near(gr[3][2], 0.2) and near(gr[3][3], 0.1) and near(gr[3][4], 0.6),
       "and the same darkened to 0.4 at the end, alpha kept")
    ok(f.bar.all == f, "the bar fills the header")
    local lc = f.line.color
    ok(f.line.shown and lc and near(lc[1], 0.2) and near(lc[2], 0.3) and near(lc[3], 0.4) and near(lc[4], 0.9),
       "the divider in its color")

    st.cfg.zoneHeaderBarColor = { r = 0.2, g = 0.4, b = 0.6, a = 0.5 }
    st.H:Begin()
    st.H:Place(button(), "quests", run("A", 1, 1), 0, st.cfg)
    gr = f.bar.gradient
    ok(gr and near(gr[2][1], 0.2) and near(gr[2][2], 0.4) and near(gr[2][3], 0.6) and near(gr[2][4], 0.5)
       and near(gr[3][1], 0.08) and near(gr[3][2], 0.16) and near(gr[3][3], 0.24) and near(gr[3][4], 0.5),
       "a new bar color reaches a header that already has a bar")

    st.cfg.zoneHeaderColorUseClass = true
    st.H:Begin()
    st.H:Place(button(), "quests", run("A", 1, 1), 0, st.cfg)
    ok(rgb(f.text.color, 0.1, 0.2, 0.3), "the class color wins while its switch is on")
    ok(rgb(f.count.color, 0.1, 0.2, 0.3) and rgb(f.collapse.color, 0.1, 0.2, 0.3), "on the count and sign as well")

    local nc = headerRig({ zoneHeaderColorUseClass = true, zoneHeaderColor = { r = 0.5, g = 0.6, b = 0.7 } },
                         { noClass = true })
    nc.H:Begin()
    nc.H:Place(button(), "quests", run("A", 1, 1), 0, nc.cfg)
    local g = nc.H.frames[1]
    ok(rgb(g.text.color, 0.5, 0.6, 0.7) and rgb(g.count.color, 0.5, 0.6, 0.7) and rgb(g.collapse.color, 0.5, 0.6, 0.7),
       "with no class color to give, the picked color stands in")

    st.cfg = {}
    st.H:Begin()
    st.H:Place(button(), "quests", run("A", 1, 1), 0, st.cfg)
    ok(not f.bar.shown and not f.line.shown, "switched back off, the bar and divider go")
end)

case("the bar falls back to a flat color without gradients", function()
    local st = headerRig({ zoneHeaderBar = true })
    st.H:Begin()
    st.H:Place(button(), "quests", run("A", 1, 1), 0, st.cfg)
    local f = st.H.frames[1]
    f.bar.SetGradient = nil
    f.bar.gradient = nil
    st.H:Begin()
    st.H:Place(button(), "quests", run("A", 1, 1), 0, st.cfg)
    local v = f.bar.vertex
    ok(f.bar.shown and v and near(v[1], 0.80) and near(v[2], 0.60) and near(v[3], 0.20) and near(v[4], 0.85),
       "the default bar color, flat")
end)

case("a click collapses or expands that zone alone", function()
    local st = headerRig({})
    st.H:Begin()
    st.H:Place(button(), "quests", run("Mid", 1, 1), 0, st.cfg)
    local f = st.H.frames[1]
    local click = f.scripts.OnClick
    ok(type(click) == "function", "it carries a click")
    if type(click) ~= "function" then return end
    click(f)
    ok(st.char.zonesCollapsed and st.char.zonesCollapsed["quests:Mid"] == true, "collapsed, stored per character")
    ok(st.renders == 1 and #st.scrolled == 0, "redrawn, scrolling nowhere")
    ok(st.askedBy == st.mods.Tracker, "the click-through check is asked of the tracker itself")
    click(f)
    ok(st.char.zonesCollapsed["quests:Mid"] == nil, "expanded, the key is cleared rather than stored false")
    ok(st.renders == 2 and st.scrolled[1] == "quests:Mid", "redrawn, then scrolled into view by its key")
    ok(table.concat(st.calls, ",") == "render,render,scroll quests:Mid",
       "the scroll after the render, which is what records where the zone landed: " .. table.concat(st.calls, ","))
    st.clickThrough = true
    click(f)
    ok(st.char.zonesCollapsed["quests:Mid"] == nil and st.renders == 2, "a click-through tracker ignores it")
    st.clickThrough = false
    f.groupID = "campaign"
    click(f)
    ok(st.char.zonesCollapsed["campaign:Mid"] == true and st.char.zonesCollapsed["quests:Mid"] == nil,
       "the click reads the header's own section when it fires")
end)

case("the indent", function()
    local st = headerRig({})
    ok(st.H:Indent({ zoneHeaders = false, zoneHeaderIndent = 20 }) == 0, "none while the option is off")
    ok(st.H:Indent({ zoneHeaders = true }) == 8, "8 while unset")
    ok(st.H:Indent({ zoneHeaders = true, zoneHeaderIndent = 14 }) == 14, "the saved one")
    ok(st.H:Indent({ zoneHeaders = true, zoneHeaderIndent = 0 }) == 0, "a saved 0, the slider's low end, is kept")
    ok(st.H:Indent({ zoneHeaders = true, zoneHeaderIndent = -5 }) == 0, "never negative")
    ok(st.H:Indent(nil) == 0, "and nothing with no profile")
    ok(st.H:Key("quests", "Mid") == "quests:Mid", "a zone is keyed by section and heading")
end)

-- ------------------------------------------------------------------- UI/DragDrop.lua, whole

local function loose(extra)
    local p = extra or {}
    p.points = p.points or {}
    return setmetatable(p, { __index = function(_, k)
        if k == "SetPoint" then return function(self, ...) self.points[#self.points + 1] = { ... } end end
        if k == "ClearAllPoints" then return function(self) self.points = {} end end
        if k == "GetEffectiveScale" then return function() return 1 end end
        if k == "GetWidth" then return function() return 100 end end
        if k == "CreateFontString" or k == "CreateTexture" then return function() return loose() end end
        return function() end
    end })
end

local function dragRow(id, groupID, zone, top)
    return loose({ _entry = { id = id, providerID = "quests", groupID = groupID, zone = zone, title = "q" },
                   GetTop = function() return top end, GetHeight = function() return 10 end })
end

local function dragRig(cfg, rows, cursorY)
    local st = { cfg = cfg, commits = {} }
    local mods = {
        DB = realDB(st),
        Tracker = {
            frame = { IsShown = function() return true end },
            IsClickThrough = function() return false end,
            DragRows = function() return rows end,
            Refresh = function() end,
        },
        ManualOrder = { Commit = function(_, ids, dragID, dropIndex)
            local copy = {}
            for i, v in ipairs(ids) do copy[i] = v end
            st.commits[#st.commits + 1] = { ids = table.concat(copy, ","), dragID = dragID, dropIndex = dropIndex }
        end },
    }
    local ns = newNS(mods)
    function ns:SafeMode() return false end
    load("UI/DragDrop.lua", ns, {
        wipe = wipe, UIParent = loose(),
        CreateFrame = function() return loose() end,
        C_Timer = { After = function() end },
        GetCursorPosition = function() return 0, cursorY or 0 end,
    })
    st.D = mods.DragDrop
    return st
end

case("a drag stays inside its zone while zone headers are on", function()
    local q1 = dragRow(1, "quests", "Alpha", 100)
    local q2 = dragRow(2, "quests", "Mid", 90)
    local q3 = dragRow(3, "quests", "Alpha", 80)
    local c1 = dragRow(4, "campaign", "Alpha", 70)
    local rows = { q1, q2, q3, c1 }
    local st = dragRig({ sortMode = "manual", zoneHeaders = true }, rows, 82)
    ok(st.D:OnDragStart(q1) == true, "the drag is accepted")
    ok(st.D.dragZone == "Alpha", "and remembers the zone it started in: " .. tostring(st.D.dragZone))
    st.D:UpdateVisuals()
    ok(st.D.dropIndex == 2, "the drop index counts the zone's rows only: " .. tostring(st.D.dropIndex))
    local ind = st.D.indicator
    ok(ind and ind.points[1] and ind.points[1][2] == q3, "and the drop line hangs off the zone's next row")
    st.D:OnDragStop()
    local c = st.commits[1]
    ok(c and c.ids == "1,3" and c.dragID == 1 and c.dropIndex == 2,
       "the commit is handed that zone's quests alone: " .. tostring(c and c.ids))
    ok(st.D.dragZone == nil, "and the zone is forgotten once the drag ends")

    local off = dragRig({ sortMode = "manual", zoneHeaders = false }, rows, 82)
    off.D:OnDragStart(q1)
    ok(off.D.dragZone == nil, "off, there is no zone")
    off.D:UpdateVisuals()
    ok(off.D.dropIndex == 3, "and the whole section counts: " .. tostring(off.D.dropIndex))
    off.D:OnDragStop()
    ok(off.commits[1] and off.commits[1].ids == "1,2,3", "the commit gets the whole section: "
       .. tostring(off.commits[1] and off.commits[1].ids))

    local n1 = dragRow(5, "quests", nil, 100)
    local n2 = dragRow(6, "quests", nil, 90)
    local nz = dragRig({ sortMode = "manual", zoneHeaders = true }, { n1, q2, n2 }, 0)
    nz.D:OnDragStart(n1)
    ok(nz.D.dragZone == "", "a quest with no heading drags in the empty-named zone")
    nz.D.dropIndex = 2
    nz.D:OnDragStop()
    ok(nz.commits[1] and nz.commits[1].ids == "5,6", "with the other quests that have none: "
       .. tostring(nz.commits[1] and nz.commits[1].ids))
end)

case("a Campaign drag stays inside its zone too", function()
    local c1, c2, c3 = dragRow(1, "campaign", "Alpha", 100), dragRow(2, "campaign", "Mid", 90),
                       dragRow(3, "campaign", "Alpha", 80)
    local st = dragRig({ sortMode = "manual", zoneHeaders = true }, { c1, c2, c3 }, 82)
    ok(st.D:OnDragStart(c1) == true and st.D.dragZone == "Alpha",
       "a Campaign drag remembers its zone: " .. tostring(st.D.dragZone))
    st.D:UpdateVisuals()
    st.D:OnDragStop()
    ok(st.commits[1] and st.commits[1].ids == "1,3", "and commits that zone's quests alone: "
       .. tostring(st.commits[1] and st.commits[1].ids))
end)

-- ------------------------------------------------- the row loop, sliced out of Render

-- Starts at the popup boxes, ahead of the zone loop's setup, so a mutant of its first lines is
-- driven rather than breaking the anchor. The slice closes the four blocks it sits in, so it is
-- opened four times over. Built under pcall: a rotted anchor fails the run rather than aborting it.
local loopChunk
do
    local good, err = pcall(function()
        local src = slice("UI/Tracker.lua", "if popupCount > 0 then",
                          "for i = _dragCount + 1, #_dragRows do _dragRows[i] = nil end")
        loopChunk = assert(loadstring("do do do do " .. src, "zone-row-loop"))
    end)
    ok(good, "the row loop slices out of Render: " .. tostring(err))
end

-- o.sticky arms the band's bookkeeping, with o.stickyN the section's place in the band and o.y where
-- the section's body starts (0 for the first section, whose header is in the band). The gap and the
-- indent are 3 and 13, unlike Block Spacing's 2 and the indent's 8, so a literal in their place shows.
-- An entry with timed set is one noteExpiry says has a countdown. o.popupCount and o.popupRender draw
-- pop-up boxes at the top of the section, and with neither a drawn box raises.
local function loopRig(group, folded, o)
    o = o or {}
    local env = {
        group = group, groupID = o.groupID or "quests", content = {}, width = 200, gap = 3, indent = 13,
        y = o.y or 10, cfg = {}, zoneTops = {}, dragProvider = "quests", _dragRows = {}, _dragCount = 0,
        hasTimed = false, _buildRow = function() end, placed = {}, drawn = {}, focused = {},
        popupCount = o.popupCount or 0,
        PopupBoxes = { Render = o.popupRender or function() error("no popup box is drawn in these cases") end },
        sticky = o.sticky, stickyN = o.stickyN or 1, stickyZ = o.stickyZ or 0,
        zKeys = {}, zTops = {}, zFirst = {}, zLast = {}, hidden = {},
        placedCfg = 0, wanted = {}, rowsByID = {}, expiry = {},
    }
    env.ZoneHeaders = {
        Key = function(_, g, z) return g .. ":" .. z end,
        Place = function(_, content, g, r, y, c)
            env.placed[#env.placed + 1] = g .. ":" .. r.zone .. "@" .. y
            if c == env.cfg then env.placedCfg = env.placedCfg + 1 end
            assert(content == env.content)
            local h = { zone = r.zone }
            function h:Hide() env.hidden[#env.hidden + 1] = self.zone end
            return 20, folded[r.zone] == true, h
        end,
    }
    -- The pool calls the builder only when it has no row to reuse, so a missing one raises in game
    -- on an empty pool and nowhere else.
    env.RowPool = { Acquire = function(_, _, providerID, id, build)
        assert(build ~= nil and build == env._buildRow, "a row is acquired with the row builder")
        local row = { id = id, providerID = providerID }
        function row:SetWidth(w) self.w = w end
        function row:ClearAllPoints() self.points = {} end
        function row:SetPoint(...) self.points[#self.points + 1] = { ... } end
        env.rowsByID[id] = row
        return row
    end }
    env.Row = { Render = function(_, row, e, w)
        env.drawn[#env.drawn + 1] = ("%s@%d,%d w%d/%d"):format(tostring(e.id), row.points[1][4], row.points[1][5], row.w, w)
        row._entry = e
        return 30
    end }
    env.ItemButtons = { Want = function(_, id, row) env.wanted[#env.wanted + 1] = { id = id, row = row } end }
    env.noteExpiry = function(e)
        env.expiry[#env.expiry + 1] = e.id
        return e.timed == true
    end
    env.noteFocus = function(e) env.focused[#env.focused + 1] = e.id end
    assert(loopChunk, "no row loop to drive")
    setfenv(loopChunk, setmetatable(env, { __index = _G }))
    loopChunk()
    return env
end

local function loopGroup(entries, runs)
    return { visibleCount = #entries, entries = entries, zoneCount = runs and #runs or 0, zoneRuns = runs }
end

case("each zone gets its header, its rows indented under it", function()
    local e1, e2, e3 = entry(1, "Alpha"), entry(2, "Alpha"), entry(3, "Mid")
    local runs = { { zone = "Alpha", first = 1, last = 2 }, { zone = "Mid", first = 3, last = 3 } }
    local env = loopRig(loopGroup({ e1, e2, e3 }, runs), {})
    ok(table.concat(env.placed, " ") == "quests:Alpha@10 quests:Mid@99", "headers: " .. table.concat(env.placed, " "))
    ok(table.concat(env.drawn, " ") == "1@13,-33 w187/187 2@13,-66 w187/187 3@13,-122 w187/187",
       "rows: " .. table.concat(env.drawn, " "))
    ok(env.y == 155, "the list grows by every header, row and gap: " .. tostring(env.y))
    ok(env.zoneTops["quests:Alpha"] == 10 and env.zoneTops["quests:Mid"] == 99, "each zone's top is recorded")
    ok(env._dragCount == 3 and env._dragRows[3] and env._dragRows[3].id == 3, "every row is draggable")
    ok(table.concat(env.focused, ",") == "1,2,3", "and reported for the focus")
    ok(env.placedCfg == 2, "each header is handed the tracker's own settings: " .. env.placedCfg)
end)

case("a Campaign section keys and places its zones under its own name", function()
    local e1, e2, e3 = entry(1, "Alpha"), entry(2, "Alpha"), entry(3, "Mid")
    local runs = { { zone = "Alpha", first = 1, last = 2 }, { zone = "Mid", first = 3, last = 3 } }
    local env = loopRig(loopGroup({ e1, e2, e3 }, runs), {}, { groupID = "campaign", sticky = true, stickyN = 2, y = 40 })
    ok(table.concat(env.placed, " ") == "campaign:Alpha@40 campaign:Mid@129",
       "placed as Campaign's: " .. table.concat(env.placed, " "))
    ok(env.zoneTops["campaign:Alpha"] == 40 and env.zoneTops["campaign:Mid"] == 129 and env.zoneTops["quests:Alpha"] == nil,
       "scrolled into view by Campaign's keys")
    ok(env.zKeys[1] == "campaign:Alpha" and env.zKeys[2] == "campaign:Mid", "and named so in the band")
end)

case("a row's item button and countdown are asked for, and nothing under a collapsed zone", function()
    local e1, e2, e3, e4 = entry(1, "Alpha"), entry(2, "Alpha"), entry(3, "Mid"), entry(4, "Mid")
    e1.hasItem, e2.timed, e3.hasItem, e3.timed = true, true, true, true
    local runs = { { zone = "Alpha", first = 1, last = 2 }, { zone = "Mid", first = 3, last = 4 } }
    local env = loopRig(loopGroup({ e1, e2, e3, e4 }, runs), { Mid = true })
    local w = env.wanted[1]
    ok(#env.wanted == 1 and w.id == 1 and w.row ~= nil and w.row == env.rowsByID[1],
       "one item button, for the quest that has one, on its own row: " .. #env.wanted)
    ok(table.concat(env.expiry, ",") == "1,2", "every drawn row's countdown is looked at: " .. table.concat(env.expiry, ","))
    ok(env.hasTimed == true, "and a quest with one keeps the ticker running")
    e2.timed = false
    local quiet = loopRig(loopGroup({ e1, e2, e3, e4 }, runs), { Mid = true })
    ok(quiet.hasTimed == false, "with none drawn, it is not asked for")
end)

case("a collapsed zone keeps its header and drops its rows", function()
    local e1, e2, e3 = entry(1, "Alpha"), entry(2, "Alpha"), entry(3, "Mid")
    local runs = { { zone = "Alpha", first = 1, last = 2 }, { zone = "Mid", first = 3, last = 3 } }
    local env = loopRig(loopGroup({ e1, e2, e3 }, runs), { Alpha = true })
    ok(table.concat(env.placed, " ") == "quests:Alpha@10 quests:Mid@33", "both headers: " .. table.concat(env.placed, " "))
    ok(table.concat(env.drawn, " ") == "3@13,-56 w187/187", "only Mid's row: " .. table.concat(env.drawn, " "))
    ok(env._dragCount == 1 and table.concat(env.focused, ",") == "3", "and nothing from Alpha is drawn at all")
end)

case("no runs draws the section as one block at the full width", function()
    local e1, e2 = entry(1, "Alpha"), entry(2, "Mid")
    local env = loopRig(loopGroup({ e1, e2 }, nil), {})
    ok(#env.placed == 0, "no header")
    ok(table.concat(env.drawn, " ") == "1@0,-10 w200/200 2@0,-43 w200/200", "rows: " .. table.concat(env.drawn, " "))
    local stale = loopRig({ visibleCount = 1, entries = { e1 }, zoneCount = 0, zoneRuns = { { zone = "Mid", first = 1, last = 1 } } }, {})
    ok(#stale.placed == 0 and #stale.drawn == 1, "runs left from an earlier pass are not read while the count is 0")
end)

case("a quest with no heading gets no header and no indent", function()
    local e1, e2 = entry(1, nil), entry(2, "Mid")
    local runs = { { zone = "", first = 1, last = 1 }, { zone = "Mid", first = 2, last = 2 } }
    local env = loopRig(loopGroup({ e1, e2 }, runs), { [""] = true })
    ok(table.concat(env.placed, " ") == "quests:Mid@43", "Mid's header only: " .. table.concat(env.placed, " "))
    ok(table.concat(env.drawn, " ") == "1@0,-10 w200/200 2@13,-66 w187/187", "rows: " .. table.concat(env.drawn, " "))
end)

case("after a zone, a quest with no heading is not indented under it", function()
    local e1, e2 = entry(1, "Mid"), entry(2, nil)
    local runs = { { zone = "Mid", first = 1, last = 1 }, { zone = "", first = 2, last = 2 } }
    local env = loopRig(loopGroup({ e1, e2 }, runs), {})
    ok(table.concat(env.placed, " ") == "quests:Mid@10", "Mid's header only: " .. table.concat(env.placed, " "))
    ok(table.concat(env.drawn, " ") == "1@13,-33 w187/187 2@0,-66 w200/200",
       "the indent ends with its zone: " .. table.concat(env.drawn, " "))
end)

case("pop-up boxes sit above the first zone header, at the section's full width", function()
    local function alphaThenMid()
        local e1, e2, e3 = entry(1, "Alpha"), entry(2, "Alpha"), entry(3, "Mid")
        return loopGroup({ e1, e2, e3 }, { { zone = "Alpha", first = 1, last = 2 }, { zone = "Mid", first = 3, last = 3 } })
    end
    local calls = {}
    local function popupRender(_, content, w, y, groupID)
        calls[#calls + 1] = { content = content, w = w, y = y, groupID = groupID }
        return 40
    end
    local env = loopRig(alphaThenMid(), {}, { popupCount = 1, popupRender = popupRender })
    local c = calls[1]
    ok(#calls == 1 and c.content == env.content and c.w == 200 and c.y == 10 and c.groupID == "quests",
       "drawn once, at the top of the section and the full width: " .. (c and (c.w .. " @" .. c.y) or "none"))
    ok(table.concat(env.placed, " ") == "quests:Alpha@50 quests:Mid@139",
       "the zone headers start below it: " .. table.concat(env.placed, " "))
    ok(table.concat(env.drawn, " ") == "1@13,-73 w187/187 2@13,-106 w187/187 3@13,-162 w187/187",
       "and the rows stay indented: " .. table.concat(env.drawn, " "))
    local band = loopRig(alphaThenMid(), {}, { sticky = true, stickyN = 1, y = 0, popupCount = 1,
                                               popupRender = function() return 40 end })
    ok(#band.hidden == 0 and table.concat(band.placed, " ") == "quests:Alpha@40 quests:Mid@129",
       "with sticky headers the first zone stays in the list under the box: " .. table.concat(band.placed, " "))
end)

local function zoneRuns3()
    local e1, e2, e3 = entry(1, "Alpha"), entry(2, "Alpha"), entry(3, "Mid")
    return loopGroup({ e1, e2, e3 }, { { zone = "Alpha", first = 1, last = 2 }, { zone = "Mid", first = 3, last = 3 } })
end

case("with sticky headers, the first section's first zone joins its header in the band", function()
    local env = loopRig(zoneRuns3(), {}, { sticky = true, stickyN = 1, y = 0 })
    ok(table.concat(env.hidden, ",") == "Alpha", "its header is hidden in the list: " .. table.concat(env.hidden, ","))
    ok(table.concat(env.placed, " ") == "quests:Alpha@0 quests:Mid@66", "and takes no room, so the next zone moves up: "
       .. table.concat(env.placed, " "))
    ok(table.concat(env.drawn, " ") == "1@13,0 w187/187 2@13,-33 w187/187 3@13,-89 w187/187",
       "the list starts with the first zone's rows: " .. table.concat(env.drawn, " "))
    ok(env.stickyZ == 2 and env.zKeys[1] == "quests:Alpha" and env.zKeys[2] == "quests:Mid", "both zones recorded")
    ok(env.zTops[1] == -23 and env.zTops[2] == 66, "the band's one a row above the list, the other at its top: "
       .. tostring(env.zTops[1]) .. ", " .. tostring(env.zTops[2]))
    ok(env.zFirst[1] == 1 and env.zLast[1] == 2, "the section owns both")
    ok(env.zoneTops["quests:Alpha"] == 0, "and it still scrolls into view at the top")
end)

case("any other section keeps its zone headers in the list, and records where they are", function()
    local env = loopRig(zoneRuns3(), {}, { sticky = true, stickyN = 2, y = 120, stickyZ = 3 })
    ok(#env.hidden == 0, "nothing hidden")
    ok(table.concat(env.placed, " ") == "quests:Alpha@120 quests:Mid@209", "headers in place: " .. table.concat(env.placed, " "))
    ok(env.stickyZ == 5 and env.zKeys[4] == "quests:Alpha" and env.zTops[4] == 120 and env.zTops[5] == 209,
       "numbered after the zones before it: " .. tostring(env.zTops[4]) .. ", " .. tostring(env.zTops[5]))
    ok(env.zFirst[2] == 4 and env.zLast[2] == 5, "and the section owns those two")
    local first = loopRig(zoneRuns3(), {}, { sticky = true, stickyN = 1, y = 30 })
    ok(#first.hidden == 0 and first.zTops[1] == 30, "the first section's first zone stays put with something above it")
end)

case("a collapsed first zone still joins the band, and a section's runs are recorded once", function()
    local env = loopRig(zoneRuns3(), { Alpha = true }, { sticky = true, stickyN = 1, y = 0 })
    ok(table.concat(env.hidden, ",") == "Alpha" and env.zTops[1] == -23 and env.zTops[2] == 0,
       "hidden, and Mid now at the top: " .. tostring(env.zTops[2]))
    ok(table.concat(env.drawn, " ") == "3@13,-23 w187/187", "only Mid's row: " .. table.concat(env.drawn, " "))
end)

case("without sticky headers nothing is recorded or hidden", function()
    local env = loopRig(zoneRuns3(), {}, { sticky = false, y = 0 })
    ok(#env.hidden == 0 and env.stickyZ == 0 and next(env.zKeys) == nil and next(env.zFirst) == nil
       and next(env.zLast) == nil, "nothing")
    ok(table.concat(env.placed, " ") == "quests:Alpha@0 quests:Mid@89", "and the headers sit where they always did")
    local none = loopRig(loopGroup({ entry(1, "Alpha") }, nil), {}, { sticky = true, stickyN = 1, y = 0 })
    ok(none.stickyZ == 0 and none.zFirst[1] == 1 and none.zLast[1] == 0, "a section with no runs owns no zones")
end)

-- ------------------------------------------------- scrollIntoView and its two callers

local scrollSrc
do
    local good, err = pcall(function()
        scrollSrc = slice("UI/Tracker.lua", "local function scrollIntoView(f, top)",
                          "-- True whenever the tracker is alpha-hidden but still on screen.")
    end)
    ok(good, "scrollIntoView slices out of the tracker: " .. tostring(err))
end

local function scrollRig(f, locked)
    assert(scrollSrc, "no scrollIntoView to drive")
    local T = { frame = f }
    local env = setmetatable({
        Tracker = T,
        secureLocked = function() return locked end,
        ns = { GetModule = function() return { Height = function() return 26 end } end },
    }, { __index = _G })
    local chunk = assert(loadstring(scrollSrc, "scroll-into-view"))
    setfenv(chunk, env)
    chunk()
    return T
end

local function scrollFrame()
    local sf = { set = {} }
    function sf:GetHeight() return 100 end
    function sf:GetVerticalScroll() return 0 end
    function sf:GetVerticalScrollRange() return 500 end
    function sf:SetVerticalScroll(v) self.set[#self.set + 1] = v end
    return sf
end

case("an expanded zone scrolls into view by its key", function()
    local sf = scrollFrame()
    local f = { scroll = sf, _zoneTop = { ["quests:Mid"] = 300 }, _sectionTop = { quests = 50 } }
    local T = scrollRig(f, false)
    T:ScrollZoneIntoView("quests:Mid")
    ok(sf.set[1] == 300, "to the zone's own top: " .. tostring(sf.set[1]))
    T:ScrollZoneIntoView("quests:Gone")
    ok(#sf.set == 1, "a key with no top scrolls nowhere")
    T:ScrollSectionIntoView("quests")
    ok(sf.set[2] == 50, "and sections still scroll by theirs: " .. tostring(sf.set[2]))
    local sf2 = scrollFrame()
    scrollRig({ scroll = sf2, _zoneTop = { ["quests:Mid"] = 300 } }, true):ScrollZoneIntoView("quests:Mid")
    ok(#sf2.set == 0, "nothing moves while the anchor chain is locked")
    local good = pcall(function() scrollRig({ scroll = scrollFrame() }, false):ScrollZoneIntoView("quests:Mid") end)
    ok(good, "a render that never recorded a zone top is safe")
end)

-- ------------------------------------------------- the rest, by whole statement

local renderSrc = ""
do
    local good, err = pcall(function()
        renderSrc = stripComments(slice("UI/Tracker.lua", "function Tracker:Render()",
                                        "local TICK_SLOW, TICK_FAST, FAST_WINDOW"))
    end)
    ok(good, "Render slices out of the tracker: " .. tostring(err))
end

local function has(src, stmt, msg) ok(count(src, stmt) == 1, msg .. " (" .. count(src, stmt) .. ")") end

has(renderSrc, '    local ZoneHeaders = ns:GetModule("ZoneHeaders")\n', "Render resolves the zone header module")
local hideAt  = renderSrc:find("    Sections:HideAll()\n    ZoneHeaders:Begin()\n", 1, true)
local loopAt  = renderSrc:find("for _, groupID in ipairs(Sections:Order()) do", 1, true)
local sweepAt = renderSrc:find("    ZoneHeaders:Sweep()\n", 1, true)
local dragAt  = renderSrc:find("    for i = _dragCount + 1, #_dragRows do _dragRows[i] = nil end\n", 1, true)
ok(count(renderSrc, "ZoneHeaders:Begin()") == 1 and hideAt and loopAt and hideAt < loopAt,
   "the header pool is reset with the section headers, before the sections are drawn")
ok(count(renderSrc, "ZoneHeaders:Sweep()") == 1 and sweepAt and dragAt and sweepAt > dragAt,
   "and swept once every section is drawn")
-- The whole statement between its neighbors, so it cannot be wrapped in a condition and still
-- match: switched off, nothing else hides the headers a previous pass drew.
has(renderSrc, "\n    for i = _dragCount + 1, #_dragRows do _dragRows[i] = nil end\n    ZoneHeaders:Sweep()\n\n",
    "the sweep runs on every pass, zone headers on or off")
-- Every use of the indent in Render, so no write, however spelled, can join the read and the one
-- place a zone's rows take it. The setting itself is read through ZoneHeaders:Indent alone.
do
    local uses = 0
    for _ in renderSrc:gmatch("%f[%w_]indent%f[^%w_]") do uses = uses + 1 end
    ok(uses == 2, "Render names the indent only where it reads it and where a zone's rows take it: " .. uses)
    ok(count(renderSrc, "zoneHeaderIndent") == 0, "and never reads or writes the saved setting itself")
end
has(renderSrc, "\n                            left = indent\n", "a zone's rows take the indent, whatever is above them")
has(renderSrc, [[
    local zoneTops = f._zoneTop
    if not zoneTops then zoneTops = {}; f._zoneTop = zoneTops end
    wipe(zoneTops)
    local indent = ZoneHeaders:Indent(cfg)
]], "the zone tops are cleared and the indent read once per pass")

-- The whole statement to its line end, and the only write to subtitle in Row:Render, so nothing
-- appended to it or written after it can bring the label back.
do
    local good, err = pcall(function()
        local rowSrc = stripComments(readFile("UI/Row.lua"))
        local at = rowSrc:find("function Row:Render(row, entry, width, cfg)", 1, true)
        assert(at, "Row:Render is not found")
        local body = rowSrc:sub(at)
        has(body, "\n    local subtitle = (cfg and cfg.showZoneTag ~= false and not cfg.zoneHeaders)"
                  .. " and entry.subtitle or nil\n", "the zone label is dropped while zone headers are on")
        local writes = 0
        for _ in body:gmatch("subtitle%s*=[^=]") do writes = writes + 1 end
        ok(writes == 1, "and Row:Render writes subtitle nowhere else: " .. writes)
    end)
    ok(good, "Row:Render slices out of the row: " .. tostring(err))
end
has(stripComments(readFile("UI/Commands.lua")), '    debugLine("ZoneGroups")\n', "/eqot status prints the line")

local db = readFile("Core/DB.lua")
for _, line in ipairs({
    "            zoneHeaders             = false,\n",
    '            zoneHeaderOrder         = "current",\n',
    "            zoneHeaderSizeDelta     = 2,\n",
    "            zoneHeaderColor         = { r = 1, g = 0.82, b = 0, a = 1 },\n",
    "            zoneHeaderColorUseClass = false,\n",
    "            zoneHeaderBar           = false,\n",
    "            zoneHeaderBarColor      = { r = 0.80, g = 0.60, b = 0.20, a = 0.85 },\n",
    "            zoneHeaderDivider       = false,\n",
    "            zoneHeaderDividerColor  = { r = 0.92, g = 0.72, b = 0.02, a = 0.85 },\n",
    "            zoneHeaderIndent        = 8,\n",
    "        zonesCollapsed     = {},\n",
    -- With its neighbors, so the reset cannot be wrapped in a condition and still match.
    "\n        c.sectionsCollapsed = {}\n        c.zonesCollapsed    = {}\n        c.pinned            = {}\n",
}) do
    has(db, line, "Core/DB.lua carries " .. line:gsub("^%s+", ""):gsub("\n$", ""))
end
local keys = db:match("local APPEARANCE_KEYS = (%b{})")
ok(keys ~= nil, "APPEARANCE_KEYS is found")
if keys then
    keys = stripComments(keys)
    for _, k in ipairs({ "zoneHeaderSizeDelta", "zoneHeaderColor", "zoneHeaderColorUseClass", "zoneHeaderBar",
                         "zoneHeaderBarColor", "zoneHeaderDivider", "zoneHeaderDividerColor", "zoneHeaderIndent" }) do
        ok(count(keys, '"' .. k .. '"') == 1, "Reset to Defaults clears " .. k)
    end
    ok(count(keys, '"zoneHeaders"') == 0 and count(keys, '"zoneHeaderOrder"') == 0,
       "but never the switch or the order")
end

local BS = string.char(92)
for _, toc in ipairs({ "EQObjectiveTracker.toc", "EQObjectiveTracker_Mainline.toc", "EQObjectiveTracker_Camelot.toc",
                       "EQObjectiveTracker_TBC.toc", "EQObjectiveTracker_Vanilla.toc" }) do
    local lines = {}
    for l in (readFile(toc) .. "\n"):gmatch("([^\r\n]*)\r?\n") do lines[#lines + 1] = l end
    local zg, zh, zgAt, zhAt, feedAt, trackerAt = 0, 0, nil, nil, nil, nil
    for i, l in ipairs(lines) do
        if l == "Data" .. BS .. "ZoneGroups.lua" then zg = zg + 1; zgAt = i end
        if l == "UI" .. BS .. "ZoneHeaders.lua" then zh = zh + 1; zhAt = i end
        if l == "Data" .. BS .. "Feed.lua" then feedAt = i end
        if l == "UI" .. BS .. "Tracker.lua" then trackerAt = i end
    end
    ok(zg == 1 and zh == 1, toc .. " lists both files exactly once: " .. zg .. ", " .. zh)
    ok(zgAt and feedAt and zgAt < feedAt, toc .. " loads ZoneGroups before Feed")
    ok(zhAt and trackerAt and zhAt < trackerAt, toc .. " loads ZoneHeaders before Tracker")
end

-- Core/DB.lua's own DB:ResetAll, sliced and run over a saved-variable stub, so the reset is driven
-- rather than only found in the source: a condition wrapped around it, or the per-character table
-- read from the wrong place, leaves collapsed zones collapsed after "Reset all settings".
case("Reset all settings clears the collapsed zones with the rest of the character's state", function()
    local src = readFile("Core/DB.lua")
    local head = "\nfunction DB:ResetAll()\n"
    local a = src:find(head, 1, true)
    local b = a and src:find("\nend\n", a + 1, true)
    assert(a and b and not src:find(head, a + 1, true), "Core/DB.lua defines DB:ResetAll once")
    local holder = {}
    local chunk = assert(loadstring(src:sub(a + 1, b + 4), "DB:ResetAll"))
    setfenv(chunk, { DB = holder })
    chunk()
    local profileReset = 0
    local zones, sections, pinned = { ["quests:Elwynn Forest"] = true }, { quests = true }, { quests = { [7] = true } }
    local saved = {
        char = { zonesCollapsed = zones, sectionsCollapsed = sections, pinned = pinned,
                 trackedQuests = { 7 }, delveRun = { tier = 3 } },
        global = { optionsWindowScale = 1.3, safeMode = true, disabledModules = { Tracker = true },
                   disabledProviders = { quests = true }, enabledModules = { Blizzard = true },
                   enabledProviders = { quests = true } },
        profile = {},
    }
    function saved:ResetProfile() if self == saved then profileReset = profileReset + 1 end end
    local DB = { db = saved, defaults = { global = { optionsWindowScale = 1 } } }
    holder.ResetAll(DB)
    local c = saved.char
    ok(profileReset == 1, "the profile is reset, through the saved variables' own method")
    ok(type(c.zonesCollapsed) == "table" and next(c.zonesCollapsed) == nil and c.zonesCollapsed ~= zones,
       "the collapsed zones are a new, empty table")
    ok(type(c.sectionsCollapsed) == "table" and next(c.sectionsCollapsed) == nil and c.sectionsCollapsed ~= sections,
       "and so are the collapsed sections")
    ok(type(c.pinned) == "table" and next(c.pinned) == nil and c.pinned ~= pinned, "and the pinned quests")
    ok(c.trackedQuests == nil and c.delveRun == nil, "the tracked set and the delve run are cleared")
    local g = saved.global
    ok(g.optionsWindowScale == 1 and g.safeMode == nil and g.disabledModules == nil and g.disabledProviders == nil
       and g.enabledModules == nil and g.enabledProviders == nil,
       "and the account-wide window scale and every switched-off or switched-on part go back too")
end)

print(("test_zone_headers: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
