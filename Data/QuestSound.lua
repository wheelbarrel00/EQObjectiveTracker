local _, ns = ...

local QuestSound = ns:RegisterModule("QuestSound", {})

-- Midnight can hand back "secret values" that error when indexed by tainted addon code,
-- even though they still report type "string"
local _issecret = _G.issecretvalue

local DEDUP_WINDOW_S = 2
local SCAN_DEBOUNCE  = 0.2

local lastComplete = {}
-- Titles on the complete path and quest IDs on the accept path. One table, because the two key
-- spaces cannot collide and a second would want a second prune loop for nothing.
local recentKeys   = {}
local scratch      = {}
local armed        = false

local function isRecent(key)
    if not key or key == "" then return false end
    local exp = recentKeys[key]
    if not exp then return false end
    if exp > GetTime() then return true end
    recentKeys[key] = nil
    return false
end

local function recordRecent(key)
    if not (key and key ~= "") then return end
    local now = GetTime()
    for k, exp in pairs(recentKeys) do
        if exp <= now then recentKeys[k] = nil end
    end
    recentKeys[key] = now + DEDUP_WINDOW_S
end

-- Read before any work rather than only inside playSound. The scan walks the whole quest log
-- and the chat path matches every system message, so gating at the end paid the feature's
-- full cost while it was switched off.
local function soundEnabled()
    local cfg = ns:GetModule("DB"):Tracker()
    return (cfg and cfg.questSoundEnabled ~= false) and true or false
end

-- No fallback name. This is shared by both paths now, so a default here would mean "if the
-- accept sound is unset, play the COMPLETE one", which is the confusion the separate pair exists
-- to avoid. Media:Play is silent on nil.
local function playFile(name)
    ns:GetModule("Media"):Play(name)
end

local function playSound()
    local cfg = ns:GetModule("DB"):Tracker()
    if not (cfg and cfg.questSoundEnabled ~= false) then return end
    playFile(cfg.questCompleteSound)
end

-- EQ diffs its own quest Cache here. EQOT has none, so the log is walked directly - the
-- transitions detected, and everything downstream of them, are identical.
local function detectTransitions()
    if not ns.Has.QuestLog then return end
    -- Re-prime rather than simply skipping, or every quest completed while the option was
    -- off reads as a fresh transition the moment it is switched back on.
    if not soundEnabled() then
        armed = false
        return
    end

    local n = 0
    local seen = scratch
    wipe(seen)

    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader then
            local id = info.questID
            if id then
                local now = (ns.Has.QuestIsComplete and C_QuestLog.IsComplete(id)) and true or false
                seen[id] = now
                -- == false, not `not lastComplete[id]`: a quest first seen already complete
                -- is nil here and must stay silent, or a cold login fires for the whole log
                if armed and now and lastComplete[id] == false then
                    local title = info.title or ""
                    -- The chat path may already have played this one
                    if not isRecent(title) then
                        n = n + 1
                        recordRecent(title)
                    end
                end
            end
        end
    end

    for id in pairs(lastComplete) do
        if seen[id] == nil then lastComplete[id] = nil end
    end
    for id, v in pairs(seen) do lastComplete[id] = v end

    -- The first pass only primes the table, or every already-complete quest sounds at once
    if not armed then
        armed = true
        return
    end
    if n > 0 then playSound() end
end

local _completePattern
local function completePattern()
    if _completePattern then return _completePattern end
    local fmt = ERR_QUEST_COMPLETE_S
    if type(fmt) ~= "string" or fmt == "" then return nil end
    local SENTINEL = "\1"
    _completePattern = "^" .. fmt
        :gsub("%%s", SENTINEL)
        :gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
        :gsub(SENTINEL, "(.+)")
        .. "$"
    return _completePattern
end

local function onSystemChat(_, msg)
    if not soundEnabled() then return end
    -- msg:match on a secret value throws, and the log scan still catches those quests
    if _issecret and _issecret(msg) then return end
    if type(msg) ~= "string" then return end
    local p = completePattern()
    if not p then return end
    local title = msg:match(p)
    if not title or title == "" then return end
    if isRecent(title) then return end
    recordRecent(title)
    playSound()
end

-- Classic fires (questLogIndex, questID) where retail fires (questID) alone, so the id is read
-- off the LAST slot. Reading slot one outright takes a log index on Classic, itself a perfectly
-- valid quest id belonging to an unrelated quest, which is how that class of bug stays silent.
local function onQuestAccepted(_, a, b)
    local cfg = ns:GetModule("DB"):Tracker()
    QuestSound._lastPayload = ("%s,%s"):format(tostring(a), tostring(b))
    QuestSound._lastAction  = "skipped, switched off"
    if not (cfg and cfg.questAcceptSoundEnabled) then return end

    local questID = b or a
    QuestSound._lastID     = questID
    QuestSound._lastAction = "skipped, no id"
    if not questID then return end

    -- Walking into a world quest or a bonus objective area accepts one with no player action at
    -- all, so those would sound at the zone rather than at a quest. Both are asked because
    -- neither has been measured to imply the other on every flavor.
    QuestSound._lastAction = "skipped, world quest"
    if C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(questID) then return end
    QuestSound._lastAction = "skipped, task quest"
    if C_QuestLog.IsQuestTask  and C_QuestLog.IsQuestTask(questID)  then return end

    -- A shared or auto-accepted quest can arrive twice
    QuestSound._lastAction = "skipped, already sounded"
    if isRecent(questID) then return end
    recordRecent(questID)
    playFile(cfg.questAcceptSound)
    QuestSound._lastAction = "played " .. tostring(cfg.questAcceptSound)
end

-- Six early returns above and every one of them is silence from the player's side, so the ACTION
-- is recorded beside the payload, exactly as Data/AutoTrack.lua does for the same event. Without
-- it, "the accept sound does nothing" has no line to ask a reporter for.
function QuestSound:DebugLine()
    local cfg = ns:GetModule("DB"):Tracker() or {}
    return ("quest sound: complete %s (%s), accept %s (%s) | last accept payload (%s) -> id %s, %s")
        :format(
            (cfg.questSoundEnabled ~= false) and "on" or "off",
            tostring(cfg.questCompleteSound),
            cfg.questAcceptSoundEnabled and "on" or "off",
            tostring(cfg.questAcceptSound),
            self._lastPayload or "none this session",
            tostring(self._lastID),
            self._lastAction or "nothing yet")
end

function QuestSound:OnEnable()
    local Events = ns:GetModule("Events")
    Events:On("QUEST_LOG_UPDATE", function()
        Events:Debounce("eqot.questsound", SCAN_DEBOUNCE, detectTransitions)
    end)
    Events:On("CHAT_MSG_SYSTEM", onSystemChat)
    Events:On("QUEST_ACCEPTED", onQuestAccepted)
end
