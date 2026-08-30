"""Prove docs/test_initiative.lua actually discriminates, by breaking production on purpose one
change at a time and checking the harness notices.

    python docs/mutate_initiative.py            (run from the repo root)

Why this exists: the first version of that harness had 25 assertions and an adversarial pass put
33 hand-built mutants past it, of which 27 survived. It read entry.groupID and called that proof
the provider declared the right group; it never shrank an objective run, so deleting Entry.EndLines
was invisible; it never built a task with no requirements, so the `total > 0` half of the complete
test was untested; and DebugLine had no assertion at all. None of that was visible from a green
run, which is the whole argument for this file.

Every mutation reintroduces a defect the harness is supposed to stand guard over. Any that still
reports "0 failed" is an assertion that does not discriminate, and the run exits 1 naming it -
unless the entry is marked EQUIVALENT, which means the mutation provably cannot change behavior
and so nothing could catch it. There is ONE of those and it is worth reading:

  - Deleting Entry.BeginLines changes nothing WHILE EndLines runs. EndLines clears _nlines and
    PushLine restarts from `(nil or 0) + 1`, so the run resets either way. Deleting EndLines is a
    real mutant and is caught.

A CRASHED verdict is reported apart from "caught" on purpose. A mutant that does not parse also
exits nonzero, and counting that as caught is a false pass in the one tool whose job is to find
false passes.

WRITES TO THE TREE. It edits Data/Providers/Initiative.lua in place and restores it after every
mutant through a finally, then verifies the restore and re-checks the baseline before reporting.
If you hard-kill it, recover from your editor's undo history, NOT with git - this file is
routinely uncommitted while it is being worked on.

Anchors are exact source text and they rot. A SKIPPED line means an anchor stopped matching: fix
the anchor rather than dropping the mutant.
"""
import io
import re
import subprocess
import sys

LUA = r"C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe"
SRC = "Data/Providers/Initiative.lua"
HARNESS = "docs/test_initiative.lua"

MUTANTS = [
    # ---------------------------------------------------------- the measured filter
    ("the filter goes back to inProgress, which measured wrong in game",
     "            if t and t.tracked and t.ID then",
     "            if t and t.inProgress and t.ID then"),

    ("the filter is dropped entirely, so all 27 tasks draw",
     "            if t and t.tracked and t.ID then",
     "            if t and t.ID then"),

    ("the id guard is dropped, so a task with no id emits a row that cannot be keyed",
     "            if t and t.tracked and t.ID then",
     "            if t and t.tracked then"),

    # ---------------------------------------------------------- the entry contract
    ("the provider declares a section of its own instead of the endeavors group",
     '    groups   = { "endeavors" },',
     '    groups   = { "initiative" },'),

    ("entries carry a different group id from the one the provider declares",
     '    groupID   = "endeavors",',
     '    groupID   = "initiative",'),

    ("an idSpace is declared, putting task ids into contention with quest claims",
     "    priority = 45,",
     '    priority = 45,\n    idSpace  = "quest",'),

    ("entries stop reporting themselves tracked, hiding the section under show-only-watched",
     "    isTracked = true,",
     "    isTracked = false,"),

    ("the title falls back to nothing instead of the task id",
     '                e.title = t.taskName or ("Task " .. tostring(t.ID))',
     '                e.title = t.taskName or ""'),

    # ---------------------------------------------------------- the objective run
    ("EQUIVALENT: Entry.BeginLines is deleted",
     "    Entry.BeginLines(e)\n    local reqs",
     "    local reqs"),

    ("Entry.EndLines is deleted, so a shrinking run keeps the longer run's tail",
     "    Entry.EndLines(e)\n    return done, total",
     "    return done, total"),

    ("the requirement text is passed through raw, bullet and padding included",
     "        ln.text      = ns.Util.CleanRequirement(rq.requirementText)",
     "        ln.text      = rq.requirementText"),

    ("a task with no requirements at all renders complete",
     "                if complete == nil then complete = (total > 0 and done == total) end",
     "                if complete == nil then complete = (done == total) end"),

    ("an explicit completed=false is overridden by the requirement tally",
     "                if complete == nil then complete = (total > 0 and done == total) end",
     "                if not complete then complete = (total > 0 and done == total) end"),

    # ---------------------------------------------------------- the gates
    ("the enabled and access gates are dropped from GetEntries",
     "    local live = (enabled and access) and true or false",
     "    local live = true"),

    # The gates are deliberately NOT cached with the graph: both are cheap boolean reads and
    # both change mid-session, which is the whole reason they sit here rather than in
    # IsAvailable. Folding them into the dirty flag puts the section to sleep for the session.
    ("the live gate is cached with the graph, so a mid-session change never lands",
     "    if not dirty and live == lastLive then return store:Out() end",
     "    if not dirty then return store:Out() end"),

    # The cache itself. Without the flag the whole initiative graph is rebuilt per repaint.
    ("the graph cache is dropped, rebuilding the whole graph every repaint",
     "    if not dirty and live == lastLive then return store:Out() end\n",
     ""),

    # The async fetch and the raise. Clearing the flag before the walk, or against an answer
    # that had not streamed in, latches a stale section for the rest of the session.
    ("the flag is cleared before the walk, so a raise latches the half-built answer",
     "    local settled = true",
     "    local settled = true\n    dirty, lastLive = false, live"),

    ("an answer that has not streamed in yet is cached as if it had",
     "        settled = (data ~= nil) and (data.isLoaded ~= false)",
     "        settled = true"),

    ("the dirty flag is never cleared, so the cache never holds",
     "    if settled then dirty, lastLive = false, live end",
     "    if settled then lastLive = live end"),

    ("IsAvailable becomes a content probe and goes stale for the session",
     '    return type(C_NeighborhoodInitiative) == "table"\n'
     '       and type(C_NeighborhoodInitiative.GetNeighborhoodInitiativeInfo) == "function"',
     '    return type(C_NeighborhoodInitiative) == "table"\n'
     '       and type(C_NeighborhoodInitiative.GetNeighborhoodInitiativeInfo) == "function"\n'
     "       and C_NeighborhoodInitiative.IsInitiativeEnabled()"),

    # ---------------------------------------------------------- the async fetch
    ("the fetch is issued from the render path",
     "        local data  = readInfo()",
     "        C.RequestNeighborhoodInitiativeInfo()\n        local data  = readInfo()"),

    ("the update event is not subscribed, so the section never refreshes",
     '    Events:On("NEIGHBORHOOD_INITIATIVE_UPDATED", invalidate)',
     "    -- removed"),

    # A bare notifyDirty is not enough for a provider whose GetEntries caches: it asks for a
    # repaint and sets no flag, so the same entries are handed straight back.
    ("the event repaints without setting the dirty flag",
     "    local function invalidate()\n        dirty = true\n        notifyDirty()\n    end",
     "    local function invalidate()\n        notifyDirty()\n    end"),

    # ---------------------------------------------------------- the instrument
    ("DebugLine loses its pcall, so one raising API takes the whole status report down",
     '        local ok, res = pcall(fn)\n        if not ok then return "raised" end',
     '        local res = fn()\n        if false then return "raised" end'),

    ("DebugLine stops counting the ids GetEntries needs, hiding a renamed id field",
     "                if t.ID then withID = withID + 1 end",
     "                if t.ID then withID = withID + 0 end"),

    ("DebugLine tallies inProgress where it means tracked",
     "            if t.tracked then\n                trk = trk + 1",
     "            if t.inProgress then\n                trk = trk + 1"),
]

SUMMARY = re.compile(r"^test_initiative: (\d+) passed, (\d+) failed$")


def run():
    """(verdict, note). verdict is "green", "failed" or "crashed"."""
    r = subprocess.run([LUA, HARNESS], capture_output=True, text=True)
    lines = [l for l in r.stdout.splitlines() if l.strip()]
    for line in reversed(lines):
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
    equivalent = name.startswith("EQUIVALENT:")
    if verdict == "crashed":
        print("CRASHED   %-74s %s" % (name, last))
        survivors.append(name)
    elif verdict == "green" and not equivalent:
        print("SURVIVED  %-74s %s" % (name, last))
        survivors.append(name)
    elif verdict == "failed" and equivalent:
        print("UNEXPECTED %-73s %s" % (name + " (was caught)", last))
        survivors.append(name)
    elif equivalent:
        print("survived  %-74s as expected, it cannot change behavior" % name)
    else:
        print("caught    %-74s %s" % (name, last))

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
