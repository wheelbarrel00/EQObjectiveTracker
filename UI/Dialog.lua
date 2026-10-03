local _, ns = ...

local Dialog = ns:RegisterModule("Dialog", {})
local L      = ns.L

-- Drawn by the EverythingUI library's dialog, which keeps the rules this one has always had: the
-- callback runs before the dialog hides (a ReloadUI from Yes was blocked on retail 12.1 while it hid
-- first), Enter never accepts a confirm, Escape cancels, and a dialog opened over another cancels
-- it. Only the fields the library knows are passed on, so a stray one cannot make it raise.
function Dialog:Show(opts)
    ns:GetModule("Options").ui:ShowDialog({
        title            = opts.title or "EQ Objective Tracker",
        text             = opts.text or "",
        button1          = opts.button1 or L["OK"],
        button2          = opts.button2,
        onAccept         = opts.onAccept,
        onCancel         = opts.onCancel,
        hasEditBox       = opts.hasEditBox and true or nil,
        maxLetters       = opts.maxLetters,
        editBoxText      = opts.editBoxText,
        highlightEditBox = opts.highlightEditBox and true or nil,
    })
end
