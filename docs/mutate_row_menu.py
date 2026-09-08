"""Prove docs/test_row_menu.lua actually discriminates, by breaking production on purpose one
change at a time and checking the harness notices.

    python docs/mutate_row_menu.py        (run from the repo root)

Why this exists: every failure this menu item can have is SILENT. Providers return item IDs and
UI/RowMenu.lua turns an id into wording with `local label = it.label or LABELS[it.id]` followed
by `if label then`, so an id with no label draws nothing and reports nothing. The gate is one
`entry.canGroup` test, and past it the item appears on rows that cannot form a group, where
clicking it opens the group finder on nothing. Each provider answers out of its own reused
file-local table, so a dropped wipe leaves a previous row's item on the next one. None of that
raises a Lua error, and no gate in this repo can see any of it.

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
HARNESS = "docs/test_row_menu.lua"

Q = "Data/Providers/Quests.lua"
W = "Data/Providers/WorldQuests.lua"
R = "UI/RowMenu.lua"

Q_GATE = '    if entry.canGroup then menuOut[#menuOut + 1] = { id = "findgroup", order = 55 } end'
W_GATE = '    if entry.canGroup then menuOut[#menuOut + 1] = { id = "findgroup", order = 25 } end'
DISPATCH = ('    elseif itemID == "findgroup" then\n'
            '        self:OnEntryGroupFinder({ id = entryID })\n')
WIPE = "    for i = #menuOut, 1, -1 do menuOut[i] = nil end\n"

MUTANTS = [
    # ------------------------------------------------------- the gate, which is the whole item
    ("the canGroup gate is dropped, so every quest offers Find Group", [
        (Q, Q_GATE, '    menuOut[#menuOut + 1] = { id = "findgroup", order = 55 }')]),

    ("the canGroup gate is inverted, so only ungroupable quests offer it", [
        (Q, Q_GATE, '    if not entry.canGroup then'
                    ' menuOut[#menuOut + 1] = { id = "findgroup", order = 55 } end')]),

    # CanCreate answers false BOTH for a resolved no and for a lookup still outstanding, so a
    # presence test offers the item on a quest already known to refuse a group. Only the
    # canGroup=false case can tell a presence test from a truth test.
    ("the gate tests presence rather than truth, so a resolved false still offers it", [
        (Q, Q_GATE, '    if entry.canGroup ~= nil then'
                    ' menuOut[#menuOut + 1] = { id = "findgroup", order = 55 } end')]),

    ("the same gate is dropped on the world quest menu", [
        (W, W_GATE, '    menuOut[#menuOut + 1] = { id = "findgroup", order = 25 }')]),

    # --------------------------------------------------------------------------- the ordering
    # 35 is EQ's, claimed by its Chain Guide item through Core/API.lua. A collision does not
    # raise: byOrder tie-breaks on the id, so the two silently swap places by spelling.
    ("Find Group takes order 35, colliding with EQ's Chain Guide item", [
        (Q, Q_GATE, Q_GATE.replace("order = 55", "order = 35"))]),

    ("Find Group moves to 45, splitting Open Log from Pop Out", [
        (Q, Q_GATE, Q_GATE.replace("order = 55", "order = 45"))]),

    ("the world quest item sorts after Wowhead instead of before it", [
        (W, W_GATE, W_GATE.replace("order = 25", "order = 35"))]),

    # ----------------------------------------------------------------------------- the styling
    ("Find Group is marked danger, drawing a harmless action in red", [
        (Q, Q_GATE, Q_GATE.replace('order = 55 }', 'order = 55, danger = true }'))]),

    # ----------------------------------------------------------------------------- the dispatch
    ("the dispatch branch is dropped, so the item draws and does nothing", [
        (Q, DISPATCH, "")]),

    ("the dispatch branch is dropped on the world quest menu", [
        (W, DISPATCH, "")]),

    # OnEntryGroupFinder indexes entry.id, so a bare id means indexing a number: a visible Lua
    # error, not a group finder quietly opening on nothing.
    ("the bare id is passed where an entry is expected, so entry.id reads nil", [
        (Q, "        self:OnEntryGroupFinder({ id = entryID })",
            "        self:OnEntryGroupFinder(entryID)")]),

    ("the same, on the world quest menu", [
        (W, "        self:OnEntryGroupFinder({ id = entryID })",
            "        self:OnEntryGroupFinder(entryID)")]),

    ("findgroup dispatches to the quest log instead of the group finder", [
        (Q, "        self:OnEntryGroupFinder({ id = entryID })",
            "        self:OnEntryOpenLog({ id = entryID })")]),

    # ------------------------------------------------- the reused table both providers answer with
    ("the menu wipe is dropped, so a groupable quest's item rides onto the next row", [
        (Q, WIPE, "")]),

    ("the same wipe is dropped on the world quest menu", [
        (W, WIPE, "")]),

    # --------------------------------------------------------------------------- the label
    # The silent one. No label means UI/RowMenu.lua's `if label then` skips the button
    # entirely: the provider offers the item, the menu draws without it, and nothing anywhere
    # says so.
    ("the LABELS entry is removed, so the item is silently never drawn", [
        (R, '    findgroup  = L["Find Group"],\n', "")]),

    # The eye's tooltip already wraps L["Find Group"], which is translated in all six shipped
    # languages. Inventing a near-miss phrase costs a full EverythingLocales round trip and
    # ships English to every translated client until it lands.
    ("the label is reworded, orphaning the phrase the eye already shares", [
        (R, '    findgroup  = L["Find Group"],',
            '    findgroup  = L["Find a Group"],')]),

    # An empty string is truthy, so UI/RowMenu.lua's `if label then` draws a blank clickable
    # button instead of skipping the item. Aimed at supertrack rather than findgroup, which is
    # already pinned by an exact-string assertion.
    ("a label is emptied, so the menu draws a blank clickable button", [
        (R, '    supertrack = L["Super-track (follow arrow)"],',
            '    supertrack = "",')]),

    # it.label wins over LABELS, so a provider can ship English that no locale gate measures.
    ("the provider supplies its own wording, bypassing LABELS and the locale gate", [
        (Q, Q_GATE, '    if entry.canGroup then menuOut[#menuOut + 1] ='
                    ' { id = "findgroup", order = 55, label = "Find Group" } end')]),

    # ------------------------------------------------- the toggles, which name the wrong verb
    ("the pin gate is inverted, so a pinned quest offers Pin", [
        (Q, '    menuOut[#menuOut + 1] = { id = Filter:IsPinned(entry) and "unpin" or "pin", order = 10 }',
            '    menuOut[#menuOut + 1] = { id = Filter:IsPinned(entry) and "pin" or "unpin", order = 10 }')]),

    ("the track gate is inverted, so a tracked quest offers Track", [
        (Q, '    menuOut[#menuOut + 1] = { id = isWatched(id) and "untrack" or "track",      order = 20 }',
            '    menuOut[#menuOut + 1] = { id = isWatched(id) and "track" or "untrack",      order = 20 }')]),

    ("the focus gate is inverted, so a focused quest offers Focus", [
        (Q, '    menuOut[#menuOut + 1] = { id = isFocused(id) and "unfocus" or "focus",      order = 30 }',
            '    menuOut[#menuOut + 1] = { id = isFocused(id) and "focus" or "unfocus",      order = 30 }')]),

    ("the world quest track gate is inverted", [
        (W, '    menuOut[#menuOut + 1] = { id = tracked and "untrack" or "track", order = 10 }',
            '    menuOut[#menuOut + 1] = { id = tracked and "track" or "untrack", order = 10 }')]),

    # --------------------------------------------- the dispatch, a different function entirely
    ("the track dispatch is inverted, so the Track button untracks the quest", [
        (Q, '    elseif itemID == "track" then\n'
            '        setWatched(entryID, true)\n'
            '    elseif itemID == "untrack" then\n'
            '        setWatched(entryID, false)\n',
            '    elseif itemID == "track" then\n'
            '        setWatched(entryID, false)\n'
            '    elseif itemID == "untrack" then\n'
            '        setWatched(entryID, true)\n')]),

    # A nil watch type IS the automatic watch, which the game evicts, so the row goes missing
    # after a reload rather than immediately.
    ("the world quest watch type is dropped, so Track adds an evictable automatic watch", [
        (W, '            C_QuestLog.AddWorldQuestWatch(entryID, manual)',
            '            C_QuestLog.AddWorldQuestWatch(entryID)')]),

    # ------------------------------------------------------------------ the wipe, done PARTLY
    # Deleting the wipe outright leaves a contiguous table. Leaving one element behind leaves a
    # HOLE, which is what a copy loop indexes into.
    ("the wipe stops one short, leaving a hole rather than a tail", [
        (Q, WIPE, "    for i = #menuOut - 1, 1, -1 do menuOut[i] = nil end\n")]),

    # --------------------------------------------------------------------------- the repaint
    # Both files carry two of these, so the anchors reach back to the branch above to name the
    # one in OnEntryMenuSelect rather than the one in OnEntryClick.
    ("the quest dispatch stops asking for a repaint, so the row keeps the old verb", [
        (Q, '        refused = abandonQuest(entryID)\n'
            '    end\n'
            '    if self._notifyDirty then self._notifyDirty() end\n',
            '        refused = abandonQuest(entryID)\n'
            '    end\n')]),

    ("the same, on the world quest menu", [
        (W, '        self:OnEntryGroupFinder({ id = entryID })\n'
            '    end\n'
            '    if self._notifyDirty then self._notifyDirty() end\n',
            '        self:OnEntryGroupFinder({ id = entryID })\n'
            '    end\n')]),
]

SUMMARY = re.compile(r"^test_row_menu: (\d+) passed, (\d+) failed$")


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
