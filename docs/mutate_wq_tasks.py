"""Prove docs/test_wq_tasks.lua actually discriminates, by breaking the tasks-table source in
Data/Providers/WorldQuests.lua on purpose one change at a time and checking the harness notices.

    python docs/mutate_wq_tasks.py         (run from the repo root)

Why this exists: addTaskTableQuests is the ONLY source in the addon that can see a bonus
objective. Measured 2026-09-08 on 12.1, standing inside one: quest 95580 answered IsQuestTask
true, IsWorldQuest false, and GetLogIndexForQuestID 29 with isHidden TRUE - a bonus objective
is in the quest log only as a HIDDEN entry, which both quest providers skip, and Entmoot's own /eqot status showed it was on no map list either. So every mutant
below removes the last route to a row the tracker is supposed to draw, and none of them would
have been caught by anything else in the tree.

Two of them are not about the reported bug at all but about NOT causing a second one: dropping
or inverting the `not isWorldQuest(qid)` skip makes this source start listing world quests, and
the reporter is a player who has autoListZoneWorldQuests deliberately switched OFF. A fix that
fills his World Quests section with the quests he asked not to see is a worse bug than the one
it fixes.

Every mutation reintroduces a defect the harness is supposed to stand guard over. Any that still
reports "0 failed" is an assertion that does not discriminate, and the run exits 1 naming it -
unless the entry is marked EQUIVALENT, which means the mutation provably cannot change behavior
and so nothing could catch it.

A mutant that makes the source RAISE is caught rather than crashing the file, because the
harness pcalls every call into the slice and asserts on the result. That is deliberate: every
battery in this tree reads a missing summary line as a SURVIVOR, so an unprotected harness would
report a crash as a coverage hole.

A CRASHED verdict is still reported apart from "caught" on purpose. A mutant that does not parse
exits nonzero too, and counting that as caught is a false pass in the one tool whose job is to
find false passes.

WRITES TO THE TREE. It edits Data/Providers/WorldQuests.lua in place and restores it after every
mutant through a finally, then verifies the restore and re-checks the baseline before reporting.
If you hard-kill it, recover from your editor's undo history.

Anchors are exact source text and they rot. A SKIPPED line means an anchor stopped matching: fix
the anchor rather than dropping the mutant.

Two of the four load-bearing places live in OTHER files - Core/Compat.lua's two capability
probes and UI/Sections.lua's title and DEFAULT_ORDER - so they are covered by greps in the
harness rather than by mutants here. Each was proved to fail the harness by hand. Widening this
driver to them needs a per-file eol: Core/Compat.lua is CRLF where this one is LF.
"""
import io
import re
import subprocess
import sys

LUA = r"C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe"
SRC = "Data/Providers/WorldQuests.lua"
HARNESS = "docs/test_wq_tasks.lua"
SUMMARY = re.compile(r"^test_wq_tasks: (\d+) passed, (\d+) failed$")

GATE = "            if infoOK and not secret and numObjectives and isInArea then push(qid) end"
SECRET = "            local secret = _issecret and (_issecret(isInArea) or _issecret(numObjectives))"
# The same call appears in ProbeLines, so this anchors to its unique predecessor in the source
# rather than to the line alone - which matched twice and reported SKIPPED on the first run.
INFO_LEAD = "            -- reason taskIsActive records.\n"
INFO = INFO_LEAD + "            local infoOK, isInArea, _, numObjectives = pcall(GetTaskInfo, qid)"
SKIP = "        if qid and not isWorldQuest(qid) then"
HAS = "    if not (ns.Has.TasksTable and ns.Has.TaskInfo) then return end"

MUTANTS = [
    # ------------------------------------------------- the two gates the reading measured
    ("the isInArea gate goes, so a task merely registered nearby lists as though live",
     GATE,
     "            if infoOK and not secret and numObjectives then push(qid) end"),

    ("the numObjectives gate goes, so an entry the client cannot answer for yet lists",
     GATE,
     "            if infoOK and not secret and isInArea then push(qid) end"),

    ("the two gates become an OR, so either alone is enough to list",
     GATE,
     "            if infoOK and not secret and (numObjectives or isInArea) then push(qid) end"),

    ("the isInArea gate is INVERTED, so it lists exactly the ones the player is not in",
     GATE,
     "            if infoOK and not secret and numObjectives and not isInArea then push(qid) end"),

    ("nothing is pushed at all, which is the shipped bug this source exists to fix",
     GATE,
     "            if infoOK and not secret and numObjectives and isInArea then local _ = qid end"),

    # ------------------------------ the section split, which lives in two places at once
    ("the second group is not declared, so every bonus objective carries an undeclared groupID",
     '    groups   = { "worldquests", "bonusobjectives" },',
     '    groups   = { "worldquests" },'),

    ("bonus objectives go back under the World Quests header instead of their own",
     '            e.groupID = wq and "worldquests" or "bonusobjectives"\n',
     ""),

    ("the group choice is inverted, so world quests draw under Bonus Objectives and back",
     '            e.groupID = wq and "worldquests" or "bonusobjectives"',
     '            e.groupID = wq and "bonusobjectives" or "worldquests"'),

    # ------------------------------------------------------- the secret value guard itself
    ("the secret value guard goes, so a secret field is truth-tested where it RAISES",
     SECRET + "\n" + GATE,
     "            if infoOK and numObjectives and isInArea then push(qid) end"),

    ("only isInArea is guarded, so a secret objective count still reaches the truth test",
     SECRET,
     "            local secret = _issecret and _issecret(isInArea)"),

    # ------------------------------------------- not causing a SECOND bug for the reporter
    ("the world quest skip goes, so this starts listing world quests for a player who "
     "switched autoListZoneWorldQuests off",
     SKIP,
     "        if qid then"),

    ("the world quest skip is INVERTED, so it lists only world quests and no bonus objectives",
     SKIP,
     "        if qid and isWorldQuest(qid) then"),

    ("the quest id guard goes, so a junk entry reaches the client APIs",
     SKIP,
     "        if not isWorldQuest(qid) then"),

    # ------------------------------------------------------------ reading the client right
    ("GetTaskInfo's SECOND return is read as the objective count, so isOnMap gates the row",
     INFO,
     INFO_LEAD + "            local infoOK, isInArea, numObjectives = pcall(GetTaskInfo, qid)"),

    ("GetTaskInfo is called bare, so one raising entry costs GetEntries and the whole section",
     INFO + "\n",
     INFO_LEAD
     + "            local isInArea, _, numObjectives = GetTaskInfo(qid)\n"
     + "            local infoOK = true\n"),

    ("GetTasksTable is called bare, so a raise there costs the section too",
     "    local ok, tasks = pcall(GetTasksTable)",
     "    local ok, tasks = true, GetTasksTable()"),

    ("the table type guard goes, so a client answering nothing raises inside the length",
     '    if not ok or type(tasks) ~= "table" then return end',
     "    if not ok then return end"),

    ("the walk stops one entry short, so the last bonus objective in the table is lost",
     "    for i = 1, #tasks do",
     "    for i = 1, #tasks - 1 do"),

    # ------------------------------------------------------------------ the capability gate
    ("the capability gate goes, so a client without these globals raises on every render",
     HAS + "\n",
     ""),

    ("only one of the two globals is probed, while the source reads both",
     HAS,
     "    if not ns.Has.TasksTable then return end"),

    ("the capability gate is INVERTED, so the source runs only where the API is absent",
     HAS,
     "    if ns.Has.TasksTable and ns.Has.TaskInfo then return end"),
    # ------------------------------------------------ the source being reachable at all
    # Everything above is inside addTaskTableQuests, and the harness slices that function - so
    # all of it passes with the feature switched off upstream. These three are that upstream.
    ("the only call site goes, so the whole source is dead code and nothing lists a bonus objective",
     '    currentSource = "tasktable"; addTaskTableQuests()\n',
     ""),

    ("the secret alias is typo'd, so every guard in this file degrades to a nil call",
     "local _issecret = _G.issecretvalue\n",
     "local _issecret = _G.issecretvalue_\n"),

    # ------------------------------------------------ the row menu, newly reachable
    # Nothing could emit a bonus objective before this release, so the menu had never been
    # asked about one. Track dispatches AddWorldQuestWatch, which does not take a task quest.
    ("the row menu stops asking which group the row is in, so a bonus objective is offered Track",
     '    local isWQ = entry.groupID ~= "bonusobjectives"',
     "    local isWQ = true"),

    ("""the track pair is offered unconditionally again""",
     """    if isWQ then
        menuOut[#menuOut + 1] = { id = tracked and "untrack" or "track", order = 10 }
    end""",
     '    menuOut[#menuOut + 1] = { id = tracked and "untrack" or "track", order = 10 }'),

    ("the icon kind is left to the store default, so a pooled row keeps the world quest ring",
     "            e.icon.kind  = wq and ICON.WORLDQUEST or ICON.NONE\n",
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


original = io.open(SRC, encoding="utf-8", newline="").read()
crlf = "\r\n" in original


def fit(s):
    return s.replace("\n", "\r\n") if crlf else s


verdict, last = run()
print("baseline: %s\n" % last)
if verdict != "green":
    print("BASELINE IS NOT GREEN - stopping")
    sys.exit(1)

failures = []
for name, old, new in MUTANTS:
    old, new = fit(old), fit(new)
    if original.count(old) != 1:
        print("SKIPPED (anchor matched %d times): %s" % (original.count(old), name))
        failures.append(("SKIPPED", name))
        continue
    try:
        io.open(SRC, "w", encoding="utf-8", newline="").write(original.replace(old, new, 1))
        verdict, last = run()
    finally:
        io.open(SRC, "w", encoding="utf-8", newline="").write(original)
    equivalent = name.startswith("EQUIVALENT:")
    if verdict == "crashed":
        print("CRASHED   %-92s %s" % (name, last))
        failures.append(("CRASHED", name))
    elif verdict == "green" and not equivalent:
        print("SURVIVED  %-92s %s" % (name, last))
        failures.append(("SURVIVED", name))
    elif verdict == "failed" and equivalent:
        print("UNEXPECTED %-91s %s" % (name + " (was caught)", last))
        failures.append(("UNEXPECTED", name))
    elif equivalent:
        print("survived  %-92s as expected, it cannot change behavior" % name)
    else:
        print("caught    %-92s %s" % (name, last))

if io.open(SRC, encoding="utf-8", newline="").read() != original:
    print("\nTHE TREE WAS NOT RESTORED - %s still holds a mutant" % SRC)
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
