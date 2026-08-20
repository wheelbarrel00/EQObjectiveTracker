local _, ns = ...

local RowMenu = ns:RegisterModule("RowMenu", {})
local L       = ns.L

-- Same seam as LABELS, for the other direction: a provider that refuses an action returns a
-- reason token and this is where it becomes something the player can read.
local REFUSALS = {
    combat      = L["You cannot abandon a quest while in combat."],
    unavailable = L["This game version cannot abandon quests from the tracker."],
    stale       = L["That quest is no longer in your quest log."],
}

-- Providers return item IDs, never translatable wording, so Data/ stays free of display text
-- and the manifest has one place to harvest. The title row carries the quest name as data, and
-- an API-registered item supplies its own already-translated label.
local LABELS = {
    pin        = L["Pin to tracker"],
    unpin      = L["Unpin from tracker"],
    track      = L["Track Quest"],
    untrack    = L["Untrack Quest"],
    focus      = L["Focus"],
    unfocus    = L["Unfocus"],
    supertrack = L["Super-track (follow arrow)"],
    openlog    = L["Open in Map & Quest Log"],
    popout     = L["Pop Out Quest Details"],
    wowhead    = L["Search on Wowhead"],
    abandon    = L["Abandon Quest"],
}

local DANGER = "|cffff5050%s|r"

local scratch = {}

local function byOrder(a, b)
    if a.order == b.order then return (a.id or "") < (b.id or "") end
    return a.order < b.order
end

-- Wowhead serves a separate site per game version, and a Classic quest id is a different quest
-- on the retail site, or a 404. Retail is read as a capability rather than a flavor test, and
-- GetExpansionLevel then names which Classic site - nothing in the 60+ probed values separates
-- Era from TBC. Only the two shipped Classic flavors are listed, so a new TOC adds its row here.
local WOWHEAD_GAME = { [0] = "classic/", [1] = "tbc/" }

-- Wowhead's own locale paths, which are not the client's locale codes. An unlisted client
-- language falls through to the English site rather than to a URL that does not resolve.
local WOWHEAD_LANG = {
    frFR = "fr/", deDE = "de/", esES = "es/", esMX = "es/", itIT = "it/",
    ptBR = "pt/", ptPT = "pt/", ruRU = "ru/", koKR = "ko/", zhCN = "cn/",
}

-- Handled here rather than dispatched: opening a link needs the ID and nothing else, so
-- routing it through a provider would be Data/ reaching into UI/ for no gain.
local function wowhead(entryID)
    local game = ""
    if not ns.Has.QuestLog then
        local level = type(GetExpansionLevel) == "function" and GetExpansionLevel() or 0
        game = WOWHEAD_GAME[level] or "classic/"
    end
    local lang = WOWHEAD_LANG[GetLocale()] or ""
    ns:ShowURL("https://www.wowhead.com/" .. game .. lang .. "quest=" .. tostring(entryID))
end

-- Dispatched against the entry ID rather than the entry table: the menu outlives the render
-- that opened it, and entries are rebuilt on every quest event.
local function run(providerID, entryID, item)
    if item.external then
        item.external.onClick(providerID, entryID)
    elseif item.id == "wowhead" then
        wowhead(entryID)
    else
        local provider = ns:GetModule("Registry"):Get(providerID)
        if provider and provider.OnEntryMenuSelect then
            local refused = provider:OnEntryMenuSelect(entryID, item.id)
            if refused and REFUSALS[refused] then ns:Print(REFUSALS[refused]) end
        end
    end
    local Tracker = ns:GetModule("Tracker")
    if Tracker then Tracker:Refresh() end
end

function RowMenu:Show(row)
    -- No OnEnable, so ns:IsModuleDisabled never covers this. Honored directly, as DragDrop and
    -- ItemButtons do, or /eqot disable all leaves the menu live - and MenuUtil, StaticPopup and
    -- the quest log popout are the newest taint vectors a bisection would be trying to rule out.
    if ns:SafeMode() then return false end
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return false end

    local entry, providerID = row._entry, row._providerID
    if not (entry and providerID) then return false end

    local provider = ns:GetModule("Registry"):Get(providerID)
    if not (provider and provider.GetEntryMenu) then return false end

    local items = provider:GetEntryMenu(entry)
    if not items then return false end

    local entryID = entry.id

    for i = #scratch, 1, -1 do scratch[i] = nil end
    for i = 1, #items do scratch[#scratch + 1] = items[i] end
    ns:GetModule("API"):MenuItemsFor(providerID, entryID, scratch)
    table.sort(scratch, byOrder)

    -- Copied out because the callback runs long after this returns and the provider's list is
    -- a reused table that the next GetEntryMenu overwrites.
    local list = {}
    for i = 1, #scratch do list[i] = scratch[i] end
    if #list == 0 then return false end

    MenuUtil.CreateContextMenu(row, function(_, root)
        for i = 1, #list do
            local it = list[i]
            if it.kind == "title" then
                root:CreateTitle(it.text or "")
            elseif it.kind == "divider" then
                root:CreateDivider()
            else
                local label = it.label or LABELS[it.id]
                if label then
                    root:CreateButton(it.danger and DANGER:format(label) or label,
                        function() run(providerID, entryID, it) end)
                end
            end
        end
        root:CreateDivider()
        root:CreateButton(L["Cancel"], function() end)
    end)
    return true
end
