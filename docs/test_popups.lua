-- Unit tests for the quest popup boxes, run against the SHIPPED source. Run from the repo root with
-- the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_popups.lua
--
-- WHY THIS FILE EXISTS. A popup box ("Quest Discovered!", or "Quest Complete!" on a quest handed in
-- from the tracker) is that quest's only prompt, Blizzard's own being suppressed. The author asked
-- (2026-10-16) for the boxes on every section tab, and approved /eqot popup test, a sample box that
-- a click leaves alone, since a real popup cannot be made on demand. The tab half is test_tabs.lua's.
--
-- What is run: Data/AutoQuestPopups.lua WHOLE, UI/AutoQuestPopup.lua WHOLE over typed frame stubs,
-- and the /eqot popup branch sliced out of UI/Commands.lua. The client's popup reads are stubbed
-- and raise on an index that is not a number, as the client's do.
--
-- OUT OF SCOPE BY CONSTRUCTION: where the tracker places the boxes (Render, which no harness runs
-- whole), and how a box looks in game.

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
end

local function readFile(rel)
    local fh = assert(io.open(repoFile(rel), "r"))
    local src = fh:read("*a")
    fh:close()
    return src
end

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end

local function case(name, fn)
    print("== " .. name)
    local good, err = pcall(fn)
    ok(good, name .. " raised: " .. tostring(err))
end

local SAMPLE = "Sample quest (/eqot popup test)"
local function K(key) return "<" .. key .. ">" end

-- ------------------------------------------------------------------------- typed frame stubs

local FRAME, TEXTURE, FONTSTRING = {}, {}, {}
local function region(methods, kind, parent)
    return setmetatable({ kind = kind, parent = parent, points = {}, scripts = {}, shown = true }, { __index = methods })
end
function FRAME:SetBackdrop(b) self.backdrop = b end
function FRAME:SetBackdropColor(...) self.bg = { ... } end
function FRAME:SetBackdropBorderColor(...) self.border = { ... } end
function FRAME:RegisterForClicks(...) self.clicks = { ... } end
function FRAME:SetScript(name, fn) self.scripts[name] = fn end
function FRAME:SetSize(w, h) self.w, self.h = w, h end
function FRAME:SetPoint(...) self.points[#self.points + 1] = { ... } end
function FRAME:ClearAllPoints() self.points = {} end
function FRAME:SetHeight(h) self.height = h end
function FRAME:Show() self.shown = true end
function FRAME:Hide() self.shown = false end
function FRAME:GetParent() return self.parent end
function FRAME:SetParent(p) self.parent = p end
function FRAME:CreateTexture(_, layer) local t = region(TEXTURE, "Texture", self) t.layer = layer return t end
function FRAME:CreateFontString(_, layer, template)
    local s = region(FONTSTRING, "FontString", self)
    s.layer, s.template = layer, template
    return s
end
function TEXTURE:SetSize(w, h) self.w, self.h = w, h end
function TEXTURE:SetPoint(...) self.points[#self.points + 1] = { ... } end
function TEXTURE:SetBlendMode(m) self.blend = m end
function TEXTURE:SetAlpha(a) self.alpha = a end
function FONTSTRING:SetPoint(...) self.points[#self.points + 1] = { ... } end
function FONTSTRING:SetFont(...) self.font = { ... } end
function FONTSTRING:SetTextColor(...) self.color = { ... } end
function FONTSTRING:SetText(s) self.text = s end
function FONTSTRING:SetJustifyH(j) self.justify = j end
function FONTSTRING:SetWidth(w) self.width = w end
function FONTSTRING:GetStringHeight() return (self.text and self.text ~= "") and 12 or 0 end

-- --------------------------------------------------------------------------------- the world

local st

-- o.popups is the client's list, each { questID, type }; o.inLog and o.campaign key quests in the
-- log and their campaign; o.has, o.safe and o.cfg are the capability flags, safe mode and settings.
local function load(o)
    o = o or {}
    st = { popups = o.popups or {}, calls = {}, refreshes = 0, cfg = o.cfg or {} }
    local modules = {}
    local ns = { Has = o.has or { AutoQuestPopUp = true, CampaignInfo = true } }
    ns.L = setmetatable({}, { __index = function(_, k) return K(k) end })
    function ns:RegisterModule(name, m) modules[name] = m return m end
    function ns:GetModule(name) return modules[name] end
    function ns:SafeMode() return o.safe == true end
    local db = {}
    function db.Tracker(self) assert(self == db, "DB:Tracker without self") return st.cfg end
    modules.DB = db
    local row = {}
    function row.ApplyGenericQuestIcon(self, glow, icon)
        assert(self == row, "Row:ApplyGenericQuestIcon without self")
        glow.atlas, icon.atlas = "glow", "icon"
    end
    modules.Row = row
    local tracker = {}
    function tracker.IsClickThrough(self) assert(self == tracker, "IsClickThrough without self") return st.through == true end
    function tracker.Refresh(self) assert(self == tracker, "Refresh without self") st.refreshes = st.refreshes + 1 end
    modules.Tracker = tracker

    local function spy(name)
        return function(...) st.calls[#st.calls + 1] = { name, ... } end
    end
    local env = setmetatable({
        wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
        tremove = table.remove,
        GetNumAutoQuestPopUps = function() return #st.popups end,
        GetAutoQuestPopUp = function(i)
            if type(i) ~= "number" then error("bad popup index", 0) end
            local p = st.popups[i]
            if p then return p[1], p[2] end
        end,
        C_QuestLog = {
            GetTitleForQuestID = function(id) return "Quest " .. tostring(id) end,
            GetLogIndexForQuestID = function(id) return (o.inLog or {})[id] end,
        },
        C_CampaignInfo = { GetCampaignID = function(id) return (o.campaign or {})[id] end },
        CreateFrame = function(kind, _, parent) return region(FRAME, kind, parent) end,
        UIParent = region(FRAME, "Frame"),
        STANDARD_TEXT_FONT = "font",
        ShowQuestOffer = spy("ShowQuestOffer"),
        ShowQuestComplete = spy("ShowQuestComplete"),
        RemoveAutoQuestPopUp = spy("RemoveAutoQuestPopUp"),
    }, { __index = _G })
    for _, rel in ipairs({ "Data/AutoQuestPopups.lua", "UI/AutoQuestPopup.lua" }) do
        local chunk = assert(loadfile(repoFile(rel)))
        setfenv(chunk, env)
        chunk("EQObjectiveTracker", ns)
    end
    st.Popups, st.Box, st.ns = modules.AutoQuestPopups, modules.AutoQuestPopup, ns
    return st
end

local function refresh()
    local good, err = pcall(st.Popups.Refresh, st.Popups)
    ok(good, "Refresh does not raise" .. (good and "" or (" - " .. tostring(err))))
end

local REAL = { { 501, "OFFER" }, { 502, "COMPLETE" }, { 503, "COMPLETE" } }
local IN_LOG = { [502] = 4, [503] = 7 }
local CAMPAIGN = { [502] = 9 }

-- ---------------------------------------------------------------------------- the data module

case("real popups route to their section and only a finished one suppresses a row", function()
    load({ popups = REAL, inLog = IN_LOG, campaign = CAMPAIGN })
    local P = st.Popups
    refresh()
    ok(P:Count() == 3, "three popups read: " .. P:Count())
    ok(P:CountFor("quests") == 2 and P:CountFor("campaign") == 1, "an offer and an untagged finish go to Quests, the campaign finish to Campaign")
    ok(P:IsSuppressed(502) and P:IsSuppressed(503) and not P:IsSuppressed(501), "the two finished quests are kept out of their rows")
    ok(P:Get(1).questID == 501 and P:Get(1).title == "Quest 501", "each carries its quest and title")
    ok(P:DebugLine() == "quest popups: available | 3 live, campaign 1, quests 2, suppressing 2 rows | sample off",
       "the status line, with the sample off: " .. P:DebugLine())
end)

case("the sample is one more Quest Discovered box in Quests, with no quest behind it", function()
    load({ popups = REAL, inLog = IN_LOG, campaign = CAMPAIGN })
    local P = st.Popups
    ok(P:ToggleSample() == true, "the first run turns it on")
    refresh()
    ok(P:Count() == 4, "it is counted with the real ones: " .. P:Count())
    local s = P:Get(4)
    ok(s and s.questID == nil and s.popUpType == "OFFER" and s.groupID == "quests" and s.title == SAMPLE,
       "last, an offer in Quests with no quest ID and the sample title")
    ok(P:Get(1).questID == 501 and P:Get(3).questID == 503, "the real ones stay first, in the client's order")
    ok(P:CountFor("quests") == 3 and P:CountFor("campaign") == 1, "Quests counts it, Campaign does not")
    ok(P:IsSuppressed(nil) == false, "it suppresses no row")
    ok(P:DebugLine() == "quest popups: available | 4 live, campaign 1, quests 3, suppressing 2 rows | sample on",
       "the status line says so: " .. P:DebugLine())
    refresh()
    ok(P:Count() == 4 and P:CountFor("quests") == 3, "a second pass does not add it twice")
    ok(P:ToggleSample() == false, "the second run turns it off")
    refresh()
    ok(P:Count() == 3 and P:Get(4) == nil and P:CountFor("quests") == 2, "and the next pass drops it")
end)

case("the sample alone, and a list that shrinks under it", function()
    load({ popups = REAL, inLog = IN_LOG, campaign = CAMPAIGN })
    local P = st.Popups
    P:ToggleSample()
    refresh()
    st.popups = {}
    refresh()
    ok(P:Count() == 1 and P:Get(1).title == SAMPLE and P:Get(1).questID == nil, "with no real popup, the sample is the only box")
    ok(P:Get(2) == nil, "and nothing is left over from the longer list before")
    ok(P:CountFor("quests") == 1 and P:CountFor("campaign") == 0, "counted in Quests alone")
end)

case("the sample keeps every gate a real popup has", function()
    load({ popups = REAL, inLog = IN_LOG, campaign = CAMPAIGN, cfg = { showQuestPopups = false } })
    local P = st.Popups
    P:ToggleSample()
    refresh()
    ok(P:Count() == 0 and P:CountFor("quests") == 0 and P:Get(1) == nil, "Show Quest Discovered popups off: no box, the sample included")
    load({ popups = REAL, has = { AutoQuestPopUp = false, CampaignInfo = true } })
    P = st.Popups
    P:ToggleSample()
    refresh()
    ok(P:Count() == 0, "a client with no popup API: none")
    ok(P:DebugLine() == "quest popups: no API | 0 live, campaign 0, quests 0, suppressing 0 rows | sample on",
       "and the status line says why: " .. P:DebugLine())
    load({ popups = REAL, safe = true })
    P = st.Popups
    P:ToggleSample()
    refresh()
    ok(P:Count() == 0, "safe mode: none")
end)

-- ------------------------------------------------------------------------------ the box itself

case("the sample box draws with Quests only, and again after a release", function()
    load({ popups = {} })
    local P, B = st.Popups, st.Box
    P:ToggleSample()
    refresh()
    local content = region(FRAME, "Frame")
    local good, h = pcall(B.Render, B, content, 300, 10, "quests")
    ok(good and type(h) == "number" and h > 0, "Quests draws one box: " .. tostring(h))
    local good2, h2 = pcall(B.Render, B, content, 300, 10, "campaign")
    ok(good2 and h2 == 0, "Campaign draws none")
    B:ReleaseAll()
    local good3, h3 = pcall(B.Render, B, content, 300, 10, "quests")
    ok(good3 and h3 == h, "a render after the release draws it again at the same height")
end)

-- CreateFrame is wrapped to keep every button Render builds, so both boxes can be checked.
case("clicking: the sample box calls nothing, a real offer opens and retires its quest", function()
    load({ popups = { { 501, "OFFER" } } })
    local built = {}
    local env = getfenv(st.Box.Render)
    local create = env.CreateFrame
    env.CreateFrame = function(kind, name, parent, template)
        local f = create(kind, name, parent, template)
        if kind == "Button" then built[#built + 1] = f end
        return f
    end
    local P, B = st.Popups, st.Box
    P:ToggleSample()
    refresh()
    local content = region(FRAME, "Frame")
    B:Render(content, 300, 0, "quests")
    ok(#built == 2, "two boxes built, the real offer and the sample: " .. #built)
    local real, sample = built[1], built[2]
    ok(real.questID == 501 and real.popUpType == "OFFER", "the real box carries its quest")
    ok(sample.questID == nil and sample.popUpType == "OFFER", "the sample carries none")
    ok(sample.header.text == K"Quest Discovered!" and sample.title.text == SAMPLE,
       "the sample reads Quest Discovered! over the sample title")
    ok(sample.points[1] and sample.points[1][1] == "TOPLEFT" and sample.points[1][2] == content
       and sample.points[1][5] < real.points[1][5], "and sits under the real box, on the same content")

    st.calls, st.refreshes = {}, 0
    local good, err = pcall(sample.scripts.OnClick, sample)
    ok(good, "a click on the sample does not raise" .. (good and "" or (" - " .. tostring(err))))
    ok(#st.calls == 0, "and calls nothing on the client: " .. #st.calls)
    ok(st.refreshes == 0, "and asks for no repaint")

    good = pcall(real.scripts.OnClick, real)
    ok(good and #st.calls == 2 and st.calls[1][1] == "ShowQuestOffer" and st.calls[1][2] == 501
       and st.calls[2][1] == "RemoveAutoQuestPopUp" and st.calls[2][2] == 501,
       "a real offer opens its quest and retires the popup")
    ok(st.refreshes == 1, "then asks for one repaint")

    B:ReleaseAll()
    ok(real.questID == nil and real.popUpType == nil and real.shown == false, "a released box forgets its quest")
end)

-- ---------------------------------------------------------------------------------- the command

local cmdSrc = readFile("UI/Commands.lua")
local a = cmdSrc:find('        elseif cmd == "popup" then\n', 1, true)
local b = cmdSrc:find('        elseif cmd == "timer" then\n', 1, true)
assert(a and b and b > a, "the popup branch is found ahead of the timer branch")
local cchunk = assert(loadstring("local tracker, ns, strtrim, debugLine = ...\nreturn function(cmd, rest)\n    if false then\n"
                                 .. cmdSrc:sub(a, b - 1) .. "    end\nend", "popup-command-slice"))

local out, renders, toggles, lines, blizzard, popupsMod, cfg
-- Render, the popup refresh and the status line, in the order the command ran them.
local seq = {}
local cmdNs, cmdDB, TR = {}, {}, {}
function cmdNs:GetModule(name)
    assert(self == cmdNs, "ns:GetModule without self")
    if name == "AutoQuestPopups" then return popupsMod end
    if name == "DB" then return cmdDB end
end
function cmdNs:UsesBlizzardTracker() assert(self == cmdNs, "UsesBlizzardTracker without self") return blizzard end
function cmdNs:Print(s) assert(self == cmdNs, "Print without self") out[#out + 1] = s end
function cmdDB:Tracker() assert(self == cmdDB, "DB:Tracker without self") return cfg end
function TR:Render() assert(self == TR, "Render without self") renders = renders + 1 seq[#seq + 1] = "render" end
local runCmd = cchunk(function() return TR end, cmdNs,
                      function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end,
                      function(name) lines[#lines + 1] = name seq[#seq + 1] = "line" end)

local function stubPopups(available, answers)
    local p = {}
    function p:Available() assert(self == p, "Available without self") return available end
    function p:Refresh() assert(self == p, "Refresh without self") seq[#seq + 1] = "refresh" end
    function p:ToggleSample()
        assert(self == p, "ToggleSample without self")
        toggles = toggles + 1
        return answers[toggles]
    end
    return p
end
local function cmd(rest)
    out, renders, lines, seq = {}, 0, {}, {}
    local good, err = pcall(runCmd, "popup", rest)
    ok(good, "/eqot popup " .. tostring(rest) .. " does not raise" .. (good and "" or (" - " .. tostring(err))))
    return out[1]
end

local ON = "popup test: on. A sample Quest Discovered box is drawn with the Quests section, "
    .. "and on every other tab while section tabs are on. Type /eqot popup test again to clear it."

case("/eqot popup", function()
    toggles, blizzard, cfg = 0, false, {}
    popupsMod = nil
    ok(cmd("test") == "popup: not available on this client", "no popup module: not available")
    popupsMod = stubPopups(false, {})
    ok(cmd("test") == "popup: not available on this client" and toggles == 0, "a client with no popup API: not available")

    popupsMod = stubPopups(true, { true, false, true })
    blizzard = true
    ok(cmd("test") == "popup: off, Blizzard's tracker in use", "under Blizzard's tracker it says so")
    ok(toggles == 0 and renders == 0, "and starts no sample")
    blizzard = false

    ok(cmd("test") == ON, "on: " .. tostring(out[1]))
    ok(toggles == 1 and renders == 1, "toggled once, then the tracker is drawn again")
    ok(table.concat(seq, ",") == "render", "with no status line and no extra refresh")
    ok(cmd("test") == "popup test: off.", "a second run says off")
    cfg = { showQuestPopups = false }
    ok(cmd("  TEST ") == ON .. " Show Quest Discovered popups is off, so it is not drawn.",
       "read trimmed and in any case, and it says when the boxes are switched off: " .. tostring(out[1]))
    ok(toggles == 3, "three runs, three toggles")

    toggles = 0
    ok(cmd("") == nil and renders == 1 and #lines == 1 and lines[1] == "AutoQuestPopups",
       "with no word: a fresh render and the popup status line")
    ok(toggles == 0, "and no sample")
    ok(table.concat(seq, ",") == "render,refresh,line",
       "the popups read again after the render, which returns early while the tracker is hidden: "
       .. table.concat(seq, ","))
    cmd("late")
    ok(toggles == 0 and #lines == 1 and lines[1] == "AutoQuestPopups", "any other word: the same, never a sample")

    -- The real module behind it.
    load({ popups = {} })
    popupsMod, cfg = st.Popups, {}
    ok(cmd("test") == ON, "the real module starts the sample")
    refresh()
    ok(st.Popups:Count() == 1 and st.Popups:Get(1).title == SAMPLE, "and the next pass draws it")
    ok(cmd("test") == "popup test: off.", "and the command clears it")
    refresh()
    ok(st.Popups:Count() == 0, "and the next pass drops it")
end)

case("the usage line lists the command", function()
    ok(cmdSrc:find('mplus [test|late], popup [test], timer [test], importeq', 1, true) ~= nil,
       "popup [test] is in the usage line")
end)

print(("test_popups: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
