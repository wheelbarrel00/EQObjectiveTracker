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

function Events:DebugLine()
    local names = {}
    for event in pairs(unknown) do names[#names + 1] = event end
    if #names == 0 then return "events: every registration accepted by this client" end
    table.sort(names)
    return ("events: %d unknown on this client - %s"):format(#names, table.concat(names, ", "))
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

local _debounce   = {}
local _debTickFns = {}

local function debounceTick(key)
    local d = _debounce[key]
    if not d then return end
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
        d.fn = fn
        return false
    end
    if not d then d = {}; _debounce[key] = d end
    d.armed = true
    d.fn    = fn
    C_Timer.After(delay, getDebTickFn(key))
    return true
end

ns.Events = Events
