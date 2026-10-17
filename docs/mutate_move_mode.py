"""Prove docs/test_move_mode.lua actually discriminates, by breaking production on purpose one
change at a time and checking the harness notices.

    python -B docs/mutate_move_mode.py        (run from the repo root)

Why this exists: move mode is how a player finds out the tracker can be moved, and every way it
breaks is silent. A bar that never shows looks exactly like the old invisible strip, a bar that
never goes away sits over the tracker for good, a lock that leaves it up reads as the lock not
working, and a right-click that opens nothing looks like there is no menu at all. None of that
raises a Lua error.

Every mutation reintroduces a defect the harness is supposed to stand guard over. Any that still
reports "0 failed" is an assertion that does not discriminate, and the run exits 1 naming it. A
mutant marked EQUIVALENT is expected to survive and fails the run if caught. There are none.

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
HARNESS = "docs/test_move_mode.lua"

T = "UI/Tracker.lua"
C = "UI/Commands.lua"

SESSION_IF = "    if not locked and (startMove or f._wasLocked) then f._moveSession = true end\n"
APPLY_TAIL = "    f._wasLocked = locked\n    self:ApplyMoveMode()\n"
OPTIONS_READ = "    return (Options and Options.frame and Options.frame:IsShown()) and true or false\n"
GOLD = "        hint:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, f._dragHover and 0.55 or 0.35)\n"
WHITE_IF = "    elseif f._dragHover and not Tracker:IsLocked() then\n"
WHITE = "        hint:SetColorTexture(1, 1, 1, 0.15)\n"
SHOW_BAR = "    f.moveBar:SetShown(on)\n"
SHOW_OUTLINE = "    f.moveOutline:SetShown(on)\n"
LEFT_SORT = "    if cfg and cfg.showSortButton == true then x = x + HEADER_ICON_SZ + 3 end\n"
LEFT_FILTER = "    if pastFilter and cfg and cfg.showFilterButton == true then x = x + HEADER_ICON_SZ + 3 end\n"
LABEL_ICON = '        label:SetPoint("RIGHT", f._lastIcon, "LEFT", -4, 0)\n'
LABEL_EDGE = '        label:SetPoint("RIGHT", f.moveBar, "RIGHT", -4, 0)\n'
STORE = "    gen.lockTracker = locked and true or false\n"
SET_APPLY = "    self:ApplyLockState(not locked)\n"
SET_PRINT = '    ns:Print(locked and L["tracker locked."] or L["tracker unlocked."])\n'
SET_REFRESH = '    if Options and Options.RefreshIfShown then Options:RefreshIfShown("general") end\n'
OPEN_ROW = "            if not (Options.frame and Options.frame:IsShown()) then Options:Toggle() end\n"
MENU_TOGGLE = '        { text = locked and L["Unlock (allow moving)"] or L["Lock position"], onClick = function()\n'
MENU_GUARD = "    if not (Options and Options.ui) then return end\n    local locked = self:IsLocked()\n"
RIGHT_TEST = ('    if button ~= "RightButton" or Tracker:IsClickThrough() or not self:IsMouseOver()'
              ' then return end\n')
DRAG_UP = '    drag:SetScript("OnMouseUp", openFrameMenuOnRightUp)\n'
COG_UP = '    cog:SetScript("OnMouseUp", openFrameMenuOnRightUp)\n'
BAR_LEVEL = "    moveBar:SetFrameLevel(f:GetFrameLevel() + 11)\n"
BAR_HIDE = "    moveBar:Hide()\n    local done"
DONE_TEX = '    if Options and Options.ui then doneTex:SetTexture(Options.ui:Texture("check")) end\n'
DONE_CLICK = ('    done:SetScript("OnClick", function()\n        if Tracker:IsClickThrough() then return end\n'
              '        Tracker:SetLocked(true)\n')
OUTLINE_LEVEL = "    outline:SetFrameLevel(f:GetFrameLevel() + 20)\n"
EDGE = "        if side[3] then edge:SetWidth(1) else edge:SetHeight(1) end\n"
REBUILD = "    f.sortButton = sort\n    self:RebuildHeaderIcons()\n"
BAR_MAKE = '    local moveBar = CreateFrame("Frame", nil, f)\n'

MUTANTS = [
    # -------------------------------------------------------------------- the lock state
    ("a lock change never re-applies move mode", [
        (T, APPLY_TAIL, "    f._wasLocked = locked\n")]),

    ("the slash command's startMove is ignored", [
        (T, SESSION_IF, "    if not locked and f._wasLocked then f._moveSession = true end\n")]),

    ("an unlock after a lock no longer starts the session", [
        (T, SESSION_IF, "    if not locked and startMove then f._moveSession = true end\n")]),

    ("the last lock state is never kept", [
        (T, APPLY_TAIL, "    self:ApplyMoveMode()\n")]),

    ("the load-time apply starts the session, so the bar shows at every login", [
        (T, SESSION_IF, "    if not locked then f._moveSession = true end\n")]),

    # -------------------------------------------------------------------- when it shows
    ("move mode ignores the lock", [
        (T, "    if not f or self:IsLocked() then return false end\n", "    if not f then return false end\n")]),

    ("move mode ignores the session", [
        (T, "    if f._moveSession then return true end\n", "")]),

    ("move mode ignores the options window", [
        (T, OPTIONS_READ, "    return false\n")]),

    ("move mode reads the options window as always open", [
        (T, OPTIONS_READ, "    return true\n")]),

    ("move mode reads a field the options window does not have", [
        (T, OPTIONS_READ, "    return (Options and Options.frame and Options.frame.shown) and true or false\n")]),

    ("the bar is never shown or hidden", [
        (T, SHOW_BAR, "")]),

    ("the outline is never shown or hidden", [
        (T, SHOW_OUTLINE, "")]),

    ("move mode is applied without repainting the strip", [
        (T, SHOW_OUTLINE + "    paintDragHint(f)\n", SHOW_OUTLINE)]),

    # -------------------------------------------------------------------------- the tint
    ("the gold resting and hover alphas are swapped", [
        (T, GOLD, "        hint:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, f._dragHover and 0.35 or 0.55)\n")]),

    ("move mode paints the strip white", [
        (T, GOLD, "        hint:SetColorTexture(1, 1, 1, f._dragHover and 0.55 or 0.35)\n")]),

    ("a locked tracker takes the hover tint again", [
        (T, WHITE_IF, "    elseif f._dragHover then\n")]),

    ("the white hover tint is a different strength", [
        (T, WHITE, "        hint:SetColorTexture(1, 1, 1, 0.25)\n")]),

    ("the strip's tint is never stored on the tracker", [
        (T, "    f.dragHint = hint\n", "")]),

    ("a hover is never remembered", [
        (T, "        f._dragHover = true\n", "")]),

    ("leaving never forgets the hover", [
        (T, "        f._dragHover = nil\n", "")]),

    # ------------------------------------------------------------------------- the layout
    ("the check does not clear the sort button", [
        (T, LEFT_SORT, "    if cfg and cfg.showSortButton == true then x = x + HEADER_ICON_SZ end\n")]),

    ("any truthy sort setting moves the check", [
        (T, LEFT_SORT, "    if cfg and cfg.showSortButton then x = x + HEADER_ICON_SZ + 3 end\n")]),

    ("the check ignores the filter button", [
        (T, LEFT_FILTER, "")]),

    ("any truthy filter setting moves the check", [
        (T, LEFT_FILTER, "    if pastFilter and cfg and cfg.showFilterButton then x = x + HEADER_ICON_SZ + 3 end\n")]),

    ("the move bar is laid out as if the filter button were never there", [
        (T, "    local left = leftButtonX(ns:GetModule(\"DB\"):Tracker(), true)\n",
            "    local left = leftButtonX(ns:GetModule(\"DB\"):Tracker(), false)\n")]),

    ("the check's old anchor is never cleared", [
        (T, "    done:ClearAllPoints()\n", "")]),

    ("the label's old anchors are never cleared", [
        (T, "    label:ClearAllPoints()\n", "")]),

    ("the label runs into the leftmost icon", [
        (T, LABEL_ICON, '        label:SetPoint("RIGHT", f._lastIcon, "LEFT", 0, 0)\n')]),

    ("the label ignores the icons and runs to the edge", [
        (T, "    if f._lastIcon then\n", "    if false then\n")]),

    ("with no icon the label runs to the very edge", [
        (T, LABEL_EDGE, '        label:SetPoint("RIGHT", f.moveBar, "RIGHT", 0, 0)\n')]),

    # ------------------------------------------------------------------------ SetLocked
    ("SetLocked stores whatever it was handed", [
        (T, STORE, "    gen.lockTracker = locked\n")]),

    ("SetLocked never starts move mode on an unlock", [
        (T, SET_APPLY, "    self:ApplyLockState()\n")]),

    ("SetLocked says nothing", [
        (T, SET_PRINT, "")]),

    ("SetLocked says the opposite", [
        (T, SET_PRINT, '    ns:Print(locked and L["tracker unlocked."] or L["tracker locked."])\n')]),

    ("SetLocked never refreshes the General tab", [
        (T, SET_REFRESH, "")]),

    ("SetLocked refreshes the wrong tab", [
        (T, SET_REFRESH, '    if Options and Options.RefreshIfShown then Options:RefreshIfShown("tracker") end\n')]),

    ("SetLocked runs on with no profile", [
        (T, "    local gen = ns:GetModule(\"DB\"):General()\n    if not gen then return end\n    gen.lockTracker",
            "    local gen = ns:GetModule(\"DB\"):General() or {}\n    gen.lockTracker")]),

    # ---------------------------------------------------------------------------- the menu
    ("the menu offers the wrong half of lock and unlock", [
        (T, MENU_TOGGLE,
            '        { text = locked and L["Lock position"] or L["Unlock (allow moving)"], onClick = function()\n')]),

    ("the lock row sets the state it already has", [
        (T, "            Tracker:SetLocked(not locked)\n", "            Tracker:SetLocked(locked)\n")]),

    ("Reset never resets", [
        (T, "            Tracker:ResetPosition()\n            ns:Print", "            ns:Print")]),

    ("Reset says nothing", [
        (T, '            ns:Print(L["position and size reset."])\n', "")]),

    ("the options row is gone", [
        (T, '        { text = L["Open the options panel"], onClick = function()\n' + OPEN_ROW + "        end },\n", "")]),

    ("the options row closes a window already open", [(T, OPEN_ROW, "            Options:Toggle()\n")]),

    ("the options row never opens a closed window", [
        (T, OPEN_ROW, "            if Options.frame then Options.frame:Raise() end\n")]),

    ("the options row reads a field the window does not have", [
        (T, OPEN_ROW, "            if not (Options.frame and Options.frame.shown) then Options:Toggle() end\n")]),

    ("the options row hides a window already open", [
        (T, OPEN_ROW, "            if not (Options.frame and Options.frame:IsShown()) then Options:Toggle() else Options.frame:Hide() end\n")]),

    ("the options row does nothing before the window is first built", [
        (T, OPEN_ROW, "            if Options.frame and not Options.frame:IsShown() then Options:Toggle() end\n")]),

    ("the options row lifts an open window over its color picker", [
        (T, OPEN_ROW, "            if Options.frame and Options.frame:IsShown() then Options.frame:Raise() else Options:Toggle() end\n")]),

    ("the menu opens at the cursor, not on the frame", [
        (T, "    }, owner)\nend\n", "    })\nend\n")]),

    ("the menu runs with no library", [
        (T, MENU_GUARD, "    local locked = self:IsLocked()\n")]),

    ("a left release opens the menu too", [
        (T, RIGHT_TEST, '    if Tracker:IsClickThrough() or not self:IsMouseOver() then return end\n')]),

    ("a click-through tracker opens the menu", [
        (T, RIGHT_TEST, '    if button ~= "RightButton" or not self:IsMouseOver() then return end\n')]),

    ("a release dragged off the frame opens the menu", [
        (T, RIGHT_TEST, '    if button ~= "RightButton" or Tracker:IsClickThrough() then return end\n')]),

    ("the menu is opened with no owner", [
        (T, "    Tracker:OpenFrameMenu(self)\nend\n", "    Tracker:OpenFrameMenu()\nend\n")]),

    ("the strip never answers a right-click", [
        (T, DRAG_UP, "")]),

    ("the cogwheel never answers a right-click", [
        (T, COG_UP, "")]),

    # --------------------------------------------------------------------------- the build
    ("the bar is built level with the icons", [
        (T, BAR_LEVEL, "    moveBar:SetFrameLevel(f:GetFrameLevel() + 10)\n")]),

    ("the bar takes the mouse, swallowing drags on the label", [
        (T, BAR_HIDE, "    moveBar:Hide()\n    moveBar:EnableMouse(true)\n    local done")]),

    ("the bar is built showing", [
        (T, BAR_HIDE, "    local done")]),

    ("the check uses the wrong texture", [
        (T, DONE_TEX, '    if Options and Options.ui then doneTex:SetTexture(Options.ui:Texture("close")) end\n')]),

    ("the check is not tinted green", [
        (T, "    doneTex:SetVertexColor(0.45, 0.85, 0.35)\n", "")]),

    ("the check never locks", [
        (T, DONE_CLICK, '    done:SetScript("OnClick", function()\n        if Tracker:IsClickThrough() then return end\n')]),

    ("the check locks a click-through tracker", [
        (T, DONE_CLICK, '    done:SetScript("OnClick", function()\n        Tracker:SetLocked(true)\n')]),

    ("the check's tooltip names the wrong control", [
        (T, '        tip:AddLine(L["Lock tracker"])\n', '        tip:AddLine(L["Lock position"])\n')]),

    ("the label wraps", [
        (T, "    label:SetWordWrap(false)\n", "")]),

    ("the label is English everywhere", [
        (T, '    label:SetText(L["Drag to move, corner grip to resize."])\n',
            '    label:SetText("Drag to move, corner grip to resize.")\n')]),

    ("the label is left-aligned", [
        (T, '    label:SetJustifyH("CENTER")\n', '    label:SetJustifyH("LEFT")\n')]),

    ("the outline is drawn under the rows", [
        (T, OUTLINE_LEVEL, "    outline:SetFrameLevel(f:GetFrameLevel() + 1)\n")]),

    ("the outline is built showing", [
        (T, "    outline:Hide()\n", "")]),

    ("the outline's edges are filled the wrong way", [
        (T, EDGE, "        if side[3] then edge:SetHeight(1) else edge:SetWidth(1) end\n")]),

    ("the outline is faint", [
        (T, "        edge:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 0.9)\n",
            "        edge:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 0.3)\n")]),

    ("the header pass runs before the bar exists", [
        (T, REBUILD, "    f.sortButton = sort\n"),
        (T, BAR_MAKE, "    self:RebuildHeaderIcons()\n" + BAR_MAKE)]),

    # ------------------------------------------------------------------- the slash command
    ("/eqot unlock no longer opens move mode on an unlocked tracker", [
        (C, "    tracker():ApplyLockState(true)\n", "    tracker():ApplyLockState()\n")]),

    # Scan 1 (2026-10-16).
    ("the Lock/Unlock row carries a check the library refuses on a plain row", [
        (T, '        { text = locked and L["Unlock (allow moving)"] or L["Lock position"], onClick = function()\n',
            '        { text = locked and L["Unlock (allow moving)"] or L["Lock position"], checked = locked, onClick = function()\n')]),

    ("BuildFrame never applies the saved lock", [
        (T, "    self:ApplyWorldQuestsPosition()\n    self:ApplyLockState()\nend\n", "    self:ApplyWorldQuestsPosition()\nend\n")]),

    ("a middle-button release opens the menu", [
        (T, '    if button ~= "RightButton" or Tracker:IsClickThrough() or not self:IsMouseOver() then return end\n',
            '    if button == "LeftButton" or Tracker:IsClickThrough() or not self:IsMouseOver() then return end\n')]),
]

SUMMARY = re.compile(r"^test_move_mode: (\d+) passed, (\d+) failed$")


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
