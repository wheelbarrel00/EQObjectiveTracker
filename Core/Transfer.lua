local _, ns = ...

local Transfer = ns:RegisterModule("Transfer", {})

local ADDON    = "EQObjectiveTracker"
local SECTIONS = { "general", "tracker" }
local CHANNELS = { "r", "g", "b", "a" }

Transfer.PREFIX     = "EQOT1:"
Transfer.FORMAT     = 1
Transfer.MAX_LENGTH = 16000
-- A real profile unpacks to a few KB, and a short crafted string can unpack to megabytes.
Transfer.MAX_UNPACKED = 65536

-- Which trackers run stays the importer's own choice, and a manual order is one character's quest list.
Transfer.LEFT_OUT = {
    general = { useBlizzardTracker = true, hideQuestieTracker = true, blizzardTrackerOnGamepad = true },
    tracker = { manualOrder = true },
}

-- Migration state, not a setting: every exporting client has converted its offsets, so an import writes it.
Transfer.FORCED = { tracker = { positionInScreenUnits = true } }

-- Settings with no AceDB default, which a diff against the defaults cannot see. docs/test_transfer.lua's E13 fails
-- on a setting read through the names it lists that is neither a default, on this list nor left out.
Transfer.NO_DEFAULT = {
    tracker = {
        titleColorMode         = "string",
        titleColorOverride     = "color",
        finishedObjectiveColor = "color",
        finishedQuestColor     = "color",
        countColorHalf         = "color",
        countColorMost         = "color",
        showQuestTypeTag       = "boolean",
        otherAddonTooltipLines = "boolean",
        todoShowNames          = "boolean",
        todoShowUnfinished     = "boolean",
        todoShowReady          = "boolean",
        todoShowHere           = "boolean",
        todoShowAll            = "boolean",
        todoCountSizeDelta     = "number",
        sectionOrder           = "list:string",
        filters          = { showInstance = "boolean", showOutsideInstance = "boolean",
                             showUnfinished = "boolean", showFinished = "boolean" },
        zoneProgressBar  = { backgroundColor = "color", font = "string", barTexture = "string" },
        progressBar      = { barTexture = "string" },
        scenarioBonusHUD = { backgroundColor = "color" },
    },
}

-- Defaults of {}, which say nothing about their entries.
Transfer.MAPS = {
    tracker = {
        sectionsHidden = { key = "string", value = "boolean" },
        sectionTab     = { key = "string", value = "number" },
        simplifyGroups = { key = "string", value = "boolean" },
    },
}

local function setOf(list)
    local out = {}
    for _, v in ipairs(list) do out[v] = true end
    return out
end

local POINTS = setOf({ "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" })

-- Values SetScale, SetPoint or SetJustifyH raise on, the outline and sound channel kept to their dropdowns' lists,
-- and sizes with no ceiling of their own. Ranges are the controls', the box's its grip's.
Transfer.CHECKS = {
    ["tracker.width"]                     = { min = 200, max = 600 },
    ["tracker.maxHeight"]                 = { min = 100, max = 2000 },
    ["tracker.headerBarHeight"]           = { min = 6, max = 26 },
    ["tracker.blockSpacing"]              = { min = 0, max = 12 },
    ["tracker.cardPadding"]               = { min = 2, max = 14 },
    ["tracker.zoneHeaderIndent"]          = { min = 0, max = 30 },
    ["tracker.scrollBarThumbWidth"]       = { min = 4, max = 16 },
    ["tracker.borderSize"]                = { min = 1, max = 5 },
    ["tracker.fontSize"]                  = { min = 8, max = 24 },
    ["tracker.titleSizeDelta"]            = { min = -6, max = 12 },
    ["tracker.headerSizeDelta"]           = { min = -8, max = 12 },
    ["tracker.zoneHeaderSizeDelta"]       = { min = -8, max = 12 },
    ["tracker.scenarioTextSizeDelta"]     = { min = -4, max = 6 },
    ["tracker.scenarioFontSize"]          = { min = 8, max = 24 },
    ["tracker.scenarioTitleSizeDelta"]    = { min = -4, max = 12 },
    ["tracker.todoCountSizeDelta"]        = { min = -4, max = 8 },
    ["tracker.scale"]                     = { min = 0.7, max = 1.5 },
    ["tracker.zoneProgressBar.scale"]     = { min = 0.5, max = 2.0 },
    ["tracker.scenarioBonusHUD.scale"]    = { min = 0.5, max = 2.0 },
    ["tracker.anchor"]                    = { set = POINTS },
    ["tracker.relativePoint"]             = { set = POINTS },
    ["tracker.zoneProgressBar.point"]     = { set = POINTS },
    ["tracker.zoneProgressBar.relPoint"]  = { set = POINTS },
    ["tracker.scenarioBonusHUD.point"]    = { set = POINTS },
    ["tracker.scenarioBonusHUD.relPoint"] = { set = POINTS },
    ["tracker.scenarioTextAlign"]         = { set = setOf({ "LEFT", "CENTER", "RIGHT" }) },
    ["tracker.fontOutline"]               = { set = setOf({ "", "OUTLINE", "THICKOUTLINE", "MONOCHROME",
                                                            "MONOCHROME, OUTLINE", "MONOCHROME, THICKOUTLINE" }) },
    ["tracker.soundChannel"]              = { set = setOf(ns:GetModule("Media").CHANNELS) },
}

local function copyTable(t)
    local out = {}
    for k, v in pairs(t) do out[k] = (type(v) == "table") and copyTable(v) or v end
    return out
end

local function isColor(d)
    return type(d) == "table" and type(d.r) == "number"
end

-- The Class toggle is stored inside the color, a key no color default holds.
local function diffColor(v, d)
    local out
    for _, c in ipairs(CHANNELS) do
        if v[c] ~= nil and v[c] ~= d[c] then
            out = out or {}
            out[c] = v[c]
        end
    end
    if v.class == true then
        out = out or {}
        out.class = true
    end
    return out
end

-- Only what differs from the defaults, as AceDB decides what to save at logout. The live profile holds
-- every default too, so walking it alone would export everything.
local function diff(live, defaults, noDefault, maps, leftOut)
    local out
    for k, v in pairs(live) do
        local d, val = defaults[k], nil
        if leftOut and leftOut[k] then
            val = nil
        elseif maps and maps[k] then
            if type(v) == "table" and next(v) ~= nil then val = copyTable(v) end
        elseif d == nil then
            local spec = noDefault and noDefault[k]
            if spec ~= nil and type(spec) ~= "table" then
                val = (type(v) == "table") and copyTable(v) or v
            end
        elseif type(d) == "table" then
            if type(v) == "table" then
                if isColor(d) then
                    val = diffColor(v, d)
                else
                    local sub = noDefault and noDefault[k]
                    val = diff(v, d, type(sub) == "table" and sub or nil)
                end
            end
        elseif v ~= d then
            val = v
        end
        if val ~= nil then
            out = out or {}
            out[k] = val
        end
    end
    return out
end

local function libs()
    local S = LibStub and LibStub("AceSerializer-3.0", true)
    local D = LibStub and LibStub("LibDeflate", true)
    return S, D
end

function Transfer:Export()
    local DB = ns:GetModule("DB")
    local db = DB and DB.db
    local S, D = libs()
    if not (db and S and D) then return nil end
    local defaults, profile = DB.defaults.profile, {}
    for _, section in ipairs(SECTIONS) do
        local live = db.profile[section]
        if type(live) == "table" then
            profile[section] = diff(live, defaults[section] or {}, self.NO_DEFAULT[section], self.MAPS[section],
                self.LEFT_OUT[section])
        end
    end
    local raw = S:Serialize({ addon = ADDON, version = ns.VERSION, name = db:GetCurrentProfile(), profile = profile })
    return self.PREFIX .. D:EncodeForPrint(D:CompressDeflate(raw, { level = 9 }))
end

local function finite(n)
    return n == n and n ~= math.huge and n ~= -math.huge
end

local function cleanScalar(v, want)
    if type(v) ~= want or (want == "number" and not finite(v)) then return nil end
    return v
end

local function cleanColor(v)
    if type(v) ~= "table" then return nil end
    local out
    for _, c in ipairs(CHANNELS) do
        if type(v[c]) == "number" and finite(v[c]) then
            out = out or {}
            out[c] = v[c]
        end
    end
    if type(v.class) == "boolean" then
        out = out or {}
        out.class = v.class
    end
    return out
end

-- A whole list or none of it: a list with one entry dropped would read as a different order.
local function cleanList(v)
    if type(v) ~= "table" then return nil end
    local out = {}
    for k, item in pairs(v) do
        if type(k) ~= "number" or not finite(k) or k < 1 or k % 1 ~= 0 or type(item) ~= "string" then return nil end
        out[k] = item
    end
    return next(out) and out or nil
end

local function cleanMap(v, spec)
    if type(v) ~= "table" then return nil end
    local out
    for k, item in pairs(v) do
        if type(k) == spec.key and cleanScalar(item, spec.value) ~= nil then
            out = out or {}
            out[k] = item
        end
    end
    return out
end

-- A color with no default has no channel for AceDB to fill in, and its readers use r, g and b together.
local function cleanWholeColor(v)
    local c = cleanColor(v)
    if c and c.r and c.g and c.b then return c end
    return nil
end

local function cleanBySpec(v, spec)
    if spec == "color" then return cleanWholeColor(v) end
    if spec == "list:string" then return cleanList(v) end
    return cleanScalar(v, spec)
end

local function passes(path, v)
    local c = Transfer.CHECKS[path]
    if not c then return true end
    if c.set then return c.set[v] == true end
    return v >= c.min and v <= c.max
end

-- The same walk as the export's, keeping only a value of the type and shape its default or
-- NO_DEFAULT names, and inside its range or list where CHECKS has one.
local function clean(src, defaults, noDefault, maps, leftOut, path)
    if type(src) ~= "table" then return nil end
    local out
    for k, v in pairs(src) do
        local val
        if type(k) == "string" and not (leftOut and leftOut[k]) then
            local d, here = defaults[k], path .. "." .. k
            if maps and maps[k] then
                val = cleanMap(v, maps[k])
            elseif d == nil then
                local spec = noDefault and noDefault[k]
                if spec ~= nil and type(spec) ~= "table" then val = cleanBySpec(v, spec) end
            elseif type(d) == "table" then
                if isColor(d) then
                    val = cleanColor(v)
                else
                    local sub = noDefault and noDefault[k]
                    val = clean(v, d, type(sub) == "table" and sub or nil, nil, nil, here)
                end
            else
                val = cleanScalar(v, type(d))
            end
            if val ~= nil and not passes(here, val) then val = nil end
        end
        if val ~= nil then
            out = out or {}
            out[k] = val
        end
    end
    return out
end

-- Returns { name, profile } or nil and "empty", "invalid" or "newer". The string is found anywhere in
-- the text, so quote marks or a label pasted around it do not matter.
function Transfer:Decode(text)
    if type(text) ~= "string" then return nil, "empty" end
    text = text:gsub("%s", "")
    if text == "" then return nil, "empty" end
    if #text > self.MAX_LENGTH then return nil, "invalid" end
    local fmt, body = text:match("EQOT(%d+):([%w%(%)]+)")
    fmt = tonumber(fmt)
    if not fmt then return nil, "invalid" end
    if fmt > self.FORMAT then return nil, "newer" end
    if fmt ~= self.FORMAT then return nil, "invalid" end
    local DB = ns:GetModule("DB")
    local S, D = libs()
    if not (DB and DB.defaults and S and D) then return nil, "invalid" end
    local okDecode, packedData = pcall(D.DecodeForPrint, D, body)
    if not okDecode or type(packedData) ~= "string" then return nil, "invalid" end
    local okInflate, raw = pcall(D.DecompressDeflate, D, packedData)
    if not okInflate or type(raw) ~= "string" or #raw > self.MAX_UNPACKED then return nil, "invalid" end
    local okRead, good, data = pcall(S.Deserialize, S, raw)
    if not (okRead and good) or type(data) ~= "table" or data.addon ~= ADDON or type(data.profile) ~= "table" then
        return nil, "invalid"
    end
    local defaults, profile = DB.defaults.profile, {}
    for _, section in ipairs(SECTIONS) do
        profile[section] = clean(data.profile[section], defaults[section] or {}, self.NO_DEFAULT[section],
            self.MAPS[section], self.LEFT_OUT[section], section)
    end
    return { name = (type(data.name) == "string") and data.name or nil, profile = profile }
end

-- The left-out settings come from the profile being replaced, or for a new one the profile the player
-- is on. Only the saved table is written, never the live one, and AceDB saves it as it finds it at logout.
function Transfer:Apply(profile, name)
    local DB = ns:GetModule("DB")
    local db = DB and DB.db
    if not (db and type(profile) == "table" and type(name) == "string") then return end
    local keepFrom = db.profiles[name] or db.profile
    local out = copyTable(profile)
    for _, section in ipairs(SECTIONS) do
        out[section] = out[section] or {}
        local from = keepFrom[section]
        for k in pairs(self.LEFT_OUT[section] or {}) do
            local v
            if type(from) == "table" then v = from[k] end
            if type(v) == "table" then v = copyTable(v) end
            out[section][k] = v
        end
        for k, v in pairs(self.FORCED[section] or {}) do out[section][k] = v end
    end
    db.profiles[name] = out
    if name ~= db:GetCurrentProfile() then db:SetProfile(name) end
    ReloadUI()
end
