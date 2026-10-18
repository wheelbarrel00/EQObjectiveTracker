"""Prove docs/test_tabs.lua actually discriminates, by breaking production on purpose one change
at a time and checking the harness notices.

    python -B docs/mutate_tabs.py        (run from the repo root)

Why this exists: section tabs fail quietly. A section filed under the wrong tab vanishes from the
tracker with nothing to say where it went, a strip that shows with nothing moved changes every
player's tracker, content left under the strip is drawn over by it, and a tab switch in combat
leaves item buttons over the wrong rows. None of that raises a Lua error.

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
HARNESS = "docs/test_tabs.lua"

T = "UI/Tracker.lua"
V = "UI/Visibility.lua"
D = "Core/DB.lua"
C = "Core/Compat.lua"

FOREVER_RANGE = "    return toc ~= nil and toc >= 16000 and toc < 17000\n"

READ = "    if t and t >= 1 and t <= MAX_TABS then return math.floor(t) end\n"
ON = "    if not (cfg and cfg.showTabs == true) or not self:TabsOffered() then return nil end\n"
OFFERED_COUNT = "        if not (Sections:IsVirtual(id) or Sections:IsContainer(id)) then n = n + 1 end\n"
RESET = "    for i = 1, MAX_TABS do usedTabs[i] = false end\n"
SKIP_CONTAINER = "        if drawsOnTab(Sections, id) then\n            local t = self:SectionTab(id)\n"
DRAWS_SKIP = "    if Sections:IsContainer(id) or Sections:IsHidden(id) then return false end\n"
DRAWS_ZONE = "        return (ZoneBar and ZoneBar:IsDocked()) and true or false\n"
KEPT = "    if t and used[t] then return t end\n"
FALLBACK = "    for i = 1, MAX_TABS do\n        if used[i] then return i end\n    end\n"
SET_GUARD = ("    if secureLocked() then\n        self._pendingTab = t\n"
             "        ns:GetModule(\"Events\"):RunWhenOutOfCombat(\"eqot.activeTab\", applyPendingTab)\n"
             "        return\n    end\n")
PENDING = "    local t = Tracker._pendingTab\n    Tracker._pendingTab = nil\n    if t then Tracker:SetActiveTab(t) end\n"
SWITCHED = "    local before = self:ActiveTab()\n"
TO_TOP = ("    if self:ActiveTab() ~= before and self.frame and self.frame.scroll then "
          "self.frame.scroll:SetVerticalScroll(0) end\n")
ACTIVE_PAINT = ("        b.bg:SetColorTexture(0, 0, 0, 0.35)\n        b.line:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 1)\n"
                "        b.text:SetTextColor(1, 1, 1)\n")
IDLE_PAINT = ("        b.bg:SetColorTexture(0, 0, 0, 0.15)\n        b.line:SetColorTexture(1, 1, 1, 0.15)\n"
              "        b.text:SetTextColor(0.6, 0.6, 0.6)\n")
CLICK = ("    b:SetScript(\"OnClick\", function(btn)\n        if Tracker:IsClickThrough() then return end\n"
         "        Tracker:SetActiveTab(btn.tab)\n")
ENTER = "        if Tracker:IsClickThrough() or not btn._label then return end\n"
WIDTH = "    local w = (width - (n - 1) * 2) / n\n"
PLACE = '            b:SetPoint("TOPLEFT", strip, "TOPLEFT", (i - 1) * (w + 2), 0)\n'
NAMES = "                if drawsOnTab(Sections, id) and self:SectionTab(id) == t then\n"
LABEL = "            if b._label ~= label then\n"
ORDER_GUARD = "    if not active then return order end\n    local Popups = ns:GetModule(\"AutoQuestPopups\")\n    wipe(onTab)\n"
ORDER_KEEP = "        if self:SectionTab(id) == active or (Popups and Popups:CountFor(id) > 0) then\n"
GROUP_TEST = "    if active and self:SectionTab(groupID) ~= active then return EMPTY_GROUP end\n"
GROUP_LINE = "            local group      = self:_GroupOnTab(groupID, byGroup[groupID], activeTab)\n"
TOP = "    local top = DRAG_HANDLE_H + (self:TabsInUse() and TAB_STRIP_H or 0)\n"
INSET_GUARD = "    if f._scrollGutter == gutter and f._contentTop == top then return end\n"
INSET_STORE = "    f._scrollGutter, f._contentTop = gutter, top\n"
LOOP = "    for _, groupID in ipairs(self:_OrderOnTab(Sections:Order(), activeTab)) do\n"
WAIT = "    if activeTab and f._contentTop ~= DRAG_HANDLE_H + TAB_STRIP_H then activeTab = nil end\n"
KEEP_TAB = "    self._activeTab = activeTab\n    self:LayoutTabs(activeTab)\n"
ZONE_IF = "    if activeTab and self:SectionTab(\"zoneprogress\") ~= activeTab then\n"
ZONE_HIDE = "        if ZoneBar then ZoneBar:HideDocked() end\n"
LINE_OFF = "    if not (cfg and cfg.showTabs == true) then return \"tabs: off\" end\n"

MUTANTS = [
    # ------------------------------------------------------------------------------ SectionTab
    ("a tab below 1 is kept", [(T, READ, "    if t and t <= MAX_TABS then return math.floor(t) end\n")]),
    ("a tab past 3 is kept", [(T, READ, "    if t and t >= 1 then return math.floor(t) end\n")]),
    ("a fraction is kept as it is", [(T, READ, "    if t and t >= 1 and t <= MAX_TABS then return t end\n")]),
    ("an unmoved section reads as tab 0", [(T, READ + "    return 1\n", READ + "    return 0\n")]),
    ("a tab saved as text is not read", [
        (T, "    local t = cfg and cfg.sectionTab and tonumber(cfg.sectionTab[groupID])\n",
            "    local t = cfg and cfg.sectionTab and cfg.sectionTab[groupID]\n"
            "    if type(t) ~= \"number\" then t = nil end\n")]),

    # ------------------------------------------------------------------------------- TabsInUse
    ("any truthy setting turns tabs on", [
        (T, ON, "    if not (cfg and cfg.showTabs) or not self:TabsOffered() then return nil end\n")]),
    ("a profile's tabs show where they are not offered", [
        (T, ON, "    if not (cfg and cfg.showTabs == true) then return nil end\n")]),
    ("one section that can take a tab is enough to offer them", [
        (T, "    return n >= 2\nend\n\n-- Filled in place", "    return n >= 1\nend\n\n-- Filled in place")]),
    ("the zone bar counts toward offering tabs", [
        (T, OFFERED_COUNT, "        if not Sections:IsContainer(id) then n = n + 1 end\n")]),
    ("the scenario panel counts toward offering tabs", [
        (T, OFFERED_COUNT, "        if not Sections:IsVirtual(id) then n = n + 1 end\n")]),
    ("the Tracker tab is told every section draws on a tab", [
        (T, '    return drawsOnTab(ns:GetModule("Sections"), groupID)\n', "    return true\n")]),
    ("one tab in use shows the strip", [(T, "    if n < 2 then return nil end\n", "    if n < 1 then return nil end\n")]),
    ("the tabs in use are never cleared between asks", [(T, RESET, "")]),
    ("the tabs in use ask nothing of a section", [
        (T, SKIP_CONTAINER, "        do\n            local t = self:SectionTab(id)\n")]),
    ("the scenario panel makes a tab of its own", [
        (T, DRAWS_SKIP, "    if Sections:IsHidden(id) then return false end\n")]),
    ("a hidden section makes a tab", [(T, DRAWS_SKIP, "    if Sections:IsContainer(id) then return false end\n")]),
    ("the zone bar makes a tab while it floats", [(T, DRAWS_ZONE, "        return true\n")]),
    ("the zone bar never makes a tab, even docked", [(T, DRAWS_ZONE, "        return false\n")]),
    ("the count is never kept", [(T, "                usedTabs[t] = true\n                n = n + 1\n",
                                     "                usedTabs[t] = true\n")]),

    # ------------------------------------------------------------------------------- ActiveTab
    ("a chosen tab holding nothing is kept", [(T, KEPT, "    if t then return t end\n")]),
    ("with no choice there is no tab on screen", [(T, FALLBACK, "")]),
    ("the choice is never read", [(T, KEPT, "")]),

    # ---------------------------------------------------------------------------- SetActiveTab
    ("a tab switch goes through in combat", [(T, SET_GUARD, "")]),
    ("a tab clicked in combat is never queued", [
        (T, SET_GUARD, SET_GUARD.replace(
            "        ns:GetModule(\"Events\"):RunWhenOutOfCombat(\"eqot.activeTab\", applyPendingTab)\n", ""))]),
    ("a tab clicked in combat is queued under another key", [
        (T, SET_GUARD, SET_GUARD.replace("\"eqot.activeTab\"", "\"eqot.deferredRender\""))]),
    ("the tab clicked in combat is forgotten", [(T, SET_GUARD, SET_GUARD.replace("        self._pendingTab = t\n", ""))]),
    ("the queue opens nothing when the fight ends", [
        (T, PENDING, "    local t = Tracker._pendingTab\n    Tracker._pendingTab = nil\n")]),
    ("the queue is never emptied", [(T, PENDING, PENDING.replace("    Tracker._pendingTab = nil\n", ""))]),
    ("a tab switch is never stored", [(T, "    char.activeTab = t\n", "")]),
    ("a tab switch never redraws", [(T, TO_TOP + "    self:Render()\n", TO_TOP)]),
    ("a new tab opens where the last one was scrolled", [(T, TO_TOP, "")]),
    ("every click scrolls to the top", [(T, TO_TOP, TO_TOP.replace("self:ActiveTab() ~= before and ", ""))]),
    ("the switch is judged by the tab clicked, not the tab shown", [
        (T, TO_TOP, TO_TOP.replace("self:ActiveTab() ~= before", "t ~= before"))]),
    ("the switch is judged after the new tab is stored", [
        (T, SWITCHED + "    char.activeTab = t\n", "    char.activeTab = t\n" + SWITCHED)]),

    # -------------------------------------------------------------------------------- painting
    ("the tab on screen is not underlined in gold", [
        (T, ACTIVE_PAINT, ACTIVE_PAINT.replace("GOLD_R, GOLD_G, GOLD_B, 1", "1, 1, 1, 0.15"))]),
    ("the tab on screen reads grey", [(T, ACTIVE_PAINT, ACTIVE_PAINT.replace("SetTextColor(1, 1, 1)", "SetTextColor(0.6, 0.6, 0.6)"))]),
    ("the other tabs read bright", [(T, IDLE_PAINT, IDLE_PAINT.replace("SetTextColor(0.6, 0.6, 0.6)", "SetTextColor(1, 1, 1)"))]),

    # ------------------------------------------------------------------------------ the buttons
    ("a click-through tracker switches tabs", [
        (T, CLICK, "    b:SetScript(\"OnClick\", function(btn)\n        Tracker:SetActiveTab(btn.tab)\n")]),
    ("every button opens tab 1", [(T, CLICK, CLICK.replace("SetActiveTab(btn.tab)", "SetActiveTab(1)"))]),
    ("a click-through tracker shows the tooltip", [(T, ENTER, "        if not btn._label then return end\n")]),
    ("the tooltip names nothing", [(T, "        tip:SetText(btn._label, 1, 1, 1)\n", "        tip:SetText(\"\", 1, 1, 1)\n")]),
    ("the tooltip never goes", [(T, "    b:SetScript(\"OnLeave\", function() ns.Util.Tooltip():Hide() end)\n    return b\n",
                                     "    return b\n")]),
    ("the label wraps", [(T, "    b.text:SetWordWrap(false)\n", "")]),

    # ------------------------------------------------------------------------------- LayoutTabs
    ("the strip never hides", [(T, "    if not used then\n        strip:Hide()\n        return\n",
                                   "    if not used then\n        return\n")]),
    ("the strip never shows", [(T, "            b:Show()\n        end\n    end\n    strip:Show()\n",
                                   "            b:Show()\n        end\n    end\n")]),
    ("the buttons take no gap", [(T, WIDTH, "    local w = width / n\n")]),
    ("the buttons sit on top of each other", [(T, PLACE, '            b:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, 0)\n')]),
    ("the buttons overlap by the gap", [(T, PLACE, '            b:SetPoint("TOPLEFT", strip, "TOPLEFT", (i - 1) * w, 0)\n')]),
    ("a button no longer needed stays", [(T, "            if b then b:Hide() end\n", "")]),
    ("a button opens its slot, not its tab", [(T, "            b.tab = t\n", "            b.tab = i\n")]),
    ("the slot, not the tab, is lit", [(T, "            paintTab(b, t == active)\n", "            paintTab(b, i == active)\n")]),
    ("the scenario panel is named on tab 1", [(T, NAMES, "                if self:SectionTab(id) == t then\n")]),
    ("the label is set on every layout", [(T, LABEL, "            if true then\n")]),
    ("the label is never set", [(T, "                b.text:SetText(label)\n", "")]),

    # ----------------------------------------------------------------------------- _OrderOnTab
    ("the render filters with no tab strip", [
        (T, ORDER_GUARD, "    local Popups = ns:GetModule(\"AutoQuestPopups\")\n    wipe(onTab)\n")]),
    ("the render keeps the other tabs' sections", [
        (T, ORDER_KEEP, "        if self:SectionTab(id) ~= active or (Popups and Popups:CountFor(id) > 0) then\n")]),
    ("the filtered order keeps the last call's sections", [
        (T, ORDER_GUARD, "    if not active then return order end\n    local Popups = ns:GetModule(\"AutoQuestPopups\")\n")]),

    # ------------------------------------- popup boxes on every tab (the author's call, 2026-10-16)
    ("the order asks the box module, not the one that counts them", [
        (T, ORDER_GUARD, ORDER_GUARD.replace('"AutoQuestPopups"', '"AutoQuestPopup"'))]),
    ("a section with popup boxes stays on its own tab", [
        (T, ORDER_KEEP, "        if self:SectionTab(id) == active then\n")]),
    ("every section joins while the popup module is loaded, boxes or not", [
        (T, ORDER_KEEP, "        if self:SectionTab(id) == active or Popups then\n")]),
    ("a single popup box is not enough to join", [
        (T, ORDER_KEEP, "        if self:SectionTab(id) == active or (Popups and Popups:CountFor(id) > 1) then\n")]),
    ("the popup module is asked with a dot call", [
        (T, ORDER_KEEP, "        if self:SectionTab(id) == active or (Popups and Popups.CountFor(id) > 0) then\n")]),
    ("a section drawn on another tab brings its rows", [(T, GROUP_TEST, "    if false then return EMPTY_GROUP end\n")]),
    ("every section draws the empty group while tabs are on", [(T, GROUP_TEST, "    if active then return EMPTY_GROUP end\n")]),
    ("a section Feed made no group for gets nothing to draw into", [
        (T, "    return group or EMPTY_GROUP\n", "    return group\n")]),
    ("the empty group counts a row", [
        (T, "local EMPTY_GROUP = { visibleCount = 0, totalCount = 0, entries = {} }\n",
            "local EMPTY_GROUP = { visibleCount = 1, totalCount = 0, entries = {} }\n")]),
    ("Render takes its group straight off the feed again", [
        (T, GROUP_LINE, "            local group      = byGroup[groupID] or EMPTY_GROUP\n")]),
    ("Render hands the helper no tab, so a visiting section brings its rows", [
        (T, GROUP_LINE, GROUP_LINE.replace("byGroup[groupID], activeTab)", "byGroup[groupID], nil)"))]),

    # -------------------------------------------------------------------------- content inset
    ("the content stays under the strip", [(T, TOP, "    local top = DRAG_HANDLE_H\n")]),
    ("a move of the strip alone is never applied", [
        (T, INSET_GUARD, "    if f._scrollGutter == gutter then return end\n")]),
    ("the content's top is never kept", [(T, INSET_STORE, "    f._scrollGutter = gutter\n")]),
    ("the content moves in combat", [
        (T, "    if secureLocked() then\n        ns:GetModule(\"Events\"):RunWhenOutOfCombat(\"eqot.contentInset\"",
            "    if false then\n        ns:GetModule(\"Events\"):RunWhenOutOfCombat(\"eqot.contentInset\"")]),

    # ---------------------------------------------------------------------------- the strip
    ("the strip is built showing", [(T, "    tabStrip:SetHeight(TAB_STRIP_H)\n    tabStrip:Hide()\n",
                                         "    tabStrip:SetHeight(TAB_STRIP_H)\n")]),
    ("the strip sits on the drag strip", [(T, "    tabStrip:SetPoint(\"TOPLEFT\", CONTENT_PAD, -DRAG_HANDLE_H)\n",
                                               "    tabStrip:SetPoint(\"TOPLEFT\", CONTENT_PAD, 0)\n")]),
    ("the strip is a tab shorter than its room", [(T, "    tabStrip:SetHeight(TAB_STRIP_H)\n", "    tabStrip:SetHeight(TAB_STRIP_H - 4)\n")]),
    ("the strip is 20 tall", [(T, "local TAB_STRIP_H      = 18\n", "local TAB_STRIP_H      = 20\n")]),
    ("there are 4 tabs", [(T, "local MAX_TABS         = 3\n", "local MAX_TABS         = 4\n")]),

    # ---------------------------------------------------------------------------- the render
    ("the render walks every section", [
        (T, LOOP, LOOP.replace("ipairs(self:_OrderOnTab(Sections:Order(), activeTab))", "ipairs(Sections:Order())"))]),
    ("the strip is never laid out", [(T, KEEP_TAB, "    self._activeTab = activeTab\n")]),
    ("World Quests never learn the tab on screen", [(T, KEEP_TAB, "    self:LayoutTabs(activeTab)\n")]),
    ("the tabs show before the content moves under the strip", [(T, WAIT, "")]),
    ("the tabs never show, even under the strip", [
        (T, WAIT, "    if activeTab then activeTab = nil end\n")]),
    ("a docked zone bar stays drawn over another tab", [(T, ZONE_HIDE, "")]),
    ("the zone bar is hidden on its own tab", [
        (T, ZONE_IF, ZONE_IF.replace("~= activeTab then", "== activeTab then"))]),
    ("the zone bar is hidden with tabs off", [(T, ZONE_IF, ZONE_IF.replace("activeTab and self:", "self:"))]),
    ("the status line says off with tabs on", [(T, LINE_OFF, "    if true then return \"tabs: off\" end\n")]),
    ("the status line drops the tab on screen", [
        (T, "        table.concat(list, \",\"), tostring(self._activeTab), tostring(char and char.activeTab),\n",
            "        table.concat(list, \",\"), tostring(char and char.activeTab), tostring(char and char.activeTab),\n")]),
    ("the status line never names a queued click", [
        (T, "        tostring(self._pendingTab), tostring(self.frame and self.frame._contentTop))\n",
            "        tostring(nil), tostring(self.frame and self.frame._contentTop))\n")]),
    ("the status line reports tabs on a client that does not offer them", [
        (T, '    if not self:TabsOffered() then return "tabs: on, not offered on this client" end\n', "")]),
    ("World Quests show on every tab", [
        (T, "    if not group or group.visibleCount == 0 or Sections:IsHidden(PINNED_GROUP)\n"
            "       or (self._activeTab and self:SectionTab(PINNED_GROUP) ~= self._activeTab) then\n",
            "    if not group or group.visibleCount == 0 or Sections:IsHidden(PINNED_GROUP) then\n")]),
    ("the list's height ignores the strip", [
        (T, "(f:GetHeight() or 0) - (f._contentTop or DRAG_HANDLE_H) - scenarioH",
            "(f:GetHeight() or 0) - DRAG_HANDLE_H - scenarioH")]),
    ("hovering the strip does not count", [(V, "    if over(f.tabStrip) then return true end\n", "")]),
    ("tabs ship on", [(D, "            showTabs       = false,\n", "            showTabs       = true,\n")]),

    # Scan 1 (2026-10-16): the tab button's look, the list's width, a second write of the tab, and
    # World Quests on another tab.
    ("every tab looks hovered", [(T, '    local hl = b:CreateTexture(nil, "HIGHLIGHT")\n', '    local hl = b:CreateTexture(nil, "ARTWORK")\n')]),
    ("the tab on screen is no darker than the others", [
        (T, "        b.bg:SetColorTexture(0, 0, 0, 0.35)\n", "        b.bg:SetColorTexture(0, 0, 0, 0.15)\n")]),
    ("the label runs under the next tab", [(T, '    b.text:SetPoint("RIGHT", -4, 1)\n', '    b.text:SetPoint("RIGHT", 4, 1)\n')]),
    ("the buttons fill the strip's height", [(T, "    b:SetHeight(TAB_STRIP_H - 2)\n", "    b:SetHeight(TAB_STRIP_H)\n")]),
    ("the underline sits at the top", [
        (T, '    b.line:SetPoint("BOTTOMLEFT")\n    b.line:SetPoint("BOTTOMRIGHT")\n',
            '    b.line:SetPoint("TOPLEFT")\n    b.line:SetPoint("TOPRIGHT")\n')]),
    ("the list's width ignores a slim bar", [
        (T, "    local want = math.max(1, math.floor((f:GetWidth() or 0) + 0.5) - scrollGutter(cfg))\n",
            "    local want = math.max(1, math.floor((f:GetWidth() or 0) + 0.5) - SCROLLBAR_GUTTER)\n")]),
    ("World Quests forget the tab just before their pass", [
        (T, "    local wqH, wqTimed = self:_RenderPinnedWorldQuests(byGroup[PINNED_GROUP], eventsCap, width, cfg)\n",
            "    self._activeTab = nil\n"
            "    local wqH, wqTimed = self:_RenderPinnedWorldQuests(byGroup[PINNED_GROUP], eventsCap, width, cfg)\n")]),
    ("World Quests on another tab still draw", [
        (T, "       or (self._activeTab and self:SectionTab(PINNED_GROUP) ~= self._activeTab) then\n",
            "       or (self._activeTab and self:SectionTab(PINNED_GROUP) == self._activeTab) then\n")]),

    # Scan 2 (2026-10-16): the holes its test lens found.
    ("a docked zone bar on a higher tab stays drawn", [
        (T, ZONE_IF, ZONE_IF.replace("~= activeTab then", "< activeTab then"))]),
    ("the strip's tooltip is drawn invisible", [
        (T, "        tip:SetText(btn._label, 1, 1, 1)\n", "        tip:SetText(btn._label, 1, 1, 1, 0)\n")]),
    ("the fill covers nothing", [(T, "    b.bg = b:CreateTexture(nil, \"BACKGROUND\")\n    b.bg:SetAllPoints()\n",
                                  "    b.bg = b:CreateTexture(nil, \"BACKGROUND\")\n")]),
    ("the label is drawn under the fill", [
        (T, '    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")\n',
            '    b.text = b:CreateFontString(nil, "BACKGROUND", "GameFontHighlightSmall")\n')]),
    ("Hide when no quests counts only the tab on screen", [
        (T, "            if not Sections:IsHidden(gid) then\n                local g = byGroup[gid]\n",
            "            if not Sections:IsHidden(gid) and self:SectionTab(gid) == (self._activeTab or 1) then\n"
            "                local g = byGroup[gid]\n")]),
    ("World Quests forget the tab in a multiple assignment", [
        (T, "    local wqH, wqTimed = self:_RenderPinnedWorldQuests(byGroup[PINNED_GROUP], eventsCap, width, cfg)\n",
            "    self._activeTab, self._wqPass = nil, true\n"
            "    local wqH, wqTimed = self:_RenderPinnedWorldQuests(byGroup[PINNED_GROUP], eventsCap, width, cfg)\n")]),

    # Scan 3 (2026-10-16): the holes its test lens found.
    ("hidden World Quests still earn a tab", [
        (T, DRAWS_SKIP, "    if Sections:IsContainer(id) or (Sections:IsHidden(id) and not Sections:IsPinned(id)) then return false end\n")]),
    ("the tabs in use count hidden World Quests", [
        (T, SKIP_CONTAINER, SKIP_CONTAINER.replace("drawsOnTab(Sections, id) then", "drawsOnTab(Sections, id) or Sections:IsPinned(id) then"))]),
    ("the Tracker tab is told World Quests always draw", [
        (T, '    return drawsOnTab(ns:GetModule("Sections"), groupID)\n',
            '    return drawsOnTab(ns:GetModule("Sections"), groupID) or groupID == PINNED_GROUP\n')]),
    ("a tab that falls back to another keeps the old tab's scroll", [
        (T, TO_TOP, TO_TOP.replace("self:ActiveTab() ~= before and ", "self:ActiveTab() ~= before and self:ActiveTab() == t and "))]),
    ("the status line reads a tabs-off profile on Era as not offered", [
        (T, LINE_OFF + '    if not self:TabsOffered() then return "tabs: on, not offered on this client" end\n',
            '    if not self:TabsOffered() then return "tabs: on, not offered on this client" end\n' + LINE_OFF)]),
    ("the status line reads a content top that was never set as the drag strip's", [
        (T, "tostring(self._pendingTab), tostring(self.frame and self.frame._contentTop))\n",
            "tostring(self._pendingTab), tostring(self.frame and self.frame._contentTop or DRAG_HANDLE_H))\n")]),
    ("the status line raises with no tracker frame", [
        (T, "tostring(self._pendingTab), tostring(self.frame and self.frame._contentTop))\n",
            "tostring(self._pendingTab), tostring(self.frame._contentTop))\n")]),

    # --------------------------------------------------------------------------- WoW Forever
    ("Forever offers tabs for its retail sections", [
        (T, "    if ns.IsForever() then return false end\n", "")]),
    ("Forever's first interface number is not Forever", [
        (C, FOREVER_RANGE, "    return toc ~= nil and toc > 16000 and toc < 17000\n")]),
    ("Forever's last interface number is not Forever", [
        (C, FOREVER_RANGE, "    return toc ~= nil and toc >= 16000 and toc < 16999\n")]),
    ("the next game type's first number reads as Forever", [
        (C, FOREVER_RANGE, "    return toc ~= nil and toc >= 16000 and toc <= 17000\n")]),
    ("a client with no interface number raises", [
        (C, FOREVER_RANGE, "    return toc >= 16000 and toc < 17000\n")]),
    ("the build date is read as the interface number", [
        (C, "    local toc = tonumber((select(4, GetBuildInfo())))\n",
            "    local toc = tonumber((select(3, GetBuildInfo())))\n")]),
    # The pre-ship scan of 2026-10-17: the lines of Render between the group and the header.
    ("Render counts no popup boxes, so a section with only boxes leaves every other tab", [
        (T, "            local popupCount = Popups:CountFor(groupID)\n", "            local popupCount = 0\n")]),
    ("a section with only popup boxes is never drawn", [
        (T, "            local anything   = group.visibleCount + popupCount\n",
            "            local anything   = group.visibleCount\n")]),
    ("each section reads Quests' hide rather than its own", [
        (T, "            if anything > 0 and not Sections:IsHidden(groupID) then\n",
            "            if anything > 0 and not Sections:IsHidden(\"quests\") then\n")]),
    ("a hidden section with popup boxes is drawn", [
        (T, "            if anything > 0 and not Sections:IsHidden(groupID) then\n",
            "            if anything > 0 then\n")]),
    ("the delve header flag asks for another header's call", [
        (C, 'Has.DelveHeader         = method(C_UIWidgetManager, "GetScenarioHeaderDelvesWidgetVisualizationInfo")',
            'Has.DelveHeader         = method(C_UIWidgetManager, "GetScenarioHeaderCurrenciesAndBackgroundWidgetVisualizationInfo")')]),
    ("the delve header flag is on whatever the client has", [
        (C, 'Has.DelveHeader         = method(C_UIWidgetManager, "GetScenarioHeaderDelvesWidgetVisualizationInfo")',
            "Has.DelveHeader         = true")]),
]

SUMMARY = re.compile(r"^test_tabs: (\d+) passed, (\d+) failed$")


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
