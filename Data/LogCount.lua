local _, ns = ...

local LogCount = ns:RegisterModule("LogCount", {})

-- The first answer of Era and TBC's count call counts only the rows a collapsed heading leaves
-- visible, so the walk goes by index until a title comes back nil, to Data/QuestSound.lua's ceiling.
local MAX_LOG_INDEX = 75

-- Set by OnEnable, so /eqot disable LogCount stops the count as well as its events.
local enabled = false
local dirty = true
local count, surface = nil, "no walk yet"

local function walk()
    -- The game's own count. Leaving out every quest GetInfo marks hidden read 26 on a retail log the
    -- game counted as 32 (2026-11-20).
    if ns.Has.QuestLog then
        surface = "C_QuestLog"
        local _, n = C_QuestLog.GetNumQuestLogEntries()
        return n
    end
    if type(GetQuestLogTitle) ~= "function" then
        surface = "none, no quest log api"
        return nil
    end
    surface = "GetQuestLogTitle"
    local n = 0
    for i = 1, MAX_LOG_INDEX do
        local title, _, _, isHeader = GetQuestLogTitle(i)
        if not title then break end
        if not isHeader then n = n + 1 end
    end
    return n
end

function LogCount:Get()
    if not enabled then return nil end
    local cap = C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept()
    if not cap then return nil end
    if dirty then
        count = walk()
        dirty = false
    end
    if not count then return nil end
    return count, cap
end

function LogCount:DebugLine()
    local n, cap = self:Get()
    if not n then return ("log count: none (%s)"):format(surface) end
    return ("log count: %d/%d via %s"):format(n, cap, surface)
end

function LogCount:OnEnable()
    enabled = true
    local Events = ns:GetModule("Events")
    local function mark() dirty = true end
    Events:On("QUEST_LOG_UPDATE", mark)
    Events:On("QUEST_ACCEPTED", mark)
    Events:On("QUEST_REMOVED", mark)
end
