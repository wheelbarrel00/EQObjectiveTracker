-- luacheck: globals GetQuestLink IsModifiedClick ChatEdit_GetActiveWindow ChatEdit_InsertLink
--
-- Unit tests for shift-clicking a tracker row into chat, run against the SHIPPED source.
-- Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_quest_link.lua
--
-- Two halves, because the feature is two halves and the recorded produce/consume split says a
-- harness that only tests one of them looks complete and is not. Data/QuestLink.lua loads whole
-- - it touches no frame - and chatLinkClick is SLICED out of UI/Row.lua by text anchor, the way
-- docs/test_row_blocks.lua slices the block builder.
--
-- The cases that earn this file:
--
--   1. The gesture REPLACED a destructive one. Shift-click used to hide the row, per character,
--      with no undo but a slash command, and a user lost three quests to it. Nothing here may
--      let the modifier reach a branch that changes state.
--   2. It must NOT fire without a focused chat box. Consuming the click when nobody is linking
--      takes the row's ordinary left-click away, which is the shape of the bug it replaces.
--   3. It must return FALSE rather than swallowing the click whenever it cannot produce a link,
--      or a provider with no link silently loses its normal click too.
--   4. Classic must not reach for the client's own link. Everything Quests ships plain text
--      there and its own harness asserts the call is never made. These two addons share a
--      chat format on purpose, so a divergence here is a real defect rather than a style
--      choice.
--   5. Zero and nil are different answers. A quest with no level still shares, in the shorter
--      form, and a quest with no title on a client with no link shares NOTHING rather than a
--      bare "(id)" nobody can read.
--
-- OUT OF SCOPE BY CONSTRUCTION: the slice starts at chatLinkClick, so onMouseUp's ORDER - that
-- the link branch sits ahead of split-click and the row menu - is reached by no assertion here.

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
end

local function readFile(rel)
    local fh = assert(io.open(repoFile(rel), "r"))
    local s = fh:read("*a")
    fh:close()
    return s
end

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end

-- ------------------------------------------------------------------- Data/QuestLink.lua

-- calls counts the client call being REACHED, not merely answering. The Classic case is the
-- only place this matters and it is the whole point of that branch: a nil-return check alone
-- would pass against a build that asked the client and then threw the answer away.
local calls
local function build(opts)
    opts = opts or {}
    calls = 0
    local mods = {}

    _G.GetQuestLink = nil
    if opts.link ~= nil then
        _G.GetQuestLink = function(id)
            calls = calls + 1
            return opts.link(id)
        end
    end

    -- Written with an explicit if rather than "a and b or c": hasLink false is the case that
    -- matters here and that idiom silently yields c for it, which is how the first cut of this
    -- helper reported a passing guard that was never exercised.
    local hasLink = (opts.link ~= nil)
    if opts.hasLink ~= nil then hasLink = opts.hasLink end

    local ns = { Has = {
        -- Set independently of the stub above, so a case can hold the API present while the
        -- flag is false. That is what proves the guard rather than the absence.
        QuestLog  = opts.retail ~= false,
        QuestLink = hasLink,
    } }
    function ns:RegisterModule(n, t) mods[n] = t return t end
    function ns:GetModule(n) return mods[n] end

    assert(loadfile(repoFile("Data/QuestLink.lua")))("EQObjectiveTracker", ns)
    return mods.QuestLink, ns
end

-- pcall'd, so a mutant that RAISES fails an assertion here rather than aborting the file. Every
-- battery in this tree reads a MISSING summary line as a survivor, so an aborting harness
-- reports a real defect as a coverage hole - the recorded docs/test_widgets.lua failure. Two
-- mutants land here: dropping the pcall around the client call, and dropping the quest id type
-- guard, which reaches string.format with a nil.
local function linkOf(QL, ...)
    local okCall, v = pcall(QL.For, QL, ...)
    if not okCall then return "<raised: " .. tostring(v) .. ">" end
    return v
end

print("== retail uses the client's own link")
do
    local QL = build{ link = function(id) return "|Hquest:" .. id .. ":18|h[Name]|h" end }
    ok(linkOf(QL, 155, "Name", 18) == "|Hquest:155:18|h[Name]|h", "a real link is passed through")
    ok(calls == 1, "the client was asked exactly once")
end

print("== retail falls back to plain text rather than sharing nothing")
do
    -- The gesture promises a link. A quest the client cannot name must still share something
    -- readable, or shift-click reads as broken on exactly the quests it cannot resolve.
    local cases = {
        ["an empty answer"]        = function() return "" end,
        ["a hollow answer"]        = function() return "Name" end,
        ["a raising client call"]  = function() error("nope") end,
        ["a non-string answer"]    = function() return 7 end,
    }
    for label, fn in pairs(cases) do
        local QL = build{ link = fn }
        ok(linkOf(QL, 155, "Name", 18) == "[[18] Name (155)]", label .. " falls back to plain text")
    end

    -- No counting closure is installed when the global is absent, so an "it was never
    -- called" assertion here could not fail whatever production did. The line below does
    -- the work: a build that called the nil global would raise and never reach the plain
    -- form. The guard proper is the hasLink case underneath, where the global IS present.
    local QL = build{}
    ok(linkOf(QL, 155, "Name", 18) == "[[18] Name (155)]", "no GetQuestLink at all falls back")

    -- Present but not probed. Has.QuestLink false with the global sitting right there is the
    -- one shape that separates the guard from the absence.
    local guarded = build{ link = function() return "|Hquest:1:1|h[X]|h" end, hasLink = false }
    ok(linkOf(guarded, 155, "Name", 18) == "[[18] Name (155)]", "Has.QuestLink false is honored")
    ok(calls == 0, "Has.QuestLink false means the client is never asked")
end

print("== Classic must not reach for the client link")
do
    local QL = build{ retail = false, link = function(id) return "|Hquest:" .. id .. ":18|h[X]|h" end }
    ok(linkOf(QL, 155, "Name", 18) == "[[18] Name (155)]",
       "Classic builds plain text even when GetQuestLink answers a real link")
    ok(calls == 0, "Classic does not CALL GetQuestLink at all")
end

print("== the plain-text form")
do
    local QL = build{ retail = false }
    ok(linkOf(QL, 155, "Name", 18) == "[[18] Name (155)]", "with a level")
    ok(linkOf(QL, 155, "Name", nil) == "[Name (155)]",     "with no level")
    ok(linkOf(QL, 155, "Name", 0)   == "[Name (155)]",     "level 0 is not a level")
    ok(linkOf(QL, 155, "Name")      == "[Name (155)]",     "a missing level argument")
    ok(linkOf(QL, 155, nil, 18)     == nil,                "no title shares nothing")
    ok(linkOf(QL, 155, "", 18)      == nil,                "an empty title shares nothing")
    ok(linkOf(QL, nil, "Name", 18)  == nil,                "no quest id shares nothing")
    ok(linkOf(QL, 0, "Name", 18)    == nil,                "quest id 0 shares nothing")
    ok(linkOf(QL, "155", "Name", 18) == nil,               "a string quest id shares nothing")
end

-- --------------------------------------------------------------------- UI/Row.lua slice

-- Row.lua cannot be loaded whole without a frame stub, so the click handler is sliced out by
-- TEXT ANCHORS rather than line numbers, which drift. If an anchor below stops matching the
-- file, fix the anchor here rather than deleting the test.
local src = readFile("UI/Row.lua")

local FROM_ANCHOR = "local function chatLinkClick(row)"
local TO_ANCHOR   = "local function onMouseUp(row, button)"
local from = src:find(FROM_ANCHOR, 1, true)
local to   = src:find(TO_ANCHOR, 1, true)
assert(from, "anchor not found in UI/Row.lua: " .. FROM_ANCHOR)
assert(to,   "anchor not found in UI/Row.lua: " .. TO_ANCHOR)
assert(to > from, "anchors are out of order in UI/Row.lua")

local slice = src:sub(from, to - 1) .. "\nreturn chatLinkClick\n"

local inserted, linkAsked, regAsked
local envNS
local env = setmetatable({ ns = setmetatable({}, { __index = function(_, k) return envNS[k] end }) },
                         { __index = _G })
local chatLinkClick = (function()
    local chunk = assert(loadstring(slice, "@UI/Row.lua slice"))
    setfenv(chunk, env)
    return chunk()
end)()
assert(type(chatLinkClick) == "function", "the UI/Row.lua slice defined nothing")

-- A row is only ever read here, so a bare table is the whole stub: the slice reads two
-- fields off the row and three off the entry it carries. Anything it reaches that is NOT stubbed raises, which is the point.
local function click(opts)
    opts = opts or {}
    inserted, linkAsked, regAsked = nil, 0, nil

    -- Explicit ifs, not "a and nil or b", which can never yield nil - the exact trap that made
    -- the first cut of these two cases pass against a build that had no guard at all.
    if opts.noModifierApi then
        _G.IsModifiedClick = nil
    else
        _G.IsModifiedClick = function(kind) return opts.modifier == kind end
    end
    if opts.noActiveWindowApi then
        _G.ChatEdit_GetActiveWindow = nil
    else
        _G.ChatEdit_GetActiveWindow = function() return opts.chatOpen and {} or nil end
    end
    if opts.noInsertApi then
        _G.ChatEdit_InsertLink = nil
    else
        _G.ChatEdit_InsertLink = function(text) inserted = text return opts.insertRefuses ~= true end
    end

    local mods = {
        Registry = { Get = function(_, id)
            -- Recorded, not just matched. Answering only for the configured id means a
            -- build that asked for a HARDCODED provider satisfies every case here while
            -- silently losing the link on campaign and world quest rows.
            regAsked = id
            if id ~= opts.providerID then return nil end
            return { idSpace = opts.idSpace }
        end },
        QuestLink = { For = function(_, id, title, level)
            linkAsked = linkAsked + 1
            if opts.linkText == false then return nil end
            return (opts.linkText or "[%s|%s|%s]"):format(tostring(id), tostring(title), tostring(level))
        end },
    }
    envNS = { GetModule = function(_, n) return mods[n] end }

    local row = {
        _providerID = opts.providerID,
        _entry = { id = opts.id or 155, title = opts.title or "Name", level = opts.level or 18 },
    }
    -- pcall'd for the same reason as linkOf above: a raising click must fail a case, not kill
    -- the file. The string is returned so it can never compare equal to true or to false.
    local okCall, res = pcall(chatLinkClick, row)
    if not okCall then return "<raised: " .. tostring(res) .. ">" end
    return res
end

local BASE = { modifier = "CHATLINK", chatOpen = true, providerID = "quests", idSpace = "quest" }

-- pairs skips a nil value, so a case that wants to CLEAR one of the base fields has to say so
-- with a sentinel. Without this "modifier = nil" reads as "no override" and the case silently
-- tests the base again, which is an assertion that cannot fail.
local NONE = setmetatable({}, { __tostring = function() return "NONE" end })
local function with(extra)
    local t = {}
    for k, v in pairs(BASE) do t[k] = v end
    for k, v in pairs(extra or {}) do
        -- An explicit if, because "(v ~= NONE) and v or nil" turns a legitimate FALSE override
        -- into nil. That is the third time this file has been bitten by that idiom.
        if v == NONE then t[k] = nil else t[k] = v end
    end
    return t
end

print("== the click links when everything lines up")
do
    ok(click(BASE) == true, "a shift-click with chat open links")
    ok(inserted == "[155|Name|18]", "the resolved text is what reaches the edit box")
    ok(linkAsked == 1, "the link is resolved exactly once")
end

print("== the click refuses, and refuses by RETURNING FALSE")
do
    -- Every one of these has to answer false rather than true. Answering true swallows the
    -- row's ordinary left-click, which is the class of bug this whole change exists to remove.
    ok(click(with{ modifier = "QUESTWATCHTOGGLE" }) == false, "a different modifier does not link")
    ok(linkAsked == 0, "a different modifier never even resolves a link")

    ok(click(with{ modifier = NONE }) == false, "an unmodified click does not link")

    ok(click(with{ chatOpen = false }) == false, "no chat box open does not link")
    ok(linkAsked == 0, "with no chat box open the link is never resolved")
    ok(inserted == nil, "with no chat box open nothing is inserted")

    ok(click(with{ idSpace = "achievement" }) == false, "a non-quest provider does not link")
    ok(linkAsked == 0, "a non-quest provider never resolves a link")

    ok(click(with{ providerID = "quests", idSpace = NONE }) == false,
       "a provider with no idSpace does not link")

    ok(click(with{ providerID = NONE }) == false, "a row with no provider id does not link")

    -- The ROW's own provider, not a fixed one. Every case above configures the stub with the
    -- id it expects, so a build that looked up a hardcoded "quests" satisfied all of them
    -- while losing the link on campaign and world quest rows - the two the idSpace test is
    -- there to cover in the first place.
    ok(click(with{ providerID = "worldquests" }) == true, "a world quest row links")
    ok(regAsked == "worldquests", "the registry is asked for the row's own provider id")

    ok(click(with{ linkText = false }) == false, "a quest with no shareable link does not link")
    ok(inserted == nil, "a quest with no shareable link inserts nothing")

    ok(click(with{ insertRefuses = true }) == false, "an edit box that refuses reports false")

    ok(click(with{ noModifierApi = true }) == false, "no IsModifiedClick at all does not link")
    ok(click(with{ noInsertApi = true }) == false, "no ChatEdit_InsertLink at all does not link")
    ok(click(with{ noActiveWindowApi = true }) == false,
       "no ChatEdit_GetActiveWindow at all does not link")
end

print("== the entry's own fields are what get shared")
do
    click(with{ id = 8744, title = "A Carefully Wrapped Present", level = 1 })
    ok(inserted == "[8744|A Carefully Wrapped Present|1]",
       "id, title and level are read off the entry rather than invented")
end

print("== the link branch's place in onMouseUp")
do
    -- Out of scope for the slice, which starts AT chatLinkClick - so a grep instead. The link
    -- has to be asked BEFORE split-click and before the row menu, or a split-click row opens
    -- the quest log while the player is trying to link it and a right-click opens the menu.
    -- Deliberately not gated on a button: the hide gesture this replaced took any button, and
    -- the README and the changelog both still say "shift-click" with no button named.
    local body = src:match("local function onMouseUp.-\nend")
    ok(body ~= nil, "onMouseUp is still findable in UI/Row.lua")
    body = body or ""
    local link  = body:find("chatLinkClick(row)", 1, true)
    local split = body:find("splitClickWanted(row)", 1, true)
    local menu  = body:find("RowMenu", 1, true)
    ok(link ~= nil, "onMouseUp still asks chatLinkClick")
    ok(link and split and link < split, "the link is asked before split-click")
    ok(link and menu and link < menu, "and before the row menu")
    ok(not body:find('if button == "LeftButton" and chatLinkClick', 1, true),
       "the link is not gated on a button, so shift+right-click links as it always did")
end

print("== the removed gesture is gone from the shipped source")
do
    -- A grep rather than a behavior test, and deliberately so: the defect was that shift-click
    -- reached SetHidden at all, and the only way to assert on something deleted is to look.
    -- Anchored on the CALL, never the bare name: a comment may legitimately name the gesture
    -- this replaced, and UI/Sections.lua has a live Sections:IsHidden for section visibility
    -- that a bare grep would one day mistake for this one.
    ok(not src:find("Filter:SetHidden", 1, true), "UI/Row.lua no longer calls Filter:SetHidden")
    ok(not src:find('IsModifiedClick("QUESTWATCHTOGGLE")', 1, true),
       "UI/Row.lua no longer reads QUESTWATCHTOGGLE")
    local filter = readFile("Data/Filter.lua")
    ok(not filter:find("Filter:IsHidden", 1, true), "Data/Filter.lua no longer carries IsHidden")
    ok(not filter:find("Filter:ClearHidden", 1, true),
       "Data/Filter.lua no longer carries ClearHidden")
    -- The WRITER, and the one the other greps did not cover. IsHidden and ClearHidden only
    -- read and reset. SetHidden is what actually took a quest off the tracker, so it is the
    -- one whose return would reintroduce the defect rather than the machinery around it.
    ok(not filter:find("Filter:SetHidden", 1, true), "Data/Filter.lua no longer carries SetHidden")
end

print(("test_quest_link: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
