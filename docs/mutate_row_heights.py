"""Prove docs/test_row_heights.lua actually discriminates, by breaking production on purpose one
change at a time and checking the harness notices.

    python docs/mutate_row_heights.py        (run from the repo root)

Why this exists: the re-check is invisible when it works and nearly invisible when it does not. A
check that never fires leaves the overlap it was written for, which only shows on a row whose text
reads differently after Render measured it. A check that fires on nothing, or never stops, lays
the tracker out over and over, which shows as nothing at all until someone profiles it. A check
that gives up for good switches itself off for the session. None of that raises a Lua error, and
no gate in this repo can see any of it.

Every mutation reintroduces a defect the harness is supposed to stand guard over. Any that still
reports "0 failed" is an assertion that does not discriminate, and the run exits 1 naming it.

WRITES TO THE TREE. It edits in place and restores through a finally, so an interrupted run
still puts the file back, and it verifies the restore and re-checks the baseline before
reporting. If you hard-kill it anyway and the file is committed, git restore is the recovery;
while the work is still uncommitted it is your editor's undo history instead.

Anchors are exact source text and they rot. A SKIPPED line means an anchor stopped matching:
fix the anchor rather than dropping the mutant.
"""
import io
import re
import subprocess
import sys

LUA = r"C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe"
HARNESS = "docs/test_row_heights.lua"

R = "UI/Row.lua"
T = "UI/Tracker.lua"
C = "UI/Commands.lua"

SUB_READ = ("    if row.subtitle:IsShown() then h = h + TITLE_TO_SUB"
            " + row.subtitle:GetStringHeight() end\n")
STORE = "    row._mStr, row._mText = titleH + subH + textH, nText\n"
SUM = "            textH = textH + blockH\n"
REBASE = "    if row._mStr then row._mStr = row._mStr + self:Drift(row) end\n"
HIDDEN = "    if not f or f._eqotHidden or not f:IsShown() then return end\n"
WORST = "                if math.abs(d) > math.abs(worst) then worst = d end\n"
MIN_CONST = "local DRIFT_MIN = 0.5\n"
SETTLED = "            if math.abs(d) < DRIFT_MIN then\n"
SETTLED_RESET = SETTLED + "                row._mTries = nil\n"
BUMP = "                row._mTries = (row._mTries or 0) + 1\n"
CAP = "                if row._mTries > DRIFT_MAX then\n"
REBASE_CALL = "                    Row:Rebase(row)\n"
GIVEUP_RESET = REBASE_CALL + "                    row._mTries = nil\n"
PICK = ("                elseif math.abs(d) > math.abs(fix) then\n"
        "                    fix = d\n")
GAVE_UP = "    if gaveUp then self._driftGaveUp = (self._driftGaveUp or 0) + 1 end\n"
FIXGATE = "    if math.abs(fix) < DRIFT_MIN then return end\n"
FIXES = "    self._driftFixes = (self._driftFixes or 0) + 1\n"
INVALIDATE = FIXES + "    Row:Invalidate()\n"
# Anchored on the call alone, never on the note above it: the prose was reworded once and
# took two mutants quietly to SKIPPED with it.
REFRESH = "\n    self:Refresh()\n"
LAST = "    if math.abs(worst) >= DRIFT_MIN then self._driftLast = worst end\n"
RESET_ROW = "    row._mStr, row._mText, row._mTries = nil, nil, nil\n"
STATUS = '    debugLine("Tracker", nil, "HeightLine")\n'

MUTANTS = [
    # ------------------------------------------------------------------------- Row:Drift
    ("Drift loses its nil guard, raising on a row Render never measured", [
        (R, "    if not row._mStr then return 0 end\n", "")]),

    ("Drift ignores the title, so a title that wrapped late is never caught", [
        (R, "    local h = row.title:GetStringHeight()\n", "    local h = 0\n")]),

    ("Drift skips the subtitle, so every row with one reads as drifted", [
        (R, SUB_READ, "")]),

    ("Drift drops the gap Render adds under a subtitle", [
        (R, SUB_READ, "    if row.subtitle:IsShown() then h = h + row.subtitle:GetStringHeight() end\n")]),

    ("Drift reads the subtitle even while it is hidden", [
        (R, SUB_READ, SUB_READ.replace("if row.subtitle:IsShown() then", "if true then"))]),

    ("Drift reads every pooled block, including stale hidden ones", [
        (R, "    for i = 1, row._mText or 0 do", "    for i = 1, #row._textBlocks do")]),

    ("Drift answers with the sign flipped", [
        (R, "    return h - row._mStr\n", "    return row._mStr - h\n")]),

    # A float jitter of -0.3 floors to -1, which reads as a real move.
    ("Drift rounds down, so sub-pixel jitter lays the tracker out", [
        (R, "    return h - row._mStr\n", "    return math.floor(h - row._mStr)\n")]),

    # ------------------------------------------------------------------------- Row:Rebase
    ("Rebase does nothing, so a give-up leaves the row drifted", [
        (R, REBASE, "")]),

    ("Rebase subtracts the drift instead of adding it", [
        (R, REBASE, REBASE.replace("row._mStr + self:Drift(row)", "row._mStr - self:Drift(row)"))]),

    ("Rebase loses its nil guard, raising on a row Render never measured", [
        (R, REBASE, "    row._mStr = row._mStr + self:Drift(row)\n")]),

    # ------------------------------------------------------------ what Render stores for it
    ("Render stops summing its text blocks", [
        (R, SUM, "")]),

    ("Render stores the title and subtitle without the text", [
        (R, STORE, "    row._mStr, row._mText = titleH + subH, nText\n")]),

    # linesH carries the gaps and the bar heights, which no string read can ever match.
    ("Render stores the laid-out height, gaps and bars included", [
        (R, STORE, "    row._mStr, row._mText = titleH + subH + linesH, nText\n")]),

    ("Render records no block count, so Drift reads no blocks", [
        (R, STORE, "    row._mStr = titleH + subH + textH\n")]),

    ("Reset keeps the stored measurement on a row going back to the pool", [
        (R, RESET_ROW, "")]),

    ("Reset hands a pooled row on with the budget the last quest spent", [
        (R, RESET_ROW, "    row._mStr, row._mText = nil, nil\n")]),

    # Stray writes, each a one-line insertion in a spelling the exact-line greps do not match.
    ("a stray reset after the store switches the check off", [
        (R, "    row._sGen = self.generation\n",
            "    row._sGen = self.generation\n    row._mStr = nil\n")]),

    ("a stray zero block count after the store", [
        (R, "    row._sGen = self.generation\n",
            "    row._sGen = self.generation\n    row._mText = 0\n")]),

    ("a stray reset of the text sum before the store", [
        (R, "    hideBlocks(row, nText + 1, nBar + 1)\n",
            "    hideBlocks(row, nText + 1, nBar + 1)\n    textH = 0\n")]),

    ("bars are summed as text, so every row with a bar reads as drifted", [
        (R, "            blockH = Media:ProgressBarHeight()\n",
            "            blockH = Media:ProgressBarHeight()\n            textH = blockH + textH\n")]),

    ("gaps are summed as text", [
        (R, SUM, SUM + "            textH = gap + textH\n")]),

    ("the subtitle gap is stored for rows that have none", [
        (R, STORE, STORE + "    if not row.subtitle:IsShown() then row._mStr = row._mStr"
                           " + TITLE_TO_SUB end\n")]),

    # ------------------------------------------------------------------ arming the check
    ("the latch is dropped, so every caller in a frame queues its own check", [
        (T, "    if self._heightArmed then return end\n", "")]),

    ("the latch is never cleared, so the check runs once a session", [
        (T, "        self._heightArmed = nil\n", "")]),

    ("the check waits a second instead of the next frame", [
        (T, "    C_Timer.After(0, self._heightCheck)\n", "    C_Timer.After(1, self._heightCheck)\n")]),

    ("Render no longer arms the check", [
        (T, "    self:_EnsureTimerTicker(hasTimed, soonestExpiry)\n    self:_ArmHeightCheck()\n",
            "    self:_EnsureTimerTicker(hasTimed, soonestExpiry)\n")]),

    ("the cap is raised past what the harness allows", [
        (T, "local DRIFT_MAX = 3\n", "local DRIFT_MAX = 10\n")]),

    ("the callback refuses to check again once anything has given up", [
        (T, "        self._heightArmed = nil\n",
            "        self._heightArmed = nil\n"
            "        if (self._driftGaveUp or 0) > 0 then return end\n")]),

    # --------------------------------------------------------------------- the check
    ("the hidden guard is dropped, so a hidden tracker is laid out", [
        (T, HIDDEN, "    if not f then return end\n")]),

    ("only the Visibility half of the hidden guard is dropped", [
        (T, HIDDEN, "    if not f or not f:IsShown() then return end\n")]),

    ("the frame guard is dropped, raising before the tracker is built", [
        (T, HIDDEN, "    if f._eqotHidden or not f:IsShown() then return end\n")]),

    ("only the quest rows are walked, so a world quest or achievement row is never read", [
        (T, "    for _, byID in pairs(RowPool.byProvider) do\n"
            "        for _, row in pairs(byID) do\n",
            "    for _, byID in pairs({ RowPool.byProvider.quests or {} }) do\n"
            "        for _, row in pairs(byID) do\n")]),

    ("rows are walked by counting from one, so rows keyed by quest id are never read", [
        (T, "    for _, byID in pairs(RowPool.byProvider) do\n"
            "        for _, row in pairs(byID) do\n",
            "    for _, byID in pairs(RowPool.byProvider) do\n"
            "        for _, row in ipairs(byID) do\n")]),

    ("the worst move is picked by sign, so a shrink never wins", [
        (T, WORST, "                if d > worst then worst = d end\n")]),

    ("the last nonzero move wins, so a settled row read after a real one masks it", [
        (T, WORST, "                if d ~= 0 then worst = d end\n")]),

    ("the last row read wins, whatever it reads", [
        (T, WORST, "                worst = d\n")]),

    ("the settled test loses its abs, so any shrink reads as settled", [
        (T, SETTLED, "            if d < DRIFT_MIN then\n")]),

    ("the settle threshold is widened until a whole line reads as rounding", [
        (T, MIN_CONST, "local DRIFT_MIN = 20\n")]),

    ("the settle threshold is widened to two pixels", [
        (T, MIN_CONST, "local DRIFT_MIN = 2\n")]),

    ("the settle threshold is narrowed until rounding lays the tracker out", [
        (T, MIN_CONST, "local DRIFT_MIN = 0.1\n")]),

    # The two tests disagreeing is what let a narrowed settle test hide behind the layout one.
    ("the settle test keeps its own threshold, so it can drift from the layout test", [
        (T, SETTLED, "            if math.abs(d) < 0.1 then\n")]),

    ("the layout test keeps its own threshold", [
        (T, FIXGATE, "    if math.abs(fix) < 20 then return end\n")]),

    ("a settled read never hands the budget back, so a row spends it for the session", [
        (T, SETTLED_RESET, SETTLED)]),

    # The defect the per-row budget replaced: one run shared by every row, so DRIFT_MAX checks
    # with ANY row moving refused the next row to be drawn on its very first drift.
    ("the budget is shared, so a late arrival is refused for an earlier row's run", [
        (T, BUMP, "                self._mShared = (self._mShared or 0) + 1\n"),
        (T, CAP, "                if self._mShared > DRIFT_MAX then\n")]),

    ("the cap is removed, so a height that never settles lays out without end", [
        (T, CAP, "                if false then\n")]),

    ("the cap stops one layout early", [
        (T, CAP, "                if row._mTries >= DRIFT_MAX then\n")]),

    ("the budget is counted but never spent, so it can never be exceeded", [
        (T, BUMP, "                row._mTries = 1\n")]),

    ("a give-up does not hand the budget back, so the next move is refused at once", [
        (T, GIVEUP_RESET, REBASE_CALL)]),

    ("a give-up does not rebase, so the stuck row is read as moved forever", [
        (T, REBASE_CALL, "")]),

    ("a give-up polls instead of stopping", [
        (T, GAVE_UP, GAVE_UP + "    if gaveUp then C_Timer.After(1, self._heightCheck) end\n")]),

    ("a give-up is not counted", [
        (T, GAVE_UP, "")]),

    ("a row past its budget still drives the layout it was refused", [
        (T, PICK, "                end\n                if math.abs(d) > math.abs(fix) then\n"
                  "                    fix = d\n")]),

    ("how far it was off is only recorded when a layout follows", [
        (T, LAST, ""),
        (T, FIXES, FIXES + "    self._driftLast = worst\n")]),

    ("how far it was off is not recorded at all", [
        (T, LAST, "")]),

    ("the status line reports the refused rows as layouts too", [
        (T, FIXGATE, "")]),

    # The check itself runs against a RowSpy and a stub Refresh, so these three break the REAL
    # production calls the spies stand in for. Each leaves the reported overlap on screen.
    ("Row:Invalidate stops moving the generation, so Render's gate never misses", [
        (R, "    self.generation = self.generation + 1\n",
            "    self.generation = self.generation\n")]),

    ("the generation drops out of Render's repaint gate", [
        (R, "       and row._sGen   == self.generation\n", "")]),

    ("Tracker:Refresh is never able to ask for a render", [
        (T, "    if not self.frame then return end\n", "    if self.frame then return end\n")]),

    ("the repaint gate is not cleared, so Render keeps the short height", [
        (T, INVALIDATE, FIXES)]),

    ("Invalidate is called with a dot, raising on the nil self in game", [
        (T, INVALIDATE, FIXES + "    Row.Invalidate()\n")]),

    ("the gate is cleared but no layout is asked for", [
        (T, REFRESH, "\n")]),

    # A direct Render adds a pass of its own rather than coalescing, and Visibility takes a
    # quest count off the end of every render with only its first zero guarded.
    ("the check renders directly instead of through Refresh", [
        (T, REFRESH, "\n    self:Render()\n")]),

    ("a layout is not counted", [
        (T, FIXES, "")]),

    ("the status line swaps the layouts and the refusals", [
        (T, "(self._driftFixes or 0, self._driftLast or 0, self._driftGaveUp or 0)",
            "(self._driftGaveUp or 0, self._driftLast or 0, self._driftFixes or 0)")]),

    ("/eqot status stops printing the counters", [
        (C, STATUS, "")]),

    ("/eqot status prints the counters only in debug mode", [
        (C, STATUS, "    if ns.DEBUG then\n    " + STATUS + "    end\n")]),
]

SUMMARY = re.compile(r"^test_row_heights: (\d+) passed, (\d+) failed$")


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
    # survive and being caught is the finding.
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
