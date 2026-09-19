local _, ns = ...

local Entry    = ns:GetModule("Entry")
local Registry = ns:GetModule("Registry")

local STATE, ICON = Entry.STATE, Entry.ICON

-- The Midnight neighborhood initiative, which Blizzard draws under its own ENDEAVORS header
-- alongside the Traveler's Log. It feeds the SAME display group as Data/Providers/Endeavors.lua
-- rather than growing a section of its own, because that is what the stock tracker does and
-- Feed's byGroup supports it: it fetches or creates by group id and appends, knowing nothing
-- about which provider an entry came from. `endeavors` is the tree's first group with two LIVE
-- providers though - quests is declared by both quest providers, which never co-load.
local Initiative = {
    id       = "initiative",
    groups   = { "endeavors" },
    -- Task IDs are their own space, so no idSpace and no claim contention with the quest
    -- providers or with the Traveler's Log beside it.
    priority = 45,
    tags     = {},
}

local store = Entry.NewStore({
    groupID   = "endeavors",
    icon      = { kind = ICON.NONE },
    isTracked = true,
})

-- Counts GetEntries' graph reads, the only thing that tells a working cache from a rebuild: the
-- entries are identical either way.
local dirty, lastLive, reads = true, nil, 0
local sent, skipped = 0, 0

local function readInfo()
    if type(C_NeighborhoodInitiative) ~= "table" then return nil end
    local fn = C_NeighborhoodInitiative.GetNeighborhoodInitiativeInfo
    if type(fn) ~= "function" then return nil end
    return fn()
end

-- A gate the client lacks reads closed, because an ungated request disconnected WoW Forever.
local function isLive(C)
    if type(C.IsInitiativeEnabled) ~= "function"
       or type(C.PlayerHasInitiativeAccess) ~= "function" then
        return false
    end
    return (C.IsInitiativeEnabled() and C.PlayerHasInitiativeAccess()) and true or false
end

local function fillLines(e, task)
    Entry.BeginLines(e)
    local reqs = task.requirementsList
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

-- A CAPABILITY probe, deliberately, not a content one. Whether the player is in a neighborhood
-- at all can change mid-session, and IsAvailable is answered once, so gating on it here would
-- leave the section dead for the rest of the session. The content gate lives in GetEntries.
function Initiative:IsAvailable()
    return type(C_NeighborhoodInitiative) == "table"
       and type(C_NeighborhoodInitiative.GetNeighborhoodInitiativeInfo) == "function"
end

function Initiative:GetEntries()
    local live = isLive(C_NeighborhoodInitiative)

    -- GetEntries runs inside Tracker:Render, which repaints several times a second, and
    -- GetNeighborhoodInitiativeInfo builds the WHOLE initiative graph fresh on every call -
    -- the root, the task array, and per task a criteriaList, a requirementsList and every
    -- requirement under it, none of it cached. It is read on a dirty flag now, the way
    -- Data/Providers/Quests.lua does it.
    --
    -- The two gates isLive reads are NOT cached with it. Both are cheap boolean reads and both
    -- can change mid-session, which is the reason the content gate lives here rather than in
    -- IsAvailable, so caching them would reintroduce the bug that placement exists to avoid.
    if not dirty and live == lastLive then return store:Out() end

    store:Begin()

    -- Whether this pass had real data to cache. The fetch is ASYNCHRONOUS - that is the whole
    -- reason RequestNeighborhoodInitiativeInfo is issued from the event path - so the first
    -- pass after login routinely reads nothing. Clearing the flag against that answer caches
    -- the empty section until an event happens by, where the uncached version picked the data
    -- up on the very next repaint with no event needed.
    local settled = true

    if live then
        local data  = readInfo()
        local tasks = data and data.tasks
        settled = (data ~= nil) and (data.isLoaded ~= false)
        reads = reads + 1
        for i = 1, (tasks and #tasks or 0) do
            local t = tasks[i]
            -- The PER-TASK flag, never GetTrackedInitiativeTasks. Measured 2026-08-30: that
            -- call answered 0 while three tasks carried this flag and the stock tracker drew
            -- exactly those three. inProgress was the other candidate and is wrong - six
            -- carried it, and only one of the six was on screen.
            if t and t.tracked and t.ID then
                local e = store:Acquire(t.ID)
                e.title = t.taskName or ("Task " .. tostring(t.ID))
                local done, total = fillLines(e, t)
                local complete = t.completed
                if complete == nil then complete = (total > 0 and done == total) end
                e.state = complete and STATE.COMPLETE or STATE.ACTIVE
            end
        end
    end

    local out = store:Finish()
    -- Cleared only after a pass that ran to the end AND, where it read the graph at all, got a
    -- settled answer out of it. A raise inside the walk above leaves the flag set, so the next
    -- repaint retries rather than handing back a half-built answer for the rest of the session.
    -- A pass that was never live read nothing and still clears: what carries that case is the
    -- live == lastLive test at the top, which is why that test is not redundant - store:Begin has already wiped the
    -- bookkeeping by then, and only Finish trims the array the cached branch returns.
    if settled then dirty, lastLive = false, live end
    return out
end

function Initiative:Enable(notifyDirty)
    local Events = ns:GetModule("Events")
    -- The flag, then the repaint. A bare notifyDirty is not enough for a provider whose
    -- GetEntries caches: it asks for a repaint and sets nothing, so the same entries are handed
    -- straight back and the new answer never reaches a row.
    local function invalidate()
        dirty = true
        notifyDirty()
    end
    Events:On("NEIGHBORHOOD_INITIATIVE_UPDATED", invalidate)
    -- The info arrives asynchronously and RequestNeighborhoodInitiativeInfo is what asks for it,
    -- so the fetch is issued from the event path only. GetEntries runs inside Tracker:Render and
    -- must not make a call that answers later.
    -- WoW Forever reads both gates false and this request disconnected it. Retail read both true
    -- right after login (2026-09-17). Blizzard's tracker also asks on a zone change.
    local function request()
        local C = C_NeighborhoodInitiative
        if type(C) == "table" and type(C.RequestNeighborhoodInitiativeInfo) == "function" and isLive(C) then
            C.RequestNeighborhoodInitiativeInfo()
            sent = sent + 1
        else
            skipped = skipped + 1
        end
    end
    Events:On("PLAYER_ENTERING_WORLD", function()
        request()
        invalidate()
    end)
    Events:On("ZONE_CHANGED_NEW_AREA", request)
end

-- `initiative 0 -> shown 0` cannot say whether the player is outside a neighborhood, whether the
-- info has not streamed in, or whether nothing is tracked, and those want three different
-- answers. The flag tallies are here because the filter was picked from them: inProgress looked
-- right and drew four rows Blizzard does not.
function Initiative:DebugLine()
    local C = C_NeighborhoodInitiative
    if type(C) ~= "table" then return "initiative: C_NeighborhoodInitiative absent" end

    local function ask(name)
        local fn = C[name]
        if type(fn) ~= "function" then return "absent" end
        local ok, res = pcall(fn)
        if not ok then return "raised" end
        return tostring(res)
    end

    -- Ungated, this read disconnected /eqot status on WoW Forever. A raising gate shows in ask(),
    -- a raising read as loaded=raised.
    local okLive, live = pcall(isLive, C)
    local data, loaded = nil, "not read"
    if okLive and live then
        local okRead
        okRead, data = pcall(readInfo)
        if not okRead then data = nil end
        loaded = okRead and tostring(type(data) == "table" and data.isLoaded) or "raised"
    end
    local tasks = (type(data) == "table") and data.tasks or nil
    local done, prog, trk, withID, names = 0, 0, 0, 0, {}
    for i = 1, (type(tasks) == "table" and #tasks or 0) do
        local t = tasks[i]
        if type(t) == "table" then
            if t.completed  then done = done + 1 end
            if t.inProgress then prog = prog + 1 end
            if t.tracked then
                trk = trk + 1
                -- Counted separately because GetEntries emits on `tracked AND ID`. Without this,
                -- a renamed id field reads "3 tracked" beside "shown 0" and nothing on the line
                -- separates a wrong filter from a wrong field name.
                if t.ID then withID = withID + 1 end
                if #names < 8 then names[#names + 1] = tostring(t.taskName) end
            end
        end
    end

    -- Only GetEntries moves `graph reads`: the read and walk above are DebugLine's own.
    return ("initiative: enabled=%s access=%s loaded=%s | %s tasks, %d tracked (%d with an id), %d inProgress, %d completed%s"
            .. "\n      %d graph reads this session, %s | %d requests sent, %d skipped")
        :format(ask("IsInitiativeEnabled"), ask("PlayerHasInitiativeAccess"), loaded,
                (type(tasks) == "table") and tostring(#tasks) or "no",
                trk, withID, prog, done,
                (#names > 0) and (" -> " .. table.concat(names, ", ")) or "",
                reads, dirty and "a rebuild is pending" or "cached", sent, skipped)
end

Registry:Register(Initiative)
