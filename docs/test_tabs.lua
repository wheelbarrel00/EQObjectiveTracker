-- Unit tests for the tracker's section tabs, run against the SHIPPED source. Run from the repo root
-- with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_tabs.lua
--
-- WHY THIS FILE EXISTS. bramer26 asked on CurseForge (2026-10-15) for separate tracker windows "maybe
-- with the addition of tabs" so the one tracker is not cluttered. The author chose tabs first:
-- off by default, each section given a tab from 1 to 3 on the Section Order card, a strip under
-- the drag strip that switches between them, the choice kept per character. The scenario panel
-- shows on every tab, and the strip shows only once two tabs hold a section, so switching tabs on
-- with nothing moved changes nothing on screen.
--
-- What is run: UI/Tracker.lua from SectionTab to RebuildHeaderIcons (every tab method and the
-- strip's file-local helpers), ApplyContentInset, TabsLine, Render's own lines from the ActiveTab
-- read up to the section loop, the head of _RenderPinnedWorldQuests through its tab guard, and
-- BuildFrame's own build of the strip, all over the REAL UI/Sections.lua. Stub frames answer only
-- the methods their widget type has.
--
-- OUT OF SCOPE BY CONSTRUCTION: what the strip looks like in game, the Section Order card's
-- controls (docs/test_tracker_tab.lua), the Tracker.MAX_TABS those controls read
-- (docs/test_preview.lua), and the rest of the render, which no harness runs whole.

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

local function between(src, a, b)
    local i, j = only(src, a), only(src, b)
    assert(j > i, "anchors out of order: " .. a)
    return src:sub(i, j - 1)
end

local function throughEnd(src, a)
    local i = only(src, a)
    local j = src:find("\nend\n", i, true)
    return src:sub(i, j + 4)
end

local function stripComments(src)
    local out = {}
    for line in (src .. "\n"):gmatch("(.-)\n") do
        if not line:match("^%s*%-%-") then out[#out + 1] = (line:gsub("%s+%-%-[^\"]*$", "")) end
    end
    return table.concat(out, "\n")
end

local trackerSrc = readFile("UI/Tracker.lua")
local tabsSrc  = between(trackerSrc, "function Tracker:SectionTab(groupID)\n", "function Tracker:RebuildHeaderIcons()\n")
local insetSrc = throughEnd(trackerSrc, "function Tracker:ApplyContentInset()\n")
local lineSrc  = throughEnd(trackerSrc, "function Tracker:TabsLine()\n")
local stripSrc = between(trackerSrc, '    local tabStrip = CreateFrame("Frame", nil, f)\n',
                         '    local eventsRegion = CreateFrame("Frame", nil, f)\n')
local LOOP_LINE = "    for _, groupID in ipairs(self:_OrderOnTab(Sections:Order(), activeTab)) do\n"
-- Render's lines from the ActiveTab read up to the section loop, run as they stand.
local prologueSrc = between(trackerSrc, "    local activeTab = self:ActiveTab()\n", "    for _, groupID in ipairs(")
-- The pinned World Quests region's head, through the guard that collapses it on another tab.
local pinnedSrc = between(trackerSrc, "function Tracker:_RenderPinnedWorldQuests(group, cap, width, cfg)\n",
                          "    region:Show()\n\n    local collapsed = Sections:IsCollapsed(PINNED_GROUP)\n")

-- ------------------------------------------------------------------- typed widget stubs

local FRAME, TEXTURE, FONTSTRING = {}, {}, {}

local function region(methods, kind, parent)
    return setmetatable({ kind = kind, parent = parent, points = {}, scripts = {}, shown = true }, { __index = methods })
end

local function newFrame(kind, parent)
    local fr = region(FRAME, kind, parent)
    fr.textures = {}
    return fr
end

function FRAME:SetPoint(...) self.points[#self.points + 1] = { ... } end
function FRAME:ClearAllPoints() self.points = {} end
function FRAME:SetHeight(h) self.height = h end
function FRAME:SetWidth(w) self.width = w end
function FRAME:GetWidth() return self.width or 0 end
function FRAME:SetScript(name, fn) self.scripts[name] = fn end
function FRAME:Show() self.shown = true end
function FRAME:Hide() self.shown = false end
function FRAME:SetShown(v) self.shown = v and true or false end
function FRAME:IsShown() return self.shown end
function FRAME:CreateTexture(_, layer)
    local t = region(TEXTURE, "Texture", self)
    t.layer = layer
    self.textures[#self.textures + 1] = t
    return t
end
function FRAME:CreateFontString(_, layer, template)
    local s = region(FONTSTRING, "FontString", self)
    s.layer, s.template = layer, template
    self.font = s
    return s
end

local SCROLL = setmetatable({}, { __index = FRAME })
function SCROLL:SetVerticalScroll(v) self.vscroll = v self.vsets = (self.vsets or 0) + 1 end

function TEXTURE:SetAllPoints() self.all = true end
function TEXTURE:SetPoint(...) self.points[#self.points + 1] = { ... } end
function TEXTURE:SetHeight(h) self.height = h end
function TEXTURE:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end

function FONTSTRING:SetPoint(...) self.points[#self.points + 1] = { ... } end
function FONTSTRING:SetText(s) self.text = s self.sets = (self.sets or 0) + 1 end
function FONTSTRING:SetWordWrap(v) self.wrap = v end
function FONTSTRING:SetTextColor(r, g, b) self.color = { r, g, b } end

-- --------------------------------------------------------------------------------- the world

local st

local function load(o)
    o = o or {}
    st = { renders = 0, deferred = 0, tips = {} }
    local cfg = o.cfg or {}
    local char
    if not o.noChar then char = o.char or {} end
    st.cfg, st.char = cfg, char
    local L = setmetatable({}, { __index = function(_, k) return "<" .. k .. ">" end })
    local modules = {}
    local ns = { L = L }
    function ns:RegisterModule(name, m) modules[name] = m return m end
    function ns:GetModule(name) return modules[name] end
    local db = {}
    function db.Tracker(self) assert(self == db, "DB:Tracker without self") return cfg end
    function db.Char(self) assert(self == db, "DB:Char without self") return char end
    modules.DB = db
    local groups = o.groups or { "campaign", "quests", "achievements", "worldquests", "scenarios" }
    modules.Registry = { Groups = function() return groups end }
    st.locked = false
    modules.Events = { RunWhenOutOfCombat = function(_, key, fn)
        st.deferred = st.deferred + 1
        st.deferKey, st.deferFn = key, fn
    end }
    st.docked, st.zoneHides = o.docked, 0
    local zoneBar = {}
    function zoneBar.IsDocked(self) assert(self == zoneBar, "IsDocked without self") return st.docked == true end
    function zoneBar.HideDocked(self) assert(self == zoneBar, "HideDocked without self") st.zoneHides = st.zoneHides + 1 end
    modules.ZoneProgressBar = zoneBar
    local tip = {}
    function tip:SetOwner(owner, anchor) st.tips[#st.tips + 1] = { owner = owner, anchor = anchor } end
    function tip:SetText(s, r, g, b, a) st.tips[#st.tips].text, st.tips[#st.tips].color = s, { r, g, b, a } end
    function tip:Show() st.tips[#st.tips].shown = true end
    function tip:Hide() st.tipHides = (st.tipHides or 0) + 1 end
    ns.Util = { Tooltip = function() return tip end }

    local sChunk = assert(loadfile(repoFile("UI/Sections.lua")))
    setfenv(sChunk, setmetatable({}, { __index = _G }))
    sChunk("EQObjectiveTracker", ns)

    local Tracker = { clickThrough = false }
    function Tracker.Render(self) assert(self == Tracker, "Render without self") st.renders = st.renders + 1 end
    function Tracker.IsClickThrough(self) return self.clickThrough end
    st.Tracker, st.Sections, st.modules = Tracker, modules.Sections, modules

    local env = setmetatable({
        Tracker = Tracker, ns = ns, L = L,
        DRAG_HANDLE_H = 14, TAB_STRIP_H = 18, MAX_TABS = 3, CONTENT_PAD = 4,
        GOLD_R = 0.92, GOLD_G = 0.72, GOLD_B = 0.02,
        CreateFrame = function(kind, _, parent) return newFrame(kind, parent) end,
        secureLocked = function() return st.locked end,
        scrollGutter = function() return 26 end,
        applyContentInsetWhenSafe = function() end,
        wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
    }, { __index = _G })
    env.PINNED_GROUP = "worldquests"
    env.headerBand = function() return 20 end
    env.setRegionHeight = function(r, h) r.height = h end
    local chunk = assert(loadstring(tabsSrc .. insetSrc .. lineSrc .. pinnedSrc .. "    return \"drawn\"\nend\n"
        .. "\nreturn function(f)\n" .. stripSrc .. "\nend, function(self, f)\n" .. prologueSrc
        .. "\nreturn activeTab\nend", "tabs-slice"))
    setfenv(chunk, env)
    st.buildStrip, st.prologue = chunk()
    local f = newFrame("Frame")
    f.width = 304
    f.scenarioContainer = newFrame("Frame", f)
    f.scroll = region(SCROLL, "ScrollFrame", f)
    st.buildStrip(f)
    Tracker.frame = f
    st.f = f
    return st
end

-- The label a tab should carry, worked out here from the real section titles rather than read
-- back from the code under test: no scenario panel, no hidden section, and no zone bar unless docked.
local function labelFor(tab)
    local out = {}
    for _, id in ipairs(st.Sections:Known()) do
        local hidden = st.cfg.sectionsHidden and st.cfg.sectionsHidden[id]
        local floating = id == "zoneprogress" and st.docked ~= true
        if id ~= "scenarios" and not hidden and not floating and st.Tracker:SectionTab(id) == tab then
            out[#out + 1] = st.Sections:Title(id)
        end
    end
    return table.concat(out, ", ")
end

-- ---------------------------------------------------------------------------------- SectionTab

case("a section's tab is 1 unless it was moved to 2 or 3", function()
    load({ cfg = { sectionTab = { quests = 2, campaign = 3, achievements = 4, bonusobjectives = 0, worldquests = "2",
                                  zoneprogress = 2.5 } } })
    local T = st.Tracker
    ok(T:SectionTab("quests") == 2 and T:SectionTab("campaign") == 3, "a stored 2 or 3 is read")
    ok(T:SectionTab("achievements") == 1, "past 3 reads as 1")
    ok(T:SectionTab("bonusobjectives") == 1, "below 1 reads as 1")
    ok(T:SectionTab("worldquests") == 2, "a number saved as text still reads")
    ok(T:SectionTab("zoneprogress") == 2, "a fraction rounds down")
    ok(T:SectionTab("profession") == 1, "never moved: 1")
    load({ cfg = {} })
    ok(st.Tracker:SectionTab("quests") == 1, "no map at all: 1")
end)

-- ------------------------------------------------------------------------- TabsInUse, ActiveTab

case("the tabs count only while switched on and two of them hold a section", function()
    load({ cfg = { sectionTab = { quests = 2 } } })
    local T = st.Tracker
    ok(T:TabsInUse() == nil and T:ActiveTab() == nil, "off by default: no tabs, whatever is moved")
    st.cfg.showTabs = 1
    ok(T:TabsInUse() == nil, "only a real true turns them on")
    st.cfg.showTabs = true
    local used = T:TabsInUse()
    ok(used and used[1] == true and used[2] == true and used[3] == false, "on, with sections on 1 and 2")
    st.cfg.sectionTab = {}
    ok(T:TabsInUse() == nil, "on, with every section on one tab: no strip")
    st.cfg.sectionTab = { scenarios = 2 }
    ok(T:TabsInUse() == nil, "the scenario panel is on every tab, so it never makes a tab of its own")
    st.cfg.sectionTab = { worldquests = 3 }
    used = T:TabsInUse()
    ok(used and used[1] and used[3] and not used[2], "World Quests count, from their own panel")
    st.cfg.sectionTab = { campaign = 2, quests = 2, achievements = 2, worldquests = 2, zoneprogress = 2 }
    ok(T:TabsInUse() == nil, "every section moved to one tab: still one tab")
end)

case("on a client with one quest section, tabs saved on in a profile make no strip", function()
    -- Era and TBC: the classic quests provider's one group, with the zone bar docked.
    load({ cfg = { showTabs = true, sectionTab = { quests = 2 } }, groups = { "quests" }, docked = true })
    local T = st.Tracker
    ok(T:TabsOffered() == false, "Zone Progress and Quests alone: tabs are not offered")
    ok(T:TabsInUse() == nil and T:ActiveTab() == nil, "so a profile with tabs on still shows no strip")
    ok(T:TabsLine() == "tabs: on, not offered on this client", "and the status line says why: " .. T:TabsLine())
    st.cfg.showTabs = nil
    ok(T:TabsLine() == "tabs: off", "and with tabs off there, simply off: " .. T:TabsLine())
    load({ cfg = { showTabs = true, sectionTab = { quests = 2 } }, groups = { "quests", "scenarios" } })
    ok(st.Tracker:TabsOffered() == false, "the scenario panel is not a second section")
    load({ cfg = { showTabs = true, sectionTab = { quests = 2 } }, groups = { "campaign", "quests" } })
    ok(st.Tracker:TabsOffered() == true and st.Tracker:TabsInUse() ~= nil, "Campaign and Quests: offered, and in use")
end)

case("a section's tab draws only while the section does", function()
    load({ cfg = { showTabs = true } })
    local T = st.Tracker
    ok(T:DrawsOnTab("quests") == true, "an ordinary section draws")
    ok(T:DrawsOnTab("scenarios") == false, "the scenario panel is on every tab, so takes none")
    ok(T:DrawsOnTab("zoneprogress") == false, "the zone bar left undocked: none")
    st.docked = true
    ok(T:DrawsOnTab("zoneprogress") == true, "docked: it does")
    st.cfg.sectionsHidden = { quests = true }
    ok(T:DrawsOnTab("quests") == false, "a hidden section: none")
    st.cfg.sectionsHidden = { worldquests = true }
    ok(T:DrawsOnTab("worldquests") == false, "World Quests hidden from their own panel: none")
    st.cfg.sectionTab = { worldquests = 3 }
    ok(T:TabsInUse() == nil, "so moving them alone to tab 3 makes no tab named after them")
    st.cfg.sectionTab = { worldquests = 3, quests = 2 }
    local used = T:TabsInUse()
    ok(used and used[1] and used[2] and not used[3], "with Quests on tab 2: tabs 1 and 2, still no tab 3")
end)

case("the tab on screen is kept per character and falls back to one in use", function()
    load({ cfg = { showTabs = true, sectionTab = { quests = 2, achievements = 3 } } })
    local T = st.Tracker
    ok(T:ActiveTab() == 1, "nothing chosen yet: the first tab")
    st.char.activeTab = 3
    ok(T:ActiveTab() == 3, "the one chosen")
    st.cfg.sectionTab.achievements = nil
    ok(T:ActiveTab() == 1, "a chosen tab that no longer holds anything falls back to the first in use")
    st.cfg.sectionTab = { campaign = 2, quests = 2, achievements = 2, worldquests = 2, zoneprogress = 3 }
    st.char.activeTab = 1
    st.docked = true
    ok(T:ActiveTab() == 2, "with nothing left on tab 1, the first tab in use is 2")
    st.docked = false
    ok(T:ActiveTab() == nil, "and with the zone bar floating, tab 3 holds nothing, so there are no tabs")
    load({ cfg = { showTabs = true, sectionTab = { quests = 2 } }, noChar = true })
    ok(st.Tracker:ActiveTab() == 1, "no character table yet: the first tab")
end)

case("switching tabs stores the choice, opens the new tab at its top and redraws", function()
    load({ cfg = { showTabs = true, sectionTab = { quests = 2 } } })
    local T, sc = st.Tracker, st.f.scroll
    sc.vscroll = 600
    T:SetActiveTab(2)
    ok(st.char.activeTab == 2 and st.renders == 1, "stored and redrawn once")
    ok(sc.vscroll == 0 and sc.vsets == 1, "the new tab opens at its top, not 600 px down")
    sc.vscroll = 300
    T:SetActiveTab(2)
    ok(sc.vscroll == 300 and sc.vsets == 1 and st.renders == 2, "a click on the tab on screen keeps its place")
    T:SetActiveTab(1)
    ok(sc.vscroll == 0 and sc.vsets == 2, "back to tab 1: its top")
    sc.vscroll = 300
    T:SetActiveTab(3)
    ok(sc.vscroll == 300 and sc.vsets == 2,
       "a tab no longer in use falls back to the first in use, here the one shown, so the place is kept")
    T:SetActiveTab(2)
    sc.vscroll = 300
    T:SetActiveTab(3)
    ok(sc.vscroll == 0 and sc.vsets == 4,
       "from tab 2, a tab no longer in use falls back to tab 1, a different tab, which opens at its top")
    load({ cfg = { showTabs = true, sectionTab = { quests = 2 } } })
    sc = st.f.scroll
    sc.vscroll = 300
    st.Tracker:SetActiveTab(1)
    ok(sc.vscroll == 300 and sc.vsets == nil, "and with nothing saved yet, a click on tab 1, the one shown, too")
    load({ cfg = { showTabs = true }, noChar = true })
    ok(pcall(st.Tracker.SetActiveTab, st.Tracker, 2) and st.renders == 0, "no character table: nothing")
end)

case("a tab clicked in combat with item buttons opens when the fight ends", function()
    load({ cfg = { showTabs = true, sectionTab = { quests = 2, achievements = 3 } } })
    local T, sc = st.Tracker, st.f.scroll
    st.locked = true
    sc.vscroll = 600
    T:SetActiveTab(2)
    ok(st.char.activeTab == nil and st.renders == 0 and sc.vsets == nil, "nothing moves during the fight")
    ok(st.deferred == 1 and st.deferKey == "eqot.activeTab" and type(st.deferFn) == "function",
       "the switch is queued for the end of combat: " .. tostring(st.deferKey))
    T:SetActiveTab(3)
    ok(st.deferred == 2 and st.deferKey == "eqot.activeTab", "a second click in the fight queues under the same key")
    st.locked = false
    st.deferFn()
    ok(st.char.activeTab == 3 and st.renders == 1 and sc.vscroll == 0, "the fight over, the last tab clicked opens at its top")
    ok(T._pendingTab == nil, "and nothing is left queued")
    st.deferFn()
    ok(st.renders == 1, "so a second run of the queue does nothing")
end)

case("a hidden section, or the zone bar while it floats, neither earns a tab nor names one", function()
    load({ cfg = { showTabs = true, sectionTab = { zoneprogress = 2 } } })
    local T, s = st.Tracker, st.f.tabStrip
    local zone = st.Sections:Title("zoneprogress")
    ok(T:TabsInUse() == nil, "the zone bar floats by default, so moving it alone makes no tab")
    st.docked = true
    local used = T:TabsInUse()
    ok(used and used[1] and used[2], "docked in the tracker, it holds tab 2")
    T:LayoutTabs(T:ActiveTab())
    ok(s.tabs[2]._label == zone, "and names it: " .. tostring(s.tabs[2]._label))
    st.docked = false
    st.cfg.sectionTab = { quests = 2 }
    T:LayoutTabs(T:ActiveTab())
    ok(s.tabs[1]._label == labelFor(1) and not s.tabs[1]._label:find(zone, 1, true),
       "floating, it names no tab: " .. tostring(s.tabs[1]._label))
    st.docked = true
    T:LayoutTabs(T:ActiveTab())
    ok(s.tabs[1]._label:find(zone, 1, true) == 1, "docked, it leads tab 1's name again")
    st.cfg.sectionTab = { quests = 2, achievements = 3 }
    st.cfg.sectionsHidden = { achievements = true }
    used = T:TabsInUse()
    ok(used and used[1] and used[2] and not used[3], "a hidden section on tab 3 makes no tab")
    T:LayoutTabs(T:ActiveTab())
    ok(#s.tabs == 2 or not s.tabs[3].shown, "so no third button")
    ok(not s.tabs[1]._label:find(st.Sections:Title("achievements"), 1, true), "and tab 1 does not name it")
    st.cfg.sectionsHidden = { quests = true }
    st.cfg.sectionTab = { quests = 2 }
    st.char.activeTab = 2
    ok(T:TabsInUse() == nil and T:ActiveTab() == nil, "hiding the only section on tab 2 leaves one tab")
end)

case("the render shows the tabs only once the content sits under the strip", function()
    load({ cfg = { showTabs = true, sectionTab = { quests = 2 } } })
    local T, f = st.Tracker, st.f
    T:ApplyContentInset()
    ok(st.prologue(T, f) == 1 and T._activeTab == 1 and f.tabStrip.shown, "under the strip: tab 1 on screen")
    st.char.activeTab = 2
    ok(st.prologue(T, f) == 2 and T._activeTab == 2, "the tab chosen")
    f._contentTop = 14
    ok(st.prologue(T, f) == nil and T._activeTab == nil and f.tabStrip.shown == false,
       "the content still at the drag strip, as combat leaves it: every section shows and the strip waits")
    st.cfg.showTabs = false
    T:ApplyContentInset()
    ok(st.prologue(T, f) == nil and f.tabStrip.shown == false, "tabs off: none")
end)

case("the docked zone bar is hidden while its section's tab is not on screen", function()
    load({ cfg = { showTabs = true, sectionTab = { quests = 2 } }, docked = true })
    local T, f = st.Tracker, st.f
    T:ApplyContentInset()
    st.prologue(T, f)
    ok(st.zoneHides == 0, "its own tab on screen: the section's pass draws it")
    st.char.activeTab = 2
    st.prologue(T, f)
    ok(st.zoneHides == 1, "another tab: hidden, since the section's pass that hides it is skipped")
    st.cfg.sectionTab = { quests = 2, zoneprogress = 2 }
    st.prologue(T, f)
    ok(st.zoneHides == 1, "moved onto the tab on screen: left to its section")
    st.char.activeTab = 1
    st.prologue(T, f)
    ok(st.zoneHides == 2, "on tab 2 with tab 1 on screen: hidden, whichever way round the tabs are")
    st.cfg.showTabs = false
    T:ApplyContentInset()
    st.prologue(T, f)
    ok(st.zoneHides == 2, "tabs off: left to its section")
end)

case("World Quests collapse while their tab is not the one on screen", function()
    load({ cfg = { showTabs = true, sectionTab = { worldquests = 2 } } })
    local T, f = st.Tracker, st.f
    f.eventsRegion, f.eventsScroll, f.eventsContent = newFrame("Frame", f), newFrame("ScrollFrame", f), newFrame("Frame", f)
    local group = { visibleCount = 3, totalCount = 3 }
    T._activeTab = 1
    local h, drew = T:_RenderPinnedWorldQuests(group, 200, 300, st.cfg)
    ok(h == 0 and drew == false and f.eventsRegion.shown == false and f.eventsScroll.shown == false,
       "on tab 1, World Quests sitting on tab 2 collapse")
    T._activeTab = 2
    ok(T:_RenderPinnedWorldQuests(group, 200, 300, st.cfg) == "drawn", "on their own tab they draw")
    T._activeTab = nil
    ok(T:_RenderPinnedWorldQuests(group, 200, 300, st.cfg) == "drawn", "with no tab strip they draw")
    st.cfg.sectionTab = {}
    T._activeTab = 1
    ok(T:_RenderPinnedWorldQuests(group, 200, 300, st.cfg) == "drawn", "never moved, they are on tab 1")
    T._activeTab = 2
    ok(T:_RenderPinnedWorldQuests(group, 200, 300, st.cfg) == 0, "and so collapse on tab 2")
end)

case("/eqot status reads the tabs", function()
    load({ cfg = {} })
    local T = st.Tracker
    ok(T:TabsLine() == "tabs: off", "off: " .. T:TabsLine())
    st.cfg.showTabs = 1
    ok(T:TabsLine() == "tabs: off", "a stray 1 in a profile is off, as the tracker reads it: " .. T:TabsLine())
    st.cfg.showTabs = true
    ok(T:TabsLine() == "tabs: on, one tab in use, strip hidden", "on with nothing moved: " .. T:TabsLine())
    st.cfg.sectionTab = { quests = 3 }
    st.char.activeTab = 3
    T._activeTab = 3
    ok(T:TabsLine() == "tabs: on, in use 1,3, showing 3, saved 3, queued nil, content top nil",
       "before the content was ever inset, its top is unknown: " .. T:TabsLine())
    T:ApplyContentInset()
    ok(T:TabsLine() == "tabs: on, in use 1,3, showing 3, saved 3, queued nil, content top 32", "in use: " .. T:TabsLine())
    T._activeTab, st.f._contentTop = nil, 14
    ok(T:TabsLine() == "tabs: on, in use 1,3, showing nil, saved 3, queued nil, content top 14",
       "waiting for combat, the content still at the drag strip: " .. T:TabsLine())
    st.char.activeTab, T._activeTab, T._pendingTab = 2, 1, 3
    ok(T:TabsLine() == "tabs: on, in use 1,3, showing 1, saved 2, queued 3, content top 14",
       "a saved tab no longer in use, shown as the first, with a click waiting for the fight: " .. T:TabsLine())
    local f = T.frame
    T.frame = nil
    local good, line = pcall(T.TabsLine, T)
    ok(good and line == "tabs: on, in use 1,3, showing 1, saved 2, queued 3, content top nil",
       "before the tracker frame is built, it still reads: " .. tostring(line))
    T.frame = f
end)

case("the render keeps only the active tab's sections, in order", function()
    load({ cfg = { showTabs = true, sectionTab = { quests = 2 } } })
    local T = st.Tracker
    local order = { "zoneprogress", "campaign", "quests", "achievements" }
    ok(T:_OrderOnTab(order, nil) == order, "no tab strip: the whole order, the same table")
    ok(table.concat(T:_OrderOnTab(order, 1), ",") == "zoneprogress,campaign,achievements", "tab 1")
    ok(table.concat(T:_OrderOnTab(order, 2), ",") == "quests", "tab 2")
    ok(table.concat(T:_OrderOnTab(order, 3), ",") == "", "an empty tab: nothing")
    ok(table.concat(T:_OrderOnTab(order, 1), ",") == "zoneprogress,campaign,achievements",
       "and the reused list holds nothing from the call before")
end)

-- ---------------------------------------------------------------------------- the strip

case("the strip is built hidden, under the drag strip, the height of a tab", function()
    load()
    local s = st.f.tabStrip
    ok(s and s.parent == st.f and s.kind == "Frame", "a frame on the tracker")
    ok(s.shown == false, "built hidden")
    ok(s.height == 18, "18 tall: " .. tostring(s.height))
    local tl, tr = s.points[1], s.points[2]
    ok(tl and tl[1] == "TOPLEFT" and tl[2] == 4 and tl[3] == -14, "4 in, under the 14 px drag strip")
    ok(tr and tr[1] == "TOPRIGHT" and tr[2] == -4 and tr[3] == -14, "and 4 in from the right")
    ok(type(s.tabs) == "table" and #s.tabs == 0, "with no buttons until a layout asks")
end)

case("the strip lays one button per tab in use, named after its sections", function()
    load({ cfg = { showTabs = true, sectionTab = { quests = 2, worldquests = 2 } } })
    local T, s = st.Tracker, st.f.tabStrip
    local active = T:ActiveTab()
    T:LayoutTabs(active)
    ok(s.shown == true, "shown")
    ok(#s.tabs == 2 and s.tabs[1].shown and s.tabs[2].shown, "two buttons")
    ok(s.tabs[1].tab == 1 and s.tabs[2].tab == 2, "for tabs 1 and 2")
    ok(s.tabs[1]._label == labelFor(1) and labelFor(1):find(st.Sections:Title("campaign"), 1, true) ~= nil,
       "the first named after tab 1's sections: " .. tostring(s.tabs[1]._label))
    ok(s.tabs[2]._label == labelFor(2) and labelFor(2) == st.Sections:Title("quests") .. ", " .. st.Sections:Title("worldquests"),
       "the second after Quests and World Quests: " .. tostring(s.tabs[2]._label))
    ok(s.tabs[1].font.text == s.tabs[1]._label and s.tabs[1].font.wrap == false, "on one line")
    local b1, b2 = s.tabs[1], s.tabs[2]
    ok(b1.height == 16, "each button 2 px short of the strip: " .. tostring(b1.height))
    local layers = {}
    for _, t in ipairs(b1.textures) do layers[#layers + 1] = tostring(t.layer) end
    ok(b1.bg.all == true, "the fill covers the whole button")
    ok(b1.font.layer == "OVERLAY", "the label drawn over the fill and the underline: " .. tostring(b1.font.layer))
    ok(table.concat(layers, ",") == "BACKGROUND,ARTWORK,HIGHLIGHT",
       "a fill, an underline and a hover highlight: " .. table.concat(layers, ","))
    local hl = b1.textures[3]
    ok(hl and hl.all and hl.color and hl.color[4] == 0.08, "the highlight a faint wash over the whole button")
    ok(b1.line.height == 2 and b1.line.points[1][1] == "BOTTOMLEFT" and b1.line.points[2][1] == "BOTTOMRIGHT",
       "the underline 2 px along the bottom")
    ok(b1.bg.color[4] == 0.35 and b2.bg.color[4] == 0.15, "the tab on screen on the darker fill")
    local tp = b1.font.points
    ok(tp[1][1] == "LEFT" and tp[1][2] == 4 and tp[1][3] == 1 and tp[2][1] == "RIGHT" and tp[2][2] == -4
       and tp[2][3] == 1, "the label inset 4 px from each end")
    local w = s.tabs[1].width
    ok(w == (304 - 8 - 2) / 2, "the strip's width shared out, with a 2 px gap: " .. tostring(w))
    ok(s.tabs[2].points[1][4] == w + 2, "the second starts one width and a gap along")
    ok(s.tabs[1].font.color[1] == 1 and s.tabs[2].font.color[1] == 0.6, "the tab on screen bright, the other grey")
    local line = s.tabs[1].line.color
    ok(line[1] == 0.92 and line[2] == 0.72 and line[3] == 0.02 and line[4] == 1, "and underlined in gold")
    local sets = s.tabs[1].font.sets
    T:LayoutTabs(active)
    ok(s.tabs[1].font.sets == sets, "the same label is not set again")
    st.cfg.sectionTab.achievements = 3
    T:LayoutTabs(T:ActiveTab())
    ok(#s.tabs == 3 and s.tabs[3].shown and s.tabs[3].tab == 3, "a third tab in use: a third button")
    st.cfg.sectionTab = {}
    T:LayoutTabs(T:ActiveTab())
    ok(s.shown == false, "back to one tab: the strip hides")
    st.cfg.sectionTab = { quests = 2 }
    T:LayoutTabs(T:ActiveTab())
    ok(s.tabs[3].shown == false, "and a button no longer needed is hidden")

    -- Tabs 1 and 3 in use, tab 2 empty: the second button is tab 3's, and lit while 3 is on screen.
    st.cfg.sectionTab = { quests = 3 }
    st.char.activeTab = 3
    T:LayoutTabs(T:ActiveTab())
    ok(s.tabs[2].tab == 3 and s.tabs[2]._label == labelFor(3), "the second button is tab 3's when tab 2 is empty")
    ok(s.tabs[2].font.color[1] == 1 and s.tabs[1].font.color[1] == 0.6, "and the one lit while tab 3 is on screen")
end)

case("a tab button switches tabs and names every section in its tooltip", function()
    load({ cfg = { showTabs = true, sectionTab = { quests = 2 } } })
    local T, s = st.Tracker, st.f.tabStrip
    T:LayoutTabs(T:ActiveTab())
    local b = s.tabs[2]
    b.scripts.OnClick(b)
    ok(st.char.activeTab == 2 and st.renders == 1, "a click shows its tab")
    T.clickThrough = true
    b.scripts.OnClick(s.tabs[1])
    ok(st.char.activeTab == 2, "a click-through tracker ignores it")
    b.scripts.OnEnter(b)
    ok(#st.tips == 0, "and shows no tooltip")
    T.clickThrough = false
    b.scripts.OnEnter(b)
    ok(st.tips[1] and st.tips[1].owner == b and st.tips[1].text == b._label and st.tips[1].shown, "the tooltip names its sections")
    local c = st.tips[1] and st.tips[1].color or {}
    ok(c[1] == 1 and c[2] == 1 and c[3] == 1 and (c[4] == nil or c[4] == 1), "in white at full alpha")
    b.scripts.OnLeave(b)
    ok(st.tipHides == 1, "and goes on leaving")
end)

case("the content moves below the strip only while it shows, and waits for combat", function()
    load({ cfg = {} })
    local T, sc = st.Tracker, st.f.scenarioContainer
    T:ApplyContentInset()
    ok(st.f._contentTop == 14 and sc.points[1][3] == -14, "no tabs: under the drag strip")
    st.cfg.showTabs, st.cfg.sectionTab = true, { quests = 2 }
    T:ApplyContentInset()
    ok(st.f._contentTop == 32 and sc.points[#sc.points][3] == -32, "a strip: 14 + 18 down: " .. tostring(st.f._contentTop))
    local n = #sc.points
    T:ApplyContentInset()
    ok(#sc.points == n, "nothing changed: no new anchor")
    st.cfg.sectionTab = {}
    st.locked = true
    T:ApplyContentInset()
    ok(st.f._contentTop == 32 and st.deferred == 1 and st.deferKey == "eqot.contentInset", "in combat: deferred, not moved")
    st.locked = false
    T:ApplyContentInset()
    ok(st.f._contentTop == 14, "and moved back once it can")
end)

-- ---------------------------------------------------------------------------- the wiring

do
    local code = stripComments(trackerSrc)
    ok(count(code, LOOP_LINE) == 1 and count(prologueSrc, "    self:LayoutTabs(activeTab)\n") == 1,
       "the render walks only the active tab's sections, after the lines run above lay out the strip")
    -- No harness runs the whole Render, so the tab on screen is held to the one write run above:
    -- a second one before the World Quests pass would show them on every tab.
    local writes, uses = 0, 0
    for _ in code:gmatch("_activeTab%s*=[^=]") do writes = writes + 1 end
    for _ in code:gmatch("_activeTab") do uses = uses + 1 end
    -- Every use counted too, since a multiple assignment hides from the write pattern: the write,
    -- World Quests' two reads in their guard, and the status line's.
    ok(writes == 1 and uses == 4,
       "the tab on screen is written in one place, before the sections and World Quests: " .. writes .. " " .. uses)
    ok(count(code, "    local want = math.max(1, math.floor((f:GetWidth() or 0) + 0.5) - scrollGutter(cfg))\n") == 1,
       "the list's width leaves the scroll bar's own gutter, slim or stock")
    -- The count is held to its whole text, so no tab test of any spelling can be slipped into it.
    local rowsBlock = between(code, "    local questRows = 0\n", "    local y        = 0\n")
    ok(rowsBlock == "    local questRows = 0\n    do\n"
           .. "        local provider = ns:GetModule(\"Registry\"):Get(QUEST_PROVIDER)\n"
           .. "        local groups   = provider and provider.groups\n"
           .. "        for i = 1, (groups and #groups or 0) do\n"
           .. "            local gid = groups[i]\n"
           .. "            if not Sections:IsHidden(gid) then\n"
           .. "                local g = byGroup[gid]\n"
           .. "                questRows = questRows + ((g and g.visibleCount) or 0) + Popups:CountFor(gid)\n"
           .. "            end\n        end\n    end\n\n",
       "Hide when no quests counts the quests on every tab, not only the one on screen")
    ok(count(code, "       or (self._activeTab and self:SectionTab(PINNED_GROUP) ~= self._activeTab) then\n") == 1,
       "World Quests collapse while their tab is not on screen")
    ok(count(code, "(f:GetHeight() or 0) - (f._contentTop or DRAG_HANDLE_H) - scenarioH") == 1,
       "the list's height leaves room for the strip")
    ok(count(code, "local TAB_STRIP_H      = 18\n") == 1 and count(code, "local MAX_TABS         = 3\n") == 1,
       "the strip is 18 tall and there are 3 tabs")
    local vis = stripComments(readFile("UI/Visibility.lua"))
    ok(count(vis, "    if over(f.tabStrip) then return true end\n") == 1, "hovering the strip counts as hovering the tracker")
    local db = readFile("Core/DB.lua")
    ok(count(db, "            showTabs       = false,\n") == 1, "tabs ship off")
    ok(count(db, "            sectionTab     = {},\n") == 1, "with every section on tab 1")
end

print(("test_tabs: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
