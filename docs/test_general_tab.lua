-- Unit tests for Options/TabGeneral.lua, run against the SHIPPED source.
-- Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_general_tab.lua
--
-- The tab loads WHOLE over a stub context that records every control, button and dialog, and
-- stub modules that record the calls these cases check. The Use Blizzard's quest tracker box has
-- its own cases in test_blizzard_tracker.lua, which boots the addon around it. This file covers the
-- rest of the tab: the footer's two resets, Lock tracker, the hide rules, the two plain boxes,
-- Hide Questie's quest tracker, the Options Window Scale slider and the whole profile flow.
--
-- Every lookup in the locale table reads "<key>", so a hard-coded English string cannot pass for
-- a translated one.
--
-- OUT OF SCOPE BY CONSTRUCTION: what the library draws, and what AceDB does with a profile call.

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
end

local pass, fail = 0, 0
-- Core/DB.lua's accessors read self, so a module calling one with a dot raises in game. This
-- stand-in raises the same way, rather than answering a call the client would refuse.
local function strictDB(methods)
    local db = {}
    for name, v in pairs(methods) do
        if type(v) == "function" then
            db[name] = function(self, ...)
                if self ~= db then error("DB:" .. name .. " called without self", 2) end
                return v(self, ...)
            end
        else
            db[name] = v
        end
    end
    return db
end

local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end

local function case(name, fn)
    print("== " .. name)
    local good, err = pcall(fn)
    ok(good, name .. " raised: " .. tostring(err))
end

local function K(key) return "<" .. key .. ">" end

local function frame()
    local f = { shown = true, points = {}, hooks = {} }
    function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function f:SetChecked(v) self.checked = v end
    function f:HookScript(e, fn) self.hooks[e] = fn end
    return f
end

-- o.profiles is the profile list AceDB answers with, o.current the active one, o.mythicPlus and
-- o.questie the two optional rows, o.questieAddon and o.questieFrame Questie's two globals, and
-- o.noGlobal a DB that has not initialized.
local function generalTab(o)
    o = o or {}
    local st = { log = {}, dialogs = {}, scales = 0, lock = 0, applies = 0, questie = 0,
                 general = {}, global = {}, current = o.current or "Default",
                 profiles = o.profiles or { "Zeta", "Alpha", "Default" } }
    local function log(s) st.log[#st.log + 1] = s end
    local modules = {}
    local ns = {
        L = setmetatable({}, { __index = function(_, k) return K(k) end }),
        Has = { MythicPlus = o.mythicPlus },
    }
    function ns:GetModule(name) return modules[name] end
    function ns:Print() end
    local spec
    modules.Options = {
        RegisterTab = function(_, s) spec = s end,
        ApplyWindowScale = function() st.scales = st.scales + 1 end,
    }
    local db = {}
    function db:GetProfiles() local out = {} for i, p in ipairs(st.profiles) do out[i] = p end return out end
    function db:GetCurrentProfile() return st.current end
    function db:SetProfile(name) log("set:" .. name) st.current = name end
    function db:CopyProfile(source, silent) log("copy:" .. tostring(source) .. ":" .. tostring(silent)) end
    modules.DB = {
        db = db,
        General = function() return st.general end,
        Global = function() if not o.noGlobal then return st.global end end,
        ResetAll = function() log("resetAll") end,
    }
    modules.DB = strictDB(modules.DB)
    modules.Tracker = {
        ResetPosition = function() log("resetPosition") end,
        ApplyLockState = function() st.lock = st.lock + 1 end,
    }
    modules.Visibility = { Apply = function() st.applies = st.applies + 1 end }
    modules.API = {
        GetBlizzardTrackerSetting = function() return false end,
        SetBlizzardTrackerSetting = function() return true end,
    }
    modules.Dialog = { Show = function(_, d) st.dialogs[#st.dialogs + 1] = d end }
    modules.QuestieCoexist = {
        QuestiePresent = function() return o.questie == true end,
        Apply = function() st.questie = st.questie + 1 end,
    }

    local ui = { boxes = {}, buttons = {}, cards = {} }
    function ui:CreateGroup(_, label)
        local card = frame()
        card.title, card.rows, card.label = label, {}, frame()
        card.Add = function(c, control) c.rows[#c.rows + 1] = control return frame() end
        ui.cards[#ui.cards + 1] = card
        return card
    end
    function ui:CreateCheckbox(_, label, getter, setter, tooltip)
        local f = frame()
        f.label, f.getter, f.setter, f.tooltip = label, getter, setter, tooltip
        ui.boxes[label] = f
        return f
    end
    function ui:CreateSlider(_, label, minV, maxV, step, getter, setter, tooltip)
        local f = frame()
        f.label, f.min, f.max, f.step, f.getter, f.setter, f.tooltip = label, minV, maxV, step, getter, setter, tooltip
        f.slider = frame()
        ui.slider = f
        return f, f.slider
    end
    function ui:CreateButton(_, label, width, onClick, tooltip)
        local f = frame()
        f.label, f.width, f.onClick, f.tooltip = label, width, onClick, tooltip
        ui.buttons[label] = f
        return f
    end
    function ui:CreateDropdown(_, label, options, getter, setter, tooltip)
        local f = frame()
        f.label, f.options, f.getter, f.setter, f.tooltip = label, options, getter, setter, tooltip
        ui.dropdown = f
        return f
    end
    function ui:AttachTooltip() end
    function ui:Spacing() return 10 end

    local env = setmetatable({
        ReloadUI = function() log("reload") end,
        C_Timer = { After = function() end },
        Questie = o.questieAddon,
        Questie_BaseFrame = o.questieFrame,
    }, { __index = _G })
    local chunk = assert(loadfile(repoFile("Options/TabGeneral.lua")))
    setfenv(chunk, env)
    chunk("EQObjectiveTracker", ns)
    spec.build(ui, frame())
    st.bar = frame()
    spec.footer(ui, st.bar)
    st.ui, st.spec = ui, spec
    return st
end

local function joined(st) return table.concat(st.log, ",") end

case("Reset all settings asks first, then resets everything, puts the tracker back and reloads", function()
    local st = generalTab()
    local b = st.ui.buttons[K"Reset all settings"]
    ok(b and type(b.onClick) == "function", "the footer carries Reset all settings")
    b.onClick()
    local d = st.dialogs[1] or {}
    ok(#st.dialogs == 1 and d.button1 == K"Reset" and d.button2 == K"Cancel" and type(d.onAccept) == "function",
       "a click asks first, with Reset and Cancel")
    ok(joined(st) == "", "and nothing happens before Yes: " .. joined(st))
    d.onAccept()
    ok(joined(st) == "resetAll,resetPosition,reload",
       "Yes resets the settings, puts the live tracker back, then reloads: " .. joined(st))
end)

case("Reset position and size puts the tracker back without a reload", function()
    local st = generalTab()
    local b = st.ui.buttons[K"Reset position and size"]
    ok(b and type(b.onClick) == "function", "the footer carries Reset position and size")
    b.onClick()
    ok(joined(st) == "resetPosition", "a click resets the position at once, and only that: " .. joined(st))
    ok(#st.dialogs == 0, "with no dialog")
    local p = b.points[1] or {}
    ok(p[1] == "RIGHT" and p[2] == st.ui.buttons[K"Reset all settings"] and p[3] == "LEFT",
       "left of Reset all settings")
end)

case("Lock tracker stores the lock and applies it", function()
    local st = generalTab()
    local box = st.ui.boxes[K"Lock tracker"]
    box.setter(true)
    ok(st.general.lockTracker == true and st.lock == 1, "ticked, it locks and applies once")
    box.setter(false)
    ok(st.general.lockTracker == false and st.lock == 2, "unticked, it unlocks and applies again")
    st.general.lockTracker = true
    ok(box.getter() == true, "and reads the stored lock")
end)

case("each hide rule stores its key and re-applies the visibility rules", function()
    local function drive(st, label, key)
        local box = st.ui.boxes[K(label)]
        ok(box ~= nil, label .. " is built")
        if not box then return end
        local before = st.applies
        box.setter(true)
        ok(st.general[key] == true and st.applies == before + 1, label .. " stores " .. key .. " and applies once")
        box.setter(false)
        ok(st.general[key] == false and st.applies == before + 2, label .. " stores it off and applies again")
        st.general[key] = true
        ok(box.getter() == true, label .. " reads " .. key)
    end
    local st = generalTab({ mythicPlus = true })
    drive(st, "Hide tracker in combat", "hideInCombat")
    drive(st, "Hide tracker in instances", "hideInInstances")
    drive(st, "Hide tracker when world map is open", "hideOnMapOpen")
    drive(st, "Hide tracker in Mythic+", "hideInMythicPlus")
    drive(st, "Hide tracker when no quests are showing", "hideWhenNoQuests")
    ok(generalTab().ui.boxes[K"Hide tracker in Mythic+"] == nil, "a client with no Mythic+ gets no Mythic+ box")
end)

case("Auto-track and Keep focused quest store their keys, on by default", function()
    local st = generalTab()
    local auto = st.ui.boxes[K"Auto-track accepted quests"]
    ok(auto.getter() == true, "auto-track reads on while unset")
    auto.setter(false)
    ok(st.general.autoTrackAccepted == false and auto.getter() == false, "and stores off")
    auto.setter(true)
    ok(st.general.autoTrackAccepted == true, "and on")
    local keep = st.ui.boxes[K"Keep focused quest after relog"]
    ok(keep.getter() == true, "keep focused reads on while unset")
    keep.setter(false)
    ok(st.general.restoreSuperTrackOnLogin == false and keep.getter() == false, "and stores off")
end)

case("Hide Questie's quest tracker is offered only beside Questie, and unticking asks Questie first", function()
    ok(generalTab().ui.boxes[K"Hide Questie's quest tracker"] == nil, "no Questie, no box")
    local qframe = { shows = 0 }
    function qframe:Show() self.shows = self.shows + 1 end
    local questie = { db = { profile = {} } }
    local st = generalTab({ questie = true, questieAddon = questie, questieFrame = qframe })
    local box = st.ui.boxes[K"Hide Questie's quest tracker"]
    ok(box ~= nil, "beside Questie, the box is built")
    if not box then return end
    local inCard = false
    for _, row in ipairs(st.ui.cards[1].rows) do if row == box then inCard = true end end
    ok(inCard, "on the General card")
    ok(not box.getter(), "off while unset")
    box.setter(true)
    ok(st.general.hideQuestieTracker == true and st.questie == 1, "ticked, it stores on and hides Questie's tracker")
    ok(qframe.shows == 0, "and never shows it")
    box.setter(false)
    ok(st.general.hideQuestieTracker == false and st.questie == 1, "unticked, it stores off and hides nothing")
    ok(qframe.shows == 1, "and shows Questie's tracker, which Questie keeps on while its setting is unset")
    questie.db.profile.trackerEnabled = false
    box.setter(false)
    ok(qframe.shows == 1, "but not while Questie has its own tracker turned off")
    questie.db.profile.trackerEnabled = true
    box.setter(false)
    ok(qframe.shows == 2, "and does again once Questie has it on")

    local other = { shows = 0 }
    function other:Show() self.shows = self.shows + 1 end
    local unread = generalTab({ questie = true, questieAddon = { db = "unreadable" }, questieFrame = other })
    unread.ui.boxes[K"Hide Questie's quest tracker"].setter(false)
    ok(other.shows == 1, "a Questie whose settings cannot be read gets its tracker back")
    local frameless = generalTab({ questie = true, questieAddon = questie })
    local good, err = pcall(frameless.ui.boxes[K"Hide Questie's quest tracker"].setter, false)
    ok(good, "with no Questie frame to show, unticking raises nothing: " .. tostring(err))
end)

case("the Options Window Scale slider stores its value and resizes the window on release", function()
    local st = generalTab()
    local s = st.ui.slider
    ok(s and s.label == K"Options Window Scale" and s.min == 0.7 and s.max == 1.4 and s.step == 0.05,
       "the slider runs 0.7 to 1.4 in steps of 0.05")
    ok(s.getter() == 1.0, "reading 1 while unset")
    s.setter(0.9)
    ok(st.global.optionsWindowScale == 0.9, "a drag stores the value on the account")
    ok(s.getter() == 0.9, "and the slider reads the saved value back")
    ok(st.scales == 0, "but does not resize the window under the mouse mid-drag")
    s.setter(0)
    ok(st.global.optionsWindowScale == 0.9, "a zero is never stored")
    local up = s.slider.hooks.OnMouseUp
    ok(type(up) == "function", "letting go of the slider is hooked")
    if up then up() end
    ok(st.scales == 1, "and resizes the window once: " .. st.scales)

    local early = generalTab({ noGlobal = true })
    local good, v = pcall(early.ui.slider.getter)
    ok(good and v == 1.0, "before the DB is ready it reads 1: " .. tostring(v))
    local good2, err = pcall(early.ui.slider.setter, 1.2)
    ok(good2, "and a drag raises nothing: " .. tostring(err))
end)

case("Active profile lists the profiles sorted, and a pick switches and reloads", function()
    local st = generalTab()
    local dd = st.ui.dropdown
    ok(dd and dd.label == K"Active profile", "the profile dropdown is built")
    local names = {}
    for _, opt in ipairs(dd.options()) do names[#names + 1] = opt.value .. "=" .. opt.label end
    ok(table.concat(names, ",") == "Alpha=Alpha,Default=Default,Zeta=Zeta", "sorted by name: " .. table.concat(names, ","))
    ok(dd.getter() == "Default", "it shows the active profile")
    dd.setter("Alpha")
    ok(joined(st) == "set:Alpha,reload", "a pick switches the profile, then reloads: " .. joined(st))
end)

case("New Profile asks for a name", function()
    local st = generalTab()
    local b = st.ui.buttons[K"New Profile"]
    ok(b and type(b.onClick) == "function", "the New Profile button is built")
    b.onClick()
    local d = st.dialogs[1] or {}
    ok(#st.dialogs == 1 and d.title == K"New Profile" and d.hasEditBox == true and d.maxLetters == 32
       and d.button1 == K"Create" and d.button2 == K"Cancel" and (d.editBoxText or "") == "",
       "a click asks for a name in an empty field of up to 32 letters")
    ok(joined(st) == "", "and creates nothing yet")
    local p = b.points[1] or {}
    ok(p[1] == "RIGHT" and p[3] == "RIGHT" and p[4] == -10, "at the end of the profile row")
end)

case("an empty name asks again rather than closing", function()
    local st = generalTab()
    st.ui.buttons[K"New Profile"].onClick()
    st.dialogs[1].onAccept("")
    ok(#st.dialogs == 2 and st.dialogs[2].hasEditBox == true, "an empty name opens the prompt again")
    ok(joined(st) == "", "and creates nothing: " .. joined(st))
    st.dialogs[2].onAccept("   ")
    ok(#st.dialogs == 3 and st.dialogs[3].editBoxText == "   ", "spaces only ask again, keeping what was typed")
    ok(joined(st) == "", "and still create nothing")
end)

case("a new name makes a copy of the current settings, switches to it and reloads", function()
    local st = generalTab()
    st.ui.buttons[K"New Profile"].onClick()
    st.dialogs[1].onAccept("  Raid  ")
    ok(#st.dialogs == 1, "a new name asks nothing more")
    ok(joined(st) == "set:Raid,copy:Default:true,reload",
       "trimmed, created as a copy of the current profile, then a reload: " .. joined(st))
end)

case("a name already taken asks before overwriting it", function()
    local st = generalTab()
    st.ui.buttons[K"New Profile"].onClick()
    st.dialogs[1].onAccept("Alpha")
    local d = st.dialogs[2] or {}
    ok(#st.dialogs == 2 and d.title == K"Overwrite profile?" and d.button1 == K"Overwrite" and d.button2 == K"Cancel",
       "an existing name asks to overwrite it")
    ok(d.text and d.text:find("Alpha", 1, true) ~= nil, "naming the profile: " .. tostring(d.text))
    ok(joined(st) == "", "and touches nothing before the answer: " .. joined(st))
    d.onAccept()
    ok(joined(st) == "set:Alpha,copy:Default:true,reload", "Yes overwrites it with a copy: " .. joined(st))

    local same = generalTab()
    same.ui.buttons[K"New Profile"].onClick()
    same.dialogs[1].onAccept("Default")
    ok(#same.dialogs == 1 and joined(same) == "set:Default,reload",
       "the current profile's own name needs no question and copies nothing onto itself: " .. joined(same))
end)

print(("test_general_tab: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
