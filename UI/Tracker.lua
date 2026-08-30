local _, ns = ...

local Tracker = ns:RegisterModule("Tracker", {})
local L       = ns.L

local CONTENT_PAD      = 4
local SCROLLBAR_GUTTER = 26
local DRAG_HANDLE_H    = 14
local GRIP_SIZE        = 14
local HEADER_ICON_SZ   = 13
local REFRESH_THROTTLE = 0.25

local WQ_PIN_FRACTION  = 0.40
local PINNED_GROUP     = "worldquests"
local CONTAINER_GROUP  = "scenarios"
-- Registered by Quests on retail and QuestsClassic on Classic, so its own groups list is what
-- names the sections the empty rule counts - campaign and quests on one flavor, quests on the
-- other. Never a hardcoded pair here.
local QUEST_PROVIDER   = "quests"

-- Hiding the bar reclaims its gutter for text, so the inset is a function of the
-- setting rather than a constant.
local function scrollGutter(cfg)
    if cfg and cfg.hideScrollBar == true then return CONTENT_PAD * 2 end
    return SCROLLBAR_GUTTER
end

-- The pinned region reserves its header plus a 2px gap before its own scroll area.
-- Derived rather than a constant so it tracks the section header height.
local function headerBand()
    return ns:GetModule("Sections"):Height() + 2
end
local MIN_W, MIN_H     = 200, 100
local MAX_W, MAX_H     = 600, 2000

local function frameScale(f)
    local s = f and f:GetScale()
    if not s or s <= 0 then return 1 end
    return s
end

-- Offsets are stored in UIParent units but SetPoint reads them in the frame's own scaled
-- space, so they are divided back out. Without this the tracker slides across the screen
-- as the scale slider moves instead of growing in place.
function Tracker:_ApplyPosition(anchor, relativePoint, x, y)
    local f = self.frame
    if not f then return end
    local scale = frameScale(f)
    f:ClearAllPoints()
    f:SetPoint(anchor or "CENTER", UIParent, relativePoint or anchor or "CENTER",
               (x or 0) / scale, (y or 0) / scale)
end

local function applyScaleWhenSafe() Tracker:ApplyScale() end

-- A secure quest-item button makes every size and anchor call on the frames ABOVE it
-- protected, not just the button. Once one has ever been built the whole chain stays that
-- way for the session, so each such call asks this first and defers instead of erroring.
local function secureLocked()
    local IB = ns:GetModule("ItemButtons")
    return (IB and IB.Locked and IB:Locked()) and true or false
end

-- Above the drag handle's frame level so the handle does not eat the click.
local function makeHeaderIcon(f, texture, tooltip, onClick)
    local b = CreateFrame("Button", nil, f)
    b:SetSize(HEADER_ICON_SZ, HEADER_ICON_SZ)
    b:SetFrameLevel(f:GetFrameLevel() + 10)
    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture(texture)
    tex:SetAlpha(0.85)
    b:SetScript("OnEnter", function(btn)
        if Tracker:IsClickThrough() then return end
        tex:SetAlpha(1)
        if not tooltip then return end
        local tip = ns.Util.Tooltip()
        tip:SetOwner(btn, "ANCHOR_BOTTOMLEFT")
        tip:AddLine(tooltip)
        tip:Show()
    end)
    b:SetScript("OnLeave", function()
        tex:SetAlpha(0.85)
        ns.Util.Tooltip():Hide()
    end)
    b:SetScript("OnClick", function()
        if Tracker:IsClickThrough() then return end
        onClick()
    end)
    return b
end

-- Icons registered through ns:GetModule("API") are built lazily here, so an addon that registers
-- before or after the frame exists lands the same way. The list is empty in the standalone
-- case. The whole run is rebuilt rather than appended to, because a de-registered icon has to
-- disappear and a re-registered one has to pick up its new texture and handler - a button
-- built once captures the spec it was made from.
function Tracker:RebuildHeaderIcons()
    local f = self.frame
    if not (f and f.headerIcons) then return end

    local specs = ns:GetModule("API"):HeaderIcons()
    f._apiIcons = f._apiIcons or {}

    local live = {}
    for i = 1, #specs do live[specs[i].id] = true end
    -- A frame cannot be destroyed, so a dropped icon is hidden and unanchored instead.
    for id, b in pairs(f._apiIcons) do
        if not live[id] then
            b:Hide()
            b:ClearAllPoints()
            f._apiIcons[id] = nil
        end
    end

    -- The cogwheel is EQOT's own and always index 1, so the API run is rebuilt after it.
    for i = #f.headerIcons, 2, -1 do f.headerIcons[i] = nil end

    for i = 1, #specs do
        local spec = specs[i]
        local b = f._apiIcons[spec.id]
        -- AddHeaderIcon stores a fresh table per call, so an id re-registered with a new
        -- texture or handler arrives as a different spec and has to be rebuilt - the button
        -- captured the spec it was made from.
        if b and b._apiSpec ~= spec then
            b:Hide()
            b:ClearAllPoints()
            f._apiIcons[spec.id] = nil
            b = nil
        end
        if not b then
            b = makeHeaderIcon(f, spec.texture, spec.tooltip, function() spec.onClick() end)
            b._apiSpec = spec
            f._apiIcons[spec.id] = b
        end
        b._dbKey = spec.dbKey
        f.headerIcons[#f.headerIcons + 1] = b
    end

    self:ApplyHeaderIcons()
end

-- Visibility and anchoring together, because a hidden icon has to drop out of the run rather
-- than leave a gap in it - so toggling the cogwheel off slides the rest right.
function Tracker:ApplyHeaderIcons()
    local f = self.frame
    if not (f and f.headerIcons) then return end
    local DB  = ns:GetModule("DB")
    local cfg = DB and DB:Tracker()

    local prev
    for i = 1, #f.headerIcons do
        local b = f.headerIcons[i]
        if cfg and b._dbKey and cfg[b._dbKey] == false then
            b:Hide()
        else
            b:Show()
            b:ClearAllPoints()
            if prev then
                b:SetPoint("RIGHT", prev, "LEFT", -3, 0)
            else
                b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -1)
            end
            prev = b
        end
    end
end

-- Blizzard's scroll bar keeps its own handlers, so a click in the invisible gutter scrolled
-- a tracker nobody could see. The bar's children are walked rather than named: the template
-- differs between flavors.
local function suspendBarInput(sf, suspended)
    local bar = sf and (sf.ScrollBar or sf.scrollBar)
    if not bar then return end
    bar:EnableMouse(not suspended)
    local kids = { bar:GetChildren() }
    for i = 1, #kids do
        if kids[i].EnableMouse then kids[i]:EnableMouse(not suspended) end
    end
end

-- A list that shrinks leaves the offset past its new end, so the frame draws blank where the
-- content used to be and the section reads as empty until the player scrolls back up.
local function clampScroll(sf)
    if not sf then return end
    local range = math.max(0, sf:GetVerticalScrollRange() or 0)
    if (sf:GetVerticalScroll() or 0) > range then sf:SetVerticalScroll(range) end
end

function Tracker:SetScrollInputSuspended(suspended)
    local f = self.frame
    if not f then return end
    suspendBarInput(f.scroll, suspended)
    suspendBarInput(f.eventsScroll, suspended)
end

-- Expanding a section near the bottom of a long list puts its rows below the viewport, so the
-- header flips to "-" and nothing else appears to happen. Scrolls only when the body is short
-- of room, and never past the end.
function Tracker:ScrollSectionIntoView(groupID)
    local f = self.frame
    local top = f and f._sectionTop and f._sectionTop[groupID]
    local sf  = f and f.scroll
    if not (top and sf) or secureLocked() then return end

    local viewH = sf:GetHeight() or 0
    local cur   = sf:GetVerticalScroll() or 0
    local want  = math.min(top, math.max(0, sf:GetVerticalScrollRange() or 0))
    -- One header plus a little body is the bar for "you can see that it opened".
    local need  = ns:GetModule("Sections"):Height() + 40
    if top < cur or (top + need) > (cur + viewH) then
        if want ~= cur then sf:SetVerticalScroll(want) end
    end
end

-- True whenever the tracker is alpha-hidden but still on screen. Every mouse handler in the
-- tracker checks this. Without it an alpha-0 tracker keeps taking clicks, tooltips and the
-- wheel, which is the trap EQ leaves open on all but two of its paths.
function Tracker:IsClickThrough()
    local f = self.frame
    return (f and f._eqotHidden and f:IsShown()) and true or false
end

local function renderWhenSafe() Tracker:Render() end
local function applyWQPosWhenSafe() Tracker:ApplyWorldQuestsPosition() end
local function resetPositionWhenSafe() Tracker:ResetPosition() end
local function applyContentInsetWhenSafe() Tracker:ApplyContentInset() end

-- One key for the whole render, so a combat full of quest events collapses into a single
-- relayout when it ends rather than one per event.
local function deferRender()
    ns:GetModule("Events"):RunWhenOutOfCombat("eqot.deferredRender", renderWhenSafe)
end

-- Deferred on BOTH positions, though nothing in this region is secure. Render skips
-- scroll:SetSize under the same lock, so growing the region in combat moved half the layout
-- and left the quest area at its old size, drawing rows past the tracker's bottom edge until
-- the fight ended. Bottom is the default, so that was the common case.
local function setRegionHeight(region, h)
    if secureLocked() then
        deferRender()
        return
    end
    region:SetHeight(h)
end

-- Re-anchors as well as scaling, or the frame keeps offsets meant for the old scale
function Tracker:ApplyScale()
    local f = self.frame
    if not f then return end
    -- Deferred rather than dropped: SetScale is protected once secure children land here,
    -- and the key collapses a whole slider drag into one call when combat ends
    if InCombatLockdown() then
        ns:GetModule("Events"):RunWhenOutOfCombat("eqot.applyScale", applyScaleWhenSafe)
        return
    end
    local cfg = ns:GetModule("DB"):Tracker()
    if not cfg then return end
    f:SetScale(cfg.scale or 1)
    self:_ApplyPosition(cfg.anchor, cfg.relativePoint, cfg.xOffset, cfg.yOffset)
end

function Tracker:PersistPositionAndSize()
    local f = self.frame
    if not f then return end
    local cfg = ns:GetModule("DB"):Tracker()
    if not cfg then return end

    cfg.width     = math.floor(f:GetWidth())
    cfg.maxHeight = math.floor(f:GetHeight())

    local point, _, relativePoint, x, y = f:GetPoint()
    if not point then return end

    local scale = frameScale(f)
    cfg.anchor        = point
    cfg.relativePoint = relativePoint or point
    cfg.xOffset       = math.floor((x or 0) * scale + 0.5)
    cfg.yOffset       = math.floor((y or 0) * scale + 0.5)

    self:_ApplyPosition(cfg.anchor, cfg.relativePoint, cfg.xOffset, cfg.yOffset)
end

function Tracker:IsLocked()
    local gen = ns:GetModule("DB"):General()
    return (gen and gen.lockTracker) and true or false
end

function Tracker:ApplyLockState()
    local f = self.frame
    if not (f and f.grip) then return end
    local locked = self:IsLocked()
    if locked and f._dragging then
        pcall(f.StopMovingOrSizing, f)
        f._dragging = nil
    end
    f.grip:SetAlpha(locked and 0 or 1)
    f.grip:EnableMouse(not locked)
end

function Tracker:BuildFrame()
    local cfg = ns:GetModule("DB"):Tracker()

    local f = CreateFrame("Frame", "EQOTTrackerFrame", UIParent)
    self.frame = f
    f:SetSize(cfg.width, cfg.maxHeight)
    f:SetScale(cfg.scale or 1)
    self:_ApplyPosition(cfg.anchor, cfg.relativePoint, cfg.xOffset, cfg.yOffset)
    f:SetMovable(true)
    f:SetResizable(true)
    if ns.Has.ResizeBounds then f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H) end
    f:SetClampedToScreen(true)
    -- The tooltip hangs off UIParent, so hiding the tracker under the cursor delivers no
    -- OnLeave. The shared tooltip used to be cleared by the next hover anywhere.
    f:HookScript("OnHide", function() ns.Util.Tooltip():Hide() end)

    local drag = CreateFrame("Frame", nil, f)
    drag:SetPoint("TOPLEFT")
    drag:SetPoint("TOPRIGHT")
    drag:SetHeight(DRAG_HANDLE_H)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")

    local hint = drag:CreateTexture(nil, "OVERLAY")
    hint:SetAllPoints()
    hint:SetColorTexture(1, 1, 1, 0)

    drag:SetScript("OnEnter", function()
        if Tracker:IsClickThrough() then return end
        hint:SetColorTexture(1, 1, 1, 0.15)
        local tip = ns.Util.Tooltip()
        tip:SetOwner(drag, "ANCHOR_BOTTOM")
        tip:SetText("EQ Objective Tracker", 0.92, 0.72, 0.02)
        if Tracker:IsLocked() then
            tip:AddLine(L["Tracker locked"], 1, 0.3, 0.3)
            tip:AddLine(L["Use /eqot unlock to move it."], 0.8, 0.8, 0.8)
        else
            tip:AddLine(L["Drag to move, corner grip to resize."], 1, 1, 1)
            tip:AddLine(L["/eqot for options"], 0.8, 0.8, 0.8)
        end
        tip:Show()
    end)
    drag:SetScript("OnLeave", function()
        hint:SetColorTexture(1, 1, 1, 0)
        ns.Util.Tooltip():Hide()
    end)

    local cog = makeHeaderIcon(f, "Interface\\AddOns\\EQObjectiveTracker\\Media\\Textures\\cogwheel.tga",
        L["Open the options panel"], function() ns:GetModule("Options"):Toggle() end)
    cog._dbKey = "showOptionsIcon"
    f.headerIcons = { cog }
    self:RebuildHeaderIcons()

    -- Only PersistPositionAndSize makes the protected SetPoint, so only it has to wait for
    -- combat to end. Deferring the whole body left the frame following the cursor for the
    -- rest of the fight and then saved wherever the cursor had wandered to.
    local function finishDrag()
        pcall(f.StopMovingOrSizing, f)
        Tracker:PersistPositionAndSize()
    end

    -- Whether StopMovingOrSizing is protected once secure buttons are armed has never been
    -- established, so it is attempted here and repeated by finishDrag if it was refused.
    local function stopDrag()
        if not f._dragging then return end
        f._dragging = nil
        pcall(f.StopMovingOrSizing, f)
        if secureLocked() then
            ns:GetModule("Events"):RunWhenOutOfCombat("eqot.stopDrag", finishDrag)
            return
        end
        Tracker:PersistPositionAndSize()
    end

    drag:SetScript("OnDragStart", function()
        if InCombatLockdown() or Tracker:IsLocked() then return end
        f:StartMoving()
        f._dragging = true
    end)
    drag:SetScript("OnDragStop", stopDrag)

    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(GRIP_SIZE, GRIP_SIZE)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    for i, len in ipairs({ 12, 8, 4 }) do
        local g = grip:CreateTexture(nil, "OVERLAY")
        g:SetColorTexture(1, 1, 1, 0.5)
        g:SetSize(len, 1)
        g:SetPoint("BOTTOMRIGHT", -2, 2 + (i - 1) * 3)
    end
    grip:SetScript("OnMouseDown", function()
        if InCombatLockdown() or Tracker:IsLocked() then return end
        f:StartSizing("BOTTOMRIGHT")
        f._dragging = true
    end)
    grip:SetScript("OnMouseUp", stopDrag)

    -- Its own frame one level below so the backdrop never draws over rows
    local bg = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate")
    bg:SetAllPoints(f)
    bg:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))
    f.bgFrame = bg
    f.background = bg:CreateTexture(nil, "BACKGROUND")
    f.background:SetAllPoints()
    f.background:Hide()

    local scenarioContainer = CreateFrame("Frame", nil, f)
    scenarioContainer:SetPoint("TOPLEFT", CONTENT_PAD, -DRAG_HANDLE_H)
    -- Reserve the quest list's scroll bar gutter so the banner lines up with scrolled text
    scenarioContainer:SetPoint("TOPRIGHT", -(scrollGutter(cfg) - CONTENT_PAD), -DRAG_HANDLE_H)
    scenarioContainer:SetHeight(1)
    f.scenarioContainer = scenarioContainer
    scenarioContainer:SetScript("OnSizeChanged", function() Tracker:Refresh() end)

    local eventsRegion = CreateFrame("Frame", nil, f)
    eventsRegion:SetHeight(1)
    eventsRegion:Hide()
    f.eventsRegion = eventsRegion

    local eventsScroll = CreateFrame("ScrollFrame", nil, eventsRegion, "UIPanelScrollFrameTemplate")
    eventsScroll:SetPoint("TOPLEFT",     eventsRegion, "TOPLEFT",     0, -headerBand())
    eventsScroll:SetPoint("BOTTOMRIGHT", eventsRegion, "BOTTOMRIGHT", 0, 0)
    local eventsContent = CreateFrame("Frame", nil, eventsScroll)
    eventsContent:SetSize(math.max(1, cfg.width - scrollGutter(cfg)), 1)
    eventsScroll:SetScrollChild(eventsContent)
    f.eventsScroll, f.eventsContent = eventsScroll, eventsContent

    local eBg = f:CreateTexture(nil, "BORDER")
    local eBar = eventsScroll.ScrollBar or eventsScroll.scrollBar
    if eBar then
        eBg:SetPoint("TOPLEFT",     eBar, "TOPLEFT",    -1, 0)
        eBg:SetPoint("BOTTOMRIGHT", eBar, "BOTTOMRIGHT", 1, 0)
    else
        eBg:SetPoint("TOPLEFT",     eventsScroll, "TOPRIGHT",     0, 1)
        eBg:SetPoint("BOTTOMRIGHT", eventsRegion, "BOTTOMRIGHT", -2, 0)
    end
    eBg:Hide()
    f.eventsScrollBarBG = eBg

    -- scroll and eventsRegion are anchored by ApplyWorldQuestsPosition per the Top/Bottom
    -- setting, so they are deliberately not hard-anchored here.
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(math.max(1, cfg.width - scrollGutter(cfg)), 1)
    scroll:SetScrollChild(content)

    local function wheelScroll(sf, delta)
        if Tracker:IsClickThrough() then return end
        -- The one protected site that must REFUSE rather than defer: running a wheel turn
        -- minutes later when combat drops is worse than not scrolling. Only this scroll frame
        -- is affected - its content child parents the secure item buttons, while eventsScroll
        -- is a disjoint subtree that hosts nothing secure.
        if sf == scroll and secureLocked() then return end
        local range = sf:GetVerticalScrollRange() or 0
        if range <= 0 then return end
        local new = (sf:GetVerticalScroll() or 0) - delta * 24
        sf:SetVerticalScroll(math.max(0, math.min(new, range)))
    end
    for _, sf in ipairs({ scroll, eventsScroll }) do
        sf:EnableMouseWheel(true)
        sf:SetScript("OnMouseWheel", wheelScroll)
    end

    -- Anchored to the bar itself when the template exposes one, so it tracks the bar's
    -- real width rather than assuming the gutter constant matches it.
    local sbBG = f:CreateTexture(nil, "BORDER")
    local sBar = scroll.ScrollBar or scroll.scrollBar
    if sBar then
        sbBG:SetPoint("TOPLEFT",     sBar, "TOPLEFT",    -1, 0)
        sbBG:SetPoint("BOTTOMRIGHT", sBar, "BOTTOMRIGHT", 1, 0)
    else
        sbBG:SetPoint("TOPLEFT",     scroll, "TOPRIGHT",     0, 1)
        sbBG:SetPoint("BOTTOMRIGHT", bg,     "BOTTOMRIGHT", -2, GRIP_SIZE + 2)
    end
    sbBG:Hide()
    f.scrollBarBG = sbBG

    f:SetScript("OnSizeChanged", function() Tracker:Refresh() end)

    f.drag, f.grip, f.scroll, f.content = drag, grip, scroll, content
    self:ApplyWorldQuestsPosition()
    self:ApplyLockState()
end

-- Blizzard re-shows the bar whenever the scroll range changes, so this needs a
-- persistent hook rather than a one-shot Hide.
local function setScrollBarHidden(sf, hidden)
    if not sf then return end
    local bar = sf.ScrollBar or sf.scrollBar
    if not bar then return end
    bar._eqotHidden = hidden
    if not bar._eqotShowHook then
        bar._eqotShowHook = true
        bar:HookScript("OnShow", function(b) if b._eqotHidden then b:Hide() end end)
    end
    if hidden then
        if bar:IsShown() then bar:Hide() end
    else
        bar:SetShown((sf:GetVerticalScrollRange() or 0) > 0.5)
    end
end

local function scrollArrowButtons(bar)
    local name = bar.GetName and bar:GetName()
    local up = bar.ScrollUpButton or bar.Back
        or (name and _G[name .. "ScrollUpButton"])
    local down = bar.ScrollDownButton or bar.Forward
        or (name and _G[name .. "ScrollDownButton"])
    return up, down
end

-- Blizzard re-shows the arrows whenever the scroll range changes, so hiding needs a
-- persistent hook rather than a one-shot Hide.
local function setArrowHidden(btn, hidden)
    if not btn then return end
    btn._eqotArrowHidden = hidden
    if not btn._eqotArrowHook then
        btn._eqotArrowHook = true
        btn:HookScript("OnShow", function(b) if b._eqotArrowHidden then b:Hide() end end)
    end
    if hidden then
        if btn:IsShown() then btn:Hide() end
    elseif not btn:IsShown() then
        btn:Show()
    end
end

-- The thumb is a texture on the old slider-based bar and a frame on the newer one, so
-- both shapes are handled. The stock look is captured before the first skin so turning
-- it back off restores rather than guesses.
local function applyScrollBarSkin(sf, cfg)
    if not (sf and cfg) then return end
    local bar = sf.ScrollBar or sf.scrollBar
    if not bar then return end
    local on = cfg.skinScrollBar == true
    local c  = cfg.scrollBarThumbColor or {}
    local r, g, b, a = c.r or 0.60, c.g or 0.60, c.b or 0.65, c.a or 0.90
    local w  = cfg.scrollBarThumbWidth

    local thumbTex = bar.GetThumbTexture and bar:GetThumbTexture()
    if thumbTex then
        -- Capture the plain texture as well as the atlas. A stock thumb that is not
        -- atlas-based leaves the atlas nil, and restoring on that alone strands the
        -- solid color permanently, since the skinned flag is cleared either way.
        if not bar._eqotThumbCaptured then
            bar._eqotThumbCaptured = true
            bar._eqotThumbAtlas   = thumbTex.GetAtlas and thumbTex:GetAtlas() or nil
            bar._eqotThumbTexture = thumbTex.GetTexture and thumbTex:GetTexture() or nil
            bar._eqotThumbW       = thumbTex:GetWidth()
        end
        if on then
            thumbTex:SetTexture(nil)
            thumbTex:SetColorTexture(r, g, b, a)
            if w and w > 0 then thumbTex:SetWidth(w) end
        elseif bar._eqotThumbSkinned then
            if bar._eqotThumbAtlas then
                thumbTex:SetAtlas(bar._eqotThumbAtlas, true)
            elseif bar._eqotThumbTexture then
                thumbTex:SetTexture(bar._eqotThumbTexture)
            end
            if bar._eqotThumbW and bar._eqotThumbW > 0 then thumbTex:SetWidth(bar._eqotThumbW) end
        end
        bar._eqotThumbSkinned = on
    else
        local tf = bar.Thumb or (bar.Track and bar.Track.Thumb)
        if tf then
            local skin = tf._eqotSkinTex
            -- 0 is truthy in Lua, so a width captured before the thumb was sized would
            -- latch forever and the restore below could never run.
            if not tf._eqotW or tf._eqotW <= 0 then tf._eqotW = tf:GetWidth() end
            if on then
                if not skin then
                    skin = tf:CreateTexture(nil, "OVERLAY")
                    skin:SetAllPoints(tf)
                    tf._eqotSkinTex = skin
                end
                skin:SetColorTexture(r, g, b, a)
                skin:Show()
                if w and w > 0 then tf:SetWidth(w) end
            elseif skin then
                skin:Hide()
                if tf._eqotW > 0 then tf:SetWidth(tf._eqotW) end
            end
        end
    end

    local up, down = scrollArrowButtons(bar)
    setArrowHidden(up,   cfg.hideScrollArrows == true)
    setArrowHidden(down, cfg.hideScrollArrows == true)
end

function Tracker:ApplyFrameSkin(cfg)
    local f = self.frame
    if not (f and f.bgFrame and cfg) then return end

    if cfg.showBackground then
        local c = cfg.backgroundColor or {}
        f.background:SetColorTexture(c.r or 0, c.g or 0, c.b or 0, c.a or 0.6)
        f.background:Show()
    else
        f.background:Hide()
    end

    -- SetBackdrop rebuilds the edge textures, so only call it when the size changes
    local size = math.max(1, cfg.borderSize or 1)
    if f._borderSize ~= size then
        f._borderSize = size
        f.bgFrame:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = size })
        f.bgFrame:SetBackdropColor(0, 0, 0, 0)
    end

    if cfg.showBorder then
        local c = cfg.borderColor or {}
        f.bgFrame:SetBackdropBorderColor(c.r or 0, c.g or 0, c.b or 0, c.a or 1)
    else
        f.bgFrame:SetBackdropBorderColor(0, 0, 0, 0)
    end

    -- The scroll frame is sized explicitly per render, so the gutter feeds the anchoring
    -- pass rather than a BOTTOMRIGHT point that would fight SetSize.
    self:ApplyContentInset()

    local hideBar = cfg.hideScrollBar == true
    if f.scrollBarBG then
        if cfg.scrollBarBg ~= false and not hideBar then
            local s = cfg.scrollBarBgColor or {}
            f.scrollBarBG:SetColorTexture(s.r or 0.60, s.g or 0.60, s.b or 0.65, s.a or 0.25)
            f.scrollBarBG:Show()
        else
            f.scrollBarBG:Hide()
        end
    end

    setScrollBarHidden(f.scroll, hideBar)
    setScrollBarHidden(f.eventsScroll, hideBar)
    applyScrollBarSkin(f.scroll, cfg)
    applyScrollBarSkin(f.eventsScroll, cfg)
end

-- Guarded on the last gutter: SetPoint fires scenarioContainer's OnSizeChanged, which
-- calls Refresh, so an unguarded re-inset re-enters on every pass.
function Tracker:ApplyContentInset()
    local f = self.frame
    if not (f and f.scenarioContainer) then return end
    local gutter = scrollGutter(ns:GetModule("DB"):Tracker())
    if f._scrollGutter == gutter then return end

    -- The quest scroll anchors to this container, so re-anchoring it is a protected move once
    -- a secure button exists anywhere in the chain - a quest item button, or one of the
    -- scenario spell buttons this container parents directly. The gutter is recorded only
    -- after the move lands, or the guard above would swallow the deferred retry.
    if secureLocked() then
        ns:GetModule("Events"):RunWhenOutOfCombat("eqot.contentInset", applyContentInsetWhenSafe)
        return
    end

    f._scrollGutter = gutter
    f.scenarioContainer:SetPoint("TOPLEFT",  CONTENT_PAD, -DRAG_HANDLE_H)
    f.scenarioContainer:SetPoint("TOPRIGHT", -(gutter - CONTENT_PAD), -DRAG_HANDLE_H)
end

-- Everything hangs off the scenario container's bottom rather than off the frame top, so
-- the whole stack moves down together when a scenario appears.
function Tracker:ApplyWorldQuestsPosition()
    local f = self.frame
    if not f then return end
    local scroll, region, scen = f.scroll, f.eventsRegion, f.scenarioContainer
    if not (scroll and region and scen) then return end

    -- scroll is in the quest item buttons' ancestor chain, so re-anchoring it is a protected
    -- move once one exists. It is only ANCHORED to the scenario container, never parented by
    -- it, so the spell buttons are not what protects this one
    if secureLocked() then
        ns:GetModule("Events"):RunWhenOutOfCombat("eqot.applyWQPos", applyWQPosWhenSafe)
        return
    end

    local cfg = ns:GetModule("DB"):Tracker()
    local pos = (cfg and cfg.worldQuestsPosition) or "bottom"

    scroll:ClearAllPoints()
    region:ClearAllPoints()
    if pos == "top" then
        region:SetPoint("TOPLEFT",  scen,   "BOTTOMLEFT",  0, -2)
        region:SetPoint("TOPRIGHT", scen,   "BOTTOMRIGHT", 0, -2)
        scroll:SetPoint("TOPLEFT",  region, "BOTTOMLEFT",  0, -2)
    else
        scroll:SetPoint("TOPLEFT",  scen,   "BOTTOMLEFT",  0, -2)
        region:SetPoint("TOPLEFT",  scroll, "BOTTOMLEFT",  0, -2)
        region:SetPoint("TOPRIGHT", scroll, "BOTTOMRIGHT", 0, -2)
    end
end

function Tracker:SetWorldQuestsPosition(pos)
    local cfg = ns:GetModule("DB"):Tracker()
    if cfg then cfg.worldQuestsPosition = pos end
    self:ApplyWorldQuestsPosition()
    self:Render()
end

-- Scroll widgets differ between flavors and between the old slider bar and the newer
-- one, so report what is actually on screen rather than what the template should give.
function Tracker:DebugScroll()
    local f = self.frame
    if not (f and f.scroll) then return "no frame" end
    local cfg = ns:GetModule("DB"):Tracker() or {}
    local sf  = f.scroll
    local bar = sf.ScrollBar or sf.scrollBar
    local out = {}

    local function shown(o) return o and (o:IsShown() and "shown" or "hidden") or "none" end

    out[#out + 1] = ("gutter %s range %.0f bgTex %s"):format(
        tostring(f._scrollGutter), sf:GetVerticalScrollRange() or 0, shown(f.scrollBarBG))

    -- Live frame-space offsets beside the stored UIParent ones: this fix's only symptom is
    -- geometric, and a cfg scale that disagrees with the frame means combat deferred it.
    local point, _, relPoint, px, py = f:GetPoint()
    out[#out + 1] = ("scale %.2f cfg %.2f anchor %s>%s live %.0f,%.0f stored %.0f,%.0f"):format(
        f:GetScale() or 1, cfg.scale or 1, tostring(point), tostring(relPoint),
        px or 0, py or 0, cfg.xOffset or 0, cfg.yOffset or 0)

    -- The live size beside the stored one. A reset that leaves the frame large reads here
    -- as the two disagreeing, which says whether the config or the frame kept the old value.
    out[#out + 1] = ("size live %.0fx%.0f cfg %.0fx%.0f"):format(
        f:GetWidth() or 0, f:GetHeight() or 0, cfg.width or 0, cfg.maxHeight or 0)

    if not bar then
        out[#out + 1] = "bar none"
    else
        out[#out + 1] = ("bar %s %.0fx%.0f"):format(shown(bar), bar:GetWidth() or 0, bar:GetHeight() or 0)
        local t = bar.GetThumbTexture and bar:GetThumbTexture()
        if t then
            -- Assign before tostring: a getter that returns NO values, rather than nil,
            -- leaves tostring() with zero arguments and that is an error, not a "nil"
            local tex   = t:GetTexture()
            local atlas = t.GetAtlas and t:GetAtlas()
            out[#out + 1] = ("thumbTex %s tex=%s atlas=%s w=%.0f"):format(shown(t),
                tostring(tex), tostring(atlas), t:GetWidth() or 0)
        else
            local tf = bar.Thumb or (bar.Track and bar.Track.Thumb)
            out[#out + 1] = tf and ("thumbFrame %s w=%.0f"):format(shown(tf), tf:GetWidth() or 0)
                or "thumb none"
        end
        local up, down = scrollArrowButtons(bar)
        out[#out + 1] = ("arrows %s/%s"):format(shown(up), shown(down))
    end

    out[#out + 1] = ("cfg hide=%s bg=%s skin=%s noArrows=%s"):format(
        tostring(cfg.hideScrollBar), tostring(cfg.scrollBarBg),
        tostring(cfg.skinScrollBar), tostring(cfg.hideScrollArrows))

    out[#out + 1] = ("wq %s pos=%s scrollH=%.0f regionH=%.0f contentH=%.0f"):format(
        shown(f.eventsRegion), tostring(cfg.worldQuestsPosition),
        sf:GetHeight() or 0,
        f.eventsRegion and f.eventsRegion:GetHeight() or 0,
        f.eventsContent and f.eventsContent:GetHeight() or 0)

    out[#out + 1] = ("scenario container %s h=%.0f"):format(
        shown(f.scenarioContainer),
        f.scenarioContainer and f.scenarioContainer:GetHeight() or 0)

    -- A hidden tracker skips Render, so the provider counters above are the last painted
    -- ones rather than the current state. Say so instead of letting them read as live.
    out[#out + 1] = ("frame %s%s%s"):format(shown(f),
        f._eqotUserHidden and " [toggled off]" or "",
        f._eqotPendingRender and " [render pending]" or "")

    return table.concat(out, " | ")
end

function Tracker:Refresh()
    if not self.frame then return end
    local Events = ns:GetModule("Events")
    if not (Events and Events.Debounce) then return end
    self._renderThunk = self._renderThunk or function() self:Render() end
    Events:Debounce("eqot.render", REFRESH_THROTTLE, self._renderThunk)
end

-- Hoisted: Render runs on every quest event, so a per-row closure here would
-- allocate garbage proportional to the tracker's length on every repaint.
local _buildRow, _resetRow

-- Rendered draggable rows in visual order, rebuilt every pass. RowPool is a two-level map
-- with no ordering of its own, and manual sort needs to know which row a cursor is over.
local _dragRows, _dragCount = {}, 0

function Tracker:DragRows()
    return _dragRows
end

-- World quests live outside the main scroll area in a region capped to a fraction of the
-- tracker, so a long world quest list can never push the quest sections off screen.
function Tracker:_RenderPinnedWorldQuests(group, cap, width, cfg)
    local f = self.frame
    local region, escroll, econtent = f.eventsRegion, f.eventsScroll, f.eventsContent
    if not (region and escroll and econtent) then return 0, false end

    local Sections = ns:GetModule("Sections")
    local band     = headerBand()

    -- escroll is anchored once at build from this same band, so it only goes stale after a
    -- Header Size Offset change. Re-applied on change rather than every render.
    if f._eqotBand ~= band and not secureLocked() then
        f._eqotBand = band
        escroll:SetPoint("TOPLEFT", region, "TOPLEFT", 0, -band)
    end

    local function collapseRegion()
        escroll:Hide()
        if f.eventsScrollBarBG then f.eventsScrollBarBG:Hide() end
        setRegionHeight(region, 1)
        region:Hide()
    end

    if not group or group.visibleCount == 0 or Sections:IsHidden(PINNED_GROUP) then
        collapseRegion()
        return 0, false
    end

    region:Show()

    local collapsed = Sections:IsCollapsed(PINNED_GROUP)
    local header    = Sections:Acquire(region, PINNED_GROUP)
    Sections:Place(header, region, 0, group, collapsed, cfg and cfg.showQuestTotal ~= false)

    if collapsed then
        escroll:Hide()
        if f.eventsScrollBarBG then f.eventsScrollBarBG:Hide() end
        setRegionHeight(region, band)
        return band, false
    end

    escroll:Show()
    econtent:SetWidth(math.max(1, width))

    local Row     = ns:GetModule("Row")
    local RowPool = ns:GetModule("RowPool")
    local Card    = ns:GetModule("Card")
    local gap     = Card:Gap(math.max(0, (cfg and cfg.blockSpacing) or 2), (Card:State(cfg)))

    local y, hasTimed = 0, false
    for i = 1, group.visibleCount do
        local entry = group.entries[i]
        if entry.expiresAt then hasTimed = true end
        local row = RowPool:Acquire(econtent, entry.providerID, entry.id, _buildRow)
        row:SetWidth(width)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", econtent, "TOPLEFT", 0, -y)
        y = y + Row:Render(row, entry, width, cfg) + gap
    end
    econtent:SetHeight(math.max(1, y))

    -- A cap of zero means the tracker has no room for this region at all, and the 30px floor
    -- would take band + 30 anyway - so the floor is skipped there and the region collapses.
    -- Any non-zero cap keeps the floor, which is what stops a tight tracker losing the region.
    if (cap or 0) <= 0 then
        collapseRegion()
        return 0, false
    end
    local capViewport = math.max(30, cap - band)
    local viewport    = math.max(1, math.min(y, capViewport))
    setRegionHeight(region, band + viewport)

    if escroll.UpdateScrollChildRect then escroll:UpdateScrollChildRect() end
    clampScroll(escroll)

    if f.eventsScrollBarBG then
        local needsBar = y > viewport + 0.5
        if needsBar and cfg and cfg.scrollBarBg ~= false and cfg.hideScrollBar ~= true then
            local s = cfg.scrollBarBgColor or {}
            f.eventsScrollBarBG:SetColorTexture(s.r or 0.60, s.g or 0.60, s.b or 0.65, s.a or 0.25)
            f.eventsScrollBarBG:Show()
        else
            f.eventsScrollBarBG:Hide()
        end
    end

    return band + viewport, hasTimed
end

-- Reused: Place reads only the two counts and the zone header overwrites both straight
-- after, so a fresh table per render would be pure garbage.
local _virtualGroup = { visibleCount = 0, totalCount = 0 }

function Tracker:_RenderZoneSection(content, groupID, y, gap)
    local ZoneBar = ns:GetModule("ZoneProgressBar")
    if not ZoneBar then return 0 end

    local done, total, zoneName = ZoneBar:DockedState()
    if not done then
        ZoneBar:HideDocked()
        return 0
    end

    local Sections  = ns:GetModule("Sections")
    local collapsed = Sections:IsCollapsed(groupID)
    local header    = Sections:Acquire(content, groupID)
    local added     = Sections:Place(header, content, y, _virtualGroup, collapsed, false) + gap

    header.text:SetText(zoneName)
    header.count:SetText(done .. "/" .. total)

    if collapsed then
        ZoneBar:HideDocked()
    else
        added = added + ZoneBar:RenderDocked(content, y + added, done, total) + gap
    end
    return added
end

function Tracker:_RenderScenario(group, cfg)
    local f    = self.frame
    local scen = f.scenarioContainer
    if not scen then return 1 end

    -- Zero while the card is off, which is what keeps this path byte-identical to the one that
    -- shipped before it: every offset below collapses back to what it was.
    local Card = ns:GetModule("Card")
    local cardOn, cardPad, cardBorderSize = Card:ScenarioState(cfg)
    local inset = cardOn and cardPad or 0

    -- Blizzard draws its own widget sets inside the tracker it owns, and this addon hides
    -- that frame, so these are drawn here or they are not drawn at all. Resolved defensively
    -- rather than assumed, though every TOC lists it today.
    local WB      = ns:GetModule("WidgetBlock")
    local widgetH = WB and WB:Render(scen, cfg, inset) or 0

    local entry = (group and group.visibleCount > 0) and group.entries[1] or nil
    local info
    if entry then
        local provider = ns:GetModule("Registry"):Get(CONTAINER_GROUP)
        if provider and provider.GetBanner then info = provider:GetBanner() end
    end

    local h = widgetH + math.max(1, ns:GetModule("Scenario"):Render(scen, cfg, info, entry,
                                                                   inset + widgetH))

    -- An idle container is one pixel tall, so the card is asked for CONTENT rather than for the
    -- option - without this it draws a bare padded strip across the top of the tracker all day.
    if cardOn and (info or widgetH > 0) then
        local bg, border = Card:Colors(cfg)
        Card:Draw(scen, nil, 0, cardBorderSize, bg, border)
        h = h + inset * 2
    else
        Card:Clear(scen)
    end

    -- SetHeight fires OnSizeChanged, which calls Refresh, so only touch it on a real move
    -- This container parents the scenario spell buttons and everything below hangs off its
    -- bottom, so resizing it is a protected move on two counts
    if math.abs((scen:GetHeight() or 0) - h) > 0.5 and not secureLocked() then
        scen:SetHeight(h)
    end
    return h
end

-- A group Feed has never created has no byGroup entry, and Feed builds that table lazily
-- from emitted entries - so a section with popups and no quests had nothing to draw into
-- and the player got no affordance at all, Blizzard's own popup being suppressed. Every
-- OFFER popup routes to quests, since a quest not yet in the log cannot test as campaign,
-- which makes a campaign-only log reach this and not just an empty one. Read-only: Place
-- and the row loop only ever read these two counts.
local EMPTY_GROUP = { visibleCount = 0, totalCount = 0, entries = {} }

function Tracker:Render()
    local f = self.frame
    if not f then return end
    -- Nothing on screen to lay out, so the work is deferred until Visibility shows it again.
    -- The one exception is the hide-when-no-quests rule, which is fed BY this count: stopping
    -- here would leave the count frozen at zero and the tracker could never come back. It buys
    -- that with a WHOLE render per quest event, feed build and world quest rows included, not
    -- just the count.
    if (f._eqotHidden or not f:IsShown()) and not f._eqotRenderWhileHidden then
        f._eqotPendingRender = true
        return
    end
    f._eqotPendingRender = nil
    local content = f.content
    if not content then return end

    if not _buildRow then
        local Row = ns:GetModule("Row")
        _buildRow = function() return Row:Build() end
        _resetRow = function(row) Row:Reset(row) end
    end

    local DB       = ns:GetModule("DB")
    local Feed     = ns:GetModule("Feed")
    local Row      = ns:GetModule("Row")
    local RowPool  = ns:GetModule("RowPool")
    local Sections = ns:GetModule("Sections")
    local ItemButtons = ns:GetModule("ItemButtons")
    local PopupBoxes  = ns:GetModule("AutoQuestPopup")
    local Popups      = ns:GetModule("AutoQuestPopups")
    local cfg      = DB:Tracker()

    self:ApplyFrameSkin(cfg)

    local locked = secureLocked()
    if locked then deferRender() end

    local want = math.max(1, math.floor((f:GetWidth() or 0) + 0.5) - scrollGutter(cfg))
    if math.floor((content:GetWidth() or 0) + 0.5) ~= want and not locked then
        content:SetWidth(want)
    end

    -- Rows are sized to what content ACTUALLY is, not to what it wants to be. Rows are not
    -- in the button's anchor family so they stay free in combat, but the set above is
    -- skipped there, and laying them out at the wanted width would overflow frozen content.
    local width = math.floor((content:GetWidth() or 0) + 0.5)
    if width <= 0 then width = want end

    RowPool:Begin()
    ItemButtons:Begin()
    _dragCount = 0
    PopupBoxes:ReleaseAll()
    Sections:HideAll()

    -- Before Feed:Build, because Filter reads the popup suppression set to keep a quest
    -- that is drawn as a popup box out of the section run as well.
    Popups:Refresh()

    local byGroup  = Feed:Build()
    local Card     = ns:GetModule("Card")
    local DragDrop = ns:GetModule("DragDrop")
    local dragProvider = DragDrop and DragDrop.PROVIDER
    local gap      = Card:Gap(math.max(0, (cfg and cfg.blockSpacing) or 2), (Card:State(cfg)))

    local scenarioH = self:_RenderScenario(byGroup[CONTAINER_GROUP], cfg)

    -- Counted off the group rather than off the row loop, because a COLLAPSED section draws no
    -- rows and a collapsed quest list is not an empty one. A hidden section is skipped, since
    -- the rule is about what is on screen. Popups count: a Quest Discovered box is the only
    -- affordance that quest has, Blizzard's own being suppressed.
    local questRows = 0
    do
        local provider = ns:GetModule("Registry"):Get(QUEST_PROVIDER)
        local groups   = provider and provider.groups
        for i = 1, (groups and #groups or 0) do
            local gid = groups[i]
            if not Sections:IsHidden(gid) then
                local g = byGroup[gid]
                questRows = questRows + ((g and g.visibleCount) or 0) + Popups:CountFor(gid)
            end
        end
    end

    local y        = 0
    local hasTimed = false
    local sectionTops = {}
    local tops = f._sectionTop
    if not tops then tops = {}; f._sectionTop = tops end
    wipe(tops)

    for _, groupID in ipairs(Sections:Order()) do
        if Sections:IsVirtual(groupID) then
            local top   = y
            local added = self:_RenderZoneSection(content, groupID, y, gap)
            if added > 0 then sectionTops[#sectionTops + 1] = top end
            y = y + added
        else
            local group      = byGroup[groupID] or EMPTY_GROUP
            local popupCount = Popups:CountFor(groupID)
            local anything   = group.visibleCount + popupCount
            if anything > 0 and not Sections:IsHidden(groupID) then
                local collapsed = Sections:IsCollapsed(groupID)
                local header    = Sections:Acquire(content, groupID)
                sectionTops[#sectionTops + 1] = y
                tops[groupID] = y
                y = y + Sections:Place(header, content, y, group, collapsed,
                                       cfg and cfg.showQuestTotal ~= false, popupCount) + gap

                if not collapsed then
                    -- Popup boxes sit above the rows in their section, as EQ has them
                    if popupCount > 0 then
                        y = y + PopupBoxes:Render(content, width, y, groupID)
                    end
                    for i = 1, group.visibleCount do
                        local entry = group.entries[i]
                        if entry.expiresAt then hasTimed = true end
                        local row = RowPool:Acquire(content, entry.providerID, entry.id, _buildRow)
                        row:SetWidth(width)
                        row:ClearAllPoints()
                        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                        if entry.hasItem then ItemButtons:Want(entry.id, row) end
                        y = y + Row:Render(row, entry, width, cfg) + gap
                        -- After Render, which is what stamps row._entry - DragDrop reads it
                        -- back off the row to scope a drag to its own section.
                        if entry.providerID == dragProvider then
                            _dragCount = _dragCount + 1
                            _dragRows[_dragCount] = row
                        end
                    end
                end
            end
        end
    end

    -- collectScope walks the whole array, so a row left over from a longer previous pass
    -- would put a retired frame in the drop-index scan.
    for i = _dragCount + 1, #_dragRows do _dragRows[i] = nil end

    local questContentH = y
    if not locked then content:SetHeight(math.max(1, questContentH)) end

    local available = math.max(1, (f:GetHeight() or 0) - DRAG_HANDLE_H - scenarioH - 2
                                  - (GRIP_SIZE + 2))
    local fraction  = (cfg and cfg.worldQuestsPinnedMaxFraction) or WQ_PIN_FRACTION
    local band      = headerBand()

    -- The world quest cap binds and quests take the remainder. Quests scroll, so height
    -- costs them only a drag, where giving them priority instead starved world quests to
    -- questFloor and clipped their first row - the fraction could never apply on a normal
    -- quest log. questFloor is what stops a trailing section becoming a header with no body.
    local eventsCap
    local questFloor = band + 40
    if cfg and cfg.worldQuestsHeightOverride then
        local wqWant = band + math.max(0, cfg.worldQuestsHeight or 0)
        eventsCap = math.max(0, math.min(wqWant, available - questFloor))
    else
        eventsCap = math.max(0, math.min(math.floor(available * fraction), available - questFloor))
    end

    local wqH, wqTimed = self:_RenderPinnedWorldQuests(byGroup[PINNED_GROUP], eventsCap, width, cfg)
    if wqTimed then hasTimed = true end

    -- Only snap the clip up when the cut lands inside a header's own row. Snapping when a
    -- body merely overflows would collapse the viewport to the sections above it.
    local scrollH = math.min(questContentH, available - (wqH or 0))
    if scrollH < questContentH then
        local headerGap = Sections:Height() + gap
        for i = #sectionTops, 1, -1 do
            local top = sectionTops[i]
            if top > 0 and top < scrollH then
                if scrollH - top < headerGap then scrollH = top end
                break
            end
        end
    end
    if scrollH < 1 then scrollH = 1 end

    if not locked then
        f.scroll:SetSize(math.max(1, width), scrollH)
        if f.scroll.UpdateScrollChildRect then f.scroll:UpdateScrollChildRect() end
        clampScroll(f.scroll)
    end

    RowPool:Sweep(_resetRow)
    -- After Sweep, so a retired row's button retires with it, and after the sizing above so
    -- the anchor arithmetic reads settled positions.
    ItemButtons:Commit()
    self:_EnsureTimerTicker(hasTimed)

    -- Last, so the layout is settled before a rule is allowed to paint over it. Apply is only
    -- re-entered when the count crosses zero, so this is a no-op on almost every render.
    local Visibility = ns:GetModule("Visibility")
    if Visibility then Visibility:SetQuestRows(questRows) end
end

-- Row's change gate keys on the formatted time string, so a plain Render only repaints
-- the rows whose countdown actually rolled over. No Invalidate needed here.
function Tracker:_EnsureTimerTicker(wanted)
    if wanted and not self._timerTicker then
        self._timerTicker = C_Timer.NewTicker(30, function()
            local f = self.frame
            if f and f:IsShown() then self:Render() end
        end)
    elseif not wanted and self._timerTicker then
        self._timerTicker:Cancel()
        self._timerTicker = nil
    end
end

-- Records intent and lets Visibility do the painting. Branching on IsShown instead would
-- invert the toggle whenever a rule already had the tracker hidden, and the flag is what
-- keeps a manual hide from being undone by the next visibility event.
function Tracker:Toggle()
    local f = self.frame
    if not f then return end
    f._eqotUserHidden = (not f._eqotUserHidden) or nil

    local V = ns:GetModule("Visibility")
    if V then
        V:Apply()
        if not f._eqotUserHidden and V:IsRuleHiding() then
            ns:Print(L["a visibility rule is keeping the tracker hidden - see /eqot, General."])
        end
        return
    end

    if f._eqotUserHidden then f:Hide() else f:Show(); self:Render() end
end

function Tracker:ResetPosition()
    -- Sizing and re-anchoring the tracker itself is protected once it hosts a secure
    -- button, so /eqot reset in combat lands when combat ends rather than erroring
    if secureLocked() then
        ns:GetModule("Events"):RunWhenOutOfCombat("eqot.resetPosition", resetPositionWhenSafe)
        return
    end
    local DB  = ns:GetModule("DB")
    local cfg = DB:Tracker()
    local d   = DB.defaults.profile.tracker
    cfg.anchor, cfg.relativePoint = d.anchor, d.relativePoint
    cfg.xOffset, cfg.yOffset      = d.xOffset, d.yOffset
    cfg.width, cfg.maxHeight      = d.width, d.maxHeight
    if self.frame then self.frame:SetSize(cfg.width, cfg.maxHeight) end
    self:_ApplyPosition(cfg.anchor, cfg.relativePoint, cfg.xOffset, cfg.yOffset)
    self:Render()
end

function Tracker:OnEnable()
    self:BuildFrame()

    local Registry = ns:GetModule("Registry")
    Registry:OnDirty(function() self:Refresh() end)

    local Distance = ns:GetModule("Distance")
    if Distance then Distance:OnDirty(function() self:Refresh() end) end

    -- A ding changes no entry field. GetQuestDifficultyColor is player-level relative, so it
    -- is the COMPARISON BASE that moved and no memoized field can see that - the repaint gate
    -- has to be cleared before a render will redraw a single title.
    ns:GetModule("Events"):On("PLAYER_LEVEL_UP", function()
        ns:GetModule("Row"):Invalidate()
        self:Refresh()
    end)

    self:ApplyHeaderIcons()
    self:Render()
end
