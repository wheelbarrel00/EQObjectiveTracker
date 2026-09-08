"""Prove docs/test_quest_groups.lua actually discriminates, by breaking production on purpose
one change at a time and checking the harness notices.

    python docs/mutate_quest_groups.py        (run from the repo root)

Why this exists: Data/QuestGroups.lua answers one question - can this quest form a group - and
every way it can answer wrongly is silent. A wrong false costs the group finder eye and the Find
Group menu item with nothing on screen to say so; a wrong true offers both on a quest the game
will refuse. The cache is the only thing between that answer and a client call this project has
already bisected once for taint, so a cache that stops caching is a performance regression nobody
would see either.

DebugLine is in scope and is the reason the file got a harness at all. It counted the cache and
never said how many answers were TRUE, so one status line read identically whether every quest
genuinely refused or the eye had stopped drawing. That ambiguity cost a session on 2026-09-07.

Every mutation reintroduces a defect the harness is supposed to stand guard over. Any that still
reports "0 failed" is an assertion that does not discriminate, and the run exits 1 naming it.

WRITES TO THE TREE. It edits in place and restores through a finally, so an interrupted run still
puts the file back, and it verifies the restore and re-checks the baseline before reporting.

Anchors are exact source text and they rot. A SKIPPED line means an anchor stopped matching: fix
the anchor rather than dropping the mutant.
"""
import io
import re
import subprocess
import sys

LUA = r"C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe"
HARNESS = "docs/test_quest_groups.lua"

G = "Data/QuestGroups.lua"

MUTANTS = [
    # ------------------------------------------------ DebugLine, which is why this file exists
    # The defect this whole line was rewritten to remove: a count that cannot tell "every answer
    # is a real no" from "the eye stopped drawing".
    ("DebugLine stops naming the eligible ids, going back to a bare count", [
        (G, '    local eligible = #yes > 0 and table.concat(yes, " ") or "none"',
            '    local eligible = "none"')]),

    ("DebugLine counts every cached answer as eligible, not just the true ones", [
        (G, "        if answer then yes[#yes + 1] = qid end",
            "        yes[#yes + 1] = qid")]),

    # pairs order is unspecified, so without this two readings of a cache nothing touched can
    # differ and the line becomes unreadable as a diagnostic.
    ("the eligible list is left in pairs order rather than sorted", [
        (G, "    table.sort(yes)\n", "")]),

    ("DebugLine reports the eligible count as the cached total", [
        (G, "        :format(n, #yes, eligible, p, #listeners)",
            "        :format(#yes, #yes, eligible, p, #listeners)")]),

    # ------------------------------------------------------------------- the answer contract
    # entry.canGroup is assigned straight from this and every consumer is a plain truth test, so
    # a nil still gates correctly - but two comments in this repo asserted nil and reasoned from
    # it. The harness pins the real contract so the next reader does not have to guess.
    ("CanCreate answers nil rather than false while a lookup is outstanding", [
        (G, "    pending[questID] = true\n"
            "    if not queued then\n"
            "        queued = true\n"
            "        C_Timer.After(RESOLVE_DELAY, drain)\n"
            "    end\n"
            "    return false\n",
            "    pending[questID] = true\n"
            "    if not queued then\n"
            "        queued = true\n"
            "        C_Timer.After(RESOLVE_DELAY, drain)\n"
            "    end\n"
            "    return nil\n")]),

    ("a nil quest id is asked of the client instead of refused", [
        (G, "    if not questID then return false end\n", "")]),

    # --------------------------------------------------------------------------- the cache
    # Without this every render asks the client again, which is the call this project bisected
    # over eight rounds for taint and then deliberately moved onto a timer.
    ("the cache is never read, so every ask reaches the client", [
        (G, "    local cached = cache[questID]\n    if cached ~= nil then return cached end\n",
            "")]),

    ("the cache is never written, so an answer never settles", [
        (G, "        cache[qid] = answer\n", "")]),

    # ------------------------------------------------------------------------- the recheck
    # A false is either a real no or activity data that has not streamed in. Re-asking forever
    # risks being throttled by that API, which then returns nil for good.
    ("the single recheck is dropped, so a false is never re-asked", [
        (G, "        if answer == false and not rechecked[qid] then\n"
            "            rechecked[qid] = true\n"
            "            recheck[#recheck + 1] = qid\n"
            "        end\n", "")]),

    ("the recheck is unbounded, so a false is re-asked for the session", [
        (G, "        if answer == false and not rechecked[qid] then",
            "        if answer == false then")]),

    # --------------------------------------------------------------------------- the notify
    ("listeners fire on every drain rather than only when an answer moved", [
        (G, "    if not changed then return end\n", "")]),

    ("a raising listener strands the drain and the ones after it never run", [
        (G, "        local ok, err = pcall(listeners[i])\n"
            "        if not ok then geterrorhandler()(err) end\n",
            "        listeners[i]()\n")]),

    # --------------------------------------------------------------------- eviction and prune
    # Quest IDs get recycled, so an id seen removed has to drop or the next quest under it
    # inherits this answer.
    ("Forget leaves the cached answer behind for a recycled quest id", [
        (G, "        cache[questID] = nil\n        pending[questID] = nil\n",
            "        pending[questID] = nil\n")]),

    ("PruneExcept keeps everything, so the cache grows for the session", [
        (G, "        if not keep(qid) then", "        if false then")]),

    # ------------------------------------------------------------------------ the client APIs
    # The fallback is what answers on a client that has one global and not the other.
    ("the C_LFGList fallback is dropped, so a client with only it can never group", [
        (G, "    if C_LFGList and C_LFGList.CanCreateQuestGroup then\n"
            "        return C_LFGList.CanCreateQuestGroup(questID) and true or false\n"
            "    end\n", "")]),

    ("ask returns true where the client is silent, so every quest offers a group", [
        (G, "    return false\nend\n\n-- Resolved on a TIMER",
            "    return true\nend\n\n-- Resolved on a TIMER")]),
]

SUMMARY = re.compile(r"^test_quest_groups: (\d+) passed, (\d+) failed$")


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
