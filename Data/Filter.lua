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

-- Feed reports "filtered N" and could never say why, which has cost a misdiagnosis: a stale
-- isTracked and an active zone filter look identical from that number. One integer bump per
-- rejected entry, so it stays on in release.
Filter.rejects = { popup = 0, watched = 0, category = 0, zone = 0 }
-- The rows the zone rule would have hidden and the campaign exemption kept, so a "why is
-- this quest showing" report is answered from the same line as the rejects.
Filter.campaignKept = 0
-- The rows To-Do Mode's view hid for being finished or not, read by its status line.
Filter.todoHidden = 0

function Filter:BeginPass()
    local r = self.rejects
    r.popup, r.watched, r.category, r.zone = 0, 0, 0, 0
    self.campaignKept = 0
    self.todoHidden = 0
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
    for i = 1, #self.CATEGORIES do
        local key = self.CATEGORIES[i].key
        cats[i] = ("%s=%s"):format(key, tostring((f and f[key]) ~= false))
    end

    return ("filters: onlyWatched=%s onlyCurrentZone=%s campaignAnyZone=%s | %s\n      rejected this pass: watched %d, category %d, zone %d, popup %d | campaign kept from other zones %d")
        :format(tostring(cfg and cfg.showOnlyWatched and true or false),
                tostring(f and f.onlyCurrentZone and true or false),
                tostring(f and f.campaignAnyZone and true or false),
                f and table.concat(cats, " ") or "no filters table",
                r.watched, r.category, r.zone, r.popup, self.campaignKept)
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
