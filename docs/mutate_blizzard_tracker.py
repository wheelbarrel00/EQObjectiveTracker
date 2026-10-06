"""Prove docs/test_blizzard_tracker.lua actually discriminates, by breaking production on purpose
one change at a time and checking the harness notices.

    python -B docs/mutate_blizzard_tracker.py        (run from the repo root)

Why this exists: "Use Blizzard's quest tracker" is read once at login and changes what enables.
Most ways it can fail are silent - two trackers on screen, none at all, or a live half switch -
and nothing prints, because the one line that would (the bisection warning) must stay quiet.

THE MUTANT THAT EARNS IT moves the stand-down below the explicit enable in IsModuleDisabled. A
past /eqot bisection can leave enabledModules.Blizzard set, and the suppression would then hide
Blizzard's tracker under a window that was never built.

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
HARNESS = "docs/test_blizzard_tracker.lua"

I = "Core/Init.lua"
D = "Core/DB.lua"
A = "Core/API.lua"
TS = "Data/TrackedSet.lua"
QC = "Data/Providers/QuestsClassic.lua"
TR = "UI/Tracker.lua"
V = "UI/Visibility.lua"
C = "UI/Commands.lua"
G = "Options/TabGeneral.lua"
AT = "Data/AutoTrack.lua"
HUD = "UI/ScenarioBonusHUD.lua"
SB = "Data/ScenarioBonus.lua"
QX = "UI/QuestieCoexist.lua"
ZB = "UI/ZoneProgressBar.lua"
DLG = "UI/Dialog.lua"
DD ="Libs/EverythingUI/Dropdown.lua"

LIST1 = "    Blizzard = true, QuestLogChecks = true, QuestieCoexist = true,\n"
LIST3 = "    Widgets = true, WidgetBlock = true, Visibility = true,\n"
LIST4 = "    SuperTrackPersist = true, WatchPersist = true,\n"
STANDING = "    if self:IsStandingDown(name) then return true end\n"
ENABLED = "    if g and g.enabledModules and g.enabledModules[name] then return false end\n"
LOADER = ("            if ns:IsStandingDown(name) then\n"
          "                ns.stoodDown = (ns.stoodDown or 0) + 1\n"
          "            elseif ns:IsModuleDisabled(name) then\n")
LATCH = "    ns._blizzardTracker = (self.db.profile.general.useBlizzardTracker == true)\n"
DEBUG_GATE = '    if ns:IsStandingDown(name) or (WINDOW_ONLY[name] and ns:UsesBlizzardTracker()) then\n'
FRAME_TEST = '            local okShown, state = pcall(function() return f:IsShown() and "shown" or "hidden" end)\n'
FRAME_SHOWN = '            shown = okShown and state or "unreadable"\n'
WATCHED = '            (okCount and type(watched) == "number") and tostring(watched) or "?")\n'
ASK_SAVE = ('                local Dialog = ns:GetModule("Dialog")\n'
            "                if not Dialog then blizz:SetChecked(not v); return end\n")
ACCEPT = ('                        if ns:GetModule("API"):SetBlizzardTrackerSetting(v) then\n'
          "                            ReloadUI()\n")

MUTANTS = [
    # ------------------------------------------------------------------ what stands down
    ("the suppression keeps running, so Blizzard's tracker is hidden with no window over it", [
        (I, LIST1, "    QuestLogChecks = true, QuestieCoexist = true,\n")]),

    ("Classic's quest log click keeps feeding EQOT's set", [
        (I, LIST1, "    Blizzard = true, QuestieCoexist = true,\n")]),

    ("the Questie hider keeps running", [
        (I, LIST1, "    Blizzard = true, QuestLogChecks = true,\n")]),

    ("auto-track stands down, so Classic quests accepted meanwhile come back untracked", [
        (I, LIST1, "    Blizzard = true, QuestLogChecks = true, QuestieCoexist = true, AutoTrack = true,\n")]),

    ("Visibility keeps running", [
        (I, LIST3, "    Widgets = true, WidgetBlock = true,\n")]),

    ("the bonus objectives HUD doubles Blizzard's", [
        (I, "    ScenarioBonus = true, ScenarioBonusHUD = true, ScenarioSpells = true,\n",
            "    ScenarioBonus = true, ScenarioSpells = true,\n")]),

    ("world quest watches keep being restored behind Blizzard's tracker", [
        (I, LIST4, "    SuperTrackPersist = true,\n")]),

    ("Focus stands down, so Everything Quests loses its Forever arrow", [
        (I, LIST4, "    SuperTrackPersist = true, WatchPersist = true, Focus = true,\n")]),

    ("the quest sounds stand down, against the author's call", [
        (I, LIST4, "    SuperTrackPersist = true, WatchPersist = true, QuestSound = true,\n")]),

    # ------------------------------------------------------------------- the mode and the latch
    ("the mode reads on whenever the latch is set at all", [
        (I, "    return self._blizzardTracker == true\n", "    return self._blizzardTracker ~= nil\n")]),

    ("the mode is read live, so a setting change half switches the session", [
        (I, "    return self._blizzardTracker == true\n",
            "    return self.db ~= nil and self.db.profile.general.useBlizzardTracker == true\n")]),

    ("standing down ignores the mode, so EQOT's own window loses its modules", [
        (I, "    return self:UsesBlizzardTracker() and STAND_DOWN[name] == true\n",
            "    return STAND_DOWN[name] == true\n")]),

    ("IsModuleDisabled never asks, so render-driven checks see the module on", [
        (I, STANDING, "")]),

    ("a leftover explicit enable outranks the switch", [
        (I, STANDING, ""),
        (I, ENABLED, ENABLED + STANDING)]),

    ("providers keep running under Blizzard's tracker", [
        (I, "    if self:UsesBlizzardTracker() then return true end\n", "")]),

    ("the loader lists stood-down modules in the bisection warning", [
        (I, LOADER, "            if ns:IsModuleDisabled(name) then\n")]),

    ("the loader stops counting", [
        (I, "                ns.stoodDown = (ns.stoodDown or 0) + 1\n", "                ns.stoodDown = 1\n")]),

    ("the default flips on", [
        (D, "            useBlizzardTracker = false,\n", "            useBlizzardTracker = true,\n")]),

    ("the latch is never taken, so the switch does nothing", [
        (D, LATCH, "")]),

    # -------------------------------------------------------------------------------- the API
    ("the API reports the saved choice as the session", [
        (A, "    return ns:UsesBlizzardTracker()\n", "    return API:GetBlizzardTrackerSetting()\n")]),

    ("the API hands back whatever is stored", [
        (A, "    return (gen and gen.useBlizzardTracker == true) and true or false\n",
            "    return gen and gen.useBlizzardTracker\n")]),

    ("the API stores a nil as nil", [
        (A, "    gen.useBlizzardTracker = on and true or false\n", "    gen.useBlizzardTracker = on\n")]),

    ("the API reports no success", [
        (A, "    gen.useBlizzardTracker = on and true or false\n    return true\n",
            "    gen.useBlizzardTracker = on and true or false\n")]),

    # ---------------------------------------------------------------------- Classic's list
    ("TrackedSet leaves the marker on EQOT's window too", [
        (TS, "    if not ns:UsesBlizzardTracker() then return end\n", "")]),

    ("TrackedSet never leaves the marker", [
        (TS, "    if char then char.clearBlizzardWatches = true end\n", "")]),

    ("the clear-up walks forward over a shrinking list", [
        (QC, "    for i = (GetNumQuestWatches() or 0), 1, -1 do\n",
             "    for i = 1, (GetNumQuestWatches() or 0) do\n")]),

    ("the clear-up runs without the marker, untracking another addon's quests", [
        (QC, "    if not (char and char.clearBlizzardWatches) then return end\n",
             "    if not char then return end\n")]),

    ("the clear-up runs before the log has loaded", [
        (QC, '       or type(RemoveQuestWatch) ~= "function" or not GetQuestLogTitle(1) then return end\n',
             '       or type(RemoveQuestWatch) ~= "function" then return end\n')]),

    ("the marker is never cleared, so every login clears again", [
        (QC, "    char.clearBlizzardWatches = nil\n", "")]),

    ("QUEST_LOG_UPDATE no longer runs the clear-up", [
        (QC, '    Events:On("QUEST_LOG_UPDATE",        logUpdated)\n',
             '    Events:On("QUEST_LOG_UPDATE",        markDynamic)\n')]),

    ("the clear-up swallows the rebuild it rides on", [
        (QC, "        clearLeftoverWatches()\n        markDynamic()\n", "        clearLeftoverWatches()\n")]),

    # ------------------------------------------------------------------------- the window
    ("the tracker window is built anyway", [
        (TR, "    if ns:UsesBlizzardTracker() then return end\n    self:BuildFrame()\n",
             "    self:BuildFrame()\n")]),

    ("Visibility:Apply installs its map hook while standing down", [
        (V, '    if ns:IsStandingDown("Visibility") then return end\n', "")]),

    # ------------------------------------------------------------------------------- /eqot
    ("toggle reaches the tracker silently", [
        (C, "    if ns:UsesBlizzardTracker() then\n"
            "        ns:Print(L[\"Blizzard's quest tracker is in use - see /eqot, General.\"])\n"
            "        return\n"
            "    end\n", "")]),

    ("/eqot modules loses the stand-down wording", [
        (C, "        if standing then return \"off, Blizzard's tracker in use\" end\n", "")]),

    ("/eqot modules never flags a stood-down module", [
        (C, "                ns:IsStandingDown(name))))\n", "                false)))\n")]),

    ("/eqot modules never flags a provider", [
        (C, "                ns:UsesBlizzardTracker())))\n", "                false)))\n")]),

    ("/eqot status prints the saved choice as the session", [
        (C, "        ns:UsesBlizzardTracker() and \"Blizzard's\" or \"EQ Objective Tracker\",\n",
            "        (gen and gen.useBlizzardTracker == true) and \"Blizzard's\" or \"EQ Objective Tracker\",\n")]),

    ("/eqot status loses the count", [
        (C, "        ns.stoodDown or 0, frameState))\n", "        0, frameState))\n")]),

    # ---------------------------------------------------------------------------- the box
    ("the box saves before the player answers", [
        (G, ASK_SAVE, '                ns:GetModule("API"):SetBlizzardTrackerSetting(v)\n' + ASK_SAVE)]),

    ("Cancel leaves the box ticked", [
        (G, "                    onCancel = function() blizz:SetChecked(not v) end,\n", "")]),

    ("Yes saves but never reloads", [
        (G, ACCEPT, '                        if ns:GetModule("API"):SetBlizzardTrackerSetting(v) then\n')]),

    ("Yes saves the opposite", [
        (G, ACCEPT, '                        if ns:GetModule("API"):SetBlizzardTrackerSetting(not v) then\n'
                    "                            ReloadUI()\n")]),

    ("a refused write reloads anyway", [
        (G, ACCEPT, '                        ns:GetModule("API"):SetBlizzardTrackerSetting(v)\n'
                    "                        do\n"
                    "                            ReloadUI()\n")]),

    ("a refused write leaves the box ticked", [
        (G, "                        else\n                            blizz:SetChecked(not v)\n",
            "                        else\n")]),

    ("the dialog names the other addon", [
        (G, '                    title    = "EQ Objective Tracker",\n                    text     = v and',
            '                    title    = "Everything Quests",\n                    text     = v and')]),

    ("the dialog asks the wrong way round", [
        (G, "                    text     = v and L[", "                    text     = (not v) and L[")]),

    ("with no dialog the box stays ticked", [
        (G, "                if not Dialog then blizz:SetChecked(not v); return end\n",
            "                if not Dialog then return end\n")]),

    ("the box shows the session instead of the saved choice", [
        (G, '            function() return ns:GetModule("API"):GetBlizzardTrackerSetting() end,\n',
            "            function() return ns:UsesBlizzardTracker() end,\n")]),

    ("the box is never put in its card", [
        (G, "        general:Add(blizz)\n", "")]),

    ("Lock tracker heads the card and the box falls below it", [
        (G, "        general:Add(blizz)\n", ""),
        (G, "        general:Add(lock)\n", "        general:Add(lock)\n        general:Add(blizz)\n")]),

    ("the box goes in a second card instead of General", [
        (G, "        general:Add(blizz)\n",
            '        self:CreateGroup(content, L["Profiles"]):Add(blizz)\n')]),

    # ------------------------------------------------- found by the first scan, kept caught
    ("EQOT's own set keeps answering, so an older Everything Quests filters by a stale list", [
        (TS, "    if ns:UsesBlizzardTracker() then return nil end\n", "")]),

    ("auto-track adds manual watches behind Blizzard's own rules on retail", [
        (AT, "    if ns:UsesBlizzardTracker() then return end\n", "")]),

    ("auto-track skips Classic's own set too", [
        (AT, '    local TrackedSet = ns:GetModule("TrackedSet")\n    if TrackedSet then\n',
             '    local TrackedSet = ns:GetModule("TrackedSet")\n'
             "    if ns:UsesBlizzardTracker() then return end\n"
             "    if TrackedSet then\n")]),

    ("the bonus objectives HUD can be switched on beside Blizzard's", [
        (HUD, '    if not enabled() or ns:IsStandingDown("ScenarioBonusHUD") then\n',
              "    if not enabled() then\n")]),

    ("the HUD's test frame can never be taken down under Blizzard's tracker", [
        (HUD, "    if self._test then return end\n",
              '    if ns:IsStandingDown("ScenarioBonusHUD") then return end\n'
              "    if self._test then return end\n")]),

    ("the bonus model arms its delve events while standing down", [
        (SB, '    setDelveEvents(self:Enabled() and playerInDelve() and not ns:IsStandingDown("ScenarioBonus"))\n',
             "    setDelveEvents(self:Enabled() and playerInDelve())\n")]),

    ("the Questie hider still hides that tracker, leaving Classic with none", [
        (QX, '    if ns:IsStandingDown("QuestieCoexist") then return end\n', "")]),

    ("a docked zone bar vanishes with the tracker window", [
        (ZB, "    if ns:UsesBlizzardTracker() then return true end\n", "")]),

    ("/eqot status prints a stood-down module's own line, which reads as a fault", [
        (C, DEBUG_GATE +
            "        if method == \"DebugLine\" then ns:Print((\"%s: off, Blizzard's tracker in use\"):format(name)) end\n"
            "        return\n"
            "    end\n", "")]),

    ("/eqot status silences kept modules too", [
        (C, DEBUG_GATE, DEBUG_GATE.replace("ns:IsStandingDown(name) or", "ns:UsesBlizzardTracker() or"))]),

    ("/eqot status names a stood-down module once per line it has", [
        (C, "        if method == \"DebugLine\" then ns:Print(", "        if true then ns:Print(")]),

    ("/eqot status lets a stood-down module's other lines through", [
        (C, DEBUG_GATE + "        if method == \"DebugLine\" then ns:Print(",
            DEBUG_GATE.replace(" then\n", " and method == \"DebugLine\" then\n") + "        if true then ns:Print(")]),

    ("/eqot status prints the tracker window's lines for a window never built", [
        (C, DEBUG_GATE, "    if ns:IsStandingDown(name) then\n")]),

    ("/eqot status drops the tracker window's lines on EQOT's window too", [
        (C, DEBUG_GATE, DEBUG_GATE.replace("(WINDOW_ONLY[name] and ns:UsesBlizzardTracker())",
                                           "WINDOW_ONLY[name]"))]),

    ("/eqot status prints the item buttons' line, which reads as a fault with no window", [
        (C, "local WINDOW_ONLY = { Tracker = true, ItemButtons = true, ZoneGroups = true }\n",
            "local WINDOW_ONLY = { Tracker = true, ZoneGroups = true }\n")]),

    ("/eqot status prints the zone headers' line, which reads as nothing grouped with no feed", [
        (C, "local WINDOW_ONLY = { Tracker = true, ItemButtons = true, ZoneGroups = true }\n",
            "local WINDOW_ONLY = { Tracker = true, ItemButtons = true }\n")]),

    ("/eqot status never says whether Blizzard's frame is shown", [
        (C, "        ns.stoodDown or 0, frameState))\n", "        ns.stoodDown or 0, \"\"))\n")]),

    ("/eqot status looks only for Classic's frame", [
        (C, "        local f = _G.ObjectiveTrackerFrame or _G.QuestWatchFrame\n",
            "        local f = _G.QuestWatchFrame\n")]),

    ("/eqot status looks only for retail's frame, so Classic always reads absent", [
        (C, "        local f = _G.ObjectiveTrackerFrame or _G.QuestWatchFrame\n",
            "        local f = _G.ObjectiveTrackerFrame\n")]),

    ("/eqot status always reads Blizzard's frame as shown", [
        (C, FRAME_TEST, FRAME_TEST.replace("f:IsShown() and \"shown\" or \"hidden\"", "\"shown\""))]),

    ("/eqot status calls a hidden frame absent", [
        (C, FRAME_TEST, FRAME_TEST.replace("or \"hidden\" end)", "or \"absent\" end)"))]),

    ("/eqot status calls an unreadable frame hidden", [
        (C, FRAME_SHOWN, FRAME_SHOWN.replace("or \"unreadable\"", "or \"hidden\""))]),

    ("/eqot status reads the frame unprotected", [
        (C, FRAME_TEST, "            local okShown, state = true, (f:IsShown() and \"shown\" or \"hidden\")\n")]),

    ("/eqot status reads the frame without its self, so a client frame always reads unreadable", [
        (C, FRAME_TEST, FRAME_TEST.replace("f:IsShown()", "f.IsShown()"))]),

    ("/eqot status counts from C_QuestLog whenever the namespace exists, so Classic always reads ?", [
        (C, "        local countWatches = (C_QuestLog and C_QuestLog.GetNumQuestWatches) or _G.GetNumQuestWatches\n",
            "        local countWatches = (C_QuestLog or _G).GetNumQuestWatches\n")]),

    # The dialog itself moved to the EverythingUI library on 2026-10-02 with its 1.28 rules, and its
    # mutants with it (the library's tests/mutate.py). What stays here is the wrapper handing it on.
    ("the dialog loses its default title", [
        (DLG, '        title            = opts.title or "EQ Objective Tracker",\n',
              '        title            = opts.title,\n')]),

    ("a dialog with no button named gets none", [
        (DLG, '        button1          = opts.button1 or L["OK"],\n', '        button1          = opts.button1,\n')]),

    ("the dialog's text is dropped", [
        (DLG, '        text             = opts.text or "",\n', '        text             = "",\n')]),

    ("a confirm loses its second button", [
        (DLG, '        button2          = opts.button2,\n', '')]),

    ("Yes never reaches its callback, so nothing it confirms happens", [
        (DLG, '        onAccept         = opts.onAccept,\n', '')]),

    ("Cancel no longer reaches its callback", [
        (DLG, '        onCancel         = opts.onCancel,\n', '')]),

    ("New Profile and the copy-a-link popups lose their field", [
        (DLG, '        hasEditBox       = opts.hasEditBox and true or nil,\n', '')]),

    ("a link to copy opens with an empty field", [
        (DLG, '        editBoxText      = opts.editBoxText,\n', '')]),

    ("a link to copy opens unselected", [
        (DLG, '        highlightEditBox = opts.highlightEditBox and true or nil,\n', '')]),

    ("a field loses its letter limit", [
        (DLG, '        maxLetters       = opts.maxLetters,\n', '')]),

    ("the library's list picks after it hides, which blocks the profile switch's reload", [
        (DD, "            xpcall(function() onPick(opt.value) end, geterrorhandler())\n            p:Hide()\n",
             "            p:Hide()\n            xpcall(function() onPick(opt.value) end, geterrorhandler())\n")]),

    ("Yes leaves no hint when the reload is refused", [
        (G, "                            C_Timer.After(1, function()\n"
            "                                ns:Print(L[\"The interface did not reload. Type /reload to finish.\"])\n"
            "                            end)\n", "")]),

    ("the hint fires without waiting for the reload", [
        (G, "                            C_Timer.After(1, function()\n",
            "                            C_Timer.After(0, function()\n")]),

    ("the hint prints at once, before the reload can happen", [
        (G, "                            C_Timer.After(1, function()\n"
            "                                ns:Print(L[\"The interface did not reload. Type /reload to finish.\"])\n"
            "                            end)\n",
            "                            ns:Print(L[\"The interface did not reload. Type /reload to finish.\"])\n")]),

    ("Enable no longer installs the add hook, so Blizzard's five-watch cap comes back", [
        (QC, '    if type(AddQuestWatch) == "function" and type(RemoveQuestWatch) == "function" then\n',
             '    if false and type(AddQuestWatch) == "function" and type(RemoveQuestWatch) == "function" then\n')]),

    ("/eqot status drops the watch count", [
        (C, WATCHED, "            \"?\")\n")]),

    ("/eqot status prints whatever the count answered", [
        (C, WATCHED, "            okCount and tostring(watched) or \"?\")\n")]),

    ("/eqot status reads the bare count ahead of the namespaced one", [
        (C, "        local countWatches = (C_QuestLog and C_QuestLog.GetNumQuestWatches) or _G.GetNumQuestWatches\n",
            "        local countWatches = _G.GetNumQuestWatches or (C_QuestLog and C_QuestLog.GetNumQuestWatches)\n")]),

    ("/eqot status counts only on retail-shaped clients", [
        (C, "        local countWatches = (C_QuestLog and C_QuestLog.GetNumQuestWatches) or _G.GetNumQuestWatches\n",
            "        local countWatches = (C_QuestLog and C_QuestLog.GetNumQuestWatches)\n")]),

    ("/eqot status counts unprotected", [
        (C, "        if type(countWatches) == \"function\" then okCount, watched = pcall(countWatches) end\n",
            "        if type(countWatches) == \"function\" then okCount, watched = true, countWatches() end\n")]),

    ("the add hook untracks the quest in Questie again", [
        (QC, "            RemoveQuestWatch(index, true)\n", "            RemoveQuestWatch(index)\n")]),

    ("the add hook never releases its guard", [
        (QC, "            suppressWatchHook = false\n        end)\n", "        end)\n")]),

    ("the add hook bounces off another addon's add", [
        (QC, "            if suppressWatchHook then return end\n", "")]),

    ("the clear-up drops Questie's own-removal flag", [
        (QC, "        if index then RemoveQuestWatch(index, true) end\n",
             "        if index then RemoveQuestWatch(index) end\n")]),

    ("the clear-up assumes C_AddOns exists", [
        (QC, '    local loaded = (ns.Has.AddOns and C_AddOns.IsAddOnLoaded("Questie")) or Questie ~= nil\n',
             '    local loaded = C_AddOns.IsAddOnLoaded("Questie") or Questie ~= nil\n')]),

    ("/eqot enable all forgets what stays off", [
        (C, "                .. (ns:UsesBlizzardTracker()\n",
            "                .. (false\n")]),

    ("auto-track's status line no longer says why it left the watch list alone", [
        (AT, "    AutoTrack._lastAction = \"left alone, Blizzard's tracker in use\"\n"
             "    if ns:UsesBlizzardTracker() then return end\n",
             "    if ns:UsesBlizzardTracker() then return end\n")]),

    ("the clear-up marker waits for an OnEnable that safe mode skips", [
        (TS, "function TrackedSet:OnInitialize()\n", "function TrackedSet:OnEnable()\n")]),

    ("/eqot status builds a feed for a tracker that is not there", [
        (C, "    if not ns:UsesBlizzardTracker() then\n        ns:GetModule(\"Tracker\"):Render()\n",
            "    if true then\n        ns:GetModule(\"Tracker\"):Render()\n")]),

    ("/eqot status calls a provider unavailable on this client", [
        (C, "            ns:Print((\"  %-14s %s\"):format(p.id, ns:UsesBlizzardTracker()\n",
            "            ns:Print((\"  %-14s %s\"):format(p.id, false\n")]),

    ("/eqot enable promises a module it cannot bring back", [
        (C, "                ns:IsStandingDown(name) and \" It stays off while Blizzard's tracker is in use.\" or \"\"))\n",
            "                \"\"))\n")]),

    ("/eqot enable promises a provider it cannot bring back", [
        (C, "                ns:UsesBlizzardTracker() and \" It stays off while Blizzard's tracker is in use.\" or \"\"))\n",
            "                \"\"))\n")]),

    ("the clear-up untracks Questie's quests while its tracker runs", [
        (QC, "    if questieTrackerRuns() then return end\n", "")]),

    ("a Questie with its tracker off blocks the clear-up for good", [
        (QC, '    return not (type(profile) == "table" and profile.trackerEnabled == false)\n',
             "    return true\n")]),

    ("an unreadable Questie profile counts as its tracker off", [
        (QC, '    return not (type(profile) == "table" and profile.trackerEnabled == false)\n',
             '    return type(profile) == "table" and profile.trackerEnabled ~= false\n')]),

    ("the clear-up trusts only Questie's global, not its load state", [
        (QC, '    local loaded = (ns.Has.AddOns and C_AddOns.IsAddOnLoaded("Questie")) or Questie ~= nil\n',
             "    local loaded = Questie ~= nil\n")]),

    ("the clear-up trusts only Questie's load state, not its global", [
        (QC, '    local loaded = (ns.Has.AddOns and C_AddOns.IsAddOnLoaded("Questie")) or Questie ~= nil\n',
             '    local loaded = ns.Has.AddOns and C_AddOns.IsAddOnLoaded("Questie")\n')]),

    ("the log-loaded probe asks row 0", [
        (QC, "or not GetQuestLogTitle(1) then return end\n", "or not GetQuestLogTitle(0) then return end\n")]),

    ("the clear-up skips its count guard", [
        (QC, '    if type(GetNumQuestWatches) ~= "function" or type(GetQuestIndexForWatch) ~= "function"\n',
             '    if type(GetQuestIndexForWatch) ~= "function"\n')]),

    ("the clear-up skips its index guard", [
        (QC, '    if type(GetNumQuestWatches) ~= "function" or type(GetQuestIndexForWatch) ~= "function"\n',
             '    if type(GetNumQuestWatches) ~= "function"\n')]),

    # ------------------------------------------------------------------ DB accessors called with a dot
    # Each raises in game, and no harness drives these three lines with a DB that reads self.
    ("Render reads the profile with a dot call", [
        (TR, "    local cfg      = DB:Tracker()\n", "    local cfg      = DB.Tracker()\n")]),

    ("resetting the position reads the profile with a dot call", [
        (TR, "    local cfg = DB:Tracker()\n    local d   = DB.defaults.profile.tracker\n",
             "    local cfg = DB.Tracker()\n    local d   = DB.defaults.profile.tracker\n")]),

    ("the section order reads the profile with a dot call", [
        ("UI/Sections.lua", 'function Sections:Order()\n    local DB  = ns:GetModule("DB")\n    local cfg = DB and DB:Tracker()',
                            'function Sections:Order()\n    local DB  = ns:GetModule("DB")\n    local cfg = DB and DB.Tracker()')]),

    ("the title color status line reads the profile with a dot straight off GetModule", [
        ("UI/Row.lua", '    local cfg = ns:GetModule("DB"):Tracker()\n', '    local cfg = ns:GetModule("DB").Tracker()\n')]),

    ("the section order holds the DB module under another name and calls it with a dot", [
        ("UI/Sections.lua", 'function Sections:Order()\n    local DB  = ns:GetModule("DB")\n    local cfg = DB and DB:Tracker()',
                            'function Sections:Order()\n    local db  = ns:GetModule("DB")\n    local cfg = db and db.Tracker()')]),

    ("Render reads the profile through brackets", [
        (TR, "    local cfg      = DB:Tracker()\n", '    local cfg      = DB["Tracker"]()\n')]),

    ("the section order hands the DB module to a second local and calls that with a dot", [
        ("UI/Sections.lua", 'function Sections:Order()\n    local DB  = ns:GetModule("DB")\n    local cfg = DB and DB:Tracker()',
                            'function Sections:Order()\n    local DB  = ns:GetModule("DB")\n    local D = DB\n    local cfg = D and D.Tracker()')]),

    ("the section order takes the DB module in a multiple assignment", [
        ("UI/Sections.lua", 'function Sections:Order()\n    local DB  = ns:GetModule("DB")\n    local cfg = DB and DB:Tracker()',
                            'function Sections:Order()\n    local db, known0 = ns:GetModule("DB"), nil\n    local cfg = db and db.Tracker()')]),

    ("the section order takes the DB module with a fallback", [
        ("UI/Sections.lua", 'function Sections:Order()\n    local DB  = ns:GetModule("DB")\n    local cfg = DB and DB:Tracker()',
                            'function Sections:Order()\n    local db  = ns:GetModule("DB") or nil\n    local cfg = db and db.Tracker()')]),

    ("the section order takes the DB module on a line ending in a semicolon", [
        ("UI/Sections.lua", 'function Sections:Order()\n    local DB  = ns:GetModule("DB")\n    local cfg = DB and DB:Tracker()',
                            'function Sections:Order()\n    local db  = ns:GetModule("DB");\n    local cfg = db and db.Tracker()')]),
]

SUMMARY = re.compile(r"^test_blizzard_tracker: (\d+) passed, (\d+) failed$")


def run():
    """(verdict, note). verdict is "green", "failed" or "crashed".

    The harness's own summary line is matched rather than its exit code, because a mutant that
    does not parse exits nonzero too, and reporting that as caught is a false pass.
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
        # Asserted rather than assumed: a mutant applied to a file still holding the last one is a
        # silent no-op, and would report the previous result under this name.
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
