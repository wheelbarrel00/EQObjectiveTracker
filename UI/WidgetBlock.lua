local _, ns = ...

local WidgetBlock = ns:RegisterModule("WidgetBlock", {})
local Util        = ns.Util

-- Draws the widget sets EQOT hides. Blizzard shows these inside ObjectiveTrackerFrame and
-- inside the scenario stage block, both of which this addon takes off screen, so without this
-- the information is simply gone - which is what a user reported for delves and for the events
-- that borrow the scenario panel.
--
-- Four runs, drawn where Blizzard draws them: the tracker's own set at the top of the container,
-- the scenario's step set between the banner and the criteria, and the scenario tracker's two
-- fixed sets under the criteria. They keep separate pools because several are on screen at once
-- and each releases its own frames, so one pool would have each draw retire the others'.
--
-- The frames here are our own. Nothing registers a UIWidgetContainer against a Blizzard widget
-- set, and nothing may - see the note in UI/Scenario.lua.

-- Height and texture come from Media's shared progress bar block, so there is no constant for
-- either here. See buildBar for what a widget bar does NOT take from it.
local ROW_GAP     = 3
local SIDE_PAD    = 8
local TICK        = 0.1

local DEFAULT_TINT = { 0.26, 0.42, 1.00 }

-- Keyed by the enum member NAME, so a value Blizzard renumbers or adds lands on the default
-- instead of on the wrong color.
local TINT_BY_NAME = {
    Black  = { 0.15, 0.15, 0.15 },
    White  = { 0.85, 0.85, 0.85 },
    Red    = { 0.80, 0.20, 0.20 },
    Yellow = { 0.90, 0.80, 0.20 },
    Orange = { 0.90, 0.50, 0.15 },
    Purple = { 0.60, 0.30, 0.80 },
    Green  = { 0.20, 0.75, 0.30 },
    Blue   = { 0.26, 0.42, 1.00 },
}

local tintByValue
local function tintFor(textureKit, value)
    -- The texture kit names the fill color outright on the bars measured so far, and colorTint
    -- read 0 beside it, so the kit is asked first and the tint is the fallback.
    if textureKit and TINT_BY_NAME[textureKit] then return TINT_BY_NAME[textureKit] end
    if not tintByValue then
        tintByValue = {}
        local CT = Enum and Enum.StatusBarColorTintValue
        if type(CT) == "table" then
            for name, v in pairs(CT) do tintByValue[v] = TINT_BY_NAME[name] end
        end
    end
    return (value and tintByValue[value]) or DEFAULT_TINT
end

-- Util.FmtDuration rounds to whole minutes, which reads as a frozen "2m" for the whole of a
-- three minute countdown. A scenario timer is drawn as a clock, the way the default one is.
local function clock(secs)
    secs = math.max(0, math.floor(secs or 0))
    local h = math.floor(secs / 3600)
    if h > 0 then
        return ("%d:%02d:%02d"):format(h, math.floor((secs % 3600) / 60), secs % 60)
    end
    return ("%02d:%02d"):format(math.floor(secs / 60), secs % 60)
end

-- Blizzard names the format on the widget rather than sending the finished string, so the
-- kinds are matched by name. An unrecognized one falls through to value over max, which is
-- the reading that loses the least.
local function valueText(w, value)
    if w.overrideText then return w.overrideText end
    local kind = w.valueTextKind
    local minV, maxV = w.min or 0, w.max or 0
    value = value or w.value or 0
    if kind == "Hidden" then return nil end
    if kind == "Percentage" then
        local span = maxV - minV
        if span <= 0 then return nil end
        return ("%d%%"):format(math.floor(((value - minV) / span) * 100 + 0.5))
    end
    if kind == "Value" then return tostring(value) end
    if kind == "Time" or kind == "TimeShowOneLevelOnly" then return clock(value) end
    if kind == "ValueOverMaxNormalized" then
        return ("%d / %d"):format(value - minV, maxV - minV)
    end
    return ("%d / %d"):format(value, maxV)
end

local function clickThrough()
    local Tracker = ns:GetModule("Tracker")
    return (Tracker and Tracker.IsClickThrough and Tracker:IsClickThrough()) and true or false
end

-- A spell with no tooltip text of its own shows the spell's, as Blizzard's widget does.
local function onEnter(frame)
    if clickThrough() or not (frame._tooltip or frame._spellID) then return end
    local tip = Util.Tooltip()
    tip:SetOwner(frame, "ANCHOR_RIGHT")
    if frame._tooltip then
        tip:SetText(frame._tooltip, 1, 1, 1, 1, true)
    else
        tip:SetSpellByID(frame._spellID)
    end
    tip:Show()
end

local function onLeave()
    Util.Tooltip():Hide()
end

-- A countdown ticks between server pushes, so it runs locally off a deadline the READER stamps
-- when it takes the value, and the next widget update re-stamps it. Bounded: installed only on
-- a bar currently drawing a timer, cleared when that bar is retired, and a hidden frame runs no
-- OnUpdate.
local function onUpdateCountdown(bar, elapsed)
    bar._clock = (bar._clock or 0) + elapsed
    if bar._clock < TICK then return end
    bar._clock = 0
    local left = math.max(0, (bar._deadline or 0) - GetTime())
    bar:SetValue(math.max(bar._cdMin or 0, math.min(bar._cdMax or 0, left)))
    bar.value:SetText(clock(left))
    if left <= 0 then bar:SetScript("OnUpdate", nil) end
end

local function newState()
    return { barPool = {}, bars = {}, textPool = {}, texts = {}, delvePool = {}, delves = {} }
end

WidgetBlock.top         = newState()
WidgetBlock.scenario    = newState()
WidgetBlock.belowTop    = newState()
WidgetBlock.belowBottom = newState()

-- Texture, background and border come from Media's shared progress bar block in Render below,
-- so a widget bar matches the criteria bars it draws beside. The fill color does NOT: it is
-- decoded per widget from Blizzard's textureKit and is what separates one widget's state from
-- another. The bg and border are built here because that helper styles them and creates neither.
local function buildBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)

    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()

    bar.border = CreateFrame("Frame", nil, bar, BackdropTemplateMixin and "BackdropTemplate")
    bar.border:SetPoint("TOPLEFT", -1, 1)
    bar.border:SetPoint("BOTTOMRIGHT", 1, -1)
    bar.border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })

    bar.value = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.value:SetJustifyH("RIGHT")
    bar.value:SetWordWrap(false)
    bar.value:SetPoint("RIGHT", bar, "RIGHT", -4, 0)

    -- Bounded on the right by the meter rather than left to run under it
    bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.label:SetJustifyH("LEFT")
    bar.label:SetWordWrap(false)
    bar.label:SetPoint("LEFT",  bar, "LEFT", 4, 0)
    bar.label:SetPoint("RIGHT", bar.value, "LEFT", -4, 0)

    bar:EnableMouse(true)
    bar:SetScript("OnEnter", onEnter)
    bar:SetScript("OnLeave", onLeave)
    return bar
end

local function buildText(parent)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    fs:SetTextColor(0.85, 0.85, 0.85)
    return fs
end

-- The affix icon is round, as Blizzard masks it, and its earned check is Blizzard's own.
local function buildCounter(parent, round)
    local c = CreateFrame("Frame", nil, parent)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetPoint("LEFT", c, "LEFT", 0, 0)
    if round then
        c.mask = c:CreateMaskTexture()
        c.mask:SetAllPoints(c.icon)
        c.mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask",
                          "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        c.icon:AddMaskTexture(c.mask)
        c.check = c:CreateTexture(nil, "OVERLAY")
        c.check:SetPoint("TOPRIGHT", c.icon, "TOPRIGHT", 3, 3)
        Util.SafeSetAtlas(c.check, "common-icon-checkmark")
    end
    c.text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.text:SetWordWrap(false)
    c:EnableMouse(true)
    c:SetScript("OnEnter", onEnter)
    c:SetScript("OnLeave", onLeave)
    return c
end

local function buildDelveRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.tier = buildText(row)
    row.tier:SetWordWrap(false)
    row.tier:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.nem = buildCounter(row, true)
    row.lives = buildCounter(row, false)
    return row
end

local COUNTER_GAP, COUNTER_SPACE = 4, 10
local TEXT_GRAY = { 0.85, 0.85, 0.85 }
local LIVES_LOW  = { 1, 0.5, 0.25 }
local LIVES_LAST = { 1, 0.2, 0.2 }

local function fillCounter(c, iconID, text, color, tooltip, spellID, earned, size)
    local Media = ns:GetModule("Media")
    c.icon:SetSize(size, size)
    c.icon:SetTexture(iconID)
    c.icon:SetShown(iconID ~= nil)
    if c.check then
        local s = math.floor(size * 0.75 + 0.5)
        c.check:SetSize(s, s)
        c.check:SetShown(earned and true or false)
    end
    Media:ApplyFont(c.text, -2)
    Media:ApplyTextShadow(c.text)
    c.text:SetText(text or "")
    c.text:SetTextColor(color[1], color[2], color[3])
    c.text:ClearAllPoints()
    local w = iconID and size or 0
    if text and text ~= "" then
        if iconID then w = w + COUNTER_GAP end
        c.text:SetPoint("LEFT", c, "LEFT", w, 0)
        w = w + math.ceil(c.text:GetStringWidth() or 0)
    end
    c._tooltip, c._spellID = tooltip, spellID
    c:SetSize(math.max(w, 1), size)
    c:Show()
    return w
end

local function livesColor(lives)
    if lives <= 1 then return LIVES_LAST end
    if lives == 2 then return LIVES_LOW end
    return TEXT_GRAY
end

-- The tier on the left, then the nemesis affix and the lives at the right edge, as Blizzard's
-- own delve header lays them out. Returns the row's height.
local function fillDelveRow(row, w, width)
    local Media = ns:GetModule("Media")
    Media:ApplyFont(row.tier, -2)
    Media:ApplyTextShadow(row.tier)
    row.tier:SetText(w.text or "")
    -- Sized to the tier text, never under 14, so a large font does not leave the icons small.
    local size = math.max(14, math.ceil((row.tier:GetStringHeight() or 0) + 3))
    row:SetSize(width, size)

    local right = 0
    row.lives:ClearAllPoints()
    row.nem:ClearAllPoints()
    if w.lives then
        right = fillCounter(row.lives, w.livesIcon, tostring(w.lives), livesColor(w.lives), w.livesTip,
                            nil, false, size) + COUNTER_SPACE
        row.lives:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    else
        row.lives:Hide()
    end
    if w.nemAlive then
        -- Groups killed, as the bonus objectives HUD counts them. The check sits on the affix icon,
        -- so an affix drawn with no icon keeps its N/N.
        local earned = w.nemAlive == 0 and w.nemIcon ~= nil
        local killed = math.max(0, w.nemTotal - w.nemAlive)
        local text = (not earned) and (killed .. "/" .. w.nemTotal) or nil
        fillCounter(row.nem, w.nemIcon, text, TEXT_GRAY, w.nemTip, w.nemSpell, earned, size)
        row.nem:SetPoint("RIGHT", row, "RIGHT", -right, 0)
    else
        row.nem:Hide()
    end
    row:Show()
    return size
end

local function release(state)
    for i = #state.bars, 1, -1 do
        local bar = state.bars[i]
        bar:SetScript("OnUpdate", nil)
        bar._deadline, bar._clock, bar._tooltip = nil, nil, nil
        bar:Hide()
        bar:ClearAllPoints()
        state.barPool[#state.barPool + 1] = bar
        state.bars[i] = nil
    end
    for i = #state.texts, 1, -1 do
        local fs = state.texts[i]
        fs:SetText("")
        fs:Hide()
        fs:ClearAllPoints()
        state.textPool[#state.textPool + 1] = fs
        state.texts[i] = nil
    end
    for i = #state.delves, 1, -1 do
        local row = state.delves[i]
        row.nem._tooltip, row.nem._spellID, row.lives._tooltip = nil, nil, nil
        row:Hide()
        row:ClearAllPoints()
        state.delvePool[#state.delvePool + 1] = row
        state.delves[i] = nil
    end
end

-- Render-driven, so IsModuleDisabled's OnEnable gate never reaches it and this asks for itself.
-- IsModuleDisabled, never SafeMode, or an explicit /eqot enable cannot override it. Both names
-- because /eqot modules lists both, and asked BEFORE the set id is fetched - behind that call a
-- disabled module still reached C_UIWidgetManager once per render.
local function widgetsOff(cfg)
    return ns:IsModuleDisabled("WidgetBlock") or ns:IsModuleDisabled("Widgets")
        or (cfg and cfg.showTrackerWidgets == false)
end

local function draw(state, container, cfg, top, setID)
    release(state)

    local W = ns:GetModule("Widgets")
    if not setID or not (W and W:IsAvailable()) then
        if W and W.Forget then W:Forget(setID) end
        return 0
    end

    local list, n = W:Read(setID)
    if n == 0 then return 0 end

    local Media = ns:GetModule("Media")
    local width = math.max(1, (container:GetWidth() or 1) - SIDE_PAD * 2)
    local y     = top

    for i = 1, n do
        local w = list[i]
        if w.kind == "bar" then
            local bar = tremove(state.barPool) or buildBar(container)
            if bar:GetParent() ~= container then bar:SetParent(container) end
            state.bars[#state.bars + 1] = bar

            Media:ApplyFont(bar.label, -2)
            Media:ApplyFont(bar.value, -2)
            bar.label:SetText(w.text or "")
            -- A countdown's raw value is frozen between server pushes, so painting from it shows
            -- the time as it was when the server last spoke and onUpdateCountdown corrects it one
            -- tick later: a visible upward flash of the clock on every repaint. Both the text and
            -- the fill below are seeded from the deadline instead, which is what the ticker reads.
            local left = (w.countdown and w.deadline) and math.max(0, w.deadline - GetTime())
            bar.value:SetText(left and clock(left) or (valueText(w) or ""))
            Media:ApplyTextShadow(bar.label)
            Media:ApplyTextShadow(bar.value)

            -- A widget bar keeps its label INSIDE it, unlike the criteria bars, so the user's
            -- height is a FLOOR here rather than the answer: the label is drawn at their Font
            -- Size and a large font would otherwise overflow into the block below.
            Media:ApplyProgressBar(bar, true)
            local barH = math.max(Media:ProgressBarHeight(),
                                  math.ceil((bar.label:GetStringHeight() or 0) + 4))
            bar:SetHeight(barH)

            local tint = tintFor(w.textureKit, w.colorTint)
            bar:SetStatusBarColor(tint[1], tint[2], tint[3])
            bar:SetMinMaxValues(w.min, w.max)
            bar:SetValue(math.max(w.min, math.min(w.max, left or w.value)))
            bar:SetWidth(width)
            bar:ClearAllPoints()
            bar:SetPoint("TOPLEFT", container, "TOPLEFT", SIDE_PAD, -y)
            bar._tooltip = w.tooltip

            if w.countdown then
                -- w.deadline, not GetTime() + w.value: the value is frozen between server
                -- pushes, so re-deriving it here restarted the clock on every repaint.
                bar._deadline = w.deadline or (GetTime() + (w.value or 0))
                bar._cdMin, bar._cdMax, bar._clock = w.min, w.max, 0
                bar:SetScript("OnUpdate", onUpdateCountdown)
            end

            bar:Show()
            y = y + barH + ROW_GAP
        elseif w.kind == "delve" then
            local row = tremove(state.delvePool) or buildDelveRow(container)
            if row:GetParent() ~= container then row:SetParent(container) end
            state.delves[#state.delves + 1] = row
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", container, "TOPLEFT", SIDE_PAD, -y)
            y = y + fillDelveRow(row, w, width) + ROW_GAP
        else
            local fs = tremove(state.textPool) or buildText(container)
            state.texts[#state.texts + 1] = fs
            Media:ApplyFont(fs, -2)
            fs:SetWidth(width)
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", container, "TOPLEFT", SIDE_PAD, -y)
            fs:SetText(w.text or "")
            Media:ApplyTextShadow(fs)
            fs:Show()
            y = y + fs:GetStringHeight() + ROW_GAP
        end
    end

    return y - top
end

-- Data may never reach into UI, so the widget reader announces a change and this is what turns
-- it into a repaint. Same seam ZoneProgress and ScenarioBonus use.
function WidgetBlock:OnEnable()
    local W = ns:GetModule("Widgets")
    if not (W and W.OnDirty) then return end
    W:OnDirty(function()
        local Tracker = ns:GetModule("Tracker")
        if Tracker then Tracker:Refresh() end
    end)
end

-- The tracker's own set, at the top of the block. Blizzard draws it above its modules.
function WidgetBlock:Render(container, cfg, top)
    if widgetsOff(cfg) then release(self.top) return 0 end
    local W = ns:GetModule("Widgets")
    return draw(self.top, container, cfg, top or 0, W and W:TrackerSetID())
end

-- The scenario's set, between the banner and the criteria, which is where the stage block puts
-- it. Driven from UI/Scenario.lua because only that knows where its banner ends.
function WidgetBlock:RenderScenario(container, cfg, top)
    if widgetsOff(cfg) then release(self.scenario) return 0 end
    local W = ns:GetModule("Widgets")
    return draw(self.scenario, container, cfg, top or 0, W and W:ScenarioSetID())
end

-- The scenario tracker's two fixed sets, top block then bottom block, under the criteria and the
-- spells. Driven from UI/Scenario.lua, so they draw only while a scenario does, as Blizzard's do.
function WidgetBlock:RenderBelowCriteria(container, cfg, top)
    if widgetsOff(cfg) then
        release(self.belowTop)
        release(self.belowBottom)
        return 0
    end
    local W = ns:GetModule("Widgets")
    local topID, bottomID
    if W then topID, bottomID = W:BelowCriteriaSetIDs() end
    local y = (top or 0) + ROW_GAP
    local h = draw(self.belowTop, container, cfg, y, topID)
    h = h + draw(self.belowBottom, container, cfg, y + h, bottomID)
    return h > 0 and h + ROW_GAP or 0
end

function WidgetBlock:ClearScenario()
    release(self.scenario)
    release(self.belowTop)
    release(self.belowBottom)
    -- These two ids never change, so only this keeps the status line off a finished scenario's read
    local W = ns:GetModule("Widgets")
    if W and W.Forget then
        local topID, bottomID = W:BelowCriteriaSetIDs()
        W:Forget(topID)
        W:Forget(bottomID)
    end
end
