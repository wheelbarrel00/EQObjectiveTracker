-- Unit tests for Options:ShowColorPicker, run against the SHIPPED source.
-- Run from the repo root with the game's own Lua version:
--
--     "C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe" docs/test_color_picker.lua
--
-- WHAT EARNS THIS FILE. A user on Classic Era changed the header bar color and the bars
-- vanished, permanently - reload, relog, picking a new color, none of it brought them back.
-- The stored value read { 0.949, 0.541, 0.722, a = 0 }: the color they picked, with an alpha
-- of exactly zero. UI/Sections.lua then does c.a or BAR_COLOR[4], and 0 is TRUTHY in Lua, so
-- the zero is kept and every later pick keeps it too.
--
-- The alpha comes from the picker's opacity control, and BOTH flavors load that control from
-- OnShow - transcribed below from Blizzard's own source:
--
--   Classic   ColorPickerFrameMixin:GetColorAlpha() -> OpacitySliderFrame:GetValue()
--             <OnShow> if self.hasOpacity then OpacitySliderFrame:Show()
--                           OpacitySliderFrame:SetValue(self.opacity) ...
--             SetupColorPickerAndShow(): ... self:SetColorRGB(r,g,b)
--                                            self:Show()
--
-- Show on a frame that is ALREADY SHOWN fires nothing, so re-seeding a picker that is still
-- open leaves the PREVIOUS swatch's alpha sitting in the control - and the run commits that
-- instead of its own. The slider's XML carries defaultValue="1" and nothing but the picker's
-- own OnShow calls SetValue on it in Blizzard's code, so an unloaded one holds whatever the
-- last picker left.
--
-- Retail reaches the same code and almost never trips it: its picker registers
-- GLOBAL_MOUSE_DOWN and cancels itself when you click outside, so clicking a second swatch
-- closes the first picker and the next Show is real. The Classic picker has no such handler.
-- That is the whole of the flavor asymmetry - the DEFECT is shared, the REACHABILITY is not.
--
-- AND THE SECOND, WHICH IS WHAT THE REPORTER ACTUALLY HIT. ElvUI's Color Picker Plus reads
-- that same slider as TRANSPARENCY - the pre-10.0 ColorPickerFrame.opacity convention -
-- while Blizzard's Classic GetColorAlpha reads it as ALPHA. Measured on 1.15.9:
--
--   slider 0.84999996  ->  ColorPPBoxA reads 15
--   slider 0           ->  ColorPPBoxA reads 100, GetColorAlpha reads 0
--
-- So its Class button writes 0 meaning OPAQUE and this addon stored it as fully
-- transparent. Both UIs then agreed the color was fine and the bar was invisible.
--
-- OUT OF SCOPE BY CONSTRUCTION: the slice is ShowColorPicker alone. CreateColorPicker builds
-- frames, so its swatch, its paint() and its prev-snapshot are reached by no assertion here.
-- The two file-locals are stubbed too, so the OnHide hook that clears activeColorApply,
-- activeReopen and activeCancel - which the re-seed Hide now fires - is uncovered as well.

local function repoFile(rel)
    local f = io.open(rel, "r")
    if f then f:close() return rel end
    return "../" .. rel
end

local function readFile(rel)
    local fh = assert(io.open(repoFile(rel), "r"))
    local s = fh:read("*a")
    fh:close()
    return s
end

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. msg) end
end

-- Calls into sliced production go through this, so a mutant that RAISES fails a case rather
-- than aborting the file: a run that prints no summary line reads as a survivor, not a catch.
local function guard(fn, ...)
    local okCall, err = pcall(fn, ...)
    if not okCall then
        fail = fail + 1
        print("FAIL: raised - " .. tostring(err))
    end
    return okCall
end

-- The picker's own buttons re-enter apply and cancel, so they need the same protection the
-- entry point gets. Driving one bare is what lets a single mutant abort the run.
local function drive(obj, method, ...)
    return guard(obj[method], obj, ...)
end

-- ------------------------------------------------- Blizzard's Classic picker, transcribed
--
-- Read off Blizzard_FrameXML/Classic/ColorPickerFrame.lua and .xml, which Era 1.15.9 loads
-- through Blizzard_FrameXML_Vanilla.toc and TBC 2.5.6 through the _TBC one. Nothing here is
-- invented: the slider bounds, the OnShow body, the OnColorSelect body and the Okay button's
-- call order are all Blizzard's.

local function newSlider(minV, maxV)
    local s = { min = minV, max = maxV, _v = minV, _shown = false, _writes = 0 }
    function s:SetValue(v)
        -- Counted at the top rather than beside the assignment: the point of the count is how
        -- often the control is WRITTEN, including a write that turns out to change nothing.
        self._writes = self._writes + 1
        if v == nil then v = self.min end
        if v < self.min then v = self.min elseif v > self.max then v = self.max end
        -- A slider fires OnValueChanged only when the value actually MOVES. Modeled
        -- because it is what stops OnShow correcting an already-matching stale value.
        if v == self._v then return end
        self._v = v
        if self.OnValueChanged then self:OnValueChanged() end
    end
    function s:GetValue() return self._v end
    function s:Show() self._shown = true end
    function s:Hide() self._shown = false end
    function s:IsShown() return self._shown end
    return s
end

local picker

-- startAlpha is whatever the opacity slider is carrying before this picker loads it. Driven
-- rather than assumed: the bug is that a STALE value is read, and the zero the user hit came
-- from ElvUI's Class button rather than from any slider floor.
local function newClassicPicker(startAlpha)
    local slider = newSlider(0, 1)
    slider._v = startAlpha or 0

    local cp = { _shown = false, _r = 1, _g = 1, _b = 1 }

    slider.OnValueChanged = function()
        if cp.opacityFunc then cp.opacityFunc() end
    end

    function cp:IsShown() return self._shown end

    function cp:Show()
        if self._shown then return end          -- Show on a shown frame fires no OnShow
        self._shown = true
        if self.hasOpacity then
            slider:Show()
            slider:SetValue(self.opacity)
        else
            slider:Hide()
        end
    end

    function cp:Hide() self._shown = false end

    function cp:GetColorRGB() return self._r, self._g, self._b end

    -- Blizzard's <OnColorSelect> calls swatchFunc and nothing else on Classic.
    function cp:SetColorRGB(r, g, b)
        self._r, self._g, self._b = r, g, b
        if self.swatchFunc then self.swatchFunc() end
    end

    -- Deliberately NOT gated on hasOpacity, matching Blizzard: it reads the slider whatever
    -- state the frame is in.
    function cp:GetColorAlpha() return slider:GetValue() end

    function cp:SetupColorPickerAndShow(info)
        self.swatchFunc  = info.swatchFunc
        self.hasOpacity  = info.hasOpacity
        self.opacityFunc = info.opacityFunc
        self.opacity     = info.opacity
        self.previousValues = { r = info.r, g = info.g, b = info.b, a = info.opacity }
        self.cancelFunc  = info.cancelFunc
        self:SetColorRGB(info.r, info.g, info.b)
        self:Show()
    end

    -- The Okay button: HideUIPanel first, then swatchFunc, then opacityFunc.
    function cp:ClickOkay()
        self:Hide()
        self.swatchFunc()
        if self.opacityFunc then self.opacityFunc() end
    end

    function cp:ClickCancel()
        self:Hide()
        if self.cancelFunc then self.cancelFunc(self.previousValues) end
    end

    -- The user dragging the vertical opacity slider. Its $parentText carries no text on
    -- Classic, so the control is unlabeled beyond its own - and + marks.
    function cp:DragOpacity(v) slider:SetValue(v) end

    cp.slider = slider
    return cp
end

-- --------------------------------------------------------- Options/Frame.lua slice
--
-- Frame.lua cannot be loaded whole - it takes the addon namespace off varargs and registers a
-- module at file scope - so ShowColorPicker is sliced by TEXT ANCHOR rather than line number,
-- which drifts. If an anchor below stops matching, fix the anchor here rather than deleting
-- the test.

local src = readFile("Options/Frame.lua")

-- The slice starts at the class button rather than at ShowColorPicker: the button seeds a
-- reopen from the control's own value, so it has to be read in the same space the picker
-- writes, and it shares activeReopen with the picker as a file-local.
local FROM_ANCHOR = "local function ensureClassColorButton()"
local TO_ANCHOR   = "function Options:CreateColorPicker(content, label, getter, setter, tooltip, hasAlpha, onClear)"
local from = src:find(FROM_ANCHOR, 1, true)
local to   = src:find(TO_ANCHOR, 1, true)
assert(from, "anchor not found in Options/Frame.lua: " .. FROM_ANCHOR)
assert(to,   "anchor not found in Options/Frame.lua: " .. TO_ANCHOR)
assert(to > from, "anchors are out of order in Options/Frame.lua")

local slice = "local Options = {}\n" .. src:sub(from, to - 1) .. "\nreturn Options\n"

-- Read out of the shipped source rather than written here: a probe value restated in the test
-- would keep agreeing with itself after the shipped one moved.
local PROBE_ALPHA = tonumber(src:match("local PROBE_ALPHA%s*=%s*([%d%.]+)"))
assert(PROBE_ALPHA, "PROBE_ALPHA did not match in Options/Frame.lua")
ok(PROBE_ALPHA ~= 0.5, "a probe at 0.5 could not tell the two conventions apart")

-- The class button the slice builds, captured so a case can press it.
local classBtn

local env = setmetatable({
    -- These are file-locals above the slice in production, so they resolve as globals here.
    ensurePickerHook = function() end,
    PROBE_ALPHA      = PROBE_ALPHA,
    elvUILoaded      = function() return false end,
    ns               = { GetModule = function()
        return { GetPlayerClassColor = function() return 0.67, 0.83, 0.45 end }
    end },
    flatButton = function(_, _, onClick)
        classBtn = { _shown = false, Click = onClick }
        function classBtn:SetSize() end
        function classBtn:SetPoint() end
        function classBtn:Show() self._shown = true end
        function classBtn:Hide() self._shown = false end
        return classBtn
    end,
}, { __index = _G })

local Options = (function()
    local chunk = assert(loadstring(slice, "@Options/Frame.lua slice"))
    setfenv(chunk, env)
    return chunk()
end)()
assert(type(Options.ShowColorPicker) == "function", "the slice defined no ShowColorPicker")

-- Swaps the frames without touching session state, for a case that models one client opening
-- two pickers rather than two clients.
local function installFrames(cp, box)
    picker = cp
    env.ColorPickerFrame   = cp
    env.OpacitySliderFrame = cp and cp.slider or nil
    -- The slice reads _G.ColorPPBoxA, so _G has to be the sandbox's own table rather than the
    -- real one. Absent box means a client with no Color Picker Plus.
    env._G = { ColorPPBoxA = box }
end

-- The slice reads these as globals off its environment.
local function install(cp, box)
    installFrames(cp, box)
    -- Cleared per case because production settles these once per SESSION, and every case here
    -- is a fresh client. Leaving them set lets one case answer for the next one's picker.
    env.pickerAlphaInverted = nil
    env.classColorButton    = nil
    classBtn                = nil
end

-- ElvUI's Color Picker Plus, read off Game/Classic/Blizzard/ColorPicker.lua rather than
-- inferred. Three things about it are load-bearing and an earlier model here had all three
-- wrong. Its alpha box is AlphaValue(num) = floor(((1 - num) * 100) + .05), so it truncates
-- rather than rounds. It takes the slider with SetScript rather than a hook, so Blizzard's
-- own OnValueChanged no longer runs. And it updates its box BEFORE calling opacityFunc,
-- which the real addon defers by 0.15s and this calls inline.
local function attachColorPP(cp, invert)
    local box = { _text = "" }
    function box:GetText() return self._text end
    local function alphaValue(v)
        if invert then v = 1 - v end
        return math.floor((v * 100) + 0.05)
    end
    -- It memoizes the last percent and the last RGB it saw, in file-locals its OnShow hook
    -- never resets, and returns early when a write does not move them. Those early returns are
    -- why merely seeding a picker commits nothing until a write crosses a percent boundary.
    local last = { r = 0, g = 0, b = 0, a = 0 }
    cp.slider.OnValueChanged = function()
        local a = alphaValue(cp.slider:GetValue())
        if a == last.a then return end
        last.a = a
        box._text = tostring(a)
        if cp.opacityFunc then cp.opacityFunc() end
    end
    -- It replaces OnColorSelect as well, and the seed lands while the frame is still hidden,
    -- where its own handler reaches a DelayCall with nothing armed rather than swatchFunc.
    function cp:SetColorRGB(r, g, b)
        self._r, self._g, self._b = r, g, b
        if r == last.r and g == last.g and b == last.b then return end
        last.r, last.g, last.b = r, g, b
        if self:IsShown() and self.swatchFunc then self.swatchFunc() end
    end
    -- Its OnShow hook re-renders the box off the live slider and leaves the memo alone.
    local baseShow = cp.Show
    function cp:Show()
        local was = self._shown
        baseShow(self)
        if not was then box._text = tostring(alphaValue(cp.slider:GetValue())) end
    end
    -- Its Class button sets the COLOR first and the slider second, and writes 0 for a fully
    -- opaque color. The order is the reported bug's own: swatchFunc fires while the slider
    -- still holds the previous alpha, and only the second commit carries the class color's.
    function cp:ClickClass(r, g, b)
        cp:SetColorRGB(r, g, b)
        if cp.hasOpacity then cp.slider:SetValue(invert and 0 or 1) end
    end
    return box
end

-- A stand-in for one swatch on the Appearance tab: it holds a stored color and commits
-- whatever the picker hands back, exactly as CreateColorPicker's commit does.
local function swatch(stored, hasAlpha)
    local s = { value = stored }
    function s:Open()
        local c = self.value or {}
        local prev = self.value and { r = c.r, g = c.g, b = c.b, a = c.a } or nil
        guard(Options.ShowColorPicker, Options, c.r or 1, c.g or 1, c.b or 1, c.a or 1, hasAlpha,
            function(nr, ng, nb, na) self.value = { r = nr, g = ng, b = nb, a = na } end,
            function() self.value = prev end)
    end
    return s
end

local function A(s) return s.value and s.value.a end

-- 1 - 0.85 is not exactly 0.15 in binary floating point, so the round trip back through
-- the inversion lands a hair off. Exact equality is kept everywhere it can be.
local function near(x, y) return type(x) == "number" and math.abs(x - y) < 0.005 end

-- ------------------------------------------------------------------------------- cases

print("== a picker opened on a CLOSED frame commits its own alpha")
do
    install(newClassicPicker(0))
    local bar = swatch({ r = 0.80, g = 0.60, b = 0.20, a = 0.85 }, true)
    bar:Open()
    ok(picker:IsShown(), "the picker is up")
    ok(picker.slider:IsShown(), "an alpha picker shows its opacity slider")
    ok(picker.slider:GetValue() == 0.85, "the slider carries the color's own alpha")
    picker:SetColorRGB(0.94, 0.54, 0.72)          -- the user picks a color off the wheel
    drive(picker, "ClickOkay")
    ok(A(bar) == 0.85, "the alpha survives the pick")
    ok(bar.value.r == 0.94, "and the new color lands")
end

print("== the reported bug: a second swatch opened while the picker is still up")
do
    -- Nothing here is contrived. The Classic picker does not close when you click outside
    -- it, so opening one swatch and then another without pressing Okay is ordinary use.
    install(newClassicPicker(0))
    local header = swatch({ r = 0.93, g = 0.32, b = 0.10 }, false)   -- Section Header Color
    header:Open()
    ok(not picker.slider:IsShown(), "a no-alpha picker hides the opacity slider")
    ok(picker.slider:GetValue() == 0, "and never loads it, so it keeps what the last one left")

    local bar = swatch({ r = 0.80, g = 0.60, b = 0.20, a = 0.85 }, true)
    bar:Open()                                     -- re-seeded onto the OPEN picker
    ok(picker.slider:IsShown(), "the opacity slider must be shown for an alpha picker")
    ok(picker.slider:GetValue() == 0.85, "and must carry THIS color's alpha, not the last one's")

    picker:SetColorRGB(0.94, 0.54, 0.72)
    drive(picker, "ClickOkay")
    ok(A(bar) == 0.85, "the header bar keeps its alpha instead of committing 0")
    ok(A(bar) ~= 0, "an alpha of 0 makes the bar invisible while its checkbox still reads on")
end

print("== a re-seed must not inherit the previous swatch's alpha either")
do
    install(newClassicPicker(0))
    local first = swatch({ r = 0.1, g = 0.2, b = 0.3, a = 0.25 }, true)
    first:Open()
    ok(picker.slider:GetValue() == 0.25, "the first picker loads its own alpha")

    local second = swatch({ r = 0.8, g = 0.6, b = 0.2, a = 0.85 }, true)
    second:Open()
    picker:SetColorRGB(0.5, 0.5, 0.5)
    drive(picker, "ClickOkay")
    ok(A(second) == 0.85, "the second swatch commits 0.85, not the first swatch's 0.25")
    ok(A(first) == 0.25, "and the first swatch is left alone")
end

print("== the opacity control still wins once the user moves it")
do
    -- The fix must LOAD the control, never pin the value: a deliberate alpha is a real
    -- choice and has to survive.
    install(newClassicPicker(0))
    local bar = swatch({ r = 0.8, g = 0.6, b = 0.2, a = 0.85 }, true)
    bar:Open()
    drive(picker, "DragOpacity", 0.40)
    ok(A(bar) == 0.40, "dragging the opacity slider commits that alpha")
    picker:SetColorRGB(0.94, 0.54, 0.72)
    drive(picker, "ClickOkay")
    ok(A(bar) == 0.40, "and it survives a later color pick")

    -- Zero is reachable on purpose. That is not the bug - the bug was reaching it without
    -- touching the control.
    drive(picker, "DragOpacity", 0)
    ok(A(bar) == 0, "a deliberate 0 is still allowed")
end

print("== a stale slider cannot leak in through a no-alpha picker")
do
    install(newClassicPicker(0))
    local bar = swatch({ r = 0.8, g = 0.6, b = 0.2, a = 0.85 }, true)
    bar:Open()
    drive(picker, "ClickOkay")

    local header = swatch({ r = 0.93, g = 0.32, b = 0.10 }, false)
    header:Open()
    picker:SetColorRGB(0.1, 0.2, 0.3)
    drive(picker, "ClickOkay")
    ok(A(header) == 1, "a no-alpha picker commits 1 whatever the slider holds")
end

print("== Cancel restores the value the picker was opened on")
do
    install(newClassicPicker(0))
    local bar = swatch({ r = 0.8, g = 0.6, b = 0.2, a = 0.85 }, true)
    bar:Open()
    picker:SetColorRGB(0.94, 0.54, 0.72)
    drive(picker, "ClickCancel")
    ok(bar.value.r == 0.8 and A(bar) == 0.85, "Cancel puts the original color back")
end

print("== an unset color still opens, and commits an opaque one")
do
    install(newClassicPicker(0))
    local unset = swatch(nil, true)
    unset:Open()
    ok(picker.slider:GetValue() == 1, "an unset color seeds a fully opaque picker")
    picker:SetColorRGB(0.2, 0.4, 0.6)
    drive(picker, "ClickOkay")
    ok(A(unset) == 1, "and commits alpha 1 rather than 0")
end

print("== ElvUI's picker: the alpha it SHOWS is the alpha that gets stored")
do
    local cp = newClassicPicker(0)
    local box = attachColorPP(cp, true)
    install(cp, box)

    local bar = swatch({ r = 0.80, g = 0.60, b = 0.20, a = 0.85 }, true)
    bar:Open()
    -- Seeding matters as much as reading. Left alone, the picker opens reporting 15 for an
    -- alpha of 0.85 and the user "corrects" it into something nobody chose.
    ok(box:GetText() == "85", "the picker opens reporting the alpha this addon holds")
    picker:SetColorRGB(0.94, 0.54, 0.72)
    drive(picker, "ClickOkay")
    ok(near(A(bar), 0.85), "picking a color leaves the alpha alone")
end

print("== the reported bug: ElvUI's Class button")
do
    local cp = newClassicPicker(0)
    local box = attachColorPP(cp, true)
    install(cp, box)

    local bar = swatch({ r = 0.80, g = 0.60, b = 0.20, a = 0.85 }, true)
    bar:Open()
    drive(picker, "ClickClass", 0.949, 0.541, 0.722)
    drive(picker, "ClickOkay")
    ok(bar.value.r == 0.949, "the class color lands")
    ok(near(A(bar), 1), "and it is fully OPAQUE, which is what that button means")
    ok(A(bar) ~= 0, "rather than the invisible bar the reporter got")
end

print("== a deliberate alpha still lands through ElvUI's slider")
do
    local cp = newClassicPicker(0)
    local box = attachColorPP(cp, true)
    install(cp, box)
    local bar = swatch({ r = 0.8, g = 0.6, b = 0.2, a = 0.85 }, true)
    bar:Open()
    drive(picker, "DragOpacity", 0.75)
    ok(box:GetText() == "25", "ElvUI shows 25 for a slider at 0.75")
    ok(near(A(bar), 0.25), "and the addon stores the alpha the user is looking at")
end

print("== a picker that AGREES with Blizzard is left alone")
do
    -- The day ElvUI maps the slider as alpha, the calibration must invert nothing. This is
    -- what stops the fix becoming the next version of the bug.
    local cp = newClassicPicker(0)
    local box = attachColorPP(cp, false)
    install(cp, box)
    local bar = swatch({ r = 0.8, g = 0.6, b = 0.2, a = 0.85 }, true)
    bar:Open()
    ok(near(picker.slider:GetValue(), 0.85), "the slider is not flipped")
    ok(box:GetText() == "85", "and the box already reads the right alpha")
    picker:SetColorRGB(0.5, 0.5, 0.5)
    drive(picker, "ClickOkay")
    ok(near(A(bar), 0.85), "the alpha is read straight")
end

print("== an alpha of exactly 0.5 still calibrates, through the probe")
do
    -- 1 - na and na are the SAME NUMBER at 0.5, so the opening reading cannot tell the two
    -- conventions apart. Without the probe the flag stayed false and the reported bug came
    -- back for anyone who had ever picked 50% opacity.
    local cp = newClassicPicker(0)
    local box = attachColorPP(cp, true)
    install(cp, box)
    local bar = swatch({ r = 0.8, g = 0.6, b = 0.2, a = 0.5 }, true)
    bar:Open()
    ok(env.pickerAlphaInverted == true, "the probe settles the convention at the ambiguous alpha")
    ok(near(picker.slider:GetValue(), 0.5), "and the control still ends up where the color asked")
    drive(picker, "DragOpacity", 0.75)
    ok(near(A(bar), 0.25), "so a later drag stores the alpha ElvUI is showing, not its complement")
end

print("== the convention is settled once per session, not re-derived per swatch")
do
    local cp = newClassicPicker(0)
    local box = attachColorPP(cp, true)
    install(cp, box)
    local first = swatch({ r = 0.1, g = 0.2, b = 0.3, a = 0.85 }, true)
    first:Open()
    ok(env.pickerAlphaInverted == true, "the first open that can answer settles it")

    local before = cp.slider._writes
    local second = swatch({ r = 0.4, g = 0.5, b = 0.6, a = 0.25 }, true)
    second:Open()
    ok(cp.slider._writes == before + 1,
       "a later open seeds the control once and needs no corrective write")
    ok(near(picker.slider:GetValue(), 0.75),
       "seeded straight to this swatch's own alpha, in the control's space")
end

print("== a box present but unreadable leaves the question open rather than answering it")
do
    -- ColorPPBoxA is an EditBox the user can clear. Latching false on an unreadable one would
    -- answer the question WRONGLY and, being a session flag, never ask again.
    local cp = newClassicPicker(0)
    install(cp, { GetText = function() return "" end })
    swatch({ r = 0.8, g = 0.6, b = 0.2, a = 0.85 }, true):Open()
    ok(env.pickerAlphaInverted == nil, "an unreadable box settles nothing")

    -- Same session, so the frames are swapped without clearing what it has learned.
    local good = newClassicPicker(0)
    installFrames(good, attachColorPP(good, true))
    local bar = swatch({ r = 0.8, g = 0.6, b = 0.2, a = 0.85 }, true)
    bar:Open()
    ok(env.pickerAlphaInverted == true, "and a later readable one still settles it")
    drive(picker, "DragOpacity", 0.75)
    ok(near(A(bar), 0.25), "with the alpha read the right way round from then on")
end

print("== EQOT's own Class button stands down beside another picker addon's")
do
    local cp = newClassicPicker(0)
    install(cp, attachColorPP(cp, true))
    swatch({ r = 0.8, g = 0.6, b = 0.2, a = 0.85 }, true):Open()
    ok(classBtn == nil, "no second Class button is built when a ColorPPBoxA is present")

    local plain = newClassicPicker(0)
    install(plain, nil)
    local bar = swatch({ r = 0.8, g = 0.6, b = 0.2, a = 0.85 }, true)
    bar:Open()
    ok(classBtn ~= nil, "and it IS built on a client with no such box")
    ok(classBtn and classBtn._shown, "and shown with the picker")

    -- It reopens the picker seeded from the control, so it has to hand back an addon-space
    -- alpha rather than whatever the control happens to be holding.
    if classBtn then guard(classBtn.Click) end
    ok(near(A(bar), 0.85), "pressing it keeps the alpha")
    ok(bar.value and bar.value.r ~= 0.8, "and changes the color")
end

-- --------------------------------------------------------------- the consumer, UI/Sections
--
-- Everything above drives the picker, so it all passes with UI/Sections.lua dropping the alpha
-- on the way to the screen. ApplyBar is SLICED rather than grepped for the reason a grep
-- cannot cover it at all: no text search tells CreateColor(r, g, b, a) from (r, g, b, 1).

local secSrc = readFile("UI/Sections.lua")

local function newColor(r, g, b, a)
    local c = { r = r, g = g, b = b, a = a }
    function c:SetRGBA(nr, ng, nb, na) self.r, self.g, self.b, self.a = nr, ng, nb, na end
    return c
end

local Sections = (function()
    -- The BAR_ constants are sliced too, never restated: an expected value written out here
    -- would move with the shipped one and the assertion could no longer fail.
    local consts = secSrc:match("(local BAR_COLOR.-\nlocal BAR_DARKEN[^\n]*\n)")
    assert(consts, "the BAR_ constants did not match in UI/Sections.lua")
    local FROM = "function Sections:ApplyBar(header, cfg)"
    local TO   = "function Sections:ApplyStyle(header)"
    local a, b = secSrc:find(FROM, 1, true), secSrc:find(TO, 1, true)
    assert(a, "anchor not found in UI/Sections.lua: " .. FROM)
    assert(b and b > a, "anchor not found or out of order in UI/Sections.lua: " .. TO)
    local chunk = assert(loadstring(
        "local Sections = {}\n" .. consts .. secSrc:sub(a, b - 1) .. "\nreturn Sections\n",
        "@UI/Sections.lua slice"))
    setfenv(chunk, setmetatable({ CreateColor = newColor }, { __index = _G }))
    return chunk()
end)()
assert(type(Sections.ApplyBar) == "function", "the slice defined no ApplyBar")

local function newHeader()
    local bar = { _shown = false }
    function bar:SetHeight(h) self._h = h end
    function bar:Show() self._shown = true end
    function bar:Hide() self._shown = false end
    function bar:SetGradient(o, c1, c2) self._orient, self._c1, self._c2 = o, c1, c2 end
    return { bar = bar }
end

print("== the stored alpha reaches the bar the user is looking at")
do
    local h = newHeader()
    guard(Sections.ApplyBar, Sections, h,
          { headerBar = true, headerBarColor = { r = 0.94, g = 0.54, b = 0.72, a = 0.85 } })
    ok(h.bar._c1 and h.bar._c1.a == 0.85, "the picked alpha is what the bar draws with")
    ok(h.bar._c2 and h.bar._c2.a == 0.85, "on both ends of the gradient")
    ok(h.bar._c1 and h.bar._c1.r == 0.94, "and the color goes with it")

    -- The reported bug at the consumer end. 0 is TRUTHY, so c.a or BAR_COLOR[4] KEEPS it -
    -- the bar holds a real color with nothing left of it and stays shown, which is the whole
    -- reason nothing on screen said why.
    local z = newHeader()
    guard(Sections.ApplyBar, Sections, z,
          { headerBar = true, headerBarColor = { r = 0.94, g = 0.54, b = 0.72, a = 0 } })
    ok(z.bar._c1 and z.bar._c1.a == 0, "a stored 0 is kept rather than falling back")
    ok(z.bar._shown, "and the bar is still shown while drawing nothing")

    local unset = newHeader()
    guard(Sections.ApplyBar, Sections, unset, { headerBar = true })
    ok(unset.bar._c1 and unset.bar._c1.a ~= 0, "an unset color takes the shipped default")
end

print("== merely opening an unset clearable color must not commit one")
do
    -- Two alpha pickers ship unset and carry a Clear button, so a commit nobody asked for both
    -- invents a color and offers to clear it. The first open of a session is the one that has
    -- to correct its own seed, and that write is the one ElvUI turns into a deferred commit.
    local cp = newClassicPicker(0)
    local box = attachColorPP(cp, true)
    install(cp, box)

    local commits, stored = 0, nil
    guard(Options.ShowColorPicker, Options, 1, 1, 1, 1, true,
        function(nr, ng, nb, na)
            commits = commits + 1
            stored = { r = nr, g = ng, b = nb, a = na }
        end,
        function() stored = nil end)

    ok(env.pickerAlphaInverted == true, "the first open still settles the convention")
    ok(commits == 0, "and merely opening it commits nothing")
    ok(stored == nil, "so an unset clearable color is still unset")
    ok(near(picker.slider:GetValue(), 0), "while the control ends up showing a fully opaque alpha")
end

print("== a probe that answers neither convention leaves the question open")
do
    -- A box that does not track the control can settle nothing. Latching false on it is the
    -- wrong answer rather than the absent one the session flag exists to hold, and only a
    -- reading taken where the two conventions differ can tell those two apart.
    local cp = newClassicPicker(0.5)
    local box = { _text = "50" }
    function box:GetText() return self._text end
    install(cp, box)

    local stuck = swatch({ r = 0.1, g = 0.2, b = 0.3, a = 0.5 }, true)
    stuck:Open()
    ok(env.pickerAlphaInverted == nil, "a box that answers neither convention settles nothing")
end

-- ------------------------------------------------------------------------------- seams

print("== seams")
do
    -- Whole-line, trailing AND block comments are stripped: a commented-out occurrence must
    -- not satisfy a grep. Each of the three forms is proved on a known hit before it is used.
    local function codeOf(text)
        text = text:gsub("%-%-%[%[.-%]%]", " ")
        local out = {}
        for line in (text .. "\n"):gmatch("([^\n]*)\n") do
            out[#out + 1] = line:gsub("%-%-.*$", "")
        end
        return table.concat(out, "\n")
    end
    ok(codeOf("-- local x = 1\nlocal y = 2"):find("local x", 1, true) == nil,
       "codeOf refuses a whole-line comment")
    ok(codeOf("local y = 2 -- local x = 1"):find("local x", 1, true) == nil,
       "codeOf refuses a trailing comment")
    -- Spanning LINES is what makes this case discriminate: a one-line block comment is
    -- already taken by the trailing strip above, so the block strip would be dead code.
    ok(codeOf("--[[\nlocal x = 1\n]]\nlocal y = 2"):find("local x", 1, true) == nil,
       "codeOf refuses a block comment that spans lines")
    ok(codeOf("-- local x = 1\nlocal y = 2"):find("local y", 1, true) ~= nil,
       "codeOf still finds real code")

    local fr = codeOf(src)
    ok(fr:find("cp:SetupColorPickerAndShow", 1, true) ~= nil,
       "ShowColorPicker still prefers the modern entry point")
    -- The initializer sits above the slice, so no case here can reach it. Latching false at
    -- load is a wrong answer rather than an absent one, which is the whole of the tri-state.
    ok(fr:find("local pickerAlphaInverted = nil", 1, true) ~= nil,
       "the session flag is still initialized unset")
    -- Seeding is not a user gesture. A bare SetValue here commits a color nobody picked.
    ok(fr:find("setControl(controlValue(na))", 1, true) ~= nil,
       "the corrective write still goes through the commit-suppressing helper")
    ok(fr:find("cp.opacityFunc = nil", 1, true) ~= nil,
       "and that helper still silences the picker's own opacity callback")
end

print(("test_color_picker: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
