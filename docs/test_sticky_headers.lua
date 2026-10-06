-- Unit tests for the sticky section headers, run against the SHIPPED source rather than a copy.
-- Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_sticky_headers.lua
--
-- WHAT THE FEATURE IS. With "Keep section headers in view while scrolling" on, a band above the
-- quest list holds the header of the section the list is scrolled into. The band sits above the
-- scroll frame rather than over it, so rows leaving the top are cut off at its edge. The first
-- section's header lives in the band instead of the list, and a later header pushes the band's
-- one up as it reaches the top.
--
-- WHAT IS HELD HERE. stickyState's hand-over and push, driven. Tracker:_UpdateSticky over stub
-- frames: which section each band header shows, where it sits, the text it copies, the click
-- target, styling a header the first time it is made, and the fallback with no clipping. The
-- anchor chain ApplyWorldQuestsPosition builds with the option on and off, at either World
-- Quests position, its combat deferral and the one Refresh it asks for on a change. The docked
-- zone bar section giving its header to the band. The opacity hover counting the band. The band's
-- zone row (zone headers): the hand-over and push inside a section, a section push that brings the
-- next section's first zone in without pushing this one's last, a first zone below the band, a
-- leftover zone key under a section with no zones, the copies restyled once per render with the
-- profile Core/DB.lua's own DB:Tracker (sliced) reads through self, and the row coming back after a
-- pass that hid it.
--
-- OUT OF SCOPE BY CONSTRUCTION: Tracker:Render is too large to drive, so its share (the first
-- header hidden instead of spaced, the band's height, the list giving that height up, the update
-- and the styling after sizing) is pinned by comment-stripped whole-statement greps at the end. The
-- one block of it that is sliced and run keeps the band's zone arrays on the frame. Whether the
-- client clips the band, and how the push looks, are in-game questions.

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
-- Core/DB.lua's accessors read self, so a module calling one with a dot raises in game. This
-- stand-in raises the same way, rather than answering a call the client would refuse.
local function strictDB(methods)
    local db = {}
    for name, v in pairs(methods) do
        if type(v) == "function" then
            db[name] = function(self, ...)
                if self ~= db then error("DB:" .. name .. " called without self", 2) end
                return v(self, ...)
            end
        else
            db[name] = v
        end
    end
    return db
end

local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end

local function case(name, fn)
    print("== " .. name)
    local good, err = pcall(fn)
    ok(good, name .. " raised: " .. tostring(err))
end

local function slicer(rel)
    local src = readFile(rel)
    return function(fromAnchor, toAnchor)
        local function only(anchor)
            local at, n, from = nil, 0, 1
            while true do
                local i = src:find(anchor, from, true)
                if not i then break end
                at, n, from = at or i, n + 1, i + 1
            end
            assert(n == 1, ("anchor matched %d times in %s (need exactly 1): %s")
                           :format(n, rel, anchor))
            return at
        end
        local from, to = only(fromAnchor), only(toAnchor)
        assert(to > from, "anchors are out of order in " .. rel .. ": " .. fromAnchor)
        return src:sub(from, to - 1)
    end
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

local trackerSlice = slicer("UI/Tracker.lua")

-- Core/DB.lua's own DB:Tracker, sliced, over a stub profile. It reads through self, so a call
-- written DB.Tracker() raises here as it does in game. nil when the slice fails, which the rig
-- that asks for it reports.
local dbTracker
do
    local good, err = pcall(function()
        local src = readFile("Core/DB.lua")
        local head = "\nfunction DB:Tracker()\n"
        local a = src:find(head, 1, true)
        local b = a and src:find("\nend\n", a + 1, true)
        assert(a and b and not src:find(head, a + 1, true), "Core/DB.lua defines DB:Tracker once")
        local holder = {}
        local chunk = assert(loadstring(src:sub(a + 1, b + 4), "DB:Tracker"))
        setfenv(chunk, { DB = holder })
        chunk()
        dbTracker = holder.Tracker
    end)
    ok(good and type(dbTracker) == "function", "DB:Tracker slices out of Core/DB.lua: " .. tostring(err))
end

-- ------------------------------------------------------------------------------ the stubs

local function fontString(text)
    local s = { text = text }
    function s:SetText(t) self.text = t end
    function s:GetText() return self.text end
    return s
end

local function frame(name)
    local f = { name = name, shown = true, points = {}, h = 1 }
    function f:ClearAllPoints() self.points = {} end
    function f:SetPoint(p, rel, relP, x, y)
        self.points[#self.points + 1] = { p, rel, relP, x or 0, y or 0 }
    end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:GetHeight() return self.h end
    function f:SetHeight(h) self.h = h end
    return f
end

-- The point list as one string, relative frames by name, so an assertion reads as the anchor.
local function pointsOf(f)
    local out = {}
    for i, p in ipairs(f.points) do
        out[i] = ("%s>%s.%s(%g,%g)"):format(p[1], p[2] and p[2].name or "nil", p[3], p[4], p[5])
    end
    return table.concat(out, " ")
end

-- ------------------------------------------------------- ApplyWorldQuestsPosition, driven

local anchorSrc = trackerSlice("function Tracker:ApplyWorldQuestsPosition()",
                               "function Tracker:SetWorldQuestsPosition(pos)")

local function anchorRig(cfg, opts)
    opts = opts or {}
    local st = { refresh = 0, deferred = {}, locked = opts.locked or false, cfg = cfg }
    local f = { scroll = frame("scroll"), eventsRegion = frame("region"),
                scenarioContainer = frame("scen") }
    if not opts.noBand then f.stickyBand = frame("band") end
    f._stickyAnchored = opts.anchored
    local T = { frame = f }
    function T:Refresh() st.refresh = st.refresh + 1 end
    local modules = {
        DB = strictDB({ Tracker = function() return st.cfg end }),
        Events = { RunWhenOutOfCombat = function(_, key) st.deferred[#st.deferred + 1] = key end },
    }
    local ns = { GetModule = function(_, n) return modules[n] end }
    local env = setmetatable({
        Tracker = T, ns = ns,
        secureLocked = function() return st.locked end,
        applyWQPosWhenSafe = function() end,
    }, { __index = _G })
    local chunk = assert(loadstring(anchorSrc, "apply-wq-position"))
    setfenv(chunk, env)
    chunk()
    st.T, st.f = T, f
    return st
end

case("unset, it is on: the band joins the chain", function()
    local st = anchorRig({ worldQuestsPosition = "bottom" })
    st.T:ApplyWorldQuestsPosition()
    ok(#st.f.stickyBand.points == 2 and st.f._stickyAnchored == true,
       "with nothing stored the band is anchored, as the shipped default says")
end)

case("off at the bottom, the list hangs off the scenario container as it always has", function()
    local st = anchorRig({ worldQuestsPosition = "bottom", stickySectionHeaders = false })
    st.T:ApplyWorldQuestsPosition()
    local f = st.f
    ok(pointsOf(f.scroll) == "TOPLEFT>scen.BOTTOMLEFT(0,-2)", "scroll: " .. pointsOf(f.scroll))
    ok(pointsOf(f.eventsRegion) == "TOPLEFT>scroll.BOTTOMLEFT(0,-2) TOPRIGHT>scroll.BOTTOMRIGHT(0,-2)",
       "region: " .. pointsOf(f.eventsRegion))
    ok(#f.stickyBand.points == 0, "the band is left out of the chain")
    ok(not f._stickyAnchored, "not recorded as anchored")
    ok(st.refresh == 0, "nothing changed from a fresh frame, so no render is asked for")
end)

case("off at the top, the list hangs off the world quest region", function()
    local st = anchorRig({ worldQuestsPosition = "top", stickySectionHeaders = false })
    st.T:ApplyWorldQuestsPosition()
    local f = st.f
    ok(pointsOf(f.eventsRegion) == "TOPLEFT>scen.BOTTOMLEFT(0,-2) TOPRIGHT>scen.BOTTOMRIGHT(0,-2)",
       "region: " .. pointsOf(f.eventsRegion))
    ok(pointsOf(f.scroll) == "TOPLEFT>region.BOTTOMLEFT(0,-2)", "scroll: " .. pointsOf(f.scroll))
    ok(#f.stickyBand.points == 0, "the band is left out of the chain")
end)

case("on at the bottom, the band takes the list's old place and the list hangs off it", function()
    local st = anchorRig({ worldQuestsPosition = "bottom", stickySectionHeaders = true })
    st.T:ApplyWorldQuestsPosition()
    local f = st.f
    ok(pointsOf(f.stickyBand) == "TOPLEFT>scen.BOTTOMLEFT(0,-2) TOPRIGHT>scen.BOTTOMRIGHT(0,-2)",
       "band: " .. pointsOf(f.stickyBand))
    ok(pointsOf(f.scroll) == "TOPLEFT>band.BOTTOMLEFT(0,0)",
       "scroll sits flush under the band, so a header crossing the edge reads as one: " .. pointsOf(f.scroll))
    ok(pointsOf(f.eventsRegion) == "TOPLEFT>scroll.BOTTOMLEFT(0,-2) TOPRIGHT>scroll.BOTTOMRIGHT(0,-2)",
       "region still follows the list: " .. pointsOf(f.eventsRegion))
    ok(f._stickyAnchored == true and st.refresh == 1, "recorded, and one render asked for")
    st.T:ApplyWorldQuestsPosition()
    ok(st.refresh == 1, "applied again unchanged, no second render")
    ok(#f.stickyBand.points == 2, "and the band's points are replaced, not stacked: " .. #f.stickyBand.points)
end)

case("on at the top, the band sits under the world quest region", function()
    local st = anchorRig({ worldQuestsPosition = "top", stickySectionHeaders = true })
    st.T:ApplyWorldQuestsPosition()
    local f = st.f
    ok(pointsOf(f.eventsRegion) == "TOPLEFT>scen.BOTTOMLEFT(0,-2) TOPRIGHT>scen.BOTTOMRIGHT(0,-2)",
       "region: " .. pointsOf(f.eventsRegion))
    ok(pointsOf(f.stickyBand) == "TOPLEFT>region.BOTTOMLEFT(0,-2) TOPRIGHT>region.BOTTOMRIGHT(0,-2)",
       "band: " .. pointsOf(f.stickyBand))
    ok(pointsOf(f.scroll) == "TOPLEFT>band.BOTTOMLEFT(0,0)", "scroll: " .. pointsOf(f.scroll))
end)

case("switched off again, the list goes back and one render is asked for", function()
    local st = anchorRig({ worldQuestsPosition = "bottom", stickySectionHeaders = false }, { anchored = true })
    st.T:ApplyWorldQuestsPosition()
    ok(pointsOf(st.f.scroll) == "TOPLEFT>scen.BOTTOMLEFT(0,-2)", "scroll: " .. pointsOf(st.f.scroll))
    ok(st.f._stickyAnchored == false and st.refresh == 1, "recorded off, one render")
end)

case("in combat it defers and changes nothing, so Render keeps laying out for the old chain", function()
    local st = anchorRig({ worldQuestsPosition = "bottom", stickySectionHeaders = true }, { locked = true })
    st.T:ApplyWorldQuestsPosition()
    ok(#st.deferred == 1 and st.deferred[1] == "eqot.applyWQPos", "deferred under its key")
    ok(#st.f.scroll.points == 0 and #st.f.stickyBand.points == 0, "no anchor moved")
    ok(st.f._stickyAnchored == nil and st.refresh == 0, "and the anchored state is not claimed early")
end)

case("a frame with no band keeps the old chain even with the option on", function()
    local st = anchorRig({ worldQuestsPosition = "bottom", stickySectionHeaders = true }, { noBand = true })
    st.T:ApplyWorldQuestsPosition()
    ok(pointsOf(st.f.scroll) == "TOPLEFT>scen.BOTTOMLEFT(0,-2)", "scroll: " .. pointsOf(st.f.scroll))
    ok(not st.f._stickyAnchored, "and nothing claims a band is anchored")
end)

-- ---------------------------------------------- the zone bar section, stickyState, the band

local bandSrc = trackerSlice("function Tracker:_RenderZoneSection(content, groupID, y, gap, inBand)",
                             "function Tracker:_RenderScenario(group, cfg)")
    .. "\nreturn stickyState"

local function bandRig(opts)
    opts = opts or {}
    local st = { styled = {}, made = 0, zone = opts.zone, collapsed = opts.collapsed or {},
                 hideDocked = 0, docked = {} }
    local function header(id, text, cnt, col)
        local h = frame("header:" .. tostring(id))
        h.text, h.count, h.collapse = fontString(text), fontString(cnt), fontString(col)
        return h
    end
    local Sections = { frames = {} }
    function Sections:NewHeader(parent, id)
        st.made = st.made + 1
        local h = header(id, "title:" .. tostring(id), "", "")
        h.parent = parent
        return h
    end
    function Sections:ApplyStyle(h) st.styled[h] = (st.styled[h] or 0) + 1 end
    function Sections:IsCollapsed(id) return st.collapsed[id] == true end
    function Sections:Acquire(_, id)
        local h = self.frames[id] or header(id, "", "", "")
        self.frames[id] = h
        return h
    end
    function Sections:Place(h, _, y, _, collapsed)
        h.placedAt = y
        h:Show()
        h.collapse:SetText(collapsed and "+" or "-")
        return 26
    end
    local ZoneBar = {
        DockedState = function() if st.zone then return 3, 10, st.zone end end,
        HideDocked = function() st.hideDocked = st.hideDocked + 1 end,
        RenderDocked = function(_, _, y) st.docked[#st.docked + 1] = y; return 20 end,
    }
    -- The zone headers' side of the band: Mirror copies from the pooled header a zone was drawn
    -- into, which st.zoneSrc stands in for. st.zoneStyledWith keeps the settings each styling of a
    -- copy was handed, and st.cfg is the tracker profile the real DB:Tracker hands back.
    st.zoneSrc, st.zoneMade, st.zoneStyled, st.zoneStyledWith = {}, 0, {}, {}
    st.cfg = { zoneHeaders = true }
    -- gen is what ZoneHeaders:Begin moves on every render. newPass stands in for one.
    local ZoneHeaders = { gen = 1 }
    st.newPass = function() ZoneHeaders.gen = ZoneHeaders.gen + 1 end
    function ZoneHeaders:NewHeader(parent)
        st.zoneMade = st.zoneMade + 1
        local h = header("zone", "", "", "")
        h.parent = parent
        return h
    end
    function ZoneHeaders:Mirror(dst, key)
        local src = st.zoneSrc[key]
        if not src then return false end
        dst.key = key
        dst.text:SetText(src.text:GetText())
        return true
    end
    function ZoneHeaders:ApplyStyle(h, cfg)
        st.zoneStyled[h] = (st.zoneStyled[h] or 0) + 1
        local with = st.zoneStyledWith[h] or {}
        with[#with + 1] = cfg == nil and "nothing" or cfg
        st.zoneStyledWith[h] = with
    end
    assert(dbTracker, "no DB:Tracker to hand the band")
    local DB = { db = { profile = { tracker = st.cfg } }, Tracker = dbTracker }
    local modules = { Sections = Sections, ZoneProgressBar = (not opts.noZoneBar) and ZoneBar or nil,
                      ZoneHeaders = ZoneHeaders, DB = DB }
    local ns = { GetModule = function(_, n) return modules[n] end }

    local band = frame("band")
    band.heads = {}
    band.zoneHeads = {}
    if not opts.noClip then function band.SetClipsChildren() end end
    local scrollOffset = 0
    local f = { stickyBand = band, scroll = { GetVerticalScroll = function() return scrollOffset end } }
    local T = { frame = f }
    st.rows = 0
    local function createFrame(_, _, parent)
        st.rows = st.rows + 1
        local r = frame("zoneRow")
        r.parent = parent
        if not opts.noClip then function r.SetClipsChildren(self) self.clips = true end end
        return r
    end
    local env = setmetatable({ Tracker = T, ns = ns, _virtualGroup = {}, CreateFrame = createFrame },
                             { __index = _G })
    local chunk = assert(loadstring(bandSrc, "sticky-band"))
    setfenv(chunk, env)
    st.stickyState = chunk()
    st.T, st.f, st.band, st.Sections = T, f, band, Sections
    st.scrollTo = function(v) scrollOffset = v end
    -- The drawn sections as Render would record them: each id with the top of its header in
    -- the list, the first one's shown in the band, and the band's height.
    st.layout = function(ids, tops, h)
        f._stickyAnchored = true
        f._stickyIDs, f._stickyTops, f._stickyN, f._stickyH = ids, tops, #ids, h
        for i, id in ipairs(ids) do
            Sections.frames[id] = header(id, "T:" .. id, i .. "/9", "-")
        end
    end
    -- The drawn zones as Render records them: keys and list tops in drawing order, each
    -- section's first and last index into them, and the two row heights the band adds up.
    st.zoneLayout = function(keys, tops, first, last, row1, row2)
        f._stickyZoned = true
        f._stickyZKeys, f._stickyZTops, f._stickyZFirst, f._stickyZLast = keys, tops, first, last
        f._stickyRow1, f._stickyRow2 = row1, row2
        for _, k in ipairs(keys) do st.zoneSrc[k] = header("src", "Z:" .. k, "", "") end
    end
    return st
end

case("stickyState hands over only once a header has scrolled fully under the band", function()
    local S = bandRig().stickyState
    local tops = { 0, 100, 250 }
    local function at(offset)
        local cur, push = S(tops, 3, offset, 30)
        return cur .. "/" .. push
    end
    ok(at(0) == "1/0", "at rest the first section: " .. at(0))
    ok(at(99) == "1/0", "the second header still below the top: " .. at(99))
    ok(at(100) == "1/0", "the second header exactly at the top pushes nothing yet: " .. at(100))
    ok(at(110) == "1/10", "10px past it, the band's header is pushed up 10: " .. at(110))
    ok(at(129.5) == "1/29.5", "half a pixel short of the hand-over: " .. at(129.5))
    ok(at(130) == "2/0", "a whole band past it, the second section takes the band: " .. at(130))
    ok(at(260) == "2/10", "and the third header pushes that one: " .. at(260))
    ok(at(280) == "3/0", "the third takes over a band later: " .. at(280))
    ok(at(5000) == "3/0", "the last section is never pushed: " .. at(5000))
    local cur, push = S(tops, 2, 5000, 30)
    ok(cur == 2 and push == 0, "entries past n are not read: " .. cur .. "/" .. push)
    cur, push = S({ 0 }, 1, 400, 30)
    ok(cur == 1 and push == 0, "one section stays put however far it scrolls")
end)

case("stickyState with the band's section collapsed, so the next header starts the list", function()
    local S = bandRig().stickyState
    local tops = { 0, 0, 50 }
    local function at(offset)
        local cur, push = S(tops, 3, offset, 30)
        return cur .. "/" .. push
    end
    ok(at(0) == "1/0", "at rest the collapsed one keeps the band: " .. at(0))
    ok(at(5) == "1/5", "and the header under it pushes from the first pixel: " .. at(5))
    ok(at(30) == "2/0", "taking over a band later: " .. at(30))
    ok(at(60) == "2/10", "then pushed by the third: " .. at(60))
end)

case("not anchored or nothing drawn, the band shows nothing and makes nothing", function()
    local st = bandRig()
    st.T:_UpdateSticky()
    ok(st.made == 0, "nothing made while off")
    st.layout({ "campaign" }, { 0 }, 30)
    st.T:_UpdateSticky()
    ok(#st.band.heads == 1 and st.band.heads[1].shown, "one section drawn, one header shown")
    st.f._stickyAnchored = false
    st.T:_UpdateSticky()
    ok(not st.band.heads[1].shown, "turned off, the shown header hides")
    st.f._stickyAnchored = true
    st.T:_UpdateSticky()
    ok(st.band.heads[1].shown, "turned back on, the same header shows again")
    st.f._stickyN = 0
    st.band.heads[1]:Show()
    st.T:_UpdateSticky()
    ok(not st.band.heads[1].shown, "and again once no section is drawn")
end)

case("at rest the band shows the first section, copied from its own header", function()
    local st = bandRig()
    st.layout({ "campaign", "quests", "achievements" }, { 0, 100, 250 }, 30)
    st.T:_UpdateSticky()
    local h = st.band.heads[1]
    ok(h and h.shown, "one header shown")
    ok(h.parent == st.band, "made inside the band, so the band clips it")
    ok(h.groupID == "campaign", "its click collapses the section it shows: " .. tostring(h.groupID))
    ok(h.text.text == "T:campaign" and h.count.text == "1/9" and h.collapse.text == "-",
       "title, count and collapse sign copied from the section's header")
    ok(pointsOf(h) == "TOPLEFT>band.TOPLEFT(0,0) TOPRIGHT>band.TOPRIGHT(0,0)", "flush with the band: " .. pointsOf(h))
    ok(st.styled[h] == 1, "styled once when it was made")
    ok(st.band.heads[2] == nil, "no second header made before a push")
    ok(st.T._stickyShown == "campaign" and st.T._stickyPush == 0, "the status line reads what is shown")
end)

case("a push slides the band's header up and the next one in under it", function()
    local st = bandRig()
    st.layout({ "campaign", "quests", "achievements" }, { 0, 100, 250 }, 30)
    st.T:_UpdateSticky()
    st.scrollTo(110)
    st.T:_UpdateSticky()
    local a, b = st.band.heads[1], st.band.heads[2]
    ok(a.groupID == "campaign" and pointsOf(a) == "TOPLEFT>band.TOPLEFT(0,10) TOPRIGHT>band.TOPRIGHT(0,10)",
       "the band's header moves up by the push: " .. pointsOf(a))
    ok(b and b.shown and b.groupID == "quests", "the incoming header is shown")
    ok(b and pointsOf(b) == "TOPLEFT>band.TOPLEFT(0,-20) TOPRIGHT>band.TOPRIGHT(0,-20)",
       "a band below the pushed one, where the list's copy has reached: " .. (b and pointsOf(b) or "none"))
    ok(b and b.text.text == "T:quests" and b.count.text == "2/9", "copied from its own section's header")
    ok(b and st.styled[b] == 1, "styled the moment it is made, mid-scroll")
    ok(st.T._stickyPush == 10, "the status line reads the push")

    st.scrollTo(130)
    st.T:_UpdateSticky()
    ok(a.groupID == "quests" and a.text.text == "T:quests", "handed over: the band shows the second section")
    ok(pointsOf(a) == "TOPLEFT>band.TOPLEFT(0,0) TOPRIGHT>band.TOPRIGHT(0,0)", "back flush: " .. pointsOf(a))
    ok(not b.shown, "and the incoming header hides once nothing is pushing")
    ok(st.styled[a] == 1 and st.styled[b] == 1, "a scroll step styles nothing it had already made")
    ok(st.made == 2, "two headers, ever: " .. st.made)

    st.scrollTo(0)
    st.T:_UpdateSticky()
    ok(a.groupID == "campaign" and a.collapse.text == "-", "scrolled back, the first section returns")

    st.scrollTo(260)
    st.T:_UpdateSticky()
    ok(b.shown and b.groupID == "achievements", "a later push shows the incoming header again: " .. tostring(b.groupID))
    st.f._stickyAnchored = false
    st.T:_UpdateSticky()
    ok(not a.shown and not b.shown, "switched off mid-push, both headers hide")
end)

case("BuildFrame makes the band inside the tracker frame, with an empty header list", function()
    local src = stripComments(trackerSlice("function Tracker:BuildFrame()",
                                           "local function setScrollBarHidden(sf, hidden)"))
    -- Up to the scroll frame, so anything done to the band after it is stored is run too.
    local first, last = "local stickyBand = CreateFrame(", 'local scroll = CreateFrame("ScrollFrame"'
    local a, b = src:find(first, 1, true), src:find(last, 1, true)
    ok(a ~= nil and b ~= nil and b > a, "the band block is found")
    if not (a and b and b > a) then return end
    local made = {}
    local tracker = frame("tracker")
    local env = setmetatable({ f = tracker, CreateFrame = function(kind, name, parent)
        local fr = frame("band")
        fr.kind, fr.frameName, fr.parent = kind, name, parent
        function fr:SetHeight(h) self.h = h end
        function fr:SetClipsChildren(v) self.clips = v end
        made[#made + 1] = fr
        return fr
    end }, { __index = _G })
    local chunk = assert(loadstring(src:sub(a, b - 1), "band-block"))
    setfenv(chunk, env)
    chunk()
    local band = made[1]
    ok(#made == 1 and tracker.stickyBand == band, "one band, kept on the tracker frame")
    ok(band and band.shown, "and left shown, since nothing else ever shows it")
    ok(band and band.parent == tracker, "parented to the tracker, so it scales, fades and hides with it")
    ok(band and type(band.heads) == "table" and next(band.heads) == nil, "with an empty header list for the update to fill")
    ok(band and type(band.zoneHeads) == "table" and next(band.zoneHeads) == nil and band.zoneHeads ~= band.heads,
       "and an empty zone header list of its own")
    ok(band and band.clips == true and band.h == 1, "clipping, and 1px tall until the first render")
end)

-- The band reuses one header for whichever section it shows, so the click has to read the
-- header's groupID when it fires. Driven through the real UI/Sections.lua.
case("the real header click collapses the section the header shows now", function()
    local function proxy()
        local p = { scripts = {} }
        return setmetatable(p, { __index = function(_, k)
            if k == "SetScript" then return function(self, e, fn) self.scripts[e] = fn end end
            if k == "RegisterForClicks" then return function(self, ...) self.clicks = { ... } end end
            if k == "CreateTexture" or k == "CreateFontString" or k == "CreateMaskTexture" then
                return function() return proxy() end
            end
            return function() end
        end })
    end
    local char, renders, clickThrough, scrolled, askedBy = {}, 0, false, {}, nil
    local mods = { DB = strictDB({ Char = function() return char end }) }
    mods.Tracker = {
        Render = function() renders = renders + 1 end,
        IsClickThrough = function(self) askedBy = self; return clickThrough end,
        ScrollSectionIntoView = function(_, id) scrolled[#scrolled + 1] = id end,
    }
    local ns = {
        Util = {},
        L = setmetatable({}, { __index = function(_, k) return k end }),
        RegisterModule = function(_, name, t) mods[name] = t; return t end,
        GetModule = function(_, n) return mods[n] end,
    }
    local chunk = assert(loadfile(repoFile("UI/Sections.lua")))
    setfenv(chunk, setmetatable({ CreateFrame = function() return proxy() end }, { __index = _G }))
    chunk("EQObjectiveTracker", ns)
    local h = mods.Sections:NewHeader(proxy(), "campaign")
    local click = h.scripts.OnClick
    ok(type(click) == "function", "the header carries a click")
    if type(click) ~= "function" then return end
    h.groupID = "quests"
    click(h)
    local c = char.sectionsCollapsed or {}
    ok(c.quests == true and c.campaign == nil, "the section it shows now collapses, not the one it was made for")
    ok(renders == 1 and #scrolled == 0, "and the tracker redraws once, scrolling nowhere")
    ok(askedBy == mods.Tracker, "the click-through check is asked of the tracker itself")
    ok(h.clicks and h.clicks[1] == "LeftButtonUp" and h.clicks[2] == nil, "the header takes left clicks only")
    clickThrough = true
    click(h)
    ok(c.quests == true and renders == 1, "a click-through tracker ignores it")
    clickThrough = false
    click(h)
    ok(c.quests == false and renders == 2 and scrolled[1] == "quests",
       "clicked again it expands and scrolls that section into view: " .. tostring(scrolled[1]))
end)

case("with no zone bar module the section reports nothing drawn", function()
    local st = bandRig({ noZoneBar = true })
    local added, drawn = st.T:_RenderZoneSection({}, "zoneprogress", 0, 2, true)
    ok(added == 0 and drawn == false, "nothing added and nothing drawn: " .. tostring(added) .. ", " .. tostring(drawn))
end)

case("without clipping the hand-over happens in place, never pushed over what sits above", function()
    local st = bandRig({ noClip = true })
    st.layout({ "campaign", "quests" }, { 0, 100 }, 30)
    st.scrollTo(110)
    st.T:_UpdateSticky()
    local a = st.band.heads[1]
    ok(a.groupID == "campaign" and pointsOf(a) == "TOPLEFT>band.TOPLEFT(0,0) TOPRIGHT>band.TOPRIGHT(0,0)",
       "the band's header holds still: " .. pointsOf(a))
    ok(st.band.heads[2] == nil or not st.band.heads[2].shown, "and no second header is drawn")
    ok(st.T._stickyPush == 0, "the status line reads no push")
    st.scrollTo(130)
    st.T:_UpdateSticky()
    ok(a.groupID == "quests", "the hand-over itself still happens")
end)

case("StickyLine says which state it is in", function()
    local st = bandRig()
    ok(st.T:StickyLine() == "sticky headers: off", "off: " .. st.T:StickyLine())
    st.layout({ "campaign", "quests" }, { 0, 100 }, 30)
    st.band.h = 30
    st.T:_UpdateSticky()
    local line = st.T:StickyLine()
    ok(line == "sticky headers: on, band 30px, 2 section(s), showing campaign, pushed 0, clip yes, zone row off",
       "on: " .. line)
    local nc = bandRig({ noClip = true })
    nc.layout({ "quests" }, { 0 }, 30)
    nc.T:_UpdateSticky()
    ok(nc.T:StickyLine():find("clip no", 1, true) ~= nil, "and reports a client without clipping")
end)

-- ------------------------------------------------------- the zone row (zone headers, 2.2.0)
-- Two sections: campaign at 0 with zones A (given to the band, so recorded one row above the
-- list) and B at 200, quests at 400 with zone C at 430. The band is 30 + 22 tall.

local function zoned(opts)
    local st = bandRig(opts)
    st.layout({ "campaign", "quests" }, { 0, 400 }, 52)
    st.zoneLayout({ "campaign:A", "campaign:B", "quests:C" }, { -22, 200, 430 }, { 1, 3 }, { 2, 3 }, 30, 22)
    return st
end

local function zh(st, slot) return st.band.zoneHeads[slot] end
local function shownKey(st, slot)
    local h = zh(st, slot)
    return (h and h.shown) and h.key or nil
end
local function dyOf(h) return h and h.points[1] and h.points[1][5] end
-- Every styling of the copy was handed the tracker profile itself, as DB:Tracker reads it.
local function styledWithProfile(st, h)
    local with = h and st.zoneStyledWith[h]
    if not with or #with == 0 then return false end
    for _, c in ipairs(with) do
        if c ~= st.cfg then return false end
    end
    return true
end

case("at rest the zone row sits under the section header and shows the section's first zone", function()
    local st = zoned()
    st.scrollTo(0)
    st.T:_UpdateSticky()
    local row = st.band.zoneRow
    ok(row and st.rows == 1 and row.parent == st.band and row.clips == true, "one clipping row, made in the band")
    ok(row and pointsOf(row) == "TOPLEFT>band.TOPLEFT(0,-30) TOPRIGHT>band.TOPRIGHT(0,-30)" and row.h == 22 and row.shown,
       "a row's height under the section header's: " .. (row and pointsOf(row) or "none"))
    local a = zh(st, 1)
    ok(shownKey(st, 1) == "campaign:A" and a.parent == row and a.points[1][2] == row and dyOf(a) == 0,
       "the first zone, at the top of the row")
    ok(a.text:GetText() == "Z:campaign:A", "copied from the zone's own header")
    ok(shownKey(st, 2) == nil and shownKey(st, 3) == nil, "nothing incoming")
    ok(st.T._stickyZone == "campaign:A", "and the status line can say which")
    ok(st.zoneStyled[a] == 1 and st.zoneMade == 1, "styled once when made")
    ok(styledWithProfile(st, a), "with the tracker's own settings, read through DB:Tracker")
    st.T:_UpdateSticky()
    ok(st.zoneStyled[a] == 1 and st.zoneMade == 1 and st.rows == 1,
       "a later step in the same render restyles and makes nothing")
    st.newPass()
    st.T:_UpdateSticky()
    st.T:_UpdateSticky()
    ok(st.zoneStyled[a] == 2 and st.zoneMade == 1, "the next render restyles it once: " .. tostring(st.zoneStyled[a]))
    ok(styledWithProfile(st, a), "with the tracker's own settings again")
end)

-- A look change renders while the incoming copies are hidden, so each has to catch up the next time
-- it is shown, or a zone pushes in drawn the old way.
case("a copy hidden through a render is restyled the next time it is shown, and only then", function()
    local st = zoned()
    st.scrollTo(205)
    st.T:_UpdateSticky()
    local b = zh(st, 2)
    ok(shownKey(st, 2) == "campaign:B" and st.zoneStyled[b] == 1, "the incoming zone is styled when first shown")
    st.scrollTo(0)
    st.T:_UpdateSticky()
    ok(shownKey(st, 2) == nil, "and hidden once the push is over")
    st.newPass()
    st.T:_UpdateSticky()
    ok(st.zoneStyled[b] == 1, "a render while it is hidden leaves it alone")
    st.scrollTo(205)
    st.T:_UpdateSticky()
    ok(shownKey(st, 2) == "campaign:B" and st.zoneStyled[b] == 2,
       "shown again after that render, it is restyled: " .. tostring(st.zoneStyled[b]))
    ok(styledWithProfile(st, b), "each time with the tracker's own settings")
    st.scrollTo(206)
    st.T:_UpdateSticky()
    ok(st.zoneStyled[b] == 2, "and not again on the next step")
end)

case("the next zone pushes the current one up inside the row, then takes it", function()
    local st = zoned()
    st.scrollTo(200)
    st.T:_UpdateSticky()
    ok(shownKey(st, 1) == "campaign:A" and dyOf(zh(st, 1)) == 0 and shownKey(st, 2) == nil,
       "a zone exactly at the top pushes nothing yet")
    st.scrollTo(205)
    st.T:_UpdateSticky()
    ok(shownKey(st, 1) == "campaign:A" and dyOf(zh(st, 1)) == 5, "pushed up by 5: " .. tostring(dyOf(zh(st, 1))))
    ok(shownKey(st, 2) == "campaign:B" and dyOf(zh(st, 2)) == 5 - 22 and zh(st, 2).parent == st.band.zoneRow,
       "the next one a row below it, in the row: " .. tostring(dyOf(zh(st, 2))))
    st.scrollTo(221)
    st.T:_UpdateSticky()
    ok(shownKey(st, 1) == "campaign:A" and dyOf(zh(st, 1)) == 21, "still handing over a pixel short")
    st.scrollTo(222)
    st.T:_UpdateSticky()
    ok(shownKey(st, 1) == "campaign:B" and dyOf(zh(st, 1)) == 0 and shownKey(st, 2) == nil,
       "once it has scrolled a whole row under, it takes the row")
    ok(pointsOf(st.band.zoneRow) == "TOPLEFT>band.TOPLEFT(0,-30) TOPRIGHT>band.TOPRIGHT(0,-30)",
       "and the row itself never moved")
end)

case("a section push carries the zone row up and brings the next section's first zone in", function()
    local st = zoned()
    st.scrollTo(410)
    st.T:_UpdateSticky()
    ok(pointsOf(st.band.zoneRow) == "TOPLEFT>band.TOPLEFT(0,-20) TOPRIGHT>band.TOPRIGHT(0,-20)",
       "the row rides up with the section header: " .. pointsOf(st.band.zoneRow))
    ok(shownKey(st, 1) == "campaign:B" and dyOf(zh(st, 1)) == 0, "still showing the section's last zone")
    local c = zh(st, 3)
    ok(shownKey(st, 3) == "quests:C" and c.parent == st.band and c.points[1][2] == st.band,
       "the next section's first zone, in the band itself")
    ok(dyOf(c) == 410 - 430 - 52, "where the list has it: " .. tostring(dyOf(c)))
    ok(dyOf(st.band.heads[2]) == 10 - 52 and dyOf(c) == dyOf(st.band.heads[2]) - 30,
       "one section row under the incoming section header")
    st.scrollTo(451)
    st.T:_UpdateSticky()
    ok(shownKey(st, 3) == "quests:C" and dyOf(c) == 451 - 430 - 52, "a pixel short of the hand-over it is still coming in")
    -- The next section's first zone comes in through slot 3 alone. It never pushes this section's last.
    ok(shownKey(st, 1) == "campaign:B" and dyOf(zh(st, 1)) == 0,
       "the section's last zone holds still in its row: " .. tostring(dyOf(zh(st, 1))))
    ok(shownKey(st, 2) == nil, "and no second copy comes into the row")
    st.scrollTo(452)
    st.T:_UpdateSticky()
    ok(st.T._stickyShown == "quests" and shownKey(st, 1) == "quests:C" and dyOf(zh(st, 1)) == 0,
       "then the next section and its zone hold the band")
    ok(shownKey(st, 3) == nil, "and the incoming copy goes")
    ok(pointsOf(st.band.zoneRow) == "TOPLEFT>band.TOPLEFT(0,-30) TOPRIGHT>band.TOPRIGHT(0,-30)", "the row back in place")
end)

case("under a section with no zones the second row stays empty", function()
    local st = bandRig()
    st.layout({ "campaign", "achievements" }, { 0, 300 }, 52)
    st.zoneLayout({ "campaign:A" }, { -22 }, { 1 }, { 1 }, 30, 22)
    st.scrollTo(400)
    st.T:_UpdateSticky()
    ok(st.T._stickyShown == "achievements" and shownKey(st, 1) == nil and st.T._stickyZone == nil,
       "no zone is shown")
    ok(st.band.zoneRow and st.band.zoneRow.shown, "though the row keeps its place, so the band never resizes")
end)

-- Popup boxes sit above a section's rows, so its first zone header can start below the band.
case("a first zone below the band leaves the row empty until it scrolls under, and nothing raises", function()
    local st = bandRig()
    st.layout({ "campaign", "quests" }, { 0, 400 }, 52)
    st.zoneLayout({ "campaign:A", "campaign:B", "quests:C" }, { 30, 200, 430 }, { 1, 3 }, { 2, 3 }, 30, 22)
    st.scrollTo(0)
    local good, err = pcall(function() st.T:_UpdateSticky() end)
    ok(good and shownKey(st, 1) == nil and st.T._stickyZone == nil,
       "no zone in the row yet: " .. tostring(err))
    st.scrollTo(52)
    st.T:_UpdateSticky()
    ok(shownKey(st, 1) == "campaign:A", "then the first zone takes it: " .. tostring(shownKey(st, 1)))
end)

-- Render never wipes the band's zone keys, so a key past this pass's last zone is a leftover. Here
-- quests:D was drawn this pass at index 2 and is still listed at index 3 from the pass before.
case("a section with no zones never brings in a zone key left from an earlier pass", function()
    local st = bandRig()
    st.layout({ "campaign", "quests", "achievements" }, { 0, 400, 700 }, 52)
    st.zoneLayout({ "quests:C", "quests:D", "quests:D" }, { 430, 500, 999 }, { 1, 1, 3 }, { 0, 2, 2 }, 30, 22)
    st.scrollTo(710)
    st.T:_UpdateSticky()
    ok(st.T._stickyShown == "quests" and shownKey(st, 1) == "quests:D" and shownKey(st, 3) == nil,
       "Achievements comes in with no zone under it: " .. tostring(shownKey(st, 3)))
end)

-- _UpdateStickyZones reads the band's zone arrays off the frame, so Render must keep them there.
-- Its block is sliced from the first read to the section loop and run twice on one frame.
case("Render keeps the band's zone arrays on the frame, each under its own name", function()
    local src = trackerSlice("    local zKeys, zTops, zFirst, zLast = f._stickyZKeys",
                             "    for _, groupID in ipairs(Sections:Order()) do")
    local chunk = assert(loadstring(src .. "\nreturn zKeys, zTops, zFirst, zLast", "zone-arrays"))
    local f = {}
    local function wipe(t) for k in pairs(t) do t[k] = nil end return t end
    setfenv(chunk, setmetatable({ f = f, wipe = wipe }, { __index = _G }))
    local keys, tops, first, last = chunk()
    ok(type(keys) == "table" and f._stickyZKeys == keys and f._stickyZTops == tops and f._stickyZFirst == first
       and f._stickyZLast == last, "the first pass stores the four arrays it fills")
    first[1], last[1] = 1, 2
    local _, _, first2, last2 = chunk()
    ok(f._stickyZFirst == first2 and f._stickyZLast == last2 and first2[1] == nil and last2[1] == nil,
       "a later pass starts each section's zone runs empty")
end)

case("without clipping a zone swaps in place and the next section's never shows early", function()
    local st = zoned({ noClip = true })
    st.scrollTo(205)
    st.T:_UpdateSticky()
    ok(shownKey(st, 1) == "campaign:A" and dyOf(zh(st, 1)) == 0 and shownKey(st, 2) == nil, "no push in the row")
    ok(st.band.zoneRow.clips == nil, "and the row asks for no clipping it cannot have")
    st.scrollTo(410)
    st.T:_UpdateSticky()
    ok(shownKey(st, 3) == nil, "no incoming zone")
    ok(pointsOf(st.band.zoneRow) == "TOPLEFT>band.TOPLEFT(0,-30) TOPRIGHT>band.TOPRIGHT(0,-30)", "and the row stays put")
end)

case("a zone that drew no header leaves its slot empty", function()
    local st = zoned()
    st.zoneSrc["campaign:A"] = nil
    st.scrollTo(0)
    st.T:_UpdateSticky()
    ok(shownKey(st, 1) == nil and (zh(st, 1) == nil or not zh(st, 1).shown), "nothing copied, nothing shown")
    ok(next(st.zoneStyled) == nil, "and an empty copy is never styled")
end)

case("the zone row goes when zones stop being drawn, the band goes, or the option does", function()
    local st = zoned()
    st.scrollTo(205)
    st.T:_UpdateSticky()
    st.f._stickyZoned = false
    st.T:_UpdateSticky()
    ok(not zh(st, 1).shown and not zh(st, 2).shown and not st.band.zoneRow.shown and st.T._stickyZone == nil,
       "no zone drawn this pass: every copy and the row hidden")
    local line = st.T:StickyLine()
    ok(line:find(", zone row off$") ~= nil, "the status line says the row is off: " .. line)
    st.f._stickyZoned = true
    st.T:_UpdateSticky()
    ok(st.band.zoneRow.shown and shownKey(st, 1) == "campaign:A", "zones drawn again: the row comes back with its zone")
    local st2 = zoned()
    st2.scrollTo(410)
    st2.T:_UpdateSticky()
    st2.f._stickyAnchored = false
    st2.T:_UpdateSticky()
    ok(not zh(st2, 1).shown and not zh(st2, 3).shown and not st2.band.zoneRow.shown, "the option off: all hidden")
    local st3 = zoned()
    st3.scrollTo(0)
    st3.T:_UpdateSticky()
    st3.f._stickyN = 0
    st3.T:_UpdateSticky()
    ok(not zh(st3, 1).shown and not st3.band.zoneRow.shown, "nothing drawn: all hidden")
    st3.f._stickyN = 2
    st3.T:_UpdateSticky()
    ok(st3.T:StickyLine():find(", zone campaign:A$") ~= nil, "and names the zone it shows: " .. st3.T:StickyLine())
    ok(st3.band.zoneRow.shown and shownKey(st3, 1) == "campaign:A", "sections drawn again: the row comes back")
end)

case("the docked zone bar section gives its header to the band", function()
    local st = bandRig({ zone = "Elwynn Forest" })
    local added, drawn = st.T:_RenderZoneSection({}, "zoneprogress", 40, 2, false)
    local h = st.Sections.frames.zoneprogress
    ok(drawn == true and added == 26 + 2 + 20 + 2, "in the list: header, gap, bar, gap: " .. tostring(added))
    ok(h.shown and st.docked[1] == 40 + 26 + 2, "header shown and the bar under it: " .. tostring(st.docked[1]))

    st = bandRig({ zone = "Elwynn Forest" })
    added, drawn = st.T:_RenderZoneSection({}, "zoneprogress", 0, 2, true)
    h = st.Sections.frames.zoneprogress
    ok(drawn == true and added == 20 + 2, "in the band: the list gets the bar alone: " .. tostring(added))
    ok(not h.shown, "its header is hidden")
    ok(st.docked[1] == 0, "and the bar starts the list: " .. tostring(st.docked[1]))
    ok(h.text.text == "Elwynn Forest" and h.count.text == "3/10", "the hidden header still carries what the band copies")

    st = bandRig({ zone = "Elwynn Forest", collapsed = { zoneprogress = true } })
    added, drawn = st.T:_RenderZoneSection({}, "zoneprogress", 0, 2, true)
    ok(drawn == true and added == 0, "collapsed in the band, nothing in the list and still drawn")
    ok(st.hideDocked == 1, "and the docked bar is hidden")

    st = bandRig()
    added, drawn = st.T:_RenderZoneSection({}, "zoneprogress", 0, 2, true)
    ok(added == 0 and drawn == false, "no zone, nothing drawn")
end)

-- ------------------------------------------------------------- the opacity hover, driven

local hoverSrc = slicer("UI/Visibility.lua")("local function over(r)", "local function fadeTarget()")
    .. "\nreturn mouseOverDrawn"

case("the band's headers count as drawn for the mouseover", function()
    local function region(visible, over)
        return { IsVisible = function() return visible end, IsMouseOver = function() return over end }
    end
    local env = setmetatable({ ns = { GetModule = function() return { IsLocked = function() return true end } end } },
                             { __index = _G })
    local chunk = assert(loadstring(hoverSrc, "visibility-hover"))
    setfenv(chunk, env)
    local drawn = chunk()
    local off = region(true, false)
    local f = { drag = off, scenarioContainer = off, eventsRegion = off, scroll = off, content = off, grip = off }
    ok(drawn(f) == false, "nothing hovered, nothing drawn")
    f.stickyBand = { heads = { region(true, true) } }
    ok(drawn(f) == true, "over the band's header")
    f.stickyBand = { heads = { region(true, false), region(true, true) } }
    ok(drawn(f) == true, "over the incoming header")
    f.stickyBand = { heads = { region(false, true) } }
    ok(drawn(f) == false, "a hidden header does not count")
    f.stickyBand = { heads = {} }
    ok(drawn(f) == false, "nor does an empty band")
    for slot = 1, 3 do
        local zones = {}
        zones[slot] = region(true, true)
        f.stickyBand = { heads = {}, zoneHeads = zones }
        ok(drawn(f) == true, "over the band's zone header in slot " .. slot)
    end
    f.stickyBand = { heads = {}, zoneHeads = { region(false, true) } }
    ok(drawn(f) == false, "a hidden zone header does not count")
end)

-- ------------------------------------------------- Render and the wiring, by whole statement

local renderSrc = stripComments(trackerSlice("function Tracker:Render()",
                                             "local TICK_SLOW, TICK_FAST, FAST_WINDOW"))
local buildSrc  = stripComments(trackerSlice("function Tracker:BuildFrame()",
                                             "local function setScrollBarHidden(sf, hidden)"))

local function has(src, stmt, msg) ok(count(src, stmt) == 1, msg .. " (" .. count(src, stmt) .. ")") end

has(renderSrc, "local sticky = f._stickyAnchored and f.stickyBand",
    "Render lays out for the anchored chain")
ok(count(renderSrc, "stickySectionHeaders") == 0, "and never reads the live setting")
has(renderSrc, [[
                if sticky and stickyN == 1 then
                    header:Hide()
                else
                    y = y + headerH + gap
                end]], "the first section's header is hidden instead of spaced, every other one spaced")
has(renderSrc, [[
                stickyN = stickyN + 1
                stickyIDs[stickyN], stickyTops[stickyN] = groupID, y
                local headerH = Sections:Place(header, content, y, group, collapsed,
                                               cfg and cfg.showQuestTotal ~= false, popupCount)]],
    "an ordinary section is recorded at its top before it is placed")
has(renderSrc, [[
            local added, drawn = self:_RenderZoneSection(content, groupID, y, gap,
                                                         sticky and stickyN == 0)
            if drawn then
                sectionTops[#sectionTops + 1] = top
                stickyN = stickyN + 1
                stickyIDs[stickyN], stickyTops[stickyN] = groupID, top
            end
            y = y + added]], "the zone bar section is asked to use the band only when it comes first")
has(renderSrc, "local stickyN = 0", "the count starts from zero each pass")
has(renderSrc, [[
    f._stickyN = sticky and stickyN or 0
    if sticky then
        local row1 = Sections:Height() + gap
        local row2 = (stickyZ > 0) and (ZoneHeaders:Height() + gap) or 0
        bandH = (stickyN > 0) and (row1 + row2) or 1
        f._stickyH, f._stickyRow1, f._stickyRow2, f._stickyZoned = bandH, row1, row2, stickyZ > 0
        if math.abs((sticky:GetHeight() or 0) - bandH) > 0.5 then
            setRegionHeight(sticky, bandH)
        end
    end]], "the band is a header and a gap tall, and a zone row more while any zone header is drawn, "
           .. "through the combat-safe setter")
has(renderSrc, [[
    wipe(zFirst)
    wipe(zLast)
    local stickyZ = 0
]], "the zone runs each section owns are cleared, and the zone count started, every pass")
-- A shown-only restyle here is what left a hidden copy in the old look, so it must not come back.
ok(count(renderSrc, "ZoneHeaders:ApplyStyle") == 0, "Render styles no zone copy itself, the band does once per render")
has(renderSrc, "local scrollH = math.min(questContentH, available - (wqH or 0) - bandH)",
    "the list gives the band's height up")
has(renderSrc, "local bandH = 0", "and gives up nothing with the option off")

local upd   = renderSrc:find("self:_UpdateSticky()", 1, true)
local clamp = renderSrc:find("clampScroll(f.scroll)", 1, true)
local style = renderSrc:find("for i = 1, (heads and #heads or 0) do Sections:ApplyStyle(heads[i]) end", 1, true)
local sweep = renderSrc:find("RowPool:Sweep(_resetRow)", 1, true)
ok(count(renderSrc, "self:_UpdateSticky()") == 1 and upd and clamp and upd > clamp,
   "the band is updated once, after the scroll is clamped")
ok(style and upd and sweep and style > upd and style < sweep,
   "and its headers styled after that, before the sweep")

has(buildSrc, [[scroll:HookScript("OnVerticalScroll", function() Tracker:_UpdateSticky() end)]],
    "every scroll step updates the band")
has(buildSrc, "if stickyBand.SetClipsChildren then stickyBand:SetClipsChildren(true) end",
    "the band clips where the client can")
local made   = buildSrc:find("f.stickyBand = stickyBand", 1, true)
local anchor = buildSrc:find("self:ApplyWorldQuestsPosition()", 1, true)
ok(made and anchor and made < anchor, "the band exists before the first anchoring pass")

has(stripComments(readFile("UI/Commands.lua")), [[debugLine("Tracker", nil, "StickyLine")]],
    "/eqot status prints the line")
has(readFile("Core/DB.lua"), "            stickySectionHeaders = true,\n", "the option ships on (the author's call for 2.1.0)")

print(("test_sticky_headers: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
