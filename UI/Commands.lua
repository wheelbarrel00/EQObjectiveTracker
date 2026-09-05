local _, ns = ...

local Commands = ns:RegisterModule("Commands", {})
local L        = ns.L

local function tracker() return ns:GetModule("Tracker") end

local handlers = {}

handlers.lock = function()
    ns:GetModule("DB"):General().lockTracker = true
    tracker():ApplyLockState()
    ns:Print(L["tracker locked."])
end

handlers.unlock = function()
    ns:GetModule("DB"):General().lockTracker = false
    tracker():ApplyLockState()
    ns:Print(L["tracker unlocked."])
end

handlers.reset = function()
    tracker():ResetPosition()
    ns:Print(L["position and size reset."])
end

handlers.toggle = function()
    tracker():Toggle()
end

handlers.debug = function()
    ns.DEBUG = not ns.DEBUG
    ns:Print("debug validation " .. (ns.DEBUG and "on" or "off") .. ".")
    tracker():Render()
end

-- One module raising must not take the rest of the report
-- with it: this is the tool for diagnosing a broken subsystem, so it has to outlive one, and
-- a report that stops halfway reads as "the addon is fine up to here".
local function debugLine(name, prefix, method)
    local m = ns:GetModule(name)
    method = method or "DebugLine"
    if not (m and m[method]) then return end
    local ok, line = pcall(m[method], m)
    if not ok then
        ns:Print(("|cffff5555%s:%s raised|r %s"):format(name, method, tostring(line)))
        return
    end
    if line then ns:Print((prefix or "") .. line) end
end

handlers.status = function()
    local Registry = ns:GetModule("Registry")
    local Feed     = ns:GetModule("Feed")
    local RowPool  = ns:GetModule("RowPool")

    local Sections = ns:GetModule("Sections")

    ns:Print(("version %s"):format(ns.VERSION))

    -- Early, because a refused event registration explains a whole subsystem being silent
    -- and every counter below it would otherwise read as a clean zero.
    debugLine("Events")

    -- Rebuild first so the counters describe the current state, not the last repaint.
    -- Render skips entirely while the tracker is hidden, so the feed is built directly too
    -- or a rule-hidden tracker would report whatever the last paint happened to leave.
    ns:GetModule("Tracker"):Render()
    -- Render owns this refresh normally, but it returns early while hidden, and Filter reads
    -- the suppression set - so refresh here too or the direct build below reports stale rows.
    ns:GetModule("AutoQuestPopups"):Refresh()
    Feed:Build()

    ns:Print("providers (emitted -> duplicate / filtered / shown):")
    for _, p in ipairs(Registry:Active()) do
        if not p._available then
            ns:Print(("  %-14s unavailable on this client"):format(p.id))
        else
            local st = Feed.stats[p.id] or {}
            ns:Print(("  %-14s %d -> dup %d, filtered %d, shown %d")
                :format(p.id, st.emitted or 0, st.duplicate or 0,
                        st.filtered or 0, st.shown or 0))
            if p.DebugLine then
                local ok, line = pcall(p.DebugLine, p)
                ns:Print("      " .. (ok and (line or "")
                    or ("|cffff5555DebugLine raised|r " .. tostring(line))))
            end
        end
    end

    debugLine("Filter", nil, "FiltersLine")
    debugLine("Filter")

    ns:Print("sections (in render order):")
    local function sectionLine(id)
        local g = Feed.byGroup[id]
        ns:Print(("  %-14s %d/%d visible%s%s%s%s"):format(id,
            g and g.visibleCount or 0, g and g.totalCount or 0,
            Sections:IsVirtual(id) and "  [virtual]" or "",
            Sections:IsPinned(id) and "  [pinned]" or "",
            Sections:IsHidden(id) and "  [hidden]" or "",
            Sections:IsCollapsed(id) and "  [collapsed]" or ""))
    end
    for _, id in ipairs(Sections:Order()) do sectionLine(id) end
    -- Order() excludes pinned groups, so without this a pinned region reports nothing
    -- about its own hidden or collapsed state and an empty one reads as switched off.
    for _, id in ipairs(Sections:Known()) do
        if Sections:IsPinned(id) then sectionLine(id) end
    end

    local active, free = RowPool:Count()
    ns:Print(("rows: %d active, %d pooled"):format(active, free))
    debugLine("Row")
    debugLine("Tracker", "scroll: ", "DebugScroll")

    debugLine("ItemButtons")
    debugLine("ScenarioSpells")
    debugLine("ManualOrder")
    debugLine("Distance")
    debugLine("Migrate")
    debugLine("API")
    debugLine("AutoQuestPopups")
    debugLine("WatchPersist")
    debugLine("Blizzard")
    debugLine("AutoTrack")
    debugLine("QuestSound")
    debugLine("QuestProgress")
    debugLine("QuestieCoexist")
    debugLine("QuestLogChecks")
    debugLine("Visibility")

    local ZP = ns:GetModule("ZoneProgress")
    if ZP and ZP.DebugLines then
        local ok, lines = pcall(ZP.DebugLines, ZP)
        if ok and type(lines) == "table" then
            for _, line in ipairs(lines) do ns:Print(line) end
        elseif not ok then
            ns:Print("|cffff5555ZoneProgress:DebugLines raised|r " .. tostring(lines))
        end
    end

    debugLine("ZoneProgressBar")
    debugLine("ScenarioBonusHUD")
    debugLine("Widgets")
    debugLine("QuestGroups")
end

-- Bisection aid: skip a subsystem's OnEnable for a session so a fault can be narrowed to one
-- module. Persisted per account so it survives the reload it needs to take effect.
local function moduleCmd(cmd, rest)
    local db = ns.db
    if not db then ns:Print("database not ready."); return end
    db.global.disabledModules = db.global.disabledModules or {}
    local off = db.global.disabledModules
    local list = ns:SkippableModules()

    db.global.disabledProviders = db.global.disabledProviders or {}
    local offP = db.global.disabledProviders
    -- The explicit-enable sets. Safe mode turns everything off as a default, and these are
    -- what let one subsystem be brought back on top of it.
    db.global.enabledModules   = db.global.enabledModules or {}
    db.global.enabledProviders = db.global.enabledProviders or {}
    local on, onP = db.global.enabledModules, db.global.enabledProviders
    local Registry = ns:GetModule("Registry")

    -- Reports the EFFECTIVE state, not the raw flag: under safe mode the flag reads enabled
    -- for everything, which made the whole optional half look innocent when it was not.
    local function stateOf(disabled, overridden)
        if disabled then return "|cffff5555disabled|r" end
        if overridden and db.global.safeMode then return "enabled |cffffd100(override)|r" end
        return "enabled"
    end

    if cmd == "modules" then
        ns:Print(("skippable modules (safe mode %s, /reload to apply):")
            :format(db.global.safeMode and "|cffff5555ON|r" or "off"))
        for _, name in ipairs(list) do
            ns:Print(("  %-18s %s"):format(name, stateOf(ns:IsModuleDisabled(name), on[name])))
        end
        ns:Print("providers:")
        for _, p in ipairs(Registry:Active()) do
            ns:Print(("  %-18s %s"):format(p.id, stateOf(ns:IsProviderDisabled(p.id), onP[p.id])))
        end
        return
    end

    local want = strtrim(rest or "")
    if want == "" then ns:Print("usage: /eqot " .. cmd .. " <module>  (see /eqot modules)"); return end

    -- "all" is the first step of a bisection: everything optional off, including the two
    -- subsystems that have no OnEnable and are driven from the render pass instead.
    if want:lower() == "all" then
        if cmd == "disable" then
            db.global.safeMode = true
            -- Cleared so a bisection starts from a clean slate rather than inheriting an
            -- override left over from the previous one.
            wipe(on)
            wipe(onP)
            ns:Print("|cffff5555safe mode ON|r - every optional module, every provider, quest item buttons, quest popups and the event widget block are off. /reload to apply.")
        else
            db.global.safeMode = nil
            wipe(off)
            wipe(offP)
            wipe(on)
            wipe(onP)
            ns:Print("safe mode off, all modules and providers re-enabled. /reload to apply.")
        end
        return
    end

    -- The two sets are always written together, so they can never disagree.
    local disabling = (cmd == "disable")

    for _, name in ipairs(list) do
        if name:lower() == want:lower() then
            off[name] = disabling or nil
            on[name]  = (not disabling) or nil
            ns:Print(("%s is now %s. /reload to apply."):format(name,
                stateOf(disabling, on[name])))
            return
        end
    end

    for _, p in ipairs(Registry:Active()) do
        if p.id:lower() == want:lower() then
            offP[p.id] = disabling or nil
            onP[p.id]  = (not disabling) or nil
            ns:Print(("provider %s is now %s. /reload to apply."):format(p.id,
                stateOf(disabling, onP[p.id])))
            return
        end
    end

    ns:Print(("no module or provider %q. see /eqot modules"):format(want))
end

-- The automatic import only ever fires on a first run, so this is the only way to exercise
-- it without deleting the saved variables, and the only way back for someone who moved to
-- EQOT before installing it alongside EQ.
local function importEQ()
    local Migrate = ns:GetModule("Migrate")
    if not (Migrate and Migrate.HasEQConfig and Migrate:HasEQConfig()) then
        ns:Print(L["no Everything Quests configuration found to import."])
        return
    end

    local Dialog = ns:GetModule("Dialog")
    if not Dialog then return end
    Dialog:Show({
        title   = L["Import from Everything Quests"],
        text    = L["Reset this profile to defaults and replace it with your Everything Quests tracker settings?\n\nThis cannot be undone. Make a new profile first if you want to keep the current one."],
        button1 = L["Import"],
        button2 = L["Cancel"],
        onAccept = function()
            -- Reset first, because the import copies only the keys EQ actually saved. AceDB
            -- strips defaults at logout, so what survives there is the user's deviation, and
            -- laying that over a tuned profile would leave a hybrid of the two. Resetting
            -- also drops positionInScreenUnits, so the reload converts EQ's frame-space
            -- offsets exactly as it does on a first run.
            if ns.db and ns.db.ResetProfile then ns.db:ResetProfile() end
            local n = Migrate:ImportFromEQ(ns.db)
            n = n + Migrate:ImportCharFromEQ(ns.db, true)
            ns:Print((L["imported %d settings from Everything Quests."]):format(n or 0))
            ReloadUI()
        end,
    })
end

function Commands:OnEnable()
    SLASH_EQOT1 = "/eqot"
    SLASH_EQOT2 = "/eqobjectivetracker"
    SlashCmdList["EQOT"] = function(msg)
        local raw = strtrim(msg or "")
        local cmd, rest = raw:match("^(%S*)%s*(.-)$")
        cmd = (cmd or ""):lower()
        local fn = handlers[cmd]
        if cmd == "disable" or cmd == "enable" or cmd == "modules" then
            moduleCmd(cmd, rest)
        elseif cmd == "bonushud" then
            -- Guarded like flavorprobe below. The module is absent on a flavor whose TOC does
            -- not list it, and this is the one documented command that fetched it unguarded.
            local BH = ns:GetModule("ScenarioBonusHUD")
            if not BH then
                ns:Print("scenario bonus HUD is not loaded on this client.")
            elseif strtrim(rest or ""):lower() == "test" then
                BH:ToggleTest()
            else
                BH:Dump()
            end
        elseif cmd == "importeq" then
            importEQ()
        elseif cmd == "flavorprobe" then
            -- Deliberately absent from the usage line and from the About tab's command
            -- list: a temporary measurement command, not a feature, and every About tab row
            -- carries a wrapped description a translator would then have to carry.
            local P = ns:GetModule("FlavorProbe")
            -- The watch subcommand is opt in because it is the one probe that writes. It
            -- toggles one quest's watch state and toggles it back to whatever it found.
            if P then
                if strtrim(rest or ""):lower() == "watch" then P:WatchTest() else P:Dump() end
            end
        elseif cmd == "zoneprobe" then
            -- Undocumented for the same reason flavorprobe is: a measurement, not a feature.
            local QP = ns:GetModule("Registry"):Get("quests")
            if QP and QP.ZoneProbeLines then
                for _, l in ipairs(QP:ZoneProbeLines()) do ns:Print(l) end
            else
                ns:Print("zoneprobe: not available on this flavor")
            end
        elseif cmd == "wqprobe" then
            -- Undocumented for the same reason zoneprobe is. It rebuilds the provider, so it
            -- CURES the half it reports on - read it while the row is missing, not after.
            local WQ = ns:GetModule("Registry"):Get("worldquests")
            if WQ and WQ.ProbeLines then
                local okProbe, lines = pcall(function() return WQ:ProbeLines() end)
                if okProbe and type(lines) == "table" then
                    for _, l in ipairs(lines) do ns:Print(l) end
                else
                    ns:Print("wqprobe failed: " .. tostring(lines))
                end
            else
                ns:Print("wqprobe: not available on this flavor")
            end
        elseif cmd == "widgetprobe" then
            -- Undocumented for the same reason zoneprobe is. Read only: it never registers a
            -- UIWidgetContainer, which is the thing UI/Scenario.lua forbids.
            local SC = ns:GetModule("Registry"):Get("scenarios")
            if SC and SC.WidgetProbeLines then
                -- A set answers with everything registered against it, most of it not on
                -- screen, so hidden widgets are left out unless they are asked for.
                local all = strtrim(rest or ""):lower() == "all"
                for _, l in ipairs(SC:WidgetProbeLines(all)) do ns:Print(l) end
            else
                ns:Print("widgetprobe: not available on this flavor")
            end
        elseif fn then
            fn()
        elseif cmd == "" then
            ns:GetModule("Options"):Toggle()
        else
            -- The subcommands are literals the dispatcher matches, so they stay outside
            -- L. Only the word introducing them is translated.
            ns:Print(L["commands:"] .. " lock, unlock, reset, toggle, status, debug, "
                .. "bonushud [test], importeq, modules, disable <m>, enable <m>")
        end
    end
end
