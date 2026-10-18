-- luacheck: globals Enum C_UIWidgetManager C_ScenarioInfo geterrorhandler GetTime
-- luacheck: globals issecretvalue C_CurrencyInfo C_Spell C_Timer
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

local ns = { L = setmetatable({}, { __index = function(_, k) return k end }), Has = { DelveHeader = true } }
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
local scenarioSetID = 777
C_ScenarioInfo = {
    GetScenarioStepInfo = function()
        return { title = "Stage One", widgetSetID = scenarioSetID }
    end,
}
geterrorhandler = function() return function(e) error(e) end end
-- The nemesis counts. An id with no entry answers nil, as the client does for one it does not know.
local CUR, currencyRaises = {}, false
C_CurrencyInfo = {
    GetCurrencyInfo = function(id)
        if currencyRaises then error("the currency read raised") end
        if CUR[id] == nil then return nil end
        return { currencyID = id, quantity = CUR[id] }
    end,
}
-- Each affix answers its own icon, so reading the wrong spell's shows.
C_Spell = { GetSpellTexture = function(id) return 900000 + id, 1 end }
-- The nemesis wait. Every timer is kept so a case can end it, and records a cancel.
local timers = {}
C_Timer = {
    NewTimer = function(delay, fn)
        local t = { delay = delay, fn = fn, cancelled = false }
        function t.Cancel(self)
            assert(self == t, "Cancel without self")
            self.cancelled = true
        end
        timers[#timers + 1] = t
        return t
    end,
}
local fakeNow = 1000
GetTime = function() return fakeNow end

-- Captured at chunk load by Data/Widgets.lua, so it has to exist before loadfile
local SECRET = setmetatable({}, { __tostring = function() return "secret" end })
issecretvalue = function(v) return v == SECRET end

-- Events and DB, so OnEnable's own listeners can be driven. mods.Events is what the module
-- takes at OnEnable time, so it has to be registered before then rather than before loadfile.
local handlers, debounced = {}, 0
mods.Events = {
    On       = function(_, e, fn) handlers[e] = fn end,
    Debounce = function() debounced = debounced + 1 end,
}
local cfg = {}
mods.DB = {}
function mods.DB.Tracker(self)
    assert(self == mods.DB, "DB:Tracker without self")
    return cfg
end

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

-- Back to the variable, not a fixed 777, or every later case that moves the scenario moves nothing.
C_ScenarioInfo.GetScenarioStepInfo = function()
    return { title = "Stage One", widgetSetID = scenarioSetID }
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

-- The delve header. With both counters off, or below Tier 4, the tier draws as a line of text as it
-- always has. With either on, the tier and the counters are one entry, which the block draws as a row.
local function delve(id, tier, currencies, spells)
    return widget(id, "ScenarioHeaderDelves", { orderIndex = 0, shownState = 1, tierText = tier,
                                                headerText = "Shadowguard Point", currencies = currencies,
                                                spells = spells })
end
local function readDelve(tier, currencies, spells)
    W:Invalidate()
    SETS[240] = { delve(702, tier, currencies, spells) }
    return W:Read(240)
end
local function raising() return setmetatable({}, { __index = function() error("raised") end }) end
-- The second entry carries different values, so reading the wrong one shows.
local LIVES = { { text = "4", iconFileID = 4410, tooltip = "Total deaths: 1" },
                { text = "9", iconFileID = 4411, tooltip = "the wrong entry" } }
-- The nemesis affix in the middle, as on the header, with no tooltip text of its own.
local SPELLS = { { spellID = 111, tooltip = "first affix" }, { spellID = 1307638, tooltip = "" },
                 { spellID = 222, tooltip = "third affix" } }
CUR[3103], CUR[3104] = 2, 3

cfg.showDelveLives, cfg.showNemesisGroups = false, false
local list, count = readDelve("7", LIVES, SPELLS)
ok(count == 1 and list[1].kind == "text" and list[1].text == "Tier 7", "both counters switched off: the tier alone, as text")
-- Both ship on (the author, 2026-10-17), so a profile that never touched them draws both.
cfg.showDelveLives, cfg.showNemesisGroups = nil, nil
list, count = readDelve("7", LIVES, SPELLS)
ok(count == 1 and list[1].kind == "delve" and list[1].lives == 4 and list[1].nemAlive == 2,
   "both unset: both drawn, as they are on by default")
cfg.showDelveLives, cfg.showNemesisGroups = 1, "yes"
list, count = readDelve("7", LIVES, SPELLS)
ok(count == 1 and list[1].kind == "delve" and list[1].lives == 4 and list[1].nemAlive == 2,
   "only a real false switches either off")

cfg.showDelveLives, cfg.showNemesisGroups = true, false
list, count = readDelve("7", LIVES, SPELLS)
local d = list[1]
ok(count == 1 and d.kind == "delve" and d.text == "Tier 7", "lives on: one row with the tier on it, got " .. tostring(d.kind))
ok(d.lives == 4 and d.livesIcon == 4410 and d.livesTip == "Total deaths: 1",
   "the first currency's number, icon and tooltip: " .. tostring(d.lives) .. " " .. tostring(d.livesIcon))
ok(d.nemAlive == nil and d.nemTotal == nil and d.nemSpell == nil and d.nemIcon == nil and d.nemTip == nil,
   "and nothing of the nemesis")

cfg.showDelveLives, cfg.showNemesisGroups = false, true
d = readDelve("7", LIVES, SPELLS)[1]
ok(d.kind == "delve" and d.lives == nil and d.livesIcon == nil and d.livesTip == nil, "nemesis on: nothing of the lives")
ok(d.nemAlive == 2 and d.nemTotal == 3, "the groups alive and the total: " .. tostring(d.nemAlive) .. "/" .. tostring(d.nemTotal))
ok(d.nemSpell == 1307638 and d.nemIcon == 900000 + 1307638, "the affix found by its id, with that spell's own icon")
ok(d.nemTip == nil, "an affix with no tooltip text leaves the spell's own tooltip to show")

cfg.showDelveLives = true
d = readDelve("7", LIVES, SPELLS)[1]
ok(d.lives == 4 and d.nemAlive == 2 and d.nemSpell == 1307638, "both on: both on the one row")

d = readDelve("7", LIVES, { { spellID = 1270179, tooltip = "Nemesis Influence" } })[1]
ok(d.nemSpell == 1270179 and d.nemIcon == 900000 + 1270179 and d.nemTip == "Nemesis Influence",
   "the older season's id is found too, with the affix's own tooltip text")
d = readDelve("7", LIVES, { { spellID = 1270179 }, { spellID = 1307638 } })[1]
ok(d.nemSpell == 1270179 and d.nemIcon == 900000 + 1270179, "the first listed affix on the header wins")

-- Each affix reading that fails costs the icon and tooltip only, never the count.
for _, c in ipairs({ { "no spells", nil }, { "a secret list", SECRET },
                     { "no listed id", { { spellID = 111 }, { spellID = 222 } } },
                     { "a secret id", { { spellID = SECRET } } }, { "an entry that is not a table", { 1307638 } },
                     { "an entry that raises when read", { raising() } } }) do
    local okRead, got = pcall(readDelve, "8", LIVES, c[2])
    local row = okRead and got[1]
    ok(row and row.kind == "delve" and row.nemAlive == 2 and row.nemSpell == nil and row.nemIcon == nil
       and row.nemTip == nil and row.lives == 4, c[1] .. ": the count with no affix icon, the lives drawn")
end
local realSpell = C_Spell
C_Spell = nil
d = readDelve("8", LIVES, SPELLS)[1]
ok(d.nemSpell == 1307638 and d.nemIcon == nil and d.nemAlive == 2, "a client with no spell API: the affix found, no icon")
C_Spell = { GetSpellTexture = function() return SECRET end }
ok(readDelve("8", LIVES, SPELLS)[1].nemIcon == nil, "a secret icon reads as no icon")
C_Spell = realSpell

list, count = readDelve("3", LIVES, SPELLS)
ok(count == 1 and list[1].kind == "text" and list[1].text == "Tier 3", "Tier 3: the tier alone, as text")
d = readDelve("4", LIVES, SPELLS)[1]
ok(d.kind == "delve" and d.lives == 4 and d.nemAlive == 2, "Tier 4: the row, both counters on it")
d = readDelve("10", LIVES, SPELLS)[1]
ok(d.kind == "delve" and d.text == "Tier 10", "Tier 10: the row, the tier compared as a number")
ok(select(2, readDelve(nil, LIVES, SPELLS)) == 0, "no tier: nothing at all")
ok(select(2, readDelve(SECRET, LIVES, SPELLS)) == 0, "a secret tier: nothing at all")

-- Each lives reading that is not a number costs the lives only.
ok(readDelve("8", { { text = "0", iconFileID = 4410 } }, SPELLS)[1].lives == 0, "no lives left is a 0, drawn")
for _, c in ipairs({ { "an empty text", { { text = "" } } }, { "a secret text", { { text = SECRET } } },
                     { "no currencies", nil }, { "a secret list", SECRET }, { "an entry that is not a table", { "4" } },
                     { "an entry that raises when read", { raising() } } }) do
    local okRead, got = pcall(readDelve, "8", c[2], SPELLS)
    local row = okRead and got[1]
    ok(row and row.kind == "delve" and row.lives == nil and row.livesIcon == nil and row.nemAlive == 2,
       c[1] .. ": no lives, the nemesis drawn")
end
d = readDelve("8", { { text = "5", iconFileID = SECRET, tooltip = SECRET } }, SPELLS)[1]
ok(d.lives == 5 and d.livesIcon == nil and d.livesTip == nil, "a secret icon or tooltip reads as absent, the number drawn")
d = readDelve("8", { { text = "5", iconFileID = 4410, tooltip = "" } }, SPELLS)[1]
ok(d.lives == 5 and d.livesIcon == 4410 and d.livesTip == nil, "an empty tooltip reads as none")
cfg.showNemesisGroups = false
list, count = readDelve("8", { { text = "" } }, SPELLS)
ok(count == 1 and list[1].kind == "text", "lives on but unreadable, nemesis off: the tier as text")
cfg.showNemesisGroups = true

-- And each nemesis reading that is not a count costs the nemesis only.
for _, c in ipairs({ { "no total", 2, 0 }, { "no alive count", nil, 3 }, { "no total count", 2, nil },
                     { "a secret alive count", SECRET, 3 }, { "a secret total", 2, SECRET },
                     { "a negative count", -1, 3 } }) do
    CUR[3103], CUR[3104] = c[2], c[3]
    local okRead, got = pcall(readDelve, "8", LIVES, SPELLS)
    d = okRead and got[1]
    ok(d and d.kind == "delve" and d.lives == 4 and d.nemAlive == nil and d.nemTotal == nil and d.nemSpell == nil,
       c[1] .. ": nothing of the nemesis, the lives drawn, and no raise: " .. tostring(okRead and "" or got))
end
CUR[3103], CUR[3104] = 0, 3
d = readDelve("8", LIVES, SPELLS)[1]
ok(d.nemAlive == 0 and d.nemTotal == 3 and d.nemSpell == 1307638, "all dead: still drawn, for the check mark")
CUR[3103], CUR[3104] = 3, 3
d = readDelve("8", LIVES, SPELLS)[1]
ok(d.nemAlive == 3 and d.nemTotal == 3, "none dead yet: 3 of 3")
-- The row draws total minus alive, so the total must be the game's, and a reading above it must reach the
-- row, which clamps it.
CUR[3103], CUR[3104] = 1, 4
d = readDelve("10", LIVES, SPELLS)[1]
ok(d.nemAlive == 1 and d.nemTotal == 4, "Tier 10's four groups: the total is the game's, not three: " .. tostring(d.nemTotal))
CUR[3103], CUR[3104] = 5, 3
d = readDelve("8", LIVES, SPELLS)[1]
ok(d.nemAlive == 5 and d.nemTotal == 3, "a reading above the total still reaches the row, which clamps it")
currencyRaises = true
local okRaise, raised = pcall(readDelve, "8", LIVES, SPELLS)
d = okRaise and raised[1]
ok(d and d.lives == 4 and d.nemAlive == nil, "a currency read that raises costs the nemesis only")
currencyRaises = false
CUR[3103], CUR[3104] = 2, 3

-- /eqot status names what the header carried, read whatever the switches say, and every affix id.
cfg.showDelveLives, cfg.showNemesisGroups = nil, nil
readDelve("7", LIVES, SPELLS)
local status = W:DebugLine()
ok(status:find(" | delve tier 7, lives 4, nemesis alive 2/3, spell 1307638 of 111,1307638,222", 1, true),
   "the status line names the tier, lives, groups alive and affixes: " .. status)
currencyRaises = true
status = W:DebugLine()
ok(status:find(" | delve tier 7, lives 4, nemesis alive read threw/-, spell 1307638", 1, true),
   "and says so when the groups read raised: " .. status)
currencyRaises = false
readDelve("8", { { text = "" } }, { { spellID = 111 }, { spellID = 222 } })
status = W:DebugLine()
ok(status:find(" | delve tier 8, lives nil, nemesis alive 2/3, spell nil of 111,222", 1, true),
   "no lives number and no listed affix read nil, with the ids it did see: " .. status)
readDelve("8", LIVES, nil)
status = W:DebugLine()
ok(status:find(", spell nil of none", 1, true), "and a header with no affixes says none: " .. status)
scenarioSetID = 4243
W:Invalidate()
status = W:DebugLine()
ok(not status:find("delve", 1, true), "a new scenario clears it: " .. status)
scenarioSetID = 777
W:Invalidate()
W:ScenarioSetID()
cfg.showDelveLives, cfg.showNemesisGroups = nil, nil

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

-- The availability guard. Data/Widgets.lua ships on every flavor, and with the guard gone a
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

-- ------------------------------------------------- which widget events reach the tracker

-- UPDATE_UI_WIDGET names the SET its widget belongs to, and this addon reads exactly two. The
-- payload used to be discarded, so a widget ticking anywhere in the game - top center, below
-- minimap, another addon's - asked for a full tracker repaint, and every provider rebuilt
-- behind it. Classic registers none of this, because OnEnable returns on a client with no
-- C_UIWidgetManager.
W:OnEnable()
ok(handlers.UPDATE_UI_WIDGET ~= nil, "the widget event is subscribed")

-- Resolve the ids first, the way the first render does. Without this the filter is in its
-- fail-open state and proves nothing.
W:TrackerSetID()
W:ScenarioSetID()

local function fire(payload)
    debounced = 0
    local sent, err = pcall(handlers.UPDATE_UI_WIDGET, "UPDATE_UI_WIDGET", payload)
    ok(sent, "the widget handler does not raise: " .. tostring(err))
    if not sent then return -1 end
    return debounced
end
local function widgetEvent(setID)
    return fire(setID and { widgetSetID = setID } or nil)
end

ok(widgetEvent(trackerSetID) == 1, "a widget in the tracker's own set asks for a repaint")
ok(widgetEvent(777) == 1, "so does one in the scenario set")
ok(widgetEvent(999999) == 0, "a widget in a set this addon never reads asks for nothing")
ok(widgetEvent(nil) == 1,
   "and a payload with no set at all still does, so UPDATE_ALL_UI_WIDGETS is unaffected")

-- A payload that IS a table and carries no set. This guard had NO case: inverting it to
-- `return false` left the whole file green, because the nil payload above is answered by the
-- type test one line higher and never reaches it.
local rawEvent = fire
W:TrackerSetID(); W:ScenarioSetID()
ok(rawEvent({}) == 1, "a widget payload carrying no set at all fails open")

-- A secret set id has to read as ABSENT, the way every other Blizzard read in this file does.
-- Read raw it failed CLOSED - refusing the repaint AND the Invalidate behind it - which is the
-- opposite of what the comment above the filter promises.
W:TrackerSetID(); W:ScenarioSetID()
ok(rawEvent({ widgetSetID = SECRET }) == 1,
   "a secret widget set id fails open rather than closed")

-- Our own widget ticking must not LOOSEN the filter. Invalidate bumps the generation and the
-- burst behind it is exactly the case the snapshot reuse exists for, so a foreign set is still
-- refused straight after one of ours has been through.
W:TrackerSetID(); W:ScenarioSetID()
ok(widgetEvent(trackerSetID) == 1, "our own set asks for a repaint")
ok(widgetEvent(999999) == 0, "and a foreign set is still refused straight after it")

-- A payload with no set at all means "assume everything moved", so the resolved pair stops
-- being trusted until a render re-reads it. Nothing asserted that, so deleting the line left
-- the file green while a set that moved across a loading screen was refused.
scenarioSetID = 4242
W:TrackerSetID(); W:ScenarioSetID()
scenarioSetID = 5150
ok(widgetEvent(5150) == 0, "a set the resolved pair does not name is refused")
ok(widgetEvent(nil) == 1, "a payload with no set is let through")
ok(widgetEvent(5150) == 1, "and retires the pair, so the moved set is no longer refused")
scenarioSetID = 777
W:TrackerSetID(); W:ScenarioSetID()

-- The filter compares against ids only a RENDER resolves, so a scenario STARTING left the pair
-- naming the sets from before it and the new scenario's first widget events were dropped, the
-- Invalidate with them. SCENARIO_UPDATE marks the pair stale for exactly this.
scenarioSetID = 4242
ok(widgetEvent(4242) == 0, "a set the last render never saw is refused while nothing says otherwise")
handlers.SCENARIO_UPDATE("SCENARIO_UPDATE")
ok(widgetEvent(4242) == 1,
   "a widget in a scenario that started since the last render is not dropped")
W:TrackerSetID(); W:ScenarioSetID()
ok(widgetEvent(999999) == 0, "and the filter is tight again once a render has re-resolved")
scenarioSetID = 777
W:TrackerSetID(); W:ScenarioSetID()

-- This handler is SHARED with PLAYER_ENTERING_WORLD, which passes isInitialLogin - a BOOLEAN -
-- where a widget event passes a table. Testing the truthiness rather than the type indexed
-- `true` and raised, once per session, on the first login of every retail player. Zoning and a
-- reload both pass false and were silently fine, which is exactly why the harness has to drive
-- all three payloads rather than the one it was written for.
ok(handlers.PLAYER_ENTERING_WORLD ~= nil, "the login event shares this handler")
for _, p in ipairs({ { "first login", true, false }, { "reload", false, true },
                     { "zoning", false, false } }) do
    debounced = 0
    local rang, err = pcall(handlers.PLAYER_ENTERING_WORLD,
                            "PLAYER_ENTERING_WORLD", p[2], p[3])
    ok(rang, p[1] .. " does not raise: " .. tostring(err))
    ok(rang and debounced == 1, p[1] .. " still asks for a repaint, got " .. debounced)
end

-- The generation still moves for our own sets even when the repaint is refused below, so a
-- snapshot can never outlive the widgets it describes.
cfg.showTrackerWidgets = false
ok(widgetEvent(trackerSetID) == 0,
   "with the widgets option off, our own set asks for no repaint either")

-- Only the REPAINT is refused, never the bookkeeping. Skipping Invalidate here would let the
-- snapshot outlive the widgets it describes, so the render after the option is switched back
-- on would draw whatever was true when it was switched off. The API call count is the only
-- thing that can see this: the entries look identical either way.
SETS[trackerSetID] = { widget(801, "StatusBar", bar(3, "moved while off")) }
W:Read(trackerSetID)
before = apiCalls
W:Read(trackerSetID)
ok(apiCalls == before, "a repeat read is served from the snapshot, as always")
SETS[trackerSetID] = { widget(802, "StatusBar", bar(4, "moved again")) }
widgetEvent(trackerSetID)
before = apiCalls
local reread = W:Read(trackerSetID)
ok(apiCalls > before,
   "a widget event with the option OFF still drops the snapshot, so the next read is fresh")
ok(reread[1] and reread[1].text == "moved again",
   "and it is the new widget that is read, got " .. tostring(reread[1] and reread[1].text))

cfg.showTrackerWidgets = nil

-- The nemesis counts are currencies, so only their own event says they moved. A kill reports 0 and
-- then the real count, up to a second apart, which would flash the all-dead check. From the first
-- report the row keeps the count it had, each report restarts a one-second wait (the figure two
-- other trackers wait for the same reason), and when the reports stop the snapshot drops and the
-- tracker repaints once.
ok(handlers.CURRENCY_DISPLAY_UPDATE ~= nil, "the currency event is subscribed where the delve widget exists")
local repaints = 0
W:OnDirty(function() repaints = repaints + 1 end)
local function currencyEvent(id)
    local sent, err = pcall(handlers.CURRENCY_DISPLAY_UPDATE, "CURRENCY_DISPLAY_UPDATE", id, 1, 1)
    ok(sent, "the currency handler does not raise: " .. tostring(err))
end
local function nemesisOf(entries, size)
    for i = 1, size do
        if entries[i].kind == "delve" then return entries[i].nemAlive, entries[i].nemTotal end
    end
end
local function readNem()
    W:TrackerSetID(); W:ScenarioSetID()
    return nemesisOf(W:Read(240))
end
local function clearTimers() for i = #timers, 1, -1 do timers[i] = nil end end
-- Ends wait i (the latest when left out), failing rather than raising when none was started.
local function endWait(i)
    local t = timers[i or #timers]
    ok(t ~= nil, "a wait was started to end, " .. #timers .. " running")
    if t then t.fn() end
end

cfg.showNemesisGroups = true
CUR[3103], CUR[3104] = 3, 3
SETS[240] = { delve(702, "8", LIVES, SPELLS) }
W:Invalidate()
ok(readNem() == 3, "three groups alive before any kill")

clearTimers()
repaints = 0
CUR[3103] = 0
currencyEvent(3103)
ok(#timers == 1 and timers[1].delay == 1 and not timers[1].cancelled, "the first report starts a one-second wait")
W:Invalidate()
local alive, total = readNem()
ok(alive == 3 and total == 3, "a read while the reports come in keeps the count it had, not the 0: " .. tostring(alive))
ok(W:DebugLine():find("nemesis alive 0/3 held", 1, true), "and the status line says it is held: " .. W:DebugLine())
ok(repaints == 0, "nothing repaints yet")

CUR[3103] = 2
currencyEvent(3103)
ok(#timers == 2 and timers[1].cancelled and not timers[2].cancelled and timers[2].delay == 1,
   "the next report cancels the wait and starts another")
W:Invalidate()
ok(readNem() == 3, "still held")
local calls = apiCalls
endWait(2)
ok(repaints == 1, "when the reports stop the tracker repaints once, got " .. repaints)
alive = readNem()
ok(apiCalls > calls, "the snapshot was dropped, so that read went back to the client")
ok(alive == 2, "and the row shows the real count: " .. tostring(alive))
ok(not W:DebugLine():find(" held", 1, true), "no longer held")

CUR[3103] = 0
currencyEvent(3103)
endWait()
ok(readNem() == 0, "a 0 that stands past the wait is all dead")

-- The total's own report holds too.
CUR[3103], CUR[3104] = 2, 3
currencyEvent(3104)
endWait()
ok(readNem() == 2, "settled at 2 of 3")
clearTimers()
CUR[3103] = 0
currencyEvent(3104)
ok(#timers == 1, "currency 3104 starts the wait as well")
W:Invalidate()
ok(readNem() == 2, "and holds the count")
endWait(1)
-- The hold keeps the total with the count, so a total reporting 0 in the wait cannot reach the row.
CUR[3103], CUR[3104] = 2, 3
W:Invalidate()
ok(readNem() == 2, "settled at 2 of 3 again")
clearTimers()
CUR[3103], CUR[3104] = 0, 0
currencyEvent(3104)
W:Invalidate()
local heldA, heldT = readNem()
ok(heldA == 2 and heldT == 3, "a total that reports 0 in the wait is held as well: " .. tostring(heldA) .. "/" .. tostring(heldT))
CUR[3104] = 3
endWait(1)
CUR[3103], CUR[3104] = 1, 4
W:Invalidate()
heldA, heldT = readNem()
ok(heldA == 1 and heldT == 4, "a fresh read takes the new total: " .. tostring(heldT))
clearTimers()
currencyEvent(3103)
W:Invalidate()
heldA, heldT = readNem()
ok(heldA == 1 and heldT == 4, "and the hold serves the last read's total, not an older one: " .. tostring(heldT))
endWait(1)
CUR[3104] = 3

-- Any other currency starts nothing and holds nothing.
for _, id in ipairs({ 3102, 3105, 1, SECRET, "3103" }) do
    clearTimers()
    CUR[3103] = 1
    currencyEvent(id)
    W:Invalidate()
    ok(#timers == 0 and readNem() == 1, "currency " .. tostring(id) .. " starts no wait and holds nothing")
end
clearTimers()
currencyEvent(nil)
ok(#timers == 0, "an event with no currency id starts no wait")

-- The wait always drops the snapshot, and repaints only while the count can draw.
for _, c in ipairs({ { "with the nemesis count off", false, nil, 0 }, { "with it unset, so on", nil, nil, 1 },
                     { "with it set to a non-false value", 1, nil, 1 },
                     { "with the widgets box off", true, false, 0 } }) do
    cfg.showNemesisGroups, cfg.showTrackerWidgets = c[2], c[3]
    clearTimers()
    currencyEvent(3103)
    W:Read(240)
    calls = apiCalls
    repaints = 0
    endWait(1)
    ok(repaints == c[4], c[1] .. ", the wait ends with " .. c[4] .. " repaint(s), got " .. repaints)
    W:Read(240)
    ok(apiCalls > calls, c[1] .. ", the snapshot drops")
end
cfg.showNemesisGroups, cfg.showTrackerWidgets = true, nil

-- A new delve drops the held count, so a hold cannot carry one run's count into the next.
CUR[3103] = 2
W:Invalidate()
ok(readNem() == 2, "two alive")
clearTimers()
currencyEvent(3103)
CUR[3103] = 1
scenarioSetID = 4244
W:Invalidate()
ok(readNem() == 1, "a new scenario reads the count afresh while the wait still runs")
scenarioSetID = 777
W:Invalidate()
endWait(1)
cfg.showNemesisGroups, cfg.showTrackerWidgets = nil, nil

-- Fail OPEN before anything has resolved a set id, which is the state at login: the filter may
-- only ever remove work, never introduce a case where a real change is missed.
local fresh = {}
local nsFresh = { L = ns.L, Has = {} }
function nsFresh:RegisterModule(name, t) fresh[name] = t return t end
function nsFresh:GetModule(name) return fresh[name] end
local h2, d2 = {}, 0
fresh.Events = {
    On       = function(_, e, fn) h2[e] = fn end,
    Debounce = function() d2 = d2 + 1 end,
}
fresh.DB = { Tracker = function() return {} end }
assert(loadfile(repoFile("Data/Widgets.lua")))("EQObjectiveTracker", nsFresh)
fresh.Widgets:OnEnable()
h2.UPDATE_UI_WIDGET("UPDATE_UI_WIDGET", { widgetSetID = 424242 })
ok(d2 == 1, "before any set id is resolved, an unknown set is let through rather than dropped")
ok(h2.CURRENCY_DISPLAY_UPDATE == nil, "a client with no delve widget never subscribes the currency event")
ok(h2.UPDATE_UI_WIDGET ~= nil, "while it still subscribes the widget events")

print(string.format("test_widgets: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
