"""Prove docs/test_objective_colors.lua actually discriminates, by breaking production on purpose
one change at a time and checking the harness notices.

    python docs/mutate_objective_colors.py        (run from the repo root)

Why this exists: the count colors are cached so a repaint does not build a hex string per line,
and a cache is where a picked color quietly stops arriving: a channel the change test forgets, or
a reset that leaves the old color behind. The defaults have to reproduce the old escapes byte for
byte or every player's tracker shifts on update, and the finished line's color has to win over the
rules it sits in front of without disturbing them while it is unset.

Every mutation reintroduces a defect the harness is supposed to stand guard over. Any that still
reports "0 failed" is an assertion that does not discriminate, and the run exits 1 naming it.

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
HARNESS = "docs/test_objective_colors.lua"

U = "Core/Util.lua"
R = "UI/Row.lua"
D = "Core/DB.lua"

MUTANTS = [
    # ------------------------------------------------------------------ the count colors
    ("a count with none done takes the in-progress color", [
        (U, "    if h == 0    then color = countEsc[1]", "    if h == 0    then color = countEsc[2]")]),

    ("a finished count takes the in-progress color", [
        (U, "    else              color = countEsc[3]", "    else              color = countEsc[2]")]),

    ("the none-done color is never read off the profile", [
        (U, "    setCount(1, cfg and cfg.countColorNone)\n", "")]),

    ("in progress reads the none-done key", [
        (U, "    setCount(2, cfg and cfg.countColorPartial)", "    setCount(2, cfg and cfg.countColorNone)")]),

    ("done reads the in-progress key", [
        (U, "    setCount(3, cfg and cfg.countColorDone)", "    setCount(3, cfg and cfg.countColorPartial)")]),

    ("a change to green alone is missed", [
        (U, "    elseif k.r ~= c.r or k.g ~= c.g or k.b ~= c.b then", "    elseif k.r ~= c.r or k.b ~= c.b then")]),

    ("a change to blue alone is missed", [
        (U, "    elseif k.r ~= c.r or k.g ~= c.g or k.b ~= c.b then", "    elseif k.r ~= c.r or k.g ~= c.g then")]),

    ("a change to red alone is missed", [
        (U, "    elseif k.r ~= c.r or k.g ~= c.g or k.b ~= c.b then", "    elseif k.g ~= c.g or k.b ~= c.b then")]),

    ("going back to unset keeps the last picked color", [
        (U, "        countEsc[i], k.r = COUNT_DEFAULT[i], nil\n", "        k.r = nil\n")]),

    ("going back to unset leaves the cache, so the same pick again is refused", [
        (U, "        countEsc[i], k.r = COUNT_DEFAULT[i], nil\n", "        countEsc[i] = COUNT_DEFAULT[i]\n")]),

    ("the old red drifts", [
        (U, "local COUNT_DEFAULT = { \"|cffff5050\",", "local COUNT_DEFAULT = { \"|cffff5151\",")]),

    ("a stored color loses its rounding and lands a shade off the old red", [
        (D, "            countColorNone     = { r = 1, g = 80 / 255, b = 80 / 255 },",
            "            countColorNone     = { r = 1, g = 0.31, b = 0.31 },")]),

    ("the in-progress default lands a shade off the old orange", [
        (D, "            countColorPartial  = { r = 238 / 255, g = 170 / 255, b = 0 },",
            "            countColorPartial  = { r = 0.93, g = 0.67, b = 0 },")]),

    ("the objective text default is no longer the old gray", [
        (D, "            objectiveColor     = { r = 0.85, g = 0.85, b = 0.85 },",
            "            objectiveColor     = { r = 0.8, g = 0.8, b = 0.8 },")]),

    # ------------------------------------------------------------------ the finished line
    ("a picked finished color is ignored", [
        (R, "    local f = cfg and cfg.finishedObjectiveColor\n    if f and f.r then return Util.Hex(f.r, f.g, f.b) end\n", "")]),

    ("an empty color table counts as picked", [
        (R, "    if f and f.r then return Util.Hex(f.r, f.g, f.b) end", "    if f then return Util.Hex(f.r, f.g, f.b) end")]),

    ("an unset finished line ignores the done color and stays green", [
        (R, "    local d = cfg and cfg.countColorDone\n    if d and d.r then return Util.Hex(d.r, d.g, d.b) end\n", "")]),

    ("the done color beats a title color under the completed box", [
        (R, "    if cfg and cfg.overrideCompleteGreen ~= false then\n"
            "        local r, g, b = Util.EffectiveTitleColor(cfg, true)\n"
            "        if r then return Util.Hex(r, g, b) end\n"
            "    end\n"
            "    local d = cfg and cfg.countColorDone\n    if d and d.r then return Util.Hex(d.r, d.g, d.b) end\n",
            "    local d = cfg and cfg.countColorDone\n    if d and d.r then return Util.Hex(d.r, d.g, d.b) end\n"
            "    if cfg and cfg.overrideCompleteGreen ~= false then\n"
            "        local r, g, b = Util.EffectiveTitleColor(cfg, true)\n"
            "        if r then return Util.Hex(r, g, b) end\n"
            "    end\n")]),

    ("the completed box switched off still hands the title color over", [
        (R, "    if cfg and cfg.overrideCompleteGreen ~= false then\n", "    if cfg then\n")]),

    ("an empty done color counts as picked", [
        (R, "    if d and d.r then return Util.Hex(d.r, d.g, d.b) end", "    if d then return Util.Hex(d.r, d.g, d.b) end")]),

    ("a finished line takes the title color it would draw on an unfinished quest", [
        (R, "        local r, g, b = Util.EffectiveTitleColor(cfg, true)\n        if r then return Util.Hex(r, g, b) end\n    end\n    local d",
            "        local r, g, b = Util.EffectiveTitleColor(cfg)\n        if r then return Util.Hex(r, g, b) end\n    end\n    local d")]),

    ("the finished color gets a default, so it is never unset", [
        (D, "            objectiveColor     = { r = 0.85, g = 0.85, b = 0.85 },\n",
            "            objectiveColor     = { r = 0.85, g = 0.85, b = 0.85 },\n"
            "            finishedObjectiveColor = { r = 0.27, g = 1, b = 0.27 },\n")]),

    # ------------------------------------------------------------------ the wiring
    ("the objective color never reaches a text block", [
        (R, "            block:SetTextColor(oR, oG, oB)\n", "")]),

    ("without a color the objective text goes white", [
        (R, "    local oR, oG, oB = 0.85, 0.85, 0.85\n", "    local oR, oG, oB = 1, 1, 1\n")]),

    ("a progress bar's label ignores the picked count colors", [
        (R, "Util.ColorizeProgress(label, cfg)", "Util.ColorizeProgress(label)")]),

    ("an objective line ignores the picked count colors", [
        (R, "Util.ColorizeProgress(text, cfg)", "Util.ColorizeProgress(text)")]),

    ("Reset to Defaults forgets the finished color", [
        (D, "\"countColorDone\", \"finishedObjectiveColor\",", "\"countColorDone\",")]),

    ("a picked finished color has its green and blue swapped", [
        (R, "    if f and f.r then return Util.Hex(f.r, f.g, f.b) end",
            "    if f and f.r then return Util.Hex(f.r, f.b, f.g) end")]),
]

SUMMARY = re.compile(r"^test_objective_colors: (\d+) passed, (\d+) failed$")


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
        # Asserted rather than assumed: applying a mutant to a file that still holds the last one
        # is a silent no-op, and the run would report the previous mutant's result under this name.
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
    if verdict == "crashed":
        print("CRASHED   %-74s %s" % (name, last))
        failures.append(("CRASHED", name))
    elif verdict == "green":
        print("SURVIVED  %-74s %s" % (name, last))
        failures.append(("SURVIVED", name))
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
    # Three different verdicts, never pooled. A SKIPPED anchor reported as a survivor sends the
    # reader hunting a coverage hole that is not there, and a CRASHED one hides an abort.
    for kind, label in (
            ("SURVIVED", "mutant(s) survived - those assertions do not discriminate"),
            ("CRASHED",  "mutant(s) aborted the harness rather than failing it"),
            ("SKIPPED",  "anchor(s) rotted - fix the anchor, never drop the mutant")):
        named = [name for verdict, name in failures if verdict == kind]
        if named:
            print("%d %s:" % (len(named), label))
            for name in named:
                print("  - " + name)
    sys.exit(1)
print("every mutant behaved as expected")
