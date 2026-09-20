-- Unit tests for handing a finished auto-complete quest in from its row, run against the SHIPPED
-- source rather than a copy. Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_quest_turnin.lua
--
-- WHY THIS FILE EXISTS. A CurseForge report against 1.24.2: a finished Prey hunt for Astalor
-- Bloodsworn could not be handed in with the tracker installed, and the player had to remove the
-- addon to end it. An auto-complete quest is handed in from the objective tracker, never from an
-- NPC, and in Blizzard's own UI only two places call ShowQuestComplete: the Complete popup box and
-- a click on the quest in Blizzard's tracker. The quest log has no button for it. EQOT hides
-- Blizzard's tracker and drew the popup box only, so a quest that raised no popup had no way in.
--
-- WHAT IS HELD HERE. A left click on a finished auto-complete row hands it in, and so does the
-- title half of a split click, which is Blizzard's header click. The icon half super-tracks and
-- nothing more, as Blizzard's POI button does, and a right click never hands in. A press released
-- off the row is a cancel and does nothing, since this click can now open the reward window. The
-- menu's Open item still only opens the log, as Blizzard's does. The row says it can be clicked,
-- in Blizzard's own translated string, as an ordinary unfinished objective line so simplify mode
-- and the completed-line filters keep it.
--
-- OUT OF SCOPE BY CONSTRUCTION, so a green run says nothing about any of it: how UI/Row.lua draws
-- the line (docs/test_row_blocks.lua covers line kinds), whether the reward window really opens,
-- whether a Prey hunt raises QUEST_AUTOCOMPLETE at all (unmeasured), and the Classic provider,
-- which is untouched.
--
-- The provider cannot be loaded whole without stubbing the whole quest log, so the functions are
-- sliced out by TEXT ANCHORS rather than line numbers. If an anchor stops matching it fails
-- loudly naming the anchor: fix the anchor here rather than deleting the test.

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

-- Counts rather than taking the first hit, so a duplicated anchor cannot hand back region one.
local function slicer(rel)
    local src = readFile(rel)
    return function(fromAnchor, toAnchor)
        local function only(anchor)
            local at, n, from = nil, 0, 1
            while true do
                local i = src:find(anchor, from, true)
                if not i then break end
                at, n, from = at or i, n + 1, i + 1
            end
            assert(n == 1, ("anchor matched %d times in %s (need exactly 1): %s")
                           :format(n, rel, anchor))
            return at
        end
        local from, to = only(fromAnchor), only(toAnchor)
        assert(to > from, "anchors are out of order in " .. rel .. ": " .. fromAnchor)
        return src:sub(from, to - 1)
    end
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

-- ------------------------------------------------------------------------ the sliced source

local sliceQ = slicer("Data/Providers/Quests.lua")
local src = sliceQ("local function questState(id)", "-- A world quest can sit in the quest log")
         .. sliceQ("-- Blizzard's tracker hands an auto-complete quest in", "local function isFocused(id)")
         .. sliceQ("function Quests:OnEntryMenuSelect(entryID, itemID)",
                   "function Quests:OnEntryGroupFinder")
         .. "\nreturn { fillLines = fillLines, questState = questState }"

-- The real Data/Entry.lua, because the line pool IS the behavior: PushLine's reset list and
-- EndLines' trim decide what a reused entry still shows.
local Entry
do
    local chunk = assert(loadstring(readFile("Data/Entry.lua"), "Data/Entry.lua"))
    chunk(nil, { RegisterModule = function(_, _, t) Entry = t return t end })
    assert(Entry and Entry.PushLine, "Data/Entry.lua did not register its module")
end
local STATE, LINE = Entry.STATE, Entry.LINE

-- ------------------------------------------------------------------------------ the world

-- Deliberately NOT the English text, or a line hard-coding "(click to complete)" would pass
-- while shipping English to every translated client.
local STR = "<the client's own click-to-complete string>"

-- id -> { index, complete, failed, auto, noInfo, objs, fallback }
local world
local calls

local function note(what) calls[#calls + 1] = what end

-- The client's quest APIs RAISE on a nil id, so these do too. A forgiving stub lets a real
-- guard be deleted with every assertion green.
local function need(v, fn)
    if v == nil then error(fn .. ": bad argument #1 (nil)", 2) end
end

local function showStub(id) need(id, "ShowQuestComplete") note("show:" .. tostring(id)) end
local function removeStub(id) need(id, "RemoveAutoQuestPopUp") note("remove:" .. tostring(id)) end

local ns = {
    Has = { QuestIsFailed = true, QuestIsComplete = true, QuestObjectives = true,
            QuestWatchAPI = true, SuperTrack = true },
    GetModule = function(_, name) error("unexpected module: " .. tostring(name), 0) end,
}

local Quests = { id = "quests", _notifyDirty = function() note("notify") end }

local C_QuestLog = {
    IsFailed   = function(id) need(id, "IsFailed")   return world[id] and world[id].failed or false end,
    IsComplete = function(id) need(id, "IsComplete") return world[id] and world[id].complete or false end,
    GetQuestObjectives = function(id)
        need(id, "GetQuestObjectives")
        return world[id] and world[id].objs or {}
    end,
    GetLogIndexForQuestID = function(id)
        need(id, "GetLogIndexForQuestID")
        return world[id] and world[id].index or nil
    end,
    GetInfo = function(index)
        need(index, "GetInfo")
        for id, q in pairs(world) do
            if q.index == index then
                if q.noInfo then return nil end
                return { questID = id, title = "Quest " .. id, isAutoComplete = q.auto }
            end
        end
        return nil
    end,
    RemoveQuestWatch = function(id) need(id, "RemoveQuestWatch") note("rmwatch:" .. tostring(id)) end,
}

local env = setmetatable({
    ns = ns, Quests = Quests, Entry = Entry, STATE = STATE, LINE = LINE,
    C_QuestLog = C_QuestLog,
    QuestCache = { Note = function() end },
    getFallbackText = function(id) return world[id] and world[id].fallback or "" end,
    C_SuperTrack = {
        SetSuperTrackedQuestID = function(id) note("supertrack:" .. tostring(id)) end,
    },
    C_AddOns = { LoadAddOn = function(name) note("load:" .. tostring(name)) end },
    QuestMapFrame_OpenToQuestDetails = function(id) note("openlog:" .. tostring(id)) end,
    ToggleQuestLog = function() note("togglelog") end,
}, { __index = _G })

local api
do
    local chunk = assert(loadstring(src, "quest-turnin-slices"))
    setfenv(chunk, env)
    api = chunk()
end

local GET_INDEX = C_QuestLog.GetLogIndexForQuestID

local function reset()
    world, calls = {}, {}
    env.ShowQuestComplete = showStub
    env.RemoveAutoQuestPopUp = removeStub
    env.QUEST_WATCH_CLICK_TO_COMPLETE = STR
    C_QuestLog.GetLogIndexForQuestID = GET_INDEX
end

local function obj(text)
    return { text = text, finished = true, numFulfilled = 1, numRequired = 1, type = "monster" }
end

-- The log index is never the quest id, or GetInfo(id) would read the right quest by accident.
local function quest(id, t)
    t.index = t.index or (id + 1000)
    t.objs = t.objs or { obj("Prey slain"), obj("Anguish gathered") }
    world[id] = t
end

-- ------------------------------------------------------------------------------- helpers

-- The entry is built the way fullRebuild builds it: state from questState, then fillLines.
local function fill(e, id)
    e = e or { id = id, lines = {} }
    local okCall, err = pcall(function()
        e.state = api.questState(id)
        api.fillLines(e, id)
    end)
    ok(okCall, "fillLines does not raise for quest " .. id .. (okCall and "" or (" - " .. tostring(err))))
    return e
end

local function clickLines(e)
    local n = 0
    for i = 1, #e.lines do
        if e.lines[i].text == STR then n = n + 1 end
    end
    return n
end

local function call(fn, why, ...)
    calls = {}
    local okCall, err = pcall(fn, ...)
    ok(okCall, why .. " does not raise" .. (okCall and "" or (" - " .. tostring(err))))
    return table.concat(calls, " ")
end

local function click(id, button, splitIcon)
    return call(Quests.OnEntryClick, "OnEntryClick", Quests, { id = id },
                button or "LeftButton", splitIcon)
end

local function openLog(id)
    return call(Quests.OnEntryOpenLog, "OnEntryOpenLog", Quests, { id = id })
end

local function menu(id, item)
    return call(Quests.OnEntryMenuSelect, "OnEntryMenuSelect", Quests, id, item)
end

-- --------------------------------------------------------------------------------- cases

print("== the row says it can be clicked, only when it can")
do
    reset()
    quest(10, { complete = true, auto = true })
    local e = fill(nil, 10)
    ok(#e.lines == 3, "a finished auto-complete quest keeps both objectives and gains one line: "
       .. #e.lines)
    local last = e.lines[#e.lines] or {}
    ok(last.text == STR, "the last line is Blizzard's own string: " .. tostring(last.text))
    ok(e.lines[1].text == "Prey slain" and e.lines[2].text == "Anguish gathered",
       "and it sits below the objectives rather than in front of them")
    -- An unfinished OBJECTIVE, because simplify mode and the per-section completed filter drop a
    -- completed line, and a NOTE draws dimmed, where Blizzard draws this as an ordinary line.
    ok(last.completed == false, "it is not a completed line, which the filters would hide")
    ok(last.kind == LINE.OBJECTIVE, "it is an ordinary objective line: " .. tostring(last.kind))
    ok(last.richText == false and last.current == nil and last.required == nil
       and last.percent == nil, "with no meter and no pre-colored text")

    reset()
    quest(11, { complete = true, auto = false })
    local plain = fill(nil, 11)
    ok(#plain.lines == 2 and clickLines(plain) == 0,
       "a finished quest handed in to an NPC gains nothing: " .. #plain.lines)

    -- The flag ABSENT rather than false. Every other fixture sets it either way, which cannot
    -- tell `info.isAutoComplete` from `info.isAutoComplete ~= false` - and that second spelling
    -- gives the line, and the hand-in click, to every finished quest in the log.
    reset()
    quest(13, { complete = true, auto = nil })
    local unset = fill(nil, 13)
    ok(#unset.lines == 2 and clickLines(unset) == 0,
       "a finished quest whose info carries no isAutoComplete gains nothing: " .. #unset.lines)

    reset()
    quest(12, { complete = false, auto = true })
    local active = fill(nil, 12)
    ok(#active.lines == 2 and clickLines(active) == 0,
       "an unfinished auto-complete quest gains nothing: " .. #active.lines)

    -- Failed AND complete, the one state where the two answers disagree. A failed case built
    -- with complete = false could not tell the state test from IsComplete.
    reset()
    quest(13, { complete = true, failed = true, auto = true })
    local failed = fill(nil, 13)
    ok(failed.state == STATE.FAILED, "the fixture really is failed: " .. tostring(failed.state))
    ok(clickLines(failed) == 0, "and a failed auto-complete quest gains nothing")
end

print("== the answer is read for the quest being filled, not another")
do
    reset()
    quest(20, { complete = true, auto = true })
    quest(21, { complete = true, auto = false })
    local a, b = fill(nil, 20), fill(nil, 21)
    ok(clickLines(a) == 1 and clickLines(b) == 0,
       "two finished quests side by side each get their own answer")
end

print("== a pooled entry drops the line when the quest stops qualifying")
do
    reset()
    quest(30, { complete = true, auto = true })
    local e = fill(nil, 30)
    ok(clickLines(e) == 1, "the line is there first")
    world[30].complete = false
    fill(e, 30)
    ok(#e.lines == 2 and clickLines(e) == 0,
       "and gone on the next fill of the same entry: " .. #e.lines)
end

print("== a quest with no objectives still says it can be clicked")
do
    reset()
    quest(40, { complete = true, auto = true, objs = {}, fallback = "Kill your prey." })
    local e = fill(nil, 40)
    ok(#e.lines == 2 and e.lines[1].text == "Kill your prey." and e.lines[2].text == STR,
       "the fallback text, then the click line: " .. #e.lines)
end

print("== what the client cannot answer costs the line, never a Lua error")
do
    reset()
    quest(50, { complete = true, auto = true })
    env.QUEST_WATCH_CLICK_TO_COMPLETE = nil
    local e = fill(nil, 50)
    ok(#e.lines == 2, "no global string, no line, rather than a line with no text: " .. #e.lines)

    reset()
    quest(51, { complete = true, auto = true })
    world[51].index = nil
    ok(clickLines(fill(nil, 51)) == 0, "a quest the log no longer holds gains nothing")

    reset()
    quest(52, { complete = true, auto = true, noInfo = true })
    ok(clickLines(fill(nil, 52)) == 0, "nor one GetInfo cannot describe")

    reset()
    quest(53, { complete = true, auto = true })
    C_QuestLog.GetLogIndexForQuestID = nil
    ok(clickLines(fill(nil, 53)) == 0, "nor any quest on a client without GetLogIndexForQuestID")
    reset()
end

print("== a left click on a finished auto-complete quest hands it in")
do
    reset()
    quest(60, { complete = true, auto = true })
    local got = click(60)
    ok(got == "remove:60 show:60 notify",
       "popup removed, reward window opened, one repaint, and nothing else: " .. got)
end

print("== every other left click still super-tracks")
do
    reset()
    quest(61, { complete = true, auto = false })
    local got = click(61)
    ok(got == "supertrack:61 notify", "a finished NPC quest is focused, not handed in: " .. got)

    reset()
    quest(62, { complete = false, auto = true })
    got = click(62)
    ok(got == "supertrack:62 notify", "an unfinished auto-complete quest is focused: " .. got)

    reset()
    quest(63, { complete = true, failed = true, auto = true })
    got = click(63)
    ok(got == "supertrack:63 notify", "a failed one is focused, even though IsComplete says yes: "
       .. got)

    reset()
    quest(64, { complete = true, auto = true })
    world[64].index = nil
    got = click(64)
    ok(got == "supertrack:64 notify", "and so is one the log no longer holds: " .. got)
end

print("== the icon half of a split click super-tracks, as Blizzard's POI button does")
do
    reset()
    quest(65, { complete = true, auto = true })
    local got = click(65, "LeftButton", true)
    ok(got == "supertrack:65 notify", "the icon half focuses a finished quest, never hands it in: "
       .. got)
    got = click(65, "LeftButton", false)
    ok(got == "remove:65 show:65 notify", "while the whole row still hands it in: " .. got)
    got = click(65)
    ok(got == "remove:65 show:65 notify", "and so does a click that names no half: " .. got)
end

print("== a right click never hands a quest in")
do
    reset()
    quest(70, { complete = true, auto = true })
    local got = click(70, "RightButton")
    ok(got == "rmwatch:70", "it keeps untracking when no menu opens: " .. got)
end

print("== a missing or raising popup API does not cost the hand-in")
do
    reset()
    quest(80, { complete = true, auto = true })
    env.RemoveAutoQuestPopUp = function() note("remove-raised") error("no such popup") end
    local got = click(80)
    ok(got == "remove-raised show:80 notify", "a raising RemoveAutoQuestPopUp is contained: " .. got)

    reset()
    quest(81, { complete = true, auto = true })
    env.RemoveAutoQuestPopUp = nil
    got = click(81)
    ok(got == "show:81 notify", "an absent one is skipped: " .. got)

    reset()
    quest(82, { complete = true, auto = true })
    env.ShowQuestComplete = nil
    got = click(82)
    ok(got == "supertrack:82 notify", "and with no ShowQuestComplete the click falls back: " .. got)

    -- UI/AutoQuestPopup.lua records this global raising on a popup already retired, and the
    -- hand-in retires one on the line above. A raise reaching the row's mouse script would be
    -- a Lua error in place of the reward window.
    reset()
    quest(83, { complete = true, auto = true })
    env.ShowQuestComplete = function(id) note("show-raised:" .. tostring(id)) error("no quest") end
    got = click(83)
    ok(got == "remove:83 show-raised:83 supertrack:83 notify",
       "a raising ShowQuestComplete is contained and the click falls back: " .. got)
end

print("== the title half of a split click is Blizzard's header click")
do
    reset()
    quest(90, { complete = true, auto = true })
    local got = openLog(90)
    ok(got == "remove:90 show:90 notify", "a finished auto-complete quest is handed in: " .. got)

    reset()
    quest(91, { complete = true, auto = false })
    got = openLog(91)
    ok(got == "load:Blizzard_QuestLog openlog:91", "any other quest opens the log: " .. got)

    -- The fallback on this half is the quest log, so a raise that was not contained would take
    -- the line below it down as well and the press would do nothing at all.
    reset()
    quest(92, { complete = true, auto = true })
    env.ShowQuestComplete = function(id) note("show-raised:" .. tostring(id)) error("no quest") end
    got = openLog(92)
    ok(got == "remove:92 show-raised:92 load:Blizzard_QuestLog openlog:92",
       "a raising ShowQuestComplete still leaves the quest log opening: " .. got)

    reset()
    quest(92, { complete = false, auto = true })
    got = openLog(92)
    ok(got == "load:Blizzard_QuestLog openlog:92", "including an unfinished auto-complete one: "
       .. got)
end

print("== the menu's Open item only ever opens the log")
do
    reset()
    quest(100, { complete = true, auto = true })
    local got = menu(100, "openlog")
    ok(got == "load:Blizzard_QuestLog openlog:100 notify",
       "a finished auto-complete quest can still be read before it is handed in: " .. got)
end

print("== with no map to open, the log is toggled instead")
do
    reset()
    quest(105, { complete = false, auto = false })
    local saved = env.QuestMapFrame_OpenToQuestDetails
    env.QuestMapFrame_OpenToQuestDetails = nil
    local got = openLog(105)
    env.QuestMapFrame_OpenToQuestDetails = saved
    ok(got == "load:Blizzard_QuestLog togglelog", "ToggleQuestLog is the fallback: " .. got)
end

print("== an answer the client could not give yet is asked again")
do
    -- A memo of the miss would pin a quest filled before GetInfo could describe it to no line
    -- and no hand-in. Every other cannot-answer case uses a fresh id, so only this sees one.
    reset()
    quest(110, { complete = true, auto = true, noInfo = true })
    local e = fill(nil, 110)
    ok(clickLines(e) == 0, "no line while GetInfo cannot describe the quest")
    ok(click(110) == "supertrack:110 notify", "and no hand-in either")
    world[110].noInfo = nil
    fill(e, 110)
    ok(clickLines(e) == 1, "the line once it can, on the same pooled entry")
    ok(click(110) == "remove:110 show:110 notify", "and the click hands it in")
end

print("== both rebuild paths set the state before they fill the lines")
do
    -- fill() above sets the state itself, so only this can see production filling the lines
    -- before the state is written, which puts the line a quest event behind the green title.
    local q = stripComments(readFile("Data/Providers/Quests.lua"))
    local function body(from, to)
        local a = q:find(from, 1, true)
        local b = a and q:find(to, a, true)
        return (a and b) and q:sub(a, b - 1) or ""
    end
    for _, span in ipairs({ { "local function fullRebuild()", "local function refreshDynamic()" },
                            { "local function refreshDynamic()", "function Quests:IsAvailable()" } }) do
        local b = body(span[1], span[2])
        local writes, at = 0, nil
        for pos in b:gmatch("()e%.state%s*=[^=]") do writes = writes + 1 at = at or pos end
        -- Anchored to the START of a line and to the end of the statement, so wrapping the call
        -- in a condition is not the same text. A plain find() for it passes against
        -- `if e.state ~= STATE.COMPLETE then fillLines(e, id) end`, which removes the line the
        -- whole feature is about while every assertion here stays green.
        local fillAt = b:find("\n%s*fillLines%(e, id%)\n")
        ok(writes == 1 and fillAt ~= nil and at < fillAt,
           span[1] .. " writes e.state once, before an unconditional fillLines: " .. writes .. " "
           .. tostring(at) .. " " .. tostring(fillAt))
    end
end

print("== the row routes each press where the click promises, and a cancel nowhere")
do
    -- UI/Row.lua's click routing, sliced whole, so the dispatch that reaches turnIn is driven
    -- rather than grepped for.
    local rsrc = slicer("UI/Row.lua")("local function clickThrough()",
                                      "-- Offered only where both halves are really wired")
    local got, splitOn, menuOpens, cursorX
    local provider = {
        OnEntryClick = function(_, _, button, splitIcon)
            got[#got + 1] = "click:" .. tostring(button) .. (splitIcon and ":icon" or "")
        end,
        OnEntryOpenLog = function(_, _, ...) got[#got + 1] = "openlog:" .. select("#", ...) end,
    }
    local rowEnv = setmetatable({
        ns = { GetModule = function(_, name)
            if name == "Tracker" then return { IsClickThrough = function() return false end } end
            if name == "Registry" then return { Get = function() return provider end } end
            if name == "DB" then
                return { Tracker = function() return { splitQuestClick = splitOn } end }
            end
            if name == "RowMenu" then return { Show = function() return menuOpens end } end
            error("unexpected module " .. tostring(name), 0)
        end },
        IsModifiedClick = function() return false end,
        ChatEdit_GetActiveWindow = function() return nil end,
        IsShiftKeyDown = function() return false end,
        GetCursorPosition = function() return cursorX, 0 end,
    }, { __index = _G })
    local chunk = assert(loadstring(rsrc .. "\nreturn onMouseUp", "row-mouseup-slice"))
    setfenv(chunk, rowEnv)
    local onMouseUp = chunk()
    local row = { _entry = { id = 1 }, _providerID = "quests",
                  iconHolder = { IsShown = function() return true end,
                                 GetRight = function() return 100 end },
                  GetEffectiveScale = function() return 1 end }
    local function press(button, upInside)
        got = {}
        local okCall, err = pcall(onMouseUp, row, button, upInside)
        ok(okCall, "onMouseUp does not raise: " .. tostring(err))
        return table.concat(got, " ")
    end

    splitOn, menuOpens, cursorX = false, true, 500
    ok(press("LeftButton", true) == "click:LeftButton",
       "a left click reaches OnEntryClick with its button: " .. press("LeftButton", true))
    ok(press("LeftButton", nil) == "click:LeftButton",
       "and still does on a client that passes no upInside: " .. press("LeftButton", nil))
    ok(press("LeftButton", false) == "",
       "a press released off the row is a cancel and reaches nothing: " .. press("LeftButton", false))
    ok(press("RightButton", true) == "", "a right click that opens the menu dispatches nothing")
    menuOpens = false
    ok(press("RightButton", true) == "click:RightButton",
       "a right click with no menu keeps its button: " .. press("RightButton", true))
    ok(press("RightButton", false) == "", "and is canceled the same way off the row")

    splitOn, menuOpens = true, true
    ok(press("LeftButton", true) == "openlog:0",
       "a split title click reaches OnEntryOpenLog and nothing else: " .. press("LeftButton", true))
    ok(press("LeftButton", false) == "", "and is canceled off the row too")
    cursorX = 50
    ok(press("LeftButton", true) == "click:LeftButton:icon",
       "the icon half of a split click reaches OnEntryClick, told which half it was: "
       .. press("LeftButton", true))
    splitOn = false
    ok(press("LeftButton", true) == "click:LeftButton",
       "with split click off the same spot is an ordinary row click: " .. press("LeftButton", true))
    splitOn = true
    cursorX, menuOpens = 500, false
    ok(press("RightButton", true) == "click:RightButton",
       "and a right click never reaches OnEntryOpenLog: " .. press("RightButton", true))

    splitOn = false
    row._wasDragging = true
    ok(press("LeftButton", true) == "", "the release that ends a drag is swallowed")
    ok(row._wasDragging == nil, "and clears the flag, so the next press clicks")
    ok(press("LeftButton", true) == "click:LeftButton", "which it does")
end

print("== the row still routes both halves of a left click to the provider")
do
    ok(count(stripComments("a\n--[[\nx()\n]]\n-- x()\nb = 1 -- x()\n"), "x()") == 0,
       "the comment stripper removes block, whole-line and trailing comments")
    local row = stripComments(readFile("UI/Row.lua"))
    ok(count(row, 'dispatch(row, "OnEntryClick", button, splitIcon)') == 1,
       "UI/Row.lua dispatches the plain click to OnEntryClick with the half it was")
    ok(count(row, 'dispatch(row, "OnEntryOpenLog")') == 1,
       "and the split title click to OnEntryOpenLog")

    -- The handler by reference, so the client's own third argument reaches it. The slice above
    -- calls onMouseUp directly with arguments of its own, so it cannot see the wiring: wrapping
    -- it as function(s, b) onMouseUp(s, b) end drops upInside on every client and the cancel
    -- stops working with every assertion in this file green.
    ok(count(row, 'r:SetScript("OnMouseUp", onMouseUp)') == 1,
       "the row hands OnMouseUp straight to the handler, passing the client's arguments on")
    ok(count(row, "local function onMouseUp(row, button, upInside)") == 1,
       "and the handler takes upInside as its third argument")
end

print(("test_quest_turnin: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
