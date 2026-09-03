local _, ns = ...

local AutoTrack = ns:RegisterModule("AutoTrack", {})

-- Copied from Data/WatchPersist.lua. A nil answer is ambiguous - not watched, or no
-- GetQuestWatchType on this client - so the readback below asks ns.Has.QuestWatchType first
-- rather than reading a nil as "not watched".
local function watchType(questID)
    if not ns.Has.QuestWatchType then return nil end
    return C_QuestLog.GetQuestWatchType(questID)
end

-- EQ keeps this in its Visibility.lua, but that file is pure frame work in EQOT and calls
-- no quest API. Storage keys and labels still match EQ, only the file differs.
-- Classic fires (questLogIndex, questID) where retail fires (questID) on its own, measured on
-- 1.15.9 as payload (6,967). Slot two is preferred with slot one as the fallback, which is
-- correct under both of those without needing to know which client sent which. Reading slot one
-- outright auto-tracked the LOG INDEX on Classic, itself a valid quest id belonging to some
-- unrelated quest, so nothing errored and the accepted quest was simply never tracked.
local function onQuestAccepted(_, a, b)
    local cfg = ns:GetModule("DB"):General()
    local questID = b or a
    AutoTrack._lastPayload = ("%s,%s"):format(tostring(a), tostring(b))
    AutoTrack._lastID      = questID
    AutoTrack._lastAction  = "no config"
    AutoTrack._lastType    = "n/a, no watch add"
    if not (cfg and questID) then return end

    -- World quest watches are their own system with their own cap and persistence, and a
    -- bonus objective is accepted by walking into its area rather than chosen. Both are asked
    -- because neither implies the other on every flavor, as Data/QuestSound.lua does here too.
    AutoTrack._lastAction = "skipped, world quest"
    if C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(questID) then return end
    AutoTrack._lastAction = "skipped, task quest"
    if C_QuestLog.IsQuestTask and C_QuestLog.IsQuestTask(questID) then return end

    -- Classic owns its tracked set rather than Blizzard's watch list, so this works there now.
    -- It could not before: the flat AddQuestWatch is capped at five and throws a red error on the
    -- sixth, which made auto-tracking every accepted quest a dead end rather than a missing wire.
    -- The module is absent on retail, where the C_QuestLog path below is correct.
    local TrackedSet = ns:GetModule("TrackedSet")
    if TrackedSet then
        local want = cfg.autoTrackAccepted ~= false
        TrackedSet:Set(questID, want)
        AutoTrack._lastAction = want and "tracked" or "untracked"
        AutoTrack._lastType   = "n/a, this client owns its tracked set"
        return
    end

    if cfg.autoTrackAccepted == false then
        local watched = watchType(questID) ~= nil
        if watched and ns.Has.QuestWatchAPI then
            C_QuestLog.RemoveQuestWatch(questID)
            AutoTrack._lastAction = "untracked"
        else
            AutoTrack._lastAction = "left alone, was not watched"
        end
        return
    end

    AutoTrack._lastAction = "skipped, no watch api"
    if not ns.Has.QuestWatchAPI then return end
    -- Forced to MANUAL. AddQuestWatch with no type adds an AUTOMATIC watch, which is what
    -- Blizzard's autoQuestWatch CVar creates, and the engine silently evicts those past a
    -- small cap - so the quest would vanish from the tracker again on its own.
    -- Literal 1 from Data/WatchPersist.lua: a nil type IS the automatic watch refused above.
    local manual = (Enum and Enum.QuestWatchType and Enum.QuestWatchType.Manual) or 1
    AutoTrack._lastType = manual
    local before = watchType(questID)
    C_QuestLog.AddQuestWatch(questID, manual)

    -- AddQuestWatch answers nothing, so the watch is read back rather than the call being
    -- reported as its own outcome. Compared against MANUAL the way Data/WatchPersist.lua
    -- does, never against nil: Automatic is 0, which is not nil, so a nil test calls two
    -- different outcomes "tracked" - a quest autoQuestWatch had already picked up, where
    -- this add is the upgrade rather than a no-op, and a client that took the watch while
    -- ignoring the type, which is the eviction the typed add exists to avoid.
    local after = watchType(questID)
    if not ns.Has.QuestWatchType then
        AutoTrack._lastAction = "add sent, unverifiable on this client"
    elseif after == nil then
        AutoTrack._lastAction = "ADD REFUSED, the client did not take the watch"
    elseif after ~= manual then
        AutoTrack._lastAction = "tracked as AUTOMATIC, the engine can evict it"
    elseif before == manual then
        AutoTrack._lastAction = "already a manual watch, the add changed nothing"
    elseif before ~= nil then
        AutoTrack._lastAction = "tracked, upgraded from an automatic watch"
    else
        AutoTrack._lastAction = "tracked"
    end
end

function AutoTrack:OnEnable()
    ns:GetModule("Events"):On("QUEST_ACCEPTED", onQuestAccepted)
end

-- The payload is printed raw, because which slot carries the quest id differs by flavor and is
-- the kind of thing that gets re-derived wrongly from memory. The ACTION is printed beside it:
-- the id alone says what the handler worked out, not what it did, and every early return here
-- would otherwise read identically to a successful track.
function AutoTrack:DebugLine()
    local cfg = ns:GetModule("DB"):General()
    return ("auto track: %s, set owned %s | last accept payload (%s) -> id %s, %s | watch type %s"):format(
        (cfg and cfg.autoTrackAccepted ~= false) and "on" or "off",
        tostring(ns:GetModule("TrackedSet") ~= nil),
        self._lastPayload or "none this session",
        tostring(self._lastID),
        self._lastAction or "nothing yet",
        tostring(self._lastType))
end
