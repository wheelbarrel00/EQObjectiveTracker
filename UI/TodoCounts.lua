local _, ns = ...

local TodoCounts = ns:RegisterModule("TodoCounts", {})
local Util       = ns.Util
local L          = ns.L

local DIM_ALPHA = 0.5
-- Between a count and the slash beside it. The rightmost count keeps the old count's 6 px.
local GAP = 2
local EDGE_GAP = 6

-- Core/DB.lua's defaults, for a stored color that lacks a channel.
local DEFAULTS = {
    { r = 238 / 255, g = 170 / 255, b = 0 },
    { r = 68 / 255, g = 1, b = 68 / 255 },
    { r = 1, g = 1, b = 1 },
    { r = 0.6, g = 0.6, b = 0.6 },
}
local COLOR_KEYS = { "todoColorUnfinished", "todoColorReady", "todoColorHere", "todoColorAll" }
local NAMES = { L["Unfinished here"], L["Ready to turn in here"], L["All here"], L["All quests"] }

local function onClick(b)
    local Tracker = ns:GetModule("Tracker")
    if Tracker and Tracker:IsClickThrough() then return end
    local TodoMode = ns:GetModule("TodoMode")
    if b.view == TodoMode:View() then return end
    TodoMode:SetView(b.view)
    if Tracker then Tracker:Render() end
end

local function onEnter(b)
    local Tracker = ns:GetModule("Tracker")
    if Tracker and Tracker:IsClickThrough() then return end
    local picked = b.view == ns:GetModule("TodoMode"):View()
    local tip = Util.Tooltip()
    tip:SetOwner(b, "ANCHOR_BOTTOMLEFT")
    -- SetText arg 5 is alpha, not wrap. Pass 1 or the line renders invisible.
    tip:SetText(NAMES[b.index], 1, 1, 1, 1, true)
    tip:AddLine(picked and L["These are the quests showing now."] or L["Click to show only these quests."],
                0.82, 0.82, 0.82, true)
    tip:Show()
end

local function onLeave()
    Util.Tooltip():Hide()
end

local function build(header)
    local views = ns:GetModule("TodoMode").VIEWS
    local t = { counts = {}, seps = {} }
    for i = 1, #views do
        local b = CreateFrame("Button", nil, header)
        b:RegisterForClicks("LeftButtonUp")
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.text:SetPoint("CENTER")
        b.line = b:CreateTexture(nil, "OVERLAY")
        b.line:SetHeight(1)
        b.line:SetPoint("TOPLEFT", b.text, "BOTTOMLEFT", 0, -1)
        b.line:SetPoint("TOPRIGHT", b.text, "BOTTOMRIGHT", 0, -1)
        b.view, b.index = views[i], i
        b:SetScript("OnClick", onClick)
        b:SetScript("OnEnter", onEnter)
        b:SetScript("OnLeave", onLeave)
        b:Hide()
        t.counts[i] = b
        if i > 1 then
            local s = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            s:SetText("/")
            s:Hide()
            t.seps[i - 1] = s
        end
    end
    header.todo = t
    return t
end

-- Right to left from the collapse sign, a slash before every shown count but the leftmost. Each
-- count's click area reaches halfway over the slash on each side of it and the header's full height, or a
-- click that misses a count lands on the header and collapses the section.
local function layout(header, t)
    local prev, used = nil, 0
    local reach = GAP + math.ceil(t.seps[1]:GetStringWidth() / 2)
    for i = #t.counts, 1, -1 do
        local b = t.counts[i]
        if b:IsShown() then
            local anchor, gap = header.collapse, EDGE_GAP
            if prev then
                used = used + 1
                local s = t.seps[used]
                s:ClearAllPoints()
                s:SetPoint("RIGHT", prev, "LEFT", -GAP, 0)
                s:Show()
                anchor, gap = s, GAP
            end
            b:SetSize(b.text:GetStringWidth() + 2, b.text:GetStringHeight() + 4)
            b:ClearAllPoints()
            b:SetPoint("RIGHT", anchor, "LEFT", -gap, 0)
            b._left, b._right = 0, prev and reach or 0
            if prev then prev._left = reach end
            prev = b
        end
    end
    for i = used + 1, #t.seps do t.seps[i]:Hide() end
    for _, b in ipairs(t.counts) do
        if b:IsShown() then
            local rise = math.max(0, (header:GetHeight() - b:GetHeight()) / 2)
            b:SetHitRectInsets(-b._left, -b._right, -rise, -rise)
        end
    end
end

function TodoCounts:Paint(header, group)
    local TodoMode = ns:GetModule("TodoMode")
    local cfg = ns:GetModule("DB"):Tracker()
    local t = header.todo
    local made = not t
    if made then t = build(header) end
    header._todoGroup = group
    local picked = TodoMode:View()
    for i, b in ipairs(t.counts) do
        local shown = TodoMode:Shown(cfg, i)
        b:SetShown(shown)
        if shown then
            b.text:SetText(tostring(group.todo[i] or 0))
            local lit = b.view == picked
            b:SetAlpha(lit and 1 or DIM_ALPHA)
            b.line:SetShown(lit)
        end
    end
    -- Styled once when made, or a header's first counts wear the stock font until the next render.
    if made then self:Style(header, cfg) end
    layout(header, t)
end

function TodoCounts:Clear(header)
    header._todoGroup = nil
    local t = header.todo
    if not t then return end
    for _, b in ipairs(t.counts) do b:Hide() end
    for _, s in ipairs(t.seps) do s:Hide() end
end

function TodoCounts:Mirror(dst, src)
    if src._todoGroup then self:Paint(dst, src._todoGroup) else self:Clear(dst) end
end

-- Sized off the header count's own delta, so the default is the size that count has always had.
function TodoCounts:Style(header, cfg)
    local t = header.todo
    if not (t and cfg) then return end
    local Media = ns:GetModule("Media")
    local delta = (tonumber(cfg.headerSizeDelta) or 4) - 6 + (tonumber(cfg.todoCountSizeDelta) or 0)
    for i, b in ipairs(t.counts) do
        Media:ApplyFont(b.text, delta)
        local c, d = Util.Color(cfg[COLOR_KEYS[i]]) or {}, DEFAULTS[i]
        local r, g, bl = c.r or d.r, c.g or d.g, c.b or d.b
        b.text:SetTextColor(r, g, bl)
        b.line:SetColorTexture(r, g, bl, 1)
    end
    local r, g, b = header.count:GetTextColor()
    for _, s in ipairs(t.seps) do
        Media:ApplyFont(s, delta)
        s:SetTextColor(r, g, b)
    end
    if header._todoGroup then layout(header, t) end
end
