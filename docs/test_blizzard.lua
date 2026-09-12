-- luacheck: globals ObjectiveTrackerFrame QuestWatchFrame GetTime C_Timer InCombatLockdown
--
-- Unit tests for suppressing Blizzard's own objective tracker, run against the SHIPPED source.
-- Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_blizzard.lua
--
-- UI/Blizzard.lua loads WHOLE here rather than being sliced: it creates no frame and calls no
-- quest API, so a table with the right methods on it is a complete stand-in for Blizzard's
-- tracker. That is worth having, because this is the one file in the tree whose whole job is
-- writing to a frame this addon does not own.
--
-- The cases that earn this file:
--
--   1. THE UNMOUNT WALKS A LIST THAT SHRINKS UNDER IT. Blizzard's RemoveModule deletes from the
--      very table being iterated, so a forward walk of tracker.modules leaves every second
--      module mounted and the bug half-fixed - which looks fixed on a client with one module
--      and is not. The snapshot is the whole defence and the twelve-module case is what proves
--      it.
--   2. Classic has no .modules and no RemoveModule. Reaching for either has to be a no-op
--      rather than a raise: this runs at PLAYER_ENTERING_WORLD on every flavor. Core/Events.lua
--      pcalls each handler, so a raise does not reach the others, and silence() has already run
--      by then - what it loses is the OnShow hook, and without that a second tracker comes back
--      the first time Blizzard shows the frame.
--   3. Suppress is deliberately NOT latched, so it is called again on every world change and
--      every combat end. Running it twice may not hook twice, and may not count a module it
--      has already taken off.
--   4. The frame is hidden AND alpha zero AND unregistered. An alpha-only frame still eats
--      clicks, and a hidden frame that Blizzard shows again draws for a frame at full alpha.
--   5. DebugLine is the standing regression check for the double-tracker bug and it is read
--      off a user's paste. It has to name both numbers and it may never raise.

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
end

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end

-- The ONLY way this file calls Suppress. A raise has to fail a case, never kill the run: the
-- summary line would never print and every battery here reads a missing summary as a mutant that
-- SURVIVED, which sends the next reader hunting a coverage hole that is not there.
local function suppress(B, why)
    local okCall, err = pcall(B.Suppress, B)
    ok(okCall, (why or "Suppress") .. " does not raise" ..
       (okCall and "" or (" - " .. tostring(err))))
    return okCall
end

-- --------------------------------------------------------------------- the client stubs

local deferred
local function flush()
    local queue = deferred
    deferred = {}
    for i = 1, #queue do queue[i]() end
end

-- Advanceable rather than constant. With a fixed clock the age arithmetic in DebugLine is
-- always exactly 0, so inverting the subtraction or replacing it with a literal both satisfy
-- the assertion - and that field is how an 846-reshow delve storm is told from a quiet hour.
local now = 1000
_G.GetTime = function() return now end
_G.InCombatLockdown = function() return false end
_G.C_Timer = { After = function(_, fn) deferred[#deferred + 1] = fn end }

-- Blizzard's own RemoveModule deletes from self.modules, so the fake carries that behavior
-- rather than a convenient one. A stub that removed nothing, or removed by value from a copy,
-- would make the snapshot case pass against a build that has no snapshot.
local function fakeTracker(opts)
    opts = opts or {}
    local t = {
        _shown = true, _alpha = 1, _unregistered = 0, _hooks = {},
        removeCalls = 0, hideCalls = 0, alphaCalls = 0,
    }
    t.Hide = function(self) self.hideCalls = self.hideCalls + 1 self._shown = false end
    t.Show = function(self) self._shown = true end
    t.IsShown = function(self) return self._shown end
    t.SetAlpha = function(self, a) self.alphaCalls = self.alphaCalls + 1 self._alpha = a end
    t.GetAlpha = function(self) return self._alpha end
    t.HookScript = function(self, script, fn) self._hooks[script] = fn end
    -- findTracker only ever proves .Hide exists, so silence's other two guards are the ones
    -- that can meet a frame without them - which is what noAlpha and noUnregister build.
    if not opts.noUnregister then
        t.UnregisterAllEvents = function(self) self._unregistered = self._unregistered + 1 end
    end
    if opts.noAlpha then t.SetAlpha, t.GetAlpha = nil, nil end

    if opts.modules ~= false then
        t.modules = {}
        for i = 1, (opts.count or 12) do t.modules[i] = { id = i } end
    end
    if opts.removeModule ~= false then
        t.RemoveModule = function(self, m)
            self.removeCalls = self.removeCalls + 1
            if opts.removeRaises then error("RemoveModule blew up") end
            for i = 1, #self.modules do
                if self.modules[i] == m then table.remove(self.modules, i) return end
            end
        end
    end
    return t
end

-- --------------------------------------------------------------------- load the shipped file

-- A fresh module table per case, because Suppress records _hookedFrame and _unmounted on it and
-- a case must not inherit either from the case before it.
local function load(tracker, name, opts)
    opts = opts or {}
    _G.ObjectiveTrackerFrame = nil
    _G.QuestWatchFrame = nil
    _G.QuestTimerFrame = opts.timerFrame or nil
    _G[name or "ObjectiveTrackerFrame"] = tracker
    deferred = {}

    local events = {}
    local ns = {
        modules = {},
        -- Empty by default, which is what keeps every case above blind to the quest timer
        -- frame: findQuestTimer refuses without BOTH the timer source and the absence of the
        -- retail quest log.
        Has = opts.has or {},
        RegisterModule = function(self, n, tbl) self.modules[n] = tbl or {} return self.modules[n] end,
        GetModule = function(self, n) return self.modules[n] end,
    }
    ns.modules.Events = {
        On = function(_, ev, fn) events[ev] = fn end,
        RunWhenOutOfCombat = function(_, key, fn) events["!" .. key] = fn end,
    }
    local chunk = assert(loadfile(repoFile("UI/Blizzard.lua")))
    chunk("EQObjectiveTracker", ns)
    return ns:GetModule("Blizzard"), events
end

-- ------------------------------------------------------------------------------ the cases

print("== a retail tracker is hidden, blanked, silenced and unmounted")
do
    local t = fakeTracker()
    local B = load(t)
    suppress(B, "a retail suppress")

    ok(t._shown == false, "the frame is hidden")
    ok(t._alpha == 0, "and its alpha is zeroed, so a re-show draws nothing before the re-hide")
    ok(t._unregistered == 1, "and its own events are unregistered")
    ok(t._hooks.OnShow ~= nil, "the OnShow hook is installed")

    -- The whole point of the change: with no modules mounted, Blizzard's container has nothing
    -- to lay out, so the scenario module's unguarded secret-aura read is never reached.
    ok(#t.modules == 0, "every module is taken off the container")
    ok(t.removeCalls == 12, "and RemoveModule is called once per module, not once")
end

print("== the unmount survives a list that shrinks under it")
do
    -- The case that earns the snapshot. Blizzard's RemoveModule deletes from tracker.modules,
    -- so a plain forward walk of that table skips every second entry: twelve modules would
    -- leave six mounted, the aura read would still be reached, and a one-module client would
    -- have reported it fixed.
    for _, n in ipairs({ 1, 2, 3, 11, 12, 25 }) do
        local t = fakeTracker{ count = n }
        local B = load(t)
        suppress(B, ("a %d-module suppress"):format(n))
        ok(#t.modules == 0, ("all %d modules are unmounted, none skipped"):format(n))
        ok(t.removeCalls == n, ("and RemoveModule ran exactly %d times"):format(n))
    end
end

print("== Classic is left alone rather than raised on")
do
    -- Classic's QuestWatchFrame has neither field, and the third case below is neither Classic
    -- nor QuestWatchFrame - it is the half-shaped frame a future Blizzard rename would leave.
    -- This runs at PLAYER_ENTERING_WORLD on every flavor, so a raise here loses the OnShow hook
    -- and a second tracker comes back the first time Blizzard shows the frame.
    local t = fakeTracker{ modules = false, removeModule = false }
    local B = load(t, "QuestWatchFrame")
    suppress(B, "a frame with no modules and no RemoveModule")
    ok(t._shown == false, "and it is still hidden")

    local t2 = fakeTracker{ removeModule = false }
    local B2 = load(t2, "QuestWatchFrame")
    suppress(B2, "a frame with modules but no RemoveModule")
    ok(#t2.modules == 12, "and its modules are left mounted, because there is no way to remove one")

    local t3 = fakeTracker{ modules = false }
    local B3 = load(t3)
    suppress(B3, "a frame with RemoveModule but no modules")
    ok(t3.removeCalls == 0, "and nothing is removed")
end

print("== a RemoveModule that raises does not take the rest with it")
do
    -- pcall'd per module rather than around the loop: Blizzard's method is another addon's
    -- code by the time a skin has hooked it, and one raising module must not leave the other
    -- eleven mounted.
    local t = fakeTracker{ removeRaises = true }
    local B = load(t)
    suppress(B, "a suppress whose RemoveModule raises")
    ok(t.removeCalls == 12, "every module is still attempted")
    ok(t._shown == false, "and the frame is still hidden")
end

print("== Suppress is called again on every world change and every combat end")
do
    local t = fakeTracker()
    local B = load(t)
    suppress(B, "the first suppress")
    local firstHook = t._hooks.OnShow
    suppress(B, "the second suppress")
    suppress(B, "the third suppress")

    ok(t._hooks.OnShow == firstHook, "the OnShow hook is installed once, not once per call")
    ok(t.removeCalls == 12, "a second pass removes nothing, because nothing is mounted")
    ok(t._unregistered == 3, "but the frame is re-silenced every time, which is what recovers it")

    -- Blizzard adding a module back later is exactly why none of this is latched.
    t.modules[1] = { id = 99 }
    suppress(B, "a suppress after Blizzard adds a module back")
    ok(#t.modules == 0, "a module Blizzard adds back is taken off again")
    ok(t.removeCalls == 13, "with one more RemoveModule call for it")
end

print("== the deferred re-hide")
do
    local t = fakeTracker()
    local B = load(t)
    suppress(B, "the suppress before the re-show")

    t:Show()
    t:SetAlpha(1)
    t._hooks.OnShow(t)
    -- Deferred by a frame on purpose: hiding straight from inside Blizzard's own Show was
    -- followed by a blocked map-pin action off a stack carrying none of this addon's code.
    ok(t._shown == true, "the hook does not hide the frame synchronously")
    flush()
    ok(t._shown == false, "the deferred callback hides it")
    ok(t._alpha == 0, "and blanks it")

    -- Coalesced, or a burst of shows queues a callback each.
    t:Show()
    t._hooks.OnShow(t)
    t._hooks.OnShow(t)
    t._hooks.OnShow(t)
    ok(#deferred == 1, "a burst of shows queues one re-hide, not one each")
    flush()
    ok(t._shown == false, "and the frame ends up hidden")
end

print("== the status line")
do
    local t = fakeTracker()
    local B = load(t)
    suppress(B, "a retail suppress")
    local line = B:DebugLine()

    ok(type(line) == "string", "DebugLine answers a string")
    ok(line:find("ObjectiveTrackerFrame", 1, true) ~= nil, "it names the frame it resolved")
    -- Both numbers, because 0 modules means two different things now: Classic has none to
    -- begin with, retail has been emptied. Without the second one a working retail client
    -- reads exactly like a Classic one on the line a user pastes.
    ok(line:find("0 modules (12 unmounted)", 1, true) ~= nil,
       "it prints the module count AND how many were unmounted")
    ok(line:find("hidden", 1, true) ~= nil, "and that the frame is hidden")

    local t2 = fakeTracker{ modules = false, removeModule = false }
    local B2 = load(t2, "QuestWatchFrame")
    suppress(B2, "a Classic suppress")
    local classic = B2:DebugLine()
    ok(classic:find("QuestWatchFrame", 1, true) ~= nil, "Classic names its own frame")
    ok(classic:find("0 modules (0 unmounted)", 1, true) ~= nil,
       "and reports nothing unmounted, which is what separates it from retail")

    _G.ObjectiveTrackerFrame, _G.QuestWatchFrame = nil, nil
    local B3 = load(fakeTracker())
    _G.ObjectiveTrackerFrame = nil
    local absent = B3:DebugLine()
    ok(absent:find("no known tracker frame", 1, true) ~= nil,
       "and a client with neither global says so rather than raising")
end

print("== the status line separates a count that ran from one that found nothing")
do
    -- The count alone is a stub DEFAULT that is also the passing value: every DebugLine call
    -- here happens after a Suppress, so retail reads 0 modules and so does Classic. These two
    -- cases are what make the number mean something.
    local t = fakeTracker()
    local B = load(t)
    suppress(B, "a retail suppress")
    t.modules[1] = { id = 91 }
    t.modules[2] = { id = 92 }
    ok(B:DebugLine():find("2 modules (12 unmounted)", 1, true) ~= nil,
       "the live module count is read back, not assumed to be zero: " .. B:DebugLine())

    -- Nothing came off, so the unmounted count may not claim otherwise. This is the reading
    -- that separates "the unmount worked" from "the unmount silently found nothing", which is
    -- what a renamed Blizzard field would produce.
    local t2 = fakeTracker{ removeRaises = true }
    local B2 = load(t2)
    suppress(B2, "a suppress whose RemoveModule raises")
    ok(B2:DebugLine():find("(0 unmounted)", 1, true) ~= nil,
       "a removal that raised is not counted as unmounted: " .. B2:DebugLine())

    -- SHOWN - hide pending is NOT a failure and must never read as one: the re-hide is deferred
    -- by a frame, so the frame really is shown for that frame, ~846 times in a single delve.
    local t3 = fakeTracker()
    local B3 = load(t3)
    suppress(B3, "a suppress before the re-show")
    t3:Show()
    t3._hooks.OnShow(t3)
    ok(B3:DebugLine():find("SHOWN - hide pending", 1, true) ~= nil,
       "a shown frame with a re-hide queued says so: " .. B3:DebugLine())
    flush()
    ok(B3:DebugLine():find("hidden", 1, true) ~= nil, "and reads hidden once it lands")

    -- The other SHOWN state is the real alarm, and it is also what the author's own client
    -- reads while running the two trackers side by side with /eqot disable Blizzard.
    t3:Show()
    ok(B3:DebugLine():find("SHOWN - suppression lost", 1, true) ~= nil,
       "a shown frame with nothing pending is the one that reports a lost suppression: "
       .. B3:DebugLine())

    -- reshown and its age are read off a user's paste and neither is driven anywhere else.
    ok(B3:DebugLine():find("reshown 1", 1, true) ~= nil, "re-shows are counted")
    ok(B3:DebugLine():find("last 0s ago", 1, true) ~= nil, "and stamped")

    -- The clock has to MOVE for this field to say anything. Constant, every wrong expression
    -- that yields zero passes.
    now = now + 42
    ok(B3:DebugLine():find("last 42s ago", 1, true) ~= nil,
       "the age counts forward from the stamp: " .. B3:DebugLine())
    now = now - 42

    -- alpha is the field that separates a working client from one running the two trackers
    -- side by side, and nothing read it: hardcoding it to zero survived.
    t3._alpha = 0.5
    ok(B3:DebugLine():find("alpha 0.50", 1, true) ~= nil,
       "the frame's own alpha is what is printed, not a constant: " .. B3:DebugLine())
    t3._alpha = 0
    local fresh = load(fakeTracker())
    ok(fresh:DebugLine():find("reshown 0, last never", 1, true) ~= nil,
       "a session that has seen none says never rather than a time")

    -- The hook field was only ever read at "installed", so it could be pinned there. That is the
    -- single most misread line in this addon's whole status dump: the author runs
    -- /eqot disable Blizzard permanently to keep both trackers on screen, so every status they
    -- paste reads "hook missing" - and a field that can only ever say "installed" would turn
    -- that deliberate setup into a silent lie on the one line used to diagnose the
    -- double-tracker bug.
    ok(fresh:DebugLine():find("hook missing", 1, true) ~= nil,
       "a module whose Suppress never ran says its hook is MISSING: " .. fresh:DebugLine())
    suppress(fresh, "a suppress on the previously untouched module")
    ok(fresh:DebugLine():find("hook installed", 1, true) ~= nil,
       "and says installed once it has: " .. fresh:DebugLine())
end

print("== OnEnable is what wires the repeat suppression")
do
    -- Every case above calls Suppress by hand. Without this the whole registration block can be
    -- deleted with the file green, and the recorded failure of this module was exactly that:
    -- a suppression that ran once and never again.
    local t = fakeTracker()
    local B, events = load(t)
    ok(pcall(B.OnEnable, B), "OnEnable does not raise")
    ok(t._hooks.OnShow ~= nil, "OnEnable suppresses immediately rather than only registering")
    ok(events.PLAYER_ENTERING_WORLD ~= nil, "it registers PLAYER_ENTERING_WORLD")
    ok(events.PLAYER_REGEN_ENABLED ~= nil, "and PLAYER_REGEN_ENABLED, so combat end re-suppresses")
    ok(events.ADDON_LOADED ~= nil, "and ADDON_LOADED, for a tracker that loads on demand")

    -- The ADDON_LOADED gate names one addon. Inverted or dropped it would re-suppress on every
    -- addon that loads, which is work on a frame this addon has already tainted.
    -- Called through a guard, never bare: a mutant that drops a registration would otherwise
    -- reach a nil and kill the file rather than failing these cases.
    local function fire(name, ...)
        if events[name] then events[name](...) end
    end

    t.modules[1] = { id = 1 }
    fire("ADDON_LOADED", nil, "Some_Other_Addon")
    ok(#t.modules == 1, "an unrelated addon loading does not re-suppress")
    fire("ADDON_LOADED", nil, "Blizzard_ObjectiveTracker")
    ok(#t.modules == 0, "Blizzard_ObjectiveTracker loading does")

    t.modules[1] = { id = 2 }
    fire("PLAYER_ENTERING_WORLD")
    ok(#t.modules == 0, "and so does a world change")
end

print("== the deferred re-hide in combat, and on a frame already hidden")
do
    local t = fakeTracker()
    local B = load(t)
    suppress(B, "a suppress before the re-show")

    -- A frame Blizzard hid again between the OnShow and the callback must not be written to a
    -- second time: that is one more insecure write to a Blizzard frame, from a timer.
    t:Show()
    t._hooks.OnShow(t)
    local hidesBefore, alphaBefore = t.hideCalls, t.alphaCalls
    t:Hide()
    flush()
    ok(t.hideCalls == hidesBefore + 1,
       "a frame hidden before the callback lands is not hidden again by it")
    ok(t.alphaCalls == alphaBefore, "and its alpha is not rewritten either")

    -- In combat the re-hide still runs AND queues a re-suppress for when combat ends.
    local t2 = fakeTracker()
    local B2, events2 = load(t2)
    suppress(B2, "a suppress before a combat re-show")
    _G.InCombatLockdown = function() return true end
    t2:Show()
    t2._hooks.OnShow(t2)
    flush()
    _G.InCombatLockdown = function() return false end
    ok(t2._shown == false, "the re-hide lands in combat rather than waiting")
    ok(events2["!eqot.blizzardSuppress"] ~= nil,
       "and a re-suppress is queued for when combat ends")

    -- Proving it was QUEUED says nothing about what it does. Emptying the closure survived
    -- until this ran it: the produce/consume split, which this project has now paid for four
    -- times.
    t2:Show()
    for i = 1, #t2.modules do t2.modules[i] = nil end
    t2.modules[1] = { id = "re-added" }
    local okRun = pcall(events2["!eqot.blizzardSuppress"])
    ok(okRun, "the queued re-suppress runs without raising")
    ok(t2._shown == false, "and it hides the frame again when combat ends")
    ok(#t2.modules == 0, "and takes the re-added module back off the container")
end

print("== findTracker picks the right global, and survives having none")
do
    -- Retail wins when both globals exist. load() sets exactly one, so without this the two
    -- branches can be swapped with the file green.
    local retail, classic = fakeTracker(), fakeTracker{ modules = false, removeModule = false }
    local B = load(retail)
    _G.QuestWatchFrame = classic
    suppress(B, "a suppress with both globals present")
    ok(retail._shown == false, "the retail frame is the one suppressed")
    ok(classic._shown == true, "and the Classic global is left alone")
    ok(B:DebugLine():find("ObjectiveTrackerFrame", 1, true) ~= nil, "and named")
    _G.QuestWatchFrame = nil

    -- A table without Hide is not a tracker. Blizzard has shipped placeholder globals before.
    local B2 = load(fakeTracker())
    _G.ObjectiveTrackerFrame = { modules = {} }
    _G.QuestWatchFrame = classic
    suppress(B2, "a suppress with a shapeless retail global")
    ok(classic._shown == false, "a global with no Hide is skipped for the one that has it")
    _G.QuestWatchFrame = nil

    -- ADDON_LOADED exists precisely because the frame may not, so Suppress runs with neither.
    local B3 = load(fakeTracker())
    _G.ObjectiveTrackerFrame = nil
    suppress(B3, "a suppress with no tracker frame at all")
end

print("== silence guards each call, because findTracker only proves Hide")
do
    local t = fakeTracker{ noAlpha = true }
    local B = load(t)
    suppress(B, "a suppress on a frame with no SetAlpha")
    ok(t._shown == false, "the frame is still hidden")

    local t2 = fakeTracker{ noUnregister = true }
    local B2 = load(t2)
    suppress(B2, "a suppress on a frame with no UnregisterAllEvents")
    ok(t2._shown == false, "that frame is hidden too")
    ok(t2._alpha == 0, "and blanked")
end

print("== the hook is keyed on the FRAME, not on a flag")
do
    -- The one thing the production comment argues for, and nothing tested it: every other case
    -- gives each frame its own module table, so the frame never changes within a case.
    local first = fakeTracker()
    local B = load(first)
    suppress(B, "the first frame's suppress")
    local firstHook = first._hooks.OnShow

    local second = fakeTracker()
    _G.ObjectiveTrackerFrame = second
    suppress(B, "a second frame's suppress on the same module")
    ok(second._hooks.OnShow ~= nil, "a different frame gets its own hook")
    ok(second._hooks.OnShow ~= firstHook, "a fresh one, not the first frame's")
end

-- ================================================================ Blizzard's OWN quest timer

-- QuestTimerFrame is a THIRD Blizzard frame and a sibling of neither tracker, so findTracker
-- cannot reach it: it draws its own floating countdown for any timed quest, and until v1.23.0 it
-- sat beside an EQOT row that said nothing about the timer.
--
-- Hiding it is not cosmetic. It is the ONLY timer a Classic player has, so the two capability
-- tests in findQuestTimer are what stop this being a straight regression, and the retail case
-- below is the one that would have reached every retail user rather than a few Era ones.

local CLASSIC = { QuestTimers = true }              -- can read the timers, no retail quest log
local RETAIL  = { QuestTimers = true, QuestLog = true }
-- The one combination that can tell the two refusals APART. With both flags true the order of
-- the two overrides in QuestTimerLine cannot matter, so RETAIL alone proves nothing about which
-- one wins - and the retail answer has to win, because on retail the frame is deliberately left
-- alone whether or not the timer API happens to be there. Reporting it as "GetQuestTimers
-- absent" would send a reader probing an API that was never the reason.
local RETAIL_NO_TIMERS = { QuestLog = true }

local function timerFrame()
    local f = { _shown = true, _alpha = 1, _hooks = {}, hideCalls = 0, unregistered = 0 }
    f.Hide = function(self) self.hideCalls = self.hideCalls + 1 self._shown = false end
    f.Show = function(self) self._shown = true end
    f.IsShown = function(self) return self._shown end
    f.SetAlpha = function(self, a) self._alpha = a end
    f.GetAlpha = function(self) return self._alpha end
    f.HookScript = function(self, script, fn) self._hooks[script] = fn end
    f.UnregisterAllEvents = function(self) self.unregistered = self.unregistered + 1 end
    return f
end

-- Asserted before it is called, never called bare. A mutant that drops the hook leaves this nil,
-- and calling nil ABORTS the file before its summary line - which every battery here reads as a
-- mutant that SURVIVED, so the crash would report as a coverage hole instead of as the catch it
-- is. Two mutants did exactly that on this battery's first run.
local function fireShow(f, why)
    ok(f._hooks.OnShow ~= nil, (why or "the frame") .. " has an OnShow hook to fire")
    if f._hooks.OnShow then f._hooks.OnShow(f) end
end

print("== Blizzard's own quest timer frame is hidden on Classic")
do
    local qt = timerFrame()
    local B = load(fakeTracker{ modules = false, removeModule = false }, "QuestWatchFrame",
                   { has = CLASSIC, timerFrame = qt })
    suppress(B, "a Classic suppress with a quest timer frame")

    ok(qt._shown == false, "the quest timer frame is hidden")
    ok(qt._alpha == 0, "and blanked, so a re-show draws nothing before the deferred re-hide")
    ok(qt._hooks.OnShow ~= nil, "and hooked, or it comes back the first time Blizzard shows it")

    -- Deliberate, and the same rule the tracker's own sub-modules get: this stops the frame
    -- DRAWING and nothing more. A frame whose events have been torn off could never recover.
    ok(qt.unregistered == 0, "its own events are left registered, unlike the tracker frame's")
end

print("== and left completely alone on retail, where nothing would replace it")
do
    -- The case that matters most. Data/Providers/Quests.lua does not fill expiresAt, so hiding
    -- this frame on retail would take a timer away and put nothing back - and it would reach
    -- every retail player rather than the Era ones the feature is for.
    local qt = timerFrame()
    local B = load(fakeTracker(), "ObjectiveTrackerFrame", { has = RETAIL, timerFrame = qt })
    suppress(B, "a retail suppress with a quest timer frame present")

    ok(qt._shown == true, "the frame is still shown on retail")
    ok(qt.hideCalls == 0, "Hide is never reached")
    ok(qt._hooks.OnShow == nil, "and no hook is installed on it")
    ok(B:QuestTimerLine():find("not applicable") ~= nil,
       "and the status line says so rather than reporting a failure")

    -- The hook field on THIS line, at its other value. A refusal must never claim a hook it
    -- never installed, or a retail paste reads as though the frame were being driven.
    ok(B:QuestTimerLine():find("hook") == nil,
       "a refusal reports no hook state at all rather than claiming one: " .. B:QuestTimerLine())
end

print("== a retail client with no timer API still reports the retail reason, not the timer one")
do
    -- Precedence, which the RETAIL fixture above cannot test: with BOTH flags true the order of
    -- the two overrides is unobservable. Only the retail quest log with no timer source can say
    -- which wins, and it has to be the retail one - the frame is left alone here because this is
    -- retail, not because an API is missing, and naming the wrong half sends the next reader to
    -- probe GetQuestTimers on a client where that was never the question.
    local qt = timerFrame()
    local B = load(fakeTracker(), "ObjectiveTrackerFrame",
                   { has = RETAIL_NO_TIMERS, timerFrame = qt })
    suppress(B, "a retail suppress on a client with no timer API")

    ok(qt._shown == true, "the frame is still left alone")
    ok(qt.hideCalls == 0, "and never hidden")

    local line = B:QuestTimerLine()
    ok(line:find("not applicable") ~= nil, "the retail reason wins: " .. line)
    ok(line:find("GetQuestTimers absent") == nil,
       "and the timer-source reason is not what gets reported: " .. line)
end

print("== and left alone on a client that cannot answer for the timers")
do
    -- Same bargain from the other side: with no GetQuestTimers there is no countdown on the
    -- row either, so hiding the frame would leave the player with no timer at all.
    local qt = timerFrame()
    local B = load(fakeTracker{ modules = false, removeModule = false }, "QuestWatchFrame",
                   { has = {}, timerFrame = qt })
    suppress(B, "a suppress with no timer source")

    ok(qt._shown == true, "the frame is left shown")
    ok(qt.hideCalls == 0, "and never hidden")
    ok(B:QuestTimerLine():find("GetQuestTimers absent") ~= nil,
       "and the status line names which half refused")
end

print("== a frame that is not shaped like one is refused rather than called into")
do
    -- findQuestTimer used to validate Hide and nothing else, while this file goes on to call
    -- HookScript and IsShown on the same frame. That matters more than it looks: hideQuestTimer
    -- is the FIRST statement of Suppress, which is the first statement of OnEnable, so a raise
    -- here costs the tracker suppression AND the three event subscriptions behind it - the
    -- double-tracker bug, for the session, with no recovery path.
    local half = { _shown = true }
    half.Hide = function(self) self._shown = false end

    local B = load(fakeTracker{ modules = false, removeModule = false }, "QuestWatchFrame",
                   { has = CLASSIC, timerFrame = half })
    suppress(B, "a suppress with a half-shaped quest timer frame")

    ok(half._shown == true, "the frame is left alone rather than driven")

    local okLine, line = pcall(B.QuestTimerLine, B)
    ok(okLine, "the status line does not raise on a half-shaped frame" ..
       (okLine and "" or (" - " .. tostring(line))))
    line = okLine and line or ""
    ok(line:find("frame shape not recognized") ~= nil,
       "and names the frame as the half that refused, not the timer source")

    -- The refusal must not read as an absence: the source IS present here, and a reader sent to
    -- probe GetQuestTimers would find it answering perfectly.
    ok(line:find("no frame") == nil, "and does not report it as absent")
end

print("== a client with no such frame is a no-op, not a raise")
do
    local B = load(fakeTracker{ modules = false, removeModule = false }, "QuestWatchFrame",
                   { has = CLASSIC })
    suppress(B, "a suppress with no quest timer frame at all")
    ok(B:QuestTimerLine():find("no frame") ~= nil, "and the status line says the frame is absent")
end

print("== the quest timer is suppressed even when no tracker frame is found")
do
    -- Ordering, and it is load-bearing: Suppress returns early when findTracker answers nothing,
    -- so a quest timer hidden AFTER that test would never be reached on a client where the
    -- tracker global is missing or renamed.
    local qt = timerFrame()
    local B = load(nil, "QuestWatchFrame", { has = CLASSIC, timerFrame = qt })
    suppress(B, "a suppress with no tracker frame")
    ok(qt._shown == false, "the quest timer frame is still hidden")
end

print("== the quest timer re-hide is deferred a frame and coalesced")
do
    local qt = timerFrame()
    local B = load(fakeTracker{ modules = false, removeModule = false }, "QuestWatchFrame",
                   { has = CLASSIC, timerFrame = qt })
    suppress(B, "a Classic suppress")
    local hideAfterSuppress = qt.hideCalls

    -- Read before any show as well as after. At one value the literal satisfies the assertion,
    -- which is what lets a counter be pinned - the tracker's own line reads its at two values
    -- for exactly this reason.
    ok(B:QuestTimerLine():find("reshown 0", 1, true) ~= nil,
       "nothing has re-shown the frame yet: " .. B:QuestTimerLine())

    qt:Show()
    fireShow(qt, "the quest timer frame")
    ok(qt._shown == true, "hiding is NOT synchronous - the frame is still shown inside the hook")
    ok(qt.hideCalls == hideAfterSuppress, "and Hide has not been reached yet")

    fireShow(qt, "the quest timer frame")
    fireShow(qt, "the quest timer frame")
    -- Counted as DEFERRALS rather than as hides. Three queued callbacks all land on a frame the
    -- first one already hid, so the IsShown guard one line down masks them and the hide count
    -- reads 1 either way - which let the coalescing flag be deleted with this file green.
    ok(#deferred == 1, "three shows inside one frame queue exactly ONE re-hide")
    flush()
    ok(qt._shown == false, "the deferred re-hide lands")
    ok(qt.hideCalls == hideAfterSuppress + 1, "and Hide is reached once")
    ok(B:QuestTimerLine():find("reshown 3") ~= nil, "the status line counts every show")

    -- A show that something else has already taken back must not be hidden again, or the addon
    -- writes to a frame nobody asked it to touch.
    qt:Show()
    fireShow(qt, "the quest timer frame")
    qt:Hide()
    local before = qt.hideCalls
    flush()
    ok(qt.hideCalls == before, "a frame hidden again before the deferral lands is left alone")

    -- A third reading, so the count is seen to keep MOVING rather than to have reached a
    -- literal. A show the addon declines to act on is still a show, and still counts.
    ok(B:QuestTimerLine():find("reshown 4", 1, true) ~= nil,
       "and the show it declined to act on is counted all the same: " .. B:QuestTimerLine())
end

print("== the quest timer hook is keyed on the frame too")
do
    local first = timerFrame()
    local B = load(fakeTracker{ modules = false, removeModule = false }, "QuestWatchFrame",
                   { has = CLASSIC, timerFrame = first })
    suppress(B, "the first quest timer suppress")
    local firstHook = first._hooks.OnShow

    suppress(B, "a second suppress on the same frame")
    ok(first._hooks.OnShow == firstHook, "the same frame is not hooked twice")

    local second = timerFrame()
    _G.QuestTimerFrame = second
    suppress(B, "a suppress after the frame was replaced")
    ok(second._hooks.OnShow ~= nil, "a replaced frame gets its own hook")
    ok(second._hooks.OnShow ~= firstHook, "a fresh one, not the first frame's")
end

print("== QuestTimerLine reports both failure states and never raises")
do
    local qt = timerFrame()
    local B = load(fakeTracker{ modules = false, removeModule = false }, "QuestWatchFrame",
                   { has = CLASSIC, timerFrame = qt })

    -- Before Suppress the frame RESOLVES and the hook does not exist, which is the state a
    -- Classic client running /eqot disable Blizzard is in. Pinned to "installed" this line would
    -- claim the frame was being driven when nothing had touched it.
    ok(B:QuestTimerLine():find("hook missing", 1, true) ~= nil,
       "a resolved frame with no hook yet says missing: " .. B:QuestTimerLine())

    suppress(B, "a Classic suppress")
    ok(B:QuestTimerLine():find("hook installed", 1, true) ~= nil,
       "and says installed once Suppress has run: " .. B:QuestTimerLine())

    local okCall, line = pcall(B.QuestTimerLine, B)
    ok(okCall and type(line) == "string", "it answers a string")
    ok(okCall and line:find("hidden") ~= nil, "and reads hidden while the suppression holds")

    -- The distinction the tracker's own line already makes, for the same reason: a frame that is
    -- shown with a re-hide queued is the deferral working, not the suppression failing, and
    -- crying wolf on it is what makes a status line stop being read.
    qt:Show()
    fireShow(qt, "the quest timer frame")
    line = B:QuestTimerLine()
    ok(line:find("hide pending") ~= nil, "a show with a re-hide queued reads as pending")
    flush()

    qt:Show()
    line = B:QuestTimerLine()
    ok(line:find("suppression lost") ~= nil,
       "and a show with nothing queued reads as the suppression being lost")
end

print(("test_blizzard: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
