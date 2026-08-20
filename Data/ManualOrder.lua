local _, ns = ...

local ManualOrder = ns:RegisterModule("ManualOrder", {})

-- Anything the user has never dragged sorts after everything they have.
ManualOrder.UNRANKED = 99999

local function map()
    local DB = ns:GetModule("DB")
    local t = DB and DB:Tracker()
    if not t then return nil end
    if type(t.manualOrder) ~= "table" then t.manualOrder = {} end
    return t.manualOrder
end

local function rankedIDs(m)
    local out = {}
    for id, rank in pairs(m) do
        if type(id) == "number" and type(rank) == "number" then
            out[#out + 1] = id
        end
    end
    table.sort(out, function(a, b) return m[a] < m[b] end)
    return out
end

function ManualOrder:Get()
    return map()
end

-- The quest log is this addon's stand-in for EQ's quest Cache: it decides whether an off-screen
-- rank is worth carrying forward, and it is the only thing keeping the saved map from growing
-- for every quest ever dragged. Only ever asked from Commit, which a drag reaches, so the log
-- is loaded by then.
function ManualOrder:IsLive(questID)
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        return C_QuestLog.GetLogIndexForQuestID(questID) ~= nil
    end
    -- The Classic global answers 0 rather than nil for a quest that is not in the log. Without
    -- this branch it answered true for everything and nothing was pruned there at all.
    if GetQuestLogIndexByID then
        local i = GetQuestLogIndexByID(questID)
        return (i and i ~= 0) and true or false
    end
    return true
end

-- Densifies to 1..N and drops junk keys. Commit always writes a dense map, so the only
-- source of a sparse one is a hand-edited or imported saved variable.
function ManualOrder:Reconcile()
    local m = map()
    if not m then return 0 end

    local ids = rankedIDs(m)
    wipe(m)
    for i = 1, #ids do m[ids[i]] = i end
    return #ids
end

-- visibleIDs is the dragged row's own section, in the order it is drawn. Ids outside it
-- keep their relative rank, so dragging inside Quests never disturbs Campaign and
-- filtering the tracker never discards the order of what is hidden.
function ManualOrder:Commit(visibleIDs, draggedID, dropIndex)
    local m = map()
    if not (m and visibleIDs and draggedID and dropIndex) then return end

    local seq, dragAt = {}, nil
    for i = 1, #visibleIDs do
        local id = visibleIDs[i]
        if id == draggedID then
            dragAt = i
        else
            seq[#seq + 1] = id
        end
    end

    -- dropIndex counts the dragged row, since it is measured against the rows on screen,
    -- and seq does not. Without this every drop below its own slot lands a row too low.
    if dragAt and dropIndex > dragAt then dropIndex = dropIndex - 1 end

    local insertAt = math.min(math.max(dropIndex, 1), #seq + 1)
    table.insert(seq, insertAt, draggedID)

    local onScreen = {}
    for i = 1, #seq do onScreen[seq[i]] = true end

    local previous = rankedIDs(m)
    local merged, si = {}, 1
    for i = 1, #previous do
        local id = previous[i]
        if onScreen[id] then
            if si <= #seq then
                merged[#merged + 1] = seq[si]
                si = si + 1
            end
        elseif self:IsLive(id) then
            merged[#merged + 1] = id
        end
    end
    while si <= #seq do
        merged[#merged + 1] = seq[si]
        si = si + 1
    end

    wipe(m)
    for i = 1, #merged do m[merged[i]] = i end
end

function ManualOrder:DebugLine()
    local m = map()
    local ranked, live = 0, 0
    if m then
        for id in pairs(m) do
            ranked = ranked + 1
            if self:IsLive(id) then live = live + 1 end
        end
    end
    local DB = ns:GetModule("DB")
    local t  = DB and DB:Tracker()
    return ("manual order: %d ranked, %d still in log, sort mode %s")
        :format(ranked, live, tostring(t and t.sortMode or "?"))
end
