local _, ns = ...

local Feed = ns:RegisterModule("Feed", {})

Feed.byGroup = {}

-- Per-provider pipeline counters. Four integer bumps per entry, so this stays on in
-- release: "the provider returned N but nothing rendered" is otherwise unanswerable
-- without reading code.
Feed.stats = {}

-- Providers drawing on the same ID space (quests, world quests, bonus objectives all
-- use quest IDs) would otherwise show the same entry twice. Lowest provider priority
-- wins.
--
-- A claim is staked when an entry is actually DISPLAYED, never when it is merely
-- emitted. A world quest you are standing inside is in the quest log but has no watch
-- type, so the quests provider emits it and then hides it under "only show tracked" - an
-- emit-time claim would block the world quest provider from rendering an entry nobody
-- ends up showing, and it vanishes from the tracker entirely.
--
-- Claims are also never taken against the quest log directly: GetLogIndexForQuestID
-- returns non-nil for hidden task quests, so a log check would wrongly swallow them.
local spaces = {}
-- The shown entries of the quest id space. Each carries its distance, which only a quest row's title draws.
local questShown, nQuestShown = {}, 0

local function group(self, id)
    local g = self.byGroup[id]
    if not g then
        g = { id = id, entries = {}, visibleCount = 0, totalCount = 0, todo = { 0, 0, 0, 0 }, todoOn = false }
        self.byGroup[id] = g
    end
    return g
end

function Feed:Build()
    local Registry = ns:GetModule("Registry")
    local Filter   = ns:GetModule("Filter")
    local Sort     = ns:GetModule("Sort")
    local DB       = ns:GetModule("DB")
    local Entry    = ns:GetModule("Entry")
    local cfg      = DB and DB:Tracker()

    for _, g in pairs(self.byGroup) do
        wipe(g.entries)
        g.visibleCount, g.totalCount = 0, 0
        local t = g.todo
        t[1], t[2], t[3], t[4] = 0, 0, 0, 0
        g.todoOn = false
    end
    for _, s in pairs(spaces) do wipe(s) end
    nQuestShown = 0
    Filter:BeginPass()
    local ZoneGroups = ns:GetModule("ZoneGroups")
    local zoned = ZoneGroups and ZoneGroups:Grouping(cfg)
    if zoned then ZoneGroups:Begin(cfg) end
    local Todo = ns:GetModule("TodoMode")
    local view = Todo and Todo:IsOn(cfg) and Todo:View() or nil

    for _, p in ipairs(Registry:Active()) do
        if p._available then
            local claimed
            if p.idSpace then
                claimed = spaces[p.idSpace]
                if not claimed then claimed = {}; spaces[p.idSpace] = claimed end
            end

            local st = self.stats[p.id]
            if not st then st = {}; self.stats[p.id] = st end
            st.emitted, st.duplicate, st.filtered, st.shown = 0, 0, 0, 0

            local list = p:GetEntries()
            for i = 1, #list do
                local e = list[i]
                st.emitted = st.emitted + 1
                if claimed and claimed[e.id] then
                    st.duplicate = st.duplicate + 1
                else
                    if ns.DEBUG then
                        local ok, err = Entry:Validate(e, p)
                        if not ok then geterrorhandler()("EQOT provider " .. p.id .. ": " .. err) end
                    end
                    e.providerID = p.id
                    local g = group(self, e.groupID)
                    g.totalCount = g.totalCount + 1
                    if zoned then ZoneGroups:Note(e.groupID, e) end
                    local pView = p.todo and view or nil
                    if pView then
                        g.todoOn = true
                        Todo:Count(g, e, cfg, p)
                    end
                    -- Before the filter, so a hidden zone's quests are counted and their leaving can forget it.
                    Filter:NoteZone(e)
                    if Filter:Visible(e, cfg, p, pView) then
                        g.visibleCount = g.visibleCount + 1
                        g.entries[g.visibleCount] = e
                        st.shown = st.shown + 1
                        if claimed then claimed[e.id] = true end
                        if p.idSpace == "quest" then
                            nQuestShown = nQuestShown + 1
                            questShown[nQuestShown] = e
                        end
                    else
                        st.filtered = st.filtered + 1
                    end
                end
            end
        end
    end

    Filter:EndPass()
    local ManualOrder = ns:GetModule("ManualOrder")
    local DistanceMod = ns:GetModule("Distance")
    local showDistance = cfg ~= nil and cfg.showQuestDistance == true
    if DistanceMod then DistanceMod:Sync(cfg and cfg.sortMode, spaces.quest, showDistance) end
    -- Assigned on every pass, since entries are pooled.
    for i = 1, nQuestShown do
        local e = questShown[i]
        e.distance = (showDistance and DistanceMod and DistanceMod:Yards(e.id)) or nil
    end
    local cmp = Sort:For(cfg and cfg.sortMode, ManualOrder and ManualOrder:Get(), cfg and cfg.sortReverse)
    for _, g in pairs(self.byGroup) do
        table.sort(g.entries, cmp)
    end
    if ZoneGroups then ZoneGroups:Build(self.byGroup, cfg) end

    return self.byGroup
end

function Feed:Group(id)
    return self.byGroup[id]
end
