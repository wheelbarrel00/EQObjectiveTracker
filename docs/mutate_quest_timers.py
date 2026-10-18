"""Prove docs/test_quest_timers.lua actually discriminates, by breaking the timed-quest countdown,
Classic's and since 2.6.0 retail's, on purpose one change at a time and checking the harness notices.

    python docs/mutate_quest_timers.py         (run from the repo root)

Why this exists: UI/Blizzard.lua now hides Blizzard's own QuestTimerFrame, so the countdown on
the tracker row is the ONLY timer a Classic player has. Every mutant below is a way for that row
to draw nothing, draw the wrong number, or draw a number for a quest that has no timer - and
before this file, a green harness said nothing about any of them.

EIGHT FILES, which is what makes this battery worth having at all. Classic's read half is in
Data/Providers/QuestsClassic.lua, the format half in Core/Util.lua, the tick rate in
UI/Tracker.lua and the row's countdown block in UI/Row.lua. Since 2.6.0 retail's reader and
/eqot timer test are in Data/Providers/Quests.lua, the command in UI/Commands.lua, the
GetTimeAllowed flag in Core/Compat.lua and the tooltip's lines in UI/RewardTooltip.lua. The seams
between them are exactly where the two halves of a feature can be individually correct and
jointly useless. The harness covers some of those seams with greps, and the call-site mutants
are the ones that prove the greps fire.

The pooled-entry mutant is the one that would have shipped. Entries are handed out again, so a
quest whose timer has ENDED inherits the previous occupant's deadline unless the field is
assigned on every pass - and it would count down against nothing, on a row that never had a
timer, for as long as that table kept being reused.

Every mutation reintroduces a defect the harness is supposed to stand guard over. Any that still
reports "0 failed" is an assertion that does not discriminate, and the run exits 1 naming it -
unless the entry is marked EQUIVALENT, which means the mutation provably cannot change behavior
and so nothing could catch it.

A mutant that makes the source RAISE is caught rather than crashing the file, because the harness
pcalls every call into the slices and asserts on the result - the reader, fillTimer, the two
formatters, TimeColor, the row's countdown block, the ticker and noteExpiry. That is deliberate:
every battery in this tree reads a missing summary line as a SURVIVOR, so an unprotected harness
would report a crash as a coverage hole.

A CRASHED verdict is still reported apart from "caught" on purpose. A mutant that does not parse
exits nonzero too, and counting that as caught is a false pass in the one tool whose job is to
find false passes.

WRITES TO THE TREE. It edits those eight files in place and restores them after every mutant through a
finally, then verifies the restore and re-checks the baseline before reporting. If you hard-kill
it, recover from your editor's undo history.

Line endings are resolved PER FILE rather than once. This tree is mixed: Core/Compat.lua is CRLF
in the working tree and the others are LF, and a bare-LF anchor against a CRLF file fails to
match and reports SKIPPED, which reads as a rotted anchor rather than as the driver's own bug.

Anchors are exact source text and they rot. A SKIPPED line means an anchor stopped matching: fix
the anchor rather than dropping the mutant.

The frame-hiding half of this feature lives in UI/Blizzard.lua and is covered by
docs/mutate_blizzard.py, not here.
"""
import io
import re
import subprocess
import sys

LUA = r"C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe"
HARNESS = "docs/test_quest_timers.lua"
SUMMARY = re.compile(r"^test_quest_timers: (\d+) passed, (\d+) failed$")

PROV = "Data/Providers/QuestsClassic.lua"
UTIL = "Core/Util.lua"
TRAC = "UI/Tracker.lua"
QRET = "Data/Providers/Quests.lua"
CMDS = "UI/Commands.lua"
COMPAT = "Core/Compat.lua"
RTIP = "UI/RewardTooltip.lua"

FILL = """local function fillTimer(e, timers, index)
    local secs = index and timers[index] or nil
    e.expiresAt = (secs and secs > 0) and (time() + secs) or nil
end"""

GATHER_SET = "                timerSecs[at] = secs"
GATHER_IDX = "            local gotIndex, index = pcall(GetQuestIndexForTimer, slot)"
GATHER_NUM = "        if secs and secs > 0 then"
GATHER_OK = "            if at and at > 0 then"

READ = """local function readTimers()
    wipe(timerSecs)
    if ns.Has.QuestTimers then gatherTimers(pcall(GetQuestTimers)) end
    return timerSecs
end"""

SECS_FN = """function Util.TimeShortSecs(secs)
    if not secs or secs <= 0 then return "" end
    if secs < 60 then return ("%ds"):format(secs) end
    return Util.TimeShort(math.floor(secs / 60))
end"""

RATE_GUARD = "    if self._timerRate == want then return end"
FAST = "        local fast = left and left <= FAST_WINDOW"
WANT = "        want = fast and TICK_FAST or TICK_SLOW"

# (file, name, old, new)
MUTANTS = [
    # ------------------------------------- the pooled entry, which is the one that would ship
    (PROV,
     "a quest with no timer keeps a POOLED entry's old deadline and counts down against nothing",
     FILL,
     """local function fillTimer(e, timers, index)
    local secs = index and timers[index] or nil
    if secs and secs > 0 then e.expiresAt = time() + secs end
end"""),

    (PROV,
     "the deadline is stored RELATIVE, so the row reads it as an absolute time in 1970",
     "    e.expiresAt = (secs and secs > 0) and (time() + secs) or nil",
     "    e.expiresAt = (secs and secs > 0) and secs or nil"),

    # -------------------------------------------- the slot to log-index mapping
    (PROV,
     "the timer slot is asked for one index off, so a real countdown lands on the wrong quest",
     GATHER_IDX,
     "            local gotIndex, index = pcall(GetQuestIndexForTimer, slot - 1)"),

    (PROV,
     "the table is keyed by timer SLOT rather than by quest log index",
     GATHER_SET,
     "                timerSecs[slot] = secs"),

    # ---------------------------------------------------------------- the reused table
    (PROV,
     "the reused table is not wiped, so a timer that has ended still answers on the next read",
     READ,
     """local function readTimers()
    if ns.Has.QuestTimers then gatherTimers(pcall(GetQuestTimers)) end
    return timerSecs
end"""),

    # ---------------------------------------------------------------- the refusals
    (PROV,
     "a zero or negative seconds value is taken, so an expired timer draws a countdown",
     GATHER_NUM,
     "        if secs then"),

    (PROV,
     "the timer value is taken raw rather than through tonumber, so a junk value reaches\n      the arithmetic",
     "        local secs = tonumber(raw)",
     "        local secs = raw"),

    # The client is documented as answering STRINGS of seconds and no reading has settled
    # it, so both values go through tonumber. Dropping it on the index is invisible against
    # a numeric stub, which is why the harness drives a string index too.
    (PROV,
     "the quest log index is taken raw, so a string index misses the walk's numeric key",
     "            local at = gotIndex and tonumber(index)",
     "            local at = gotIndex and index"),

    # select returns EVERY remaining value, so folding the assignment into the call reads
    # the next slot as tonumber's numeric BASE and raises. The two-step is load-bearing.
    (PROV,
     "select is passed straight to tonumber, so the next slot is read as a numeric base",
     "        local raw = select(slot, ...)\n        local secs = tonumber(raw)",
     "        local secs = tonumber(select(slot, ...))"),

    (PROV,
     "a quest log index of 0 is taken, which is the client's own way of saying it has none",
     GATHER_OK,
     "            if at then"),

    # ---------------------------------------------------------------- the guards
    (PROV,
     "GetQuestTimers is called bare, so a raise there costs GetEntries and the whole render",
     READ,
     """local function readTimers()
    wipe(timerSecs)
    if ns.Has.QuestTimers then gatherTimers(true, GetQuestTimers()) end
    return timerSecs
end"""),

    (PROV,
     "GetQuestIndexForTimer is called bare, so one bad slot costs the render",
     GATHER_IDX,
     "            local gotIndex, index = true, GetQuestIndexForTimer(slot)"),

    (PROV,
     "the capability gate goes, so a client without these globals raises on every rebuild",
     "    if ns.Has.QuestTimers then gatherTimers(pcall(GetQuestTimers)) end",
     "    gatherTimers(pcall(GetQuestTimers))"),

    (PROV,
     "the capability gate is INVERTED, so the reader runs only where the API is absent",
     "    if ns.Has.QuestTimers then gatherTimers(pcall(GetQuestTimers)) end",
     "    if not ns.Has.QuestTimers then gatherTimers(pcall(GetQuestTimers)) end"),

    (PROV,
     "the pcall result is discarded, so a raising client reports timers it never answered for",
     "local function gatherTimers(ok, ...)\n    if not ok then return end",
     "local function gatherTimers(ok, ...)\n    if false then return end"),

    # ------------------------------------------------- the formatter, and the last 59 seconds
    (UTIL,
     "the sub-minute branch goes, so the row draws NOTHING through the last 59 seconds",
     SECS_FN,
     """function Util.TimeShortSecs(secs)
    if not secs or secs <= 0 then return "" end
    return Util.TimeShort(math.floor(secs / 60))
end"""),

    (UTIL,
     "an expired countdown formats as a number instead of as nothing",
     '    if not secs or secs <= 0 then return "" end',
     "    if not secs then return \"\" end"),

    (UTIL,
     "the minutes form is handed SECONDS, so five minutes left reads as five hours",
     "    return Util.TimeShort(math.floor(secs / 60))",
     "    return Util.TimeShort(secs)"),

    (UTIL,
     "the seconds branch swallows a full minute too, so 1m never appears",
     "    if secs < 60 then return (\"%ds\"):format(secs) end",
     "    if secs <= 60 then return (\"%ds\"):format(secs) end"),

    # ---------------------------------------------------------------- the tick rate
    (TRAC,
     "the rate is compared against the REQUEST, so the ticker is rebuilt on every render",
     RATE_GUARD,
     "    if false then return end"),

    (TRAC,
     "the window test is inverted, so it ticks fast when the deadline is far away",
     FAST,
     "        local fast = left and left > FAST_WINDOW"),

    (TRAC,
     "the fast rate is never chosen, so a seconds readout sits half a minute stale",
     WANT,
     "        want = TICK_SLOW"),

    (TRAC,
     "the slow rate is never chosen, so every world quest on screen renders at 5 seconds",
     WANT,
     "        want = TICK_FAST"),

    (TRAC,
     "the ticker is not canceled when the last timed row goes, so it renders forever",
     """    if self._timerTicker then
        self._timerTicker:Cancel()
        self._timerTicker = nil
    end""",
     "    self._timerTicker = nil"),

    (TRAC,
     "the fast window is widened to an hour, which gives back the render rate v1.17.0 cut",
     "local TICK_SLOW, TICK_FAST, FAST_WINDOW = 30, 5, 90",
     "local TICK_SLOW, TICK_FAST, FAST_WINDOW = 30, 5, 3600"),

    # ------------------------------------------------ the seams, which the greps stand over
    # Everything above is inside a sliced function, so all of it passes with the feature
    # unwired. These are the wiring, and they are what the harness's greps exist for.
    (PROV,
     "the full rebuild stops stamping the deadline, so a newly accepted timed quest has none",
     "                fillTimer(e, timers, i)\n",
     ""),

    (PROV,
     "the cheap path stops stamping it, so a timer STARTING never reaches the row",
     "        fillTimer(e, timers, i)\n        fillLines(e, id, i)",
     "        fillLines(e, id, i)"),

    (TRAC,
     "the soonest deadline is not handed to the ticker, so it can never choose the fast rate",
     "    self:_EnsureTimerTicker(hasTimed, soonestExpiry)",
     "    self:_EnsureTimerTicker(hasTimed)"),

    (TRAC,
     "the soonest deadline is never reset, so it only ever falls and the rate sticks fast",
     "    soonestExpiry  = nil\n",
     ""),

    (TRAC,
     "the world quest loop stops feeding it, so a pinned timer cannot set the rate",
     """        if noteExpiry(entry) then hasTimed = true end
        local row = RowPool:Acquire(econtent""",
     """        if entry.expiresAt then hasTimed = true end
        local row = RowPool:Acquire(econtent"""),

    ("UI/Row.lua",
     "the row goes back to whole minutes, which draws nothing through the last 59 seconds",
     """        if secs > 0 then
            timeText = Util.TimeShortSecs(secs)""",
     """        if timeMins > 0 then
            timeText = Util.TimeShort(timeMins)"""),

    ("UI/Tracker.lua",
     "the fast rate is gated to Classic again, so a retail quest timer's last minute sits half a minute stale",
     FAST,
     FAST + " and not ns.Has.QuestLog"),

    ("UI/Tracker.lua",
     "the fast rate is gated to retail, so a Classic quest timer's last minute sits half a minute stale",
     FAST,
     FAST + " and ns.Has.QuestLog"),

    ("UI/Row.lua",
     "the color is taken at minute resolution, so a live sub-minute row draws expired",
     "            if timeMins < 1 then timeMins = 1 end",
     "            if timeMins < 0 then timeMins = 1 end"),

    # ------------------------------------------------- the countdown's COLOR, at its source
    # timeMins has exactly ONE consumer - Util.TimeColor - and until 2026-09-09 neither the
    # derivation nor the five bands it feeds had an assertion anywhere in this tree. Every
    # mutant below left all 22 harnesses green.
    ("UI/Row.lua",
     "timeMins is pinned to zero, so EVERY timed row on both flavors draws in the expired color",
     "        timeMins = math.floor(secs / 60)",
     "        timeMins = 0"),

    ("UI/Row.lua",
     "the clamp is widened to every row, so one color is drawn for the whole tracker",
     "            if timeMins < 1 then timeMins = 1 end",
     "            timeMins = 1"),

    # Not a tidiness point: rounding UP inside the last minute of a band moves the row into the
    # NEXT band, so a quest 29 minutes and 59 seconds out stops reading urgent a minute early.
    ("UI/Row.lua",
     "the floor becomes a ceil, so a deadline just inside a band is colored as the next one",
     "        timeMins = math.floor(secs / 60)",
     "        timeMins = math.ceil(secs / 60)"),

    ("UI/Row.lua",
     "the minutes come off the DEADLINE rather than the time remaining, which is 1970 arithmetic",
     "        timeMins = math.floor(secs / 60)",
     "        timeMins = math.floor(entry.expiresAt / 60)"),

    (UTIL,
     "TimeColor's expired band is merged into the urgent one, so no time left reads as a little",
     "    if not mins or mins <= 0 then return 1.00, 0.10, 0.10 end",
     "    if not mins or mins <= 0 then return 1.00, 0.25, 0.25 end"),

    (UTIL,
     "TimeColor loses its nil guard, so a row whose deadline did not resolve raises",
     "    if not mins or mins <= 0 then return 1.00, 0.10, 0.10 end",
     "    if mins <= 0 then return 1.00, 0.10, 0.10 end"),

    (UTIL,
     "the urgent band is widened to an hour, so a comfortable deadline is drawn as urgent",
     "    if mins < 30   then return 1.00, 0.25, 0.25 end",
     "    if mins < 60   then return 1.00, 0.25, 0.25 end"),

    (UTIL,
     "the calmest band swallows the one below it, so half a day out draws the same as two hours",
     "    if mins < 720  then return 1.00, 1.00, 0.40 end",
     "    if mins < 120  then return 1.00, 1.00, 0.40 end"),
    # ------------------------------------------- retail and WoW Forever (2026-10-16, frkstram)
    (QRET,
     "the retail reader ignores the state, so a finished quest keeps counting down",
     "    elseif e.state == STATE.ACTIVE and ns.Has.QuestTimeAllowed then",
     "    elseif ns.Has.QuestTimeAllowed then"),

    (QRET,
     "the retail reader lets a failed quest count down",
     "    elseif e.state == STATE.ACTIVE and ns.Has.QuestTimeAllowed then",
     "    elseif e.state ~= STATE.COMPLETE and ns.Has.QuestTimeAllowed then"),

    (QRET,
     "the retail reader skips the capability test, so a client without the call raises",
     "    elseif e.state == STATE.ACTIVE and ns.Has.QuestTimeAllowed then",
     "    elseif e.state == STATE.ACTIVE then"),

    (QRET,
     "the time left is rounded up, so a countdown reads a second long",
     "        if total and elapsed then left = math.floor(total - elapsed) end",
     "        if total and elapsed then left = math.ceil(total - elapsed) end"),

    (QRET,
     "the time left is the whole limit, ignoring what has already run",
     "        if total and elapsed then left = math.floor(total - elapsed) end",
     "        if total then left = math.floor(total) end"),

    (QRET,
     "the figures are taken unchecked, so junk from the client raises",
     "        total, elapsed = tonumber(total), tonumber(elapsed)\n",
     ""),

    (QRET,
     "the retail deadline is stored RELATIVE, so the row reads it as a time in 1970",
     "    e.expiresAt = (left and left > 0) and (time() + left) or nil",
     "    e.expiresAt = (left and left > 0) and left or nil"),

    (QRET,
     "a quest with no limit keeps a POOLED entry's old retail deadline",
     "    e.expiresAt = (left and left > 0) and (time() + left) or nil",
     "    if left and left > 0 then e.expiresAt = time() + left end"),

    (QRET,
     "a limit with no time left still stamps a deadline",
     "    e.expiresAt = (left and left > 0) and (time() + left) or nil",
     "    e.expiresAt = (left and left >= 0) and (time() + left) or nil"),

    (QRET,
     "the sample is never laid over its quest",
     "    if testTimerID and id == testTimerID and testTimerAt > time() then",
     "    if false then"),

    (QRET,
     "the sample is laid over every quest",
     "    if testTimerID and id == testTimerID and testTimerAt > time() then",
     "    if testTimerID and testTimerAt > time() then"),

    (QRET,
     "the sample's deadline is read as seconds left, so it never runs down",
     "        left = testTimerAt - time()",
     "        left = testTimerAt"),

    (QRET,
     "the full rebuild stops stamping the retail deadline",
     "                fillTimer(e, id)\n                fillLines(e, id)",
     "                fillLines(e, id)"),

    (QRET,
     "the cheap refresh stops stamping it, so a timer starting mid-quest never shows",
     "        fillTimer(e, id)\n        fillLines(e, id)\n    end\n",
     "        fillLines(e, id)\n    end\n"),

    (QRET,
     "the sample prefers no tracked quest, so it can land on one the tracker hides",
     "            if e.isTracked and e.state == STATE.ACTIVE then pick = e break end",
     "            if e.state == STATE.ACTIVE then pick = e break end"),

    (QRET,
     "the sample lands on a tracked quest that is already finished",
     "            if e.isTracked and e.state == STATE.ACTIVE then pick = e break end",
     "            if e.isTracked then pick = e break end"),

    (QRET,
     "a second run never clears the sample",
     "    if testTimerID and testTimerAt > time() then",
     "    if false then"),

    (QRET,
     "a sample that has run out is cleared rather than started again",
     "    if testTimerID and testTimerAt > time() then",
     "    if testTimerID then"),

    (QRET,
     "the sample asks for no repaint, so nothing shows until an unrelated quest event",
     "    self._notifyDirty()\n    return pick and pick.title or nil",
     "    return pick and pick.title or nil"),

    (QRET,
     "the sample sets no dirty flag, so the store hands back the old entries",
     "    end\n    if primed then dirtyObjectives = true else dirtyAll = true end\n",
     "    end\n"),

    (QRET,
     "before the first full pass the sample sets only the cheap flag, which skips quests not yet cached",
     "    end\n    if primed then dirtyObjectives = true else dirtyAll = true end\n",
     "    end\n    dirtyObjectives = true\n"),

    (QRET,
     "the sample runs on a switched-off provider and raises",
     "    if not self._notifyDirty then return nil, \"off\" end\n",
     ""),

    (QRET,
     "an empty log raises instead of saying so",
     "        if not pick then return nil, \"empty\" end\n",
     ""),

    (QRET,
     "the sample is ten minutes rather than two",
     "local TEST_TIMER_SECS = 120",
     "local TEST_TIMER_SECS = 600"),

    (QRET,
     "the status line lists a countdown that is already over",
     "        if e.expiresAt and e.expiresAt > now then",
     "        if e.expiresAt then"),

    (QRET,
     "the status line reports a run-out sample as still on",
     "        (testTimerID and testTimerAt > now) and tostring(testTimerID) or \"off\")",
     "        testTimerID and tostring(testTimerID) or \"off\")"),

    (COMPAT,
     "the retail capability probes a call the client does not have",
     "Has.QuestTimeAllowed    = method(C_QuestLog, \"GetTimeAllowed\")",
     "Has.QuestTimeAllowed    = method(C_QuestLog, \"GetTimeLeft\")"),

    (CMDS,
     "the timer command starts a sample under Blizzard's tracker",
     "            elseif ns:UsesBlizzardTracker() then\n                ns:Print(\"timer: off, Blizzard's tracker in use\")\n",
     ""),

    (CMDS,
     "the timer command reads its word case-sensitively",
     "            local Q   = ns:GetModule(\"Registry\"):Get(\"quests\")\n            local arg = strtrim(rest or \"\"):lower()",
     "            local Q   = ns:GetModule(\"Registry\"):Get(\"quests\")\n            local arg = strtrim(rest or \"\")"),

    (CMDS,
     "a switched-off provider is reported as an empty log",
     "                if why == \"off\" then\n                    ns:Print(\"timer: the quests provider",
     "                if why == \"empty\" then\n                    ns:Print(\"timer: the quests provider"),

    (CMDS,
     "the timer line is printed without a fresh render",
     "                tracker():Render()\n                ns:GetModule(\"Feed\"):Build()\n                local ok, line = pcall(Q.TimerLine, Q)",
     "                local ok, line = pcall(Q.TimerLine, Q)"),

    (CMDS,
     "a raising timer line aborts the command",
     "                local ok, line = pcall(Q.TimerLine, Q)\n                ns:Print(ok and line or (\"|cffff5555TimerLine raised|r \" .. tostring(line)))",
     "                ns:Print(Q:TimerLine())"),

    (CMDS,
     "/eqot status never prints the providers' timer lines",
     "            if p.TimerLine then\n",
     "            if false then\n"),

    # ------------------------------------------- the pre-ship scan of 2026-10-17
    (QRET,
     "a sample that has run out keeps the quest's row, hiding a real limit under it for good",
     "    if testTimerID and id == testTimerID and testTimerAt > time() then",
     "    if testTimerID and id == testTimerID then"),

    (QRET,
     "the sample's end is timed to the second it runs out rather than one after",
     "        C_Timer.After(TEST_TIMER_SECS + 1, function()",
     "        C_Timer.After(TEST_TIMER_SECS, function()"),

    (QRET,
     "a cleared sample's timer ends the sample started after it",
     "            if testTimerAt ~= at then return end\n",
     ""),

    (QRET,
     "the sample is left set once its timer has ended it",
     "            testTimerID, testTimerAt = nil, nil\n            if primed then dirtyObjectives",
     "            if primed then dirtyObjectives"),

    (QRET,
     "the sample's end marks nothing dirty, so the next pass keeps its deadline",
     "            if primed then dirtyObjectives = true else dirtyAll = true end\n            self._notifyDirty()\n        end)",
     "            self._notifyDirty()\n        end)"),

    (QRET,
     "the sample's end asks for no repaint",
     "            self._notifyDirty()\n        end)",
     "        end)"),

    (QRET,
     "the timer line lists its quests in no set order",
     "    table.sort(parts)\n    return (\"quest timers:",
     "    return (\"quest timers:"),

    (RTIP,
     "the tooltip floors Time Left to minutes, so the last minute draws nothing",
     "        local secs = math.floor(expiresAt - time())",
     "        local secs = math.floor((expiresAt - time()) / 60) * 60"),

    (RTIP,
     "the tooltip draws no time under a minute",
     "        if secs > 0 then",
     "        if secs > 60 then"),

    (RTIP,
     "the tooltip colors Time Left by its seconds rather than its minutes",
     "                        Util.TimeColor(math.max(1, math.floor(secs / 60))))",
     "                        Util.TimeColor(secs))"),

    (RTIP,
     "the tooltip draws the last minute in the red of no time left, unlike the row",
     "                        Util.TimeColor(math.max(1, math.floor(secs / 60))))",
     "                        Util.TimeColor(math.floor(secs / 60)))"),

    (RTIP,
     "the tooltip is handed no deadline, so no row shows its faction or time left",
     "    self:_DrawEntry(owner, entry.id, entry.title, entry.expiresAt, clickHint)",
     "    self:_DrawEntry(owner, entry.id, entry.title, nil, clickHint)"),

    (RTIP,
     "a redraw while the rewards load drops the faction and the time left",
     "            self:_DrawEntry(owner, questID, title, expiresAt, clickHint)\n        end)",
     "            self:_DrawEntry(owner, questID, title, nil, clickHint)\n        end)"),

    ("UI/Row.lua",
     "a quest row's hover hands the tooltip no deadline",
     "        if RT then RT:ShowForEntry(row, row._entry, row._hintShown) end",
     "        if RT then RT:ShowForEntry(row, { id = row._entry.id, title = row._entry.title }, row._hintShown) end"),

    ("UI/Row.lua",
     "a quest row's hover drops its click hint",
     "        if RT then RT:ShowForEntry(row, row._entry, row._hintShown) end",
     "        if RT then RT:ShowForEntry(row, row._entry, false) end"),

    # The bounded round after scan 3: the tooltip's redraw, its title fallback and its minute floor.
    (RTIP,
     "a hover never refills the redraw budget, so a cold quest's rewards never appear",
     "    self._redrawLeft = REDRAW_TRIES\n    -- Scalars only from here down.",
     "    -- Scalars only from here down."),

    (RTIP,
     "the redraw is armed for no quest, so it never draws",
     "        armRedraw(owner, questID, function()\n            self:_DrawEntry(owner, questID, title, expiresAt, clickHint)",
     "        armRedraw(owner, nil, function()\n            self:_DrawEntry(owner, questID, title, expiresAt, clickHint)"),

    (RTIP,
     "the redraw is armed for no row, so it never draws",
     "        armRedraw(owner, questID, function()\n            self:_DrawEntry(owner, questID, title, expiresAt, clickHint)",
     "        armRedraw(nil, questID, function()\n            self:_DrawEntry(owner, questID, title, expiresAt, clickHint)"),

    (RTIP,
     "the redraw drops the click hint",
     "            self:_DrawEntry(owner, questID, title, expiresAt, clickHint)\n        end)",
     "            self:_DrawEntry(owner, questID, title, expiresAt, false)\n        end)"),

    (RTIP,
     "the redraw drops the entry's title",
     "            self:_DrawEntry(owner, questID, title, expiresAt, clickHint)\n        end)",
     "            self:_DrawEntry(owner, questID, nil, expiresAt, clickHint)\n        end)"),

    (RTIP,
     "the tooltip is handed no title, so a quest the game has none for yet shows nothing",
     "    self:_DrawEntry(owner, entry.id, entry.title, entry.expiresAt, clickHint)",
     "    self:_DrawEntry(owner, entry.id, nil, entry.expiresAt, clickHint)"),

    (RTIP,
     "the tooltip rounds a minute up, so it goes orange while the row is still red",
     "                        Util.TimeColor(math.max(1, math.floor(secs / 60))))",
     "                        Util.TimeColor(math.max(1, math.ceil(secs / 60))))"),

    (QRET,
     "a sample still counts in the second it runs out",
     "    if testTimerID and id == testTimerID and testTimerAt > time() then",
     "    if testTimerID and id == testTimerID and testTimerAt >= time() then"),

    (QRET,
     "a cold log's sample end asks only for the cheap refresh, which skips quests not yet cached",
     "            if primed then dirtyObjectives = true else dirtyAll = true end\n            self._notifyDirty()\n        end)",
     "            dirtyObjectives = true\n            self._notifyDirty()\n        end)"),

    (RTIP,
     "a deadline brings no faction line",
     "    if expiresAt then\n        local faction = QR:FactionName(questID)",
     "    if false then\n        local faction = QR:FactionName(questID)"),

    (RTIP,
     "the time left is drawn with no gap after the objectives",
     "            if drew then tip:AddLine(\" \") end\n",
     ""),
]


def run():
    """(verdict, note). verdict is "green", "failed" or "crashed".

    The harness's own summary line is matched rather than its exit code. A mutant that does not
    parse exits nonzero too, and reporting that as "caught" is a false pass in the one tool whose
    job is to catch false passes.
    """
    r = subprocess.run([LUA, HARNESS], capture_output=True, text=True)
    for line in reversed([l for l in r.stdout.splitlines() if l.strip()]):
        m = SUMMARY.match(line.strip())
        if m:
            return ("failed" if int(m.group(2)) else "green"), line.strip()
    return "crashed", (r.stderr.strip().splitlines() or ["no output"])[0][:90]


FILES = sorted({path for path, _, _, _ in MUTANTS})
original = {p: io.open(p, encoding="utf-8", newline="").read() for p in FILES}


def fit(path, s):
    """Per file, because this tree is mixed and a bare-LF anchor silently misses a CRLF file."""
    return s.replace("\n", "\r\n") if "\r\n" in original[path] else s


def restore():
    for p in FILES:
        io.open(p, "w", encoding="utf-8", newline="").write(original[p])


verdict, last = run()
print("baseline: %s\n" % last)
if verdict != "green":
    print("BASELINE IS NOT GREEN - stopping")
    sys.exit(1)

failures = []
for path, name, old, new in MUTANTS:
    old, new = fit(path, old), fit(path, new)
    src = original[path]
    if src.count(old) != 1:
        print("SKIPPED (anchor matched %d times in %s): %s" % (src.count(old), path, name))
        failures.append(("SKIPPED", name))
        continue
    try:
        io.open(path, "w", encoding="utf-8", newline="").write(src.replace(old, new, 1))
        verdict, last = run()
    finally:
        restore()
    equivalent = name.startswith("EQUIVALENT:")
    if verdict == "crashed":
        print("CRASHED   %-90s %s" % (name, last))
        failures.append(("CRASHED", name))
    elif verdict == "green" and not equivalent:
        print("SURVIVED  %-90s %s" % (name, last))
        failures.append(("SURVIVED", name))
    elif verdict == "failed" and equivalent:
        print("UNEXPECTED %-89s %s" % (name + " (was caught)", last))
        failures.append(("UNEXPECTED", name))
    elif equivalent:
        print("survived  %-90s as expected, it cannot change behavior" % name)
    else:
        print("caught    %-90s %s" % (name, last))

for p in FILES:
    if io.open(p, encoding="utf-8", newline="").read() != original[p]:
        print("\nTHE TREE WAS NOT RESTORED - %s still holds a mutant" % p)
        sys.exit(1)
verdict, last = run()
if verdict != "green":
    print("\nBASELINE IS NOT GREEN AFTER THE RUN - %s" % last)
    sys.exit(1)

print()
if failures:
    # Four different verdicts, never pooled. A SKIPPED anchor reported as a survivor sends the
    # reader hunting a coverage hole that is not there, and a CRASHED one hides an abort.
    for kind, label in (
            ("SURVIVED",   "mutant(s) survived - those assertions do not discriminate"),
            ("UNEXPECTED", "EQUIVALENT mutant(s) were caught - the equivalence claim is wrong"),
            ("CRASHED",    "mutant(s) aborted the harness rather than failing it"),
            ("SKIPPED",    "anchor(s) rotted - fix the anchor, never drop the mutant")):
        named = [name for verdict, name in failures if verdict == kind]
        if named:
            print("%d %s:" % (len(named), label))
            for name in named:
                print("  - " + name)
    sys.exit(1)
print("every mutant behaved as expected")
