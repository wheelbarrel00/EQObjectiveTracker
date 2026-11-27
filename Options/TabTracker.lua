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
    { value = "progress", label = L["Progress"],
      tip = L["Furthest along first, by how much of each objective is done. Ties go in alphabetical order."] },
    { value = "type",     label = L["Type"],
      tip = L["Weekly first, then daily, then everything else. Only quests carry a type, so other sections fall back to alphabetical."] },
    { value = "level",    label = L["Level"],
      tip = L["Lowest quest level first."] },
    { value = "distance", label = L["Distance"],
      tip = ns.Has.QuestDistance
          and L["Nearest objective first, updated as you move. A quest ready to turn in measures to its turn-in point."]
          or L["Nearest objective first, updated as you move. A quest ready to turn in measures to its turn-in point. On this version of the game, this order needs Everything Quests installed."] },
    { value = "recent",   label = L["Recent"],
      tip = L["Most recently accepted first."] },
    { value = "manual",   label = L["Manual"],
      tip = L["Your own order. Drag quests up and down in the tracker to set it."] },
}
-- The tracker's sort button offers this same list.
Options.SORT_OPTIONS = SORT_OPTIONS

-- EQ's own screen order, which is not Filter.CATEGORIES order - that one encodes match
-- precedence and must not be reshuffled for display.
local FILTER_ORDER = {
    "showNormal", "showDaily", "showWeekly", "showScheduled", "showCampaign", "showWorld",
    "showBonus",
}
-- The tracker's filter button offers the same rows in the same order.
Options.FILTER_ORDER = FILTER_ORDER

-- Most of these say what they are in the label. Scheduled is the one nothing in the game
-- names out loud, so the generic line below leaves the player guessing.
local FILTER_TIPS = {
    showScheduled = L["Quests the game resets on its own schedule rather than daily or weekly. Special Assignments and some meta quests are what you will see here."],
    showInstance = L["Shows your dungeon, raid and delve quests, as long as their type's box is ticked too. A pinned quest always shows."],
    showOutsideInstance = L["Shows your other quests, as long as their type's box is ticked too. Untick it to see only your dungeon, raid and delve quests. A pinned quest always shows."],
    showUnfinished = L["Shows the quests you are still working on. A pinned quest always shows. While To-Do Mode is on, this box is set aside and the quest sections follow its picked count."],
    showFinished = L["Shows the quests ready to turn in. A pinned quest always shows. While To-Do Mode is on, this box is set aside and the quest sections follow its picked count."],
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

local ARROW_SIZE = 24
local ARROW_GAP  = 4

local function DB() return ns:GetModule("DB"):Tracker() end
local function render() ns:GetModule("Tracker"):Render() end

local function trackerSetting(key)
    return function() return DB()[key] end,
           function(v) DB()[key] = v; render() end
end

-- Row memoizes on the fields in its repaint gate and returns early when they all match, so
-- anything that changes how a row READS without moving a gate field has to invalidate or it
-- silently never repaints.
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

-- The Filters card's Reset button and the tracker's filter button both reset through this.
-- Walked rather than listed, so a category added to Filter.CATEGORIES is reset without anyone
-- remembering to come back for it.
function Options:ResetFilters()
    local f = DB().filters
    local Filter = ns:GetModule("Filter")
    for _, run in ipairs({ Filter.CATEGORIES, Filter.PLACE, Filter.PROGRESS }) do
        for i = 1, #run do f[run[i].key] = true end
    end
    f.onlyCurrentZone = false
    f.campaignAnyZone = false
    ns:GetModule("Filter"):ShowAllZones()
end

-- Each To-Do count's box and color, in the order the header draws them.
local TODO_COUNTS = {
    { show = "todoShowUnfinished", color = "todoColorUnfinished", label = L["Unfinished here"] },
    { show = "todoShowReady",      color = "todoColorReady",      label = L["Ready to turn in here"] },
    { show = "todoShowHere",       color = "todoColorHere",       label = L["All here"] },
    { show = "todoShowAll",        color = "todoColorAll",        label = L["All quests"] },
}

-- Its own function so the tab's build closes over one name, not every control on the card. It dims
-- its rows while the mode is off, and the current-zone box and the progress pair while it is on, since
-- the mode decides those.
local function buildTodoCard(ui, content, above, zoneOnly, progressBoxes)
    local gap  = ui:Spacing("groupGap")
    local card = ui:CreateGroup(content, L["To-Do Mode"])
    card:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -gap)
    card:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT", 0, -gap)

    local rows = {}
    local function sync()
        local on = DB().todoMode == true
        for _, r in ipairs(rows) do ui:SetDependent(r, on) end
        ui:SetDependent(zoneOnly, not on)
        for _, b in ipairs(progressBoxes or {}) do ui:SetDependent(b, not on) end
    end

    card:Add(ui:CreateCheckbox(content, L["Turn on To-Do Mode"],
        function() return DB().todoMode == true end,
        function(v) DB().todoMode = v; sync(); render() end,
        L["Turns the quest headers into four counts: your unfinished quests in this zone, the ones ready to turn in here, every quest here and every quest you have. Click a count to show only those quests. It starts on the unfinished ones."]))

    for _, c in ipairs(TODO_COUNTS) do
        local box = ui:CreateCheckbox(content, c.label,
            function() return DB()[c.show] ~= false end,
            function(v) DB()[c.show] = v; render() end,
            L["Shows this count on the quest headers."])
        local row = card:Add(box, { dependent = true })
        local picker = ui:CreateColorPicker(content, L["Color"],
            function() return DB()[c.color] end,
            function(v) DB()[c.color] = v; render() end,
            L["Color of this count on the quest headers."], nil, nil, true)
        picker:SetPoint("RIGHT", row, "RIGHT", -ui:Spacing("rowPadding"), 0)
        rows[#rows + 1] = box
        rows[#rows + 1] = picker
    end

    local size = ui:CreateSlider(content, L["Count Size Offset"], -4, 8, 1,
        function() return tonumber(DB().todoCountSizeDelta) or 0 end,
        function(v) DB().todoCountSizeDelta = v; render() end,
        L["Sizes the counts on the quest headers. 0 keeps them the size the header count has today."])
    card:Add(size, { dependent = true })
    rows[#rows + 1] = size

    local names = ui:CreateCheckbox(content, L["Show section names"],
        function() return DB().todoShowNames ~= false end,
        function(v) DB().todoShowNames = v; render() end,
        L["Shows the names Quests and Campaign on the quest headers. Untick it to keep only the counts. To make the names smaller instead, use Header Size Offset on the Appearance tab, which the button beside this box opens. The counts follow it, and Count Size Offset sizes them back."])
    local namesRow = card:Add(names, { dependent = true })
    local jump = ui:CreateButton(content, L["Header Size Offset"], nil, function() Options:ShowHeaderSize() end)
    jump:SetPoint("RIGHT", namesRow, "RIGHT", -ui:Spacing("rowPadding"), 0)
    rows[#rows + 1] = names
    rows[#rows + 1] = jump

    sync()
    content._syncTodo = sync
    return card
end

local COMPACT_PARTS = {
    { key = "compactTags", label = L["Short quest tags"],
      tip = L["Shows a quest's level and type as one short tag in front of its title, such as [60g3!]: g group, with its size, d dungeon, hc heroic, r raid, r10 and r25 its size, de delve, s scenario, pvp player versus player, + elite, ! daily, !! weekly. The type shows even with Show quest type tags off, and the level only while Show quest level prefix is on."] },
    { key = "compactFinished", label = L["Short finished line"],
      tip = L["A finished quest shows Ready for turn-in under its title in place of where to hand it in or its objectives, minimized or not."] },
    { key = "compactOneLine", label = L["One line per text"],
      tip = L["Long quest titles and objectives stay on one line and end in ... instead of wrapping. Hover a quest to read its whole title."] },
}

-- Its own function for the same reason as the To-Do card's. Wrapping is in no gate field, so every
-- change draws the rows again from scratch.
local function buildCompactCard(ui, content, above)
    local gap  = ui:Spacing("groupGap")
    local card = ui:CreateGroup(content, L["Compact Mode"])
    card:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -gap)
    card:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT", 0, -gap)

    local rows = {}
    local function sync()
        local on = DB().compactMode == true
        for _, r in ipairs(rows) do ui:SetDependent(r, on) end
    end
    local function redraw()
        ns:GetModule("Row"):Invalidate()
        render()
    end

    card:Add(ui:CreateCheckbox(content, L["Turn on Compact Mode"],
        function() return DB().compactMode == true end,
        function(v) DB().compactMode = v; sync(); redraw() end,
        L["Makes the tracker take less room: a short tag in front of quest titles, a short line for finished quests and one line for each title and objective. Choose which below. Nothing changes while this is off."]))
    for _, part in ipairs(COMPACT_PARTS) do
        local box = ui:CreateCheckbox(content, part.label,
            function() return DB()[part.key] ~= false end,
            function(v) DB()[part.key] = v; redraw() end,
            part.tip)
        card:Add(box, { dependent = true })
        rows[#rows + 1] = box
    end

    sync()
    return card
end

local function sectionLabel(id)
    return ns:GetModule("Sections"):Title(id)
end

-- The library's chevron, flipped for up. The tooltip is hand-rolled rather than going through
-- AttachTooltip because EQ titles this one white, not gold.
local function makeOrderArrow(ui, parent, isUp)
    local b = ui:CreateIconButton(parent, "chevron-down", ARROW_SIZE, isUp)
    b:HookScript("OnEnter", function(self)
        local name = (self.sectionID and sectionLabel(self.sectionID)) or ""
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

local function nextTab(id)
    local cfg = DB()
    cfg.sectionTab = cfg.sectionTab or {}
    local Tracker = ns:GetModule("Tracker")
    local t = Tracker:SectionTab(id) % Tracker.MAX_TABS + 1
    -- Tab 1 is stored as nothing, so the map only ever holds the sections that were moved.
    cfg.sectionTab[id] = (t ~= 1) and t or nil
end

-- A row can name a different section after a move, so the click reads the section off the button.
local function makeTabButton(ui, parent, onMoved)
    local b = ui:CreateButton(parent, "1", ARROW_SIZE, function(btn)
        if not btn.sectionID then return end
        nextTab(btn.sectionID)
        onMoved()
    end)
    b:SetHeight(ARROW_SIZE)
    b:HookScript("OnEnter", function(self)
        local tip = ns.Util.Tooltip()
        tip:SetOwner(self, "ANCHOR_RIGHT")
        -- SetText arg 5 is alpha, not wrap. Pass 1 or the line renders invisible.
        tip:SetText(self.sectionID and sectionLabel(self.sectionID) or "", 1, 1, 1, 1, true)
        tip:AddLine(L["Which tab this section sits on. Click to move it to the next tab."], 0.82, 0.82, 0.82, true)
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
        local gap      = self:Spacing("groupGap")

        local onScreen = self:CreateGroup(content, L["On-Screen Tracker"])
        onScreen:SetPoint("TOPLEFT")
        onScreen:SetPoint("TOPRIGHT")
        self:AttachTooltip(onScreen.label, L["On-Screen Tracker"],
            L["Changes apply immediately to the on-screen tracker."])

        local watchedGet, watchedSet = trackerSetting("showOnlyWatched")
        onScreen:Add(self:CreateCheckbox(content, L["Show only tracked quests"],
            watchedGet, watchedSet,
            L["Hides quests that are in your log but not tracked. Matches Blizzard's default tracker."]))

        local simplifyGet, simplifySet = trackerSetting("simplifyMode")
        local simplify = self:CreateCheckbox(content, L["Simplify Mode"], simplifyGet,
            function(v)
                simplifySet(v)
                content._syncHideFinished()
            end)
        onScreen:Add(simplify)
        self:AttachTooltip(simplify, L["Simplify Mode"],
            L["Show only the first incomplete objective per quest."])

        local hideGet, hideSet = trackerSetting("hideFinishedObjectives")
        local hideFinished = self:CreateCheckbox(content, L["Hide finished objectives"], hideGet, hideSet,
            L["Hides objectives you have already finished and keeps every one still left to do. A quest with all of them finished keeps its last one. Simplify Mode shows only the first one left, so this box is dimmed while Simplify Mode is on."])
        onScreen:Add(hideFinished)
        content._syncHideFinished = function() self:SetDependent(hideFinished, not DB().simplifyMode) end
        content._syncHideFinished()

        local autoGet, autoSet = trackerSetting("autoMinimizeFinished")
        onScreen:Add(self:CreateCheckbox(content, L["Auto minimize finished quests"], autoGet, autoSet,
            L["Folds every finished quest to its title and (Complete). Open one with its + or the right-click menu and it stays open. A quest you can hand in by clicking it stays open, so its line saying so still shows."]))

        -- On by default, so an unset key reads ticked.
        onScreen:Add(self:CreateCheckbox(content, L["Show hand-in text on finished quests"],
            function() return DB().showHandInText ~= false end,
            function(v) DB().showHandInText = v; render() end,
            L["A quest ready to turn in shows one line in place of its finished objectives, saying where to hand it in when the game says, or that it is ready for turn-in. A failed quest shows that it failed. On by default. Compact Mode's short finished line shows Ready for turn-in even with this box off."]))

        onScreen:Add(self:CreateCheckbox(content, L["Simplify tracked achievements"],
            function() return DB().simplifyGroups and DB().simplifyGroups.achievements end,
            function(v)
                DB().simplifyGroups = DB().simplifyGroups or {}
                DB().simplifyGroups.achievements = v
                render()
            end,
            L["Show only incomplete criteria for tracked achievements."]))

        local manualHint
        local function syncManualHint(value)
            manualHint:SetShown(value == "manual")
            onScreen:Layout()
            -- Showing the hint moves every card under it, and the scroll range is otherwise
            -- only measured on a tab switch.
            self:MeasureContent(content)
        end

        -- Nine choices, so the library draws this as a dropdown with each choice's tip on its row.
        onScreen:Add(self:CreateRadioGroup(content, L["Sort Order"],
            SORT_OPTIONS,
            function() return DB().sortMode or "zone" end,
            function(v)
                -- A reverse belongs to the order it was picked on, as on the sort button
                if DB().sortMode ~= v then DB().sortReverse = false end
                DB().sortMode = v
                render()
                syncManualHint(v)
            end))

        manualHint = self:CreateText(content,
            L["Drag and drop the quests in the tracker to reorder them however you like."], "hint")
        onScreen:Add(manualHint, { dependent = true, fill = true })
        syncManualHint(DB().sortMode)
        -- The tracker's sort button can change the order after this tab is built.
        content._syncManualHint = function() syncManualHint(DB().sortMode) end

        local filters = self:CreateGroup(content, L["Filters"])
        filters:SetPoint("TOPLEFT", onScreen, "BOTTOMLEFT", 0, -gap)
        filters:SetPoint("TOPRIGHT", onScreen, "BOTTOMRIGHT", 0, -gap)

        local byKey = {}
        for i = 1, #Filter.CATEGORIES do
            byKey[Filter.CATEGORIES[i].key] = Filter.CATEGORIES[i]
        end

        local filterBoxes = {}
        for _, key in ipairs(FILTER_ORDER) do
            local c = byKey[key]
            -- No loaded provider can produce this category, so the toggle would be dead
            if c and ((not c.tag) or Registry:HasTag(c.tag)) then
                local get, set = filterSetting(key)
                -- Not interpolated with the label: every label already ends in a noun, so
                -- the old form read "Show or hide world quests entries in the tracker."
                local cb = self:CreateCheckbox(content, c.label, get, set,
                    FILTER_TIPS[key] or L["Show or hide this category of entry in the tracker."])
                filters:Add(cb)
                filterBoxes[#filterBoxes + 1] = { key = key, cb = cb }
            end
        end

        -- The two pairs ANDed with the types. In filterBoxes so Reset re-ticks them.
        local progressBoxes = {}
        local function pairBox(c, list)
            local get, set = filterSetting(c.key)
            local cb = self:CreateCheckbox(content, c.label, get, set, FILTER_TIPS[c.key])
            filters:Add(cb)
            filterBoxes[#filterBoxes + 1] = { key = c.key, cb = cb }
            if list then list[#list + 1] = cb end
        end
        if Filter:OffersPlace(Registry) then
            for _, c in ipairs(Filter.PLACE) do pairBox(c) end
        end
        for _, c in ipairs(Filter.PROGRESS) do pairBox(c, progressBoxes) end

        local zoneOnly = self:CreateCheckbox(content, L["Show only quests in current zone"],
            function() return DB().filters.onlyCurrentZone end,
            function(v) DB().filters.onlyCurrentZone = v; render() end,
            L["Only show entries with an objective on your current map. Entries whose provider cannot tell are always shown. While To-Do Mode is on, its picked count decides this instead."])
        filters:Add(zoneOnly)

        -- Gated like the category run above. Classic has no campaigns, so it could never act.
        local campaignZone
        if Registry:HasTag("campaign") then
            campaignZone = self:CreateCheckbox(content, L["Always show campaign quests"],
                function() return DB().filters.campaignAnyZone end,
                function(v) DB().filters.campaignAnyZone = v; render() end,
                L["Campaign quests from every zone stay on the tracker, even while Show only quests in current zone is on. In To-Do Mode they also show, and count, in the views for your zone."])
            filters:Add(campaignZone)
        end

        filters:Add(self:CreateButton(content, L["Hide zones"], nil,
            function(button) ns:GetModule("Tracker"):OpenZoneMenu(button) end,
            L["Opens a list of the zones in your quest log. Untick a zone to hide its quests from the tracker, and tick it again to bring them back. A pinned quest always shows. A zone stays hidden until you tick it again or its last quest leaves your log."]))

        -- Deliberately does NOT touch showOnlyWatched. That box sits under a different
        -- heading and is the most impactful setting on the tab, so silently turning it back
        -- on here hid quests with nothing connecting the two.
        local resetFilters = self:CreateButton(content, L["Reset filters to defaults"], nil,
            function()
                Options:ResetFilters()
                local f = DB().filters
                -- Re-checked in place rather than by reloading the tab: these boxes only
                -- read their getter on build and on a tab view.
                zoneOnly:SetChecked(false)
                if campaignZone then campaignZone:SetChecked(false) end
                for _, e in ipairs(filterBoxes) do
                    e.cb:SetChecked(f[e.key] ~= false)
                end
                render()
            end,
            -- Without the campaign box the tooltip must not name it.
            campaignZone
                and L["Turns every category filter back on, along with the four boxes under them, clears the current-zone filter, turns off Always show campaign quests and shows every zone again. Nothing else on this tab is changed."]
                or L["Turns every category filter back on, along with the four boxes under them, clears the current-zone filter and shows every zone again. Nothing else on this tab is changed."])
        -- The last row of the card, after whichever filter ends the run.
        filters:Add(resetFilters)

        local todoCard = buildTodoCard(self, content, filters, zoneOnly, progressBoxes)
        local compactCard = buildCompactCard(self, content, todoCard)

        local visibility = self:CreateGroup(content, L["Tracker Visibility"])
        visibility:SetPoint("TOPLEFT", compactCard, "BOTTOMLEFT", 0, -gap)
        visibility:SetPoint("TOPRIGHT", compactCard, "BOTTOMRIGHT", 0, -gap)

        -- Gated like the filter run above it: a section its TOC never loaded must not get a
        -- toggle that can never do anything.
        local liveSections = {}
        for _, id in ipairs(Sections:Known()) do liveSections[id] = true end

        for _, row in ipairs(VISIBILITY_ROWS) do
            local id = row.id
            if liveSections[id] then
                -- The box SHOWS the section, so the tooltip has to describe unchecking it.
                visibility:Add(self:CreateCheckbox(content, row.label,
                    function() return not Sections:IsHidden(id) end,
                    function(v)
                        Sections:SetHidden(id, not v)
                        render()
                        if content._renderOrderRows then content._renderOrderRows() end
                    end,
                    L["Uncheck to hide this section from the tracker even while it has entries."]))
            end
        end

        -- No loaded provider can produce a world quest, so the whole block would sit there
        -- with nothing behind it. The region itself still exists at 1px on such a flavor,
        -- which is exactly why the controls read as live when they are not.
        local hasWorldQuests = Registry:HasTag("worldquest")

        if hasWorldQuests then
            local autoWQ = self:CreateCheckbox(content, L["Auto-list current-zone world quests"],
                trackerSetting("autoListZoneWorldQuests"))
            visibility:Add(autoWQ)
            self:AttachTooltip(autoWQ, L["Auto-list current-zone world quests"],
                L["Lists every WQ in your zone without tracking each."])

            -- The two sliders are mutually exclusive - UI/Tracker.lua reads the fixed height or
            -- the fraction, never both, and neither while World Quests are drawn alone - so the
            -- dead one has to say so.
            local wqHeightSlider, wqMaxSlider
            local function setWqHeightEnabled(on)
                self:SetDependent(wqHeightSlider, on)
                self:SetDependent(wqMaxSlider, not on)
            end

            visibility:Add(self:CreateCheckbox(content, L["Set a custom World Quests height"],
                function() return DB().worldQuestsHeightOverride end,
                function(v)
                    DB().worldQuestsHeightOverride = v
                    setWqHeightEnabled(v)
                    render()
                end,
                L["By default the World Quests area is capped to a share of the tracker, set by the slider below that. Turn this on to give it a fixed height in pixels instead."]))

            wqHeightSlider = self:CreateSlider(content, L["World Quests Height"], 40, 400, 10,
                function() return DB().worldQuestsHeight or 200 end,
                function(v) DB().worldQuestsHeight = v; render() end,
                L["Height in pixels for the world quest area. Only used while Set a custom World Quests height is on. When world quests are the only thing on the tracker, or on their tab, they use all of its height."])
            visibility:Add(wqHeightSlider, { dependent = true })

            -- EQOT-only: EQ caps the world quest area by fixed height alone. Kept because it
            -- is backed by real tracker code, and placed with the other height controls.
            wqMaxSlider = self:CreateSlider(content, L["Maximum Height (percent of tracker)"], 10, 80, 5,
                function() return (DB().worldQuestsPinnedMaxFraction or 0.40) * 100 end,
                function(v)
                    DB().worldQuestsPinnedMaxFraction = v / 100
                    render()
                end,
                L["The most of the tracker the world quest area may take. It is capped here first and your quest list takes the space that is left, scrolling for whatever does not fit. Only used while Set a custom World Quests height is off. When world quests are the only thing on the tracker, or on their tab, they use all of its height."])
            visibility:Add(wqMaxSlider, { dependent = true })
            setWqHeightEnabled(DB().worldQuestsHeightOverride)
        end

        local order = self:CreateGroup(content, L["Section Order"])
        order:SetPoint("TOPLEFT", visibility, "BOTTOMLEFT", 0, -gap)
        order:SetPoint("TOPRIGHT", visibility, "BOTTOMRIGHT", 0, -gap)
        self:AttachTooltip(order.label, L["Section Order"],
            L["Rearrange the tracker's sections with the arrows below. A section only appears on the tracker while it has something in it, so reordering an empty section won't look like anything changed. World Quests scroll in their own panel and can only sit at the very top or bottom, so use the Top/Bottom control."])

        local wqPos = self:CreateRadioGroup(content, L["World Quests Position"],
            WQ_POSITIONS,
            function() return DB().worldQuestsPosition or "bottom" end,
            function(v) ns:GetModule("Tracker"):SetWorldQuestsPosition(v) end,
            nil, nil,
            L["World Quests Position"],
            L["Where the World Quests panel sits on the tracker. |cffffffffTop|r puts it above your quests. |cffffffffBottom|r keeps it below your quests, which is the default. World Quests scroll in their own capped panel, which is why they can't be mixed in between the other sections."])
        if not hasWorldQuests then wqPos:Hide() end
        local wqRow = order:Add(wqPos)

        local tabsOffered = ns:GetModule("Tracker"):TabsOffered()

        local renderOrderRows
        if tabsOffered then
            local tabsBox = self:CreateCheckbox(content, L["Show section tabs"],
                function() return DB().showTabs == true end,
                function(v)
                    DB().showTabs = v
                    render()
                    renderOrderRows()
                end,
                L["Splits the tracker into up to three tabs. Use the number beside each section below to choose its tab, then click a tab at the top of the tracker to show only the sections on it. The scenario panel shows on every tab, and the tabs appear once two of them hold a section."])
            order:Add(tabsBox)
        end

        local function tabMoved()
            render()
            renderOrderRows()
        end

        -- World Quests sit in their own panel rather than in the order, so their tab is chosen here.
        local wqTab = makeTabButton(self, content, tabMoved)
        wqTab:SetPoint("RIGHT", wqRow, "RIGHT", -self:Spacing("rowPadding"), 0)
        wqTab.sectionID = "worldquests"

        -- One row per place in the order, built the first time the list needs it and relabeled on
        -- every move, so a row keeps its place in the card while the section named on it changes.
        local orderRows = {}
        renderOrderRows = function()
            local tabsOn = tabsOffered and DB().showTabs == true
            local Tracker = ns:GetModule("Tracker")
            wqTab:SetShown(tabsOn and hasWorldQuests)
            wqTab:SetText(Tracker:SectionTab("worldquests"))
            -- Dimmed where the section makes no tab (hidden, or the zone bar unless docked), as a
            -- setting that is not in effect is dimmed. The move is still kept for when it is.
            self:SetDependent(wqTab, Tracker:DrawsOnTab("worldquests"))
            local list = Sections:Order()
            for i, id in ipairs(list) do
                local r = orderRows[i]
                if not r then
                    r = { name = self:CreateText(content, "") }
                    local row = order:Add(r.name)
                    r.down = makeOrderArrow(self, content, false)
                    r.down:SetPoint("RIGHT", row, "RIGHT", -self:Spacing("rowPadding"), 0)
                    r.up = makeOrderArrow(self, content, true)
                    r.up:SetPoint("RIGHT", r.down, "LEFT", -ARROW_GAP, 0)
                    r.tab = makeTabButton(self, content, tabMoved)
                    r.tab:SetPoint("RIGHT", r.up, "LEFT", -ARROW_GAP, 0)
                    orderRows[i] = r
                end
                r.name:SetText(sectionLabel(id))
                r.name:Show()
                r.up:Show()
                r.down:Show()
                r.tab.sectionID = id
                r.tab:SetText(Tracker:SectionTab(id))
                r.tab:SetShown(tabsOn)
                self:SetDependent(r.tab, Tracker:DrawsOnTab(id))
                r.up.sectionID, r.down.sectionID = id, id
                r.up:SetEnabled(i > 1)
                r.down:SetEnabled(i < #list)
                -- The list reorders under a stationary cursor, so a tooltip left up would
                -- keep naming the section that used to be on this row.
                r.up:SetScript("OnClick", function()
                    Sections:Move(id, -1)
                    render()
                    renderOrderRows()
                    ns.Util.Tooltip():Hide()
                end)
                r.down:SetScript("OnClick", function()
                    Sections:Move(id, 1)
                    render()
                    renderOrderRows()
                    ns.Util.Tooltip():Hide()
                end)
            end
            for i = #list + 1, #orderRows do
                orderRows[i].name:Hide()
                orderRows[i].up:Hide()
                orderRows[i].down:Hide()
                orderRows[i].tab:Hide()
            end
            order:Layout()
        end
        renderOrderRows()
        -- Read again on each visit too, since the zone bar is docked from the Appearance tab.
        content._renderOrderRows = renderOrderRows

        local questRows = self:CreateGroup(content, L["Quest Row Details"])
        questRows:SetPoint("TOPLEFT", order, "BOTTOMLEFT", 0, -gap)
        questRows:SetPoint("TOPRIGHT", order, "BOTTOMRIGHT", 0, -gap)

        -- The quest provider fills the elite + on Forever, Era and TBC only.
        local questsProvider = Registry:Get("quests")
        local typed = questsProvider and questsProvider.HasTypeTags and questsProvider:HasTypeTags()
        local lvl = self:CreateCheckbox(content, L["Show quest level prefix"],
            rowSetting("showLevelInTracker"))
        questRows:Add(lvl)
        self:AttachTooltip(lvl, L["Show quest level prefix"], typed
            and L["For example, [60] Title, or [60+] for an elite or group quest. With Compact Mode's short tags on, the level and the type share one tag in front of the title."]
            or L["For example, [60] Title. With Compact Mode's short tags on, the level and the type share one tag in front of the title."])

        if questsProvider and questsProvider.TypeTagsDefault then
            local _, setTypeTag = rowSetting("showQuestTypeTag")
            local typeTag = self:CreateCheckbox(content, L["Show quest type tags"],
                function()
                    local v = DB().showQuestTypeTag
                    if v == nil then return questsProvider:TypeTagsDefault() end
                    return v ~= false
                end, setTypeTag)
            questRows:Add(typeTag)
            self:AttachTooltip(typeTag, L["Show quest type tags"],
                L["Adds the quest's type after its title in your game's own words, such as (Dungeon) or (Daily). A quest with two shows both, such as (Dungeon, Daily). With Compact Mode's short tags on, the type shows as letters in one tag in front of the title, even with this box off."])
        end

        local zoneCheck = self:CreateCheckbox(content, L["Show zone label under quest titles"],
            rowSetting("showZoneTag"))
        questRows:Add(zoneCheck)
        self:AttachTooltip(zoneCheck, L["Show zone label under quest titles"],
            L["Adds the quest log heading each quest came from as a small line under its title. While Show zone headers is on, on the Appearance tab, only quests in the Dungeons header show it."])
        -- Its masters are on another tab, so its dimming is set again each time this tab is shown.
        content._syncZoneTag = function() self:SetDependent(zoneCheck, not DB().zoneHeaders or DB().dungeonHeader == true) end
        content._syncZoneTag()

        local objCheck = self:CreateCheckbox(content, L["Show objective progress numbers"],
            rowSetting("showObjectiveNumbers", true))
        questRows:Add(objCheck)
        self:AttachTooltip(objCheck, L["Show objective progress numbers"],
            L["For example, 0/4, 1/1, etc."])

        -- Show progress bars moved to the Appearance tab's Progress Bars group, so the switch
        -- that turns the bars on is not two tabs away from the controls that style them. Same
        -- move the zone progress bar's own toggles made, for the same reason.

        local qidCheck = self:CreateCheckbox(content, L["Show quest ID"],
            rowSetting("showQuestID"))
        questRows:Add(qidCheck)
        self:AttachTooltip(qidCheck, L["Show quest ID"], L["Useful for bug reports."])

        local getXP, setXP = rowSetting("showQuestXP")
        local xpCheck = self:CreateCheckbox(content, L["Show XP after quest titles"], getXP, function(v)
            -- Asked first, so the redraw that follows carries the figures.
            if questsProvider and questsProvider.RefreshXP then questsProvider:RefreshXP() end
            setXP(v)
        end)
        questRows:Add(xpCheck)
        self:AttachTooltip(xpCheck, L["Show XP after quest titles"],
            L["Adds the XP each quest gives after its title, in gray, such as (450 XP). A quest that gives no XP, as every quest does at the level cap, shows nothing. Off by default."])

        local distCheck = self:CreateCheckbox(content, L["Show distance after quest titles"],
            rowSetting("showQuestDistance"))
        questRows:Add(distCheck)
        self:AttachTooltip(distCheck, L["Show distance after quest titles"], ns.Has.QuestDistance
            and L["Adds how far away each quest is after its title, in gray, such as (120 yd), updated as you move. A quest ready to turn in measures to its turn-in point, and a quest with no known place shows nothing. Off by default."]
            or L["Adds how far away each quest is after its title, in gray, such as (120 yd), updated as you move. A quest ready to turn in measures to its turn-in point, and a quest with no known place shows nothing. Off by default. On this version of the game, distances need Everything Quests installed."])

        local itemBtnCheck = self:CreateCheckbox(content, L["Show usable quest item buttons"],
            rowSetting("showItemButtons", true))
        questRows:Add(itemBtnCheck)
        self:AttachTooltip(itemBtnCheck, L["Show usable quest item buttons"],
            L["Puts a button on the tracker row of any quest that carries a usable item, so you can use it without opening your bags."])

        local foldCheck = self:CreateCheckbox(content, L["Show a +/- on each quest"], rowSetting("showFoldButtons"))
        questRows:Add(foldCheck)
        self:AttachTooltip(foldCheck, L["Show a +/- on each quest"],
            L["Puts a - at the end of each quest's title line. Click it to fold the quest to its title, and click the + to open it again. A folded quest always shows its +. Shift-click a zone or section header to fold or open every quest under it."])

        local newTagCheck = self:CreateCheckbox(content,
            L["Show NEW tag on recently accepted quests"],
            rowSetting("showRecentlyAddedTag", true))
        questRows:Add(newTagCheck)
        self:AttachTooltip(newTagCheck, L["Show NEW tag on recently accepted quests"],
            L["For about an hour after accepting."])

        local textCheck = self:CreateCheckbox(content, L["Show the quest text in its tooltip"],
            trackerSetting("showQuestText"))
        questRows:Add(textCheck)
        self:AttachTooltip(textCheck, L["Show the quest text in its tooltip"],
            L["When you point at a quest, its tooltip also shows the quest log's own text: first the short paragraph saying what to do and who to go back to, then the quest's story in gray. Off by default."])

        local rewardTip = ns:GetModule("RewardTooltip")
        if rewardTip and rewardTip:HooksAvailable() then
            local hooksCheck = self:CreateCheckbox(content, L["Let other addons add to quest tooltips"],
                function() return DB().otherAddonTooltipLines ~= false end,
                function(v) DB().otherAddonTooltipLines = v end)
            questRows:Add(hooksCheck)
            self:AttachTooltip(hooksCheck, L["Let other addons add to quest tooltips"],
                L["Addons that add lines to quest tooltips can add them at the bottom of a quest's tooltip here too. Turn this off if another addon's lines cause trouble. On by default."])
        end

        local headers = self:CreateGroup(content, L["Headers and Buttons"])
        headers:SetPoint("TOPLEFT", questRows, "BOTTOMLEFT", 0, -gap)
        headers:SetPoint("TOPRIGHT", questRows, "BOTTOMRIGHT", 0, -gap)

        -- UI/Tracker.lua reads showQuestTotal for every ordinary section and for the pinned
        -- world quest region, not just Quests and Campaign, and UI/ZoneHeaders.lua for every zone
        -- header. The pair drawn is visible/total rather than tracked/total.
        headers:Add(self:CreateCheckbox(content,
            L["Show the visible / total count on section headers"],
            function() return DB().showQuestTotal ~= false end,
            function(v) DB().showQuestTotal = v; render() end,
            L["For example, 3/9. Applies to every section header and zone header, except the Quests and Campaign headers while To-Do Mode is on."]))

        headers:Add(self:CreateCheckbox(content, L["Keep section headers in view while scrolling"],
            function() return DB().stickySectionHeaders ~= false end,
            function(v)
                DB().stickySectionHeaders = v
                ns:GetModule("Tracker"):ApplyWorldQuestsPosition()
                render()
            end,
            L["The header of the section you are scrolled into stays at the top of the quest list, so you can always see which section you are in. With zone headers on, the header of the zone you are scrolled into stays just under it. On by default."]))

        -- Named after the cogwheel itself: as "Options icon" two players, the author among them,
        -- went looking for a way to hide it and never found this box.
        headers:Add(self:CreateCheckbox(content, L["Show the options cogwheel on the tracker"],
            function() return DB().showOptionsIcon ~= false end,
            function(v)
                DB().showOptionsIcon = v
                ns:GetModule("Tracker"):ApplyHeaderIcons()
            end,
            L["A small cogwheel at the right end of the tracker's button bar that opens the options panel."]))

        headers:Add(self:CreateCheckbox(content, L["Show the sort button on the tracker"],
            function() return DB().showSortButton == true end,
            function(v)
                DB().showSortButton = v
                -- Only the button shows a reverse or turns one on, so hiding it ends one
                if not v and DB().sortReverse then
                    DB().sortReverse = false
                    render()
                end
                ns:GetModule("Tracker"):ApplyHeaderIcons()
            end,
            L["A small button at the left end of the tracker's button bar that opens a list of the sort orders, so you can switch between them in two clicks. It changes the same Sort Order as the On-Screen Tracker card. Off by default."]))

        headers:Add(self:CreateCheckbox(content, L["Show the filter button on the tracker"],
            function() return DB().showFilterButton == true end,
            function(v)
                DB().showFilterButton = v
                ns:GetModule("Tracker"):ApplyHeaderIcons()
            end,
            L["A small funnel at the left end of the tracker's button bar that opens a list of the filters, so you can turn quest types, the current-zone filter and the zones in your quest log on and off in a couple of clicks. The list stays open while you check boxes, and the funnel turns gold while any filter in it is set to hide quests. It changes the same filters as the Filters card. Off by default."]))

        headers:Add(self:CreateCheckbox(content, L["Show the quest log count on the tracker"],
            function() return DB().showLogCount == true end,
            function(v)
                DB().showLogCount = v
                ns:GetModule("Tracker"):ApplyHeaderIcons()
            end,
            L["Shows how many quests are in your quest log and how many it can hold, such as 14/25, at the left end of the tracker's button bar. It turns red when your log is full. Off by default."]))

        headers:Add(self:CreateCheckbox(content, L["Show the button bar at the bottom of the tracker"],
            function() return DB().buttonBarBottom == true end,
            function(v)
                DB().buttonBarBottom = v
                ns:GetModule("Tracker"):ApplyButtonBar()
            end,
            L["Moves the bar along the top of the tracker, the one you drag it by, with the cogwheel and the other buttons on it, to the bottom edge beside the corner grip. The quests then start at the very top, so the tracker can sit flush against the top of the screen. Off by default."]))

        headers:Add(self:CreateCheckbox(content, L["Show the buttons only on mouseover"],
            function() return DB().buttonsOnMouseover == true end,
            function(v)
                DB().buttonsOnMouseover = v
                ns:GetModule("Tracker"):ApplyHeaderIcons()
            end,
            L["Hides the cogwheel, the sort and filter buttons, the quest log count and any buttons other addons add to the tracker until you point at the bar they sit on, at the top or the bottom of the tracker. Off by default."]))
        headers:Add(self:CreateSlider(content, L["Button Size"], 10, 24, 1,
            function() return ns:GetModule("Tracker"):ButtonSize(DB()) end,
            function(v)
                DB().buttonSize = v
                ns:GetModule("Tracker"):ApplyButtonBar()
            end,
            L["How big the cogwheel, the sort and filter buttons and any buttons other addons add to the tracker's button bar are. The bar is sized to fit them, and the quest log count's text grows with larger buttons. 13 is the default."]))
        -- EQ's Show Chain Guide icon is deliberately not ported: it opens EQ's Chain Guide, which
        -- EQOT does not have.

        local clicking = self:CreateGroup(content, L["Clicking and Focus"])
        clicking:SetPoint("TOPLEFT", headers, "BOTTOMLEFT", 0, -gap)
        clicking:SetPoint("TOPRIGHT", headers, "BOTTOMRIGHT", 0, -gap)

        local splitCheck = self:CreateCheckbox(content, L["Split quest click"],
            trackerSetting("splitQuestClick"))
        clicking:Add(splitCheck)
        self:AttachTooltip(splitCheck, L["Split quest click"],
            L["Click the icon to focus, click the title to open the quest log. Click the title again to close it. A finished quest that can be handed in from the tracker is handed in from its title."])

        -- Classic already toggles its focus on every click, and its game never focuses a quest on its own.
        if ns.Has.SuperTrack then
            clicking:Add(self:CreateCheckbox(content, L["Click a focused quest to unfocus it"],
                function() return DB().clickToUnfocus == true end,
                function(v) DB().clickToUnfocus = v end,
                L["Click the focused quest again to unfocus it. With Split quest click on, click its icon."]))
            clicking:Add(self:CreateCheckbox(content, L["Focus newly accepted quests"],
                function() return DB().focusAcceptedQuests ~= false end,
                function(v) DB().focusAcceptedQuests = v end,
                L["While nothing is focused, the game focuses each quest you accept. Turn this off to leave new quests unfocused."]))
        end

        local scenarios = self:CreateGroup(content, L["Scenarios and Popups"])
        scenarios:SetPoint("TOPLEFT", clicking, "BOTTOMLEFT", 0, -gap)
        scenarios:SetPoint("TOPRIGHT", clicking, "BOTTOMRIGHT", 0, -gap)

        local widgetGet, widgetSet = rowSetting("showTrackerWidgets", true)
        local delveRows = {}
        local function syncDelveRows()
            for _, r in ipairs(delveRows) do self:SetDependent(r, widgetGet()) end
        end
        local widgetCheck = self:CreateCheckbox(content, L["Show event and scenario widgets"],
            widgetGet,
            function(v)
                widgetSet(v)
                syncDelveRows()
            end)
        scenarios:Add(widgetCheck)
        self:AttachTooltip(widgetCheck, L["Show event and scenario widgets"],
            L["Draws the extra bars and status lines the default tracker shows during world events, delves and scenarios, such as an event's progress bar or a delve's tier. This tracker replaces the default one, so without this those are not shown anywhere."])

        -- Both counters draw on the delve's tier row, which is a widget line, so they go with the box
        -- above. Forever has the widget call but no delves, and Blizzard's API docs list it for Era and
        -- TBC too, whose TOCs load no scenario provider.
        if ns.Has.DelveHeader and ns:GetModule("Registry"):Get("scenarios") and not ns.IsForever() then
            -- The reader draws from a snapshot, so a switch has to make it read again.
            local function delveBox(label, key, tooltip)
                return self:CreateCheckbox(content, label,
                    function() return DB()[key] ~= false end,
                    function(v)
                        DB()[key] = v
                        ns:GetModule("Widgets"):Invalidate()
                        render()
                    end,
                    tooltip)
            end
            delveRows[1] = delveBox(L["Show delve lives"], "showDelveLives",
                L["In a delve of Tier 4 or higher, shows the lives left beside the delve's tier. The number turns orange at 2 lives and red at 1."])
            delveRows[2] = delveBox(L["Show nemesis groups"], "showNemesisGroups",
                L["In a delve with a Nemesis Strongbox, shows beside the delve's tier how many groups of the nemesis's minions have been killed, and a check mark once all of them are dead. Hover the icon for the game's own description."])
            for _, r in ipairs(delveRows) do scenarios:Add(r, { dependent = true }) end
            syncDelveRows()
            content._syncDelveRows = syncDelveRows
        end

        -- Only the scenario provider reads a key, and the Classic TOCs do not load it
        if ns.Has.ChallengeTimer and ns:GetModule("Registry"):Get("scenarios") then
            local mplusCheck = self:CreateCheckbox(content, L["Show the Mythic+ timer"],
                rowSetting("showMythicPlusTimer", true))
            scenarios:Add(mplusCheck)
            self:AttachTooltip(mplusCheck, L["Show the Mythic+ timer"],
                L["During a Mythic+ run, draws the keystone level, the affixes, the time left with the +2 and +3 times, and the deaths in place of the stage banner. This tracker replaces the default one, so without this they are not shown anywhere."])
        end

        scenarios:Add(self:CreateCheckbox(content, L["Show Quest Discovered popups"],
            function() return DB().showQuestPopups ~= false end,
            function(v) DB().showQuestPopups = v; render() end,
            L["Boxes for newly discovered / completed quests."]))

        local sounds = self:CreateGroup(content, L["Sounds"])
        sounds:SetPoint("TOPLEFT", scenarios, "BOTTOMLEFT", 0, -gap)
        sounds:SetPoint("TOPRIGHT", scenarios, "BOTTOMRIGHT", 0, -gap)

        local function playSound(value)
            ns:GetModule("Media"):Play(value)
        end
        -- The list is rebuilt on every open rather than captured, which is what CreateDropdown's
        -- function form is for, and every picker wants the identical one.
        local function soundList()
            local labels, values = ns:GetModule("Media"):GetSoundList()
            local out = {}
            for _, name in ipairs(labels) do
                out[#out + 1] = { value = values[name] or "NONE", label = name }
            end
            return out
        end

        local function channelList()
            local Media, out = ns:GetModule("Media"), {}
            for _, v in ipairs(Media.CHANNELS) do
                out[#out + 1] = { value = v, label = Media:ChannelLabel(v) }
            end
            return out
        end
        -- Picking one plays the quest sound, so the player hears where their sounds now go.
        sounds:Add(self:CreateDropdown(content, L["Sound Channel"],
            channelList,
            function() return DB().soundChannel or "Master" end,
            function(v) DB().soundChannel = v; playSound(DB().questCompleteSound) end,
            L["Which volume slider in the game's sound settings these sounds follow. Master Volume by default."]))

        -- Each picker sits under the switch it belongs to and is never dimmed: most of the
        -- switches ship off, and a picker grayed out in the common state reads as broken (the
        -- author's call, 2026-10-01).
        sounds:Add(self:CreateCheckbox(content, L["Quest Sound"],
            function() return DB().questSoundEnabled ~= false end,
            function(v) DB().questSoundEnabled = v end,
            L["Plays when a quest is ready to turn in."]))
        sounds:Add(self:CreateDropdown(content, L["Quest Complete Sound"],
            soundList,
            function() return DB().questCompleteSound or "NONE" end,
            function(v) DB().questCompleteSound = v; playSound(v) end,
            L["Which sound plays when a quest becomes ready to turn in."],
            nil, playSound), { dependent = true })

        -- Its own switch rather than hanging off Quest Sound above, so a player can have one
        -- without the other. == true, not ~= false: this one ships off.
        sounds:Add(self:CreateCheckbox(content,
            L["Play a sound when you accept a quest"],
            function() return DB().questAcceptSoundEnabled == true end,
            function(v) DB().questAcceptSoundEnabled = v end,
            L["Off by default. It has its own sound below, so accepting and completing can be told apart."]))
        sounds:Add(self:CreateDropdown(content, L["Quest Accepted Sound"],
            soundList,
            function() return DB().questAcceptSound or "NONE" end,
            function(v) DB().questAcceptSound = v; playSound(v) end,
            L["Which sound plays when you accept a quest. World quests and bonus objectives are left silent, since walking into one accepts it."],
            nil, playSound), { dependent = true })

        -- Its own switch and its own sound, like the accept pair above. This one fires at the
        -- quest giver, which is where the Quest Complete sound was landing on Classic by
        -- accident.
        sounds:Add(self:CreateCheckbox(content,
            L["Play a sound when you turn a quest in"],
            function() return DB().questTurnInSoundEnabled == true end,
            function(v) DB().questTurnInSoundEnabled = v end,
            L["Off by default. It has its own sound below, so handing a quest in and finishing its objectives can be told apart."]))
        sounds:Add(self:CreateDropdown(content, L["Quest Turned In Sound"],
            soundList,
            function() return DB().questTurnInSound or "NONE" end,
            function(v) DB().questTurnInSound = v; playSound(v) end,
            L["Which sound plays when you hand a quest in at the quest giver."],
            nil, playSound), { dependent = true })

        sounds:Add(self:CreateCheckbox(content,
            L["Play a sound when an objective is finished"],
            function() return DB().objectiveDoneSoundEnabled == true end,
            function(v) DB().objectiveDoneSoundEnabled = v end,
            L["Off by default. It has its own sound below. When the same moment also finishes a quest and Quest Sound is on, only the quest's sound plays."]))
        sounds:Add(self:CreateDropdown(content, L["Objective Finished Sound"],
            soundList,
            function() return DB().objectiveDoneSound or "NONE" end,
            function(v) DB().objectiveDoneSound = v; playSound(v) end,
            L["Which sound plays when you finish one of a quest's objectives."],
            nil, playSound), { dependent = true })

        sounds:Add(self:CreateCheckbox(content,
            L["Play a sound when you make progress on an objective"],
            function() return DB().objectiveProgressSoundEnabled == true end,
            function(v) DB().objectiveProgressSoundEnabled = v end,
            L["Off by default. Plays for each step, such as 3/10 to 4/10. Only one sound plays at a time, so a step that also finishes an objective or a quest plays that sound instead, if it is turned on."]))
        sounds:Add(self:CreateDropdown(content, L["Objective Progress Sound"],
            soundList,
            function() return DB().objectiveProgressSound or "NONE" end,
            function(v) DB().objectiveProgressSound = v; playSound(v) end,
            L["Which sound plays when an objective moves forward."],
            nil, playSound), { dependent = true })

        -- The zone progress bar's two toggles and the bonus objectives HUD's three used to be on
        -- this tab. Both features live under their own Appearance heading now, beside the
        -- controls that style them - one feature, one place.
    end,

    refresh = function(_, content)
        if content._syncZoneTag then content._syncZoneTag() end
        if content._syncTodo then content._syncTodo() end
        if content._syncManualHint then content._syncManualHint() end
        if content._syncHideFinished then content._syncHideFinished() end
        if content._syncDelveRows then content._syncDelveRows() end
        if content._renderOrderRows then content._renderOrderRows() end
    end,
})
