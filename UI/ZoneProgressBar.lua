local _, ns = ...

local ZoneBar = ns:RegisterModule("ZoneProgressBar", {})
local L       = ns.L

local FRAME_W     = 220
local FRAME_H     = 38
local BAR_H       = 12
local ROW_PAD_TOP = 2
local ROW_PAD_BOT = 4
local DEFAULT_BAR = [[Interface\TargetingFrame\UI-StatusBar]]

local TITLE_COLOR = { 0.93, 0.32, 0.10 }
local COUNT_COLOR = { 0.92, 0.72, 0.02 }
local BORDER_RED  = { 0.635, 0.000, 0.039, 1 }

local function cfg()
    return ns:GetModule("DB"):Tracker()
end

local function barState()
    local t = cfg()
    if not t then return nil end
    t.zoneProgressBar = t.zoneProgressBar or {}
    return t.zoneProgressBar
end

local function enabled()
    local t = cfg()
    return (t and t.showZoneProgressBar) == true
end

-- Docked needs the tracker window, which Blizzard's tracker replaces.
local function isFloating()
    if ns:UsesBlizzardTracker() then return true end
    local t = cfg()
    return ((t and t.zoneProgressLocation) or "floating") == "floating"
end

local function applyBarFill(bar)
    if not bar then return end
    local st = barState() or {}
    local Media = ns:GetModule("Media")
    bar:SetStatusBarTexture(Media:GetStatusBarFile(st.barTexture) or DEFAULT_BAR)
    local c = st.barColor
    if c then bar:SetStatusBarColor(c.r, c.g, c.b, c.a or 1)
    else       bar:SetStatusBarColor(0.26, 0.42, 1.0) end
end

function ZoneBar:ApplySettings()
    local f = self.frame
    if not f then return end
    local st = barState() or {}
    local scale = st.scale or 1.0
    if scale <= 0 then scale = 1.0 end

    -- Offsets are stored in UIParent units but SetPoint reads them in the frame's own
    -- scaled space, so they are divided back out. Without this the bar walks across the
    -- screen as the scale slider moves instead of growing in place. EQ has this bug.
    f:SetScale(scale)
    f:ClearAllPoints()
    f:SetPoint(st.point or "CENTER", UIParent, st.relPoint or st.point or "CENTER",
               (st.x or 0) / scale, (st.y or 220) / scale)

    if st.showBackground == false then
        f:SetBackdropColor(0, 0, 0, 0)
    elseif st.backgroundColor then
        local c = st.backgroundColor
        -- A picked color carries its own alpha, so the lock fade below stops applying.
        f:SetBackdropColor(c.r or 0, c.g or 0, c.b or 0, c.a or 1)
    else
        -- Fades slightly once locked, so an unlocked bar reads as draggable
        f:SetBackdropColor(0, 0, 0, st.locked and 0.40 or 0.55)
    end

    if st.showBorder == false then
        f:SetBackdropBorderColor(0, 0, 0, 0)
    else
        local bc = st.borderColor
        if bc then f:SetBackdropBorderColor(bc.r, bc.g, bc.b, bc.a or 1)
        else       f:SetBackdropBorderColor(BORDER_RED[1], BORDER_RED[2], BORDER_RED[3], BORDER_RED[4]) end
    end
end

function ZoneBar:_SavePosition()
    local f, st = self.frame, barState()
    if not (f and st) then return end
    local point, _, relPoint, x, y = f:GetPoint()
    if not point then return end
    local scale = f:GetScale()
    if not scale or scale <= 0 then scale = 1.0 end
    st.point, st.relPoint = point, relPoint
    st.x, st.y = (x or 0) * scale, (y or 0) * scale
end

function ZoneBar:_ContextMenu()
    if not self.frame then return end
    local st = barState() or {}
    ns:GetModule("Options").ui:ShowMenu({
        { kind = "title", text = L["Zone Progress Bar"] },
        { text = st.locked and L["Unlock (allow moving)"] or L["Lock position"], onClick = function()
            local s = barState()
            if s then s.locked = not s.locked end
            ZoneBar:ApplySettings()
        end },
        { text = L["Reset position"], onClick = function()
            local s = barState()
            if s then s.point, s.relPoint, s.x, s.y = "CENTER", "CENTER", 0, 220 end
            ZoneBar:ApplySettings()
        end },
        { kind = "divider" },
        { text = L["Cancel"] },
    })
end

function ZoneBar:_Acquire()
    if self.frame then return self.frame end

    local f = CreateFrame("Frame", "EQOTZoneProgressBar", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    f:SetSize(FRAME_W, FRAME_H)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s)
        local st = barState()
        if st and st.locked then return end
        s:StartMoving()
    end)
    f:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        ZoneBar:_SavePosition()
    end)
    f:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then ZoneBar:_ContextMenu() end
    end)

    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 6, -4)
    f.title:SetJustifyH("LEFT")
    f.title:SetTextColor(TITLE_COLOR[1], TITLE_COLOR[2], TITLE_COLOR[3])

    f.count = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.count:SetPoint("TOPRIGHT", -6, -5)
    f.count:SetTextColor(COUNT_COLOR[1], COUNT_COLOR[2], COUNT_COLOR[3])

    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetPoint("BOTTOMLEFT", 6, 5)
    bar:SetPoint("BOTTOMRIGHT", -6, 5)
    bar:SetHeight(BAR_H)
    bar:SetMinMaxValues(0, 100)
    applyBarFill(bar)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0.04, 0.07, 0.18, 0.9)
    bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.label:SetPoint("CENTER")
    f.bar = bar

    self.frame = f
    self:ApplySettings()
    return f
end

-- Docked, the bar is drawn by the tracker's own render pass, so both counts come back
-- together and one count walk serves the header and the bar.
function ZoneBar:DockedState()
    if not (enabled() and not isFloating()) then return nil end
    local done, total, zoneName = ns:GetModule("ZoneProgress"):Current()
    if not total or total <= 0 then return nil end
    return done, total, zoneName or ""
end

-- Whether the tracker draws the bar as one of its sections, whatever the zone holds right now.
function ZoneBar:IsDocked()
    return (enabled() and not isFloating()) and true or false
end

function ZoneBar:_AcquireDocked(parent)
    local bar = self.docked
    if bar then
        if bar:GetParent() ~= parent then bar:SetParent(parent) end
        return bar
    end
    self.docked = self:BuildDockedBar(parent)
    return self.docked
end

-- Also the Appearance preview's, which draws a docked bar of its own rather than borrowing this one.
function ZoneBar:BuildDockedBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetHeight(BAR_H)
    bar:SetMinMaxValues(0, 100)
    applyBarFill(bar)

    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0.04, 0.07, 0.18, 0.9)

    bar.border = CreateFrame("Frame", nil, bar, BackdropTemplateMixin and "BackdropTemplate")
    bar.border:SetPoint("TOPLEFT", -1, 1)
    bar.border:SetPoint("BOTTOMRIGHT", 1, -1)
    bar.border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    bar.border:SetBackdropBorderColor(0, 0, 0, 0.9)

    bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.label:SetPoint("CENTER")

    return bar
end

function ZoneBar:HideDocked()
    if self.docked then self.docked:Hide() end
end

-- The zone name and the count live on the section header, so the bar itself carries only
-- its percentage, exactly as EQ draws it.
function ZoneBar:RenderDocked(content, y, done, total)
    return self:DrawDocked(self:_AcquireDocked(content), content, y, done, total)
end

function ZoneBar:DrawDocked(bar, content, y, done, total)
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -(y + ROW_PAD_TOP))
    bar:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(y + ROW_PAD_TOP))

    local pct = (done / total) * 100
    bar:SetValue(pct)
    bar.label:SetText(("%d%%"):format(math.floor(pct + 0.5)))

    ns:GetModule("Media"):ApplyFont(bar.label, -2)
    applyBarFill(bar)

    bar:Show()
    return ROW_PAD_TOP + BAR_H + ROW_PAD_BOT
end

local function refreshTracker()
    local Tracker = ns:GetModule("Tracker")
    if Tracker then Tracker:Refresh() end
end

function ZoneBar:Update()
    if not (enabled() and isFloating()) then
        if self.frame then self.frame:Hide() end
        -- Reached with the feature on only while docked, and the tracker owns that repaint
        if enabled() then refreshTracker() end
        return
    end

    local done, total, zoneName = ns:GetModule("ZoneProgress"):Current()
    if not total or total <= 0 then
        if self.frame then self.frame:Hide() end
        return
    end

    local f   = self:_Acquire()
    local pct = (done / total) * 100

    f.title:SetText(zoneName or "")
    f.count:SetText(done .. "/" .. total)
    f.bar:SetValue(pct)
    f.bar.label:SetText(("%d%%"):format(math.floor(pct + 0.5)))

    local st = barState() or {}
    local hc = st.headerColor
    if hc then f.title:SetTextColor(hc.r, hc.g, hc.b, hc.a or 1)
    else       f.title:SetTextColor(TITLE_COLOR[1], TITLE_COLOR[2], TITLE_COLOR[3]) end
    local cc = st.countColor
    if cc then f.count:SetTextColor(cc.r, cc.g, cc.b, cc.a or 1)
    else       f.count:SetTextColor(COUNT_COLOR[1], COUNT_COLOR[2], COUNT_COLOR[3]) end

    -- The bar's own font applies to the floating frame only, as it does in EQ. Docked, the
    -- header is a section header and the label follows the tracker font.
    local Media = ns:GetModule("Media")
    Media:ApplyTitleFont(f.title, st.font)
    Media:ApplyFont(f.count, -2, st.font)
    Media:ApplyFont(f.bar.label, -2, st.font)
    applyBarFill(f.bar)

    f:Show()
end

-- Rendered rather than refreshed: turning either setting off has to clear the docked bar
-- in the same click, and Refresh alone would leave it up for the debounce window.
function ZoneBar:SetEnabled(on)
    local t = cfg()
    if t then t.showZoneProgressBar = on and true or false end
    self:Update()
    local Tracker = ns:GetModule("Tracker")
    if Tracker then Tracker:Render() end
end

function ZoneBar:SetLocation(loc)
    local t = cfg()
    if t then t.zoneProgressLocation = loc end
    self:Update()
    local Tracker = ns:GetModule("Tracker")
    if Tracker then Tracker:Render() end
end

function ZoneBar:RefreshAppearance()
    self:ApplySettings()
    self:Update()
end

function ZoneBar:DebugLine()
    local function shown(o)
        if not o then return "none" end
        return o:IsShown() and "shown" or "hidden"
    end
    local done, total, zoneName = self:DockedState()
    return ("zone bar: %s, location=%s, float %s, docked %s%s"):format(
        enabled() and "on" or "off",
        isFloating() and "floating" or "tracker",
        shown(self.frame), shown(self.docked),
        done and (" %s %d/%d"):format(zoneName, done, total) or "")
end

function ZoneBar:OnEnable()
    local Events = ns:GetModule("Events")
    local function refresh() self:Update() end
    Events:On("ZONE_CHANGED_NEW_AREA", refresh)
    Events:On("PLAYER_ENTERING_WORLD", refresh)
    Events:On("QUEST_TURNED_IN",       refresh)
    Events:On("QUEST_REMOVED",         refresh)
    Events:On("QUESTLINE_UPDATE",      refresh)
    ns:GetModule("ZoneProgress"):OnDirty(refresh)
    self:Update()
end
