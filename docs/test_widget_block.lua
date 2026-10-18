-- luacheck: globals CreateFrame GetTime tremove BackdropTemplateMixin
--
-- Unit tests for UI/WidgetBlock.lua's delve tier row, run against the SHIPPED source.
-- Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_widget_block.lua
--
-- The row is the tier on the left and two counters at the right edge, the nemesis affix and the
-- lives, each an icon, a number and the game's own tooltip. Data/Widgets.lua decides what the entry
-- carries (docs/test_widgets.lua); this file proves what the block draws from it. Every region stub
-- answers only the methods its type has, so a call the client would refuse raises here too.

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
end

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end

-- --------------------------------------------------------------------------------- region stubs

local METHODS = {
    Frame = { "CreateTexture", "CreateMaskTexture", "CreateFontString", "SetPoint", "ClearAllPoints",
              "SetSize", "SetWidth", "SetHeight", "GetWidth", "GetHeight", "Show", "Hide", "IsShown",
              "EnableMouse", "SetScript", "GetScript", "GetParent", "SetParent" },
    Texture = { "SetPoint", "SetAllPoints", "ClearAllPoints", "SetSize", "SetTexture", "SetShown", "IsShown",
                "Show", "Hide", "AddMaskTexture", "SetAtlas", "SetTexCoord" },
    MaskTexture = { "SetAllPoints", "SetTexture" },
    FontString = { "SetPoint", "ClearAllPoints", "SetText", "GetText", "SetTextColor", "GetStringWidth",
                   "GetStringHeight", "SetWordWrap", "SetJustifyH", "SetWidth", "Show", "Hide", "IsShown" },
}

-- A font string measures six pixels a character, and its height is what Media last gave it.
local IMPL = {}
function IMPL:SetPoint(point, rel, relPoint, x, y)
    self.points[#self.points + 1] = { point, rel, relPoint, x, y }
end
function IMPL:ClearAllPoints() self.points = {} end
function IMPL:SetAllPoints(rel) self.allPoints = rel end
function IMPL:SetSize(w, h) self.w, self.h = w, h end
function IMPL:SetWidth(w) self.w = w end
function IMPL:SetHeight(h) self.h = h end
function IMPL:GetWidth() return self.w or 0 end
function IMPL:GetHeight() return self.h or 0 end
function IMPL:Show() self.shown = true end
function IMPL:Hide() self.shown = false end
function IMPL:SetShown(v) self.shown = v and true or false end
function IMPL:IsShown() return self.shown end
function IMPL:EnableMouse(v) self.mouse = v end
function IMPL:SetScript(e, fn) self.scripts[e] = fn end
function IMPL:GetScript(e) return self.scripts[e] end
function IMPL:GetParent() return self.parent end
function IMPL:SetParent(p) self.parent = p end
function IMPL:SetTexture(path, wrapH, wrapV) self.texture, self.wrapH, self.wrapV = path, wrapH, wrapV end
function IMPL:SetAtlas(atlas, useSize) self.atlas, self.atlasSize = atlas, useSize end
function IMPL:SetTexCoord() end
function IMPL:AddMaskTexture(m) self.masks[#self.masks + 1] = m end
function IMPL:SetText(s) self.text = s end
function IMPL:GetText() return self.text end
function IMPL:SetTextColor(r, g, b) self.color = { r, g, b } end
function IMPL:GetStringWidth() return #(self.text or "") * 6 end
function IMPL:GetStringHeight() return self.fontH or 0 end
function IMPL:SetWordWrap(v) self.wordWrap = v end
function IMPL:SetJustifyH(v) self.justify = v end

local new
local function region(kind, parent, layer, template)
    local o = { kind = kind, parent = parent, layer = layer, template = template, points = {},
                scripts = {}, masks = {}, shown = true }
    local allowed = {}
    for _, m in ipairs(METHODS[kind]) do allowed[m] = IMPL[m] end
    if kind == "Frame" then
        allowed.CreateTexture = function(self, _, lay) return new("Texture", self, lay) end
        allowed.CreateMaskTexture = function(self) return new("MaskTexture", self) end
        allowed.CreateFontString = function(self, _, lay, tmpl) return new("FontString", self, lay, tmpl) end
    end
    -- A lowercase key is the addon's own field and reads nil when unset, as in the client.
    return setmetatable(o, { __index = function(_, k)
        local fn = allowed[k]
        if fn then return fn end
        if type(k) == "string" and k:find("^%u") then error(kind .. " has no method " .. k, 2) end
        return nil
    end })
end
new = region

function CreateFrame(kind, _, parent)
    assert(kind == "Frame", "only plain frames are drawn here, got " .. tostring(kind))
    return new("Frame", parent)
end
tremove = table.remove
GetTime = function() return 1000 end
BackdropTemplateMixin = nil

-- ------------------------------------------------------------------------------- module stubs

local mods = {}
local ns = {}
function ns:RegisterModule(n, t) mods[n] = t return t end
function ns:GetModule(n) return mods[n] end
local disabled = {}
function ns:IsModuleDisabled(n) return disabled[n] == true end

local tipLog = {}
local tip = {}
function tip:SetOwner(owner, anchor) tipLog[#tipLog + 1] = { "owner", owner, anchor } end
function tip:SetText(text, r, g, b, a, wrap) tipLog[#tipLog + 1] = { "text", text, r, g, b, a, wrap } end
function tip:SetSpellByID(id) tipLog[#tipLog + 1] = { "spell", id } end
function tip:Show() tipLog[#tipLog + 1] = { "show" } end
function tip:Hide() tipLog[#tipLog + 1] = { "hide" } end

local atlasCalls = {}
ns.Util = {
    Tooltip = function() return tip end,
    SafeSetAtlas = function(tex, atlas, useSize)
        atlasCalls[#atlasCalls + 1] = { tex, atlas }
        tex:SetAtlas(atlas, useSize and true or false)
        return true
    end,
}

local fontH = 12
local fontLog = {}
local media = {}
function media.ApplyFont(self, fs, delta)
    assert(self == media, "Media:ApplyFont without self")
    fontLog[fs] = (fontLog[fs] or "") .. "font" .. tostring(delta) .. ";"
    fs.fontH = fontH
end
function media.ApplyTextShadow(self, fs)
    assert(self == media, "Media:ApplyTextShadow without self")
    fontLog[fs] = (fontLog[fs] or "") .. "shadow;"
end
mods.Media = media

local entries, entryN = {}, 0
local widgets = {}
function widgets.IsAvailable(self) assert(self == widgets) return true end
function widgets.Read(self, setID)
    assert(self == widgets and setID == 777, "Widgets:Read(777)")
    return entries, entryN
end
function widgets.ScenarioSetID(self) assert(self == widgets) return 777 end
function widgets.TrackerSetID(self) assert(self == widgets) return 240 end
function widgets.Forget() end
mods.Widgets = widgets

local clickThrough = false
mods.Tracker = { IsClickThrough = function() return clickThrough end, Refresh = function() end }

assert(loadfile(repoFile("UI/WidgetBlock.lua")))("EQObjectiveTracker", ns)
local WB = mods.WidgetBlock
assert(WB, "UI/WidgetBlock.lua did not register a WidgetBlock module")

local container = new("Frame")
container:SetSize(300, 400)
local cfg = {}

local function render(list, top)
    entries, entryN = list, #list
    return WB:RenderScenario(container, cfg, top or 10)
end

local function pointIs(r, i, point, rel, relPoint, x, y)
    local p = r.points[i]
    return p ~= nil and p[1] == point and p[2] == rel and p[3] == relPoint and p[4] == x and p[5] == y
end
local function colorIs(fs, r, g, b)
    local c = fs.color
    return c ~= nil and c[1] == r and c[2] == g and c[3] == b
end
local function both(extra)
    local e = { kind = "delve", text = "Tier 8", lives = 5, livesIcon = 4410, livesTip = "Total deaths: 0",
                nemAlive = 2, nemTotal = 3, nemSpell = 1307638, nemIcon = 777001 }
    for k, v in pairs(extra or {}) do e[k] = v end
    return e
end
-- Data/Widgets.lua leaves a field it did not read unset, never false.
local function without(e, ...)
    for i = 1, select("#", ...) do e[select(i, ...)] = nil end
    return e
end

-- Ends the run as a failure when a case has nothing left to inspect, rather than raising.
local function stop(msg)
    ok(false, msg)
    print(string.format("test_widget_block: %d passed, %d failed", pass, fail))
    os.exit(1)
end

-- ------------------------------------------------------------------------- both counters drawn

local h = render({ both() })
local rows = WB.scenario.delves
ok(#rows == 1, "one row for one delve entry, got " .. #rows)
local row = rows[1]
if not row then stop("no row was drawn for a delve entry, so nothing else can be checked") end
ok(h == 15 + 3, "the block grows by the row and its gap: " .. tostring(h))
ok(row.parent == container and #row.points == 1 and pointIs(row, 1, "TOPLEFT", container, "TOPLEFT", 8, -10),
   "the row hangs at the block's side pad, at the top it was handed")
ok(row.w == 284 and row.h == 15, "the row spans the block and stands as tall as an icon: " .. tostring(row.w) .. "x" .. tostring(row.h))
ok(row.shown and not row.mouse, "the row is shown and leaves the mouse to its counters")

ok(row.tier.text == "Tier 8" and colorIs(row.tier, 0.85, 0.85, 0.85), "the tier on the left, in the widget gray")
ok(#row.tier.points == 1 and pointIs(row.tier, 1, "LEFT", row, "LEFT", 0, 0) and row.tier.wordWrap == false,
   "anchored to the row's left, one line")
ok(fontLog[row.tier] == "font-2;shadow;", "the tier takes the tracker font two sizes down and the shadow: " .. tostring(fontLog[row.tier]))

local lives, nem = row.lives, row.nem
ok(lives.shown and lives.mouse == true and nem.shown and nem.mouse == true, "both counters shown and taking the mouse")
ok(lives.icon.texture == 4410 and lives.icon.shown and lives.icon.w == 15 and lives.icon.h == 15,
   "the heart is the widget's own icon, as tall as the row")
ok(lives.icon.layer == "ARTWORK" and pointIs(lives.icon, 1, "LEFT", lives, "LEFT", 0, 0), "the icon at the counter's left")
ok(lives.text.text == "5" and colorIs(lives.text, 0.85, 0.85, 0.85), "five lives, in gray")
ok(lives.text.layer == "OVERLAY" and lives.text.template == "GameFontHighlightSmall" and lives.text.wordWrap == false,
   "its number on the overlay, the widget font, one line")
ok(#lives.text.points == 1 and pointIs(lives.text, 1, "LEFT", lives, "LEFT", 19, 0), "the number four pixels past the icon")
ok(fontLog[lives.text] == "font-2;shadow;", "and in the tracker's font with the shadow")
ok(lives.w == 25 and lives.h == 15, "the counter as wide as its icon, gap and number: " .. tostring(lives.w))
ok(#lives.points == 1 and pointIs(lives, 1, "RIGHT", row, "RIGHT", 0, 0), "the lives at the row's right edge")
ok(lives.mask == nil and #lives.icon.masks == 0 and lives.check == nil, "the heart is not masked and has no check")
ok(lives._tooltip == "Total deaths: 0" and lives._spellID == nil, "the lives tooltip is the widget's own text")

ok(nem.icon.texture == 777001 and nem.icon.shown and nem.icon.w == 15 and nem.icon.h == 15, "the affix's own icon")
ok(nem.mask and nem.mask.kind == "MaskTexture" and nem.mask.texture == "Interface\\CharacterFrame\\TempPortraitAlphaMask"
   and nem.mask.wrapH == "CLAMPTOBLACKADDITIVE" and nem.mask.wrapV == "CLAMPTOBLACKADDITIVE" and nem.mask.allPoints == nem.icon,
   "masked round, as Blizzard masks it")
ok(#nem.icon.masks == 1 and nem.icon.masks[1] == nem.mask, "and the mask is on the icon")
if not nem.check then stop("the affix counter has no check, so the all-dead cases cannot be checked") end
ok(nem.check.atlas == "common-icon-checkmark" and nem.check.layer == "OVERLAY",
   "Blizzard's own earned check, over the icon")
ok(#nem.check.points == 1 and pointIs(nem.check, 1, "TOPRIGHT", nem.icon, "TOPRIGHT", 3, 3), "at the icon's top right, as Blizzard places it")
ok(nem.check.w == 11 and nem.check.h == 11 and nem.check.shown == false, "three quarters of the icon, hidden while groups live")
ok(nem.text.text == "1/3" and colorIs(nem.text, 0.85, 0.85, 0.85), "two of three groups alive: one of three killed")
ok(pointIs(nem.text, 1, "LEFT", nem, "LEFT", 19, 0) and nem.w == 37 and nem.h == 15, "laid out as the lives are: " .. tostring(nem.w))
ok(#nem.points == 1 and pointIs(nem, 1, "RIGHT", row, "RIGHT", -35, 0),
   "left of the lives by their width and a ten pixel space")
ok(nem._tooltip == nil and nem._spellID == 1307638, "with no text of its own the affix's spell tooltip shows")

-- ------------------------------------------------------------------------------- lives colors

for _, c in ipairs({ { 5, 0.85, 0.85, 0.85 }, { 3, 0.85, 0.85, 0.85 }, { 2, 1, 0.5, 0.25 },
                     { 1, 1, 0.2, 0.2 }, { 0, 1, 0.2, 0.2 } }) do
    render({ both({ lives = c[1] }) })
    local t = WB.scenario.delves[1].lives.text
    ok(t.text == tostring(c[1]) and colorIs(t, c[2], c[3], c[4]),
       c[1] .. " lives drawn in " .. c[2] .. "," .. c[3] .. "," .. c[4])
end
render({ both({ lives = 2 }) })
ok(colorIs(WB.scenario.delves[1].nem.text, 0.85, 0.85, 0.85), "the warning colors are the lives' alone")

-- --------------------------------------------------------------------------------- all dead

render({ both({ nemAlive = 0 }) })
row = WB.scenario.delves[1]
ok(row.nem.check.shown == true and row.nem.text.text == "", "all dead: the check shows and the count goes")
ok(row.nem.icon.shown and row.nem.icon.texture == 777001, "over the affix's icon, which stays")
ok(row.nem.w == 15, "the counter is just its icon: " .. tostring(row.nem.w))
render({ both() })
ok(WB.scenario.delves[1].nem.check.shown == false, "and a reused row hides the check again")

-- --------------------------------------------------------------------- one counter, or reuse

render({ both() })
local first = WB.scenario.delves[1]
render({ without(both(), "nemAlive", "nemTotal", "nemSpell", "nemIcon") })
row = WB.scenario.delves[1]
ok(row == first, "the row is reused from the pool")
ok(row.nem.shown == false and row.nem._tooltip == nil and row.nem._spellID == nil,
   "lives only: the nemesis hidden, its tooltip and spell gone")
ok(row.lives.shown and pointIs(row.lives, 1, "RIGHT", row, "RIGHT", 0, 0), "the lives at the right edge")

render({ { kind = "delve", text = "Tier 8", nemAlive = 1, nemTotal = 3, nemSpell = 1307638, nemIcon = 777001,
           nemTip = "Nemesis Influence" } })
row = WB.scenario.delves[1]
ok(row.lives.shown == false and row.lives._tooltip == nil, "nemesis only: the lives hidden, their tooltip gone")
ok(#row.nem.points == 1 and pointIs(row.nem, 1, "RIGHT", row, "RIGHT", 0, 0), "and the nemesis takes the right edge")
ok(row.nem._tooltip == "Nemesis Influence", "an affix tooltip with text of its own is kept")
ok(row.nem.text.text == "2/3" and row.nem.check.shown == false, "one group left: two killed, a count, not the check")

-- ---------------------------------------------------------------------------- groups killed

-- The count reads groups killed, as the bonus objectives HUD counts them, while the entry carries
-- the game's groups alive.
for _, c in ipairs({ { 3, 3, "0/3" }, { 1, 4, "3/4" }, { 4, 4, "0/4" }, { 5, 3, "0/3" } }) do
    render({ both({ nemAlive = c[1], nemTotal = c[2] }) })
    local n = WB.scenario.delves[1].nem
    ok(n.text.text == c[3] and n.check.shown == false,
       c[1] .. " of " .. c[2] .. " alive draws " .. c[3] .. ": " .. tostring(n.text.text))
end

-- The killed count stays in the widget gray, and a new total with the same groups alive redraws it.
for _, c in ipairs({ { 3, 3 }, { 1, 4 }, { 4, 4 } }) do
    render({ both({ nemAlive = c[1], nemTotal = c[2] }) })
    ok(colorIs(WB.scenario.delves[1].nem.text, 0.85, 0.85, 0.85), c[1] .. " of " .. c[2] .. " alive: the count in the widget gray")
end
render({ without(both({ nemAlive = 0 }), "nemIcon") })
ok(colorIs(WB.scenario.delves[1].nem.text, 0.85, 0.85, 0.85), "every group killed with no affix icon: 3/3 still in the widget gray")
render({ both({ nemAlive = 1, nemTotal = 3 }) })
render({ both({ nemAlive = 1, nemTotal = 4 }) })
ok(WB.scenario.delves[1].nem.text.text == "3/4",
   "a new total with the same groups alive redraws the count: " .. tostring(WB.scenario.delves[1].nem.text.text))

-- ---------------------------------------------------------------------------- missing icons

render({ without(both(), "livesIcon", "nemIcon") })
row = WB.scenario.delves[1]
ok(row.lives.shown and row.nem.shown, "a reused row shows the counter the last draw hid")
ok(row.lives.icon.shown == false and pointIs(row.lives.text, 1, "LEFT", row.lives, "LEFT", 0, 0) and row.lives.w == 6,
   "no lives icon: the number alone, at the counter's left")
ok(row.nem.icon.shown == false and row.nem.w == 18, "no affix icon: the count alone")
ok(pointIs(row.nem, 1, "RIGHT", row, "RIGHT", -16, 0), "placed by the narrower lives counter")

-- The pre-ship scan of 2026-10-17: with every group dead and no affix icon, the check drew on the
-- hidden icon's spot, over the heart or past the row's edge.
render({ without(both({ nemAlive = 0 }), "nemIcon") })
row = WB.scenario.delves[1]
ok(row.nem.check.shown == false, "all dead with no affix icon: no check, which has no icon to sit on")
ok(row.nem.text.text == "3/3", "the count says it instead: " .. tostring(row.nem.text.text))
ok(row.nem.w == 18, "and the counter is that count: " .. tostring(row.nem.w))
render({ both({ nemAlive = 0 }) })
ok(WB.scenario.delves[1].nem.check.shown == true and WB.scenario.delves[1].nem.text.text == "",
   "while the same row with its icon back shows the check again")

-- ---------------------------------------------------------------------------- a larger font

fontH = 20
h = render({ both() })
row = WB.scenario.delves[1]
ok(h == 23 + 3 and row.h == 23, "the row grows with the font: " .. tostring(h))
ok(row.lives.icon.w == 23 and row.nem.icon.h == 23 and row.nem.check.w == 17, "and the icons and check with it")
ok(pointIs(row.lives.text, 1, "LEFT", row.lives, "LEFT", 27, 0), "the number still four pixels past the bigger icon")
fontH = 8
h = render({ both() })
row = WB.scenario.delves[1]
ok(row.h == 14 and row.lives.icon.w == 14 and row.nem.icon.h == 14,
   "a small font never takes the icons under 14: " .. tostring(row.h))
ok(row.nem.check.w == 11 and row.nem.check.h == 11, "and the check stays three quarters of 14, rounded: "
   .. tostring(row.nem.check.w))
ok(h == 14 + 3, "and the row is that tall: " .. tostring(h))
fontH = 12

-- ---------------------------------------------------------------------------------- tooltips

render({ both() })
row = WB.scenario.delves[1]
local function hover(f)
    for i = #tipLog, 1, -1 do tipLog[i] = nil end
    local enter = f:GetScript("OnEnter")
    ok(enter ~= nil, "a counter has an OnEnter")
    if not enter then return "no OnEnter" end
    enter(f)
    local out = {}
    for _, e in ipairs(tipLog) do out[#out + 1] = table.concat({ tostring(e[1]), tostring(e[2]), tostring(e[3]) }, "=") end
    return table.concat(out, " ")
end
local got = hover(row.lives)
ok(got == "owner=" .. tostring(row.lives) .. "=ANCHOR_RIGHT text=Total deaths: 0=1 show=nil=nil", "the heart shows the widget's text: " .. got)
ok(tipLog[2] and tipLog[2][7] == true and tipLog[2][4] == 1 and tipLog[2][5] == 1 and tipLog[2][6] == 1, "in white, wrapped")
got = hover(row.nem)
ok(got == "owner=" .. tostring(row.nem) .. "=ANCHOR_RIGHT spell=1307638=nil show=nil=nil",
   "the affix with no text of its own shows its spell, as Blizzard's does: " .. got)
render({ both({ nemTip = "Nemesis Influence" }) })
row = WB.scenario.delves[1]
got = hover(row.nem)
ok(got:find("text=Nemesis Influence", 1, true) and not got:find("spell=", 1, true), "an affix with its own text shows that instead: " .. got)
clickThrough = true
ok(hover(row.lives) == "" and hover(row.nem) == "", "a click-through tracker shows no tooltip")
clickThrough = false
render({ without(both(), "livesTip") })
ok(hover(WB.scenario.delves[1].lives) == "", "a counter with nothing to show shows nothing")
for i = #tipLog, 1, -1 do tipLog[i] = nil end
for _, f in ipairs({ WB.scenario.delves[1].nem, WB.scenario.delves[1].lives }) do
    local leave = f:GetScript("OnLeave")
    ok(leave ~= nil, "a counter has an OnLeave")
    if leave then leave(f) end
end
ok(#tipLog == 2 and tipLog[1][1] == "hide" and tipLog[2][1] == "hide", "leaving either counter hides the tooltip")

-- --------------------------------------------------------------------- among the other lines

h = render({ { kind = "text", text = "Above" }, both(), { kind = "text", text = "Below" } })
local texts = WB.scenario.texts
row = WB.scenario.delves[1]
ok(#texts == 2 and texts[1].text == "Above" and texts[2].text == "Below", "the text lines around it draw")
ok(pointIs(row, 1, "TOPLEFT", container, "TOPLEFT", 8, -(10 + 12 + 3)), "the row under the first line")
ok(pointIs(texts[2], 1, "TOPLEFT", container, "TOPLEFT", 8, -(10 + 15 + 15 + 3)), "the next line under the row")
ok(h == 15 + 15 + 15 + 3, "the block's height counts all three: " .. tostring(h))

render({ both(), both({ text = "Tier 9" }) })
ok(#WB.scenario.delves == 2 and WB.scenario.delves[2].tier.text == "Tier 9", "two entries, two rows")
local second = WB.scenario.delves[2]
render({ both() })
ok(#WB.scenario.delves == 1 and #WB.scenario.delvePool == 1 and second.shown == false,
   "a shorter read sends the spare row back to the pool, hidden")

-- ------------------------------------------------------------------------------- the release

render({ both() })
row = WB.scenario.delves[1]
h = render({})
ok(h == 0 and #WB.scenario.delves == 0 and row.shown == false and #row.points == 0,
   "nothing to draw: the row is released, hidden and unanchored")
ok(row.nem._tooltip == nil and row.nem._spellID == nil and row.lives._tooltip == nil,
   "and its tooltips forgotten, so a hidden counter cannot show a stale one")
render({ both() })
ok(WB.scenario.delves[1] == row and row.shown == true, "and taken back from the pool, shown again")
cfg.showTrackerWidgets = false
h = render({ both() })
ok(h == 0 and #WB.scenario.delves == 0 and row.shown == false, "with the widgets box off the row is released")
cfg.showTrackerWidgets = nil
disabled.WidgetBlock = true
ok(render({ both() }) == 0 and #WB.scenario.delves == 0, "and with the module disabled")
disabled.WidgetBlock = nil

print(string.format("test_widget_block: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
