-- Unit tests for the row menu's "Pop out Quest Details", run against the SHIPPED source. Run
-- from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_popout.lua
--
-- WHY THIS FILE EXISTS. DugFromTheEarth reported on 2026-10-15 that the item opened an EMPTY
-- window on WoW Forever. Forever 70425 (and retail's 12.1.7 PTR) moved the window's fill from the
-- global QuestLogPopupDetailFrame_Update into a frame method, so the hand-built sequence skipped
-- the fill and showed a bare frame. The fix hands the quest to QuestUtil.OpenQuestDetails, which
-- each client implements against its own frame. docs/test_row_menu.lua replaces this whole
-- function with a spy, so before this file nothing ran its body.
--
-- The function is sliced out of Data/Providers/Quests.lua by text anchors and run against stubs
-- shaped like three clients: Forever and 12.1.7 (QuestUtil present, no _Update global), retail
-- live (both present), and one with no QuestUtil wrapper, where the old sequence still runs.
--
-- OUT OF SCOPE BY CONSTRUCTION: whether Blizzard's window draws the quest (only the game can
-- show that), and the menu dispatch that reaches this function (docs/test_row_menu.lua).

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

local questsSrc = readFile("Data/Providers/Quests.lua")
local from = only(questsSrc, "local function openQuestDetailsPopup(id)\n")
local to   = only(questsSrc, "\nlocal function abandonQuest(")
assert(to > from, "the pop-out anchors are out of order")
local popoutSrc = questsSrc:sub(from, to)

-- ---------------------------------------------------------------------------- the stubs

local log

-- shape: "forever" (wrapper, no _Update global), "live" (both), "bare" (no wrapper), "emptyutil"
-- (QuestUtil without OpenQuestDetails).
-- inLog: whether the quest log holds the quest. frame: "present", "absent", or "ondemand", the
-- last created only once Blizzard_QuestLog is loaded, which is why the load has to come first.
local function makeEnv(shape, inLog, frame)
    log = {}
    local function note(s) log[#log + 1] = s end

    local popup = {
        Show = function() note("frame:Show") end,
    }
    local env
    env = {
        C_AddOns = {
            LoadAddOn = function(name)
                note("load:" .. tostring(name))
                if frame == "ondemand" and name == "Blizzard_QuestLog" then
                    env.QuestLogPopupDetailFrame = popup
                end
            end,
        },
        C_QuestLog = {
            GetLogIndexForQuestID = function(id)
                note("index:" .. tostring(id))
                if inLog then return 7 end
            end,
            SetSelectedQuest = function(id) note("select:" .. tostring(id)) end,
        },
        StaticPopup_Hide = function(which) note("hide:" .. tostring(which)) end,
        QuestMapFrame_UpdateQuestDetailsButtons = function() note("buttons") end,
    }
    if frame == "present" then env.QuestLogPopupDetailFrame = popup end
    if shape == "forever" or shape == "live" then
        env.QuestUtil = {
            OpenQuestDetails = function(...)
                local args = {}
                for i = 1, select("#", ...) do args[i] = tostring((select(i, ...))) end
                note("wrapper:" .. table.concat(args, ","))
            end,
        }
    elseif shape == "emptyutil" then
        env.QuestUtil = {}
    end
    if shape == "live" or shape == "bare" or shape == "emptyutil" then
        env.QuestLogPopupDetailFrame_Update = function(reset) note("update:" .. tostring(reset)) end
    end
    return setmetatable(env, { __index = _G }), popup
end

-- prevID: the quest the window was last shown for, which a real window keeps on .questID.
local function open(shape, inLog, frame, id, prevID)
    local env, popup = makeEnv(shape, inLog, frame)
    popup.questID = prevID
    local chunk = assert(loadstring(popoutSrc .. "\nreturn openQuestDetailsPopup", "popout-slice"))
    setfenv(chunk, env)
    local fn = chunk()
    local good, err = pcall(fn, id)
    return good, err, popup
end

local function count(prefix)
    local n = 0
    for _, s in ipairs(log) do
        if s:sub(1, #prefix) == prefix then n = n + 1 end
    end
    return n
end

local function indexOf(entry)
    for i, s in ipairs(log) do
        if s == entry then return i end
    end
end

local function dump() return table.concat(log, " ") end

-- ------------------------------------------------------------------------------- the cases

do -- Forever and 12.1.7: the reported client. Blizzard's wrapper does the whole job.
    local good, err, popup = open("forever", true, "present", 81234)
    ok(good, "Forever shape does not raise: " .. tostring(err))
    ok(count("wrapper:") == 1, "Forever opens through QuestUtil.OpenQuestDetails exactly once: " .. dump())
    ok(indexOf("wrapper:81234") ~= nil, "the wrapper gets the quest id and nothing else: " .. dump())
    ok(count("frame:Show") == 0, "Forever never shows the bare frame itself: " .. dump())
    ok(count("select:") == 0 and count("hide:") == 0 and count("buttons") == 0,
       "Forever leaves selection, popups and buttons to the wrapper: " .. dump())
    ok(popup.questID == nil, "Forever does not write the frame's questID itself: " .. tostring(popup.questID))
    ok(indexOf("load:Blizzard_QuestLog") ~= nil
       and indexOf("load:Blizzard_QuestLog") < (indexOf("wrapper:81234") or 0),
       "Blizzard_QuestLog is loaded before the wrapper is called: " .. dump())
end

do -- Retail live: the old global still exists, but the wrapper is still the one used.
    local good, err = open("live", true, "present", 555)
    ok(good, "live shape does not raise: " .. tostring(err))
    ok(indexOf("wrapper:555") ~= nil and count("wrapper:") == 1,
       "retail live opens through the wrapper too: " .. dump())
    ok(count("update:") == 0 and count("frame:Show") == 0,
       "retail live does not also run the old sequence: " .. dump())
end

do -- A quest that is not in the log: nothing opens, on either path.
    local good, err = open("forever", false, "present", 42)
    ok(good, "a quest outside the log does not raise: " .. tostring(err))
    ok(count("wrapper:") == 0 and count("frame:Show") == 0,
       "a quest outside the log opens nothing: " .. dump())
    ok(indexOf("index:42") ~= nil, "the log is asked about this quest: " .. dump())
    local good2, err2 = open("bare", false, "present", 42)
    ok(good2, "a quest outside the log does not raise without the wrapper: " .. tostring(err2))
    ok(count("frame:Show") == 0 and count("select:") == 0,
       "without the wrapper a quest outside the log opens nothing either: " .. dump())
end

do -- No window at all: nothing is called, and nothing raises.
    local good, err = open("forever", true, "absent", 9)
    ok(good, "a client with no popup window does not raise: " .. tostring(err))
    ok(count("wrapper:") == 0, "with no window the wrapper is not called: " .. dump())
end

do -- The window only exists once Blizzard_QuestLog loads: the load comes before the frame test.
    local good, err = open("forever", true, "ondemand", 3030)
    ok(good, "an on-demand window does not raise: " .. tostring(err))
    ok(indexOf("wrapper:3030") ~= nil, "an on-demand window still opens once loaded: " .. dump())
end

do -- No wrapper: the old hand-built sequence still runs, in full.
    local good, err, popup = open("bare", true, "present", 777)
    ok(good, "bare shape does not raise: " .. tostring(err))
    ok(popup.questID == 777, "bare writes the frame's questID: " .. tostring(popup.questID))
    ok(indexOf("select:777") ~= nil, "bare selects the quest: " .. dump())
    ok(indexOf("hide:ABANDON_QUEST") ~= nil and indexOf("hide:ABANDON_QUEST_WITH_ITEMS") ~= nil,
       "bare closes both abandon prompts: " .. dump())
    ok(indexOf("buttons") ~= nil, "bare updates the detail buttons: " .. dump())
    ok(indexOf("update:true") ~= nil, "bare fills the window with a scroll reset: " .. dump())
    ok(count("frame:Show") == 1, "bare shows the window once: " .. dump())
    ok((indexOf("update:true") or 99) < (indexOf("frame:Show") or 0),
       "bare fills the window before showing it: " .. dump())
end

do -- QuestUtil present without OpenQuestDetails: falls back rather than calling nil.
    local good, err = open("emptyutil", true, "present", 12)
    ok(good, "a QuestUtil without the wrapper does not raise: " .. tostring(err))
    ok(indexOf("update:true") ~= nil and count("frame:Show") == 1,
       "a QuestUtil without the wrapper runs the old sequence: " .. dump())
end

do -- The window still on an earlier quest: the click opens the quest clicked, never the one before.
    for _, shape in ipairs({ "forever", "live" }) do
        local good, err = open(shape, true, "present", 2222, 1111)
        ok(good, shape .. " over an earlier quest does not raise: " .. tostring(err))
        ok(indexOf("wrapper:2222") ~= nil and count("wrapper:") == 1,
           shape .. ": the wrapper gets the quest clicked: " .. dump())
        ok(indexOf("index:2222") ~= nil and indexOf("index:1111") == nil,
           shape .. ": and the log is asked about that quest: " .. dump())
    end
    local good, err, popup = open("bare", true, "present", 2222, 1111)
    ok(good and popup.questID == 2222 and indexOf("select:2222") ~= nil and indexOf("select:1111") == nil,
       "bare: the window and the selection move to the quest clicked: " .. tostring(err) .. " " .. dump())
end

print(("test_popout: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
