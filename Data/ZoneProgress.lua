local _, ns = ...

local ZoneProgress = ns:RegisterModule("ZoneProgress", {})

local MAX_HOPS = 5

local _rootID, _rootName, _rootDirty = nil, nil, true
-- The map the walk STARTED from, recorded only when it actually climbed past it. The one
-- line a "my zone bar vanished" report is read from cannot otherwise say that the zone it
-- names is not the zone underfoot. Cleared on every walk, or it announces a climb that did
-- not happen on the next pass that stays put.
local _rootVia = nil

local RETRY_DELAY = 0.3
local RETRY_MAX   = 5

local function categoryByMapID(rootID)
    if not rootID then return nil end
    for id, cat in pairs(ns.ZONE_CATEGORIES or {}) do
        if cat.mapID == rootID then return id end
        local mids = cat.mapIDs
        if type(mids) == "table" then
            for i = 1, #mids do
                if mids[i] == rootID then return id end
            end
        end
    end
    return nil
end

-- Substring both ways after the exact pass, so "Eversong Woods" still matches when the
-- client hands back a decorated zone name.
local function categoryByName(name)
    if not name or name == "" then return nil end
    local lower = name:lower()
    for id, cat in pairs(ns.ZONE_CATEGORIES or {}) do
        if (cat.name or ""):lower() == lower then return id end
    end
    for id, cat in pairs(ns.ZONE_CATEGORIES or {}) do
        local cn = (cat.name or ""):lower()
        if cn ~= "" and (lower:find(cn, 1, true) or cn:find(lower, 1, true)) then
            return id
        end
    end
    return nil
end

-- Walks up to the containing Zone, so a micro-dungeon counts against the zone around it.
--
-- Midnight NESTS zones, measured 2026-09-03: Slayer's Rise (2444) is mapType Zone and so is
-- its parent Voidstorm (2405). Stopping at the first Zone therefore answered Slayer's Rise,
-- which no category names, and Voidstorm's own routed questlines drew no bar at all. So a
-- Zone that resolves to no category is passed THROUGH rather than accepted, and the first
-- Zone seen is kept as the answer for when nothing above it resolves either. Every zone that
-- works today resolves on its own hop and never climbs.
--
-- The per-hop test is the same pair Count uses, mapID AND name, and that is load-bearing:
-- Eversong Woods carries no mapID entry in either addon - the one listed is Silvermoon City -
-- so a mapID-only climb would pass it over from a sub-area inside it, answer the sub-area,
-- and draw no bar at all: the same NO ROUTING this walk was fixed for.
local function zoneRoot()
    if not _rootDirty then return _rootID, _rootName end
    if not ns.Has.Map then return nil end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID or mapID <= 0 then return nil end

    _rootDirty = false
    _rootID, _rootName, _rootVia = nil, nil, nil

    local ZONE = Enum and Enum.UIMapType and Enum.UIMapType.Zone
    local firstID, firstName

    local id = mapID
    for _ = 1, MAX_HOPS do
        local info = C_Map.GetMapInfo(id)
        if not info then break end
        if ZONE and info.mapType == ZONE then
            if not firstID then firstID, firstName = id, info.name end
            if categoryByMapID(id) or categoryByName(info.name) then
                _rootID, _rootName = id, info.name
                if firstID and firstID ~= id then _rootVia = firstID end
                break
            end
        end
        -- The top of a hierarchy answers parentMapID 0, and 0 is truthy in Lua.
        if not info.parentMapID or info.parentMapID == 0 then break end
        local pinfo = C_Map.GetMapInfo(info.parentMapID)
        -- Never climb above zone level: a continent's questlines are not this zone's, and
        -- Quel'Thalas sits one hop over Voidstorm. Same above-zone test as
        -- WorldQuests:zoneParent, which ALSO refuses to climb from a Zone - this walk must
        -- not, or the nesting above is unreachable again.
        if ZONE and pinfo and pinfo.mapType and pinfo.mapType < ZONE then break end
        id = info.parentMapID
    end

    -- No Zone above resolved either, so answer the one the old walk would have.
    if not _rootID then _rootID, _rootName = firstID, firstName end

    -- Fall back to the player's own map, as EQ does. Without this a map with no Zone
    -- ancestor latches nil until the next zone change.
    if not _rootID then
        local info = C_Map.GetMapInfo(mapID)
        _rootID, _rootName = mapID, info and info.name or nil
    end
    return _rootID, _rootName
end

local _catIndex
local function categoryQuestLines(catID)
    local routing = ns.QUESTLINE_ROUTING
    if not (routing and catID) then return nil end
    if not _catIndex then
        _catIndex = {}
        for qlID, entry in pairs(routing) do
            local c = (type(entry) == "table") and entry.cat or entry
            if c then
                local list = _catIndex[c]
                if not list then list = {}; _catIndex[c] = list end
                list[#list + 1] = qlID
            end
        end
    end
    return _catIndex[catID]
end

-- Questline contents stream in late, so a miss is retried rather than cached as empty,
-- and the store only ever grows for a given questline.
local qlQuests      = {}
local retryCount    = {}
local retryPending  = {}
-- Bumped by dirty(). A C_Timer callback cannot be canceled, so a superseded chain retires
-- itself by comparing this instead.
local retryGen      = 0

local dirtyListeners = {}

function ZoneProgress:OnDirty(fn)
    dirtyListeners[#dirtyListeners + 1] = fn
end

local function fireDirty()
    for i = 1, #dirtyListeners do
        local ok, err = pcall(dirtyListeners[i])
        if not ok then geterrorhandler()(err) end
    end
end

local _count = {}

function ZoneProgress:Invalidate()
    _count.rootID = nil
end

-- silent is passed by Count alone. Count owns _seen and is not re-entrant, and a listener
-- fired mid-walk calls straight back into it, so an inline fill must never announce itself.
-- The caller already has the filled data. Only the async retry has news worth telling.
function ZoneProgress:EnsureQuests(qlID, silent)
    if not (qlID and C_QuestLine and C_QuestLine.GetQuestLineQuests) then return end
    local quests = C_QuestLine.GetQuestLineQuests(qlID)
    if not quests or #quests == 0 then
        local n = retryCount[qlID] or 0
        if n < RETRY_MAX and not retryPending[qlID] then
            retryPending[qlID] = true
            retryCount[qlID]   = n + 1
            local gen = retryGen
            C_Timer.After(RETRY_DELAY * (n + 1), function()
                -- Without this, wiping retryPending on a zone change let a second chain arm
                -- for the same questline while the first was still in flight. They share one
                -- retryCount, so the five attempts were spent in half the wall time and the
                -- streaming window closed early. Reproduced at almost every login.
                if gen ~= retryGen then return end
                retryPending[qlID] = nil
                self:EnsureQuests(qlID)
            end)
        end
        return
    end
    retryCount[qlID] = nil
    local existing = qlQuests[qlID]
    if not existing or #quests >= #existing then
        qlQuests[qlID] = quests
        self:Invalidate()
        -- The retry is the whole point of this function, so it has to tell someone. A
        -- silent fill leaves the bar hidden or short until an unrelated event repaints it.
        if not silent then fireDirty() end
    end
end

local _seen = {}

-- Deduplicated by quest id: a quest can appear in more than one routed questline, and
-- counting it twice would inflate both halves of the bar.
function ZoneProgress:Count(rootID, rootName)
    local catID = categoryByMapID(rootID) or categoryByName(rootName)
    local lines = catID and categoryQuestLines(catID)
    if not lines then return nil, nil, catID end

    wipe(_seen)
    local total, done = 0, 0
    local flagged = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted

    for i = 1, #lines do
        local qlID = lines[i]
        local quests = qlQuests[qlID]
        if not quests then
            self:EnsureQuests(qlID, true)
            quests = qlQuests[qlID]
        end
        for j = 1, (quests and #quests or 0) do
            local qid = quests[j]
            if qid and not _seen[qid] then
                _seen[qid] = true
                total = total + 1
                if flagged and flagged(qid) then done = done + 1 end
            end
        end
    end
    return done, total, catID
end

-- Memoized because the tracker calls this once per render and Render is not throttled -
-- an appearance slider drag would otherwise re-walk every routed questline per step.
-- A fill during the walk clears the entry and the walk then overwrites it, so the stored
-- result is always a complete pass rather than a half-updated one.
function ZoneProgress:Current()
    local rootID, rootName = zoneRoot()
    if not rootID then return nil end

    if _count.rootID ~= rootID then
        local done, total, catID = self:Count(rootID, rootName)
        _count.rootID, _count.done, _count.total, _count.name, _count.catID =
            rootID, done, total, rootName, catID
    end

    if not _count.total or _count.total == 0 then return nil end
    return _count.done, _count.total, _count.name, _count.catID
end

local function viaText()
    return _rootVia and ((" via %d"):format(_rootVia)) or ""
end

function ZoneProgress:DebugLines()
    local lines = {}
    local rootID, rootName = zoneRoot()
    if not rootID then
        lines[1] = "zone progress: no zone map (instanced or no map)"
        return lines
    end

    local done, total, catID = self:Count(rootID, rootName)
    local cat = catID and ns.ZONE_CATEGORIES and ns.ZONE_CATEGORIES[catID]
    if not total then
        lines[1] = ("zone progress: %s (%d)%s -> NO ROUTING, no bar here")
            :format(rootName or "?", rootID, viaText())
        return lines
    end

    local qls = categoryQuestLines(catID) or {}
    local loaded = 0
    for i = 1, #qls do
        if qlQuests[qls[i]] then loaded = loaded + 1 end
    end

    lines[1] = ("zone progress: %s (%d)%s -> %s, %d/%d complete")
        :format(rootName or "?", rootID, viaText(),
                (cat and cat.name) or tostring(catID), done, total)
    lines[2] = ("  %d/%d routed questlines loaded"):format(loaded, #qls)
    return lines
end

-- Registered here rather than only on the bar because the count cache has to be dropped
-- before any renderer reads it, and Events dispatches in registration order - this module
-- loads ahead of every consumer in the TOC, so its handler runs first.
function ZoneProgress:OnEnable()
    local Events = ns:GetModule("Events")
    -- Clearing the retry counters matters as much as the map: a questline that exhausted
    -- its five attempts would otherwise never poll again for the rest of the session.
    local function dirty()
        _rootDirty = true
        wipe(retryCount)
        wipe(retryPending)
        retryGen = retryGen + 1
        self:Invalidate()
    end
    Events:On("ZONE_CHANGED_NEW_AREA", dirty)
    Events:On("PLAYER_ENTERING_WORLD", dirty)

    -- A turn-in moves the bar without touching the questline store, so the cache needs
    -- clearing on its own here.
    local function recount() self:Invalidate() end
    Events:On("QUEST_TURNED_IN",  recount)
    Events:On("QUEST_REMOVED",    recount)
    Events:On("QUESTLINE_UPDATE", recount)
end
