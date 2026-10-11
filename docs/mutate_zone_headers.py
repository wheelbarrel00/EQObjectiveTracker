"""Prove docs/test_zone_headers.lua actually discriminates, by breaking production on purpose one
change at a time and checking the harness notices.

    python -B docs/mutate_zone_headers.py        (run from the repo root)

Why this exists: the zone headers live in seven places that each fail quietly. ZoneGroups picks
the runs and their order, Feed hands it every quest in quest log order and asks it to group after
the sort, ZoneHeaders draws and collapses each header, Render's row loop places and indents the
rows under them, DragDrop keeps a drag inside its zone, Row drops the zone label, and the defaults,
the reset list and the TOC lines decide whether any of it loads. Since 2026-10-10 the Dungeons
header rides on the same seven (Row keeps the label for its quests), and the two quest providers
decide which quests join it. A wrong comparison or a dropped line in any of them draws the zones
in the wrong order, or the rows under the wrong header, with every gate green.

Every mutation reintroduces a defect the harness is supposed to stand guard over. Any that still
reports "0 failed" is an assertion that does not discriminate, and the run exits 1 naming it.

Equivalent mutants left out on purpose: dropping "s.n = 0" from Begin (ranks keep climbing but keep
their order), dropping the GROUPS test from Note (a tally for a section Build never reads),
"zoned" ignoring the option (Build reads the option itself), and dropping "sticky and" from the test
that gives the first zone to the band (zFirst is only written with sticky headers on, so the test
fails on it anyway).

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
HARNESS = "docs/test_zone_headers.lua"

Z = "Data/ZoneGroups.lua"
F = "Data/Feed.lua"
H = "UI/ZoneHeaders.lua"
T = "UI/Tracker.lua"
G = "UI/DragDrop.lua"
R = "UI/Row.lua"
C = "UI/Commands.lua"
D = "Core/DB.lua"
Q = "Data/Providers/Quests.lua"
QC = "Data/Providers/QuestsClassic.lua"
TOC_V = "EQObjectiveTracker_Vanilla.toc"
TOC_M = "EQObjectiveTracker_Mainline.toc"
HEADED = ("    local headed = cfg and cfg.zoneHeaders and not (cfg.dungeonHeader == true and entry.tags"
          " and entry.tags.dungeon)\n")
TOC_T = "EQObjectiveTracker_TBC.toc"

MUTANTS = [
    # ------------------------------------------------------------------- ZoneGroups: which
    ("Campaign is never grouped", [
        (Z, "ZoneGroups.GROUPS = { quests = true, campaign = true }", "ZoneGroups.GROUPS = { quests = true }")]),

    ("every section is grouped", [
        (Z, "        if (zones or dungeons) and self.GROUPS[id] and g.visibleCount > 0 then\n",
            "        if (zones or dungeons) and g.visibleCount > 0 then\n")]),

    # ------------------------------------------------------------------- ZoneGroups: order
    ("alphabetical runs Z to A", [
        (Z, "        if c ~= 0 then return c < 0 end\n        return a.zone < b.zone\n",
            "        if c ~= 0 then return c > 0 end\n        return a.zone > b.zone\n")]),

    ("the client's compare is never asked", [
        (Z, "        local c = strcmputf8i and strcmputf8i(a.zone, b.zone) or 0\n", "        local c = 0\n")]),

    ("the client's compare is read backwards", [
        (Z, "        if c ~= 0 then return c < 0 end\n", "        if c ~= 0 then return c > 0 end\n")]),

    ("the client's compare is handed the zones the wrong way round", [
        (Z, "strcmputf8i(a.zone, b.zone)", "strcmputf8i(b.zone, a.zone)")]),

    ("a tie the client's compare cannot break is left unbroken", [
        (Z, "        if c ~= 0 then return c < 0 end\n        return a.zone < b.zone\n", "        return c < 0\n")]),

    ("with no client compare, and on a tie, the order runs Z to A", [
        (Z, "        return a.zone < b.zone\n", "        return a.zone > b.zone\n")]),

    ("a client without the compare raises", [
        (Z, "strcmputf8i and strcmputf8i(a.zone, b.zone) or 0", "strcmputf8i(a.zone, b.zone) or 0")]),

    ("with no client compare every pair reads as out of order", [
        (Z, "strcmputf8i(a.zone, b.zone) or 0\n", "strcmputf8i(a.zone, b.zone) or 1\n")]),

    ("alphabetical is never chosen", [
        (Z, "    sortAlpha    = zones and cfg.zoneHeaderOrder == \"alpha\"\n", "    sortAlpha    = false\n")]),

    ("alphabetical is chosen for any order but current", [
        (Z, "    sortAlpha    = zones and cfg.zoneHeaderOrder == \"alpha\"\n",
            "    sortAlpha    = zones and cfg.zoneHeaderOrder ~= \"current\"\n")]),

    ("the current zone goes last", [
        (Z, "    if a.current ~= b.current then return a.current end\n",
            "    if a.current ~= b.current then return b.current end\n")]),

    ("the current zone is not put first", [
        (Z, "    if a.current ~= b.current then return a.current end\n", "")]),

    ("the rest run in reverse quest log order", [
        (Z, "    return a.rank < b.rank\n", "    return a.rank > b.rank\n")]),

    ("the rest run A to Z instead of in quest log order", [
        (Z, "    return a.rank < b.rank\n", "    return a.zone < b.zone\n")]),

    ("a heading's place is its last sighting, not its first", [
        (Z, "    if not s.rank[z] then\n", "    if true then\n")]),

    ("a heading with no recorded place sorts first", [
        (Z, "            run.rank  = s.rank[z] or math.huge\n", "            run.rank  = s.rank[z] or 0\n")]),

    # ------------------------------------------------------------------- ZoneGroups: counts
    ("the total counts one quest per heading", [
        (Z, "    s.total[z] = (s.total[z] or 0) + 1\n", "    s.total[z] = 1\n")]),

    ("a run's total is not read", [
        (Z, "            run.total = s.total[z] or 0\n", "            run.total = 0\n")]),

    ("totals carry over from the last pass", [
        (Z, "        wipe(s.total)\n", "")]),

    ("places carry over from the last pass", [
        (Z, "        wipe(s.rank)\n", "")]),

    # ------------------------------------------------------------------- ZoneGroups: current
    ("any truthy answer makes a heading current", [
        (Z, "if p and p.IsCurrentZone and p:IsCurrentZone(e) == true then run.current = true end",
            "if p and p.IsCurrentZone and p:IsCurrentZone(e) then run.current = true end")]),

    ("a provider with no IsCurrentZone is asked anyway", [
        (Z, "if p and p.IsCurrentZone and p:IsCurrentZone(e) == true then run.current = true end",
            "if p and p:IsCurrentZone(e) == true then run.current = true end")]),

    ("every quest is asked, even in a heading already current", [
        (Z, "        if not run.current then\n", "        if true then\n")]),

    ("only a heading's first quest is asked", [
        (Z, "        if not run.current then\n", "        if run.count == 1 then\n")]),

    # ------------------------------------------------------------------- ZoneGroups: runs
    ("the run list keeps runs from a longer pass", [
        (Z, "    for i = #runs, n + 1, -1 do runs[i] = nil end\n", "")]),

    ("a reused run keeps quests from an earlier pass", [
        (Z, "        for j = #run.entries, run.count + 1, -1 do run.entries[j] = nil end\n", "")]),

    ("the zone index is not cleared between passes", [
        (Z, "    wipe(byZone)\n", "")]),

    ("the entries are never put in run order", [
        (Z, "            g.entries[k] = run.entries[j]\n", "")]),

    ("a run starts one entry early", [
        (Z, "        run.first = k + 1\n", "        run.first = k\n")]),

    ("a run ends one entry late", [
        (Z, "        run.last = k\n", "        run.last = k + 1\n")]),

    ("a section switched off keeps its last runs", [
        (Z, "        g.zoneCount = 0\n", "")]),

    # ------------------------------------------------------------------- ZoneGroups: status line
    ("the status line counts a key stored false as collapsed", [
        (Z, "        if v then folded = folded + 1 end\n", "        folded = folded + 1\n")]),

    ("the status line names every heading as current", [
        (Z, "                if run.current then here[#here + 1] = run.zone end\n",
            "                here[#here + 1] = run.zone\n")]),

    ("the status line counts the unnamed run as a zone", [
        (Z, "            if run.zone ~= \"\" then\n                named = named + 1\n",
            "            named = named + 1\n            if run.zone ~= \"\" then\n")]),

    ("the status line names the unnamed run as current, a blank name", [
        (Z, "            if run.zone ~= \"\" then\n"
            "                named = named + 1\n"
            "                if run.current then here[#here + 1] = run.zone end\n"
            "            end\n",
            "            if run.current then here[#here + 1] = run.zone end\n"
            "            if run.zone ~= \"\" then\n"
            "                named = named + 1\n"
            "            end\n")]),

    ("the status line counts every run, the unnamed one included", [
        (Z, ":format(id, named,", ":format(id, g.zoneCount,")]),

    ("the status line names the orders the wrong way round", [
        (Z, "cfg.zoneHeaderOrder == \"alpha\" and \"alphabetical\" or \"current zone first\"",
            "cfg.zoneHeaderOrder == \"alpha\" and \"current zone first\" or \"alphabetical\"")]),

    ("the status line leaves Campaign out", [
        (Z, "    for _, id in ipairs({ \"campaign\", \"quests\" }) do\n", "    for _, id in ipairs({ \"quests\" }) do\n")]),

    ("the status line names Quests before Campaign", [
        (Z, "    for _, id in ipairs({ \"campaign\", \"quests\" }) do\n",
            "    for _, id in ipairs({ \"quests\", \"campaign\" }) do\n")]),

    # ------------------------------------------------------------------- Feed
    ("only shown quests are tallied", [
        (F, "                    if zoned then ZoneGroups:Note(e.groupID, e) end\n"
            "                    if Filter:Visible(e, cfg, p) then\n",
            "                    if Filter:Visible(e, cfg, p) then\n"
            "                    if zoned then ZoneGroups:Note(e.groupID, e) end\n")]),

    ("nothing is tallied", [
        (F, "                    if zoned then ZoneGroups:Note(e.groupID, e) end\n", "")]),

    ("the tally is never reset", [
        (F, "    if zoned then ZoneGroups:Begin(cfg) end\n", "")]),

    ("the grouping runs before the sort", [
        (F, "    for _, g in pairs(self.byGroup) do\n"
            "        table.sort(g.entries, cmp)\n"
            "    end\n"
            "    if ZoneGroups then ZoneGroups:Build(self.byGroup, cfg) end\n",
            "    if ZoneGroups then ZoneGroups:Build(self.byGroup, cfg) end\n"
            "    for _, g in pairs(self.byGroup) do\n"
            "        table.sort(g.entries, cmp)\n"
            "    end\n")]),

    ("the grouping is skipped while the option is off, so old runs stay", [
        (F, "    if ZoneGroups then ZoneGroups:Build(self.byGroup, cfg) end\n",
            "    if zoned then ZoneGroups:Build(self.byGroup, cfg) end\n")]),

    ("every quest is tallied under Quests, Campaign's too", [
        (F, "ZoneGroups:Note(e.groupID, e)", "ZoneGroups:Note(\"quests\", e)")]),

    ("a quest another provider already shows is tallied as well", [
        (F, "                    if zoned then ZoneGroups:Note(e.groupID, e) end\n", ""),
        (F, "                if claimed and claimed[e.id] then\n",
            "                if zoned then ZoneGroups:Note(e.groupID, e) end\n"
            "                if claimed and claimed[e.id] then\n")]),

    # ------------------------------------------------------------------- ZoneHeaders: collapse
    ("a header made for the preview joins the tracker's pool", [
        (H, "function ZoneHeaders:NewHeader(parent)\n    return build(parent)\nend",
            "function ZoneHeaders:NewHeader(parent)\n    local h = build(parent)\n    used = used + 1\n"
            "    self.frames[used] = h\n    return h\nend")]),

    ("a pooled header is no longer drawn through Draw", [
        (H, "    local height, collapsed = self:Draw(h, content, groupID, run, y, cfg)\n",
            "    local height, collapsed = 16, false\n")]),

    # ------------------------------------------------------------------- ZoneHeaders: for the band
    ("Place hands back no header", [
        (H, "    return height, collapsed, h\n", "    return height, collapsed\n")]),
    ("Place never records which header drew a zone", [
        (H, "    self.byKey[key(groupID, run.zone)] = h\n", "")]),
    ("a new pass keeps the last pass's headers to mirror", [
        (H, "    wipe(self.byKey)\n", "")]),
    ("a band copy is told nothing about what it heads", [
        (H, "    dst.groupID, dst.zone = src.groupID, src.zone\n", "")]),
    ("a band copy misses the zone's count", [
        (H, "    dst.count:SetText(src.count:GetText())\n", "")]),
    ("a band copy misses the zone's sign", [
        (H, "    dst.collapse:SetText(src.collapse:GetText())\n", "")]),
    ("a zone that drew nothing is mirrored anyway", [
        (H, "    if not src then return false end\n", "    if not src then return true end\n")]),

    # ------------------------------------------------------------------- the row loop, for the band
    ("a section never says where its zones start", [
        (T, "                    if zoneSticky then zFirst[stickyN] = stickyZ + 1 end\n", "")]),
    ("a section never says where its zones end", [
        (T, "                    if zoneSticky then zLast[stickyN] = stickyZ end\n", "")]),
    ("the Dungeons header alone pins in the band, over an empty zone row", [
        (T, "                    local zoneSticky = sticky and cfg and cfg.zoneHeaders == true\n",
            "                    local zoneSticky = sticky\n")]),
    ("any stored zone headers value lets a zone into the band", [
        (T, "                    local zoneSticky = sticky and cfg and cfg.zoneHeaders == true\n",
            "                    local zoneSticky = sticky and cfg and cfg.zoneHeaders\n")]),
    ("the band's zones are never counted", [
        (T, "                                stickyZ = stickyZ + 1\n", "")]),
    ("the band's zones are never named", [
        (T, "                                zKeys[stickyZ] = zoneKey\n", "")]),
    ("the first zone stays in the list as well as the band", [
        (T, "                                zoneHead:Hide()\n", "")]),
    ("the band's own zone is recorded at the top of the list", [
        (T, "                                zTops[stickyZ] = -(zoneH + gap)\n", "                                zTops[stickyZ] = 0\n")]),
    ("a zone below the top is never placed for the band", [
        (T, "                                if zoneSticky then zTops[stickyZ] = y end\n", "")]),
    ("a zone joins the band with something above it in the list", [
        (T, "if zoneSticky and y == 0 and stickyZ == zFirst[stickyN] then", "if zoneSticky and stickyZ == zFirst[stickyN] then")]),
    ("every zone at the top joins the band, not only the first", [
        (T, "if zoneSticky and y == 0 and stickyZ == zFirst[stickyN] then", "if zoneSticky and y == 0 then")]),

    ("a zone is keyed by heading alone", [
        (H, "    return groupID .. \":\" .. zone\n", "    return zone\n")]),

    ("expanding stores false instead of clearing the key", [
        (H, "    char.zonesCollapsed[k] = collapsed or nil\n", "    char.zonesCollapsed[k] = collapsed\n")]),

    ("collapsing scrolls and expanding does not", [
        (H, "    if not collapsed and Tracker.ScrollZoneIntoView then Tracker:ScrollZoneIntoView(k) end\n",
            "    if collapsed and Tracker.ScrollZoneIntoView then Tracker:ScrollZoneIntoView(k) end\n")]),

    ("an expanded zone scrolls before the render that places it", [
        (H, "    if not collapsed and Tracker.ScrollZoneIntoView then Tracker:ScrollZoneIntoView(k) end\n", ""),
        (H, "    Tracker:Render()\n",
            "    if not collapsed and Tracker.ScrollZoneIntoView then Tracker:ScrollZoneIntoView(k) end\n"
            "    Tracker:Render()\n")]),

    ("a click-through tracker still collapses a zone", [
        (H, "        if Tracker and Tracker.IsClickThrough and Tracker:IsClickThrough() then return end\n", "")]),

    ("the header takes every button", [
        (H, "    h:RegisterForClicks(\"LeftButtonUp\")\n", "    h:RegisterForClicks(\"AnyUp\")\n")]),

    # ------------------------------------------------------------------- ZoneHeaders: what it shows
    ("the count always shows the total", [
        (H, "    if cfg.showQuestTotal ~= false then\n", "    if true then\n")]),

    ("the count reads total over shown", [
        (H, "        h.count:SetText(run.count .. \"/\" .. run.total)\n",
            "        h.count:SetText(run.total .. \"/\" .. run.count)\n")]),

    ("the sign is inverted", [
        (H, "    h.collapse:SetText(collapsed and \"+\" or \"-\")\n", "    h.collapse:SetText(collapsed and \"-\" or \"+\")\n")]),

    ("the header is placed below its y", [
        (H, "    h:SetPoint(\"TOPLEFT\",  content, \"TOPLEFT\",  0, -y)\n",
            "    h:SetPoint(\"TOPLEFT\",  content, \"TOPLEFT\",  0, y)\n")]),

    ("a header stays in the content it was made in", [
        (H, "    if h:GetParent() ~= content then h:SetParent(content) end\n", "")]),

    ("a header hidden once never shows again", [
        (H, "    h:SetPoint(\"TOPRIGHT\", content, \"TOPRIGHT\", 0, -y)\n    h:Show()\n",
            "    h:SetPoint(\"TOPRIGHT\", content, \"TOPRIGHT\", 0, -y)\n")]),

    ("the zone name wraps", [
        (H, "    h.text:SetWordWrap(false)\n", "")]),

    ("the zone name sits flush to the edge", [
        (H, "    h.text:SetPoint(\"LEFT\", 4, 0)\n", "    h.text:SetPoint(\"LEFT\", 0, 0)\n")]),

    ("a long zone name runs under the count", [
        (H, "    h.text:SetPoint(\"RIGHT\", h.count, \"LEFT\", -6, 0)\n", "")]),

    ("the count sits on the sign", [
        (H, "    h.count:SetPoint(\"RIGHT\", h.collapse, \"LEFT\", -6, 0)\n", "    h.count:SetPoint(\"RIGHT\", -4, 0)\n")]),

    # ------------------------------------------------------------------- ZoneHeaders: the generation
    ("Begin never moves the render generation", [
        (H, "    self.gen = self.gen + 1\n", "")]),

    ("the render generation moves on the first pass only", [
        (H, "    self.gen = self.gen + 1\n", "    self.gen = 1\n")]),

    ("the render generation is not set at load", [
        (H, "ZoneHeaders.gen = 0\n", "")]),

    # ------------------------------------------------------------------- ZoneHeaders: look
    ("the height has no floor", [
        (H, "math.max(MIN_H, math.ceil(textH + 4))", "math.ceil(textH + 4)")]),

    ("the height is two short", [
        (H, "math.max(MIN_H, math.ceil(textH + 4))", "math.max(MIN_H, math.ceil(textH + 2))")]),

    ("the height rounds a part pixel down", [
        (H, "math.ceil(textH + 4)", "math.floor(textH + 4)")]),

    ("Height never learns the height a header was drawn at", [
        (H, "    self._h = height\n", "")]),

    ("Height reads the text's own height", [
        (H, "    self._h = height\n", "    self._h = textH\n")]),

    ("the default size offset is the objective text's", [
        (H, "    local delta = cfg.zoneHeaderSizeDelta or 2\n", "    local delta = cfg.zoneHeaderSizeDelta or 0\n")]),

    ("the count is drawn at the section count's size", [
        (H, "    Media:ApplyFont(h.count, delta - 4)\n", "    Media:ApplyFont(h.count, delta - 6)\n")]),

    ("the class color switch is ignored", [
        (H, "    if cfg.zoneHeaderColorUseClass then r, g, b = Util.GetPlayerClassColor() end\n", "")]),

    ("the default color is white", [
        (H, "local TEXT_COLOR = { 1, 0.82, 0 }", "local TEXT_COLOR = { 1, 1, 1 }")]),

    ("the count is drawn gold whatever the color", [
        (H, "    h.count:SetTextColor(r, g, b)\n", "    h.count:SetTextColor(TEXT_COLOR[1], TEXT_COLOR[2], TEXT_COLOR[3])\n")]),

    ("the sign is drawn gold whatever the color", [
        (H, "    h.collapse:SetTextColor(r, g, b)\n",
            "    h.collapse:SetTextColor(TEXT_COLOR[1], TEXT_COLOR[2], TEXT_COLOR[3])\n")]),

    ("the count ignores the class color", [
        (H, "    h.count:SetTextColor(r, g, b)\n",
            "    local pc = cfg.zoneHeaderColor or {}\n"
            "    h.count:SetTextColor(pc.r or TEXT_COLOR[1], pc.g or TEXT_COLOR[2], pc.b or TEXT_COLOR[3])\n")]),

    ("the sign ignores the class color", [
        (H, "    h.collapse:SetTextColor(r, g, b)\n",
            "    local pc = cfg.zoneHeaderColor or {}\n"
            "    h.collapse:SetTextColor(pc.r or TEXT_COLOR[1], pc.g or TEXT_COLOR[2], pc.b or TEXT_COLOR[3])\n")]),

    ("the count's color channels are swapped", [
        (H, "    h.count:SetTextColor(r, g, b)\n", "    h.count:SetTextColor(r, b, g)\n")]),

    ("with no class color to give, the header gets no color", [
        (H, "    if not r then\n", "    if not cfg.zoneHeaderColorUseClass then\n")]),

    ("a header's bar keeps the first color it was given", [
        (H, "        if h._c1 then h._c1:SetRGBA(r, g, b, a) else h._c1 = CreateColor(r, g, b, a) end\n",
            "        if not h._c1 then h._c1 = CreateColor(r, g, b, a) end\n")]),

    ("a header's bar keeps the first dark end it was given", [
        (H, "        if h._c2 then h._c2:SetRGBA(r * k, g * k, b * k, a) else h._c2 = CreateColor(r * k, g * k, b * k, a) end\n",
            "        if not h._c2 then h._c2 = CreateColor(r * k, g * k, b * k, a) end\n")]),

    ("the bar is drawn with its switch off", [
        (H, "    if not cfg.zoneHeaderBar then\n", "    if false then\n")]),

    ("the bar is not darkened toward its end", [
        (H, "local BAR_DARKEN = 0.4", "local BAR_DARKEN = 1")]),

    ("the bar runs top to bottom", [
        (H, "\"HORIZONTAL\"", "\"VERTICAL\"")]),

    ("the bar has no color without gradients", [
        (H, "        h.bar:SetVertexColor(r, g, b, a)\n", "")]),

    ("the divider is drawn with its switch off", [
        (H, "    if cfg.zoneHeaderDivider then\n", "    if true then\n")]),

    # ------------------------------------------------------------------- ZoneHeaders: pool
    ("leftover headers are never hidden", [
        (H, "    for i = used + 1, #self.frames do self.frames[i]:Hide() end\n", "")]),

    ("the pool is never reset", [
        (H, "function ZoneHeaders:Begin()\n    used = 0\n", "function ZoneHeaders:Begin()\n")]),

    # ------------------------------------------------------------------- ZoneHeaders: indent
    ("rows are indented with the option off", [
        (H, "    if not (cfg and (cfg.zoneHeaders or cfg.dungeonHeader)) then return 0 end\n", "    if not cfg then return 0 end\n")]),

    ("a negative indent is let through", [
        (H, "    return math.max(0, cfg.zoneHeaderIndent or 8)\n", "    return cfg.zoneHeaderIndent or 8\n")]),

    ("the default indent is none", [
        (H, "    return math.max(0, cfg.zoneHeaderIndent or 8)\n", "    return math.max(0, cfg.zoneHeaderIndent or 0)\n")]),

    # ------------------------------------------------------------------- Render's row loop
    ("runs left from an earlier pass are read while the count is 0", [
        (T, "local runs = (group.zoneCount or 0) > 0 and group.zoneRuns or nil",
            "local runs = group.zoneRuns")]),

    ("every run draws the whole section", [
        (T, "                        if run then first, last = run.first, run.last end\n", "")]),

    ("a quest with no heading gets a header", [
        (T, "if run and run.zone ~= \"\" then", "if run then")]),

    ("a zone's top is not recorded", [
        (T, "                            zoneTops[zoneKey] = y\n", "")]),

    ("no gap under a zone header", [
        (T, "                            y = y + zoneH + gap\n", "                            y = y + zoneH\n")]),

    ("the rows under a header are not indented", [
        (T, "                            left = indent\n", "")]),

    ("a collapsed zone still draws its rows", [
        (T, "                            if zoneCollapsed then last = first - 1 end\n", "")]),

    ("an indented row keeps the full width", [
        (T, "row:SetWidth(width - left)", "row:SetWidth(width)")]),

    ("an indented row is laid out at the full width", [
        (T, "Row:Render(row, entry, width - left, cfg)", "Row:Render(row, entry, width, cfg)")]),

    ("an indented row is not moved", [
        (T, "row:SetPoint(\"TOPLEFT\", content, \"TOPLEFT\", left, -y)", "row:SetPoint(\"TOPLEFT\", content, \"TOPLEFT\", 0, -y)")]),

    ("a zone header is handed no settings", [
        (T, "ZoneHeaders:Place(content, groupID, run, y, cfg)", "ZoneHeaders:Place(content, groupID, run, y)")]),

    ("a zone header is handed empty settings", [
        (T, "ZoneHeaders:Place(content, groupID, run, y, cfg)", "ZoneHeaders:Place(content, groupID, run, y, {})")]),

    ("a zone header is placed as Quests' in any section", [
        (T, "ZoneHeaders:Place(content, groupID, run, y, cfg)", "ZoneHeaders:Place(content, \"quests\", run, y, cfg)")]),

    ("a zone is keyed as Quests' in any section", [
        (T, "ZoneHeaders:Key(groupID, run.zone)", "ZoneHeaders:Key(\"quests\", run.zone)")]),

    ("quest item buttons are never asked for", [
        (T, "                            if entry.hasItem then ItemButtons:Want(entry.id, row) end\n", "")]),

    ("an item button is asked for with no row", [
        (T, "ItemButtons:Want(entry.id, row)", "ItemButtons:Want(entry.id)")]),

    ("every row asks for an item button", [
        (T, "if entry.hasItem then ItemButtons:Want(entry.id, row) end", "ItemButtons:Want(entry.id, row)")]),

    ("a countdown never keeps the ticker running", [
        (T, "                            if noteExpiry(entry) then hasTimed = true end\n",
            "                            noteExpiry(entry)\n")]),

    ("no row's countdown is looked at", [
        (T, "                            if noteExpiry(entry) then hasTimed = true end\n", "")]),

    ("the indent is always 8", [
        (T, "                            left = indent\n", "                            left = 8\n")]),

    ("the tracker reads no Quest Indent", [
        (T, "    local indent = ZoneHeaders:Indent(cfg)\n", "    local indent = 8\n")]),

    ("Block Spacing under a zone header is always 2", [
        (T, "                            y = y + zoneH + gap\n", "                            y = y + zoneH + 2\n")]),

    ("Block Spacing between rows is always 2", [
        (T, "y = y + Row:Render(row, entry, width - left, cfg) + gap", "y = y + Row:Render(row, entry, width - left, cfg) + 2")]),

    ("the band's zone sits a gap of 2 above the list", [
        (T, "zTops[stickyZ] = -(zoneH + gap)", "zTops[stickyZ] = -(zoneH + 2)")]),

    ("the header pool is never reset", [
        (T, "    ZoneHeaders:Begin()\n", "")]),

    ("leftover headers stay on screen", [
        (T, "    ZoneHeaders:Sweep()\n", "")]),

    ("the zone tops are never cleared", [
        (T, "    wipe(zoneTops)\n", "")]),

    ("a zone scrolls to its section's top", [
        (T, "scrollIntoView(f, f and f._zoneTop and f._zoneTop[zoneKey])",
            "scrollIntoView(f, f and f._sectionTop and f._sectionTop[zoneKey])")]),

    ("scrolling ignores the locked anchor chain", [
        (T, "    if not (top and sf) or secureLocked() then return end\n", "    if not (top and sf) then return end\n")]),

    # ------------------------------------------------------------------- DragDrop
    ("a drag ignores its zone", [
        (G, "(zone == nil or ZoneGroups:RunKey(e, cfg) == zone)", "true")]),

    ("a drag never remembers its zone", [
        (G, "self.dragZone  = ZoneGroups:Grouping(cfg) and ZoneGroups:RunKey(e, cfg) or nil", "self.dragZone  = nil")]),

    ("a drag keeps to a zone with zone headers off", [
        (G, "self.dragZone  = ZoneGroups:Grouping(cfg) and ZoneGroups:RunKey(e, cfg) or nil",
            "self.dragZone  = ZoneGroups:RunKey(e, cfg)")]),

    ("a quest with no heading is not matched to the empty zone", [
        (Z, "    if zones then return e.zone or \"\" end\n", "    if zones then return e.zone end\n")]),

    ("the drop line counts the whole section", [
        (G, "local n = collectScope(self.dragGroup, self.dragZone)", "local n = collectScope(self.dragGroup)")]),

    ("the commit is handed the whole section", [
        (G, "local n = collectScope(dragGroup, dragZone)", "local n = collectScope(dragGroup)")]),

    ("the zone outlives the drag", [
        (G, "self.dragID, self.dragGroup, self.dragZone, self.dropIndex, self.dragRow = nil, nil, nil, nil, nil",
            "self.dragID, self.dragGroup, self.dropIndex, self.dragRow = nil, nil, nil, nil")]),

    # ------------------------------------------------------------------- Row, Commands
    ("the zone label still draws under zone headers", [
        (R, "cfg.showZoneTag ~= false and not headed)", "cfg.showZoneTag ~= false)")]),

    ("a quest in the Dungeons header loses its label too", [
        (R, "    local headed = cfg and cfg.zoneHeaders and not (cfg.dungeonHeader == true and entry.tags and entry.tags.dungeon)\n",
            "    local headed = cfg and cfg.zoneHeaders\n")]),

    ("any stored Dungeons value keeps the label", [
        (R, "not (cfg.dungeonHeader == true and entry.tags", "not (cfg.dungeonHeader and entry.tags")]),

    ("every quest keeps its label while the Dungeons header is on", [
        (R, "not (cfg.dungeonHeader == true and entry.tags and entry.tags.dungeon)", "not (cfg.dungeonHeader == true)")]),

    ("a quest with no tags raises under zone headers and the Dungeons header", [
        (R, "and entry.tags and entry.tags.dungeon)", "and entry.tags.dungeon)")]),

    ("the label is hidden with zone headers off unless the quest is a dungeon quest", [
        (R, "    local headed = cfg and cfg.zoneHeaders and not (",
            "    local headed = cfg and not (")]),

    ("the zone label comes back through a trailing or", [
        (R, "and entry.subtitle or nil\n", "and entry.subtitle or nil or entry.subtitle\n")]),

    ("the zone label is written again after the test", [
        (R, "and entry.subtitle or nil\n", "and entry.subtitle or nil\n    subtitle = entry.subtitle\n")]),

    ("the zone label is cleared after the test", [
        (R, "and entry.subtitle or nil\n", "and entry.subtitle or nil\n    subtitle = nil\n")]),

    ("/eqot status loses its zone headers line", [
        (C, "    debugLine(\"ZoneGroups\")\n", "")]),

    # ------------------------------------------------------------------- the defaults
    ("zone headers ship on", [
        (D, "            zoneHeaders             = false,\n", "            zoneHeaders             = true,\n")]),

    ("the order ships alphabetical", [
        (D, "            zoneHeaderOrder         = \"current\",\n", "            zoneHeaderOrder         = \"alpha\",\n")]),

    ("the default indent is none in the profile", [
        (D, "            zoneHeaderIndent        = 8,\n", "            zoneHeaderIndent        = 0,\n")]),

    ("the default text color is white in the profile", [
        (D, "            zoneHeaderColor         = { r = 1, g = 0.82, b = 0, a = 1 },\n",
            "            zoneHeaderColor         = { r = 1, g = 1, b = 1, a = 1 },\n")]),

    ("the collapsed zones have no default table", [
        (D, "        zonesCollapsed     = {},\n", "")]),

    ("Reset all settings keeps the collapsed zones", [
        (D, "        c.zonesCollapsed    = {}\n", "")]),

    ("Reset to Defaults switches zone headers off", [
        (D, "\"zoneHeaderBarColor\", \"zoneHeaderDivider\", \"zoneHeaderDividerColor\", \"zoneHeaderIndent\",",
            "\"zoneHeaderBarColor\", \"zoneHeaderDivider\", \"zoneHeaderDividerColor\", \"zoneHeaderIndent\", \"zoneHeaders\",")]),

    ("Reset to Defaults keeps the indent", [
        (D, "\"zoneHeaderBarColor\", \"zoneHeaderDivider\", \"zoneHeaderDividerColor\", \"zoneHeaderIndent\",",
            "\"zoneHeaderBarColor\", \"zoneHeaderDivider\", \"zoneHeaderDividerColor\",")]),

    # ------------------------------------------------------------------- the TOCs
    ("a Classic TOC forgets the grouping file", [
        (TOC_V, "Data\\ZoneGroups.lua\n", "")]),

    ("the retail TOC lists the header file twice", [
        (TOC_M, "UI\\ZoneHeaders.lua\n", "UI\\ZoneHeaders.lua\nUI\\ZoneHeaders.lua\n")]),

    ("a TOC loads the grouping file after Feed", [
        (TOC_T, "Data\\ZoneGroups.lua\n", ""),
        (TOC_T, "Data\\Feed.lua\n", "Data\\Feed.lua\nData\\ZoneGroups.lua\n")]),

    # ------------------------------------------------------------------- the second scan's hand-breaks
    # Each survived the harness green until its stubs read through self, recorded the frame type and
    # draw layers, measured an empty string as 0, and its fixtures reused one module across passes.
    ("a reused run keeps a current flag from the pass before", [
        (Z, "            run.zone, run.count, run.current = z, 0, false\n",
            "            run.zone, run.count, run.current = z, 0, run.current == true\n")]),

    ("a reused run keeps its place from the pass before", [
        (Z, "            run.rank  = s.rank[z] or math.huge\n",
            "            run.rank  = run.rank or s.rank[z] or math.huge\n")]),

    ("a reused run keeps its total from the pass before", [
        (Z, "            run.total = s.total[z] or 0\n",
            "            run.total = run.total or s.total[z] or 0\n")]),

    ("the run list is trimmed after the sort, so a run from the pass before sorts in", [
        (Z, "    for i = #runs, n + 1, -1 do runs[i] = nil end\n    table.sort(runs, before)\n",
            "    table.sort(runs, before)\n    for i = #runs, n + 1, -1 do runs[i] = nil end\n")]),

    ("the status line reads the profile with a dot call, which raises in game", [
        (Z, "    local cfg = DB and DB:Tracker()\n", "    local cfg = DB and DB.Tracker()\n")]),

    ("the status line reads the character with a dot call, which raises in game", [
        (Z, "    local char  = DB:Char()\n", "    local char  = DB.Char()\n")]),

    ("the status line lists a section that grouped nothing", [
        (Z, "        if named > 0 then\n", "        if g then\n")]),

    ("a header reads the collapsed zones with a dot call, which raises on every render", [
        (H, "    local char = DB and DB:Char()\n    local t    = char and char.zonesCollapsed\n",
            "    local char = DB and DB.Char()\n    local t    = char and char.zonesCollapsed\n")]),

    ("a click reads the character with a dot call, which raises on click", [
        (H, "    local char = DB and DB:Char()\n    if not char then return end\n",
            "    local char = DB and DB.Char()\n    if not char then return end\n")]),

    ("a click renders with a dot call, which raises on click", [
        (H, "    Tracker:Render()\n", "    Tracker.Render()\n")]),

    ("a zone header is built as a plain Frame, which takes no click in game", [
        (H, "    local h = CreateFrame(\"Button\", nil, parent)\n", "    local h = CreateFrame(\"Frame\", nil, parent)\n")]),

    ("the bar is drawn over the text", [
        (H, "    h.bar = h:CreateTexture(nil, \"BACKGROUND\")\n", "    h.bar = h:CreateTexture(nil, \"OVERLAY\")\n")]),

    ("the zone name is drawn on the bar's layer", [
        (H, "    h.text = h:CreateFontString(nil, \"OVERLAY\", \"GameFontNormal\")\n",
            "    h.text = h:CreateFontString(nil, \"BACKGROUND\", \"GameFontNormal\")\n")]),

    ("the divider is drawn under the bar", [
        (H, "    h.line = h:CreateTexture(nil, \"ARTWORK\")\n", "    h.line = h:CreateTexture(nil, \"BACKGROUND\")\n")]),

    ("the bar has no texture for its color to tint", [
        (H, "    h.bar:SetColorTexture(1, 1, 1, 1)\n", "")]),

    ("the divider has no height", [
        (H, "    h.line:SetHeight(1)\n", "")]),

    ("the divider has no right edge", [
        (H, "    h.line:SetPoint(\"BOTTOMRIGHT\", 0, 0)\n", "")]),

    ("the divider hangs from the top edge", [
        (H, "    h.line:SetPoint(\"BOTTOMLEFT\", 0, 0)\n", "    h.line:SetPoint(\"TOPLEFT\", 0, 0)\n")]),

    ("a header is styled before its text is in, so its height is measured empty", [
        (H, "    h.text:SetText(run.zone)\n", "    local height = self:ApplyStyle(h, cfg)\n    h.text:SetText(run.zone)\n"),
        (H, "    local height = self:ApplyStyle(h, cfg)\n    h:ClearAllPoints()\n", "    h:ClearAllPoints()\n")]),

    ("a string the font never sized raises", [
        (H, "    local textH  = h.text:GetStringHeight() or 0\n", "    local textH  = h.text:GetStringHeight()\n")]),

    ("the header's right edge hangs off the content's left edge", [
        (H, "    h:SetPoint(\"TOPRIGHT\", content, \"TOPRIGHT\", 0, -y)\n",
            "    h:SetPoint(\"TOPRIGHT\", content, \"TOPLEFT\", 0, -y)\n")]),

    ("the header stops 8px short of the content's right edge", [
        (H, "    h:SetPoint(\"TOPRIGHT\", content, \"TOPRIGHT\", 0, -y)\n",
            "    h:SetPoint(\"TOPRIGHT\", content, \"TOPRIGHT\", -8, -y)\n")]),

    ("a drag reads the profile with a dot call, which raises on every drag in game", [
        (G, "    local cfg = ns:GetModule(\"DB\"):Tracker()\n    local ZoneGroups = ns:GetModule(\"ZoneGroups\")\n    self.dragZone",
            "    local cfg = ns:GetModule(\"DB\").Tracker()\n    local ZoneGroups = ns:GetModule(\"ZoneGroups\")\n    self.dragZone")]),

    ("the drop scope reads the profile with a dot call, which raises on every drag in game", [
        (G, "    local ZoneGroups = ns:GetModule(\"ZoneGroups\")\n    local cfg = ns:GetModule(\"DB\"):Tracker()\n    local n = 0\n",
            "    local ZoneGroups = ns:GetModule(\"ZoneGroups\")\n    local cfg = ns:GetModule(\"DB\").Tracker()\n    local n = 0\n")]),

    ("a Campaign drag ignores its zone", [
        (G, "    self.dragZone  = ZoneGroups:Grouping(cfg) and ZoneGroups:RunKey(e, cfg) or nil\n",
            "    self.dragZone  = (ZoneGroups:Grouping(cfg) and e.groupID == \"quests\") and ZoneGroups:RunKey(e, cfg) or nil\n")]),

    ("a row is acquired with no builder, which raises on an empty pool", [
        (T, "local row = RowPool:Acquire(content, entry.providerID, entry.id, _buildRow)",
            "local row = RowPool:Acquire(content, entry.providerID, entry.id)")]),

    # ------------------------------------------------------------------- found by the final scan
    ("the headers are swept only while zone headers are on", [
        (T, "    ZoneHeaders:Sweep()\n",
            "    if cfg and cfg.zoneHeaders then\n        ZoneHeaders:Sweep()\n    end\n")]),

    ("a reused run appends after the quests it kept", [
        (Z, "        run.entries[run.count] = e\n", "        run.entries[#run.entries + 1] = e\n")]),

    ("Reset all settings clears the collapsed zones only when there are none", [
        (D, "        c.zonesCollapsed    = {}\n",
            "        if not c.zonesCollapsed then\n            c.zonesCollapsed    = {}\n        end\n")]),

    ("the indent is dropped while sticky headers are off", [
        (T, "    local indent = ZoneHeaders:Indent(cfg)\n",
            "    local indent = ZoneHeaders:Indent(cfg)\n    if not (f._stickyAnchored and f.stickyBand) then indent = 0 end\n")]),

    # ------------------------------------------------------------------- found by the second scan
    ("a pop-up box adds no height, so the first zone header sits on it", [
        (T, "                        y = y + PopupBoxes:Render(content, width, y, groupID)\n",
            "                        PopupBoxes:Render(content, width, y, groupID)\n")]),

    ("pop-up boxes are drawn at the indented width", [
        (T, "                        y = y + PopupBoxes:Render(content, width, y, groupID)\n",
            "                        y = y + PopupBoxes:Render(content, width - indent, y, groupID)\n")]),

    ("a zone's rows are indented only while no pop-up box is drawn", [
        (T, "                            left = indent\n", "                            left = (popupCount == 0) and indent or 0\n")]),

    ("the indent is dropped through a multiple assignment while sticky headers are off", [
        (T, "    local sticky = f._stickyAnchored and f.stickyBand\n",
            "    local sticky = f._stickyAnchored and f.stickyBand\n    if not sticky then indent, sticky = 0, sticky end\n")]),

    # Outside the block pinned whole, so only the count of the saved setting in Render catches it.
    ("Render writes the saved indent itself", [
        (T, "    local scenarioH = self:_RenderScenario(byGroup[CONTAINER_GROUP], cfg)\n",
            "    local scenarioH = self:_RenderScenario(byGroup[CONTAINER_GROUP], cfg)\n"
            "    if cfg then cfg.zoneHeaderIndent = 0 end\n")]),

    ("a saved indent of 0 falls back to 8", [
        (H, "    return math.max(0, cfg.zoneHeaderIndent or 8)\n",
            "    return math.max(0, (cfg.zoneHeaderIndent ~= 0 and cfg.zoneHeaderIndent) or 8)\n")]),

    ("the indent carries over into the next run", [
        (T, "                    for r = 1, (runs and group.zoneCount or 1) do\n"
            "                        local first, last, left = 1, group.visibleCount, 0\n",
            "                    local left = 0\n"
            "                    for r = 1, (runs and group.zoneCount or 1) do\n"
            "                        local first, last = 1, group.visibleCount\n")]),

    ("Reset all settings clears the character's state only when it was never set", [
        (D, "    if c then\n        c.sectionsCollapsed = {}\n",
            "    if c and c.sectionsCollapsed == nil then\n        c.sectionsCollapsed = {}\n")]),

    ("Reset all settings clears the profile's copy instead of the character's", [
        (D, "    local c = self.db.char\n", "    local c = self.db.profile\n")]),

    ("Reset all settings stops after the profile", [
        (D, "    if self.db.ResetProfile then self.db:ResetProfile() end\n",
            "    if self.db.ResetProfile then self.db:ResetProfile() return end\n")]),

    ("Reset all settings keeps the old collapsed zones table", [
        (D, "        c.zonesCollapsed    = {}\n", "        c.zonesCollapsed    = c.zonesCollapsed or {}\n")]),

    ("Reset all settings leaves the parts switched on by /eqot enable", [
        (D, "        g.enabledModules, g.enabledProviders               = nil, nil\n", "")]),

    ("Reset all settings leaves the providers switched off by /eqot disable", [
        (D, "        g.safeMode, g.disabledModules, g.disabledProviders = nil, nil, nil\n",
            "        g.safeMode, g.disabledModules = nil, nil\n")]),

    # ----------------------------------------- the Dungeons header (2026-10-10, requested by Andreon)
    ("dungeon quests never leave their zones", [
        (Z, "    if dungeons and e.tags and e.tags.dungeon then return DUNGEONS end\n", "")]),
    ("every quest counts as a dungeon quest under the dungeon header", [
        (Z, "    if dungeons and e.tags and e.tags.dungeon then return DUNGEONS end\n",
            "    if dungeons then return DUNGEONS end\n")]),
    ("a quest with no tags raises under the dungeon header", [
        (Z, "    if dungeons and e.tags and e.tags.dungeon then return DUNGEONS end\n",
            "    if dungeons and e.tags.dungeon then return DUNGEONS end\n")]),
    ("with zone headers off, every quest is keyed by its zone", [
        (Z, "    if zones then return e.zone or \"\" end\n    return \"\"\nend\n", "    return e.zone or \"\"\nend\n")]),
    ("the run key reads a truthy switch as on", [
        (Z, "    return runKey(e, cfg ~= nil and cfg.zoneHeaders == true, cfg ~= nil and cfg.dungeonHeader == true)\n",
            "    return runKey(e, cfg ~= nil and cfg.zoneHeaders, cfg ~= nil and cfg.dungeonHeader)\n")]),
    ("the run key never sees the dungeon switch", [
        (Z, "    return runKey(e, cfg ~= nil and cfg.zoneHeaders == true, cfg ~= nil and cfg.dungeonHeader == true)\n",
            "    return runKey(e, cfg ~= nil and cfg.zoneHeaders == true, false)\n")]),
    ("Grouping leaves the dungeon header out", [
        (Z, "    return cfg ~= nil and (cfg.zoneHeaders == true or cfg.dungeonHeader == true)\n",
            "    return cfg ~= nil and cfg.zoneHeaders == true\n")]),
    ("Grouping reads a truthy switch as on", [
        (Z, "    return cfg ~= nil and (cfg.zoneHeaders == true or cfg.dungeonHeader == true)\n",
            "    return cfg ~= nil and (cfg.zoneHeaders or cfg.dungeonHeader) and true or false\n")]),
    # AceDB hands a switch over as false, never nil, so a test against nil is always true in game.
    ("Grouping reads a dungeon switch stored off as on", [
        (Z, "(cfg.zoneHeaders == true or cfg.dungeonHeader == true)", "(cfg.zoneHeaders == true or cfg.dungeonHeader ~= nil)")]),
    ("Grouping reads a zone switch stored off as on", [
        (Z, "(cfg.zoneHeaders == true or cfg.dungeonHeader == true)", "(cfg.zoneHeaders ~= nil or cfg.dungeonHeader == true)")]),
    ("the run key reads a dungeon switch stored off as on", [
        (Z, "    return runKey(e, cfg ~= nil and cfg.zoneHeaders == true, cfg ~= nil and cfg.dungeonHeader == true)\n",
            "    return runKey(e, cfg ~= nil and cfg.zoneHeaders == true, cfg ~= nil and cfg.dungeonHeader ~= nil)\n")]),
    ("Build groups for a dungeon switch stored off", [
        (Z, "    local dungeons = cfg ~= nil and cfg.dungeonHeader == true\n    sortAlpha",
            "    local dungeons = cfg ~= nil and cfg.dungeonHeader ~= nil\n    sortAlpha")]),
    ("Begin tallies for a dungeon switch stored off", [
        (Z, "    noteDungeons = cfg ~= nil and cfg.dungeonHeader == true\n",
            "    noteDungeons = cfg ~= nil and cfg.dungeonHeader ~= nil\n")]),
    # A comparison that contradicts itself, which a fixture of several runs can still sort right.
    ("Dungeons leads whenever any current zone is in the pair", [
        (Z, "        local lead = currentFirst and not dungeonsLast and d.current\n",
            "        local lead = currentFirst and not dungeonsLast and (a.current or b.current)\n")]),
    # The sticky band with both switches on.
    ("the band drops the zone row whenever the Dungeons header is on", [
        (T, "                    local zoneSticky = sticky and cfg and cfg.zoneHeaders == true\n",
            "                    local zoneSticky = sticky and cfg and cfg.zoneHeaders == true and not cfg.dungeonHeader\n")]),
    ("Dungeons at the top is drawn in the list as well as in the band", [
        (T, "if zoneSticky and y == 0 and stickyZ == zFirst[stickyN] then",
            "if zoneSticky and y == 0 and stickyZ == zFirst[stickyN] and not run.dungeon then")]),
    ("Dungeons keeps the place the sort gave it", [
        (Z, "    if a.dungeon ~= b.dungeon then\n", "    if false then\n")]),
    ("Dungeons always goes last", [
        (Z, "        local lead = currentFirst and not dungeonsLast and d.current\n", "        local lead = false\n")]),
    ("Dungeons leads while none of its quests is here", [
        (Z, "        local lead = currentFirst and not dungeonsLast and d.current\n",
            "        local lead = currentFirst and not dungeonsLast and not d.current\n")]),
    ("Keep Dungeons at the bottom is ignored", [
        (Z, "        local lead = currentFirst and not dungeonsLast and d.current\n",
            "        local lead = currentFirst and d.current\n")]),
    ("Build never reads Keep Dungeons at the bottom", [
        (Z, "    dungeonsLast = cfg ~= nil and cfg.dungeonHeaderLast == true\n", "    dungeonsLast = false\n")]),
    ("Keep Dungeons at the bottom reads any stored value as on", [
        (Z, "    dungeonsLast = cfg ~= nil and cfg.dungeonHeaderLast == true\n",
            "    dungeonsLast = cfg ~= nil and cfg.dungeonHeaderLast and true or false\n")]),
    ("a later pass keeps Keep Dungeons at the bottom on after it is switched off", [
        (Z, "    dungeonsLast = cfg ~= nil and cfg.dungeonHeaderLast == true\n",
            "    if cfg ~= nil and cfg.dungeonHeaderLast == true then dungeonsLast = true end\n")]),
    ("the status line never says Dungeons is kept at the bottom", [
        (Z, "(cfg.dungeonHeaderLast == true and \", dungeon header on, kept at the bottom\" or \", dungeon header on\")",
            "\", dungeon header on\"")]),
    ("the status line reports any stored value as kept at the bottom", [
        (Z, "(cfg.dungeonHeaderLast == true and \", dungeon header on, kept at the bottom\"",
            "(cfg.dungeonHeaderLast and \", dungeon header on, kept at the bottom\"")]),
    ("Keep Dungeons at the bottom ships on", [
        (D, "            dungeonHeaderLast       = false,\n", "            dungeonHeaderLast       = true,\n")]),
    ("Reset to Defaults clears Keep Dungeons at the bottom", [
        (D, "    \"zoneHeaderSizeDelta\", \"zoneHeaderColor\", \"zoneHeaderColorUseClass\", \"zoneHeaderBar\",\n",
            "    \"dungeonHeaderLast\", \"zoneHeaderSizeDelta\", \"zoneHeaderColor\", \"zoneHeaderColorUseClass\", \"zoneHeaderBar\",\n")]),
    ("Dungeons always goes first", [
        (Z, "        if a.dungeon then return lead end\n        return not lead\n",
            "        if a.dungeon then return true end\n        return false\n")]),
    ("Dungeons comes to the top under Alphabetical too", [
        (Z, "    currentFirst = zones and not sortAlpha\n", "    currentFirst = zones\n")]),
    ("Dungeons comes to the top with zone headers off", [
        (Z, "    currentFirst = zones and not sortAlpha\n", "    currentFirst = not sortAlpha\n")]),
    ("any run counts as Dungeons under the dungeon header", [
        (Z, "            run.dungeon = dungeons and z == DUNGEONS\n", "            run.dungeon = dungeons\n")]),
    ("a reused run keeps its Dungeons flag", [
        (Z, "            run.dungeon = dungeons and z == DUNGEONS\n",
            "            if dungeons and z == DUNGEONS then run.dungeon = true end\n")]),
    ("the tally keys every quest by its zone, so Dungeons counts nothing", [
        (Z, "    local z = runKey(entry, noteZones, noteDungeons)\n", "    local z = entry.zone or \"\"\n")]),
    ("Begin never learns the dungeon switch", [
        (Z, "    noteDungeons = cfg ~= nil and cfg.dungeonHeader == true\n", "    noteDungeons = false\n")]),
    ("Begin never learns the zone switch", [
        (Z, "    noteZones    = cfg ~= nil and cfg.zoneHeaders == true\n", "    noteZones    = false\n")]),
    ("Build splits nothing for the dungeon header alone", [
        (Z, "        if (zones or dungeons) and self.GROUPS[id] and g.visibleCount > 0 then\n",
            "        if zones and self.GROUPS[id] and g.visibleCount > 0 then\n")]),
    ("Build hands the runs no dungeon switch", [
        (Z, "            build(stateFor(id), g, Registry, zones, dungeons)\n",
            "            build(stateFor(id), g, Registry, zones, false)\n")]),
    ("Build reads the dungeon switch as the zone switch", [
        (Z, "    local dungeons = cfg ~= nil and cfg.dungeonHeader == true\n    sortAlpha",
            "    local dungeons = cfg ~= nil and cfg.zoneHeaders == true\n    sortAlpha")]),
    ("the status line reads off for the dungeon header alone", [
        (Z, "    if not (zones or dungeons) then return \"zone headers: off\" end\n",
            "    if not zones then return \"zone headers: off\" end\n")]),
    ("the status line never names the dungeon header", [
        (Z, "    if dungeons then\n        head = head .. (cfg.dungeonHeaderLast == true and \", dungeon header on, kept at the bottom\""
            " or \", dungeon header on\")\n    end\n", "")]),
    ("the Dungeons run is named in English on every client", [
        (Z, "local DUNGEONS = L[\"Dungeons\"]\n", "local DUNGEONS = \"Dungeons\"\n")]),
    ("Feed tallies nothing for the dungeon header alone", [
        (F, "    local zoned = ZoneGroups and ZoneGroups:Grouping(cfg)\n",
            "    local zoned = ZoneGroups and cfg and cfg.zoneHeaders == true\n")]),
    ("Feed starts the tally without the settings", [
        (F, "    if zoned then ZoneGroups:Begin(cfg) end\n", "    if zoned then ZoneGroups:Begin() end\n")]),
    ("the Dungeons header does not indent its quests with zone headers off", [
        (H, "    if not (cfg and (cfg.zoneHeaders or cfg.dungeonHeader)) then return 0 end\n",
            "    if not (cfg and cfg.zoneHeaders) then return 0 end\n")]),
    ("a drag under the dungeon header alone spans the whole section", [
        (G, "    self.dragZone  = ZoneGroups:Grouping(cfg) and ZoneGroups:RunKey(e, cfg) or nil\n",
            "    self.dragZone  = (cfg and cfg.zoneHeaders) and ZoneGroups:RunKey(e, cfg) or nil\n")]),
    ("a drag remembers the quest's zone rather than its run", [
        (G, "    self.dragZone  = ZoneGroups:Grouping(cfg) and ZoneGroups:RunKey(e, cfg) or nil\n",
            "    self.dragZone  = ZoneGroups:Grouping(cfg) and (e.zone or \"\") or nil\n")]),
    ("the drop scope compares each row's zone rather than its run", [
        (G, "(zone == nil or ZoneGroups:RunKey(e, cfg) == zone)", "(zone == nil or (e.zone or \"\") == zone)")]),
    ("the dungeon header ships on", [
        (D, "            dungeonHeader           = false,\n", "            dungeonHeader           = true,\n")]),
    # Heroic dungeon quests (TBC's dailies) count as dungeon quests (the author, 2026-10-11).
    ("retail: a heroic dungeon quest is not a dungeon quest", [
        (Q, "    if tagID == TAG_DUNGEON or tagID == TAG_HEROIC then\n", "    if tagID == TAG_DUNGEON then\n")]),
    ("retail: Heroic's fallback number is wrong", [
        (Q, "local TAG_HEROIC  = (Enum and Enum.QuestTag and Enum.QuestTag.Heroic)  or 85\n",
            "local TAG_HEROIC  = (Enum and Enum.QuestTag and Enum.QuestTag.Heroic)  or 88\n")]),
    ("retail: the client's own Heroic number is never read", [
        (Q, "local TAG_HEROIC  = (Enum and Enum.QuestTag and Enum.QuestTag.Heroic)  or 85\n",
            "local TAG_HEROIC  = 85\n")]),
    ("retail: a heroic quest counts as a raid quest", [
        (Q, "    if tagID == TAG_DUNGEON or tagID == TAG_HEROIC then\n", "    if tagID == TAG_DUNGEON then\n"),
        (Q, "    elseif tagID == TAG_RAID or tagID == TAG_RAID10 or tagID == TAG_RAID25 then\n",
            "    elseif tagID == TAG_RAID or tagID == TAG_RAID10 or tagID == TAG_RAID25 or tagID == TAG_HEROIC then\n")]),
    ("Classic: a heroic dungeon quest is not a dungeon quest", [
        (QC, "    if tagID == TAG_DUNGEON or tagID == TAG_HEROIC then\n", "    if tagID == TAG_DUNGEON then\n")]),
    ("Classic: Heroic's fallback number is wrong", [
        (QC, "local TAG_HEROIC  = (Enum and Enum.QuestTag and Enum.QuestTag.Heroic)  or 85\n",
             "local TAG_HEROIC  = (Enum and Enum.QuestTag and Enum.QuestTag.Heroic)  or 88\n")]),
    ("Classic: the client's own Heroic number is never read", [
        (QC, "local TAG_HEROIC  = (Enum and Enum.QuestTag and Enum.QuestTag.Heroic)  or 85\n",
             "local TAG_HEROIC  = 85\n")]),
    ("Classic: a heroic quest counts as a raid quest", [
        (QC, "    if tagID == TAG_DUNGEON or tagID == TAG_HEROIC then\n", "    if tagID == TAG_DUNGEON then\n"),
        (QC, "    elseif tagID == TAG_RAID or tagID == TAG_RAID10 or tagID == TAG_RAID25 then\n",
             "    elseif tagID == TAG_RAID or tagID == TAG_RAID10 or tagID == TAG_RAID25 or tagID == TAG_HEROIC then\n")]),
    ("Reset to Defaults switches the dungeon header off", [
        (D, "    \"zoneHeaderSizeDelta\", \"zoneHeaderColor\", \"zoneHeaderColorUseClass\", \"zoneHeaderBar\",\n",
            "    \"dungeonHeader\", \"zoneHeaderSizeDelta\", \"zoneHeaderColor\", \"zoneHeaderColorUseClass\", \"zoneHeaderBar\",\n")]),

    # ---- after the second 2.3.0 scan: the zone label under Dungeons, the band, the client's
    # compare under Alphabetical, and the status line
    ("with the Dungeons header alone every ordinary quest loses its label", [
        (R, HEADED, HEADED[:-1] + " or (cfg and cfg.dungeonHeader == true and not (entry.tags and entry.tags.dungeon))\n")]),
    ("Keep Dungeons at the bottom drops the dungeon quests' label", [
        (R, "entry.tags.dungeon)\n    local subtitle", "entry.tags.dungeon and not cfg.dungeonHeaderLast)\n    local subtitle")]),
    ("Alphabetical zone order drops the dungeon quests' label", [
        (R, "(cfg.dungeonHeader == true and entry.tags", "(cfg.dungeonHeader == true and cfg.zoneHeaderOrder ~= \"alpha\" and entry.tags")]),
    ("the label is kept only for a dungeon quest with no heading", [
        (R, "entry.tags.dungeon)\n    local subtitle", "entry.tags.dungeon and not entry.zone)\n    local subtitle")]),
    ("Campaign dungeon quests lose the label", [
        (R, "entry.tags.dungeon)\n    local subtitle", "entry.tags.dungeon and entry.groupID ~= \"campaign\")\n    local subtitle")]),
    ("a later multiple assignment brings the label back", [
        (R, "    buildBlocks(entry, cfg)\n    local lineText = blocksKey()\n",
            "    buildBlocks(entry, cfg)\n    local lineText = blocksKey()\n    subtitle, lineText = entry.subtitle, lineText\n")]),
    ("a bracketed write ahead of the rule clears the label under zone headers", [
        (R, HEADED, "    if cfg and cfg.zoneHeaders then entry[\"subtitle\"] = nil end\n" + HEADED)]),
    ("the label is drawn from the entry, not the one worked out", [
        (R, "    if subtitle and subtitle ~= \"\" then\n        row.subtitle:SetText(subtitle)\n",
            "    if entry.subtitle and entry.subtitle ~= \"\" then\n        row.subtitle:SetText(entry.subtitle)\n")]),
    ("the repaint gate compares the entry's label, so a label switched off lingers", [
        (R, "       and row._sSub   == subtitle\n", "       and row._sSub   == entry.subtitle\n")]),
    ("a Dungeons run below the top is left out of the band", [
        (T, "                            if zoneSticky then\n                                stickyZ = stickyZ + 1\n",
            "                            if zoneSticky and (y == 0 or not run.dungeon) then\n                                stickyZ = stickyZ + 1\n")]),
    ("the client's compare puts a current zone first under Alphabetical", [
        (Z, "        if c ~= 0 then return c < 0 end\n", "        if c ~= 0 then return c < 0 or a.current end\n")]),
    ("the client's compare answers true for a tie", [
        (Z, "        if c ~= 0 then return c < 0 end\n        return a.zone < b.zone\n",
            "        if c ~= 0 then return c < 0 end\n        return a.zone <= b.zone\n")]),
    ("the status line lists only the last current zone", [
        (Z, "                if run.current then here[#here + 1] = run.zone end\n",
            "                if run.current then here[1] = run.zone end\n")]),
    ("the status line joins the current zones with a space", [
        (Z, "#here > 0 and table.concat(here, \", \") or \"none\")", "#here > 0 and table.concat(here, \" \") or \"none\")")]),
    ("the status line walks the whole run table, so an emptied section's old zones are listed", [
        (Z, "        for r = 1, g and g.zoneCount or 0 do\n", "        for r = 1, g and #g.zoneRuns or 0 do\n")]),
    ("the status line reports the dungeon header on for a switch stored off", [
        (Z, "    local dungeons = cfg ~= nil and cfg.dungeonHeader == true\n    if not (zones or dungeons) then return",
            "    local dungeons = cfg ~= nil and cfg.dungeonHeader ~= nil\n    if not (zones or dungeons) then return")]),

    # ---- after the third scan: how the label is drawn and written, what else of the quest or the
    # profile its rule may not read, the band's scroll position and Keep at the bottom, a heading
    # named Dungeons, and the status line
    ("the kept label is hidden under zone headers by the draw branch", [
        (R, "        row.subtitle:SetText(subtitle)\n        row.subtitle:Show()\n",
            "        row.subtitle:SetText(subtitle)\n        row.subtitle:SetShown(not (cfg and cfg.zoneHeaders))\n")]),
    ("a label switched off leaves its line shown, blank", [
        (R, "        row.subtitle:SetText(\"\")\n        row.subtitle:Hide()\n", "        row.subtitle:SetText(\"\")\n")]),
    ("a finished dungeon quest loses its label under the Dungeons header", [
        (R, "entry.tags.dungeon)\n    local subtitle", "entry.tags.dungeon and entry.state ~= \"complete\")\n    local subtitle")]),
    ("raid quests keep their label under zone headers with the Dungeons header on", [
        (R, "and entry.tags.dungeon)\n    local subtitle", "and (entry.tags.dungeon or entry.tags.raid))\n    local subtitle")]),
    ("the followed quest keeps its label under zone headers", [
        (R, "not (cfg.dungeonHeader == true and entry.tags", "not (entry.isFocused or cfg.dungeonHeader == true and entry.tags")]),
    ("the label hides with the objective numbers switch", [
        (R, "cfg.showZoneTag ~= false and not headed", "cfg.showZoneTag ~= false and cfg.showObjectiveNumbers ~= false and not headed")]),
    ("retail quests carry no zone label", [
        (Q, "                e.subtitle  = currentHeader\n", "                e.subtitle  = nil\n")]),
    ("Classic quests carry no zone label", [
        (QC, "                e.subtitle  = currentHeader\n", "                e.subtitle  = nil\n")]),
    ("the Dungeons header never records where it sits for scroll-into-view", [
        (T, "                            zoneTops[zoneKey] = y\n",
            "                            if not run.dungeon then zoneTops[zoneKey] = y end\n")]),
    ("with Keep at the bottom on, a Dungeons header at the top stays in the list", [
        (T, "if zoneSticky and y == 0 and stickyZ == zFirst[stickyN] then",
            "if zoneSticky and y == 0 and stickyZ == zFirst[stickyN] and not (run.dungeon and cfg.dungeonHeaderLast) then")]),
    ("a heading named Dungeons sorts last with the Dungeons header off", [
        (Z, "            run.dungeon = dungeons and z == DUNGEONS\n", "            run.dungeon = z == DUNGEONS\n")]),
    ("the status line forgets Keep at the bottom with zone headers off", [
        (Z, "    if dungeons then\n        head = head .. (cfg.dungeonHeaderLast == true",
            "    if dungeons then\n        head = head .. (zones and cfg.dungeonHeaderLast == true")]),

    # The final check's spellings, after the bounded round.
    ("a line after the draw branch hides the kept label under zone headers", [
        (R, "        row.subtitle:Hide()\n        anchor = row.title\n    end\n",
            "        row.subtitle:Hide()\n        anchor = row.title\n    end\n"
            "    if cfg and cfg.zoneHeaders then row.subtitle:Hide() end\n")]),
    ("retail clears the label in a multiple assignment", [
        (Q, "                e.level     = info.level\n", "                e.subtitle, e.level = nil, info.level\n")]),
    ("Classic clears the label through a bracketed field", [
        (QC, "                e.zone      = currentHeader\n                e.level     = t[T_LEVEL]\n",
             "                e.zone      = currentHeader\n                e[\"subtitle\"] = nil\n"
             "                e.level     = t[T_LEVEL]\n")]),
]

SUMMARY = re.compile(r"^test_zone_headers: (\d+) passed, (\d+) failed$")


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
