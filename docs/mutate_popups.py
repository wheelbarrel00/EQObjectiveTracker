"""Prove docs/test_popups.lua actually discriminates, by breaking production on purpose one change
at a time and checking the harness notices.

    python -B docs/mutate_popups.py        (run from the repo root)

Why this exists: a popup box is that quest's only prompt, Blizzard's own being suppressed, and
/eqot popup test's sample is how its place on each tab is checked at all. A sample that opens a
quest when clicked, lands in the wrong section, or never clears fails quietly, and so does a
real box whose click stops reaching the client. None of that raises a Lua error.

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
HARNESS = "docs/test_popups.lua"

P = "Data/AutoQuestPopups.lua"
U = "UI/AutoQuestPopup.lua"
C = "UI/Commands.lua"

SAMPLE_OPEN = "    if sampleOn then\n        count = count + 1\n"
SAMPLE_FIELDS = '        p.questID, p.popUpType, p.groupID, p.title = nil, "OFFER", "quests", SAMPLE_TITLE\n'
TOGGLE = "    sampleOn = not sampleOn\n    return sampleOn\n"
P_ARG = '            local P   = ns:GetModule("AutoQuestPopups")\n            local arg = strtrim(rest or ""):lower()\n'

MUTANTS = [
    # ------------------------------------------------------------------------------ the sample
    ("the sample is never added", [(P, SAMPLE_OPEN, "    if false then\n        count = count + 1\n")]),
    ("the sample is always added", [(P, SAMPLE_OPEN, "    if true then\n        count = count + 1\n")]),
    ("the sample overwrites the last real popup", [(P, SAMPLE_OPEN, "    if sampleOn then\n")]),
    ("the sample carries a quest, so a click on it opens one", [
        (P, SAMPLE_FIELDS, SAMPLE_FIELDS.replace("= nil,", "= 0,"))]),
    ("the sample is a finished quest's box", [(P, SAMPLE_FIELDS, SAMPLE_FIELDS.replace('"OFFER"', '"COMPLETE"'))]),
    ("the sample lands in Campaign", [(P, SAMPLE_FIELDS, SAMPLE_FIELDS.replace('"quests"', '"campaign"'))]),
    ("the sample takes a pooled entry and keeps its quest", [
        (P, SAMPLE_FIELDS, '        p.popUpType, p.groupID, p.title = "OFFER", "quests", SAMPLE_TITLE\n')]),
    ("the sample is not counted in its section", [(P, "        byGroup.quests = byGroup.quests + 1\n", "")]),
    ("a new sample entry is built but never stored", [
        (P, "        local p = list[count]\n        if not p then p = {}; list[count] = p end\n        p.questID, p.popUpType",
            "        local p = list[count]\n        if not p then p = {} end\n        p.questID, p.popUpType")]),
    ("the sample can never be turned off", [(P, TOGGLE, "    sampleOn = true\n    return sampleOn\n")]),
    ("the toggle answers the state it left", [
        (P, TOGGLE, "    local was = sampleOn\n    sampleOn = not sampleOn\n    return was\n")]),
    ("the status line never says the sample is on", [
        (P, 'suppressed, sampleOn and "on" or "off")', 'suppressed, "off")')]),

    # --------------------------------------------------------------------------------- the box
    ("a box with no quest still calls the client", [(U, "    if not questID then return end\n", "")]),
    ("a click asks for no repaint", [(U, '    ns:GetModule("Tracker"):Refresh()\nend\n', "end\n")]),
    ("a released box keeps its quest", [(U, "        box.questID, box.popUpType = nil, nil\n", "")]),

    # ------------------------------------------------------------------------------ the command
    ("the popup command starts a sample under Blizzard's tracker", [
        (C, '            elseif ns:UsesBlizzardTracker() then\n                ns:Print("popup: off, Blizzard\'s tracker in use")\n', "")]),
    ("the popup command reads its word case-sensitively", [
        (C, P_ARG, P_ARG.replace(":lower()", ""))]),
    ("the popup command skips the capability check", [
        (C, "            if not (P and P:Available()) then\n", "            if not P then\n")]),
    ("the popup command asks the module with a dot call", [
        (C, "            if not (P and P:Available()) then\n", "            if not (P and P.Available()) then\n")]),
    ("the sample is not drawn until something else repaints", [
        (C, "                local on = P:ToggleSample()\n                tracker():Render()\n",
            "                local on = P:ToggleSample()\n")]),
    ("on and off swap their messages", [
        (C, "                if on then\n                    local cfg = ns:GetModule(\"DB\"):Tracker()\n",
            "                if not on then\n                    local cfg = ns:GetModule(\"DB\"):Tracker()\n")]),
    ("the note about switched-off boxes never shows", [
        (C, "((cfg and cfg.showQuestPopups == false)", "((cfg and cfg.showQuestPopups == true)")]),
    ("the plain command prints the last paint", [
        (C, '                tracker():Render()\n                -- Render returns early',
            '                -- Render returns early')]),
    ("the plain command prints nothing", [
        (C, '                debugLine("AutoQuestPopups")\n            end\n        elseif cmd == "timer" then\n',
            '            end\n        elseif cmd == "timer" then\n')]),
    ("any word starts the sample", [
        (C, '            elseif arg == "test" then\n                local on = P:ToggleSample()\n',
            '            elseif arg ~= "" then\n                local on = P:ToggleSample()\n')]),
    ("the usage line leaves it out", [
        (C, '"bonushud [test], mplus [test|late], popup [test], timer [test], importeq',
            '"bonushud [test], mplus [test|late], timer [test], importeq')]),
    ("the off message is printed on", [
        (C, '                    ns:Print("popup test: off.")\n', '                    ns:Print("popup test: on.")\n')]),
    ("the bare command prints popups a hidden tracker never read", [
        (C, "                P:Refresh()\n", "")]),
]

SUMMARY = re.compile(r"^test_popups: (\d+) passed, (\d+) failed$")


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
