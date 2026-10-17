"""Prove docs/test_popout.lua actually discriminates, by breaking production on purpose one
change at a time and checking the harness notices.

    python -B docs/mutate_popout.py        (run from the repo root)

Why this exists: "Pop out Quest Details" fails silently. On WoW Forever it showed an empty
window with no Lua error, because the fill it called had moved into a frame method. The fix
hands the quest to QuestUtil.OpenQuestDetails, and every way that hand-off can break (dropped,
called before a guard, called and then followed by the old sequence, called without the quest)
is just as quiet. The old sequence stays as the fallback for a client with no wrapper, so its
steps are mutated too.

Every mutation reintroduces a defect the harness is supposed to stand guard over. Any that still
reports "0 failed" is an assertion that does not discriminate, and the run exits 1 naming it. A
mutant marked EQUIVALENT is expected to survive and fails the run if caught. There are none.

WRITES TO THE TREE. It edits in place and restores through a finally, so an interrupted run
still puts the file back, and it verifies the restore and re-checks the baseline before
reporting. This checkout is junctioned into AddOns, so run it from a scratch copy while the game
is open.

Anchors are exact source text and they rot. A SKIPPED line means an anchor stopped matching:
fix the anchor rather than dropping the mutant.
"""
import io
import re
import subprocess
import sys

LUA = r"C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe"
HARNESS = "docs/test_popout.lua"

Q = "Data/Providers/Quests.lua"

LOAD = '    if C_AddOns and C_AddOns.LoadAddOn then C_AddOns.LoadAddOn("Blizzard_QuestLog") end\n'
FRAME_GUARD = "    if not QuestLogPopupDetailFrame then return end\n"
LOG_GUARD = ("    if not (C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id))"
             " then return end\n")
WRAP_TEST = "    if QuestUtil and QuestUtil.OpenQuestDetails then\n"
WRAP_CALL = "        QuestUtil.OpenQuestDetails(id)\n"
WRAP = WRAP_TEST + WRAP_CALL + "        return\n    end\n"
SET_ID = "    QuestLogPopupDetailFrame.questID = id\n"
SELECT = "    if C_QuestLog.SetSelectedQuest then C_QuestLog.SetSelectedQuest(id) end\n"
HIDE_ITEMS = '        StaticPopup_Hide("ABANDON_QUEST_WITH_ITEMS")\n'
HIDE_PLAIN = '        StaticPopup_Hide("ABANDON_QUEST")\n'
BUTTONS = ("    if QuestMapFrame_UpdateQuestDetailsButtons then"
           " QuestMapFrame_UpdateQuestDetailsButtons() end\n")
UPDATE = "    if QuestLogPopupDetailFrame_Update then QuestLogPopupDetailFrame_Update(true) end\n"
SHOW = "    QuestLogPopupDetailFrame:Show()\n"

MUTANTS = [
    # ------------------------------------------------------------------- the wrapper
    ("the wrapper branch is gone, so Forever shows the empty window again", [
        (Q, WRAP, "")]),

    ("the wrapper runs and then falls through into the old sequence", [
        (Q, WRAP_CALL + "        return\n", WRAP_CALL)]),

    ("the wrapper is called without the quest", [
        (Q, WRAP_CALL, "        QuestUtil.OpenQuestDetails()\n")]),

    ("the wrapper test stops asking for the function, calling nil", [
        (Q, WRAP_TEST, "    if QuestUtil then\n")]),

    ("the wrapper test asks for the old global instead, so Forever skips it", [
        (Q, WRAP_TEST, "    if QuestUtil and QuestLogPopupDetailFrame_Update then\n")]),

    ("the wrapper runs before the log guard, opening a quest the log does not hold", [
        (Q, WRAP, ""),
        (Q, LOG_GUARD, WRAP + LOG_GUARD)]),

    ("the wrapper runs before the frame guard, calling into a missing window", [
        (Q, WRAP, ""),
        (Q, LOAD + "\n" + FRAME_GUARD, LOAD + "\n" + WRAP + FRAME_GUARD)]),

    # -------------------------------------------------------------------- the guards
    ("the frame guard is dropped", [
        (Q, FRAME_GUARD, "")]),

    ("the log guard is dropped", [
        (Q, LOG_GUARD, "")]),

    ("Blizzard_QuestLog loads after the frame guard, so an on-demand window never opens", [
        (Q, LOAD + "\n" + FRAME_GUARD, FRAME_GUARD + LOAD)]),

    ("Blizzard_QuestLog is never loaded", [
        (Q, LOAD + "\n" + FRAME_GUARD, FRAME_GUARD)]),

    # ------------------------------------------------------- the fallback, no wrapper
    ("the fallback never fills the window", [
        (Q, UPDATE, "")]),

    ("the fallback fills without a scroll reset", [
        (Q, UPDATE, "    if QuestLogPopupDetailFrame_Update then QuestLogPopupDetailFrame_Update() end\n")]),

    ("the fallback never shows the window", [
        (Q, SHOW, "")]),

    ("the fallback shows the window before filling it", [
        (Q, UPDATE + SHOW, SHOW + UPDATE)]),

    ("the fallback never selects the quest", [
        (Q, SELECT, "")]),

    ("the fallback never writes the frame's quest", [
        (Q, SET_ID, "")]),

    ("the fallback leaves the item-loss abandon prompt open", [
        (Q, HIDE_ITEMS, "")]),

    ("the fallback leaves the plain abandon prompt open", [
        (Q, HIDE_PLAIN, "")]),

    ("the fallback never updates the detail buttons", [
        (Q, BUTTONS, "")]),

    # Scan 1 (2026-10-16): the window still on an earlier quest.
    ("the wrapper is handed the quest the window last showed", [
        (Q, "        QuestUtil.OpenQuestDetails(id)\n",
            "        QuestUtil.OpenQuestDetails(QuestLogPopupDetailFrame.questID or id)\n")]),

    ("the log is asked about the quest the window last showed", [
        (Q, "    if not (C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id)) then return end\n",
            "    if not (C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(QuestLogPopupDetailFrame.questID or id)) then return end\n")]),
]

SUMMARY = re.compile(r"^test_popout: (\d+) passed, (\d+) failed$")


def run():
    """(verdict, note). verdict is "green", "failed" or "crashed".

    A nonzero exit is NOT evidence that an assertion discriminated - a mutant that does not parse
    exits nonzero too - so the harness's own summary line is matched rather than its exit code,
    and a run that never got that far is its own verdict.
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
    return s.replace("\n", "\r\n") if "\r\n" in original[f] else s


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
        # this mutant's name.
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
        print("equivalent %-73s %s" % (name, last))
    else:
        print("caught    %-74s %s" % (name, last))

for f in FILES:
    if io.open(f, encoding="utf-8", newline="").read() != original[f]:
        print("\nTHE TREE WAS NOT RESTORED - %s still holds a mutant" % f)
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
