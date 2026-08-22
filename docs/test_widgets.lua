-- luacheck: globals Enum C_UIWidgetManager C_ScenarioInfo geterrorhandler
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
    },
    StatusBarValueTextType = { Value = 0, Time = 1 },
    WidgetShownState = { Hidden = 0, Shown = 1 },
}

local SETS, INFO = {}, {}
local function byID(id) return INFO[id] end
C_UIWidgetManager = {
    GetAllWidgetsBySetID             = function(id) return SETS[id] or {} end,
    GetObjectiveTrackerWidgetSetID   = function() return 240 end,
    GetStatusBarWidgetVisualizationInfo       = byID,
    GetDoubleStatusBarWidgetVisualizationInfo = byID,
    GetBulletTextListWidgetVisualizationInfo  = byID,
    GetTextWithStateWidgetVisualizationInfo   = byID,
    GetSpellDisplayVisualizationInfo          = byID,
    GetCaptureBarVisualizationInfo            = byID,
}
C_ScenarioInfo = {
    GetScenarioStepInfo = function() return { title = "Stage One", widgetSetID = 777 } end,
}
geterrorhandler = function() return function(e) error(e) end end

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
SETS[240] = { widget(1, "DoubleStatusBar", {
    orderIndex = 0, shownState = 1,
    leftBarMin = 0, leftBarMax = 10, leftBarValue = 5, leftText = "Zeta",
    rightBarMin = 0, rightBarMax = 10, rightBarValue = 5, rightText = "Alpha",
}) }
local out, n = W:Read(240)
ok(n == 2, "DoubleStatusBar pushes two entries, got " .. tostring(n))
ok(out[1].text == "Zeta", "left half draws first, got " .. tostring(out[1].text))
ok(out[2].text == "Alpha", "right half draws second, got " .. tostring(out[2].text))

SETS[240] = { widget(2, "BulletTextList", {
    orderIndex = 0, shownState = 1,
    lines = { { text = "Zeta" }, { text = "Middle" }, { text = "Alpha" } },
}) }
out, n = W:Read(240)
ok(n == 3, "bullet list keeps three lines, got " .. tostring(n))
ok(out[1].text == "Zeta" and out[2].text == "Middle" and out[3].text == "Alpha",
   "bullet list keeps its own order rather than alphabetizing")

SETS[240] = { widget(3, "StatusBar", bar(0, "Zulu")), widget(4, "StatusBar", bar(0, "Alfa")) }
out, n = W:Read(240)
ok(n == 2 and out[1].text == "Zulu" and out[2].text == "Alfa",
   "equal orderIndex keeps push order")

SETS[240] = { widget(5, "StatusBar", bar(9, "Late")), widget(6, "StatusBar", bar(1, "Early")) }
out, n = W:Read(240)
ok(n == 2 and out[1].text == "Early" and out[2].text == "Late",
   "orderIndex still outranks push order")

-- Shrink: a long read followed by a short one must leave no tail behind.
SETS[240] = {}
for i = 1, 6 do SETS[240][i] = widget(100 + i, "StatusBar", bar(i, "bar" .. i)) end
out, n = W:Read(240)
ok(n == 6 and out[6] ~= nil, "long read is six entries")
SETS[240] = { widget(200, "StatusBar", bar(0, "only")) }
out, n = W:Read(240)
ok(n == 1, "short read is one entry")
ok(out[2] == nil, "no tail of the long read survives")
ok(out[1].text == "only", "short read holds the right entry")

SETS[240] = {}
out, n = W:Read(240)
ok(n == 0 and out[1] == nil, "a read returning nothing clears the view")

-- Hidden gating, including the nested shownState a SpellDisplay carries on its payload.
SETS[240] = {
    widget(300, "StatusBar", { orderIndex = 0, shownState = 0, barMin = 0, barMax = 10,
                               barValue = 5, text = "hidden" }),
    widget(301, "StatusBar", bar(1, "shown")),
}
out, n = W:Read(240)
ok(n == 1 and out[1].text == "shown", "a hidden widget is dropped")

-- The status line must sum BOTH sets, or the tracker set's unread types vanish behind the
-- scenario set that is read immediately after it.
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

C_ScenarioInfo.GetScenarioStepInfo = function() return { title = "Stage One" } end
line = W:DebugLine()
ok(line:find("0 drawn", 1, true) ~= nil, "an ended scenario stops being reported, got: " .. line)

print(string.format("test_widgets: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
