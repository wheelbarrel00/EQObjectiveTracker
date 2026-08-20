local _, ns = ...

local Options = ns:RegisterModule("Options", {})
local L       = ns.L

local W, H        = 1020, 720
local TAB_H       = 28
local TAB_PAD_X   = 18
local FRAME_PAD   = 12
local TAB_TOP     = 44

local BRAND_RED    = { 0.635, 0.000, 0.039 }
local TAB_INACTIVE = { 0.10, 0.10, 0.10, 0.85 }
local GOLD         = { 0.92, 0.72, 0.02 }

Options.tabs = {}

-- One vertical rhythm for every tab: this far under a heading that tops a column, this far
-- under an in-column heading, and this far above one. Shared rather than per tab so a fifth
-- value cannot be invented - the four tabs had four of each before.
Options.GAP = { tabHead = -16, head = -10, aboveHead = -20 }

-- Tab files load after this one and register themselves, so the tab bar is built from
-- whatever the TOC actually loaded.
function Options:RegisterTab(def)
    self.tabs[#self.tabs + 1] = def
    table.sort(self.tabs, function(a, b) return (a.order or 100) < (b.order or 100) end)
end

local function stripEscapes(s)
    if not s then return "" end
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

function Options:AttachTooltip(frame, title, body)
    if not frame or (not title and not body) then return end
    title = (title and title ~= "") and stripEscapes(title) or nil

    if frame.GetObjectType and frame:GetObjectType() == "FontString" then
        local overlay = CreateFrame("Frame", nil, frame:GetParent())
        overlay:SetAllPoints(frame)
        frame = overlay
    elseif frame.label and frame.GetObjectType and frame:GetObjectType() == "CheckButton" then
        local w = frame.label:GetStringWidth() or 0
        if w > 0 then frame:SetHitRectInsets(0, -(w + 8), 0, 0) end
    end

    local targets = { frame }
    if frame.slider then targets[#targets + 1] = frame.slider end
    if frame.button then targets[#targets + 1] = frame.button end

    for _, t in ipairs(targets) do
        if t.EnableMouse then t:EnableMouse(true) end
        t:HookScript("OnEnter", function(s)
            local tip = ns.Util.Tooltip()
            tip:SetOwner(s, "ANCHOR_RIGHT")
            -- SetText arg 5 is alpha, not wrap - wrap is 6th. Pass 1 or the title is invisible.
            if title then tip:SetText(title, GOLD[1], GOLD[2], GOLD[3], 1, true) end
            if body and body ~= "" then tip:AddLine(body, 0.82, 0.82, 0.82, true) end
            tip:Show()
        end)
        t:HookScript("OnLeave", function() ns.Util.Tooltip():Hide() end)
    end
end

-- Every helper returns an UNANCHORED frame and the tab writes its own SetPoint chain, as
-- EQ does. There is no shared layout engine: two columns, same-row satellites, deferred
-- anchoring and the two runtime re-anchors cannot be expressed by a cursor, and the one tab
-- that does want stacking keeps a cursor of its own.
function Options:CreateHeading(content, text)
    local fs = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetText(text)
    fs:SetTextColor(unpack(BRAND_RED))
    return fs
end

function Options:CreateCheckbox(content, label, getter, setter, tooltip)
    local cb = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    cb.label:SetText(label)
    -- GameFontNormal is gold. Every control label in this panel is white, so it has to be
    -- set rather than left to the template.
    cb.label:SetTextColor(1, 1, 1)
    -- Widened here rather than only in AttachTooltip, or a checkbox built without a tooltip
    -- has a label the mouse cannot click while its neighbors' labels work.
    local labelW = cb.label:GetStringWidth() or 0
    if labelW > 0 then cb:SetHitRectInsets(0, -(labelW + 8), 0, 0) end
    cb:SetChecked(getter() and true or false)
    -- No Render here. Every setter that needs one does it itself, and an unconditional
    -- render made the whole six-provider feed rebuild twice per click.
    cb:SetScript("OnClick", function(btn)
        setter(btn:GetChecked() and true or false)
    end)
    cb.Refresh = function(btn) btn:SetChecked(getter() and true or false) end
    if tooltip then self:AttachTooltip(cb, label, tooltip) end
    content._controls[#content._controls + 1] = cb
    return cb
end

-- A texture on the HIGHLIGHT layer is shown and hidden by the Button itself, so hover needs
-- no script. Without one these read as labels rather than as something clickable.
local function addHighlight(frame, alpha)
    local hl = frame:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, alpha or 0.10)
    return hl
end

local function flatButton(parent, label, onClick)
    local b = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    b:SetSize(160, 28)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.10, 0.10, 0.10, 0.9)
    addHighlight(b)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    b.text:SetTextColor(1, 1, 1)
    b:SetScript("OnMouseDown", function() b.text:SetPoint("CENTER", 1, -1) end)
    b:SetScript("OnMouseUp",   function() b.text:SetPoint("CENTER", 0, 0) end)
    -- Keeps btn:SetText() working now the Blizzard template and its FontString are gone.
    -- Without it a caller relabeling a button would fail silently.
    b.SetText = function(_, s) b.text:SetText(s) end
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

function Options:CreateButton(content, label, width, onClick, tooltip)
    local b = flatButton(content, label, onClick)
    b:SetSize(width or 160, 28)
    if tooltip then self:AttachTooltip(b, label, tooltip) end
    return b
end

-- options is a list of { value =, label = } pairs. The value is what reaches the setter,
-- so a translated label can never end up in the profile.
function Options:CreateRadioGroup(content, label, options, getter, setter, maxWidth, pad,
                                  tipTitle, tipBody)
    local container = CreateFrame("Frame", nil, content)

    local labelFS
    if label then
        labelFS = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        labelFS:SetPoint("TOPLEFT")
        labelFS:SetText(label)
        labelFS:SetTextColor(1, 1, 1)
    end

    local buttons = {}
    local function paint(active)
        for _, b in ipairs(buttons) do
            if b.value == active then
                b.bg:SetColorTexture(BRAND_RED[1], BRAND_RED[2], BRAND_RED[3], 1)
                b.txt:SetTextColor(1, 1, 1, 1)
            else
                b.bg:SetColorTexture(unpack(TAB_INACTIVE))
                b.txt:SetTextColor(1, 1, 1, 1)
            end
        end
    end

    local BTN_H, BTN_ROW_GAP, BTN_GAP = 24, 4, 4
    local btnPad     = pad or 18
    local rowAnchor  = labelFS or container
    local rowOffsetY = labelFS and -4 or 0
    local x, y, maxX = 0, 0, 0
    for _, opt in ipairs(options) do
        local btn = CreateFrame("Button", nil, container, BackdropTemplateMixin and "BackdropTemplate")
        btn:SetHeight(BTN_H)
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        addHighlight(btn)
        local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        txt:SetPoint("CENTER")
        txt:SetText(opt.label)
        local w = math.max(40, txt:GetStringWidth() + btnPad)
        btn:SetWidth(w)
        if maxWidth and x > 0 and (x + w) > maxWidth then
            x, y = 0, y + BTN_H + BTN_ROW_GAP
        end
        btn:SetPoint("TOPLEFT", rowAnchor, labelFS and "BOTTOMLEFT" or "TOPLEFT",
                     x, rowOffsetY - y)
        btn.bg, btn.txt, btn.value = bg, txt, opt.value
        btn:SetScript("OnClick", function(b)
            if setter then setter(b.value) end
            paint(b.value)
        end)
        -- A per-option tip titles itself with that option's own label. Without one the
        -- group's shared tooltip is used, which is what every existing caller passes.
        if opt.tip then
            self:AttachTooltip(btn, opt.label, opt.tip)
        elseif tipTitle or tipBody then
            self:AttachTooltip(btn, tipTitle, tipBody)
        end
        x = x + w + BTN_GAP
        if x > maxX then maxX = x end
        buttons[#buttons + 1] = btn
    end

    paint(getter and getter())
    -- Derived, not a constant. A fixed 50 declared 8px more than the contents occupy, so
    -- every gap written under a radio group rendered 8px larger than the number said.
    local h = (labelFS and ((labelFS:GetStringHeight() or 14) + 4) or 0) + BTN_H + y
    container:SetSize(maxWidth or maxX, h)
    container.Refresh = function() paint(getter and getter()) end
    content._controls[#content._controls + 1] = container
    return container
end

-- Built by hand rather than from OptionsSliderTemplate, whose name and children have
-- moved between flavors. This works everywhere and needs no template at all.
function Options:CreateSlider(content, label, minV, maxV, step, getter, setter, tooltip)
    local holder = CreateFrame("Frame", nil, content)
    holder:SetSize(280, 44)

    local text = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOPLEFT", 0, 0)
    text:SetText(label)
    text:SetTextColor(1, 1, 1)

    local value = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    value:SetPoint("TOPRIGHT", 0, 0)
    value:SetTextColor(1, 1, 1)

    -- Decimals follow the step, so a 0.05 step reads 1.05 and a step of 1 reads 16.
    local function chooseFormat(s)
        if not s or s >= 1 then return "%d" end
        return "%." .. math.max(1, math.ceil(-math.log10(s))) .. "f"
    end
    local valueFmt = chooseFormat(step)
    local function formatValue(v) return valueFmt:format(v) end

    local slider = CreateFrame("Slider", nil, holder)
    slider:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -8)
    slider:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, -22)
    slider:SetHeight(16)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minV, maxV)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", 0, 0)
    track:SetPoint("RIGHT", 0, 0)
    track:SetHeight(4)
    track:SetColorTexture(0.25, 0.25, 0.25, 0.9)

    -- Refresh runs on every tab view. Without this guard SetValue would clamp a saved
    -- value that sits outside the range and dispatch the clamped result straight back
    -- to setter, rewriting a profile the user never touched.
    local suppress = false

    slider:SetValue(getter() or minV)
    value:SetText(formatValue(slider:GetValue()))
    slider:SetScript("OnValueChanged", function(_, v)
        local stepped = step and (math.floor((v - minV) / step + 0.5) * step + minV) or v
        value:SetText(formatValue(stepped))
        if not suppress then setter(stepped) end
    end)

    holder.slider = slider
    holder.Refresh = function()
        suppress = true
        slider:SetValue(getter() or minV)
        suppress = false
        value:SetText(formatValue(slider:GetValue()))
    end

    if tooltip then self:AttachTooltip(holder, label, tooltip) end
    content._controls[#content._controls + 1] = holder
    return holder, slider
end

-- Escape-to-close WITHOUT UISpecialFrames, and it must stay that way. Blizzard's panel
-- manager walks that list by NAME and does _G[name], so an addon frame in it taints
-- UIParentPanelManager on every single Escape press. That taint reaches the panel manager's own
-- state and from there the panels it owns, the world map among them. The taint log named
-- EQOTOptionsFrame at UIParentPanelManager.lua:1044, which is what this closes. It did NOT cause
-- the 2026-07-30 map pin blocked action - that reproduced with this already fixed - so do not
-- read it as the cause of anything else. The rule stands on the taint vector alone.
-- SetPropagateKeyboardInput is itself protected in combat, so the handler stands down there
-- and Escape just falls through to the default UI.
local function closeOnEscape(frame)
    frame:EnableKeyboard(false)
    frame:HookScript("OnShow", function(f)
        if InCombatLockdown() then return end
        f:EnableKeyboard(true)
        f:SetPropagateKeyboardInput(true)
    end)
    frame:HookScript("OnHide", function(f) f:EnableKeyboard(false) end)
    frame:SetScript("OnKeyDown", function(f, key)
        if InCombatLockdown() then return end
        if key == "ESCAPE" then
            f:SetPropagateKeyboardInput(false)
            f:Hide()
        else
            f:SetPropagateKeyboardInput(true)
        end
    end)
end

-- Hand-rolled rather than UIDropDownMenu: that was deprecated in favor of MenuUtil on
-- current retail but is still the only option on Classic, and this addon loads on both.
local DD_ROW      = 22
local DD_MAX_ROWS = 10

local function dropdownPopup()
    if Options._ddPopup then return Options._ddPopup end
    local p = CreateFrame("Frame", "EQOTDropdownPopup", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:SetSize(240, 300)
    p:Hide()
    -- A backdrop, not a fill plus a larger rect over it. EQ draws the border texture at
    -- BORDER above a BACKGROUND fill, so the border covers the fill and the whole popup
    -- renders solid gray - the same layering mistake its drag ghost had.
    if p.SetBackdrop then
        p:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        p:SetBackdropColor(0.04, 0.04, 0.04, 0.98)
        p:SetBackdropBorderColor(0.30, 0.30, 0.30, 1)
    end
    local sf = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 4, -4)
    sf:SetPoint("BOTTOMRIGHT", -24, 4)
    local c = CreateFrame("Frame", nil, sf)
    c:SetSize(1, 1)
    sf:SetScrollChild(c)
    p.scroll, p.content, p.rows = sf, c, {}
    closeOnEscape(p)

    -- Hooked rather than set, so closeOnEscape's own OnShow hook above survives.
    p:HookScript("OnShow", function(self)
        if not self.closer then
            self.closer = CreateFrame("Button", nil, UIParent)
            self.closer:SetAllPoints(UIParent)
            self.closer:SetFrameStrata("FULLSCREEN")
            self.closer:RegisterForClicks("AnyDown")
            self.closer:SetScript("OnClick", function() p:Hide() end)
        end
        self.closer:Show()
    end)
    p:HookScript("OnHide", function(self)
        if self.closer then self.closer:Hide() end
    end)

    Options._ddPopup = p
    return p
end

local SWATCH_W, SWATCH_H = 60, 12

local DD_PREVIEW_SIZE = 14

-- SetFont in BOTH directions, because an explicit SetFont is what has to be undone and
-- SetFontObject was observed not undoing it: the shared popup's rows are pooled across every
-- dropdown, and a font list left its faces on the profile and sound lists that reused them.
-- Success is read back with GetFont rather than from SetFont's return value, which is only
-- documented for EditBox - a file that fails to load leaves the string with no font at all.
local function applyPreviewFont(fs, path)
    if path and path ~= "" then
        fs:SetFont(path, DD_PREVIEW_SIZE, "")
        if fs:GetFont() then return end
    end
    local file, size, flags = _G.GameFontNormal:GetFont()
    if file then fs:SetFont(file, size, flags) else fs:SetFontObject(_G.GameFontNormal) end
    fs:SetTextColor(1, 1, 1)
end

-- One popup is shared by every dropdown, so a row that grew a swatch has to give it back
-- when a plain list reuses it.
local function decorateRow(b, item, decorate, previewFont)
    applyPreviewFont(b.text, previewFont and previewFont(item))
    if decorate then
        if not b.swatch then
            b.swatchBg = b:CreateTexture(nil, "BACKGROUND")
            b.swatchBg:SetPoint("LEFT", 6, 0)
            b.swatchBg:SetSize(SWATCH_W, SWATCH_H)
            b.swatchBg:SetColorTexture(0, 0, 0, 0.6)
            b.swatch = b:CreateTexture(nil, "ARTWORK")
            b.swatch:SetPoint("LEFT", 6, 0)
            b.swatch:SetSize(SWATCH_W, SWATCH_H)
        end
        b.swatchBg:Show()
        b.swatch:Show()
        b.text:ClearAllPoints()
        b.text:SetPoint("LEFT", 74, 0)
        b.text:SetPoint("RIGHT", -6, 0)
        decorate(b, item)
    elseif b.swatch then
        b.swatchBg:Hide()
        b.swatch:Hide()
        b.text:ClearAllPoints()
        b.text:SetPoint("LEFT", 6, 0)
        b.text:SetPoint("RIGHT", -6, 0)
    end
end

local function showDropdown(anchor, opts, onPick, decorate, current, previewFont)
    local p = dropdownPopup()
    -- The popup hangs off UIParent, so it does not inherit the options window's scale.
    -- Matching it also puts anchor and popup back in one unit space, which the width
    -- arithmetic below depends on.
    p:SetScale((Options.frame and Options.frame:GetScale()) or 1)

    local h = math.min(#opts, DD_MAX_ROWS) * DD_ROW + 8
    p:SetHeight(h)
    p:ClearAllPoints()
    -- A list opened near the foot of a column is taller than the space under it, so it
    -- would render off the bottom of the screen. Compared in real pixels because anchor
    -- and popup can sit at different effective scales.
    if ((anchor:GetBottom() or 0) * anchor:GetEffectiveScale()) - (h * p:GetEffectiveScale()) < 0 then
        p:SetPoint("BOTTOMLEFT",  anchor, "TOPLEFT",  0, 2)
        p:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 2)
    else
        p:SetPoint("TOPLEFT",  anchor, "BOTTOMLEFT",  0, -2)
        p:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
    end

    local activeIndex
    for i = 1, #opts do
        local b = p.rows[i]
        if not b then
            b = CreateFrame("Button", nil, p.content)
            b:SetHeight(DD_ROW)
            b.sel = b:CreateTexture(nil, "BACKGROUND")
            b.sel:SetAllPoints()
            b.sel:SetColorTexture(BRAND_RED[1], BRAND_RED[2], BRAND_RED[3], 1)
            b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            b.text:SetPoint("LEFT", 6, 0)
            b.text:SetPoint("RIGHT", -6, 0)
            b.text:SetJustifyH("LEFT")
            b.text:SetWordWrap(false)
            b.text:SetTextColor(1, 1, 1)
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.10)
            p.rows[i] = b
        end
        local opt = opts[i]
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT",  p.content, "TOPLEFT",  0, -(i - 1) * DD_ROW)
        b:SetPoint("TOPRIGHT", p.content, "TOPRIGHT", 0, -(i - 1) * DD_ROW)
        decorateRow(b, opt.value, decorate, previewFont)
        b.text:SetText(opt.label)
        -- Marked the way the radio buttons mark their active choice, so 42 fonts or 27
        -- sounds do not open with nothing saying which one is in use.
        local isActive = (opt.value == current)
        b.sel:SetShown(isActive)
        if isActive then activeIndex = i end
        b:SetScript("OnClick", function() p:Hide(); onPick(opt.value) end)
        b:Show()
    end
    for i = #opts + 1, #p.rows do p.rows[i]:Hide() end

    -- Taken from the anchor rather than the popup: the popup's own width is only two
    -- SetPoints old here and has not resolved yet.
    p.content:SetSize(math.max(1, anchor:GetWidth() - 28), math.max(1, #opts * DD_ROW))
    p:Show()

    -- One popup is shared by every dropdown and nothing else resets the offset, so a
    -- short list opened after a long one would inherit the long one's scroll position.
    local maxScroll = math.max(0, (#opts - math.min(#opts, DD_MAX_ROWS)) * DD_ROW)
    local want = activeIndex
        and ((activeIndex - 1) * DD_ROW - math.floor(DD_MAX_ROWS / 2) * DD_ROW)
        or 0
    p.scroll:SetVerticalScroll(math.min(math.max(0, want), maxScroll))
end

-- options is a list of { value =, label = } pairs, or a function returning one that is
-- re-read on every open. The setter receives the VALUE, so a translated label can never
-- reach the profile and a setter never has to compare against a display string.
-- decorate(frame, value) draws a preview on the closed button and on every row. Passed by
-- pickers whose values are not self-describing, such as a status bar texture.
-- previewFont(value) returns a font file to draw that row's own label in, which is the only
-- preview a font list can have - a swatch cannot show a typeface.
-- onTest(value) adds a speaker button left of the closed bar that replays the current pick.
function Options:CreateDropdown(content, label, options, getter, setter, tooltip, decorate, onTest, previewFont)
    local holder = CreateFrame("Frame", nil, content)
    holder:SetSize(280, 44)

    local function resolveOptions()
        return (type(options) == "function") and (options() or {}) or options
    end

    local text = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOPLEFT", 0, 0)
    text:SetText(label)
    text:SetTextColor(1, 1, 1)

    local speaker
    if onTest then
        speaker = CreateFrame("Button", nil, holder)
        speaker:SetSize(20, 20)
        local icon = speaker:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexture("Interface\\Common\\VoiceChat-Speaker")
        speaker:SetHighlightTexture("Interface\\Common\\VoiceChat-Speaker", "ADD")
        speaker:SetScript("OnClick", function() onTest(getter()) end)
    end

    local btn = CreateFrame("Button", nil, holder, BackdropTemplateMixin and "BackdropTemplate")
    btn:SetHeight(22)
    -- Both TOP anchors carry the same y. Giving TOPLEFT and TOPRIGHT different offsets sets
    -- one edge twice, silently, and nothing decides which wins.
    btn:SetPoint("TOPLEFT",  holder, "TOPLEFT",  speaker and 24 or 0, -22)
    btn:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, -22)
    if speaker then
        speaker:SetPoint("RIGHT", btn, "LEFT", -4, 0)
        self:AttachTooltip(speaker, label, L["Plays the currently selected sound."])
    end
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.10, 0.10, 0.10, 0.95)
    addHighlight(btn)

    if decorate then
        btn.swatch = btn:CreateTexture(nil, "ARTWORK")
        btn.swatch:SetPoint("LEFT", 6, 0)
        btn.swatch:SetSize(SWATCH_W, SWATCH_H)
    end

    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.text:SetPoint("LEFT", decorate and 74 or 6, 0)
    btn.text:SetPoint("RIGHT", -22, 0)
    btn.text:SetJustifyH("LEFT")
    btn.text:SetWordWrap(false)
    btn.text:SetTextColor(1, 1, 1)

    -- A literal lowercase "v", as EQ has it. There is no chevron in the atlas set that
    -- matches, and an atlas arrow reads as a different widget.
    btn.arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.arrow:SetPoint("RIGHT", -6, 0)
    btn.arrow:SetText("v")
    btn.arrow:SetTextColor(1, 1, 1)

    local function refresh()
        local current = getter()
        if decorate then decorate(btn, current) end
        applyPreviewFont(btn.text, previewFont and previewFont(current))
        -- "NONE" is this addon's no-sound sentinel (Core/Media.lua returns no file for it),
        -- so previewing it can only ever be silent. Hidden rather than left to look broken.
        if speaker then speaker:SetShown(current ~= nil and current ~= "NONE") end
        for _, opt in ipairs(resolveOptions()) do
            if opt.value == current then btn.text:SetText(opt.label); return end
        end
        btn.text:SetText(tostring(current or ""))
    end
    refresh()

    btn:SetScript("OnClick", function()
        showDropdown(btn, resolveOptions(), function(v)
            setter(v)
            refresh()
        end, decorate, getter(), previewFont)
    end)

    holder.button  = btn
    holder.Refresh = refresh
    if tooltip then self:AttachTooltip(holder, label, tooltip) end
    content._controls[#content._controls + 1] = holder
    return holder
end

-- Skipped when ElvUI is loaded, which puts its own class-color button on the picker.
local function elvUILoaded()
    local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G["IsAddOnLoaded"]
    return (f and f("ElvUI")) and true or false
end

local classColorButton, activeColorApply, activeReopen, activeCancel
local pickerHookInstalled = false

-- Installed independently of the class button, which ElvUI suppresses. These three outlive a
-- picker that has closed unless something clears them, and a stale cancel would revert an
-- already committed color the next time the options window hides over an open picker.
local function ensurePickerHook()
    if pickerHookInstalled or not ColorPickerFrame then return end
    pickerHookInstalled = true
    ColorPickerFrame:HookScript("OnHide", function()
        if classColorButton then classColorButton:Hide() end
        activeColorApply, activeReopen, activeCancel = nil, nil, nil
    end)
end

local function ensureClassColorButton()
    if classColorButton ~= nil then return classColorButton or nil end
    if elvUILoaded() or not ColorPickerFrame then
        classColorButton = false
        return nil
    end
    local b = flatButton(ColorPickerFrame, _G.CLASS or "Class", function()
        local Util = ns:GetModule("Util")
        if not (Util and Util.GetPlayerClassColor and activeReopen) then return end
        local r, g, bl = Util.GetPlayerClassColor()
        if not r then return end
        -- SetColorRGB does not reliably move the 10.2.5+ picker, so re-open it seeded instead.
        local a = (ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha()) or 1
        activeReopen(r, g, bl, a)
        if activeColorApply then activeColorApply() end
    end)
    b:SetSize(90, 22)
    b:SetPoint("TOPLEFT", ColorPickerFrame, "TOPRIGHT", 6, -34)
    b:Hide()
    classColorButton = b
    return b
end

-- SetupColorPickerAndShow is the current retail entry point. The field-assignment form
-- is the only one Classic has. Feature-detect, never version-detect.
function Options:ShowColorPicker(r, g, b, a, hasAlpha, onChange, onCancel)
    local cp = ColorPickerFrame
    if not cp then return end
    -- Snapshotted before the first open, so Cancel after a Class click still restores the
    -- color the picker was opened on rather than the seeded class color.
    local origR, origG, origB, origA = r, g, b, a

    local function apply()
        local nr, ng, nb = cp:GetColorRGB()
        local na = 1
        if hasAlpha then
            if cp.GetColorAlpha then
                na = cp:GetColorAlpha()
            elseif OpacitySliderFrame then
                na = OpacitySliderFrame:GetValue()
            end
        end
        onChange(nr, ng, nb, na)
    end
    -- onCancel restores the caller's PREVIOUS value. Falling back to the seeded channels
    -- is wrong when there was no value to begin with: an unset color seeds white, so
    -- Cancel would write white into a profile the user never edited.
    local function cancel()
        if onCancel then onCancel() else onChange(origR, origG, origB, origA) end
    end

    local function openWith(nr, ng, nb, na)
        if cp.SetupColorPickerAndShow then
            cp:SetupColorPickerAndShow({
                r = nr, g = ng, b = nb,
                opacity = na, hasOpacity = hasAlpha and true or false,
                swatchFunc = apply, opacityFunc = apply, cancelFunc = cancel,
            })
        else
            cp.func, cp.opacityFunc, cp.cancelFunc = apply, apply, cancel
            cp.hasOpacity = hasAlpha and true or false
            cp.opacity = na
            cp:SetColorRGB(nr, ng, nb)
            cp:Hide()
            cp:Show()
        end
        -- Set after the open: the legacy branch's Hide fires the OnHide hook that clears these.
        activeColorApply, activeReopen, activeCancel = apply, openWith, cancel
        ensurePickerHook()
        local classBtn = ensureClassColorButton()
        if classBtn then classBtn:Show() end
    end

    openWith(r, g, b, a)
end

function Options:CreateColorPicker(content, label, getter, setter, tooltip, hasAlpha, onClear)
    local holder = CreateFrame("Frame", nil, content)
    holder:SetSize(220, 22)

    local text = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT")
    text:SetText(label)
    text:SetTextColor(1, 1, 1)

    local swatch = CreateFrame("Button", nil, holder)
    swatch:SetSize(44, 20)
    swatch:SetPoint("LEFT", text, "RIGHT", 8, 0)
    local rim = swatch:CreateTexture(nil, "BACKGROUND")
    rim:SetAllPoints()
    rim:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    -- The color is drawn with its own alpha, so it needs something opaque behind it or a
    -- translucent swatch composites against the gold rim and reads as washed-out gold.
    local underlay = swatch:CreateTexture(nil, "BORDER")
    underlay:SetPoint("TOPLEFT", 2, -2)
    underlay:SetPoint("BOTTOMRIGHT", -2, 2)
    underlay:SetColorTexture(0, 0, 0, 1)
    local tex = swatch:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", 2, -2)
    tex:SetPoint("BOTTOMRIGHT", -2, 2)
    addHighlight(swatch, 0.18)

    local clear
    local function paint()
        local c = getter()
        local isSet = (c and c.r ~= nil) and true or false
        if isSet then
            tex:SetColorTexture(c.r, c.g or 0, c.b or 0, c.a or 1)
        else
            tex:SetColorTexture(0.22, 0.22, 0.22, 1)
        end
        if clear then clear:SetShown(isSet) end
    end

    -- Only clearable pickers get the button, so an unset swatch stays distinguishable
    -- from a deliberately black one.
    if onClear then
        clear = flatButton(holder, L["Clear"], function()
            onClear()
            paint()
        end)
        clear:SetSize(60, 18)
        clear:SetPoint("LEFT", holder, "RIGHT", 8, 0)
    end
    paint()

    swatch:SetScript("OnClick", function()
        local c = getter()
        -- Copied rather than aliased: the setter may hand this same table straight back.
        local prev = c and { r = c.r, g = c.g, b = c.b, a = c.a } or nil
        local function commit(v)
            setter(v)
            paint()
        end
        c = c or {}
        Options:ShowColorPicker(c.r or 1, c.g or 1, c.b or 1, c.a or 1, hasAlpha,
            function(nr, ng, nb, na) commit({ r = nr, g = ng, b = nb, a = na }) end,
            function() commit(prev) end)
    end)

    -- The row is hoverable across its whole width for the tooltip, and AlignPickerColumn
    -- can open a wide gap between label and swatch, so the click has to work there too.
    holder:EnableMouse(true)
    holder:SetScript("OnMouseUp", function(_, mouseButton)
        if mouseButton == "LeftButton" then swatch:Click() end
    end)

    holder.button  = swatch
    holder.label   = text
    holder.paint   = paint
    holder.Refresh = paint
    if tooltip then self:AttachTooltip(holder, label, tooltip) end
    content._controls[#content._controls + 1] = holder
    return holder
end

-- Dims a control whose master switch is off. Deliberately does NOT disable the mouse:
-- AttachTooltip's hover lives on these same frames, and a control that cannot say why it is
-- grayed is worse than one that is simply lit. The value stays editable and takes effect
-- when its master is switched back on.
function Options:SetDependent(control, on)
    if control then control:SetAlpha(on and 1 or 0.4) end
end

-- A checkbox frame is a fixed 22x22 and its label hangs OUTSIDE it. SetHitRectInsets widens
-- the mouse rect and never GetWidth, so the frame's right edge says nothing about where its
-- text ends, and anything placed beside one at a hardcoded offset collides the moment a label
-- outruns the number that was guessed. A translation does that on every flavor - "Show header
-- bars" is about half again as wide in French and Russian as in English.
--
-- Each argument is a { checkbox, satellite } pair. They land in ONE column past the widest
-- label in the group, so a short label does not pull its own satellite left out of line.
local SATELLITE_GAP = 16

function Options:AlignSatelliteColumn(...)
    local rows = { ... }
    local reach = 0
    for _, row in ipairs(rows) do
        local cb  = row[1]
        local lbl = cb and cb.label
        local w   = (lbl and lbl:GetStringWidth()) or 0
        -- The 4 is CreateCheckbox's own label inset, and the box width is read off the frame
        -- rather than written here again so the two cannot drift apart.
        if w > 0 then
            local r = (cb:GetWidth() or 0) + 4 + w
            if r > reach then reach = r end
        end
    end
    -- A string that has not been laid out answers 0, and 0 is truthy, so this has to test the
    -- value. The floor is the widest reach any of these groups used before they were measured
    -- (22 + 170), so a failed measure cannot land a satellite further left than it already sat.
    if reach <= 0 then reach = 192 end

    for _, row in ipairs(rows) do
        row[2]:ClearAllPoints()
        row[2]:SetPoint("LEFT", row[1], "LEFT", reach + SATELLITE_GAP, 0)
    end
end

-- Lines a run of pickers up as a table: labels flush left, every swatch in one column just
-- past the widest label. EQ instead right-aligns each label off its own swatch, which
-- straightens the swatches but leaves the labels ragged - its Border Color reads indented
-- from the Background Color above it and the Border Thickness slider below.
function Options:AlignPickerColumn(...)
    local pickers = { ... }
    local widest = 0
    for _, p in ipairs(pickers) do
        local w = p.label:GetStringWidth() or 0
        if w > widest then widest = w end
    end
    for _, p in ipairs(pickers) do
        p.label:ClearAllPoints()
        p.label:SetPoint("LEFT", p, "LEFT", 0, 0)
        p.button:ClearAllPoints()
        p.button:SetPoint("TOP",  p, "TOP", 0, -1)
        p.button:SetPoint("LEFT", p, "LEFT", widest + 8, 0)
        -- A translated label can outrun the 220 the holder is built at, and anything hung
        -- off the holder's right (the Clear button) would then sit under the swatch.
        local need = widest + 8 + p.button:GetWidth()
        if need > p:GetWidth() then p:SetWidth(need) end
    end
end

-- A hand-anchored column resolves nothing until the next frame, so its height is unknowable
-- at build time. Run per view rather than once per build as EQ does, because Build() runs
-- at login with the whole window hidden - GetTop() is nil there and a one-shot measure
-- would leave the tab unscrollable until a reload. Exposed because a tab that re-anchors
-- its own column at runtime has to re-measure without waiting for the next tab switch.
function Options:MeasureContent(content)
    C_Timer.After(0, function()
        local top = content:GetTop()
        if not top then return end
        local lowest = top

        -- Regions as well as children. A FontString is not a child, so a children-only
        -- walk measures a tab whose lowest element is a heading or a label as empty -
        -- which is the whole of the About tab.
        local function consider(o)
            if not (o and o.IsShown and o:IsShown() and o.GetBottom) then return end
            local bottom = o:GetBottom()
            if bottom and bottom < lowest then lowest = bottom end
        end
        for _, child  in ipairs({ content:GetChildren() }) do consider(child) end
        for _, region in ipairs({ content:GetRegions()  }) do consider(region) end

        content:SetHeight((top - lowest) + 28)
    end)
end

local function styleTab(btn, selected)
    if selected then
        btn.bg:SetColorTexture(BRAND_RED[1], BRAND_RED[2], BRAND_RED[3], 1)
    else
        btn.bg:SetColorTexture(unpack(TAB_INACTIVE))
    end
    btn.text:SetTextColor(1, 1, 1, 1)
end

function Options:SelectTab(id)
    if not self.frame then return end
    for _, t in ipairs(self.tabs) do
        local isSel = (t.id == id)
        styleTab(t._button, isSel)
        if isSel then
            if not t._built then
                t._content._controls = {}
                t.build(self, t._content)
                t._built = true
            end
            if t.refresh then t.refresh(self, t._content) end
            for _, c in ipairs(t._content._controls or {}) do
                if c.Refresh then c:Refresh() end
            end
            t._scroll:Show()
            self:MeasureContent(t._content)
        else
            t._scroll:Hide()
        end
    end
    local char = ns:GetModule("DB"):Char()
    if char then char.lastOptionsTab = id end
    self._current = id
end

function Options:Build()
    if self.frame then return end

    local f = CreateFrame("Frame", "EQOTOptionsFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    self.frame = f
    f:SetSize(W, H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    -- This frame persists no position, so a window dragged off screen would stay there for
    -- every later show. Every other movable frame in the addon already clamps.
    f:SetClampedToScreen(true)
    f:Hide()
    closeOnEscape(f)

    -- Both hang off UIParent rather than this frame, so neither goes away on its own and a
    -- list or a color picker would be left floating over the game world.
    f:HookScript("OnHide", function()
        if Options._ddPopup then Options._ddPopup:Hide() end
        ns.Util.Tooltip():Hide()
        -- Closing the window mid-edit has to CANCEL the picker, not merely hide it. The live
        -- preview writes on every drag frame, so hiding alone commits whatever color the
        -- wheel was last sitting on. Captured before the Hide, which clears it.
        if ColorPickerFrame and ColorPickerFrame:IsShown() then
            local cancelPending = activeCancel
            ColorPickerFrame:Hide()
            if cancelPending then cancelPending() end
        end
    end)

    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        f:SetBackdropColor(0, 0, 0, 0.95)
        f:SetBackdropBorderColor(BRAND_RED[1], BRAND_RED[2], BRAND_RED[3], 1.0)
    end

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText("EQ Objective Tracker")
    title:SetTextColor(unpack(BRAND_RED))
    title:SetFont(title:GetFont(), 25, "OUTLINE")

    local version = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    version:SetPoint("TOPRIGHT", -34, -14)
    version:SetText("v" .. ns.VERSION)
    version:SetTextColor(1, 1, 1)

    -- Gold rather than the panel's white, as EQ has it. This is the only LINK in the panel,
    -- so it is the third sanctioned use of GOLD alongside tooltip titles and the swatch rim.
    local discord = CreateFrame("Button", nil, f)
    discord.icon = discord:CreateTexture(nil, "OVERLAY")
    discord.icon:SetSize(16, 16)
    discord.icon:SetPoint("LEFT", 0, 0)
    discord.icon:SetTexture("Interface\\AddOns\\EQObjectiveTracker\\Media\\Textures\\discord.tga")
    discord.text = discord:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    discord.text:SetPoint("LEFT", discord.icon, "RIGHT", 5, 0)
    discord.text:SetText(L["Join our Discord!"])
    discord.text:SetTextColor(unpack(GOLD))
    -- `<= 0` as well as nil, because 0 is truthy in Lua and an unmeasured string would size
    -- the button to the icon alone, leaving the label unclickable with nothing to show why.
    local discordW = discord.text:GetStringWidth()
    if not discordW or discordW <= 0 then discordW = 90 end
    discord:SetSize(16 + 5 + discordW + 4, 18)
    discord:SetPoint("TOPLEFT", 14, -15)
    discord:SetScript("OnClick", function() ns:ShowDiscord() end)
    discord:SetScript("OnEnter", function(s) s.text:SetTextColor(1, 1, 1) end)
    discord:SetScript("OnLeave", function(s) s.text:SetTextColor(unpack(GOLD)) end)
    -- MUST stay below the two SetScript calls. AttachTooltip uses HookScript, so the color
    -- swap runs and then the tooltip draws. Above them, SetScript would replace the hook
    -- chain and the tooltip would vanish silently, with the hover color still working.
    -- EQ wraps this tooltip's title but hardcodes its body in English.
    self:AttachTooltip(discord, L["Join our Discord"], L["Click to copy the invite link."])

    -- Untemplated to match EQ - UIPanelCloseButton draws Blizzard's own red panel art.
    local close = CreateFrame("Button", nil, f)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -8, -10)
    local closeBg = close:CreateTexture(nil, "BACKGROUND")
    closeBg:SetAllPoints()
    closeBg:SetColorTexture(0, 0, 0, 0.9)
    addHighlight(close, 0.20)
    local closeText = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeText:SetPoint("CENTER")
    closeText:SetText("X")
    closeText:SetTextColor(1, 1, 1, 1)
    close:SetScript("OnClick", function() f:Hide() end)

    f.tabStrip = CreateFrame("Frame", nil, f)
    f.tabStrip:SetPoint("TOPLEFT", FRAME_PAD, -TAB_TOP)
    f.tabStrip:SetPoint("TOPRIGHT", -FRAME_PAD, -TAB_TOP)
    f.tabStrip:SetHeight(TAB_H)

    f.tabContent = CreateFrame("Frame", nil, f)
    f.tabContent:SetPoint("TOPLEFT", FRAME_PAD, -(TAB_TOP + TAB_H + 6))
    f.tabContent:SetPoint("BOTTOMRIGHT", -FRAME_PAD, FRAME_PAD)

    local x = 0
    for _, t in ipairs(self.tabs) do
        local b = CreateFrame("Button", nil, f.tabStrip)
        b:SetHeight(TAB_H)
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints()
        addHighlight(b)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.text:SetPoint("CENTER")
        b.text:SetText(t.title)
        b:SetWidth(b.text:GetStringWidth() + TAB_PAD_X * 2)
        b:SetPoint("LEFT", f.tabStrip, "LEFT", x, 0)
        b:SetScript("OnClick", function() Options:SelectTab(t.id) end)
        x = x + b:GetWidth() + 4
        t._button = b

        local scroll = CreateFrame("ScrollFrame", nil, f.tabContent,
                                   "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 0, 0)
        scroll:SetPoint("BOTTOMRIGHT", -24, 0)
        scroll:Hide()
        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(W - FRAME_PAD * 2 - 24, 1)
        content._controls = {}
        scroll:SetScrollChild(content)
        t._scroll, t._content = scroll, content
    end

    local char = ns:GetModule("DB"):Char()
    local want = (char and char.lastOptionsTab) or (self.tabs[1] and self.tabs[1].id)
    local found = false
    for _, t in ipairs(self.tabs) do
        if t.id == want then found = true break end
    end
    self:SelectTab(found and want or (self.tabs[1] and self.tabs[1].id))
end

-- EQ's version, ported as it stands. The UIParent-units idiom the tracker and zone bar use
-- does not apply here: this frame persists no position, so there is nothing stored to be in
-- the wrong units.
function Options:ApplyWindowScale()
    local f = self.frame
    if not f then return end
    local g = ns:GetModule("DB"):Global()
    local s = g and g.optionsWindowScale
    if type(s) ~= "number" or s <= 0 then s = 1 end

    -- The window is a fixed 1020x720. On a default 768-unit UIParent anything past about
    -- 1.06 pushes the close button and then the tab bar off the top edge, and since this
    -- re-applies on every open the broken state would survive closing the window.
    local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
    if uw and uh and uw > 0 and uh > 0 then
        local capped = math.min(s, uw / W, uh / H)
        -- Written back, or the slider goes on reporting a number the window never had: at a
        -- 768-unit UIParent every step from about 1.07 up rendered identically while the
        -- readout still said 1.40. The ceiling moves with the player's UI Scale.
        if capped < s and g then g.optionsWindowScale = capped end
        s = capped
    end

    -- SetScale re-reads the anchor offsets in the new scale, so a dragged window jumps
    -- unless its center is restored.
    local cx, cy = f:GetCenter()
    local oldEff = f:GetEffectiveScale()
    f:SetScale(s)
    if cx and cy and oldEff then
        local newEff = f:GetEffectiveScale()
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx * oldEff / newEff, cy * oldEff / newEff)
    end
end

function Options:Toggle()
    self:Build()
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self:ApplyWindowScale()
        self:SelectTab(self._current)
        self.frame:Show()
    end
end

function Options:OnEnable()
    self:Build()
end
