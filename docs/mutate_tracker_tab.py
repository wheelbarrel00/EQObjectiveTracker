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
DBF = "Core/DB.lua"

DELVE_SYNC = "            syncDelveRows()\n            content._syncDelveRows = syncDelveRows\n"
DELVE_GATE = "        if ns.Has.DelveHeader and ns:GetModule(\"Registry\"):Get(\"scenarios\") and not ns.IsForever() then\n"
DELVE_SET = ("                        DB()[key] = v\n"
             "                        ns:GetModule(\"Widgets\"):Invalidate()\n"
             "                        render()\n")

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

COG_BOX = ('        headers:Add(self:CreateCheckbox(content, L["Show the options cogwheel on the tracker"],\n'
           '            function() return DB().showOptionsIcon ~= false end,\n'
           '            function(v)\n'
           '                DB().showOptionsIcon = v\n'
           '                ns:GetModule("Tracker"):ApplyHeaderIcons()\n'
           '            end,\n'
           '            L["A small cogwheel at the top-right of the tracker that opens the options panel."]))\n')
SORT_BOX = ('        headers:Add(self:CreateCheckbox(content, L["Show the sort button on the tracker"],\n'
            '            function() return DB().showSortButton == true end,\n'
            '            function(v)\n'
            '                DB().showSortButton = v\n'
            '                ns:GetModule("Tracker"):ApplyHeaderIcons()\n'
            '            end,\n'
            '            L["A small button at the top-left of the tracker that opens a list of the sort orders, so you'
            ' can switch between them in two clicks. It changes the same Sort Order as the On-Screen Tracker card.'
            ' Off by default."]))\n')
UNFOCUS_OPEN = '            clicking:Add(self:CreateCheckbox(content, L["Click a focused quest to unfocus it"],\n'
ACCEPT_OPEN = '            clicking:Add(self:CreateCheckbox(content, L["Focus newly accepted quests"],\n'
ST_GUARD = '        if ns.Has.SuperTrack then\n' + UNFOCUS_OPEN
UNFOCUS_BOX = (UNFOCUS_OPEN +
               '                function() return DB().clickToUnfocus == true end,\n'
               '                function(v) DB().clickToUnfocus = v end,\n'
               '                L["Click the focused quest again to unfocus it. With Split quest click on, click its icon."]))\n')
ACCEPT_BOX = (ACCEPT_OPEN +
              '                function() return DB().focusAcceptedQuests ~= false end,\n'
              '                function(v) DB().focusAcceptedQuests = v end,\n'
              '                L["While nothing is focused, the game focuses each quest you accept. Turn this off to leave new quests unfocused."]))\n')
SPLIT_BOX = ('        local splitCheck = self:CreateCheckbox(content, L["Split quest click"],\n'
             '            trackerSetting("splitQuestClick"))\n')
ZONE_SYNC = ("        content._syncZoneTag = function() self:SetDependent(zoneCheck, not DB().zoneHeaders or DB().dungeonHeader == true) end\n"
             "        content._syncZoneTag()\n")

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
        (T, "                orderRows[i].tab:Hide()\n            end\n            order:Layout()\n",
            "                orderRows[i].tab:Hide()\n            end\n")]),

    # ------------------------------------------------------------------- Tracker Visibility
    ("a section show box stores the opposite of what it shows", [
        (T, "                        Sections:SetHidden(id, not v)\n                        render()\n",
            "                        Sections:SetHidden(id, v)\n                        render()\n")]),

    ("a section show box never redraws the tracker", [
        (T, "                        Sections:SetHidden(id, not v)\n                        render()\n",
            "                        Sections:SetHidden(id, not v)\n")]),

    ("a section show box reads the hidden state as shown", [
        (T, "                    function() return not Sections:IsHidden(id) end,",
            "                    function() return Sections:IsHidden(id) end,")]),

    ("a box is built for a section the TOC never loaded", [
        (T, "            if liveSections[id] then\n", "            if true then\n")]),

    # ------------------------------------------------- the boxes that were on the Options card
    # The difficulty box became one choice of Quest Title Color on Appearance. These three put
    # back what its removal took away, or break the box that took its place in the card.
    ("the difficulty box comes back to this tab", [
        (T, "        local lvl = self:CreateCheckbox(content, L[\"Show quest level prefix\"],\n",
            "        questRows:Add(self:CreateCheckbox(content, L[\"Quest Title Color By Difficulty\"],\n"
            "            rowSetting(\"colorByDifficulty\", true)))\n"
            "        local lvl = self:CreateCheckbox(content, L[\"Show quest level prefix\"],\n")]),

    # The zone label box's master is Show zone headers on Appearance, so this tab dims it on build
    # and again on every view (2.2.0).
    ("the per-view pass no longer dims the zone label box", [
        (T, "        if content._syncZoneTag then content._syncZoneTag() end\n", "")]),

    ("the zone label box is dimmed the wrong way round", [
        (T, "self:SetDependent(zoneCheck, not DB().zoneHeaders or", "self:SetDependent(zoneCheck, DB().zoneHeaders or")]),

    ("the zone label box is not dimmed until the tab is shown again", [
        (T, "        content._syncZoneTag()\n", "")]),

    ("the zone label tooltip loses its zone headers sentence", [
        (T, " While Show zone headers is on, on the Appearance tab, only quests in the Dungeons header show it.\"])", "\"])")]),

    # Since 2.3.0 a quest in the Dungeons header keeps its label under zone headers, so the box
    # stays lit while that header is on.
    ("the Dungeons header no longer lights the zone label box", [
        (T, "not DB().zoneHeaders or DB().dungeonHeader == true)", "not DB().zoneHeaders)")]),

    ("any stored Dungeons value lights the zone label box", [
        (T, "or DB().dungeonHeader == true)", "or DB().dungeonHeader)")]),

    ("the zone label box is lit only with the Dungeons header on and zone headers off", [
        (T, "not DB().zoneHeaders or DB().dungeonHeader == true)", "not DB().zoneHeaders and DB().dungeonHeader == true)")]),

    # The stub modules check self, as the real ones read it.
    ("the sort box applies the header icons with a dot, which raises in game", [
        (T, "                DB().showSortButton = v\n                ns:GetModule(\"Tracker\"):ApplyHeaderIcons()\n",
            "                DB().showSortButton = v\n                ns:GetModule(\"Tracker\").ApplyHeaderIcons()\n")]),

    ("the cogwheel box applies the header icons with a dot, which raises in game", [
        (T, "                DB().showOptionsIcon = v\n                ns:GetModule(\"Tracker\"):ApplyHeaderIcons()\n",
            "                DB().showOptionsIcon = v\n                ns:GetModule(\"Tracker\").ApplyHeaderIcons()\n")]),

    ("the tab redraws the tracker with a dot, which raises in game", [
        (T, 'local function render() ns:GetModule("Tracker"):Render() end\n',
            'local function render() ns:GetModule("Tracker").Render() end\n')]),

    ("a row setting repaints the rows with a dot, which raises in game", [
        (T, '               ns:GetModule("Row"):Invalidate()\n', '               ns:GetModule("Row").Invalidate()\n')]),

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
        (T, "            L[\"The header of the section you are scrolled into stays at the top of the quest list, so you can always see which section you are in. With zone headers on, the header of the zone you are scrolled into stays just under it. On by default.\"]))\n",
            "            L[\"The header of the section you are scrolled into stays at the top of the quest list, so you can always see which section you are in. With zone headers on, the header of the zone you are scrolled into stays just under it. On by default.\"]), { dependent = true })\n")]),

    ("the cogwheel box is stored but never applied", [
        (T, '                DB().showOptionsIcon = v\n                ns:GetModule("Tracker"):ApplyHeaderIcons()\n',
            '                DB().showOptionsIcon = v\n')]),

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

    # ------------------------------------------------------- the two focus boxes (2.2.0)
    ("the focus boxes are built on Classic too, where a click already toggles", [
        (T, "        if ns.Has.SuperTrack then\n            clicking:Add(self:CreateCheckbox(content, L[\"Click a focused",
            "        if true then\n            clicking:Add(self:CreateCheckbox(content, L[\"Click a focused")]),

    ("the focus boxes are built only on Classic", [
        (T, "        if ns.Has.SuperTrack then\n            clicking:Add(self:CreateCheckbox(content, L[\"Click a focused",
            "        if not ns.Has.SuperTrack then\n            clicking:Add(self:CreateCheckbox(content, L[\"Click a focused")]),

    ("the unfocus box reads on while unset", [
        (T, "                function() return DB().clickToUnfocus == true end,\n",
            "                function() return DB().clickToUnfocus ~= false end,\n")]),

    ("the accept box reads off while unset, the opposite of the game", [
        (T, "                function() return DB().focusAcceptedQuests ~= false end,\n",
            "                function() return DB().focusAcceptedQuests == true end,\n")]),

    ("the unfocus box writes the accept box's key", [
        (T, "                function(v) DB().clickToUnfocus = v end,\n",
            "                function(v) DB().focusAcceptedQuests = v end,\n")]),

    ("the accept box writes the unfocus box's key", [
        (T, "                function(v) DB().focusAcceptedQuests = v end,\n",
            "                function(v) DB().clickToUnfocus = v end,\n")]),

    ("the unfocus box stores the opposite of what was ticked", [
        (T, "                function(v) DB().clickToUnfocus = v end,\n",
            "                function(v) DB().clickToUnfocus = not v end,\n")]),

    ("the accept box stores nothing", [
        (T, "                function(v) DB().focusAcceptedQuests = v end,\n",
            "                function() end,\n")]),

    ("the unfocus box loses its tooltip", [
        (T, "                L[\"Click the focused quest again to unfocus it. With Split quest click on, click its icon.\"]))\n",
            "                nil))\n")]),

    ("the accept box carries the unfocus box's tooltip", [
        (T, "                L[\"While nothing is focused, the game focuses each quest you accept. Turn this off to leave new quests unfocused.\"]))\n",
            "                L[\"Click the focused quest again to unfocus it. With Split quest click on, click its icon.\"]))\n")]),

    ("the unfocus box is indented under Split quest click", [
        (T, "                L[\"Click the focused quest again to unfocus it. With Split quest click on, click its icon.\"]))\n",
            "                L[\"Click the focused quest again to unfocus it. With Split quest click on, click its icon.\"]), { dependent = true })\n")]),

    ("the unfocus box is built but never added to the card", [
        (T, "            clicking:Add(self:CreateCheckbox(content, L[\"Click a focused quest to unfocus it\"],\n",
            "            local _ = (self:CreateCheckbox(content, L[\"Click a focused quest to unfocus it\"],\n")]),

    ("the two boxes are added the other way round", [
        (T, "            clicking:Add(self:CreateCheckbox(content, L[\"Click a focused quest to unfocus it\"],\n",
            "            local unfocusBox = (self:CreateCheckbox(content, L[\"Click a focused quest to unfocus it\"],\n"),
        (T, "                L[\"While nothing is focused, the game focuses each quest you accept. Turn this off to leave new quests unfocused.\"]))\n",
            "                L[\"While nothing is focused, the game focuses each quest you accept. Turn this off to leave new quests unfocused.\"]))\n"
            "            clicking:Add(unfocusBox)\n")]),

    ("the focus boxes are added above Split quest click", [
        (T, "        local splitCheck = self:CreateCheckbox(content, L[\"Split quest click\"],\n"
            "            trackerSetting(\"splitQuestClick\"))\n"
            "        clicking:Add(splitCheck)\n",
            "        local splitCheck = self:CreateCheckbox(content, L[\"Split quest click\"],\n"
            "            trackerSetting(\"splitQuestClick\"))\n"),
        (T, "Turn this off to leave new quests unfocused.\"]))\n        end\n",
            "Turn this off to leave new quests unfocused.\"]))\n        end\n        clicking:Add(splitCheck)\n")]),

    # ------------------------------------------- found by the pre-release scan's hand-breaks
    ("the unfocus box also writes Split quest click's key", [
        (T, "                function(v) DB().clickToUnfocus = v end,\n",
            "                function(v) DB().clickToUnfocus = v; DB().splitQuestClick = v end,\n")]),

    ("the accept box also writes a second tracker key", [
        (T, "                function(v) DB().focusAcceptedQuests = v end,\n",
            "                function(v) DB().focusAcceptedQuests = v; DB().trackerAlphaFocus = v end,\n")]),

    ("the accept box also writes auto-track in the general settings", [
        (T, "                function(v) DB().focusAcceptedQuests = v end,\n",
            "                function(v) DB().focusAcceptedQuests = v;"
            " ns:GetModule(\"DB\"):General().autoTrackAccepted = v end,\n")]),

    ("the unfocus box reads ticked while Split quest click is on", [
        (T, "                function() return DB().clickToUnfocus == true end,\n",
            "                function() return DB().clickToUnfocus == true or DB().splitQuestClick == true end,\n")]),

    ("the accept box reads unticked while the unfocus option is on", [
        (T, "                function() return DB().focusAcceptedQuests ~= false end,\n",
            "                function() return DB().focusAcceptedQuests ~= false and DB().clickToUnfocus ~= true end,\n")]),

    ("the focus boxes are built on Classic, where super-track reads false", [
        (T, "        if ns.Has.SuperTrack then\n            clicking:Add(self:CreateCheckbox(content, L[\"Click a focused",
            "        if ns.Has.SuperTrack ~= nil then\n            clicking:Add(self:CreateCheckbox(content, L[\"Click a focused")]),

    ("the unfocus box is added full width", [
        (T, "                L[\"Click the focused quest again to unfocus it. With Split quest click on, click its icon.\"]))\n",
            "                L[\"Click the focused quest again to unfocus it. With Split quest click on, click its icon.\"]), { fill = true })\n")]),

    ("the accept box is added full width", [
        (T, "                L[\"While nothing is focused, the game focuses each quest you accept. Turn this off to leave new quests unfocused.\"]))\n",
            "                L[\"While nothing is focused, the game focuses each quest you accept. Turn this off to leave new quests unfocused.\"]), { fill = true })\n")]),

    # A dot call hands DB:Tracker no self, a Lua error in game that a stub ignoring self passes.
    ("the tab calls DB.Tracker with a dot", [
        (T, "local function DB() return ns:GetModule(\"DB\"):Tracker() end\n",
            "local function DB() return ns:GetModule(\"DB\").Tracker() end\n")]),

    ("the header pass calls DB.Tracker with a dot", [
        (TR, "    local cfg = DB and DB:Tracker()\n\n    if f.sortButton then",
             "    local cfg = DB and DB.Tracker()\n\n    if f.sortButton then")]),

    # ------------------------------------- found by the 2.2.0 fix pass's second scan (T1 to T10)
    # The library appends a checkbox to its parent's _controls, which only the content carries,
    # so either of these stops the whole tab building in game.
    ("the unfocus box is built on the card, not the tab's content", [
        (T, UNFOCUS_OPEN, UNFOCUS_OPEN.replace("CreateCheckbox(content,", "CreateCheckbox(clicking,"))]),

    ("the accept box is built with no parent", [
        (T, ACCEPT_OPEN, ACCEPT_OPEN.replace("CreateCheckbox(content,", "CreateCheckbox(nil,"))]),

    ("the unfocus box is dimmed while Split quest click is off", [
        (T, UNFOCUS_BOX,
         '            local unfocusBox = self:CreateCheckbox(content, L["Click a focused quest to unfocus it"],\n'
         '                function() return DB().clickToUnfocus == true end,\n'
         '                function(v) DB().clickToUnfocus = v end,\n'
         '                L["Click the focused quest again to unfocus it. With Split quest click on, click its icon."])\n'
         '            clicking:Add(unfocusBox)\n'
         '            self:SetDependent(unfocusBox, DB().splitQuestClick == true)\n')]),

    ("the accept box is dimmed while Auto track accepted quests is off", [
        (T, ACCEPT_BOX,
         '            local acceptBox = self:CreateCheckbox(content, L["Focus newly accepted quests"],\n'
         '                function() return DB().focusAcceptedQuests ~= false end,\n'
         '                function(v) DB().focusAcceptedQuests = v end,\n'
         '                L["While nothing is focused, the game focuses each quest you accept. Turn this off to leave new quests unfocused."])\n'
         '            clicking:Add(acceptBox)\n'
         '            self:SetDependent(acceptBox, (ns:GetModule("DB"):General() or {}).autoTrackAccepted ~= false)\n')]),

    ("the unfocus box's setter invalidates every row and redraws, for a key no row reads", [
        (T, "                function(v) DB().clickToUnfocus = v end,\n",
            "                function(v) DB().clickToUnfocus = v; ns:GetModule(\"Row\"):Invalidate(); render() end,\n")]),

    ("the accept box's setter invalidates every row", [
        (T, "                function(v) DB().focusAcceptedQuests = v end,\n",
            "                function(v) DB().focusAcceptedQuests = v; ns:GetModule(\"Row\"):Invalidate() end,\n")]),

    ("the Split quest click box's tooltip is overwritten with the unfocus box's", [
        (T, ST_GUARD, '        if ns.Has.SuperTrack then\n'
                      '            self:AttachTooltip(splitCheck, L["Click a focused quest to unfocus it"],\n'
                      '                L["Click the focused quest again to unfocus it. With Split quest click on, click its icon."])\n'
                      + ST_GUARD.split("\n", 1)[1])]),

    ("turning Split quest click off also turns the unfocus option off", [
        (T, SPLIT_BOX,
         '        local splitCheck = self:CreateCheckbox(content, L["Split quest click"],\n'
         '            function() return DB().splitQuestClick end,\n'
         '            function(v) DB().splitQuestClick = v; if not v then DB().clickToUnfocus = false end; render() end)\n')]),

    ("the Split quest click box reads ticked while the unfocus option is on", [
        (T, SPLIT_BOX,
         '        local splitCheck = self:CreateCheckbox(content, L["Split quest click"],\n'
         '            function() return DB().splitQuestClick or DB().clickToUnfocus end,\n'
         '            function(v) DB().splitQuestClick = v; render() end)\n')]),

    ("the zone label's dimming is set up only where super-track exists, so Classic never dims it", [
        (T, ZONE_SYNC, ""),
        (T, ST_GUARD, ST_GUARD.split("\n", 1)[0] + "\n" + ZONE_SYNC.replace("        ", "            ")
                      + ST_GUARD.split("\n", 1)[1])]),

    ("the per-view pass dims the zone label only where super-track exists", [
        (T, "        if content._syncZoneTag then content._syncZoneTag() end\n",
            "        if ns.Has.SuperTrack and content._syncZoneTag then content._syncZoneTag() end\n")]),

    ("Show quest level prefix also writes a neighbor's key", [
        (T, "            rowSetting(\"showLevelInTracker\"))\n",
            "            function() return DB().showLevelInTracker end,\n"
            "            function(v) DB().showLevelInTracker = v; DB().showQuestID = v;"
            " ns:GetModule(\"Row\"):Invalidate(); render() end)\n")]),

    ("Simplify Mode reads ticked while a neighbor is on", [
        (T, "            trackerSetting(\"simplifyMode\"))\n",
            "            function() return DB().simplifyMode or DB().showOnlyWatched end,\n"
            "            function(v) DB().simplifyMode = v; render() end)\n")]),

    # ----------------------------------------------- section tabs (2026-10-15, for bramer26)
    ("Show section tabs reads on while unset, so tabs ship on", [
        (T, "            function() return DB().showTabs == true end,\n",
            "            function() return DB().showTabs ~= false end,\n")]),

    ("Show section tabs writes the sort button's key", [
        (T, "                DB().showTabs = v\n", "                DB().showSortButton = v\n")]),

    ("Show section tabs never redraws the tracker", [
        (T, "                    DB().showTabs = v\n                    render()\n", "                    DB().showTabs = v\n")]),

    ("Show section tabs never shows the tab buttons", [
        (T, "                    DB().showTabs = v\n                    render()\n                    renderOrderRows()\n",
            "                    DB().showTabs = v\n                    render()\n")]),

    # Which clients offer tabs is UI/Tracker.lua's TabsOffered, and mutate_tabs.py breaks its own count.
    ("the box is offered whatever the tracker says", [
        (T, '        local tabsOffered = ns:GetModule("Tracker"):TabsOffered()\n', "        local tabsOffered = true\n")]),

    ("the box is never offered", [
        (T, '        local tabsOffered = ns:GetModule("Tracker"):TabsOffered()\n', "        local tabsOffered = false\n")]),

    ("the tab buttons show where no box is offered", [
        (T, "            local tabsOn = tabsOffered and DB().showTabs == true\n",
            "            local tabsOn = DB().showTabs == true\n")]),

    ("Show section tabs is labeled in English", [
        (T, '        local tabsBox = self:CreateCheckbox(content, L["Show section tabs"],\n',
            '        local tabsBox = self:CreateCheckbox(content, "Show section tabs",\n')]),

    ("a tab button cycles between two tabs only", [
        (T, "    local t = Tracker:SectionTab(id) % Tracker.MAX_TABS + 1\n",
            "    local t = Tracker:SectionTab(id) % 2 + 1\n")]),

    ("a section that makes no tab keeps its button lit", [
        (T, "                self:SetDependent(r.tab, Tracker:DrawsOnTab(id))\n", "")]),

    ("a row's dim reads the section its button showed before a reorder", [
        (T, ("                r.tab.sectionID = id\n"
             "                r.tab:SetText(Tracker:SectionTab(id))\n"
             "                r.tab:SetShown(tabsOn)\n"
             "                self:SetDependent(r.tab, Tracker:DrawsOnTab(id))\n"),
            ("                self:SetDependent(r.tab, Tracker:DrawsOnTab(r.tab.sectionID or id))\n"
             "                r.tab.sectionID = id\n"
             "                r.tab:SetText(Tracker:SectionTab(id))\n"
             "                r.tab:SetShown(tabsOn)\n"))]),

    ("World Quests' tab button sits a written-in 10 px from the row's edge", [
        (T, '        wqTab:SetPoint("RIGHT", wqRow, "RIGHT", -self:Spacing("rowPadding"), 0)\n',
            '        wqTab:SetPoint("RIGHT", wqRow, "RIGHT", -10, 0)\n')]),

    ("World Quests' button stays lit while World Quests are hidden", [
        (T, '            self:SetDependent(wqTab, Tracker:DrawsOnTab("worldquests"))\n', "")]),

    ("a visit to the tab never re-reads the tab buttons", [
        (T, "        if content._renderOrderRows then content._renderOrderRows() end\n    end,\n})",
            "    end,\n})")]),

    ("hiding a section leaves its tab button lit until the next visit", [
        (T, "                        render()\n                        if content._renderOrderRows then content._renderOrderRows() end\n",
            "                        render()\n")]),

    ("World Quests' tab button reads the card's gap, not a row's padding", [
        (T, '        wqTab:SetPoint("RIGHT", wqRow, "RIGHT", -self:Spacing("rowPadding"), 0)\n',
            '        wqTab:SetPoint("RIGHT", wqRow, "RIGHT", -self:Spacing("groupGap"), 0)\n')]),

    ("a row's tab button sits over its up chevron", [
        (T, '                    r.tab:SetPoint("RIGHT", r.up, "LEFT", -ARROW_GAP, 0)\n',
            '                    r.tab:SetPoint("RIGHT", r.up, "LEFT", ARROW_GAP, 0)\n')]),

    ("tab 1 is stored as a 1, not as nothing", [
        (T, "    cfg.sectionTab[id] = (t ~= 1) and t or nil\n", "    cfg.sectionTab[id] = t\n")]),

    ("a tab button moves nothing", [
        (T, "        if not btn.sectionID then return end\n        nextTab(btn.sectionID)\n",
            "        if not btn.sectionID then return end\n")]),

    ("a tab move never redraws or relabels", [
        (T, "        nextTab(btn.sectionID)\n        onMoved()\n", "        nextTab(btn.sectionID)\n")]),

    ("a tab button is taller than the arrows", [
        (T, "    b:SetHeight(ARROW_SIZE)\n", "")]),

    ("a tab move redraws without relabeling the rows", [
        (T, "        local function tabMoved()\n            render()\n            renderOrderRows()\n",
            "        local function tabMoved()\n            render()\n")]),

    ("World Quests' tab button moves Quests", [
        (T, '        wqTab.sectionID = "worldquests"\n', '        wqTab.sectionID = "quests"\n')]),

    ("World Quests' tab button shows on a client with no world quests", [
        (T, "            wqTab:SetShown(tabsOn and hasWorldQuests)\n", "            wqTab:SetShown(tabsOn)\n")]),

    ("World Quests' tab button always reads 1", [
        (T, '            wqTab:SetText(Tracker:SectionTab("worldquests"))\n', '            wqTab:SetText(1)\n')]),

    ("a row's tab button carries no section", [
        (T, "                r.tab.sectionID = id\n", "")]),

    ("a row's tab button always reads 1", [
        (T, "                r.tab:SetText(Tracker:SectionTab(id))\n", "                r.tab:SetText(1)\n")]),

    ("a row's tab button shows with tabs off", [
        (T, "                r.tab:SetShown(tabsOn)\n", "                r.tab:SetShown(true)\n")]),

    ("tabs read on for any truthy value on the card", [
        (T, "            local tabsOn = tabsOffered and DB().showTabs == true\n",
            "            local tabsOn = tabsOffered and DB().showTabs and true or false\n")]),

    # ------------------------------------- the filter button box (2026-10-15, for Tyrial and bramer26)
    ("the filter button box reads on while unset, so the button ships on", [
        (T, "            function() return DB().showFilterButton == true end,\n",
            "            function() return DB().showFilterButton ~= false end,\n")]),

    ("the filter button box reads the sort button's key", [
        (T, "            function() return DB().showFilterButton == true end,\n",
            "            function() return DB().showSortButton == true end,\n")]),

    ("the filter button box writes the sort button's key", [
        (T, "                DB().showFilterButton = v\n", "                DB().showSortButton = v\n")]),

    ("the filter button box never asks the header pass to show or hide the button", [
        (T, "                DB().showFilterButton = v\n                ns:GetModule(\"Tracker\"):ApplyHeaderIcons()\n",
            "                DB().showFilterButton = v\n")]),

    ("the filter button box asks the header pass before it stores", [
        (T, "                DB().showFilterButton = v\n                ns:GetModule(\"Tracker\"):ApplyHeaderIcons()\n",
            "                ns:GetModule(\"Tracker\"):ApplyHeaderIcons()\n                DB().showFilterButton = v\n")]),

    ("the filter button box redraws the whole tracker", [
        (T, "                DB().showFilterButton = v\n                ns:GetModule(\"Tracker\"):ApplyHeaderIcons()\n",
            "                DB().showFilterButton = v\n                ns:GetModule(\"Tracker\"):ApplyHeaderIcons()\n"
            "                ns:GetModule(\"Tracker\"):Render()\n")]),

    ("the filter button box is labeled in English", [
        (T, '        headers:Add(self:CreateCheckbox(content, L["Show the filter button on the tracker"],\n',
            '        headers:Add(self:CreateCheckbox(content, "Show the filter button on the tracker",\n')]),

    ("the filter button box ships on in Core/DB.lua", [
        ("Core/DB.lua", "            showFilterButton     = false,\n", "            showFilterButton     = true,\n")]),

    # ----------------------------------------------- the sort button box (2026-10-10, for Andreon)
    ("the sort button box reads on while unset, so the button ships on", [
        (T, "            function() return DB().showSortButton == true end,\n",
            "            function() return DB().showSortButton ~= false end,\n")]),

    ("the sort button box reads a neighbor's key", [
        (T, "            function() return DB().showSortButton == true end,\n",
            "            function() return DB().showOptionsIcon == true end,\n")]),

    ("the sort button box writes the cogwheel's key", [
        (T, "                DB().showSortButton = v\n", "                DB().showOptionsIcon = v\n")]),

    ("the sort button box never asks the header pass to show or hide the button", [
        (T, "                DB().showSortButton = v\n                ns:GetModule(\"Tracker\"):ApplyHeaderIcons()\n",
            "                DB().showSortButton = v\n")]),

    ("the sort button box asks the header pass before it stores", [
        (T, "                DB().showSortButton = v\n                ns:GetModule(\"Tracker\"):ApplyHeaderIcons()\n",
            "                ns:GetModule(\"Tracker\"):ApplyHeaderIcons()\n                DB().showSortButton = v\n")]),

    ("the sort button box also redraws the whole list", [
        (T, "                DB().showSortButton = v\n                ns:GetModule(\"Tracker\"):ApplyHeaderIcons()\n",
            "                DB().showSortButton = v\n                ns:GetModule(\"Tracker\"):ApplyHeaderIcons()\n"
            "                render()\n")]),

    ("the sort button box is built but never added to its card", [
        (T, '        headers:Add(self:CreateCheckbox(content, L["Show the sort button on the tracker"],\n',
            '        (self:CreateCheckbox(content, L["Show the sort button on the tracker"],\n')]),

    ("the sort button box sits above the cogwheel's", [
        (T, COG_BOX + "\n" + SORT_BOX, SORT_BOX + "\n" + COG_BOX)]),

    ("the sort button box loses its tooltip", [
        (T, 'the On-Screen Tracker card. Off by default."]))\n', 'the On-Screen Tracker card. Off by default."] and nil))\n')]),

    ("the Tracker tab no longer hands its list to the sort button", [
        (T, "Options.SORT_OPTIONS = SORT_OPTIONS\n", "")]),

    ("the sort button gets a copy of the list, which drifts from the dropdown's", [
        (T, "Options.SORT_OPTIONS = SORT_OPTIONS\n", "Options.SORT_OPTIONS = { unpack(SORT_OPTIONS) }\n")]),

    ("a view no longer follows an order picked on the tracker", [
        (T, "        if content._syncManualHint then content._syncManualHint() end\n", "")]),

    ("the Manual hint's per-view pass is never set up", [
        (T, "        content._syncManualHint = function() syncManualHint(DB().sortMode) end\n", "")]),

    ("the per-view pass reads the order the tab was built with", [
        (T, "        content._syncManualHint = function() syncManualHint(DB().sortMode) end\n",
            "        local builtOrder = DB().sortMode\n"
            "        content._syncManualHint = function() syncManualHint(builtOrder) end\n")]),

    ("every view of the tab redraws the tracker", [
        (T, "        content._syncManualHint = function() syncManualHint(DB().sortMode) end\n",
            "        content._syncManualHint = function() syncManualHint(DB().sortMode); render() end\n")]),

    ("Keep Dungeons at the bottom lights the zone label box", [
        (T, "or DB().dungeonHeader == true) end\n", "or DB().dungeonHeader == true or DB().dungeonHeaderLast == true) end\n")]),

    ("the box lights for the Dungeons header only under Current zone first", [
        (T, "or DB().dungeonHeader == true) end\n",
            "or DB().dungeonHeader == true and DB().zoneHeaderOrder ~= \"alpha\") end\n")]),

    # Read beside every switch the defaults ship, the box's own included, after the third scan.
    ("the zone label box dims while it is unticked under both headers", [
        (T, "or DB().dungeonHeader == true) end\n", "or DB().dungeonHeader == true and DB().showZoneTag ~= false) end\n")]),

    ("the zone label box lights while zone header dividers are on", [
        (T, "or DB().dungeonHeader == true) end\n", "or DB().dungeonHeader == true or DB().zoneHeaderDivider == true) end\n")]),

    # Another addon's header icons, each built from the spec it registered.
    ("another addon's header icon loses its tooltip", [
        (TR, "b = makeHeaderIcon(f, spec.texture, spec.tooltip, function() spec.onClick() end)",
             "b = makeHeaderIcon(f, spec.texture, nil, function() spec.onClick() end)")]),

    ("another addon's header icon gets another icon's texture", [
        (TR, "b = makeHeaderIcon(f, spec.texture, spec.tooltip, function() spec.onClick() end)",
             "b = makeHeaderIcon(f, specs[1].texture, spec.tooltip, function() spec.onClick() end)")]),

    ("another addon's header icon never runs its click", [
        (TR, "b = makeHeaderIcon(f, spec.texture, spec.tooltip, function() spec.onClick() end)",
             "b = makeHeaderIcon(f, spec.texture, spec.tooltip, function() end)")]),

    ("with two addons' icons, clicking either runs the last one's handler", [
        (TR, "b = makeHeaderIcon(f, spec.texture, spec.tooltip, function() spec.onClick() end)",
             "b = makeHeaderIcon(f, spec.texture, spec.tooltip, function() specs[#specs].onClick() end)")]),

    ("an id registered again with a new texture or handler keeps its old button", [
        (TR, "        if b and b._apiSpec ~= spec then\n", "        if b and b._apiSpec.id ~= spec.id then\n")]),

    ("another addon's icon ignores its show and hide key", [
        (TR, "        b._dbKey = spec.dbKey\n", "        b._dbKey = nil\n")]),

    # The final check's sort-order neighbor.
    ("the zone label box dims under Sort by level", [
        (T, "self:SetDependent(zoneCheck, not DB().zoneHeaders or DB().dungeonHeader == true) end\n",
            "self:SetDependent(zoneCheck, (not DB().zoneHeaders or DB().dungeonHeader == true)"
            " and DB().sortMode ~= \"level\") end\n")]),

    # The Mythic+ timer box (2026-10-11).
    ("the Mythic+ timer box is built on every client", [
        (T, '        if ns.Has.ChallengeTimer and ns:GetModule("Registry"):Get("scenarios") then\n            local mplusCheck', "        do\n            local mplusCheck")]),
    ("the Mythic+ timer box is built only where there is no key", [
        (T, '        if ns.Has.ChallengeTimer and ns:GetModule("Registry"):Get("scenarios") then\n            local mplusCheck',
            '        if not (ns.Has.ChallengeTimer and ns:GetModule("Registry"):Get("scenarios")) then\n            local mplusCheck')]),
    ("the Mythic+ timer box reads unset as off", [
        (T, '                rowSetting("showMythicPlusTimer", true))\n', '                rowSetting("showMythicPlusTimer"))\n')]),
    ("the Mythic+ timer box writes the widgets key", [
        (T, '                rowSetting("showMythicPlusTimer", true))\n', '                rowSetting("showTrackerWidgets", true))\n')]),
    ("the Mythic+ timer box only redraws, leaving the rows' gate shut", [
        (T, '                rowSetting("showMythicPlusTimer", true))\n',
            '                function() return DB().showMythicPlusTimer ~= false end,\n'
            '                function(v) DB().showMythicPlusTimer = v; render() end)\n')]),
    ("the Mythic+ timer box is never added to the card", [
        (T, "            scenarios:Add(mplusCheck)\n", "")]),
    ("the Mythic+ timer box goes on the Quest Row Details card", [
        (T, "            scenarios:Add(mplusCheck)\n", "            questRows:Add(mplusCheck)\n")]),
    ("the Mythic+ timer box borrows the widgets box's tooltip", [
        (T, '                L["During a Mythic+ run, draws the keystone level',
            '                L["Draws the extra bars and status lines the default tracker shows during world events, delves and scenarios, such as an event\'s progress bar or a delve\'s tier. This tracker replaces the default one, so without this those are not shown anywhere."] or L["During a Mythic+ run, draws the keystone level')]),
    ("the Mythic+ timer box has no tooltip title", [
        (T, '            self:AttachTooltip(mplusCheck, L["Show the Mythic+ timer"],\n', "            self:AttachTooltip(mplusCheck, nil,\n")]),
    ("the Mythic+ timer box is indented", [
        (T, "            scenarios:Add(mplusCheck)\n", "            scenarios:Add(mplusCheck, { dependent = true })\n")]),
    ("the Mythic+ timer box is added full width", [
        (T, "            scenarios:Add(mplusCheck)\n", "            scenarios:Add(mplusCheck, { fill = true })\n")]),
    ("the Mythic+ timer box is built with no scenario provider", [
        (T, '        if ns.Has.ChallengeTimer and ns:GetModule("Registry"):Get("scenarios") then\n',
            '        if ns.Has.ChallengeTimer then\n')]),
    ("the Mythic+ timer box asks the Registry for a provider that does not exist", [
        (T, '        if ns.Has.ChallengeTimer and ns:GetModule("Registry"):Get("scenarios") then\n',
            '        if ns.Has.ChallengeTimer and ns:GetModule("Registry"):Get("scenario") then\n')]),
    ("the Mythic+ timer box asks the Registry with a dot call", [
        (T, '        if ns.Has.ChallengeTimer and ns:GetModule("Registry"):Get("scenarios") then\n',
            '        if ns.Has.ChallengeTimer and ns:GetModule("Registry").Get("scenarios") then\n')]),
    ("the Mythic+ timer ships off while its box reads on", [
        ("Core/DB.lua", "            showMythicPlusTimer  = true,\n", "            showMythicPlusTimer  = false,\n")]),

    # Scan 1 (2026-10-16): the tab buttons' anchors, tooltip and section after a move, and the box's
    # store before its redraw.
    ("a row's tab button keeps the section it was built for", [
        (T, "                r.tab.sectionID = id\n                r.tab:SetText(Tracker:SectionTab(id))\n",
            "                r.tab.sectionID = r.tab.sectionID or id\n                r.tab:SetText(Tracker:SectionTab(id))\n")]),
    ("a row's tab button sits on its up chevron", [
        (T, '                    r.tab:SetPoint("RIGHT", r.up, "LEFT", -ARROW_GAP, 0)\n',
            '                    r.tab:SetPoint("RIGHT", r.down, "LEFT", -ARROW_GAP, 0)\n')]),
    ("World Quests' tab button sits over its row's label", [
        (T, '        wqTab:SetPoint("RIGHT", wqRow, "RIGHT", -self:Spacing("rowPadding"), 0)\n',
            '        wqTab:SetPoint("LEFT", wqRow, "LEFT", self:Spacing("rowPadding"), 0)\n')]),
    ("the tab button's tooltip title is drawn invisible", [
        (T, '        tip:SetText(self.sectionID and sectionLabel(self.sectionID) or "", 1, 1, 1, 1, true)\n',
            '        tip:SetText(self.sectionID and sectionLabel(self.sectionID) or "", 1, 1, 1, 0, true)\n')]),
    ("the tab button's tooltip is never shown", [
        (T, '        tip:AddLine(L["Which tab this section sits on. Click to move it to the next tab."], 0.82, 0.82, 0.82, true)\n        tip:Show()\n',
            '        tip:AddLine(L["Which tab this section sits on. Click to move it to the next tab."], 0.82, 0.82, 0.82, true)\n')]),
    ("the tab button's tooltip stays up on leaving", [
        (T, '        tip:Show()\n    end)\n    b:HookScript("OnLeave", function() ns.Util.Tooltip():Hide() end)\n    return b\nend\n\nOptions:RegisterTab',
            '        tip:Show()\n    end)\n    return b\nend\n\nOptions:RegisterTab')]),
    ("Show section tabs redraws before storing", [
        (T, "                    DB().showTabs = v\n                    render()\n                    renderOrderRows()\n",
            "                    render()\n                    DB().showTabs = v\n                    renderOrderRows()\n")]),
    # The author's split of the Options card (2026-10-16): five cards in its place, in order, each
    # holding its own rows, built on the tab's content and hung one gap under the card before it.
    ("the Options card comes back in place of Quest Row Details", [
        (T, '        local questRows = self:CreateGroup(content, L["Quest Row Details"])\n',
            '        local questRows = self:CreateGroup(content, L["Options"])\n')]),
    ("Headers and Buttons and Clicking and Focus swap titles", [
        (T, '        local headers = self:CreateGroup(content, L["Headers and Buttons"])\n',
            '        local headers = self:CreateGroup(content, L["Clicking and Focus"])\n'),
        (T, '        local clicking = self:CreateGroup(content, L["Clicking and Focus"])\n',
            '        local clicking = self:CreateGroup(content, L["Headers and Buttons"])\n')]),
    ("Quest Row Details hangs under Tracker Visibility, over Section Order", [
        (T, '        questRows:SetPoint("TOPLEFT", order, "BOTTOMLEFT", 0, -gap)\n',
            '        questRows:SetPoint("TOPLEFT", visibility, "BOTTOMLEFT", 0, -gap)\n')]),
    ("Headers and Buttons keeps only its left edge on the card above", [
        (T, '        headers:SetPoint("TOPRIGHT", questRows, "BOTTOMRIGHT", 0, -gap)\n', '')]),
    ("Clicking and Focus hangs under Quest Row Details, over Headers and Buttons", [
        (T, '        clicking:SetPoint("TOPLEFT", headers, "BOTTOMLEFT", 0, -gap)\n'
            '        clicking:SetPoint("TOPRIGHT", headers, "BOTTOMRIGHT", 0, -gap)\n',
            '        clicking:SetPoint("TOPLEFT", questRows, "BOTTOMLEFT", 0, -gap)\n'
            '        clicking:SetPoint("TOPRIGHT", questRows, "BOTTOMRIGHT", 0, -gap)\n')]),
    ("Scenarios and Popups sits flush against the card above, with no gap", [
        (T, '        scenarios:SetPoint("TOPLEFT", clicking, "BOTTOMLEFT", 0, -gap)\n'
            '        scenarios:SetPoint("TOPRIGHT", clicking, "BOTTOMRIGHT", 0, -gap)\n',
            '        scenarios:SetPoint("TOPLEFT", clicking, "BOTTOMLEFT", 0, 0)\n'
            '        scenarios:SetPoint("TOPRIGHT", clicking, "BOTTOMRIGHT", 0, 0)\n')]),
    ("Sounds overlaps the card above by a gap on its right edge", [
        (T, '        sounds:SetPoint("TOPRIGHT", scenarios, "BOTTOMRIGHT", 0, -gap)\n',
            '        sounds:SetPoint("TOPRIGHT", scenarios, "BOTTOMRIGHT", 0, gap)\n')]),
    ("the Sounds card is built inside Scenarios and Popups, not on the tab's content", [
        (T, '        local sounds = self:CreateGroup(content, L["Sounds"])\n',
            '        local sounds = self:CreateGroup(scenarios, L["Sounds"])\n')]),
    ("the NEW tag box lands on the Section Order card", [
        (T, '        questRows:Add(newTagCheck)\n', '        order:Add(newTagCheck)\n')]),
    ("the quest ID box is added to Scenarios and Popups as well", [
        (T, '        scenarios:Add(widgetCheck)\n', '        scenarios:Add(widgetCheck)\n        scenarios:Add(qidCheck)\n')]),
    ("the header count box lands on Quest Row Details", [
        (T, '        headers:Add(self:CreateCheckbox(content,\n            L["Show the visible / total count on section headers"],\n',
            '        questRows:Add(self:CreateCheckbox(content,\n            L["Show the visible / total count on section headers"],\n')]),
    ("the filter button box lands on Quest Row Details", [
        (T, '        headers:Add(self:CreateCheckbox(content, L["Show the filter button on the tracker"],\n',
            '        questRows:Add(self:CreateCheckbox(content, L["Show the filter button on the tracker"],\n')]),
    ("Split quest click lands on Headers and Buttons", [
        (T, '        clicking:Add(splitCheck)\n', '        headers:Add(splitCheck)\n')]),
    ("Split quest click is added only where super-track exists, so Classic's card is empty", [
        (T, '        clicking:Add(splitCheck)\n', '        if ns.Has.SuperTrack then clicking:Add(splitCheck) end\n')]),
    ("Show Quest Discovered popups lands on Clicking and Focus", [
        (T, '        scenarios:Add(self:CreateCheckbox(content, L["Show Quest Discovered popups"],\n',
            '        clicking:Add(self:CreateCheckbox(content, L["Show Quest Discovered popups"],\n')]),
    ("Quest Sound lands on Scenarios and Popups", [
        (T, '        sounds:Add(self:CreateCheckbox(content, L["Quest Sound"],\n',
            '        scenarios:Add(self:CreateCheckbox(content, L["Quest Sound"],\n')]),

    # ------------------------------------------------------------------------ the delve boxes
    ("the widgets box stops relighting the delve boxes", [
        (T, "                widgetSet(v)\n                syncDelveRows()\n", "                widgetSet(v)\n")]),
    ("the delve boxes are not dimmed to match at build", [
        (T, DELVE_SYNC, "            content._syncDelveRows = syncDelveRows\n")]),
    ("refresh is never handed the delve boxes", [
        (T, DELVE_SYNC, "            syncDelveRows()\n")]),
    ("refresh skips the delve boxes", [
        (T, "        if content._syncDelveRows then content._syncDelveRows() end\n", "")]),
    ("the delve boxes are lit while the widgets box is off", [
        (T, "            for _, r in ipairs(delveRows) do self:SetDependent(r, widgetGet()) end\n",
            "            for _, r in ipairs(delveRows) do self:SetDependent(r, not widgetGet()) end\n")]),
    ("the delve boxes are built on Forever", [
        (T, DELVE_GATE, "        if ns.Has.DelveHeader and ns:GetModule(\"Registry\"):Get(\"scenarios\") then\n")]),
    ("the delve boxes are built with no delve widget", [
        (T, DELVE_GATE, "        if ns:GetModule(\"Registry\"):Get(\"scenarios\") and not ns.IsForever() then\n")]),
    ("the delve boxes are built on Era and TBC, which carry the delve call but no scenario provider", [
        (T, DELVE_GATE, "        if ns.Has.DelveHeader and not ns.IsForever() then\n")]),
    ("a delve box reads unset as off", [
        (T, "                    function() return DB()[key] ~= false end,\n",
            "                    function() return DB()[key] == true end,\n")]),
    ("a delve box writes nothing", [
        (T, DELVE_SET, DELVE_SET.replace("                        DB()[key] = v\n", ""))]),
    ("a delve box keeps the widget snapshot", [
        (T, DELVE_SET, DELVE_SET.replace("                        ns:GetModule(\"Widgets\"):Invalidate()\n", ""))]),
    ("a delve box does not redraw", [
        (T, DELVE_SET, DELVE_SET.replace("                        render()\n", ""))]),
    ("a delve box redraws before the snapshot drops", [
        (T, DELVE_SET, "                        DB()[key] = v\n"
                       "                        render()\n"
                       "                        ns:GetModule(\"Widgets\"):Invalidate()\n")]),
    ("a delve box invalidates the rows instead", [
        (T, DELVE_SET, DELVE_SET.replace("ns:GetModule(\"Widgets\")", "ns:GetModule(\"Row\")"))]),
    ("the delve boxes are not indented", [
        (T, "            for _, r in ipairs(delveRows) do scenarios:Add(r, { dependent = true }) end\n",
            "            for _, r in ipairs(delveRows) do scenarios:Add(r) end\n")]),
    ("the lives box writes the nemesis key", [
        (T, '            delveRows[1] = delveBox(L["Show delve lives"], "showDelveLives",\n',
            '            delveRows[1] = delveBox(L["Show delve lives"], "showNemesisGroups",\n')]),
    ("the nemesis box writes the lives key", [
        (T, '            delveRows[2] = delveBox(L["Show nemesis groups"], "showNemesisGroups",\n',
            '            delveRows[2] = delveBox(L["Show nemesis groups"], "showDelveLives",\n')]),
    ("Core/DB.lua ships the lives off", [
        (DBF, "            showDelveLives       = true,\n", "            showDelveLives       = false,\n")]),
    ("Core/DB.lua ships the nemesis groups off", [
        (DBF, "            showNemesisGroups    = true,\n", "            showNemesisGroups    = false,\n")]),
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
