local _, ns = ...

local Options = ns:GetModule("Options")
local L       = ns.L

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

-- An escape opening one of the theme's colors, for the part of a line drawn in another one.
local function colorCode(ui, name)
    local r, g, b = ui:Color(name)
    return ("|cff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
                                       math.floor(b * 255 + 0.5))
end

Options:RegisterTab({
    id    = "about",
    title = L["About"],
    order = 90,
    build = function(self, content)
        local gap, listRow = self:Spacing("groupGap"), self:Spacing("listRowHeight")
        local above
        local function stack(card)
            if above then
                card:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -gap)
                card:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT", 0, -gap)
            else
                card:SetPoint("TOPLEFT")
                card:SetPoint("TOPRIGHT")
            end
            above = card
            return card
        end

        local intro = stack(self:CreateGroup(content, nil))
        local blurb = self:CreateTextBlock(content)
        blurb:AddLine(L["Version %s"]:format(ns.VERSION) .. " " .. L["by Wheelbarrel00"], "value")
        blurb:AddLine(L["A standalone replacement for the default objective tracker. It does not require Everything Quests, and never will."])
        intro:Add(blurb, { fitHeight = true })

        local links = CreateFrame("Frame", nil, content)
        links:SetHeight(self:Spacing("buttonHeight"))
        local prev
        for _, lk in ipairs({
            { label = L["Join our Discord"], onClick = function() ns:ShowDiscord() end },
            { label = L["CurseForge"],       onClick = function() ns:ShowURL(CURSEFORGE_URL) end },
            { label = L["GitHub"],           onClick = function() ns:ShowURL(GITHUB_URL) end },
            { label = L["Report a Bug"],     onClick = function() ns:ShowURL(BUG_URL) end },
        }) do
            local b = self:CreateButton(content, lk.label, nil, lk.onClick)
            if prev then
                b:SetPoint("LEFT", prev, "RIGHT", self:Spacing("buttonGap"), 0)
            else
                b:SetPoint("LEFT", links, "LEFT")
            end
            prev = b
        end
        intro:Add(links, { fill = true })

        local commands = stack(self:CreateGroup(content, L["Commands"]))
        for _, cmd in ipairs(COMMANDS) do
            local row = self:CreateTextRow(content, cmd[1], cmd[2])
            row.label:SetTextColor(self:Color("text"))
            commands:Add(row, { height = listRow })
        end

        local providers = stack(self:CreateGroup(content, L["Content providers"]))
        local note = self:CreateTextBlock(content)
        note:AddLine(L["Providers are gated at load time by which TOC file your game flavor used. A provider that is not listed was never loaded."], "hint")
        providers:Add(note, { fitHeight = true })
        content._providerRows = {}
        for _, p in ipairs(ns:GetModule("Registry"):Active()) do
            local row = self:CreateTextRow(content, p.id, "")
            providers:Add(row, { height = listRow })
            content._providerRows[p.id] = row
        end

        local thanks = stack(self:CreateGroup(content, L["Thanks"]))
        local bright = colorCode(self, "text")
        for _, t in ipairs(THANKS) do
            local credit = self:CreateTextBlock(content)
            -- |r falls back to the line's own color, so only the name needs an escape.
            credit:AddLine(t.line:format(bright .. t.name .. "|r"))
            thanks:Add(credit, { fitHeight = true })
        end

        local changelog = stack(self:CreateGroup(content, L["Changelog"]))
        local muted = colorCode(self, "muted")
        -- A version-less entry would throw on the concatenation below, and a throw here
        -- leaves the library's SelectTab without _built and with every tab hidden, so the
        -- whole window goes blank and re-throws on each click. Cheaper to skip the row.
        for _, entry in ipairs(ns.Changelog or {}) do
            if entry.version then
                local block = self:CreateTextBlock(content)
                block:AddLine(entry.version .. "   " .. muted .. (entry.date or "") .. "|r", "value")
                if entry.summary then block:AddLine(entry.summary, "hint") end
                for _, sec in ipairs(entry.sections or {}) do
                    block:AddLine(sec.head or "", "groupLabel", { gap = 10 })
                    for _, item in ipairs(sec.items or {}) do
                        block:AddLine(item, "label", { bullet = "-" })
                    end
                end
                changelog:Add(block, { fitHeight = true })
            end
        end
        changelog:Add(self:CreateButton(content, L["Older versions are on CurseForge"], nil,
            function() ns:ShowURL(CURSEFORGE_URL) end, nil, "ghost"))
    end,

    -- Live, because "is the provider empty or is the section not rendering" is the
    -- first question asked whenever something does not appear. Left untranslated with
    -- the rest of the diagnostic output - the counts are for bug reports, not reading.
    refresh = function(self, content)
        local muted = colorCode(self, "muted")
        for _, p in ipairs(ns:GetModule("Registry"):Active()) do
            local row = content._providerRows and content._providerRows[p.id]
            if row then
                if not p._available then
                    row.label:SetTextColor(self:Color("muted"))
                    row.text:SetTextColor(self:Color("muted"))
                    row.text:SetText("unavailable on this client")
                else
                    local ok, entries = pcall(p.GetEntries, p)
                    local n = (ok and entries) and #entries or -1
                    row.label:SetTextColor(self:Color("text"))
                    row.text:SetTextColor(self:Color("label"))
                    row.text:SetText(("%d entries   %sgroups: %s|r")
                        :format(math.max(0, n), muted, table.concat(p.groups, ", ")))
                end
            end
        end
    end,
})
