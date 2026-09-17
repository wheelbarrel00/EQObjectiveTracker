-- Unit tests for the quest reward XP line on Classic, run against the SHIPPED source rather than
-- a copy. Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_reward_xp.lua
--
-- WHY THIS FILE EXISTS. On Era 1.15.9 GetQuestLogRewardXP ignores its argument and answers for
-- whichever quest log entry is SELECTED. Measured by /eqsprobe xp in Everything Quests on
-- 2026-08-12: quests 87 and 121 both answered 250 with the selection on 121, and the same call
-- answered 525 once it moved to 87. The tooltip passed each row's questID, so every quest showed
-- the selected quest's figure - 650 on every row for days, then 330. A /run on the reporter's Era
-- client confirmed it and showed money and item counts DO honor the argument, which is why only
-- XP moved to the selection path.
--
-- What it loads and reads:
--   * Data/QuestRewards.lua WHOLE. It reads each quest with the selection moved onto it and put
--     back, stores the figure per player level, backs off after a refused read, and the tooltip
--     reads what it stored.
--   * Data/Providers/QuestsClassic.lua, whose two queue helpers are SLICED by text anchor. Its call
--     sites and event wiring are checked by comment-stripped grep, because it cannot load without
--     the game.
--   * UI/Commands.lua and both Classic TOCs, by grep only.
--
-- The world stub reproduces the measured Era shape: the argument is ignored and the selection
-- decides. With honorsArg set it answers by argument instead, which is retail's shape and possibly
-- TBC's - no reading has been taken on 2.5.6 - and the selection path has to read right under both.
--
-- OUT OF SCOPE BY CONSTRUCTION: UI/RewardTooltip.lua's drawing of the line, whether an index past
-- a collapsed header can be selected on a real client, and whether UnitLevel has moved by the time
-- a PLAYER_LEVEL_UP pass runs. No harness can settle the last two.

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
end

local function readFile(rel)
    local fh = assert(io.open(repoFile(rel), "rb"))
    local s = fh:read("*a")
    fh:close()
    return (s:gsub("\r\n", "\n"))
end

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end

-- Helpers answer this rather than nil on a raise, so an assertion written `== nil` or `== false`
-- cannot pass against a crash.
local RAISED = "RAISED"

-- ===================================================================== the world the stubs model

local world

local function newWorld(opts)
    opts = opts or {}
    return {
        -- 1 and 3 are zone headers, as on a real Classic log
        rows  = { [1] = { header = true }, [2] = { id = 87 }, [3] = { header = true },
                  [4] = { id = 121 }, [5] = { id = 200 }, [6] = { id = 300 }, [7] = { id = 400 } },
        -- Per level, so a ding changes what the client answers. 300 pays nothing and 400 answers
        -- something that is not a number. A nil there could not tell the type guard from its
        -- absence, because storing nil stores nothing.
        xp    = { [10] = { [87] = 525, [121] = 250, [200] = 900, [300] = 0, [400] = "junk" },
                  [11] = { [87] = 420, [121] = 200, [200] = 900, [300] = 0, [400] = "junk" } },
        level = 10,
        clock = 1000,
        sel   = opts.sel or 5,
        -- Indices the selection refuses to move onto, and indices whose select raises.
        stuck = opts.stuck or {},
        selectRaises = opts.selectRaises or {},
        -- Which GetQuestLogSelection calls raise, counted from 1 for the whole world.
        selectionRaisesOn = opts.selectionRaisesOn or {},
        selectionCalls = 0,
        raiseXP = opts.raiseXP or false,
        honorsArg = opts.honorsArg or false,
        noSelectionAPI = opts.noSelectionAPI or false,
        noSelectAPI = opts.noSelectAPI or false,
        nilSelection = opts.nilSelection or false,
        noXPAPI = opts.noXPAPI or false,
        selects = 0,
        xpCalls = 0,
    }
end

local function xpFor(id)
    local byLevel = world.xp[world.level]
    return byLevel and byLevel[id]
end

local qrSrc = readFile("Data/QuestRewards.lua")
local registeredAs

local function loadQR(retail)
    local registered
    registeredAs = nil
    local ns = {
        Has = { QuestLog = retail and true or false, TaskQuestInfo = false },
        RegisterModule = function(_, name, t) registeredAs, registered = name, t return t end,
        GetModule = function() return nil end,
    }
    local env = setmetatable({
        wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
        tremove = table.remove,
        C_QuestLog = {},
        GetQuestLogRewardMoney = function() return 0 end,
        GetNumQuestLogRewards  = function() return 0 end,
        GetNumQuestLogChoices  = function() return 0 end,
        GetTime = function() return world.clock end,
        -- Raises on anything but "player", so a wrong unit token cannot pass quietly.
        UnitLevel = function(unit)
            if unit ~= "player" then error("bad unit", 0) end
            return world.level
        end,
    }, { __index = function(_, k)
        if k == "SelectQuestLogEntry" then
            if world.noSelectAPI then return nil end
            return function(index)
                if type(index) ~= "number" then error("bad quest log index", 0) end
                world.selects = world.selects + 1
                if world.selectRaises[index] then error("SelectQuestLogEntry raised", 0) end
                if not world.stuck[index] then world.sel = index end
            end
        elseif k == "GetQuestLogSelection" then
            if world.noSelectionAPI then return nil end
            return function()
                world.selectionCalls = world.selectionCalls + 1
                if world.selectionRaisesOn[world.selectionCalls] then
                    error("GetQuestLogSelection raised", 0)
                end
                if world.nilSelection then return nil end
                return world.sel
            end
        elseif k == "GetQuestLogRewardXP" then
            if world.noXPAPI then return nil end
            return function(questID)
                world.xpCalls = world.xpCalls + 1
                if world.raiseXP then error("GetQuestLogRewardXP raised", 0) end
                if world.honorsArg then
                    if questID == nil then return 0 end
                    return xpFor(questID)
                end
                local row = world.rows[world.sel]
                if not row or row.header then return 0 end
                return xpFor(row.id)
            end
        end
        return _G[k]
    end })

    local chunk = assert(loadstring(qrSrc, "QuestRewards.lua"))
    setfenv(chunk, env)
    local okLoad, err = pcall(chunk, "EQObjectiveTracker", ns)
    ok(okLoad, "Data/QuestRewards.lua loads: " .. tostring(err))
    ok(type(registered) == "table", "and registers its module")
    return registered or {}
end

local function xpShown(QR, id)
    local okCall, lines = pcall(QR.Lines, QR, id)
    ok(okCall, "Lines did not raise for " .. tostring(id))
    if not okCall or type(lines) ~= "table" then return RAISED end
    for i = 1, #lines do
        if lines[i].kind == "xp" then return lines[i].amount end
    end
    return nil
end

local function needs(QR, id)
    local okCall, res = pcall(QR.NeedsXP, QR, id)
    ok(okCall, "NeedsXP did not raise for " .. tostring(id))
    if not okCall then return RAISED end
    return res
end

local function collect(QR, indices, ids, n)
    local okCall, err = pcall(QR.CollectXP, QR, indices, ids, n)
    ok(okCall, "CollectXP did not raise: " .. tostring(err))
end

local function debugLine(QR)
    local okCall, res = pcall(QR.DebugLine, QR)
    ok(okCall, "DebugLine did not raise: " .. tostring(res))
    if not okCall then return RAISED end
    return res
end

local function has(s, needle)
    return type(s) == "string" and s:find(needle, 1, true) ~= nil
end

-- ===================================================================== Era: the reported bug

world = newWorld({ sel = 4 })
local QR = loadQR(false)
ok(registeredAs == "QuestRewards", "the module registers under the name the provider looks up")
local dl = debugLine(QR)
ok(has(dl, "| 0 figures held at level nil, player 10, 0 refusals held |"),
   "before any read, status says no level has been read yet: " .. tostring(dl))

-- The selection sits on 121, which pays 250. That figure must not reach any other quest's tooltip.
ok(xpShown(QR, 87) == nil, "before any read, quest 87 shows no XP rather than the selected quest's 250")
ok(xpShown(QR, 121) == nil, "and the selected quest shows nothing either, since the hover never asks")
ok(world.selects == 0, "a hover never moves the quest log selection")
ok(world.xpCalls == 0, "and never asks the selection-driven API at all")
ok(needs(QR, 87) == true and needs(QR, 121) == true, "both quests need a read")

-- ===================================================================== Era: the sweep

world.sel = 5
collect(QR, { 2, 4 }, { 87, 121 }, 2)
ok(xpShown(QR, 87) == 525, "quest 87 shows its own 525")
ok(xpShown(QR, 121) == 250, "quest 121 shows its own 250")
ok(world.sel == 5, "the selection is put back where the player left it, not on the last quest read")
ok(world.selects == 3, "two reads and one restore move the selection, and nothing else does")
ok(needs(QR, 87) == false and needs(QR, 121) == false, "neither quest needs a read once stored")
dl = debugLine(QR)
ok(type(dl) == "string" and dl:find("^reward xp: read by selection | ") ~= nil,
   "the status line names itself: " .. tostring(dl))
ok(has(dl, "| 2 figures held at level 10, player 10, 0 refusals held |"),
   "status names what is stored and at which level: " .. tostring(dl))
ok(has(dl, "| 1 sweep(s), 2 read, 0 refused, 0 not restored") and dl:sub(-14) == "0 not restored",
   "and counts the sweep and both reads: " .. tostring(dl))

-- A quest log that has not changed costs nothing, even if a caller hands the same pairs again.
world.selects, world.xpCalls = 0, 0
collect(QR, { 2, 4 }, { 87, 121 }, 2)
ok(world.selects == 0, "a second sweep over stored quests moves the selection zero times")
ok(world.xpCalls == 0, "and asks the API nothing")
ok(xpShown(QR, 87) == 525, "and the stored figure still shows")

-- A newly accepted quest costs exactly one read. The selection is modeled starting on a HEADER so
-- the restore is not satisfied by the last read landing where it began.
world.sel, world.selects = 1, 0
collect(QR, { 2, 4, 5 }, { 87, 121, 200 }, 3)
ok(world.selects == 2, "only the new quest is read, plus the restore")
ok(xpShown(QR, 200) == 900, "and it shows its own 900")
ok(world.sel == 1, "the selection is put back onto the header it started on")

-- The provider reuses its arrays, so slots past n belong to an older pass and an older quest log.
world.sel, world.selects = 5, 0
collect(QR, { 6, 7 }, { 300, 400 }, 1)
ok(world.selects == 2, "only the first n pairs are read, never a stale pair past n")
ok(needs(QR, 400) == true, "so the quest in the stale slot was never asked about")

-- ===================================================================== Era: a ding

world.level = 11
ok(xpShown(QR, 87) == nil, "after a ding a stored figure from the old level is not shown")
ok(needs(QR, 87) == true, "and a quest already stored needs a read again")
dl = debugLine(QR)
ok(has(dl, "| 4 figures held at level 10, player 11, 0 refusals held |"),
   "status tells the stored level from the player's before the re-read: " .. tostring(dl))

-- A sweep that cannot start must leave the old store and the counters alone.
world.nilSelection = true
collect(QR, { 2, 4, 5 }, { 87, 121, 200 }, 3)
world.nilSelection = false
dl = debugLine(QR)
ok(has(dl, "| 4 figures held at level 10, player 11, 0 refusals held | 4 sweep(s),"),
   "a sweep refused before it starts neither wipes the store nor counts: " .. tostring(dl))

world.sel, world.selects = 5, 0
collect(QR, { 2, 4, 5 }, { 87, 121, 200 }, 3)
ok(xpShown(QR, 87) == 420, "quest 87 shows its new 420")
ok(xpShown(QR, 121) == 200, "quest 121 shows its new 200")
ok(xpShown(QR, 200) == 900, "quest 200 is read again too and still shows 900")
ok(world.selects == 4, "all three are read at the new level, plus the restore")
dl = debugLine(QR)
ok(has(dl, "| 3 figures held at level 11, player 11, 0 refusals held |"), "status follows the new level: " .. tostring(dl))

-- ===================================================================== Era: refusals and the wait

-- The selection will not move onto index 4, so whatever the API answers there belongs to index 2.
world = newWorld({ sel = 5, stuck = { [4] = true } })
QR = loadQR(false)
collect(QR, { 2, 4 }, { 87, 121 }, 2)
ok(xpShown(QR, 87) == 525, "a quest the selection reached is stored")
ok(xpShown(QR, 121) == nil, "a quest the selection did not reach stores nothing rather than 87's figure")
ok(world.sel == 5, "and the selection is still put back")
dl = debugLine(QR)
ok(has(dl, "| 1 figures held at level 10, player 10, 1 refusals held |"), "status counts the quest waiting: " .. tostring(dl))
ok(has(dl, "| 1 sweep(s), 1 read, 1 refused, 0 not restored"), "and the refusal: " .. tostring(dl))

-- Without the wait, a refused quest moved the selection again on every quest log update.
ok(needs(QR, 121) == false, "a refused quest is not queued again straight away")
world.selects = 0
collect(QR, { 4 }, { 121 }, 1)
ok(world.selects == 0, "and a caller handing it over anyway does not move the selection")
-- Half seconds, because GetTime is fractional and a whole-second step cannot see a boundary moved
-- by less than one.
world.clock = world.clock + 29.5
ok(needs(QR, 121) == false, "it is still waiting 29.5 seconds later")
collect(QR, { 4 }, { 121 }, 1)
ok(world.selects == 0, "and the sweep holds it back too")
world.clock = world.clock + 0.5
ok(needs(QR, 121) == true, "and is asked about again at 30 seconds")
dl = debugLine(QR)
ok(has(dl, "| 1 figures held at level 10, player 10, 1 refusals held |"),
   "a refusal whose wait is over is still held until the quest is read: " .. tostring(dl))
world.stuck = {}
collect(QR, { 4 }, { 121 }, 1)
ok(xpShown(QR, 121) == 250, "a retry that reaches the quest stores its own figure")
dl = debugLine(QR)
ok(has(dl, "| 2 figures held at level 10, player 10, 0 refusals held |"),
   "and it stops waiting once read: " .. tostring(dl))

-- A ding clears the wait, since every figure is re-read at the new level anyway.
world = newWorld({ sel = 5, stuck = { [4] = true } })
QR = loadQR(false)
collect(QR, { 4 }, { 121 }, 1)
world.stuck, world.level = {}, 11
ok(needs(QR, 121) == true, "after a ding a refused quest is queued without waiting out the retry")
collect(QR, { 4 }, { 121 }, 1)
ok(xpShown(QR, 121) == 200, "and is read at once at the new level")

world = newWorld({ sel = 5, raiseXP = true })
QR = loadQR(false)
collect(QR, { 2, 4 }, { 87, 121 }, 2)
ok(world.sel == 5, "an API that raises still leaves the selection where the player put it")
ok(xpShown(QR, 87) == nil and needs(QR, 87) == false, "and stores nothing, and waits before asking again")

-- Stored, a non-number would never be asked about again, and the tooltip's `xp > 0` would raise.
world = newWorld({ sel = 5 })
QR = loadQR(false)
collect(QR, { 7 }, { 400 }, 1)
ok(xpShown(QR, 400) == nil, "an answer that is not a number is not stored, and the tooltip still draws")
world.clock = world.clock + 30
ok(needs(QR, 400) == true, "and is asked about again once the wait is over")

world = newWorld({ sel = 5 })
QR = loadQR(false)
collect(QR, { 6 }, { 300 }, 1)
ok(needs(QR, 300) == false, "a quest that pays 0 is stored, so it is not read on every pass")
ok(xpShown(QR, 300) == nil, "and draws no XP line")
dl = debugLine(QR)
ok(has(dl, ", 0 refusals held |"), "and is not counted as waiting: " .. tostring(dl))

-- A select that raises, in the loop and then on the restore.
world = newWorld({ sel = 5, selectRaises = { [4] = true } })
QR = loadQR(false)
collect(QR, { 2, 4 }, { 87, 121 }, 2)
ok(xpShown(QR, 87) == 525 and xpShown(QR, 121) == nil, "a select that raises refuses that quest alone")
ok(world.sel == 5, "and the selection is still put back")

world = newWorld({ sel = 5, selectRaises = { [5] = true } })
QR = loadQR(false)
collect(QR, { 2, 4 }, { 87, 121 }, 2)
dl = debugLine(QR)
ok(has(dl, " 2 read, 0 refused, 1 not restored"), "a restore that raises is counted as not restored: " .. tostring(dl))

-- A selection read that raises: call 1 is the save, call 2 confirms quest 87, call 4 re-reads the
-- restore after two quests.
world = newWorld({ sel = 5, selectionRaisesOn = { [2] = true } })
QR = loadQR(false)
collect(QR, { 2, 4 }, { 87, 121 }, 2)
ok(xpShown(QR, 87) == nil and xpShown(QR, 121) == 250, "a confirm that raises refuses that quest alone")
ok(world.sel == 5, "and the selection is still put back")

world = newWorld({ sel = 5, selectionRaisesOn = { [4] = true } })
QR = loadQR(false)
collect(QR, { 2, 4 }, { 87, 121 }, 2)
dl = debugLine(QR)
ok(has(dl, " 2 read, 0 refused, 1 not restored"), "a restore check that raises is counted as not restored: " .. tostring(dl))

world = newWorld({ sel = 5, noSelectionAPI = true })
QR = loadQR(false)
collect(QR, { 2, 4 }, { 87, 121 }, 2)
ok(world.selects == 0, "with no way to read the selection back, it is never moved")

world = newWorld({ sel = 5, nilSelection = true })
QR = loadQR(false)
collect(QR, { 2, 4 }, { 87, 121 }, 2)
ok(world.selects == 0, "with a selection that is not a number, it is never moved")
dl = debugLine(QR)
ok(has(dl, "| 0 sweep(s),"), "and no sweep is counted: " .. tostring(dl))

world = newWorld({ sel = 5, selectionRaisesOn = { [1] = true } })
QR = loadQR(false)
collect(QR, { 2, 4 }, { 87, 121 }, 2)
ok(world.selects == 0, "with a selection read that raises, it is never moved")

-- Modeled as the client answering 0 with nothing selected. That is a number, so the sweep runs.
-- Whether a real client accepts SelectQuestLogEntry(0) is unmeasured, and a refusal there would show
-- in status as not restored.
world = newWorld({ sel = 0 })
QR = loadQR(false)
collect(QR, { 2, 4 }, { 87, 121 }, 2)
ok(xpShown(QR, 87) == 525 and xpShown(QR, 121) == 250, "with nothing selected the quests are still read")
ok(world.sel == 0, "and nothing is selected afterwards")

world = newWorld({ sel = 5, noXPAPI = true })
QR = loadQR(false)
collect(QR, { 2, 4 }, { 87, 121 }, 2)
ok(world.selects == 0, "with no XP API there is nothing to read, so the selection is never moved")

world = newWorld({ sel = 5, noSelectAPI = true })
QR = loadQR(false)
collect(QR, { 2, 4 }, { 87, 121 }, 2)
dl = debugLine(QR)
ok(has(dl, "| 0 sweep(s),") and needs(QR, 87) == true,
   "with no select API there is no sweep and no refusal to wait out: " .. tostring(dl))

world = newWorld({ sel = 5 })
QR = loadQR(false)
collect(QR, {}, {}, 0)
ok(world.selects == 0, "an empty batch moves nothing")
dl = debugLine(QR)
ok(has(dl, "| 0 sweep(s),"), "and is not counted as a sweep: " .. tostring(dl))

-- The restore itself is refused, which is the one failure a player would see in their own log.
world = newWorld({ sel = 5, stuck = { [5] = true } })
QR = loadQR(false)
collect(QR, { 2, 4 }, { 87, 121 }, 2)
dl = debugLine(QR)
ok(has(dl, " 2 read, 0 refused, 1 not restored"), "status counts a restore that did not take: " .. tostring(dl))

-- Modeled so that no argument answers 0, which makes a read that drops the questID visible.
world = newWorld({ sel = 5, honorsArg = true })
QR = loadQR(false)
collect(QR, { 2, 4 }, { 87, 121 }, 2)
ok(xpShown(QR, 87) == 525 and xpShown(QR, 121) == 250,
   "the selection path reads right on a client that honors the argument")

-- ===================================================================== retail

world = newWorld({ sel = 5, honorsArg = true })
QR = loadQR(true)
ok(xpShown(QR, 87) == 525, "retail reads quest 87 by its argument")
ok(xpShown(QR, 121) == 250, "retail reads quest 121 by its argument")
ok(needs(QR, 87) == false, "retail never asks for a read")
collect(QR, { 2, 4 }, { 87, 121 }, 2)
ok(world.selects == 0, "retail never moves the quest log selection")
ok(debugLine(QR) == nil, "retail prints no status line")

-- ===================================================================== the provider's helpers

local provSrc = readFile("Data/Providers/QuestsClassic.lua")

local function slice(src, fromAnchor, toAnchor, label)
    local from = src:find(fromAnchor, 1, true)
    local to   = from and src:find(toAnchor, from, true)
    assert(from, "anchor not found in " .. label .. ": " .. fromAnchor)
    assert(to,   "anchor not found in " .. label .. ": " .. toAnchor)
    return src:sub(from, to - 1)
end

local helperSrc = slice(provSrc, "local xpIndex, xpQuest, xpCount = {}, {}, 0",
                        "-- isComplete arrives nil while in progress", "QuestsClassic.lua")

local needsSet, handed
local penv = setmetatable({
    QuestRewards = {
        NeedsXP = function(_, id)
            if type(id) ~= "number" then error("bad quest id", 0) end
            return needsSet[id] == true
        end,
        -- Copied at the call, because the arrays are reused and a later pass rewrites them.
        CollectXP = function(_, indices, ids, n)
            local c = { n = n, indices = {}, ids = {} }
            for k = 1, n do c.indices[k], c.ids[k] = indices[k], ids[k] end
            handed[#handed + 1] = c
        end,
    },
}, { __index = _G })

local wantXP, collectXP, countOf, enterWorld
local hchunk, loadErr = loadstring(helperSrc .. "\nreturn wantXP, collectXP, "
    .. "function() return xpCount end, function() xpWorldEntered = true end", "reward-xp-helpers")
ok(hchunk ~= nil, "the helper slice compiles: " .. tostring(loadErr))
if hchunk then
    setfenv(hchunk, penv)
    local okRun, a, b, c, d = pcall(hchunk)
    ok(okRun, "the helper slice runs: " .. tostring(a))
    if okRun then wantXP, collectXP, countOf, enterWorld = a, b, c, d end
end
ok(type(wantXP) == "function" and type(collectXP) == "function", "the slice defines both helpers")

local function want(id, index)
    local okCall, err = pcall(wantXP, id, index)
    ok(okCall, "wantXP did not raise: " .. tostring(err))
end

local function collectP(ready)
    local okCall, err = pcall(collectXP, ready)
    ok(okCall, "collectXP did not raise: " .. tostring(err))
end

local function queued()
    local okCall, n = pcall(countOf)
    if not okCall then return RAISED end
    return n
end

-- Before PLAYER_ENTERING_WORLD the quest cache has no opinion and answers ready, so readiness
-- alone would let the login render read.
needsSet, handed = { [87] = true }, {}
want(87, 2)
collectP(true)
ok(#handed == 0, "a ready pass before the world is entered hands nothing over")
ok(queued() == 0, "and still empties its batch")
pcall(enterWorld)

needsSet, handed = { [87] = true, [121] = true }, {}
want(87, 2)
want(121, 4)
collectP(true)
ok(#handed == 1, "a ready pass hands its batch over once")
ok(handed[1] and handed[1].n == 2 and handed[1].indices[1] == 2 and handed[1].ids[1] == 87
   and handed[1].indices[2] == 4 and handed[1].ids[2] == 121,
   "with each index beside its own questID")
ok(queued() == 0, "and the batch is emptied after")

needsSet, handed = { [87] = true, [121] = true }, {}
want(87, 2)
collectP(false)
ok(#handed == 0, "a pass before the quest cache is ready hands nothing over")
ok(queued() == 0, "and still empties its batch")
want(121, 4)
collectP(true)
ok(#handed == 1 and handed[1].n == 1 and handed[1].ids[1] == 121,
   "so the next ready pass does not resend a pair from a quest log that may have changed")

needsSet, handed = { [87] = true }, {}
want(87, nil)
collectP(true)
ok(#handed == 0, "a quest with no log index is not queued")

needsSet, handed = {}, {}
want(87, 2)
collectP(true)
ok(#handed == 0, "a quest that already has its figure is not queued")

-- ===================================================================== wiring, by grep

-- Comments are stripped first, or a commented-out call satisfies the assertion that it exists.
local function strip(s)
    s = s:gsub("%-%-%[(=*)%[.-%]%1%]", "")
    s = s:gsub("%-%-[^\n]*", "")
    s = s:gsub("[ \t]+\n", "\n")
    return s
end

local proof = strip("a\n-- wantXP(id, i)\n--[[\nwantXP(id, i)\n]]\nx = 1 -- wantXP(id, i)\nb")
ok(not proof:find("wantXP", 1, true), "the stripper removes line, trailing and multi-line block comments")
ok(strip("    collectXP(cacheReady) -- a note\n"):find("^    collectXP%(cacheReady%)\n$") ~= nil,
   "and code followed by a trailing comment still matches a pattern that ends at the line")

local function count(s, pattern)
    return select(2, s:gsub(pattern, ""))
end

local prov = strip(provSrc)

ok(count(prov, "local QuestRewards = ns:GetModule%(\"QuestRewards\"%)\n") == 1,
   "the provider resolves the QuestRewards module")
ok(count(prov, "wantXP%(id, i%)") == 2, "both passes queue quests")
-- Five writes: the declaration, the increment, and a reset at the top of each pass and in
-- collectXP. A stray reset between a queue and its hand-over switches the read off with every other
-- check green, however it is spelled.
ok(count(prov, "xpCount%s*=[^=]") == 5, "the batch count is written in exactly five places")
ok(count(prov, "xpWorldEntered%s*=[^=]") == 2,
   "the world-entered gate is written only where it is declared and where it opens")

local fullAt    = prov:find("local function fullRebuild()", 1, true)
local beginAt   = fullAt and prov:find("store:Begin()", fullAt, true)
local finishAt  = fullAt and prov:find("store:Finish()", fullAt, true)
local dynAt     = prov:find("local function refreshDynamic()", 1, true)
local dynLoopAt = dynAt and prov:find("for id, e in store:Each() do", dynAt, true)
local dynEndAt  = dynAt and prov:find("lastDynAt = time()", dynAt, true)
ok(fullAt and beginAt and finishAt and dynAt and dynLoopAt and dynEndAt, "both passes are found")

if fullAt and beginAt and finishAt and dynAt and dynLoopAt and dynEndAt then
    local fullHead = prov:sub(fullAt, beginAt)
    local fullWalk = prov:sub(beginAt, finishAt)
    local dynHead  = prov:sub(dynAt, dynLoopAt)
    local dynBody  = prov:sub(dynLoopAt, dynEndAt)
    ok(count(fullHead, "\n%s*xpCount = 0\n") == 1, "fullRebuild empties the batch before its walk")
    ok(count(dynHead, "\n%s*xpCount = 0\n") == 1, "refreshDynamic empties the batch before its loop")
    ok(count(fullWalk, "wantXP%(id, i%)") == 1, "fullRebuild's walk queues quests")
    ok(count(dynBody, "wantXP%(id, i%)") == 1, "refreshDynamic's loop queues quests")
    ok(count(dynBody, "\n    collectXP%(QuestCache:IsReady%(%)%)\n") == 1,
       "refreshDynamic hands its batch over after the loop, gated on the quest cache")
end

ok(count(prov, "local cacheReady = QuestCache:Finish%(%)\n%s*collectXP%(cacheReady%)\n") == 1,
   "fullRebuild hands its batch over right after the quest cache judges the walk")
ok(count(prov, "collectXP%(") == 3, "collectXP has its definition and exactly two callers")

ok(count(prov, "local function enterWorld%(%)\n%s*xpWorldEntered = true\n%s*markAll%(%)\n%s*end\n") == 1,
   "entering the world opens the read and still marks everything dirty")
ok(count(prov, "xpWorldEntered = true") == 1, "and nothing else opens it")
ok(count(prov, "Events:On%(\"PLAYER_ENTERING_WORLD\",%s+enterWorld%)\n") == 1,
   "PLAYER_ENTERING_WORLD is what calls it")
ok(count(prov, "Events:On%(\"PLAYER_LEVEL_UP\",%s+markDynamic%)\n") == 1,
   "a ding triggers a pass, which re-reads every figure")
ok(count(prov, "local function playerLevelChanged%(_, unit%)\n%s*if unit == \"player\" then markDynamic%(%) end\n%s*end\n") == 1,
   "a level change triggers a pass only for the player")
ok(count(prov, "Events:On%(\"UNIT_LEVEL\",%s+playerLevelChanged%)\n") == 1,
   "and UNIT_LEVEL is what calls it")

local commands = strip(readFile("UI/Commands.lua"))
ok(count(commands, "\n%s*debugLine%(\"QuestRewards\"%)\n") == 1, "/eqot status prints the reward XP line")

-- The provider resolves QuestRewards at load, so the module must load first on both flavors.
for _, toc in ipairs({ "EQObjectiveTracker_Vanilla.toc", "EQObjectiveTracker_TBC.toc" }) do
    local t = "\n" .. readFile(toc):gsub("\n#[^\n]*", "\n")
    local rewardsAt  = t:find("\nData\\QuestRewards.lua\n", 1, true)
    local providerAt = t:find("\nData\\Providers\\QuestsClassic.lua\n", 1, true)
    ok(rewardsAt and providerAt and rewardsAt < providerAt,
       toc .. " loads Data/QuestRewards.lua before the Classic provider")
end

print(("test_reward_xp: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
