local _, ns = ...

local Events = ns:RegisterModule("Events", {})

local frame     = CreateFrame("Frame")
local listeners = {}
local unknown   = {}

-- Answers whether the listener was installed, so a caller can fall back to older events on a
-- client that does not know a newer one.
function Events:On(event, fn)
    if unknown[event] then return false end
    local list = listeners[event]
    if not list then
        -- RegisterEvent raises on an event the client does not know, and non-provider
        -- modules are listed on every flavor. Refusing the listener makes the feature
        -- inert there instead of aborting whatever was enabling it. Recorded rather than
        -- swallowed, or a whole subsystem goes quiet with nothing on screen to say why.
        if not pcall(frame.RegisterEvent, frame, event) then
            unknown[event] = true
            return false
        end
        list = {}
        listeners[event] = list
    end
    list[#list + 1] = fn
    return true
end

function Events:Off(event, fn)
    local list = listeners[event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == fn then tremove(list, i) end
    end
    if #list == 0 then
        listeners[event] = nil
        frame:UnregisterEvent(event)
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = listeners[event]
    if not list then return end
    for i = 1, #list do
        local fn = list[i]
        if fn then
            local ok, err = pcall(fn, event, ...)
            if not ok then geterrorhandler()(err) end
        end
    end
end)

local _deferred   = {}
local _deferOrder = {}
local _flushKeys  = {}
local _flushArmed = false

-- Drained in the order the calls arrived rather than in pairs() order. A deferred reset and a
-- deferred stopDrag both write the tracker's position, and which one won was left to chance.
local function flushDeferred()
    local n = #_deferOrder
    for i = 1, n do
        _flushKeys[i]  = _deferOrder[i]
        _deferOrder[i] = nil
    end
    for i = 1, n do
        local key = _flushKeys[i]
        local fn  = _deferred[key]
        _deferred[key] = nil
        _flushKeys[i]  = nil
        if fn then
            local ok, err = pcall(fn)
            if not ok then geterrorhandler()(err) end
        end
    end
end

function Events:InCombat()
    return InCombatLockdown() and true or false
end

function Events:RunWhenOutOfCombat(key, fn)
    if not InCombatLockdown() then
        fn()
        return true
    end
    -- Re-deferring a key keeps its first arrival slot, which is what makes this FIFO.
    if _deferred[key] == nil then _deferOrder[#_deferOrder + 1] = key end
    _deferred[key] = fn
    if not _flushArmed then
        _flushArmed = true
        self:On("PLAYER_REGEN_ENABLED", flushDeferred)
    end
    return false
end

local _debounce     = {}
local _debTickFns   = {}
local _debOrder     = {}
local _debRecovered = 0
local _debWorstLate = 0

-- A key is disarmed only by its own timer callback, so before this a C_Timer.After that never
-- fired left the key armed for the rest of the session and every later request on it was dropped
-- in silence - no work, no error. Read off a user's client: the quest sound scan had not run for
-- 39 minutes while the events driving it kept firing. The stamp is what lets a later request
-- notice its timer is overdue and schedule a fresh one.
local LOST_SLACK = 3

local function debounceTick(key)
    local d = _debounce[key]
    if not d then return end
    -- A recovery leaves the lost timer outstanding, so two ticks can be in flight on one key.
    -- Only the one whose own arming is due may take the work. A tick arriving early still
    -- disarms the key on its way past, so the next request arms a second timer of its own and
    -- the pair then runs the key twice per window for the rest of the session - measured at a
    -- sustained 2x, which is the render rate v1.17.0 was released to cut.
    if GetTime() < d.at + d.delay then return end
    local fn = d.fn
    d.armed = false
    d.fn    = nil
    if fn then
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(err) end
    end
end

local function getDebTickFn(key)
    local fn = _debTickFns[key]
    if not fn then
        fn = function() debounceTick(key) end
        _debTickFns[key] = fn
    end
    return fn
end

function Events:Debounce(key, delay, fn)
    local d = _debounce[key]
    if d and d.armed then
        -- Collapsing a burst is the whole point of this, so only an OVERDUE key counts as lost.
        local late = GetTime() - d.at - d.delay
        if late <= LOST_SLACK then
            d.fn = fn
            return false
        end
        _debRecovered = _debRecovered + 1
        if late > _debWorstLate then _debWorstLate = late end
    end
    if not d then
        d = {}
        _debounce[key] = d
        _debOrder[#_debOrder + 1] = key
    end
    d.armed = true
    d.fn    = fn
    d.at    = GetTime()
    -- Stamped per arming rather than read back from the caller, so a key ever debounced at two
    -- different delays still measures its lateness against the deadline it was actually given.
    d.delay = delay
    C_Timer.After(delay, getDebTickFn(key))
    return true
end

-- The debounce half lives on this line because an armed key is invisible everywhere else: a
-- request landing on one returns false, schedules nothing, and neither the work nor an error ever
-- appears. The AGE beside it separates a burst being collapsed from a timer that never came.
function Events:DebugLine()
    local names = {}
    for event in pairs(unknown) do names[#names + 1] = event end
    local first = "events: every registration accepted by this client"
    if #names > 0 then
        table.sort(names)
        first = ("events: %d unknown on this client - %s"):format(#names, table.concat(names, ", "))
    end

    local now, armed = GetTime(), {}
    for i = 1, #_debOrder do
        local key = _debOrder[i]
        local d = _debounce[key]
        if d and d.armed then
            armed[#armed + 1] = ("%s %.0fs"):format(key, now - d.at)
        end
    end
    return first .. ("\n      debounce: %d keys | armed now: %s | recovered %d, worst %.0fs late")
        :format(#_debOrder, #armed > 0 and table.concat(armed, ", ") or "none",
                _debRecovered, _debWorstLate)
end

ns.Events = Events
