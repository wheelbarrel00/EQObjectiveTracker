local _, ns = ...

local Widgets = ns:RegisterModule("Widgets", {})
local L       = ns.L

-- Midnight can hand back "secret values" that error when matched by tainted addon code,
-- even though they still report type "string"
local _issecret = _G.issecretvalue

local REFRESH_DEBOUNCE = 0.2

-- Read only, and it must stay that way. Registering a UIWidgetContainer against one of these
-- sets was reported breaking the next tooltip to close with widgets on it, and removing that
-- registration is what closed the report - see the note in UI/Scenario.lua. Reading the info
-- and drawing our own frames is a different thing, but the taint posture of these reads is
-- unproven in either direction, which is what showTrackerWidgets gives a bisection an axis
-- for.
--
-- Only the sets EQOT HIDES are read. UI/Blizzard.lua hides ObjectiveTrackerFrame, which takes
-- this set off screen with it, and the scenario step set goes with the stage block. Top
-- center and below minimap are Blizzard frames this addon leaves alone, so they still draw
-- themselves and drawing them again would double up.

local function plain(v)
    if v == nil then return nil end
    if _issecret and _issecret(v) then return nil end
    return v
end

local function num(v)
    v = plain(v)
    return type(v) == "number" and v or nil
end

local function str(v)
    v = plain(v)
    if type(v) ~= "string" or v == "" then return nil end
    return v
end

-- Resolved by NAME rather than by number, once. Blizzard adds enum members, and a table
-- keyed on today's numbers acquires a wrong answer the day it does.
local typeByValue, valueTextByValue
local function resolveEnums()
    if typeByValue then return end
    typeByValue, valueTextByValue = {}, {}
    local VT = Enum and Enum.UIWidgetVisualizationType
    if type(VT) == "table" then
        for name, value in pairs(VT) do typeByValue[value] = name end
    end
    local ST = Enum and Enum.StatusBarValueTextType
    if type(ST) == "table" then
        for name, value in pairs(ST) do valueTextByValue[value] = name end
    end
end

-- Two naming conventions are in use on C_UIWidgetManager and neither covers every type.
local INFO_SUFFIXES = { "VisualizationInfo", "WidgetVisualizationInfo" }

local function visualizationInfo(typeName, widgetID)
    for i = 1, #INFO_SUFFIXES do
        local fn = C_UIWidgetManager["Get" .. typeName .. INFO_SUFFIXES[i]]
        if fn then
            local ok, info = pcall(fn, widgetID)
            if ok and type(info) == "table" then return info end
        end
    end
    return nil
end

-- Some types keep shownState on their payload table rather than at the top level. Measured on
-- 2026-08-21: a SpellDisplay in the objective tracker set carried spellInfo.shownState = 0 with
-- nothing at the top, so a top-level-only test called two hidden widgets shown.
local NESTED_STATE = { "spellInfo", "itemInfo" }

-- A set answers with everything registered against it, most of it not on screen. Measured on
-- the same client: top center returned 33 widgets, 32 of them hidden. A type carrying no
-- shownState anywhere is treated as shown.
local function isHidden(info)
    local v = plain(info.shownState)
    if v == nil then
        for i = 1, #NESTED_STATE do
            local sub = plain(info[NESTED_STATE[i]])
            if type(sub) == "table" then
                v = plain(sub.shownState)
                if v ~= nil then break end
            end
        end
    end
    if v == nil then return false end
    local SS = Enum and Enum.WidgetShownState
    return v == ((SS and SS.Hidden) or 0)
end

-- Reused across reads. This runs on the render path, so a fresh list per repaint would
-- allocate for as long as any widget is on screen.
--
-- pool OWNS the tables and only ever grows. out is the view handed back, and its tail is
-- nilled on every read. Sorting the pool directly would drag a previous, longer read's
-- leftovers into the sorted range, because table.sort has no way to be told a length.
local pool, out, outN = {}, {}, 0
local skipped, skippedN = {}, 0

-- Read runs once per set and each caller draws its own slice, so one pair of counters would
-- only ever describe whichever set ran last. Recorded per set instead, and DebugLine reports
-- the live sets only, so a finished scenario's numbers cannot linger.
local stats = {}

-- Widgets are ordered within a set, not across sets, so the set's own position is folded in
-- ahead of the widget's. Without it two sets interleave by a number that means nothing
-- between them.
local SET_STRIDE = 1000000

local function acquire(order, tooltip)
    outN = outN + 1
    local o = pool[outN]
    if not o then o = {}; pool[outN] = o end
    o.kind, o.text, o.value, o.min, o.max = nil, nil, nil, nil, nil
    o.valueTextKind, o.overrideText, o.colorTint, o.textureKit = nil, nil, nil, nil
    o.countdown = nil
    o.order, o.tooltip = order or 0, tooltip
    o.seq = outN
    out[outN] = o
    return o
end

-- Returns the entry so a reader can flag something the shape has no field for, and nil when
-- the bar was refused, which is what keeps that flag off the wrong entry.
local function pushBar(order, minV, maxV, value, textKind, override, tint, tooltip, label, kit)
    if not (maxV and value) or maxV <= minV then return nil end
    local o = acquire(order, tooltip)
    o.kind          = "bar"
    o.min, o.max    = minV, maxV
    o.value         = value
    o.valueTextKind = textKind
    o.overrideText  = override
    o.colorTint     = tint
    o.textureKit    = kit
    o.text          = label
    return o
end

local function pushText(order, text, tooltip)
    if not text then return end
    local o = acquire(order, tooltip)
    o.kind = "text"
    o.text = text
end

-- What the scenario banner is already showing, so a widget repeating it can be trimmed.
-- Declared here because a reader below reads it and Read refreshes it.
local stageTitle

-- Keyed on the widget type NAME. A type with no reader here is counted rather than dropped
-- silently, and /eqot status names it, so the next one to matter is visible rather than
-- absent.
local READERS = {}

-- textureKit is the fill COLOR here, not frame art - measured returning Yellow, Blue and
-- White beside a colorTint of 0. frameTextureKit is the art and is deliberately not read.
function READERS.StatusBar(info, order)
    resolveEnums()
    pushBar(order,
        num(info.barMin) or 0, num(info.barMax), num(info.barValue),
        valueTextByValue[num(info.barValueTextType) or -1],
        str(info.overrideBarText), num(info.colorTint),
        str(info.tooltip), str(info.text), str(info.textureKit))
end

function READERS.DoubleStatusBar(info, order)
    resolveEnums()
    pushBar(order, num(info.leftBarMin) or 0, num(info.leftBarMax), num(info.leftBarValue),
        nil, nil, nil, str(info.leftBarTooltip), str(info.leftText))
    pushBar(order, num(info.rightBarMin) or 0, num(info.rightBarMax), num(info.rightBarValue),
        nil, nil, nil, str(info.rightBarTooltip), str(info.rightText))
end

function READERS.TextWithState(info, order)
    pushText(order, str(info.text), str(info.tooltip))
end

function READERS.TextureAndText(info, order)
    pushText(order, str(info.text), str(info.tooltip))
end

function READERS.IconAndText(info, order)
    pushText(order, str(info.text), str(info.tooltip) or str(info.dynamicTooltip))
end

function READERS.BulletTextList(info, order)
    local lines = plain(info.lines)
    if type(lines) ~= "table" then return end
    for i = 1, #lines do
        local ln = lines[i]
        pushText(order, str(ln and ln.text))
    end
end

-- Blizzard draws this as its own box: a header, a clock and a draining fill. Measured on
-- 2026-08-21 during a Curse Surge - timerValue 154, timerMin 1, timerMax 180 - and note that
-- hasTimer read FALSE on it, so that field is not the signal here. The timer values are.
--
-- headerText carried the stage name the scenario banner already draws, so it is dropped when
-- the two match rather than printing the same line twice.
function READERS.ScenarioHeaderTimer(info, order)
    local label = str(info.headerText)
    if label and stageTitle and label == stageTitle then label = nil end
    local o = pushBar(order, num(info.timerMin) or 0, num(info.timerMax),
        num(info.timerValue), "Time", nil, nil, str(info.timerTooltip), label)
    -- The server pushes this rarely, so the drawer runs the clock down between updates
    if o then o.countdown = true end
end

-- The delve tier, which has been on screen nowhere since the widget container came out and
-- which v1.9.1's changelog promised back. tierText is a bare number with no label of its own.
function READERS.ScenarioHeaderDelves(info, order)
    local tier = tonumber(plain(info.tierText))
    if tier then pushText(order, (L["Tier %d"]):format(tier)) end
end

local function refreshStageTitle()
    stageTitle = nil
    if not (C_ScenarioInfo and C_ScenarioInfo.GetScenarioStepInfo) then return end
    local ok, step = pcall(C_ScenarioInfo.GetScenarioStepInfo)
    if ok and type(step) == "table" then stageTitle = str(step.title) end
end

-- A widget that pushes more than one entry gives them all the same order, so the tie-break
-- decides a bullet list's line order and which half of a DoubleStatusBar draws first. It has
-- to be the push order and nothing else - on text, a bullet list comes out alphabetized.
local function byOrder(a, b)
    if a.order ~= b.order then return a.order < b.order end
    return a.seq < b.seq
end

function Widgets:IsAvailable()
    return (C_UIWidgetManager and C_UIWidgetManager.GetAllWidgetsBySetID) and true or false
end

function Widgets:TrackerSetID()
    if not (C_UIWidgetManager and C_UIWidgetManager.GetObjectiveTrackerWidgetSetID) then
        return nil
    end
    local ok, id = pcall(C_UIWidgetManager.GetObjectiveTrackerWidgetSetID)
    return (ok and type(id) == "number" and id ~= 0) and id or nil
end

function Widgets:ScenarioSetID()
    if not (C_ScenarioInfo and C_ScenarioInfo.GetScenarioStepInfo) then return nil end
    local ok, step = pcall(C_ScenarioInfo.GetScenarioStepInfo)
    if not (ok and type(step) == "table") then return nil end
    local id = num(step.widgetSetID)
    return (id and id ~= 0) and id or nil
end

-- Returns the shared list and its length. Valid only until the next Read, exactly as a
-- provider's entries are - the caller draws from it and keeps nothing.
function Widgets:Read(...)
    outN, skippedN = 0, 0
    if not self:IsAvailable() then return out, 0 end
    resolveEnums()
    refreshStageTitle()

    for i = 1, select("#", ...) do
        local setID = select(i, ...)
        if setID then
            local firstOut, firstSkip = outN + 1, skippedN + 1
            local ok, widgets = pcall(C_UIWidgetManager.GetAllWidgetsBySetID, setID)
            if ok and type(widgets) == "table" then
                for w = 1, #widgets do
                    local widget = widgets[w]
                    local tname  = typeByValue[widget.widgetType]
                    local info   = tname and visualizationInfo(tname, widget.widgetID)
                    if info and not isHidden(info) then
                        local reader = READERS[tname]
                        if reader then
                            reader(info, i * SET_STRIDE + (num(info.orderIndex) or 0))
                        else
                            skippedN = skippedN + 1
                            skipped[skippedN] = tname
                        end
                    end
                end
            end
            local st = stats[setID]
            if not st then st = { types = {} }; stats[setID] = st end
            st.drawn, st.nTypes = outN - firstOut + 1, 0
            for k = firstSkip, skippedN do
                st.nTypes = st.nTypes + 1
                st.types[st.nTypes] = skipped[k]
            end
        end
    end

    for i = outN + 1, #out do out[i] = nil end
    if outN > 1 then table.sort(out, byOrder) end
    return out, outN
end

-- A caller that draws nothing has to say so, or the line keeps reporting its last live read
function Widgets:Forget(setID)
    if setID then stats[setID] = nil end
end

function Widgets:DebugLine()
    if not self:IsAvailable() then return "widgets: api absent" end
    local tid, sid = self:TrackerSetID(), self:ScenarioSetID()
    for id in pairs(stats) do
        if id ~= tid and id ~= sid then stats[id] = nil end
    end

    local drawn, names, nNames = 0, {}, 0
    local function add(id)
        local st = id and stats[id]
        if not st then return end
        drawn = drawn + st.drawn
        for i = 1, st.nTypes do
            nNames = nNames + 1
            names[nNames] = st.types[i]
        end
    end
    add(tid)
    if sid ~= tid then add(sid) end

    local skips = ""
    if nNames > 0 then
        skips = " | unread types: " .. table.concat(names, ",", 1, math.min(nNames, 6))
    end
    return ("widgets: tracker set %s, scenario set %s | %d drawn%s"):format(
        tostring(tid), tostring(sid), drawn, skips)
end

local dirtyListeners = {}

function Widgets:OnDirty(fn)
    dirtyListeners[#dirtyListeners + 1] = fn
end

function Widgets:OnEnable()
    if not self:IsAvailable() then return end
    local Events = ns:GetModule("Events")

    local function fire()
        for i = 1, #dirtyListeners do
            local ok, err = pcall(dirtyListeners[i])
            if not ok then geterrorhandler()(err) end
        end
    end

    -- UPDATE_UI_WIDGET fires per widget and a busy event fires it in bursts, so it is
    -- coalesced rather than repainting the tracker once per widget.
    local function dirty()
        Events:Debounce("widgets", REFRESH_DEBOUNCE, fire)
    end

    Events:On("UPDATE_UI_WIDGET",      dirty)
    Events:On("UPDATE_ALL_UI_WIDGETS", dirty)
    Events:On("PLAYER_ENTERING_WORLD", dirty)
end
