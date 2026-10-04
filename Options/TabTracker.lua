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

local ARROW_SIZE = 24
local ARROW_GAP  = 4

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

        local simplify = self:CreateCheckbox(content, L["Simplify Mode"],
            trackerSetting("simplifyMode"))
        onScreen:Add(simplify)
        self:AttachTooltip(simplify, L["Simplify Mode"],
            L["Show only the first incomplete objective per quest."])

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

        -- Eight choices, so the library draws this as a dropdown with each choice's tip on its row.
        onScreen:Add(self:CreateRadioGroup(content, L["Sort Order"],
            SORT_OPTIONS,
            function() return DB().sortMode or "zone" end,
            function(v)
                DB().sortMode = v
                render()
                syncManualHint(v)
            end))

        manualHint = self:CreateText(content,
            L["Drag and drop the quests in the tracker to reorder them however you like."], "hint")
        onScreen:Add(manualHint, { dependent = true, fill = true })
        syncManualHint(DB().sortMode)

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

        local zoneOnly = self:CreateCheckbox(content, L["Show only quests in current zone"],
            function() return DB().filters.onlyCurrentZone end,
            function(v) DB().filters.onlyCurrentZone = v; render() end,
            L["Only show entries with an objective on your current map. Entries whose provider cannot tell are always shown."])
        filters:Add(zoneOnly)

        -- Gated like the category run above. Classic has no campaigns, so it could never act.
        local campaignZone
        if Registry:HasTag("campaign") then
            campaignZone = self:CreateCheckbox(content, L["Always show campaign quests"],
                function() return DB().filters.campaignAnyZone end,
                function(v) DB().filters.campaignAnyZone = v; render() end,
                L["Campaign quests from every zone stay on the tracker, even while Show only quests in current zone is on."])
            filters:Add(campaignZone)
        end

        -- Deliberately does NOT touch showOnlyWatched. That box sits under a different
        -- heading and is the most impactful setting on the tab, so silently turning it back
        -- on here hid quests with nothing connecting the two.
        local resetFilters = self:CreateButton(content, L["Reset filters to defaults"], nil,
            function()
                local f = DB().filters
                -- Walked rather than listed, so a category added to Filter.CATEGORIES is
                -- reset here without anyone remembering to come back for it.
                for i = 1, #Filter.CATEGORIES do f[Filter.CATEGORIES[i].key] = true end
                f.onlyCurrentZone = false
                f.campaignAnyZone = false
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
                and L["Turns every category filter back on, clears the current-zone filter and turns off Always show campaign quests. Nothing else on this tab is changed."]
                or L["Turns every category filter back on and clears the current-zone filter. Nothing else on this tab is changed."])
        -- The last row of the card, after whichever filter ends the run.
        filters:Add(resetFilters)

        local visibility = self:CreateGroup(content, L["Tracker Visibility"])
        visibility:SetPoint("TOPLEFT", filters, "BOTTOMLEFT", 0, -gap)
        visibility:SetPoint("TOPRIGHT", filters, "BOTTOMRIGHT", 0, -gap)

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
                    function(v) Sections:SetHidden(id, not v); render() end,
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
            -- the fraction, never both - so exactly one of them is live at a time and the dead
            -- one has to say so.
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
                L["Height in pixels for the world quest area. Only used while Set a custom World Quests height is on."])
            visibility:Add(wqHeightSlider, { dependent = true })

            -- EQOT-only: EQ caps the world quest area by fixed height alone. Kept because it
            -- is backed by real tracker code, and placed with the other height controls.
            wqMaxSlider = self:CreateSlider(content, L["Maximum Height (percent of tracker)"], 10, 80, 5,
                function() return (DB().worldQuestsPinnedMaxFraction or 0.40) * 100 end,
                function(v)
                    DB().worldQuestsPinnedMaxFraction = v / 100
                    render()
                end,
                L["The most of the tracker the world quest area may take. It is capped here first and your quest list takes the space that is left, scrolling for whatever does not fit. Only used while Set a custom World Quests height is off."])
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
        order:Add(wqPos)

        -- One row per place in the order, built the first time the list needs it and relabeled on
        -- every move, so a row keeps its place in the card while the section named on it changes.
        local orderRows = {}
        local function renderOrderRows()
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
                    orderRows[i] = r
                end
                r.name:SetText(sectionLabel(id))
                r.name:Show()
                r.up:Show()
                r.down:Show()
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
            end
            order:Layout()
        end
        renderOrderRows()

        local display = self:CreateGroup(content, L["Options"])
        display:SetPoint("TOPLEFT", order, "BOTTOMLEFT", 0, -gap)
        display:SetPoint("TOPRIGHT", order, "BOTTOMRIGHT", 0, -gap)

        local lvl = self:CreateCheckbox(content, L["Show quest level prefix"],
            rowSetting("showLevelInTracker"))
        display:Add(lvl)
        self:AttachTooltip(lvl, L["Show quest level prefix"], L["For example, [60] Title."])

        local zoneCheck = self:CreateCheckbox(content, L["Show zone label under quest titles"],
            rowSetting("showZoneTag"))
        display:Add(zoneCheck)
        self:AttachTooltip(zoneCheck, L["Show zone label under quest titles"],
            L["Adds the quest log heading each quest came from as a small line under its title."])

        local objCheck = self:CreateCheckbox(content, L["Show objective progress numbers"],
            rowSetting("showObjectiveNumbers", true))
        display:Add(objCheck)
        self:AttachTooltip(objCheck, L["Show objective progress numbers"],
            L["For example, 0/4, 1/1, etc."])

        -- Show progress bars moved to the Appearance tab's Progress Bars group, so the switch
        -- that turns the bars on is not two tabs away from the controls that style them. Same
        -- move the zone progress bar's own toggles made, for the same reason.
        local widgetCheck = self:CreateCheckbox(content, L["Show event and scenario widgets"],
            rowSetting("showTrackerWidgets", true))
        display:Add(widgetCheck)
        self:AttachTooltip(widgetCheck, L["Show event and scenario widgets"],
            L["Draws the extra bars and status lines the default tracker shows during world events, delves and scenarios, such as an event's progress bar or a delve's tier. This tracker replaces the default one, so without this those are not shown anywhere."])

        local qidCheck = self:CreateCheckbox(content, L["Show quest ID"],
            rowSetting("showQuestID"))
        display:Add(qidCheck)
        self:AttachTooltip(qidCheck, L["Show quest ID"], L["Useful for bug reports."])

        -- UI/Tracker.lua reads showQuestTotal for every ordinary section and for the pinned
        -- world quest region, not just Quests and Campaign, and the pair it draws is
        -- visible/total rather than tracked/total.
        display:Add(self:CreateCheckbox(content,
            L["Show the visible / total count on section headers"],
            function() return DB().showQuestTotal ~= false end,
            function(v) DB().showQuestTotal = v; render() end,
            L["For example, 3/9. Applies to every section header."]))

        display:Add(self:CreateCheckbox(content, L["Keep section headers in view while scrolling"],
            function() return DB().stickySectionHeaders ~= false end,
            function(v)
                DB().stickySectionHeaders = v
                ns:GetModule("Tracker"):ApplyWorldQuestsPosition()
                render()
            end,
            L["The header of the section you are scrolled into stays at the top of the quest list, so you can always see which section you are in. On by default."]))

        local itemBtnCheck = self:CreateCheckbox(content, L["Show usable quest item buttons"],
            rowSetting("showItemButtons", true))
        display:Add(itemBtnCheck)
        self:AttachTooltip(itemBtnCheck, L["Show usable quest item buttons"],
            L["Puts a button on the tracker row of any quest that carries a usable item, so you can use it without opening your bags."])

        -- Named after the cogwheel itself: as "Options icon" two players, the author among them,
        -- went looking for a way to hide it and never found this box.
        display:Add(self:CreateCheckbox(content, L["Show the options cogwheel on the tracker"],
            function() return DB().showOptionsIcon ~= false end,
            function(v)
                DB().showOptionsIcon = v
                ns:GetModule("Tracker"):ApplyHeaderIcons()
            end,
            L["A small cogwheel at the top-right of the tracker that opens the options panel."]))

        -- EQ has Show Chain Guide icon after this one. Deliberately not ported: it opens
        -- EQ's Chain Guide, which EQOT does not have.
        display:Add(self:CreateCheckbox(content, L["Show Quest Discovered popups"],
            function() return DB().showQuestPopups ~= false end,
            function(v) DB().showQuestPopups = v; render() end,
            L["Boxes for newly discovered / completed quests."]))

        local newTagCheck = self:CreateCheckbox(content,
            L["Show NEW tag on recently accepted quests"],
            rowSetting("showRecentlyAddedTag", true))
        display:Add(newTagCheck)
        self:AttachTooltip(newTagCheck, L["Show NEW tag on recently accepted quests"],
            L["For about an hour after accepting."])

        local splitCheck = self:CreateCheckbox(content, L["Split quest click"],
            trackerSetting("splitQuestClick"))
        display:Add(splitCheck)
        self:AttachTooltip(splitCheck, L["Split quest click"],
            L["Click the icon to focus, click the title to open the quest log."])

        local function playSound(value)
            ns:GetModule("Media"):Play(value)
        end
        -- The list is rebuilt on every open rather than captured, which is what CreateDropdown's
        -- function form is for, and all three pickers want the identical one.
        local function soundList()
            local labels, values = ns:GetModule("Media"):GetSoundList()
            local out = {}
            for _, name in ipairs(labels) do
                out[#out + 1] = { value = values[name] or "NONE", label = name }
            end
            return out
        end

        -- Each picker sits under the switch it belongs to and is never dimmed: two of the three
        -- switches ship off, and a picker grayed out in the common state reads as broken (the
        -- author's call, 2026-10-01).
        display:Add(self:CreateCheckbox(content, L["Quest Sound"],
            function() return DB().questSoundEnabled ~= false end,
            function(v) DB().questSoundEnabled = v end,
            L["Plays when a quest is ready to turn in."]))
        display:Add(self:CreateDropdown(content, L["Quest Complete Sound"],
            soundList,
            function() return DB().questCompleteSound or "NONE" end,
            function(v) DB().questCompleteSound = v; playSound(v) end,
            L["Which sound plays when a quest becomes ready to turn in."],
            nil, playSound), { dependent = true })

        -- Its own switch rather than hanging off Quest Sound above, so a player can have one
        -- without the other. == true, not ~= false: this one ships off.
        display:Add(self:CreateCheckbox(content,
            L["Play a sound when you accept a quest"],
            function() return DB().questAcceptSoundEnabled == true end,
            function(v) DB().questAcceptSoundEnabled = v end,
            L["Off by default. It has its own sound below, so accepting and completing can be told apart."]))
        display:Add(self:CreateDropdown(content, L["Quest Accepted Sound"],
            soundList,
            function() return DB().questAcceptSound or "NONE" end,
            function(v) DB().questAcceptSound = v; playSound(v) end,
            L["Which sound plays when you accept a quest. World quests and bonus objectives are left silent, since walking into one accepts it."],
            nil, playSound), { dependent = true })

        -- Its own switch and its own sound, like the accept pair above. This one fires at the
        -- quest giver, which is where the Quest Complete sound was landing on Classic by
        -- accident.
        display:Add(self:CreateCheckbox(content,
            L["Play a sound when you turn a quest in"],
            function() return DB().questTurnInSoundEnabled == true end,
            function(v) DB().questTurnInSoundEnabled = v end,
            L["Off by default. It has its own sound below, so handing a quest in and finishing its objectives can be told apart."]))
        display:Add(self:CreateDropdown(content, L["Quest Turned In Sound"],
            soundList,
            function() return DB().questTurnInSound or "NONE" end,
            function(v) DB().questTurnInSound = v; playSound(v) end,
            L["Which sound plays when you hand a quest in at the quest giver."],
            nil, playSound), { dependent = true })

        -- The zone progress bar's two toggles used to sit here, and so did the bonus
        -- objectives HUD's three. Both features live under their own Appearance heading now,
        -- beside the controls that style them - one feature, one place.
    end,
})
