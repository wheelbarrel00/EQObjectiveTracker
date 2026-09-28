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
and so nothing could catch it. There are three. The two later ones are explained at their
entries, and the first looks load-bearing:

  - The first-pass `if not armed then return end` cannot be what keeps a cold login quiet. The
    visit above it only counts a quest while `armed` is already true, so on the first pass
    pending can only be 0 (and the table it compares against is empty there anyway).

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
and they are kept together in a section of their own for that reason. Debouncing on
"eqot.render" - the tracker's repaint key, which a keyed bus lets one caller silently cancel -
left the harness reading 89 passed, 0 failed, because the stub threw the key away. And
hardcoding a sound name
was invisible because the Media stub recorded the "NONE" token as a played sound, so the one
configuration that could tell the two apart could not be written down.

WRITES TO THE TREE. It edits Data/QuestSound.lua and Core/Media.lua in place and restores them
after every mutant, through a finally, so an interrupted run still puts them back, and it
verifies the restore and re-checks the baseline before reporting.

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
MEDIA = "Core/Media.lua"

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
        ("        if scratch[id] == nil and not (holding and lastComplete[id]) then\n"
         "            lastComplete[id] = nil\n        end",
         "        if false then lastComplete[id] = nil end")]),

    # The prune must not erase a recorded completion while the gate is closed - that record
    # is what the hold in visit reads. Without it the quest returns reading incomplete and
    # the correct value arriving next scan is the same false to true the chime fires on.
    ("a quest absent for one scan loses its completion while the gate is closed", [
        ("        if scratch[id] == nil and not (holding and lastComplete[id]) then",
         "        if scratch[id] == nil then")]),

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

    # ------------------------------------------ a complete quest across a loading screen
    # Blizzard hands a complete quest back as incomplete for a second or two after a loading
    # screen. Written in, it reads as the quest un-finishing, and the correct value on the pass
    # after it then reads as a fresh completion - an ordinary zone change chiming for a quest
    # finished ten minutes ago. docs/test_quest_cache.lua greps for this line; these two mutants
    # are what say it actually does anything.
    ("the hold on a complete quest across a loading screen is dropped",
     [("    if not now and lastComplete[id] and not QuestCache:IsReady() then",
       "    if false and not now and lastComplete[id] and not QuestCache:IsReady() then")]),

    # The other direction, and the one that would be reported as "the chime stopped working":
    # holding unconditionally means a quest can never be seen to un-finish at all, so a quest
    # abandoned and retaken is complete forever and never chimes again.
    ("the hold ignores the window and applies always",
     [("    if not now and lastComplete[id] and not QuestCache:IsReady() then",
       "    if not now and lastComplete[id] then")]),

    ("the hold fires on a quest that was never complete",
     [("    if not now and lastComplete[id] and not QuestCache:IsReady() then",
       "    if not now and lastComplete[id] ~= nil and not QuestCache:IsReady() then")]),

    # ------------------------------------------ the /eqot status census of complete quests
    # Only a recorded false lets visit chime, and the census is the only line that shows which
    # record each currently-complete quest carries. Every mutant here makes that line read
    # plausibly while answering a different question.
    ("the census counts every quest in the log, finished or not", [
        ("        if not (flag or derived) then return end\n", "")]),

    ("the census counts a quest done by Blizzard's flag only, never by its objectives", [
        ("        if not (flag or derived) then return end\n", "        if not flag then return end\n")]),

    ("the census hands a FAILED quest the derived answer visit refuses it", [
        ("        if not flag and not failed then derived = objectivesDone(id) end",
         "        if not flag then derived = objectivesDone(id) end")]),

    ("the retail census stops passing IsFailed through", [
        ("                     ns.Has.QuestIsFailed and C_QuestLog.IsFailed(info.questID))",
         "                     false)")]),

    ("the Classic census reads a -1 in slot 6 as complete", [
        ("                note(id, title, isComplete and isComplete ~= 0 and isComplete ~= -1,",
         "                note(id, title, isComplete and isComplete ~= 0,")]),

    ("the Classic census stops passing the -1 through as failed", [
        ("                note(id, title, isComplete and isComplete ~= 0 and isComplete ~= -1,\n"
         "                     isComplete == -1)",
         "                note(id, title, isComplete and isComplete ~= 0 and isComplete ~= -1)")]),

    ("the census reads presence, so a quest due to chime reads as already recorded", [
        ("        if rec == true then\n", "        if rec ~= nil then\n")]),

    ("the census reads truth, so a quest due to chime reads as never seen", [
        ("        elseif rec == false then\n", "        elseif rec then\n")]),

    ("the census swaps recorded complete and recorded unfinished", [
        ("            recDone = recDone + 1\n        elseif rec == false then\n"
         "            recPending = recPending + 1\n",
         "            recPending = recPending + 1\n        elseif rec == false then\n"
         "            recDone = recDone + 1\n")]),

    # A quest held over a loading screen is recorded but absent from the last scan's answers,
    # which is the one place the scratch table and the kept record disagree.
    ("the census reads the last scan's answers rather than the kept record", [
        ("        local rec = lastComplete[id]\n", "        local rec = scratch[id]\n")]),

    ("the census names the LAST unrecorded quest rather than the first", [
        ("            firstNone = firstNone or ('\"%s\" (%s)'):format(safeText(title), tostring(id))",
         "            firstNone = ('\"%s\" (%s)'):format(safeText(title), tostring(id))")]),

    ("the census hands a secret quest title straight to string.format", [
        ("            firstNone = firstNone or ('\"%s\" (%s)'):format(safeText(title), tostring(id))",
         "            firstNone = firstNone or ('\"%s\" (%s)'):format(title, tostring(id))")]),

    ("the census never names the unrecorded quest", [
        ('            :format(recDone, recPending, recNone, firstNone and (" -> " .. firstNone) or "")',
         '            :format(recDone, recPending, recNone, "")')]),

    ("the census prints its tallies out of order", [
        ('            :format(recDone, recPending, recNone, firstNone and (" -> " .. firstNone) or "")',
         '            :format(recDone, recNone, recPending, firstNone and (" -> " .. firstNone) or "")')]),

    # ------------------------------------------ when the scan last asked for the sound
    # `(last Ns)` exists to tell "the scan asked late" from "the client played late", so a value
    # that reads right only while the scan and the play share a second is the defect.
    ("the scan line prints the last SCAN time in the last-played slot", [
        ("            :format(stats.scanSaw, stats.scanPlayed, ago(stats.scanPlayedAt), stats.turnIns,",
         "            :format(stats.scanSaw, stats.scanPlayed, ago(stats.scanAt), stats.turnIns,")]),

    ("the play time is never stamped, so a chime reads as never asked for", [
        ("        stats.scanPlayedAt = GetTime()\n", "")]),

    ("a session with no chime reads as one played at time zero", [
        ("    scanSaw = 0, scanPlayed = 0, turnIns = 0,\n",
         "    scanSaw = 0, scanPlayed = 0, turnIns = 0, scanPlayedAt = 0,\n")]),

    ("the last sound line stops asking Media", [
        ('        ("last sound: %s"):format(ns:GetModule("Media"):LastPlayLine()),',
         '        ("last sound: %s"):format("none this session"),')]),

    # ------------------------------------------ Core/Media.lua's own play record
    # Before 2026-09-21 no harness reached the real Play at all. The kit half had no refusal and
    # no raise to report until the PlaySound stub learned both.
    ("a PlaySound that raises escapes Play, taking the scan down with it", [
        ('        local ok, willPlay = pcall(PlaySound, kit, "Master")',
         '        local ok, willPlay = true, PlaySound(kit, "Master")', MEDIA)]),

    ("a PlaySoundFile that raises escapes Play, taking the scan down with it", [
        ('    local ok, willPlay = pcall(PlaySoundFile, file, "Master")',
         '    local ok, willPlay = true, PlaySoundFile(file, "Master")', MEDIA)]),

    ("a raising PlaySound is recorded as an answer rather than a raise", [
        ('        lastPlay = { name = name, at = at, kit = kit,\n'
         '                     outcome = ok and ("willPlay " .. tostring(willPlay)) or "raised" }',
         '        lastPlay = { name = name, at = at, kit = kit,\n'
         '                     outcome = "willPlay " .. tostring(willPlay) }', MEDIA)]),

    ("the kit record prints pcall's ok where the client's willPlay belongs", [
        ('                     outcome = ok and ("willPlay " .. tostring(willPlay)) or "raised" }\n'
         '        return',
         '                     outcome = ok and ("willPlay " .. tostring(ok)) or "raised" }\n'
         '        return', MEDIA)]),

    ("the file record prints pcall's ok where the client's willPlay belongs", [
        ('    lastPlay = { name = name, at = at, file = file,\n'
         '                 outcome = ok and ("willPlay " .. tostring(willPlay)) or "raised" }',
         '    lastPlay = { name = name, at = at, file = file,\n'
         '                 outcome = ok and ("willPlay " .. tostring(ok)) or "raised" }', MEDIA)]),

    ("the kit record drops the kit id", [
        ("        lastPlay = { name = name, at = at, kit = kit,\n",
         "        lastPlay = { name = name, at = at,\n", MEDIA)]),

    ("the file record drops the file id", [
        ("    lastPlay = { name = name, at = at, file = file,\n",
         "    lastPlay = { name = name, at = at,\n", MEDIA)]),

    ("a kit this client lacks leaves the previous record standing", [
        ('            lastPlay = { name = name, at = at, outcome = "no kit on this client" }\n', "",
         MEDIA)]),

    ("a client with no PlaySoundFile leaves the previous record standing", [
        ('        lastPlay = { name = name, at = at, outcome = "no file" }\n', "", MEDIA)]),

    ("the age is printed as the call's clock time rather than time since it", [
        ("        GetTime() - lastPlay.at, lastPlay.outcome)",
         "        lastPlay.at, lastPlay.outcome)", MEDIA)]),

    ("the age counts from the session's first sound, not its last", [
        ("    local at = GetTime()\n", "    local at = lastPlay and lastPlay.at or GetTime()\n",
         MEDIA)]),

    ("the status line drops the kit or file id", [
        ('        lastPlay.name, what and (" (" .. tostring(what) .. ")") or "",',
         '        lastPlay.name, "",', MEDIA)]),

    ("nothing played reads as something other than none this session", [
        ('    if not lastPlay then return "none this session" end',
         '    if not lastPlay then return "none" end', MEDIA)]),

    ("the kit path drops the Master channel", [
        ('        local ok, willPlay = pcall(PlaySound, kit, "Master")',
         '        local ok, willPlay = pcall(PlaySound, kit)', MEDIA)]),

    # Genuinely equivalent: LastPlayLine reads `file or kit` and only one is ever set, so the
    # field a record carries its id under changes nothing any reader can see.
    ("EQUIVALENT: the kit id is stored under the file field", [
        ("        lastPlay = { name = name, at = at, kit = kit,\n",
         "        lastPlay = { name = name, at = at, file = kit,\n", MEDIA)]),

    # ------------------------------------------ hand-broken in the second 2026-09-27 scan
    ("the census's unfinished tally never passes one", [
        ("            recPending = recPending + 1\n", "            recPending = 1\n")]),

    ("the Classic census reads a slot 6 of 0 as complete", [
        ("                note(id, title, isComplete and isComplete ~= 0 and isComplete ~= -1,",
         "                note(id, title, isComplete and isComplete ~= -1,")]),

    ("a kit with no PlaySound on the client is recorded as raised", [
        ("        if not (kit and PlaySound) then", "        if not kit then", MEDIA)]),
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


# Read once per file. The status record half of these mutants lives in Core/Media.lua, which is
# LF where Data/QuestSound.lua is CRLF, so the line endings are resolved per file as well.
ORIGINALS = {}


def sourceOf(rel):
    if rel not in ORIGINALS:
        ORIGINALS[rel] = io.open(rel, encoding="utf-8", newline="").read()
    return ORIGINALS[rel]


def fit(rel, s):
    return s.replace("\n", "\r\n") if "\r\n" in sourceOf(rel) else s


sourceOf(SRC)
verdict, last = run()
print("baseline: %s\n" % last)
if verdict != "green":
    print("BASELINE IS NOT GREEN - stopping")
    sys.exit(1)

survivors = []
for name, hunks in MUTANTS:
    # A third element names a file other than SRC. Two-element hunks are the majority and mean
    # Data/QuestSound.lua, so widening this cost them nothing.
    edited, broken = {}, False
    for hunk in hunks:
        rel = hunk[2] if len(hunk) > 2 else SRC
        old, new = fit(rel, hunk[0]), fit(rel, hunk[1])
        cur = edited.get(rel, sourceOf(rel))
        if cur.count(old) != 1:
            print("SKIPPED (anchor matched %d times in %s): %s" % (cur.count(old), rel, name))
            broken = True
            break
        edited[rel] = cur.replace(old, new, 1)
    if broken:
        survivors.append(name)
        continue
    try:
        for rel, text in edited.items():
            io.open(rel, "w", encoding="utf-8", newline="").write(text)
        verdict, last = run()
    finally:
        for rel in edited:
            io.open(rel, "w", encoding="utf-8", newline="").write(sourceOf(rel))
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
for rel, text in ORIGINALS.items():
    if io.open(rel, encoding="utf-8", newline="").read() != text:
        print("\nTHE TREE WAS NOT RESTORED - %s still holds a mutant" % rel)
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
