local _, ns = ...

local ZoneGroups = ns:RegisterModule("ZoneGroups", {})

-- The quest provider's sections. Only quest entries carry a quest log heading in entry.zone.
ZoneGroups.GROUPS = { quests = true, campaign = true }

-- Per group: what Note saw this pass, and the run tables Build reuses.
local state = {}

local sortAlpha = false

local function stateFor(id)
    local s = state[id]
    if not s then
        s = { total = {}, rank = {}, n = 0, byZone = {}, pool = {}, runs = {} }
        state[id] = s
    end
    return s
end

local function before(a, b)
    if sortAlpha then
        -- Blizzard's compare for translated names, so an accented letter sorts where its lists put it.
        local c = strcmputf8i and strcmputf8i(a.zone, b.zone) or 0
        if c ~= 0 then return c < 0 end
        return a.zone < b.zone
    end
    if a.current ~= b.current then return a.current end
    return a.rank < b.rank
end

function ZoneGroups:Begin()
    for _, s in pairs(state) do
        wipe(s.total)
        wipe(s.rank)
        s.n = 0
    end
end

-- Called for every entry a group is handed, shown or filtered, in the provider's own order. The
-- quest store hands its entries over in walk order, so the first sighting of a heading is its
-- place in the quest log.
function ZoneGroups:Note(groupID, entry)
    if not self.GROUPS[groupID] then return end
    local s = stateFor(groupID)
    local z = entry.zone or ""
    if not s.rank[z] then
        s.n = s.n + 1
        s.rank[z] = s.n
    end
    s.total[z] = (s.total[z] or 0) + 1
end

local function build(s, g, Registry)
    local byZone, runs = s.byZone, s.runs
    wipe(byZone)
    local n = 0
    for i = 1, g.visibleCount do
        local e = g.entries[i]
        local z = e.zone or ""
        local run = byZone[z]
        if not run then
            n = n + 1
            run = s.pool[n]
            if not run then
                run = { entries = {} }
                s.pool[n] = run
            end
            run.zone, run.count, run.current = z, 0, false
            run.rank  = s.rank[z] or math.huge
            run.total = s.total[z] or 0
            byZone[z] = run
            runs[n] = run
        end
        run.count = run.count + 1
        run.entries[run.count] = e
        -- The zone filter's own answer, so current here means what it means there.
        if not run.current then
            local p = Registry:Get(e.providerID)
            if p and p.IsCurrentZone and p:IsCurrentZone(e) == true then run.current = true end
        end
    end
    for i = #runs, n + 1, -1 do runs[i] = nil end
    table.sort(runs, before)

    -- Each run's entries keep the order the sort gave them, so the sort still applies inside a zone.
    local k = 0
    for r = 1, n do
        local run = runs[r]
        run.first = k + 1
        for j = 1, run.count do
            k = k + 1
            g.entries[k] = run.entries[j]
        end
        run.last = k
        for j = #run.entries, run.count + 1, -1 do run.entries[j] = nil end
    end
    g.zoneRuns, g.zoneCount = runs, n
end

-- After Feed's sort. Leaves zoneCount at 0 on every group it does not split.
function ZoneGroups:Build(byGroup, cfg)
    local on = cfg and cfg.zoneHeaders == true
    sortAlpha = on and cfg.zoneHeaderOrder == "alpha"
    local Registry = ns:GetModule("Registry")
    for id, g in pairs(byGroup) do
        g.zoneCount = 0
        if on and self.GROUPS[id] and g.visibleCount > 0 then
            build(stateFor(id), g, Registry)
        end
    end
end

function ZoneGroups:DebugLine()
    local DB  = ns:GetModule("DB")
    local cfg = DB and DB:Tracker()
    if not (cfg and cfg.zoneHeaders) then return "zone headers: off" end
    local char  = DB:Char()
    local folded = 0
    for _, v in pairs(char and char.zonesCollapsed or {}) do
        if v then folded = folded + 1 end
    end
    local Feed = ns:GetModule("Feed")
    local parts = {}
    for _, id in ipairs({ "campaign", "quests" }) do
        local g = Feed and Feed:Group(id)
        if g and (g.zoneCount or 0) > 0 then
            local here = {}
            for r = 1, g.zoneCount do
                if g.zoneRuns[r].current then here[#here + 1] = g.zoneRuns[r].zone end
            end
            parts[#parts + 1] = ("%s %d zone(s), current: %s"):format(id, g.zoneCount,
                #here > 0 and table.concat(here, ", ") or "none")
        end
    end
    return ("zone headers: on, order %s, %d collapsed | %s"):format(
        cfg.zoneHeaderOrder == "alpha" and "alphabetical" or "current zone first", folded,
        #parts > 0 and table.concat(parts, " | ") or "nothing grouped")
end
