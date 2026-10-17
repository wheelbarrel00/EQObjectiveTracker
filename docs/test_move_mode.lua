-- Unit tests for the tracker's move mode, run against the SHIPPED source. Run from the repo root
-- with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_move_mode.lua
--
-- WHY THIS FILE EXISTS. boondox3906 asked on CurseForge (2026-10-15) how to move a tracker that
-- was already unlocked. The only sign was a 15% white tint on an invisible 14 px strip, shown on
-- hover, and the same tint showed on a LOCKED tracker too. The author approved a move mode: while
-- the tracker is unlocked and the options window is open, or after an unlock this session, the
-- strip turns gold with "Drag to move, corner grip to resize." and a check button that locks it,
-- and a gold outline shows the box that moves. A right-click on the strip or the cogwheel opens a
-- lock, reset and options menu, and the hover tint shows only while unlocked.
--
-- What is run: UI/Tracker.lua from "function Tracker:IsLocked()" up to BuildFrame (every move mode
-- method and the two file-local helpers), plus BuildFrame's own build of the drag strip, move bar,
-- outline and cogwheel, sliced by code anchors. The stub frames answer only the methods their
-- widget type has, so a texture call on a frame, or a frame call on a texture, raises here as it
-- would in game.
--
-- OUT OF SCOPE BY CONSTRUCTION: what the game draws (the label's truncation on a narrow tracker,
-- the check texture's look), the drag itself (unchanged), and Options/Frame.lua's two window
-- hooks (docs/test_options_frame.lua). The header pass's call into LayoutMoveBar is
-- docs/test_sort_button.lua's.

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

local function only(src, anchor)
    local at, n, from = nil, 0, 1
    while true do
        local i = src:find(anchor, from, true)
        if not i then break end
        at, n, from = at or i, n + 1, i + 1
    end
    assert(n == 1, ("anchor matched %d times (need exactly 1): %s"):format(n, anchor))
    return at
end

local trackerSrc = readFile("UI/Tracker.lua")

-- The vendored library's own row rules. Its ShowMenu raises on any other field, a field of the
-- wrong type, an unknown kind, or `checked` on a plain row, so the stub below raises on them too.
local MENU_FIELDS, MENU_KINDS = {}, {}
do
    local menuSrc = readFile("Libs/EverythingUI/Menu.lua")
    local fields = menuSrc:match("local ITEM_FIELDS = (%b{})")
    local kinds = menuSrc:match("local KINDS = (%b{})")
    assert(fields and kinds, "Menu.lua's ITEM_FIELDS and KINDS are found")
    for k, v in fields:gmatch("(%w+)%s*=%s*\"(%w+)\"") do MENU_FIELDS[k] = v end
    for k in kinds:gmatch("(%w+)%s*=%s*true") do MENU_KINDS[k] = true end
    assert(MENU_FIELDS.text == "string" and MENU_KINDS.title, "the rule lists read as expected")
end

local function checkMenuRows(items)
    for i, it in ipairs(items) do
        for k, v in pairs(it) do
            if MENU_FIELDS[k] ~= type(v) then error(("menu row %d: field %s"):format(i, tostring(k)), 2) end
        end
        if it.kind and not MENU_KINDS[it.kind] then error(("menu row %d: kind %s"):format(i, it.kind), 2) end
        if it.checked ~= nil and it.kind ~= "check" then error(("menu row %d: checked on a plain row"):format(i), 2) end
    end
end

local methodsSrc
do
    local a = only(trackerSrc, "function Tracker:IsLocked()\n")
    local b = only(trackerSrc, "function Tracker:BuildFrame()\n")
    assert(b > a, "the move mode methods sit above BuildFrame")
    -- LayoutMoveBar measures the left-end buttons through this file-local helper.
    local la = only(trackerSrc, "local function leftButtonX(cfg, pastFilter)\n")
    local lb = only(trackerSrc, "local function makeHeaderIcon(f, texture, tooltip, onClick, anchor)\n")
    assert(lb > la, "leftButtonX sits above makeHeaderIcon")
    methodsSrc = trackerSrc:sub(la, lb - 1) .. trackerSrc:sub(a, b - 1)
end

local buildSrc
do
    local a = only(trackerSrc, '    local drag = CreateFrame("Frame", nil, f)\n')
    local b = only(trackerSrc, "    local function finishDrag()\n")
    assert(b > a, "the strip's build sits above finishDrag")
    buildSrc = trackerSrc:sub(a, b - 1)
end

-- ------------------------------------------------------------------- typed widget stubs

local FRAME, TEXTURE, FONTSTRING = {}, {}, {}

local function region(methods, kind, parent)
    local r = { kind = kind, parent = parent, points = {}, scripts = {}, shown = true }
    return setmetatable(r, { __index = methods })
end

local function newFrame(kind, parent)
    local fr = region(FRAME, kind, parent)
    fr.level = parent and parent.level and parent.level + 1 or 0
    fr.textures, fr.fonts = {}, {}
    return fr
end

function FRAME:SetPoint(...) self.points[#self.points + 1] = { ... } end
function FRAME:ClearAllPoints() self.points = {} end
function FRAME:SetAllPoints(t) self.allPoints = t end
function FRAME:SetHeight(h) self.height = h end
function FRAME:SetSize(w, h) self.width, self.height = w, h end
function FRAME:EnableMouse(on) self.mouse = on end
function FRAME:RegisterForDrag(...) self.dragButtons = { ... } end
function FRAME:SetScript(name, fn) self.scripts[name] = fn end
function FRAME:Show() self.shown = true end
function FRAME:Hide() self.shown = false end
function FRAME:SetShown(v) self.shown = v and true or false end
function FRAME:IsShown() return self.shown end
function FRAME:SetFrameLevel(l) self.level = l end
function FRAME:GetFrameLevel() return self.level end
function FRAME:IsMouseOver() return self.mouseOver == true end
function FRAME:StopMovingOrSizing() self.stopped = (self.stopped or 0) + 1 end
function FRAME:CreateTexture(_, layer)
    local t = region(TEXTURE, "Texture", self)
    t.layer = layer
    self.textures[#self.textures + 1] = t
    return t
end
function FRAME:CreateFontString(_, layer, template)
    local s = region(FONTSTRING, "FontString", self)
    s.layer, s.template = layer, template
    self.fonts[#self.fonts + 1] = s
    return s
end

function TEXTURE:SetPoint(...) self.points[#self.points + 1] = { ... } end
function TEXTURE:SetAllPoints(t) self.allPoints = t or true end
function TEXTURE:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
function TEXTURE:SetTexture(p) self.texture = p end
function TEXTURE:SetVertexColor(r, g, b) self.vertex = { r, g, b } end
function TEXTURE:SetAlpha(a) self.alpha = a end
function TEXTURE:SetWidth(w) self.width = w end
function TEXTURE:SetHeight(h) self.height = h end

function FONTSTRING:SetPoint(...) self.points[#self.points + 1] = { ... } end
function FONTSTRING:ClearAllPoints() self.points = {} end
function FONTSTRING:SetText(s) self.text = s end
function FONTSTRING:SetWordWrap(v) self.wordWrap = v end
function FONTSTRING:SetJustifyH(j) self.justifyH = j end

-- --------------------------------------------------------------------------- the world

local st

local function load(o)
    o = o or {}
    st = { prints = {}, menus = {}, refreshed = {}, toggles = 0, resets = 0, rebuilt = 0,
           tips = {}, created = {}, clickThrough = false }
    local gen
    if not o.noGeneral then gen = { lockTracker = o.locked == true } end
    local trackerCfg = { showSortButton = o.sortOn == true, showFilterButton = o.filterOn == true }
    st.gen, st.trackerCfg = gen, trackerCfg

    local optionsFrame = newFrame("Frame")
    -- A private flag in place of the stub's public field, which no real frame has, so code that
    -- reads the field rather than calling IsShown fails here as it would in game.
    optionsFrame.shown = nil
    optionsFrame._open = o.optionsOpen == true
    function optionsFrame.IsShown(self) assert(self == optionsFrame, "IsShown without self") return self._open end
    function optionsFrame.Show(self) self._open = true end
    function optionsFrame.Hide(self) self._open = false end
    st.raises = 0
    function optionsFrame.Raise(self) assert(self == optionsFrame, "Raise without self") st.raises = st.raises + 1 end
    local Options = {
        frame = optionsFrame,
        RefreshIfShown = function(self, id)
            assert(self.frame == optionsFrame, "RefreshIfShown called with a colon")
            st.refreshed[#st.refreshed + 1] = id
        end,
        Toggle = function(self)
            assert(self == st.Options, "Toggle called with a colon")
            st.toggles = st.toggles + 1
        end,
    }
    if not o.noUI then
        Options.ui = {
            Texture = function(_, name) return "tex:" .. name end,
            ShowMenu = function(_, items, owner)
                checkMenuRows(items)
                st.menus[#st.menus + 1] = { items = items, owner = owner }
            end,
        }
    end
    st.Options = Options

    local tip = {}
    function tip:SetOwner(owner, anchor) st.tips[#st.tips + 1] = { owner = owner, anchor = anchor, lines = {} } end
    function tip:SetText(s) local t = st.tips[#st.tips] t.lines[#t.lines + 1] = s end
    function tip:AddLine(s) local t = st.tips[#st.tips] t.lines[#t.lines + 1] = s end
    function tip:Show() st.tips[#st.tips].shown = true end
    function tip:Hide() st.tipHidden = (st.tipHidden or 0) + 1 end

    -- Strict about self, as the real module's methods are: a dot call raises there.
    local db = {}
    function db.General(self) if self ~= db then error("DB:General called without self", 2) end return gen end
    function db.Tracker(self) if self ~= db then error("DB:Tracker called without self", 2) end return trackerCfg end
    local mods = {
        DB = db,
        Options = Options,
    }
    local ns = {
        GetModule = function(_, n) return mods[n] end,
        Print = function(_, s) st.prints[#st.prints + 1] = s end,
        Util = { Tooltip = function() return tip end },
    }
    local L = setmetatable({}, { __index = function(_, k) return "<" .. k .. ">" end })

    local Tracker = {}
    function Tracker:IsClickThrough() return st.clickThrough end
    function Tracker:ResetPosition() st.resets = st.resets + 1 end
    function Tracker:RebuildHeaderIcons()
        st.rebuilt = st.rebuilt + 1
        st.barAtRebuild = self.frame and self.frame.moveBar ~= nil
    end
    st.Tracker = Tracker

    local env = setmetatable({
        Tracker = Tracker, ns = ns, L = L,
        GOLD_R = 0.92, GOLD_G = 0.72, GOLD_B = 0.02,
        DRAG_HANDLE_H = 14, HEADER_ICON_SZ = 13,
        CreateFrame = function(kind, _, parent)
            local fr = newFrame(kind, parent)
            st.created[#st.created + 1] = fr
            return fr
        end,
        makeHeaderIcon = function(parent, texture, tooltip, onClick)
            local b = newFrame("Button", parent)
            b.texture, b.tooltip, b.onClick = texture, tooltip, onClick
            if texture:find("cogwheel.tga", 1, true) then st.cog = b end
            if texture:find("filter.tga", 1, true) then st.filterIcon = b end
            return b
        end,
    }, { __index = _G })

    local chunk = assert(loadstring(methodsSrc .. "\nreturn function(f, self)\n" .. buildSrc .. "\nend",
                                    "move-mode-slice"))
    setfenv(chunk, env)
    local build = chunk()

    local f = newFrame("Frame")
    f.level = 5
    local grip = newFrame("Button", f)
    function grip:SetAlpha(a) self.alpha = a end
    f.grip = grip
    Tracker.frame = f
    build(f, Tracker)
    st.f = f
    st.drag = f.dragHint and f.dragHint.parent
    return st
end

local function hintAlpha() return st.f.dragHint.color and st.f.dragHint.color[4] end
local function hintIsGold()
    local c = st.f.dragHint.color
    return c and c[1] == 0.92 and c[2] == 0.72 and c[3] == 0.02
end
local function shownBoth() return st.f.moveBar.shown and st.f.moveOutline.shown end
local function hiddenBoth() return not st.f.moveBar.shown and not st.f.moveOutline.shown end

-- ------------------------------------------------------------------------------ the build

case("the strip, the move bar and the outline are built as described", function()
    load()
    local f = st.f
    ok(st.drag and st.drag.kind == "Frame" and st.drag.parent == f, "the drag strip is a frame on the tracker")
    ok(f.dragHint and f.dragHint.kind == "Texture" and f.dragHint.layer == "OVERLAY",
       "the strip's tint is an OVERLAY texture stored on the tracker")
    ok(f.dragHint.color and f.dragHint.color[4] == 0, "and starts clear")

    local bar = f.moveBar
    ok(bar and bar.kind == "Frame" and bar.parent == f, "the move bar is a frame on the tracker")
    ok(bar.level == 16, "eleven levels above the tracker, over the icons at ten: " .. tostring(bar.level))
    ok(bar.height == 14, "as tall as the strip: " .. tostring(bar.height))
    ok(#bar.points == 2 and bar.points[1][1] == "TOPLEFT" and bar.points[2][1] == "TOPRIGHT",
       "spanning the top edge")
    ok(not bar.mouse, "and not mouse-enabled, so a drag on the label reaches the strip")
    ok(bar.shown == false, "built hidden")

    local done = f.moveDone
    ok(done and done.kind == "Button" and done.parent == bar, "the check button sits on the move bar")
    ok(done.width == 13 and done.height == 13, "in the header icons' size")
    local tex = done.textures[1]
    ok(tex and tex.texture == "tex:check", "drawn with the library's check texture: " .. tostring(tex and tex.texture))
    ok(tex and tex.vertex and tex.vertex[1] == 0.45 and tex.vertex[2] == 0.85 and tex.vertex[3] == 0.35,
       "tinted green")
    ok(tex and tex.alpha == 0.85, "at the icons' resting alpha")
    ok(done.scripts.OnClick and done.scripts.OnEnter and done.scripts.OnLeave, "with click and hover scripts")

    local label = f.moveLabel
    ok(label and label.kind == "FontString" and label.parent == bar and label.layer == "OVERLAY",
       "the label is an OVERLAY string on the move bar")
    ok(label.template == "GameFontHighlightSmall", "in the small highlight font: " .. tostring(label.template))
    ok(label.text == "<Drag to move, corner grip to resize.>", "reading the translated hint: " .. tostring(label.text))
    ok(label.wordWrap == false, "on one line")
    ok(label.justifyH == "CENTER", "centered")

    local outline = f.moveOutline
    ok(outline and outline.kind == "Frame" and outline.parent == f and outline.allPoints == f,
       "the outline covers the tracker")
    ok(outline.level == 25, "twenty levels up, over the rows: " .. tostring(outline.level))
    ok(not outline.mouse, "and never takes the mouse")
    ok(outline.shown == false, "built hidden")
    ok(#outline.textures == 4, "four edges: " .. #outline.textures)
    local ones, gold = 0, 0
    for _, e in ipairs(outline.textures) do
        if (e.width == 1 and e.height == nil) or (e.height == 1 and e.width == nil) then ones = ones + 1 end
        local c = e.color
        if c and c[1] == 0.92 and c[2] == 0.72 and c[3] == 0.02 and c[4] == 0.9 then gold = gold + 1 end
    end
    ok(ones == 4, "each one pixel thick, in one direction only: " .. ones)
    ok(gold == 4, "each gold at 0.9: " .. gold)
    local sides = {}
    for _, e in ipairs(outline.textures) do
        sides[#sides + 1] = e.points[1][1] .. "-" .. e.points[2][1] .. (e.width and ":w" or ":h")
    end
    table.sort(sides)
    ok(table.concat(sides, ",") == "BOTTOMLEFT-BOTTOMRIGHT:h,TOPLEFT-BOTTOMLEFT:w,TOPLEFT-TOPRIGHT:h,TOPRIGHT-BOTTOMRIGHT:w",
       "top and bottom run across, left and right run down: " .. table.concat(sides, ","))

    ok(st.rebuilt == 1 and st.barAtRebuild == true, "the header pass runs once, after the move bar exists")
    ok(st.cog and st.cog.scripts.OnMouseUp ~= nil, "the cogwheel answers a mouse release")
    ok(st.drag.scripts.OnMouseUp ~= nil and st.drag.scripts.OnMouseUp == st.cog.scripts.OnMouseUp,
       "with the same right-click handler as the strip")
end)

-- ------------------------------------------------------------------ when move mode shows

case("move mode follows the lock, the options window and an unlock this session", function()
    load()
    local T = st.Tracker
    T:ApplyLockState()
    ok(T:InMoveMode() == false and hiddenBoth(), "loaded unlocked with the options closed: no move mode")
    st.Options.frame._open = true
    T:ApplyMoveMode()
    ok(T:InMoveMode() == true and shownBoth(), "the options window opens: move mode")
    ok(hintIsGold() and hintAlpha() == 0.35, "the strip turns gold at 0.35")
    st.Options.frame._open = false
    T:ApplyMoveMode()
    ok(T:InMoveMode() == false and hiddenBoth(), "it closes: gone again")
    ok(hintAlpha() == 0, "and the strip clears")

    st.gen.lockTracker = true
    T:ApplyLockState()
    st.Options.frame._open = true
    T:ApplyMoveMode()
    ok(T:InMoveMode() == false and hiddenBoth(), "locked, an open options window shows nothing")
    st.Options.frame._open = false

    st.gen.lockTracker = false
    T:ApplyLockState()
    ok(T:InMoveMode() == true and shownBoth(), "an unlock after a lock starts move mode with the options closed")
    T:ApplyMoveMode()
    ok(shownBoth(), "and it stays up on the next apply")
    st.gen.lockTracker = true
    T:ApplyLockState()
    ok(T:InMoveMode() == false and hiddenBoth(), "the next lock ends it")
    st.gen.lockTracker = false
    T:ApplyLockState()
    ok(T:InMoveMode() == true, "and the next unlock starts it again")
end)

case("an unlock asked for on an unlocked tracker still starts move mode", function()
    load()
    local T = st.Tracker
    T:ApplyLockState()
    ok(T:InMoveMode() == false, "loaded unlocked: no move mode")
    T:ApplyLockState()
    ok(T:InMoveMode() == false, "another plain apply is no unlock")
    T:ApplyLockState(true)
    ok(T:InMoveMode() == true and shownBoth(), "the slash command's apply starts it")
end)

case("a lock stops a drag in progress and hides the grip", function()
    load()
    local T, f = st.Tracker, st.f
    f._dragging = true
    st.gen.lockTracker = true
    T:ApplyLockState()
    ok(f.stopped == 1 and f._dragging == nil, "the drag is stopped")
    ok(f.grip.alpha == 0 and f.grip.mouse == false, "the grip is hidden and lets the mouse through")
    st.gen.lockTracker = false
    T:ApplyLockState()
    ok(f.grip.alpha == 1 and f.grip.mouse == true, "unlocked, it shows and takes the mouse")
end)

case("no tracker frame, or one built without the move bar, is passed over", function()
    load()
    local T = st.Tracker
    T.frame = nil
    ok(pcall(function() T:ApplyLockState() T:ApplyMoveMode() T:LayoutMoveBar() end), "no frame: nothing raises")
    ok(T:InMoveMode() == false, "and there is no move mode")
    T.frame = newFrame("Frame")
    ok(pcall(function() T:ApplyMoveMode() T:LayoutMoveBar() end), "a frame with no move bar: nothing raises")
end)

-- ---------------------------------------------------------------------------- the strip tint

case("the strip's hover tint shows only while unlocked, and gold in move mode", function()
    load()
    local T, drag = st.Tracker, st.drag
    T:ApplyLockState()
    drag.scripts.OnEnter(drag)
    ok(not hintIsGold() and hintAlpha() == 0.15, "unlocked, a hover tints it white at 0.15")
    ok(st.tips[1] and st.tips[1].lines[2] == "<Drag to move, corner grip to resize.>", "and the tooltip says how")
    drag.scripts.OnLeave(drag)
    ok(hintAlpha() == 0, "leaving clears it")

    st.gen.lockTracker = true
    T:ApplyLockState()
    drag.scripts.OnEnter(drag)
    ok(hintAlpha() == 0, "locked, a hover leaves it clear")
    ok(st.tips[2] and st.tips[2].lines[2] == "<Tracker locked>", "and the tooltip says it is locked")
    drag.scripts.OnLeave(drag)

    st.gen.lockTracker = false
    T:ApplyLockState()
    drag.scripts.OnEnter(drag)
    ok(hintIsGold() and hintAlpha() == 0.55, "in move mode a hover deepens the gold to 0.55")
    drag.scripts.OnLeave(drag)
    ok(hintIsGold() and hintAlpha() == 0.35, "and leaving returns it to 0.35")
end)

case("a click-through tracker takes no hover tint", function()
    load()
    local T, drag = st.Tracker, st.drag
    T:ApplyLockState()
    st.clickThrough = true
    drag.scripts.OnEnter(drag)
    ok(hintAlpha() == 0 and #st.tips == 0, "no tint and no tooltip")
    ok(st.f._dragHover == nil, "and no hover remembered")
end)

-- ------------------------------------------------------------------------- the move bar layout

case("the check and the label sit between the sort button and the cogwheel's run", function()
    load()
    local T, f = st.Tracker, st.f
    local cog = newFrame("Button", f)
    f._lastIcon = cog
    T:LayoutMoveBar()
    local d, l = f.moveDone.points, f.moveLabel.points
    ok(#d == 1 and d[1][1] == "LEFT" and d[1][2] == f.moveBar and d[1][3] == "LEFT" and d[1][4] == 4 and d[1][5] == 0,
       "sort button off: the check sits 4 px in")
    ok(#l == 2 and l[1][1] == "LEFT" and l[1][2] == f.moveDone and l[1][3] == "RIGHT" and l[1][4] == 4,
       "the label starts 4 px after the check")
    ok(l[2] and l[2][1] == "RIGHT" and l[2][2] == cog and l[2][3] == "LEFT" and l[2][4] == -4,
       "and stops 4 px short of the leftmost icon")

    st.trackerCfg.showSortButton = true
    T:LayoutMoveBar()
    d = f.moveDone.points
    ok(#d == 1 and d[1][4] == 20, "sort button on: the check clears it, at 4 + 13 + 3 = 20: " .. tostring(d[1] and d[1][4]))
    st.trackerCfg.showSortButton = 1
    T:LayoutMoveBar()
    ok(f.moveDone.points[1][4] == 4, "only a real true counts as on")

    st.trackerCfg.showSortButton, st.trackerCfg.showFilterButton = false, true
    T:LayoutMoveBar()
    ok(f.moveDone.points[1][4] == 20, "filter button alone: the check clears it at 20 too: " .. tostring(f.moveDone.points[1][4]))
    st.trackerCfg.showSortButton = true
    T:LayoutMoveBar()
    ok(f.moveDone.points[1][4] == 36, "both buttons: 4 + 16 + 16 = 36: " .. tostring(f.moveDone.points[1][4]))
    st.trackerCfg.showFilterButton = 1
    T:LayoutMoveBar()
    ok(f.moveDone.points[1][4] == 20, "the filter button counts only for a real true")
    st.trackerCfg.showSortButton, st.trackerCfg.showFilterButton = false, false

    f._lastIcon = nil
    T:LayoutMoveBar()
    l = f.moveLabel.points
    ok(#l == 2 and l[2][1] == "RIGHT" and l[2][2] == f.moveBar and l[2][3] == "RIGHT" and l[2][4] == -4,
       "with no icon showing, the label runs to 4 px from the right edge")
end)

-- ----------------------------------------------------------------------- locking from the bar

case("the check button locks, says so, and refreshes the General tab", function()
    load()
    local T, f = st.Tracker, st.f
    T:ApplyLockState(true)
    ok(shownBoth(), "in move mode")
    f.moveDone.scripts.OnEnter(f.moveDone)
    local tip = st.tips[#st.tips]
    ok(tip and tip.owner == f.moveDone and tip.anchor == "ANCHOR_BOTTOMRIGHT" and tip.lines[1] == "<Lock tracker>",
       "its tooltip names the Lock tracker box")
    ok(f.moveDone.textures[1].alpha == 1, "hovered, it lights")
    f.moveDone.scripts.OnLeave(f.moveDone)
    ok(f.moveDone.textures[1].alpha == 0.85, "and dims again")
    f.moveDone.scripts.OnClick(f.moveDone, "LeftButton")
    ok(st.gen.lockTracker == true, "a click locks the tracker")
    ok(hiddenBoth(), "which ends move mode")
    ok(st.prints[1] == "<tracker locked.>", "it says so in chat: " .. tostring(st.prints[1]))
    ok(#st.refreshed == 1 and st.refreshed[1] == "general", "and refreshes the General tab")
end)

case("a click-through tracker ignores the check button", function()
    load()
    local T, f = st.Tracker, st.f
    T:ApplyLockState(true)
    st.clickThrough = true
    f.moveDone.scripts.OnClick(f.moveDone, "LeftButton")
    ok(st.gen.lockTracker == false and #st.prints == 0, "nothing changes")
    f.moveDone.scripts.OnEnter(f.moveDone)
    ok(#st.tips == 0, "and it shows no tooltip")
end)

case("SetLocked unlocks into move mode, and survives a missing profile", function()
    load({ locked = true })
    local T = st.Tracker
    T:ApplyLockState()
    T:SetLocked(false)
    ok(st.gen.lockTracker == false, "it unlocks")
    ok(T:InMoveMode() == true and shownBoth(), "straight into move mode, options closed")
    ok(st.prints[1] == "<tracker unlocked.>", "and says so: " .. tostring(st.prints[1]))
    T:SetLocked(1)
    ok(st.gen.lockTracker == true, "any true value stores a real true")
    -- A menu opened while locked can be answered after the box has already unlocked the tracker.
    load()
    st.Tracker:ApplyLockState()
    st.Tracker:SetLocked(false)
    ok(st.Tracker:InMoveMode() == true and shownBoth(), "an unlock on an unlocked tracker still opens move mode")
    load({ noGeneral = true })
    ok(pcall(function() st.Tracker:SetLocked(true) end), "with no profile nothing raises")
    ok(#st.prints == 0 and #st.refreshed == 0, "and nothing is said or refreshed")
end)

-- -------------------------------------------------------------------------------- the menu

local function menuTexts(m)
    local out = {}
    for i, it in ipairs(m.items) do out[i] = (it.kind and ("[" .. it.kind .. "]") or "") .. tostring(it.text) end
    return table.concat(out, " | ")
end

case("the right-click menu offers unlock or lock, reset and the options", function()
    load({ locked = true })
    local T = st.Tracker
    T:ApplyLockState()
    T:OpenFrameMenu(st.drag)
    local m = st.menus[1]
    ok(m and m.owner == st.drag, "it opens on the frame clicked")
    ok(m and menuTexts(m) == "[title]EQ Objective Tracker | <Unlock (allow moving)> | <Reset position and size> | "
       .. "<Open the options panel> | [divider]nil | <Cancel>", "locked, it reads: " .. (m and menuTexts(m) or "none"))
    m.items[2].onClick()
    ok(st.gen.lockTracker == false and T:InMoveMode() == true, "Unlock unlocks, into move mode")
    T:OpenFrameMenu(st.drag)
    m = st.menus[2]
    ok(m.items[2].text == "<Lock position>", "unlocked, the same row offers Lock position")
    m.items[2].onClick()
    ok(st.gen.lockTracker == true, "which locks")
    m.items[3].onClick()
    ok(st.resets == 1 and st.prints[#st.prints] == "<position and size reset.>", "Reset resets and says so")
    m.items[4].onClick()
    ok(st.toggles == 1 and st.raises == 0, "the options row opens the options")
    st.Options.frame._open = true
    m.items[4].onClick()
    ok(st.toggles == 1 and st.raises == 0 and st.Options.frame:IsShown() == true,
       "and with the window already open, neither closes it nor lifts it over a color picker it may have open")
    st.Options.frame = nil
    ok(pcall(m.items[4].onClick) and st.toggles == 2, "before the window is first built, the row builds it")
    ok(m.items[6].onClick == nil, "and Cancel just closes")
end)

case("with no menu library the right-click does nothing", function()
    load({ noUI = true })
    ok(pcall(function() st.Tracker:OpenFrameMenu(st.drag) end), "nothing raises")
    ok(#st.menus == 0, "and no menu opens")
end)

case("only a right-button release over the strip or cogwheel opens the menu", function()
    load()
    local handler = st.drag.scripts.OnMouseUp
    st.drag.mouseOver = true
    handler(st.drag, "LeftButton")
    ok(#st.menus == 0, "a left release opens nothing")
    handler(st.drag, "MiddleButton")
    ok(#st.menus == 0, "nor a middle one")
    handler(st.drag, "RightButton")
    ok(#st.menus == 1 and st.menus[1].owner == st.drag, "a right release over the strip opens it there")
    st.drag.mouseOver = false
    handler(st.drag, "RightButton")
    ok(#st.menus == 1, "a right release dragged off the strip opens nothing")
    st.drag.mouseOver = true
    st.clickThrough = true
    handler(st.drag, "RightButton")
    ok(#st.menus == 1, "a click-through tracker opens nothing")
    st.clickThrough = false
    st.cog.mouseOver = true
    st.cog.scripts.OnMouseUp(st.cog, "RightButton")
    ok(#st.menus == 2 and st.menus[2].owner == st.cog, "a right release on the cogwheel opens it there")
end)

-- ------------------------------------------------------------------- the slash command's unlock

do
    local commands = readFile("UI/Commands.lua")
    local function count(s)
        local n, from = 0, 1
        while true do
            local i = commands:find(s, from, true)
            if not i then return n end
            n, from = n + 1, i + 1
        end
    end
    ok(count('handlers.unlock = function()\n    ns:GetModule("DB"):General().lockTracker = false\n'
             .. '    tracker():ApplyLockState(true)\n') == 1,
       "/eqot unlock applies with startMove, so it opens move mode on an already unlocked tracker")
    ok(count('handlers.lock = function()\n    ns:GetModule("DB"):General().lockTracker = true\n'
             .. '    tracker():ApplyLockState()\n') == 1,
       "/eqot lock applies without it")
end

-- BuildFrame's own last lines, which the slices above stop short of: the saved lock is applied as the
-- frame is built, so a locked tracker starts with its grip hidden and a reload ends any move session.
do
    local tail = "    f.drag, f.grip, f.scroll, f.content = drag, grip, scroll, content\n"
        .. "    self:ApplyWorldQuestsPosition()\n    self:ApplyLockState()\nend\n"
    local n, from = 0, 1
    while true do
        local i = trackerSrc:find(tail, from, true)
        if not i then break end
        n, from = n + 1, i + 1
    end
    ok(n == 1 and trackerSrc:find(tail, 1, true) > trackerSrc:find("function Tracker:BuildFrame()\n", 1, true),
       "BuildFrame applies the saved lock last, with no start of a move session")
end

print(("test_move_mode: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
