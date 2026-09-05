local _, ns = ...

local Bonus = ns:RegisterModule("ScenarioBonus", {})
local L     = ns.L

-- Midnight can hand back "secret values" that error when matched by tainted addon code,
-- even though they still report type "string"
local _issecret = _G.issecretvalue

local REFRESH_DEBOUNCE = 0.25
local DELVE_DIFFICULTY = 208

-- Delves expose no scenario bonus steps, so these vignette, spell and aura IDs stand in for
-- them. They churn every season, so they are the first thing to check when a delve tracks
-- nothing - read them back with /eqot bonushud.
-- One vignette per REMAINING pack, gone when that pack dies. Each season adds a NEW id and
-- the older delves still spawn theirs, so APPEND, never replace - a single id here is what
-- left this HUD blank for a whole season. Everything Delves carries the same list.
local NEMESIS_PACK_VIGNETTES = {
    7531,  -- Season 1, "Nullaeus' Minions"
    7869,  -- Season 2, "Ula'tek's Chosen", confirmed live 2026-08-21
}
local RAGER_NAME_MATCH       = "voidfused"
local BANNER_INTERACT_SPELLS = { [1269411] = true, [1269412] = true, [1269416] = true }
local BANNER_BUFFS = {
    1271918, 1271945, 1272609, 1272666, 1272756, 1272769,
    1272809, 1272810, 1272813, 1272814, 1273058, 1273066,
}
local BANNER_RANK = { announced = 1, clicked = 2, buffed = 3, eliteUp = 4, grand = 5 }

local MSG_EVENTS = {
    "CHAT_MSG_RAID_BOSS_EMOTE", "CHAT_MSG_MONSTER_YELL",
    "CHAT_MSG_MONSTER_EMOTE",   "CHAT_MSG_MONSTER_SAY",
    "UI_INFO_MESSAGE",          "CHAT_MSG_SYSTEM",
}
local VIGNETTE_EVENTS = { "VIGNETTE_MINIMAP_UPDATED", "VIGNETTES_UPDATED" }

local bannerState, ragerGUID
local nemesisSeen, nemesisSeenCount, nemesisRemaining = {}, 0, nil
local trackedDelve, delveTier
local runDeaths = 0
local packsKilledBase = 0
local vignetteMisses = 0

-- Only a backstop for a client crash. LEAVING a delve clears the record outright, so a saved
-- one means the player never left, which is what makes a reload the only thing that resumes.
local RESUME_MAX_AGE = 3 * 60 * 60

-- char.delveRun is an ABSENCE FLAG and is deliberately NOT in DB.defaults, the same reason
-- char.trackedQuests is not: absent means no run is in progress, and a default would have
-- AceDB invent one for every character.
local function charScope()
    local DB = ns:GetModule("DB")
    return DB and DB:Char()
end

local function clearSavedRun()
    local char = charScope()
    if char then char.delveRun = nil end
end

-- Kills are INFERRED from packs going away, which is why an empty vignette list has to be
-- refused in scanVignettes: a flushed one reads here as every pack dead, not as zero.
local function packsKilledNow()
    return packsKilledBase + math.max(0, nemesisSeenCount - (nemesisRemaining or 0))
end

-- Deliberately not ratcheted with math.max: an inferred count corrects DOWNWARDS when a
-- vignette that would not resolve comes back, and a max would hold that wrong reading all run.
-- Gated on Enabled because checkRun runs for every player who enters a delve and this HUD
-- ships off, so an ungated write lands a saved variable on people who never turned it on.
local function persistRun()
    if not Bonus:Enabled() then return end
    local char = charScope()
    if not (char and trackedDelve) then return end
    local r = char.delveRun
    if not (r and r.name == trackedDelve) then
        r = { name = trackedDelve }
        char.delveRun = r
    end
    r.at          = time()
    r.deaths      = runDeaths
    r.packsKilled = packsKilledNow()
end
local delveEventsOn = false

local model, stepPool, critPool = {}, {}, {}
local dirtyFns = {}

local function state()
    local DB = ns:GetModule("DB")
    local t  = DB and DB:Tracker()
    if not t then return nil end
    t.scenarioBonusHUD = t.scenarioBonusHUD or {}
    return t.scenarioBonusHUD
end

function Bonus:Enabled()
    local st = state()
    return (st and st.enabled == true) or false
end

local function playerInDelve()
    if not GetInstanceInfo then return false end
    local _, _, diffID = GetInstanceInfo()
    return diffID == DELVE_DIFFICULTY
end

function Bonus:InDelve() return playerInDelve() end

function Bonus:OnDirty(fn)
    if fn then dirtyFns[#dirtyFns + 1] = fn end
end

local function notifyDirty()
    for i = 1, #dirtyFns do
        local ok, err = pcall(dirtyFns[i])
        if not ok then geterrorhandler()(err) end
    end
end

function Bonus:QueueRefresh()
    if not self:Enabled() then return end
    ns:GetModule("Events"):Debounce("eqot.scenariobonus", REFRESH_DEBOUNCE, notifyDirty)
end

local function resetModel()
    for i = #model, 1, -1 do
        local step = model[i]
        local crit = step.criteria
        for c = #crit, 1, -1 do
            critPool[#critPool + 1] = crit[c]
            crit[c] = nil
        end
        stepPool[#stepPool + 1] = step
        model[i] = nil
    end
end

local function pushStep(name, rewardQuestID, rewardIcon)
    local step = tremove(stepPool) or { criteria = {} }
    step.name          = name
    step.rewardQuestID = rewardQuestID
    step.rewardIcon    = rewardIcon
    model[#model + 1]  = step
    return step
end

-- kind is nil for an ordinary objective and "stat" for a run readout, which UI draws with no
-- check icon. Always assigned, never left over: these tables come from a pool.
local function pushCriterion(step, text, completed, kind)
    local c = tremove(critPool) or {}
    c.text, c.completed, c.kind = text, completed, kind
    step.criteria[#step.criteria + 1] = c
end

-- Reward data streams in, so a nil icon here is a not-yet rather than a never. The renderer
-- falls back to a generic chest and the next refresh picks up the real one.
local function rewardIconFor(questID)
    if not (questID and questID ~= 0) then return nil end
    if HaveQuestRewardData and not HaveQuestRewardData(questID)
       and C_TaskQuest and C_TaskQuest.RequestPreloadRewardData then
        C_TaskQuest.RequestPreloadRewardData(questID)
    end
    if not GetQuestLogRewardInfo then return nil end
    local _, texture = GetQuestLogRewardInfo(1, questID)
    return texture
end

local function gatherScenarioSteps()
    if not (C_Scenario and C_Scenario.GetBonusSteps and C_ScenarioInfo
            and C_ScenarioInfo.GetCriteriaInfoByStep) then return false end
    local steps = C_Scenario.GetBonusSteps()
    if not (steps and #steps > 0) then return false end

    for i = 1, #steps do
        local idx = steps[i]
        local name, description, numCriteria, _, _, _, shouldShow = C_Scenario.GetStepInfo(idx)
        if shouldShow then
            local rewardQuestID = C_Scenario.GetBonusStepRewardQuestID
                                  and C_Scenario.GetBonusStepRewardQuestID(idx)
            local step = pushStep((name and name ~= "" and name) or description or "",
                                  rewardQuestID, rewardIconFor(rewardQuestID))
            for c = 1, (numCriteria or 0) do
                local info = C_ScenarioInfo.GetCriteriaInfoByStep(idx, c)
                if info then
                    local desc  = info.description or ""
                    local label = desc
                    if not info.isFormatted and not info.completed
                       and info.totalQuantity and info.totalQuantity > 0 then
                        label = ("%d/%d %s"):format(info.quantity or 0, info.totalQuantity, desc)
                    end
                    pushCriterion(step, label, info.completed and true or false)
                end
            end
        end
    end
    return #model > 0
end

-- Matches Data/Widgets.lua, which reads tierText off this same widget: a secret value reports
-- a real type and raises the moment it is used, so it has to be filtered rather than tested for.
local function plain(v)
    if v == nil then return nil end
    if _issecret and _issecret(v) then return nil end
    return v
end

-- The delve header widget carries the tier AND the lives, so both readers share this walk.
local function findDelveHeader()
    if not (C_ScenarioInfo and C_ScenarioInfo.GetScenarioStepInfo
            and C_UIWidgetManager and C_UIWidgetManager.GetAllWidgetsBySetID) then return nil end
    local stepInfo = C_ScenarioInfo.GetScenarioStepInfo()
    if not (stepInfo and stepInfo.widgetSetID) then return nil end
    local VT     = Enum and Enum.UIWidgetVisualizationType
    local getter = C_UIWidgetManager.GetScenarioHeaderDelvesWidgetVisualizationInfo
    if not (VT and VT.ScenarioHeaderDelves and getter) then return nil end
    local widgets = C_UIWidgetManager.GetAllWidgetsBySetID(stepInfo.widgetSetID)
    if type(widgets) ~= "table" then return nil end
    for _, w in ipairs(widgets) do
        if w.widgetType == VT.ScenarioHeaderDelves then
            local hv = getter(w.widgetID)
            if hv then return hv end
        end
    end
    return nil
end

-- readTier's callers do not protect it and it runs BEFORE the guarded lives read, so a raise
-- anywhere in the shared walk cost the whole delve model rather than one line - and permanently,
-- because the statement that caches delveTier is the one that died. The widgetType test is the
-- vector: a secret value raises when it is COMPARED.
local function delveHeader()
    local ok, hv = pcall(findDelveHeader)
    return ok and hv or nil
end

local function readTier()
    local hv = delveHeader()
    return hv and tonumber(plain(hv.tierText)) or nil
end

-- Lives remaining, measured 2026-09-05 in a tier 7 delve: currencies[1].text read 5, then 4
-- after one death, with that entry's tooltip moving from "Total deaths: 0" to "Total deaths: 1".
-- The tooltip is deliberately NOT parsed - it is localized, which is the English-only defect the
-- frame-scraping reader this replaced was rewritten to remove. runDeaths below stays this addon's
-- own count.
-- tonumber rather than a truth test: an empty string is a real answer meaning the widget drew no
-- number, and it must read as no lives rather than as zero lives.
local function readLives()
    local hv = delveHeader()
    local c  = hv and type(hv.currencies) == "table" and hv.currencies[1]
    return c and tonumber(plain(c.text)) or nil
end

local function setBannerState(s)
    if not BANNER_RANK[s] then return end
    if bannerState and BANNER_RANK[s] <= BANNER_RANK[bannerState] then return end
    bannerState = s
    Bonus:QueueRefresh()
end

-- A vignette GUID is Vignette-0-<server>-<instance>-<zone>-<id>-<spawn>, so field six is the
-- id, the slot an npc id occupies on a creature GUID. This is the ONLY handle on a vignette
-- whose GetVignetteInfo will not resolve. Matched with a pattern rather than strsplit so it
-- needs no WoW global and can be tested outright.
-- Used by the dump ONLY. It deliberately does NOT feed the pack count: the dedupe key there
-- is objectGUID, which an unreadable vignette does not have, and the vignette GUID itself
-- regenerates - which is the double-counting bug this feature already had once.
local function guidVignetteID(guid)
    if type(guid) ~= "string" then return nil end
    return tonumber(guid:match("^Vignette%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
end

-- Hoisted so ONE pcall covers the whole read: a secret value errors when MATCHED, so find
-- raises as readily as lower and a guard around lower alone never sees it.
local function bannerNameHit(name)
    local ln = string.lower(name)
    if type(ln) ~= "string" or ln == "" then return nil end
    if ln:find(RAGER_NAME_MATCH, 1, true)    then return "eliteUp"   end
    if ln:find("grand sanctified", 1, true)  then return "grand"     end
    if ln:find("sanctified spoils", 1, true) then return "clicked"   end
    if ln:find("sanctified banner", 1, true) then return "announced" end
    return nil
end

-- Compared rather than used as a table key: a Midnight secret value throws on index.
local function isNemesisPack(vignetteID)
    for i = 1, #NEMESIS_PACK_VIGNETTES do
        if vignetteID == NEMESIS_PACK_VIGNETTES[i] then return true end
    end
    return false
end

local function scanVignettes()
    if not playerInDelve() then return end
    if not (C_VignetteInfo and C_VignetteInfo.GetVignettes) then return end
    local ok, vigs = pcall(C_VignetteInfo.GetVignettes)
    if not (ok and type(vigs) == "table") then return end

    local ragerSeen, packCount, listed = false, 0, 0
    local misses = 0
    -- Counted rather than ipairs: a nil hole stops ipairs dead, and everything after it -
    -- the banner included - would never be looked at. A vignette that will not resolve is
    -- counted instead of dropped, because a silent drop is how a missing banner hides.
    for i = 1, #vigs do
        local vguid = vigs[i]
        local ok2, v
        if vguid then
            listed = listed + 1
            ok2, v = pcall(C_VignetteInfo.GetVignetteInfo, vguid)
        end
        if not (ok2 and v) then misses = misses + 1 end
        if ok2 and v then
            if isNemesisPack(v.vignetteID) then
                packCount = packCount + 1
                local key = v.objectGUID
                if key and not nemesisSeen[key] then
                    nemesisSeen[key]  = true
                    nemesisSeenCount = nemesisSeenCount + 1
                end
            end
            -- Per vignette, not by the caller's pcall, which would lose every vignette after
            -- the bad one - packs included.
            local okName, hit = pcall(bannerNameHit, v.name)
            if okName and hit then
                -- eliteUp is only ever the rager, and the despawn test below reads its GUID.
                if hit == "eliteUp" then ragerSeen, ragerGUID = true, vguid end
                setBannerState(hit)
            end
        end
    end
    -- Same empty-list rule as the pack count below: a rager gone only because nothing was
    -- scanned has not been killed, and setBannerState only ever raises, so this would stand.
    if listed > 0 and ragerGUID and not ragerSeen and bannerState == "eliteUp" then
        setBannerState("grand")
    end
    -- An EMPTY list is a loading screen, not a cleared delve, and taking it as a reading
    -- reports every pack dead at once. A delve draws its own exit vignette, so anything at all
    -- in the list makes this a real reading.
    if listed > 0 then nemesisRemaining = packCount end
    vignetteMisses   = misses
    persistRun()
end

local function onUnitAura(_, unit)
    if unit ~= "player" then return end
    if not playerInDelve() then return end
    if bannerState and BANNER_RANK[bannerState] >= BANNER_RANK.buffed then return end
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return end
    for _, sid in ipairs(BANNER_BUFFS) do
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, sid)
        if ok and aura then setBannerState("buffed"); return end
    end
    for sid in pairs(BANNER_INTERACT_SPELLS) do
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, sid)
        if ok and aura then setBannerState("clicked"); return end
    end
end

local function onUnitCast(_, unit, _, spellID)
    if unit ~= "player" then return end
    if not (spellID and playerInDelve()) then return end
    if BANNER_INTERACT_SPELLS[spellID] then setBannerState("clicked") end
end

local function onMessage(event, a1, a2)
    if not playerInDelve() then return end
    local text = (event == "UI_INFO_MESSAGE") and a2 or a1
    -- find on a secret value throws, and the vignette scan still catches the banner
    if _issecret and _issecret(text) then return end
    if type(text) ~= "string" or text == "" then return end
    if text:lower():find("sanctified banner", 1, true) then setBannerState("announced") end
end

local function onVignette()
    if not playerInDelve() then return end
    pcall(scanVignettes)
    Bonus:QueueRefresh()
end

local function resetRun()
    delveTier    = nil
    bannerState, ragerGUID = nil, nil
    nemesisRemaining, nemesisSeenCount = nil, 0
    runDeaths    = 0
    packsKilledBase = 0
    vignetteMisses  = 0
    wipe(nemesisSeen)
end

-- Own deaths only. Delve lives are spent by the whole group, so in a party this number and
-- the lives readout above it legitimately disagree - Everything Delves has the same split.
local function onPlayerDead()
    if not playerInDelve() then return end
    runDeaths = runDeaths + 1
    persistRun()
    Bonus:QueueRefresh()
end

-- Reset per-run state on delve change or exit so a new run never inherits the old packs or
-- banner. The exit half has to be driven from a world transition: gatherDelveModel is only
-- ever reached from inside a delve, so it can never observe the player leaving one, and
-- re-entering the same delve would otherwise match trackedDelve and skip the reset.
local function checkRun()
    if not playerInDelve() then
        trackedDelve = nil
        resetRun()
        -- Cleared whether or not THIS session tracked a run: trackedDelve is nil at login, so
        -- behind that guard a player who logged back in outside a delve resumed the old one.
        clearSavedRun()
        return
    end
    local name = (GetInstanceInfo and GetInstanceInfo()) or "delve"
    if name ~= trackedDelve then
        trackedDelve = name
        resetRun()

        local char = charScope()
        local r = char and char.delveRun
        if r and r.name == name and r.at and (time() - r.at) < RESUME_MAX_AGE then
            runDeaths       = r.deaths or 0
            packsKilledBase = r.packsKilled or 0
        else
            clearSavedRun()
        end
        persistRun()
    end
end

local function gatherDelveModel()
    checkRun()
    if not playerInDelve() then return false end
    pcall(scanVignettes)

    local step = pushStep(L["Delve Bonus Loot"], nil, nil)

    -- Read once per run for the pack total below.
    if not delveTier then delveTier = readTier() end

    -- packsKilledBase alone is enough: after a reload every pack may already be dead, so the
    -- live scan sees none and only the restored tally proves the line belongs on screen.
    if nemesisSeenCount > 0 or packsKilledBase > 0 then
        local tier, expected = delveTier or 0, 0
        if     tier >= 10 then expected = 4
        elseif tier >= 8  then expected = 3
        elseif tier >= 6  then expected = 2
        elseif tier >= 4  then expected = 1 end
        local total  = math.max(expected, packsKilledBase + nemesisSeenCount)
        local killed = packsKilledNow()
        pushCriterion(step, (L["Nemesis Strongbox: %d/%d packs"]):format(killed, total),
                      killed >= total)
    end

    if bannerState == "grand" then
        pushCriterion(step, L["Sanctified Banner: Grand Spoils earned"], true)
    elseif bannerState == "buffed" or bannerState == "clicked" then
        pushCriterion(step, L["Sanctified Banner: bonus Spoils secured"], true)
    elseif bannerState == "eliteUp" then
        pushCriterion(step, L["Sanctified Banner: kill the Voidfused Rager"], false)
    elseif bannerState == "announced" then
        pushCriterion(step, L["Sanctified Banner: find it for bonus loot"], false)
    end

    -- pcall'd for the currencies index, which delveHeader's own guard does not cover: a throw
    -- must cost the Lives half of one line rather than the whole run readout. Concatenated
    -- rather than formatted because a stray percent in a translation would make string.format
    -- raise here.
    local okLives, lives = pcall(readLives)
    local stat = L["Deaths:"] .. " " .. runDeaths
    if okLives and lives then stat = L["Lives:"] .. " " .. lives .. "   " .. stat end
    pushCriterion(step, stat, false, "stat")

    return true
end

-- The unit events are the expensive half, so they are held only while a delve is actually
-- being tracked. UNIT_AURA is filtered to the player in the handler rather than through
-- RegisterUnitEvent, since the shared event frame registers by name.
local function setDelveEvents(on)
    if on == delveEventsOn then return end
    delveEventsOn = on
    local Events = ns:GetModule("Events")
    local bind = on and Events.On or Events.Off
    bind(Events, "UNIT_AURA", onUnitAura)
    bind(Events, "UNIT_SPELLCAST_SUCCEEDED", onUnitCast)
    bind(Events, "PLAYER_DEAD", onPlayerDead)
    for i = 1, #MSG_EVENTS      do bind(Events, MSG_EVENTS[i], onMessage) end
    for i = 1, #VIGNETTE_EVENTS do bind(Events, VIGNETTE_EVENTS[i], onVignette) end
end

function Bonus:Reconcile()
    setDelveEvents(self:Enabled() and playerInDelve())
end

-- Entries are valid only until the next call, exactly as a provider's are.
function Bonus:GetModel()
    resetModel()
    if not self:Enabled() then return nil end
    local any
    if playerInDelve() then
        any = gatherDelveModel()
    else
        any = gatherScenarioSteps()
    end
    return any and model or nil
end

function Bonus:DebugLine()
    return ("source=%s banner=%s packs seen %d remaining %s tier=%s"):format(
        playerInDelve() and "delve" or "scenario",
        tostring(bannerState), nemesisSeenCount,
        tostring(nemesisRemaining), tostring(delveTier))
end

-- Built through ONE pcall by the caller: every value here can be one that throws, and guarding
-- the name alone was defeated by the vignetteID beside it in the same argument list.
-- The PACK marker is the point - a season that moves the id shows up as vignettes with no
-- marker - and an unreadable vignette is named rather than dropped, because a count of 5 above
-- a list of 4 is how the one that mattered stayed invisible.
local function vignetteDumpLine(i, guid, v)
    local gid = guidVignetteID(guid)
    if not v then
        return ("  vig [%d] UNREADABLE guid id=%s%s guid=%s"):format(
            i, tostring(gid), isNemesisPack(gid) and " PACK" or "", tostring(guid))
    end
    return ("  vig id=%s (guid id %s)%s name=%s"):format(
        tostring(v.vignetteID), tostring(gid),
        isNemesisPack(v.vignetteID) and " PACK" or "", tostring(v.name))
end

function Bonus:DumpLines(out)
    -- lives=nil is the reading only a delve run can produce, and it separates the two ways
    -- this can go quiet: the widget carried no number, or the read threw.
    out[#out + 1] = ("enabled=%s inDelve=%s tier=%s banner=%s nemesisSeen=%d remaining=%s")
        :format(tostring(self:Enabled()), tostring(playerInDelve()), tostring(readTier()),
                tostring(bannerState), nemesisSeenCount, tostring(nemesisRemaining))
    local okL, lv = pcall(readLives)
    out[#out + 1] = ("lives=%s deaths=%d packsKilled=%d (restored %d) | "
        .. "vignettes the scan could not read: %d")
        :format(okL and tostring(lv) or "read threw", runDeaths,
                packsKilledNow(), packsKilledBase, vignetteMisses)

    if GetInstanceInfo then
        local _, itype, diffID = GetInstanceInfo()
        out[#out + 1] = ("instance: type=%s difficultyID=%s (208=Delve)")
            :format(tostring(itype), tostring(diffID))
    end

    if C_Scenario and C_Scenario.GetStepInfo then
        local sname, _, ncrit = C_Scenario.GetStepInfo()
        out[#out + 1] = ("current step: name=%s numCriteria=%s")
            :format(tostring(sname), tostring(ncrit))
        if C_ScenarioInfo and C_ScenarioInfo.GetCriteriaInfo then
            for i = 1, math.min(ncrit or 0, 10) do
                local info = C_ScenarioInfo.GetCriteriaInfo(i)
                if info then
                    out[#out + 1] = ("  mainCrit[%d] %s done=%s %s/%s"):format(i,
                        tostring(info.description), tostring(info.completed),
                        tostring(info.quantity), tostring(info.totalQuantity))
                end
            end
        end
    end

    local steps = C_Scenario and C_Scenario.GetBonusSteps and C_Scenario.GetBonusSteps()
    out[#out + 1] = "GetBonusSteps count=" .. tostring(steps and #steps or "nil")

    out[#out + 1] = "pack vignette ids matched: "
        .. table.concat(NEMESIS_PACK_VIGNETTES, ", ")

    if C_VignetteInfo and C_VignetteInfo.GetVignettes then
        local ok, vigs = pcall(C_VignetteInfo.GetVignettes)
        out[#out + 1] = "vignettes=" .. tostring(ok and type(vigs) == "table" and #vigs or "nil")
        if ok and type(vigs) == "table" then
            for i = 1, #vigs do
                local g = vigs[i]
                local ok2, v
                if g then ok2, v = pcall(C_VignetteInfo.GetVignetteInfo, g) end
                local okLine, line = pcall(vignetteDumpLine, i, g, ok2 and v or nil)
                out[#out + 1] = okLine and line
                    or ("  vig [%d] holds values that will not print"):format(i)
            end
        end
    end
    return out
end

function Bonus:OnEnable()
    -- A CAPABILITY probe, so it reads true on Classic where the functions are hollow stubs and
    -- this does NOT return. Events:On pcalls each registration and records the refusal, which is
    -- what actually absorbs ACTIVE_DELVE_DATA_UPDATE there - see the events: line in /eqot
    -- status. This gate only covers a client missing the functions outright.
    if not ns.Has.ScenarioBonus then return end
    local Events = ns:GetModule("Events")
    local function refresh()
        Bonus:Reconcile()
        Bonus:QueueRefresh()
    end
    -- Only the world transitions test for an exit, which now clears the SAVED run too. A
    -- criteria update fires all run, so a momentarily stale "not in a delve" would wipe both.
    local function worldChanged()
        checkRun()
        refresh()
    end
    Events:On("SCENARIO_UPDATE",                     refresh)
    Events:On("SCENARIO_CRITERIA_UPDATE",            refresh)
    Events:On("SCENARIO_CRITERIA_SHOW_STATE_UPDATE", refresh)
    Events:On("SCENARIO_COMPLETED",                  refresh)
    Events:On("ACTIVE_DELVE_DATA_UPDATE",            refresh)
    Events:On("PLAYER_ENTERING_WORLD",               worldChanged)
    Events:On("ZONE_CHANGED_NEW_AREA",               worldChanged)
    self:Reconcile()
end
