-- luacheck: globals InCombatLockdown IsInInstance C_ChallengeMode WorldMapFrame
-- luacheck: globals hooksecurefunc C_Timer
--
-- Unit tests for the hide-when-no-quests rule, run against the SHIPPED source rather than a
-- copy. Run from the repo root with the game's own Lua version:
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
-- UI/Tracker.lua cannot be loaded whole without a frame stub, so its count is sliced out by TEXT
-- ANCHOR rather than by line number, which drifts. If an anchor stops matching, fix the anchor
-- here rather than deleting the test.

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

local general, mods = {}, {}
local disabled = {}
local ns = { Has = { MythicPlus = true } }
function ns:RegisterModule(n, t) mods[n] = t return t end
function ns:GetModule(n) return mods[n] end
function ns:IsModuleDisabled(name) return disabled[name] == true end
ns.Util = { Tooltip = function() return { Hide = function() end } end }

mods.DB = { General = function() return general end }

local frame = {
    _shown = true, _alpha = 1,
    SetAlpha = function(self, a) self._alpha = a end,
    GetAlpha = function(self) return self._alpha end,
    Show     = function(self) self._shown = true end,
    Hide     = function(self) self._shown = false end,
    IsShown  = function(self) return self._shown end,
}

local refreshes = 0
mods.Tracker = {
    frame = frame,
    Refresh = function() refreshes = refreshes + 1 end,
    SetScrollInputSuspended = function() end,
}
mods.ItemButtons = {
    HasSecureButtons  = function() return false end,
    Locked            = function() return false end,
    SetMouseSuspended = function() end,
}
mods.Events = { On = function() end }

InCombatLockdown = function() return false end
IsInInstance     = function() return false end
C_ChallengeMode  = { IsChallengeModeActive = function() return false end }
WorldMapFrame    = { IsShown = function() return false end }
hooksecurefunc   = function() end
C_Timer          = { After = function(_, fn) fn() end }

local chunk = assert(loadstring(readFile("UI/Visibility.lua"), "@UI/Visibility.lua"))
chunk("EQObjectiveTracker", ns)
local V = mods.Visibility
assert(V, "UI/Visibility.lua did not register a Visibility module")

-- The count and the first-count guard are file-local upvalues, so they survive between cases
-- and a case that happens to set the same number twice would short-circuit and prove nothing.
-- SetQuestRows(nil) is the honest way back to the login state and restores both, which is the
-- state the first cases below are about. Cleared BEFORE the frame flags, because it can
-- re-apply and paint the frame on its way past.
local function reset(overrides)
    general = {}
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

print(string.format("test_visibility: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
