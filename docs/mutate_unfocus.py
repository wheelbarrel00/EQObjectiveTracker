"""Prove docs/test_unfocus.lua actually discriminates, by breaking production on purpose one
change at a time and checking the harness notices.

    python -B docs/mutate_unfocus.py        (run from the repo root)

Why this exists: Focus newly accepted quests works by hooking two of Blizzard's functions, and
every way it can break is silent. A hook that never goes on leaves the game's focus where it was,
which looks like the option doing nothing. An arm that is never spent, or spent on the wrong
quest, takes back a focus the player chose on the map, which looks like the game losing it. The
world quest row's click toggle fails just as quietly. None of that raises a Lua error.

Every mutation reintroduces a defect the harness is supposed to stand guard over. Any that still
reports "0 failed" is an assertion that does not discriminate, and the run exits 1 naming it. A
mutant marked EQUIVALENT is expected to survive and fails the run if caught.

EQUIVALENT ones left as such: dropping the nil test from onCheck's arm check, since Blizzard
always hands a quest id, so an unarmed check never equals it. Three more are correct rewrites a
fixture once refused (the status call with its method named, a trailing note on a default, the
DB module asked twice), kept so a fixture that rejects good code fails the run.

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
HARNESS = "docs/test_unfocus.lua"

SP = "Data/SuperTrackPersist.lua"
WQ = "Data/Providers/WorldQuests.lua"
DB = "Core/DB.lua"
CMD = "UI/Commands.lua"

GUARD_TOP = ("    if not (type(QuestUtil) == \"table\" and type(QuestUtil.AllowAutoSuperTrackQuest)"
             " == \"function\"\n")
GUARD_CHECK = "            and type(QuestUtil.CheckAutoSuperTrackQuest) == \"function\"\n"
GUARD_CLIENT = ("            and C_SuperTrack.IsSuperTrackingAnything"
                " and C_SuperTrack.GetSuperTrackedQuestID) then\n")
HOOK_ALLOW = "    hooksecurefunc(QuestUtil, \"AllowAutoSuperTrackQuest\", onAllow)\n"
HOOK_CHECK = "    hooksecurefunc(QuestUtil, \"CheckAutoSuperTrackQuest\", onCheck)\n"
ARM = "    if not C_SuperTrack.IsSuperTrackingAnything() then armedFor = questID end\n"
ARM_TEST = "    if was == nil or was ~= questID then return end\n"
WANTED_TEST = "    if focusAcceptedWanted() then return end\n"
FOLLOWED_TEST = "    if C_SuperTrack.GetSuperTrackedQuestID() ~= questID then return end\n"
CLEAR = "    C_SuperTrack.SetSuperTrackedQuestID(0)\n    cleared, lastCleared"
WANTED = "    return not (cfg and cfg.focusAcceptedQuests == false)\n"

WQ_TEST = "        if cfg and cfg.clickToUnfocus == true and C_SuperTrack.GetSuperTrackedQuestID\n"
WQ_FOLLOWED = "           and C_SuperTrack.GetSuperTrackedQuestID() == entry.id then\n"
WQ_CLEAR = "            C_SuperTrack.SetSuperTrackedQuestID(0)\n        else\n"

MUTANTS = [
    # ----------------------------------------------------------------- installing the hooks
    ("enable never hooks, so the option does nothing", [
        (SP, "    hookAutoFocus()\n", "")]),

    ("the hooks go on before the super-track guard, so Classic is hooked too", [
        (SP, "    if not ns.Has.SuperTrack then return end\n    hookAutoFocus()\n",
             "    hookAutoFocus()\n    if not ns.Has.SuperTrack then return end\n")]),

    ("the guard stops asking for QuestUtil, raising on a client without it", [
        (SP, GUARD_TOP, "    if not (type(QuestUtil.AllowAutoSuperTrackQuest) == \"function\"\n")]),

    ("the guard stops asking for Allow, hooking a function that is not there", [
        (SP, GUARD_TOP, "    if not (type(QuestUtil) == \"table\"\n")]),

    ("the guard stops asking for Check, hooking a function that is not there", [
        (SP, GUARD_CHECK, "")]),

    ("the guard stops asking for IsSuperTrackingAnything, which the arm reads", [
        (SP, GUARD_CLIENT, "            and C_SuperTrack.GetSuperTrackedQuestID) then\n")]),

    ("the guard stops asking for GetSuperTrackedQuestID, which the check reads", [
        (SP, GUARD_CLIENT, "            and C_SuperTrack.IsSuperTrackingAnything) then\n")]),

    ("only Check is hooked, so nothing is ever armed", [
        (SP, HOOK_ALLOW, "")]),

    ("only Allow is hooked, so nothing is ever taken back", [
        (SP, HOOK_CHECK, "")]),

    ("the two hooks are swapped", [
        (SP, HOOK_ALLOW, "    hooksecurefunc(QuestUtil, \"AllowAutoSuperTrackQuest\", onCheck)\n"),
        (SP, HOOK_CHECK, "    hooksecurefunc(QuestUtil, \"CheckAutoSuperTrackQuest\", onAllow)\n")]),

    ("the hooks go on but the status line never says so", [
        (SP, "    hooked = true\n", "")]),

    # ------------------------------------------------------------------------ the arm
    ("an arm from an ask with no check is never dropped", [
        (SP, "local function onAllow(questID, forceAllowTasks)\n    armedFor = nil\n",
             "local function onAllow(questID, forceAllowTasks)\n")]),

    ("a world quest pin click arms, so the player's own choice is taken back", [
        (SP, "    if forceAllowTasks then return end\n", "")]),

    ("only a world quest pin click arms", [
        (SP, "    if forceAllowTasks then return end\n", "    if not forceAllowTasks then return end\n")]),

    ("the hook stops reading the forced flag Blizzard hands it", [
        (SP, "local function onAllow(questID, forceAllowTasks)\n", "local function onAllow(questID)\n")]),

    ("the arm is set only while something is focused", [
        (SP, ARM, "    if C_SuperTrack.IsSuperTrackingAnything() then armedFor = questID end\n")]),

    ("every ask arms, so a focus the player chose is taken back", [
        (SP, ARM, "    armedFor = questID\n")]),

    ("a check never spends its arm", [
        (SP, "    local was = armedFor\n    armedFor = nil\n", "    local was = armedFor\n")]),

    ("an arm for one quest is spent on another", [
        (SP, ARM_TEST, "    if was == nil then return end\n")]),

    ("EQUIVALENT: the arm check drops its nil test, which a quest id never equals", [
        (SP, ARM_TEST, "    if was ~= questID then return end\n")]),

    ("the check ignores the arm altogether", [
        (SP, ARM_TEST, "")]),

    # ------------------------------------------------------------------- taking it back
    ("the option is read inverted, so the game's focus is taken back while it is on", [
        (SP, WANTED_TEST, "    if not focusAcceptedWanted() then return end\n")]),

    ("the option is not asked, so every new quest's focus is taken back", [
        (SP, WANTED_TEST, "")]),

    ("a quest the game declined to focus is cleared anyway", [
        (SP, FOLLOWED_TEST, "")]),

    ("the focus is set again on the new quest instead of cleared", [
        (SP, CLEAR, "    C_SuperTrack.SetSuperTrackedQuestID(questID)\n    cleared, lastCleared")]),

    ("the focus is counted as taken back but never cleared", [
        (SP, CLEAR, "    cleared, lastCleared")]),

    ("the option reads another key", [
        (SP, WANTED, "    return not (cfg and cfg.clickToUnfocus == false)\n")]),

    ("an unset option reads off, the opposite of the game", [
        (SP, WANTED, "    return (cfg and cfg.focusAcceptedQuests) == true\n")]),

    ("the option raises with no DB module, inside Blizzard's accept", [
        (SP, "    local cfg = DB and DB:Tracker()\n    return not (cfg and",
             "    local cfg = DB:Tracker()\n    return not (cfg and")]),

    ("the option raises with no saved tracker settings", [
        (SP, WANTED, "    return not (cfg.focusAcceptedQuests == false)\n")]),

    # ------------------------------------------------------------------------- counters
    ("asks are counted only once armed", [
        (SP, "    asked = asked + 1\n" + ARM_TEST, ARM_TEST + "    asked = asked + 1\n")]),

    ("asks are not counted", [
        (SP, "    asked = asked + 1\n", "")]),

    ("asks with nothing focused are counted only when taken back", [
        (SP, "    fromNothing = fromNothing + 1\n" + WANTED_TEST,
             WANTED_TEST + "    fromNothing = fromNothing + 1\n")]),

    ("asks with nothing focused are not counted", [
        (SP, "    fromNothing = fromNothing + 1\n", "")]),

    ("a focus taken back is not counted", [
        (SP, "    cleared, lastCleared = cleared + 1, questID\n", "    lastCleared = questID\n")]),

    ("the last quest taken back is not kept", [
        (SP, "    cleared, lastCleared = cleared + 1, questID\n", "    cleared = cleared + 1\n")]),

    # ----------------------------------------------------------------------- status line
    ("the status line prints on Classic too", [
        (SP, "    if not ns.Has.SuperTrack then return nil end\n", "")]),

    ("the status line raises with no saved tracker settings", [
        (SP, "    local cfg = (DB and DB:Tracker()) or {}\n", "    local cfg = DB and DB:Tracker()\n")]),

    ("the status line raises with no DB module", [
        (SP, "    local cfg = (DB and DB:Tracker()) or {}\n", "    local cfg = DB:Tracker() or {}\n")]),

    ("the status line reads the click option the wrong way round", [
        (SP, "        cfg.clickToUnfocus == true and \"unfocuses it\" or \"keeps it\",\n",
             "        cfg.clickToUnfocus == true and \"keeps it\" or \"unfocuses it\",\n")]),

    ("the status line reads the accept option the wrong way round", [
        (SP, "        focusAcceptedWanted() and \"focused\" or \"left unfocused\",\n",
             "        focusAcceptedWanted() and \"left unfocused\" or \"focused\",\n")]),

    ("the status line always says hooked", [
        (SP, "        hooked and \"hooked\" or \"NOT HOOKED\",\n", "        \"hooked\",\n")]),

    ("the status line swaps the asks and the asks with nothing focused", [
        (SP, "        asked, fromNothing, cleared, tostring(lastCleared))\n",
             "        fromNothing, asked, cleared, tostring(lastCleared))\n")]),

    # -------------------------------------------------------------------- the login restore
    ("a reload clears the focus too", [
        (SP, "        if not isInitialLogin then return end\n", "")]),

    ("Keep focused quest after relog is ignored", [
        (SP, "        if shouldRestore() then return end\n", "")]),

    ("Keep focused quest after relog is read inverted", [
        (SP, "    return (gen and gen.restoreSuperTrackOnLogin) == true\n",
             "    return (gen and gen.restoreSuperTrackOnLogin) ~= true\n")]),

    ("the login clear waits a different time", [
        (SP, "local CLEAR_DELAY = 0.5\n", "local CLEAR_DELAY = 0.25\n")]),

    ("the login clear sets a quest instead of clearing", [
        (SP, "            C_SuperTrack.SetSuperTrackedQuestID(0)\n        end)\n",
             "            C_SuperTrack.SetSuperTrackedQuestID(1)\n        end)\n")]),

    # --------------------------------------------------------------- the world quest click
    ("the world quest click sets a focus on a client with no super-track", [
        (WQ, "    if ns.Has.SuperTrack then\n        local DB  = ns:GetModule(\"DB\")\n",
             "    if true then\n        local DB  = ns:GetModule(\"DB\")\n")]),

    ("the world quest click ignores the option", [
        (WQ, WQ_TEST, "        if false and C_SuperTrack.GetSuperTrackedQuestID\n")]),

    ("the world quest click reads the option inverted", [
        (WQ, WQ_TEST, "        if cfg and cfg.clickToUnfocus ~= true and C_SuperTrack.GetSuperTrackedQuestID\n")]),

    ("the world quest click reads another key", [
        (WQ, WQ_TEST, "        if cfg and cfg.splitQuestClick == true and C_SuperTrack.GetSuperTrackedQuestID\n")]),

    ("the world quest click unfocuses whatever was clicked", [
        (WQ, WQ_FOLLOWED, "           then\n")]),

    ("the world quest click compares the followed quest with the entry table", [
        (WQ, WQ_FOLLOWED, "           and C_SuperTrack.GetSuperTrackedQuestID() == entry then\n")]),

    ("the world quest click raises on a client with no super-track getter", [
        (WQ, WQ_TEST, "        if cfg and cfg.clickToUnfocus == true\n")]),

    ("the world quest click raises with no saved tracker settings", [
        (WQ, WQ_TEST, "        if cfg.clickToUnfocus == true and C_SuperTrack.GetSuperTrackedQuestID\n")]),

    ("the world quest click raises with no DB module", [
        (WQ, "        local cfg = DB and DB:Tracker()\n" + WQ_TEST, "        local cfg = DB:Tracker()\n" + WQ_TEST)]),

    ("the world quest click sets the quest again instead of clearing", [
        (WQ, WQ_CLEAR, "            C_SuperTrack.SetSuperTrackedQuestID(entry.id)\n        else\n")]),

    ("the world quest unfocus skips the repaint", [
        (WQ, WQ_CLEAR, "            C_SuperTrack.SetSuperTrackedQuestID(0)\n            return\n        else\n")]),

    # ------------------------------------------------------------------------------ seams
    ("Click a focused quest to unfocus it defaults on", [
        (DB, "            clickToUnfocus       = false,\n", "            clickToUnfocus       = true,\n")]),

    ("Focus newly accepted quests defaults off", [
        (DB, "            focusAcceptedQuests  = true,\n", "            focusAcceptedQuests  = false,\n")]),

    ("Focus newly accepted quests gets its default in the general block", [
        (DB, "            focusAcceptedQuests  = true,\n", ""),
        (DB, "            useBlizzardTracker = false,\n",
             "            useBlizzardTracker = false,\n            focusAcceptedQuests  = true,\n")]),

    ("/eqot status never prints the focus line", [
        (CMD, "    debugLine(\"SuperTrackPersist\")\n", "")]),

    ("/eqot status has the focus line commented out", [
        (CMD, "    debugLine(\"SuperTrackPersist\")\n", "    -- debugLine(\"SuperTrackPersist\")\n")]),

    ("/eqot status prints the focus line at the very end, away from auto-track", [
        (CMD, "    debugLine(\"SuperTrackPersist\")\n", ""),
        (CMD, "    debugLine(\"QuestGroups\")\n",
              "    debugLine(\"QuestGroups\")\n    debugLine(\"SuperTrackPersist\")\n")]),

    # ------------------------------------------- found by the pre-release scan's hand-breaks
    # A dot call hands DB:Tracker no self, a Lua error in game that a stub ignoring self passes.
    ("the world quest click calls DB.Tracker with a dot", [
        (WQ, "        local cfg = DB and DB:Tracker()\n" + WQ_TEST,
             "        local cfg = DB and DB.Tracker()\n" + WQ_TEST)]),

    ("the accept option calls DB.Tracker with a dot", [
        (SP, "    local cfg = DB and DB:Tracker()\n    return not (cfg and",
             "    local cfg = DB and DB.Tracker()\n    return not (cfg and")]),

    ("the status line calls DB.Tracker with a dot", [
        (SP, "    local cfg = (DB and DB:Tracker()) or {}\n", "    local cfg = (DB and DB.Tracker()) or {}\n")]),

    ("the world quest click also unfocuses for Split quest click", [
        (WQ, WQ_TEST, "        if cfg and (cfg.clickToUnfocus == true or cfg.splitQuestClick == true)"
                      " and C_SuperTrack.GetSuperTrackedQuestID\n")]),

    ("the accept option also reads off while General's Auto track accepted quests is off", [
        (SP, WANTED, "    local gen = DB and DB:General()\n"
                     "    return not (cfg and cfg.focusAcceptedQuests == false)"
                     " and not (gen and gen.autoTrackAccepted == false)\n")]),

    ("the accept option also reads off when the click option is on", [
        (SP, WANTED, "    return not (cfg and (cfg.focusAcceptedQuests == false or cfg.clickToUnfocus == true))\n")]),

    ("the status line's click field also says unfocuses for Split quest click", [
        (SP, "        cfg.clickToUnfocus == true and \"unfocuses it\" or \"keeps it\",\n",
             "        (cfg.clickToUnfocus == true or cfg.splitQuestClick == true) and \"unfocuses it\" or \"keeps it\",\n")]),

    ("a followed bonus objective can never be unfocused", [
        (WQ, WQ_FOLLOWED, "           and C_SuperTrack.GetSuperTrackedQuestID() == entry.id"
                          " and entry.groupID ~= \"bonusobjectives\" then\n")]),

    ("a stale entry still marked focused is cleared, dropping another quest's focus", [
        (WQ, WQ_FOLLOWED, "           and (entry.isFocused or C_SuperTrack.GetSuperTrackedQuestID() == entry.id) then\n")]),

    ("the world quest click runs on Classic, where super-track reads false", [
        (WQ, "    if ns.Has.SuperTrack then\n        local DB  = ns:GetModule(\"DB\")\n",
             "    if ns.Has.SuperTrack ~= nil then\n        local DB  = ns:GetModule(\"DB\")\n")]),

    ("enable hooks on Classic, where super-track reads false", [
        (SP, "    if not ns.Has.SuperTrack then return end\n", "    if ns.Has.SuperTrack == nil then return end\n")]),

    ("the status line prints on Classic, where super-track reads false", [
        (SP, "    if not ns.Has.SuperTrack then return nil end\n", "    if ns.Has.SuperTrack == nil then return nil end\n")]),

    ("a repeatable quest accepted again keeps the game's focus", [
        (SP, FOLLOWED_TEST, "    if lastCleared == questID then return end\n" + FOLLOWED_TEST)]),

    ("every loading screen hooks the pair again", [
        (SP, "    Events:On(\"PLAYER_ENTERING_WORLD\", function(_, isInitialLogin)\n",
             "    Events:On(\"PLAYER_ENTERING_WORLD\", function(_, isInitialLogin)\n        hookAutoFocus()\n")]),

    ("a fresh login hooks the pair again", [
        (SP, "        if not isInitialLogin then return end\n",
             "        if not isInitialLogin then return end\n        hookAutoFocus()\n")]),

    ("a fresh login without Keep focused quest hooks the pair again", [
        (SP, "        if shouldRestore() then return end\n",
             "        if shouldRestore() then return end\n        hookAutoFocus()\n")]),

    ("the arm reads the followed quest, so a followed map pin arms", [
        (SP, ARM, "    if C_SuperTrack.GetSuperTrackedQuestID() == 0 then armedFor = questID end\n")]),

    ("/eqot status prints the focus line twice, the second with a prefix", [
        (CMD, "    debugLine(\"SuperTrackPersist\")\n",
              "    debugLine(\"SuperTrackPersist\")\n    debugLine(\"SuperTrackPersist\", \"  \")\n")]),

    ("Click a focused quest to unfocus it gets its default in the char block", [
        (DB, "            clickToUnfocus       = false,\n", ""),
        (DB, "        trackedWorldQuests = {},\n",
             "        trackedWorldQuests = {},\n            clickToUnfocus       = false,\n")]),

    ("Focus newly accepted quests gets its default in the char block", [
        (DB, "            focusAcceptedQuests  = true,\n", ""),
        (DB, "        trackedWorldQuests = {},\n",
             "        trackedWorldQuests = {},\n            focusAcceptedQuests  = true,\n")]),

    # ------------------------------------------ found by the 2.2.0 fix pass's second scan
    ("a forced ask returns before it drops a stale arm, so a pin click after a stray ask is taken back", [
        (SP, "local function onAllow(questID, forceAllowTasks)\n    armedFor = nil\n",
             "local function onAllow(questID, forceAllowTasks)\n"),
        (SP, "    if forceAllowTasks then return end\n",
             "    if forceAllowTasks then return end\n    armedFor = nil\n")]),

    ("a check spends its arm only when the quest matches, so a stray arm outlives a mismatched check", [
        (SP, "    local was = armedFor\n    armedFor = nil\n    asked = asked + 1\n" + ARM_TEST,
             "    local was = armedFor\n    asked = asked + 1\n" + ARM_TEST + "    armedFor = nil\n")]),

    ("the 'with nothing focused' count is taken at the arm, not at the check", [
        (SP, ARM, "    if not C_SuperTrack.IsSuperTrackingAnything() then"
                  " armedFor = questID; fromNothing = fromNothing + 1 end\n"),
        (SP, "    fromNothing = fromNothing + 1\n" + WANTED_TEST, WANTED_TEST)]),

    ("the login clear is decided at the loading screen, only when a quest is followed then", [
        (SP, "        C_Timer.After(CLEAR_DELAY, function()\n",
             "        if C_SuperTrack.GetSuperTrackedQuestID() == 0 then return end\n"
             "        C_Timer.After(CLEAR_DELAY, function()\n")]),

    ("the accept option also reads off while Keep focused quest after relog is off", [
        (SP, WANTED, "    local gen = DB and DB:General()\n"
                     "    return not (cfg and cfg.focusAcceptedQuests == false)"
                     " and not (gen and gen.restoreSuperTrackOnLogin == false)\n")]),

    ("the accept option also reads off while Keep the focused quest solid is off", [
        (SP, WANTED, "    return not (cfg and (cfg.focusAcceptedQuests == false or cfg.trackerAlphaFocus == false))\n")]),

    ("a completed world quest is never unfocused", [
        (WQ, WQ_TEST, "        if cfg and cfg.clickToUnfocus == true and entry.state ~= \"complete\""
                      " and C_SuperTrack.GetSuperTrackedQuestID\n")]),

    ("only an entry tagged worldquest unfocuses, so a real bonus objective never does", [
        (WQ, WQ_TEST, "        if cfg and cfg.clickToUnfocus == true and entry.tags.worldquest"
                      " and C_SuperTrack.GetSuperTrackedQuestID\n")]),

    ("a world quest with a countdown is never unfocused", [
        (WQ, WQ_TEST, "        if cfg and cfg.clickToUnfocus == true and not entry.expiresAt"
                      " and C_SuperTrack.GetSuperTrackedQuestID\n")]),

    ("the world quest click unfocuses only while Keep the focused quest solid is on", [
        (WQ, WQ_TEST, "        if cfg and cfg.clickToUnfocus == true and cfg.trackerAlphaFocus ~= false"
                      " and C_SuperTrack.GetSuperTrackedQuestID\n")]),

    # Correct rewrites the fixtures once refused. Caught here is a fixture rejecting good code.
    ("EQUIVALENT: /eqot status names the focus line's method explicitly, the same call", [
        (CMD, "    debugLine(\"SuperTrackPersist\")\n",
              "    debugLine(\"SuperTrackPersist\", nil, \"DebugLine\")\n")]),

    ("EQUIVALENT: the accept default carries a trailing note", [
        (DB, "            focusAcceptedQuests  = true,\n",
             "            focusAcceptedQuests  = true, -- the game's own behavior\n")]),

    ("EQUIVALENT: the world quest click asks for the DB module twice rather than through a local", [
        (WQ, "        local DB  = ns:GetModule(\"DB\")\n        local cfg = DB and DB:Tracker()\n" + WQ_TEST,
             "        local cfg = ns:GetModule(\"DB\") and ns:GetModule(\"DB\"):Tracker()\n" + WQ_TEST)]),
]

SUMMARY = re.compile(r"^test_unfocus: (\d+) passed, (\d+) failed$")


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
        # Asserted rather than assumed. Applying a mutant to a file that still holds the last
        # one is a silent no-op, and the run then reports the PREVIOUS mutant's result under
        # this mutant's name.
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
        print("equivalent %-73s %s" % (name, last))
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
