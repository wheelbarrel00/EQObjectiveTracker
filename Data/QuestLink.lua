local _, ns = ...

local QuestLink = ns:RegisterModule("QuestLink", {})

-- Byte-identical to Everything Quests' Compat.QuestLinkText, so a reference shared from either
-- addon reads the same and EQ's Classic chat filter can upgrade one of ours back into a link.
-- Do not "fix" this to call GetQuestLink on Classic: EQ's own harness asserts that call is never
-- made there.
local function plain(questID, title, level)
    if type(title) ~= "string" or title == "" then return nil end
    if type(level) == "number" and level > 0 then
        return ("[[%d] %s (%d)]"):format(level, title, questID)
    end
    return ("[%s (%d)]"):format(title, questID)
end

-- The plain form is the retail fallback too. A quest whose link will not resolve would
-- otherwise share nothing, and a gesture that silently does nothing reads as broken.
function QuestLink:For(questID, title, level)
    if type(questID) ~= "number" or questID <= 0 then return nil end

    if ns.Has.QuestLog and ns.Has.QuestLink then
        local ok, link = pcall(GetQuestLink, questID)
        if ok and type(link) == "string" and link:find("|Hquest:", 1, true) then
            return link
        end
    end

    return plain(questID, title, level)
end
