local _, ns = ...

local Row   = ns:RegisterModule("Row", {})
local Entry = ns:GetModule("Entry")
local Util  = ns.Util
local L     = ns.L

local STATE, LINE, ICON = Entry.STATE, Entry.LINE, Entry.ICON

local PAD_X, PAD_Y     = 6, 2
local ICON_SIZE        = 26
local ICON_GAP         = 4

-- Native atlas size, kept separate from the 26px holder it deliberately overhangs, as EQ
-- does. Drawing these at ICON_SIZE shrinks them to 81% inside the same 50x50 glow.
local POI_ICON_SIZE    = 32

-- The ring deliberately overhangs the 26px icon column, matching the default tracker
local WQ_RING_SIZE     = 33
local WQ_STAR_SIZE     = 18
local WQ_RING_TEXTURE  = "Interface/WorldMap/UI-QuestPoi-NumberIcons"
local WQ_RING_TRACKED  = { 0.500, 0.625, 0.375, 0.5 }
local WQ_RING_NORMAL   = { 0.875, 1.000, 0.375, 0.5 }
local WQ_FALLBACK      = "Worldquest-icon"

-- Used only where the retail POI atlas art is absent. SafeSetAtlas blanks the texture on a
-- miss, so without these the icon column is empty while the row still pays for its width.
-- Both files were measured present on 1.15.9 and 2.5.6. If one were missing too, the result
-- is the same blank it would have been.
local POI_FALLBACK_ACTIVE    = "Interface/GossipFrame/ActiveQuestIcon"
local POI_FALLBACK_AVAILABLE = "Interface/GossipFrame/AvailableQuestIcon"
local GROUP_EYE_SIZE   = 16
local TITLE_TO_SUB     = 1
local SUB_TO_LINES     = 2
local SUBTITLE_COLOR   = { 0.42, 0.69, 1.00 }
local DEFAULT_DONE_HEX = "44ff44"

-- A client with super-track marks its focused row with the -SuperTracked atlas, and that art
-- does not exist anywhere else, so a client without the API gets a title tint instead. Nil is
-- the off switch: every read below is a plain truth test, so retail takes none of these
-- branches and is unchanged. Capability, never a flavor or build number.
local FOCUS_TINT = (not ns.Has.SuperTrack) and { 0.35, 0.90, 1.00 } or nil

-- The width one secure quest-item button needs. Only a row that actually owns an item pays
-- for it - EQ computes this per block rather than indenting the whole list, so one item
-- quest indents one row.
function Row:Gutter()
    local IB = ns:GetModule("ItemButtons")
    return (IB and IB.Gutter) and IB:Gutter() or 0
end

-- ItemButtons reads this rather than keeping its own copy - a stale copy puts the button
-- on the card border instead of inside it.
function Row:Padding(cfg)
    local cardOn, cardPad = ns:GetModule("Card"):State(cfg)
    if cardOn then return cardPad, cardPad end
    return PAD_X, PAD_Y
end

-- Shared by the quest POI rows and the auto-quest popup boxes, so these live here once
-- rather than being copied into each consumer. World quest rows use none of them.
local OUTER_GLOW, CENTER_FACE, CENTER_TURNIN = {}, {}, {}
do
    local QC = (Enum and Enum.QuestClassification) or {}
    local NORMAL = QC.Normal or -1

    OUTER_GLOW[NORMAL]              = "UI-QuestPoi-OuterGlow"
    OUTER_GLOW[QC.Questline or -2]  = "UI-QuestPoi-OuterGlow"
    OUTER_GLOW[QC.Campaign  or -3]  = "UI-QuestPoiCampaign-OuterGlow"
    OUTER_GLOW[QC.Calling   or -4]  = "UI-QuestPoiCampaign-OuterGlow"
    OUTER_GLOW[QC.Important or -5]  = "UI-QuestPoiImportant-OuterGlow"
    OUTER_GLOW[QC.Legendary or -6]  = "UI-QuestPoiLegendary-OuterGlow"
    OUTER_GLOW[QC.Recurring or -7]  = "UI-QuestPoiRecurring-OuterGlow"
    OUTER_GLOW[QC.Meta      or -8]  = "UI-QuestPoiWrapper-OuterGlow"

    CENTER_FACE[NORMAL]             = "UI-QuestPoi-QuestNumber"
    CENTER_FACE[QC.Questline or -2] = "UI-QuestPoi-QuestNumber"
    CENTER_FACE[QC.Campaign  or -3] = "UI-QuestPoiCampaign-QuestNumber"
    CENTER_FACE[QC.Calling   or -4] = "UI-QuestPoiCampaign-QuestNumber"
    CENTER_FACE[QC.Important or -5] = "UI-QuestPoiImportant-QuestNumber"
    CENTER_FACE[QC.Legendary or -6] = "UI-QuestPoiLegendary-QuestNumber"
    CENTER_FACE[QC.Recurring or -7] = "UI-QuestPoiRecurring-QuestNumber"
    CENTER_FACE[QC.Meta      or -8] = "UI-QuestPoiWrapper-QuestNumber"

    CENTER_TURNIN[NORMAL]             = "UI-QuestIcon-TurnIn-Normal"
    CENTER_TURNIN[QC.Questline or -2] = "UI-QuestIcon-TurnIn-Normal"
    CENTER_TURNIN[QC.Campaign  or -3] = "UI-QuestPoiCampaign-QuestBangTurnIn"
    CENTER_TURNIN[QC.Calling   or -4] = "UI-DailyQuestPoiCampaign-QuestBangTurnIn"
    CENTER_TURNIN[QC.Important or -5] = "UI-QuestPoiImportant-QuestBangTurnIn"
    CENTER_TURNIN[QC.Legendary or -6] = "UI-QuestPoiLegendary-QuestBangTurnIn"
    CENTER_TURNIN[QC.Recurring or -7] = "UI-QuestPoiRecurring-QuestBangTurnIn"
    CENTER_TURNIN[QC.Meta      or -8] = "UI-QuestPoiWrapper-QuestBangTurnIn"
end

-- The plain quest POI art, no classification and no bang, for the auto-quest popup boxes.
-- Kept here so the atlas tables above stay the single source.
function Row:ApplyGenericQuestIcon(glow, icon)
    Util.SafeSetAtlas(glow, OUTER_GLOW[(Enum and Enum.QuestClassification
                                       and Enum.QuestClassification.Normal) or -1])
    Util.SafeSetAtlas(icon, CENTER_FACE[(Enum and Enum.QuestClassification
                                        and Enum.QuestClassification.Normal) or -1])
end

local function lookup(tbl, classification)
    local QC = (Enum and Enum.QuestClassification) or {}
    return tbl[classification] or tbl[QC.Normal or -1]
end

local function applyIcon(row, entry)
    local icon = entry.icon
    local kind = icon and icon.kind or ICON.NONE

    if kind == ICON.NONE or not icon then
        row.iconGlow:SetTexture(nil)
        row.icon:SetTexture(nil)
        row.iconBang:SetTexture(nil)
        return
    end

    row.iconGlow:SetVertexColor(1, 1, 1)
    row.icon:SetVertexColor(1, 1, 1)
    row.iconBang:SetVertexColor(1, 1, 1)

    if kind == ICON.QUESTPOI then
        row.icon:SetSize(POI_ICON_SIZE, POI_ICON_SIZE)
        row.iconBang:SetSize(POI_ICON_SIZE, POI_ICON_SIZE)
        local glow = lookup(OUTER_GLOW, icon.classification)
        local baseFace = lookup(CENTER_FACE, icon.classification)
        local face = baseFace
        if entry.isFocused and face then face = face .. "-SuperTracked" end
        local glowOK = Util.SafeSetAtlas(row.iconGlow, glow)
        local faceOK = Util.SafeSetAtlas(row.icon, face)
        -- Keyed on the UNSUFFIXED atlas, never on faceOK alone. lookup falls back to the
        -- Normal face, which resolves on retail, so faceOK is false there only when the
        -- -SuperTracked suffix above found nothing.
        if not faceOK and not Util.AtlasExists(baseFace) then
            row.iconGlow:SetTexture(nil)
            -- Back to the 26px holder size, which the POI branch above widened to 32
            row.icon:SetSize(ICON_SIZE, ICON_SIZE)
            row.icon:SetTexture(entry.state == STATE.COMPLETE
                                and POI_FALLBACK_ACTIVE or POI_FALLBACK_AVAILABLE)
            row.iconBang:SetTexture(nil)
            return
        end
        if entry.state == STATE.COMPLETE then
            Util.SafeSetAtlas(row.iconBang, lookup(CENTER_TURNIN, icon.classification))
        else
            Util.SafeSetAtlas(row.iconBang, "Quest-In-Progress-Icon-yellow")
        end
        if entry.isFocused then
            local ulx, uly = row.icon:GetTexCoord()
            Row._focusIcon = ("id=%s class=%s | face=%s ok=%s tex=%s coord %.3f,%.3f"
                              .. " size %.0fx%.0f a=%.2f | glow=%s ok=%s tex=%s size %.0fx%.0f"
                              .. " a=%.2f | holder a=%.2f row a=%.2f"):format(
                tostring(entry.id), tostring(icon.classification),
                tostring(face), tostring(faceOK), tostring(row.icon:GetTexture()),
                ulx or -1, uly or -1,
                row.icon:GetWidth() or 0, row.icon:GetHeight() or 0, row.icon:GetAlpha() or -1,
                tostring(glow), tostring(glowOK), tostring(row.iconGlow:GetTexture()),
                row.iconGlow:GetWidth() or 0, row.iconGlow:GetHeight() or 0,
                row.iconGlow:GetAlpha() or -1,
                row.iconHolder:GetAlpha() or -1, row:GetAlpha() or -1)
            Row._focusIconAt = GetTime and GetTime() or nil
        end
        return
    end

    if kind == ICON.WORLDQUEST then
        row.iconGlow:SetTexture(nil)
        row.icon:SetSize(WQ_RING_SIZE, WQ_RING_SIZE)
        row.icon:SetTexture(WQ_RING_TEXTURE)
        local c = entry.isFocused and WQ_RING_TRACKED or WQ_RING_NORMAL
        row.icon:SetTexCoord(c[1], c[2], c[3], c[4])
        row.iconBang:SetSize(WQ_STAR_SIZE, WQ_STAR_SIZE)
        Util.SafeSetAtlas(row.iconBang, icon.atlas or WQ_FALLBACK)
        return
    end

    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.iconBang:SetSize(ICON_SIZE, ICON_SIZE)
    row.iconGlow:SetTexture(nil)
    row.iconBang:SetTexture(nil)
    if icon.atlas then
        Util.SafeSetAtlas(row.icon, icon.atlas)
    elseif icon.texture then
        row.icon:SetTexture(icon.texture)
        local c = icon.texCoord
        if c then row.icon:SetTexCoord(c[1], c[2], c[3], c[4]) else row.icon:SetTexCoord(0, 1, 0, 1) end
    else
        row.icon:SetTexture(nil)
    end
end

-- The age matters as much as the line: this only records when a super-tracked POI row is
-- actually repainted, so a stale reading would otherwise read as current.
function Row:DebugLine()
    if not Row._focusIcon then return "focus icon: no super-tracked row drawn" end
    local age = (GetTime and Row._focusIconAt) and (GetTime() - Row._focusIconAt) or -1
    return ("focus icon: %s | drawn %.1fs ago"):format(Row._focusIcon, age)
end

local function doneHex(cfg)
    if not cfg or cfg.overrideCompleteGreen == false then return DEFAULT_DONE_HEX end
    local r, g, b = Util.EffectiveTitleColor(cfg)
    if r then return Util.Hex(r, g, b) end
    return DEFAULT_DONE_HEX
end

-- Every user styling option is applied here, once, so it reaches every content type.
local _scratch = {}
local function buildLineText(entry, cfg)
    local lines  = entry.lines
    local hex    = doneHex(cfg)
    local hideN  = cfg and cfg.showObjectiveNumbers == false
    local simple = cfg and cfg.simplifyMode

    local groups   = cfg and cfg.simplifyGroups
    local hideDone = simple or (groups and entry.groupID and groups[entry.groupID]) or false

    local n = 0
    for i = 1, #lines do
        local ln = lines[i]
        if not (hideDone and ln.completed) then
            local text = ln.text or ""
            if not ln.richText then
                if ln.kind == LINE.PROGRESSBAR and ln.required and ln.required > 0 then
                    local meter = tostring(ln.current or 0) .. "/" .. tostring(ln.required)
                    -- A finished bar reads as its label alone, matching the default
                    -- tracker. With no label the meter is all there is, so it stays.
                    if not ln.completed then
                        text = (text ~= "") and (meter .. " " .. text) or meter
                    elseif text == "" then
                        text = meter
                    end
                end
                if hideN then text = Util.StripLeadingCount(text) end
                if ln.completed then
                    text = "|A:common-icon-checkmark:12:12|a |cff" .. hex .. text .. "|r"
                elseif ln.kind == LINE.NOTE then
                    text = "|cff999999- " .. text .. "|r"
                else
                    text = "- " .. Util.ColorizeProgress(text)
                end
            end
            n = n + 1
            _scratch[n] = text
            if simple then break end
        end
    end

    -- Everything finished still needs to show the last line, or the entry renders with a
    -- bare title and reads as though it had no objectives at all
    if n == 0 and hideDone and #lines > 0 then
        local last = lines[#lines]
        n = 1
        _scratch[1] = "|A:common-icon-checkmark:12:12|a |cff" .. hex .. (last.text or "") .. "|r"
    end

    if n == 0 then return "" end
    return table.concat(_scratch, "\n", 1, n)
end

-- EQ applies all three of these inside _RenderQuestGroup, so only quest and campaign rows
-- get them - the same set that pays for the item-button gutter, for the same reason.
local TITLE_META_PROVIDER = "quests"
local NEW_WINDOW = 3600
local NEW_TAG    = "|cff6BAFFFNEW|r "
-- Escaped U+2605 so this file stays ASCII, matching EQ's pinned marker.
local PIN_TAG    = "|cffEBB706\226\152\133|r "

local function decorateTitle(entry, cfg)
    local text = entry.title or ""
    if not cfg or entry.providerID ~= TITLE_META_PROVIDER then return text end

    if cfg.showLevelInTracker and entry.level and entry.level > 0 then
        text = ("[%d] %s"):format(entry.level, text)
    end
    if cfg.showQuestID and entry.id then
        text = text .. (" |cff666666(#%d)|r"):format(entry.id)
    end
    -- Pin before the NEW tag, matching EQ, so a quest that is both reads "NEW * Title".
    -- Decorated here rather than gated separately: row._sTitle stores the finished string,
    -- so the pin repaints for free.
    if ns:GetModule("Filter"):IsPinned(entry) then
        text = PIN_TAG .. text
    end
    if cfg.showRecentlyAddedTag ~= false and entry.addedAt and entry.addedAt > 0
       and (time() - entry.addedAt) < NEW_WINDOW then
        text = NEW_TAG .. text
    end
    return text
end

local function clickThrough()
    local Tracker = ns:GetModule("Tracker")
    return (Tracker and Tracker.IsClickThrough and Tracker:IsClickThrough()) and true or false
end

local function dispatch(row, fnName, ...)
    if clickThrough() then return end
    local Registry = ns:GetModule("Registry")
    local provider = row._providerID and Registry:Get(row._providerID)
    if not (provider and provider[fnName] and row._entry) then return end
    provider[fnName](provider, row._entry, ...)
end

local function splitClickWanted(row)
    local DB  = ns:GetModule("DB")
    local cfg = DB and DB:Tracker()
    if not (cfg and cfg.splitQuestClick) then return false end
    local Registry = ns:GetModule("Registry")
    local provider = row._providerID and Registry:Get(row._providerID)
    return (provider and provider.OnEntryOpenLog) and true or false
end

-- Hit-tested by cursor X rather than by parenting the click to the icon: a mouse-enabled
-- icon child would swallow drags that start on it. GetCursorPosition returns raw pixels, so
-- it needs dividing by the effective scale before comparing against GetRight.
local function overIcon(row)
    local ih = row.iconHolder
    if not (ih and ih:IsShown()) then return false end
    local iconRight = ih:GetRight()
    if not iconRight then return false end
    local mx = GetCursorPosition() / (row:GetEffectiveScale() or 1)
    return mx <= iconRight
end

local function onMouseUp(row, button)
    local wasDragging = row._wasDragging
    row._wasDragging = nil
    if wasDragging then return end
    if not row._entry or clickThrough() then return end
    if IsModifiedClick and IsModifiedClick("QUESTWATCHTOGGLE") then
        local Filter = ns:GetModule("Filter")
        Filter:SetHidden(row._entry, not Filter:IsHidden(row._entry))
        local Tracker = ns:GetModule("Tracker")
        if Tracker then Tracker:Refresh() end
        return
    end

    if button == "LeftButton" and splitClickWanted(row) and not overIcon(row) then
        dispatch(row, "OnEntryOpenLog")
        return
    end

    -- A provider that offers no menu keeps its existing right-click, so nothing changes for
    -- achievements or professions.
    if button == "RightButton" then
        local RowMenu = ns:GetModule("RowMenu")
        if RowMenu and RowMenu:Show(row) then return end
    end

    dispatch(row, "OnEntryClick", button)
end

-- Offered only where both halves are really wired: the focus gesture needs a client with no
-- super-track, and the title half only opens the quest log while Split quest click is on.
local function splitHintWanted(row)
    return (FOCUS_TINT and splitClickWanted(row) and overIcon(row)) and true or false
end

local function paintTooltip(row)
    local Registry = ns:GetModule("Registry")
    local provider = row._providerID and Registry:Get(row._providerID)
    if not provider then return end
    -- A provider whose ids ARE quest ids gets EQ's rich tooltip. It is drawn here rather
    -- than by the provider because it needs coin textures, item quality colors and the
    -- ilvl comparison, none of which Data/ may build.
    if provider.idSpace == "quest" then
        local RT = ns:GetModule("RewardTooltip")
        if RT then RT:ShowForEntry(row, row._entry, row._hintShown) end
        return
    end
    if not provider.OnEntryTooltip then return end
    local tip = ns.Util.Tooltip()
    tip:SetOwner(row, "ANCHOR_RIGHT")
    provider:OnEntryTooltip(row._entry, tip)
    tip:Show()
end

-- The cursor crosses between the icon and the title without ever leaving the row, and OnEnter
-- does not fire again for that, so the half is re-tested while the row is hovered. Installed
-- only on a row that can actually show the hint, and only one row is hovered at a time.
local HINT_POLL = 0.1
local function onUpdateHalf(row, elapsed)
    row._hintClock = (row._hintClock or 0) + elapsed
    if row._hintClock < HINT_POLL then return end
    row._hintClock = 0
    local want = splitHintWanted(row)
    if want ~= row._hintShown then
        row._hintShown = want
        paintTooltip(row)
    end
end

local function onEnter(row)
    if row._wasDragging then return end
    if not row._entry or clickThrough() then return end
    row._hintShown = splitHintWanted(row)
    paintTooltip(row)
    if FOCUS_TINT and splitClickWanted(row) then
        row._hintClock = 0
        row:SetScript("OnUpdate", onUpdateHalf)
    end
end

-- Shared with the group-finder button, which has no icon holder and never polls.
local function onLeave(frame)
    ns.Util.Tooltip():Hide()
    if frame and frame.iconHolder then
        frame:SetScript("OnUpdate", nil)
        frame._hintShown, frame._hintClock = nil, nil
    end
end

function Row:Build()
    local r = CreateFrame("Frame")

    r.iconHolder = CreateFrame("Frame", nil, r)
    r.iconHolder:SetSize(ICON_SIZE, ICON_SIZE)

    r.iconGlow = r.iconHolder:CreateTexture(nil, "BACKGROUND")
    r.iconGlow:SetSize(50, 50)
    r.iconGlow:SetPoint("CENTER")
    r.iconGlow:SetBlendMode("ADD")
    r.iconGlow:SetAlpha(0.5)

    r.icon = r.iconHolder:CreateTexture(nil, "ARTWORK", nil, 0)
    r.icon:SetSize(POI_ICON_SIZE, POI_ICON_SIZE)
    r.icon:SetPoint("CENTER")

    r.iconBang = r.iconHolder:CreateTexture(nil, "ARTWORK", nil, 1)
    r.iconBang:SetSize(POI_ICON_SIZE, POI_ICON_SIZE)
    r.iconBang:SetPoint("CENTER")

    r.title = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.title:SetJustifyH("LEFT")
    r.title:SetWordWrap(true)

    r.subtitle = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.subtitle:SetJustifyH("LEFT")
    r.subtitle:SetWordWrap(false)
    r.subtitle:SetTextColor(SUBTITLE_COLOR[1], SUBTITLE_COLOR[2], SUBTITLE_COLOR[3])

    r.lines = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.lines:SetJustifyH("LEFT")
    r.lines:SetWordWrap(true)
    r.lines:SetTextColor(0.85, 0.85, 0.85)

    r.timer = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.timer:SetJustifyH("RIGHT")
    r.timer:SetWordWrap(false)
    r.timer:Hide()

    r.groupFinder = CreateFrame("Button", nil, r)
    r.groupFinder:SetSize(GROUP_EYE_SIZE, GROUP_EYE_SIZE)
    r.groupFinder.icon = r.groupFinder:CreateTexture(nil, "ARTWORK")
    r.groupFinder.icon:SetAllPoints()
    r.groupFinder.icon:SetAtlas("groupfinder-eye-single")
    r.groupFinder:Hide()
    r.groupFinder:SetScript("OnClick", function(btn)
        dispatch(btn:GetParent(), "OnEntryGroupFinder")
    end)
    r.groupFinder:SetScript("OnEnter", function(btn)
        if clickThrough() then return end
        local tip = ns.Util.Tooltip()
        tip:SetOwner(btn, "ANCHOR_LEFT")
        tip:SetText(L["Find Group"], 1, 1, 1)
        tip:AddLine(L["Open the Premade Group Finder for this quest."], 0.7, 0.7, 0.7, true)
        tip:Show()
    end)
    r.groupFinder:SetScript("OnLeave", onLeave)

    r:EnableMouse(true)
    r:SetScript("OnMouseUp", onMouseUp)
    r:SetScript("OnEnter", onEnter)
    r:SetScript("OnLeave", onLeave)

    local DragDrop = ns:GetModule("DragDrop")
    if DragDrop then DragDrop:Wire(r) end

    return r
end

function Row:Reset(row)
    row._entry, row._providerID = nil, nil
    row._wasDragging = nil
    row:SetScript("OnUpdate", nil)
    row._hintShown, row._hintClock = nil, nil
    row._sTitle, row._sSub, row._sState  = nil, nil, nil
    row._sFocus, row._sWidth, row._sText = nil, nil, nil
    row._sTime, row._sGen, row._sCardBg  = nil, nil, nil
    row._sGroup, row._sIcon, row._sItem = nil, nil, nil
    ns:GetModule("Card"):Clear(row)
end

Row.generation = 0

function Row:Invalidate()
    self.generation = self.generation + 1
end

function Row:Render(row, entry, width, cfg)
    row._entry      = entry
    row._providerID = entry.providerID

    local titleText = decorateTitle(entry, cfg)
    local subtitle = (cfg and cfg.showZoneTag ~= false) and entry.subtitle or nil
    local lineText = buildLineText(entry, cfg)
    local showEye  = entry.canGroup and true or false
    -- The effective answer, not the raw field, so turning the option off drops the gutter
    -- as well as the button and both land through the one repaint gate below.
    local hasItem  = (entry.hasItem and (not cfg or cfg.showItemButtons ~= false)) and true or false

    -- Providers resolve icons late on purpose - a world quest falls back to the generic
    -- marker until its tag info streams in - so the icon has to sit in the repaint gate
    -- or that second answer never reaches the screen.
    local icon    = entry.icon
    local iconKey = icon and (icon.atlas or icon.texture or icon.classification) or nil

    local timeText, timeMins
    if entry.expiresAt then
        timeMins = math.floor((entry.expiresAt - time()) / 60)
        if timeMins > 0 then timeText = Util.TimeShort(timeMins) end
    end

    local Card = ns:GetModule("Card")
    local cardOn, _, cardBorderSize = Card:State(cfg)
    local cardBg, cardBorder
    if cardOn then
        cardBg, cardBorder = Card:Colors(cfg)
        if cfg and cfg.cardTintByType then cardBg = Card:TintFor(cfg, entry) or cardBg end
    end

    -- The resolved color is compared by table identity, which is stable per option and
    -- changes whenever a setter assigns a new one, so tint swaps repaint without a bump.
    local unchanged =
           row._sTitle == titleText
       and row._sSub   == subtitle
       and row._sState == entry.state
       and row._sFocus == entry.isFocused
       and row._sWidth == width
       and row._sText  == lineText
       and row._sTime  == timeText
       and row._sCardBg == cardBg
       and row._sGroup == showEye
       and row._sIcon  == iconKey
       and row._sItem  == hasItem
       and row._sGen   == self.generation
    if unchanged then return row:GetHeight() end

    applyIcon(row, entry)

    local padX, padY = self:Padding(cfg)

    -- Zero inset: the row frame already carries the card's padding, so the card tracks it
    if cardOn then
        Card:Draw(row, nil, 0, cardBorderSize, cardBg, cardBorder)
    else
        Card:Clear(row)
    end

    local Media = ns:GetModule("Media")
    Media:ApplyTitleFont(row.title)
    Media:ApplyFont(row.subtitle, -3)
    Media:ApplyFont(row.lines, -2)
    Media:ApplyFont(row.timer, -2)
    row.lines:SetSpacing(Media:LineSpacing())

    -- A provider that emits no icon should not pay for the icon column, or its titles
    -- hang in empty space where the art would have been.
    local hasIcon = ((entry.icon and entry.icon.kind) or ICON.NONE) ~= ICON.NONE
    local iconW   = hasIcon and ICON_SIZE or 0
    local iconGap = hasIcon and ICON_GAP or 0

    local gutter = hasItem and self:Gutter() or 0
    row.iconHolder:SetSize(math.max(1, iconW), ICON_SIZE)
    row.iconHolder:ClearAllPoints()
    row.iconHolder:SetPoint("TOPLEFT", row, "TOPLEFT", padX + gutter, -padY)

    -- The eye takes the right edge and the countdown shuffles left of it, so a world
    -- quest that can form a group still shows how long is left on it.
    row.groupFinder:ClearAllPoints()
    row.groupFinder:SetPoint("TOPRIGHT", row, "TOPRIGHT", -padX, -padY)
    row.groupFinder:SetShown(showEye)
    local eyeW = showEye and (GROUP_EYE_SIZE + 4) or 0

    row.timer:ClearAllPoints()
    row.timer:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(padX + eyeW), -padY)
    local timerW = 0
    if timeText then
        row.timer:SetText(timeText)
        row.timer:SetTextColor(Util.TimeColor(timeMins))
        row.timer:Show()
        timerW = row.timer:GetStringWidth() + 6
    else
        row.timer:SetText("")
        row.timer:Hide()
    end

    -- Widths are explicit rather than left to a TOPRIGHT anchor, so the timer only ever
    -- narrows the title. Objectives keep the full column.
    row.title:ClearAllPoints()
    row.title:SetPoint("TOPLEFT", row.iconHolder, "TOPRIGHT", iconGap, 1)

    -- Anchor the subtitle even when hidden - the lines below hang off it, so leaving it
    -- unpositioned drops the objectives off the frame the moment it is shown
    row.subtitle:ClearAllPoints()
    row.subtitle:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -TITLE_TO_SUB)

    local subGap = math.max(0, SUB_TO_LINES + Media:HeaderSpacing())
    local textW = width - (iconW + iconGap + padX * 2 + gutter)
    if textW > 0 then
        row.title:SetWidth(math.max(1, textW - timerW - eyeW))
        row.lines:SetWidth(textW)
    end
    row.title:SetText(titleText)

    local ovR, ovG, ovB = Util.EffectiveTitleColor(cfg)
    -- Recoloring completed entries needs a color to recolor them TO, so the toggle is
    -- inert until an override or class color is set.
    local recolorComplete = ovR and (not cfg or cfg.overrideCompleteGreen ~= false)
    if FOCUS_TINT and entry.isFocused then
        -- Ahead of the state colors deliberately: there is exactly one focused row, it is the
        -- one the player just picked, and on this client nothing else marks it.
        row.title:SetTextColor(FOCUS_TINT[1], FOCUS_TINT[2], FOCUS_TINT[3])
    elseif entry.state == STATE.FAILED then
        row.title:SetTextColor(0.85, 0.27, 0.27)
    elseif entry.state == STATE.COMPLETE and not recolorComplete then
        row.title:SetTextColor(0.27, 0.85, 0.27)
    elseif ovR then
        row.title:SetTextColor(ovR, ovG, ovB)
    elseif (not cfg or cfg.colorByDifficulty ~= false) and entry.level and GetQuestDifficultyColor then
        local c = GetQuestDifficultyColor(entry.level)
        row.title:SetTextColor(c.r, c.g, c.b)
    else
        row.title:SetTextColor(0.92, 0.72, 0.02)
    end

    row.lines:ClearAllPoints()
    if subtitle and subtitle ~= "" then
        row.subtitle:SetWidth(textW)
        row.subtitle:SetText(subtitle)
        row.subtitle:Show()
        row.lines:SetPoint("TOPLEFT", row.subtitle, "BOTTOMLEFT", 0, -subGap)
    else
        row.subtitle:SetText("")
        row.subtitle:Hide()
        row.lines:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -subGap)
    end
    row.lines:SetText(lineText)

    local titleH = row.title:GetStringHeight()
    local subH   = row.subtitle:IsShown() and (TITLE_TO_SUB + row.subtitle:GetStringHeight()) or 0
    local linesH = (lineText ~= "") and (subGap + row.lines:GetStringHeight()) or 0
    local textH  = titleH + subH + linesH
    local h      = math.max(textH, iconW) + padY * 2

    row:SetHeight(math.max(1, h))

    row._sTitle, row._sSub, row._sState = titleText, subtitle, entry.state
    row._sFocus, row._sWidth, row._sText = entry.isFocused, width, lineText
    row._sTime = timeText
    row._sCardBg = cardBg
    row._sGroup = showEye
    row._sIcon = iconKey
    row._sItem = hasItem
    row._sGen = self.generation

    return row:GetHeight()
end
