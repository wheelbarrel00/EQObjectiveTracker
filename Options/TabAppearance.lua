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

-- Font, size, outline and shadow all feed the SetFont pass that pooled rows only redo
-- when the generation bumps, so every one of these setters must invalidate.
local function restyle(key, v)
    DB()[key] = v
    ns:GetModule("Row"):Invalidate()
    ns:GetModule("Tracker"):Render()
end

local function relayout(key, v)
    DB()[key] = v
    ns:GetModule("Tracker"):Render()
end

local function bannerRestyle(key, v)
    DB()[key] = v
    ns:GetModule("Scenario"):ApplyBannerShadow()
    ns:GetModule("Tracker"):Render()
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
end

local function barTextureSwatch(frame, name)
    if not frame.swatch then return end
    frame.swatch:SetTexture(ns:GetModule("Media"):GetStatusBarFile(name))
    frame.swatch:SetVertexColor(0.26, 0.42, 1.0)
end

-- EQ's two columns are nothing but a second anchor chain rooted this far right of the
-- first header, sharing its y. There is no column API on either side.
local COLUMN_X = 460

Options:RegisterTab({
    id    = "appearance",
    title = L["Appearance"],
    order = 30,
    build = function(self, content)
        -- Forward-declared because roughly half the controls below are dimmed by a master
        -- switch and every one of those masters has to be able to re-run the sweep.
        local syncDependents

        local h = self:CreateHeading(content, L["Appearance"])
        h:SetPoint("TOPLEFT", 8, -8)

        local fontDD = self:CreateDropdown(content, L["Font"],
            function() return mediaOptions(ns:GetModule("Media"):GetFontList()) end,
            function() return DB().font end,
            function(v) restyle("font", v) end,
            L["Fonts registered through LibSharedMedia, so anything from ElvUI or SharedMedia appears here too."],
            nil, nil, fontPreview)
        fontDD:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, self.GAP.tabHead)

        local sizeSlider = self:CreateSlider(content, L["Font Size"], 8, 24, 0.5,
            function() return DB().fontSize or 15 end,
            function(v) restyle("fontSize", v) end,
            L["Base size for objective text. Titles and headers offset from this."])
        sizeSlider:SetPoint("TOPLEFT", fontDD, "BOTTOMLEFT", 0, -16)

        local titleSizeSlider = self:CreateSlider(content, L["Title Size Offset"], -6, 12, 0.5,
            function() return DB().titleSizeDelta or 0 end,
            function(v) restyle("titleSizeDelta", v) end,
            L["Sizes quest and achievement titles separately from the objective text. This value is added to the Font Size above: 0 keeps titles the same size as the base font, positive makes them larger, negative smaller."])
        titleSizeSlider:SetPoint("TOPLEFT", sizeSlider, "BOTTOMLEFT", 0, -16)

        local headerSizeSlider = self:CreateSlider(content, L["Header Size Offset"], -8, 12, 0.5,
            function() return DB().headerSizeDelta or 4 end,
            function(v) relayout("headerSizeDelta", v) end,
            L["Sizes the section headers (Quests, Campaign, and so on) independently of the quest text. Added on top of the Font Size above: the default 4 keeps headers at their current size, lower shrinks them (handy on a low UI scale), higher enlarges them."])
        headerSizeSlider:SetPoint("TOPLEFT", titleSizeSlider, "BOTTOMLEFT", 0, -16)

        local outlineDD = self:CreateDropdown(content, L["Font Outline"],
            OUTLINES,
            function() return DB().fontOutline or "" end,
            function(v) restyle("fontOutline", v) end,
            L["Outlines keep small text legible over bright terrain."])
        outlineDD:SetPoint("TOPLEFT", headerSizeSlider, "BOTTOMLEFT", 0, -16)

        local shadowCheck = self:CreateCheckbox(content, L["Text Shadow"],
            function() return DB().textShadow end,
            function(v) restyle("textShadow", v); syncDependents() end,
            L["Draws a soft drop-shadow behind all tracker text so it stays readable over bright or busy backgrounds. Use Shadow Color to tint it and Shadow Size to set how far it's cast."])
        shadowCheck:SetPoint("TOPLEFT", outlineDD, "BOTTOMLEFT", 0, -16)

        local shadowPicker = self:CreateColorPicker(content, L["Shadow Color"],
            function() return DB().textShadowColor end,
            function(v) restyle("textShadowColor", v) end,
            L["Shadow color and opacity."], true)
        self:AlignSatelliteColumn({ shadowCheck, shadowPicker })

        local shadowSizeSlider = self:CreateSlider(content, L["Shadow Size"], 1, 6, 0.5,
            function() return DB().textShadowStrength or 2 end,
            function(v) restyle("textShadowStrength", v) end,
            L["How far the text drop-shadow is cast behind the letters. Higher values give a larger, more pronounced shadow. Lower values keep it tight. Only applies while Text Shadow is on."])
        shadowSizeSlider:SetPoint("TOPLEFT", shadowCheck, "BOTTOMLEFT", 0, -14)

        local scenarioHeader = self:CreateHeading(content, L["Scenario"])
        scenarioHeader:SetPoint("TOPLEFT", shadowSizeSlider, "BOTTOMLEFT", 0, self.GAP.aboveHead)

        local scShadowCheck = self:CreateCheckbox(content, L["Text Shadow"],
            function() return DB().scenarioTextShadow ~= false end,
            function(v) bannerRestyle("scenarioTextShadow", v); syncDependents() end,
            L["Draws a drop-shadow behind the scenario / delve banner text (the Stage and name lines). This is SEPARATE from the Text Shadow above, which affects only the quest and objective text. The banner is styled on its own."])
        scShadowCheck:SetPoint("TOPLEFT", scenarioHeader, "BOTTOMLEFT", 0, self.GAP.head)

        local scShadowPicker = self:CreateColorPicker(content, L["Shadow Color"],
            function() return DB().scenarioTextShadowColor end,
            function(v) bannerRestyle("scenarioTextShadowColor", v) end,
            L["Color and opacity of the banner's drop shadow."], true)
        self:AlignSatelliteColumn({ scShadowCheck, scShadowPicker })

        local scShadowSizeSlider = self:CreateSlider(content, L["Shadow Size"], 1, 6, 0.5,
            function() return DB().scenarioTextShadowStrength or 1 end,
            function(v) bannerRestyle("scenarioTextShadowStrength", v) end,
            L["How far the scenario banner's drop-shadow is cast. Higher values give a larger, more pronounced shadow. Lower values keep it tight. Only applies while the Scenario Text Shadow above is on."])
        scShadowSizeSlider:SetPoint("TOPLEFT", scShadowCheck, "BOTTOMLEFT", 0, -14)

        local scAlignDD = self:CreateDropdown(content, L["Banner Alignment"],
            SCENARIO_ALIGN,
            function() return alignValue(DB().scenarioTextAlign) end,
            function(v) relayout("scenarioTextAlign", v) end,
            L["Positions the scenario / delve banner within the tracker. Left lines it up with the quest text, Center keeps it centered (the default), and Right pushes it to the tracker's right edge."])
        scAlignDD:SetPoint("TOPLEFT", scShadowSizeSlider, "BOTTOMLEFT", 0, -16)

        local scSizeSlider = self:CreateSlider(content, L["Banner Text Size"], -4, 6, 0.5,
            function() return DB().scenarioTextSizeDelta or 0 end,
            function(v) relayout("scenarioTextSizeDelta", v) end,
            L["Grows or shrinks the scenario / delve banner's Stage and name text. 0 is the default size. The banner artwork is a fixed size, so large values may overflow it."])
        scSizeSlider:SetPoint("TOPLEFT", scAlignDD, "BOTTOMLEFT", 0, -16)

        local scCritSizeSlider = self:CreateSlider(content, L["Criteria Text Size"], 8, 24, 0.5,
            function() return DB().scenarioFontSize or 13 end,
            function(v) relayout("scenarioFontSize", v) end,
            L["Sizes the scenario / delve objective (criteria) lines shown under the banner, separately from the Banner Text Size above. Raise it if the criteria text looks small next to your quest and World Quest text."])
        scCritSizeSlider:SetPoint("TOPLEFT", scSizeSlider, "BOTTOMLEFT", 0, -16)

        -- Built here but anchored at the very bottom of this builder, because it re-homes
        -- the Tracker group under a section written further down. Screen order is not file
        -- order in EQ either, and the mirror is of the screen.
        local trackerHeader = self:CreateHeading(content, L["Tracker"])

        local skinsHeader = self:CreateHeading(content, L["Scroll Bar"])
        skinsHeader:SetPoint("TOPLEFT", scCritSizeSlider, "BOTTOMLEFT", 0, self.GAP.aboveHead)

        -- Heads its own group rather than sitting on the Tracker tab, where it switched off
        -- six controls the player could not see from there.
        local hideBarCheck = self:CreateCheckbox(content, L["Hide scroll bar"],
            function() return DB().hideScrollBar end,
            function(v) relayout("hideScrollBar", v); syncDependents() end,
            L["Removes the tracker's scroll bar entirely and scrolls with the mouse wheel instead. Everything else in this group styles that bar, so it all stops applying while this is on."])
        hideBarCheck:SetPoint("TOPLEFT", skinsHeader, "BOTTOMLEFT", 0, self.GAP.head)

        local sbCheck = self:CreateCheckbox(content, L["Scroll Bar Background"],
            function() return DB().scrollBarBg ~= false end,
            function(v) relayout("scrollBarBg", v); syncDependents() end,
            L["Draws a track behind the scroll bar so it stays visible over bright terrain."])
        sbCheck:SetPoint("TOPLEFT", hideBarCheck, "BOTTOMLEFT", 0, -2)

        local sbPicker = self:CreateColorPicker(content, L["Scroll Bar Color"],
            function() return DB().scrollBarBgColor end,
            function(v) relayout("scrollBarBgColor", v) end,
            L["Color and opacity of the scroll bar track."], true)

        local thumbSkinCheck = self:CreateCheckbox(content, L["Solid color thumb"],
            function() return DB().skinScrollBar end,
            function(v) relayout("skinScrollBar", v); syncDependents() end,
            L["Replaces the tracker scroll bar's textured thumb (the draggable block) with a flat single-color block. Use the Thumb Color and Thumb Width controls to style it. Off restores the stock Blizzard bar."])
        thumbSkinCheck:SetPoint("TOPLEFT", sbCheck, "BOTTOMLEFT", 0, -12)

        local thumbColorPicker = self:CreateColorPicker(content, L["Thumb Color"],
            function() return DB().scrollBarThumbColor end,
            function(v) relayout("scrollBarThumbColor", v) end,
            L["Color and opacity of the draggable block. Only used while Solid color thumb is on."], true)
        self:AlignSatelliteColumn({ sbCheck, sbPicker }, { thumbSkinCheck, thumbColorPicker })
        self:AlignPickerColumn(sbPicker, thumbColorPicker)

        local thumbWidthSlider = self:CreateSlider(content, L["Thumb Width"], 4, 16, 0.5,
            function() return DB().scrollBarThumbWidth or 8 end,
            function(v) relayout("scrollBarThumbWidth", v) end,
            L["How wide the draggable block is. Only used while Solid color thumb is on."])
        thumbWidthSlider:SetPoint("TOPLEFT", thumbSkinCheck, "BOTTOMLEFT", 0, -14)

        local hideArrowsCheck = self:CreateCheckbox(content, L["Hide scroll bar arrows"],
            function() return DB().hideScrollArrows end,
            function(v) relayout("hideScrollArrows", v) end,
            L["Hides the up and down arrow buttons at the ends of the tracker scroll bar. The bar still scrolls by dragging the thumb or using the mouse wheel."])
        hideArrowsCheck:SetPoint("TOPLEFT", thumbWidthSlider, "BOTTOMLEFT", 0, -14)

        local bgCheck = self:CreateCheckbox(content, L["Background"],
            function() return DB().showBackground end,
            function(v) relayout("showBackground", v); syncDependents() end,
            L["Fills the tracker behind the text. Useful over bright terrain."])
        bgCheck:SetPoint("TOPLEFT", trackerHeader, "BOTTOMLEFT", 0, self.GAP.head)

        local bgPicker = self:CreateColorPicker(content, L["Background Color"],
            function() return DB().backgroundColor end,
            function(v) relayout("backgroundColor", v) end,
            L["Background color and opacity."], true)

        local borderCheck = self:CreateCheckbox(content, L["Border"],
            function() return DB().showBorder end,
            function(v) relayout("showBorder", v); syncDependents() end,
            L["Draws a border around the tracker."])
        borderCheck:SetPoint("TOPLEFT", bgCheck, "BOTTOMLEFT", 0, -10)

        local borderPicker = self:CreateColorPicker(content, L["Border Color"],
            function() return DB().borderColor end,
            function(v) relayout("borderColor", v) end,
            L["Border color and opacity."], true)

        local borderThickSlider = self:CreateSlider(content, L["Border Thickness"], 1, 5, 0.5,
            function() return DB().borderSize or 1 end,
            function(v) relayout("borderSize", v) end,
            L["Border thickness in pixels."])
        borderThickSlider:SetPoint("TOPLEFT", borderCheck, "BOTTOMLEFT", 0, -20)

        local hbBarHeader = self:CreateHeading(content, L["Header Bar"])
        hbBarHeader:SetPoint("TOPLEFT", borderThickSlider, "BOTTOMLEFT", 0, self.GAP.aboveHead)

        local hbCheck = self:CreateCheckbox(content, L["Show header bars"],
            function() return DB().headerBar end,
            function(v) relayout("headerBar", v); syncDependents() end,
            L["Draws a colored gradient bar behind each section header (Quests, Campaign, World Quests, and so on), for a look closer to the default Blizzard tracker. Off by default."])
        hbCheck:SetPoint("TOPLEFT", hbBarHeader, "BOTTOMLEFT", 0, self.GAP.head)

        local hbPicker = self:CreateColorPicker(content, L["Bar Color"],
            function() return DB().headerBarColor end,
            function(v) relayout("headerBarColor", v) end,
            L["Brightest end of the bar gradient. The other end is the same color darkened."], true)
        -- Three sections apart, but they share a left edge, so one swatch column reads as
        -- one column. EQ aligns these together too. "Show header bars" is the widest label of
        -- the three and the one that used to run under its own swatch.
        self:AlignSatelliteColumn({ bgCheck, bgPicker }, { borderCheck, borderPicker },
                                  { hbCheck, hbPicker })
        self:AlignPickerColumn(bgPicker, borderPicker, hbPicker)

        local hbStyleDD = self:CreateDropdown(content, L["Bar Style"],
            BAR_STYLES,
            function() return (DB().headerBarStyle or 1) == 2 and 2 or 1 end,
            function(v) relayout("headerBarStyle", v) end,
            L["Header Bar 1 is a horizontal gradient (bright on the left, dark on the right). Header Bar 2 is a vertical gradient (bright at the top, dark at the bottom). Bar Color, Bar Height, and Soft edges all apply to whichever style you pick."])
        hbStyleDD:SetWidth(150)
        hbStyleDD:SetPoint("TOPLEFT", hbCheck, "BOTTOMLEFT", 0, -14)

        local hbSoftCheck = self:CreateCheckbox(content, L["Soft edges"],
            function() return DB().headerBarSoftEdges end,
            function(v) relayout("headerBarSoftEdges", v); syncDependents() end,
            L["Feathers the top, left, and right edges of the header bar so it blends into the UI instead of sitting in a hard box. The gradient color is unchanged. Only applies while Header bars is on. Off by default."])
        hbSoftCheck:SetPoint("TOPLEFT", hbStyleDD, "BOTTOMLEFT", 0, self.GAP.head)

        local hbHeightSlider = self:CreateSlider(content, L["Bar Height"], 6, 26, 0.5,
            function() return DB().headerBarHeight or 22 end,
            function(v) relayout("headerBarHeight", v) end,
            L["How tall the section-header bar is. The bar is centered on the header row, so larger values fill more of it."])
        hbHeightSlider:SetPoint("TOPLEFT", hbSoftCheck, "BOTTOMLEFT", 0, -14)

        local hbSoftSlider = self:CreateSlider(content, L["Edge Softness"], 1, 10, 0.5,
            function() return DB().headerBarSoftEdgeStrength or 10 end,
            function(v) relayout("headerBarSoftEdgeStrength", v) end,
            L["How soft the header bar's feathered edges are when Soft edges is on. Higher is softer, lower tightens toward a hard edge."])
        hbSoftSlider:SetPoint("TOPLEFT", hbHeightSlider, "BOTTOMLEFT", 0, -14)

        local colorsHeader = self:CreateHeading(content, L["Colors & Dimensions"])
        colorsHeader:SetPoint("TOPLEFT", h, "TOPLEFT", COLUMN_X, 0)

        local resetBtn = self:CreateButton(content, L["Reset to Defaults"], 160, function()
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
        resetBtn:SetSize(160, 24)
        resetBtn:SetPoint("LEFT", colorsHeader, "LEFT", 320, 0)

        -- onClear rather than a button of our own: the helper hides it while the color is
        -- unset, so a live Clear no longer sits beside a swatch it cannot change.
        local titlePicker = self:CreateColorPicker(content, L["Quest Title Color Override"],
            function() return DB().titleColorOverride end,
            function(v)
                local had = DB().titleColorOverride ~= nil
                restyle("titleColorOverride", v)
                -- Only when the nil state actually changes, in either direction. The wheel
                -- fires this setter every frame of a drag, and the sweep is ~40 SetAlpha
                -- calls. Cancel comes back through here with the previous value, so testing
                -- only for the arriving transition left the control undimmed and inert.
                if had ~= (v ~= nil) then syncDependents() end
            end,
            L["When cleared, falls back to difficulty coloring or default yellow."],
            false,
            function()
                restyle("titleColorOverride", nil)
                syncDependents()
            end)
        titlePicker:SetPoint("TOPLEFT", colorsHeader, "BOTTOMLEFT", 0, self.GAP.tabHead)

        local titleClassCheck = self:CreateCheckbox(content, L["Use class color for titles"],
            function() return DB().titleColorUseClass end,
            function(v) restyle("titleColorUseClass", v); syncDependents() end,
            L["Colors quest, achievement, and endeavor titles with the class color of the character you are currently logged in on. Overrides the color above while it is on. Off by default."])
        titleClassCheck:SetPoint("TOPLEFT", titlePicker, "BOTTOMLEFT", 0, -10)

        local recolorCheck = self:CreateCheckbox(content, L["Use title color for completed quests"],
            function() return DB().overrideCompleteGreen ~= false end,
            function(v) restyle("overrideCompleteGreen", v) end,
            L["Instead of green."])
        recolorCheck:SetPoint("TOPLEFT", titleClassCheck, "BOTTOMLEFT", 0, -8)

        local headerPicker = self:CreateColorPicker(content, L["Section Header Color"],
            function() return DB().headerColor end,
            function(v) relayout("headerColor", v) end,
            L["Color of the Quests, Campaign and World Quests headings."])
        headerPicker:SetPoint("TOPLEFT", recolorCheck, "BOTTOMLEFT", 0, -16)

        local headerClassCheck = self:CreateCheckbox(content, L["Use class color for headers"],
            function() return DB().headerColorUseClass end,
            function(v) relayout("headerColorUseClass", v); syncDependents() end,
            L["Colors the section headers (Quests, Campaign, and so on) with the class color of the character you are currently logged in on. Overrides the color above while it is on. Off by default."])
        headerClassCheck:SetPoint("TOPLEFT", headerPicker, "BOTTOMLEFT", 0, -10)

        local dividerPicker = self:CreateColorPicker(content, L["Divider Line Color"],
            function() return DB().headerDividerColor end,
            function(v) relayout("headerDividerColor", v) end,
            L["Sets the color of the thin line under each section header. Defaults to the original gold."], true)
        dividerPicker:SetPoint("TOPLEFT", headerClassCheck, "BOTTOMLEFT", 0, -14)
        self:AlignPickerColumn(titlePicker, headerPicker, dividerPicker)

        local scaleSlider = self:CreateSlider(content, L["Tracker Scale"], 0.7, 1.5, 0.05,
            function() return DB().scale or 1 end,
            function(v)
                DB().scale = v
                ns:GetModule("Tracker"):ApplyScale()
            end,
            L["Scales the whole tracker. Takes effect immediately out of combat."])
        scaleSlider:SetPoint("TOPLEFT", dividerPicker, "BOTTOMLEFT", 0, -32)

        local spacingSlider = self:CreateSlider(content, L["Block Spacing"], 0, 12, 0.5,
            function() return DB().blockSpacing or 2 end,
            function(v) relayout("blockSpacing", v) end,
            L["Vertical gap between each entry and between sections."])
        spacingSlider:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", 0, -16)

        local lineSpacingSlider = self:CreateSlider(content, L["Line Spacing"], 0, 12, 1,
            function() return DB().lineSpacing or 0 end,
            function(v) restyle("lineSpacing", v) end,
            L["Adds vertical space between a quest's objective lines, across the whole tracker. 0 keeps the default spacing."])
        lineSpacingSlider:SetPoint("TOPLEFT", spacingSlider, "BOTTOMLEFT", 0, -16)

        local headerSpacingSlider = self:CreateSlider(content, L["Header Spacing"], -2, 12, 1,
            function() return DB().headerSpacing or 0 end,
            function(v) restyle("headerSpacing", v) end,
            L["Adds or removes space around section headers and beneath each quest's title. 0 keeps the default spacing."])
        headerSpacingSlider:SetPoint("TOPLEFT", lineSpacingSlider, "BOTTOMLEFT", 0, -16)

        local cardHeader = self:CreateHeading(content, L["Quest Rows"])
        cardHeader:SetPoint("TOPLEFT", headerSpacingSlider, "BOTTOMLEFT", 0, self.GAP.aboveHead)

        local layout = self:CreateRadioGroup(content, L["Row Layout"],
            LAYOUTS,
            function() return DB().blockLayout or "classic" end,
            function(v) restyle("blockLayout", v); syncDependents() end,
            300, 14,
            L["Row Layout"],
            L["How each quest is drawn in the tracker. |cffffffffPlain|r is the default look - text straight on the tracker background. |cffffffffCard|r gives every quest its own panel with a background and border, which makes long lists easier to read apart."])
        layout:SetPoint("TOPLEFT", cardHeader, "BOTTOMLEFT", 0, self.GAP.head)

        local cardColorPicker = self:CreateColorPicker(content, L["Background Color"],
            function() return DB().cardColor end,
            function(v) restyle("cardColor", v) end,
            L["Fill color behind each quest card. Only used while Row Layout is set to Card."], true)
        cardColorPicker:SetPoint("TOPLEFT", layout, "BOTTOMLEFT", 0, -16)

        local cardBorderPicker = self:CreateColorPicker(content, L["Border Color"],
            function() return DB().cardBorderColor end,
            function(v) restyle("cardBorderColor", v) end,
            L["Outline color around each quest card. Only used while Row Layout is set to Card."], true)
        cardBorderPicker:SetPoint("TOPLEFT", cardColorPicker, "BOTTOMLEFT", 0, -10)
        self:AlignPickerColumn(cardColorPicker, cardBorderPicker)

        local cardBorderSlider = self:CreateSlider(content, L["Border Thickness"], 0, 4, 1,
            function() return DB().cardBorderSize or 1 end,
            function(v) restyle("cardBorderSize", v) end,
            L["How thick the card outline is, in pixels. 0 hides the outline and leaves just the fill."])
        cardBorderSlider:SetPoint("TOPLEFT", cardBorderPicker, "BOTTOMLEFT", 0, -20)

        local cardPaddingSlider = self:CreateSlider(content, L["Card Padding"], 2, 14, 1,
            function() return DB().cardPadding or 6 end,
            function(v) restyle("cardPadding", v) end,
            L["Breathing room between a card's edge and the text inside it. Larger values make taller cards."])
        cardPaddingSlider:SetPoint("TOPLEFT", cardBorderSlider, "BOTTOMLEFT", 0, -16)

        local scenarioCardCheck = self:CreateCheckbox(content, L["Card behind the scenario panel"],
            function() return DB().scenarioCard ~= false end,
            function(v) relayout("scenarioCard", v) end,
            L["Draws the delve, dungeon, raid and world event panel at the top of the tracker on a card of its own, matching the quest cards below it. Only used while Row Layout is set to Card."])
        scenarioCardCheck:SetPoint("TOPLEFT", cardPaddingSlider, "BOTTOMLEFT", 0, -16)

        local tintCheck = self:CreateCheckbox(content, L["Tint cards by quest type"],
            function() return DB().cardTintByType end,
            function(v) restyle("cardTintByType", v); syncDependents() end,
            L["Gives campaign, legendary, dungeon and raid entries their own card color. Anything else uses the plain background color above."])
        tintCheck:SetPoint("TOPLEFT", scenarioCardCheck, "BOTTOMLEFT", 0, -16)

        local campaignTint = self:CreateColorPicker(content, L["Campaign"],
            function() return DB().cardTintCampaign end,
            function(v) restyle("cardTintCampaign", v) end,
            L["Card color for campaign entries. Needs Tint cards by quest type switched on."], true)
        campaignTint:SetPoint("TOPLEFT", tintCheck, "BOTTOMLEFT", 0, -10)

        local legendaryTint = self:CreateColorPicker(content, L["Legendary"],
            function() return DB().cardTintLegendary end,
            function(v) restyle("cardTintLegendary", v) end,
            L["Card color for legendary entries. Needs Tint cards by quest type switched on."], true)
        legendaryTint:SetPoint("TOPLEFT", campaignTint, "BOTTOMLEFT", 0, -10)

        local dungeonTint = self:CreateColorPicker(content, L["Dungeon"],
            function() return DB().cardTintDungeon end,
            function(v) restyle("cardTintDungeon", v) end,
            L["Card color for dungeon entries. Needs Tint cards by quest type switched on."], true)
        dungeonTint:SetPoint("TOPLEFT", legendaryTint, "BOTTOMLEFT", 0, -10)

        local raidTint = self:CreateColorPicker(content, L["Raid"],
            function() return DB().cardTintRaid end,
            function(v) restyle("cardTintRaid", v) end,
            L["Card color for raid entries. Needs Tint cards by quest type switched on."], true)
        raidTint:SetPoint("TOPLEFT", dungeonTint, "BOTTOMLEFT", 0, -10)
        self:AlignPickerColumn(campaignTint, legendaryTint, dungeonTint, raidTint)

        -- The whole feature lives here: its two toggles came off the Tracker tab so the
        -- switch that turns the bar on is not two tabs away from the controls that style it.
        local zbHeader = self:CreateHeading(content, L["Zone Progress Bar"])
        zbHeader:SetPoint("TOPLEFT", raidTint, "BOTTOMLEFT", 0, self.GAP.aboveHead)

        local zbEnable = self:CreateCheckbox(content, L["Show zone progress bar"],
            function() return DB().showZoneProgressBar end,
            function(v) ns:GetModule("ZoneProgressBar"):SetEnabled(v); syncDependents() end,
            L["Approximate questline progress."])
        zbEnable:SetPoint("TOPLEFT", zbHeader, "BOTTOMLEFT", 0, self.GAP.head)

        local zbFloat = self:CreateCheckbox(content, L["Float as a movable bar"],
            function() return (DB().zoneProgressLocation or "floating") == "floating" end,
            function(v)
                ns:GetModule("ZoneProgressBar"):SetLocation(v and "floating" or "tracker")
                syncDependents()
            end,
            L["Drag to move, right-click to lock or reset. Unticked, the bar becomes an ordinary tracker section instead and only Bar Texture and Bar Color still apply to it."])
        zbFloat:SetPoint("TOPLEFT", zbEnable, "BOTTOMLEFT", 0, -2)

        local zbBgCheck = self:CreateCheckbox(content, L["Background"],
            function() local st = zbState(); return not (st and st.showBackground == false) end,
            function(v) zbSet("showBackground", v); syncDependents() end,
            L["Fills the floating bar behind its text."])
        zbBgCheck:SetPoint("TOPLEFT", zbFloat, "BOTTOMLEFT", 0, -2)

        -- Left unset by default so the backdrop keeps its locked/unlocked alpha fade. Once
        -- a color is picked that alpha is the user's, and the fade stops.
        local zbBgPicker = self:CreateColorPicker(content, L["Background Color"],
            function() local st = zbState(); return st and st.backgroundColor end,
            function(v) zbSet("backgroundColor", v) end,
            L["Background color and opacity for the floating bar. While this is unset the bar uses a plain black fill that fades slightly once locked."], true,
            function() zbSet("backgroundColor", nil) end)

        local zbBorderCheck = self:CreateCheckbox(content, L["Border"],
            function() local st = zbState(); return not (st and st.showBorder == false) end,
            function(v) zbSet("showBorder", v); syncDependents() end,
            L["Draws a border around the floating bar."])
        zbBorderCheck:SetPoint("TOPLEFT", zbBgCheck, "BOTTOMLEFT", 0, -2)

        local zbBorderPicker = self:CreateColorPicker(content, L["Border Color"],
            function() local st = zbState(); return st and st.borderColor end,
            function(v) zbSet("borderColor", v) end,
            L["Border color and opacity for the floating bar."], true)
        self:AlignSatelliteColumn({ zbBgCheck, zbBgPicker }, { zbBorderCheck, zbBorderPicker })
        self:AlignPickerColumn(zbBgPicker, zbBorderPicker)

        local zbScaleSlider = self:CreateSlider(content, L["Zone Bar Scale"], 0.5, 2.0, 0.05,
            function() local st = zbState(); return (st and st.scale) or 1.0 end,
            function(v) zbSet("scale", v) end,
            L["Size of the floating bar. The docked section follows the tracker's own scale instead."])
        zbScaleSlider:SetPoint("TOPLEFT", zbBorderCheck, "BOTTOMLEFT", 0, -14)

        local zbFontDD = self:CreateDropdown(content, L["Font"],
            function()
                return mediaOptions(ns:GetModule("Media"):GetFontList(),
                                    { value = "", label = SAME_FONT })
            end,
            function() local st = zbState(); return (st and st.font) or "" end,
            function(v) zbSet("font", v ~= "" and v or nil) end,
            L["Font for the floating bar's zone name, count and percentage. The docked section uses the tracker font."],
            nil, nil, fontPreview)
        zbFontDD:SetPoint("TOPLEFT", zbScaleSlider, "BOTTOMLEFT", 0, -14)

        local zbTexDD = self:CreateDropdown(content, L["Bar Texture"],
            function() return mediaOptions(ns:GetModule("Media"):GetStatusBarList()) end,
            function() local st = zbState(); return (st and st.barTexture) or "Blizzard" end,
            function(v) zbSet("barTexture", v, true) end,
            L["Sets the fill texture of the zone progress bar. Textures added by other media addons (such as SharedMedia, ElvUI, or Details) appear here too."],
            barTextureSwatch)
        zbTexDD:SetPoint("TOPLEFT", zbFontDD, "BOTTOMLEFT", 0, -14)

        local zbBarColorPicker = self:CreateColorPicker(content, L["Bar Color"],
            function() local st = zbState(); return st and st.barColor end,
            function(v) zbSet("barColor", v, true) end,
            L["Fill color and opacity of the bar itself."], true)
        zbBarColorPicker:SetPoint("TOPLEFT", zbTexDD, "BOTTOMLEFT", 0, -16)

        local zbHeaderPicker = self:CreateColorPicker(content, L["Header Color"],
            function() local st = zbState(); return st and st.headerColor end,
            function(v) zbSet("headerColor", v) end,
            L["Color of the zone name on the floating bar. The docked section uses the section header color."], true)
        zbHeaderPicker:SetPoint("TOPLEFT", zbBarColorPicker, "BOTTOMLEFT", 0, -10)

        local zbCountPicker = self:CreateColorPicker(content, L["Count Color"],
            function() local st = zbState(); return st and st.countColor end,
            function(v) zbSet("countColor", v) end,
            L["Color of the completed-of-total count on the floating bar."], true)
        zbCountPicker:SetPoint("TOPLEFT", zbHeaderPicker, "BOTTOMLEFT", 0, -10)
        self:AlignPickerColumn(zbBarColorPicker, zbHeaderPicker, zbCountPicker)

        -- The quest row bars, the scenario criteria bars and the event widget bars share one
        -- style block. They all draw identically, so splitting the styling as well as the
        -- switches would mean setting the same seven controls three times over.
        local pbHeader = self:CreateHeading(content, L["Progress Bars"])
        pbHeader:SetPoint("TOPLEFT", zbCountPicker, "BOTTOMLEFT", 0, self.GAP.aboveHead)

        -- This key came off the Tracker tab and keeps the meaning it shipped with, so a
        -- profile that had already switched bars off is unchanged by the split. The two
        -- halves below are NEW keys, which is why neither can silently revert a stored choice.
        local pbEnable = self:CreateCheckbox(content, L["Show progress bars"],
            function() return DB().showProgressBars ~= false end,
            function(v) restyle("showProgressBars", v); syncDependents() end,
            L["Draws a filled bar for objectives that report a percentage or a running total, the way the default tracker does, instead of a plain line of text. The two boxes under this pick which of them get one."])
        pbEnable:SetPoint("TOPLEFT", pbHeader, "BOTTOMLEFT", 0, self.GAP.head)

        local pbQuests = self:CreateCheckbox(content, L["Quest Rows"],
            function() return DB().showQuestProgressBars ~= false end,
            function(v) restyle("showQuestProgressBars", v); syncDependents() end,
            L["Bars on quest, World Quest and achievement rows. The objective's own text is drawn above its bar, matching the default tracker."])
        pbQuests:SetPoint("TOPLEFT", pbEnable, "BOTTOMLEFT", 0, -2)

        local pbScenario = self:CreateCheckbox(content, L["Scenario Criteria"],
            function() return DB().showScenarioProgressBars ~= false end,
            function(v) restyle("showScenarioProgressBars", v); syncDependents() end,
            L["Bars on the objective lines shown under a scenario or delve banner."])
        pbScenario:SetPoint("TOPLEFT", pbQuests, "BOTTOMLEFT", 0, -2)

        local pbBgCheck = self:CreateCheckbox(content, L["Background"],
            function() local st = pbState(); return not (st and st.showBackground == false) end,
            function(v) pbSet("showBackground", v); syncDependents() end,
            L["Fills the unfinished part of the bar. Unticked, only the filled part is drawn."])
        pbBgCheck:SetPoint("TOPLEFT", pbScenario, "BOTTOMLEFT", 0, -2)

        local pbBgPicker = self:CreateColorPicker(content, L["Background Color"],
            function() local st = pbState(); return st and st.backgroundColor end,
            function(v) pbSet("backgroundColor", v) end,
            L["Color and opacity of the unfilled part of the bar."], true)

        local pbBorderCheck = self:CreateCheckbox(content, L["Border"],
            function() local st = pbState(); return not (st and st.showBorder == false) end,
            function(v) pbSet("showBorder", v); syncDependents() end,
            L["Draws a one pixel border around the bar."])
        pbBorderCheck:SetPoint("TOPLEFT", pbBgCheck, "BOTTOMLEFT", 0, -2)

        local pbBorderPicker = self:CreateColorPicker(content, L["Border Color"],
            function() local st = pbState(); return st and st.borderColor end,
            function(v) pbSet("borderColor", v) end,
            L["Color and opacity of the bar's border."], true)
        self:AlignSatelliteColumn({ pbBgCheck, pbBgPicker }, { pbBorderCheck, pbBorderPicker })
        self:AlignPickerColumn(pbBgPicker, pbBorderPicker)

        -- Keep this range and Media:ProgressBarHeight's clamp in step. CreateSlider's own
        -- suppress flag is what stops a stored value outside the range being written back on
        -- every tab view, so the two disagreeing is a silently clamped bar rather than a
        -- corrupted profile - but only while that flag survives.
        local pbHeightSlider = self:CreateSlider(content, L["Bar Height"], 8, 24, 1,
            function() local st = pbState(); return (st and st.height) or 16 end,
            function(v) pbSet("height", v) end,
            L["How tall each progress bar is drawn."])
        pbHeightSlider:SetPoint("TOPLEFT", pbBorderCheck, "BOTTOMLEFT", 0, -14)

        local pbTexDD = self:CreateDropdown(content, L["Bar Texture"],
            function() return mediaOptions(ns:GetModule("Media"):GetStatusBarList()) end,
            function() local st = pbState(); return (st and st.barTexture) or "Blizzard" end,
            function(v) pbSet("barTexture", v) end,
            L["Sets the fill texture of the progress bars. Textures added by other media addons (such as SharedMedia, ElvUI, or Details) appear here too."],
            barTextureSwatch)
        pbTexDD:SetPoint("TOPLEFT", pbHeightSlider, "BOTTOMLEFT", 0, -14)

        local pbBarColorPicker = self:CreateColorPicker(content, L["Bar Color"],
            function() local st = pbState(); return st and st.barColor end,
            function(v) pbSet("barColor", v) end,
            L["Fill color and opacity of the bar itself."], true)
        pbBarColorPicker:SetPoint("TOPLEFT", pbTexDD, "BOTTOMLEFT", 0, -16)

        trackerHeader:SetPoint("TOPLEFT", hideArrowsCheck, "BOTTOMLEFT", 0, self.GAP.aboveHead)

        syncDependents = function()
            local cfg = DB() or {}
            local zb  = zbState() or {}
            local function dim(control, on) self:SetDependent(control, on) end

            dim(shadowPicker,       cfg.textShadow)
            dim(shadowSizeSlider,   cfg.textShadow)
            dim(scShadowPicker,     cfg.scenarioTextShadow ~= false)
            dim(scShadowSizeSlider, cfg.scenarioTextShadow ~= false)

            -- Hide scroll bar kills this whole block, so these are two conditions deep
            -- rather than one. It heads the group itself and so is never dimmed.
            local bar = not cfg.hideScrollBar
            dim(sbCheck,          bar)
            dim(hideArrowsCheck,  bar)
            dim(thumbSkinCheck,   bar)
            dim(sbPicker,         bar and cfg.scrollBarBg ~= false)
            dim(thumbColorPicker, bar and cfg.skinScrollBar)
            dim(thumbWidthSlider, bar and cfg.skinScrollBar)

            dim(bgPicker,         cfg.showBackground)
            dim(borderPicker,     cfg.showBorder)
            dim(borderThickSlider, cfg.showBorder)

            dim(hbPicker,       cfg.headerBar)
            dim(hbStyleDD,      cfg.headerBar)
            dim(hbHeightSlider, cfg.headerBar)
            dim(hbSoftCheck,    cfg.headerBar)
            dim(hbSoftSlider,   cfg.headerBar and cfg.headerBarSoftEdges)

            -- The class color overrides the picker above it rather than the other way
            -- round, so the picker is what goes dim.
            dim(titlePicker,  not cfg.titleColorUseClass)
            -- Inert until one of those two gives it a color to use instead of green.
            dim(recolorCheck, cfg.titleColorOverride ~= nil or cfg.titleColorUseClass)
            dim(headerPicker, not cfg.headerColorUseClass)

            local card = (cfg.blockLayout or "classic") == "card"
            dim(cardColorPicker,  card)
            dim(cardBorderPicker, card)
            dim(cardBorderSlider, card)
            dim(cardPaddingSlider, card)
            dim(scenarioCardCheck, card)
            dim(tintCheck,        card)
            local tint = card and cfg.cardTintByType
            dim(campaignTint,  tint)
            dim(legendaryTint, tint)
            dim(dungeonTint,   tint)
            dim(raidTint,      tint)

            -- Docked, the bar is drawn by the tracker, so only the two shared controls
            -- still reach it - everything else styles the floating frame alone.
            local on    = cfg.showZoneProgressBar
            local float = on and (cfg.zoneProgressLocation or "floating") == "floating"
            dim(zbFloat,          on)
            dim(zbTexDD,          on)
            dim(zbBarColorPicker, on)
            dim(zbBgCheck,      float)
            dim(zbBorderCheck,  float)
            dim(zbScaleSlider,  float)
            dim(zbFontDD,       float)
            dim(zbHeaderPicker, float)
            dim(zbCountPicker,  float)
            dim(zbBgPicker,     float and zb.showBackground ~= false)
            dim(zbBorderPicker, float and zb.showBorder ~= false)

            -- showProgressBars heads this group and so is never dimmed. The two half-switches
            -- are inert while it is off, and the STYLING is inert unless at least one half is
            -- actually drawing a bar - master on with both halves off leaves nothing on screen
            -- for a texture or a height to reach.
            local pb    = pbState() or {}
            local bars  = cfg.showProgressBars ~= false
            local drawn = bars and (cfg.showQuestProgressBars ~= false
                                    or cfg.showScenarioProgressBars ~= false)
            dim(pbQuests,          bars)
            dim(pbScenario,        bars)
            dim(pbBgCheck,         drawn)
            dim(pbBorderCheck,     drawn)
            dim(pbHeightSlider,    drawn)
            dim(pbTexDD,           drawn)
            dim(pbBarColorPicker,  drawn)
            dim(pbBgPicker,        drawn and pb.showBackground ~= false)
            dim(pbBorderPicker,    drawn and pb.showBorder ~= false)
        end
        syncDependents()
        content._syncDependents = syncDependents
    end,

    -- This sweep covers THIS tab's masters only. Options/TabTracker.lua owns a second,
    -- independent pair of its own, so two files hold dependency state and neither one is the
    -- whole picture. Re-running per view costs one pass over ~30 SetAlpha calls.
    refresh = function(_, content)
        if content._syncDependents then content._syncDependents() end
    end,
})
