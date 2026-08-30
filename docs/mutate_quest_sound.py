"""Prove docs/test_quest_sound.lua actually discriminates, by breaking production on purpose
one change at a time and checking the harness notices.

    python docs/mutate_quest_sound.py           (run from the repo root)

Why this exists: the defect this module was rewritten to fix was invisible to every gate the
project has. The scan read three C_QuestLog functions that do not exist on Classic, so it
returned at its first line on every pass there and the sound was left to a chat message that
arrives at the quest giver. luacheck was clean, the retail behavior was correct, and no harness
had a Classic case to fail. Several mutants below put that exact shape back.

Every mutation reintroduces a defect the harness is supposed to stand guard over. Any that still
reports "0 failed" is an assertion that does not discriminate, and the run exits 1 naming it -
unless the entry is marked EQUIVALENT, which means the mutation provably cannot change behavior
and so nothing could catch it. There is ONE of those, and it looks load-bearing:

  - The first-pass `if not armed then return end` cannot be what keeps a cold login quiet. The
    visit above it already refuses on `lastComplete[id] == false`, and on the first pass that
    table is empty, so every entry reads nil and pending can only be 0.

The prune of quests that left the log was ALSO marked equivalent here, on the reasoning that the
write-back below it overwrites every quest still in the log so a stale entry can only belong to
one the walk no longer visits. That reasoning is wrong and a scan measured it: a quest recorded
unfinished, one pass where the log reads EMPTY, then the same quest back and complete, sounds
WITHOUT the prune and stays silent with it. An empty quest log is a real cold-login state this
project has already recorded. The label was hiding a genuine coverage hole.

A mutant with more than one hunk is deliberate: reverting half of a two-part behavior leaves the
code working and reports a coverage hole that is not there. The turn-in dedup key is the one
here - namespacing it matters only if both the read and the write are namespaced.

Two of the mutants below could not be caught at all until the harness's own STUBS were fixed,
and they are kept together at the end for that reason. Debouncing on "eqot.render" - the
tracker's repaint key, which a keyed bus lets one caller silently cancel - left the harness
reading 89 passed, 0 failed, because the stub threw the key away. And hardcoding a sound name
was invisible because the Media stub recorded the "NONE" token as a played sound, so the one
configuration that could tell the two apart could not be written down.

WRITES TO THE TREE. It edits Data/QuestSound.lua in place and restores it after every mutant,
through a finally, so an interrupted run still puts it back, and it verifies the restore and
re-checks the baseline before reporting.

If you hard-kill it anyway, recover from your editor's undo history, NOT with git. This file is
routinely uncommitted while it is being worked on, so `git checkout -- Data/QuestSound.lua` would
throw the session's work away rather than bring it back.

Anchors are exact source text and they rot. A SKIPPED line means an anchor stopped matching:
fix the anchor rather than dropping the mutant, the same rule test_row_blocks.lua carries.
"""
import io
import re
import subprocess
import sys

LUA = r"C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe"
SRC = "Data/QuestSound.lua"
HARNESS = "docs/test_quest_sound.lua"

MUTANTS = [
    # ---------------------------------------------------------- the failed quest, both surfaces
    # The flag path refuses a FAILED quest on both surfaces and the derived path then asked
    # objectivesDone anyway, which answers true for a failed escort whose objectives all read
    # finished. That is the one state where the two answers disagree.
    ("a failed quest is handed to the derived answer that the flag path just refused it for", [
        ("    if not now and not failed then", "    if not now then")]),

    ("the retail walk stops reading IsFailed, so nothing tells visit the quest failed", [
        ("visit(info.questID, info.title, flag and true or false, failed and true or false)",
         "visit(info.questID, info.title, flag and true or false)")]),

    ("the Classic walk stops passing the -1 in slot 6 through as failed", [
        ("and true or false,\n                  isComplete == -1)",
         "and true or false)")]),

    ("the failed refusal stops being counted, so the status line cannot name it", [
        ("    if failed then stats.failed = stats.failed + 1 end\n", "")]),

    # ---------------------------------------------------------- the turn in path's own gates
    ("the hand in loses its world quest gate and chimes in a field", [
        ('    if C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(questID) then\n'
         '        logEvent("turnin", tostring(questID), "skipped, world quest")\n'
         "        return\n    end\n", "")]),

    ("the hand in loses its task quest gate, so a bonus objective chimes", [
        ('    if C_QuestLog.IsQuestTask and C_QuestLog.IsQuestTask(questID) then\n'
         '        logEvent("turnin", tostring(questID), "skipped, task quest")\n'
         "        return\n    end\n", "")]),

    ("the two hand in gates are swapped, so each names the other's refusal", [
        ('"skipped, world quest")', '"skipped, task quest")'),
        ('"skipped, task quest")\n        return\n    end\n\n    if isRecent',
         '"skipped, world quest")\n        return\n    end\n\n    if isRecent')]),

    # ---------------------------------------------------------- the shipped Classic defect
    ("the walk goes back to retail only, the bug this rewrite fixed", [
        ('    if type(GetQuestLogTitle) ~= "function" then\n        stats.surface = "none, no quest log api"',
         '    if true then\n        stats.surface = "none, no quest log api"')]),

    ("the Classic walk is bounded by GetNumQuestLogEntries, which counts visible rows only", [
        ("    for i = 1, MAX_LOG_INDEX do\n        local title, _, _, isHeader, _, isComplete, _, id = GetQuestLogTitle(i)",
         "    for i = 1, GetNumQuestLogEntries() do\n        local title, _, _, isHeader, _, isComplete, _, id = GetQuestLogTitle(i)")]),

    ("the Classic tuple's complete flag is read from the wrong slot", [
        ("        local title, _, _, isHeader, _, isComplete, _, id = GetQuestLogTitle(i)\n        if not title then break end\n        if not isHeader and id and id ~= 0 then\n            visit(id, title, (isComplete and isComplete ~= 0 and isComplete ~= -1) and true or false,\n                  isComplete == -1)",
         "        local title, _, _, isHeader, isComplete, _, _, id = GetQuestLogTitle(i)\n        if not title then break end\n        if not isHeader and id and id ~= 0 then\n            visit(id, title, (isComplete and isComplete ~= 0 and isComplete ~= -1) and true or false,\n                  isComplete == -1)")]),

    ("a FAILED Classic quest counts as complete", [
        ("visit(id, title, (isComplete and isComplete ~= 0 and isComplete ~= -1) and true or false,\n                  isComplete == -1)",
         "visit(id, title, (isComplete and isComplete ~= 0) and true or false,\n                  isComplete == -1)")]),

    # ---------------------------------------------------------- the derived answer
    ("Blizzard's complete flag is trusted on its own again", [
        ("    if not now and not failed then\n        now = objectivesDone(id)\n        if now then stats.derived = stats.derived + 1 end\n    end\n",
         "")]),

    ("a quest whose objectives have not streamed in counts as all done", [
        ("    if n == 0 then return false end", "    if n == 0 then return true end")]),

    ("one unfinished objective no longer refuses the quest", [
        ("        if not objs[i].finished then return false end",
         "        if objs[i] == nil then return false end")]),

    ("the count of derived answers stops moving, so the status cannot say what answered", [
        ("        if now then stats.derived = stats.derived + 1 end",
         "        if now then stats.derived = stats.derived + 0 end")]),

    # ---------------------------------------------------------- priming and re-priming
    ("a quest first seen already complete is treated as a transition", [
        ("    if armed and now and lastComplete[id] == false then",
         "    if armed and now and not lastComplete[id] then")]),

    ("EQUIVALENT: the belt-and-braces first-pass return is deleted", [
        ("    if not armed then\n        armed = true\n        return\n    end", "    armed = true")]),

    ("the prune of quests that left the log is dropped", [
        ("        if scratch[id] == nil then lastComplete[id] = nil end",
         "        if false then lastComplete[id] = nil end")]),

    ("switching the option off no longer re-primes", [
        ("        armed = false\n        return", "        return")]),

    ("the write-back of this pass's answers is dropped", [
        ("    for id, v in pairs(scratch) do lastComplete[id] = v end",
         "    for id in pairs(scratch) do lastComplete[id] = nil end")]),

    ("a quest log header is walked as a quest, retail", [
        ("            if info and not info.isHeader and info.questID then\n                local flag",
         "            if info and info.questID then\n                local flag")]),

    # Split from the retail hunk deliberately. Bundled, the pair reported "caught" on the retail
    # half alone and implied coverage the Classic half does not have. It is genuinely equivalent
    # on measured client data: Classic headers carry questID 0, which the `id ~= 0` beside it
    # already refuses, so a header would need a NON-zero id to slip through and no reading has
    # ever produced one.
    ("EQUIVALENT: the Classic header guard is dropped", [
        ("        if not isHeader and id and id ~= 0 then\n            visit(id, title,",
         "        if id and id ~= 0 then\n            visit(id, title,")]),

    # ---------------------------------------------------------- the three sounds staying apart
    ("the turn in plays the objectives sound", [
        ("    playFile(cfg.questTurnInSound)", "    playFile(cfg.questCompleteSound)")]),

    ("the turn in ignores its own switch", [
        ("    if not (cfg and cfg.questTurnInSoundEnabled) then",
         "    if not (cfg and cfg.questSoundEnabled) then")]),

    # Four hunks on purpose. Dropping the prefix on the turn in alone leaves the accept side
    # still writing "a<id>", so the two keys cannot collide and the mutant reproduces nothing -
    # a half-mutation reporting a coverage hole that is not there.
    ("the dedup keys stop being namespaced, so an accept swallows the hand in behind it", [
        ('    if isRecent("a" .. questID) then return end', "    if isRecent(questID) then return end"),
        ('    recordRecent("a" .. questID)', "    recordRecent(questID)"),
        ('    if isRecent("t" .. questID) then', "    if isRecent(questID) then"),
        ('    recordRecent("t" .. questID)', "    recordRecent(questID)")]),

    ("a doubled hand in event is not deduped", [
        ('    if isRecent("t" .. questID) then',
         "    if questID == nil then")]),

    ("hand ins are counted only when they play", [
        ("    stats.turnIns = stats.turnIns + 1", "    stats.turnIns = stats.turnIns + 0")]),

    ("the accept path reads the FIRST payload slot, the Classic log index", [
        ("    local questID = b or a", "    local questID = a or b")]),

    ("the accept path stops skipping world quests", [
        ("    if C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(questID) then return end",
         "    if false then return end")]),

    # ---------------------------------------------------------- the instrument itself
    ("the walked surface is not named, so no log at all reads as an empty log", [
        ('    stats.surface = "GetQuestLogTitle"', '    stats.surface = "C_QuestLog"')]),

    ("the mismatch walk stops naming the quest it found", [
        ("""            firstMismatch = firstMismatch or ('"%s" (%s)'):format(safeText(title), tostring(id))""",
         '            firstMismatch = firstMismatch or "a quest"')]),

    ("a secret quest title reaches string.format unguarded", [
        ("    log[#log + 1] = { path = path, title = safeText(title), action = action, at = GetTime() }",
         "    log[#log + 1] = { path = path, title = title, action = action, at = GetTime() }")]),

    ("the recent list grows without bound", [
        ("    if #log > LOG_MAX then table.remove(log, 1) end", "    -- unbounded")]),

    ("QUEST_TURNED_IN is not registered", [
        ('    Events:On("QUEST_TURNED_IN", onQuestTurnedIn)', "    -- removed")]),

    # ---------------------------------------------------------- the debounce key and delay
    # The bus in Core/Events.lua is keyed, and a second arrival on an armed key REPLACES the
    # first function. Before the harness recorded the key, this exact mutant left the file
    # reading 89 passed, 0 failed while the tracker's queued repaint was being thrown away.
    ("the scan debounces on the tracker's own repaint key, canceling it", [
        ('Events:Debounce("eqot.questsound", SCAN_DEBOUNCE, detectTransitions)',
         'Events:Debounce("eqot.render", SCAN_DEBOUNCE, detectTransitions)')]),

    ("the debounce delay goes missing, which reaches C_Timer.After as nil", [
        ('Events:Debounce("eqot.questsound", SCAN_DEBOUNCE, detectTransitions)',
         'Events:Debounce("eqot.questsound", nil, detectTransitions)')]),

    # ---------------------------------------------------------- silence, which is a setting
    # "None" heads all three pickers and stores the bare token "NONE", which Media:Play returns
    # at its first line on. Hardcoding a name is inaudible on a default profile and only shows
    # up against a player who chose None.
    ("the objectives sound name is hardcoded, ignoring the player's pick", [
        ("    playFile(cfg.questCompleteSound)", '    playFile("EQ: Work Complete")')]),

    # The defect playFile's own comment exists to prevent: three paths share the helper, so a
    # fallback here means "if the turn in sound is unset, play the objectives one".
    ("playFile grows a fallback name, so an unset sound borrows another path's", [
        ('local function playFile(name)\n    ns:GetModule("Media"):Play(name)',
         'local function playFile(name)\n    ns:GetModule("Media"):Play(name or "EQ: Work Complete")')]),

    # ---------------------------------------------------------- the capability guards
    # ns.Has is a CAPABILITY probe and Core/Compat.lua asks these three separately, so each of
    # the mutants below calls a nil value on a client that answered no to one and yes to another.
    ("the GetQuestObjectives guard is deleted", [
        ("    if not ns.Has.QuestObjectives then return false end", "    -- unguarded")]),

    ("the IsComplete guard on the walk is deleted", [
        ("                local flag   = ns.Has.QuestIsComplete and C_QuestLog.IsComplete(info.questID)",
         "                local flag   = C_QuestLog.IsComplete(info.questID)")]),

    ("the IsComplete guard on the status walk is deleted", [
        ("                note(info.questID, info.title,\n                     ns.Has.QuestIsComplete and C_QuestLog.IsComplete(info.questID),",
         "                note(info.questID, info.title, C_QuestLog.IsComplete(info.questID),")]),

    # ---------------------------------------------------------- the done count
    ("the done count stops moving", [
        ("    if now then stats.done = stats.done + 1 end",
         "    if now then stats.done = stats.done + 0 end")]),

    ("the done count counts every quest walked, finished or not", [
        ("    scratch[id] = now\n    if now then stats.done = stats.done + 1 end",
         "    scratch[id] = now\n    stats.done = stats.done + 1")]),

    # ---------------------------------------------------------- the Classic zero
    # The everyday incomplete answer on 1.15.9 is nil, caught by the first `and`. A slot 6 of 0
    # is caught by this half alone, so without a quest that actually answers 0 it is deletable.
    ("a Classic slot 6 of 0 counts as complete", [
        ("visit(id, title, (isComplete and isComplete ~= 0 and isComplete ~= -1) and true or false,\n                  isComplete == -1)",
         "visit(id, title, (isComplete and isComplete ~= -1) and true or false,\n                  isComplete == -1)")]),
]


SUMMARY = re.compile(r"^test_quest_sound: (\d+) passed, (\d+) failed$")


def run():
    """(verdict, note). verdict is "green", "failed" or "crashed".

    A nonzero exit is NOT evidence that an assertion discriminated. A mutant that does not parse,
    or that blows the module up on load, exits nonzero too - and reporting that as "caught" is a
    false pass in the one tool whose job is to catch false passes. So the harness's own summary
    line is matched rather than its exit code, and a run that never got that far is its own
    verdict.
    """
    r = subprocess.run([LUA, HARNESS], capture_output=True, text=True)
    lines = [l for l in r.stdout.splitlines() if l.strip()]
    for line in reversed(lines):
        m = SUMMARY.match(line.strip())
        if m:
            return ("failed" if int(m.group(2)) else "green"), line.strip()
    return "crashed", (r.stderr.strip().splitlines() or ["no output"])[0][:90]


original = io.open(SRC, encoding="utf-8", newline="").read()
# Data/QuestSound.lua is one of the CRLF files in this tree, and the anchors above are written
# with plain newlines so they stay readable. Nothing here may rewrite the endings.
crlf = "\r\n" in original


def fit(s):
    return s.replace("\n", "\r\n") if crlf else s


verdict, last = run()
print("baseline: %s\n" % last)
if verdict != "green":
    print("BASELINE IS NOT GREEN - stopping")
    sys.exit(1)

survivors = []
for name, hunks in MUTANTS:
    mutated, broken = original, False
    for old, new in hunks:
        old, new = fit(old), fit(new)
        if mutated.count(old) != 1:
            print("SKIPPED (anchor matched %d times): %s" % (mutated.count(old), name))
            broken = True
            break
        mutated = mutated.replace(old, new, 1)
    if broken:
        survivors.append(name)
        continue
    try:
        io.open(SRC, "w", encoding="utf-8", newline="").write(mutated)
        verdict, last = run()
    finally:
        io.open(SRC, "w", encoding="utf-8", newline="").write(original)
    equivalent = name.startswith("EQUIVALENT:")
    if verdict == "crashed":
        # Its own verdict, never "caught". The harness did not run, so nothing about it was
        # proved: the mutant is malformed and its anchor or replacement needs fixing.
        print("CRASHED   %-72s %s" % (name, last))
        survivors.append(name)
    elif verdict == "green" and not equivalent:
        print("SURVIVED  %-72s %s" % (name, last))
        survivors.append(name)
    elif verdict == "failed" and equivalent:
        print("UNEXPECTED %-71s %s" % (name + " (was caught)", last))
        survivors.append(name)
    elif equivalent:
        print("survived  %-72s as expected, it cannot change behavior" % name)
    else:
        print("caught    %-72s %s" % (name, last))

# Proved rather than trusted. A run that left a mutant in the tree would otherwise report a clean
# sweep over a file nobody meant to keep, and the restore is the one thing this tool must not get
# wrong.
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
