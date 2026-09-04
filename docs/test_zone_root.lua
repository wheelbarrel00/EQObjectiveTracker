-- Unit tests for Data/ZoneProgress.lua's zoneRoot walk, run against the SHIPPED source rather
-- than a copy. Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_zone_root.lua
--
-- WHY THIS FILE EXISTS. Measured in game on 2026-09-03, standing in Slayer's Rise:
--
--     2444 Slayer's Rise  mapType 3 (Zone)  parent 2405
--     2405 Voidstorm      mapType 3 (Zone)  parent 2537
--     2537 Quel'Thalas    mapType 2 (Continent)
--
-- Midnight NESTS zones. The old walk stopped at the FIRST Zone, answered Slayer's Rise, which
-- no category names, and Voidstorm's own routed questlines drew no bar - reported as "the
-- progress bar is not visible in the Voidstorm". The walk now passes THROUGH a Zone that
-- resolves to no category.
--
-- The case this file exists to protect is EVERSONG. A category is matched two ways, by mapID
-- and by NAME, and Eversong Woods (2395) has NO mapID entry in either addon - the one listed
-- is Silvermoon City. So a climb that asked only "does this map have a mapID entry" would pass
-- Eversong over from a sub-area inside it and answer the sub-area, drawing no bar at all -
-- silently, on a zone that works today. Eversong's own ancestor is a Continent and can never
-- be taken, so the harm is the miss rather than a wrong zone being counted.
--
-- Data/ZoneProgress.lua cannot be loaded whole without stubbing its events, its retry timers
-- and the questline store, so the pieces under test are sliced out by TEXT ANCHORS rather than
-- line numbers, which drift. If an anchor below stops matching, fix the anchor here rather
-- than deleting the test.
--
-- OUT OF SCOPE BY CONSTRUCTION: everything downstream of the root. Count, categoryQuestLines,
-- the questline retry chain and the bar itself are reached by no assertion here, so a green
-- run says nothing about them. categoryByMapID and categoryByName ARE in scope - they are
-- sliced rather than restated, because zoneRoot's whole correctness now rests on asking them
-- the same question Count asks.

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
end

local fh = assert(io.open(repoFile("Data/ZoneProgress.lua"), "r"))
local src = fh:read("*a")
fh:close()

local function sliceBetween(fromAnchor, toAnchor)
    local from = src:find(fromAnchor, 1, true)
    local to   = src:find(toAnchor, 1, true)
    assert(from, "anchor not found in Data/ZoneProgress.lua: " .. fromAnchor)
    assert(to,   "anchor not found in Data/ZoneProgress.lua: " .. toAnchor)
    assert(to > from, "anchors are out of order in Data/ZoneProgress.lua: " .. fromAnchor)
    return src:sub(from, to - 1)
end

-- MAX_HOPS and the three memo fields are sliced rather than restated, so the hop-bound case
-- below is measured against the shipped constant instead of a copy that could drift from it.
local state   = sliceBetween("local MAX_HOPS", "local RETRY_DELAY")
local lookups = sliceBetween("local function categoryByMapID", "local _catIndex")

-- zoneRoot and the two lookups are file-locals, so the slice is asked to hand them out. The
-- dirty() hook makes the one assignment out of ZoneProgress's ZONE_CHANGED_NEW_AREA handler
-- that this walk reads, rather than being a back door invented for the test. That handler does
-- four other things, all of them downstream of the root and out of scope here.
local CAPTURE = [[
OUT = {
    zoneRoot        = zoneRoot,
    categoryByMapID = categoryByMapID,
    categoryByName  = categoryByName,
    dirty           = function() _rootDirty = true end,
    maxHops         = MAX_HOPS,
    via             = function() return _rootVia end,
}
]]

local ZONE, CONTINENT, WORLD, MICRO = 3, 2, 1, 5

local maps      = {}
local playerMap = nil
local infoReads = 0

local env = setmetatable({
    ns    = { Has = { Map = true } },
    Enum  = { UIMapType = { Zone = ZONE } },
    C_Map = {
        GetBestMapForUnit = function() return playerMap end,
        GetMapInfo        = function(id)
            infoReads = infoReads + 1
            return maps[id]
        end,
    },
}, { __index = _G })

local chunk = assert(loadstring(state .. "\n" .. lookups .. "\n" .. CAPTURE,
                                "@Data/ZoneProgress.lua slice"))
setfenv(chunk, env)
chunk()

local OUT = env.OUT
assert(OUT and OUT.zoneRoot, "the Data/ZoneProgress.lua slice defined no zoneRoot")
assert(OUT.categoryByMapID, "the slice defined no categoryByMapID")
assert(OUT.categoryByName,  "the slice defined no categoryByName")

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end

-- Stand-ins for ns.ZONE_CATEGORIES. Deliberately shaped like the real table: VOIDSTORM
-- carries the mapID it really carries, and EVERSONG carries the WRONG one it really carries,
-- so the name-only match below is the shipped situation rather than a contrived one.
local CAT = {
    VOIDSTORM   = { name = "Voidstorm",      mapIDs = { 2405 } },
    EVERSONG    = { name = "Eversong Woods", mapIDs = { 2393 } },
    COILED      = { name = "The Coiled Isle", mapIDs = { 2512 } },
    QUELTHALAS  = { name = "Quel'Thalas",    mapIDs = { 2537 } },
}

local function setMaps(chain, cats)
    maps, playerMap, infoReads = {}, nil, 0
    for i = 1, #chain do
        local m = chain[i]
        maps[m.id] = { name = m.name, mapType = m.mapType, parentMapID = m.parent or 0 }
        if i == 1 then playerMap = m.id end
    end
    env.ns.ZONE_CATEGORIES = cats
    OUT.dirty()
end

-- Every call into zoneRoot goes through pcall. A mutant that raises would otherwise kill the
-- file with no summary line, and every battery in this tree reads a missing summary as a
-- SURVIVOR - so a crash would report as a coverage hole rather than as the crash it is. The
-- three slice-behaviour assertions below call the lookups bare, deliberately: a raise there is
-- a rotted slice rather than a mutant, and it should abort loudly.
local function root()
    local okCall, id, name = pcall(OUT.zoneRoot)
    if not okCall then
        return nil, nil, tostring(id)
    end
    return id, name, nil
end

-- The slice is proved to behave before anything is measured through it. A rotted anchor that
-- silently handed back a do-nothing function would otherwise let every case below pass.
env.ns.ZONE_CATEGORIES = CAT
ok(OUT.categoryByMapID(2405) == "VOIDSTORM", "sliced categoryByMapID resolves Voidstorm by id")
ok(OUT.categoryByName("Eversong Woods") == "EVERSONG",
   "sliced categoryByName resolves Eversong by name")
ok(OUT.categoryByMapID(2395) == nil, "Eversong's own mapID is genuinely absent from the table")

local id, name, err

-- 0. The memo ships ARMED, and this is the only point in the file where that can be seen -
--    every case below dirties before it reads. A memo that started clean would answer nil
--    here and never walk again for the whole session, and the bar would never draw at all.
maps, playerMap, infoReads = {}, 2405, 0
maps[2405] = { name = "Voidstorm",   mapType = ZONE,      parentMapID = 2537 }
maps[2537] = { name = "Quel'Thalas", mapType = CONTINENT, parentMapID = 13 }
env.ns.ZONE_CATEGORIES = CAT
id, name = root()
ok(id == 2405, "the first call of a session walks without being dirtied, got " .. tostring(id))
ok(name == "Voidstorm", "and answers a full pair, got " .. tostring(name))

-- 1. THE REPORTED CASE. Nested Zones: the first one names no category, the second does.
setMaps({
    { id = 2444, name = "Slayer's Rise", mapType = ZONE,      parent = 2405 },
    { id = 2405, name = "Voidstorm",     mapType = ZONE,      parent = 2537 },
    { id = 2537, name = "Quel'Thalas",   mapType = CONTINENT, parent = 13 },
}, CAT)
id, name, err = root()
ok(err == nil, "nested zones: zoneRoot did not raise (" .. tostring(err) .. ")")
ok(id == 2405, "nested zones: climbs past Slayer's Rise to Voidstorm, got " .. tostring(id))
ok(name == "Voidstorm",
   "nested zones: the NAME climbs with the id, or the bar labels Voidstorm's count "
   .. "'Slayer's Rise' - got " .. tostring(name))
ok(OUT.via() == 2444,
   "the status line records the map the walk climbed FROM, got " .. tostring(OUT.via()))

-- 2. A root that already resolves stops there. Its parent here is a Continent, so this case
--    only proves the ordinary answer is unchanged - 2b is where stopping is actually pinned.
setMaps({
    { id = 2512, name = "The Coiled Isle", mapType = ZONE,      parent = 2537 },
    { id = 2537, name = "Quel'Thalas",     mapType = CONTINENT, parent = 13 },
}, CAT)
id, name = root()
ok(id == 2512, "a zone that resolves on its own hop stays put, got " .. tostring(id))
ok(name == "The Coiled Isle", "and reports its own name, got " .. tostring(name))
-- Runs straight after the climbing case, so a via that is never cleared still reads 2444 here.
-- That is the recorded trap: a status line announcing a climb that did not happen, on the one
-- line a "my zone bar vanished" report is read from.
ok(OUT.via() == nil,
   "a walk that did not climb records no via, got " .. tostring(OUT.via()))

-- 2b. TWO nested Zones that BOTH resolve, which no other chain in this file has. The walk
--     must take the INNERMOST: deleting the break leaves the assignment in place and the last
--     resolving zone up the chain wins instead, which is the reported bug in reverse - an
--     ancestor's questlines counted under a zone the player is not in. Void Acropolis nested
--     inside Voidstorm is the plausible live instance.
setMaps({
    { id = 2512, name = "The Coiled Isle", mapType = ZONE,      parent = 2405 },
    { id = 2405, name = "Voidstorm",       mapType = ZONE,      parent = 2537 },
    { id = 2537, name = "Quel'Thalas",     mapType = CONTINENT, parent = 13 },
}, CAT)
id, name = root()
ok(id == 2512, "the INNERMOST resolving zone wins, got " .. tostring(id))
ok(name == "The Coiled Isle", "and the name is the inner one's, got " .. tostring(name))

-- 3. Eversong resolves by NAME only. This case only proves the ANSWER is unchanged: Eversong's
--    own ancestor is a Continent, so it can never be taken and this case cannot fail for the
--    dropped-name mutant. 3b is where the name test actually earns its keep.
setMaps({
    { id = 2395, name = "Eversong Woods", mapType = ZONE,      parent = 2537 },
    { id = 2537, name = "Quel'Thalas",    mapType = CONTINENT, parent = 13 },
}, CAT)
id, name = root()
ok(id == 2395,
   "a name-only category stops the climb - got " .. tostring(id)
   .. ", which means the per-hop test dropped categoryByName")
ok(name == "Eversong Woods", "the name-only match reports its own name, got " .. tostring(name))

-- 3b. The same trap one level up: an intermediate Zone matching by NAME alone must be taken
--     rather than passed over.
setMaps({
    { id = 9001, name = "Some Cellar",    mapType = ZONE,      parent = 2395 },
    { id = 2395, name = "Eversong Woods", mapType = ZONE,      parent = 2537 },
    { id = 2537, name = "Quel'Thalas",    mapType = CONTINENT, parent = 13 },
}, CAT)
id = root()
ok(id == 2395, "an intermediate name-only category is taken, got " .. tostring(id))

-- 3c. The MIRROR of the Eversong trap, and it needs a chain of its own. Silvermoon City is
--     reached by mapID and by NOTHING else - the category it belongs to is called "Eversong
--     Woods", which its name does not match either way round. The zone below it deliberately
--     matches nothing, so dropping categoryByMapID from the per-hop test changes the ANSWER
--     rather than just the route to it. Without this chain that mutant survives: the first
--     Zone and the matching Zone were the same map, so both branches agreed.
setMaps({
    { id = 9100, name = "Ruined Hall",     mapType = ZONE,      parent = 2393 },
    { id = 2393, name = "Silvermoon City", mapType = ZONE,      parent = 2537 },
    { id = 2537, name = "Quel'Thalas",     mapType = CONTINENT, parent = 13 },
}, CAT)
id, name = root()
ok(id == 2393,
   "a mapID-only category is taken - got " .. tostring(id)
   .. ", which means the per-hop test dropped categoryByMapID")
ok(name == "Silvermoon City", "the mapID-only match reports its own name, got " .. tostring(name))

-- 4. THE CONTINENT BOUND, and its contract is narrower than it first looks. A continent can
--    never ANSWER regardless, because the category test is gated on mapType == Zone - so a
--    chain that merely ends in a continent proves nothing about this guard. What the guard
--    alone stops is the walk CROSSING a continent to reach a Zone on the far side and counting
--    that one. Contrived topology on purpose: it is the guard's actual promise, and nothing
--    else in the walk keeps it.
setMaps({
    { id = 6001, name = "Near Zone",  mapType = ZONE,      parent = 6002 },
    { id = 6002, name = "In Between", mapType = CONTINENT, parent = 6003 },
    { id = 6003, name = "Voidstorm",  mapType = ZONE,      parent = 0 },
}, CAT)
id = root()
ok(id == 6001,
   "the walk refuses to cross above zone level and answers the near Zone, got " .. tostring(id))

-- 5. Nothing in the chain resolves: the answer is the FIRST Zone, which is what the old walk
--    returned. Every zone showing NO ROUTING today must keep showing exactly that.
setMaps({
    { id = 2444, name = "Slayer's Rise", mapType = ZONE,      parent = 2405 },
    { id = 2405, name = "Voidstorm",     mapType = ZONE,      parent = 2537 },
    { id = 2537, name = "Quel'Thalas",   mapType = CONTINENT, parent = 13 },
}, { COILED = CAT.COILED })
id, name = root()
ok(id == 2444, "no category anywhere falls back to the first Zone, got " .. tostring(id))
ok(name == "Slayer's Rise", "the fallback reports the first Zone's name, got " .. tostring(name))

-- 5b. The same fallback measured where it can actually be seen. Above, the first Zone and the
--     player's own map are the SAME map, so deleting the first-Zone fallback altogether left
--     the player-map fallback below it answering identically. Starting from a micro map splits
--     the two: the first Zone is 2405 and the player's map is 5556.
setMaps({
    { id = 5556, name = "A Cellar",    mapType = MICRO,     parent = 2405 },
    { id = 2405, name = "Voidstorm",   mapType = ZONE,      parent = 2537 },
    { id = 2537, name = "Quel'Thalas", mapType = CONTINENT, parent = 13 },
}, { COILED = CAT.COILED })
id, name = root()
ok(id == 2405,
   "with nothing resolving, the first ZONE wins over the player's own map, got " .. tostring(id))
ok(name == "Voidstorm", "the first-Zone fallback carries that zone's name, got " .. tostring(name))

-- 6. A micro-dungeon still counts against the zone around it, which is the behavior the
--    function was originally written for and must not lose.
setMaps({
    { id = 5555, name = "A Cave",     mapType = MICRO,     parent = 2405 },
    { id = 2405, name = "Voidstorm",  mapType = ZONE,      parent = 2537 },
    { id = 2537, name = "Quel'Thalas", mapType = CONTINENT, parent = 13 },
}, CAT)
id = root()
ok(id == 2405, "a micro map climbs to the zone around it, got " .. tostring(id))

-- 7. No Zone anywhere in the chain: fall back to the player's own map, so a category keyed on
--    a non-Zone mapID is still reachable through Count.
setMaps({
    { id = 7777, name = "Orphan Map", mapType = MICRO, parent = 947 },
    { id = 947,  name = "Azeroth",    mapType = WORLD, parent = 0 },
}, CAT)
id, name = root()
ok(id == 7777, "no Zone in the chain answers the player's own map, got " .. tostring(id))
ok(name == "Orphan Map", "the player-map fallback carries its name, got " .. tostring(name))

-- 8. THE HOP BOUND, measured from both sides against the SLICED constant rather than a copy.
--    A chain whose only resolving zone sits exactly AT the bound must be reached; one a single
--    hop PAST it must not. A long chain with nothing resolving in it proves only that the walk
--    terminates - it answers the first Zone for any bound at all, which is what let MAX_HOPS be
--    raised to 100 or dropped to 2 with this file green.
-- The literal, deliberately. Building the chains from OUT.maxHops made both bound cases
-- UNFAILABLE - the chain grew and shrank with the constant under test, so raising MAX_HOPS to
-- 100 or dropping it to 4 left this file green. Reading an expected value out of the thing you
-- are measuring is the defect a constant's own comment in this codebase exists to prevent. The
-- slice is still what supplies HOPS, so a changed constant fails HERE, by name, rather than
-- somewhere downstream.
local HOPS = OUT.maxHops
ok(HOPS == 5, "MAX_HOPS is still 5 - if this changed on purpose, fix the two chains below "
   .. "and their literals together, got " .. tostring(HOPS))

local function chainOf(n, base, resolverName)
    local c = {}
    for i = 1, n do
        c[i] = { id = base + i, name = "Deep " .. i, mapType = ZONE, parent = base + i + 1 }
    end
    c[n].name, c[n].parent = resolverName, 0
    return c
end

-- Five deep, resolver on the last hop the walk is allowed to take.
setMaps(chainOf(5, 8000, "Voidstorm"), CAT)
id = root()
ok(id == 8005, "a resolving zone exactly at MAX_HOPS is reached, got " .. tostring(id))

-- Six deep, resolver one hop out of reach. The walk must give up and answer the first Zone.
setMaps(chainOf(6, 8100, "Voidstorm"), CAT)
id = root()
ok(id == 8101, "a resolving zone one hop PAST MAX_HOPS is not reached, got " .. tostring(id))

-- 9. Memoized between zone changes. The tracker calls this once per render and Render is not
--    throttled, so a walk on every call would re-read the map chain during a slider drag.
setMaps({
    { id = 2444, name = "Slayer's Rise", mapType = ZONE,      parent = 2405 },
    { id = 2405, name = "Voidstorm",     mapType = ZONE,      parent = 2537 },
    { id = 2537, name = "Quel'Thalas",   mapType = CONTINENT, parent = 13 },
}, CAT)
local walkID, walkName = root()
local afterFirst = infoReads
-- The VALUES the cached branch hands back, not just the fact that it read nothing. Asserting
-- the read count alone left `return nil` from that branch invisible - which would draw the bar
-- once after a zone change and drop it on every render after, the whole feature gone.
local cachedID, cachedName = root()
local againID,  againName  = root()
ok(infoReads == afterFirst, "the root is memoized until dirty, reads went "
   .. afterFirst .. " -> " .. infoReads)
ok(cachedID == walkID and cachedName == walkName,
   "the cached branch answers the SAME pair the walk did, got "
   .. tostring(cachedID) .. "/" .. tostring(cachedName))
ok(againID == walkID and againName == walkName,
   "and keeps answering it, got " .. tostring(againID) .. "/" .. tostring(againName))
OUT.dirty()
root()
ok(infoReads > afterFirst, "dirty() makes the next call walk again")

-- 9b. parentMapID 0 means "no parent", and 0 is TRUTHY in Lua - so the guard against it is the
--     only thing between the walk and following a parent that is not one. Answering nil from
--     GetMapInfo(0) would mask that, so map 0 is made readable here and the walk is measured by
--     how far it travels: one read with the guard, more without it.
maps, playerMap, infoReads = {}, 4001, 0
maps[4001] = { name = "Lone Zone", mapType = ZONE, parentMapID = 0 }
maps[0]    = { name = "Cosmic",    mapType = 0,    parentMapID = 0 }
env.ns.ZONE_CATEGORIES = CAT
OUT.dirty()
id = root()
ok(id == 4001, "a parent of 0 still answers the zone underfoot, got " .. tostring(id))
ok(infoReads == 1,
   "a parent of 0 ends the walk rather than being followed, reads " .. infoReads)

-- 9c. A client whose Enum.UIMapType carries no Zone. Every mapType test must answer false
--     rather than true: a map info table with no mapType at all would otherwise compare
--     nil == nil and every map in the chain would read as a Zone. Degrades to the player's
--     own map, which is what the fallback is there for.
maps, playerMap, infoReads = {}, 7201, 0
maps[7201] = { name = "Nowhere",   parentMapID = 7202 }
maps[7202] = { name = "Voidstorm", parentMapID = 0 }
env.ns.ZONE_CATEGORIES = CAT
env.Enum = { UIMapType = {} }
OUT.dirty()
id, name, err = root()
env.Enum = { UIMapType = { Zone = ZONE } }
ok(err == nil, "a client with no Zone enum does not raise (" .. tostring(err) .. ")")
ok(id == 7201,
   "with no Zone enum no map reads as a Zone, so the player's map answers, got " .. tostring(id))
ok(name == "Nowhere", "and the fallback still names it, got " .. tostring(name))

-- 9d. A client with no Enum.UIMapType at all. The probe reads it defensively for this, and
--     without that guard the walk indexes a nil table and takes the whole render with it.
maps, playerMap, infoReads = {}, 7301, 0
maps[7301] = { name = "Somewhere", mapType = ZONE, parentMapID = 0 }
env.ns.ZONE_CATEGORIES = CAT
env.Enum = {}
OUT.dirty()
id, name, err = root()
env.Enum = { UIMapType = { Zone = ZONE } }
ok(err == nil, "no Enum.UIMapType does not raise (" .. tostring(err) .. ")")
ok(id == 7301, "and the player's own map still answers, got " .. tostring(id))
ok(name == "Somewhere", "and still names it, got " .. tostring(name))

-- 9e. A parent the client describes without a mapType. The above-zone guard tests that field
--     for existence before comparing it, and `nil < 3` raises rather than answering false.
maps, playerMap, infoReads = {}, 7401, 0
maps[7401] = { name = "Below",   mapType = ZONE, parentMapID = 7402 }
maps[7402] = { name = "Typeless",                parentMapID = 0 }
env.ns.ZONE_CATEGORIES = CAT
OUT.dirty()
id, name, err = root()
ok(err == nil, "a parent with no mapType does not raise (" .. tostring(err) .. ")")
ok(id == 7401, "and the first Zone still answers, got " .. tostring(id))
ok(name == "Below", "and names that Zone, got " .. tostring(name))

-- 10. Refusals. Neither may raise, both must answer nil so Current returns before Count, and
--     both must return before touching the map API at all - a walk that starts on a nil id and
--     happens to come back nil anyway is the same answer for the wrong reason, which is what
--     the read count is here to separate.
setMaps({ { id = 2444, name = "Slayer's Rise", mapType = ZONE, parent = 0 } }, CAT)
playerMap, infoReads = nil, 0
id, name, err = root()
ok(err == nil and id == nil, "no player map answers nil rather than raising")
ok(name == nil, "the refusal returns a bare nil rather than the previous zone's name")
ok(infoReads == 0, "no player map returns before reading any map, reads " .. infoReads)

setMaps({ { id = 2444, name = "Slayer's Rise", mapType = ZONE, parent = 0 } }, CAT)
playerMap, infoReads = 0, 0
id, name, err = root()
ok(err == nil and id == nil, "a map id of 0 answers nil rather than walking")
ok(name == nil, "the id-0 refusal returns a bare nil, not a stale pair")
ok(infoReads == 0, "a map id of 0 returns before reading any map, reads " .. infoReads)

setMaps({ { id = 2444, name = "Slayer's Rise", mapType = ZONE, parent = 0 } }, CAT)
env.ns.Has.Map, infoReads = false, 0
id, name, err = root()
ok(err == nil and id == nil, "a client with no map API answers nil")
ok(name == nil, "the capability refusal returns a bare nil, not a stale pair")
ok(infoReads == 0, "a client with no map API reads no map, reads " .. infoReads)
env.ns.Has.Map = true

-- 11. A map the client cannot describe. GetMapInfo answering nil mid-chain must not strand the
--     walk, and the player's own map is still the honest answer.
setMaps({ { id = 4242, name = "Known", mapType = MICRO, parent = 4243 } }, CAT)
id, name, err = root()
ok(err == nil, "an unreadable parent does not raise (" .. tostring(err) .. ")")
ok(id == 4242, "an unreadable parent falls back to the player's map, got " .. tostring(id))
ok(name == "Known", "the player-map fallback still carries its name, got " .. tostring(name))

print(("test_zone_root: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
