-- luacheck: globals C_ChallengeMode C_MythicPlus GetWorldElapsedTimers GetWorldElapsedTime Enum
-- luacheck: globals GetTime issecretvalue wipe CreateFrame UnitIsGroupLeader C_Texture tremove CopyTable
-- luacheck: globals BackdropTemplateMixin SlashCmdList SLASH_EQOT1 SLASH_EQOT2 strtrim
-- luacheck: globals C_Scenario C_ScenarioInfo GetInstanceInfo type
--
-- Unit tests for the Mythic+ key panel, run against the SHIPPED source. Run from the repo root
-- with the game's own Lua:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_mplus.lua
--
-- WHY THIS FILE EXISTS. Nobody could run a real key before the panel shipped, so this file and its
-- battery are the evidence it works there. It loads WHOLE: Data/Keystone.lua (the reads),
-- Data/Providers/Scenarios.lua (the seam to the display, the test sample and the events),
-- UI/MythicPlus.lua (the block), UI/Scenario.lua (the banner swap and the arithmetic around it),
-- UI/Commands.lua (/eqot mplus) and Core/Compat.lua (the capability flag, EVALUATED rather than
-- grepped). The two new files are also loaded once with every retail API missing, as on Classic.
-- Core/DB.lua runs over an AceDB stub for the default, and the box's gate and the TOC order are
-- read by comment-stripped statement.
--
-- The client API stubs copy Blizzard's 12.1.0 signatures (GetMapUIInfo answers six values with the
-- time limit THIRD, GetWorldElapsedTime three with the type third), RAISE on a nil id as the client
-- does, and can be told to raise outright, so a pcall taken away fails. A secret is a unique object
-- that raises on arithmetic, comparison and format, as a Midnight secret does in tainted code, so a
-- guard taken away fails rather than reading a plain equal value. Section A's secrets also answer
-- type() as the value they stand for, as the client's do, so only plain() keeps one out of the key,
-- and each read with a secret checks that none reached it. The timer type comes from an Enum whose
-- ChallengeMode is NOT 1, so a hard-coded 1 fails. Frame stubs raise on any CamelCase key nobody
-- set, replace an anchor on the same point as the client does, and answer IsVisible through their
-- parents.

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
end

local function readFile(rel)
    local fh = assert(io.open(repoFile(rel), "rb"))
    local s = fh:read("*a")
    fh:close()
    return s
end

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end
local function eq(got, want, msg)
    ok(got == want, ("%s: got %s, want %s"):format(msg, tostring(got), tostring(want)))
end
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end
local function has(s, needle) return type(s) == "string" and s:find(needle, 1, true) ~= nil end

local function guard(name, fn)
    local okRun, err = pcall(fn)
    if not okRun then
        fail = fail + 1
        print(("FAIL: %s raised: %s"):format(name, tostring(err)))
    end
end

local function setGlobal(name, v) _G[name] = v end

-- Built in pieces: the tooltip gate counts this word across every committed Lua file
local TIP = "Game" .. "Tooltip"

-- ---------------------------------------------------------------------------------------------
-- The world
-- ---------------------------------------------------------------------------------------------

local NOW = 1000
GetTime = function() return NOW end

-- A secret is its own object, so marking one never marks a plain value equal to it. One made for
-- a number, a string or a boolean answers type() as that, as the client's secrets do, so a type
-- test in production cannot pass for its secret check.
local SECRETS = setmetatable({}, { __mode = "k" })
local SECRET_TYPES = setmetatable({}, { __mode = "k" })
local function refuse() error("a secret value was used") end
local SECRET_MT = { __add = refuse, __sub = refuse, __mul = refuse, __div = refuse, __lt = refuse,
                    __le = refuse, __concat = refuse, __unm = refuse, __len = refuse,
                    __index = refuse, __tostring = function() return "<secret>" end }
local function secret(kind)
    local s = setmetatable({}, SECRET_MT)
    SECRETS[s] = true
    SECRET_TYPES[s] = kind
    return s
end
issecretvalue = function(v) return v ~= nil and SECRETS[v] == true end
local rawType = type
type = function(v) return SECRET_TYPES[v] or rawType(v) end

wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
tremove = table.remove
local function copy(t)
    local o = {}
    for k, v in pairs(t) do o[k] = (type(v) == "table") and copy(v) or v end
    return o
end
CopyTable = copy
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- 7 rather than Blizzard's 1, so only a build that reads the enum finds the timer
local ENUM = { WorldElapsedTimerTypes = { None = 0, ChallengeMode = 7, ProvingGround = 2 } }
Enum = ENUM

local W  -- the world state each case sets
local calls

local function resetWorld()
    W = {
        mapID = 2648, mapRaises = false,
        maps = {
            [2648] = { name = "The Rookery", limit = 1799 },
            [2649] = { name = "Priory of the Sacred Flame", limit = 1950 },
            [2650] = { name = "Zero Limit", limit = 0 },
        },
        timers = { 3 },
        timerInfo = { [3] = { elapsed = 400, kind = 7 } },
        level = 12, affixes = { 9, 147, 10 }, energized = true, keyRaises = false,
        deaths = 2, lost = 10, deathRaises = false,
        affixInfo = {
            [9]   = { "Tyrannical", "Bosses are tougher.", 236401 },
            [10]  = { "Fortified", "Trash is tougher.", 463829 },
            [147] = { "Xal'atath's Guile", "Guile.", 5927634 },
            [152] = { "Challenger's Peril", "Peril.", 5927635 },
            [160] = { "Devour", "Devour.", 5927636 },
        },
        mapTable = { 2649, 2648 },
        current = { { id = 160, seasonID = 15 }, { id = 9, seasonID = 15 } },
        raise = {},
    }
    calls = { affix = {}, elapsed = 0 }
    Enum = ENUM
end

C_ChallengeMode = {
    GetActiveChallengeMapID = function()
        if W.mapRaises then error("map read raised") end
        return W.mapID
    end,
    GetMapUIInfo = function(mapID)
        if mapID == nil then error("GetMapUIInfo: nil mapID") end
        if W.raise.map then error("map info raised") end
        local m = W.maps[mapID]
        if not m then return nil end
        return m.name, mapID, m.limit, 525134, 525135, mapID
    end,
    GetActiveKeystoneInfo = function()
        if W.keyRaises then error("keystone read raised") end
        return W.level, W.affixes, W.energized
    end,
    GetDeathCount = function()
        if W.deathRaises then error("death read raised") end
        return W.deaths, W.lost
    end,
    GetAffixInfo = function(id)
        if id == nil then error("GetAffixInfo: nil id") end
        if W.raise.affix then error("affix read raised") end
        calls.affix[id] = (calls.affix[id] or 0) + 1
        local a = W.affixInfo[id]
        if not a then return nil end
        return a[1], a[2], a[3]
    end,
    GetMapTable = function()
        if W.raise.mapTable then error("map table raised") end
        return W.mapTable
    end,
}
local CM = C_ChallengeMode
local MP_API = { GetCurrentAffixes = function()
    if W.raise.current then error("current affixes raised") end
    return W.current
end }
C_MythicPlus = MP_API

local function timersFn()
    if W.raise.timers then error("timer list raised") end
    return unpack(W.timers)
end
local function elapsedFn(id)
    if id == nil then error("GetWorldElapsedTime: nil id") end
    if W.raise.elapsed then error("elapsed read raised") end
    calls.elapsed = calls.elapsed + 1
    local t = W.timerInfo[id]
    if not t then return "", 0, 0 end
    return "Timer", t.elapsed, t.kind
end
GetWorldElapsedTimers = timersFn
GetWorldElapsedTime = elapsedFn

-- ---------------------------------------------------------------------------------------------
-- Frames
-- ---------------------------------------------------------------------------------------------

local FONTS = {
    GameFontNormal          = { "NORMAL.TTF", 12 },
    GameFontNormalMed2      = { "MED2.TTF", 14 },
    GameFontHighlightHuge   = { "HUGE.TTF", 20 },
    GameFontHighlightLarge  = { "LARGE.TTF", 16 },
    GameFontHighlightSmall  = { "SMALL.TTF", 10 },
    GameFontHighlightSmall2 = { "SMALL2.TTF", 11 },
    GameFontNormalSmall     = { "NSMALL.TTF", 10 },
    GameFontNormalLarge     = { "NLARGE.TTF", 16 },
    Game18Font              = { "G18.TTF", 18 },
    ObjectiveTrackerHeaderFont = { "OTH.TTF", 15 },
}
-- What the Media stub's criteria font sets, a file no font object above uses
local CRIT_FONT = { "CRIT.TTF", 17, "" }
local function installFonts(except)
    for name in pairs(FONTS) do
        setGlobal(name, (except == nil or not except[name]) and { name = name } or nil)
    end
end

local STR_H = 12

-- CamelCase keys are methods or children, which the client either has or the code built. A
-- lowercase or underscore key is a field production stores on its own frames, and reads nil
-- until it has.
local function strict(obj, kind)
    return setmetatable(obj, { __index = function(_, k)
        if type(k) == "string" and k:match("^[A-Z]") then
            error(("%s stub has no %s"):format(kind, k), 2)
        end
        return nil
    end })
end

local frames = {}
local regions = {}

local function region(kind, parent)
    local o = { _type = kind, _parent = parent, _points = {}, _shown = true, _w = 0, _h = 0 }
    -- Stored the way the client resolves it: a left-out frame is the parent, a left-out relative
    -- point is the point itself, and an anchor set again on the same point replaces it
    function o:SetPoint(p, rel, relP, x, y)
        if type(rel) == "number" then rel, relP, x, y = nil, nil, rel, relP end
        local a = { p = p, rel = rel or self._parent, relP = relP or p, x = x or 0, y = y or 0 }
        for i, old in ipairs(self._points) do
            if old.p == p then self._points[i] = a return end
        end
        self._points[#self._points + 1] = a
    end
    function o:ClearAllPoints() self._points, self._allPoints = {}, nil end
    function o:SetAllPoints(rel)
        rel = rel or self._parent
        self:ClearAllPoints()
        self._allPoints = rel
        self:SetPoint("TOPLEFT", rel, "TOPLEFT", 0, 0)
        self:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0)
    end
    function o:SetSize(w, h) self._w, self._h = w, h end
    function o:SetWidth(w) self._w = w end
    function o:SetHeight(h) self._h = h end
    function o:GetWidth() return self._w end
    function o:GetHeight() return self._h end
    function o:Show() self._shown = true end
    function o:Hide() self._shown = false end
    function o:IsShown() return self._shown end
    function o:IsVisible()
        local f = self
        while f do
            if not f._shown then return false end
            f = f._parent
        end
        return true
    end
    function o:SetShown(v)
        if type(v) ~= "boolean" then error("SetShown wants a boolean, got " .. type(v)) end
        self._shown = v
    end
    function o:GetParent() return self._parent end
    function o:SetParent(p) self._parent = p end
    return o
end

local function texture(parent, layer, sub)
    local t = region("Texture", parent)
    t._layer, t._sub = layer, sub
    function t:SetAtlas(a, size)
        if type(size) ~= "boolean" then error("SetAtlas wants a boolean size flag") end
        self._atlas, self._atlasSize = a, size
    end
    function t:SetTexture(v) self._texture = v; self._color = nil end
    function t:SetTexCoord(l, r, top, b) self._tc = { l, r, top, b } end
    function t:SetVertexColor(r, g, b, a) self._tint = { r, g, b, a } end
    function t:SetColorTexture(r, g, b, a) self._color = { r, g, b, a }; self._texture = "color" end
    function t:SetBlendMode(m) self._blend = m end
    regions[#regions + 1] = t
    return strict(t, "Texture")
end

local function fontString(parent, layer, template)
    if template and not _G[template] then
        error("CreateFontString: unknown font object " .. tostring(template))
    end
    local fs = region("FontString", parent)
    fs._layer, fs._template, fs._text = layer, template, ""
    local f = template and FONTS[template]
    fs._font = f and { f[1], f[2], "" } or nil
    function fs:SetText(t) self._text = t end
    function fs:GetText() return self._text end
    function fs:SetFormattedText(fmt, ...) self._text = fmt:format(...) end
    function fs:SetTextColor(r, g, b, a) self._color = { r, g, b, a } end
    function fs:SetJustifyH(v) self._justify = v end
    function fs:SetJustifyV(v) self._justifyV = v end
    function fs:SetSpacing(v) self._spacing = v end
    function fs:SetWordWrap(v) self._wrap = v end
    function fs:SetFont(file, size, flags) self._font = { file, size, flags } end
    function fs:GetFont()
        if not self._font then return nil end
        return self._font[1], self._font[2], self._font[3]
    end
    function fs:SetFontObject(o) self._fontObject = o end
    function fs:GetStringHeight()
        if self._text == nil or self._text == "" then return 0 end
        return STR_H
    end
    regions[#regions + 1] = fs
    return strict(fs, "FontString")
end

CreateFrame = function(kind, name, parent, template)
    local f = region(kind, parent)
    f._name, f._template, f._scripts, f._mouse = name, template, {}, false
    function f:CreateTexture(_, layer, _, sub) return texture(self, layer, sub) end
    function f:CreateFontString(_, layer, tmpl) return fontString(self, layer, tmpl) end
    function f:SetScript(ev, fn) self._scripts[ev] = fn end
    function f:GetScript(ev) return self._scripts[ev] end
    function f:EnableMouse(v) self._mouse = v end
    function f:IsMouseEnabled() return self._mouse end
    if kind == "StatusBar" then
        function f:SetMinMaxValues(lo, hi) self._min, self._max = lo, hi end
        function f:SetValue(v) self._value = v end
    end
    if template == "BackdropTemplate" then
        function f:SetBackdrop(b) self._backdrop = b end
    end
    if kind == TIP then
        f._lines, f._shown = {}, false
        function f:SetOwner(owner, anchor) self._owner, self._anchor = owner, anchor; self._lines = {} end
        function f:SetText(t, r, g, b, a, wrap) self._lines = { t }; self._title = { r, g, b, a, wrap } end
        function f:AddLine(t, r, g, b, wrap)
            self._lines[#self._lines + 1] = t
            self._wraps = self._wraps or {}
            self._wraps[#self._lines] = { r, g, b, wrap }
        end
    end
    frames[#frames + 1] = f
    return strict(f, kind)
end
BackdropTemplateMixin = {}

UnitIsGroupLeader = function(unit)
    if unit ~= "player" then error("UnitIsGroupLeader asked for " .. tostring(unit)) end
    return W.leader == true
end

local FILL_INFO = { file = 4567, leftTexCoord = 0.25, rightTexCoord = 0.75,
                    topTexCoord = 0.5, bottomTexCoord = 0.625, width = 207, height = 13 }
local fillInfo = FILL_INFO
local atlasStreamed = true
local TEX = { GetAtlasInfo = function(name)
    if name == "ChallengeMode-TimerFill" then return atlasStreamed and fillInfo or nil end
    return { file = 1, width = 10, height = 10 }
end }
C_Texture = TEX

-- ---------------------------------------------------------------------------------------------
-- The addon around it
-- ---------------------------------------------------------------------------------------------

local function newNS(flags)
    local ns = { L = setmetatable({}, { __index = function(_, k) return k end }),
                 Has = flags or { ChallengeTimer = true, Atlas = true }, printed = {}, standing = {} }
    local mods = {}
    ns._mods = mods
    function ns:RegisterModule(n, t)
        if self ~= ns then error("RegisterModule called with a dot") end
        mods[n] = t
        return t
    end
    function ns:GetModule(n)
        if self ~= ns then error("GetModule called with a dot") end
        return mods[n]
    end
    function ns:Print(s) self.printed[#self.printed + 1] = s end
    function ns:UsesBlizzardTracker() return self._blizzard == true end
    function ns:IsStandingDown(name)
        if self ~= ns then error("IsStandingDown called with a dot") end
        self.standing[#self.standing + 1] = name
        return false
    end
    return ns, mods
end

local function method(owner, name)
    return function(self, ...)
        if self ~= owner then error(name .. " called with a dot or on the wrong object") end
        return owner["_" .. name](self, ...)
    end
end

local function newUtil()
    local tip = CreateFrame(TIP, "EQOTTooltip", nil, TIP .. "Template")
    local Util = { missingAtlas = {} }
    function Util.AtlasExists(a) return a ~= nil and a ~= "" and not Util.missingAtlas[a] end
    function Util.SafeSetAtlas(tex, atlas, useAtlasSize)
        tex:SetTexCoord(0, 1, 0, 1)
        if Util.AtlasExists(atlas) then
            tex:SetAtlas(atlas, useAtlasSize and true or false)
            return true
        end
        tex:SetTexture(nil)
        return false
    end
    function Util.Tooltip() return tip end
    Util._tip = tip
    return Util
end

local function newMedia()
    -- Each call is logged against its font string, and the ones that set a font really set one,
    -- so a font string handed the wrong one no longer keeps the font it was built with
    local M = { banner = {}, bshadow = {}, crit = {}, tshadow = {}, log = {} }
    -- The real Media returns on a nil font string, so the stub does too
    local function note(fs, what)
        if not fs then return false end
        local l = M.log[fs] or {}
        M.log[fs] = l
        l[#l + 1] = what
        return true
    end
    M._ApplyScenarioFont = function(self, fs, base)
        self.banner[#self.banner + 1] = { fs = fs, base = base }
        if note(fs, "ApplyScenarioFont") and base and base[1] and base[2] then
            fs:SetFont(base[1], base[2] + 3, base[3] or "")
        end
    end
    M._ApplyScenarioShadow = function(self, fs)
        self.bshadow[#self.bshadow + 1] = fs
        note(fs, "ApplyScenarioShadow")
    end
    M._ApplyScenarioCriteriaFont = function(self, fs)
        self.crit[#self.crit + 1] = fs
        if note(fs, "ApplyScenarioCriteriaFont") then fs:SetFont(CRIT_FONT[1], CRIT_FONT[2], CRIT_FONT[3]) end
    end
    M._ApplyTextShadow = function(self, fs)
        self.tshadow[#self.tshadow + 1] = fs
        note(fs, "ApplyTextShadow")
    end
    M._ApplyFont = function(_, fs, delta)
        if note(fs, "ApplyFont") then fs:SetFont("TRACKER.TTF", 13 + (delta or 0), "") end
    end
    M._ProgressBarHeight = function() return 16 end
    M._ApplyProgressBar = function() end
    for _, n in ipairs({ "ApplyScenarioFont", "ApplyScenarioShadow", "ApplyScenarioCriteriaFont",
                         "ApplyTextShadow", "ApplyFont", "ProgressBarHeight", "ApplyProgressBar" }) do
        M[n] = method(M, n)
    end
    return M
end

local function newDB(cfg)
    local DB = { cfg = cfg }
    function DB:Tracker()
        if self ~= DB then error("DB.Tracker called with a dot") end
        return self.cfg
    end
    return DB
end

local function inList(list, x)
    for i = 1, #list do if list[i] == x then return true end end
    return false
end

-- ---------------------------------------------------------------------------------------------
-- A. Data/Keystone.lua
-- ---------------------------------------------------------------------------------------------

local function loadKeystone(flags)
    local ns, mods = newNS(flags)
    local chunk = assert(loadfile(repoFile("Data/Keystone.lua")))
    chunk("EQObjectiveTracker", ns)
    return mods.Keystone, ns
end

-- Every field the panel and the status line draw from, so a secret shows wherever it lands
local KEY_FIELDS = { "mapID", "mapName", "level", "timeLimit", "plusTwo", "plusThree", "elapsed",
                     "elapsedAt", "deaths", "timeLost", "depleted" }
local AFFIX_FIELDS = { "id", "name", "description", "icon" }
local function secretsIn(key)
    local found = {}
    for _, f in ipairs(KEY_FIELDS) do
        if issecretvalue(key[f]) then found[#found + 1] = f end
    end
    for i = 1, key.affixN do
        for _, f in ipairs(AFFIX_FIELDS) do
            if issecretvalue(key.affixes[i][f]) then found[#found + 1] = "affix " .. f end
        end
    end
    return table.concat(found, ",")
end

guard("A. reads", function()
    resetWorld()
    local K = loadKeystone()
    ok(K ~= nil, "Data/Keystone.lua registers the Keystone module")
    eq(K:DebugLine(), "mythic+: not read yet", "the line before any read")

    local key = K:Read()
    ok(key.active == true, "a running key reads active")
    eq(key.mapID, 2648, "map id")
    eq(key.mapName, "The Rookery", "map name, the first value GetMapUIInfo answers")
    eq(key.timeLimit, 1799, "time limit, the THIRD value GetMapUIInfo answers")
    eq(key.level, 12, "keystone level")
    eq(key.elapsed, 400, "elapsed seconds from the challenge timer")
    eq(key.elapsedAt, 1000, "stamped at the read")
    ok(near(key.plusTwo, 1439.2), "+2 is 80 percent of the limit, got " .. tostring(key.plusTwo))
    ok(near(key.plusThree, 1079.4), "+3 is 60 percent of the limit, got " .. tostring(key.plusThree))
    eq(key.deaths, 2, "deaths")
    eq(key.timeLost, 10, "time lost")
    eq(key.depleted, false, "an energized key is not depleted")
    eq(key.affixN, 3, "three affixes")
    eq(key.affixes[1] and key.affixes[1].id, 9, "affix order kept (1)")
    eq(key.affixes[2] and key.affixes[2].id, 147, "affix order kept (2)")
    eq(key.affixes[3] and key.affixes[3].name, "Fortified", "affix name")
    eq(key.affixes[1] and key.affixes[1].description, "Bosses are tougher.", "affix description")
    eq(key.affixes[2] and key.affixes[2].icon, 5927634, "affix icon, the third value")
    ok(key.test == nil, "a real read is not a test")

    local line = K:DebugLine()
    ok(has(line, "mythic+: +12 The Rookery (map 2648)"), "status names the key: " .. line)
    ok(has(line, "timer 3, 400s of 1799s, +2 by 1439s, +3 by 1079s"), "status timer: " .. line)
    ok(has(line, "deaths 2, 10s lost"), "status deaths: " .. line)
    ok(has(line, "affixes 9,147,10"), "status affixes: " .. line)
    ok(has(line, "depleted no"), "status depleted: " .. line)
    ok(not has(line, "TEST"), "a real read is not marked TEST")
    ok(not has(line, "secret"), "nothing secret named")
    NOW = 1012.6
    line = K:DebugLine()
    ok(has(line, "timer 3, 412s of 1799s"), "the line counts on from the reading, as the clock does: " .. line)
    NOW = 1000

    W.affixes = {}
    K:Read()
    ok(has(K:DebugLine(), "affixes none"), "no affixes reads none: " .. K:DebugLine())
    W.level = "12"
    eq(K:Read().level, nil, "a level that is not a number is not used")
end)

guard("A. affix cache", function()
    resetWorld()
    local K = loadKeystone()
    K:Read()
    K:Read()
    eq(calls.affix[9], 1, "a named affix is asked once across reads")
    W.affixInfo[11] = nil
    W.affixes = { 11, 9 }
    K:Read()
    K:Read()
    eq(calls.affix[11], 2, "an affix with no name yet is asked again on every read")
    local key = K:Read()
    eq(key.affixN, 1, "the unnamed affix is left out")
    eq(key.affixes[1].id, 9, "and the named one kept")
    eq(key.affixes[2], nil, "the shorter list leaves no tail behind")

    W.affixes = { 9, 10, 147, 152, 160 }
    key = K:Read()
    eq(key.affixN, 4, "at most four affixes")
    eq(key.affixes[5], nil, "the fifth is not reachable")

    W.affixes = secret()
    key = K:Read()
    eq(key.affixN, 0, "a secret affix list reads as none")
    ok(has(K:DebugLine(), "secret: affixes"), "and is named: " .. K:DebugLine())
    W.affixes = { 9, secret("number") }
    key = K:Read()
    eq(key.affixN, 1, "a secret affix id is skipped")
    eq(key.affixes[1].id, 9, "the plain one kept")
    ok(has(K:DebugLine(), "secret: affix id"), "and named")
    eq(secretsIn(key), "", "no secret affix id reaches the key")

    -- A raising affix read is skipped and not cached, so it is named once it answers. Fresh ids
    -- throughout, since an affix read once is cached.
    W.affixInfo[170] = { "Spite", "Spite.", 5927640 }
    W.affixes = { 170 }
    W.raise.affix = true
    key = K:Read()
    eq(key.affixN, 0, "a raising affix read draws no affix")
    W.raise.affix = nil
    key = K:Read()
    eq(key.affixN, 1, "and the affix is read once it answers")
    eq(key.affixes[1].name, "Spite", "with its own name, not the error text")

    -- Secret parts of an affix
    W.affixInfo[171] = { secret("string"), "Devour.", 5927636 }
    W.affixes = { 171 }
    key = K:Read()
    eq(key.affixN, 0, "a secret affix name drops the affix")
    ok(has(K:DebugLine(), "secret: affix name"), "named affix name")
    eq(secretsIn(key), "", "no secret affix name reaches the key")
    W.affixInfo[161] = { "Bolt", "Bolt.", secret("number") }
    W.affixes = { 161 }
    key = K:Read()
    eq(key.affixN, 1, "a secret icon keeps the affix")
    eq(key.affixes[1].icon, nil, "with no icon")
    eq(key.affixes[1].description, "Bolt.", "and its own description")
    ok(has(K:DebugLine(), "secret: affix icon"), "and names the secret: " .. K:DebugLine())
    eq(secretsIn(key), "", "no secret affix icon reaches the key")
    W.affixInfo[164] = { "Sanguine", secret("string"), 5927641 }
    W.affixes = { 164 }
    key = K:Read()
    eq(key.affixN, 1, "a secret description keeps the affix")
    eq(key.affixes[1].name, "Sanguine", "with its name")
    eq(key.affixes[1].description, nil, "and no description")
    eq(key.affixes[1].icon, 5927641, "and its icon")
    ok(has(K:DebugLine(), "secret: affix description"), "and names the secret: " .. K:DebugLine())
    eq(secretsIn(key), "", "no secret affix description reaches the key")
    W.affixInfo[162] = { "Ward", "Ward.", "Interface\\Icons\\Ward" }
    W.affixes = { 162 }
    eq(K:Read().affixes[1].icon, "Interface\\Icons\\Ward", "an icon path is kept")
    W.affixInfo[163] = { "Rot", "Rot.", true }
    W.affixes = { 163 }
    eq(K:Read().affixes[1].icon, nil, "an icon that is neither a file id nor a path is dropped")
end)

guard("A. refusals", function()
    resetWorld()
    local K = loadKeystone({ ChallengeTimer = false })
    eq(K:Read().active, false, "no API reads inactive")
    eq(K:DebugLine(), "mythic+: not on this client", "and says why")

    K = loadKeystone()
    W.mapID = nil
    eq(K:Read().active, false, "no key reads inactive")
    eq(K:DebugLine(), "mythic+: no key running", "no key")

    resetWorld()
    W.mapRaises = true
    eq(K:Read().active, false, "a raising map read is inactive")
    eq(K:DebugLine(), "mythic+: map read raised", "raising map read")

    resetWorld()
    W.mapID = secret("number")
    eq(K:Read().active, false, "a secret map id is inactive")
    ok(has(K:DebugLine(), "secret: map id"), "and named: " .. K:DebugLine())
    eq(secretsIn(K:Read()), "", "no secret map id reaches the key")
    W.mapID = 2648
    eq(K:Read().active, true, "the next plain read is active")
    ok(not has(K:DebugLine(), "secret"), "and names no secret from the last read: " .. K:DebugLine())
    W.mapID = nil
    eq(K:Read().active, false, "an active read followed by no key reads inactive")

    resetWorld()
    W.timerInfo[3].kind = 2
    eq(K:Read().active, false, "a proving grounds timer is not a key timer")
    eq(K:DebugLine(), "mythic+: no challenge timer running", "no challenge timer")

    resetWorld()
    W.timerInfo[3].kind = 1
    eq(K:Read().active, false, "type 1 is refused while the enum says 7")

    resetWorld()
    W.timers = {}
    eq(K:Read().active, false, "no timers at all")

    resetWorld()
    W.raise.timers = true
    eq(K:Read().active, false, "a raising timer list is inactive")
    eq(K:DebugLine(), "mythic+: no challenge timer running", "and reads as no timer")

    resetWorld()
    W.raise.elapsed = true
    eq(K:Read().active, false, "a raising elapsed read is inactive")

    resetWorld()
    W.maps[2648].limit = 0
    eq(K:Read().active, false, "a zero time limit is inactive")
    eq(K:DebugLine(), "mythic+: no time limit for this map", "zero limit")
    W.maps[2648] = nil
    eq(K:Read().active, false, "an unknown map is inactive")

    resetWorld()
    W.raise.map = true
    eq(K:Read().active, false, "a raising map info read is inactive")

    resetWorld()
    W.maps[2648].limit = "1850"
    local okRead, read = pcall(K.Read, K)
    ok(okRead, "a time limit that is not a number does not raise: " .. tostring(read))
    ok(okRead and read.active == false, "and is inactive")

    resetWorld()
    W.timerInfo[3].elapsed = secret("number")
    eq(K:Read().active, false, "a secret elapsed figure finds no timer")
    ok(has(K:DebugLine(), "secret: elapsed"), "and is named")
    eq(secretsIn(K:Read()), "", "no secret elapsed figure reaches the key")

    resetWorld()
    W.timers = { secret("number") }
    eq(K:Read().active, false, "a secret timer id finds no timer")
    ok(has(K:DebugLine(), "secret: timer id"), "and is named")

    resetWorld()
    W.timerInfo[3].kind = secret("number")
    eq(K:Read().active, false, "a secret timer type finds no timer")
    ok(has(K:DebugLine(), "secret: timer type"), "and is named")

    resetWorld()
    W.maps[2648].limit = secret("number")
    eq(K:Read().active, false, "a secret time limit is inactive")
    ok(has(K:DebugLine(), "secret: time limit"), "and is named")
    eq(secretsIn(K:Read()), "", "no secret time limit reaches the key")

    -- Two secrets in one read: the line names the first one met
    resetWorld()
    W.timers = { secret("number"), 3 }
    W.maps[2648].limit = secret("number")
    K:Read()
    ok(has(K:DebugLine(), "secret: timer id"), "the first secret is the one named: " .. K:DebugLine())
end)

guard("A. secrets inside an active read", function()
    resetWorld()
    local K = loadKeystone()
    W.maps[2648].name = secret("string")
    local key = K:Read()
    ok(key.active, "a secret map name still draws")
    eq(key.mapName, nil, "with no name")
    ok(has(K:DebugLine(), "secret: map name"), "and is named")
    eq(secretsIn(key), "", "no secret map name reaches the key")

    resetWorld()
    W.level = secret("number")
    key = K:Read()
    ok(key.active, "a secret level still draws")
    eq(key.level, nil, "with no level")
    ok(has(K:DebugLine(), "secret: level"), "and is named")
    eq(secretsIn(key), "", "no secret level reaches the key")

    resetWorld()
    W.deaths = secret("number")
    key = K:Read()
    eq(key.deaths, 0, "a secret death count reads 0")
    ok(has(K:DebugLine(), "secret: deaths"), "and is named")
    eq(secretsIn(key), "", "no secret death count reaches the key")

    resetWorld()
    W.lost = secret("number")
    key = K:Read()
    eq(key.timeLost, 0, "a secret time lost reads 0")
    ok(has(K:DebugLine(), "secret: time lost"), "and is named")
    eq(secretsIn(key), "", "no secret time lost reaches the key")
end)

guard("A. timer selection", function()
    resetWorld()
    local K = loadKeystone()
    W.timers = { 1, 5, 3 }
    W.timerInfo[1] = { elapsed = 50, kind = 2 }
    W.timerInfo[5] = { elapsed = 60, kind = 0 }
    local key = K:Read()
    ok(key.active, "the challenge timer is found past two others")
    eq(key.elapsed, 400, "its own elapsed figure, not the first timer's")
    ok(has(K:DebugLine(), "timer 3,"), "its id")

    Enum = nil
    W.timerInfo[3].kind = 1
    key = K:Read()
    ok(key.active, "with no enum, type 1 is the challenge timer")
    eq(key.elapsed, 400, "and it is that timer, not the proving grounds one before it")
    ok(has(K:DebugLine(), "timer 3,"), "timer 3 named with no enum")
    Enum = ENUM
end)

guard("A. stopped timers", function()
    resetWorld()
    local K = loadKeystone()
    K:TimerStopped(3)
    eq(K:Read().active, false, "a stopped timer is skipped")
    K:TimerStarted(3)
    eq(K:Read().active, true, "and found again once started")
    K:TimerStopped(3)
    K:Started()
    eq(K:Read().active, true, "a new key or a loading screen starts every timer fresh")
    K:Read()
    K:Finished()
    eq(K:Read().active, false, "a finished run stops the timer it was read from")
    K:TimerStarted(4)
    eq(K:Read().active, false, "another timer starting does not restart it")
    K:Started()
    K:TimerStopped(nil)
    K:TimerStarted(nil)
    eq(K:Read().active, true, "a nil id changes nothing")
    -- The plain 3 marked secret for one call: an event id is checked as the reads are
    SECRETS[3] = true
    K:TimerStopped(3)
    SECRETS[3] = nil
    eq(K:Read().active, true, "a secret stop id stops nothing")
    K:TimerStopped(3)
    SECRETS[3] = true
    K:TimerStarted(3)
    SECRETS[3] = nil
    eq(K:Read().active, false, "and a secret start id clears no stop")
    K:Started()
    K:Read()
    K:TimerStarted(3)
    K:Finished()
    eq(K:Read().active, false, "a finish right after a start, with no read between, still stops the run's timer")
    K:Started()
    W.timers = { 3, 8 }
    W.timerInfo[8] = { elapsed = 90, kind = 7 }
    K:TimerStopped(3)
    local key = K:Read()
    eq(key.elapsed, 90, "a stopped timer is passed over, not the end of the walk")
    W.timers = { 3 }
    K:SetTest("test")
    K:SetTest(nil)
    eq(K:Read().active, false, "a sample key on and off restarts no stopped timer")

    -- A reset after a reload, before any repaint has read the timer again
    K:Started()
    eq(K:Read().active, true, "the timer runs again after a loading screen")
    K:Finished()
    K:Started()
    K:Finished()
    eq(K:Read().active, false, "a second finish after a loading screen stops the timer last read")
end)

guard("A. stamp and rebase", function()
    resetWorld()
    NOW = 1000
    local K = loadKeystone()
    local key = K:Read()
    eq(key.elapsedAt, 1000, "first stamp")
    NOW = 1000.7
    key = K:Read()
    eq(key.elapsedAt, 1000, "the same reading is not restamped")
    eq(key.elapsed, 400, "and keeps its figure")
    W.timerInfo[3].elapsed = 401
    NOW = 1001.2
    key = K:Read()
    eq(key.elapsedAt, 1001.2, "a moved reading is restamped")
    eq(key.elapsed, 401, "with the new figure")
    W.timers = { 4 }
    W.timerInfo[4] = { elapsed = 401, kind = 7 }
    NOW = 1002
    key = K:Read()
    eq(key.elapsedAt, 1002, "a different timer is restamped even at the same figure")

    -- The key's countdown lists the timer at 0, and the real start reads 0 again
    resetWorld()
    K = loadKeystone()
    W.timerInfo[3].elapsed = 0
    NOW = 2000
    key = K:Read()
    eq(key.elapsedAt, 2000, "the countdown stamps 0")
    NOW = 2010
    K:TimerStarted(3)
    key = K:Read()
    eq(key.elapsedAt, 2010, "a timer start restamps the same 0")
    NOW = 2020
    K:Started()
    key = K:Read()
    eq(key.elapsedAt, 2020, "and so does a new key or a loading screen")
    NOW = 2021
    key = K:Read()
    eq(key.elapsedAt, 2020, "but a plain re-read after it does not")
    NOW = 2030
    K:TimerStarted(nil)
    eq(K:Read().elapsedAt, 2030, "a start with no id still restamps")
    NOW = 2040
    SECRETS[3] = true
    K:TimerStarted(3)
    SECRETS[3] = nil
    eq(K:Read().elapsedAt, 2040, "and so does one with a secret id")
    NOW = 2045
    K:TimerStopped(8)
    eq(K:Read().elapsedAt, 2040, "another timer stopping is not a new reading of this one")
    NOW = 1000
end)

guard("A. depleted and deaths", function()
    resetWorld()
    local K = loadKeystone()
    W.energized = false
    eq(K:Read().depleted, true, "a plain false is depleted")
    ok(has(K:DebugLine(), "depleted yes"), "status says so")
    W.energized = nil
    eq(K:Read().depleted, false, "nil is not called depleted")
    W.energized = secret("boolean")
    eq(K:Read().depleted, false, "a secret is not called depleted")
    ok(has(K:DebugLine(), "secret: energized"), "and is named")
    eq(secretsIn(K:Read()), "", "no secret depleted flag reaches the key")

    resetWorld()
    W.keyRaises = true
    local key = K:Read()
    ok(key.active, "a raising keystone read still draws the timer")
    eq(key.level, nil, "with no level")
    eq(key.affixN, 0, "and no affixes")
    eq(key.depleted, false, "and not depleted")

    resetWorld()
    W.deathRaises = true
    key = K:Read()
    ok(key.active, "a raising death read still draws")
    eq(key.deaths, 0, "deaths 0")
    eq(key.timeLost, 0, "time lost 0")
    resetWorld()
    local saved = CM.GetDeathCount
    CM.GetDeathCount = nil
    key = K:Read()
    ok(key.active, "a client with no death count still draws")
    eq(key.deaths, 0, "deaths 0 without the call")
    CM.GetDeathCount = saved
    W.deaths, W.lost = 5, 25
    key = K:Read()
    eq(key.deaths, 5, "deaths read fresh on every read")
    eq(key.timeLost, 25, "time lost read fresh")
end)

guard("A. idle", function()
    resetWorld()
    local K = loadKeystone()
    K:Read()
    local key = K:Idle("no scenario running")
    eq(key.active, false, "idle is inactive")
    eq(K:DebugLine(), "mythic+: no scenario running", "and the line says why, not the last key")
    W.mapID = secret("number")
    K:Read()
    K:Idle("switched off")
    eq(K:DebugLine(), "mythic+: switched off", "idle forgets a secret too")
    K:SetTest("test")
    K:ReadTest()
    eq(K:Idle("x").test, nil, "and the test mark")
end)

guard("A. test key", function()
    resetWorld()
    NOW = 1990
    local K = loadKeystone()
    W.level = secret("number")
    K:Read()
    NOW = 2000
    ok(has(K:DebugLine(), "secret: level"), "the real read before the test names its secret")
    eq(K:ReadTest().active, false, "no test, nothing")
    eq(K:IsTesting(), false, "not testing")
    eq(K:TestMode(), nil, "no mode")
    eq(K:SetTest("bogus"), false, "an unknown mode is off")
    eq(K:SetTest("test"), true, "test on")
    eq(K:TestMode(), "test", "mode test")
    local key = K:ReadTest()
    ok(key.active and key.test ~= nil, "a test key is active and marked")
    eq(key.mapID, 2649, "the first map the client lists")
    eq(key.mapName, "Priory of the Sacred Flame", "its name")
    eq(key.timeLimit, 1950, "its limit")
    eq(key.level, 12, "sample level")
    eq(key.deaths, 3, "sample deaths")
    eq(key.timeLost, 15, "sample time lost")
    eq(key.depleted, false, "test is not depleted")
    ok(near(key.elapsed, 1950 * 0.6 - 20), "starts twenty seconds before +3 runs out, got " .. tostring(key.elapsed))
    eq(key.elapsedAt, 2000, "stamped when the test began")
    eq(key.affixN, 2, "the client's current affixes")
    eq(key.affixes[1].id, 160, "read through their id field")
    ok(has(K:DebugLine(), "mythic+: TEST +12"), "status marks the test: " .. K:DebugLine())
    ok(has(K:DebugLine(), "timer none, 1150s of 1950s"), "with no timer, not the last real one: " .. K:DebugLine())
    ok(not has(K:DebugLine(), "secret"), "nor the real read's secret: " .. K:DebugLine())

    NOW = 2005
    key = K:ReadTest()
    ok(near(key.elapsed, 1950 * 0.6 - 20) and key.elapsedAt == 2000, "the start holds across reads")
    ok(has(K:DebugLine(), "timer none, 1155s of 1950s"), "and the line counts on: " .. K:DebugLine())

    eq(K:SetTest("late"), true, "late on")
    eq(K:TestMode(), "late", "mode late")
    key = K:ReadTest()
    eq(key.elapsed, 1950 - 15, "late starts fifteen seconds before time runs out")
    eq(key.elapsedAt, 2005, "restamped for the new mode")
    eq(key.depleted, true, "late is depleted")
    NOW = 2035
    ok(has(K:DebugLine(), "1965s of 1950s"), "the line counts past the limit, as the panel does: " .. K:DebugLine())
    NOW = 2005
    K:SetTest("test")
    eq(K:ReadTest().depleted, false, "test after late is not depleted")

    W.mapTable = {}
    W.current = {}
    K:SetTest("test")
    key = K:ReadTest()
    eq(key.timeLimit, 1800, "no map: a half hour")
    eq(key.mapName, nil, "and no name")
    eq(key.affixN, 2, "no current affixes: the two fallbacks")
    eq(key.affixes[1].id, 9, "Tyrannical first")
    eq(key.affixes[2].id, 10, "Fortified second")
    W.mapTable = { 2650 }
    K:SetTest("test")
    eq(K:ReadTest().timeLimit, 1800, "a listed map with no limit: the half hour too")
    -- Each secret carries an entry, so a list read past its guard shows in the result. Lua 5.1
    -- has no length hook for a table, so an empty secret would read as an empty list.
    W.mapTable = secret()
    rawset(W.mapTable, 1, 2649)
    W.current = secret()
    rawset(W.current, 1, { id = 152 })
    K:SetTest("test")
    key = K:ReadTest()
    eq(key.timeLimit, 1800, "a secret map table is not read")
    eq(key.affixes[1].id, 9, "a secret current-affix list falls back")
    W.mapTable = { 2649 }
    W.current = {}
    W.raise.mapTable, W.raise.current = true, true
    K:SetTest("test")
    key = K:ReadTest()
    ok(key.active and key.timeLimit == 1800, "raising map and affix lists still draw a sample")
    W.raise = { map = true }
    K:SetTest("test")
    key = K:ReadTest()
    ok(key.active and key.timeLimit == 1800, "a raising map info read still draws a sample")
    eq(key.mapName, nil, "and names no dungeon, not the error text")
    W.raise = {}
    W.mapTable = { secret("number"), 2648 }
    K:SetTest("test")
    key = K:ReadTest()
    eq(key.mapID, nil, "a secret first map is not the sample's dungeon")
    eq(secretsIn(key), "", "and no secret map id reaches the key")
    W.mapTable = { 2649 }
    C_MythicPlus = nil
    key = K:ReadTest()
    ok(key.active, "no C_MythicPlus table at all still reads")
    C_MythicPlus = MP_API

    eq(K:SetTest(nil), false, "off")
    eq(K:ReadTest().active, false, "nothing after off")
    eq(K:IsTesting(), false, "not testing after off")
    NOW = 1000
end)

-- ---------------------------------------------------------------------------------------------
-- B. Data/Providers/Scenarios.lua around it
-- ---------------------------------------------------------------------------------------------

local SCEN
local function resetScen()
    SCEN = { active = true, kit = nil, widgetSet = 0, spells = nil,
             name = "The Rookery", stage = 1, numStages = 1, sType = 1, stageName = "The Rookery",
             criteria = {}, inst = { "The Rookery", "party", 8 } }
end
resetScen()
C_Scenario = {
    GetInfo = function()
        if not SCEN.active then return nil end
        return SCEN.name, SCEN.stage, SCEN.numStages, nil, nil, nil, nil, nil, nil, SCEN.sType, nil, SCEN.kit
    end,
    GetStepInfo = function()
        return SCEN.stageName, nil, #SCEN.criteria, nil, nil, nil, nil, nil, nil, nil, nil, SCEN.widgetSet
    end,
}
C_ScenarioInfo = {
    GetCriteriaInfo = function(i)
        if type(i) ~= "number" then error("GetCriteriaInfo wants an index, got " .. tostring(i)) end
        return SCEN.criteria[i]
    end,
    GetScenarioStepInfo = function() return { spells = SCEN.spells } end,
}
GetInstanceInfo = function() return SCEN.inst[1], SCEN.inst[2], SCEN.inst[3] end

-- The client's xpcall hands its extra arguments on. Stock 5.1 drops them, so Data/Registry.lua's
-- Enable call would run with no self.
local stockXpcall = xpcall
local function clientXpcall(fn, handler, ...)
    local args, n = { ... }, select("#", ...)
    return stockXpcall(function() return fn(unpack(args, 1, n)) end, handler)
end

-- o.registry loads the real Data/Registry.lua and boots it as the login does, so the provider's
-- repaint is the one the Registry hands it. o.disabled names a provider /eqot disable switched off.
local function loadProvider(o)
    o = o or {}
    local ns, mods = newNS(o.has)
    assert(loadfile(repoFile("Data/Entry.lua")))("EQObjectiveTracker", ns)
    assert(loadfile(repoFile("Data/Keystone.lua")))("EQObjectiveTracker", ns)
    if o.db then
        mods.DB = o.db
    elseif o.cfg ~= false then
        mods.DB = newDB(o.cfg or {})
    end
    local provider
    if o.registry then
        assert(loadfile(repoFile("Data/Registry.lua")))("EQObjectiveTracker", ns)
        function ns:IsProviderDisabled(id)
            if self ~= ns then error("IsProviderDisabled called with a dot") end
            return id == o.disabled
        end
    else
        mods.Registry = { Register = function(self, p)
            if self ~= mods.Registry then error("Register called with a dot") end
            provider = p
        end }
    end
    local handlers = {}
    mods.Events = { On = function(self, ev, fn)
        if self ~= mods.Events then error("Events.On called with a dot") end
        handlers[ev] = handlers[ev] or {}
        handlers[ev][#handlers[ev] + 1] = fn
        return true
    end }
    assert(loadfile(repoFile("Data/Providers/Scenarios.lua")))("EQObjectiveTracker", ns)
    local dirty, ids = 0, {}
    local function notify() dirty = dirty + 1 end
    if o.registry then
        local R = mods.Registry
        provider = R:Get("scenarios")
        local raised = {}
        local savedH = rawget(_G, "geterrorhandler")
        setGlobal("geterrorhandler", function() return function(e) raised[#raised + 1] = tostring(e) end end)
        setGlobal("xpcall", clientXpcall)
        local okBoot, err = pcall(function()
            R:OnInitialize()
            R:OnEnable()
        end)
        setGlobal("xpcall", stockXpcall)
        setGlobal("geterrorhandler", savedH)
        if not okBoot then error(err) end
        if raised[1] then error("the Registry's boot raised: " .. raised[1]) end
        R:OnDirty(function(id)
            ids[#ids + 1] = id
            notify()
        end)
    else
        provider._notifyDirty = notify
        provider:Enable(notify)
    end
    local function fire(ev, ...)
        for _, fn in ipairs(handlers[ev] or {}) do fn(ev, ...) end
    end
    return provider, mods.Keystone, fire, function() return dirty end, handlers, ns, mods, ids
end

guard("B. provider", function()
    resetWorld()
    resetScen()
    local P, K, _, dirty = loadProvider()
    P:GetEntries()
    local b = P:GetBanner()
    ok(b and b.keystone ~= nil, "a key in a scenario reaches the banner")
    ok(b.keystone == K:Read(), "as Keystone's own table")
    eq(b.keystone.level, 12, "with its reads")

    W.mapID = nil
    P:GetEntries()
    b = P:GetBanner()
    ok(b ~= nil and b.keystone == nil, "a scenario with no key carries none")

    resetWorld()
    SCEN.active = false
    local entries = P:GetEntries()
    eq(#entries, 0, "no scenario, no test: no entry")
    eq(P:GetBanner(), nil, "and no banner")
    eq(K:DebugLine(), "mythic+: no scenario running", "and the line no longer names the last key")

    -- The test key, with no scenario
    local on, why = P:ToggleKeystoneTest("test")
    eq(on, true, "the toggle turns the test on")
    eq(why, nil, "with nothing to say")
    eq(dirty(), 1, "and asks for a repaint")
    entries = P:GetEntries()
    eq(#entries, 1, "the test draws one entry")
    local e = entries[1]
    eq(#e.lines, 1, "with one line")
    local ln = e.lines[1]
    eq(ln.kind, "weighted", "a weighted bar")
    eq(ln.current, 63, "at 63")
    eq(ln.required, 100, "of 100")
    eq(ln.text, "", "with no text to translate")
    eq(ln.completed, false, "not completed")
    eq(e.state, "active", "an active entry")
    eq(e.title, "Priory of the Sacred Flame", "titled after the sample map")
    b = P:GetBanner()
    ok(b and b.keystone and b.keystone.test ~= nil, "the banner carries the test key")
    eq(b.category, "Mythic+", "category Mythic+")
    eq(b.name, "Priory of the Sacred Flame", "name the sample map")
    eq(b.stage, 1, "stage 1")
    eq(b.numStages, 1, "one stage")
    eq(b.isFinalStage, false, "not a final stage")

    -- A real scenario ends the test
    SCEN.active = true
    P:GetEntries()
    b = P:GetBanner()
    ok(b.keystone and b.keystone.test == nil, "a real scenario reads the real key")
    eq(b.keystone.mapID, 2648, "the real map")
    eq(K:IsTesting(), false, "and ends the test")
    SCEN.active = false
    P:GetEntries()
    eq(P:GetBanner(), nil, "so nothing comes back once the scenario ends")

    on = P:ToggleKeystoneTest("test")
    eq(on, true, "test on again")
    on = P:ToggleKeystoneTest("late")
    eq(on, true, "the other mode switches")
    eq(K:TestMode(), "late", "to late")
    on = P:ToggleKeystoneTest("late")
    eq(on, false, "the same mode again clears it")
    eq(dirty(), 4, "each toggle asked for a repaint")
    eq(#P:GetEntries(), 0, "no entry once cleared")
    eq(P:GetBanner(), nil, "no banner once cleared")
    eq(K:DebugLine(), "mythic+: no scenario running", "and the line drops the sample")

    -- The sample's title with no map listed
    W.mapTable = {}
    P:ToggleKeystoneTest("test")
    eq(P:GetEntries()[1].title, "Mythic+", "no map name: titled Mythic+")
    P:ToggleKeystoneTest("test")
end)

guard("B. the switch and the toggle's answers", function()
    resetWorld()
    resetScen()
    local cfg = { showMythicPlusTimer = false }
    local P, K, _, dirty = loadProvider({ cfg = cfg })
    local calls0 = calls.elapsed
    P:GetEntries()
    eq(P:GetBanner().keystone, nil, "switched off, a key does not reach the banner")
    eq(calls.elapsed, calls0, "and the timer is not even read")
    eq(K:DebugLine(), "mythic+: switched off", "the line says so")
    cfg.showMythicPlusTimer = true
    P:GetEntries()
    ok(P:GetBanner().keystone ~= nil, "true reads it")
    cfg.showMythicPlusTimer = nil
    P:GetEntries()
    ok(P:GetBanner().keystone ~= nil, "unset reads it, the default")

    -- A real scenario: the toggle refuses
    local d0 = dirty()
    local on, why = P:ToggleKeystoneTest("test")
    eq(on, false, "no test while a scenario is up")
    eq(why, "scenario", "and says so")
    eq(K:IsTesting(), false, "nothing turned on")
    eq(dirty(), d0, "no repaint asked")

    -- A test from before a scenario no render has seen, as under a hide rule: the toggle ends it
    for _, mode in ipairs({ "test", "late" }) do
        SCEN.active = false
        P:ToggleKeystoneTest(mode)
        SCEN.active = true
        on, why = P:ToggleKeystoneTest("test")
        eq(on, false, mode .. " on, a scenario up: no sample")
        eq(why, "scenario", mode .. ": and says so")
        eq(K:IsTesting(), false, mode .. ": and the test it found is over")
        SCEN.active = false
        eq(#P:GetEntries(), 0, mode .. ": so it does not come back after the scenario")
    end
    SCEN.active = true

    -- Switched off, no scenario: on, with the reason
    SCEN.active = false
    cfg.showMythicPlusTimer = false
    on, why = P:ToggleKeystoneTest("test")
    eq(on, true, "the sample turns on with the box off")
    eq(why, "switched off", "and says the banner shows in its place")
    on, why = P:ToggleKeystoneTest("test")
    eq(on, false, "off again")
    eq(why, nil, "with nothing to say")

    -- Never enabled: off
    P._notifyDirty = nil
    on, why = P:ToggleKeystoneTest("test")
    eq(on, false, "a provider never enabled draws no sample")
    eq(why, "off", "and says so")
    eq(K:IsTesting(), false, "and turns nothing on")

    -- No DB module reads as on
    resetWorld()
    resetScen()
    local P2 = loadProvider({ cfg = false })
    P2:GetEntries()
    ok(P2:GetBanner().keystone ~= nil, "no DB module reads the switch as on")
end)

guard("B. test from a fresh login", function()
    resetWorld()
    resetScen()
    SCEN.active = false
    local P = loadProvider()
    eq(P:ToggleKeystoneTest("test"), true, "test on before anything was ever read")
    P:GetEntries()
    local b = P:GetBanner()
    ok(b and b.keystone and b.keystone.test ~= nil, "the first test panel carries the test key")
end)

guard("B. a delve's leftovers do not reach the sample", function()
    resetWorld()
    resetScen()
    SCEN.kit, SCEN.widgetSet = "delves-scenario", 842
    SCEN.spells = { { icon = 237559, name = "Foul Ball", spellID = 1295317 } }
    W.mapID = nil
    local P = loadProvider()
    P:GetEntries()
    local b = P:GetBanner()
    eq(b.widgetSetID, 842, "the delve's widget set")
    eq(b.spellsN, 1, "and its spell")
    SCEN.active = false
    P:ToggleKeystoneTest("test")
    P:GetEntries()
    b = P:GetBanner()
    eq(b.widgetSetID, nil, "the sample carries no widget set")
    eq(b.textureKit, nil, "and no texture kit")
    eq(b.spellsN, 0, "and no spell")
end)

guard("B. a real scenario's events end a test, with no render", function()
    for _, ev in ipairs({ "SCENARIO_UPDATE", "PLAYER_ENTERING_WORLD", "CHALLENGE_MODE_START" }) do
        for _, mode in ipairs({ "test", "late" }) do
            for _, box in ipairs({ "on", "off" }) do
                local tag = ev .. " (" .. mode .. ", box " .. box .. ")"
                resetWorld()
                resetScen()
                SCEN.active = false
                local cfg = {}
                if box == "off" then cfg.showMythicPlusTimer = false end
                local P, K, fire, dirty = loadProvider({ cfg = cfg })
                P:ToggleKeystoneTest(mode)
                eq(K:TestMode(), mode, tag .. ": the sample is on")
                local d0 = dirty()
                fire(ev)
                eq(K:IsTesting(), true, tag .. " with no scenario keeps the test")
                ok(dirty() > d0, tag .. " asks for a repaint")
                SCEN.active = true
                fire(ev)
                eq(K:IsTesting(), false, tag .. " in a scenario ends the test")
                SCEN.active = false
                eq(#P:GetEntries(), 0, tag .. ": nothing comes back after the scenario")
            end
        end
    end
end)

guard("B. events", function()
    resetWorld()
    resetScen()
    local P, _, fire, dirty, handlers = loadProvider()
    for _, ev in ipairs({ "WORLD_STATE_TIMER_START", "WORLD_STATE_TIMER_STOP", "CHALLENGE_MODE_START",
                          "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_RESET",
                          "CHALLENGE_MODE_DEATH_COUNT_UPDATED", "PLAYER_ENTERING_WORLD",
                          "SCENARIO_UPDATE" }) do
        ok(handlers[ev] ~= nil, ev .. " is registered")
    end
    local d0 = dirty()
    fire("WORLD_STATE_TIMER_STOP", 3)
    eq(dirty(), d0 + 1, "a timer stop repaints")
    P:GetEntries()
    eq(P:GetBanner().keystone, nil, "and the stopped timer is not drawn")
    fire("WORLD_STATE_TIMER_START", 3)
    eq(dirty(), d0 + 2, "a timer start repaints")
    P:GetEntries()
    ok(P:GetBanner().keystone ~= nil, "and the timer is drawn again")
    fire("WORLD_STATE_TIMER_STOP", 3)
    fire("CHALLENGE_MODE_START")
    eq(dirty(), d0 + 4, "a key start repaints")
    P:GetEntries()
    ok(P:GetBanner().keystone ~= nil, "and starts every timer fresh")
    fire("CHALLENGE_MODE_COMPLETED")
    eq(dirty(), d0 + 5, "completion repaints")
    P:GetEntries()
    eq(P:GetBanner().keystone, nil, "and stops the run's timer")
    fire("CHALLENGE_MODE_START")
    P:GetEntries()
    fire("CHALLENGE_MODE_RESET")
    eq(dirty(), d0 + 7, "a reset repaints")
    P:GetEntries()
    eq(P:GetBanner().keystone, nil, "and stops it too")
    -- Zoning out and back in mid-key: only the loading screen arrives
    local d1 = dirty()
    fire("PLAYER_ENTERING_WORLD")
    ok(dirty() > d1, "a loading screen repaints")
    P:GetEntries()
    ok(P:GetBanner().keystone ~= nil, "and forgets the stops, as Blizzard's own re-check does")
    W.deaths = 4
    local d2 = dirty()
    fire("CHALLENGE_MODE_DEATH_COUNT_UPDATED")
    eq(dirty(), d2 + 1, "a death repaints")
    P:GetEntries()
    eq(P:GetBanner().keystone.deaths, 4, "and the next read has it")
    -- A loading screen also rebases the clock
    W.timerInfo[3].elapsed = 0
    NOW = 3000
    P:GetEntries()
    NOW = 3010
    fire("PLAYER_ENTERING_WORLD")
    P:GetEntries()
    eq(P:GetBanner().keystone.elapsedAt, 3010, "the same figure after a loading screen is a new reading")
    NOW = 3020
    fire("WORLD_STATE_TIMER_START", 3)
    P:GetEntries()
    eq(P:GetBanner().keystone.elapsedAt, 3020, "and so it is after the timer starts")
    NOW = 1000
end)

local function retailHas()
    return { ChallengeTimer = true, Atlas = true, Scenario = true, ScenarioCriteria = true }
end

-- What each event the provider listens to does to a key on screen: "keeps" only repaints,
-- "rebases" takes the same figure as a new reading, "stops" ends the drawn timer
local EVENT_KINDS = {
    { "SCENARIO_CRITERIA_UPDATE", "keeps" },
    { "SCENARIO_SPELL_UPDATE", "keeps" },
    { "SCENARIO_CRITERIA_SHOW_STATE_UPDATE", "keeps" },
    { "SCENARIO_COMPLETED", "keeps" },
    { "ACTIVE_DELVE_DATA_UPDATE", "keeps" },
    { "SCENARIO_UPDATE", "keeps" },
    { "CHALLENGE_MODE_DEATH_COUNT_UPDATED", "keeps" },
    { "PLAYER_ENTERING_WORLD", "rebases" },
    { "CHALLENGE_MODE_START", "rebases" },
    { "WORLD_STATE_TIMER_START", "rebases" },
    { "WORLD_STATE_TIMER_STOP", "stops" },
    { "CHALLENGE_MODE_COMPLETED", "stops" },
    { "CHALLENGE_MODE_RESET", "stops" },
}

guard("B. what each event does to a key on screen", function()
    resetWorld()
    resetScen()
    local known = {}
    for _, row in ipairs(EVENT_KINDS) do known[row[1]] = true end
    local _, _, _, _, all = loadProvider()
    for ev, list in pairs(all) do
        ok(known[ev], ev .. " is one of the events listed here")
        eq(#list, 1, ev .. " is registered once")
    end
    for _, row in ipairs(EVENT_KINDS) do
        local ev, kind = row[1], row[2]
        ok(all[ev] ~= nil, ev .. " is registered")
        resetWorld()
        resetScen()
        NOW = 1000
        local P, K, fire, dirty = loadProvider()
        P:GetEntries()
        NOW = 1000.6
        W.deaths = 4
        local d0 = dirty()
        fire(ev, 3)
        eq(dirty(), d0 + 1, ev .. " asks for one repaint")
        eq(K:IsTesting(), false, ev .. " turns no sample on")
        P:GetEntries()
        local key = P:GetBanner().keystone
        if kind == "stops" then
            eq(key, nil, ev .. " stops the key's timer")
        else
            ok(key ~= nil, ev .. " leaves the key drawn")
            eq(key and key.elapsedAt, kind == "rebases" and 1000.6 or 1000, ev .. (kind == "rebases"
               and " takes the same figure as a new reading" or " leaves the clock where it stood"))
            eq(key and key.deaths, 4, ev .. ": the next read has the deaths")
        end
    end
    NOW = 1000
end)

guard("B. no event turns a sample on", function()
    for _, row in ipairs(EVENT_KINDS) do
        resetWorld()
        resetScen()
        SCEN.active = false
        local P, K, fire = loadProvider()
        fire(row[1], 3)
        eq(K:IsTesting(), false, row[1] .. " with no scenario turns no sample on")
        eq(#P:GetEntries(), 0, row[1] .. " with no scenario draws nothing")
    end
end)

guard("B. one timer starting leaves another's stop alone", function()
    resetWorld()
    resetScen()
    W.timers = { 3, 5 }
    W.timerInfo[5] = { elapsed = 70, kind = 2 }
    local P, _, fire = loadProvider()
    fire("WORLD_STATE_TIMER_STOP", 3)
    fire("WORLD_STATE_TIMER_START", 5)
    P:GetEntries()
    eq(P:GetBanner().keystone, nil, "a proving grounds timer starting does not bring the stopped key timer back")
    fire("WORLD_STATE_TIMER_START", 3)
    P:GetEntries()
    local key = P:GetBanner().keystone
    ok(key ~= nil, "its own start does")
    eq(key and key.elapsed, 400, "with its own figure")
end)

guard("B. a real scenario's render ends a test with the box off too", function()
    resetWorld()
    resetScen()
    SCEN.active = false
    local P, K = loadProvider({ cfg = { showMythicPlusTimer = false } })
    eq(P:ToggleKeystoneTest("late"), true, "the sample turns on with the box off")
    SCEN.active = true
    P:GetEntries()
    eq(K:IsTesting(), false, "a render inside a real scenario ends it, box off as with it on")
    SCEN.active = false
    eq(#P:GetEntries(), 0, "so it does not come back once the scenario ends")
end)

-- GetInfo's answers outside a running stage. One stage of one, the shape a key takes, is the control.
local NOT_RUNNING = {
    { "stage 0", "The Rookery", 0, 3 },
    { "no stages", "The Rookery", 2, 0 },
    { "no name", nil, 1, 1 },
}

guard("B. what counts as a running scenario", function()
    for _, c in ipairs(NOT_RUNNING) do
        local label = c[1]
        resetWorld()
        resetScen()
        SCEN.name, SCEN.stage, SCEN.numStages = c[2], c[3], c[4]
        local P, K, fire = loadProvider()
        eq(#P:GetEntries(), 0, label .. ": no scenario entry")
        eq(P:GetBanner(), nil, label .. ": no banner")
        eq(K:DebugLine(), "mythic+: no scenario running", label .. ": and no key read")
        local on, why = P:ToggleKeystoneTest("test")
        eq(on, true, label .. ": the sample is not refused")
        eq(why, nil, label .. ": with nothing to say")
        fire("SCENARIO_UPDATE")
        eq(K:IsTesting(), true, label .. ": a scenario update does not end it")
        local entries = P:GetEntries()
        eq(#entries, 1, label .. ": the sample draws")
        eq(entries[1] and entries[1].title, "Priory of the Sacred Flame", label .. ": the sample, not the scenario")
    end
    resetWorld()
    resetScen()
    local P, K = loadProvider()
    local entries = P:GetEntries()
    eq(entries[1] and entries[1].title, "The Rookery", "one stage of one is running")
    local on, why = P:ToggleKeystoneTest("test")
    eq(on, false, "so the sample is refused")
    eq(why, "scenario", "and says why")
    eq(K:IsTesting(), false, "with nothing turned on")
end)

guard("B. the sample's own facts, not the last scenario's", function()
    resetWorld()
    resetScen()
    W.mapID = nil
    SCEN.name, SCEN.stage, SCEN.numStages, SCEN.sType, SCEN.kit = "Earthcrawl Mines", 2, 3, 8, "delves-cave"
    SCEN.stageName, SCEN.widgetSet = "Find the Cache", 842
    SCEN.inst = { "Earthcrawl Mines", "scenario", 208 }
    SCEN.criteria = { { description = "Open the cache", completed = true },
                      { description = "Defeat the Speaker", completed = false } }
    local P = loadProvider()
    P:GetEntries()
    eq(P:DebugLine(), "Delves | Find the Cache stage 2/3 | type 8 kit delves-cave diff 208 inst scenario | widgetSet 842 | 2 criteria",
       "a delve first, for the sample to carry nothing of")
    SCEN.active = false
    P:ToggleKeystoneTest("test")
    local e = P:GetEntries()[1]
    eq(P:DebugLine(), "Mythic+ | Priory of the Sacred Flame stage 1/1 | type 1 kit nil diff nil inst party | widgetSet nil | 1 criteria",
       "the sample's status line reads as a key's: its dungeon on the stage line, one bar, a party")
    local b = P:GetBanner()
    eq(b.name, "Priory of the Sacred Flame", "the banner names the sample's dungeon")
    eq(b.stageName, "Priory of the Sacred Flame", "and so does the stage line the box off shows")
    local tip = CreateFrame(TIP, nil, nil)
    P:OnEntryTooltip(e, tip)
    eq(table.concat(tip._lines, "|"), "Priory of the Sacred Flame|Mythic+", "the tooltip: the dungeon, then Mythic+")

    setGlobal("C_UIWidgetManager", {})
    local okProbe, lines = pcall(P.WidgetProbeLines, P, false)
    eq(okProbe and lines[1], "scenario active true | Priory of the Sacred Flame | GetStepInfo set nil | GetScenarioStepInfo set nil",
       "/eqot widgetprobe names the sample's dungeon")
    W.mapTable = {}
    e = P:GetEntries()[1]
    eq(e.title, "Mythic+", "with no dungeon listed the sample is titled Mythic+")
    b = P:GetBanner()
    eq(b.name, nil, "but the banner names no dungeon")
    eq(b.stageName, nil, "and the stage line none")
    okProbe, lines = pcall(P.WidgetProbeLines, P, false)
    eq(okProbe and lines[1], "scenario active true | nil | GetStepInfo set nil | GetScenarioStepInfo set nil",
       "nor does /eqot widgetprobe")
    setGlobal("C_UIWidgetManager", nil)
end)

guard("B. the real Registry enables the provider and hands it its repaint", function()
    resetWorld()
    resetScen()
    SCEN.active = false
    local P, _, fire, dirty, handlers, _, mods, ids = loadProvider({ registry = true, has = retailHas() })
    ok(P ~= nil and mods.Registry:Get("scenarios") == P, "the provider registers itself by its id")
    eq(P and P._available, true, "available where the scenario reads are")
    ok(handlers.SCENARIO_UPDATE ~= nil, "and enabled, so its events are registered")
    local on, why = P:ToggleKeystoneTest("test")
    eq(on, true, "the sample turns on through the repaint the Registry handed it")
    eq(why, nil, "with nothing to say")
    eq(dirty(), 1, "the toggle's repaint reaches the Registry's listeners")
    eq(ids[1], "scenarios", "named for this provider")
    fire("WORLD_STATE_TIMER_STOP", 3)
    eq(dirty(), 2, "and so does an event's")
    eq(ids[2], "scenarios", "named the same")
    eq(#P:GetEntries(), 1, "the sample draws")

    local noScenario, noCriteria = retailHas(), retailHas()
    noScenario.Scenario, noCriteria.ScenarioCriteria = false, false
    for _, c in ipairs({ { "switched off with /eqot disable", { registry = true, disabled = "scenarios", has = retailHas() } },
                         { "a client without the scenario read", { registry = true, has = noScenario } },
                         { "a client without the criteria read", { registry = true, has = noCriteria } } }) do
        resetWorld()
        resetScen()
        SCEN.active = false
        local P2, K2, _, dirty2, handlers2 = loadProvider(c[2])
        eq(P2 and P2._available, false, c[1] .. ": not available")
        eq(next(handlers2), nil, c[1] .. ": never enabled, so no event is registered")
        on, why = P2:ToggleKeystoneTest("test")
        eq(on, false, c[1] .. ": no sample")
        eq(why, "off", c[1] .. ": and says the provider is off")
        eq(K2:IsTesting(), false, c[1] .. ": nothing turned on")
        eq(dirty2(), 0, c[1] .. ": no repaint")
    end
end)

-- ---------------------------------------------------------------------------------------------
-- C. UI/MythicPlus.lua
-- ---------------------------------------------------------------------------------------------

local function loadBlock(opts)
    opts = opts or {}
    installFonts(opts.missingFonts)
    local ns, mods = newNS()
    ns.Util = newUtil()
    mods.Media = newMedia()
    local clickThrough = false
    mods.Tracker = { IsClickThrough = function(self)
        if self ~= mods.Tracker then error("IsClickThrough called with a dot") end
        return clickThrough
    end }
    assert(loadfile(repoFile("UI/MythicPlus.lua")))("EQObjectiveTracker", ns)
    local MP = mods.MythicPlus
    local container = CreateFrame("Frame", nil, nil)
    container:SetWidth(300)
    return MP, container, ns, mods, function(v) clickThrough = v end
end

local function sampleKey(o)
    o = o or {}
    local limit = o.limit or 1799
    local level = 12
    if o.level == false then level = nil elseif o.level then level = o.level end
    return {
        active = true, mapID = 2648, level = level, mapName = "The Rookery", test = nil,
        timeLimit = limit, plusTwo = o.two or limit * 0.8, plusThree = o.three or limit * 0.6,
        elapsed = o.elapsed or 400, elapsedAt = o.at or 1000,
        deaths = o.deaths or 2, timeLost = o.lost or 10, depleted = o.depleted or false,
        affixN = o.affixN or 3,
        affixes = o.affixes or {
            { id = 9, name = "Tyrannical", description = "Bosses are tougher.", icon = 236401 },
            { id = 147, name = "Xal'atath's Guile", description = "Guile.", icon = 5927634 },
            { id = 10, name = "Fortified", description = "Trash is tougher.", icon = 463829 },
        },
    }
end

local function point(o, i) return o._points[i or 1] or {} end

local function tipOf(ns) return ns.Util._tip end

setGlobal("CHALLENGE_MODE_POWER_LEVEL", "Stufe %d")
setGlobal("CHALLENGE_MODE_DEATH_COUNT_TITLE", "%d Tode")
setGlobal("CHALLENGE_MODE_DEATH_COUNT_DESCRIPTION", "Zeitverlust: %s")
setGlobal("CHALLENGE_MODE_DEPLETED_KEYSTONE", "Depleted")
setGlobal("CHALLENGE_MODE_KEYSTONE_DEPLETED_AT_START", "Depleted at start")
setGlobal("CHALLENGE_MODE_TIMES_UP", "Times up")
setGlobal("CHALLENGE_MODE_TIMES_UP_LOOT", "Loot")
setGlobal("CHALLENGE_MODE_TIMES_UP_NO_LOOT", "No loot")
setGlobal("CHALLENGE_MODE_TIMES_UP_NO_LOOT_LEADER", "No loot, leader")

guard("C. block build and layout", function()
    resetWorld()
    NOW = 1000
    local MP, container, _, mods = loadBlock()
    local h = MP:Render(container, { scenarioTextAlign = "CENTER" }, sampleKey(), 40)
    local f = MP.frame
    eq(h, 87 + 2 + 14, "height: Blizzard's 87, the 2 gap, the chest line floored at 14")
    STR_H = 18
    h = MP:Render(container, nil, sampleKey(), 40)
    eq(h, 87 + 2 + 18, "a taller chest line is measured")
    STR_H = 12
    eq(f._type, "Frame", "the block is a Frame")
    ok(f:GetParent() == container, "on the container")
    eq(f._w, 251, "Blizzard's width")
    eq(f._h, 87, "Blizzard's height")
    ok(f:IsVisible(), "visible")
    eq(point(f).p, "TOP", "no cfg centers it")
    ok(point(f).rel == container and point(f).relP == "TOP", "to the container's top")
    eq(point(f).y, -40, "at the offset it was handed")
    MP:Render(container, { scenarioTextAlign = "LEFT" }, sampleKey(), 7)
    eq(point(f).p, "TOPLEFT", "Left aligns the block left")
    eq(point(f).relP, "TOPLEFT", "to the container's left")
    eq(point(f).y, -7, "offset moves with it")
    eq(#f._points, 1, "one anchor, cleared first")
    MP:Render(container, { scenarioTextAlign = "RIGHT" }, sampleKey(), 7)
    eq(point(f).p, "TOPRIGHT", "Right aligns it right")
    eq(#f._points, 1, "still one anchor")
    MP:Render(container, { scenarioTextAlign = "CENTER" }, sampleKey(), 7)
    eq(point(f).p, "TOP", "Center centers it")

    eq(f.Art._atlas, "challengemode-timer", "the frame art")
    eq(f.Art._atlasSize, false, "stretched, not at its atlas size")
    ok(f.Art._allPoints, "covering the block")
    eq(f.Art._layer, "OVERLAY", "over the bar")
    eq(f.BarBack._atlas, "ChallengeMode-TimerBG-Back", "the bar's back")
    eq(f.BarBack._atlasSize, true, "at its atlas size")
    eq(f.BarBG._atlas, "ChallengeMode-TimerBG", "the bar's frame")
    eq(f.BarBG._atlasSize, true, "at its atlas size")
    eq(f.BarBack._layer, "BACKGROUND", "back in the background")
    eq(f.BarBG._layer, "BACKGROUND", "frame in the background")
    eq(f.BarBG._sub, 1, "the frame above the back")
    eq(point(f.BarBack).y, 13, "the back 13 up")
    eq(point(f.BarBG).p, "BOTTOM", "the frame from the bottom")
    eq(point(f.BarBG).y, 13, "the frame 13 up")
    eq(f.Fill._layer, "BORDER", "the fill above both")
    eq(f.Fill._h, 13, "the fill 13 tall")
    eq(point(f.Fill).p, "BOTTOMLEFT", "the fill grows from the left")
    eq(point(f.Fill).relP, "BOTTOM", "from the block's bottom center")
    eq(point(f.Fill).x, -103.5, "half the bar left of center")
    eq(point(f.Fill).y, 10, "10 up")
    eq(f.MarkThree._layer, "ARTWORK", "+3 mark over the fill")
    eq(f.MarkTwo._layer, "ARTWORK", "+2 mark over the fill")
    eq(point(f.Level).x, 28, "level 28 in")
    eq(point(f.Level).y, -18, "level 18 down")
    eq(f.Level._template, "GameFontNormalMed2", "level in Blizzard's font")
    eq(f.TimeLeft._template, "GameFontHighlightHuge", "time in Blizzard's huge font")
    ok(point(f.TimeLeft).rel == f.Level, "time under the level")
    eq(point(f.TimeLeft).y, -8, "8 below it")
    eq(f.Level._text, "Stufe 12", "level through the client's own string")
    MP:Render(container, nil, sampleKey({ level = false }), 0)
    eq(f.Level._text, "", "no level read, no level line")
    MP:Render(container, nil, sampleKey({ level = 7 }), 0)
    eq(f.Level._text, "Stufe 7", "the level, never the map id")
    setGlobal("CHALLENGE_MODE_POWER_LEVEL", nil)
    MP:Render(container, nil, sampleKey(), 0)
    eq(f.Level._text, "+12", "no client string: +12")
    setGlobal("CHALLENGE_MODE_POWER_LEVEL", "Stufe %d")
    MP:Render(container, { scenarioTextAlign = "CENTER" }, sampleKey(), 7)

    -- Blizzard's sizes stay inside the block: only the shadow setting reaches them
    for _, fs in ipairs({ f.Level, f.TimeLeft, f.Death.Count }) do
        ok(inList(mods.Media.bshadow, fs), "the banner shadow reaches " .. tostring(fs._template))
    end
    eq(#mods.Media.banner, 0, "no banner size is applied to the block")
    eq(f.Level._font[2], 14, "the level keeps its font size")
    eq(f.TimeLeft._font[2], 20, "the time keeps its font size")
    ok(inList(mods.Media.crit, f.Plus3) and inList(mods.Media.crit, f.Plus2), "the chest line in the criteria font")
    ok(inList(mods.Media.tshadow, f.Plus3) and inList(mods.Media.tshadow, f.Plus2), "and the text shadow")
    ok(not inList(mods.Media.crit, f.Level), "the level is not in the criteria font")

    eq(point(f.Plus3).p, "TOPRIGHT", "+3 grows left")
    ok(point(f.Plus3).rel == f and point(f.Plus3).relP == "BOTTOM", "from under the block's center")
    eq(point(f.Plus3).x, -8, "8 left of center")
    eq(point(f.Plus3).y, -2, "2 below")
    eq(point(f.Plus2).p, "TOPLEFT", "+2 grows right")
    ok(point(f.Plus2).relP == "BOTTOM", "from under the block's center")
    eq(point(f.Plus2).x, 8, "8 right of center")

    ok(f.Death:GetParent() == f, "deaths on the block")
    eq(point(f.Death).p, "TOPLEFT", "deaths anchor")
    eq(point(f.Death).relP, "BOTTOMRIGHT", "from the bottom right")
    eq(point(f.Death).x, -47, "47 in")
    eq(point(f.Death).y, 43, "43 up")
    eq(f.Death.Icon._atlas, "poi-graveyard-neutral", "the graveyard icon")
    eq(f.Death.Icon._atlasSize, true, "at its atlas size")
    eq(point(f.Death.Icon).p, "LEFT", "the icon at the left")
    eq(point(f.Death.Count).p, "LEFT", "the count beside it")
    ok(point(f.Death.Count).rel == f.Death.Icon and point(f.Death.Count).relP == "RIGHT", "right of the icon")
    eq(point(f.Death.Count).x, 1, "1 apart")
    for _, m in ipairs({ f.Depleted, f.TimesUp }) do
        ok(m.Chest._atlas == "ChallengeMode-icon-chest" and m.Chest._atlasSize == true, "a chest at its size")
        ok(m.Line._atlas == "ChallengeMode-icon-redline" and m.Line._atlasSize == true, "a red line at its size")
        eq(m.Chest._layer, "ARTWORK", "chest layer")
        eq(m.Line._layer, "ARTWORK", "line layer")
        eq(m.Line._sub, 1, "the line over the chest")
        eq(point(m.Chest).p, "CENTER", "chest centered")
        eq(point(m.Line).p, "CENTER", "line centered")
    end
    ok(point(f.Depleted).rel == f.Level and point(f.Depleted).relP == "RIGHT", "beside the level")
    ok(point(f.TimesUp).rel == f.TimeLeft and point(f.TimesUp).relP == "RIGHT", "time's up beside the time")
    eq(point(f.TimesUp).x, 4, "4 apart")
    ok(f.Depleted._w == 19 and f.Depleted._h == 20, "markers are Blizzard's 19 by 20")
    ok(f.TimesUp._w == 19 and f.TimesUp._h == 20, "both of them")
    ok(f.Death._w == 20 and f.Death._h == 16, "the death count is 20 by 16")
    ok(f.MarkThree._color and f.MarkThree._color[4] == 0.7 and f.MarkTwo._color[4] == 0.7,
       "the chest marks are a faint white")
    eq(f.MarkTwo._w, 1, "a pixel wide")
end)

local function under(o, top)
    local p = o._parent
    while p do
        if p == top then return true end
        p = p._parent
    end
    return false
end

local function fmtColor(c)
    if not c then return "nil" end
    return ("%s,%s,%s,%s,%s"):format(tostring(c[1]), tostring(c[2]), tostring(c[3]), tostring(c[4]), tostring(c[5]))
end

-- Every channel, alpha included: a nil in want is a channel the code must leave unset
local function colorIs(c, want, msg)
    local same = want == nil and c == nil
    if want and c then
        same = true
        for i = 1, 5 do if c[i] ~= want[i] then same = false end end
    end
    ok(same, ("%s: want %s, got %s"):format(msg, fmtColor(want), fmtColor(c)))
end

-- The whole anchor set, every field of every point. A sixth field is a frame the point may
-- equally be taken from, for an anchor Blizzard writes against a child that covers its parent.
local function anchorsAre(o, want, msg)
    local got = o._points or {}
    eq(#got, #want, msg .. ": number of anchors")
    for _, w in ipairs(want) do
        local g
        for _, a in ipairs(got) do if a.p == w[1] then g = a end end
        local relOK = g ~= nil and (g.rel == w[2] or (w[6] ~= nil and g.rel == w[6]))
        ok(relOK and g.relP == w[3] and near(g.x, w[4]) and near(g.y, w[5]),
           ("%s: %s to %s %s,%s, got %s"):format(msg, w[1], w[3], tostring(w[4]), tostring(w[5]),
               g and ("%s to %s %s,%s%s"):format(g.p, tostring(g.relP), tostring(g.x), tostring(g.y),
                   relOK and "" or " on another frame") or "none"))
    end
end

local function tipIs(tip, msg)
    colorIs(tip._title, { 1, 1, 1, 1, true }, msg .. ": a white title that wraps")
    for i = 2, #tip._lines do
        colorIs(tip._wraps and tip._wraps[i], { nil, nil, nil, true }, msg .. ": line " .. i .. " uncolored and wrapping")
    end
end

guard("C. every region of the block against Blizzard's XML", function()
    resetWorld()
    NOW = 1000
    local MP, container, ns, mods = loadBlock()
    MP:Render(container, { scenarioTextAlign = "CENTER" }, sampleKey(), 7)
    local f = MP.frame
    local D, TU, DT, A = f.Depleted, f.TimesUp, f.Death, MP.affixes
    local frac = 1399 / 1799
    -- ChallengeModeBlock and ScenarioChallengeModeAffixTemplate in Blizzard's 12.1.0 XML, the
    -- marks and the +3 and +2 line from the file's own constants. Fields: the region, its name,
    -- its parent, its anchors, its size, its layer and sublayer, its atlas and whether at size.
    local R = {
        { f, "block", container, { { "TOP", container, "TOP", 0, -7 } }, { 251, 87 } },
        { f.BarBack, "bar back", f, { { "BOTTOM", f, "BOTTOM", 0, 13 } }, { 0, 0 },
          "BACKGROUND", nil, "ChallengeMode-TimerBG-Back", true },
        { f.BarBG, "bar frame", f, { { "BOTTOM", f, "BOTTOM", 0, 13 } }, { 0, 0 },
          "BACKGROUND", 1, "ChallengeMode-TimerBG", true },
        { f.Fill, "fill", f, { { "BOTTOMLEFT", f, "BOTTOM", -207 / 2, 10 } }, { 207 * frac, 13 }, "BORDER" },
        { f.MarkThree, "+3 mark", f, { { "BOTTOMLEFT", f, "BOTTOMLEFT", 22 + 207 * 0.4, 10 } }, { 1, 13 }, "ARTWORK" },
        { f.MarkTwo, "+2 mark", f, { { "BOTTOMLEFT", f, "BOTTOMLEFT", 22 + 207 * 0.2, 10 } }, { 1, 13 }, "ARTWORK" },
        { f.Art, "art", f, { { "TOPLEFT", f, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0 } },
          { 0, 0 }, "OVERLAY", nil, "challengemode-timer", false },
        { f.Level, "level", f, { { "TOPLEFT", f, "TOPLEFT", 28, -18 } }, { 0, 0 }, "OVERLAY" },
        { f.TimeLeft, "time", f, { { "TOPLEFT", f.Level, "BOTTOMLEFT", 0, -8 } }, { 0, 0 }, "OVERLAY" },
        { D, "depleted mark", f, { { "LEFT", f.Level, "RIGHT", 4, 0 } }, { 19, 20 } },
        { D.Chest, "depleted chest", D, { { "CENTER", D, "CENTER", 0, 0 } }, { 0, 0 },
          "ARTWORK", nil, "ChallengeMode-icon-chest", true },
        { D.Line, "depleted line", D, { { "CENTER", D, "CENTER", 0, 0 } }, { 0, 0 },
          "ARTWORK", 1, "ChallengeMode-icon-redline", true },
        { TU, "time's up mark", f, { { "LEFT", f.TimeLeft, "RIGHT", 4, 0 } }, { 19, 20 } },
        { TU.Chest, "time's up chest", TU, { { "CENTER", TU, "CENTER", 0, 0 } }, { 0, 0 },
          "ARTWORK", nil, "ChallengeMode-icon-chest", true },
        { TU.Line, "time's up line", TU, { { "CENTER", TU, "CENTER", 0, 0 } }, { 0, 0 },
          "ARTWORK", 1, "ChallengeMode-icon-redline", true },
        { DT, "death count", f, { { "TOPLEFT", f, "BOTTOMRIGHT", -47, 43 } }, { 20, 16 } },
        { DT.Icon, "death icon", DT, { { "LEFT", DT, "LEFT", 0, 0 } }, { 0, 0 },
          "ARTWORK", nil, "poi-graveyard-neutral", true },
        { DT.Count, "death number", DT, { { "LEFT", DT.Icon, "RIGHT", 1, 0 } }, { 0, 0 } },
        { f.Plus3, "+3 line", f, { { "TOPRIGHT", f, "BOTTOM", -8, -2 } }, { 0, 0 }, "OVERLAY" },
        { f.Plus2, "+2 line", f, { { "TOPLEFT", f, "BOTTOM", 8, -2 } }, { 0, 0 }, "OVERLAY" },
    }
    for i = 1, 3 do
        local a = A[i]
        R[#R + 1] = { a, "affix " .. i, f, i == 1 and { { "TOPLEFT", f, "TOPRIGHT", -(28 + 4 * 2 + 22 * 3), -18 } }
                                              or { { "LEFT", A[i - 1], "RIGHT", 4, 0 } }, { 22, 22 } }
        R[#R + 1] = { a.Portrait, "affix icon " .. i, a, { { "CENTER", a, "CENTER", 0, 0, a.Border } }, { 20, 20 }, "ARTWORK" }
        R[#R + 1] = { a.Border, "affix ring " .. i, a,
                      { { "TOPLEFT", a, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", a, "BOTTOMRIGHT", 0, 0 } }, { 0, 0 },
                      "OVERLAY", nil, "ChallengeMode-AffixRing-Sm", false }
    end

    local listed = {}
    for _, r in ipairs(R) do
        local o, name = r[1], r[2]
        listed[o] = true
        ok(o._parent == r[3], name .. " on its parent")
        anchorsAre(o, r[4], name)
        ok(near(o._w, r[5][1]) and near(o._h, r[5][2]),
           ("%s is %sx%s, got %sx%s"):format(name, r[5][1], r[5][2], tostring(o._w), tostring(o._h)))
        if r[6] then
            ok(o._layer == r[6] and o._sub == r[7], ("%s on %s %s, got %s %s"):format(name, r[6], tostring(r[7]),
               tostring(o._layer), tostring(o._sub)))
        end
        if r[8] then
            ok(o._atlas == r[8] and o._atlasSize == r[9], ("%s is %s at size %s, got %s %s"):format(name, r[8],
               tostring(r[9]), tostring(o._atlas), tostring(o._atlasSize)))
        end
    end
    local seen = 0
    for _, list in ipairs({ frames, regions }) do
        for _, o in ipairs(list) do
            if under(o, f) then
                seen = seen + 1
                ok(listed[o], "every region in the block is checked here, not a " .. tostring(o._type))
            end
        end
    end
    eq(seen, #R - 1, "and every one checked is in the block")

    MP:Render(container, { scenarioTextAlign = "LEFT" }, sampleKey(), 7)
    anchorsAre(f, { { "TOPLEFT", container, "TOPLEFT", 0, -7 } }, "block aligned left")
    MP:Render(container, { scenarioTextAlign = "RIGHT" }, sampleKey(), 7)
    anchorsAre(f, { { "TOPRIGHT", container, "TOPRIGHT", 0, -7 } }, "block aligned right")

    -- Fonts. Blizzard's templates and justification, and only the banner shadow reaches them,
    -- since the art does not grow with Banner Text Size. The +3 and +2 line is the file's own.
    local B = { GameFontNormalMed2 = FONTS.GameFontNormalMed2, GameFontHighlightHuge = FONTS.GameFontHighlightHuge,
                GameFontHighlightSmall2 = FONTS.GameFontHighlightSmall2 }
    local shadowOnly = { "ApplyScenarioShadow" }
    local criteria = { "ApplyScenarioCriteriaFont", "ApplyTextShadow" }
    local function sorted(l)
        local c = {}
        for i, v in ipairs(l or {}) do c[i] = v end
        table.sort(c)
        return table.concat(c, ",")
    end
    local FS = {
        { f.Level, "level", "GameFontNormalMed2", "LEFT", shadowOnly, B.GameFontNormalMed2 },
        { f.TimeLeft, "time", "GameFontHighlightHuge", "LEFT", shadowOnly, B.GameFontHighlightHuge },
        { DT.Count, "death number", "GameFontHighlightSmall2", nil, shadowOnly, B.GameFontHighlightSmall2 },
        { f.Plus3, "+3 line", "GameFontHighlightSmall", "RIGHT", criteria, CRIT_FONT },
        { f.Plus2, "+2 line", "GameFontHighlightSmall", "LEFT", criteria, CRIT_FONT },
    }
    MP:Render(container, nil, sampleKey(), 7)
    mods.Media.log = {}
    MP:Render(container, nil, sampleKey(), 7)
    local logged = 0
    for _ in pairs(mods.Media.log) do logged = logged + 1 end
    eq(logged, #FS, "a render styles the five font strings and nothing else")
    for _, r in ipairs(FS) do
        local fs, name = r[1], r[2]
        eq(fs._template, r[3], name .. " built from its font object")
        eq(fs._justify, r[4], name .. " justified")
        eq(sorted(mods.Media.log[fs]), sorted(r[5]), name .. " styled by exactly these, once each")
        ok(fs._font and fs._font[1] == r[6][1] and fs._font[2] == r[6][2] and (fs._font[3] or "") == (r[6][3] or ""),
           ("%s keeps %s %s, got %s %s"):format(name, r[6][1], r[6][2], tostring(fs._font and fs._font[1]),
               tostring(fs._font and fs._font[2])))
        eq(fs._fontObject, nil, name .. " never handed another font object")
    end

    -- Colors, every channel
    colorIs(f.Level._color, nil, "the level keeps its font's gold")
    colorIs(DT.Count._color, nil, "the death number keeps its font's white")
    colorIs(f.TimeLeft._color, { 1, 1, 1 }, "white while time is left")
    colorIs(f.Plus3._color, { 1, 1, 1 }, "+3 white while reachable")
    colorIs(f.Plus2._color, { 1, 1, 1 }, "+2 white while reachable")
    colorIs(f.MarkThree._color, { 1, 1, 1, 0.7 }, "the +3 mark a faint white")
    colorIs(f.MarkTwo._color, { 1, 1, 1, 0.7 }, "the +2 mark a faint white")
    colorIs(f.Fill._tint, { 1, 1, 1 }, "the fill art untinted")
    for _, r in ipairs(R) do
        local o = r[1]
        if o._type == "Texture" and o ~= f.Fill then
            colorIs(o._tint, nil, r[2] .. " never tinted")
            if o ~= f.MarkThree and o ~= f.MarkTwo then colorIs(o._color, nil, r[2] .. " is no color fill") end
        end
    end
    MP:Render(container, nil, sampleKey({ elapsed = 1080 }), 7)
    colorIs(f.Plus3._color, { 0.5, 0.5, 0.5 }, "+3 gray once missed")
    colorIs(f.Plus2._color, { 1, 1, 1 }, "+2 still white")
    MP:Render(container, nil, sampleKey({ elapsed = 1500 }), 7)
    colorIs(f.Plus2._color, { 0.5, 0.5, 0.5 }, "+2 gray once missed")
    MP:Render(container, nil, sampleKey({ elapsed = 1799 }), 7)
    colorIs(f.TimeLeft._color, { 1, 0.1, 0.1 }, "time's up in Blizzard's red")
    MP:Render(container, nil, sampleKey({ elapsed = 400 }), 7)
    colorIs(f.TimeLeft._color, { 1, 1, 1 }, "and white again with time left")

    atlasStreamed = false
    local MP2, container2 = loadBlock()
    MP2:Render(container2, nil, sampleKey(), 0)
    colorIs(MP2.frame.Fill._color, { 0.95, 0.75, 0.2 }, "the fallback fill in gold")
    colorIs(MP2.frame.Fill._tint, nil, "and not tinted")
    atlasStreamed = true

    -- Every tooltip: a white title that wraps, lines in the tooltip's own color that wrap
    local tip = tipOf(ns)
    MP:Render(container, nil, sampleKey({ elapsed = 100, depleted = true, deaths = 3, lost = 15 }), 7)
    D._scripts.OnEnter(D)
    tipIs(tip, "the depleted tooltip")
    DT._scripts.OnEnter(DT)
    tipIs(tip, "the death tooltip")
    A[1]._scripts.OnEnter(A[1])
    tipIs(tip, "an affix tooltip")
    MP:Render(container, nil, sampleKey({ elapsed = 1799, depleted = true }), 7)
    TU._scripts.OnEnter(TU)
    tipIs(tip, "the time's up tooltip")
    eq(#tip._lines, 2, "with its line")
end)

guard("C. fonts that are missing", function()
    local MP, container = loadBlock({ missingFonts = { GameFontNormalMed2 = true } })
    MP:Render(container, nil, sampleKey(), 0)
    eq(MP.frame.Level._template, "GameFontNormal", "no Med2: the plain normal font")
    MP, container = loadBlock({ missingFonts = { GameFontHighlightHuge = true } })
    MP:Render(container, nil, sampleKey(), 0)
    eq(MP.frame.TimeLeft._template, "GameFontHighlightLarge", "no Huge: the large one")
    MP, container = loadBlock({ missingFonts = { GameFontHighlightSmall2 = true } })
    MP:Render(container, nil, sampleKey(), 0)
    eq(MP.frame.Death.Count._template, "GameFontHighlightSmall", "no Small2: the small one")
    installFonts()
end)

guard("C. the clock", function()
    resetWorld()
    NOW = 1000
    local MP, container = loadBlock()
    MP:Render(container, nil, sampleKey({ elapsed = 400, at = 1000 }), 0)
    local f = MP.frame
    eq(f.TimeLeft._text, "23:19", "1799 less 400 is 23:19")
    ok(f._scripts.OnUpdate ~= nil, "the clock runs")
    local onUpdate = f._scripts.OnUpdate
    NOW = 1000.95
    onUpdate(f, 0.05)
    eq(f.TimeLeft._text, "23:19", "inside the tick, nothing moves")
    onUpdate(f, 0.06)
    eq(f.TimeLeft._text, "23:19", "a tick inside the same second leaves it")
    NOW = 1001.05
    onUpdate(f, 0.1)
    eq(f.TimeLeft._text, "23:18", "a second later it counts down")
    NOW = 1031.05
    onUpdate(f, 0.1)
    eq(f.TimeLeft._text, "22:48", "thirty more")
    ok(f.TimeLeft._color and f.TimeLeft._color[1] == 1 and f.TimeLeft._color[2] == 1, "white while time is left")

    -- At a real frame rate no single frame reaches the tick: the time adds up across them
    NOW = 1000
    MP:Render(container, nil, sampleKey({ elapsed = 400, at = 1000 }), 0)
    NOW = 1003
    for _ = 1, 8 do onUpdate(f, 0.016) end
    eq(f.TimeLeft._text, "23:16", "eight frames of 16ms add up to a tick")

    -- The reading's own stamp, not the moment it was drawn
    NOW = 1000
    MP:Render(container, nil, sampleKey({ elapsed = 400, at = 990 }), 0)
    eq(f.TimeLeft._text, "23:09", "a reading stamped ten seconds ago counts those ten")

    -- Copied, not held
    local key = sampleKey({ elapsed = 400, at = 1000 })
    NOW = 1000
    MP:Render(container, nil, key, 0)
    key.elapsed, key.timeLimit, key.elapsedAt = 0, 99999, 0
    NOW = 1002
    f._scripts.OnUpdate(f, 0.2)
    eq(f.TimeLeft._text, "23:17", "a refilled provider table does not move the clock")

    NOW = 1000
    MP:Render(container, nil, sampleKey({ limit = 4000, elapsed = 0, at = 1000 }), 0)
    eq(f.TimeLeft._text, "1:06:40", "past an hour, hours first")
    MP:Render(container, nil, sampleKey({ limit = 1799, elapsed = 1798.5, at = 1000 }), 0)
    eq(f.TimeLeft._text, "00:01", "a fractional elapsed figure is floored")

    -- A minute of 16ms frames through the real OnUpdate, the stamp 0.9s old when drawn. A clock
    -- that rebases on a tick from the floored second loses that fraction, and the tick's lateness
    -- every second after it. Every frame is read once the tick has had time to land.
    local function mmss(s) return ("%02d:%02d"):format(math.floor(s / 60), s % 60) end
    NOW = 1000.9
    MP:Render(container, nil, sampleKey({ elapsed = 400, at = 1000 }), 0)
    local read, wrong, first = 0, 0, nil
    for i = 1, 3750 do
        NOW = 1000.9 + i * 0.016
        onUpdate(f, 0.016)
        local run = 400 + (NOW - 1000)
        local part = run - math.floor(run)
        if part > 0.15 and part < 0.95 then
            read = read + 1
            local want = mmss(1799 - math.floor(run))
            if f.TimeLeft._text ~= want then
                wrong = wrong + 1
                first = first or ("frame %d: %s, want %s"):format(i, tostring(f.TimeLeft._text), want)
            end
        end
    end
    ok(read > 2500, "most of the minute's frames are read, got " .. read)
    eq(wrong, 0, "the clock keeps time frame by frame " .. tostring(first))
    eq(f.TimeLeft._text, "22:19", "a minute of frames: 400 + 60.9 elapsed")
    eq(f.Plus3._text, "+3 10:19", "and +3 counts with it")
    eq(f.Plus2._text, "+2 16:19", "and +2 too")
    NOW = 1000
end)

guard("C. the bar and the chest times", function()
    resetWorld()
    NOW = 1000
    local MP, container = loadBlock()
    local f
    MP:Render(container, nil, sampleKey({ limit = 1799, elapsed = 400, at = 1000 }), 0)
    f = MP.frame
    local frac = 1399 / 1799
    ok(near(f.Fill._w, 207 * frac), "fill width is the share of time left, got " .. tostring(f.Fill._w))
    eq(f.Fill._texture, 4567, "the fill atlas's own file")
    ok(f.Fill._tc and near(f.Fill._tc[1], 0.25) and near(f.Fill._tc[2], 0.25 + 0.5 * frac)
       and near(f.Fill._tc[3], 0.5) and near(f.Fill._tc[4], 0.625), "cropped from the atlas's coordinates")
    eq(f.Fill._shown, true, "shown")
    ok(near(point(f.MarkThree).x, 22 + 207 * 0.4), "+3 mark, got " .. tostring(point(f.MarkThree).x))
    ok(near(point(f.MarkTwo).x, 22 + 207 * 0.2), "+2 mark, got " .. tostring(point(f.MarkTwo).x))
    eq(point(f.MarkThree).y, 10, "+3 on the bar")
    eq(point(f.MarkTwo).y, 10, "+2 on the bar")
    eq(f.MarkThree._h, 13, "the bar's height")
    eq(f.MarkThree._shown, true, "+3 mark shown")
    eq(f.MarkTwo._shown, true, "+2 mark shown")
    eq(#f.MarkThree._points, 1, "one anchor")

    eq(f.Plus3._text, "+3 11:19", "+3 counts to 1079.4: 679 left")
    eq(f.Plus2._text, "+2 17:19", "+2 counts to 1439.2: 1039 left")
    ok(f.Plus3._color[1] == 1 and f.Plus3._color[3] == 1, "+3 white while reachable")

    MP:Render(container, nil, sampleKey({ elapsed = 1080, at = 1000 }), 0)
    eq(f.Plus3._text, "+3 00:00", "+3 gone")
    ok(f.Plus3._color[1] == 0.5 and f.Plus3._color[2] == 0.5, "+3 gray once gone")
    eq(f.Plus2._text, "+2 05:59", "+2 still running")
    ok(f.Plus2._color[1] == 1, "+2 still white")
    MP:Render(container, nil, sampleKey({ elapsed = 1079, at = 1000 }), 0)
    eq(f.Plus3._text, "+3 00:00", "a fraction of a second left floors to 00:00")
    ok(f.Plus3._color[1] == 1, "but is still white, since it is still reachable")
    MP:Render(container, nil, sampleKey({ limit = 1800, three = 1080, elapsed = 1080, at = 1000 }), 0)
    ok(f.Plus3._color[1] == 0.5, "exactly nothing left is gone")

    MP:Render(container, nil, sampleKey({ limit = 1799, elapsed = 1790, at = 1000 }), 0)
    eq(f.Fill._shown, true, "half a percent left still fills")
    ok(near(f.Fill._w, 207 * 9 / 1799), "at half a percent of the width")

    -- The atlas not streamed in yet: a plain fill, then the art once it arrives
    atlasStreamed = false
    MP, container = loadBlock()
    MP:Render(container, nil, sampleKey(), 0)
    f = MP.frame
    eq(f.Fill._texture, "color", "a color fill while the atlas is missing")
    ok(f.Fill._color and f.Fill._color[1] == 0.95 and f.Fill._color[2] == 0.75, "in the fallback gold")
    ok(near(f.Fill._w, 207 * 1399 / 1799), "at the same width")
    atlasStreamed = true
    MP:Render(container, nil, sampleKey(), 0)
    eq(f.Fill._texture, 4567, "the art once it streams in")
    ok(f.Fill._tint and f.Fill._tint[1] == 1, "untinted")

    -- An atlas that names its file by path
    fillInfo = { filename = "Interface\\ChallengeMode\\Fill", leftTexCoord = 0, rightTexCoord = 1,
                 topTexCoord = 0, bottomTexCoord = 1 }
    MP, container = loadBlock()
    MP:Render(container, nil, sampleKey(), 0)
    eq(MP.frame.Fill._texture, "Interface\\ChallengeMode\\Fill", "a path is used when there is no file id")
    fillInfo = FILL_INFO
end)

guard("C. time's up and depleted", function()
    resetWorld()
    NOW = 1000
    local MP, container, ns, _, setClick = loadBlock()
    local tip = tipOf(ns)
    MP:Render(container, nil, sampleKey({ elapsed = 1799 }), 0)
    local f = MP.frame
    eq(f.TimeLeft._text, "00:00", "no time left")
    ok(f.TimeLeft._color[1] == 1 and f.TimeLeft._color[2] < 0.2, "red")
    eq(f.TimesUp._shown, true, "the time's up marker")
    eq(f.TimesUp.Line._shown, false, "loot kept on an energized key")
    eq(f.Depleted._shown, false, "no depleted marker")
    eq(f.Fill._shown, false, "an empty bar")

    MP:Render(container, nil, sampleKey({ elapsed = 100, depleted = true }), 0)
    eq(f.Depleted._shown, true, "a depleted key shows its marker while time is left")
    MP:Render(container, nil, sampleKey({ elapsed = 2000, depleted = true }), 0)
    eq(f.TimesUp.Line._shown, true, "a depleted key that runs out loses the loot")
    eq(f.Depleted._shown, false, "and the depleted marker gives way to it")

    MP:Render(container, nil, sampleKey({ elapsed = 100, depleted = true }), 0)
    eq(f.Depleted._shown, true, "a depleted key with time left shows the marker")
    eq(f.TimesUp._shown, false, "and no time's up")
    eq(f.Fill._shown, true, "and the bar fills again")
    MP:Render(container, nil, sampleKey({ elapsed = 100, depleted = false }), 0)
    eq(f.Depleted._shown, false, "a full key with time left shows no marker")

    MP:Render(container, nil, sampleKey({ elapsed = 2000, depleted = false }), 0)
    eq(f.TimesUp.Line._shown, false, "time's up on a full key, loot kept")
    MP:Render(container, nil, sampleKey({ elapsed = 2000, depleted = true }), 0)
    eq(f.TimesUp.Line._shown, true, "the same second on a depleted key redraws the line")

    -- Tooltips through the addon's own tooltip, never while the tracker is click-through
    MP:Render(container, nil, sampleKey({ elapsed = 100, depleted = true }), 0)
    f.Depleted._scripts.OnEnter(f.Depleted)
    eq(tip._lines[1], "Depleted", "depleted title")
    eq(tip._lines[2], "Depleted at start", "depleted line")
    ok(tip._owner == f.Depleted, "owned by the marker")
    eq(tip._anchor, "ANCHOR_RIGHT", "anchored right")
    eq(tip._shown, true, "and shown")
    ok(tip._title[1] == 1 and tip._title[5] == true, "a white title that wraps")
    ok(tip._wraps[2] and tip._wraps[2][4] == true, "and a line that wraps")
    f.Depleted._scripts.OnLeave(f.Depleted)
    eq(tip._shown, false, "leaving the marker hides it")
    MP:Render(container, nil, sampleKey({ elapsed = 2000, depleted = false }), 0)
    f.TimesUp._scripts.OnEnter(f.TimesUp)
    eq(tip._lines[2], "Loot", "time's up on a full key keeps the loot")
    eq(tip._anchor, "ANCHOR_RIGHT", "anchored right")
    f.TimesUp._scripts.OnLeave(f.TimesUp)
    eq(tip._shown, false, "leaving it hides the tooltip")
    MP:Render(container, nil, sampleKey({ elapsed = 2000, depleted = true }), 0)
    W.leader = false
    f.TimesUp._scripts.OnEnter(f.TimesUp)
    eq(tip._lines[2], "No loot", "a depleted key: no loot")
    W.leader = true
    f.TimesUp._scripts.OnEnter(f.TimesUp)
    eq(tip._lines[2], "No loot, leader", "and the leader's line for the leader")
    eq(tip._lines[1], "Times up", "titled time's up")
    setClick(true)
    tip._lines, tip._shown = {}, false
    f.TimesUp._scripts.OnEnter(f.TimesUp)
    eq(#tip._lines, 0, "no tooltip while the tracker is click-through")
    eq(tip._shown, false, "and nothing shown")
    setClick(false)
    ok(f.TimesUp._mouse and f.Depleted._mouse, "both markers take the mouse")
end)

guard("C. deaths", function()
    resetWorld()
    NOW = 1000
    local MP, container, ns = loadBlock()
    local tip = tipOf(ns)
    MP:Render(container, nil, sampleKey({ deaths = 3, lost = 15 }), 0)
    local f = MP.frame
    eq(f.Death._shown, true, "deaths shown once they cost time")
    eq(f.Death.Count._text, "3", "the count")
    f.Death._scripts.OnEnter(f.Death)
    eq(tip._lines[1], "3 Tode", "the client's death title")
    eq(tip._lines[2], "Zeitverlust: 00:15", "and the time lost")
    eq(tip._anchor, "ANCHOR_LEFT", "to the left, as Blizzard anchors it")
    eq(tip._shown, true, "shown")
    f.Death._scripts.OnLeave(f.Death)
    eq(tip._shown, false, "and hidden on leaving")
    MP:Render(container, nil, sampleKey({ deaths = 3, lost = 0 }), 0)
    eq(f.Death._shown, false, "deaths that cost nothing are not shown")
    MP:Render(container, nil, sampleKey({ deaths = 0, lost = 15 }), 0)
    eq(f.Death._shown, false, "no deaths, nothing shown")
    ok(f.Death._mouse, "the count takes the mouse")
end)

guard("C. affixes", function()
    resetWorld()
    local MP, container, ns, _, setClick = loadBlock()
    local tip = tipOf(ns)
    MP:Render(container, nil, sampleKey(), 0)
    local f = MP.frame
    local a1, a2, a3 = MP.affixes[1], MP.affixes[2], MP.affixes[3]
    ok(a1 and a2 and a3, "three affix frames")
    eq(point(a1).p, "TOPLEFT", "the first from its top left")
    ok(point(a1).rel == f and point(a1).relP == "TOPRIGHT", "measured from the block's top right")
    eq(point(a1).x, -(28 + 4 * 2 + 22 * 3), "Blizzard's offset for three")
    eq(point(a1).y, -18, "18 down")
    ok(point(a2).rel == a1 and point(a2).relP == "RIGHT", "the next beside it")
    eq(point(a2).x, 4, "4 apart")
    eq(a1.Portrait._texture, 236401, "the first icon")
    eq(a3.Portrait._texture, 463829, "the third icon")
    eq(a1.Portrait._layer, "ARTWORK", "the icon under the ring")
    eq(point(a1.Portrait).p, "CENTER", "the icon centered")
    eq(a1.Portrait._w, 20, "the icon 20 across")
    eq(a1.Border._atlas, "ChallengeMode-AffixRing-Sm", "Blizzard's ring")
    eq(a1.Border._atlasSize, false, "stretched over the frame")
    ok(a1.Border._allPoints, "covering the affix")
    eq(a1.Border._layer, "OVERLAY", "the ring over the icon")
    eq(a1._w, 22, "22 across")
    ok(a1._mouse and a3._mouse, "each affix takes the mouse, for its tooltip")
    a2._scripts.OnEnter(a2)
    eq(tip._lines[1], "Xal'atath's Guile", "the affix name")
    eq(tip._lines[2], "Guile.", "its description")
    eq(tip._anchor, "ANCHOR_RIGHT", "anchored right")
    eq(tip._shown, true, "shown")
    a2._scripts.OnLeave(a2)
    eq(tip._shown, false, "hidden on leaving")
    setClick(true)
    tip._lines = {}
    a2._scripts.OnEnter(a2)
    eq(#tip._lines, 0, "no affix tooltip while click-through")
    setClick(false)

    -- The same slot drawing a different affix, with nothing hidden in between
    MP:Render(container, nil, sampleKey({ affixes = {
        { id = 9, name = "Tyrannical", description = "Bosses are tougher.", icon = 236401 },
        { id = 160, name = "Devour", description = "Devour.", icon = 5927636 },
        { id = 10, name = "Fortified", description = "Trash is tougher.", icon = 463829 } } }), 0)
    a2._scripts.OnEnter(a2)
    eq(tip._lines[1], "Devour", "a slot drawing another affix takes its name")
    eq(tip._lines[2], "Devour.", "and its description")

    MP:Render(container, nil, sampleKey({ affixN = 1, affixes = {
        { id = 10, name = "Fortified", description = "Trash.", icon = 463829 } } }), 0)
    eq(a1._shown, true, "one affix left shown")
    eq(a2._shown, false, "the second hidden")
    eq(a3._shown, false, "the third hidden")
    eq(a2._name, nil, "a hidden affix forgets its name")
    eq(a2._description, nil, "and its description")
    eq(point(a1).x, -(28 + 22), "Blizzard's offset for one")
    eq(a1.Portrait._texture, 463829, "the remaining affix's own icon")
    tip._lines = {}
    a2._scripts.OnEnter(a2)
    eq(#tip._lines, 0, "a hidden affix has nothing to say")
    MP:Render(container, nil, sampleKey({ affixN = 2, affixes = {
        { id = 10, name = "Fortified", description = "Trash.", icon = 463829 },
        { id = 152, name = "Peril", description = "New words.", icon = 5927635 } } }), 0)
    ok(MP.affixes[2] == a2 and a2._shown, "growing again reuses the frames")
    a2._scripts.OnEnter(a2)
    eq(tip._lines[2], "New words.", "with the new affix's description")
    eq(#MP.affixes, 3, "and builds none")
end)

guard("C. clear and status", function()
    resetWorld()
    NOW = 1000
    local MP, container = loadBlock()
    eq(MP:DebugLine(), "mythic+ block: not drawn", "never drawn")
    MP:Clear("switched off")
    eq(MP:DebugLine(), "mythic+ block: not drawn, switched off", "says why when it was asked to clear")
    MP:Render(container, nil, sampleKey({ elapsed = 400 }), 0)
    local line = MP:DebugLine()
    ok(has(line, "mythic+ block: drawn 103px, 23:19 left, +3 11:19, +2 17:19, 3 affix(es), deaths 2"),
       "drawn line: " .. line)
    MP:Clear()
    local f = MP.frame
    eq(f._shown, false, "cleared hides the block")
    eq(f._scripts.OnUpdate, nil, "and stops the clock")
    eq(MP.affixes[1]._shown, false, "and its affixes")
    eq(MP.affixes[1]._name, nil, "which forget their names")
    eq(MP:DebugLine(), "mythic+ block: not drawn", "nil reason, plain line")
    NOW = 1010
    MP:_Tick(true)
    eq(f.TimeLeft._text, "23:19", "a tick after clearing changes nothing")
    NOW = 1000

    local other = CreateFrame("Frame", nil, nil)
    MP:Render(other, nil, sampleKey(), 0)
    ok(MP.frame == f and f:GetParent() == other, "built once, moved to a new container")
    MP:Render(other, nil, sampleKey({ deaths = 0 }), 0)
    eq(MP:DebugLine():match("deaths (%a+)$"), "hidden", "status says the deaths are hidden")
end)

-- ---------------------------------------------------------------------------------------------
-- D. UI/Scenario.lua with the block in it
-- ---------------------------------------------------------------------------------------------

local function loadPanel()
    installFonts()
    local ns, mods = newNS()
    ns.Util = newUtil()
    mods.Media = newMedia()
    mods.Tracker = { IsClickThrough = function() return false end }
    assert(loadfile(repoFile("Data/Entry.lua")))("EQObjectiveTracker", ns)
    local WB = { calls = {} }
    function WB:RenderScenario(_, _, top)
        if self ~= WB then error("RenderScenario called with a dot") end
        self.calls[#self.calls + 1] = top
        return self.h or 0
    end
    function WB:ClearScenario() end
    mods.WidgetBlock = WB
    local SS = { places = {} }
    function SS:Place(_, _, top)
        if self ~= SS then error("Place called with a dot") end
        self.places[#self.places + 1] = top
        return 0
    end
    function SS:Clear() end
    mods.ScenarioSpells = SS
    assert(loadfile(repoFile("UI/Scenario.lua")))("EQObjectiveTracker", ns)
    assert(loadfile(repoFile("UI/MythicPlus.lua")))("EQObjectiveTracker", ns)
    local container = CreateFrame("Frame", nil, nil)
    container:SetWidth(300)
    return mods.Scenario, mods.MythicPlus, container, WB, SS, mods.Media
end

local function info(key)
    return { category = "Mythic+", name = "The Rookery", stageName = "The Rookery", stage = 1,
             numStages = 1, isFinalStage = false, keystone = key, spells = {}, spellsN = 0 }
end

guard("D. the panel", function()
    resetWorld()
    NOW = 1000
    local S, MP, container, WB, SS, Media = loadPanel()
    local entry = { lines = {} }
    local cfg = { scenarioTextAlign = "LEFT" }
    local h = S:Render(container, cfg, info(sampleKey()), entry, 5)
    local subH = S.subHeaderH
    eq(subH, 31, "the two-tier header in this fixture")
    eq(S.banner._shown, false, "in a key the banner gives way")
    ok(MP.frame:GetParent() == container, "to the key block, on the container")
    ok(MP.frame:IsVisible(), "and visible")
    anchorsAre(MP.frame, { { "TOPLEFT", container, "TOPLEFT", 0, -(5 + 31 + 6) } },
        "the block aligned the way the banner would be, under the header and the banner gap")
    -- A hidden banner is not drawn, so a key's repaints do not style it
    eq(S.banner.Name._text, "", "a key never writes the hidden banner's name")
    eq(S.banner.NormalBG._atlas, nil, "nor sets its art")
    ok(Media.log[S.banner.Stage] == nil and Media.log[S.banner.Name] == nil, "nor styles its strings")
    eq(S.headH, 103, "the block's own height")
    eq(WB.calls[#WB.calls], 5 + 31 + 6 + 103, "the widget block starts under the key block")
    eq(SS.places[#SS.places], 5 + 31 + 6 + 103, "and so do the scenario spells")
    eq(h, 31 + 6 + 103 + 0 + 0 + 6, "the panel height counts the block")

    WB.h = 20
    entry.lines = { { text = "Boss", completed = false, kind = "objective" } }
    h = S:Render(container, cfg, info(sampleKey()), entry, 5)
    local row = S.activeCriteria[1]
    ok(row and point(row).y == -(5 + 31 + 6 + 103 + 20 + 4), "the first criterion under the block and the widgets, got "
       .. tostring(row and point(row).y))
    eq(SS.places[#SS.places], 5 + 31 + 6 + 103 + 20 + 4 + 14, "the spells under the criteria")
    eq(h, 31 + 6 + 103 + 20 + 4 + 14 + 0 + 6, "and the height counts all of it")
    WB.h = 0
    entry.lines = {}

    cfg.showMythicPlusTimer = false
    h = S:Render(container, cfg, info(sampleKey()), entry, 5)
    eq(S.banner._shown, true, "switched off, the banner is back")
    eq(MP.frame._shown, false, "and the block gone")
    eq(MP:DebugLine(), "mythic+ block: not drawn, switched off", "saying why")
    eq(S.headH, 83, "the banner's height")
    eq(WB.calls[#WB.calls], 5 + 31 + 6 + 83, "the widgets under the banner")
    eq(h, 31 + 6 + 83 + 6, "the panel height counts the banner")
    cfg.showMythicPlusTimer = true
    local styled, named = #Media.banner, S.banner.Name._text
    S.banner.Name._text = "untouched"
    S:Render(container, cfg, info(sampleKey()), entry, 5)
    eq(MP.frame._shown, true, "true draws it")
    eq(S.banner._shown, false, "and hides the banner again")
    eq(#Media.banner, styled, "without restyling the banner it hides")
    eq(S.banner.Name._text, "untouched", "or redrawing it")
    S.banner.Name._text = named
    cfg.showMythicPlusTimer = nil

    S:Render(container, cfg, info(sampleKey()), entry, 5)
    eq(MP.frame._shown, true, "unset draws it, the default")
    S:Render(container, cfg, info(nil), entry, 5)
    eq(S.banner._shown, true, "no key: the banner")
    eq(MP.frame._shown, false, "and no block")
    eq(MP:DebugLine(), "mythic+ block: not drawn", "with no reason given")
    eq(S.headH, 83, "banner height")
    -- Switched off, the provider hands no key at all, and the line still says why
    cfg.showMythicPlusTimer = false
    S:Render(container, cfg, info(nil), entry, 5)
    eq(MP:DebugLine(), "mythic+ block: not drawn, switched off", "switched off with no key in hand")
    cfg.showMythicPlusTimer = nil

    S:Render(container, cfg, info(sampleKey()), entry, 5)
    S:Render(container, cfg, nil, entry, 5)
    eq(MP.frame._shown, false, "the scenario ending clears the block")
    eq(S.headH, 83, "and the height goes back to the banner's")
    eq(MP.frame._scripts.OnUpdate, nil, "and its clock")
    eq(MP:DebugLine(), "mythic+ block: not drawn", "with no reason, since nothing was switched off")
end)

-- ---------------------------------------------------------------------------------------------
-- E. /eqot mplus
-- ---------------------------------------------------------------------------------------------

guard("E. the command", function()
    resetWorld()
    local ns, mods = newNS()
    SlashCmdList = {}
    assert(loadfile(repoFile("UI/Commands.lua")))("EQObjectiveTracker", ns)
    mods.Commands:OnEnable()
    local slash = SlashCmdList["EQOT"]
    ok(type(slash) == "function", "the slash command is installed")
    -- Answers by mode, as the provider does: the same mode again clears it
    local toggles, current, nextWhy = {}, nil, nil
    local SC = {}
    function SC:ToggleKeystoneTest(mode)
        if self ~= SC then error("ToggleKeystoneTest called with a dot") end
        toggles[#toggles + 1] = mode
        if nextWhy == "off" or nextWhy == "scenario" then return false, nextWhy end
        if current == mode then current = nil else current = mode end
        if current and nextWhy then return true, nextWhy end
        return current ~= nil, nil
    end
    mods.Registry = { Get = function(self, id)
        if self ~= mods.Registry then error("Registry.Get called with a dot") end
        return id == "scenarios" and SC or nil
    end }
    local order = {}
    mods.Tracker = { Render = function(self)
        if self ~= mods.Tracker then error("Tracker.Render called with a dot") end
        order[#order + 1] = "render"
    end }
    mods.Feed = { Build = function(self)
        if self ~= mods.Feed then error("Feed.Build called with a dot") end
        order[#order + 1] = "build"
    end }
    mods.Keystone = { DebugLine = function()
        order[#order + 1] = "keystone"
        return "mythic+: K"
    end }
    mods.MythicPlus = { DebugLine = function() return "mythic+ block: M" end }
    mods.Visibility = { DebugLine = function(self)
        if self ~= mods.Visibility then error("Visibility.DebugLine called with a dot") end
        return "visibility: V"
    end }

    slash("mplus test")
    eq(toggles[1], "test", "test toggles the test")
    eq(ns.printed[#ns.printed], "mythic+ test: on. A sample key is drawn while no scenario is running. "
       .. "Type /eqot mplus test again to clear it.", "and says it is on, and how to clear it")
    slash("MPLUS  TEST ")
    eq(toggles[2], "test", "case and spaces do not matter")
    eq(ns.printed[#ns.printed], "mythic+ test: off.", "and off says off")
    slash("mplus late")
    eq(toggles[3], "late", "late toggles the late test")
    ok(has(ns.printed[#ns.printed], "mythic+ late: on"), "and names it")
    ok(has(ns.printed[#ns.printed], "/eqot mplus late again"), "and how to clear that one")
    slash("mplus late")
    eq(ns.printed[#ns.printed], "mythic+ late: off.", "late off names late")

    nextWhy = "switched off"
    slash("mplus test")
    ok(has(ns.printed[#ns.printed], "Show the Mythic+ timer is off, so the stage banner shows in its place."),
       "the box off: the banner shows instead: " .. ns.printed[#ns.printed])
    slash("mplus test")
    nextWhy = "scenario"
    slash("mplus test")
    eq(ns.printed[#ns.printed], "mythic+: a scenario is running, so no sample key until it ends.", "a scenario: refused")
    nextWhy = "off"
    slash("mplus late")
    eq(ns.printed[#ns.printed], "mythic+: the scenarios provider is switched off (/eqot modules).", "provider off")
    nextWhy = nil

    local n = #toggles
    local before = #ns.printed
    eq(#order, 0, "a toggle reads nothing itself")
    slash("mplus")
    eq(table.concat(order, ","), "render,build,keystone",
       "plain mplus repaints and rebuilds before it prints, so a hidden tracker reports now")
    eq(#ns.printed, before + 3, "plain mplus prints three lines")
    eq(ns.printed[before + 1], "mythic+: K", "the reads")
    eq(ns.printed[before + 2], "mythic+ block: M", "then the block")
    eq(ns.printed[before + 3], "visibility: V", "then whether the tracker is hidden, so the block line may be its last paint")
    ok(inList(ns.standing, "Keystone") and inList(ns.standing, "MythicPlus"), "each asked whether it stands down")
    before = #ns.printed
    slash("mplus foo")
    eq(#ns.printed, before + 3, "anything else prints the three lines too")
    eq(#toggles, n, "and toggles nothing")

    ns._blizzard = true
    slash("mplus test")
    eq(ns.printed[#ns.printed], "mythic+: off, Blizzard's tracker in use", "under Blizzard's tracker it says so")
    eq(#toggles, n, "and toggles nothing")
    local orderN, printedN = #order, #ns.printed
    slash("mplus")
    eq(#ns.printed, printedN + 1, "plain mplus under Blizzard's tracker prints one line")
    eq(ns.printed[#ns.printed], "mythic+: off, Blizzard's tracker in use", "and says so")
    eq(#order, orderN, "and builds no feed, which would start the tracker's own timers")
    ns._blizzard = false
    ns.Has.ChallengeTimer = false
    slash("mplus test")
    eq(ns.printed[#ns.printed], "mythic+: not available on this client", "no API: not available")
    ns.Has.ChallengeTimer = true
    mods.Registry.Get = function() return nil end
    slash("mplus")
    eq(ns.printed[#ns.printed], "mythic+: not available on this client", "no provider: not available")

    slash("nonsense")
    ok(has(ns.printed[#ns.printed], "mplus [test|late]"), "the usage line lists it")
end)

-- The command against the real provider and the real Registry, so the answers the model above
-- stands in for are the provider's own
local function commandsOver(o)
    local P, K, _, dirty, _, ns, mods = loadProvider(o)
    SlashCmdList = {}
    assert(loadfile(repoFile("UI/Commands.lua")))("EQObjectiveTracker", ns)
    mods.Commands:OnEnable()
    local reads = 0
    mods.Tracker = { Render = function(self)
        if self ~= mods.Tracker then error("Tracker.Render called with a dot") end
    end }
    mods.Feed = { Build = function(self)
        if self ~= mods.Feed then error("Feed.Build called with a dot") end
        reads = reads + 1
        P:GetEntries()
    end }
    mods.MythicPlus = { DebugLine = function(self)
        if self ~= mods.MythicPlus then error("MythicPlus.DebugLine called with a dot") end
        return "mythic+ block: stub"
    end }
    mods.Visibility = { DebugLine = function(self)
        if self ~= mods.Visibility then error("Visibility.DebugLine called with a dot") end
        return "visibility: stub"
    end }
    return SlashCmdList["EQOT"], P, K, ns, dirty, function() return reads end
end

guard("E. the command against the real provider", function()
    resetWorld()
    resetScen()
    SCEN.active = false
    local cfg = {}
    local slash, _, K, ns, dirty, reads = commandsOver({ registry = true, cfg = cfg, has = retailHas() })
    local ON = "mythic+ %s: on. A sample key is drawn while no scenario is running. Type /eqot mplus %s again to clear it."
    local function last() return ns.printed[#ns.printed] end

    slash("mplus test")
    eq(last(), ON:format("test", "test"), "test: the provider turns the sample on")
    eq(K:TestMode(), "test", "and it is on")
    eq(dirty(), 1, "with one repaint through the Registry")
    local before = #ns.printed
    slash("mplus")
    eq(reads(), 1, "plain mplus builds the feed, which reads the provider")
    ok(has(ns.printed[before + 1], "mythic+: TEST +12 Priory of the Sacred Flame (map 2649)"),
       "and prints the sample the provider drew: " .. tostring(ns.printed[before + 1]))
    eq(ns.printed[before + 2], "mythic+ block: stub", "then the block's line")
    eq(ns.printed[before + 3], "visibility: stub", "then the visibility line")
    slash("mplus late")
    eq(last(), ON:format("late", "late"), "late switches modes")
    eq(K:TestMode(), "late", "to late")
    slash("mplus late")
    eq(last(), "mythic+ late: off.", "the same mode again clears it")
    eq(K:IsTesting(), false, "and the sample is gone")

    cfg.showMythicPlusTimer = false
    slash("mplus test")
    eq(last(), ON:format("test", "test") .. " Show the Mythic+ timer is off, so the stage banner shows in its place.",
       "box off: on, with the banner in its place")
    slash("mplus test")
    eq(last(), "mythic+ test: off.", "and off again")
    cfg.showMythicPlusTimer = nil

    slash("mplus late")
    SCEN.active = true
    slash("mplus test")
    eq(last(), "mythic+: a scenario is running, so no sample key until it ends.", "a scenario up: refused")
    eq(K:IsTesting(), false, "and the sample it found is over")
    SCEN.active = false

    ns._blizzard = true
    local n0, r0 = #ns.printed, reads()
    slash("mplus")
    eq(#ns.printed, n0 + 1, "under Blizzard's tracker plain mplus prints one line")
    eq(last(), "mythic+: off, Blizzard's tracker in use", "saying so")
    eq(reads(), r0, "and builds no feed")
    slash("mplus test")
    eq(last(), "mythic+: off, Blizzard's tracker in use", "test says so too")
    eq(K:IsTesting(), false, "and turns nothing on")
    ns._blizzard = false

    resetWorld()
    resetScen()
    SCEN.active = false
    local slash2, _, K2, ns2 = commandsOver({ registry = true, disabled = "scenarios", has = retailHas() })
    slash2("mplus test")
    eq(ns2.printed[#ns2.printed], "mythic+: the scenarios provider is switched off (/eqot modules).",
       "a provider the Registry left off says so")
    eq(K2:IsTesting(), false, "and turns nothing on")
end)

-- ---------------------------------------------------------------------------------------------
-- F. The capability flag, Classic, and seams
-- ---------------------------------------------------------------------------------------------

local function evalHas(mutate)
    local saved = { CM = C_ChallengeMode, T = GetWorldElapsedTimers, E = GetWorldElapsedTime,
                    CF = CreateFrame }
    local cm = {}
    for k, v in pairs(CM) do cm[k] = v end
    C_ChallengeMode = cm
    GetWorldElapsedTimers, GetWorldElapsedTime = timersFn, elapsedFn
    if mutate then mutate(cm) end
    CreateFrame = function() return { SetParent = function() end } end
    local ns = {}
    local okLoad, err = pcall(assert(loadfile(repoFile("Core/Compat.lua"))), "EQObjectiveTracker", ns)
    C_ChallengeMode, GetWorldElapsedTimers, GetWorldElapsedTime = saved.CM, saved.T, saved.E
    CreateFrame = saved.CF
    if not okLoad then error(err) end
    return ns.Has.ChallengeTimer
end

guard("F. the capability flag", function()
    eq(evalHas(), true, "Core/Compat.lua answers true with every read present")
    eq(evalHas(function(cm) cm.GetActiveChallengeMapID = nil end), false, "false without the map id read")
    eq(evalHas(function(cm) cm.GetMapUIInfo = nil end), false, "false without the map info read")
    eq(evalHas(function(cm) cm.GetActiveKeystoneInfo = nil end), false, "false without the keystone read")
    eq(evalHas(function() GetWorldElapsedTimers = nil end), false, "false without the timer list")
    eq(evalHas(function() GetWorldElapsedTime = nil end), false, "false without the timer read")
    eq(evalHas(function() C_ChallengeMode = nil end), false, "false with no C_ChallengeMode at all")
    eq(evalHas(function(cm) cm.GetDeathCount, cm.GetAffixInfo = nil, nil end), true,
       "the death count and affix names are not required")
end)

guard("F. Classic", function()
    local saved = { CM = C_ChallengeMode, MPA = C_MythicPlus, T = C_Texture, GT = GetWorldElapsedTimers,
                    GE = GetWorldElapsedTime, E = Enum }
    C_ChallengeMode, C_MythicPlus, C_Texture = nil, nil, nil
    GetWorldElapsedTimers, GetWorldElapsedTime, Enum = nil, nil, nil
    installFonts({ GameFontNormalMed2 = true, GameFontHighlightHuge = true, GameFontHighlightSmall2 = true })
    local okK, K = pcall(loadKeystone, { ChallengeTimer = false })
    ok(okK, "Data/Keystone.lua loads on a client with no retail API: " .. tostring(not okK and K or ""))
    if okK then
        eq(K:DebugLine(), "mythic+: not on this client", "and says so before any read")
        eq(K:Read().active, false, "a read is inactive")
        eq(K:DebugLine(), "mythic+: not on this client", "and still says so after one")
    end
    local okB, MP = pcall(loadBlock, { missingFonts = { GameFontNormalMed2 = true,
                                                        GameFontHighlightHuge = true,
                                                        GameFontHighlightSmall2 = true } })
    ok(okB, "UI/MythicPlus.lua loads there too: " .. tostring(not okB and MP or ""))
    if okB then eq(MP:DebugLine(), "mythic+ block: not drawn", "and has nothing drawn") end
    C_ChallengeMode, C_MythicPlus, C_Texture = saved.CM, saved.MPA, saved.T
    GetWorldElapsedTimers, GetWorldElapsedTime, Enum = saved.GT, saved.GE, saved.E
    installFonts()
end)

local function stripComments(s)
    s = s:gsub("%-%-%[(=*)%[.-%]%1%]", "")
    s = s:gsub("%-%-[^\n]*", "")
    return s
end

guard("F. seams", function()
    local probe = stripComments("a\n--[[\nshowMythicPlusTimer  = true,\n]]\n-- showMythicPlusTimer  = true,\nb")
    ok(not has(probe, "showMythicPlusTimer"), "the stripper removes line and block comments")

    local tab = stripComments(readFile("Options/TabTracker.lua"))
    ok(has(tab, 'if ns.Has.ChallengeTimer and ns:GetModule("Registry"):Get("scenarios") then\n            local mplusCheck = self:CreateCheckbox(content, L["Show the Mythic+ timer"],\n                rowSetting("showMythicPlusTimer", true))\n            scenarios:Add(mplusCheck)'),
       "the box is built where a key can be read and drawn, on the Scenarios and Popups card, default on")

    local cmd = stripComments(readFile("UI/Commands.lua"))
    ok(has(cmd, 'local WINDOW_ONLY = { Tracker = true, ItemButtons = true, ZoneGroups = true,\n                      Keystone = true, MythicPlus = true }'),
       "under Blizzard's tracker both Mythic+ lines say so, like the window's other parts")
    ok(has(cmd, '    debugLine("ScenarioSpells")\n    if Registry:Get("scenarios") then\n        debugLine("Keystone")\n        debugLine("MythicPlus")\n    end\n'),
       "/eqot status prints them after the scenario spells, where a provider can read a key")

    local BS = string.char(92)
    local KEY, PROV = "Data" .. BS .. "Keystone.lua", "Data" .. BS .. "Providers" .. BS .. "Scenarios.lua"
    local SUI, MPL = "UI" .. BS .. "Scenario.lua", "UI" .. BS .. "MythicPlus.lua"
    local LINK = "Data" .. BS .. "QuestLink.lua"
    for _, toc in ipairs({ "EQObjectiveTracker.toc", "EQObjectiveTracker_Mainline.toc",
                           "EQObjectiveTracker_Camelot.toc", "EQObjectiveTracker_TBC.toc",
                           "EQObjectiveTracker_Vanilla.toc" }) do
        local lines = {}
        for l in (readFile(toc) .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = (l:gsub("\r$", "")) end
        local nK, nP, nS, nM, iK, iP, iS, iM, iL = 0, 0, 0, 0, nil, nil, nil, nil, nil
        for i, l in ipairs(lines) do
            if l == KEY then nK, iK = nK + 1, i end
            if l == PROV then nP, iP = nP + 1, i end
            if l == SUI then nS, iS = nS + 1, i end
            if l == MPL then nM, iM = nM + 1, i end
            if l == LINK then iL = i end
        end
        eq(nS, 1, toc .. " lists UI\\Scenario.lua once")
        eq(nM, 1, toc .. " lists UI\\MythicPlus.lua once")
        eq(iM, iS and iS + 1, toc .. " right after UI\\Scenario.lua")
        eq(nK, 1, toc .. " lists Data\\Keystone.lua once, a shared module like Data\\Widgets.lua")
        eq(iK, iL and iL + 1, toc .. " at the end of the shared data modules")
        if nP == 1 then ok(iK < iP, toc .. " before the scenario provider, which captures it at load") end
    end
end)

-- Core/DB.lua run whole and initialized over an AceDB stub, so a fresh profile reads what it ships
local function shippedDB()
    local ns, mods = newNS({ ChallengeTimer = true, Atlas = true, QuestWatchAPI = true })
    local lib = {}
    function lib:New(sv, defaults)
        if self ~= lib then error("AceDB New called with a dot") end
        if sv ~= "EQObjectiveTrackerDB" then error("AceDB asked for " .. tostring(sv)) end
        return { profile = copy(defaults.profile), char = copy(defaults.char), global = copy(defaults.global) }
    end
    local saved = rawget(_G, "LibStub")
    setGlobal("LibStub", function(name)
        if name ~= "AceDB-3.0" then error("LibStub asked for " .. tostring(name)) end
        return lib
    end)
    local okLoad, err = pcall(function()
        assert(loadfile(repoFile("Core/DB.lua")))("EQObjectiveTracker", ns)
        mods.DB:OnInitialize()
    end)
    setGlobal("LibStub", saved)
    if not okLoad then error(err) end
    return mods.DB
end

local function panelF()
    installFonts()
    local ns, mods = newNS()
    ns.Util = newUtil()
    mods.Media = newMedia()
    mods.Tracker = { IsClickThrough = function(self)
        if self ~= mods.Tracker then error("IsClickThrough called with a dot") end
        return false
    end }
    assert(loadfile(repoFile("Data/Entry.lua")))("EQObjectiveTracker", ns)
    local WB = {}
    function WB:RenderScenario()
        if self ~= WB then error("RenderScenario called with a dot") end
        return 0
    end
    function WB:ClearScenario() end
    mods.WidgetBlock = WB
    local SS = {}
    function SS:Place()
        if self ~= SS then error("Place called with a dot") end
        return 0
    end
    function SS:Clear() end
    mods.ScenarioSpells = SS
    assert(loadfile(repoFile("UI/Scenario.lua")))("EQObjectiveTracker", ns)
    assert(loadfile(repoFile("UI/MythicPlus.lua")))("EQObjectiveTracker", ns)
    local container = CreateFrame("Frame", nil, nil)
    container:SetWidth(300)
    return mods.Scenario, mods.MythicPlus, container
end

guard("F. the shipped default draws the key", function()
    local DB = shippedDB()
    eq(DB:Tracker().showMythicPlusTimer, true, "a fresh profile ships the timer on")
    resetWorld()
    resetScen()
    NOW = 1000
    local P = loadProvider({ db = DB })
    local c0 = calls.elapsed
    local entry = P:GetEntries()[1]
    local b = P:GetBanner()
    ok(calls.elapsed > c0, "so a key in a scenario is read")
    ok(b and b.keystone ~= nil, "and handed on")
    local S, MP, container = panelF()
    S:Render(container, DB:Tracker(), b, entry, 0)
    ok(MP.frame ~= nil and MP.frame:IsVisible(), "and the key block is drawn")
    eq(S.banner._shown, false, "in the stage banner's place")
end)

guard("F. the sample on screen, with the box on and off", function()
    resetWorld()
    resetScen()
    NOW = 1000
    SCEN.active = false
    local cfg = { scenarioTextAlign = "CENTER" }
    local P = loadProvider({ cfg = cfg })
    P:ToggleKeystoneTest("test")
    local S, MP, container = panelF()
    local entry = P:GetEntries()[1]
    S:Render(container, cfg, P:GetBanner(), entry, 0)
    ok(MP.frame ~= nil and MP.frame:IsVisible(), "the sample draws the key block")
    eq(S.banner._shown, false, "in the banner's place")
    eq(S.subHeader.text:GetText(), "Priory of the Sacred Flame", "under a header naming the sample's dungeon")
    eq(S.subHeader.cat:GetText(), "Mythic+", "as a Mythic+ run")
    cfg.showMythicPlusTimer = false
    entry = P:GetEntries()[1]
    S:Render(container, cfg, P:GetBanner(), entry, 0)
    eq(S.banner._shown, true, "box off: the stage banner shows")
    eq(MP.frame._shown, false, "and the block does not")
    eq(S.banner.Name:GetText(), "Priory of the Sacred Flame", "naming the dungeon, as a key's stage line does")
    eq(S.banner.Stage:GetText(), "", "with no stage count for a run of one stage")
end)

print(("test_mplus: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
