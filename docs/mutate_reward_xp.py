"""Prove docs/test_reward_xp.lua actually discriminates, by breaking the Classic reward XP read
on purpose one change at a time and checking the harness notices.

    python docs/mutate_reward_xp.py         (run from the repo root)

Why this exists: on Era GetQuestLogRewardXP answers for the SELECTED quest log entry whatever
questID it is handed, so the tooltip showed one figure on every quest. The fix moves the selection
onto each quest once, puts it back, and stores the figure per player level. Most mutants below are
a way to show a figure that belongs to a different quest or a different level, to leave the
player's own quest log pointing somewhere they did not put it, or to quietly stop reading at all.
Others move the selection when nothing needs reading, or misreport the sweep in /eqot status.

THREE FILES. Data/QuestRewards.lua does the reading, Data/Providers/QuestsClassic.lua decides when
and hands over the pairs, and UI/Commands.lua prints the status line. The provider is covered by a
slice plus greps, so the call-site mutants are the ones that prove the greps fire.

Every mutation reintroduces a defect the harness is supposed to stand guard over. Any that still
reports "0 failed" is an assertion that does not discriminate, and the run exits 1 naming it -
unless the entry is marked EQUIVALENT, which means the mutation provably cannot change behavior.

A CRASHED verdict is reported apart from "caught" on purpose. A mutant that does not parse exits
nonzero too, and counting that as caught is a false pass in the one tool whose job is to find
false passes.

WRITES TO THE TREE. It edits three files in place and restores them after every mutant through a
finally, then verifies the restore and re-checks the baseline before reporting. If you hard-kill
it, recover from your editor's undo history.

Line endings are resolved PER FILE, because the working tree can hold CRLF and LF files side by
side, and a bare-LF anchor against a CRLF file reports SKIPPED, which reads as a rotted anchor.

Anchors are exact source text and they rot. A SKIPPED line means an anchor stopped matching: fix
the anchor rather than dropping the mutant.
"""
import io
import re
import subprocess
import sys

LUA = r"C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe"
HARNESS = "docs/test_reward_xp.lua"
SUMMARY = re.compile(r"^test_reward_xp: (\d+) passed, (\d+) failed$")

QR = "Data/QuestRewards.lua"
PROV = "Data/Providers/QuestsClassic.lua"
CMDS = "UI/Commands.lua"

LINES_READ = """    if xpBySelection then
        if xpLevel == UnitLevel("player") then xp = xpCache[questID] end
    else
        xp = GetQuestLogRewardXP and GetQuestLogRewardXP(questID) or 0
    end"""

LEVEL_WIPE = """    if xpLevel ~= level then
        wipe(xpCache)
        wipe(xpRefusedAt)
        xpLevel = level
    end"""

BEFORE_READ = """    local okBefore, before = pcall(GetQuestLogSelection)
    if not (okBefore and type(before) == "number") then return end
"""

RESTORE = """    if moved then
        pcall(SelectQuestLogEntry, before)
        local okAfter, after = pcall(GetQuestLogSelection)
        if not (okAfter and after == before) then xpStats.unrestored = xpStats.unrestored + 1 end
    end"""

COLLECT = """local function collectXP(ready)
    if ready and xpWorldEntered and xpCount > 0 then
        QuestRewards:CollectXP(xpIndex, xpQuest, xpCount)
    end
    xpCount = 0
end"""

# (file, name, old, new)
MUTANTS = [
    # ------------------------------------------------------------------ the reported bug itself
    (QR,
     "the tooltip reads the API by argument on Classic again, so every quest shows the selected one's XP",
     LINES_READ,
     "        xp = GetQuestLogRewardXP and GetQuestLogRewardXP(questID) or 0"),

    (QR,
     "the flavor flag is inverted, so Classic reads by argument and retail moves the selection",
     "local xpBySelection = not ns.Has.QuestLog",
     "local xpBySelection = ns.Has.QuestLog"),

    (QR,
     "the module registers under another name, so the provider's lookup resolves nothing",
     'local QR = ns:RegisterModule("QuestRewards", {})',
     'local QR = ns:RegisterModule("QuestReward", {})'),

    # ------------------------------------------------------------------------------ the level
    (QR,
     "the tooltip shows a stored figure from before a ding",
     '        if xpLevel == UnitLevel("player") then xp = xpCache[questID] end',
     "        xp = xpCache[questID]"),

    (QR,
     "NeedsXP ignores a ding, so a stored quest is never queued for a re-read",
     '    if xpLevel ~= UnitLevel("player") then return true end\n',
     ""),

    (QR,
     "a ding does not empty the store, so the sweep skips every quest it already read",
     LEVEL_WIPE,
     """    if xpLevel ~= level then
        wipe(xpRefusedAt)
        xpLevel = level
    end"""),

    (QR,
     "a ding does not clear the wait, so a refused quest is not re-read at the new level",
     LEVEL_WIPE,
     """    if xpLevel ~= level then
        wipe(xpCache)
        xpLevel = level
    end"""),

    (QR,
     "the level is never recorded, so no stored figure is ever shown",
     LEVEL_WIPE,
     """    if xpLevel ~= level then
        wipe(xpCache)
        wipe(xpRefusedAt)
    end"""),

    (QR,
     "the selection is read AFTER the level wipe, so a sweep that cannot start still empties the store",
     BEFORE_READ + '\n    local level = UnitLevel("player")\n' + LEVEL_WIPE + "\n",
     '    local level = UnitLevel("player")\n' + LEVEL_WIPE + "\n" + BEFORE_READ + "\n"),

    # ----------------------------------------------------------------------- the selection move
    (QR,
     "only the first n pairs are no longer the limit, so a stale pair past n is read",
     "    for k = 1, n do\n",
     "    for k = 1, #ids do\n"),

    (QR,
     "the read is not confirmed against the selection, so a refused move stores another quest's figure",
     "            if okSel and sel == index then okXP, xp = pcall(GetQuestLogRewardXP, id) end",
     "            okXP, xp = pcall(GetQuestLogRewardXP, id)"),

    (QR,
     "the questID is dropped from the read, so a client that honors the argument reads nothing",
     "okXP, xp = pcall(GetQuestLogRewardXP, id) end",
     "okXP, xp = pcall(GetQuestLogRewardXP) end"),

    (QR,
     "the selection is never put back, so the player's quest log is left on the last quest read",
     "        pcall(SelectQuestLogEntry, before)\n",
     ""),

    (QR,
     "the restore runs even when nothing moved, so a steady quest log still moves the selection",
     "    if moved then\n",
     "    if true then\n"),

    (QR,
     "a stored quest is read again on every sweep",
     "        if xpCache[id] == nil and not waiting(id, clock) then\n",
     "        if not waiting(id, clock) then\n"),

    # ------------------------------------------------------------------------- unprotected calls
    (QR,
     "the move is not protected, so a select that raises aborts the sweep with the selection moved",
     "            pcall(SelectQuestLogEntry, index)\n",
     "            SelectQuestLogEntry(index)\n"),

    (QR,
     "the restore is not protected, so a select that raises there escapes",
     "        pcall(SelectQuestLogEntry, before)\n",
     "        SelectQuestLogEntry(before)\n"),

    (QR,
     "the confirm is not protected, so a selection read that raises aborts the sweep",
     "            local okSel, sel = pcall(GetQuestLogSelection)\n",
     "            local okSel, sel = true, GetQuestLogSelection()\n"),

    (QR,
     "the restore check is not protected, so a selection read that raises escapes",
     "        local okAfter, after = pcall(GetQuestLogSelection)\n",
     "        local okAfter, after = true, GetQuestLogSelection()\n"),

    # ------------------------------------------------------------------------- the refusals
    (QR,
     "the selection is moved with nothing to put it back to",
     '    if not (okBefore and type(before) == "number") then return end\n',
     ""),

    (QR,
     "the selection is moved on a client with no XP API to read",
     '    if type(GetQuestLogRewardXP) ~= "function" or type(SelectQuestLogEntry) ~= "function" then',
     '    if type(SelectQuestLogEntry) ~= "function" then'),

    (QR,
     "an empty batch still runs a sweep",
     "    if not (xpBySelection and n > 0) then return end",
     "    if not xpBySelection then return end"),

    (QR,
     "an answer that is not a number is stored, so that quest is never asked about again",
     '            if okXP and type(xp) == "number" then',
     "            if okXP then"),

    # ------------------------------------------------------------------------------- the wait
    (QR,
     "a refused quest never waits, so it moves the selection again on every pass",
     "    return at ~= nil and clock - at < XP_RETRY_S\n",
     "    return false\n"),

    (QR,
     "the wait is lengthened, so a quest that could now be read waits twice as long",
     "local XP_RETRY_S = 30\n",
     "local XP_RETRY_S = 60\n"),

    (QR,
     "the wait is shortened, so a refused quest is retried inside the window",
     "local XP_RETRY_S = 30\n",
     "local XP_RETRY_S = 10\n"),

    (QR,
     "the wait is shortened by less than a second, which only a fractional clock can see",
     "local XP_RETRY_S = 30\n",
     "local XP_RETRY_S = 29.5\n"),

    (QR,
     "the wait boundary is inclusive, so a quest is held back at exactly 30 seconds",
     "    return at ~= nil and clock - at < XP_RETRY_S\n",
     "    return at ~= nil and clock - at <= XP_RETRY_S\n"),

    (QR,
     "the wait is measured backwards, so a refused quest waits forever",
     "    return at ~= nil and clock - at < XP_RETRY_S\n",
     "    return at ~= nil and at - clock < XP_RETRY_S\n"),

    (QR,
     "a refusal is stamped a second late, so its wait runs past 30 seconds",
     "                xpRefusedAt[id] = clock\n",
     "                xpRefusedAt[id] = clock + 1\n"),

    (QR,
     "the sweep checks the wait a second ahead, so it reads a quest NeedsXP still holds back",
     "        if xpCache[id] == nil and not waiting(id, clock) then\n",
     "        if xpCache[id] == nil and not waiting(id, clock + 1) then\n"),

    (QR,
     "every sweep clears the wait, not only a ding",
     LEVEL_WIPE,
     """    wipe(xpRefusedAt)
    if xpLevel ~= level then
        wipe(xpCache)
        xpLevel = level
    end"""),

    (QR,
     "a refusal is not stamped, so the wait never starts",
     "                xpRefusedAt[id] = clock\n",
     ""),

    (QR,
     "a successful read does not clear the wait, so status reports a quest still waiting",
     "                xpRefusedAt[id] = nil\n",
     ""),

    (QR,
     "NeedsXP ignores the wait, so a refused quest is queued on every pass",
     "    return xpCache[questID] == nil and not waiting(questID, GetTime())\n",
     "    return xpCache[questID] == nil\n"),

    (QR,
     "the sweep ignores the wait, so a caller handing over a refused quest moves the selection",
     "        if xpCache[id] == nil and not waiting(id, clock) then\n",
     "        if xpCache[id] == nil then\n"),

    # ---------------------------------------------------------------------------- the counters
    (QR,
     "a refused read is not counted, so status cannot say why a quest shows no XP",
     "                xpStats.refused = xpStats.refused + 1\n",
     ""),

    (QR,
     "a successful read is not counted",
     "                xpStats.reads = xpStats.reads + 1\n",
     ""),

    (QR,
     "a restore that did not take is not counted, the one failure a player would see",
     RESTORE,
     """    if moved then
        pcall(SelectQuestLogEntry, before)
    end"""),

    (QR,
     "a sweep that cannot start is still counted as a sweep",
     BEFORE_READ,
     "    xpStats.sweeps = xpStats.sweeps + 1\n" + BEFORE_READ),

    (QR,
     "the sweep counter is deleted, so status always reads 0 sweeps",
     "    xpStats.sweeps = xpStats.sweeps + 1\n    local clock = GetTime()\n",
     "    local clock = GetTime()\n"),

    (QR,
     "a sweep is counted only when it moved the selection",
     "    if moved then\n        pcall(SelectQuestLogEntry, before)\n",
     "    if not moved then xpStats.sweeps = xpStats.sweeps - 1 end\n"
     "    if moved then\n        pcall(SelectQuestLogEntry, before)\n"),

    (QR,
     "a missing select API still starts a sweep that refuses every quest",
     '    if type(GetQuestLogRewardXP) ~= "function" or type(SelectQuestLogEntry) ~= "function" then',
     '    if type(GetQuestLogRewardXP) ~= "function" then'),

    (QR,
     "the status line swaps the stored level and the player's level",
     '        figures, tostring(xpLevel), tostring(UnitLevel("player")), refusals,',
     '        figures, tostring(UnitLevel("player")), tostring(xpLevel), refusals,'),

    (QR,
     "status prints level 0 before any read, which reads like a real level",
     '        figures, tostring(xpLevel), tostring(UnitLevel("player")), refusals,',
     '        figures, tostring(xpLevel or 0), tostring(UnitLevel("player")), refusals,'),

    (QR,
     "the refusal count reads the store instead",
     "    for _ in pairs(xpRefusedAt) do refusals = refusals + 1 end\n",
     "    for _ in pairs(xpCache) do refusals = refusals + 1 end\n"),

    (QR,
     "a refusal is counted only while its wait lasts, so a quest still unread drops out of status",
     "    for _ in pairs(xpRefusedAt) do refusals = refusals + 1 end\n",
     "    for _, at in pairs(xpRefusedAt) do\n"
     "        if GetTime() - at < XP_RETRY_S then refusals = refusals + 1 end\n"
     "    end\n"),

    (QR,
     "the status line loses its label, so /eqot status prints an unnamed row of numbers",
     '    return ("reward xp: read by selection | %d figures held',
     '    return ("%d figures held'),

    (QR,
     "retail prints a reward XP line that describes a path it never takes",
     "    if not xpBySelection then return nil end\n    local figures",
     "    local figures"),

    # ------------------------------------------------------------------- the provider's helpers
    (PROV,
     "a pass before the quest cache is ready reads XP anyway",
     "    if ready and xpWorldEntered and xpCount > 0 then",
     "    if xpWorldEntered and xpCount > 0 then"),

    (PROV,
     "the login render reads XP before PLAYER_ENTERING_WORLD arms the quest cache",
     "    if ready and xpWorldEntered and xpCount > 0 then",
     "    if ready and xpCount > 0 then"),

    (PROV,
     "an unready pass keeps its batch, so the next ready pass resends pairs from an older quest log",
     COLLECT,
     """local function collectXP(ready)
    if ready and xpWorldEntered and xpCount > 0 then
        QuestRewards:CollectXP(xpIndex, xpQuest, xpCount)
        xpCount = 0
    end
end"""),

    (PROV,
     "a quest with no log index is queued",
     "    if index and QuestRewards:NeedsXP(id) then",
     "    if QuestRewards:NeedsXP(id) then"),

    (PROV,
     "a quest that already has its figure is queued anyway",
     "    if index and QuestRewards:NeedsXP(id) then",
     "    if index then"),

    # ------------------------------------------------------------------------- the call sites
    (PROV,
     "fullRebuild never queues a quest, so a fresh login shows no XP until a dynamic pass",
     "                fillLines(e, id, i)\n                wantXP(id, i)\n",
     "                fillLines(e, id, i)\n"),

    (PROV,
     "refreshDynamic never queues a quest, so a ding is not re-read until a full rebuild",
     "        fillLines(e, id, i)\n        wantXP(id, i)\n",
     "        fillLines(e, id, i)\n"),

    (PROV,
     "fullRebuild reads XP before the quest cache has judged the log",
     "    collectXP(cacheReady)\n",
     "    collectXP(true)\n"),

    (PROV,
     "refreshDynamic reads XP inside the settle window",
     "    collectXP(QuestCache:IsReady())\n",
     "    collectXP(true)\n"),

    (PROV,
     "refreshDynamic never hands its batch over",
     "    collectXP(QuestCache:IsReady())\n",
     ""),

    (PROV,
     "fullRebuild does not empty the batch first, so a pass that raised leaves stale pairs behind",
     "    local timers = readTimers()\n    xpCount = 0\n    store:Begin()",
     "    local timers = readTimers()\n    store:Begin()"),

    (PROV,
     "refreshDynamic does not empty the batch first",
     "    local timers = readTimers()\n    xpCount = 0\n    for id, e in store:Each() do",
     "    local timers = readTimers()\n    for id, e in store:Each() do"),

    (PROV,
     "a stray reset before refreshDynamic's hand-over switches the read off",
     "    collectXP(QuestCache:IsReady())\n",
     "    xpCount = 0\n    collectXP(QuestCache:IsReady())\n"),

    (PROV,
     "a stray reset before fullRebuild's hand-over switches the read off",
     "    store:Finish()\n    local cacheReady = QuestCache:Finish()\n",
     "    store:Finish()\n    xpCount = 0\n    local cacheReady = QuestCache:Finish()\n"),

    (PROV,
     "a stray reset spelled with a semicolon switches the read off",
     "    collectXP(QuestCache:IsReady())\n",
     "    xpCount = 0;\n    collectXP(QuestCache:IsReady())\n"),

    (PROV,
     "a stray reset carrying a trailing comment switches the read off",
     "    store:Finish()\n    local cacheReady = QuestCache:Finish()\n",
     "    xpCount = 0 -- start clean\n    store:Finish()\n    local cacheReady = QuestCache:Finish()\n"),

    (PROV,
     "a stray reset written as arithmetic switches the read off",
     "    collectXP(QuestCache:IsReady())\n",
     "    xpCount = xpCount * 0\n    collectXP(QuestCache:IsReady())\n"),

    (PROV,
     "the world-entered gate closes again on every turn-in",
     "    local function markRemoved()\n        dirtyAll = true\n",
     "    local function markRemoved()\n        xpWorldEntered = false\n        dirtyAll = true\n"),

    (PROV,
     "the world-entered gate starts open, so the login render reads before the cache is armed",
     "local xpWorldEntered = false\n",
     "local xpWorldEntered = true\n"),

    # --------------------------------------------------------------------------------- events
    (PROV,
     "entering the world never opens the read, so Classic never shows XP again",
     "        xpWorldEntered = true\n",
     ""),

    (PROV,
     "PLAYER_ENTERING_WORLD goes straight to markAll, so the read is never opened",
     '    Events:On("PLAYER_ENTERING_WORLD",   enterWorld)\n',
     '    Events:On("PLAYER_ENTERING_WORLD",   markAll)\n'),

    (PROV,
     "entering the world no longer marks everything dirty",
     "        xpWorldEntered = true\n        markAll()\n",
     "        xpWorldEntered = true\n"),

    (PROV,
     "entering the world marks only a dynamic pass, so no full rebuild follows a loading screen",
     "        xpWorldEntered = true\n        markAll()\n",
     "        xpWorldEntered = true\n        markDynamic()\n"),

    (PROV,
     "a ding triggers no pass, so the tooltip shows no XP until an unrelated quest event",
     '    Events:On("PLAYER_LEVEL_UP",         markDynamic)\n',
     ""),

    (PROV,
     "UNIT_LEVEL is not registered, so a level that moves after the ding's pass waits for a quest event",
     '    Events:On("UNIT_LEVEL",              playerLevelChanged)\n',
     ""),

    (PROV,
     "any unit's level change triggers a pass, not just the player's",
     '        if unit == "player" then markDynamic() end\n',
     "        markDynamic()\n"),

    (PROV,
     "the level filter is inverted, so every unit but the player triggers a pass",
     '        if unit == "player" then markDynamic() end\n',
     '        if unit ~= "player" then markDynamic() end\n'),

    (CMDS,
     "/eqot status never prints the reward XP line",
     '    debugLine("QuestRewards")\n',
     ""),
]


def run():
    """(verdict, note). verdict is "green", "failed" or "crashed".

    The harness's own summary line is matched rather than its exit code. A mutant that does not
    parse exits nonzero too, and reporting that as "caught" is a false pass.
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
    """Per file, because a bare-LF anchor against a CRLF file would report SKIPPED."""
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
