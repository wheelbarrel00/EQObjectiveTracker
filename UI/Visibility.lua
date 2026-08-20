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
    local function onMapToggle() Visibility:Apply() end
    hooksecurefunc(WorldMapFrame, "Show", onMapToggle)
    hooksecurefunc(WorldMapFrame, "Hide", onMapToggle)
end

-- The manual hide is folded in here so one function owns every reason the tracker is not
-- on screen, and /eqot toggle never has to fight an event that repaints it.
local function shouldHide(f)
    if f._eqotUserHidden then return true end
    local g = cfg()
    if not g then return false end
    if g.hideInCombat     and inCombat()                                then return true end
    if g.hideInInstances  and IsInInstance and (IsInInstance())         then return true end
    if g.hideInMythicPlus and inMythicPlus()                            then return true end
    if g.hideOnMapOpen    and WorldMapFrame and WorldMapFrame:IsShown() then return true end
    return false
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
    f:SetAlpha(visible and 1 or 0)
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
end

function Visibility:Apply()
    ensureMapHook()
    local Tracker = ns:GetModule("Tracker")
    local f = Tracker and Tracker.frame
    if not f then return end

    local visible = not shouldHide(f)
    setVisible(f, visible)
    if visible and f._eqotPendingRender then
        f._eqotPendingRender = nil
        Tracker:Refresh()
    end
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

function Visibility:DebugLine()
    local g = cfg() or {}
    local Tracker = ns:GetModule("Tracker")
    local f = Tracker and Tracker.frame
    return ("visibility: ruleHide=%s | cfg combat=%s inst=%s m+=%s map=%s | now combat=%s inst=%s m+=%s map=%s | frame %s alpha=%.2f pending=%s")
        :format(tostring(self:IsRuleHiding()),
                tostring(g.hideInCombat), tostring(g.hideInInstances),
                tostring(g.hideInMythicPlus), tostring(g.hideOnMapOpen),
                tostring(inCombat()),
                tostring(IsInInstance and (IsInInstance()) or false),
                tostring(inMythicPlus()),
                tostring(WorldMapFrame and WorldMapFrame:IsShown() or false),
                f and (f:IsShown() and "shown" or "hidden") or "none",
                f and f:GetAlpha() or -1,
                tostring((f and f._eqotPendingRender) and true or false))
end

function Visibility:OnEnable()
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
