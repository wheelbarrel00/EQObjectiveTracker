local _, ns = ...

-- The questions a Gamepad UI player is asked. The tracker is picked at login (Core/DB.lua), so a
-- switch of the Gamepad UI mid-session needs a reload. Every question goes through EQOT's own dialog:
-- players report freezes after an addon's StaticPopup under the Gamepad UI.
local GamepadPrompt = ns:RegisterModule("GamepadPrompt", {})
local L = ns.L

local MAX_ASKS = 3
-- What's New's 3 second timer starts at login, before the loading screen this one waits on.
local LOGIN_DELAY = 4

local loginSeen, askedThisSession, reloadAsked, retrying = false, false, false, false
-- A switch waiting out a fight or an open dialog, kept apart from the check that runs it: a later
-- check queued under the same key would otherwise replace it.
local pendingSwitch = false

local function runPending()
    local switched = pendingSwitch
    pendingSwitch = false
    GamepadPrompt:Check(switched)
end

local function reload()
    ReloadUI()
    -- Expected to fire only if the client refused the reload.
    C_Timer.After(1, function() ns:Print(L["The interface did not reload. Type /reload to finish."]) end)
end

local function askReload(Dialog)
    reloadAsked = true
    Dialog:Show({
        title    = "EQ Objective Tracker",
        text     = L["The Gamepad UI was switched, so the quest tracker should switch too. Reload the interface now?"],
        button1  = L["Reload"],
        button2  = L["Not now"],
        onAccept = reload,
    })
end

-- Only a click on Yes or No answers it. A pad player may close it some other way without a mouse, and
-- that must not end the only offer they get.
local function askOnce(Dialog, gen, g)
    askedThisSession = true
    g.gamepadPromptAsks = (g.gamepadPromptAsks or 0) + 1
    Dialog:Show({
        title     = "EQ Objective Tracker",
        text      = L["You are using the Gamepad UI. The game's own quest tracker works with a controller, and this one does not yet."]
            .. "\n\n" .. L["Use the game's quest tracker while the Gamepad UI is on? The interface reloads. You can change this later on the General tab."],
        button1   = L["Yes"],
        button2   = L["No"],
        onAccept  = function()
            g.gamepadPromptAnswered = "yes"
            gen.blizzardTrackerOnGamepad = true
            reload()
        end,
        onDecline = function() g.gamepadPromptAnswered = "no" end,
    })
end

-- switched: the Gamepad UI switched this session, the only time a reload can help, since the login
-- reads the saved setting again. mode: the event's new mode, read in place of the live answer, which
-- the event may arrive ahead of. A deferred check reads the live answer by then.
function GamepadPrompt:Check(switched, mode)
    local Events = ns:GetModule("Events")
    if Events:InCombat() then
        pendingSwitch = pendingSwitch or switched == true
        Events:RunWhenOutOfCombat("eqot.gamepadPrompt", runPending)
        return
    end
    local Gamepad = ns:GetModule("Gamepad")
    if not (Gamepad and Gamepad:Supported()) then return end
    local DB = ns:GetModule("DB")
    local Dialog = ns:GetModule("Dialog")
    local gen, g = DB and DB:General(), ns.db and ns.db.global
    if not (gen and g and Dialog) or gen.useBlizzardTracker == true then return end
    -- One dialog frame serves every EQOT question, and a new one cancels the one on screen.
    if Dialog:IsShown() then
        pendingSwitch = pendingSwitch or switched == true
        if not retrying then
            retrying = true
            C_Timer.After(LOGIN_DELAY, function()
                retrying = false
                runPending()
            end)
        end
        return
    end

    local types = _G.Enum and _G.Enum.InputDeviceInterfaceType
    local live
    if type(mode) == "number" and types and types.Gamepad then
        live = mode == types.Gamepad
    else
        live = Gamepad:LiveOn()
    end
    if gen.blizzardTrackerOnGamepad == true then
        if switched and not reloadAsked and live ~= (ns._blizzardTrackerWhy == "gamepad") then askReload(Dialog) end
        return
    end
    if live and not askedThisSession and g.gamepadPromptAnswered == nil and (g.gamepadPromptAsks or 0) < MAX_ASKS then
        askOnce(Dialog, gen, g)
    end
end

function GamepadPrompt:OnEnable()
    local Gamepad = ns:GetModule("Gamepad")
    if not (Gamepad and Gamepad:Supported()) then return end
    local Events = ns:GetModule("Events")
    Events:On("PLAYER_ENTERING_WORLD", function()
        if loginSeen then return end
        loginSeen = true
        C_Timer.After(LOGIN_DELAY, function() GamepadPrompt:Check() end)
    end)
    Events:On("INPUT_DEVICE_INTERFACE_TRANSITION", function(_, newMode) GamepadPrompt:Check(true, newMode) end)
end

function GamepadPrompt:DebugLine()
    local g = ns.db and ns.db.global or {}
    return ("gamepad prompt: answered %s, asks %d/%d, reload asked %s"):format(tostring(g.gamepadPromptAnswered or "-"),
        g.gamepadPromptAsks or 0, MAX_ASKS, reloadAsked and "yes" or "no")
end
