local _, ns = ...

local Entry      = ns:GetModule("Entry")
local Registry   = ns:GetModule("Registry")
local QuestItems = ns:GetModule("QuestItems")
local QuestGroups = ns:GetModule("QuestGroups")

local STATE, LINE, ICON = Entry.STATE, Entry.LINE, Entry.ICON

local Quests = {
    id       = "quests",
    groups   = { "campaign", "quests" },
    priority = 10,
    idSpace  = "quest",
    tags     = { "campaign", "daily", "weekly", "scheduled", "dungeon", "raid", "legendary",
                 "worldquest" },
    filterCategories = true,
}

-- Compared against info.frequency from C_QuestLog.GetInfo, which is Enum.QuestFrequency, so the
-- fallbacks are the ENUM values read off a live dump: Default 0, Daily 1, Weekly 2. They used to
-- read 2 and 3, which is the LEGACY numbering the flat GetQuestLogTitle uses - correct in
-- QuestsClassic.lua, wrong here, and dead code either way while the enum is present.
local DAILY_FREQ  = (Enum and Enum.QuestFrequency and Enum.QuestFrequency.Daily)  or 1
local WEEKLY_FREQ = (Enum and Enum.QuestFrequency and Enum.QuestFrequency.Weekly) or 2

-- The fourth member, read off a 12.1 dump as 3. It carries Special Assignments and the
-- Midnight meta quest, which had no tag at all and so filtered as normal quests.
local SCHED_FREQ  = (Enum and Enum.QuestFrequency and Enum.QuestFrequency.ResetByScheduler) or 3

-- Fallback ids read off Enum.QuestTag on 1.15.9: Dungeon 81, Raid 62, Raid10 88, Raid25 89.
-- Raid10 used to read 85, which is Heroic, and Raid25 used to read 88, which is Raid10.
local TAG_DUNGEON = (Enum and Enum.QuestTag and Enum.QuestTag.Dungeon) or 81
local TAG_RAID    = (Enum and Enum.QuestTag and Enum.QuestTag.Raid)    or 62
local TAG_RAID10  = (Enum and Enum.QuestTag and Enum.QuestTag.Raid10)  or 88
local TAG_RAID25  = (Enum and Enum.QuestTag and Enum.QuestTag.Raid25)  or 89

local CLASS_LEGENDARY = Enum and Enum.QuestClassification and Enum.QuestClassification.Legendary

local store = Entry.NewStore({
    groupID = "quests",
    icon    = { kind = ICON.QUESTPOI },
    tags    = {},
})

-- Persisted per character. A session-local table stamped every quest that predated the
-- session with the 0 baseline, so after a reload the whole log tied at 0 and the Recent
-- sort fell through to alphabetical. Deliberately not in DB.defaults: it is created on
-- first use and pruned to the live log below.
local sessionSeen = {}
local function stamps()
    local DB   = ns:GetModule("DB")
    local char = DB and DB:Char()
    if not char then return sessionSeen end
    if type(char.questFirstSeen) ~= "table" then char.questFirstSeen = {} end
    return char.questFirstSeen
end

-- Its own counter rather than sharing one with any other prune: two prunes spending the same
-- strikes would reach the limit in half the passes.
local SEEN_STRIKES = 3
local seenMisses   = {}

local dirtyAll        = true
local dirtyObjectives = false

-- A cold login can present an empty quest log, so stay on full rebuild until one
-- succeeds. The cheap refresh only touches quests that are already cached.
local primed    = false
local baselined = false

local tagIDCache   = {}
local objTextCache = {}

local function getTagID(id)
    local cached = tagIDCache[id]
    if cached then return cached end
    if not ns.Has.QuestTagInfo then return nil end
    local info  = C_QuestLog.GetQuestTagInfo(id)
    local tagID = info and info.tagID
    -- Memoize hits only - a miss can mean static data has not streamed in yet
    if tagID then tagIDCache[id] = tagID end
    return tagID
end

local function getClassification(id)
    if C_QuestInfoSystem and C_QuestInfoSystem.GetQuestClassification then
        return C_QuestInfoSystem.GetQuestClassification(id)
    end
    if C_QuestLog.GetQuestClassification then
        return C_QuestLog.GetQuestClassification(id)
    end
    return nil
end

local function isCampaign(id, info)
    if ns.Has.CampaignInfo then
        local cid = C_CampaignInfo.GetCampaignID(id)
        if cid and cid > 0 then return true end
    end
    return (info and info.campaignID and info.campaignID > 0) and true or false
end

local function getFallbackText(id)
    local cached = objTextCache[id]
    if cached ~= nil then return cached end
    local text = ""
    if C_QuestLog.SetSelectedQuest and GetQuestLogQuestText then
        local saved = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
        C_QuestLog.SetSelectedQuest(id)
        local _, objText = GetQuestLogQuestText()
        text = objText or ""
        -- Restored unconditionally: GetSelectedQuest answers 0 when nothing is selected, and
        -- skipping the restore there leaves Blizzard's quest log opening on whichever quest
        -- this happened to probe last. Gated on the getter existing, or a flavor that has
        -- only the setter would clear a selection it could never have read.
        if C_QuestLog.GetSelectedQuest then C_QuestLog.SetSelectedQuest(saved or 0) end
    end
    -- Never memoize "" - the text may simply not have streamed in yet
    if text ~= "" then objTextCache[id] = text end
    return text
end

local function questState(id)
    if ns.Has.QuestIsFailed and C_QuestLog.IsFailed(id) then return STATE.FAILED end
    if ns.Has.QuestIsComplete and C_QuestLog.IsComplete(id) then return STATE.COMPLETE end
    return STATE.ACTIVE
end

local function fillLines(e, id)
    Entry.BeginLines(e)
    local objs = ns.Has.QuestObjectives and C_QuestLog.GetQuestObjectives(id) or nil
    local n    = objs and #objs or 0

    if n == 0 then
        local fb = getFallbackText(id)
        if fb ~= "" then
            local ln = Entry.PushLine(e)
            ln.text      = fb
            ln.completed = (e.state == STATE.COMPLETE)
        end
    else
        for i = 1, n do
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
                    ln.percent = ns:GetModule("QuestProgress"):Percent(id)
                end
            end
        end
    end

    Entry.EndLines(e)
end

-- A world quest can sit in the quest log and therefore render in a quest section.
-- EQ's Filters.lua checks this before every other category, so tag it the same way or
-- the World quests toggle would silently miss them.
local function isWorldQuest(id)
    if C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(id) then return true end
    if QuestUtils_IsQuestWorldQuest and QuestUtils_IsQuestWorldQuest(id) then return true end
    return false
end

local function fillTags(e, id, info)
    local tags = e.tags
    wipe(tags)
    if isWorldQuest(id) then tags.worldquest = true end
    if isCampaign(id, info) then tags.campaign = true end
    -- Kept as the raw enum alongside the tags for the diagnostic dump. Nothing sorts or
    -- filters on it: the two flavors number this field differently.
    e.frequency = (info and info.frequency) or 0
    if info then
        if info.frequency == DAILY_FREQ  then tags.daily     = true end
        if info.frequency == WEEKLY_FREQ then tags.weekly    = true end
        if info.frequency == SCHED_FREQ  then tags.scheduled = true end
    end
    local tagID = getTagID(id)
    if tagID == TAG_DUNGEON then
        tags.dungeon = true
    elseif tagID == TAG_RAID or tagID == TAG_RAID10 or tagID == TAG_RAID25 then
        tags.raid = true
    end
    if CLASS_LEGENDARY and e.icon.classification == CLASS_LEGENDARY then tags.legendary = true end
end

local function superTrackedID()
    if not (ns.Has.SuperTrack and C_SuperTrack.GetSuperTrackedQuestID) then return nil end
    return C_SuperTrack.GetSuperTrackedQuestID()
end

local function isWatched(id)
    return (ns.Has.QuestWatchType and C_QuestLog.GetQuestWatchType(id) ~= nil) and true or false
end

local zoneSet   = {}
local zoneMapID = nil
local zoneDirty = true
-- The map the set was filled from. Differs from zoneMapID only when the walk below climbed.
local zoneRootID = nil

local MAX_HOPS = 5

local function fillZoneSet(list)
    if not (list and #list > 0) then return false end
    for i = 1, #list do
        local q = list[i]
        if q and q.questID then zoneSet[q.questID] = true end
    end
    return true
end

-- The parent walk runs ONLY when the map underfoot has no quests of its own, so a map that
-- already shows something can never change. A sub-area answers an empty list while its quests
-- sit on the zone above it - measured in Revendreth, where map 1699 answered an empty list
-- with the player's only quest on 1525 - which hid that quest outright. Stops at the first Zone, and
-- refuses a parent above zone level, so it reaches the zone around a sanctum or a dungeon.
local function currentZoneSet()
    if not (ns.Has.QuestsOnMap and ns.Has.Map) then return nil end
    local map = C_Map.GetBestMapForUnit("player")
    if not map or map <= 0 then return nil end
    if not zoneDirty and map == zoneMapID then return zoneSet end
    local list = C_QuestLog.GetQuestsOnMap(map)
    if not list then return nil end

    wipe(zoneSet)
    zoneRootID = map
    if not fillZoneSet(list) then
        local ZONE = Enum and Enum.UIMapType and Enum.UIMapType.Zone
        local id   = map
        for _ = 1, MAX_HOPS do
            local info = C_Map.GetMapInfo and C_Map.GetMapInfo(id)
            if not info or info.mapType == ZONE then break end
            -- The top of a hierarchy answers 0, and 0 is truthy in Lua.
            local parent = info.parentMapID
            if not parent or parent <= 0 then break end
            -- Refusing a parent ABOVE zone level is what actually bounds this. Breaking on a
            -- Zone underfoot only stops the climb once one is reached, and a chain that skips
            -- Zone entirely does exist - Data/ZoneProgress.lua names three - so without this
            -- the set could be filled from a continent, which is every quest on it.
            local pinfo = C_Map.GetMapInfo and C_Map.GetMapInfo(parent)
            if ZONE and pinfo and pinfo.mapType and pinfo.mapType < ZONE then break end
            id = parent
            if fillZoneSet(C_QuestLog.GetQuestsOnMap(id)) then
                zoneRootID = id
                break
            end
        end
    end
    zoneMapID, zoneDirty = map, false
    return zoneSet
end

-- Zone membership comes from map POIs. Quest-log headers are campaign groupings that rarely
-- equal GetZoneText(), so comparing those would hide almost everything. nil means "cannot
-- tell" and the filter fails open on it. Absent from the map counts as elsewhere.
--
-- That last part replaces a fallback answering false only for a quest GetNextWaypoint could
-- place, which on a 16 quest log in The Coiled Isle rejected 2 and showed 14 that were not in
-- the zone - 7 resolving to another map, 7 with no position anywhere. GetInfo's own isOnMap
-- picked the same 2 quests as GetQuestsOnMap there, so it is not a second opinion to fall back
-- to. Read /eqot zoneprobe before changing this.
function Quests:IsCurrentZone(entry)
    local set = currentZoneSet()
    if not set then return nil end
    return set[entry.id] == true
end

-- Unlike 1.15.9, this bound is safe: on retail the count read 50 with every quest log header
-- collapsed and the walk still found all 15 quests.
local walkEntries, walkQuests = 0, 0

local function fullRebuild()
    local firstSeen = stamps()
    local focused = superTrackedID()
    local currentHeader
    store:Begin()

    walkEntries, walkQuests = C_QuestLog.GetNumQuestLogEntries() or 0, 0

    for i = 1, walkEntries do
        local info = C_QuestLog.GetInfo(i)
        if info then
            if info.isHeader then
                currentHeader = info.title
            elseif not info.isHidden then
                walkQuests = walkQuests + 1
                local id = info.questID
                local fs = firstSeen[id]
                if not fs then
                    fs = baselined and time() or 0
                    firstSeen[id] = fs
                end

                local e = store:Acquire(id)
                e.title     = info.title or ("Quest #" .. tostring(id))
                e.subtitle  = currentHeader
                e.zone      = currentHeader
                e.level     = info.level
                e.addedAt   = fs
                e.state     = questState(id)
                e.isFocused = (focused == id)
                e.isTracked = isWatched(id)
                e.icon.classification = getClassification(id)
                e.hasItem   = QuestItems:Has(id)
                -- Blizzard puts the group-finder eye on any quest that can form a group, not
                -- only on world quests. This provider not setting it is why a dungeon or an
                -- elite quest in the ordinary Quests section never showed one.
                e.canGroup  = QuestGroups:CanCreate(id)
                fillTags(e, id, info)
                e.groupID = e.tags.campaign and "campaign" or "quests"
                fillLines(e, id)
            end
        end
    end

    store:Finish()

    -- Pruned only against a log that actually returned something. A cold login can present
    -- an empty one, and pruning against that would drop every persisted stamp. That test is
    -- one-sided though: a walk that returned SOME quests still says nothing about the ones
    -- that have not streamed in, and they look identical to quests that are gone. So absence
    -- has to repeat, the same way TrackedSet's prune already handles the same hazard.
    if next(store:Out()) ~= nil then
        for id in pairs(firstSeen) do
            if store:Get(id) then
                seenMisses[id] = nil
            else
                local n = (seenMisses[id] or 0) + 1
                if n >= SEEN_STRIKES then
                    seenMisses[id] = nil
                    firstSeen[id], tagIDCache[id], objTextCache[id] = nil, nil, nil
                else
                    seenMisses[id] = n
                end
            end
        end
        primed    = true
        baselined = true
    end
    dirtyAll        = false
    dirtyObjectives = false
end

local function refreshDynamic()
    local focused = superTrackedID()
    for id, e in store:Each() do
        e.isTracked = isWatched(id)
        e.isFocused = (focused == id)
        e.state     = questState(id)
        -- Refreshed on the cheap path too. A quest's special item arrives after the
        -- quest does, so caching it only on full rebuild leaves the gutter missing.
        e.hasItem   = QuestItems:Has(id)
        -- Same reason, and deliberately not memoized: a classification read while static
        -- data is still streaming can come back wrong, and caching the hit would pin the
        -- wrong POI shape until the next full rebuild.
        e.icon.classification = getClassification(id)
        -- Cached and resolved off a timer inside QuestGroups, so this is a table read
        e.canGroup  = QuestGroups:CanCreate(id)
        -- fillTags needs GetInfo and so only runs on a full rebuild. The one tag derived from
        -- classification is re-derived here, or a late-arriving Legendary repaints the POI
        -- icon while the card stays tinted as an ordinary quest.
        e.tags.legendary = (CLASS_LEGENDARY and e.icon.classification == CLASS_LEGENDARY)
                           or nil
        fillLines(e, id)
    end
    dirtyObjectives = false
end

function Quests:IsAvailable()
    return ns.Has.QuestLog
end

function Quests:GetEntries()
    if dirtyAll then
        fullRebuild()
    elseif dirtyObjectives then
        refreshDynamic()
    end
    return store:Out()
end

function Quests:DebugLine()
    local QC    = (Enum and Enum.QuestClassification) or {}
    local parts = {}
    for id, e in store:Each() do
        parts[#parts + 1] = ("%d=%s%s"):format(
            id, tostring(e.icon.classification), e.isFocused and "*" or "")
    end
    table.sort(parts)

    -- Cached against live, separately, because one number cannot tell a stale cache from a
    -- watch list that really is empty. The cached answer is what the rows were filtered on, and
    -- the live one re-reads outside the GetInfo walk that fullRebuild writes it from.
    local cached, live = 0, 0
    for id, e in store:Each() do
        if e.isTracked then cached = cached + 1 end
        if isWatched(id) then live = live + 1 end
    end

    local map  = ns.Has.Map and C_Map.GetBestMapForUnit("player") or nil
    local list = (map and ns.Has.QuestsOnMap) and C_QuestLog.GetQuestsOnMap(map) or nil

    -- Live rather than the walk's copy: the counters are written in fullRebuild only, so on a
    -- refreshDynamic pass the stored pair describes an older log state than this line.
    local apiNow = C_QuestLog.GetNumQuestLogEntries() or 0

    -- Named only when the cached set belongs to the map underfoot AND the walk climbed to
    -- build it. Neither half is optional: zoneRootID is never cleared, so on a fail-open pass
    -- or with the filter switched off it holds a previous map's root and would announce a
    -- climb that did not happen, on the one line a "my quest vanished" report is read from.
    local climbed = (zoneMapID == map and zoneRootID and zoneRootID ~= zoneMapID)
        and (" -> zone %s"):format(tostring(zoneRootID)) or ""

    return ("quests: normal=%s questline=%s campaign=%s meta=%s important=%s | class %s\n      log api %d now %d walked %d | watched cached %d live %d | zone set map %s list %s%s"):format(
        tostring(QC.Normal), tostring(QC.Questline), tostring(QC.Campaign),
        tostring(QC.Meta), tostring(QC.Important), table.concat(parts, " "),
        walkEntries, apiNow, walkQuests, cached, live, tostring(map),
        list and tostring(#list) or "nil", climbed)
end

-- Undocumented, like /eqot flavorprobe. Prints every signal that could place a quest beside
-- the verdict IsCurrentZone actually returned, which is what the zone rule was chosen from and
-- what to read before changing it again.
function Quests:ZoneProbeLines()
    local out  = {}
    local map  = ns.Has.Map and C_Map.GetBestMapForUnit("player") or nil
    local mi   = (map and C_Map.GetMapInfo) and C_Map.GetMapInfo(map) or nil
    local par  = mi and mi.parentMapID
    local pmi  = (par and par > 0 and C_Map.GetMapInfo) and C_Map.GetMapInfo(par) or nil

    local function idsOn(m)
        local set, list = {}, (m and ns.Has.QuestsOnMap) and C_QuestLog.GetQuestsOnMap(m) or nil
        if list then
            for i = 1, #list do
                local q = list[i]
                if q and q.questID then set[q.questID] = true end
            end
        end
        return set, list and #list or -1
    end

    local onMap, nMap = idsOn(map)
    local onPar, nPar = idsOn(par)

    out[#out + 1] = ("zone probe: map %s %s (%d on map) | parent %s %s (%d on map)"):format(
        tostring(map), mi and mi.name or "?", nMap,
        tostring(par), pmi and pmi.name or "?", nPar)
    out[#out + 1] = "  id     set par iOM POI wp          dist         tz   verdict | header | title"

    local header
    for i = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
        local info = C_QuestLog.GetInfo(i)
        if info then
            if info.isHeader then
                header = info.title
            elseif not info.isHidden and info.questID then
                local id = info.questID

                local wp = "-"
                if ns.Has.NextWaypoint then
                    local wm, wx, wy = C_QuestLog.GetNextWaypoint(id)
                    wp = ("%s/%s"):format(tostring(wm), (wx and wy) and "xy" or "noxy")
                end

                local dist = "-"
                if ns.Has.QuestDistance then
                    -- Distance.lua reports this API returning NaN for an unplaceable quest, so
                    -- the self-comparison catches it. The Coiled Isle reading saw nil, not NaN.
                    local sq, cont = C_QuestLog.GetDistanceSqToQuest(id)
                    dist = ("%s/%s"):format(
                        (sq == nil and "nil") or (sq ~= sq and "nan") or ("%.0f"):format(sq),
                        tostring(cont))
                end

                local tz = "-"
                if C_TaskQuest and C_TaskQuest.GetQuestZoneID then
                    -- Assigned before it is printed: this returns ZERO values for a quest
                    -- that is not a task quest, and tostring() with no argument raises.
                    local z = C_TaskQuest.GetQuestZoneID(id)
                    tz = tostring(z)
                end

                local verdict = self:IsCurrentZone({ id = id })

                out[#out + 1] = ("  %-6d %-3s %-3s %-3s %-3s %-11s %-14s %-4s %-7s | %s | %s"):format(
                    id, onMap[id] and "YES" or "no", onPar[id] and "YES" or "no",
                    info.isOnMap and "YES" or "no", info.hasLocalPOI and "YES" or "no",
                    wp, dist, tz, tostring(verdict),
                    tostring(header):sub(1, 16), tostring(info.title):sub(1, 30))
            end
        end
    end
    return out
end

function Quests:OnEntryClick(entry, button)
    if button == "RightButton" then
        if ns.Has.QuestWatchAPI then C_QuestLog.RemoveQuestWatch(entry.id) end
        return
    end
    if ns.Has.SuperTrack then
        C_SuperTrack.SetSuperTrackedQuestID(entry.id)
        if self._notifyDirty then self._notifyDirty() end
    end
end

-- Only implemented here, which is also what gates the split-click option: Row offers it
-- solely to a provider that answers this, matching EQ having it on quest blocks alone.
function Quests:OnEntryOpenLog(entry)
    if C_AddOns and C_AddOns.LoadAddOn then C_AddOns.LoadAddOn("Blizzard_QuestLog") end
    if QuestMapFrame_OpenToQuestDetails then
        QuestMapFrame_OpenToQuestDetails(entry.id)
    elseif ToggleQuestLog then
        ToggleQuestLog()
    end
end

local function isFocused(id)
    return ns.Has.SuperTrack and C_SuperTrack.GetSuperTrackedQuestID
       and C_SuperTrack.GetSuperTrackedQuestID() == id
end

local function setWatched(id, watch)
    if not ns.Has.QuestWatchAPI then return end
    if watch then
        -- Typed Manual on purpose: an untyped watch is AUTOMATIC, which the engine silently
        -- evicts past a small cap, so the quest would drop off the tracker on its own.
        -- Literal 1 from Data/WatchPersist.lua: a nil type IS the automatic watch refused above.
        local manual = (Enum and Enum.QuestWatchType and Enum.QuestWatchType.Manual) or 1
        C_QuestLog.AddQuestWatch(id, manual)
    else
        C_QuestLog.RemoveQuestWatch(id)
    end
end

local function openQuestDetailsPopup(id)
    if C_AddOns and C_AddOns.LoadAddOn then C_AddOns.LoadAddOn("Blizzard_QuestLog") end

    if QuestMapQuestOptions_OpenQuestDetails then
        QuestMapQuestOptions_OpenQuestDetails(id)
        return
    end
    if not QuestLogPopupDetailFrame then return end
    if not (C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id)) then return end

    QuestLogPopupDetailFrame.questID = id
    if C_QuestLog.SetSelectedQuest then C_QuestLog.SetSelectedQuest(id) end
    if StaticPopup_Hide then
        StaticPopup_Hide("ABANDON_QUEST")
        StaticPopup_Hide("ABANDON_QUEST_WITH_ITEMS")
    end
    if QuestMapFrame_UpdateQuestDetailsButtons then QuestMapFrame_UpdateQuestDetailsButtons() end
    if QuestLogPopupDetailFrame_Update then QuestLogPopupDetailFrame_Update(true) end
    QuestLogPopupDetailFrame:Show()
end

-- Routed through Blizzard's own confirmation popup rather than abandoning outright, so the
-- item-loss warning still appears. SetSelectedQuest is global state the quest log reads, so
-- the previous selection is put back or the log opens on a quest the player did not choose.
-- Returns nil on success or a reason TOKEN, never wording: UI/RowMenu.lua turns it into a
-- line the player can read. Returning nothing meant a click on a red Abandon Quest did
-- nothing at all and looked like a broken addon.
local function abandonQuest(id)
    if not (C_QuestLog.SetSelectedQuest and C_QuestLog.SetAbandonQuest
            and C_QuestLog.GetAbandonQuest) then
        return "unavailable"
    end
    if InCombatLockdown() then return "combat" end

    local oldSelected = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest() or 0
    C_QuestLog.SetSelectedQuest(id)
    C_QuestLog.SetAbandonQuest()

    local abandonID = C_QuestLog.GetAbandonQuest()
    -- SetAbandonQuest latches a target. If the quest left the log between opening the menu and
    -- clicking, the latch can still hold the previous one, and abandoning that is unrecoverable.
    if abandonID and abandonID ~= id then
        C_QuestLog.SetSelectedQuest(oldSelected or 0)
        return "stale"
    end
    -- Total by construction: a nil here reaches StaticPopup's no-arg branch and the
    -- confirmation renders a literal %s instead of the quest name.
    local title = (QuestUtils_GetQuestName and QuestUtils_GetQuestName(abandonID))
                  or (C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(abandonID))
                  or ("Quest #" .. tostring(id))
    local items = C_QuestLog.GetAbandonQuestItems and C_QuestLog.GetAbandonQuestItems()
    if items and #items > 0 and StaticPopupDialogs and StaticPopupDialogs.ABANDON_QUEST_WITH_ITEMS then
        StaticPopup_Show("ABANDON_QUEST_WITH_ITEMS", title, table.concat(items, ", "))
    else
        StaticPopup_Show("ABANDON_QUEST", title)
    end

    C_QuestLog.SetSelectedQuest(oldSelected or 0)
end

local menuOut = {}
local pinShim = {}

function Quests:GetEntryMenu(entry)
    local Filter = ns:GetModule("Filter")
    local id = entry.id

    for i = #menuOut, 1, -1 do menuOut[i] = nil end

    -- Spaced by ten so an extension can land between any two, which is how EQ puts its Chain
    -- Guide "Get Directions" back between Focus and Open in Map.
    menuOut[#menuOut + 1] = { kind = "title", text = entry.title, order = 0 }
    menuOut[#menuOut + 1] = { id = Filter:IsPinned(entry) and "unpin" or "pin", order = 10 }
    menuOut[#menuOut + 1] = { id = isWatched(id) and "untrack" or "track",      order = 20 }
    menuOut[#menuOut + 1] = { id = isFocused(id) and "unfocus" or "focus",      order = 30 }
    menuOut[#menuOut + 1] = { id = "openlog", order = 40 }
    menuOut[#menuOut + 1] = { id = "popout",  order = 50 }
    menuOut[#menuOut + 1] = { id = "wowhead", order = 60 }
    menuOut[#menuOut + 1] = { kind = "divider", order = 70 }
    menuOut[#menuOut + 1] = { id = "abandon", order = 80, danger = true }
    return menuOut
end

function Quests:OnEntryMenuSelect(entryID, itemID)
    local refused
    if itemID == "pin" or itemID == "unpin" then
        pinShim.id, pinShim.providerID = entryID, self.id
        ns:GetModule("Filter"):SetPinned(pinShim, itemID == "pin")
    elseif itemID == "track" then
        setWatched(entryID, true)
    elseif itemID == "untrack" then
        setWatched(entryID, false)
    elseif itemID == "focus" then
        if ns.Has.SuperTrack then C_SuperTrack.SetSuperTrackedQuestID(entryID) end
    elseif itemID == "unfocus" then
        if ns.Has.SuperTrack then C_SuperTrack.SetSuperTrackedQuestID(0) end
    elseif itemID == "openlog" then
        self:OnEntryOpenLog({ id = entryID })
    elseif itemID == "popout" then
        openQuestDetailsPopup(entryID)
    elseif itemID == "abandon" then
        refused = abandonQuest(entryID)
    end
    if self._notifyDirty then self._notifyDirty() end
    return refused
end

function Quests:OnEntryGroupFinder(entry)
    QuestGroups:Find(entry.id)
end

function Quests:Enable(notifyDirty)
    local Events = ns:GetModule("Events")

    -- A bare notifyDirty is not enough here: GetEntries returns the cached store unless a dirty
    -- flag is set, so the repaint would hand back the same entries with canGroup still false and
    -- the eye would wait for an unrelated quest event. WorldQuests can subscribe the raw notify
    -- because its GetEntries rebuilds every pass.
    ns:GetModule("QuestGroups"):OnResolved(function()
        dirtyObjectives = true
        notifyDirty()
    end)

    local function markAll()
        dirtyAll, zoneDirty = true, true
        notifyDirty()
    end
    local function markDynamic()
        if not primed then dirtyAll = true else dirtyObjectives = true end
        zoneDirty = true
        notifyDirty()
    end
    local function markZone()
        zoneDirty = true
        notifyDirty()
    end

    Events:On("QUEST_ACCEPTED",           markAll)
    Events:On("QUEST_REMOVED",            markAll)
    Events:On("QUEST_TURNED_IN",          markAll)
    Events:On("PLAYER_ENTERING_WORLD",    markAll)
    Events:On("QUEST_LOG_UPDATE",         markDynamic)
    Events:On("QUEST_WATCH_LIST_CHANGED", markDynamic)
    Events:On("SUPER_TRACKING_CHANGED",   markDynamic)
    Events:On("ZONE_CHANGED_NEW_AREA",    markZone)

    -- Blizzard fires nothing when a quest item arrives by any route other than looting, so
    -- withdrawing 5 of 8 from the bank leaves the row reading 3/8 until an unrelated quest event
    -- happens by. All six are registered rather than treating the interaction manager as an
    -- either/or: Events:On answers whether the client knows the event NAME, which is not whether
    -- it FIRES for these windows, and a client that accepts the registration without firing it
    -- would have had its own fallback suppressed. markDynamic only sets a dirty flag and the
    -- notify is throttled, so a doubled event costs nothing.
    Events:On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", markDynamic)
    Events:On("BANKFRAME_CLOSED",     markDynamic)
    Events:On("MAIL_CLOSED",          markDynamic)
    Events:On("MERCHANT_CLOSED",      markDynamic)
    Events:On("TRADE_CLOSED",         markDynamic)
    Events:On("AUCTION_HOUSE_CLOSED", markDynamic)
end

Registry:Register(Quests)
