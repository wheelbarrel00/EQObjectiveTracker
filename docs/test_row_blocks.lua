-- Unit tests for UI/Row.lua's objective block builder, run against the SHIPPED source.
-- Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_row_blocks.lua
--
-- Row.lua cannot be loaded whole without a frame stub, so the block builder is sliced out by
-- TEXT ANCHORS rather than line numbers, which drift. If an anchor below stops matching the
-- file, fix the anchor here rather than deleting the test.
--
-- The cases that earn this file: a percentage and a count are told apart by the line KIND
-- rather than guessed from the denominator, because an achievement criterion of 43/100 is a
-- real count and used to render as 43%; bars switched OFF must collapse to text that is
-- byte-identical to what shipped before bars existed, which is what makes the option a real
-- off switch; and the SHRINK case, where a shorter run must not inherit a longer one's tail.
--
-- ONE BAR LINE IS TWO BLOCKS, and every index below turns on it. The label was drawn inside
-- the bar until 2026-08-31 and now sits above it as an ordinary objective line, so a lone bar
-- objective builds a TEXT block holding the label followed by a BAR block holding only the
-- numbers. A label that comes out empty builds the bar alone, and that asymmetry is the case
-- most likely to be broken by a future edit: pushing an empty string would draw a stray "- "
-- bullet above every such bar, and nothing on screen would say where it came from.
--
-- OUT OF SCOPE BY CONSTRUCTION: the slice ends at the layout, so the bar's own centered value
-- string, its height, and the BAR_PAD gap arithmetic are reached by no assertion in this file.
-- A green run here says nothing about the half that draws.

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
end

local path = repoFile("UI/Row.lua")
local fh = assert(io.open(path, "r"))
local src = fh:read("*a")
fh:close()

local FROM_ANCHOR = "local _scratch = {}"
local TO_ANCHOR   = "local function newTextBlock"
local from = src:find(FROM_ANCHOR, 1, true)
local to   = src:find(TO_ANCHOR, 1, true)
assert(from, "anchor not found in UI/Row.lua: " .. FROM_ANCHOR)
assert(to,   "anchor not found in UI/Row.lua: " .. TO_ANCHOR)
assert(to > from, "anchors are out of order in UI/Row.lua")

local slice = src:sub(from, to - 1) .. [[

return {
    build = buildBlocks,
    key   = blocksKey,
    n     = function() return _nBlocks end,
    kind  = function(i) return _bKind[i] end,
    text  = function(i) return _bText[i] end,
    cur   = function(i) return _bCur[i] end,
    req   = function(i) return _bReq[i] end,
    pct   = function(i) return _bPct[i] end,
}
]]

local LINE = {
    OBJECTIVE = "objective", PROGRESSBAR = "progressbar",
    NOTE = "note", WEIGHTED = "weighted",
}

-- StripLeadingCount is SLICED out of the shipped Core/Util.lua rather than restated here, and
-- that is not tidiness. A hand-written stub read `^%d+/%d+%s+` where production reads
-- `^%s*%d+%s*/%s*%d+%s*`, so a label that is nothing BUT its meter stripped to empty in the
-- game and did not in this file - the harness disagreeing with the build it is testing, in
-- either direction depending on the case. It has no dependencies, so there is no reason to
-- copy it. If this anchor stops matching, fix the anchor.
local U_FROM = "function Util.StripLeadingCount"
local ufh = assert(io.open(repoFile("Core/Util.lua"), "r"))
local usrc = ufh:read("*a")
ufh:close()
local ufrom = usrc:find(U_FROM, 1, true)
assert(ufrom, "anchor not found in Core/Util.lua: " .. U_FROM)
local uto = usrc:find("\nend", ufrom, true)
assert(uto, "no end found for " .. U_FROM)

local Util = {}
local uchunk = assert(loadstring("local Util = ...\n" .. usrc:sub(ufrom, uto + 4),
                                 "@Core/Util.lua slice"))
uchunk(Util)
assert(Util.StripLeadingCount, "the Core/Util.lua slice defined nothing")
assert(Util.StripLeadingCount("5/10") == "",
       "the sliced StripLeadingCount does not behave like the shipped one")

-- These two are stubbed rather than sliced, and the reason is NOT that they are unimportant.
-- The real ColorizeProgress wraps a meter in a color escape, so the bars-off assertions below
-- would have to match "|cff...43/100|r Kill things" rather than the plain text they are about.
-- Hex is pure, but nothing in the slice reaches it - its only caller is doneHex, which sits
-- above the slice anchor and is stubbed separately just above.
Util.ColorizeProgress = function(t) return t end
Util.Hex              = function() return "40ff40" end

-- Everything the slice reads but does not declare resolves through this environment.
local env = setmetatable({
    LINE      = LINE,
    BLOCK_BAR = "bar",
    doneHex   = function() return "40ff40" end,
    Util      = Util,
}, { __index = _G })

local chunk = assert(loadstring(slice, "@UI/Row.lua slice"))
setfenv(chunk, env)
local R = chunk()

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end

-- Calling a string method straight off R.text(i) RAISES when a mutant shortens the run, and a
-- file that dies prints no summary line, which every battery in this tree reads as a SURVIVOR.
-- Reading through here turns that into an ordinary failed assertion.
local function txt(i) return R.text(i) or "" end

local function entry(lines) return { lines = lines, groupID = "quests" } end
local ON  = {}
local OFF = { showProgressBars = false }

-- A quest percentage objective is WEIGHTED and fills a fixed 0-100 bar. Two blocks: the label
-- above, the bar below.
R.build(entry({ { text = "Ritual Progress", kind = LINE.WEIGHTED,
                  current = 45, required = 100 } }), ON)
ok(R.n() == 2 and R.kind(1) == nil and R.kind(2) == "bar",
   "a weighted line draws a label above a bar, got " .. tostring(R.n()) .. " blocks")
ok(R.pct(2) == true, "a weighted line is flagged as a percentage")
ok(R.cur(2) == 45 and R.req(2) == 100,
   "weighted pins to 0-100, got " .. tostring(R.cur(2)) .. "/" .. tostring(R.req(2)))

-- An achievement criterion of 43/100 is a real count and must not read as a percentage.
R.build(entry({ { text = "Kill things", kind = LINE.PROGRESSBAR,
                  current = 43, required = 100 } }), ON)
ok(R.kind(2) == "bar", "an achievement meter draws a bar")
ok(R.pct(2) == nil, "43/100 is NOT flagged as a percentage")
ok(R.cur(2) == 43 and R.req(2) == 100, "a count keeps its own numbers")

-- A yes or no objective stays text, and so does anything completed or pre-colored.
R.build(entry({ { text = "Do the thing", kind = LINE.PROGRESSBAR,
                  current = 0, required = 1 } }), ON)
ok(R.n() == 1 and R.kind(1) == nil, "a 0/1 objective stays text")

-- The world quest progress bar. The percentage is carried BESIDE current and required rather
-- than replacing them, so a 0 of 1 objective draws a real bar while the numbers a bars-off row
-- prints stay the ones Blizzard gave us.
R.build(entry({ { text = "Camp destroyed", kind = LINE.PROGRESSBAR,
                  current = 0, required = 1, percent = 30 } }), ON)
ok(R.kind(2) == "bar", "a supplied percentage draws a bar on a 0/1 objective")
ok(R.pct(2) and R.cur(2) == 30 and R.req(2) == 100,
   "drawn against a fixed 100 rather than that denominator, got "
   .. tostring(R.cur(2)) .. "/" .. tostring(R.req(2)))

-- ZERO, on the CONSUMING side. The provider carrying `percent = 0` is asserted in
-- docs/test_quest_progress.lua, and that is the produce half - the same split that let a
-- deleted consumer sit green for a release once already. Quest 92149 was MEASURED at 0%, so a
-- gate written `ln.percent and ln.percent > 0` refuses the one quest the feature exists for
-- while every assertion in both files still passes.
R.build(entry({ { text = "Camp destroyed", kind = LINE.PROGRESSBAR,
                  current = 0, required = 1, percent = 0 } }), ON)
ok(R.kind(2) == "bar", "a percentage of zero still draws a bar")
ok(R.cur(2) == 0 and R.req(2) == 100,
   "empty rather than absent, got " .. tostring(R.cur(2)) .. "/" .. tostring(R.req(2)))

-- The clamp. usable() already range-checks, so this is belt and braces, but it costs one case.
R.build(entry({ { text = "Overflow", kind = LINE.PROGRESSBAR,
                  current = 0, required = 1, percent = 140 } }), ON)
ok(R.cur(2) == 100, "a percentage over 100 is clamped, got " .. tostring(R.cur(2)))

-- The property that makes the option a real off switch, and the one this change broke once:
-- an earlier draft rewrote current and required to 30/100, so a row with bars switched off read
-- `0/100 Camp destroyed` where it had always read `0/1 Camp destroyed`.
R.build(entry({ { text = "Camp destroyed", kind = LINE.PROGRESSBAR,
                  current = 0, required = 1, percent = 30 } }), OFF)
ok(R.n() == 1 and R.kind(1) == nil, "bars off collapses a percentage line to text")
ok(R.text(1):find("0/1 Camp destroyed", 1, true) ~= nil,
   "and prints the objective's OWN numbers, not the percentage: " .. tostring(R.text(1)))
ok(R.text(1):find("0/100", 1, true) == nil,
   "the percentage denominator never reaches the text path: " .. tostring(R.text(1)))

-- A weighted line still draws against 100 from its own current, which is the achievement and
-- scenario path and predates all of this.
R.build(entry({ { text = "Ritual", kind = LINE.WEIGHTED, current = 45, required = 100 } }), ON)
ok(R.pct(2) and R.cur(2) == 45, "a weighted line still fills from its own current")
-- BOTH of these assert R.n() as well, and that is the whole assertion. A bar line pushes its
-- label as a text block FIRST, so index 1 is text whether or not the guard fires - read at
-- index 1 alone these passed with `if ln.richText or ln.completed then return false end`
-- DELETED, which would draw a full bar over a completed objective's checkmark line and route
-- pre-colored engine output into a bar.
R.build(entry({ { text = "Done", kind = LINE.WEIGHTED, current = 100,
                  required = 100, completed = true } }), ON)
ok(R.n() == 1 and R.kind(1) == nil, "a completed weighted line stays text")
R.build(entry({ { text = "Raw", kind = LINE.WEIGHTED, current = 50,
                  required = 100, richText = true } }), ON)
ok(R.n() == 1 and R.kind(1) == nil, "a richText weighted line stays text")

-- Bars OFF must reproduce the wording that shipped before bars existed.
R.build(entry({ { text = "Ritual Progress", kind = LINE.WEIGHTED,
                  current = 45, required = 100 } }), OFF)
ok(R.n() == 1 and R.kind(1) == nil, "bars off collapses the run to one text block")
ok(R.text(1):find("45/100 Ritual Progress", 1, true) ~= nil,
   "bars off keeps the pre-bars wording, got " .. tostring(R.text(1)))
R.build(entry({ { text = "Kill things", kind = LINE.PROGRESSBAR,
                  current = 43, required = 100 } }), OFF)
ok(R.text(1):find("43/100 Kill things", 1, true) ~= nil,
   "a count reads the same with bars off, got " .. tostring(R.text(1)))

-- A bar sitting between two text lines is the whole reason the run exists. The bar's own label
-- MERGES into the text block above it rather than opening a third one, which is what puts it
-- immediately over its bar with no gap of its own - the default tracker's layout exactly.
R.build(entry({
    { text = "first",  kind = LINE.OBJECTIVE },
    { text = "middle", kind = LINE.WEIGHTED, current = 10, required = 100 },
    { text = "last",   kind = LINE.OBJECTIVE },
}), ON)
ok(R.n() == 3, "text, bar, text is three blocks, got " .. tostring(R.n()))
ok(R.kind(1) == nil and R.kind(2) == "bar" and R.kind(3) == nil,
   "the bar keeps the middle slot rather than being pushed under the text")
-- Read into locals rather than compared inline. A mutant that collapses the run leaves one of
-- these nil, and `nil > number` RAISES - which kills the file with no summary line, and every
-- battery in this tree reads a missing summary as a SURVIVOR. The same shape that hid a
-- first-login crash in docs/test_widgets.lua. An assertion must fail, never abort.
local mFirst = txt(1):find("first", 1, true)
local mMid   = txt(1):find("middle", 1, true)
ok(mFirst and mMid,
   "the label joins the block above rather than opening its own: " .. tostring(R.text(1)))
ok(mFirst and mMid and mMid > mFirst,
   "and lands LAST in it, directly above the bar it names")

-- ------------------------------------------------------- the label above the bar

-- The label was drawn INSIDE the bar until 2026-08-31, left-aligned against a right-aligned
-- meter, and the two ran together on a long objective. It is an ordinary objective line now.
R.build(entry({ { text = "Disrupt smuggling operations (40%)", kind = LINE.PROGRESSBAR,
                  current = 0, required = 1, percent = 40 } }), ON)
ok(R.n() == 2, "one bar objective builds two blocks, got " .. tostring(R.n()))
ok(R.kind(1) == nil and R.kind(2) == "bar", "label first, bar second")
ok(txt(1):find("Disrupt smuggling operations", 1, true) ~= nil,
   "the label holds the objective's text: " .. tostring(R.text(1)))
ok(R.text(2) == "", "and the bar holds no label of its own: " .. tostring(R.text(2)))

-- Blizzard bakes the percentage into some objectives as a trailing (N%), and the DEFAULT
-- TRACKER prints it in the label beside a bar showing that same percentage - read off a
-- side-by-side screenshot on 2026-08-31. So it stays. Stripping it would diverge from the
-- thing this feature exists to match, which is the opposite of the obvious tidy-up.
ok(txt(1):find("(40%)", 1, true) ~= nil,
   "the trailing percentage Blizzard supplies is KEPT: " .. tostring(R.text(1)))

-- The leading meter goes, because the bar underneath is already showing those numbers.
R.build(entry({ { text = "7/20 Camps burned", kind = LINE.PROGRESSBAR,
                  current = 7, required = 20 } }), ON)
ok(txt(1):find("7/20", 1, true) == nil,
   "the label drops the count the bar is showing: " .. tostring(R.text(1)))
ok(txt(1):find("Camps burned", 1, true) ~= nil, "and keeps the wording")
ok(txt(1):find("- ", 1, true) == 1,
   "and is dashed like every other objective line: " .. tostring(R.text(1)))

-- The bar clears its own label slot. Nothing in production reads _bText on a bar block, so this
-- pins an invariant rather than guarding a live defect - but it takes a SHRINK across a changed
-- block KIND to see it at all: a text block's content at index 2, then a run whose index 2 is a
-- bar. Blocks are pooled by index, so without the reset that slot keeps the old string.
R.build(entry({
    { text = "", kind = LINE.WEIGHTED, current = 50, required = 100 },
    { text = "STALE", kind = LINE.OBJECTIVE },
}), ON)
ok(R.kind(1) == "bar" and R.kind(2) == nil, "a label-less bar first, then a text block")
ok(txt(2):find("STALE", 1, true) ~= nil, "which holds content at index 2")
R.build(entry({ { text = "Label here", kind = LINE.WEIGHTED,
                  current = 50, required = 100 } }), ON)
ok(R.kind(2) == "bar", "the next run puts a bar at that index")
ok(R.text(2) == "",
   "and it does not inherit the text block's string: " .. tostring(R.text(2)))

-- An empty label draws the bar ALONE. Pushing "" instead would put a blank line above every
-- such bar, and nothing on screen would say where the gap came from.
R.build(entry({ { text = "", kind = LINE.WEIGHTED, current = 60, required = 100 } }), ON)
ok(R.n() == 1 and R.kind(1) == "bar",
   "a label-less bar builds the bar alone, got " .. tostring(R.n()) .. " blocks")
ok(R.cur(1) == 60, "and still fills, got " .. tostring(R.cur(1)))

-- A label that is nothing BUT the meter empties once the meter is stripped, so it takes the
-- same path. This is the shape a bare progressbar objective arrives in.
R.build(entry({ { text = "5/10", kind = LINE.PROGRESSBAR, current = 5, required = 10 } }), ON)
ok(R.n() == 1 and R.kind(1) == "bar",
   "a label that was only its meter draws no empty line above the bar, got "
   .. tostring(R.n()) .. " blocks")

-- The new half-switch. Quest rows off collapses to text exactly as the master does, and the
-- SCENARIO half is not this file's key at all - Row must ignore it, or unticking the scenario
-- box would take the quest bars with it.
R.build(entry({ { text = "Ritual", kind = LINE.WEIGHTED, current = 45, required = 100 } }),
        { showQuestProgressBars = false })
ok(R.n() == 1 and R.kind(1) == nil, "quest rows off collapses a bar line to text")
ok(txt(1):find("45/100 Ritual", 1, true) ~= nil,
   "and prints the pre-bars wording, got " .. tostring(R.text(1)))
-- R.n() is load-bearing here too, and for a different reason: if Row ever DID honor the
-- scenario key the run collapses to one block, and kind(2) would still read "bar" off the
-- previous build, because pooled slots are never cleared past _nBlocks.
R.build(entry({ { text = "Ritual", kind = LINE.WEIGHTED, current = 45, required = 100 } }),
        { showScenarioProgressBars = false })
ok(R.n() == 2 and R.kind(2) == "bar", "the scenario half does not touch a quest row")

-- The repaint key has to move when only a fill moves, or a bar never redraws.
local function keyFor(kind, cur, req)
    R.build(entry({ { text = "x", kind = kind, current = cur, required = req } }), ON)
    return R.key()
end
local k1 = keyFor(LINE.WEIGHTED, 10, 100)
ok(k1 ~= keyFor(LINE.WEIGHTED, 11, 100), "the key moves when the fill moves")
ok(keyFor(LINE.WEIGHTED, 10, 100) == k1, "the key is stable when nothing moves")
ok(keyFor(LINE.PROGRESSBAR, 10, 100) ~= k1, "a count and a percentage key differently")

-- Shrink: a long run then a short one leaves nothing behind.
R.build(entry({
    { text = "a", kind = LINE.OBJECTIVE },
    { text = "b", kind = LINE.WEIGHTED, current = 1, required = 100 },
    { text = "c", kind = LINE.OBJECTIVE },
    { text = "d", kind = LINE.WEIGHTED, current = 2, required = 100 },
    { text = "e", kind = LINE.OBJECTIVE },
}), ON)
local longKey = R.key()
ok(R.n() == 5, "the long run is five blocks, got " .. tostring(R.n()))
R.build(entry({ { text = "solo", kind = LINE.OBJECTIVE } }), ON)
ok(R.n() == 1, "the short run is one block")
ok(R.key():find("solo", 1, true) ~= nil, "the short run holds its own content")
ok(R.key():find("b", 1, true) == nil, "no tail of the long run survives in the key")
ok(R.key() ~= longKey, "the short key differs from the long key")

-- A percentage flag must not survive onto a later count block.
-- Both reads are at the BAR's index. Left at 1 the second one asks a text block whether it is
-- a percentage, which is nil whatever the builder does and so can never fail.
R.build(entry({ { text = "p", kind = LINE.WEIGHTED, current = 5, required = 100 } }), ON)
ok(R.pct(2) == true, "the percentage flag is set")
R.build(entry({ { text = "c", kind = LINE.PROGRESSBAR, current = 5, required = 20 } }), ON)
ok(R.kind(2) == "bar" and R.pct(2) == nil,
   "a stale percentage flag does not survive into a count block")

-- ------------------------------------------------------------------ the text path

-- Every styling option is applied here, once, so it reaches every content type - and none of it
-- was asserted. Five mutants survived on a green file: the checkmark, the dimmed note, the
-- objective-number strip, the finished meter and the bar's own label strip.
R.build(entry({ { text = "Gate opened", kind = LINE.OBJECTIVE, completed = true } }), ON)
ok(R.text(1):find("common%-icon%-checkmark") ~= nil,
   "a completed line keeps its checkmark: " .. tostring(R.text(1)))
ok(R.text(1):find("40ff40", 1, true) ~= nil, "and takes the complete color")

R.build(entry({ { text = "no meter here", kind = LINE.NOTE } }), ON)
ok(R.text(1):find("|cff999999- ", 1, true) ~= nil,
   "a NOTE is dimmed with the dash INSIDE the grey: " .. tostring(R.text(1)))

R.build(entry({ { text = "5/10 Bandages", kind = LINE.OBJECTIVE } }), ON)
ok(R.text(1):find("5/10", 1, true) ~= nil, "the count is kept by default")
R.build(entry({ { text = "5/10 Bandages", kind = LINE.OBJECTIVE } }),
        { showObjectiveNumbers = false })
ok(R.text(1):find("5/10", 1, true) == nil,
   "and stripped when the option is off: " .. tostring(R.text(1)))

-- A finished meter reads as its label alone, matching the default tracker.
R.build(entry({ { text = "Supplies", kind = LINE.PROGRESSBAR,
                  current = 10, required = 10, completed = true } }), OFF)
ok(R.text(1):find("10/10", 1, true) == nil,
   "a finished meter drops its numbers: " .. tostring(R.text(1)))
R.build(entry({ { text = "Supplies", kind = LINE.PROGRESSBAR,
                  current = 4, required = 10 } }), OFF)
ok(R.text(1):find("4/10 Supplies", 1, true) ~= nil,
   "while an unfinished one keeps them: " .. tostring(R.text(1)))

-- The bar label's own cases live under "the label above the bar" above, beside the rest of
-- that behavior, rather than a second time here.

-- ------------------------------------------------------------------ simplify mode

-- Nothing in this file ever set a simplify flag, so hideDone was false on every case above and
-- the whole branch loaded without ever running. Five separate mutants survived on a green file,
-- one of them INVERTING the filter so simplify hid every unfinished objective and showed only
-- the completed ones.
local SIMPLE = { simplifyMode = true }
local mixed  = {
    { text = "found the gate", kind = LINE.OBJECTIVE, completed = true },
    { text = "kill the boss",  kind = LINE.OBJECTIVE },
    { text = "loot the chest", kind = LINE.OBJECTIVE },
}

R.build(entry(mixed), ON)
ok(R.n() == 1, "with simplify off the run is one text block, got " .. tostring(R.n()))
local allThree = R.text(1)
ok(allThree:find("found the gate", 1, true) ~= nil, "holding the completed line")
ok(allThree:find("loot the chest", 1, true) ~= nil, "and the last unfinished one")

R.build(entry(mixed), SIMPLE)
ok(R.n() == 1, "simplify still draws a block")
local firstOnly = R.text(1)
ok(firstOnly:find("kill the boss", 1, true) ~= nil,
   "simplify keeps the first UNFINISHED objective, got: " .. tostring(firstOnly))
ok(firstOnly:find("found the gate", 1, true) == nil,
   "and drops the completed one rather than the unfinished ones")
ok(firstOnly:find("loot the chest", 1, true) == nil,
   "and stops at the first, so the run is one line not two")

-- The per-group switch is the same branch reached by a different input, and UI/Row.lua reads it
-- generically off entry.groupID while both writers in the tree only ever set `achievements`.
local grouped = { simplifyGroups = { quests = true } }
R.build(entry(mixed), grouped)
ok(R.text(1):find("found the gate", 1, true) == nil,
   "the per-group switch hides completed lines too: " .. tostring(R.text(1)))
ok(R.text(1):find("loot the chest", 1, true) ~= nil,
   "but does NOT break after the first, which is simplifyMode's own job")

R.build({ lines = mixed, groupID = "worldquests" }, grouped)
ok(R.text(1):find("found the gate", 1, true) ~= nil,
   "and a group it does not name is untouched")

-- Everything finished would otherwise leave a bare title reading as an entry with no objectives
-- at all, so the last line comes back with its checkmark.
local done = {
    { text = "step one", kind = LINE.OBJECTIVE, completed = true },
    { text = "step two", kind = LINE.OBJECTIVE, completed = true },
}
R.build(entry(done), SIMPLE)
ok(R.n() == 1, "an all-finished entry still draws one block, got " .. tostring(R.n()))
ok(R.text(1):find("step two", 1, true) ~= nil,
   "the LAST line, not the first: " .. tostring(R.text(1)))
ok(R.text(1):find("common%-icon%-checkmark") ~= nil, "and it keeps its checkmark")

print(string.format("test_row_blocks: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
