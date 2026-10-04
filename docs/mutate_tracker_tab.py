"""Prove docs/test_tracker_tab.lua actually discriminates, by breaking production on purpose one
change at a time and checking the harness notices.

    python docs/mutate_tracker_tab.py        (run from the repo root)

Why this exists: apart from the Filters card, nothing on the Tracker tab was driven by any
harness. The Section Order rows are relabeled in place on every move, the section show boxes
store the opposite of what they show, and the display boxes split into those that must
invalidate the rows and those that need only a redraw. Every way of getting one wrong is silent:
a chevron that moves the wrong way, a row that keeps naming the section that left it, a box that
never repaints a row already drawn.

Every mutation reintroduces a defect the harness is supposed to stand guard over. Any that still
reports "0 failed" is an assertion that does not discriminate, and the run exits 1 naming it.

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
HARNESS = "docs/test_tracker_tab.lua"

T = "Options/TabTracker.lua"
TR = "UI/Tracker.lua"

UP_CLICK = ("                r.up:SetScript(\"OnClick\", function()\n"
            "                    Sections:Move(id, -1)\n"
            "                    render()\n"
            "                    renderOrderRows()\n"
            "                    ns.Util.Tooltip():Hide()\n")
DOWN_CLICK = ("                r.down:SetScript(\"OnClick\", function()\n"
              "                    Sections:Move(id, 1)\n"
              "                    render()\n"
              "                    renderOrderRows()\n"
              "                    ns.Util.Tooltip():Hide()\n")

MUTANTS = [
    # ------------------------------------------------------------------- Section Order
    ("the Up chevron moves its section down", [
        (T, UP_CLICK, UP_CLICK.replace("Sections:Move(id, -1)", "Sections:Move(id, 1)"))]),

    ("the Down chevron moves its section up", [
        (T, DOWN_CLICK, DOWN_CLICK.replace("Sections:Move(id, 1)", "Sections:Move(id, -1)"))]),

    ("the Up chevron never redraws the tracker", [
        (T, UP_CLICK, UP_CLICK.replace("                    render()\n", ""))]),

    ("the Up chevron leaves the rows naming the old order", [
        (T, UP_CLICK, UP_CLICK.replace("                    renderOrderRows()\n", ""))]),

    ("the Down chevron leaves the rows naming the old order", [
        (T, DOWN_CLICK, DOWN_CLICK.replace("                    renderOrderRows()\n", ""))]),

    ("the Down chevron leaves a tooltip naming the section that moved", [
        (T, DOWN_CLICK, DOWN_CLICK.replace("                    ns.Util.Tooltip():Hide()\n", ""))]),

    ("the first section's Up chevron is live", [
        (T, "                r.up:SetEnabled(i > 1)", "                r.up:SetEnabled(true)")]),

    ("the last section's Down chevron is live", [
        (T, "                r.down:SetEnabled(i < #list)", "                r.down:SetEnabled(true)")]),

    ("the rows are never named", [
        (T, "                r.name:SetText(sectionLabel(id))\n", "")]),

    ("the chevrons never learn their section, so their tooltip names none", [
        (T, "                r.up.sectionID, r.down.sectionID = id, id\n", "")]),

    ("the up chevron is not flipped", [
        (T, "                    r.up = makeOrderArrow(self, content, true)",
            "                    r.up = makeOrderArrow(self, content, false)")]),

    ("the card is not laid out again after a move", [
        (T, "                orderRows[i].down:Hide()\n            end\n            order:Layout()\n",
            "                orderRows[i].down:Hide()\n            end\n")]),

    # ------------------------------------------------------------------- Tracker Visibility
    ("a section show box stores the opposite of what it shows", [
        (T, "                    function(v) Sections:SetHidden(id, not v); render() end,",
            "                    function(v) Sections:SetHidden(id, v); render() end,")]),

    ("a section show box never redraws the tracker", [
        (T, "                    function(v) Sections:SetHidden(id, not v); render() end,",
            "                    function(v) Sections:SetHidden(id, not v) end,")]),

    ("a section show box reads the hidden state as shown", [
        (T, "                    function() return not Sections:IsHidden(id) end,",
            "                    function() return Sections:IsHidden(id) end,")]),

    ("a box is built for a section the TOC never loaded", [
        (T, "            if liveSections[id] then\n", "            if true then\n")]),

    # ------------------------------------------------------------------- the Options card
    # The difficulty box became one choice of Quest Title Color on Appearance. These three put
    # back what its removal took away, or break the box that took its place in the card.
    ("the difficulty box comes back to this tab", [
        (T, "        local lvl = self:CreateCheckbox(content, L[\"Show quest level prefix\"],\n",
            "        display:Add(self:CreateCheckbox(content, L[\"Quest Title Color By Difficulty\"],\n"
            "            rowSetting(\"colorByDifficulty\", true)))\n"
            "        local lvl = self:CreateCheckbox(content, L[\"Show quest level prefix\"],\n")]),

    ("the tab grows a per-view pass again", [
        (T, "        -- beside the controls that style them - one feature, one place.\n    end,\n})\n",
            "        -- beside the controls that style them - one feature, one place.\n    end,\n"
            "    refresh = function() end,\n})\n")]),

    ("Keep section headers in view redraws before it re-anchors", [
        (T, "                DB().stickySectionHeaders = v\n"
            "                ns:GetModule(\"Tracker\"):ApplyWorldQuestsPosition()\n"
            "                render()\n",
            "                DB().stickySectionHeaders = v\n"
            "                render()\n"
            "                ns:GetModule(\"Tracker\"):ApplyWorldQuestsPosition()\n")]),

    ("Keep section headers in view never re-anchors the list", [
        (T, "                DB().stickySectionHeaders = v\n"
            "                ns:GetModule(\"Tracker\"):ApplyWorldQuestsPosition()\n",
            "                DB().stickySectionHeaders = v\n")]),

    ("Keep section headers in view stores the opposite of the box", [
        (T, "                DB().stickySectionHeaders = v\n",
            "                DB().stickySectionHeaders = not v\n")]),

    ("Keep section headers in view is indented under the count box", [
        (T, "            L[\"The header of the section you are scrolled into stays at the top of the quest list, so you can always see which section you are in. On by default.\"]))\n",
            "            L[\"The header of the section you are scrolled into stays at the top of the quest list, so you can always see which section you are in. On by default.\"]), { dependent = true })\n")]),

    ("the cogwheel box is stored but never applied", [
        (T, '                ns:GetModule("Tracker"):ApplyHeaderIcons()\n', "")]),

    ("the cogwheel box goes back to the label nobody could find", [
        (T, 'L["Show the options cogwheel on the tracker"]', 'L["Show Options icon on the tracker"]')]),

    ("a display box that changes how a row reads never invalidates the rows", [
        (T, '               DB()[key] = v\n               ns:GetModule("Row"):Invalidate()\n               render()\n',
            "               DB()[key] = v\n               render()\n")]),

    ("a display box that changes how a row reads never redraws", [
        (T, '               ns:GetModule("Row"):Invalidate()\n               render()\n',
            '               ns:GetModule("Row"):Invalidate()\n')]),

    ("a default-on display box reads off while unset", [
        (T, "               if defaultOn then return v ~= false end\n", "")]),

    ("a plain tracker box never redraws", [
        (T, "           function(v) DB()[key] = v; render() end\n",
            "           function(v) DB()[key] = v end\n")]),

    ("Show quest ID changes how rows read but no longer invalidates them", [
        (T, '            rowSetting("showQuestID"))', '            trackerSetting("showQuestID"))')]),

    ("Split quest click invalidates every row for nothing", [
        (T, '            trackerSetting("splitQuestClick"))', '            rowSetting("splitQuestClick"))')]),

    ("the section total box never redraws", [
        (T, "            function(v) DB().showQuestTotal = v; render() end,",
            "            function(v) DB().showQuestTotal = v end,")]),

    # ------------------------------------------------------------------- the sounds
    ("Quest Sound writes nothing", [
        (T, "            function(v) DB().questSoundEnabled = v end,", "            function() end,")]),

    ("Quest Sound reads off while unset", [
        (T, "            function() return DB().questSoundEnabled ~= false end,",
            "            function() return DB().questSoundEnabled == true end,")]),

    ("the accept sound switch reads on while unset, though it ships off", [
        (T, "            function() return DB().questAcceptSoundEnabled == true end,",
            "            function() return DB().questAcceptSoundEnabled ~= false end,")]),

    ("the turn-in sound switch writes nothing", [
        (T, "            function(v) DB().questTurnInSoundEnabled = v end,", "            function() end,")]),

    ("picking a complete sound no longer plays it", [
        (T, "            function(v) DB().questCompleteSound = v; playSound(v) end,",
            "            function(v) DB().questCompleteSound = v end,")]),

    ("picking an accept sound stores it under the complete sound", [
        (T, "            function(v) DB().questAcceptSound = v; playSound(v) end,",
            "            function(v) DB().questCompleteSound = v; playSound(v) end,")]),

    ("picking a turn-in sound no longer plays it", [
        (T, "            function(v) DB().questTurnInSound = v; playSound(v) end,",
            "            function(v) DB().questTurnInSound = v end,")]),

    ("the sound list hands over the label as the value", [
        (T, '                out[#out + 1] = { value = values[name] or "NONE", label = name }',
            '                out[#out + 1] = { value = name, label = name }')]),

    ("the complete sound picker loses its indent", [
        (T, '            L["Which sound plays when a quest becomes ready to turn in."],\n            nil, playSound), { dependent = true })',
            '            L["Which sound plays when a quest becomes ready to turn in."],\n            nil, playSound))')]),

    ("the turn-in sound picker loses its speaker", [
        (T, '            L["Which sound plays when you hand a quest in at the quest giver."],\n            nil, playSound), { dependent = true })',
            '            L["Which sound plays when you hand a quest in at the quest giver."],\n            nil, nil), { dependent = true })')]),
    # Sort Order and its Manual hint.
    ("the Manual hint never shows", [
        (T, '        manualHint:SetShown(value == "manual")', "        manualHint:SetShown(false)")]),

    ("the Manual hint shows for any order once one is picked", [
        (T, '        manualHint:SetShown(value == "manual")', "        manualHint:SetShown(value ~= nil)")]),

    ("the hint is never set at build, so it shows on every order", [
        (T, "        syncManualHint(DB().sortMode)\n", "")]),

    ("picking an order never sets the hint", [
        (T, "                syncManualHint(v)\n", "")]),

    ("the sort order is never stored", [
        (T, "                DB().sortMode = v\n", "")]),

    ("picking an order never redraws the tracker", [
        (T, "                DB().sortMode = v\n                render()\n", "                DB().sortMode = v\n")]),

    ("Sort Order reads nothing while unset", [
        (T, '            function() return DB().sortMode or "zone" end,', "            function() return DB().sortMode end,")]),

    ("the card is not laid out again when the hint shows", [
        (T, "        onScreen:Layout()\n", "")]),

    ("the tab is not measured again when the hint shows", [
        (T, "        self:MeasureContent(content)\n", "")]),

    ("the hint loses its indent", [
        (T, "        onScreen:Add(manualHint, { dependent = true, fill = true })",
            "        onScreen:Add(manualHint, { fill = true })")]),

    ("Sort Order is labeled in English", [
        (T, '        onScreen:Add(self:CreateRadioGroup(content, L["Sort Order"],',
            '        onScreen:Add(self:CreateRadioGroup(content, "Sort Order",')]),

    # Simplify tracked achievements.
    ("Simplify tracked achievements stores nothing", [
        (T, "                DB().simplifyGroups.achievements = v\n", "")]),

    ("Simplify tracked achievements wipes every other group", [
        (T, "                DB().simplifyGroups = DB().simplifyGroups or {}\n", "                DB().simplifyGroups = {}\n")]),

    ("Simplify tracked achievements never redraws", [
        (T, "                DB().simplifyGroups.achievements = v\n                render()\n",
            "                DB().simplifyGroups.achievements = v\n")]),

    ("Simplify tracked achievements reads on whenever any group is simplified", [
        (T, "            function() return DB().simplifyGroups and DB().simplifyGroups.achievements end,",
            "            function() return DB().simplifyGroups end,")]),

    # World Quests Position.
    ("World Quests Position does nothing", [
        (T, '            function(v) ns:GetModule("Tracker"):SetWorldQuestsPosition(v) end,', "            function() end,")]),

    ("World Quests Position reads Top while unset", [
        (T, '            function() return DB().worldQuestsPosition or "bottom" end,',
            '            function() return DB().worldQuestsPosition or "top" end,')]),

    ("World Quests Position shows where nothing has a world quest", [
        (T, "        if not hasWorldQuests then wqPos:Hide() end\n", "")]),

    # The World Quests height controls.
    ("the two World Quests sliders dim the wrong way round", [
        (T, "                self:SetDependent(wqHeightSlider, on)\n                self:SetDependent(wqMaxSlider, not on)",
            "                self:SetDependent(wqHeightSlider, not on)\n                self:SetDependent(wqMaxSlider, on)")]),

    ("the World Quests sliders are never dimmed at build", [
        (T, "            setWqHeightEnabled(DB().worldQuestsHeightOverride)\n", "")]),

    ("the height switch never dims the sliders again", [
        (T, "                    setWqHeightEnabled(v)\n", "")]),

    ("the height switch stores nothing", [
        (T, "                    DB().worldQuestsHeightOverride = v\n", "")]),

    ("the share is stored as a percent rather than a fraction", [
        (T, "                    DB().worldQuestsPinnedMaxFraction = v / 100", "                    DB().worldQuestsPinnedMaxFraction = v")]),

    ("the share slider shows a fraction", [
        (T, "            function() return (DB().worldQuestsPinnedMaxFraction or 0.40) * 100 end,",
            "            function() return DB().worldQuestsPinnedMaxFraction or 0.40 end,")]),

    ("the fixed height slider loses its indent", [
        (T, "            visibility:Add(wqHeightSlider, { dependent = true })", "            visibility:Add(wqHeightSlider)")]),

    ("the World Quests block is built where nothing has a world quest", [
        (T, "        if hasWorldQuests then\n            local autoWQ", "        if true then\n            local autoWQ")]),

    ("Keep section headers in view reads a misspelled key, so it always shows ticked", [
        (T, "            function() return DB().stickySectionHeaders ~= false end,",
            "            function() return DB().stickySectionHeader ~= false end,")]),

    ("Keep section headers in view reads an unset setting as off, against the shipped default", [
        (T, "            function() return DB().stickySectionHeaders ~= false end,",
            "            function() return DB().stickySectionHeaders == true end,")]),

    ("the cogwheel box reads a misspelled key, so it always shows ticked", [
        (T, "            function() return DB().showOptionsIcon ~= false end,",
            "            function() return DB().showOptionIcon ~= false end,")]),

    ("the cogwheel is built carrying a key the box never writes", [
        (TR, '    cog._dbKey = "showOptionsIcon"', '    cog._dbKey = "showOptionIcon"')]),

    ("the cogwheel's key line is commented out", [
        (TR, '    cog._dbKey = "showOptionsIcon"', '    -- cog._dbKey = "showOptionsIcon"')]),

    ("the cogwheel is left out of the icon run", [
        (TR, "    f.headerIcons = { cog }", "    f.headerIcons = {}")]),

    ("a rebuild drops the cogwheel along with the API icons", [
        (TR, "    for i = #f.headerIcons, 2, -1 do f.headerIcons[i] = nil end",
             "    for i = #f.headerIcons, 1, -1 do f.headerIcons[i] = nil end")]),

    ("the icons sit 3px apart the other way", [
        (TR, '                b:SetPoint("RIGHT", prev, "LEFT", -3, 0)', '                b:SetPoint("RIGHT", prev, "LEFT", 3, 0)')]),

    ("the cogwheel box redraws before it stores, so it toggles one click late", [
        (T, "                DB().showOptionsIcon = v\n                ns:GetModule(\"Tracker\"):ApplyHeaderIcons()\n",
            "                ns:GetModule(\"Tracker\"):ApplyHeaderIcons()\n                DB().showOptionsIcon = v\n")]),

    ("the header pass never hides an icon whose switch is off", [
        (TR, "        if cfg and b._dbKey and cfg[b._dbKey] == false then",
             "        if cfg and b._dbKey and cfg[b._dbKey] == nil then")]),
]

SUMMARY = re.compile(r"^test_tracker_tab: (\d+) passed, (\d+) failed$")


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
