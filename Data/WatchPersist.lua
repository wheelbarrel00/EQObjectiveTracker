local _, ns = ...

local WatchPersist = ns:RegisterModule("WatchPersist", {})

local MANUAL          = (Enum and Enum.QuestWatchType and Enum.QuestWatchType.Manual) or 1
local RESTORE_DELAY   = 2
local RESTORE_RETRIES = 5

-- Everything Quests drives this from its own world map pins, which call Track and
-- Untrack directly. EQOT is tracker-only and has no map UI to hook, so it mirrors
-- Blizzard's watch list instead of intercepting it.
--
-- Only MANUAL watches are stored. Walking near a world quest auto-watches it, and
-- persisting that would permanently pin every quest the player ever ran past.
local restored       = false
local restoreArmed   = false
local restoreTries   = 0
local restorePending = nil

local function getList()
    local DB   = ns:GetModule("DB")
    local char = DB and DB:Char()
    if not char then return nil end
    char.trackedWorldQuests = char.trackedWorldQuests or {}
    return char.trackedWorldQuests
end

-- Three-state, and the third state is the point. Not C_QuestLog.IsWorldQuest: that stays
-- true for an expired world quest forever, so ghost entries could never be pruned. But nil
-- means the task cache has not answered yet, and pruning on that deletes the player's saved
-- watches on any slow login. A non-nil zero IS an answer, so it reads as expired.
local function liveState(questID)
    if ns.Has.WorldQuestTime then
        local t = C_TaskQuest.GetQuestTimeLeftMinutes(questID)
        if t then return t > 0 end
    end
    if C_TaskQuest and C_TaskQuest.IsActive and C_TaskQuest.IsActive(questID) then
        return true
    end
    return nil
end

local function watchType(questID)
    if not ns.Has.QuestWatchType then return nil end
    return C_QuestLog.GetQuestWatchType(questID)
end

local function restore()
    if restored then return end
    local list = getList()
    -- Disarm rather than give up, or a DB that was not ready yet strands the chain and no
    -- later loading screen can restart it.
    if not list then
        restoreArmed = false
        return
    end

    -- Retries walk only what is still unanswered, never the whole list again. Re-walking it
    -- would re-add a watch the player removed during the window, since mirror() cannot prune
    -- it until the chain finishes.
    local stillUnknown
    for questID in pairs(restorePending or list) do
        if list[questID] then
            local live = liveState(questID)
            if live == false then
                list[questID] = nil
            elseif live then
                -- Automatic is 0, so a nil test reads an auto-watch as restored and the next mirror()
                -- drops it. A manual add promotes one.
                if watchType(questID) ~= MANUAL and ns.Has.WorldQuestWatchAdd then
                    C_QuestLog.AddWorldQuestWatch(questID, MANUAL)
                    -- The add is silently rejected once Blizzard's watch cap is full, which
                    -- proximity auto-watch can reach before this runs. Retry on a watch that
                    -- did not land, or mirror() drops the entry at the next watch change.
                    if watchType(questID) ~= MANUAL then
                        stillUnknown = stillUnknown or {}
                        stillUnknown[questID] = true
                    end
                end
            else
                stillUnknown = stillUnknown or {}
                stillUnknown[questID] = true
            end
        end
    end

    -- Retry rather than prune what the cache has not answered for. Giving up leaves those
    -- entries alone: mirror() prunes for real once the watch list next changes.
    if stillUnknown and restoreTries < RESTORE_RETRIES then
        restorePending = stillUnknown
        restoreTries   = restoreTries + 1
        C_Timer.After(RESTORE_DELAY, restore)
        return
    end
    restorePending = nil

    restoreArmed = false
    restored     = true
    -- Through the provider's own dirty hook rather than the tracker, so this stays
    -- inside the data layer.
    local provider = ns:GetModule("Registry"):Get("worldquests")
    if provider and provider._notifyDirty then provider._notifyDirty() end
end

-- Blizzard's watch list is empty until the restore runs, so mirroring any earlier would
-- wipe the saved set on every login.
local function mirror()
    if not restored then return end
    local list = getList()
    if not (list and ns.Has.WorldQuests) then return end
    wipe(list)
    for i = 1, (C_QuestLog.GetNumWorldQuestWatches() or 0) do
        local qid = C_QuestLog.GetQuestIDForWorldQuestWatchIndex(i)
        if qid and watchType(qid) == MANUAL then list[qid] = true end
    end
end

function WatchPersist:DebugLine()
    local list = getList()
    local n = 0
    if list then for _ in pairs(list) do n = n + 1 end end
    return ("world quest watches: %d saved, restore %s"):format(
        n, restored and "done"
           or ("pending (try %d/%d)"):format(restoreTries, RESTORE_RETRIES))
end

function WatchPersist:OnEnable()
    if not ns.Has.WorldQuests then return end
    local Events = ns:GetModule("Events")

    -- World quest data is not populated at login, so the restore has to wait for it. One
    -- chain per session: re-arming on every loading screen re-rolls the same race.
    Events:On("PLAYER_ENTERING_WORLD", function()
        if restored or restoreArmed then return end
        restoreArmed = true
        C_Timer.After(RESTORE_DELAY, restore)
    end)
    Events:On("QUEST_WATCH_LIST_CHANGED", mirror)
    Events:On("QUEST_TURNED_IN", function(_, questID)
        local list = getList()
        if list and questID then list[questID] = nil end
    end)
end
