local _, ns = ...

local Entry    = ns:GetModule("Entry")
local Registry = ns:GetModule("Registry")
local L        = ns.L

local ICON = Entry.ICON

local Professions = {
    id       = "professions",
    -- Section id matches EQ's so an imported sectionOrder lands on the right run
    groups   = { "profession" },
    priority = 30,
    tags     = {},
}

local ICON_CROP = { 0.08, 0.92, 0.08, 0.92 }

local BASIC_REAGENT = (Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic) or 0

local REAGENT_FMT = PROFESSIONS_TRACKER_REAGENT_FORMAT or "%s %s"
local COUNT_FMT   = PROFESSIONS_TRACKER_REAGENT_COUNT_FORMAT or "%d/%d"
local RANGE_FMT   = PROFESSIONS_TRACKER_REAGENT_RANGE_FORMAT or "%d-%d"

-- GetRecipesTracked's only argument is isRecraft and the same recipeID appears in both
-- lists, so identity is the pair, never the id alone.
local IS_RECRAFT = { false, true }

local function entryKey(recipeID, isRecraft)
    return (isRecraft and "R" or "N") .. tostring(recipeID)
end

local store = Entry.NewStore({
    groupID   = "profession",
    icon      = { kind = ICON.TEXTURE, texCoord = ICON_CROP },
    payload   = {},
    isTracked = true,
})

local recipes = {}

local function collectTracked()
    wipe(recipes)
    if not ns.Has.TrackedRecipes then return recipes end
    local seen = {}
    for _, isRecraft in ipairs(IS_RECRAFT) do
        local list = C_TradeSkillUI.GetRecipesTracked(isRecraft)
        for i = 1, (list and #list or 0) do
            local item = list[i]
            local rid  = (type(item) == "table") and item.recipeID or item
            local key  = rid and entryKey(rid, isRecraft)
            if rid and not seen[key] then
                seen[key] = true
                recipes[#recipes + 1] = { recipeID = rid, isRecraft = isRecraft }
            end
        end
    end
    return recipes
end

local function slotRequired(slot)
    if ProfessionsUtil and ProfessionsUtil.IsReagentSlotRequired then
        return ProfessionsUtil.IsReagentSlotRequired(slot)
    end
    return slot.reagentType == BASIC_REAGENT
end

local function slotModifying(slot)
    if ProfessionsUtil and ProfessionsUtil.IsReagentSlotModifyingRequired then
        return ProfessionsUtil.IsReagentSlotModifyingRequired(slot)
    end
    return false
end

local function slotQuantityRequired(slot, reagent)
    if slot.GetQuantityRequired then
        local ok, n = pcall(slot.GetQuantityRequired, slot, reagent)
        if ok and n then return n end
    end
    return slot.quantityRequired or 0
end

-- The slot list is static per recipe and GetRecipeSchematic allocates fresh multi-KB
-- tables, so the extracted entries are cached. Counts and names still resolve per render.
local reagentCache = {}

local function getReagents(recipeID, isRecraft)
    local key    = entryKey(recipeID, isRecraft)
    local cached = reagentCache[key]
    if cached then return cached end

    local getSchematic = (ProfessionsUtil and ProfessionsUtil.GetRecipeSchematic)
                      or (C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic)
    if not getSchematic then return {} end
    local ok, schematic = pcall(getSchematic, recipeID, isRecraft and true or false)
    -- Returning uncached is load-bearing: a schematic that has not streamed in yet must
    -- retry, and caching its empty list would blank that recipe for the whole session.
    if not ok or not schematic or not schematic.reagentSlotSchematics then return {} end

    local out = {}
    for i = 1, #schematic.reagentSlotSchematics do
        local slot    = schematic.reagentSlotSchematics[i]
        local reagent = slot and slot.reagents and slot.reagents[1]
        if reagent and slotRequired(slot) then
            local isModifying = slotModifying(slot)
            local e = {
                reagents   = slot.reagents,
                need       = slotQuantityRequired(slot, reagent),
                itemID     = (not isModifying) and reagent.itemID or nil,
                currencyID = (not isModifying) and reagent.currencyID or nil,
                slotText   = isModifying and slot.slotInfo and slot.slotInfo.slotText or nil,
            }
            if slot.IsVariableQuantityReagent and slot.GetVariableQuantityRange
               and slot:IsVariableQuantityReagent(reagent) then
                e.varMin, e.varMax = slot:GetVariableQuantityRange(reagent)
            end
            if (e.slotText or e.itemID or e.currencyID) and (e.need > 0 or e.varMin) then
                -- Blizzard orders modifying-required slots ahead of the basic ones
                tinsert(out, isModifying and 1 or #out + 1, e)
            end
        end
    end
    reagentCache[key] = out
    return out
end

-- Sums every quality tier under the game's own bank and warband rules, so a stack of
-- nothing but rank-2 or rank-3 still counts. Reading reagents[1] alone reports zero.
local function reagentHave(e)
    if ProfessionsUtil and ProfessionsUtil.AccumulateReagentsInPossession and e.reagents then
        -- Raises on a currency that answers nothing or a tier with no id, and nothing between here
        -- and Tracker:Render catches it, so one recipe would stop the whole tracker drawing.
        local ok, have = pcall(ProfessionsUtil.AccumulateReagentsInPossession, e.reagents)
        if ok then return have or 0 end
    end
    if e.currencyID and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local info = C_CurrencyInfo.GetCurrencyInfo(e.currencyID)
        return (info and info.quantity) or 0
    end
    if e.itemID and C_Item and C_Item.GetItemCount then
        return C_Item.GetItemCount(e.itemID, true, false, true, true) or 0
    end
    return 0
end

local function reagentName(e)
    if e.slotText then return e.slotText end
    if e.currencyID and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local info = C_CurrencyInfo.GetCurrencyInfo(e.currencyID)
        if info and info.name then return info.name end
    end
    if e.itemID then
        if C_Item and C_Item.GetItemNameByID then
            local n = C_Item.GetItemNameByID(e.itemID)
            if n then return n end
        end
        return "Item " .. tostring(e.itemID)
    end
    return ""
end

local function fillLines(e, recipeID, isRecraft)
    Entry.BeginLines(e)
    local list = getReagents(recipeID, isRecraft)
    local met, total = 0, 0
    for i = 1, #list do
        local rg = list[i]
        local nm = reagentName(rg)
        local ln = Entry.PushLine(e)
        total = total + 1
        if rg.varMin then
            -- A variable-quantity slot depends on crafting-form choices that cannot be
            -- read, so it shows its range and is never counted as satisfied.
            ln.text      = format(REAGENT_FMT, format(RANGE_FMT, rg.varMin, rg.varMax), nm)
            ln.completed = false
        else
            local have = reagentHave(rg)
            ln.text      = format(REAGENT_FMT, format(COUNT_FMT, have, rg.need), nm)
            ln.completed = have >= rg.need
            ln.current, ln.required = have, rg.need
            if ln.completed then met = met + 1 end
        end
    end
    Entry.EndLines(e)
    return met, total
end

local function recipeLabel(name, isRecraft)
    if not isRecraft then return name end
    if PROFESSIONS_CRAFTING_FORM_RECRAFTING_HEADER then
        return PROFESSIONS_CRAFTING_FORM_RECRAFTING_HEADER:format(name)
    end
    return L["%s (Recraft)"]:format(name)
end

function Professions:IsAvailable()
    return ns.Has.TrackedRecipes and ns.Has.RecipeSchematic
end

function Professions:GetEntries()
    local tracked = collectTracked()

    store:Begin()
    for i = 1, #tracked do
        local r    = tracked[i]
        local info = C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(r.recipeID)
        local name = (info and info.name) or ("Recipe " .. tostring(r.recipeID))

        local e = store:Acquire(entryKey(r.recipeID, r.isRecraft))
        e.title = recipeLabel(name, r.isRecraft)
        e.icon.texture = (info and info.icon) or nil
        e.payload.recipeID  = r.recipeID
        e.payload.isRecraft = r.isRecraft
        fillLines(e, r.recipeID, r.isRecraft)
    end
    return store:Finish()
end

function Professions:OnEntryClick(entry, button)
    local p = entry.payload
    if not (p and p.recipeID and C_TradeSkillUI) then return end
    if button == "RightButton" then
        if C_TradeSkillUI.SetRecipeTracked then
            -- Argument 3 is a required boolean, and nil raises "bad argument #3"
            C_TradeSkillUI.SetRecipeTracked(p.recipeID, false, p.isRecraft and true or false)
        end
        return
    end
    if C_TradeSkillUI.OpenRecipe then C_TradeSkillUI.OpenRecipe(p.recipeID) end
end

function Professions:OnEntryTooltip(entry, tooltip)
    tooltip:AddLine(entry.title, 1, 0.82, 0)
    tooltip:AddLine(" ")
    tooltip:AddLine(L["Left-click to open the recipe, right-click to untrack."], 0.5, 0.5, 0.5)
end

function Professions:DebugLine()
    local hasUtil = ProfessionsUtil ~= nil
    return ("ProfessionsUtil %s, accumulate %s, cached schematics %d"):format(
        tostring(hasUtil),
        tostring(hasUtil and ProfessionsUtil.AccumulateReagentsInPossession ~= nil),
        (function() local n = 0 for _ in pairs(reagentCache) do n = n + 1 end return n end)())
end

function Professions:Enable(notifyDirty)
    local Events = ns:GetModule("Events")

    local function recipesChanged()
        wipe(reagentCache)
        collectTracked()
        notifyDirty()
    end

    Events:On("TRACKED_RECIPE_UPDATE",   recipesChanged)
    Events:On("TRADE_SKILL_LIST_UPDATE", recipesChanged)
    Events:On("PLAYER_ENTERING_WORLD",   recipesChanged)
    -- Bag and currency traffic is constant, so only repaint when a tracked recipe could care
    local function reagentsMoved()
        if #recipes > 0 then notifyDirty() end
    end
    Events:On("BAG_UPDATE_DELAYED",      reagentsMoved)
    Events:On("CURRENCY_DISPLAY_UPDATE", reagentsMoved)
end

Registry:Register(Professions)
