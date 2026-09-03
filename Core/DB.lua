local _, ns = ...

local DB = ns:RegisterModule("DB", {})

-- Key names under profile.tracker and profile.general are deliberately identical to
-- Everything Quests so the future EQ config import stays a filtered table copy rather
-- than a semantic translation. Do not rename these for taste.
DB.defaults = {
    profile = {
        general = {
            lockTracker      = false,
            hideInCombat     = false,
            hideInInstances  = false,
            hideOnMapOpen    = false,
            hideInMythicPlus = false,
            -- Counted by Tracker:Render and read by UI/Visibility.lua. New key, so no stored
            -- value exists for a default to silently overrule - see the AceDB note below.
            hideWhenNoQuests = false,
            autoTrackAccepted = true,
            restoreSuperTrackOnLogin = true,
            -- A NEW key defaulting to false is safe. This is not the AceDB default-flip
            -- trap, which is about CHANGING an existing default and silently reverting
            -- everyone who chose the old value. The companion global.questieTrackerPrompted
            -- has no default because it is only ever written true.
            hideQuestieTracker = false,
        },
        tracker = {
            anchor        = "TOPRIGHT",
            relativePoint = "TOPRIGHT",
            -- In UIParent units, NOT the frame's own scaled space. Tracker divides by the
            -- live scale on apply and multiplies on save, so the tracker grows in place
            -- rather than sliding when the scale slider moves.
            xOffset       = -85,
            yOffset       = -200,
            width         = 305,
            maxHeight     = 600,
            scale         = 1.0,

            questSoundEnabled    = true,
            questCompleteSound   = "EQ: Work Complete",
            -- Its own pair rather than sharing the two above, so accept and complete can be set
            -- apart or either switched off. Off, because this reaches players who already have
            -- the complete sound switched off and a new noise nobody asked for is worse.
            questAcceptSoundEnabled = false,
            questAcceptSound        = "EQ: Quest Ding",
            -- The hand in used to be reached only by accident, as the chat line standing in for
            -- the objectives sound. It has its own event and its own pair now, and it ships off
            -- because it is a moment nobody was being told about on purpose.
            questTurnInSoundEnabled = false,
            -- Deliberately NOT the objectives sound above. Its own tooltip promises the two
            -- moments can be told apart, and a player who switches this on and leaves the seed
            -- alone would hear one voice line at the last objective and again at the quest
            -- giver. The scan walks both quest log surfaces, so that is every flavor, not just
            -- Classic where the accident used to live.
            questTurnInSound        = "EQ: Ready Check",

            showOnlyWatched      = true,
            sortMode             = "zone",
            manualOrder          = {},
            simplifyMode         = false,
            simplifyGroups       = {},

            font               = "GothamXNarrow Black",
            fontSize           = 15,
            fontOutline        = "OUTLINE",
            titleSizeDelta     = 0,
            textShadow         = false,
            textShadowColor    = { r = 0, g = 0, b = 0, a = 1 },
            textShadowStrength = 2,

            scenarioTextShadow         = true,
            scenarioTextShadowColor    = { r = 0, g = 0, b = 0, a = 1 },
            scenarioTextShadowStrength = 1,
            scenarioTextAlign          = "CENTER",
            scenarioTextSizeDelta      = 0,
            scenarioFontSize           = 13,

            blockSpacing         = 2,
            lineSpacing          = 0,
            headerSpacing        = 0,

            blockLayout          = "classic",
            cardColor            = { r = 0.09, g = 0.10, b = 0.12, a = 0.73 },
            cardBorderColor      = { r = 0.00, g = 0.00, b = 0.00, a = 0.45 },
            cardBorderSize       = 1,
            cardPadding          = 6,
            cardTintByType       = false,
            cardTintCampaign     = { r = 0.20, g = 0.14, b = 0.04, a = 0.80 },
            cardTintLegendary    = { r = 0.24, g = 0.12, b = 0.01, a = 0.80 },
            cardTintDungeon      = { r = 0.02, g = 0.11, b = 0.20, a = 0.80 },
            cardTintRaid         = { r = 0.02, g = 0.15, b = 0.03, a = 0.80 },
            scenarioCard         = true,

            showBackground     = false,
            backgroundColor    = { r = 0, g = 0, b = 0, a = 0.6 },
            showBorder         = false,
            borderColor        = { r = 0.635, g = 0.000, b = 0.039, a = 1 },
            borderSize         = 1,

            headerColor        = { r = 0.93, g = 0.32, b = 0.10, a = 1 },
            headerDividerColor = { r = 0.92, g = 0.72, b = 0.02, a = 0.85 },
            headerSizeDelta    = 4,
            headerColorUseClass = false,

            headerBar            = false,
            headerBarColor       = { r = 0.80, g = 0.60, b = 0.20, a = 0.85 },
            headerBarHeight      = 22,
            headerBarStyle       = 1,
            headerBarSoftEdges   = false,
            headerBarSoftEdgeStrength = 10,

            scrollBarBg          = true,
            scrollBarBgColor     = { r = 0.60, g = 0.60, b = 0.65, a = 0.25 },
            hideScrollBar        = false,
            skinScrollBar        = false,
            scrollBarThumbColor  = { r = 0.60, g = 0.60, b = 0.65, a = 0.90 },
            scrollBarThumbWidth  = 8,
            hideScrollArrows     = false,
            showZoneTag          = false,
            showObjectiveNumbers = true,
            -- A NEW key, so nobody has a stored value a default could silently revert.
            -- On matches the default tracker, which draws a real bar for these.
            showProgressBars     = true,
            -- The two halves under that master. Both are NEW keys and showProgressBars keeps
            -- the meaning it shipped with, which is the whole reason the split is shaped this
            -- way: a player who had already switched bars off stays off on both halves rather
            -- than having the scenario one silently handed back to them.
            showQuestProgressBars    = true,
            showScenarioProgressBars = true,
            -- Also a NEW key. Blizzard shows these inside the tracker EQOT hides, so on
            -- is what restores what the stock tracker was already showing.
            showTrackerWidgets   = true,
            showQuestTotal       = true,
            showLevelInTracker   = false,
            showQuestID          = false,
            showRecentlyAddedTag = true,
            showOptionsIcon      = true,
            splitQuestClick      = false,
            showItemButtons       = true,
            showQuestPopups       = true,
            colorByDifficulty     = true,
            titleColorUseClass    = false,
            overrideCompleteGreen = true,
            -- Left unset on purpose: nil is what makes titles fall through to difficulty
            -- coloring, so AceDB must not seed a default the Clear button cannot restore.
            titleColorOverride    = nil,

            filters = {
                showNormal      = true,
                showDaily       = true,
                showWeekly      = true,
                showScheduled   = true,
                showCampaign    = true,
                showWorld       = true,
                showBonus       = true,
                onlyCurrentZone = false,
            },

            -- positionInScreenUnits is deliberately NOT defaulted here, and must never be.
            -- Its ABSENCE is what marks a profile whose xOffset and yOffset predate the
            -- units change above, and Core/Migrate.lua converts on that. Give it a default
            -- and every unconverted profile silently reads as already converted.

            -- sectionOrder is deliberately NOT defaulted here, and must never be. AceDB
            -- merges an array default per index and strips matching indices at logout, so a
            -- saved order returns as a sparse fragment and any later change to the default's
            -- shape silently reinterprets it. Sections.DEFAULT_ORDER holds it instead.
            sectionsHidden = {},

            showZoneProgressBar  = false,
            zoneProgressLocation = "floating",
            zoneProgressBar = {
                point = "CENTER", relPoint = "CENTER", x = 0, y = 220,
                scale = 1.0,
                locked = false,
                showBorder = true,
                showBackground = true,
                -- Real defaults rather than fallbacks synthesized in the options getter. A
                -- picker snapshots its getter for the Cancel restore, so a synthesized value
                -- gets written on Cancel, and a key absent from here can never be stripped
                -- back out at logout. Values match the fallbacks in UI/ZoneProgressBar.lua.
                -- backgroundColor is deliberately still unset, so the backdrop keeps its
                -- locked/unlocked alpha fade until the user picks a color.
                barColor    = { r = 0.26,  g = 0.42,  b = 1.00,  a = 1 },
                borderColor = { r = 0.635, g = 0.000, b = 0.039, a = 1 },
                headerColor = { r = 0.93,  g = 0.32,  b = 0.10,  a = 1 },
                countColor  = { r = 0.92,  g = 0.72,  b = 0.02,  a = 1 },
            },

            -- ONE style block shared by the quest row bars, the scenario criteria bars and the
            -- event widget bars, which all draw identically. Splitting the styling as well as
            -- the switches would mean setting the same seven controls three times over just to
            -- keep the look they already have. Real defaults rather than fallbacks synthesized
            -- in the options getter, for the reason the zone bar's block above gives.
            -- barTexture is deliberately unset: Media falls back to Blizzard's own.
            progressBar = {
                height          = 16,
                showBackground  = true,
                showBorder      = true,
                barColor        = { r = 0.26, g = 0.42, b = 1.00, a = 1 },
                backgroundColor = { r = 0.04, g = 0.07, b = 0.18, a = 0.9 },
                borderColor     = { r = 0.00, g = 0.00, b = 0.00, a = 0.9 },
            },

            scenarioBonusHUD = {
                enabled = false,
                point = "CENTER", relPoint = "CENTER", x = 0, y = -120,
                scale = 1.0,
                locked = false,
                showBorder = true,
                showBackground = true,
            },

            autoListZoneWorldQuests      = true,
            worldQuestsPosition          = "bottom",
            worldQuestsPinnedMaxFraction = 0.40,
            worldQuestsHeightOverride    = false,
            worldQuestsHeight            = 200,
        },
    },
    char = {
        sectionsCollapsed  = {},
        pinned             = {},
        trackedWorldQuests = {},
    },
    global = {
        schemaVersion       = 1,
        optionsWindowScale  = 1.0,
    },
}

local APPEARANCE_KEYS = {
    "font", "fontSize", "fontOutline", "titleSizeDelta",
    "textShadow", "textShadowColor", "textShadowStrength",
    "scenarioTextShadow", "scenarioTextShadowColor", "scenarioTextShadowStrength",
    "scenarioTextAlign", "scenarioTextSizeDelta", "scenarioFontSize",
    "titleColorOverride", "overrideCompleteGreen", "headerColor",
    "headerDividerColor", "headerSizeDelta",
    "titleColorUseClass", "headerColorUseClass",
    "headerBar", "headerBarColor", "headerBarHeight", "headerBarStyle",
    "headerBarSoftEdges", "headerBarSoftEdgeStrength",
    "blockSpacing", "lineSpacing", "headerSpacing", "scale",
    "blockLayout", "cardColor", "cardBorderColor", "cardBorderSize", "cardPadding",
    "cardTintByType", "cardTintCampaign", "cardTintLegendary", "cardTintDungeon", "cardTintRaid",
    "scenarioCard",
    "showBackground", "backgroundColor", "showBorder", "borderColor", "borderSize",
    "scrollBarBg", "scrollBarBgColor", "skinScrollBar",
    "scrollBarThumbColor", "scrollBarThumbWidth", "hideScrollArrows",
    -- showZoneProgressBar and zoneProgressLocation belong on this tab but must NOT be here:
    -- they default to off and floating, so clearing them switches a configured bar off and
    -- undocks it. hideScrollBar defaults to false, so clearing it restores the bar.
    "hideScrollBar",
    -- Same test as hideScrollBar rather than the zone bar's: all three default to ON, so
    -- clearing re-enables the bars instead of switching a configured one off.
    "showProgressBars", "showQuestProgressBars", "showScenarioProgressBars",
}

-- Clearing a key lets AceDB re-apply its default. Left alone by design: the zone bar's saved
-- position, and any switch whose default is OFF, because clearing one of those switches a
-- configured feature off rather than restoring a look.
function DB:ResetTrackerAppearance()
    local prof = self:Tracker()
    if not prof then return end
    for _, k in ipairs(APPEARANCE_KEYS) do prof[k] = nil end
    local zb = prof.zoneProgressBar
    if zb then
        zb.showBackground, zb.showBorder, zb.scale = nil, nil, nil
        zb.borderColor, zb.headerColor, zb.countColor, zb.font = nil, nil, nil, nil
        zb.barTexture, zb.barColor, zb.backgroundColor = nil, nil, nil
    end
    -- The switches live in APPEARANCE_KEYS, so only the STYLE block is left to clear here.
    -- Clearing restores the default look rather than blanking a bar: every key has a visible
    -- default except barTexture, which has none and falls back to Blizzard's in Core/Media.lua.
    local pb = prof.progressBar
    if pb then
        pb.height, pb.showBackground, pb.showBorder = nil, nil, nil
        pb.barTexture, pb.barColor = nil, nil
        pb.backgroundColor, pb.borderColor = nil, nil
    end
end

-- ResetProfile only clears the profile scope, so on its own it leaves the per-character
-- display state and the one global key behind - both of which a user reads as "a setting".
-- trackedWorldQuests is deliberately spared: it mirrors the player's own manual world quest
-- watches, so clearing it untracks their quests rather than restoring a default.
--
-- trackedQuests IS cleared, and to nil rather than to an empty table, because on Classic its
-- ABSENCE is the flag for "nothing decided yet" and absence fails open to every quest tracked.
-- An empty table is the opposite state and would hide the whole log. It clears where
-- trackedWorldQuests does not because the two fail in opposite directions.
--
-- delveRun clears too, and it is not a third exemption: it is the delve HUD's live tally
-- rather than a choice, and absence is already what it reads as "no run in progress".
function DB:ResetAll()
    if not self.db then return end
    if self.db.ResetProfile then self.db:ResetProfile() end

    local g = self.db.global
    if g then
        g.optionsWindowScale = self.defaults.global.optionsWindowScale
        -- The bisection axis is not a setting, but a player who ran /eqot disable all and
        -- forgot is looking at an addon with most of it switched off, and this is the button
        -- they reach for. Cleared rather than defaulted: absence is what these five read as
        -- off, and Commands recreates the tables on the next use.
        g.safeMode, g.disabledModules, g.disabledProviders = nil, nil, nil
        g.enabledModules, g.enabledProviders               = nil, nil
    end

    local c = self.db.char
    if c then
        c.sectionsCollapsed = {}
        c.pinned            = {}
        c.trackedQuests     = nil
        c.delveRun          = nil
    end
end

function DB:OnInitialize()
    -- The saved variable global exists only once this addon has written one, so its absence
    -- is what marks a genuinely first run. That is the only safe moment to import EQ's
    -- config: overwriting a profile somebody has already tuned is indistinguishable from
    -- data loss. Must be read BEFORE AceDB:New, which creates the table.
    local freshInstall = (_G.EQObjectiveTrackerDB == nil)

    -- Ships off on Classic by the author's decision. The original reason has since been removed
    -- by the addon owning its own tracked set: there is no five-quest cap any more and auto-track
    -- works there. What remains is that an existing Classic character has never had a tracked set
    -- of their own, so defaulting the filter ON would hide a log nobody had opted into.
    -- Capability gated rather than flavor gated, and written before AceDB:New, which takes this
    -- table by reference.
    if not ns.Has.QuestWatchAPI then
        self.defaults.profile.tracker.showOnlyWatched = false
    end

    self.db = LibStub("AceDB-3.0"):New("EQObjectiveTrackerDB", self.defaults, true)
    ns.db = self.db

    local Migrate = ns:GetModule("Migrate")
    if Migrate and Migrate.Run then Migrate:Run(self.db, freshInstall) end
end

function DB:Profile()
    return self.db and self.db.profile
end

function DB:Tracker()
    return self.db and self.db.profile and self.db.profile.tracker
end

function DB:General()
    return self.db and self.db.profile and self.db.profile.general
end

function DB:Char()
    return self.db and self.db.char
end

function DB:Global()
    return self.db and self.db.global
end
