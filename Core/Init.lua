local addonName, ns = ...

_G.EQObjectiveTracker = ns
ns.NAME    = addonName
ns.VERSION = "1.11.1"

ns.modules     = {}
ns.moduleOrder = {}

function ns:RegisterModule(name, tbl)
    if self.modules[name] then
        error(("EQOT: module %q already registered"):format(name))
    end
    tbl = tbl or {}
    self.modules[name] = tbl
    self.moduleOrder[#self.moduleOrder + 1] = name
    return tbl
end

function ns:GetModule(name)
    return self.modules[name]
end

function ns:Print(...)
    print("|cffEBB706EQObjectiveTracker|r:", ...)
end

-- The client offers no way to open a browser, so a link is handed over as selectable text.
function ns:ShowURL(url)
    local D = self:GetModule("Dialog")
    if not (D and url) then return end
    local L = self.L
    D:Show({
        title            = "EQ Objective Tracker",
        -- Escaped em dash, not a literal: this file stays ASCII, and the port tool compares
        -- decoded bytes, so this still matches EQ's key and inherits its three translations.
        text             = L["Copy the link below (it's pre-selected \226\128\148 just press Ctrl+C):"],
        button1          = L["Close"],
        hasEditBox       = true,
        editBoxText      = url,
        highlightEditBox = true,
    })
end

-- One community server across every addon by this author. EQ titles this dialog with its
-- own name, so the faithful mirror is this addon's own name - and a standalone user who has
-- never installed EQ must not be shown another addon's branding.
ns.DISCORD_URL = "https://discord.gg/vm8K2WfQUE"

function ns:ShowDiscord()
    local D = self:GetModule("Dialog")
    if not D then return end
    local L = self.L
    D:Show({
        title            = "EQ Objective Tracker",
        text             = L["Join the community for help, feedback, and updates.\nCopy the invite below (it's pre-selected \226\128\148 just press Ctrl+C):"],
        button1          = L["Close"],
        hasEditBox       = true,
        editBoxText      = self.DISCORD_URL,
        highlightEditBox = true,
    })
end

-- Modules whose OnEnable is skipped this session, for bisecting a fault to one subsystem.
-- Driven by /eqot disable and persisted per account, so a reload keeps the choice. Core
-- plumbing is never skippable - dropping DB or Events breaks the addon rather than the test.
local NEVER_SKIP = {
    Entry = true, Registry = true, Feed = true, DB = true, Events = true,
    Media = true, Migrate = true, Commands = true, Tracker = true,
}

-- Read straight off the saved variable rather than through DB, so it answers correctly
-- before AceDB has initialized and from inside a module's own load-time code.
function ns:SafeMode()
    local db = _G.EQObjectiveTrackerDB
    return (db and db.global and db.global.safeMode) and true or false
end

-- An explicit enable outranks safe mode. Without that the bisection tool could turn
-- everything off and then never bring one subsystem back to test it, while reporting that it
-- had - which is the whole workflow the tool exists for.
function ns:IsModuleDisabled(name)
    if NEVER_SKIP[name] then return false end
    local db = _G.EQObjectiveTrackerDB
    local g  = db and db.global
    if g and g.enabledModules and g.enabledModules[name] then return false end
    if self:SafeMode() then return true end
    return (g and g.disabledModules and g.disabledModules[name]) and true or false
end

-- Providers are a separate axis: Registry itself must stay enabled or Feed has nothing to
-- iterate, but each provider can be marked unavailable so it registers no events and makes
-- no game API calls at all.
function ns:IsProviderDisabled(id)
    local db = _G.EQObjectiveTrackerDB
    local g  = db and db.global
    if g and g.enabledProviders and g.enabledProviders[id] then return false end
    if self:SafeMode() then return true end
    return (g and g.disabledProviders and g.disabledProviders[id]) and true or false
end

function ns:SkippableModules()
    local out = {}
    for _, name in ipairs(self.moduleOrder) do
        if not NEVER_SKIP[name] and self.modules[name].OnEnable then
            out[#out + 1] = name
        end
    end
    return out
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    for _, name in ipairs(ns.moduleOrder) do
        local m = ns.modules[name]
        if m.OnInitialize then xpcall(m.OnInitialize, geterrorhandler(), m) end
    end
    ns.skipped = {}
    for _, name in ipairs(ns.moduleOrder) do
        local m = ns.modules[name]
        if m.OnEnable then
            if ns:IsModuleDisabled(name) then
                ns.skipped[#ns.skipped + 1] = name
            else
                xpcall(m.OnEnable, geterrorhandler(), m)
            end
        end
    end
    if #ns.skipped > 0 then
        ns:Print("|cffff5555disabled this session:|r " .. table.concat(ns.skipped, ", "))
    end
end)
