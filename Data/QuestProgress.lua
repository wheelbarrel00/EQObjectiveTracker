local _, ns = ...

local QuestProgress = ns:RegisterModule("QuestProgress", {})

-- Blizzard draws a filling bar under a quest's percentage objective where this tracker drew the
-- text alone, and the reason is that the percentage is in NEITHER numFulfilled NOR numRequired.
-- Measured on quest 92149 Death to Twilight: its progressbar objective reads 0 of 1, so the
-- meter carries a yes-or-no while the bar beside it is a real percentage.
--
-- BOTH sources are asked rather than betting on one, and the first is a BARE GLOBAL - that is
-- the trap here. C_QuestLog.GetQuestProgressBarPercent does not exist, and a probe of
-- C_QuestLog for anything matching "Progress" comes back with nothing at all, so a first
-- attempt reads nil and looks like a dead end.

-- Midnight can hand back "secret values" that report type "number" and then error on
-- arithmetic, so one is refused here rather than at every comparison below.
local _issecret = _G.issecretvalue

-- Values, never a formatted string. Percent runs on the render path, through the providers'
-- GetEntries, and a format call there allocates a fresh string on every repaint for a line
-- almost nobody reads. DebugLine does the formatting, once, when it is asked for.
local stats = {
    asked = 0, byGlobal = 0, byTask = 0, refused = 0,
    lastSource = nil, lastPct = nil, lastQuest = nil,
}

local function usable(v)
    if _issecret and _issecret(v) then return nil end
    if type(v) ~= "number" then return nil end
    if v < 0 or v > 100 then return nil end
    return v
end

-- Answers a percentage out of 100, or nil when this client has neither source. Deliberately not
-- gated on showProgressBars: the providers cache their entries, so reading the option here would
-- leave a line still shaped as a plain count after the option was switched back on, and no quest
-- event need follow to correct it. One extra read per progressbar objective is the cheaper half
-- of that trade, and there are rarely more than one.
function QuestProgress:Percent(questID)
    if not questID then return nil end

    -- Render-driven: the providers ask from inside Tracker:Render, so the OnEnable gate never
    -- reaches this and it has to ask for itself. Ahead of BOTH reads, because a disable that
    -- leaves one API call behind is not an axis, and this is a quest API call on every retail
    -- render that meets a percentage objective - two call sites, but the second is reached only
    -- when the first answers nothing. IsModuleDisabled rather than SafeMode,
    -- so an explicit enable can outrank safe mode the way the bisection tool expects.
    --
    -- This module has no OnEnable, so ns:SkippableModules leaves it out and the NAME cannot be
    -- given to /eqot disable. What reaches this line is `/eqot disable all`. The per-feature
    -- axis is the provider - `/eqot disable quests` or `worldquests` - which stops GetEntries
    -- from running at all, so do not reach for the module name when bisecting a taint report.
    if ns:IsModuleDisabled("QuestProgress") then
        stats.lastSource, stats.lastQuest = "off", questID
        return nil
    end

    stats.asked = stats.asked + 1

    if ns.Has.QuestProgressBar then
        local pct = usable(GetQuestProgressBarPercent(questID))
        if pct then
            stats.byGlobal = stats.byGlobal + 1
            stats.lastSource, stats.lastPct, stats.lastQuest = "global", pct, questID
            return pct
        end
    end

    if ns.Has.TaskQuestProgressBar then
        local pct = usable(C_TaskQuest.GetQuestProgressBarInfo(questID))
        if pct then
            stats.byTask = stats.byTask + 1
            stats.lastSource, stats.lastPct, stats.lastQuest = "task", pct, questID
            return pct
        end
    end

    stats.refused = stats.refused + 1
    stats.lastSource, stats.lastPct, stats.lastQuest = "none", nil, questID
    return nil
end

-- Which source answered, because the two are tried in order and a client with only the second
-- looks identical from the row. A bar that never appears is the report this exists to make
-- readable: a non-zero `asked` beside `N refused` is a client neither API answers for, while
-- `asked 0` is no progressbar objective reaching us at all - or safe mode, which returns above
-- without counting and says so on the `last:` clause. Those want different hunts.
function QuestProgress:DebugLine()
    local last = "nothing asked this session"
    local src  = stats.lastSource
    if src == "global" then
        last = ("%d%% for %d, from GetQuestProgressBarPercent"):format(
            stats.lastPct, stats.lastQuest)
    elseif src == "task" then
        last = ("%d%% for %d, from C_TaskQuest"):format(stats.lastPct, stats.lastQuest)
    elseif src == "none" then
        last = ("neither source answered for %d"):format(stats.lastQuest)
    elseif src == "off" then
        last = "switched off, safe mode"
    end
    return ("quest progress bars: asked %d, %d by global, %d by task quest, %d refused"
            .. "\n      api GetQuestProgressBarPercent %s, C_TaskQuest %s | last: %s"):format(
        stats.asked, stats.byGlobal, stats.byTask, stats.refused,
        tostring(ns.Has.QuestProgressBar), tostring(ns.Has.TaskQuestProgressBar), last)
end
