"""Prove docs/test_scenario_bars.lua actually discriminates, by breaking UI/Scenario.lua's
criteria draw on purpose one change at a time and checking the harness notices.

    python docs/mutate_scenario_bars.py         (run from the repo root)

Why this exists: showScenarioProgressBars shipped in v1.18.0 with no coverage on the side that
CONSUMES it. _DrawCriteria is that side and nothing sliced it, so the first four mutants below -
the switch ignored, the switch inverted, the switch wired to the QUEST key, the master ignored -
would every one of them have survived the whole tree being green. A harness written to close
that gap has to be shown to close it, which is what this file is for.

It also mutates Scenario:ReleaseCriteria, which the harness slices out of the same file. An
adversarial pass found 7 of its 9 statements deletable with the harness green - row:Hide()
among them, which is what takes an orphaned criterion off SCREEN when a stage shrinks, and
the one an #activeCriteria length check can never see.

Every mutation reintroduces a defect the harness is supposed to stand guard over. Any that still
reports "0 failed" is an assertion that does not discriminate, and the run exits 1 naming it -
unless the entry is marked EQUIVALENT, which means the mutation provably cannot change behavior
and so nothing could catch it.

A mutant that makes _DrawCriteria RAISE is caught rather than crashing the file, because the
harness pcalls every call into the slice and asserts on the result. That is deliberate: every
battery in this tree reads a missing summary line as a SURVIVOR, so an unprotected harness would
report a crash as a coverage hole.

A CRASHED verdict is still reported apart from "caught" on purpose. A mutant that does not parse
exits nonzero too, and counting that as caught is a false pass in the one tool whose job is to
find false passes.

WRITES TO THE TREE. It edits UI/Scenario.lua in place and restores it after every mutant through
a finally, then verifies the restore and re-checks the baseline before reporting. If you
hard-kill it, recover from your editor's undo history.

Anchors are exact source text and they rot. A SKIPPED line means an anchor stopped matching: fix
the anchor rather than dropping the mutant.
"""
import io
import re
import subprocess
import sys

LUA = r"C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe"
SRC = "UI/Scenario.lua"
HARNESS = "docs/test_scenario_bars.lua"
SUMMARY = re.compile(r"^test_scenario_bars: (\d+) passed, (\d+) failed$")

GATE = ("        if not ln.completed and (not cfg or (cfg.showProgressBars ~= false\n"
        "                                             and cfg.showScenarioProgressBars ~= false)) then")

MUTANTS = [
    # ------------------------------------------------------- the switch this file exists for
    ("the scenario half is ignored, so switching it off still draws bars",
     GATE,
     "        if not ln.completed and (not cfg or (cfg.showProgressBars ~= false)) then"),

    ("the scenario half is INVERTED, so the switch does the opposite of what it says",
     "and cfg.showScenarioProgressBars ~= false)) then",
     "and cfg.showScenarioProgressBars == false)) then"),

    ("the scenario half is wired to the QUEST key, so the two halves move together",
     "and cfg.showScenarioProgressBars ~= false)) then",
     "and cfg.showQuestProgressBars ~= false)) then"),

    ("the master switch is ignored, so turning all bars off leaves the scenario ones drawing",
     GATE,
     "        if not ln.completed and (not cfg or (cfg.showScenarioProgressBars ~= false)) then"),

    ("both switches go, so the bars can never be turned off at all",
     GATE,
     "        if not ln.completed then"),

    ("the nil-config guard goes, so a render before the profile loads raises",
     "(not cfg or (cfg.showProgressBars ~= false",
     "((cfg.showProgressBars ~= false"),

    # ------------------------------------------------------- what is deliberately not a bar
    ("a completed criterion draws a bar over its own checkmark",
     "        if not ln.completed and (not cfg or (cfg.showProgressBars ~= false",
     "        if (not cfg or (cfg.showProgressBars ~= false"),

    ("a 0/1 criterion draws a bar, which reads as broken beside the checkmark rows",
     "            elseif ln.kind == LINE.PROGRESSBAR and ln.required and ln.required > 1 then",
     "            elseif ln.kind == LINE.PROGRESSBAR and ln.required and ln.required > 0 then"),

    ("a weighted line is treated as a count, so a percentage loses its denominator",
     "            if ln.kind == LINE.WEIGHTED then\n"
     "                barValue, barMax = math.max(0, math.min(100, ln.current or 0)), 100",
     "            if false then\n"
     "                barValue, barMax = math.max(0, math.min(100, ln.current or 0)), 100"),

    ("the bars-off meter drops a 0/1 criterion, so a yes-or-no row loses its numbers",
     "                elseif ln.kind == LINE.PROGRESSBAR and ln.required and ln.required > 0 then",
     "                elseif ln.kind == LINE.PROGRESSBAR and ln.required and ln.required > 1 then"),

    # ------------------------------------------------------- clamping and labels
    ("a weighted value stops clamping at 100, so an overrun bar runs off its own track",
     "                barValue, barMax = math.max(0, math.min(100, ln.current or 0)), 100",
     "                barValue, barMax = ln.current or 0, 100"),

    ("a count stops clamping to its denominator",
     "                barValue = math.max(0, math.min(ln.required, ln.current or 0))",
     "                barValue = ln.current or 0"),

    ("the percentage label reports the raw value rather than the clamped one",
     '                barLabel = ("%d%%"):format(barValue)',
     '                barLabel = ("%d%%"):format(ln.current or 0)'),

    ("the count label reports the raw value rather than the clamped one",
     '                barLabel = ("%d/%d"):format(barValue, barMax)',
     '                barLabel = ("%d/%d"):format(ln.current or 0, barMax)'),

    # ------------------------------------------------------- the text the bars-off path keeps
    ("the meter is dropped from the text, so with bars off the numbers vanish entirely",
     "                    label = (label ~= \"\") and (meter .. \" \" .. label) or meter",
     "                    label = label"),

    ("a completed criterion keeps its meter, where the default tracker drops it",
     "            local label = ln.text or \"\"\n            if not ln.completed then",
     "            local label = ln.text or \"\"\n            if true then"),

    ("the completed and unfinished text colors are swapped",
     "                row.text:SetTextColor(0.27, 1.0, 0.27)\n"
     "            else\n"
     "                row.text:SetTextColor(0.85, 0.85, 0.85)",
     "                row.text:SetTextColor(0.85, 0.85, 0.85)\n"
     "            else\n"
     "                row.text:SetTextColor(0.27, 1.0, 0.27)"),

    ("the checkmark and the nub atlases are swapped",
     '            Util.SafeSetAtlas(row.icon, ln.completed and "ui-questtracker-tracker-check"\n'
     '                                                      or "ui-questtracker-objective-nub")',
     '            Util.SafeSetAtlas(row.icon, ln.completed and "ui-questtracker-objective-nub"\n'
     '                                                      or "ui-questtracker-tracker-check")'),

    # ------------------------------------------------------- the gap Scenario:Render sums again
    ("a row after a bar pays the plain gap, so the panel is drawn short of its own content",
     "        row._gapAbove = (prev and prevBar) and BAR_TEXT_GAP or CRITERIA_LINE_GAP",
     "        row._gapAbove = CRITERIA_LINE_GAP"),

    ("every row after the first pays the wide gap, whether a bar drew or not",
     "        row._gapAbove = (prev and prevBar) and BAR_TEXT_GAP or CRITERIA_LINE_GAP",
     "        row._gapAbove = prev and BAR_TEXT_GAP or CRITERIA_LINE_GAP"),

    ("a bar stops reporting itself to the row below it",
     "        prev, prevBar = row, barValue ~= nil",
     "        prev, prevBar = row, false"),

    # ------------------------------------------------------- geometry
    ("the bar takes the build-time seed height rather than the user's",
     "    local barH     = Media:ProgressBarHeight()",
     "    local barH     = BAR_H"),

    ("the first row stops paying for the widget block above it, so the two overlap",
     "                      + BANNER_GAP + BANNER_H + (self.widgetH or 0) + CRITERIA_LINE_GAP",
     "                      + BANNER_GAP + BANNER_H + CRITERIA_LINE_GAP"),

    ("the first row stops paying for the offset the widget block was anchored from",
     "    local firstRowY = (self.topOffset or 0) + (self.subHeaderH or SUBHEADER_H)",
     "    local firstRowY = (self.subHeaderH or SUBHEADER_H)"),

    ("the bar row is drawn full width rather than at its ratio",
     "    local barWidth = math.max(1, math.floor(width * BAR_W_RATIO))",
     "    local barWidth = math.max(1, math.floor(width))"),

    ("a text row loses its side padding and runs to the container edge",
     "    local rowWidth = math.max(1, width - 16)",
     "    local rowWidth = math.max(1, width)"),

    ("a labeled bar row stops paying for the bar in its own height, so rows overlap",
     "                row:SetHeight(row.text:GetStringHeight() + BAR_TEXT_GAP + barH)",
     "                row:SetHeight(row.text:GetStringHeight() + BAR_TEXT_GAP)"),

    ("the bar sits flush against its label rather than the gap below it",
     '                row.bar:SetPoint("TOP", row.text, "BOTTOM", 0, -BAR_TEXT_GAP)',
     '                row.bar:SetPoint("TOP", row.text, "BOTTOM", 0, 0)'),

    ("an empty label draws a blank line above the bar rather than the bar alone",
     '            if ln.text ~= "" then',
     "            if true then"),

    ("a pooled row keeps whatever width it last drew with, so one criterion wraps and the "
     "next overflows",
     "                row.text:SetWidth(barWidth)",
     "                row.text:SetWidth(row.text:GetWidth() or barWidth)"),

    # ------------------------------------------------------- the styling and font hooks
    ("the shared progress bar styling is never applied, so the user's texture and colors are lost",
     "            Media:ApplyProgressBar(row.bar)",
     "            local _ = row.bar"),

    ("the bar's own label never takes the criteria font",
     "        Media:ApplyScenarioCriteriaFont(row.bar.label)",
     "        local _ = row.bar.label"),

    ("the bar's own label never takes the text shadow",
     "        Media:ApplyTextShadow(row.bar.label)",
     "        local _ = row.bar.label"),

    # ------------------------------------------------------- ReleaseCriteria, sliced and driven
    ("a released row is dropped from the run but left DRAWN over whatever replaces it",
     "        row:Hide()\n",
     ""),

    ("a released row keeps its old anchor, so it reappears where it used to be",
     "        row:Hide()\n        row:ClearAllPoints()\n",
     "        row:Hide()\n"),

    ("a released BAR row leaves its bar on screen",
     "        row:ClearAllPoints()\n        row.bar:Hide()\n",
     "        row:ClearAllPoints()\n"),

    ("a released row leaves its objective icon on screen",
     "        row.bar:Hide()\n        row.icon:Hide()\n",
     "        row.bar:Hide()\n"),

    ("a released row keeps its icon anchored",
     "        row.icon:Hide()\n        row.icon:ClearAllPoints()\n",
     "        row.icon:Hide()\n"),

    ("a released row keeps its text anchored",
     "        row.icon:ClearAllPoints()\n        row.text:ClearAllPoints()\n",
     "        row.icon:ClearAllPoints()\n"),

    ("a released row keeps its wrap width, so the next criterion to reuse it measures wrong",
     "        row.text:SetWidth(0)\n",
     ""),

    ("a released row keeps its old string, which a pooled reuse can flash",
     '        row.text:SetWidth(0)\n        row.text:SetText("")\n',
     '        row.text:SetWidth(0)\n'),

    # ------------------------------------------------------- the styling arity
    ("the scenario bars skip the fill, silently losing the user's bar color",
     "            Media:ApplyProgressBar(row.bar)",
     "            Media:ApplyProgressBar(row.bar, true)"),

    ("the criteria font goes on the bar label twice and never on the row's own text",
     "        Media:ApplyScenarioCriteriaFont(row.text)",
     "        Media:ApplyScenarioCriteriaFont(row.bar.label)"),

    ("the text shadow goes on the bar label twice and never on the row's own text",
     "        Media:ApplyTextShadow(row.text)",
     "        Media:ApplyTextShadow(row.bar.label)"),

    # ------------------------------------------------------- text-row geometry
    ("a text row loses its height floor, so the panel is short by 2px per criterion",
     "            row:SetHeight(math.max(row.text:GetStringHeight(), 14))",
     "            row:SetHeight(row.text:GetStringHeight())"),

    ("a bar's label loses the gold that separates it from an ordinary criterion",
     "                row.text:SetTextColor(1, 0.82, 0)",
     "                row.text:SetTextColor(1, 1, 1)"),

    ("the objective icon is drawn flush against the row edge",
     '            row.icon:SetPoint("LEFT", row, "LEFT", 8, 0)',
     '            row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)'),

    ("a criterion's text anchors to the row rather than to its own icon, so they overlap",
     '            row.text:SetPoint("LEFT",  row.icon, "RIGHT", 6, 0)',
     '            row.text:SetPoint("LEFT",  row, "RIGHT", 6, 0)'),

    # ------------------------------------------------------- the first row's anchor
    ("every row anchors to the previous one, so the first has nothing to hang from",
     '            row:SetPoint("TOP", container, "TOP", 0, -firstRowY)',
     '            row:SetPoint("TOP", container, "TOP", 0, 0)'),

    # ------------------------------------------------- added 2026-09-02 by the test-code scan
    # Every one of these survived a green 149-assertion run before the cases above were added.
    ("the sub-header height is ignored, so a two-tier header overlaps its first criterion",
     "    local firstRowY = (self.topOffset or 0) + (self.subHeaderH or SUBHEADER_H)",
     "    local firstRowY = (self.topOffset or 0) + SUBHEADER_H"),

    ("a bar row never hides the objective icon, leaving a nub behind the first bar",
     """            row:SetWidth(barWidth)
            row.icon:Hide()""",
     "            row:SetWidth(barWidth)"),

    ("a text row never hides the bar, leaving a StatusBar behind the first criterion",
     """            row:SetWidth(rowWidth)
            row.bar:Hide()""",
     "            row:SetWidth(rowWidth)"),

    ("the bar fills from its own maximum, so every bar draws full at any value",
     "            row.bar:SetMinMaxValues(0, barMax)",
     "            row.bar:SetMinMaxValues(barMax, barMax)"),

    ("a bar's label wraps to the ROW, so it overhangs the bar it labels",
     "                row.text:SetWidth(barWidth)",
     "                row.text:SetWidth(rowWidth)"),

    ("a criterion's text is never pinned to the row's right edge, so it has no wrap width",
     '            row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)',
     "            -- the right anchor is gone"),

    ("the row width guard is dropped, so a container mid-layout sizes a row to -16",
     "    local rowWidth = math.max(1, width - 16)",
     "    local rowWidth = width - 16"),

    ("the bar width guard is dropped, so a container mid-layout sizes a bar to zero",
     "    local barWidth = math.max(1, math.floor(width * BAR_W_RATIO))",
     "    local barWidth = math.floor(width * BAR_W_RATIO)"),

    ("a container that answers no width at all raises inside math.max",
     "    local width    = math.max(1, container:GetWidth() or 1)",
     "    local width    = math.max(1, container:GetWidth())"),
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
        print("CRASHED   %-88s %s" % (name, last))
        failures.append(("CRASHED", name))
    elif verdict == "green" and not equivalent:
        print("SURVIVED  %-88s %s" % (name, last))
        failures.append(("SURVIVED", name))
    elif verdict == "failed" and equivalent:
        print("UNEXPECTED %-87s %s" % (name + " (was caught)", last))
        failures.append(("UNEXPECTED", name))
    elif equivalent:
        print("survived  %-88s as expected, it cannot change behavior" % name)
    else:
        print("caught    %-88s %s" % (name, last))

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
