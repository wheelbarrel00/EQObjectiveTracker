local _, ns = ...

local Distance = ns:RegisterModule("Distance", {})

local TICK     = 2
local MOVE_EPS = 0.0025
local MAX_AGE  = 5

local scratch = {}
local dirtyListeners = {}

function Distance:OnDirty(fn)
    dirtyListeners[#dirtyListeners + 1] = fn
end

local function fireDirty()
    for i = 1, #dirtyListeners do
        local ok, err = pcall(dirtyListeners[i])
        if not ok then geterrorhandler()(err) end
    end
end

local function gameCall()
    return C_QuestLog and C_QuestLog.GetDistanceSqToQuest
end

-- Era and TBC have no distance call, so another addon that knows where quests are can answer through the API.
local function sourceAPI()
    local API = ns:GetModule("API")
    if API and API.distanceSources and #API.distanceSources > 0 then return API end
    return nil
end

function Distance:IsAvailable()
    return (gameCall() or sourceAPI()) and true or false
end

local function samplePlayerPos()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not (mapID and C_Map.GetPlayerMapPosition) then return mapID, nil, nil end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return mapID, nil, nil end
    local x, y = pos:GetXY()
    return mapID, x, y
end

function Distance:Moved(mapID, x, y)
    if mapID ~= self._mapID then return true end
    if not (x and y) then return false end
    if not (self._x and self._y) then return true end
    return math.abs(x - self._x) > MOVE_EPS or math.abs(y - self._y) > MOVE_EPS
end

local function harvest()
    wipe(scratch)
    local n = 0
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        -- isHidden is deliberately NOT filtered, unlike the Quests provider's own walk: a
        -- world quest you are standing inside sits in the log hidden, and the WorldQuests
        -- provider still draws it, so it needs a real distance rather than the INF fallback.
        if info and not info.isHeader and info.questID then
            local distSq, onContinent = C_QuestLog.GetDistanceSqToQuest(info.questID)
            -- distSq == distSq rejects NaN, which the API returns for a quest with no
            -- resolvable position. Complete quests are kept deliberately: they resolve to
            -- their turn-in POI, and dropping them strands ready-to-hand-in quests at the
            -- bottom of the list. EQ's own changelog records that as a fix.
            if distSq and onContinent and distSq == distSq then
                scratch[info.questID] = distSq
                n = n + 1
            end
        end
    end
    return n
end

-- [questID] = yards, or false for asked and not placed, so an unknown quest is not asked on every render
local asked = {}

-- Only the quests Feed is about to sort, each once until the next full re-read.
local function askSources(API, questIDs)
    local n = 0
    if not questIDs then return n end
    for id in pairs(questIDs) do
        if asked[id] == nil then
            local d = API:DistanceFor(id)
            asked[id] = d or false
            if d then
                scratch[id] = d
                n = n + 1
            end
        end
    end
    return n
end

-- Called from Feed:Build, which is the Data-side entry point that runs once per render and
-- already knows the sort mode. EQ's old tracker drove this from Tracker:Render, which EQOT cannot copy -
-- GetDistanceSqToQuest is a quest API and UI/ may not call one.
function Distance:Sync(sortMode, questIDs)
    local Sort = ns:GetModule("Sort")
    -- No OnEnable to skip, so safe mode is honored here, as ItemButtons and DragDrop do it.
    -- Otherwise a bisection session keeps harvesting and ticking with nothing to sort.
    local wanted = (sortMode == "distance") and self:IsAvailable() and not ns:SafeMode()

    if not wanted then
        if Sort then Sort:SetDistances(nil) end
        self:_StopTicker()
        return
    end

    local API = not gameCall() and sourceAPI()
    local mapID, px, py = samplePlayerPos()
    local stale = (GetTime() - (self._stamp or 0)) >= MAX_AGE
    if not (self._harvested and not stale and not self:Moved(mapID, px, py)) then
        if API then
            wipe(scratch)
            wipe(asked)
            self._count = 0
        else
            self._count = harvest()
        end
        self._harvested = true
        self._stamp     = GetTime()
        self._mapID, self._x, self._y = mapID, px, py
    end
    if API then self._count = self._count + askSources(API, questIDs) end

    if Sort then Sort:SetDistances(scratch) end
    self:_StartTicker()
end

local function questAccepted()
    -- Where the game measures, a quest accepted standing still has no distance until a harvest, so it would sort last.
    Distance._harvested = nil
end

-- The API's flush, a frame after a source is added or removed or says its answers moved.
-- Asked for while no source is left too, so the list drops the old order.
function Distance:SourceChanged()
    if gameCall() then return end
    self._harvested = nil
    local DB  = ns:GetModule("DB")
    local cfg = DB and DB:Tracker()
    if cfg and cfg.sortMode == "distance" then fireDirty() end
end

function Distance:_StartTicker()
    if self._ticker then return end
    if not self._listening then
        self._listening = true
        ns:GetModule("Events"):On("QUEST_ACCEPTED", questAccepted)
    end
    self._ticker = C_Timer.NewTicker(TICK, function()
        local DB  = ns:GetModule("DB")
        local cfg = DB and DB:Tracker()
        if not cfg or cfg.sortMode ~= "distance" then
            Distance:_StopTicker()
            return
        end
        -- Re-sorting the list under a player who is mid-fight is churn they cannot act on,
        -- and the tracker may not even be on screen. Both were EQ's old tracker's gates.
        local Tracker = ns:GetModule("Tracker")
        local f = Tracker and Tracker.frame
        if not (f and f:IsShown() and f:GetAlpha() > 0) then return end
        if InCombatLockdown and InCombatLockdown() then return end

        local mapID, px, py = samplePlayerPos()
        if Distance:Moved(mapID, px, py) then fireDirty() end
    end)
end

function Distance:_StopTicker()
    if not self._ticker then return end
    self._ticker:Cancel()
    self._ticker = nil
end

local function origin()
    if gameCall() then return "game" end
    local API = sourceAPI()
    if not API then return "nothing" end
    local s = ("%d source(s)"):format(#API.distanceSources)
    if API.distanceSourceError then s = s .. ", last raise: " .. API.distanceSourceError end
    return s
end

function Distance:DebugLine()
    local DB  = ns:GetModule("DB")
    local cfg = DB and DB:Tracker()
    return ("distance: api %s, sort mode %s, %d harvested, ticker %s, age %.1fs, from %s")
        :format(tostring(self:IsAvailable()), tostring(cfg and cfg.sortMode or "?"),
                self._count or 0, self._ticker and "on" or "off",
                GetTime() - (self._stamp or GetTime()), origin())
end
