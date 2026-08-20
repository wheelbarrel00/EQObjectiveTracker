local _, ns = ...

local RT   = ns:RegisterModule("RewardTooltip", {})
local L    = ns.L
local Util = ns.Util

local INDENT = "    "
-- Escaped rather than literal so this file stays ASCII: \195\151 is a multiplication sign,
-- matching EQ's string byte for byte.
local TIMES = "\195\151"

-- Both globals are deprecated in favor of the namespaced calls and may go away
local function coinText(amount)
    local f = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    return (f and f(amount)) or tostring(amount)
end

-- Truncated to three deliberately: the API also returns a hex string, which would land in
-- AddLine's wrapText slot and word-wrap every item line.
local function qualityColor(quality)
    local f = (C_Item and C_Item.GetItemQualityColor) or GetItemQualityColor
    if not (quality and f) then return 1, 1, 1 end
    local r, g, b = f(quality)
    return r or 1, g or 1, b or 1
end

local function pickAnchor(owner)
    local cx = owner.GetCenter and select(1, owner:GetCenter())
    if not cx then return "ANCHOR_RIGHT" end
    local ownerPx   = cx * (owner:GetEffectiveScale() or 1)
    local screenMid = (UIParent:GetWidth() * (UIParent:GetEffectiveScale() or 1)) / 2
    return ownerPx > screenMid and "ANCHOR_LEFT" or "ANCHOR_RIGHT"
end

local function addComparison(tip, e)
    if e.cmpEmpty then
        -- The em dash escape sits INSIDE the key. Concatenated on, the phrase would never
        -- reach the manifest and could never be translated.
        tip:AddLine(INDENT .. L["Equip \226\128\148 empty slot"], 0.2, 1.0, 0.2)
        return
    end
    local lowest = e.cmpLowest
    if not lowest then return end

    local label = e.slotLabel or ""
    tip:AddLine((INDENT .. L["Equipped: ilvl %d"]):format(lowest)
        .. (label ~= "" and ("  (" .. label .. ")") or ""), 0.7, 0.7, 0.7)

    local delta = (e.ilvl or 0) - lowest
    if delta > 0 then
        tip:AddLine((INDENT .. L["+%d ilvl upgrade"]):format(delta), 0.2, 1.0, 0.2)
    elseif delta < 0 then
        tip:AddLine((INDENT .. L["%d ilvl lower"]):format(delta), 1.0, 0.3, 0.3)
    else
        tip:AddLine(INDENT .. L["Same item level"], 1.0, 0.82, 0.0)
    end
end

local function addItem(tip, e)
    local label = e.name or ""
    if e.count and e.count > 1 then label = label .. " " .. TIMES .. e.count end
    if e.showIlvl and e.ilvl then
        label = label .. ("  |cff999999" .. L["ilvl %d"] .. "|r"):format(e.ilvl)
    end

    tip:AddLine(label, qualityColor(e.quality))

    addComparison(tip, e)
end

-- Returns whether anything was drawn, so a caller can decide about a separator below it.
local function renderLines(tip, questID)
    local QR = ns:GetModule("QuestRewards")
    if not QR then return false end

    local lines = QR:Lines(questID)
    local sawReward = false
    for i = 1, #lines do
        local e = lines[i]
        if e.kind ~= "objective" then sawReward = true end
        if e.kind == "objective" then
            if e.done then
                tip:AddLine("- " .. e.text, 0.40, 0.85, 0.40, true)
            else
                tip:AddLine("- " .. e.text, 0.95, 0.95, 0.95, true)
            end
        elseif e.kind == "money" then
            tip:AddLine(coinText(e.amount), 1, 1, 1)
        elseif e.kind == "xp" then
            tip:AddLine((L["%d XP"]):format(e.amount), 1, 1, 1)
        elseif e.kind == "item" then
            addItem(tip, e)
        elseif e.kind == "choices" then
            tip:AddLine(L["Choose one:"], 0.9, 0.8, 0.3)
        elseif e.kind == "currency" then
            local label = e.name or ""
            if e.count and e.count > 1 then label = label .. " " .. TIMES .. e.count end
            tip:AddLine(label, 0.85, 0.85, 1.0)
        end
    end
    return #lines > 0, sawReward
end

-- A task quest's rewards stream in after RequestPreloadRewardData, so the first hover of a
-- cold world quest drew a tooltip with no rewards and nothing ever redrew it.
local REDRAW_DELAY = 0.4
local REDRAW_TRIES = 3

-- The budget is spent per hover and is what ends the chain: each re-draw arms the next one
-- from inside its own callback, so without it a row whose rewards never resolve rebuilt its
-- tooltip every REDRAW_DELAY for as long as the cursor sat on it. The generation is the
-- other half - a single armed flag let one row's pending re-draw refuse the arm of the next
-- row hovered inside the delay, and that row then never drew its rewards at all.
local function armRedraw(owner, questID, redraw)
    local left = RT._redrawLeft or 0
    if left <= 0 then return end
    RT._redrawLeft = left - 1

    RT._redrawGen = (RT._redrawGen or 0) + 1
    local gen = RT._redrawGen
    C_Timer.After(REDRAW_DELAY, function()
        if RT._redrawGen ~= gen then return end
        local tip = Util.Tooltip()
        if not (tip:IsShown() and tip:GetOwner() == owner) then return end
        -- The row may have been recycled onto another quest inside the delay.
        local e = owner._entry
        if e and e.id ~= questID then return end
        redraw()
    end)
end

RT.calls, RT.drawn = 0, 0

-- The public entry points are hover handlers, so they are where a fresh re-draw budget
-- belongs. The draw itself must not refill it or it could never run out.
function RT:Show(owner, questID)
    self._redrawLeft = REDRAW_TRIES
    self:_DrawQuest(owner, questID)
end

function RT:_DrawQuest(owner, questID)
    self.calls = self.calls + 1
    if not (owner and questID) then return end
    local QR = ns:GetModule("QuestRewards")
    if not QR then return end

    local tip = Util.Tooltip()
    tip:SetOwner(owner, pickAnchor(owner))
    tip:SetText(QR:Title(questID) or "", 1.0, 0.82, 0.0, 1, true)
    local _, sawReward = renderLines(tip, questID)
    tip:Show()
    self.drawn = self.drawn + 1
    if not sawReward then
        armRedraw(owner, questID, function() self:_DrawQuest(owner, questID) end)
    end
end

-- The tracker row tooltip, mirroring EQ: title, objectives and rewards on a quest row, plus
-- a faction line and a color-coded countdown on a world quest row. There is no click hint on
-- the row as a whole - with Split quest click on, one sentence describes only half of it,
-- which is why the caller asks for the hint by hovering the icon and not before.
--
-- The hint names focus rather than an arrow because a standalone tracker has no coordinates
-- and cannot place one. The arrow belongs to whatever registered a focus listener.
function RT:ShowForEntry(owner, entry, clickHint)
    if not (owner and entry and entry.id) then return end
    self._redrawLeft = REDRAW_TRIES
    -- Scalars only from here down. An entry is provider-owned and invalid after the next
    -- GetEntries, so the deferred re-draw below must never hold one.
    self:_DrawEntry(owner, entry.id, entry.title, entry.expiresAt, clickHint)
end

function RT:_DrawEntry(owner, questID, title, expiresAt, clickHint)
    local QR = ns:GetModule("QuestRewards")
    if not QR then return end

    -- An expiry is what makes a row a world quest in the Entry shape - Row's own countdown
    -- reads the same field - so it gates both of EQ's world-quest-only lines.
    local tip = Util.Tooltip()
    tip:SetOwner(owner, pickAnchor(owner))
    tip:SetText(QR:Title(questID) or title or "", 1.0, 0.82, 0.0, 1, true)

    if expiresAt then
        local faction = QR:FactionName(questID)
        if faction then tip:AddLine(faction, 0.7, 0.7, 0.7) end
    end

    local drew, sawReward = renderLines(tip, questID)

    if expiresAt then
        local mins = math.floor((expiresAt - time()) / 60)
        if mins > 0 then
            if drew then tip:AddLine(" ") end
            tip:AddLine(L["Time Left: "] .. Util.FmtDuration(mins * 60),
                        Util.TimeColor(mins))
        end
    end

    if clickHint then
        tip:AddLine(" ")
        tip:AddLine(L["Click the icon to focus this quest, or again to clear it."],
                    0.7, 0.7, 0.7, true)
        tip:AddLine(L["Click the title to open the quest log."], 0.7, 0.7, 0.7, true)
    end

    tip:Show()
    if not sawReward then
        armRedraw(owner, questID, function()
            self:_DrawEntry(owner, questID, title, expiresAt, clickHint)
        end)
    end
end

function RT:Hide()
    Util.Tooltip():Hide()
end
