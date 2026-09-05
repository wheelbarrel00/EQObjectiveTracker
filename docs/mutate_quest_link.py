"""Prove docs/test_quest_link.lua actually discriminates, by breaking production on purpose one
change at a time and checking the harness notices.

    python docs/mutate_quest_link.py        (run from the repo root)

Why this exists: the gesture this replaces was shift-click-to-HIDE, which removed a quest from
the tracker per character with no undo but a slash command nobody knew about. A user shift-
clicked three quests trying to link them into chat and reported all three as lost. Nothing
raised, nothing was logged, and every gate in this project was green throughout. The mutants
below put the shape of that back: a modifier branch that fires when it should not, and a refusal
that answers true and swallows the row's ordinary click.

Two files, because the feature is three parts - the link string in Data/QuestLink.lua, the
click that inserts it and the click that untracks when no chat box is open, both in
UI/Row.lua - and one harness covers all three.

Every mutation reintroduces a defect the harness is supposed to stand guard over. Any that still
reports "0 failed" is an assertion that does not discriminate, and the run exits 1 naming it.

WRITES TO THE TREE. It edits in place and restores through a finally, so an interrupted run
still puts the files back, and it verifies the restore and re-checks the baseline before
reporting. If you hard-kill it anyway, recover from your editor's undo history, NOT with git -
these files are uncommitted while they are being worked on.

Anchors are exact source text and they rot. A SKIPPED line means an anchor stopped matching:
fix the anchor rather than dropping the mutant.
"""
import io
import re
import subprocess
import sys

LUA = r"C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe"
HARNESS = "docs/test_quest_link.lua"

SRC = "Data/QuestLink.lua"
ROW = "UI/Row.lua"

MUTANTS = [
    # ------------------------------------------------- the deletion this release exists for
    ("the hide gesture's WRITER comes back to Data/Filter.lua", [
        ("Data/Filter.lua", "function Filter:IsPinned(entry)",
            "function Filter:SetHidden(entry, hidden)\n"
            "    local c = ns:GetModule(\"DB\"):Char()\n"
            "    if not c then return end\n"
            "    c.hidden = c.hidden or {}\n"
            "    c.hidden[entry.id] = hidden or nil\n"
            "end\n\n"
            "function Filter:IsPinned(entry)")]),

    ("the link asks the registry for a hardcoded provider rather than the row's own", [
        (ROW,
         '    local provider = row._providerID and ns:GetModule("Registry"):Get(row._providerID)\n'
         '    if not (provider and provider.idSpace == "quest") then return false end',
         '    local provider = ns:GetModule("Registry"):Get("quests")\n'
         '    if not (provider and provider.idSpace == "quest") then return false end')]),

    ("the untrack asks the registry for a hardcoded provider rather than the row's own", [
        (ROW,
         '    local provider = row._providerID and ns:GetModule("Registry"):Get(row._providerID)\n'
         '    if not (provider and provider.GetEntryMenu and provider.OnEntryMenuSelect) then return false end',
         '    local provider = ns:GetModule("Registry"):Get("quests")\n'
         '    if not (provider and provider.GetEntryMenu and provider.OnEntryMenuSelect) then return false end')]),

    # ------------------------------------------------- Data/QuestLink.lua, the string
    ("Classic reaches for the client's own link", [
        (SRC, "    if ns.Has.QuestLog and ns.Has.QuestLink then",
              "    if ns.Has.QuestLink then")]),

    ("the Has.QuestLink probe is dropped, so a client without the API is still asked", [
        (SRC, "    if ns.Has.QuestLog and ns.Has.QuestLink then",
              "    if ns.Has.QuestLog then")]),

    ("a hollow client answer is taken as a link", [
        (SRC, '        if ok and type(link) == "string" and link:find("|Hquest:", 1, true) then',
              '        if ok and type(link) == "string" then')]),

    ("a raising client call is not caught", [
        (SRC, "        local ok, link = pcall(GetQuestLink, questID)",
              "        local ok, link = true, GetQuestLink(questID)")]),

    ("there is no plain-text fallback, so an unresolvable quest shares nothing", [
        (SRC, "    return plain(questID, title, level)", "    return nil")]),

    ("the level is dropped from the plain-text form", [
        (SRC, """    if type(level) == "number" and level > 0 then
        return ("[[%d] %s (%d)]"):format(level, title, questID)
    end""",
              "    -- no level form")]),

    ("level 0 is treated as a real level", [
        (SRC, '    if type(level) == "number" and level > 0 then',
              '    if type(level) == "number" then')]),

    ("an empty title still shares, as a bare id nobody can read", [
        (SRC, '    if type(title) ~= "string" or title == "" then return nil end',
              '    if type(title) ~= "string" then return nil end')]),

    ("a nil quest id is shared", [
        (SRC, '    if type(questID) ~= "number" or questID <= 0 then return nil end',
              "    if false then return nil end")]),

    # ------------------------------------------------- UI/Row.lua, the click
    ("the modifier is not checked, so every left-click links", [
        (ROW, '    if not (IsModifiedClick and IsModifiedClick("CHATLINK")) then return false end',
              "    -- unchecked")]),

    ("the OLD destructive modifier is what the gesture reads", [
        (ROW, '    if not (IsModifiedClick and IsModifiedClick("CHATLINK")) then return false end',
              '    if not (IsModifiedClick and IsModifiedClick("QUESTWATCHTOGGLE")) then return false end')]),

    ("the focused chat box is not required, so shift-click eats the row's normal click", [
        (ROW, "    if not (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()) then return false end",
              "    -- unchecked")]),

    ("any provider links, not only the ones whose ids ARE quest ids", [
        (ROW, '    if not (provider and provider.idSpace == "quest") then return false end',
              "    if not provider then return false end")]),

    ("a row with no resolvable link swallows the click anyway", [
        (ROW, "    if not text then return false end", "    if not text then return true end")]),

    ("an edit box that refuses the insert is reported as a successful link", [
        (ROW, "    return (ChatEdit_InsertLink and ChatEdit_InsertLink(text)) and true or false",
              "    if ChatEdit_InsertLink then ChatEdit_InsertLink(text) end\n    return true")]),

    ("the title is shared as the level, so every link reads wrong", [
        (ROW, "    local text  = ns:GetModule(\"QuestLink\"):For(entry.id, entry.title, entry.level)",
              "    local text  = ns:GetModule(\"QuestLink\"):For(entry.id, entry.title, entry.title)")]),

    # ----------------------------------------------- added 2026-09-02 by the scan
    ("the ChatEdit_GetActiveWindow presence guard is dropped", [
        (ROW, "    if not (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()) then return false end",
              "    if not ChatEdit_GetActiveWindow() then return false end")]),

    # onMouseUp's ORDER, which the slice cannot reach and which this session's own fix moved.
    ("the link branch is moved BELOW split-click, so a split-click row never links", [
        (ROW, """    if chatLinkClick(row) then return end
    if button == "LeftButton" and untrackClick(row) then return end

    if button == "LeftButton" and splitClickWanted(row) and not overIcon(row) then
        dispatch(row, "OnEntryOpenLog")
        return
    end""",
              """    if button == "LeftButton" and untrackClick(row) then return end

    if button == "LeftButton" and splitClickWanted(row) and not overIcon(row) then
        dispatch(row, "OnEntryOpenLog")
        return
    end

    if chatLinkClick(row) then return end""")]),

    # The untrack asked FIRST is the one that matters most: with both bound to shift by default,
    # it would untrack the quest the player was trying to link.
    ("the untrack branch is asked BEFORE the link", [
        (ROW, """    if chatLinkClick(row) then return end
    if button == "LeftButton" and untrackClick(row) then return end""",
              """    if button == "LeftButton" and untrackClick(row) then return end
    if chatLinkClick(row) then return end""")]),

    ("the untrack loses its LeftButton gate, so shift+right-click stops opening the row menu", [
        (ROW, '    if button == "LeftButton" and untrackClick(row) then return end',
              "    if untrackClick(row) then return end")]),

    ("the link is gated on LeftButton again, so shift+right-click stops linking", [
        (ROW, "    if chatLinkClick(row) then return end",
              '    if button == "LeftButton" and chatLinkClick(row) then return end')]),

    # ------------------------------------------------- UI/Row.lua, the untrack half
    # This is the branch that changes state, so its refusals are the ones worth breaking. The
    # first mutant is the shape of the original defect wearing the new gesture: a modified click
    # reaching a state change while the player was doing something else with the modifier.
    ("the untrack fires with a chat box open, so a link that will not resolve untracks instead", [
        (ROW, "    if ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() then return false end",
              "    -- unchecked")]),

    ("the modifier is not checked, so every left-click untracks", [
        (ROW, '    if not ((IsModifiedClick and IsModifiedClick("QUESTWATCHTOGGLE"))\n'
              "            or (IsShiftKeyDown and IsShiftKeyDown())) then return false end",
              "    -- unchecked")]),

    ("the shift fallback is dropped, so a client that does not know the binding loses the gesture", [
        (ROW, '    if not ((IsModifiedClick and IsModifiedClick("QUESTWATCHTOGGLE"))\n'
              "            or (IsShiftKeyDown and IsShiftKeyDown())) then return false end",
              '    if not (IsModifiedClick and IsModifiedClick("QUESTWATCHTOGGLE")) then return false end')]),

    ("the explicit binding is dropped, so a rebound modifier stops untracking", [
        (ROW, '    if not ((IsModifiedClick and IsModifiedClick("QUESTWATCHTOGGLE"))\n'
              "            or (IsShiftKeyDown and IsShiftKeyDown())) then return false end",
              "    if not (IsShiftKeyDown and IsShiftKeyDown()) then return false end")]),

    ("the provider is not asked whether it can be told, so a menu-only provider raises", [
        (ROW, "    if not (provider and provider.GetEntryMenu and provider.OnEntryMenuSelect) then return false end",
              "    if not (provider and provider.GetEntryMenu) then return false end")]),

    ("a nil menu is walked anyway", [
        (ROW, "    if not items then return false end", "    -- unchecked")]),

    ("the menu is not consulted, so a quest that is already untracked is untracked again", [
        (ROW, "    local offered = false", "    local offered = true")]),

    ("a row the gesture cannot act on swallows the click anyway", [
        (ROW, "    if not offered then return false end", "    if not offered then return true end")]),

    ("the entry table is dispatched rather than its id", [
        (ROW, "    provider:OnEntryMenuSelect(entry.id, UNTRACK_ITEM)",
              "    provider:OnEntryMenuSelect(entry, UNTRACK_ITEM)")]),

    ("the wrong menu item is dispatched, so the gesture re-tracks instead", [
        (ROW, "    provider:OnEntryMenuSelect(entry.id, UNTRACK_ITEM)",
              '    provider:OnEntryMenuSelect(entry.id, "track")')]),

    ("the tracker is never asked to repaint, so the row sits there until the next quest event", [
        (ROW, '    local Tracker = ns:GetModule("Tracker")\n'
              "    if Tracker then Tracker:Refresh() end",
              "    -- no repaint")]),
]

SUMMARY = re.compile(r"^test_quest_link: (\d+) passed, (\d+) failed$")


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
