-- Unit tests for the tracker's filter button, run against the SHIPPED source. Run from the repo
-- root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_filter_button.lua
--
-- WHY THIS FILE EXISTS. Requested by Tyrial ("the same thing but for the filter options,
-- multi-check drop down") and bramer26 (a header button for "show only the quests in the current
-- zone"), 2026-10-15. The author approved one funnel beside the sort button, off by default, whose
-- list stays open while boxes are checked: the current-zone filter on top, the Filters card's
-- categories, then Reset filters. The funnel turns gold while any filter in it is set to hide quests.
--
-- What is run: from UI/Tracker.lua, leftButtonX, FilterActive, PaintFilterButton, OpenFilterMenu,
-- ApplyHeaderIcons and BuildFrame's own build of the button. From Options/TabTracker.lua,
-- FILTER_ORDER and Options:ResetFilters. Data/Filter.lua WHOLE for the real categories and labels.
-- Every row handed to the menu is checked against the fields and kinds the VENDORED library's
-- Menu.lua accepts, since the library raises on any other.
--
-- OUT OF SCOPE BY CONSTRUCTION: how the library draws a check row or toggles its mark (its own
-- tests/test_menu.lua), the Tracker tab's box for the button (docs/test_tracker_tab.lua), and
-- what the filters hide (docs/test_filter.lua).

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
end

local function readFile(rel)
    local fh = assert(io.open(repoFile(rel), "r"))
    local src = fh:read("*a")
    fh:close()
    return src
end

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end

local function case(name, fn)
    print("== " .. name)
    local good, err = pcall(fn)
    ok(good, name .. " raised: " .. tostring(err))
end

local function count(src, s)
    local n, from = 0, 1
    while true do
        local i = src:find(s, from, true)
        if not i then return n end
        n, from = n + 1, i + 1
    end
end

local function only(src, anchor)
    assert(count(src, anchor) == 1, ("anchor matched %d times (need exactly 1): %s"):format(count(src, anchor), anchor))
    return src:find(anchor, 1, true)
end

local function between(src, fromAnchor, toAnchor)
    local a, b = only(src, fromAnchor), only(src, toAnchor)
    assert(b > a, "anchors out of order: " .. fromAnchor)
    return src:sub(a, b - 1)
end

local function throughEnd(src, fromAnchor)
    local a = only(src, fromAnchor)
    local b = src:find("\nend\n", a, true)
    assert(b, "no end after " .. fromAnchor)
    return src:sub(a, b + 4)
end

-- Whole-line and trailing comments out, so a commented-out statement cannot satisfy a check.
local function stripComments(src)
    local out = {}
    for line in (src .. "\n"):gmatch("(.-)\n") do
        if not line:match("^%s*%-%-") then
            out[#out + 1] = (line:gsub("%s+%-%-[^\"]*$", ""))
        end
    end
    return table.concat(out, "\n")
end

local trackerSrc = readFile("UI/Tracker.lua")
local tabSrc     = readFile("Options/TabTracker.lua")
local menuSrc    = readFile("Libs/EverythingUI/Menu.lua")

local leftSrc    = between(trackerSrc, "local function leftButtonX(cfg, pastFilter)\n",
                           "local function makeHeaderIcon(f, texture, tooltip, onClick, anchor)\n")
local methodsSrc = between(trackerSrc, "function Tracker:FilterActive()\n", "function Tracker:RebuildHeaderIcons()\n")
local applySrc   = throughEnd(trackerSrc, "function Tracker:ApplyHeaderIcons()\n")
local buildSrc   = between(trackerSrc, '    local filter = makeHeaderIcon(f, "Interface',
                           "    local cog = makeHeaderIcon(")
local orderSrc   = between(tabSrc, "local FILTER_ORDER = {\n", "-- Most of these say what they are in the label.")
local resetSrc   = throughEnd(tabSrc, "function Options:ResetFilters()\n")

-- The library's own field and kind lists, read off the vendored copy.
local MENU_FIELDS, MENU_KINDS = {}, {}
do
    local fields = menuSrc:match("local ITEM_FIELDS = (%b{})")
    local kinds = menuSrc:match("local KINDS = (%b{})")
    assert(fields and kinds, "Menu.lua's ITEM_FIELDS and KINDS are found")
    for k, v in fields:gmatch("(%w+)%s*=%s*\"(%w+)\"") do MENU_FIELDS[k] = v end
    for k in kinds:gmatch("(%w+)%s*=%s*true") do MENU_KINDS[k] = true end
end

-- --------------------------------------------------------------------------------- the world

local st

local function strictDB(cfg)
    local db = {}
    function db.Tracker(self)
        if self ~= db then error("DB:Tracker called without self", 2) end
        return cfg
    end
    return db
end

local function newIcon()
    local b = { shown = true, points = {} }
    function b:SetShown(v) self.shown = v and true or false end
    function b:ClearAllPoints() self.points = {} end
    function b:SetPoint(...) self.points[#self.points + 1] = { ... } end
    b.icon = {}
    function b.icon:SetVertexColor(r, g, bb) self.vertex = { r, g, bb } self.calls = (self.calls or 0) + 1 end
    return b
end

-- o.tags: the provider tags a loaded provider can produce, nil meaning every one (retail).
local function load(o)
    o = o or {}
    st = { renders = 0, refreshed = {}, menus = {}, layouts = 0 }
    local cfg = o.cfg
    if cfg == nil then
        cfg = { filters = { showNormal = true, showDaily = true, showWeekly = true, showScheduled = true,
                            showCampaign = true, showWorld = true, showBonus = true,
                            onlyCurrentZone = false, campaignAnyZone = false } }
    end
    st.cfg = cfg

    local L = setmetatable({}, { __index = function(_, k) return "<" .. k .. ">" end })
    local modules = {}
    local ns = { L = L }
    function ns:RegisterModule(name, m) modules[name] = m return m end
    function ns:GetModule(name) return modules[name] end

    local chunk = assert(loadfile(repoFile("Data/Filter.lua")))
    setfenv(chunk, setmetatable({}, { __index = _G }))
    chunk("EQObjectiveTracker", ns)

    if not o.noDB then modules.DB = strictDB(cfg) end
    if not o.noRegistry then
        local reg = {}
        function reg.HasTag(self, tag)
            if self ~= reg then error("Registry:HasTag called without self", 2) end
            if o.tags == nil then return true end
            return o.tags[tag] == true
        end
        modules.Registry = reg
    end

    local Options = {}
    function Options.RefreshIfShown(self, id)
        if self ~= Options then error("Options:RefreshIfShown called without self", 2) end
        st.refreshed[#st.refreshed + 1] = id
    end
    if not o.noUI then
        Options.ui = { ShowMenu = function(_, items, owner) st.menus[#st.menus + 1] = { items = items, owner = owner } end }
    end
    modules.Options = Options

    local tabEnv = setmetatable({ Options = Options, ns = ns, L = L,
                                  DB = function() return cfg end }, { __index = _G })
    local tabChunk = assert(loadstring(orderSrc .. resetSrc, "tab-slice"))
    setfenv(tabChunk, tabEnv)
    tabChunk()
    if o.noOrder then Options.FILTER_ORDER = nil end

    local Tracker = {}
    function Tracker.Render(self)
        if self ~= Tracker then error("Tracker:Render called without self", 2) end
        st.renders = st.renders + 1
    end
    function Tracker.LayoutMoveBar(self)
        if self ~= Tracker then error("LayoutMoveBar called without self", 2) end
        st.layouts = st.layouts + 1
    end
    modules.Tracker = Tracker
    st.Tracker, st.Options, st.modules = Tracker, Options, modules

    local env = setmetatable({ Tracker = Tracker, ns = ns, L = L, HEADER_ICON_SZ = 13,
                               GOLD_R = 0.92, GOLD_G = 0.72, GOLD_B = 0.02 }, { __index = _G })
    local trackerChunk = assert(loadstring(leftSrc .. methodsSrc .. applySrc
        .. "\nreturn function(f, makeHeaderIcon)\n" .. buildSrc .. "\nend", "tracker-slice"))
    setfenv(trackerChunk, env)
    st.build = trackerChunk()
    return st
end

local function frameWith(filterButton)
    return { headerIcons = {}, sortButton = newIcon(), filterButton = filterButton }
end

local function isGold(v) return v and v[1] == 0.92 and v[2] == 0.72 and v[3] == 0.02 end
local function isWhite(v) return v and v[1] == 1 and v[2] == 1 and v[3] == 1 end

-- ------------------------------------------------------------------------------ FilterActive

case("FilterActive is true while any filter the menu offers is set to hide quests", function()
    load()
    local T, f = st.Tracker, st.cfg.filters
    ok(T:FilterActive() == false, "every category on and the zone filter off: nothing hidden")
    f.onlyCurrentZone = true
    ok(T:FilterActive() == true, "the zone filter on")
    f.onlyCurrentZone = false
    f.showWeekly = false
    ok(T:FilterActive() == true, "a category off")
    f.showWeekly = nil
    ok(T:FilterActive() == false, "an unset category reads on, as the card reads it")
    f.showNormal = false
    ok(T:FilterActive() == true, "the untagged Normal category counts too")
    f.showNormal = true
    f.campaignAnyZone = true
    ok(T:FilterActive() == false, "Always show campaign quests hides nothing, so it does not count")

    load({ tags = { daily = true, weekly = true } })
    st.cfg.filters.showWorld = false
    ok(st.Tracker:FilterActive() == false, "a category no loaded provider produces, left off, does not count")
    st.cfg.filters.showDaily = false
    ok(st.Tracker:FilterActive() == true, "one that can, does")

    load({ cfg = { } })
    ok(st.Tracker:FilterActive() == false, "a profile with no filters table reads nothing active")
    load({ noRegistry = true })
    st.cfg.filters.showDaily = false
    ok(st.Tracker:FilterActive() == false, "no registry: categories cannot be told apart, so nothing counts")
    st.cfg.filters.onlyCurrentZone = true
    ok(st.Tracker:FilterActive() == true, "but the zone filter still does")
end)

-- ------------------------------------------------------------------------ PaintFilterButton

case("the funnel is gold while a filter is active and white otherwise, painted once per change", function()
    load()
    local T = st.Tracker
    local b = newIcon()
    T.frame = frameWith(b)
    T:PaintFilterButton()
    ok(isWhite(b.icon.vertex), "nothing hidden: white")
    st.cfg.filters.showDaily = false
    T:PaintFilterButton()
    ok(isGold(b.icon.vertex), "a category off: EQOT gold")
    local calls = b.icon.calls
    T:PaintFilterButton()
    ok(b.icon.calls == calls, "the same state again paints nothing")
    st.cfg.filters.showDaily = true
    T:PaintFilterButton()
    ok(isWhite(b.icon.vertex), "back to white once nothing is hidden")
    T.frame = { headerIcons = {} }
    ok(pcall(T.PaintFilterButton, T), "a frame with no button is passed over")
    T.frame = nil
    ok(pcall(T.PaintFilterButton, T), "and so is no frame")
end)

-- --------------------------------------------------------------------------- OpenFilterMenu

local function texts(m)
    local out = {}
    for i, it in ipairs(m.items) do
        out[i] = (it.kind and ("[" .. it.kind .. "]") or "") .. tostring(it.text)
            .. (it.checked == true and "+" or (it.checked == false and "-" or ""))
    end
    return table.concat(out, " | ")
end

local function validRows(m)
    for i, it in ipairs(m.items) do
        for k, v in pairs(it) do
            if MENU_FIELDS[k] ~= type(v) then return false, ("row %d field %s"):format(i, tostring(k)) end
        end
        if it.kind and not MENU_KINDS[it.kind] then return false, ("row %d kind %s"):format(i, it.kind) end
        if it.checked ~= nil and it.kind ~= "check" then return false, ("row %d checked on a plain row"):format(i) end
    end
    return true
end

case("the menu offers the zone filter, the card's categories in its order, then Reset", function()
    load()
    st.cfg.filters.onlyCurrentZone = true
    st.cfg.filters.showWeekly = false
    -- Unset reads as on, as the card's own box reads it: only a stored false hides a category.
    st.cfg.filters.showDaily = nil
    local owner = {}
    st.Tracker:OpenFilterMenu(owner)
    local m = st.menus[1]
    ok(m and m.owner == owner, "it opens on the button clicked")
    ok(m and texts(m) == "[title]<Filters> | [check]<Show only quests in current zone>+ | [divider]nil | "
       .. "[check]<Normal quests>+ | [check]<Daily quests>+ | [check]<Weekly quests>- | [check]<Scheduled quests>+ | "
       .. "[check]<Campaign quests>+ | [check]<World Quests>+ | [check]<Bonus Objectives>+ | [divider]nil | "
       .. "<Reset filters to defaults>", "reading: " .. (m and texts(m) or "none"))
    local good, why = validRows(m)
    ok(good, "every row is one the library accepts: " .. tostring(why))
end)

case("on Classic only the categories a provider can produce are offered", function()
    load({ tags = { daily = true, weekly = true } })
    st.Tracker:OpenFilterMenu({})
    local m = st.menus[1]
    ok(m and texts(m) == "[title]<Filters> | [check]<Show only quests in current zone>- | [divider]nil | "
       .. "[check]<Normal quests>+ | [check]<Daily quests>+ | [check]<Weekly quests>+ | [divider]nil | "
       .. "<Reset filters to defaults>", "reading: " .. (m and texts(m) or "none"))
end)

case("ticking a row stores it, redraws, repaints the funnel and refreshes the Tracker tab", function()
    load()
    local T = st.Tracker
    local b = newIcon()
    T.frame = frameWith(b)
    T:OpenFilterMenu({})
    local m = st.menus[1]
    m.items[2].onClick(true)
    ok(st.cfg.filters.onlyCurrentZone == true, "the zone row stores its new state")
    ok(st.renders == 1, "the tracker redraws once: " .. st.renders)
    ok(st.refreshed[1] == "tracker" and #st.refreshed == 1, "the Tracker tab is refreshed if it is on screen")
    ok(isGold(b.icon.vertex), "and the funnel turns gold at once")
    m.items[2].onClick(false)
    ok(st.cfg.filters.onlyCurrentZone == false and isWhite(b.icon.vertex), "unticked, stored off and white again")
    local weekly
    for _, it in ipairs(m.items) do if it.text == "<Weekly quests>" then weekly = it end end
    weekly.onClick(false)
    ok(st.cfg.filters.showWeekly == false and isGold(b.icon.vertex), "a category row stores into its own key")
    for k, v in pairs(st.cfg.filters) do
        if k ~= "showWeekly" and k ~= "onlyCurrentZone" and k ~= "campaignAnyZone" then
            ok(v == true, k .. " is left alone by the Weekly row")
        end
    end
end)

case("Reset puts every filter back through the same reset the card uses", function()
    load()
    local T = st.Tracker
    local b = newIcon()
    T.frame = frameWith(b)
    local f = st.cfg.filters
    f.onlyCurrentZone, f.campaignAnyZone = true, true
    -- Every category off, the first and the last included, so a reset that stops short shows.
    for _, c in ipairs(st.modules.Filter.CATEGORIES) do f[c.key] = false end
    -- Settings outside the filters, which Reset filters must leave as the player set them.
    st.cfg.showOnlyWatched, st.cfg.sortMode = true, "level"
    local before = {}
    for k, v in pairs(st.cfg) do if k ~= "filters" then before[k] = v end end
    T:PaintFilterButton()
    T:OpenFilterMenu({})
    local m = st.menus[1]
    m.items[#m.items].onClick()
    ok(f.onlyCurrentZone == false and f.campaignAnyZone == false, "the zone filter off, Always show campaign quests off")
    for _, c in ipairs(st.modules.Filter.CATEGORIES) do
        ok(f[c.key] == true, c.key .. " back on")
    end
    for k, v in pairs(st.cfg) do
        if k ~= "filters" then ok(before[k] == v, "Reset filters left " .. k .. " alone: " .. tostring(v)) end
    end
    for k in pairs(before) do ok(st.cfg[k] ~= nil, "Reset filters did not clear " .. k) end
    ok(st.renders == 1 and st.refreshed[1] == "tracker", "redrawn and the tab refreshed")
    ok(isWhite(b.icon.vertex), "and the funnel is white again")
end)

case("with no menu library, no filter order or no profile, the click does nothing", function()
    load({ noUI = true })
    ok(pcall(st.Tracker.OpenFilterMenu, st.Tracker, {}) and #st.menus == 0, "no library")
    load({ noOrder = true })
    ok(pcall(st.Tracker.OpenFilterMenu, st.Tracker, {}) and #st.menus == 0, "no filter order")
    load({ cfg = {} })
    ok(pcall(st.Tracker.OpenFilterMenu, st.Tracker, {}) and #st.menus == 0, "no filters table")
    load({ noRegistry = true })
    ok(pcall(st.Tracker.OpenFilterMenu, st.Tracker, {}) and #st.menus == 0, "no registry")
end)

-- ---------------------------------------------------------------------------- the header pass

case("the header pass shows the funnel only while switched on, beside the sort button", function()
    load()
    local T = st.Tracker
    local b = newIcon()
    T.frame = frameWith(b)
    T:ApplyHeaderIcons()
    ok(b.shown == false, "unset: hidden, so it ships off")
    st.cfg.showFilterButton = true
    T:ApplyHeaderIcons()
    ok(b.shown == true, "on: shown")
    local p = b.points[1]
    ok(#b.points == 1 and p[1] == "TOPLEFT" and p[2] == T.frame and p[3] == "TOPLEFT" and p[4] == 4 and p[5] == -1,
       "sort button off: at the top-left, 4 in and 1 down, like the sort button")
    st.cfg.showSortButton = true
    T:ApplyHeaderIcons()
    ok(#b.points == 1 and b.points[1][4] == 20, "sort button on: just past it at 20: " .. tostring(b.points[1] and b.points[1][4]))
    st.cfg.showFilterButton = 1
    T:ApplyHeaderIcons()
    ok(b.shown == false, "only a real true shows it")
    st.cfg.showFilterButton = true
    st.cfg.filters.showBonus = false
    T:ApplyHeaderIcons()
    ok(isGold(b.icon.vertex), "and the pass paints it")
    T.frame = frameWith(nil)
    ok(pcall(T.ApplyHeaderIcons, T), "a frame built without one is passed over")
end)

-- --------------------------------------------------------------------------------- the build

case("BuildFrame makes the funnel with its texture, tooltip and menu, and keeps it", function()
    load()
    local made = {}
    local f = {}
    st.build(f, function(parent, texture, tooltip, onClick, anchor)
        local b = { parent = parent, texture = texture, tooltip = tooltip, onClick = onClick, anchor = anchor }
        made[#made + 1] = b
        return b
    end)
    local b = made[1]
    ok(#made == 1 and b.parent == f, "one icon, on the tracker")
    ok(b.texture == "Interface\\AddOns\\EQObjectiveTracker\\Media\\Textures\\filter.tga", "the funnel texture: " .. tostring(b.texture))
    ok(b.tooltip == "<Filters>", "the Filters card's own title as its tooltip")
    ok(b.anchor == "ANCHOR_BOTTOMRIGHT", "its tooltip opens to the right, as the sort button's does")
    ok(f.filterButton == b, "kept on the frame for the header pass")
    local got
    st.Tracker.OpenFilterMenu = function(self, owner) got = { self = self, owner = owner } end
    b.onClick(b)
    ok(got and got.self == st.Tracker and got.owner == b, "a click opens the menu on the button")
end)

-- ------------------------------------------------------------------------------- the wiring

do
    local code = stripComments(trackerSrc)
    ok(count(code, "    f._eqotPendingRender = nil\n    self:PaintFilterButton()\n    local content = f.content\n") == 1,
       "every render that lays out repaints the funnel, so the Filters card's boxes reach it")
    ok(count(code, "    tex:SetAlpha(0.85)\n    b.icon = tex\n") == 1, "the icon helper keeps its texture on the button")
    ok(count(code, "local GOLD_R, GOLD_G, GOLD_B = 0.92, 0.72, 0.02\n") == 1, "EQOT gold is 0.92, 0.72, 0.02")
    ok(count(code, "local HEADER_ICON_SZ   = 13\n") == 1, "the header icons are 13 px")
    local tab = stripComments(tabSrc)
    ok(count(tab, "            function()\n                Options:ResetFilters()\n                local f = DB().filters\n") == 1,
       "the card's Reset button resets through the same function the menu uses")
    ok(count(tab, "Options.FILTER_ORDER = FILTER_ORDER\n") == 1, "the card's order is the one the menu reads")
end

-- The funnel is uncompressed, unlike the cogwheel and the sort icon: 24 by 24 at 32 bits, so its
-- header plus 2304 bytes of pixels.
do
    local fh = io.open(repoFile("Media/Textures/filter.tga"), "rb")
    ok(fh ~= nil, "Media/Textures/filter.tga is on disk")
    if fh then
        local data = fh:read("*a")
        fh:close()
        ok(#data == 18 + 24 * 24 * 4, "its whole image is there: " .. #data .. " bytes")
        local want = { 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 24, 0, 24, 0, 32, 8 }
        local same = true
        for i = 1, 18 do if data:byte(i) ~= want[i] then same = false end end
        ok(same, "an uncompressed 24 by 24 image at 32 bits, 8 of them alpha, its rows from the bottom up")
        -- White wherever it is drawn, so the gold vertex color tints it whole.
        local opaque, clear, partial, colored = 0, 0, 0, 0
        local rowOpaque = {}
        for p = 0, 24 * 24 - 1 do
            local o = 18 + p * 4
            local b, g, r, a = data:byte(o + 1, o + 4)
            if a == 255 then opaque = opaque + 1 elseif a == 0 then clear = clear + 1 else partial = partial + 1 end
            if a > 0 and (r ~= 255 or g ~= 255 or b ~= 255) then colored = colored + 1 end
            local row = math.floor(p / 24) + 1
            if a > 0 then rowOpaque[row] = (rowOpaque[row] or 0) + 1 end
        end
        ok(opaque == 114 and clear == 434 and partial == 28,
           ("the funnel's own pixels: %d solid, %d clear, %d edge"):format(opaque, clear, partial))
        ok(colored == 0, "every drawn pixel white: " .. colored)
        local bottom, top = 0, 0
        for row = 1, 6 do bottom = bottom + (rowOpaque[row] or 0) end
        for row = 19, 24 do top = top + (rowOpaque[row] or 0) end
        ok(top > bottom, ("wide end up: the top rows draw %d pixels, the bottom %d"):format(top, bottom))
    end
end

print(("test_filter_button: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
