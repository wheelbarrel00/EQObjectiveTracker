-- luacheck: globals Enum C_UIWidgetManager C_ScenarioInfo geterrorhandler GetTime
-- luacheck: globals issecretvalue
--
-- Unit tests for Data/Widgets.lua, run against the SHIPPED source rather than a copy.
-- Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_widgets.lua
--
-- The two cases that earn this file: SORT ORDER, because every entry a single widget pushes
-- carries the same order value and a tie-break on text alphabetized bullet lists; and the
-- SHRINK case, because table.sort has no length argument, so sorting a reused pool drags a
-- previous longer read's tail into the sorted range. Both shipped as real defects.
--
-- Read is answered from a snapshot until Invalidate says the widgets moved, so every case below
-- that changes SETS has to invalidate first - exactly as a widget event does in game. The
-- CACHE cases at the end are what prove the snapshot is really being used and really drops.

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
end

local ns = { L = setmetatable({}, { __index = function(_, k) return k end }) }
local mods = {}
function ns:RegisterModule(n, t) mods[n] = t return t end
function ns:GetModule(n) return mods[n] end

Enum = {
    UIWidgetVisualizationType = {
        StatusBar = 0, DoubleStatusBar = 1, BulletTextList = 2,
        TextWithState = 3, SpellDisplay = 4, CaptureBar = 5,
        ScenarioHeaderTimer = 6, ScenarioHeaderDelves = 7,
    },
    StatusBarValueTextType = { Value = 0, Time = 1 },
    WidgetShownState = { Hidden = 0, Shown = 1 },
}

local SETS, INFO = {}, {}
-- Every C_UIWidgetManager entry point is counted, because "the snapshot was used" is only
-- provable by the calls that did NOT happen.
local apiCalls = 0
-- Settable, so the prune rule can be tested: a snapshot survives while its set is one a render
-- can still ask for, and is dropped once it is not.
local trackerSetID = 240
local function byID(id) apiCalls = apiCalls + 1 return INFO[id] end
C_UIWidgetManager = {
    GetAllWidgetsBySetID             = function(id) apiCalls = apiCalls + 1 return SETS[id] or {} end,
    GetObjectiveTrackerWidgetSetID   = function() apiCalls = apiCalls + 1 return trackerSetID end,
    GetStatusBarWidgetVisualizationInfo       = byID,
    GetDoubleStatusBarWidgetVisualizationInfo = byID,
    GetBulletTextListWidgetVisualizationInfo  = byID,
    GetTextWithStateWidgetVisualizationInfo   = byID,
    GetSpellDisplayVisualizationInfo          = byID,
    GetCaptureBarVisualizationInfo            = byID,
    GetScenarioHeaderTimerWidgetVisualizationInfo  = byID,
    GetScenarioHeaderDelvesWidgetVisualizationInfo = byID,
}
C_ScenarioInfo = {
    GetScenarioStepInfo = function() return { title = "Stage One", widgetSetID = 777 } end,
}
geterrorhandler = function() return function(e) error(e) end end
local fakeNow = 1000
GetTime = function() return fakeNow end

-- Captured at chunk load by Data/Widgets.lua, so it has to exist before loadfile
local SECRET = setmetatable({}, { __tostring = function() return "secret" end })
issecretvalue = function(v) return v == SECRET end

local chunk = assert(loadfile(repoFile("Data/Widgets.lua")))
chunk("EQObjectiveTracker", ns)
local W = mods.Widgets
assert(W, "Data/Widgets.lua did not register a Widgets module")

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end

local function widget(id, typeName, info)
    INFO[id] = info
    return { widgetID = id, widgetType = Enum.UIWidgetVisualizationType[typeName] }
end

local function bar(order, text)
    return { orderIndex = order, shownState = 1, barMin = 0, barMax = 10,
             barValue = 1, text = text }
end

-- Ordering: a widget that pushes more than one entry gives them all the same order, so only
-- the push order can break the tie.
W:Invalidate()
SETS[240] = { widget(1, "DoubleStatusBar", {
    orderIndex = 0, shownState = 1,
    leftBarMin = 0, leftBarMax = 10, leftBarValue = 5, leftText = "Zeta",
    rightBarMin = 0, rightBarMax = 10, rightBarValue = 5, rightText = "Alpha",
}) }
local out, n = W:Read(240)
ok(n == 2, "DoubleStatusBar pushes two entries, got " .. tostring(n))
ok(out[1].text == "Zeta", "left half draws first, got " .. tostring(out[1].text))
ok(out[2].text == "Alpha", "right half draws second, got " .. tostring(out[2].text))

W:Invalidate()
SETS[240] = { widget(2, "BulletTextList", {
    orderIndex = 0, shownState = 1,
    lines = { { text = "Zeta" }, { text = "Middle" }, { text = "Alpha" } },
}) }
out, n = W:Read(240)
ok(n == 3, "bullet list keeps three lines, got " .. tostring(n))
ok(out[1].text == "Zeta" and out[2].text == "Middle" and out[3].text == "Alpha",
   "bullet list keeps its own order rather than alphabetizing")

W:Invalidate()
SETS[240] = { widget(3, "StatusBar", bar(0, "Zulu")), widget(4, "StatusBar", bar(0, "Alfa")) }
out, n = W:Read(240)
ok(n == 2 and out[1].text == "Zulu" and out[2].text == "Alfa",
   "equal orderIndex keeps push order")

W:Invalidate()
SETS[240] = { widget(5, "StatusBar", bar(9, "Late")), widget(6, "StatusBar", bar(1, "Early")) }
out, n = W:Read(240)
ok(n == 2 and out[1].text == "Early" and out[2].text == "Late",
   "orderIndex still outranks push order")

-- Shrink: a long read followed by a short one must leave no tail behind.
W:Invalidate()
SETS[240] = {}
for i = 1, 6 do SETS[240][i] = widget(100 + i, "StatusBar", bar(i, "bar" .. i)) end
out, n = W:Read(240)
ok(n == 6 and out[6] ~= nil, "long read is six entries")
W:Invalidate()
SETS[240] = { widget(200, "StatusBar", bar(0, "only")) }
out, n = W:Read(240)
ok(n == 1, "short read is one entry")
ok(out[2] == nil, "no tail of the long read survives")
ok(out[1].text == "only", "short read holds the right entry")

W:Invalidate()
SETS[240] = {}
out, n = W:Read(240)
ok(n == 0 and out[1] == nil, "a read returning nothing clears the view")

-- Hidden gating, including the nested shownState a SpellDisplay carries on its payload.
W:Invalidate()
SETS[240] = {
    widget(300, "StatusBar", { orderIndex = 0, shownState = 0, barMin = 0, barMax = 10,
                               barValue = 5, text = "hidden" }),
    widget(301, "StatusBar", bar(1, "shown")),
}
out, n = W:Read(240)
ok(n == 1 and out[1].text == "shown", "a hidden widget is dropped")

-- The status line must sum BOTH sets, or the tracker set's unread types vanish behind the
-- scenario set that is read immediately after it.
W:Invalidate()
SETS[240] = {
    widget(400, "StatusBar", bar(0, "tracker")),
    widget(401, "SpellDisplay", { orderIndex = 1, spellInfo = { spellID = 1, shownState = 1 } }),
    widget(402, "CaptureBar", { orderIndex = 2, barValue = 1, barMinValue = 0, barMaxValue = 2 }),
}
SETS[777] = { widget(500, "StatusBar", bar(0, "scenario")) }
W:Read(240)
W:Read(777)
local line = W:DebugLine()
ok(line:find("2 drawn", 1, true) ~= nil, "both sets counted, got: " .. line)
ok(line:find("SpellDisplay", 1, true) ~= nil, "tracker set unread type survives, got: " .. line)
ok(line:find("CaptureBar", 1, true) ~= nil, "second unread type survives, got: " .. line)

W:Forget(240)
line = W:DebugLine()
ok(line:find("1 drawn", 1, true) ~= nil, "a forgotten set drops its count, got: " .. line)
ok(line:find("SpellDisplay", 1, true) == nil, "a forgotten set drops its unread types")

W:Invalidate()
C_ScenarioInfo.GetScenarioStepInfo = function() return { title = "Stage One" } end
line = W:DebugLine()
ok(line:find("0 drawn", 1, true) ~= nil, "an ended scenario stops being reported, got: " .. line)

C_ScenarioInfo.GetScenarioStepInfo = function()
    return { title = "Stage One", widgetSetID = 777 }
end

-- The snapshot. Reading the same set twice without an invalidate must touch no API at all -
-- that reduction IS the change, so it is asserted rather than assumed.
W:Invalidate()
SETS[240] = { widget(600, "StatusBar", bar(0, "cached")) }
local before = apiCalls
n = select(2, W:Read(240))
ok(apiCalls > before, "a first read after invalidate calls the API")
before = apiCalls
local out2, n2 = W:Read(240)
ok(apiCalls == before, "a second read of the same set is served without touching the API")
ok(n2 == n and out2[1].text == "cached", "the cached read holds the same content")

-- Why a snapshot rather than the shared pool: the two callers ask for DIFFERENT sets inside one
-- render pass, so a pool handed straight back is rewritten under the first caller by the second.
W:Invalidate()
SETS[240] = { widget(601, "StatusBar", bar(0, "tracker set")) }
SETS[777] = { widget(602, "StatusBar", bar(0, "scenario set")) }
local trackerList = W:Read(240)
W:Read(777)
ok(trackerList[1].text == "tracker set",
   "reading the scenario set does not rewrite the tracker set's list, got: "
   .. tostring(trackerList[1].text))

-- Invalidate is the ONLY thing that lets a change through, and Forget drops the snapshot with
-- the counters so a caller that stopped drawing cannot be served a stale list later.
W:Invalidate()
SETS[240] = { widget(603, "StatusBar", bar(0, "moved")) }
out = W:Read(240)
ok(out[1].text == "moved", "invalidate lets the next read see the change")
W:Forget(240)
before = apiCalls
W:Read(240)
ok(apiCalls > before, "a forgotten set is read again rather than served from its snapshot")

-- Pruning. An api-call count cannot see this - a stale snapshot is re-read whether or not it was
-- dropped - so it is read off the identity of the list table, which a surviving snapshot reuses
-- and a dropped one replaces. The rule is membership, not age: a set a render can still ask for
-- keeps its pooled tables however many times UPDATE_UI_WIDGET fires, and that burst is exactly
-- what an age rule threw them away on.
local listA = W:Read(240)
W:Invalidate()
W:Invalidate()
W:Invalidate()
local listB = W:Read(240)
ok(listB == listA,
   "the current set keeps its snapshot through a burst of invalidations, tables and all")
-- A zone change moves the tracker set. The render that follows resolves the new id, and the
-- next invalidation is the one that can see 240 is no longer askable.
trackerSetID = 241
W:Invalidate()
W:Read(241)
W:Invalidate()
local listC = W:Read(240)
ok(listC ~= listB, "a set that stopped being current is dropped rather than kept forever")
trackerSetID = 240
W:Invalidate()

-- The countdown deadline is stamped when the value is READ. Serving the same reading again must
-- not move it, or every repaint between server pushes restarts the clock on screen.
W:Invalidate()
SETS[240] = { widget(700, "ScenarioHeaderTimer", {
    orderIndex = 0, shownState = 1, timerMin = 0, timerMax = 180, timerValue = 150,
    headerText = "Curse Surge",
}) }
out, n = W:Read(240)
ok(n == 1 and out[1].countdown == true, "a scenario header timer draws as a countdown")
ok(out[1].deadline == 1150, "the deadline is stamped at read time, got: " .. tostring(out[1].deadline))
fakeNow = 1030
out = W:Read(240)
ok(out[1].deadline == 1150, "a repaint between pushes leaves the deadline where it was")

-- The one that matters: UPDATE_UI_WIDGET fires PER WIDGET, so a sibling changing invalidates and
-- re-reads this timer with a value the server has not touched. Re-stamping there would jump the
-- clock backwards on screen by the age of the reading.
W:Invalidate()
out = W:Read(240)
ok(out[1].deadline == 1150,
   "an unrelated widget update does not restart the clock, got: " .. tostring(out[1].deadline))

-- A real push moves the value, and only that re-stamps
W:Invalidate()
INFO[700].timerValue = 90
out = W:Read(240)
ok(out[1].deadline == 1120,
   "a server push with a new value re-stamps it, got: " .. tostring(out[1].deadline))

-- The timer's header repeats the stage name the scenario banner already draws
W:Invalidate()
SETS[240] = { widget(701, "ScenarioHeaderTimer", {
    orderIndex = 0, shownState = 1, timerMin = 0, timerMax = 180, timerValue = 10,
    headerText = "Stage One",
}) }
out = W:Read(240)
ok(out[1].text == nil, "a header matching the stage title is dropped, got: " .. tostring(out[1].text))

-- The delve tier, which is the only thing read off the delve header widget
W:Invalidate()
SETS[240] = { widget(702, "ScenarioHeaderDelves", {
    orderIndex = 0, shownState = 1, tierText = "7", headerText = "Shadowguard Point",
}) }
out, n = W:Read(240)
ok(n == 1 and out[1].text == "Tier 7", "the delve tier draws, got: " .. tostring(out[1].text))

-- A secret value types as a string and throws when matched, so it has to read as absent
W:Invalidate()
SETS[240] = { widget(703, "StatusBar", { orderIndex = 0, shownState = 1, barMin = 0,
                                         barMax = 10, barValue = 5, text = SECRET }) }
out, n = W:Read(240)
ok(n == 1 and out[1].text == nil, "a secret label reads as absent rather than being drawn")
W:Invalidate()
SETS[240] = { widget(704, "StatusBar", { orderIndex = 0, shownState = 1, barMin = 0,
                                         barMax = SECRET, barValue = 5, text = "bad max" }) }
n = select(2, W:Read(240))
ok(n == 0, "a bar with a secret maximum is refused rather than drawn degenerate")

-- The availability guard. Data/Widgets.lua ships on all four flavors, and with the guard gone a
-- Read on a client without the API indexes a nil table OUTSIDE the pcall, because arguments are
-- evaluated first - so it raises rather than degrading. Callers gate first today, which is what
-- keeps this a trap rather than a live bug.
local realManager = C_UIWidgetManager
C_UIWidgetManager = nil
W:Invalidate()
local okCall, listX, nX = pcall(function() return W:Read(240) end)
ok(okCall, "a client with no widget API is refused rather than raising")
ok(nX == 0 or listX ~= nil, "and answers an empty read")
C_UIWidgetManager = realManager
W:Invalidate()

-- Nothing to read must never hand back the shared pool, which still holds the last read's
-- entries behind a non-zero length.
W:Invalidate()
SETS[240] = { widget(800, "StatusBar", bar(0, "still here")) }
local held = W:Read(240)
local none, noneN = W:Read(nil)
ok(noneN == 0, "a nil set id reads as nothing")
ok(none ~= held, "and does not hand back the list another caller is holding")
ok(#none == 0, "the empty answer is empty by length too, got: " .. tostring(#none))
ok(held[1] and held[1].text == "still here", "and the held list is untouched")

print(string.format("test_widgets: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
