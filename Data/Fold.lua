local _, ns = ...

local Fold     = ns:RegisterModule("Fold", {})
local COMPLETE = ns:GetModule("Entry").STATE.COMPLETE

-- char.folded[providerID][entryID]: true when the player folded the row, false when they opened a
-- finished quest auto minimize would fold, absent when they made no choice.
local function folds(create)
    local DB   = ns:GetModule("DB")
    local char = DB and DB:Char()
    if type(char) ~= "table" then return nil end
    if create and type(char.folded) ~= "table" then char.folded = {} end
    return type(char.folded) == "table" and char.folded or nil
end

local function stored(entry)
    local t = folds(false)
    local byProvider = t and t[entry.providerID]
    if type(byProvider) ~= "table" then return nil end
    return byProvider[entry.id]
end

local function store(entry, v)
    local t = folds(v ~= nil)
    if not t then return end
    local byProvider = t[entry.providerID]
    if v == nil then
        if type(byProvider) == "table" then
            byProvider[entry.id] = nil
            if next(byProvider) == nil then t[entry.providerID] = nil end
        end
        return
    end
    if type(byProvider) ~= "table" then
        byProvider = {}
        t[entry.providerID] = byProvider
    end
    byProvider[entry.id] = v
end

local function questSpace(providerID)
    local p = ns:GetModule("Registry"):Get(providerID)
    return p ~= nil and p.idSpace == "quest"
end

-- A quest Blizzard hands in on a click is left open, so its click to complete line still shows.
function Fold:AutoFolds(entry, cfg)
    return cfg ~= nil and cfg.autoMinimizeFinished == true and entry.state == COMPLETE
       and not entry.clickToComplete and questSpace(entry.providerID)
end

function Fold:IsFolded(entry, cfg)
    local v = stored(entry)
    if v == true then return true end
    if v == false then return false end
    return self:AutoFolds(entry, cfg)
end

function Fold:Foldable(entry)
    return type(entry.lines) == "table" and #entry.lines > 0
end

local function open(entry, cfg)
    if Fold:AutoFolds(entry, cfg) then store(entry, false) else store(entry, nil) end
end

function Fold:Toggle(entry, cfg)
    if self:IsFolded(entry, cfg) then open(entry, cfg) else store(entry, true) end
end

function Fold:Set(entry, folded, cfg)
    if folded then store(entry, true) else open(entry, cfg) end
end

function Fold:SetAll(entries, folded, cfg)
    for i = 1, #entries do
        if self:Foldable(entries[i]) then self:Set(entries[i], folded, cfg) end
    end
end

local function areaQuest(questID)
    local q = C_QuestLog
    if not q then return false end
    return (q.IsWorldQuest and q.IsWorldQuest(questID)) or (q.IsQuestTask and q.IsQuestTask(questID)) or false
end

-- Walking into or out of a world quest or bonus objective area fires accept and remove on retail,
-- and that must not open a fold. Handing one in still clears it.
function Fold:Forget(questID, kind)
    questID = tonumber(questID)
    local t = folds(false)
    if not (questID and t) then return end
    if kind ~= "turnin" and areaQuest(questID) then return end
    for providerID, byProvider in pairs(t) do
        if type(byProvider) == "table" and questSpace(providerID) then
            byProvider[questID] = nil
            if next(byProvider) == nil then t[providerID] = nil end
        end
    end
end

function Fold:OnEnable()
    local Events = ns:GetModule("Events")
    -- Classic fires (questLogIndex, questID) where retail fires (questID), as AutoTrack reads it.
    Events:On("QUEST_ACCEPTED",  function(_, a, b) Fold:Forget(b or a, "accept") end)
    Events:On("QUEST_REMOVED",   function(_, id) Fold:Forget(id, "remove") end)
    Events:On("QUEST_TURNED_IN", function(_, id) Fold:Forget(id, "turnin") end)
end

function Fold:DebugLine()
    local DB  = ns:GetModule("DB")
    local cfg = DB and DB:Tracker()
    local folded, opened = 0, 0
    for _, byProvider in pairs(folds(false) or {}) do
        if type(byProvider) == "table" then
            for _, v in pairs(byProvider) do
                if v == true then folded = folded + 1 elseif v == false then opened = opened + 1 end
            end
        end
    end
    return ("fold: %d folded, %d opened | auto minimize %s, signs %s"):format(folded, opened,
        (cfg and cfg.autoMinimizeFinished == true) and "on" or "off",
        (cfg and cfg.showFoldButtons == true) and "on" or "off")
end
