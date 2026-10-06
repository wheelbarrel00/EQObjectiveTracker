local _, ns = ...

local Options = ns:GetModule("Options")
local L       = ns.L

-- Values go straight to SetFont, which takes a comma-joined combo and ignores unknown
-- tokens, so "" means no outline.
-- The space after each comma is EQ's, and it is copied rather than tidied: fontOutline is
-- one of the keys Core/Migrate.lua lifts from EQ by name, so an imported value has to be
-- one this list can represent or the dropdown reads blank.
local OUTLINES = {
    { value = "",                         label = L["None"] },
    { value = "OUTLINE",                  label = L["Outline"] },
    { value = "THICKOUTLINE",             label = L["Thick"] },
    { value = "MONOCHROME",               label = L["Mono"] },
    { value = "MONOCHROME, OUTLINE",      label = L["Mono Outline"] },
    { value = "MONOCHROME, THICKOUTLINE", label = L["Mono Thick"] },
}

local LAYOUTS = {
    { value = "classic", label = L["Plain"] },
    { value = "card",    label = L["Card"] },
}

local BAR_STYLES = {
    { value = 1, label = L["Header Bar 1"] },
    { value = 2, label = L["Header Bar 2"] },
}

local TITLE_MODES = {
    { value = "difficulty", label = L["By difficulty"],
      tip = L["Each quest title takes the color of how hard it is for your level, the way the quest log does. Entries with no level are gold."] },
    -- Not L["Gold"]: the shared store translates that one as money.
    { value = "gold",       label = L["Gold color"],
      tip = L["Every title in the same gold."] },
    { value = "class",      label = L["Class color"],
      tip = L["Every title in the class color of the character you are logged in on."] },
    -- Not L["Custom"]: its translations were written for another addon, and in Korean it reads "User".
    { value = "custom",     label = L["Custom color"],
      tip = L["Every title in the color you pick under this."] },
    { value = "original",   label = L["Original Style"],
      tip = L["Titles colored the way Blizzard's own tracker colors them on this version of the game."] },
}

local ZONE_ORDERS = {
    { value = "current", label = L["Current zone first"],
      tip = L["Zones with a quest on the map you are in come first, then the rest in the order your quest log lists them."] },
    { value = "alpha",   label = L["Alphabetical"],
      tip = L["Every zone in alphabetical order."] },
}

local SCENARIO_ALIGN = {
    { value = "LEFT",   label = L["Left"] },
    { value = "CENTER", label = L["Center"] },
    { value = "RIGHT",  label = L["Right"] },
}

-- Anything unrecognized normalizes to CENTER. A profile written before the align value was
-- separated from its display label can hold a translated word like "GAUCHE".
local function alignValue(v)
    return (v == "LEFT" or v == "RIGHT") and v or "CENTER"
end

-- Media names are a migration contract - a profile stores the font or bar by name - so
-- value and label are deliberately the same string.
local function mediaOptions(names, first)
    local out = {}
    if first then out[1] = first end
    for _, n in ipairs(names) do out[#out + 1] = { value = n, label = n } end
    return out
end

local function DB() return ns:GetModule("DB"):Tracker() end

-- Empty is the zone bar's "same as tracker" sentinel, which has no file of its own and so
-- correctly falls back to the interface font in the list.
local function fontPreview(name)
    if not name or name == "" then return nil end
    return ns:GetModule("Media"):GetFontFile(name)
end

-- The sample tracker in the preview panel draws from the same settings, so every setter that
-- reaches the tracker redraws it too.
local function refreshPreview()
    ns:GetModule("TrackerPreview"):Refresh()
end

-- Font, size, outline and shadow all feed the SetFont pass that pooled rows only redo
-- when the generation bumps, so every one of these setters must invalidate.
local function restyle(key, v)
    DB()[key] = v
    ns:GetModule("Row"):Invalidate()
    ns:GetModule("Tracker"):Render()
    refreshPreview()
end

local function relayout(key, v)
    DB()[key] = v
    ns:GetModule("Tracker"):Render()
    refreshPreview()
end

local function bannerRestyle(key, v)
    DB()[key] = v
    ns:GetModule("Scenario"):ApplyBannerShadow()
    ns:GetModule("Tracker"):Render()
    refreshPreview()
end

local SAME_FONT = L["Same as tracker font"]

local function zbState()
    local t = DB()
    if not t then return nil end
    t.zoneProgressBar = t.zoneProgressBar or {}
    return t.zoneProgressBar
end

-- Only the fill texture and color reach the docked bar, so only those repaint the tracker.
-- The rest land on the floating frame alone, and a full Render there would re-run every
-- provider once per slider step for a frame the tracker does not contain.
local function zbSet(key, v, shared)
    local st = zbState()
    if st then st[key] = v end
    ns:GetModule("ZoneProgressBar"):RefreshAppearance()
    if shared then ns:GetModule("Tracker"):Render() end
    refreshPreview()
end

local function pbState()
    local t = DB()
    if not t then return nil end
    t.progressBar = t.progressBar or {}
    return t.progressBar
end

-- Every bar this styles is drawn inside the tracker, so every key here needs a full repaint.
-- Row memoizes on a set of stored fields and returns before it would touch a bar at all, so a
-- bare Render would leave every existing row exactly as it was - Invalidate is what makes the
-- new texture, color or height reach a row that is already on screen.
local function pbSet(key, v)
    local st = pbState()
    if st then st[key] = v end
    ns:GetModule("Row"):Invalidate()
    ns:GetModule("Tracker"):Render()
    refreshPreview()
end

local function sbState()
    local t = DB()
    if not t then return nil end
    t.scenarioBonusHUD = t.scenarioBonusHUD or {}
    return t.scenarioBonusHUD
end

-- The HUD is parented to UIParent rather than to the tracker, so none of this needs a
-- tracker repaint. ApplySettings is the whole apply path.
local function sbSet(key, v)
    local st = sbState()
    if st then st[key] = v end
    ns:GetModule("ScenarioBonusHUD"):ApplySettings()
end

local function barTextureSwatch(frame, name)
    if not frame.swatch then return end
    frame.swatch:SetTexture(ns:GetModule("Media"):GetStatusBarFile(name))
    frame.swatch:SetVertexColor(0.26, 0.42, 1.0)
end

-- A row the card indents under the switch above it. The card only reads it, so one is shared.
local DEPENDENT = { dependent = true }

-- A checkbox's own color sits at the right end of the checkbox's row.
local function satellite(ui, row, picker)
    picker:SetPoint("RIGHT", row, "RIGHT", -ui:Spacing("rowPadding"), 0)
end

Options:RegisterTab({
    id    = "appearance",
    title = L["Appearance"],
    order = 30,
    footer = function(self, bar)
        local reset = self:CreateButton(bar, L["Reset to Defaults"], nil, function()
            local Dialog = ns:GetModule("Dialog")
            if not Dialog then return end
            Dialog:Show({
                title    = "EQ Objective Tracker",
                text     = L["Reset every setting on this tab to its defaults? The interface will reload."],
                button1  = L["Reset"],
                button2  = L["Cancel"],
                onAccept = function()
                    ns:GetModule("DB"):ResetTrackerAppearance()
                    ReloadUI()
                end,
            })
        end, L["Restores every control on this tab, including the zone bar block, to its default. Other tabs are left alone."])
        reset:SetPoint("RIGHT")
    end,
    preview = function(_, panel) ns:GetModule("TrackerPreview"):Build(panel) end,
    previewRefresh = refreshPreview,
    build = function(self, content)
        -- Forward-declared because roughly half the controls below are dimmed by a master
        -- switch and every one of those masters has to be able to re-run the sweep.
        local syncDependents
        -- Every control syncDependents dims lives in this one table. As separate upvalues they
        -- reached 55 against Lua 5.1's limit of 60, past which this FILE stops compiling and
        -- the Appearance tab disappears, with luacheck still reporting it clean.
        local w = {}

        local gap = self:Spacing("groupGap")
        local above
        local function stack(card)
            if above then
                card:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -gap)
                card:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT", 0, -gap)
            else
                card:SetPoint("TOPLEFT")
                card:SetPoint("TOPRIGHT")
            end
            above = card
            return card
        end

        -- The card order is the author's (2026-10-03): the most used settings first, the
        -- self-contained features last.
        local look = stack(self:CreateGroup(content, L["Text"]))

        look:Add(self:CreateDropdown(content, L["Font"],
            function() return mediaOptions(ns:GetModule("Media"):GetFontList()) end,
            function() return DB().font end,
            function(v) restyle("font", v) end,
            L["Fonts registered through LibSharedMedia, so anything from ElvUI or SharedMedia appears here too."],
            nil, nil, fontPreview))

        local sizeSlider = self:CreateSlider(content, L["Font Size"], 8, 24, 0.5,
            function() return DB().fontSize or 15 end,
            function(v) restyle("fontSize", v) end,
            L["Base size for objective text. Titles and headers offset from this."])
        look:Add(sizeSlider)

        local titleSizeSlider = self:CreateSlider(content, L["Title Size Offset"], -6, 12, 0.5,
            function() return DB().titleSizeDelta or 0 end,
            function(v) restyle("titleSizeDelta", v) end,
            L["Sizes quest and achievement titles separately from the objective text. This value is added to the Font Size above: 0 keeps titles the same size as the base font, positive makes them larger, negative smaller."])
        look:Add(titleSizeSlider)

        local headerSizeSlider = self:CreateSlider(content, L["Header Size Offset"], -8, 12, 0.5,
            function() return DB().headerSizeDelta or 4 end,
            function(v) relayout("headerSizeDelta", v) end,
            L["Sizes the section headers (Quests, Campaign, and so on) independently of the quest text. Added on top of the Font Size above: the default 4 keeps headers at their current size, lower shrinks them (handy on a low UI scale), higher enlarges them."])
        look:Add(headerSizeSlider)

        look:Add(self:CreateDropdown(content, L["Font Outline"],
            OUTLINES,
            function() return DB().fontOutline or "" end,
            function(v) restyle("fontOutline", v) end,
            L["Outlines keep small text legible over bright terrain."]))

        local shadowRow = look:Add(self:CreateCheckbox(content, L["Text Shadow"],
            function() return DB().textShadow end,
            function(v) restyle("textShadow", v); syncDependents() end,
            L["Draws a soft drop-shadow behind all tracker text so it stays readable over bright or busy backgrounds. Use Shadow Color to tint it and Shadow Size to set how far it's cast."]))

        w.shadowPicker = self:CreateColorPicker(content, L["Shadow Color"],
            function() return DB().textShadowColor end,
            function(v) restyle("textShadowColor", v) end,
            L["Shadow color and opacity."], true)
        satellite(self, shadowRow, w.shadowPicker)

        w.shadowSizeSlider = self:CreateSlider(content, L["Shadow Size"], 1, 6, 0.5,
            function() return DB().textShadowStrength or 2 end,
            function(v) restyle("textShadowStrength", v) end,
            L["How far the text drop-shadow is cast behind the letters. Higher values give a larger, more pronounced shadow. Lower values keep it tight. Only applies while Text Shadow is on."])
        look:Add(w.shadowSizeSlider, DEPENDENT)

        local questColors = stack(self:CreateGroup(content, L["Quest Colors"]))

        -- Five choices, so the library draws a dropdown with each choice's tip on its row. The
        -- getter reads the mode the old switches imply until one is saved.
        questColors:Add(self:CreateRadioGroup(content, L["Quest Title Color"],
            TITLE_MODES,
            function() return ns.Util.TitleColorMode(DB()) end,
            function(v) restyle("titleColorMode", v); syncDependents() end,
            nil, nil,
            L["Quest Title Color"],
            L["How quest, achievement and endeavor titles are colored. Failed quests are always red, and finished ones green unless Use title color for completed quests is on."]))

        -- Until a known mode is saved the override is one of the switches the mode is read off, so
        -- the mode shown is saved first or the picker and its Clear would switch every title.
        local function setTitleOverride(v)
            local db = DB()
            db.titleColorMode = ns.Util.TitleColorMode(db)
            restyle("titleColorOverride", v)
        end

        -- onClear rather than a button of our own: the helper hides it while the color is
        -- unset, so a live Clear no longer sits beside a swatch it cannot change.
        w.titlePicker = self:CreateColorPicker(content, L["Custom Title Color"],
            function() return DB().titleColorOverride end,
            function(v)
                local had = (DB().titleColorOverride or {}).r ~= nil
                setTitleOverride(v)
                -- Only when the nil state actually changes, in either direction. The wheel
                -- fires this setter every frame of a drag, and the sweep is ~40 SetAlpha
                -- calls. Cancel comes back through here with the previous value, so testing
                -- only for the arriving transition left the control undimmed and inert.
                if had ~= (v ~= nil) then syncDependents() end
            end,
            L["The color every title takes while Quest Title Color is set to Custom color. Until one is picked they are gold."],
            false,
            function()
                setTitleOverride(nil)
                syncDependents()
            end)
        questColors:Add(w.titlePicker, DEPENDENT)

        w.recolorCheck = self:CreateCheckbox(content, L["Use title color for completed quests"],
            function() return DB().overrideCompleteGreen ~= false end,
            function(v) restyle("overrideCompleteGreen", v) end,
            L["A finished quest's title takes the title color instead of green, and so do its finished objectives unless a Finished Objective Color is picked. Only Class color, Custom color and Original Style give a title color."])
        questColors:Add(w.recolorCheck)

        questColors:Add(self:CreateColorPicker(content, L["Objective Text Color"],
            function() return DB().objectiveColor end,
            function(v) restyle("objectiveColor", v) end,
            L["Color of the objective lines under each title. The count at the start of a line has its own three colors below."]))

        questColors:Add(self:CreateColorPicker(content, L["Count Color: None Done"],
            function() return DB().countColorNone end,
            function(v) restyle("countColorNone", v) end,
            L["Color of a count like 0/5, while none of it is done."]))

        questColors:Add(self:CreateColorPicker(content, L["Count Color: In Progress"],
            function() return DB().countColorPartial end,
            function(v) restyle("countColorPartial", v) end,
            L["Color of a count like 2/5, while some of it is done."]))

        questColors:Add(self:CreateColorPicker(content, L["Count Color: Done"],
            function() return DB().countColorDone end,
            function(v) restyle("countColorDone", v) end,
            L["Color of a count like 5/5 once all of it is done. Finished objectives take it too, unless a Finished Objective Color is picked, or Use title color for completed quests is on with Quest Title Color set to Class color, Custom color or Original Style."]))

        -- Unset by default, so until one is picked a finished line takes the title color the box
        -- gives, else the done count's.
        questColors:Add(self:CreateColorPicker(content, L["Finished Objective Color"],
            function() return DB().finishedObjectiveColor end,
            function(v) restyle("finishedObjectiveColor", v) end,
            L["Color of an objective you have finished. While unset it follows Count Color: Done, or the title color when Use title color for completed quests gives one."],
            false,
            function() restyle("finishedObjectiveColor", nil) end))

        local tracker = stack(self:CreateGroup(content, L["Tracker"]))

        local scaleSlider = self:CreateSlider(content, L["Tracker Scale"], 0.7, 1.5, 0.05,
            function() return DB().scale or 1 end,
            function(v)
                DB().scale = v
                ns:GetModule("Tracker"):ApplyScale()
            end,
            L["Scales the whole tracker. Takes effect immediately out of combat."])
        tracker:Add(scaleSlider)

        local syncFade
        -- Stored as a fraction and shown as a whole number, so no key carries a bare percent sign.
        local fadeSlider = self:CreateSlider(content, L["Tracker Opacity"], 10, 100, 5,
            function() return math.floor((DB().trackerAlpha or 1) * 100 + 0.5) end,
            function(v)
                DB().trackerAlpha = v / 100
                ns:GetModule("Visibility"):ApplyFade()
                syncFade()
                refreshPreview()
            end,
            L["How solid the tracker is. At 100 it is fully solid, and lower values let the game show through it."])
        tracker:Add(fadeSlider)

        local fadeHover = self:CreateCheckbox(content, L["Full opacity on mouseover"],
            function() return DB().trackerAlphaHover ~= false end,
            function(v)
                DB().trackerAlphaHover = v
                ns:GetModule("Visibility"):ApplyFade()
            end,
            L["Brings the tracker back to full while the mouse is over its quests or headers. Only used while Tracker Opacity is below 100."])
        tracker:Add(fadeHover, DEPENDENT)

        local fadeFocus = self:CreateCheckbox(content, L["Keep the focused quest at full opacity"],
            function() return DB().trackerAlphaFocus ~= false end,
            function(v)
                DB().trackerAlphaFocus = v
                ns:GetModule("Visibility"):ApplyFade()
            end,
            L["The quest you are following stays fully solid while the rest of the tracker is faded. Only used while Tracker Opacity is below 100."])
        tracker:Add(fadeFocus, DEPENDENT)

        -- Swept on its own rather than through syncDependents: the slider calls it on every
        -- step of a drag, and these two boxes are all that step can change.
        syncFade = function()
            local faded = (DB().trackerAlpha or 1) < 1
            self:SetDependent(fadeHover, faded)
            self:SetDependent(fadeFocus, faded)
        end
        syncFade()

        local bgRow = tracker:Add(self:CreateCheckbox(content, L["Background"],
            function() return DB().showBackground end,
            function(v) relayout("showBackground", v); syncDependents() end,
            L["Fills the tracker behind the text. Useful over bright terrain."]))

        w.bgPicker = self:CreateColorPicker(content, L["Background Color"],
            function() return DB().backgroundColor end,
            function(v) relayout("backgroundColor", v) end,
            L["Background color and opacity."], true)
        satellite(self, bgRow, w.bgPicker)

        local borderRow = tracker:Add(self:CreateCheckbox(content, L["Border"],
            function() return DB().showBorder end,
            function(v) relayout("showBorder", v); syncDependents() end,
            L["Draws a border around the tracker."]))

        w.borderPicker = self:CreateColorPicker(content, L["Border Color"],
            function() return DB().borderColor end,
            function(v) relayout("borderColor", v) end,
            L["Border color and opacity."], true)
        satellite(self, borderRow, w.borderPicker)

        w.borderThickSlider = self:CreateSlider(content, L["Border Thickness"], 1, 5, 0.5,
            function() return DB().borderSize or 1 end,
            function(v) relayout("borderSize", v) end,
            L["Border thickness in pixels."])
        tracker:Add(w.borderThickSlider, DEPENDENT)

        local headers = stack(self:CreateGroup(content, L["Section Headers"]))

        headers:Add(self:CreateCheckbox(content, L["Use class color for headers"],
            function() return DB().headerColorUseClass end,
            function(v) relayout("headerColorUseClass", v); syncDependents() end,
            L["Colors the section headers (Quests, Campaign, and so on) with the class color of the character you are currently logged in on. Overrides the color below while it is on. Off by default."]))

        w.headerPicker = self:CreateColorPicker(content, L["Section Header Color"],
            function() return DB().headerColor end,
            function(v) relayout("headerColor", v) end,
            L["Color of the Quests, Campaign and World Quests headings."])
        headers:Add(w.headerPicker, DEPENDENT)

        headers:Add(self:CreateColorPicker(content, L["Divider Line Color"],
            function() return DB().headerDividerColor end,
            function(v) relayout("headerDividerColor", v) end,
            L["Sets the color of the thin line under each section header. Defaults to the original gold."], true))

        local hbRow = headers:Add(self:CreateCheckbox(content, L["Show header bars"],
            function() return DB().headerBar end,
            function(v) relayout("headerBar", v); syncDependents() end,
            L["Draws a colored gradient bar behind each section header (Quests, Campaign, World Quests, and so on), for a look closer to the default Blizzard tracker. Off by default."]))

        w.hbPicker = self:CreateColorPicker(content, L["Bar Color"],
            function() return DB().headerBarColor end,
            function(v) relayout("headerBarColor", v) end,
            L["Brightest end of the bar gradient. The other end is the same color darkened."], true)
        satellite(self, hbRow, w.hbPicker)

        w.hbStyle = self:CreateRadioGroup(content, L["Bar Style"],
            BAR_STYLES,
            function() return (DB().headerBarStyle or 1) == 2 and 2 or 1 end,
            function(v) relayout("headerBarStyle", v) end,
            nil, nil,
            L["Bar Style"],
            L["Header Bar 1 is a horizontal gradient (bright on the left, dark on the right). Header Bar 2 is a vertical gradient (bright at the top, dark at the bottom). Bar Color, Bar Height, and Soft edges all apply to whichever style you pick."])
        headers:Add(w.hbStyle)

        w.hbHeightSlider = self:CreateSlider(content, L["Bar Height"], 6, 26, 0.5,
            function() return DB().headerBarHeight or 22 end,
            function(v) relayout("headerBarHeight", v) end,
            L["How tall the section-header bar is. The bar is centered on the header row, so larger values fill more of it."])
        headers:Add(w.hbHeightSlider)

        w.hbSoftCheck = self:CreateCheckbox(content, L["Soft edges"],
            function() return DB().headerBarSoftEdges end,
            function(v) relayout("headerBarSoftEdges", v); syncDependents() end,
            L["Feathers the top, left, and right edges of the header bar so it blends into the UI instead of sitting in a hard box. The gradient color is unchanged. Only applies while Header bars is on. Off by default."])
        headers:Add(w.hbSoftCheck)

        w.hbSoftSlider = self:CreateSlider(content, L["Edge Softness"], 1, 10, 0.5,
            function() return DB().headerBarSoftEdgeStrength or 10 end,
            function(v) relayout("headerBarSoftEdgeStrength", v) end,
            L["How soft the header bar's feathered edges are when Soft edges is on. Higher is softer, lower tightens toward a hard edge."])
        headers:Add(w.hbSoftSlider, DEPENDENT)

        local zoneHeads = stack(self:CreateGroup(content, L["Zone Headers"]))

        zoneHeads:Add(self:CreateCheckbox(content, L["Show zone headers"],
            function() return DB().zoneHeaders end,
            function(v) restyle("zoneHeaders", v); syncDependents() end,
            L["Groups the quests in the Quests and Campaign sections under the quest log heading each one sits under, which is its zone for most quests. Each zone collapses on its own. Off by default."]))

        w.zoneOrder = self:CreateRadioGroup(content, L["Zone Order"],
            ZONE_ORDERS,
            function() return DB().zoneHeaderOrder == "alpha" and "alpha" or "current" end,
            function(v) relayout("zoneHeaderOrder", v) end,
            nil, nil,
            L["Zone Order"],
            L["The order of the zones inside each section. Quests inside a zone still follow Sort Order on the Tracker tab."])
        zoneHeads:Add(w.zoneOrder)

        w.zoneSize = self:CreateSlider(content, L["Zone Header Size Offset"], -8, 12, 0.5,
            function() return DB().zoneHeaderSizeDelta or 2 end,
            function(v) relayout("zoneHeaderSizeDelta", v) end,
            L["Sizes the zone headers, added on top of the Font Size on the Text card. The default 2 sits between the quest titles and the section headers."])
        zoneHeads:Add(w.zoneSize)

        w.zoneClass = self:CreateCheckbox(content, L["Use class color for zone headers"],
            function() return DB().zoneHeaderColorUseClass end,
            function(v) relayout("zoneHeaderColorUseClass", v); syncDependents() end,
            L["Colors the zone headers with the class color of the character you are logged in on. Overrides the color below while it is on."])
        zoneHeads:Add(w.zoneClass)

        w.zoneColor = self:CreateColorPicker(content, L["Zone Header Color"],
            function() return DB().zoneHeaderColor end,
            function(v) relayout("zoneHeaderColor", v) end,
            L["Color of the zone names, their counts and their collapse signs. Gold by default."])
        zoneHeads:Add(w.zoneColor, DEPENDENT)

        w.zoneBarCheck = self:CreateCheckbox(content, L["Show zone header bars"],
            function() return DB().zoneHeaderBar end,
            function(v) relayout("zoneHeaderBar", v); syncDependents() end,
            L["Draws a colored bar behind each zone header, bright on the left and darker on the right. Off by default."])
        local zoneBarRow = zoneHeads:Add(w.zoneBarCheck)

        w.zoneBarPicker = self:CreateColorPicker(content, L["Bar Color"],
            function() return DB().zoneHeaderBarColor end,
            function(v) relayout("zoneHeaderBarColor", v) end,
            L["Brightest end of the bar gradient. The other end is the same color darkened."], true)
        satellite(self, zoneBarRow, w.zoneBarPicker)

        w.zoneLineCheck = self:CreateCheckbox(content, L["Show zone header divider"],
            function() return DB().zoneHeaderDivider end,
            function(v) relayout("zoneHeaderDivider", v); syncDependents() end,
            L["Draws a thin line under each zone header. Off by default."])
        local zoneLineRow = zoneHeads:Add(w.zoneLineCheck)

        w.zoneLinePicker = self:CreateColorPicker(content, L["Divider Line Color"],
            function() return DB().zoneHeaderDividerColor end,
            function(v) relayout("zoneHeaderDividerColor", v) end,
            L["Color of the thin line under each zone header."], true)
        satellite(self, zoneLineRow, w.zoneLinePicker)

        w.zoneIndent = self:CreateSlider(content, L["Quest Indent"], 0, 30, 1,
            function() return DB().zoneHeaderIndent or 8 end,
            function(v) relayout("zoneHeaderIndent", v) end,
            L["How far the quests under each zone header are moved in from the left edge."])
        zoneHeads:Add(w.zoneIndent)

        local spacing = stack(self:CreateGroup(content, L["Spacing"]))

        local spacingSlider = self:CreateSlider(content, L["Block Spacing"], 0, 12, 0.5,
            function() return DB().blockSpacing or 2 end,
            function(v) relayout("blockSpacing", v) end,
            L["Vertical gap between each entry and between sections."])
        spacing:Add(spacingSlider)

        local lineSpacingSlider = self:CreateSlider(content, L["Line Spacing"], 0, 12, 1,
            function() return DB().lineSpacing or 0 end,
            function(v) restyle("lineSpacing", v) end,
            L["Adds vertical space between a quest's objective lines, across the whole tracker. 0 keeps the default spacing."])
        spacing:Add(lineSpacingSlider)

        local headerSpacingSlider = self:CreateSlider(content, L["Header Spacing"], -2, 12, 1,
            function() return DB().headerSpacing or 0 end,
            function(v) restyle("headerSpacing", v) end,
            L["Adds or removes space around section headers and beneath each quest's title. 0 keeps the default spacing."])
        spacing:Add(headerSpacingSlider)

        local questRows = stack(self:CreateGroup(content, L["Quest Rows"]))

        questRows:Add(self:CreateRadioGroup(content, L["Row Layout"],
            LAYOUTS,
            function() return DB().blockLayout or "classic" end,
            function(v) restyle("blockLayout", v); syncDependents() end,
            300, 14,
            L["Row Layout"],
            L["How each quest is drawn in the tracker. |cffffffffPlain|r is the default look - text straight on the tracker background. |cffffffffCard|r gives every quest its own panel with a background and border, which makes long lists easier to read apart."]))

        w.cardColorPicker = self:CreateColorPicker(content, L["Background Color"],
            function() return DB().cardColor end,
            function(v) restyle("cardColor", v) end,
            L["Fill color behind each quest card. Only used while Row Layout is set to Card."], true)
        questRows:Add(w.cardColorPicker)

        w.cardBorderPicker = self:CreateColorPicker(content, L["Border Color"],
            function() return DB().cardBorderColor end,
            function(v) restyle("cardBorderColor", v) end,
            L["Outline color around each quest card. Only used while Row Layout is set to Card."], true)
        questRows:Add(w.cardBorderPicker)

        w.cardBorderSlider = self:CreateSlider(content, L["Border Thickness"], 0, 4, 1,
            function() return DB().cardBorderSize or 1 end,
            function(v) restyle("cardBorderSize", v) end,
            L["How thick the card outline is, in pixels. 0 hides the outline and leaves just the fill."])
        questRows:Add(w.cardBorderSlider)

        w.cardPaddingSlider = self:CreateSlider(content, L["Card Padding"], 2, 14, 1,
            function() return DB().cardPadding or 6 end,
            function(v) restyle("cardPadding", v) end,
            L["Breathing room between a card's edge and the text inside it. Larger values make taller cards."])
        questRows:Add(w.cardPaddingSlider)

        w.scenarioCardCheck = self:CreateCheckbox(content, L["Card behind the scenario panel"],
            function() return DB().scenarioCard ~= false end,
            function(v) relayout("scenarioCard", v) end,
            L["Draws the delve, dungeon, raid and world event panel at the top of the tracker on a card of its own, matching the quest cards below it. Only used while Row Layout is set to Card."])
        questRows:Add(w.scenarioCardCheck)

        w.tintCheck = self:CreateCheckbox(content, L["Tint cards by quest type"],
            function() return DB().cardTintByType end,
            function(v) restyle("cardTintByType", v); syncDependents() end,
            L["Gives campaign, legendary, dungeon and raid entries their own card color. Anything else uses the plain background color above."])
        questRows:Add(w.tintCheck)

        w.campaignTint = self:CreateColorPicker(content, L["Campaign"],
            function() return DB().cardTintCampaign end,
            function(v) restyle("cardTintCampaign", v) end,
            L["Card color for campaign entries. Needs Tint cards by quest type switched on."], true)
        questRows:Add(w.campaignTint, DEPENDENT)

        w.legendaryTint = self:CreateColorPicker(content, L["Legendary"],
            function() return DB().cardTintLegendary end,
            function(v) restyle("cardTintLegendary", v) end,
            L["Card color for legendary entries. Needs Tint cards by quest type switched on."], true)
        questRows:Add(w.legendaryTint, DEPENDENT)

        w.dungeonTint = self:CreateColorPicker(content, L["Dungeon"],
            function() return DB().cardTintDungeon end,
            function(v) restyle("cardTintDungeon", v) end,
            L["Card color for dungeon entries. Needs Tint cards by quest type switched on."], true)
        questRows:Add(w.dungeonTint, DEPENDENT)

        w.raidTint = self:CreateColorPicker(content, L["Raid"],
            function() return DB().cardTintRaid end,
            function(v) restyle("cardTintRaid", v) end,
            L["Card color for raid entries. Needs Tint cards by quest type switched on."], true)
        questRows:Add(w.raidTint, DEPENDENT)

        -- The quest row bars, the scenario criteria bars and the event widget bars share one
        -- style block. They all draw identically, so splitting the styling as well as the
        -- switches would mean setting the same seven controls three times over.
        local progress = stack(self:CreateGroup(content, L["Progress Bars"]))

        -- This key came off the Tracker tab and keeps the meaning it shipped with, so a
        -- profile that had already switched bars off is unchanged by the split. The two
        -- halves below are NEW keys, which is why neither can silently revert a stored choice.
        progress:Add(self:CreateCheckbox(content, L["Show progress bars"],
            function() return DB().showProgressBars ~= false end,
            function(v) restyle("showProgressBars", v); syncDependents() end,
            L["Draws a filled bar for objectives that report a percentage or a running total, the way the default tracker does, instead of a plain line of text. The two boxes under this pick which of them get one."]))

        w.pbQuests = self:CreateCheckbox(content, L["Quest Rows"],
            function() return DB().showQuestProgressBars ~= false end,
            function(v) restyle("showQuestProgressBars", v); syncDependents() end,
            L["Bars on quest, World Quest and achievement rows. The objective's own text is drawn above its bar, matching the default tracker."])
        progress:Add(w.pbQuests)

        w.pbScenario = self:CreateCheckbox(content, L["Scenario Criteria"],
            function() return DB().showScenarioProgressBars ~= false end,
            function(v) restyle("showScenarioProgressBars", v); syncDependents() end,
            L["Bars on the objective lines shown under a scenario or delve banner."])
        progress:Add(w.pbScenario)

        w.pbBgCheck = self:CreateCheckbox(content, L["Background"],
            function() local st = pbState(); return not (st and st.showBackground == false) end,
            function(v) pbSet("showBackground", v); syncDependents() end,
            L["Fills the unfinished part of the bar. Unticked, only the filled part is drawn."])
        local pbBgRow = progress:Add(w.pbBgCheck)

        w.pbBgPicker = self:CreateColorPicker(content, L["Background Color"],
            function() local st = pbState(); return st and st.backgroundColor end,
            function(v) pbSet("backgroundColor", v) end,
            L["Color and opacity of the unfilled part of the bar."], true)
        satellite(self, pbBgRow, w.pbBgPicker)

        w.pbBorderCheck = self:CreateCheckbox(content, L["Border"],
            function() local st = pbState(); return not (st and st.showBorder == false) end,
            function(v) pbSet("showBorder", v); syncDependents() end,
            L["Draws a one pixel border around the bar."])
        local pbBorderRow = progress:Add(w.pbBorderCheck)

        w.pbBorderPicker = self:CreateColorPicker(content, L["Border Color"],
            function() local st = pbState(); return st and st.borderColor end,
            function(v) pbSet("borderColor", v) end,
            L["Color and opacity of the bar's border."], true)
        satellite(self, pbBorderRow, w.pbBorderPicker)

        -- Keep this range and Media:ProgressBarHeight's clamp in step. CreateSlider's own
        -- suppress flag is what stops a stored value outside the range being written back on
        -- every tab view, so the two disagreeing is a silently clamped bar rather than a
        -- corrupted profile - but only while that flag survives.
        w.pbHeightSlider = self:CreateSlider(content, L["Bar Height"], 8, 24, 1,
            function() local st = pbState(); return (st and st.height) or 16 end,
            function(v) pbSet("height", v) end,
            L["How tall each progress bar is drawn."])
        progress:Add(w.pbHeightSlider)

        w.pbTexDD = self:CreateDropdown(content, L["Bar Texture"],
            function() return mediaOptions(ns:GetModule("Media"):GetStatusBarList()) end,
            function() local st = pbState(); return (st and st.barTexture) or "Blizzard" end,
            function(v) pbSet("barTexture", v) end,
            L["Sets the fill texture of the progress bars. Textures added by other media addons (such as SharedMedia, ElvUI, or Details) appear here too."],
            barTextureSwatch)
        progress:Add(w.pbTexDD)

        w.pbBarColorPicker = self:CreateColorPicker(content, L["Bar Color"],
            function() local st = pbState(); return st and st.barColor end,
            function(v) pbSet("barColor", v) end,
            L["Fill color and opacity of the bar itself."], true)
        progress:Add(w.pbBarColorPicker)

        local scrollBar = stack(self:CreateGroup(content, L["Scroll Bar"]))

        -- Heads its own group rather than sitting on the Tracker tab, where it switched off
        -- six controls the player could not see from there.
        scrollBar:Add(self:CreateCheckbox(content, L["Hide scroll bar"],
            function() return DB().hideScrollBar end,
            function(v) relayout("hideScrollBar", v); syncDependents() end,
            L["Removes the tracker's scroll bar entirely and scrolls with the mouse wheel instead. Everything else in this group styles that bar, so it all stops applying while this is on."]))

        w.sbCheck = self:CreateCheckbox(content, L["Scroll Bar Background"],
            function() return DB().scrollBarBg ~= false end,
            function(v) relayout("scrollBarBg", v); syncDependents() end,
            L["Draws a track behind the scroll bar so it stays visible over bright terrain."])
        local sbRow = scrollBar:Add(w.sbCheck)

        w.sbPicker = self:CreateColorPicker(content, L["Scroll Bar Color"],
            function() return DB().scrollBarBgColor end,
            function(v) relayout("scrollBarBgColor", v) end,
            L["Color and opacity of the scroll bar track."], true)
        satellite(self, sbRow, w.sbPicker)

        w.thumbSkinCheck = self:CreateCheckbox(content, L["Solid color thumb"],
            function() return DB().skinScrollBar end,
            function(v) relayout("skinScrollBar", v); syncDependents() end,
            L["Replaces the tracker scroll bar's textured thumb (the draggable block) with a flat single-color block. Use the Thumb Color and Thumb Width controls to style it. Off restores the stock Blizzard bar."])
        local thumbRow = scrollBar:Add(w.thumbSkinCheck)

        w.thumbColorPicker = self:CreateColorPicker(content, L["Thumb Color"],
            function() return DB().scrollBarThumbColor end,
            function(v) relayout("scrollBarThumbColor", v) end,
            L["Color and opacity of the draggable block. Only used while Solid color thumb is on."], true)
        satellite(self, thumbRow, w.thumbColorPicker)

        w.thumbWidthSlider = self:CreateSlider(content, L["Thumb Width"], 4, 16, 0.5,
            function() return DB().scrollBarThumbWidth or 8 end,
            function(v) relayout("scrollBarThumbWidth", v) end,
            L["How wide the draggable block is. Only used while Solid color thumb is on."])
        scrollBar:Add(w.thumbWidthSlider, DEPENDENT)

        w.hideArrowsCheck = self:CreateCheckbox(content, L["Hide scroll bar arrows"],
            function() return DB().hideScrollArrows end,
            function(v) relayout("hideScrollArrows", v) end,
            L["Hides the up and down arrow buttons at the ends of the tracker scroll bar. The bar still scrolls by dragging the thumb or using the mouse wheel."])
        scrollBar:Add(w.hideArrowsCheck)

        local scenario = stack(self:CreateGroup(content, L["Scenario"]))

        local scShadowRow = scenario:Add(self:CreateCheckbox(content, L["Text Shadow"],
            function() return DB().scenarioTextShadow ~= false end,
            function(v) bannerRestyle("scenarioTextShadow", v); syncDependents() end,
            L["Draws a drop-shadow behind the scenario / delve banner text (the Stage and name lines). This is SEPARATE from the Text Shadow above, which affects only the quest and objective text. The banner is styled on its own."]))

        w.scShadowPicker = self:CreateColorPicker(content, L["Shadow Color"],
            function() return DB().scenarioTextShadowColor end,
            function(v) bannerRestyle("scenarioTextShadowColor", v) end,
            L["Color and opacity of the banner's drop shadow."], true)
        satellite(self, scShadowRow, w.scShadowPicker)

        w.scShadowSizeSlider = self:CreateSlider(content, L["Shadow Size"], 1, 6, 0.5,
            function() return DB().scenarioTextShadowStrength or 1 end,
            function(v) bannerRestyle("scenarioTextShadowStrength", v) end,
            L["How far the scenario banner's drop-shadow is cast. Higher values give a larger, more pronounced shadow. Lower values keep it tight. Only applies while the Scenario Text Shadow above is on."])
        scenario:Add(w.scShadowSizeSlider, DEPENDENT)

        scenario:Add(self:CreateRadioGroup(content, L["Banner Alignment"],
            SCENARIO_ALIGN,
            function() return alignValue(DB().scenarioTextAlign) end,
            function(v) relayout("scenarioTextAlign", v) end,
            nil, nil,
            L["Banner Alignment"],
            L["Positions the scenario / delve banner within the tracker. Left lines it up with the quest text, Center keeps it centered (the default), and Right pushes it to the tracker's right edge."]))

        local scSizeSlider = self:CreateSlider(content, L["Banner Text Size"], -4, 6, 0.5,
            function() return DB().scenarioTextSizeDelta or 0 end,
            function(v) relayout("scenarioTextSizeDelta", v) end,
            L["Grows or shrinks the scenario / delve banner's Stage and name text. 0 is the default size. The banner artwork is a fixed size, so large values may overflow it."])
        scenario:Add(scSizeSlider)

        local scCritSizeSlider = self:CreateSlider(content, L["Criteria Text Size"], 8, 24, 0.5,
            function() return DB().scenarioFontSize or 13 end,
            function(v) relayout("scenarioFontSize", v) end,
            L["Sizes the scenario / delve objective (criteria) lines shown under the banner, separately from the Banner Text Size above. Raise it if the criteria text looks small next to your quest and World Quest text."])
        scenario:Add(scCritSizeSlider)

        -- Out of syncDependents: they dim on nothing.
        local scTitleSizeSlider = self:CreateSlider(content, L["Event Title Text Size"], -4, 12, 0.5,
            function() return DB().scenarioTitleSizeDelta or 4 end,
            function(v) relayout("scenarioTitleSizeDelta", v) end,
            L["Grows or shrinks the event title above the scenario / delve banner, the line naming the scenario itself. This value is added to the Font Size above, so 4 is the default and keeps the title sizing like a section heading. A long title wraps rather than trailing off, so large values make the panel taller."])
        scenario:Add(scTitleSizeSlider)

        scenario:Add(self:CreateColorPicker(content, L["Event Title Color"],
            function() return DB().scenarioTitleColor end,
            function(v) relayout("scenarioTitleColor", v) end,
            L["Color of the event title above the scenario / delve banner. It matches the Section Header Color by default but is set separately, because the scenario panel is not one of the tracker's sections."]))

        -- Whether the provider registered, which the TOC already decides per flavor. ns.Has
        -- is a CAPABILITY probe and reads true on Classic, where the client keeps the
        -- functions and ships no scenarios behind them.
        if ns.Has.ScenarioBonus and ns:GetModule("Registry"):Get("scenarios") then
            local bonus = stack(self:CreateGroup(content, L["Scenario Bonus Objectives"]))

            bonus:Add(self:CreateCheckbox(content, L["Show bonus objectives HUD"],
                function() local st = sbState(); return st and st.enabled end,
                function(v) ns:GetModule("ScenarioBonusHUD"):SetEnabled(v) end,
                L["Shows a small movable checklist of the extra bonus objectives that appear during some scenarios and delves, so you do not miss their rewards. Drag to move, right-click to lock or reset. Off by default."]))

            -- The HUD only draws inside a scenario or delve, so without this the position,
            -- scale and colors below can only be set somewhere the player cannot see them.
            bonus:Add(self:CreateButton(content, L["Test"], 120, function()
                ns:GetModule("ScenarioBonusHUD"):ToggleTest()
            end, L["Draws the HUD with two made-up bonus objectives so you can position and size it without being in a scenario or delve. Click again to clear it."]))

            -- This group sweeps itself rather than joining syncDependents below. That began as a
            -- hard constraint: the sweep once closed over 55 upvalues against Lua's limit of 60,
            -- past which this FILE stops compiling and the Appearance tab disappears. It now
            -- reads one table, and a dimmed control joins that table rather than becoming an
            -- upvalue of its own.
            local syncHUD

            local sbBgRow = bonus:Add(self:CreateCheckbox(content, L["Background"],
                function() local st = sbState(); return not (st and st.showBackground == false) end,
                function(v) sbSet("showBackground", v); syncHUD() end,
                L["Fills the HUD behind its text."]))

            -- The onClear below is what the border picker does not have: this key is the one
            -- with no DB default, so unset is a state the user can get back to.
            local sbBgPicker = self:CreateColorPicker(content, L["Background Color"],
                function() local st = sbState(); return st and st.backgroundColor end,
                function(v) sbSet("backgroundColor", v) end,
                L["Background color and opacity for the HUD. While this is unset it uses a plain black fill that fades slightly once locked."], true,
                function() sbSet("backgroundColor", nil) end)
            satellite(self, sbBgRow, sbBgPicker)

            local sbBorderRow = bonus:Add(self:CreateCheckbox(content, L["Border"],
                function() local st = sbState(); return not (st and st.showBorder == false) end,
                function(v) sbSet("showBorder", v); syncHUD() end,
                L["Draws a border around the HUD."]))

            local sbBorderPicker = self:CreateColorPicker(content, L["Border Color"],
                function() local st = sbState(); return st and st.borderColor end,
                function(v) sbSet("borderColor", v) end,
                L["Border color and opacity for the HUD."], true)
            satellite(self, sbBorderRow, sbBorderPicker)

            local sbScale = self:CreateSlider(content, L["HUD Scale"], 0.5, 2.0, 0.05,
                function() local st = sbState(); return (st and st.scale) or 1.0 end,
                function(v) ns:GetModule("ScenarioBonusHUD"):SetScale(v) end,
                L["Sizes the bonus objectives HUD."])
            bonus:Add(sbScale)

            -- Each picker dims on its own box, and nothing dims on the HUD's own switch. Test
            -- draws the HUD with that switch off, which is what the button is for, so the
            -- colors and the scale are reachable settings there rather than inert ones.
            syncHUD = function()
                local st = sbState() or {}
                self:SetDependent(sbBgPicker,     st.showBackground ~= false)
                self:SetDependent(sbBorderPicker, st.showBorder ~= false)
            end
            syncHUD()
            content._syncHUD = syncHUD
        end

        -- The whole feature lives here: its two toggles came off the Tracker tab so the
        -- switch that turns the bar on is not two tabs away from the controls that style it.
        local zone = stack(self:CreateGroup(content, L["Zone Progress Bar"]))

        zone:Add(self:CreateCheckbox(content, L["Show zone progress bar"],
            function() return DB().showZoneProgressBar end,
            function(v) ns:GetModule("ZoneProgressBar"):SetEnabled(v); syncDependents(); refreshPreview() end,
            L["Approximate questline progress."]))

        w.zbFloat = self:CreateCheckbox(content, L["Float as a movable bar"],
            function() return (DB().zoneProgressLocation or "floating") == "floating" end,
            function(v)
                ns:GetModule("ZoneProgressBar"):SetLocation(v and "floating" or "tracker")
                syncDependents()
                refreshPreview()
            end,
            L["Drag to move, right-click to lock or reset. Unticked, the bar becomes an ordinary tracker section instead and only Bar Texture and Bar Color still apply to it."])
        zone:Add(w.zbFloat)

        w.zbBgCheck = self:CreateCheckbox(content, L["Background"],
            function() local st = zbState(); return not (st and st.showBackground == false) end,
            function(v) zbSet("showBackground", v); syncDependents() end,
            L["Fills the floating bar behind its text."])
        local zbBgRow = zone:Add(w.zbBgCheck, DEPENDENT)

        -- Left unset by default so the backdrop keeps its locked/unlocked alpha fade. Once
        -- a color is picked that alpha is the user's, and the fade stops.
        w.zbBgPicker = self:CreateColorPicker(content, L["Background Color"],
            function() local st = zbState(); return st and st.backgroundColor end,
            function(v) zbSet("backgroundColor", v) end,
            L["Background color and opacity for the floating bar. While this is unset the bar uses a plain black fill that fades slightly once locked."], true,
            function() zbSet("backgroundColor", nil) end)
        satellite(self, zbBgRow, w.zbBgPicker)

        w.zbBorderCheck = self:CreateCheckbox(content, L["Border"],
            function() local st = zbState(); return not (st and st.showBorder == false) end,
            function(v) zbSet("showBorder", v); syncDependents() end,
            L["Draws a border around the floating bar."])
        local zbBorderRow = zone:Add(w.zbBorderCheck, DEPENDENT)

        w.zbBorderPicker = self:CreateColorPicker(content, L["Border Color"],
            function() local st = zbState(); return st and st.borderColor end,
            function(v) zbSet("borderColor", v) end,
            L["Border color and opacity for the floating bar."], true)
        satellite(self, zbBorderRow, w.zbBorderPicker)

        w.zbScaleSlider = self:CreateSlider(content, L["Zone Bar Scale"], 0.5, 2.0, 0.05,
            function() local st = zbState(); return (st and st.scale) or 1.0 end,
            function(v) zbSet("scale", v) end,
            L["Size of the floating bar. The docked section follows the tracker's own scale instead."])
        zone:Add(w.zbScaleSlider, DEPENDENT)

        w.zbFontDD = self:CreateDropdown(content, L["Font"],
            function()
                return mediaOptions(ns:GetModule("Media"):GetFontList(),
                                    { value = "", label = SAME_FONT })
            end,
            function() local st = zbState(); return (st and st.font) or "" end,
            function(v) zbSet("font", v ~= "" and v or nil) end,
            L["Font for the floating bar's zone name, count and percentage. The docked section uses the tracker font."],
            nil, nil, fontPreview)
        zone:Add(w.zbFontDD, DEPENDENT)

        w.zbHeaderPicker = self:CreateColorPicker(content, L["Header Color"],
            function() local st = zbState(); return st and st.headerColor end,
            function(v) zbSet("headerColor", v) end,
            L["Color of the zone name on the floating bar. The docked section uses the section header color."], true)
        zone:Add(w.zbHeaderPicker, DEPENDENT)

        w.zbCountPicker = self:CreateColorPicker(content, L["Count Color"],
            function() local st = zbState(); return st and st.countColor end,
            function(v) zbSet("countColor", v) end,
            L["Color of the completed-of-total count on the floating bar."], true)
        zone:Add(w.zbCountPicker, DEPENDENT)

        w.zbTexDD = self:CreateDropdown(content, L["Bar Texture"],
            function() return mediaOptions(ns:GetModule("Media"):GetStatusBarList()) end,
            function() local st = zbState(); return (st and st.barTexture) or "Blizzard" end,
            function(v) zbSet("barTexture", v, true) end,
            L["Sets the fill texture of the zone progress bar. Textures added by other media addons (such as SharedMedia, ElvUI, or Details) appear here too."],
            barTextureSwatch)
        zone:Add(w.zbTexDD)

        w.zbBarColorPicker = self:CreateColorPicker(content, L["Bar Color"],
            function() local st = zbState(); return st and st.barColor end,
            function(v) zbSet("barColor", v, true) end,
            L["Fill color and opacity of the bar itself."], true)
        zone:Add(w.zbBarColorPicker)

        syncDependents = function()
            local cfg = DB() or {}
            local zb  = zbState() or {}
            local function dim(control, on) self:SetDependent(control, on) end

            dim(w.shadowPicker,       cfg.textShadow)
            dim(w.shadowSizeSlider,   cfg.textShadow)
            dim(w.scShadowPicker,     cfg.scenarioTextShadow ~= false)
            dim(w.scShadowSizeSlider, cfg.scenarioTextShadow ~= false)

            -- Hide scroll bar kills this whole block, so these are two conditions deep
            -- rather than one. It heads the group itself and so is never dimmed.
            local bar = not cfg.hideScrollBar
            dim(w.sbCheck,          bar)
            dim(w.hideArrowsCheck,  bar)
            dim(w.thumbSkinCheck,   bar)
            dim(w.sbPicker,         bar and cfg.scrollBarBg ~= false)
            dim(w.thumbColorPicker, bar and cfg.skinScrollBar)
            dim(w.thumbWidthSlider, bar and cfg.skinScrollBar)

            dim(w.bgPicker,          cfg.showBackground)
            dim(w.borderPicker,      cfg.showBorder)
            dim(w.borderThickSlider, cfg.showBorder)

            dim(w.hbPicker,       cfg.headerBar)
            dim(w.hbStyle,        cfg.headerBar)
            dim(w.hbHeightSlider, cfg.headerBar)
            dim(w.hbSoftCheck,    cfg.headerBar)
            dim(w.hbSoftSlider,   cfg.headerBar and cfg.headerBarSoftEdges)

            -- Show zone headers heads the card and so is never dimmed.
            local zh = cfg.zoneHeaders
            dim(w.zoneOrder,      zh)
            dim(w.zoneSize,       zh)
            dim(w.zoneClass,      zh)
            dim(w.zoneColor,      zh and not cfg.zoneHeaderColorUseClass)
            dim(w.zoneBarCheck,   zh)
            dim(w.zoneBarPicker,  zh and cfg.zoneHeaderBar)
            dim(w.zoneLineCheck,  zh)
            dim(w.zoneLinePicker, zh and cfg.zoneHeaderDivider)
            dim(w.zoneIndent,     zh)

            dim(w.titlePicker,  ns.Util.TitleColorMode(cfg) == "custom")
            -- Inert until the mode gives it one color to use instead of green.
            dim(w.recolorCheck, ns.Util.EffectiveTitleColor(cfg) ~= nil)
            dim(w.headerPicker, not cfg.headerColorUseClass)

            local card = (cfg.blockLayout or "classic") == "card"
            dim(w.cardColorPicker,   card)
            dim(w.cardBorderPicker,  card)
            dim(w.cardBorderSlider,  card)
            dim(w.cardPaddingSlider, card)
            dim(w.scenarioCardCheck, card)
            dim(w.tintCheck,         card)
            local tint = card and cfg.cardTintByType
            dim(w.campaignTint,  tint)
            dim(w.legendaryTint, tint)
            dim(w.dungeonTint,   tint)
            dim(w.raidTint,      tint)

            -- Docked, the bar is drawn by the tracker, so only the two shared controls
            -- still reach it - everything else styles the floating frame alone.
            local on    = cfg.showZoneProgressBar
            local float = on and (cfg.zoneProgressLocation or "floating") == "floating"
            dim(w.zbFloat,          on)
            dim(w.zbTexDD,          on)
            dim(w.zbBarColorPicker, on)
            dim(w.zbBgCheck,      float)
            dim(w.zbBorderCheck,  float)
            dim(w.zbScaleSlider,  float)
            dim(w.zbFontDD,       float)
            dim(w.zbHeaderPicker, float)
            dim(w.zbCountPicker,  float)
            dim(w.zbBgPicker,     float and zb.showBackground ~= false)
            dim(w.zbBorderPicker, float and zb.showBorder ~= false)

            -- showProgressBars heads this group and so is never dimmed. The two half-switches
            -- are inert while it is off, and the STYLING is inert unless at least one half is
            -- actually drawing a bar - master on with both halves off leaves nothing on screen
            -- for a texture or a height to reach.
            local pb    = pbState() or {}
            local bars  = cfg.showProgressBars ~= false
            local drawn = bars and (cfg.showQuestProgressBars ~= false
                                    or cfg.showScenarioProgressBars ~= false)
            dim(w.pbQuests,          bars)
            dim(w.pbScenario,        bars)
            dim(w.pbBgCheck,         drawn)
            dim(w.pbBorderCheck,     drawn)
            dim(w.pbHeightSlider,    drawn)
            dim(w.pbTexDD,           drawn)
            dim(w.pbBarColorPicker,  drawn)
            dim(w.pbBgPicker,        drawn and pb.showBackground ~= false)
            dim(w.pbBorderPicker,    drawn and pb.showBorder ~= false)
        end
        syncDependents()
        content._syncDependents = syncDependents
    end,

    -- This sweep covers THIS tab's masters only. Options/TabTracker.lua owns a second,
    -- independent pair of its own, so two files hold dependency state and neither one is the
    -- whole picture. Re-running per view costs one pass over ~30 SetAlpha calls.
    refresh = function(_, content)
        if content._syncDependents then content._syncDependents() end
        if content._syncHUD then content._syncHUD() end
    end,
})
