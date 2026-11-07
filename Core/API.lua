local _, ns = ...

-- The public surface another addon reaches through _G.EQObjectiveTracker. EQOT declares no
-- dependency on anything, so every list here is empty in the standalone case.
--
-- Registrations carry an entry ID and a provider ID, never the entry table itself - entries are
-- rebuilt on every quest event and handing one to a foreign addon would leak a table that is
-- invalid by the time it is read.
local API = ns:RegisterModule("API", {})

API.headerIcons     = {}
API.menuItems       = {}
API.focusListeners  = {}
API.layoutListeners = {}

local function slotFor(list, id)
    for i = 1, #list do
        if list[i].id == id then return i end
    end
    return #list + 1
end

-- order runs RIGHT TO LEFT from the cogwheel, which is always rightmost and EQOT's own: the
-- lowest order sits immediately left of it. Explicit rather than registration order, so an
-- icon that is removed and re-added comes back in the same place instead of jumping to the end.
function API:AddHeaderIcon(spec)
    if type(spec) ~= "table" or type(spec.id) ~= "string" then return false end
    if type(spec.onClick) ~= "function" or type(spec.texture) ~= "string" then return false end
    self.headerIcons[slotFor(self.headerIcons, spec.id)] = {
        id      = spec.id,
        texture = spec.texture,
        -- A string only, since the header icon would call a function on every hover, unprotected.
        tooltip = type(spec.tooltip) == "string" and spec.tooltip or nil,
        onClick = spec.onClick,
        dbKey   = spec.dbKey,
        order   = tonumber(spec.order) or 999,
    }
    table.sort(self.headerIcons, function(a, b)
        if a.order == b.order then return a.id < b.id end
        return a.order < b.order
    end)
    local Tracker = ns:GetModule("Tracker")
    if Tracker and Tracker.RebuildHeaderIcons then Tracker:RebuildHeaderIcons() end
    return true
end

function API:RemoveHeaderIcon(id)
    for i = #self.headerIcons, 1, -1 do
        if self.headerIcons[i].id == id then table.remove(self.headerIcons, i) end
    end
    local Tracker = ns:GetModule("Tracker")
    if Tracker and Tracker.RebuildHeaderIcons then Tracker:RebuildHeaderIcons() end
end

function API:HeaderIcons()
    return self.headerIcons
end

-- order interleaves with the provider's own items, which are spaced by ten so a caller can
-- land between any two of them.
-- label is required, not optional: MenuItemsFor drops an item without one, so accepting it
-- here would hand a caller true for a registration that can never render.
function API:AddMenuItem(spec)
    if type(spec) ~= "table" or type(spec.id) ~= "string" then return false end
    if type(spec.onClick) ~= "function" or type(spec.label) ~= "string" then return false end
    self.menuItems[slotFor(self.menuItems, spec.id)] = {
        id         = spec.id,
        providerID = spec.providerID,
        label      = spec.label,
        order      = tonumber(spec.order) or 999,
        shouldShow = spec.shouldShow,
        onClick    = spec.onClick,
    }
    return true
end

function API:RemoveMenuItem(id)
    for i = #self.menuItems, 1, -1 do
        if self.menuItems[i].id == id then table.remove(self.menuItems, i) end
    end
end

function API:MenuItemsFor(providerID, entryID, out)
    out = out or {}
    for i = 1, #self.menuItems do
        local it = self.menuItems[i]
        if not it.providerID or it.providerID == providerID then
            local show = true
            if it.shouldShow then
                local ok, res = pcall(it.shouldShow, providerID, entryID)
                show = ok and res and true or false
            end
            if show and it.label then
                out[#out + 1] = {
                    id = it.id, kind = "button", label = it.label,
                    order = it.order, external = it,
                }
            end
        end
    end
    return out
end

-- Announced when the tracker's focused row changes: EQOT owns the focus, a listener owns
-- whatever it points at. Only Data/Focus.lua fires this, and only on Classic and WoW Forever,
-- so a retail listener is registered and never called.
-- Registering here on every flavor is deliberate - a call that exists on one flavor and is nil
-- on another is the trap, not the courtesy.
function API:AddFocusListener(spec)
    if type(spec) ~= "table" or type(spec.id) ~= "string" then return false end
    if type(spec.onFocus) ~= "function" then return false end
    self.focusListeners[slotFor(self.focusListeners, spec.id)] = {
        id = spec.id, onFocus = spec.onFocus,
    }
    return true
end

function API:RemoveFocusListener(id)
    for i = #self.focusListeners, 1, -1 do
        if self.focusListeners[i].id == id then table.remove(self.focusListeners, i) end
    end
end

-- entryID is nil when focus was CLEARED, and providerID still names the provider that lost it.
-- pcall'd because this runs inside the click or event that set the focus, so a foreign addon
-- erroring here would otherwise take that handler down with it.
--
-- Walked backwards because a one-shot listener unregistering itself from its own callback is an
-- ordinary thing to write, and table.remove would shift an unvisited entry into a slot the
-- forward loop had already passed - silently skipping it.
function API:NotifyFocus(providerID, entryID)
    local list = self.focusListeners
    for i = #list, 1, -1 do
        local it = list[i]
        if it then pcall(it.onFocus, providerID, entryID) end
    end
end

function API:GetFocus()
    local Focus = ns:GetModule("Focus")
    if not Focus then return nil, nil end
    return Focus:Get()
end

-- For an addon that keeps its own frames clear of the quest list (Shortest Path Forever's journey
-- column). Left, right, top and bottom in UIParent units, or nil while nothing is drawn.
function API:GetListBounds()
    local Tracker = ns:GetModule("Tracker")
    if not Tracker then return nil end
    return Tracker:ListBounds()
end

local layoutQueued = false
local lastL, lastR, lastT, lastB

function API:AddLayoutListener(spec)
    if type(spec) ~= "table" or type(spec.id) ~= "string" then return false end
    if type(spec.onLayout) ~= "function" then return false end
    self.layoutListeners[slotFor(self.layoutListeners, spec.id)] = {
        id = spec.id, onLayout = spec.onLayout,
    }
    -- Nothing flushes while no one listens, so the last answer can be stale: the next flush calls everyone.
    lastL = false
    return true
end

function API:RemoveLayoutListener(id)
    for i = #self.layoutListeners, 1, -1 do
        if self.layoutListeners[i].id == id then table.remove(self.layoutListeners, i) end
    end
end

-- One flush a frame later however many calls came first, and silent unless the answer moved or a
-- listener was added, since a render runs on every quest event. Walked backwards for the reason
-- NotifyFocus is.
local function flushLayout()
    layoutQueued = false
    local list = API.layoutListeners
    local l, r, t, b = API:GetListBounds()
    if l == lastL and r == lastR and t == lastT and b == lastB then return end
    lastL, lastR, lastT, lastB = l, r, t, b
    for i = #list, 1, -1 do
        local it = list[i]
        if it then pcall(it.onLayout) end
    end
end

-- Shortest Path Forever runs no timer of its own, so whatever moves, sizes or hides the list calls this.
function API:NotifyLayout()
    if layoutQueued or #self.layoutListeners == 0 then return end
    layoutQueued = true
    C_Timer.After(0, flushLayout)
end

-- Two answers on purpose: the mode this session runs in, fixed at login, and the saved choice,
-- which only a reload applies. A caller reading Blizzard's watch list needs the first.
function API:UsesBlizzardTracker()
    return ns:UsesBlizzardTracker()
end

function API:GetBlizzardTrackerSetting()
    local gen = ns:GetModule("DB"):General()
    return (gen and gen.useBlizzardTracker == true) and true or false
end

function API:SetBlizzardTrackerSetting(on)
    local gen = ns:GetModule("DB"):General()
    if not gen then return false end
    gen.useBlizzardTracker = on and true or false
    return true
end

function API:DebugLine()
    local providerID, entryID = self:GetFocus()
    local Focus = ns:GetModule("Focus")
    local follows = Focus and Focus:FollowsSuperTrack()
    local l, r, t, b = self:GetListBounds()
    local list = l and ("%.0f,%.0f,%.0f,%.0f"):format(l, r, t, b) or "none"
    return ("api: %d header icon(s), %d menu item(s), %d focus listener(s), %d layout listener(s)"
            .. " | focus %s:%s%s | list %s")
        :format(#self.headerIcons, #self.menuItems, #self.focusListeners, #self.layoutListeners,
                tostring(providerID), tostring(entryID), follows and ", follows super-track" or "", list)
end
