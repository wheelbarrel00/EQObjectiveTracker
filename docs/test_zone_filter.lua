-- Unit tests for the retail quest provider's IsCurrentZone, run against the SHIPPED source.
-- Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_zone_filter.lua
--
-- IsCurrentZone is what Show only quests in current zone hides by and what Current zone first lifts a
-- zone header by. Every other harness stubs it. This one slices the real function and the zone set
-- under it out of Data/Providers/Quests.lua and runs them, with the real Core/Compat.lua deciding
-- whether the client is WoW Forever. Forever's quest log headings are zone names, as Classic's are,
-- and a quest's marker can sit in another zone: in Stormwind (2026-10-17) every quest under the
-- Stormwind City heading was marked at a hand-in elsewhere, so the marker rule alone hid them all.
-- There a heading naming the zone counts as well. Retail keeps the marker rule alone.
--
-- /eqot zoneprobe is loaded beside it, for the verdict it prints. OUT OF SCOPE: the probe's other
-- columns, and the climb to a parent map, which only the comments describe and no case here walks.

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

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end

local questsSrc = readFile("Data/Providers/Quests.lua")
local FROM, TO = "local zoneSet   = {}", "-- /eqot timer test's sample"
local from, to = questsSrc:find(FROM, 1, true), questsSrc:find(TO, 1, true)
assert(from and to and to > from, "the zone set and IsCurrentZone are found between their anchors")
local slice = questsSrc:sub(from, to - 1)
assert(slice:find("function Quests:IsCurrentZone(entry)", 1, true), "the slice holds IsCurrentZone")
local PFROM, PTO = "function Quests:ZoneProbeLines()", "-- Blizzard's tracker hands an auto-complete quest"
local pfrom, pto = questsSrc:find(PFROM, 1, true), questsSrc:find(PTO, 1, true)
assert(pfrom and pto and pto > pfrom, "the zone probe is found between its anchors")
slice = slice .. questsSrc:sub(pfrom, pto - 1)

-- The shipped Core/Compat.lua run over one interface number, so the Forever test is the real one.
local function compatFor(toc)
    local cns = {}
    local chunk = assert(loadfile(repoFile("Core/Compat.lua")))
    setfenv(chunk, setmetatable({
        GetBuildInfo = function() return "1.0.0", "1", "Jan 1 2026", toc end,
        CreateFrame = function() return { SetResizeBounds = function() end, SetParent = function() end } end,
    }, { __index = _G }))
    chunk("EQObjectiveTracker", cns)
    return cns
end
local FOREVER, RETAIL = compatFor(16001), compatFor(120100)
assert(FOREVER.IsForever() == true and RETAIL.IsForever() == false, "Compat tells the two clients apart")

local ZONE_TYPE = 3
-- Stormwind City and Westfall are zones under Eastern Kingdoms, a continent.
local MAPS = {
    [84]  = { name = "Stormwind City", mapType = ZONE_TYPE, parentMapID = 13 },
    [52]  = { name = "Westfall", mapType = ZONE_TYPE, parentMapID = 13 },
    [13]  = { name = "Eastern Kingdoms", mapType = 2, parentMapID = 947 },
}

-- o.client: FOREVER or RETAIL. o.map: the player's map. o.onMap: map id to the quest ids with a
-- marker on it (an absent map answers nil, as the client does for one it cannot read). o.zoneText:
-- what GetZoneText answers, or false for a client without it. Every scenario loads the slice afresh,
-- so its cached set starts empty.
local function load(o)
    local st = { asked = 0 }
    local env = setmetatable({
        ns = { Has = { QuestsOnMap = true, Map = true }, IsForever = o.client.IsForever },
        wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
        Enum = { UIMapType = { Zone = ZONE_TYPE } },
        C_Map = {
            GetBestMapForUnit = function(unit)
                assert(unit == "player", "the player's map is asked for")
                return o.map
            end,
            GetMapInfo = function(id) return MAPS[id] end,
        },
        C_QuestLog = {
            GetNumQuestLogEntries = function() return o.log and #o.log or 0 end,
            GetInfo = function(i) return o.log and o.log[i] end,
            GetQuestsOnMap = function(id)
                st.asked = st.asked + 1
                local ids = o.onMap and o.onMap[id]
                if not ids then return nil end
                local list = {}
                for i, q in ipairs(ids) do list[i] = { questID = q } end
                return list
            end,
        },
    }, { __index = _G })
    if o.zoneText ~= false then
        env.GetZoneText = function() return o.zoneText end
    end
    local Quests = {}
    local chunk = assert(loadstring("local Quests = ...\n" .. slice, "zone-slice"))
    setfenv(chunk, env)
    chunk(Quests)
    function st.probe()
        local okCall, lines = pcall(Quests.ZoneProbeLines, Quests)
        ok(okCall, "ZoneProbeLines does not raise" .. (okCall and "" or (" - " .. tostring(lines))))
        return okCall and lines or {}
    end
    function st.at(id, zone)
        local okCall, verdict = pcall(Quests.IsCurrentZone, Quests, { id = id, zone = zone })
        ok(okCall, "IsCurrentZone does not raise" .. (okCall and "" or (" - " .. tostring(verdict))))
        return verdict
    end
    return st
end

-- --------------------------------------------------------------------- WoW Forever

-- The reported case: standing in Stormwind, no quest has its marker there.
local s = load({ client = FOREVER, map = 84, onMap = { [84] = {}, [13] = { 141 } }, zoneText = "Stormwind City" })
ok(s.at(345, "Stormwind City") == true, "Forever: a quest under the Stormwind City heading is in Stormwind")
ok(s.at(538, "Stormwind City") == true, "and so is every other quest under it")
ok(s.at(141, "Westfall") == false, "a quest under another zone's heading is not")
ok(s.at(471, nil) == false, "nor is a quest with no heading")
ok(s.at(999, "Stormwind") == false, "the heading has to name the zone exactly")
ok(s.at(998, "Stormwind City Outskirts") == false, "a heading that only starts with the zone's name is elsewhere")

-- The marker rule still counts on Forever, so nothing that showed before now hides.
s = load({ client = FOREVER, map = 84, onMap = { [84] = { 141 } }, zoneText = "Stormwind City" })
ok(s.at(141, "Westfall") == true, "Forever: a quest whose marker is on the map is in the zone, whatever its heading")
ok(s.at(345, "Stormwind City") == true, "beside the quests the heading places there")
ok(s.at(471, "Wetlands") == false, "and a quest with neither is elsewhere")

-- A heading match answers without the map, so a client that cannot read the map still places it.
s = load({ client = FOREVER, map = nil, onMap = {}, zoneText = "Stormwind City" })
ok(s.at(345, "Stormwind City") == true, "Forever: the heading places a quest with no map at all")
ok(s.at(141, "Westfall") == nil, "and anything else is still a cannot-tell, which the filter fails open on")
s = load({ client = FOREVER, map = 84, onMap = {}, zoneText = "Stormwind City" })
ok(s.at(141, "Westfall") == nil, "a map the client cannot read is a cannot-tell too")

-- No zone text means the marker rule alone.
for _, c in ipairs({ { "an empty zone text", "" }, { "no zone text", nil }, { "a client without GetZoneText", false } }) do
    s = load({ client = FOREVER, map = 84, onMap = { [84] = { 141 } }, zoneText = c[2] })
    ok(s.at(345, "") == false, "Forever with " .. c[1] .. ": an empty heading never matches")
    ok(s.at(471, nil) == false, "Forever with " .. c[1] .. ": nor does a missing one")
    ok(s.at(345, "Stormwind City") == false, "Forever with " .. c[1] .. ": the heading counts for nothing")
    ok(s.at(141, "Westfall") == true, "Forever with " .. c[1] .. ": the marker still does")
end

-- ---------------------------------------------------------------------------- retail

-- Retail headings are campaign groupings that rarely equal the zone text, so the marker rule stays
-- alone there.
s = load({ client = RETAIL, map = 84, onMap = { [84] = {}, [13] = {} }, zoneText = "Stormwind City" })
ok(s.at(345, "Stormwind City") == false, "retail: a heading naming the zone does not place a quest")
s = load({ client = RETAIL, map = 84, onMap = { [84] = { 141 } }, zoneText = "Stormwind City" })
ok(s.at(141, "Westfall") == true, "retail: a quest whose marker is on the map is in the zone")
ok(s.at(345, "Stormwind City") == false, "and one without a marker is not, whatever its heading")
s = load({ client = RETAIL, map = 84, onMap = {}, zoneText = "Stormwind City" })
ok(s.at(345, "Stormwind City") == nil, "retail: a map the client cannot read is a cannot-tell")
s = load({ client = RETAIL, map = 52, onMap = { [52] = { 141 } }, zoneText = "Westfall" })
ok(s.at(141, "Westfall") == true and s.at(345, "Stormwind City") == false, "retail: the player's own map is the one read")

-- ------------------------------------------------------------------- the zone probe's verdict

-- The probe hands IsCurrentZone each quest with its heading, so its verdict is the filter's.
local LOG = {
    { isHeader = true, title = "Stormwind City" },
    { questID = 345, title = "The Fargodeep Mine" },
    { isHeader = true, title = "Westfall" },
    { questID = 141, title = "Report to Gryan" },
}
local function verdictOf(lines, id)
    for _, l in ipairs(lines) do
        if l:match("^%s+" .. id .. " ") then return l:match("(%S+)%s+| [^|]* | [^|]*$") end
    end
end
s = load({ client = FOREVER, map = 84, onMap = { [84] = {} }, zoneText = "Stormwind City", log = LOG })
local probed = s.probe()
ok(verdictOf(probed, 345) == "true", "Forever: the probe says a quest under the zone's heading is in it: "
   .. tostring(verdictOf(probed, 345)))
ok(verdictOf(probed, 141) == "false", "and one under another zone's is not")
ok(probed[1] and probed[1]:find("zone text Stormwind City (Forever: a heading naming it counts)", 1, true) ~= nil,
   "its first line names the zone text and the Forever rule")
s = load({ client = RETAIL, map = 84, onMap = { [84] = {} }, zoneText = "Stormwind City", log = LOG })
probed = s.probe()
ok(verdictOf(probed, 345) == "false", "retail: the probe follows the marker rule alone")
ok(probed[1] and probed[1]:find("(Forever", 1, true) == nil, "and names no Forever rule")

print(string.format("test_zone_filter: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
