-- Unit tests for "Use Blizzard's quest tracker", run against the SHIPPED source. Run from the repo
-- root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_blizzard_tracker.lua
--
-- The switch is read ONCE, by DB:OnInitialize, and everything it changes is decided at enable:
-- the modules that would double Blizzard's tracker or fight it for its watch list skip their
-- OnEnable, every provider reads as disabled, the tracker frame is never built, and Blizzard's
-- own tracker is never suppressed. Most ways that can fail are silent - two trackers on screen,
-- or none, and nothing printed.
--
-- LOADED WHOLE, in a sandbox per case: Core/Init.lua (and its login loader, fired by hand),
-- Core/DB.lua over an AceDB stub, Core/API.lua, Data/TrackedSet.lua, and where a case asks,
-- Data/Registry.lua, Data/AutoTrack.lua, UI/Blizzard.lua, UI/Visibility.lua, UI/Commands.lua
-- and Options/TabGeneral.lua. SLICED: Tracker:OnEnable, the HUD's Update, the bonus model's
-- Reconcile, the Questie hider's Apply, the zone bar's isFloating and the Classic provider's
-- clearLeftoverWatches, each of whose files needs far more to load whole. Every other module is
-- a fake carrying only an OnEnable that counts, and the fakes are the REAL module list read off
-- the retail and Vanilla TOCs, so a module added to either later must be put on a list.
--
-- THE CASE THAT EARNS IT is the explicit enable. A past /eqot bisection can leave
-- enabledModules.Blizzard set, and if that outranked the switch, the suppression would hide
-- Blizzard's tracker under a tracker window that was never built - no tracker at all.
--
-- OUT OF SCOPE BY CONSTRUCTION: what Blizzard's tracker draws once left alone, and Everything
-- Quests' side, which its own trackedpins_test.lua and trackerswitch_test.lua cover.

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
end

local function readFile(rel)
    local f = assert(io.open(repoFile(rel), "rb"))
    local s = f:read("*a")
    f:close()
    return (s:gsub("\r\n", "\n"))
end

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end

local function case(name, fn)
    print("== " .. name)
    local okRun, err = pcall(fn)
    ok(okRun, name .. " ran without raising" .. (okRun and "" or (" - " .. tostring(err))))
end

local function copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copy(v) end
    return out
end

local function overlay(dst, src)
    for k, v in pairs(src or {}) do
        if type(v) == "table" and type(dst[k]) == "table" then overlay(dst[k], v) else dst[k] = v end
    end
    return dst
end

-- The real module list per flavor, read off the TOC and each listed file, so the fakes below
-- are exactly the modules the loader would walk.
local function modulesOf(toc)
    local out = {}
    for line in (readFile(toc) .. "\n"):gmatch("([^\n]*)\n") do
        local rel = line:match("^([CDUO][%w]*\\.-%.lua)%s*$")
        if rel then
            local src = readFile((rel:gsub("\\", "/")))
            local name = src:match('RegisterModule%("([%w]+)"')
            if name then
                out[#out + 1] = { name = name, file = rel, enable = src:find(":OnEnable%(") ~= nil }
            end
        end
    end
    return out
end

local REAL = { API = "Core/API.lua", DB = "Core/DB.lua", TrackedSet = "Data/TrackedSet.lua" }
local RETAIL_TOC, CLASSIC_TOC = "EQObjectiveTracker_Mainline.toc", "EQObjectiveTracker_Vanilla.toc"

local function newFrame()
    local f = { scripts = {}, events = {}, points = {} }
    function f:RegisterEvent(e) self.events[e] = true end
    function f:SetScript(k, fn) self.scripts[k] = fn end
    function f:HookScript() end
    function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function f:SetSize() end
    function f:SetChecked(v) self.checked = v; self.setChecked = (self.setChecked or 0) + 1 end
    return f
end

-- A fresh addon per case, booted the way the client boots it: files load, then PLAYER_LOGIN runs
-- every OnInitialize and then every OnEnable.
local function boot(opts)
    opts = opts or {}
    local toc = opts.classic and CLASSIC_TOC or RETAIL_TOC
    local env = setmetatable({}, { __index = _G })
    env._G = env
    local frames, prints, raised = {}, {}, {}
    env.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        prints[#prints + 1] = table.concat(parts, " ")
    end
    env.CreateFrame = function() local f = newFrame(); frames[#frames + 1] = f; return f end
    env.geterrorhandler = function() return function(e) raised[#raised + 1] = tostring(e) end end
    -- The client's xpcall passes its extra arguments on. Stock 5.1 drops them, which would run
    -- every OnInitialize with no self.
    env.xpcall = function(fn, handler, ...)
        local args, n = { ... }, select("#", ...)
        return xpcall(function() return fn(unpack(args, 1, n)) end, handler)
    end
    env.EQObjectiveTrackerDB = { global = copy(opts.global or {}) }
    env.LibStub = function()
        return { New = function(_, svName, defaults)
            local sv = env[svName]
            local db = {
                profile = overlay(copy(defaults.profile), opts.profile),
                char    = overlay(copy(defaults.char), opts.char),
                global  = overlay(sv.global, copy(defaults.global)),
            }
            overlay(db.global, opts.global or {})
            return db
        end }
    end

    local ns = {}
    local function load(rel)
        local chunk = assert(loadfile(repoFile(rel)))
        setfenv(chunk, env)
        return chunk("EQObjectiveTracker", ns)
    end
    load("Core/Init.lua")
    ns.Has = { QuestWatchAPI = not opts.classic, QuestWatchType = not opts.classic }
    ns.L = setmetatable({}, { __index = function(_, k) return k end })

    local calls, fakes = {}, {}
    local real = {}
    for _, name in ipairs(opts.real or {}) do real[name] = true end
    for _, m in ipairs(modulesOf(toc)) do
        if REAL[m.name] then
            load(REAL[m.name])
        elseif real[m.name] then
            load((m.file:gsub("\\", "/")))
        elseif not ns.modules[m.name] then
            local t = ns:RegisterModule(m.name, {})
            fakes[m.name] = t
            if m.enable then
                t.OnEnable = function() calls[m.name] = (calls[m.name] or 0) + 1 end
            end
        end
    end

    local t = { ns = ns, env = env, calls = calls, fakes = fakes, prints = prints, raised = raised,
                API = ns.modules.API, DB = ns.modules.DB }
    function t.login()
        for _, f in ipairs(frames) do
            if f.events.PLAYER_LOGIN and f.scripts.OnEvent then f.scripts.OnEvent(f, "PLAYER_LOGIN") end
        end
    end
    function t.printed(needle)
        for _, p in ipairs(prints) do if p:find(needle, 1, true) then return true end end
        return false
    end
    function t.load(rel) return load(rel) end
    return t
end

local STOOD_DOWN = { "Blizzard", "QuestieCoexist", "ScenarioBonus", "ScenarioBonusHUD",
                     "ScenarioSpells", "Widgets", "WidgetBlock", "Visibility", "SuperTrackPersist",
                     "WatchPersist" }
local KEPT = { "Focus", "QuestCache", "QuestSound", "ZoneProgress", "ZoneProgressBar", "TaxiHighlight",
               "Options", "Registry", "Commands", "Tracker", "AutoTrack" }

-- A module added later with an OnEnable has to be put on one list or the other on purpose.
local function everyModuleDecided(t, extra)
    local decided = {}
    for _, name in ipairs(STOOD_DOWN) do decided[name] = true end
    for _, name in ipairs(KEPT) do decided[name] = true end
    for _, name in ipairs(extra or {}) do decided[name] = true end
    for name, fake in pairs(t.fakes) do
        if fake.OnEnable then ok(decided[name], name .. " is decided: stands down or is kept") end
    end
end

-- ------------------------------------------------------------------------------ the loader

case("Blizzard's tracker: what the login enables, retail", function()
    local t = boot({ profile = { general = { useBlizzardTracker = true } } })
    t.login()
    ok(#t.raised == 0, "nothing raised: " .. tostring(t.raised[1]))
    ok(t.ns:UsesBlizzardTracker() == true, "the session runs Blizzard's tracker")
    for _, name in ipairs(STOOD_DOWN) do
        ok(t.fakes[name] ~= nil, name .. " is a real retail module")
        ok(t.calls[name] == nil, name .. " stood down: " .. tostring(t.calls[name]))
        ok(t.ns:IsModuleDisabled(name) == true, name .. " reads disabled")
    end
    for _, name in ipairs(KEPT) do
        ok(t.calls[name] == 1, name .. " still enabled once: " .. tostring(t.calls[name]))
    end
    ok(t.ns.stoodDown == #STOOD_DOWN, "the count is the retail list: " .. tostring(t.ns.stoodDown))
    everyModuleDecided(t)
    ok(not t.printed("disabled this session"), "and no bisection warning at login")
    ok(t.ns:IsProviderDisabled("quests") == true and t.ns:IsProviderDisabled("worldquests") == true,
       "every provider reads disabled")
end)

case("Blizzard's tracker: Classic stands QuestLogChecks down too", function()
    local t = boot({ classic = true, profile = { general = { useBlizzardTracker = true } } })
    t.login()
    ok(#t.raised == 0, "nothing raised: " .. tostring(t.raised[1]))
    ok(t.fakes.QuestLogChecks ~= nil, "QuestLogChecks is a real Classic module")
    ok(t.calls.QuestLogChecks == nil, "QuestLogChecks stood down")
    ok(t.calls.Blizzard == nil, "as does the suppression")
    ok(t.calls.AutoTrack == 1, "auto-track stays, keeping Classic's own set current for the way back")
    ok(t.ns.stoodDown == #STOOD_DOWN + 1, "the count is the Classic list: " .. tostring(t.ns.stoodDown))
    ok(t.calls.Focus == 1 and t.calls.Tracker == 1, "Focus and Tracker's own OnEnable still run")
    everyModuleDecided(t, { "QuestLogChecks" })
end)

case("EQ Objective Tracker's window: nothing stands down (the control)", function()
    local t = boot({})
    t.login()
    ok(t.ns:UsesBlizzardTracker() == false, "the session runs the EQOT window")
    for _, name in ipairs(STOOD_DOWN) do
        ok(t.calls[name] == 1, name .. " enabled once: " .. tostring(t.calls[name]))
    end
    ok(t.ns.stoodDown == nil, "nothing counted as standing down: " .. tostring(t.ns.stoodDown))
    ok(t.ns:IsProviderDisabled("quests") == false, "providers are live")
    ok(not t.printed("disabled this session"), "and no warning")
end)

case("the bisection warning still fires for a real /eqot disable", function()
    local t = boot({ global = { disabledModules = { Blizzard = true } } })
    t.login()
    ok(t.calls.Blizzard == nil, "the disabled module was skipped")
    ok(t.printed("disabled this session:|r Blizzard"), "and named in the warning: " .. tostring(t.prints[1]))
end)

case("the switch outranks a leftover explicit enable", function()
    local t = boot({ profile = { general = { useBlizzardTracker = true } },
                     global = { enabledModules = { Blizzard = true, Visibility = true },
                                enabledProviders = { quests = true } } })
    t.login()
    ok(t.calls.Blizzard == nil, "a bisection's enable cannot bring the suppression back")
    ok(t.calls.Visibility == nil, "nor Visibility")
    -- Asked directly too: the render-driven modules ask this, never the loader.
    ok(t.ns:IsModuleDisabled("Blizzard") == true, "and IsModuleDisabled agrees, past the enable")
    ok(t.ns:IsModuleDisabled("Visibility") == true, "for Visibility as well")
    ok(t.ns:IsProviderDisabled("quests") == true, "nor a provider")
    ok(not t.printed("disabled this session"), "and still no warning")
end)

case("safe mode on EQOT's window is unchanged", function()
    local t = boot({ global = { safeMode = true } })
    t.login()
    ok(t.calls.Blizzard == nil and t.calls.Focus == nil, "safe mode still skips optional modules")
    ok(t.calls.Tracker == 1 and t.calls.Registry == 1, "and never core ones")
    ok(t.printed("disabled this session"), "and still says so")
    ok(t.ns.stoodDown == nil, "none of it counted as the switch")
end)

-- ------------------------------------------------------------------------------ the latch

case("the switch is read once, at initialize", function()
    local t = boot({ profile = { general = { useBlizzardTracker = true } } })
    ok(t.ns:UsesBlizzardTracker() == false, "before login nothing has read it yet")
    t.login()
    ok(t.ns:UsesBlizzardTracker() == true, "after login it has")

    local u = boot({})
    u.login()
    u.API:SetBlizzardTrackerSetting(true)
    ok(u.API:GetBlizzardTrackerSetting() == true, "the saved choice moves at once")
    ok(u.ns:UsesBlizzardTracker() == false, "the session does not, until the reload")
    ok(u.API:UsesBlizzardTracker() == false, "and the API says the same as ns")
    ok(u.ns:IsModuleDisabled("Blizzard") == false, "so nothing is half switched live")
end)

case("the API reads and writes the profile", function()
    local t = boot({})
    t.login()
    ok(t.DB.defaults.profile.general.useBlizzardTracker == false, "the default is off")
    ok(t.API:GetBlizzardTrackerSetting() == false, "reads off by default")
    ok(t.API:SetBlizzardTrackerSetting(true) == true, "a write reports success")
    ok(t.DB:General().useBlizzardTracker == true, "and lands in profile.general")
    ok(t.API:SetBlizzardTrackerSetting(false) == true, "an OFF write reports success too")
    ok(t.DB:General().useBlizzardTracker == false, "and lands as false")
    t.API:SetBlizzardTrackerSetting(true)
    t.API:SetBlizzardTrackerSetting(nil)
    ok(t.DB:General().useBlizzardTracker == false, "a nil writes false, never nil")
    t.DB:General().useBlizzardTracker = "yes"
    ok(t.API:GetBlizzardTrackerSetting() == false, "only a real true reads as on")

    local b = boot({ profile = { general = { useBlizzardTracker = true } } })
    b.login()
    ok(b.API:UsesBlizzardTracker() == true, "the API reports the session")
end)

-- ------------------------------------------------------------------------------ Classic's list

case("TrackedSet leaves the clear-up marker only for a Blizzard session", function()
    local t = boot({ classic = true, profile = { general = { useBlizzardTracker = true } } })
    t.login()
    ok(t.DB:Char().clearBlizzardWatches == true, "set during Blizzard's tracker")
    local u = boot({ classic = true })
    u.login()
    ok(u.DB:Char().clearBlizzardWatches == nil, "never during EQOT's window")
    local r = boot({ classic = true, char = { clearBlizzardWatches = true } })
    r.login()
    ok(r.DB:Char().clearBlizzardWatches == true, "and never cleared by TrackedSet itself")
    -- Set at initialize, which safe mode never skips, so a bisection on Blizzard's tracker still
    -- leaves the marker for the way back.
    local s = boot({ classic = true, global = { safeMode = true }, profile = { general = { useBlizzardTracker = true } } })
    s.login()
    ok(s.DB:Char().clearBlizzardWatches == true, "set in safe mode too")
end)

-- clearLeftoverWatches and the Questie check above it, sliced from the Classic provider with a
-- watch list that SHRINKS as the client's does, so a forward walk would skip every other watch.
local CLASSIC_SRC = readFile("Data/Providers/QuestsClassic.lua")
local CLEAR = CLASSIC_SRC:match("\n(local function questieTrackerRuns%(%).-\nend\n.-local function clearLeftoverWatches%(%).-\nend\n)")

local function clearWorld(opts)
    local char = opts.char or {}
    local list = opts.watches and copy(opts.watches) or {}
    local removed = {}
    local env = setmetatable({}, { __index = _G })
    env.ns = { Has = { AddOns = opts.addOnsAPI ~= false },
               GetModule = function(_, n) if n == "DB" then return { Char = function() return char end } end end }
    -- No AddOns API means no C_AddOns table at all, so the guard on it is what is tested.
    if opts.addOnsAPI ~= false then
        env.C_AddOns = { IsAddOnLoaded = function(name) return name == "Questie" and opts.questieLoaded == true end }
    else
        env.C_AddOns = false
    end
    env.Questie = opts.questieGlobal
    if not opts.noWatchAPI and not opts.noCount then
        env.GetNumQuestWatches = function() return #list end
    end
    if not opts.noWatchAPI and not opts.noIndex then
        env.GetQuestIndexForWatch = function(i) return list[i] end
    end
    local flags = {}
    if not opts.noRemove then
        -- Questie's hook reads a second argument of true as its own removal and leaves its list alone.
        env.RemoveQuestWatch = function(index, isQuestie)
            flags[#flags + 1] = tostring(isQuestie)
            removed[#removed + 1] = index
            for i = #list, 1, -1 do if list[i] == index then table.remove(list, i) end end
        end
    end
    -- Rows count from 1, as the client's do: row 0 answers nothing.
    env.GetQuestLogTitle = function(i)
        if opts.logLoaded ~= false and type(i) == "number" and i >= 1 then return "A quest" end
    end
    local chunk = assert(loadstring(CLEAR .. "\nreturn clearLeftoverWatches", "clearLeftoverWatches"))
    setfenv(chunk, env)
    chunk()()
    return table.concat(removed, ","), #list, char.clearBlizzardWatches, table.concat(flags, ",")
end

case("clearLeftoverWatches empties Blizzard's list once, after a Blizzard session", function()
    ok(CLEAR ~= nil, "the function is where the slice expects it")
    local removed, left, flag, flags = clearWorld({ char = { clearBlizzardWatches = true }, watches = { 4, 9, 2 } })
    ok(removed == "2,9,4", "every watch removed, walked from the end: " .. removed)
    ok(flags == "true,true,true", "each removal flagged so Questie's hook leaves its own list alone: " .. flags)
    ok(left == 0, "nothing left: " .. left)
    ok(flag == nil, "and the marker cleared")

    removed, left, flag = clearWorld({ watches = { 4, 9 } })
    ok(removed == "" and left == 2 and flag == nil, "no marker, nothing touched: " .. removed)

    removed, left, flag = clearWorld({ char = { clearBlizzardWatches = true }, watches = { 4 }, logLoaded = false })
    ok(removed == "" and left == 1 and flag == true, "an unloaded log waits and keeps the marker")

    removed, left, flag = clearWorld({ char = { clearBlizzardWatches = true }, watches = { 4 }, noWatchAPI = true })
    ok(removed == "" and left == 1 and flag == true, "a client with no watch list keeps the marker")

    removed, left, flag = clearWorld({ char = { clearBlizzardWatches = true }, watches = {} })
    ok(removed == "" and left == 0 and flag == nil, "an empty list clears the marker")

    -- Each watch function missing on its own, so no one guard can stand in for another.
    for _, missing in ipairs({ "noCount", "noIndex", "noRemove" }) do
        local o = { char = { clearBlizzardWatches = true }, watches = { 4 } }
        o[missing] = true
        local okRun, r, l, f = pcall(clearWorld, o)
        ok(okRun and r == "" and l == 1 and f == true, missing .. ": nothing touched, no raise, marker kept")
    end

    -- Questie hooks RemoveQuestWatch to untrack its own copy while its tracker runs, so nothing is
    -- removed then. With its tracker off it installs no hook, and that is when Blizzard's list fills.
    local QUESTIE_ON  = { db = { profile = { trackerEnabled = true } } }
    local QUESTIE_OFF = { db = { profile = { trackerEnabled = false } } }
    removed, left, flag = clearWorld({ char = { clearBlizzardWatches = true }, watches = { 4 },
                                       questieLoaded = true, questieGlobal = QUESTIE_ON })
    ok(removed == "" and left == 1 and flag == true, "Questie's tracker on: nothing removed, the marker kept")
    removed, left, flag = clearWorld({ char = { clearBlizzardWatches = true }, watches = { 4, 9 },
                                       questieLoaded = true, questieGlobal = QUESTIE_OFF })
    ok(removed == "9,4" and left == 0 and flag == nil, "Questie's tracker off: cleared as with no Questie")
    removed, left, flag = clearWorld({ char = { clearBlizzardWatches = true }, watches = { 4 },
                                       questieLoaded = true })
    ok(removed == "" and left == 1 and flag == true, "Questie loaded but its global not there yet: counts as on")
    removed, left, flag = clearWorld({ char = { clearBlizzardWatches = true }, watches = { 4 },
                                       addOnsAPI = false, questieGlobal = { db = {} } })
    ok(removed == "" and left == 1 and flag == true, "Questie's global alone, profile unreadable: counts as on")
    removed, left, flag = clearWorld({ char = { clearBlizzardWatches = true }, watches = { 4 },
                                       addOnsAPI = false, questieGlobal = QUESTIE_OFF })
    ok(removed == "4" and left == 0 and flag == nil, "Questie's global alone with its tracker off: cleared")
end)

-- The hook that empties Blizzard's list behind every add, sliced from Enable. Questie's own
-- RemoveQuestWatch hook untracks a quest on any removal not flagged as its own.
local ADD_HOOK = CLASSIC_SRC:match('hooksecurefunc%("AddQuestWatch", (function%(index%).-\n        end)%)')

case("the add hook removes with Questie's flag, once", function()
    ok(ADD_HOOK ~= nil, "the hook is where the slice expects it")
    local calls = {}
    local env = setmetatable({ suppressWatchHook = false }, { __index = _G })
    -- Another addon answering the removal with an add, which the guard must not bounce on.
    env.RemoveQuestWatch = function(index, isQuestie)
        calls[#calls + 1] = tostring(index) .. ":" .. tostring(isQuestie)
        env.hook(index)
    end
    local chunk = assert(loadstring("return " .. ADD_HOOK, "AddQuestWatch hook"))
    setfenv(chunk, env)
    env.hook = chunk()
    env.hook(7)
    ok(table.concat(calls, ",") == "7:true", "one removal, flagged as not the player's: " .. table.concat(calls, ","))
    ok(env.suppressWatchHook == false, "and the guard released for the next add")
end)

-- ------------------------------------------------------------------------------ no window

local function trackerEnable(uses)
    local src = readFile("UI/Tracker.lua")
    local body = src:match("\n(function Tracker:OnEnable%(%).-\nend\n)")
    assert(body, "Tracker:OnEnable not found")
    local built, dirty = 0, 0
    local env = setmetatable({}, { __index = _G })
    env.Tracker = {
        BuildFrame = function() built = built + 1 end,
        ApplyHeaderIcons = function() end, Render = function() end, Refresh = function() end,
    }
    env.ns = {
        UsesBlizzardTracker = function() return uses end,
        GetModule = function(_, n)
            if n == "Registry" then return { OnDirty = function() dirty = dirty + 1 end } end
            if n == "Events" then return { On = function() end } end
            return nil
        end,
    }
    local chunk = assert(loadstring(body, "Tracker:OnEnable"))
    setfenv(chunk, env)
    chunk()
    env.Tracker:OnEnable()
    return built, dirty
end

case("the tracker window is never built for Blizzard's tracker", function()
    local built, dirty = trackerEnable(true)
    ok(built == 0, "no frame built: " .. built)
    ok(dirty == 0, "and no repaint subscription: " .. dirty)
    built, dirty = trackerEnable(false)
    ok(built == 1 and dirty == 1, "EQOT's window builds as before: " .. built .. "/" .. dirty)
end)

case("Visibility:Apply installs no map hook while standing down", function()
    local function hooks(useBlizzard)
        local t = boot({ real = { "Visibility" },
                         profile = { general = { useBlizzardTracker = useBlizzard, hideOnMapOpen = true } } })
        local n = 0
        t.env.WorldMapFrame = { IsShown = function() return false end }
        t.env.hooksecurefunc = function() n = n + 1 end
        t.ns.modules.Events = { On = function() return true end }
        t.login()
        t.ns.modules.Visibility:Apply()
        return n
    end
    ok(hooks(true) == 0, "Blizzard's tracker: no world map hook, from login or a direct Apply")
    ok(hooks(false) == 2, "EQOT's window: the Show and Hide hooks the rule needs (the control)")
end)

-- ------------------------------------------------------------------------------ /eqot

-- savedFlip writes the opposite choice after login, so the saved choice and the session differ
-- the way they do between a write and its reload.
local function commands(useBlizzard, savedFlip)
    local t = boot({ real = { "Commands" }, profile = { general = { useBlizzardTracker = useBlizzard } } })
    t.env.SlashCmdList = {}
    t.env.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
    t.env.wipe = function(x) for k in pairs(x) do x[k] = nil end return x end
    local toggled = 0
    t.login()
    if savedFlip then t.API:SetBlizzardTrackerSetting(not useBlizzard) end
    t.ns.modules.Tracker.Toggle = function() toggled = toggled + 1 end
    t.ns.modules.Registry.Active = function() return { { id = "quests" }, { id = "worldquests" } } end
    t.env.SlashCmdList.EQOT("toggle")
    t.env.SlashCmdList.EQOT("modules")
    t.env.SlashCmdList.EQOT("enable Blizzard")
    t.env.SlashCmdList.EQOT("enable quests")
    t.env.SlashCmdList.EQOT("enable Focus")
    return t, toggled
end

local function printedLine(t, needle)
    for _, p in ipairs(t.prints) do if p:find(needle, 1, true) then return p end end
    return ""
end

local function lineFor(t, name)
    for _, p in ipairs(t.prints) do
        if p:find("  " .. name .. " ", 1, true) then return p end
    end
end

case("/eqot toggle and /eqot modules say why", function()
    local t, toggled = commands(true)
    ok(toggled == 0, "toggle does not reach the tracker: " .. toggled)
    ok(t.printed("Blizzard's quest tracker is in use - see /eqot, General."), "and says what is going on")
    ok((lineFor(t, "Blizzard") or ""):find("off, Blizzard's tracker in use", 1, true) ~= nil,
       "a stood-down module is named as such: " .. tostring(lineFor(t, "Blizzard")))
    ok((lineFor(t, "quests") or ""):find("off, Blizzard's tracker in use", 1, true) ~= nil,
       "so is a provider: " .. tostring(lineFor(t, "quests")))
    ok((lineFor(t, "Focus") or ""):find("enabled", 1, true) ~= nil,
       "a kept module reads enabled: " .. tostring(lineFor(t, "Focus")))

    local SUFFIX = "It stays off while Blizzard's tracker is in use."
    ok(printedLine(t, "Blizzard is now"):find(SUFFIX, 1, true) ~= nil,
       "enabling a stood-down module says it stays off: " .. printedLine(t, "Blizzard is now"))
    ok(printedLine(t, "provider quests is now"):find(SUFFIX, 1, true) ~= nil,
       "and so does enabling a provider: " .. printedLine(t, "provider quests is now"))
    ok(printedLine(t, "Focus is now") ~= "" and printedLine(t, "Focus is now"):find(SUFFIX, 1, true) == nil,
       "a kept module carries no such note: " .. printedLine(t, "Focus is now"))

    local u, toggledU = commands(false)
    ok(toggledU == 1, "on EQOT's window toggle still toggles")
    ok(not u.printed("Blizzard's quest tracker is in use"), "and prints nothing about it")
    ok((lineFor(u, "Blizzard") or ""):find("enabled", 1, true) ~= nil,
       "and the module list is untouched: " .. tostring(lineFor(u, "Blizzard")))
    ok(not u.printed(SUFFIX), "and no enable carries the note")

    -- toggle answers the session, never the saved choice, which only the reload applies.
    local s, toggledS = commands(true, true)
    ok(toggledS == 0 and s.printed("Blizzard's quest tracker is in use"),
       "Blizzard's session with EQOT's window saved: toggle still says why")
    local w, toggledW = commands(false, true)
    ok(toggledW == 1 and not w.printed("Blizzard's quest tracker is in use"),
       "EQOT's session with Blizzard's saved: toggle still toggles")
end)

case("/eqot status names the tracker in use and the saved choice", function()
    -- A stood-down module's own line looks like a fault (it never enabled), and a kept one's must
    -- still print as it is.
    local function status(useBlizzard, stored, classic, arrange)
        local t = boot({ real = { "Commands" }, classic = classic,
                         profile = { general = { useBlizzardTracker = useBlizzard } } })
        t.env.SlashCmdList = {}
        t.env.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
        t.login()
        local m = t.ns.modules
        local built = 0
        m.Tracker.Render = function() built = built + 1 end
        m.AutoQuestPopups = { Refresh = function() built = built + 1 end }
        m.Feed = { Build = function() built = built + 1 end, stats = {}, byGroup = {} }
        m.Registry.Active = function() return { { id = "quests", _available = false } } end
        m.Sections = { Order = function() return {} end, Known = function() return {} end }
        m.RowPool = { Count = function() return 0, 0 end }
        m.QuestieCoexist.DebugLine = function() return "questie coexist: hook missing" end
        m.QuestSound.DebugLine = function() return "quest sound: ready" end
        -- The second line of a stood-down module is said nowhere, or it reads as a fault twice.
        m.Blizzard.DebugLine = function() return "blizzard tracker: SHOWN - suppression lost" end
        m.Blizzard.QuestTimerLine = function() return "blizzard quest timer: SHOWN - suppression lost" end
        m.Visibility.DebugLine = function() return "visibility: rules" end
        m.Visibility.FadeLine = function() return "fade: opacity" end
        m.Tracker.DebugScroll = function() return "no frame" end
        m.Tracker.HeightLine = function() return "tracker height: unmeasured" end
        m.ItemButtons.DebugLine = function() return "item buttons: on | container none" end
        -- Each flavor's own frame and count. Retail also answers the bare count with another
        -- figure, so reading the wrong one shows. Classic's frame is hidden with nothing watched,
        -- as QuestWatch_Update leaves it, and Classic has a C_QuestLog with no watch count in it.
        -- IsShown reads its frame through self, as a client method does.
        local function frame(isShown) return { isShown = isShown, IsShown = function(self) return self.isShown end } end
        if classic then
            t.env.QuestWatchFrame = frame(false)
            t.env.C_QuestLog = { GetQuestObjectives = function() return {} end }
            t.env.GetNumQuestWatches = function() return 0 end
        else
            t.env.ObjectiveTrackerFrame = frame(true)
            t.env.C_QuestLog = { GetNumQuestWatches = function() return 2 end }
            t.env.GetNumQuestWatches = function() return 9 end
        end
        if arrange then arrange(t.env) end
        if stored ~= nil then t.API:SetBlizzardTrackerSetting(stored) end
        t.env.SlashCmdList.EQOT("status")
        return printedLine(t, "tracker in use:"), built, printedLine(t, "  quests "), t
    end
    local function count(t, needle)
        local n = 0
        for _, p in ipairs(t.prints) do if p:find(needle, 1, true) then n = n + 1 end end
        return n
    end
    local line, built, provider, t = status(true)
    ok(line:find("tracker in use: Blizzard's | setting Blizzard's | 10 module(s) standing down"
                 .. " | Blizzard's frame shown, 2 quest(s) watched", 1, true) ~= nil,
       "Blizzard's session, whether Blizzard's own frame is shown, and the namespaced count: " .. line)
    ok(count(t, "Blizzard: off, Blizzard's tracker in use") == 1 and count(t, "Visibility: off") == 1,
       "each stood-down module is named once")
    ok(count(t, "suppression lost") == 0 and count(t, "fade: opacity") == 0,
       "and none of its own lines print")
    ok(count(t, "no frame") == 0 and count(t, "tracker height") == 0 and count(t, "Tracker: off") == 0,
       "the tracker window's own lines are not printed for a window never built")
    ok(count(t, "container none") == 0 and count(t, "ItemButtons: off, Blizzard's tracker in use") == 1,
       "nor are the item buttons', which have no window to sit in")
    ok(built == 0, "and no feed is built for a tracker that is not there: " .. built)
    ok(provider:find("off, Blizzard's tracker in use", 1, true) ~= nil, "a provider says why it is off: " .. provider)
    ok(t.printed("QuestieCoexist: off, Blizzard's tracker in use") and not t.printed("hook missing"),
       "a stood-down module is named as off, not as broken")
    ok(t.printed("quest sound: ready"), "a kept module's own line still prints")
    line = status(true, nil, true)
    ok(line:find("| 11 module(s) standing down | Blizzard's frame hidden, 0 quest(s) watched", 1, true) ~= nil,
       "Classic counts QuestLogChecks too, and an empty list explains a hidden frame: " .. line)
    line = status(true, nil, true, function(env) env.QuestWatchFrame = nil; env.GetNumQuestWatches = nil end)
    ok(line:find("| Blizzard's frame absent, ? quest(s) watched", 1, true) ~= nil,
       "no frame and no count say so: " .. line)
    line = status(true, nil, false, function(env)
        env.ObjectiveTrackerFrame = { IsShown = function() error("protected") end }
        env.C_QuestLog = { GetNumQuestWatches = function() error("protected") end }
    end)
    ok(line:find("| Blizzard's frame unreadable, ? quest(s) watched", 1, true) ~= nil,
       "a raising read leaves the line standing: " .. line)
    line = status(true, nil, false, function(env) env.C_QuestLog = { GetNumQuestWatches = function() return nil end } end)
    ok(line:find("shown, ? quest(s) watched", 1, true) ~= nil, "a count that is not a number reads unknown: " .. line)
    line, built, provider, t = status(false, true)
    ok(line:find("tracker in use: EQ Objective Tracker | setting Blizzard's | 0 module(s) standing down", 1, true) ~= nil
       and line:find("frame", 1, true) == nil,
       "a choice waiting for its reload reads apart from the session, with no frame state: " .. line)
    ok(count(t, "suppression lost") == 2 and count(t, "fade: opacity") == 1,
       "EQOT's window: every module's own lines print as before")
    ok(count(t, "scroll: no frame") == 1 and count(t, "tracker height: unmeasured") == 1
       and count(t, "container none") == 1 and count(t, "ItemButtons: off") == 0,
       "EQOT's window: the tracker's and item buttons' own lines print as before")
    ok(built == 3, "EQOT's window: render, popups and the feed as before: " .. built)
    ok(provider:find("unavailable on this client", 1, true) ~= nil, "and an unavailable provider reads so: " .. provider)
    ok(t.printed("questie coexist: hook missing"), "and every module's own line prints as before")
end)

case("/eqot enable all says what stays off", function()
    local function all(useBlizzard)
        local t = boot({ real = { "Commands" }, profile = { general = { useBlizzardTracker = useBlizzard } } })
        t.env.SlashCmdList = {}
        t.env.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
        t.env.wipe = function(x) for k in pairs(x) do x[k] = nil end return x end
        t.login()
        t.env.SlashCmdList.EQOT("enable all")
        return printedLine(t, "safe mode off")
    end
    ok(all(true):find("Those that stand down for Blizzard's tracker stay off.", 1, true) ~= nil,
       "Blizzard's tracker: the stand-down is named: " .. all(true))
    ok(all(false):find("stay off", 1, true) == nil and all(false) ~= "", "EQOT's window: no such note")
end)

-- ------------------------------------------------------------------------------ the checkbox

local LABEL = "Use Blizzard's quest tracker"

local function generalTab(useBlizzard, opts)
    opts = opts or {}
    local t = boot({ profile = { general = { useBlizzardTracker = useBlizzard } } })
    t.login()
    if opts.refuseWrite then t.API.SetBlizzardTrackerSetting = function() return false end end
    local shown, reloads, timers = {}, 0, {}
    t.env.ReloadUI = function() reloads = reloads + 1 end
    t.env.C_Timer = { After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end }
    t.ns.modules.QuestieCoexist = { QuestiePresent = function() return false end }
    if not opts.noDialog then
        t.ns.modules.Dialog = { Show = function(_, o) shown[#shown + 1] = o end }
    else
        t.ns.modules.Dialog = nil
    end
    local spec, boxes = nil, {}
    local O = { GAP = { tabHead = -16, head = -10, aboveHead = -20 } }
    function O:RegisterTab(s) spec = s end
    function O:CreateHeading() return newFrame() end
    function O:CreateCheckbox(_, label, getter, setter, tooltip)
        local f = newFrame()
        f.getter, f.setter, f.tooltip = getter, setter, tooltip
        boxes[label] = f
        return f
    end
    function O:CreateSlider() local f = newFrame(); f.slider = newFrame(); return f end
    function O:CreateButton() return newFrame() end
    function O:CreateDropdown() local f = newFrame(); f.button = newFrame(); return f end
    function O:AttachTooltip() end
    function O:ApplyWindowScale() end
    t.ns.modules.Options = O
    t.load("Options/TabGeneral.lua")
    spec.build(O, newFrame())
    return { t = t, box = boxes[LABEL], lock = boxes["Lock tracker"], shown = shown, timers = timers,
             reloads = function() return reloads end }
end

local HINT = "The interface did not reload. Type /reload to finish."

case("the General tab's box asks first and saves only on Yes", function()
    local g = generalTab(false)
    ok(g.box ~= nil, "the box is built")
    ok(g.box.getter() == false, "it reads the saved choice")
    ok(g.box.tooltip ~= nil and g.box.tooltip:find("reloads", 1, true) ~= nil, "its tooltip says it reloads")

    g.box.setter(true)
    ok(#g.shown == 1, "ticking it asks: " .. #g.shown)
    local o = g.shown[1] or {}
    ok(o.text == "Switch to Blizzard's quest tracker? The interface will reload.", "with the switch text: " .. tostring(o.text))
    ok(o.button1 == "Yes" and o.button2 == "Cancel", "Yes and Cancel")
    ok(g.t.API:GetBlizzardTrackerSetting() == false, "nothing saved before the answer")
    ok(g.reloads() == 0, "and nothing reloaded")
    o.onAccept()
    ok(g.t.API:GetBlizzardTrackerSetting() == true, "Yes saves it")
    ok(g.reloads() == 1, "and reloads")
    -- A reload that goes ahead tears the UI down before the timer, so only a refused one prints.
    ok(#g.timers == 1 and g.timers[1].delay == 1, "a hint waits a second behind the reload: " .. #g.timers)
    ok(not g.t.printed(HINT), "and says nothing yet")
    if g.timers[1] then g.timers[1].fn() end
    ok(g.t.printed(HINT), "then tells the player to finish with /reload")

    local c = generalTab(false)
    c.box.setter(true)
    c.shown[1].onCancel()
    ok(c.t.API:GetBlizzardTrackerSetting() == false, "Cancel saves nothing")
    ok(c.reloads() == 0, "reloads nothing")
    ok(c.box.checked == false, "and puts the box back")
    ok(#c.timers == 0, "and leaves no hint")

    local b = generalTab(true)
    ok(b.box.getter() == true, "on Blizzard's tracker it reads ticked")
    b.box.setter(false)
    ok((b.shown[1] or {}).text == "Switch back to the EQ Objective Tracker window? The interface will reload.",
       "unticking asks the way back: " .. tostring((b.shown[1] or {}).text))
    b.shown[1].onAccept()
    ok(b.t.API:GetBlizzardTrackerSetting() == false and b.reloads() == 1, "and Yes switches back")

    local bc = generalTab(true)
    bc.box.setter(false)
    bc.shown[1].onCancel()
    ok(bc.box.checked == true, "untick then Cancel on Blizzard's tracker puts the tick back")
    ok(bc.t.API:GetBlizzardTrackerSetting() == true and bc.reloads() == 0, "and saves or reloads nothing")

    -- Saved and session differ only until a reload, and the box shows the saved choice then.
    local p = generalTab(false)
    p.t.API:SetBlizzardTrackerSetting(true)
    ok(p.box.getter() == true, "the box reads the saved choice, not the session")

    local n = generalTab(false, { noDialog = true })
    n.box.setter(true)
    ok(n.box.checked == false, "no dialog module: the box goes straight back")
    ok(n.t.API:GetBlizzardTrackerSetting() == false and n.reloads() == 0, "and nothing is saved or reloaded")

    local r = generalTab(false, { refuseWrite = true })
    r.box.setter(true)
    r.shown[1].onAccept()
    ok(r.reloads() == 0 and r.box.checked == false, "a refused write reloads nothing and puts the box back")
    ok(#r.timers == 0, "and leaves no hint")
    ok((g.shown[1] or {}).title == "EQ Objective Tracker", "the dialog is titled for this addon")
end)

-- The REAL UI/Dialog.lua on permissive stubs: a method a stub does not model is a no-op.
local function stubFrame()
    local f = { shown = false, scripts = {} }
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:SetScript(name, fn) self.scripts[name] = fn end
    function f:ClearFocus() self.cleared = true end
    function f:GetText() return self.text end
    function f:SetText(s) self.text = s end
    function f:GetStringWidth() return 40 end
    function f:GetStringHeight() return 14 end
    function f:GetFont() return "font", 12 end
    function f:CreateTexture() return stubFrame() end
    function f:CreateFontString() return stubFrame() end
    function f:GetFontString() return stubFrame() end
    return setmetatable(f, { __index = function() return function() end end })
end

local function realDialog()
    local handled = {}
    local ns = { L = setmetatable({}, { __index = function(_, k) return k end }) }
    function ns:RegisterModule(_, m) self.dialog = m; return m end
    function ns:GetModule() return { RunWhenOutOfCombat = function() end } end
    local env = setmetatable({
        CreateFrame = function() return stubFrame() end, UIParent = stubFrame(), BackdropTemplateMixin = {},
        InCombatLockdown = function() return false end,
        geterrorhandler = function() return function(e) handled[#handled + 1] = tostring(e) end end,
    }, { __index = _G })
    local chunk = assert(loadfile(repoFile("UI/Dialog.lua")))
    setfenv(chunk, env)
    chunk("EQObjectiveTracker", ns)
    return ns.dialog, handled
end

case("the dialog runs a button's callback before it hides", function()
    -- A ReloadUI from Yes was blocked on retail 12.1 while the dialog hid first.
    local D = realDialog()
    local during
    D:Show({ button1 = "Yes", button2 = "Cancel", onAccept = function() during = D.frame:IsShown() end })
    D.frame.editBox.cleared = nil
    D.frame.accept.scripts.OnClick()
    ok(during == true, "Yes runs its callback with the dialog still up: " .. tostring(during))
    ok(D.frame:IsShown() == false, "then hides it")
    ok(D.frame.editBox.cleared == true, "and the edit box lets go of the keyboard")

    local C = realDialog()
    local cancelled
    C:Show({ button1 = "Yes", button2 = "Cancel", onCancel = function() cancelled = C.frame:IsShown() end })
    C.frame.cancel.scripts.OnClick()
    ok(cancelled == true and C.frame:IsShown() == false, "Cancel the same: " .. tostring(cancelled))

    local N = realDialog()
    local second = { button1 = "OK" }
    N:Show({ button1 = "Yes", onAccept = function() N:Show(second) end })
    N.frame.accept.scripts.OnClick()
    ok(N.frame:IsShown() == true and N.opts == second, "a callback that opens the next dialog keeps it on screen")

    local R, handled = realDialog()
    R:Show({ button1 = "Yes", onAccept = function() error("boom", 0) end })
    local okRun = pcall(R.frame.accept.scripts.OnClick)
    ok(okRun and R.frame:IsShown() == false, "a raising callback still closes the dialog")
    ok(handled[1] == "boom", "and reaches the error handler: " .. tostring(handled[1]))

    local RC, handledC = realDialog()
    RC:Show({ button1 = "Yes", button2 = "Cancel", onCancel = function() error("boom", 0) end })
    okRun = pcall(RC.frame.cancel.scripts.OnClick)
    ok(okRun and RC.frame:IsShown() == false and handledC[1] == "boom", "and a raising Cancel the same")

    -- New Profile's path: what was typed reaches onAccept from the button and from Enter, with the
    -- keyboard already let go, so a re-prompt from the callback opens with the cursor in its box.
    for _, route in ipairs({ "button", "enter" }) do
        local T = realDialog()
        local got, focusFreed
        T:Show({ button1 = "OK", button2 = "Cancel", hasEditBox = true,
                 onAccept = function(text) got = text; focusFreed = T.frame.editBox.cleared end })
        T.frame.editBox:SetText("Raid")
        T.frame.editBox.cleared = nil
        if route == "button" then T.frame.accept.scripts.OnClick() else T.frame.editBox.scripts.OnEnterPressed() end
        ok(got == "Raid", route .. ": what was typed reaches onAccept: " .. tostring(got))
        ok(focusFreed == true, route .. ": the edit box let go before the callback ran")
    end

    -- Escape cancels from the frame and the edit box. Enter with no edit box is swallowed, never an
    -- accept, since most of these confirms reload.
    for _, route in ipairs({ "frame", "editbox", "enter" }) do
        local E = realDialog()
        local got = "nothing"
        E:Show({ button1 = "Yes", button2 = "Cancel", hasEditBox = (route == "editbox"),
                 onAccept = function() got = "accepted" end, onCancel = function() got = "cancelled" end })
        if route == "frame" then
            E.frame.scripts.OnKeyDown(E.frame, "ESCAPE")
        elseif route == "editbox" then
            E.frame.editBox.scripts.OnEscapePressed()
        else
            E.frame.scripts.OnKeyDown(E.frame, "ENTER")
        end
        local want = (route == "enter") and "nothing" or "cancelled"
        ok(got == want, route .. ": " .. got)
    end

    local I = realDialog()
    local first = "nothing"
    local nextOne = { button1 = "OK" }
    I:Show({ button1 = "Yes", button2 = "Cancel",
             onAccept = function() first = "accepted" end, onCancel = function() first = "cancelled" end })
    I:Show(nextOne)
    ok(first == "cancelled" and I.frame:IsShown() == true and I.opts == nextOne,
       "a dialog opened over another cancels it: " .. first)
end)

case("the box heads the General column", function()
    local g = generalTab(false)
    local p = g.box.points[1] or {}
    ok(p[1] == "TOPLEFT" and p[3] == "BOTTOMLEFT" and p[5] == -16, "under the heading at the tab gap")
    local l = g.lock.points[1] or {}
    ok(l[2] == g.box and l[5] == -2, "and Lock tracker hangs off it")
end)

-- ------------------------------------------------------------------------------ the rest

case("the REAL registry never enables a provider under Blizzard's tracker", function()
    local function enables(useBlizzard)
        local t = boot({ real = { "Registry" }, profile = { general = { useBlizzardTracker = useBlizzard } } })
        local inits, enabled = 0, 0
        t.ns.modules.Registry:Register({ id = "probe", groups = { "probe" }, GetEntries = function() return {} end,
            Init = function() inits = inits + 1 end, Enable = function() enabled = enabled + 1 end })
        t.login()
        return inits, enabled, t.ns.modules.Registry:Get("probe")._available
    end
    local i, e, a = enables(true)
    ok(i == 0 and e == 0 and a == false, "Blizzard's tracker: no Init, no Enable, unavailable: " .. i .. "/" .. e)
    i, e, a = enables(false)
    ok(i == 1 and e == 1 and a == true, "EQOT's window: Init and Enable once: " .. i .. "/" .. e)
end)

case("EQOT's own Classic set answers cannot-tell under Blizzard's tracker, and still takes writes", function()
    local function read(useBlizzard)
        local t = boot({ classic = true, char = { trackedQuests = { [5] = true } },
                         profile = { general = { useBlizzardTracker = useBlizzard } } })
        t.login()
        local TS = t.ns.modules.TrackedSet
        local before = TS:IsTracked(5)
        TS:Set(6, true)
        return before, t.DB:Char().trackedQuests[6]
    end
    local tracked, wrote = read(true)
    ok(tracked == nil, "Blizzard's tracker: an older Everything Quests hears cannot-tell: " .. tostring(tracked))
    ok(wrote == true, "and a write still lands, so the set is current on the way back")
    tracked = read(false)
    ok(tracked == true, "EQOT's window: the set answers as before: " .. tostring(tracked))
end)

case("auto-track keeps Classic's set and leaves retail's watch list to Blizzard", function()
    local function accept(useBlizzard, classic)
        local t = boot({ real = { "AutoTrack" }, classic = classic, char = { trackedQuests = {} },
                         profile = { general = { useBlizzardTracker = useBlizzard } } })
        local handlers, added = {}, 0
        t.ns.modules.Events = { On = function(_, e, fn) handlers[e] = fn; return true end }
        t.env.C_QuestLog = {
            IsWorldQuest = function() return false end, IsQuestTask = function() return false end,
            GetQuestWatchType = function() return nil end,
            AddQuestWatch = function() added = added + 1 end, RemoveQuestWatch = function() end,
        }
        t.env.Enum = { QuestWatchType = { Manual = 1 } }
        t.login()
        if classic then handlers.QUEST_ACCEPTED("QUEST_ACCEPTED", 3, 77) else handlers.QUEST_ACCEPTED("QUEST_ACCEPTED", 77) end
        return added, t.DB:Char().trackedQuests[77], t.ns.modules.AutoTrack:DebugLine()
    end
    local added, inSet, line = accept(true, true)
    ok(added == 0 and inSet == true, "Classic, Blizzard's tracker: into EQOT's own set, never Blizzard's list")
    ok(line:find("tracked", 1, true) ~= nil, "and /eqot status reports it tracked: " .. tostring(line))
    added, inSet, line = accept(true, false)
    ok(added == 0 and inSet == nil, "retail, Blizzard's tracker: no watch added behind the game's own rules: " .. added)
    ok(line:find("left alone, Blizzard's tracker in use", 1, true) ~= nil,
       "and /eqot status says why: " .. tostring(line))
    added = accept(false, false)
    ok(added == 1, "retail, EQOT's window: the manual watch as before: " .. added)
end)

-- One function sliced out of a file too big to load whole, with its file-locals handed in as globals.
local function sliceFn(rel, header)
    local src = readFile(rel)
    local s = src:find("\n" .. header .. "\n", 1, true)
    assert(s, header .. " not found in " .. rel)
    local e = src:find("\nend\n", s + 1, true)
    return src:sub(s + 1, e + 4)
end

local function runSlice(rel, header, env, retName)
    local chunk = assert(loadstring(sliceFn(rel, header) .. (retName and ("\nreturn " .. retName) or ""), header))
    setfenv(chunk, setmetatable(env, { __index = _G }))
    return chunk()
end

-- The REAL stand-down list, read out of Core/Init.lua, so a slice's ns answers exactly what the
-- shipped ns:IsStandingDown would: only those names, and only in Blizzard's mode.
local REAL_STAND_DOWN = {}
for name in (readFile("Core/Init.lua"):match("\nlocal STAND_DOWN = {(.-)\n}") or ""):gmatch("([%w]+) = true") do
    REAL_STAND_DOWN[name] = true
end

local function standing(mode)
    return { IsStandingDown = function(_, n) return mode == true and REAL_STAND_DOWN[n] == true end,
             UsesBlizzardTracker = function() return mode == true end,
             Print = function() end }
end

case("guards on what the options can still reach", function()
    -- Update and ToggleTest sliced into one HUD, so the Test button's second press reaches the real
    -- Update, which is the only call that takes the test frame down.
    local function hud(mode)
        local rendered, frame = 0, { shown = false }
        function frame:Hide() self.shown = false end
        local env = { ns = standing(mode), enabled = function() return true end,
                      HUD = { _Render = function(self) rendered = rendered + 1; self.frame = frame; frame.shown = true end,
                              _ReleaseRows = function() end } }
        env.ns.GetModule = function() return { GetModel = function() return {} end } end
        runSlice("UI/ScenarioBonusHUD.lua", "function HUD:Update()", env)
        runSlice("UI/ScenarioBonusHUD.lua", "function HUD:ToggleTest()", env)
        env.HUD:Update()
        local before = rendered
        env.HUD:ToggleTest()
        local during = frame.shown
        env.HUD:ToggleTest()
        return ("%d %s %s"):format(before, tostring(during), tostring(frame.shown))
    end
    ok(hud(true) == "0 true false", "Blizzard's tracker: no HUD drawn, the test frame shows and clears: " .. hud(true))
    ok(hud(false) == "1 true true", "EQOT's window: drawn, and the HUD stays after the test: " .. hud(false))

    local function reconcile(mode)
        local armed
        local env = { ns = standing(mode),
                      playerInDelve = function() return true end,
                      setDelveEvents = function(on) armed = on end,
                      Bonus = { Enabled = function() return true end } }
        runSlice("Data/ScenarioBonus.lua", "function Bonus:Reconcile()", env)
        env.Bonus:Reconcile()
        return armed
    end
    ok(reconcile(true) == false, "its delve events stay off while standing down: " .. tostring(reconcile(true)))
    ok(reconcile(false) == true, "and arm as before otherwise")

    local function coexist(mode)
        local looked = 0
        local env = { ns = standing(mode),
                      trackerFrame = function() looked = looked + 1 end,
                      Coexist = {} }
        runSlice("UI/QuestieCoexist.lua", "function Coexist:Apply()", env)
        env.Coexist:Apply()
        return looked
    end
    ok(coexist(true) == 0, "the Questie hider never reaches that tracker while standing down")
    ok(coexist(false) == 1, "and does otherwise")

    local function floating(mode)
        local env = { ns = standing(mode), cfg = function() return { zoneProgressLocation = "tracker" } end }
        return runSlice("UI/ZoneProgressBar.lua", "local function isFloating()", env, "isFloating")()
    end
    ok(floating(true) == true, "a docked zone bar floats while there is no tracker window")
    ok(floating(false) == false, "and stays docked otherwise")
end)

-- ------------------------------------------------------------------------------ seams

local function code(rel)
    local out = {}
    for line in (readFile(rel) .. "\n"):gmatch("([^\n]*)\n") do
        if not line:match("^%s*%-%-") then out[#out + 1] = (line:gsub("%s+%-%-.*$", "")) end
    end
    return "\n" .. table.concat(out, "\n") .. "\n"
end

case("seams", function()
    local init = code("Core/Init.lua")
    local list = init:match("\nlocal STAND_DOWN = {(.-)\n}")
    ok(list ~= nil, "STAND_DOWN is where the seam expects it")
    local names = {}
    for name in (list or ""):gmatch("([%w]+) = true") do names[#names + 1] = name end
    ok(#names == #STOOD_DOWN + 1, "eleven names, ten retail and QuestLogChecks: " .. #names)

    -- The latch is taken in DB:OnInitialize, and Registry and TrackedSet read it in their own
    -- OnInitialize, so DB has to load first in every TOC.
    for _, toc in ipairs({ "EQObjectiveTracker.toc", "EQObjectiveTracker_Mainline.toc",
                           "EQObjectiveTracker_Camelot.toc", "EQObjectiveTracker_Vanilla.toc",
                           "EQObjectiveTracker_TBC.toc" }) do
        local at = {}
        for i, m in ipairs(modulesOf(toc)) do at[m.name] = i end
        ok(at.DB and at.Registry and at.DB < at.Registry, toc .. " loads DB before Registry")
        ok(not at.TrackedSet or at.DB < at.TrackedSet, toc .. " loads DB before TrackedSet")
    end
    local all = {}
    for _, m in ipairs(modulesOf(CLASSIC_TOC)) do all[m.name] = m end
    for _, m in ipairs(modulesOf(RETAIL_TOC)) do all[m.name] = m end
    for _, name in ipairs(names) do
        ok(all[name] ~= nil, name .. " is a module some TOC loads")
        ok(all[name] and all[name].enable, name .. " has an OnEnable, so standing down means something")
    end

    local q = code("Data/Providers/QuestsClassic.lua")
    ok(q:find('\n    Events:On("QUEST_LOG_UPDATE",        logUpdated)\n', 1, true) ~= nil,
       "QUEST_LOG_UPDATE runs the clear-up")
    ok(q:find("\n    local function logUpdated()\n        clearLeftoverWatches()\n        markDynamic()\n    end\n", 1, true) ~= nil,
       "which clears first and still marks the rebuild")
    -- A dropdown pick runs before its list hides, as the dialog's callback does, because picking a
    -- profile reloads.
    ok(code("Options/Frame.lua"):find("\n        b:SetScript(\"OnClick\", function()\n"
        .. "            xpcall(function() onPick(opt.value) end, geterrorhandler())\n"
        .. "            p:Hide()\n        end)\n", 1, true) ~= nil,
       "a dropdown pick runs before the list hides")

    -- The add hook's own case runs a slice of it, so only this proves Enable still installs it.
    local enable = q:match("\n(function Quests:Enable%(notify%).-\nend\n)")
    ok(enable ~= nil and enable:find('\n    if type(AddQuestWatch) == "function" and type(RemoveQuestWatch) == "function" then\n'
                                     .. '        hooksecurefunc("AddQuestWatch", function(index)\n', 1, true) ~= nil,
       "Enable installs the add hook wherever both watch functions exist")
end)

print(("test_blizzard_tracker: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
