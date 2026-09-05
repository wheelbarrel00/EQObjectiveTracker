"""Prove docs/test_wq_zone.lua actually discriminates, by breaking production on purpose one
change at a time and checking the harness notices.

    python docs/mutate_wq_zone.py        (run from the repo root)

Why this exists: this walk has failed in BOTH directions, each time silently, and each time a
user found it rather than a gate.

  - Too loose: an unbounded climb reached a CONTINENT within two hops, and a continent's task
    list is every in-progress task quest on it. Reported by Souseiseki87 on 2026-08-21 as
    Zul'Aman world quests filling the section while standing on The Coiled Isle.
  - Tight in the other direction: it will not climb through a nested Zone, so a world quest
    registered on the zone enclosing the city you stand in is never asked for. That is a KNOWN
    and deliberate limitation. The climb was tried on 2026-09-05 and reverted: it fixed nothing
    measurable and re-created a smaller version of the report above.

So a mutant that widens the walk and one that narrows it are equally important here, and the
battery carries both.

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
HARNESS = "docs/test_wq_zone.lua"

WQ = "Data/Providers/WorldQuests.lua"

MUTANTS = [
    # ---------------------------------- too loose: the climb this project tried and reverted
    ("the Zone-underfoot stop is removed, so the walk climbs into the enclosing zone", [
        (WQ, "    if not info or info.mapType == ZONE then return nil end",
             "    if not info then return nil end")]),

    ("the parent must be strictly above zone level, so no zone is ever reached", [
        (WQ, "    if ZONE and pinfo and pinfo.mapType and pinfo.mapType < ZONE then return nil end",
             "    if ZONE and pinfo and pinfo.mapType and pinfo.mapType <= ZONE then return nil end")]),

    # ------------------------------------------------ too loose: Souseiseki87's own report
    ("the parent-type guard is dropped, so the climb can take a continent", [
        (WQ, "    if ZONE and pinfo and pinfo.mapType and pinfo.mapType < ZONE then return nil end\n",
             "")]),

    ("the parent-type guard reads the CHILD's type, so it never refuses anything", [
        (WQ, "    if ZONE and pinfo and pinfo.mapType and pinfo.mapType < ZONE then return nil end",
             "    if ZONE and info and info.mapType and info.mapType < ZONE then return nil end")]),

    # ------------------------------------------------------------------- the smaller guards
    ("parentMapID 0 is treated as a real map, because 0 is truthy in Lua", [
        (WQ, "    if not parent or parent <= 0 then return nil end",
             "    if not parent then return nil end")]),

    ("the map itself is returned rather than its parent, so the walk never moves", [
        (WQ, "    local pinfo = C_Map.GetMapInfo(parent)\n"
             "    if ZONE and pinfo and pinfo.mapType and pinfo.mapType < ZONE then return nil end\n"
             "    return parent",
             "    local pinfo = C_Map.GetMapInfo(parent)\n"
             "    if ZONE and pinfo and pinfo.mapType and pinfo.mapType < ZONE then return nil end\n"
             "    return mapID")]),

    ("an unreadable parent ends the climb, dropping a legitimate hop", [
        (WQ, "    if ZONE and pinfo and pinfo.mapType and pinfo.mapType < ZONE then return nil end",
             "    if not (pinfo and pinfo.mapType) then return nil end\n"
             "    if ZONE and pinfo.mapType < ZONE then return nil end")]),

    ("the map id guard is dropped, so map zero and nil reach the client", [
        (WQ, "    if not (C_Map.GetMapInfo and mapID and mapID > 0) then return nil end",
             "    if not C_Map.GetMapInfo then return nil end")]),

    ("MAP_DEPTH is cut to one, so a chain needing a hop cannot make it", [
        (WQ, "local MAP_DEPTH      = 5", "local MAP_DEPTH      = 1")]),

    # Both guards at once. Each alone is covered above; this is the shape that actually reaches
    # a continent, and it is what Souseiseki87 reported.
    ("BOTH guards are dropped, so the climb runs all the way to a continent", [
        (WQ, "    if not info or info.mapType == ZONE then return nil end",
             "    if not info then return nil end"),
        (WQ, "    if ZONE and pinfo and pinfo.mapType and pinfo.mapType < ZONE then return nil end\n",
             "")]),

    # Disables both guards through the front door rather than by deleting either: with ZONE nil
    # the mapType test is never equal and the parent guard's own `ZONE and` short-circuits.
    ("the Zone enum does not resolve, so neither guard can fire", [
        (WQ, "    local ZONE = Enum and Enum.UIMapType and Enum.UIMapType.Zone",
             "    local ZONE = nil")]),
]

SUMMARY = re.compile(r"^test_wq_zone: (\d+) passed, (\d+) failed$")


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
