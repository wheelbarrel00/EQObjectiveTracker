local _, ns = ...

local WhatsNew = ns:RegisterModule("WhatsNew", {})
local L        = ns.L

local WIDTH, HEIGHT = 600, 560
local PAD_TOP, PAD_SIDE, PAD_BOTTOM = 20, 24, 24
local HEAD_GAP, SECTION_GAP, BLOCK_GAP = 6, 12, 20
local FOOTER_H, BAR_ROOM = 56, 10
-- Off center, so a What's New window Everything Quests opens in the same login cannot cover this one exactly
local OFFSET_X, OFFSET_Y = 40, -40
local DELAY = 3
-- The last version without this window. With no marker saved, every release after it counts as unread.
local BEFORE_FIRST = "2.14.0"
-- A bare literal, because the changelog's heads are English on every client
local FEATURES = "New Features"
local NAME = "EQ Objective Tracker"
local LINK = "addon:EQObjectiveTracker:whatsnew"

local function numbers(version)
    local out = {}
    for n in tostring(version or ""):gmatch("%d+") do out[#out + 1] = tonumber(n) end
    return out
end

local function newer(a, b)
    local x, y = numbers(a), numbers(b)
    for i = 1, math.max(#x, #y) do
        local p, q = x[i] or 0, y[i] or 0
        if p ~= q then return p > q end
    end
    return false
end

local function global()
    local DB = ns:GetModule("DB")
    return DB and DB:Global()
end

local function mode()
    local g = global()
    return (g and g.whatsNewMode) or "popup"
end

local function latest()
    local c = ns.Changelog
    return c and c[1] and c[1].version
end

local function since(marker)
    local out = {}
    for _, release in ipairs(ns.Changelog or {}) do
        if release.version and newer(release.version, marker) then out[#out + 1] = release end
    end
    return out
end

-- A release either notice covered counts as told, so a switch between popup and chat never repeats one
local function toldUpTo()
    local g = global() or {}
    local seen, said = g.whatsNewSeen, g.whatsNewAnnounced
    if seen and said then return newer(said, seen) and said or seen end
    return seen or said or BEFORE_FIRST
end

-- What the window lists: everything since the last one READ, so a chat link clicked later still shows it all
local function toRead()
    local g = global() or {}
    local list = since(g.whatsNewSeen or BEFORE_FIRST)
    if #list == 0 and ns.Changelog and ns.Changelog[1] then list = { ns.Changelog[1] } end
    return list
end

local function hasFeatures(list)
    for _, release in ipairs(list) do
        for _, sec in ipairs(release.sections or {}) do
            if sec.head == FEATURES then return true end
        end
    end
    return false
end

local function colorCode(ui, name)
    local r, g, b = ui:Color(name)
    return ("|cff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
                                       math.floor(b * 255 + 0.5))
end

local function openOptions()
    local Options = ns:GetModule("Options")
    if not Options then return end
    Options:Build()
    if Options.frame and Options.frame:IsShown() then
        -- Another addon's window may have come up over it since it opened
        Options.frame:Raise()
    else
        Options:Toggle()
    end
    return Options
end

-- A text block measures all of its lines again for every line added, so each release gets its own
local function fill(ui, content, releases, quietFirst, goToSetting)
    local pieces = {}
    local function place(frame)
        local prev = pieces[#pieces]
        if prev then
            frame:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -BLOCK_GAP)
            frame:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -BLOCK_GAP)
        else
            frame:SetPoint("TOPLEFT", content, "TOPLEFT", PAD_SIDE, -PAD_TOP)
            frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD_SIDE, -PAD_TOP)
        end
        pieces[#pieces + 1] = frame
        return frame
    end
    local bright, muted = colorCode(ui, "text"), colorCode(ui, "muted")
    local function lit(s) return bright .. s .. "|r" end

    local function quiet()
        local b = place(ui:CreateTextBlock(content))
        b:AddLine(L["Prefer quiet updates?"], "title")
        b:AddLine(L["Switch these notices to a clickable chat link, or turn them off, under %1$s > %2$s > %3$s, or tick the %4$s box below."]
            :format(lit("/eqot"), lit(L["General"]), lit(L["After an update"]), lit(L["Don't show these again"])),
            "label", { gap = HEAD_GAP })
        local row = CreateFrame("Frame", nil, content)
        row:SetHeight(ui:Spacing("buttonHeight"))
        place(row)
        local go = ui:CreateButton(row, L["Go to this setting"], nil, goToSetting)
        go:SetPoint("LEFT", row, "LEFT")
        pieces.go = go
    end

    if quietFirst then quiet() end
    local several = #releases > 1
    for _, release in ipairs(releases) do
        local b = place(ui:CreateTextBlock(content))
        if several then
            b:AddLine(release.version .. "   " .. muted .. (release.date or "") .. "|r", "title")
        end
        if release.summary then b:AddLine(release.summary, "hint", { gap = several and HEAD_GAP or nil }) end
        for i, sec in ipairs(release.sections or {}) do
            local first = (i == 1) and not several and not release.summary
            b:AddLine(sec.head or "", "groupLabel", { gap = (not first) and SECTION_GAP or nil })
            for _, item in ipairs(sec.items or {}) do
                b:AddLine(item, "label", { bullet = "-", gap = HEAD_GAP })
            end
        end
    end
    if not quietFirst then quiet() end

    local closing = place(ui:CreateTextBlock(content))
    closing:AddLine(L["Thanks for using %s!"]:format(NAME), "title")
    closing:AddLine(L["Found a bug or have an idea? Use the Discord button at the top of this window."], "label",
        { gap = HEAD_GAP })
    closing:AddLine(L["Type %s anytime to see this again."]:format(lit("/eqot whatsnew")), "hint", { gap = HEAD_GAP })
    return pieces
end

-- Built once a session, because a text block cannot be emptied, so a reopen shows the same notes
function WhatsNew:Build(releases)
    if self.frame then return self.frame end
    local Options = ns:GetModule("Options")
    local ui = Options.ui
    local g = global()
    local quietFirst = not (g and g.whatsNewIntroShown)

    local f = ui:CreateWindow({ name = "EQOTWhatsNewFrame", title = L["What's New"], width = WIDTH, height = HEIGHT })
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", OFFSET_X, OFFSET_Y)
    f:SetSection(NAME .. " " .. (latest() or ""))
    f:AddHeaderButton("icon-discord", L["Join our Discord"], L["Click to copy the invite link."],
        function() ns:ShowDiscord() end)
    local area = ui:CreateScrollArea(f.body, {})
    area:SetPoint("TOPLEFT", f.body, "TOPLEFT")
    area:SetPoint("BOTTOMRIGHT", f.body, "BOTTOMRIGHT", 0, FOOTER_H)
    -- An ancestor hide (Alt-Z, a cinematic) fires OnHide with the window still shown, and is not a close,
    -- so only a real close sends the notes back to their top for the next open
    f:HookScript("OnHide", function(win)
        if win:IsShown() then return end
        area:ScrollTo(0, 0)
        local gl = global()
        if not gl then return end
        gl.whatsNewSeen = latest()
        gl.whatsNewIntroShown = true
    end)
    local function goToSetting()
        f:Hide()
        local O = openOptions()
        if O then O:ShowWhatsNewSetting() end
    end
    local parts = fill(ui, area.content, releases, quietFirst, goToSetting)
    f.parts = parts

    local footer = CreateFrame("Frame", nil, f.body)
    footer:SetPoint("BOTTOMLEFT")
    footer:SetPoint("BOTTOMRIGHT")
    footer:SetHeight(FOOTER_H)
    footer._controls = {}
    ui:Paint(footer, "chrome", "divider", "T")

    f.dontShow = ui:CreateCheckbox(footer, L["Don't show these again"],
        function() return mode() == "none" end,
        function(on)
            local gl = global()
            if not gl then return end
            -- Unticking puts back the mode in use before, kept across sessions, so a chat link player is not moved to the popup
            if on then
                if mode() ~= "none" then gl.whatsNewModeBeforeOff = mode() end
                gl.whatsNewMode = "none"
            else
                local before = gl.whatsNewModeBeforeOff
                gl.whatsNewMode = (before and before ~= "none") and before or "popup"
            end
            Options:RefreshIfShown("general")
        end,
        L["Stops What's New notices entirely. You can turn them back on under /eqot > General > After an update."])
    f.dontShow:SetPoint("LEFT", footer, "LEFT", PAD_SIDE, 0)

    f.gotIt = ui:CreateButton(footer, L["Got it"], nil, function() f:Hide() end, nil, "primary")
    f.gotIt:SetPoint("RIGHT", footer, "RIGHT", -PAD_SIDE, 0)
    f.openOptions = ui:CreateButton(footer, L["Open Options"], nil, function()
        f:Hide()
        openOptions()
    end)
    f.openOptions:SetPoint("RIGHT", f.gotIt, "LEFT", -ui:Spacing("buttonGap"), 0)

    -- Text measured while hidden can be short of the text as drawn, so it is measured again once shown
    local function layout()
        local w = area.scroll:GetWidth() or 0
        if w <= 0 then w = WIDTH - BAR_ROOM end
        -- The width first, since a wrapped line reports its height only once it has one. Width alone, as a
        -- height of 1 would drop the scroll range and send a window shown again back to its top.
        area.content:SetWidth(w)
        local h = PAD_TOP + PAD_BOTTOM + BLOCK_GAP * (#parts - 1)
        for _, p in ipairs(parts) do
            h = h + (p.Measure and p:Measure() or p:GetHeight() or 0)
        end
        area:SetContentSize(w, h)
        f.gotIt:Fit()
        f.openOptions:Fit()
        if parts.go then parts.go:Fit() end
    end
    layout()
    f:HookScript("OnShow", function()
        f.dontShow:Refresh()
        C_Timer.After(0, layout)
    end)

    self.frame = f
    return f
end

function WhatsNew:Show(list)
    if not latest() then return end
    local Options = ns:GetModule("Options")
    if not (Options and Options.ui) then return end
    local f = self:Build(list or toRead())
    f:Show()
    f:Raise()
end

function WhatsNew:Refresh()
    if self.frame and self.frame:IsShown() then self.frame.dontShow:Refresh() end
end

local function announce()
    local link = "|H" .. LINK .. "|h|cffEBB706" .. L["[See what's new]"] .. "|r|h"
    print(L["%1$s updated to %2$s - %3$s"]:format("|cffEBB706" .. NAME .. "|r", latest(), link))
    local g = global()
    if g then g.whatsNewAnnounced = latest() end
end

function WhatsNew:OnEnable()
    local g, v = global(), latest()
    if not (g and v) then return end
    -- The game opens nothing for an addon link, so a click on this one opens the window here
    if type(hooksecurefunc) == "function" and type(_G.SetItemRef) == "function" then
        hooksecurefunc("SetItemRef", function(link)
            if link == LINK then WhatsNew:Show() end
        end)
    end
    -- A first install has nothing to catch up on, so every release so far counts as read
    local DB = ns:GetModule("DB")
    if DB and DB.freshInstall and not g.whatsNewSeen and not g.whatsNewAnnounced then
        g.whatsNewSeen, g.whatsNewAnnounced = v, v
        return
    end
    C_Timer.After(DELAY, function()
        local m = mode()
        -- A release with only fixes waits unmarked, so the next one with new features lists it too
        if m == "none" or not hasFeatures(since(toldUpTo())) then return end
        if m == "chat" then announce() else self:Show(toRead()) end
    end)
end

function WhatsNew:DebugLine()
    local g = global() or {}
    return ("what's new: mode %s, seen %s, announced %s, first window %s, %d untold, %s"):format(
        mode(), tostring(g.whatsNewSeen or "-"), tostring(g.whatsNewAnnounced or "-"),
        g.whatsNewIntroShown and "shown" or "not yet", #since(toldUpTo()),
        self.frame and "window built" or "no window this session")
end
