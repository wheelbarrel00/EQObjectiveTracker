local _, ns = ...

-- Temporary cross-flavor measurement command, added for the Classic port. It creates no
-- frames, and every PROBED global is reached through _G with a variable name, so probing a
-- new one needs no .luacheckrc entry. The build number it prints is reported only - nothing
-- in this addon may branch on a build number or a project id.
local Probe = ns:RegisterModule("FlavorProbe", {})
local Util  = ns.Util

local GLOBALS = {
    "ObjectiveTrackerFrame", "QuestWatchFrame", "WatchFrame",
    "BackdropTemplateMixin", "GetBuildInfo", "GetLocale",
    "Questie", "QuestieTracker", "Questie_BaseFrame",
}

-- The quest log surface, both spellings. Retail moved these into C_QuestLog. Classic kept
-- the flat globals for years. Which set answers decides whether the Quests provider can
-- work at all on this client, so both are listed rather than assumed.
local QUEST_API = {
    "C_QuestLog.GetNumQuestLogEntries", "C_QuestLog.GetInfo",
    "C_QuestLog.GetQuestObjectives", "C_QuestLog.GetQuestWatchType",
    "C_QuestLog.AddQuestWatch", "C_QuestLog.RemoveQuestWatch",
    "C_QuestLog.IsComplete", "C_QuestLog.IsFailed",
    "C_QuestLog.GetQuestTagInfo", "C_QuestLog.GetLogIndexForQuestID",
    "C_QuestLog.GetQuestIDForLogIndex", "C_QuestLog.SetSelectedQuest",
    "C_QuestLog.GetSelectedQuest", "C_QuestLog.GetDistanceSqToQuest",
    "C_QuestLog.GetTitleForQuestID", "C_QuestLog.IsQuestFlaggedCompleted",
    "GetNumQuestLogEntries", "GetQuestLogTitle", "SelectQuestLogEntry",
    "GetQuestLogSelection", "GetNumQuestLeaderBoards", "GetQuestLogLeaderBoard",
    "GetQuestLogIndexByID", "GetQuestLink", "GetQuestLogSpecialItemInfo",
    "IsQuestWatched", "AddQuestWatch", "RemoveQuestWatch",
    "GetNumQuestWatches", "GetQuestIndexForWatch", "IsQuestComplete",
    "GetQuestTimers", "GetQuestIndexForTimer", "GetQuestLogTimeLeft",
    "GetQuestLogPushable", "QuestUtils_GetQuestName", "QuestUtils_IsQuestWorldQuest",
    "C_SuperTrack.SetSuperTrackedQuestID", "C_SuperTrack.GetSuperTrackedQuestID",
    "GetAchievementInfo", "GetAchievementNumCriteria", "GetAchievementCriteriaInfo",
    "GetTrackedAchievements", "C_ContentTracking.GetTrackedIDs",
}

local ENUM_TABLES = {
    "QuestFrequency", "QuestWatchType", "QuestClassification", "QuestTag",
}

local ATLASES = {
    "UI-QuestPoi-OuterGlow", "UI-QuestPoi-QuestNumber",
    "UI-QuestPoi-QuestNumber-SuperTracked", "UI-QuestPoiCampaign-OuterGlow",
    "UI-QuestPoiCampaign-QuestNumber", "UI-QuestIcon-TurnIn-Normal",
    "Quest-In-Progress-Icon-yellow", "Worldquest-icon",
    -- UI/Row.lua writes this one as an inline |A:...|a escape on every completed objective
    "common-icon-checkmark",
}

local TEXTURES = {
    "Interface/WorldMap/UI-QuestPoi-NumberIcons",
    "Interface/GossipFrame/AvailableQuestIcon",
    "Interface/GossipFrame/ActiveQuestIcon",
    -- Candidate replacements for the checkmark atlas, both older than the atlas system
    "Interface/Buttons/UI-CheckBox-Check",
    "Interface/RaidFrame/ReadyCheck-Ready",
}

local function resolve(path)
    local obj = _G
    for part in path:gmatch("[^.]+") do
        if type(obj) ~= "table" then return nil end
        obj = obj[part]
    end
    return obj
end

local function describe(v)
    if v == nil then return "nil" end
    if type(v) == "table" and type(v.GetObjectType) == "function"
       and type(v.IsShown) == "function" then
        return ("%s shown=%s"):format(tostring(v:GetObjectType()), tostring(v:IsShown()))
    end
    return type(v)
end

local scratch

local function resolves(path)
    if not scratch then
        scratch = UIParent:CreateTexture(nil, "BACKGROUND")
        scratch:Hide()
    end
    scratch:SetTexture(nil)
    scratch:SetTexture(path)
    return tostring(scratch:GetTexture())
end

local function emit(list, per)
    local buf = {}
    for i = 1, #list do
        buf[#buf + 1] = list[i]
        if #buf == per or i == #list then
            ns:Print("  " .. table.concat(buf, "   "))
            for k = #buf, 1, -1 do buf[k] = nil end
        end
    end
end

local function countAndPack(...)
    return select("#", ...), { ... }
end

-- Return signatures differ by flavor and existence alone cannot tell you the shape, so
-- the Classic quest log is CALLED here and its actual returns are printed. Everything is
-- pcall wrapped: a probe that errors tells you nothing.
local function callDump(label, path, ...)
    local fn = resolve(path)
    if type(fn) ~= "function" then
        ns:Print(("  %s: %s ABSENT"):format(label, path))
        return
    end
    -- Counted with select('#') rather than '#' on the table: a probed function returning
    -- nil in any slot leaves a hole, and '#' finds a border rather than the count, so the
    -- tuple would print short and read as a genuinely shorter return. This file's output is
    -- what gets recorded as ground truth, so it must not be able to lie. Packed in one call
    -- because the probed function must not be invoked twice.
    local n, packed = countAndPack(pcall(fn, ...))
    if not packed[1] then
        ns:Print(("  %s: %s RAISED - %s"):format(label, path, tostring(packed[2])))
        return
    end
    local out = {}
    for i = 2, n do
        local v = packed[i]
        out[#out + 1] = ("[%d]=%s(%s)"):format(i - 1, type(v), tostring(v))
    end
    if #out == 0 then out[1] = "no return values" end
    ns:Print(("  %s: %s"):format(label, table.concat(out, " ")))
end

function Probe:DumpQuestLog()
    ns:Print("live quest log (actual return values):")
    callDump("GetNumQuestLogEntries()", "GetNumQuestLogEntries")
    for i = 1, 3 do
        callDump(("GetQuestLogTitle(%d)"):format(i), "GetQuestLogTitle", i)
    end
    callDump("GetNumQuestWatches()", "GetNumQuestWatches")
    callDump("GetQuestIndexForWatch(1)", "GetQuestIndexForWatch", 1)
    callDump("GetQuestLogSelection()", "GetQuestLogSelection")
    callDump("GetNumQuestLeaderBoards(1)", "GetNumQuestLeaderBoards", 1)
    callDump("GetQuestLogLeaderBoard(1,1)", "GetQuestLogLeaderBoard", 1, 1)
    -- GetQuestTimers answers per RUNNING timer, so with no timed quest in the log it prints an
    -- EMPTY tuple that reads exactly like a healthy result. Not every escort is timed and the
    -- clock starts when one begins, so leave a detector running rather than hunting content.
    callDump("GetQuestTimers()", "GetQuestTimers")
    callDump("GetQuestIndexForTimer(1)", "GetQuestIndexForTimer", 1)
    callDump("GetQuestLogTimeLeft()", "GetQuestLogTimeLeft")

    ns:Print("abandon and tag api:")
    local abandon = {}
    for _, path in ipairs({ "SetAbandonQuest", "GetAbandonQuest", "AbandonQuest",
                            "GetAbandonQuestItems", "GetQuestTagInfo",
                            "C_QuestLog.SetAbandonQuest", "C_QuestLog.GetAbandonQuest",
                            "C_QuestLog.GetQuestsOnMap", "GetQuestLogQuestText" }) do
        abandon[#abandon + 1] = ("%s=%s"):format(path, type(resolve(path)))
    end
    emit(abandon, 2)
end

local MAX_WATCH_ROWS = 12

-- Printed as value(type) rather than as a coerced boolean. Reading a truthiness here
-- would destroy the one thing this probe exists to measure.
local function callStr(fn, ...)
    if type(fn) ~= "function" then return "absent" end
    local ok, v = pcall(fn, ...)
    if not ok then return "RAISED" end
    return ("%s(%s)"):format(tostring(v), type(v))
end

-- /eqot status reported every quest watched on Classic Era while GetNumQuestWatches()
-- reported none, and those cannot both be true. The watch state is read from both ends
-- here: per log index, and from the watch list itself.
function Probe:DumpWatchState()
    local numEntries  = resolve("GetNumQuestLogEntries")
    local getTitle    = resolve("GetQuestLogTitle")
    local byID        = resolve("GetQuestLogIndexByID")
    local watched     = resolve("IsQuestWatched")
    local numWatches  = resolve("GetNumQuestWatches")
    local idxForWatch = resolve("GetQuestIndexForWatch")

    ns:Print("watch state, per quest:")
    if type(numEntries) ~= "function" or type(getTitle) ~= "function" then
        ns:Print("  the flat quest log globals are absent on this client")
        return
    end

    local total, rows = numEntries() or 0, 0
    for i = 1, total do
        local t = { getTitle(i) }
        local id = t[8]
        if not t[4] and id and id ~= 0 and rows < MAX_WATCH_ROWS then
            rows = rows + 1
            local mapped = nil
            if type(byID) == "function" then
                local ok, v = pcall(byID, id)
                mapped = ok and v or nil
            end
            ns:Print(("  walk=%d id=%s byID=%s watched(walk)=%s watched(byID)=%s  %s")
                :format(i, tostring(id), callStr(byID, id),
                        callStr(watched, i),
                        mapped and callStr(watched, mapped) or "n/a",
                        tostring(t[1]):sub(1, 24)))
        end
    end

    ns:Print("watch state, from the watch list:")
    ns:Print(("  log entries=%d, rows shown=%d, GetNumQuestWatches()=%s")
        :format(total, rows, callStr(numWatches)))
    local n = nil
    if type(numWatches) == "function" then
        local ok, v = pcall(numWatches)
        n = ok and type(v) == "number" and v or nil
    end
    for k = 1, math.min(n or 0, MAX_WATCH_ROWS) do
        ns:Print(("  GetQuestIndexForWatch(%d)=%s"):format(k, callStr(idxForWatch, k)))
    end
end

-- Mutates the watch list, so it is opt in via /eqot flavorprobe watch. It reads the state
-- back from IsQuestWatched and toggles in whichever direction restores what it found -
-- an earlier version keyed the restore on GetNumQuestWatches, which reads 0 on this client
-- in every state, and it left a quest untracked.
--
-- Measured on 1.15.9: RemoveQuestWatch flips IsQuestWatched, so that call reports real
-- state, while GetNumQuestWatches stays 0 throughout. The derived count below is printed
-- to keep that disagreement visible, not because anything should read it.
function Probe:WatchTest()
    local numEntries  = resolve("GetNumQuestLogEntries")
    local getTitle    = resolve("GetQuestLogTitle")
    local watched     = resolve("IsQuestWatched")
    local numWatches  = resolve("GetNumQuestWatches")
    local idxForWatch = resolve("GetQuestIndexForWatch")
    local addWatch    = resolve("AddQuestWatch")
    local removeWatch = resolve("RemoveQuestWatch")

    if type(numEntries) ~= "function" or type(getTitle) ~= "function"
       or type(numWatches) ~= "function" or type(idxForWatch) ~= "function"
       or type(addWatch) ~= "function" or type(removeWatch) ~= "function" then
        ns:Print("watchtest: part of the flat watch api is absent on this client")
        return
    end

    local function watchCount()
        local ok, v = pcall(numWatches)
        return (ok and type(v) == "number") and v or 0
    end

    local function isWatchedNow(i)
        local ok, v = pcall(watched, i)
        return ok and v and true or false
    end

    local found = {}
    for i = 1, (numEntries() or 0) do
        local t = { getTitle(i) }
        if not t[4] and t[8] and t[8] ~= 0 then
            found[#found + 1] = { index = i, title = t[1] }
            if #found == 2 then break end
        end
    end
    if #found == 0 then
        ns:Print("watchtest: no quest in the log to test with")
        return
    end

    -- A second quest is watched by nothing throughout. If IsQuestWatched answers true for
    -- it while the derived count reads 1, that API is not reporting watch state at all.
    local target      = found[1].index
    local targetTitle = found[1].title
    local other       = found[2] and found[2].index

    -- The derived set is the exact read a provider would use in place of IsQuestWatched.
    local function derived()
        local n, out = watchCount(), {}
        for k = 1, n do
            local ok, i = pcall(idxForWatch, k)
            out[#out + 1] = ("[%d]=%s"):format(k, ok and tostring(i) or "RAISED")
        end
        return ("count=%d %s"):format(n, #out > 0 and table.concat(out, " ") or "(empty)")
    end

    local frame = _G["QuestWatchFrame"]
    local function frameState()
        if type(frame) ~= "table" or type(frame.IsShown) ~= "function" then return "absent" end
        return frame:IsShown() and "shown" or "hidden"
    end

    local function line(label)
        ns:Print(("  %-8s %s | watched(target %d)=%s | watched(other %s)=%s | frame %s"):format(
            label, derived(), target, callStr(watched, target),
            tostring(other), other and callStr(watched, other) or "n/a", frameState()))
    end

    ns:Print(("watchtest: target walk=%d %s"):format(target, tostring(targetTitle)))

    -- Parent and alpha are reported alongside the shown state. This addon suppresses
    -- QuestWatchFrame itself, so a hidden reading here is expected and is not evidence
    -- about what any other addon is doing.
    if type(frame) == "table" then
        local parent = frame.GetParent and frame:GetParent()
        ns:Print(("  QuestWatchFrame: %s alpha=%s parent=%s"):format(
            frameState(),
            tostring(frame.GetAlpha and frame:GetAlpha()),
            tostring(parent and ((parent.GetName and parent:GetName()) or "unnamed") or "none")))
    end

    local initial = isWatchedNow(target)
    line("start")

    -- Toggled away from whatever was found and then back, so the quest ends as it began
    -- whichever state that was.
    if initial then
        pcall(removeWatch, target)
        line("removed")
        pcall(addWatch, target)
        line("restored")
    else
        pcall(addWatch, target)
        line("added")
        pcall(removeWatch, target)
        line("restored")
    end

    local final = isWatchedNow(target)
    ns:Print(("  restore: started %s, ended %s - %s"):format(
        tostring(initial), tostring(final),
        initial == final and "unchanged" or "STATE CHANGED, re-track it by hand"))
end

function Probe:Dump()
    local build = _G["GetBuildInfo"]
    local version, buildNum, toc = "?", "?", "?"
    if type(build) == "function" then
        -- One call, and indexed rather than selected: select(4, ...) on a shorter return
        -- yields ZERO values, and tostring() with no argument raises, which would kill the
        -- whole probe on its first line.
        local _, info = countAndPack(build())
        version, buildNum, toc = tostring(info[1]), tostring(info[2]), tostring(info[4])
    end
    ns:Print(("flavorprobe: addon %s | client %s.%s | client reports interface %s")
        :format(tostring(ns.VERSION), version, buildNum, toc))

    ns:Print("globals:")
    local lines = {}
    for _, name in ipairs(GLOBALS) do
        lines[#lines + 1] = ("%s=%s"):format(name, describe(_G[name]))
    end
    emit(lines, 2)

    ns:Print("quest api (MISSING first, then present):")
    local missing, present = {}, {}
    for _, path in ipairs(QUEST_API) do
        local target = (type(resolve(path)) == "function") and present or missing
        target[#target + 1] = path
    end
    ns:Print(("  MISSING (%d):"):format(#missing))
    emit(missing, 2)
    ns:Print(("  present (%d):"):format(#present))
    emit(present, 2)

    -- MEMBER VALUES, not just a count. A count cannot be compared against the numbers the
    -- flat quest log actually returns, and that gap hid a real defect: Enum.QuestFrequency
    -- exists here but GetQuestLogTitle reports the legacy scheme, so reading the enum
    -- tagged every quest daily.
    ns:Print("enums:")
    for _, name in ipairs(ENUM_TABLES) do
        local tbl = (type(_G["Enum"]) == "table") and _G["Enum"][name] or nil
        if type(tbl) ~= "table" then
            ns:Print(("  Enum.%s=%s"):format(name, type(tbl)))
        else
            local members = {}
            for k, v in pairs(tbl) do
                members[#members + 1] = ("%s=%s"):format(tostring(k), tostring(v))
            end
            table.sort(members)
            ns:Print(("  Enum.%s (%d):"):format(name, #members))
            emit(members, 4)
        end
    end

    ns:Print("ns.Has (false first):")
    local off, on = {}, {}
    for k in pairs(ns.Has) do
        local target = ns.Has[k] and on or off
        target[#target + 1] = k
    end
    table.sort(off)
    table.sort(on)
    ns:Print(("  FALSE (%d):"):format(#off))
    emit(off, 3)
    ns:Print(("  true (%d):"):format(#on))
    emit(on, 3)

    ns:Print(("atlas api=%s:"):format(tostring(ns.Has.Atlas)))
    local atlases = {}
    for _, a in ipairs(ATLASES) do
        atlases[#atlases + 1] = ("%s=%s"):format(a, tostring(Util.AtlasExists(a)))
    end
    emit(atlases, 2)

    ns:Print("textures (file id, or nil when the client has no such file):")
    for _, path in ipairs(TEXTURES) do
        ns:Print(("  %s -> %s"):format(path, resolves(path)))
    end

    -- An inline escape is not a texture object, so no call here can report whether one DREW -
    -- and the atlas result above does not either, since it answers whether GetAtlasInfo knows
    -- the atlas, not whether the markup renders inside a FontString. Copying these lines out of
    -- chat drops the art too, so a blank in a pasted log says nothing. Only the screen answers.
    ns:Print("inline escapes (READ THESE ON SCREEN, a paste drops the art):")
    ns:Print("  |A:common-icon-checkmark:12:12|a <- atlas escape, the one Row.lua ships")
    ns:Print("  |TInterface\\Buttons\\UI-CheckBox-Check:12:12|t <- UI-CheckBox-Check")
    ns:Print("  |TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t <- ReadyCheck-Ready")

    self:DumpQuestLog()
    self:DumpWatchState()

    local q = _G["Questie"]
    local enabled = "n/a"
    if type(q) == "table" and type(q.db) == "table" and type(q.db.profile) == "table" then
        enabled = tostring(q.db.profile.trackerEnabled)
    end
    ns:Print(("questie: base frame %s | trackerEnabled=%s")
        :format(describe(_G["Questie_BaseFrame"]), enabled))
end
