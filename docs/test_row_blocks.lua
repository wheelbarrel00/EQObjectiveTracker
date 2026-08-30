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

-- Everything the slice reads but does not declare resolves through this environment.
local env = setmetatable({
    LINE      = LINE,
    BLOCK_BAR = "bar",
    doneHex   = function() return "40ff40" end,
    Util = {
        StripLeadingCount = function(t) return (t:gsub("^%d+/%d+%s+", "")) end,
        ColorizeProgress  = function(t) return t end,
        Hex               = function() return "40ff40" end,
    },
}, { __index = _G })

local chunk = assert(loadstring(slice, "@UI/Row.lua slice"))
setfenv(chunk, env)
local R = chunk()

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end

local function entry(lines) return { lines = lines, groupID = "quests" } end
local ON  = {}
local OFF = { showProgressBars = false }

-- A quest percentage objective is WEIGHTED and fills a fixed 0-100 bar.
R.build(entry({ { text = "Ritual Progress", kind = LINE.WEIGHTED,
                  current = 45, required = 100 } }), ON)
ok(R.n() == 1 and R.kind(1) == "bar", "a weighted line draws a bar")
ok(R.pct(1) == true, "a weighted line is flagged as a percentage")
ok(R.cur(1) == 45 and R.req(1) == 100,
   "weighted pins to 0-100, got " .. tostring(R.cur(1)) .. "/" .. tostring(R.req(1)))

-- An achievement criterion of 43/100 is a real count and must not read as a percentage.
R.build(entry({ { text = "Kill things", kind = LINE.PROGRESSBAR,
                  current = 43, required = 100 } }), ON)
ok(R.kind(1) == "bar", "an achievement meter draws a bar")
ok(R.pct(1) == nil, "43/100 is NOT flagged as a percentage")
ok(R.cur(1) == 43 and R.req(1) == 100, "a count keeps its own numbers")

-- A yes or no objective stays text, and so does anything completed or pre-colored.
R.build(entry({ { text = "Do the thing", kind = LINE.PROGRESSBAR,
                  current = 0, required = 1 } }), ON)
ok(R.n() == 1 and R.kind(1) == nil, "a 0/1 objective stays text")

-- The world quest progress bar. The percentage is carried BESIDE current and required rather
-- than replacing them, so a 0 of 1 objective draws a real bar while the numbers a bars-off row
-- prints stay the ones Blizzard gave us.
R.build(entry({ { text = "Camp destroyed", kind = LINE.PROGRESSBAR,
                  current = 0, required = 1, percent = 30 } }), ON)
ok(R.kind(1) == "bar", "a supplied percentage draws a bar on a 0/1 objective")
ok(R.pct(1) and R.cur(1) == 30 and R.req(1) == 100,
   "drawn against a fixed 100 rather than that denominator, got "
   .. tostring(R.cur(1)) .. "/" .. tostring(R.req(1)))

-- ZERO, on the CONSUMING side. The provider carrying `percent = 0` is asserted in
-- docs/test_quest_progress.lua, and that is the produce half - the same split that let a
-- deleted consumer sit green for a release once already. Quest 92149 was MEASURED at 0%, so a
-- gate written `ln.percent and ln.percent > 0` refuses the one quest the feature exists for
-- while every assertion in both files still passes.
R.build(entry({ { text = "Camp destroyed", kind = LINE.PROGRESSBAR,
                  current = 0, required = 1, percent = 0 } }), ON)
ok(R.kind(1) == "bar", "a percentage of zero still draws a bar")
ok(R.cur(1) == 0 and R.req(1) == 100,
   "empty rather than absent, got " .. tostring(R.cur(1)) .. "/" .. tostring(R.req(1)))

-- The clamp. usable() already range-checks, so this is belt and braces, but it costs one case.
R.build(entry({ { text = "Overflow", kind = LINE.PROGRESSBAR,
                  current = 0, required = 1, percent = 140 } }), ON)
ok(R.cur(1) == 100, "a percentage over 100 is clamped, got " .. tostring(R.cur(1)))

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
ok(R.pct(1) and R.cur(1) == 45, "a weighted line still fills from its own current")
R.build(entry({ { text = "Done", kind = LINE.WEIGHTED, current = 100,
                  required = 100, completed = true } }), ON)
ok(R.kind(1) == nil, "a completed weighted line stays text")
R.build(entry({ { text = "Raw", kind = LINE.WEIGHTED, current = 50,
                  required = 100, richText = true } }), ON)
ok(R.kind(1) == nil, "a richText weighted line stays text")

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

-- A bar sitting between two text lines is the whole reason the run exists.
R.build(entry({
    { text = "first",  kind = LINE.OBJECTIVE },
    { text = "middle", kind = LINE.WEIGHTED, current = 10, required = 100 },
    { text = "last",   kind = LINE.OBJECTIVE },
}), ON)
ok(R.n() == 3, "text, bar, text is three blocks, got " .. tostring(R.n()))
ok(R.kind(1) == nil and R.kind(2) == "bar" and R.kind(3) == nil,
   "the bar keeps the middle slot rather than being pushed under the text")

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
R.build(entry({ { text = "p", kind = LINE.WEIGHTED, current = 5, required = 100 } }), ON)
ok(R.pct(1) == true, "the percentage flag is set")
R.build(entry({ { text = "c", kind = LINE.PROGRESSBAR, current = 5, required = 20 } }), ON)
ok(R.pct(1) == nil, "a stale percentage flag does not survive into a count block")

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

-- The meter moves INTO the bar, so a label that already carries one would print it twice.
R.build(entry({ { text = "7/20 Camps burned", kind = LINE.PROGRESSBAR,
                  current = 7, required = 20 } }), ON)
ok(R.kind(1) == "bar", "the meter draws a bar")
ok(R.text(1) == "Camps burned",
   "and its label drops the count the bar is already showing, got: " .. tostring(R.text(1)))

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
