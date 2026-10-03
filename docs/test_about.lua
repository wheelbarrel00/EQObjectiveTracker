-- Unit tests for Options/TabAbout.lua, run against the SHIPPED source.
-- Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_about.lua
--
-- The tab loads WHOLE over a stub context that records what the library would draw: each card
-- and how it is anchored, the rows it stacks in order with the options each was added with,
-- every text block's lines with their style and options, every two-column text row, and every
-- button with its style and click.
--
-- WHAT EARNS THIS FILE: About is where a player reads the commands, the credits and the release
-- history, and it had no harness. Since the 2.0.0 restyle (2026-10-02) it is five cards whose rows
-- are text blocks that size themselves, so a row added without fitHeight (held at a fixed height
-- while its text runs on), a line in the wrong card, a link opening the wrong page or the
-- provider refresh reading the wrong state would show only in game. The theme the author
-- approved is checked too: no gold and no brand red, names bright and dates muted, and every
-- key the tab asks for already translated.
--
-- OUT OF SCOPE BY CONSTRUCTION: how any of it looks. Wrapping, row heights and the label column
-- are the library's tests' business.

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
end

local function readFile(rel)
    local f = assert(io.open(repoFile(rel), "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end

local COLORS = {
    text  = { 0.910, 0.918, 0.929 },
    label = { 0.769, 0.784, 0.808 },
    muted = { 0.545, 0.565, 0.596 },
}
local BRIGHT, MUTED = "|cffe8eaed", "|cff8b9098"
local SPACING = { groupGap = 22, listRowHeight = 28, buttonHeight = 32, buttonGap = 10 }

local CURSEFORGE = "https://www.curseforge.com/wow/addons/eq-objective-tracker"
local GITHUB     = "https://github.com/wheelbarrel00/EQObjectiveTracker"
local BUGS       = "https://github.com/wheelbarrel00/EQObjectiveTracker/issues"

local function frame(kind)
    local f = { kind = kind, shown = true, points = {} }
    function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function f:SetHeight(h) self.height = h end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    return f
end

local function fontString(text)
    local fs = { text = text }
    function fs:SetText(s) self.text = s end
    function fs:GetText() return self.text end
    function fs:SetTextColor(r, g, b) self.color = { r, g, b } end
    return fs
end

local function isColor(c, name)
    local want = COLORS[name]
    return c ~= nil and c[1] == want[1] and c[2] == want[2] and c[3] == want[3]
end

local DEFAULT_PROVIDERS = {
    { id = "quests", _available = true, groups = { "quests", "campaign" },
      GetEntries = function() return { {}, {}, {} } end },
    { id = "scenarios", _available = false, groups = { "scenarios" } },
    { id = "worldquests", _available = true, groups = { "worldquests" },
      GetEntries = function() error("a provider raised") end },
}

local FIXTURE_LOG = {
    { version = "2.0.0", date = "2026-10-10", summary = "The options window, redone.",
      sections = {
          { head = "Improvements", items = { "The options window has a new look.", "Cards on every tab." } },
          { head = "Bug Fixes", items = { "Something mended." } },
      } },
    { date = "2026-10-05", sections = { { head = "Notes", items = { "A heading with no version." } } } },
    { version = "1.28.0", date = "2026-09-30",
      sections = { { head = "New Features", items = { "Use Blizzard's quest tracker." } } } },
}

-- Builds the tab once. log is the changelog it reads, and providers is what the Registry answers.
local function aboutTab(log, providers)
    providers = providers or DEFAULT_PROVIDERS
    local t = { cards = {}, buttons = {}, blocks = {}, textRows = {}, frames = {}, urls = {},
                discord = 0, keys = {} }
    local modules = {}
    local ns = {
        VERSION = "1.28.0",
        Changelog = log,
        L = setmetatable({}, { __index = function(_, k) t.keys[k] = true return k end }),
    }
    function ns:GetModule(name) return modules[name] end
    function ns:ShowDiscord() t.discord = t.discord + 1 end
    function ns:ShowURL(url) t.urls[#t.urls + 1] = url end
    local spec
    modules.Options = { RegisterTab = function(_, s) spec = s end }
    t.active = providers
    modules.Registry = { Active = function() return t.active end }

    local ui = {}
    function ui:Color(name)
        local c = assert(COLORS[name], "no color named " .. tostring(name))
        return c[1], c[2], c[3]
    end
    function ui:Spacing(name)
        return assert(SPACING[name], "no spacing named " .. tostring(name))
    end
    function ui:CreateGroup(_, label)
        local card = frame("card")
        card.title, card.rows = label, {}
        card.Add = function(c, ctl, opts)
            local row = frame("row")
            row.control, row.opts = ctl, opts or {}
            ctl.card = c
            c.rows[#c.rows + 1] = row
            return row
        end
        t.cards[#t.cards + 1] = card
        return card
    end
    function ui:CreateTextBlock()
        local block = frame("block")
        block.lines = {}
        block.AddLine = function(b, text, style, opts)
            local fs = fontString(text)
            b.lines[#b.lines + 1] = { text = text, style = style, opts = opts or {}, fs = fs }
            return fs
        end
        block.Measure = function() return 1 end
        t.blocks[#t.blocks + 1] = block
        return block
    end
    function ui:CreateTextRow(_, label, text)
        local row = frame("textrow")
        row.label, row.text = fontString(label), fontString(text)
        t.textRows[#t.textRows + 1] = row
        return row
    end
    function ui:CreateButton(_, label, width, onClick, tooltip, style)
        local b = frame("button")
        b.label, b.width, b.onClick, b.tooltip, b.style = label, width, onClick, tooltip, style
        t.buttons[#t.buttons + 1] = b
        return b
    end

    -- The tab's only bare global is CreateFrame, so the chunk runs in a sandbox that adds it
    -- rather than setting a real global here.
    local env = setmetatable({
        CreateFrame = function(kind)
            local f = frame(kind)
            t.frames[#t.frames + 1] = f
            return f
        end,
    }, { __index = _G })
    local chunk = assert(loadfile(repoFile("Options/TabAbout.lua")))
    setfenv(chunk, env)
    chunk("EQObjectiveTracker", ns)
    t.spec, t.ui = spec, ui
    t.content = {}
    spec.build(ui, t.content)
    return t
end

-- Every line of text the tab drew, for the theme checks.
local function everyText(t)
    local out = {}
    for _, b in ipairs(t.blocks) do
        for _, line in ipairs(b.lines) do out[#out + 1] = line.text end
        for _, line in ipairs(b.lines) do out[#out + 1] = line.fs.text end
    end
    for _, r in ipairs(t.textRows) do
        out[#out + 1] = r.label.text
        out[#out + 1] = r.text.text
    end
    for _, b in ipairs(t.buttons) do out[#out + 1] = b.label end
    return out
end

local function case(name, fn)
    print("== " .. name)
    local good, err = pcall(fn)
    ok(good, name .. " raised: " .. tostring(err))
end

case("the tab registers as About, last, with a live refresh and no footer", function()
    local t = aboutTab(FIXTURE_LOG)
    ok(t.spec.id == "about" and t.spec.title == "About" and t.spec.order == 90, "id, title and order")
    ok(type(t.spec.build) == "function" and type(t.spec.refresh) == "function" and t.spec.footer == nil,
       "a build, a refresh and no footer")
end)

case("five cards, one per section the tab already had, stacked in order", function()
    local t = aboutTab(FIXTURE_LOG)
    local want = { false, "Commands", "Content providers", "Thanks", "Changelog" }
    ok(#t.cards == #want, "five cards: " .. #t.cards)
    for i, title in ipairs(want) do
        local card = t.cards[i]
        if title then
            ok(card and card.title == title, "card " .. i .. " is " .. title .. ": " .. tostring(card and card.title))
        else
            ok(card and card.title == nil, "the first card has no group label")
        end
    end
    local first = t.cards[1].points
    ok(#first == 2 and first[1][1] == "TOPLEFT" and first[1][2] == nil and first[2][1] == "TOPRIGHT"
       and first[2][2] == nil, "the first card tops the content, edge to edge")
    for i = 2, #t.cards do
        local p = t.cards[i].points
        ok(#p == 2 and p[1][1] == "TOPLEFT" and p[1][2] == t.cards[i - 1] and p[1][3] == "BOTTOMLEFT"
           and p[1][5] == -22 and p[2][1] == "TOPRIGHT" and p[2][2] == t.cards[i - 1]
           and p[2][3] == "BOTTOMRIGHT" and p[2][5] == -22,
           "card " .. i .. " hangs 22 under the one above it")
    end
end)

case("the top card: the version, what the addon is, and four links", function()
    local t = aboutTab(FIXTURE_LOG)
    local intro = t.cards[1]
    ok(#intro.rows == 2, "two rows: " .. #intro.rows)
    local blurb = intro.rows[1].control
    ok(blurb.kind == "block" and intro.rows[1].opts.fitHeight == true, "a text block, sized to its text")
    ok(#blurb.lines == 2, "two lines")
    ok(blurb.lines[1].text == "Version 1.28.0 by Wheelbarrel00" and blurb.lines[1].style == "value",
       "the version line carries the version, in the value style: " .. tostring(blurb.lines[1].text))
    ok(blurb.lines[2].text:find("standalone replacement", 1, true) and (blurb.lines[2].style or "label") == "label",
       "then what the addon is, as a label")

    local links = intro.rows[2]
    ok(links.control.kind == "Frame" and links.opts.fill == true and links.control.height == 32,
       "a button-high strip across the row")
    local want = {
        { "Join our Discord" }, { "CurseForge", CURSEFORGE }, { "GitHub", GITHUB }, { "Report a Bug", BUGS },
    }
    local buttons = {}
    for _, b in ipairs(t.buttons) do if b.label ~= "Older versions are on CurseForge" then buttons[#buttons + 1] = b end end
    ok(#buttons == 4, "four link buttons: " .. #buttons)
    for i, w in ipairs(want) do
        local b = buttons[i]
        ok(b and b.label == w[1], "link " .. i .. " is " .. w[1])
        ok(b and b.width == nil and b.style == nil and b.tooltip == nil,
           w[1] .. " is a secondary button sized from its text")
        local p = b and b.points[1]
        if i == 1 then
            ok(p and p[1] == "LEFT" and p[2] == links.control and p[3] == "LEFT" and (p[4] or 0) == 0,
               "the first starts at the strip's left")
        else
            ok(p and p[1] == "LEFT" and p[2] == buttons[i - 1] and p[3] == "RIGHT" and p[4] == 10 and (p[5] or 0) == 0,
               w[1] .. " sits 10 right of the one before")
        end
    end
    buttons[1].onClick()
    ok(t.discord == 1 and #t.urls == 0, "Discord opens the invite, not a page")
    for i = 2, 4 do
        buttons[i].onClick()
        ok(t.urls[#t.urls] == want[i][2], want[i][1] .. " opens " .. want[i][2] .. ": " .. tostring(t.urls[#t.urls]))
    end
end)

case("Commands: one list row per command, the command bright", function()
    local t = aboutTab(FIXTURE_LOG)
    local want = {
        { "/eqot", "Open this window" }, { "/eqot lock", "Lock moving and resizing" },
        { "/eqot unlock", "Unlock moving and resizing" }, { "/eqot reset", "Restore the default position and size" },
        { "/eqot toggle", "Show or hide the tracker" }, { "/eqot importeq", "Import your Everything Quests settings" },
        { "/eqot status", "Print provider status to chat" }, { "/eqot debug", "Toggle entry validation warnings" },
    }
    local card = t.cards[2]
    ok(#card.rows == #want, "eight rows: " .. #card.rows)
    for i, w in ipairs(want) do
        local row = card.rows[i]
        local c = row and row.control
        ok(c and c.kind == "textrow" and c.label.text == w[1] and c.text.text == w[2], "row " .. i .. " is " .. w[1])
        ok(row and row.opts.height == 28 and not row.opts.fitHeight, w[1] .. " is a 28 px list row")
        ok(c and isColor(c.label.color, "text"), w[1] .. " is drawn bright")
    end
end)

case("Content providers: the note, then one live row per provider", function()
    local t = aboutTab(FIXTURE_LOG)
    local card = t.cards[3]
    ok(#card.rows == 1 + #DEFAULT_PROVIDERS, "a note and three providers: " .. #card.rows)
    local note = card.rows[1]
    ok(note.control.kind == "block" and note.opts.fitHeight == true and #note.control.lines == 1
       and note.control.lines[1].style == "hint"
       and note.control.lines[1].text:find("Providers are gated at load time", 1, true),
       "the note is a hint, sized to its text")
    for i, p in ipairs(DEFAULT_PROVIDERS) do
        local row = card.rows[i + 1]
        ok(row and row.control.kind == "textrow" and row.control.label.text == p.id and row.opts.height == 28,
           p.id .. " has a 28 px row")
        ok(row and t.content._providerRows[p.id] == row.control, p.id .. " is kept for the refresh")
    end

    t.spec.refresh(t.ui, t.content)
    local q, s, w = t.content._providerRows.quests, t.content._providerRows.scenarios,
                    t.content._providerRows.worldquests
    ok(q.text.text == "3 entries   " .. MUTED .. "groups: quests, campaign|r",
       "an available provider counts its entries and lists its groups muted: " .. tostring(q.text.text))
    ok(isColor(q.label.color, "text") and isColor(q.text.color, "label"), "its name bright, its count a label")
    ok(s.text.text == "unavailable on this client" and isColor(s.label.color, "muted") and isColor(s.text.color, "muted"),
       "an unavailable one says so, all muted")
    ok(w.text.text == "0 entries   " .. MUTED .. "groups: worldquests|r", "a provider that raises reads 0, and the tab lives")

    t.active = {
        { id = "quests", _available = true, groups = { "quests" }, GetEntries = function() return nil end },
        { id = "late", _available = true, groups = { "late" }, GetEntries = function() return {} end },
    }
    t.spec.refresh(t.ui, t.content)
    ok(q.text.text == "0 entries   " .. MUTED .. "groups: quests|r", "an answer of nil reads 0")
    ok(t.content._providerRows.late == nil, "a provider with no row built is passed over")

    local again = aboutTab(FIXTURE_LOG)
    again.spec.refresh(again.ui, again.content)
    again.spec.refresh(again.ui, again.content)
    ok(again.content._providerRows.quests.text.text == "3 entries   " .. MUTED .. "groups: quests, campaign|r",
       "every view writes the same line again")
end)

case("Thanks: one row per credit, the name bright inside the translated line", function()
    local t = aboutTab(FIXTURE_LOG)
    local names = { "DrahgunFyre", "Zox", "Malevi4", "labrie75", "Keriaovo", "BNS333", "Stonetwist" }
    local card = t.cards[4]
    ok(#card.rows == #names, "seven credits: " .. #card.rows)
    for i, name in ipairs(names) do
        local row = card.rows[i]
        local block = row and row.control
        ok(block and block.kind == "block" and row.opts.fitHeight == true and #block.lines == 1,
           name .. " has a row sized to its text")
        local line = block and block.lines[1]
        ok(line and (line.style or "label") == "label" and line.text:find("Special thanks to " .. BRIGHT .. name .. "|r", 1, true),
           name .. " is bright inside a label line: " .. tostring(line and line.text))
    end
    ok(card.rows[1].control.lines[1].text:find("features, fixes, and reports", 1, true)
       and card.rows[2].control.lines[1].text:find("into French", 1, true), "each name keeps its own line")
end)

case("Changelog: one row per version, the date muted, every section and item", function()
    local t = aboutTab(FIXTURE_LOG)
    local card = t.cards[5]
    ok(#card.rows == 3, "two versions and the CurseForge link, the version-less entry skipped: " .. #card.rows)
    local first = card.rows[1]
    local b = first.control
    ok(b.kind == "block" and first.opts.fitHeight == true, "a version is a text block sized to its text")
    local want = {
        { "2.0.0   " .. MUTED .. "2026-10-10|r", "value" },
        { "The options window, redone.", "hint" },
        { "Improvements", "groupLabel", 10 },
        { "The options window has a new look.", "label", nil, "-" },
        { "Cards on every tab.", "label", nil, "-" },
        { "Bug Fixes", "groupLabel", 10 },
        { "Something mended.", "label", nil, "-" },
    }
    ok(#b.lines == #want, "seven lines: " .. #b.lines)
    for i, w in ipairs(want) do
        local line = b.lines[i]
        ok(line and line.text == w[1] and line.style == w[2], "line " .. i .. " is " .. w[1] .. " as " .. w[2]
           .. ": " .. tostring(line and line.text) .. " / " .. tostring(line and line.style))
        ok(line and line.opts.gap == w[3] and line.opts.bullet == w[4] and line.opts.indent == nil,
           "line " .. i .. " has its gap and bullet")
    end
    local second = card.rows[2].control
    ok(second.lines[1].text == "1.28.0   " .. MUTED .. "2026-09-30|r" and #second.lines == 3,
       "a version with no summary goes straight to its sections")

    local older = card.rows[3]
    ok(older.control.kind == "button" and older.control.label == "Older versions are on CurseForge"
       and older.control.style == "ghost" and older.control.width == nil and not older.opts.fitHeight,
       "the CurseForge link is a ghost button")
    older.control.onClick()
    ok(t.urls[#t.urls] == CURSEFORGE, "and opens the CurseForge page")
end)

case("the real changelog builds one row per version it holds", function()
    local chunk = assert(loadfile(repoFile("Core/Changelog.lua")))
    local ns = {}
    chunk("EQObjectiveTracker", ns)
    local versions = 0
    for _, e in ipairs(ns.Changelog) do if e.version then versions = versions + 1 end end
    ok(versions > 40, "the shipped changelog is long: " .. versions)
    local t = aboutTab(ns.Changelog)
    ok(#t.cards[5].rows == versions + 1, "every version has its row: " .. #t.cards[5].rows)
    ok(t.cards[5].rows[1].control.lines[1].text:find("^%d+%.%d+%.%d+   " .. MUTED:gsub("|", "%%|")) ~= nil,
       "the newest first: " .. tostring(t.cards[5].rows[1].control.lines[1].text))
end)

case("a changelog that is missing, or empty, still builds", function()
    local t = aboutTab(nil)
    ok(#t.cards == 5 and #t.cards[5].rows == 1 and t.cards[5].rows[1].control.kind == "button",
       "with no changelog the card holds only the link")
    local e = aboutTab({ { version = "1.0.0" } })
    ok(e.cards[5].rows[1].control.lines[1].text == "1.0.0   " .. MUTED .. "|r" and #e.cards[5].rows[1].control.lines == 1,
       "a version with no date and no sections is one line")
end)

case("the theme the author approved, and no key that is not translated", function()
    local t = aboutTab(FIXTURE_LOG)
    t.spec.refresh(t.ui, t.content)
    local allowed = { [BRIGHT] = true, [MUTED] = true }
    for _, s in ipairs(everyText(t)) do
        for code in tostring(s):gmatch("|c%x%x%x%x%x%x%x%x") do
            ok(allowed[code:lower()], "only the theme's bright and muted escapes are drawn: " .. code .. " in " .. s)
        end
    end
    local src = readFile("Options/TabAbout.lua")
    ok(not src:find("GOLD", 1, true) and not src:find("BRAND_RED", 1, true) and not src:find("SetFont", 1, true),
       "no gold, no brand red and no font of the tab's own")
    local enUS = readFile("Locales/enUS.lua")
    local n = 0
    for key in pairs(t.keys) do
        n = n + 1
        -- Built with %q rather than written out, or the locale scanner reads the needle as a key.
        ok(enUS:find(("L[%q]"):format(key), 1, true) ~= nil, "the key is already in enUS: " .. key)
    end
    ok(n >= 20, "every string the tab draws went through L: " .. n)
end)

print(("test_about: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
