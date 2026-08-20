local _, ns = ...

local DragDrop = ns:RegisterModule("DragDrop", {})

-- Only the Quests provider is draggable, matching EQ calling Blocks:AcquireFor from
-- _RenderQuestGroup alone. It feeds both the campaign and quests groups. Tracker reads
-- this to decide which rows go into DragRows, so the rule lives in one place.
DragDrop.PROVIDER = "quests"

local GHOST_THROTTLE = 1 / 30

local _scope = {}
local _ids   = {}
local _accum = 0

local GHOST_H      = 24
local GHOST_MIN_W  = 120
local GHOST_BORDER = 1

local function ensureGhost()
    if DragDrop.ghost then return DragDrop.ghost end

    local g = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate")
    g:SetSize(220, GHOST_H)
    g:SetFrameStrata("TOOLTIP")
    g:Hide()

    -- A backdrop, not two textures. An opaque full-size rim with an inset fill over it
    -- makes the fill composite against the RIM rather than against the row underneath, so
    -- the ghost stays opaque however low the fill's alpha is - which is how this started
    -- out and it hid the drop target exactly as EQ's old red box did.
    if g.SetBackdrop then
        g:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = GHOST_BORDER,
        })
        g:SetBackdropColor(0.09, 0.10, 0.12, 0.80)
        g:SetBackdropBorderColor(0.92, 0.72, 0.02, 1)
    end

    g.text = g:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    g.text:SetPoint("LEFT", 6, 0)
    g.text:SetPoint("RIGHT", -6, 0)
    g.text:SetJustifyH("LEFT")
    g.text:SetWordWrap(false)
    g.text:SetTextColor(1, 1, 1, 1)

    DragDrop.ghost = g
    return g
end

local function ensureIndicator()
    if DragDrop.indicator then return DragDrop.indicator end

    local i = CreateFrame("Frame", nil, UIParent)
    i:SetHeight(2)
    i:SetFrameStrata("TOOLTIP")
    i:Hide()

    local t = i:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints()
    t:SetColorTexture(0.92, 0.72, 0.02, 1)

    DragDrop.indicator = i
    return i
end

-- A quest cannot move between Campaign and Quests, so only the dragged row's own section
-- takes part. Including the other one would draw a drop line promising a move that the
-- commit cannot make.
local function collectScope(groupID)
    local Tracker = ns:GetModule("Tracker")
    local rows = Tracker and Tracker.DragRows and Tracker:DragRows()

    wipe(_scope)
    if not rows then return 0 end

    local n = 0
    for i = 1, #rows do
        local row = rows[i]
        local e   = row._entry
        if e and e.groupID == groupID then
            n = n + 1
            _scope[n] = row
        end
    end
    return n
end

local function ghostOnUpdate(_, elapsed)
    _accum = _accum + elapsed
    if _accum < GHOST_THROTTLE then return end
    _accum = 0
    DragDrop:UpdateVisuals()
end

function DragDrop:IsManualMode()
    local DB = ns:GetModule("DB")
    local t  = DB and DB:Tracker()
    return (t and t.sortMode == "manual") and true or false
end

function DragDrop:OnDragStart(row)
    -- No OnEnable to skip, so safe mode is honored here, as ItemButtons does it.
    if ns:SafeMode() then return false end

    local Tracker = ns:GetModule("Tracker")
    if Tracker and Tracker.IsClickThrough and Tracker:IsClickThrough() then return false end
    if not self:IsManualMode() then return false end

    local e = row._entry
    if not (e and e.providerID == self.PROVIDER and e.id) then return false end

    self.dragID    = e.id
    self.dragGroup = e.groupID
    self.dragRow   = row
    self.dropIndex = nil

    local g = ensureGhost()
    -- Sized to the row it was lifted from, so it reads as that row rather than a loose
    -- label. GetWidth is in the ROW's scaled space and the ghost hangs off UIParent, so
    -- without converting through both effective scales it is off by 1/scale at any tracker
    -- scale but 1 - the same trap the drop-index scan below documents for the cursor.
    local rowW = (row:GetWidth() or 0) * row:GetEffectiveScale() / g:GetEffectiveScale()
    g:SetSize(math.max(GHOST_MIN_W, rowW), GHOST_H)
    g.text:SetText(e.title or ("Quest #" .. tostring(e.id)))
    g:Show()
    ensureIndicator():Show()

    _accum = 0
    g:SetScript("OnUpdate", ghostOnUpdate)
    return true
end

function DragDrop:UpdateVisuals()
    if not self.dragID then return end
    local g = self.ghost
    if not g then return end

    -- A visibility rule can take the tracker away mid-drag, and a row hidden underneath the
    -- cursor never delivers OnDragStop - without this the ghost follows the cursor for the
    -- rest of the session. EQ has no visibility rules, so it never needed the check.
    local T = ns:GetModule("Tracker")
    local f = T and T.frame
    if not (f and f:IsShown()) or (T.IsClickThrough and T:IsClickThrough()) then
        self:Cancel()
        return
    end

    local cx, cy = GetCursorPosition()
    local s = g:GetEffectiveScale()
    g:ClearAllPoints()
    g:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx / s + 12, cy / s - 24)

    local ind = self.indicator
    local n = collectScope(self.dragGroup)
    if n == 0 then
        self.dropIndex = nil
        if ind then ind:Hide() end
        return
    end

    -- Divide the cursor by the ROWS' effective scale, not the ghost's - GetTop pairs with
    -- a frame's own scale, and the mismatch offsets the drop line by the tracker scale.
    local rowScale = _scope[1]:GetEffectiveScale() or s
    local cursorY  = cy / rowScale

    local target = n + 1
    for i = 1, n do
        local row = _scope[i]
        local top = row:GetTop()
        if top and cursorY > top - (row:GetHeight() * 0.5) then
            target = i
            break
        end
    end
    self.dropIndex = target

    if not ind then return end
    ind:ClearAllPoints()
    ind:Show()
    if target <= n then
        local t = _scope[target]
        ind:SetPoint("BOTTOMLEFT",  t, "TOPLEFT",  0, 1)
        ind:SetPoint("BOTTOMRIGHT", t, "TOPRIGHT", 0, 1)
    else
        local last = _scope[n]
        ind:SetPoint("TOPLEFT",  last, "BOTTOMLEFT",  0, -1)
        ind:SetPoint("TOPRIGHT", last, "BOTTOMRIGHT", 0, -1)
    end
end

function DragDrop:Cancel()
    if self.ghost then
        self.ghost:Hide()
        self.ghost:SetScript("OnUpdate", nil)
    end
    if self.indicator then self.indicator:Hide() end
    -- Next frame rather than now: the row's own OnMouseUp still has to read this to swallow
    -- the click that ended the drag. A cancel from UpdateVisuals delivers neither, and the
    -- flag left set makes that row ignore its next click and show no tooltip.
    local row = self.dragRow
    if row then C_Timer.After(0, function() row._wasDragging = nil end) end
    self.dragID, self.dragGroup, self.dropIndex, self.dragRow = nil, nil, nil, nil
end

function DragDrop:OnDragStop()
    local dragID, dragGroup, dropIndex = self.dragID, self.dragGroup, self.dropIndex
    self:Cancel()
    if not (dragID and dropIndex) then return end

    local n = collectScope(dragGroup)
    wipe(_ids)
    for i = 1, n do
        local e = _scope[i]._entry
        _ids[i] = e and e.id
    end

    local ManualOrder = ns:GetModule("ManualOrder")
    if ManualOrder then ManualOrder:Commit(_ids, dragID, dropIndex) end

    local Tracker = ns:GetModule("Tracker")
    if Tracker then Tracker:Refresh() end
end

-- _wasDragging is set only once a drag is accepted. Setting it on every OnDragStart, as EQ
-- does, would swallow the next click on the rows EQ never has - achievements, professions
-- and the rest share this one row frame.
local function onDragStart(row)
    if DragDrop:OnDragStart(row) then row._wasDragging = true end
end

local function onDragStop()
    DragDrop:OnDragStop()
end

function DragDrop:Wire(row)
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", onDragStart)
    row:SetScript("OnDragStop", onDragStop)
end
