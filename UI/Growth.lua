local _, ns = ...

local Growth = ns:RegisterModule("Growth", {})

local MODES = { down = true, up = true }

function Growth:Mode(cfg)
    local m = cfg and cfg.trackerGrowth
    if MODES[m] then return m end
    return "fixed"
end

function Growth:GripCorner(cfg)
    return self:Mode(cfg) == "up" and "TOPRIGHT" or "BOTTOMRIGHT"
end

local function scaleOf(f)
    local k = f and f.GetEffectiveScale and f:GetEffectiveScale()
    local u = UIParent:GetEffectiveScale()
    if not k or k <= 0 or not u or u <= 0 then return 1 end
    return k / u
end

-- The grip's own minimum (MIN_H in UI/Tracker.lua), for a saved edge a UI scale change left off the
-- screen: a box there would be 1 px, and the screen clamp pulls a 100 px one back into view. A box
-- parked near the edge on purpose keeps its room, so its anchored edge stays put.
local MIN_ROOM = 100

-- Read off the saved anchor rather than the frame, so a box that is fitted, held or full answers
-- the same room. An anchor whose vertical half does not match the mode is not converted yet.
function Growth:Room(cfg, f)
    local cap = cfg.maxHeight
    local mode = self:Mode(cfg)
    local anchor = cfg.anchor or ""
    local edge
    if mode == "down" and anchor:find("^TOP") then
        edge = UIParent:GetHeight() + (cfg.yOffset or 0)
    elseif mode == "up" and anchor:find("^BOTTOM") then
        edge = UIParent:GetHeight() - (cfg.yOffset or 0)
    else
        return cap
    end
    local space = edge / scaleOf(f)
    if space <= 0 then space = MIN_ROOM end
    return math.max(1, math.min(cap, space))
end

-- A fitted box keeps the edge it grows from, so the full box is rebuilt from that edge.
function Growth:FullRect(f, laidOut, maxH)
    local k = scaleOf(f)
    local l, r, t, b = f:GetLeft() * k, f:GetRight() * k, f:GetTop() * k, f:GetBottom() * k
    if laidOut == "down" then
        b = t - maxH * k
    elseif laidOut == "up" then
        t = b + maxH * k
    end
    return l, r, t, b
end

local function fx(point)
    if point:find("LEFT") then return 0 elseif point:find("RIGHT") then return 1 end
    return 0.5
end

local function fy(point)
    if point:find("TOP") then return 1 elseif point:find("BOTTOM") then return 0 end
    return 0.5
end

-- The saved anchor always describes the full box, so a change of choice converts from it rather than
-- from a frame the client may not have laid out. onScreen places it where the client's clamp draws it.
function Growth:SavedRect(cfg, f, onScreen)
    local k = scaleOf(f)
    local w, h = cfg.width * k, cfg.maxHeight * k
    local point = cfg.anchor or "CENTER"
    local rel = cfg.relativePoint or point
    local px = fx(rel) * UIParent:GetWidth() + (cfg.xOffset or 0)
    local py = fy(rel) * UIParent:GetHeight() + (cfg.yOffset or 0)
    local left = px - fx(point) * w
    local top = py + (1 - fy(point)) * h
    if onScreen then
        local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
        left = math.max(0, math.min(left, sw - w))
        top = math.min(sh, math.max(top, h))
    end
    return left, left + w, top, top - h
end

local HOLD_TIME = 0.5

local function trackerOf()
    return ns:GetModule("Tracker")
end

local function inMoveMode()
    local T = trackerOf()
    return T ~= nil and T:InMoveMode() and true or false
end

-- Grow upward keeps its bottom still, so a height change under the mouse would slide the row just
-- clicked out from under it. The box is held until the mouse has been away for HOLD_TIME.
function Growth:LayoutHeight(cfg, f)
    self._held = false
    local live = f:GetHeight() or 0
    local mode = self:Mode(cfg)
    -- A move or a resize holds the box, and so does its save waiting for a fight's end. The save
    -- asks for the fit.
    if mode == "fixed" or f._dragging or f._savePending then return live end
    if inMoveMode() then return self:Room(cfg, f) end
    if mode == "up" and live > 1 and f:IsMouseOver() then
        self._held = true
        return live
    end
    return self:Room(cfg, f)
end

local watch

local function stopWatch()
    if watch then watch:SetScript("OnUpdate", nil) end
    Growth._waiting, Growth._leftAt = nil, nil
end

local function onWatch()
    local T = trackerOf()
    local f = T and T.frame
    local cfg = ns:GetModule("DB"):Tracker()
    if not (f and f:IsShown()) or f._eqotHidden or Growth:Mode(cfg) ~= "up" then
        stopWatch()
        return
    end
    if f:IsMouseOver() then
        Growth._leftAt = nil
        return
    end
    local now = GetTime()
    Growth._leftAt = Growth._leftAt or now
    if now - Growth._leftAt < HOLD_TIME then return end
    stopWatch()
    T:Refresh()
end

local function arm()
    if Growth._waiting then return end
    watch = watch or CreateFrame("Frame")
    Growth._waiting, Growth._leftAt = true, nil
    watch:SetScript("OnUpdate", onWatch)
end

function Growth:Holding()
    return self._waiting == true
end

function Growth:Target(cfg, f, locked, layoutH, slack)
    if self:Mode(cfg) == "fixed" or f._dragging or f._savePending or locked then return nil end
    local want
    if inMoveMode() then
        want = layoutH
    elseif self._held then
        arm()
        return nil
    else
        want = math.max(1, layoutH - math.max(0, slack))
    end
    if math.abs(want - (f:GetHeight() or 0)) <= 0.5 then return nil end
    return want
end

function Growth:Line()
    local T = trackerOf()
    local f = T and T.frame
    if not f then return "no frame" end
    local cfg = ns:GetModule("DB"):Tracker()
    local mode = self:Mode(cfg)
    local full = mode == "fixed" or inMoveMode()
    return ("%s live %.0f room %.0f full %s held %s"):format(mode, f:GetHeight() or 0, self:Room(cfg, f),
        full and "yes" or "no", self:Holding() and "yes" or "no")
end

local function round(v) return math.floor(v + 0.5) end

function Growth:AnchorFor(mode, anchor, left, right, top, bottom)
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    anchor = anchor or ""
    local side, x = "", (left + right) / 2 - w / 2
    if anchor:find("LEFT") then
        side, x = "LEFT", left
    elseif anchor:find("RIGHT") then
        side, x = "RIGHT", right - w
    end
    local vert, y
    if mode == "up" then
        vert, y = "BOTTOM", math.max(0, math.min(h, bottom))
    else
        vert, y = "TOP", math.max(0, math.min(h, top)) - h
    end
    local point = vert .. side
    return point, point, round(x), round(y)
end
