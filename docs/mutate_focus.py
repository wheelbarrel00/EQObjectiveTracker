"""Prove docs/test_focus.lua actually discriminates, by breaking production on purpose one change
at a time and checking the harness notices.

    python -B docs/mutate_focus.py        (run from the repo root)

Why this exists: on WoW Forever, Data/Focus.lua follows super-track and announces it, and
Everything Quests turns that announcement into a TomTom arrow. Most ways it can fail are silent.
No arrow appears, and nothing says whether EQOT stopped announcing or something after it stopped
drawing. The Classic half of the file had no harness before this one either, so its Set and
Toggle contract and Core/API.lua's listener list are broken here too.

THE MUTANT THAT EARNS IT is the read at enable. Everything Quests registers its listener after
EQOT's modules enable, and Set is silent on an unchanged focus, so a read there stores the
login's quest where nobody hears it and the first loading screen then announces nothing.

The pre-ship scan of 2026-09-29 hand-broke the first version of this pair 50 ways and 30
survived. The mutants under "found by the scan" are those survivors, kept so they stay caught.

Every mutation reintroduces a defect the harness is supposed to stand guard over. Any that still
reports "0 failed" is an assertion that does not discriminate, and the run exits 1 naming it.

WRITES TO THE TREE. It edits in place and restores through a finally, so an interrupted run still
puts the files back, and it verifies the restore and re-checks the baseline before reporting. Run
it from a scratch copy of the repo while the game is open, since this checkout is junctioned into
AddOns.

Anchors are exact source text and they rot. A SKIPPED line means an anchor stopped matching: fix
the anchor rather than dropping the mutant.
"""
import io
import re
import subprocess
import sys

LUA = r"C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe"
HARNESS = "docs/test_focus.lua"

F = "Data/Focus.lua"
A = "Core/API.lua"
V = "EQObjectiveTracker_Vanilla.toc"
QUESTS = "Data/Providers/Quests.lua"
CLASSIC = "Data/Providers/QuestsClassic.lua"

GATE = "if ns.Has.SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and isForever() then\n"
PEW = '        Events:On("PLAYER_ENTERING_WORLD", followSuperTrack)\n'
STORE = "    focusedProvider, focusedID = providerID, entryID\n"
ANNOUNCE = ('    local API = ns:GetModule("API")\n'
            "    if API then API:NotifyFocus(announceProvider, entryID) end\n")
DIRTY = "    for i = 1, #dirtyHandlers do dirtyHandlers[i]() end\n"
RESEND_GATE = "    if not (following and focusedID) then return end\n"
RESEND_CALL = "    if API then API:NotifyFocus(focusedProvider, focusedID) end\n"
FOCUS_TOC = "Data\\QuestCache.lua\nData\\Focus.lua\n"

MUTANTS = [
    # ------------------------------------------------------------- when Forever is announced
    ("the enable reads super-track at once, so the login's quest reaches no listener", [
        (F, "        following = true\n    end\nend\n",
            "        following = true\n        followSuperTrack()\n    end\nend\n")]),

    ("the loading-screen read is dropped, so nothing is announced at login", [
        (F, PEW, "")]),

    ("super-track changes are no longer followed", [
        (F, '        Events:On("SUPER_TRACKING_CHANGED", followSuperTrack)\n', "")]),

    ("super-track is followed through Toggle, so a repeat read clears the quest", [
        (F, '    Focus:Set("quests", id)\n', '    Focus:Toggle("quests", id)\n')]),

    # Everything Quests drops any announcement whose provider is not exactly "quests".
    ("the announcement names a provider Everything Quests does not recognize", [
        (F, '    Focus:Set("quests", id)\n', '    Focus:Set("quest", id)\n')]),

    # -------------------------------------------------------------------- what counts as a quest
    ("a super-track of 0 is announced as quest 0 rather than a clear", [
        (F, "    if not (id and id > 0) then id = nil end\n",
            "    if not (id and id >= 0) then id = nil end\n")]),

    ("the read is passed through unchecked, so 0 and -1 are announced as quests", [
        (F, "    if not (id and id > 0) then id = nil end\n", "")]),

    # ------------------------------------------------------------------ which client it runs on
    ("the Forever test is dropped, so retail follows super-track too", [
        (F, GATE, "if ns.Has.SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then\n")]),

    ("Has.SuperTrack is not asked, so a client without C_SuperTrack raises at load", [
        (F, GATE, "if C_SuperTrack.GetSuperTrackedQuestID and isForever() then\n")]),

    ("the getter is not asked, so a client without it subscribes to a raise", [
        (F, GATE, "if ns.Has.SuperTrack and isForever() then\n")]),

    # The shape before the scan: OnEnable everywhere with the gate inside, which put Focus in
    # /eqot modules on retail and Classic as a switch that changes nothing.
    ("OnEnable is defined everywhere again, with the gate moved inside it", [
        (F, GATE + "    function Focus:OnEnable()\n",
            "do\n    function Focus:OnEnable()\n"
            "        if not (ns.Has.SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and isForever()) "
            "then return end\n")]),

    ("interface 16000 is left out of Forever's range", [
        (F, "toc >= 16000 and", "toc > 16000 and")]),

    ("interface 17000 is let into Forever's range", [
        (F, "toc < 17000\n", "toc <= 17000\n")]),

    # The trap RowMenu's Wowhead link already guards against: without the extra parentheses,
    # every value after the interface reaches tonumber, and the next one is read as a base.
    ("the extra parentheses around select are dropped", [
        (F, "    local toc = tonumber((select(4, GetBuildInfo())))\n",
            "    local toc = tonumber(select(4, GetBuildInfo()))\n")]),

    ("the build number is read instead of the interface", [
        (F, "    local toc = tonumber((select(4, GetBuildInfo())))\n",
            "    local toc = tonumber((select(2, GetBuildInfo())))\n")]),

    ("a build info with no interface number raises instead of reading as not Forever", [
        (F, "    return toc ~= nil and toc >= 16000", "    return toc >= 16000")]),

    # ------------------------------------------------------- the resend and the status line
    ("OnEnable never records that it follows super-track, so Resend never fires", [
        (F, "        following = true\n", "")]),

    ("Focus claims to follow super-track from load, so retail and Classic resend", [
        (F, "local following = false\n", "local following = true\n")]),

    ("Resend ignores whether Focus follows super-track", [
        (F, RESEND_GATE, "    if not focusedID then return end\n")]),

    ("Resend announces with nothing focused", [
        (F, RESEND_GATE, "    if not following then return end\n")]),

    ("Resend goes through Set, which stays silent on an unchanged focus", [
        (F, RESEND_CALL, "    Focus:Set(focusedProvider, focusedID)\n")]),

    ("Resend also asks for a repaint", [
        (F, RESEND_CALL, RESEND_CALL + "    for i = 1, #dirtyHandlers do dirtyHandlers[i]() end\n")]),

    ("FollowsSuperTrack answers yes everywhere", [
        (F, "    return following\n", "    return true\n")]),

    ("the status line never says Focus follows super-track", [
        (A, 'tostring(providerID), tostring(entryID), follows and ", follows super-track" or "")',
            'tostring(providerID), tostring(entryID), "")')]),

    ("the status line says it follows super-track whenever Focus is loaded", [
        (A, "    local follows = Focus and Focus:FollowsSuperTrack()\n",
            "    local follows = Focus ~= nil\n")]),

    # ------------------------------------------------------------- the Set and Toggle contract
    ("a clear with a provider is stored as that provider with no quest", [
        (F, "    if not entryID then providerID = nil end\n", "")]),

    ("Set announces even when the focus has not changed", [
        (F, "    if focusedProvider == providerID and focusedID == entryID then return false end\n", "")]),

    ("a clear is announced with no provider, so a scoped listener cannot tell it is its own", [
        (F, "    if API then API:NotifyFocus(announceProvider, entryID) end\n",
            "    if API then API:NotifyFocus(providerID, entryID) end\n")]),

    ("Set stops announcing altogether", [
        (F, "    if API then API:NotifyFocus(announceProvider, entryID) end\n", "")]),

    ("Set stops asking for a repaint", [
        (F, DIRTY, "")]),

    ("Toggle never clears, so a second click keeps the quest", [
        (F, "    if self:Is(providerID, entryID) then return self:Set(nil, nil) end\n", "")]),

    ("an empty focus reads as a focus on nothing", [
        (F, "    return focusedProvider ~= nil and focusedProvider == providerID and focusedID == entryID\n",
            "    return focusedProvider == providerID and focusedID == entryID\n")]),

    # -------------------------------------------------------------------- found by the scan
    ("the loading-screen read runs only on a first login, as SuperTrackPersist's does", [
        (F, PEW, '        Events:On("PLAYER_ENTERING_WORLD", function(_, isInitialLogin)\n'
                 "            if isInitialLogin then followSuperTrack() end\n"
                 "        end)\n")]),

    ("the loading-screen read skips zone changes", [
        (F, PEW, '        Events:On("PLAYER_ENTERING_WORLD", function(_, isLogin, isReload)\n'
                 "            if isLogin or isReload then followSuperTrack() end\n"
                 "        end)\n")]),

    ("the handler writes super-track back", [
        (F, '    Focus:Set("quests", id)\n',
            '    C_SuperTrack.SetSuperTrackedQuestID(id or 0)\n    Focus:Set("quests", id)\n')]),

    ("the no-change test ignores the provider", [
        (F, "    if focusedProvider == providerID and focusedID == entryID then return false end\n",
            "    if focusedID == entryID then return false end\n")]),

    ("Is compares the quest and ignores the provider", [
        (F, "    return focusedProvider ~= nil and focusedProvider == providerID and focusedID == entryID\n",
            "    return focusedProvider ~= nil and focusedID == entryID\n")]),

    ("the listeners hear the change before it is stored", [
        (F, STORE + "\n" + ANNOUNCE, ANNOUNCE + STORE)]),

    ("the repaint runs before the change is stored", [
        (F, STORE + "\n" + ANNOUNCE + DIRTY, DIRTY + STORE + ANNOUNCE)]),

    ("OnDirty keeps only the last handler", [
        (F, "    dirtyHandlers[#dirtyHandlers + 1] = fn\n", "    dirtyHandlers[1] = fn\n")]),

    ("a raising listener is not contained and stops the rest", [
        (A, "        if it then pcall(it.onFocus, providerID, entryID) end\n",
            "        if it then it.onFocus(providerID, entryID) end\n")]),

    ("the listeners are walked forwards, so a self-removing one skips its neighbor", [
        (A, "    for i = #list, 1, -1 do\n", "    for i = 1, #list do\n")]),

    ("only the last listener is called", [
        (A, "    for i = #list, 1, -1 do\n", "    for i = #list, #list, -1 do\n")]),

    ("a listener registered twice under one id is kept twice", [
        (A, "    self.focusListeners[slotFor(self.focusListeners, spec.id)] = {\n",
            "    self.focusListeners[#self.focusListeners + 1] = {\n")]),

    ("a listener with no onFocus is accepted", [
        (A, '    if type(spec.onFocus) ~= "function" then return false end\n', "")]),

    ("a successful registration reports failure", [
        (A, "        id = spec.id, onFocus = spec.onFocus,\n    }\n    return true\n",
            "        id = spec.id, onFocus = spec.onFocus,\n    }\n    return false\n")]),

    ("RemoveFocusListener removes nothing", [
        (A, "        if self.focusListeners[i].id == id then table.remove(self.focusListeners, i) end\n", "")]),

    # -------------------------------------------------------------------------------- seams
    ("the module is registered under a name API:GetFocus does not read", [
        (F, 'local Focus = ns:RegisterModule("Focus", {})\n',
            'local Focus = ns:RegisterModule("TrackerFocus", {})\n')]),

    ("API:GetFocus reads a module that does not exist", [
        (A, '    local Focus = ns:GetModule("Focus")\n    if not Focus then return nil, nil end\n',
            '    local Focus = ns:GetModule("Focused")\n    if not Focus then return nil, nil end\n')]),

    ("the retail TOC drops Data\\Focus.lua, which is the one Forever loads", [
        ("EQObjectiveTracker_Mainline.toc", FOCUS_TOC, "Data\\QuestCache.lua\n")]),

    ("the Camelot TOC drops Data\\Focus.lua", [
        ("EQObjectiveTracker_Camelot.toc", FOCUS_TOC, "Data\\QuestCache.lua\n")]),

    ("the base TOC drops Data\\Focus.lua", [
        ("EQObjectiveTracker.toc", FOCUS_TOC, "Data\\QuestCache.lua\n")]),

    ("the Vanilla TOC drops Data\\Focus.lua", [
        (V, FOCUS_TOC, "Data\\QuestCache.lua\n")]),

    ("the TBC TOC drops Data\\Focus.lua", [
        ("EQObjectiveTracker_TBC.toc", FOCUS_TOC, "Data\\QuestCache.lua\n")]),

    # Two adjacent copies share a newline, which a single-pattern count cannot see.
    ("the Vanilla TOC lists Data\\Focus.lua twice in a row", [
        (V, FOCUS_TOC, FOCUS_TOC + "Data\\Focus.lua\n")]),

    ("the Vanilla TOC loads Focus after QuestsClassic has captured it", [
        (V, FOCUS_TOC, "Data\\QuestCache.lua\n"),
        (V, "Data\\Providers\\QuestsClassic.lua\n", "Data\\Providers\\QuestsClassic.lua\nData\\Focus.lua\n")]),

    ("the retail quest provider changes the id Focus announces under", [
        (QUESTS, '    id       = "quests",\n', '    id       = "quest",\n')]),

    ("the Classic quest provider changes the id Focus announces under", [
        (CLASSIC, '    id       = "quests",\n', '    id       = "quest",\n')]),
]

SUMMARY = re.compile(r"^test_focus: (\d+) passed, (\d+) failed$")


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
