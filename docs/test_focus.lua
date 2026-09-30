-- luacheck: globals GetBuildInfo C_SuperTrack
--
-- Unit tests for Data/Focus.lua, run against the SHIPPED source with the SHIPPED Core/API.lua.
-- Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_focus.lua
--
-- Both files load WHOLE. Neither creates a frame, so a table with RegisterModule, GetModule and
-- Has on it, an Events stub that records its handlers, GetBuildInfo and C_SuperTrack are a
-- complete stand-in. The stub calls a handler with the event name first, as Core/Events.lua does,
-- which docs/test_events.lua holds for the real module.
--
-- WHY THIS FILE EXISTS. On WoW Forever the tracker follows quests by super-track, and Everything
-- Quests turns EQOT's focus announcement into a TomTom arrow, as it does on Classic. Focus follows
-- super-track on Forever only, gated on its interface range, and Forever loads the retail file
-- list, so the retail TOCs must list it. Most ways this can fail are silent: no arrow, and nothing
-- on screen to say which addon dropped it.
--
-- THE CASE THAT EARNS IT. Everything Quests registers its listener AFTER EQOT's modules enable,
-- and Focus:Set says nothing when the focus has not changed. A read at enable would store the
-- login's quest where nobody hears it, and the first loading screen would then find nothing to
-- announce. So the Forever cases register their listener after enable, as in game, except one
-- that registers first to prove enable itself announces nothing.
--
-- OUT OF SCOPE BY CONSTRUCTION: whether EQ places the arrow, whether TomTom draws it, and which
-- TOC the Forever client loads. Only what EQOT announces, and when, is measured. The click that
-- resends a followed quest lives in Data/Providers/Quests.lua and docs/test_quest_turnin.lua.

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
end

local function readFile(rel)
    local f = assert(io.open(repoFile(rel), "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end

-- Every block runs under one pcall, so a raise fails that block instead of aborting the run.
local function case(name, fn)
    print("== " .. name)
    local okRun, err = pcall(fn)
    ok(okRun, name .. " ran without raising" .. (okRun and "" or (" - " .. tostring(err))))
end

local superTracked = 0

-- The real GetBuildInfo returns six values and the interface is the FOURTH. Strings follow it on
-- purpose: tonumber(select(4, GetBuildInfo())) without the extra parentheses hands tonumber a base.
local function world(opts)
    GetBuildInfo = function()
        return "1.60.1", "70009", "Sep 24 2026", opts.toc, "1.60.1", "Release x64"
    end
    superTracked = opts.superTracked or 0
    if opts.noSuperTrack then
        C_SuperTrack = nil
    else
        C_SuperTrack = {
            SetSuperTrackedQuestID = function(id)
                if id == nil then error("SetSuperTrackedQuestID: bad argument #1") end
                superTracked = id
            end,
        }
        if not opts.noGet then
            C_SuperTrack.GetSuperTrackedQuestID = function() return superTracked end
        end
    end
end

-- A fresh addon per case. Focus keeps its state in file locals and decides at load whether it
-- follows super-track, so loading again is the only honest reset.
local function fresh(opts)
    world(opts)
    local handlers, registered = {}, {}
    local ns = { modules = {}, Has = { SuperTrack = opts.hasSuperTrack ~= false and not opts.noSuperTrack } }
    function ns:RegisterModule(name, t)
        registered[#registered + 1] = name
        self.modules[name] = t or {}
        return self.modules[name]
    end
    function ns:GetModule(name) return self.modules[name] end
    ns.modules.Events = {
        On = function(_, event, fn)
            handlers[event] = handlers[event] or {}
            handlers[event][#handlers[event] + 1] = fn
            return true
        end,
    }
    assert(loadfile(repoFile("Core/API.lua")))("EQObjectiveTracker", ns)
    assert(loadfile(repoFile("Data/Focus.lua")))("EQObjectiveTracker", ns)

    local t = { ns = ns, API = ns.modules.API, Focus = ns.modules.Focus, handlers = handlers,
                registered = registered, heard = {} }
    function t.enable()
        if t.Focus.OnEnable then t.Focus:OnEnable() end
    end
    -- Registered the way Everything Quests registers it, one string per announcement.
    function t.listen()
        t.API:AddFocusListener({ id = "eq-quest-arrow", onFocus = function(p, e)
            t.heard[#t.heard + 1] = tostring(p) .. ":" .. tostring(e)
        end })
    end
    function t.fire(event, ...)
        for _, fn in ipairs(handlers[event] or {}) do fn(event, ...) end
    end
    function t.count(event)
        return #(handlers[event] or {})
    end
    function t.events()
        local n = 0
        for _, list in pairs(handlers) do n = n + #list end
        return n
    end
    return t
end

local FOREVER, RETAIL, ERA = 16001, 120100, 11509

-- ------------------------------------------------------------------------------- Forever

case("Forever: enabling subscribes to exactly the two events", function()
    local t = fresh({ toc = FOREVER })
    ok(type(t.Focus.OnEnable) == "function", "Focus has an OnEnable on Forever")
    ok(not t.Focus:FollowsSuperTrack(), "and follows nothing until it runs")
    t.enable()
    ok(t.count("SUPER_TRACKING_CHANGED") == 1, "follows a super-track change, once")
    ok(t.count("PLAYER_ENTERING_WORLD") == 1, "reads again at every loading screen, once")
    ok(t.events() == 2, "and subscribes to nothing else: " .. t.events())
    ok(t.Focus:FollowsSuperTrack(), "and says it follows super-track once it has run")
end)

case("Forever: nothing is announced at enable, even to a listener that is already there", function()
    local t = fresh({ toc = FOREVER, superTracked = 1234 })
    t.listen()
    t.enable()
    ok(#t.heard == 0, "enable reads nothing: " .. table.concat(t.heard, " "))
end)

case("Forever: the login's quest reaches a listener registered AFTER enable", function()
    -- The real order. A read at enable stores 1234 with nobody listening, and this loading
    -- screen then finds nothing changed and stays silent.
    local t = fresh({ toc = FOREVER, superTracked = 1234 })
    t.enable()
    t.listen()
    t.fire("PLAYER_ENTERING_WORLD", true, false)
    ok(#t.heard == 1 and t.heard[1] == "quests:1234",
       "the first loading screen announces the followed quest: " .. table.concat(t.heard, " "))
    local p, e = t.API:GetFocus()
    ok(p == "quests" and e == 1234, "and GetFocus answers it: " .. tostring(p) .. ":" .. tostring(e))
end)

case("Forever: a /reload's loading screen announces the followed quest too", function()
    -- The payload a reload carries. SuperTrackPersist returns early on it, and copying that
    -- guard here would leave every reload without an arrow.
    local t = fresh({ toc = FOREVER, superTracked = 1234 })
    t.enable()
    t.listen()
    t.fire("PLAYER_ENTERING_WORLD", false, true)
    ok(t.heard[1] == "quests:1234", "the reload payload announces: " .. table.concat(t.heard, " "))
end)

case("Forever: a loading screen with the same quest announces nothing", function()
    local t = fresh({ toc = FOREVER, superTracked = 1234 })
    t.enable()
    t.listen()
    t.fire("PLAYER_ENTERING_WORLD", true, false)
    t.fire("PLAYER_ENTERING_WORLD", false, false)
    ok(#t.heard == 1, "a zone change repeats nothing: " .. table.concat(t.heard, " "))
end)

case("Forever: every loading screen reads again, so a change it missed is caught there", function()
    local t = fresh({ toc = FOREVER, superTracked = 1234 })
    t.enable()
    t.listen()
    t.fire("PLAYER_ENTERING_WORLD", true, false)
    superTracked = 5678
    t.fire("PLAYER_ENTERING_WORLD", false, false)
    ok(t.heard[2] == "quests:5678", "the zone change announces it: " .. table.concat(t.heard, " "))
end)

case("Forever: following another quest announces it, and stopping announces a clear", function()
    local t = fresh({ toc = FOREVER, superTracked = 0 })
    t.enable()
    t.listen()
    t.fire("PLAYER_ENTERING_WORLD", true, false)
    ok(#t.heard == 0, "nothing followed at login, nothing announced: " .. table.concat(t.heard, " "))

    C_SuperTrack.SetSuperTrackedQuestID(5678)
    t.fire("SUPER_TRACKING_CHANGED")
    ok(t.heard[1] == "quests:5678", "a click on a row reaches the listener: " .. tostring(t.heard[1]))

    C_SuperTrack.SetSuperTrackedQuestID(91723)
    t.fire("SUPER_TRACKING_CHANGED")
    ok(t.heard[2] == "quests:91723", "and so does a switch to another quest: " .. tostring(t.heard[2]))

    C_SuperTrack.SetSuperTrackedQuestID(0)
    t.fire("SUPER_TRACKING_CHANGED")
    ok(t.heard[3] == "quests:nil",
       "0 is a clear, announced against the provider that lost it: " .. tostring(t.heard[3]))
    local p, e = t.API:GetFocus()
    ok(p == nil and e == nil, "and GetFocus is empty again: " .. tostring(p) .. ":" .. tostring(e))

    t.fire("SUPER_TRACKING_CHANGED")
    ok(#t.heard == 3, "a second clear says nothing: " .. table.concat(t.heard, " "))
end)

case("Forever: the handlers read super-track and never write it", function()
    local t = fresh({ toc = FOREVER, superTracked = 1234 })
    local writes = 0
    local set = C_SuperTrack.SetSuperTrackedQuestID
    C_SuperTrack.SetSuperTrackedQuestID = function(id) writes = writes + 1 return set(id) end
    t.enable()
    t.listen()
    t.fire("PLAYER_ENTERING_WORLD", true, false)
    t.fire("SUPER_TRACKING_CHANGED")
    ok(writes == 0, "no write back: " .. writes)
end)

case("Forever: a nil read is a clear, never a raise", function()
    local t = fresh({ toc = FOREVER, superTracked = 42 })
    t.enable()
    t.listen()
    t.fire("PLAYER_ENTERING_WORLD", true, false)
    superTracked = nil
    t.fire("SUPER_TRACKING_CHANGED")
    ok(t.heard[2] == "quests:nil", "nil clears: " .. table.concat(t.heard, " "))
end)

case("Forever: a negative id is not a quest either", function()
    local t = fresh({ toc = FOREVER, superTracked = 42 })
    t.enable()
    t.listen()
    t.fire("PLAYER_ENTERING_WORLD", true, false)
    superTracked = -1
    t.fire("SUPER_TRACKING_CHANGED")
    ok(t.heard[2] == "quests:nil", "-1 clears: " .. table.concat(t.heard, " "))
end)

case("Forever: Resend repeats the followed quest, and only that", function()
    local t = fresh({ toc = FOREVER, superTracked = 1234 })
    t.enable()
    t.listen()
    local dirty = 0
    t.Focus:OnDirty(function() dirty = dirty + 1 end)
    t.Focus:Resend()
    ok(#t.heard == 0, "with nothing read yet there is nothing to resend: " .. table.concat(t.heard, " "))
    t.fire("PLAYER_ENTERING_WORLD", true, false)
    t.Focus:Resend()
    ok(#t.heard == 2 and t.heard[2] == "quests:1234",
       "the followed quest is announced again: " .. table.concat(t.heard, " "))
    ok(dirty == 1, "without asking for another repaint: " .. dirty)
    local p, e = t.API:GetFocus()
    ok(p == "quests" and e == 1234, "and the focus itself is unchanged: " .. tostring(p) .. ":" .. tostring(e))
    C_SuperTrack.SetSuperTrackedQuestID(0)
    t.fire("SUPER_TRACKING_CHANGED")
    t.Focus:Resend()
    ok(#t.heard == 3, "after a clear there is nothing to resend: " .. table.concat(t.heard, " "))
end)

case("Forever: the interface range is the packager's 16xxx, both edges", function()
    for _, row in ipairs({ { 15999, 0 }, { 16000, 2 }, { 16999, 2 }, { 17000, 0 } }) do
        local t = fresh({ toc = row[1] })
        t.enable()
        ok(t.events() == row[2], ("interface %d subscribes %d events: %d"):format(row[1], row[2], t.events()))
    end
end)

case("a build info with no interface number stays silent rather than raising", function()
    local t = fresh({ toc = nil })
    ok(t.Focus.OnEnable == nil, "no OnEnable is defined")
    t.enable()
    ok(t.events() == 0, "nothing subscribed: " .. t.events())
end)

case("Forever: a client with no super-track getter stays silent rather than raising", function()
    local t = fresh({ toc = FOREVER, noGet = true })
    ok(t.Focus.OnEnable == nil, "no OnEnable is defined")
    t.enable()
    ok(t.events() == 0, "nothing subscribed: " .. t.events())
end)

case("Forever: a client where Has.SuperTrack reads false stays silent", function()
    local t = fresh({ toc = FOREVER, hasSuperTrack = false })
    ok(t.Focus.OnEnable == nil, "no OnEnable is defined")
    t.enable()
    ok(t.events() == 0, "nothing subscribed: " .. t.events())
end)

case("the status line says whether Focus follows super-track, whole", function()
    local t = fresh({ toc = FOREVER, superTracked = 1234 })
    t.listen()
    ok(t.API:DebugLine() == "api: 0 header icon(s), 0 menu item(s), 1 focus listener(s) | focus nil:nil",
       "before enable it follows nothing: " .. t.API:DebugLine())
    t.enable()
    t.fire("PLAYER_ENTERING_WORLD", true, false)
    local want = "api: 0 header icon(s), 0 menu item(s), 1 focus listener(s) | focus quests:1234, "
        .. "follows super-track"
    ok(t.API:DebugLine() == want, "on Forever it names the quest and says so: " .. t.API:DebugLine())

    local r = fresh({ toc = RETAIL })
    r.enable()
    ok(r.API:DebugLine() == "api: 0 header icon(s), 0 menu item(s), 0 focus listener(s) | focus nil:nil",
       "retail says nothing about super-track: " .. r.API:DebugLine())
end)

-- ------------------------------------------------------------------------ retail and Classic

case("retail: Focus loads with no OnEnable, subscribes to nothing and never announces", function()
    local t = fresh({ toc = RETAIL, superTracked = 1234 })
    ok(t.Focus.OnEnable == nil, "no OnEnable, so /eqot modules does not offer it")
    t.enable()
    t.listen()
    ok(t.events() == 0, "no event on retail: " .. t.events())
    t.fire("PLAYER_ENTERING_WORLD", true, false)
    t.fire("SUPER_TRACKING_CHANGED")
    t.Focus:Resend()
    ok(#t.heard == 0, "a retail listener is never called: " .. table.concat(t.heard, " "))
    local p, e = t.API:GetFocus()
    ok(p == nil and e == nil, "and GetFocus stays empty there: " .. tostring(p) .. ":" .. tostring(e))
    ok(not t.Focus:FollowsSuperTrack(), "and it does not follow super-track")
end)

case("Classic Era: no C_SuperTrack at all, no OnEnable, no raise", function()
    local t = fresh({ toc = ERA, noSuperTrack = true })
    ok(t.Focus.OnEnable == nil, "no OnEnable, so /eqot modules does not offer it")
    t.enable()
    ok(t.events() == 0, "no event on Era: " .. t.events())
end)

case("Classic: a click sets focus and a second click clears it, announced both times", function()
    local t = fresh({ toc = ERA, noSuperTrack = true })
    t.enable()
    t.listen()
    local dirty = 0
    t.Focus:OnDirty(function() dirty = dirty + 1 end)

    ok(not t.Focus:Is(nil, nil), "an empty focus is not a focus on nothing")
    ok(t.Focus:Toggle("quests", 7) == true, "the first click reports a change")
    ok(t.heard[1] == "quests:7", "and announces the quest: " .. tostring(t.heard[1]))
    ok(t.Focus:Is("quests", 7), "and Is agrees")
    ok(dirty == 1, "and asks for one repaint: " .. dirty)

    ok(t.Focus:Set("quests", 7) == false, "setting the same focus again reports no change")
    ok(#t.heard == 1 and dirty == 1, "and neither announces nor repaints")
    t.Focus:Resend()
    ok(#t.heard == 1, "and Classic resends nothing, since a second click clears instead")

    ok(t.Focus:Toggle("quests", 7) == true, "the second click reports a change")
    ok(t.heard[2] == "quests:nil", "and announces the clear against quests: " .. tostring(t.heard[2]))
    ok(not t.Focus:Is("quests", 7), "and Is agrees")

    ok(t.Focus:Set(nil, nil) == false, "clearing an empty focus reports no change")
    ok(t.Focus:Set("quests", nil) == false, "nor does a provider with no entry")
    ok(#t.heard == 2 and dirty == 2, "and neither announces: " .. table.concat(t.heard, " "))
end)

case("two providers never share a focus", function()
    local t = fresh({ toc = ERA, noSuperTrack = true })
    t.listen()
    t.Focus:Set("quests", 7)
    ok(t.Focus:Set("worldquests", 7) == true, "the same id under another provider is a change")
    ok(t.heard[2] == "worldquests:7", "announced under the new provider: " .. tostring(t.heard[2]))
    ok(not t.Focus:Is("quests", 7), "and quests no longer owns it")
    ok(t.Focus:Toggle("quests", 7) == true and t.Focus:Is("quests", 7),
       "a toggle from another provider takes focus rather than clearing it")
    t.Focus:Set("worldquests", 9)
    t.Focus:Set(nil, nil)
    ok(t.heard[#t.heard] == "worldquests:nil",
       "a clear names the provider that lost focus: " .. tostring(t.heard[#t.heard]))
end)

case("every listener hears it once, past a raise and a listener that removes itself", function()
    local t = fresh({ toc = ERA, noSuperTrack = true })
    local dirty, a, b, inside, inDirty = 0, {}, {}, {}, nil
    t.Focus:OnDirty(function() dirty = dirty + 1 local _, e = t.Focus:Get() inDirty = e end)
    t.Focus:OnDirty(function() dirty = dirty + 10 end)
    t.API:AddFocusListener({ id = "once", onFocus = function() t.API:RemoveFocusListener("once") end })
    t.API:AddFocusListener({ id = "a", onFocus = function(p, e) a[#a + 1] = tostring(p) .. ":" .. tostring(e) end })
    t.API:AddFocusListener({ id = "boom", onFocus = function() error("listener bug") end })
    local function recordB(p, e)
        b[#b + 1] = tostring(p) .. ":" .. tostring(e)
        local gp, ge = t.API:GetFocus()
        inside[#inside + 1] = tostring(gp) .. ":" .. tostring(ge)
    end
    t.API:AddFocusListener({ id = "b", onFocus = recordB })
    ok(t.API:AddFocusListener({ id = "b", onFocus = recordB }) == true,
       "re-registering an id reports success")
    ok(t.API:AddFocusListener({ id = "bad" }) == false, "a spec with no onFocus is refused")
    t.Focus:Set("quests", 7)
    ok(a[1] == "quests:7" and b[1] == "quests:7" and #a == 1 and #b == 1,
       "every listener hears it once despite the raise: " .. table.concat(a, " ") .. " | " .. table.concat(b, " "))
    ok(inside[1] == "quests:7", "GetFocus inside the callback reads the new focus: " .. tostring(inside[1]))
    ok(dirty == 11, "and every repaint handler runs: " .. dirty)
    ok(inDirty == 7, "and the repaint reads the new focus: " .. tostring(inDirty))
    ok(#t.API.focusListeners == 3, "the one-shot listener removed itself: " .. #t.API.focusListeners)
    t.API:RemoveFocusListener("a")
    t.Focus:Set(nil, nil)
    ok(#a == 1, "a removed listener hears nothing more: " .. #a)
end)

-- --------------------------------------------------------------------------------- seams

case("seams: the module name, the provider id and every TOC", function()
    local t = fresh({ toc = RETAIL })
    local named = 0
    for _, n in ipairs(t.registered) do if n == "Focus" then named = named + 1 end end
    ok(named == 1, "Data/Focus.lua registers the module API:GetFocus reads, once: " .. named)

    -- Everything Quests drops any announcement whose provider is not exactly "quests".
    for _, rel in ipairs({ "Data/Providers/Quests.lua", "Data/Providers/QuestsClassic.lua" }) do
        ok(readFile(rel):find('\n    id       = "quests",\n', 1, true) ~= nil,
           rel .. " still declares the id Focus announces under")
    end

    -- Counted line by line. A single pattern over the file consumes the newline two adjacent
    -- copies share, and a duplicate raises "already registered" at every login.
    local function lines(toc)
        local out = {}
        for line in (readFile(toc):gsub("\r\n", "\n") .. "\n"):gmatch("([^\n]*)\n") do
            out[#out + 1] = line
        end
        return out
    end
    for _, toc in ipairs({ "EQObjectiveTracker.toc", "EQObjectiveTracker_Mainline.toc",
                           "EQObjectiveTracker_Camelot.toc", "EQObjectiveTracker_Vanilla.toc",
                           "EQObjectiveTracker_TBC.toc" }) do
        local n, focusAt, classicAt = 0, nil, nil
        for i, line in ipairs(lines(toc)) do
            if line == "Data\\Focus.lua" then n = n + 1 focusAt = focusAt or i end
            if line == "Data\\Providers\\QuestsClassic.lua" then classicAt = i end
        end
        ok(n == 1, toc .. " lists Data\\Focus.lua exactly once: " .. n)
        -- QuestsClassic captures the module when its file loads.
        if classicAt then
            ok(focusAt ~= nil and focusAt < classicAt, toc .. " lists Focus before QuestsClassic")
        end
    end
end)

print(("test_focus: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
