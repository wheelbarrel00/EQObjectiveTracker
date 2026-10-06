-- Unit tests for UI/TrackerPreview.lua, and for the three splits in shipped code it draws through,
-- run against the SHIPPED source. Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_preview.lua
--
-- The preview is a small tracker on the Appearance tab's panel, drawn by the tracker's own code from
-- made-up quests (EverythingUI phase 1b, the author's calls of 2026-10-02).
-- Part one loads the preview over stub modules that record every call: which sections it draws and
-- in what order, the samples it hands Row, the header counts, the zone section, the gaps, the view it
-- leaves for the scroll bar, the fit to the panel, the opacity, the skins, and that nothing it builds
-- answers the mouse or borrows the tracker's pooled rows and headers. With zone headers on, each
-- sample zone's header is drawn, left shown across refreshes, and hidden once the option goes off.
--
-- Part two loads the REAL UI/Tracker.lua, UI/Sections.lua and UI/ZoneProgressBar.lua and drives the
-- methods the preview needs from them: the backdrop and scroll bar skins, the gutter, the insets, a
-- header outside the pool, and a docked bar of the preview's own. The tracker's own paths through
-- those methods are checked unchanged beside them, since they were split out of shipped code.
--
-- OUT OF SCOPE BY CONSTRUCTION: what a row looks like. Row:Render draws it, and the row harnesses own
-- that.

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
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

local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.001 end

local timers = {}

local function region(kind, parent)
    local r = { kind = kind, parent = parent, points = {}, shown = true, visible = true, scripts = {},
                children = {}, level = parent and ((parent.level or 1) + 1) or 1 }
    function r:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function r:ClearAllPoints() self.points = {} end
    function r:SetAllPoints(rel) self.points = { { "ALL", rel } } end
    function r:SetSize(w, h) self.w, self.h = w, h end
    function r:SetWidth(w) self.w = w end
    function r:SetHeight(h) self.h = h end
    function r:GetWidth() return self.w or 0 end
    function r:GetHeight() return self.h or 0 end
    function r:Show() self.shown = true end
    function r:Hide() self.shown = false end
    function r:SetShown(v) self.shown = v and true or false end
    function r:IsShown() return self.shown end
    function r:IsVisible() return self.visible and self.shown end
    function r:SetParent(p) self.parent = p end
    function r:GetParent() return self.parent end
    function r:SetScale(s) self.scale = s end
    function r:GetScale() return self.scale or 1 end
    function r:SetAlpha(a) self.alpha = a end
    function r:SetFrameLevel(l) self.level = l end
    function r:GetFrameLevel() return self.level end
    function r:EnableMouse(v) self.mouse = v end
    function r:EnableMouseWheel(v) self.wheel = v end
    function r:SetScript(e, fn) self.scripts[e] = fn end
    function r:HookScript(e, fn) self.hooks = self.hooks or {} self.hooks[e] = fn end
    function r:RegisterForClicks() end
    function r:SetColorTexture(r1, g, b, a) self.color = { r1, g, b, a } end
    function r:SetTexture(t) self.texture = t end
    function r:GetTexture() return self.texture end
    function r:GetAtlas() return nil end
    function r:SetText(s) self.text = s end
    function r:GetText() return self.text end
    function r:SetTextColor() end
    function r:CreateTexture() local t = region("Texture", self) return t end
    function r:CreateFontString() local fs = region("FontString", self) return fs end
    function r:CreateMaskTexture() return region("MaskTexture", self) end
    function r:SetBackdrop(b) self.backdrop = b self.backdropCalls = (self.backdropCalls or 0) + 1 end
    function r:SetBackdropColor(...) self.backdropColor = { ... } end
    function r:SetBackdropBorderColor(...) self.borderColor = { ... } end
    function r:SetStatusBarTexture(t) self.barTexture = t end
    function r:SetStatusBarColor(...) self.barColor = { ... } end
    function r:SetMinMaxValues(a, b) self.min, self.max = a, b end
    function r:SetValue(v) self.value = v end
    function r:SetScrollChild(c) self.child = c end
    function r:SetVerticalScroll(v) self.vscroll = v end
    function r:GetVerticalScroll() return self.vscroll or 0 end
    function r:GetVerticalScrollRange() return self.range or 0 end
    function r:UpdateScrollChildRect() self.rectUpdates = (self.rectUpdates or 0) + 1 end
    if parent and parent.children then parent.children[#parent.children + 1] = r end
    return r
end

local function newCreateFrame(log)
    return function(kind, name, parent, template)
        local f = region(kind, parent)
        f.name, f.template = name, template
        if template == "UIPanelScrollFrameTemplate" then
            f.ScrollBar = region("Slider", f)
            f.ScrollBar.thumb = region("Texture", f.ScrollBar)
            function f.ScrollBar:GetThumbTexture() return self.thumb end
            f.ScrollBar.ScrollUpButton = region("Button", f.ScrollBar)
            f.ScrollBar.ScrollDownButton = region("Button", f.ScrollBar)
        end
        if log then log[#log + 1] = f end
        return f
    end
end

local function loadInto(rel, ns, env)
    local chunk = assert(loadfile(repoFile(rel)))
    setfenv(chunk, setmetatable(env, { __index = _G }))
    chunk("EQObjectiveTracker", ns)
end

local function newNs()
    local modules = {}
    local ns = { modules = modules, L = setmetatable({}, { __index = function(_, k) return k end }),
                 Util = {}, Has = {} }
    function ns:RegisterModule(name, m) modules[name] = m return m end
    function ns:GetModule(name) return modules[name] end
    function ns:UsesBlizzardTracker() return self.blizzard == true end
    return ns
end

local QC = { Normal = 0, Campaign = 2 }

local function previewWorld(o)
    o = o or {}
    local ns = newNs()
    local m = ns.modules
    loadInto("Data/Entry.lua", ns, {})
    local log = { headers = {}, place = {}, rows = {}, built = 0, resets = 0, render = {},
                  skins = {}, docked = {}, bars = 0, frames = {}, zoneHeads = {}, zoneDraws = {} }
    local cfg = o.cfg or { width = 305, blockSpacing = 2 }
    log.cfg = cfg
    m.DB = strictDB({ Tracker = function() return cfg end })
    -- Writes the shared height as the real ApplyStyle does, so the preview's restore is seen. Has no
    -- Place and no pool: the preview must reach neither.
    m.ZoneHeaders = {
        NewHeader = function(_, parent)
            local h = region("Button", parent)
            h.mouse = true
            log.zoneHeads[#log.zoneHeads + 1] = h
            return h
        end,
        Draw = function(self, h, content, groupID, run, y, c)
            log.zoneDraws[#log.zoneDraws + 1] = { h = h, content = content, groupID = groupID, zone = run.zone,
                                                  count = run.count, total = run.total, y = y, cfg = c }
            self._h = 20
            log.zoneHeightWrites = (log.zoneHeightWrites or 0) + 1
            h:Show()
            return 20, false
        end,
        Indent = function(_, c) return c.zoneHeaders and (c.zoneHeaderIndent or 8) or 0 end,
    }
    m.Tracker = {
        Insets = function() return 4, 14, 16 end,
        ScrollGutter = function(_, c) return c.hideScrollBar and 8 or 26 end,
        SkinBackdrop = function(_, bg, background, c) log.skins[#log.skins + 1] = { "backdrop", bg, background, c } end,
        SkinScroll = function(_, sf, barBG, c) log.skins[#log.skins + 1] = { "scroll", sf, barBG, c } end,
    }
    m.Sections = {
        Order = function() return o.order or { "zoneprogress", "campaign", "quests", "bonusobjectives" } end,
        IsVirtual = function(_, id) return id == "zoneprogress" end,
        IsHidden = function(_, id) return (o.hidden or {})[id] == true end,
        NewHeader = function(_, parent, id)
            local h = region("Button", parent)
            h.groupID, h.text, h.count = id, region("FontString", h), region("FontString", h)
            h.text.text = "title:" .. id
            log.headers[#log.headers + 1] = h
            return h
        end,
        -- Writes the shared height as the real ApplyStyle does, so the preview's restore is seen.
        Place = function(self, h, content, y, group, collapsed, showTotal)
            log.place[#log.place + 1] = { h = h, content = content, y = y, group = group,
                                          collapsed = collapsed, showTotal = showTotal }
            self._h = o.headerH or 26
            log.heightWrites = (log.heightWrites or 0) + 1
            return o.headerH or 26
        end,
    }
    m.Row = {
        Build = function()
            log.built = log.built + 1
            local r = region("Frame", nil)
            r.mouse = true
            log.rows[#log.rows + 1] = r
            return r
        end,
        Reset = function(_, row) log.resets = log.resets + 1 row.resetBefore = true end,
        -- Records a followed row's probe as the real Render does, so the preview's restore is seen.
        Render = function(self, row, entry, width, c)
            if entry.isFocused then
                self._focusIcon, self._focusIconAt = "id=" .. tostring(entry.id), 9
                log.probeWrites = (log.probeWrites or 0) + 1
            end
            log.render[#log.render + 1] = { row = row, entry = entry, width = width, cfg = c,
                                            reset = row.resetBefore }
            row.resetBefore = nil
            return o.rowH or 40
        end,
    }
    m.Card = {
        State = function(_, c) return c.blockLayout == "card" end,
        Gap = function(_, base, on) if on then return math.max(base, 4) end return base end,
    }
    m.ZoneProgressBar = {
        IsDocked = function() return o.docked == true end,
        BuildDockedBar = function(_, parent)
            log.bars = log.bars + 1
            return region("StatusBar", parent)
        end,
        DrawDocked = function(_, bar, content, y, done, total)
            log.docked[#log.docked + 1] = { bar = bar, content = content, y = y, done = done, total = total }
            bar:Show()
            return 18
        end,
    }
    m.Registry = { Get = function(_, id)
        if id ~= "quests" or o.noProvider then return nil end
        return { groups = o.groups or { "campaign", "quests" } }
    end }
    local env = {
        CreateFrame = newCreateFrame(log.frames),
        Enum = { QuestClassification = QC },
        UnitLevel = function() return 60 end,
        time = function() return 1000 end,
        C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end },
        BackdropTemplateMixin = {},
    }
    loadInto("UI/TrackerPreview.lua", ns, env)
    local P = m.TrackerPreview
    local panel = region("Frame", nil)
    panel.w, panel.h = 320, o.panelH or 600
    log.panel, log.P, log.ns = panel, P, ns
    return log
end

local function built(o)
    local w = previewWorld(o)
    w.P:Build(w.panel)
    return w
end

local function placesOf(w)
    local out = {}
    for _, p in ipairs(w.place) do out[#out + 1] = p.h.groupID end
    return table.concat(out, ",")
end

case("the preview is a tracker-shaped frame on the panel, built once", function()
    local w = built()
    local P = w.P
    ok(P.box and P.box.parent == w.panel, "a frame of its own on the library's panel")
    ok(P.bg and P.bg.parent == P.box and P.bg.template == "BackdropTemplate", "a backdrop frame in it, as the tracker has")
    ok(P.bg.points[1][1] == "ALL" and P.bg.points[1][2] == P.box, "covering the frame")
    ok(P.bg.level == P.box.level, "at the frame's own level, under the scroll frame")
    ok(P.background and P.background.parent == P.bg and not P.background.shown, "a background texture, hidden until a skin shows it")
    ok(P.scroll and P.scroll.kind == "ScrollFrame" and P.scroll.template == "UIPanelScrollFrameTemplate"
       and P.scroll.parent == P.box, "the same template scroll frame the tracker uses")
    ok(P.content and P.scroll.child == P.content, "with a content child")
    ok(P.scroll.wheel == true and type(P.scroll.scripts.OnMouseWheel) == "function", "that scrolls with the wheel")
    local bar = P.scroll.ScrollBar
    ok(P.barBG and P.barBG.points[1][2] == bar and P.barBG.points[1][1] == "TOPLEFT" and P.barBG.points[1][4] == -1
       and P.barBG.points[2][2] == bar and P.barBG.points[2][4] == 1 and not P.barBG.shown,
       "and a track texture hugging its bar, hidden until a skin shows it")
    local n = #w.frames
    P:Build(w.panel)
    ok(#w.frames == n, "building again builds nothing")
end)

case("the wheel scrolls within the range and not past it", function()
    local w = built()
    local sf = w.P.scroll
    local wheel = sf.scripts.OnMouseWheel
    sf.range = 0
    wheel(sf, -1)
    ok(sf:GetVerticalScroll() == 0, "nothing to scroll, nothing moves")
    sf.range = 60
    wheel(sf, -1)
    ok(sf:GetVerticalScroll() == 24, "a notch down scrolls 24")
    wheel(sf, -5)
    ok(sf:GetVerticalScroll() == 60, "and stops at the end")
    wheel(sf, 9)
    ok(sf:GetVerticalScroll() == 0, "and at the top")
end)

case("the sample quests cover each way a row can look", function()
    local w = previewWorld()
    local s = w.P:Samples()
    local STATE, LINE, ICON = w.ns.modules.Entry.STATE, w.ns.modules.Entry.LINE, w.ns.modules.Entry.ICON
    ok(#s.campaign == 1 and #s.quests == 4, "one campaign quest and four quests")
    local seen = {}
    for _, g in ipairs({ "campaign", "quests" }) do
        for _, e in ipairs(s[g]) do
            ok(e.providerID == "quests" and e.groupID == g, e.title .. " is a quest of the " .. g .. " group")
            ok(not seen[e.id] and e.id >= 90001 and e.id <= 90005, e.title .. " has its own id")
            seen[e.id] = true
            ok(e.icon and e.icon.kind == ICON.QUESTPOI, e.title .. " carries a quest marker")
            ok(not e.hasItem and not e.canGroup and not e.expiresAt,
               e.title .. " has no item button, group finder or timer, which belong to the live tracker")
            ok(#e.lines >= 1 and type(e.title) == "string" and e.title ~= "", e.title .. " has a title and a line")
        end
    end
    local camp = s.campaign[1]
    ok(camp.tags.campaign == true and camp.icon.classification == QC.Campaign, "the campaign quest is tagged, for the card tint")
    local wolves, grove, supplies, scout = s.quests[1], s.quests[2], s.quests[3], s.quests[4]
    ok(wolves.addedAt == 1000 and wolves.state == STATE.ACTIVE, "one is new, for the NEW tag")
    ok(grove.lines[1].kind == LINE.PROGRESSBAR and grove.lines[1].current == 45 and grove.lines[1].required == 100,
       "one has a progress bar")
    ok(supplies.state == STATE.COMPLETE and supplies.lines[1].completed == true, "one is complete")
    ok(scout.isFocused == true and scout.subtitle ~= nil, "one is followed and has a zone tag")
    ok(wolves.level == 60 and grove.level == 63 and supplies.level == 56,
       "levels around the player's, so the difficulty colors differ")
    ok(s.quests[1] ~= w.P:Samples().quests[1], "made fresh each time, so the clock and level stay current")
    ok(wolves.zone == "Ashwood Glen" and grove.zone == "Ashwood Glen" and supplies.zone == "Northern Vale"
       and scout.zone == "Northern Vale" and camp.zone == "Northern Vale",
       "the quests sit in two zones, each zone's quests together, for the zone headers")
    ok(scout.subtitle == scout.zone, "and the zone tag names the zone the quest sits in")
end)

case("with zone headers on, each sample zone gets a header of the preview's own, its rows indented", function()
    local w = built({ cfg = { width = 305, blockSpacing = 2, zoneHeaders = true, zoneHeaderIndent = 10 } })
    w.P:Refresh()
    local d = w.zoneDraws
    ok(#d == 3, "three zone headers: one in Campaign and two in Quests: " .. #d)
    local seq = {}
    for _, z in ipairs(d) do seq[#seq + 1] = z.groupID .. ":" .. tostring(z.zone) .. "@" .. z.y end
    local y1 = 26 + 2
    local y2 = y1 + 20 + 2 + 40 + 2
    local y3 = y2 + 26 + 2
    local y4 = y3 + 20 + 2 + 40 + 2 + 40 + 2
    local want = ("campaign:Northern Vale@%d quests:Ashwood Glen@%d quests:Northern Vale@%d"):format(y1, y3, y4)
    ok(table.concat(seq, " ") == want, "each zone under its section header, in sample order: " .. table.concat(seq, " "))
    ok(w.place[2] and w.place[2].y == y2, "the Quests section header follows the campaign zone and its row")
    ok(d[2].count == 2 and d[2].total == 2 and d[3].count == 2, "each counts its own two quests")
    ok(d[1].content == w.P.content and d[1].cfg == w.cfg, "drawn into the preview's content with the tracker's settings")
    for _, r in ipairs(w.render) do
        ok(r.width == 279 - 10 and r.row.w == 269 and r.row.points[1][4] == 10,
           "row " .. tostring(r.entry.id) .. " is drawn at the indent and narrowed by it")
    end
    ok(#w.zoneHeads == 3, "three headers made")
    for _, h in ipairs(w.zoneHeads) do
        ok(h.mouse == false and h.parent == w.P.content, "deaf to the mouse, so a click collapses nothing")
    end
    ok(w.render[2].entry.id == 90002 and w.render[3].entry.id == 90003 and w.render[4].entry.id == 90004,
       "the rows follow their zones")
    local shown = 0
    for _, h in ipairs(w.zoneHeads) do if h.shown then shown = shown + 1 end end
    ok(shown == 3, "and every header drawn is left shown: " .. shown)
    w.P:Refresh()
    ok(#w.zoneHeads == 3, "a second refresh reuses them: " .. #w.zoneHeads)
    shown = 0
    for _, h in ipairs(w.zoneHeads) do if h.shown then shown = shown + 1 end end
    ok(shown == 3, "and leaves them shown: " .. shown)
    ok(w.P.content.h == y4 + 20 + 2 + 40 + 2 + 40 + 2, "the content counts every zone header: " .. tostring(w.P.content.h))
end)

case("zone headers switched off in the preview go, and the rows come back to the edge", function()
    local w = built({ cfg = { width = 305, blockSpacing = 2, zoneHeaders = true } })
    w.P:Refresh()
    w.cfg.zoneHeaders = false
    local before = #w.zoneDraws
    w.P:Refresh()
    ok(#w.zoneDraws == before, "nothing more is drawn")
    for _, h in ipairs(w.zoneHeads) do ok(not h.shown, "every zone header is hidden") end
    local last = w.render[#w.render]
    ok(last.width == 279 and last.row.points[1][4] == 0, "and the rows are back at the full width")
end)

case("drawing leaves the zone header height as it found it", function()
    local w = built({ cfg = { width = 305, blockSpacing = 2, zoneHeaders = true } })
    local Z = w.ns:GetModule("ZoneHeaders")
    Z._h = 23
    w.P:Refresh()
    ok((w.zoneHeightWrites or 0) > 0 and Z._h == 23, "the sample headers wrote it, and it was put back: " .. tostring(Z._h))
    Z._h = nil
    w.P:Refresh()
    ok(Z._h == nil, "and where the tracker had drawn none, nothing is left")
end)

case("a refresh draws the sections in the tracker's order, with the samples", function()
    local w = built()
    w.P:Refresh()
    ok(placesOf(w) == "campaign,quests", "campaign then quests, the zone section skipped while not docked: " .. placesOf(w))
    local camp, quests = w.place[1], w.place[2]
    ok(camp.y == 0 and camp.group.visibleCount == 1 and camp.group.totalCount == 4 and camp.collapsed == false
       and camp.showTotal == true and camp.content == w.P.content, "the campaign header at the top, 1 of 4, open, with its total")
    ok(#w.render == 5, "five rows drawn")
    local y = 26 + 2
    ok(w.render[1].entry.groupID == "campaign" and w.render[1].row.points[1][5] == -y, "the campaign row under its header and the gap")
    y = y + 40 + 2
    ok(quests.y == y and quests.group.visibleCount == 4 and quests.group.totalCount == 25, "then the quests header, 4 of 25")
    y = y + 26 + 2
    for i = 2, 5 do
        local r = w.render[i]
        ok(r.row.points[1][1] == "TOPLEFT" and r.row.points[1][2] == w.P.content and r.row.points[1][5] == -y,
           "row " .. i .. " stacks under the one above with the gap")
        y = y + 40 + 2
    end
    for _, r in ipairs(w.render) do
        ok(r.width == 305 - 26 and r.row.w == 279 and r.cfg == w.cfg, "drawn at the tracker's content width with its settings")
        ok(r.reset == true, "reset before it is drawn, so the repaint gate never keeps a stale height")
        ok(r.row.parent == w.P.content and r.row.mouse == false and r.row.shown, "in the preview's content, deaf to the mouse")
    end
    for _, h in ipairs(w.headers) do ok(h.mouse == false, h.groupID .. "'s header ignores the mouse, so a click collapses nothing") end
    ok(w.P.content.w == 279 and w.P.content.h == y, "the content is as tall as what was drawn")
end)

case("drawing leaves the tracker's status probe and header height as it found them", function()
    for _, docked in ipairs({ false, true }) do
        local where = docked and "zone bar docked: " or "zone bar floating: "
        local w = built({ docked = docked })
        local Row, Sections = w.ns:GetModule("Row"), w.ns:GetModule("Sections")
        Row._focusIcon, Row._focusIconAt, Sections._h = "id=4242 real", 77, 31
        w.P:Refresh()
        ok(#w.docked == (docked and 1 or 0), where .. "the zone section drawn only while docked: " .. #w.docked)
        ok((w.probeWrites or 0) > 0 and (w.heightWrites or 0) > 0,
           where .. "the sample's followed quest and its headers did write both")
        ok(Row._focusIcon == "id=4242 real" and Row._focusIconAt == 77,
           where .. "/eqot status still reports the tracker's own followed row: " .. tostring(Row._focusIcon))
        ok(Sections._h == 31,
           where .. "the tracker's world quest region keeps its own header height: " .. tostring(Sections._h))
        Row._focusIcon, Row._focusIconAt, Sections._h = nil, nil, nil
        w.P:Refresh()
        ok(Row._focusIcon == nil and Row._focusIconAt == nil and Sections._h == nil,
           where .. "and where the tracker had drawn nothing, the preview leaves nothing")
    end
end)

case("rows and headers are built once and kept apart from the tracker's pools", function()
    local w = built()
    w.P:Refresh()
    w.P:Refresh()
    ok(w.built == 5 and #w.headers == 2, "five rows and two headers across two refreshes")
    ok(w.ns.modules.RowPool == nil and w.ns.modules.Sections.Acquire == nil,
       "and it never reaches the row pool or the pooled headers, which do not exist here")
end)

case("the order, the client's groups and hidden sections all follow the tracker", function()
    local w = built({ order = { "quests", "campaign" } })
    w.P:Refresh()
    ok(placesOf(w) == "quests,campaign", "the player's own section order: " .. placesOf(w))
    local c = built({ groups = { "quests" } })
    c.P:Refresh()
    ok(placesOf(c) == "quests" and #c.render == 4, "a client with no campaign group shows none")
    local n = built({ noProvider = true })
    n.P:Refresh()
    ok(placesOf(n) == "quests", "with no quest provider the quests section still shows")
    local h = built({ hidden = { quests = true } })
    h.P:Refresh()
    ok(placesOf(h) == "campaign" and #h.render == 1, "a section the player hid is not drawn")
    local o = built({ order = { "zoneprogress", "quests", "bonusobjectives", "profession" } })
    o.P:Refresh()
    ok(placesOf(o) == "quests", "sections with no samples are passed over")
end)

case("rows and headers no longer drawn are hidden", function()
    local o = { hidden = {} }
    local w = built(o)
    w.P:Refresh()
    o.hidden.campaign = true
    w.P:Refresh()
    local campHeader
    for _, hd in ipairs(w.headers) do if hd.groupID == "campaign" then campHeader = hd end end
    local campRow = w.P.rows[90001]
    ok(campHeader and not campHeader.shown and campRow and not campRow.shown, "the hidden section's header and row go")
    ok(w.P.rows[90002].shown, "the rest stay")
end)

case("a section shown again brings its rows back", function()
    local o = { hidden = {} }
    local w = built(o)
    w.P:Refresh()
    o.hidden.campaign = true
    w.P:Refresh()
    o.hidden.campaign = nil
    w.P:Refresh()
    local campRow = w.P.rows[90001]
    ok(campRow and campRow.shown, "the row hidden with its section is drawn again once the section is back")
    ok(w.built == 5, "on the same frame, not a new one: " .. w.built)
end)

case("the docked zone section, only while the bar is docked", function()
    local o = { docked = true }
    local w = built(o)
    w.P:Refresh()
    ok(placesOf(w) == "zoneprogress,campaign,quests", "the zone section first, in the tracker's order: " .. placesOf(w))
    local z = w.place[1]
    ok(z.y == 0 and z.group.visibleCount == 0 and z.group.totalCount == 0 and z.collapsed == false and z.showTotal == false,
       "its header placed open with no total, as the tracker places it")
    ok(z.h.count.text == "7/12", "then given the sample's count")
    ok(z.h.text.text == "title:zoneprogress", "under the section's own translated title")
    local d = w.docked[1]
    ok(d and d.y == 26 + 2 and d.done == 7 and d.total == 12 and d.content == w.P.content, "the bar under it, 7 of 12")
    ok(w.place[2].y == 26 + 2 + 18 + 2, "and the next section under the bar and the gap")
    w.P:Refresh()
    ok(w.bars == 1 and w.docked[2].bar == w.docked[1].bar, "one bar of the preview's own, kept")
    o.docked = false
    w.P:Refresh()
    ok(not w.docked[1].bar.shown and not z.h.shown, "undocked, the bar and its header go")
end)

case("the gap and the header total come from the tracker's settings", function()
    local w = built({ cfg = { width = 305, blockSpacing = 6, showQuestTotal = false } })
    w.P:Refresh()
    ok(w.place[2].y == 26 + 6 + 40 + 6, "Block Spacing between everything: " .. tostring(w.place[2].y))
    ok(w.place[1].showTotal == false, "Show quest total off, so the header counts without it")
    local c = built({ cfg = { width = 305, blockSpacing = 2, blockLayout = "card" } })
    c.P:Refresh()
    ok(c.place[2].y == 26 + 4 + 40 + 4, "cards widen a small gap the way the tracker does")
    local h = built({ cfg = { width = 305, hideScrollBar = true } })
    h.P:Refresh()
    ok(h.render[1].width == 305 - 8, "a hidden scroll bar gives its gutter back to the rows")
end)

case("the view leaves the sample running past it, and the frame fits the panel", function()
    local w = built()
    w.P:Refresh()
    local contentH = 2 * (26 + 2) + 5 * (40 + 2)
    local scale = (320 - 24) / 305
    local avail = (600 - 24) / scale - 14 - 3 - 16
    local view = math.min(avail, math.max(160, contentH - 48))
    local box, sf = w.P.box, w.P.scroll
    ok(near(box.scale, scale), "the tracker's width shrunk to fit the panel: " .. tostring(box.scale))
    ok(box.w == 305 and near(box.h, 14 + 3 + view + 16), "the frame at the tracker's width, as tall as its view needs")
    ok(near(sf.h, view) and sf.w == 279, "a view 48 short of the content, so the bar has something to scroll: " .. tostring(sf.h))
    ok(sf.points[1][1] == "TOPLEFT" and sf.points[1][2] == box and sf.points[1][4] == 4 and sf.points[1][5] == -(14 + 3),
       "the scroll frame where the tracker puts its own")
    ok(box.points[1][1] == "TOP" and box.points[1][2] == w.panel and near(box.points[1][5], -12 / scale),
       "the frame 12 under the top of the panel")
    ok((sf.rectUpdates or 0) >= 1, "the scroll range is brought up to date")

    local wide = built({ cfg = { width = 400 } })
    wide.P:Refresh()
    ok(near(wide.P.box.scale, 296 / 400), "a wider tracker shrinks further")
    local narrow = built({ cfg = { width = 250 } })
    narrow.P:Refresh()
    ok(narrow.P.box.scale == 1, "a narrower one is never enlarged")
    local tiny = built({ cfg = { width = 120 } })
    tiny.P:Refresh()
    ok(tiny.P.box.w == 200, "and never drawn narrower than the tracker can be")

    local tall = built({ rowH = 400 })
    tall.P:Refresh()
    local tAvail = (600 - 24) / scale - 14 - 3 - 16
    ok(near(tall.P.scroll.h, tAvail), "a long sample stops at the panel's height")
    local short = built({ rowH = 4, headerH = 4 })
    short.P:Refresh()
    ok(short.P.scroll.h == 160, "a short one still keeps a usable view")
    local cramped = built({ panelH = 150 })
    cramped.P:Refresh()
    ok(cramped.P.scroll.h < 160, "but never more than the panel holds")
end)

case("the scroll position is kept, but never past the end", function()
    local w = built()
    w.P.scroll.vscroll = 30
    w.P.scroll.range = 50
    w.P:Refresh()
    ok(w.P.scroll.vscroll == 30, "a position inside the range is kept")
    w.P.scroll.range = 10
    w.P:Refresh()
    ok(w.P.scroll.vscroll == 10, "one past it comes back to the end")
end)

case("opacity and the skins come from the tracker's settings", function()
    local w = built({ cfg = { width = 305, trackerAlpha = 0.4 } })
    w.P:Refresh()
    ok(w.P.box.alpha == 0.4, "Tracker Opacity fades the preview")
    local s = w.skins
    ok(#s == 2 and s[1][1] == "backdrop" and s[1][2] == w.P.bg and s[1][3] == w.P.background and s[1][4] == w.cfg,
       "the tracker's own backdrop skin, on the preview's frame")
    ok(s[2][1] == "scroll" and s[2][2] == w.P.scroll and s[2][3] == w.P.barBG and s[2][4] == w.cfg,
       "and its own scroll bar skin, on the preview's scroll frame")
    local d = built()
    d.P:Refresh()
    ok(d.P.box.alpha == 1, "fully solid by default")
end)

case("a refresh made while hidden is drawn once more, once on screen", function()
    for i = #timers, 1, -1 do timers[i] = nil end
    local w = built()
    w.P.box.visible = false
    w.P:Refresh()
    ok(#timers == 1 and #w.render == 5, "drawn now and once more a frame later")
    w.P.box.visible = true
    local fn = table.remove(timers)
    fn()
    ok(#w.render == 10 and #timers == 0, "the second pass draws and asks for no third")
    w.P.box.visible = false
    fn()
    ok(#timers == 0, "even when the panel is still hidden")
    w.P.box.visible = true
    w.P:Refresh()
    ok(#timers == 0, "a refresh on screen asks for nothing later")
end)

case("a refresh before the panel exists does nothing", function()
    local w = previewWorld()
    local good = pcall(w.P.Refresh, w.P)
    ok(good and #w.render == 0, "no frame, no work")
end)

local function trackerFile()
    local ns = newNs()
    ns.modules.DB = strictDB({ Tracker = function() return ns.cfg end })
    loadInto("UI/Tracker.lua", ns, { CreateFrame = newCreateFrame(), InCombatLockdown = function() return false end })
    return ns.modules.Tracker, ns
end

case("Tracker:SkinBackdrop styles any backdrop frame the way the tracker's is styled", function()
    local T = trackerFile()
    local bg, tex = region("Frame"), region("Texture")
    T:SkinBackdrop(bg, tex, { showBackground = true, backgroundColor = { r = 0.1, g = 0.2, b = 0.3, a = 0.4 },
                              showBorder = true, borderColor = { r = 1, g = 0, b = 0, a = 0.5 }, borderSize = 3 })
    ok(tex.shown and tex.color[1] == 0.1 and tex.color[4] == 0.4, "the background in its color")
    ok(bg.backdrop and bg.backdrop.edgeSize == 3 and bg._borderSize == 3, "an edge of the border's thickness, remembered on the frame")
    ok(bg.borderColor[1] == 1 and bg.borderColor[4] == 0.5, "the border in its color")
    T:SkinBackdrop(bg, tex, { showBackground = false, showBorder = false, borderSize = 3 })
    ok(not tex.shown and bg.borderColor[4] == 0 and bg.backdropCalls == 1,
       "off, the background hides and the border goes clear, with no new backdrop for the same thickness")
    T:SkinBackdrop(bg, tex, { borderSize = 0 })
    ok(bg.backdrop.edgeSize == 1 and bg.backdropCalls == 2, "a thickness under 1 draws 1")
    ok(tex.color[1] == 0.1, "the default background color is only applied when shown")
    T:SkinBackdrop(bg, tex, { showBackground = true })
    ok(tex.color[1] == 0 and tex.color[4] == 0.6, "and an unset color falls back to translucent black")
end)

case("Tracker:SkinScroll styles any scroll frame's bar and track", function()
    local T = trackerFile()
    local sf = newCreateFrame()("ScrollFrame", nil, nil, "UIPanelScrollFrameTemplate")
    local track = region("Texture")
    T:SkinScroll(sf, track, { scrollBarBgColor = { r = 0.2, g = 0.3, b = 0.4, a = 0.5 } })
    ok(track.shown and track.color[1] == 0.2 and track.color[4] == 0.5, "the track in its color")
    ok(sf.ScrollBar._eqotHidden == false, "the bar left to its range")
    T:SkinScroll(sf, track, { scrollBarBg = false })
    ok(not track.shown, "the track off")
    T:SkinScroll(sf, track, { hideScrollBar = true })
    ok(not track.shown and sf.ScrollBar._eqotHidden == true and not sf.ScrollBar.shown, "a hidden bar takes its track with it")
    T:SkinScroll(sf, track, { skinScrollBar = true, scrollBarThumbColor = { r = 0.9, g = 0.8, b = 0.7, a = 1 },
                              scrollBarThumbWidth = 10, hideScrollArrows = true })
    local thumb = sf.ScrollBar.thumb
    ok(thumb.color and thumb.color[1] == 0.9 and thumb.w == 10, "a solid thumb in its color and width")
    ok(not sf.ScrollBar.ScrollUpButton.shown and not sf.ScrollBar.ScrollDownButton.shown, "and the arrows hidden")
    local good = pcall(T.SkinScroll, T, sf, nil, {})
    ok(good, "a scroll frame with no track texture is styled too")
end)

case("Tracker:ScrollGutter and Tracker:Insets give the tracker's own numbers", function()
    local T = trackerFile()
    ok(T:ScrollGutter({}) == 26 and T:ScrollGutter({ hideScrollBar = true }) == 8, "26 with the bar, 8 without")
    local pad, top, bottom = T:Insets()
    ok(pad == 4 and top == 14 and bottom == 16, "4 in, under the 14 drag handle, above the 14 grip and 2")
end)

case("the tracker's own frame still skins through the split methods", function()
    local T, ns = trackerFile()
    local f = region("Frame")
    f.bgFrame, f.background = region("Frame", f), region("Texture", f)
    f.scroll = newCreateFrame()("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.eventsScroll = newCreateFrame()("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.scrollBarBG = region("Texture", f)
    f.scenarioContainer = region("Frame", f)
    T.frame = f
    ns.modules.ItemButtons = { Locked = function() return false end }
    ns.cfg = { showBackground = true, showBorder = true, borderSize = 2, hideScrollBar = true }
    T:ApplyFrameSkin(ns.cfg)
    ok(f.background.shown and f.bgFrame.backdrop.edgeSize == 2, "the tracker's background and border")
    ok(f.scroll.ScrollBar._eqotHidden == true and f.eventsScroll.ScrollBar._eqotHidden == true and not f.scrollBarBG.shown,
       "both of its scroll bars, and the track")
end)

local function sectionsFile()
    local ns = newNs()
    ns.modules.DB = strictDB({ Tracker = function() return {} end, Char = function() return {} end })
    ns.modules.Media = { ApplyFont = function() end }
    loadInto("UI/Sections.lua", ns, { CreateFrame = newCreateFrame() })
    return ns.modules.Sections
end

case("Sections:NewHeader builds a header outside the pool", function()
    local S = sectionsFile()
    local parent = region("Frame")
    local h = S:NewHeader(parent, "quests")
    ok(h and h.parent == parent and h.groupID == "quests" and h.text.text == "Quests", "a header for the group, titled")
    ok(h.bar and h.hairline and h.count and h.collapse, "with everything ApplyStyle and Place touch")
    ok(S.frames.quests == nil, "and not put in the pool")
    local pooled = S:Acquire(parent, "quests")
    ok(pooled ~= h and S.frames.quests == pooled and S:Acquire(parent, "quests") == pooled,
       "the tracker's own Acquire still builds one and reuses it")
end)

-- The tracker hides every header before each render and Acquire never shows one, so Place is the
-- only thing that brings a header back, the preview's own headers included.
case("Sections:Place shows the header it places", function()
    local S = sectionsFile()
    local parent = region("Frame")
    for _, h in ipairs({ S:NewHeader(parent, "quests"), S:Acquire(parent, "campaign") }) do
        function h.text:GetStringHeight() return 14 end
        h:Hide()
        S:Place(h, parent, 30, { visibleCount = 2, totalCount = 5 }, false, true)
        ok(h.shown, h.groupID .. ": a hidden header is shown again when it is placed")
        local p = h.points[1] or {}
        ok(p[1] == "TOPLEFT" and p[2] == parent and p[5] == -30, h.groupID .. ": at the y it was handed")
        h:Hide()
        S:Place(h, parent, 0, { visibleCount = 2, totalCount = 5 }, false, true)
        ok(h.shown, h.groupID .. ": and again on the next render, after the next hide")
    end
    S.frames.campaign:Show()
    S:HideAll()
    ok(not S.frames.campaign.shown, "HideAll hides the pooled header, so Place has to show it")
end)

local function zoneFile(o)
    local ns = newNs()
    ns.blizzard = o.blizzard
    local cfg = { showZoneProgressBar = o.on, zoneProgressLocation = o.where }
    ns.modules.DB = strictDB({ Tracker = function() return cfg end })
    ns.modules.Media = { GetStatusBarFile = function() return "bar.tga" end, ApplyFont = function() end }
    loadInto("UI/ZoneProgressBar.lua", ns, { CreateFrame = newCreateFrame(), BackdropTemplateMixin = {} })
    return ns.modules.ZoneProgressBar
end

case("ZoneProgressBar:IsDocked, BuildDockedBar and DrawDocked", function()
    ok(zoneFile({ on = true, where = "tracker" }):IsDocked() == true, "on and in the tracker: docked")
    ok(zoneFile({ on = true, where = "floating" }):IsDocked() == false, "floating: not docked")
    ok(zoneFile({ on = true }):IsDocked() == false, "floating by default")
    ok(zoneFile({ on = false, where = "tracker" }):IsDocked() == false, "off: not docked")
    ok(zoneFile({ on = true, where = "tracker", blizzard = true }):IsDocked() == false,
       "under Blizzard's tracker there is no window to dock in")
    local Z = zoneFile({ on = true, where = "tracker" })
    local content = region("Frame")
    local bar = Z:BuildDockedBar(content)
    ok(bar.kind == "StatusBar" and bar.parent == content and bar.label and bar.bg and bar.border, "a docked bar of its own")
    ok(Z.docked == nil, "not the tracker's cached one")
    local h = Z:DrawDocked(bar, content, 30, 7, 12)
    ok(h == 2 + 12 + 4 and bar.points[1][5] == -(30 + 2) and bar.value and near(bar.value, 7 / 12 * 100)
       and bar.label.text == "58%", "placed under its header, filled to the share, labelled with it")
    local live = Z:RenderDocked(content, 0, 1, 2)
    ok(live == 18 and Z.docked and Z.docked ~= bar, "the tracker's RenderDocked still builds and caches its own")
    local again = Z.docked
    Z:RenderDocked(content, 0, 1, 2)
    ok(Z.docked == again, "and reuses it")
end)

print(("test_preview: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
