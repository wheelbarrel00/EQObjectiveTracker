local _, ns = ...

local ZoneGroups = ns:RegisterModule("ZoneGroups", {})
local L          = ns.L

-- The quest provider's sections. Only quest entries carry a quest log heading in entry.zone.
ZoneGroups.GROUPS = { quests = true, campaign = true }

-- The run every dungeon quest in a section joins while the dungeon header is on. Keyed by the name
-- it is drawn with, as a heading's run is, so a heading of that very name merges into it.
local DUNGEONS = L["Dungeons"]
ZoneGroups.DUNGEONS = DUNGEONS

-- Per group: what Note saw this pass, and the run tables Build reuses.
local state = {}

local sortAlpha, currentFirst, dungeonsLast = false, false, false
-- What Begin was handed, so Note keys each quest the way Build will.
local noteZones, noteDungeons = false, false

local function stateFor(id)
    local s = state[id]
    if not s then
        s = { total = {}, rank = {}, n = 0, byZone = {}, pool = {}, runs = {} }
        state[id] = s
    end
    return s
end

local function runKey(e, zones, dungeons)
    if dungeons and e.tags and e.tags.dungeon then return DUNGEONS end
    if zones then return e.zone or "" end
    return ""
end

-- The run a quest falls in under these settings, which its header and its collapse are keyed by.
-- An empty name draws no header.
function ZoneGroups:RunKey(e, cfg)
    return runKey(e, cfg ~= nil and cfg.zoneHeaders == true, cfg ~= nil and cfg.dungeonHeader == true)
end

function ZoneGroups:Grouping(cfg)
    return cfg ~= nil and (cfg.zoneHeaders == true or cfg.dungeonHeader == true)
end

local function before(a, b)
    -- The dungeon run goes last, unless Current zone first finds one of its quests in your zone
    -- and Keep Dungeons at the bottom is off.
    if a.dungeon ~= b.dungeon then
        local d = a.dungeon and a or b
        local lead = currentFirst and not dungeonsLast and d.current
        if a.dungeon then return lead end
        return not lead
    end
    if sortAlpha then
        -- Blizzard's compare for translated names, so an accented letter sorts where its lists put it.
        local c = strcmputf8i and strcmputf8i(a.zone, b.zone) or 0
        if c ~= 0 then return c < 0 end
        return a.zone < b.zone
    end
    if a.current ~= b.current then return a.current end
    return a.rank < b.rank
end

function ZoneGroups:Begin(cfg)
    noteZones    = cfg ~= nil and cfg.zoneHeaders == true
    noteDungeons = cfg ~= nil and cfg.dungeonHeader == true
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
    local z = runKey(entry, noteZones, noteDungeons)
    if not s.rank[z] then
        s.n = s.n + 1
        s.rank[z] = s.n
    end
    s.total[z] = (s.total[z] or 0) + 1
end

local function build(s, g, Registry, zones, dungeons)
    local byZone, runs = s.byZone, s.runs
    wipe(byZone)
    local n = 0
    for i = 1, g.visibleCount do
        local e = g.entries[i]
        local z = runKey(e, zones, dungeons)
        local run = byZone[z]
        if not run then
            n = n + 1
            run = s.pool[n]
            if not run then
                run = { entries = {} }
                s.pool[n] = run
            end
            run.zone, run.count, run.current = z, 0, false
            run.dungeon = dungeons and z == DUNGEONS
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
    local zones    = cfg ~= nil and cfg.zoneHeaders == true
    local dungeons = cfg ~= nil and cfg.dungeonHeader == true
    sortAlpha    = zones and cfg.zoneHeaderOrder == "alpha"
    currentFirst = zones and not sortAlpha
    dungeonsLast = cfg ~= nil and cfg.dungeonHeaderLast == true
    local Registry = ns:GetModule("Registry")
    for id, g in pairs(byGroup) do
        g.zoneCount = 0
        if (zones or dungeons) and self.GROUPS[id] and g.visibleCount > 0 then
            build(stateFor(id), g, Registry, zones, dungeons)
        end
    end
end

function ZoneGroups:DebugLine()
    local DB  = ns:GetModule("DB")
    local cfg = DB and DB:Tracker()
    local zones    = cfg ~= nil and cfg.zoneHeaders == true
    local dungeons = cfg ~= nil and cfg.dungeonHeader == true
    if not (zones or dungeons) then return "zone headers: off" end
    local char  = DB:Char()
    local folded = 0
    for _, v in pairs(char and char.zonesCollapsed or {}) do
        if v then folded = folded + 1 end
    end
    local Feed = ns:GetModule("Feed")
    local parts = {}
    for _, id in ipairs({ "campaign", "quests" }) do
        local g = Feed and Feed:Group(id)
        local here, named = {}, 0
        for r = 1, g and g.zoneCount or 0 do
            local run = g.zoneRuns[r]
            if run.zone ~= "" then
                named = named + 1
                if run.current then here[#here + 1] = run.zone end
            end
        end
        if named > 0 then
            parts[#parts + 1] = ("%s %d zone(s), current: %s"):format(id, named,
                #here > 0 and table.concat(here, ", ") or "none")
        end
    end
    local head = "zone headers: off"
    if zones then
        head = ("zone headers: on, order %s"):format(
            cfg.zoneHeaderOrder == "alpha" and "alphabetical" or "current zone first")
    end
    if dungeons then
        head = head .. (cfg.dungeonHeaderLast == true and ", dungeon header on, kept at the bottom" or ", dungeon header on")
    end
    return ("%s, %d collapsed | %s"):format(head, folded,
        #parts > 0 and table.concat(parts, " | ") or "nothing grouped")
end
