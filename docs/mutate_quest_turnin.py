"""Prove docs/test_quest_turnin.lua actually discriminates, by breaking production on purpose one
change at a time and checking the harness notices.

    python docs/mutate_quest_turnin.py        (run from the repo root)

Why this exists: a finished auto-complete quest is handed in from the objective tracker and
nowhere else, and EQOT hides Blizzard's tracker. Every way this can break is quiet. A click that
stops handing in falls through to super-tracking, which looks like a click that worked. A click
line that stops appearing leaves a row that simply never says it can be clicked. A hand-in wired
to the wrong click opens the reward window on a quest the player only meant to read. None of that
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
HARNESS = "docs/test_quest_turnin.lua"

Q = "Data/Providers/Quests.lua"
R = "UI/Row.lua"

LINE_GATE = ("    if e.state == STATE.COMPLETE and QUEST_WATCH_CLICK_TO_COMPLETE"
             " and isAutoComplete(id) then\n")
LINE_BODY = ("        local ln = Entry.PushLine(e)\n"
             "        ln.text = QUEST_WATCH_CLICK_TO_COMPLETE\n"
             "    end\n")
LINE_BLOCK = LINE_GATE + LINE_BODY

TURNIN_GATE = ("    if not (ShowQuestComplete and questState(id) == STATE.COMPLETE"
               " and isAutoComplete(id)) then\n")
REMOVE = "    if RemoveAutoQuestPopUp then pcall(RemoveAutoQuestPopUp, id) end\n"
SHOW = "    if not pcall(ShowQuestComplete, id) then return false end\n"
NOTIFY = "    if provider._notifyDirty then provider._notifyDirty() end\n"

RIGHT_BRANCH = ("    if button == \"RightButton\" then\n"
                "        if ns.Has.QuestWatchAPI then C_QuestLog.RemoveQuestWatch(entry.id) end\n"
                "        return\n"
                "    end\n")
TURNIN_CALL = "    if not splitIcon and turnIn(self, entry.id) then return end\n"
DISPATCH_CLICK = "    dispatch(row, \"OnEntryClick\", button, splitIcon)\n"
OPENLOG_TURNIN = ("function Quests:OnEntryOpenLog(entry)\n"
                  "    if turnIn(self, entry.id) then return end\n")

UNFOCUS_TEST = "        if again and clickUnfocuses() then\n"
SPLIT_ICON = "    local splitIcon = button == \"LeftButton\" and splitClickWanted(row) and overIcon(row)\n"
CURSOR = "    local mx = GetCursorPosition() / (row:GetEffectiveScale() or 1)\n"

INDEX = ("    local index = C_QuestLog.GetLogIndexForQuestID"
         " and C_QuestLog.GetLogIndexForQuestID(id)\n")
INFO = "    local info  = index and C_QuestLog.GetInfo(index)\n"
AUTO_RETURN = "    return (info and info.isAutoComplete) and true or false\n"

MUTANTS = [
    # ------------------------------------------------------------------- the click line
    ("the click line is never pushed, so nothing says the row hands in", [
        (Q, LINE_BLOCK, "")]),

    ("the line drops its state test, so an unfinished quest says click to complete", [
        (Q, LINE_GATE, "    if QUEST_WATCH_CLICK_TO_COMPLETE and isAutoComplete(id) then\n")]),

    ("the line drops its auto-complete test, so an NPC quest says click to complete", [
        (Q, LINE_GATE, "    if e.state == STATE.COMPLETE and QUEST_WATCH_CLICK_TO_COMPLETE then\n")]),

    ("the line drops its global test, so a client without the string pushes a nil line", [
        (Q, LINE_GATE, "    if e.state == STATE.COMPLETE and isAutoComplete(id) then\n")]),

    # Simplify mode and the per-section completed filter both drop a completed line, which
    # would take away the one line that says the row can be clicked.
    ("the line is marked completed, so the completed-line filters hide it", [
        (Q, "        ln.text = QUEST_WATCH_CLICK_TO_COMPLETE\n",
            "        ln.text = QUEST_WATCH_CLICK_TO_COMPLETE\n"
            "        ln.completed = true\n")]),

    ("the line is a NOTE, so it draws dimmed where Blizzard draws an ordinary line", [
        (Q, "        ln.text = QUEST_WATCH_CLICK_TO_COMPLETE\n",
            "        ln.text = QUEST_WATCH_CLICK_TO_COMPLETE\n"
            "        ln.kind = LINE.NOTE\n")]),

    ("the line is drawn above the objectives rather than below them", [
        (Q, LINE_BLOCK, ""),
        (Q, "    Entry.BeginLines(e)\n", "    Entry.BeginLines(e)\n" + LINE_BLOCK)]),

    # EndLines clears the run counter, so a push after it starts again at slot one and
    # overwrites the first objective.
    ("the line is pushed after EndLines, overwriting the first objective", [
        (Q, LINE_BLOCK + "\n    Entry.EndLines(e)\n", "    Entry.EndLines(e)\n" + LINE_BLOCK)]),

    ("the line hard-codes English instead of Blizzard's translated string", [
        (Q, "        ln.text = QUEST_WATCH_CLICK_TO_COMPLETE\n",
            "        ln.text = \"(click to complete)\"\n")]),

    # ------------------------------------------------------------------- isAutoComplete
    ("the GetLogIndexForQuestID presence guard is dropped, raising on a client without it", [
        (Q, INDEX, "    local index = C_QuestLog.GetLogIndexForQuestID(id)\n")]),

    ("GetInfo is asked with no index, raising for a quest the log no longer holds", [
        (Q, INFO, "    local info  = C_QuestLog.GetInfo(index)\n")]),

    ("GetInfo is handed the quest id where it takes a log index", [
        (Q, INFO, "    local info  = index and C_QuestLog.GetInfo(id)\n")]),

    ("the info nil guard is dropped, raising when GetInfo has no answer", [
        (Q, AUTO_RETURN, "    return info.isAutoComplete and true or false\n")]),

    # An absent flag is not a false one: this spelling hands the click-to-complete line, and
    # the hand-in click with it, to every finished quest whose info omits the field.
    ("an absent isAutoComplete is read as auto-complete", [
        (Q, AUTO_RETURN, "    return (info and info.isAutoComplete ~= false) and true or false\n")]),

    ("every quest reads as auto-complete", [
        (Q, AUTO_RETURN, "    return true\n")]),

    # ------------------------------------------------------------------------- turnIn
    ("the hand-in drops its state test, so an unfinished quest opens the reward window", [
        (Q, TURNIN_GATE, "    if not (ShowQuestComplete and isAutoComplete(id)) then\n")]),

    ("the hand-in drops its auto-complete test, so an NPC quest is handed in from the row", [
        (Q, TURNIN_GATE, "    if not (ShowQuestComplete and questState(id) == STATE.COMPLETE) then\n")]),

    # Data/QuestSound.lua records IsComplete saying no for a failed quest. The fixture builds the
    # opposite anyway, so the hand-in gate cannot come to lean on that.
    ("the hand-in trusts IsComplete, so a failed quest is handed in", [
        (Q, TURNIN_GATE, "    if not (ShowQuestComplete and C_QuestLog.IsComplete(id)"
                         " and isAutoComplete(id)) then\n")]),

    ("the ShowQuestComplete presence guard is dropped, raising on a client without it", [
        (Q, TURNIN_GATE, "    if not (questState(id) == STATE.COMPLETE and isAutoComplete(id)) then\n")]),

    ("a refused hand-in still swallows the click, so nothing super-tracks", [
        (Q, TURNIN_GATE + "        return false\n",
            TURNIN_GATE + "        return true\n")]),

    ("the popup is left behind after a hand-in from the row", [
        (Q, REMOVE, "")]),

    ("the popup removal loses its pcall, so a raising API costs the hand-in", [
        (Q, REMOVE, "    if RemoveAutoQuestPopUp then RemoveAutoQuestPopUp(id) end\n")]),

    # pcall(nil) does not raise, it answers false, so the presence test in front of the pcall
    # is redundant and removing it changes nothing a player could see.
    ("EQUIVALENT: the popup removal drops its presence test, which pcall already absorbs", [
        (Q, REMOVE, "    pcall(RemoveAutoQuestPopUp, id)\n")]),

    ("the reward window opens before the popup is removed, not in Blizzard's order", [
        # Two edits rather than one anchor spanning both lines, so the note between them can be
        # reworded without taking this mutant quietly to SKIPPED.
        (Q, REMOVE, ""),
        (Q, SHOW, SHOW + REMOVE)]),

    # UI/AutoQuestPopup.lua records this global raising on a popup already retired, and the
    # line above retires one.
    # Both call sites, separately: the line is only pushed for a COMPLETE quest, so skipping
    # the fill for exactly those removes the whole visible half of the feature.
    ("the full rebuild skips filling the lines of a finished quest", [
        (Q, "                fillLines(e, id)\n",
            "                if e.state ~= STATE.COMPLETE then fillLines(e, id) end\n")]),

    ("the cheap refresh skips filling the lines of a finished quest", [
        (Q, "\n        fillLines(e, id)\n",
            "\n        if e.state ~= STATE.COMPLETE then fillLines(e, id) end\n")]),

    ("the frame script wraps the handler and drops the client's upInside", [
        (R, 'r:SetScript("OnMouseUp", onMouseUp)\n',
            'r:SetScript("OnMouseUp", function(s, b) onMouseUp(s, b) end)\n')]),

    ("the reward window call is unprotected, so a raise reaches the row's mouse script", [
        (Q, SHOW, "    ShowQuestComplete(id)\n")]),

    ("a raising reward window is swallowed and still reported as handed in", [
        (Q, SHOW, "    pcall(ShowQuestComplete, id)\n")]),

    ("the hand-in stops asking for a repaint", [
        (Q, SHOW + NOTIFY, SHOW)]),

    # ------------------------------------------------------------------ the click paths
    # Anchored on code only, in two edits where a move is needed, so the note between the right
    # button branch and the hand-in can be reworded without taking these to SKIPPED.
    ("the plain click never hands in, so the reported bug is back", [
        (Q, TURNIN_CALL, "")]),

    ("the hand-in moves above the right-button branch, so a right click hands in", [
        (Q, TURNIN_CALL, ""),
        (Q, RIGHT_BRANCH, TURNIN_CALL + RIGHT_BRANCH)]),

    ("the plain click hands in and then super-tracks as well", [
        (Q, TURNIN_CALL, "    if not splitIcon then turnIn(self, entry.id) end\n")]),

    ("the plain click passes the entry where the id is expected", [
        (Q, TURNIN_CALL, "    if not splitIcon and turnIn(self, entry) then return end\n")]),

    ("the split title click never hands in", [
        (Q, OPENLOG_TURNIN, "function Quests:OnEntryOpenLog(entry)\n")]),

    ("the split title click hands in and then opens the log as well", [
        (Q, OPENLOG_TURNIN, "function Quests:OnEntryOpenLog(entry)\n"
                            "    turnIn(self, entry.id)\n")]),

    ("the menu's Open item hands a finished quest in instead of opening the log", [
        (Q, "        openQuestLog(entryID)\n", "        self:OnEntryOpenLog({ id = entryID })\n")]),

    ("the log opens on no quest", [
        (Q, "        QuestMapFrame_OpenToQuestDetails(id)\n",
            "        QuestMapFrame_OpenToQuestDetails()\n")]),

    # ------------------------------------------------------------------- UI/Row.lua routing
    ("the split title click stops reaching the provider", [
        (R, "        dispatch(row, \"OnEntryOpenLog\")\n", "")]),

    ("the same dispatch is commented out rather than deleted", [
        (R, "        dispatch(row, \"OnEntryOpenLog\")\n",
            "        -- dispatch(row, \"OnEntryOpenLog\")\n")]),

    ("the plain click stops reaching the provider", [
        (R, DISPATCH_CLICK, "")]),

    # ------------------------------------------------------------ UI/Row.lua click routing
    # A press dragged off the row used to count, and it can now open the reward window.
    ("a press released off the row counts as a click again", [
        (R, "    if upInside == false then return end\n", "")]),

    ("the cancel test is loosened, so a client that passes no upInside never clicks", [
        (R, "    if upInside == false then return end\n", "    if not upInside then return end\n")]),

    ("the release that ends a drag is no longer swallowed", [
        (R, "    if wasDragging then return end\n", "")]),

    ("the plain left click is refused before it reaches the provider", [
        (R, DISPATCH_CLICK,
            "    if button == \"LeftButton\" then return end\n" + DISPATCH_CLICK)]),

    ("the split title half answers the right button, so a right click hands in", [
        (R, "    if button == \"LeftButton\" and splitClickWanted(row) and not overIcon(row) then\n",
            "    if button == \"RightButton\" and splitClickWanted(row) and not overIcon(row) then\n")]),

    # With the button dropped, OnEntryClick reads nil as a left click and hands in on a right
    # click that opened no menu.
    ("the dispatch drops the button", [
        (R, "    provider[fnName](provider, row._entry, ...)\n",
            "    provider[fnName](provider, row._entry)\n")]),

    ("the split title click falls through and super-tracks as well", [
        (R, "        dispatch(row, \"OnEntryOpenLog\")\n        return\n",
            "        dispatch(row, \"OnEntryOpenLog\")\n")]),

    # ------------------------------------------------------- which half of a split click
    ("the icon half hands in, where Blizzard's POI button only super-tracks", [
        (Q, "    if not splitIcon and turnIn(self, entry.id) then return end\n",
            "    if turnIn(self, entry.id) then return end\n")]),

    ("the halves are swapped, so only the icon hands in", [
        (Q, "    if not splitIcon and turnIn(self, entry.id) then return end\n",
            "    if splitIcon and turnIn(self, entry.id) then return end\n")]),

    ("the row stops telling the provider which half was clicked", [
        (R, DISPATCH_CLICK,
            "    dispatch(row, \"OnEntryClick\", button)\n")]),

    # Without splitClickWanted the icon area reads as the icon half even with the option off,
    # and then the only click that hands in is gone.
    ("the icon half is judged on the cursor alone, ignoring the option", [
        (R, "    local splitIcon = button == \"LeftButton\" and splitClickWanted(row) and overIcon(row)\n",
            "    local splitIcon = button == \"LeftButton\" and overIcon(row)\n")]),

    # --------------------------------------------------- the state fillLines reads
    ("the full rebuild fills the lines before it writes the state", [
        (Q, "                e.addedAt   = fs\n                e.state     = questState(id)\n",
            "                e.addedAt   = fs\n"),
        (Q, "                fillLines(e, id)\n",
            "                fillLines(e, id)\n                e.state     = questState(id)\n")]),

    ("the cheap refresh fills the lines before it writes the state", [
        (Q, "        e.isFocused = (focused == id)\n        e.state     = questState(id)\n",
            "        e.isFocused = (focused == id)\n"),
        (Q, "        fillLines(e, id)\n    end\n    dirtyObjectives = false\n",
            "        fillLines(e, id)\n        e.state     = questState(id)\n"
            "    end\n    dirtyObjectives = false\n")]),

    # A memo of the miss pins a quest filled before GetInfo could describe it.
    ("isAutoComplete memoizes its answer, misses included", [
        (Q, INDEX + INFO + AUTO_RETURN,
            "    ns._autoMemo = ns._autoMemo or {}\n"
            "    if ns._autoMemo[id] ~= nil then return ns._autoMemo[id] end\n"
            + INDEX + INFO +
            "    ns._autoMemo[id] = (info and info.isAutoComplete) and true or false\n"
            "    return ns._autoMemo[id]\n")]),

    ("the ToggleQuestLog fallback is dropped", [
        (Q, "    elseif ToggleQuestLog then\n        ToggleQuestLog()\n", "")]),

    # ------------------------------------------ a click on the followed quest resends it (Forever)
    # Focus:Set passes over an unchanged quest, so without the resend an arrow TomTom removed on
    # arrival never comes back.
    ("a click on the followed quest no longer resends it", [
        (Q, "            if Focus then Focus:Resend() end\n", "")]),

    ("every click resends, so a new quest is announced before its own event", [
        (Q, "        if again then\n", "        if true then\n")]),

    ("the followed quest is read after the set, so every click looks like a repeat", [
        (Q, "        local again = superTrackedID() == entry.id\n",
            "        C_SuperTrack.SetSuperTrackedQuestID(entry.id)\n"
            "        local again = superTrackedID() == entry.id\n")]),

    ("the followed quest is compared with the entry table, so it never matches", [
        (Q, "        local again = superTrackedID() == entry.id\n",
            "        local again = superTrackedID() == entry\n")]),

    ("a missing Focus module raises inside the click", [
        (Q, "            if Focus then Focus:Resend() end\n", "            Focus:Resend()\n")]),

    ("superTrackedID asks for a getter the client may not have", [
        (Q, "    if not (ns.Has.SuperTrack and C_SuperTrack.GetSuperTrackedQuestID) then return nil end\n",
            "    if not ns.Has.SuperTrack then return nil end\n")]),

    # ------------------------------ Click a focused quest to unfocus it (2.2.0, retail and Forever)
    ("the option is ignored, so a click on the followed quest only ever resends", [
        (Q, "        if again and clickUnfocuses() then\n", "        if false then\n")]),

    ("the option unfocuses on every click, followed or not", [
        (Q, "        if again and clickUnfocuses() then\n", "        if clickUnfocuses() then\n")]),

    ("the option unfocuses the followed quest whether it is on or not", [
        (Q, "        if again and clickUnfocuses() then\n", "        if again then\n")]),

    ("the unfocus sets the clicked quest again instead of clearing", [
        (Q, "            C_SuperTrack.SetSuperTrackedQuestID(0)\n        else\n",
            "            C_SuperTrack.SetSuperTrackedQuestID(entry.id)\n        else\n")]),

    ("the unfocus also resends the quest it just dropped", [
        (Q, "            C_SuperTrack.SetSuperTrackedQuestID(0)\n        else\n",
            "            C_SuperTrack.SetSuperTrackedQuestID(0)\n"
            "            ns:GetModule(\"Focus\"):Resend()\n        else\n")]),

    ("the unfocus skips the repaint", [
        (Q, "            C_SuperTrack.SetSuperTrackedQuestID(0)\n        else\n",
            "            C_SuperTrack.SetSuperTrackedQuestID(0)\n            return\n        else\n")]),

    ("the option is read off the wrong key", [
        (Q, "    return (cfg and cfg.clickToUnfocus) == true\n",
            "    return (cfg and cfg.splitQuestClick) == true\n")]),

    ("the option is read inverted, so it unfocuses while unset", [
        (Q, "    return (cfg and cfg.clickToUnfocus) == true\n",
            "    return (cfg and cfg.clickToUnfocus) ~= true\n")]),

    ("the option raises with no DB module", [
        (Q, "    local cfg = DB and DB:Tracker()\n    return (cfg and cfg.clickToUnfocus) == true\n",
            "    local cfg = DB:Tracker()\n    return (cfg and cfg.clickToUnfocus) == true\n")]),

    ("the option raises with no saved tracker settings", [
        (Q, "    return (cfg and cfg.clickToUnfocus) == true\n",
            "    return cfg.clickToUnfocus == true\n")]),

    # ------------------------------------------- found by the pre-release scan's hand-breaks
    # A dot call hands DB:Tracker no self, a Lua error in game that a stub ignoring self passes.
    ("the option calls DB.Tracker with a dot", [
        (Q, "    local cfg = DB and DB:Tracker()\n    return (cfg and cfg.clickToUnfocus) == true\n",
            "    local cfg = DB and DB.Tracker()\n    return (cfg and cfg.clickToUnfocus) == true\n")]),

    ("the split click test calls DB.Tracker with a dot", [
        (R, "    local cfg = DB and DB:Tracker()\n    if not (cfg and cfg.splitQuestClick) then return false end\n",
            "    local cfg = DB and DB.Tracker()\n    if not (cfg and cfg.splitQuestClick) then return false end\n")]),

    ("the option also turns on with Split quest click", [
        (Q, "    return (cfg and cfg.clickToUnfocus) == true\n",
            "    return (cfg and (cfg.clickToUnfocus or cfg.splitQuestClick)) == true\n")]),

    ("the option also turns off when the accept option is off", [
        (Q, "    return (cfg and cfg.clickToUnfocus) == true\n",
            "    return (cfg and cfg.clickToUnfocus and cfg.focusAcceptedQuests ~= false) == true\n")]),

    ("a finished quest can never be unfocused", [
        (Q, "        if again and clickUnfocuses() then\n",
            "        if again and clickUnfocuses() and entry.state ~= STATE.COMPLETE then\n")]),

    ("only an active quest can be unfocused", [
        (Q, "        if again and clickUnfocuses() then\n",
            "        if again and clickUnfocuses() and entry.state == STATE.ACTIVE then\n")]),

    ("a stale entry still marked focused is cleared, dropping another quest's focus", [
        (Q, "        local again = superTrackedID() == entry.id\n",
            "        local again = entry.isFocused or superTrackedID() == entry.id\n")]),

    ("the followed test trusts the entry alone", [
        (Q, "        local again = superTrackedID() == entry.id\n",
            "        local again = entry.isFocused\n")]),

    ("the click focuses on Classic, where super-track reads false", [
        (Q, "    if ns.Has.SuperTrack then\n        local again",
            "    if ns.Has.SuperTrack ~= nil then\n        local again")]),

    # ------------------------------------------ found by the 2.2.0 fix pass's second scan
    ("a campaign quest is never unfocused by a click", [
        (Q, UNFOCUS_TEST, "        if again and clickUnfocuses() and entry.groupID ~= \"campaign\" then\n")]),

    ("an untracked quest shown with Show only tracked off is never unfocused", [
        (Q, UNFOCUS_TEST, "        if again and clickUnfocuses() and entry.isTracked ~= false then\n")]),

    ("a campaign-tagged quest is never unfocused", [
        (Q, UNFOCUS_TEST, "        if again and clickUnfocuses() and not (entry.tags and entry.tags.campaign) then\n")]),

    ("the quest click unfocuses only while Keep the focused quest solid is on", [
        (Q, "    return (cfg and cfg.clickToUnfocus) == true\n",
            "    return (cfg and cfg.clickToUnfocus and cfg.trackerAlphaFocus ~= false) == true\n")]),

    ("the icon half is judged for any button, so a right click over the icon carries it", [
        (R, SPLIT_ICON, "    local splitIcon = splitClickWanted(row) and overIcon(row)\n")]),

    ("the icon hit-test ignores the row's effective scale", [
        (R, CURSOR, "    local mx = GetCursorPosition()\n")]),

    ("the icon hit-test multiplies by the scale instead of dividing", [
        (R, CURSOR, "    local mx = GetCursorPosition() * (row:GetEffectiveScale() or 1)\n")]),

    ("the icon hit-test ignores whether the icon is shown, so an iconless row's left side is the icon", [
        (R, "    if not (ih and ih:IsShown()) then return false end\n", "    if not ih then return false end\n")]),

    ("the icon hit-test drops its nil-edge guard, raising on a row not laid out", [
        (R, "    if not iconRight then return false end\n", "")]),

    ("the icon's right edge itself counts as the title", [
        (R, "    return mx <= iconRight\n", "    return mx < iconRight\n")]),

    ("the icon reaches a pixel past its right edge", [
        (R, "    return mx <= iconRight\n", "    return mx <= iconRight + 1\n")]),

    ("the icon hit-test divides by the scale twice", [
        (R, CURSOR, "    local mx = GetCursorPosition() / (row:GetEffectiveScale() or 1) / (row:GetEffectiveScale() or 1)\n")]),

    ("split click is offered to any provider with a click, not only those that open a log", [
        (R, "    return (provider and provider.OnEntryOpenLog) and true or false\n",
            "    return (provider and provider.OnEntryClick) and true or false\n")]),

    # A correct rewrite the fixture once refused. Caught here is a fixture rejecting good code.
    ("EQUIVALENT: the quest click caches the DB module once at file load, as the game has one", [
        (Q, "local function clickUnfocuses()\n    local DB  = ns:GetModule(\"DB\")\n",
            "local DBM = ns:GetModule(\"DB\")\nlocal function clickUnfocuses()\n    local DB  = DBM\n")]),
]

SUMMARY = re.compile(r"^test_quest_turnin: (\d+) passed, (\d+) failed$")


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
