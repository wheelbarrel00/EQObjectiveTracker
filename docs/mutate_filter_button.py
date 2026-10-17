"""Prove docs/test_filter_button.lua actually discriminates, by breaking production on purpose one
change at a time and checking the harness notices.

    python -B docs/mutate_filter_button.py        (run from the repo root)

Why this exists: the filter button's failures are quiet. A row that writes the wrong key hides a
category the player never touched, a funnel that stays white hides the reason quests are missing,
a menu that offers a category no provider can produce is a dead box, and a row the library does
not accept raises only when the menu opens. None of that shows up until someone clicks.

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
HARNESS = "docs/test_filter_button.lua"

T = "UI/Tracker.lua"
O = "Options/TabTracker.lua"

ZONE_ACTIVE = "    if f.onlyCurrentZone == true then return true end\n"
CAT_ACTIVE = "        if f[c.key] == false and ((not c.tag) or Registry:HasTag(c.tag)) then return true end\n"
ACTIVE_GUARD = "    if not (Filter and Registry) then return false end\n"
PAINT_CACHE = "    if b._active == active then return end\n    b._active = active\n"
PAINT = "    if active then b.icon:SetVertexColor(GOLD_R, GOLD_G, GOLD_B) else b.icon:SetVertexColor(1, 1, 1) end\n"
MENU_GUARD = ("    if not (Options and Options.ui and Options.FILTER_ORDER and cfg and cfg.filters and Filter"
              " and Registry) then\n")
CHANGED = ("        Tracker:PaintFilterButton()\n        Tracker:Render()\n"
           "        Options:RefreshIfShown(\"tracker\")\n")
ZONE_ROW = ('        { kind = "check", text = L["Show only quests in current zone"], checked = f.onlyCurrentZone == true,\n'
            '          onClick = function(on) f.onlyCurrentZone = on; changed() end },\n')
CAT_GATE = "        if c and ((not c.tag) or Registry:HasTag(c.tag)) then\n"
CAT_ROW = ('            items[#items + 1] = { kind = "check", text = c.label, checked = f[key] ~= false,\n'
           '                                  onClick = function(on) f[key] = on; changed() end }\n')
RESET_ROW = ('    items[#items + 1] = { text = L["Reset filters to defaults"], onClick = function()\n'
             '        Options:ResetFilters()\n        changed()\n')
SHOWN = "        filter:SetShown(cfg ~= nil and cfg.showFilterButton == true)\n"
PLACE = '        filter:SetPoint("TOPLEFT", f, "TOPLEFT", leftButtonX(cfg, false), -1)\n'
LEFT_FILTER = "    if pastFilter and cfg and cfg.showFilterButton == true then x = x + HEADER_ICON_SZ + 3 end\n"
BUILD = ('    local filter = makeHeaderIcon(f, "Interface\\\\AddOns\\\\EQObjectiveTracker\\\\Media\\\\Textures\\\\filter.tga",\n'
         '        L["Filters"], function(b) Tracker:OpenFilterMenu(b) end, "ANCHOR_BOTTOMRIGHT")\n')
RESET_FN = ("    for i = 1, #cats do f[cats[i].key] = true end\n    f.onlyCurrentZone = false\n"
            "    f.campaignAnyZone = false\n")

MUTANTS = [
    # ---------------------------------------------------------------------------- FilterActive
    ("the zone filter does not count as active", [
        (T, ZONE_ACTIVE, "")]),

    ("an unset category counts as off", [
        (T, CAT_ACTIVE, "        if f[c.key] ~= true and ((not c.tag) or Registry:HasTag(c.tag)) then return true end\n")]),

    ("a category no provider produces counts as active", [
        (T, CAT_ACTIVE, "        if f[c.key] == false then return true end\n")]),

    ("the untagged Normal category never counts", [
        (T, CAT_ACTIVE, "        if f[c.key] == false and c.tag and Registry:HasTag(c.tag) then return true end\n")]),

    ("Always show campaign quests counts as active", [
        (T, ZONE_ACTIVE, "    if f.onlyCurrentZone == true or f.campaignAnyZone == true then return true end\n")]),

    ("no registry reads as active whenever a category is off", [
        (T, ACTIVE_GUARD, "    if not Filter then return false end\n    Registry = Registry or { HasTag = function() return true end }\n")]),

    # ------------------------------------------------------------------------ PaintFilterButton
    ("the funnel is never painted gold", [
        (T, PAINT, "    b.icon:SetVertexColor(1, 1, 1)\n")]),

    ("the funnel stays gold once turned", [
        (T, PAINT, "    if active then b.icon:SetVertexColor(GOLD_R, GOLD_G, GOLD_B) end\n")]),

    ("the funnel is painted on every render, state or no state", [
        (T, PAINT_CACHE, "    b._active = active\n")]),

    ("the remembered state is never kept, so it never repaints after the first", [
        (T, PAINT_CACHE, "    if b._active == active then return end\n")]),

    ("the funnel takes some other gold", [
        (T, "local GOLD_R, GOLD_G, GOLD_B = 0.92, 0.72, 0.02\n", "local GOLD_R, GOLD_G, GOLD_B = 1, 0.82, 0\n")]),

    # --------------------------------------------------------------------------- OpenFilterMenu
    ("the menu opens with no library", [
        (T, MENU_GUARD, "    if not (cfg and cfg.filters and Filter and Registry) then\n")]),

    ("the menu opens with no filters table", [
        (T, MENU_GUARD, "    if not (Options and Options.ui and Options.FILTER_ORDER and Filter and Registry) then\n")]),

    ("a tick never repaints the funnel", [
        (T, CHANGED, "        Tracker:Render()\n        Options:RefreshIfShown(\"tracker\")\n")]),

    ("a tick never redraws the tracker", [
        (T, CHANGED, "        Tracker:PaintFilterButton()\n        Options:RefreshIfShown(\"tracker\")\n")]),

    ("a tick never refreshes the Tracker tab", [
        (T, CHANGED, "        Tracker:PaintFilterButton()\n        Tracker:Render()\n")]),

    ("a tick refreshes the wrong tab", [
        (T, CHANGED, "        Tracker:PaintFilterButton()\n        Tracker:Render()\n"
                     "        Options:RefreshIfShown(\"appearance\")\n")]),

    ("the title is missing", [
        (T, '        { kind = "title", text = L["Filters"] },\n', "")]),

    ("the zone row is missing", [
        (T, ZONE_ROW, "")]),

    ("the zone row opens unticked whatever the filter says", [
        (T, "checked = f.onlyCurrentZone == true,\n", "checked = false,\n")]),

    ("the zone row writes Always show campaign quests", [
        (T, "          onClick = function(on) f.onlyCurrentZone = on; changed() end },\n",
            "          onClick = function(on) f.campaignAnyZone = on; changed() end },\n")]),

    ("the zone row stores without redrawing", [
        (T, "          onClick = function(on) f.onlyCurrentZone = on; changed() end },\n",
            "          onClick = function(on) f.onlyCurrentZone = on end },\n")]),

    ("the divider under the zone row is missing", [
        (T, "          onClick = function(on) f.onlyCurrentZone = on; changed() end },\n        { kind = \"divider\" },\n",
            "          onClick = function(on) f.onlyCurrentZone = on; changed() end },\n")]),

    ("every category is offered, produced or not", [
        (T, CAT_GATE, "        if c then\n")]),

    ("the untagged Normal category is never offered", [
        (T, CAT_GATE, "        if c and c.tag and Registry:HasTag(c.tag) then\n")]),

    ("the categories come in match order, not the card's", [
        (T, "    for _, key in ipairs(Options.FILTER_ORDER) do\n",
            "    for _, key in ipairs({ \"showWorld\", \"showBonus\", \"showCampaign\", \"showDaily\", \"showWeekly\","
            " \"showScheduled\", \"showNormal\" }) do\n")]),

    ("a category row opens ticked only when it is exactly true", [
        (T, "checked = f[key] ~= false,\n", "checked = f[key] == true,\n")]),

    ("a category row writes the zone filter", [
        (T, "                                  onClick = function(on) f[key] = on; changed() end }\n",
            "                                  onClick = function(on) f.onlyCurrentZone = on; changed() end }\n")]),

    ("a category row stores the opposite", [
        (T, "                                  onClick = function(on) f[key] = on; changed() end }\n",
            "                                  onClick = function(on) f[key] = not on; changed() end }\n")]),

    ("a category row is a plain item that closes the menu", [
        (T, CAT_ROW, '            items[#items + 1] = { text = c.label, onClick = function() f[key] = not (f[key] ~= false); changed() end }\n')]),

    ("Reset never resets", [
        (T, RESET_ROW, '    items[#items + 1] = { text = L["Reset filters to defaults"], onClick = function()\n        changed()\n')]),

    ("Reset resets without redrawing", [
        (T, RESET_ROW, '    items[#items + 1] = { text = L["Reset filters to defaults"], onClick = function()\n'
                       '        Options:ResetFilters()\n')]),

    ("Reset is missing", [
        (T, '    items[#items + 1] = { text = L["Reset filters to defaults"], onClick = function()\n'
            '        Options:ResetFilters()\n        changed()\n    end }\n', "")]),

    ("the menu opens at the cursor, not on the button", [
        (T, "        changed()\n    end }\n    Options.ui:ShowMenu(items, owner)\n",
            "        changed()\n    end }\n    Options.ui:ShowMenu(items)\n")]),

    # ---------------------------------------------------------------------------- the header pass
    ("the funnel ships on", [
        (T, SHOWN, "        filter:SetShown(cfg ~= nil and cfg.showFilterButton ~= false)\n")]),

    ("any stored value that is not false shows the funnel", [
        (T, SHOWN, "        filter:SetShown(cfg ~= nil and cfg.showFilterButton and true or false)\n")]),

    ("the funnel is never shown or hidden", [
        (T, SHOWN, "")]),

    ("the funnel's old anchor is never cleared", [
        (T, "        filter:ClearAllPoints()\n", "")]),

    ("the funnel sits on the sort button", [
        (T, PLACE, '        filter:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -1)\n')]),

    ("the funnel sits past itself", [
        (T, PLACE, '        filter:SetPoint("TOPLEFT", f, "TOPLEFT", leftButtonX(cfg, true), -1)\n')]),

    ("the funnel sits at the sort button's height plus one", [
        (T, PLACE, '        filter:SetPoint("TOPLEFT", f, "TOPLEFT", leftButtonX(cfg, false), -2)\n')]),

    ("the filter offset counts the filter button for its own place", [
        (T, LEFT_FILTER, "    if cfg and cfg.showFilterButton == true then x = x + HEADER_ICON_SZ + 3 end\n")]),

    ("the header pass never paints the funnel", [
        (T, "        filter:SetPoint(\"TOPLEFT\", f, \"TOPLEFT\", leftButtonX(cfg, false), -1)\n        self:PaintFilterButton()\n",
            "        filter:SetPoint(\"TOPLEFT\", f, \"TOPLEFT\", leftButtonX(cfg, false), -1)\n")]),

    # ---------------------------------------------------------------------------- the build
    ("the funnel uses the sort texture", [
        (T, BUILD, BUILD.replace("filter.tga", "sort.tga"))]),

    ("the funnel's tooltip is English everywhere", [
        (T, BUILD, BUILD.replace('L["Filters"]', '"Filters"'))]),

    ("a click opens the sort menu", [
        (T, BUILD, BUILD.replace("Tracker:OpenFilterMenu(b)", "Tracker:OpenSortMenu(b)"))]),

    ("a click opens the menu with no owner", [
        (T, BUILD, BUILD.replace("Tracker:OpenFilterMenu(b)", "Tracker:OpenFilterMenu()"))]),

    ("the funnel's tooltip opens to the left", [
        (T, BUILD, BUILD.replace('"ANCHOR_BOTTOMRIGHT"', '"ANCHOR_BOTTOMLEFT"'))]),

    ("the funnel is never kept on the frame", [
        (T, "    f.filterButton = filter\n", "")]),

    ("a render never repaints the funnel", [
        (T, "    f._eqotPendingRender = nil\n    self:PaintFilterButton()\n", "    f._eqotPendingRender = nil\n")]),

    ("the icon helper never keeps its texture", [
        (T, "    b.icon = tex\n", "")]),

    # ---------------------------------------------------------------------------- the shared reset
    ("the shared reset leaves the categories alone", [
        (O, RESET_FN, "    f.onlyCurrentZone = false\n    f.campaignAnyZone = false\n")]),

    ("the shared reset leaves the zone filter on", [
        (O, RESET_FN, "    for i = 1, #cats do f[cats[i].key] = true end\n    f.campaignAnyZone = false\n")]),

    ("the card resets by itself instead of through the shared reset", [
        (O, "                Options:ResetFilters()\n                local f = DB().filters\n",
            "                local f = DB().filters\n                f.onlyCurrentZone = false\n")]),

    ("the menu reads its own order instead of the card's", [
        (O, "Options.FILTER_ORDER = FILTER_ORDER\n", "Options.FILTER_ORDER = { \"showNormal\" }\n")]),

    # Scan 1 (2026-10-16): what Reset filters may touch.
    ("Reset filters stops short of the last category", [
        (O, "    for i = 1, #cats do f[cats[i].key] = true end\n", "    for i = 1, #cats - 1 do f[cats[i].key] = true end\n")]),
    ("Reset filters also turns Show only tracked quests off", [
        (O, "    f.onlyCurrentZone = false\n    f.campaignAnyZone = false\nend\n",
            "    f.onlyCurrentZone = false\n    f.campaignAnyZone = false\n    DB().showOnlyWatched = false\nend\n")]),
]

SUMMARY = re.compile(r"^test_filter_button: (\d+) passed, (\d+) failed$")


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
