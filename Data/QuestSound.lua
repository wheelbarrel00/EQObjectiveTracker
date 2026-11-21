local _, ns = ...

local QuestSound = ns:RegisterModule("QuestSound", {})

local QuestCache = ns:GetModule("QuestCache")

-- Midnight can hand back "secret values" that error when indexed by tainted addon code,
-- even though they still report type "string"
local _issecret = _G.issecretvalue

local DEDUP_WINDOW_S = 2
-- Events:Debounce is leading-armed and trailing-fire, so the scan runs this long after the
-- FIRST event of a burst and this value is an exposure WINDOW, not just a delay. Anything that
-- both starts and finishes inside it is lost rather than deferred: a quest accepted and
-- completed within the window is first SEEN complete, which `lastComplete[id] == false`
-- deliberately refuses, and one that completes and then leaves the log within it is never
-- visited, so the scan prunes its record instead of ever seeing it finish. Widening this to 1.0 to cut the walk's cost silently took the
-- chime away from auto-completing content, which is the sound the world quest exclusion was
-- declined in order to keep. The walk is expensive and this is not the lever for it.
local SCAN_DEBOUNCE  = 0.2

-- Ceiling for the Classic walk, matching Data/Providers/QuestsClassic.lua. GetNumQuestLogEntries
-- counts only the VISIBLE rows there, so a collapsed header hides quests that are still
-- perfectly addressable by index.
local MAX_LOG_INDEX = 75

local lastComplete = {}
-- Per quest, how many objectives are finished and the sum of their counts, a bar's percentage
-- included. Flat and swapped each scan, so keeping them needs no new table.
local lastFin, lastSum, scratchFin, scratchSum = {}, {}, {}, {}
-- Keys are prefixed per path. Accept and turn in are both quest IDs, and an auto-completing
-- quest can pass through both inside the dedup window.
local recentKeys   = {}
local scratch      = {}
local armed        = false

-- The accept path records the action behind each of its silent early returns. The objectives
-- path recorded nothing at all, so "it only sounds once I hand the quest in" had no line to
-- read. Nothing here is formatted on the scan path: the strings are built in DebugLine.
local stats = {
    scans = 0, walked = 0, done = 0, derived = 0, failed = 0, held = 0,
    scanSaw = 0, scanPlayed = 0, turnIns = 0,
    finSeen = 0, finPlayed = 0, progSeen = 0, progPlayed = 0,
    surface = "no scan yet",
}

local LOG_MAX = 6
local log     = {}

-- A secret value throws when it reaches string.format, and DebugLine has to report rather than
-- raise, so a title is neutralized on the way into the log rather than at every print.
local function safeText(v)
    if _issecret and _issecret(v) then return "<secret>" end
    return tostring(v or "")
end

local function logEvent(path, title, action)
    log[#log + 1] = { path = path, title = safeText(title), action = action, at = GetTime() }
    if #log > LOG_MAX then table.remove(log, 1) end
end

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

-- Read before any work rather than only at the play below. The scan walks the whole quest log, so
-- gating at the end paid the feature's full cost while it was switched off.
local function soundEnabled()
    local cfg = ns:GetModule("DB"):Tracker()
    if not cfg then return false end
    return cfg.questSoundEnabled ~= false or cfg.objectiveDoneSoundEnabled == true
        or cfg.objectiveProgressSoundEnabled == true
end

-- No fallback name. Three paths share this now, so a default here would mean "if the turn in
-- sound is unset, play the objectives one". Media:Play is silent on nil.
local function playFile(name)
    ns:GetModule("Media"):Play(name)
end

local function readObjectives(id)
    if not ns.Has.QuestObjectives then return 0, 0, 0 end
    local objs = C_QuestLog.GetQuestObjectives(id)
    local n    = objs and #objs or 0
    local fin, sum = 0, 0
    for i = 1, n do
        local o = objs[i]
        if o.finished then fin = fin + 1 end
        sum = sum + (tonumber(o.numFulfilled) or 0)
        -- A bar reading 0 of 1 keeps its fill in neither count, so its percentage is the progress
        if o.type == "progressbar" and o.numRequired ~= 100 then
            local QP = ns:GetModule("QuestProgress")
            local pct = QP and QP:PercentQuiet(id)
            sum = sum + (tonumber(pct) or 0)
        end
    end
    return n, fin, sum
end

-- Blizzard's own complete flag is not enough: it leaves empty objectives on some quests that
-- then never flip the flag, so the answer is derived from "are all objectives finished" whenever
-- the flag is silent. A quest with NO objectives is excluded rather than counted as all-done,
-- because one whose objectives have not streamed in yet is indistinguishable from one that never
-- had any.
local function objectivesDone(id)
    local n, fin = readObjectives(id)
    return n > 0 and fin == n
end

-- pendingShown counts the completions of quests the tracker draws, the only ones the two
-- objective sounds hear.
local pending, pendingShown, pendingFin, pendingProg = 0, 0, 0, 0

local function visit(id, title, flag, failed, hidden)
    stats.walked = stats.walked + 1
    if failed then stats.failed = stats.failed + 1 end

    local now = flag
    local n, fin, sum = 0, 0, 0
    -- A FAILED quest is refused the derived answer as well. Both surfaces already report it as
    -- not complete - retail through IsComplete, Classic through the -1 in slot 6 - and deriving
    -- it anyway hands back true for a failed escort whose objectives all read finished, which is
    -- the one state where the two answers disagree.
    if not now and not failed then
        n, fin, sum = readObjectives(id)
        now = n > 0 and fin == n
        if now then stats.derived = stats.derived + 1 end
    end
    -- Guards a complete quest reading incomplete across a loading screen: writing that in makes
    -- the SAME quest read as a fresh completion next scan. Held rather than skipped, so a real
    -- completion inside the window is still seen on the pass after it.
    if not now and lastComplete[id] and not QuestCache:IsReady() then
        now = true
        stats.held = stats.held + 1
    end

    scratch[id] = now
    if now then stats.done = stats.done + 1 end

    -- == false, not `not lastComplete[id]`: a quest first seen already complete is nil here and
    -- must stay silent, or a quest that arrives finished sounds as though it just finished
    if armed and now and lastComplete[id] == false then
        pending = pending + 1
        if not hidden then pendingShown = pendingShown + 1 end
        stats.scanSaw = stats.scanSaw + 1
        -- "done", not "played": one chime plays per SCAN while this is written per QUEST,
        -- so three finishing together would otherwise read as three sounds on the very line
        -- someone checks to answer "did it play". The counters carry that.
        logEvent("scan", title, "done")
    end

    -- A hidden quest is never drawn (world quests and bonus areas are not hidden here), and a failed
    -- or flagged-complete one is not read, so their records go and a later reading starts fresh. An
    -- empty reading keeps the record.
    if hidden or failed or flag then return end
    if n == 0 then
        scratchFin[id], scratchSum[id] = lastFin[id], lastSum[id]
        return
    end
    -- Until the log is confirmed a reading is recorded and never heard, and a drop is held, so a
    -- login or a loading screen reading low first sounds nothing on the way back up.
    local oldFin, oldSum = lastFin[id], lastSum[id]
    local ready = QuestCache:IsReady()
    if oldFin and not ready and (fin < oldFin or sum < oldSum) then
        fin, sum = oldFin, oldSum
    end
    if armed and ready and oldFin ~= nil then
        if fin > oldFin then
            pendingFin = pendingFin + 1
            stats.finSeen = stats.finSeen + 1
        elseif sum > oldSum then
            pendingProg = pendingProg + 1
            stats.progSeen = stats.progSeen + 1
        end
    end
    scratchFin[id], scratchSum[id] = fin, sum
end

-- Retail answers on C_QuestLog and Classic answers on the flat globals, and NONE of the three
-- this used to require exist there. That is not a degraded reading, it is no reading at all:
-- the scan returned at its first line on every Classic pass since the feature shipped, leaving
-- the sound to a chat message that fires at the HAND IN. Measured 2026-08-30 in Redridge, where
-- the status read `0 scans, armed no` with the chat match landing on the same second as
-- QUEST_TURNED_IN.
local function walkQuestLog()
    if ns.Has.QuestLog then
        stats.surface = "C_QuestLog"
        local n = C_QuestLog.GetNumQuestLogEntries()
        for i = 1, n or 0 do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID then
                local flag   = ns.Has.QuestIsComplete and C_QuestLog.IsComplete(info.questID)
                local failed = ns.Has.QuestIsFailed and C_QuestLog.IsFailed(info.questID)
                -- A bonus area and a world quest you stand in sit in the log hidden, and they are drawn
                local hidden = info.isHidden and not (info.isTask
                    or (C_QuestLog.IsQuestTask and C_QuestLog.IsQuestTask(info.questID))
                    or (C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(info.questID)))
                visit(info.questID, info.title, flag and true or false, failed and true or false,
                      hidden and true or false)
            end
        end
        return true
    end

    if type(GetQuestLogTitle) ~= "function" then
        stats.surface = "none, no quest log api"
        return false
    end
    stats.surface = "GetQuestLogTitle"
    -- 1 title, 4 isHeader, 6 isComplete, 8 questID, measured on 1.15.9 and 2.5.6. Slot 6 carries
    -- -1 for FAILED, which is not complete.
    for i = 1, MAX_LOG_INDEX do
        local title, _, _, isHeader, _, isComplete, _, id = GetQuestLogTitle(i)
        if not title then break end
        if not isHeader and id and id ~= 0 then
            visit(id, title, (isComplete and isComplete ~= 0 and isComplete ~= -1) and true or false,
                  isComplete == -1)
        end
    end
    return true
end

local function detectTransitions()
    -- Re-prime rather than simply skipping, or every quest completed while the option was
    -- off reads as a fresh transition the moment it is switched back on.
    if not soundEnabled() then
        armed = false
        return
    end

    pending, pendingShown, pendingFin, pendingProg = 0, 0, 0, 0
    stats.scans    = stats.scans + 1
    stats.scanAt   = GetTime()
    stats.walked   = 0
    stats.done     = 0
    stats.derived  = 0
    stats.failed   = 0
    wipe(scratch)
    wipe(scratchFin)
    wipe(scratchSum)

    if not walkQuestLog() then return end

    -- A quest missing from ONE scan must keep a recorded completion while the gate is
    -- closed, because that record is what the hold in visit reads. Pruned, the quest
    -- returns reading incomplete and the correct value arriving next scan is the same
    -- false to true the chime fires on. A recorded false still prunes.
    local holding = not QuestCache:IsReady()
    for id in pairs(lastComplete) do
        if scratch[id] == nil and not (holding and lastComplete[id]) then
            lastComplete[id] = nil
        end
    end
    for id, v in pairs(scratch) do lastComplete[id] = v end
    if holding then
        for id, v in pairs(lastFin) do
            if scratch[id] == nil then scratchFin[id], scratchSum[id] = v, lastSum[id] end
        end
    end
    lastFin, scratchFin = scratchFin, lastFin
    lastSum, scratchSum = scratchSum, lastSum

    -- Belt and braces. The gate in visit already refuses while armed is false, so this can
    -- never be what keeps a cold login quiet - it is a second floor under that gate.
    if not armed then
        armed = true
        return
    end
    -- One sound a scan: the biggest that happened and is switched on. A completed quest the tracker
    -- draws counts as a finished objective and as progress too, so a smaller switch still hears it.
    local cfg = ns:GetModule("DB"):Tracker()
    if pending > 0 and cfg.questSoundEnabled ~= false then
        stats.scanPlayed   = stats.scanPlayed + 1
        stats.scanPlayedAt = GetTime()
        playFile(cfg.questCompleteSound)
    elseif pendingShown + pendingFin > 0 and cfg.objectiveDoneSoundEnabled == true then
        stats.finPlayed = stats.finPlayed + 1
        playFile(cfg.objectiveDoneSound)
    elseif pendingShown + pendingFin + pendingProg > 0 and cfg.objectiveProgressSoundEnabled == true then
        stats.progPlayed = stats.progPlayed + 1
        playFile(cfg.objectiveProgressSound)
    end
end

-- Classic fires (questLogIndex, questID) where retail fires (questID) alone, so the id is read
-- off the LAST slot. Reading slot one outright takes a log index on Classic, itself a perfectly
-- valid quest id belonging to an unrelated quest, which is how that class of bug stays silent.
local function onQuestAccepted(_, a, b)
    local cfg = ns:GetModule("DB"):Tracker()
    local questID = b or a
    QuestSound._lastPayload = ("%s,%s"):format(tostring(a), tostring(b))
    QuestSound._lastID      = questID
    QuestSound._lastAction  = "skipped, switched off"
    if not (cfg and cfg.questAcceptSoundEnabled) then return end

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
    if isRecent("a" .. questID) then return end
    recordRecent("a" .. questID)
    playFile(cfg.questAcceptSound)
    QuestSound._lastAction = "played " .. tostring(cfg.questAcceptSound)
end

-- The hand in has its own event and its own option. It used to be reached only by accident, as
-- the ERR_QUEST_COMPLETE_S chat line that was standing in for the objectives sound, which is why
-- that line and its pattern are gone: the message is measured to arrive at the quest giver, and
-- matching every system message to guess at a moment the client announces outright is worse on
-- every axis.
local function onQuestTurnedIn(_, questID)
    local cfg = ns:GetModule("DB"):Tracker()
    stats.turnIns = stats.turnIns + 1
    if not (cfg and cfg.questTurnInSoundEnabled) then
        logEvent("turnin", tostring(questID), "switched off")
        return
    end
    if not questID then
        logEvent("turnin", tostring(questID), "skipped, no id")
        return
    end

    -- The same two gates the accept path spends, for the same reason. A world quest or a bonus
    -- objective hands itself in where it completes, with no quest giver in it, and this option's
    -- own wording promises the hand in - so without these one of them chimes in a field, and
    -- twice over while the objectives sound is on, which it is by default.
    if C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(questID) then
        logEvent("turnin", tostring(questID), "skipped, world quest")
        return
    end
    if C_QuestLog.IsQuestTask and C_QuestLog.IsQuestTask(questID) then
        logEvent("turnin", tostring(questID), "skipped, task quest")
        return
    end

    if isRecent("t" .. questID) then
        logEvent("turnin", tostring(questID), "skipped, already sounded")
        return
    end
    recordRecent("t" .. questID)
    logEvent("turnin", tostring(questID), "played")
    playFile(cfg.questTurnInSound)
end

-- Every early return on the accept and turn in paths is silence from the player's side, so the
-- ACTION is recorded beside the payload, exactly as Data/AutoTrack.lua does for the same event. The objectives half names the SURFACE it walked for the same reason: a scan that found
-- no quest log to read at all reported identically to one that read a log with nothing finished
-- in it, and that is precisely the bug this file shipped with on Classic.
function QuestSound:DebugLine()
    local cfg = ns:GetModule("DB"):Tracker() or {}
    local at  = GetTime()
    local function ago(t)
        return t and ("%.0fs"):format(at - t) or "never"
    end

    -- Walked here rather than in the scan, because it asks what the log looks like RIGHT NOW and
    -- the scan already pays one GetQuestObjectives per unfinished quest. This is the derived
    -- case on screen: quests the objectives call finished while Blizzard's own flag does not.
    local mismatch, firstMismatch = 0, nil
    -- Only a recorded false lets visit chime, and no other line here shows which record a
    -- complete quest carries. A nil means visit records its next complete reading in silence.
    local recDone, recPending, recNone, firstNone = 0, 0, 0, nil
    local function note(id, title, flag, failed)
        local derived = false
        if not flag and not failed then derived = objectivesDone(id) end
        if derived then
            mismatch = mismatch + 1
            firstMismatch = firstMismatch or ('"%s" (%s)'):format(safeText(title), tostring(id))
        end
        if not (flag or derived) then return end
        local rec = lastComplete[id]
        if rec == true then
            recDone = recDone + 1
        elseif rec == false then
            recPending = recPending + 1
        else
            recNone = recNone + 1
            firstNone = firstNone or ('"%s" (%s)'):format(safeText(title), tostring(id))
        end
    end
    if ns.Has.QuestLog then
        local n = C_QuestLog.GetNumQuestLogEntries()
        for i = 1, n or 0 do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID then
                note(info.questID, info.title,
                     ns.Has.QuestIsComplete and C_QuestLog.IsComplete(info.questID),
                     ns.Has.QuestIsFailed and C_QuestLog.IsFailed(info.questID))
            end
        end
    elseif type(GetQuestLogTitle) == "function" then
        for i = 1, MAX_LOG_INDEX do
            local title, _, _, isHeader, _, isComplete, _, id = GetQuestLogTitle(i)
            if not title then break end
            if not isHeader and id and id ~= 0 then
                note(id, title, isComplete and isComplete ~= 0 and isComplete ~= -1,
                     isComplete == -1)
            end
        end
    end

    local events = {}
    for i = 1, #log do
        local e = log[i]
        events[i] = ("%s/%s \"%s\" %s"):format(e.path, e.action, e.title, ago(e.at))
    end

    local lines = {
        ("quest sound: objectives %s (%s), accept %s (%s), turn in %s (%s), finished %s (%s), progress %s (%s)")
            :format(
            (cfg.questSoundEnabled ~= false) and "on" or "off",
            tostring(cfg.questCompleteSound),
            cfg.questAcceptSoundEnabled and "on" or "off",
            tostring(cfg.questAcceptSound),
            cfg.questTurnInSoundEnabled and "on" or "off",
            tostring(cfg.questTurnInSound),
            cfg.objectiveDoneSoundEnabled == true and "on" or "off",
            tostring(cfg.objectiveDoneSound),
            cfg.objectiveProgressSoundEnabled == true and "on" or "off",
            tostring(cfg.objectiveProgressSound)),
        ("objectives path: armed %s, log via %s, IsComplete api %s"):format(
            armed and "yes" or "no", stats.surface, tostring(ns.Has.QuestIsComplete)),
        ("%d scans, %d quests walked, %d read done (%d of them from the objectives), %d read failed, last scan %s")
            :format(stats.scans, stats.walked, stats.done, stats.derived, stats.failed,
                    ago(stats.scanAt)),
        ("scan saw %d, played %d (last %s) | turn ins seen %d | %d held over a loading screen")
            :format(stats.scanSaw, stats.scanPlayed, ago(stats.scanPlayedAt), stats.turnIns,
                    stats.held),
        ("objective sounds: finished seen %d, played %d | progress seen %d, played %d"):format(
            stats.finSeen, stats.finPlayed, stats.progSeen, stats.progPlayed),
        ("done by objectives but not by Blizzard's flag right now: %d%s"):format(
            mismatch, firstMismatch and (" -> " .. firstMismatch) or ""),
        ("complete right now: %d recorded complete, %d recorded unfinished, %d unrecorded%s")
            :format(recDone, recPending, recNone, firstNone and (" -> " .. firstNone) or ""),
        ("last sound: %s"):format(ns:GetModule("Media"):LastPlayLine()),
        ("recent: %s"):format(
            (#log > 0) and table.concat(events, " | ") or "nothing this session"),
        ("last accept payload (%s) -> id %s, %s"):format(
            self._lastPayload or "none this session",
            tostring(self._lastID),
            self._lastAction or "nothing yet"),
    }
    return table.concat(lines, "\n      ")
end

function QuestSound:OnEnable()
    local Events = ns:GetModule("Events")
    Events:On("QUEST_LOG_UPDATE", function()
        Events:Debounce("eqot.questsound", SCAN_DEBOUNCE, detectTransitions)
    end)
    Events:On("QUEST_ACCEPTED", onQuestAccepted)
    Events:On("QUEST_TURNED_IN", onQuestTurnedIn)
end
