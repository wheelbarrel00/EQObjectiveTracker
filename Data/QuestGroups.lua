local _, ns = ...

local QuestGroups = ns:RegisterModule("QuestGroups", {})

-- Lifted out of Data/Providers/WorldQuests.lua when the quests provider needed the same
-- answer. It is one cache and one timer for both, rather than two copies of a call this
-- project has already bisected once - see the note on drain below.

local RESOLVE_DELAY = 1

-- CanCreateQuestGroup, never GetActivityIDForQuestID - the latter returns truthy for
-- ordinary world quests too, which would put the eye on every row.
local cache = {}
local pending, queued = {}, false
local recheck, rechecked = {}, {}
local listeners = {}

local function ask(questID)
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
local function drain()
    queued = false
    local changed, again = false, false
    for qid in pairs(pending) do
        pending[qid] = nil
        local answer = ask(qid)
        if cache[qid] ~= answer then changed = true end
        cache[qid] = answer
        -- A false is either a real no or activity data that has not streamed in yet, and the
        -- two are indistinguishable here, so each quest is re-asked exactly once. Two calls per
        -- quest at most. The drain fires a second after login against the whole quest log,
        -- which is the window where that data is still loading.
        if answer == false and not rechecked[qid] then
            rechecked[qid] = true
            recheck[#recheck + 1] = qid
        end
    end
    -- Queued after the walk rather than inside it, because adding a key while traversing the
    -- same table is undefined
    for i = #recheck, 1, -1 do
        pending[recheck[i]] = true
        recheck[i] = nil
        again = true
    end
    if again and not queued then
        queued = true
        C_Timer.After(RESOLVE_DELAY, drain)
    end
    if not changed then return end
    for i = 1, #listeners do
        local ok, err = pcall(listeners[i])
        if not ok then geterrorhandler()(err) end
    end
end

-- A quest is eyeless for one tick the first time it appears, which is invisible in practice
function QuestGroups:CanCreate(questID)
    if not questID then return false end
    local cached = cache[questID]
    if cached ~= nil then return cached end

    pending[questID] = true
    if not queued then
        queued = true
        C_Timer.After(RESOLVE_DELAY, drain)
    end
    return false
end

-- Called by each provider's notifyDirty, so a resolved answer reaches the screen. Data may
-- never call Tracker:Refresh itself.
function QuestGroups:OnResolved(fn)
    listeners[#listeners + 1] = fn
end

-- Quest IDs get recycled, so an ID seen removed is dropped rather than letting the next quest
-- under it inherit this answer. Only WorldQuests calls this, and its handler fires for every
-- removed id rather than only its own, so the quests provider rides on that. PruneExcept below
-- is what covers the case neither event reaches, which is a world quest expiring.
function QuestGroups:Forget(questID)
    if questID then
        cache[questID] = nil
        pending[questID] = nil
        rechecked[questID] = nil
    end
end

-- Bounded by the live entries the callers still have, the way the atlas cache is. Without it
-- this grows for every quest walked past for the session, and a recycled ID inherits an answer
-- that no event ever cleared. Called from WorldQuests:GetEntries.
--
-- keep has to answer for BOTH providers. Pruning against one provider's entries alone evicts
-- the other's, which re-asks on its next pass and rearms the timer, so the eye flickers and
-- the cache never settles.
function QuestGroups:PruneExcept(keep)
    for qid in pairs(cache) do
        if not keep(qid) then
            cache[qid] = nil
            rechecked[qid] = nil
        end
    end
end

function QuestGroups:Find(questID)
    if LFGListUtil_FindQuestGroup and questID then LFGListUtil_FindQuestGroup(questID) end
end

function QuestGroups:DebugLine()
    local n, p = 0, 0
    for _ in pairs(cache) do n = n + 1 end
    for _ in pairs(pending) do p = p + 1 end
    return ("quest groups: %d cached, %d pending, %d listener(s)"):format(n, p, #listeners)
end
