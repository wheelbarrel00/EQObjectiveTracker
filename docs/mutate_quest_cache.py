"""Prove docs/test_quest_cache.lua actually discriminates, by breaking production on purpose
one change at a time and checking the harness notices.

    python docs/mutate_quest_cache.py        (run from the repo root)

Why this exists: Data/QuestCache.lua answers one question - has the game finished handing back
the quest log - and every way it can answer wrongly is silent in a different direction.

A wrong READY lets a half-streamed login through, which is what spends a strike against a quest
that is merely late and takes its first-seen stamp with it, marks a quest the player has had for
a week as NEW, and lets a complete quest that read incomplete across a loading screen chime as a
fresh completion on the pass after it.

A wrong NOT READY is worse, because it is a hang rather than a wrong number: everything this
gates - the stamps, the NEW tag baseline, the Classic tracked-set prune, the objectives chime -
simply stops, with a green tracker on screen and nothing to say why. That is why the two mutants
that pin the window open and the one that makes a decrease permanently suspicious are in here,
and why the harness reads both sides of the window boundary rather than only the far one.

Every mutation reintroduces a defect the harness is supposed to stand guard over. Any that still
reports "0 failed" is an assertion that does not discriminate, and the run exits 1 naming it.

WRITES TO THE TREE. It edits in place and restores through a finally, so an interrupted run still
puts the file back, and it verifies the restore and re-checks the baseline before reporting.

Anchors are exact source text and they rot. A SKIPPED line means an anchor stopped matching: fix
the anchor rather than dropping the mutant.
"""
import io
import re
import subprocess
import sys

LUA = r"C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe"
HARNESS = "docs/test_quest_cache.lua"

Q = "Data/QuestCache.lua"
P = "Data/Providers/Quests.lua"
C = "Data/Providers/QuestsClassic.lua"
S = "Data/QuestSound.lua"

MUTANTS = [
    # ------------------------------------------------------------- the readiness contract
    # EQUIVALENT, and it took a surviving mutant to notice: `armed` is set in the same statement
    # block as settleUntil and is never cleared, so `not armed` holds exactly while settleUntil
    # is still its initial 0 - and GetTime() >= 0 is already true. The clause is documentation
    # and insurance rather than logic. It stops being equivalent the day anything writes
    # settleUntil without arming, or arms without writing it, and the battery catches it then.
    ("EQUIVALENT: IsReady loses the unarmed escape the window already implies", [
        (Q, "    if not armed or confirmed then return true end",
            "    if confirmed then return true end")]),

    ("IsReady ignores a confirmation and always waits out the window", [
        (Q, "    if not armed or confirmed then return true end",
            "    if not armed then return true end")]),

    ("IsReady answers ready always, so the gate is inert", [
        (Q, "    return GetTime() >= settleUntil\nend",
            "    return true\nend")]),

    # THE STARVATION MUTANT. Everything this gates stops for the session and the tracker looks
    # perfectly healthy while it happens.
    ("the window never lapses, so an unconfirmed client is gated forever", [
        (Q, "    return GetTime() >= settleUntil\nend",
            "    return false\nend")]),

    ("the window is opened for an hour rather than seconds", [
        (Q, "local SETTLE_MAX_S = 10", "local SETTLE_MAX_S = 3600")]),

    ("the window is zero seconds wide, so it closes before anything can read it", [
        (Q, "local SETTLE_MAX_S = 10", "local SETTLE_MAX_S = 0")]),

    ("the boundary is exclusive, so the gate reopens a frame late forever", [
        (Q, "    return GetTime() >= settleUntil\nend",
            "    return GetTime() > settleUntil + 1\nend")]),

    # ------------------------------------------------------------------------ the login skip
    ("a cold login stops skipping its first QUEST_LOG_UPDATE", [
        (Q, "local LOGIN_SKIP  = 1", "local LOGIN_SKIP  = 0")]),

    ("a reload skips one update it should not", [
        (Q, "local RELOAD_SKIP = 0", "local RELOAD_SKIP = 1")]),

    ("the skip is off by one, confirming on the event it exists to ignore", [
        (Q, "    if walkJudged > 0 and not walkDirty and qluSeen > skipCount then",
            "    if walkJudged > 0 and not walkDirty and qluSeen >= skipCount then")]),

    ("the skip is not consulted at all when confirming", [
        (Q, "    if walkJudged > 0 and not walkDirty and qluSeen > skipCount then",
            "    if walkJudged > 0 and not walkDirty then")]),

    # The count is chosen ONCE. Re-choosing it on a zone change sets it to the reload value and
    # re-arms a skip that has already been served.
    ("the skip count is re-chosen on every world event, not just the first", [
        (Q, "        if not loginSeen then\n            loginSeen = true\n",
            "        if true then\n            loginSeen = true\n")]),

    ("the update count is reset on every world event, so a zone change re-arms the skip", [
        (Q, "            qluSeen   = 0\n        end\n",
            "        end\n        qluSeen = 0\n")]),

    ("QUEST_LOG_UPDATE stops being counted", [
        (Q, "        qluSeen = qluSeen + 1", "        qluSeen = qluSeen + 0")]),

    # ----------------------------------------------------------------------- the world event
    ("the window is never opened", [
        (Q, "        settleUntil   = GetTime() + SETTLE_MAX_S",
            "        settleUntil   = GetTime()")]),

    # A loading screen has to REOPEN the question. Without this the first confirmation of the
    # session stands forever and no transition is ever guarded.
    ("a world event no longer reopens a confirmed gate", [
        (Q, "        confirmed     = false\n", "")]),

    ("the module never arms itself", [
        (Q, "        armed         = true\n", "")]),

    ("PLAYER_ENTERING_WORLD is not subscribed", [
        (Q, '    Events:On("PLAYER_ENTERING_WORLD", function(_, isInitialLogin)',
            '    Events:On("EQOT_NEVER_FIRES", function(_, isInitialLogin)')]),

    ("QUEST_LOG_UPDATE is not subscribed", [
        (Q, '    Events:On("QUEST_LOG_UPDATE", function()',
            '    Events:On("EQOT_ALSO_NEVER_FIRES", function()')]),

    # ------------------------------------------------------- the log is still streaming
    ("the leading-space test is dropped, so a half-streamed log reads as arrived", [
        (Q, '            if type(text) ~= "string" or text == "" or sbyte(text, 1) == 32 then streamed = false end',
            '            if type(text) ~= "string" or text == "" then streamed = false end')]),

    ("the leading-space test reads the wrong byte", [
        (Q, "sbyte(text, 1) == 32 then streamed = false end",
            "sbyte(text, 1) == 33 then streamed = false end")]),

    ("the leading-space test reads the wrong position", [
        (Q, "sbyte(text, 1) == 32 then streamed = false end",
            "sbyte(text, 2) == 32 then streamed = false end")]),

    ("an empty objective text is accepted as streamed", [
        (Q, '            if type(text) ~= "string" or text == "" or sbyte(text, 1) == 32 then streamed = false end',
            '            if type(text) ~= "string" or sbyte(text, 1) == 32 then streamed = false end')]),

    ("a missing objective text is accepted as streamed", [
        (Q, '            if type(text) ~= "string" or text == "" or sbyte(text, 1) == 32 then streamed = false end',
            '            if text ~= nil and (text == "" or sbyte(text, 1) == 32) then streamed = false end')]),

    ("an unstreamed read no longer marks the walk dirty", [
        (Q, "    if not streamed then\n        walkDirty = true\n",
            "    if not streamed then\n")]),

    ("an unstreamed read is written in as the new baseline", [
        (Q, "        stats.unstreamed = stats.unstreamed + 1\n        return\n",
            "        stats.unstreamed = stats.unstreamed + 1\n")]),

    # --------------------------------------------------------------- the regression guard
    # THE OTHER HANG. Suspicious everywhere means a decrease outside a loading screen - an item
    # banked, deleted or used - pins the baseline at the old value and refuses every read after
    # it for as long as the player leaves it there.
    ("a decrease is suspicious everywhere, not only inside the window", [
        (Q, "    if not self:IsReady() then\n        local was = prevObjN[questID]",
            "    if true then\n        local was = prevObjN[questID]")]),

    ("a decrease is never suspicious, so a loading screen is not guarded at all", [
        (Q, "    if not self:IsReady() then\n        local was = prevObjN[questID]",
            "    if false then\n        local was = prevObjN[questID]")]),

    ("an objective COUNT that went down is no longer a regression", [
        (Q, "        if was and (n < was or fill < prevFill[questID]",
            "        if was and (fill < prevFill[questID]")]),

    ("a fulfilled count that went down is no longer a regression", [
        (Q, "        if was and (n < was or fill < prevFill[questID]\n                    or (prevDone[questID] and not isComplete)) then",
            "        if was and (n < was\n                    or (prevDone[questID] and not isComplete)) then")]),

    # The one the quest sound hold rests on: without it a complete quest reading incomplete
    # across a loading screen is written in, and chimes as a fresh completion on the next pass.
    ("a complete quest reading incomplete is no longer a regression", [
        (Q, "        if was and (n < was or fill < prevFill[questID]\n                    or (prevDone[questID] and not isComplete)) then",
            "        if was and (n < was or fill < prevFill[questID]) then")]),

    ("the objective count comparison is inverted", [
        (Q, "        if was and (n < was or fill < prevFill[questID]",
            "        if was and (n > was or fill < prevFill[questID]")]),

    ("the fulfilled comparison is inverted", [
        (Q, "or fill < prevFill[questID]\n", "or fill > prevFill[questID]\n")]),

    ("the complete comparison is inverted", [
        (Q, "or (prevDone[questID] and not isComplete)) then",
            "or (not prevDone[questID] and isComplete)) then")]),

    ("a regressed read no longer marks the walk dirty", [
        (Q, "            walkDirty = true\n            stats.regressed = stats.regressed + 1",
            "            stats.regressed = stats.regressed + 1")]),

    # A refused read that becomes the new baseline reads as recovery on the next walk, and the
    # window then closes over data that is still wrong.
    ("a regressed read is written in as the new baseline", [
        (Q, "            stats.regressed = stats.regressed + 1\n            return\n",
            "            stats.regressed = stats.regressed + 1\n")]),

    # Written so it RAISES nowhere: n < math.huge short-circuits the or, so this measures the
    # missing-baseline semantics rather than the harness's pcall.
    ("a quest with no baseline of its own is treated as having regressed", [
        (Q, "        local was = prevObjN[questID]",
            "        local was = prevObjN[questID] or math.huge")]),

    # ------------------------------------------------------------------ unjudgeable values
    ("a secret value is read rather than skipped", [
        (Q, "            if secret(text) or secret(got) then return end\n", "")]),

    # The nil arrives at that call constantly - an objective with no numFulfilled is ordinary -
    # and whether issecretvalue tolerates one is not something this addon has measured. The
    # harness answers it with a stub that raises, which is the direction that costs a render.
    ("the secret test stops asking about nil before asking the client", [
        (Q, "    return v ~= nil and _issecret ~= nil and _issecret(v)",
            "    return _issecret ~= nil and _issecret(v)")]),

    ("an objective that is not a table is read rather than skipped", [
        (Q, '            if type(o) ~= "table" then return end\n', "")]),

    ("a quest skipped as unjudgeable is counted as evidence the log arrived", [
        (Q, "    seen[questID] = true\n\n    local n, fill, streamed = 0, 0, true",
            "    seen[questID] = true\n    walkJudged = walkJudged + 1\n\n    local n, fill, streamed = 0, 0, true")]),

    # ------------------------------------------------------------------ the walk lifecycle
    ("Begin stops resetting the dirty flag, so one bad walk poisons every later one", [
        (Q, "    walkOpen, walkDirty, walkJudged = true, false, 0",
            "    walkOpen, walkJudged = true, 0")]),

    ("Begin stops resetting the judged count", [
        (Q, "    walkOpen, walkDirty, walkJudged = true, false, 0",
            "    walkOpen, walkDirty = true, false")]),

    ("Begin stops wiping the seen set, so the prune keeps a departed quest forever", [
        (Q, "    wipe(seen)\n", "")]),

    ("Note records outside an open walk", [
        (Q, '    if not walkOpen or type(questID) ~= "number" then return end',
            '    if type(questID) ~= "number" then return end')]),

    ("Note accepts a quest id that is not a number", [
        (Q, '    if not walkOpen or type(questID) ~= "number" then return end',
            "    if not walkOpen then return end")]),

    ("Finish confirms on stale accumulators when no walk was open", [
        (Q, "    if not walkOpen then return self:IsReady() end\n", "")]),

    ("Finish leaves the walk open, so the next Note lands in the last walk", [
        (Q, "    walkOpen = false\n", "")]),

    ("an empty walk is allowed to confirm", [
        (Q, "    if walkJudged > 0 and not walkDirty and qluSeen > skipCount then",
            "    if not walkDirty and qluSeen > skipCount then")]),

    ("a walk that read nothing prunes every baseline it holds", [
        (Q, "    if walkJudged > 0 and self:IsReady() then\n        for id in pairs(prevObjN) do",
            "    if true then\n        for id in pairs(prevObjN) do")]),

    # The prune must not run INSIDE the window. A quest missing from a partial walk would
    # lose the baseline that is the only thing left to judge it against, so it returns
    # reading zero objectives, nothing refuses it, and the gate confirms on a half-read log.
    ("the baseline prune runs inside the settle window, so a half-read walk loses its cover", [
        (Q, "    if walkJudged > 0 and self:IsReady() then",
            "    if walkJudged > 0 then")]),

    ("the prune keeps the quests that left the log and drops the ones still in it", [
        (Q, "            if not seen[id] then", "            if seen[id] then")]),

    ("nothing is ever pruned", [
        (Q, "    if walkJudged > 0 and self:IsReady() then\n        for id in pairs(prevObjN) do",
            "    if false then\n        for id in pairs(prevObjN) do")]),

    # EQUIVALENT: prevDone is only ever read for truthiness, and nil and false are both falsy,
    # so storing one rather than the other cannot change an answer. Kept because it stops
    # being equivalent the moment anything tests that field against false explicitly.
    ("EQUIVALENT: the complete flag is stored raw rather than normalized to a boolean", [
        (Q, "prevDone[questID] = n, fill, isComplete and true or false",
            "prevDone[questID] = n, fill, isComplete")]),

    # ---------------------------------------------------------------------- the status line
    ("DebugLine stops naming the unarmed state", [
        (Q, '        why = "no opinion, no world event seen yet"',
            '        why = "settling"')]),

    ("DebugLine calls a lapsed window a confirmation", [
        (Q, '    elseif ready then\n        why = "window lapsed unconfirmed"',
            '    elseif ready then\n        why = "confirmed by a clean walk"')]),

    ("DebugLine reports the wrong verdict", [
        (Q, '        ready and "ready" or "NOT READY", why,',
            '        (not ready) and "ready" or "NOT READY", why,')]),

    ("DebugLine reports no baselines however many are held", [
        (Q, "    for _ in pairs(prevObjN) do baselines = baselines + 1 end",
            "    for _ in pairs(seen) do baselines = baselines + 0 end")]),

    ("DebugLine reports the streaming and regression refusals the wrong way round", [
        (Q, "        stats.unstreamed, stats.regressed, baselines)",
            "        stats.regressed, stats.unstreamed, baselines)")]),

    # The late count is the only thing separating a guard that worked from one that had already
    # expired by the time a walk reached it, and both say "confirmed by a clean walk".
    ("a confirmation arriving after the window expired is not counted as late", [
        (Q, "            if GetTime() >= settleUntil then stats.late = stats.late + 1 end\n", "")]),

    ("every confirmation is counted as late, not just the ones that were", [
        (Q, "            if GetTime() >= settleUntil then stats.late = stats.late + 1 end",
            "            stats.late = stats.late + 1")]),

    ("the late test reads the wrong side of the window", [
        (Q, "            if GetTime() >= settleUntil then stats.late = stats.late + 1 end",
            "            if GetTime() < settleUntil then stats.late = stats.late + 1 end")]),

    # ----------------------------------------------------------------------------- the seams
    # Everything above passes with the module wired to nothing at all. These four are the whole
    # of what makes it reach a player, and they live in files the harness never loads.
    ("the retail provider stops feeding the walk", [
        (P, "    QuestCache:Note(id, objs, e.state == STATE.COMPLETE)\n", "")]),

    ("the Classic provider stops feeding the walk", [
        (C, "    QuestCache:Note(id, objs, e.state == STATE.COMPLETE)\n", "")]),

    ("the retail rebuild stops opening a walk", [
        (P, "    QuestCache:Begin()\n", "")]),

    ("the Classic rebuild stops opening a walk", [
        (C, "    QuestCache:Begin()\n", "")]),

    ("the retail stamp prune stops waiting for the verdict", [
        (P, "    if cacheReady and next(store:Out()) ~= nil then",
            "    if next(store:Out()) ~= nil then")]),

    ("the Classic tracked-set prune stops waiting for the verdict", [
        (C, "    if cacheReady and next(store:Out()) ~= nil then\n        TrackedSet:Prune(stillInLog)",
            "    if next(store:Out()) ~= nil then\n        TrackedSet:Prune(stillInLog)")]),

    ("the quest sound stops holding a complete quest across a loading screen", [
        (S, "    if not now and lastComplete[id] and not QuestCache:IsReady() then",
            "    if false and not now and lastComplete[id] and not QuestCache:IsReady() then")]),

    ("the quest sound holds a complete quest forever rather than only in the window", [
        (S, "    if not now and lastComplete[id] and not QuestCache:IsReady() then",
            "    if not now and lastComplete[id] then")]),

    # ------------------------------------------------ both >= comparisons, AT the boundary
    # Read on both sides and never ON it until 2026-09-09, so either could be tightened to a
    # strict > with every harness green. They are the same instant read for two purposes, and
    # they have to agree: the gate is OPEN at the deadline, so a walk landing exactly there
    # guarded nothing and has to count as late.
    ("IsReady holds the window shut one frame past its own deadline", [
        (Q, "    return GetTime() >= settleUntil", "    return GetTime() > settleUntil")]),

    ("a confirmation landing exactly on the deadline is not counted late", [
        (Q, "            if GetTime() >= settleUntil then stats.late = stats.late + 1 end",
            "            if GetTime() > settleUntil then stats.late = stats.late + 1 end")]),

    # ------------------------------------------------------ the status line's own figures
    # This line is the whole diagnostic - reading it CURES the state it reports, so the
    # counters are all that survive the cure.
    ("the settling branch claims a confirmation it never had", [
        (Q, '        why = ("settling, %.1fs left"):format(settleUntil - GetTime())',
            '        why = "confirmed by a clean walk"')]),

    ("the settling countdown is frozen, so it cannot say how much window is left", [
        (Q, '        why = ("settling, %.1fs left"):format(settleUntil - GetTime())',
            '        why = ("settling, %.1fs left"):format(SETTLE_MAX_S)')]),

    ("the window count is pinned, so a session of zoning reads like a single login", [
        (Q, "        stats.windows = stats.windows + 1", "        stats.windows = 1")]),

    ("windows are not counted at all", [
        (Q, "        stats.windows = stats.windows + 1", "        stats.windows = stats.windows")]),

    ("confirmations are counted per WALK rather than per window", [
        (Q, """        if not confirmed then
            stats.confirms = stats.confirms + 1""",
            """        if true then
            stats.confirms = stats.confirms + 1""")]),

    # skip reading 1 on a cold login and 0 after a reload is the cheapest check in the whole
    # dump, and it is the only thing that says the login skip is working at all.
    ("the login skip is paid on a reload too, so nothing confirms on the first update", [
        (Q, "            skipCount = isInitialLogin and LOGIN_SKIP or RELOAD_SKIP",
            "            skipCount = LOGIN_SKIP")]),

    ("the skip is printed as a constant, so the pair that discriminates reads the same", [
        (Q, "        skipCount, qluSeen, stats.walks, lastJudged, lastQlu,",
            "        0, qluSeen, stats.walks, lastJudged, lastQlu,")]),

    ("the log update counter latches at one, so the skip can never be paid off", [
        (Q, "        qluSeen = qluSeen + 1", "        qluSeen = 1")]),

    # The count deliberately survives a loading screen. Resetting it demands the skip be paid
    # again, so nothing can confirm for another two events on every zone change.
    ("a loading screen resets the log update count, so the skip is paid on every zone change", [
        (Q, "        armed         = true", "        qluSeen       = 0\n        armed         = true")]),

    # ------------------------------------------- the walk count, and the pair beside it
    # These exist because a retail dump read `9 log updates` with `0 confirmed` and nothing on
    # the line could say whether a rebuild had run after the log arrived. The gate is measured
    # innocent, so the open question is the provider's, and this trio is the only thing that can
    # tell "no rebuild ran" from "one ran and read nothing" from "one ran before the skip".
    ("full rebuilds are not counted, so the line cannot say whether any ran", [
        (Q, "    stats.walks = stats.walks + 1\n", "")]),

    ("the walk count latches at one, so rebuilds that kept coming read as one that did not", [
        (Q, "    stats.walks = stats.walks + 1\n",
            "    if stats.walks < 1 then stats.walks = 1 end\n")]),

    # The walk count has to survive a loading screen for the same reason the log update count
    # does: reset there, it can never show that rebuilds stopped arriving.
    ("a loading screen resets the walk count, so the figure only ever describes one window", [
        (Q, "        stats.windows = stats.windows + 1",
            "        stats.windows = stats.windows + 1\n        stats.walks = 0")]),

    ("the last walk's judged and update figures are never recorded", [
        (Q, "    lastJudged, lastQlu = walkJudged, qluSeen\n", "")]),

    # The placement is the behavior. In Begin the count means rebuilds STARTED, which is what
    # answers "did one run at all" for a fullRebuild that raised partway. Moved to Finish it
    # means rebuilds that completed, and an aborted one disappears from the only line that
    # could report it. A tidy-up is plausible because the pair already lives in Finish.
    ("the walk count moves to Finish, so a rebuild that raised is never counted", [
        (Q, "    stats.walks = stats.walks + 1\n    wipe(seen)", "    wipe(seen)"),
        (Q, "    lastJudged, lastQlu = walkJudged, qluSeen",
            "    stats.walks = stats.walks + 1\n    lastJudged, lastQlu = walkJudged, qluSeen")]),

    # walkJudged is zeroed in Begin and never cleared in Finish, so between walks it already
    # holds the last walk's count - which makes lastJudged look redundant. It is not: the two
    # diverge on an aborted walk, where the live value counts quests the walk never finished.
    ("the live walkJudged is printed instead of the recorded copy", [
        (Q, "        skipCount, qluSeen, stats.walks, lastJudged, lastQlu,",
            "        skipCount, qluSeen, stats.walks, walkJudged, lastQlu,")]),

    # Sharper than the walk count's own reset mutant: cleared on a window that has not been
    # walked yet, the pair reads `last judged 0`, which is the "a walk ran and read nothing"
    # shape the trio exists to tell apart. It has to keep describing the last real walk.
    ("a loading screen clears the last walk's pair, so an unwalked window reads as an empty walk", [
        (Q, "        stats.windows = stats.windows + 1",
            "        stats.windows = stats.windows + 1\n        lastJudged, lastQlu = 0, 0")]),

    ("the last walk's pair is recorded the wrong way round", [
        (Q, "    lastJudged, lastQlu = walkJudged, qluSeen",
            "    lastJudged, lastQlu = qluSeen, walkJudged")]),

    # It has to describe the LAST walk. Kept as a high-water mark, a short walk after a long one
    # reads as the long one, which is precisely the "one ran and read nothing" case it is here
    # to expose.
    ("judged is kept as a session high-water mark rather than the last walk's count", [
        (Q, "    lastJudged, lastQlu = walkJudged, qluSeen",
            "    lastJudged = lastJudged > walkJudged and lastJudged or walkJudged\n"
            "    lastQlu = qluSeen")]),

    ("the update figure records the skip rather than the count the walk actually landed at", [
        (Q, "    lastJudged, lastQlu = walkJudged, qluSeen",
            "    lastJudged, lastQlu = walkJudged, skipCount")]),

    ("the walk figure is printed as a constant", [
        (Q, "        skipCount, qluSeen, stats.walks, lastJudged, lastQlu,",
            "        skipCount, qluSeen, 0, lastJudged, lastQlu,")]),

    ("judged and the update figure are printed swapped", [
        (Q, "        skipCount, qluSeen, stats.walks, lastJudged, lastQlu,",
            "        skipCount, qluSeen, stats.walks, lastQlu, lastJudged,")]),

    # The walk figure means FULL REBUILDS only while Begin has one caller per provider. A second
    # one on the cheap path satisfies every presence grep and quietly turns it into a render
    # count - and since it is read against `log updates` to decide whether rebuilds kept coming,
    # that does not read as wrong, it reads as the opposite answer.
    ("a second cache walk opens on the retail provider's cheap path", [
        (P, "local function refreshDynamic()", "local function refreshDynamic()\n    QuestCache:Begin()")]),

    ("a second cache walk opens on the Classic provider's cheap path", [
        (C, "local function refreshDynamic()", "local function refreshDynamic()\n    QuestCache:Begin()")]),
]

SUMMARY = re.compile(r"^test_quest_cache: (\d+) passed, (\d+) failed$")


def run():
    """(verdict, note). verdict is "green", "failed" or "crashed".

    A nonzero exit is NOT evidence that an assertion discriminated - a mutant that does not parse
    exits nonzero too, and reporting that as "caught" is a false pass in the one tool whose job
    is to catch false passes. So the harness's own summary line is matched rather than its exit
    code, and a run that never got that far is its own verdict.
    """
    r = subprocess.run([LUA, HARNESS], capture_output=True, text=True)
    for line in reversed([l for l in r.stdout.splitlines() if l.strip()]):
        m = SUMMARY.match(line.strip())
        if m:
            return ("failed" if int(m.group(2)) else "green"), line.strip()
    err = (r.stderr.strip().splitlines() or r.stdout.strip().splitlines() or ["no output"])
    return "crashed", err[0][:90]


FILES = sorted({f for _, hunks in MUTANTS for f, _, _ in hunks})
original = {f: io.open(f, encoding="utf-8", newline="").read() for f in FILES}


def fit(f, s):
    """Per FILE, never once for the run. Data/QuestSound.lua is CRLF while everything else this
    touches is LF, so a single resolution silently matches nothing in one of them."""
    return s.replace("\r\n", "\n").replace("\n", "\r\n") if "\r\n" in original[f] else s


def restore():
    for f, text in original.items():
        io.open(f, "w", encoding="utf-8", newline="").write(text)


verdict, last = run()
print("baseline: %s\n" % last)
if verdict != "green":
    print("BASELINE IS NOT GREEN - stopping")
    sys.exit(1)

failures = []
for name, hunks in MUTANTS:
    edited, broken = {}, False
    for f, old, new in hunks:
        old, new = fit(f, old), fit(f, new)
        cur = edited.get(f, original[f])
        # Asserted rather than assumed. Applying a mutant to a file that still holds the last
        # one is a silent no-op, and the run then reports the PREVIOUS mutant's result under
        # this mutant's name - a false pass in the tool meant to find them.
        if cur.count(old) != 1:
            print("SKIPPED (anchor matched %d times): %s" % (cur.count(old), name))
            broken = True
            break
        edited[f] = cur.replace(old, new, 1)
    if broken:
        failures.append(("SKIPPED", name))
        continue
    try:
        for f, text in edited.items():
            io.open(f, "w", encoding="utf-8", newline="").write(text)
        verdict, last = run()
    finally:
        restore()
    # EQUIVALENT: marks a mutant that provably cannot change behavior, so it is EXPECTED to
    # survive and being caught is the finding. Without this the summary below advertises a
    # verdict the loop can never produce.
    expected_equivalent = name.startswith("EQUIVALENT:")
    if verdict == "crashed":
        print("CRASHED   %-74s %s" % (name, last))
        failures.append(("CRASHED", name))
    elif verdict == "green" and not expected_equivalent:
        print("SURVIVED  %-74s %s" % (name, last))
        failures.append(("SURVIVED", name))
    elif verdict != "green" and expected_equivalent:
        print("UNEXPECTED %-73s %s" % (name + " (was caught)", last))
        failures.append(("UNEXPECTED", name))
    elif expected_equivalent:
        # Its own word rather than "caught". Nothing caught it and nothing could, and printing
        # that as a catch overstates the run by one every time anybody counts the output.
        print("equivalent %-73s %s" % (name, last))
    else:
        print("caught    %-74s %s" % (name, last))

for f in FILES:
    if io.open(f, encoding="utf-8", newline="").read() != original[f]:
        print("\nTHE TREE WAS NOT RESTORED - %s still holds a mutant" % f)
        sys.exit(1)
verdict, last = run()
if verdict != "green":
    print("\nTHE BASELINE IS NO LONGER GREEN AFTER RESTORE - %s" % last)
    sys.exit(1)

print("\n%d mutants, %d not caught" % (len(MUTANTS), len(failures)))
if failures:
    for kind, name in failures:
        print("  %-10s %s" % (kind, name))
    print("\nSKIPPED means an anchor rotted - fix the anchor, never drop the mutant.")
    print("CRASHED means the harness died before its summary line, which is not the same as")
    print("catching the mutant: pcall the call into the code under test and assert the result.")
    print("SURVIVED means those assertions do not discriminate.")
    sys.exit(1)
print("every mutant caught")
