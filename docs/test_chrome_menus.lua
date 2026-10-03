-- luacheck: globals CreateFrame UIParent tremove
--
-- Unit tests for the right-click menus of the two floating frames, run against the SHIPPED source.
-- Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_chrome_menus.lua
--
-- UI/ScenarioBonusHUD.lua and UI/ZoneProgressBar.lua load WHOLE here, one fresh copy per case,
-- and each frame's _ContextMenu is driven through the EverythingUI library's menu, which is a
-- spy here, as is ApplySettings. Since 2.0 that menu draws all three of EQOT's right-click
-- menus in place of Blizzard's MenuUtil, and how it draws is tested in EverythingUI's own
-- tests/test_menu.lua.
--
-- What each menu promises, and what this file holds it to:
--
--   1. NO FRAME, NO MENU. The menu is reached only from the frame's own right-click, so there is
--      nothing to move or reset before it is drawn.
--   2. THE LOCK ITEM NAMES THE STATE IT WILL LEAVE. A locked frame offers Unlock and an unlocked one
--      Lock, read from the saved block when the menu opens.
--   3. EACH ACTION WRITES THE SAVED BLOCK FIRST AND APPLIES IT SECOND. Applied first, the frame
--      would draw the old state until the next unrelated refresh.
--   4. RESET PUTS THE FRAME'S OWN DEFAULT ANCHOR BACK, which is not the same for the two frames.
--   5. A PROFILE THAT CANNOT BE READ STILL OPENS THE MENU AND WRITES NOTHING.
--   6. EVERY ROW IS ONE THE LIBRARY ACCEPTS. Its menu raises on any field it does not know, and a
--      raise there is a Lua error on every right-click.

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
end

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end

_G.UIParent = { name = "UIParent" }
_G.tremove = table.remove
local function noFrame() error("a menu must not build a frame") end
_G.CreateFrame = noFrame

-- For the one case that builds the frame itself, to reach the script its right-click runs. It
-- records the scripts it is given and takes every other call without a word.
local function permissive()
    local f = { scripts = {}, hooks = {} }
    function f:SetScript(e, fn) self.scripts[e] = fn end
    function f:HookScript(e, fn) self.hooks[e] = fn end
    function f:CreateFontString() return permissive() end
    function f:CreateTexture() return permissive() end
    return setmetatable(f, { __index = function() return function() end end })
end

-- Read from the vendored Menu.lua rather than copied, so the two cannot drift apart.
local function libItemFields()
    local fh = assert(io.open(repoFile("Libs/EverythingUI/Menu.lua"), "r"))
    local src = fh:read("*a")
    fh:close()
    local body = assert(src:match("local ITEM_FIELDS = (%b{})"), "ITEM_FIELDS not found in Menu.lua")
    return assert(loadstring("return " .. body))()
end
local fieldsRead, LIB_FIELDS = pcall(libItemFields)
ok(fieldsRead and type(LIB_FIELDS) == "table" and next(LIB_FIELDS) ~= nil,
   "the library's item fields are read from its Menu.lua: " .. tostring(LIB_FIELDS))
if not fieldsRead then LIB_FIELDS = {} end

local SUBJECTS = {
    { name = "the bonus objectives HUD", file = "UI/ScenarioBonusHUD.lua", module = "ScenarioBonusHUD",
      key = "scenarioBonusHUD", title = "Bonus Objectives", resetY = -120 },
    { name = "the zone progress bar", file = "UI/ZoneProgressBar.lua", module = "ZoneProgressBar",
      key = "zoneProgressBar", title = "Zone Progress Bar", resetY = 220 },
}

-- A fresh module per case, so neither the frame nor a spy carries from one case to the next.
-- ApplySettings is replaced with a spy that copies the saved block at the moment it is called,
-- which is what tells "written then applied" from "applied then written".
-- marked makes every lookup read "<key>", so a hard-coded English string can be told from one.
local function load(subject, block, noProfile, marked)
    local tracker = { [subject.key] = block }
    local st = { shown = {}, applied = {} }
    local ns = {
        modules = {},
        Has = {},
        L = setmetatable({}, { __index = function(_, k) return marked and ("<" .. k .. ">") or k end }),
        Util = {},
        RegisterModule = function(self, n, tbl) self.modules[n] = tbl or {} return self.modules[n] end,
        GetModule = function(self, n) return self.modules[n] end,
        UsesBlizzardTracker = function() return false end,
    }
    ns.modules.DB = { Tracker = function() if not noProfile then return tracker end end }
    ns.modules.Options = { ui = { ShowMenu = function(_, items) st.shown[#st.shown + 1] = items end } }
    ns.modules.ScenarioBonus = {
        OnDirty = function() end,
        GetModel = function() return {} end,
        Reconcile = function() end,
    }
    ns.modules.Media = { GetStatusBarFile = function() return "bar.tga" end }
    local chunk = assert(loadfile(repoFile(subject.file)))
    chunk("EQObjectiveTracker", ns)
    local mod = ns:GetModule(subject.module)
    mod.frame = {}
    mod.ApplySettings = function()
        local b = tracker[subject.key] or {}
        st.applied[#st.applied + 1] = { locked = b.locked, point = b.point, relPoint = b.relPoint, x = b.x, y = b.y }
    end
    return mod, st, tracker
end

local function open(mod, why)
    local okCall, err = pcall(mod._ContextMenu, mod)
    ok(okCall, why .. ": _ContextMenu does not raise" .. (okCall and "" or (" - " .. tostring(err))))
end

local function click(item, why)
    local okCall, err = pcall(item and item.onClick or error)
    ok(okCall, why .. " does not raise" .. (okCall and "" or (" - " .. tostring(err))))
end

local function names(menu)
    local out = {}
    for i = 1, #(menu or {}) do out[i] = menu[i].text or menu[i].kind end
    return table.concat(out, " | ")
end

for _, s in ipairs(SUBJECTS) do
    print("== " .. s.name .. ": no frame, no menu")
    do
        local mod, st = load(s, { locked = false })
        mod.frame = nil
        open(mod, s.name)
        ok(#st.shown == 0, s.name .. ": nothing is shown before the frame exists")
    end

    print("== " .. s.name .. ": the rows, with the lock item naming the state it leaves")
    do
        local mod, st = load(s, { locked = false })
        open(mod, s.name)
        ok(#st.shown == 1, s.name .. ": the library is asked once")
        local m = st.shown[1] or {}
        local want = s.title .. " | Lock position | Reset position | divider | Cancel"
        ok(names(m) == want, s.name .. " unlocked: " .. names(m))
        ok(m[1] and m[1].kind == "title", s.name .. ": the first row is the title")
        for i, row in ipairs(m) do
            local acts = (i == 2 or i == 3)
            ok((type(row.onClick) == "function") == acts,
               ("%s row %d carries an action only if it is Lock or Reset"):format(s.name, i))
            ok(not row.danger, ("%s row %d is not drawn as danger"):format(s.name, i))
            for k, v in pairs(row) do
                ok(LIB_FIELDS[k] == type(v), ("%s row %d field %s is one the library takes"):format(s.name, i, tostring(k)))
            end
        end

        local mod2, st2 = load(s, { locked = true })
        open(mod2, s.name .. " locked")
        ok(names(st2.shown[1]) == s.title .. " | Unlock (allow moving) | Reset position | divider | Cancel",
           s.name .. " locked offers Unlock: " .. names(st2.shown[1]))
    end

    print("== " .. s.name .. ": Lock and Unlock write the saved lock, then apply it")
    do
        local mod, st, tracker = load(s, { locked = false })
        open(mod, s.name)
        click((st.shown[1] or {})[2], s.name .. " Lock")
        ok(tracker[s.key].locked == true, s.name .. ": Lock saves locked")
        ok(#st.applied == 1 and st.applied[1].locked == true,
           s.name .. ": and applies once, after the write: " .. #st.applied)

        mod, st, tracker = load(s, { locked = true })
        open(mod, s.name)
        click((st.shown[1] or {})[2], s.name .. " Unlock")
        ok(tracker[s.key].locked == false, s.name .. ": Unlock saves unlocked")
        ok(#st.applied == 1 and st.applied[1].locked == false, s.name .. ": and applies it")
    end

    print("== " .. s.name .. ": Reset position puts its own default anchor back, then applies it")
    do
        local mod, st, tracker = load(s, { locked = true, point = "TOPLEFT", relPoint = "BOTTOMRIGHT", x = 50, y = 60 })
        open(mod, s.name)
        click((st.shown[1] or {})[3], s.name .. " Reset")
        local b = tracker[s.key]
        ok(b.point == "CENTER" and b.relPoint == "CENTER" and b.x == 0 and b.y == s.resetY,
           ("%s: centered, %d up: %s %s %s %s"):format(s.name, s.resetY, tostring(b.point), tostring(b.relPoint),
                                                       tostring(b.x), tostring(b.y)))
        ok(b.locked == true, s.name .. ": and the lock is left as it was")
        local a = st.applied[1] or {}
        ok(#st.applied == 1 and a.point == "CENTER" and a.y == s.resetY, s.name .. ": applied once, after the write")
    end

    print("== " .. s.name .. ": a profile that cannot be read still opens the menu and writes nothing")
    do
        local mod, st, tracker = load(s, { locked = true }, true)
        open(mod, s.name .. " with no profile")
        local m = st.shown[1] or {}
        ok(names(m) == s.title .. " | Lock position | Reset position | divider | Cancel",
           s.name .. ": the menu opens, offering Lock: " .. names(m))
        click(m[2], s.name .. " Lock with no profile")
        click(m[3], s.name .. " Reset with no profile")
        ok(tracker[s.key].locked == true and tracker[s.key].point == nil, s.name .. ": the saved block is untouched")
        ok(#st.applied == 2, s.name .. ": each still re-applies: " .. #st.applied)
    end

    print("== " .. s.name .. ": a right-click on the frame opens the menu, and only a right-click")
    do
        local good, err = pcall(function()
            local mod, st = load(s, { locked = false })
            mod.frame = nil
            local made = {}
            _G.CreateFrame = function()
                local f = permissive()
                made[#made + 1] = f
                return f
            end
            local f = mod:_Acquire()
            _G.CreateFrame = noFrame
            ok(f ~= nil and f == made[1] and mod.frame == f, s.name .. ": the frame is built and kept")
            local up = f and f.scripts.OnMouseUp
            ok(type(up) == "function", s.name .. ": the frame answers a mouse release")
            if type(up) ~= "function" then return end
            up(f, "LeftButton")
            ok(#st.shown == 0, s.name .. ": a left release opens nothing, since a left drag moves the frame")
            up(f, "RightButton")
            ok(#st.shown == 1 and names(st.shown[1]) == s.title .. " | Lock position | Reset position | divider | Cancel",
               s.name .. ": a right release opens the menu: " .. names(st.shown[1]))
        end)
        _G.CreateFrame = noFrame
        ok(good, s.name .. ": the right-click case raised: " .. tostring(err))
    end

    print("== " .. s.name .. ": every word on the menu comes through the locale table")
    do
        local good, err = pcall(function()
            local mod, st = load(s, { locked = false }, false, true)
            open(mod, s.name .. " translated")
            local want = "<" .. s.title .. "> | <Lock position> | <Reset position> | divider | <Cancel>"
            ok(names(st.shown[1]) == want, s.name .. ": " .. names(st.shown[1]))
            mod, st = load(s, { locked = true }, false, true)
            open(mod, s.name .. " translated, locked")
            ok((st.shown[1] or {})[2] and st.shown[1][2].text == "<Unlock (allow moving)>",
               s.name .. ": and the Unlock item too")
        end)
        ok(good, s.name .. ": the translated menu raised: " .. tostring(err))
    end
end

print(("test_chrome_menus: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
