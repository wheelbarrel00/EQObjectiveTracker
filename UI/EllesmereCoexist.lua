local _, ns = ...

local Ellesmere = ns:RegisterModule("EllesmereCoexist", {})

-- EllesmereUI's own call for hiding its quest tracker, the one its Mythic+ timer uses. Made only
-- while its own tracker window exists (WoW Forever), since without that window the same call works
-- on Blizzard's tracker, showing it at alpha 0. Its suppression lives in memory, so asking once a
-- session is enough.
local KEY = "EQObjectiveTracker"

local function trackerWindow()
    return _G.EUI_CustomQuestTracker
end

local function applyWhenSafe() Ellesmere:Apply() end

-- A missing or renamed call fails inside the pcall, so it is simply asked again next time.
function Ellesmere:Apply()
    if self._asked or not trackerWindow() then return end
    -- Deferred past a fight, as hiding another addon's tracker has been since 2.10.0.
    if InCombatLockdown() then
        ns:GetModule("Events"):RunWhenOutOfCombat("eqot.ellesmere", applyWhenSafe)
        return
    end
    self._asked = pcall(_G._EQT_SetSuppressed, KEY, true)
end

function Ellesmere:OnEnable()
    -- That window is built at EllesmereUI's own PLAYER_LOGIN, which may run after this one.
    ns:GetModule("Events"):On("PLAYER_ENTERING_WORLD", applyWhenSafe)
    self:Apply()
end

function Ellesmere:DebugLine()
    return ("ellesmereui: tracker window %s, hide call %s, asked %s"):format(
        trackerWindow() and "present" or "none",
        type(_G._EQT_SetSuppressed) == "function" and "present" or "missing",
        self._asked and "yes" or "no")
end
