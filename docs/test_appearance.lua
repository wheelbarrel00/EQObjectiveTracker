-- Unit tests for Options/TabAppearance.lua, run against the SHIPPED source.
-- Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_appearance.lua
--
-- The tab loads WHOLE over a stub context that records what the library would draw: each card,
-- the rows it stacks in order, which rows are indented, which picker hangs at the end of which
-- checkbox row, and every SetDependent call.
--
-- WHAT EARNS THIS FILE is the dependency sweep. Roughly half the tab dims on a master switch,
-- two conditions deep in places, and no harness had ever driven it: a control dimmed on the
-- wrong key, or a master whose setter forgot to re-run the sweep, was visible only in game. The
-- sweep is checked against the rules written out independently below, across a fixed run of
-- generated profiles that toggles every key it reads. Beside it: the card order the author set on
-- 2026-10-03, every card's rows as the author approved them, and the cap
-- that keeps the sweep away from Lua 5.1's 60-upvalue ceiling.
--
-- OUT OF SCOPE BY CONSTRUCTION: how any of it looks. The stub draws nothing, so row heights,
-- the label column and the swatch's place at the row's end are the library's tests' business.

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
end

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end

local ROW_PADDING, GROUP_GAP = 14, 22

local function frame()
    local f = { shown = true, points = {} }
    function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:SetChecked(v) self.checked = v end
    function f:SetText(s) self.text = s end
    function f:SetScript() end
    function f:HookScript() end
    return f
end

-- Builds the tab once. bonus is whether the scenario provider registered, which is what puts
-- the bonus objectives HUD card on the tab (retail). The capability probe reads true on every
-- flavor, Classic included, so it is never what keeps the card off.
-- marked: every lookup comes back as "\1<key>", so a string that bypassed the table reads bare.
local function appearanceTab(bonus, marked)
    local cfg = {}
    local calls = { applyFade = 0, render = 0, invalidate = 0, hud = 0, preview = 0, zoneLook = 0,
                    banner = 0, applyScale = 0, hudTest = 0, hudEnabled = {}, hudScale = {}, log = {} }
    local modules = {}
    -- Every key looked up, so a label typed as a bare English string can be told from a wrapped one.
    local looked = {}
    local ns = {
        L = setmetatable({}, { __index = function(_, k) looked[k] = true; return marked and ("\1" .. k) or k end }),
        Has = { ScenarioBonus = true },
    }
    function ns:GetModule(name) return modules[name] end
    -- The real Util, since the title color dropdown and the sweep both read the mode through
    -- it. A class is stubbed so Class color has a color to give.
    do
        local utilNs = { RegisterModule = function(_, _, m) return m end, Has = {} }
        local utilChunk = assert(loadfile(repoFile("Core/Util.lua")))
        setfenv(utilChunk, setmetatable({
            UnitClass = function() return "Mage", "MAGE" end,
            RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } },
        }, { __index = _G }))
        utilChunk("EQObjectiveTracker", utilNs)
        ns.Util = utilNs.Util
    end
    local spec
    modules.Options = { RegisterTab = function(_, s) spec = s end }
    modules.DB = { Tracker = function() return cfg end,
                   ResetTrackerAppearance = function() calls.log[#calls.log + 1] = "reset" end }
    modules.Tracker = { Render = function() calls.render = calls.render + 1 end,
                        ApplyScale = function() calls.applyScale = calls.applyScale + 1 end }
    modules.Row = { Invalidate = function() calls.invalidate = calls.invalidate + 1 end }
    modules.Scenario = { ApplyBannerShadow = function() calls.banner = calls.banner + 1 end }
    modules.Visibility = { ApplyFade = function() calls.applyFade = calls.applyFade + 1 end }
    modules.Dialog = { Show = function(_, o) calls.dialog = o end }
    modules.Media = {
        GetFontList = function() return { "Friz" } end, GetStatusBarList = function() return { "Blizzard" } end,
        GetFontFile = function(_, name) return "file:" .. tostring(name) end, GetStatusBarFile = function() return "X" end,
    }
    modules.ZoneProgressBar = {
        RefreshAppearance = function() calls.zoneLook = calls.zoneLook + 1 end,
        SetEnabled = function(_, v) cfg.showZoneProgressBar = v end,
        SetLocation = function(_, where) cfg.zoneProgressLocation = where end,
    }
    modules.ScenarioBonusHUD = {
        ApplySettings = function() calls.hud = calls.hud + 1 end,
        SetEnabled = function(_, v) calls.hudEnabled[#calls.hudEnabled + 1] = v end,
        SetScale = function(_, v) calls.hudScale[#calls.hudScale + 1] = v end,
        ToggleTest = function() calls.hudTest = calls.hudTest + 1 end,
    }
    modules.Registry = { Get = function(_, id) return id == "scenarios" and bonus and {} or nil end }
    modules.TrackerPreview = {
        Refresh = function() calls.preview = calls.preview + 1 end,
        Build = function(_, panel) calls.previewPanel = panel end,
    }

    local t = { cfg = cfg, calls = calls, cards = {}, dims = {}, dimCalls = 0, controls = {}, looked = looked }
    local ui = {}
    local function control(kind, label, getter, setter, tooltip)
        local f = frame()
        f.kind, f.label, f.getter, f.setter, f.tooltip = kind, label, getter, setter, tooltip
        t.controls[#t.controls + 1] = f
        return f
    end
    function ui:CreateGroup(_, label)
        local card = frame()
        card.title, card.rows = label, {}
        card.Add = function(c, ctl, opts)
            local row = frame()
            row.control, row.dependent = ctl, opts and opts.dependent and true or false
            ctl.card, ctl.row = c, row
            c.rows[#c.rows + 1] = row
            return row
        end
        t.cards[#t.cards + 1] = card
        return card
    end
    function ui:CreateCheckbox(_, label, getter, setter, tooltip)
        return control("checkbox", label, getter, setter, tooltip)
    end
    function ui:CreateSlider(_, label, minV, maxV, step, getter, setter, tooltip)
        local f = control("slider", label, getter, setter, tooltip)
        f.min, f.max, f.step = minV, maxV, step
        return f, frame()
    end
    function ui:CreateDropdown(_, label, options, getter, setter, tooltip, decorate, onTest, previewFont)
        local f = control("dropdown", label, getter, setter, tooltip)
        f.options, f.decorate, f.onTest, f.previewFont = options, decorate, onTest, previewFont
        return f
    end
    function ui:CreateRadioGroup(_, label, options, getter, setter, _, _, tipTitle, tipBody)
        local f = control("radio", label, getter, setter, tipBody)
        f.options, f.tipTitle = options, tipTitle
        return f
    end
    function ui:CreateColorPicker(_, label, getter, setter, tooltip, hasAlpha, onClear)
        local f = control("picker", label, getter, setter, tooltip)
        f.hasAlpha, f.onClear = hasAlpha, onClear
        return f
    end
    function ui:CreateButton(_, label, width, onClick, tooltip)
        local f = control("button", label, nil, nil, tooltip)
        f.width, f.onClick = width, onClick
        return f
    end
    function ui:Spacing(name)
        if name == "rowPadding" then return ROW_PADDING end
        if name == "groupGap" then return GROUP_GAP end
        error("no spacing named " .. tostring(name))
    end
    function ui:SetDependent(ctl, on)
        t.dims[ctl] = on and true or false
        t.dimCalls = t.dimCalls + 1
    end

    local chunk = assert(loadfile(repoFile("Options/TabAppearance.lua")))
    setfenv(chunk, setmetatable({ ReloadUI = function() calls.log[#calls.log + 1] = "reload" end },
                                { __index = _G }))
    chunk("EQObjectiveTracker", ns)
    t.content = {}
    spec.build(ui, t.content)
    t.spec, t.ui = spec, ui

    -- Every control by "Card/Label". Labels repeat across cards but never inside one.
    t.byKey = {}
    for _, card in ipairs(t.cards) do
        for _, row in ipairs(card.rows) do t.byKey[card.title .. "/" .. row.control.label] = row.control end
    end
    -- A picker that is no card's row hangs at the end of a checkbox row. It is found by the row
    -- it is anchored to.
    for _, c in ipairs(t.controls) do
        if not c.card then
            local p = c.points[1]
            local row = p and p[2]
            if row and row.control then
                c.satelliteOf = row.control
                t.byKey[row.control.card.title .. "/" .. c.label] = c
            end
        end
    end
    return t
end

-- The author's order of 2026-10-03: the big tickets first, the self-contained features last.
-- It replaced the one card per old heading that section 8 of the design spec set for phase 1.
local CARD_ORDER = {
    "Text", "Quest Colors", "Tracker", "Section Headers", "Spacing", "Quest Rows", "Progress Bars",
    "Scroll Bar", "Scenario", "Scenario Bonus Objectives", "Zone Progress Bar",
}

-- { label, kind, dependent, the picker at the row's end }
local ROWS = {
    ["Text"] = {
        { "Font", "dropdown" }, { "Font Size", "slider" }, { "Title Size Offset", "slider" },
        { "Header Size Offset", "slider" }, { "Font Outline", "dropdown" },
        { "Text Shadow", "checkbox", false, "Shadow Color" }, { "Shadow Size", "slider", true },
    },
    ["Quest Colors"] = {
        { "Quest Title Color", "radio" }, { "Custom Title Color", "picker", true },
        { "Use title color for completed quests", "checkbox" },
        { "Objective Text Color", "picker" }, { "Count Color: None Done", "picker" },
        { "Count Color: In Progress", "picker" }, { "Count Color: Done", "picker" },
        { "Finished Objective Color", "picker" },
    },
    ["Tracker"] = {
        { "Tracker Scale", "slider" }, { "Tracker Opacity", "slider" },
        { "Full opacity on mouseover", "checkbox", true },
        { "Keep the focused quest at full opacity", "checkbox", true },
        { "Background", "checkbox", false, "Background Color" },
        { "Border", "checkbox", false, "Border Color" }, { "Border Thickness", "slider", true },
    },
    ["Section Headers"] = {
        { "Use class color for headers", "checkbox" }, { "Section Header Color", "picker", true },
        { "Divider Line Color", "picker" },
        { "Show header bars", "checkbox", false, "Bar Color" }, { "Bar Style", "radio" },
        { "Bar Height", "slider" }, { "Soft edges", "checkbox" }, { "Edge Softness", "slider", true },
    },
    ["Spacing"] = {
        { "Block Spacing", "slider" }, { "Line Spacing", "slider" }, { "Header Spacing", "slider" },
    },
    ["Scenario"] = {
        { "Text Shadow", "checkbox", false, "Shadow Color" }, { "Shadow Size", "slider", true },
        { "Banner Alignment", "radio" }, { "Banner Text Size", "slider" },
        { "Criteria Text Size", "slider" }, { "Event Title Text Size", "slider" },
        { "Event Title Color", "picker" },
    },
    ["Scroll Bar"] = {
        { "Hide scroll bar", "checkbox" },
        { "Scroll Bar Background", "checkbox", false, "Scroll Bar Color" },
        { "Solid color thumb", "checkbox", false, "Thumb Color" }, { "Thumb Width", "slider", true },
        { "Hide scroll bar arrows", "checkbox" },
    },
    ["Scenario Bonus Objectives"] = {
        { "Show bonus objectives HUD", "checkbox" }, { "Test", "button" },
        { "Background", "checkbox", false, "Background Color" },
        { "Border", "checkbox", false, "Border Color" }, { "HUD Scale", "slider" },
    },
    ["Quest Rows"] = {
        { "Row Layout", "radio" }, { "Background Color", "picker" }, { "Border Color", "picker" },
        { "Border Thickness", "slider" }, { "Card Padding", "slider" },
        { "Card behind the scenario panel", "checkbox" }, { "Tint cards by quest type", "checkbox" },
        { "Campaign", "picker", true }, { "Legendary", "picker", true }, { "Dungeon", "picker", true },
        { "Raid", "picker", true },
    },
    ["Zone Progress Bar"] = {
        { "Show zone progress bar", "checkbox" }, { "Float as a movable bar", "checkbox" },
        { "Background", "checkbox", true, "Background Color" },
        { "Border", "checkbox", true, "Border Color" }, { "Zone Bar Scale", "slider", true },
        { "Font", "dropdown", true }, { "Header Color", "picker", true },
        { "Count Color", "picker", true }, { "Bar Texture", "dropdown" }, { "Bar Color", "picker" },
    },
    ["Progress Bars"] = {
        { "Show progress bars", "checkbox" }, { "Quest Rows", "checkbox" },
        { "Scenario Criteria", "checkbox" }, { "Background", "checkbox", false, "Background Color" },
        { "Border", "checkbox", false, "Border Color" }, { "Bar Height", "slider" },
        { "Bar Texture", "dropdown" }, { "Bar Color", "picker" },
    },
}

-- The dimming rules, written out from the tab's own notes rather than read off its code. Each
-- answers whether that control is LIT for a profile. cfg is the tracker profile.
local function zb(cfg) return cfg.zoneProgressBar or {} end
local function pb(cfg) return cfg.progressBar or {} end
local function noBar(cfg) return not cfg.hideScrollBar end
local function card(cfg) return (cfg.blockLayout or "classic") == "card" end
local function float(cfg)
    return cfg.showZoneProgressBar and (cfg.zoneProgressLocation or "floating") == "floating"
end
local function drawn(cfg)
    return cfg.showProgressBars ~= false
       and (cfg.showQuestProgressBars ~= false or cfg.showScenarioProgressBars ~= false)
end
-- A profile from before the dropdown keeps the colors its three old switches gave it: class over
-- a set override, then difficulty unless it was switched off, which reads as Gold.
local MODES = { difficulty = true, gold = true, class = true, custom = true, original = true }
local function titleMode(c)
    if MODES[c.titleColorMode] then return c.titleColorMode end
    if c.titleColorUseClass then return "class" end
    if c.titleColorOverride and c.titleColorOverride.r then return "custom" end
    if c.colorByDifficulty == false then return "gold" end
    return "difficulty"
end
local SWEEP = {
    ["Text/Shadow Color"]   = function(c) return c.textShadow end,
    ["Text/Shadow Size"]    = function(c) return c.textShadow end,
    ["Scenario/Shadow Color"]     = function(c) return c.scenarioTextShadow ~= false end,
    ["Scenario/Shadow Size"]      = function(c) return c.scenarioTextShadow ~= false end,
    ["Scroll Bar/Scroll Bar Background"]  = noBar,
    ["Scroll Bar/Hide scroll bar arrows"] = noBar,
    ["Scroll Bar/Solid color thumb"]      = noBar,
    ["Scroll Bar/Scroll Bar Color"] = function(c) return noBar(c) and c.scrollBarBg ~= false end,
    ["Scroll Bar/Thumb Color"]      = function(c) return noBar(c) and c.skinScrollBar end,
    ["Scroll Bar/Thumb Width"]      = function(c) return noBar(c) and c.skinScrollBar end,
    ["Tracker/Background Color"] = function(c) return c.showBackground end,
    ["Tracker/Border Color"]     = function(c) return c.showBorder end,
    ["Tracker/Border Thickness"] = function(c) return c.showBorder end,
    ["Section Headers/Bar Color"]     = function(c) return c.headerBar end,
    ["Section Headers/Bar Style"]     = function(c) return c.headerBar end,
    ["Section Headers/Bar Height"]    = function(c) return c.headerBar end,
    ["Section Headers/Soft edges"]    = function(c) return c.headerBar end,
    ["Section Headers/Edge Softness"] = function(c) return c.headerBar and c.headerBarSoftEdges end,
    ["Quest Colors/Custom Title Color"] = function(c) return titleMode(c) == "custom" end,
    ["Quest Colors/Use title color for completed quests"] = function(c)
        local m = titleMode(c)
        return m == "class" or m == "original" or (m == "custom" and c.titleColorOverride ~= nil
                                                     and c.titleColorOverride.r ~= nil)
    end,
    ["Section Headers/Section Header Color"] = function(c) return not c.headerColorUseClass end,
    ["Quest Rows/Background Color"]               = card,
    ["Quest Rows/Border Color"]                   = card,
    ["Quest Rows/Border Thickness"]               = card,
    ["Quest Rows/Card Padding"]                   = card,
    ["Quest Rows/Card behind the scenario panel"] = card,
    ["Quest Rows/Tint cards by quest type"]       = card,
    ["Quest Rows/Campaign"]  = function(c) return card(c) and c.cardTintByType end,
    ["Quest Rows/Legendary"] = function(c) return card(c) and c.cardTintByType end,
    ["Quest Rows/Dungeon"]   = function(c) return card(c) and c.cardTintByType end,
    ["Quest Rows/Raid"]      = function(c) return card(c) and c.cardTintByType end,
    ["Zone Progress Bar/Float as a movable bar"] = function(c) return c.showZoneProgressBar end,
    ["Zone Progress Bar/Bar Texture"]            = function(c) return c.showZoneProgressBar end,
    ["Zone Progress Bar/Bar Color"]              = function(c) return c.showZoneProgressBar end,
    ["Zone Progress Bar/Background"]     = float,
    ["Zone Progress Bar/Border"]         = float,
    ["Zone Progress Bar/Zone Bar Scale"] = float,
    ["Zone Progress Bar/Font"]           = float,
    ["Zone Progress Bar/Header Color"]   = float,
    ["Zone Progress Bar/Count Color"]    = float,
    ["Zone Progress Bar/Background Color"] =
        function(c) return float(c) and zb(c).showBackground ~= false end,
    ["Zone Progress Bar/Border Color"] =
        function(c) return float(c) and zb(c).showBorder ~= false end,
    ["Progress Bars/Quest Rows"]        = function(c) return c.showProgressBars ~= false end,
    ["Progress Bars/Scenario Criteria"] = function(c) return c.showProgressBars ~= false end,
    ["Progress Bars/Background"]  = drawn,
    ["Progress Bars/Border"]      = drawn,
    ["Progress Bars/Bar Height"]  = drawn,
    ["Progress Bars/Bar Texture"] = drawn,
    ["Progress Bars/Bar Color"]   = drawn,
    ["Progress Bars/Background Color"] = function(c) return drawn(c) and pb(c).showBackground ~= false end,
    ["Progress Bars/Border Color"]     = function(c) return drawn(c) and pb(c).showBorder ~= false end,
}

local FADE = {
    ["Tracker/Full opacity on mouseover"] = true,
    ["Tracker/Keep the focused quest at full opacity"] = true,
}
local HUD = {
    ["Scenario Bonus Objectives/Background Color"] = function(s) return s.showBackground ~= false end,
    ["Scenario Bonus Objectives/Border Color"]     = function(s) return s.showBorder ~= false end,
}

-- Every value each key the sweep reads can hold. ABSENT stands for nil, which a list cannot hold.
local ABSENT = {}
local SWITCH = { ABSENT, true, false }
local DOMAIN = {
    textShadow = SWITCH, scenarioTextShadow = SWITCH, hideScrollBar = SWITCH, scrollBarBg = SWITCH,
    skinScrollBar = SWITCH, showBackground = SWITCH, showBorder = SWITCH, headerBar = SWITCH,
    headerBarSoftEdges = SWITCH, titleColorUseClass = SWITCH, headerColorUseClass = SWITCH,
    titleColorOverride = { ABSENT, { r = 1, g = 0, b = 0 }, {} },
    titleColorMode = { ABSENT, "difficulty", "gold", "class", "custom", "original", "bogus" },
    colorByDifficulty = SWITCH,
    blockLayout = { ABSENT, "classic", "card" }, cardTintByType = SWITCH,
    showZoneProgressBar = SWITCH, zoneProgressLocation = { ABSENT, "floating", "tracker" },
    showProgressBars = SWITCH, showQuestProgressBars = SWITCH, showScenarioProgressBars = SWITCH,
}

-- A fixed generator rather than math.random, so a failing profile is the same on every run.
local seed = 12345
local function pick(list)
    seed = (seed * 1103515245 + 12345) % 2147483648
    local v = list[math.floor(seed / 65536) % #list + 1]
    if v == ABSENT then return nil end
    return v
end

local DOMAIN_KEYS = {}
for k in pairs(DOMAIN) do DOMAIN_KEYS[#DOMAIN_KEYS + 1] = k end
table.sort(DOMAIN_KEYS)

local function randomProfile()
    local cfg = {}
    for _, k in ipairs(DOMAIN_KEYS) do cfg[k] = pick(DOMAIN[k]) end
    cfg.zoneProgressBar = { showBackground = pick(SWITCH), showBorder = pick(SWITCH) }
    cfg.progressBar     = { showBackground = pick(SWITCH), showBorder = pick(SWITCH) }
    return cfg
end

local function setProfile(t, profile)
    for k in pairs(t.cfg) do t.cfg[k] = nil end
    for k, v in pairs(profile) do t.cfg[k] = v end
end

local function lit(v) return v and true or false end

print("== the cards, in the order the author set on 2026-10-03")
do
    local good, err = pcall(function()
        for _, bonus in ipairs({ true, false }) do
            local t = appearanceTab(bonus)
            local want = {}
            for _, title in ipairs(CARD_ORDER) do
                if bonus or title ~= "Scenario Bonus Objectives" then want[#want + 1] = title end
            end
            local tag = bonus and "retail" or "Classic"
            ok(#t.cards == #want, tag .. ": " .. #want .. " cards, got " .. #t.cards)
            for i, title in ipairs(want) do
                ok(t.cards[i] and t.cards[i].title == title,
                   tag .. ": card " .. i .. " is " .. title .. ", got " .. tostring(t.cards[i] and t.cards[i].title))
            end
            local first = t.cards[1] and t.cards[1].points or {}
            ok(#first == 2 and first[1][1] == "TOPLEFT" and #first[1] == 1
               and first[2][1] == "TOPRIGHT" and #first[2] == 1,
               tag .. ": the first card spans the top of the tab")
            for i = 2, #t.cards do
                local p = t.cards[i].points
                ok(#p == 2 and p[1][1] == "TOPLEFT" and p[1][2] == t.cards[i - 1] and p[1][3] == "BOTTOMLEFT"
                   and p[1][5] == -GROUP_GAP and p[2][1] == "TOPRIGHT" and p[2][2] == t.cards[i - 1]
                   and p[2][3] == "BOTTOMRIGHT" and p[2][5] == -GROUP_GAP,
                   tag .. ": " .. t.cards[i].title .. " hangs full width a group gap under the card before it")
            end
        end
    end)
    ok(good, "the card order raised: " .. tostring(err))
end

print("== every card's rows, indents and end-of-row pickers")
do
    local good, err = pcall(function()
        local t = appearanceTab(true)
        for _, c in ipairs(t.cards) do
            local want = ROWS[c.title] or {}
            ok(#c.rows == #want, c.title .. ": " .. #want .. " rows, got " .. #c.rows)
            for i, w in ipairs(want) do
                local row = c.rows[i]
                local ctl = row and row.control
                local where = c.title .. " row " .. i .. " (" .. w[1] .. ")"
                ok(ctl and ctl.label == w[1], where .. " is labelled " .. w[1] .. ", got " .. tostring(ctl and ctl.label))
                ok(ctl and ctl.kind == w[2], where .. " is a " .. w[2] .. ", got " .. tostring(ctl and ctl.kind))
                ok(row and row.dependent == (w[3] and true or false),
                   where .. (w[3] and " is indented under the switch above it" or " is not indented"))
                if w[4] then
                    local sat = t.byKey[c.title .. "/" .. w[4]]
                    local p = sat and sat.points[1] or {}
                    ok(sat and sat.satelliteOf == ctl and sat.kind == "picker",
                       where .. " carries " .. w[4] .. " at its end")
                    ok(p[1] == "RIGHT" and p[2] == row and p[3] == "RIGHT" and p[4] == -ROW_PADDING and p[5] == 0,
                       where .. ": " .. w[4] .. " sits at the row's right end, inside its padding")
                end
            end
        end
        -- Every control the tab builds is a row or hangs on one. A stray would draw at the top
        -- of the tab.
        for _, ctl in ipairs(t.controls) do
            ok(ctl.card or ctl.satelliteOf, tostring(ctl.label) .. " is placed on a card")
            ok(ctl.tooltip ~= nil and ctl.tooltip ~= "", tostring(ctl.label) .. " still carries its tooltip")
        end
    end)
    ok(good, "the rows raised: " .. tostring(err))
end

print("== the two pickers that went segmented keep their values")
do
    local good, err = pcall(function()
        local t = appearanceTab(true)
        local align = t.byKey["Scenario/Banner Alignment"]
        local style = t.byKey["Section Headers/Bar Style"]
        local function values(ctl)
            local out = {}
            for _, o in ipairs(ctl and ctl.options or {}) do out[#out + 1] = tostring(o.value) .. "=" .. o.label end
            return table.concat(out, ",")
        end
        ok(values(align) == "LEFT=Left,CENTER=Center,RIGHT=Right", "Banner Alignment offers Left, Center, Right")
        ok(align and align.tipTitle == "Banner Alignment", "and titles its tooltip with its own label")
        t.cfg.scenarioTextAlign = "GAUCHE"
        ok(align and align.getter() == "CENTER", "a translated word left in a profile still reads as Center")
        align.setter("RIGHT")
        ok(t.cfg.scenarioTextAlign == "RIGHT", "and a pick stores the value, not the label")

        ok(values(style) == "1=Header Bar 1,2=Header Bar 2", "Bar Style offers Header Bar 1 and 2")
        ok(style and style.tipTitle == "Bar Style", "and titles its tooltip with its own label")
        t.cfg.headerBarStyle = 7
        ok(style and style.getter() == 1, "an unknown style reads as Header Bar 1")
        style.setter(2)
        ok(t.cfg.headerBarStyle == 2, "and a pick stores the number")
    end)
    ok(good, "the segmented pickers raised: " .. tostring(err))
end

print("== the sweep dims exactly what each rule says, across generated profiles")
do
    local good, err = pcall(function()
        local t = appearanceTab(true)
        local sweep = t.content._syncDependents
        ok(type(sweep) == "function", "the tab leaves its sweep where refresh can find it")
        for key, rule in pairs(SWEEP) do
            ok(t.byKey[key] and t.dims[t.byKey[key]] == lit(rule(t.cfg)),
               key .. " is already dimmed right when the tab is built")
        end
        local wrong, seenLit, seenDim = {}, {}, {}
        for n = 1, 400 do
            local profile = randomProfile()
            setProfile(t, profile)
            for k in pairs(t.dims) do t.dims[k] = nil end
            sweep()
            for key, rule in pairs(SWEEP) do
                local ctl = t.byKey[key]
                local want = lit(rule(t.cfg))
                if want then seenLit[key] = true else seenDim[key] = true end
                if not ctl or t.dims[ctl] ~= want then wrong[key] = wrong[key] or n end
            end
            for ctl in pairs(t.dims) do
                local key = ctl.card and (ctl.card.title .. "/" .. ctl.label)
                    or (ctl.satelliteOf and ctl.satelliteOf.card.title .. "/" .. ctl.label)
                if not SWEEP[key] then wrong["stray " .. tostring(key)] = n end
            end
        end
        for key in pairs(SWEEP) do
            ok(not wrong[key], key .. " follows its rule (first wrong at profile " .. tostring(wrong[key]) .. ")")
            ok(seenLit[key] and seenDim[key], key .. " was seen both lit and dimmed")
        end
        for key, n in pairs(wrong) do
            if not SWEEP[key] then ok(false, key .. " is dimmed by the sweep (profile " .. n .. ")") end
        end
    end)
    ok(good, "the sweep raised: " .. tostring(err))
end

print("== every master re-runs the sweep, and nothing else does")
do
    local good, err = pcall(function()
        local t = appearanceTab(true)
        local sweepSize = 0
        for _ in pairs(SWEEP) do sweepSize = sweepSize + 1 end
        -- Counting the sweep's calls cannot see one run before the setter stores, which dims for
        -- the state before the click, so every setter's result is held against the rules too.
        local function stale()
            local out = {}
            for key, rule in pairs(SWEEP) do
                local ctl = t.byKey[key]
                if ctl and t.dims[ctl] ~= lit(rule(t.cfg)) then out[#out + 1] = key end
            end
            table.sort(out)
            return table.concat(out, ", ")
        end
        local function sweeps(key, value)
            local ctl = t.byKey[key]
            assert(ctl and ctl.setter, "no setter for " .. key)
            local before = t.dimCalls
            ctl.setter(value)
            local s = stale()
            ok(s == "", key .. " leaves every dependent dimmed for the new value: " .. s)
            return t.dimCalls - before >= sweepSize
        end
        for _, key in ipairs({
            "Text/Text Shadow", "Scenario/Text Shadow", "Scroll Bar/Hide scroll bar",
            "Scroll Bar/Scroll Bar Background", "Scroll Bar/Solid color thumb", "Tracker/Background",
            "Tracker/Border", "Section Headers/Show header bars", "Section Headers/Soft edges",
            "Section Headers/Use class color for headers",
            "Quest Rows/Tint cards by quest type", "Zone Progress Bar/Show zone progress bar",
            "Zone Progress Bar/Float as a movable bar", "Zone Progress Bar/Background",
            "Zone Progress Bar/Border", "Progress Bars/Show progress bars", "Progress Bars/Quest Rows",
            "Progress Bars/Scenario Criteria", "Progress Bars/Background", "Progress Bars/Border",
        }) do
            ok(sweeps(key, true), key .. " re-runs the sweep when it changes")
        end
        ok(sweeps("Quest Rows/Row Layout", "card"), "Quest Rows/Row Layout re-runs the sweep when it changes")
        ok(t.cfg.blockLayout == "card", "and stores the layout it was handed")
        ok(sweeps("Quest Colors/Quest Title Color", "custom"),
           "Quest Colors/Quest Title Color re-runs the sweep when it changes")
        ok(t.cfg.titleColorMode == "custom", "and stores the mode it was handed")
        -- No rule reads these, so none re-runs the sweep. The first does nothing until the title
        -- mode gives a color, and is dimmed until then.
        for _, key in ipairs({
            "Quest Colors/Use title color for completed quests", "Text/Shadow Color",
            "Scroll Bar/Hide scroll bar arrows", "Quest Rows/Card behind the scenario panel",
            "Text/Font Size", "Section Headers/Divider Line Color",
        }) do
            ok(not sweeps(key, true), key .. " does not re-run the sweep")
        end

        -- The title override sweeps only when its nil state changes, in either direction.
        local title = t.byKey["Quest Colors/Custom Title Color"]
        t.cfg.titleColorOverride = nil
        ok(sweeps("Quest Colors/Custom Title Color", { r = 1, g = 0, b = 0 }),
           "setting a title color from none re-runs the sweep")
        ok(not sweeps("Quest Colors/Custom Title Color", { r = 0, g = 1, b = 0 }),
           "dragging an already set color does not")
        ok(sweeps("Quest Colors/Custom Title Color", nil),
           "and a Cancel back to none does")
        t.cfg.titleColorOverride = { r = 1, g = 1, b = 1 }
        local before = t.dimCalls
        if title and title.onClear then title.onClear() end
        ok(t.cfg.titleColorOverride == nil and t.dimCalls - before >= sweepSize,
           "Clear unsets it and re-runs the sweep")
        ok(stale() == "", "leaving every dependent dimmed for the cleared color: " .. stale())
        -- An empty table is no color to every reader, so a pick over one is a nil-to-set change.
        t.cfg.titleColorMode, t.cfg.titleColorOverride = "custom", {}
        t.content._syncDependents()
        ok(sweeps("Quest Colors/Custom Title Color", { r = 1, g = 0, b = 0 }),
           "a color picked over an empty one re-runs the sweep")
        ok(title and title.hasAlpha == false, "the title color takes no alpha")
    end)
    ok(good, "the masters raised: " .. tostring(err))
end

print("== every setter redraws the preview, but the HUD's, Tracker Scale's and the two opacity behaviors")
do
    local good, err = pcall(function()
        local t = appearanceTab(true)
        ok(type(t.spec.preview) == "function" and type(t.spec.previewRefresh) == "function",
           "the tab registers a preview and its refresh")
        local panel = {}
        t.spec.preview(t.ui, panel)
        ok(t.calls.previewPanel == panel, "the preview is built into the library's panel")
        local before = t.calls.preview
        t.spec.previewRefresh(t.ui, panel)
        ok(t.calls.preview == before + 1, "and drawn again on every view")

        -- The HUD is its own frame with its own Test button, Tracker Scale is not drawn (the preview
        -- is fitted to its panel), and the two boxes under the opacity slider change only how the
        -- live tracker answers the mouse and the followed quest.
        local SKIP = {
            ["Scenario Bonus Objectives/Show bonus objectives HUD"] = true,
            ["Scenario Bonus Objectives/Background"] = true,
            ["Scenario Bonus Objectives/Background Color"] = true,
            ["Scenario Bonus Objectives/Border"] = true,
            ["Scenario Bonus Objectives/Border Color"] = true,
            ["Scenario Bonus Objectives/HUD Scale"] = true,
            ["Tracker/Tracker Scale"] = true,
            ["Tracker/Full opacity on mouseover"] = true,
            ["Tracker/Keep the focused quest at full opacity"] = true,
        }
        local function valueFor(c)
            if c.kind == "checkbox" then return true end
            if c.kind == "slider" then return c.min end
            if c.kind == "radio" then return c.options[1].value end
            if c.kind == "picker" then return { r = 0.5, g = 0.5, b = 0.5, a = 1 } end
            return "Friz"
        end
        local drove, skipped = 0, 0
        for key, c in pairs(t.byKey) do
            if c.setter then
                local was = t.calls.preview
                c.setter(valueFor(c))
                local redrew = t.calls.preview > was
                if SKIP[key] then
                    skipped = skipped + 1
                    ok(not redrew, key .. " leaves the preview alone")
                else
                    drove = drove + 1
                    ok(redrew, key .. " redraws the preview")
                end
            end
        end
        ok(skipped == 9, "every exception was reached: " .. skipped)
        ok(drove >= 50, "and every other control was driven: " .. drove)
        for key, c in pairs(t.byKey) do
            if c.onClear then
                local was = t.calls.preview
                c.onClear()
                if SKIP[key] then
                    ok(t.calls.preview == was, key .. "'s Clear leaves the preview alone")
                else
                    ok(t.calls.preview > was, key .. "'s Clear redraws the preview")
                end
            end
        end
    end)
    ok(good, "the preview refresh raised: " .. tostring(err))
end

print("== the sweep stays far from the 60-upvalue ceiling")
do
    local good, err = pcall(function()
        local t = appearanceTab(true)
        local n = debug.getinfo(t.content._syncDependents, "u").nups
        -- It closed over 55 before its controls moved into one table, and past 60 the whole file
        -- fails to load while luacheck reports it clean.
        ok(n <= 10, "the sweep closes over " .. n .. " upvalues, at most 10")
    end)
    ok(good, "the upvalue count raised: " .. tostring(err))
end

print("== the opacity slider and its two boxes")
do
    local good, err = pcall(function()
        local t = appearanceTab(true)
        local slider = t.byKey["Tracker/Tracker Opacity"]
        ok(slider and slider.min == 10 and slider.max == 100 and slider.step == 5,
           "the slider runs 10 to 100 in fives, so it can never reach invisible")
        t.cfg.trackerAlpha = 0.35
        ok(slider.getter() == 35, "it shows the stored fraction as a whole number")
        local fades = t.calls.applyFade
        slider.setter(50)
        ok(t.cfg.trackerAlpha == 0.5, "and stores it back as a fraction")
        ok(t.calls.applyFade == fades + 1, "and applies it")
        for key in pairs(FADE) do
            ok(t.dims[t.byKey[key]] == true, key .. " is lit while the tracker is faded")
        end
        slider.setter(100)
        for key in pairs(FADE) do
            ok(t.dims[t.byKey[key]] == false, key .. " is dimmed at 100")
        end
        local hover = t.byKey["Tracker/Full opacity on mouseover"]
        hover.setter(false)
        ok(t.cfg.trackerAlphaHover == false and t.calls.applyFade == fades + 3, "the mouseover box writes and applies")
        local focus = t.byKey["Tracker/Keep the focused quest at full opacity"]
        focus.setter(false)
        ok(t.cfg.trackerAlphaFocus == false and t.calls.applyFade == fades + 4, "and so does the focused quest box")

        local fresh = appearanceTab(true)
        for key in pairs(FADE) do
            ok(fresh.dims[fresh.byKey[key]] == false, key .. " is dimmed when the tab is built at full opacity")
        end
    end)
    ok(good, "the opacity controls raised: " .. tostring(err))
end

print("== the bonus objectives HUD sweeps its own two pickers")
do
    local good, err = pcall(function()
        local t = appearanceTab(true)
        local hud = t.content._syncHUD
        ok(type(hud) == "function", "the HUD card leaves its sweep for refresh")
        for key in pairs(HUD) do
            ok(t.dims[t.byKey[key]] == true, key .. " is lit when the tab is built on a new profile")
        end
        for _, sub in ipairs({ { nil, nil }, { false, true }, { true, false }, { false, false } }) do
            t.cfg.scenarioBonusHUD = { showBackground = sub[1], showBorder = sub[2] }
            hud()
            for key, rule in pairs(HUD) do
                ok(t.dims[t.byKey[key]] == lit(rule(t.cfg.scenarioBonusHUD)),
                   key .. " follows its own box (" .. tostring(sub[1]) .. ", " .. tostring(sub[2]) .. ")")
            end
        end
        local before = t.dimCalls
        t.byKey["Scenario Bonus Objectives/Background"].setter(false)
        ok(t.cfg.scenarioBonusHUD.showBackground == false and t.dimCalls - before == 2,
           "its Background box writes the HUD key and re-runs only the HUD's sweep")
        ok(t.calls.hud > 0, "through the HUD's own apply path")
        local test = t.byKey["Scenario Bonus Objectives/Test"]
        ok(test and test.width == 120 and type(test.onClick) == "function", "the Test button keeps its width and action")
        local bg = t.byKey["Scenario Bonus Objectives/Background Color"]
        ok(bg and type(bg.onClear) == "function", "the HUD background color can be cleared")

        local classic = appearanceTab(false)
        ok(classic.content._syncHUD == nil, "Classic builds no HUD card and no HUD sweep")
        local good2 = pcall(classic.spec.refresh, nil, classic.content)
        ok(good2, "and its refresh runs without one")
    end)
    ok(good, "the HUD card raised: " .. tostring(err))
end

print("== refresh re-runs both sweeps")
do
    local good, err = pcall(function()
        local t = appearanceTab(true)
        local before = t.dimCalls
        t.spec.refresh(nil, t.content)
        local sweepSize = 0
        for _ in pairs(SWEEP) do sweepSize = sweepSize + 1 end
        ok(t.dimCalls - before == sweepSize + 2, "one pass of the main sweep and one of the HUD's: "
           .. (t.dimCalls - before))
    end)
    ok(good, "refresh raised: " .. tostring(err))
end

-- How each setter reaches the LIVE tracker, written out from the tab's own notes. R restyles
-- (fonts and anything Row memoizes, so the rows are invalidated before the render), L relays out
-- (a render alone), B restyles the scenario banner and renders, Z styles the floating zone bar
-- alone, ZS also renders for the docked bar, P styles the progress bars (invalidate and render),
-- S is the HUD's own apply. The preview redraw is checked in "every setter redraws the preview".
local R, LAY, B, Z, ZS, P, S = "R", "L", "B", "Z", "ZS", "P", "S"
local PATH = {
    ["Text/Font"] = R, ["Text/Font Size"] = R, ["Text/Title Size Offset"] = R,
    ["Text/Header Size Offset"] = LAY, ["Text/Font Outline"] = R,
    ["Text/Text Shadow"] = R, ["Text/Shadow Color"] = R, ["Text/Shadow Size"] = R,
    ["Scenario/Text Shadow"] = B, ["Scenario/Shadow Color"] = B, ["Scenario/Shadow Size"] = B,
    ["Scenario/Banner Alignment"] = LAY, ["Scenario/Banner Text Size"] = LAY,
    ["Scenario/Criteria Text Size"] = LAY, ["Scenario/Event Title Text Size"] = LAY,
    ["Scenario/Event Title Color"] = LAY,
    ["Scroll Bar/Hide scroll bar"] = LAY, ["Scroll Bar/Scroll Bar Background"] = LAY,
    ["Scroll Bar/Scroll Bar Color"] = LAY, ["Scroll Bar/Solid color thumb"] = LAY,
    ["Scroll Bar/Thumb Color"] = LAY, ["Scroll Bar/Thumb Width"] = LAY, ["Scroll Bar/Hide scroll bar arrows"] = LAY,
    ["Tracker/Background"] = LAY, ["Tracker/Background Color"] = LAY, ["Tracker/Border"] = LAY,
    ["Tracker/Border Color"] = LAY, ["Tracker/Border Thickness"] = LAY,
    ["Section Headers/Show header bars"] = LAY, ["Section Headers/Bar Color"] = LAY, ["Section Headers/Bar Style"] = LAY,
    ["Section Headers/Bar Height"] = LAY, ["Section Headers/Soft edges"] = LAY, ["Section Headers/Edge Softness"] = LAY,
    ["Scenario Bonus Objectives/Background"] = S, ["Scenario Bonus Objectives/Background Color"] = S,
    ["Scenario Bonus Objectives/Border"] = S, ["Scenario Bonus Objectives/Border Color"] = S,
    ["Quest Colors/Quest Title Color"] = R,
    ["Quest Colors/Custom Title Color"] = R,
    ["Quest Colors/Use title color for completed quests"] = R,
    ["Quest Colors/Objective Text Color"] = R,
    ["Quest Colors/Count Color: None Done"] = R,
    ["Quest Colors/Count Color: In Progress"] = R,
    ["Quest Colors/Count Color: Done"] = R,
    ["Quest Colors/Finished Objective Color"] = R,
    ["Section Headers/Use class color for headers"] = LAY,
    ["Section Headers/Section Header Color"] = LAY, ["Section Headers/Divider Line Color"] = LAY,
    ["Spacing/Block Spacing"] = LAY, ["Spacing/Line Spacing"] = R,
    ["Spacing/Header Spacing"] = R,
    ["Quest Rows/Row Layout"] = R, ["Quest Rows/Background Color"] = R, ["Quest Rows/Border Color"] = R,
    ["Quest Rows/Border Thickness"] = R, ["Quest Rows/Card Padding"] = R,
    ["Quest Rows/Card behind the scenario panel"] = LAY, ["Quest Rows/Tint cards by quest type"] = R,
    ["Quest Rows/Campaign"] = R, ["Quest Rows/Legendary"] = R, ["Quest Rows/Dungeon"] = R, ["Quest Rows/Raid"] = R,
    ["Zone Progress Bar/Background"] = Z, ["Zone Progress Bar/Background Color"] = Z,
    ["Zone Progress Bar/Border"] = Z, ["Zone Progress Bar/Border Color"] = Z,
    ["Zone Progress Bar/Zone Bar Scale"] = Z, ["Zone Progress Bar/Font"] = Z,
    ["Zone Progress Bar/Header Color"] = Z, ["Zone Progress Bar/Count Color"] = Z,
    ["Zone Progress Bar/Bar Texture"] = ZS, ["Zone Progress Bar/Bar Color"] = ZS,
    ["Progress Bars/Show progress bars"] = R, ["Progress Bars/Quest Rows"] = R,
    ["Progress Bars/Scenario Criteria"] = R, ["Progress Bars/Background"] = P,
    ["Progress Bars/Background Color"] = P, ["Progress Bars/Border"] = P, ["Progress Bars/Border Color"] = P,
    ["Progress Bars/Bar Height"] = P, ["Progress Bars/Bar Texture"] = P, ["Progress Bars/Bar Color"] = P,
}
-- Each reaches its own module and is checked by value elsewhere: the three opacity controls in
-- "the opacity slider and its two boxes", the rest in the case after the next.
local OWN_PATH = {
    ["Scenario Bonus Objectives/Show bonus objectives HUD"] = true,
    ["Scenario Bonus Objectives/HUD Scale"] = true,
    ["Tracker/Tracker Scale"] = true,
    ["Tracker/Tracker Opacity"] = true,
    ["Tracker/Full opacity on mouseover"] = true,
    ["Tracker/Keep the focused quest at full opacity"] = true,
    ["Zone Progress Bar/Show zone progress bar"] = true,
    ["Zone Progress Bar/Float as a movable bar"] = true,
}
-- { invalidate, render, banner, zone bar look, HUD apply }
local EXPECT = {
    R = { 1, 1, 0, 0, 0 }, L = { 0, 1, 0, 0, 0 }, B = { 0, 1, 1, 0, 0 }, Z = { 0, 0, 0, 1, 0 },
    ZS = { 0, 1, 0, 1, 0 }, P = { 1, 1, 0, 0, 0 }, S = { 0, 0, 0, 0, 1 },
}

print("== every setter reaches the live tracker by its own path")
do
    local good, err = pcall(function()
        local t = appearanceTab(true)
        local c = t.calls
        local function valueFor(ctl)
            if ctl.kind == "checkbox" then return true end
            if ctl.kind == "slider" then return ctl.min end
            if ctl.kind == "radio" then return ctl.options[1].value end
            if ctl.kind == "picker" then return { r = 0.5, g = 0.5, b = 0.5, a = 1 } end
            return "Friz"
        end
        local function drive(key, fn)
            local before = { c.invalidate, c.render, c.banner, c.zoneLook, c.hud }
            fn()
            local got = { c.invalidate - before[1], c.render - before[2], c.banner - before[3],
                          c.zoneLook - before[4], c.hud - before[5] }
            local want = EXPECT[PATH[key]]
            ok(table.concat(got, ",") == table.concat(want, ","),
               key .. " reaches the tracker by path " .. PATH[key] .. ": invalidate, render, banner, zone bar, HUD = "
               .. table.concat(got, ",") .. ", want " .. table.concat(want, ","))
        end
        local driven = 0
        for key, ctl in pairs(t.byKey) do
            if ctl.setter then
                if PATH[key] then
                    driven = driven + 1
                    drive(key, function() ctl.setter(valueFor(ctl)) end)
                else
                    ok(OWN_PATH[key], key .. " has a path written out for it")
                end
            end
            if ctl.onClear and PATH[key] then
                drive(key, function() ctl.onClear() end)
            end
        end
        local want = 0
        for _ in pairs(PATH) do want = want + 1 end
        ok(driven == want, "every control with a path was driven: " .. driven .. " of " .. want)
    end)
    ok(good, "the live paths raised: " .. tostring(err))
end

print("== the HUD's switch, Test button and scale, and Tracker Scale reach their modules")
do
    local good, err = pcall(function()
        local t = appearanceTab(true)
        local c = t.calls
        t.byKey["Scenario Bonus Objectives/Show bonus objectives HUD"].setter(true)
        t.byKey["Scenario Bonus Objectives/Show bonus objectives HUD"].setter(false)
        ok(#c.hudEnabled == 2 and c.hudEnabled[1] == true and c.hudEnabled[2] == false,
           "the HUD switch hands the HUD its state, on and off")
        t.byKey["Scenario Bonus Objectives/Test"].onClick()
        ok(c.hudTest == 1, "the Test button toggles the HUD's test draw once: " .. c.hudTest)
        t.byKey["Scenario Bonus Objectives/HUD Scale"].setter(0.75)
        ok(#c.hudScale == 1 and c.hudScale[1] == 0.75, "HUD Scale hands the HUD its scale")
        local scale = t.byKey["Tracker/Tracker Scale"]
        scale.setter(1.2)
        ok(t.cfg.scale == 1.2 and c.applyScale == 1, "Tracker Scale stores the scale and applies it once")
        t.byKey["Zone Progress Bar/Show zone progress bar"].setter(true)
        ok(t.cfg.showZoneProgressBar == true, "the zone bar switch reaches the bar")
        t.byKey["Zone Progress Bar/Float as a movable bar"].setter(false)
        ok(t.cfg.zoneProgressLocation == "tracker", "unticked, the bar docks in the tracker")
        t.byKey["Zone Progress Bar/Float as a movable bar"].setter(true)
        ok(t.cfg.zoneProgressLocation == "floating", "ticked, it floats again")
    end)
    ok(good, "the module calls raised: " .. tostring(err))
end

print("== Reset to Defaults asks first, then resets the tab before the reload")
do
    local good, err = pcall(function()
        local t = appearanceTab(true)
        local bar = frame()
        t.spec.footer(t.ui, bar)
        local reset
        for _, ctl in ipairs(t.controls) do
            if ctl.kind == "button" and ctl.label == "Reset to Defaults" then reset = ctl end
        end
        ok(reset and reset.points[1] and reset.points[1][1] == "RIGHT", "the footer carries Reset to Defaults at its right")
        reset.onClick()
        local d = t.calls.dialog
        ok(d and d.button1 == "Reset" and d.button2 == "Cancel" and type(d.onAccept) == "function",
           "a click asks first, with Reset and Cancel")
        ok(#t.calls.log == 0, "and nothing is reset or reloaded until Yes")
        d.onAccept()
        ok(table.concat(t.calls.log, ",") == "reset,reload",
           "Yes resets the appearance, then reloads: " .. table.concat(t.calls.log, ","))
    end)
    ok(good, "Reset to Defaults raised: " .. tostring(err))
end

print("== the font lists draw each face in itself")
do
    local good, err = pcall(function()
        local t = appearanceTab(true)
        local font = t.byKey["Text/Font"]
        ok(font and type(font.previewFont) == "function" and font.previewFont("Friz") == "file:Friz",
           "the tracker font list previews each face from its media file")
        local zone = t.byKey["Zone Progress Bar/Font"]
        ok(zone and type(zone.previewFont) == "function" and zone.previewFont("Friz") == "file:Friz",
           "and so does the zone bar's")
        ok(zone.previewFont("") == nil, "while its Same as tracker font row has no face of its own")
    end)
    ok(good, "the font previews raised: " .. tostring(err))
end

print("== the headers' class color box names what it colors and the picker below it")
do
    local good, err = pcall(function()
        local t = appearanceTab(true)
        local headers = t.byKey["Section Headers/Use class color for headers"]
        local ht = tostring(headers and headers.tooltip)
        ok(ht:find("section headers", 1, true) and ht:find("color below", 1, true), "the headers box's tooltip: " .. ht)
        ok(t.byKey["Quest Colors/Use class color for titles"] == nil,
           "the titles' box is gone, now one choice of Quest Title Color")
    end)
    ok(good, "the class color tooltips raised: " .. tostring(err))
end

print("== the objective and count colors each read and store their own key")
do
    local good, err = pcall(function()
        local t = appearanceTab(true)
        local PICKERS = {
            { "Objective Text Color", "objectiveColor" },
            { "Count Color: None Done", "countColorNone" },
            { "Count Color: In Progress", "countColorPartial" },
            { "Count Color: Done", "countColorDone" },
            { "Finished Objective Color", "finishedObjectiveColor" },
        }
        for i, p in ipairs(PICKERS) do
            local ctl = t.byKey["Quest Colors/" .. p[1]]
            ok(ctl ~= nil, p[1] .. " is built")
            if ctl then
                local color = { r = i / 10, g = 0, b = 0 }
                ctl.setter(color)
                ok(t.cfg[p[2]] == color, p[1] .. " stores " .. p[2])
                ok(ctl.getter() == color, p[1] .. " reads it back")
                for _, other in ipairs(PICKERS) do
                    if other[2] ~= p[2] then
                        ok(t.cfg[other[2]] ~= color, p[1] .. " leaves " .. other[2] .. " alone")
                    end
                end
            end
        end
        local finished = t.byKey["Quest Colors/Finished Objective Color"]
        ok(finished and type(finished.onClear) == "function", "the finished color can be cleared")
        if finished and finished.onClear then
            local inv = t.calls.invalidate
            finished.onClear()
            ok(t.cfg.finishedObjectiveColor == nil, "Clear unsets it, which is what brings green back")
            ok(t.calls.invalidate == inv + 1, "and repaints the rows")
        end
        ok(finished and finished.hasAlpha == false, "a finished line's color takes no alpha")
        for i = 1, 4 do
            local ctl = t.byKey["Quest Colors/" .. PICKERS[i][1]]
            ok(ctl and ctl.onClear == nil, PICKERS[i][1] .. " has a default, so no Clear")
            ok(ctl and not ctl.hasAlpha, PICKERS[i][1] .. " takes no alpha")
        end
    end)
    ok(good, "the objective colors raised: " .. tostring(err))
end

print("== every card title and control label on the tab is a wrapped phrase")
do
    local good, err = pcall(function()
        local t = appearanceTab(true)
        local bare = {}
        for _, group in ipairs(t.cards) do
            if not t.looked[group.title] then bare[#bare + 1] = "card " .. tostring(group.title) end
        end
        for _, c in ipairs(t.controls) do
            if c.label ~= nil and not t.looked[c.label] then bare[#bare + 1] = tostring(c.label) end
        end
        ok(#t.cards > 0 and #t.controls > 0, "the tab built its cards and controls")
        ok(#bare == 0, "each one was looked up in the locale table: " .. table.concat(bare, ", "))
    end)
    ok(good, "the label sweep raised: " .. tostring(err))
end

-- A key looked up in one place says nothing about a bare string drawn in another, so the tab is
-- built again with a marking table and every string it draws must carry the mark. Media names
-- are their own value and unwrapped on purpose, so a choice whose label is its value is skipped.
print("== built with a marking locale table, every string the tab draws comes through it")
do
    local good, err = pcall(function()
        local t = appearanceTab(true, true)
        local bare = {}
        local function check(where, s)
            if type(s) == "string" and s:sub(1, 1) ~= "\1" then bare[#bare + 1] = where .. " '" .. s .. "'" end
        end
        for _, group in ipairs(t.cards) do check("card", group.title) end
        for _, c in ipairs(t.controls) do
            local name = tostring(c.label)
            check("label", c.label)
            check("tooltip of " .. name, c.tooltip)
            check("tip title of " .. name, c.tipTitle)
            local opts = c.options
            if type(opts) == "function" then
                local okCall, res = pcall(opts)
                opts = okCall and res or nil
            end
            for _, o in ipairs(type(opts) == "table" and opts or {}) do
                if o.value ~= o.label then check("choice of " .. name, o.label) end
                check("choice tip of " .. name, o.tip)
            end
        end
        local made = #t.controls
        t.spec.footer(t.ui, {})
        local reset = t.controls[made + 1]
        ok(reset and reset.kind == "button", "the footer builds its Reset button")
        if reset then
            check("footer button", reset.label)
            check("footer tooltip", reset.tooltip)
            reset.onClick()
            local d = t.calls.dialog
            ok(d ~= nil, "Reset asks first")
            if d then
                check("prompt text", d.text)
                check("prompt accept", d.button1)
                check("prompt cancel", d.button2)
            end
        end
        ok(#t.controls > 60, "the marked build drew the whole tab: " .. #t.controls)
        ok(#bare == 0, "nothing drawn bypasses the table: " .. table.concat(bare, "; "))
    end)
    ok(good, "the marked build raised: " .. tostring(err))
end

print("== Quest Title Color offers the five modes, each with its own tip, and reads the old switches")
do
    local good, err = pcall(function()
        local t = appearanceTab(true)
        local dd = t.byKey["Quest Colors/Quest Title Color"]
        ok(dd ~= nil, "the control is built")
        local want = { "difficulty", "gold", "class", "custom", "original" }
        -- "Gold color", never the bare "Gold" the shared store translates as money.
        local labels = { "By difficulty", "Gold color", "Class color", "Custom color", "Original Style" }
        local tips = {
            "Each quest title takes the color of how hard it is for your level, the way the quest log does. Entries with no level are gold.",
            "Every title in the same gold.",
            "Every title in the class color of the character you are logged in on.",
            "Every title in the color you pick under this.",
            "Titles colored the way Blizzard's own tracker colors them on this version of the game.",
        }
        ok(dd and #dd.options == #want, "five choices: " .. tostring(dd and #dd.options))
        for i = 1, #want do
            local o = dd and dd.options[i]
            ok(o and o.value == want[i] and o.label == labels[i], "choice " .. i .. " is " .. labels[i])
            ok(o and o.tip == tips[i], "choice " .. i .. " carries its own tip: " .. tostring(o and o.tip))
            ok(o and t.looked[o.label] and t.looked[o.tip], "choice " .. i .. "'s label and tip are both wrapped")
        end
        ok(dd and dd.tipTitle == "Quest Title Color" and tostring(dd.tooltip):find("Failed quests are always red", 1, true),
           "the control's own tooltip says what stays fixed: " .. tostring(dd and dd.tooltip))
        -- Each old profile shape reads as the mode it already drew.
        local cases = {
            { {}, "difficulty" },
            { { colorByDifficulty = false }, "gold" },
            { { titleColorOverride = { r = 1, g = 0, b = 0 } }, "custom" },
            { { titleColorOverride = { r = 1, g = 0, b = 0 }, colorByDifficulty = false }, "custom" },
            { { titleColorUseClass = true, titleColorOverride = { r = 1, g = 0, b = 0 } }, "class" },
            { { titleColorUseClass = true, titleColorMode = "original" }, "original" },
            { { titleColorMode = "bogus", colorByDifficulty = false }, "gold" },
            { { titleColorOverride = {} }, "difficulty" },
        }
        for i, c in ipairs(cases) do
            for k in pairs(t.cfg) do t.cfg[k] = nil end
            for k, v in pairs(c[1]) do t.cfg[k] = v end
            ok(dd and dd.getter() == c[2], "profile " .. i .. " reads " .. c[2] .. ": " .. tostring(dd and dd.getter()))
        end
        local picker = t.byKey["Quest Colors/Custom Title Color"]
        ok(picker and tostring(picker.tooltip):find("set to Custom color.", 1, true), "the picker says when it applies")

        -- With no mode saved, the override is one of the switches the mode is read off, so the
        -- dimmed picker must save the mode the player sees before it touches the override.
        local function fresh(c)
            for k in pairs(t.cfg) do t.cfg[k] = nil end
            for k, v in pairs(c) do t.cfg[k] = v end
        end
        fresh({})
        picker.setter({ r = 1, g = 0, b = 0 })
        ok(dd.getter() == "difficulty" and t.cfg.titleColorMode == "difficulty",
           "picking a color on an upgraded By difficulty profile keeps By difficulty: "
           .. tostring(dd.getter()) .. "/" .. tostring(t.cfg.titleColorMode))
        ok(t.cfg.titleColorOverride and t.cfg.titleColorOverride.r == 1 and t.cfg.titleColorOverride.g == 0,
           "and still stores the color for when Custom is picked")
        fresh({ colorByDifficulty = false })
        picker.setter({ r = 0, g = 0, b = 1 })
        ok(dd.getter() == "gold" and t.cfg.titleColorMode == "gold",
           "an upgraded Gold profile stays Gold: " .. tostring(dd.getter()))
        fresh({ titleColorUseClass = true })
        picker.setter({ r = 0, g = 1, b = 0 })
        ok(t.cfg.titleColorMode == "class", "an upgraded Class color profile stays Class color")
        fresh({ titleColorOverride = { r = 1, g = 0, b = 0 } })
        picker.onClear()
        ok(dd.getter() == "custom" and t.cfg.titleColorMode == "custom" and t.cfg.titleColorOverride == nil,
           "Clear on an upgraded Custom profile keeps Custom rather than falling to By difficulty: "
           .. tostring(dd.getter()))
        fresh({ titleColorOverride = { r = 1, g = 0, b = 0 } })
        picker.setter(nil)
        ok(t.cfg.titleColorMode == "custom", "and so does a Cancel back to none")
        fresh({ titleColorMode = "original" })
        picker.setter({ r = 1, g = 1, b = 0 })
        ok(t.cfg.titleColorMode == "original", "a mode already saved is kept")
        fresh({ titleColorMode = "bogus", colorByDifficulty = false })
        picker.setter({ r = 1, g = 0, b = 0 })
        ok(dd.getter() == "gold" and t.cfg.titleColorMode == "gold",
           "an unknown saved mode reads off the old switches too, so it is replaced by the one shown: "
           .. tostring(dd.getter()) .. "/" .. tostring(t.cfg.titleColorMode))
    end)
    ok(good, "the title color dropdown raised: " .. tostring(err))
end

print(("test_appearance: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
