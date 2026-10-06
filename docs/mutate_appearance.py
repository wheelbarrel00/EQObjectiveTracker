"""Prove docs/test_appearance.lua actually discriminates, by breaking production on purpose one
change at a time and checking the harness notices.

    python docs/mutate_appearance.py        (run from the repo root)

Why this exists: the Appearance tab dims about half its controls on a master switch, two
conditions deep in places, and every way that can go wrong is silent. A control dimmed on the
wrong key reads as broken while it works, or lit while it does nothing. A master whose setter
forgets the sweep leaves the tab showing the state before the click until the next view. And the
sweep itself once sat five upvalues under Lua 5.1's ceiling of 60, past which the whole file
stops compiling with luacheck still clean. The cards the tab moved into in EverythingUI phase 1
step 4 add their own silent failures: a row in the wrong card or order, an indent lost, a
checkbox's color left unplaced at the top of the tab.

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
HARNESS = "docs/test_appearance.lua"

A = "Options/TabAppearance.lua"
U = "Core/Util.lua"

MUTANTS = [
    # --------------------------------------------------------------------------- the zone headers card
    ("the zone header size slider writes the indent", [
        (A, '            function(v) relayout("zoneHeaderSizeDelta", v) end,',
            '            function(v) relayout("zoneHeaderIndent", v) end,')]),
    ("the zone header size slider runs past 12", [
        (A, 'L["Zone Header Size Offset"], -8, 12, 0.5,', 'L["Zone Header Size Offset"], -8, 24, 0.5,')]),
    ("the zone header size slider moves in whole steps", [
        (A, 'L["Zone Header Size Offset"], -8, 12, 0.5,', 'L["Zone Header Size Offset"], -8, 12, 1,')]),
    ("the indent slider moves in half pixels", [
        (A, 'L["Quest Indent"], 0, 30, 1,', 'L["Quest Indent"], 0, 30, 0.5,')]),
    ("the indent reads 0 while unset", [
        (A, "            function() return DB().zoneHeaderIndent or 8 end,", "            function() return DB().zoneHeaderIndent or 0 end,")]),
    ("the zone class color switch does not re-run the sweep", [
        (A, '            function(v) relayout("zoneHeaderColorUseClass", v); syncDependents() end,',
            '            function(v) relayout("zoneHeaderColorUseClass", v) end,')]),
    ("the zone divider switch does not re-run the sweep", [
        (A, '            function(v) relayout("zoneHeaderDivider", v); syncDependents() end,',
            '            function(v) relayout("zoneHeaderDivider", v) end,')]),
    ("the zone bar color writes the section headers' bar color", [
        (A, '            function(v) relayout("zoneHeaderBarColor", v) end,', '            function(v) relayout("headerBarColor", v) end,')]),
    ("the zone divider color takes no alpha", [
        (A, 'L["Color of the thin line under each zone header."], true)', 'L["Color of the thin line under each zone header."])')]),
    ("the zone header color is not indented under the class color switch", [
        (A, "        zoneHeads:Add(w.zoneColor, DEPENDENT)\n", "        zoneHeads:Add(w.zoneColor)\n")]),
    ("the zone header color stays lit under the class color", [
        (A, "            dim(w.zoneColor,      zh and not cfg.zoneHeaderColorUseClass)\n", "            dim(w.zoneColor,      zh)\n")]),
    ("the zone bar color stays lit with its bar off", [
        (A, "            dim(w.zoneBarPicker,  zh and cfg.zoneHeaderBar)\n", "            dim(w.zoneBarPicker,  zh)\n")]),
    ("the zone divider color stays lit with its divider off", [
        (A, "            dim(w.zoneLinePicker, zh and cfg.zoneHeaderDivider)\n", "            dim(w.zoneLinePicker, zh)\n")]),
    ("the indent stays lit with zone headers off", [
        (A, "            dim(w.zoneIndent,     zh)\n", "")]),

    # --------------------------------------------------------------------------- the cards
    ("a card is built but never anchored, so it draws at the top of the tab", [
        (A, '        local tracker = stack(self:CreateGroup(content, L["Tracker"]))',
            '        local tracker = self:CreateGroup(content, L["Tracker"])')]),

    ("every card hangs from the top of the tab instead of the card before it", [
        (A, "            above = card\n", "")]),

    ("cards touch, with no group gap between them", [
        (A, '                card:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -gap)',
            '                card:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, 0)')]),

    ("a card is titled with a key that is not its heading", [
        (A, 'stack(self:CreateGroup(content, L["Scroll Bar"]))',
            'stack(self:CreateGroup(content, L["Scrollbar"]))')]),

    ("the first card goes back to the old heading, the tab's own name", [
        (A, 'stack(self:CreateGroup(content, L["Text"]))',
            'stack(self:CreateGroup(content, L["Appearance"]))')]),

    ("the quest colors are built after the tracker card instead of before it", [
        (A, '        local questColors = stack(self:CreateGroup(content, L["Quest Colors"]))\n',
            '        local questColors = self:CreateGroup(content, L["Quest Colors"])\n'),
        (A, '        local tracker = stack(self:CreateGroup(content, L["Tracker"]))\n',
            '        local tracker = stack(self:CreateGroup(content, L["Tracker"]))\n        stack(questColors)\n')]),

    ("the bonus HUD card is built on Classic, where the capability reads true with nothing behind it", [
        (A, '        if ns.Has.ScenarioBonus and ns:GetModule("Registry"):Get("scenarios") then',
            '        if ns.Has.ScenarioBonus then')]),

    # ---------------------------------------------------------------------- rows and order
    ("Bar Height goes back under Soft edges, between the switch and its slider", [
        (A, "        headers:Add(w.hbHeightSlider)\n", ""),
        (A, "        headers:Add(w.hbSoftCheck)\n",
            "        headers:Add(w.hbSoftCheck)\n        headers:Add(w.hbHeightSlider)\n")]),

    ("the title color goes back below the boxes rather than under the switch that dims it", [
        (A, "        questColors:Add(w.titlePicker, DEPENDENT)\n", ""),
        (A, "        questColors:Add(w.recolorCheck)\n",
            "        questColors:Add(w.recolorCheck)\n        questColors:Add(w.titlePicker, DEPENDENT)\n")]),

    ("Header Color goes back below Bar Color, out of the floating block", [
        (A, "        zone:Add(w.zbHeaderPicker, DEPENDENT)\n", ""),
        (A, "        zone:Add(w.zbBarColorPicker)\n",
            "        zone:Add(w.zbBarColorPicker)\n        zone:Add(w.zbHeaderPicker, DEPENDENT)\n")]),

    ("a control is never added to its card", [
        (A, "        scenario:Add(scCritSizeSlider)\n", "")]),

    ("Shadow Size is not indented under Text Shadow", [
        (A, "        look:Add(w.shadowSizeSlider, DEPENDENT)", "        look:Add(w.shadowSizeSlider)")]),

    ("Thumb Width is not indented under Solid color thumb", [
        (A, "        scrollBar:Add(w.thumbWidthSlider, DEPENDENT)", "        scrollBar:Add(w.thumbWidthSlider)")]),

    ("Border Thickness is not indented under Border", [
        (A, "        tracker:Add(w.borderThickSlider, DEPENDENT)", "        tracker:Add(w.borderThickSlider)")]),

    ("Edge Softness is not indented under Soft edges", [
        (A, "        headers:Add(w.hbSoftSlider, DEPENDENT)", "        headers:Add(w.hbSoftSlider)")]),

    ("Section Header Color is not indented under its class box", [
        (A, "        headers:Add(w.headerPicker, DEPENDENT)", "        headers:Add(w.headerPicker)")]),

    ("Raid is not indented under Tint cards by quest type", [
        (A, "        questRows:Add(w.raidTint, DEPENDENT)", "        questRows:Add(w.raidTint)")]),

    ("the zone bar Background box is not indented under Float", [
        (A, "        local zbBgRow = zone:Add(w.zbBgCheck, DEPENDENT)", "        local zbBgRow = zone:Add(w.zbBgCheck)")]),

    ("the zone bar Font is not indented under Float", [
        (A, "        zone:Add(w.zbFontDD, DEPENDENT)", "        zone:Add(w.zbFontDD)")]),

    ("a row under a whole-card switch is indented, which the author ruled out", [
        (A, "        questRows:Add(w.cardColorPicker)\n", "        questRows:Add(w.cardColorPicker, DEPENDENT)\n")]),

    ("Scroll Bar Background is indented under Hide scroll bar, which heads the whole card", [
        (A, "        local sbRow = scrollBar:Add(w.sbCheck)", "        local sbRow = scrollBar:Add(w.sbCheck, DEPENDENT)")]),

    ("the indent table indents nothing", [
        (A, "local DEPENDENT = { dependent = true }", "local DEPENDENT = {}")]),

    # ----------------------------------------------------------------- end-of-row pickers
    ("Shadow Color is built but never placed, so it draws at the top of the tab", [
        (A, "        satellite(self, shadowRow, w.shadowPicker)\n", "")]),

    ("Border Color hangs on the Background row", [
        (A, "        satellite(self, borderRow, w.borderPicker)", "        satellite(self, bgRow, w.borderPicker)")]),

    ("an end-of-row color ignores the row padding", [
        (A, '    picker:SetPoint("RIGHT", row, "RIGHT", -ui:Spacing("rowPadding"), 0)',
            '    picker:SetPoint("RIGHT", row, "RIGHT", 0, 0)')]),

    ("Bar Color becomes a row of its own instead of the header bar switch's color", [
        (A, "        satellite(self, hbRow, w.hbPicker)", "        headers:Add(w.hbPicker)")]),

    # ----------------------------------------------------------------------- segmented
    ("Banner Alignment goes back to a dropdown, losing its tooltip on the way", [
        (A, '        scenario:Add(self:CreateRadioGroup(content, L["Banner Alignment"],',
            '        scenario:Add(self:CreateDropdown(content, L["Banner Alignment"],')]),

    ("Bar Style goes back to a dropdown", [
        (A, "        w.hbStyle = self:CreateRadioGroup(", "        w.hbStyle = self:CreateDropdown(")]),

    ("Bar Style's tooltip loses its title", [
        (A, '            nil, nil,\n            L["Bar Style"],', '            nil, nil,\n            nil,')]),

    ("the alignment choices are offered out of order", [
        (A, '    { value = "LEFT",   label = L["Left"] },\n    { value = "CENTER", label = L["Center"] },',
            '    { value = "CENTER", label = L["Center"] },\n    { value = "LEFT",   label = L["Left"] },')]),

    ("a translated alignment word left in a profile no longer reads as Center", [
        (A, '    return (v == "LEFT" or v == "RIGHT") and v or "CENTER"', '    return v or "CENTER"')]),

    ("an unknown bar style no longer reads as style 1", [
        (A, "function() return (DB().headerBarStyle or 1) == 2 and 2 or 1 end,",
            "function() return DB().headerBarStyle or 1 end,")]),

    # ------------------------------------------------------------------------- the sweep
    ("Shadow Color dims on the scenario's shadow instead of the tracker's", [
        (A, "            dim(w.shadowPicker,       cfg.textShadow)",
            "            dim(w.shadowPicker,       cfg.scenarioTextShadow)")]),

    ("the scenario shadow controls dim while their switch sits at its default on", [
        (A, "            dim(w.scShadowSizeSlider, cfg.scenarioTextShadow ~= false)",
            "            dim(w.scShadowSizeSlider, cfg.scenarioTextShadow)")]),

    ("Hide scroll bar no longer dims the group it switches off", [
        (A, "            local bar = not cfg.hideScrollBar", "            local bar = true")]),

    ("the scroll bar color stays lit while Hide scroll bar is on", [
        (A, "            dim(w.sbPicker,         bar and cfg.scrollBarBg ~= false)",
            "            dim(w.sbPicker,         cfg.scrollBarBg ~= false)")]),

    ("Thumb Width stays lit with Solid color thumb off", [
        (A, "            dim(w.thumbWidthSlider, bar and cfg.skinScrollBar)",
            "            dim(w.thumbWidthSlider, bar)")]),

    ("Hide scroll bar arrows is never dimmed", [
        (A, "            dim(w.hideArrowsCheck,  bar)\n", "")]),

    ("Border Thickness dims on the background switch", [
        (A, "            dim(w.borderThickSlider, cfg.showBorder)",
            "            dim(w.borderThickSlider, cfg.showBackground)")]),

    ("Edge Softness ignores Show header bars", [
        (A, "            dim(w.hbSoftSlider,   cfg.headerBar and cfg.headerBarSoftEdges)",
            "            dim(w.hbSoftSlider,   cfg.headerBarSoftEdges)")]),

    ("Bar Style is never dimmed", [
        (A, "            dim(w.hbStyle,        cfg.headerBar)\n", "")]),

    ("the custom title color dims the wrong way round, lit unless Custom is picked", [
        (A, "            dim(w.titlePicker,  ns.Util.TitleColorMode(cfg) == \"custom\")",
            "            dim(w.titlePicker,  ns.Util.TitleColorMode(cfg) ~= \"custom\")")]),

    ("Use title color for completed quests reads the raw override, missing Class color and Original Style", [
        (A, "            dim(w.recolorCheck, ns.Util.EffectiveTitleColor(cfg) ~= nil)",
            "            dim(w.recolorCheck, cfg.titleColorOverride ~= nil)")]),

    ("the custom title color dims on the raw key, so an old profile's custom color reads dim", [
        (A, "            dim(w.titlePicker,  ns.Util.TitleColorMode(cfg) == \"custom\")",
            "            dim(w.titlePicker,  cfg.titleColorMode == \"custom\")")]),

    ("Quest Title Color stores its pick but never re-runs the sweep", [
        (A, "            function(v) restyle(\"titleColorMode\", v); syncDependents() end,",
            "            function(v) restyle(\"titleColorMode\", v) end,")]),

    ("Quest Title Color reads the raw key, so every old profile reads blank", [
        (A, "            function() return ns.Util.TitleColorMode(DB()) end,",
            "            function() return DB().titleColorMode end,")]),

    ("Section Header Color dims on the TITLE class box", [
        (A, "            dim(w.headerPicker, not cfg.headerColorUseClass)",
            "            dim(w.headerPicker, not cfg.titleColorUseClass)")]),

    ("an unset row layout reads as Card", [
        (A, '            local card = (cfg.blockLayout or "classic") == "card"',
            '            local card = (cfg.blockLayout or "card") == "card"')]),

    ("the tints stay lit on Plain rows", [
        (A, "            local tint = card and cfg.cardTintByType", "            local tint = cfg.cardTintByType")]),

    ("Card behind the scenario panel is never dimmed", [
        (A, "            dim(w.scenarioCardCheck, card)\n", "")]),

    ("an unset zone bar location reads as docked", [
        (A, '            local float = on and (cfg.zoneProgressLocation or "floating") == "floating"',
            '            local float = on and (cfg.zoneProgressLocation or "tracker") == "floating"')]),

    ("the floating-only controls stay lit with the zone bar switched off", [
        (A, '            local float = on and (cfg.zoneProgressLocation or "floating") == "floating"',
            '            local float = (cfg.zoneProgressLocation or "floating") == "floating"')]),

    ("the zone bar texture dims when docked, where it still reaches the bar", [
        (A, "            dim(w.zbTexDD,          on)", "            dim(w.zbTexDD,          float)")]),

    ("the zone bar background color ignores its own box", [
        (A, "            dim(w.zbBgPicker,     float and zb.showBackground ~= false)",
            "            dim(w.zbBgPicker,     float)")]),

    ("the zone bar border color follows the background box", [
        (A, "            dim(w.zbBorderPicker, float and zb.showBorder ~= false)",
            "            dim(w.zbBorderPicker, float and zb.showBackground ~= false)")]),

    ("the sweep reads a blank zone bar table instead of the profile's", [
        (A, "            local zb  = zbState() or {}", "            local zb  = {}")]),

    ("the bar styling needs BOTH halves on rather than either", [
        (A, "                                    or cfg.showScenarioProgressBars ~= false)",
            "                                    and cfg.showScenarioProgressBars ~= false)")]),

    ("the bar styling ignores Show progress bars", [
        (A, "            local drawn = bars and (cfg.showQuestProgressBars ~= false",
            "            local drawn = (cfg.showQuestProgressBars ~= false")]),

    ("the two half-switches dim on whether a bar is drawn rather than on their master", [
        (A, "            dim(w.pbQuests,          bars)", "            dim(w.pbQuests,          drawn)")]),

    ("the progress bar background color ignores its own box", [
        (A, "            dim(w.pbBgPicker,        drawn and pb.showBackground ~= false)",
            "            dim(w.pbBgPicker,        drawn)")]),

    ("the sweep reads a blank progress bar table instead of the profile's", [
        (A, "            local pb    = pbState() or {}", "            local pb    = {}")]),

    ("the tab is built without dimming anything", [
        (A, "        syncDependents()\n        content._syncDependents = syncDependents\n",
            "        content._syncDependents = syncDependents\n")]),

    ("the sweep is not left for refresh", [
        (A, "        content._syncDependents = syncDependents\n", "")]),

    ("refresh skips the HUD's sweep", [
        (A, "        if content._syncHUD then content._syncHUD() end\n", "")]),

    ("the sweep creeps back toward the ceiling, closing over each card", [
        (A, "            local zb  = zbState() or {}\n",
            "            local zb  = zbState() or {}\n"
            "            local _ = look, questColors, tracker, headers, spacing, scrollBar, scenario\n")]),

    # ----------------------------------------------------------------------- the masters
    ("Text Shadow stops re-running the sweep", [
        (A, 'function(v) restyle("textShadow", v); syncDependents() end,',
            'function(v) restyle("textShadow", v) end,')]),

    ("Hide scroll bar stops re-running the sweep", [
        (A, 'function(v) relayout("hideScrollBar", v); syncDependents() end,',
            'function(v) relayout("hideScrollBar", v) end,')]),

    ("Soft edges stops re-running the sweep", [
        (A, 'function(v) relayout("headerBarSoftEdges", v); syncDependents() end,',
            'function(v) relayout("headerBarSoftEdges", v) end,')]),

    ("Row Layout stops re-running the sweep", [
        (A, 'function(v) restyle("blockLayout", v); syncDependents() end,',
            'function(v) restyle("blockLayout", v) end,')]),

    ("Tint cards by quest type stops re-running the sweep", [
        (A, 'function(v) restyle("cardTintByType", v); syncDependents() end,',
            'function(v) restyle("cardTintByType", v) end,')]),

    ("Float as a movable bar stops re-running the sweep", [
        (A, '                ns:GetModule("ZoneProgressBar"):SetLocation(v and "floating" or "tracker")\n'
            "                syncDependents()\n",
            '                ns:GetModule("ZoneProgressBar"):SetLocation(v and "floating" or "tracker")\n')]),

    ("the zone bar Background box stops re-running the sweep", [
        (A, 'function(v) zbSet("showBackground", v); syncDependents() end,',
            'function(v) zbSet("showBackground", v) end,')]),

    ("the progress bar Border box stops re-running the sweep", [
        (A, 'function(v) pbSet("showBorder", v); syncDependents() end,',
            'function(v) pbSet("showBorder", v) end,')]),

    ("Use title color for completed quests starts sweeping, against its recorded note", [
        (A, 'function(v) restyle("overrideCompleteGreen", v) end,',
            'function(v) restyle("overrideCompleteGreen", v); syncDependents() end,')]),

    ("the title color sweeps on every frame of a drag", [
        (A, "                if had ~= (v ~= nil) then syncDependents() end",
            "                syncDependents()")]),

    ("the title color sweeps only on arriving, so a Cancel back to none leaves it inert", [
        (A, "                if had ~= (v ~= nil) then syncDependents() end",
            "                if v ~= nil and not had then syncDependents() end")]),

    ("Clear on the title color stops re-running the sweep", [
        (A, '                setTitleOverride(nil)\n                syncDependents()\n',
            '                setTitleOverride(nil)\n')]),

    ("the title picker stops saving the mode first, so on an upgraded profile it switches the titles", [
        (A, "            db.titleColorMode = ns.Util.TitleColorMode(db)\n", "")]),

    ("the mode is saved after the color, so it is read off the new override", [
        (A, "            db.titleColorMode = ns.Util.TitleColorMode(db)\n"
            "            restyle(\"titleColorOverride\", v)\n",
            "            restyle(\"titleColorOverride\", v)\n"
            "            db.titleColorMode = ns.Util.TitleColorMode(db)\n")]),

    ("the mode is saved as By difficulty whatever the old switches say", [
        (A, "            db.titleColorMode = ns.Util.TitleColorMode(db)\n",
            "            db.titleColorMode = \"difficulty\"\n")]),

    ("only a missing mode is saved, so a profile with an unknown one still switches its titles", [
        (A, "            db.titleColorMode = ns.Util.TitleColorMode(db)\n",
            "            if db.titleColorMode == nil then db.titleColorMode = ns.Util.TitleColorMode(db) end\n")]),

    ("the picker's setter goes straight to the override, past the saved mode", [
        (A, "                setTitleOverride(v)\n", "                restyle(\"titleColorOverride\", v)\n")]),

    ("Clear goes straight to the override, so an upgraded Custom profile falls to By difficulty", [
        (A, "                setTitleOverride(nil)\n", "                restyle(\"titleColorOverride\", nil)\n")]),

    # ------------------------------------------------------------------- the small sweeps
    ("the opacity slider stores a whole number where a fraction belongs", [
        (A, "                DB().trackerAlpha = v / 100\n", "                DB().trackerAlpha = v\n")]),

    ("the opacity boxes are never dimmed when the tab is built", [
        (A, "        syncFade()\n\n        local bgRow = tracker:Add(", "\n        local bgRow = tracker:Add(")]),

    ("the HUD background color dims on the border box", [
        (A, "                self:SetDependent(sbBgPicker,     st.showBackground ~= false)",
            "                self:SetDependent(sbBgPicker,     st.showBorder ~= false)")]),

    ("the HUD Background box stops re-running the HUD's sweep", [
        (A, 'function(v) sbSet("showBackground", v); syncHUD() end,',
            'function(v) sbSet("showBackground", v) end,')]),

    ("the HUD pickers are not dimmed when the tab is built", [
        (A, "            syncHUD()\n            content._syncHUD = syncHUD\n",
            "            content._syncHUD = syncHUD\n")]),

    ("the HUD background color can no longer be cleared", [
        (A, '                function() sbSet("backgroundColor", nil) end)\n            satellite(self, sbBgRow, sbBgPicker)',
            '                nil)\n            satellite(self, sbBgRow, sbBgPicker)')]),

    ("the Test button loses its width", [
        (A, '            bonus:Add(self:CreateButton(content, L["Test"], 120, function()',
            '            bonus:Add(self:CreateButton(content, L["Test"], nil, function()')]),

    # ------------------------------------------- the live tracker, which the preview cannot stand in for
    ("restyle never invalidates the rows, so a font change misses every row already drawn", [
        (A, 'local function restyle(key, v)\n    DB()[key] = v\n    ns:GetModule("Row"):Invalidate()\n',
            'local function restyle(key, v)\n    DB()[key] = v\n')]),

    ("relayout never redraws the tracker", [
        (A, 'local function relayout(key, v)\n    DB()[key] = v\n    ns:GetModule("Tracker"):Render()\n',
            'local function relayout(key, v)\n    DB()[key] = v\n')]),

    ("relayout invalidates every row as restyle does", [
        (A, 'local function relayout(key, v)\n    DB()[key] = v\n',
            'local function relayout(key, v)\n    DB()[key] = v\n    ns:GetModule("Row"):Invalidate()\n')]),

    ("the progress bar styling never invalidates the rows", [
        (A, '    if st then st[key] = v end\n    ns:GetModule("Row"):Invalidate()\n',
            '    if st then st[key] = v end\n')]),

    ("the zone bar styling never reaches the floating bar", [
        (A, '    ns:GetModule("ZoneProgressBar"):RefreshAppearance()\n', "")]),

    ("the zone bar texture and color never reach the docked bar", [
        (A, '    if shared then ns:GetModule("Tracker"):Render() end\n', "")]),

    ("every zone bar control redraws the whole tracker", [
        (A, '    if shared then ns:GetModule("Tracker"):Render() end\n',
            '    ns:GetModule("Tracker"):Render()\n')]),

    ("the scenario banner shadow is never applied", [
        (A, '    ns:GetModule("Scenario"):ApplyBannerShadow()\n', "")]),

    ("the HUD's apply path is dropped", [
        (A, '    if st then st[key] = v end\n    ns:GetModule("ScenarioBonusHUD"):ApplySettings()\n',
            '    if st then st[key] = v end\n')]),

    ("the HUD switch does nothing", [
        (A, '                function(v) ns:GetModule("ScenarioBonusHUD"):SetEnabled(v) end,',
            '                function() end,')]),

    ("the Test button does nothing", [
        (A, '                ns:GetModule("ScenarioBonusHUD"):ToggleTest()\n', "")]),

    ("HUD Scale does nothing", [
        (A, '                function(v) ns:GetModule("ScenarioBonusHUD"):SetScale(v) end,',
            '                function() end,')]),

    ("Tracker Scale is stored but never applied", [
        (A, '                ns:GetModule("Tracker"):ApplyScale()\n', "")]),

    ("the zone bar's Float box docks it when ticked", [
        (A, 'SetLocation(v and "floating" or "tracker")', 'SetLocation(v and "tracker" or "floating")')]),

    ("Reset to Defaults reloads without resetting anything", [
        (A, '                    ns:GetModule("DB"):ResetTrackerAppearance()\n', "")]),

    ("Reset to Defaults resets without asking", [
        (A, '            if not Dialog then return end\n            Dialog:Show({\n                title    = "EQ Objective Tracker",\n'
            '                text     = L["Reset every setting on this tab to its defaults? The interface will reload."],',
            '            if not Dialog then return end\n            ns:GetModule("DB"):ResetTrackerAppearance()\n            Dialog:Show({\n                title    = "EQ Objective Tracker",\n'
            '                text     = L["Reset every setting on this tab to its defaults? The interface will reload."],')]),

    ("the tracker font list loses its per-face preview", [
        (A, "            nil, nil, fontPreview))", "            nil, nil, nil))")]),

    ("the zone bar's Same as tracker font row asks for a face it does not have", [
        (A, '    if not name or name == "" then return nil end\n', '    if not name then return nil end\n')]),
    # Which tooltip sits on which class color box. Both keys stay valid, so the locale gate cannot see a swap.
    ("Quest Title Color carries the custom picker's tooltip", [
        (A, '            L["How quest, achievement and endeavor titles are colored. Failed quests are always red, and finished ones green unless Use title color for completed quests is on."]))', '            L["The color every title takes while Quest Title Color is set to Custom color. Until one is picked they are gold."]))')]),

    ("the headers box carries the titles tooltip", [
        (A, '            L["Colors the section headers (Quests, Campaign, and so on) with the class color of the character you are currently logged in on. Overrides the color below while it is on. Off by default."]))', '            L["Colors quest, achievement, and endeavor titles with the class color of the character you are currently logged in on. Overrides the color below while it is on. Off by default."]))')]),

    ("the in-progress count color writes the none-done key", [
        (A, "            function(v) restyle(\"countColorPartial\", v) end,",
            "            function(v) restyle(\"countColorNone\", v) end,")]),

    ("the objective text color reads the done count's key", [
        (A, "            function() return DB().objectiveColor end,",
            "            function() return DB().countColorDone end,")]),

    ("the finished objective color loses its Clear, so green can never come back", [
        (A, "            function() restyle(\"finishedObjectiveColor\", nil) end))",
            "            nil))")]),

    ("the finished objective color takes alpha", [
        (A, "L[\"Color of an objective you have finished. While unset it follows Count Color: Done, or the title color when Use title color for completed quests gives one.\"],\n            false,",
            "L[\"Color of an objective you have finished. While unset it follows Count Color: Done, or the title color when Use title color for completed quests gives one.\"],\n            true,")]),

    ("the gold choice goes back to the bare key the store translates as money", [
        (A, 'label = L["Gold color"],', 'label = L["Gold"],')]),

    ("the gold choice is typed in English, so no language can translate it", [
        (A, 'label = L["Gold color"],', 'label = "Gold color",')]),

    ("the Quest Colors card title is typed in English", [
        (A, 'stack(self:CreateGroup(content, L["Quest Colors"]))', 'stack(self:CreateGroup(content, "Quest Colors"))')]),

    ("the Gold and Class color choices carry each other's tips", [
        (A, 'tip = L["Every title in the same gold."] },', 'tip = L["Every title in the class color of the character you are logged in on."] },'),
        (A, '      tip = L["Every title in the class color of the character you are logged in on."] },\n    -- Not L["Custom"]',
            '      tip = L["Every title in the same gold."] },\n    -- Not L["Custom"]')]),

    ("an empty override table reads as Custom, so the profile's titles go gold", [
        (U, '    if ov and ov.r then return "custom" end', '    if ov then return "custom" end')]),

    ("the objective text color takes alpha", [
        (A, 'L["Color of the objective lines under each title. The count at the start of a line has its own three colors below."]))',
            'L["Color of the objective lines under each title. The count at the start of a line has its own three colors below."], true))')]),

    # ------------------------------------------- strings drawn bare, which only a marked build sees
    ("Quest Title Color's own label is typed in English, its tooltip title still wrapped", [
        (A, 'self:CreateRadioGroup(content, L["Quest Title Color"],', 'self:CreateRadioGroup(content, "Quest Title Color",')]),

    ("the Tracker card's Background box is typed in English, while three other cards wrap it", [
        (A, '        local bgRow = tracker:Add(self:CreateCheckbox(content, L["Background"],',
            '        local bgRow = tracker:Add(self:CreateCheckbox(content, "Background",')]),

    ("the Quest Rows card title is typed in English", [
        (A, 'stack(self:CreateGroup(content, L["Quest Rows"]))', 'stack(self:CreateGroup(content, "Quest Rows"))')]),

    ("the Card layout choice is typed in English", [
        (A, '{ value = "card",    label = L["Card"] },', '{ value = "card",    label = "Card" },')]),

    ("the Left banner alignment is typed in English", [
        (A, '{ value = "LEFT",   label = L["Left"] },', '{ value = "LEFT",   label = "Left" },')]),

    ("a tooltip is typed in English", [
        (A, 'L["Shadow color and opacity."]', '"Shadow color and opacity."')]),

    ("the Reset prompt is typed in English", [
        (A, 'text     = L["Reset every setting on this tab to its defaults? The interface will reload."],',
            'text     = "Reset every setting on this tab to its defaults? The interface will reload.",')]),

    # ------------------------------------------------- a sweep that runs before the setter stores
    ("Text Shadow sweeps before it stores, so its dependents dim for the old value", [
        (A, 'function(v) restyle("textShadow", v); syncDependents() end,',
            'function(v) syncDependents(); restyle("textShadow", v) end,')]),

    ("the title picker sweeps before it stores", [
        (A, '                setTitleOverride(v)\n', ''),
        (A, '                if had ~= (v ~= nil) then syncDependents() end',
            '                if had ~= (v ~= nil) then syncDependents() end\n                setTitleOverride(v)')]),

    ("Clear on the title color sweeps before it clears", [
        (A, '                setTitleOverride(nil)\n                syncDependents()\n',
            '                syncDependents()\n                setTitleOverride(nil)\n')]),

    ("a color picked over an empty one counts as no change, so the sweep is skipped", [
        (A, 'local had = (DB().titleColorOverride or {}).r ~= nil', 'local had = DB().titleColorOverride ~= nil')]),

    ("Quest Title Color loses Original Style", [
        (A, "    { value = \"original\",   label = L[\"Original Style\"],\n"
            "      tip = L[\"Titles colored the way Blizzard's own tracker colors them on this version of the game.\"] },\n", "")]),

    ("the headers tooltip points at the picker above again", [
        (A, '            L["Colors the section headers (Quests, Campaign, and so on) with the class color of the character you are currently logged in on. Overrides the color below while it is on. Off by default."]))', '            L["Colors the section headers (Quests, Campaign, and so on) with the class color of the character you are currently logged in on. Overrides the color above while it is on. Off by default."]))')]),
]

SUMMARY = re.compile(r"^test_appearance: (\d+) passed, (\d+) failed$")


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
