local _, ns = ...

local Migrate = ns:RegisterModule("Migrate", {})
local L       = ns.L

Migrate.CURRENT_SCHEMA = 1

-- Gated per profile rather than on the account-wide schemaVersion: the offsets it rewrites
-- live under profile.tracker, so an account stamp would leave every other profile
-- unconverted. Runs before Tracker:BuildFrame, which reads the offsets.
local function normalizeTrackerPosition(db)
    local t = db and db.profile and db.profile.tracker
    if not t or t.positionInScreenUnits then return end

    local s = t.scale or 1
    if s > 0 and s ~= 1 then
        t.xOffset = math.floor((t.xOffset or 0) * s + 0.5)
        t.yOffset = math.floor((t.yOffset or 0) * s + 0.5)
    end
    t.positionInScreenUnits = true
end

-- Keys whose name and meaning are identical on both sides. EQOT's defaults match EQ's value
-- for value, and AceDB strips defaults at logout, so whatever survives in EQ's saved variables
-- IS the user's deviation - copying it onto EQOT's defaults reproduces their tracker without
-- needing to reason about defaults at all.
-- Two keys deliberately no longer match EQ: autoListZoneWorldQuests defaults to true here and
-- worldQuestsHeight to 200. An EQ user who left either alone therefore gets EQOT's value, not
-- EQ's, which is the intent - EQ's tracker no longer exists to be reproduced faithfully.
local TRACKER_KEYS = {
    "anchor", "relativePoint", "xOffset", "yOffset", "width", "maxHeight", "scale",
    "simplifyMode", "sortMode", "manualOrder", "showOnlyWatched",
    "showBackground", "backgroundColor", "showBorder", "borderColor", "borderSize",
    "font", "fontSize", "fontOutline", "titleSizeDelta",
    "textShadow", "textShadowColor", "textShadowStrength",
    "scenarioTextShadow", "scenarioTextShadowColor", "scenarioTextShadowStrength",
    "scenarioTextAlign", "scenarioTextSizeDelta", "scenarioFontSize",
    "colorByDifficulty", "showItemButtons", "showQuestPopups",
    "questSoundEnabled", "questCompleteSound",
    "showZoneTag", "showObjectiveNumbers", "showQuestTotal",
    "showLevelInTracker", "showQuestID", "showRecentlyAddedTag", "showOptionsIcon",
    "splitQuestClick",
    "titleColorOverride", "titleColorUseClass", "overrideCompleteGreen",
    "headerColor", "headerColorUseClass", "headerDividerColor", "headerSizeDelta",
    "headerBar", "headerBarColor", "headerBarHeight", "headerBarStyle",
    "headerBarSoftEdges", "headerBarSoftEdgeStrength",
    "blockSpacing", "lineSpacing", "headerSpacing",
    "blockLayout", "cardColor", "cardBorderColor", "cardBorderSize", "cardPadding",
    "cardTintByType", "cardTintCampaign", "cardTintLegendary", "cardTintDungeon",
    "cardTintRaid",
    "scrollBarBg", "scrollBarBgColor", "hideScrollBar", "skinScrollBar",
    "scrollBarThumbColor", "scrollBarThumbWidth", "hideScrollArrows",
    "worldQuestsPosition", "autoListZoneWorldQuests", "worldQuestsPinnedMaxFraction",
    "worldQuestsHeightOverride", "worldQuestsHeight",
    "showZoneProgressBar", "zoneProgressLocation",
}

local GENERAL_KEYS = {
    "lockTracker", "hideInCombat", "hideInInstances", "hideOnMapOpen", "hideInMythicPlus",
    "autoTrackAccepted", "restoreSuperTrackOnLogin",
}

-- showBonus is EQOT-only, so it keeps its own default rather than being invented here.
local FILTER_KEYS = {
    "showNormal", "showDaily", "showWeekly", "showCampaign", "showWorld", "onlyCurrentZone",
}

local FRAME_KEYS = { "point", "relPoint", "locked", "showBorder", "showBackground" }

-- EQ writes these to the identical zoneProgressBar sub-table, so they copy by name.
-- backgroundColor is absent because it is EQOT-only, with no EQ counterpart to carry.
local ZONE_BAR_STYLE_KEYS = {
    "barTexture", "barColor", "borderColor", "headerColor", "countColor", "font",
}

local SECTION_VISIBILITY = {
    showProfessionSection   = "profession",
    showAchievementsSection = "achievements",
    showWorldQuestsSection  = "worldquests",
}

-- EQ's own default, needed verbatim: AceDB strips array indices that match the default, so a
-- saved order arrives as a SPARSE fragment and a hole means "EQ's default at this index".
local EQ_SECTION_ORDER = {
    "zoneprogress", "campaign", "quests", "profession", "endeavors", "achievements",
}
local SECTION_SCAN = 20

local function copyValue(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, sub in pairs(v) do out[k] = copyValue(sub) end
    return out
end

-- Never probe for an EQ addon table: EQ declares a dependency on EQOT, so EQOT loads first
-- and any EQ namespace would always be nil here. The saved variable is the only source.
local function eqProfile()
    local sv = _G.EverythingQuestsDB
    if type(sv) ~= "table" or type(sv.profiles) ~= "table" then return nil end

    local name
    if type(sv.profileKeys) == "table" and UnitName and GetRealmName then
        local char, realm = UnitName("player"), GetRealmName()
        if char and realm then name = sv.profileKeys[char .. " - " .. realm] end
    end

    return (name and sv.profiles[name]) or sv.profiles["Default"]
end

local function eqGlobal()
    local sv = _G.EverythingQuestsDB
    if type(sv) ~= "table" or type(sv.global) ~= "table" then return nil end
    return sv.global
end

-- Not an AceDB scope: EQ assigns DB.char straight to this per-character saved variable and
-- seeds it with CopyTable, so unlike the profile nothing is stripped at logout. That only
-- matters for scalars - every table imported below defaults to empty, so a non-empty one is
-- always the player's own doing.
local function eqChar()
    local sv = _G.EverythingQuestsCharDB
    return (type(sv) == "table") and sv or nil
end

-- EQ keys pinned by bare quest ID. EQOT keys it by provider first so two providers can never
-- collide on the same number, and quests is the only provider EQ could have been talking about.
-- EQ's own "hidden" set is deliberately NOT imported: EQOT has no per-entry hiding to put it in.
local function importIDSet(dst, src, key)
    if type(src[key]) ~= "table" then return 0 end
    local n = 0
    for id, on in pairs(src[key]) do
        if on and type(id) == "number" then
            dst[key] = dst[key] or {}
            dst[key].quests = dst[key].quests or {}
            dst[key].quests[id] = true
            n = n + 1
        end
    end
    return n
end

-- EQ calls the world quest section "events" where EQOT calls it "worldquests". Every other
-- section id is already identical, which is why only this one is listed.
local COLLAPSE_ID = { events = "worldquests" }

local function importChar(db)
    local src = eqChar()
    local dst = db and db.char
    if not (src and dst) then return 0 end

    local n = importIDSet(dst, src, "pinned")

    if type(src.sectionsCollapsed) == "table" then
        for id, on in pairs(src.sectionsCollapsed) do
            if on == true and type(id) == "string" then
                dst.sectionsCollapsed = dst.sectionsCollapsed or {}
                dst.sectionsCollapsed[COLLAPSE_ID[id] or id] = true
                n = n + 1
            end
        end
    end

    if type(src.trackedWorldQuests) == "table" then
        for id, on in pairs(src.trackedWorldQuests) do
            if on and type(id) == "number" then
                dst.trackedWorldQuests = dst.trackedWorldQuests or {}
                dst.trackedWorldQuests[id] = true
                n = n + 1
            end
        end
    end

    return n
end

-- EQ SetPoints these offsets raw and only then scales the frame, so what it stores lives in
-- the frame's own scaled space. EQOT stores UIParent units, so multiply through on the way in.
local function importFrame(dst, src, styleKeys)
    if type(src) ~= "table" or type(dst) ~= "table" then return 0 end

    local n = 0
    for i = 1, #FRAME_KEYS do
        local k = FRAME_KEYS[i]
        if src[k] ~= nil then dst[k] = src[k]; n = n + 1 end
    end
    if styleKeys then
        for i = 1, #styleKeys do
            local k = styleKeys[i]
            if src[k] ~= nil then dst[k] = copyValue(src[k]); n = n + 1 end
        end
    end
    if src.enabled ~= nil then dst.enabled = src.enabled; n = n + 1 end

    local s = src.scale or 1
    if src.scale ~= nil then dst.scale = src.scale; n = n + 1 end
    if src.x then dst.x = src.x * s; n = n + 1 end
    if src.y then dst.y = src.y * s; n = n + 1 end
    return n
end

local function importSectionOrder(t, st)
    if type(st.sectionOrder) ~= "table" then return 0 end

    local seen, order = {}, {}
    for i = 1, SECTION_SCAN do
        local id = st.sectionOrder[i] or EQ_SECTION_ORDER[i]
        if id and not seen[id] then
            seen[id] = true
            order[#order + 1] = id
        end
    end
    t.sectionOrder = order
    return 1
end

-- The tracker offsets are left in EQ's frame-space units on purpose. positionInScreenUnits
-- stays absent, so normalizeTrackerPosition converts them immediately after - which is why
-- this must run before it rather than after.
function Migrate:ImportFromEQ(db)
    local src = eqProfile()
    local p = db and db.profile
    if not (src and p) then return 0 end

    local n = 0
    local st = src.tracker
    if type(st) == "table" then
        local t = p.tracker
        for i = 1, #TRACKER_KEYS do
            local k = TRACKER_KEYS[i]
            if st[k] ~= nil then t[k] = copyValue(st[k]); n = n + 1 end
        end

        if type(st.filters) == "table" then
            t.filters = t.filters or {}
            for i = 1, #FILTER_KEYS do
                local k = FILTER_KEYS[i]
                if st.filters[k] ~= nil then t.filters[k] = st.filters[k]; n = n + 1 end
            end
        end

        n = n + importFrame(t.zoneProgressBar, st.zoneProgressBar, ZONE_BAR_STYLE_KEYS)
        n = n + importFrame(t.scenarioBonusHUD, st.scenarioBonusHUD)
        n = n + importSectionOrder(t, st)

        -- The one semantic translation: EQ's achievements-only flag becomes a per-group table.
        if st.simplifyAchievements ~= nil then
            t.simplifyGroups = t.simplifyGroups or {}
            t.simplifyGroups.achievements = st.simplifyAchievements and true or false
            n = n + 1
        end

        -- EQ stores three "show this section" booleans. EQOT stores the inverse, keyed by
        -- group id, so only an explicit false carries across.
        for eqKey, groupID in pairs(SECTION_VISIBILITY) do
            if st[eqKey] == false then
                t.sectionsHidden = t.sectionsHidden or {}
                t.sectionsHidden[groupID] = true
                n = n + 1
            end
        end
    end

    local sg = src.general
    if type(sg) == "table" then
        local g = p.general
        for i = 1, #GENERAL_KEYS do
            local k = GENERAL_KEYS[i]
            if sg[k] ~= nil then g[k] = copyValue(sg[k]); n = n + 1 end
        end
    end

    -- The only global-scope key the two addons share. Both windows are 1020x720 and both
    -- sliders run 0.7-1.4, so an imported value is always representable.
    local sgl = eqGlobal()
    if db.global and sgl and type(sgl.optionsWindowScale) == "number" then
        db.global.optionsWindowScale = sgl.optionsWindowScale
        n = n + 1
    end

    if db.global then db.global.eqConfigImported = true end
    return n
end

-- Once per character, tracked by its own char-scope flag. force is the manual /eqot importeq
-- path, which is the user explicitly asking for EQ's state again.
function Migrate:ImportCharFromEQ(db, force)
    local char = db and db.char
    if not char then return 0 end
    if char.eqCharImported and not force then return 0 end
    if not self:HasEQConfig() then return 0 end

    local n = importChar(db)
    char.eqCharImported = true
    return n
end

-- Runs once from DB:OnInitialize, never on an AceDB profile change. That is complete only
-- because every profile switch reloads the UI, as EQ's does - a profiles tab that swaps in
-- place would leave the new profile unconverted.
function Migrate:Run(db, isFreshInstall)
    -- Only ever on a first run. An existing profile is somebody's tuned tracker, and a
    -- silent overwrite of it would be indistinguishable from data loss.
    if isFreshInstall and self:HasEQConfig() then
        local n = self:ImportFromEQ(db)
        if n > 0 then
            ns:Print((L["imported %d settings from Everything Quests."]):format(n))
        end
    end

    -- Gated per CHARACTER, not on the fresh-install flag. That flag reads an account-wide
    -- saved variable, while EQ's pins and collapsed sections live in a
    -- per-character one - so keying this off the same flag would import the first character
    -- to log in and silently drop every alt's state.
    self:ImportCharFromEQ(db)

    normalizeTrackerPosition(db)

    local ManualOrder = ns:GetModule("ManualOrder")
    if ManualOrder then ManualOrder:Reconcile() end

    -- Per-entry hiding is gone, so this set has no reader and no writer left. Cleared rather
    -- than left in place because it is per character and nothing would ever empty it again.
    -- Unconditional rather than schema gated: the key is only ever leftover now, so a second
    -- pass finds nothing.
    if db and db.char then db.char.hidden = nil end

    local g = db and db.global
    if not g then return end

    if not g.schemaVersion or g.schemaVersion < 1 then
        g.schemaVersion = 1
    end

    g.schemaVersion = self.CURRENT_SCHEMA
end

function Migrate:HasEQConfig()
    return type(_G.EverythingQuestsDB) == "table"
end

function Migrate:DebugLine()
    local g = ns.db and ns.db.global
    local c = ns.db and ns.db.char
    return ("eq import: config %s, char %s, profile imported %s, char imported %s")
        :format(self:HasEQConfig() and "present" or "absent",
                eqChar() and "present" or "absent",
                (g and g.eqConfigImported) and "yes" or "no",
                (c and c.eqCharImported) and "yes" or "no")
end
