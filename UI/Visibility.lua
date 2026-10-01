local _, ns = ...

local Visibility = ns:RegisterModule("Visibility", {})

local function cfg()
    return ns:GetModule("DB"):General()
end

local function inCombat()
    -- PLAYER_REGEN_DISABLED fires just before InCombatLockdown reports true, so the
    -- event-tracked flag has to count as well or the first hide lands a frame late.
    return InCombatLockdown() or Visibility._inCombat == true
end

local function inMythicPlus()
    if not ns.Has.MythicPlus then return false end
    return C_ChallengeMode.IsChallengeModeActive() and true or false
end

-- Installed lazily, and ONLY once the map rule is actually switched on, because a Blizzard
-- frame should not be hooked for a feature the player has switched off. That is hygiene and
-- NOT a fix for anything: this was made lazy while chasing the SetPassThroughButtons blocked
-- action on 2026-07-30 and was then exonerated, since the error reproduced with the hook
-- never installed. hooksecurefunc rather than HookScript, because that is the taint-safe way
-- to watch a Blizzard frame. Once taken the hook stays for the session, which is harmless.
local function ensureMapHook()
    if Visibility._mapHooked then return end
    local g = cfg()
    if not (g and g.hideOnMapOpen and WorldMapFrame) then return end
    Visibility._mapHooked = true
    -- Deferred by a frame, and coalesced so a fast toggle cannot queue a second one. The hook
    -- runs inside WorldMapFrame:Show, so Apply mutated frames there - alpha, Show and Hide, the
    -- item buttons' mouse, and EnableMouse on the scroll bar and its children. A v1.11.0 user
    -- who had never seen one before reported a blocked SetPassThroughButtons on a map pin, and
    -- v1.11.0 is what added that EnableMouse call. No taint log was taken, so the mechanism is
    -- inferred from that window alone. Same deferral as UI/Blizzard.lua. This does NOT reopen
    -- the exoneration above: that one was measured against the 2026-07-30 report, which
    -- reproduced with this hook never installed and before the EnableMouse call existed.
    local function onMapToggle()
        if Visibility._mapPending then return end
        Visibility._mapPending = true
        C_Timer.After(0, function()
            Visibility._mapPending = nil
            Visibility:Apply()
        end)
    end
    hooksecurefunc(WorldMapFrame, "Show", onMapToggle)
    hooksecurefunc(WorldMapFrame, "Hide", onMapToggle)
end

-- How many quest and campaign rows the last render drew. NIL until a render has actually
-- counted, so the empty rule cannot hide a tracker on the strength of a question nobody has
-- answered yet - a login reads nil, which is not zero, and the tracker stays up.
local questRows

-- The manual hide is folded in here so one function owns every reason the tracker is not
-- on screen, and /eqot toggle never has to fight an event that repaints it.
--
-- The reason comes back with the answer because ONE of them, the empty rule, still needs the
-- tracker to keep rendering while it is hidden - see Tracker:Render. It is tested LAST so any
-- other reason wins the label, or a combat hide would let the render through as well.
local function shouldHide(f)
    if f._eqotUserHidden then return true, "user" end
    local g = cfg()
    if not g then return false end
    if g.hideInCombat     and inCombat()                                then return true, "combat" end
    if g.hideInInstances  and IsInInstance and (IsInInstance())         then return true, "instance" end
    if g.hideInMythicPlus and inMythicPlus()                            then return true, "mythicplus" end
    if g.hideOnMapOpen    and WorldMapFrame and WorldMapFrame:IsShown() then return true, "map" end
    if g.hideWhenNoQuests and questRows == 0                            then return true, "noquests" end
    return false
end

-- The hide below owns alpha 0 and the opacity option owns every alpha a SHOWN tracker has, so
-- the two can never disagree about the frame.
local FADE_TIME  = 0.2
local HOLD_TIME  = 1
local HOVER_POLL = 0.05
-- A faded tracker still takes clicks, so no stored value may make it invisible.
local MIN_ALPHA  = 0.1

local fade = { current = 1, over = false, leftAt = nil, poll = 0 }
local focusRow, focusQuestID
local exemptRow, exemptButton
local driver

local function appearance()
    return ns:GetModule("DB"):Tracker()
end

local function fadeLevel()
    local t = appearance()
    local a = t and tonumber(t.trackerAlpha)
    if not a or a >= 1 then return 1 end
    return math.max(MIN_ALPHA, a)
end

local function hoverOn()
    local t = appearance()
    return not (t and t.trackerAlphaHover == false)
end

local function focusOn()
    local t = appearance()
    return not (t and t.trackerAlphaFocus == false)
end

local function over(r)
    return r ~= nil and r:IsVisible() and r:IsMouseOver() and true or false
end

local function overBar(sf)
    return sf ~= nil and over(sf.ScrollBar or sf.scrollBar)
end

-- Only what is drawn counts, so the empty part of the frame below the last quest does not bring
-- the tracker up. The quest list is the scroll viewport clipped to the content laid out in it.
local function mouseOverDrawn(f)
    if over(f.drag) or over(f.scenarioContainer) or over(f.eventsRegion) then return true end
    if over(f.scroll) and over(f.content) then return true end
    if overBar(f.scroll) or overBar(f.eventsScroll) then return true end
    -- A locked grip sits at alpha 0 but still reads as visible.
    if not over(f.grip) then return false end
    local Tracker = ns:GetModule("Tracker")
    return not (Tracker and Tracker:IsLocked())
end

local function fadeTarget()
    local level = fadeLevel()
    if level >= 1 then return 1 end
    if hoverOn() and (fade.over or (fade.leftAt and GetTime() - fade.leftAt < HOLD_TIME)) then
        return 1
    end
    return level
end

-- Takes the level at once rather than animating from wherever the last fade left off. Every
-- Apply that leaves the tracker shown lands here, so combat or a map toggle also ends a mouseover
-- hold early.
local function settle(f)
    fade.over = fadeLevel() < 1 and hoverOn() and mouseOverDrawn(f)
    fade.leftAt = nil
    fade.current = fadeTarget()
    return fade.current
end

local function stepFade(_, elapsed)
    local Tracker = ns:GetModule("Tracker")
    local f = Tracker and Tracker.frame
    if not f then return end
    fade.poll = fade.poll - elapsed
    if fade.poll <= 0 then
        fade.poll = HOVER_POLL
        local now = mouseOverDrawn(f)
        if fade.over and not now then fade.leftAt = GetTime() end
        fade.over = now
    end
    local cur, target = fade.current, fadeTarget()
    if cur == target then return end
    local step = elapsed / FADE_TIME
    if cur < target then cur = math.min(target, cur + step) else cur = math.max(target, cur - step) end
    fade.current = cur
    f:SetAlpha(cur)
end

-- Runs only while a shown tracker is faded with mouseover on, so the default costs nothing.
local function syncDriver(visible)
    if visible and fadeLevel() < 1 and hoverOn() then
        if not driver then
            driver = CreateFrame("Frame")
            driver:SetScript("OnUpdate", stepFade)
        end
        driver:Show()
    elseif driver then
        driver:Hide()
    end
end

local function canExempt(r)
    return r ~= nil and r.SetIgnoreParentAlpha ~= nil
end

-- The focused quest's row ignores the tracker's alpha, so it stays solid while the rest fades.
-- Its item button is secure and nobody has measured this call on one in combat, so it is exempt
-- out of combat only. PLAYER_REGEN_DISABLED runs Apply before the lockdown to drop it, and no
-- call reaches the button while the lockdown is up.
local function syncExempt(visible)
    local row = (visible and fadeLevel() < 1 and focusOn()) and focusRow or nil
    local button
    if row and not inCombat() then
        local IB = ns:GetModule("ItemButtons")
        button = IB and IB.buttons and IB.buttons[focusQuestID]
    end
    if exemptRow ~= row then
        if canExempt(exemptRow) then exemptRow:SetIgnoreParentAlpha(false) end
        if canExempt(row) then row:SetIgnoreParentAlpha(true) end
        exemptRow = row
    end
    if exemptButton ~= button and not InCombatLockdown() then
        if canExempt(exemptButton) then exemptButton:SetIgnoreParentAlpha(false) end
        if canExempt(button) then button:SetIgnoreParentAlpha(true) end
        exemptButton = button
    end
end

-- A real Hide until a secure quest-item button has been built, and alpha from then on for the
-- rest of the session - HasSecureButtons latches, so this is not scoped to combat. Unlike EQ
-- the invisible frame is also made click-through: Tracker:IsClickThrough gates every mouse
-- handler and the item buttons give up their own mouse, so an alpha-0 tracker cannot take
-- clicks, tooltips or the wheel.
local function setVisible(f, visible)
    local IB = ns:GetModule("ItemButtons")
    -- The alpha-only path fires no OnHide, so the frame's own hook cannot catch this one
    if not visible then ns.Util.Tooltip():Hide() end
    f:SetAlpha(visible and settle(f) or 0)
    f._eqotHidden = (not visible) or nil
    -- Hiding for real once a secure button has been built strands the frame: Show is
    -- protected in combat too, so a toggle mid-fight set alpha on a frame that was never
    -- coming back, and printed nothing. Alpha carries every hide from then on and the frame
    -- stays shown, which is the one state combat can always undo.
    if visible then
        if not (IB and IB.Locked and IB:Locked()) then f:Show() end
    elseif not (IB and IB.HasSecureButtons and IB:HasSecureButtons()) then
        f:Hide()
    end
    if IB and IB.SetMouseSuspended then IB:SetMouseSuspended(not visible) end
    local Tracker = ns:GetModule("Tracker")
    if Tracker and Tracker.SetScrollInputSuspended then
        Tracker:SetScrollInputSuspended(not visible)
    end
    syncDriver(visible)
    syncExempt(visible)
end

function Visibility:Apply()
    -- Still reachable from the General tab's hide rules, and the map hook it installs would
    -- serve a tracker window that does not exist.
    if ns:IsStandingDown("Visibility") then return end
    ensureMapHook()
    local Tracker = ns:GetModule("Tracker")
    local f = Tracker and Tracker.frame
    if not f then return end

    local wasHidden   = f._eqotHidden
    local hidden, why = shouldHide(f)
    setVisible(f, not hidden)

    -- Two states need the tracker to keep rendering while it is off screen, and both belong to
    -- the empty rule. The hide itself, because the render IS what counts the quests and a
    -- tracker that stopped counting could never notice the quest meant to bring it back. And a
    -- Show the secure lock REFUSED: setVisible drops it silently while combat is up once a
    -- scenario spell button has armed the latch, which leaves the frame off screen with no
    -- reason recorded against it and would otherwise stop the count until the fight ended.
    local ruleOn = (cfg() or {}).hideWhenNoQuests
    f._eqotRenderWhileHidden = ((hidden and why == "noquests")
        or (ruleOn and not hidden and not f:IsShown())) or nil

    -- A render that ran while hidden laid the rows out against a frame with no resolvable top,
    -- so its item buttons hid rather than guessing at an anchor. Coming back on screen has to
    -- ask for one more pass or that row keeps its empty gutter until an unrelated quest event.
    if not hidden and (wasHidden or f._eqotPendingRender) then
        f._eqotPendingRender = nil
        Tracker:Refresh()
    elseif f._eqotRenderWhileHidden and f._eqotPendingRender then
        f._eqotPendingRender = nil
        Tracker:Refresh()
    end
end

-- The first count of a session may not HIDE, only record. Tracker:OnEnable renders at
-- PLAYER_LOGIN and a quest log that has not streamed in yet answers a real zero that reads
-- exactly like an empty one, so a full log would blink out and back at every login. The zero is
-- DROPPED rather than stored, leaving the count at nil, so a genuinely empty log still hides on
-- the next render rather than never.
local firstCount = true

-- Called at the end of every render. Only the zero boundary can change what the rule answers,
-- so a log going from four quests to three does not re-apply anything.
function Visibility:SetQuestRows(n)
    -- Render-driven, so IsModuleDisabled's OnEnable gate never reaches it and this asks for
    -- itself, the way UI/WidgetBlock.lua and UI/ScenarioSpells.lua do. Without it /eqot disable
    -- all hides the tracker on the first empty feed and then NEVER re-applies, because OnEnable
    -- was skipped and no event is left to call Apply - safe mode would blank the one thing a
    -- taint bisection needs to look at.
    if ns:IsModuleDisabled("Visibility") then return end

    -- nil means "never counted", and it restores that state in BOTH halves: the count and the
    -- guard below, so anything returning to the login state gets a login's protection.
    if n == nil then
        questRows, firstCount = nil, true
        return
    end

    if firstCount then
        firstCount = false
        if n == 0 then return end
    end

    local was = questRows
    questRows = n
    if was == n then return end
    local g = cfg()
    if not (g and g.hideWhenNoQuests) then return end
    if was ~= nil and (was == 0) == (n == 0) then return end
    self:Apply()
end

-- The options call this rather than Apply, which would rerun every hide rule on each tick of a
-- slider drag.
function Visibility:ApplyFade()
    if not self._started then return end
    local Tracker = ns:GetModule("Tracker")
    local f = Tracker and Tracker.frame
    if not f then return end
    local visible = not f._eqotHidden
    if visible then f:SetAlpha(settle(f)) end
    syncDriver(visible)
    syncExempt(visible)
end

-- Called by Tracker:Render after ItemButtons:Commit, so the button looked up here is the one this
-- pass settled rather than one Commit is about to pool.
function Visibility:SetFocus(row, questID)
    if not self._started then return end
    focusRow, focusQuestID = row, questID
    local Tracker = ns:GetModule("Tracker")
    local f = Tracker and Tracker.frame
    syncExempt(f ~= nil and not f._eqotHidden)
end

function Visibility:FadeLine()
    local Tracker = ns:GetModule("Tracker")
    local f = Tracker and Tracker.frame
    return ("fade: opacity %.2f, mouseover %s, focused quest %s | now %.2f, over %s, driver %s | exempt quest %s, item button %s | ignore parent alpha %s")
        :format(fadeLevel(), hoverOn() and "on" or "off", focusOn() and "on" or "off",
                fade.current, tostring(fade.over),
                (driver and driver:IsShown()) and "running" or "idle",
                exemptRow and tostring(focusQuestID) or "none",
                exemptButton and "yes" or "no",
                canExempt(f) and "supported" or "unsupported")
end

function Visibility:IsRuleHiding()
    local Tracker = ns:GetModule("Tracker")
    local f = Tracker and Tracker.frame
    if not f then return false end
    local was = f._eqotUserHidden
    f._eqotUserHidden = nil
    local hidden = shouldHide(f)
    f._eqotUserHidden = was
    return hidden
end

-- The rule's own input, so a "my tracker vanished" report names the count rather than arguing
-- about it. "never counted" is the login state and reads differently from a real zero.
function Visibility:QuestRowsLine()
    return ("empty rule: %s | quest rows %s"):format(
        tostring((cfg() or {}).hideWhenNoQuests),
        questRows == nil and "never counted" or tostring(questRows))
end

function Visibility:DebugLine()
    local g = cfg() or {}
    local Tracker = ns:GetModule("Tracker")
    local f = Tracker and Tracker.frame
    return ("visibility: ruleHide=%s | cfg combat=%s inst=%s m+=%s map=%s | now combat=%s inst=%s m+=%s map=%s | frame %s alpha=%.2f pending=%s | %s")
        :format(tostring(self:IsRuleHiding()),
                tostring(g.hideInCombat), tostring(g.hideInInstances),
                tostring(g.hideInMythicPlus), tostring(g.hideOnMapOpen),
                tostring(inCombat()),
                tostring(IsInInstance and (IsInInstance()) or false),
                tostring(inMythicPlus()),
                tostring(WorldMapFrame and WorldMapFrame:IsShown() or false),
                f and (f:IsShown() and "shown" or "hidden") or "none",
                f and f:GetAlpha() or -1,
                tostring((f and f._eqotPendingRender) and true or false),
                self:QuestRowsLine())
end

function Visibility:OnEnable()
    -- ApplyFade and SetFocus ask this rather than IsModuleDisabled, so /eqot enable and disable wait
    -- for the reload they ask for. Enabled live, the item button would be exempted with no combat
    -- listener to drop it before the lockdown.
    self._started = true
    local Events = ns:GetModule("Events")
    local function apply() self:Apply() end

    Events:On("PLAYER_REGEN_DISABLED", function()
        Visibility._inCombat = true
        Visibility:Apply()
    end)
    Events:On("PLAYER_REGEN_ENABLED", function()
        Visibility._inCombat = false
        Visibility:Apply()
    end)
    Events:On("CHALLENGE_MODE_START",     apply)
    Events:On("CHALLENGE_MODE_COMPLETED", apply)

    -- The map frame is load-on-demand, so ensureMapHook retries here rather than at load.
    Events:On("PLAYER_ENTERING_WORLD", apply)

    self:Apply()
end
