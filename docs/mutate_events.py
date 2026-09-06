"""Prove docs/test_events.lua actually discriminates, by breaking Core/Events.lua on purpose one
change at a time and checking the harness notices.

    python docs/mutate_events.py        (run from the repo root)

Why this exists: this file had no harness and no battery at all until 2026-09-05, and it carries
the one failure mode that can silence the whole addon without an error.

A debounce key is disarmed ONLY by its own timer callback. Before the recovery below, a
C_Timer.After that never fired left the key armed for the session, and every later Debounce on it
replaced d.fn, returned false and scheduled NOTHING - so the work never ran, nothing errored, and
there was no way back short of a reload. Read off a user's client: the quest sound scan had not
run for 39 minutes while the events driving it kept firing, and on that same client a manual
Tracker:Refresh() did nothing where Tracker:Render() worked. Only the scan is carried by a counter
of its own; the dead repaint is read off that Refresh/Render split rather than measured directly.

Three directions matter equally here, so the battery carries all three. A recovery that never
fires leaves the original bug. One that fires too eagerly turns off the burst collapse this
function exists to do. And one whose stray timer can still serve a later arming runs the key
twice per window from then on. The last two both hand back the render rate v1.17.0 was released
to cut, and the third was measured at a sustained 2x before the tick gained its deadline guard.

Every mutation reintroduces a defect the harness is supposed to stand guard over. Any that still
reports "0 failed" is an assertion that does not discriminate, and the run exits 1 naming it.

WRITES TO THE TREE. It edits in place and restores through a finally, so an interrupted run still
puts the file back, and it verifies the restore and re-checks the baseline before reporting. If
you hard-kill it anyway and the file is committed, git restore is the recovery; while the work is
still uncommitted it is your editor's undo history instead.

Anchors are exact source text and they rot. A SKIPPED line means an anchor stopped matching: fix
the anchor rather than dropping the mutant.
"""
import io
import re
import subprocess
import sys

LUA = r"C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe"
HARNESS = "docs/test_events.lua"

EV = "Core/Events.lua"

MUTANTS = [
    # ------------------------------------------------- the recovery, in the losing direction
    ("the recovery is removed, so one lost timer strands the key for the session", [
        (EV, "        -- Collapsing a burst is the whole point of this, so only an OVERDUE key"
             " counts as lost.\n"
             "        local late = GetTime() - d.at - d.delay\n"
             "        if late <= LOST_SLACK then\n"
             "            d.fn = fn\n"
             "            return false\n"
             "        end\n"
             "        _debRecovered = _debRecovered + 1\n"
             "        if late > _debWorstLate then _debWorstLate = late end\n",
             "        d.fn = fn\n"
             "        return false\n")]),

    ("LOST_SLACK is raised out of reach, so no key is ever judged lost", [
        (EV, "local LOST_SLACK = 3", "local LOST_SLACK = 100000")]),

    ("the recovery re-arms without re-stamping, so a recovered key never collapses again", [
        (EV, "    d.at    = GetTime()", "    d.at    = d.at or GetTime()")]),

    # ------------------------------------------ the recovery, in the burst-collapse direction
    ("every armed key is treated as lost, so a burst is never collapsed", [
        (EV, "        if late <= LOST_SLACK then", "        if false then")]),

    ("the overdue test is inverted, so live bursts recover and lost keys do not", [
        (EV, "        if late <= LOST_SLACK then", "        if late > LOST_SLACK then")]),

    ("the overdue test measures from the arming rather than from the deadline", [
        (EV, "        local late = GetTime() - d.at - d.delay",
             "        local late = GetTime() - d.at")]),

    # ----------------------------------------------------- the counters that report the rescue
    ("the recovery counter is not incremented, so the status cannot report a rescue", [
        (EV, "        _debRecovered = _debRecovered + 1\n", "")]),

    ("the worst-late figure is not tracked, so timer jitter and a dead key read alike", [
        (EV, "        if late > _debWorstLate then _debWorstLate = late end\n", "")]),

    ("the key is never recorded, so the status can never name an armed one", [
        (EV, "        _debOrder[#_debOrder + 1] = key\n", "")]),

    ("the armed age is measured backwards", [
        (EV, '            armed[#armed + 1] = ("%s %.0fs"):format(key, now - d.at)',
             '            armed[#armed + 1] = ("%s %.0fs"):format(key, d.at - now)')]),

    # --------------------------------------------------------------------- the tick's own job
    ("the armed flag is not cleared, so every key strands itself after one use", [
        (EV, "    d.armed = false\n", "")]),

    ("the pending function is not cleared, so a late timer runs the work twice", [
        (EV, "    d.fn    = nil\n", "")]),

    ("the tick calls its callback bare, so one raising handler escapes the timer", [
        (EV, "        local ok, err = pcall(fn)\n"
             "        if not ok then geterrorhandler()(err) end",
             "        fn()")]),

    # pcall(nil) does not raise, it answers false, so this reaches the error handler rather than
    # running anything - which is why the case behind it asserts the error count, not a raise.
    ("the tick's empty-slot guard is dropped, so a cleared key reports an error", [
        (EV, "    if fn then\n"
             "        local ok, err = pcall(fn)",
             "    if true then\n"
             "        local ok, err = pcall(fn)")]),

    # ------------------------------------------------------------------------- registration
    ("the unknown set is not consulted, so a refused event is asked of the client again", [
        (EV, "    if unknown[event] then return false end\n", "")]),

    ("a refused registration is not recorded", [
        (EV, "            unknown[event] = true\n", "")]),

    ("the registration is not protected, so an unknown event aborts the caller", [
        (EV, "        if not pcall(frame.RegisterEvent, frame, event) then\n"
             "            unknown[event] = true\n"
             "            return false\n"
             "        end\n",
             "        frame:RegisterEvent(event)\n")]),

    ("On answers true for an event it refused", [
        (EV, "            unknown[event] = true\n"
             "            return false",
             "            unknown[event] = true\n"
             "            return true")]),

    # ----------------------------------------------------------------------------- dispatch
    ("a raising handler stops every handler after it", [
        (EV, "            local ok, err = pcall(fn, event, ...)\n"
             "            if not ok then geterrorhandler()(err) end",
             "            fn(event, ...)")]),

    ("the event name is dropped from the payload", [
        (EV, "pcall(fn, event, ...)", "pcall(fn, ...)")]),

    # ---------------------------------------------------------------------------------- Off
    ("Off removes every handler rather than the one it was given", [
        (EV, "        if list[i] == fn then tremove(list, i) end", "        tremove(list, i)")]),

    ("the event is never unregistered when its last handler goes", [
        (EV, "    if #list == 0 then\n"
             "        listeners[event] = nil\n"
             "        frame:UnregisterEvent(event)\n"
             "    end\n", "")]),

    # ------------------------------- the recovery's stray timer, which is the third direction
    ("the stray timer guard is dropped, so a recovery doubles the key's rate for the session", [
        (EV, "    if GetTime() < d.at + d.delay then return end\n", "")]),

    ("the stray timer guard is inverted, so the arming's own tick is the one that returns", [
        (EV, "    if GetTime() < d.at + d.delay then return end",
             "    if GetTime() >= d.at + d.delay then return end")]),

    ("the delay is not stamped, so the tick has no deadline to measure itself against", [
        (EV, "    d.delay = delay\n", "")]),

    ("lateness is measured against the CALLER's delay rather than the arming's", [
        (EV, "        local late = GetTime() - d.at - d.delay",
             "        local late = GetTime() - d.at - delay")]),

    ("the debounce window is collapsed to zero, so no burst is ever held back", [
        (EV, "    C_Timer.After(delay, getDebTickFn(key))",
             "    C_Timer.After(0, getDebTickFn(key))")]),

    ("the key is recorded on every arm, so the status count climbs without bound", [
        (EV, "    if not d then\n"
             "        d = {}\n"
             "        _debounce[key] = d\n"
             "        _debOrder[#_debOrder + 1] = key\n"
             "    end\n",
             "    if not d then\n"
             "        d = {}\n"
             "        _debounce[key] = d\n"
             "    end\n"
             "    _debOrder[#_debOrder + 1] = key\n")]),

    ("the happy-path status wording is replaced, which is the line most users paste", [
        (EV, '    local first = "events: every registration accepted by this client"',
             '    local first = "events: ok"')]),

    # ------------------------------------------------------------------- combat deferral
    ("the flush calls its callbacks bare, so one raise abandons every key behind it", [
        (EV, "        if fn then\n"
             "            local ok, err = pcall(fn)\n"
             "            if not ok then geterrorhandler()(err) end\n"
             "        end\n",
             "        if fn then\n"
             "            fn()\n"
             "        end\n")]),

    # Drains until empty instead of snapshotting, which is the natural way to rewrite this and
    # is what the two-pass structure exists to avoid: a key deferred by a callback DURING the
    # flush is then consumed by the same flush, so its combat gate means nothing.
    ("the flush drains until empty, so a key deferred during it runs in that same pass", [
        (EV, "    local n = #_deferOrder\n"
             "    for i = 1, n do\n"
             "        _flushKeys[i]  = _deferOrder[i]\n"
             "        _deferOrder[i] = nil\n"
             "    end\n"
             "    for i = 1, n do\n"
             "        local key = _flushKeys[i]\n"
             "        local fn  = _deferred[key]\n"
             "        _deferred[key] = nil\n"
             "        _flushKeys[i]  = nil\n",
             "    while #_deferOrder > 0 do\n"
             "        local key = tremove(_deferOrder, 1)\n"
             "        local fn  = _deferred[key]\n"
             "        _deferred[key] = nil\n")]),

    ("InCombat hands back the client's raw answer rather than a boolean", [
        (EV, "    return InCombatLockdown() and true or false",
             "    return InCombatLockdown()")]),

    ("the emptied listener list is left in place, so a later On never re-registers the event", [
        (EV, "        listeners[event] = nil\n", "")]),

    ("the deferral queue becomes LIFO", [
        (EV, "    if _deferred[key] == nil then _deferOrder[#_deferOrder + 1] = key end",
             "    if _deferred[key] == nil then table.insert(_deferOrder, 1, key) end")]),

    ("a re-deferred key keeps the OLD function rather than the newer one", [
        (EV, "    _deferred[key] = fn\n",
             "    if _deferred[key] == nil then _deferred[key] = fn end\n")]),

    ("out of combat the work is deferred instead of run", [
        (EV, "    if not InCombatLockdown() then\n"
             "        fn()\n"
             "        return true\n"
             "    end\n", "")]),

    # NOT a replay: the flush empties _deferOrder either way, so the next combat end walks nothing.
    # The damage only shows when the SAME key is deferred again AFTER a flush, where the leftover
    # entry reads as already queued, nothing is appended, and the work is accepted and never runs.
    ("a flushed key is left in the map, so deferring it again queues nothing", [
        (EV, "        _deferred[key] = nil\n", "")]),

    # A real equivalence rather than a placeholder: a fresh closure per call behaves identically
    # and only allocates more. It is here so the EQUIVALENT verdict below is exercised by
    # something, because two drivers in this tree once printed a verdict their loop could never
    # produce and the first equivalent mutant anyone added would have read as SURVIVED.
    # Also a real equivalence: Events:On only reaches RegisterEvent when the listener list is
    # nil, so subscribing the flush repeatedly appends handlers that each find an empty queue and
    # no-op. The cost is one leaked listener per deferred key and nothing here can observe it,
    # which is exactly why it is recorded rather than left for a future reader to rediscover.
    ("EQUIVALENT: the flush is subscribed on every deferral rather than once", [
        (EV, "    if not _flushArmed then\n"
             "        _flushArmed = true\n"
             '        self:On("PLAYER_REGEN_ENABLED", flushDeferred)\n'
             "    end\n",
             '    self:On("PLAYER_REGEN_ENABLED", flushDeferred)\n')]),

    ("EQUIVALENT: the tick closure is not memoized per key", [
        (EV, "local function getDebTickFn(key)\n"
             "    local fn = _debTickFns[key]\n"
             "    if not fn then\n"
             "        fn = function() debounceTick(key) end\n"
             "        _debTickFns[key] = fn\n"
             "    end\n"
             "    return fn\n"
             "end",
             "local function getDebTickFn(key)\n"
             "    return function() debounceTick(key) end\n"
             "end")]),
]

SUMMARY = re.compile(r"^test_events: (\d+) passed, (\d+) failed$")


def run():
    """(verdict, note). verdict is "green", "failed" or "crashed".

    A nonzero exit is NOT evidence that an assertion discriminated - a mutant that does not parse
    exits nonzero too, and reporting that as "caught" is a false pass in the one tool whose job is
    to catch false passes. So the harness's own summary line is matched rather than its exit code,
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
        # Its own word rather than "caught": nothing caught this one, and reading a green line
        # as an assertion doing work is how a coverage hole gets mistaken for coverage.
        print("EQUIVALENT %-73s %s" % (name, last))
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
