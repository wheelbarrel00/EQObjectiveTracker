local _, ns = ...

-- Whether Blizzard's Gamepad UI exists on this client and is on. WoW Forever has it. Live retail,
-- Era and TBC have no InputDeviceInterfaceStyle CVar, so everything here reads false there.
local Gamepad = ns:RegisterModule("Gamepad", {})

local CVAR = "InputDeviceInterfaceStyle"

local function cvar()
    local C = _G.C_CVar
    if not (C and C.GetCVar) then return nil end
    return C.GetCVar(CVAR)
end

function Gamepad:Supported()
    return cvar() ~= nil
end

-- Blizzard's own options checkbox writes the enum's number here, so this is the choice saved
-- before the login, readable before C_InputInterfaceStyle may be.
function Gamepad:SavedOn()
    local value = cvar()
    if value == nil then return false end
    local types = _G.Enum and _G.Enum.InputDeviceInterfaceType
    if not (types and types.Gamepad) then return false end
    return tonumber(value) == types.Gamepad
end

function Gamepad:LiveOn()
    if not self:Supported() then return false end
    local IU = _G.InputUtil
    if IU and IU.IsGamepadUIEnabled then return IU.IsGamepadUIEnabled() == true end
    return self:SavedOn()
end
