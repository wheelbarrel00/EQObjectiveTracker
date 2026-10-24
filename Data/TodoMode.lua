local _, ns = ...

local TodoMode = ns:RegisterModule("TodoMode", {})
local STATE    = ns:GetModule("Entry").STATE

-- Screen order, and index i is count i in every group's todo array.
TodoMode.VIEWS = { "unfinished", "ready", "here", "all" }

local KNOWN = {}
for i, v in ipairs(TodoMode.VIEWS) do KNOWN[v] = i end

local SHOW_KEYS = { "todoShowUnfinished", "todoShowReady", "todoShowHere", "todoShowAll" }

function TodoMode:IsOn(cfg)
    return (cfg and cfg.todoMode == true) and true or false
end

-- Per character with no default, so a character that never picked reads the unfinished view.
function TodoMode:View()
    local DB   = ns:GetModule("DB")
    local char = DB and DB:Char()
    local v    = char and char.todoView
    if v ~= nil and KNOWN[v] then return v end
    return "unfinished"
end

function TodoMode:SetView(view)
    if view == nil or not KNOWN[view] then return end
    local DB   = ns:GetModule("DB")
    local char = DB and DB:Char()
    if char then char.todoView = view end
end

function TodoMode:IsHereView(view)
    return view ~= "all"
end

-- The row's own state, so a quest never sits in one count while drawn as the other.
function TodoMode:IsFinished(entry)
    return entry.state == STATE.COMPLETE
end

function TodoMode:Fits(view, here, finished)
    if view == "all" then return true end
    if not here then return false end
    if view == "here" then return true end
    if view == "ready" then return finished and true or false end
    return not finished
end

function TodoMode:Shown(cfg, index)
    local key = SHOW_KEYS[index]
    if not key then return false end
    return not (cfg and cfg[key] == false)
end

-- Asks the filter's own questions, so a count is the rows its click shows, but for two deliberate
-- extras: a pinned quest shows in every view and counts by its zone and state alone, and a quest
-- drawn as a popup box counts where it belongs.
function TodoMode:Count(group, entry, cfg, provider)
    local Filter = ns:GetModule("Filter")
    local f = cfg and cfg.filters
    if not Filter:IsPinned(entry) then
        if not Filter:PassesWatched(entry, cfg) then return end
        if provider.filterCategories and not Filter:PassesCategory(entry, f) then return end
    end
    local here     = Filter:IsHere(entry, f, provider)
    local finished = self:IsFinished(entry)
    local counts   = group.todo
    for i = 1, #self.VIEWS do
        if self:Fits(self.VIEWS[i], here, finished) then counts[i] = counts[i] + 1 end
    end
end

-- Without this a player who finished everything here would lose the counts that switch the view.
function TodoMode:Holds(group, cfg)
    if not (self:IsOn(cfg) and group and group.todoOn) then return false end
    local counts = group.todo
    for i = 1, #self.VIEWS do
        if counts[i] > 0 and self:Shown(cfg, i) then return true end
    end
    return false
end

function TodoMode:DebugLine()
    local DB  = ns:GetModule("DB")
    local cfg = DB and DB:Tracker()
    if not self:IsOn(cfg) then return "todo mode: off" end
    local Feed, Filter = ns:GetModule("Feed"), ns:GetModule("Filter")
    local byGroup = (Feed and Feed.byGroup) or {}
    local ids = {}
    for id, g in pairs(byGroup) do
        if g.todoOn then ids[#ids + 1] = id end
    end
    table.sort(ids)
    local parts = { ("todo mode: on, view %s"):format(self:View()) }
    for _, id in ipairs(ids) do
        local c = byGroup[id].todo
        parts[#parts + 1] = ("%s %d/%d/%d/%d"):format(id, c[1], c[2], c[3], c[4])
    end
    parts[#parts + 1] = ("hidden by finished %d"):format((Filter and Filter.todoHidden) or 0)
    return table.concat(parts, " | ")
end
