local _, ns = ...

local MythicPlus = ns:RegisterModule("MythicPlus", {})
local Util       = ns.Util

-- Blizzard's own key block, read off Blizzard_ScenarioObjectiveTracker.xml and its SetUpAffixes
-- on 12.1.0, so a key looks here the way it does in the default tracker.
local BLOCK_W, BLOCK_H     = 251, 87
local LEVEL_X, LEVEL_Y     = 28, -18
local TIME_GAP             = 8
local MARK_W, MARK_H       = 19, 20
local MARK_GAP             = 4
local AFFIX_SIZE           = 22
local AFFIX_ICON           = 20
local AFFIX_GAP            = 4
local AFFIX_RIGHT, AFFIX_Y = 28, -18
local DEATH_X, DEATH_Y     = -47, 43
local DEATH_W, DEATH_H     = 20, 16
local BAR_W, BAR_H, BAR_Y  = 207, 13, 10
local BAR_BG_Y             = 13
-- Not Blizzard's: the +3 and +2 line under the block, which the default tracker does not draw
local CHEST_GAP, CHEST_SPLIT, CHEST_MIN_H = 2, 8, 14
local TICK = 0.1

local ART      = "challengemode-timer"
local BAR_BACK = "ChallengeMode-TimerBG-Back"
local BAR_BG   = "ChallengeMode-TimerBG"
local BAR_FILL = "ChallengeMode-TimerFill"
local RING     = "ChallengeMode-AffixRing-Sm"
local CHEST    = "ChallengeMode-icon-chest"
local REDLINE  = "ChallengeMode-icon-redline"
local GRAVE    = "poi-graveyard-neutral"

local WHITE = { 1, 1, 1 }
local RED   = { 1, 0.1, 0.1 }
local MISSED = { 0.5, 0.5, 0.5 }
-- Drawn when the fill atlas has not streamed in, so the bar still reads
local FILL_FALLBACK = { 0.95, 0.75, 0.2 }

-- Blizzard's SecondsToClock shape: 05:07. Time left never reaches an hour, so the hours form
-- is only a guard.
local function clock(s)
    s = math.max(0, math.floor(s or 0))
    local h, m = math.floor(s / 3600), math.floor(s / 60) % 60
    if h > 0 then return ("%d:%02d:%02d"):format(h, m, s % 60) end
    return ("%02d:%02d"):format(m, s % 60)
end

-- Blizzard's own strings, already translated for every client. A missing one drops its tooltip
-- line, or the whole tooltip when it is the title, and the level falls back to +%d.
local function gs(name)
    local v = _G[name]
    return type(v) == "string" and v or nil
end

local function clickThrough()
    local Tracker = ns:GetModule("Tracker")
    return (Tracker and Tracker.IsClickThrough and Tracker:IsClickThrough()) and true or false
end

local function showTip(owner, anchor, title, ...)
    if clickThrough() or not title then return end
    local tip = Util.Tooltip()
    tip:SetOwner(owner, anchor)
    tip:SetText(title, 1, 1, 1, 1, true)
    for i = 1, select("#", ...) do
        local line = select(i, ...)
        if line then tip:AddLine(line, nil, nil, nil, true) end
    end
    tip:Show()
end

local function hideTip()
    Util.Tooltip():Hide()
end

local function fontObject(name, fallback)
    return _G[name] and name or fallback
end

-- Blizzard's chest icon with a red line over it. The depleted mark always shows the line, the
-- time's-up mark only when the run gets no loot.
local function buildMark(parent)
    local m = CreateFrame("Frame", nil, parent)
    m:SetSize(MARK_W, MARK_H)
    m.Chest = m:CreateTexture(nil, "ARTWORK")
    m.Chest:SetPoint("CENTER")
    Util.SafeSetAtlas(m.Chest, CHEST, true)
    m.Line = m:CreateTexture(nil, "ARTWORK", nil, 1)
    m.Line:SetPoint("CENTER")
    Util.SafeSetAtlas(m.Line, REDLINE, true)
    m:EnableMouse(true)
    m:SetScript("OnLeave", hideTip)
    m:Hide()
    return m
end

local function affixEnter(a)
    showTip(a, "ANCHOR_RIGHT", a._name, a._description)
end

local function buildAffix(parent)
    local a = CreateFrame("Frame", nil, parent)
    a:SetSize(AFFIX_SIZE, AFFIX_SIZE)
    a.Portrait = a:CreateTexture(nil, "ARTWORK")
    a.Portrait:SetSize(AFFIX_ICON, AFFIX_ICON)
    a.Portrait:SetPoint("CENTER")
    a.Border = a:CreateTexture(nil, "OVERLAY")
    a.Border:SetAllPoints()
    Util.SafeSetAtlas(a.Border, RING, false)
    a:EnableMouse(true)
    a:SetScript("OnEnter", affixEnter)
    a:SetScript("OnLeave", hideTip)
    return a
end

local function onUpdate(f, elapsed)
    f._clock = (f._clock or 0) + elapsed
    if f._clock < TICK then return end
    f._clock = 0
    MythicPlus:_Tick()
end

function MythicPlus:Build(container)
    if self.frame then
        if self.frame:GetParent() ~= container then self.frame:SetParent(container) end
        return
    end
    local f = CreateFrame("Frame", nil, container)
    f:SetSize(BLOCK_W, BLOCK_H)
    f:Hide()

    f.BarBack = f:CreateTexture(nil, "BACKGROUND")
    f.BarBack:SetPoint("BOTTOM", f, "BOTTOM", 0, BAR_BG_Y)
    Util.SafeSetAtlas(f.BarBack, BAR_BACK, true)
    f.BarBG = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.BarBG:SetPoint("BOTTOM", f, "BOTTOM", 0, BAR_BG_Y)
    Util.SafeSetAtlas(f.BarBG, BAR_BG, true)

    -- A texture cropped by hand rather than a StatusBar: the fill is an atlas, and an atlas on a
    -- status bar from Lua is a call this addon has never measured.
    f.Fill = f:CreateTexture(nil, "BORDER")
    f.Fill:SetPoint("BOTTOMLEFT", f, "BOTTOM", -BAR_W / 2, BAR_Y)
    f.Fill:SetHeight(BAR_H)

    -- Where +3 and +2 run out along the draining bar
    f.MarkThree = f:CreateTexture(nil, "ARTWORK")
    f.MarkTwo   = f:CreateTexture(nil, "ARTWORK")
    for _, t in ipairs({ f.MarkThree, f.MarkTwo }) do
        t:SetColorTexture(1, 1, 1, 0.7)
        t:SetSize(1, BAR_H)
    end

    f.Art = f:CreateTexture(nil, "OVERLAY")
    f.Art:SetAllPoints()
    Util.SafeSetAtlas(f.Art, ART, false)

    f.Level = f:CreateFontString(nil, "OVERLAY", fontObject("GameFontNormalMed2", "GameFontNormal"))
    f.Level:SetJustifyH("LEFT")
    f.Level:SetPoint("TOPLEFT", f, "TOPLEFT", LEVEL_X, LEVEL_Y)

    f.TimeLeft = f:CreateFontString(nil, "OVERLAY",
        fontObject("GameFontHighlightHuge", "GameFontHighlightLarge"))
    f.TimeLeft:SetJustifyH("LEFT")
    f.TimeLeft:SetPoint("TOPLEFT", f.Level, "BOTTOMLEFT", 0, -TIME_GAP)

    f.Depleted = buildMark(f)
    f.Depleted:SetPoint("LEFT", f.Level, "RIGHT", MARK_GAP, 0)
    f.Depleted:SetScript("OnEnter", function(m)
        showTip(m, "ANCHOR_RIGHT", gs("CHALLENGE_MODE_DEPLETED_KEYSTONE"),
            gs("CHALLENGE_MODE_KEYSTONE_DEPLETED_AT_START"))
    end)

    f.TimesUp = buildMark(f)
    f.TimesUp:SetPoint("LEFT", f.TimeLeft, "RIGHT", MARK_GAP, 0)
    f.TimesUp:SetScript("OnEnter", function(m)
        local line
        if not self._depleted then
            line = gs("CHALLENGE_MODE_TIMES_UP_LOOT")
        elseif UnitIsGroupLeader and UnitIsGroupLeader("player") then
            line = gs("CHALLENGE_MODE_TIMES_UP_NO_LOOT_LEADER")
        else
            line = gs("CHALLENGE_MODE_TIMES_UP_NO_LOOT")
        end
        showTip(m, "ANCHOR_RIGHT", gs("CHALLENGE_MODE_TIMES_UP"), line)
    end)

    f.Death = CreateFrame("Frame", nil, f)
    f.Death:SetSize(DEATH_W, DEATH_H)
    f.Death:SetPoint("TOPLEFT", f, "BOTTOMRIGHT", DEATH_X, DEATH_Y)
    f.Death.Icon = f.Death:CreateTexture(nil, "ARTWORK")
    f.Death.Icon:SetPoint("LEFT")
    Util.SafeSetAtlas(f.Death.Icon, GRAVE, true)
    f.Death.Count = f.Death:CreateFontString(nil, "OVERLAY",
        fontObject("GameFontHighlightSmall2", "GameFontHighlightSmall"))
    f.Death.Count:SetPoint("LEFT", f.Death.Icon, "RIGHT", 1, 0)
    f.Death:EnableMouse(true)
    f.Death:SetScript("OnEnter", function(d)
        local title, desc = gs("CHALLENGE_MODE_DEATH_COUNT_TITLE"),
                            gs("CHALLENGE_MODE_DEATH_COUNT_DESCRIPTION")
        showTip(d, "ANCHOR_LEFT", title and title:format(self._deaths or 0),
            desc and desc:format(clock(self._timeLost)))
    end)
    f.Death:SetScript("OnLeave", hideTip)
    f.Death:Hide()

    -- Anchored below the block from its center, each half growing away from the middle, so a
    -- digit changing width moves only the outer edge
    f.Plus3 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.Plus3:SetJustifyH("RIGHT")
    f.Plus3:SetPoint("TOPRIGHT", f, "BOTTOM", -CHEST_SPLIT, -CHEST_GAP)
    f.Plus2 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.Plus2:SetJustifyH("LEFT")
    f.Plus2:SetPoint("TOPLEFT", f, "BOTTOM", CHEST_SPLIT, -CHEST_GAP)

    self.affixes = {}
    self.frame = f
end

local function criteriaFont(Media, fs)
    Media:ApplyScenarioCriteriaFont(fs)
    Media:ApplyTextShadow(fs)
end

-- Inside the block Blizzard's own font sizes stay, since its art does not grow with Banner
-- Text Size, and only the banner's shadow reaches them. The +3 and +2 line under it takes the
-- criteria font, like the lines it sits with.
function MythicPlus:_ApplyFonts()
    local f = self.frame
    local Media = ns:GetModule("Media")
    Media:ApplyScenarioShadow(f.Level)
    Media:ApplyScenarioShadow(f.TimeLeft)
    Media:ApplyScenarioShadow(f.Death.Count)
    criteriaFont(Media, f.Plus3)
    criteriaFont(Media, f.Plus2)
end

-- Cropped from the atlas's own coordinates so the fill drains the way a status bar does rather
-- than squashing the art. Asked again on every set until the atlas has streamed in.
function MythicPlus:_SetFill(frac)
    local fill = self.frame.Fill
    frac = math.max(0, math.min(1, frac or 0))
    if frac <= 0 then
        fill:Hide()
        return
    end
    if not self._fillInfo and ns.Has.Atlas then
        local info = C_Texture.GetAtlasInfo(BAR_FILL)
        if info and (info.file or info.filename) then
            self._fillInfo = info
            fill:SetTexture(info.file or info.filename)
            fill:SetVertexColor(1, 1, 1)
        end
    end
    local info = self._fillInfo
    if info then
        local l, r = info.leftTexCoord or 0, info.rightTexCoord or 1
        fill:SetTexCoord(l, l + (r - l) * frac, info.topTexCoord or 0, info.bottomTexCoord or 1)
    elseif not self._fillFallback then
        self._fillFallback = true
        fill:SetColorTexture(FILL_FALLBACK[1], FILL_FALLBACK[2], FILL_FALLBACK[3])
    end
    fill:SetWidth(BAR_W * frac)
    fill:Show()
end

local function chest(fs, label, remain)
    local c = remain > 0 and WHITE or MISSED
    fs:SetText(("%s %s"):format(label, clock(remain)))
    fs:SetTextColor(c[1], c[2], c[3])
end

function MythicPlus:_Tick(force)
    local f = self.frame
    if not (f and self._limit) then return end
    local elapsed = math.floor((self._elapsed or 0) + (GetTime() - (self._at or GetTime())))
    if not force and elapsed == self._shownAt then return end
    self._shownAt = elapsed

    local limit = self._limit
    local left = math.max(0, limit - elapsed)
    f.TimeLeft:SetText(clock(left))
    if left == 0 then
        f.TimeLeft:SetTextColor(RED[1], RED[2], RED[3])
        f.Depleted:Hide()
        f.TimesUp:Show()
        f.TimesUp.Line:SetShown(self._depleted and true or false)
    else
        f.TimeLeft:SetTextColor(WHITE[1], WHITE[2], WHITE[3])
        f.TimesUp:Hide()
        f.Depleted:SetShown(self._depleted and true or false)
    end
    self:_SetFill(left / limit)

    chest(f.Plus3, "+3", (self._three or 0) - elapsed)
    chest(f.Plus2, "+2", (self._two or 0) - elapsed)
end

-- Right-aligned 28px in from the block's top right corner, first affix leftmost, as Blizzard
-- places them
function MythicPlus:_Affixes(key)
    local f, pool = self.frame, self.affixes
    local n = key.affixN or 0
    local left = AFFIX_RIGHT + AFFIX_GAP * (n - 1) + AFFIX_SIZE * n
    for i = 1, math.max(n, #pool) do
        local a = pool[i]
        if i <= n then
            if not a then
                a = buildAffix(f)
                pool[i] = a
            end
            local info = key.affixes[i]
            a._name, a._description = info.name, info.description
            a.Portrait:SetTexture(info.icon)
            a:ClearAllPoints()
            if i == 1 then
                a:SetPoint("TOPLEFT", f, "TOPRIGHT", -left, AFFIX_Y)
            else
                a:SetPoint("LEFT", pool[i - 1], "RIGHT", AFFIX_GAP, 0)
            end
            a:Show()
        elseif a then
            a:Hide()
            a._name, a._description = nil, nil
        end
    end
    self._affixN = n
end

-- top is measured from the container's top, under the scenario's sub-header. Answers the
-- height the block takes, the +3 and +2 line under it included.
function MythicPlus:Render(container, cfg, key, top)
    self:Build(container)
    local f = self.frame

    -- Copied rather than held: Keystone refills its table on the next read
    self._elapsed, self._at = key.elapsed or 0, key.elapsedAt or GetTime()
    self._limit = key.timeLimit
    self._two, self._three = key.plusTwo, key.plusThree
    self._depleted = key.depleted and true or false
    self._deaths, self._timeLost = key.deaths or 0, key.timeLost or 0

    local align = (cfg and cfg.scenarioTextAlign) or "CENTER"
    local point = (align == "LEFT" and "TOPLEFT") or (align == "RIGHT" and "TOPRIGHT") or "TOP"
    f:ClearAllPoints()
    f:SetPoint(point, container, point, 0, -(top or 0))

    local fmt = gs("CHALLENGE_MODE_POWER_LEVEL") or "+%d"
    f.Level:SetText(key.level and fmt:format(key.level) or "")
    self:_Affixes(key)

    -- Blizzard shows the count only once a death has cost time
    if self._deaths > 0 and self._timeLost > 0 then
        f.Death.Count:SetText(tostring(self._deaths))
        f.Death:Show()
    else
        f.Death:Hide()
    end

    local limit = self._limit or 0
    f.MarkThree:SetShown(limit > 0)
    f.MarkTwo:SetShown(limit > 0)
    if limit > 0 then
        local x0 = (BLOCK_W - BAR_W) / 2
        f.MarkThree:ClearAllPoints()
        f.MarkThree:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT",
            x0 + BAR_W * (1 - (self._three or 0) / limit), BAR_Y)
        f.MarkTwo:ClearAllPoints()
        f.MarkTwo:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT",
            x0 + BAR_W * (1 - (self._two or 0) / limit), BAR_Y)
    end

    self:_ApplyFonts()
    self:_Tick(true)
    f:SetScript("OnUpdate", onUpdate)
    f:Show()

    local chestH = math.max(CHEST_MIN_H, f.Plus3:GetStringHeight() or 0)
    self._height = BLOCK_H + CHEST_GAP + chestH
    return self._height
end

-- why is what the status line says instead of the block, nil for no key at all
function MythicPlus:Clear(why)
    self._why = why
    self._limit, self._height = nil, nil
    local f = self.frame
    if not f then return end
    f:SetScript("OnUpdate", nil)
    f:Hide()
    for _, a in ipairs(self.affixes) do
        a:Hide()
        a._name, a._description = nil, nil
    end
end

function MythicPlus:DebugLine()
    local f = self.frame
    if not (f and f:IsShown() and self._limit) then
        return ("mythic+ block: not drawn%s"):format(self._why and (", " .. self._why) or "")
    end
    return ("mythic+ block: drawn %dpx, %s left, %s, %s, %d affix(es), deaths %s"):format(
        self._height or 0, tostring(f.TimeLeft:GetText()), tostring(f.Plus3:GetText()),
        tostring(f.Plus2:GetText()), self._affixN or 0,
        f.Death:IsShown() and tostring(self._deaths) or "hidden")
end
