-- luacheck: globals C_Scenario C_ScenarioInfo C_UIWidgetManager C_UnitAuras C_VignetteInfo
-- luacheck: globals Enum GetInstanceInfo GetQuestLogRewardInfo HaveQuestRewardData
-- luacheck: globals geterrorhandler time tremove wipe
--
-- Unit tests for the delve half of the scenario bonus HUD, run against the SHIPPED source
-- rather than a copy. Run from the repo root with the game's own Lua:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_scenario_bonus.lua
--
-- What earns this harness, every item a bug that shipped or nearly shipped and none of which
-- raised an error:
--
--   The pack vignette LIST. One hardcoded seasonal id is what left this HUD showing nothing
--   in Midnight delves, so the season-1 and season-2 ids are both asserted here. A future
--   season appends; anyone collapsing this back to one id fails these tests.
--
--   The per-vignette name guard. A delve vignette name can be a secret value that throws on
--   any string method, and the scan runs inside the caller's pcall - so an unguarded name
--   aborts the whole scan and silently loses every pack after it.
--
--   THE FLUSHED LIST. Kills are inferred from packs going away, so an empty vignette list -
--   which is what a loading screen hands back - used to read as every pack killed at once,
--   draw green with both packs alive, and write that into the saved run.
--
--   The saved run. Deaths and the pack tally have to survive a /reload and must NOT survive
--   the player leaving, and the record must not be written at all for the majority of players
--   who never switch this HUD on.
--
-- Read the note above fakeGuid before changing a fixture: the vignette GUID REGENERATES on
-- the live client, and a fixture that pretends otherwise makes the dedupe test meaningless.

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
end

local ns = { L = setmetatable({}, { __index = function(_, k) return k end }) }
local mods = {}
function ns:RegisterModule(n, t) mods[n] = t return t end
function ns:GetModule(n) return mods[n] end

wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
tremove = table.remove
time = os.time                    -- a WoW global, and vanilla Lua only has os.time
geterrorhandler = function() return function(e) error(e, 0) end end

-- Debounce runs its callback straight through: this harness tests the model, not the timer.
-- On/Off record handlers so the death counter and the world transitions are driven through the
-- REAL registrations rather than by reaching past them.
local handlers = {}
mods.Events = {
    Debounce = function(_, _, _, fn) if fn then fn() end end,
    On  = function(_, event, fn) handlers[event] = fn end,
    Off = function(_, event) handlers[event] = nil end,
}

local CFG = { scenarioBonusHUD = { enabled = true } }
-- CHAR stands in for the saved variables: it deliberately SURVIVES a module reload below,
-- which is the whole point of the persistence tests.
local CHAR = {}
mods.DB = { Tracker = function() return CFG end, Char = function() return CHAR end }
ns.Has = { ScenarioBonus = true }

local INSTANCE_NAME, DIFF = "The Ring of Glory", 208
GetInstanceInfo = function() return INSTANCE_NAME, "scenario", DIFF end

local TIER = 6
Enum = { UIWidgetVisualizationType = { ScenarioHeaderDelves = 30 } }
C_ScenarioInfo = { GetScenarioStepInfo = function() return { widgetSetID = 842 } end }
C_UIWidgetManager = {
    GetAllWidgetsBySetID = function() return { { widgetType = 30, widgetID = 1 } } end,
    GetScenarioHeaderDelvesWidgetVisualizationInfo = function()
        return { tierText = tostring(TIER) }
    end,
}
C_Scenario   = { GetBonusSteps = function() return {} end }
C_UnitAuras  = { GetPlayerAuraBySpellID = function() return nil end }
HaveQuestRewardData = function() return true end
GetQuestLogRewardInfo = function() return nil end

-- Each entry is { vignetteID, objectGUID, name }. SECRET_NAME stands in for a Midnight secret
-- value, and it has to satisfy BOTH halves of what makes one dangerous: type() reports
-- "string" AND any string method throws. A plain table was tried first and reported a false
-- pass - it fails the type() test, so the guarded branch was skipped rather than survived.
-- Overriding string.lower is what reproduces it, and it covers the nm:lower() method form too,
-- since a string method resolves through this same table.
local SECRET_NAME = "|secret|"
local realLower = string.lower
-- luacheck: push ignore 122
-- Replacing a field of the string table is exactly the point here and nowhere else, so the
-- warning is suppressed for these three lines rather than in .luacheckrc, which this repo
-- keeps strict at zero warnings.
string.lower = function(v)
    if v == SECRET_NAME then error("attempt to use a secret value", 0) end
    return realLower(v)
end
-- luacheck: pop

-- A name that survives lower() and dies on find(). The header model of a secret value is that
-- it errors when MATCHED, so find is the call that raises - and a guard wrapped around lower()
-- alone never sees it. Overriding string.find is what reproduces that half.
local FIND_TRAP_NAME = "|findtrap|"
local realFind = string.find
-- luacheck: push ignore 122
string.find = function(v, ...)
    if v == FIND_TRAP_NAME then error("attempt to match a secret value", 0) end
    return realFind(v, ...)
end
-- luacheck: pop

-- A vignette id that dies the moment anything prints it. The dump's guard used to be one pcall
-- around the NAME while this sat beside it in the same argument list, which Lua evaluates
-- first - so the guard could never fire and the whole command died instead.
local UNPRINTABLE_ID = setmetatable({}, {
    __tostring = function() error("attempt to print a secret value", 0) end,
})

local VIGNETTES = {}
-- Two markers reproduce what a live delve returned: "hole" leaves a real nil in the guid
-- array, which is what stops ipairs dead, and { dead = id } hands back a guid whose info will
-- not resolve. The live dump read "vignettes=5" above a list of four, which is the second.
--
-- Guids are shaped like the real thing - Vignette-0-<server>-<instance>-<zone>-<id>-<spawn> -
-- because production decodes field SIX out of them. The index rides in field five so this stub
-- can find its entry without production caring.
--
-- The SPAWN field moves on every scan, and that is not decoration: a live vignette GUID
-- regenerates, which is the entire reason the dedupe key is objectGUID. A fixed guid here let
-- a test pass with the key swapped to the regenerating one, which is the double-counting bug
-- this feature already shipped once.
local scanSeq = 0
local function fakeGuid(i, id)
    return ("Vignette-0-3782-%d-%d-%d-%08X"):format(2979, i, id, scanSeq)
end

local function entryID(v)
    if type(v) ~= "table" then return 0 end
    local id = v.dead or v[1]
    -- A fixture id can be a value that is not a number at all, and the guid is built with
    -- %d - the STUB must not be what throws first, or the case under test never runs.
    return type(id) == "number" and id or 0
end

C_VignetteInfo = {
    GetVignettes = function()
        scanSeq = scanSeq + 1
        local out = {}
        for i = 1, #VIGNETTES do
            if VIGNETTES[i] ~= "hole" then out[i] = fakeGuid(i, entryID(VIGNETTES[i])) end
        end
        return out
    end,
    GetVignetteInfo = function(guid)
        local i = tonumber(guid:match("^Vignette%-%d+%-%d+%-%d+%-(%d+)%-"))
        local v = VIGNETTES[i]
        if type(v) ~= "table" or v.dead then return nil end
        return { vignetteID = v[1], objectGUID = v[2], name = v[3] }
    end,
}

assert(loadfile(repoFile("Data/ScenarioBonus.lua")))("EQObjectiveTracker", ns)
local Bonus = mods.ScenarioBonus
assert(Bonus, "Data/ScenarioBonus.lua did not register the ScenarioBonus module")
-- The world transitions are what drive checkRun, and the exit branch cannot be reached without
-- them: GetModel never calls it from outside a delve.
Bonus:OnEnable()

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end

-- Force a clean run: the module resets per-run state when the delve NAME changes.
local runSeq = 0
local function newRun(vigs)
    runSeq = runSeq + 1
    INSTANCE_NAME = "Delve Run " .. runSeq
    VIGNETTES = vigs or {}
    return Bonus:GetModel()
end

local function strongboxLine(m)
    if not m then return nil end
    for i = 1, #m do
        local crit = m[i].criteria
        for c = 1, #crit do
            if crit[c].text:find("Strongbox", 1, true) then return crit[c] end
        end
    end
    return nil
end

local function boxReads(m, want)
    local line = strongboxLine(m)
    return line and line.text:find(want, 1, true) ~= nil
end

local function statLine(model)
    if not model then return nil end
    for i = 1, #model do
        local crit = model[i].criteria
        for c = 1, #crit do
            if crit[c].kind == "stat" then return crit[c] end
        end
    end
    return nil
end

-- Every read of a line's text goes through these. One regression that returns nil here used to
-- abort the whole run on a nil index and mask every assertion after it.
local function boxText(m)
    local line = strongboxLine(m)
    return line and line.text or "<no Strongbox line>"
end

local function statText(m)
    local line = statLine(m)
    return line and line.text or "<no stat line>"
end

local function pack(guid, id) return { id or 7869, guid, "Ulatek's Chosen" } end

local function bannerLine(m)
    if not m then return nil end
    for i = 1, #m do
        local crit = m[i].criteria
        for c = 1, #crit do
            if crit[c].text:find("Banner", 1, true) then return crit[c] end
        end
    end
    return nil
end

local function bannerText(m)
    local line = bannerLine(m)
    return line and line.text or "<no Banner line>"
end

-- 1-2. Both seasons count. A single id here is the bug this file exists to prevent.
local m = newRun({ { 7531, "npc-A", "Nullaeus Minions" } })
ok(strongboxLine(m) ~= nil, "season 1 vignette 7531 is counted as a pack")

m = newRun({ { 7869, "npc-A", "Ulatek's Chosen" } })
ok(strongboxLine(m) ~= nil, "season 2 vignette 7869 is counted as a pack")

-- 3. An unrelated vignette must not be counted, or every delve reads as full of packs.
m = newRun({ { 6127, "npc-X", "Exit" }, { 7135, "npc-Y", "Valeera Sanguinar" } })
ok(strongboxLine(m) == nil, "non-pack vignettes are not counted")

-- 4-5. Mixed seasons in one run, which is what "append, never replace" buys. Run at TIER 4,
-- where the floor is ONE pack: at tier 6 the floor is 2 and one id counting would render
-- 0/2 exactly like two, so the case could not fail.
TIER = 4
m = newRun({ { 7531, "npc-A", "Nullaeus Minions" } })
ok(boxReads(m, "0/1"), "one season-1 id alone reads 0/1 at tier 4: " .. boxText(m))
m = newRun({ { 7531, "npc-A", "Nullaeus Minions" }, { 7869, "npc-B", "Ulatek's Chosen" } })
ok(boxReads(m, "0/2"), "both seasons' ids count together, 0/2 packs: " .. boxText(m))
TIER = 6

-- 6. THE ONE THAT SHIPPED. A name that throws must not lose the pack listed after it.
m = newRun({
    { 6171, "npc-X", SECRET_NAME },
    { 7869, "npc-B", "Ulatek's Chosen" },
})
ok(boxReads(m, "0/2"), "a secret vignette name does not abort the scan: " .. boxText(m))

-- 7. And it must not lose a pack listed BEFORE it either. Reading the TEXT rather than only
-- the line's presence: a scan that aborts after the pack still leaves a line behind.
m = newRun({
    { 7869, "npc-B", "Ulatek's Chosen" },
    { 6171, "npc-X", SECRET_NAME },
})
ok(boxReads(m, "0/2"), "a secret name after a pack is survived too: " .. boxText(m))

-- 8. And the guard has to cover the MATCHING, not just the lower(). A name that survives
-- lower() and throws on find() escapes a guard wrapped around lower() alone, and the escape
-- lands in the caller's pcall - which loses every vignette after it, packs included.
m = newRun({
    { 6171, "npc-X", FIND_TRAP_NAME },
    { 7869, "npc-B", "Ulatek's Chosen" },
})
ok(boxReads(m, "0/2"),
   "a name that throws on find rather than lower is survived too: " .. boxText(m))

-- 9. Two packs either side of a bad name still both count.
m = newRun({
    { 7869, "npc-B", "Ulatek's Chosen" },
    { 6171, "npc-X", SECRET_NAME },
    { 7531, "npc-C", "Nullaeus Minions" },
})
ok(boxReads(m, "0/2"), "packs either side of a secret name both count: " .. boxText(m))

-- 10. Distinct packs key on objectGUID, so re-scanning the same pack cannot inflate the tally.
-- The guid moves between scans, exactly as the live one does, so keying on it fails here.
newRun({ pack("npc-B") })
Bonus:GetModel()
m = Bonus:GetModel()
ok(boxReads(m, "0/2"), "re-scanning one pack does not double-count it: " .. boxText(m))

-- 11. A pack that despawns is a pack killed: seen 2, remaining 1.
newRun({ pack("npc-B"), pack("npc-C") })
VIGNETTES = { pack("npc-B") }
m = Bonus:GetModel()
ok(boxReads(m, "1/2"), "a despawned pack counts as killed, 1/2: " .. boxText(m))

-- 12-13. The tier floor: an unfinished run still shows how many packs the tier will hand out.
TIER = 6
m = newRun({ pack("npc-B") })
ok(boxReads(m, "0/2"), "tier 6 floors the total at 2 packs: " .. boxText(m))

TIER = 10
m = newRun({ pack("npc-B") })
ok(boxReads(m, "0/4"), "tier 10 floors the total at 4 packs: " .. boxText(m))
TIER = 6

-- 14. Leaving the delve resets the tally. Driven through the REAL world transition and back
-- into the SAME delve name: a new name resets the run on its own, so a test that changes it
-- passes with the exit branch deleted outright.
newRun({ pack("npc-B"), pack("npc-C") })
local sameDelve = INSTANCE_NAME
DIFF = 0
handlers.PLAYER_ENTERING_WORLD()
DIFF = 208
INSTANCE_NAME = sameDelve
VIGNETTES = { pack("npc-D") }
m = Bonus:GetModel()
ok(boxReads(m, "0/2"), "re-entering the same delve after leaving starts clean: " .. boxText(m))

-- 15. Nothing at all is drawn when the HUD is switched off, whatever the vignettes say.
CFG.scenarioBonusHUD.enabled = false
m = newRun({ pack("npc-B") })
ok(m == nil, "no model at all while the HUD is switched off")

-- 16. And nothing is WRITTEN either. checkRun is driven from the world transitions, which do
-- not ask whether the feature is on, so an ungated write lands a saved variable on every
-- player who walks into a delve - and this HUD ships off.
CHAR.delveRun = nil
runSeq = runSeq + 1
INSTANCE_NAME = "Delve Run " .. runSeq
VIGNETTES = { pack("npc-B") }
handlers.PLAYER_ENTERING_WORLD()
ok(CHAR.delveRun == nil, "no saved run is written for a player who never switched the HUD on")
CFG.scenarioBonusHUD.enabled = true

-- 17-19. The instrument. A season that moves the id must be READABLE from one dump, which
-- means naming the ids being matched and marking the vignettes that matched them.
newRun({ pack("npc-B"), { 6127, "npc-X", "Exit" }, { 6171, "n", SECRET_NAME } })
local dump = table.concat(Bonus:DumpLines({}), "\n")
ok(dump:find("pack vignette ids matched: 7531, 7869", 1, true) ~= nil,
   "the dump names every id it matches on")
ok(dump:find("id=7869 (guid id 7869) PACK", 1, true) ~= nil,
   "a matching vignette is marked PACK")
ok(dump:find("id=6127 (guid id 6127) name=Exit", 1, true) ~= nil,
   "a non-matching vignette carries no marker")

-- 20-21. A value that will not print must cost its own line and nothing else. The guard used
-- to be one pcall around the NAME, and the vignette id sat beside it in the same argument
-- list - which Lua evaluates first, so the guard could not fire and the whole command died.
-- This is the one instrument this feature is diagnosed from.
newRun({ pack("npc-B"), { UNPRINTABLE_ID, "npc-X", "harmless" } })
local okDump, dumpU = pcall(function() return table.concat(Bonus:DumpLines({}), "\n") end)
ok(okDump, "a vignette whose values will not print does not kill the whole dump")
ok(okDump and dumpU:find("id=7869 (guid id 7869) PACK", 1, true) ~= nil,
   "and every other vignette still reports: "
   .. (okDump and "dump ran" or tostring(dumpU)))

-- 22-33. Lives and the death counter.

-- The reader is registered by UI/ScenarioBonusHUD.lua in the real addon, and its frame walk is
-- tested against the shipped source at the bottom of this file. Here it is a stub, so what is
-- under test is the seam and the model.
local livesAnswer, livesSawTier = nil, nil
Bonus:SetLivesReader(function(tier) livesSawTier = tier return livesAnswer end)

livesAnswer = nil
m = newRun({ pack("npc-B") })
ok(statLine(m) ~= nil, "a stat line is drawn in a delve")
ok(statText(m):find("Deaths: 0", 1, true) ~= nil, "deaths start at zero: " .. statText(m))
ok(statText(m):find("Lives", 1, true) == nil,
   "the Lives half is omitted when the reader finds nothing: " .. statText(m))

-- The reader must be handed the tier: it anchors on it to pick the right digit.
TIER = 7
livesAnswer = 6
m = newRun({ pack("npc-B") })
ok(livesSawTier == 7, "the lives reader is handed the delve tier to anchor on")
ok(statText(m):find("Lives: 6", 1, true) ~= nil,
   "lives are drawn when the reader answers: " .. statText(m))
TIER = 6

-- Deaths come from the real PLAYER_DEAD registration, so Reconcile has to have wired it.
Bonus:Reconcile()
ok(handlers.PLAYER_DEAD ~= nil, "PLAYER_DEAD is registered while in a delve")
handlers.PLAYER_DEAD()
handlers.PLAYER_DEAD()
m = Bonus:GetModel()
ok(statText(m):find("Deaths: 2", 1, true) ~= nil, "two deaths are counted: " .. statText(m))

-- A death outside a delve belongs to somebody else's content.
DIFF = 0
handlers.PLAYER_DEAD()
DIFF = 208
m = Bonus:GetModel()
ok(statText(m):find("Deaths: 2", 1, true) ~= nil,
   "a death outside a delve is not counted: " .. statText(m))

m = newRun({ pack("npc-D") })
ok(statText(m):find("Deaths: 0", 1, true) ~= nil,
   "a new run resets the death count: " .. statText(m))

-- The reader walks Blizzard's frames and is registered from another module, so a throw there
-- has to cost the Lives half of one line rather than the whole model.
Bonus:SetLivesReader(function() error("the tracker moved", 0) end)
m = newRun({ pack("npc-B") })
ok(statLine(m) ~= nil and statText(m):find("Lives", 1, true) == nil,
   "a lives reader that throws drops the Lives half rather than the model: " .. statText(m))
ok(pcall(function() return Bonus:DumpLines({}) end),
   "and it does not take the dump down either")
Bonus:SetLivesReader(function() return livesAnswer end)

-- The stat line alone keeps the model non-empty, so the HUD now draws in a delve that has no
-- pack and no banner at all. That is a deliberate behavior change, not a leak.
livesAnswer = nil
m = newRun({ { 6127, "npc-X", "Exit" } })
ok(m ~= nil and statLine(m) ~= nil,
   "a delve with no bonus mechanics still draws the run readout")

-- 34-37. A vignette the scan cannot read must not take the rest of the list with it. This is
-- what a live T7 delve showed: five vignettes counted, four listed.

livesAnswer = nil

-- A guid that resolves to nothing, with a real pack listed after it.
m = newRun({ { dead = 6116 }, pack("npc-B") })
ok(boxReads(m, "0/2"),
   "a vignette whose info will not resolve does not hide the pack after it: " .. boxText(m))

-- A genuine nil hole in the guid array. ipairs stops at it and loses everything past it.
local holed = { pack("npc-B"), "hole", pack("npc-C"), { 7531, "npc-D", "Nullaeus Minions" } }
VIGNETTES = holed
do
    -- # on a holed array is UNDEFINED in Lua 5.1, and this fixture only crosses the hole
    -- because the length still reports past it. Asserted rather than assumed: shortening the
    -- fixture could silently stop testing the hole at all and nothing would say so.
    local probe = C_VignetteInfo.GetVignettes()
    assert(probe[2] == nil, "the holed fixture must leave a real nil in the guid array")
    assert(#probe == #holed,
        "# stopped reporting past the hole: this fixture no longer tests the hole")
end
m = newRun(holed)
ok(boxReads(m, "0/3"), "a nil hole in the vignette list does not truncate the scan: " .. boxText(m))

-- And the misses are reported rather than absorbed, as a NUMBER: matching the format string's
-- own literal is a test of the format string, not of the count.
local dump2 = table.concat(Bonus:DumpLines({}), " | ")
ok(dump2:match("could not read: (%d+)") == "1",
   "the dump reports how many vignettes it could not read, and the count is right")
ok(dump2:find("UNREADABLE", 1, true) ~= nil, "each unreadable vignette is named, not skipped")

-- 38-40. The miss count belongs to THIS scan. It is a file-local like every other counter, so
-- it has to be reset with the run - and that reset is only observable when the next scan
-- RETURNS EARLY, because a scan that completes overwrites the number anyway. Early is exactly
-- when a stale count is most misleading: it reports the last delve's misses as this one's.
newRun({ pack("npc-B") })
ok(table.concat(Bonus:DumpLines({}), " | "):match("could not read: (%d+)") == "0",
   "the miss count does not carry over from the previous run")

newRun({ { dead = 6116 }, pack("npc-B") })
ok(table.concat(Bonus:DumpLines({}), " | "):match("could not read: (%d+)") == "1",
   "a miss in this run is reported")

local realGetVignettes = C_VignetteInfo.GetVignettes
C_VignetteInfo.GetVignettes = function() error("the client refused", 0) end
newRun({ pack("npc-C") })
C_VignetteInfo.GetVignettes = realGetVignettes
ok(table.concat(Bonus:DumpLines({}), " | "):match("could not read: (%d+)") == "0",
   "a scan that returns early reports no misses rather than the last run's")

-- 41-44. Decoding the id out of the guid, which is the only handle on a vignette whose info
-- will not resolve. The unreadable one in the live T7 reading was guid id 6116.

newRun({ { 6127, "npc-X", "Exit" }, { dead = 6116 }, pack("npc-B") })
local dump3 = table.concat(Bonus:DumpLines({}), " | ")
ok(dump3:find("UNREADABLE guid id=6116", 1, true) ~= nil,
   "an unreadable vignette still reports the id decoded from its guid")
ok(dump3:find("id=6127 (guid id 6127)", 1, true) ~= nil,
   "a readable vignette prints both ids, which is what proves the decode")
ok(dump3:find("id=7869 (guid id 7869) PACK", 1, true) ~= nil,
   "the guid id agrees with the real id on a pack too")

-- A pack that cannot be read is still flagged, so a season that makes packs unreadable is
-- visible in one line rather than looking like an empty delve.
newRun({ { dead = 7869 } })
local dump4 = table.concat(Bonus:DumpLines({}), " | ")
ok(dump4:find("UNREADABLE guid id=7869 PACK", 1, true) ~= nil,
   "an unreadable vignette that matches a pack id is flagged PACK")

-- 45-51. THE FLUSHED LIST, traced end to end. Kills are inferred from packs GOING AWAY, so an
-- empty vignette list - which is what a loading screen hands back - used to read as every pack
-- killed at once. It drew green with both packs alive, wrote that into the saved run, and a
-- math.max there kept it: a two-pack delve came back from the next reload reading 2/4.

livesAnswer = nil
m = newRun({ pack("npc-B"), pack("npc-C") })
ok(boxReads(m, "0/2"), "both packs alive reads 0/2: " .. boxText(m))

VIGNETTES = {}                    -- the loading screen
m = Bonus:GetModel()
ok(boxReads(m, "0/2"), "a flushed vignette list does not read as every pack killed: " .. boxText(m))
ok(strongboxLine(m) and strongboxLine(m).completed == false,
   "and the line is not drawn complete while both packs are alive")
ok(CHAR.delveRun and CHAR.delveRun.packsKilled == 0,
   "and nothing is written to the saved run: packsKilled="
   .. tostring(CHAR.delveRun and CHAR.delveRun.packsKilled))

VIGNETTES = { pack("npc-B"), pack("npc-C") }   -- the list comes back
m = Bonus:GetModel()
ok(boxReads(m, "0/2"), "the count is unchanged when the list returns: " .. boxText(m))

-- A pack that will not resolve for one scan reads as killed while it does not resolve, and the
-- count has to correct back DOWN when it resolves again. A ratchet on the saved value looks
-- like the safe choice here and is what holds a wrong reading for the rest of the run.
VIGNETTES = { pack("npc-B"), { dead = 7869 } }
m = Bonus:GetModel()
ok(boxReads(m, "1/2"), "a pack that will not resolve reads as killed while it does not: "
   .. boxText(m))
VIGNETTES = { pack("npc-B"), pack("npc-C") }
m = Bonus:GetModel()
ok(boxReads(m, "0/2") and CHAR.delveRun.packsKilled == 0,
   "the count corrects back down when it resolves again, saved value included: "
   .. boxText(m) .. " saved=" .. tostring(CHAR.delveRun.packsKilled))

-- 52-61. Surviving a /reload. The author reloaded a few times hunting a banner and came back
-- to Deaths: 0 and no Strongbox line at all, while Everything Delves still read 2 deaths and
-- 2/2 packs - so this is the case that matters, not a nicety.

-- A real reload: fresh module state, saved variables intact. Reloading the file is the only
-- honest way to test that, because every counter is a file-local.
local function reloadAddon()
    assert(loadfile(repoFile("Data/ScenarioBonus.lua")))("EQObjectiveTracker", ns)
    Bonus = mods.ScenarioBonus
    -- The tier capture is not re-armed: it was asserted before the reload and nothing after
    -- this point reads it.
    Bonus:SetLivesReader(function() return livesAnswer end)
    Bonus:OnEnable()
end

-- The flush case survives a reload too, which is where it used to surface: 2/4 packs in a
-- delve that has two.
reloadAddon()
m = Bonus:GetModel()
ok(boxReads(m, "0/2"), "a reload after a flushed scan still reads 0/2, not 2/4: " .. boxText(m))

-- The rager despawn test reads the SAME empty list, and a banner state only ever goes up - so
-- a promotion taken from a loading screen stands for the rest of the run. Same bug as the pack
-- count, one branch over, and it was found while fixing that one.
livesAnswer = nil
m = newRun({ { 9001, "npc-R", "A Voidfused Rager" } })
ok(bannerText(m):find("Voidfused Rager", 1, true) ~= nil,
   "a rager on the list draws the kill-it line: " .. bannerText(m))

VIGNETTES = {}                    -- the loading screen again
m = Bonus:GetModel()
ok(bannerText(m):find("Voidfused Rager", 1, true) ~= nil,
   "a flushed list does not promote the rager to killed: " .. bannerText(m))

VIGNETTES = { { 6127, "npc-X", "Exit" } }   -- a real reading with the rager gone
m = Bonus:GetModel()
ok(bannerText(m):find("Grand Spoils", 1, true) ~= nil,
   "a real reading with the rager gone does promote it: " .. bannerText(m))

livesAnswer = nil
newRun({ pack("npc-B"), pack("npc-C") })
Bonus:Reconcile()
handlers.PLAYER_DEAD()
handlers.PLAYER_DEAD()
-- Both packs killed. A delve still draws its own exit vignette, so the list is not empty -
-- an empty one is a loading screen and is covered above.
VIGNETTES = { { 6127, "npc-X", "Exit" } }
m = Bonus:GetModel()
ok(boxReads(m, "2/2"), "both packs read as killed before the reload: " .. boxText(m))

reloadAddon()
m = Bonus:GetModel()
ok(statText(m):find("Deaths: 2", 1, true) ~= nil, "deaths survive a reload: " .. statText(m))
ok(boxReads(m, "2/2"),
   "the Strongbox line survives a reload with every pack already dead: " .. boxText(m))

-- Leaving clears the record, so the NEXT entry to the same delve starts clean. That clear is
-- what lets the resume be a plain name check.
handlers.PLAYER_ENTERING_WORLD()  -- still inside, nothing to clear
ok(CHAR.delveRun ~= nil, "a world transition inside the delve keeps the saved run")
DIFF = 0
handlers.PLAYER_ENTERING_WORLD()  -- left the delve
DIFF = 208
ok(CHAR.delveRun == nil, "leaving the delve clears the saved run")

reloadAddon()
m = Bonus:GetModel()
ok(statText(m):find("Deaths: 0", 1, true) ~= nil,
   "re-entering after leaving does not resume the old deaths: " .. statText(m))

-- 62-64. A record left behind by a logout INSIDE a delve must not resume onto the next entry
-- hours later. The clear used to sit behind a file-local that is nil at login, so a player who
-- logged back in OUTSIDE the delve never cleared anything - and their old deaths and pack
-- tally landed on the next run.
livesAnswer = nil
newRun({ pack("npc-B") })
Bonus:Reconcile()
handlers.PLAYER_DEAD()
local loggedOutIn = INSTANCE_NAME
ok(CHAR.delveRun ~= nil and CHAR.delveRun.deaths == 1,
   "the run is saved while the player is inside the delve")

reloadAddon()                     -- logged out inside the delve, logged back in outside it
DIFF = 0
INSTANCE_NAME = "Dornogal"
handlers.PLAYER_ENTERING_WORLD()
ok(CHAR.delveRun == nil,
   "logging in outside a delve clears a record this session never tracked")

DIFF = 208
INSTANCE_NAME = loggedOutIn       -- and walking back into the same delve starts clean
VIGNETTES = { pack("npc-B") }
m = Bonus:GetModel()
ok(statText(m):find("Deaths: 0", 1, true) ~= nil,
   "re-entering the same delve does not resume the stale run: " .. statText(m))

-- 65. A crash leaves a record behind, and the age check is the only thing that stops it
-- resuming onto a run days later.
CHAR.delveRun = { name = INSTANCE_NAME, at = 1, deaths = 9, packsKilled = 4 }
reloadAddon()
m = Bonus:GetModel()
ok(statText(m):find("Deaths: 0", 1, true) ~= nil,
   "a stale saved run is refused rather than resumed: " .. statText(m))

-- ---------------------------------------------------------------------------------------
-- The lives reader itself, sliced out of UI/ScenarioBonusHUD.lua by TEXT ANCHOR the way
-- test_row_blocks.lua slices UI/Row.lua - the file cannot be loaded whole without a frame
-- stub, and line numbers rot. If an anchor below stops matching, fix the anchor rather than
-- deleting the test.
--
-- What earns it: the walk used to stop before a "Challenge" or "Wave" label matched as RAW
-- ENGLISH. Blizzard draws that text localized, so on deDE, frFR, ruRU, koKR, zhCN and zhTW the
-- guard never fired, and the reader could hand back a confident wrong integer while testing
-- perfectly on an English client.

local hudSrc = assert(io.open(repoFile("UI/ScenarioBonusHUD.lua"), "r"))
local hudText = hudSrc:read("*a")
hudSrc:close()

local FROM_ANCHOR = "local LIVES_MAX_DEPTH = "
local TO_ANCHOR   = "local function buildRow"
local from = hudText:find(FROM_ANCHOR, 1, true)
local to   = hudText:find(TO_ANCHOR, 1, true)
assert(from, "anchor not found in UI/ScenarioBonusHUD.lua: " .. FROM_ANCHOR)
assert(to,   "anchor not found in UI/ScenarioBonusHUD.lua: " .. TO_ANCHOR)
assert(to > from, "anchors are out of order in UI/ScenarioBonusHUD.lua")

local FAKEG = {}
local chunk = assert(loadstring(
    hudText:sub(from, to - 1) .. "\nreturn { read = readDelveLives }",
    "@UI/ScenarioBonusHUD.lua slice"))
setfenv(chunk, setmetatable({ _G = FAKEG }, { __index = _G }))
local LIVES = chunk()

local function fsRegion(text, shown)
    return {
        GetObjectType = function() return "FontString" end,
        IsShown       = function() return shown ~= false end,
        GetText       = function() return text end,
    }
end

local function fakeFrame(regions, kids)
    return {
        GetRegions  = function() return unpack(regions or {}) end,
        GetChildren = function() return unpack(kids or {}) end,
    }
end

local function tracker(f) FAKEG.ScenarioObjectiveTracker = f end

-- 66-77. The delve header as the reader expects it: the delve name, the tier, then the
-- lives digit.
tracker(fakeFrame({}, {
    fakeFrame({ fsRegion("The Ring of Glory"), fsRegion("7") }),
    fakeFrame({ fsRegion("5") }),
}))
ok(LIVES.read(7) == 5, "the digit after the tier is the lives count")
ok(LIVES.read(nil) == 5, "with no tier to anchor on, two digits and nothing else still reads")

-- THE FIX. The same tracker text must give the same answer whatever language its labels are
-- in. The old stop guard matched raw English, so the English arrangement below refused to read
-- anything at all while every translated client read 5 - locale-dependent behavior, which is
-- how a wrong number gets drawn with nothing on screen to say so.
-- The labels stand in for translated text and their BYTES do not matter, because nothing here
-- reads them - which is the property under test. They are kept ASCII so this file adds no hit
-- to the decimal-escape grep, whose count is read on every release.
local function withLabel(label)
    return fakeFrame({}, {
        fakeFrame({ fsRegion(label), fsRegion("3") }),
        fakeFrame({ fsRegion("The Ring of Glory"), fsRegion("7") }),
        fakeFrame({ fsRegion("5") }),
    })
end
tracker(withLabel("Challenge"))
local enAnswer = LIVES.read(7)
tracker(withLabel("Herausforderung"))
local deAnswer = LIVES.read(7)
tracker(withLabel("Vague"))
local frAnswer = LIVES.read(7)
ok(enAnswer == deAnswer and deAnswer == frAnswer,
   "the answer does not depend on the language a label is drawn in: "
   .. tostring(enAnswer) .. " / " .. tostring(deAnswer) .. " / " .. tostring(frAnswer))
ok(enAnswer == 5, "and it is still the digit after the tier: " .. tostring(enAnswer))

-- Nothing drawn past the answer is read at all, so no label has to be recognized to stop.
tracker(fakeFrame({}, {
    fakeFrame({ fsRegion("7") }),
    fakeFrame({ fsRegion("5") }),
    fakeFrame({ fsRegion("9"), fsRegion("11") }),
}))
ok(LIVES.read(7) == 5, "digits after the answer cannot displace it")

-- Without an anchor, a third digit is what makes this refuse rather than guess.
ok(LIVES.read(nil) == nil, "with no anchor and more than two digits it refuses to answer")

-- Only a BARE digit counts. A criterion counter and a labeled tier are not lives.
tracker(fakeFrame({}, {
    fakeFrame({ fsRegion("Tier 7"), fsRegion("0/1 Defeat the boss") }),
    fakeFrame({ fsRegion("7"), fsRegion("5") }),
}))
ok(LIVES.read(7) == 5, "a slash counter and a labeled tier are not read as digits")

-- Color escapes are stripped, or every colored digit is invisible to this.
tracker(fakeFrame({}, {
    fakeFrame({ fsRegion("|cff00ff007|r"), fsRegion("|cffff00005|r") }),
}))
ok(LIVES.read(7) == 5, "color escapes are stripped before the digit is read")

-- A FontString that throws must not abort the walk and lose the digit after it.
local throwing = {
    GetObjectType = function() return "FontString" end,
    IsShown       = function() return true end,
    GetText       = function() error("attempt to use a secret value", 0) end,
}
tracker(fakeFrame({}, {
    fakeFrame({ throwing, fsRegion("7") }),
    fakeFrame({ fsRegion("5") }),
}))
ok(LIVES.read(7) == 5, "a FontString that throws does not abort the walk")

-- A hidden FontString is not on screen, so it is not a reading.
tracker(fakeFrame({}, {
    fakeFrame({ fsRegion("7"), fsRegion("99", false) }),
    fakeFrame({ fsRegion("5") }),
}))
ok(LIVES.read(7) == 5, "a hidden FontString is skipped")

-- No tracker at all, which is every client that is not in a scenario.
tracker(nil)
FAKEG.ObjectiveTrackerFrame = nil
ok(LIVES.read(7) == nil, "no tracker frame means no answer rather than an error")

-- The depth cap is real: a digit buried deeper than the walk goes is not read.
local deep = fakeFrame({ fsRegion("5") })
for _ = 1, 12 do deep = fakeFrame({}, { deep }) end
tracker(fakeFrame({}, { fakeFrame({ fsRegion("7") }), deep }))
ok(LIVES.read(7) == nil, "a digit past the depth cap is not read")

print(("test_scenario_bonus: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
