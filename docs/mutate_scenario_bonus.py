"""Prove docs/test_scenario_bonus.lua actually discriminates, by breaking production on
purpose one change at a time and checking the harness notices.

    python docs/mutate_scenario_bonus.py        (run from the repo root)

Why this exists: an earlier version of that harness read 40 passed with four blockers sitting
in the tree, and five of its assertions could not tell a working build from a broken one - the
pack ratchet had no test at all, and the dedupe test passed with the key swapped to the wrong
field. A green suite is not coverage. This is what says otherwise.

Every mutation below reintroduces a defect the harness is supposed to stand guard over. Any
that still reports "0 failed" is an assertion that does not discriminate, and the run exits 1
naming it - unless the entry is marked EQUIVALENT, which means the mutation provably cannot
change behavior and so nothing could catch it. Deaths are the one of those: runDeaths only
ever counts up, so ratcheting it with math.max is a no-op rather than a bug.

WRITES TO THE TREE. It edits Data/ScenarioBonus.lua and UI/ScenarioBonusHUD.lua in place and
restores them after every mutant, through a finally, so an interrupted run still puts them
back. Check git status if you kill it mid-run anyway.

Anchors are exact source text and they rot. A SKIPPED line means an anchor stopped matching:
fix the anchor rather than dropping the mutant, the same rule test_row_blocks.lua carries.
"""
import io
import re
import subprocess
import sys

LUA = r"C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe"
DATA = "Data/ScenarioBonus.lua"

MUTANTS = [
    ("dedupe on the regenerating vignette guid", DATA, [
        ("                local key = v.objectGUID",
         "                local key = vguid")]),

    ("flush guard removed, a loading screen reads as every pack dead", DATA, [
        ("    if listed > 0 then nemesisRemaining = packCount end",
         "    nemesisRemaining = packCount")]),

    ("the math.max ratchet put back on the saved pack count", DATA, [
        ("    r.packsKilled = packsKilledNow()",
         "    r.packsKilled = math.max(r.packsKilled or 0, packsKilledNow())")]),

    ("EQUIVALENT: the math.max ratchet put back on deaths", DATA, [
        ("    r.deaths      = runDeaths",
         "    r.deaths      = math.max(r.deaths or 0, runDeaths)")]),

    # The exit arm neutered rather than deleted: an earlier version opened an "if false then"
    # against an end it never wrote, so the mutant did not PARSE and the driver reported it as
    # caught for as long as this battery had only an exit code to go on.
    ("checkRun's exit arm does nothing, so leaving a delve keeps the run", DATA, [
        ("""    if not playerInDelve() then
        trackedDelve = nil
        resetRun()""",
         """    if not playerInDelve() then
        trackedDelve = trackedDelve""")]),

    ("the saved-run clear put back behind the trackedDelve guard", DATA, [
        ("""        trackedDelve = nil
        resetRun()""",
         """        local wasTracking = trackedDelve
        trackedDelve = nil
        resetRun()
        if not wasTracking then return end""")]),

    ("the enabled gate removed from persistRun", DATA, [
        ("    if not Bonus:Enabled() then return end\n    local char = charScope()",
         "    local char = charScope()")]),

    ("the pack vignette list collapsed back to one season", DATA, [
        ("    7531,  -- Season 1,", "    -- 7531,  -- Season 1,")]),

    ("the vignette walk back on ipairs, which stops dead at a nil hole", DATA, [
        ("""    for i = 1, #vigs do
        local vguid = vigs[i]
        local ok2, v""",
         """    for _, vguid in ipairs(vigs) do
        local ok2, v""")]),

    ("the name guard narrowed back to lower() with the matching outside it", DATA, [
        ("""            local okName, hit = pcall(bannerNameHit, v.name)
            if okName and hit then""",
         """            local _ok, _ln = pcall(string.lower, v.name)
            local hit = _ok and type(_ln) == "string" and _ln ~= "" and (
                (_ln:find(RAGER_NAME_MATCH, 1, true) and "eliteUp")
                or (_ln:find("sanctified banner", 1, true) and "announced")) or nil
            local okName = true
            if okName and hit then""")]),

    ("vignetteMisses no longer reset with the run", DATA, [
        ("    vignetteMisses  = 0\n    wipe(nemesisSeen)", "    wipe(nemesisSeen)")]),

    ("the dump line guard removed, one bad value kills the command", DATA, [
        ("""                local okLine, line = pcall(vignetteDumpLine, i, g, ok2 and v or nil)
                out[#out + 1] = okLine and line
                    or ("  vig [%d] holds values that will not print"):format(i)""",
         """                out[#out + 1] = vignetteDumpLine(i, g, ok2 and v or nil)""")]),

    ("the lives read called unguarded from the model", DATA, [
        ("    local okLives, lives = pcall(readLives)",
         "    local okLives, lives = true, readLives()")]),

    ("the rager despawn test back on a flushed list", DATA, [
        ('    if listed > 0 and ragerGUID and not ragerSeen and bannerState == "eliteUp" then',
         '    if ragerGUID and not ragerSeen and bannerState == "eliteUp" then')]),

    ("the tier floor removed, so the total no longer reflects the tier", DATA, [
        ("        local total  = math.max(expected, packsKilledBase + nemesisSeenCount)",
         "        local total  = packsKilledBase + nemesisSeenCount")]),

    # Lives moved off a frame scrape and onto the delve header widget on 2026-09-05, measured
    # in a tier 7 delve: currencies[1].text read "5" and then "4" after one death. These six
    # stand where the old walk's four did.
    ("the lives read takes the currency tooltip instead of its number", DATA, [
        ("    return c and tonumber(plain(c.text)) or nil",
         "    return c and tonumber(plain(c.tooltip)) or nil")]),

    ("the lives read takes the tier, which is on the same widget", DATA, [
        ("    local c  = hv and type(hv.currencies) == \"table\" and hv.currencies[1]\n"
         "    return c and tonumber(plain(c.text)) or nil",
         "    return hv and tonumber(plain(hv.tierText)) or nil")]),

    ("tonumber dropped, so an empty widget string draws a blank Lives half", DATA, [
        ("    return c and tonumber(plain(c.text)) or nil",
         "    return c and plain(c.text) or nil")]),

    ("the currencies table guard dropped, so a widget without them raises", DATA, [
        ("    local c  = hv and type(hv.currencies) == \"table\" and hv.currencies[1]",
         "    local c  = hv and hv.currencies[1]")]),

    ("the lives read takes the second currency rather than the first", DATA, [
        ("    local c  = hv and type(hv.currencies) == \"table\" and hv.currencies[1]",
         "    local c  = hv and type(hv.currencies) == \"table\" and hv.currencies[2]")]),

    # ------------------------------------------------ the walk, which had one mutant until now
    ("the shared walk is unguarded, so a throwing client kills the whole delve model", DATA, [
        ("local function delveHeader()\n"
         "    local ok, hv = pcall(findDelveHeader)\n"
         "    return ok and hv or nil",
         "local function delveHeader()\n"
         "    local hv = findDelveHeader()\n"
         "    return hv")]),

    ("the widget list is asked for by a literal set id rather than the step's own", DATA, [
        ("    local widgets = C_UIWidgetManager.GetAllWidgetsBySetID(stepInfo.widgetSetID)",
         "    local widgets = C_UIWidgetManager.GetAllWidgetsBySetID(0)")]),

    # Equivalent only because delveHeader's own pcall now catches everything under it: ipairs
    # on a nil or a number raises, and that pcall answers nil, which is what the guard returns.
    # It stops being equivalent the day that pcall moves or narrows.
    ("EQUIVALENT: the widget list shape guard is dropped, so a non-table is walked", DATA, [
        ('    if type(widgets) ~= "table" then return nil end', "")]),

    ("the getter is handed the widget TYPE instead of the widget id", DATA, [
        ("            local hv = getter(w.widgetID)", "            local hv = getter(w.widgetType)")]),

    ("the delves type filter is dropped, so the first widget of any type is read", DATA, [
        ("        if w.widgetType == VT.ScenarioHeaderDelves then", "        if true then")]),

    ("the widgetSetID requirement is dropped, so nil reaches the widget API", DATA, [
        ("    if not (stepInfo and stepInfo.widgetSetID) then return nil end",
         "    if not stepInfo then return nil end")]),

    ("the tier drops its secret filter, so a secret tier is taken as a real number", DATA, [
        ("    return hv and tonumber(plain(hv.tierText)) or nil",
         "    return hv and tonumber(hv.tierText) or nil")]),

    ("the lives read drops its secret filter", DATA, [
        ("    return c and tonumber(plain(c.text)) or nil",
         "    return c and tonumber(c.text) or nil")]),

]


SUMMARY = re.compile(r"^test_scenario_bonus: (\d+) passed, (\d+) failed$")


def run():
    """(verdict, note). verdict is "green", "failed" or "crashed".

    A nonzero exit is NOT evidence that an assertion discriminated - a mutant that does not
    parse, or one that makes the harness raise, exits nonzero too, and reporting either as
    "caught" is a false pass in the one tool whose job is to catch false passes. So the
    harness's own summary line is matched rather than its exit code.
    """
    r = subprocess.run([LUA, "docs/test_scenario_bonus.lua"], capture_output=True, text=True)
    for line in reversed([l for l in r.stdout.splitlines() if l.strip()]):
        m = SUMMARY.match(line.strip())
        if m:
            return ("failed" if int(m.group(2)) else "green"), line.strip()
    err = (r.stderr.strip().splitlines() or r.stdout.strip().splitlines() or ["no output"])
    return "crashed", err[0][:90]


originals = {p: io.open(p, encoding="utf-8", newline="").read() for p in (DATA,)}

verdict, last = run()
print("baseline: %s\n" % last)
if verdict != "green":
    print("BASELINE IS NOT GREEN - stopping")
    sys.exit(1)

failures = []
for name, path, hunks in MUTANTS:
    src = originals[path]
    mutated, bad = src, False
    for old, new in hunks:
        if mutated.count(old) != 1:
            print("SKIPPED (anchor matched %d times): %s" % (mutated.count(old), name))
            bad = True
            break
        mutated = mutated.replace(old, new, 1)
    if bad:
        failures.append(("SKIPPED", name))
        continue
    try:
        io.open(path, "w", encoding="utf-8", newline="").write(mutated)
        verdict, last = run()
    finally:
        io.open(path, "w", encoding="utf-8", newline="").write(src)
    expected_equivalent = name.startswith("EQUIVALENT:")
    if verdict == "crashed":
        print("CRASHED   %-72s %s" % (name, last))
        failures.append(("CRASHED", name))
    elif verdict == "green" and not expected_equivalent:
        print("SURVIVED  %-72s %s" % (name, last))
        failures.append(("SURVIVED", name))
    elif verdict != "green" and expected_equivalent:
        print("UNEXPECTED %-71s %s" % (name + " (was caught)", last))
        failures.append(("UNEXPECTED", name))
    else:
        print("caught    %-72s %s" % (name, last))

print()
if failures:
    for kind, label in (
            ("SURVIVED",   "mutant(s) survived - those assertions do not discriminate"),
            ("UNEXPECTED", "EQUIVALENT mutant(s) were caught - the equivalence claim is wrong"),
            ("CRASHED",    "mutant(s) aborted the harness rather than failing it"),
            ("SKIPPED",    "anchor(s) rotted - fix the anchor, never drop the mutant")):
        named = [n for verdict, n in failures if verdict == kind]
        if named:
            print("%d %s:" % (len(named), label))
            for n in named:
                print("  - " + n)
    sys.exit(1)
print("every mutant behaved as expected")
