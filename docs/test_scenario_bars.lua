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
-- (Options/TabAppearance.lua also reads the key, at its getter, its setter, and in the sweep
-- that dims the styling group. Those are out of scope here and covered by nothing.)
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
-- OUT OF SCOPE BY CONSTRUCTION: everything above _DrawCriteria draws. The banner, the header,
-- the widget block's own height and Scenario:Render's container arithmetic are reached by no
-- assertion here, so a green run says nothing about them. ReleaseCriteria IS in scope - it is
-- sliced and driven, because the pooled reuse it feeds is half of what _DrawCriteria does.

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

local LINE = {
    OBJECTIVE = "objective", PROGRESSBAR = "progressbar",
    NOTE = "note", WEIGHTED = "weighted",
}

-- Deterministic so every height assertion below can be a literal rather than a reading of
-- the stub it is measuring.
local TEXT_LINE_H = 12
local STUB_BAR_H  = 20

local function newFontString()
    local fs = { _text = "", _width = 0, _justify = nil, _color = nil, _points = {} }
    function fs:ClearAllPoints() self._points = {} end
    function fs:SetPoint(p, rel, relP, x, y)
        self._points[#self._points + 1] = { p = p, rel = rel, relP = relP, x = x, y = y }
    end
    function fs:SetJustifyH(v) self._justify = v end
    function fs:SetWidth(w) self._width = w end
    function fs:SetText(t) self._text = t end
    function fs:SetTextColor(r, g, b) self._color = { r, g, b } end
    function fs:GetStringHeight() return TEXT_LINE_H end
    return fs
end

-- SHOWN, because a real CreateTexture and a real StatusBar both are on creation. Defaulting
-- this to false made it the value a refusal case expects, and both Hide calls on the draw path
-- could then be deleted with the file green. Ask of any stub default whether it is a PASSING
-- value.
local function newRegion()
    local t = { _shown = true, _atlas = nil, _points = {} }
    function t:Show() self._shown = true end
    function t:Hide() self._shown = false end
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
local Media = { _fonts = {}, _shadows = {}, _styled = 0, _lastBar = nil, _skipFill = nil }
function Media:ProgressBarHeight() return STUB_BAR_H end
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

local Util = {}
function Util.SafeSetAtlas(region, atlas) region._atlas = atlas return true end

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

local env = setmetatable({
    ns       = { GetModule = function(_, name) return (name == "Media") and Media or nil end },
    Scenario = Scenario,
    LINE     = LINE,
    Util     = Util,
}, { __index = _G })

local chunk = assert(loadstring(constants .. "\n" .. release .. "\n" .. draw,
                                "@UI/Scenario.lua slice"))
setfenv(chunk, env)
chunk()
assert(Scenario._DrawCriteria, "the UI/Scenario.lua slice defined no _DrawCriteria")
assert(Scenario.ReleaseCriteria, "the UI/Scenario.lua slice defined no ReleaseCriteria")

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

print(("test_scenario_bars: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
