"""Prove docs/test_quest_progress.lua actually discriminates, by breaking production on purpose
one change at a time and checking the harness notices.

    python docs/mutate_quest_progress.py        (run from the repo root)

Why this exists: a bar had never once drawn on a quest row, and the reason was a single gate
refusing a denominator of 1 - correct on its own terms, and wrong here because the real fill was
never in that denominator at all. Nothing failed, nothing raised, and every gate this project
has was green throughout. Several mutants below put that shape back.

Unlike the other two batteries this one edits TWO files, because the feature is two halves: the
percentage source in Data/QuestProgress.lua, and the stanza in the providers that turns it into
a line the bar gate will accept. Getting either half right and the other wrong draws nothing,
which is exactly what shipped before.

Every mutation reintroduces a defect the harness is supposed to stand guard over. Any that still
reports "0 failed" is an assertion that does not discriminate, and the run exits 1 naming it.
There are no EQUIVALENT entries here - every mutant below changes behavior somewhere.

WRITES TO THE TREE. It edits in place and restores through a finally, so an interrupted run
still puts the files back, and it verifies the restore and re-checks the baseline before
reporting. If you hard-kill it anyway, recover from your editor's undo history, NOT with git -
these files are uncommitted while they are being worked on.

Anchors are exact source text and they rot. A SKIPPED line means an anchor stopped matching:
fix the anchor rather than dropping the mutant.
"""
import io
import re
import subprocess
import sys

LUA = r"C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe"
HARNESS = "docs/test_quest_progress.lua"
# UI/Row.lua and Data/Entry.lua are covered by the block builder's own harness, so a mutant in
# either is only caught if BOTH are run. A verdict is "caught" when either one notices.
HARNESS2 = "docs/test_row_blocks.lua"

SRC = "Data/QuestProgress.lua"
PROV = "Data/Providers/Quests.lua"
# The third half of the feature. A percentage that reaches a row and is then refused by the bar
# gate draws nothing, and until this file reached UI/Row.lua no battery in the tree mutated it.
ROW = "UI/Row.lua"

MUTANTS = [
    # ------------------------------------------------- the two sources, and their order
    ("the task quest source is asked before the bare global", [
        (SRC,
         """    if ns.Has.QuestProgressBar then
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
    end""",
         """    if ns.Has.TaskQuestProgressBar then
        local pct = usable(C_TaskQuest.GetQuestProgressBarInfo(questID))
        if pct then
            stats.byTask = stats.byTask + 1
            stats.lastSource, stats.lastPct, stats.lastQuest = "task", pct, questID
            return pct
        end
    end

    if ns.Has.QuestProgressBar then
        local pct = usable(GetQuestProgressBarPercent(questID))
        if pct then
            stats.byGlobal = stats.byGlobal + 1
            stats.lastSource, stats.lastPct, stats.lastQuest = "global", pct, questID
            return pct
        end
    end""")]),

    ("the second source is never reached, so a client with only it draws nothing", [
        (SRC, "    if ns.Has.TaskQuestProgressBar then", "    if false then")]),

    # ------------------------------------------------- the capability guards
    ("the bare global's guard is deleted, calling it on a client that lacks it", [
        (SRC, "    if ns.Has.QuestProgressBar then", "    if true then")]),

    ("the task quest guard is deleted, calling it on a client that lacks it", [
        (SRC, "    if ns.Has.TaskQuestProgressBar then", "    if true then")]),

    # ------------------------------------------------- what counts as an answer
    ("zero stops counting as a percentage, which is the measured case", [
        (SRC, "    if v < 0 or v > 100 then return nil end",
              "    if v <= 0 or v > 100 then return nil end")]),

    ("the range check is dropped, so a nonsense percentage reaches a bar", [
        (SRC, "    if v < 0 or v > 100 then return nil end", "    -- unchecked")]),

    ("the type check is dropped, so a string reaches the comparison", [
        (SRC, '    if type(v) ~= "number" then return nil end', "    -- unchecked")]),

    # NO reordering mutant, deliberately. In game the probe must run ahead of the range check,
    # because a real secret value reports type "number" and raises the moment it is compared -
    # but Lua 5.1 answers number-versus-number primitively and never consults an __lt installed
    # with debug.setmetatable, so no harness here can tell the two orders apart. A mutant for it
    # would read SURVIVED forever and be mistaken for a coverage hole. Its EXISTENCE is covered
    # by "the secret value probe is deleted" below.

    ("no quest id is counted as a question anyway", [
        (SRC, "    if not questID then return nil end",
              "    if not questID then stats.asked = stats.asked + 1 return nil end")]),

    # ------------------------------------------------- the instrument
    ("the counters stop saying which source answered", [
        (SRC, "            stats.byGlobal = stats.byGlobal + 1",
              "            stats.byTask = stats.byTask + 1")]),

    ("a refusal is not counted, so an absent API reads like an empty bar", [
        (SRC, """    stats.refused = stats.refused + 1
    stats.lastSource, stats.lastPct, stats.lastQuest = "none", nil, questID""",
              "    -- unrecorded")]),

    # ------------------------------------------------- the emission, in a provider
    ("the percentage is never asked for, which is the shipped bug", [
        (PROV, "                    ln.percent = ns:GetModule(\"QuestProgress\"):Percent(id)",
               "                    ln.percent = nil")]),

    # The regression this shape exists to prevent: overwriting current and required draws the
    # bar correctly and silently rewrites what a bars-OFF row prints.
    ("the percentage overwrites current and required, breaking the bars-off text", [
        (PROV, "                    ln.percent = ns:GetModule(\"QuestProgress\"):Percent(id)",
               "                    ln.current = ns:GetModule(\"QuestProgress\"):Percent(id)\n"
               "                    ln.required = 100")]),

    ("a denominator of 100 is overwritten by a source it never needed", [
        (PROV, "                if ln.kind ~= LINE.WEIGHTED then", "                if true then")]),

    ("every objective asks for a percentage, not only a progressbar one", [
        (PROV, '            if o.type == "progressbar" then',
               '            if o.type == "progressbar" or true then')]),

    # ------------------------------------------------- the row that has to accept it
    # ZERO is the measured value for quest 92149, so a gate that treats it as "no percentage"
    # refuses the one quest the feature was written for.
    ("a percentage of zero is refused by the bar gate", [
        (ROW, "    if ln.percent then return true end",
              "    if ln.percent and ln.percent > 0 then return true end")]),

    ("the bar gate ignores the percentage, so a 0 of 1 objective stays text", [
        (ROW, "    if ln.percent then return true end", "    -- unguarded")]),

    ("the bar is filled from the objective's own count rather than the percentage", [
        (ROW, "                    _bCur[_nBlocks] = math.max(0, math.min(100, ln.percent or ln.current or 0))",
              "                    _bCur[_nBlocks] = math.max(0, math.min(100, ln.current or 0))")]),

    ("a percentage line is not flagged as a percentage, so it draws against its own denominator", [
        (ROW, "                _bPct[_nBlocks]  = (ln.kind == LINE.WEIGHTED or ln.percent ~= nil) or nil",
              "                _bPct[_nBlocks]  = (ln.kind == LINE.WEIGHTED) or nil")]),

    ("the percentage is not cleared between pooled lines", [
        ("Data/Entry.lua", "    ln.percent = nil", "    -- not cleared")]),

    # ------------------------------------------------- the bisection axis
    ("the disable check is deleted, so safe mode still calls both APIs", [
        (SRC, '    if ns:IsModuleDisabled("QuestProgress") then', "    if false then")]),

    ("the disable check sits after the reads it is supposed to prevent", [
        (SRC, '    if ns:IsModuleDisabled("QuestProgress") then',
              '    if ns:IsModuleDisabled("Widgets") then')]),

    ("the secret value probe is deleted", [
        (SRC, "    if _issecret and _issecret(v) then return nil end", "    -- unguarded")]),
]

SUMMARY  = re.compile(r"^test_quest_progress: (\d+) passed, (\d+) failed$")
SUMMARY2 = re.compile(r"^test_row_blocks: (\d+) passed, (\d+) failed$")


def run():
    """(verdict, note). verdict is "green", "failed" or "crashed".

    A nonzero exit is NOT evidence that an assertion discriminated. A mutant that does not parse
    exits nonzero too, and reporting that as "caught" is a false pass in the one tool whose job
    is to catch false passes. So the harness's own summary line is matched rather than its exit
    code, and a run that never got that far is its own verdict.
    """
    worst, notes = "green", []
    for harness, pat in ((HARNESS, SUMMARY), (HARNESS2, SUMMARY2)):
        r = subprocess.run([LUA, harness], capture_output=True, text=True)
        seen = None
        for line in reversed([l for l in r.stdout.splitlines() if l.strip()]):
            m = pat.match(line.strip())
            if m:
                seen = ("failed" if int(m.group(2)) else "green"), line.strip()
                break
        if seen is None:
            return "crashed", (r.stderr.strip().splitlines() or ["no output"])[0][:90]
        notes.append(seen[1])
        # One harness noticing is enough: a mutant only survives if BOTH stay green.
        if seen[0] == "failed":
            worst = "failed"
    return worst, " | ".join(notes)


FILES = sorted({f for _, hunks in MUTANTS for f, _, _ in hunks})
original = {f: io.open(f, encoding="utf-8", newline="").read() for f in FILES}


def fit(f, s):
    return s.replace("\n", "\r\n") if "\r\n" in original[f] else s


def restore():
    for f, text in original.items():
        io.open(f, "w", encoding="utf-8", newline="").write(text)


verdict, last = run()
print("baseline: %s\n" % last)
if verdict != "green":
    print("BASELINE IS NOT GREEN - stopping")
    sys.exit(1)

survivors = []
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
        survivors.append(name)
        continue
    try:
        for f, text in edited.items():
            io.open(f, "w", encoding="utf-8", newline="").write(text)
        verdict, last = run()
    finally:
        restore()
    if verdict == "crashed":
        print("CRASHED   %-72s %s" % (name, last))
        survivors.append(name)
    elif verdict == "green":
        print("SURVIVED  %-72s %s" % (name, last))
        survivors.append(name)
    else:
        print("caught    %-72s %s" % (name, last))

for f in FILES:
    if io.open(f, encoding="utf-8", newline="").read() != original[f]:
        print("\nTHE TREE WAS NOT RESTORED - %s still holds a mutant" % f)
        sys.exit(1)
verdict, last = run()
if verdict != "green":
    print("\nBASELINE IS NOT GREEN AFTER THE RUN - %s" % last)
    sys.exit(1)

print()
if survivors:
    print("%d mutant(s) survived - those assertions do not discriminate:" % len(survivors))
    for s in survivors:
        print("  - " + s)
    sys.exit(1)
print("every mutant behaved as expected")
