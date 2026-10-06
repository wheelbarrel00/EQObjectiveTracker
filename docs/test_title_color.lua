-- Unit tests for the quest title colors, run against the SHIPPED source rather than a copy. Run
-- from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_title_color.lua
--
-- WHAT THE FEATURE IS. One Quest Title Color dropdown on the Appearance tab replaced three
-- controls on two tabs: Use class color for titles, the title color override, and Quest Title
-- Color By Difficulty. It adds Gold, which is what turning difficulty off always drew, and
-- Original Style, which copies the tracker Blizzard ships on the client.
--
-- WHAT IS HELD HERE. The promise that nobody's titles change: the shipped v2.0.0 rules are
-- written out below and run against the new code over every combination of the old switches,
-- every quest state, with and without the Classic focus tint, for both the title and the color
-- a finished objective line takes. Then Original Style on each tracker family, the hover
-- brighten, the status line, and the wiring by comment-stripped whole statement.
--
-- OUT OF SCOPE BY CONSTRUCTION: whether OBJECTIVE_TRACKER_BLOCK_HEADER_COLOR holds what Blizzard's
-- code says on a live client (the status line reads it), and the dropdown itself, which
-- test_appearance.lua drives.

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

local function slice(rel, fromAnchor, toAnchor)
    local src = readFile(rel)
    local function only(anchor)
        local at, n, from = nil, 0, 1
        while true do
            local i = src:find(anchor, from, true)
            if not i then break end
            at, n, from = at or i, n + 1, i + 1
        end
        assert(n == 1, ("anchor matched %d times in %s (need exactly 1): %s"):format(n, rel, anchor))
        return at
    end
    local from, to = only(fromAnchor), only(toAnchor)
    assert(to > from, "anchors are out of order in " .. rel)
    return src:sub(from, to - 1)
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

local function near(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-9 end
local function same(r1, g1, b1, r2, g2, b2) return near(r1, r2) and near(g1, g2) and near(b1, b2) end
local function fmt(r, g, b) return ("%s %s %s"):format(tostring(r), tostring(g), tostring(b)) end

-- ------------------------------------------------------------------------------ the rigs

local STATE = { ACTIVE = "active", COMPLETE = "complete", FAILED = "failed" }
local CLASS = { r = 0.25, g = 0.78, b = 0.92 }
local NORMAL = { r = 1, g = 0.82, b = 0 }
-- Deliberately not the watch frame's 0.75, 0.61, 0, so a retail answer can only come from here.
local HEADER = { r = 0.70, g = 0.55, b = 0.05 }
local FOCUS = { 0.35, 0.90, 1.00 }

local function difficulty(level) return { r = level / 100, g = 0.5, b = 1 - level / 100 } end

-- client is "retail" (Blizzard's tracker, Forever included) or "watch" (Era and TBC).
local function loadUtil(client)
    local env = {
        UnitClass = function() return "Mage", "MAGE" end,
        RAID_CLASS_COLORS = { MAGE = CLASS },
        NORMAL_FONT_COLOR = NORMAL,
    }
    if client == "retail" then
        env.ObjectiveTrackerFrame = {}
        env.OBJECTIVE_TRACKER_BLOCK_HEADER_COLOR = HEADER
    else
        env.QuestWatchFrame = {}
    end
    local utilNs = { RegisterModule = function(_, _, m) return m end, Has = {} }
    local chunk = assert(loadfile(repoFile("Core/Util.lua")))
    setfenv(chunk, setmetatable(env, { __index = _G }))
    chunk("EQObjectiveTracker", utilNs)
    return utilNs.Util
end

local rowSrc = slice("UI/Row.lua", "local function doneHex(cfg)", "local _scratch = {}")
    .. "\nreturn doneHex, titleColor, paintTitle"

local function loadRow(client, focusTint)
    local Util = loadUtil(client)
    local chunk = assert(loadstring(rowSrc, "row-title"))
    setfenv(chunk, setmetatable({
        Util = Util, STATE = STATE, DEFAULT_DONE_HEX = "44ff44",
        FOCUS_TINT = focusTint and FOCUS or nil,
        GetQuestDifficultyColor = difficulty,
    }, { __index = _G }))
    local doneHex, titleColor, paintTitle = chunk()
    return { Util = Util, doneHex = doneHex, titleColor = titleColor, paintTitle = paintTitle }
end

-- ------------------------------------------- v2.0.0's rules, written out from the shipped code

local function oldEffective(cfg)
    if cfg and cfg.titleColorUseClass then return CLASS.r, CLASS.g, CLASS.b end
    local ov = cfg and cfg.titleColorOverride
    if ov and ov.r then return ov.r, ov.g, ov.b end
end

local function oldTitle(entry, cfg, focusTint)
    local r, g, b = oldEffective(cfg)
    local recolor = r and (not cfg or cfg.overrideCompleteGreen ~= false)
    if focusTint and entry.isFocused then return FOCUS[1], FOCUS[2], FOCUS[3] end
    if entry.state == STATE.FAILED then return 0.85, 0.27, 0.27 end
    if entry.state == STATE.COMPLETE and not recolor then return 0.27, 0.85, 0.27 end
    if r then return r, g, b end
    if (not cfg or cfg.colorByDifficulty ~= false) and entry.level then
        local c = difficulty(entry.level)
        return c.r, c.g, c.b
    end
    return 0.92, 0.72, 0.02
end

local function hex(r, g, b)
    return ("%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
                                   math.floor(b * 255 + 0.5))
end

local function oldDone(cfg)
    if not cfg or cfg.overrideCompleteGreen == false then return "44ff44" end
    local r, g, b = oldEffective(cfg)
    if r then return hex(r, g, b) end
    return "44ff44"
end

local ENTRIES = {
    { state = STATE.ACTIVE, level = 30 },
    { state = STATE.ACTIVE },
    { state = STATE.COMPLETE, level = 30 },
    { state = STATE.COMPLETE },
    { state = STATE.FAILED, level = 30 },
    { state = STATE.ACTIVE, level = 30, isFocused = true },
    { state = STATE.COMPLETE, level = 30, isFocused = true },
}

local function profiles()
    local out = { false }
    for _, class in ipairs({ "nil", true, false }) do
        for _, ov in ipairs({ "nil", { r = 0.1, g = 0.2, b = 0.3 } }) do
            for _, diff in ipairs({ "nil", true, false }) do
                for _, green in ipairs({ "nil", true, false }) do
                    local c = {}
                    if class ~= "nil" then c.titleColorUseClass = class end
                    if ov ~= "nil" then c.titleColorOverride = ov end
                    if diff ~= "nil" then c.colorByDifficulty = diff end
                    if green ~= "nil" then c.overrideCompleteGreen = green end
                    out[#out + 1] = c
                end
            end
        end
    end
    return out
end

local function describe(c)
    if not c then return "no profile" end
    local keys = {}
    for k, v in pairs(c) do keys[#keys + 1] = k .. "=" .. (type(v) == "table" and "color" or tostring(v)) end
    table.sort(keys)
    return "{" .. table.concat(keys, ",") .. "}"
end

case("every old profile draws every title exactly as v2.0.0 did, on both families", function()
    local checked, wrong = 0, 0
    for _, client in ipairs({ "retail", "watch" }) do
        for _, focusTint in ipairs({ false, true }) do
            local R = loadRow(client, focusTint)
            for _, c in ipairs(profiles()) do
                local cfg = c or nil
                for i, e in ipairs(ENTRIES) do
                    local r, g, b, lit = R.titleColor(e, cfg)
                    local wr, wg, wb = oldTitle(e, cfg, focusTint)
                    checked = checked + 1
                    if not same(r, g, b, wr, wg, wb) or lit ~= false then
                        wrong = wrong + 1
                        if wrong <= 5 then
                            print(("  %s focus=%s %s entry %d: got %s lit=%s, v2.0.0 drew %s")
                                  :format(client, tostring(focusTint), describe(c), i, fmt(r, g, b),
                                          tostring(lit), fmt(wr, wg, wb)))
                        end
                    end
                end
                if R.doneHex(cfg) ~= oldDone(cfg) then
                    wrong = wrong + 1
                    if wrong <= 5 then print("  done line " .. describe(c) .. ": " .. R.doneHex(cfg)) end
                end
            end
        end
    end
    ok(wrong == 0, ("%d of %d old-profile titles and done lines differ from v2.0.0"):format(wrong, checked))
    ok(checked > 1000, "and the grid is the whole grid: " .. checked)
end)

case("each mode picked explicitly draws what it names", function()
    local R = loadRow("retail", false)
    local active = { state = STATE.ACTIVE, level = 40 }
    local noLevel = { state = STATE.ACTIVE }
    local r, g, b = R.titleColor(active, { titleColorMode = "difficulty", titleColorUseClass = true })
    ok(same(r, g, b, 0.4, 0.5, 0.6), "By difficulty beats an old class switch once picked: " .. fmt(r, g, b))
    r, g, b = R.titleColor(active, { titleColorMode = "gold", titleColorOverride = { r = 1, g = 0, b = 0 } })
    ok(same(r, g, b, 0.92, 0.72, 0.02), "Gold beats a stored custom color: " .. fmt(r, g, b))
    r, g, b = R.titleColor(noLevel, { titleColorMode = "class" })
    ok(same(r, g, b, CLASS.r, CLASS.g, CLASS.b), "Class color: " .. fmt(r, g, b))
    r, g, b = R.titleColor(active, { titleColorMode = "custom", titleColorOverride = { r = 1, g = 0, b = 0 } })
    ok(same(r, g, b, 1, 0, 0), "Custom with a color: " .. fmt(r, g, b))
    r, g, b = R.titleColor(active, { titleColorMode = "custom" })
    ok(same(r, g, b, 0.92, 0.72, 0.02), "Custom before a color is picked is gold, as its tooltip says: " .. fmt(r, g, b))
    r, g, b = R.titleColor(noLevel, { titleColorMode = "difficulty" })
    ok(same(r, g, b, 0.92, 0.72, 0.02), "a row with no level under By difficulty is gold: " .. fmt(r, g, b))
    -- A value no build ever wrote, as a profile from a later version could hold. Read as unset,
    -- so the old switches decide, rather than as a mode nothing draws.
    local bogus = { titleColorMode = "neon", colorByDifficulty = false }
    ok(R.Util.TitleColorMode(bogus) == "gold", "an unknown stored mode falls back to the old switches: "
       .. tostring(R.Util.TitleColorMode(bogus)))
    r, g, b = R.titleColor(active, { titleColorMode = "neon" })
    ok(same(r, g, b, 0.4, 0.5, 0.6), "and draws what they say: " .. fmt(r, g, b))
    r, g, b = R.titleColor({ state = STATE.COMPLETE }, { titleColorMode = "gold" })
    ok(same(r, g, b, 0.27, 0.85, 0.27), "Gold keeps a finished quest green: " .. fmt(r, g, b))
    ok(R.doneHex({ titleColorMode = "gold" }) == "44ff44", "and its finished lines")
    r, g, b = R.titleColor({ state = STATE.COMPLETE }, { titleColorMode = "class" })
    ok(same(r, g, b, CLASS.r, CLASS.g, CLASS.b), "Class color recolors a finished quest by default: " .. fmt(r, g, b))
    r, g, b = R.titleColor({ state = STATE.COMPLETE }, { titleColorMode = "class", overrideCompleteGreen = false })
    ok(same(r, g, b, 0.27, 0.85, 0.27), "and leaves it green with that box off: " .. fmt(r, g, b))
end)

case("Original Style copies retail's tracker on retail and Forever", function()
    local R = loadRow("retail", false)
    local cfg = { titleColorMode = "original" }
    local r, g, b, lit = R.titleColor({ state = STATE.ACTIVE, level = 30 }, cfg)
    ok(same(r, g, b, HEADER.r, HEADER.g, HEADER.b), "active titles take the client's header color: " .. fmt(r, g, b))
    ok(lit == true, "and are lit by a hover")
    r, g, b, lit = R.titleColor({ state = STATE.COMPLETE }, cfg)
    ok(same(r, g, b, HEADER.r, HEADER.g, HEADER.b), "a finished title keeps it, as Blizzard's does: " .. fmt(r, g, b))
    ok(lit == true, "and is lit by a hover too")
    r, g, b, lit = R.titleColor({ state = STATE.COMPLETE }, { titleColorMode = "original", overrideCompleteGreen = false })
    ok(same(r, g, b, 0.27, 0.85, 0.27) and lit == false, "green with the completed box off, and never lit")
    r, g, b, lit = R.titleColor({ state = STATE.FAILED }, cfg)
    ok(same(r, g, b, 0.85, 0.27, 0.27) and lit == false, "failed stays red and unlit")
    ok(R.doneHex(cfg) == hex(HEADER.r, HEADER.g, HEADER.b), "finished lines take the header color: " .. R.doneHex(cfg))
    local hr, hg, hb = R.Util.OriginalTitleHighlight()
    ok(same(hr, hg, hb, NORMAL.r, NORMAL.g, NORMAL.b), "the hover brightens to the normal font color")
end)

case("Original Style copies the watch frame on Era and TBC", function()
    local R = loadRow("watch", false)
    local cfg = { titleColorMode = "original" }
    local r, g, b, lit = R.titleColor({ state = STATE.ACTIVE, level = 30 }, cfg)
    ok(same(r, g, b, 0.75, 0.61, 0), "active titles in the watch frame's gold: " .. fmt(r, g, b))
    ok(lit == true, "flagged lit, which a client with no hover color then ignores")
    r, g, b = R.titleColor({ state = STATE.COMPLETE }, cfg)
    ok(same(r, g, b, NORMAL.r, NORMAL.g, NORMAL.b), "a finished one brightens, as QuestWatch_Update does: " .. fmt(r, g, b))
    ok(R.doneHex(cfg) == hex(NORMAL.r, NORMAL.g, NORMAL.b), "and so do its finished lines")
    ok(R.Util.OriginalTitleHighlight() == nil, "the watch frame has no hover color")
    local F = loadRow("watch", true)
    r, g, b = F.titleColor({ state = STATE.ACTIVE, isFocused = true }, cfg)
    ok(same(r, g, b, FOCUS[1], FOCUS[2], FOCUS[3]), "the Classic focus tint still wins: " .. fmt(r, g, b))
end)

case("without the client's header color, retail falls back to the value Blizzard's code uses elsewhere", function()
    local Util = loadUtil("retail")
    local chunk = assert(loadfile(repoFile("Core/Util.lua")))
    local utilNs = { RegisterModule = function(_, _, m) return m end, Has = {} }
    setfenv(chunk, setmetatable({ ObjectiveTrackerFrame = {} }, { __index = _G }))
    chunk("EQObjectiveTracker", utilNs)
    local r, g, b = utilNs.Util.OriginalTitleColor(false)
    ok(same(r, g, b, 0.75, 0.61, 0), "0.75, 0.61, 0: " .. fmt(r, g, b))
    r, g, b = utilNs.Util.OriginalTitleHighlight()
    ok(same(r, g, b, 1, 0.82, 0), "and the highlight falls back to 1, 0.82, 0: " .. fmt(r, g, b))
    ok(Util.TitleColorMode(nil) == "difficulty", "no profile at all reads as By difficulty")
end)

case("a hover brightens only a lit title, and leaving puts it back", function()
    local R = loadRow("retail", false)
    local painted
    local row = { title = { SetTextColor = function(_, r, g, b) painted = fmt(r, g, b) end } }
    row._tR, row._tG, row._tB, row._tLit = 0.2, 0.3, 0.4, true
    R.paintTitle(row)
    ok(painted == fmt(0.2, 0.3, 0.4), "not hovered, the stored color: " .. tostring(painted))
    row._hovered = true
    R.paintTitle(row)
    ok(painted == fmt(NORMAL.r, NORMAL.g, NORMAL.b), "hovered and lit, the highlight: " .. tostring(painted))
    row._tLit = false
    R.paintTitle(row)
    ok(painted == fmt(0.2, 0.3, 0.4), "hovered but unlit, the stored color: " .. tostring(painted))
    local W = loadRow("watch", false)
    row._tLit = true
    W.paintTitle(row)
    ok(painted == fmt(0.2, 0.3, 0.4), "on the watch frame client a hover changes nothing: " .. tostring(painted))
    painted = nil
    W.paintTitle({ title = row.title })
    ok(painted == nil, "a row never rendered is left alone")
end)

case("the status line reads the mode and the client's colors", function()
    local Util = loadUtil("watch")
    local Row = {}
    local chunk = assert(loadstring(slice("UI/Row.lua", "function Row:TitleColorLine()", "local function doneHex(cfg)"),
                                    "title-line"))
    local cfg = { titleColorMode = "original" }
    setfenv(chunk, setmetatable({ Row = Row, Util = Util,
        ns = { GetModule = function() return strictDB({ Tracker = function() return cfg end }) end } }, { __index = _G }))
    chunk()
    local line = Row:TitleColorLine()
    ok(line == "title color: original | original 0.75 0.61 0.00, finished 1.00 0.82 0.00, hover none", "watch: " .. line)
    -- An upgraded profile has no mode saved, and it is the one most likely to be asked about.
    cfg = { colorByDifficulty = false }
    line = Row:TitleColorLine()
    ok(line:find("title color: gold |", 1, true) == 1, "an upgraded Gold profile reads gold: " .. line)
end)

-- ---------------------------------------------------------------- the wiring, by statement

local row = stripComments(readFile("UI/Row.lua"))
local function has(src, stmt, msg) ok(count(src, stmt) == 1, msg .. " (" .. count(src, stmt) .. ")") end

has(row, [[
    local tr, tg, tb, lit = titleColor(entry, cfg)
    row._tR, row._tG, row._tB, row._tLit = tr, tg, tb, lit
    paintTitle(row)]], "Render colors the title through the one function and stores what a hover restores")
has(row, [[
    row._hovered = true
    paintTitle(row)
    paintTooltip(row)]], "entering a row lights its title")
has(row, [[
        if frame._hovered then
            frame._hovered = nil
            paintTitle(frame)
        end]], "leaving puts it back")
has(row, "row._hintShown, row._hintClock, row._hovered = nil, nil, nil", "a retired row forgets its hover")
has(row, "row._tR, row._tG, row._tB, row._tLit = nil, nil, nil, nil", "and its stored color")
has(row, "local hex    = doneHex(cfg)", "finished lines still take doneHex")
ok(count(row, "row.title:SetTextColor") == 2, "the title is colored in paintTitle and nowhere else: "
   .. count(row, "row.title:SetTextColor"))
ok(count(row, "colorByDifficulty") == 0 and count(row, "titleColorUseClass") == 0,
   "Row reads no old switch directly, only the mode")

local db = readFile("Core/DB.lua")
local defaults = db:sub(1, db:find("local APPEARANCE_KEYS", 1, true))
ok(not stripComments(defaults):find("titleColorMode%s*="), "titleColorMode has no AceDB default")
has(db, [["titleColorMode", "colorByDifficulty",]], "Reset to Defaults clears the mode and the switch it is read from")
-- Every key the mode is read off, since a reset leaves no mode saved: a leftover override would
-- read as Custom color and a leftover class switch as Class color.
local resetKeys = stripComments(db:match("local APPEARANCE_KEYS = %b{}") or "")
for _, k in ipairs({ "titleColorMode", "colorByDifficulty", "titleColorUseClass", "titleColorOverride" }) do
    ok(count(resetKeys, '"' .. k .. '"') == 1, "Reset to Defaults clears " .. k)
end
local plainDefaults = stripComments(defaults)
local _, overrideSets = plainDefaults:gsub("titleColorOverride%s*=", "")
ok(overrideSets == 1 and plainDefaults:find("titleColorOverride%s*=%s*nil,") ~= nil,
   "the custom title color has no AceDB default either, or every old profile would read as Custom color")
has(stripComments(readFile("UI/Commands.lua")), [[debugLine("Row", nil, "TitleColorLine")]], "/eqot status prints the line")
ok(count(stripComments(readFile("Options/TabTracker.lua")), "colorByDifficulty") == 0,
   "the Tracker tab no longer carries a difficulty box")

print(("test_title_color: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
