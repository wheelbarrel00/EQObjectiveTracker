local _, ns = ...

local Entry    = ns:GetModule("Entry")
local Registry = ns:GetModule("Registry")
local L        = ns.L

local STATE, LINE, ICON = Entry.STATE, Entry.LINE, Entry.ICON

-- Midnight can hand back "secret values" that error when matched by tainted addon code,
-- even though they still report type "string"
local _issecret = _G.issecretvalue

local Scenarios = {
    id       = "scenarios",
    groups   = { "scenarios" },
    -- Declares no idSpace, so it never claims and is never blocked by one. The scenario
    -- draws in its own container, outside Sections:Order(), so this only sets build order.
    priority = 1,
    tags     = {},
}

-- Only one scenario is ever active, so the entry keeps a constant id and the store reuses
-- its table across stages instead of churning a new one on every criteria update.
local ENTRY_ID = "scenario"

local DELVE_TYPE        = 8
local MYTHIC_PLUS_TYPE  = 1
local PROVING_TYPE      = 2
local DUNGEON_TYPE      = 5
local WARFRONT_TYPE     = 7
local FOLLOWER_DUNGEON  = 205

local store = Entry.NewStore({
    groupID   = "scenarios",
    icon      = { kind = ICON.NONE },
    isTracked = true,
})

-- Reused rather than rebuilt: GetEntries runs on every render, so a fresh table here
-- would allocate on every quest event for as long as a scenario is up.
local facts  = { active = false }
local banner = {}

local function categoryLabel(scenarioType, textureKit, scenarioName, instType, diffID)
    -- Ritual Sites reuse the Delve scenarioType, so only the texture kit separates them
    if scenarioType == DELVE_TYPE then
        if textureKit and textureKit ~= "" and not textureKit:lower():find("delve") then
            return L["Ritual Site"]
        end
        return L["Delves"]
    end
    if textureKit and textureKit:lower():find("delve") then return L["Delves"] end
    if scenarioType == MYTHIC_PLUS_TYPE then return L["Mythic+"] end
    if scenarioType == DUNGEON_TYPE     then return L["Dungeon"] end
    if scenarioType == WARFRONT_TYPE    then return L["Warfront"] end
    if scenarioType == PROVING_TYPE     then return L["Proving Grounds"] end

    -- Normal dungeons also report scenarioType 3, so only difficulty 205 means Follower Dungeon
    if diffID == FOLLOWER_DUNGEON then return L["Follower Dungeon"] end

    -- Matched against the English name, so this misses on a non-English client. EQ has the
    -- same gap. The fallbacks below still produce a sensible label.
    if scenarioName then
        local n = scenarioName:lower()
        if n:find("void incursion") or n:find("void assault") then return L["Void Incursion"] end
    end

    if instType == "party" then return L["Dungeon"]      end
    if instType == "raid"  then return L["Raid"]         end
    if instType == "pvp"   then return L["Battleground"] end
    if instType == "arena" then return L["Arena"]        end

    if scenarioName and scenarioName ~= "" then return scenarioName end
    return L["Scenario"]
end

local function resolveName(scenarioName, instName, instType)
    if instName and instName ~= "" and instType and instType ~= "none" then
        return instName
    end
    if scenarioName and scenarioName ~= "" then return scenarioName end
    return nil
end

-- Unreleased steps can return an internal build string where the criteria text belongs.
-- Real criteria never open with a version number or carry a "- Step NN" marker.
local function looksInternal(s)
    if not s or s == "" then return false end
    if s:find("^%s*%d+%.%d+%.%d+") then return true end
    if s:find("%-%s*Step%s+%d+")   then return true end
    if s:find("Scenario%s+%d%d")   then return true end
    return false
end

local function readScenario()
    local name, stage, numStages, _, _, _, _, _, _, sType, _, kit = C_Scenario.GetInfo()
    return name, stage, numStages, sType, kit
end

local function readStep()
    if not C_Scenario.GetStepInfo then return nil, 0, nil end
    local stageName, _, numCriteria, _, _, _, _, _, _, _, _, widgetSetID = C_Scenario.GetStepInfo()
    return stageName, numCriteria or 0, widgetSetID
end

local function fillCriteria(e, numCriteria)
    Entry.BeginLines(e)
    local done, total = 0, 0
    for i = 1, numCriteria do
        local info = C_ScenarioInfo.GetCriteriaInfo(i)
        if info then
            local desc = info.description or ""
            if looksInternal(desc) then desc = "" end

            -- Weighted progress reports quantity as a percentage rather than a count, so
            -- the denominator is fixed at 100 rather than read from totalQuantity.
            local isWeighted = info.isWeightedProgress and true or false
            -- isFormatted means the description already carries its own count
            local hasMeter = (not info.isFormatted) and info.totalQuantity
                             and info.totalQuantity > 0

            if desc ~= "" or isWeighted or hasMeter then
                local ln = Entry.PushLine(e)
                ln.text      = desc
                ln.completed = info.completed and true or false
                if isWeighted then
                    ln.kind    = LINE.WEIGHTED
                    ln.current, ln.required = info.quantity or 0, 100
                elseif hasMeter then
                    ln.kind    = LINE.PROGRESSBAR
                    ln.current, ln.required = info.quantity or 0, info.totalQuantity
                end
                total = total + 1
                if ln.completed then done = done + 1 end
            end
        end
    end
    Entry.EndLines(e)
    return done, total
end

function Scenarios:IsAvailable()
    return ns.Has.Scenario and ns.Has.ScenarioCriteria
end

function Scenarios:GetEntries()
    store:Begin()

    local scenarioName, currentStage, numStages, scenarioType, textureKit = readScenario()
    local active = scenarioName and numStages and numStages > 0
                   and currentStage and currentStage > 0
    if not active then
        facts.active = false
        return store:Finish()
    end

    local stageName, numCriteria, widgetSetID = readStep()

    local instName, instType, diffID
    if GetInstanceInfo then instName, instType, diffID = GetInstanceInfo() end

    local category = categoryLabel(scenarioType, textureKit, scenarioName, instType, diffID)
    local name     = resolveName(scenarioName, instName, instType)

    -- The container draws the stage name on the banner and the category in its own
    -- sub-header, so the entry carries no subtitle and its title is never rendered.
    local e = store:Acquire(ENTRY_ID)
    e.title = (stageName and stageName ~= "" and stageName) or name or L["Scenario"]

    local done, total = fillCriteria(e, numCriteria)
    e.state = (total > 0 and done == total) and STATE.COMPLETE or STATE.ACTIVE

    facts.active       = true
    facts.category     = category
    facts.name         = name
    facts.stageName    = stageName
    facts.stage        = currentStage
    facts.numStages    = numStages
    facts.scenarioType = scenarioType
    facts.textureKit   = textureKit
    facts.widgetSetID  = widgetSetID
    facts.criteria     = total
    facts.instType     = instType
    facts.diffID       = diffID

    return store:Finish()
end

-- The banner is bespoke atlas art with no Entry equivalent, so the display layer reads
-- these facts through a provider method rather than through entry.payload. The theme
-- color resolves to plain numbers here - Data never hands UI a color escape.
function Scenarios:GetBanner()
    if not facts.active then return nil end

    banner.category     = facts.category
    banner.name         = facts.name
    banner.stageName    = facts.stageName
    banner.stage        = facts.stage
    banner.numStages    = facts.numStages
    banner.isFinalStage = facts.numStages > 1 and facts.stage == facts.numStages
    banner.textureKit   = facts.textureKit
    banner.widgetSetID  = facts.widgetSetID

    banner.themeR, banner.themeG, banner.themeB = nil, nil, nil
    if C_ScenarioInfo.GetDisplayInfo then
        local display = C_ScenarioInfo.GetDisplayInfo()
        if display and display.themeColor then
            banner.themeR, banner.themeG, banner.themeB = display.themeColor:GetRGB()
        end
    end
    return banner
end

function Scenarios:OnEntryTooltip(entry, tooltip)
    tooltip:AddLine(entry.title, 1, 0.82, 0)
    if not facts.active then return end
    if facts.name and facts.name ~= entry.title then
        tooltip:AddLine(facts.name, 1, 1, 1)
    end
    tooltip:AddLine(facts.category, 0.6, 0.6, 0.6)
    if facts.numStages > 1 then
        tooltip:AddLine((L["Stage %d of %d"]):format(facts.stage, facts.numStages), 0.6, 0.6, 0.6)
    end
end

local PROBE_MAX_WIDGETS = 40
local PROBE_MAX_FIELDS  = 22
local PROBE_MAX_NESTED  = 10

-- Printed first, in this order, and never truncated away. Sorting every field alphabetically
-- buried shownState and the bar values behind a StatusBar's thirty-odd layout fields, which
-- is what made the first capture unreadable.
local PROBE_FIRST = {
    "shownState", "text", "headerText", "tooltip", "dynamicTooltip",
    "barValue", "barMin", "barMax", "barValueTextType", "barTextEnabledState",
    "enabledState", "state", "hasTimer", "colorTint",
    "textureKit", "frameTextureKit", "orderIndex", "widgetTag",
}

-- Expanded one level, because this is where the content actually is: a SpellDisplay's spell,
-- an ItemDisplay's item, a row widget's entries.
local PROBE_EXPAND = {
    spellInfo = true, itemInfo = true, entries = true, buttons = true, lines = true,
}

-- Two naming conventions are in use on C_UIWidgetManager and neither covers every type, so
-- both are tried rather than kept in a table that rots the next time Blizzard adds a kind.
local INFO_SUFFIXES = { "VisualizationInfo", "WidgetVisualizationInfo" }

local function widgetTypeNames()
    local out = {}
    local VT = Enum and Enum.UIWidgetVisualizationType
    if type(VT) == "table" then
        for name, value in pairs(VT) do out[value] = name end
    end
    return out
end

local function visualizationInfo(typeName, widgetID)
    if not (typeName and C_UIWidgetManager) then return nil end
    for i = 1, #INFO_SUFFIXES do
        local fn = C_UIWidgetManager["Get" .. typeName .. INFO_SUFFIXES[i]]
        if fn then
            local ok, info = pcall(fn, widgetID)
            if ok and type(info) == "table" then return info end
        end
    end
    return nil
end

-- Midnight hands back secret values through this pipeline, which is the family the open
-- widget report lives in, so no field VALUE reaches tostring or a comparison without coming
-- through here first.
local function safeValue(v)
    if _issecret and _issecret(v) then return "<secret>" end
    local t = type(v)
    if t == "table" then
        local n = 0
        for _ in pairs(v) do n = n + 1 end
        return ("{%d}"):format(n)
    end
    local ok, s = pcall(tostring, v)
    return ok and s or "<?>"
end

-- A widget the server has registered but is not currently showing. The first capture proved
-- these are returned: top center answered 33 widgets at once, spanning content that cannot
-- all be live. Some types keep the flag on their payload table instead - a SpellDisplay
-- carries spellInfo.shownState with nothing at the top - so both are read. A type carrying
-- the flag nowhere is treated as shown.
local PROBE_NESTED_STATE = { "spellInfo", "itemInfo" }

local function widgetHidden(info)
    local v = info.shownState
    if v == nil then
        for i = 1, #PROBE_NESTED_STATE do
            local sub = info[PROBE_NESTED_STATE[i]]
            if type(sub) == "table" and sub.shownState ~= nil then
                v = sub.shownState
                break
            end
        end
    end
    if v == nil then return false end
    if _issecret and _issecret(v) then return false end
    local SS = Enum and Enum.WidgetShownState
    return v == ((SS and SS.Hidden) or 0)
end

local keyBuf, seenKey = {}, {}

local function pushField(out, indent, k, v)
    out[#out + 1] = ("%s%s = %s"):format(indent, k, safeValue(v))
end

-- Its own key list rather than the shared one, because it recurses: the inner call used to
-- wipe the outer call's buffer mid-loop, which printed "nil = nil" rows for a nested array.
local function dumpNested(out, indent, tbl)
    local keys = {}
    for k in pairs(tbl) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local shown = math.min(#keys, PROBE_MAX_NESTED)
    for i = 1, shown do
        local k = keys[i]
        local v = tbl[k]
        if type(v) == "table" then
            out[#out + 1] = ("%s%s ="):format(indent, tostring(k))
            dumpNested(out, indent .. "    ", v)
        else
            pushField(out, indent, tostring(k), v)
        end
    end
    if #keys > shown then
        out[#out + 1] = ("%s... %d more"):format(indent, #keys - shown)
    end
end

local function dumpFields(info, out)
    wipe(seenKey)
    local written = 0

    for i = 1, #PROBE_FIRST do
        local k = PROBE_FIRST[i]
        if info[k] ~= nil then
            seenKey[k] = true
            written = written + 1
            pushField(out, "        ", k, info[k])
        end
    end

    for i = #keyBuf, 1, -1 do keyBuf[i] = nil end
    for k in pairs(info) do
        if type(k) == "string" and not seenKey[k] then keyBuf[#keyBuf + 1] = k end
    end
    table.sort(keyBuf)

    local room = math.max(0, PROBE_MAX_FIELDS - written)
    local shown = math.min(#keyBuf, room)
    for i = 1, shown do
        pushField(out, "        ", keyBuf[i], info[keyBuf[i]])
    end
    if #keyBuf > shown then
        out[#out + 1] = ("        ... %d more field(s) not shown"):format(#keyBuf - shown)
    end

    for k in pairs(PROBE_EXPAND) do
        local v = info[k]
        if type(v) == "table" then
            out[#out + 1] = ("        %s ="):format(k)
            dumpNested(out, "            ", v)
        end
    end
end

local function dumpSet(out, label, setID, showAll)
    if not setID or setID == 0 then
        out[#out + 1] = ("%s: no set"):format(label)
        return
    end
    local ok, widgets = pcall(C_UIWidgetManager.GetAllWidgetsBySetID, setID)
    if not (ok and type(widgets) == "table") then
        out[#out + 1] = ("%s: set %s could not be read"):format(label, tostring(setID))
        return
    end

    local names = widgetTypeNames()
    local printed, hiddenCount, capped = 0, 0, 0
    local body = {}

    for i = 1, #widgets do
        local w     = widgets[i]
        local tname = names[w.widgetType]
        local info  = tname and visualizationInfo(tname, w.widgetID)
        local hidden = info and widgetHidden(info) or false
        if hidden and not showAll then
            hiddenCount = hiddenCount + 1
        elseif printed >= PROBE_MAX_WIDGETS then
            capped = capped + 1
        else
            printed = printed + 1
            body[#body + 1] = ("    #%d id=%s type=%s(%s)%s"):format(
                printed, tostring(w.widgetID), tostring(tname), tostring(w.widgetType),
                hidden and "  [hidden]" or "")
            if info then
                dumpFields(info, body)
            else
                body[#body + 1] = "        no visualization info"
            end
        end
    end

    out[#out + 1] = ("%s: set %s, %d widget(s), %d shown%s"):format(
        label, tostring(setID), #widgets, printed,
        hiddenCount > 0 and (", " .. hiddenCount .. " hidden (widgetprobe all)") or "")
    for i = 1, #body do out[#out + 1] = body[i] end
    if capped > 0 then
        out[#out + 1] = ("    ... %d more widget(s) over the print cap"):format(capped)
    end
end

local function setID(fnName)
    local fn = C_UIWidgetManager and C_UIWidgetManager[fnName]
    if not fn then return nil end
    local ok, id = pcall(fn)
    if ok and type(id) == "number" then return id end
    return nil
end

-- Undocumented like flavorprobe and zoneprobe: a measurement, not a feature. It answers what
-- a delve or a special event actually puts in a widget set, which is the only way to learn
-- what the stock tracker draws there and this one does not. Read only - registering a
-- UIWidgetContainer against these sets is what UI/Scenario.lua forbids.
--
-- Top center and below minimap are reported for orientation only. EQOT hides neither of those
-- frames, so Blizzard still draws them and this addon must not draw them a second time.
function Scenarios:WidgetProbeLines(showAll)
    local out = {}
    if not C_UIWidgetManager then
        out[1] = "widgetprobe: C_UIWidgetManager is absent on this client"
        return out
    end

    local stepSet
    if C_ScenarioInfo and C_ScenarioInfo.GetScenarioStepInfo then
        local ok, stepInfo = pcall(C_ScenarioInfo.GetScenarioStepInfo)
        if ok and type(stepInfo) == "table" then stepSet = stepInfo.widgetSetID end
    end

    out[#out + 1] = ("scenario active %s | %s | GetStepInfo set %s | GetScenarioStepInfo set %s%s"):format(
        tostring(facts.active), facts.active and tostring(facts.name) or "-",
        tostring(facts.active and facts.widgetSetID or nil), tostring(stepSet),
        showAll and " | showing hidden widgets too" or "")

    dumpSet(out, "scenario step",     stepSet, showAll)
    dumpSet(out, "objective tracker", setID("GetObjectiveTrackerWidgetSetID"), showAll)
    dumpSet(out, "top center",        setID("GetTopCenterWidgetSetID"), showAll)
    dumpSet(out, "below minimap",     setID("GetBelowMinimapWidgetSetID"), showAll)
    return out
end

function Scenarios:DebugLine()
    if not facts.active then return "no active scenario" end
    return ("%s | %s stage %d/%d | type %s kit %s diff %s inst %s | widgetSet %s | %d criteria"):format(
        facts.category, tostring(facts.stageName), facts.stage, facts.numStages,
        tostring(facts.scenarioType), tostring(facts.textureKit), tostring(facts.diffID),
        tostring(facts.instType), tostring(facts.widgetSetID), facts.criteria)
end

-- EQ debounces its own scenario events. Tracker:Refresh already coalesces, so a second
-- timer here would only add latency.
function Scenarios:Enable(notifyDirty)
    local Events = ns:GetModule("Events")
    Events:On("SCENARIO_UPDATE",                     notifyDirty)
    Events:On("SCENARIO_CRITERIA_UPDATE",            notifyDirty)
    Events:On("SCENARIO_SPELL_UPDATE",               notifyDirty)
    Events:On("SCENARIO_CRITERIA_SHOW_STATE_UPDATE", notifyDirty)
    Events:On("SCENARIO_COMPLETED",                  notifyDirty)
    Events:On("ACTIVE_DELVE_DATA_UPDATE",            notifyDirty)
    Events:On("PLAYER_ENTERING_WORLD",               notifyDirty)
end

Registry:Register(Scenarios)
