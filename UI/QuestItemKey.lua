local _, ns = ...

-- One named secure button for a macro or key binding: /click EQOTQuestItem uses the followed quest's
-- item. Under Forever's Gamepad UI the supported route from a pad button is a macro on its action bar.
-- Parented to UIParent, never the tracker, so it cannot make the tracker's frames protected in combat.
local QuestItemKey = ns:RegisterModule("QuestItemKey", {})

local button, questID, link
local pending = false

local function apply()
    pending = false
    if not button then
        button = CreateFrame("Button", "EQOTQuestItem", UIParent, "SecureActionButtonTemplate")
        button:SetSize(1, 1)
        button:SetAlpha(0)
        button:EnableMouse(false)
        button:RegisterForClicks("AnyDown", "AnyUp")
        -- /click sends only a release, which the secure handler skips while it acts on the press,
        -- as ActionButtonUseKeyDown (on by default) asks. On the release, a key binding fires too.
        button:SetAttribute("useOnKeyDown", false)
        button:SetAttribute("type", "item")
    end
    local _, id = ns:GetModule("Focus"):Get()
    questID = id
    link = id and ns:GetModule("QuestItems"):Get(id) or nil
    button:SetAttribute("item", link)
end

function QuestItemKey:Refresh()
    pending = not ns:GetModule("Events"):RunWhenOutOfCombat("eqot.questItemKey", apply)
end

function QuestItemKey:OnEnable()
    local Events = ns:GetModule("Events")
    ns:GetModule("Focus"):OnDirty(function() QuestItemKey:Refresh() end)
    Events:On("QUEST_LOG_UPDATE", function()
        Events:Debounce("eqot.questItemKey", 0.2, function() QuestItemKey:Refresh() end)
    end)
    self:Refresh()
end

function QuestItemKey:DebugLine()
    return ("quest item key: built %s, quest %s, item %s, pending after combat %s"):format(button and "yes" or "no",
        tostring(questID or "-"), tostring(link or "-"), pending and "yes" or "no")
end
