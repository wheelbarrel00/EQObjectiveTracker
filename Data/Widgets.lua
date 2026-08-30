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

local apiReads = 0

local function visualizationInfo(typeName, widgetID)
    for i = 1, #INFO_SUFFIXES do
        local fn = C_UIWidgetManager["Get" .. typeName .. INFO_SUFFIXES[i]]
        if fn then
            apiReads = apiReads + 1
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

-- setID -> { gen, n, list }. Pruned in Invalidate down to the two sets a render can ask for.
local snaps = {}

-- Handed back when there is nothing to read, so no caller is ever given the shared pool
local EMPTY = {}

-- Read runs once per set and each caller draws its own slice, so one pair of counters would
-- only ever describe whichever set ran last. Recorded per set instead, and DebugLine reports
-- the live sets only, so a finished scenario's numbers cannot linger.
local stats = {}

local function acquire(order, tooltip)
    outN = outN + 1
    local o = pool[outN]
    if not o then o = {}; pool[outN] = o end
    o.kind, o.text, o.value, o.min, o.max = nil, nil, nil, nil, nil
    o.valueTextKind, o.overrideText, o.colorTint, o.textureKit = nil, nil, nil, nil
    o.countdown, o.deadline = nil, nil
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
-- Declared here because a reader below reads it and resolveIDs refreshes it.
local stageTitle

-- The last countdown reading and the deadline it was given. A re-read is NOT a server push:
-- UPDATE_UI_WIDGET fires PER WIDGET, so a nemesis pack dying beside a delve timer invalidates
-- and re-reads the whole set, and a fresh stamp there would jump the clock BACKWARDS on screen
-- by however long the reading had been standing. Cleared when the scenario changes, because two
-- runs can push the same value and it would then be the older run's deadline.
local lastTimerValue, lastTimerMax, lastTimerDeadline

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
    -- The server pushes this rarely, so the drawer runs the clock down between updates. The
    -- deadline is stamped HERE rather than at draw time: a read is now served from a snapshot
    -- between pushes, so a repaint that re-stamped it from the frozen value would restart the
    -- clock every time the tracker repainted.
    if o then
        o.countdown = true
        if lastTimerValue ~= o.value or lastTimerMax ~= o.max then
            lastTimerValue, lastTimerMax = o.value, o.max
            lastTimerDeadline = GetTime() + (o.value or 0)
        end
        o.deadline = lastTimerDeadline
    end
end

-- The delve tier, which has been on screen nowhere since the widget container came out and
-- which v1.9.1's changelog promised back. tierText is a bare number with no label of its own.
function READERS.ScenarioHeaderDelves(info, order)
    local tier = tonumber(plain(info.tierText))
    if tier then pushText(order, (L["Tier %d"]):format(tier)) end
end

-- Everything below is served from a snapshot until something says the widgets moved. Before
-- this, every debounced repaint asked C_UIWidgetManager for the set id, then for the set, then
-- for one visualization info per widget - so a retail player standing in the open world with no
-- widgets on screen at all still made two calls on every quest event, and the widget pipeline
-- is where the open taint report lives.
--
-- This is a MITIGATION and not a proven fix. Caching did not fix the map-pin report either, and
-- the taint posture of these reads has never been measured in either direction.
--
-- Every event that invalidates below is already followed by a repaint, so a snapshot is at most
-- as stale as the render reading it. The one deliberate gap is SCENARIO_SPELL_UPDATE, which
-- repaints WITHOUT invalidating: a spell changing moves no widget set id. Widen the two together,
-- and read the note on the event list before adding to it.
local generation = 1
local idGen, trackerID, scenarioID
-- Set by whatever can MOVE a widget set id, and cleared by the render that re-reads the pair.
-- A widget ticking inside a set moves no id, so a burst leaves this alone and the filter stays
-- tight; a scenario starting or a zone change does move one, and until the next render the pair
-- still names the previous sets.
local idsStale = true

local function resolveIDs()
    if idGen == generation and not idsStale then return end
    idGen, idsStale = generation, false
    local prevScenario = scenarioID
    trackerID, scenarioID, stageTitle = nil, nil, nil

    if C_UIWidgetManager and C_UIWidgetManager.GetObjectiveTrackerWidgetSetID then
        apiReads = apiReads + 1
        local ok, id = pcall(C_UIWidgetManager.GetObjectiveTrackerWidgetSetID)
        if ok and type(id) == "number" and id ~= 0 then trackerID = id end
    end

    -- One step read per generation covers the scenario set id AND the stage title the timer
    -- reader trims against, where the two used to cost a call each per render.
    if C_ScenarioInfo and C_ScenarioInfo.GetScenarioStepInfo then
        apiReads = apiReads + 1
        local ok, step = pcall(C_ScenarioInfo.GetScenarioStepInfo)
        if ok and type(step) == "table" then
            local id = num(step.widgetSetID)
            if id and id ~= 0 then scenarioID = id end
            stageTitle = str(step.title)
        end
    end

    -- A new scenario is a new clock, and two runs can coincidentally push the same value
    if scenarioID ~= prevScenario then
        lastTimerValue, lastTimerMax, lastTimerDeadline = nil, nil, nil
    end
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
    resolveIDs()
    return trackerID
end

function Widgets:ScenarioSetID()
    resolveIDs()
    return scenarioID
end

-- The seam the events below drive, and the one a test drives by hand. Nothing else may bump
-- the generation, or a snapshot can go stale without an event having said so.
function Widgets:Invalidate()
    generation = generation + 1
    -- Only the two sets a render can ASK for are worth keeping, which holds this at two entries
    -- however many zones and scenarios a session visits. Pruning on AGE instead threw the pooled
    -- tables away on every burst of UPDATE_UI_WIDGET - it fires per widget, so a busy delve bumps
    -- the generation several times inside one debounced repaint - and that burst is precisely the
    -- case the reuse exists for.
    for id in pairs(snaps) do
        if id ~= trackerID and id ~= scenarioID then snaps[id] = nil end
    end
end

-- Copied out of the shared pool rather than handed straight back. The two callers ask for
-- different sets inside ONE render pass, so a list handed back from the pool would be rewritten
-- under the first caller by the second.
local function snapshot(setID)
    local snap = snaps[setID]
    if not snap then snap = { gen = -1, n = 0, list = {} }; snaps[setID] = snap end
    local list = snap.list
    for i = 1, outN do
        local dst = list[i]
        if not dst then dst = {}; list[i] = dst end
        for k in pairs(dst) do dst[k] = nil end
        for k, v in pairs(out[i]) do dst[k] = v end
    end
    -- Same shrink rule the pool has: a shorter read must leave no tail of a longer one behind.
    for i = outN + 1, #list do list[i] = nil end
    snap.n, snap.gen = outN, generation
    return list, outN
end

-- Returns one set's list and its length, valid until the next Invalidate. Answered without
-- touching C_UIWidgetManager at all while the snapshot is current, which is the whole point.
function Widgets:Read(setID)
    -- EMPTY rather than the shared pool: every other path here hands back a private list, and
    -- the pool still holds the previous read's entries with a non-zero length behind it.
    if not (setID and self:IsAvailable()) then return EMPTY, 0 end

    local snap = snaps[setID]
    if snap and snap.gen == generation then return snap.list, snap.n end

    outN, skippedN = 0, 0
    resolveEnums()
    -- Asked for here as well as by the callers, because the timer reader trims against
    -- stageTitle and would otherwise take whichever generation an id getter last resolved.
    resolveIDs()

    apiReads = apiReads + 1
    local ok, widgets = pcall(C_UIWidgetManager.GetAllWidgetsBySetID, setID)
    if ok and type(widgets) == "table" then
        for w = 1, #widgets do
            local widget = widgets[w]
            local tname  = typeByValue[widget.widgetType]
            local info   = tname and visualizationInfo(tname, widget.widgetID)
            if info and not isHidden(info) then
                local reader = READERS[tname]
                if reader then
                    reader(info, num(info.orderIndex) or 0)
                else
                    skippedN = skippedN + 1
                    skipped[skippedN] = tname
                end
            end
        end
    end

    local st = stats[setID]
    if not st then st = { types = {} }; stats[setID] = st end
    st.drawn, st.nTypes = outN, 0
    for k = 1, skippedN do
        st.nTypes = st.nTypes + 1
        st.types[st.nTypes] = skipped[k]
    end

    for i = outN + 1, #out do out[i] = nil end
    if outN > 1 then table.sort(out, byOrder) end
    return snapshot(setID)
end

-- A caller that draws nothing has to say so, or the line keeps reporting its last live read
function Widgets:Forget(setID)
    if setID then stats[setID], snaps[setID] = nil, nil end
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
    return ("widgets: tracker set %s, scenario set %s | %d drawn | %d api reads this session%s")
        :format(tostring(tid), tostring(sid), drawn, apiReads, skips)
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

    -- UPDATE_UI_WIDGET carries the SET its widget belongs to, and this addon reads exactly two.
    -- The payload used to be discarded, so a widget changing anywhere in the game - top center,
    -- below minimap, another addon's - rebuilt the whole feed. OnEnable returns above on a
    -- client with no C_UIWidgetManager, so Classic registers none of this at all.
    --
    -- Fail OPEN while the resolved pair is stale. Only a render resolves it, so between a
    -- scenario starting and the next render the pair still names the previous sets, and the new
    -- scenario's first widget events were refused - their Invalidate along with them.
    -- The set id goes through num() for the reason every other Blizzard read here does: a
    -- secret value reads as absent and fails open rather than raising on ==.
    -- The TYPE is tested, never the truthiness. This handler is shared with
    -- PLAYER_ENTERING_WORLD, whose first payload argument is isInitialLogin - a BOOLEAN - so
    -- `widgetInfo and widgetInfo.widgetSetID` indexes `true` on the first login of a session
    -- and raises. Zoning and a reload both pass false and were silently fine, which is what
    -- made it a once-a-session error rather than an obvious one.
    local function ours(widgetInfo)
        if type(widgetInfo) ~= "table" then return true end
        local setID = num(widgetInfo.widgetSetID)
        if not setID then return true end
        if idsStale or not (trackerID or scenarioID) then return true end
        return setID == trackerID or setID == scenarioID
    end

    -- Coalesced rather than repainting once per widget, because UPDATE_UI_WIDGET fires per
    -- widget and a busy event fires it in bursts.
    --
    -- Invalidate even when the repaint is refused, or the snapshot the next render serves is
    -- older than the widgets it describes. Only the REPAINT is switched off, never the
    -- bookkeeping that keeps the cache honest.
    local function dirty(_, widgetInfo)
        -- No widget set in the payload means "assume everything moved" - UPDATE_ALL_UI_WIDGETS
        -- and PLAYER_ENTERING_WORLD both land here - so the resolved pair stops being trusted.
        if type(widgetInfo) ~= "table" then idsStale = true end
        if not ours(widgetInfo) then return end
        self:Invalidate()
        local DB  = ns:GetModule("DB")
        local cfg = DB and DB:Tracker()
        if cfg and cfg.showTrackerWidgets == false then return end
        Events:Debounce("widgets", REFRESH_DEBOUNCE, fire)
    end

    -- These MOVE a set id rather than changing a widget inside one, so they mark the resolved
    -- pair stale as well. Invalidate alone bumps the generation and leaves the ids in place,
    -- which is right for a burst and wrong for a scenario that has just started.
    local function invalidate()
        idsStale = true
        self:Invalidate()
    end

    Events:On("UPDATE_UI_WIDGET",      dirty)
    Events:On("UPDATE_ALL_UI_WIDGETS", dirty)
    Events:On("PLAYER_ENTERING_WORLD", dirty)

    -- Invalidate only. A repaint already follows every one of these - the four scenario events
    -- through Data/ScenarioBonus.lua, ZONE_CHANGED_NEW_AREA through the quest providers - so
    -- asking for a second one here would double the render rate of a busy delve for nothing.
    --
    -- This file is listed on EVERY flavor, and Events:On RECORDS a refusal on an event the
    -- client does not know - which is a line in /eqot status. The set below is exactly what
    -- Data/ScenarioBonus.lua already registers from every flavor, so it is proven to cost no
    -- new refusal. SCENARIO_SPELL_UPDATE is deliberately NOT here: it is registered only by the
    -- retail-only Scenarios provider, and a spell changing moves no widget set id.
    Events:On("SCENARIO_UPDATE",                     invalidate)
    Events:On("SCENARIO_CRITERIA_UPDATE",            invalidate)
    Events:On("SCENARIO_CRITERIA_SHOW_STATE_UPDATE", invalidate)
    Events:On("SCENARIO_COMPLETED",                  invalidate)
    Events:On("ACTIVE_DELVE_DATA_UPDATE",            invalidate)
    Events:On("ZONE_CHANGED_NEW_AREA",               invalidate)
end
