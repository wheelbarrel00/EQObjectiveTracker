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
import subprocess
import sys

LUA = r"C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe"
DATA = "Data/ScenarioBonus.lua"
HUD = "UI/ScenarioBonusHUD.lua"

# The pre-fix lives reader, restored faithfully: the word-matching stop guard AND the walk that
# obeyed it. Mutating only one half does not reproduce the bug, which is worth knowing - a
# half-mutation reported a false SURVIVED the first time this battery ran.
LIVES_REVERT = [
    ("""        local clean = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        return tonumber(clean:match("^%s*(%d+)%s*$"))""",
     """        local clean = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        if clean:find("Challenge", 1, true) or clean:find("Wave", 1, true) then
            return "stop"
        end
        return tonumber(clean:match("^%s*(%d+)%s*$"))"""),
    ("""    local digits, count, answer = {}, 0, nil
    local function walk(f, depth)
        if answer or not f or depth > LIVES_MAX_DEPTH then return end""",
     """    local digits, count, stop = {}, 0, false
    local function walk(f, depth)
        if stop or not f or depth > LIVES_MAX_DEPTH then return end"""),
    ("""                local d = livesDigit(regions[i])
                if d then
                    if knownTier and digits[count] == knownTier then answer = d return end
                    count = count + 1
                    digits[count] = d
                end""",
     """                local d = livesDigit(regions[i])
                if d == "stop" then stop = true return end
                if d then count = count + 1; digits[count] = d end"""),
    ("""                walk(kids[i], depth + 1)
                if answer then return end""",
     """                walk(kids[i], depth + 1)
                if stop then return end"""),
    ("""    if answer then return answer end""",
     """    if knownTier then
        for i = 1, count - 1 do
            if digits[i] == knownTier then return digits[i + 1] end
        end
    end"""),
]

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

    ("checkRun's exit arm deleted outright", DATA, [
        ("""    if not playerInDelve() then
        trackedDelve = nil
        resetRun()""",
         """    if not playerInDelve() then
        if false then
        trackedDelve = nil
        resetRun()""")]),

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

    ("the lives reader called unguarded from the model", DATA, [
        ("    if livesReader then okLives, lives = pcall(livesReader, delveTier) end",
         "    if livesReader then okLives, lives = true, livesReader(delveTier) end")]),

    ("the rager despawn test back on a flushed list", DATA, [
        ('    if listed > 0 and ragerGUID and not ragerSeen and bannerState == "eliteUp" then',
         '    if ragerGUID and not ragerSeen and bannerState == "eliteUp" then')]),

    ("the tier floor removed, so the total no longer reflects the tier", DATA, [
        ("        local total  = math.max(expected, packsKilledBase + nemesisSeenCount)",
         "        local total  = packsKilledBase + nemesisSeenCount")]),

    ("the whole pre-fix lives reader restored, word-matching stop guard and all", HUD,
     LIVES_REVERT),

    ("the lives walk reading past the answer", HUD, [
        ("                    if knownTier and digits[count] == knownTier then answer = d return end",
         "                    if false then answer = d return end")]),

    ("the lives reader guessing from a stream it cannot resolve", HUD, [
        ("    if count == 2 then return digits[2] end",
         "    if count >= 2 then return digits[2] end")]),
]


def run():
    r = subprocess.run([LUA, "docs/test_scenario_bonus.lua"], capture_output=True, text=True)
    out = (r.stdout + r.stderr).strip()
    return r.returncode, (out.splitlines()[-1] if out else "(no output)")


originals = {p: io.open(p, encoding="utf-8", newline="").read() for p in (DATA, HUD)}

code, last = run()
print("baseline: %s\n" % last)
if code != 0:
    print("BASELINE IS NOT GREEN - stopping")
    sys.exit(1)

survivors = []
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
        survivors.append(name)
        continue
    try:
        io.open(path, "w", encoding="utf-8", newline="").write(mutated)
        code, last = run()
    finally:
        io.open(path, "w", encoding="utf-8", newline="").write(src)
    expected_equivalent = name.startswith("EQUIVALENT:")
    if code == 0 and not expected_equivalent:
        print("SURVIVED  %-72s %s" % (name, last))
        survivors.append(name)
    elif code != 0 and expected_equivalent:
        print("UNEXPECTED %-71s %s" % (name + " (was caught)", last))
        survivors.append(name)
    else:
        print("caught    %-72s %s" % (name, last))

print()
if survivors:
    print("%d mutant(s) survived - those assertions do not discriminate:" % len(survivors))
    for s in survivors:
        print("  - " + s)
    sys.exit(1)
print("every mutant behaved as expected")
