-- Unit tests for the two focus options on the Tracker tab, run against the SHIPPED source. Run
-- from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_unfocus.lua
--
-- WHY THIS FILE EXISTS. A WoW Forever player asked on CurseForge (2026-10-04) for a plain click to
-- unfocus a quest, and for the quests he accepts to stop being focused on their own, because each
-- focus moves his TomTom arrow. The game does that second part itself: Blizzard_FrameXMLUtil's
-- QuestUtils.lua focuses a quest accepted while nothing is focused, whichever tracker is showing.
-- Its one other caller is a click on a world quest's map pin, forced, which is the player's own
-- choice. Both options are retail and Forever only.
--
-- WHAT IS HELD HERE. Data/SuperTrackPersist.lua loads WHOLE over a copy of Blizzard's two
-- functions written out from that file (read on the live and forever branches, 2026-10-04): Check
-- asks Allow THROUGH THE TABLE, Allow answers yes only while nothing is focused and refuses a world
-- quest or bonus objective unless forced, and Check then sets the focus. With Focus newly accepted
-- quests off, only a focus the game just put on that quest from nothing is taken back: never one
-- the player already had, on that quest or any other, never a map pin, and never the forced ask a
-- world quest pin click makes. The option is read at every accept.
-- A later client that stops asking Allow through the table loses the option rather than clearing
-- a focus it cannot place. The login restore, the status line and the world quest row's click
-- (sliced) are here too. The quest row's click is in docs/test_quest_turnin.lua and the two boxes
-- in docs/test_tracker_tab.lua.
--
-- The DB module is Core/DB.lua's own accessors, sliced, over a stub profile, so a call written
-- DB.Tracker() raises here as it does in game. The saved tracker AND general settings carry their
-- other keys set both ways, so an option that reads a neighbor's key fails, and Classic is
-- Has.SuperTrack false, as Core/Compat.lua sets it, never nil.
--
-- OUT OF SCOPE BY CONSTRUCTION: whether the real client fires SUPER_TRACKING_CHANGED inside the
-- set or after it, which decides whether Everything Quests' arrow flashes for an instant before the
-- focus is taken back. Only an in-game look can tell. Blizzard's own focus clears, such as
-- OnQuestWatchChanged and OnQuestTurnedIn, are not modeled either.

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
end

local function readFile(rel)
    local fh = assert(io.open(repoFile(rel), "rb"))
    local src = fh:read("*a")
    fh:close()
    return (src:gsub("\r\n", "\n"))
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

local function count(src, needle)
    local n, from = 0, 1
    while true do
        local i = src:find(needle, from, true)
        if not i then return n end
        n, from = n + 1, i + 1
    end
end

local function stripComments(src)
    src = src:gsub("%-%-%[(=*)%[.-%]%1%]", "")
    return (src:gsub("%-%-[^\n]*", ""))
end

local function pack(...) return { n = select("#", ...), ... } end

-- Core/DB.lua's accessors, sliced once. Each reads through self, so a dot call raises.
local accessors
local function realDB(profile)
    if not accessors then
        local src = readFile("Core/DB.lua")
        accessors = {}
        for _, name in ipairs({ "Tracker", "General" }) do
            local head = "\nfunction DB:" .. name .. "()\n"
            local a = src:find(head, 1, true)
            local b = a and src:find("\nend\n", a + 1, true)
            assert(a and b and not src:find(head, a + 1, true), "Core/DB.lua defines DB:" .. name .. " once")
            local holder = {}
            local chunk = assert(loadstring(src:sub(a + 1, b + 4), "DB:" .. name))
            setfenv(chunk, { DB = holder })
            chunk()
            accessors[name] = holder[name]
        end
    end
    local db = { db = { profile = profile } }
    for name, fn in pairs(accessors) do db[name] = fn end
    return db
end

-- A set of the saved keys the two options sit beside, all real keys of Core/DB.lua, set to v,
-- leaving own and any key already there alone. neighbors fills the tracker table, generals the
-- general one.
local NEIGHBORS = { "clickToUnfocus", "focusAcceptedQuests", "splitQuestClick", "showOnlyWatched",
                    "simplifyMode", "trackerAlphaFocus", "trackerAlphaHover" }
local GENERAL_NEIGHBORS = { "autoTrackAccepted", "restoreSuperTrackOnLogin", "useBlizzardTracker" }
local function neighbors(cfg, own, v)
    for _, k in ipairs(NEIGHBORS) do
        if k ~= own and cfg[k] == nil then cfg[k] = v end
    end
    return cfg
end
local function generals(gen, v)
    for _, k in ipairs(GENERAL_NEIGHBORS) do
        if gen[k] == nil then gen[k] = v end
    end
    return gen
end

-- --------------------------------------------------------------------------- the world

-- o.cfg is the saved tracker settings, o.gen the general ones, o.focused the quest the client
-- follows (0 for none), o.pin a map pin or other content followed instead, o.worldQuest the quest
-- ids Blizzard counts as world quests or bonus objectives, o.has false for a client with no
-- super-track, and o.no names client functions to leave out.
local function fresh(o)
    o = o or {}
    local no = o.no or {}
    local st = { cfg = o.cfg or {}, gen = o.gen or {}, focused = o.focused or 0, pin = o.pin or false,
                 worldQuest = o.worldQuest or {}, sets = {}, hooks = {}, timers = {}, handlers = {},
                 skipAllow = false }

    -- The client's set RAISES on a nil id, as the real one does.
    local C = {
        SetSuperTrackedQuestID = function(id)
            if id == nil then error("SetSuperTrackedQuestID: bad argument #1 (nil)", 2) end
            st.sets[#st.sets + 1] = id
            st.focused = id
            if id ~= 0 then st.pin = false end
        end,
        GetSuperTrackedQuestID = function() return st.focused end,
        IsSuperTrackingAnything = function() return st.focused ~= 0 or st.pin end,
    }
    if no.IsSuperTrackingAnything then C.IsSuperTrackingAnything = nil end
    if no.GetSuperTrackedQuestID then C.GetSuperTrackedQuestID = nil end

    -- Blizzard's own pair. Check reads Allow off the table at call time, which is the lookup the
    -- hooks depend on. skipAllow stands in for a later client that answers inline instead.
    local QU = {}
    function QU.AllowAutoSuperTrackQuest(questID, forceAllowTasks)
        if not C.IsSuperTrackingAnything() then
            if not forceAllowTasks then
                return not st.worldQuest[questID]
            end
            return true
        end
        return false
    end
    function QU.CheckAutoSuperTrackQuest(questID, forceAllowTasks)
        local allowed
        if st.skipAllow then
            allowed = not C.IsSuperTrackingAnything()
        else
            allowed = QU.AllowAutoSuperTrackQuest(questID, forceAllowTasks)
        end
        if allowed then C.SetSuperTrackedQuestID(questID) end
    end
    if no.AllowAutoSuperTrackQuest then QU.AllowAutoSuperTrackQuest = nil end
    if no.CheckAutoSuperTrackQuest then QU.CheckAutoSuperTrackQuest = nil end
    st.original = { Allow = QU.AllowAutoSuperTrackQuest, Check = QU.CheckAutoSuperTrackQuest }

    -- The real one runs the original first, then calls the hook with the same arguments, and hands
    -- back the original's answers.
    local function hooksecurefunc(t, key, hook)
        if type(t[key]) ~= "function" then error("hooksecurefunc: " .. tostring(key) .. " is not a function", 2) end
        st.hooks[#st.hooks + 1] = key
        local orig = t[key]
        t[key] = function(...)
            local res = pack(orig(...))
            hook(...)
            return unpack(res, 1, res.n)
        end
    end

    local modules = {}
    local ns = { Has = { SuperTrack = o.has ~= false } }
    function ns:RegisterModule(name, t)
        modules[name] = t or {}
        return modules[name]
    end
    function ns:GetModule(name) return modules[name] end
    modules.DB = realDB({ tracker = st.cfg, general = st.gen })
    modules.Events = { On = function(_, event, fn) st.handlers[event] = fn return true end }

    local env = setmetatable({
        C_SuperTrack = C,
        QuestUtil = (not no.QuestUtil) and QU or nil,
        hooksecurefunc = hooksecurefunc,
        C_Timer = { After = function(delay, fn) st.timers[#st.timers + 1] = { delay = delay, fn = fn } end },
    }, { __index = _G })
    local chunk = assert(loadfile(repoFile("Data/SuperTrackPersist.lua")))
    setfenv(chunk, env)
    chunk("EQObjectiveTracker", ns)

    st.mod, st.QU, st.C, st.modules, st.ns = modules.SuperTrackPersist, QU, C, modules, ns
    function st.enable() st.mod:OnEnable() end
    -- What Blizzard's QUEST_ACCEPTED handler does: drop a followed quest giver's pin, then ask.
    function st.accept(questID, offerPin)
        if offerPin then st.pin = false end
        QU.CheckAutoSuperTrackQuest(questID)
    end
    -- A click on a world quest's map pin: TrackWorldQuest's automatic watch asks forced, then the
    -- pin sets the focus itself (WorldQuestDataProvider.lua).
    function st.pinClick(questID)
        QU.CheckAutoSuperTrackQuest(questID, true)
        C.SetSuperTrackedQuestID(questID)
    end
    function st.line()
        local okLine, line = pcall(st.mod.DebugLine, st.mod)
        ok(okLine, "DebugLine does not raise" .. (okLine and "" or (" - " .. tostring(line))))
        return okLine and line or nil
    end
    return st
end

local function sets(st) return table.concat(st.sets, ",") end

local LINE = "focus: a click on the focused quest %s | newly accepted quests %s | game auto-focus %s,"
             .. " asked %d, %d with nothing focused, %d taken back (last %s)"

-- ------------------------------------------------------------------- installing the hooks

case("the hooks go on at enable, on a client with super-track", function()
    local st = fresh()
    ok(#st.hooks == 0, "nothing is hooked at load")
    st.enable()
    ok(table.concat(st.hooks, ",") == "AllowAutoSuperTrackQuest,CheckAutoSuperTrackQuest",
       "enable hooks Allow and Check, once each: " .. table.concat(st.hooks, ","))
    ok(type(st.handlers.PLAYER_ENTERING_WORLD) == "function", "the login restore is still registered")
end)

-- fresh builds Has.SuperTrack as false here, as Core/Compat.lua does, never nil.
case("no client without super-track is hooked, and it reports nothing", function()
    local st = fresh({ has = false })
    st.enable()
    ok(#st.hooks == 0, "nothing is hooked")
    ok(st.handlers.PLAYER_ENTERING_WORLD == nil, "and the login restore is not registered either")
    ok(st.line() == nil, "the status line has nothing to say there")
end)

case("a missing piece of Blizzard's pair leaves both unhooked", function()
    -- One hook without the other would arm and never spend, or spend what was never armed.
    for _, missing in ipairs({ "QuestUtil", "AllowAutoSuperTrackQuest", "CheckAutoSuperTrackQuest",
                               "IsSuperTrackingAnything", "GetSuperTrackedQuestID" }) do
        local st = fresh({ no = { [missing] = true } })
        local okRun, err = pcall(st.enable)
        ok(okRun, "enable does not raise without " .. missing .. (okRun and "" or (" - " .. tostring(err))))
        ok(#st.hooks == 0, "without " .. missing .. " nothing is hooked: " .. table.concat(st.hooks, ","))
        ok(type(st.handlers.PLAYER_ENTERING_WORLD) == "function", "without " .. missing .. " the login restore still runs")
        local line = st.line()
        ok(line and line:find("game auto-focus NOT HOOKED,", 1, true) ~= nil,
           "and the status line says so without " .. missing .. ": " .. tostring(line))
    end
end)

-- ---------------------------------------------------------------- the game's focus on accept

case("with Focus newly accepted quests on, the game's focus on a new quest stays", function()
    for _, value in ipairs({ "unset", true }) do
        local st = fresh({ cfg = value == true and { focusAcceptedQuests = true } or {} })
        st.enable()
        st.accept(101)
        ok(sets(st) == "101" and st.focused == 101,
           "saved " .. tostring(value) .. ", the accepted quest is focused and left so: " .. sets(st))
    end
end)

case("with it off, the focus the game just put on a new quest is taken back", function()
    local st = fresh({ cfg = { focusAcceptedQuests = false } })
    st.enable()
    st.accept(101)
    ok(sets(st) == "101,0" and st.focused == 0, "the game focuses it, then it is taken back: " .. sets(st))
    st.accept(102)
    ok(sets(st) == "101,0,102,0" and st.focused == 0, "and the next one the same way: " .. sets(st))
    ok(st.line() == LINE:format("keeps it", "left unfocused", "hooked", 2, 2, 2, "102"),
       "the status line counts both: " .. tostring(st.line()))
end)

case("a click on a world quest's map pin is the player's choice, never taken back", function()
    local st = fresh({ cfg = { focusAcceptedQuests = false }, worldQuest = { [301] = true } })
    st.enable()
    st.pinClick(301)
    ok(sets(st) == "301,301" and st.focused == 301,
       "the forced ask focuses it and the pin sets it again, with no clear between: " .. sets(st))
    ok(st.line() == LINE:format("keeps it", "left unfocused", "hooked", 1, 0, 0, "nil"),
       "asked once, never armed, nothing taken back: " .. tostring(st.line()))
end)

case("a quest giver's pin dropped on accept leaves nothing followed, so the game's focus is taken back", function()
    local st = fresh({ cfg = { focusAcceptedQuests = false }, pin = true })
    st.enable()
    st.accept(103, true)
    ok(sets(st) == "103,0" and st.focused == 0, "the quest the pin led to is not kept: " .. sets(st))
end)

case("with it off, a focus the player already had is never touched", function()
    local st = fresh({ cfg = { focusAcceptedQuests = false }, focused = 55 })
    st.enable()
    st.accept(101)
    ok(sets(st) == "" and st.focused == 55, "another quest followed: nothing is set at all: " .. sets(st))

    st = fresh({ cfg = { focusAcceptedQuests = false }, pin = true })
    st.enable()
    st.accept(101)
    ok(sets(st) == "" and st.pin == true, "a map pin followed: nothing is set and the pin stays: " .. sets(st))
    -- The client follows no quest here, so only the status line can tell the pin was seen.
    ok(st.line() == LINE:format("keeps it", "left unfocused", "hooked", 1, 0, 0, "nil"),
       "a followed pin counts as something focused, so nothing is armed: " .. tostring(st.line()))

    -- The case the arm exists for: the player followed this world quest from the map, then walked
    -- into it, which accepts it. The game asks on that accept, finds it followed and sets nothing,
    -- so the quest IS followed after the check, and only the arm says it was the player's.
    st = fresh({ cfg = { focusAcceptedQuests = false }, focused = 300, worldQuest = { [300] = true } })
    st.enable()
    st.accept(300)
    ok(sets(st) == "" and st.focused == 300, "the world quest the player followed stays followed: " .. sets(st))
    ok(st.line() == LINE:format("keeps it", "left unfocused", "hooked", 1, 0, 0, "nil"),
       "asked once, nothing focused before it never, nothing taken back: " .. tostring(st.line()))
end)

case("a quest the game declines to focus is left alone, with no clear sent", function()
    local st = fresh({ cfg = { focusAcceptedQuests = false }, worldQuest = { [400] = true } })
    st.enable()
    st.accept(400)
    ok(sets(st) == "" and st.focused == 0, "an accepted world quest is not focused, and nothing is cleared: " .. sets(st))
    ok(st.line() == LINE:format("keeps it", "left unfocused", "hooked", 1, 1, 0, "nil"),
       "counted as asked with nothing focused, not as taken back: " .. tostring(st.line()))
end)

case("the option is read at every accept, so a change applies at once", function()
    local st = fresh({ cfg = { focusAcceptedQuests = false } })
    st.enable()
    st.accept(101)
    ok(st.focused == 0, "off: taken back")
    st.cfg.focusAcceptedQuests = true
    st.accept(102)
    ok(st.focused == 102 and sets(st) == "101,0,102", "turned on: the next one stays: " .. sets(st))
    st.C.SetSuperTrackedQuestID(0)
    st.cfg.focusAcceptedQuests = false
    st.accept(103)
    ok(st.focused == 0 and sets(st) == "101,0,102,0,103,0", "turned off again: taken back again: " .. sets(st))
end)

case("no DB profile reads as on, the game's own behavior", function()
    local st = fresh()
    st.modules.DB.db.profile.tracker = nil
    st.enable()
    st.accept(101)
    ok(sets(st) == "101" and st.focused == 101, "with no saved settings the focus stays: " .. sets(st))
    ok(st.line() == LINE:format("keeps it", "focused", "hooked", 1, 1, 0, "nil"),
       "and the status line reads the defaults: " .. tostring(st.line()))
    st.modules.DB = nil
    st.C.SetSuperTrackedQuestID(0)
    st.accept(102)
    ok(st.focused == 102, "and with no DB module at all")
    ok(st.line() == LINE:format("keeps it", "focused", "hooked", 2, 2, 0, "nil"),
       "where the status line reads the defaults too: " .. tostring(st.line()))

    st = fresh({ cfg = { focusAcceptedQuests = false } })
    st.modules.DB.db = nil
    st.enable()
    st.accept(103)
    ok(sets(st) == "103" and st.focused == 103, "and with a DB module whose profile is not loaded yet: " .. sets(st))
end)

case("Focus newly accepted quests reads its own key, whatever its neighbors hold", function()
    for _, v in ipairs({ true, false }) do
        local st = fresh({ cfg = neighbors({}, "focusAcceptedQuests", v), gen = generals({}, v) })
        st.enable()
        st.accept(101)
        ok(sets(st) == "101" and st.focused == 101,
           "unset beside neighbors all " .. tostring(v) .. ", the focus stays: " .. sets(st))
        ok(st.line() == LINE:format(v and "unfocuses it" or "keeps it", "focused", "hooked", 1, 1, 0, "nil"),
           "and the status line says focused: " .. tostring(st.line()))

        st = fresh({ cfg = neighbors({ focusAcceptedQuests = false }, nil, v), gen = generals({}, v) })
        st.enable()
        st.accept(101)
        ok(sets(st) == "101,0" and st.focused == 0,
           "off beside neighbors all " .. tostring(v) .. ", it is taken back: " .. sets(st))
        ok(st.line() == LINE:format(v and "unfocuses it" or "keeps it", "left unfocused", "hooked", 1, 1, 1, "101"),
           "and the status line says left unfocused: " .. tostring(st.line()))
    end
end)

case("the status line's click field reads its own key, whatever its neighbors hold", function()
    for _, v in ipairs({ true, false }) do
        local st = fresh({ cfg = neighbors({}, "clickToUnfocus", v), gen = generals({}, v) })
        st.enable()
        ok(st.line() == LINE:format("keeps it", v and "focused" or "left unfocused", "hooked", 0, 0, 0, "nil"),
           "unset beside neighbors all " .. tostring(v) .. ": " .. tostring(st.line()))
        st = fresh({ cfg = neighbors({ clickToUnfocus = true }, nil, v), gen = generals({}, v) })
        st.enable()
        ok(st.line() == LINE:format("unfocuses it", v and "focused" or "left unfocused", "hooked", 0, 0, 0, "nil"),
           "on beside neighbors all " .. tostring(v) .. ": " .. tostring(st.line()))
    end
end)

case("a repeatable quest accepted again is taken back again", function()
    local st = fresh({ cfg = { focusAcceptedQuests = false } })
    st.enable()
    st.accept(101)
    st.accept(101)
    ok(sets(st) == "101,0,101,0" and st.focused == 0, "the same quest twice, taken back twice: " .. sets(st))
    ok(st.line() == LINE:format("keeps it", "left unfocused", "hooked", 2, 2, 2, "101"),
       "and counted twice: " .. tostring(st.line()))
end)

case("a loading screen never hooks the pair again", function()
    for _, restore in ipairs({ true, false }) do
        local st = fresh({ cfg = { focusAcceptedQuests = false }, gen = { restoreSuperTrackOnLogin = restore } })
        st.enable()
        for _, p in ipairs({ { true, false }, { false, true }, { false, false } }) do
            st.handlers.PLAYER_ENTERING_WORLD("PLAYER_ENTERING_WORLD", p[1], p[2])
        end
        ok(#st.hooks == 2, "after a login, a reload and a zone change, still two hooks: " .. table.concat(st.hooks, ","))
        st.accept(101)
        ok(sets(st) == "101,0", "one accept is taken back once: " .. sets(st))
        ok(st.line() == LINE:format("keeps it", "left unfocused", "hooked", 1, 1, 1, "101"),
           "and asked once: " .. tostring(st.line()))
    end
end)

-- ----------------------------------------------------------------- the arm and its spending

case("an arm from a check that never came is dropped by the next ask", function()
    local st = fresh({ cfg = { focusAcceptedQuests = false } })
    st.enable()
    st.QU.AllowAutoSuperTrackQuest(9)
    st.C.SetSuperTrackedQuestID(9)
    st.accept(9)
    ok(st.focused == 9 and sets(st) == "9", "the player's own focus on that quest survives the next accept: " .. sets(st))
    -- Counted at the check, so the ask that never had one is not a focus from nothing.
    ok(st.line() == LINE:format("keeps it", "left unfocused", "hooked", 1, 0, 0, "nil"),
       "one check, none with nothing focused: " .. tostring(st.line()))

    -- The forced ask drops the stale arm too, or the pin's own focus is taken back.
    st = fresh({ cfg = { focusAcceptedQuests = false }, worldQuest = { [301] = true } })
    st.enable()
    st.QU.AllowAutoSuperTrackQuest(301)
    st.pinClick(301)
    ok(sets(st) == "301,301" and st.focused == 301,
       "a pin click on the quest a stray ask armed is never taken back: " .. sets(st))
    ok(st.line() == LINE:format("keeps it", "left unfocused", "hooked", 1, 0, 0, "nil"),
       "and nothing is counted as taken back: " .. tostring(st.line()))
end)

case("an arm is spent on the check it belongs to", function()
    local st = fresh({ cfg = { focusAcceptedQuests = false } })
    st.enable()
    st.accept(101)
    ok(st.focused == 0, "the first accept is taken back")
    st.skipAllow = true
    st.C.SetSuperTrackedQuestID(101)
    st.accept(101)
    ok(st.focused == 101 and sets(st) == "101,0,101",
       "a later check with no ask of its own finds no arm, so the player's focus stays: " .. sets(st))
end)

case("an arm for one quest is never spent on another", function()
    local st = fresh({ cfg = { focusAcceptedQuests = false } })
    st.enable()
    st.QU.AllowAutoSuperTrackQuest(5)
    st.skipAllow = true
    st.accept(6)
    ok(st.focused == 6 and sets(st) == "6", "quest 6 keeps the focus quest 5's arm cannot reach: " .. sets(st))
    -- The mismatched check spent the arm, so a later check for quest 5 finds none.
    st.C.SetSuperTrackedQuestID(5)
    st.accept(5)
    ok(st.focused == 5 and sets(st) == "6,5", "the player's own focus on quest 5 then survives its check: " .. sets(st))
    ok(st.line() == LINE:format("keeps it", "left unfocused", "hooked", 2, 0, 0, "nil"),
       "two checks, none with nothing focused: " .. tostring(st.line()))
end)

case("a client that stops asking Allow through the table loses the option, never a focus", function()
    local st = fresh({ cfg = { focusAcceptedQuests = false } })
    st.enable()
    st.skipAllow = true
    st.accept(102)
    ok(st.focused == 102 and sets(st) == "102", "the game's focus stays, as with the option on: " .. sets(st))
    ok(st.line() == LINE:format("keeps it", "left unfocused", "hooked", 1, 0, 0, "nil"),
       "and the status line shows asks with no arm: " .. tostring(st.line()))
end)

-- ---------------------------------------------------------------------------- status line

case("the status line names both options and the counts", function()
    local st = fresh()
    st.enable()
    ok(st.line() == LINE:format("keeps it", "focused", "hooked", 0, 0, 0, "nil"),
       "unset: " .. tostring(st.line()))
    st.cfg.clickToUnfocus = true
    st.cfg.focusAcceptedQuests = false
    ok(st.line() == LINE:format("unfocuses it", "left unfocused", "hooked", 0, 0, 0, "nil"),
       "both changed: " .. tostring(st.line()))
    st.accept(7)
    ok(st.line() == LINE:format("unfocuses it", "left unfocused", "hooked", 1, 1, 1, "7"),
       "after one taken back: " .. tostring(st.line()))
end)

-- ------------------------------------------------------------------------ the login restore

case("the login restore clears the focus on a fresh login only, and only when switched off", function()
    local st = fresh({ gen = { restoreSuperTrackOnLogin = false }, focused = 42 })
    st.enable()
    st.handlers.PLAYER_ENTERING_WORLD("PLAYER_ENTERING_WORLD", true, false)
    ok(#st.timers == 1 and st.timers[1].delay == 0.5, "a fresh login waits half a second: " .. #st.timers)
    if st.timers[1] then st.timers[1].fn() end
    ok(sets(st) == "0" and st.focused == 0, "then clears the focus: " .. sets(st))

    st = fresh({ gen = { restoreSuperTrackOnLogin = false }, focused = 42 })
    st.enable()
    st.handlers.PLAYER_ENTERING_WORLD("PLAYER_ENTERING_WORLD", false, true)
    ok(#st.timers == 0 and st.focused == 42, "a reload leaves it alone")

    st = fresh({ gen = { restoreSuperTrackOnLogin = true }, focused = 42 })
    st.enable()
    st.handlers.PLAYER_ENTERING_WORLD("PLAYER_ENTERING_WORLD", true, false)
    ok(#st.timers == 0 and st.focused == 42, "and Keep focused quest after relog keeps it")

    -- The client can put the saved focus back after the loading screen, so the clear is not
    -- decided by what is followed when the screen fires.
    st = fresh({ gen = { restoreSuperTrackOnLogin = false } })
    st.enable()
    st.handlers.PLAYER_ENTERING_WORLD("PLAYER_ENTERING_WORLD", true, false)
    st.C.SetSuperTrackedQuestID(42)
    ok(#st.timers == 1, "a login with nothing followed yet still waits to clear: " .. #st.timers)
    if st.timers[1] then st.timers[1].fn() end
    ok(sets(st) == "42,0" and st.focused == 0, "and clears the focus the client restored: " .. sets(st))
end)

-- -------------------------------------------------------------------- the world quest click

case("a world quest row toggles its focus the way a quest row does", function()
    local src = readFile("Data/Providers/WorldQuests.lua")
    local a = src:find("function WorldQuests:OnEntryClick(entry, button)", 1, true)
    local b = a and src:find("function WorldQuests:OnEntryGroupFinder(entry)", a, true)
    ok(a ~= nil and b ~= nil, "OnEntryClick is found, ahead of OnEntryGroupFinder")
    if not (a and b) then return end

    local calls, followed, cfg, gen, dbLoaded, has
    local function note(s) calls[#calls + 1] = s end
    local C = {}
    local env = setmetatable({
        WorldQuests = { _notifyDirty = function() note("notify") end },
        C_SuperTrack = C,
        C_QuestLog = { RemoveWorldQuestWatch = function(id) note("rmwatch:" .. tostring(id)) end },
        ns = { Has = {}, GetModule = function(_, name)
            if name == "DB" then return dbLoaded and realDB({ tracker = cfg, general = gen }) or nil end
            error("unexpected module " .. tostring(name), 0)
        end },
    }, { __index = _G })
    local chunk = assert(loadstring(src:sub(a, b - 1), "wq-click-slice"))
    setfenv(chunk, env)
    chunk()
    local function reset(o)
        o = o or {}
        calls, followed, cfg, gen, dbLoaded = {}, o.followed or 0, o.cfg or {}, o.gen or {}, true
        has = { SuperTrack = true, WorldQuestWatchAPI = true }
        env.ns.Has = has
        C.SetSuperTrackedQuestID = function(id)
            if id == nil then error("SetSuperTrackedQuestID: bad argument #1 (nil)", 2) end
            note("supertrack:" .. tostring(id))
            followed = id
        end
        C.GetSuperTrackedQuestID = function() return followed end
    end
    -- An entry as GetEntries builds it: a world quest carries the worldquest tag and its
    -- countdown, a bonus objective (kind "bonus") the bonus tag, its own group and none. Both are
    -- active and marked followed if they were when the list was built. extra overrides any field.
    local function click(id, button, extra, kind)
        calls = {}
        local wq = kind ~= "bonus"
        local e = { id = id, groupID = wq and "worldquests" or "bonusobjectives", title = "World quest " .. id,
                    state = "active", isFocused = followed == id, lines = {},
                    tags = wq and { worldquest = true } or { bonus = true },
                    expiresAt = wq and (os.time() + 3600) or nil }
        for k, v in pairs(extra or {}) do e[k] = v end
        local okCall, err = pcall(env.WorldQuests.OnEntryClick, env.WorldQuests, e, button or "LeftButton")
        ok(okCall, "OnEntryClick does not raise" .. (okCall and "" or (" - " .. tostring(err))))
        return table.concat(calls, " ")
    end

    reset({ followed = 300 })
    ok(click(300) == "supertrack:300 notify", "unset, a click on the followed world quest keeps it: " .. click(300))
    reset({ followed = 300, cfg = { clickToUnfocus = false } })
    ok(click(300) == "supertrack:300 notify", "saved off, the same")

    -- followed is written through by the set, so the next click reads the client's new answer.
    reset({ followed = 300, cfg = { clickToUnfocus = true } })
    ok(click(300) == "supertrack:0 notify", "on, it unfocuses the followed world quest")
    ok(click(300) == "supertrack:300 notify", "and the next click focuses it again")
    ok(click(300) == "supertrack:0 notify", "and the one after unfocuses it again")

    reset({ followed = 301, cfg = { clickToUnfocus = true } })
    ok(click(300) == "supertrack:300 notify", "on, a world quest that is not followed is focused")
    reset({ cfg = { clickToUnfocus = true } })
    ok(click(300) == "supertrack:300 notify", "and so is one clicked while nothing is followed")

    -- Every set is recorded in calls, so an untouched focus needs no second check.
    reset({ followed = 300, cfg = { clickToUnfocus = true } })
    ok(click(300, "RightButton") == "rmwatch:300", "a right click only untracks, focus untouched")

    reset({ followed = 300, cfg = { clickToUnfocus = true } })
    C.GetSuperTrackedQuestID = nil
    ok(click(300) == "supertrack:300 notify", "a client with no super-track getter only focuses")

    reset({ followed = 300 })
    dbLoaded = false
    ok(click(300) == "supertrack:300 notify", "with no DB module it only focuses")
    reset({ followed = 300 })
    cfg = nil
    ok(click(300) == "supertrack:300 notify", "and with no saved tracker settings")

    reset({ followed = 300, cfg = { clickToUnfocus = true } })
    has.SuperTrack = false
    ok(click(300) == "", "a client with no super-track does nothing on a left click")

    -- A bonus objective is a row of this provider too, and toggles the same way.
    reset({ followed = 300, cfg = { clickToUnfocus = true } })
    ok(click(300, nil, nil, "bonus") == "supertrack:0 notify",
       "on, a followed bonus objective is unfocused: " .. table.concat(calls, " "))
    ok(click(300, nil, nil, "bonus") == "supertrack:300 notify", "and focused again on the next click")

    -- Neither the quest's state nor its countdown has any say.
    reset({ followed = 300, cfg = { clickToUnfocus = true } })
    ok(click(300, nil, { state = "complete" }) == "supertrack:0 notify",
       "on, a followed world quest whose objectives are done is unfocused: " .. table.concat(calls, " "))
    reset({ followed = 300, cfg = { clickToUnfocus = true } })
    ok(click(300, nil, { state = "complete" }, "bonus") == "supertrack:0 notify",
       "and so is a finished bonus objective: " .. table.concat(calls, " "))
    reset({ followed = 300, cfg = { clickToUnfocus = true } })
    ok(click(300, nil, { expiresAt = os.time() + 60 }, "bonus") == "supertrack:0 notify",
       "and a bonus objective with a countdown: " .. table.concat(calls, " "))

    -- The client's answer decides, never a list built before the focus moved.
    reset({ followed = 301, cfg = { clickToUnfocus = true } })
    ok(click(300, nil, { isFocused = true }) == "supertrack:300 notify",
       "an entry still marked focused from before is focused, not cleared: " .. table.concat(calls, " "))
    reset({ followed = 300, cfg = { clickToUnfocus = true } })
    ok(click(300, nil, { isFocused = false }) == "supertrack:0 notify",
       "and an entry not yet marked is still unfocused: " .. table.concat(calls, " "))

    for _, v in ipairs({ true, false }) do
        reset({ followed = 300, cfg = neighbors({}, "clickToUnfocus", v), gen = generals({}, v) })
        ok(click(300) == "supertrack:300 notify",
           "unset beside neighbors all " .. tostring(v) .. ", it keeps the quest: " .. table.concat(calls, " "))
        reset({ followed = 300, cfg = neighbors({ clickToUnfocus = true }, nil, v), gen = generals({}, v) })
        ok(click(300) == "supertrack:0 notify",
           "on beside neighbors all " .. tostring(v) .. ", it unfocuses: " .. table.concat(calls, " "))
    end
    reset({ followed = 300, cfg = { splitQuestClick = true } })
    ok(click(300) == "supertrack:300 notify", "Split quest click alone never unfocuses: " .. table.concat(calls, " "))
end)

-- ----------------------------------------------------------------------------------- seams

case("the defaults, and the status line's place in /eqot status", function()
    ok(count(stripComments("a\n--[[\nx()\n]]\n-- x()\nb = 1 -- x()\n"), "x()") == 0,
       "the comment stripper removes block, whole-line and trailing comments")
    local db = stripComments(readFile("Core/DB.lua"))
    local tracker = db:find("\n        tracker = {\n", 1, true)
    -- The block itself, bounded by its own braces, so a default moved into a later block at the
    -- same indent is not still found after the tracker block's start.
    local block = tracker and db:match("%b{}", tracker) or ""
    ok(block:find("\n            worldQuestsHeight            = 200,\n", 1, true) ~= nil
       and not block:find("\n    char = {", 1, true) and not block:find("\n        general = {", 1, true),
       "the tracker block is read from its opening brace to its own closing one")
    ok(count(db, "clickToUnfocus") == 1 and count(db, "focusAcceptedQuests") == 1,
       "each key has exactly one default: " .. count(db, "clickToUnfocus") .. ", " .. count(db, "focusAcceptedQuests"))
    -- A pattern, so the space a stripped trailing note leaves still matches, and the comma
    -- anchors the value so true cannot pass for trueish.
    local function pcount(s, pat)
        local n = 0
        for _ in s:gmatch(pat) do n = n + 1 end
        return n
    end
    ok(pcount("\n            focusAcceptedQuests  = true, \n", "\n            focusAcceptedQuests%s*=%s*true,[ \t]*\n") == 1,
       "the default pattern takes a line whose trailing note was stripped")
    ok(pcount(block, "\n            clickToUnfocus%s*=%s*false,[ \t]*\n") == 1
       and pcount(block, "\n            focusAcceptedQuests%s*=%s*true,[ \t]*\n") == 1,
       "Click a focused quest to unfocus it defaults off and Focus newly accepted quests on, both in the tracker block")

    -- Every statement on its own line, comments stripped and blank lines dropped, so the call is
    -- read whatever spelling of its two optional arguments it uses.
    local stmts = {}
    for line in stripComments(readFile("UI/Commands.lua")):gmatch("[^\n]+") do
        if line:find("%S") then stmts[#stmts + 1] = line end
    end
    local function isCall(line, name)
        local rest = line:match("^%s*debugLine%s*%(%s*[\"']" .. name .. "[\"']%s*(.-)%)%s*$")
        if not rest then return false end
        return rest == "" or rest:match("^,%s*nil%s*$") ~= nil
               or rest:match("^,%s*nil%s*,%s*[\"']DebugLine[\"']%s*$") ~= nil
    end
    ok(isCall('    debugLine("SuperTrackPersist", nil, "DebugLine")', "SuperTrackPersist")
       and not isCall('    debugLine("SuperTrackPersist", "  ")', "SuperTrackPersist"),
       "the call reader takes the explicit method and refuses a prefix")
    local mine, auto, anyForm = {}, nil, 0
    for i, line in ipairs(stmts) do
        if isCall(line, "SuperTrackPersist") then mine[#mine + 1] = i end
        if isCall(line, "AutoTrack") then auto = auto or i end
        for _ in line:gmatch("debugLine%s*%(%s*[\"']SuperTrackPersist[\"']") do anyForm = anyForm + 1 end
    end
    ok(#mine == 1, "/eqot status prints the focus line, once: " .. #mine)
    ok(anyForm == 1, "and in no other form: " .. anyForm)
    ok(auto ~= nil and mine[1] == auto + 1, "straight after the auto-track line: " .. tostring(auto) .. ", " .. tostring(mine[1]))
end)

print(("test_unfocus: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
