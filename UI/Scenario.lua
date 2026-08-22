local _, ns = ...

local Scenario = ns:RegisterModule("Scenario", {})
local Entry    = ns:GetModule("Entry")
local Util     = ns.Util
local L        = ns.L

local LINE = Entry.LINE

local SUBHEADER_H       = 26
local CAT_GAP           = 1
local BANNER_GAP        = 6
local CRITERIA_LINE_GAP = 4
local BAR_H             = 16
local BAR_W_RATIO       = 0.85
local BANNER_W          = 201
local BANNER_H          = 83

local HEADER_COLOR   = { 0.93, 0.32, 0.10 }
local CATEGORY_COLOR = { 0.78, 0.78, 0.78 }

local TEXTURE_KIT_OFFSETS = {
    ["evergreen-scenario"]    = { nx = 0,  ny = 0, fx = -4, fy = 2 },
    ["thewarwithin-scenario"] = { nx = 0,  ny = 0, fx = 3,  fy = -2 },
    ["delves-scenario"]       = { nx = -2, ny = 1, fx = -2, fy = 1 },
}
local DEFAULT_OFFSETS = { nx = 0, ny = 0, fx = -10, fy = 3 }

-- Falls back whole rather than per-texture: a kit with no tracker header has no filigree
-- either, so both revert to evergreen together.
local function pickAtlases(textureKit)
    local kit    = textureKit or "evergreen-scenario"
    local normal = kit .. "-trackerheader"
    local final  = kit .. "-trackerheader-final-filigree"

    if not Util.AtlasExists(normal) then
        kit    = "evergreen-scenario"
        normal = "evergreen-scenario-trackerheader"
        final  = "evergreen-scenario-trackerheader-final-filigree"
    elseif not Util.AtlasExists(final) then
        final = nil
    end
    return normal, final, kit
end

Scenario.criteriaPool   = {}
Scenario.activeCriteria = {}

local function buildCriteriaRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(BAR_H + 14)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(12, 12)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetJustifyH("LEFT")
    row.text:SetTextColor(1, 0.82, 0)

    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetHeight(BAR_H)
    row.bar:SetMinMaxValues(0, 100)
    row.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    row.bar:SetStatusBarColor(0.26, 0.42, 1.0)

    row.bar.bg = row.bar:CreateTexture(nil, "BACKGROUND")
    row.bar.bg:SetAllPoints()
    row.bar.bg:SetColorTexture(0.04, 0.07, 0.18, 0.9)

    row.bar.border = CreateFrame("Frame", nil, row.bar, BackdropTemplateMixin and "BackdropTemplate")
    row.bar.border:SetPoint("TOPLEFT", -1, 1)
    row.bar.border:SetPoint("BOTTOMRIGHT", 1, -1)
    row.bar.border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    row.bar.border:SetBackdropBorderColor(0, 0, 0, 0.9)

    row.bar.label = row.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.bar.label:SetPoint("CENTER", row.bar, "CENTER", 0, 0)

    return row
end

function Scenario:AcquireCriteria(parent)
    local row = tremove(self.criteriaPool) or buildCriteriaRow(parent)
    if row:GetParent() ~= parent then row:SetParent(parent) end
    row:Show()
    self.activeCriteria[#self.activeCriteria + 1] = row
    return row
end

function Scenario:ReleaseCriteria()
    for i = #self.activeCriteria, 1, -1 do
        local row = self.activeCriteria[i]
        row:Hide()
        row:ClearAllPoints()
        row.bar:Hide()
        row.icon:Hide()
        row.icon:ClearAllPoints()
        row.text:ClearAllPoints()
        row.text:SetWidth(0)
        row.text:SetText("")
        self.criteriaPool[#self.criteriaPool + 1] = row
        self.activeCriteria[i] = nil
    end
end

function Scenario:Build(container)
    if self.banner then return end
    self.frame = container

    local subHeader = CreateFrame("Frame", nil, container)
    subHeader:SetHeight(SUBHEADER_H)
    subHeader:SetPoint("TOPLEFT",  container, "TOPLEFT",  0, 0)
    subHeader:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)

    subHeader.cat = subHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subHeader.cat:SetJustifyH("LEFT")
    subHeader.cat:SetTextColor(CATEGORY_COLOR[1], CATEGORY_COLOR[2], CATEGORY_COLOR[3])

    -- Chosen rather than corrected afterwards: CreateFontString raises outright when the
    -- inherited template is absent, so the check below can never run on a client that
    -- lacks it. ObjectiveTrackerHeaderFont is retail only.
    subHeader.text = subHeader:CreateFontString(nil, "OVERLAY",
        ObjectiveTrackerHeaderFont and "ObjectiveTrackerHeaderFont" or "GameFontNormalLarge")
    if not subHeader.text:GetFont() then subHeader.text:SetFontObject("GameFontNormalLarge") end
    subHeader.text:SetTextColor(HEADER_COLOR[1], HEADER_COLOR[2], HEADER_COLOR[3])

    local banner = CreateFrame("Frame", nil, container)
    banner:SetPoint("TOP", subHeader, "BOTTOM", 0, -BANNER_GAP)

    banner.NormalBG     = banner:CreateTexture(nil, "BACKGROUND")
    banner.ThemeOverlay = banner:CreateTexture(nil, "BACKGROUND", nil, 1)
    banner.ThemeOverlay:SetBlendMode("ADD")
    banner.FinalBG      = banner:CreateTexture(nil, "BORDER")

    -- Chosen rather than corrected, the same way subHeader.text above is: CreateFontString
    -- RAISES on an absent font object, Build runs from Render on every flavor, and a raise here
    -- aborts the whole tracker. Game18Font resolves on all four shipping TOCs, so the guard is
    -- for the next one.
    banner.Stage = banner:CreateFontString(nil, "ARTWORK",
        _G.Game18Font and "Game18Font" or "GameFontNormal")
    banner.Stage:SetSize(172, 18)
    banner.Stage:SetJustifyH("CENTER")
    banner.Stage:SetTextColor(1, 0.914, 0.682)

    banner.Name = banner:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    banner.Name:SetSize(172, 28)
    banner.Name:SetJustifyH("CENTER")
    banner.Name:SetJustifyV("TOP")
    banner.Name:SetSpacing(2)
    banner.Name:SetTextColor(1, 0.831, 0.380)
    banner.Name:SetPoint("TOP", banner.Stage, "BOTTOM", 0, -4)

    banner.Stage._baseFont = { banner.Stage:GetFont() }
    banner.Name._baseFont  = { banner.Name:GetFont() }

    self.subHeader = subHeader
    self.banner    = banner
end

function Scenario:ApplyHeaderLabels(category, name)
    local subHeader = self.subHeader
    if self._sCat == category and self._sName == name then return end
    self._sCat, self._sName = category, name

    local twoTier = name ~= nil and name:lower() ~= category:lower()
    local Media   = ns:GetModule("Media")

    subHeader.text:SetText(name or category)
    -- +4 matches the section header delta, so this sizes like the headers around it
    Media:ApplyFont(subHeader.text, 4)

    if twoTier then
        Media:ApplyFont(subHeader.cat, -1)
        subHeader.cat:SetText(category)
        subHeader.cat:Show()
        subHeader.cat:ClearAllPoints()
        subHeader.text:ClearAllPoints()
        subHeader.cat:SetPoint("TOPLEFT", subHeader, "TOPLEFT", 8, -1)
        subHeader.text:SetPoint("TOPLEFT", subHeader.cat, "BOTTOMLEFT", 0, -CAT_GAP)
        local h = subHeader.cat:GetStringHeight() + CAT_GAP
                  + subHeader.text:GetStringHeight() + 6
        self.subHeaderH = h
        subHeader:SetHeight(h)
    else
        subHeader.cat:Hide()
        subHeader.text:ClearAllPoints()
        subHeader.text:SetPoint("LEFT", subHeader, "LEFT", 8, 0)
        self.subHeaderH = SUBHEADER_H
        subHeader:SetHeight(SUBHEADER_H)
    end
end

-- ApplyHeaderLabels memoizes on the scenario identity, so the font has to be re-applied
-- separately or an appearance change would not land until the stage did.
function Scenario:ApplyHeaderFont()
    local subHeader = self.subHeader
    if not subHeader then return end
    local Media = ns:GetModule("Media")
    Media:ApplyFont(subHeader.text, 4)

    local h = SUBHEADER_H
    if subHeader.cat:IsShown() then
        Media:ApplyFont(subHeader.cat, -1)
        h = subHeader.cat:GetStringHeight() + CAT_GAP
            + subHeader.text:GetStringHeight() + 6
    end
    -- Render reads subHeaderH for the first criteria row and the container height, so keep it
    -- in step after a re-font
    if h ~= self.subHeaderH then
        self.subHeaderH = h
        subHeader:SetHeight(h)
    end
end

function Scenario:ApplyBannerShadow()
    local banner = self.banner
    if not banner then return end
    local Media = ns:GetModule("Media")
    Media:ApplyScenarioShadow(banner.Stage)
    Media:ApplyScenarioShadow(banner.Name)
end

function Scenario:ApplyBannerFont()
    local banner = self.banner
    if not banner then return end
    local Media = ns:GetModule("Media")
    Media:ApplyScenarioFont(banner.Stage, banner.Stage._baseFont)
    Media:ApplyScenarioFont(banner.Name,  banner.Name._baseFont)
end

function Scenario:_Clear()
    self:ReleaseCriteria()
    local WB = ns:GetModule("WidgetBlock")
    if WB then WB:ClearScenario() end
    self.widgetH = 0
    local SS = ns:GetModule("ScenarioSpells")
    if SS then SS:Clear() end
    if self.subHeader then self.subHeader:Hide() end
    local banner = self.banner
    if banner then
        banner:Hide()
    end
    self._sCat, self._sName = nil, nil
end

function Scenario:_DrawBanner(info, cfg)
    local banner    = self.banner
    local subHeader = self.subHeader

    local normalAtlas, finalAtlas, resolvedKit = pickAtlases(info.textureKit)
    local offsets = TEXTURE_KIT_OFFSETS[resolvedKit] or DEFAULT_OFFSETS

    banner:SetSize(BANNER_W, BANNER_H)

    local align = (cfg and cfg.scenarioTextAlign) or "CENTER"
    banner:ClearAllPoints()
    if align == "LEFT" then
        banner:SetPoint("TOPLEFT",  subHeader, "BOTTOMLEFT",  0, -BANNER_GAP)
    elseif align == "RIGHT" then
        banner:SetPoint("TOPRIGHT", subHeader, "BOTTOMRIGHT", 0, -BANNER_GAP)
    else
        banner:SetPoint("TOP",      subHeader, "BOTTOM",      0, -BANNER_GAP)
    end

    Util.SafeSetAtlas(banner.NormalBG, normalAtlas, true)
    banner.NormalBG:ClearAllPoints()
    banner.NormalBG:SetPoint("TOPLEFT", banner, "TOPLEFT", offsets.nx, offsets.ny)
    banner.NormalBG:Show()

    if finalAtlas and info.isFinalStage then
        Util.SafeSetAtlas(banner.FinalBG, finalAtlas, true)
        banner.FinalBG:ClearAllPoints()
        banner.FinalBG:SetPoint("TOPLEFT", banner, "TOPLEFT", offsets.fx, offsets.fy)
        banner.FinalBG:Show()
    else
        banner.FinalBG:Hide()
    end

    if info.themeR then
        Util.SafeSetAtlas(banner.ThemeOverlay, "themed-scenario-trackerheader-add", true)
        banner.ThemeOverlay:ClearAllPoints()
        banner.ThemeOverlay:SetPoint("BOTTOM", banner.NormalBG, "BOTTOM", 0, 0)
        banner.ThemeOverlay:SetVertexColor(info.themeR, info.themeG, info.themeB)
        banner.ThemeOverlay:Show()
    else
        banner.ThemeOverlay:Hide()
    end

    -- No UIWidgetContainer here on purpose. Registering one against Blizzard's shared widget
    -- set was reported killing the next tooltip to close with widgets on it. UI/WidgetBlock.lua
    -- reads those widgets and draws our own frames from them instead.
    banner.Stage:ClearAllPoints()
    banner.Stage:SetPoint("TOP", banner, "TOP", 0, -10)
    if info.isFinalStage then
        banner.Stage:SetText(L["Final Stage"])
    elseif info.numStages > 1 then
        banner.Stage:SetFormattedText(L["Stage %d"], info.stage)
    else
        banner.Stage:SetText("")
    end
    banner.Stage:Show()
    banner.Name:SetText(info.stageName or "")
    banner.Name:Show()
    self:ApplyBannerFont()
    self:ApplyBannerShadow()
end

function Scenario:_DrawCriteria(container, cfg, lines)
    local Media    = ns:GetModule("Media")
    local width    = math.max(1, container:GetWidth() or 1)
    local barWidth = math.max(1, math.floor(width * BAR_W_RATIO))
    local rowWidth = math.max(1, width - 16)
    local firstRowY = (self.topOffset or 0) + (self.subHeaderH or SUBHEADER_H)
                      + BANNER_GAP + BANNER_H + (self.widgetH or 0) + CRITERIA_LINE_GAP

    local prev
    for i = 1, #lines do
        local ln  = lines[i]
        local row = self:AcquireCriteria(container)
        Media:ApplyScenarioCriteriaFont(row.text)
        Media:ApplyScenarioCriteriaFont(row.bar.label)

        row:ClearAllPoints()
        if prev then
            row:SetPoint("TOP", prev, "BOTTOM", 0, -CRITERIA_LINE_GAP)
        else
            -- Anchored to the container, not the banner, so a side-aligned banner does
            -- not drag the rows off center with it
            row:SetPoint("TOP", container, "TOP", 0, -firstRowY)
        end

        -- WEIGHTED already carries a percentage, so its denominator is fixed at 100.
        -- PROGRESSBAR is a running total and keeps its own.
        local barValue, barMax, barLabel
        if not ln.completed and (not cfg or cfg.showProgressBars ~= false) then
            if ln.kind == LINE.WEIGHTED then
                barValue, barMax = math.max(0, math.min(100, ln.current or 0)), 100
                barLabel = ("%d%%"):format(barValue)
            -- Only a real meter. A 0/1 criterion is a yes or no, and drawing a bar for it
            -- reads as broken beside the checkmark rows around it.
            elseif ln.kind == LINE.PROGRESSBAR and ln.required and ln.required > 1 then
                barValue = math.max(0, math.min(ln.required, ln.current or 0))
                barMax   = ln.required
                barLabel = ("%d/%d"):format(barValue, barMax)
            end
        end

        if barValue then
            row:SetWidth(barWidth)
            row.icon:Hide()

            row.bar:Show()
            row.bar:ClearAllPoints()
            row.bar:SetWidth(barWidth)
            row.bar:SetMinMaxValues(0, barMax)
            row.bar:SetValue(barValue)
            row.bar.label:SetText(barLabel)

            row.text:ClearAllPoints()
            if ln.text ~= "" then
                row.text:SetPoint("TOP", row, "TOP", 0, 0)
                row.text:SetJustifyH("CENTER")
                -- Set for the same reason the text path below sets it, and this path measures
                -- GetStringHeight too. Without it a pooled row keeps whatever width it last
                -- drew with, so one criterion wraps and the next overflows the tracker.
                row.text:SetWidth(barWidth)
                row.text:SetText(ln.text)
                row.text:SetTextColor(1, 0.82, 0)
                row.bar:SetPoint("TOP", row.text, "BOTTOM", 0, -2)
                row:SetHeight(row.text:GetStringHeight() + 2 + BAR_H)
            else
                row.text:SetText("")
                row.bar:SetPoint("TOP", row, "TOP", 0, 0)
                row:SetHeight(BAR_H)
            end
        else
            row:SetWidth(rowWidth)
            row.bar:Hide()

            row.icon:Show()
            row.icon:ClearAllPoints()
            row.icon:SetPoint("LEFT", row, "LEFT", 8, 0)
            Util.SafeSetAtlas(row.icon, ln.completed and "ui-questtracker-tracker-check"
                                                      or "ui-questtracker-objective-nub")

            row.text:ClearAllPoints()
            row.text:SetPoint("LEFT",  row.icon, "RIGHT", 6, 0)
            row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            row.text:SetJustifyH("LEFT")
            -- GetStringHeight below is stale off anchors alone, so the wrap width is set
            -- explicitly or a wrapped criterion measures as one line and rows overlap
            row.text:SetWidth(math.max(1, rowWidth - 18))

            -- Completed criteria drop the meter, matching the default tracker. An
            -- unfinished one keeps it here, which is the only place it survives when bars
            -- are switched off.
            local label = ln.text or ""
            if not ln.completed then
                local meter
                if ln.kind == LINE.WEIGHTED then
                    meter = ("%d%%"):format(ln.current or 0)
                elseif ln.kind == LINE.PROGRESSBAR and ln.required and ln.required > 0 then
                    meter = ("%d/%d"):format(ln.current or 0, ln.required)
                end
                if meter then
                    label = (label ~= "") and (meter .. " " .. label) or meter
                end
            end
            row.text:SetText(label)
            if ln.completed then
                row.text:SetTextColor(0.27, 1.0, 0.27)
            else
                row.text:SetTextColor(0.85, 0.85, 0.85)
            end
            row:SetHeight(math.max(row.text:GetStringHeight(), 14))
        end

        Media:ApplyTextShadow(row.text)
        Media:ApplyTextShadow(row.bar.label)
        prev = row
    end
end

-- topOffset is the height the widget block above already took. Everything here anchors
-- from it rather than from the container's own top, so the two share one container and
-- one combat-gated SetHeight.
function Scenario:Render(container, cfg, info, entry, topOffset)
    self:Build(container)
    if not (self.banner and self.subHeader) then return 1 end
    self.topOffset = topOffset or 0

    if not info then
        self:_Clear()
        return 1
    end

    self.subHeader:ClearAllPoints()
    self.subHeader:SetPoint("TOPLEFT",  container, "TOPLEFT",  0, -self.topOffset)
    self.subHeader:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -self.topOffset)
    self.subHeader:Show()
    self:ApplyHeaderLabels(info.category, info.name)
    self:ApplyHeaderFont()
    self.banner:Show()

    self:_DrawBanner(info, cfg)

    -- Between the banner and the criteria, which is where the stage block draws it. The
    -- scenario's countdown belongs to the scenario, not to the top of the tracker.
    local WB = ns:GetModule("WidgetBlock")
    self.widgetH = WB and WB:RenderScenario(container, cfg,
        (self.topOffset or 0) + (self.subHeaderH or SUBHEADER_H) + BANNER_GAP + BANNER_H) or 0

    self:ReleaseCriteria()
    self:_DrawCriteria(container, cfg, (entry and entry.lines) or {})

    local h = (self.subHeaderH or SUBHEADER_H) + BANNER_GAP + BANNER_H + self.widgetH
    for i = 1, #self.activeCriteria do
        h = h + CRITERIA_LINE_GAP + self.activeCriteria[i]:GetHeight()
    end

    -- Under the criteria, where the stock tracker draws the scenario's own castable spells
    local SS = ns:GetModule("ScenarioSpells")
    local spellH = SS and SS:Place(container, info, (self.topOffset or 0) + h) or 0

    return h + spellH + 6
end
