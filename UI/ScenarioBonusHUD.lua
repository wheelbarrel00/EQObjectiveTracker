local _, ns = ...

local HUD = ns:RegisterModule("ScenarioBonusHUD", {})
local L   = ns.L

local FRAME_W   = 240
local PAD       = 8
local ROW_GAP   = 3
local ICON_SIZE = 12
local TITLE_H   = 18
local REWARD_FALLBACK = 133785   -- inv_misc_treasurechest01

local TITLE_GOLD = { 0.92, 0.72, 0.02 }
local BORDER_RED = { 0.635, 0.000, 0.039, 1 }
local DEFAULT_Y  = -120

local rowPool, activeRows = {}, {}
local hoverCount = 0

local function hudState()
    local DB = ns:GetModule("DB")
    local t  = DB and DB:Tracker()
    if not t then return nil end
    t.scenarioBonusHUD = t.scenarioBonusHUD or {}
    return t.scenarioBonusHUD
end

local function enabled()
    local st = hudState()
    return (st and st.enabled == true) or false
end

local function buildRow(parent)
    local row = CreateFrame("Frame", nil, parent)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetJustifyH("LEFT")

    row.reward = CreateFrame("Frame", nil, row)
    row.reward:SetSize(16, 16)
    row.reward:EnableMouse(true)
    -- The HUD frame is mouse-enabled for its own drag, so the button has to sit clearly
    -- above it or the drag region swallows the hover. EQ sets this too, but from its row
    -- acquire, because its pooling calls SetParent unconditionally and that resets the
    -- level. Ours only reparents when the parent differs and the HUD frame is a singleton,
    -- so build time is enough.
    row.reward:SetFrameLevel(parent:GetFrameLevel() + 5)
    row.reward.tex = row.reward:CreateTexture(nil, "ARTWORK")
    row.reward.tex:SetAllPoints()
    row.reward:SetScript("OnEnter", function(self)
        hoverCount = hoverCount + 1
        local RT = ns:GetModule("RewardTooltip")
        if RT and self.questID then RT:Show(self, self.questID) end
    end)
    row.reward:SetScript("OnLeave", function()
        local RT = ns:GetModule("RewardTooltip")
        if RT then RT:Hide() end
    end)
    row.reward:Hide()

    return row
end

local function acquireRow(parent)
    local row = tremove(rowPool)
    if not row then
        row = buildRow(parent)
    elseif row:GetParent() ~= parent then
        row:SetParent(parent)
    end
    activeRows[#activeRows + 1] = row
    return row
end

function HUD:_ReleaseRows()
    for i = #activeRows, 1, -1 do
        local row = activeRows[i]
        row:Hide()
        row:ClearAllPoints()
        row.icon:Hide()
        row.icon:ClearAllPoints()
        row.text:SetText("")
        row.text:ClearAllPoints()
        row.reward:Hide()
        row.reward:ClearAllPoints()
        row.reward.questID = nil
        rowPool[#rowPool + 1] = row
        activeRows[i] = nil
    end
end

function HUD:ApplySettings()
    local f = self.frame
    if not f then return end
    local st = hudState() or {}
    local scale = st.scale or 1.0
    if scale <= 0 then scale = 1.0 end

    -- Offsets are stored in UIParent units but SetPoint reads them in the frame's own scaled
    -- space, so they are divided back out. Without this the HUD walks across the screen as
    -- the scale slider moves instead of growing in place. EQ has this bug.
    f:SetScale(scale)
    f:ClearAllPoints()
    f:SetPoint(st.point or "CENTER", UIParent, st.relPoint or st.point or "CENTER",
               (st.x or 0) / scale, (st.y or DEFAULT_Y) / scale)

    if st.showBackground == false then
        f:SetBackdropColor(0, 0, 0, 0)
    elseif st.backgroundColor then
        local c = st.backgroundColor
        -- A picked color carries its own alpha, so the lock fade below stops applying.
        f:SetBackdropColor(c.r or 0, c.g or 0, c.b or 0, c.a or 1)
    else
        -- Fades slightly once locked, so an unlocked HUD reads as draggable
        f:SetBackdropColor(0, 0, 0, st.locked and 0.40 or 0.55)
    end

    if st.showBorder == false then
        f:SetBackdropBorderColor(0, 0, 0, 0)
    else
        local bc = st.borderColor
        if bc then f:SetBackdropBorderColor(bc.r, bc.g, bc.b, bc.a or 1)
        else       f:SetBackdropBorderColor(BORDER_RED[1], BORDER_RED[2], BORDER_RED[3], BORDER_RED[4]) end
    end
end

function HUD:_SavePosition()
    local f, st = self.frame, hudState()
    if not (f and st) then return end
    local point, _, relPoint, x, y = f:GetPoint()
    if not point then return end
    local scale = f:GetScale()
    if not scale or scale <= 0 then scale = 1.0 end
    st.point, st.relPoint = point, relPoint
    st.x, st.y = (x or 0) * scale, (y or 0) * scale
end

function HUD:_ContextMenu()
    if not (MenuUtil and MenuUtil.CreateContextMenu and self.frame) then return end
    MenuUtil.CreateContextMenu(self.frame, function(_, root)
        root:CreateTitle(L["Bonus Objectives"])
        local st = hudState() or {}
        root:CreateButton(st.locked and L["Unlock (allow moving)"] or L["Lock position"], function()
            local s = hudState()
            if s then s.locked = not s.locked end
            HUD:ApplySettings()
        end)
        root:CreateButton(L["Reset position"], function()
            local s = hudState()
            if s then s.point, s.relPoint, s.x, s.y = "CENTER", "CENTER", 0, DEFAULT_Y end
            HUD:ApplySettings()
        end)
        root:CreateDivider()
        root:CreateButton(L["Cancel"], function() end)
    end)
end

-- Parented to UIParent so it stays outside the tracker's secure item-button chain and needs
-- none of the combat gating those frames carry.
function HUD:_Acquire()
    if self.frame then return self.frame end

    local f = CreateFrame("Frame", "EQOTScenarioBonusHUD", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    f:SetSize(FRAME_W, 40)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    -- Hiding this frame fires no OnLeave on the reward button inside it, and the private
    -- tooltip does not self-heal the way the shared one did, so hiding the HUD under a
    -- hovered reward icon left an opaque box over the world. Scoped to this frame's own
    -- subtree because the owner is a reward button two levels down, and an unscoped hide
    -- would close the tooltip of whatever the cursor is really on.
    f:HookScript("OnHide", function(s)
        local tip   = ns.Util.Tooltip()
        local owner = tip:GetOwner()
        while owner do
            if owner == s then
                tip:Hide()
                return
            end
            owner = owner.GetParent and owner:GetParent()
        end
    end)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s)
        local st = hudState()
        if st and st.locked then return end
        s:StartMoving()
    end)
    f:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        HUD:_SavePosition()
    end)
    f:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then HUD:_ContextMenu() end
    end)

    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", PAD, -6)
    f.title:SetJustifyH("LEFT")
    f.title:SetText(L["Bonus Objectives"])
    f.title:SetTextColor(TITLE_GOLD[1], TITLE_GOLD[2], TITLE_GOLD[3])

    self.frame = f
    self:ApplySettings()
    return f
end

local function setReward(row, questID, icon)
    local btn = row.reward
    if not (questID and questID ~= 0) then btn:Hide(); return end
    btn.questID = questID
    btn:ClearAllPoints()
    btn:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    btn.tex:SetTexture(icon or REWARD_FALLBACK)
    btn:Show()
end

function HUD:_Render(model)
    if not (model and #model > 0) then
        self:_ReleaseRows()
        if self.frame then self.frame:Hide() end
        return
    end

    local f = self:_Acquire()
    self:_ReleaseRows()
    local Media = ns:GetModule("Media")
    local Util  = ns.Util
    local y = TITLE_H + 6

    for i = 1, #model do
        local step = model[i]
        local hrow = acquireRow(f)
        hrow.icon:Hide()
        hrow.text:ClearAllPoints()
        hrow.text:SetPoint("LEFT",  hrow, "LEFT",  PAD, 0)
        hrow.text:SetPoint("RIGHT", hrow, "RIGHT", -26, 0)
        hrow.text:SetText(step.name or "")
        hrow.text:SetTextColor(TITLE_GOLD[1], TITLE_GOLD[2], TITLE_GOLD[3])
        setReward(hrow, step.rewardQuestID, step.rewardIcon)
        hrow:ClearAllPoints()
        hrow:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, -y)
        hrow:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -y)
        hrow:SetHeight(math.max(hrow.text:GetStringHeight(), 14))
        hrow:Show()
        Media:ApplyTextShadow(hrow.text)
        y = y + hrow:GetHeight() + ROW_GAP

        local crit = step.criteria
        for c = 1, (crit and #crit or 0) do
            local info = crit[c]
            local crow = acquireRow(f)
            local isStat = info.kind == "stat"
            crow.reward:Hide()
            crow.text:ClearAllPoints()
            if isStat then
                -- Run state, not an objective, so no checkbox and no completed color.
                crow.icon:Hide()
                crow.text:SetPoint("LEFT", crow, "LEFT", PAD + 6, 0)
            else
                crow.icon:Show()
                crow.icon:ClearAllPoints()
                crow.icon:SetPoint("LEFT", crow, "LEFT", PAD + 6, 0)
                Util.SafeSetAtlas(crow.icon, info.completed
                    and "ui-questtracker-tracker-check"
                    or  "ui-questtracker-objective-nub")
                crow.text:SetPoint("LEFT", crow.icon, "RIGHT", 6, 0)
            end
            crow.text:SetPoint("RIGHT", crow, "RIGHT", -6, 0)
            crow.text:SetText(info.text or "")
            if isStat then
                crow.text:SetTextColor(0.62, 0.62, 0.62)
            elseif info.completed then
                crow.text:SetTextColor(0.27, 1.0, 0.27)
            else
                crow.text:SetTextColor(0.85, 0.85, 0.85)
            end
            crow:ClearAllPoints()
            crow:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, -y)
            crow:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -y)
            crow:SetHeight(math.max(crow.text:GetStringHeight(), 14))
            crow:Show()
            Media:ApplyTextShadow(crow.text)
            y = y + crow:GetHeight() + ROW_GAP
        end
    end

    f:SetHeight(y + PAD - ROW_GAP)
    f:Show()
end

function HUD:Update()
    if self._test then return end
    if not enabled() then
        self:_ReleaseRows()
        if self.frame then self.frame:Hide() end
        return
    end
    self:_Render(ns:GetModule("ScenarioBonus"):GetModel())
end

function HUD:SetEnabled(on)
    local st = hudState()
    if st then st.enabled = on and true or false end
    self._test = false
    ns:GetModule("ScenarioBonus"):Reconcile()
    self:Update()
end

function HUD:SetScale(v)
    local st = hudState()
    if st then st.scale = v end
    self:ApplySettings()
end

-- Drawn from a fixed model so the frame can be positioned without being in a delve
function HUD:ToggleTest()
    if self._test then
        self._test = false
        self:Update()
    else
        self._test = true
        self:_Render({
            { name = "Bonus: Extra Credit", rewardQuestID = 999999, criteria = {
                { text = "Rescue the trapped villagers", completed = true },
                { text = "0/3 Hidden caches opened",     completed = false },
            } },
            { name = "Bonus: Swift Delver", rewardQuestID = 999999, criteria = {
                { text = "Finish within the time limit", completed = false },
                { text = "Lives: 3   Deaths: 1", completed = false, kind = "stat" },
            } },
        })
    end
    ns:Print("bonus HUD test mode " ..
        (self._test and "ON (drag to position, run again to hide)" or "OFF"))
end

function HUD:Dump()
    -- The data half reads live values that can throw, and this is the instrument this feature
    -- is diagnosed from - an unguarded call let one throw kill the whole command.
    local okData, out = pcall(function()
        return ns:GetModule("ScenarioBonus"):DumpLines({})
    end)
    if not (okData and type(out) == "table") then
        out = { "|cffff5555bonus data dump failed:|r " .. tostring(out) }
    end
    out[#out + 1] = ("frame: %s  rows %d  test=%s"):format(
        self.frame and (self.frame:IsShown() and "shown" or "hidden") or "not created",
        #activeRows, tostring(self._test and true or false))

    local RT = ns:GetModule("RewardTooltip")
    out[#out + 1] = ("reward: hovers %d, module %s, Show called %s, drawn %s"):format(
        hoverCount, RT and "loaded" or "|cffff5555MISSING|r",
        RT and tostring(RT.calls) or "-", RT and tostring(RT.drawn) or "-")

    local base = self.frame and self.frame:GetFrameLevel() or -1
    for i = 1, #activeRows do
        local btn = activeRows[i].reward
        if btn:IsShown() then
            out[#out + 1] = ("  btn[%d] quest=%s mouse=%s level=%d over %d"):format(i,
                tostring(btn.questID), tostring(btn:IsMouseEnabled()),
                btn:GetFrameLevel(), base)
        end
    end

    for i = 1, #out do ns:Print("  " .. out[i]) end
end

function HUD:DebugLine()
    return ("bonus hud: %s, frame %s, rows %d, %s"):format(
        enabled() and "on" or "off",
        self.frame and (self.frame:IsShown() and "shown" or "hidden") or "none",
        #activeRows,
        ns:GetModule("ScenarioBonus"):DebugLine())
end

function HUD:OnEnable()
    local Bonus = ns:GetModule("ScenarioBonus")
    if not Bonus then return end
    Bonus:OnDirty(function() HUD:Update() end)
    if enabled() then self:Update() end
end
