local _, ns = ...

local Sort = ns:RegisterModule("Sort", {})

-- Every comparator reads only normalized Entry fields, so a new provider is sortable
-- the moment it exists - no comparator ever learns about a content type.
local function byTitle(a, b)
    local ta, tb = a.title or "", b.title or ""
    if ta ~= tb then return ta < tb end
    return tostring(a.id) < tostring(b.id)
end

local function byZone(a, b)
    local za, zb = a.zone or "~", b.zone or "~"
    if za ~= zb then return za < zb end
    return byTitle(a, b)
end

local function byStatus(a, b)
    local ca = (a.state == "complete")
    local cb = (b.state == "complete")
    if ca ~= cb then return ca end
    return byTitle(a, b)
end

-- Ranked on the tags rather than on entry.frequency, which the two flavors number
-- differently: Classic's flat quest log calls daily 2 and weekly 3 where retail's enum
-- calls them 1 and 2, so a raw descending compare agreed only by accident and retail's
-- fourth member sorted above everything. Only the quest providers tag any of these, so
-- every other group ranks 0 and drops through to byTitle.
local function typeRank(e)
    local t = e.tags
    if not t then return 0 end
    if t.weekly    then return 3 end
    if t.scheduled then return 2 end
    if t.daily     then return 1 end
    return 0
end

local function byType(a, b)
    local ra, rb = typeRank(a), typeRank(b)
    if ra ~= rb then return ra > rb end
    return byTitle(a, b)
end

local function byLevel(a, b)
    local la, lb = a.level or 0, b.level or 0
    if la ~= lb then return la < lb end
    return byTitle(a, b)
end

local function byRecent(a, b)
    local fa, fb = a.addedAt or 0, b.addedAt or 0
    if fa ~= fb then return fa > fb end
    return byTitle(a, b)
end

local INF = math.huge
local distances

-- Pushed by Data/Distance.lua rather than threaded through For, because the map is harvested
-- on a ticker independent of any sort call. ManualOrder's is read fresh per build instead, so
-- Feed passes that one as an argument.
function Sort:SetDistances(map)
    distances = map
end

local function byDistance(a, b)
    local da = (distances and distances[a.id]) or INF
    local db = (distances and distances[b.id]) or INF
    if da ~= db then return da < db end
    local za, zb = a.zone or "~", b.zone or "~"
    if za ~= zb then return za < zb end
    return byTitle(a, b)
end

local UNRANKED = 99999
local activeOrder

local function byManual(a, b)
    local ra = (activeOrder and activeOrder[a.id]) or UNRANKED
    local rb = (activeOrder and activeOrder[b.id]) or UNRANKED
    if ra ~= rb then return ra < rb end
    -- Only quest rows are draggable, so every entry in the other groups shares the
    -- unranked fallback. Without this fall-through table.sort sees them all as equal and
    -- leaves their order unspecified, which reshuffles those sections on every repaint.
    return byTitle(a, b)
end

local MODES = {
    zone     = byZone,
    title    = byTitle,
    status   = byStatus,
    type     = byType,
    level    = byLevel,
    recent   = byRecent,
    manual   = byManual,
    distance = byDistance,
}

function Sort:For(mode, orderMap)
    if mode == "manual" then
        activeOrder = orderMap
        return byManual
    end
    activeOrder = nil
    return MODES[mode or "zone"] or byZone
end

function Sort:Modes()
    return MODES
end
