"""Prove docs/test_widget_block.lua actually discriminates, by breaking UI/WidgetBlock.lua's delve
tier row on purpose one change at a time and checking the harness notices.

    python docs/mutate_widget_block.py               (run from the repo root)

The row is the tier on the left and two counters at the right edge, each an icon, a number and the
game's own tooltip. Every mutation reintroduces a defect the harness is supposed to stand guard
over: a counter placed, sized, colored or masked wrong, a check that never shows or never hides, a
tooltip that shows the wrong thing or a stale one, a row the pool never gets back. Any that still
reports "0 failed" is an assertion that does not discriminate, and the run exits 1 naming it.

A CRASHED verdict is reported apart from "caught" on purpose. A mutant that does not parse also
exits nonzero, and counting that as caught is a false pass in the one tool whose job is to find
false passes.

WRITES TO THE TREE. It edits UI/WidgetBlock.lua in place and restores it after every mutant through
a finally, then verifies the restore and re-checks the baseline before reporting. Run it from a
scratch copy while the game is open, since this checkout is the live addon.

Anchors are exact source text and they rot. A SKIPPED line means an anchor stopped matching: fix
the anchor rather than dropping the mutant.
"""
import io
import re
import subprocess
import sys

LUA = r"C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe"
SRC = "UI/WidgetBlock.lua"
HARNESS = "docs/test_widget_block.lua"
SUMMARY = re.compile(r"^test_widget_block: (\d+) passed, (\d+) failed$")

MUTANTS = [
    # The pre-ship scan of 2026-10-17.
    ("all dead with no affix icon draws the check on the hidden icon's spot",
     "        local earned = w.nemAlive == 0 and w.nemIcon ~= nil\n",
     "        local earned = w.nemAlive == 0\n"),
    ("a small font takes the icons under 14",
     "    local size = math.max(14, math.ceil((row.tier:GetStringHeight() or 0) + 3))",
     "    local size = math.max(1, math.ceil((row.tier:GetStringHeight() or 0) + 3))"),
    # ------------------------------------------------------------------------------- the tooltip
    ("a click-through tracker still shows a counter's tooltip",
     "    if clickThrough() or not (frame._tooltip or frame._spellID) then return end",
     "    if not (frame._tooltip or frame._spellID) then return end"),
    ("a counter with only a spell shows nothing",
     "    if clickThrough() or not (frame._tooltip or frame._spellID) then return end",
     "    if clickThrough() or not frame._tooltip then return end"),
    ("the spell is shown ahead of the counter's own text",
     "    if frame._tooltip then\n        tip:SetText(frame._tooltip, 1, 1, 1, 1, true)",
     "    if not frame._spellID then\n        tip:SetText(frame._tooltip, 1, 1, 1, 1, true)"),
    ("the tooltip text is not wrapped",
     "        tip:SetText(frame._tooltip, 1, 1, 1, 1, true)",
     "        tip:SetText(frame._tooltip, 1, 1, 1, 1, false)"),
    ("the spell's own tooltip is never asked for",
     "        tip:SetSpellByID(frame._spellID)",
     "        tip:SetText(tostring(frame._spellID), 1, 1, 1, 1, true)"),

    # --------------------------------------------------------------------------- building a counter
    ("the icon sits on the background layer",
     '    c.icon = c:CreateTexture(nil, "ARTWORK")', '    c.icon = c:CreateTexture(nil, "BACKGROUND")'),
    ("the icon sits two pixels in",
     '    c.icon:SetPoint("LEFT", c, "LEFT", 0, 0)', '    c.icon:SetPoint("LEFT", c, "LEFT", 2, 0)'),
    ("the heart is masked round as well",
     "    if round then", "    if true then"),
    ("the round mask is made and never put on the icon",
     "        c.icon:AddMaskTexture(c.mask)\n", ""),
    ("the mask covers the counter rather than its icon",
     "        c.mask:SetAllPoints(c.icon)", "        c.mask:SetAllPoints(c)"),
    ("the mask wraps by clamping rather than clamping to black",
     '                          "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")',
     '                          "CLAMP", "CLAMP")'),
    ("the check sits under the icon",
     '        c.check = c:CreateTexture(nil, "OVERLAY")', '        c.check = c:CreateTexture(nil, "ARTWORK")'),
    ("the check sits inside the icon's corner",
     '        c.check:SetPoint("TOPRIGHT", c.icon, "TOPRIGHT", 3, 3)',
     '        c.check:SetPoint("TOPRIGHT", c.icon, "TOPRIGHT", 0, 0)'),
    ("the check is the tracker's criteria tick rather than Blizzard's earned check",
     '        Util.SafeSetAtlas(c.check, "common-icon-checkmark")',
     '        Util.SafeSetAtlas(c.check, "ui-questtracker-tracker-check")'),
    ("the number takes another font object",
     '    c.text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")',
     '    c.text = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")'),
    ("the number may wrap",
     "    c.text:SetWordWrap(false)\n    c:EnableMouse(true)", "    c:EnableMouse(true)"),
    ("the counter takes no mouse, so it can show no tooltip",
     "    c:EnableMouse(true)\n", ""),
    ("leaving a counter leaves its tooltip up",
     '    c:SetScript("OnLeave", onLeave)\n    return c', "    return c"),
    ("the tier may wrap",
     "    row.tier:SetWordWrap(false)\n", ""),
    ("the tier hangs from the row's top",
     '    row.tier:SetPoint("LEFT", row, "LEFT", 0, 0)', '    row.tier:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)'),
    ("the affix icon is not masked round",
     "    row.nem = buildCounter(row, true)", "    row.nem = buildCounter(row, false)"),

    # --------------------------------------------------------------------------------- the figures
    ("the number sits five pixels past its icon",
     "local COUNTER_GAP, COUNTER_SPACE = 4, 10", "local COUNTER_GAP, COUNTER_SPACE = 5, 10"),
    ("the two counters sit twelve pixels apart",
     "local COUNTER_GAP, COUNTER_SPACE = 4, 10", "local COUNTER_GAP, COUNTER_SPACE = 4, 12"),
    ("the gray moves",
     "local TEXT_GRAY = { 0.85, 0.85, 0.85 }", "local TEXT_GRAY = { 0.85, 0.85, 0.9 }"),
    ("the orange moves",
     "local LIVES_LOW  = { 1, 0.5, 0.25 }", "local LIVES_LOW  = { 1, 0.5, 0.3 }"),
    ("the red moves",
     "local LIVES_LAST = { 1, 0.2, 0.2 }", "local LIVES_LAST = { 1, 0.25, 0.2 }"),
    ("one life left is not red",
     "    if lives <= 1 then return LIVES_LAST end", "    if lives < 1 then return LIVES_LAST end"),
    ("every count from 2 up is orange",
     "    if lives == 2 then return LIVES_LOW end", "    if lives >= 2 then return LIVES_LOW end"),
    ("three lives are orange and two are not",
     "    if lives == 2 then return LIVES_LOW end", "    if lives == 3 then return LIVES_LOW end"),

    # ---------------------------------------------------------------------------- filling a counter
    ("the icon is a pixel narrow",
     "    c.icon:SetSize(size, size)", "    c.icon:SetSize(size - 1, size)"),
    ("the icon is never set",
     "    c.icon:SetTexture(iconID)", "    c.icon:SetTexture(nil)"),
    ("a missing icon still takes its place",
     "    c.icon:SetShown(iconID ~= nil)", "    c.icon:SetShown(true)"),
    ("the check is sized at 70 percent of the icon",
     "        local s = math.floor(size * 0.75 + 0.5)", "        local s = math.floor(size * 0.7 + 0.5)"),
    ("the check is rounded down, a pixel short at the 14 px floor",
     "        local s = math.floor(size * 0.75 + 0.5)", "        local s = math.floor(size * 0.75)"),
    ("the check never shows",
     "        c.check:SetShown(earned and true or false)", "        c.check:SetShown(false)"),
    ("the check always shows",
     "        c.check:SetShown(earned and true or false)", "        c.check:SetShown(true)"),
    ("the number takes neither the tracker font nor its shadow",
     "    Media:ApplyFont(c.text, -2)\n    Media:ApplyTextShadow(c.text)\n", ""),
    ("an empty number is left unset rather than cleared",
     '    c.text:SetText(text or "")', "    c.text:SetText(text)"),
    ("the number's blue is its green",
     "    c.text:SetTextColor(color[1], color[2], color[3])",
     "    c.text:SetTextColor(color[1], color[2], color[2])"),
    ("the gap is kept with no icon before it",
     "        if iconID then w = w + COUNTER_GAP end", "        w = w + COUNTER_GAP"),
    ("the number sits a pixel off",
     '        c.text:SetPoint("LEFT", c, "LEFT", w, 0)', '        c.text:SetPoint("LEFT", c, "LEFT", w + 1, 0)'),
    ("the number's width is left out of the counter",
     "        w = w + math.ceil(c.text:GetStringWidth() or 0)", "        w = w"),
    ("the spell is dropped from the counter",
     "    c._tooltip, c._spellID = tooltip, spellID", "    c._tooltip, c._spellID = tooltip, nil"),
    ("the tooltip text is dropped from the counter",
     "    c._tooltip, c._spellID = tooltip, spellID", "    c._tooltip, c._spellID = nil, spellID"),
    ("the counter is a pixel taller than the row",
     "    c:SetSize(math.max(w, 1), size)", "    c:SetSize(math.max(w, 1), size + 1)"),
    ("a counter the last draw hid stays hidden",
     "    c:Show()\n    return w", "    return w"),

    # ------------------------------------------------------------------------------- filling the row
    ("the tier is drawn a size larger",
     "    Media:ApplyFont(row.tier, -2)", "    Media:ApplyFont(row.tier, -1)"),
    ("the tier is never written",
     '    row.tier:SetText(w.text or "")', '    row.tier:SetText("")'),
    ("the row stands a pixel shorter than its text needs",
     "    local size = math.max(14, math.ceil((row.tier:GetStringHeight() or 0) + 3))",
     "    local size = math.max(14, math.ceil((row.tier:GetStringHeight() or 0) + 2))"),
    ("the row's floor is 16",
     "    local size = math.max(14, math.ceil((row.tier:GetStringHeight() or 0) + 3))",
     "    local size = math.max(16, math.ceil((row.tier:GetStringHeight() or 0) + 3))"),
    ("the row is a pixel narrow",
     "    row:SetSize(width, size)", "    row:SetSize(width - 1, size)"),
    ("the nemesis butts against the lives",
     "                            nil, false, size) + COUNTER_SPACE",
     "                            nil, false, size)"),
    ("the lives sit at the row's left",
     '        row.lives:SetPoint("RIGHT", row, "RIGHT", 0, 0)', '        row.lives:SetPoint("LEFT", row, "LEFT", 0, 0)'),
    ("lives switched off stay on screen",
     "    else\n        row.lives:Hide()\n    end", "    else\n    end"),
    ("one group left shows the check",
     "        local earned = w.nemAlive == 0", "        local earned = w.nemAlive <= 1"),
    ("all dead still shows a count",
     '        local text = (not earned) and (killed .. "/" .. w.nemTotal) or nil',
     '        local text = killed .. "/" .. w.nemTotal'),
    ("the count leaves out the total",
     '        local text = (not earned) and (killed .. "/" .. w.nemTotal) or nil',
     '        local text = (not earned) and tostring(killed) or nil'),
    # The author, 2026-10-17: the count reads groups killed, as the bonus objectives HUD does.
    ("the count shows groups alive, as it did before the switch",
     "        local killed = math.max(0, w.nemTotal - w.nemAlive)",
     "        local killed = w.nemAlive"),
    ("a reading above the total counts below zero",
     "        local killed = math.max(0, w.nemTotal - w.nemAlive)",
     "        local killed = w.nemTotal - w.nemAlive"),
    ("no group killed still counts one",
     "        local killed = math.max(0, w.nemTotal - w.nemAlive)",
     "        local killed = math.max(1, w.nemTotal - w.nemAlive)"),
    ("killed counts against three groups whatever the tier",
     "        local killed = math.max(0, w.nemTotal - w.nemAlive)",
     "        local killed = math.max(0, 3 - w.nemAlive)"),
    ("the count draws over the groups alive",
     '        local text = (not earned) and (killed .. "/" .. w.nemTotal) or nil',
     '        local text = (not earned) and (killed .. "/" .. w.nemAlive) or nil'),
    ("the affix's tooltip text and spell are swapped",
     "        fillCounter(row.nem, w.nemIcon, text, TEXT_GRAY, w.nemTip, w.nemSpell, earned, size)",
     "        fillCounter(row.nem, w.nemIcon, text, TEXT_GRAY, w.nemSpell, w.nemTip, earned, size)"),
    ("the count turns green once every group is killed",
     "        fillCounter(row.nem, w.nemIcon, text, TEXT_GRAY, w.nemTip, w.nemSpell, earned, size)",
     "        fillCounter(row.nem, w.nemIcon, text, killed >= w.nemTotal and { 0.2, 1, 0.2 } or TEXT_GRAY, w.nemTip, w.nemSpell, earned, size)"),
    ("the nemesis sits off the row's right edge",
     '        row.nem:SetPoint("RIGHT", row, "RIGHT", -right, 0)', '        row.nem:SetPoint("RIGHT", row, "RIGHT", right, 0)'),
    ("a nemesis switched off stays on screen",
     "    else\n        row.nem:Hide()\n    end", "    else\n    end"),
    ("a row the pool gives back stays hidden",
     "    row:Show()\n    return size", "    return size"),

    # ------------------------------------------------------------------------- the pool and the draw
    ("a released row keeps its tooltips",
     "        row.nem._tooltip, row.nem._spellID, row.lives._tooltip = nil, nil, nil\n", ""),
    ("a released row stays on screen",
     "        row:Hide()\n        row:ClearAllPoints()\n        state.delvePool",
     "        row:ClearAllPoints()\n        state.delvePool"),
    ("a released row keeps its anchor",
     "        row:Hide()\n        row:ClearAllPoints()\n        state.delvePool",
     "        row:Hide()\n        state.delvePool"),
    ("a released row never goes back to the pool",
     "        state.delvePool[#state.delvePool + 1] = row\n", ""),
    ("every draw builds a new row",
     "            local row = tremove(state.delvePool) or buildDelveRow(container)",
     "            local row = buildDelveRow(container)"),
    ("a drawn row is never released",
     "            state.delves[#state.delves + 1] = row\n", ""),
    ("the row hangs a pixel in from the side pad",
     '            row:SetPoint("TOPLEFT", container, "TOPLEFT", SIDE_PAD, -y)',
     '            row:SetPoint("TOPLEFT", container, "TOPLEFT", SIDE_PAD + 1, -y)'),
    ("the line after the row loses its gap",
     "            y = y + fillDelveRow(row, w, width) + ROW_GAP", "            y = y + fillDelveRow(row, w, width)"),
    ("a delve entry is drawn as a line of text",
     '        elseif w.kind == "delve" then', '        elseif w.kind == "row" then'),
]


def run():
    """(verdict, note). verdict is "green", "failed" or "crashed".

    The harness's own summary line is matched rather than its exit code. A mutant that does not
    parse exits nonzero too, and reporting that as "caught" is a false pass in the one tool whose
    job is to catch false passes.
    """
    r = subprocess.run([LUA, HARNESS], capture_output=True, text=True)
    for line in reversed([l for l in r.stdout.splitlines() if l.strip()]):
        m = SUMMARY.match(line.strip())
        if m:
            return ("failed" if int(m.group(2)) else "green"), line.strip()
    return "crashed", (r.stderr.strip().splitlines() or ["no output"])[0][:90]


original = io.open(SRC, encoding="utf-8", newline="").read()
crlf = "\r\n" in original


def fit(s):
    return s.replace("\n", "\r\n") if crlf else s


verdict, last = run()
print("baseline: %s\n" % last)
if verdict != "green":
    print("BASELINE IS NOT GREEN - stopping")
    sys.exit(1)

survivors = []
for name, old, new in MUTANTS:
    old, new = fit(old), fit(new)
    if original.count(old) != 1:
        print("SKIPPED (anchor matched %d times): %s" % (original.count(old), name))
        survivors.append(name)
        continue
    try:
        io.open(SRC, "w", encoding="utf-8", newline="").write(original.replace(old, new, 1))
        verdict, last = run()
    finally:
        io.open(SRC, "w", encoding="utf-8", newline="").write(original)
    if verdict == "crashed":
        print("CRASHED   %-78s %s" % (name, last))
        survivors.append(name)
    elif verdict == "green":
        print("SURVIVED  %-78s %s" % (name, last))
        survivors.append(name)
    else:
        print("caught    %-78s %s" % (name, last))

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
