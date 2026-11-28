local _, ns = ...

-- /eqot next and /eqot prev: which quest comes next in an order, the tracked quests for when the
-- window draws none, and the follow a row click makes. The UI hands in the drawn order.
local FollowWalk = ns:RegisterModule("FollowWalk", {})

-- The Classic log walk's ceiling, as Data/QuestItems.lua's: the count call drops collapsed rows.
local MAX_LOG_INDEX = 75

function FollowWalk:Pick(ids, n, currentID, dir)
    if not n or n < 1 then return nil end
    local at
    if currentID then
        for i = 1, n do
            if ids[i] == currentID then at = i break end
        end
    end
    if not at then return dir > 0 and 1 or n end
    return ((at - 1 + dir) % n) + 1
end

function FollowWalk:WatchOrder(ids, provs)
    local n = 0
    local log = C_QuestLog
    if ns.Has.QuestWatchAPI and log and log.GetQuestIDForQuestWatchIndex then
        for i = 1, (log.GetNumQuestWatches() or 0) do
            local id = log.GetQuestIDForQuestWatchIndex(i)
            if id then n = n + 1; ids[n], provs[n] = id, "quests" end
        end
        if ns.Has.WorldQuests then
            for i = 1, (log.GetNumWorldQuestWatches() or 0) do
                local id = log.GetQuestIDForWorldQuestWatchIndex(i)
                if id then n = n + 1; ids[n], provs[n] = id, "worldquests" end
            end
        end
    elseif not ns:UsesBlizzardTracker() and ns:GetModule("TrackedSet") and type(GetQuestLogTitle) == "function" then
        -- Era and TBC empty the game's watch list while EQOT's tracker runs, and keep their own set.
        local set = ns:GetModule("TrackedSet")
        for i = 1, MAX_LOG_INDEX do
            local title, _, _, isHeader, _, _, _, id = GetQuestLogTitle(i)
            if not title then break end
            if not isHeader and id and id > 0 and set:IsTracked(id) ~= false then
                n = n + 1; ids[n], provs[n] = id, "quests"
            end
        end
    elseif type(GetNumQuestWatches) == "function" and type(GetQuestIndexForWatch) == "function"
            and type(GetQuestLogTitle) == "function" then
        for i = 1, (GetNumQuestWatches() or 0) do
            local index = GetQuestIndexForWatch(i)
            if index then
                local _, _, _, _, _, _, _, id = GetQuestLogTitle(index)
                if id and id > 0 then n = n + 1; ids[n], provs[n] = id, "quests" end
            end
        end
    end
    for i = n + 1, #ids do ids[i], provs[i] = nil, nil end
    return n
end

function FollowWalk:Follow(providerID, questID)
    if ns.Has.SuperTrack then
        C_SuperTrack.SetSuperTrackedQuestID(questID)
    else
        ns:GetModule("Focus"):Set(providerID, questID)
    end
end
