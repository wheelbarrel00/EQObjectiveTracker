-- Unit tests for the tracker's sort button, run against the SHIPPED source rather than a copy. Run
-- from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_sort_button.lua
--
-- WHAT THE FEATURE IS. A small button at the tracker's top-left, off by default ("Show the sort
-- button on the tracker" on the Tracker tab), whose click opens a menu of the eight sort orders
-- under a title naming the current one. A pick stores the same Sort Order the Tracker tab's
-- dropdown does, redraws the tracker, and views the Tracker tab again if it is the one on screen.
-- Requested by Andreon on CurseForge (2026-10-10), who asked to switch between level and
-- distance. The author asked for every order.
--
-- WHAT IS HELD HERE. UI/Tracker.lua's header icon helper (now taking a tooltip read on each hover,
-- an anchor, and handing its handler the button), SortLine and OpenSortMenu, sliced together and
-- driven over the REAL list Options/TabTracker.lua builds, with the menu's items checked against
-- the vendored library's own field list. The slice runs before the Options module exists, as the
-- five TOCs (checked here) load it, so a list or module captured at load comes back nil. The header
-- pass's show and hide, sliced and driven. Options:RefreshIfShown, sliced from Options/Frame.lua and
-- driven. Core/API.lua's AddHeaderIcon, sliced and driven, for the tooltip it keeps. The button's
-- build in BuildFrame, its default and its texture, by comment-stripped whole statement and by the
-- file's own header bytes. The Tracker tab's box is test_tracker_tab.lua's.
--
-- Every lookup in the locale table reads "<key>", so a hard-coded English string cannot pass for
-- a translated one. The DB module is Core/DB.lua's own accessors, sliced, so a call written with a
-- dot raises as it does in game.
--
-- OUT OF SCOPE BY CONSTRUCTION: how the menu draws (the library's tests), and what each sort order
-- does to the list (Data/Sort.lua).

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
end

local function readFile(rel)
    local fh = assert(io.open(repoFile(rel), "rb"))
    local src = fh:read("*a"):gsub("\r\n", "\n")
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

local function K(key) return "<" .. key .. ">" end

local function only(src, anchor, rel)
    local at, n, from = nil, 0, 1
    while true do
        local i = src:find(anchor, from, true)
        if not i then break end
        at, n, from = at or i, n + 1, i + 1
    end
    assert(n == 1, ("anchor matched %d times in %s (need exactly 1): %s"):format(n, rel, anchor))
    return at
end

local function slice(rel, fromAnchor, toAnchor)
    local src = readFile(rel)
    local from, to = only(src, fromAnchor, rel), only(src, toAnchor, rel)
    assert(to > from, "anchors are out of order in " .. rel)
    return src:sub(from, to - 1)
end

-- From a function's head to the end that closes it, the first "\nend\n" after the head.
local function sliceFunction(rel, head)
    local src = readFile(rel)
    local a = only(src, head, rel)
    local b = src:find("\nend\n", a, true)
    assert(b, "no end after " .. head)
    return src:sub(a, b + 4)
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

-- Core/DB.lua's accessors, sliced once. Each reads through self, so a dot call raises.
local accessors
local function realDB(db)
    if not accessors then
        accessors = {}
        for _, name in ipairs({ "Tracker", "Char" }) do
            local holder = {}
            local chunk = assert(loadstring(sliceFunction("Core/DB.lua", "\nfunction DB:" .. name .. "()\n"),
                                            "DB:" .. name))
            setfenv(chunk, { DB = holder })
            chunk()
            accessors[name] = holder[name]
        end
    end
    local out = { db = db }
    for name, fn in pairs(accessors) do out[name] = fn end
    return out
end

-- The REAL list, from Options/TabTracker.lua loaded over a stub that only takes its registration.
local function realSortOptions()
    local holder = { RegisterTab = function() end }
    local ns = { L = setmetatable({}, { __index = function(_, k) return K(k) end }), Has = {} }
    function ns:GetModule(name)
        if name == "Options" then return holder end
        return nil
    end
    assert(loadfile(repoFile("Options/TabTracker.lua")))("EQObjectiveTracker", ns)
    return holder.SORT_OPTIONS
end

local SORT = realSortOptions()
local WANT = { "zone", "title", "status", "type", "level", "distance", "recent", "manual" }

-- The vendored library's own field list, which ShowMenu checks every item against: an item with
-- any other field raises, which in game is a Lua error on every click of the button.
local menuSrc = readFile("Libs/EverythingUI/Menu.lua")
local ITEM_FIELDS = assert(loadstring("return " .. assert(menuSrc:match("local ITEM_FIELDS = (%b{})"))))()
local KINDS = assert(loadstring("return " .. assert(menuSrc:match("local KINDS = (%b{})"))))()

-- ------------------------------------------------------------------------------- the rig

local function newTip()
    local tip = { lines = {}, owners = {}, shows = 0, hides = 0 }
    function tip:SetOwner(owner, anchor) self.owners[#self.owners + 1] = { owner, anchor } end
    function tip:AddLine(s) self.lines[#self.lines + 1] = s end
    function tip:Show() self.shows = self.shows + 1 end
    function tip:Hide() self.hides = self.hides + 1 end
    return tip
end

local function newButton(kind, parent)
    local b = { kind = kind, parent = parent, scripts = {}, shown = true }
    function b:SetSize(w, h) self.w, self.h = w, h end
    function b:SetFrameLevel(l) self.level = l end
    function b:CreateTexture(name, layer)
        local t = { name = name, layer = layer }
        function t.SetAllPoints(tx) tx.all = true end
        function t.SetTexture(tx, p) tx.path = p end
        function t.SetAlpha(tx, a) tx.alpha = a end
        self.tex = t
        return t
    end
    function b:SetScript(e, fn) self.scripts[e] = fn end
    function b:SetShown(v) self.shown = v and true or false end
    function b:Show() self.shown = true end
    function b:Hide() self.shown = false end
    return b
end

-- o.cfg the saved tracker settings (nil for a profile not loaded), o.options what the Options
-- module carries (false for no module at all), o.clickThrough the tracker's click-through state.
local function rig(o)
    o = o or {}
    local st = { renders = {}, refreshed = {}, menus = {}, seq = {}, tip = newTip(), made = {} }
    st.cfg = o.cfg
    local profile = { tracker = st.cfg }
    if o.noProfile then profile = nil end
    local mods = { DB = realDB({ profile = profile }) }
    local T = {}
    function T.IsClickThrough(self)
        if self ~= T then error("Tracker:IsClickThrough called without self", 2) end
        return o.clickThrough == true
    end
    function T.Render(self)
        if self ~= T then error("Tracker:Render called without self", 2) end
        st.renders[#st.renders + 1] = st.cfg and st.cfg.sortMode
        st.seq[#st.seq + 1] = "render"
    end
    if o.options ~= false then
        local O = { SORT_OPTIONS = SORT }
        if o.options then for k, v in pairs(o.options) do O[k] = v end end
        if O.ui == nil then
            O.ui = {}
            function O.ui.ShowMenu(self, items, owner)
                if self ~= O.ui then error("ShowMenu called without self", 2) end
                st.menus[#st.menus + 1] = { items = items, owner = owner }
            end
        elseif O.ui == "none" then
            O.ui = nil
        end
        if O.SORT_OPTIONS == "none" then O.SORT_OPTIONS = nil end
        function O.RefreshIfShown(self, id)
            if self ~= O then error("Options:RefreshIfShown called without self", 2) end
            st.refreshed[#st.refreshed + 1] = id
            st.seq[#st.seq + 1] = "refresh:" .. tostring(id)
        end
        st.options = O
    end
    local ns = { Util = { Tooltip = function() return st.tip end } }
    function ns:GetModule(name) return mods[name] end
    local src = slice("UI/Tracker.lua", "local function makeHeaderIcon(f, texture, tooltip, onClick, anchor)",
                      "-- Icons registered through ns:GetModule(\"API\") are built lazily here")
        .. "\nreturn makeHeaderIcon"
    local chunk = assert(loadstring(src, "sort-button"))
    setfenv(chunk, setmetatable({
        Tracker = T, ns = ns, HEADER_ICON_SZ = 13,
        L = setmetatable({}, { __index = function(_, k) return K(k) end }),
        CreateFrame = function(kind, name, parent)
            local b = newButton(kind, parent)
            b.name = name
            st.made[#st.made + 1] = b
            return b
        end,
    }, { __index = _G }))
    st.makeHeaderIcon = chunk()
    -- Only now, as in game: UI/Tracker.lua loads before Options/Frame.lua (checked below).
    mods.Options = st.options
    st.T, st.mods = T, mods
    return st
end

local function trackerFrame()
    local f = {}
    function f:GetFrameLevel() return 5 end
    return f
end

local function label(value)
    for _, o in ipairs(SORT) do if o.value == value then return o.label end end
end

-- ------------------------------------------------------------------------------ the cases

case("the real list is the eight orders, each named through the locale table", function()
    ok(type(SORT) == "table" and #SORT == 8, "Options/TabTracker.lua hands over eight orders: " .. tostring(SORT and #SORT))
    for i, v in ipairs(WANT) do
        ok(SORT[i] and SORT[i].value == v, "order " .. i .. " is " .. v .. ": " .. tostring(SORT[i] and SORT[i].value))
        ok(SORT[i] and type(SORT[i].label) == "string" and SORT[i].label:sub(1, 1) == "<",
           v .. " is named through the locale table: " .. tostring(SORT[i] and SORT[i].label))
    end
end)

case("the icon helper builds a button above the drag handle, in the cogwheel's size and alpha", function()
    local st = rig({ cfg = {} })
    local f = trackerFrame()
    local b = st.makeHeaderIcon(f, "path/x.tga", "tip", function() end)
    ok(b.kind == "Button" and b.parent == f, "a Button on the tracker frame: " .. tostring(b.kind))
    ok(b.w == 13 and b.h == 13, "13 by 13")
    ok(b.level == 15, "ten levels above the frame, so the drag handle does not eat its click: " .. tostring(b.level))
    ok(b.tex and b.tex.layer == "ARTWORK" and b.tex.all and b.tex.path == "path/x.tga" and b.tex.alpha == 0.85,
       "its texture fills it at 85% until hovered")
end)

case("the tooltip: a string, a function read on every hover, the anchor, and nothing while click-through", function()
    local st = rig({ cfg = {} })
    local f = trackerFrame()
    local b = st.makeHeaderIcon(f, "p", "fixed", function() end)
    b.scripts.OnEnter(b)
    ok(st.tip.lines[1] == "fixed" and st.tip.owners[1][1] == b and st.tip.owners[1][2] == "ANCHOR_BOTTOMLEFT"
       and st.tip.shows == 1, "a string shows as it is, below and to the left by default")
    ok(b.tex.alpha == 1, "and lights the icon")
    b.scripts.OnLeave(b)
    ok(b.tex.alpha == 0.85 and st.tip.hides == 1, "leaving dims it and hides the tooltip")

    local n = 0
    local live = st.makeHeaderIcon(f, "p", function() n = n + 1; return "read " .. n end, function() end,
                                   "ANCHOR_BOTTOMRIGHT")
    live.scripts.OnEnter(live)
    live.scripts.OnEnter(live)
    ok(st.tip.lines[2] == "read 1" and st.tip.lines[3] == "read 2", "a function is read again on every hover: "
       .. tostring(st.tip.lines[2]) .. ", " .. tostring(st.tip.lines[3]))
    ok(st.tip.owners[2][2] == "ANCHOR_BOTTOMRIGHT", "and the anchor given is the one used")

    local quiet = st.makeHeaderIcon(f, "p", function() return nil end, function() end)
    quiet.scripts.OnEnter(quiet)
    ok(#st.tip.owners == 3 and quiet.tex.alpha == 1, "a function answering nothing shows no tooltip, the icon still lit")
    local none = st.makeHeaderIcon(f, "p", nil, function() end)
    none.scripts.OnEnter(none)
    ok(#st.tip.owners == 3, "and neither does no tooltip at all")

    local ct = rig({ cfg = {}, clickThrough = true })
    local hidden = ct.makeHeaderIcon(f, "p", "fixed", function() end)
    hidden.scripts.OnEnter(hidden)
    ok(#ct.tip.owners == 0 and hidden.tex.alpha == 0.85, "while click-through, a hover does nothing at all")
end)

case("a click hands the button to its handler, and never while click-through", function()
    local st = rig({ cfg = {} })
    local got, calls = nil, 0
    local b = st.makeHeaderIcon(trackerFrame(), "p", "t", function(btn) got, calls = btn, calls + 1 end)
    b.scripts.OnClick(b, "LeftButton")
    ok(calls == 1 and got == b, "the handler gets the button it was clicked on")
    local ct = rig({ cfg = {}, clickThrough = true })
    local n = 0
    local hb = ct.makeHeaderIcon(trackerFrame(), "p", "t", function() n = n + 1 end)
    hb.scripts.OnClick(hb, "LeftButton")
    ok(n == 0, "a click-through tracker never runs it")
end)

case("SortLine names the stored order in the dropdown's own words", function()
    for _, v in ipairs(WANT) do
        local st = rig({ cfg = { sortMode = v } })
        ok(st.T:SortLine() == K"Sort Order: %s":format(label(v)), v .. ": " .. st.T:SortLine())
    end
    local st = rig({ cfg = {} })
    ok(st.T:SortLine() == K"Sort Order: %s":format(label("zone")), "unset reads as Zone, the default: " .. st.T:SortLine())
    st = rig({ cfg = { sortMode = "bogus" } })
    ok(st.T:SortLine() == K"Sort Order: %s":format("bogus"), "an order no list names prints as stored: " .. st.T:SortLine())
    st = rig({ cfg = { sortMode = "distance" }, options = false })
    ok(st.T:SortLine() == K"Sort Order: %s":format("distance"), "with no Options module too: " .. st.T:SortLine())
    st = rig({ noProfile = true })
    ok(st.T:SortLine() == K"Sort Order: %s":format(label("zone")), "a profile not loaded yet reads as Zone: " .. st.T:SortLine())
end)

case("the menu lists every order under a title naming the current one", function()
    local st = rig({ cfg = { sortMode = "distance" } })
    local owner = {}
    st.T:OpenSortMenu(owner)
    ok(#st.menus == 1, "one menu is opened: " .. #st.menus)
    local m = st.menus[1]
    if not m then return end
    ok(m.owner == owner, "owned by the button, so it closes with the tracker")
    ok(#m.items == 9, "a title and eight orders: " .. #m.items)
    ok(m.items[1].kind == "title" and m.items[1].text == K"Sort Order: %s":format(label("distance")),
       "the title names the current order: " .. tostring(m.items[1].text))
    for i, v in ipairs(WANT) do
        local it = m.items[i + 1]
        ok(it and it.kind == nil and it.text == label(v) and type(it.onClick) == "function",
           "row " .. (i + 1) .. " picks " .. v .. ": " .. tostring(it and it.text))
    end
    local bad = {}
    for i, it in ipairs(m.items) do
        for k, val in pairs(it) do
            if ITEM_FIELDS[k] ~= type(val) then bad[#bad + 1] = i .. "." .. tostring(k) end
        end
        if it.kind and not KINDS[it.kind] then bad[#bad + 1] = i .. " kind " .. tostring(it.kind) end
        if it.danger then bad[#bad + 1] = i .. " danger" end
    end
    ok(#bad == 0, "every field is one the library takes, and nothing is drawn as danger: " .. table.concat(bad, ", "))
end)

case("a pick stores the order, then redraws once, then views an open Tracker tab again", function()
    for i, v in ipairs(WANT) do
        local st = rig({ cfg = { sortMode = (v == "zone") and "title" or "zone" } })
        st.T:OpenSortMenu({})
        st.menus[1].items[i + 1].onClick()
        ok(st.cfg.sortMode == v, "row " .. (i + 1) .. " stores " .. v .. ": " .. tostring(st.cfg.sortMode))
        ok(#st.renders == 1 and st.renders[1] == v, v .. ": one redraw, after the store: " .. tostring(st.renders[1]))
        ok(table.concat(st.seq, ",") == "render,refresh:tracker", v .. ": redrawn, then the Tracker tab asked to follow: "
           .. table.concat(st.seq, ","))
    end
    local st = rig({ cfg = { sortMode = "zone" } })
    st.T:OpenSortMenu({})
    st.menus[1].items[6].onClick()
    st.T:OpenSortMenu({})
    ok(st.menus[2].items[1].text == K"Sort Order: %s":format(label("level")), "opened again, the title names the pick: "
       .. tostring(st.menus[2].items[1].text))
    -- The menu outlives the render that built it, so each row reads the profile when it is clicked.
    local fresh = { sortMode = "zone" }
    local later = rig({ cfg = fresh })
    later.T:OpenSortMenu({})
    later.mods.DB.db.profile.tracker = { sortMode = "title" }
    later.cfg = later.mods.DB.db.profile.tracker
    later.menus[1].items[4].onClick()
    ok(later.cfg.sortMode == "status" and fresh.sortMode == "zone",
       "a row stores into the profile there when it is clicked, not the one there when the menu opened")
end)

case("a pick with no profile loaded writes nothing and draws nothing", function()
    local st = rig({ noProfile = true })
    st.T:OpenSortMenu({})
    ok(#st.menus == 1, "the menu still opens")
    if st.menus[1] then st.menus[1].items[2].onClick() end
    ok(#st.renders == 0 and #st.refreshed == 0, "a pick draws nothing and refreshes nothing")
end)

case("nothing is offered without the list, the library or the Options module", function()
    local st = rig({ cfg = {}, options = { SORT_OPTIONS = "none" } })
    st.T:OpenSortMenu({})
    ok(#st.menus == 0, "no list, no menu")
    st = rig({ cfg = {}, options = { ui = "none" } })
    st.T:OpenSortMenu({})
    ok(#st.menus == 0, "no library context, no menu")
    st = rig({ cfg = {}, options = false })
    local good = pcall(function() st.T:OpenSortMenu({}) end)
    ok(good and #st.menus == 0, "no Options module, no menu and no error")
end)

-- ------------------------------------------------------------- the header pass's show and hide

local applySrc = sliceFunction("UI/Tracker.lua", "function Tracker:ApplyHeaderIcons()")

local function header(cfg, noDB)
    local T, mods = {}, {}
    if not noDB then mods.DB = realDB({ profile = { tracker = cfg } }) end
    local ns = { GetModule = function(_, n) return mods[n] end }
    local chunk = assert(loadstring(applySrc, "apply-header-icons"))
    setfenv(chunk, setmetatable({ Tracker = T, ns = ns }, { __index = _G }))
    chunk()
    local function icon(key)
        local b = newButton("Button")
        b._dbKey, b.points = key, {}
        function b:ClearAllPoints() self.points = {} end
        function b:SetPoint(...) self.points[#self.points + 1] = { ... } end
        return b
    end
    local sort, cog = icon(nil), icon("showOptionsIcon")
    T.frame = { headerIcons = { cog }, sortButton = sort }
    T:ApplyHeaderIcons()
    return sort, cog
end

case("the header pass shows the sort button only while it is switched on", function()
    local sort, cog = header({})
    ok(sort.shown == false, "unset: hidden, so it ships off")
    ok(cog.shown and cog.points[1] and cog.points[1][1] == "TOPRIGHT", "the cogwheel keeps its corner")
    ok(#sort.points == 0, "and the sort button is never moved into the cogwheel's run")
    sort = header({ showSortButton = false })
    ok(sort.shown == false, "off: hidden")
    sort = header({ showSortButton = true })
    ok(sort.shown == true, "on: shown")
    sort = header({ showSortButton = 1 })
    ok(sort.shown == false, "only a real true shows it")
    sort = header(nil)
    ok(sort.shown == false, "no profile: hidden")
    sort = header({ showSortButton = true }, true)
    ok(sort.shown == false, "no DB module: hidden")
    local T = {}
    local chunk = assert(loadstring(applySrc, "apply-header-icons"))
    setfenv(chunk, setmetatable({ Tracker = T, ns = { GetModule = function()
        return realDB({ profile = { tracker = { showSortButton = true } } })
    end } }, { __index = _G }))
    chunk()
    T.frame = { headerIcons = {} }
    ok(pcall(function() T:ApplyHeaderIcons() end), "a frame built without one is passed over")
end)

-- --------------------------------------------------------------------- Options:RefreshIfShown

local refreshSrc = sliceFunction("Options/Frame.lua", "function Options:RefreshIfShown(id)")

local function refreshRig(o)
    local st = { selected = {} }
    local ui = {}
    function ui.SelectTab(self, id)
        if self ~= ui then error("SelectTab called without self", 2) end
        st.selected[#st.selected + 1] = id
    end
    local char = o.char
    local db = o.noChar and {} or { char = char or {} }
    local mods = { DB = realDB(db) }
    local ns = { GetModule = function(_, n) return mods[n] end }
    local O = {}
    if o.frame ~= nil then
        O.frame = { IsShown = function(self) return self.shownFlag end, shownFlag = o.frame }
    end
    local chunk = assert(loadstring(refreshSrc, "refresh-if-shown"))
    setfenv(chunk, setmetatable({ Options = O, ui = ui, ns = ns }, { __index = _G }))
    chunk()
    st.O = O
    return st
end

case("RefreshIfShown views a tab again only when it is the one on screen", function()
    local st = refreshRig({ frame = true, char = { lastOptionsTab = "tracker" } })
    st.O:RefreshIfShown("tracker")
    ok(#st.selected == 1 and st.selected[1] == "tracker", "shown on that tab: viewed again once")
    st = refreshRig({ frame = true, char = { lastOptionsTab = "appearance" } })
    st.O:RefreshIfShown("tracker")
    ok(#st.selected == 0, "shown on another tab: left alone, so the window never jumps tabs")
    st = refreshRig({ frame = true, char = { lastOptionsTab = "appearance" } })
    st.O:RefreshIfShown("appearance")
    ok(#st.selected == 1 and st.selected[1] == "appearance", "the tab asked for is the one viewed")
    st = refreshRig({ frame = false, char = { lastOptionsTab = "tracker" } })
    st.O:RefreshIfShown("tracker")
    ok(#st.selected == 0, "a closed window is left closed")
    st = refreshRig({ char = { lastOptionsTab = "tracker" } })
    st.O:RefreshIfShown("tracker")
    ok(#st.selected == 0, "a window never built is not built for it")
    st = refreshRig({ frame = true, noChar = true })
    ok(pcall(function() st.O:RefreshIfShown("tracker") end) and #st.selected == 0,
       "no character settings: nothing, and no error")
end)

-- ------------------------------------------------------------- the public API's header icons

-- The helper now calls a function tooltip on each hover, so the API must not pass another addon's
-- function through to it.
local apiSrc = slice("Core/API.lua", "local function slotFor(list, id)", "function API:RemoveHeaderIcon(id)")

local function register(tooltip)
    local A, rebuilt = { headerIcons = {} }, 0
    local T = {}
    function T.RebuildHeaderIcons(self)
        if self ~= T then error("Tracker:RebuildHeaderIcons called without self", 2) end
        rebuilt = rebuilt + 1
    end
    local ns = { GetModule = function(_, n) if n == "Tracker" then return T end end }
    local chunk = assert(loadstring(apiSrc, "add-header-icon"))
    setfenv(chunk, setmetatable({ API = A, ns = ns }, { __index = _G }))
    chunk()
    local added = A:AddHeaderIcon({ id = "chain", texture = "t", onClick = function() end, tooltip = tooltip })
    return added, A.headerIcons[1], rebuilt
end

case("an icon another addon registers keeps a string tooltip and drops any other", function()
    local added, spec, rebuilt = register("Chain Guide")
    ok(added == true and spec and spec.tooltip == "Chain Guide" and rebuilt == 1,
       "a string is kept as it is, and the icons are rebuilt")
    added, spec = register(function() return "live" end)
    ok(added == true and spec and spec.tooltip == nil,
       "a function is dropped and the icon still added, so a hover never calls into the other addon")
    added, spec = register(42)
    ok(added == true and spec and spec.tooltip == nil, "and so is a number")
    added, spec = register({ "a table" })
    ok(added == true and spec and spec.tooltip == nil, "a table")
    added, spec = register(true)
    ok(added == true and spec and spec.tooltip == nil, "or a boolean, none of which the hover is written to show")
    added, spec = register(nil)
    ok(added == true and spec and spec.tooltip == nil, "no tooltip stays none")
end)

-- The rig puts the Options module in place only after the slice has run, which is true only while
-- every TOC loads UI/Tracker.lua first.
for _, toc in ipairs({ "EQObjectiveTracker.toc", "EQObjectiveTracker_Mainline.toc", "EQObjectiveTracker_Camelot.toc",
                       "EQObjectiveTracker_TBC.toc", "EQObjectiveTracker_Vanilla.toc" }) do
    local lines = readFile(toc)
    local trackerAt = lines:find("\nUI\\Tracker.lua\n", 1, true)
    local frameAt = lines:find("\nOptions\\Frame.lua\n", 1, true)
    local tabAt = lines:find("\nOptions\\TabTracker.lua\n", 1, true)
    ok(trackerAt and frameAt and tabAt and trackerAt < frameAt and trackerAt < tabAt,
       toc .. " loads UI/Tracker.lua before Options/Frame.lua and Options/TabTracker.lua")
end

-- ------------------------------------------------------------------ the build, by statement

local tracker = stripComments(readFile("UI/Tracker.lua"))
local function has(src, stmt, msg) ok(count(src, stmt) == 1, msg .. " (" .. count(src, stmt) .. ")") end

has(tracker, [[    local sort = makeHeaderIcon(f, "Interface\\AddOns\\EQObjectiveTracker\\Media\\Textures\\sort.tga",
        function() return Tracker:SortLine() end, function(b) Tracker:OpenSortMenu(b) end,
        "ANCHOR_BOTTOMRIGHT")
    sort:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -1)
    f.sortButton = sort
    self:RebuildHeaderIcons()]],
    "BuildFrame makes the button with its texture, live tooltip and menu, at the top-left, before the first header pass")
-- With the comments gone their lines are blank, so blank lines are dropped before reading what
-- follows what.
local tight = tracker:gsub("\n[ \t]*\n", "\n"):gsub("\n[ \t]*\n", "\n")
has(tight, [[    f.headerIcons = { cog }
    local sort = makeHeaderIcon(]], "beside the cogwheel, which alone heads the right-hand run")
ok(count(tracker, "sortButton") == 3, "the button is stored once and read only by the header pass: "
   .. count(tracker, "sortButton"))
has(tracker, "    self:ApplyHeaderIcons()\n    self:Render()\nend", "OnEnable runs the header pass before the first render")

local db = readFile("Core/DB.lua")
local defaults = stripComments(db:sub(1, db:find("local APPEARANCE_KEYS", 1, true)))
local _, sets = defaults:gsub("showSortButton%s*=", "")
ok(sets == 1 and defaults:find("\n%s*showSortButton%s*=%s*false,") ~= nil, "it ships off, with one default")
local resetKeys = stripComments(db:match("local APPEARANCE_KEYS = %b{}") or "")
ok(count(resetKeys, "showSortButton") == 0, "the Appearance reset leaves it alone, since it is a Tracker tab switch")

local tex = io.open(repoFile("Media/Textures/sort.tga"), "rb")
ok(tex ~= nil, "Media/Textures/sort.tga is on disk")
if tex then
    local head = tex:read(18)
    tex:close()
    local cog = io.open(repoFile("Media/Textures/cogwheel.tga"), "rb")
    local cogHead = cog and cog:read(18)
    if cog then cog:close() end
    ok(head and #head == 18 and head == cogHead, "with the cogwheel's own header: 24 by 24, 32 bits, run-length")
    ok(head and head:byte(13) == 24 and head:byte(15) == 24 and head:byte(17) == 32,
       "read as 24 by 24 at 32 bits")
end

print(("test_sort_button: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
