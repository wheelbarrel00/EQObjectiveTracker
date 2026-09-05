-- Unit tests for Data/Providers/WorldQuests.lua's zoneParent climb, run against the SHIPPED
-- source rather than a copy. Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_wq_zone.lua
--
-- WHY THIS FILE EXISTS. Measured in game on 2026-09-05, standing in Silvermoon City with the
-- world quest drawn in Blizzard's own tracker and absent from ours:
--
--     2393 Silvermoon City  mapType 3 (Zone)      parent 2395
--     2395 Eversong Woods   mapType 3 (Zone)      parent 2537
--     2537 Quel'Thalas      mapType 2 (Continent) parent 13
--     13   Eastern Kingdoms mapType 2 (Continent)
--
-- Midnight NESTS zones, and this walk deliberately does NOT climb through one: it stops the
-- moment the map underfoot is a Zone, so from Silvermoon City it never asks Eversong Woods.
-- Climbing through was tried on 2026-09-05 and REVERTED. It did not fix the world quest that
-- listed 25 seconds late, which was what it was written for, and it would have started listing
-- the enclosing zone's world quests while the player stands in a city inside it - a smaller
-- version of the report below. Do not re-apply it without a measurement that it fixes
-- something.
--
-- THE OPPOSITE FAILURE IS THE EXPENSIVE ONE AND IT HAS A REPORTER. Souseiseki87, 2026-08-21:
-- an unbounded climb reached a CONTINENT within two hops, and a continent's task list is every
-- in-progress task quest on it, which filled the section with Zul'Aman quests while standing on
-- The Coiled Isle. TWO guards stop this walk and the cases below assert each one alone: the
-- Zone underfoot ends it, and independently a parent above zone level is refused. The second is
-- the only one that fires when the player is standing in a SUB-AREA, which is the Coiled Isle
-- shape.
--
-- Data/Providers/WorldQuests.lua cannot be loaded whole without stubbing the quest log, the
-- task quest API, the entry store and the group cache, so zoneParent and MAP_DEPTH are sliced
-- out by TEXT ANCHORS rather than line numbers, which drift. If an anchor stops matching, fix
-- the anchor here rather than deleting the test.
--
-- OUT OF SCOPE BY CONSTRUCTION: everything the walk feeds. The task quest lists, the liveness
-- signals, the entry store and the super-track source are reached by no assertion here, so a
-- green run says nothing about them.

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

-- MAP_DEPTH is sliced rather than restated, so the hop-bound case is measured against the
-- shipped constant instead of a copy that could drift from it.
local depthSrc = sliceBetween("local MAP_DEPTH", "local store = Entry.NewStore")
local walkSrc  = sliceBetween("-- The bound both walks below need", "-- Walks the current map")

local chunk = assert(loadstring(
    depthSrc .. "\n" .. walkSrc .. "\nreturn zoneParent, MAP_DEPTH",
    "wq-zone-slice"))

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end

-- ------------------------------------------------------------------------- the client stubs

local CONTINENT, ZONE = 2, 3
local maps

local env = setmetatable({
    Enum  = { UIMapType = { Continent = CONTINENT, Zone = ZONE } },
    -- Raises on a nil or zero map id, the way a client API does rather than politely
    -- answering nil. A forgiving stub let zoneParent's own id guard be deleted with the file
    -- green, because nothing downstream could tell the two apart.
    C_Map = { GetMapInfo = function(id)
        if type(id) ~= "number" or id <= 0 then error("bad map id", 0) end
        return maps and maps[id] or nil
    end },
}, { __index = _G })

setfenv(chunk, env)
local zoneParent, MAP_DEPTH = chunk()

-- The ONLY way the cases below reach production. A raise has to FAIL a case, never kill the
-- run: the summary line would never print, and docs/mutate_wq_zone.py reads a missing summary
-- as a mutant that SURVIVED, which sends the next reader hunting a coverage hole that is not
-- there. Two mutants proved it on this file's first battery run.
local function parentOf(mapID, why)
    local okCall, res = pcall(zoneParent, mapID)
    ok(okCall, (why or "zoneParent") .. " does not raise" ..
       (okCall and "" or (" - " .. tostring(res))))
    if not okCall then return nil end
    return res
end

-- The chain exactly as it was measured in game, so a case describes a real hierarchy rather
-- than one invented to make the walk look right.
local function midnightChain()
    return {
        [2393] = { name = "Silvermoon City",  mapType = ZONE,      parentMapID = 2395 },
        [2395] = { name = "Eversong Woods",   mapType = ZONE,      parentMapID = 2537 },
        [2537] = { name = "Quel'Thalas",      mapType = CONTINENT, parentMapID = 13 },
        [13]   = { name = "Eastern Kingdoms", mapType = CONTINENT, parentMapID = 947 },
    }
end

-- ------------------------------------------------------------------------------- the cases

print("== the measured Midnight chain stops at the zone underfoot, by design")
do
    maps = midnightChain()
    -- The known limitation, asserted rather than left to be rediscovered: a world quest
    -- registered on Eversong Woods is not reachable from Silvermoon City by this walk.
    ok(parentOf(2393) == nil,
       "a Zone underfoot ends the climb, so the enclosing zone is never asked")
    ok(parentOf(2395) == nil,
       "and Eversong Woods stops too, which the continent guard would also have done")
end

print("== a continent can never be reached, however deep the nesting")
do
    -- Souseiseki87's bug: a continent's task list is every in-progress task quest on it, which
    -- is how quests from a zone the player had left kept refilling the section.
    -- Started from a SUB-AREA, not from the Zone itself. Starting on a Zone means the first
    -- guard answers immediately, the loop breaks before its first iteration, and the assertion
    -- inside it never runs at all - which is how this case sat inert against every mutant.
    maps = midnightChain()
    maps[1699] = { name = "Sinfall", mapType = 6, parentMapID = 2393 }
    local id, hops = 1699, 0
    while id and hops < 10 do
        local nxt = parentOf(id)
        if not nxt then break end
        -- Indexed defensively: an unbounded walk climbs off the end of this table, and an
        -- index of nil would ABORT the run rather than fail it, which every battery here reads
        -- as a mutant that SURVIVED.
        local mi = maps[nxt]
        ok(mi and mi.mapType ~= CONTINENT,
           "the walk never lands on a continent or off the map chain: " .. tostring(nxt))
        id, hops = nxt, hops + 1
    end
    ok(hops == 1, "and it stops one hop up, at the zone that encloses the sub-area: " .. hops)
end

print("== a sub-area below zone level still climbs, which always worked")
do
    -- The pre-existing case: a sanctum or a dungeon map inside a zone. This is what the walk
    -- was written for and it must not regress.
    maps = midnightChain()
    maps[1699] = { name = "Sinfall", mapType = 6, parentMapID = 2393 }
    ok(parentOf(1699) == 2393, "a micro-dungeon reaches the zone around it")
end

print("== TWO independent guards stop this walk, and each one alone is enough")
do
    -- The Zone-underfoot stop and the parent-type guard overlap on a normal chain. The second
    -- is the one that matters: the comment in production says so, and it is what refuses a
    -- continent reached from a SUB-ZONE, where the first guard never fires at all.
    maps = {
        [10] = { name = "inner", mapType = ZONE,      parentMapID = 20 },
        [20] = { name = "outer", mapType = ZONE,      parentMapID = 30 },
        [30] = { name = "land",  mapType = CONTINENT, parentMapID = 0 },
        [11] = { name = "cave",  mapType = 6,         parentMapID = 30 },
    }
    ok(parentOf(10) == nil, "a Zone underfoot stops on the first guard")
    ok(parentOf(11) == nil,
       "and a sub-zone whose parent is a continent stops on the second, which is the one "
       .. "Souseiseki87's report bought")
end

print("== the top of a hierarchy, and maps the client cannot answer for")
do
    -- Sub-zones rather than Zones, or the Zone-underfoot stop answers first and the parent
    -- guards these cases are about are never reached.
    maps = {
        [40] = { name = "top", mapType = 6, parentMapID = 0 },
        [41] = { name = "orphan", mapType = 6 },
    }
    -- 0 is truthy in Lua, so a bare truth test on parentMapID would climb to map zero.
    ok(parentOf(40) == nil, "parentMapID 0 is the top of the chain, not a map to climb to")
    ok(parentOf(41) == nil, "a map with no parent field at all answers nil")
    ok(parentOf(9999) == nil, "and a map the client knows nothing about answers nil")
    ok(parentOf(nil) == nil, "as does no map at all")
    ok(parentOf(0) == nil, "and map zero itself")
end

print("== a parent the client cannot answer for is still taken")
do
    -- The guard reads pinfo.mapType, and a nil pinfo means the client did not answer. Refusing
    -- there would drop a legitimate hop; the walk's own MAP_DEPTH is what bounds the damage.
    -- Deliberately a sub-zone rather than a Zone, or the first guard answers before the one
    -- this case is about is ever reached.
    maps = { [50] = { name = "child", mapType = 6, parentMapID = 51 } }
    ok(parentOf(50) == 51, "an unreadable parent does not end the climb")
end

print("== MAP_DEPTH is a real bound the callers can use")
do
    ok(type(MAP_DEPTH) == "number" and MAP_DEPTH >= 2,
       "MAP_DEPTH is a number and leaves room for the one hop the measured chain needs: "
       .. tostring(MAP_DEPTH))
    -- Written as a literal rather than derived from the constant under test, or the assertion
    -- grows and shrinks with it and can never fail.
    ok(MAP_DEPTH == 5, "and it is still 5")
end

print(("test_wq_zone: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
