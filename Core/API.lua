local _, ns = ...

-- The public surface another addon reaches through _G.EQObjectiveTracker. EQOT declares no
-- dependency on anything, so both lists here are empty in the standalone case.
--
-- Registrations carry an entry ID and a provider ID, never the entry table itself - entries are
-- rebuilt on every quest event and handing one to a foreign addon would leak a table that is
-- invalid by the time it is read.
local API = ns:RegisterModule("API", {})

API.headerIcons    = {}
API.menuItems      = {}
API.focusListeners = {}

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
        tooltip = spec.tooltip,
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
    return ("api: %d header icon(s), %d menu item(s), %d focus listener(s) | focus %s:%s%s")
        :format(#self.headerIcons, #self.menuItems, #self.focusListeners,
                tostring(providerID), tostring(entryID), follows and ", follows super-track" or "")
end
