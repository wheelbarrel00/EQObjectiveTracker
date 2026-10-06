local _, ns = ...

local ZoneHeaders = ns:RegisterModule("ZoneHeaders", {})
local Util        = ns.Util

local MIN_H      = 16
local TEXT_COLOR = { 1, 0.82, 0 }
local BAR_COLOR  = { 0.80, 0.60, 0.20, 0.85 }
local LINE_COLOR = { 0.92, 0.72, 0.02, 0.85 }
local BAR_DARKEN = 0.4

-- Pooled by position rather than by zone: a header holds nothing but what Place writes into it.
ZoneHeaders.frames = {}
-- The pooled header each zone was drawn into this pass, which the sticky band copies from.
ZoneHeaders.byKey = {}
ZoneHeaders.gen = 0
local used = 0

local function key(groupID, zone)
    return groupID .. ":" .. zone
end

function ZoneHeaders:IsCollapsed(groupID, zone)
    local DB   = ns:GetModule("DB")
    local char = DB and DB:Char()
    local t    = char and char.zonesCollapsed
    return (t and t[key(groupID, zone)] == true) and true or false
end

function ZoneHeaders:ToggleCollapsed(groupID, zone)
    local DB   = ns:GetModule("DB")
    local char = DB and DB:Char()
    if not char then return end
    char.zonesCollapsed = char.zonesCollapsed or {}
    local k = key(groupID, zone)
    local collapsed = char.zonesCollapsed[k] ~= true
    char.zonesCollapsed[k] = collapsed or nil
    local Tracker = ns:GetModule("Tracker")
    if not Tracker then return end
    Tracker:Render()
    -- After the render, which is what records where the zone landed.
    if not collapsed and Tracker.ScrollZoneIntoView then Tracker:ScrollZoneIntoView(k) end
end

function ZoneHeaders:Key(groupID, zone)
    return key(groupID, zone)
end

local function build(parent)
    local h = CreateFrame("Button", nil, parent)
    h:SetHeight(MIN_H)
    h:RegisterForClicks("LeftButtonUp")

    h.bar = h:CreateTexture(nil, "BACKGROUND")
    h.bar:SetColorTexture(1, 1, 1, 1)
    h.bar:SetAllPoints(h)
    h.bar:Hide()

    h.line = h:CreateTexture(nil, "ARTWORK")
    h.line:SetHeight(1)
    h.line:SetPoint("BOTTOMLEFT", 0, 0)
    h.line:SetPoint("BOTTOMRIGHT", 0, 0)
    h.line:Hide()

    h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h.text:SetPoint("LEFT", 4, 0)
    h.text:SetJustifyH("LEFT")
    h.text:SetWordWrap(false)

    h.collapse = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h.collapse:SetPoint("RIGHT", -4, 0)

    h.count = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    h.count:SetPoint("RIGHT", h.collapse, "LEFT", -6, 0)
    h.text:SetPoint("RIGHT", h.count, "LEFT", -6, 0)

    h:SetScript("OnClick", function(self)
        local Tracker = ns:GetModule("Tracker")
        if Tracker and Tracker.IsClickThrough and Tracker:IsClickThrough() then return end
        if self.groupID and self.zone then ZoneHeaders:ToggleCollapsed(self.groupID, self.zone) end
    end)
    return h
end

local function applyBar(h, cfg)
    if not cfg.zoneHeaderBar then
        h.bar:Hide()
        return
    end
    local c = cfg.zoneHeaderBarColor or {}
    local r, g, b, a = c.r or BAR_COLOR[1], c.g or BAR_COLOR[2], c.b or BAR_COLOR[3], c.a or BAR_COLOR[4]
    if h.bar.SetGradient then
        local k = BAR_DARKEN
        if h._c1 then h._c1:SetRGBA(r, g, b, a) else h._c1 = CreateColor(r, g, b, a) end
        if h._c2 then h._c2:SetRGBA(r * k, g * k, b * k, a) else h._c2 = CreateColor(r * k, g * k, b * k, a) end
        h.bar:SetGradient("HORIZONTAL", h._c1, h._c2)
    else
        h.bar:SetVertexColor(r, g, b, a)
    end
    h.bar:Show()
end

-- Text first: the height is read off the string.
function ZoneHeaders:ApplyStyle(h, cfg)
    local Media = ns:GetModule("Media")
    local delta = cfg.zoneHeaderSizeDelta or 2
    Media:ApplyFont(h.text, delta)
    Media:ApplyFont(h.count, delta - 4)
    Media:ApplyFont(h.collapse, delta)

    local textH  = h.text:GetStringHeight() or 0
    local height = (textH > 0) and math.max(MIN_H, math.ceil(textH + 4)) or MIN_H
    h:SetHeight(height)
    self._h = height

    local r, g, b
    if cfg.zoneHeaderColorUseClass then r, g, b = Util.GetPlayerClassColor() end
    if not r then
        local c = cfg.zoneHeaderColor or {}
        r, g, b = c.r or TEXT_COLOR[1], c.g or TEXT_COLOR[2], c.b or TEXT_COLOR[3]
    end
    h.text:SetTextColor(r, g, b)
    h.count:SetTextColor(r, g, b)
    h.collapse:SetTextColor(r, g, b)

    applyBar(h, cfg)
    if cfg.zoneHeaderDivider then
        local d = cfg.zoneHeaderDividerColor or {}
        h.line:SetColorTexture(d.r or LINE_COLOR[1], d.g or LINE_COLOR[2],
                               d.b or LINE_COLOR[3], d.a or LINE_COLOR[4])
        h.line:Show()
    else
        h.line:Hide()
    end
    return height
end

function ZoneHeaders:Begin()
    used = 0
    wipe(self.byKey)
    self.gen = self.gen + 1
end

-- Outside the pool, for the sticky band and the Appearance preview: a render reuses pooled ones.
function ZoneHeaders:NewHeader(parent)
    return build(parent)
end

function ZoneHeaders:Place(content, groupID, run, y, cfg)
    used = used + 1
    local h = self.frames[used]
    if not h then
        h = build(content)
        self.frames[used] = h
    end
    self.byKey[key(groupID, run.zone)] = h
    local height, collapsed = self:Draw(h, content, groupID, run, y, cfg)
    return height, collapsed, h
end

-- Copies the zone's header into a sticky band header. False when the zone drew no header this pass.
function ZoneHeaders:Mirror(dst, zoneKey)
    local src = self.byKey[zoneKey]
    if not src then return false end
    dst.groupID, dst.zone = src.groupID, src.zone
    dst.text:SetText(src.text:GetText())
    dst.count:SetText(src.count:GetText())
    dst.collapse:SetText(src.collapse:GetText())
    return true
end

function ZoneHeaders:Draw(h, content, groupID, run, y, cfg)
    if h:GetParent() ~= content then h:SetParent(content) end
    h.groupID, h.zone = groupID, run.zone

    local collapsed = self:IsCollapsed(groupID, run.zone)
    h.text:SetText(run.zone)
    if cfg.showQuestTotal ~= false then
        h.count:SetText(run.count .. "/" .. run.total)
    else
        h.count:SetText(tostring(run.count))
    end
    -- ASCII, as the section headers have it: the Korean client font has no en dash.
    h.collapse:SetText(collapsed and "+" or "-")

    local height = self:ApplyStyle(h, cfg)
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -y)
    h:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
    h:Show()
    return height, collapsed
end

function ZoneHeaders:Sweep()
    for i = used + 1, #self.frames do self.frames[i]:Hide() end
end

function ZoneHeaders:Indent(cfg)
    if not (cfg and cfg.zoneHeaders) then return 0 end
    return math.max(0, cfg.zoneHeaderIndent or 8)
end

function ZoneHeaders:Height()
    return self._h or MIN_H
end
