local _, ns = ...

local QuestLogChecks = ns:RegisterModule("QuestLogChecks", {})

-- Measured on 1.15.9 against a row Blizzard had positioned itself: its check sits four pixels
-- past the right edge of the title FontString. Derived that way rather than as text width plus a
-- constant, because the constant form silently carries the title's 20px indent inside it.
local CHECK_PAD = 4

-- Measured on 1.15.9: shift-clicking a quest log row calls NEITHER AddQuestWatch NOR
-- RemoveQuestWatch. Temporary print hooks on both globals stayed silent across clicks that
-- visibly did nothing, with Blizzard's own watch list already empty. Whatever makes its handler
-- bail, the gesture is a CLICK - so the click is what this listens to, and the watch functions
-- are out of the path entirely.
--
-- HookScript rather than hooking a named handler, because it survives Blizzard changing which
-- function that row's OnClick points at.
local function hookRow(row)
    if row._eqotClickHooked then return end
    row._eqotClickHooked = true
    row:HookScript("OnClick", function(self, button)
        if button and button ~= "LeftButton" then return end
        -- The IsShiftKeyDown fallback overrides a rebound QUESTWATCHTOGGLE, so a player who has
        -- moved that modifier to Ctrl still gets shift toggling. Kept because the gesture is
        -- confirmed working in game this way and QUESTWATCHTOGGLE's presence on 1.15.9 has not
        -- been measured, so dropping it risks removing the gesture entirely.
        -- With the chat edit box open, shift-click is the link gesture, and toggling there
        -- materializes the whole tracked set behind the player's back. The explicit
        -- QUESTWATCHTOGGLE branch is left unconditional, since that one was asked for.
        local linking = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
        local wantsToggle = (IsModifiedClick and IsModifiedClick("QUESTWATCHTOGGLE"))
                            or (not linking and IsShiftKeyDown and IsShiftKeyDown())
        if not wantsToggle then return end
        local TrackedSet = ns:GetModule("TrackedSet")
        if TrackedSet then TrackedSet:ToggleAtIndex(self:GetID()) end
    end)
end

-- Blizzard draws the quest log's tracked checkmark from its own watch list, and this addon no
-- longer writes to that list - so without this the log would show nothing checked while the
-- tracker showed a full set, which is exactly the two-lists-disagreeing state this replaces.
--
-- Repainting the texture is deliberately narrower than answering IsQuestWatched for the whole
-- UI. Replacing that global would make every other addon read our set believing it to be the
-- game's, and an addon that stashes the original at load would capture ours instead - which is
-- the failure that made three recorded "client facts" in this project wrong for months, from the
-- other direction. Only this frame's display changes here, and nothing is told anything.
-- Rows are discovered by walking QuestLogTitle1, 2, 3 ... until one is missing, and each row's
-- quest log index is read off its own GetID rather than recomputed from a scroll offset. Both
-- avoid a named constant: an earlier version bounded the loop by QUESTS_DISPLAYED, and if that
-- global is absent the loop runs zero times and repaints nothing, silently.
local function repaint()
    local TrackedSet = ns:GetModule("TrackedSet")
    if not TrackedSet then return end

    QuestLogChecks._rows = 0
    local i = 1
    while true do
        local row = _G["QuestLogTitle" .. i]
        if not row then break end
        hookRow(row)
        local check = _G["QuestLogTitle" .. i .. "Check"]
        if check and row:IsShown() and TrackedSet:IsTrackedAtIndex(row:GetID()) then
            -- Positioning is not optional. Blizzard only moves this texture for rows IT decided
            -- were watched and leaves every other one at a default offset of 50, which sits ON TOP
            -- of the title text - so showing a check without re-anchoring it draws a faint smudge
            -- across the quest name and reads as nothing happening.
            local text = _G["QuestLogTitle" .. i .. "NormalText"]
            if text then
                check:ClearAllPoints()
                check:SetPoint("LEFT", text, "RIGHT", CHECK_PAD, 0)
            end
            check:Show()
        elseif check then
            check:Hide()
        end
        i = i + 1
    end
    QuestLogChecks._rows = i - 1
end

function QuestLogChecks:OnEnable()
    if type(QuestLog_Update) ~= "function" then
        self._why = "QuestLog_Update absent"
        return
    end

    -- hooksecurefunc rather than a replacement, the same taint-safe shape UI/Visibility.lua uses
    -- on the world map. Blizzard has already drawn its own answer by the time this runs.
    hooksecurefunc("QuestLog_Update", repaint)

    -- Repaints BOTH surfaces a set change affects. The log does not redraw when the set changes
    -- from the tracker's row menu, and the tracker does not redraw when it changes from here.
    --
    -- Asking the tracker directly rather than leaving it to the provider's own notifier is
    -- deliberate. Measured: calling TrackedSet:Set from a /run updated the checkmark and left the
    -- tracker stale, so that notifier is not reaching a render. The quest log click SEEMED to work
    -- only because Blizzard's handler also fires QUEST_LOG_UPDATE, which the provider listens to -
    -- the repaint was riding on a coincidence. UI may ask UI, and the row menu has always done
    -- exactly this after a track or untrack.
    self._hooked = true

    local TrackedSet = ns:GetModule("TrackedSet")
    if TrackedSet then
        self._subscribed = true
        TrackedSet:OnDirty(function()
            repaint()
            local Tracker = ns:GetModule("Tracker")
            if Tracker and Tracker.Refresh then Tracker:Refresh() end
        end)
    else
        self._why = "TrackedSet module absent"
    end
end

-- Both halves can be missing with nothing on screen to say so: OnEnable returns outright
-- without QuestLog_Update, and skips the repaint subscription on its own if TrackedSet is
-- absent. rows counts what the last repaint actually walked, so a hook that fires against a
-- log Blizzard has not built yet is visible as 0 rather than as silence.
function QuestLogChecks:DebugLine()
    return ("quest log checks: hook %s, repaint subscription %s, %d row(s) last pass%s")
        :format(self._hooked and "installed" or "missing",
                self._subscribed and "on" or "|cffff5555off|r",
                self._rows or 0,
                self._why and (" | " .. self._why) or "")
end
