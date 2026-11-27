local _, ns = ...

-- Which row the player is working on. Classic has no super-track, so a click sets it here. Retail
-- and WoW Forever follow super-track instead, giving Everything Quests the same announcement it
-- turns into a TomTom arrow on Classic.
--
-- Session state on purpose. A Classic login starts with no focus, and where super-track exists it
-- is read at the first loading screen.
local Focus = ns:RegisterModule("Focus", {})

local focusedProvider, focusedID
local dirtyHandlers = {}
local following = false

function Focus:OnDirty(fn)
    dirtyHandlers[#dirtyHandlers + 1] = fn
end

function Focus:Get()
    return focusedProvider, focusedID
end

function Focus:Is(providerID, entryID)
    return focusedProvider ~= nil and focusedProvider == providerID and focusedID == entryID
end

function Focus:Set(providerID, entryID)
    -- Normalized first so a clear cannot be stored as a provider with no entry, which would
    -- make the no-op check below miss and announce a clear over an already empty focus.
    if not entryID then providerID = nil end
    if focusedProvider == providerID and focusedID == entryID then return false end

    -- A clear is announced against the provider that LOST focus, so a listener scoped to one
    -- provider can tell whether the clear concerns it. A move to another provider sends that clear
    -- first, or such a listener keeps following a quest that lost focus.
    local lost = focusedProvider
    focusedProvider, focusedID = providerID, entryID

    local API = ns:GetModule("API")
    if API then
        if providerID and lost and lost ~= providerID then API:NotifyFocus(lost, nil) end
        API:NotifyFocus(providerID or lost, entryID)
    end
    for i = 1, #dirtyHandlers do dirtyHandlers[i]() end
    return true
end

function Focus:Toggle(providerID, entryID)
    if self:Is(providerID, entryID) then return self:Set(nil, nil) end
    return self:Set(providerID, entryID)
end

function Focus:FollowsSuperTrack()
    return following
end

-- For a click on the quest already followed, which Set would pass over as unchanged, so an arrow
-- TomTom removed on arrival could never come back.
function Focus:Resend()
    if not (following and focusedID) then return end
    local API = ns:GetModule("API")
    if API then API:NotifyFocus(focusedProvider, focusedID) end
end

-- A world quest or bonus objective is announced as World Quests', so a listener can tell it from a
-- log quest.
local function providerOf(id)
    local log = C_QuestLog
    if log and ((log.IsWorldQuest and log.IsWorldQuest(id)) or (log.IsQuestTask and log.IsQuestTask(id))) then
        return "worldquests"
    end
    return "quests"
end

local function followSuperTrack()
    local id = C_SuperTrack.GetSuperTrackedQuestID()
    if not (id and id > 0) then
        Focus:Set(nil, nil)
        return
    end
    Focus:Set(providerOf(id), id)
end

-- Defined only where it does something, so /eqot modules never offers a switch that changes nothing.
if ns.Has.SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
    function Focus:OnEnable()
        local Events = ns:GetModule("Events")
        Events:On("SUPER_TRACKING_CHANGED", followSuperTrack)
        -- Not read at enable: Everything Quests registers its listener after this runs, and Set is
        -- silent on an unchanged focus, so an early read would keep the login's quest from it.
        Events:On("PLAYER_ENTERING_WORLD", followSuperTrack)
        following = true
    end
end
