local _, ns = ...

local TrackedSet = ns:RegisterModule("TrackedSet", {})

-- Classic has no per-quest watch API worth mirroring. Blizzard caps its own watch list at FIVE
-- (measured on 1.15.9 by its own error text), there is no auto-track on accept, and another quest
-- addon commonly replaces IsQuestWatched and empties that list outright - so a mirror of it is
-- neither complete nor trustworthy. This owns the set instead, per character. Listed in the
-- Classic TOCs only.

local function readSet()
    local DB = ns:GetModule("DB")
    local char = DB and DB:Char()
    return char and char.trackedQuests
end

local function writeSet()
    local DB = ns:GetModule("DB")
    local char = DB and DB:Char()
    if not char then return nil end
    char.trackedQuests = char.trackedQuests or {}
    return char.trackedQuests
end

-- `char.trackedQuests` is an ABSENCE FLAG and is deliberately NOT in DB.defaults, the same
-- reason `profile.tracker.positionInScreenUnits` is not. Give it a default and AceDB creates it
-- for every character, IsTracked stops answering nil, and every quest reads as untracked on the
-- first login after the update - which is the exact empty tracker this was written to remove.
--
-- nil, never false, until the player has made a first explicit choice. Filter tests
-- `isTracked == false`, so an absent set fails open and the whole log shows rather than none of
-- it - which is what makes this need no migration pass over an existing character.
function TrackedSet:IsTracked(questID)
    local set = readSet()
    if not (set and questID) then return nil end
    return set[questID] and true or false
end

local MAX_LOG_INDEX = 75

-- Absence means every quest is tracked, so the FIRST write that removes one has to turn that
-- into a real set holding the whole log before applying itself. This is the only place the
-- table is created, and it is never created empty.
--
-- Bounded by a ceiling and stopped at the first nil title, never by GetNumQuestLogEntries,
-- which counts only the rows visible with the player's headers expanded.
local function materialize()
    if type(GetQuestLogTitle) ~= "function" then return nil end
    local found, n = {}, 0
    for i = 1, MAX_LOG_INDEX do
        local title, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(i)
        if not title then break end
        if not isHeader and questID and questID ~= 0 then
            found[questID] = true
            n = n + 1
        end
    end
    -- A walk that found nothing is a log that has not loaded, not a player who tracks nothing.
    -- Writing it out would demote the whole character, so absence is left in place instead.
    if n == 0 then return nil end
    local set = writeSet()
    if not set then return nil end
    for questID in pairs(found) do set[questID] = true end
    return set
end

-- Never call writeSet from here. It creates the table, and the table's ABSENCE is the flag:
-- absent means every quest is tracked, whereas an EMPTY table means none of them are. So a
-- Set(id, false) that stores nothing must not create one, or turning auto-track off and
-- accepting a single quest would silently untrack the whole character for good. Tracking a
-- quest that an absent set already reports as tracked is a real no-op for the same reason.
function TrackedSet:Set(questID, on)
    if not questID then return end
    local want = on and true or nil
    local set = readSet()

    if not set then
        if want then return end
        set = materialize()
        if not set then return end
    end

    if set[questID] == want then return end
    set[questID] = want
    self:_FireDirty()
end

-- An absent set reads as tracked, so the first toggle on an untouched character must turn a quest
-- OFF rather than on, which is what `not IsTracked` gives once nil is treated as true.
function TrackedSet:Toggle(questID)
    local tracked = self:IsTracked(questID)
    if tracked == nil then tracked = true end
    self:Set(questID, not tracked)
end

-- The set outlives the quests in it otherwise, and a character who has played for a while
-- accumulates every quest they ever tracked. Driven from the provider's own rebuild, which
-- already walks the live log.
function TrackedSet:Prune(isLive)
    local set = readSet()
    if not set then return end
    for questID in pairs(set) do
        if not isLive(questID) then set[questID] = nil end
    end
end

-- Answers about a quest log ROW, resolving the index here so UI/QuestLogChecks.lua can repaint
-- Blizzard's checkmarks without calling a quest API of its own. An absent set answers true, the
-- display side of the same fail-open contract IsTracked uses.
function TrackedSet:IsTrackedAtIndex(index)
    if type(index) ~= "number" or type(GetQuestLogTitle) ~= "function" then return false end
    local title, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(index)
    if not title or isHeader or not questID or questID == 0 then return false end
    local tracked = self:IsTracked(questID)
    if tracked == nil then return true end
    return tracked
end

-- The click half of the same seam: UI/QuestLogChecks.lua knows a row was shift-clicked, this
-- knows which quest that row is.
function TrackedSet:ToggleAtIndex(index)
    if type(index) ~= "number" or type(GetQuestLogTitle) ~= "function" then return end
    local title, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(index)
    if not title or isHeader or not questID or questID == 0 then return end
    self:Toggle(questID)
end

local dirtyListeners = {}

function TrackedSet:OnDirty(fn)
    dirtyListeners[#dirtyListeners + 1] = fn
end

-- Data/ never reaches into UI/, so a set change announces itself and the quest log repaint hangs
-- off this the way the tracker hangs off Focus:OnDirty.
function TrackedSet:_FireDirty()
    for i = 1, #dirtyListeners do
        local ok, err = pcall(dirtyListeners[i])
        if not ok then geterrorhandler()(err) end
    end
end

function TrackedSet:Count()
    local set = readSet()
    if not set then return nil end
    local n = 0
    for _ in pairs(set) do n = n + 1 end
    return n
end
