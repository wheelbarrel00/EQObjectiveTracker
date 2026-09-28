-- luacheck: globals InCombatLockdown IsInInstance C_ChallengeMode WorldMapFrame
-- luacheck: globals hooksecurefunc C_Timer GetTime CreateFrame
--
-- Unit tests for the hide-when-no-quests rule and the opacity option, run against the
-- SHIPPED source rather than a copy. Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_visibility.lua
--
-- The cases that earn this file are the INTERLOCK, because it spans two files and each half is
-- harmless on its own:
--
--   1. The rule is tested LAST in shouldHide, so any other reason wins the label. If it moves
--      up, a combat hide starts reporting itself as an empty hide and the tracker renders
--      through every fight for nothing.
--   2. _eqotRenderWhileHidden is granted ONLY to the empty hide, because the render is what
--      counts the quests - a tracker hidden by this rule that stopped rendering could never see
--      the quest meant to bring it back, and would stay gone for the session.
--   3. questRows is NIL until a render has counted, which is not zero. Reading nil as zero hides
--      the tracker at every login, before the first render can say otherwise.
--
-- UI/Tracker.lua cannot be loaded whole without a frame stub, so its count and noteFocus are
-- sliced out by TEXT ANCHOR rather than by line number, which drifts. If an anchor stops
-- matching, fix the anchor here rather than deleting the test.

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
end

local function readFile(rel)
    local fh = assert(io.open(repoFile(rel), "r"))
    local src = fh:read("*a")
    fh:close()
    return src
end

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end

-- ---------------------------------------------------------------- UI/Visibility.lua, whole

local general, tracker, mods = {}, {}, {}
local disabled = {}
local ns = { Has = { MythicPlus = true } }
function ns:RegisterModule(n, t) mods[n] = t return t end
function ns:GetModule(n) return mods[n] end
function ns:IsModuleDisabled(name) return disabled[name] == true end
ns.Util = { Tooltip = function() return { Hide = function() end } end }

mods.DB = {
    General = function() return general end,
    Tracker = function() return tracker end,
}

local frame = {
    _shown = true, _alpha = 1,
    SetAlpha = function(self, a) self._alpha = a end,
    GetAlpha = function(self) return self._alpha end,
    Show     = function(self) self._shown = true end,
    Hide     = function(self) self._shown = false end,
    IsShown  = function(self) return self._shown end,
}

-- The regions the opacity option's hover test reads. Each answers IsMouseOver from a flag the
-- case sets, so "the mouse is over the quest rows" is two flags: the viewport AND the content.
local function region()
    return { visible = true, mouse = false,
             IsVisible   = function(self) return self.visible end,
             IsMouseOver = function(self) return self.mouse end }
end
frame.drag, frame.scenarioContainer, frame.eventsRegion = region(), region(), region()
frame.scroll, frame.content, frame.grip = region(), region(), region()
frame.eventsScroll = region()
frame.scroll.ScrollBar, frame.eventsScroll.ScrollBar = region(), region()
local REGIONS = { frame.drag, frame.scenarioContainer, frame.eventsRegion, frame.scroll,
                  frame.content, frame.grip, frame.eventsScroll, frame.scroll.ScrollBar,
                  frame.eventsScroll.ScrollBar }
-- Present so FadeLine can report the client supports the call, and counted so a case can prove
-- nothing ever exempts the tracker frame itself.
local frameIgnoreCalls = 0
frame.SetIgnoreParentAlpha = function() frameIgnoreCalls = frameIgnoreCalls + 1 end

local refreshes = 0
local trackerLocked = false
mods.Tracker = {
    frame = frame,
    Refresh = function() refreshes = refreshes + 1 end,
    SetScrollInputSuspended = function() end,
    IsLocked = function() return trackerLocked end,
}
mods.ItemButtons = {
    HasSecureButtons  = function() return false end,
    Locked            = function() return false end,
    SetMouseSuspended = function() end,
    buttons           = {},
}
mods.Events = { On = function() end }

-- lockdown is the CLIENT's lockdown. V._inCombat is the event flag, which PLAYER_REGEN_DISABLED
-- sets a moment BEFORE the lockdown starts - the window the item button exemption relies on.
local lockdown = false
InCombatLockdown = function() return lockdown end
IsInInstance     = function() return false end
C_ChallengeMode  = { IsChallengeModeActive = function() return false end }
WorldMapFrame    = { IsShown = function() return false end }
hooksecurefunc   = function() end
C_Timer          = { After = function(_, fn) fn() end }

local now = 100
GetTime = function() return now end
local created = {}
CreateFrame = function()
    local d = { _shown = true, _scripts = {} }
    function d:SetScript(k, fn) self._scripts[k] = fn end
    function d:Show() self._shown = true end
    function d:Hide() self._shown = false end
    function d:IsShown() return self._shown end
    created[#created + 1] = d
    return d
end

local chunk = assert(loadstring(readFile("UI/Visibility.lua"), "@UI/Visibility.lua"))
chunk("EQObjectiveTracker", ns)
local V = mods.Visibility
assert(V, "UI/Visibility.lua did not register a Visibility module")
-- ApplyFade and SetFocus answer only once OnEnable has run, which nothing here does until the
-- combat events case, so the module starts out marked the way it is in game.
V._started = true

-- The count and the first-count guard are file-local upvalues, so they survive between cases
-- and a case that happens to set the same number twice would short-circuit and prove nothing.
-- SetQuestRows(nil) is the honest way back to the login state and restores both, which is the
-- state the first cases below are about. Cleared BEFORE the frame flags, because it can
-- re-apply and paint the frame on its way past.
local function reset(overrides)
    general = {}
    tracker = {}
    disabled = {}
    for k, v in pairs(overrides or {}) do general[k] = v end
    V:SetQuestRows(nil)
    frame._shown, frame._alpha = true, 1
    frame._eqotHidden, frame._eqotUserHidden = nil, nil
    frame._eqotRenderWhileHidden, frame._eqotPendingRender = nil, nil
    V._inCombat = nil
    refreshes = 0
end

-- Gets past the first-count guard the way a login render does, so a case about the steady state
-- is not accidentally testing the cold-log protection instead. Two calls: the first spends the
-- guard, the second is the one that counts.
local function settle(n)
    V:SetQuestRows(n)
    V:SetQuestRows(n)
end

-- A login has never counted. nil is not zero, and reading it as zero hides every tracker at
-- every login before the first render has had a chance to say otherwise.
reset({ hideWhenNoQuests = true })
V:Apply()
ok(frame._alpha == 1, "an uncounted tracker stays visible at login")
ok(V:QuestRowsLine():find("never counted", 1, true) ~= nil,
   "the status line says never counted rather than 0, got: " .. V:QuestRowsLine())

reset({ hideWhenNoQuests = false })
settle(0)
V:Apply()
ok(frame._alpha == 1, "an empty tracker stays visible while the rule is off")

reset({ hideWhenNoQuests = true })
settle(0)
ok(frame._alpha == 0, "an empty tracker is hidden while the rule is on")
ok(frame._shown == false, "and it is hidden for real rather than only faded")
ok(frame._eqotRenderWhileHidden == true,
   "the empty hide keeps rendering underneath itself, or it can never come back")
ok(V:IsRuleHiding() == true, "the empty hide reports as a rule hide")

V:SetQuestRows(1)
ok(frame._alpha == 1, "one quest brings it back")
ok(frame._eqotRenderWhileHidden == nil, "and the render exception goes with it")

-- Any other reason wins the label, so the render exception is NOT granted to a combat hide.
reset({ hideWhenNoQuests = true, hideInCombat = true })
settle(0)
V._inCombat = true
V:Apply()
ok(frame._alpha == 0, "combat hides it")
ok(frame._eqotRenderWhileHidden == nil,
   "a combat hide does not take the empty rule exception")

reset({ hideWhenNoQuests = true })
frame._eqotUserHidden = true
settle(0)
V:Apply()
ok(frame._eqotRenderWhileHidden == nil,
   "a tracker the player switched off does not keep rendering either")

-- Combat over an empty log is the path that would otherwise strand the tracker: Render stopped
-- during the fight, so the count is frozen, and only a flushed pending render unfreezes it.
reset({ hideWhenNoQuests = true, hideInCombat = true })
settle(0)
V._inCombat = true
V:Apply()
frame._eqotPendingRender = true
V._inCombat = false
V:Apply()
ok(frame._eqotRenderWhileHidden == true, "leaving combat hands the exception back")
ok(refreshes > 0, "and flushes the pending render, or the count stays frozen at zero")

-- Only the zero boundary can change what the rule answers
local realApply = V.Apply
local applies = 0
local function spy()
    applies = 0
    V.Apply = function(self) applies = applies + 1 return realApply(self) end
end
local function unspy() V.Apply = realApply end

reset({ hideWhenNoQuests = true })
V:SetQuestRows(4)
spy()
V:SetQuestRows(3)
ok(applies == 0, "a log going from four quests to three re-applies nothing")
V:SetQuestRows(0)
ok(applies == 1, "crossing to zero re-applies")
V:SetQuestRows(2)
ok(applies == 2, "crossing back off zero re-applies")
unspy()

reset({ hideWhenNoQuests = false })
V:SetQuestRows(3)
spy()
V:SetQuestRows(0)
ok(applies == 0, "with the rule off, crossing zero re-applies nothing")
unspy()

reset({ hideWhenNoQuests = true })
V:SetQuestRows(7)
ok(V:QuestRowsLine():find("quest rows 7", 1, true) ~= nil,
   "the status line names the count, got: " .. V:QuestRowsLine())

-- Safe mode. This is render-driven, so the OnEnable gate never reaches it: without its own
-- check, /eqot disable all hides the tracker on the first empty feed and nothing is left to
-- ever call Apply again, blanking the one thing a taint bisection needs to look at.
-- Settled FIRST, with the module enabled, or the first-count guard would decline this zero on
-- its own and the case would pass with the disable check deleted.
reset({ hideWhenNoQuests = true })
settle(3)
disabled.Visibility = true
V:SetQuestRows(0)
ok(frame._alpha == 1 and frame._shown == true,
   "a disabled Visibility module does not hide the tracker from the render path")
ok(V:QuestRowsLine():find("quest rows 3", 1, true) ~= nil,
   "and does not record the count either, got: " .. V:QuestRowsLine())
disabled.Visibility = nil

-- A cold quest log answers a real zero that reads exactly like an empty one, and Tracker
-- renders at PLAYER_LOGIN before it has streamed in.
reset({ hideWhenNoQuests = true })
V:SetQuestRows(0)
ok(frame._alpha == 1, "the first count of a session may not hide the tracker")
ok(V:QuestRowsLine():find("never counted", 1, true) ~= nil,
   "and that zero is dropped rather than stored, got: " .. V:QuestRowsLine())
V:SetQuestRows(0)
ok(frame._alpha == 0, "a genuinely empty log still hides on the next render")

reset({ hideWhenNoQuests = true })
V:SetQuestRows(5)
ok(frame._alpha == 1, "a login with a full log stays visible")
V:SetQuestRows(0)
ok(frame._alpha == 0, "and hides once the log really empties")

-- The secure latch. Once a scenario spell button is adopted, setVisible drops a Show in combat
-- rather than erroring, which leaves the frame off screen with no reason recorded against it.
reset({ hideWhenNoQuests = true })
V:SetQuestRows(1)
V:SetQuestRows(0)
mods.ItemButtons.Locked = function() return true end
V:SetQuestRows(2)
ok(frame._shown == false, "a Show refused by the secure lock leaves the frame off screen")
ok(frame._eqotRenderWhileHidden == true,
   "and the render exception is kept, or the count freezes until the fight ends")
mods.ItemButtons.Locked = function() return false end
V:Apply()
ok(frame._shown == true, "combat ending shows it")
ok(frame._eqotRenderWhileHidden == nil, "and drops the exception")

-- Coming back on screen after a hidden render: item buttons hid rather than guessing at an
-- anchor they could not resolve, so one more pass has to be asked for.
reset({ hideWhenNoQuests = true })
V:SetQuestRows(1)
V:SetQuestRows(0)
refreshes = 0
V:SetQuestRows(3)
ok(frame._alpha == 1, "the tracker comes back")
ok(refreshes > 0, "and asks for one more render, or a quest item button never draws")

-- --------------------------------------------------------------- the opacity option
--
-- What earns this block: a faded tracker must still HIDE (alpha 0 wins), the hover test must
-- count only what is drawn, the focused quest's row must be the one exempt and move with focus,
-- and the focused quest's secure item button must never be touched while the client is in
-- combat lockdown. The driver is stepped by hand, one OnUpdate at a time, on a clock that only
-- moves when a case moves it.

local function exemptable(name)
    local r = { name = name, ignore = false, lockedCalls = 0 }
    function r:SetIgnoreParentAlpha(v)
        self.ignore = v and true or false
        if lockdown then self.lockedCalls = self.lockedCalls + 1 end
    end
    return r
end

local function near(a, b) return math.abs((a or -1) - b) < 0.001 end

local function fadeReset(t)
    reset()
    for k, v in pairs(t or {}) do tracker[k] = v end
    for _, r in ipairs(REGIONS) do r.mouse, r.visible = false, true end
    trackerLocked, lockdown = false, false
    mods.ItemButtons.buttons = {}
    local okFocus, errF = pcall(V.SetFocus, V, nil, nil)
    ok(okFocus, "SetFocus does not raise: " .. tostring(errF))
    local okApply, err = pcall(V.Apply, V)
    ok(okApply, "Apply does not raise: " .. tostring(err))
end

-- Advances the clock and runs the driver once, the way the client would on the next frame. A
-- driver that is not shown gets no OnUpdate, exactly as a hidden frame gets none in game.
local function step(dt)
    now = now + dt
    local d = created[1]
    if d and d._shown and d._scripts.OnUpdate then d._scripts.OnUpdate(d, dt) end
end

local function driverRunning() return created[1] ~= nil and created[1]._shown end

local function overRows(on) frame.scroll.mouse, frame.content.mouse = on, on end

-- Every case below calls the module directly, so the whole block runs under one pcall. A raise
-- then fails the run with a summary line, where an abort would read to a battery as CRASHED
-- rather than caught.
local okOpacity, errOpacity = pcall(function()
print("== at the default opacity nothing changes and nothing runs")
fadeReset()
ok(frame._alpha == 1, "a shown tracker is solid: " .. tostring(frame._alpha))
ok(not driverRunning(), "and no driver is running")
do
    local row = exemptable("row")
    V:SetFocus(row, 101)
    ok(row.ignore == false, "and the focused row is not exempt, since nothing is faded")
end

print("== a faded tracker rests at its level")
fadeReset({ trackerAlpha = 0.4 })
ok(near(frame._alpha, 0.4), "shown at 0.4: " .. tostring(frame._alpha))
ok(driverRunning(), "the driver runs while it is faded with mouseover on")

print("== the level is floored, and a zero is a real zero rather than a missing value")
for _, c in ipairs({ { 0.02, 0.1 }, { 0, 0.1 }, { 0.1, 0.1 }, { 0.55, 0.55 }, { 1.5, 1 } }) do
    fadeReset({ trackerAlpha = c[1] })
    ok(near(frame._alpha, c[2]), ("trackerAlpha %s shows as %s: %s"):format(
        tostring(c[1]), tostring(c[2]), tostring(frame._alpha)))
end
fadeReset({ trackerAlpha = "junk" })
ok(frame._alpha == 1, "a value that is not a number reads as the default")

print("== a hide still wins over the fade")
fadeReset({ trackerAlpha = 0.4 })
frame._eqotUserHidden = true
V:Apply()
ok(frame._alpha == 0, "hidden is alpha 0, not the faded level: " .. tostring(frame._alpha))
ok(not driverRunning(), "and the driver stops with it")
frame._eqotUserHidden = nil
V:Apply()
ok(near(frame._alpha, 0.4), "shown again at the faded level: " .. tostring(frame._alpha))

print("== hovering the rows brings it up, animated rather than snapped")
fadeReset({ trackerAlpha = 0.4 })
overRows(true)
step(0.05)
ok(frame._alpha > 0.4 and frame._alpha < 1, "one frame in it is on its way: " .. frame._alpha)
step(0.05) step(0.05) step(0.05)
ok(frame._alpha == 1, "and a fifth of a second later it is solid: " .. frame._alpha)

print("== only what is drawn counts as hover")
local drawn = {
    { "the viewport with no content under the cursor", function() frame.scroll.mouse = true end, false },
    { "content scrolled outside the viewport", function() frame.content.mouse = true end, false },
    { "the header strip", function() frame.drag.mouse = true end, true },
    { "the scenario panel", function() frame.scenarioContainer.mouse = true end, true },
    { "the world quest region", function() frame.eventsRegion.mouse = true end, true },
    { "the quest scroll bar", function() frame.scroll.ScrollBar.mouse = true end, true },
    { "the world quest scroll bar", function() frame.eventsScroll.ScrollBar.mouse = true end, true },
    { "the resize grip while unlocked", function() frame.grip.mouse = true end, true },
    { "the resize grip while locked",
      function() frame.grip.mouse = true; trackerLocked = true end, false },
    { "a hidden world quest region",
      function() frame.eventsRegion.mouse = true; frame.eventsRegion.visible = false end, false },
}
for _, c in ipairs(drawn) do
    fadeReset({ trackerAlpha = 0.4 })
    c[2]()
    for _ = 1, 10 do step(0.05) end
    if c[3] then
        ok(frame._alpha == 1, c[1] .. " brings it up: " .. frame._alpha)
    else
        ok(near(frame._alpha, 0.4), c[1] .. " leaves it faded: " .. frame._alpha)
    end
end

print("== leaving holds it up for a second, then fades back")
fadeReset({ trackerAlpha = 0.4 })
overRows(true)
for _ = 1, 6 do step(0.05) end
overRows(false)
step(0.05)
-- Counted in whole ticks from the frame that noticed the mouse leave, so neither reading sits
-- on the one-second boundary where float drift could put it either side.
for _ = 1, 19 do step(0.05) end
ok(frame._alpha == 1, "still solid 0.95s after leaving: " .. frame._alpha)
step(0.1)
ok(frame._alpha > 0.4 and frame._alpha < 1, "fading 1.05s after leaving: " .. frame._alpha)
for _ = 1, 10 do step(0.05) end
ok(near(frame._alpha, 0.4), "and back at its level: " .. frame._alpha)

print("== with mouseover off, hover does nothing and nothing polls")
fadeReset({ trackerAlpha = 0.4, trackerAlphaHover = false })
ok(not driverRunning(), "no driver runs")
overRows(true)
for _ = 1, 10 do step(0.05) end
ok(near(frame._alpha, 0.4), "the mouse over the rows leaves it faded: " .. frame._alpha)

print("== a setting moved while the mouse is over the rows takes effect at once")
fadeReset()
overRows(true)
tracker.trackerAlpha = 0.5
V:ApplyFade()
ok(frame._alpha == 1, "the mouse over it holds it solid through the change: " .. frame._alpha)
ok(driverRunning(), "moving off 100 starts the driver without waiting for a visibility change")
overRows(false)
V:ApplyFade()
ok(near(frame._alpha, 0.5), "and without the mouse the new level shows straight away: "
   .. frame._alpha)
tracker.trackerAlpha = 1
V:ApplyFade()
ok(frame._alpha == 1, "back to 100 is solid")
ok(not driverRunning(), "and stops the driver")

-- Inside the hold the tracker is still solid, and a setting moved then must not wait it out.
fadeReset({ trackerAlpha = 0.4 })
overRows(true)
for _ = 1, 6 do step(0.05) end
overRows(false)
step(0.05)
step(0.05)
ok(frame._alpha == 1, "just after leaving it is still held solid")
tracker.trackerAlpha = 0.6
V:ApplyFade()
ok(near(frame._alpha, 0.6), "a new level lands at once rather than after the hold: " .. frame._alpha)

fadeReset({ trackerAlpha = 0.4 })
frame._eqotUserHidden = true
V:Apply()
tracker.trackerAlpha = 0.7
V:ApplyFade()
ok(frame._alpha == 0, "moving the slider does not bring a hidden tracker back: " .. frame._alpha)
frame._eqotUserHidden = nil

print("== the focused row is exempt, and the exemption moves with focus")
fadeReset({ trackerAlpha = 0.4 })
do
    local a, b = exemptable("a"), exemptable("b")
    V:SetFocus(a, 101)
    ok(a.ignore == true, "the focused row ignores the tracker's alpha")
    V:SetFocus(b, 102)
    ok(a.ignore == false, "focus moving clears the old row")
    ok(b.ignore == true, "and exempts the new one")
    V:SetFocus(nil, nil)
    ok(b.ignore == false, "no focused row on screen clears it")

    fadeReset({ trackerAlpha = 0.4, trackerAlphaFocus = false })
    V:SetFocus(a, 101)
    ok(a.ignore == false, "with the option off nothing is exempt")

    fadeReset({ trackerAlpha = 0.4 })
    V:SetFocus(a, 101)
    tracker.trackerAlpha = 1
    V:ApplyFade()
    ok(a.ignore == false, "moving back to 100 clears the exemption")
    ok(frameIgnoreCalls == 0, "and nothing ever exempts the tracker frame itself")
end

print("== a hide drops the exemption, or the focused quest stays on screen alone")
fadeReset({ trackerAlpha = 0.4 })
do
    local row, btn = exemptable("row"), exemptable("button")
    mods.ItemButtons.buttons[101] = btn
    V:SetFocus(row, 101)
    ok(row.ignore and btn.ignore, "both are exempt on a shown tracker")
    frame._eqotUserHidden = true
    V:Apply()
    ok(row.ignore == false, "hiding clears the row")
    ok(btn.ignore == false, "and the item button")
    frame._eqotUserHidden = nil
    V:Apply()
    ok(row.ignore and btn.ignore, "showing it again puts both back without a render")

    -- A render can run while hidden, for the empty rule. Its report must not exempt anything.
    frame._eqotUserHidden = true
    V:Apply()
    V:SetFocus(row, 101)
    ok(row.ignore == false, "a render reporting focus while hidden exempts nothing")
    frame._eqotUserHidden = nil
end

print("== the item button is exempt out of combat only, and never touched in lockdown")
fadeReset({ trackerAlpha = 0.4 })
do
    local row, btn = exemptable("row"), exemptable("button")
    mods.ItemButtons.buttons[101] = btn
    V:SetFocus(row, 101)
    ok(btn.ignore == true, "out of combat the focused quest's button is exempt")

    -- PLAYER_REGEN_DISABLED, which fires before the lockdown starts
    V._inCombat = true
    V:Apply()
    ok(btn.ignore == false, "combat starting drops the button's exemption")
    ok(row.ignore == true, "and keeps the row's, which is not secure")

    lockdown = true
    local other = exemptable("other")
    mods.ItemButtons.buttons[102] = other
    V:SetFocus(exemptable("row2"), 102)
    V:SetFocus(row, 101)
    V:ApplyFade()
    V:Apply()
    ok(btn.lockedCalls == 0 and other.lockedCalls == 0,
       "no button is touched while the lockdown is up: " .. btn.lockedCalls .. ", " .. other.lockedCalls)
    ok(btn.ignore == false and other.ignore == false, "and none is exempt")

    -- PLAYER_REGEN_ENABLED, which fires after it ends
    lockdown = false
    V._inCombat = false
    V:Apply()
    ok(btn.ignore == true, "combat ending exempts the focused quest's button again")
    ok(other.ignore == false, "and only that one")
end

print("== a client without the call degrades rather than raising")
fadeReset({ trackerAlpha = 0.4 })
do
    local bare = {}
    local okCall = pcall(V.SetFocus, V, bare, 101)
    ok(okCall, "a row with no SetIgnoreParentAlpha does not raise")
    local saved = frame.SetIgnoreParentAlpha
    frame.SetIgnoreParentAlpha = nil
    ok(V:FadeLine():find("ignore parent alpha unsupported", 1, true) ~= nil,
       "and the status line says the client cannot do it: " .. V:FadeLine())
    frame.SetIgnoreParentAlpha = saved
end

-- Safe mode, or /eqot enable before the reload it asks for. Either way OnEnable has not run, so
-- no combat listener exists to drop the item button's exemption before a lockdown.
print("== a module OnEnable never started leaves the fade alone")
fadeReset()
V._started = nil
tracker.trackerAlpha = 0.4
V:ApplyFade()
ok(frame._alpha == 1, "ApplyFade does nothing until OnEnable has run: " .. tostring(frame._alpha))
ok(not driverRunning(), "nor starts the driver")
do
    local row, btn = exemptable("row"), exemptable("button")
    mods.ItemButtons.buttons[101] = btn
    V:SetFocus(row, 101)
    ok(row.ignore == false and btn.ignore == false, "and a render reporting focus exempts nothing")
    -- Apply is not gated (/eqot toggle and the General tab's hide rules reach it), so the focus
    -- refused above must not have been kept for it.
    V:Apply()
    ok(row.ignore == false and btn.ignore == false,
       "nor does a later Apply exempt a focus reported before OnEnable ran")
end
V._started = true

print("== a live /eqot disable waits for its reload")
fadeReset()
disabled.Visibility = true
tracker.trackerAlpha = 0.4
V:ApplyFade()
ok(near(frame._alpha, 0.4), "the live switch does not gate the fade: " .. tostring(frame._alpha))
do
    local row = exemptable("row")
    V:SetFocus(row, 101)
    ok(row.ignore == true, "nor the exemption, so no row is left frozen with it")
end
disabled.Visibility = nil

print("== the status line")
fadeReset({ trackerAlpha = 0.4 })
do
    local row = exemptable("row")
    mods.ItemButtons.buttons[101] = exemptable("button")
    V:SetFocus(row, 101)
    local s = V:FadeLine()
    ok(s:find("opacity 0.40, mouseover on, focused quest on", 1, true) ~= nil,
       "names the three settings: " .. s)
    ok(s:find("now 0.40, over false, driver running", 1, true) ~= nil, "the live state: " .. s)
    ok(s:find("exempt quest 101, item button yes", 1, true) ~= nil, "and what is exempt: " .. s)
    ok(s:find("ignore parent alpha supported", 1, true) ~= nil, "and that the client can: " .. s)
end
-- Held up by the mouse, so the live alpha and the setting differ. With both at 0.40 a line
-- printing the setting in the live slot read the same, and a report could not tell "set to fade"
-- from "stuck faded".
fadeReset({ trackerAlpha = 0.4 })
overRows(true)
for _ = 1, 6 do step(0.05) end
ok(V:FadeLine():find("opacity 0.40, mouseover on", 1, true) ~= nil
   and V:FadeLine():find("now 1.00, over true", 1, true) ~= nil,
   "the live alpha is its own field, apart from the setting: " .. V:FadeLine())

-- One on and one off, so a line printing either setting in the other's slot reads differently.
fadeReset({ trackerAlpha = 0.4, trackerAlphaHover = false })
ok(V:FadeLine():find("mouseover off, focused quest on", 1, true) ~= nil,
   "each option reads its own setting: " .. V:FadeLine())
ok(V:FadeLine():find("driver idle", 1, true) ~= nil, "with the driver idle")
fadeReset({ trackerAlpha = 0.4, trackerAlphaFocus = false })
ok(V:FadeLine():find("mouseover on, focused quest off", 1, true) ~= nil,
   "and the other way round: " .. V:FadeLine())

print("== the status line in the states that exempt nothing")
fadeReset()
do
    mods.ItemButtons.buttons[101] = exemptable("button")
    V:SetFocus(exemptable("row"), 101)
    local s = V:FadeLine()
    ok(s:find("exempt quest none, item button no | ignore parent alpha supported", 1, true) ~= nil,
       "at 100 nothing reads as exempt, and support is the client's answer: " .. s)
end
fadeReset({ trackerAlpha = 0.4 })
do
    mods.ItemButtons.buttons[101] = exemptable("button")
    V:SetFocus(exemptable("row"), 101)
    V._inCombat = true
    V:Apply()
    local s = V:FadeLine()
    ok(s:find("exempt quest 101, item button no", 1, true) ~= nil,
       "in combat the row is exempt and the button is not: " .. s)
    V._inCombat = nil
end
fadeReset({ trackerAlpha = 0.4 })
ok(V:FadeLine():find("exempt quest none, item button no | ignore parent alpha supported", 1, true) ~= nil,
   "no focus reads none, and the client still supports the call: " .. V:FadeLine())
-- The mouse over the rows, where hover cannot act, so a settle that recorded it anyway reads true.
fadeReset()
overRows(true)
V:ApplyFade()
ok(V:FadeLine():find("over false", 1, true) ~= nil,
   "at 100 the mouse is not recorded as over: " .. V:FadeLine())
fadeReset({ trackerAlpha = 0.4, trackerAlphaHover = false })
overRows(true)
V:ApplyFade()
ok(V:FadeLine():find("over false", 1, true) ~= nil,
   "nor with mouseover off: " .. V:FadeLine())

print("== once a secure button exists, alpha IS the hide, and the fade must respect it")
fadeReset({ trackerAlpha = 0.4 })
do
    mods.ItemButtons.HasSecureButtons = function() return true end
    local row, btn = exemptable("row"), exemptable("button")
    mods.ItemButtons.buttons[101] = btn
    V:SetFocus(row, 101)
    frame._eqotUserHidden = true
    V:Apply()
    ok(frame._shown == true and frame._alpha == 0,
       "hidden by alpha with the frame still shown: " .. tostring(frame._shown) .. " " .. frame._alpha)
    ok(row.ignore == false and btn.ignore == false, "and the hide drops both exemptions")
    tracker.trackerAlpha = 0.6
    V:ApplyFade()
    ok(frame._alpha == 0, "moving the slider does not bring an alpha-hidden tracker back: " .. frame._alpha)
    ok(not driverRunning(), "nor start the driver under it")
    ok(row.ignore == false, "nor exempt the focused row over it")
    V:SetFocus(row, 101)
    ok(row.ignore == false and btn.ignore == false,
       "and a render reporting focus while alpha-hidden exempts nothing")
    frame._eqotUserHidden = nil
    V:Apply()
    ok(near(frame._alpha, 0.6) and row.ignore and btn.ignore,
       "showing it again restores the level and both exemptions: " .. frame._alpha)
    mods.ItemButtons.HasSecureButtons = function() return false end
end

print("== a level or switch set from the options still answers the mouse")
fadeReset()
tracker.trackerAlpha = 0.4
V:ApplyFade()
ok(driverRunning(), "moving off 100 starts the driver")
overRows(true)
for _ = 1, 10 do step(0.05) end
ok(frame._alpha == 1, "and hovering brings it up: " .. frame._alpha)
fadeReset({ trackerAlpha = 0.4, trackerAlphaHover = false })
tracker.trackerAlphaHover = true
V:ApplyFade()
ok(driverRunning(), "switching mouseover on starts it too")

print("== the animation never leaves the range between the level and 1")
fadeReset({ trackerAlpha = 0.1 })
do
    local lo, hi = 1, 0
    local function watch(n)
        for _ = 1, n do
            step(0.05)
            lo, hi = math.min(lo, frame._alpha), math.max(hi, frame._alpha)
        end
    end
    overRows(true)
    watch(10)
    overRows(false)
    watch(40)
    ok(hi <= 1 and lo >= 0.1 - 0.001, ("stays within 0.1 and 1: %.3f to %.3f"):format(lo, hi))
end

print("== a scroll bar under the lowercase key counts too")
fadeReset({ trackerAlpha = 0.4 })
do
    local bar = frame.eventsScroll.ScrollBar
    frame.eventsScroll.ScrollBar, frame.eventsScroll.scrollBar = nil, bar
    bar.mouse = true
    for _ = 1, 10 do step(0.05) end
    ok(frame._alpha == 1, "a scrollBar-keyed bar brings it up: " .. frame._alpha)
    frame.eventsScroll.ScrollBar, frame.eventsScroll.scrollBar = bar, nil
end

print("== the combat events drive the button exemption, in the order the lockdown needs")
do
    local handlers = {}
    mods.Events.On = function(_, e, fn) handlers[e] = fn end
    fadeReset({ trackerAlpha = 0.4 })
    V._started = nil
    local okEnable, err = pcall(V.OnEnable, V)
    ok(okEnable, "OnEnable runs: " .. tostring(err))
    ok(V._started == true, "and marks the module started, which ApplyFade and SetFocus wait for")
    local row, btn = exemptable("row"), exemptable("button")
    mods.ItemButtons.buttons[101] = btn
    V:SetFocus(row, 101)
    ok(btn.ignore == true, "out of combat the button is exempt")
    ok(handlers.PLAYER_REGEN_DISABLED ~= nil and handlers.PLAYER_REGEN_ENABLED ~= nil,
       "both combat events are listened for")
    if handlers.PLAYER_REGEN_DISABLED then handlers.PLAYER_REGEN_DISABLED() end
    ok(btn.ignore == false, "PLAYER_REGEN_DISABLED drops the button BEFORE the lockdown starts")
    lockdown = true
    V:SetFocus(row, 101)
    V:ApplyFade()
    ok(btn.lockedCalls == 0, "so nothing touches it once the lockdown is up: " .. btn.lockedCalls)
    lockdown = false
    if handlers.PLAYER_REGEN_ENABLED then handlers.PLAYER_REGEN_ENABLED() end
    ok(btn.ignore == true, "PLAYER_REGEN_ENABLED exempts it again")
    mods.Events.On = function() end
end

-- Belt and braces. The event order normally drops the button before the lockdown, but a lockdown
-- that starts with it still exempt must still get no call on it.
print("== a render in lockdown never touches a secure button, whatever the event order")
fadeReset({ trackerAlpha = 0.4 })
do
    local row, btn, other = exemptable("row"), exemptable("button"), exemptable("other")
    mods.ItemButtons.buttons[101], mods.ItemButtons.buttons[102] = btn, other
    V:SetFocus(row, 101)
    ok(btn.ignore == true, "out of combat the button is exempt")
    lockdown = true
    V:SetFocus(row, 101)
    V:ApplyFade()
    V:Apply()
    V:SetFocus(exemptable("row2"), 102)
    ok(btn.lockedCalls == 0 and other.lockedCalls == 0,
       "nothing touches a button in lockdown, even as focus moves: "
       .. btn.lockedCalls .. ", " .. other.lockedCalls)
    lockdown = false
    V:SetFocus(exemptable("row2"), 102)
    ok(btn.ignore == false and other.ignore == true,
       "and the first render after it moves the exemption to the new button")
end

-- The quest list's own bar under the lowercase key. UI/Tracker.lua reads both keys on f.scroll too,
-- and the case above only lowercases the world quest list's.
print("== the quest list's scroll bar under the lowercase key counts too")
fadeReset({ trackerAlpha = 0.4 })
do
    local bar = frame.scroll.ScrollBar
    frame.scroll.ScrollBar, frame.scroll.scrollBar = nil, bar
    bar.mouse = true
    for _ = 1, 10 do step(0.05) end
    ok(frame._alpha == 1, "a scrollBar-keyed quest list bar brings it up: " .. frame._alpha)
    frame.scroll.ScrollBar, frame.scroll.scrollBar = bar, nil
end

-- leftAt is only cleared by settle, so a leave that kept the FIRST leave's time would give every
-- later leave in the session no hold at all.
print("== a second mouse-leave gets its own hold")
fadeReset({ trackerAlpha = 0.4 })
overRows(true)
for _ = 1, 6 do step(0.05) end
overRows(false)
for _ = 1, 40 do step(0.05) end
ok(near(frame._alpha, 0.4), "the first leave has faded back: " .. frame._alpha)
overRows(true)
for _ = 1, 6 do step(0.05) end
overRows(false)
step(0.05)
for _ = 1, 19 do step(0.05) end
ok(frame._alpha == 1, "still solid 0.95s after the SECOND leave: " .. frame._alpha)

-- The row's exemption follows the SETTING, never the live alpha. A render while the mouse holds
-- the tracker at full must still exempt it, or it fades with the rest once the mouse leaves.
print("== a render while the mouse holds the tracker up still exempts the focused row")
fadeReset({ trackerAlpha = 0.4 })
do
    local row = exemptable("row")
    overRows(true)
    for _ = 1, 6 do step(0.05) end
    V:SetFocus(row, 101)
    ok(row.ignore == true, "exempt while the mouse holds it at full")
    overRows(false)
    for _ = 1, 40 do step(0.05) end
    ok(near(frame._alpha, 0.4) and row.ignore == true,
       "and still exempt once the tracker has faded back: " .. frame._alpha)
end

-- Rows are not secure. A toggle or the map opening mid-fight hides by alpha, and the row must
-- drop its exemption then or it floats alone over an invisible tracker.
print("== a hide during the lockdown still drops the focused row")
fadeReset({ trackerAlpha = 0.4 })
do
    mods.ItemButtons.HasSecureButtons = function() return true end
    local row, btn = exemptable("row"), exemptable("button")
    mods.ItemButtons.buttons[101] = btn
    V:SetFocus(row, 101)
    V._inCombat = true
    V:Apply()
    lockdown = true
    frame._eqotUserHidden = true
    V:Apply()
    ok(frame._alpha == 0 and row.ignore == false,
       "a hide in lockdown drops the row's exemption: " .. tostring(row.ignore))
    ok(btn.lockedCalls == 0 and btn.ignore == false, "and never touches the secure button")
    frame._eqotUserHidden = nil
    lockdown = false
    V._inCombat = nil
    V:Apply()
    mods.ItemButtons.HasSecureButtons = function() return false end
end

-- A /reload mid-fight never sees PLAYER_REGEN_DISABLED, so the client's own lockdown is all
-- that says combat is up.
print("== the client lockdown alone counts as combat")
reset({ hideInCombat = true })
settle(2)
lockdown = true
V:Apply()
ok(frame._alpha == 0, "combat with no PLAYER_REGEN_DISABLED seen still hides it: " .. frame._alpha)
lockdown = false
V:Apply()
ok(frame._alpha == 1, "and it comes back once the lockdown ends: " .. frame._alpha)

fadeReset({ trackerAlpha = 0.02 })
ok(V:FadeLine():find("fade: opacity 0.10,", 1, true) ~= nil,
   "the status prints the floored level the tracker uses: " .. V:FadeLine())

ok(#created == 1, "one driver frame for the whole session, reused: " .. #created)
fadeReset()
end)
ok(okOpacity, "the opacity cases ran to the end without raising: " .. tostring(errOpacity))

-- ------------------------------------------------------- UI/Tracker.lua's count, by anchor

local tsrc = readFile("UI/Tracker.lua")
local FROM = "    local questRows = 0"
local TO   = "    local y        = 0"
local from, to = tsrc:find(FROM, 1, true), tsrc:find(TO, 1, true)
assert(from, "anchor not found in UI/Tracker.lua: " .. FROM)
assert(to,   "anchor not found in UI/Tracker.lua: " .. TO)
assert(to > from, "anchors are out of order in UI/Tracker.lua")

-- Render's EARLY RETURN, the other half of the interlock. Visibility only SETS the exception;
-- this is the code that has to honour it, and it lives in a different file. Without this slice
-- the whole guard can be deleted from Tracker:Render and every assertion above still passes,
-- while the shipped tracker hides on an empty log and never renders again.
local GFROM = "    -- Nothing on screen to lay out"
local GTO   = "    f._eqotPendingRender = nil"
local gfrom, gto = tsrc:find(GFROM, 1, true), tsrc:find(GTO, 1, true)
assert(gfrom, "anchor not found in UI/Tracker.lua: " .. GFROM)
assert(gto,   "anchor not found in UI/Tracker.lua: " .. GTO)
assert(gto > gfrom, "render-guard anchors are out of order in UI/Tracker.lua")

-- Returns "ran" when the render would proceed, nil when it bailed out early.
-- string.char(10) rather than an escape: this file is written by tooling that has been
-- seen to collapse a backslash-n, which turns the line below into an unfinished string.
local NL = string.char(10)
local renderGuard = assert(loadstring(
    "return function(f)" .. NL .. tsrc:sub(gfrom, gto - 1) .. NL .. "return 'ran' end",
    "@UI/Tracker.lua render guard"))()

local function guardFrame(shown, hidden, exception)
    return { _shown = shown, _eqotHidden = hidden, _eqotRenderWhileHidden = exception,
             IsShown = function(self) return self._shown end }
end

local gf = guardFrame(true, nil, nil)
ok(renderGuard(gf) == "ran", "a visible tracker renders")

gf = guardFrame(false, true, nil)
ok(renderGuard(gf) == nil, "a hidden tracker does not render")
ok(gf._eqotPendingRender == true, "and records that a render is owed")

gf = guardFrame(false, true, true)
ok(renderGuard(gf) == "ran",
   "a tracker hidden by the empty rule KEEPS rendering, or the count can never leave zero")

-- The alpha path: once a secure button is armed the frame stays shown and only _eqotHidden says
-- it is off screen, so the guard has to read both.
gf = guardFrame(true, true, nil)
ok(renderGuard(gf) == nil, "an alpha-hidden tracker does not render either")
gf = guardFrame(true, true, true)
ok(renderGuard(gf) == "ran", "unless the empty rule granted the exception")

local tchunk = assert(loadstring(
    "local ns, Sections, Popups, QUEST_PROVIDER = ...\nreturn function(byGroup)\n"
    .. tsrc:sub(from, to - 1) .. "\nreturn questRows end",
    "@UI/Tracker.lua slice"))

local hiddenSections, popupCounts, declared = {}, {}, { "campaign", "quests" }
local tns = { GetModule = function(_, n)
    if n == "Registry" then return { Get = function() return { groups = declared } end } end
end }
local count = tchunk(tns,
    { IsHidden = function(_, gid) return hiddenSections[gid] == true end },
    { CountFor = function(_, gid) return popupCounts[gid] or 0 end },
    "quests")

local function group(n) return { visibleCount = n } end

ok(count({ quests = group(3), campaign = group(2) }) == 5, "both quest groups are summed")
ok(count({ quests = group(0), campaign = group(0) }) == 0, "an empty log counts zero")
ok(count({}) == 0, "a feed that never built those groups counts zero")

-- A collapsed section draws no rows and is not an empty one, which is why the count comes off
-- the group rather than off the row loop.
ok(count({ quests = group(6) }) == 6, "a collapsed section still counts its quests")

hiddenSections.campaign = true
ok(count({ quests = group(1), campaign = group(9) }) == 1,
   "a hidden section does not keep the tracker on screen")
hiddenSections.campaign = nil

-- A Quest Discovered box is the only affordance that quest has, Blizzard's own being suppressed
popupCounts.quests = 1
ok(count({}) == 1, "a quest popup with no rows keeps the tracker up")
ok(count({ quests = group(2) }) == 3, "popups add to the rows in their section")
hiddenSections.quests = true
ok(count({ quests = group(2) }) == 0, "a hidden section popup does not count either")
hiddenSections.quests = nil
popupCounts.quests = 0

-- Classic registers the same provider id with one group, so the list comes off the provider
declared = { "quests" }
ok(count({ quests = group(4), campaign = group(9) }) == 4,
   "only the groups the provider declares are counted")

-- ------------------------------------------------- the opacity option's seams, by anchor
--
-- Everything above hands Visibility a focused row directly. These are the other files, where
-- a dropped call or a wrong key switches the feature off with every case above still green.

local function stripComments(src)
    src = src:gsub("%-%-%[(=*)%[.-%]%1%]", "")
    return (src:gsub("%-%-[^\n]*", ""))
end

local function occurrences(src, needle)
    local n, at = 0, 1
    while true do
        local i = src:find(needle, at, true)
        if not i then return n end
        n, at = n + 1, i + 1
    end
end

do
    local probe = stripComments("-- noteFocus(entry, row)\n--[[\nsyncFade()\n]]\nx = 1\n")
    ok(not probe:find("noteFocus", 1, true) and not probe:find("syncFade", 1, true),
       "the stripper removes a line and a multi-line block comment")
    ok(probe:find("x = 1", 1, true) ~= nil, "and keeps the code after them")
end

-- noteFocus itself, sliced and driven. First focused entry wins and a later one cannot steal it.
do
    local FFROM = "local focusRow, focusQuestID\n"
    local FTO   = "function Tracker:_RenderPinnedWorldQuests("
    local ff, ft = tsrc:find(FFROM, 1, true), tsrc:find(FTO, 1, true)
    ok(ff ~= nil and ft ~= nil and ft > ff, "the noteFocus slice anchors are found in order")
    if ff and ft and ft > ff then
        local focusChunk, err = loadstring(tsrc:sub(ff, ft - 1)
            .. "\nreturn noteFocus, function() return focusRow, focusQuestID end",
            "@UI/Tracker.lua noteFocus")
        ok(focusChunk ~= nil, "the noteFocus slice compiles: " .. tostring(err))
        local noteFocus, read = (focusChunk or function() return function() end, function() end end)()
        local okSlice, errSlice = pcall(function()
            local r1, r2, r3 = {}, {}, {}
            noteFocus({ id = 1, isFocused = false }, r1)
            local row, qid = read()
            ok(row == nil and qid == nil, "an unfocused entry records nothing")
            noteFocus({ id = 2, isFocused = true }, r2)
            row, qid = read()
            ok(row == r2 and qid == 2, "the focused entry records its row and quest id")
            noteFocus({ id = 3, isFocused = true }, r3)
            row, qid = read()
            ok(row == r2 and qid == 2, "a second focused entry in the same pass does not replace it")
        end)
        ok(okSlice, "noteFocus does not raise: " .. tostring(errSlice))
    end
end

do
    local t = stripComments(tsrc)
    ok(occurrences(t, "        y = y + Row:Render(row, entry, width, cfg) + gap\n        noteFocus(entry, row)\n") == 1,
       "the world quest loop reports its rows, straight after drawing each")
    ok(occurrences(t, "                        y = y + Row:Render(row, entry, width, cfg) + gap\n"
             .. "                        noteFocus(entry, row)\n") == 1,
       "and so does the section loop")
    -- Call shape, indented: the bare name also matches "local function noteFocus(entry, row)".
    ok(occurrences(t, "        noteFocus(entry, row)\n") == 2, "and nowhere else")

    local resetAt  = t:find("    soonestExpiry  = nil\n    focusRow, focusQuestID = nil, nil\n", 1, true)
    local loopAt   = t:find("                        noteFocus(entry, row)\n", 1, true)
    local wqAt     = t:find("self:_RenderPinnedWorldQuests(byGroup[PINNED_GROUP]", 1, true)
    local sweepAt  = t:find("    RowPool:Sweep(_resetRow)\n", 1, true)
    local commitAt = t:find("    ItemButtons:Commit()\n", 1, true)
    local reportAt = t:find("        Visibility:SetFocus(focusRow, focusQuestID)\n", 1, true)
    ok(resetAt ~= nil, "Render clears the last pass's focus beside soonestExpiry")
    ok(resetAt and loopAt and wqAt and resetAt < loopAt and resetAt < wqAt,
       "and clears it BEFORE either loop can record one")
    ok(reportAt ~= nil, "Render reports the focused row to Visibility")
    ok(reportAt and sweepAt and commitAt and reportAt > sweepAt and reportAt > commitAt,
       "AFTER Sweep and Commit, or the lookup reads a button Commit is about to pool")
    ok(occurrences(t, "Visibility:SetFocus(") == 1, "from exactly one place")
    ok(occurrences(t, "    if Visibility then\n        Visibility:SetFocus(focusRow, focusQuestID)\n"
             .. "        Visibility:SetQuestRows(questRows)\n    end\n") == 1,
       "reported unconditionally on every render, so losing focus clears it")
end

do
    local c = stripComments(readFile("UI/Commands.lua"))
    ok(occurrences(c, 'debugLine("Visibility", nil, "FadeLine")\n') == 1,
       "/eqot status prints the fade line")
    ok(occurrences(c, '    debugLine("Visibility")\n    debugLine("Visibility", nil, "FadeLine")\n') == 1,
       "unconditionally, straight after the visibility line")

    local v = stripComments(readFile("UI/Visibility.lua"))
    ok(occurrences(v, "    f:SetAlpha(visible and settle(f) or 0)\n") == 1,
       "the hide path shows at the faded level and hides at zero")
    ok(occurrences(v, "    syncDriver(visible)\n    syncExempt(visible)\nend\n") == 2,
       "and both setVisible and ApplyFade end by resyncing the driver and the exemption")

    local db = stripComments(readFile("Core/DB.lua"))
    ok(occurrences(db, "            trackerAlpha      = 1.0,\n") == 1, "opacity defaults to solid")
    ok(occurrences(db, "            trackerAlphaHover = true,\n") == 1, "mouseover defaults on")
    ok(occurrences(db, "            trackerAlphaFocus = true,\n") == 1, "the focused quest defaults on")
    -- Inside the list ResetTrackerAppearance walks, not merely somewhere in the file.
    local resetKeys = db:match("\nlocal APPEARANCE_KEYS = (%b{})") or ""
    ok(occurrences(resetKeys, '    "trackerAlpha", "trackerAlphaHover", "trackerAlphaFocus",\n') == 1,
       "and Reset to Defaults on the Appearance tab clears all three")

    local a = stripComments(readFile("Options/TabAppearance.lua"))
    ok(occurrences(a, "L" .. '["Tracker Opacity"], 10, 100, 5,') == 1,
       "the slider runs 10 to 100 in fives, so it can never reach invisible")
    ok(occurrences(a, "return math.floor((DB().trackerAlpha or 1) * 100 + 0.5) end,") == 1,
       "it shows the stored fraction as a whole number")
    ok(occurrences(a, "DB().trackerAlpha = v / 100\n"
             .. "                ns:GetModule(\"Visibility\"):ApplyFade()\n"
             .. "                syncFade()\n") == 1,
       "and stores it back as a fraction, applies it, and re-dims the two boxes")
    ok(occurrences(a, "return DB().trackerAlphaHover ~= false end,") == 1, "the mouseover box reads its key")
    ok(occurrences(a, "DB().trackerAlphaHover = v\n                ns:GetModule(\"Visibility\"):ApplyFade()\n") == 1,
       "and writes and applies it")
    ok(occurrences(a, "return DB().trackerAlphaFocus ~= false end,") == 1, "the focused quest box reads its key")
    ok(occurrences(a, "DB().trackerAlphaFocus = v\n                ns:GetModule(\"Visibility\"):ApplyFade()\n") == 1,
       "and writes and applies it")
    ok(occurrences(a, "local faded = (DB().trackerAlpha or 1) < 1\n") == 1,
       "both boxes dim exactly while the tracker is at 100")
    ok(occurrences(a, "self:SetDependent(fadeHover, faded)\n") == 1
       and occurrences(a, "self:SetDependent(fadeFocus, faded)\n") == 1, "both are swept")
    ok(occurrences(a, "        end\n        syncFade()\n\n        local spacingSlider") == 1,
       "and dimmed once when the tab is built")
    ok(occurrences(a, 'spacingSlider:SetPoint("TOPLEFT", fadeFocus, "BOTTOMLEFT", 0, -14)') == 1,
       "Block Spacing hangs below the new controls rather than on top of them")
    ok(occurrences(a, 'fadeSlider:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", 0, -16)') == 1
       and occurrences(a, 'fadeHover:SetPoint("TOPLEFT", fadeSlider, "BOTTOMLEFT", 0, -14)') == 1
       and occurrences(a, 'fadeFocus:SetPoint("TOPLEFT", fadeHover, "BOTTOMLEFT", 0, -2)') == 1,
       "the three new controls hang one below the other under Tracker Scale")
end

print(string.format("test_visibility: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
