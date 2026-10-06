local _, ns = ...

local SuperTrackPersist = ns:RegisterModule("SuperTrackPersist", {})

local CLEAR_DELAY = 0.5

local function shouldRestore()
    local gen = ns:GetModule("DB"):General()
    return (gen and gen.restoreSuperTrackOnLogin) == true
end

local function focusAcceptedWanted()
    local DB  = ns:GetModule("DB")
    local cfg = DB and DB:Tracker()
    return not (cfg and cfg.focusAcceptedQuests == false)
end

-- The game focuses a quest picked up while nothing is focused, through
-- QuestUtil.CheckAutoSuperTrackQuest. Its Allow half runs before the set, so the hook there is
-- what tells a focus the game just put on that quest from one the player already had on it.
local hooked, armedFor = false, nil
local asked, fromNothing, cleared, lastCleared = 0, 0, 0, nil

local function onAllow(questID, forceAllowTasks)
    armedFor = nil
    -- Blizzard passes forceAllowTasks only for a click on a world quest's map pin, which is the
    -- player choosing it.
    if forceAllowTasks then return end
    if not C_SuperTrack.IsSuperTrackingAnything() then armedFor = questID end
end

local function onCheck(questID)
    local was = armedFor
    armedFor = nil
    asked = asked + 1
    if was == nil or was ~= questID then return end
    fromNothing = fromNothing + 1
    if focusAcceptedWanted() then return end
    if C_SuperTrack.GetSuperTrackedQuestID() ~= questID then return end
    C_SuperTrack.SetSuperTrackedQuestID(0)
    cleared, lastCleared = cleared + 1, questID
end

local function hookAutoFocus()
    if not (type(QuestUtil) == "table" and type(QuestUtil.AllowAutoSuperTrackQuest) == "function"
            and type(QuestUtil.CheckAutoSuperTrackQuest) == "function"
            and C_SuperTrack.IsSuperTrackingAnything and C_SuperTrack.GetSuperTrackedQuestID) then
        return
    end
    hooksecurefunc(QuestUtil, "AllowAutoSuperTrackQuest", onAllow)
    hooksecurefunc(QuestUtil, "CheckAutoSuperTrackQuest", onCheck)
    hooked = true
end

function SuperTrackPersist:OnEnable()
    if not ns.Has.SuperTrack then return end
    hookAutoFocus()
    local Events = ns:GetModule("Events")

    Events:On("PLAYER_ENTERING_WORLD", function(_, isInitialLogin)
        -- Only a fresh login. A reload or a zone change must leave the current
        -- super-track alone, or every loading screen would drop the player's arrow.
        if not isInitialLogin then return end
        if shouldRestore() then return end
        C_Timer.After(CLEAR_DELAY, function()
            C_SuperTrack.SetSuperTrackedQuestID(0)
        end)
    end)
end

function SuperTrackPersist:DebugLine()
    if not ns.Has.SuperTrack then return nil end
    local DB  = ns:GetModule("DB")
    local cfg = (DB and DB:Tracker()) or {}
    return ("focus: a click on the focused quest %s | newly accepted quests %s | game auto-focus %s,"
            .. " asked %d, %d with nothing focused, %d taken back (last %s)"):format(
        cfg.clickToUnfocus == true and "unfocuses it" or "keeps it",
        focusAcceptedWanted() and "focused" or "left unfocused",
        hooked and "hooked" or "NOT HOOKED",
        asked, fromNothing, cleared, tostring(lastCleared))
end
