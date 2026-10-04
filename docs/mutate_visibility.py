"""Prove docs/test_visibility.lua actually discriminates, by breaking production on purpose one
change at a time and checking the harness notices.

    python docs/mutate_visibility.py        (run from the repo root)

Why this exists: UI/Visibility.lua owns the tracker frame's alpha, and every way it can get that
wrong is silent. The hide rules put the tracker at 0 and the opacity option (2026-09-27, for
Flamed_1984) puts a shown one anywhere from 0.1 to 1. Get the hide wrong and a tracker vanishes
for the session or renders through every fight. Get the fade wrong and it never comes back up
under the mouse, comes up over empty space, leaves the focused quest floating on screen alone
while the tracker is hidden, or touches a secure item button during combat lockdown.

test_visibility had no battery at all before this, one of five such harnesses. The fade's
mutants are the bulk of the list, and a handful cover the older hide interlock that the
harness header names.

Every mutation reintroduces a defect the harness is supposed to stand guard over. Any that still
reports "0 failed" is an assertion that does not discriminate, and the run exits 1 naming it.

WRITES TO THE TREE. It edits in place and restores through a finally, so an interrupted run still
puts the files back, and it verifies the restore and re-checks the baseline before reporting.
This checkout is junctioned into AddOns, so run it from a scratch copy while the game is open.

Anchors are exact source text and they rot. A SKIPPED line means an anchor stopped matching: fix
the anchor rather than dropping the mutant.
"""
import io
import re
import subprocess
import sys

LUA = r"C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe"
HARNESS = "docs/test_visibility.lua"

V = "UI/Visibility.lua"
T = "UI/Tracker.lua"
C = "UI/Commands.lua"
D = "Core/DB.lua"
A = "Options/TabAppearance.lua"

MOUSE_FIRST = "    if over(f.drag) or over(f.scenarioContainer) or over(f.eventsRegion) then return true end"
ROWS = "    if over(f.scroll) and over(f.content) then return true end"
BARS = "    if overBar(f.scroll) or overBar(f.eventsScroll) then return true end"
EXEMPT_ROW = "    local row = (visible and fadeLevel() < 1 and focusOn()) and focusRow or nil"
DRIVER_IF = "    if visible and fadeLevel() < 1 and hoverOn() then"
HOLD_IF = ("    if hoverOn() and (fade.over or (fade.leftAt and GetTime() - fade.leftAt < HOLD_TIME))"
           " then")
FADELINE_ARGS = '        :format(fadeLevel(), hoverOn() and "on" or "off", focusOn() and "on" or "off",'
WQ_REPORT = ("        y = y + Row:Render(row, entry, width, cfg) + gap\n"
             "        noteFocus(entry, row)\n")
SECTION_REPORT = ("                        y = y + Row:Render(row, entry, width, cfg) + gap\n"
                  "                        noteFocus(entry, row)\n")
REPORT = "        Visibility:SetFocus(focusRow, focusQuestID)\n"
TAIL = ('    local Visibility = ns:GetModule("Visibility")\n'
        "    if Visibility then\n" + REPORT +
        "        Visibility:SetQuestRows(questRows)\n"
        "    end\n")
SLIDER_SET = ("                DB().trackerAlpha = v / 100\n"
              '                ns:GetModule("Visibility"):ApplyFade()\n'
              "                syncFade()\n")

MUTANTS = [
    # --------------------------------------------------------------------------- the level
    ("the fade ignores its setting and the tracker is always solid", [
        (V, "    if not a or a >= 1 then return 1 end", "    if true then return 1 end")]),

    ("the floor is dropped, so a low setting makes the tracker nearly invisible", [
        (V, "    return math.max(MIN_ALPHA, a)", "    return a")]),

    ("the floor is raised above the lowest slider stop", [
        (V, "local MIN_ALPHA  = 0.1", "local MIN_ALPHA  = 0.2")]),

    ("the floor is lowered to zero", [
        (V, "local MIN_ALPHA  = 0.1", "local MIN_ALPHA  = 0")]),

    ("the mouseover option cannot be switched off", [
        (V, "    return not (t and t.trackerAlphaHover == false)", "    return true")]),

    ("the focused quest option cannot be switched off", [
        (V, "    return not (t and t.trackerAlphaFocus == false)", "    return true")]),

    # ------------------------------------------------------------------ what counts as hover
    ("the viewport alone counts, so empty space below the last quest brings it up", [
        (V, ROWS, "    if over(f.scroll) then return true end")]),

    ("content alone counts, so rows scrolled out of view bring it up", [
        (V, ROWS, "    if over(f.content) then return true end")]),

    ("the header strip does not count", [
        (V, MOUSE_FIRST,
            "    if over(f.scenarioContainer) or over(f.eventsRegion) then return true end")]),

    ("the scenario panel does not count", [
        (V, MOUSE_FIRST, "    if over(f.drag) or over(f.eventsRegion) then return true end")]),

    ("the world quest region does not count", [
        (V, MOUSE_FIRST, "    if over(f.drag) or over(f.scenarioContainer) then return true end")]),

    ("neither scroll bar counts", [
        (V, BARS, "    if false then return true end")]),

    ("only the quest list's scroll bar counts", [
        (V, BARS, "    if overBar(f.scroll) then return true end")]),

    ("only the world quest list's scroll bar counts", [
        (V, BARS, "    if overBar(f.eventsScroll) then return true end")]),

    ("a scroll bar under the lowercase key does not count", [
        (V, "    return sf ~= nil and over(sf.ScrollBar or sf.scrollBar)",
            "    return sf ~= nil and over(sf.ScrollBar)")]),

    ("the resize grip counts while the tracker is locked", [
        (V, "    return not (Tracker and Tracker:IsLocked())\n", "    return true\n")]),

    ("the resize grip never counts", [
        (V, "    if not over(f.grip) then return false end\n", "    do return false end\n")]),

    ("a hidden region still counts as hover", [
        (V, "    return r ~= nil and r:IsVisible() and r:IsMouseOver() and true or false",
            "    return r ~= nil and r:IsMouseOver() and true or false")]),

    # ---------------------------------------------------------------- the animation and hold
    ("leaving drops it at once, with no hold", [
        (V, HOLD_IF, "    if hoverOn() and fade.over then")]),

    ("the hold is doubled", [
        (V, "local HOLD_TIME  = 1\n", "local HOLD_TIME  = 2\n")]),

    ("the hold is halved", [
        (V, "local HOLD_TIME  = 1\n", "local HOLD_TIME  = 0.5\n")]),

    ("the fade snaps rather than animating", [
        (V, "    local step = elapsed / FADE_TIME", "    local step = 1")]),

    ("the fade takes twice as long", [
        (V, "local FADE_TIME  = 0.2", "local FADE_TIME  = 0.4")]),

    ("the mouse leaving is never noticed, so the hold never starts", [
        (V, "        if fade.over and not now then fade.leftAt = GetTime() end\n", "")]),

    ("hover is polled and thrown away", [
        (V, "        fade.over = now\n", "")]),

    ("a setting moved inside the hold waits the hold out", [
        (V, "    fade.leftAt = nil\n", "")]),

    ("settle returns the old level rather than the new one", [
        (V, "    fade.current = fadeTarget()\n    return fade.current", "    return fade.current")]),

    # ---------------------------------------------------------------------------- the driver
    ("the driver runs at 100 as well", [
        (V, DRIVER_IF, "    if visible and hoverOn() then")]),

    ("the driver runs with mouseover off", [
        (V, DRIVER_IF, "    if visible and fadeLevel() < 1 then")]),

    ("the driver keeps running while the tracker is hidden", [
        (V, DRIVER_IF, "    if fadeLevel() < 1 and hoverOn() then")]),

    ("a stopped driver is never started again", [
        (V, "        driver:Show()\n", "")]),

    ("a new driver frame is made every time", [
        (V, "        if not driver then\n            driver = CreateFrame",
            "        do\n            driver = CreateFrame")]),

    # ---------------------------------------------------------------------- the hide wins
    ("a hidden tracker shows at the faded level", [
        (V, "    f:SetAlpha(visible and settle(f) or 0)", "    f:SetAlpha(settle(f))")]),

    ("moving the slider repaints a hidden tracker", [
        (V, "    if visible then f:SetAlpha(settle(f)) end", "    f:SetAlpha(settle(f))")]),

    ("a visibility change no longer moves the exemption", [
        (V, "        Tracker:SetScrollInputSuspended(not visible)\n    end\n"
            "    syncDriver(visible)\n    syncExempt(visible)\nend\n",
            "        Tracker:SetScrollInputSuspended(not visible)\n    end\n"
            "    syncDriver(visible)\nend\n")]),

    # --------------------------------------------------------------------- the exemption
    ("the focused row is exempt at 100 too", [
        (V, EXEMPT_ROW, "    local row = (visible and focusOn()) and focusRow or nil")]),

    ("the focused row stays exempt while the tracker is hidden", [
        (V, EXEMPT_ROW, "    local row = (fadeLevel() < 1 and focusOn()) and focusRow or nil")]),

    ("the focused row is exempt with the option off", [
        (V, EXEMPT_ROW, "    local row = (visible and fadeLevel() < 1) and focusRow or nil")]),

    ("the item button is exempted in combat as well", [
        (V, "    if row and not inCombat() then", "    if row then")]),

    ("the item button is never exempted", [
        (V, "        button = IB and IB.buttons and IB.buttons[focusQuestID]",
            "        button = nil")]),

    ("the old row keeps its exemption when focus moves", [
        (V, "        if canExempt(exemptRow) then exemptRow:SetIgnoreParentAlpha(false) end\n", "")]),

    # Belt and braces behind the event order, which drops the button before the lockdown: no call
    # may reach the button while the lockdown is up.
    ("a render in lockdown drops the button it exempted", [
        (V, "    if exemptButton ~= button and not InCombatLockdown() then",
            "    if exemptButton ~= button then")]),

    ("the button waits for the event flag, so combat starts with it still exempt", [
        (V, "    if exemptButton ~= button and not InCombatLockdown() then",
            "    if exemptButton ~= button and not inCombat() then")]),

    ("the old button keeps its exemption", [
        (V, "        if canExempt(exemptButton) then exemptButton:SetIgnoreParentAlpha(false) end\n",
            "")]),

    ("a client without the call is assumed to have it", [
        (V, "    return r ~= nil and r.SetIgnoreParentAlpha ~= nil", "    return r ~= nil")]),

    # Both wait for OnEnable, so a module /eqot enable turns on without its reload never exempts a
    # secure button that no combat listener would drop.
    ("ApplyFade runs before OnEnable has", [
        (V, "function Visibility:ApplyFade()\n    if not self._started then return end\n",
            "function Visibility:ApplyFade()\n")]),

    ("SetFocus runs before OnEnable has", [
        (V, "function Visibility:SetFocus(row, questID)\n"
            "    if not self._started then return end\n",
            "function Visibility:SetFocus(row, questID)\n")]),

    ("OnEnable never marks the module started", [
        (V, "    self._started = true\n", "")]),

    ("ApplyFade answers the live switch again", [
        (V, "function Visibility:ApplyFade()\n    if not self._started then return end\n",
            "function Visibility:ApplyFade()\n"
            '    if ns:IsModuleDisabled("Visibility") then return end\n')]),

    ("SetFocus answers the live switch again", [
        (V, "function Visibility:SetFocus(row, questID)\n"
            "    if not self._started then return end\n",
            "function Visibility:SetFocus(row, questID)\n"
            '    if ns:IsModuleDisabled("Visibility") then return end\n')]),

    ("a render reporting focus while hidden exempts it anyway", [
        (V, "    syncExempt(f ~= nil and not f._eqotHidden)", "    syncExempt(true)")]),

    # ------------------------------------------------------------------------ the status line
    ("the status line swaps the two options", [
        (V, FADELINE_ARGS,
            '        :format(fadeLevel(), focusOn() and "on" or "off", hoverOn() and "on" or "off",')]),

    ("the status line reports the setting in place of the live alpha", [
        (V, "                fade.current, tostring(fade.over),",
            "                fadeLevel(), tostring(fade.over),")]),

    # ------------------------------------------------------------- the render side of focus
    ("the world quest loop never reports its focused row", [
        (T, WQ_REPORT, "        y = y + Row:Render(row, entry, width, cfg) + gap\n")]),

    ("the section loop never reports its focused row", [
        (T, SECTION_REPORT,
            "                        y = y + Row:Render(row, entry, width, cfg) + gap\n")]),

    ("a later focused entry replaces the first", [
        (T, "    if entry.isFocused and not focusRow then", "    if entry.isFocused then")]),

    ("every entry is recorded, focused or not", [
        (T, "    if entry.isFocused and not focusRow then", "    if not focusRow then")]),

    ("Render never clears the last pass's focus", [
        (T, "    focusRow, focusQuestID = nil, nil\n", "")]),

    ("Render never reports the focused row", [
        (T, REPORT, "")]),

    # Reported before Commit, the lookup reads a button this pass has not built or retired yet.
    # The whole block moves, so the block pin still passes and only the order check can see it.
    ("the focused row is reported before the item buttons settle", [
        (T, TAIL, ""),
        (T, "    ItemButtons:Commit()\n", TAIL + "    ItemButtons:Commit()\n")]),

    ("Render reports focus only while there is one, so losing focus never clears it", [
        (T, REPORT, "        if focusRow then\n    " + REPORT + "        end\n")]),

    ("/eqot status stops printing the fade line", [
        (C, '    debugLine("Visibility", nil, "FadeLine")\n', "")]),

    # ------------------------------------------------------------------ defaults and reset
    ("the tracker ships faded", [
        (D, "            trackerAlpha      = 1.0,", "            trackerAlpha      = 0.5,")]),

    ("mouseover ships off", [
        (D, "            trackerAlphaHover = true,", "            trackerAlphaHover = false,")]),

    ("the focused quest option ships off", [
        (D, "            trackerAlphaFocus = true,", "            trackerAlphaFocus = false,")]),

    ("Reset to Defaults leaves the three settings behind", [
        (D, '    "trackerAlpha", "trackerAlphaHover", "trackerAlphaFocus",\n', "")]),

    # ---------------------------------------------------------------------------- the panel
    ("the slider reaches zero", [
        (A, 'L["Tracker Opacity"], 10, 100, 5,', 'L["Tracker Opacity"], 0, 100, 5,')]),

    ("the slider stores a whole number where a fraction belongs", [
        (A, "                DB().trackerAlpha = v / 100\n", "                DB().trackerAlpha = v\n")]),

    ("the slider shows the stored fraction unscaled", [
        (A, "return math.floor((DB().trackerAlpha or 1) * 100 + 0.5) end,",
            "return math.floor((DB().trackerAlpha or 1) + 0.5) end,")]),

    ("the slider never applies what it stores", [
        (A, SLIDER_SET, "                DB().trackerAlpha = v / 100\n                syncFade()\n")]),

    ("the slider never re-dims the two boxes", [
        (A, SLIDER_SET,
            '                DB().trackerAlpha = v / 100\n'
            '                ns:GetModule("Visibility"):ApplyFade()\n')]),

    ("the mouseover box never applies", [
        (A, '                DB().trackerAlphaHover = v\n'
            '                ns:GetModule("Visibility"):ApplyFade()\n',
            "                DB().trackerAlphaHover = v\n")]),

    ("the focused quest box never applies", [
        (A, '                DB().trackerAlphaFocus = v\n'
            '                ns:GetModule("Visibility"):ApplyFade()\n',
            "                DB().trackerAlphaFocus = v\n")]),

    ("the boxes stay lit at 100", [
        (A, "            local faded = (DB().trackerAlpha or 1) < 1\n",
            "            local faded = (DB().trackerAlpha or 1) <= 1\n")]),

    ("only one box is swept", [
        (A, "            self:SetDependent(fadeFocus, faded)\n", "")]),

    ("the boxes are never dimmed when the tab is built", [
        (A, "        end\n        syncFade()\n\n        local bgRow = tracker:Add(",
            "        end\n\n        local bgRow = tracker:Add(")]),

    ("the focused-quest box is added below the background, out of the opacity group", [
        (A, "        tracker:Add(fadeFocus, DEPENDENT)\n", ""),
        (A, "        tracker:Add(w.borderThickSlider, DEPENDENT)\n",
            "        tracker:Add(fadeFocus, DEPENDENT)\n        tracker:Add(w.borderThickSlider, DEPENDENT)\n")]),

    ("the mouseover box is not indented under the slider", [
        (A, "        tracker:Add(fadeHover, DEPENDENT)\n", "        tracker:Add(fadeHover)\n")]),

    ("the boxes are indented by a table that indents nothing", [
        (A, "local DEPENDENT = { dependent = true }\n", "local DEPENDENT = {}\n")]),

    # ------------------------------------------------------------ the older hide interlock
    # The three cases the harness header names, plus the first-count guard and the pass owed on
    # coming back on screen.
    ("an uncounted log reads as empty and hides the tracker at every login", [
        (V, "    if g.hideWhenNoQuests and questRows == 0 ",
            "    if g.hideWhenNoQuests and (questRows or 0) == 0 ")]),

    ("every hide keeps rendering, not only the empty one", [
        (V, '    f._eqotRenderWhileHidden = ((hidden and why == "noquests")',
            "    f._eqotRenderWhileHidden = ((hidden)")]),

    ("the empty rule is tested first and takes the label from a combat hide", [
        (V, '    if g.hideWhenNoQuests and questRows == 0                            '
            'then return true, "noquests" end\n', ""),
        (V, "    if not g then return false end\n",
            "    if not g then return false end\n"
            '    if g.hideWhenNoQuests and questRows == 0 then return true, "noquests" end\n')]),

    ("the first count of a session may hide", [
        (V, "        firstCount = false\n        if n == 0 then return end\n",
            "        firstCount = false\n")]),

    ("coming back on screen asks for no render", [
        (V, "    if not hidden and (wasHidden or f._eqotPendingRender) then",
            "    if false then")]),

    # ------------------------------------------------- hand-broken in the 2026-09-27 scan
    ("settle never records the mouse as over", [
        (V, "    fade.over = fadeLevel() < 1 and hoverOn() and mouseOverDrawn(f)\n",
            "    fade.over = false\n")]),

    ("settle records hover even with mouseover off or at 100", [
        (V, "    fade.over = fadeLevel() < 1 and hoverOn() and mouseOverDrawn(f)\n",
            "    fade.over = mouseOverDrawn(f)\n")]),

    ("the animation moves fade.current but never paints the frame", [
        (V, "    fade.current = cur\n"
            "    f:SetAlpha(cur)\n",
            "    fade.current = cur\n")]),

    ("fading down is not clamped at the level (overshoots below the floor)", [
        (V, "else cur = math.max(target, cur - step) end",
            "else cur = cur - step end")]),

    ("fading up is not clamped at 1", [
        (V, "cur = math.min(target, cur + step) else",
            "cur = cur + step else")]),

    ("the hold is re-armed on every poll the mouse is away", [
        (V, "        if fade.over and not now then fade.leftAt = GetTime() end\n",
            "        if not now then fade.leftAt = GetTime() end\n")]),

    ("an absent mouseover key reads as off", [
        (V, "    return not (t and t.trackerAlphaHover == false)",
            "    return t and t.trackerAlphaHover == true")]),

    ("an absent focused-quest key reads as off", [
        (V, "    return not (t and t.trackerAlphaFocus == false)",
            "    return t and t.trackerAlphaFocus == true")]),

    ("tonumber dropped, a junk value compares a string", [
        (V, "    local a = t and tonumber(t.trackerAlpha)",
            "    local a = t and t.trackerAlpha")]),

    ("settle lands on the level even with the mouse over", [
        (V, "    fade.current = fadeTarget()\n"
            "    return fade.current",
            "    fade.current = fadeLevel()\n"
            "    return fade.current")]),

    ("the driver is never hidden once made", [
        (V, "    elseif driver then\n"
            "        driver:Hide()\n"
            "    end",
            "    end")]),

    ("the button exemption reads the client lockdown only, not the event flag", [
        (V, "    if row and not inCombat() then",
            "    if row and not InCombatLockdown() then")]),

    ("exemptRow is never recorded", [
        (V, "        if canExempt(row) then row:SetIgnoreParentAlpha(true) end\n"
            "        exemptRow = row\n",
            "        if canExempt(row) then row:SetIgnoreParentAlpha(true) end\n")]),

    ("exemptButton is never recorded", [
        (V, "        if canExempt(button) then button:SetIgnoreParentAlpha(true) end\n"
            "        exemptButton = button\n",
            "        if canExempt(button) then button:SetIgnoreParentAlpha(true) end\n")]),

    ("setVisible shows solid and never settles", [
        (V, "    f:SetAlpha(visible and settle(f) or 0)",
            "    f:SetAlpha(visible and 1 or 0)")]),

    ("ApplyFade asks IsShown instead of the hidden flag (alpha-hide path)", [
        (V, "    local visible = not f._eqotHidden\n",
            "    local visible = f:IsShown()\n")]),

    ("SetFocus asks IsShown instead of the hidden flag (alpha-hide path)", [
        (V, "    syncExempt(f ~= nil and not f._eqotHidden)",
            "    syncExempt(f ~= nil and f:IsShown())")]),

    ("SetFocus stores the row but not the quest id", [
        (V, "    focusRow, focusQuestID = row, questID\n",
            "    focusRow = row\n")]),

    ("FadeLine names the focused quest as exempt even when nothing is", [
        (V, "                exemptRow and tostring(focusQuestID) or \"none\",",
            "                tostring(focusQuestID),")]),

    ("FadeLine says item button yes whenever there is a focus", [
        (V, "                exemptButton and \"yes\" or \"no\",",
            "                focusQuestID and \"yes\" or \"no\",")]),

    ("FadeLine asks the focused row, not the frame, whether the client supports it", [
        (V, "                canExempt(f) and \"supported\" or \"unsupported\")",
            "                canExempt(focusRow) and \"supported\" or \"unsupported\")")]),

    ("PLAYER_REGEN_DISABLED applies BEFORE setting the combat flag", [
        (V, "    Events:On(\"PLAYER_REGEN_DISABLED\", function()\n"
            "        Visibility._inCombat = true\n"
            "        Visibility:Apply()\n"
            "    end)",
            "    Events:On(\"PLAYER_REGEN_DISABLED\", function()\n"
            "        Visibility:Apply()\n"
            "        Visibility._inCombat = true\n"
            "    end)")]),

    ("PLAYER_REGEN_DISABLED no longer applies at all", [
        (V, "    Events:On(\"PLAYER_REGEN_DISABLED\", function()\n"
            "        Visibility._inCombat = true\n"
            "        Visibility:Apply()\n"
            "    end)",
            "    Events:On(\"PLAYER_REGEN_DISABLED\", function()\n"
            "        Visibility._inCombat = true\n"
            "    end)")]),

    ("hover is polled ten times slower", [
        (V, "local HOVER_POLL = 0.05",
            "local HOVER_POLL = 0.5")]),

    ("ApplyFade no longer resyncs the exemption", [
        (V, "    if visible then f:SetAlpha(settle(f)) end\n"
            "    syncDriver(visible)\n"
            "    syncExempt(visible)\n"
            "end",
            "    if visible then f:SetAlpha(settle(f)) end\n"
            "    syncDriver(visible)\n"
            "end")]),

    ("ApplyFade no longer resyncs the driver", [
        (V, "    if visible then f:SetAlpha(settle(f)) end\n"
            "    syncDriver(visible)\n"
            "    syncExempt(visible)\n"
            "end",
            "    if visible then f:SetAlpha(settle(f)) end\n"
            "    syncExempt(visible)\n"
            "end")]),

    ("PLAYER_REGEN_ENABLED no longer applies, so the button is never re-exempted", [
        (V, "    Events:On(\"PLAYER_REGEN_ENABLED\", function()\n"
            "        Visibility._inCombat = false\n"
            "        Visibility:Apply()\n"
            "    end)",
            "    Events:On(\"PLAYER_REGEN_ENABLED\", function()\n"
            "        Visibility._inCombat = false\n"
            "    end)")]),

    ("a focus reported in combat keeps whatever button was exempt", [
        (V, "    local button\n"
            "    if row and not inCombat() then",
            "    local button = inCombat() and exemptButton or nil\n"
            "    if row and not inCombat() then")]),

    ("the section loop reports focus only for quests with an item", [
        (T, "                        if entry.hasItem then ItemButtons:Want(entry.id, row) end\n"
            "                        y = y + Row:Render(row, entry, width, cfg) + gap\n"
            "                        noteFocus(entry, row)\n",
            "                        if entry.hasItem then ItemButtons:Want(entry.id, row) end\n"
            "                        y = y + Row:Render(row, entry, width, cfg) + gap\n"
            "                        noteFocus(entry.hasItem and entry or {}, row)\n")]),

    ("the fade line is gated behind a capability that never exists", [
        (C, "    debugLine(\"Visibility\", nil, \"FadeLine\")\n",
            "    if ns.Has.IgnoreParentAlpha then\n"
            "    debugLine(\"Visibility\", nil, \"FadeLine\")\n"
            "    end\n")]),

    ("the opacity slider is added above Tracker Scale", [
        (A, "        tracker:Add(scaleSlider)\n", ""),
        (A, "        tracker:Add(fadeSlider)\n",
            "        tracker:Add(fadeSlider)\n        tracker:Add(scaleSlider)\n")]),

    ("the focused-quest box is added above the mouseover box", [
        (A, "        tracker:Add(fadeHover, DEPENDENT)\n", ""),
        (A, "        tracker:Add(fadeFocus, DEPENDENT)\n",
            "        tracker:Add(fadeFocus, DEPENDENT)\n        tracker:Add(fadeHover, DEPENDENT)\n")]),

    ("the slider re-dims the boxes but through a stale copy (syncFade before store)", [
        (A, "                DB().trackerAlpha = v / 100\n"
            "                ns:GetModule(\"Visibility\"):ApplyFade()\n"
            "                syncFade()\n",
            "                syncFade()\n"
            "                DB().trackerAlpha = v / 100\n"
            "                ns:GetModule(\"Visibility\"):ApplyFade()\n")]),

    # ------------------------------------------ hand-broken in the second 2026-09-27 scan
    ("the quest list's bar is read under its capitalized key only", [
        (V, "    if overBar(f.scroll) or overBar(f.eventsScroll) then return true end",
            "    if over(f.scroll.ScrollBar) or overBar(f.eventsScroll) then return true end")]),

    ("a second mouse-leave keeps the first leave's time, so it gets no hold", [
        (V, "        if fade.over and not now then fade.leftAt = GetTime() end\n",
            "        if fade.over and not now and not fade.leftAt then fade.leftAt = GetTime() end\n")]),

    ("inCombat reads only the event flag, so a reload mid-fight never hides", [
        (V, "    return InCombatLockdown() or Visibility._inCombat == true",
            "    return Visibility._inCombat == true")]),

    ("the row exemption keys on the live alpha, so a render under the mouse drops it", [
        (V, "    local row = (visible and fadeLevel() < 1 and focusOn()) and focusRow or nil",
            "    local row = (visible and fade.current < 1 and focusOn()) and focusRow or nil")]),

    ("syncExempt returns at once in lockdown, so a hide in combat leaves the row floating", [
        (V, "local function syncExempt(visible)\n",
            "local function syncExempt(visible)\n    if InCombatLockdown() then return end\n")]),

    ("the row swap is lockdown-guarded too, so a hide in combat leaves the row floating", [
        (V, "    if exemptRow ~= row then\n", "    if exemptRow ~= row and not InCombatLockdown() then\n")]),

    ("FadeLine prints the stored setting rather than the floored level", [
        (V, '        :format(fadeLevel(), hoverOn() and "on" or "off"',
            '        :format(tonumber((appearance() or {}).trackerAlpha) or 1, hoverOn() and "on" or "off"')]),

    ("SetFocus records focus before OnEnable ran, so a later toggle exempts it", [
        (V, "    if not self._started then return end\n    focusRow, focusQuestID = row, questID\n",
            "    focusRow, focusQuestID = row, questID\n    if not self._started then return end\n")]),

    ("the opacity keys sit in a list the reset never walks", [
        (D, '    "trackerAlpha", "trackerAlphaHover", "trackerAlphaFocus",\n', ""),
        (D, '    "showProgressBars", "showQuestProgressBars", "showScenarioProgressBars",\n}\n',
            '    "showProgressBars", "showQuestProgressBars", "showScenarioProgressBars",\n}\n'
            'DB.FADE_KEYS = {\n    "trackerAlpha", "trackerAlphaHover", "trackerAlphaFocus",\n}\n')]),
]

SUMMARY = re.compile(r"^test_visibility: (\d+) passed, (\d+) failed$")


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
