local _, ns = ...

local Entry    = ns:GetModule("Entry")
local Registry = ns:GetModule("Registry")
local L        = ns.L

local STATE, LINE, ICON = Entry.STATE, Entry.LINE, Entry.ICON

local WorldQuests = {
    id       = "worldquests",
    groups   = { "worldquests" },
    -- Ahead of the quests provider on purpose. A world quest you are standing inside is
    -- also in the quest log, so both providers emit it - and in EQ a world quest always
    -- belongs to its own section, never to Quests. Claiming first is what guarantees
    -- that, regardless of the quest section's filter settings.
    priority = 5,
    idSpace  = "quest",
    tags     = { "worldquest", "bonus" },
    filterCategories = true,
}

local FALLBACK_ATLAS = "Worldquest-icon"
local MAP_DEPTH      = 5

local store = Entry.NewStore({
    groupID   = "worldquests",
    icon      = { kind = ICON.WORLDQUEST },
    tags      = {},
    isTracked = true,
})

local candidates, seen, watched = {}, {}, {}
-- Marked for every id a map list carries, INCLUDING one that push has already seen, because
-- this answers "is it still out there" rather than "who found it first".
local onMap = {}
local sourceStats = { watched = 0, autozone = 0, inzone = 0, questlog = 0,
                      wq = 0, bonus = 0, logOwned = 0 }
local currentSource
-- Values only, formatted on demand in DebugLine. GetEntries runs on the render path, so
-- building the strings here would allocate on every repaint for a line nobody has asked for.
local rawZoneList, autoListOn = 0, false
-- Whether any map list came back this pass at all. A cold client answers nil for every map,
-- which is not the same answer as a map that legitimately carries nothing.
local mapListRead = false
-- The map the zone list was actually read from, which is not the map underfoot whenever
-- the zone-list walk below climbed out of a sub-area. On the one line a "my world quests are wrong"
-- report is read from, that difference is the whole answer.
local zoneListMap, zoneListClimbed = nil, false
local detailN = 0
local detailID, detailKind, detailMins, detailNamed = {}, {}, {}, {}
local detailLive = {}

local function push(qid)
    if qid and not seen[qid] then
        seen[qid] = true
        candidates[#candidates + 1] = qid
        if currentSource then sourceStats[currentSource] = sourceStats[currentSource] + 1 end
    end
end

local detailBuf = {}

function WorldQuests:DebugLine()
    local m = ns.Has.Map and C_Map.GetBestMapForUnit("player")
    -- Named rather than counted: a watched quest kept because nothing could answer for it
    -- reads /blind below, and this says which of the two reasons applied.
    local liveness = (not mapListRead) and "blind, no map list read"
                     or (IsInInstance and (IsInInstance())) and "blind, in an instance"
                     or "readable"
    for i = 1, detailN do
        detailBuf[i] = ("%d:%s%s%s%s"):format(detailID[i], detailKind[i],
            detailMins[i] and ("/" .. detailMins[i] .. "m") or "",
            detailLive[i] or "",
            detailNamed[i] and "" or "/noname")
    end
    return ("sources: watched %d, zone-list %d, in-zone %d, quest log %d   map %s\n      kinds: %d real world quests, %d task/bonus, %d normal log quests (left to Quests)\n      autoList %s, list map %s%s, raw map list %d, liveness %s, api IsWorldQuest=%s IsQuestWorldQuest=%s time=%s\n      candidates: %s")
        :format(sourceStats.watched, sourceStats.autozone, sourceStats.inzone,
                sourceStats.questlog, tostring(m),
                sourceStats.wq, sourceStats.bonus, sourceStats.logOwned,
                tostring(autoListOn), tostring(zoneListMap),
                zoneListClimbed and " (climbed)" or "", rawZoneList, liveness,
                tostring(C_QuestLog.IsWorldQuest ~= nil),
                tostring(QuestUtils_IsQuestWorldQuest ~= nil),
                tostring(ns.Has.WorldQuestTime and true or false),
                detailN > 0 and table.concat(detailBuf, "  ", 1, detailN) or "none")
end

local function addWatched()
    wipe(watched)
    if not ns.Has.WorldQuests then return end
    for i = 1, (C_QuestLog.GetNumWorldQuestWatches() or 0) do
        local qid = C_QuestLog.GetQuestIDForWorldQuestWatchIndex(i)
        if qid then
            watched[qid] = true
            push(qid)
        end
    end
end

-- C_TaskQuest.GetQuestsForPlayerByMapID was renamed to GetQuestsOnMap - try the new
-- name first, since the old one is gone on current retail.
-- Both walks read through here, so the readable flag is set here and a third one cannot forget.
local function taskQuestsForMap(mapID)
    if not (C_TaskQuest and mapID) then return nil end
    local list
    if C_TaskQuest.GetQuestsOnMap then
        list = C_TaskQuest.GetQuestsOnMap(mapID)
    elseif C_TaskQuest.GetQuestsForPlayerByMapID then
        list = C_TaskQuest.GetQuestsForPlayerByMapID(mapID)
    end
    if list then mapListRead = true end
    return list
end

-- The bound both walks below need, and it is the one Quests:currentZoneSet already uses.
-- A continent answers with every in-progress task quest on it, so the climb stops at the
-- first Zone and refuses a parent above zone level - a chain that skips Zone entirely does
-- exist, and Data/ZoneProgress.lua names three. Returns nil when there is nowhere to go.
local function zoneParent(mapID)
    if not (C_Map.GetMapInfo and mapID and mapID > 0) then return nil end
    local ZONE = Enum and Enum.UIMapType and Enum.UIMapType.Zone
    local info = C_Map.GetMapInfo(mapID)
    if not info or info.mapType == ZONE then return nil end
    -- The top of a hierarchy answers parentMapID 0, and 0 is truthy in Lua.
    local parent = info.parentMapID
    if not parent or parent <= 0 then return nil end
    local pinfo = C_Map.GetMapInfo(parent)
    if ZONE and pinfo and pinfo.mapType and pinfo.mapType < ZONE then return nil end
    return parent
end

-- Walks the current map and its parents: a world quest you are standing inside is often
-- registered on a parent map rather than the one you are on. Bounded by hop count alone this
-- reached a continent within two hops on a Midnight zone, and a continent's list is every
-- in-progress task quest on it, which is how quests from a zone the player had left kept
-- refilling this section. zoneParent bounds it by map TYPE, which is the half that was missing.
local function addInZoneTaskQuests()
    if not ns.Has.Map then return end
    local m = C_Map.GetBestMapForUnit("player")
    for _ = 1, MAP_DEPTH do
        if not m or m <= 0 then break end
        local list = taskQuestsForMap(m)
        for i = 1, (list and #list or 0) do
            local q = list[i]
            local qid = q and (q.questId or q.questID)
            if qid then
                onMap[qid] = true
                if q.inProgress then push(qid) end
            end
        end
        m = zoneParent(m)
    end
end

local function addQuestLogTaskQuests()
    if not ns.Has.QuestLog then return end
    for i = 1, (C_QuestLog.GetNumQuestLogEntries() or 0) do
        local info = C_QuestLog.GetInfo(i)
        if info and info.questID and not info.isHeader and not info.isHidden then
            if info.isTask or info.isBounty
               or (QuestUtils_IsQuestWorldQuest and QuestUtils_IsQuestWorldQuest(info.questID)) then
                push(info.questID)
            end
        end
    end
end

local function isWorldQuest(qid)
    if C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(qid) then return true end
    if QuestUtils_IsQuestWorldQuest and QuestUtils_IsQuestWorldQuest(qid) then return true end
    return false
end

-- Lists every world quest on the map you are standing in, watched or not. No inProgress
-- gate, which is what makes unstarted ones appear.
--
-- The climb runs ONLY when the map underfoot answers an EMPTY list, so a map that already
-- lists something is never second-guessed. A sub-area - a cave, a building, an island's own
-- map - answers empty while the zone's world quests sit one level up, which is what left
-- this section blank while the player stood inside a quest area. zoneParent is what keeps it
-- from reaching a continent.
--
-- An unreadable answer climbs as well as an empty one. This list is added to, never filtered
-- against, so there is no fail-open contract to hold here the way Quests:IsCurrentZone has
-- one - trying the parent can only find more, and finding nothing costs the same either way.
local function addZoneWorldQuests()
    local DB  = ns:GetModule("DB")
    local cfg = DB and DB:Tracker()
    -- Cleared before every early return, not just on the path that fills it. Left to go stale
    -- it reports a PREVIOUS pass's map on the one line a "my world quests are wrong" report is
    -- read from, which is the same trap Quests:currentZoneSet records for its zone suffix.
    zoneListMap, zoneListClimbed = nil, false
    autoListOn = (cfg and cfg.autoListZoneWorldQuests) and true or false
    if not autoListOn then return end
    if not ns.Has.Map then return end
    local m = C_Map.GetBestMapForUnit("player")
    if not m or m <= 0 then return end
    zoneListMap = m

    local list = taskQuestsForMap(m)
    for _ = 1, MAP_DEPTH do
        if list and #list > 0 then break end
        local parent = zoneParent(zoneListMap)
        if not parent then break end
        zoneListMap, zoneListClimbed = parent, true
        list = taskQuestsForMap(parent)
    end

    rawZoneList = list and #list or 0
    for i = 1, (list and #list or 0) do
        local q   = list[i]
        local qid = q and (q.questId or q.questID)
        if qid then
            onMap[qid] = true
            if isWorldQuest(qid) then push(qid) end
        end
    end
end

-- A normal, visible quest log entry belongs to the Quests section. Task and bonus
-- entries do not, even though they are in the log, and neither do world quests.
local function ownedByQuestLog(qid)
    if not C_QuestLog.GetLogIndexForQuestID then return false end
    local idx = C_QuestLog.GetLogIndexForQuestID(qid)
    if not idx then return false end
    local info = C_QuestLog.GetInfo(idx)
    if not info or info.isHidden then return false end
    return not (info.isTask or info.isBounty)
end

local function minutesLeft(questID)
    if not ns.Has.WorldQuestTime then return nil end
    return C_TaskQuest.GetQuestTimeLeftMinutes(questID)
end

-- A liveness question, not a claim. Claims must never be taken against the quest log, because
-- it answers non-nil for hidden task quests - which is exactly what makes it right here.
local function inQuestLog(questID)
    return (C_QuestLog.GetLogIndexForQuestID
            and C_QuestLog.GetLogIndexForQuestID(questID)) and true or false
end

-- All three signals below can fall silent for reasons that have nothing to do with the quest.
-- Measured 2026-08-21 inside The Ring of Glory: a watched lair quest lost all three at once and
-- the row vanished while the default tracker kept it. Whether that is the map lists answering
-- for the instance rather than the world is NOT measured, so this refuses to judge liveness
-- instead of guessing, the same nil-means-cannot-tell contract Quests:IsCurrentZone uses. A map
-- that could not be read at all is refused on the same grounds.
local function cannotTellLiveness()
    if not mapListRead then return true end
    return IsInInstance and (IsInInstance()) or false
end

-- Liveness for a WATCHED candidate, and it takes four signals rather than one. A quest still
-- on a map list or still in the quest log is live whatever its timer says. Measured on
-- 2026-08-21: quest 97128, a watched lair world quest, reported no minutes at all - not zero,
-- ABSENT - so a minutes-only test read it as an expired ghost and the row vanished while the
-- default tracker still showed it. Not every world quest expires. Measured again inside The
-- Ring of Glory, where the same quest lost the other two signals as well.
--
-- Strictly more permissive than the minutes test it replaces, so nothing that shows today can
-- stop showing. A genuine ghost, judged from a map the client could answer for, still fails.
local function stillLive(questID, mins)
    if mins and mins > 0 then return true end
    if onMap[questID] or inQuestLog(questID) then return true end
    return cannotTellLiveness()
end

-- Both quest providers feed the shared group cache, so this keeps anything EITHER of them
-- still has. Pruning against this provider's entries alone would evict every quest-log answer,
-- the quests provider would re-ask it a second later, and the eye would never settle.
local function groupCacheKeep(qid)
    return store:Get(qid) ~= nil or inQuestLog(qid)
end

local function title(questID)
    if ns.Has.TaskQuestInfo then
        local t = C_TaskQuest.GetQuestInfoByQuestID(questID)
        if t and t ~= "" then return t end
    end
    if C_QuestLog.GetTitleForQuestID then
        local t = C_QuestLog.GetTitleForQuestID(questID)
        if t and t ~= "" then return t end
    end
    return nil
end

local atlasCache = {}

-- The icon is the quest TYPE, not its reward: a pet battle, a profession, a pvp marker.
-- Only a resolved atlas is memoized - tag info streams in late, and caching the fallback
-- would freeze every row on the generic marker for the session.
local function typeAtlas(questID)
    local cached = atlasCache[questID]
    if cached then return cached end
    if not (QuestUtil and QuestUtil.GetWorldQuestAtlasInfo and ns.Has.QuestTagInfo) then
        return FALLBACK_ATLAS
    end
    local tagInfo = C_QuestLog.GetQuestTagInfo(questID)
    if not tagInfo then return FALLBACK_ATLAS end
    local atlas = QuestUtil.GetWorldQuestAtlasInfo(questID, tagInfo, false)
    if not atlas then return FALLBACK_ATLAS end
    atlasCache[questID] = atlas
    return atlas
end

-- The cache and the deferred resolve moved to Data/QuestGroups.lua when the quests provider
-- needed the same answer. The reasons not to call it from a render pass live there.
local function canCreateGroup(questID)
    return ns:GetModule("QuestGroups"):CanCreate(questID)
end

local function fillLines(e, questID, complete)
    Entry.BeginLines(e)
    local objs = ns.Has.QuestObjectives and C_QuestLog.GetQuestObjectives(questID) or nil
    for i = 1, (objs and #objs or 0) do
        local o  = objs[i]
        local ln = Entry.PushLine(e)
        ln.text      = o.text or ""
        ln.completed = o.finished and true or false
        ln.current   = o.numFulfilled
        ln.required  = o.numRequired
        -- A progressbar objective whose denominator is already 100 reports a percentage,
        -- which is what WEIGHTED means. Otherwise the real fill is in NEITHER number and
        -- has to be asked for: quest 92149 reads 0 of 1 while Blizzard draws a filling bar
        -- beside it, and the bar gate refuses a 0/1 for the good reason that it is a yes
        -- or no. Anything neither source can answer for stays the count it always was.
        if o.type == "progressbar" then
            ln.kind = (o.numRequired == 100) and LINE.WEIGHTED or LINE.PROGRESSBAR
            if ln.kind ~= LINE.WEIGHTED then
                -- Carried BESIDE current and required rather than overwriting them. The
                -- bars-off path renders those two as `cur/req`, so rewriting them turned
                -- `0/1 Camp destroyed` into `0/100 Camp destroyed` for anyone with bars
                -- switched off - and a byte-identical off switch is the property that
                -- makes it a real one.
                ln.percent = ns:GetModule("QuestProgress"):Percent(questID)
            end
        end
    end
    if (objs and #objs or 0) == 0 and complete then
        local ln = Entry.PushLine(e)
        ln.text, ln.completed = L["Ready to turn in"], true
    end
    Entry.EndLines(e)
end

function WorldQuests:IsAvailable()
    return (ns.Has.WorldQuests or ns.Has.TaskQuests) and ns.Has.QuestObjectives
end

function WorldQuests:GetEntries()
    wipe(candidates)
    wipe(seen)
    wipe(onMap)
    sourceStats.watched, sourceStats.inzone, sourceStats.questlog = 0, 0, 0
    sourceStats.autozone = 0
    sourceStats.wq, sourceStats.bonus, sourceStats.logOwned = 0, 0, 0
    rawZoneList = 0
    mapListRead = false
    detailN = 0
    currentSource = "watched";  addWatched()
    currentSource = "autozone"; addZoneWorldQuests()
    currentSource = "inzone";   addInZoneTaskQuests()
    currentSource = "questlog"; addQuestLogTaskQuests()
    currentSource = nil

    store:Begin()
    local superID = ns.Has.SuperTrack and C_SuperTrack.GetSuperTrackedQuestID() or 0

    for i = 1, #candidates do
        local qid  = candidates[i]
        local name = title(qid)
        local mins = minutesLeft(qid)
        local wq       = isWorldQuest(qid)
        -- The map API returns in-progress task-flavored content, which on some maps
        -- includes ordinary quests. Those belong to the quest section, so leave them
        -- there rather than dragging them under a World Quests header.
        local logOwned = (not wq) and ownedByQuestLog(qid) or false

        if wq then
            sourceStats.wq = sourceStats.wq + 1
        elseif logOwned then
            sourceStats.logOwned = sourceStats.logOwned + 1
        else
            sourceStats.bonus = sourceStats.bonus + 1
        end

        if detailN < 10 then
            detailN = detailN + 1
            detailID[detailN]    = qid
            detailKind[detailN]  = wq and "wq" or (logOwned and "log" or "bonus")
            detailMins[detailN]  = mins
            -- Which signal vouched for the candidate, which a bare count could never say
            detailLive[detailN]  = onMap[qid] and "/map"
                                   or inQuestLog(qid) and "/log"
                                   or (watched[qid] and not (mins and mins > 0))
                                      and (cannotTellLiveness() and "/blind" or "/ghost")
                                   or nil
            detailNamed[detailN] = name and true or false
        end

        -- A watched entry nothing vouches for any more is an expired ghost. Liveness cannot
        -- come from IsWorldQuest: that stays true forever once a quest has been one.
        local expired = watched[qid] and not stillLive(qid, mins)

        if name and not expired and not logOwned then
            local complete = ns.Has.QuestIsComplete and C_QuestLog.IsComplete(qid) or false
            local e = store:Acquire(qid)
            e.title     = name
            e.state     = complete and STATE.COMPLETE or STATE.ACTIVE
            e.expiresAt = (mins and mins > 0) and (time() + mins * 60) or nil

            wipe(e.tags)
            if wq then e.tags.worldquest = true else e.tags.bonus = true end

            e.icon.atlas = typeAtlas(qid)
            e.canGroup   = canCreateGroup(qid)
            e.isFocused  = (superID == qid)

            fillLines(e, qid, complete)
        end
    end

    local out = store:Finish()

    -- Turn-in and removal miss the way most world quests actually end, which is expiring,
    -- and auto-list-zone memoizes every quest flown past whether or not it is ever accepted.
    -- Pruning against the live set also keeps the recycled-ID hazard the drop handler
    -- describes from surviving the expiry path. Both caches need it for the same reason.
    for qid in pairs(atlasCache) do
        if not store:Get(qid) then atlasCache[qid] = nil end
    end
    ns:GetModule("QuestGroups"):PruneExcept(groupCacheKeep)

    return out
end

function WorldQuests:OnEntryClick(entry, button)
    if button == "RightButton" then
        if ns.Has.WorldQuestWatchAPI then C_QuestLog.RemoveWorldQuestWatch(entry.id) end
        return
    end
    if ns.Has.SuperTrack then
        C_SuperTrack.SetSuperTrackedQuestID(entry.id)
        if self._notifyDirty then self._notifyDirty() end
    end
end

function WorldQuests:OnEntryGroupFinder(entry)
    ns:GetModule("QuestGroups"):Find(entry.id)
end

local menuOut = {}

-- Shorter than the quest menu because a world quest has no log entry to pin, pop out or
-- abandon - which is exactly the set EQ offers on its own world quest rows.
function WorldQuests:GetEntryMenu(entry)
    local id = entry.id
    local tracked = ns.Has.WorldQuests and C_QuestLog.GetQuestWatchType
                    and C_QuestLog.GetQuestWatchType(id) ~= nil

    for i = #menuOut, 1, -1 do menuOut[i] = nil end
    menuOut[#menuOut + 1] = { kind = "title", text = entry.title, order = 0 }
    menuOut[#menuOut + 1] = { id = tracked and "untrack" or "track", order = 10 }
    menuOut[#menuOut + 1] = { id = "supertrack", order = 20 }
    menuOut[#menuOut + 1] = { id = "wowhead",    order = 30 }
    return menuOut
end

function WorldQuests:OnEntryMenuSelect(entryID, itemID)
    if itemID == "track" then
        -- Manual, not the proximity auto-watch: only a manual watch is mirrored into the
        -- saved list, so an automatic one would not survive a reload.
        if ns.Has.WorldQuestWatchAdd then
            -- Literal 1 from Data/WatchPersist.lua: a nil type IS the automatic watch refused above.
            local manual = (Enum and Enum.QuestWatchType and Enum.QuestWatchType.Manual) or 1
            C_QuestLog.AddWorldQuestWatch(entryID, manual)
        end
    elseif itemID == "untrack" then
        if ns.Has.WorldQuestWatchAPI then C_QuestLog.RemoveWorldQuestWatch(entryID) end
    elseif itemID == "supertrack" then
        if ns.Has.SuperTrack then C_SuperTrack.SetSuperTrackedQuestID(entryID) end
    end
    if self._notifyDirty then self._notifyDirty() end
end

function WorldQuests:Enable(notifyDirty)
    local Events = ns:GetModule("Events")

    -- Quest IDs get recycled, so drop the atlas or the next quest under that ID
    -- inherits this one's icon
    local function drop(_, questID)
        if questID then
            atlasCache[questID] = nil
            ns:GetModule("QuestGroups"):Forget(questID)
        end
        notifyDirty()
    end

    -- The resolve lands a second after the render that asked for it, so without this the eye
    -- never reaches the screen until some unrelated quest event happens by.
    ns:GetModule("QuestGroups"):OnResolved(notifyDirty)

    Events:On("QUEST_TURNED_IN",           drop)
    Events:On("QUEST_REMOVED",             drop)
    Events:On("QUEST_WATCH_LIST_CHANGED",  notifyDirty)
    Events:On("QUEST_LOG_UPDATE",          notifyDirty)
    Events:On("SUPER_TRACKING_CHANGED",    notifyDirty)
    Events:On("TASK_PROGRESS_UPDATE",      notifyDirty)
    Events:On("QUEST_ACCEPTED",            notifyDirty)
    Events:On("ZONE_CHANGED_NEW_AREA",     notifyDirty)
    Events:On("PLAYER_ENTERING_WORLD",     notifyDirty)
    -- Re-read once a fight ends. Combat is where the tracker is most often hidden by a
    -- visibility rule and where renders are skipped, so the map lists are most likely stale
    -- exactly then.
    Events:On("PLAYER_REGEN_ENABLED",      notifyDirty)
end

Registry:Register(WorldQuests)
