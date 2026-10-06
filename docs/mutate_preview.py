"""Prove docs/test_preview.lua actually discriminates, by breaking production on purpose one change
at a time and checking the harness notices.

    python docs/mutate_preview.py        (run from the repo root)

Why this exists: the Appearance preview draws a sample tracker with the tracker's own code, and its
failures are quiet. A sample row that answers the mouse can open a menu on a quest that does not
exist, or a click on a preview header collapses the player's real section. A row drawn through the
shared row pool is swept off the preview by the next tracker render. A view as tall as its content
hides the scroll bar the Scroll Bar card styles. The methods split out of shipped code for it (the
skins, a header outside the pool, a docked bar of its own) must leave the tracker's own paths as
they were. And the two values the tracker's Row and Sections record while drawing, the /eqot status
focus probe and the shared header height, must be the tracker's again once the preview has drawn.

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
HARNESS = "docs/test_preview.lua"

P = "UI/TrackerPreview.lua"
T = "UI/Tracker.lua"
S = "UI/Sections.lua"
Z = "UI/ZoneProgressBar.lua"

MUTANTS = [
    # --------------------------------------------------------------------------- the frame
    ("the preview builds again on every Build", [
        (P, "    if self.box then return end\n", "")]),
    ("the backdrop frame sits over the scroll frame", [
        (P, "    bg:SetFrameLevel(box:GetFrameLevel())\n", "    bg:SetFrameLevel(box:GetFrameLevel() + 5)\n")]),
    ("the background shows before any skin asks", [
        (P, "    self.background:Hide()\n", "")]),
    ("the preview scrolls with a plain frame, not the tracker's template", [
        (P, 'CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")', 'CreateFrame("ScrollFrame", nil, box)')]),
    ("the wheel does nothing", [
        (P, '    scroll:SetScript("OnMouseWheel", wheel)\n', "")]),
    ("the wheel scrolls past the end", [
        (P, "    sf:SetVerticalScroll(math.max(0, math.min(new, range)))", "    sf:SetVerticalScroll(math.max(0, new))")]),
    ("the wheel scrolls the wrong way", [
        (P, "(sf:GetVerticalScroll() or 0) - delta * WHEEL_STEP", "(sf:GetVerticalScroll() or 0) + delta * WHEEL_STEP")]),
    ("the track texture stands off its bar", [
        (P, '        barBG:SetPoint("TOPLEFT",     bar, "TOPLEFT",    -1, 0)', '        barBG:SetPoint("TOPLEFT",     bar, "TOPLEFT",    0, 0)')]),

    # --------------------------------------------------------------------------- the samples
    ("the campaign quest loses its tag, so the tint never shows", [
        (P, "                tags  = { campaign = true }, zone", "                zone")]),
    ("no sample is new", [
        (P, "                addedAt = time(), zone", "                zone")]),
    ("the progress bar sample is a plain line", [
        (P, 'kind = LINE.PROGRESSBAR, current = 45, required = 100', 'kind = LINE.OBJECTIVE, current = 45, required = 100')]),
    ("no sample is complete", [
        (P, "                state = STATE.COMPLETE, level = level - 4,", "                level = level - 4,")]),
    ("no sample is followed", [
        (P, '                isFocused = true, subtitle = "Northern Vale",', '                subtitle = "Northern Vale",')]),
    ("every sample is one level, so the difficulty colors all match", [
        (P, "                level = level + 3, zone", "                zone")]),
    ("the samples claim a provider of their own, so no quest-only title option reaches them", [
        (P, 'local e = { id = id, providerID = "quests",', 'local e = { id = id, providerID = "preview",')]),

    # --------------------------------------------------------------------------- the sections
    ("rows go through a fresh frame every refresh", [
        (P, "    if row then return row end\n", "")]),
    ("a sample row answers the mouse", [
        (P, "    row:EnableMouse(false)\n", "")]),
    ("a preview header collapses the player's section on a click", [
        (P, "    h:EnableMouse(false)\n    self.headers[groupID] = h\n", "    self.headers[groupID] = h\n")]),
    ("the repaint gate keeps a height measured while hidden", [
        (P, "                Row:Reset(row)\n", "")]),
    ("rows are drawn at the tracker's full width, over the scroll bar", [
        (P, "    local inner = math.max(1, width - Tracker:ScrollGutter(cfg))", "    local inner = width")]),
    ("the gap ignores Block Spacing", [
        (P, "    local gap   = Card:Gap(math.max(0, cfg.blockSpacing or 2), (Card:State(cfg)))", "    local gap   = 2")]),
    ("the header always counts with its total", [
        (P, "    local showTotal = cfg.showQuestTotal ~= false", "    local showTotal = true")]),
    ("a campaign section shows on a client with no campaign group", [
        (P, "        elseif samples[groupID] and declared[groupID] and not Sections:IsHidden(groupID) then",
            "        elseif samples[groupID] and not Sections:IsHidden(groupID) then")]),
    ("a section the player hid still shows", [
        (P, "        elseif samples[groupID] and declared[groupID] and not Sections:IsHidden(groupID) then",
            "        elseif samples[groupID] and declared[groupID] then")]),
    ("the header totals are dropped", [
        (P, "{ visibleCount = #list, totalCount = TOTALS[groupID] }", "{ visibleCount = #list, totalCount = #list }")]),
    ("a header is drawn collapsed", [
        (P, "                                   false, showTotal) + gap", "                                   true, showTotal) + gap")]),
    ("rows no longer drawn stay on screen", [
        (P, "    for id, row in pairs(self.rows) do if not drawnRows[id] then row:Hide() end end\n", "")]),
    ("headers no longer drawn stay on screen", [
        (P, "    for id, h in pairs(self.headers) do if not drawnHeaders[id] then h:Hide() end end\n", "")]),
    ("rows stack with no gap", [
        (P, "                    y = y + Row:Render(row, entry, inner - left, cfg) + gap", "                    y = y + Row:Render(row, entry, inner - left, cfg)")]),

    # --------------------------------------------------------------------------- the zone headers
    ("the samples sit in one zone", [
        (P, "                addedAt = time(), zone = \"Ashwood Glen\",", "                addedAt = time(), zone = \"Northern Vale\",")]),
    ("the preview draws zone headers with the option off", [
        (P, "    local Zones   = cfg.zoneHeaders and ns:GetModule(\"ZoneHeaders\") or nil", "    local Zones   = ns:GetModule(\"ZoneHeaders\")")]),
    ("every sample quest gets a zone of its own", [
        (P, "        local run = byZone[e.zone]\n", "        local run = nil\n")]),
    ("a preview zone header collapses a zone on a click", [
        (P, "    h:EnableMouse(false)\n    self.zoneHeads[key] = h\n", "    self.zoneHeads[key] = h\n")]),
    ("preview zone headers are made afresh every refresh", [
        (P, "    local h = self.zoneHeads[key]\n    if h then return h end\n", "    local h\n")]),
    ("no gap under a preview zone header", [
        (P, "y = y + Zones:Draw(self:ZoneHeader(key), content, groupID, run, y, cfg) + gap",
            "y = y + Zones:Draw(self:ZoneHeader(key), content, groupID, run, y, cfg)")]),
    ("the preview's rows are not indented under a zone", [
        (P, "                    left = Zones:Indent(cfg)\n", "")]),
    ("an indented preview row keeps the full width", [
        (P, "                    row:SetWidth(inner - left)\n", "                    row:SetWidth(inner)\n")]),
    ("an indented preview row is laid out at the full width", [
        (P, "Row:Render(row, entry, inner - left, cfg)", "Row:Render(row, entry, inner, cfg)")]),
    ("preview zone headers stay up once the option is off", [
        (P, "    for key, h in pairs(self.zoneHeads) do if not drawnZones[key] then h:Hide() end end\n", "")]),
    ("the preview hides every zone header it drew", [
        (P, "                    drawnZones[key] = true\n", "")]),
    ("the preview hides the zone headers it drew and keeps the rest", [
        (P, "if not drawnZones[key] then h:Hide() end", "if drawnZones[key] then h:Hide() end")]),
    ("the preview leaves its zone header height on the tracker's module", [
        (P, "    if Zones then Zones._h = keepZoneH end\n", "")]),

    # --------------------------------------------------------------------------- the zone section
    ("the zone section shows while the bar floats", [
        (P, "            if ZoneBar and ZoneBar:IsDocked() then", "            if ZoneBar then")]),
    ("the zone header keeps a count of 0", [
        (P, '                h.count:SetText(ZONE_DONE .. "/" .. ZONE_TOTAL)\n', "")]),
    ("a new zone bar every refresh", [
        (P, "                self.zoneBar = self.zoneBar or ZoneBar:BuildDockedBar(content)", "                self.zoneBar = ZoneBar:BuildDockedBar(content)")]),
    ("an undocked zone bar stays on screen", [
        (P, "    if self.zoneBar and not zoneDrawn then self.zoneBar:Hide() end\n", "")]),
    ("the sections under the zone bar ignore its height", [
        (P, "                y = y + ZoneBar:DrawDocked(self.zoneBar, content, y, ZONE_DONE, ZONE_TOTAL) + gap",
            "                ZoneBar:DrawDocked(self.zoneBar, content, y, ZONE_DONE, ZONE_TOTAL)")]),

    # --------------------------------------------------------------------------- the view and fit
    ("the view is as tall as the sample, so the scroll bar never shows", [
        (P, "    local view  = math.min(avail, math.max(MIN_VIEW, y - PEEK))", "    local view  = math.min(avail, math.max(MIN_VIEW, y))")]),
    ("a short sample leaves no usable view", [
        (P, "    local view  = math.min(avail, math.max(MIN_VIEW, y - PEEK))", "    local view  = math.min(avail, y - PEEK)")]),
    ("a long sample runs off the panel", [
        (P, "    local view  = math.min(avail, math.max(MIN_VIEW, y - PEEK))", "    local view  = math.max(MIN_VIEW, y - PEEK)")]),
    ("a wide tracker is not shrunk to fit", [
        (P, "    local scale = (panelW > 0) and math.min(1, (panelW - MARGIN * 2) / width) or 1", "    local scale = 1")]),
    ("a narrow tracker is enlarged", [
        (P, "    local scale = (panelW > 0) and math.min(1, (panelW - MARGIN * 2) / width) or 1",
            "    local scale = (panelW > 0) and ((panelW - MARGIN * 2) / width) or 1")]),
    ("the tracker's minimum width is ignored", [
        (P, "    local width = math.max(MIN_WIDTH, cfg.width or MIN_WIDTH)", "    local width = cfg.width or MIN_WIDTH")]),
    ("the frame's margin is not divided back out of its scale", [
        (P, '    box:SetPoint("TOP", panel, "TOP", 0, -MARGIN / scale)', '    box:SetPoint("TOP", panel, "TOP", 0, -MARGIN)')]),
    ("Tracker Opacity does not reach the preview", [
        (P, "    box:SetAlpha(cfg.trackerAlpha or 1)\n", "")]),
    ("the scroll frame is not where the tracker puts it", [
        (P, '    scroll:SetPoint("TOPLEFT", box, "TOPLEFT", pad, -(top + SCENARIO_GAP))', '    scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -top)')]),
    ("the scroll range is never brought up to date", [
        (P, "    if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end\n", "")]),
    ("a scroll position past the end is kept", [
        (P, "    if (scroll:GetVerticalScroll() or 0) > range then scroll:SetVerticalScroll(range) end\n", "")]),
    ("the backdrop skin is never applied", [
        (P, "    Tracker:SkinBackdrop(self.bg, self.background, cfg)\n", "")]),
    ("the scroll bar skin is never applied", [
        (P, "    Tracker:SkinScroll(scroll, self.barBG, cfg)\n", "")]),
    ("a refresh made while hidden is never drawn again on screen", [
        (P, "        C_Timer.After(0, function() self:Refresh(true) end)\n", "")]),
    ("the second pass asks for a third, every frame while hidden", [
        (P, "    if not again and not box:IsVisible() then", "    if not box:IsVisible() then")]),

    # --------------------------------------------------------------------------- the splits
    ("SkinBackdrop never shows the background", [
        (T, "        background:Show()\n    else\n        background:Hide()", "        background:Hide()\n    else\n        background:Hide()")]),
    ("SkinBackdrop rebuilds the backdrop every call", [
        (T, "    if bgFrame._borderSize ~= size then", "    if true then")]),
    ("SkinBackdrop keeps a border it was told to hide", [
        (T, "        bgFrame:SetBackdropBorderColor(0, 0, 0, 0)\n    end\nend", "    end\nend")]),
    ("SkinScroll shows the track under a hidden bar", [
        (T, "        if cfg.scrollBarBg ~= false and not hideBar then", "        if cfg.scrollBarBg ~= false then")]),
    ("SkinScroll never hides the bar", [
        (T, "    setScrollBarHidden(sf, hideBar)\n    applyScrollBarSkin(sf, cfg)\nend", "    applyScrollBarSkin(sf, cfg)\nend")]),
    ("SkinScroll never skins the thumb", [
        (T, "    setScrollBarHidden(sf, hideBar)\n    applyScrollBarSkin(sf, cfg)\nend", "    setScrollBarHidden(sf, hideBar)\nend")]),
    ("the tracker's own events scroll bar is no longer hidden", [
        (T, "    setScrollBarHidden(f.eventsScroll, cfg.hideScrollBar == true)\n", "")]),
    ("Insets forgets the grip", [
        (T, "    return CONTENT_PAD, DRAG_HANDLE_H, GRIP_SIZE + 2", "    return CONTENT_PAD, DRAG_HANDLE_H, GRIP_SIZE")]),
    ("NewHeader puts its header in the pool", [
        (S, "    return build(parent, groupID, self:Title(groupID))\nend",
            "    local h = build(parent, groupID, self:Title(groupID))\n    self.frames[groupID] = h\n    return h\nend")]),
    ("IsDocked ignores the switch", [
        (Z, "    return (enabled() and not isFloating()) and true or false", "    return (not isFloating()) and true or false")]),
    ("BuildDockedBar caches its bar as the tracker's", [
        (Z, "    bar.label:SetPoint(\"CENTER\")\n\n    return bar", "    bar.label:SetPoint(\"CENTER\")\n\n    self.docked = bar\n    return bar")]),
    ("the tracker's docked bar is no longer cached", [
        (Z, "    self.docked = self:BuildDockedBar(parent)\n    return self.docked", "    return self:BuildDockedBar(parent)")]),
    ("DrawDocked forgets the fill", [
        (Z, "    bar:SetValue(pct)\n", "")]),

    # ------------------------------------------- what the preview's drawing leaves behind
    ("the preview leaves its sample in /eqot status and its header height on the tracker", [
        (P, "    Row._focusIcon, Row._focusIconAt, Sections._h = keepProbe, keepProbeAt, keepHeaderH\n", "")]),
    ("the header height is not put back", [
        (P, "    Row._focusIcon, Row._focusIconAt, Sections._h = keepProbe, keepProbeAt, keepHeaderH",
            "    Row._focusIcon, Row._focusIconAt = keepProbe, keepProbeAt")]),
    ("the probe's time is not put back", [
        (P, "    Row._focusIcon, Row._focusIconAt, Sections._h = keepProbe, keepProbeAt, keepHeaderH",
            "    Row._focusIcon, Sections._h = keepProbe, keepHeaderH")]),
    ("the values are never read, so the restore wipes the tracker's", [
        (P, "    local keepProbe, keepProbeAt, keepHeaderH = Row._focusIcon, Row._focusIconAt, Sections._h\n", "    local keepProbe, keepProbeAt, keepHeaderH\n")]),

    # ------------------------------------------- a section hidden and shown again
    ("a row hidden with its section is never shown again", [
        (P, "                row:Show()\n", "")]),
    ("Place never shows its header, so every header stays hidden after HideAll", [
        (S, "    self:ApplyStyle(header)\n    header:Show()\n", "    self:ApplyStyle(header)\n")]),
    ("Place shows its header only if it was never hidden", [
        (S, "    self:ApplyStyle(header)\n    header:Show()\n",
            "    self:ApplyStyle(header)\n    if not header._placed then header:Show() end\n    header._placed = true\n")]),
    # The restore case runs with the zone bar docked as well as floating.
    ("the restore is skipped while the zone section is docked", [
        (P, "    Row._focusIcon, Row._focusIconAt, Sections._h = keepProbe, keepProbeAt, keepHeaderH\n",
            "    if not zoneDrawn then Row._focusIcon, Row._focusIconAt, Sections._h = keepProbe, keepProbeAt, keepHeaderH end\n")]),
]

SUMMARY = re.compile(r"^test_preview: (\d+) passed, (\d+) failed$")


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
