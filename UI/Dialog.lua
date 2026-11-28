local _, ns = ...

local Dialog = ns:RegisterModule("Dialog", {})
local L      = ns.L

-- Drawn by the EverythingUI library's dialog, which keeps the rules this one has always had: the
-- callback runs before the dialog hides (a ReloadUI from Yes was blocked on retail 12.1 while it hid
-- first), Enter never accepts a confirm, Escape cancels, and a dialog opened over another cancels
-- it. Only the fields the library knows are passed on, so a stray one cannot make it raise.
-- Every close runs one of the callbacks, so wrapping them tracks whether one is on screen.
local open = false
local function closing(fn)
    return function(...)
        open = false
        if fn then return fn(...) end
    end
end

function Dialog:Show(opts)
    ns:GetModule("Options").ui:ShowDialog({
        title            = opts.title or "EQ Objective Tracker",
        text             = opts.text or "",
        button1          = opts.button1 or L["OK"],
        button2          = opts.button2,
        onAccept         = closing(opts.onAccept),
        onCancel         = closing(opts.onCancel),
        -- Left out unless given, so the secondary button falls back to onCancel.
        onDecline        = opts.onDecline and closing(opts.onDecline) or nil,
        hasEditBox       = opts.hasEditBox and true or nil,
        maxLetters       = opts.maxLetters,
        editBoxText      = opts.editBoxText,
        highlightEditBox = opts.highlightEditBox and true or nil,
        -- The library raises on readOnly without an edit box.
        readOnly         = (opts.hasEditBox and opts.readOnly) and true or nil,
    })
    -- After the call, since the library first cancels any dialog still on screen.
    open = true
end

function Dialog:IsShown()
    return open
end
