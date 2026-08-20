local _, ns = ...

local Entry      = ns:GetModule("Entry")
local Registry   = ns:GetModule("Registry")
local QuestItems = ns:GetModule("QuestItems")
local Focus      = ns:GetModule("Focus")
local TrackedSet = ns:GetModule("TrackedSet")

local STATE, LINE, ICON = Entry.STATE, Entry.LINE, Entry.ICON

-- The Classic quest log is index driven where retail is questID driven, and it carries no
-- super-track and no campaign at all. Listed only in the Classic TOCs, so this file and
-- Data/Providers/Quests.lua are never both loaded and both may claim the id "quests".
local Quests = {
    id       = "quests",
    groups   = { "quests" },
    priority = 10,
    idSpace  = "quest",
    tags     = { "daily", "weekly", "dungeon", "raid" },
    filterCategories = true,
}

-- GetQuestLogTitle returns the full modern tuple on 1.15.9 and 2.5.6, measured on both:
-- 1 title, 2 level, 4 isHeader, 6 isComplete, 7 frequency, 8 questID.
local T_TITLE, T_LEVEL, T_HEADER, T_COMPLETE, T_FREQ, T_ID = 1, 2, 4, 6, 7, 8

-- Ceiling for the quest log walk. The real cap is far lower, so this only has to be safely
-- above it.
local MAX_LOG_INDEX = 75

-- Slot 7 of the flat GetQuestLogTitle carries the LEGACY numbering, 1 default / 2 daily /
-- 3 weekly, NOT Enum.QuestFrequency whose Daily is 1. Measured on 1.15.9: an ordinary
-- Elwynn quest reports 7 = 1, which means "default" only under the legacy scheme. Reading
-- the enum here, which is present on both Classic clients, tagged every quest as daily and
-- emptied the tracker whenever the Daily filter was unticked.
local DAILY_FREQ, WEEKLY_FREQ = 2, 3

-- Fallback ids read off Enum.QuestTag on 1.15.9: Dungeon 81, Raid 62, Raid10 88, Raid25 89.
-- 85 is Heroic and was wrong here for both raid sizes.
local TAG_DUNGEON = (Enum and Enum.QuestTag and Enum.QuestTag.Dungeon) or 81
local TAG_RAID    = (Enum and Enum.QuestTag and Enum.QuestTag.Raid)    or 62
local TAG_RAID10  = (Enum and Enum.QuestTag and Enum.QuestTag.Raid10)  or 88
local TAG_RAID25  = (Enum and Enum.QuestTag and Enum.QuestTag.Raid25)  or 89

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

-- Its own counter rather than stillInLog's, which TrackedSet:Prune already spends: two prunes
-- sharing one set of strikes would reach the limit in half the passes.
local SEEN_STRIKES = 3
local seenMisses   = {}

local dirtyAll        = true
local dirtyObjectives = false
local primed          = false
local baselined       = false

-- Stamped so DebugLine can separate a stale cache from isWatched answering differently
-- inside the GetQuestLogTitle walk than outside it. Status read 0 cached against 9 live.
local lastFullAt, lastDynAt, lastFullWatched = 0, 0, 0

local notifyDirty

-- Re-entrancy guard for the AddQuestWatch hook below, which answers by calling RemoveQuestWatch.
-- Nothing in this file hooks RemoveQuestWatch, so it does not guard against ourselves - it
-- guards against another addon hooking RemoveQuestWatch and calling AddQuestWatch back, which
-- would otherwise bounce between the two hooks without end.
local suppressWatchHook = false

-- The watch poll that used to live here is GONE, and owning the tracked set is why. It existed
-- because another addon replaces IsQuestWatched seconds after login, so the first walks read a
-- watch list that was not ours and not yet correct. Nothing reads that global any more, so there
-- is no longer an answer that arrives late. Do not reintroduce a retry here for that reason.

-- Every rebuild for the first stretch after login, recorded as elapsed:watched/entries, because
-- the window where the tracker looks empty cannot be read while it is happening - /eqot status
-- builds the feed itself and cures the symptom, so the last entry here is usually that command.
local WALK_LOG_MAX = 10
local walkLog, walkLogN, loadedAt = {}, 0, GetTime()

local tagIDCache = {}

local function logIndex(id)
    if type(GetQuestLogIndexByID) ~= "function" then return nil end
    local i = GetQuestLogIndexByID(id)
    if not i or i == 0 then return nil end
    return i
end

-- GetQuestTagInfo is a plain global here rather than a C_QuestLog method, and its return
-- can be a table or a bare id, so both shapes are accepted rather than assumed.
local function getTagID(id)
    local cached = tagIDCache[id]
    if cached then return cached end
    if type(GetQuestTagInfo) ~= "function" then return nil end
    local got = GetQuestTagInfo(id)
    local tagID = (type(got) == "table" and got.tagID) or (type(got) == "number" and got) or nil
    if tagID then tagIDCache[id] = tagID end
    return tagID
end

-- isComplete arrives nil while in progress, 1 when complete and -1 when failed.
local function questState(isComplete)
    if isComplete == -1 then return STATE.FAILED end
    if isComplete and isComplete ~= 0 then return STATE.COMPLETE end
    return STATE.ACTIVE
end

-- EQOT owns the tracked set on this flavor rather than mirroring Blizzard's watch list, and
-- that is the whole point. Blizzard caps its list at FIVE and throws a red error on the sixth, it
-- auto-tracks nothing on accept, and another quest addon commonly replaces IsQuestWatched and
-- empties the list underneath it. Reading our own table removes all three at once, and it is why
-- no TRACKING path here calls AddQuestWatch or RemoveQuestWatch any more - which is what stops
-- an untrack from the row menu writing into that other addon's saved variables. The hook in
-- Enable is the one remaining caller and it runs on Blizzard's own adds, not on ours.
--
-- nil, never false, until the player has made a first explicit choice, so Filter's
-- `isTracked == false` test fails open exactly as IsCurrentZone's nil already does.
local function isWatched(id)
    return TrackedSet:IsTracked(id)
end

local function setWatched(id, watch)
    TrackedSet:Set(id, watch)
end

-- Hoisted rather than written inline at the Prune call, which runs on the rebuild path and would
-- allocate a fresh closure every time.
--
-- A quest that has not streamed in yet looks exactly like one that is gone, and pruning deletes
-- a tracked flag from saved variables permanently - so absence has to repeat before it counts.
-- A missed prune costs nothing but a stale id. A wrong one is unrecoverable.
local PRUNE_STRIKES = 3
local pruneMisses   = {}
local function stillInLog(id)
    if store:Get(id) then
        pruneMisses[id] = nil
        return true
    end
    local n = (pruneMisses[id] or 0) + 1
    if n >= PRUNE_STRIKES then
        pruneMisses[id] = nil
        return false
    end
    pruneMisses[id] = n
    return true
end

local function fillLines(e, id, index)
    Entry.BeginLines(e)

    local objs = ns.Has.QuestObjectives and C_QuestLog.GetQuestObjectives(id) or nil
    local n    = objs and #objs or 0

    if n > 0 then
        for i = 1, n do
            local o  = objs[i]
            local ln = Entry.PushLine(e)
            ln.text      = o.text or ""
            ln.completed = o.finished and true or false
            ln.current   = o.numFulfilled
            ln.required  = o.numRequired
            if o.type == "progressbar" then ln.kind = LINE.PROGRESSBAR end
        end
    elseif index and type(GetNumQuestLeaderBoards) == "function"
           and type(GetQuestLogLeaderBoard) == "function" then
        -- Fallback for a quest whose structured objectives have not streamed in. The text
        -- already carries its own "0/1" here, so no current/required is set.
        for i = 1, (GetNumQuestLeaderBoards(index) or 0) do
            local text, _, finished = GetQuestLogLeaderBoard(i, index)
            if text and text ~= "" then
                local ln = Entry.PushLine(e)
                ln.text      = text
                ln.completed = finished and true or false
            end
        end
    end

    Entry.EndLines(e)
end

local function fillTags(e, id, frequency)
    local tags = e.tags
    wipe(tags)
    e.frequency = frequency or 0
    if frequency == DAILY_FREQ  then tags.daily  = true end
    if frequency == WEEKLY_FREQ then tags.weekly = true end
    local tagID = getTagID(id)
    if tagID == TAG_DUNGEON then
        tags.dungeon = true
    elseif tagID == TAG_RAID or tagID == TAG_RAID10 or tagID == TAG_RAID25 then
        tags.raid = true
    end
end

-- Quest-log headers ARE zone names on Classic, unlike retail where they are campaign
-- groupings, so comparing the header to the player's zone is correct here.
function Quests:IsCurrentZone(entry)
    if type(GetZoneText) ~= "function" then return nil end
    local zone = GetZoneText()
    if not zone or zone == "" then return nil end
    return entry.zone == zone
end

local function fullRebuild()
    local firstSeen = stamps()
    local currentHeader
    local watchedDuringWalk = 0
    store:Begin()

    -- Bounded by a ceiling and stopped at the first nil title, NOT by GetNumQuestLogEntries.
    -- That count returns only the VISIBLE rows, so it drops to the header count when the
    -- player collapses their quest log - while the quests stay perfectly addressable, just
    -- reordered after the headers. Measured on 1.15.9 with all three headers collapsed:
    -- entries=3, yet indices 4 through 13 still returned all ten quests. Walking to that
    -- count saw three headers and no quests, and Store:Finish then pruned every entry, so
    -- one collapsed header plus any quest event emptied the tracker and re-flagged the lot
    -- as NEW on expand.
    for i = 1, MAX_LOG_INDEX do
        local t = { GetQuestLogTitle(i) }
        local title = t[T_TITLE]
        if not title then break end
        if t[T_HEADER] then
            currentHeader = title
        else
            local id = t[T_ID]
            if id and id ~= 0 then
                local fs = firstSeen[id]
                if not fs then
                    fs = baselined and time() or 0
                    firstSeen[id] = fs
                end

                local e = store:Acquire(id)
                e.title     = title
                e.subtitle  = currentHeader
                e.zone      = currentHeader
                e.level     = t[T_LEVEL]
                e.addedAt   = fs
                e.state     = questState(t[T_COMPLETE])
                e.isTracked = isWatched(id)
                if e.isTracked then watchedDuringWalk = watchedDuringWalk + 1 end
                e.icon.classification = nil
                e.hasItem   = QuestItems:Has(id)
                fillTags(e, id, t[T_FREQ])
                e.groupID = "quests"
                fillLines(e, id, i)
            end
        end
    end

    store:Finish()

    -- Pruned only against a log that actually returned something. A cold login can present
    -- an empty one, and pruning against that would drop every persisted stamp. That test is
    -- one-sided though: a walk that returned SOME quests still says nothing about the ones
    -- that have not streamed in, and they look identical to quests that are gone. So absence
    -- has to repeat, exactly as the tracked-set prune above already requires.
    if next(store:Out()) ~= nil then
        for id in pairs(firstSeen) do
            if store:Get(id) then
                seenMisses[id] = nil
            else
                local n = (seenMisses[id] or 0) + 1
                if n >= SEEN_STRIKES then
                    seenMisses[id] = nil
                    firstSeen[id], tagIDCache[id] = nil, nil
                else
                    seenMisses[id] = n
                end
            end
        end
        primed    = true
        baselined = true
    end
    lastFullAt, lastFullWatched = time(), watchedDuringWalk
    dirtyAll        = false
    dirtyObjectives = false

    if walkLogN < WALK_LOG_MAX then
        walkLogN = walkLogN + 1
        walkLog[walkLogN] = ("%.1fs:%d/%d"):format(GetTime() - loadedAt,
                                                  watchedDuringWalk, #store:Out())
    end

    -- Prune only. Materializing the set is TrackedSet's own job now, done on the first write
    -- that removes a quest, because this rebuild is NOT a reliable first-write barrier: it runs
    -- from Tracker:Render, which returns early while the tracker is hidden, so a quest accepted
    -- behind a visibility rule reached the set before any rebuild did. Prune no-ops while the
    -- set is absent, so nothing here has to know which state it is in.
    if next(store:Out()) ~= nil then
        TrackedSet:Prune(stillInLog)
    end
end

local function refreshDynamic()
    for id, e in store:Each() do
        local i = logIndex(id)
        e.isTracked = isWatched(id)
        e.hasItem   = QuestItems:Has(id)
        if i then
            local t = { GetQuestLogTitle(i) }
            e.state = questState(t[T_COMPLETE])
        end
        fillLines(e, id, i)
    end
    lastDynAt = time()
    dirtyObjectives = false
end

function Quests:IsAvailable()
    return type(GetNumQuestLogEntries) == "function"
       and type(GetQuestLogTitle) == "function"
end

-- Watch state is re-read here, outside any GetQuestLogTitle walk and on every call, because
-- the copy written during fullRebuild's walk came back false for every quest on 1.15.9 while
-- a direct read moments later returned true for nine of ten. Two causes fit that - the walk
-- context, or a cache nothing re-dirtied after login - and they were never separated. This
-- is correct under both. `saw N watched` in DebugLine still reports the walk-time answer, so
-- the next rebuild that happens with quests watched will say which it was.
local function syncWatched()
    for id, e in store:Each() do
        e.isTracked = isWatched(id)
    end
end

-- Total rather than written during the walk, so a focus change needs no rebuild and a pooled
-- entry can never keep a previous quest's focus. This client has no super-track, so the answer
-- comes from Data/Focus.lua rather than from the game.
local function syncFocus()
    local providerID, focusedID = Focus:Get()
    local mine = providerID == Quests.id
    for id, e in store:Each() do
        e.isFocused = mine and focusedID == id
    end
end

function Quests:GetEntries()
    if dirtyAll then
        fullRebuild()
    elseif dirtyObjectives then
        refreshDynamic()
    end
    syncWatched()
    syncFocus()
    return store:Out()
end

-- The cached count is what the rows were drawn from. The live count re-reads the API now.
-- They are reported separately because status once said 0 watched a minute after a direct
-- IsQuestWatched read on the same quests returned true, and a single number cannot tell a
-- stale cache from a watch list that really did empty.
function Quests:DebugLine()
    local n, cached, live = 0, 0, 0
    local stamped, newest = 0, nil
    local sample = {}
    for id, e in store:Each() do
        n = n + 1
        local now = isWatched(id)
        if e.isTracked then cached = cached + 1 end
        if now then live = live + 1 end
        -- Whatever the whole log was baselined to reads 0 here, so a nonzero stamp is a quest
        -- accepted since login and is exactly what the NEW tag draws off.
        if e.addedAt and e.addedAt > 0 then
            stamped = stamped + 1
            if not newest or e.addedAt > newest then newest = e.addedAt end
        end
        if #sample < 6 then
            sample[#sample + 1] = ("%s:%d/%d"):format(id, e.isTracked and 1 or 0, now and 1 or 0)
        end
    end
    -- Assigned to locals first: select(2, ...) on a one-value return yields ZERO values and
    -- tostring() with no argument raises, which would truncate the rest of /eqot status.
    local numEntries, numQuests
    if type(GetNumQuestLogEntries) == "function" then
        numEntries, numQuests = GetNumQuestLogEntries()
    end

    -- nil means the player has never made an explicit choice, which is NOT the same as zero and
    -- is why the whole log shows rather than none of it.
    local owned = TrackedSet:Count()

    local now = time()
    return ("quests: classic quest log, %d entries (%d cached watched, %d live) | log %s/%s | zone %s | rebuild %ds ago saw %d watched, tracked set %s, refresh %ds ago | new tag: baselined %s, %d stamped, newest %s | walks %s | id:cached/live %s"):format(
        n, cached, live,
        tostring(numQuests),
        tostring(numEntries),
        tostring(GetZoneText and GetZoneText()),
        lastFullAt > 0 and (now - lastFullAt) or -1, lastFullWatched,
        owned and tostring(owned) or "none stored yet",
        lastDynAt > 0 and (now - lastDynAt) or -1,
        tostring(baselined), stamped,
        newest and ((now - newest) .. "s ago") or "none",
        table.concat(walkLog, " ", 1, walkLogN),
        table.concat(sample, " "))
end

-- The icon half of a left-click lands here and the title half goes to OnEntryOpenLog, which is
-- retail's layout with focus standing in for super-track. With Split quest click OFF the whole
-- row lands here, so focus is then the only left-click and the quest log is reached from the
-- row menu, exactly as it is on retail.
function Quests:OnEntryClick(entry, button)
    if button == "RightButton" then
        setWatched(entry.id, false)
        return
    end
    Focus:Toggle(self.id, entry.id)
end

function Quests:OnEntryOpenLog(entry)
    local i = logIndex(entry.id)
    if i and type(SelectQuestLogEntry) == "function" then SelectQuestLogEntry(i) end
    if type(ToggleQuestLog) == "function" then ToggleQuestLog() end
end

local menuOut = {}
local pinShim = {}

-- Still shorter than the retail menu. Pop out and Abandon both need a Blizzard popup or detail
-- frame, and Data/ may not drive one - the two calls that already do in Quests.lua are recorded
-- debt, not a precedent to copy. Named indirectly so the layering grep's output stays a known
-- set. Focus is here at retail's own order 30 now that this client has a focus concept.
function Quests:GetEntryMenu(entry)
    local Filter = ns:GetModule("Filter")
    local id = entry.id

    for i = #menuOut, 1, -1 do menuOut[i] = nil end

    menuOut[#menuOut + 1] = { kind = "title", text = entry.title, order = 0 }
    menuOut[#menuOut + 1] = { id = Filter:IsPinned(entry) and "unpin" or "pin", order = 10 }
    menuOut[#menuOut + 1] = { id = isWatched(id) and "untrack" or "track",      order = 20 }
    menuOut[#menuOut + 1] = { id = Focus:Is(self.id, id) and "unfocus" or "focus", order = 30 }
    menuOut[#menuOut + 1] = { id = "openlog", order = 40 }
    menuOut[#menuOut + 1] = { id = "wowhead", order = 60 }
    return menuOut
end

function Quests:OnEntryMenuSelect(entryID, itemID)
    if itemID == "pin" or itemID == "unpin" then
        pinShim.id, pinShim.providerID = entryID, self.id
        ns:GetModule("Filter"):SetPinned(pinShim, itemID == "pin")
    elseif itemID == "track" then
        setWatched(entryID, true)
    elseif itemID == "untrack" then
        setWatched(entryID, false)
    elseif itemID == "focus" then
        Focus:Set(self.id, entryID)
    elseif itemID == "unfocus" then
        Focus:Set(nil, nil)
    elseif itemID == "openlog" then
        self:OnEntryOpenLog({ id = entryID })
    end
    if self._notifyDirty then self._notifyDirty() end
end

function Quests:Enable(notify)
    local Events = ns:GetModule("Events")

    notifyDirty = notify

    -- Focus answers to no game event, so the repaint has to come from the store itself.
    Focus:OnDirty(notifyDirty)

    local function markAll()
        dirtyAll = true
        notifyDirty()
    end

    -- A focused quest can leave the log by being turned in or abandoned, and nothing else would
    -- ever announce the clear, so a listener's arrow would keep pointing at a quest the player
    -- no longer has. Checked against the log rather than the store because this runs before the
    -- rebuild. Focus:Set notifies through OnDirty, so the plain notify is the other branch only.
    local function markRemoved()
        dirtyAll = true
        local providerID, focusedID = Focus:Get()
        if providerID == Quests.id and focusedID and not logIndex(focusedID) then
            Focus:Set(nil, nil)
        else
            notifyDirty()
        end
    end
    local function markDynamic()
        if not primed then dirtyAll = true else dirtyObjectives = true end
        notifyDirty()
    end

    -- The tracked set answers to no game event, so the repaint comes from the set itself. This
    -- covers every route into it at once: the row menu, auto-track on accept, and the quest log
    -- click that UI/QuestLogChecks.lua owns.
    TrackedSet:OnDirty(notifyDirty)

    -- The ONLY thing left on Blizzard's watch functions, and it no longer carries the gesture:
    -- emptying its list behind every add is what keeps its five-quest cap from ever being
    -- reached. Measured after: GetNumQuestWatches() reads 0, so its own handler can never take
    -- the too-many-quests branch. The toggle used to hang off this hook and could not stay -
    -- shift-clicking a row calls neither watch function on 1.15.9, so it silently never fired.
    if type(AddQuestWatch) == "function" and type(RemoveQuestWatch) == "function" then
        hooksecurefunc("AddQuestWatch", function(index)
            if suppressWatchHook then return end
            suppressWatchHook = true
            RemoveQuestWatch(index)
            suppressWatchHook = false
        end)
    end

    Events:On("QUEST_ACCEPTED",          markAll)
    Events:On("QUEST_REMOVED",           markRemoved)
    Events:On("QUEST_TURNED_IN",         markRemoved)
    Events:On("PLAYER_ENTERING_WORLD",   markAll)
    Events:On("QUEST_LOG_UPDATE",        markDynamic)
    Events:On("UNIT_QUEST_LOG_CHANGED",  markDynamic)
    Events:On("QUEST_WATCH_UPDATE",      markDynamic)
    Events:On("ZONE_CHANGED_NEW_AREA",   markAll)

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
