-- Unit tests for Data/Filter.lua, run against the SHIPPED source.
-- Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_filter.lua
--
-- Data/Filter.lua loads WHOLE. It creates no frame and calls no game API, so an ns carrying
-- RegisterModule, L and two module stubs is a complete stand-in.
--
-- WHAT EARNS THIS FILE is the campaign exemption from the current-zone filter. It must keep an
-- out-of-zone campaign quest and ONLY that: not a normal quest, not a quest the player untracked
-- while Show only tracked quests is on (the author's call on 2026-09-27), not one whose Campaign
-- quests category is off, and nothing at all while the zone filter itself is off. Its count has
-- to hold only the rows it really kept, or the status line reads as a feature firing when the
-- zone rule never asked it anything.
--
-- The block after the driven cases is GREPS. The tag, the default and the checkbox live in three
-- other files, and a key spelled differently in any of them switches the feature off with every
-- driven case green. The last block loads the real Options/TabTracker.lua over a stub context and
-- drives its Filters card: the order its rows stack in, and what Reset filters does.
--
-- OUT OF SCOPE BY CONSTRUCTION: whether IsCurrentZone places a quest correctly, which no harness
-- covers (/eqot zoneprobe reads it in game), and how the checkbox looks on screen.

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

local function count(src, needle)
    local n, from = 0, 1
    while true do
        local i = src:find(needle, from, true)
        if not i then return n end
        n, from = n + 1, i + 1
    end
end

local function stripComments(src)
    src = src:gsub("%-%-%[(=*)%[.-%]%1%]", "")
    return (src:gsub("%-%-[^\n]*", ""))
end

-- ------------------------------------------------------------------------------ the world

-- A fresh module per call. Production has ONE Filter for the session, so the cases that drive
-- two passes through the same module are the ones that can see a count never being reset.
local function fresh(opts)
    opts = opts or {}
    local modules, state = {}, { cfg = nil }
    local ns = { L = setmetatable({}, { __index = function(_, k) return k end }) }
    function ns:RegisterModule(name, t) modules[name] = t return t end
    function ns:GetModule(name) return modules[name] end
    modules.AutoQuestPopups = {
        IsSuppressed = function(_, id) return (opts.suppressed and opts.suppressed[id]) or false end,
    }
    modules.DB = {
        Char    = function() return { pinned = opts.pinned } end,
        Tracker = function() return state.cfg end,
    }
    assert(loadfile(repoFile("Data/Filter.lua")))("EQObjectiveTracker", ns)
    local F = modules.Filter
    assert(F and F.Visible, "Data/Filter.lua never registered its module")
    return F, state
end

-- zone maps an entry id to what IsCurrentZone answers. A missing id answers nil, which is the
-- provider saying it cannot tell.
local function questProvider(zone)
    return {
        id = "quests", idSpace = "quest", filterCategories = true,
        IsCurrentZone = function(_, e) return zone[e.id] end,
    }
end

local function entry(id, tags, tracked)
    return { id = id, providerID = "quests", tags = tags, isTracked = tracked ~= false }
end

local function cfgWith(filters, extra)
    local c = { filters = filters }
    for k, v in pairs(extra or {}) do c[k] = v end
    return c
end

local function vis(F, e, c, p)
    local okCall, res = pcall(F.Visible, F, e, c, p)
    ok(okCall, "Visible does not raise" .. (okCall and "" or (" - " .. tostring(res))))
    if not okCall then return nil end
    return res
end

local function line(F)
    local okCall, res = pcall(F.FiltersLine, F)
    ok(okCall, "FiltersLine does not raise" .. (okCall and "" or (" - " .. tostring(res))))
    if not okCall then return "" end
    return res
end

local CAMPAIGN = function() return { campaign = true } end
local ZONE_ON_EXEMPT = function() return { onlyCurrentZone = true, campaignAnyZone = true } end

-- ------------------------------------------------------------------------------- cases

print("== with the exemption off, the zone filter hides an out-of-zone campaign quest")
do
    for _, flag in ipairs({ "absent", "false" }) do
        local F = fresh()
        F:BeginPass()
        local filters = { onlyCurrentZone = true }
        if flag == "false" then filters.campaignAnyZone = false end
        local shown = vis(F, entry(10, CAMPAIGN()), cfgWith(filters), questProvider({ [10] = false }))
        ok(shown == false, "hidden with campaignAnyZone " .. flag .. ": " .. tostring(shown))
        ok(F.rejects.zone == 1, "and counted as a zone reject: " .. tostring(F.rejects.zone))
        ok(F.campaignKept == 0, "and not as kept: " .. tostring(F.campaignKept))
    end
end

print("== with it on, an out-of-zone campaign quest stays and is counted as kept")
do
    local F = fresh()
    F:BeginPass()
    local shown = vis(F, entry(20, CAMPAIGN()), cfgWith(ZONE_ON_EXEMPT()),
                      questProvider({ [20] = false }))
    ok(shown == true, "kept on the tracker: " .. tostring(shown))
    ok(F.campaignKept == 1, "counted once: " .. tostring(F.campaignKept))
    ok(F.rejects.zone == 0, "and NOT also counted as a zone reject: " .. tostring(F.rejects.zone))
end

print("== it keeps campaign quests only, never another out-of-zone quest")
do
    local F = fresh()
    F:BeginPass()
    local c, p = cfgWith(ZONE_ON_EXEMPT()), questProvider({ [30] = false, [31] = false, [32] = false })
    ok(vis(F, entry(30, {}), c, p) == false, "an untagged quest is still hidden")
    ok(vis(F, entry(31, { daily = true }), c, p) == false, "a daily is still hidden")
    ok(vis(F, entry(32, { weekly = true, dungeon = true }), c, p) == false,
       "a quest with other tags is still hidden")
    ok(F.rejects.zone == 3, "all three counted as zone rejects: " .. tostring(F.rejects.zone))
    ok(F.campaignKept == 0, "none counted as kept: " .. tostring(F.campaignKept))
end

print("== a campaign quest IN the zone shows as it always did and is not counted")
do
    -- The count means "the zone rule would have hidden this". A row the zone rule passes on its
    -- own is not something the exemption did.
    local F = fresh()
    F:BeginPass()
    local shown = vis(F, entry(40, CAMPAIGN()), cfgWith(ZONE_ON_EXEMPT()),
                      questProvider({ [40] = true }))
    ok(shown == true, "shown: " .. tostring(shown))
    ok(F.campaignKept == 0, "not counted as kept: " .. tostring(F.campaignKept))
end

print("== a quest the provider cannot place fails open and is not counted")
do
    local F = fresh()
    F:BeginPass()
    local shown = vis(F, entry(50, CAMPAIGN()), cfgWith(ZONE_ON_EXEMPT()), questProvider({}))
    ok(shown == true, "shown through the nil answer: " .. tostring(shown))
    ok(F.campaignKept == 0, "not counted as kept: " .. tostring(F.campaignKept))
    ok(F.rejects.zone == 0, "and not a zone reject: " .. tostring(F.rejects.zone))
end

print("== with the zone filter off the exemption does nothing and counts nothing")
do
    local F = fresh()
    F:BeginPass()
    local c = cfgWith({ onlyCurrentZone = false, campaignAnyZone = true })
    local p = questProvider({ [60] = false, [61] = false })
    ok(vis(F, entry(60, CAMPAIGN()), c, p) == true, "an out-of-zone campaign quest shows")
    ok(vis(F, entry(61, {}), c, p) == true, "and so does an out-of-zone normal one")
    ok(F.campaignKept == 0, "nothing counted as kept: " .. tostring(F.campaignKept))
    ok(F.rejects.zone == 0, "nothing rejected: " .. tostring(F.rejects.zone))
end

print("== it does NOT override Show only tracked quests")
do
    -- The author's decision on 2026-09-27: untracking a quest is the player's own choice.
    local F = fresh()
    F:BeginPass()
    local c = cfgWith(ZONE_ON_EXEMPT(), { showOnlyWatched = true })
    local p = questProvider({ [70] = false, [71] = false })
    ok(vis(F, entry(70, CAMPAIGN(), false), c, p) == false,
       "an untracked out-of-zone campaign quest is hidden")
    ok(F.rejects.watched == 1, "by the tracked rule: " .. tostring(F.rejects.watched))
    ok(vis(F, entry(71, CAMPAIGN(), true), c, p) == true,
       "a TRACKED one beside it still shows, so the rule is not simply off")
    ok(F.campaignKept == 1, "and only the tracked one is counted: " .. tostring(F.campaignKept))
end

print("== it does NOT override the Campaign quests category")
do
    local F = fresh()
    F:BeginPass()
    local filters = ZONE_ON_EXEMPT()
    filters.showCampaign = false
    local shown = vis(F, entry(80, CAMPAIGN()), cfgWith(filters), questProvider({ [80] = false }))
    ok(shown == false, "unchecking Campaign quests still hides it: " .. tostring(shown))
    ok(F.rejects.category == 1, "by the category rule: " .. tostring(F.rejects.category))
    ok(F.campaignKept == 0, "and it is not counted as kept: " .. tostring(F.campaignKept))
end

print("== a pinned quest shows through its pin and is not counted as kept")
do
    local F = fresh({ pinned = { quests = { [90] = true } } })
    F:BeginPass()
    local shown = vis(F, entry(90, CAMPAIGN()), cfgWith(ZONE_ON_EXEMPT()),
                      questProvider({ [90] = false }))
    ok(shown == true, "shown: " .. tostring(shown))
    ok(F.campaignKept == 0, "the pin kept it, not the exemption: " .. tostring(F.campaignKept))
end

print("== an entry carrying no tags table is hidden rather than raising")
do
    local F = fresh()
    F:BeginPass()
    local e = entry(100, nil)
    local shown = vis(F, e, cfgWith(ZONE_ON_EXEMPT()), questProvider({ [100] = false }))
    ok(shown == false, "hidden by the zone rule: " .. tostring(shown))
end

print("== a provider that does not opt into category filters is untouched")
do
    local F = fresh()
    F:BeginPass()
    local p = { id = "achievements", IsCurrentZone = function() return false end }
    local e = { id = 110, providerID = "achievements", tags = CAMPAIGN(), isTracked = true }
    ok(vis(F, e, cfgWith(ZONE_ON_EXEMPT()), p) == true, "shown")
    ok(F.campaignKept == 0, "and not counted: " .. tostring(F.campaignKept))
end

print("== BeginPass clears the count on the SAME module, and a pass accumulates")
do
    local F = fresh()
    local c = cfgWith(ZONE_ON_EXEMPT())
    local p = questProvider({ [120] = false, [121] = false, [122] = false })
    F:BeginPass()
    vis(F, entry(120, CAMPAIGN()), c, p)
    vis(F, entry(121, CAMPAIGN()), c, p)
    ok(F.campaignKept == 2, "two kept in one pass: " .. tostring(F.campaignKept))
    F:BeginPass()
    ok(F.campaignKept == 0, "a new pass starts at zero: " .. tostring(F.campaignKept))
    vis(F, entry(122, CAMPAIGN()), c, p)
    ok(F.campaignKept == 1, "and counts only its own rows: " .. tostring(F.campaignKept))
end

print("== the status line names the switch and the count")
do
    local F, state = fresh()
    local p = questProvider({ [130] = false, [131] = false })

    state.cfg = cfgWith(ZONE_ON_EXEMPT())
    F:BeginPass()
    vis(F, entry(130, CAMPAIGN()), state.cfg, p)
    vis(F, entry(131, CAMPAIGN()), state.cfg, p)
    local s = line(F)
    ok(s:find("onlyCurrentZone=true campaignAnyZone=true |", 1, true) ~= nil,
       "the switch is named beside the zone filter: " .. s)
    ok(s:find("rejected this pass: watched 0, category 0, zone 0, popup 0 |", 1, true) ~= nil,
       "the reject counts keep the wording the diagnostics notes quote: " .. s)
    ok(s:find("campaign kept from other zones 2", 1, true) ~= nil,
       "the kept count is the live figure, not a literal: " .. s)

    -- Zone on and the exemption OFF, so a line printing the zone flag in the campaign slot
    -- reads differently from a correct one.
    state.cfg = cfgWith({ onlyCurrentZone = true, campaignAnyZone = false })
    F:BeginPass()
    s = line(F)
    ok(s:find("onlyCurrentZone=true campaignAnyZone=false |", 1, true) ~= nil,
       "the exemption reads false while it is off: " .. s)
    ok(s:find("campaign kept from other zones 0", 1, true) ~= nil, "and nothing kept: " .. s)

    state.cfg = {}
    s = line(F)
    ok(s:find("campaignAnyZone=false | no filters table", 1, true) ~= nil,
       "a profile with no filters table reads false rather than raising: " .. s)
end

print("== a provider with category filters and no IsCurrentZone passes the zone rule untouched")
do
    -- WorldQuests opts into category filters and has no IsCurrentZone, so the presence test in
    -- the zone rule runs for every world quest while the zone filter is on.
    local F = fresh()
    F:BeginPass()
    local p = { id = "worldquests", idSpace = "quest", filterCategories = true }
    local e = { id = 140, providerID = "worldquests", tags = { worldquest = true }, isTracked = true }
    ok(vis(F, e, cfgWith(ZONE_ON_EXEMPT()), p) == true, "a world quest is not asked where it is")
    ok(F.rejects.zone == 0 and F.campaignKept == 0,
       "and is neither rejected nor kept: " .. F.rejects.zone .. ", " .. F.campaignKept)
end

print("== a quest drawn as a Complete popup is not also a row, even pinned")
do
    local F = fresh({ suppressed = { [150] = true }, pinned = { quests = { [150] = true } } })
    F:BeginPass()
    local shown = vis(F, entry(150, CAMPAIGN()), cfgWith(ZONE_ON_EXEMPT()),
                      questProvider({ [150] = false }))
    ok(shown == false, "the popup wins over the pin: " .. tostring(shown))
    ok(F.rejects.popup == 1 and F.campaignKept == 0,
       "counted as a popup, not kept: " .. F.rejects.popup .. ", " .. F.campaignKept)
end

print("== a status read before the first pass reads zero rather than raising")
do
    local F, state = fresh()
    state.cfg = cfgWith(ZONE_ON_EXEMPT())
    local s = line(F)
    ok(s:find("campaign kept from other zones 0", 1, true) ~= nil, "zero before any pass: " .. s)
end

-- ---------------------------------------------------------------- the other three files

print("== the stripper refuses commented occurrences, so the greps below mean code")
do
    local probe = "-- DB().filters.campaignAnyZone = v;\n--[[\nf.campaignAnyZone = false\n]]\nx = 1\n"
    local stripped = stripComments(probe)
    ok(not stripped:find("campaignAnyZone", 1, true), "a line and a multi-line block comment both go")
    ok(stripped:find("x = 1", 1, true) ~= nil, "and the code after them stays")
end

print("== the retail quest provider writes the tag the exemption reads")
do
    -- Every case above hands Filter a literal { campaign = true }, so a renamed tag on the
    -- provider side would leave them all green with the exemption keeping nothing.
    local q = stripComments(readFile("Data/Providers/Quests.lua"))
    ok(count(q, "if isCampaign(id, info) then tags.campaign = true end") == 1,
       "Data/Providers/Quests.lua tags a campaign quest as tags.campaign")
    -- Registry:HasTag reads the provider's DECLARED list, not an entry's tags, and that is what
    -- decides whether the box is built at all.
    local declared = q:match("\n    tags%s*=%s*(%b{})")
    ok(declared ~= nil and declared:find('"campaign"', 1, true) ~= nil,
       "and declares the campaign tag, which is what builds the box: " .. tostring(declared))
end

print("== Core/DB.lua ships the switch OFF, inside the filters table")
do
    local db = stripComments(readFile("Core/DB.lua"))
    local block = db:match("\n%s*filters = {(.-)}")
    ok(block ~= nil, "the filters defaults table is found")
    block = block or ""
    ok(count(block, "campaignAnyZone = false,") == 1, "defaults to false in that table")
    ok(count(db, "campaignAnyZone") == 1, "and is written nowhere else in the file")
end

print("== Options/TabTracker.lua writes the key Filter reads, and clears it on reset")
do
    local tab = stripComments(readFile("Options/TabTracker.lua"))
    ok(count(tab, "return DB().filters.campaignAnyZone end") == 1, "the checkbox reads it")
    ok(count(tab, "DB().filters.campaignAnyZone = v;") == 1, "the checkbox writes it")
    ok(count(tab, "function(v) DB().filters.campaignAnyZone = v; render() end,") == 1,
       "and re-renders, as the zone filter's own setter does")
    ok(count(tab, "f.campaignAnyZone = false\n") == 1, "Reset filters clears it")
    ok(count(tab, "                if campaignZone then campaignZone:SetChecked(false) end\n") == 1,
       "and unticks the box on screen, which only reads its getter on a tab view")
    ok(count(tab, "campaignAnyZone") == 3, "and nothing else in the tab touches it")
    ok(count(tab, 'if Registry:HasTag("campaign") then') == 1,
       "the box is only built where a provider can tag a campaign quest")
    -- The author's call on 2026-09-27: grayed out while the zone filter was off, the box read as
    -- an option that only worked in one situation, so it is always lit.
    ok(count(tab, "SetDependent(campaignZone") == 0, "the box is never grayed out")
    -- Every reference the pins in this block expect, counted by whole token, so a gray-out, a
    -- Disable or a Hide spelled any other way adds one. luacheck catches a shadowing local.
    local refs = 0
    for _ in tab:gmatch("%f[%w_]campaignZone%f[^%w_]") do refs = refs + 1 end
    ok(refs == 6, "the box is referenced only where these pins expect it: " .. refs)
    ok(count(tab, "\n            campaignZone = self:CreateCheckbox(content, L") == 1,
       "and it is built into the outer local that Reset and the tooltip read")
    ok(count(tab, "function(v) DB().filters.onlyCurrentZone = v; render() end,") == 1,
       "and the zone filter's own setter is back to its shipped form, with nothing to resync")
    -- A reworded key orphans every translation of it. Built in pieces because the locale
    -- scanner reads docs/ too, and a whole L["..."] here would list this file as a user.
    ok(count(tab, "L" .. '["Always show campaign quests"]') == 1, "the label key is unchanged")
    -- The author's call on 2026-09-27: the reset tooltip names the campaign option, and only
    -- where its box is built. Everywhere else the old wording is still true and keeps its
    -- translations.
    ok(count(tab, "            campaignZone\n"
        .. "                and L" .. '["Turns every category filter back on, clears the current-zone'
        .. ' filter and turns off Always show campaign quests. Nothing else on this tab is changed."]\n'
        .. "                or L" .. '["Turns every category filter back on and clears the current-zone'
        .. ' filter. Nothing else on this tab is changed."])\n') == 1,
       "Reset filters names the campaign option where its box is built, and nowhere else")
end

-- Loads the REAL Options/TabTracker.lua with a stub context that records each card's rows in the
-- order they were added, which is the order they stack in. campaign is whether a provider can tag
-- a campaign quest, which is what builds the box.
local function trackerTab(campaign)
    local modules = {}
    local ns = {
        L = setmetatable({}, { __index = function(_, k) return k end }),
        Util = { Tooltip = function() return { Hide = function() end } end },
    }
    function ns:GetModule(name) return modules[name] end
    local cfg = { filters = { onlyCurrentZone = true, campaignAnyZone = true, showNormal = false } }
    local spec
    modules.Options = { RegisterTab = function(_, s) spec = s end }
    modules.DB = { Tracker = function() return cfg end }
    modules.Tracker = { Render = function() end }
    modules.Row = { Invalidate = function() end }
    modules.Media = { Play = function() end, GetSoundList = function() return {}, {} end }
    modules.Sections = {
        Known = function() return { "quests" } end, Order = function() return { "quests", "campaign" } end,
        IsHidden = function() return false end, SetHidden = function() end,
        Title = function(_, id) return id end, Move = function() end,
    }
    modules.Filter = { CATEGORIES = { { key = "showNormal", label = "Normal" }, { key = "showDaily", label = "Daily" } } }
    modules.Registry = { HasTag = function(_, tag) return tag == "campaign" and campaign end }

    local function frame()
        local f = { shown = true }
        function f:SetPoint() end
        function f:Show() self.shown = true end
        function f:Hide() self.shown = false end
        function f:SetShown(v) self.shown = v and true or false end
        function f:IsShown() return self.shown end
        function f:SetChecked(v) self.checked = v end
        function f:SetText(s) self.text = s end
        function f:SetEnabled() end
        function f:SetScript() end
        function f:HookScript() end
        return f
    end
    local cards, dimmed, ui = {}, {}, {}
    function ui:CreateGroup(_, label)
        local card = frame()
        card.title, card.rows, card.label = label, {}, frame()
        card.Add = function(c, control) c.rows[#c.rows + 1] = control return frame() end
        card.Layout = function() end
        cards[#cards + 1] = card
        return card
    end
    function ui:CreateCheckbox(_, label, getter, setter, tooltip)
        local f = frame()
        f.label, f.getter, f.setter, f.tooltip = label, getter, setter, tooltip
        return f
    end
    function ui:CreateButton(_, label, _, onClick, tooltip)
        local f = frame()
        f.label, f.onClick, f.tooltip = label, onClick, tooltip
        return f
    end
    function ui:CreateSlider(_, label) local f = frame() f.label, f.slider = label, frame() return f end
    function ui:CreateDropdown(_, label) local f = frame() f.label, f.button = label, frame() return f end
    function ui:CreateRadioGroup(_, label) local f = frame() f.label = label return f end
    function ui:CreateText(_, text) local f = frame() f.text = text return f end
    function ui:CreateIconButton() return frame() end
    function ui:AttachTooltip() end
    function ui:SetDependent(control, on) dimmed[#dimmed + 1] = { control = control, on = on } end
    function ui:MeasureContent() end
    function ui:Spacing() return 10 end

    assert(loadfile(repoFile("Options/TabTracker.lua")))("EQObjectiveTracker", ns)
    spec.build(ui, {})
    local byTitle = {}
    for _, c in ipairs(cards) do byTitle[c.title] = c end
    return { cards = cards, filters = byTitle["Filters"], cfg = cfg, dimmed = dimmed }
end

local CAMPAIGN_LABEL = "Always show campaign quests"
local RESET_LABEL = "Reset filters to defaults"

print("== the Filters card, driven through the real tab")
do
    local good, err = pcall(function()
        local t = trackerTab(true)
        ok(t.filters ~= nil and t.cards[2] == t.filters, "Filters is the second card")
        local rows = (t.filters or { rows = {} }).rows
        local n = #rows
        ok(rows[n] and rows[n].label == RESET_LABEL, "Reset filters is the card's last row")
        ok(rows[n - 1] and rows[n - 1].label == CAMPAIGN_LABEL,
           "the campaign box is the row just above it, the end of the filter run")
        ok(rows[n - 2] and rows[n - 2].label == "Show only quests in current zone", "under the zone filter")
        local boxes = 0
        for _, r in ipairs(rows) do if r.label == CAMPAIGN_LABEL then boxes = boxes + 1 end end
        ok(boxes == 1, "added once: " .. boxes)

        local box, reset, zone = rows[n - 1], rows[n], rows[n - 2]
        ok(box.getter() == true, "the box reads the switch")
        box.setter(false)
        ok(t.cfg.filters.campaignAnyZone == false, "and writes it")
        t.cfg.filters.campaignAnyZone = true
        box.checked = true
        reset.onClick()
        ok(t.cfg.filters.campaignAnyZone == false and box.checked == false,
           "Reset filters clears the switch and unticks the box on screen")
        ok(t.cfg.filters.onlyCurrentZone == false and zone.checked == false, "and the zone filter")
        ok(t.cfg.filters.showNormal == true and rows[1].checked == true, "and turns the categories back on")
        ok(reset.tooltip:find(CAMPAIGN_LABEL, 1, true) ~= nil, "its tooltip names the box it clears")
        local grayed = false
        for _, d in ipairs(t.dimmed) do if d.control == box then grayed = true end end
        ok(not grayed, "and the box is never grayed out")

        local c = trackerTab(false)
        local crows = c.filters.rows
        local cn = #crows
        ok(crows[cn].label == RESET_LABEL and crows[cn - 1].label == "Show only quests in current zone",
           "with no campaign tag the reset follows the zone filter")
        local any = false
        for _, r in ipairs(crows) do if r.label == CAMPAIGN_LABEL then any = true end end
        ok(not any, "and there is no box")
        ok(crows[cn].tooltip:find(CAMPAIGN_LABEL, 1, true) == nil, "and the tooltip does not name one")
        local okReset, resetErr = pcall(crows[cn].onClick)
        ok(okReset, "and the reset runs without it: " .. tostring(resetErr))
    end)
    ok(good, "the tab builds and the card drives: " .. tostring(err))
end

print(("test_filter: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
