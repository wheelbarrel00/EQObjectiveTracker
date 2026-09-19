-- Unit tests for the row menu seam, run against the SHIPPED source rather than a copy. Run
-- from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_row_menu.lua
--
-- WHY THIS FILE EXISTS. Asked for by AIR on 2026-09-06, as a plan B for the group finder eye:
-- "One problem i can see with eye is clickable zone for it." His report closed the next day
-- against another addon's buttons sitting on top of the eye rather than the eye's size, but the
-- menu item was wanted on its own terms and shipped.
--
-- THE TRAP THIS FILE IS MOSTLY HERE FOR, and it is silent in both halves. Providers return
-- item IDs and never wording, and UI/RowMenu.lua turns an id into a label with
--
--     local label = it.label or LABELS[it.id]
--     if label then root:CreateButton(...) end
--
-- so an id with no LABELS entry is DROPPED with no error, no Lua warning and nothing on
-- screen. A provider and its labels are in different files and under different rules, so
-- nothing but an assertion couples them. The completeness case below walks every id either
-- provider can emit, in every state it can emit one, and demands a label for each.
--
-- THE OTHER TRAP IS THE REUSED TABLE. Each provider answers out of its own file-local menuOut
-- that the next call overwrites, cleared by a reverse wipe at the top of GetEntryMenu. That is the
-- shrink case this project has been bitten by in Data/Widgets.lua and UI/Row.lua already: a
-- longer previous answer leaving its tail behind a shorter one. Here it would leave Find Group
-- on a quest that cannot form a group, which is the one thing the entry.canGroup gate exists to
-- prevent.
--
-- Neither provider can be loaded whole without stubbing the quest log, the watch API, the entry
-- store and the group cache, so the menu functions are sliced out by TEXT ANCHORS rather than
-- line numbers, which drift. If an anchor stops matching it fails loudly naming the anchor: fix
-- the anchor here rather than deleting the test.
--
-- OUT OF SCOPE BY CONSTRUCTION, so a green run says nothing about any of it: the actual
-- Blizzard calls behind every other menu id, QuestGroups:Find and whether the group finder
-- opens, UI/RowMenu.lua's own popup construction, and API:MenuItemsFor's interleaving of
-- foreign items. Only the menu's SHAPE and its dispatch are measured here.

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

-- Counts rather than taking the first hit. sliceBetween in the sibling harnesses uses find,
-- which silently takes region one of two if an anchor ever appears twice. Each closure reads one
-- file, so what this guards is a duplicate WITHIN a file rather than across the two.
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

-- ------------------------------------------------------------------ the sliced menu sources

local sliceQ  = slicer("Data/Providers/Quests.lua")
local sliceWQ = slicer("Data/Providers/WorldQuests.lua")
local sliceRM = slicer("UI/RowMenu.lua")

local questSrc = sliceQ("local menuOut = {}", "function Quests:OnEntryGroupFinder")
local wqSrc    = sliceWQ("local menuOut = {}", "function WorldQuests:ProbeLines")
local labelSrc = sliceRM("local LABELS = {", "local DANGER")

-- ---------------------------------------------------------------------------- the stubs

-- What a dispatched id actually did, so a case can ask that rather than only what the menu
-- returned. Not every id reaches here: wowhead is handled by UI/RowMenu.lua itself.
local calls

local function resetCalls()
    calls = { groupFinder = {}, other = {}, notify = 0 }
end

local watched, focused, pinned = {}, {}, {}

local function makeEnv(providerName)
    local provider = {}
    -- The real OnEntryGroupFinder is a one-line QuestGroups:Find and lives outside both slices,
    -- so it is a spy here. What is under test is the DISPATCH: that findgroup reaches it, once,
    -- carrying something shaped like an entry - it reads entry.id, so a bare id would be nil.
    provider.OnEntryGroupFinder = function(_, entry)
        calls.groupFinder[#calls.groupFinder + 1] = entry
    end
    provider.OnEntryOpenLog = function(_, entry)
        calls.other[#calls.other + 1] = "openlog:" .. tostring(entry and entry.id)
    end
    provider._notifyDirty = function() calls.notify = calls.notify + 1 end

    local env
    env = {
        [providerName] = provider,
        ns = {
            Has = {
                SuperTrack = true, WorldQuests = true,
                WorldQuestWatchAdd = true, WorldQuestWatchAPI = true,
            },
            GetModule = function(_, name)
                if name == "Filter" then
                    return {
                        IsPinned  = function(_, e) return pinned[e.id] end,
                        SetPinned = function(_, e, on)
                            calls.other[#calls.other + 1] = "pin:" .. tostring(e.id) .. ":"
                                                            .. tostring(on)
                        end,
                    }
                end
                error("unexpected module: " .. tostring(name), 0)
            end,
        },
        Enum = { QuestWatchType = { Manual = 1 } },
        C_SuperTrack = {
            SetSuperTrackedQuestID = function(id)
                calls.other[#calls.other + 1] = "supertrack:" .. tostring(id)
            end,
        },
        C_QuestLog = {
            GetQuestWatchType     = function(id) return watched[id] and 1 or nil end,
            -- Two arguments, matching production. A one-argument stub drops the watch TYPE,
            -- and an automatic watch is the one the game silently evicts.
            AddWorldQuestWatch    = function(id, watchType)
                calls.other[#calls.other + 1] = "wqadd:" .. id .. ":" .. tostring(watchType)
            end,
            RemoveWorldQuestWatch = function(id) calls.other[#calls.other + 1] = "wqrm:" .. id end,
        },
        isWatched = function(id) return watched[id] end,
        isFocused = function(id) return focused[id] end,
        setWatched = function(id, on)
            calls.other[#calls.other + 1] = "watch:" .. tostring(id) .. ":" .. tostring(on)
        end,
        openQuestDetailsPopup = function(id)
            calls.other[#calls.other + 1] = "popout:" .. tostring(id)
        end,
        abandonQuest = function(id)
            calls.other[#calls.other + 1] = "abandon:" .. tostring(id)
            return nil
        end,
    }
    return setmetatable(env, { __index = _G }), provider
end

local function load(src, name, providerName)
    local chunk = assert(loadstring(src .. "\nreturn menuOut", name))
    local env, provider = makeEnv(providerName)
    setfenv(chunk, env)
    return provider, chunk()
end

local Quests,      questMenuOut = load(questSrc, "quests-menu-slice",  "Quests")
local WorldQuests, wqMenuOut    = load(wqSrc,    "wq-menu-slice",      "WorldQuests")

-- LABELS is a plain table of L[...] lookups. L answers the key itself, which is exactly what
-- the shipped metatable does for an untranslated phrase, so a missing entry reads as nil here
-- the same way it would in game.
local LABELS
do
    local chunk = assert(loadstring(labelSrc .. "\nreturn LABELS", "rowmenu-labels-slice"))
    setfenv(chunk, setmetatable(
        { L = setmetatable({}, { __index = function(_, k) return k end }) },
        { __index = _G }))
    LABELS = chunk()
end

-- ------------------------------------------------------------------------------- helpers

-- A raise has to FAIL a case, never kill the run: with no summary line the battery can only
-- report CRASHED, which names an abort rather than the assertion that failed to discriminate.
local function menuOf(provider, entry, why)
    local okCall, res = pcall(provider.GetEntryMenu, provider, entry)
    ok(okCall, (why or "GetEntryMenu") .. " does not raise"
       .. (okCall and "" or (" - " .. tostring(res))))
    if not okCall then return {} end
    -- COPIED, because the list is the provider's reused table and the very next call wipes it.
    -- A HOLE is checked while copying rather than left for find() and the harvest loop to
    -- index: a partial wipe is the shrink bug this file exists for, and indexing nil aborts
    -- the run rather than failing a case.
    local out = {}
    for i = 1, #res do
        if type(res[i]) ~= "table" then
            ok(false, (why or "GetEntryMenu") .. " left a hole at index " .. i)
            return {}
        end
        out[i] = res[i]
    end
    return out
end

local function select_(provider, entryID, itemID, why)
    resetCalls()
    local okCall, res = pcall(provider.OnEntryMenuSelect, provider, entryID, itemID)
    ok(okCall, (why or "OnEntryMenuSelect") .. " does not raise"
       .. (okCall and "" or (" - " .. tostring(res))))
    return okCall and res or nil
end

local function find(menu, id)
    for i = 1, #menu do
        if menu[i].id == id then return menu[i], i end
    end
    return nil
end

local function orderOf(menu, id)
    local item = find(menu, id)
    return item and item.order
end

resetCalls()

-- --------------------------------------------------------------------------------- cases

print("== Quests: the item appears only on a quest that can actually form a group")
do
    local yes = menuOf(Quests, { id = 101, title = "Groupable", canGroup = true })
    ok(find(yes, "findgroup") ~= nil, "canGroup true offers Find Group")

    local no = menuOf(Quests, { id = 102, title = "Solo", canGroup = false })
    ok(find(no, "findgroup") == nil, "canGroup false does not")

    -- An ABSENT field, not the unresolved state: CanCreate answers false while a lookup is
    -- outstanding, so a provider entry never carries nil. Kept because GetEntryMenu is a public
    -- seam that can be handed anything.
    local unresolved = menuOf(Quests, { id = 103, title = "Unresolved" })
    ok(find(unresolved, "findgroup") == nil, "and neither does canGroup nil")
end

print("== Quests: the reused menu table cannot leave Find Group on the next quest")
do
    -- The shrink case. menuOut is one file-local shared by every row, so the wipe at the top of
    -- GetEntryMenu is the ONLY thing stopping a groupable quest's item riding onto the next
    -- row, which is precisely what the gate exists to prevent.
    local big = menuOf(Quests, { id = 201, title = "Groupable", canGroup = true })
    local small = menuOf(Quests, { id = 202, title = "Solo", canGroup = false })
    ok(find(big, "findgroup") ~= nil, "the groupable row got the item")
    ok(find(small, "findgroup") == nil, "the row after it did not inherit it")
    ok(#small == #big - 1, "and the shorter menu is genuinely shorter: "
       .. #small .. " against " .. #big)
    ok(#questMenuOut == #small, "the live table shrank too rather than keeping a tail")
end

print("== Quests: Find Group sits between Pop Out and Wowhead, and leaves 35 alone")
do
    local menu = menuOf(Quests, { id = 301, title = "Groupable", canGroup = true })
    ok(orderOf(menu, "findgroup") == 55, "Find Group is order 55")
    ok(orderOf(menu, "popout") == 50 and orderOf(menu, "wowhead") == 60,
       "with Pop Out at 50 and Wowhead at 60 either side of it")

    -- EQ registers its Chain Guide "Get Directions" on 35 through Core/API.lua, and a
    -- collision is not an error - byOrder tie-breaks on the id, so the two would simply swap
    -- places depending on spelling. Keeping 35 free is what makes the order deterministic.
    local taken = {}
    for i = 1, #menu do
        local o = menu[i].order
        -- Asked before it is used as a key, or an item with no order indexes the table with
        -- nil and aborts the run instead of failing this case.
        ok(o ~= nil, "every item carries an order, at index " .. i)
        if o ~= nil then
            ok(taken[o] == nil, "no two menu items share an order, at " .. tostring(o))
            taken[o] = true
        end
    end
    ok(taken[35] == nil, "and 35 is still free for EQ's Chain Guide item")
end

print("== Quests: selecting it dispatches to the group finder, once, with an entry")
do
    select_(Quests, 401, "findgroup")
    ok(#calls.groupFinder == 1, "exactly one dispatch, not zero and not two: "
       .. #calls.groupFinder)
    local got = calls.groupFinder[1]
    -- OnEntryGroupFinder reads entry.id, so handing it the bare id would read nil and the
    -- group finder would silently open on nothing.
    ok(type(got) == "table", "it is handed a table, not the bare id")
    -- Indexed only AFTER the type test, never behind a bare `got and`. A bare id is a number,
    -- numbers are truthy, and indexing one ABORTS the run rather than failing it. The bare-id
    -- mutant reported CRASHED on this file's first battery run for exactly that reason.
    ok(type(got) == "table" and got.id == 401,
       "carrying the id it was selected for: "
       .. tostring(type(got) == "table" and got.id or got))
    ok(#calls.other == 0, "and nothing else on the menu fired")
end

print("== Quests: it is neither destructive nor a refusal")
do
    local menu = menuOf(Quests, { id = 501, title = "Groupable", canGroup = true })
    local item = find(menu, "findgroup")
    ok(item and not item.danger, "Find Group is not marked danger, which would draw it red")
    ok(item and item.kind == nil, "and it is an ordinary item rather than a title or divider")

    local refused = select_(Quests, 501, "findgroup")
    ok(refused == nil, "selecting it returns no refusal token")
end

print("== Quests: every other item still works, so the new branch stole nothing")
do
    -- The elseif chain is ordered, and a branch inserted in the wrong place would shadow the
    -- one after it. Each of these is the sibling either side of the new one.
    select_(Quests, 601, "popout")
    ok(calls.other[1] == "popout:601" and #calls.groupFinder == 0, "Pop Out still pops out")
    select_(Quests, 602, "abandon")
    ok(calls.other[1] == "abandon:602" and #calls.groupFinder == 0, "Abandon still abandons")
    select_(Quests, 603, "openlog")
    ok(calls.other[1] == "openlog:603" and #calls.groupFinder == 0, "Open Log still opens")
    select_(Quests, 604, "findgroup")
    ok(#calls.groupFinder == 1 and #calls.other == 0, "and Find Group reaches only itself")
end

print("== World Quests: the same gate, at its own order")
do
    local yes = menuOf(WorldQuests, { id = 701, title = "Elite WQ", canGroup = true })
    ok(find(yes, "findgroup") ~= nil, "canGroup true offers Find Group")
    ok(orderOf(yes, "findgroup") == 25, "at order 25")
    ok(orderOf(yes, "supertrack") == 20 and orderOf(yes, "wowhead") == 30,
       "between Super-track at 20 and Wowhead at 30, the same relative slot as the quest menu")

    local no = menuOf(WorldQuests, { id = 702, title = "Ordinary WQ", canGroup = false })
    ok(find(no, "findgroup") == nil, "and canGroup false does not")

    -- The same unresolved case the quest menu carries. Tested on one provider only, a
    -- presence test here survived every assertion in this file.
    local unresolved = menuOf(WorldQuests, { id = 703, title = "Unresolved WQ" })
    ok(find(unresolved, "findgroup") == nil, "and neither does an absent canGroup")
    ok(#wqMenuOut == #no, "the reused table shrank rather than keeping a tail")
end

print("== World Quests: selecting it dispatches the same way")
do
    select_(WorldQuests, 801, "findgroup")
    ok(#calls.groupFinder == 1, "exactly one dispatch: " .. #calls.groupFinder)
    local got = calls.groupFinder[1]
    ok(type(got) == "table" and got.id == 801, "carrying the id as an entry table")
    ok(#calls.other == 0, "and no watch or super-track call rode along with it")

    select_(WorldQuests, 802, "supertrack")
    ok(calls.other[1] == "supertrack:802" and #calls.groupFinder == 0,
       "while Super-track, the branch above it, is untouched")

    -- The branches either side of the new one, and the watch TYPE with them: an automatic
    -- watch is evicted by the game, so dropping the argument loses the row after a reload.
    select_(WorldQuests, 803, "track")
    ok(calls.other[1] == "wqadd:803:1", "Track adds a manual watch: " .. tostring(calls.other[1]))
    select_(WorldQuests, 804, "untrack")
    ok(calls.other[1] == "wqrm:804", "and Untrack removes it: " .. tostring(calls.other[1]))
end

print("== a toggling id answers the state it is in, not merely appears somewhere")
do
    -- The completeness case below unions both states, so pin and unpin both reach its set
    -- whichever way the ternary points. Only this block can see an inverted gate, and an
    -- inverted one puts the wrong verb on every row of the menu in game.
    local function idAt(provider, entry, present, absent, why)
        local menu = menuOf(provider, entry)
        ok(find(menu, present) ~= nil, why .. " offers " .. present)
        ok(find(menu, absent) == nil, "and not " .. absent)
    end

    pinned[910], watched[910], focused[910] = nil, nil, nil
    idAt(Quests, { id = 910, title = "Q" }, "pin",   "unpin",   "an unpinned quest")
    idAt(Quests, { id = 910, title = "Q" }, "track", "untrack", "an untracked quest")
    idAt(Quests, { id = 910, title = "Q" }, "focus", "unfocus", "an unfocused quest")

    pinned[910], watched[910], focused[910] = true, true, true
    idAt(Quests, { id = 910, title = "Q" }, "unpin",   "pin",   "a pinned quest")
    idAt(Quests, { id = 910, title = "Q" }, "untrack", "track", "a tracked quest")
    idAt(Quests, { id = 910, title = "Q" }, "unfocus", "focus", "a focused quest")
    pinned[910], watched[910], focused[910] = nil, nil, nil

    watched[911] = nil
    idAt(WorldQuests, { id = 911, title = "WQ" }, "track", "untrack", "an untracked world quest")
    watched[911] = true
    idAt(WorldQuests, { id = 911, title = "WQ" }, "untrack", "track", "a tracked world quest")
    watched[911] = nil
end

print("== the dispatch acts on the id it was given, not its opposite")
do
    -- The menu can name the right id and the dispatch still do the other thing: these are
    -- separate elseif branches in a separate function from the gates above.
    select_(Quests, 920, "track")
    ok(calls.other[1] == "watch:920:true", "Track tracks: " .. tostring(calls.other[1]))
    select_(Quests, 921, "untrack")
    ok(calls.other[1] == "watch:921:false", "Untrack untracks: " .. tostring(calls.other[1]))
    select_(Quests, 922, "pin")
    ok(calls.other[1] == "pin:922:true", "Pin pins: " .. tostring(calls.other[1]))
    select_(Quests, 923, "unpin")
    ok(calls.other[1] == "pin:923:false", "Unpin unpins: " .. tostring(calls.other[1]))

    -- calls.notify was recorded by the stub and read by nothing. A dispatch that changes state
    -- without asking for a repaint leaves the row drawing the old verb until an unrelated
    -- quest event happens by.
    select_(Quests, 924, "track")
    ok(calls.notify == 1, "a quest dispatch asks for one repaint: " .. calls.notify)
    select_(WorldQuests, 925, "supertrack")
    ok(calls.notify == 1, "and so does a world quest dispatch: " .. calls.notify)
end

print("== every id either provider can emit has a label, or it is dropped in silence")
do
    -- UI/RowMenu.lua does `local label = it.label or LABELS[it.id]` and then `if label then`,
    -- so an id with no entry here draws nothing at all and reports nothing. Providers and
    -- labels live in different files under different rules and only this case couples them.
    local seen, smuggled = {}, {}
    local function harvest(provider, entry)
        local menu = menuOf(provider, entry)
        for i = 1, #menu do
            local it = menu[i]
            if it.id then
                seen[it.id] = true
                -- it.label WINS over LABELS in UI/RowMenu.lua, so a provider setting one
                -- ships English no locale gate can see. Data/ returns ids, never wording.
                if it.label ~= nil then smuggled[it.id] = true end
            end
        end
    end

    -- Both sides of every state that swaps one id for another, or the untaken half of each
    -- pair is never harvested and its label goes unchecked.
    for _, canGroup in ipairs({ true, false }) do
        for _, flag in ipairs({ true, false }) do
            watched[900], focused[900], pinned[900] = flag, flag, flag
            harvest(Quests, { id = 900, title = "Q", canGroup = canGroup })
            watched[901] = flag
            harvest(WorldQuests, { id = 901, title = "WQ", canGroup = canGroup })
        end
    end
    watched[900], focused[900], pinned[900], watched[901] = nil, nil, nil, nil

    local n = 0
    for id in pairs(seen) do
        n = n + 1
        -- Non-EMPTY, not merely non-nil: "" is truthy in Lua, so `if label then` draws a
        -- blank clickable button rather than skipping it.
        local label = LABELS[id]
        ok(type(label) == "string" and label ~= "",
           "UI/RowMenu.lua LABELS carries a non-empty label for id: " .. id)
        ok(not smuggled[id], "and the provider supplies no wording of its own for id: " .. id)
    end
    -- Or an empty harvest would pass this block without asserting anything at all.
    ok(n >= 12, "and the harvest actually covered both providers in both states: " .. n)
    ok(seen.findgroup == true, "including the new one")
    ok(LABELS.findgroup == "Find Group",
       "which reuses the eye's own already-translated phrase rather than adding one: "
       .. tostring(LABELS.findgroup))
end

print("== Classic is excluded by the gate rather than by a flavor test")
do
    -- QuestsClassic never CALLS QuestGroups, so entry.canGroup is never set and the gate
    -- excludes it with no branch and no TOC line. Data/QuestGroups.lua IS listed in every TOC
    -- and loads inert on Classic. Asserted against the source rather than left to memory.
    local classic = readFile("Data/Providers/QuestsClassic.lua")
    ok(not classic:find("findgroup", 1, true),
       "Data/Providers/QuestsClassic.lua names no findgroup item")
    ok(not classic:find("canGroup", 1, true),
       "and sets no canGroup, so the gate can never open there")
end

print("== Search on Wowhead opens the site for the game the client runs")
do
    local wowheadSrc = sliceRM("local WOWHEAD_GAME = ", "-- Dispatched against the entry ID")
    -- Each build stubs the client fresh. The trailing strings after the interface number are
    -- what a real GetBuildInfo returns, and they are what turns an unparenthesized select into
    -- tonumber(16001, "Release x64"), which raises.
    local function urlFor(questLog, toc, level, locale)
        local url
        local chunk = assert(loadstring(wowheadSrc .. "\nreturn wowhead", "rowmenu-wowhead-slice"))
        setfenv(chunk, setmetatable({
            ns = { Has = { QuestLog = questLog }, ShowURL = function(_, u) url = u end },
            GetBuildInfo = function() return "x", "1", "date", toc, "Release x64", "Release" end,
            GetExpansionLevel = function() return level end,
            GetLocale = function() return locale or "enUS" end,
        }, { __index = _G }))
        local okCall, err = pcall(chunk(), 783)
        ok(okCall, "wowhead() does not raise: " .. tostring(err))
        return tostring(url)
    end

    local W = "https://www.wowhead.com/"
    ok(urlFor(true, 120100, 11) == W .. "quest=783",
       "retail opens the retail site: " .. urlFor(true, 120100, 11))
    ok(urlFor(true, 16001, 0) == W .. "forever/quest=783",
       "WoW Forever opens the Forever site: " .. urlFor(true, 16001, 0))
    ok(urlFor(true, 16001, 0, "deDE") == W .. "forever/de/quest=783",
       "in the client's language, which Wowhead serves under the Forever path: "
       .. urlFor(true, 16001, 0, "deDE"))
    ok(urlFor(true, 17000, 0) == W .. "quest=783" and urlFor(true, 15999, 0) == W .. "quest=783",
       "and only the 16xxx range counts as Forever")
    ok(urlFor(false, 11509, 0) == W .. "classic/quest=783",
       "Classic Era still opens the Classic site: " .. urlFor(false, 11509, 0))
    ok(urlFor(false, 20506, 1) == W .. "tbc/quest=783",
       "and TBC the TBC site: " .. urlFor(false, 20506, 1))
end

print(("test_row_menu: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
