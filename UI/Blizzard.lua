local _, ns = ...

local Blizzard = ns:RegisterModule("Blizzard", {})

-- Deliberately does NOT reparent ObjectiveTrackerFrame. In retail it hosts secure
-- quest-item buttons, and reparenting a chain containing secure children taints it.
-- Alpha as well as Hide: Show() does not restore alpha, so nothing draws during the frame
-- between Blizzard showing the tracker and the deferred re-hide landing.
local function silence(frame)
    if not frame then return end
    if frame.UnregisterAllEvents then frame:UnregisterAllEvents() end
    if frame.SetAlpha then frame:SetAlpha(0) end
    if frame.Hide then frame:Hide() end
end

-- Read off Blizzard's own published source, 2026-09-04, against a user's stack:
-- ObjectiveTrackerFrameMixin:Update returns early only when HasAnyModules() is false, and
-- ObjectiveTrackerContainerMixin:Update has no visibility check at all - so with modules
-- mounted they lay out inside the frame this addon hides, in execution this addon tainted by
-- hiding it. ScenarioObjectiveTrackerMixin:LayoutContents then calls the global
-- ShouldShowMawBuffs unconditionally, whose first statement is
-- C_UnitAuras.GetAuraDataByIndex("player", 1, "MAW") with no secret guard, and a secret aura
-- read from tainted execution throws instead of answering nil. That is the reported
-- "Auras cannot be accessed when secret while tainted by 'EQObjectiveTracker'".
--
-- This stops the LAYOUT, never the taint. Hiding a frame taints it and there is no version of
-- this addon that does not hide this one.
--
-- Emptying the list is what takes effect: HasAnyModules() then answers false and Update returns
-- before the container loop is reached at all.
--
-- RemoveModule is Blizzard's own method on the container, which is why this is not a table
-- mutation. Its whole body is a tDeleteItem plus a MarkDirty, so it does not touch a module's
-- events - which is what makes it far narrower than the UnregisterAllEvents loop this file used
-- to run, and it must not grow back into one.
local function unmount(self, tracker)
    if type(tracker.RemoveModule) ~= "function" or type(tracker.modules) ~= "table" then
        return
    end

    -- Snapshotted because RemoveModule deletes from the very table being walked, and a walk of
    -- a list that shrinks under it leaves half the modules mounted.
    local mods, n = {}, #tracker.modules
    for i = 1, n do mods[i] = tracker.modules[i] end
    for i = 1, n do
        if pcall(tracker.RemoveModule, tracker, mods[i]) then
            self._unmounted = (self._unmounted or 0) + 1
        end
    end
end

-- Blizzard's tracker has a different global on each flavor and this addon carries no
-- runtime flavor branch, so the frame is resolved by trying the names it can have.
-- ObjectiveTrackerFrame is retail. QuestWatchFrame is Vanilla and TBC, measured on 1.15.9
-- and 2.5.6. WatchFrame is the Wrath through Mists name and is deliberately absent - no TOC
-- targets those flavors, so handling it would ship untested.
local function findTracker()
    local f = ObjectiveTrackerFrame
    if type(f) == "table" and type(f.Hide) == "function" then
        return f, "ObjectiveTrackerFrame"
    end
    f = QuestWatchFrame
    if type(f) == "table" and type(f.Hide) == "function" then
        return f, "QuestWatchFrame"
    end
    return nil, nil
end

-- Deliberately NOT latched behind a "done" flag. Another addon touching the tracker can
-- re-register its modules or re-show it, and a one-shot suppress could never recover -
-- that is exactly how a second tracker reappears mid-session.
function Blizzard:Suppress()
    local tracker = findTracker()
    if not tracker then return end

    silence(tracker)

    -- Not latched either, and for the same reason silence is not: Blizzard adds its modules as
    -- their files load, and another addon can add one back at any time.
    unmount(self, tracker)

    -- The sub-modules' own EVENTS are still deliberately NOT silenced, and must not be.
    -- Unregistering them is an insecure write to every one of Blizzard's tracker frames, which
    -- feed the quest POI system, and it is a different thing from taking them off the
    -- container's layout list above: a module that is not mounted still runs its handlers and
    -- still keeps its data, it is simply never laid out. Do not turn the unmount into that loop.
    --
    -- That is also why ShouldShowMawBuffs is still reachable from the scenario module's own
    -- UNIT_AURA handler, off the layout path entirely. It has never been the reported site - all
    -- eight of that report's errors came through LayoutContents - but if this comes back, that
    -- is where to look, and the unmount is not what failed.

    -- Hooking is the one part that must happen once, or every Suppress stacks another.
    -- Keyed on the frame rather than a boolean: only one of the two globals exists per
    -- flavor, but a flag cannot tell "already hooked this frame" from "hooked a different
    -- one".
    if self._hookedFrame ~= tracker then
        self._hookedFrame = tracker
        tracker:HookScript("OnShow", function(f)
            -- Hiding straight from this hook was followed by a blocked SetPassThroughButtons
            -- on a map pin, off a stack carrying none of our code. Deferred by a frame since.
            self._shows, self._lastShow = (self._shows or 0) + 1, GetTime()
            if self._hidePending then return end
            self._hidePending = true
            C_Timer.After(0, function()
                self._hidePending = nil
                if not f:IsShown() then return end
                if f.SetAlpha then f:SetAlpha(0) end
                f:Hide()
                -- Belt and braces: if a future build ever does protect it, the queued
                -- re-suppress still catches the frame when combat ends.
                if InCombatLockdown() then
                    local Events = ns:GetModule("Events")
                    if Events and Events.RunWhenOutOfCombat then
                        self._reSuppress = self._reSuppress or function() self:Suppress() end
                        Events:RunWhenOutOfCombat("eqot.blizzardSuppress", self._reSuppress)
                    end
                end
            end)
        end)
    end
end

-- Names the frame it resolved. This line is the standing regression check for the
-- double-tracker bug, and it reported "frame absent" on Classic while QuestWatchFrame was
-- live - a check reporting a comfortable answer is worse than no check.
-- The module count reads 0 on BOTH flavors now: Classic's frame has no .modules at all, where
-- retail's has been emptied by the unmount above. The frame NAME already separates the two, so
-- what the unmounted count adds is the other question - whether the unmount ran and removed
-- something, or ran and silently found nothing, which is what a renamed field would produce and
-- what the shape guard would swallow without a word.
-- The count itself moves with the patch, so read a change in it as Blizzard's, not a bug.
function Blizzard:DebugLine()
    local t, name = findTracker()
    if not t then return "blizzard tracker: no known tracker frame on this client" end
    local n = (type(t.modules) == "table") and #t.modules or 0
    local ago = self._lastShow and ("%.0fs ago"):format(GetTime() - self._lastShow) or "never"
    local shown = "hidden"
    if t:IsShown() then
        shown = self._hidePending and "SHOWN - hide pending" or "SHOWN - suppression lost"
    end
    return ("blizzard tracker: %s %s, %d modules (%d unmounted), hook %s | alpha %.2f | reshown %d, last %s"):format(
        name, shown,
        n, self._unmounted or 0, self._hookedFrame and "installed" or "missing",
        t:GetAlpha() or 0, self._shows or 0, ago)
end

function Blizzard:OnEnable()
    self:Suppress()

    local Events = ns:GetModule("Events")
    Events:On("PLAYER_ENTERING_WORLD", function() self:Suppress() end)
    Events:On("PLAYER_REGEN_ENABLED",  function() self:Suppress() end)
    Events:On("ADDON_LOADED", function(_, name)
        if name == "Blizzard_ObjectiveTracker" then self:Suppress() end
    end)
end
