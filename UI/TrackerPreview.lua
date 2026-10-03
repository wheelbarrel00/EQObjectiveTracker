local _, ns = ...

local Preview = ns:RegisterModule("TrackerPreview", {})
local Entry   = ns:GetModule("Entry")

local STATE, LINE, ICON = Entry.STATE, Entry.LINE, Entry.ICON

local MARGIN     = 12
-- The sample runs this far past the view, so the scroll bar has something to scroll and shows.
local PEEK       = 48
local MIN_VIEW   = 160
local MIN_WIDTH  = 200
-- An idle scenario container is one pixel tall and the quest list hangs two under it.
local SCENARIO_GAP = 3
local FALLBACK_H = 600
local WHEEL_STEP = 24

local TOTALS = { campaign = 4, quests = 25 }
local ZONE_DONE, ZONE_TOTAL = 7, 12
local ZONE_GROUP = { visibleCount = 0, totalCount = 0 }

-- Made up to show each way a row can look. English on every client: they are sample data, like the
-- diagnostic lines on the About tab, so they carry no translation keys. Rebuilt per refresh, so the
-- NEW tag and the difficulty colors follow the clock and the player's level.
function Preview:Samples()
    local QC    = (Enum and Enum.QuestClassification) or {}
    local level = (UnitLevel and UnitLevel("player")) or 1
    local function quest(id, groupID, title, fields)
        local e = { id = id, providerID = "quests", groupID = groupID, title = title,
                    state = STATE.ACTIVE, level = level, tags = {}, lines = {},
                    icon = { kind = ICON.QUESTPOI, classification = QC.Normal } }
        for k, v in pairs(fields) do e[k] = v end
        return e
    end
    return {
        campaign = {
            quest(90001, "campaign", "A Shadow Over the Vale", {
                tags  = { campaign = true },
                icon  = { kind = ICON.QUESTPOI, classification = QC.Campaign },
                lines = { { text = "Investigate the ruined watchtower", kind = LINE.OBJECTIVE },
                          { text = "0/3 Ancient tablets recovered", kind = LINE.OBJECTIVE } },
            }),
        },
        quests = {
            quest(90002, "quests", "Wolves at the Door", {
                addedAt = time(),
                lines = { { text = "4/8 Gray wolves slain", kind = LINE.OBJECTIVE },
                          { text = "Speak with the innkeeper", kind = LINE.OBJECTIVE } },
            }),
            quest(90003, "quests", "Cleansing the Grove", {
                level = level + 3,
                lines = { { text = "Corruption purged", kind = LINE.PROGRESSBAR, current = 45, required = 100 } },
            }),
            quest(90004, "quests", "Supplies for the Outpost", {
                state = STATE.COMPLETE, level = level - 4,
                lines = { { text = "6/6 Crates delivered", kind = LINE.OBJECTIVE, completed = true } },
            }),
            quest(90005, "quests", "The Missing Scout", {
                isFocused = true, subtitle = "Northern Vale",
                lines = { { text = "Find the scout's trail", kind = LINE.OBJECTIVE } },
            }),
        },
    }
end

local function wheel(sf, delta)
    local range = sf:GetVerticalScrollRange() or 0
    if range <= 0 then return end
    local new = (sf:GetVerticalScroll() or 0) - delta * WHEEL_STEP
    sf:SetVerticalScroll(math.max(0, math.min(new, range)))
end

-- Built like the tracker's frame so the tracker's own skinning applies to it: a backdrop frame
-- with a background texture, and a template scroll frame with a track texture behind its bar.
function Preview:Build(panel)
    if self.box then return end
    self.panel = panel
    local box = CreateFrame("Frame", nil, panel)
    self.box = box

    local bg = CreateFrame("Frame", nil, box, BackdropTemplateMixin and "BackdropTemplate")
    bg:SetAllPoints(box)
    bg:SetFrameLevel(box:GetFrameLevel())
    self.bg = bg
    self.background = bg:CreateTexture(nil, "BACKGROUND")
    self.background:SetAllPoints()
    self.background:Hide()

    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", wheel)
    self.scroll, self.content = scroll, content

    local barBG = box:CreateTexture(nil, "BORDER")
    local bar = scroll.ScrollBar or scroll.scrollBar
    if bar then
        barBG:SetPoint("TOPLEFT",     bar, "TOPLEFT",    -1, 0)
        barBG:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, 0)
    else
        barBG:SetPoint("TOPLEFT",     scroll, "TOPRIGHT",     0, 1)
        barBG:SetPoint("BOTTOMRIGHT", box,    "BOTTOMRIGHT", -2, 0)
    end
    barBG:Hide()
    self.barBG = barBG

    self.rows, self.headers = {}, {}
end

-- Kept apart from RowPool, which the tracker sweeps on every render, and deaf to the mouse, so a
-- sample row can never be clicked, dragged, hovered for a tooltip or offered a menu.
function Preview:Row(id)
    local row = self.rows[id]
    if row then return row end
    row = ns:GetModule("Row"):Build()
    row:SetParent(self.content)
    row:EnableMouse(false)
    self.rows[id] = row
    return row
end

-- A header of the preview's own: a click on a pooled one would collapse the tracker's section.
function Preview:Header(groupID)
    local h = self.headers[groupID]
    if h then return h end
    h = ns:GetModule("Sections"):NewHeader(self.content, groupID)
    h:EnableMouse(false)
    self.headers[groupID] = h
    return h
end

-- Every row is reset before it is drawn, so the repaint gate never keeps a height measured while
-- the panel was hidden. A refresh made while it is hidden is drawn once more a frame later, once
-- it is on screen, as the library sizes text again once a tab is shown.
function Preview:Refresh(again)
    local box = self.box
    local cfg = ns:GetModule("DB"):Tracker()
    if not (box and cfg) then return end
    if not again and not box:IsVisible() then
        C_Timer.After(0, function() self:Refresh(true) end)
    end

    local Tracker, Sections = ns:GetModule("Tracker"), ns:GetModule("Sections")
    local Row, Card = ns:GetModule("Row"), ns:GetModule("Card")
    local ZoneBar = ns:GetModule("ZoneProgressBar")
    local content = self.content

    local pad, top, bottom = Tracker:Insets()
    local width = math.max(MIN_WIDTH, cfg.width or MIN_WIDTH)
    local inner = math.max(1, width - Tracker:ScrollGutter(cfg))
    local gap   = Card:Gap(math.max(0, cfg.blockSpacing or 2), (Card:State(cfg)))
    local showTotal = cfg.showQuestTotal ~= false

    local provider = ns:GetModule("Registry"):Get("quests")
    local declared = {}
    for _, g in ipairs((provider and provider.groups) or { "quests" }) do declared[g] = true end

    -- The tracker's own Row and Sections record two things the real tracker reads back: the
    -- followed row's icon probe for /eqot status, and the header height its world quest region
    -- reserves. Both are put back once the preview has drawn.
    local keepProbe, keepProbeAt, keepHeaderH = Row._focusIcon, Row._focusIconAt, Sections._h

    local samples = self:Samples()
    local drawnRows, drawnHeaders, zoneDrawn = {}, {}, false
    local y = 0
    for _, groupID in ipairs(Sections:Order()) do
        if Sections:IsVirtual(groupID) then
            if ZoneBar and ZoneBar:IsDocked() then
                local h = self:Header(groupID)
                y = y + Sections:Place(h, content, y, ZONE_GROUP, false, false) + gap
                h.count:SetText(ZONE_DONE .. "/" .. ZONE_TOTAL)
                drawnHeaders[groupID] = true
                self.zoneBar = self.zoneBar or ZoneBar:BuildDockedBar(content)
                y = y + ZoneBar:DrawDocked(self.zoneBar, content, y, ZONE_DONE, ZONE_TOTAL) + gap
                zoneDrawn = true
            end
        elseif samples[groupID] and declared[groupID] and not Sections:IsHidden(groupID) then
            local list = samples[groupID]
            local h = self:Header(groupID)
            y = y + Sections:Place(h, content, y, { visibleCount = #list, totalCount = TOTALS[groupID] },
                                   false, showTotal) + gap
            drawnHeaders[groupID] = true
            for _, entry in ipairs(list) do
                local row = self:Row(entry.id)
                row:SetWidth(inner)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                Row:Reset(row)
                y = y + Row:Render(row, entry, inner, cfg) + gap
                row:Show()
                drawnRows[entry.id] = true
            end
        end
    end
    for id, row in pairs(self.rows) do if not drawnRows[id] then row:Hide() end end
    for id, h in pairs(self.headers) do if not drawnHeaders[id] then h:Hide() end end
    if self.zoneBar and not zoneDrawn then self.zoneBar:Hide() end
    Row._focusIcon, Row._focusIconAt, Sections._h = keepProbe, keepProbeAt, keepHeaderH

    content:SetSize(inner, math.max(1, y))

    -- Drawn at the tracker's own width so text wraps where it does on the tracker, and shrunk to
    -- fit the panel when the tracker is wider.
    local panel = self.panel
    local panelW = panel:GetWidth() or 0
    local panelH = panel:GetHeight() or 0
    if panelH <= 0 then panelH = FALLBACK_H end
    local scale = (panelW > 0) and math.min(1, (panelW - MARGIN * 2) / width) or 1
    local avail = math.max(1, (panelH - MARGIN * 2) / scale - top - SCENARIO_GAP - bottom)
    local view  = math.min(avail, math.max(MIN_VIEW, y - PEEK))

    box:SetScale(scale)
    box:SetSize(width, top + SCENARIO_GAP + view + bottom)
    box:ClearAllPoints()
    box:SetPoint("TOP", panel, "TOP", 0, -MARGIN / scale)
    box:SetAlpha(cfg.trackerAlpha or 1)

    local scroll = self.scroll
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", box, "TOPLEFT", pad, -(top + SCENARIO_GAP))
    scroll:SetSize(inner, view)
    if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
    local range = math.max(0, scroll:GetVerticalScrollRange() or 0)
    if (scroll:GetVerticalScroll() or 0) > range then scroll:SetVerticalScroll(range) end

    Tracker:SkinBackdrop(self.bg, self.background, cfg)
    Tracker:SkinScroll(scroll, self.barBG, cfg)
end
