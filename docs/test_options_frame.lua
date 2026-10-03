-- Unit tests for Options/Frame.lua, run against the SHIPPED source.
-- Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_options_frame.lua
--
-- Since 2.0 Options/Frame.lua holds only the EverythingUI context and the forwarders, and every
-- tab reaches the library through it. Nothing else loads it: the boot harness fakes the Options
-- module from the TOC. So a field it stops passing on switches a whole feature off with every
-- other harness green (the live preview, the footers with every Reset button, the per-view
-- refreshes, the nav icons), and only this harness can see it.
--
-- The file loads WHOLE over a recording EverythingUI stub. Every lookup in the locale table reads
-- "<key>", so a hard-coded English string cannot pass for a translated one.
--
-- OUT OF SCOPE BY CONSTRUCTION: what the library does with what it is handed. That is the
-- library's own tests' business.

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
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

local ACCENT = { 0.784, 0.216, 0.243 }

-- o.noChar and o.noGlobal make the DB answer nil, as it does before it has initialized.
local function load(o)
    o = o or {}
    local st = { contexts = {}, tabs = {}, selected = {}, built = {}, scales = 0, toggles = 0, order = {},
                 discord = 0, char = {}, global = {} }
    local ctx = {}
    function ctx:RegisterTab(def) st.tabs[#st.tabs + 1] = def end
    function ctx:Texture(name) return "tex:" .. name end
    function ctx:SelectTab(id) st.selected[#st.selected + 1] = id end
    function ctx:BuildSettings(name)
        st.built[#st.built + 1] = name
        st.order[#st.order + 1] = "build"
        return { name = name }
    end
    function ctx:ApplyWindowScale() st.scales = st.scales + 1 end
    function ctx:ToggleSettings()
        st.toggles = st.toggles + 1
        st.order[#st.order + 1] = "toggle"
    end
    local EUI = { tokens = { accents = { EQOT = { accent = ACCENT } } } }
    function EUI:NewContext(opts)
        st.contexts[#st.contexts + 1] = opts
        return ctx
    end
    local modules = {}
    local ns = {
        VERSION = "9.8.7",
        L = setmetatable({}, { __index = function(_, k) return "<" .. k .. ">" end }),
        Util = { Tooltip = function() return "the addon's own tooltip" end },
    }
    function ns:RegisterModule(name, t) modules[name] = t return t end
    function ns:GetModule(name) return modules[name] end
    function ns:ShowDiscord() st.discord = st.discord + 1 end
    modules.DB = {
        Char = function() if not o.noChar then return st.char end end,
        Global = function() if not o.noGlobal then return st.global end end,
    }
    local env = setmetatable({
        LibStub = function(major)
            st.major = major
            return EUI
        end,
    }, { __index = _G })
    local chunk = assert(loadfile(repoFile("Options/Frame.lua")))
    setfenv(chunk, env)
    chunk("EQObjectiveTracker", ns)
    st.ctx, st.ns, st.Options = ctx, ns, modules.Options
    st.opts = st.contexts[1] or {}
    return st
end

local function sortedKeys(t)
    local out = {}
    for k in pairs(t) do out[#out + 1] = tostring(k) end
    table.sort(out)
    return table.concat(out, ",")
end

case("the context is made once, from the library, with this addon's identity", function()
    local st = load()
    ok(st.major == "EverythingUI-1.0", "the library is found by its LibStub name: " .. tostring(st.major))
    ok(#st.contexts == 1, "one context: " .. #st.contexts)
    local o = st.opts
    ok(o.id == "EQOT" and o.title == "EQ Objective Tracker", "named EQOT, titled EQ Objective Tracker")
    ok(o.version == "9.8.7", "the addon's own version, read at load: " .. tostring(o.version))
    ok(o.accent == ACCENT, "the accent the library keeps for this addon")
    ok(o.L == st.ns.L, "the addon's locale table")
    ok(o.tooltip == st.ns.Util.Tooltip, "the addon's own tooltip, never the shared one")
    ok(type(o.discord) == "function", "a Discord action")
    if type(o.discord) == "function" then o.discord() end
    ok(st.discord == 1, "which opens the addon's Discord popup")
    ok(st.Options and st.Options.ui == st.ctx, "kept on the module as Options.ui, where the tabs and menus find it")
    ok(sortedKeys(o) == "L,accent,discord,getLastTab,getWindowScale,id,labels,setLastTab,setWindowScale,title,tooltip,version",
       "and nothing it does not mean to pass: " .. sortedKeys(o))
end)

case("the library's own strings are this addon's translations", function()
    local st = load()
    local lb = st.opts.labels or {}
    ok(lb.discord == "<Join our Discord!>", "the sidebar button: " .. tostring(lb.discord))
    ok(lb.discordTipTitle == "<Join our Discord>", "its tooltip title: " .. tostring(lb.discordTipTitle))
    ok(lb.discordTip == "<Click to copy the invite link.>", "its tooltip text: " .. tostring(lb.discordTip))
    ok(lb.testSound == "<Plays the currently selected sound.>", "the speaker's tooltip: " .. tostring(lb.testSound))
    ok(lb.clear == "<Clear>", "the color picker's Clear: " .. tostring(lb.clear))
    ok(sortedKeys(lb) == "clear,discord,discordTip,discordTipTitle,testSound", "exactly those five: " .. sortedKeys(lb))
end)

case("the last tab is read and written per character", function()
    local st = load()
    local o = st.opts
    ok(o.getLastTab() == nil, "nothing saved reads nil, so the library falls back to the first tab")
    st.char.lastOptionsTab = "tracker"
    ok(o.getLastTab() == "tracker", "a saved tab is read back")
    o.setLastTab("about")
    ok(st.char.lastOptionsTab == "about", "and a viewed tab is saved: " .. tostring(st.char.lastOptionsTab))
    ok(st.global.lastOptionsTab == nil, "on the character, not the account")
    local none = load({ noChar = true })
    local good, got = pcall(none.opts.getLastTab)
    local good2 = pcall(none.opts.setLastTab, "about")
    ok(good and good2 and got == nil, "a DB not yet ready raises nothing and reads no tab")
    ok(next(none.char) == nil and next(none.global) == nil, "and the tab is saved nowhere else instead")
end)

case("the window scale is read and written for the whole account", function()
    local st = load()
    local o = st.opts
    ok(o.getWindowScale() == nil, "nothing saved reads nil, so the library uses 1")
    st.global.optionsWindowScale = 0.85
    ok(o.getWindowScale() == 0.85, "a saved scale is read back")
    o.setWindowScale(1.1)
    ok(st.global.optionsWindowScale == 1.1, "and a clamped one is written back: " .. tostring(st.global.optionsWindowScale))
    ok(st.char.optionsWindowScale == nil, "on the account, not the character")
    local none = load({ noGlobal = true })
    local good, got = pcall(none.opts.getWindowScale)
    local good2 = pcall(none.opts.setWindowScale, 1.1)
    ok(good and good2 and got == nil, "a DB not yet ready raises nothing and reads no scale")
    ok(next(none.char) == nil and next(none.global) == nil, "and the scale is saved nowhere else instead")
end)

case("RegisterTab hands the library every field a tab defines, unchanged", function()
    local st = load()
    local def = {
        id = "appearance", title = "<Appearance>", order = 30,
        build = function() end, refresh = function() end, footer = function() end,
        preview = function() end, previewRefresh = function() end,
    }
    st.Options:RegisterTab(def)
    local got = st.tabs[1] or {}
    ok(#st.tabs == 1, "one tab registered: " .. #st.tabs)
    for _, k in ipairs({ "id", "title", "order", "build", "refresh", "footer", "preview", "previewRefresh" }) do
        ok(got[k] ~= nil and got[k] == def[k], k .. " reaches the library unchanged")
    end
    ok(got.icon == "tex:icon-appearance", "with the tab's icon from the library's textures: " .. tostring(got.icon))
    ok(sortedKeys(got) == "build,footer,icon,id,order,preview,previewRefresh,refresh,title",
       "and nothing else: " .. sortedKeys(got))
end)

case("each of the four tabs gets its own icon, and a tab with none gets none", function()
    local st = load()
    for _, id in ipairs({ "general", "tracker", "appearance", "about" }) do
        st.Options:RegisterTab({ id = id, title = id, order = 1, build = function() end })
    end
    st.Options:RegisterTab({ id = "extra", title = "extra", order = 99, build = function() end })
    local icons = {}
    for _, t in ipairs(st.tabs) do icons[#icons + 1] = t.id .. "=" .. tostring(t.icon) end
    ok(table.concat(icons, ",") == "general=tex:icon-general,tracker=tex:icon-tracker,"
       .. "appearance=tex:icon-appearance,about=tex:icon-about,extra=nil", table.concat(icons, ","))
    local plain = st.tabs[1] or {}
    ok(plain.refresh == nil and plain.footer == nil and plain.preview == nil and plain.previewRefresh == nil,
       "and a tab without the optional parts hands over none, which the library would refuse")
end)

case("the forwarders reach the context", function()
    local st = load()
    local O = st.Options
    O:SelectTab("about")
    ok(#st.selected == 1 and st.selected[1] == "about", "SelectTab selects the tab it was asked for")
    O:ApplyWindowScale()
    ok(st.scales == 1, "ApplyWindowScale applies the scale once: " .. st.scales)
    O:Build()
    ok(#st.built == 1 and st.built[1] == "EQOTOptionsFrame" and O.frame and O.frame.name == "EQOTOptionsFrame",
       "Build builds the window under its global name and keeps it")
    O:Build()
    ok(#st.built == 1, "and builds it only once: " .. #st.built)

    local fresh = load()
    fresh.Options:Toggle()
    ok(table.concat(fresh.order, ",") == "build,toggle", "Toggle builds first, then toggles: " .. table.concat(fresh.order, ","))
    fresh.Options:Toggle()
    ok(#fresh.built == 1 and fresh.toggles == 2, "and the next Toggle only toggles")

    local enabled = load()
    enabled.Options:OnEnable()
    ok(#enabled.built == 1 and enabled.toggles == 0, "OnEnable builds the window at login and leaves it closed")
end)

-- Read from the vendored library rather than copied, so a key it stops taking, or one it starts
-- requiring, fails here instead of raising at login.
local function libTable(name)
    local fh = assert(io.open(repoFile("Libs/EverythingUI/Context.lua"), "r"))
    local src = fh:read("*a")
    fh:close()
    local body = assert(src:match("local " .. name .. " = (%b{})"), name .. " not found in Context.lua")
    return assert(loadstring("return " .. body))()
end

local KINDS = {
    rgb = function(v)
        if type(v) ~= "table" then return false end
        for i = 1, 3 do
            if type(v[i]) ~= "number" or v[i] < 0 or v[i] > 1 then return false end
        end
        return true
    end,
}

case("every key handed to the library is one its Context.lua takes, of its kind", function()
    local OPTS, LABELS = libTable("OPTS"), libTable("LABELS")
    ok(next(OPTS) ~= nil and next(LABELS) ~= nil, "both tables read")
    local st = load()
    local o = st.opts
    for key, v in pairs(o) do
        local spec = OPTS[key]
        ok(spec ~= nil, key .. " is a key the library takes")
        if spec then
            local fits
            if KINDS[spec.kind] then fits = KINDS[spec.kind](v) else fits = type(v) == spec.kind end
            ok(fits, key .. " is a " .. tostring(spec.kind) .. ": " .. type(v))
        end
    end
    for key, spec in pairs(OPTS) do
        if spec.required then ok(o[key] ~= nil, key .. ", which the library requires, is passed") end
    end
    for key, v in pairs(o.labels or {}) do
        ok(LABELS[key] == true and type(v) == "string", "label " .. key .. " is one the library takes, as a string")
    end
    ok(o.discord == nil or (o.labels and o.labels.discord ~= nil), "a Discord action comes with its label")
end)

print(("test_options_frame: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
