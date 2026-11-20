local _, ns = ...

local RowPool = ns:RegisterModule("RowPool", {})

-- Two-level (providerID, id) indexing rather than a "provider:id" string key. Two
-- table lookups cost nothing, and building a key string per row per render would
-- allocate on a frame that repaints on every QUEST_LOG_UPDATE.
RowPool.free       = {}
RowPool.byProvider = {}

function RowPool:Begin()
    for _, byID in pairs(self.byProvider) do
        for _, row in pairs(byID) do row._used = false end
    end
end

function RowPool:Acquire(parent, providerID, id, factory)
    local byID = self.byProvider[providerID]
    if not byID then
        byID = {}
        self.byProvider[providerID] = byID
    end

    local row = byID[id]
    if not row then
        row = tremove(self.free) or factory()
        byID[id] = row
    end

    if row:GetParent() ~= parent then row:SetParent(parent) end
    row._used = true
    row:Show()
    return row
end

function RowPool:Sweep(reset)
    for _, byID in pairs(self.byProvider) do
        for id, row in pairs(byID) do
            if not row._used then
                row:Hide()
                row:ClearAllPoints()
                row:SetParent(nil)
                if reset then reset(row) end
                byID[id] = nil
                self.free[#self.free + 1] = row
            end
        end
    end
end

-- Every row the last render drew, appended to out: Sweep has already let go of the rest.
function RowPool:Drawn(out)
    for _, byID in pairs(self.byProvider) do
        for _, row in pairs(byID) do out[#out + 1] = row end
    end
    return out
end

function RowPool:Count()
    local active, free = 0, #self.free
    for _, byID in pairs(self.byProvider) do
        for _ in pairs(byID) do active = active + 1 end
    end
    return active, free
end
