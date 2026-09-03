local _, ns = ...

-- Feature detection only. Nothing in this addon may branch on WOW_PROJECT_ID or a
-- build number - Blizzard backports API into Classic builds constantly.
local Has = {}
ns.Has = Has

local function method(tbl, key)
    return (type(tbl) == "table" and type(tbl[key]) == "function") and true or false
end

local function global(name)
    return type(_G[name]) == "function" and true or false
end

Has.QuestLog            = method(C_QuestLog, "GetNumQuestLogEntries") and method(C_QuestLog, "GetInfo")
Has.QuestObjectives     = method(C_QuestLog, "GetQuestObjectives")
Has.QuestWatchType      = method(C_QuestLog, "GetQuestWatchType")
Has.QuestWatchAPI       = method(C_QuestLog, "AddQuestWatch") and method(C_QuestLog, "RemoveQuestWatch")
Has.QuestIsComplete     = method(C_QuestLog, "IsComplete")
Has.QuestIsFailed       = method(C_QuestLog, "IsFailed")
Has.QuestTagInfo        = method(C_QuestLog, "GetQuestTagInfo")
-- The index resolver is either/or, not both. GetLogIndexForQuestID is retail only, so ANDing it
-- in read false on Era and TBC and left the whole secure button pipeline inert there, while
-- GetQuestLogSpecialItemInfo is present on those clients and answers correctly.
Has.QuestSpecialItem    = global("GetQuestLogSpecialItemInfo")
                          and (method(C_QuestLog, "GetLogIndexForQuestID")
                               or global("GetQuestLogIndexByID"))
Has.AutoQuestPopUp      = global("GetNumAutoQuestPopUps") and global("GetAutoQuestPopUp")
-- Measured on 1.15.9: GetQuestLink(65) answered a link for a quest in the log and
-- GetQuestLink(1) answered nil, so it takes a quest ID and not a log index. Probed rather
-- than assumed present - no reading has been taken on 2.5.6 or on retail.
Has.QuestLink           = global("GetQuestLink")
Has.QuestDistance       = method(C_QuestLog, "GetDistanceSqToQuest")
Has.QuestsOnMap         = method(C_QuestLog, "GetQuestsOnMap")
Has.NextWaypoint        = method(C_QuestLog, "GetNextWaypoint")
Has.QuestClassification = method(C_QuestInfoSystem, "GetQuestClassification")
                          or method(C_QuestLog, "GetQuestClassification")
Has.CampaignInfo        = method(C_CampaignInfo, "GetCampaignID")
Has.SuperTrack          = method(C_SuperTrack, "SetSuperTrackedQuestID")
Has.WorldQuests         = method(C_QuestLog, "GetNumWorldQuestWatches")
                          and method(C_QuestLog, "GetQuestIDForWorldQuestWatchIndex")
Has.WorldQuestTime      = method(C_TaskQuest, "GetQuestTimeLeftMinutes")
-- GetQuestsForPlayerByMapID was renamed to GetQuestsOnMap - accept either
Has.TaskQuests          = method(C_TaskQuest, "GetQuestsOnMap")
                          or method(C_TaskQuest, "GetQuestsForPlayerByMapID")
Has.TaskQuestInfo       = method(C_TaskQuest, "GetQuestInfoByQuestID")
-- A percentage objective's real fill is in neither numFulfilled nor numRequired. The first is a
-- BARE GLOBAL and has no C_QuestLog twin, so it is probed with global() rather than method().
Has.QuestProgressBar    = global("GetQuestProgressBarPercent")
Has.TaskQuestProgressBar = method(C_TaskQuest, "GetQuestProgressBarInfo")
Has.WorldQuestWatchAPI  = method(C_QuestLog, "RemoveWorldQuestWatch")
Has.WorldQuestWatchAdd  = method(C_QuestLog, "AddWorldQuestWatch")
Has.ContentTracking     = method(C_ContentTracking, "GetTrackedIDs")
Has.PerksActivities     = method(C_PerksActivities, "GetTrackedPerksActivities")
Has.PerksActivityInfo   = method(C_PerksActivities, "GetPerksActivityInfo")
Has.TrackedRecipes      = method(C_TradeSkillUI, "GetRecipesTracked")
Has.RecipeSchematic     = method(ProfessionsUtil, "GetRecipeSchematic")
                          or method(C_TradeSkillUI, "GetRecipeSchematic")
Has.Scenario            = method(C_Scenario, "GetInfo")
Has.ScenarioCriteria    = method(C_ScenarioInfo, "GetCriteriaInfo")
Has.ScenarioBonus       = method(C_Scenario, "GetBonusSteps")
                          and method(C_ScenarioInfo, "GetCriteriaInfoByStep")
Has.Map                 = method(C_Map, "GetBestMapForUnit")
Has.MythicPlus          = method(C_ChallengeMode, "IsChallengeModeActive")
Has.Atlas               = method(C_Texture, "GetAtlasInfo")
Has.AddOns              = method(C_AddOns, "IsAddOnLoaded")

Has.Achievements        = global("GetAchievementInfo") and global("GetAchievementNumCriteria")
                          and global("GetAchievementCriteriaInfo")
Has.AchievementTracking = Has.ContentTracking or global("GetTrackedAchievements")

Has.QuestClassificationEnum = (type(Enum) == "table" and type(Enum.QuestClassification) == "table")
                              and true or false

do
    local probe = CreateFrame("Frame")
    Has.ResizeBounds = type(probe.SetResizeBounds) == "function"
    probe:SetParent(nil)
end
