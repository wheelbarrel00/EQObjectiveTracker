local _, ns = ...

local QR = ns:RegisterModule("QuestRewards", {})

local EQUIP_SLOTS = {
    INVTYPE_HEAD           = { "HEADSLOT" },
    INVTYPE_NECK           = { "NECKSLOT" },
    INVTYPE_SHOULDER       = { "SHOULDERSLOT" },
    INVTYPE_CLOAK          = { "BACKSLOT" },
    INVTYPE_CHEST          = { "CHESTSLOT" },
    INVTYPE_ROBE           = { "CHESTSLOT" },
    INVTYPE_WAIST          = { "WAISTSLOT" },
    INVTYPE_LEGS           = { "LEGSSLOT" },
    INVTYPE_FEET           = { "FEETSLOT" },
    INVTYPE_WRIST          = { "WRISTSLOT" },
    INVTYPE_HAND           = { "HANDSSLOT" },
    INVTYPE_FINGER         = { "FINGER0SLOT", "FINGER1SLOT" },
    INVTYPE_TRINKET        = { "TRINKET0SLOT", "TRINKET1SLOT" },
    INVTYPE_WEAPON         = { "MAINHANDSLOT", "SECONDARYHANDSLOT" },
    INVTYPE_2HWEAPON       = { "MAINHANDSLOT" },
    INVTYPE_WEAPONMAINHAND = { "MAINHANDSLOT" },
    INVTYPE_WEAPONOFFHAND  = { "SECONDARYHANDSLOT" },
    INVTYPE_RANGED         = { "MAINHANDSLOT" },
    INVTYPE_RANGEDRIGHT    = { "MAINHANDSLOT" },
    INVTYPE_SHIELD         = { "SECONDARYHANDSLOT" },
    INVTYPE_HOLDABLE       = { "SECONDARYHANDSLOT" },
}

-- An equipLoc token IS the name of a Blizzard global string, so the client already holds
-- the slot name in the player's own language. That beats a hand-maintained table wrapped
-- in L: it is right in every locale rather than the ones we ship, it matches the wording
-- on the item tooltip being compared against, and it keeps ~20 phrases out of the manifest.
-- It also removes L["Back"] for the cloak slot, which a translator with no context would
-- have rendered as the navigation word - the exact defect this port found in EQ.
local function slotLabel(equipLoc)
    return (equipLoc and _G[equipLoc]) or ""
end

local lines, pool = {}, {}

local function reset()
    for i = #lines, 1, -1 do
        pool[#pool + 1] = lines[i]
        lines[i] = nil
    end
end

local function push(kind)
    local e = tremove(pool) or {}
    e.kind = kind
    e.text, e.done, e.amount                 = nil, nil, nil
    e.name, e.count, e.quality               = nil, nil, nil
    e.ilvl, e.showIlvl, e.slotLabel          = nil, nil, nil
    e.cmpEmpty, e.cmpLowest                  = nil, nil
    lines[#lines + 1] = e
    return e
end

local _slotID = {}
local function slotID(name)
    local id = _slotID[name]
    if id == nil then
        id = (GetInventorySlotInfo and GetInventorySlotInfo(name)) or false
        _slotID[name] = id
    end
    return id or nil
end

local function equipLocOf(itemID)
    if not itemID then return nil end
    local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not instant then return nil end
    return select(4, instant(itemID))
end

local function detailedIlvl(link)
    if not (link and C_Item and C_Item.GetDetailedItemLevelInfo) then return nil end
    return C_Item.GetDetailedItemLevelInfo(link)
end

local function lowestEquipped(equipLoc)
    local slots = EQUIP_SLOTS[equipLoc]
    if not slots then return nil, false end
    local lowest, hasEmpty
    for i = 1, #slots do
        local id = slotID(slots[i])
        if id then
            local link = GetInventoryItemLink and GetInventoryItemLink("player", id)
            if link then
                local il = detailedIlvl(link)
                if il and (not lowest or il < lowest) then lowest = il end
            else
                hasEmpty = true
            end
        end
    end
    return lowest, hasEmpty and true or false
end

local function addItem(questID, kind, index, name, count, quality, itemID, rewardIlvl)
    local equipLoc = equipLocOf(itemID)
    if not rewardIlvl then
        local link = GetQuestLogItemLink and GetQuestLogItemLink(kind, index, questID)
        if link then rewardIlvl = detailedIlvl(link) end
    end

    local e = push("item")
    e.name, e.count, e.quality, e.ilvl = name, count, quality, rewardIlvl
    e.showIlvl = (equipLoc and EQUIP_SLOTS[equipLoc] and rewardIlvl and rewardIlvl > 0) and true or false

    if equipLoc and rewardIlvl and rewardIlvl > 0 and EQUIP_SLOTS[equipLoc] then
        local lowest, hasEmpty = lowestEquipped(equipLoc)
        e.cmpEmpty  = hasEmpty
        e.cmpLowest = (not hasEmpty) and lowest or nil
        e.slotLabel = slotLabel(equipLoc)
    end
end

-- Total by construction, as EQ's Util.QuestTitle(id, true) is: a bonus step's reward quest
-- is a hidden container whose name streams in late, and the tooltip header is drawn once on
-- hover with no re-show, so returning nil leaves a blank line there for the whole hover.
function QR:Title(questID)
    if questID then
        if C_QuestLog and C_QuestLog.GetTitleForQuestID then
            local t = C_QuestLog.GetTitleForQuestID(questID)
            if t and t ~= "" then return t end
        end
        if QuestUtils_GetQuestName then
            local n = QuestUtils_GetQuestName(questID)
            if n and n ~= "" then return n end
        end
        if ns.Has.TaskQuestInfo then
            local t = C_TaskQuest.GetQuestInfoByQuestID(questID)
            if t and t ~= "" then return t end
        end
    end
    return "Quest #" .. tostring(questID)
end

-- The gray line EQ puts under a world quest's title. Nil for an ordinary quest, which is
-- what keeps the line off those tooltips without the renderer needing to know the row type.
function QR:FactionName(questID)
    if not (questID and C_QuestLog and C_QuestLog.GetQuestFactionID) then return nil end
    local id = C_QuestLog.GetQuestFactionID(questID)
    if not id then return nil end
    if C_FactionInfo and C_FactionInfo.GetFactionDataByID then
        local data = C_FactionInfo.GetFactionDataByID(id)
        return data and data.name or nil
    end
    return nil
end

-- Measured on Era 1.15.9: GetQuestLogRewardXP ignores its argument and answers for the SELECTED
-- entry, so XP is read with the selection moved and put back, never from a hover. The questID is
-- still passed because TBC is unmeasured. Split on the flavor flag, since retail has it too.
local xpBySelection = not ns.Has.QuestLog

-- A quest pays less once the player outlevels it, so every stored figure belongs to one level.
local xpCache, xpLevel = {}, nil

-- A refused read stores nothing, so without a wait it would move the selection again on every
-- pass. The wait is chosen, not measured.
local XP_RETRY_S = 30
local xpRefusedAt = {}
local xpStats = { sweeps = 0, reads = 0, refused = 0, unrestored = 0 }

local function waiting(questID, clock)
    local at = xpRefusedAt[questID]
    return at ~= nil and clock - at < XP_RETRY_S
end

function QR:NeedsXP(questID)
    if not xpBySelection then return false end
    if xpLevel ~= UnitLevel("player") then return true end
    return xpCache[questID] == nil and not waiting(questID, GetTime())
end

-- Read to n, never #, because the caller reuses both arrays.
function QR:CollectXP(indices, ids, n)
    if not (xpBySelection and n > 0) then return end
    if type(GetQuestLogRewardXP) ~= "function" or type(SelectQuestLogEntry) ~= "function" then
        return
    end
    local okBefore, before = pcall(GetQuestLogSelection)
    if not (okBefore and type(before) == "number") then return end

    local level = UnitLevel("player")
    if xpLevel ~= level then
        wipe(xpCache)
        wipe(xpRefusedAt)
        xpLevel = level
    end

    xpStats.sweeps = xpStats.sweeps + 1
    local clock = GetTime()
    local moved = false
    for k = 1, n do
        local index, id = indices[k], ids[k]
        if xpCache[id] == nil and not waiting(id, clock) then
            moved = true
            pcall(SelectQuestLogEntry, index)
            -- Confirmed rather than assumed, because a figure read while the selection sat
            -- elsewhere belongs to another quest.
            local okSel, sel = pcall(GetQuestLogSelection)
            local okXP, xp
            if okSel and sel == index then okXP, xp = pcall(GetQuestLogRewardXP, id) end
            if okXP and type(xp) == "number" then
                xpCache[id] = xp
                xpRefusedAt[id] = nil
                xpStats.reads = xpStats.reads + 1
            else
                xpRefusedAt[id] = clock
                xpStats.refused = xpStats.refused + 1
            end
        end
    end

    if moved then
        pcall(SelectQuestLogEntry, before)
        local okAfter, after = pcall(GetQuestLogSelection)
        if not (okAfter and after == before) then xpStats.unrestored = xpStats.unrestored + 1 end
    end
end

function QR:DebugLine()
    if not xpBySelection then return nil end
    local figures, refusals = 0, 0
    for _ in pairs(xpCache) do figures = figures + 1 end
    for _ in pairs(xpRefusedAt) do refusals = refusals + 1 end
    return ("reward xp: read by selection | %d figures held at level %s, player %s, %d refusals held | %d sweep(s), %d read, %d refused, %d not restored"):format(
        figures, tostring(xpLevel), tostring(UnitLevel("player")), refusals,
        xpStats.sweeps, xpStats.reads, xpStats.refused, xpStats.unrestored)
end

-- Structured rather than pre-formatted: the color and the indent are the renderer's, which
-- is what keeps every escape sequence out of this layer. Valid until the next call.
function QR:Lines(questID)
    reset()
    if not questID then return lines end

    if C_QuestLog and C_QuestLog.GetQuestObjectives then
        local objs = C_QuestLog.GetQuestObjectives(questID)
        for i = 1, (objs and #objs or 0) do
            local o = objs[i]
            if o and o.text and o.text ~= "" then
                local e = push("objective")
                e.text = o.text
                e.done = o.finished and true or false
            end
        end
    end

    if C_TaskQuest and C_TaskQuest.RequestPreloadRewardData then
        C_TaskQuest.RequestPreloadRewardData(questID)
    end

    local money = GetQuestLogRewardMoney and GetQuestLogRewardMoney(questID) or 0
    if money and money > 0 then
        push("money").amount = money
    end

    local xp
    if xpBySelection then
        if xpLevel == UnitLevel("player") then xp = xpCache[questID] end
    else
        xp = GetQuestLogRewardXP and GetQuestLogRewardXP(questID) or 0
    end
    if xp and xp > 0 then
        push("xp").amount = xp
    end

    local numItems = GetNumQuestLogRewards and GetNumQuestLogRewards(questID) or 0
    for i = 1, numItems do
        local name, _, count, quality, _, itemID, ilvl = GetQuestLogRewardInfo(i, questID)
        if name then addItem(questID, "reward", i, name, count, quality, itemID, ilvl) end
    end

    local numChoices = GetNumQuestLogChoices and GetNumQuestLogChoices(questID) or 0
    if numChoices and numChoices > 0 then
        push("choices")
        for i = 1, numChoices do
            local name, _, count, quality, _, itemID = GetQuestLogChoiceInfo(i, questID)
            if name then addItem(questID, "choice", i, name, count, quality, itemID, nil) end
        end
    end

    local currencies = C_QuestLog and C_QuestLog.GetQuestRewardCurrencies
                       and C_QuestLog.GetQuestRewardCurrencies(questID)
    for i = 1, (currencies and #currencies or 0) do
        local c = currencies[i]
        if c and c.name then
            local e = push("currency")
            e.name  = c.name
            e.count = c.totalRewardAmount
        end
    end

    return lines
end
