local _, ns = ...

local Options = ns:GetModule("Options")
local L       = ns.L

local GOLD  = "|cffEBB706"
local MUTED = "|cffb3b3b3"
local WHITE = "|cffe6e6e6"
local CLOSE = "|r"

local BRAND_RED = { 0.635, 0.000, 0.039 }
local LINK      = { 0.92, 0.72, 0.02 }

local CURSEFORGE_URL = "https://www.curseforge.com/wow/addons/eq-objective-tracker"
local GITHUB_URL     = "https://github.com/wheelbarrel00/EQObjectiveTracker"
local BUG_URL        = "https://github.com/wheelbarrel00/EQObjectiveTracker/issues"

-- Slash tokens are never translated. Only the description beside each one is.
-- importeq is the recovery command: nothing else re-runs the EQ import for someone who
-- installed this addon first.
local COMMANDS = {
    { "/eqot",          L["Open this window"] },
    { "/eqot lock",     L["Lock moving and resizing"] },
    { "/eqot unlock",   L["Unlock moving and resizing"] },
    { "/eqot reset",    L["Restore the default position and size"] },
    { "/eqot toggle",   L["Show or hide the tracker"] },
    { "/eqot importeq", L["Import your Everything Quests settings"] },
    { "/eqot status",   L["Print provider status to chat"] },
    { "/eqot debug",    L["Toggle entry validation warnings"] },
}

-- One key per credit rather than a shared prefix plus a tail, so the name is a %s a
-- translator can move. Korean puts it elsewhere in the sentence and a concatenation cannot.
-- Order follows EQ's: the contributor first, then the translators.
local THANKS = {
    { name = "DrahgunFyre", line = L["Special thanks to %s for the many features, fixes, and reports that keep shaping EQ Objective Tracker."] },
    { name = "Zox",         line = L["Special thanks to %s for the many hours spent translating EQ Objective Tracker into French."] },
    { name = "Malevi4",     line = L["Special thanks to %s for the many hours spent translating EQ Objective Tracker into Russian."] },
    { name = "labrie75",    line = L["Special thanks to %s for the many hours spent translating EQ Objective Tracker into Korean."] },
    { name = "Keriaovo",    line = L["Special thanks to %s for the many hours spent translating EQ Objective Tracker into Simplified Chinese."] },
    { name = "BNS333",      line = L["Special thanks to %s for the many hours spent translating EQ Objective Tracker into Traditional Chinese."] },
    { name = "Stonetwist",  line = L["Special thanks to %s for the many hours spent translating EQ Objective Tracker into German."] },
}

-- A tab-local cursor, the way EQ's own About tab does it. This is the one tab that wants
-- stacking - its provider run is as long as the flavor's TOC made it, and its changelog is
-- as long as the release history - and a cursor that lives here costs less than a layout
-- engine shared by three tabs that never use it.
local LEFT, WRAP = 8, 900

Options:RegisterTab({
    id    = "about",
    title = L["About"],
    order = 90,
    build = function(self, content)
        local y = -8

        -- size is passed only by the page title. Without it the addon name renders at the
        -- same weight as Commands and Changelog and reads as the first of five equal
        -- sections rather than as the title. Set before measuring, or y advances by the
        -- old height. EQ builds its title at this exact size and outline.
        local function title(text, size)
            local fs = self:CreateHeading(content, text)
            if size then fs:SetFont(fs:GetFont(), size, "OUTLINE") end
            fs:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT, y)
            y = y - math.max(18, fs:GetStringHeight() or 18) - 10
            return fs
        end

        -- A rule under each section heading, as EQ's About tab has. Everywhere else in the
        -- panel a heading tops a short column. Here the sections scroll past one another,
        -- and the changelog alone is longer than every other tab put together.
        local function header(text)
            local fs = title(text)
            local rule = content:CreateTexture(nil, "ARTWORK")
            rule:SetHeight(1)
            rule:SetColorTexture(0.30, 0.30, 0.30, 0.8)
            rule:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -3)
            -- WRAP, not WRAP - LEFT. A label is anchored at LEFT + indent with width
            -- WRAP - indent, so the text column ends at LEFT + WRAP and EQ's expression
            -- leaves a full-width paragraph overhanging its own rule.
            rule:SetWidth(WRAP)
            return fs
        end

        -- Width and wrap set before the text, so GetStringHeight reports the wrapped
        -- height. The old shared CreateLabel set neither and overflowed the content frame.
        local function label(text, indent, size, r, g, b)
            local fs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT + (indent or 0), y)
            if size then fs:SetFont(fs:GetFont(), size) end
            fs:SetWidth(WRAP - (indent or 0))
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(true)
            fs:SetTextColor(r or 0.8, g or 0.8, b or 0.8)
            fs:SetText(text)
            y = y - math.max(size or 12, fs:GetStringHeight() or 12) - 4
            return fs
        end

        local function gap(px) y = y - (px or 8) end

        local function makeLink(text, onClick)
            local b = CreateFrame("Button", nil, content)
            b:SetHeight(16)
            b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            b.text:SetPoint("LEFT", b, "LEFT", 0, 0)
            b.text:SetText(text)
            b.text:SetTextColor(unpack(LINK))
            -- `<= 0` as well as nil: 0 is truthy in Lua, so an unmeasured string would give
            -- a 2px button that looks like a link and cannot be clicked.
            local w = b.text:GetStringWidth()
            if not w or w <= 0 then w = 90 end
            b:SetWidth(w + 2)
            b:SetScript("OnClick", onClick)
            b:SetScript("OnEnter", function(s) s.text:SetTextColor(1, 1, 1) end)
            b:SetScript("OnLeave", function(s) s.text:SetTextColor(unpack(LINK)) end)
            return b
        end

        local function linkRow(links)
            local prev
            for i, lk in ipairs(links) do
                local b = makeLink(lk.label, lk.onClick)
                if i == 1 then
                    b:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT, y)
                else
                    local sep = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    sep:SetText(MUTED .. "  |  " .. CLOSE)
                    sep:SetPoint("LEFT", prev, "RIGHT", 2, 0)
                    b:SetPoint("LEFT", sep, "RIGHT", 2, 0)
                end
                prev = b
            end
            y = y - 24
        end

        title("EQ Objective Tracker", 22)
        label(L["Version %s"]:format(ns.VERSION) .. " " .. L["by Wheelbarrel00"])
        label(L["A standalone replacement for the default objective tracker. It does not require Everything Quests, and never will."],
            0, nil, 0.6, 0.6, 0.6)
        gap(6)

        linkRow({
            { label = L["Join our Discord"], onClick = function() ns:ShowDiscord() end },
            { label = L["CurseForge"],       onClick = function() ns:ShowURL(CURSEFORGE_URL) end },
            { label = L["GitHub"],           onClick = function() ns:ShowURL(GITHUB_URL) end },
            { label = L["Report a Bug"],     onClick = function() ns:ShowURL(BUG_URL) end },
        })
        gap(8)

        header(L["Commands"])
        local cmdRows, widest = {}, 0
        for i = 1, #COMMANDS do
            local slash = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            slash:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT, y)
            slash:SetText(GOLD .. COMMANDS[i][1] .. CLOSE)
            local w = slash:GetStringWidth() or 0
            if w > widest then widest = w end
            local desc = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            desc:SetText(WHITE .. COMMANDS[i][2] .. CLOSE)
            cmdRows[i] = { slash, desc }
            y = y - 16
        end
        -- Second column past the widest token, the way AlignPickerColumn lines the pickers
        -- up. EQ hardcodes 120, which silently overlaps the first command longer than that.
        for i = 1, #cmdRows do
            cmdRows[i][2]:SetPoint("TOPLEFT", cmdRows[i][1], "TOPLEFT", widest + 12, 0)
        end
        gap(10)

        header(L["Content providers"])
        label(L["Providers are gated at load time by which TOC file your game flavor used. A provider that is not listed was never loaded."],
            0, nil, 0.6, 0.6, 0.6)

        content._providerLines = {}
        local Registry = ns:GetModule("Registry")
        for _, p in ipairs(Registry:Active()) do
            content._providerLines[p.id] = label(p.id)
        end
        gap(10)

        header(L["Thanks"])
        for _, t in ipairs(THANKS) do
            -- WHITE is re-opened after the name because |r resets to the font's own color
            -- rather than popping back to the enclosing escape.
            label(WHITE .. t.line:format(GOLD .. t.name .. CLOSE .. WHITE) .. CLOSE,
                0, nil, 1, 1, 1)
        end
        gap(10)

        header(L["Changelog"])
        -- A version-less entry would throw on the concatenation below, and a throw here
        -- leaves Frame.lua's SelectTab without _built and with every tab hidden, so the
        -- whole window goes blank and re-throws on each click. Cheaper to skip the row.
        for _, entry in ipairs(ns.Changelog or {}) do
            if entry.version then
                local vh = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                vh:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT, y)
                vh:SetFont(vh:GetFont(), 13, "OUTLINE")
                vh:SetText(GOLD .. "v" .. entry.version .. CLOSE
                    .. MUTED .. "    " .. (entry.date or "") .. CLOSE)
                y = y - 18
                if entry.summary then label(MUTED .. entry.summary .. CLOSE, 10, 11) end
                for _, sec in ipairs(entry.sections or {}) do
                    local sh = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    sh:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT + 10, y)
                    sh:SetFont(sh:GetFont(), 11, "OUTLINE")
                    sh:SetTextColor(unpack(BRAND_RED))
                    sh:SetText(sec.head or "")
                    y = y - 16
                    for _, item in ipairs(sec.items or {}) do
                        label(WHITE .. "- " .. item .. CLOSE, 18, 11, 1, 1, 1)
                    end
                    gap(2)
                end
                gap(8)
            end
        end

        local older = makeLink(L["Older versions are on CurseForge"],
            function() ns:ShowURL(CURSEFORGE_URL) end)
        older:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT, y)
        y = y - 24
    end,

    -- Live, because "is the provider empty or is the section not rendering" is the
    -- first question asked whenever something does not appear. Left untranslated with
    -- the rest of the diagnostic output - the counts are for bug reports, not reading.
    refresh = function(_, content)
        local Registry = ns:GetModule("Registry")
        for _, p in ipairs(Registry:Active()) do
            local fs = content._providerLines and content._providerLines[p.id]
            if fs then
                if not p._available then
                    fs:SetText(("|cff888888%-14s unavailable on this client|r"):format(p.id))
                else
                    local ok, entries = pcall(p.GetEntries, p)
                    local n = (ok and entries) and #entries or -1
                    fs:SetText(("|cff44ff44%-14s|r %d entries   |cff888888groups: %s|r")
                        :format(p.id, math.max(0, n), table.concat(p.groups, ", ")))
                end
            end
        end
    end,
})
