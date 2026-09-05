-- luacheck: globals CreateFrame UIParent tremove
--
-- Unit tests for the scenario bonus HUD's frame, run against the SHIPPED source.
-- Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_bonus_hud.lua
--
-- UI/ScenarioBonusHUD.lua loads WHOLE here. It creates its frame and reads its media inside
-- functions rather than at load, so a plain table with the right methods on it is a complete
-- stand-in, and HUD.frame is an ordinary field this file can seed.
--
-- SCOPE: ApplySettings and _SavePosition only. The row layout in _Render wants a font string
-- and a texture pool to say anything about, and no assertion here reaches it - a green run is
-- NOT coverage of how the HUD draws its rows.
--
-- The cases that earn this file:
--
--   1. THE BACKGROUND HAS THREE BRANCHES AND THEIR ORDER IS THE BEHAVIOR. Off beats a picked
--      color, a picked color beats the lock fade, and only the third branch fades. Getting the
--      order wrong leaves a user who has picked a color watching its alpha change when they
--      lock the HUD, which reads as the color not sticking.
--   2. A COLOR TABLE MAY CARRY NO ALPHA. Options/Frame.lua always sends one, so `c.a or 1`
--      is insurance against a hand-edited or imported table rather than against anything this
--      addon writes. It keeps the call explicit instead of leaning on the client's own default
--      for a missing alpha.
--   3. THE BORDER FALLS BACK TO A CONSTANT, NOT TO NOTHING. AceDB merges the borderColor
--      default into every profile at load, so that fallback is unreachable both through the
--      options panel and through any saved profile - it stands for a state table that carries
--      no borderColor at all. It has to still be the red the HUD shipped with.
--   4. OFFSETS ARE STORED IN UIParent UNITS AND DIVIDED BACK OUT BY THE SCALE. Without that
--      the HUD walks across the screen as the scale slider moves instead of growing in place,
--      and the round trip through _SavePosition is what proves the two halves agree.
--   5. APPLYSETTINGS IS REACHED WITH NO FRAME. The four frame controls and the scale slider
--      all call it, and the HUD is off by default, so the first call of a session can land
--      before anything has ever been drawn. It must return rather than raise.

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
end

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end

local function near(a, b)
    return a and b and math.abs(a - b) < 0.0001
end

-- Production is only ever reached through a pcall - here, and at the _SavePosition sites
-- below. A raise has to fail a case, never kill the run: the summary line would never print,
-- and every battery here reads a missing summary as a mutant that SURVIVED, which sends the
-- next reader hunting a coverage hole that is not there.
local function apply(HUD, why)
    local okCall, err = pcall(HUD.ApplySettings, HUD)
    ok(okCall, (why or "ApplySettings") .. " does not raise" ..
       (okCall and "" or (" - " .. tostring(err))))
    return okCall
end

-- --------------------------------------------------------------------- the client stubs

_G.UIParent = { name = "UIParent" }
_G.tremove = table.remove
_G.CreateFrame = function() error("the HUD must not build a frame in these cases") end

local function fakeFrame()
    local f = { _scale = 1, _points = {} }
    f.SetScale = function(self, v) self._scale = v end
    f.GetScale = function(self) return self._scale end
    f.ClearAllPoints = function(self) self._points = {} end
    f.SetPoint = function(self, point, rel, relPoint, x, y)
        self._points[#self._points + 1] = { point, rel, relPoint, x, y }
    end
    -- GetPoint answers the LAST SetPoint, the way a real frame with one anchor does, so the
    -- save round trip below reads back what apply just wrote rather than a value this file
    -- handed it.
    f.GetPoint = function(self)
        local p = self._points[#self._points]
        if not p then return nil end
        return p[1], p[2], p[3], p[4], p[5]
    end
    f.SetBackdropColor = function(self, r, g, b, a) self.bg = { r, g, b, a } end
    f.SetBackdropBorderColor = function(self, r, g, b, a) self.border = { r, g, b, a } end
    return f
end

-- ----------------------------------------------------------------- load the shipped file

-- A fresh module table per case. ApplySettings reads nothing it stores, but _test and frame
-- both live on the module and a case must not inherit either from the case before it.
local function load(state)
    local tracker = { scenarioBonusHUD = state }
    local ns = {
        modules = {},
        Has = {},
        L = setmetatable({}, { __index = function(_, k) return k end }),
        Util = {},
        RegisterModule = function(self, n, tbl) self.modules[n] = tbl or {} return self.modules[n] end,
        GetModule = function(self, n) return self.modules[n] end,
    }
    ns.modules.DB = { Tracker = function() return tracker end }
    ns.modules.ScenarioBonus = {
        OnDirty = function() end,
        GetModel = function() return {} end,
        Reconcile = function() end,
    }
    local chunk = assert(loadfile(repoFile("UI/ScenarioBonusHUD.lua")))
    chunk("EQObjectiveTracker", ns)
    local HUD = ns:GetModule("ScenarioBonusHUD")
    HUD.frame = fakeFrame()
    return HUD, HUD.frame, tracker
end

-- The shipped defaults for this block, copied from Core/DB.lua rather than synthesized, so a
-- case describes what a real profile holds.
local function defaults()
    return {
        enabled = false,
        point = "CENTER", relPoint = "CENTER", x = 0, y = -120,
        scale = 1.0,
        locked = false,
        showBorder = true,
        showBackground = true,
        borderColor = { r = 0.635, g = 0.000, b = 0.039, a = 1 },
    }
end

-- ------------------------------------------------------------------------------ the cases

print("== the shipped defaults draw the frame the HUD has always drawn")
do
    local HUD, f = load(defaults())
    apply(HUD, "a default apply")

    ok(near(f.bg[1], 0) and near(f.bg[2], 0) and near(f.bg[3], 0),
       "the background is black while no color is picked")
    ok(near(f.bg[4], 0.55), "at the unlocked alpha")
    ok(near(f.border[1], 0.635) and near(f.border[2], 0) and near(f.border[3], 0.039)
       and near(f.border[4], 1), "and the border is the red the HUD shipped with")
end

print("== the lock fade applies to the plain fill and to nothing else")
do
    local st = defaults()
    st.locked = true
    local HUD, f = load(st)
    apply(HUD, "a locked apply")
    ok(near(f.bg[4], 0.40), "a locked HUD fades, so an unlocked one reads as draggable")

    -- The whole point of the elseif: a user who has picked a color owns its alpha, and
    -- locking must not move it. Without this the color looks like it did not stick.
    st.backgroundColor = { r = 0.1, g = 0.2, b = 0.3, a = 0.9 }
    local HUD2, f2 = load(st)
    apply(HUD2, "a locked apply with a picked color")
    ok(near(f2.bg[4], 0.9), "a picked color keeps its own alpha when the HUD is locked")
    ok(near(f2.bg[1], 0.1) and near(f2.bg[2], 0.2) and near(f2.bg[3], 0.3),
       "and its own color")
end

print("== a color with no alpha is opaque, not invisible")
do
    -- A table that carries no alpha at all. Nothing in this addon writes one, so this stands
    -- for an imported or hand-edited profile.
    local st = defaults()
    st.backgroundColor = { r = 0.5, g = 0.5, b = 0.5 }
    st.borderColor     = { r = 0.4, g = 0.3, b = 0.2 }
    local HUD, f = load(st)
    apply(HUD, "an alphaless apply")
    ok(near(f.bg[4], 1), "a background color with no alpha is drawn opaque")
    ok(near(f.border[4], 1), "and so is a border color with no alpha")
    -- The whole feature on the border side. Without this a build that ignored borderColor and
    -- always drew the shipped red would pass every other case in this file, because the red's
    -- own alpha is 1 as well.
    ok(near(f.border[1], 0.4) and near(f.border[2], 0.3) and near(f.border[3], 0.2),
       "a picked border color reaches the frame rather than the shipped red")
end

print("== switching a half off beats any color picked for it")
do
    local st = defaults()
    st.showBackground = false
    st.showBorder     = false
    st.backgroundColor = { r = 1, g = 1, b = 1, a = 1 }
    st.borderColor     = { r = 1, g = 1, b = 1, a = 1 }
    local HUD, f = load(st)
    apply(HUD, "a frameless apply")

    ok(near(f.bg[4], 0), "the background is fully transparent with its box unticked")
    ok(near(f.border[4], 0), "and so is the border, so unticking both removes the frame")
end

print("== only an explicit false switches a half off")
do
    -- nil is what ApplySettings's own `hudState() or {}` fallback produces, and what a state
    -- table carrying neither key holds. It has to read as ON rather than blanking a frame.
    local st = defaults()
    st.showBackground, st.showBorder = nil, nil
    local HUD, f = load(st)
    apply(HUD, "an apply with both switches unset")
    ok(near(f.bg[4], 0.55), "an unset background switch still draws the fill")
    ok(near(f.border[4], 1), "and an unset border switch still draws the border")
end

print("== a profile with no border color falls back to the shipped red")
do
    -- Unreachable through the options panel AND through any saved profile, since AceDB merges
    -- the default in at load. It stands for a state table that carries no borderColor at all.
    local st = defaults()
    st.borderColor = nil
    local HUD, f = load(st)
    apply(HUD, "an apply with no border color")
    ok(near(f.border[1], 0.635) and near(f.border[2], 0) and near(f.border[3], 0.039)
       and near(f.border[4], 1), "the fallback is the red, not black and not nothing")
end

print("== offsets are stored in UIParent units and divided back out")
do
    local st = defaults()
    st.x, st.y, st.scale = 300, -200, 2.0
    local HUD, f = load(st)
    apply(HUD, "a scaled apply")

    local _, rel, _, x, y = f:GetPoint()
    ok(rel == _G.UIParent, "anchored to UIParent, so the offsets mean screen units")
    ok(near(x, 150) and near(y, -100),
       "and the offsets are divided by the scale, or the HUD walks as the slider moves")
    ok(near(f._scale, 2.0), "the scale itself is applied")
end

print("== applying twice re-anchors rather than stacking a second point")
do
    -- The four frame controls and the scale slider each call ApplySettings, so a player
    -- picking a color reaches it once per click. A single apply cannot see a missing
    -- ClearAllPoints: the frame has one point either way, and only the second one stretches it.
    local st = defaults()
    st.x, st.y, st.scale = 300, -200, 2.0
    local HUD, f = load(st)
    apply(HUD, "the first apply")
    apply(HUD, "a second apply, as an options click makes")
    ok(#f._points == 1, "the old anchor is cleared first, or a second SetPoint stretches it")

    local _, _, _, x, y = f:GetPoint()
    ok(near(x, 150) and near(y, -100), "and the surviving anchor is still the right one")
end

print("== the save multiplies back by the scale, so the round trip holds")
do
    local st = defaults()
    st.x, st.y, st.scale = 300, -200, 2.0
    local HUD = load(st)
    apply(HUD, "a round trip apply")
    local okCall = pcall(HUD._SavePosition, HUD)
    ok(okCall, "_SavePosition does not raise")
    ok(near(st.x, 300) and near(st.y, -200),
       "what apply divided out, the save multiplies back in")
end

print("== an anchor other than the default is honored, and survives the save")
do
    -- Every other case anchors CENTER, which is ALSO the fallback in `st.point or "CENTER"`, so
    -- those assertions hold whether or not the profile is read at all. This is the only case
    -- that can tell the stored anchor from the constant, and the HUD is drag-movable, so the
    -- stored anchor is whatever the player last dropped it on.
    local st = defaults()
    st.point, st.relPoint = "TOPLEFT", "BOTTOMRIGHT"
    st.x, st.y = 40, -60
    local HUD, f = load(st)
    apply(HUD, "an apply with a dragged anchor")

    local point, _, relPoint = f:GetPoint()
    ok(point == "TOPLEFT", "the stored point is used rather than the CENTER fallback")
    ok(relPoint == "BOTTOMRIGHT", "and so is the stored relative point")

    st.point, st.relPoint = nil, nil
    ok(pcall(HUD._SavePosition, HUD), "_SavePosition does not raise")
    ok(st.point == "TOPLEFT" and st.relPoint == "BOTTOMRIGHT",
       "and the save writes the anchor back, or a dragged HUD returns to center next login")
end

print("== a stored point with no relative point anchors to itself")
do
    -- The middle term of `st.relPoint or st.point or "CENTER"`, which no other case reaches.
    local st = defaults()
    st.point, st.relPoint = "TOPRIGHT", nil
    local HUD, f = load(st)
    apply(HUD, "an apply with no relative point")
    local point, _, relPoint = f:GetPoint()
    ok(point == "TOPRIGHT" and relPoint == "TOPRIGHT",
       "the point stands in for the missing relative point rather than falling to CENTER")
end

print("== the save has a scale guard of its own, which apply's clamp hides")
do
    local st = defaults()
    st.x, st.y = 100, -50
    local HUD, f = load(st)
    apply(HUD, "an apply before the frame is rescaled from outside")

    -- apply clamps the STORED scale on the way in, so the fake never holds a bad one and the
    -- save's own guard is unreachable through it. A frame can still be rescaled by something
    -- that did not create it.
    f._scale = 0
    ok(pcall(HUD._SavePosition, HUD), "_SavePosition does not raise on a zero-scaled frame")
    ok(near(st.x, 100) and near(st.y, -50),
       "and a zero scale is treated as 1 rather than collapsing the saved position to 0,0")
end

print("== a broken or missing scale falls back to 1, it does not divide by zero")
do
    for _, bad in ipairs({ 0, -1 }) do
        local st = defaults()
        st.scale, st.x, st.y = bad, 120, -60
        local HUD, f = load(st)
        apply(HUD, "an apply at scale " .. bad)
        local _, _, _, x, y = f:GetPoint()
        ok(near(x, 120) and near(y, -60),
           "scale " .. bad .. " is treated as 1 rather than dividing the offsets by it")
        ok(near(f._scale, 1.0), "and the frame is set to 1")
    end
end

print("== an empty block still draws, at the HUD's own default position")
do
    -- The `or {}` state ApplySettings falls back to when hudState() answers nil. The default y
    -- is the HUD's own, not zero, or a first-time user finds it centered on their character.
    local HUD, f = load({})
    apply(HUD, "an apply with an empty state block")
    local point, _, relPoint, x, y = f:GetPoint()
    ok(point == "CENTER" and relPoint == "CENTER", "it centers")
    ok(near(x, 0) and near(y, -120), "at the HUD's own default offset")
    ok(near(f.bg[4], 0.55) and near(f.border[4], 1), "with the frame drawn")
end

print("== ApplySettings with no frame is a no-op, not a raise")
do
    -- The four frame controls and the scale slider all call it, and the HUD ships OFF, so the
    -- first call of a session can land before anything has ever been drawn.
    local HUD = load(defaults())
    HUD.frame = nil
    apply(HUD, "an apply before the frame exists")

    local okCall = pcall(HUD._SavePosition, HUD)
    ok(okCall, "_SavePosition with no frame does not raise either")
end

print("== a frame that has never been anchored saves nothing rather than raising")
do
    local st = defaults()
    local HUD, f = load(st)
    f._points = {}
    local okCall = pcall(HUD._SavePosition, HUD)
    ok(okCall, "_SavePosition on an unanchored frame does not raise")
    ok(st.x == 0 and st.y == -120, "and it leaves the stored position alone")
end

print(("test_bonus_hud: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
