local _, ns = ...

local Options = ns:RegisterModule("Options", {})
local L       = ns.L

local EUI = LibStub("EverythingUI-1.0")

local TAB_ICONS = {
    general = "icon-general", tracker = "icon-tracker",
    appearance = "icon-appearance", about = "icon-about",
}

local ui = EUI:NewContext({
    id      = "EQOT",
    title   = "EQ Objective Tracker",
    version = ns.VERSION,
    accent  = EUI.tokens.accents.EQOT.accent,
    L       = L,
    tooltip = ns.Util.Tooltip,
    discord = function() ns:ShowDiscord() end,
    -- Literal lookups here rather than inside the library, because the locale scanner skips
    -- Libs/ and would drop these keys, with their translations, from this addon's manifest.
    labels  = {
        discord         = L["Join our Discord!"],
        discordTipTitle = L["Join our Discord"],
        discordTip      = L["Click to copy the invite link."],
        testSound       = L["Plays the currently selected sound."],
        clear           = L["Clear"],
    },
    getLastTab = function()
        local c = ns:GetModule("DB"):Char()
        return c and c.lastOptionsTab
    end,
    setLastTab = function(id)
        local c = ns:GetModule("DB"):Char()
        if c then c.lastOptionsTab = id end
    end,
    getWindowScale = function()
        local g = ns:GetModule("DB"):Global()
        return g and g.optionsWindowScale
    end,
    setWindowScale = function(v)
        local g = ns:GetModule("DB"):Global()
        if g then g.optionsWindowScale = v end
    end,
})
Options.ui = ui

-- Tab files load after this one and register themselves, so the nav is built from whatever the
-- TOC actually loaded.
function Options:RegisterTab(def)
    ui:RegisterTab({
        id      = def.id,
        title   = def.title,
        order   = def.order,
        icon    = TAB_ICONS[def.id] and ui:Texture(TAB_ICONS[def.id]),
        footer  = def.footer,
        build   = def.build,
        refresh = def.refresh,
        preview = def.preview,
        previewRefresh = def.previewRefresh,
    })
end

function Options:SelectTab(id)
    ui:SelectTab(id)
end

function Options:Build()
    if self.frame then return end
    self.frame = ui:BuildSettings("EQOTOptionsFrame")
end

function Options:ApplyWindowScale()
    ui:ApplyWindowScale()
end

function Options:Toggle()
    self:Build()
    ui:ToggleSettings()
end

function Options:OnEnable()
    self:Build()
end
