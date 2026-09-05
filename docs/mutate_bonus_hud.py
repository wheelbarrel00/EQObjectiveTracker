"""Prove docs/test_bonus_hud.lua actually discriminates, by breaking production on purpose one
change at a time and checking the harness notices.

    python docs/mutate_bonus_hud.py        (run from the repo root)

Why this exists: the HUD's frame is drawn from a three-branch cascade whose ORDER is the whole
behavior, and every way of getting it wrong is silent. A picked color that loses its alpha to
the lock fade reads as the color not sticking; an alphaless color drawn at alpha nil is
invisible, which is indistinguishable from the feature being broken; and a switch tested with
`not` rather than `== false` blanks the frame of any state table that carries neither key,
which is what ApplySettings's own `hudState() or {}` fallback produces.

Almost nothing here raises: two of the mutants below drop a guard and do, and every other one
changes a color or a position with no error at all. That is the point - the HUD is off by
default and, outside its Test button, only draws inside a scenario or a delve, so a defect in
it is seen by the few players who turn it on, in the one place they cannot easily go back to.

Every mutation reintroduces a defect the harness is supposed to stand guard over. Any that
still reports "0 failed" is an assertion that does not discriminate, and the run exits 1
naming it.

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
HARNESS = "docs/test_bonus_hud.lua"

HUD = "UI/ScenarioBonusHUD.lua"

MUTANTS = [
    # ------------------------------------------ the background cascade, which this release adds
    ("the picked background color is ignored, so the lock fade owns the alpha again", [
        (HUD, """    elseif st.backgroundColor then
        local c = st.backgroundColor
        -- A picked color carries its own alpha, so the lock fade below stops applying.
        f:SetBackdropColor(c.r or 0, c.g or 0, c.b or 0, c.a or 1)
""", "")]),

    ("a picked color is asked about BEFORE the off switch, so unticking stops removing it", [
        (HUD, """    if st.showBackground == false then
        f:SetBackdropColor(0, 0, 0, 0)
    elseif st.backgroundColor then""",
              """    if st.backgroundColor then
        local c0 = st.backgroundColor
        f:SetBackdropColor(c0.r or 0, c0.g or 0, c0.b or 0, c0.a or 1)
    elseif st.showBackground == false then
        f:SetBackdropColor(0, 0, 0, 0)
    elseif false then""")]),

    ("a background color with no alpha is drawn at nil rather than opaque", [
        (HUD, "f:SetBackdropColor(c.r or 0, c.g or 0, c.b or 0, c.a or 1)",
              "f:SetBackdropColor(c.r or 0, c.g or 0, c.b or 0, c.a)")]),

    ("the picked color's own channels are dropped for black", [
        (HUD, "f:SetBackdropColor(c.r or 0, c.g or 0, c.b or 0, c.a or 1)",
              "f:SetBackdropColor(0, 0, 0, c.a or 1)")]),

    ("the background switch is a truth test, so an unset one blanks an existing frame", [
        (HUD, "    if st.showBackground == false then",
              "    if not st.showBackground then")]),

    ("the background off branch draws the fill anyway", [
        (HUD, """    if st.showBackground == false then
        f:SetBackdropColor(0, 0, 0, 0)
    elseif""",
              """    if st.showBackground == false then
        f:SetBackdropColor(0, 0, 0, 0.55)
    elseif""")]),

    # ---------------------------------------------------------------------- the lock fade
    ("the lock fade is inverted, so locking makes the HUD more solid", [
        (HUD, "f:SetBackdropColor(0, 0, 0, st.locked and 0.40 or 0.55)",
              "f:SetBackdropColor(0, 0, 0, st.locked and 0.55 or 0.40)")]),

    ("the lock fade is dropped, so an unlocked HUD no longer reads as draggable", [
        (HUD, "f:SetBackdropColor(0, 0, 0, st.locked and 0.40 or 0.55)",
              "f:SetBackdropColor(0, 0, 0, 0.55)")]),

    # -------------------------------------------- the border cascade, which this release adds
    ("the picked border color is ignored and the shipped red is always drawn", [
        (HUD, """        local bc = st.borderColor
        if bc then f:SetBackdropBorderColor(bc.r, bc.g, bc.b, bc.a or 1)
        else       f:SetBackdropBorderColor(BORDER_RED[1], BORDER_RED[2], BORDER_RED[3], BORDER_RED[4]) end""",
              """        f:SetBackdropBorderColor(BORDER_RED[1], BORDER_RED[2], BORDER_RED[3], BORDER_RED[4])""")]),

    ("the red fallback is dropped, so a table with no borderColor loses its border", [
        (HUD, """        local bc = st.borderColor
        if bc then f:SetBackdropBorderColor(bc.r, bc.g, bc.b, bc.a or 1)
        else       f:SetBackdropBorderColor(BORDER_RED[1], BORDER_RED[2], BORDER_RED[3], BORDER_RED[4]) end""",
              """        local bc = st.borderColor or { r = 0, g = 0, b = 0, a = 0 }
        f:SetBackdropBorderColor(bc.r, bc.g, bc.b, bc.a or 1)""")]),

    ("a border color with no alpha is drawn at nil rather than opaque", [
        (HUD, "if bc then f:SetBackdropBorderColor(bc.r, bc.g, bc.b, bc.a or 1)",
              "if bc then f:SetBackdropBorderColor(bc.r, bc.g, bc.b, bc.a)")]),

    ("the border switch is a truth test, so an unset one blanks an existing border", [
        (HUD, "    if st.showBorder == false then",
              "    if not st.showBorder then")]),

    ("the border off branch draws the border anyway", [
        (HUD, """    if st.showBorder == false then
        f:SetBackdropBorderColor(0, 0, 0, 0)""",
              """    if st.showBorder == false then
        f:SetBackdropBorderColor(0, 0, 0, 1)""")]),

    # ------------------------------------------------------ the position, which predates this
    ("the offsets are not divided back out, so the HUD walks as the scale slider moves", [
        (HUD, "               (st.x or 0) / scale, (st.y or DEFAULT_Y) / scale)",
              "               (st.x or 0), (st.y or DEFAULT_Y))")]),

    ("the scale guard is dropped, so a stored zero divides the offsets by nothing", [
        (HUD, "    if scale <= 0 then scale = 1.0 end\n", "")]),

    ("the scale is never applied to the frame", [
        (HUD, "    f:SetScale(scale)\n", "")]),

    ("the old anchor is not cleared, so every apply adds another SetPoint", [
        (HUD, "    f:ClearAllPoints()\n", "")]),

    ("the stored anchor is ignored and the CENTER fallback is always used", [
        (HUD, '    f:SetPoint(st.point or "CENTER", UIParent, st.relPoint or st.point or "CENTER",',
              '    f:SetPoint("CENTER", UIParent, "CENTER",')]),

    ("a stored point no longer stands in for a missing relative point", [
        (HUD, '    f:SetPoint(st.point or "CENTER", UIParent, st.relPoint or st.point or "CENTER",',
              '    f:SetPoint(st.point or "CENTER", UIParent, st.relPoint or "CENTER",')]),

    ("the save drops the anchor, so a dragged HUD returns to center next login", [
        (HUD, '    st.point, st.relPoint = point, relPoint\n', '')]),

    ("the save's own scale guard is dropped, so a rescaled frame stores 0,0", [
        (HUD, '    if not scale or scale <= 0 then scale = 1.0 end\n', '')]),

    ("the HUD's own default offset becomes zero, centering it on the player", [
        (HUD, "(st.y or DEFAULT_Y) / scale)", "(st.y or 0) / scale)")]),

    ("the save does not multiply the scale back in, so a drag stores frame units", [
        (HUD, "    st.x, st.y = (x or 0) * scale, (y or 0) * scale",
              "    st.x, st.y = (x or 0), (y or 0)")]),

    # ---------------- the no-frame guard an options setter reaches, and the unanchored guard
    # ---------------- a drag stop does
    ("the no-frame guard is dropped, so an options setter raises before the first draw", [
        (HUD, """    local f = self.frame
    if not f then return end
    local st = hudState() or {}""",
              """    local f = self.frame
    local st = hudState() or {}""")]),

    ("the unanchored guard is dropped, so saving a frame with no point raises", [
        (HUD, """    local point, _, relPoint, x, y = f:GetPoint()
    if not point then return end""",
              """    local point, _, relPoint, x, y = f:GetPoint()""")]),
]

SUMMARY = re.compile(r"^test_bonus_hud: (\d+) passed, (\d+) failed$")


def run():
    """(verdict, note). verdict is "green", "failed" or "crashed".

    A nonzero exit is NOT evidence that an assertion discriminated - a mutant that does not
    parse exits nonzero too, and reporting that as "caught" is a false pass in the one tool
    whose job is to catch false passes. So the harness's own summary line is matched rather
    than its exit code, and a run that never got that far is its own verdict.
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
