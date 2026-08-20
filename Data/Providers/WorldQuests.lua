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
local sourceStats = { watched = 0, autozone = 0, inzone = 0, questlog = 0,
                      wq = 0, bonus = 0, logOwned = 0 }
local currentSource
-- Values only, formatted on demand in DebugLine. GetEntries runs on the render path, so
-- building the strings here would allocate on every repaint for a line nobody has asked for.
local rawZoneList, autoListOn = 0, false
local detailN = 0
local detailID, detailKind, detailMins, detailNamed = {}, {}, {}, {}

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
    for i = 1, detailN do
        detailBuf[i] = ("%d:%s%s%s"):format(detailID[i], detailKind[i],
            detailMins[i] and ("/" .. detailMins[i] .. "m") or "",
            detailNamed[i] and "" or "/noname")
    end
    return ("sources: watched %d, zone-list %d, in-zone %d, quest log %d   map %s\n      kinds: %d real world quests, %d task/bonus, %d normal log quests (left to Quests)\n      autoList %s, raw map list %d, api IsWorldQuest=%s IsQuestWorldQuest=%s time=%s\n      candidates: %s")
        :format(sourceStats.watched, sourceStats.autozone, sourceStats.inzone,
                sourceStats.questlog, tostring(m),
                sourceStats.wq, sourceStats.bonus, sourceStats.logOwned,
                tostring(autoListOn), rawZoneList,
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

local GROUP_RESOLVE_DELAY = 1

-- C_TaskQuest.GetQuestsForPlayerByMapID was renamed to GetQuestsOnMap - try the new
-- name first, since the old one is gone on current retail.
local function taskQuestsForMap(mapID)
    if not (C_TaskQuest and mapID) then return nil end
    if C_TaskQuest.GetQuestsOnMap then return C_TaskQuest.GetQuestsOnMap(mapID) end
    if C_TaskQuest.GetQuestsForPlayerByMapID then
        return C_TaskQuest.GetQuestsForPlayerByMapID(mapID)
    end
    return nil
end

-- Walks the current map and its parents: a world quest you are standing inside is
-- often registered on a parent map rather than the one you are on.
local function addInZoneTaskQuests()
    if not ns.Has.Map then return end
    local m = C_Map.GetBestMapForUnit("player")
    for _ = 1, MAP_DEPTH do
        -- The top of a hierarchy answers parentMapID 0, and 0 is truthy in Lua - so without
        -- the second test this walked one more level and asked two APIs about map zero. The
        -- sibling site below has carried this guard all along.
        if not m or m <= 0 then break end
        local list = taskQuestsForMap(m)
        for i = 1, (list and #list or 0) do
            local q = list[i]
            local qid = q and (q.questId or q.questID)
            if qid and q.inProgress then push(qid) end
        end
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(m)
        m = info and info.parentMapID
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
-- gate, which is what makes unstarted ones appear, and deliberately no parent-map walk:
-- a zone list should be the zone, not its whole continent.
local function addZoneWorldQuests()
    local DB  = ns:GetModule("DB")
    local cfg = DB and DB:Tracker()
    autoListOn = (cfg and cfg.autoListZoneWorldQuests) and true or false
    if not autoListOn then return end
    if not ns.Has.Map then return end
    local m = C_Map.GetBestMapForUnit("player")
    if not m or m <= 0 then return end
    local list = taskQuestsForMap(m)
    rawZoneList = list and #list or 0
    for i = 1, (list and #list or 0) do
        local q   = list[i]
        local qid = q and (q.questId or q.questID)
        if qid and isWorldQuest(qid) then push(qid) end
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

-- CanCreateQuestGroup, never GetActivityIDForQuestID - the latter returns truthy for
-- ordinary world quests too, which would put the eye on every row.
local groupCache = {}
local pendingGroup, groupQueued = {}, false

local function askCanCreateGroup(questID)
    if QuestUtil and QuestUtil.CanCreateQuestGroup then
        return QuestUtil.CanCreateQuestGroup(questID) and true or false
    end
    if C_LFGList and C_LFGList.CanCreateQuestGroup then
        return C_LFGList.CanCreateQuestGroup(questID) and true or false
    end
    return false
end

-- Resolved on a TIMER, never inside a render pass, and do not "simplify" it back.
-- Asking QuestUtil.CanCreateQuestGroup from inside the render taints the execution context,
-- and opening the world map in combat then blocks protected mouse calls on Blizzard's map POI
-- pins - ADDON_ACTION_BLOCKED on SetPassThroughButtons and SetPropagateMouseClicks, blamed on
-- EQOT. Bisected over eight rounds on 2026-07-31: the call is at fault and the eye button is
-- not, and caching to one call per quest still blocked, so volume is not the axis either. WHY
-- the timer helps was never proven - a timer callback is still insecure execution, so it may
-- have changed when the taint lands rather than whether it lands. The bisection is the evidence
-- here, so treat any explanation of it as a guess and do not move the call back on the strength
-- of one. Draining from a fresh timer is verified clean.
local function drainGroupQueue()
    groupQueued = false
    local changed = false
    for qid in pairs(pendingGroup) do
        pendingGroup[qid] = nil
        groupCache[qid] = askCanCreateGroup(qid)
        changed = true
    end
    if changed and WorldQuests._notifyDirty then WorldQuests._notifyDirty() end
end

-- A quest is eyeless for one tick the first time it appears, which is invisible in practice
local function canCreateGroup(questID)
    local cached = groupCache[questID]
    if cached ~= nil then return cached end

    pendingGroup[questID] = true
    if not groupQueued then
        groupQueued = true
        C_Timer.After(GROUP_RESOLVE_DELAY, drainGroupQueue)
    end
    return false
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
        if o.type == "progressbar" then ln.kind = LINE.PROGRESSBAR end
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
    sourceStats.watched, sourceStats.inzone, sourceStats.questlog = 0, 0, 0
    sourceStats.autozone = 0
    sourceStats.wq, sourceStats.bonus, sourceStats.logOwned = 0, 0, 0
    rawZoneList = 0
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
            detailNamed[detailN] = name and true or false
        end

        -- A watched entry with no time left is an expired ghost. Liveness cannot come
        -- from IsWorldQuest: that stays true forever once a quest has been one.
        local expired = watched[qid] and not (mins and mins > 0)

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
    -- describes from surviving the expiry path.
    for qid in pairs(atlasCache) do
        if not store:Get(qid) then atlasCache[qid] = nil end
    end
    for qid in pairs(groupCache) do
        if not store:Get(qid) then groupCache[qid] = nil end
    end

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
    if LFGListUtil_FindQuestGroup then LFGListUtil_FindQuestGroup(entry.id) end
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
            local manual = Enum and Enum.QuestWatchType and Enum.QuestWatchType.Manual
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
            groupCache[questID] = nil
        end
        notifyDirty()
    end

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
