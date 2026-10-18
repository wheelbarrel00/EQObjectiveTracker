local _, ns = ...

local Popups = ns:RegisterModule("AutoQuestPopups", {})

local list        = {}
local count       = 0
local completeSet = {}
local byGroup     = { campaign = 0, quests = 0 }

-- /eqot popup test. English like the rest of that command's output.
local SAMPLE_TITLE = "Sample quest (/eqot popup test)"
local sampleOn     = false

local function questTitle(questID)
    if C_QuestLog.GetTitleForQuestID then
        local t = C_QuestLog.GetTitleForQuestID(questID)
        if t and t ~= "" then return t end
    end
    if QuestUtils_GetQuestName then
        local n = QuestUtils_GetQuestName(questID)
        if n and n ~= "" then return n end
    end
    return "Quest #" .. tostring(questID)
end

-- Gated on the quest actually being in the log, which is what routes a Discovered popup to
-- Quests rather than Campaign. EQ resolves this through its quest Cache, and a quest that
-- has only been offered is not in that Cache yet, so it reads as non-campaign there too.
local function isCampaign(questID)
    if not C_QuestLog.GetLogIndexForQuestID then return false end
    if not C_QuestLog.GetLogIndexForQuestID(questID) then return false end
    if not ns.Has.CampaignInfo then return false end
    local cid = C_CampaignInfo.GetCampaignID(questID)
    return (cid and cid ~= 0) and true or false
end

function Popups:Available()
    return ns.Has.AutoQuestPopUp
end

-- Rebuilt into a reused array and valid only until the next Refresh, the same contract a
-- provider's entries carry. Must run before Feed:Build, because Filter reads completeSet.
function Popups:Refresh()
    count = 0
    byGroup.campaign, byGroup.quests = 0, 0
    wipe(completeSet)

    local cfg = ns:GetModule("DB"):Tracker()
    -- Safe mode reaches in here too - this has no OnEnable to skip, Tracker:Render drives it
    if ns:SafeMode() or not (self:Available() and (not cfg or cfg.showQuestPopups ~= false)) then
        for i = #list, 1, -1 do list[i] = nil end
        return
    end

    for i = 1, GetNumAutoQuestPopUps() do
        local questID, popUpType = GetAutoQuestPopUp(i)
        if questID then
            count = count + 1
            local p = list[count]
            if not p then p = {}; list[count] = p end
            p.questID   = questID
            p.popUpType = popUpType
            p.groupID   = isCampaign(questID) and "campaign" or "quests"
            p.title     = questTitle(questID)
            byGroup[p.groupID] = (byGroup[p.groupID] or 0) + 1
            -- Only COMPLETE suppresses a row. A Discovered popup is for a quest that is not
            -- in the log at all, so it has no row to collide with.
            if popUpType == "COMPLETE" then completeSet[questID] = true end
        end
    end
    -- No quest ID, so the box's click does nothing and no row is suppressed for it.
    if sampleOn then
        count = count + 1
        local p = list[count]
        if not p then p = {}; list[count] = p end
        p.questID, p.popUpType, p.groupID, p.title = nil, "OFFER", "quests", SAMPLE_TITLE
        byGroup.quests = byGroup.quests + 1
    end
    for i = #list, count + 1, -1 do list[i] = nil end
end

function Popups:ToggleSample()
    sampleOn = not sampleOn
    return sampleOn
end

function Popups:Count()
    return count
end

function Popups:CountFor(groupID)
    return byGroup[groupID] or 0
end

function Popups:Get(i)
    return list[i]
end

function Popups:IsSuppressed(questID)
    return completeSet[questID] == true
end

function Popups:DebugLine()
    local suppressed = 0
    for _ in pairs(completeSet) do suppressed = suppressed + 1 end
    return ("quest popups: %s | %d live, campaign %d, quests %d, suppressing %d rows | sample %s")
        :format(self:Available() and "available" or "no API",
                count, byGroup.campaign, byGroup.quests, suppressed, sampleOn and "on" or "off")
end
