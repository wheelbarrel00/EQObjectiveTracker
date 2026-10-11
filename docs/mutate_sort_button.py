"""Prove docs/test_sort_button.lua actually discriminates, by breaking production on purpose one
change at a time and checking the harness notices.

    python docs/mutate_sort_button.py        (run from the repo root)

Why this exists: the sort button (requested by Andreon, 2026-10-10) touches five files, and most
of the ways it can break are silent. A menu row that stores the wrong order, or stores it after the
redraw, leaves the list in the old order with nothing on screen to say why. A button the header
pass shows while unset ships the feature on. A tooltip read once at build names the order that was
current at login for the rest of the session. A refresh that ignores which tab is open makes the
options window jump tabs under the player. Anything taken from the Options module when the tracker
file loads is nil in game, since every TOC loads the tracker first. And since the header icon now
calls a function tooltip on each hover, an icon another addon registers keeps only a string.

Every mutation reintroduces a defect the harness is supposed to stand guard over. Any that still
reports "0 failed" is an assertion that does not discriminate, and the run exits 1 naming it.

The Tracker tab's box is test_tracker_tab.lua's, and its mutants are in mutate_tracker_tab.py.

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
HARNESS = "docs/test_sort_button.lua"

TR = "UI/Tracker.lua"
F = "Options/Frame.lua"
D = "Core/DB.lua"
TT = "Options/TabTracker.lua"
A = "Core/API.lua"

PICK = ('            local cfg = ns:GetModule("DB"):Tracker()\n'
        '            if not cfg then return end\n'
        '            cfg.sortMode = value\n'
        '            Tracker:Render()\n'
        '            Options:RefreshIfShown("tracker")\n')

MUTANTS = [
    # -------------------------------------------------------------- the header icon helper
    ("a function tooltip is shown as the function, never called", [
        (TR, '        if type(text) == "function" then text = text() end\n', "")]),

    ("a function tooltip is read once at build and kept for the session", [
        (TR, "    local b = CreateFrame(\"Button\", nil, f)\n    b:SetSize(HEADER_ICON_SZ, HEADER_ICON_SZ)\n",
             "    if type(tooltip) == \"function\" then tooltip = tooltip() end\n"
             "    local b = CreateFrame(\"Button\", nil, f)\n    b:SetSize(HEADER_ICON_SZ, HEADER_ICON_SZ)\n")]),

    ("the anchor given is ignored", [
        (TR, '        tip:SetOwner(btn, anchor or "ANCHOR_BOTTOMLEFT")\n', '        tip:SetOwner(btn, "ANCHOR_BOTTOMLEFT")\n')]),

    ("the cogwheel's tooltip moves to the other side", [
        (TR, '        tip:SetOwner(btn, anchor or "ANCHOR_BOTTOMLEFT")\n', '        tip:SetOwner(btn, anchor or "ANCHOR_BOTTOMRIGHT")\n')]),

    ("a tooltip that answers nothing still opens an empty tooltip", [
        (TR, "        if not text then return end\n        local tip = ns.Util.Tooltip()\n",
             "        local tip = ns.Util.Tooltip()\n")]),

    ("the handler is not handed the button, so the menu has no owner", [
        (TR, "        onClick(btn)\n", "        onClick()\n")]),

    ("a click on a click-through tracker still runs the handler", [
        (TR, '    b:SetScript("OnClick", function(btn)\n        if Tracker:IsClickThrough() then return end\n',
             '    b:SetScript("OnClick", function(btn)\n')]),

    ("a hover on a click-through tracker still lights the icon and opens the tooltip", [
        (TR, '    b:SetScript("OnEnter", function(btn)\n        if Tracker:IsClickThrough() then return end\n',
             '    b:SetScript("OnEnter", function(btn)\n')]),

    ("the icons sit level with the drag handle, which eats their clicks", [
        (TR, "    b:SetFrameLevel(f:GetFrameLevel() + 10)\n", "    b:SetFrameLevel(f:GetFrameLevel())\n")]),

    ("the icons start fully lit", [
        (TR, "    tex:SetTexture(texture)\n    tex:SetAlpha(0.85)\n", "    tex:SetTexture(texture)\n    tex:SetAlpha(1)\n")]),

    # ------------------------------------------------------------------------- SortLine
    ("an unset order is named as Title instead of Zone", [
        (TR, '    local mode = cfg and cfg.sortMode or "zone"\n', '    local mode = cfg and cfg.sortMode or "title"\n')]),

    ("the order is named by its stored value instead of its translated label", [
        (TR, "        if o.value == mode then name = o.label end\n", "        if o.value == mode then name = o.value end\n")]),

    ("every order is named as the first one in the list", [
        (TR, "        if o.value == mode then name = o.label end\n", "        if name == mode then name = o.label end\n")]),

    ("the tooltip's words are typed in English, so no language can translate them", [
        (TR, '    return L["Sort Order: %s"]:format(name)\n', '    return ("Sort Order: %s"):format(name)\n')]),

    ("SortLine reads the profile with a dot, which raises in game", [
        (TR, '    local cfg  = ns:GetModule("DB"):Tracker()\n', '    local cfg  = ns:GetModule("DB").Tracker()\n')]),

    ("the list is read from a field nobody sets", [
        (TR, "    return Options and Options.SORT_OPTIONS\n", "    return Options and Options.SORT\n")]),

    # UI/Tracker.lua loads before the Options module exists, so anything taken from it at load is nil.
    ("the list is taken once when the file loads", [
        (TR, "local function sortOptions()\n"
             "    local Options = ns:GetModule(\"Options\")\n"
             "    return Options and Options.SORT_OPTIONS\n"
             "end\n",
             "local SORT_LIST = (ns:GetModule(\"Options\") or {}).SORT_OPTIONS\n"
             "local function sortOptions()\n"
             "    return SORT_LIST\n"
             "end\n")]),

    ("the menu takes the Options module once when the file loads", [
        (TR, "function Tracker:OpenSortMenu(owner)\n    local Options = ns:GetModule(\"Options\")\n",
             "local OptionsAtLoad = ns:GetModule(\"Options\")\n"
             "function Tracker:OpenSortMenu(owner)\n    local Options = OptionsAtLoad\n")]),

    ("a TOC loads the Options files before the tracker", [
        ("EQObjectiveTracker_Vanilla.toc", "UI\\Tracker.lua\n", ""),
        ("EQObjectiveTracker_Vanilla.toc", "Options\\TabTracker.lua\n", "Options\\TabTracker.lua\nUI\\Tracker.lua\n")]),

    # ---------------------------------------------------------------------- OpenSortMenu
    ("the menu has no title naming the current order", [
        (TR, '    local items = { { kind = "title", text = self:SortLine() } }\n', "    local items = {}\n")]),

    ("the title is drawn as a row a player can click", [
        (TR, '    local items = { { kind = "title", text = self:SortLine() } }\n',
             "    local items = { { text = self:SortLine() } }\n")]),

    ("the menu is opened with no owner, so it outlives a hidden tracker", [
        (TR, "    Options.ui:ShowMenu(items, owner)\n", "    Options.ui:ShowMenu(items)\n")]),

    ("every row stores the last order in the list", [
        (TR, "            cfg.sortMode = value\n", "            cfg.sortMode = options[#options].value\n")]),

    ("a pick never redraws the tracker", [
        (TR, PICK, PICK.replace("            Tracker:Render()\n", ""))]),

    ("a pick never brings the Tracker tab up to date", [
        (TR, PICK, PICK.replace('            Options:RefreshIfShown("tracker")\n', ""))]),

    ("the Tracker tab is refreshed before the redraw", [
        (TR, PICK, PICK.replace('            Tracker:Render()\n            Options:RefreshIfShown("tracker")\n',
                                '            Options:RefreshIfShown("tracker")\n            Tracker:Render()\n'))]),

    ("the order is stored after the redraw, so the list draws the old one", [
        (TR, PICK, PICK.replace('            cfg.sortMode = value\n            Tracker:Render()\n',
                                '            Tracker:Render()\n            cfg.sortMode = value\n'))]),

    ("the refresh asks for the Appearance tab", [
        (TR, '            Options:RefreshIfShown("tracker")\n', '            Options:RefreshIfShown("appearance")\n')]),

    ("a row stores into the profile there when the menu opened", [
        (TR, '    local items = { { kind = "title", text = self:SortLine() } }\n',
             '    local items = { { kind = "title", text = self:SortLine() } }\n'
             '    local opened = ns:GetModule("DB"):Tracker()\n'),
        (TR, '            local cfg = ns:GetModule("DB"):Tracker()\n            if not cfg then return end\n',
             '            local cfg = opened\n            if not cfg then return end\n')]),

    ("a pick with no profile loaded raises", [
        (TR, "            if not cfg then return end\n            cfg.sortMode = value\n",
             "            cfg.sortMode = value\n")]),

    ("the menu opens with no library context and raises", [
        (TR, "    if not (options and Options.ui) then return end\n", "    if not options then return end\n")]),

    ("the menu opens with no list and raises", [
        (TR, "    if not (options and Options.ui) then return end\n", "    if not Options.ui then return end\n")]),

    # -------------------------------------------------------------------- the header pass
    ("the sort button ships on", [
        (TR, "cfg.showSortButton == true)", "cfg.showSortButton ~= false)")]),

    ("any stored value that is not false shows the button", [
        (TR, "cfg.showSortButton == true)", "cfg.showSortButton and true or false)")]),

    ("the header pass never hides or shows the sort button", [
        (TR, "    if f.sortButton then f.sortButton:SetShown(cfg ~= nil and cfg.showSortButton == true) end\n", "")]),

    ("a frame built without the button raises in the header pass", [
        (TR, "    if f.sortButton then f.sortButton:SetShown(", "    do f.sortButton:SetShown(")]),

    # ---------------------------------------------------------------------- the build
    ("the button sits at the top-right, over the cogwheel", [
        (TR, '    sort:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -1)\n', '    sort:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -1)\n')]),

    ("the button is never stored, so the header pass can never show it", [
        (TR, "    f.sortButton = sort\n", "")]),

    ("the button is built after the first header pass", [
        (TR, "    f.sortButton = sort\n    self:RebuildHeaderIcons()\n", "    self:RebuildHeaderIcons()\n    f.sortButton = sort\n")]),

    ("the button's texture names a file that is not there", [
        (TR, r'Textures\\sort.tga",', r'Textures\\sorting.tga",')]),

    ("the button's tooltip is fixed text rather than read on each hover", [
        (TR, "        function() return Tracker:SortLine() end, function(b) Tracker:OpenSortMenu(b) end,\n",
             "        Tracker:SortLine(), function(b) Tracker:OpenSortMenu(b) end,\n")]),

    ("the default is on", [
        (D, "            showSortButton       = false,\n", "            showSortButton       = true,\n")]),

    ("the default is gone, so the key reads nil", [
        (D, "            showSortButton       = false,\n", "")]),

    ("the Tracker tab no longer hands over its list", [
        (TT, "Options.SORT_OPTIONS = SORT_OPTIONS\n", "")]),

    # ------------------------------------------------------------------- RefreshIfShown
    ("a closed window is viewed again", [
        (F, "    if self.frame and self.frame:IsShown() and c and c.lastOptionsTab == id then ui:SelectTab(id) end\n",
            "    if self.frame and c and c.lastOptionsTab == id then ui:SelectTab(id) end\n")]),

    ("whatever tab is open is switched to the one asked for", [
        (F, "and c and c.lastOptionsTab == id then ui:SelectTab(id) end\n", "and c then ui:SelectTab(id) end\n")]),

    ("any saved tab counts as the one on screen", [
        (F, "c.lastOptionsTab == id then", "c.lastOptionsTab ~= nil then")]),

    ("a window never built raises", [
        (F, "    if self.frame and self.frame:IsShown() and", "    if self.frame:IsShown() and")]),

    ("no character settings raises", [
        (F, "self.frame:IsShown() and c and c.lastOptionsTab", "self.frame:IsShown() and c.lastOptionsTab")]),

    ("the character settings are read with a dot, which raises in game", [
        (F, '    local c = ns:GetModule("DB"):Char()\n    if self.frame', '    local c = ns:GetModule("DB").Char()\n    if self.frame')]),

    ("the tab is selected with a dot, which raises in game", [
        (F, "then ui:SelectTab(id) end\nend\n", "then ui.SelectTab(id) end\nend\n")]),

    # -------------------------------------------------------- the public API's header icons
    ("another addon's tooltip is passed through whatever it is", [
        (A, '        tooltip = type(spec.tooltip) == "string" and spec.tooltip or nil,\n', "        tooltip = spec.tooltip,\n")]),

    ("a tooltip is let through unless it is a function", [
        (A, 'tooltip = type(spec.tooltip) == "string" and spec.tooltip or nil,',
            'tooltip = type(spec.tooltip) ~= "function" and spec.tooltip or nil,')]),

    ("a table or boolean tooltip is let through", [
        (A, 'tooltip = type(spec.tooltip) == "string" and spec.tooltip or nil,',
            'tooltip = type(spec.tooltip) ~= "function" and type(spec.tooltip) ~= "number" and spec.tooltip or nil,')]),

    ("another addon's string tooltip is dropped too", [
        (A, '        tooltip = type(spec.tooltip) == "string" and spec.tooltip or nil,\n', "        tooltip = nil,\n")]),
]

SUMMARY = re.compile(r"^test_sort_button: (\d+) passed, (\d+) failed$")


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
