local _, ns = ...

local Sections = ns:RegisterModule("Sections", {})
local Util     = ns.Util
local L        = ns.L

local HEADER_H     = 26
local HEADER_COLOR = { 0.93, 0.32, 0.10 }
local HAIRLINE     = { 0.92, 0.72, 0.02, 0.85 }
local BAR_COLOR    = { 0.80, 0.60, 0.20, 0.85 }
local BAR_DARKEN   = 0.4
local SOFT_MASK    = "Interface\\AddOns\\EQObjectiveTracker\\Media\\Textures\\headerbar-softmask.tga"

-- Titles are display-side because a group is a display concept. A provider that
-- declares a group nobody has titled still renders, under its raw id.
Sections.TITLES = {
    zoneprogress = L["Zone Progress"],
    quests       = L["Quests"],
    campaign     = L["Campaign"],
    worldquests  = L["World Quests"],
    achievements = L["Achievements"],
    scenarios    = L["Scenario"],
    endeavors    = L["Endeavors"],
    profession   = L["Profession"],
}

Sections.frames = {}

-- World quests draw in their own capped region pinned above or below the scroll area,
-- so they sit outside the reorderable run and Order never returns them.
Sections.PINNED = { worldquests = true }

-- Kept separate from PINNED because a pinned group still has a header, a collapse and a
-- visibility toggle, and a scenario container has none of the three.
Sections.CONTAINER = { scenarios = true }

-- No provider backs a virtual section. Its body is a StatusBar rather than a run of rows,
-- so reaching Order through a fake provider would mean faking an Entry too.
Sections.VIRTUAL = { zoneprogress = true }

-- Kept out of the AceDB defaults on purpose. AceDB merges an array default per index and
-- strips matching indices at logout, so a saved order comes back sparse and adding an entry
-- here would shift every later index and rewrite the user's run. worldquests is absent
-- because its placement comes from worldQuestsPosition, not from this order.
Sections.DEFAULT_ORDER = { "zoneprogress", "campaign", "quests", "profession", "endeavors" }

function Sections:Title(groupID)
    return self.TITLES[groupID] or groupID
end

function Sections:IsPinned(groupID)
    return self.PINNED[groupID] == true
end

function Sections:IsContainer(groupID)
    return self.CONTAINER[groupID] == true
end

function Sections:IsVirtual(groupID)
    return self.VIRTUAL[groupID] == true
end

-- Virtual ids lead, matching EQ's own reorderable list, so a saved order that predates
-- one appends it ahead of the other unseen groups rather than below them.
function Sections:Known()
    local out = {}
    for id in pairs(self.VIRTUAL) do out[#out + 1] = id end
    table.sort(out)
    for _, id in ipairs(ns:GetModule("Registry"):Groups()) do out[#out + 1] = id end
    return out
end

-- Saved order first, then any group the saved order has not seen. Appending the
-- unseen ones keeps a newly added provider from being invisible on an old profile.
function Sections:Order()
    local DB  = ns:GetModule("DB")
    local cfg = DB and DB:Tracker()

    local known = self:Known()
    local live  = {}
    for _, id in ipairs(known) do live[id] = true end

    local saved = (cfg and cfg.sectionOrder) or self.DEFAULT_ORDER

    local seen, out = {}, {}
    -- Indexed rather than ipairs: an order saved while this key still had an AceDB default
    -- comes back with holes where it matched, and ipairs would stop at the first one.
    for i = 1, #known do
        local id = saved[i]
        if id and live[id] and not seen[id] and not self:IsPinned(id) and not self:IsContainer(id) then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    for _, id in ipairs(known) do
        if not seen[id] and not self:IsPinned(id) and not self:IsContainer(id) then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    return out
end

function Sections:IsHidden(groupID)
    local DB  = ns:GetModule("DB")
    local cfg = DB and DB:Tracker()
    return (cfg and cfg.sectionsHidden and cfg.sectionsHidden[groupID]) and true or false
end

function Sections:SetHidden(groupID, hidden)
    local DB  = ns:GetModule("DB")
    local cfg = DB and DB:Tracker()
    if not cfg then return end
    cfg.sectionsHidden = cfg.sectionsHidden or {}
    cfg.sectionsHidden[groupID] = hidden or nil
end

-- Writes the full reconciled order back, not just the swap, so a profile whose saved
-- order predates a newly loaded provider gets that provider persisted too.
function Sections:Move(groupID, delta)
    local order = self:Order()
    local idx
    for i = 1, #order do
        if order[i] == groupID then idx = i break end
    end
    if not idx then return end
    local j = idx + delta
    if j < 1 or j > #order then return end
    order[idx], order[j] = order[j], order[idx]

    local DB  = ns:GetModule("DB")
    local cfg = DB and DB:Tracker()
    if cfg then cfg.sectionOrder = order end

    local Tracker = ns:GetModule("Tracker")
    if Tracker then Tracker:Render() end
end

function Sections:IsCollapsed(groupID)
    local DB   = ns:GetModule("DB")
    local char = DB and DB:Char()
    if not char then return false end
    char.sectionsCollapsed = char.sectionsCollapsed or {}
    return char.sectionsCollapsed[groupID] == true
end

function Sections:ToggleCollapsed(groupID)
    local DB   = ns:GetModule("DB")
    local char = DB and DB:Char()
    if not char then return end
    char.sectionsCollapsed = char.sectionsCollapsed or {}
    local collapsed = not self:IsCollapsed(groupID)
    char.sectionsCollapsed[groupID] = collapsed
    local Tracker = ns:GetModule("Tracker")
    if not Tracker then return end
    Tracker:Render()
    -- After the render, which is what places the section and records where it landed.
    if not collapsed and Tracker.ScrollSectionIntoView then
        Tracker:ScrollSectionIntoView(groupID)
    end
end

local function build(parent, groupID, title)
    local h = CreateFrame("Button", nil, parent)
    h:SetHeight(HEADER_H)
    h:RegisterForClicks("LeftButtonUp")

    -- White base so ApplyBar can tint it, and BACKGROUND keeps it under the hairline and the label
    h.bar = h:CreateTexture(nil, "BACKGROUND")
    h.bar:SetColorTexture(1, 1, 1, 1)
    h.bar:SetPoint("LEFT",  h, "LEFT",  0, 0)
    h.bar:SetPoint("RIGHT", h, "RIGHT", 0, 0)
    h.bar:Hide()

    -- The mask affects the bar's alpha only, so the gradient survives it
    if h.CreateMaskTexture then
        h.barMask = h:CreateMaskTexture(nil, "BACKGROUND")
        h.barMask:SetTexture(SOFT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        h.barMask:SetAllPoints(h.bar)
    end

    h.hairline = h:CreateTexture(nil, "ARTWORK")
    h.hairline:SetColorTexture(HAIRLINE[1], HAIRLINE[2], HAIRLINE[3], HAIRLINE[4])
    h.hairline:SetHeight(2)
    h.hairline:SetPoint("BOTTOMLEFT", 0, 0)
    h.hairline:SetPoint("BOTTOMRIGHT", 0, 0)

    h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    h.text:SetPoint("LEFT", 4, 0)
    h.text:SetText(title)
    h.text:SetTextColor(HEADER_COLOR[1], HEADER_COLOR[2], HEADER_COLOR[3])

    h.collapse = h:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    h.collapse:SetPoint("RIGHT", -4, 0)
    h.collapse:SetTextColor(HEADER_COLOR[1], HEADER_COLOR[2], HEADER_COLOR[3])

    h.count = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    h.count:SetPoint("RIGHT", h.collapse, "LEFT", -6, 0)
    h.count:SetTextColor(HEADER_COLOR[1], HEADER_COLOR[2], HEADER_COLOR[3])

    h.groupID = groupID
    h:SetScript("OnClick", function(self)
        local Tracker = ns:GetModule("Tracker")
        if Tracker and Tracker.IsClickThrough and Tracker:IsClickThrough() then return end
        Sections:ToggleCollapsed(self.groupID)
    end)
    return h
end

function Sections:Acquire(parent, groupID)
    local h = self.frames[groupID]
    if not h then
        h = build(parent, groupID, self:Title(groupID))
        self.frames[groupID] = h
    end
    if h:GetParent() ~= parent then h:SetParent(parent) end
    return h
end

function Sections:ApplyBar(header, cfg)
    local bar = header.bar
    if not bar then return end
    if not (cfg and cfg.headerBar) then
        bar:Hide()
        return
    end

    local c = cfg.headerBarColor or {}
    local r, g, b, a = c.r or BAR_COLOR[1], c.g or BAR_COLOR[2], c.b or BAR_COLOR[3], c.a or BAR_COLOR[4]
    bar:SetHeight(cfg.headerBarHeight or 22)

    if bar.SetGradient then
        local k = BAR_DARKEN
        -- Cached ColorMixins so dragging a slider does not churn GC
        if header._barC1 then header._barC1:SetRGBA(r, g, b, a) else header._barC1 = CreateColor(r, g, b, a) end
        if header._barC2 then header._barC2:SetRGBA(r * k, g * k, b * k, a) else header._barC2 = CreateColor(r * k, g * k, b * k, a) end
        -- VERTICAL takes min=bottom then max=top, so the darker shade goes first
        if (cfg.headerBarStyle or 1) == 2 then
            bar:SetGradient("VERTICAL", header._barC2, header._barC1)
        else
            bar:SetGradient("HORIZONTAL", header._barC1, header._barC2)
        end
    end

    if header.barMask then
        if cfg.headerBarSoftEdges then
            -- Strength is inverted - lower values oversize the mask so the bar samples its
            -- solid interior, and the bottom stays flush so that edge never feathers.
            local s    = cfg.headerBarSoftEdgeStrength or 10
            local extX = 30 * (10 - s) / 9
            local extY = 8  * (10 - s) / 9
            header.barMask:ClearAllPoints()
            header.barMask:SetPoint("TOPLEFT",     bar, "TOPLEFT",     -extX, extY)
            header.barMask:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT",  extX, 0)
            if not header._barMasked then
                bar:AddMaskTexture(header.barMask)
                header._barMasked = true
            end
        elseif header._barMasked then
            bar:RemoveMaskTexture(header.barMask)
            header._barMasked = false
        end
    end

    bar:Show()
end

-- Applied per section per render rather than cached: there are only a handful of
-- headers, and it means every appearance option lands without a separate invalidate.
function Sections:ApplyStyle(header)
    local cfg   = ns:GetModule("DB"):Tracker()
    local Media = ns:GetModule("Media")
    if not cfg then return end

    self:ApplyBar(header, cfg)

    local delta = cfg.headerSizeDelta or 4
    Media:ApplyFont(header.text, delta)
    Media:ApplyFont(header.count, delta - 4 - 2)
    Media:ApplyFont(header.collapse, delta)

    -- Derived from the live font instead of fixed. Header Size Offset reaches 36pt inside
    -- what was a 26px button, and past about 28 the text crossed its own hairline and drew
    -- outside the bar. Floored at the old constant, so the default layout is untouched, and
    -- stored because Height and Tracker's headerBand have to move with it.
    local textH = header.text and header.text:GetStringHeight() or 0
    self._h = (textH > 0) and math.max(HEADER_H, math.ceil(textH + 2)) or HEADER_H
    header:SetHeight(self._h)

    local r, g, b
    if cfg.headerColorUseClass then r, g, b = Util.GetPlayerClassColor() end
    if not r then
        local c = cfg.headerColor or {}
        r, g, b = c.r or HEADER_COLOR[1], c.g or HEADER_COLOR[2], c.b or HEADER_COLOR[3]
    end
    header.text:SetTextColor(r, g, b)
    header.count:SetTextColor(r, g, b)
    header.collapse:SetTextColor(r, g, b)

    local d = cfg.headerDividerColor or {}
    header.hairline:SetColorTexture(d.r or HAIRLINE[1], d.g or HAIRLINE[2],
                                    d.b or HAIRLINE[3], d.a or HAIRLINE[4])
end

-- extra is the auto-quest popup count for this group. Popup boxes are section content
-- without being entries, so they add to both sides of the count exactly as in EQ.
function Sections:Place(header, content, y, group, collapsed, showTotal, extra)
    self:ApplyStyle(header)
    header:Show()
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -y)
    header:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)

    extra = extra or 0
    local visible, total = group.visibleCount + extra, group.totalCount + extra
    if showTotal then
        header.count:SetText(visible .. "/" .. total)
    else
        header.count:SetText(tostring(visible))
    end
    -- ASCII rather than an en dash: the Korean client font has no glyph for U+2013
    -- and every section header drew an empty box.
    header.collapse:SetText(collapsed and "+" or "-")
    return self._h or HEADER_H
end

function Sections:HideAll()
    for _, h in pairs(self.frames) do h:Hide() end
end

function Sections:Height()
    return self._h or HEADER_H
end
