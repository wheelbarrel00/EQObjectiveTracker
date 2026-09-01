local _, ns = ...

local Options = ns:GetModule("Options")
local L       = ns.L

-- Wrapped at the table, never as L[SORT_OPTIONS[i].tip] - the scanner matches the literal
-- L["..."] only, so a computed index never reaches the manifest and can never be translated.
local SORT_OPTIONS = {
    { value = "zone",     label = L["Zone"],
      tip = L["Groups entries under the heading they sit under in your quest log."] },
    { value = "title",    label = L["Title"],
      tip = L["Alphabetical by name."] },
    { value = "status",   label = L["Status"],
      tip = L["Puts everything that is ready to turn in at the top."] },
    { value = "type",     label = L["Type"],
      tip = L["Weekly first, then daily, then everything else. Only quests carry a type, so other sections fall back to alphabetical."] },
    { value = "level",    label = L["Level"],
      tip = L["Lowest quest level first."] },
    { value = "distance", label = L["Distance"],
      tip = L["Nearest objective first, updated as you move. A quest ready to turn in measures to its turn-in point."] },
    { value = "recent",   label = L["Recent"],
      tip = L["Most recently accepted first."] },
    { value = "manual",   label = L["Manual"],
      tip = L["Your own order. Drag quests up and down in the tracker to set it."] },
}

-- EQ's own screen order, which is not Filter.CATEGORIES order - that one encodes match
-- precedence and must not be reshuffled for display.
local FILTER_ORDER = {
    "showNormal", "showDaily", "showWeekly", "showScheduled", "showCampaign", "showWorld",
    "showBonus",
}

-- Most of these say what they are in the label. Scheduled is the one nothing in the game
-- names out loud, so the generic line below leaves the player guessing.
local FILTER_TIPS = {
    showScheduled = L["Quests the game resets on its own schedule rather than daily or weekly. Special Assignments and some meta quests are what you will see here."],
}

-- EQ exposes three of these. The author kept all five plus World Quests, so the shape is
-- EQ's flat run and only the row count differs.
local VISIBILITY_ROWS = {
    { id = "campaign",     label = L["Campaign section"]     },
    { id = "quests",       label = L["Quests section"]       },
    { id = "profession",   label = L["Profession section"]   },
    { id = "endeavors",    label = L["Endeavors section"]    },
    { id = "achievements", label = L["Achievements section"] },
    { id = "worldquests",  label = L["World Quests section"] },
}

local WQ_POSITIONS = {
    { value = "top",    label = L["Top"] },
    { value = "bottom", label = L["Bottom"] },
}

local ORDER_ROW_H = 24

-- The right column is a second anchor chain rooted this far right of the first header,
-- sharing its y. Same figure the Appearance tab uses.
local COLUMN_X = 460

local function DB() return ns:GetModule("DB"):Tracker() end
local function render() ns:GetModule("Tracker"):Render() end

local function trackerSetting(key)
    return function() return DB()[key] end,
           function(v) DB()[key] = v; render() end
end

-- Row memoizes on the fields in its repaint gate and returns early when they all match, so
-- anything that changes how a row READS has to invalidate or it silently never repaints.
local function rowSetting(key, defaultOn)
    return function()
               local v = DB()[key]
               if defaultOn then return v ~= false end
               return v
           end,
           function(v)
               DB()[key] = v
               ns:GetModule("Row"):Invalidate()
               render()
           end
end

local function filterSetting(key)
    return function() return DB().filters[key] ~= false end,
           function(v) DB().filters[key] = v; render() end
end

local function sectionLabel(id)
    return ns:GetModule("Sections"):Title(id)
end

-- Blizzard's stock triangles, not a glyph in a panel button. The tooltip is hand-rolled
-- rather than going through AttachTooltip because EQ titles this one white, not gold.
local function makeOrderArrow(parent, dir)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(18, 18)
    b:SetNormalTexture("Interface\\Buttons\\Arrow-" .. dir .. "-Up")
    b:SetPushedTexture("Interface\\Buttons\\Arrow-" .. dir .. "-Down")
    b:SetDisabledTexture("Interface\\Buttons\\Arrow-" .. dir .. "-Disabled")
    local isUp = (dir == "Up")
    b:HookScript("OnEnter", function(self)
        local row = self:GetParent()
        local name = (row and row.sectionID and sectionLabel(row.sectionID)) or ""
        local tip = ns.Util.Tooltip()
        tip:SetOwner(self, "ANCHOR_RIGHT")
        -- SetText arg 5 is alpha, not wrap. Pass 1 or the line renders invisible.
        tip:SetText((isUp and L["Move %s up"] or L["Move %s down"]):format(name),
                    1, 1, 1, 1, true)
        tip:AddLine(L["Reorders where this section sits in the tracker. A section only shows while it has something in it, so empty sections won't visibly move."],
                    0.82, 0.82, 0.82, true)
        tip:Show()
    end)
    b:HookScript("OnLeave", function() ns.Util.Tooltip():Hide() end)
    return b
end

Options:RegisterTab({
    id    = "tracker",
    title = L["Tracker"],
    order = 20,
    build = function(self, content)
        local Sections = ns:GetModule("Sections")
        local Filter   = ns:GetModule("Filter")
        local Registry = ns:GetModule("Registry")

        local header = self:CreateHeading(content, L["On-Screen Tracker"])
        header:SetPoint("TOPLEFT", 8, -8)
        self:AttachTooltip(header, L["On-Screen Tracker"],
            L["Changes apply immediately to the on-screen tracker."])

        local watchedGet, watchedSet = trackerSetting("showOnlyWatched")
        local watched = self:CreateCheckbox(content, L["Show only tracked quests"],
            watchedGet, watchedSet,
            L["Hides quests that are in your log but not tracked. Matches Blizzard's default tracker."])
        watched:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, self.GAP.tabHead)

        local simplify = self:CreateCheckbox(content, L["Simplify Mode"],
            trackerSetting("simplifyMode"))
        simplify:SetPoint("TOPLEFT", watched, "BOTTOMLEFT", 0, -2)
        self:AttachTooltip(simplify, L["Simplify Mode"],
            L["Show only the first incomplete objective per quest."])

        local achSimplify = self:CreateCheckbox(content, L["Simplify tracked achievements"],
            function() return DB().simplifyGroups and DB().simplifyGroups.achievements end,
            function(v)
                DB().simplifyGroups = DB().simplifyGroups or {}
                DB().simplifyGroups.achievements = v
                render()
            end,
            L["Show only incomplete criteria for tracked achievements."])
        achSimplify:SetPoint("TOPLEFT", simplify, "BOTTOMLEFT", 0, -2)

        local manualHint, filtersHeader, sort
        local function syncManualHint(value)
            local manual = (value == "manual")
            if manualHint then manualHint:SetShown(manual) end
            if filtersHeader and sort then
                filtersHeader:ClearAllPoints()
                if manual and manualHint then
                    filtersHeader:SetPoint("TOPLEFT", manualHint, "BOTTOMLEFT", 0, self.GAP.aboveHead)
                else
                    filtersHeader:SetPoint("TOPLEFT", sort, "BOTTOMLEFT", 0, self.GAP.aboveHead)
                end
                -- Showing the hint moves the whole left column, and the scroll range is
                -- otherwise only measured on a tab switch.
                self:MeasureContent(content)
            end
        end

        sort = self:CreateRadioGroup(content, L["Sort Order"],
            SORT_OPTIONS,
            function() return DB().sortMode or "zone" end,
            function(v)
                DB().sortMode = v
                render()
                syncManualHint(v)
            end,
            440, 14)
        sort:SetPoint("TOPLEFT", achSimplify, "BOTTOMLEFT", 0, -12)

        manualHint = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        manualHint:SetPoint("TOPLEFT", sort, "BOTTOMLEFT", 0, -10)
        manualHint:SetWidth(440)
        manualHint:SetJustifyH("LEFT")
        manualHint:SetTextColor(0.67, 0.67, 0.67)
        manualHint:SetText(L["Drag and drop the quests in the tracker to reorder them however you like."])

        filtersHeader = self:CreateHeading(content, L["Filters"])
        syncManualHint(DB().sortMode)

        local byKey = {}
        for i = 1, #Filter.CATEGORIES do
            byKey[Filter.CATEGORIES[i].key] = Filter.CATEGORIES[i]
        end

        local prev, filterBoxes = filtersHeader, {}
        for _, key in ipairs(FILTER_ORDER) do
            local c = byKey[key]
            -- No loaded provider can produce this category, so the toggle would be dead
            if c and ((not c.tag) or Registry:HasTag(c.tag)) then
                local get, set = filterSetting(key)
                -- Not interpolated with the label: every label already ends in a noun, so
                -- the old form read "Show or hide world quests entries in the tracker."
                local cb = self:CreateCheckbox(content, c.label, get, set,
                    FILTER_TIPS[key] or L["Show or hide this category of entry in the tracker."])
                cb:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, prev == filtersHeader and self.GAP.head or -2)
                filterBoxes[#filterBoxes + 1] = { key = key, cb = cb }
                prev = cb
            end
        end

        local zoneOnly = self:CreateCheckbox(content, L["Show only quests in current zone"],
            function() return DB().filters.onlyCurrentZone end,
            function(v) DB().filters.onlyCurrentZone = v; render() end,
            L["Only show entries with an objective on your current map. Entries whose provider cannot tell are always shown."])
        zoneOnly:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -2)

        -- Deliberately does NOT touch showOnlyWatched. That box sits under a different
        -- heading and is the most impactful setting on the tab, so silently turning it back
        -- on here hid quests with nothing connecting the two.
        local resetFilters = self:CreateButton(content, L["Reset filters to defaults"], 180,
            function()
                local f = DB().filters
                -- Walked rather than listed, so a category added to Filter.CATEGORIES is
                -- reset here without anyone remembering to come back for it.
                for i = 1, #Filter.CATEGORIES do f[Filter.CATEGORIES[i].key] = true end
                f.onlyCurrentZone = false
                -- Re-checked in place rather than by reloading the tab: these boxes only
                -- read their getter on build and on a tab view.
                zoneOnly:SetChecked(false)
                for _, e in ipairs(filterBoxes) do
                    e.cb:SetChecked(f[e.key] ~= false)
                end
                render()
            end,
            L["Turns every category filter back on and clears the current-zone filter. Nothing else on this tab is changed."])
        resetFilters:SetSize(180, 24)
        resetFilters:SetPoint("TOPLEFT", zoneOnly, "BOTTOMLEFT", 0, -10)

        local visHeader = self:CreateHeading(content, L["Tracker Visibility"])
        visHeader:SetPoint("TOPLEFT", resetFilters, "BOTTOMLEFT", 0, self.GAP.aboveHead)

        -- Gated like the filter run above it: a section its TOC never loaded must not get a
        -- toggle that can never do anything.
        local liveSections = {}
        for _, id in ipairs(Sections:Known()) do liveSections[id] = true end

        local visPrev = visHeader
        for _, row in ipairs(VISIBILITY_ROWS) do
            local id = row.id
            if liveSections[id] then
                -- The box SHOWS the section, so the tooltip has to describe unchecking it.
                local cb = self:CreateCheckbox(content, row.label,
                    function() return not Sections:IsHidden(id) end,
                    function(v) Sections:SetHidden(id, not v); render() end,
                    L["Uncheck to hide this section from the tracker even while it has entries."])
                cb:SetPoint("TOPLEFT", visPrev, "BOTTOMLEFT", 0, visPrev == visHeader and self.GAP.head or -2)
                visPrev = cb
            end
        end

        -- No loaded provider can produce a world quest, so the whole block would sit there
        -- with nothing behind it. The region itself still exists at 1px on such a flavor,
        -- which is exactly why the controls read as live when they are not.
        local hasWorldQuests = Registry:HasTag("worldquest")
        local wqPrev = visPrev

        if hasWorldQuests then
            local autoWQ = self:CreateCheckbox(content, L["Auto-list current-zone world quests"],
                trackerSetting("autoListZoneWorldQuests"))
            autoWQ:SetPoint("TOPLEFT", visPrev, "BOTTOMLEFT", 0, -2)
            self:AttachTooltip(autoWQ, L["Auto-list current-zone world quests"],
                L["Lists every WQ in your zone without tracking each."])

            -- The two sliders are mutually exclusive - UI/Tracker.lua reads the fixed height or
            -- the fraction, never both - so exactly one of them is live at a time and the dead
            -- one has to say so.
            local wqHeightSlider, wqMaxSlider
            local function setWqHeightEnabled(on)
                self:SetDependent(wqHeightSlider, on)
                self:SetDependent(wqMaxSlider, not on)
            end

            local wqhCheck = self:CreateCheckbox(content, L["Set a custom World Quests height"],
                function() return DB().worldQuestsHeightOverride end,
                function(v)
                    DB().worldQuestsHeightOverride = v
                    setWqHeightEnabled(v)
                    render()
                end,
                L["By default the World Quests area is capped to a share of the tracker, set by the slider below that. Turn this on to give it a fixed height in pixels instead."])
            wqhCheck:SetPoint("TOPLEFT", autoWQ, "BOTTOMLEFT", 0, -2)

            wqHeightSlider = self:CreateSlider(content, L["World Quests Height"], 40, 400, 10,
                function() return DB().worldQuestsHeight or 200 end,
                function(v) DB().worldQuestsHeight = v; render() end,
                L["Height in pixels for the world quest area. Only used while Set a custom World Quests height is on."])
            wqHeightSlider:SetPoint("TOPLEFT", wqhCheck, "BOTTOMLEFT", 0, -8)

            -- EQOT-only: EQ caps the world quest area by fixed height alone. Kept because it
            -- is backed by real tracker code, and placed with the other height controls.
            wqMaxSlider = self:CreateSlider(content, L["Maximum Height (percent of tracker)"], 10, 80, 5,
                function() return (DB().worldQuestsPinnedMaxFraction or 0.40) * 100 end,
                function(v)
                    DB().worldQuestsPinnedMaxFraction = v / 100
                    render()
                end,
                L["The most of the tracker the world quest area may take. It is capped here first and your quest list takes the space that is left, scrolling for whatever does not fit. Only used while Set a custom World Quests height is off."])
            wqMaxSlider:SetPoint("TOPLEFT", wqHeightSlider, "BOTTOMLEFT", 0, -14)
            setWqHeightEnabled(DB().worldQuestsHeightOverride)
            wqPrev = wqMaxSlider
        end

        local orderHeader = self:CreateHeading(content, L["Section Order"])
        orderHeader:SetPoint("TOPLEFT", wqPrev, "BOTTOMLEFT", 0, self.GAP.aboveHead)
        self:AttachTooltip(orderHeader, L["Section Order"],
            L["Rearrange the tracker's sections with the arrows below. A section only appears on the tracker while it has something in it, so reordering an empty section won't look like anything changed. World Quests scroll in their own panel and can only sit at the very top or bottom, so use the Top/Bottom control."])

        local wqPos = self:CreateRadioGroup(content, L["World Quests Position"],
            WQ_POSITIONS,
            function() return DB().worldQuestsPosition or "bottom" end,
            function(v) ns:GetModule("Tracker"):SetWorldQuestsPosition(v) end,
            300, 14,
            L["World Quests Position"],
            L["Where the World Quests panel sits on the tracker. |cffffffffTop|r puts it above your quests. |cffffffffBottom|r keeps it below your quests, which is the default. World Quests scroll in their own capped panel, which is why they can't be mixed in between the other sections."])
        wqPos:SetPoint("TOPLEFT", orderHeader, "BOTTOMLEFT", 0, self.GAP.head)
        if not hasWorldQuests then wqPos:Hide() end

        local orderList = CreateFrame("Frame", nil, content)
        orderList:SetPoint("TOPLEFT", hasWorldQuests and wqPos or orderHeader, "BOTTOMLEFT", 0,
                           hasWorldQuests and -10 or self.GAP.head)
        orderList:SetSize(300, ORDER_ROW_H)

        local orderRows = {}
        local function renderOrderRows()
            local order = Sections:Order()
            for _, r in ipairs(orderRows) do r:Hide() end
            for i, id in ipairs(order) do
                local row = orderRows[i]
                if not row then
                    row = CreateFrame("Frame", nil, orderList)
                    row:SetHeight(ORDER_ROW_H)
                    row.up = makeOrderArrow(row, "Up")
                    row.up:SetPoint("LEFT", 0, 0)
                    row.down = makeOrderArrow(row, "Down")
                    row.down:SetPoint("LEFT", row.up, "RIGHT", 3, 0)
                    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    row.label:SetPoint("LEFT", row.down, "RIGHT", 8, 0)
                    row.label:SetTextColor(1, 1, 1)
                    orderRows[i] = row
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT",  orderList, "TOPLEFT",  0, -(i - 1) * ORDER_ROW_H)
                row:SetPoint("TOPRIGHT", orderList, "TOPRIGHT", 0, -(i - 1) * ORDER_ROW_H)
                row.sectionID = id
                row.label:SetText(sectionLabel(id))
                row.up:SetEnabled(i > 1)
                row.down:SetEnabled(i < #order)
                -- The list reorders under a stationary cursor, so a tooltip left up would
                -- keep naming the section that used to be on this row.
                row.up:SetScript("OnClick", function()
                    Sections:Move(id, -1)
                    render()
                    renderOrderRows()
                    ns.Util.Tooltip():Hide()
                end)
                row.down:SetScript("OnClick", function()
                    Sections:Move(id, 1)
                    render()
                    renderOrderRows()
                    ns.Util.Tooltip():Hide()
                end)
                row:Show()
            end
            orderList:SetHeight(math.max(1, #order * ORDER_ROW_H))
        end
        renderOrderRows()

        local optionsHeader = self:CreateHeading(content, L["Options"])
        optionsHeader:SetPoint("TOPLEFT", header, "TOPLEFT", COLUMN_X, 0)

        local diff = self:CreateCheckbox(content, L["Quest Title Color By Difficulty"],
            rowSetting("colorByDifficulty", true))
        diff:SetPoint("TOPLEFT", optionsHeader, "BOTTOMLEFT", 0, self.GAP.tabHead)
        -- Its master is on the Appearance tab, so the sweep there can never reach it. Per
        -- view rather than per setter for the same reason.
        content._syncDiff = function()
            local cfg = DB() or {}
            self:SetDependent(diff, cfg.titleColorOverride == nil and not cfg.titleColorUseClass)
        end
        content._syncDiff()
        self:AttachTooltip(diff, L["Quest Title Color By Difficulty"],
            L["Colors each quest title by how hard it is for your level, the way the quest log does. The Quest Title Color Override on the Appearance tab wins over this while it is set."])

        local lvl = self:CreateCheckbox(content, L["Show quest level prefix"],
            rowSetting("showLevelInTracker"))
        lvl:SetPoint("TOPLEFT", diff, "BOTTOMLEFT", 0, -2)
        self:AttachTooltip(lvl, L["Show quest level prefix"], L["For example, [60] Title."])

        local zoneCheck = self:CreateCheckbox(content, L["Show zone label under quest titles"],
            rowSetting("showZoneTag"))
        zoneCheck:SetPoint("TOPLEFT", lvl, "BOTTOMLEFT", 0, -2)
        self:AttachTooltip(zoneCheck, L["Show zone label under quest titles"],
            L["Adds the quest log heading each quest came from as a small line under its title."])

        local objCheck = self:CreateCheckbox(content, L["Show objective progress numbers"],
            rowSetting("showObjectiveNumbers", true))
        objCheck:SetPoint("TOPLEFT", zoneCheck, "BOTTOMLEFT", 0, -2)
        self:AttachTooltip(objCheck, L["Show objective progress numbers"],
            L["For example, 0/4, 1/1, etc."])

        -- Show progress bars moved to the Appearance tab's Progress Bars group, so the switch
        -- that turns the bars on is not two tabs away from the controls that style them. Same
        -- move the zone progress bar's own toggles made, for the same reason.
        local widgetCheck = self:CreateCheckbox(content, L["Show event and scenario widgets"],
            rowSetting("showTrackerWidgets", true))
        widgetCheck:SetPoint("TOPLEFT", objCheck, "BOTTOMLEFT", 0, -2)
        self:AttachTooltip(widgetCheck, L["Show event and scenario widgets"],
            L["Draws the extra bars and status lines the default tracker shows during world events, delves and scenarios, such as an event's progress bar or a delve's tier. This tracker replaces the default one, so without this those are not shown anywhere."])

        local qidCheck = self:CreateCheckbox(content, L["Show quest ID"],
            rowSetting("showQuestID"))
        qidCheck:SetPoint("TOPLEFT", widgetCheck, "BOTTOMLEFT", 0, -2)
        self:AttachTooltip(qidCheck, L["Show quest ID"], L["Useful for bug reports."])

        -- UI/Tracker.lua reads showQuestTotal for every ordinary section and for the pinned
        -- world quest region, not just Quests and Campaign, and the pair it draws is
        -- visible/total rather than tracked/total.
        local qtotalCheck = self:CreateCheckbox(content,
            L["Show the visible / total count on section headers"],
            function() return DB().showQuestTotal ~= false end,
            function(v) DB().showQuestTotal = v; render() end,
            L["For example, 3/9. Applies to every section header."])
        qtotalCheck:SetPoint("TOPLEFT", qidCheck, "BOTTOMLEFT", 0, -2)

        local itemBtnCheck = self:CreateCheckbox(content, L["Show usable quest item buttons"],
            rowSetting("showItemButtons", true))
        itemBtnCheck:SetPoint("TOPLEFT", qtotalCheck, "BOTTOMLEFT", 0, -2)
        self:AttachTooltip(itemBtnCheck, L["Show usable quest item buttons"],
            L["Puts a button on the tracker row of any quest that carries a usable item, so you can use it without opening your bags."])

        local optIconCheck = self:CreateCheckbox(content, L["Show Options icon on the tracker"],
            function() return DB().showOptionsIcon ~= false end,
            function(v)
                DB().showOptionsIcon = v
                ns:GetModule("Tracker"):ApplyHeaderIcons()
            end,
            L["A small cogwheel at the top-right of the tracker that opens the options panel."])
        optIconCheck:SetPoint("TOPLEFT", itemBtnCheck, "BOTTOMLEFT", 0, -2)

        -- EQ has Show Chain Guide icon after this one. Deliberately not ported: it opens
        -- EQ's Chain Guide, which EQOT does not have. Hide scroll bar used to sit here too,
        -- and now heads the Scroll Bar group on Appearance that it switches off.
        local popupCheck = self:CreateCheckbox(content, L["Show Quest Discovered popups"],
            function() return DB().showQuestPopups ~= false end,
            function(v) DB().showQuestPopups = v; render() end,
            L["Boxes for newly discovered / completed quests."])
        popupCheck:SetPoint("TOPLEFT", optIconCheck, "BOTTOMLEFT", 0, -2)

        local newTagCheck = self:CreateCheckbox(content,
            L["Show NEW tag on recently accepted quests"],
            rowSetting("showRecentlyAddedTag", true))
        newTagCheck:SetPoint("TOPLEFT", popupCheck, "BOTTOMLEFT", 0, -2)
        self:AttachTooltip(newTagCheck, L["Show NEW tag on recently accepted quests"],
            L["For about an hour after accepting."])

        local splitCheck = self:CreateCheckbox(content, L["Split quest click"],
            trackerSetting("splitQuestClick"))
        splitCheck:SetPoint("TOPLEFT", newTagCheck, "BOTTOMLEFT", 0, -2)
        self:AttachTooltip(splitCheck, L["Split quest click"],
            L["Click the icon to focus, click the title to open the quest log."])

        local soundCheck = self:CreateCheckbox(content, L["Quest Sound"],
            function() return DB().questSoundEnabled ~= false end,
            function(v) DB().questSoundEnabled = v end,
            L["Plays when a quest is ready to turn in."])
        soundCheck:SetPoint("TOPLEFT", splitCheck, "BOTTOMLEFT", 0, -2)

        local function playSound(value)
            ns:GetModule("Media"):Play(value)
        end
        -- The list is rebuilt on every open rather than captured, which is what CreateDropdown's
        -- function form is for, and both pickers want the identical one.
        local function soundList()
            local labels, values = ns:GetModule("Media"):GetSoundList()
            local out = {}
            for _, name in ipairs(labels) do
                out[#out + 1] = { value = values[name] or "NONE", label = name }
            end
            return out
        end
        local soundDD = self:CreateDropdown(content, L["Quest Complete Sound"],
            soundList,
            function() return DB().questCompleteSound or "NONE" end,
            function(v) DB().questCompleteSound = v; playSound(v) end,
            L["Which sound plays when a quest becomes ready to turn in."],
            nil, playSound)
        soundDD:SetPoint("TOPLEFT", soundCheck, "BOTTOMLEFT", 0, -8)

        -- Its own switch rather than hanging off Quest Sound above, so a player can have one
        -- without the other. == true, not ~= false: this one ships off.
        local acceptCheck = self:CreateCheckbox(content,
            L["Play a sound when you accept a quest"],
            function() return DB().questAcceptSoundEnabled == true end,
            function(v) DB().questAcceptSoundEnabled = v end,
            L["Off by default. It has its own sound below, so accepting and completing can be told apart."])
        acceptCheck:SetPoint("TOPLEFT", soundDD, "BOTTOMLEFT", 0, -8)

        local acceptDD = self:CreateDropdown(content, L["Quest Accepted Sound"],
            soundList,
            function() return DB().questAcceptSound or "NONE" end,
            function(v) DB().questAcceptSound = v; playSound(v) end,
            L["Which sound plays when you accept a quest. World quests and bonus objectives are left silent, since walking into one accepts it."],
            nil, playSound)
        acceptDD:SetPoint("TOPLEFT", acceptCheck, "BOTTOMLEFT", 0, -8)

        -- Its own switch and its own sound, like the accept pair above. This one fires at the
        -- quest giver, which is where the Quest Complete sound was landing on Classic by
        -- accident.
        local turnInCheck = self:CreateCheckbox(content,
            L["Play a sound when you turn a quest in"],
            function() return DB().questTurnInSoundEnabled == true end,
            function(v) DB().questTurnInSoundEnabled = v end,
            L["Off by default. It has its own sound below, so handing a quest in and finishing its objectives can be told apart."])
        turnInCheck:SetPoint("TOPLEFT", acceptDD, "BOTTOMLEFT", 0, -8)

        local turnInDD = self:CreateDropdown(content, L["Quest Turned In Sound"],
            soundList,
            function() return DB().questTurnInSound or "NONE" end,
            function(v) DB().questTurnInSound = v; playSound(v) end,
            L["Which sound plays when you hand a quest in at the quest giver."],
            nil, playSound)
        turnInDD:SetPoint("TOPLEFT", turnInCheck, "BOTTOMLEFT", 0, -8)

        -- The zone progress bar's two toggles used to sit here, with its nine styling
        -- controls on the Appearance tab. They live together under Appearance's Zone
        -- Progress Bar heading now - one feature, one place.

        -- Whether the provider registered, which the TOC already decides per flavor. ns.Has
        -- is a CAPABILITY probe and reads true on Classic, where the client keeps the
        -- functions and ships no scenarios behind them.
        if ns.Has.ScenarioBonus and Registry:Get("scenarios") then
            local sbHeader = self:CreateHeading(content, L["Scenario Bonus Objectives"])
            sbHeader:SetPoint("TOPLEFT", turnInDD, "BOTTOMLEFT", 0, self.GAP.aboveHead)

            local sbEnable = self:CreateCheckbox(content, L["Show bonus objectives HUD"],
                function()
                    local st = DB().scenarioBonusHUD
                    return st and st.enabled
                end,
                function(v) ns:GetModule("ScenarioBonusHUD"):SetEnabled(v) end,
                L["Shows a small movable checklist of the extra bonus objectives that appear during some scenarios and delves, so you do not miss their rewards. Drag to move, right-click to lock or reset. Off by default."])
            sbEnable:SetPoint("TOPLEFT", sbHeader, "BOTTOMLEFT", 0, self.GAP.head)

            -- The HUD only draws inside a scenario or delve, so without this the position
            -- and scale below can only be set somewhere the player cannot see the result.
            local sbTest = self:CreateButton(content, L["Test"], 120, function()
                ns:GetModule("ScenarioBonusHUD"):ToggleTest()
            end, L["Draws the HUD with two made-up bonus objectives so you can position and size it without being in a scenario or delve. Click again to clear it."])
            sbTest:SetSize(120, 22)
            sbTest:SetPoint("TOPLEFT", sbEnable, "BOTTOMLEFT", 0, -10)

            local sbScale = self:CreateSlider(content, L["HUD Scale"], 0.5, 2.0, 0.05,
                function()
                    local st = DB().scenarioBonusHUD
                    return (st and st.scale) or 1.0
                end,
                function(v) ns:GetModule("ScenarioBonusHUD"):SetScale(v) end,
                L["Sizes the bonus objectives HUD."])
            sbScale:SetPoint("TOPLEFT", sbTest, "BOTTOMLEFT", 0, -16)
        end
    end,

    refresh = function(_, content)
        if content._syncDiff then content._syncDiff() end
    end,
})
