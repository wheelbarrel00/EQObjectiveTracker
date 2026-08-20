local _, ns = ...

local Entry    = ns:GetModule("Entry")
local Registry = ns:GetModule("Registry")
local L        = ns.L

local STATE, LINE, ICON = Entry.STATE, Entry.LINE, Entry.ICON

local Achievements = {
    id       = "achievements",
    groups   = { "achievements" },
    priority = 40,
    tags     = {},
}

-- Progress-bar criteria carry an empty criteriaString but real quantities, so they
-- are only detectable through this GetAchievementCriteriaInfo flag bit.
local PROGRESS_BAR_FLAG = 0x1
local MAX_CRITERIA      = 12

local ACH_TYPE    = Enum and Enum.ContentTrackingType and Enum.ContentTrackingType.Achievement
local STOP_MANUAL = (Enum and Enum.ContentTrackingStopType and Enum.ContentTrackingStopType.Manual) or 2

local store = Entry.NewStore({
    groupID   = "achievements",
    icon      = { kind = ICON.TEXTURE },
    isTracked = true,
})

local ids = {}

local function trackedIDs()
    wipe(ids)
    if ns.Has.ContentTracking and ACH_TYPE then
        local t = C_ContentTracking.GetTrackedIDs(ACH_TYPE)
        for i = 1, (t and #t or 0) do
            if t[i] then ids[#ids + 1] = t[i] end
        end
    end
    if #ids == 0 and GetTrackedAchievements then
        local t = { GetTrackedAchievements() }
        for i = 1, #t do
            if t[i] and t[i] ~= 0 then ids[#ids + 1] = t[i] end
        end
    end
    return ids
end

local function fillCriteria(e, id)
    Entry.BeginLines(e)
    local num, shown = GetAchievementNumCriteria(id) or 0, 0
    for c = 1, num do
        if shown >= MAX_CRITERIA then break end
        local text, _, done, quantity, required, _, flags = GetAchievementCriteriaInfo(id, c)
        local isBar    = flags and bit.band(flags, PROGRESS_BAR_FLAG) ~= 0
        local hasMeter = required and required > 1
        if (text and text ~= "") or isBar then
            local ln = Entry.PushLine(e)
            ln.text      = text or ""
            ln.completed = done and true or false
            -- A criterion with no count of its own renders dimmed, which is the shape
            -- LINE.NOTE already carries. Anything metered keeps the ordinary bar look.
            if hasMeter then
                ln.current, ln.required = quantity, required
                ln.kind = LINE.PROGRESSBAR
            else
                ln.kind = LINE.NOTE
            end
            shown = shown + 1
        end
    end
    Entry.EndLines(e)
end

function Achievements:IsAvailable()
    return ns.Has.Achievements and ns.Has.AchievementTracking
end

function Achievements:GetEntries()
    local list = trackedIDs()
    store:Begin()
    for i = 1, #list do
        local id = list[i]
        local _, name, _, completed, _, _, _, _, _, icon = GetAchievementInfo(id)
        if name then
            local e = store:Acquire(id)
            e.title        = name
            e.state        = completed and STATE.COMPLETE or STATE.ACTIVE
            e.icon.texture = icon
            fillCriteria(e, id)
        end
    end
    return store:Finish()
end

function Achievements:OnEntryClick(entry, button)
    if button == "RightButton" then
        if ns.Has.ContentTracking and ACH_TYPE then
            C_ContentTracking.StopTracking(ACH_TYPE, entry.id, STOP_MANUAL)
        elseif RemoveTrackedAchievement then
            RemoveTrackedAchievement(entry.id)
        end
    -- 12.1 is reported to have renamed this call. The old name is tried second rather than
    -- dropped, because the Mainline TOC still targets 120007 and 120005.
    elseif ShowAchievementFrameForAchievement then
        ShowAchievementFrameForAchievement(entry.id)
    elseif OpenAchievementFrameToAchievement then
        OpenAchievementFrameToAchievement(entry.id)
    end
end

function Achievements:OnEntryTooltip(entry, tooltip)
    tooltip:AddLine(entry.title, 1, 0.82, 0)
    tooltip:AddLine(L["Left-click to open, right-click to untrack."], 0.6, 0.6, 0.6)
end

function Achievements:Enable(notifyDirty)
    local Events = ns:GetModule("Events")
    Events:On("TRACKED_ACHIEVEMENT_LIST_CHANGED", notifyDirty)
    Events:On("TRACKED_ACHIEVEMENT_UPDATE",       notifyDirty)
    Events:On("CONTENT_TRACKING_UPDATE",          notifyDirty)
    Events:On("ACHIEVEMENT_EARNED",               notifyDirty)
    Events:On("PLAYER_ENTERING_WORLD",            notifyDirty)
end

Registry:Register(Achievements)
