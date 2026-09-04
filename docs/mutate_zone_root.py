"""Prove docs/test_zone_root.lua actually discriminates, by breaking production on purpose one
change at a time and checking the harness notices.

    python docs/mutate_zone_root.py        (run from the repo root)

Why this exists: the defect this walk was fixed for was invisible. Standing in Slayer's Rise the
tracker drew no zone bar at all, every gate in the project was green, nothing raised, and the
status line said "NO ROUTING" - which reads as missing DATA rather than as a walk that stopped
one hop early. Midnight nests zones, so the first Zone above the player is not necessarily the
zone anyone means.

The mutants below put back the shape of that, plus the shape of the regression it would have
been easy to ship instead: a climb that asks only for a mapID entry passes over Eversong Woods,
which carries none, and answers a sub-area of it that no category names.

Every mutation reintroduces a defect the harness is supposed to stand guard over. Any that still
reports "0 failed" is an assertion that does not discriminate, and the run exits 1 naming it.

WRITES TO THE TREE. It edits in place and restores through a finally, so an interrupted run
still puts the file back, and it verifies the restore and re-checks the baseline before
reporting. If you hard-kill it anyway, recover from your editor's undo history, NOT with git -
this file may be uncommitted while it is being worked on.

Anchors are exact source text and they rot. A SKIPPED line means an anchor stopped matching:
fix the anchor rather than dropping the mutant.
"""
import io
import re
import subprocess
import sys

LUA = r"C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe"
HARNESS = "docs/test_zone_root.lua"

SRC = "Data/ZoneProgress.lua"

MUTANTS = [
    # --------------------------------------------------- the defect the fix exists for
    ("the walk stops at the first Zone again, whether or not it names a category", [
        (SRC,
         "        if ZONE and info.mapType == ZONE then\n"
         "            if not firstID then firstID, firstName = id, info.name end\n"
         "            if categoryByMapID(id) or categoryByName(info.name) then\n"
         "                _rootID, _rootName = id, info.name\n"
         "                if firstID and firstID ~= id then _rootVia = firstID end\n"
         "                break\n"
         "            end\n"
         "        end",
         "        if ZONE and info.mapType == ZONE then\n"
         "            _rootID, _rootName = id, info.name\n"
         "            break\n"
         "        end")]),

    # --------------------------------------------------- the Eversong trap, both halves
    ("the per-hop test drops categoryByName, so a name-only zone is walked past", [
        (SRC, "            if categoryByMapID(id) or categoryByName(info.name) then",
              "            if categoryByMapID(id) then")]),

    ("the per-hop test drops categoryByMapID, so Voidstorm is reached by name alone", [
        (SRC, "            if categoryByMapID(id) or categoryByName(info.name) then",
              "            if categoryByName(info.name) then")]),

    ("the per-hop name test is asked about the wrong map's name", [
        (SRC, "            if categoryByMapID(id) or categoryByName(info.name) then",
              "            if categoryByMapID(id) or categoryByName(_rootName) then")]),

    # --------------------------------------------------- the id and the name must move together
    ("the id climbs but the NAME stays on the map underfoot, so the bar mislabels its count", [
        (SRC, "                _rootID, _rootName = id, info.name\n"
              "                if firstID and firstID ~= id then _rootVia = firstID end\n"
              "                break",
              "                _rootID = id\n"
              "                if firstID and firstID ~= id then _rootVia = firstID end\n"
              "                break")]),

    # --------------------------------------------------- the continent bound
    ("the above-zone guard goes, so a continent can answer for a zone", [
        (SRC,
         "        local pinfo = C_Map.GetMapInfo(info.parentMapID)\n",
         "        local pinfo = nil\n")]),

    ("the above-zone guard is inverted", [
        (SRC, "        if ZONE and pinfo and pinfo.mapType and pinfo.mapType < ZONE then break end",
              "        if ZONE and pinfo and pinfo.mapType and pinfo.mapType > ZONE then break end")]),

    # --------------------------------------------------- the fallback that preserves today
    ("the first-Zone fallback goes, so a zone with no routing answers its own micro map", [
        (SRC, "    if not _rootID then _rootID, _rootName = firstID, firstName end\n", "")]),

    ("firstID latches the LAST zone seen rather than the first", [
        (SRC, "            if not firstID then firstID, firstName = id, info.name end",
              "            firstID, firstName = id, info.name")]),

    ("the player-map fallback goes, so a chain with no Zone at all latches nil", [
        (SRC,
         "    if not _rootID then\n"
         "        local info = C_Map.GetMapInfo(mapID)\n"
         "        _rootID, _rootName = mapID, info and info.name or nil\n"
         "    end\n",
         "")]),

    # --------------------------------------------------- the status line's via suffix
    ("the via record is never cleared, so the status line announces a climb that did not happen", [
        (SRC, "    _rootID, _rootName, _rootVia = nil, nil, nil",
              "    _rootID, _rootName = nil, nil")]),

    ("via is recorded even when the walk stayed put", [
        (SRC, "                if firstID and firstID ~= id then _rootVia = firstID end",
              "                _rootVia = firstID")]),

    # --------------------------------------------------- innermost resolving zone wins
    ("the break goes, so the OUTERMOST resolving zone wins instead of the innermost", [
        (SRC, "                if firstID and firstID ~= id then _rootVia = firstID end\n"
              "                break\n",
              "                if firstID and firstID ~= id then _rootVia = firstID end\n")]),

    # --------------------------------------------------- the walk's own bounds
    ("the parentMapID 0 guard goes, and 0 is truthy in Lua", [
        (SRC, "        if not info.parentMapID or info.parentMapID == 0 then break end",
              "        if not info.parentMapID then break end")]),

    ("the unreadable-map guard goes, so a nil GetMapInfo raises mid-walk", [
        (SRC, "        if not info then break end\n", "")]),

    ("MAX_HOPS is spent on one hop, so nothing nested can ever resolve", [
        (SRC, "local MAX_HOPS = 5", "local MAX_HOPS = 1")]),

    ("MAX_HOPS is one short, so a zone exactly at the bound falls out of reach", [
        (SRC, "local MAX_HOPS = 5", "local MAX_HOPS = 4")]),

    ("MAX_HOPS is widened, so the walk reaches past the bound it documents", [
        (SRC, "local MAX_HOPS = 5", "local MAX_HOPS = 100")]),

    ("the Enum.UIMapType probe is dropped, so a client without it raises mid-walk", [
        (SRC, "    local ZONE = Enum and Enum.UIMapType and Enum.UIMapType.Zone",
              "    local ZONE = Enum.UIMapType.Zone")]),

    ("the ZONE guard on the mapType test goes, so a map with no mapType reads as a Zone", [
        (SRC, "        if ZONE and info.mapType == ZONE then",
              "        if info.mapType == ZONE then")]),

    ("the mapType existence check in the above-zone guard goes, so a typeless parent raises", [
        (SRC, "        if ZONE and pinfo and pinfo.mapType and pinfo.mapType < ZONE then break end",
              "        if ZONE and pinfo and pinfo.mapType < ZONE then break end")]),

    # --------------------------------------------------- the memo, and the refusals
    ("the memo is dropped, so every render re-walks the map chain", [
        (SRC, "    if not _rootDirty then return _rootID, _rootName end\n", "")]),

    ("the memo ships CLEAN, so the first call answers nil and nothing ever walks", [
        (SRC, "local _rootID, _rootName, _rootDirty = nil, nil, true",
              "local _rootID, _rootName, _rootDirty = nil, nil, false")]),

    ("the cached branch hands back only the id, so the bar loses its header", [
        (SRC, "    if not _rootDirty then return _rootID, _rootName end",
              "    if not _rootDirty then return _rootID end")]),

    ("the cached branch hands back nil, so the bar draws once and never again", [
        (SRC, "    if not _rootDirty then return _rootID, _rootName end",
              "    if not _rootDirty then return nil end")]),

    ("the no-map refusal goes, so a nil map id walks anyway", [
        (SRC, "    if not mapID or mapID <= 0 then return nil end\n", "")]),

    ("the Has.Map capability probe goes", [
        (SRC, "    if not ns.Has.Map then return nil end\n", "")]),
]

SUMMARY = re.compile(r"^test_zone_root: (\d+) passed, (\d+) failed$")


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
        # Asserted rather than assumed. Applying a mutant to a file that still holds the last one
        # is a silent no-op, and the run then reports the PREVIOUS mutant's result under this
        # mutant's name - a false pass in the tool meant to find them.
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
