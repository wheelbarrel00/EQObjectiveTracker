local _, ns = ...

local Filter = ns:RegisterModule("Filter", {})
local L      = ns.L

-- First match wins, so this order is the precedence: a campaign daily filters as
-- campaign. Adding a category is one row here plus the tag on the provider - no
-- comparator, renderer, or branch anywhere else learns about it.
Filter.CATEGORIES = {
    { tag = "worldquest", key = "showWorld",    label = L["World Quests"]     },
    { tag = "bonus",      key = "showBonus",    label = L["Bonus Objectives"] },
    { tag = "campaign",   key = "showCampaign", label = L["Campaign quests"]  },
    { tag = "daily",      key = "showDaily",    label = L["Daily quests"]     },
    { tag = "weekly",     key = "showWeekly",   label = L["Weekly quests"]    },
    { tag = "scheduled",  key = "showScheduled", label = L["Scheduled quests"] },
    { tag = nil,          key = "showNormal",   label = L["Normal quests"]    },
}

-- Two pairs ANDed with the type boxes rather than more types, so a campaign or daily dungeon
-- quest still counts as an instance quest. Screen order.
Filter.PLACE = {
    { key = "showInstance",        label = L["Instance quests"]          },
    { key = "showOutsideInstance", label = L["Quests outside instances"] },
}
Filter.PROGRESS = {
    { key = "showUnfinished", label = L["Unfinished quests"] },
    { key = "showFinished",   label = L["Finished quests"]   },
}
Filter.INSTANCE_TAGS = { "dungeon", "raid", "delve" }

-- Feed reports "filtered N" and could never say why, which has cost a misdiagnosis: a stale
-- isTracked and an active zone filter look identical from that number. One integer bump per
-- rejected entry, so it stays on in release.
Filter.rejects = { popup = 0, watched = 0, category = 0, place = 0, progress = 0, zone = 0, hiddenZone = 0 }
-- The rows the zone rule would have hidden and the campaign exemption kept, so a "why is
-- this quest showing" report is answered from the same line as the rejects.
Filter.campaignKept = 0
-- The rows To-Do Mode's view hid for being finished or not, read by its status line.
Filter.todoHidden = 0

-- The quest log headings a player hid, kept per character. Feed notes each pass's headings for the menus,
-- and a heading is forgotten once its last quest leaves the log.
local zoneCount, zoneNames, zoneOf, noted = {}, {}, {}, {}
-- Quests that left the log since the last pass, with the heading each sat under. Never saved.
local gone = {}
local listNames, listCounts, stale = {}, {}, {}

function Filter:BeginPass()
    local r = self.rejects
    r.popup, r.watched, r.category, r.place, r.progress, r.zone, r.hiddenZone = 0, 0, 0, 0, 0, 0, 0
    wipe(zoneCount)
    wipe(zoneNames)
    wipe(zoneOf)
    wipe(noted)
    self.campaignKept = 0
    self.todoHidden = 0
end

local function hiddenSet(create)
    local DB   = ns:GetModule("DB")
    local char = DB and DB:Char()
    if not char then return nil end
    if create and type(char.hiddenZones) ~= "table" then char.hiddenZones = {} end
    return type(char.hiddenZones) == "table" and char.hiddenZones or nil
end

function Filter:HidesZone(name)
    local set = hiddenSet(false)
    return set ~= nil and set[name] == true
end

function Filter:IsZoneHidden(entry)
    local z = entry.zone
    return type(z) == "string" and z ~= "" and self:HidesZone(z)
end

function Filter:SetZoneHidden(name, hidden)
    if type(name) ~= "string" or name == "" then return end
    local set = hiddenSet(true)
    if set then set[name] = hidden and true or nil end
end

function Filter:HiddenZoneCount()
    local n, set = 0, hiddenSet(false)
    for _, v in pairs(set or {}) do
        if v == true then n = n + 1 end
    end
    return n
end

function Filter:ShowAllZones()
    local set = hiddenSet(false)
    if set then wipe(set) end
end

function Filter:NoteZone(entry)
    local z = entry.zone
    if type(z) ~= "string" or z == "" then return end
    local n = zoneCount[z]
    if not n then
        zoneNames[#zoneNames + 1] = z
        n = 0
    end
    zoneCount[z] = n + 1
    if entry.id then
        zoneOf[entry.id] = z
        noted[entry.id] = true
    end
end

local function byName(a, b)
    local c = strcmputf8i and strcmputf8i(a, b) or 0
    if c ~= 0 then return c < 0 end
    return a < b
end

-- The last pass's headings by name, then any hidden one with no quest left, so it can always be ticked back.
function Filter:ZoneList()
    wipe(listNames)
    wipe(listCounts)
    wipe(stale)
    for i = 1, #zoneNames do listNames[i] = zoneNames[i] end
    table.sort(listNames, byName)
    for name, v in pairs(hiddenSet(false) or {}) do
        if v == true and not zoneCount[name] then stale[#stale + 1] = name end
    end
    table.sort(stale, byName)
    for i = 1, #stale do listNames[#listNames + 1] = stale[i] end
    for i = 1, #listNames do listCounts[i] = zoneCount[listNames[i]] or 0 end
    return listNames, listCounts
end

-- A quest still noted means the log has not caught up, so it waits for the next pass.
function Filter:EndPass()
    if next(gone) == nil then return end
    local set = hiddenSet(false)
    for id, zone in pairs(gone) do
        if not noted[id] then
            if set and not zoneCount[zone] then set[zone] = nil end
            gone[id] = nil
        end
    end
end

function Filter:OnEnable()
    local function left(_, id)
        id = tonumber(id)
        local zone = id and zoneOf[id]
        if zone then gone[id] = zone end
    end
    local Events = ns:GetModule("Events")
    Events:On("QUEST_REMOVED", left)
    Events:On("QUEST_TURNED_IN", left)
end

-- Keyed by provider then entry id so two providers can never collide on a bare numeric id.
function Filter:IsPinned(entry)
    local DB   = ns:GetModule("DB")
    local char = DB and DB:Char()
    local byProvider = char and char.pinned and char.pinned[entry.providerID]
    return (byProvider and byProvider[entry.id]) and true or false
end

function Filter:SetPinned(entry, pinned)
    local DB   = ns:GetModule("DB")
    local char = DB and DB:Char()
    if not char then return end
    char.pinned = char.pinned or {}
    local byProvider = char.pinned[entry.providerID]
    if not byProvider then byProvider = {}; char.pinned[entry.providerID] = byProvider end
    byProvider[entry.id] = pinned or nil
end

local function countSet(char, key)
    local set = char and char[key]
    if not set then return 0, nil end
    local total, parts = 0, {}
    for providerID, byProvider in pairs(set) do
        local n = 0
        for _ in pairs(byProvider) do n = n + 1 end
        if n > 0 then
            total = total + n
            parts[#parts + 1] = ("%s %d"):format(providerID, n)
        end
    end
    -- pairs order is unspecified, so sort or the status line reshuffles between reads.
    table.sort(parts)
    return total, parts
end

function Filter:DebugLine()
    local DB   = ns:GetModule("DB")
    local char = DB and DB:Char()
    local pinned, pParts = countSet(char, "pinned")
    if pinned == 0 then return "pinned entries: none" end
    return ("pinned entries: %d (%s)"):format(pinned, table.concat(pParts, ", "))
end

-- Categories are walked from CATEGORIES rather than listed, so a new one reports itself.
function Filter:FiltersLine()
    local DB  = ns:GetModule("DB")
    local cfg = DB and DB:Tracker()
    local f   = cfg and cfg.filters
    local r   = self.rejects

    local cats = {}
    for _, run in ipairs({ self.CATEGORIES, self.PLACE, self.PROGRESS }) do
        for i = 1, #run do
            local key = run[i].key
            cats[#cats + 1] = ("%s=%s"):format(key, tostring((f and f[key]) ~= false))
        end
    end

    return ("filters: onlyWatched=%s onlyCurrentZone=%s campaignAnyZone=%s | %s\n      rejected this pass: watched %d, category %d, zone %d, popup %d | campaign kept from other zones %d | zone hidden %d (hiddenZones=%d) | place %d, progress %d")
        :format(tostring(cfg and cfg.showOnlyWatched and true or false),
                tostring(f and f.onlyCurrentZone and true or false),
                tostring(f and f.campaignAnyZone and true or false),
                f and table.concat(cats, " ") or "no filters table",
                r.watched, r.category, r.zone, r.popup, self.campaignKept, r.hiddenZone, self:HiddenZoneCount(),
                r.place, r.progress)
end

function Filter:PassesCategory(entry, f)
    if not f then return true end
    local tags = entry.tags
    if tags then
        for i = 1, #self.CATEGORIES do
            local c = self.CATEGORIES[i]
            if c.tag and tags[c.tag] then return f[c.key] ~= false end
        end
    end
    return f.showNormal ~= false
end

function Filter:IsInstance(entry)
    local tags = entry.tags
    if not tags then return false end
    for i = 1, #self.INSTANCE_TAGS do
        if tags[self.INSTANCE_TAGS[i]] then return true end
    end
    return false
end

-- No loaded provider tags an instance quest, so the pair would be dead.
function Filter:OffersPlace(Registry)
    for i = 1, #self.INSTANCE_TAGS do
        if Registry:HasTag(self.INSTANCE_TAGS[i]) then return true end
    end
    return false
end

function Filter:PassesPlace(entry, f)
    if not f then return true end
    if self:IsInstance(entry) then return f.showInstance ~= false end
    return f.showOutsideInstance ~= false
end

-- While To-Do Mode is on its counts decide progress, so the pair is not asked. Its switch, not a
-- view, since World Quests are handed no view.
function Filter:PassesProgress(entry, f, cfg)
    if not f then return true end
    local TodoMode = ns:GetModule("TodoMode")
    if TodoMode:IsOn(cfg) then return true end
    if TodoMode:IsFinished(entry) then return f.showFinished ~= false end
    return f.showUnfinished ~= false
end

function Filter:PassesWatched(entry, cfg)
    return not (cfg and cfg.showOnlyWatched and entry.isTracked == false)
end

-- nil from IsCurrentZone means the provider cannot tell, so it fails open. The second answer is
-- true only when the campaign exemption kept the quest.
function Filter:IsHere(entry, f, provider)
    if not (provider and provider.IsCurrentZone) or provider:IsCurrentZone(entry) ~= false then
        return true, false
    end
    if f and f.campaignAnyZone and entry.tags and entry.tags.campaign then return true, true end
    return false, false
end

-- Category filters are opt-in per provider. Without that gate an untagged entry from
-- any other provider falls through to showNormal, and unchecking "Normal" would hide
-- every achievement too. view is To-Do Mode's picked view, handed over only for a provider that
-- takes it, and nil is the filter as it has always been.
function Filter:Visible(entry, cfg, provider, view)
    local rejects = self.rejects

    -- A quest with a Complete popup is drawn as a popup box instead, so it must not also
    -- appear as a row. The suppression set is empty whenever the option is off, so this
    -- costs one lookup and needs no config branch of its own.
    -- Above the pin check on purpose: a pin must not resurrect the row beside its own popup.
    if provider and provider.idSpace == "quest" then
        local Popups = ns:GetModule("AutoQuestPopups")
        if Popups and Popups:IsSuppressed(entry.id) then
            rejects.popup = rejects.popup + 1
            return false
        end
    end

    -- Below the popup, above everything else, matching EQ: a pin is the player saying
    -- "keep this on screen", so it outranks every display setting below it.
    if self:IsPinned(entry) then return true end

    if not self:PassesWatched(entry, cfg) then
        rejects.watched = rejects.watched + 1
        return false
    end

    if provider and provider.filterCategories then
        local f = cfg and cfg.filters
        if not self:PassesCategory(entry, f) then
            rejects.category = rejects.category + 1
            return false
        end
        if not self:PassesPlace(entry, f) then
            rejects.place = rejects.place + 1
            return false
        end
        if not self:PassesProgress(entry, f, cfg) then
            rejects.progress = rejects.progress + 1
            return false
        end
        -- Below the pin check, so a pinned quest in a hidden zone still shows.
        if self:IsZoneHidden(entry) then
            rejects.hiddenZone = rejects.hiddenZone + 1
            return false
        end
        -- While To-Do Mode is on its view decides this, and the saved box is left alone.
        local TodoMode = view and ns:GetModule("TodoMode")
        local zoneRule
        if TodoMode then zoneRule = TodoMode:IsHereView(view) else zoneRule = f and f.onlyCurrentZone end
        local kept
        if zoneRule then
            local here
            here, kept = self:IsHere(entry, f, provider)
            if not here then
                rejects.zone = rejects.zone + 1
                return false
            end
        end
        if TodoMode and not TodoMode:Fits(view, true, TodoMode:IsFinished(entry)) then
            self.todoHidden = self.todoHidden + 1
            return false
        end
        -- Counted last, so a row the view then hid is never reported as kept.
        if kept then self.campaignKept = self.campaignKept + 1 end
    end

    return true
end
