-- Unit tests for the scenario panel's card, run against the SHIPPED source rather than a copy.
-- Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_scenario_card.lua
--
-- Two files are loaded here, because each half of the feature is harmless alone:
--
--   1. UI/Card.lua's ScenarioState, which must refuse whenever the ROW cards are off. A
--      scenario card on an otherwise plain tracker is the one look nobody asked for.
--   2. UI/Tracker.lua's _RenderScenario, which pays for the card twice - once as a top offset
--      every child anchors from, and once as height APPLIED to the container. One without the
--      other draws the panel over its own border or leaves a gap under it.
--
-- The rest of what earns this file:
--
--   3. The CONTENT gate. An idle container is one pixel tall, so a card drawn off the OPTION
--      alone is a bare padded strip across the top of the tracker all day.
--   4. The off switch being byte-identical: with the card off every offset must collapse back
--      to the numbers that shipped before it existed.
--   5. The height the container ACTUALLY takes, not just the one _RenderScenario returns, and
--      the nil group - Feed creates byGroup entries lazily, so there is no scenarios entry at
--      all until the provider first emits, which is every render for most players.
--
-- UI/Tracker.lua cannot be loaded whole without a frame stub, so _RenderScenario is sliced out
-- by TEXT ANCHOR rather than by line number, which drifts. If an anchor stops matching, fix the
-- anchor here rather than deleting the test.

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

local function newTexture()
    local t = { points = {}, shown = false, height = nil, color = nil }
    function t:ClearAllPoints() self.points = {} end
    function t:SetPoint(p, _, rel, x, y) self.points[p] = { rel = rel, x = x, y = y } end
    function t:SetHeight(h) self.height = h end
    function t:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
    function t:Show() self.shown = true end
    function t:Hide() self.shown = false end
    return t
end

local function newFrame()
    local f = { textureCount = 0, _height = 1 }
    function f:CreateTexture() self.textureCount = self.textureCount + 1 return newTexture() end
    function f:GetHeight() return self._height end
    function f:SetHeight(h) self._height = h end
    return f
end

-- ------------------------------------------------------------------------ UI/Card.lua, whole

local mods = {}
local ns = {}
function ns:RegisterModule(n, t) mods[n] = t return t end
function ns:GetModule(n) return mods[n] end

local trackerCfg = {}
mods.DB = { Tracker = function() return trackerCfg end }

local cardChunk = assert(loadstring(readFile("UI/Card.lua"), "@UI/Card.lua"))
cardChunk("EQObjectiveTracker", ns)
local Card = mods.Card
assert(Card, "UI/Card.lua did not register a Card module")

-- ------------------------------------------------------ UI/Tracker.lua's _RenderScenario slice

local src = readFile("UI/Tracker.lua")
local FROM_ANCHOR = "function Tracker:_RenderScenario(group, cfg)"
local TO_ANCHOR   = "-- A group Feed has never created has no byGroup entry"
local from = src:find(FROM_ANCHOR, 1, true)
local to   = src:find(TO_ANCHOR, 1, true)
assert(from, "anchor not found in UI/Tracker.lua: " .. FROM_ANCHOR)
assert(to,   "anchor not found in UI/Tracker.lua: " .. TO_ANCHOR)
assert(to > from, "anchors are out of order in UI/Tracker.lua")

local Tracker = {}
local scen    = newFrame()
Tracker.frame = { scenarioContainer = scen }

-- What the slice handed its two renderers, so the offsets are read back rather than inferred
local seen = {}
local widgetH, scenH, banner = 0, 0, nil

mods.WidgetBlock = {
    Render = function(_, _, _, top) seen.widgetTop = top return widgetH end,
}
mods.Scenario = {
    Render = function(_, _, _, info, entry, topOffset)
        seen.scenarioTop, seen.entry = topOffset, entry
        return info and scenH or 1
    end,
}
mods.Registry = {
    Get = function() return { GetBanner = function() return banner end } end,
}

local locked = false
local env = setmetatable({
    Tracker         = Tracker,
    ns              = ns,
    CONTAINER_GROUP = "scenarios",
    secureLocked    = function() return locked end,
}, { __index = _G })

local chunk = assert(loadstring(src:sub(from, to - 1), "@UI/Tracker.lua slice"))
setfenv(chunk, env)
chunk()
ok(type(Tracker._RenderScenario) == "function", "the slice defines _RenderScenario")

local ACTIVE = { visibleCount = 1, entries = { { lines = {} } } }
local IDLE   = { visibleCount = 0, entries = {} }

local function render(cfg, group)
    seen = {}
    return Tracker:_RenderScenario(group, cfg)
end

-- ------------------------------------------------------------------------------ ScenarioState

local CARD = { blockLayout = "card", cardPadding = 6, cardBorderSize = 1 }
local function cfgWith(t)
    local c = {}
    for k, v in pairs(CARD) do c[k] = v end
    for k, v in pairs(t or {}) do c[k] = v end
    return c
end

do
    local on, pad, border = Card:ScenarioState({ blockLayout = "classic", scenarioCard = true })
    ok(on == false, "ScenarioState refuses while Row Layout is Plain, even switched on")
    ok(pad == 0 and border == 0, "a refused ScenarioState reports no padding and no border")

    on, pad, border = Card:ScenarioState(cfgWith({}))
    ok(on == true, "ScenarioState is ON when the key is ABSENT - nil, true and absent all read "
        .. "as on, which is what lets AceDB strip the default out of a saved profile")
    ok(pad == 6 and border == 1, "ScenarioState passes the row cards' padding and border through")

    ok(Card:ScenarioState(cfgWith({ scenarioCard = false })) == false,
       "ScenarioState refuses when the option is explicitly off")
    ok(Card:ScenarioState(cfgWith({ scenarioCard = true })) == true,
       "ScenarioState accepts when the option is explicitly on")

    on, pad, border = Card:ScenarioState(cfgWith({ cardPadding = 12, cardBorderSize = 3 }))
    ok(on and pad == 12 and border == 3, "ScenarioState follows the row cards' own two sliders")

    -- Defensive only: AceDB merges DB.defaults into every profile, so no saved profile lacks these
    on, pad, border = Card:ScenarioState({ blockLayout = "card" })
    ok(on and pad == 6 and border == 1, "an unset padding and border fall back to 6 and 1")
end

-- --------------------------------------------------------------------- the card OFF, unchanged

do
    local plain = { blockLayout = "classic" }
    widgetH, scenH, banner = 0, 40, { stage = 1 }
    local h = render(plain, ACTIVE)
    ok(seen.widgetTop == 0, "card off: the tracker widget set still starts at the container top")
    ok(seen.scenarioTop == 0, "card off: the scenario block still starts at the container top")
    ok(h == 40, "card off: the height is the scenario block alone")

    widgetH = 25
    h = render(plain, ACTIVE)
    ok(seen.scenarioTop == 25, "card off: the scenario block still starts under the widget block")
    ok(h == 65, "card off: the height is the widget block plus the scenario block")

    banner = nil
    h = render(plain, IDLE)
    ok(h == 26, "card off: an idle container is the widget block plus one pixel")

    widgetH = 0
    h = render(plain, IDLE)
    ok(h == 1, "card off: a container with nothing in it is one pixel tall")
    ok(scen.cardBorder == nil or scen.cardBorder.shown == false, "card off: no card is drawn")
end

-- --------------------------------------------------------------------------- the card ON

do
    local cfg = cfgWith({})
    widgetH, scenH, banner = 0, 40, { stage = 1 }
    local h = render(cfg, ACTIVE)
    ok(seen.scenarioTop == 6, "card on: the scenario block starts below the card's top padding")
    ok(h == 52, "card on: the height carries the padding at BOTH ends, not just the top")
    ok(scen:GetHeight() == 52, "card on: and the container is really RESIZED to it - every row "
        .. "below the panel hangs off that height, so returning it is not enough")
    ok(seen.entry == ACTIVE.entries[1], "card on: the scenario entry is handed on, which is "
        .. "where every criterion line comes from")
    ok(scen.cardBorder.shown and scen.cardBg.shown, "card on: both card layers are drawn")

    widgetH = 25
    h = render(cfg, ACTIVE)
    ok(seen.widgetTop == 6, "card on: the widget block starts below the card's top padding too")
    ok(seen.scenarioTop == 31, "card on: the scenario block starts under BOTH the padding and "
        .. "the widget block")
    ok(h == 77, "card on: widget block, scenario block and the padding at both ends")

    -- Nil is what makes the card span the container rather than a number that has to be kept
    -- in step with it. The container's own SetHeight is the gated call, in the combat block.
    ok(scen.cardBorder.height == nil,
       "card on: the card TRACKS the container rather than being given a height of its own")
    ok(scen.cardBorder.points.BOTTOMLEFT ~= nil,
       "card on: the card is anchored to the container's bottom, which is what makes it track")
    ok(scen.cardBorder.points.TOPLEFT.x == 0 and scen.cardBorder.points.TOPLEFT.y == 0,
       "card on: the card is flush with the container, since the padding is already inside it")
end

-- ----------------------------------------------------------------------------- the CONTENT gate

do
    local cfg = cfgWith({})
    widgetH, scenH, banner = 0, 40, nil
    local h = render(cfg, IDLE)
    ok(h == 1, "no scenario and no widgets: the container stays one pixel, padding and all")
    ok(scen.cardBorder.shown == false and scen.cardBg.shown == false,
       "no scenario and no widgets: the card is CLEARED, not drawn around nothing")

    widgetH = 25
    h = render(cfg, IDLE)
    ok(scen.cardBorder.shown, "widgets with no scenario still earn a card")
    ok(h == 38, "widgets with no scenario: the widget block, one pixel, and the padding")

    -- The gate reads the banner, not the group: a group can be present with no facts behind it
    widgetH, banner = 0, nil
    render(cfg, ACTIVE)
    ok(scen.cardBorder.shown == false,
       "a scenario group whose provider returns no banner draws no card")
end

-- ------------------------------------------------------------------------- no group at all

-- Data/Feed.lua builds byGroup LAZILY and Build only wipes it, never removes, so there is no
-- scenarios entry until the provider has emitted once. For anyone who has not been in a
-- scenario this session that is EVERY render, and it is a different fixture from IDLE, which
-- models the rarer state after one has ended.
do
    local cfg = cfgWith({})
    widgetH, scenH, banner = 0, 40, { stage = 1 }
    local h = render(cfg, nil)
    ok(h == 1, "no group at all: one pixel, the same as a group with nothing in it")
    ok(scen:GetHeight() == 1, "no group at all: and the container is resized down to it")
    ok(scen.cardBorder.shown == false, "no group at all: no card")
    ok(seen.entry == nil, "no group at all: no entry is invented")
    ok(seen.scenarioTop == 6, "no group at all: the scenario renderer is still called, so a "
        .. "stale panel from a finished scenario is still cleared")

    -- No fixture separates visibleCount == 0 from an empty entries table, and none can:
    -- Feed:Build wipes entries every pass and only ever writes at the incremented count, so
    -- dropping that half of the guard is an EQUIVALENT mutation rather than a coverage hole.
end

-- -------------------------------------------------------------------- the option, end to end

do
    widgetH, scenH, banner = 0, 40, { stage = 1 }
    local off = render(cfgWith({ scenarioCard = false }), ACTIVE)
    ok(off == 40, "switched off, the height is byte-identical to Plain layout")
    ok(seen.scenarioTop == 0, "switched off, the scenario block is back at the container top")
    ok(scen.cardBorder.shown == false, "switched off, the card is cleared")

    local on = render(cfgWith({ scenarioCard = true }), ACTIVE)
    ok(on == 52 and scen.cardBorder.shown, "switched back on, the card returns without a reload")
end

-- ------------------------------------------------------------------ colors, border and combat

do
    local cfg = cfgWith({
        cardColor       = { r = 0.5, g = 0.25, b = 0.125, a = 0.5 },
        cardBorderColor = { r = 1,   g = 0,    b = 0,     a = 1 },
        cardBorderSize  = 3,
    })
    widgetH, scenH, banner = 0, 40, { stage = 1 }
    render(cfg, ACTIVE)
    ok(scen.cardBg.color[1] == 0.5 and scen.cardBg.color[4] == 0.5,
       "the scenario card uses the same fill color the quest cards do")
    ok(scen.cardBorder.color[1] == 1, "and the same border color")
    ok(scen.cardBg.points.TOPLEFT.x == 3,
       "the fill is inset by the border thickness, so a thick border is visible")

    -- A tint is a per-QUEST color and the scenario panel is not a quest, so it must not follow
    cfg.cardTintByType, cfg.cardTintDungeon = true, { r = 0, g = 0, b = 1, a = 1 }
    render(cfg, ACTIVE)
    ok(scen.cardBg.color[1] == 0.5, "the scenario card ignores the per-quest type tints")
end

do
    -- SetHeight is the protected call and the only thing combat may skip here: the card itself
    -- is textures, so it must still repaint or a mid-fight color change never lands
    local cfg = cfgWith({})
    widgetH, scenH, banner = 0, 40, { stage = 1 }
    render(cfg, ACTIVE)
    local before = scen:GetHeight()
    ok(before == 52, "the container really was resized before combat, or the check below "
        .. "compares two stale numbers and passes whatever happens")

    locked = true
    scenH = 90
    local h = render(cfg, ACTIVE)
    ok(h == 102, "in combat the height is still REPORTED, so the scroll area below is measured "
        .. "against the real block")
    ok(scen:GetHeight() == before, "in combat the container is not resized")
    ok(scen.cardBorder.shown, "in combat the card is still drawn")
    locked = false
end

-- ------------------------------------------------------------------ Card:State and its helpers

do
    ok(select(1, Card:State({ blockLayout = "classic" })) == false, "State is off for Plain")
    ok(select(1, Card:State({ blockLayout = "card" })) == true, "State is on for Card")

    ok(Card:Gap(2, false) == 2, "Gap leaves the spacing alone while cards are off")
    trackerCfg = { blockSpacing = 2 }
    -- The literal, never Card.MIN_GAP: reading the constant under test passes at any value,
    -- MIN_GAP = 2 included, which is the exact case its own comment exists to prevent
    ok(Card:Gap(2, true) == 4,
       "Gap floors at 4 with cards on, or adjacent borders touch and read as one card")
    trackerCfg = { blockSpacing = 9 }
    ok(Card:Gap(2, true) == 9, "Gap keeps a larger spacing the player chose")
    trackerCfg = {}

    local bg, border = Card:Colors({})
    ok(type(bg) == "table" and bg.a == 0.73, "Colors falls back to the shipped default fill")
    ok(type(border) == "table" and border.a == 0.45, "and to the shipped default border")

    local c = { cardTintCampaign = "campaign", cardTintLegendary = "legendary",
                cardTintDungeon = "dungeon", cardTintRaid = "raid" }
    ok(Card:TintFor(c, { tags = { campaign = true } }) == "campaign", "TintFor reads campaign")
    ok(Card:TintFor(c, { tags = { campaign = true, dungeon = true } }) == "dungeon",
       "an instance tag beats a storyline one")
    ok(Card:TintFor(c, { tags = { raid = true, legendary = true } }) == "raid",
       "raid beats legendary")
    ok(Card:TintFor(c, { tags = {} }) == nil, "an untagged entry takes the plain background")
    ok(Card:TintFor(nil, { tags = { raid = true } }) == nil, "TintFor needs a config")
end

do
    local f = newFrame()
    Card:Attach(f)
    local n = f.textureCount
    Card:Attach(f)
    ok(f.textureCount == n, "Attach is idempotent - a repaint must not leak textures")

    -- The fixed-height branch, which BOTH shipped callers pass nil for today. Kept covered
    -- because nothing else in the tree exercises it and it is one argument away.
    Card:Draw(f, 40, 4, 1, nil, nil)
    ok(f.cardBorder.height == 40, "a set height is used rather than tracking the frame")
    ok(f.cardBg.height == 38, "the fill loses the border thickness at both ends")
    Card:Draw(f, 1, 4, 1, nil, nil)
    ok(f.cardBg.shown == false and f.cardBorder.shown,
       "a card too short for its own border keeps the border and drops the fill")

    Card:Clear(f)
    ok(f.cardBorder.shown == false and f.cardBg.shown == false, "Clear hides both layers")
end

print(("test_scenario_card: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
