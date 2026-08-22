local _, ns = ...

local ItemButtons = ns:RegisterModule("ItemButtons", {})

local BTN_SIZE       = 26
local ITEM_GAP       = 6
local RANGE_THROTTLE = 0.25

ItemButtons.buttons = {}

local pool     = {}
local wanted   = {}
local stale    = {}
local deferFns = {}
local adopted  = {}
local container
local armed     = false
local suspended = false

local function getContainer()
    if container then return container end
    local Tracker = ns:GetModule("Tracker")
    local content = Tracker and Tracker.frame and Tracker.frame.content
    if not content then return nil end
    container = CreateFrame("Frame", nil, content)
    container:SetAllPoints(content)
    container:SetFrameLevel((content:GetFrameLevel() or 0) + 20)
    return container
end

local function enabled(cfg)
    -- Safe mode has to reach in here as well as the module list: ItemButtons has no OnEnable
    -- to skip, it is driven straight from Tracker:Render.
    if ns:SafeMode() then return false end
    return not cfg or cfg.showItemButtons ~= false
end

local function onRangeUpdate(self, elapsed)
    local t = (self._rangeTimer or 0) - elapsed
    if t > 0 then self._rangeTimer = t; return end
    self._rangeTimer = RANGE_THROTTLE

    local qid = self._questID
    if not qid then return end
    -- nil means the item has no range concept, which must stay white rather than red
    if ns:GetModule("QuestItems"):InRange(qid) == false then
        self.icon:SetVertexColor(1.0, 0.3, 0.3)
    else
        self.icon:SetVertexColor(1.0, 1.0, 1.0)
    end
end

local function buildButton()
    local b = CreateFrame("Button", nil, container, "SecureActionButtonTemplate")
    b:SetSize(BTN_SIZE, BTN_SIZE)
    -- SecureActionButton needs both AnyDown and AnyUp. AnyUp alone frequently misses the
    -- secure use.
    b:RegisterForClicks("AnyDown", "AnyUp")
    b:SetAttribute("type", "item")

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.count:SetPoint("BOTTOMRIGHT", -1, 1)

    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints()

    b:SetScript("OnUpdate", onRangeUpdate)
    b:Hide()
    ItemButtons:Adopt(b)
    return b
end

local function paint(b, questID)
    local _, icon, charges = ns:GetModule("QuestItems"):Get(questID)
    if not icon then return end
    b.icon:SetTexture(icon)
    if charges and charges > 1 then
        b.count:SetText(charges)
        b.count:Show()
    else
        b.count:SetText("")
        b.count:Hide()
    end
    local s, d = ns:GetModule("QuestItems"):Cooldown(questID)
    if s and d and d > 0 then b.cd:SetCooldown(s, d) else b.cd:Clear() end
end

local function retire(self, questID)
    local b = self.buttons[questID]
    if not b then return end
    b:Hide()
    b:ClearAllPoints()
    b._questID, b._rangeTimer = nil, nil
    self.buttons[questID] = nil
    pool[#pool + 1] = b
end

function ItemButtons:_Apply(questID)
    if not getContainer() then return end
    local cfg  = ns:GetModule("DB"):Tracker()
    local link = enabled(cfg) and ns:GetModule("QuestItems"):Get(questID) or nil
    local row  = wanted[questID]

    if not (link and row) then
        retire(self, questID)
        return
    end

    local b = self.buttons[questID]
    if not b then
        b = tremove(pool) or buildButton()
        self.buttons[questID] = b
    end
    b._questID    = questID
    b._rangeTimer = 0
    b:SetAttribute("item", link)
    b:EnableMouse(not suspended)
    b:ClearAllPoints()

    -- Anchor to the container, never to the row. A secure button anchored to the row
    -- would pull the row into its anchor family, which makes Show, Hide and SetPoint on
    -- the row itself blocked in combat.
    local cl, ct = container:GetLeft(), container:GetTop()
    local rl, rt = row:GetLeft(), row:GetTop()
    if cl and ct and rl and rt then
        local padX, padY = ns:GetModule("Row"):Padding(cfg)
        b:SetPoint("TOPLEFT", container, "TOPLEFT", (rl - cl) + padX, (rt - ct) - padY)
        b:Show()
    else
        b:Hide()
    end
end

local function deferFn(questID)
    local f = deferFns[questID]
    if not f then
        f = function()
            -- Dropped once it has run. The cache only has to outlive one combat, and keying
            -- it on quest ID with no release grows for the session.
            deferFns[questID] = nil
            ItemButtons:_Apply(questID)
            -- Paint on the flush too, or a button created at combat end stays blank
            -- until some unrelated render happens to repaint it.
            local b = ItemButtons.buttons[questID]
            if b and b:IsShown() then paint(b, questID) end
        end
        deferFns[questID] = f
    end
    return f
end

local function applySecure(self, questID)
    local Events = ns:GetModule("Events")
    if Events:InCombat() then
        Events:RunWhenOutOfCombat(questID, deferFn(questID))
    else
        self:_Apply(questID)
    end
end

-- Every secure button the tracker's frame chain hosts registers here, whoever built it. The
-- latch and the mouse sweep describe the CHAIN rather than quest items, so a second owner
-- keeping its own copy of either would leave the tracker making protected calls this one
-- already rules out. The one statement in the tree that arms the latch.
function ItemButtons:Adopt(b)
    armed = true
    adopted[#adopted + 1] = b
    b:EnableMouse(not suspended)
end

-- Once the tracker's frame chain has hosted a secure button, every size and anchor call
-- on that chain stays combat-protected for the rest of the session. Retiring a button
-- only pools it, so this deliberately never goes back to false.
function ItemButtons:HasSecureButtons()
    return armed
end

-- The one predicate the rest of the tracker asks before any size, anchor, Show or Hide
-- call on its own frame chain.
function ItemButtons:Locked()
    return InCombatLockdown() and armed
end

-- The tracker can only ever alpha-hide while a secure button is live, and an alpha-0
-- button still takes clicks, so its mouse goes off with the rest of the tracker's input.
function ItemButtons:SetMouseSuspended(v)
    v = v and true or false
    if suspended == v then return end
    suspended = v
    for i = 1, #adopted do
        local b = adopted[i]
        -- _eqotInert marks a button its own owner blanked, in combat or out, which must not get
        -- its mouse back just because the tracker became visible again. Do NOT clear it on
        -- PLAYER_REGEN_ENABLED: every pooled button carries it, and they sit at alpha 0 over the
        -- tracker with a hit rect spanning most of its width.
        b:EnableMouse(not v and not b._eqotInert)
    end
end

function ItemButtons:MouseSuspended()
    return suspended
end

function ItemButtons:Gutter()
    return BTN_SIZE + ITEM_GAP
end

function ItemButtons:Begin()
    wipe(wanted)
end

function ItemButtons:Want(questID, row)
    wanted[questID] = row
end

function ItemButtons:Commit()
    local n = 0
    for questID in pairs(self.buttons) do
        if not wanted[questID] then n = n + 1; stale[n] = questID end
    end
    for i = 1, n do
        applySecure(self, stale[i])
        stale[i] = nil
    end

    for questID in pairs(wanted) do
        applySecure(self, questID)
        local b = self.buttons[questID]
        if b and b:IsShown() then paint(b, questID) end
    end
end

function ItemButtons:DebugLine()
    local shown, total = 0, 0
    for _, b in pairs(self.buttons) do
        total = total + 1
        if b:IsShown() then shown = shown + 1 end
    end
    local nWanted = 0
    for _ in pairs(wanted) do nWanted = nWanted + 1 end
    return ("item buttons: %s | in log %d, wanted %d, live %d/%d, pooled %d | secure %s | container %s")
        :format(enabled(ns:GetModule("DB"):Tracker()) and "on" or "off",
                ns:GetModule("QuestItems"):CountInLog(),
                nWanted, shown, total, #pool,
                tostring(armed), container and "built" or "none")
end
