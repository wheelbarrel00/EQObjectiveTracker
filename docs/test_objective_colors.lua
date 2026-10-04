-- Unit tests for the objective colors, run against the SHIPPED source rather than a copy. Run
-- from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_objective_colors.lua
--
-- WHAT THE FEATURE IS. The X/Y count at the start of an objective was always red with none done,
-- orange part-way and green when done, the line's text a fixed light gray, and a finished line
-- green or in the title color. Each is a color on the Appearance tab now (requested by
-- Rhinoplasty), and the defaults are the old colors exactly.
--
-- WHAT IS HELD HERE. Util.ColorizeProgress against the v2.0.0 function written out below, with
-- the DB's own defaults read off Core/DB.lua, so the defaults are proven to reproduce the old
-- strings byte for byte. Picked colors, a color changed in place, and a profile going back to
-- the default. The finished line's color ahead of the old rules, the old rules intact while it is
-- unset, and an unset one following the done count's color. The objective color reaching every
-- text block, by whole statement.
--
-- OUT OF SCOPE BY CONSTRUCTION: how the colors look, and the pickers themselves, which
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

-- watch builds Era's and TBC's client, whose Original Style title brightens once a quest is done.
local function loadUtil(watch)
    local utilNs = { RegisterModule = function(_, _, m) return m end, Has = {} }
    local chunk = assert(loadfile(repoFile("Core/Util.lua")))
    setfenv(chunk, setmetatable({
        UnitClass = function() return "Mage", "MAGE" end,
        RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } },
        QuestWatchFrame = watch and {} or nil,
        NORMAL_FONT_COLOR = { r = 1, g = 0.82, b = 0 },
    }, { __index = _G }))
    chunk("EQObjectiveTracker", utilNs)
    return utilNs.Util
end

-- The shipped defaults, evaluated from DB.lua's own lines so a changed default is a changed test.
local dbSrc = readFile("Core/DB.lua")
local function default(key)
    local expr = dbSrc:match("\n%s*" .. key .. "%s*=%s*(%b{})%s*,")
    assert(expr, "no default for " .. key)
    return assert(loadstring("return " .. expr))()
end
local DEFAULTS = {
    objectiveColor    = default("objectiveColor"),
    countColorNone    = default("countColorNone"),
    countColorPartial = default("countColorPartial"),
    countColorDone    = default("countColorDone"),
}

-- ------------------------------------------------------------- v2.0.0, from the shipped code

local function oldRepl(have, need)
    local h, n = tonumber(have), tonumber(need)
    if not (h and n) then return have .. "/" .. need end
    local color
    if h == 0    then color = "|cffff5050"
    elseif h < n then color = "|cffeeaa00"
    else              color = "|cff44ff44"
    end
    return color .. have .. "/" .. need .. "|r"
end

local function oldColorize(text)
    if not text or text == "" then return text end
    return (text:gsub("(%d+)%s*/%s*(%d+)", oldRepl))
end

local SAMPLES = {
    "0/5 Boars slain", "3/5 Boars slain", "5/5 Boars slain", "Kill 0/1 and 2/3 and 4/4",
    "12 / 20 Pelts", "10/10", "no count here", "", "0/0", "7/3 overfilled",
}

case("the shipped defaults draw every count exactly as v2.0.0 did", function()
    local Util = loadUtil()
    for _, s in ipairs(SAMPLES) do
        ok(Util.ColorizeProgress(s, DEFAULTS) == oldColorize(s),
           ("defaults on %q: %q vs %q"):format(s, tostring(Util.ColorizeProgress(s, DEFAULTS)), oldColorize(s)))
        ok(Util.ColorizeProgress(s, nil) == oldColorize(s), ("no profile on %q"):format(s))
        ok(Util.ColorizeProgress(s, {}) == oldColorize(s), ("a profile with no colors on %q"):format(s))
    end
    ok(Util.ColorizeProgress(nil, DEFAULTS) == nil, "nil text stays nil")
end)

case("picked colors replace each of the three", function()
    local Util = loadUtil()
    local cfg = { countColorNone = { r = 0, g = 0, b = 1 }, countColorPartial = { r = 1, g = 0, b = 1 },
                  countColorDone = { r = 1, g = 1, b = 1 } }
    ok(Util.ColorizeProgress("0/5 x", cfg) == "|cff0000ff0/5|r x", "none done: " .. Util.ColorizeProgress("0/5 x", cfg))
    ok(Util.ColorizeProgress("2/5 x", cfg) == "|cffff00ff2/5|r x", "some done: " .. Util.ColorizeProgress("2/5 x", cfg))
    ok(Util.ColorizeProgress("5/5 x", cfg) == "|cffffffff5/5|r x", "all done: " .. Util.ColorizeProgress("5/5 x", cfg))
    ok(Util.ColorizeProgress("0/1, 1/2, 2/2", cfg) == "|cff0000ff0/1|r, |cffff00ff1/2|r, |cffffffff2/2|r",
       "all three on one line: " .. Util.ColorizeProgress("0/1, 1/2, 2/2", cfg))
end)

case("a color changed in place is picked up, and a profile going back to none restores the default", function()
    local Util = loadUtil()
    local c = { r = 0, g = 0, b = 1 }
    local cfg = { countColorNone = c }
    local function now() return Util.ColorizeProgress("0/5", cfg) end
    ok(now() == "|cff0000ff0/5|r", "first color")
    -- One channel at a time, so a change test that forgets any one of them is seen.
    c.r = 1
    ok(now() == "|cffff00ff0/5|r", "the same table with only red raised: " .. now())
    c.g = 1
    ok(now() == "|cffffffff0/5|r", "only green raised: " .. now())
    c.b = 0
    ok(now() == "|cffffff000/5|r", "only blue lowered: " .. now())
    cfg.countColorNone = { r = 1, g = 1, b = 0 }
    ok(now() == "|cffffff000/5|r", "an equal new table reads the same")
    cfg.countColorNone = nil
    ok(now() == "|cffff50500/5|r", "unset, back to the old red: " .. now())
    -- The very color held before the unset, so a cache that outlived the unset would keep red.
    cfg.countColorNone = { r = 1, g = 1, b = 0 }
    ok(now() == "|cffffff000/5|r", "and the same pick after that is taken again: " .. now())
    ok(Util.ColorizeProgress("3/5", cfg) == "|cffeeaa003/5|r", "while the other two keep their defaults")
end)

-- ---------------------------------------------------------------------- the finished line

local rowSrc = slice("UI/Row.lua", "local function doneHex(cfg)", "local _scratch = {}")
    .. "\nreturn doneHex"

local function doneHexFor(watch)
    local chunk = assert(loadstring(rowSrc, "row-done"))
    setfenv(chunk, setmetatable({ Util = loadUtil(watch), STATE = {}, DEFAULT_DONE_HEX = "44ff44" },
                                { __index = _G }))
    return chunk()
end

case("a picked finished color wins over every old rule, and unset leaves them as they were", function()
    local doneHex = doneHexFor()
    local white = { r = 1, g = 1, b = 1 }
    ok(doneHex({ finishedObjectiveColor = white }) == "ffffff", "picked: " .. doneHex({ finishedObjectiveColor = white }))
    ok(doneHex({ finishedObjectiveColor = white, overrideCompleteGreen = false }) == "ffffff",
       "even with the completed box off")
    ok(doneHex({ finishedObjectiveColor = white, titleColorMode = "class" }) == "ffffff",
       "and over a title color")
    local teal = { r = 0, g = 0.5, b = 1 }
    ok(doneHex({ finishedObjectiveColor = teal }) == "0080ff",
       "every channel lands in its own place: " .. doneHex({ finishedObjectiveColor = teal }))
    ok(doneHex({}) == "44ff44", "unset, green")
    ok(doneHex(nil) == "44ff44", "no profile, green")
    ok(doneHex({ titleColorMode = "class" }) == "40c7eb", "unset with Class color, the class color as before: "
       .. doneHex({ titleColorMode = "class" }))
    ok(doneHex({ titleColorMode = "class", overrideCompleteGreen = false }) == "44ff44",
       "and green again with the completed box off")
    ok(doneHex({ finishedObjectiveColor = {} }) == "44ff44", "a color table with nothing in it counts as unset")
end)

-- The author's call of 2026-10-03: picking a done color has to recolor the lines a player sees
-- finish, which an unset finished color had left green.
case("an unset finished color follows the done count's color, behind a title color", function()
    local doneHex = doneHexFor()
    local blue = { r = 0, g = 0, b = 1 }
    ok(doneHex({ countColorDone = blue }) == "0000ff", "follows the done color: " .. doneHex({ countColorDone = blue }))
    ok(doneHex({ countColorDone = blue, overrideCompleteGreen = false }) == "0000ff",
       "with the completed box off too, which only ever chose between the title color and this")
    ok(doneHex({ countColorDone = blue, titleColorMode = "class" }) == "40c7eb",
       "a title color with the completed box on still wins: " .. doneHex({ countColorDone = blue, titleColorMode = "class" }))
    ok(doneHex({ countColorDone = blue, titleColorMode = "class", overrideCompleteGreen = false }) == "0000ff",
       "and with that box off the done color is back")
    ok(doneHex({ countColorDone = blue, titleColorMode = "gold" }) == "0000ff", "Gold gives no title color to take over")
    ok(doneHex({ countColorDone = blue, finishedObjectiveColor = { r = 1, g = 1, b = 1 } }) == "ffffff",
       "a picked finished color beats the done color")
    ok(doneHex({ countColorDone = {} }) == "44ff44", "an empty done color counts as unset")
    local watchDone = doneHexFor(true)
    ok(watchDone({ countColorDone = blue, titleColorMode = "original" }) == "ffd100",
       "Original Style on Era and TBC hands over a FINISHED title's brighter gold: "
       .. watchDone({ countColorDone = blue, titleColorMode = "original" }))
    ok(doneHex({ countColorDone = DEFAULTS.countColorDone }) == "44ff44",
       "and the shipped done default is the very green finished lines always had")
end)

-- ------------------------------------------------------------- the wiring, by statement

local row = stripComments(readFile("UI/Row.lua"))
local function has(src, stmt, msg) ok(count(src, stmt) == 1, msg .. " (" .. count(src, stmt) .. ")") end

has(row, [[
    local oc = cfg and cfg.objectiveColor
    local oR, oG, oB = 0.85, 0.85, 0.85
    if oc and oc.r then oR, oG, oB = oc.r, oc.g, oc.b end]], "Render reads the objective color once, the old gray without one")
has(row, [[
            Media:ApplyFont(block, -2)
            block:SetTextColor(oR, oG, oB)]], "and puts it on every text block it draws")
ok(count(row, "Util.ColorizeProgress(") == 2 and count(row, "Util.ColorizeProgress(label, cfg)") == 1
   and count(row, "Util.ColorizeProgress(text, cfg)") == 1, "both count sites hand the profile over")

local defaults = stripComments(dbSrc:sub(1, dbSrc:find("local APPEARANCE_KEYS", 1, true)))
ok(not defaults:find("finishedObjectiveColor%s*="), "the finished color has no default, so it starts unset")
has(dbSrc, [["objectiveColor", "countColorNone", "countColorPartial", "countColorDone", "finishedObjectiveColor",]],
    "Reset to Defaults clears all five")
ok(DEFAULTS.objectiveColor.r == 0.85 and DEFAULTS.objectiveColor.g == 0.85 and DEFAULTS.objectiveColor.b == 0.85,
   "the objective color defaults to the gray every text block was made with")
has(row, "    fs:SetTextColor(0.85, 0.85, 0.85)", "which a new text block still starts in")

print(("test_objective_colors: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
