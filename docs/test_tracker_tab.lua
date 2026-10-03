-- Unit tests for Options/TabTracker.lua, run against the SHIPPED source.
-- Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_tracker_tab.lua
--
-- The tab loads WHOLE over a stub context that records every control, and stub modules that
-- record the calls these cases check. The Filters card has its own cases in test_filter.lua. This
-- file covers the rest: Sort Order and its Manual hint, Simplify tracked achievements, the section
-- show boxes, the World Quests height controls, World Quests Position, the Section Order rows and
-- their chevrons, the difficulty box's dimming, the display boxes and the three sounds.
--
-- Every lookup in the locale table reads "<key>", so a hard-coded English string cannot pass for
-- a translated one.
--
-- OUT OF SCOPE BY CONSTRUCTION: what the library draws, and what the tracker does with a setting.

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

local function K(key) return "<" .. key .. ">" end

local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.0001 end

local function frame()
    local f = { shown = true, scripts = {}, enabled = true }
    function f:SetPoint() end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:SetShown(v) self.shown = v and true or false end
    function f:IsShown() return self.shown end
    function f:SetChecked(v) self.checked = v end
    function f:SetText(s) self.text = s end
    function f:SetEnabled(v) self.enabled = v and true or false end
    function f:SetScript(e, fn) self.scripts[e] = fn end
    function f:HookScript() end
    return f
end

-- o.order is the tracker's section order, o.known the sections the TOC loaded, o.tags the
-- provider tags, o.cfg the saved settings.
local function trackerTab(o)
    o = o or {}
    local st = { cfg = o.cfg or { filters = {} }, render = 0, invalidate = 0, icons = 0, played = {}, moves = {},
                 hidden = {}, tipHides = 0, arrows = {}, dims = {}, measured = {}, wqPositions = {},
                 order = o.order or { "campaign", "quests", "achievements" } }
    local modules = {}
    local ns = {
        L = setmetatable({}, { __index = function(_, k) return K(k) end }),
        Util = { Tooltip = function()
            return { Hide = function() st.tipHides = st.tipHides + 1 end, SetOwner = function() end,
                     SetText = function() end, AddLine = function() end, Show = function() end }
        end },
    }
    function ns:GetModule(name) return modules[name] end
    local spec
    modules.Options = { RegisterTab = function(_, s) spec = s end }
    modules.DB = { Tracker = function() return st.cfg end }
    modules.Tracker = {
        Render = function() st.render = st.render + 1 end,
        ApplyHeaderIcons = function() st.icons = st.icons + 1 end,
        SetWorldQuestsPosition = function(_, v) st.wqPositions[#st.wqPositions + 1] = v end,
    }
    modules.Row = { Invalidate = function() st.invalidate = st.invalidate + 1 end }
    modules.Media = {
        Play = function(_, v) st.played[#st.played + 1] = v end,
        GetSoundList = function() return { "None", "Bell" }, { None = "NONE", Bell = "bell" } end,
    }
    modules.Sections = {
        Known = function() return o.known or { "campaign", "quests", "achievements" } end,
        Order = function()
            local out = {}
            for i, id in ipairs(st.order) do out[i] = id end
            return out
        end,
        IsHidden = function(_, id) return st.hidden[id] == true end,
        SetHidden = function(_, id, h) st.hidden[id] = h or nil end,
        Title = function(_, id) return "title:" .. id end,
        Move = function(_, id, delta)
            st.moves[#st.moves + 1] = id .. ":" .. delta
            for i, v in ipairs(st.order) do
                if v == id then
                    local j = i + delta
                    if st.order[j] then st.order[i], st.order[j] = st.order[j], st.order[i] end
                    break
                end
            end
        end,
    }
    modules.Filter = { CATEGORIES = { { key = "showNormal", label = "Normal" } } }
    local tags = o.tags or { worldquest = true }
    modules.Registry = { HasTag = function(_, tag) return tags[tag] == true end }

    local ui = { boxes = {}, dropdowns = {}, cards = {}, sliders = {}, radios = {} }
    function ui:CreateGroup(_, label)
        local card = frame()
        card.title, card.rows, card.label = label, {}, frame()
        card.Add = function(c, control, opts)
            c.rows[#c.rows + 1] = control
            control.dependent = opts and opts.dependent and true or false
            control.fill = opts and opts.fill and true or false
            return frame()
        end
        card.layouts = 0
        card.Layout = function(c) c.layouts = c.layouts + 1 end
        ui.cards[label] = card
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
        ui.sliders[label] = f
        return f
    end
    function ui:CreateDropdown(_, label, options, getter, setter, tooltip, _, onTest)
        local f = frame()
        f.label, f.options, f.getter, f.setter, f.tooltip, f.onTest = label, options, getter, setter, tooltip, onTest
        ui.dropdowns[label] = f
        return f
    end
    function ui:CreateRadioGroup(_, label, options, getter, setter, _, _, tipTitle, tipBody)
        local f = frame()
        f.label, f.options, f.getter, f.setter, f.tipTitle, f.tipBody = label, options, getter, setter, tipTitle, tipBody
        ui.radios[label] = f
        return f
    end
    function ui:CreateButton(_, label, _, onClick) local f = frame() f.label, f.onClick = label, onClick return f end
    function ui:CreateText(_, text, style) local f = frame() f.text, f.style = text, style return f end
    function ui:CreateIconButton(_, icon, size, flip)
        local f = frame()
        f.icon, f.size, f.flip = icon, size, flip
        st.arrows[#st.arrows + 1] = f
        return f
    end
    function ui:AttachTooltip() end
    function ui:SetDependent(control, on) st.dims[control] = on and true or false end
    function ui:MeasureContent(content) st.measured[#st.measured + 1] = content end
    function ui:Spacing() return 10 end

    assert(loadfile(repoFile("Options/TabTracker.lua")))("EQObjectiveTracker", ns)
    st.content = {}
    spec.build(ui, st.content)
    st.ui, st.spec = ui, spec
    return st
end

-- The Section Order card's rows after the World Quests Position control, each with the chevrons
-- that carry its section id.
local function orderRows(st)
    local out = {}
    local rows = st.ui.cards[K"Section Order"].rows
    for i = 2, #rows do
        local name = rows[i]
        local up, down
        for _, a in ipairs(st.arrows) do
            if a.shown and a.row == name then
                if a.flip then up = a else down = a end
            end
        end
        out[#out + 1] = { name = name, up = up, down = down }
    end
    return out
end

-- Arrows are matched to their row by build order: each row builds its down chevron, then its up.
local function tagArrows(st)
    local rows = st.ui.cards[K"Section Order"].rows
    for i = 2, #rows do
        local down, up = st.arrows[(i - 2) * 2 + 1], st.arrows[(i - 2) * 2 + 2]
        if down then down.row = rows[i] end
        if up then up.row = rows[i] end
    end
end

local function labels(rows)
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = tostring(r.name.text) end
    return table.concat(out, ",")
end

local function values(options)
    local out = {}
    for _, opt in ipairs(options or {}) do out[#out + 1] = tostring(opt.value) .. "=" .. tostring(opt.label) end
    return table.concat(out, ",")
end

case("Sort Order stores the pick, and its hint row shows only on Manual", function()
    local st = trackerTab()
    local sort = st.ui.radios[K"Sort Order"]
    ok(sort ~= nil, "Sort Order is built")
    local orders = {}
    for _, opt in ipairs(sort.options) do orders[#orders + 1] = opt.value end
    ok(table.concat(orders, ",") == "zone,title,status,type,level,distance,recent,manual",
       "eight orders, Manual last: " .. table.concat(orders, ","))
    ok(sort.options[8].label == K"Manual", "each named through the locale table: " .. tostring(sort.options[8].label))
    ok(sort.getter() == "zone", "reading Zone while unset")
    local onScreen = st.ui.cards[K"On-Screen Tracker"]
    local hint = onScreen.rows[#onScreen.rows]
    ok(onScreen.rows[#onScreen.rows - 1] == sort and hint.style == "hint"
       and hint.text == K"Drag and drop the quests in the tracker to reorder them however you like.",
       "the hint is the row under Sort Order")
    ok(hint.dependent == true and hint.fill == true, "indented under it and full width")
    ok(hint.shown == false, "hidden while the order is not Manual")
    local renders, layouts, measures = st.render, onScreen.layouts, #st.measured
    sort.setter("manual")
    ok(st.cfg.sortMode == "manual" and st.render == renders + 1, "a pick is stored and the tracker redraws once")
    ok(hint.shown == true, "Manual shows the hint")
    ok(onScreen.layouts == layouts + 1, "and the card is laid out again for it")
    ok(#st.measured == measures + 1 and st.measured[#st.measured] == st.content,
       "and the tab measured again, since every card under it moves")
    sort.setter("title")
    ok(st.cfg.sortMode == "title" and hint.shown == false, "any other order hides it again")
    local manual = trackerTab({ cfg = { filters = {}, sortMode = "manual" } })
    local card = manual.ui.cards[K"On-Screen Tracker"]
    ok(card.rows[#card.rows].shown == true, "a tab built on Manual shows the hint from the start")
    ok(manual.ui.radios[K"Sort Order"].getter() == "manual", "and reads the saved order")
end)

case("Simplify tracked achievements stores its own group and keeps the others", function()
    local st = trackerTab({ cfg = { filters = {}, simplifyGroups = { quests = true } } })
    local box = st.ui.boxes[K"Simplify tracked achievements"]
    ok(box ~= nil, "the box is built")
    ok(not box.getter(), "off while the achievements group is unset")
    local renders, inv = st.render, st.invalidate
    box.setter(true)
    ok(st.cfg.simplifyGroups.achievements == true, "on, it stores the achievements group")
    ok(st.cfg.simplifyGroups.quests == true, "beside the group already there")
    ok(st.render == renders + 1 and st.invalidate == inv, "and the tracker redraws once")
    ok(box.getter() == true, "and reads it back")
    box.setter(false)
    ok(st.cfg.simplifyGroups.achievements == false and not box.getter(), "off again, it stores off")
    local fresh = trackerTab()
    fresh.ui.boxes[K"Simplify tracked achievements"].setter(true)
    ok(fresh.cfg.simplifyGroups and fresh.cfg.simplifyGroups.achievements == true,
       "a profile with no groups yet gets the table")
end)

case("Section Order names every section in the tracker's order, with its own chevrons", function()
    local st = trackerTab()
    tagArrows(st)
    local rows = orderRows(st)
    ok(#rows == 3, "one row per section: " .. #rows)
    ok(labels(rows) == "title:campaign,title:quests,title:achievements", "in the tracker's order: " .. labels(rows))
    for i, r in ipairs(rows) do
        ok(r.up and r.up.flip == true and r.up.icon == "chevron-down", "row " .. i .. " has an up chevron, the chevron flipped")
        ok(r.down and r.down.flip ~= true and r.down.icon == "chevron-down", "row " .. i .. " has a down chevron")
        ok(r.up and r.up.sectionID == st.order[i] and r.down and r.down.sectionID == st.order[i],
           "row " .. i .. "'s chevrons carry its section, for their tooltip")
    end
    ok(rows[1].up and rows[1].up.enabled == false, "the first section cannot move up")
    ok(rows[3].down and rows[3].down.enabled == false, "the last cannot move down")
    ok(rows[1].down.enabled and rows[2].up.enabled and rows[2].down.enabled and rows[3].up.enabled,
       "and every other chevron is live")
end)

case("the Up chevron moves its section up, and the rows follow", function()
    local st = trackerTab()
    tagArrows(st)
    local rows = orderRows(st)
    local renders, tips = st.render, st.tipHides
    local layouts = st.ui.cards[K"Section Order"].layouts
    rows[2].up.scripts.OnClick()
    ok(st.moves[1] == "quests:-1", "it moves Quests up one: " .. tostring(st.moves[1]))
    ok(st.render == renders + 1, "the tracker redraws once")
    rows = orderRows(st)
    ok(labels(rows) == "title:quests,title:campaign,title:achievements", "the rows are named again in the new order: " .. labels(rows))
    ok(rows[1].up.sectionID == "quests" and rows[2].up.sectionID == "campaign", "and their chevrons follow")
    ok(rows[1].up.enabled == false and rows[2].up.enabled == true, "Quests, now first, can no longer move up")
    ok(st.tipHides == tips + 1, "the tooltip naming the old section is put away")
    ok(st.ui.cards[K"Section Order"].layouts == layouts + 1, "and the card is laid out again, once")
end)

case("the Down chevron moves its section down, and the rows follow", function()
    local st = trackerTab()
    tagArrows(st)
    local rows = orderRows(st)
    local renders, tips = st.render, st.tipHides
    rows[1].down.scripts.OnClick()
    ok(st.moves[1] == "campaign:1", "it moves Campaign down one: " .. tostring(st.moves[1]))
    ok(st.render == renders + 1, "the tracker redraws once")
    rows = orderRows(st)
    ok(labels(rows) == "title:quests,title:campaign,title:achievements", "the rows are named again: " .. labels(rows))
    ok(rows[2].down.sectionID == "campaign", "and the chevrons follow")
    ok(st.tipHides == tips + 1, "the tooltip naming the old section is put away")
end)

case("World Quests Position heads Section Order and hands the tracker the pick", function()
    local st = trackerTab()
    local pos = st.ui.radios[K"World Quests Position"]
    ok(pos ~= nil and st.ui.cards[K"Section Order"].rows[1] == pos, "the first row of Section Order")
    ok(pos.shown == true, "shown where a provider has world quests")
    ok(values(pos.options) == "top=" .. K"Top" .. ",bottom=" .. K"Bottom", "Top or Bottom: " .. values(pos.options))
    ok(pos.getter() == "bottom", "reading Bottom while unset")
    st.cfg.worldQuestsPosition = "top"
    ok(pos.getter() == "top", "and the saved side once set")
    pos.setter("top")
    ok(#st.wqPositions == 1 and st.wqPositions[1] == "top", "a pick goes to the tracker, which moves the panel")
    ok(pos.tipTitle == K"World Quests Position" and type(pos.tipBody) == "string" and pos.tipBody ~= "",
       "its tooltip titled with its own label")
    local none = trackerTab({ tags = {} })
    local hidden = none.ui.radios[K"World Quests Position"]
    ok(hidden and hidden.shown == false, "hidden where nothing has a world quest")
end)

case("the custom World Quests height switch lights its own slider and dims the other", function()
    local st = trackerTab()
    local box = st.ui.boxes[K"Set a custom World Quests height"]
    local height = st.ui.sliders[K"World Quests Height"]
    local share = st.ui.sliders[K"Maximum Height (percent of tracker)"]
    ok(box and height and share, "the switch and both sliders are built")
    if not (box and height and share) then return end
    ok(height.dependent == true and share.dependent == true, "both sliders sit indented under it")
    ok(st.dims[height] == false and st.dims[share] == true, "off, the fixed height is dimmed and the share is live")
    local renders = st.render
    box.setter(true)
    ok(st.cfg.worldQuestsHeightOverride == true and st.render == renders + 1, "on, it is stored and the tracker redraws")
    ok(st.dims[height] == true and st.dims[share] == false, "and the fixed height is live, the share dimmed")
    box.setter(false)
    ok(st.dims[height] == false and st.dims[share] == true, "off again, back the other way")
    local on = trackerTab({ cfg = { filters = {}, worldQuestsHeightOverride = true } })
    ok(on.dims[on.ui.sliders[K"World Quests Height"]] == true
       and on.dims[on.ui.sliders[K"Maximum Height (percent of tracker)"]] == false,
       "a tab built with it on starts the right way round")

    ok(height.min == 40 and height.max == 400 and height.step == 10 and height.getter() == 200,
       "the fixed height runs 40 to 400 in tens, 200 while unset")
    renders = st.render
    height.setter(250)
    ok(st.cfg.worldQuestsHeight == 250 and st.render == renders + 1, "and stores its pixels and redraws")
    ok(share.min == 10 and share.max == 80 and share.step == 5 and near(share.getter(), 40),
       "the share runs 10 to 80 percent in fives, 40 while unset")
    share.setter(60)
    ok(near(st.cfg.worldQuestsPinnedMaxFraction, 0.6) and st.render == renders + 2,
       "and stores a fraction of the tracker and redraws: " .. tostring(st.cfg.worldQuestsPinnedMaxFraction))
    st.cfg.worldQuestsPinnedMaxFraction = 0.25
    ok(near(share.getter(), 25), "reading a saved fraction as a percent")

    local none = trackerTab({ tags = {} })
    ok(none.ui.boxes[K"Set a custom World Quests height"] == nil and none.ui.sliders[K"World Quests Height"] == nil
       and none.ui.boxes[K"Auto-list current-zone world quests"] == nil,
       "none of the World Quests controls where nothing has a world quest")
end)

case("each section show box hides and shows its own section", function()
    local st = trackerTab({ known = { "campaign", "quests" } })
    local camp, quests = st.ui.boxes[K"Campaign section"], st.ui.boxes[K"Quests section"]
    ok(camp and quests, "a box for each section the TOC loaded")
    ok(st.ui.boxes[K"Profession section"] == nil, "and none for a section it did not")
    ok(camp.getter() == true, "a shown section reads ticked")
    local renders = st.render
    camp.setter(false)
    ok(st.hidden.campaign == true and st.hidden.quests == nil, "unticked, its own section is hidden")
    ok(st.render == renders + 1, "and the tracker redraws")
    ok(camp.getter() == false, "and the box reads unticked")
    camp.setter(true)
    ok(st.hidden.campaign == nil and camp.getter() == true, "ticked again, it shows again")
end)

case("the three sounds: each switch stores its key, each picker stores and plays its pick", function()
    local st = trackerTab()
    local b = st.ui.boxes
    ok(b[K"Quest Sound"].getter() == true, "Quest Sound is on while unset")
    b[K"Quest Sound"].setter(false)
    ok(st.cfg.questSoundEnabled == false and b[K"Quest Sound"].getter() == false, "and stores off")
    for _, k in ipairs({ { "Play a sound when you accept a quest", "questAcceptSoundEnabled" },
                         { "Play a sound when you turn a quest in", "questTurnInSoundEnabled" } }) do
        ok(b[K(k[1])].getter() == false, k[1] .. " is off while unset")
        b[K(k[1])].setter(true)
        ok(st.cfg[k[2]] == true and b[K(k[1])].getter() == true, k[1] .. " stores on")
    end
    for _, k in ipairs({ { "Quest Complete Sound", "questCompleteSound" },
                         { "Quest Accepted Sound", "questAcceptSound" },
                         { "Quest Turned In Sound", "questTurnInSound" } }) do
        local dd = st.ui.dropdowns[K(k[1])]
        ok(dd and dd.getter() == "NONE", k[1] .. " reads no sound while unset")
        local opts = {}
        for _, opt in ipairs(dd.options()) do opts[#opts + 1] = opt.value .. "=" .. opt.label end
        ok(table.concat(opts, ",") == "NONE=None,bell=Bell", k[1] .. " lists the sounds by name: " .. table.concat(opts, ","))
        local played = #st.played
        dd.setter("bell")
        ok(st.cfg[k[2]] == "bell", k[1] .. " stores the pick")
        ok(#st.played == played + 1 and st.played[#st.played] == "bell", k[1] .. " plays the pick so it can be heard")
        ok(type(dd.onTest) == "function", k[1] .. " has a speaker")
        if dd.onTest then dd.onTest("bell") end
        ok(#st.played == played + 2, k[1] .. "'s speaker plays it again")
        ok(dd.dependent == true, k[1] .. " sits indented under its switch")
        ok(st.dims[dd] == nil, k[1] .. " is never dimmed")
    end
end)

case("the difficulty box dims under a title color set on Appearance, read again on every view", function()
    local st = trackerTab()
    local diff = st.ui.boxes[K"Quest Title Color By Difficulty"]
    ok(st.dims[diff] == true, "lit when no title color is set")
    st.cfg.titleColorOverride = { r = 1, g = 0, b = 0 }
    st.spec.refresh(st.ui, st.content)
    ok(st.dims[diff] == false, "dimmed on the next view once a title color is set")
    st.cfg.titleColorOverride = nil
    st.cfg.titleColorUseClass = true
    st.spec.refresh(st.ui, st.content)
    ok(st.dims[diff] == false, "and while class colored titles are on")
    st.cfg.titleColorUseClass = false
    st.spec.refresh(st.ui, st.content)
    ok(st.dims[diff] == true, "lit again with neither")
end)

case("Show Options icon applies at once", function()
    local st = trackerTab()
    local box = st.ui.boxes[K"Show Options icon on the tracker"]
    ok(box.getter() == true, "on while unset")
    box.setter(false)
    ok(st.cfg.showOptionsIcon == false and st.icons == 1, "unticked, it stores off and redraws the header icons")
end)

-- Each changes how a row reads, so the rows are invalidated before the redraw.
local ROW_BOXES = {
    { "Quest Title Color By Difficulty", "colorByDifficulty", true },
    { "Show quest level prefix", "showLevelInTracker", false },
    { "Show zone label under quest titles", "showZoneTag", false },
    { "Show objective progress numbers", "showObjectiveNumbers", true },
    { "Show event and scenario widgets", "showTrackerWidgets", true },
    { "Show quest ID", "showQuestID", false },
    { "Show usable quest item buttons", "showItemButtons", true },
    { "Show NEW tag on recently accepted quests", "showRecentlyAddedTag", true },
}

-- None changes a drawn row's look outside the text Row's repaint gate compares, so a redraw is enough.
local PLAIN_BOXES = {
    { "Show only tracked quests", "showOnlyWatched" },
    { "Simplify Mode", "simplifyMode" },
    { "Split quest click", "splitQuestClick" },
    { "Auto-list current-zone world quests", "autoListZoneWorldQuests" },
    { "Show the visible / total count on section headers", "showQuestTotal" },
    { "Show Quest Discovered popups", "showQuestPopups" },
}

case("a display box that changes how a row reads invalidates the rows before the redraw", function()
    local st = trackerTab()
    for _, r in ipairs(ROW_BOXES) do
        local box = st.ui.boxes[K(r[1])]
        ok(box ~= nil, r[1] .. " is built")
        if box then
            ok((box.getter() and true or false) == r[3], r[1] .. " reads " .. tostring(r[3]) .. " while unset")
            local inv, ren = st.invalidate, st.render
            box.setter(not r[3])
            ok(st.cfg[r[2]] == (not r[3]), r[1] .. " stores " .. r[2])
            ok(st.invalidate == inv + 1 and st.render == ren + 1,
               r[1] .. " invalidates the rows once and redraws once: " .. (st.invalidate - inv) .. ", " .. (st.render - ren))
        end
    end
end)

case("a box that changes only what is listed redraws without invalidating", function()
    local st = trackerTab()
    for _, r in ipairs(PLAIN_BOXES) do
        local box = st.ui.boxes[K(r[1])]
        ok(box ~= nil, r[1] .. " is built")
        if box then
            local inv, ren = st.invalidate, st.render
            box.setter(false)
            ok(st.cfg[r[2]] == false, r[1] .. " stores " .. r[2])
            ok(st.render == ren + 1 and st.invalidate == inv,
               r[1] .. " redraws once and leaves the rows alone: " .. (st.render - ren) .. ", " .. (st.invalidate - inv))
        end
    end
end)

print(("test_tracker_tab: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
