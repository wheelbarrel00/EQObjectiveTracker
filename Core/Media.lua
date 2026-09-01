local _, ns = ...

local Media = ns:RegisterModule("Media", {})

local FONT_PATH = [[Interface\AddOns\EQObjectiveTracker\Media\Fonts\]]

-- These names must stay character-for-character identical to Everything Quests. A
-- profile imported from EQ stores the font by NAME, so a renamed entry silently falls
-- back to Friz Quadrata and the user's tracker changes appearance with nothing to
-- explain why. When EQ drops its own font registration it will fetch these through
-- LibSharedMedia, so the names are a shared contract, not a private list.
local FONTS = {
    { name = "GothamXNarrow Black",       file = FONT_PATH .. "GothamXNarrow-Black.ttf" },
    { name = "Avquest",                   file = FONT_PATH .. "Avquest.ttf" },
    { name = "Barlow Condensed",          file = FONT_PATH .. "BarlowCondensed-Regular.ttf" },
    { name = "Barlow Condensed Medium",   file = FONT_PATH .. "BarlowCondensed-Medium.ttf" },
    { name = "Barlow Condensed SemiBold", file = FONT_PATH .. "BarlowCondensed-SemiBold.ttf" },
    { name = "Barlow Condensed Bold",     file = FONT_PATH .. "BarlowCondensed-Bold.ttf" },
    { name = "Beep",                      file = FONT_PATH .. "Beep-Regular.otf" },
    { name = "Beep Medium",               file = FONT_PATH .. "Beep-Medium.otf" },
    { name = "Beep Bold",                 file = FONT_PATH .. "Beep-Bold.otf" },
    { name = "Exo 2 ExtraBold",           file = FONT_PATH .. "Exo2-ExtraBold.ttf" },
    { name = "GoodBrush",                 file = FONT_PATH .. "GoodBrush.ttf" },
    { name = "Gotham Narrow Black",       file = FONT_PATH .. "GothamNarrowBlack.ttf" },
    { name = "Inter",                     file = FONT_PATH .. "Inter-Regular.ttf" },
    { name = "Inter SemiBold",            file = FONT_PATH .. "Inter-SemiBold.ttf" },
    { name = "Inter Bold",                file = FONT_PATH .. "Inter-Bold.ttf" },
    { name = "Josefin Sans Bold",         file = FONT_PATH .. "JosefinSans-Bold.ttf" },
    { name = "Kimberley",                 file = FONT_PATH .. "Kimberley.ttf" },
    { name = "Lemon",                     file = FONT_PATH .. "Lemon-Regular.ttf" },
    { name = "Metal Lord",                file = FONT_PATH .. "Metal-Lord.ttf" },
    { name = "Montserrat",                file = FONT_PATH .. "Montserrat-Regular.ttf" },
    { name = "Montserrat Medium",         file = FONT_PATH .. "Montserrat-Medium.ttf" },
    { name = "Montserrat SemiBold",       file = FONT_PATH .. "Montserrat-SemiBold.ttf" },
    { name = "Montserrat Bold",           file = FONT_PATH .. "Montserrat-Bold.ttf" },
    { name = "Neuropol X",                file = FONT_PATH .. "neuropolxrg.ttf" },
    { name = "Noto Sans",                 file = FONT_PATH .. "NotoSans-Regular.ttf" },
    { name = "Noto Sans SemiBold",        file = FONT_PATH .. "NotoSans-SemiBold.ttf" },
    { name = "Noto Sans Bold",            file = FONT_PATH .. "NotoSans-Bold.ttf" },
    { name = "Optimus Princeps",          file = FONT_PATH .. "OptimusPrinceps.ttf" },
    { name = "Oswald Light",              file = FONT_PATH .. "Oswald-Light.ttf" },
    { name = "Oswald",                    file = FONT_PATH .. "Oswald-Regular.ttf" },
    { name = "Oswald Bold",               file = FONT_PATH .. "Oswald-Bold.ttf" },
    { name = "Pepsi",                     file = FONT_PATH .. "Pepsi-Cyr-Lat.ttf" },
    { name = "Pricedown",                 file = FONT_PATH .. "pricedown.ttf" },
    { name = "Reckoner",                  file = FONT_PATH .. "Reckoner.ttf" },
    { name = "Reckoner Bold",             file = FONT_PATH .. "Reckoner_Bold.ttf" },
    { name = "RingLink Medium",           file = FONT_PATH .. "RingLink-Medium.otf" },
    { name = "RingLink Bold",             file = FONT_PATH .. "RingLink-Bold.otf" },
    { name = "Roboto Bold",               file = FONT_PATH .. "Roboto-Bold.ttf" },
    { name = "Simply Sans",               file = FONT_PATH .. "SimplySans-Book.ttf" },
    { name = "Simply Sans Bold",          file = FONT_PATH .. "SimplySans-Bold.ttf" },
    { name = "Ubuntu Medium",             file = FONT_PATH .. "Ubuntu-Medium.ttf" },
    { name = "Ubuntu Bold",               file = FONT_PATH .. "Ubuntu-Bold.ttf" },
}

local WOW_FONTS = {
    { name = "WoW Default (Friz Quadrata)", file = STANDARD_TEXT_FONT or [[Fonts\FRIZQT__.TTF]] },
    { name = "WoW Arial Narrow",            file = [[Fonts\ARIALN.TTF]] },
    { name = "WoW Morpheus",                file = [[Fonts\MORPHEUS.TTF]] },
}

-- Same migration contract as the fonts: a profile stores the bar by NAME.
local STATUSBAR_PATH = [[Interface\AddOns\EQObjectiveTracker\Media\Statusbars\]]
local STATUSBARS = {
    { name = "EQ Smooth",   file = STATUSBAR_PATH .. "EQ-Smooth.tga" },
    { name = "EQ Glaze",    file = STATUSBAR_PATH .. "EQ-Glaze.tga" },
    { name = "EQ Gradient", file = STATUSBAR_PATH .. "EQ-Gradient.tga" },
    { name = "EQ Bevel",    file = STATUSBAR_PATH .. "EQ-Bevel.tga" },
    { name = "EQ Glow",     file = STATUSBAR_PATH .. "EQ-Glow.tga" },
    { name = "EQ Gloss",    file = STATUSBAR_PATH .. "EQ-Gloss.tga" },
    { name = "EQ Steel",    file = STATUSBAR_PATH .. "EQ-Steel.tga" },
}

-- LSM's built-in "Blizzard" bar, and the fallback when LSM is absent
local DEFAULT_STATUSBAR = [[Interface\TargetingFrame\UI-StatusBar]]

-- Blizzard file IDs, not bundled audio, so the zip does not grow
local SOUNDS = {
    { name = "EQ: Work Complete",   file = 558132 },
    { name = "EQ: BloodElf (M)",    file = 539400 },
    { name = "EQ: BloodElf (F)",    file = 539175 },
    { name = "EQ: Draenei (M)",     file = 539661 },
    { name = "EQ: Draenei (F)",     file = 539676 },
    { name = "EQ: Dwarf (M)",       file = 540042 },
    { name = "EQ: Dwarf (F)",       file = 539981 },
    { name = "EQ: Gnome (M)",       file = 540512 },
    { name = "EQ: Gnome (F)",       file = 540432 },
    { name = "EQ: Goblin (M)",      file = 542005 },
    { name = "EQ: Goblin (F)",      file = 541735 },
    { name = "EQ: Human (M)",       file = 540703 },
    { name = "EQ: Human (F)",       file = 540654 },
    { name = "EQ: NightElf (M)",    file = 541085 },
    { name = "EQ: NightElf (F)",    file = 541031 },
    { name = "EQ: Orc (M)",         file = 541401 },
    { name = "EQ: Orc (F)",         file = 541317 },
    { name = "EQ: Pandaren (M)",    file = 630070 },
    { name = "EQ: Pandaren (F)",    file = 636419 },
    { name = "EQ: Tauren (M)",      file = 561484 },
    { name = "EQ: Tauren (F)",      file = 542997 },
    { name = "EQ: Troll (M)",       file = 543307 },
    { name = "EQ: Troll (F)",       file = 543273 },
    { name = "EQ: Undead (M)",      file = 542775 },
    { name = "EQ: Undead (F)",      file = 542684 },
    { name = "EQ: Worgen (M)",      file = 542228 },
    { name = "EQ: Worgen (F)",      file = 542028 },
}

-- Sound KITS, not file ids, so these play through PlaySound and cannot be registered with
-- LibSharedMedia the way the list above is. The kit NAMES are read rather than their numbers,
-- so a client that does not have one answers nil rather than a wrong number, which is what the
-- filter below reads. Cooldown Master already plays the first, third and fourth
-- of these in game, which is where they come from - the list above is voice lines and had no
-- chime in it at all. Their names are the same migration contract the fonts are: add, never
-- rename.
local KIT_SOUNDS = {
    { name = "EQ: Quest Ding",   kit = "IG_QUEST_LIST_COMPLETE" },
    { name = "EQ: Quest Open",   kit = "IG_QUEST_LIST_OPEN" },
    { name = "EQ: Ready Check",  kit = "READY_CHECK" },
    { name = "EQ: Raid Warning", kit = "RAID_WARNING" },
}

-- Two questions, deliberately not one function. Answering "is this a kit name" with the kit's
-- ID conflates it with "does this client know that kit", and every guard below asks the first
-- while a client missing the kit answers the second - which sent a kit name through to
-- GetSoundFile's fallback and played the first voice line instead.
local function isKitName(name)
    for i = 1, #KIT_SOUNDS do
        if KIT_SOUNDS[i].name == name then return true end
    end
    return false
end

-- nil for a kit this client does not know, so a picker never offers a sound that could only
-- ever be silence.
local function kitID(name)
    for i = 1, #KIT_SOUNDS do
        if KIT_SOUNDS[i].name == name then
            return _G.SOUNDKIT and _G.SOUNDKIT[KIT_SOUNDS[i].kit]
        end
    end
    return nil
end

function Media:OnInitialize()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then return end
    for _, f in ipairs(FONTS)      do LSM:Register("font", f.name, f.file) end
    for _, f in ipairs(WOW_FONTS)  do LSM:Register("font", f.name, f.file) end
    for _, s in ipairs(STATUSBARS) do LSM:Register("statusbar", s.name, s.file) end
    for _, s in ipairs(SOUNDS)     do LSM:Register("sound", s.name, s.file) end
    self.LSM = LSM
end

-- Labels drop the "EQ: " prefix, values keep it - the value is what a profile stores
function Media:GetSoundList()
    -- The client's own word for it, so this reads right in every language the game ships and
    -- costs the manifest no phrase. The stored value stays the bare token.
    local none = _G.NONE or "None"
    local out, labels = { none }, { [none] = "NONE" }
    -- Ahead of the voice lines, which are a long run nobody scrolls past
    for _, s in ipairs(KIT_SOUNDS) do
        if kitID(s.name) then
            local label = s.name:gsub("^EQ: ", "")
            out[#out + 1] = label
            labels[label] = s.name
        end
    end
    for _, s in ipairs(SOUNDS) do
        local label = s.name:gsub("^EQ: ", "")
        out[#out + 1] = label
        labels[label] = s.name
    end
    return out, labels
end

function Media:GetSoundLabel(value)
    if not value or value == "NONE" then return _G.NONE or "None" end
    return (value:gsub("^EQ: ", ""))
end

-- Everything that makes a noise goes through here rather than reaching for a file, or a kit
-- sound falls through to the fallback at the bottom of GetSoundFile and the player hears the
-- wrong one. A kit name this client cannot resolve is SILENT rather than substituted, which is
-- the honest failure: the picker does not offer it either, so a substitute could not be
-- recognised or changed.
function Media:Play(name)
    if not name or name == "NONE" then return end
    if isKitName(name) then
        local kit = kitID(name)
        if kit and PlaySound then pcall(PlaySound, kit, "Master") end
        return
    end
    local file = self:GetSoundFile(name)
    if file and PlaySoundFile then pcall(PlaySoundFile, file, "Master") end
end

function Media:GetSoundFile(name)
    if name == "NONE" then return nil end
    -- A kit has no file, and the fallback below would hand back the first voice line for one
    if isKitName(name) then return nil end
    if self.LSM then
        local f = self.LSM:Fetch("sound", name)
        if f then return f end
    end
    for _, s in ipairs(SOUNDS) do
        if s.name == name then return s.file end
    end
    return SOUNDS[1].file
end

function Media:GetStatusBarList()
    local out = {}
    local names = self.LSM and self.LSM:List("statusbar")
    if names and #names > 0 then
        for _, name in ipairs(names) do out[#out + 1] = name end
        return out
    end
    for _, s in ipairs(STATUSBARS) do out[#out + 1] = s.name end
    return out
end

function Media:GetStatusBarFile(name)
    if self.LSM then
        local f = self.LSM:Fetch("statusbar", name or "Blizzard")
        if f then return f end
    end
    for _, s in ipairs(STATUSBARS) do
        if s.name == name then return s.file end
    end
    return DEFAULT_STATUSBAR
end

function Media:GetFontList()
    local out = {}
    local names = self.LSM and self.LSM:List("font")
    if names and #names > 0 then
        for _, name in ipairs(names) do out[#out + 1] = name end
        return out
    end
    for _, f in ipairs(WOW_FONTS) do out[#out + 1] = f.name end
    for _, f in ipairs(FONTS)     do out[#out + 1] = f.name end
    return out
end

function Media:GetFontFile(name)
    if self.LSM then
        local f = self.LSM:Fetch("font", name or "Friz Quadrata TT")
        if f then return f end
    end
    for _, f in ipairs(FONTS)     do if f.name == name then return f.file end end
    for _, f in ipairs(WOW_FONTS) do if f.name == name then return f.file end end
    return STANDARD_TEXT_FONT
end

local function setShadow(fs, enabled, color, strength)
    if enabled then
        fs:SetShadowColor(color and color.r or 0, color and color.g or 0,
                          color and color.b or 0, color and color.a or 1)
        local d = strength or 2
        fs:SetShadowOffset(d, -d)
    else
        fs:SetShadowColor(0, 0, 0, 0)
        fs:SetShadowOffset(0, 0)
    end
end

function Media:ApplyTextShadow(fs)
    if not fs then return end
    local cfg = ns:GetModule("DB"):Tracker()
    if not cfg then return end
    setShadow(fs, cfg.textShadow, cfg.textShadowColor, cfg.textShadowStrength)
end

-- fontName overrides the tracker's own font for callers that offer their own picker. It
-- takes a NAME rather than a file so a profile survives the font moving on disk.
function Media:ApplyFont(fs, sizeDelta, fontName)
    if not fs then return end
    local cfg = ns:GetModule("DB"):Tracker()
    if not cfg then return end
    local file = self:GetFontFile(fontName or cfg.font)
    if file then
        fs:SetFont(file, math.max(8, (cfg.fontSize or 12) + (sizeDelta or 0)),
                   cfg.fontOutline or "")
    end
    setShadow(fs, cfg.textShadow, cfg.textShadowColor, cfg.textShadowStrength)
end

function Media:ApplyTitleFont(fs, fontName)
    local cfg = ns:GetModule("DB"):Tracker()
    self:ApplyFont(fs, cfg and cfg.titleSizeDelta or 0, fontName)
end

function Media:ApplyScenarioShadow(fs)
    if not fs then return end
    local cfg = ns:GetModule("DB"):Tracker()
    if not cfg then return end
    setShadow(fs, cfg.scenarioTextShadow, cfg.scenarioTextShadowColor,
              cfg.scenarioTextShadowStrength or 1)
end

-- base must be captured before the first SetFont - GetFont() after a resize would feed
-- the already-scaled size back in and the banner text would creep on every apply.
function Media:ApplyScenarioFont(fs, base)
    if not (fs and base and base[1] and base[2]) then return end
    local cfg   = ns:GetModule("DB"):Tracker()
    local delta = (cfg and cfg.scenarioTextSizeDelta) or 0
    fs:SetFont(base[1], math.max(6, base[2] + delta), base[3] or "")
end

function Media:ApplyScenarioCriteriaFont(fs)
    if not fs then return end
    local cfg = ns:GetModule("DB"):Tracker()
    if not cfg then return end
    local file = self:GetFontFile(cfg.font)
    if file then
        fs:SetFont(file, math.max(8, cfg.scenarioFontSize or 13), cfg.fontOutline or "")
    end
end

function Media:ProgressBarStyle()
    local cfg = ns:GetModule("DB"):Tracker()
    return (cfg and cfg.progressBar) or {}
end

-- The range must match the Bar Height slider's in Options/TabAppearance.lua. Clamped here as
-- well as there because nothing else bounds a value that reached the profile by another route,
-- and a height outside this range draws a bar that does not fit the row measured for it.
function Media:ProgressBarHeight()
    local st = self:ProgressBarStyle()
    return math.max(8, math.min(24, st.height or 16))
end

-- Three bar families share this: the quest row bars (UI/Row.lua), the scenario criteria bars
-- (UI/Scenario.lua) and the event widget bars (UI/WidgetBlock.lua), which draw in the same
-- panel as the criteria and would otherwise be the one bar the settings do not reach.
-- skipFill is for that third caller alone. A widget bar's FILL COLOR is Blizzard's, decoded
-- per widget from its textureKit, and that color is the only thing separating one widget's
-- state from another - overwriting it with one user color would throw real information away.
-- Everything else about a widget bar carries no meaning and is styled like the rest.
-- A caller must build its own .bg texture and .border backdrop. This creates neither, and
-- both guards below fail SILENTLY, so a new caller missing one simply loses that half.
function Media:ApplyProgressBar(bar, skipFill)
    if not bar then return end
    local st = self:ProgressBarStyle()

    bar:SetStatusBarTexture(self:GetStatusBarFile(st.barTexture))
    if not skipFill then
        local fill = st.barColor
        if fill then bar:SetStatusBarColor(fill.r, fill.g, fill.b, fill.a or 1)
        else         bar:SetStatusBarColor(0.26, 0.42, 1.0) end
    end

    if bar.bg then
        if st.showBackground == false then
            bar.bg:Hide()
        else
            local c = st.backgroundColor
            bar.bg:SetColorTexture(c and c.r or 0.04, c and c.g or 0.07,
                                   c and c.b or 0.18, c and c.a or 0.9)
            bar.bg:Show()
        end
    end

    if bar.border then
        if st.showBorder == false then
            bar.border:Hide()
        else
            local c = st.borderColor
            bar.border:SetBackdropBorderColor(c and c.r or 0, c and c.g or 0,
                                              c and c.b or 0, c and c.a or 0.9)
            bar.border:Show()
        end
    end
end

function Media:LineSpacing()
    local cfg = ns:GetModule("DB"):Tracker()
    return math.max(-8, math.min(24, (cfg and cfg.lineSpacing) or 0))
end

function Media:HeaderSpacing()
    local cfg = ns:GetModule("DB"):Tracker()
    return math.max(-8, math.min(24, (cfg and cfg.headerSpacing) or 0))
end
