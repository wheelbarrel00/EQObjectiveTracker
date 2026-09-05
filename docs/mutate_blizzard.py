"""Prove docs/test_blizzard.lua actually discriminates, by breaking production on purpose one
change at a time and checking the harness notices.

    python docs/mutate_blizzard.py        (run from the repo root)

Why this exists: UI/Blizzard.lua writes to a frame this addon does not own, on every flavor, at
login and at every world change and every combat end. Its two recorded failures were both silent
- a latch that made every Suppress after the first a no-op and put a second tracker on screen,
and a synchronous Hide from inside Blizzard's own OnShow that was followed by a blocked map-pin
action off a stack carrying none of this addon's code. Neither raised anything.

The mutant that matters most is the SNAPSHOT. Blizzard's RemoveModule deletes from the very
table the unmount walks, so dropping the snapshot leaves every second module mounted: the
scenario module's unguarded secret-aura read is still reached, the reported error still fires,
and a client with one module reports it fixed.

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
HARNESS = "docs/test_blizzard.lua"

ROW = "UI/Blizzard.lua"

MUTANTS = [
    # ------------------------------------------------- the unmount, which this release adds
    ("the snapshot is dropped, so a shrinking list leaves every second module mounted", [
        (ROW, """    local mods, n = {}, #tracker.modules
    for i = 1, n do mods[i] = tracker.modules[i] end
    for i = 1, n do
        if pcall(tracker.RemoveModule, tracker, mods[i]) then
            self._unmounted = (self._unmounted or 0) + 1
        end
    end""",
              """    for i = 1, #tracker.modules do
        if pcall(tracker.RemoveModule, tracker, tracker.modules[i]) then
            self._unmounted = (self._unmounted or 0) + 1
        end
    end""")]),

    ("the snapshot is taken but the walk still reads the live list", [
        (ROW, "        if pcall(tracker.RemoveModule, tracker, mods[i]) then",
              "        if pcall(tracker.RemoveModule, tracker, tracker.modules[i]) then")]),

    ("only the first module is unmounted", [
        (ROW, "    for i = 1, n do\n        if pcall(tracker.RemoveModule, tracker, mods[i]) then",
              "    for i = 1, 1 do\n        if pcall(tracker.RemoveModule, tracker, mods[i]) then")]),

    ("the shape guard is dropped, so Classic raises at every world change", [
        (ROW, '    if type(tracker.RemoveModule) ~= "function" or type(tracker.modules) ~= "table" then\n'
              "        return\n"
              "    end",
              "    -- unguarded")]),

    ("the per-module pcall goes, so one raising module leaves the rest mounted", [
        (ROW, "        if pcall(tracker.RemoveModule, tracker, mods[i]) then\n"
              "            self._unmounted = (self._unmounted or 0) + 1\n"
              "        end",
              "        tracker:RemoveModule(mods[i])\n"
              "        self._unmounted = (self._unmounted or 0) + 1")]),

    ("the unmount is never called, so Blizzard lays out inside the hidden frame as before", [
        (ROW, "    unmount(self, tracker)", "    -- unmounted")]),

    ("the unmount is latched, so a module Blizzard adds back stays mounted", [
        (ROW, "    unmount(self, tracker)",
              "    if not self._didUnmount then self._didUnmount = true unmount(self, tracker) end")]),

    ("the unmounted counter never moves, so the status line cannot tell retail from Classic", [
        (ROW, "            self._unmounted = (self._unmounted or 0) + 1", "")]),

    # ------------------------------------------------- the suppression this file already had
    ("the alpha is not zeroed, so a re-shown frame draws for a frame before the re-hide", [
        (ROW, "    if frame.SetAlpha then frame:SetAlpha(0) end", "")]),

    ("the frame is blanked but never hidden, so it still eats clicks and tooltips", [
        (ROW, "    if frame.Hide then frame:Hide() end", "")]),

    ("the frame's own events are left registered", [
        (ROW, "    if frame.UnregisterAllEvents then frame:UnregisterAllEvents() end", "")]),

    ("the hook guard goes, so every Suppress stacks another OnShow hook", [
        (ROW, "    if self._hookedFrame ~= tracker then\n        self._hookedFrame = tracker",
              "    if true then\n        self._hookedFrame = tracker")]),

    ("the re-hide is synchronous again, from inside Blizzard's own Show", [
        (ROW, "            C_Timer.After(0, function()",
              "            (function(_, fn) fn() end)(0, function()")]),

    ("the deferred re-hide is not coalesced, so a burst of shows queues one callback each", [
        (ROW, "            if self._hidePending then return end", "")]),

    # ---------------------------------------------- everything the first run of this left bare
    # A scan measured 15 of 17 probes surviving this file's green 58 assertions: the unmount and
    # the hide/alpha/unregister trio were covered and essentially nothing else was. These are
    # the probes that survived, each now with a case behind it.
    ("the module count is hardcoded to zero, which every case already expected", [
        (ROW, "    local n = (type(t.modules) == \"table\") and #t.modules or 0",
              "    local n = 0")]),

    ("the unmounted counter moves whether or not the removal happened", [
        (ROW, """        if pcall(tracker.RemoveModule, tracker, mods[i]) then
            self._unmounted = (self._unmounted or 0) + 1
        end""",
              """        pcall(tracker.RemoveModule, tracker, mods[i])
        self._unmounted = (self._unmounted or 0) + 1""")]),

    ("the world-change re-suppression is never registered", [
        (ROW, '    Events:On("PLAYER_ENTERING_WORLD", function() self:Suppress() end)\n', "")]),

    ("the combat-end re-suppression is never registered", [
        (ROW, '    Events:On("PLAYER_REGEN_ENABLED",  function() self:Suppress() end)\n', "")]),

    ("the ADDON_LOADED gate is inverted, so every other addon re-suppresses instead", [
        (ROW, '        if name == "Blizzard_ObjectiveTracker" then self:Suppress() end',
              '        if name ~= "Blizzard_ObjectiveTracker" then self:Suppress() end')]),

    ("OnEnable registers but never suppresses, so nothing happens until the first world change", [
        (ROW, "function Blizzard:OnEnable()\n    self:Suppress()\n",
              "function Blizzard:OnEnable()\n")]),

    ("the combat re-suppress queued from the deferred hide is dropped", [
        (ROW, """                if InCombatLockdown() then
                    local Events = ns:GetModule("Events")
                    if Events and Events.RunWhenOutOfCombat then
                        self._reSuppress = self._reSuppress or function() self:Suppress() end
                        Events:RunWhenOutOfCombat("eqot.blizzardSuppress", self._reSuppress)
                    end
                end""", "")]),

    ("the hook is keyed on a flag, so a second frame never gets one", [
        (ROW, "    if self._hookedFrame ~= tracker then\n        self._hookedFrame = tracker",
              "    if not self._hookedFrame then\n        self._hookedFrame = tracker")]),

    ("findTracker tries the Classic global first", [
        (ROW, """    local f = ObjectiveTrackerFrame
    if type(f) == "table" and type(f.Hide) == "function" then
        return f, "ObjectiveTrackerFrame"
    end
    f = QuestWatchFrame
    if type(f) == "table" and type(f.Hide) == "function" then
        return f, "QuestWatchFrame"
    end""",
              """    local f = QuestWatchFrame
    if type(f) == "table" and type(f.Hide) == "function" then
        return f, "QuestWatchFrame"
    end
    f = ObjectiveTrackerFrame
    if type(f) == "table" and type(f.Hide) == "function" then
        return f, "ObjectiveTrackerFrame"
    end""")]),

    ("findTracker takes any table, so a placeholder global reads as the tracker", [
        (ROW, """    local f = ObjectiveTrackerFrame
    if type(f) == "table" and type(f.Hide) == "function" then""",
              """    local f = ObjectiveTrackerFrame
    if type(f) == "table" then""")]),

    ("Suppress runs with no tracker frame, which is what ADDON_LOADED exists for", [
        (ROW, "    local tracker = findTracker()\n    if not tracker then return end",
              "    local tracker = findTracker()")]),

    ("the two SHOWN states collapse, so a deferred hide reads as a lost suppression", [
        (ROW, '        shown = self._hidePending and "SHOWN - hide pending" or '
              '"SHOWN - suppression lost"',
              '        shown = "SHOWN - suppression lost"')]),

    ("re-shows are never counted", [
        (ROW, "            self._shows, self._lastShow = (self._shows or 0) + 1, GetTime()",
              "            self._lastShow = GetTime()")]),

    ("the re-show age is inverted, so it counts backwards from the stamp", [
        (ROW, 'local ago = self._lastShow and ("%.0fs ago"):format(GetTime() - self._lastShow)',
              'local ago = self._lastShow and ("%.0fs ago"):format(self._lastShow - GetTime())')]),

    ("the re-show age is a literal zero, so the status line always reads last 0s ago", [
        (ROW, 'local ago = self._lastShow and ("%.0fs ago"):format(GetTime() - self._lastShow)',
              'local ago = self._lastShow and ("%.0fs ago"):format(0)')]),

    ("the alpha field is hardcoded, so a side-by-side client is indistinguishable", [
        (ROW, '        t:GetAlpha() or 0, self._shows or 0, ago)',
              '        0, self._shows or 0, ago)')]),

    ("the queued combat re-suppress is an empty closure", [
        (ROW, 'self._reSuppress = self._reSuppress or function() self:Suppress() end',
              'self._reSuppress = self._reSuppress or function() end')]),

    ("the re-show age is never stamped, so the line always reads never", [
        (ROW, '    local ago = self._lastShow and ("%.0fs ago"):format(GetTime() - self._lastShow)'
              ' or "never"',
              '    local ago = "never"')]),

    ("silence assumes SetAlpha exists, though findTracker only ever proved Hide", [
        (ROW, "    if frame.SetAlpha then frame:SetAlpha(0) end",
              "    frame:SetAlpha(0)")]),

    ("silence assumes UnregisterAllEvents exists", [
        (ROW, "    if frame.UnregisterAllEvents then frame:UnregisterAllEvents() end",
              "    frame:UnregisterAllEvents()")]),

    ("the deferred hide writes to a frame Blizzard already hid", [
        (ROW, "                if not f:IsShown() then return end\n", "")]),

    ("the status line drops the unmounted count", [
        (ROW, '        n, self._unmounted or 0, self._hookedFrame and "installed" or "missing",',
              '        n, self._hookedFrame and "installed" or "missing",'),
        (ROW, '    return ("blizzard tracker: %s %s, %d modules (%d unmounted), hook %s'
              ' | alpha %.2f | reshown %d, last %s"):format(',
              '    return ("blizzard tracker: %s %s, %d modules, hook %s'
              ' | alpha %.2f | reshown %d, last %s"):format(')]),
]

SUMMARY = re.compile(r"^test_blizzard: (\d+) passed, (\d+) failed$")


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
