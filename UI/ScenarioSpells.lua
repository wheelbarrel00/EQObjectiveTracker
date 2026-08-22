local _, ns = ...

local ScenarioSpells = ns:RegisterModule("ScenarioSpells", {})

-- Blizzard draws a clickable, castable button in its delve block and EQOT hides the frame that
-- carries it, so this tracker drew no button for Foul Ball, the spell that moves a stuck
-- headball back onto the field. Whether the spell is reachable anywhere else on screen has not
-- been measured. The source is the scenario STEP, not a widget: Data/Providers/Scenarios.lua
-- reads C_ScenarioInfo.GetScenarioStepInfo().spells and hands the list over on the banner facts.
--
-- The buttons are SecureActionButtonTemplate parented into the scenario container, and they
-- register with ItemButtons. That module's latch is what the whole tracker asks before any
-- size, anchor, Show or Hide call on its own frame chain, so a second owner of a secure button
-- that kept its own flag would leave every one of those calls unguarded in combat.
--
-- Anchoring and showing are protected. Whether rebinding is has not been measured here, so the
-- combat path never rebinds either way. Alpha and mouse are not, which is the shape of that
-- path: a button whose spell goes away is blanked where it stands, and one whose spell comes
-- back is revived there rather than waiting for the fight to end.

local BTN_SIZE  = 26
local ROW_GAP   = 4
local TOP_GAP   = 6
-- Lines the button up with the criteria bullets above it, which sit at container left + 16
local SIDE_PAD  = 16
local LABEL_GAP = 6
local MAX       = 4

local ids, names, icons = {}, {}, {}
local live, pool = {}, {}
local wantN, lastY, lastW = 0, nil, nil

local function itemButtons()
    local IB = ns:GetModule("ItemButtons")
    return (IB and IB.Adopt) and IB or nil
end

local function renderWhenSafe()
    local Tracker = ns:GetModule("Tracker")
    if Tracker then Tracker:Render() end
end

-- Deliberately Tracker's own defer key AND its body. RunWhenOutOfCombat keeps the first
-- arrival's ORDER slot but overwrites the function, so the closure that runs is whichever
-- registered last and the two have to do the same thing. Keep them in step with
-- UI/Tracker.lua's deferRender.
local function deferRender()
    ns:GetModule("Events"):RunWhenOutOfCombat("eqot.deferredRender", renderWhenSafe)
end

local function labelWidth(w)
    return math.max(1, w - SIDE_PAD * 2 - BTN_SIZE - LABEL_GAP)
end

local function buildButton(container)
    local IB = itemButtons()
    -- A secure button under the tracker with nothing arming that latch leaves every size and
    -- anchor call above it unguarded in combat, so refusing is the safe direction.
    if not IB then return nil end

    local b = CreateFrame("Button", nil, container, "SecureActionButtonTemplate")
    b:SetSize(BTN_SIZE, BTN_SIZE)
    b:RegisterForClicks("AnyDown", "AnyUp")
    -- Confirmed casting in game on 2026-08-21, in combat and out: the step info gives a numeric
    -- id and this attribute takes one, so no name lookup sits between
    b:SetAttribute("type", "spell")

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- The only thing on the row that says it is clickable at all
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    -- A region of the button rather than a pooled FontString: regions are not protected, so
    -- the label follows the button for free and its text still changes in combat.
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetJustifyH("LEFT")
    b.label:SetWordWrap(false)
    b.label:SetPoint("LEFT", b, "RIGHT", LABEL_GAP, 0)

    b:Hide()
    IB:Adopt(b)
    return b
end

local function rowY(top, i)
    return top + TOP_GAP + (i - 1) * (BTN_SIZE + ROW_GAP)
end

-- True when the placement has work. An inert button counts: it is sitting at alpha zero and
-- only a pass through Place can tell whether its spell has come back.
local function stale(y, w)
    if y ~= lastY or w ~= lastW then return true end
    for i = 1, MAX do
        local b = live[i]
        if b then
            if b._eqotInert or b._spellID ~= ids[i] then return true end
        elseif ids[i] then
            return true
        end
    end
    return false
end

local function blank(b)
    b:SetAlpha(0)
    b:EnableMouse(false)
    b._eqotInert = true
end

local function revive(b)
    local IB = itemButtons()
    b._eqotInert = nil
    b:SetAlpha(1)
    b:EnableMouse(not (IB and IB:MouseSuspended()))
end

-- Blanked rather than hidden and unbound, so it makes no protected call and a spell that
-- comes back can be shown again with alpha alone. The cost is one invisible, mouse-dead
-- button parked in the container.
local function retire(i)
    local b = live[i]
    if not b then return end
    blank(b)
    live[i] = nil
    pool[#pool + 1] = b
end

-- Only into the slot the button is already anchored at. Moving it is protected, so one parked
-- anywhere else has to wait for the fight to end.
local function reclaim(i)
    if lastY == nil then return nil end
    local at = rowY(lastY, i)
    for p = #pool, 1, -1 do
        local b = pool[p]
        if b._spellID == ids[i] and b._eqotAt == at then
            tremove(pool, p)
            live[i] = b
            return b
        end
    end
    return nil
end

-- The only function here that makes a protected call, and it never runs in combat.
local function applyLayout(container, y, w)
    for i = MAX, wantN + 1, -1 do retire(i) end

    local IB   = itemButtons()
    local span = LABEL_GAP + labelWidth(w)
    for i = 1, wantN do
        local b = live[i]
        if not b then
            b = tremove(pool) or buildButton(container)
            live[i] = b
        end
        if b then
            if b:GetParent() ~= container then b:SetParent(container) end
            if b._spellID ~= ids[i] then
                b:SetAttribute("spell", ids[i])
                b._spellID = ids[i]
            end
            b._eqotInert = nil
            b:SetAlpha(1)
            b:EnableMouse(not (IB and IB:MouseSuspended()))
            -- The label is the readable half of the control, so it has to be clickable too
            b:SetHitRectInsets(0, -span, 0, 0)
            b:ClearAllPoints()
            b._eqotAt = rowY(y, i)
            b:SetPoint("TOPLEFT", container, "TOPLEFT", SIDE_PAD, -b._eqotAt)
            b:Show()
        end
    end
    lastY, lastW = y, w
end

-- Unconditional, because font and text are unprotected and memoizing them would freeze a label
-- at whatever Font Size it was last drawn with.
local function paint(w)
    local Media = ns:GetModule("Media")
    local width = labelWidth(w)
    for i = 1, wantN do
        local b = live[i]
        if b and b._spellID == ids[i] then
            if icons[i] then
                b.icon:SetTexture(icons[i])
                b.icon:Show()
            else
                b.icon:Hide()
            end
            Media:ApplyFont(b.label, -2)
            b.label:SetWidth(width)
            b.label:SetText(names[i] or "")
        end
    end
end

-- y is the bottom of the criteria, measured from the container's top. Returns the height taken,
-- which UI/Scenario.lua adds into the container's own.
function ScenarioSpells:Place(container, info, y)
    wantN = 0
    -- Driven from Tracker:Render, so IsModuleDisabled's OnEnable gate never reaches it. Asking
    -- IsModuleDisabled rather than SafeMode also honors an explicit enable, which is the whole
    -- of what a bisection needs. It stops the frames, not the provider's read.
    local list = info and info.spells
    if list and not ns:IsModuleDisabled("ScenarioSpells") then
        wantN = math.min(info.spellsN or 0, MAX)
        for i = 1, wantN do
            -- Scalars only. The list and its rows belong to the provider and are refilled by
            -- the next GetEntries.
            ids[i], names[i], icons[i] = list[i].spellID, list[i].name, list[i].icon
        end
    end
    for i = wantN + 1, MAX do ids[i], names[i], icons[i] = nil, nil, nil end

    local w = math.floor(container:GetWidth() or 0)
    if stale(y, w) then
        if InCombatLockdown() then
            -- A button that has merely moved stays castable where it is, which matters more
            -- in here than a few pixels do.
            -- Only queue the relayout when there is something to lay out. A scenario with no
            -- step spells still moves y as its criteria tick, so an unconditional defer would
            -- rebuild the feed at the end of every fight for a player who has no button at all.
            local pending = wantN > 0
            for i = 1, MAX do
                local b = live[i] or (ids[i] and reclaim(i))
                if b then
                    pending = true
                    if b._spellID ~= ids[i] then
                        blank(b)
                    elseif b._eqotInert then
                        revive(b)
                    end
                end
            end
            if pending then deferRender() end
        else
            applyLayout(container, y, w)
        end
    end
    paint(w)

    -- Reserved from the DATA rather than from what could be placed, so a button combat
    -- postponed does not shift the container height when it finally lands.
    if wantN == 0 then return 0 end
    return TOP_GAP + wantN * BTN_SIZE + (wantN - 1) * ROW_GAP
end

-- No combat branch, because retiring one of these makes no protected call.
function ScenarioSpells:Clear()
    for i = 1, MAX do ids[i], names[i], icons[i] = nil, nil, nil end
    wantN = 0
    for i = MAX, 1, -1 do retire(i) end
    lastY, lastW = nil, nil
end

-- No work of its own. It exists so /eqot modules lists this and /eqot disable can reach it:
-- moduleCmd only offers names that have an OnEnable, and this is the one feature in the tree
-- that arms the secure latch for a player who never tracks a quest item.
function ScenarioSpells:OnEnable() end

function ScenarioSpells:DebugLine()
    local IB = itemButtons()
    if not IB then return "scenario spells: no secure registry, refusing to build" end
    local n = 0
    for i = 1, MAX do if live[i] then n = n + 1 end end
    return ("scenario spells: %s | wanted %d, live %d, pooled %d | secure %s | %s"):format(
        ns:IsModuleDisabled("ScenarioSpells") and "off" or "on",
        wantN, n, #pool, tostring(IB:HasSecureButtons()),
        (wantN > 0 and tostring(names[1] or ids[1])) or "-")
end
