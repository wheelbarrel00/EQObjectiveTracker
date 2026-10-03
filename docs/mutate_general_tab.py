"""Prove docs/test_general_tab.lua actually discriminates, by breaking production on purpose one
change at a time and checking the harness notices.

    python docs/mutate_general_tab.py        (run from the repo root)

Why this exists: apart from the Use Blizzard's quest tracker box, nothing on the General tab was
driven by any harness. Every control here hands its value to one call in another module, and
every way of losing that call is silent: a reset that reloads without resetting, a lock that is
stored and never applied, a profile created from defaults instead of a copy, a name taken
without asking.

Every mutation reintroduces a defect the harness is supposed to stand guard over. Any that still
reports "0 failed" is an assertion that does not discriminate, and the run exits 1 naming it.

WRITES TO THE TREE. It edits in place and restores through a finally, so an interrupted run
still puts the file back, and it verifies the restore and re-checks the baseline before
reporting. This checkout is junctioned into AddOns, so run it from a scratch copy while the game
is open.

Anchors are exact source text and they rot. A SKIPPED line means an anchor stopped matching:
fix the anchor rather than dropping the mutant.
"""
import io
import re
import subprocess
import sys

LUA = r"C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe"
HARNESS = "docs/test_general_tab.lua"

G = "Options/TabGeneral.lua"

RESET_ALL_ASK = ('            Dialog:Show({\n                title    = "EQ Objective Tracker",\n'
                 '                text     = L["Reset every EQ Objective Tracker setting to defaults? The interface will reload."],')

MUTANTS = [
    # ------------------------------------------------------------------- the footer
    ("Reset all settings reloads without resetting anything", [
        (G, "                    DB:ResetAll()\n", "")]),

    ("Reset all settings leaves the live tracker where it was", [
        (G, '                    ns:GetModule("Tracker"):ResetPosition()\n                    ReloadUI()\n',
            "                    ReloadUI()\n")]),

    ("Reset all settings resets before asking", [
        (G, RESET_ALL_ASK, "            DB:ResetAll()\n" + RESET_ALL_ASK)]),

    ("Reset position and size does nothing", [
        (G, '        local resetPos = self:CreateButton(bar, L["Reset position and size"], nil, function()\n'
            '            ns:GetModule("Tracker"):ResetPosition()\n',
            '        local resetPos = self:CreateButton(bar, L["Reset position and size"], nil, function()\n')]),

    ("Reset position and size reloads the interface", [
        (G, '            ns:GetModule("Tracker"):ResetPosition()\n        end, L["Returns the tracker to its default position and size."])',
            '            ns:GetModule("Tracker"):ResetPosition()\n            ReloadUI()\n        end, L["Returns the tracker to its default position and size."])')]),

    # ------------------------------------------------------------------- the General card
    ("Lock tracker is stored but never applied", [
        (G, '                ns:GetModule("Tracker"):ApplyLockState()\n', "")]),

    ("Lock tracker always stores locked", [
        (G, "                DB:General().lockTracker = v\n", "                DB:General().lockTracker = true\n")]),

    ("a hide rule is stored but the visibility rules never run again", [
        (G, '                    DB:General()[key] = v\n                    ns:GetModule("Visibility"):Apply()\n',
            "                    DB:General()[key] = v\n")]),

    ("a hide rule always stores on", [
        (G, "                    DB:General()[key] = v\n", "                    DB:General()[key] = true\n")]),

    ("Hide tracker in combat writes the instance key", [
        (G, '        hideRule("hideInCombat", L["Hide tracker in combat"],',
            '        hideRule("hideInInstances", L["Hide tracker in combat"],')]),

    ("the Mythic+ box shows on a client with no Mythic+", [
        (G, "        if ns.Has.MythicPlus then", "        if true then")]),

    ("Auto-track writes nothing", [
        (G, "            function(v) DB:General().autoTrackAccepted = v end,", "            function() end,")]),

    ("Auto-track reads off while unset", [
        (G, "            function() return DB:General().autoTrackAccepted ~= false end,",
            "            function() return DB:General().autoTrackAccepted == true end,")]),

    ("Keep focused quest after relog writes nothing", [
        (G, "            function(v) DB:General().restoreSuperTrackOnLogin = v end,", "            function() end,")]),

    # ------------------------------------------------------------------- the window scale
    ("letting go of the scale slider never resizes the window", [
        (G, '            owScale.slider:HookScript("OnMouseUp", function() Options:ApplyWindowScale() end)',
            '            owScale.slider:HookScript("OnMouseUp", function() end)')]),

    ("the window is resized on every step of a drag", [
        (G, '                if g and type(v) == "number" and v > 0 then g.optionsWindowScale = v end\n',
            '                if g and type(v) == "number" and v > 0 then g.optionsWindowScale = v end\n'
            '                Options:ApplyWindowScale()\n')]),

    ("a zero window scale is stored", [
        (G, 'type(v) == "number" and v > 0 then g.optionsWindowScale = v end',
            'type(v) == "number" and v >= 0 then g.optionsWindowScale = v end')]),

    # ------------------------------------------------------------------- the profiles
    ("the profile list keeps AceDB's arbitrary order", [
        (G, "            table.sort(names)\n", "")]),

    ("switching profile never reloads, so the migrations never run", [
        (G, "            DB.db:SetProfile(name)\n            ReloadUI()\n        end\n\n        local function createProfileCopiedFromCurrent",
            "            DB.db:SetProfile(name)\n        end\n\n        local function createProfileCopiedFromCurrent")]),

    ("New Profile does nothing", [
        (G, "            function() promptForName() end,", "            function() end,")]),

    ("an empty name is accepted", [
        (G, '                    if name == "" then return promptForName(text) end\n', "")]),

    ("asking again loses what was typed", [
        (G, '                    if name == "" then return promptForName(text) end',
            '                    if name == "" then return promptForName() end')]),

    ("the name is not trimmed", [
        (G, '                    local name = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")',
            '                    local name = text or ""')]),

    ("a name already taken is overwritten without asking", [
        (G, "                    if name ~= currentProfile() and profileExists(name) then",
            "                    if false then")]),

    ("the current profile's own name asks to overwrite itself", [
        (G, "                    if name ~= currentProfile() and profileExists(name) then",
            "                    if profileExists(name) then")]),

    ("Overwrite does nothing", [
        (G, "                            onAccept = function() createProfileCopiedFromCurrent(name) end,",
            "                            onAccept = function() end,")]),

    ("a new profile starts from defaults instead of a copy", [
        (G, "                DB.db:CopyProfile(source, true)\n", "")]),

    ("a profile is copied onto itself", [
        (G, "            if source and source ~= name and DB.db.CopyProfile then",
            "            if source and DB.db.CopyProfile then")]),

    ("a new profile is created without a reload", [
        (G, "                DB.db:CopyProfile(source, true)\n            end\n            ReloadUI()\n",
            "                DB.db:CopyProfile(source, true)\n            end\n")]),

    ("the name field has no limit", [
        (G, "                maxLetters  = 32,", "                maxLetters  = 0,")]),
    # Hide Questie's quest tracker, offered only beside Questie.
    ("the Questie box is offered without Questie", [
        (G, "        if Coexist and Coexist:QuestiePresent() then", "        if Coexist then")]),

    ("the Questie box stores nothing", [
        (G, "                    DB:General().hideQuestieTracker = v\n", "")]),

    ("ticking the Questie box never hides Questie's tracker", [
        (G, "                        if Q then Q:Apply() end\n", "")]),

    ("ticking the Questie box also shows Questie's tracker", [
        (G, "                        if Q then Q:Apply() end\n                        return\n",
            "                        if Q then Q:Apply() end\n")]),

    ("unticking shows Questie's tracker even while Questie has it off", [
        (G, '                    if wanted and type(f) == "table" and type(f.Show) == "function" then',
            '                    if type(f) == "table" and type(f.Show) == "function" then')]),

    ("an unset Questie setting reads as off", [
        (G, "                                   or q.db.profile.trackerEnabled ~= false",
            "                                   or q.db.profile.trackerEnabled == true")]),

    ("unticking with no Questie frame raises", [
        (G, '                    if wanted and type(f) == "table" and type(f.Show) == "function" then',
            "                    if wanted then")]),

    # The window scale slider reading back what it stored.
    ("the scale slider always reads 1", [
        (G, "            function() return (DB:Global() and DB:Global().optionsWindowScale) or 1.0 end,",
            "            function() return 1.0 end,")]),

    ("the scale slider raises before the DB is ready", [
        (G, "            function() return (DB:Global() and DB:Global().optionsWindowScale) or 1.0 end,",
            "            function() return DB:Global().optionsWindowScale or 1.0 end,")]),

    ("a scale drag raises before the DB is ready", [
        (G, '                if g and type(v) == "number" and v > 0 then g.optionsWindowScale = v end\n',
            '                if type(v) == "number" and v > 0 then g.optionsWindowScale = v end\n')]),

    # Words a literal would leave in English.
    ("Reset all settings' button is hard-coded in English", [
        (G, '                button1  = L["Reset"],', '                button1  = "Reset",')]),

    ("Lock tracker is labeled in English", [
        (G, '        local lock = self:CreateCheckbox(content, L["Lock tracker"],',
            '        local lock = self:CreateCheckbox(content, "Lock tracker",')]),

    ("the overwrite question is titled in English", [
        (G, '                            title    = L["Overwrite profile?"],',
            '                            title    = "Overwrite profile?",')]),
]

SUMMARY = re.compile(r"^test_general_tab: (\d+) passed, (\d+) failed$")


def run():
    """(verdict, note). verdict is "green", "failed" or "crashed".

    A nonzero exit is NOT evidence that an assertion discriminated - a mutant that does not parse
    exits nonzero too - so the harness's own summary line is matched rather than its exit code,
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
        # Asserted rather than assumed: applying a mutant to a file that still holds the last one
        # is a silent no-op, and the run would report the previous mutant's result under this name.
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
    # Three different verdicts, never pooled. A SKIPPED anchor reported as a survivor sends the
    # reader hunting a coverage hole that is not there, and a CRASHED one hides an abort.
    for kind, label in (
            ("SURVIVED", "mutant(s) survived - those assertions do not discriminate"),
            ("CRASHED",  "mutant(s) aborted the harness rather than failing it"),
            ("SKIPPED",  "anchor(s) rotted - fix the anchor, never drop the mutant")):
        named = [name for verdict, name in failures if verdict == kind]
        if named:
            print("%d %s:" % (len(named), label))
            for name in named:
                print("  - " + name)
    sys.exit(1)
print("every mutant behaved as expected")
