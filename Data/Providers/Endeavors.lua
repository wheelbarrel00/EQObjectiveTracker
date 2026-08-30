local _, ns = ...

local Entry    = ns:GetModule("Entry")
local Registry = ns:GetModule("Registry")

local STATE, ICON = Entry.STATE, Entry.ICON

local Endeavors = {
    id       = "endeavors",
    groups   = { "endeavors" },
    -- Perks activity IDs are their own space, so no idSpace and no claim contention
    -- with the quest providers.
    priority = 40,
    tags     = {},
}

local store = Entry.NewStore({
    groupID   = "endeavors",
    icon      = { kind = ICON.NONE },
    isTracked = true,
})

local trackedIDs = {}

local function collectTracked()
    wipe(trackedIDs)
    if not ns.Has.PerksActivities then return trackedIDs end
    local data = C_PerksActivities.GetTrackedPerksActivities()
    local list = data and data.trackedIDs
    for i = 1, (list and #list or 0) do
        trackedIDs[#trackedIDs + 1] = list[i]
    end
    return trackedIDs
end

-- Requirements are emitted as ordinary objective lines with a completion flag, never as
-- pre-colored strings. EQ bakes a checkmark texture and a hardcoded green escape into
-- this text, which is why its endeavors ignore the complete-color setting.
local function fillLines(e, info)
    Entry.BeginLines(e)
    local reqs = info.requirementsList
    local done, total = 0, 0
    for i = 1, (reqs and #reqs or 0) do
        local rq = reqs[i]
        local ln = Entry.PushLine(e)
        ln.text      = ns.Util.CleanRequirement(rq.requirementText)
        ln.completed = rq.completed and true or false
        total = total + 1
        if ln.completed then done = done + 1 end
    end
    Entry.EndLines(e)
    return done, total
end

function Endeavors:IsAvailable()
    return ns.Has.PerksActivities and ns.Has.PerksActivityInfo
end

function Endeavors:GetEntries()
    local ids = collectTracked()

    store:Begin()
    for i = 1, #ids do
        local id   = ids[i]
        local info = C_PerksActivities.GetPerksActivityInfo(id)
        if info then
            local e = store:Acquire(id)
            e.title = info.activityName or ("Activity " .. tostring(id))
            local done, total = fillLines(e, info)
            local complete = info.completed
            if complete == nil then complete = (total > 0 and done == total) end
            e.state = complete and STATE.COMPLETE or STATE.ACTIVE
        end
    end
    return store:Finish()
end

-- Without this, `endeavors 0 -> shown 0` could not say whether the tracked list came back empty
-- or whether every id in it failed to resolve, and those want opposite fixes. It also prints the
-- SHAPE of what the API returned and every function the client exposes on C_PerksActivities,
-- because an empty tracked list beside a row Blizzard is drawing most likely means that row is
-- coming from a source this provider never asks.
function Endeavors:DebugLine()
    if not ns.Has.PerksActivities then
        return "endeavors: GetTrackedPerksActivities absent on this client"
    end

    -- pcall'd for the same reason the pairs walk below is: this function has to REPORT rather
    -- than raise, and it was the one call here that could take the whole status line down.
    local okData, data = pcall(C_PerksActivities.GetTrackedPerksActivities)
    if not okData then data = nil end
    local shape = {}
    if type(data) == "table" then
        for k, v in pairs(data) do
            shape[#shape + 1] = ("%s=%s%s"):format(tostring(k), type(v),
                (type(v) == "table") and ("[" .. #v .. "]") or "")
        end
        table.sort(shape)
    end

    local list, seen = (type(data) == "table") and data.trackedIDs or nil, {}
    for i = 1, (list and #list or 0) do
        local id = list[i]
        local okInfo, info
        if ns.Has.PerksActivityInfo then
            okInfo, info = pcall(C_PerksActivities.GetPerksActivityInfo, id)
        end
        if not okInfo then info = nil end
        seen[i] = ("%s:%s"):format(tostring(id),
            (type(info) == "table") and tostring(info.activityName or "?"):sub(1, 20)
                or "UNREADABLE")
    end

    -- pcall'd rather than assumed: a C namespace that refuses pairs would otherwise take the
    -- whole status report down, and the fallback still answers the two names that matter.
    local api = {}
    local okWalk = pcall(function()
        for k, v in pairs(C_PerksActivities) do
            if type(v) == "function" then api[#api + 1] = k end
        end
    end)
    if not okWalk then
        api = { "not enumerable" }
    end
    table.sort(api)

    -- An EMPTY tracked list is the CORRECT answer when the player has tracked nothing, so it
    -- cannot on its own explain a row the stock tracker is drawing. GetPerksActivitiesInfo is
    -- the plural call this provider has never asked, and the field names on one of its entries
    -- are what decide whether it can be filtered down to what Blizzard shows.
    local function fieldsOf(t, cap)
        local out = {}
        if type(t) ~= "table" then return out end
        local ok = pcall(function()
            for k, v in pairs(t) do
                out[#out + 1] = ("%s=%s%s"):format(tostring(k), type(v),
                    (type(v) == "table") and ("[" .. #v .. "]") or "")
            end
        end)
        if not ok then return { "not enumerable" } end
        table.sort(out)
        -- Truncating in SILENCE is how a capture hides the one field the answer is in, and this
        -- instrument did exactly that on its first live reading: the cap was 10, the table had
        -- 10 or more, and there was no way to tell a complete list from a cut one. Say so.
        local dropped = #out - cap
        if dropped > 0 then
            while #out > cap do table.remove(out) end
            out[#out + 1] = ("(+%d MORE, cap %d)"):format(dropped, cap)
        end
        return out
    end

    local plural = "GetPerksActivitiesInfo absent"
    if type(C_PerksActivities.GetPerksActivitiesInfo) == "function" then
        local okAll, all = pcall(C_PerksActivities.GetPerksActivitiesInfo)
        if not okAll then
            plural = "GetPerksActivitiesInfo raised: " .. tostring(all):sub(1, 60)
        else
            -- The array may be the return itself or one field down, so both are described
            -- rather than guessed at.
            local arr = (type(all) == "table" and #all > 0) and all
                or (type(all) == "table" and type(all.activities) == "table" and all.activities)
                or nil
            -- The month and the seconds left are read as VALUES rather than left as field
            -- names, because an empty activities array means two different things: a Traveler's
            -- Log between months, and one that never populates on this expansion. Nothing else
            -- on this line separates them, and that ambiguity cost a round trip once.
            local when = ""
            if type(all) == "table" and (all.displayMonthName or all.secondsRemaining) then
                when = (", month %s, %s seconds left"):format(
                    tostring(all.displayMonthName), tostring(all.secondsRemaining))
            end
            plural = ("GetPerksActivitiesInfo -> %s {%s}, array %s entries%s%s"):format(
                type(all), table.concat(fieldsOf(all, 8), " "),
                arr and tostring(#arr) or "no", when,
                (arr and arr[1]) and (", entry 1 {" .. table.concat(fieldsOf(arr[1], 14), " ") .. "}") or "")
        end
    end

    return ("endeavors: api tracked=%s info=%s | GetTracked -> %s {%s} | %d tracked: %s"
        .. "\n      %s"
        .. "\n      C_PerksActivities: %s"):format(
        tostring(ns.Has.PerksActivities), tostring(ns.Has.PerksActivityInfo),
        type(data), table.concat(shape, " "),
        list and #list or 0,
        (#seen > 0) and table.concat(seen, " ") or "none",
        plural,
        table.concat(api, " "))
end

function Endeavors:Enable(notifyDirty)
    local Events = ns:GetModule("Events")
    Events:On("PERKS_ACTIVITY_COMPLETED",              notifyDirty)
    Events:On("PERKS_ACTIVITIES_TRACKED_UPDATED",      notifyDirty)
    Events:On("PERKS_ACTIVITIES_TRACKED_LIST_CHANGED", notifyDirty)
    Events:On("PLAYER_ENTERING_WORLD",                 notifyDirty)
end

Registry:Register(Endeavors)
