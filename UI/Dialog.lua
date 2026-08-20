local _, ns = ...

local Dialog = ns:RegisterModule("Dialog", {})
local L      = ns.L

-- Own frame rather than StaticPopup: that system recycles a small shared pool, so an
-- insecure handler here could taint the frame the logout or quit dialog later reuses.

-- The options window's own border and title color, carried here rather than a second scheme of
-- its own. Most callers are that window, though the Questie prompt and /eqot importeq both
-- reach this with it closed.
local BRAND_R, BRAND_G, BRAND_B = 0.635, 0.000, 0.039

local function makeButton(parent)
    return CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
end

local function fitButton(b, label)
    b:SetText(label or "")
    local fs = b:GetFontString()
    local w = fs and math.ceil(fs:GetStringWidth()) or 0
    b:SetSize(math.max(90, w + 28), 22)
end

function Dialog:_finish(accepted)
    local opts = self.opts
    -- Guards a double fire - a button click and the escape key can both land.
    if not opts then return end
    self.opts = nil

    local f = self.frame
    local text = (f and f.editBox:IsShown()) and f.editBox:GetText() or nil
    -- Hiding the frame releases the focus on its own, but only while this stays the sole
    -- path that hides it. An edit box that kept focus would swallow Enter game-wide.
    if f then f.editBox:ClearFocus(); f:Hide() end

    if accepted then
        if opts.onAccept then opts.onAccept(text) end
    elseif opts.onCancel then
        opts.onCancel()
    end
end

function Dialog:Build()
    if self.frame then return self.frame end

    -- Deliberately unnamed. A named frame can be read out of _G, which is the whole
    -- mechanism behind the UISpecialFrames taint - see closeOnEscape in Options/Frame.lua.
    -- Template argument guarded: CreateFrame raises on a template the client does not know.
    -- Insurance rather than a live fix - the mixin was measured present on both Classic
    -- clients - and all 13 backdrop frames in this addon take the same guard.
    local f = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetSize(430, 160)
    f:SetPoint("CENTER")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()

    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        f:SetBackdropColor(0, 0, 0, 0.94)
        f:SetBackdropBorderColor(BRAND_R, BRAND_G, BRAND_B, 1)
    end

    -- SetPropagateKeyboardInput is protected, so the whole handler stands down in combat
    -- and Escape falls through to the default UI.
    f:EnableKeyboard(false)
    local function armKeyboard(frame)
        if InCombatLockdown() or not frame:IsShown() then return end
        frame:EnableKeyboard(true)
        frame:SetPropagateKeyboardInput(true)
    end
    f:HookScript("OnShow", function(frame)
        -- Deferred rather than dropped. A dialog opened in combat stayed keyboard-dead for as
        -- long as it was shown, so Escape never closed it even once the fight was over.
        if InCombatLockdown() then
            ns:GetModule("Events"):RunWhenOutOfCombat("eqot.dialogKeys",
                function() armKeyboard(frame) end)
            return
        end
        armKeyboard(frame)
    end)
    f:HookScript("OnHide", function(frame) frame:EnableKeyboard(false) end)
    f:SetScript("OnKeyDown", function(frame, key)
        if InCombatLockdown() then return end
        if key == "ESCAPE" then
            frame:SetPropagateKeyboardInput(false)
            Dialog:_finish(false)
        elseif (key == "ENTER" or key == "NUMPADENTER") and not frame.editBox:IsShown() then
            -- Swallowed, never bound to accept: most of the confirms that reach here reload
            -- the UI, so a stray keypress must not be able to trigger one. Without
            -- this it opens the chat box behind a dialog that looks modal.
            frame:SetPropagateKeyboardInput(false)
        else
            frame:SetPropagateKeyboardInput(true)
        end
    end)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", 0, -12)
    f.title:SetTextColor(BRAND_R, BRAND_G, BRAND_B)
    -- Outlined for the same reason the options window's title is: brand red is dark, and
    -- unoutlined at this size it reads muddy against the near-black fill.
    f.title:SetFont(f.title:GetFont(), 18, "OUTLINE")

    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.text:SetPoint("TOPLEFT", 18, -40)
    f.text:SetPoint("TOPRIGHT", -18, -40)
    f.text:SetJustifyH("LEFT")
    f.text:SetSpacing(3)

    f.editBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.editBox:SetAutoFocus(false)
    f.editBox:SetSize(340, 22)
    f.editBox:SetPoint("TOP", f.text, "BOTTOM", 0, -12)
    f.editBox:SetScript("OnEscapePressed", function() Dialog:_finish(false) end)
    f.editBox:SetScript("OnEnterPressed", function() Dialog:_finish(true) end)
    f.editBox:Hide()

    f.accept = makeButton(f)
    f.accept:SetScript("OnClick", function() Dialog:_finish(true) end)

    f.cancel = makeButton(f)
    f.cancel:SetPoint("BOTTOMRIGHT", -18, 14)
    f.cancel:SetScript("OnClick", function() Dialog:_finish(false) end)

    self.frame = f
    return f
end

function Dialog:Show(opts)
    local f = self:Build()
    -- Close a dialog still on screen so its callbacks are not silently dropped.
    if self.opts then self:_finish(false) end
    self.opts = opts

    f.title:SetText(opts.title or "EQ Objective Tracker")
    f.text:SetText(opts.text or "")

    fitButton(f.accept, opts.button1 or L["OK"])
    if opts.button2 then
        fitButton(f.cancel, opts.button2)
        f.cancel:Show()
    else
        f.cancel:Hide()
    end

    if opts.hasEditBox then
        f.editBox:Show()
        f.editBox:SetMaxLetters(opts.maxLetters or 0)
        f.editBox:SetText(opts.editBoxText or "")
        f.editBox:SetCursorPosition(0)
        f.editBox:SetFocus()
        -- After SetFocus, which clears any selection of its own.
        if opts.highlightEditBox then f.editBox:HighlightText() end
    else
        f.editBox:Hide()
        f.editBox:ClearFocus()
    end

    f.accept:ClearAllPoints()
    if opts.button2 then
        f.accept:SetPoint("BOTTOMLEFT", 18, 14)
    else
        f.accept:SetPoint("BOTTOM", 0, 14)
    end

    f:SetHeight(46 + math.max(18, f.text:GetStringHeight())
                + (opts.hasEditBox and 34 or 0) + 50)

    f:Show()
    f:Raise()
end
