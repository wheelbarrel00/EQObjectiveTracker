"""Prove docs/test_zone_filter.lua actually discriminates, by breaking the retail quest provider's
IsCurrentZone on purpose one change at a time and checking the harness notices.

    python docs/mutate_zone_filter.py               (run from the repo root)

IsCurrentZone is what Show only quests in current zone hides by and what Current zone first lifts a
zone header by. On WoW Forever a quest log heading naming the zone counts as well as a marker on the
map (2026-10-17: in Stormwind the marker rule alone hid every quest). Each mutation below reintroduces
a defect the harness stands guard over: the heading rule gone, leaking onto retail, matching too
loosely, the marker rule's answer bent, or /eqot zoneprobe's verdict leaving the heading
out. Any that still reports "0 failed" is an assertion that does
not discriminate, and the run exits 1 naming it.

A CRASHED verdict is reported apart from "caught" on purpose. A mutant that does not parse also exits
nonzero, and counting that as caught is a false pass in the one tool whose job is to find false passes.

WRITES TO THE TREE. It edits Data/Providers/Quests.lua in place and restores it after every mutant
through a finally, then verifies the restore and re-checks the baseline before reporting. Run it from a
scratch copy while the game is open, since this checkout is the live addon.
"""
import io
import re
import subprocess
import sys

LUA = r"C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe"
SRC = "Data/Providers/Quests.lua"
HARNESS = "docs/test_zone_filter.lua"
SUMMARY = re.compile(r"^test_zone_filter: (\d+) passed, (\d+) failed$")

GATE = "    if ns.IsForever() and GetZoneText then\n"
MATCH = "        if zone and zone ~= \"\" and entry.zone == zone then return true end\n"

MUTANTS = [
    ("the zone probe's verdict leaves out the heading, so on Forever it disagrees with the filter",
     "                local verdict = self:IsCurrentZone({ id = id, zone = header })",
     "                local verdict = self:IsCurrentZone({ id = id })"),
    ("the heading rule is gone, so Forever hides every quest under its own zone's heading",
     GATE + "        local zone = GetZoneText()\n" + MATCH + "    end\n", ""),
    ("the heading rule reaches retail too",
     GATE, "    if GetZoneText then\n"),
    ("a client without GetZoneText raises",
     GATE, "    if ns.IsForever() then\n"),
    ("an empty zone text matches an empty heading",
     MATCH, "        if zone and entry.zone == zone then return true end\n"),
    ("no zone text matches a quest with no heading",
     MATCH, "        if zone ~= \"\" and entry.zone == zone then return true end\n"),
    ("any heading at all counts as the zone",
     MATCH, "        if zone and zone ~= \"\" and entry.zone ~= nil then return true end\n"),
    ("a heading match answers cannot-tell",
     MATCH, "        if zone and zone ~= \"\" and entry.zone == zone then return nil end\n"),
    ("a heading that only starts with the zone name matches",
     MATCH, "        if zone and zone ~= \"\" and entry.zone and entry.zone:find(zone, 1, true) == 1 then return true end\n"),
    ("a quest off the map answers cannot-tell rather than elsewhere",
     "    return set[entry.id] == true\n", "    return set[entry.id]\n"),
    ("the marker rule is skipped once the client is Forever",
     "    local set = currentZoneSet()\n    if not set then return nil end\n",
     "    if ns.IsForever() then return false end\n    local set = currentZoneSet()\n    if not set then return nil end\n"),
]


def run():
    """(verdict, note). verdict is "green", "failed" or "crashed"."""
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

survivors = []
for name, old, new in MUTANTS:
    old, new = fit(old), fit(new)
    if original.count(old) != 1:
        print("SKIPPED (anchor matched %d times): %s" % (original.count(old), name))
        survivors.append(name)
        continue
    try:
        io.open(SRC, "w", encoding="utf-8", newline="").write(original.replace(old, new, 1))
        verdict, last = run()
    finally:
        io.open(SRC, "w", encoding="utf-8", newline="").write(original)
    if verdict == "crashed":
        print("CRASHED   %-78s %s" % (name, last))
        survivors.append(name)
    elif verdict == "green":
        print("SURVIVED  %-78s %s" % (name, last))
        survivors.append(name)
    else:
        print("caught    %-78s %s" % (name, last))

if io.open(SRC, encoding="utf-8", newline="").read() != original:
    print("\nTHE TREE WAS NOT RESTORED - %s still holds a mutant" % SRC)
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
