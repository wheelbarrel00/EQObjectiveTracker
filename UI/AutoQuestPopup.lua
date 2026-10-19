local _, ns = ...

local Popup = ns:RegisterModule("AutoQuestPopup", {})
local L     = ns.L

local PAD       = 7
local LINE_GAP  = 2
local BOX_GAP   = 6
local ICON_SIZE = 34
local ICON_LEFT = 10
-- The text is centered in the room right of the icon, so a narrow tracker cannot run it under the icon.
local TEXT_LEFT  = ICON_LEFT + ICON_SIZE + 6
local TEXT_RIGHT = 8
local BORDER = { 0.82, 0.65, 0.13, 0.55 }
local HILITE = { 0.95, 0.78, 0.20, 0.95 }

local pool, active = {}, {}

local function clickThrough()
    local Tracker = ns:GetModule("Tracker")
    return (Tracker and Tracker.IsClickThrough and Tracker:IsClickThrough()) and true or false
end

local function onClick(box)
    if clickThrough() then return end
    local questID, ptype = box.questID, box.popUpType
    if not questID then return end
    -- pcall because both throw on a popup the engine has already retired
    if ptype == "COMPLETE" then
        if ShowQuestComplete then pcall(ShowQuestComplete, questID) end
    elseif ShowQuestOffer then
        pcall(ShowQuestOffer, questID)
    end
    if RemoveAutoQuestPopUp then pcall(RemoveAutoQuestPopUp, questID) end
    ns:GetModule("Tracker"):Refresh()
end

local function buildBox()
    local box = CreateFrame("Button", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate")
    box:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    box:SetBackdropColor(0, 0, 0, 0.85)
    box:SetBackdropBorderColor(BORDER[1], BORDER[2], BORDER[3], BORDER[4])
    box:RegisterForClicks("LeftButtonUp")
    box:SetScript("OnClick", onClick)
    box:SetScript("OnEnter", function(b)
        if clickThrough() then return end
        b:SetBackdropBorderColor(HILITE[1], HILITE[2], HILITE[3], HILITE[4])
    end)
    box:SetScript("OnLeave", function(b)
        b:SetBackdropBorderColor(BORDER[1], BORDER[2], BORDER[3], BORDER[4])
    end)

    box.iconHolder = CreateFrame("Frame", nil, box)
    box.iconHolder:SetSize(ICON_SIZE, ICON_SIZE)
    box.iconHolder:SetPoint("LEFT", box, "LEFT", ICON_LEFT, 0)

    box.iconGlow = box.iconHolder:CreateTexture(nil, "BACKGROUND")
    box.iconGlow:SetSize(44, 44)
    box.iconGlow:SetPoint("CENTER")
    box.iconGlow:SetBlendMode("ADD")
    box.iconGlow:SetAlpha(0.5)

    box.icon = box.iconHolder:CreateTexture(nil, "ARTWORK", nil, 0)
    box.icon:SetSize(30, 30)
    box.icon:SetPoint("CENTER")

    -- No "!" exists in the atlas set, so it is a font overlay. The atlas fallback renders a
    -- "?" which reads as a turn-in and would be wrong on a Discovered box.
    box.bang = box.iconHolder:CreateFontString(nil, "OVERLAY")
    box.bang:SetPoint("CENTER", box.icon, "CENTER", 0, 0)
    box.bang:SetFont(STANDARD_TEXT_FONT, 22, "OUTLINE")
    box.bang:SetTextColor(1, 0.82, 0)
    box.bang:SetText("!")

    box.header = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    box.header:SetJustifyH("CENTER")
    box.header:SetTextColor(0.92, 0.72, 0.02)

    box.title = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    box.title:SetJustifyH("CENTER")
    box.title:SetTextColor(1, 1, 1)

    box.hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    box.hint:SetJustifyH("CENTER")
    box.hint:SetText(L["Click to view quest"])

    box.header:SetPoint("TOPLEFT", box, "TOPLEFT", TEXT_LEFT, -PAD)
    box.title:SetPoint("TOP", box.header, "BOTTOM", 0, -LINE_GAP)
    box.hint:SetPoint("TOP", box.title, "BOTTOM", 0, -LINE_GAP)

    return box
end

local function acquire(parent)
    local box = tremove(pool) or buildBox()
    if box:GetParent() ~= parent then box:SetParent(parent) end
    box:Show()
    active[#active + 1] = box
    return box
end

function Popup:ReleaseAll()
    for i = #active, 1, -1 do
        local box = active[i]
        box:Hide()
        box:ClearAllPoints()
        box.questID, box.popUpType = nil, nil
        pool[#pool + 1] = box
        active[i] = nil
    end
end

-- Appends only. The caller releases every box once per render pass, then calls this once
-- per section, so the two quest groups can each own their own boxes.
function Popup:Render(content, contentWidth, yStart, groupID)
    if not content then return 0 end
    local Popups = ns:GetModule("AutoQuestPopups")
    local n = Popups:Count()
    if n == 0 then return 0 end

    local textW  = math.max(40, (contentWidth or 0) - TEXT_LEFT - TEXT_RIGHT)
    local y      = yStart or 0
    local startY = y
    local Row    = ns:GetModule("Row")

    for i = 1, n do
        local p = Popups:Get(i)
        if p and p.groupID == groupID then
            local box = acquire(content)
            box.questID   = p.questID
            box.popUpType = p.popUpType

            box.header:SetText(p.popUpType == "COMPLETE" and L["Quest Complete!"] or L["Quest Discovered!"])
            box.title:SetText(p.title or "")
            Row:ApplyGenericQuestIcon(box.iconGlow, box.icon)

            box.header:SetWidth(textW)
            box.title:SetWidth(textW)
            box.hint:SetWidth(textW)

            local h = PAD + box.header:GetStringHeight()
                      + LINE_GAP + box.title:GetStringHeight()
                      + LINE_GAP + box.hint:GetStringHeight() + PAD
            if h < ICON_SIZE + PAD * 2 then h = ICON_SIZE + PAD * 2 end
            box:SetHeight(h)
            box:ClearAllPoints()
            box:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -y)
            box:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)

            y = y + h + BOX_GAP
        end
    end

    return y - startY
end
