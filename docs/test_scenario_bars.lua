-- Unit tests for UI/Scenario.lua's criteria draw, run against the SHIPPED source rather than
-- a copy. Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_scenario_bars.lua
--
-- WHY THIS FILE EXISTS. showScenarioProgressBars shipped in v1.18.0 with its PRODUCE side
-- covered by docs/test_row_blocks.lua and its CONSUME side covered by nothing at all. The one
-- reader that DRAWS from that key is _DrawCriteria here, and no harness sliced it, so the
-- switch could have been inverted, dropped, or wired to the QUEST key with every harness and
-- every battery in the tree green. That is the produce/consume split this project has recorded
-- four times, and this file closes the scenario half of it.
-- (The sweep in Options/TabAppearance.lua that dims the styling group is out of scope and
-- covered by nothing. The seams block at the foot of this file DOES read that file and
-- Core/DB.lua, for the event title's two settings.)
--
-- The rest of what earns the file:
--   * the two halves are INDEPENDENT - the quest key must never move a scenario criterion,
--     and the master must still veto the scenario one
--   * bars OFF must leave the meter in the TEXT, which is the only place it survives, and that
--     text is what shipped before bars existed
--   * a completed criterion never draws a bar, and a 0/1 criterion is a yes-or-no rather than a
--     meter - drawing one reads as broken beside the checkmark rows around it
--   * the gap a row records ABOVE itself, which Scenario:Render sums again to size the
--     container, so a gap this function does not record leaves the panel short by that much
--
-- UI/Scenario.lua cannot be loaded whole without a frame stub, so the pieces under test are
-- sliced out by TEXT ANCHORS rather than line numbers, which drift. If an anchor below stops
-- matching, fix the anchor here rather than deleting the test.
--
-- WIDENED 2026-09-08, after a user reported a long scenario name running straight off the right
-- edge of the tracker and the banner's own strings sitting off-center on the plaque they draw
-- on. BOTH were reachable with every assertion in this file green, because everything above
-- _DrawCriteria used to be out of scope by construction. The header's sizing and _DrawBanner
-- are sliced and driven now, and what earns those:
--   * the title is given a WRAP WIDTH at all, which is the whole of the first bug: a FontString
--     anchored on one side alone has no width, so it runs rather than wraps
--   * the width is applied BEFORE the height is measured, or an unbounded string measures as a
--     single line however long it is and the sub-header stays too short to hold it
--   * the sizing lives in ApplyHeaderFont rather than beside the labels, because
--     ApplyHeaderLabels memoizes on the scenario identity and so would never re-run for a
--     tracker the player resized while one stage was up
--   * the banner's strings are centered on the ART, which is sized by its own atlas, rather
--     than on the fixed-width frame the art is merely pinned to the top-left corner of
--
-- STILL OUT OF SCOPE: the widget block's own height and Scenario:Render's container arithmetic.
-- ReleaseCriteria IS in scope - it is sliced and driven, because the pooled reuse it feeds is
-- half of what _DrawCriteria does.

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
end

local fh = assert(io.open(repoFile("UI/Scenario.lua"), "r"))
local src = fh:read("*a")
fh:close()

local function sliceBetween(fromAnchor, toAnchor)
    local from = src:find(fromAnchor, 1, true)
    local to   = src:find(toAnchor, 1, true)
    assert(from, "anchor not found in UI/Scenario.lua: " .. fromAnchor)
    assert(to,   "anchor not found in UI/Scenario.lua: " .. toAnchor)
    assert(to > from, "anchors are out of order in UI/Scenario.lua: " .. fromAnchor)
    return src:sub(from, to - 1)
end

-- The constants are sliced rather than restated. Every geometry assertion below is written as
-- a LITERAL, so restating them here would let the file agree with itself while disagreeing
-- with the build - the defect a constant's own comment in this codebase exists to prevent.
local constants = sliceBetween("local SUBHEADER_H", "local HEADER_COLOR")
local release   = sliceBetween("function Scenario:ReleaseCriteria", "function Scenario:Build")
local draw      = sliceBetween("function Scenario:_DrawCriteria",
                               "-- topOffset is the height the widget block above already took")
-- pickAtlases and the per-kit offsets come with the banner, because _DrawBanner calls the one
-- and indexes the other, and a reimplementation of either here would be free to agree with the
-- test while disagreeing with the build.
local atlases   = sliceBetween("local HEADER_COLOR", "Scenario.criteriaPool")
local header    = sliceBetween("-- A FontString anchored on one side alone has no width",
                               "function Scenario:ApplyBannerShadow")
local bannerSrc = sliceBetween("function Scenario:_DrawBanner", "function Scenario:_DrawCriteria")

local LINE = {
    OBJECTIVE = "objective", PROGRESSBAR = "progressbar",
    NOTE = "note", WEIGHTED = "weighted",
}

-- Deterministic so every height assertion below can be a literal rather than a reading of
-- the stub it is measuring.
local TEXT_LINE_H = 12
local STUB_BAR_H  = 20

-- SHOWN by default, the way a real FontString is on creation. subHeader.cat is the one this
-- matters for: headerHeight reads IsShown to pick which of the two header shapes it is
-- measuring, so a stub defaulting to hidden would make the one-tier answer the passing value
-- for both. Every case below drives it through ApplyHeaderLabels, which sets it explicitly.
local function newFontString()
    local fs = { _text = "", _width = 0, _justify = nil, _color = nil, _points = {},
                 _shown = true, _lines = 1 }
    function fs:ClearAllPoints() self._points = {} end
    function fs:SetPoint(p, rel, relP, x, y)
        self._points[#self._points + 1] = { p = p, rel = rel, relP = relP, x = x, y = y }
    end
    function fs:SetJustifyH(v) self._justify = v end
    function fs:SetJustifyV(v) self._justifyV = v end
    function fs:SetWidth(w) self._width = w end
    -- The name's box is DERIVED from the art now rather than fixed, and the stage line's own
    -- height is one of the terms, so both axes have to be readable and settable here.
    function fs:SetHeight(h) self._height = h end
    function fs:GetHeight() return self._height or 0 end
    function fs:SetSize(w, h) self._width, self._height = w, h end
    function fs:SetText(t) self._text = t end
    function fs:SetFormattedText(f, ...) self._text = f:format(...) end
    function fs:SetTextColor(r, g, b) self._color = { r, g, b } end
    function fs:Show() self._shown = true end
    function fs:Hide() self._shown = false end
    function fs:IsShown() return self._shown end
    -- Width-aware deliberately, because that IS the behavior the header fix turns on: a
    -- FontString with no width measures as ONE line however long its text is. A stub that
    -- answered TEXT_LINE_H either way could not tell the fix from the bug it replaces.
    -- _lines is what a case says the string needs once it HAS a width, and it is 1 everywhere
    -- else, which is why no criteria height assertion in this file moves.
    function fs:GetStringHeight()
        return TEXT_LINE_H * ((self._width and self._width > 0) and self._lines or 1)
    end
    return fs
end

-- SHOWN, because a real CreateTexture and a real StatusBar both are on creation. Defaulting
-- this to false made it the value a refusal case expects, and both Hide calls on the draw path
-- could then be deleted with the file green. Ask of any stub default whether it is a PASSING
-- value.
local function newRegion()
    local t = { _shown = true, _atlas = nil, _points = {}, _w = 0, _h = 0 }
    function t:Show() self._shown = true end
    function t:Hide() self._shown = false end
    -- The banner art's own size, which SafeSetAtlas below fills in from the atlas. It is what
    -- the stage and the name are centered on, so a region that could not report it would leave
    -- the one thing those cases are about unmeasurable.
    function t:GetWidth() return self._w end
    function t:GetHeight() return self._h end
    function t:SetVertexColor(r, g, b) self._tint = { r, g, b } end
    function t:ClearAllPoints() self._points = {} end
    function t:SetPoint(p, rel, relP, x, y)
        self._points[#self._points + 1] = { p = p, rel = rel, relP = relP, x = x, y = y }
    end
    return t
end

local rowsBuilt = 0

local function newRow(parent)
    rowsBuilt = rowsBuilt + 1
    local r = { _shown = false, _w = 0, _h = 0, _points = {}, _parent = parent }
    r.text = newFontString()
    r.icon = newRegion()
    r.bar  = newRegion()
    r.bar.label = newFontString()
    r.bar._min, r.bar._max, r.bar._val, r.bar._h, r.bar._w = 0, 0, 0, 0, 0
    function r.bar:SetWidth(w) self._w = w end
    function r.bar:SetHeight(h) self._h = h end
    function r.bar:SetMinMaxValues(lo, hi) self._min, self._max = lo, hi end
    function r.bar:SetValue(v) self._val = v end
    function r:Show() self._shown = true end
    function r:Hide() self._shown = false end
    function r:SetWidth(w) self._w = w end
    function r:SetHeight(h) self._h = h end
    function r:GetHeight() return self._h end
    function r:GetParent() return self._parent end
    function r:SetParent(p) self._parent = p end
    function r:ClearAllPoints() self._points = {} end
    function r:SetPoint(p, rel, relP, x, y)
        self._points[#self._points + 1] = { p = p, rel = rel, relP = relP, x = x, y = y }
    end
    return r
end

-- Every stub records WHICH object it was handed, not just how many times it was called.
-- A counter alone cannot tell the criteria font going on the row's text from it going on the
-- bar's label instead, which leaves every criterion on whatever font it last had.
-- ApplyProgressBar takes the second parameter the shipped Core/Media.lua takes: skipFill
-- suppresses the user's bar color, and a stub with the wrong arity cannot see it being sent.
local Media = { _fonts = {}, _shadows = {}, _styled = 0, _lastBar = nil, _skipFill = nil,
                _headerFonts = {}, _bannerFonts = {}, _bannerShadows = {} }
function Media:ProgressBarHeight() return STUB_BAR_H end
-- The size DELTA is recorded, not just the call: +4 is what makes the scenario title size like
-- the section headers around it and -1 is the category above it, so a counter alone could not
-- see the two swapped.
function Media:ApplyFont(fs, delta)
    self._headerFonts[#self._headerFonts + 1] = { fs = fs, delta = delta }
end
function Media:ApplyScenarioFont(fs) self._bannerFonts[#self._bannerFonts + 1] = fs end
function Media:ApplyScenarioShadow(fs) self._bannerShadows[#self._bannerShadows + 1] = fs end
function Media:ApplyScenarioCriteriaFont(fs) self._fonts[#self._fonts + 1] = fs end
function Media:ApplyTextShadow(fs) self._shadows[#self._shadows + 1] = fs end
function Media:ApplyProgressBar(bar, skipFill)
    self._styled   = self._styled + 1
    self._lastBar  = bar
    self._skipFill = skipFill
end

local function gotBoth(list, row)
    local sawText, sawLabel = false, false
    for i = 1, #list do
        if list[i] == row.text then sawText = true end
        if list[i] == row.bar.label then sawLabel = true end
    end
    return sawText and sawLabel
end

-- The atlases this harness pretends the client has, keyed to their size. pickAtlases asks
-- AtlasExists to decide whether a texture kit resolves at all, and SafeSetAtlas sizes the
-- region from this when useAtlasSize is passed - which is how the banner art gets the width
-- its strings have to be centered on.
local ATLAS_SIZE = {}
local Util = {}
function Util.AtlasExists(atlas) return ATLAS_SIZE[atlas] ~= nil end
-- Three parameters, matching the shipped Util.SafeSetAtlas. A two-parameter stub cannot record
-- useAtlasSize, and that flag is the whole reason the art has a size at all.
function Util.SafeSetAtlas(region, atlas, useAtlasSize)
    region._atlas, region._useAtlasSize = atlas, useAtlasSize
    local size = ATLAS_SIZE[atlas]
    if size and useAtlasSize then region._w, region._h = size[1], size[2] end
    return size ~= nil
end

local Scenario = { activeCriteria = {}, criteriaPool = {} }

-- Mirrors the shipped AcquireCriteria, whose own body needs CreateFrame. The pool half is
-- reproduced rather than skipped because ReleaseCriteria IS sliced above, and the reuse it
-- feeds is what the bar-then-text case below is about.
function Scenario:AcquireCriteria(parent)
    local n   = #self.criteriaPool
    local row = self.criteriaPool[n]
    if row then self.criteriaPool[n] = nil else row = newRow(parent) end
    if row:GetParent() ~= parent then row:SetParent(parent) end
    row:Show()
    self.activeCriteria[#self.activeCriteria + 1] = row
    return row
end

-- Keys through, so a banner string carries the English wording and a missing key would read as
-- itself rather than as nil. Stage %d is formatted by the slice, so the substitution is real.
local L = setmetatable({}, { __index = function(_, k) return k end })

local env = setmetatable({
    ns       = { GetModule = function(_, name) return (name == "Media") and Media or nil end },
    Scenario = Scenario,
    LINE     = LINE,
    Util     = Util,
    L        = L,
}, { __index = _G })

local chunk = assert(loadstring(constants .. "\n" .. atlases .. "\n" .. release .. "\n"
                                .. draw .. "\n" .. header .. "\n" .. bannerSrc,
                                "@UI/Scenario.lua slice"))
setfenv(chunk, env)
chunk()
assert(Scenario._DrawCriteria, "the UI/Scenario.lua slice defined no _DrawCriteria")
assert(Scenario.ReleaseCriteria, "the UI/Scenario.lua slice defined no ReleaseCriteria")
assert(Scenario.ApplyHeaderLabels, "the UI/Scenario.lua slice defined no ApplyHeaderLabels")
assert(Scenario.ApplyHeaderFont, "the UI/Scenario.lua slice defined no ApplyHeaderFont")
assert(Scenario._DrawBanner, "the UI/Scenario.lua slice defined no _DrawBanner")

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end

local CONTAINER = { GetWidth = function() return 300 end }
-- The width guards exist for a container that has not laid out yet. With CONTAINER always
-- answering 300 they could all be deleted with the file green. ZERO_W is the real case, and
-- 0 is TRUTHY in Lua, so it reaches math.max rather than the `or 1` beside it - NIL_W is what
-- reaches that one.
local ZERO_W = { GetWidth = function() return 0 end }
local NIL_W  = { GetWidth = function() return nil end }

-- Every call into the slice goes through pcall. A mutant that raises would otherwise kill the
-- file with no summary line, and every battery in this tree reads a missing summary as a
-- SURVIVOR - so a crash would report as a coverage hole rather than as the crash it is.
local function render(lines, cfg, opts)
    opts = opts or {}
    -- Sliced from the shipped file too, so it is under test rather than scaffolding, and it
    -- gets the same pcall for the same reason.
    local relOK, relErr = pcall(Scenario.ReleaseCriteria, Scenario)
    if not relOK then return false, "ReleaseCriteria raised - " .. tostring(relErr) end
    -- ReleaseCriteria hides BOTH regions on its way to the pool, so a pooled row always
    -- arrives clean and _DrawCriteria's own Hide calls are only provably needed on a row it
    -- has never drawn. Emptying the pool here is the only way to get one.
    if opts.fresh then
        for i = #Scenario.criteriaPool, 1, -1 do Scenario.criteriaPool[i] = nil end
    end
    Scenario.topOffset  = opts.topOffset
    Scenario.subHeaderH = opts.subHeaderH
    Scenario.widgetH    = opts.widgetH
    Media._fonts, Media._shadows = {}, {}
    Media._styled, Media._lastBar, Media._skipFill = 0, nil, nil
    local good, err = pcall(Scenario._DrawCriteria, Scenario,
                            opts.container or CONTAINER, cfg, lines)
    return good, err
end

-- The row COUNT is asserted on every case, and that is load-bearing rather than tidy.
-- at() below substitutes a blank row when one is missing, and a blank row's defaults are
-- exactly what a refusal case expects - bar hidden, value zero - so a build that drew NO
-- rows at all satisfied three of the assertions below until this was added. _DrawCriteria
-- acquires one row per line unconditionally, so this holds for every case in the file.
local function drawn(msg, lines, cfg, opts)
    local good, err = render(lines, cfg, opts)
    ok(good, msg .. ": _DrawCriteria raised - " .. tostring(err))
    ok(#Scenario.activeCriteria == #lines,
       msg .. ": drew " .. #Scenario.activeCriteria .. " rows for " .. #lines .. " lines")
    return Scenario.activeCriteria
end

-- Reading a row that a mutant failed to produce must FAIL rather than raise, for the same
-- reason the pcall above exists.
local function at(rows, i) return rows[i] or newRow(nil) end

local function weighted(text, cur) return { kind = LINE.WEIGHTED, text = text, current = cur } end
local function meter(text, cur, req)
    return { kind = LINE.PROGRESSBAR, text = text, current = cur, required = req }
end

local ON       = {}
local SCEN_OFF = { showScenarioProgressBars = false }
local MASTER   = { showProgressBars = false }
local QUEST    = { showQuestProgressBars = false }

--------------------------------------------------------------------------------------------
-- The switch. This is the half that had no coverage at all.
--------------------------------------------------------------------------------------------
local rows = drawn("bars on", { weighted("Hold the line", 42) }, ON)
ok(at(rows, 1).bar._shown == true, "a weighted criterion draws a bar with bars on")
ok(at(rows, 1).bar.label._text == "42%", "the bar carries its own percentage")
ok(at(rows, 1).text._text == "Hold the line",
   "the label above the bar is the criterion text alone")

rows = drawn("scenario half off", { weighted("Hold the line", 42) }, SCEN_OFF)
ok(at(rows, 1).bar._shown == false, "showScenarioProgressBars=false draws no bar")
ok(at(rows, 1).text._text == "42% Hold the line",
   "with the bar gone the meter survives in the text, which is where it shipped")
ok(at(rows, 1).icon._shown == true, "the text path shows the objective icon again")

rows = drawn("master off", { weighted("Hold the line", 42) }, MASTER)
ok(at(rows, 1).bar._shown == false, "showProgressBars=false vetoes the scenario bar")

rows = drawn("master off, half on", { weighted("Hold the line", 42) },
             { showProgressBars = false, showScenarioProgressBars = true })
ok(at(rows, 1).bar._shown == false, "the master outranks the scenario half")

rows = drawn("quest half off", { weighted("Hold the line", 42) }, QUEST)
ok(at(rows, 1).bar._shown == true,
   "showQuestProgressBars must not reach a scenario criterion - the halves are independent")

rows = drawn("no config", { weighted("Hold the line", 42) }, nil)
ok(at(rows, 1).bar._shown == true, "a nil config draws bars, matching the shipped default")

--------------------------------------------------------------------------------------------
-- What is deliberately not a bar
--------------------------------------------------------------------------------------------
rows = drawn("completed weighted", {
    { kind = LINE.WEIGHTED, text = "Hold the line", current = 100, completed = true },
}, ON)
ok(at(rows, 1).bar._shown == false, "a completed criterion never draws a bar")
ok(at(rows, 1).text._text == "Hold the line", "a completed criterion drops its meter")
local col = at(rows, 1).text._color or {}
ok(col[1] == 0.27 and col[2] == 1.0 and col[3] == 0.27, "a completed criterion draws green")
ok(at(rows, 1).icon._atlas == "ui-questtracker-tracker-check",
   "a completed criterion takes the checkmark atlas")

rows = drawn("yes or no", { meter("Reach the vault", 0, 1) }, ON)
ok(at(rows, 1).bar._shown == false, "a 0/1 criterion is a yes-or-no, not a meter")
ok(at(rows, 1).text._text == "0/1 Reach the vault", "the 0/1 criterion keeps its meter as text")
ok(at(rows, 1).icon._atlas == "ui-questtracker-objective-nub",
   "an unfinished criterion takes the nub atlas")
local ucol = at(rows, 1).text._color or {}
ok(ucol[1] == 0.85 and ucol[2] == 0.85 and ucol[3] == 0.85, "an unfinished criterion draws grey")

rows = drawn("real meter", { meter("Slay the packs", 3, 5) }, ON)
ok(at(rows, 1).bar._shown == true, "a criterion with a real denominator draws a bar")
ok(at(rows, 1).bar.label._text == "3/5", "a count bar is labeled as a count, not a percentage")

rows = drawn("plain objective", { { kind = LINE.OBJECTIVE, text = "Survive" } }, ON)
ok(at(rows, 1).bar._shown == false, "an ordinary objective draws no bar")
ok(at(rows, 1).text._text == "Survive", "an ordinary objective draws its text alone")

--------------------------------------------------------------------------------------------
-- Clamping, and the two denominators
--------------------------------------------------------------------------------------------
rows = drawn("over 100", { weighted("Overrun", 150) }, ON)
ok(at(rows, 1).bar._val == 100, "a weighted value over 100 clamps to 100")
ok(at(rows, 1).bar.label._text == "100%", "the clamped value is what the label reports")
ok(at(rows, 1).bar._max == 100, "a weighted bar is always out of 100")

rows = drawn("under zero", { weighted("Negative", -5) }, ON)
ok(at(rows, 1).bar._val == 0, "a negative weighted value clamps to 0")
ok(at(rows, 1).bar.label._text == "0%", "zero percent still draws, it is not falsy")

rows = drawn("over the cap", { meter("Slay the packs", 99, 5) }, ON)
ok(at(rows, 1).bar._val == 5, "a count over its denominator clamps to the denominator")
ok(at(rows, 1).bar._max == 5, "a count bar keeps its own denominator")
ok(at(rows, 1).bar.label._text == "5/5", "the clamped count is what the label reports")

rows = drawn("missing current", { { kind = LINE.WEIGHTED, text = "Unknown" } }, ON)
ok(at(rows, 1).bar._val == 0, "a weighted line with no current reads as zero rather than raising")

--------------------------------------------------------------------------------------------
-- The gap each row records above itself. Scenario:Render sums these again to size the
-- container, so a wrong one leaves the panel short by exactly that much.
--------------------------------------------------------------------------------------------
rows = drawn("three plain rows", {
    { kind = LINE.OBJECTIVE, text = "One" },
    { kind = LINE.OBJECTIVE, text = "Two" },
    { kind = LINE.OBJECTIVE, text = "Three" },
}, ON)
ok(#rows == 3, "three lines draw three rows")
ok(at(rows, 1)._gapAbove == 4, "the first row records the plain criteria gap")
ok(at(rows, 2)._gapAbove == 4, "a row after a text row records the plain criteria gap")
ok(at(rows, 3)._gapAbove == 4, "and so does the row after that")

rows = drawn("text then bar then text", {
    { kind = LINE.OBJECTIVE, text = "One" },
    weighted("Two", 50),
    { kind = LINE.OBJECTIVE, text = "Three" },
}, ON)
ok(at(rows, 2)._gapAbove == 4, "a bar row after a TEXT row pays the plain gap")
ok(at(rows, 3)._gapAbove == 6,
   "a row after a BAR pays the wider gap, or the border drawn a pixel below the bar eats it")

rows = drawn("bars off kills the wide gap", {
    { kind = LINE.OBJECTIVE, text = "One" },
    weighted("Two", 50),
    { kind = LINE.OBJECTIVE, text = "Three" },
}, SCEN_OFF)
ok(at(rows, 3)._gapAbove == 4, "with bars off there is no bar to pay the wider gap for")

--------------------------------------------------------------------------------------------
-- Geometry. Literals throughout, so a changed constant fails here rather than agreeing
-- with itself.
--------------------------------------------------------------------------------------------
rows = drawn("first row anchor", { { kind = LINE.OBJECTIVE, text = "One" } }, ON)
local p = at(rows, 1)._points[1] or {}
ok(p.p == "TOP" and p.rel == CONTAINER,
   "the first row anchors to the container, not to the banner")
ok(p.y == -119,
   "the first row sits below subheader, banner gap, banner and one criteria gap (26+6+83+4)")

rows = drawn("widget block above", { { kind = LINE.OBJECTIVE, text = "One" } }, ON,
-- subHeaderH is 40 rather than the 26 it used to be, and that is the whole point: 26 is
-- SUBHEADER_H, so the fallback and the field agreed and _DrawCriteria could ignore the field
-- entirely with this case green. A two-tier header computes this off the font, so it moves.
             { topOffset = 10, widgetH = 30, subHeaderH = 40 })
local p2 = at(rows, 1)._points[1] or {}
ok(p2.y == -173,
   "the sub-header, the widget block and the top offset all push the first row down")

rows = drawn("widths", { weighted("Bar", 50), { kind = LINE.OBJECTIVE, text = "Text" } }, ON)
ok(at(rows, 1)._w == 255, "a bar row is 85 percent of the container")
ok(at(rows, 1).bar._w == 255, "the bar itself matches the row")
ok(at(rows, 1).bar._h == 20, "the bar takes its height from Media rather than a build-time seed")
ok(at(rows, 1).text._width == 255,
   "a bar's label wraps to the BAR, not the row, or it overhangs the bar it labels")
ok(at(rows, 1).bar._min == 0, "the bar fills from zero, not from its own maximum")
ok(at(rows, 2)._w == 284, "a text row is the container less its side padding")
ok(at(rows, 2).text._width == 266, "the text wraps inside the row rather than off the end")

rows = drawn("bar row height", { weighted("Bar", 50) }, ON)
ok(at(rows, 1)._h == 38, "a labeled bar row is text plus the gap plus the bar (12+6+20)")
ok(at(rows, 1).text._justify == "CENTER", "a bar's label is centered over it")
local bp = at(rows, 1).bar._points[1] or {}
ok(bp.rel == at(rows, 1).text and bp.y == -6, "the bar hangs the gap below its own label")

rows = drawn("empty label", { weighted("", 50) }, ON)
ok(at(rows, 1).bar._shown == true, "a criterion with no text still draws its bar")
ok(at(rows, 1)._h == 20, "a bar with no label is just the bar")
ok(at(rows, 1).text._text == "", "the empty label draws nothing rather than a stray bullet")
local bp2 = at(rows, 1).bar._points[1] or {}
ok(bp2.rel == at(rows, 1), "with no label the bar anchors to the row itself")

--------------------------------------------------------------------------------------------
-- The styling hook, and the pooled reuse ReleaseCriteria feeds
--------------------------------------------------------------------------------------------
rows = drawn("styling", { weighted("Bar", 50), { kind = LINE.OBJECTIVE, text = "Text" } }, ON)
ok(Media._styled == 1, "ApplyProgressBar runs for the bar row and only for it")
ok(Media._lastBar == at(rows, 1).bar, "the bar that drew is the one that got styled")
ok(Media._skipFill == nil,
   "a scenario bar keeps the user's fill color, unlike a widget bar which skips it")
ok(#Media._fonts == 4, "both the text and the bar label take the criteria font on every row")
ok(#Media._shadows == 4, "and both take the text shadow")
ok(gotBoth(Media._fonts, at(rows, 1)),
   "the font goes on the row's own text AND on the bar label, not twice on one of them")
ok(gotBoth(Media._shadows, at(rows, 1)), "and so does the shadow")

-- ReleaseCriteria is sliced from the shipped file, so what it does to a row it drops is
-- testable here. row:Hide() is the one that matters and the one an array length cannot see:
-- it is what takes an orphaned criterion off SCREEN when a stage shrinks. A build that only
-- stopped tracking the row would leave it drawn over whatever replaced it.
rows = drawn("three before the shrink", {
    { kind = LINE.OBJECTIVE, text = "One" },
    weighted("Two", 50),
    { kind = LINE.OBJECTIVE, text = "Three" },
}, ON)
local orphan = at(rows, 3)
local barOrphan = at(rows, 2)

local builtBefore = rowsBuilt
rows = drawn("shrink", { { kind = LINE.OBJECTIVE, text = "Only one" } }, ON)
ok(#rows == 1, "a shorter run releases the rows it no longer needs")
ok(rowsBuilt == builtBefore, "and builds nothing new, because the pool still holds them")
ok(#Scenario.criteriaPool >= 1, "the released rows go back to the pool rather than leaking")
ok(orphan._shown == false, "a released row is HIDDEN, not merely dropped from the run")
ok(#orphan._points == 0, "and unanchored, or it keeps its old place in the panel")
ok(orphan.icon._shown == false, "its icon goes with it")
ok(#orphan.icon._points == 0, "and the icon is unanchored too")
ok(orphan.text._text == "", "its text is cleared, so a pooled row cannot flash the old string")
ok(orphan.text._width == 0, "and its wrap width is reset")
ok(#orphan.text._points == 0, "and its text is unanchored")
ok(barOrphan.bar._shown == false, "a released BAR row hides its bar")

-- A row that last drew a BAR and is reused as a TEXT row. On the bar path production sets the
-- TEXT's width to the bar width, with a comment saying why: a pooled row otherwise keeps
-- whatever width it last drew with, so one criterion wraps while the next overflows.
rows = drawn("bar then reused as text", { weighted("Wide bar", 50) }, ON)
local reused = at(rows, 1)
rows = drawn("reuse", { { kind = LINE.OBJECTIVE, text = "Now a text row" } }, ON)
ok(at(rows, 1) == reused, "the pool handed back the row that had drawn a bar")
ok(at(rows, 1).bar._shown == false, "the reused row hides the bar it used to draw")
ok(at(rows, 1).icon._shown == true, "and shows the icon it did not need before")
ok(at(rows, 1).text._width == 266, "the reused row re-measures rather than keeping the bar width")
ok(at(rows, 1).text._justify == "LEFT", "and left-aligns again")

--------------------------------------------------------------------------------------------
-- Text-row geometry. The height floor is the other term in the sum Scenario:Render uses to
-- size the panel, so it belongs here beside the bar-row heights rather than being assumed.
--------------------------------------------------------------------------------------------
rows = drawn("text row geometry", { { kind = LINE.OBJECTIVE, text = "Survive" } }, ON)
ok(at(rows, 1)._h == 14,
   "a text row is floored at 14 even though this stub measures its string at 12")
ok(at(rows, 1).text._justify == "LEFT", "a text row is left aligned")
local ip = at(rows, 1).icon._points[1] or {}
ok(ip.p == "LEFT" and ip.x == 8, "the icon sits in from the row edge")
local tp = at(rows, 1).text._points[1] or {}
ok(tp.rel == at(rows, 1).icon and tp.x == 6, "the text hangs off the icon, not the row")
local tp2 = at(rows, 1).text._points[2] or {}
ok(tp2.p == "RIGHT" and tp2.rel == at(rows, 1) and tp2.x == -4,
   "and is pinned to the row's right edge too, which is what gives it a width to wrap in")

rows = drawn("bar label color", { weighted("Bar", 50) }, ON)
local lc = at(rows, 1).text._color or {}
ok(lc[1] == 1 and lc[2] == 0.82 and lc[3] == 0,
   "a bar's label is gold, which is what separates it from an ordinary criterion")

rows = drawn("empty label anchors", { weighted("", 50) }, ON)
local ep = at(rows, 1).text._points[1]
ok(ep == nil, "an empty label is not anchored at all, the bar takes the row top instead")

-- The bars-off text path has two meter branches and only the percentage one was exercised.
rows = drawn("bars off with a count", { meter("Slay the packs", 3, 5) }, SCEN_OFF)
ok(at(rows, 1).bar._shown == false, "a count meter obeys the switch too")
ok(at(rows, 1).text._text == "3/5 Slay the packs",
   "and its numbers survive in the text, the same way a percentage does")

--------------------------------------------------------------------------------------------
-- A row this function has never drawn before. Every case above reuses a pooled row, which
-- ReleaseCriteria has already hidden both regions on, so neither Hide below could fail there.
--------------------------------------------------------------------------------------------
rows = drawn("fresh bar row", { weighted("Bar", 50) }, ON, { fresh = true })
ok(at(rows, 1).icon._shown == false,
   "a bar row hides the icon on a row that arrives shown, as a real texture does")

rows = drawn("fresh text row", { { kind = LINE.OBJECTIVE, text = "One" } }, ON, { fresh = true })
ok(at(rows, 1).bar._shown == false,
   "a text row hides the bar on a row that arrives shown, as a real StatusBar does")

--------------------------------------------------------------------------------------------
-- Degenerate input
--------------------------------------------------------------------------------------------
rows = drawn("no lines", {}, ON)
ok(#rows == 0, "an empty criteria list draws nothing and raises nothing")

-- A container mid-layout answers 0, and every width below it goes negative without the
-- clamps. SetWidth on a negative raises in game, which is what the guards are for.
rows = drawn("zero-width container", { weighted("Bar", 50),
                                       { kind = LINE.OBJECTIVE, text = "Text" } }, ON,
             { container = ZERO_W })
ok(at(rows, 1)._w == 1 and at(rows, 1).bar._w == 1, "a bar row clamps to one pixel, not zero")
ok(at(rows, 2)._w == 1, "and a text row clamps rather than going 16 pixels negative")
ok(at(rows, 2).text._width == 1, "the wrap width clamps too")

rows = drawn("container with no width at all", { { kind = LINE.OBJECTIVE, text = "Text" } }, ON,
             { container = NIL_W })
ok(at(rows, 1)._w == 1, "a nil width falls back rather than raising inside math.max")

--------------------------------------------------------------------------------------------
-- The sub-header. Reported 2026-09-08: a scenario named "Temple Incursion: Cache of the Three"
-- drew straight past the right edge of the tracker instead of wrapping, because the title
-- FontString is anchored on ONE side and so has no width to wrap at.
--------------------------------------------------------------------------------------------
local function newSubHeader(width)
    local sh = { _h = 0, _w = width or 300 }
    sh.cat, sh.text = newFontString(), newFontString()
    function sh:SetHeight(h) self._h = h end
    function sh:GetWidth() return self._w end
    return sh
end

-- Separate state per case rather than one shared Scenario, because ApplyHeaderLabels memoizes
-- on _sCat and _sName and a second case would silently take the early return.
local function newHeader(container, width)
    return { frame = container, subHeader = newSubHeader(width) }
end

-- cfg is optional. Production always passes a table, so nil here is the wider input rather
-- than a shape the game produces. The realistic profile shape is the empty table below.
local function head(msg, st, category, name, cfg)
    local a, aErr = pcall(Scenario.ApplyHeaderLabels, st, category, name)
    ok(a, msg .. ": ApplyHeaderLabels raised - " .. tostring(aErr))
    local b, bErr = pcall(Scenario.ApplyHeaderFont, st, cfg)
    ok(b, msg .. ": ApplyHeaderFont raised - " .. tostring(bErr))
    return st.subHeader
end

-- Reads the delta the title was last fonted at, or nil if it was never fonted. Written as a
-- search rather than an index because ApplyHeaderLabels fonts it too, so the title appears
-- more than once per case and it is the LAST application that reached the screen.
local function titleDeltaSeen(fs)
    local seen
    for i = 1, #Media._headerFonts do
        if Media._headerFonts[i].fs == fs then seen = Media._headerFonts[i].delta end
    end
    return seen
end

-- Nil-safe on purpose. A build that never colors the string leaves _color nil, and indexing
-- that aborts the whole file, which mutate_scenario_bars.py reports as CRASHED rather than as
-- the coverage gap it is. Returning nil makes the same breakage FAIL one assertion instead.
local function channel(fs, i)
    return fs._color and fs._color[i]
end

local sh = head("one tier", newHeader(CONTAINER), "Scenario", "Scenario")
ok(sh.text._width == 284,
   "the title is bounded by the container less the 8 pixel padding on both sides")
ok(sh.cat._shown == false, "a name matching its category draws no second tier")
ok(sh.text._text == "Scenario", "and the title carries the name")

local st = newHeader(CONTAINER)
st.subHeader.text._lines = 1
sh = head("one tier height", st, "Scenario", "Scenario")
ok(st.subHeaderH == 26, "a one-line title keeps the height the sub-header has always had")
ok(sh._h == 26, "and the frame is sized to it")

-- The case the fix exists for. Without the wrap width the string measures as one line, the
-- sub-header stays 26 tall, and the second line is drawn over whatever is under it.
st = newHeader(CONTAINER)
st.subHeader.text._lines = 2
sh = head("wrapped title", st, "Scenario", "Scenario")
ok(st.subHeaderH == 30, "a title that wraps to two lines grows the sub-header (12 * 2 + 6)")
ok(sh._h == 30, "and the frame grows with it, so the criteria below are not drawn over")

st = newHeader(CONTAINER)
sh = head("two tier", st, "Delves", "Collegiate Calamity")
ok(sh.cat._shown == true, "a name that differs from its category draws both tiers")
ok(sh.cat._text == "Delves" and sh.text._text == "Collegiate Calamity",
   "the category goes above and the name below it")
ok(sh.cat._width == 284, "the category is bounded too, so a long one cannot run either")
ok(st.subHeaderH == 31, "cat, the gap, the title and the 6 below it (12 + 1 + 12 + 6)")

st = newHeader(CONTAINER)
st.subHeader.text._lines = 2
head("two tier wrapped", st, "Delves", "Collegiate Calamity")
ok(st.subHeaderH == 43, "a wrapped name grows the two-tier header as well (12 + 1 + 24 + 6)")

-- Production has ONE sub-header, built once and reused for every scenario the player enters,
-- where every case above builds a fresh one. A statement whose only job is to undo the PREVIOUS
-- scenario's state is invisible to those: cat:Show() and both ClearAllPoints could each be
-- deleted with this file green.
st = newHeader(CONTAINER)
head("singleton, first scenario", st, "Scenario", "Scenario")
sh = head("singleton, second scenario", st, "Delves", "Collegiate Calamity")
ok(sh.cat._shown == true,
   "a two-tier scenario after a one-tier one shows its category again on the SAME sub-header")
ok(st.subHeaderH == 31, "and is measured as two tiers rather than keeping the one-tier height")
ok(#sh.text._points == 1,
   "the title carries one anchor, not the one-tier LEFT left standing beside the new TOPLEFT")

st = newHeader(CONTAINER)
head("singleton, first delve", st, "Delves", "Collegiate Calamity")
sh = head("singleton, second delve", st, "Delves", "The Ring of Glory")
ok(#sh.cat._points == 1,
   "and a second two-tier scenario does not stack a second anchor on the category")

-- Scenario:Build is not sliced here, so this is read off the shipped source. ApplyHeaderFont
-- gives this FontString a width now. While it had none it WAS its own text and justification
-- was inert on it. A widthed FontString honors it and LEFT is not the default, which is why
-- subHeader.cat has set it explicitly all along.
ok(src:find('subHeader.text:SetJustifyH("LEFT")', 1, true) ~= nil,
   "the sub-header title pins its own justification, or a widthed title draws centered")

-- Anchors
st = newHeader(CONTAINER)
sh = head("one tier anchor", st, "Scenario", "Scenario")
local hp = sh.text._points[1] or {}
ok(hp.p == "LEFT" and hp.rel == sh and hp.x == 8,
   "a one-tier title anchors to the sub-header at the padding")

st = newHeader(CONTAINER)
sh = head("two tier anchors", st, "Delves", "Collegiate Calamity")
local catP   = sh.cat._points[1] or {}
local titleP = sh.text._points[1] or {}
ok(catP.p == "TOPLEFT" and catP.rel == sh and catP.x == 8,
   "the category anchors at the padding")
ok(titleP.p == "TOPLEFT" and titleP.rel == sh.cat and titleP.y == -1,
   "and the title hangs under the category by CAT_GAP")

-- The font, which is what the height is measured off
ok(#Media._headerFonts >= 2, "both tiers are re-fonted")
local sawTitle, sawCat = false, false
for i = 1, #Media._headerFonts do
    local h = Media._headerFonts[i]
    if h.fs == sh.text and h.delta == 4 then sawTitle = true end
    if h.fs == sh.cat and h.delta == -1 then sawCat = true end
end
ok(sawTitle, "the title takes the section header's own +4 delta")
ok(sawCat, "and the category the -1 above it")

-- A re-font has to reach BOTH tiers. ApplyHeaderLabels fonts them once and then memoizes on
-- the scenario identity, so this is the only path an appearance change has to the category.
st = newHeader(CONTAINER)
head("two tier before re-font", st, "Delves", "Collegiate Calamity")
Media._headerFonts = {}
ok(pcall(Scenario.ApplyHeaderFont, st), "a re-font on a two-tier header raises nothing")
local reTitle, reCat = false, false
for i = 1, #Media._headerFonts do
    local hf = Media._headerFonts[i]
    if hf.fs == st.subHeader.text and hf.delta == 4 then reTitle = true end
    if hf.fs == st.subHeader.cat and hf.delta == -1 then reCat = true end
end
ok(reTitle, "the title is re-fonted on its own")
ok(reCat, "and so is the category, or an appearance change never reaches it")

-- A container that has not laid out yet. ZERO_W is the real case and 0 is TRUTHY in Lua, so it
-- reaches the subtraction rather than the `or 0` beside it. NIL_W is what reaches that one.
-- There is no sub-header fallback to take, and asserting one was testing fiction: the
-- sub-header is anchored to the container at x offset 0 in both Build and Render, so it can
-- only ever answer the width the container already gave.
sh = head("zero-width container", newHeader(ZERO_W), "Scenario", "Scenario")
ok(sh.text._width == 201,
   "a container mid-layout substitutes the banner width rather than wrapping at 1 pixel")
sh = head("nil-width container", newHeader(NIL_W), "Scenario", "Scenario")
ok(sh.text._width == 201, "and so does one that answers no width at all")
-- The substitution is NOT a clamp, which is the failure the first fix walked into: a real
-- tracker narrower than the banner has to keep its own width or the title overflows it.
local NARROW = { GetWidth = function() return 190 end }
sh = head("container narrower than the banner", newHeader(NARROW), "Scenario", "Scenario")
ok(sh.text._width == 174, "a real container narrower than the banner keeps its own width")

-- The reason the sizing sits in ApplyHeaderFont rather than beside the labels: the labels
-- memoize on the scenario identity, so a tracker resized while one stage is up never re-runs
-- them. Only ApplyHeaderFont is called again here, which is what Render does on every repaint.
local RESIZE = { _w = 300 }
function RESIZE:GetWidth() return self._w end
st = newHeader(RESIZE)
head("before resize", st, "Scenario", "Scenario")
ok(st.subHeader.text._width == 284, "the title wraps to the tracker it was drawn in")
RESIZE._w = 200
ok(pcall(Scenario.ApplyHeaderFont, st), "a re-font on a resized tracker raises nothing")
ok(st.subHeader.text._width == 184,
   "and re-wraps a title whose own text has not changed, which the labels alone never would")

--------------------------------------------------------------------------------------------
-- The event title's own size and color, asked for by Entmoot: the banner text below it was
-- stylable and the title naming the scenario was not. Both are read in ApplyHeaderFont, so
-- both reach a scenario already on screen - the labels memoize and would not.
--------------------------------------------------------------------------------------------
-- The defaults first. A config carrying neither key has to land on exactly what the file
-- hardcoded before they existed, or the feature moves every existing player's title.
Media._headerFonts = {}
st = newHeader(CONTAINER)
sh = head("title with no config at all", st, "Scenario", "Scenario", nil)
ok(titleDeltaSeen(sh.text) == 4, "an unconfigured title keeps the +4 it always had")
ok(channel(sh.text, 1) == 0.93 and channel(sh.text, 2) == 0.32
   and channel(sh.text, 3) == 0.10, "and the orange it always had")

-- An EMPTY config is a different path from a nil one: the table exists and the keys do not.
Media._headerFonts = {}
st = newHeader(CONTAINER)
sh = head("title with an empty config", st, "Scenario", "Scenario", {})
ok(titleDeltaSeen(sh.text) == 4, "a config carrying neither key still gives the +4 default")
ok(channel(sh.text, 1) == 0.93 and channel(sh.text, 3) == 0.10, "and the default color")

Media._headerFonts = {}
st = newHeader(CONTAINER)
sh = head("title sized up", st, "Scenario", "Scenario", { scenarioTitleSizeDelta = 9 })
ok(titleDeltaSeen(sh.text) == 9, "a configured delta reaches the title")

-- 0 is TRUTHY in Lua, so `or` is safe here where it would not be for a boolean - and this is
-- the assertion that proves it. A player who deliberately sizes the title down to the base
-- font must keep 0 rather than silently getting the 4 back.
Media._headerFonts = {}
st = newHeader(CONTAINER)
sh = head("title sized to the base font", st, "Scenario", "Scenario", { scenarioTitleSizeDelta = 0 })
ok(titleDeltaSeen(sh.text) == 0, "a delta of 0 survives rather than falling back to 4")

-- Negative is in range on the slider, and it is the case a fallback written as a truth test
-- would also pass, so it is read at both signs.
Media._headerFonts = {}
st = newHeader(CONTAINER)
sh = head("title sized down", st, "Scenario", "Scenario", { scenarioTitleSizeDelta = -3 })
ok(titleDeltaSeen(sh.text) == -3, "and a negative delta reaches it too")

st = newHeader(CONTAINER)
sh = head("title recolored", st, "Scenario", "Scenario",
          { scenarioTitleColor = { r = 0.1, g = 0.2, b = 0.3, a = 1 } })
ok(channel(sh.text, 1) == 0.1 and channel(sh.text, 2) == 0.2 and channel(sh.text, 3) == 0.3,
   "a configured color reaches the title")

-- Per channel, the shape UI/Sections.lua uses on headerColor: a partial table has to fall back
-- channel by channel rather than taking the whole color down with it. A whole-table fallback
-- passes every case above and fails only this one.
st = newHeader(CONTAINER)
sh = head("title recolored on one channel", st, "Scenario", "Scenario",
          { scenarioTitleColor = { g = 0.5 } })
ok(channel(sh.text, 1) == 0.93, "a missing red channel falls back on its own")
ok(channel(sh.text, 2) == 0.5,  "the supplied green is kept")
ok(channel(sh.text, 3) == 0.10, "and the missing blue falls back too")

-- Black has to be reachable. Every channel is 0, which is truthy, so a fallback written as a
-- truth test on the CHANNEL would hand back the orange instead.
st = newHeader(CONTAINER)
sh = head("title in black", st, "Scenario", "Scenario",
          { scenarioTitleColor = { r = 0, g = 0, b = 0, a = 1 } })
ok(channel(sh.text, 1) == 0 and channel(sh.text, 2) == 0 and channel(sh.text, 3) == 0,
   "an all-zero color is honored rather than read as absent")

-- The live restyle path. ApplyHeaderLabels memoizes on the scenario identity, so this second
-- call with a different config is exactly what a player changing the control mid-scenario does.
st = newHeader(CONTAINER)
head("before a restyle", st, "Scenario", "Scenario", nil)
Media._headerFonts = {}
ok(pcall(Scenario.ApplyHeaderFont, st, { scenarioTitleSizeDelta = 7,
                                         scenarioTitleColor = { r = 1, g = 0, b = 0, a = 1 } }),
   "a restyle on a scenario already drawn raises nothing")
ok(titleDeltaSeen(st.subHeader.text) == 7, "and the new size reaches the title")
ok(channel(st.subHeader.text, 1) == 1 and channel(st.subHeader.text, 2) == 0,
   "and so does the new color, which the memoized labels never could")

-- The category tier is deliberately NOT restyled by these two. It is the small grey breadcrumb
-- above the title and keeps its own -1 delta, so a case that let it drift would be a silent
-- scope creep rather than a feature.
Media._headerFonts = {}
st = newHeader(CONTAINER)
sh = head("two tier with a styled title", st, "Delves", "Collegiate Calamity",
          { scenarioTitleSizeDelta = 9, scenarioTitleColor = { r = 1, g = 1, b = 1, a = 1 } })
ok(titleDeltaSeen(sh.text) == 9, "the title takes the configured delta")
ok(titleDeltaSeen(sh.cat) == -1, "while the category keeps its own -1")
-- NIL is the right expectation rather than the grey: Scenario:Build is not sliced into this
-- harness, so the only thing that could have colored the category here is ApplyHeaderFont -
-- and it must not. Colored by mistake, this reads the title's white instead.
ok(sh.cat._color == nil,
   "and ApplyHeaderFont leaves the category's color alone rather than leaking the title's onto it")

--------------------------------------------------------------------------------------------
-- The banner. Reported in the same message: the stage and the name sat off-center on the
-- plaque. The art is sized by its own ATLAS and pinned to the frame's top-left, so the two
-- share a center only while that atlas happens to be BANNER_W wide.
--------------------------------------------------------------------------------------------
-- MEASURED IN GAME, 2026-09-08, inside The Ring of Glory: the evergreen header art is
-- 252.5 x 80 while BANNER_W/BANNER_H are 201 x 83. The width is out by 51.5, which is what put
-- the stage name 25.75 pixels left of the plaque's own center - the report. An earlier version
-- of this file assumed 201 x 83 and so asserted a fiction. The constants were never read off
-- the atlas.
ATLAS_SIZE["evergreen-scenario-trackerheader"] = { 252.5, 80 }
ATLAS_SIZE["evergreen-scenario-trackerheader-final-filigree"] = { 252.5, 80 }
-- Synthetic, and the only reason it exists is to pin the boundary where art and frame agree:
-- no shipped kit is BANNER_W wide, so without it nothing would prove the fallback arithmetic.
ATLAS_SIZE["exact-scenario-trackerheader"] = { 201, 83 }
ATLAS_SIZE["wide-scenario-trackerheader"] = { 240, 83 }
ATLAS_SIZE["sizeless-scenario-trackerheader"] = { 0, 0 }
-- Art too short to hold two lines under the stage line, so the name box falls back to the
-- height it has always had rather than collapsing to a couple of pixels.
ATLAS_SIZE["squat-scenario-trackerheader"] = { 252.5, 40 }
-- Art TALLER than the banner frame. The criteria are laid out from BANNER_H, so the name box
-- has to stay inside the frame's room however tall the art is, or a wrapped name is drawn over
-- the first criterion. No shipped kit is this tall, and that bound was structural while the
-- height was a fixed 28 - deriving it from the art is what made the bound losable.
ATLAS_SIZE["tall-scenario-trackerheader"] = { 252.5, 120 }

local function newBanner()
    local b = { _w = 0, _h = 0, _points = {} }
    b.NormalBG, b.ThemeOverlay, b.FinalBG = newRegion(), newRegion(), newRegion()
    b.Stage, b.Name = newFontString(), newFontString()
    -- What Scenario:Build gives the stage line, which is not sliced here. It is a term in the
    -- name box's height, so a case below drives a DIFFERENT value to prove the derivation reads
    -- it rather than assuming this one.
    b.Stage:SetHeight(18)
    function b:SetSize(w, h) self._w, self._h = w, h end
    function b:Show() self._shown = true end
    function b:ClearAllPoints() self._points = {} end
    function b:SetPoint(pt, rel, relP, x, y)
        self._points[#self._points + 1] = { p = pt, rel = rel, relP = relP, x = x, y = y }
    end
    return b
end

-- ApplyBannerFont and ApplyBannerShadow are outside the slice, so they are stubbed on the
-- state rather than reproduced. Recorded rather than swallowed: a banner drawn without them
-- keeps whatever font the previous scenario left on it.
local function newBannerState()
    local st2 = { banner = newBanner(), subHeader = newSubHeader(), _fonted = 0, _shadowed = 0 }
    function st2:ApplyBannerFont() self._fonted = self._fonted + 1 end
    function st2:ApplyBannerShadow() self._shadowed = self._shadowed + 1 end
    return st2
end

-- The banner first, because most cases below only read it. The state comes second so the two
-- that check the re-font can take it without every other case binding one it never uses.
local function drawBanner(msg, info, cfg)
    local st2 = newBannerState()
    local good, err = pcall(Scenario._DrawBanner, st2, info, cfg)
    ok(good, msg .. ": _DrawBanner raised - " .. tostring(err))
    return st2.banner, st2
end

local function stageInfo(kit, over)
    local i = { textureKit = kit, stage = 1, numStages = 3, stageName = "Examine the Cache" }
    for k, v in pairs(over or {}) do i[k] = v end
    return i
end

local bn, bst = drawBanner("evergreen banner", stageInfo("evergreen-scenario"))
ok(bn._w == 252.5, "the frame TRACKS the measured art rather than the old fixed 201")
ok(bn._h == 83, "while the height is deliberately left at BANNER_H, which the criteria use")
ok(bn.Stage._width == 223.5 and bn.Name._width == 223.5,
   "the strings take the MEASURED evergreen art's width (252.5 - 29), not the frame's 201")
local sp = bn.Stage._points[1] or {}
ok(sp.p == "TOP" and sp.rel == bn.NormalBG,
   "the stage is centered on the ART, never on the frame the art is merely pinned inside")
ok(sp.y == -10, "and hangs the same 10 pixels below the art's top")
-- The pinning IS the diagnosis, and no assertion read it: center the art on the frame instead
-- and the reported bug stops existing with every other case in this file still green.
local np = bn.NormalBG._points[1] or {}
ok(np.p == "TOPLEFT" and np.rel == bn and np.relP == "TOPLEFT",
   "the art is pinned to the FRAME's top-left, which is why a wider atlas overhangs it")
ok(sp.relP == "TOP", "and the stage hangs from the art's own top, not some other edge of it")
ok(bn.NormalBG._useAtlasSize == true, "the art is sized from its own atlas")
-- Set in Build, which no case drives and no grep covered. SetJustifyV became load-bearing in
-- this same diff: the name box grew from a fixed 28 to a derived 42, and MIDDLE is the
-- default, so losing TOP drops every one-line stage name down the plaque.
ok(src:find('banner.Name:SetJustifyV("TOP")', 1, true) ~= nil,
   "the name draws from the TOP of its box, which is what makes a box taller than one line safe")
ok(src:find('banner.Name:SetJustifyH("CENTER")', 1, true) ~= nil,
   "and centered in it, or centering the box on the art buys nothing")
ok(bst._fonted == 1 and bst._shadowed == 1, "the banner is re-fonted and re-shadowed on a draw")

bn = drawBanner("art exactly BANNER_W", stageInfo("exact-scenario"))
ok(bn.Stage._width == 172 and bn.Name._width == 172,
   "an art exactly BANNER_W wide lays the strings out at exactly the 172 they always were")

bn = drawBanner("wider art", stageInfo("wide-scenario"))
ok(bn.Stage._width == 211 and bn.Name._width == 211,
   "a texture kit whose header art is wider takes the strings with it (240 - 29)")
ok(bn._w == 240, "and the frame goes with it, which is what keeps alignment honest")

bn = drawBanner("art with no size", stageInfo("sizeless-scenario"))
ok(bn._w == 201, "art the client cannot size falls the frame back to BANNER_W")
ok(bn.Stage._width == 172,
   "art the client could not size falls back to the frame rather than collapsing to a pixel")
-- The fallback has to reach the anchor as well as the width. A zero-width texture's TOP is its
-- left edge, so centering on it puts half the banner text off the side of the plaque.
ok((bn.Stage._points[1] or {}).rel == bn,
   "and the stage anchors to the frame too, not to a texture with no width to center on")

--------------------------------------------------------------------------------------------
-- The name box's HEIGHT, which is what truncated rather than wrapped. A FontString with an
-- explicit height truncates, and this one was a fixed 28 - one line at any ordinary font size,
-- against a stock tracker that wrapped the same string onto two.
--------------------------------------------------------------------------------------------
bn = drawBanner("name box on the measured art", stageInfo("evergreen-scenario"))
ok(bn.Name._height == 42,
   "the name gets the room left under the stage line: 80 - (10 + 18 + 4) - 6")

bn = drawBanner("name box on unreadable art", stageInfo("sizeless-scenario"))
ok(bn.Name._height == 45,
   "art with no size falls back to the frame's own room (83 - 32 - 6), not to a fixed 28")

bn = drawBanner("name box on tall art", stageInfo("tall-scenario"))
ok(bn.Name._height == 45,
   "art taller than the banner frame is still bounded by it (83 - 32 - 6), because the " ..
   "criteria below are laid out from BANNER_H and a taller box would be drawn over them")

bn = drawBanner("name box on squat art", stageInfo("squat-scenario"))
ok(bn.Name._height == 28,
   "art too short to hold a second line floors at the height the box has always had, so a " ..
   "name that fits today never stops fitting")

-- The stage line's height is a TERM, not an assumption. Driving a different one has to move
-- the room, or the derivation is reading a constant it only appears to depend on.
do
    local st3 = newBannerState()
    st3.banner.Stage:SetHeight(30)
    local goodH, errH = pcall(Scenario._DrawBanner, st3, stageInfo("evergreen-scenario"))
    ok(goodH, "taller stage line: _DrawBanner raised - " .. tostring(errH))
    ok(st3.banner.Name._height == 30,
       "a taller stage line leaves the name less room (80 - (10 + 30 + 4) - 6)")
end

-- pickAtlases, which comes with the banner and had no assertion of its own either
bn = drawBanner("unknown kit", stageInfo("no-such-kit"))
ok(bn.NormalBG._atlas == "evergreen-scenario-trackerheader",
   "a texture kit with no header art of its own falls back to evergreen whole")
bn = drawBanner("no kit at all", stageInfo(nil))
ok(bn.NormalBG._atlas == "evergreen-scenario-trackerheader",
   "and so does a scenario that names no kit")

-- The stage line itself
bn = drawBanner("final stage", stageInfo("evergreen-scenario", { isFinalStage = true }))
ok(bn.Stage._text == "Final Stage", "the last stage says so rather than counting")
ok(bn.FinalBG._shown == true, "and the filigree is drawn over it")
bn = drawBanner("middle stage", stageInfo("evergreen-scenario", { stage = 2 }))
ok(bn.Stage._text == "Stage 2", "a numbered stage carries its own number")
ok(bn.FinalBG._shown == false, "and no filigree")
bn = drawBanner("single stage", stageInfo("evergreen-scenario", { numStages = 1 }))
ok(bn.Stage._text == "", "a one-stage scenario says nothing rather than Stage 1")
ok(bn.Name._text == "Examine the Cache", "the stage name is drawn either way")

-- Production draws into ONE banner, re-anchored whenever the alignment changes in the options
-- panel, where every case above gets a fresh one. So a statement whose only job is to undo the
-- previous draw is invisible to all of them.
do
    local st4 = newBannerState()
    pcall(Scenario._DrawBanner, st4, stageInfo("evergreen-scenario"),
          { scenarioTextAlign = "LEFT" })
    local good4 = pcall(Scenario._DrawBanner, st4, stageInfo("evergreen-scenario"),
                        { scenarioTextAlign = "RIGHT" })
    ok(good4, "realigned banner: _DrawBanner raised")
    ok(#st4.banner._points == 1,
       "re-aligning re-anchors the banner rather than leaving both anchors on it")
    ok(#st4.banner.NormalBG._points == 1, "and the art keeps a single pin across redraws")
    -- The stage's anchor TARGET moves with hasArt now, where it used to be the frame every
    -- time. Two stacked anchors used to be a duplicate of each other and are now a conflict.
    ok(#st4.banner.Stage._points == 1,
       "and the stage keeps a single anchor, which matters now its target moves with hasArt")
end

-- Sizeless art after sized art, through ONE state. The stage anchors to the art when there is
-- one and to the frame when there is not, so this is the pair that can leave two conflicting
-- anchors on it, and a per-case fixture could never build it.
do
    local st5 = newBannerState()
    ok(pcall(Scenario._DrawBanner, st5, stageInfo("evergreen-scenario"), {}),
       "sized then sizeless: the first draw raised")
    ok(pcall(Scenario._DrawBanner, st5, stageInfo("sizeless-scenario"), {}),
       "sized then sizeless: the second draw raised")
    ok(#st5.banner.Stage._points == 1, "the stage carries one anchor after the target changed")
    ok((st5.banner.Stage._points[1] or {}).rel == st5.banner,
       "and it is the FRAME once the art has no size, not the zero-width texture")
end

-- A themed scenario followed by an unthemed one, through one state. The overlay is shown on
-- creation, so a case that only ever draws an unthemed scenario cannot see a dropped Hide.
do
    local st6 = newBannerState()
    ok(pcall(Scenario._DrawBanner, st6,
             stageInfo("evergreen-scenario", { themeR = 1, themeG = 0, themeB = 0 }), {}),
       "themed then plain: the themed draw raised")
    ok(st6.banner.ThemeOverlay._shown == true, "a themed scenario tints the plaque")
    ok(pcall(Scenario._DrawBanner, st6, stageInfo("evergreen-scenario"), {}),
       "themed then plain: the plain draw raised")
    ok(st6.banner.ThemeOverlay._shown == false,
       "and a plain one takes the previous scenario's tint back off it")
end

-- The kit a MIDNIGHT scenario actually draws: 248.99992 x 76.00002, measured in game 2026-09-08
-- in Purge the Undead AND in Prepare for the Ritual, byte-identical both times - so it is the
-- kit's own size rather than one scenario's. Every other case here is built on the evergreen
-- 252.5 x 80, a real measurement but not the one players see in current content, and the two
-- disagree on both axes. Absent from TEXTURE_KIT_OFFSETS, so it takes DEFAULT_OFFSETS and nx 0.
-- The fixture is the ROUNDED pair, and the three expectations below are computed from it: a
-- future session that "corrects" it to the raw reading breaks all three for no gain.
ATLAS_SIZE["midnight-scenario-trackerheader"] = { 249, 76 }
bn = drawBanner("the live Midnight kit", stageInfo("midnight-scenario"))
ok(bn._w == 249, "the frame tracks the Midnight art, which is not the evergreen width")
ok(bn.Stage._width == 220 and bn.Name._width == 220,
   "and the strings take that art's width less the padding, 249 - 29")
ok(bn.Name._height == 38, "with the name box the room it leaves: 76 - (10 + 18 + 4) - 6")
ok((bn.Stage._points[1] or {}).rel == bn.NormalBG,
   "an unlisted kit still centers its stage on the art rather than falling back to the frame")

-- The only shipped kit with a non-zero nx. The art hangs 2 pixels left of the frame there, so
-- the frame is sized to match its RIGHT edge, which is the edge RIGHT alignment pins.
ATLAS_SIZE["delves-scenario-trackerheader"] = { 252.5, 80 }
bn = drawBanner("delve art with an offset", stageInfo("delves-scenario"))
ok(bn._w == 250.5, "a kit whose art hangs left of the frame sizes the frame by its right edge")
do
    -- The invariant the whole fix rests on, and nothing read it: the frame's width carries nx
    -- because the ART's own anchor does. Drop it from the anchor alone and the two edges stop
    -- agreeing while every other assertion here still passes.
    local dnp = bn.NormalBG._points[1] or {}
    ok(dnp.x == -2 and dnp.y == 1, "and the art itself carries that kit's own offset")
    -- The literal above is what pins this. On its own the line below reads dnp.x back out of
    -- the code under test, so dropping nx from BOTH sites would satisfy it.
    ok(bn._w == (252.5 + dnp.x), "so the frame's right edge and the art's are the same edge")
end

-- Alignment moves the FRAME, and the art and the strings go with it
bn = drawBanner("left aligned", stageInfo("evergreen-scenario"), { scenarioTextAlign = "LEFT" })
ok((bn._points[1] or {}).p == "TOPLEFT", "a left-aligned banner anchors by its left edge")
bn = drawBanner("right aligned", stageInfo("evergreen-scenario"), { scenarioTextAlign = "RIGHT" })
ok((bn._points[1] or {}).p == "TOPRIGHT", "and a right-aligned one by its right")
bn = drawBanner("centered", stageInfo("evergreen-scenario"), {})
ok((bn._points[1] or {}).p == "TOP", "with center the default")

-- Driven directly: no case above builds a state with no sub-header, so this guard was
-- deletable with the file green.
ok(pcall(Scenario.ApplyHeaderFont, { frame = CONTAINER }),
   "a state with no sub-header returns rather than raising")

--------------------------------------------------------------------------------------------
-- The seams. Everything above drives the slice, so it all passes with the title settings
-- wired to nothing at all: Scenario:Render is in no slice, and neither is the options panel
-- or the defaults table. These are the only assertions that can see a broken wire.
--------------------------------------------------------------------------------------------
local function otherFile(rel)
    local f = assert(io.open(repoFile(rel), "r"), rel .. " is missing")
    local t = f:read("*a")
    f:close()
    return t
end

-- Whole-line comments are stripped before every grep below, because a plain find cannot tell
-- code from a note: writing `-- self:ApplyHeaderFont(cfg)` above a bare call satisfied all of
-- these while the feature was inert on every client.
local function codeHas(text, needle)
    return (text:gsub("\n[ \t]*%-%-[^\n]*", "\n")):find(needle, 1, true) ~= nil
end

ok(not codeHas("\n    -- self:ApplyHeaderFont(cfg)\n", "self:ApplyHeaderFont(cfg)"),
   "the code grep refuses a commented-out occurrence")
ok(codeHas("\n    self:ApplyHeaderFont(cfg)\n", "self:ApplyHeaderFont(cfg)"),
   "and still finds a real one")

-- Anchored on the ARGUMENT, not the name. Dropping it leaves self:ApplyHeaderFont(), which
-- still satisfies a bare-name grep while making every title setting inert - the title would
-- silently take its fallback on every render and no case above could tell.
ok(codeHas(src, "self:ApplyHeaderFont(cfg)"),
   "Render hands its cfg to ApplyHeaderFont rather than calling it bare")
-- The labels keep the CONSTANT deliberately, because they memoize. Reading the setting there
-- would be a second source of truth that only re-runs when the scenario itself changes.
ok(codeHas(src, "Media:ApplyFont(subHeader.text, TITLE_DELTA)"),
   "and the memoized labels font the title from the constant, not the setting")

local dbSrc = otherFile("Core/DB.lua")
-- Seeded to what the file hardcoded before the keys existed, so nobody's title moves on
-- upgrade. Both carry their trailing comma: without it `= 4` also matches `= 40`, which is a
-- 36 point jump passing the assertion written to prevent it.
ok(codeHas(dbSrc, "scenarioTitleSizeDelta     = 4,"),
   "the title size delta defaults to the 4 the code used to hardcode")
ok(codeHas(dbSrc, "scenarioTitleColor         = { r = 0.93, g = 0.32, b = 0.10, a = 1 },"),
   "and the title color to the orange it used to hardcode")
ok(codeHas(dbSrc, '"scenarioTitleColor", "scenarioTitleSizeDelta",'),
   "and both are reset by the Appearance tab's Reset to Defaults")

local optSrc = otherFile("Options/TabAppearance.lua")
-- relayout both stores and renders, so these two also pin that a change reaches the screen
-- rather than waiting for whatever repaints next.
ok(codeHas(optSrc, 'relayout("scenarioTitleSizeDelta", v)'),
   "the size slider writes the key the renderer reads")
ok(codeHas(optSrc, 'relayout("scenarioTitleColor", v)'),
   "and the color picker writes the one it reads")
-- Trailing `end` for the same reason the defaults carry their comma: `or 4` matches `or 40`.
ok(codeHas(optSrc, "DB().scenarioTitleSizeDelta or 4 end"),
   "and the slider reads its own key back, seeded to the same default")

print(("test_scenario_bars: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
