std = "lua51"
max_line_length = false
exclude_files = { "Libs/**" }

-- The addon namespace is the only global we are allowed to create.
globals = {
    "EQObjectiveTracker",
    "EQObjectiveTrackerDB",
    "EQObjectiveTrackerCharDB",
    "SLASH_EQOT1",
    "SLASH_EQOT2",
    "SlashCmdList",
    "BINDING_HEADER_EQOBJECTIVETRACKER",
    -- Classic's color picker is driven by assigning callbacks onto the frame itself
    "ColorPickerFrame",
    -- Blizzard's own quest log sets .questID on this before showing it, and the pop-out
    -- reads it back, so the field has to be written rather than passed.
    "QuestLogPopupDetailFrame",
}

read_globals = {
    -- Lua-side Blizzard shims
    "wipe", "tremove", "tinsert", "strsplit", "strtrim", "strjoin", "format",
    "CopyTable", "Mixin", "CreateFromMixins", "geterrorhandler", "securecall",
    "date", "time", "bit",

    -- Core UI
    "CreateFrame", "UIParent", "GameTooltip", "GameFontNormal", "GameFontNormalLarge",
    "GameFontNormalSmall", "GameFontHighlightSmall", "ObjectiveTrackerHeaderFont",
    "InCombatLockdown", "IsModifiedClick", "GetCursorPosition", "GetTime", "hooksecurefunc",
    -- UISpecialFrames is deliberately NOT here. Putting a frame name in that list taints
    -- Blizzard's panel manager on every Escape press - see closeOnEscape in Options/Frame.lua.
    "RAID_CLASS_COLORS", "GetQuestDifficultyColor", "CreateColor",
    "STANDARD_TEXT_FONT", "OpacitySliderFrame",
    "UnitClass", "UnitName", "GetRealmName", "GetZoneText", "PlaySound", "ReloadUI",
    -- Locales/*.lua gate on the client language before touching ns.L
    "GetLocale",
    -- Picks which Classic Wowhead site a row menu link opens
    "GetExpansionLevel",
    -- Blizzard's Classic quest log, whose tracked checkmarks UI/QuestLogChecks.lua repaints.
    -- UI/Row.lua reads ChatEdit_GetActiveWindow too, to tell a link click from an ordinary one.
    "QuestLog_Update", "IsShiftKeyDown", "ChatEdit_GetActiveWindow", "NONE",

    -- Shift-clicking a tracker row into chat. GetQuestLink is the quest API half and stays in
    -- Data/, ChatEdit_InsertLink is the frame half and stays in UI/.
    "GetQuestLink", "ChatEdit_InsertLink",

    -- Everything Quests' saved variable, read one way for the config import. Never its
    -- addon table: EQ depends on EQOT, so EQOT loads first and that table is always nil.
    "EverythingQuestsDB",
    -- The other quest tracker's addon table and its tracker root frame. Read only, for the
    -- coexistence toggle.
    "Questie", "Questie_BaseFrame",

    -- Namespaced API
    "C_Timer", "C_Map", "C_QuestLog", "C_QuestInfoSystem", "C_CampaignInfo",
    "C_SuperTrack", "C_TaskQuest", "C_ContentTracking", "C_PerksActivities",
    -- The Midnight neighborhood initiative, which is what Blizzard draws under its own
    -- ENDEAVORS header. A different system from the Traveler's Log above it.
    "C_NeighborhoodInitiative",
    "C_Scenario", "C_ScenarioInfo", "GetInstanceInfo", "C_Texture", "C_AddOns", "Enum",
    "C_VignetteInfo", "C_UnitAuras", "C_UIWidgetManager",
    "IsInInstance", "C_ChallengeMode", "WorldMapFrame",
    "C_TradeSkillUI", "C_CurrencyInfo", "C_Item", "C_FactionInfo", "ProfessionsUtil", "QuestUtil",
    "C_LFGList", "LFGListUtil_FindQuestGroup", "C_TaxiMap", "FlightMapFrame",
    "PlaySoundFile", "ERR_QUEST_COMPLETE_S", "C_QuestLine", "MenuUtil",

    -- Blizzard format strings, used so reagent lines stay localized
    "PROFESSIONS_TRACKER_REAGENT_FORMAT", "PROFESSIONS_TRACKER_REAGENT_COUNT_FORMAT",
    "PROFESSIONS_TRACKER_REAGENT_RANGE_FORMAT", "PROFESSIONS_CRAFTING_FORM_RECRAFTING_HEADER",

    -- Legacy / cross-flavor globals guarded by Core/Compat.lua
    "GetAchievementInfo", "GetAchievementNumCriteria", "GetAchievementCriteriaInfo",
    "GetTrackedAchievements", "RemoveTrackedAchievement", "OpenAchievementFrameToAchievement",
    "ShowAchievementFrameForAchievement",
    "GetQuestLogRewardMoney", "GetNumQuestLogRewards", "GetQuestLogRewardInfo",
    "HaveQuestRewardData", "GetCoinTextureString", "GetQuestLogRewardXP",
    "GetNumQuestLogChoices", "GetQuestLogChoiceInfo", "GetQuestLogItemLink",
    "GetInventorySlotInfo", "GetInventoryItemLink", "GetItemQualityColor",
    "GetItemInfoInstant",
    "GetQuestLogSpecialItemInfo", "GetQuestLogSpecialItemCooldown",
    "IsQuestLogSpecialItemInRange",
    -- The Classic quest log, which is index driven and lives on flat globals rather than
    -- C_QuestLog. Measured present on 1.15.9 and 2.5.6.
    "GetNumQuestLogEntries", "GetQuestLogTitle", "GetQuestLogIndexByID",
    "SelectQuestLogEntry", "GetNumQuestLeaderBoards", "GetQuestLogLeaderBoard",
    "IsQuestWatched", "AddQuestWatch", "RemoveQuestWatch", "GetQuestTagInfo",

    -- A percentage objective's real fill, and it is a bare global on retail with no C_QuestLog
    -- twin - C_QuestLog.GetQuestProgressBarPercent does not exist.
    "GetQuestProgressBarPercent",

    -- Read on every flavor, not only Classic. BackdropTemplateMixin guards 13 CreateFrame
    -- template arguments across UI/ and Options/, and QuestWatchFrame is Blizzard's tracker
    -- on Vanilla and TBC where ObjectiveTrackerFrame is retail's.
    "BackdropTemplateMixin", "QuestWatchFrame",

    "GetNumAutoQuestPopUps", "GetAutoQuestPopUp", "RemoveAutoQuestPopUp",
    "ShowQuestComplete", "ShowQuestOffer",
    "QuestUtils_IsQuestWorldQuest", "QuestUtils_GetQuestName",
    "QuestMapFrame_OpenToQuestDetails", "ToggleQuestLog", "GetQuestLogQuestText",
    "ObjectiveTrackerFrame",
    "QuestMapQuestOptions_OpenQuestDetails", "QuestMapFrame_UpdateQuestDetailsButtons",
    "QuestLogPopupDetailFrame_Update",
    "StaticPopup_Show", "StaticPopup_Hide", "StaticPopupDialogs",

    -- Libraries
    "LibStub",
}

ignore = {
    "212", -- unused argument, common in event handler signatures
}
