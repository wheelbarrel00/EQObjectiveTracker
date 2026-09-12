local _, ns = ...

local QuestCache = ns:RegisterModule("QuestCache", {})

-- Judges the GAME's quest cache, never one of ours. Scope is the seconds after a login or a
-- loading screen: outside that window this answers ready unconditionally, so a decrease
-- anywhere else is taken as the ordinary thing it is - an item banked, deleted, or used.

local _issecret = _G.issecretvalue
local sbyte     = string.byte

-- nil is asked about BEFORE _issecret, the same order Data/Widgets.lua's plain() uses. Whether
-- that call tolerates a nil is not something this addon has measured, and a missing objective
-- field is the commonest thing to hand it.
local function secret(v)
    return v ~= nil and _issecret ~= nil and _issecret(v)
end

-- The one timer, and the only thing here that can refuse. It is set by PLAYER_ENTERING_WORLD
-- and by nothing else, so no walk can extend its own suspicion and no consumer can be starved:
-- the worst case any of them sees is this many seconds of the behavior that shipped before this
-- file existed.
local SETTLE_MAX_S = 10

-- The first QUEST_LOG_UPDATE of a cold login describes the previous session's quest log, so one
-- is skipped there and none on a reload. UNMEASURED on this client - it is the count a working
-- implementation of the same check uses. Too HIGH only delays a confirm, which the window
-- bounds. Too LOW is the direction that matters - see the confirm gate in Finish.
local LOGIN_SKIP  = 1
local RELOAD_SKIP = 0

local armed       = false
local confirmed   = false
local settleUntil = 0
local skipCount   = 0
local qluSeen     = 0
local loginSeen   = false

local prevObjN, prevFill, prevDone = {}, {}, {}

local walkOpen, walkDirty, walkJudged = false, false, 0
local seen = {}

local stats = { windows = 0, confirms = 0, late = 0, unstreamed = 0, regressed = 0 }

-- Answers ready until a PLAYER_ENTERING_WORLD arms it, so safe mode and /eqot disable QuestCache
-- leave every consumer behaving exactly as it did before this file existed. Bisection axis and
-- safety floor in one.
function QuestCache:IsReady()
    if not armed or confirmed then return true end
    return GetTime() >= settleUntil
end

function QuestCache:Begin()
    walkOpen, walkDirty, walkJudged = true, false, 0
    wipe(seen)
end

-- Fed from the walk the quest providers already do, so the whole check costs one pass over
-- objectives that are already in hand rather than a second read of the quest log.
function QuestCache:Note(questID, objectives, isComplete)
    if not walkOpen or type(questID) ~= "number" then return end
    seen[questID] = true

    local n, fill, streamed = 0, 0, true
    if type(objectives) == "table" then
        n = #objectives
        for i = 1, n do
            local o = objectives[i]
            if type(o) ~= "table" then return end
            local text, got = o.text, o.numFulfilled
            -- A secret value is unjudgeable rather than unready, so the quest is left alone in
            -- both directions: it neither refuses the walk nor overwrites its own baseline.
            if secret(text) or secret(got) then return end
            -- An objective whose text starts with byte 32 has not streamed in. Measured at 7
            -- refusals on one Classic login and 0 on retail, so the two flavors may not
            -- stream alike and one reading of each is not enough to say they do.
            if type(text) ~= "string" or text == "" or sbyte(text, 1) == 32 then streamed = false end
            if type(got) == "number" then fill = fill + got end
        end
    end

    -- Past every skip above, so it counts quests actually JUDGED rather than quests seen. A walk
    -- that read nothing is no evidence the log arrived, and confirming on it would close the
    -- guard rather than satisfy it - where refusing only ever costs the window, which expires.
    walkJudged = walkJudged + 1

    if not streamed then
        walkDirty = true
        stats.unstreamed = stats.unstreamed + 1
        return
    end

    -- Only ever suspicious inside the window. Refusing a decrease outside it would pin the
    -- baseline at the old value and refuse every read after it for as long as the player left
    -- the item banked, which is a hang rather than a guard.
    if not self:IsReady() then
        local was = prevObjN[questID]
        if was and (n < was or fill < prevFill[questID]
                    or (prevDone[questID] and not isComplete)) then
            walkDirty = true
            stats.regressed = stats.regressed + 1
            return
        end
    end

    prevObjN[questID], prevFill[questID], prevDone[questID] = n, fill, isComplete and true or false
end

function QuestCache:Finish()
    if not walkOpen then return self:IsReady() end
    walkOpen = false

    -- Separates "fully streamed" from "fully streamed AND this session's". Without the skip a
    -- cold login could confirm against the outgoing session's quests, which read perfectly
    -- well formed, and the window cannot bound that - it opens the gate early rather than
    -- late. Unmeasured - see LOGIN_SKIP.
    if walkJudged > 0 and not walkDirty and qluSeen > skipCount then
        if not confirmed then
            stats.confirms = stats.confirms + 1
            -- Confirming AFTER the window has already lapsed means the gate did nothing for
            -- that login or loading screen - it had already fallen open on the timeout, and the
            -- clean walk only tidied up behind it. Both states read "confirmed by a clean walk"
            -- and they are the difference between a working guard and one that only ever
            -- expires, which is a distinction this addon has paid for losing before.
            if GetTime() >= settleUntil then stats.late = stats.late + 1 end
        end
        confirmed = true
    end

    -- Only once the log is trusted. Inside the window a quest can be missing because it has
    -- not arrived yet, and dropping its baseline is what lets it return reading zero
    -- objectives with nothing left to compare against, so a half-read walk confirms.
    if walkJudged > 0 and self:IsReady() then
        for id in pairs(prevObjN) do
            if not seen[id] then
                prevObjN[id], prevFill[id], prevDone[id] = nil, nil, nil
            end
        end
    end

    return self:IsReady()
end

function QuestCache:OnEnable()
    local Events = ns:GetModule("Events")

    Events:On("PLAYER_ENTERING_WORLD", function(_, isInitialLogin)
        -- The skip is chosen once. Every later firing is a zone change, which needs the window
        -- but has no login to skip past, and resetting the count there would demand another two
        -- events before anything could confirm again.
        if not loginSeen then
            loginSeen = true
            skipCount = isInitialLogin and LOGIN_SKIP or RELOAD_SKIP
            qluSeen   = 0
        end
        armed         = true
        confirmed     = false
        settleUntil   = GetTime() + SETTLE_MAX_S
        stats.windows = stats.windows + 1
    end)

    Events:On("QUEST_LOG_UPDATE", function()
        qluSeen = qluSeen + 1
    end)
end

function QuestCache:DebugLine()
    local ready = self:IsReady()
    local why
    if not armed then
        why = "no opinion, no world event seen yet"
    elseif confirmed then
        why = "confirmed by a clean walk"
    elseif ready then
        why = "window lapsed unconfirmed"
    else
        why = ("settling, %.1fs left"):format(settleUntil - GetTime())
    end

    local baselines = 0
    for _ in pairs(prevObjN) do baselines = baselines + 1 end

    -- `late` is the figure to read, not `confirmed`. A confirmation that lands after the window
    -- has already expired means the gate was open on the timeout by the time the walk got
    -- there, so it guarded nothing - and without this number that reads exactly like one that
    -- landed in time.
    return ("quest cache: %s (%s) | skip %d, %d log updates | %d window(s), %d confirmed, %d late | refused %d streaming, %d regressed | %d baselines"):format(
        ready and "ready" or "NOT READY", why,
        skipCount, qluSeen, stats.windows, stats.confirms, stats.late,
        stats.unstreamed, stats.regressed, baselines)
end
