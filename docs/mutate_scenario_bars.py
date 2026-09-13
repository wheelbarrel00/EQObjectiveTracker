"""Prove docs/test_scenario_bars.lua actually discriminates, by breaking UI/Scenario.lua's
criteria draw on purpose one change at a time and checking the harness notices.

    python docs/mutate_scenario_bars.py         (run from the repo root)

Why this exists: showScenarioProgressBars shipped in v1.18.0 with no coverage on the side that
CONSUMES it. _DrawCriteria is that side and nothing sliced it, so the first four mutants below -
the switch ignored, the switch inverted, the switch wired to the QUEST key, the master ignored -
would every one of them have survived the whole tree being green. A harness written to close
that gap has to be shown to close it, which is what this file is for.

It also mutates Scenario:ReleaseCriteria, which the harness slices out of the same file. An
adversarial pass found 7 of its 9 statements deletable with the harness green - row:Hide()
among them, which is what takes an orphaned criterion off SCREEN when a stage shrinks, and
the one an #activeCriteria length check can never see.

WIDENED 2026-09-08 to the sub-header's sizing and to _DrawBanner, after a user reported a long
scenario name running off the right edge of the tracker and the banner's strings sitting
off-center on the plaque. Everything above _DrawCriteria was out of scope by construction until
then, so every mutant in those two sections below would have survived the whole tree green.

Every mutation reintroduces a defect the harness is supposed to stand guard over. Any that still
reports "0 failed" is an assertion that does not discriminate, and the run exits 1 naming it -
unless the entry is marked EQUIVALENT, which means the mutation provably cannot change behavior
and so nothing could catch it.

A mutant that makes _DrawCriteria RAISE is caught rather than crashing the file, because the
harness pcalls every call into the slice and asserts on the result. That is deliberate: every
battery in this tree reads a missing summary line as a SURVIVOR, so an unprotected harness would
report a crash as a coverage hole.

A CRASHED verdict is still reported apart from "caught" on purpose. A mutant that does not parse
exits nonzero too, and counting that as caught is a false pass in the one tool whose job is to
find false passes.

WRITES TO THE TREE. It edits UI/Scenario.lua in place, and for the event title mutants also
Core/DB.lua and Options/TabAppearance.lua, restoring each after every mutant through a finally,
then verifying every file it touched and re-checking the baseline before reporting. If you
hard-kill it, recover those three files from your editor's undo history.

Anchors are exact source text and they rot. A SKIPPED line means an anchor stopped matching: fix
the anchor rather than dropping the mutant.
"""
import io
import re
import subprocess
import sys

LUA = r"C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe"
SRC = "UI/Scenario.lua"
HARNESS = "docs/test_scenario_bars.lua"
SUMMARY = re.compile(r"^test_scenario_bars: (\d+) passed, (\d+) failed$")

GATE = ("        if not ln.completed and (not cfg or (cfg.showProgressBars ~= false\n"
        "                                             and cfg.showScenarioProgressBars ~= false)) then")

MUTANTS = [
    # ------------------------------------------------------- the switch this file exists for
    ("the scenario half is ignored, so switching it off still draws bars",
     GATE,
     "        if not ln.completed and (not cfg or (cfg.showProgressBars ~= false)) then"),

    ("the scenario half is INVERTED, so the switch does the opposite of what it says",
     "and cfg.showScenarioProgressBars ~= false)) then",
     "and cfg.showScenarioProgressBars == false)) then"),

    ("the scenario half is wired to the QUEST key, so the two halves move together",
     "and cfg.showScenarioProgressBars ~= false)) then",
     "and cfg.showQuestProgressBars ~= false)) then"),

    ("the master switch is ignored, so turning all bars off leaves the scenario ones drawing",
     GATE,
     "        if not ln.completed and (not cfg or (cfg.showScenarioProgressBars ~= false)) then"),

    ("both switches go, so the bars can never be turned off at all",
     GATE,
     "        if not ln.completed then"),

    ("the nil-config guard goes, so a render before the profile loads raises",
     "(not cfg or (cfg.showProgressBars ~= false",
     "((cfg.showProgressBars ~= false"),

    # ------------------------------------------------------- what is deliberately not a bar
    ("a completed criterion draws a bar over its own checkmark",
     "        if not ln.completed and (not cfg or (cfg.showProgressBars ~= false",
     "        if (not cfg or (cfg.showProgressBars ~= false"),

    ("a 0/1 criterion draws a bar, which reads as broken beside the checkmark rows",
     "            elseif ln.kind == LINE.PROGRESSBAR and ln.required and ln.required > 1 then",
     "            elseif ln.kind == LINE.PROGRESSBAR and ln.required and ln.required > 0 then"),

    ("a weighted line is treated as a count, so a percentage loses its denominator",
     "            if ln.kind == LINE.WEIGHTED then\n"
     "                barValue, barMax = math.max(0, math.min(100, ln.current or 0)), 100",
     "            if false then\n"
     "                barValue, barMax = math.max(0, math.min(100, ln.current or 0)), 100"),

    ("the bars-off meter drops a 0/1 criterion, so a yes-or-no row loses its numbers",
     "                elseif ln.kind == LINE.PROGRESSBAR and ln.required and ln.required > 0 then",
     "                elseif ln.kind == LINE.PROGRESSBAR and ln.required and ln.required > 1 then"),

    # ------------------------------------------------------- clamping and labels
    ("a weighted value stops clamping at 100, so an overrun bar runs off its own track",
     "                barValue, barMax = math.max(0, math.min(100, ln.current or 0)), 100",
     "                barValue, barMax = ln.current or 0, 100"),

    ("a count stops clamping to its denominator",
     "                barValue = math.max(0, math.min(ln.required, ln.current or 0))",
     "                barValue = ln.current or 0"),

    ("the percentage label reports the raw value rather than the clamped one",
     '                barLabel = ("%d%%"):format(barValue)',
     '                barLabel = ("%d%%"):format(ln.current or 0)'),

    ("the count label reports the raw value rather than the clamped one",
     '                barLabel = ("%d/%d"):format(barValue, barMax)',
     '                barLabel = ("%d/%d"):format(ln.current or 0, barMax)'),

    # ------------------------------------------------------- the text the bars-off path keeps
    ("the meter is dropped from the text, so with bars off the numbers vanish entirely",
     "                    label = (label ~= \"\") and (meter .. \" \" .. label) or meter",
     "                    label = label"),

    ("a completed criterion keeps its meter, where the default tracker drops it",
     "            local label = ln.text or \"\"\n            if not ln.completed then",
     "            local label = ln.text or \"\"\n            if true then"),

    ("the completed and unfinished text colors are swapped",
     "                row.text:SetTextColor(0.27, 1.0, 0.27)\n"
     "            else\n"
     "                row.text:SetTextColor(0.85, 0.85, 0.85)",
     "                row.text:SetTextColor(0.85, 0.85, 0.85)\n"
     "            else\n"
     "                row.text:SetTextColor(0.27, 1.0, 0.27)"),

    ("the checkmark and the nub atlases are swapped",
     '            Util.SafeSetAtlas(row.icon, ln.completed and "ui-questtracker-tracker-check"\n'
     '                                                      or "ui-questtracker-objective-nub")',
     '            Util.SafeSetAtlas(row.icon, ln.completed and "ui-questtracker-objective-nub"\n'
     '                                                      or "ui-questtracker-tracker-check")'),

    # ------------------------------------------------------- the gap Scenario:Render sums again
    ("a row after a bar pays the plain gap, so the panel is drawn short of its own content",
     "        row._gapAbove = (prev and prevBar) and BAR_TEXT_GAP or CRITERIA_LINE_GAP",
     "        row._gapAbove = CRITERIA_LINE_GAP"),

    ("every row after the first pays the wide gap, whether a bar drew or not",
     "        row._gapAbove = (prev and prevBar) and BAR_TEXT_GAP or CRITERIA_LINE_GAP",
     "        row._gapAbove = prev and BAR_TEXT_GAP or CRITERIA_LINE_GAP"),

    ("a bar stops reporting itself to the row below it",
     "        prev, prevBar = row, barValue ~= nil",
     "        prev, prevBar = row, false"),

    # ------------------------------------------------------- geometry
    ("the bar takes the build-time seed height rather than the user's",
     "    local barH     = Media:ProgressBarHeight()",
     "    local barH     = BAR_H"),

    ("the first row stops paying for the widget block above it, so the two overlap",
     "                      + BANNER_GAP + BANNER_H + (self.widgetH or 0) + CRITERIA_LINE_GAP",
     "                      + BANNER_GAP + BANNER_H + CRITERIA_LINE_GAP"),

    ("the first row stops paying for the offset the widget block was anchored from",
     "    local firstRowY = (self.topOffset or 0) + (self.subHeaderH or SUBHEADER_H)",
     "    local firstRowY = (self.subHeaderH or SUBHEADER_H)"),

    ("the bar row is drawn full width rather than at its ratio",
     "    local barWidth = math.max(1, math.floor(width * BAR_W_RATIO))",
     "    local barWidth = math.max(1, math.floor(width))"),

    ("a text row loses its side padding and runs to the container edge",
     "    local rowWidth = math.max(1, width - 16)",
     "    local rowWidth = math.max(1, width)"),

    ("a labeled bar row stops paying for the bar in its own height, so rows overlap",
     "                row:SetHeight(row.text:GetStringHeight() + BAR_TEXT_GAP + barH)",
     "                row:SetHeight(row.text:GetStringHeight() + BAR_TEXT_GAP)"),

    ("the bar sits flush against its label rather than the gap below it",
     '                row.bar:SetPoint("TOP", row.text, "BOTTOM", 0, -BAR_TEXT_GAP)',
     '                row.bar:SetPoint("TOP", row.text, "BOTTOM", 0, 0)'),

    ("an empty label draws a blank line above the bar rather than the bar alone",
     '            if ln.text ~= "" then',
     "            if true then"),

    ("a pooled row keeps whatever width it last drew with, so one criterion wraps and the "
     "next overflows",
     "                row.text:SetWidth(barWidth)",
     "                row.text:SetWidth(row.text:GetWidth() or barWidth)"),

    # ------------------------------------------------------- the styling and font hooks
    ("the shared progress bar styling is never applied, so the user's texture and colors are lost",
     "            Media:ApplyProgressBar(row.bar)",
     "            local _ = row.bar"),

    ("the bar's own label never takes the criteria font",
     "        Media:ApplyScenarioCriteriaFont(row.bar.label)",
     "        local _ = row.bar.label"),

    ("the bar's own label never takes the text shadow",
     "        Media:ApplyTextShadow(row.bar.label)",
     "        local _ = row.bar.label"),

    # ------------------------------------------------------- ReleaseCriteria, sliced and driven
    ("a released row is dropped from the run but left DRAWN over whatever replaces it",
     "        row:Hide()\n",
     ""),

    ("a released row keeps its old anchor, so it reappears where it used to be",
     "        row:Hide()\n        row:ClearAllPoints()\n",
     "        row:Hide()\n"),

    ("a released BAR row leaves its bar on screen",
     "        row:ClearAllPoints()\n        row.bar:Hide()\n",
     "        row:ClearAllPoints()\n"),

    ("a released row leaves its objective icon on screen",
     "        row.bar:Hide()\n        row.icon:Hide()\n",
     "        row.bar:Hide()\n"),

    ("a released row keeps its icon anchored",
     "        row.icon:Hide()\n        row.icon:ClearAllPoints()\n",
     "        row.icon:Hide()\n"),

    ("a released row keeps its text anchored",
     "        row.icon:ClearAllPoints()\n        row.text:ClearAllPoints()\n",
     "        row.icon:ClearAllPoints()\n"),

    ("a released row keeps its wrap width, so the next criterion to reuse it measures wrong",
     "        row.text:SetWidth(0)\n",
     ""),

    ("a released row keeps its old string, which a pooled reuse can flash",
     '        row.text:SetWidth(0)\n        row.text:SetText("")\n',
     '        row.text:SetWidth(0)\n'),

    # ------------------------------------------------------- the styling arity
    ("the scenario bars skip the fill, silently losing the user's bar color",
     "            Media:ApplyProgressBar(row.bar)",
     "            Media:ApplyProgressBar(row.bar, true)"),

    ("the criteria font goes on the bar label twice and never on the row's own text",
     "        Media:ApplyScenarioCriteriaFont(row.text)",
     "        Media:ApplyScenarioCriteriaFont(row.bar.label)"),

    ("the text shadow goes on the bar label twice and never on the row's own text",
     "        Media:ApplyTextShadow(row.text)",
     "        Media:ApplyTextShadow(row.bar.label)"),

    # ------------------------------------------------------- text-row geometry
    ("a text row loses its height floor, so the panel is short by 2px per criterion",
     "            row:SetHeight(math.max(row.text:GetStringHeight(), 14))",
     "            row:SetHeight(row.text:GetStringHeight())"),

    ("a bar's label loses the gold that separates it from an ordinary criterion",
     "                row.text:SetTextColor(1, 0.82, 0)",
     "                row.text:SetTextColor(1, 1, 1)"),

    ("the objective icon is drawn flush against the row edge",
     '            row.icon:SetPoint("LEFT", row, "LEFT", 8, 0)',
     '            row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)'),

    ("a criterion's text anchors to the row rather than to its own icon, so they overlap",
     '            row.text:SetPoint("LEFT",  row.icon, "RIGHT", 6, 0)',
     '            row.text:SetPoint("LEFT",  row, "RIGHT", 6, 0)'),

    # ------------------------------------------------------- the first row's anchor
    ("every row anchors to the previous one, so the first has nothing to hang from",
     '            row:SetPoint("TOP", container, "TOP", 0, -firstRowY)',
     '            row:SetPoint("TOP", container, "TOP", 0, 0)'),

    # ------------------------------------------------- added 2026-09-02 by the test-code scan
    # Every one of these survived a green 149-assertion run before the cases above were added.
    ("the sub-header height is ignored, so a two-tier header overlaps its first criterion",
     "    local firstRowY = (self.topOffset or 0) + (self.subHeaderH or SUBHEADER_H)",
     "    local firstRowY = (self.topOffset or 0) + SUBHEADER_H"),

    ("a bar row never hides the objective icon, leaving a nub behind the first bar",
     """            row:SetWidth(barWidth)
            row.icon:Hide()""",
     "            row:SetWidth(barWidth)"),

    ("a text row never hides the bar, leaving a StatusBar behind the first criterion",
     """            row:SetWidth(rowWidth)
            row.bar:Hide()""",
     "            row:SetWidth(rowWidth)"),

    ("the bar fills from its own maximum, so every bar draws full at any value",
     "            row.bar:SetMinMaxValues(0, barMax)",
     "            row.bar:SetMinMaxValues(barMax, barMax)"),

    ("a bar's label wraps to the ROW, so it overhangs the bar it labels",
     "                row.text:SetWidth(barWidth)",
     "                row.text:SetWidth(rowWidth)"),

    ("a criterion's text is never pinned to the row's right edge, so it has no wrap width",
     '            row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)',
     "            -- the right anchor is gone"),

    ("the row width guard is dropped, so a container mid-layout sizes a row to -16",
     "    local rowWidth = math.max(1, width - 16)",
     "    local rowWidth = width - 16"),

    ("the bar width guard is dropped, so a container mid-layout sizes a bar to zero",
     "    local barWidth = math.max(1, math.floor(width * BAR_W_RATIO))",
     "    local barWidth = math.floor(width * BAR_W_RATIO)"),

    ("a container that answers no width at all raises inside math.max",
     "    local width    = math.max(1, container:GetWidth() or 1)",
     "    local width    = math.max(1, container:GetWidth())"),

    # ------------------------------------------------- the sub-header, reported 2026-09-08
    ("the title is never given a wrap width, which is the reported bug: it runs off the tracker",
     "    subHeader.text:SetWidth(w)\n",
     ""),

    ("the category is never bounded, so a long one runs the same way the title did",
     "    subHeader.cat:SetWidth(w)\n",
     ""),

    ("the width lands AFTER the height is measured, so a wrapped title still measures one line",
     """    local w = headerTextWidth(self)
    subHeader.text:SetWidth(w)
    subHeader.cat:SetWidth(w)

    -- Render reads subHeaderH for the first criteria row and the container height, so keep it
    -- in step after a re-font
    local h = headerHeight(self)""",
     """    local h = headerHeight(self)
    local w = headerTextWidth(self)
    subHeader.text:SetWidth(w)
    subHeader.cat:SetWidth(w)"""),

    ("the one-tier header goes back to a flat 26, so a wrapped title is drawn over",
     "    return math.max(SUBHEADER_H, textH + 6)",
     "    return SUBHEADER_H"),

    ("the padding is not taken off, so the title is bounded at the full tracker width",
     "    local w = ((self.frame and self.frame:GetWidth()) or 0) - HEADER_PAD * 2",
     "    local w = ((self.frame and self.frame:GetWidth()) or 0)"),

    ("the substitution goes back to 1, so a container mid-layout wraps one character per line",
     "    if w < 1 then return BANNER_W end",
     "    if w < 1 then return 1 end"),

    ("the substitution goes entirely, so nothing to measure sizes the title to minus sixteen",
     "    if w < 1 then return BANNER_W end\n",
     ""),

    # Turned into a CLAMP rather than a substitution. That is the shape the first cut of this
    # fix had, and the narrow-container case is the only thing that separates the two.
    ("the substitution becomes a clamp, so a tracker narrower than the banner overflows",
     """    if w < 1 then return BANNER_W end
    return w""",
     "    return math.max(BANNER_W, w)"),

    ("a container with no width raises inside the subtraction rather than substituting",
     "    local w = ((self.frame and self.frame:GetWidth()) or 0) - HEADER_PAD * 2",
     "    local w = self.frame:GetWidth() - HEADER_PAD * 2"),

    ("the stage stacks an anchor per draw, so a sizeless art after a sized one carries both",
     "    banner.Stage:ClearAllPoints()\n",
     ""),

    ("the stage anchors to the art even when the art has no size, so it centers on nothing",
     '    banner.Stage:SetPoint("TOP", hasArt and banner.NormalBG or banner, "TOP", 0, -STAGE_TOP)',
     '    banner.Stage:SetPoint("TOP", banner.NormalBG, "TOP", 0, -STAGE_TOP)'),

    ("an unthemed scenario keeps the previous one's tint on the plaque",
     "        banner.ThemeOverlay:Hide()\n",
     ""),

    ("the name is drawn from the MIDDLE of its box, so a one-line name sinks down the plaque",
     'banner.Name:SetJustifyV("TOP")',
     'banner.Name:SetJustifyV("MIDDLE")'),

    ("the name stops being centered in its box, so centering the box on the art buys nothing",
     'banner.Name:SetJustifyH("CENTER")',
     'banner.Name:SetJustifyH("LEFT")'),

    ("ApplyHeaderFont's own nil guard goes, so a state with no sub-header raises",
     "    local subHeader = self.subHeader\n    if not subHeader then return end\n",
     "    local subHeader = self.subHeader\n"),

    ("the two-tier header is measured without the gap between its tiers",
     "        return (subHeader.cat:GetStringHeight() or 0) + CAT_GAP + textH + 6",
     "        return (subHeader.cat:GetStringHeight() or 0) + textH + 6"),

    ("the two-tier header is measured as though only the title were in it",
     "        return (subHeader.cat:GetStringHeight() or 0) + CAT_GAP + textH + 6",
     "        return textH + 6"),

    ("the category is never re-fonted, so an appearance change never reaches it",
     "    if subHeader.cat:IsShown() then Media:ApplyFont(subHeader.cat, -1) end\n",
     ""),

    # ------------------------------------------------------ the banner, reported the same day
    ("the banner strings go back to being centered on the FRAME, which is the second report",
     '    banner.Stage:SetPoint("TOP", hasArt and banner.NormalBG or banner, "TOP", 0, -STAGE_TOP)',
     '    banner.Stage:SetPoint("TOP", banner, "TOP", 0, -STAGE_TOP)'),

    ("the ART loses its kit offset while the frame keeps it, so their right edges stop agreeing",
     '    banner.NormalBG:SetPoint("TOPLEFT", banner, "TOPLEFT", offsets.nx, offsets.ny)',
     '    banner.NormalBG:SetPoint("TOPLEFT", banner, "TOPLEFT", 0, offsets.ny)'),

    ("the frame goes back to a fixed BANNER_W, so RIGHT overhangs and CENTER sits right of center",
     "    banner:SetSize(hasArt and (artW + offsets.nx) or BANNER_W, BANNER_H)",
     "    banner:SetSize(BANNER_W, BANNER_H)"),

    ("the frame takes the art's width raw, so a kit whose art hangs left overhangs by its offset",
     "    banner:SetSize(hasArt and (artW + offsets.nx) or BANNER_W, BANNER_H)",
     "    banner:SetSize(hasArt and artW or BANNER_W, BANNER_H)"),

    ("art the client cannot size stops falling back, so the frame collapses to nothing",
     "    banner:SetSize(hasArt and (artW + offsets.nx) or BANNER_W, BANNER_H)",
     "    banner:SetSize(artW + offsets.nx, BANNER_H)"),

    ("the atlas lands after the width is read, so the frame tracks the PREVIOUS scenario's art",
     """    Util.SafeSetAtlas(banner.NormalBG, normalAtlas, true)
    local artW   = banner.NormalBG:GetWidth() or 0
    local hasArt = artW > 1""",
     """    local artW   = banner.NormalBG:GetWidth() or 0
    local hasArt = artW > 1
    Util.SafeSetAtlas(banner.NormalBG, normalAtlas, true)"""),

    ("the text width comes off the frame, so a wider header leaves the strings off-center",
     "    local textW  = math.max(1, (hasArt and artW or BANNER_W) - BANNER_TEXT_PAD)",
     "    local textW  = math.max(1, BANNER_W - BANNER_TEXT_PAD)"),

    ("art the client could not size collapses both strings to a single pixel",
     "    local textW  = math.max(1, (hasArt and artW or BANNER_W) - BANNER_TEXT_PAD)",
     "    local textW  = math.max(1, artW - BANNER_TEXT_PAD)"),

    ("the padding either side goes, so the strings run to the art's own edges",
     "    local textW  = math.max(1, (hasArt and artW or BANNER_W) - BANNER_TEXT_PAD)",
     "    local textW  = math.max(1, (hasArt and artW or BANNER_W))"),

    ("the stage name keeps whatever width it was built with",
     "    banner.Name:SetWidth(textW)\n",
     ""),

    # --------------------------------------------- the name box's height: wrap versus truncate
    ("the name box keeps its fixed height, so a long stage name truncates instead of wrapping",
     "    banner.Name:SetHeight(math.max(BANNER_NAME_H, room))\n",
     ""),

    ("the floor goes, so art too short for a second line collapses the name box",
     "    banner.Name:SetHeight(math.max(BANNER_NAME_H, room))",
     "    banner.Name:SetHeight(room)"),

    ("the room is measured off the FRAME rather than the art, so it ignores the real header",
     "    local room = (math.min(hasArt and artH or BANNER_H, BANNER_H)",
     "    local room = (math.min(BANNER_H, BANNER_H)"),

    ("the stage line's own height is dropped from the room, so the name overruns the art",
     "                  - (STAGE_TOP + (banner.Stage:GetHeight() or 0) + STAGE_NAME_GAP)",
     "                  - (STAGE_TOP + STAGE_NAME_GAP)"),

    ("the bottom padding is dropped, so the name may sit flush against the art's edge",
     "                  - BANNER_BOTTOM_PAD)",
     "                  - 0)"),

    ("the frame bound goes, so art taller than the banner puts the name over the criteria",
     "    local room = (math.min(hasArt and artH or BANNER_H, BANNER_H)",
     "    local room = ((hasArt and artH or BANNER_H)"),

    ("the stage anchor stops falling back, so art with no size centers the text on its left edge",
     '    banner.Stage:SetPoint("TOP", hasArt and banner.NormalBG or banner, "TOP", 0, -STAGE_TOP)',
     '    banner.Stage:SetPoint("TOP", banner.NormalBG, "TOP", 0, -STAGE_TOP)'),

    ("the title stops pinning its justification, so a widthed title draws centered",
     '    subHeader.text:SetJustifyH("LEFT")\n',
     ""),

    # ------------------------------------ the three the singleton cases exist for. Every one of
    # these was deletable with the file green while each case built its own sub-header.
    ("the category is never re-shown, so a delve after an ordinary scenario draws no category",
     "        subHeader.cat:Show()\n",
     ""),

    ("the title keeps its one-tier anchor, so a two-tier title is drawn at both",
     "        subHeader.cat:ClearAllPoints()\n        subHeader.text:ClearAllPoints()",
     "        subHeader.cat:ClearAllPoints()"),

    ("the category stacks an anchor per scenario rather than being re-anchored",
     "        subHeader.cat:ClearAllPoints()\n        subHeader.text:ClearAllPoints()",
     "        subHeader.text:ClearAllPoints()"),

    ("the banner keeps every alignment it has ever been given",
     "    banner:ClearAllPoints()\n",
     ""),

    ("the art is centered on the frame rather than pinned to its top-left, which is the bug",
     '    banner.NormalBG:SetPoint("TOPLEFT", banner, "TOPLEFT", offsets.nx, offsets.ny)',
     '    banner.NormalBG:SetPoint("CENTER", banner, "CENTER", offsets.nx, offsets.ny)'),

    ("the art is not sized from its own atlas, so there is no width to center anything on",
     "    Util.SafeSetAtlas(banner.NormalBG, normalAtlas, true)",
     "    Util.SafeSetAtlas(banner.NormalBG, normalAtlas)"),

    ("the texture kit fallback is inverted, so a kit that HAS header art is refused it",
     "    if not Util.AtlasExists(normal) then",
     "    if Util.AtlasExists(normal) then"),

    # ------------------------------------------- the event title's own size and color
    # Asked for by Entmoot: the banner text below the title was stylable and the title naming
    # the scenario was not. Both settings are read in ApplyHeaderFont, which is the only header
    # entry point that runs on every render - the labels memoize on the scenario identity, so a
    # change made while a scenario is on screen would never reach the string from there.
    ("the size delta ignores the setting and always uses the constant",
     "    return (cfg and cfg.scenarioTitleSizeDelta) or TITLE_DELTA",
     "    return TITLE_DELTA"),

    # 0 is TRUTHY in Lua, so `or` is correct here - this is the mutant that proves the
    # assertion knows the difference. A player sizing the title down to the base font keeps 0.
    ("a delta of 0 is read as absent, so the base font size can never be reached",
     "    return (cfg and cfg.scenarioTitleSizeDelta) or TITLE_DELTA",
     "    local d = cfg and cfg.scenarioTitleSizeDelta\n"
     "    if not d or d == 0 then return TITLE_DELTA end\n    return d"),

    ("the color ignores the setting and always uses the constant",
     "    return c.r or HEADER_COLOR[1], c.g or HEADER_COLOR[2], c.b or HEADER_COLOR[3]",
     "    return HEADER_COLOR[1], HEADER_COLOR[2], HEADER_COLOR[3]"),

    # Per channel, the shape UI/Sections.lua uses on headerColor. A whole-table fallback passes
    # every fully-specified color and fails only a partial one.
    ("the color falls back as a WHOLE table, so a partial one loses the channel it supplied",
     "    local c = (cfg and cfg.scenarioTitleColor) or {}\n"
     "    return c.r or HEADER_COLOR[1], c.g or HEADER_COLOR[2], c.b or HEADER_COLOR[3]",
     "    local c = (cfg and cfg.scenarioTitleColor)\n"
     "    if not (c and c.r and c.g and c.b) then\n"
     "        return HEADER_COLOR[1], HEADER_COLOR[2], HEADER_COLOR[3]\n    end\n"
     "    return c.r, c.g, c.b"),

    ("the title is never recolored, so the picker does nothing at all",
     "    subHeader.text:SetTextColor(titleColor(cfg))\n", ""),

    # Scope creep rather than a bug in the obvious direction: the category is the small grey
    # breadcrumb above the title and keeps its own color and its own -1 delta.
    ("the category is recolored with the title's color too",
     "    subHeader.text:SetTextColor(titleColor(cfg))",
     "    subHeader.text:SetTextColor(titleColor(cfg))\n"
     "    subHeader.cat:SetTextColor(titleColor(cfg))"),

    ("the size is applied from the constant rather than the setting",
     "    Media:ApplyFont(subHeader.text, titleDelta(cfg))",
     "    Media:ApplyFont(subHeader.text, TITLE_DELTA)"),

    # The seam, and the one no slice can see: Scenario:Render is in no slice at all, so dropping
    # its argument leaves every case above passing while the title silently takes its fallback
    # on every render. Only the source grep catches it.
    ("Render calls ApplyHeaderFont bare, so both settings are inert in game",
     "    self:ApplyHeaderFont(cfg)", "    self:ApplyHeaderFont()"),

    ("the memoized labels read the setting instead of the constant, a second source of truth",
     "    Media:ApplyFont(subHeader.text, TITLE_DELTA)\n\n    if twoTier then",
     "    Media:ApplyFont(subHeader.text, titleDelta(nil))\n\n    if twoTier then"),

    # ------------------------------------------- the defaults and the options wiring
    # Both keys are seeded to what the file hardcoded before they existed, so nobody's title
    # moves on upgrade. A changed default here is a visible change for every existing player,
    # and no assertion inside the slice can see Core/DB.lua at all.
    ("the size default is changed, so every existing player's title moves on upgrade",
     "            scenarioTitleSizeDelta     = 4,",
     "            scenarioTitleSizeDelta     = 0,", "Core/DB.lua"),

    ("the color default is changed, so every existing player's title recolors on upgrade",
     "            scenarioTitleColor         = { r = 0.93, g = 0.32, b = 0.10, a = 1 },",
     "            scenarioTitleColor         = { r = 1, g = 1, b = 1, a = 1 },", "Core/DB.lua"),

    ("neither key is cleared by the Appearance tab's Reset to Defaults",
     '    "scenarioTitleColor", "scenarioTitleSizeDelta",\n', "", "Core/DB.lua"),

    ("the size slider writes a key the renderer never reads",
     'relayout("scenarioTitleSizeDelta", v)', 'relayout("scenarioTitleDelta", v)',
     "Options/TabAppearance.lua"),

    ("the color picker writes a key the renderer never reads",
     'relayout("scenarioTitleColor", v)', 'relayout("scenarioTitleTint", v)',
     "Options/TabAppearance.lua"),

    # The slider's own getter has to agree with the renderer's fallback, or the control reads
    # one default while the screen shows another and the first drag jumps.
    ("the slider reads its value back against a different default than the renderer uses",
     "DB().scenarioTitleSizeDelta or 4", "DB().scenarioTitleSizeDelta or 0",
     "Options/TabAppearance.lua"),
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


# Read once per file and keyed by path, because the title mutants below reach Core/DB.lua and
# Options/TabAppearance.lua as well - the wiring they break lives in neither Scenario.lua nor any
# slice, so nothing else in this battery can see it.
ORIGINALS = {}


def sourceOf(rel):
    if rel not in ORIGINALS:
        ORIGINALS[rel] = io.open(rel, encoding="utf-8", newline="").read()
    return ORIGINALS[rel]


# Resolved PER FILE rather than once. Every file this touches is LF today, but the tree is mixed
# and a bare-LF anchor against a CRLF file matches nothing and reports SKIPPED, which reads as a
# rotted anchor rather than as this driver's own bug.
def fit(rel, s):
    return s.replace("\n", "\r\n") if "\r\n" in sourceOf(rel) else s


verdict, last = run()
print("baseline: %s\n" % last)
if verdict != "green":
    print("BASELINE IS NOT GREEN - stopping")
    sys.exit(1)

failures = []
for mutant in MUTANTS:
    # A fourth element names a file other than SRC. Three-element entries are the majority and
    # mean Scenario.lua, so widening this cost them nothing.
    name, old, new = mutant[0], mutant[1], mutant[2]
    rel = mutant[3] if len(mutant) > 3 else SRC
    original = sourceOf(rel)
    old, new = fit(rel, old), fit(rel, new)
    if original.count(old) != 1:
        print("SKIPPED (anchor matched %d times in %s): %s"
              % (original.count(old), rel, name))
        failures.append(("SKIPPED", name))
        continue
    try:
        io.open(rel, "w", encoding="utf-8", newline="").write(original.replace(old, new, 1))
        verdict, last = run()
    finally:
        io.open(rel, "w", encoding="utf-8", newline="").write(original)
    equivalent = name.startswith("EQUIVALENT:")
    if verdict == "crashed":
        print("CRASHED   %-88s %s" % (name, last))
        failures.append(("CRASHED", name))
    elif verdict == "green" and not equivalent:
        print("SURVIVED  %-88s %s" % (name, last))
        failures.append(("SURVIVED", name))
    elif verdict == "failed" and equivalent:
        print("UNEXPECTED %-87s %s" % (name + " (was caught)", last))
        failures.append(("UNEXPECTED", name))
    elif equivalent:
        print("survived  %-88s as expected, it cannot change behavior" % name)
    else:
        print("caught    %-88s %s" % (name, last))

for rel, text in ORIGINALS.items():
    if io.open(rel, encoding="utf-8", newline="").read() != text:
        print("\nTHE TREE WAS NOT RESTORED - %s still holds a mutant" % rel)
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
