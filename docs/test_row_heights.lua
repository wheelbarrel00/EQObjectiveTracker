-- Unit tests for the row height re-check, run against the SHIPPED source rather than a copy. Run
-- from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_row_heights.lua
--
-- WHY THIS FILE EXISTS. On WoW Forever, which starts every launch from default settings and so on
-- the bundled GothamXNarrow Black font, a quest whose description wrapped to three lines was laid
-- out two lines tall and the row below it drew over its last line. Row:Render measures a row only
-- when something about it changes, and its repaint gate keeps that height in between, so a short
-- measurement stays on screen. The re-check reads every drawn row again one frame after a pass
-- and asks for a new layout when any of them now reads differently.
--
-- WHAT IS HELD HERE. Row:Drift answers the difference in the same terms Render stored it, sign
-- included, and Row:Rebase takes the current reading as the stored one. The tracker's check
-- coalesces to one timer, skips a hidden tracker, finds the largest move on any active row of any
-- provider, lays out again on a real difference in either direction and ignores rounding, asks
-- through Refresh rather than Render, and gives each row three layouts of its own. Giving up on
-- a row takes its current reading as settled and hands its budget back, so neither one stuck row
-- nor a run of rows drawn at different times can switch the check off.
--
-- OUT OF SCOPE BY CONSTRUCTION, so a green run says nothing about any of it: why the row was laid
-- out short (unmeasured, font timing is only a hypothesis), whether the game reports the right
-- height one frame later, and Row:Render itself, which is too large to slice. What Render stores
-- is pinned by comment-stripped greps at the end.

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

-- Whole identifiers, so any spelling of a stray write counts, not only the one a grep expected.
local function tokens(src, name)
    local n = 0
    for w in src:gmatch("[%w_]+") do if w == name then n = n + 1 end end
    return n
end

-- ------------------------------------------------------------------------ the sliced source

local rowSrc     = readFile("UI/Row.lua")
local trackerSrc = readFile("UI/Tracker.lua")
local driftSrc   = slicer("UI/Row.lua")("function Row:Drift(row)",
                                        "function Row:Render(row, entry, width, cfg)")
-- Anchored on code, never on the note above it: a reworded comment used to rot this slice.
local checkSrc   = slicer("UI/Tracker.lua")("local DRIFT_MAX = ",
                                            "function Tracker:Render()")

-- Read off the files rather than assumed, and held to the literal, so an assertion below cannot
-- grow and shrink with the constant it is testing.
local TITLE_TO_SUB = tonumber(rowSrc:match("\nlocal TITLE_TO_SUB%s*=%s*(%d+)%s*\n"))
ok(TITLE_TO_SUB == 1, "UI/Row.lua's TITLE_TO_SUB is still 1: " .. tostring(TITLE_TO_SUB))
local DRIFT_MAX = tonumber(checkSrc:match("local DRIFT_MAX = (%d+)\n"))
ok(DRIFT_MAX == 3, "UI/Tracker.lua's DRIFT_MAX is still 3: " .. tostring(DRIFT_MAX))
local DRIFT_MIN = tonumber(checkSrc:match("local DRIFT_MIN = ([%d%.]+)\n"))
ok(DRIFT_MIN == 0.5, "UI/Tracker.lua's DRIFT_MIN is still 0.5: " .. tostring(DRIFT_MIN))
-- The declaration and all three comparisons, so a literal written back into any one of them
-- counts here. Two thresholds that can disagree is how a narrowed settle test hid behind the
-- layout test and spent a row's budget on jitter that never reached a layout.
ok(tokens(checkSrc, "DRIFT_MIN") == 4, "and every threshold reads that one constant: "
   .. tokens(checkSrc, "DRIFT_MIN"))

-- ------------------------------------------------------------------------------ the stubs

local function fs(h, shown)
    local s = { h = h, shown = shown ~= false }
    function s:GetStringHeight() return self.h end
    function s:IsShown() return self.shown end
    return s
end

-- A row's title, subtitle and text blocks. stored() adds what Render records.
local function row(title, blocks, sub)
    local r = { title = fs(title), subtitle = fs(sub or 0, sub ~= nil), _textBlocks = {} }
    for i = 1, #blocks do r._textBlocks[i] = fs(blocks[i]) end
    return r
end

local function stored(r)
    local h = r.title.h
    if r.subtitle.shown then h = h + TITLE_TO_SUB + r.subtitle.h end
    for i = 1, #r._textBlocks do h = h + r._textBlocks[i].h end
    r._mStr, r._mText = h, #r._textBlocks
    return r
end

local Row = {}
do
    local chunk = assert(loadstring(driftSrc, "row-drift-slice"))
    setfenv(chunk, setmetatable({ Row = Row, TITLE_TO_SUB = TITLE_TO_SUB }, { __index = _G }))
    chunk()
end

local timers, rows, refreshes, invalidations, invalidatedWith
local Tracker = {}
local RowPool = { byProvider = {} }

local function resetWorld()
    timers, refreshes, invalidations, invalidatedWith = {}, 0, 0, nil
    rows = {}
    RowPool.byProvider = { quests = rows }
    Tracker.frame = { shown = true, IsShown = function(self) return self.shown end }
    Tracker._heightArmed = nil
    Tracker._driftFixes, Tracker._driftLast, Tracker._driftGaveUp = nil, nil, nil
end

-- Refresh ends in a Render, which re-arms the check at its end in production, so the spy re-arms
-- too. That is what makes the cap reachable: without it a check could never follow its own
-- layout.
function Tracker:Refresh()
    refreshes = refreshes + 1
    self:_ArmHeightCheck()
end

-- A direct Render adds a pass of its own rather than coalescing with one already asked for,
-- and Visibility takes a quest count off the end of every render, so the check must never
-- call it.
function Tracker:Render()
    error("the height check called Render directly", 0)
end

-- What GetModule("Row") hands the check. Records the self it was called with, because
-- Row.Invalidate() with a dot raises in game on the nil self.
local RowSpy = setmetatable({
    Invalidate = function(self)
        invalidations = invalidations + 1
        invalidatedWith = self
    end,
}, { __index = function(_, k) return Row[k] end })

do
    local env = setmetatable({
        Tracker = Tracker,
        ns = { GetModule = function(_, name)
            if name == "Row" then return RowSpy end
            if name == "RowPool" then return RowPool end
            error("unexpected module: " .. tostring(name), 0)
        end },
        C_Timer = { After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end },
    }, { __index = _G })
    local chunk = assert(loadstring(checkSrc, "tracker-height-slice"))
    setfenv(chunk, env)
    chunk()
end

-- Fires what is queued NOW, not what those callbacks queue in turn, which is one frame.
local function frame()
    local due = timers
    timers = {}
    for i = 1, #due do
        local okCall, err = pcall(due[i].fn)
        ok(okCall, "a queued height check does not raise" .. (okCall and "" or (" - " .. tostring(err))))
    end
    return #due
end

local function arm()
    local okCall, err = pcall(Tracker._ArmHeightCheck, Tracker)
    ok(okCall, "_ArmHeightCheck does not raise" .. (okCall and "" or (" - " .. tostring(err))))
end

-- Keeps stepping frames, arming again whenever nothing is queued, as later passes would.
local function run(frames)
    for _ = 1, frames do
        if frame() == 0 then arm() frame() end
    end
end

local function drift(r)
    local okCall, res = pcall(Row.Drift, Row, r)
    ok(okCall, "Row:Drift does not raise" .. (okCall and "" or (" - " .. tostring(res))))
    -- Explicit, never `okCall and res or nil`: that shape cannot hand back a legitimate false
    -- or nil, and it would turn a raise and a real answer of 0 into the same report.
    if not okCall then return nil end
    return res
end

local function near(a, b) return a ~= nil and math.abs(a - b) < 1e-9 end

-- ------------------------------------------------------------------------------ Row:Drift

print("== Row:Drift reads the row in the terms Render stored it")
do
    ok(drift(row(15, { 13 })) == 0, "a row Render never measured reads no drift")
    -- Read once and held, never called again inside the message: drift() carries an assertion
    -- of its own, and a second call would report a reading the comparison never saw.
    local r = stored(row(15, { 13, 26 }))
    local d = drift(r)
    ok(d == 0, "an unchanged row reads 0: " .. tostring(d))

    -- The reported shape: a wrapped block laid out two lines tall that now reads three.
    r._textBlocks[2].h = 39
    d = drift(r)
    ok(d == 13, "a block that grew a line reads +13, sign included: " .. tostring(d))
    r._textBlocks[2].h = 13
    d = drift(r)
    ok(d == -13, "and one that shrank reads -13: " .. tostring(d))
    r._textBlocks[2].h = 26 - 0.3
    d = drift(r)
    ok(near(d, -0.3), "a fraction stays a fraction, never rounded: " .. tostring(d))

    local t = stored(row(15, { 13 }))
    t.title.h = 30
    d = drift(t)
    ok(d == 15, "a title that wrapped since counts too: " .. tostring(d))
end

print("== the subtitle counts only while shown, with the gap Render adds for it")
do
    local r = stored(row(15, { 13 }, 11))
    local d = drift(r)
    ok(d == 0, "a shown subtitle is read the way it was stored: " .. tostring(d))
    r.subtitle.h = 22
    d = drift(r)
    ok(d == 11, "and its growth counts: " .. tostring(d))

    local hid = stored(row(15, { 13 }))
    hid.subtitle.h = 50
    ok(drift(hid) == 0, "a hidden subtitle is not read, whatever it holds")
end

print("== only the blocks the last Render used are read")
do
    -- Blocks past _mText are pooled and hidden, and hideBlocks empties them, but one holding
    -- stale text must not count against the row.
    local r = stored(row(15, { 13 }))
    r._textBlocks[2] = fs(40)
    local d = drift(r)
    ok(d == 0, "a pooled block past the run is ignored: " .. tostring(d))
end

print("== Row:Rebase takes the current reading as the stored one")
do
    local r = stored(row(15, { 13 }))
    r._textBlocks[1].h = 39
    local okCall, err = pcall(Row.Rebase, Row, r)
    ok(okCall, "Row:Rebase does not raise: " .. tostring(err))
    local d = drift(r)
    ok(d == 0, "a rebased row reads no drift: " .. tostring(d))
    ok(r._mStr == 15 + 39, "because what it stores is what it now reads: " .. tostring(r._mStr))
    ok(r._mText == 1, "and it leaves the block count alone: " .. tostring(r._mText))

    local fresh = row(15, { 13 })
    okCall, err = pcall(Row.Rebase, Row, fresh)
    ok(okCall and fresh._mStr == nil, "a row Render never measured is left unmeasured: "
       .. tostring(err) .. " " .. tostring(fresh._mStr))
end

-- -------------------------------------------------------------------- the tracker's check

print("== the check is armed once per frame, whatever asks for it")
do
    resetWorld()
    arm() arm() arm()
    ok(#timers == 1, "three arms in one frame queue one check: " .. #timers)
    ok(timers[1] and timers[1].delay == 0, "on the very next frame")
    frame()
    arm()
    ok(#timers == 1, "and firing clears the latch, so the next pass can arm again: " .. #timers)
end

print("== a settled tracker is left alone")
do
    resetWorld()
    rows[1] = stored(row(15, { 13 }))
    rows[2] = stored(row(15, { 26 }, 11))
    arm() frame()
    ok(refreshes == 0 and invalidations == 0, "no row moved, so no layout: " .. refreshes)
end

print("== the settle threshold holds from both sides and in both directions")
do
    for _, c in ipairs({ { 0.4, 0 }, { -0.4, 0 }, { 0.6, 1 }, { -0.6, 1 }, { 1, 1 }, { -1, 1 } }) do
        resetWorld()
        rows[1] = stored(row(15, { 13 }))
        rows[1]._textBlocks[1].h = 13 + c[1]
        arm() frame()
        ok(refreshes == c[2], ("a move of %+.1f lays out %d time(s): %d"):format(c[1], c[2], refreshes))
    end
end

print("== a row that reads differently gets the tracker laid out again")
do
    resetWorld()
    rows[1] = stored(row(15, { 13 }))
    rows[2] = stored(row(15, { 26 }))
    rows[2]._textBlocks[1].h = 39
    arm() frame()
    ok(invalidations == 1, "the repaint gate is cleared, or Render would keep the old height: "
       .. invalidations)
    ok(invalidatedWith == RowSpy, "through Row:Invalidate with the module as self")
    ok(refreshes == 1, "and one layout is asked for: " .. refreshes)
    ok(Tracker._driftFixes == 1 and Tracker._driftLast == 13,
       "counted, with how far it was off: " .. tostring(Tracker._driftFixes) .. " "
       .. tostring(Tracker._driftLast))
end

print("== a shrink counts as much as a growth")
do
    resetWorld()
    rows[1] = stored(row(15, { 26 }))
    rows[1]._textBlocks[1].h = 13
    arm() frame()
    ok(refreshes == 1 and Tracker._driftLast == -13,
       "a row now a line SHORTER is laid out again too: " .. refreshes .. " "
       .. tostring(Tracker._driftLast))
end

print("== the largest move wins wherever it is read")
do
    -- Array keys, so pairs visits them in order and each case controls which row comes first.
    resetWorld()
    rows[1] = stored(row(15, { 13 }))
    rows[2] = stored(row(15, { 13 }))
    rows[1]._textBlocks[1].h = 13 + 13
    rows[2]._textBlocks[1].h = 13 + 0.3
    arm() frame()
    ok(refreshes == 1 and Tracker._driftLast == 13,
       "a real move read FIRST is not masked by a settled row after it: " .. refreshes .. " "
       .. tostring(Tracker._driftLast))

    resetWorld()
    rows[1] = stored(row(15, { 13 }))
    rows[2] = stored(row(15, { 26 }))
    rows[3] = stored(row(15, { 13 }))
    rows[1]._textBlocks[1].h = 13 - 20
    rows[2]._textBlocks[1].h = 26 + 2
    rows[3]._textBlocks[1].h = 13 + 15
    arm() frame()
    ok(Tracker._driftLast == -20, "by magnitude, not by sign or by order: "
       .. tostring(Tracker._driftLast))
end

print("== rows are found by walking the pool, not by counting from one")
do
    -- Production keys rows by quest id, so a walk that only counts from 1 finds none of them.
    resetWorld()
    rows[26789] = stored(row(15, { 13 }))
    rows[91234] = stored(row(15, { 26 }))
    rows[91234]._textBlocks[1].h = 39
    arm() frame()
    ok(refreshes == 1, "a moved row keyed by its quest id is found: " .. refreshes)
end

print("== rows from every provider are read, whichever one the walk visits first")
do
    for flip = 1, 2 do
        resetWorld()
        rows[1] = stored(row(15, { 13 }))
        local other = stored(row(15, { 26 }))
        other._textBlocks[1].h = 39
        RowPool.byProvider.worldquests = { [7001] = other }
        local first = next(RowPool.byProvider)
        if (flip == 1) ~= (first == "worldquests") then
            RowPool.byProvider.quests, RowPool.byProvider.worldquests =
                RowPool.byProvider.worldquests, RowPool.byProvider.quests
        end
        arm() frame()
        ok(refreshes == 1, "the moved provider read " .. (flip == 1 and "first" or "last")
           .. " lays the tracker out once: " .. refreshes)
    end
end

print("== a hidden tracker is not checked")
do
    resetWorld()
    rows[1] = stored(row(15, { 13 }))
    rows[1]._textBlocks[1].h = 39
    Tracker.frame.shown = false
    arm() frame()
    ok(refreshes == 0, "a tracker that is not shown draws nothing, so reads nothing: " .. refreshes)

    resetWorld()
    rows[1] = stored(row(15, { 13 }))
    rows[1]._textBlocks[1].h = 39
    Tracker.frame._eqotHidden = true
    arm() frame()
    ok(refreshes == 0, "and neither does one Visibility has hidden: " .. refreshes)

    resetWorld()
    Tracker.frame = nil
    arm() frame()
    ok(refreshes == 0, "nor one with no frame yet")
end

print("== a height that never settles stops after " .. tostring(DRIFT_MAX) .. " layouts")
do
    resetWorld()
    rows[1] = stored(row(15, { 13 }))
    -- Every read disagrees with the store Render made, however often it lays out.
    local extra = 13
    rows[1]._textBlocks[1].GetStringHeight = function(self) return self.h + extra end
    run(10)
    ok(refreshes == 3, "exactly three layouts, not one per frame: " .. refreshes)
    ok(Tracker._driftFixes == 3, "counted as three: " .. tostring(Tracker._driftFixes))
    ok(Tracker._driftGaveUp == 1, "and ONE refusal, since giving up settles it: "
       .. tostring(Tracker._driftGaveUp))
    ok(#timers == 0, "nothing is left queued, so a refusal does not poll: " .. #timers)
    ok(drift(rows[1]) == 0, "the stuck row now reads as settled")
    ok(rows[1]._mTries == nil or rows[1]._mTries <= DRIFT_MAX,
       "and its budget is not left spent: " .. tostring(rows[1]._mTries))

    -- The refusal must not switch the check off: a new move on the same or any row gets its
    -- full three layouts again.
    extra = 13 + 26
    run(10)
    ok(refreshes == 6, "a later disturbance gets three fresh layouts: " .. refreshes)
    ok(Tracker._driftGaveUp == 2, "and gives up once more: " .. tostring(Tracker._driftGaveUp))
end

print("== a refusal still records how far the row was off")
do
    resetWorld()
    rows[1] = stored(row(15, { 13 }))
    rows[1]._textBlocks[1].h = 13 + 7
    rows[1]._mTries = DRIFT_MAX
    arm() frame()
    ok(refreshes == 0 and Tracker._driftGaveUp == 1, "a check past the cap gives up at once")
    ok(Tracker._driftLast == 7, "and the status line still names the move: "
       .. tostring(Tracker._driftLast))

    -- A new move straight after a give-up, with no settled check between them to reset the run.
    rows[1]._textBlocks[1].h = 13 + 7 + 13
    arm() frame()
    ok(refreshes == 1, "the very next move is laid out rather than refused: " .. refreshes)
end

print("== one settled check hands the budget back")
do
    resetWorld()
    rows[1] = stored(row(15, { 13 }))
    local unsettled = true
    rows[1]._textBlocks[1].GetStringHeight = function(self)
        return unsettled and self.h + 13 or self.h
    end
    arm() frame() frame()
    ok(refreshes == 2, "two layouts while it moved: " .. refreshes)
    unsettled = false
    frame()
    ok(rows[1]._mTries == nil, "a settled read hands that row its budget back: "
       .. tostring(rows[1]._mTries))
    unsettled = true
    run(10)
    ok(refreshes == 5, "so a later disturbance gets its full three again, not one: " .. refreshes)
end

print("== the budget is per row, so a late arrival is not refused for an earlier one's run")
do
    -- The defect this replaced: one run shared by every row. Rows are drawn at different times,
    -- so DRIFT_MAX checks with ANY row moving spent the budget, and the next row to be drawn was
    -- rebased on its FIRST drift and left short for as long as it stayed on screen.
    resetWorld()
    local drawn = {}
    for i = 1, DRIFT_MAX + 1 do
        -- The rows already seen settle, as the layout each of them asked for would settle them.
        for j = 1, #drawn do drawn[j]._textBlocks[1].h = 13 end
        local r = stored(row(15, { 13 }))
        r._textBlocks[1].h = 13 + 11
        rows[i] = r
        drawn[#drawn + 1] = r
        arm() frame()
    end
    ok(refreshes == DRIFT_MAX + 1, "every row drawn in a check of its own is laid out: "
       .. refreshes)
    ok(Tracker._driftGaveUp == nil, "and none of them is refused: "
       .. tostring(Tracker._driftGaveUp))
    ok(rows[DRIFT_MAX + 1]._mTries == 1, "the last one counts its own first try, not the run: "
       .. tostring(rows[DRIFT_MAX + 1]._mTries))
end

print("== the two calls the check makes into production do what the spies stand in for")
do
    -- The check above runs against a RowSpy and a stub Tracker:Refresh, so neutering either of
    -- the real ones leaves every assertion in this file green while the short height stays on
    -- screen. Both are small enough to slice and drive for real.
    local realRow = {}
    local chunk = assert(loadstring(
        slicer("UI/Row.lua")("Row.generation = 0", "function Row:Drift(row)"), "row-invalidate"))
    setfenv(chunk, setmetatable({ Row = realRow }, { __index = _G }))
    chunk()
    ok(realRow.generation == 0, "Row starts at generation 0: " .. tostring(realRow.generation))
    realRow:Invalidate()
    realRow:Invalidate()
    ok(realRow.generation == 2, "and Invalidate really moves it, so Render's gate misses: "
       .. tostring(realRow.generation))

    -- Render is too large to slice, so the gate field is pinned by grep in all three places it
    -- has to appear. Drop it from the comparison and Invalidate stops reaching the screen.
    local rowCode = stripComments(rowSrc)
    ok(count(rowCode, "       and row._sGen   == self.generation\n") == 1,
       "Render's repaint gate compares the generation Invalidate moves")
    ok(count(rowCode, "    row._sGen = self.generation\n") == 1, "stores it at the end of a pass")
    ok(count(rowCode, "row._sTime, row._sGen, row._sCardBg  = nil, nil, nil\n") == 1,
       "and Row:Reset clears it")

    local realTracker = { frame = {}, Render = function(t) t.rendered = (t.rendered or 0) + 1 end }
    local debounced = {}
    local tchunk = assert(loadstring(
        slicer("UI/Tracker.lua")("function Tracker:Refresh()", "local _buildRow, _resetRow"),
        "tracker-refresh"))
    setfenv(tchunk, setmetatable({
        Tracker = realTracker,
        REFRESH_THROTTLE = 0.25,
        ns = { GetModule = function(_, name)
            ok(name == "Events", "Refresh asks for Events: " .. tostring(name))
            return { Debounce = function(_, key, delay, fn)
                debounced[#debounced + 1] = { key = key, delay = delay, fn = fn }
            end }
        end },
    }, { __index = _G }))
    tchunk()
    realTracker:Refresh()
    ok(#debounced == 1, "Refresh really asks for a render: " .. #debounced)
    ok(debounced[1] and debounced[1].key == "eqot.render",
       "on the shared render key, so it coalesces with one already asked for: "
       .. tostring(debounced[1] and debounced[1].key))
    if debounced[1] then debounced[1].fn() end
    ok(realTracker.rendered == 1, "and what it queues is a Render: "
       .. tostring(realTracker.rendered))

    realTracker.frame = nil
    realTracker:Refresh()
    ok(#debounced == 1, "with no frame yet it asks for nothing: " .. #debounced)
end

print("== the status line reads the counters it names")
do
    resetWorld()
    Tracker._driftFixes, Tracker._driftLast, Tracker._driftGaveUp = 2, 13, 1
    local okCall, line = pcall(Tracker.HeightLine, Tracker)
    ok(okCall and line == "row heights: laid out again 2 time(s) after drawing, last off by +13.0px, gave up 1",
       "HeightLine: " .. tostring(line))
    resetWorld()
    okCall, line = pcall(Tracker.HeightLine, Tracker)
    ok(okCall and line == "row heights: laid out again 0 time(s) after drawing, last off by +0.0px, gave up 0",
       "and on a fresh session: " .. tostring(line))
end

-- ------------------------------------------------------------------ the wiring, by grep

print("== Render stores what Drift reads, and every pass arms the check")
do
    ok(count(stripComments("a\n--[[\nx()\n]]\n-- x()\nb = 1 -- x()\n"), "x()") == 0,
       "the comment stripper removes block, whole-line and trailing comments")

    local rowCode = stripComments(rowSrc)
    ok(count(rowCode, "            blockH = block:GetStringHeight()\n"
                   .. "            textH = textH + blockH\n") == 1,
       "Render adds every text block to the sum, right where the block is measured")
    ok(count(rowCode, "    row._mStr, row._mText = titleH + subH + textH, nText\n") == 1,
       "and stores title, subtitle and text with the number of blocks it used")
    -- Drift adds TITLE_TO_SUB for a shown subtitle because Render's subH already holds it.
    ok(count(rowCode, "local subH   = row.subtitle:IsShown() and (TITLE_TO_SUB"
                   .. " + row.subtitle:GetStringHeight()) or 0") == 1,
       "Render's subH still includes TITLE_TO_SUB, which Drift mirrors")
    ok(count(rowCode, "    row._mStr, row._mText, row._mTries = nil, nil, nil\n") == 1,
       "Row:Reset clears the stored measurement and the row's budget with the rest of it")
    -- Every occurrence of each name, in any spelling, so a stray reset or a second sum cannot
    -- hide beside the lines pinned above. The totals are asserted rather than the split between
    -- the functions, so moving a use from one to another has to be read here deliberately.
    ok(tokens(rowCode, "_mStr") == 7, "_mStr appears exactly 7 times: " .. tokens(rowCode, "_mStr"))
    ok(tokens(rowCode, "_mText") == 3, "_mText appears exactly 3 times: " .. tokens(rowCode, "_mText"))
    ok(tokens(rowCode, "_mTries") == 1, "_mTries appears in UI/Row.lua only to be cleared: "
       .. tokens(rowCode, "_mTries"))
    ok(tokens(rowCode, "textH") == 4, "textH appears exactly 4 times: " .. tokens(rowCode, "textH"))

    local trackerCode = stripComments(trackerSrc)
    ok(count(trackerCode, "    self:_EnsureTimerTicker(hasTimed, soonestExpiry)\n"
                       .. "    self:_ArmHeightCheck()\n") == 1,
       "Render arms the check at the end of every full pass")
    ok(tokens(trackerCode, "_ArmHeightCheck") == 2, "and nothing else arms it: "
       .. tokens(trackerCode, "_ArmHeightCheck"))
    ok(tokens(trackerCode, "_heightCheck") == 3, "nor schedules the check another way: "
       .. tokens(trackerCode, "_heightCheck"))

    local commands = stripComments(readFile("UI/Commands.lua"))
    ok(count(commands, '    debugLine("Tracker", "scroll: ", "DebugScroll")\n'
                    .. '    debugLine("Tracker", nil, "HeightLine")\n') == 1,
       "/eqot status prints the counters, unconditionally, beside the scroll line")
end

print(("test_row_heights: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
