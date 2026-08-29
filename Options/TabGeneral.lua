local _, ns = ...

local Options = ns:GetModule("Options")
local L       = ns.L

-- The right column is a second anchor chain rooted this far right of the first header,
-- sharing its y. Same figure the Tracker and Appearance tabs use.
local COLUMN_X = 460

Options:RegisterTab({
    id    = "general",
    title = L["General"],
    order = 10,
    build = function(self, content)
        local DB = ns:GetModule("DB")

        local h = self:CreateHeading(content, L["General"])
        h:SetPoint("TOPLEFT", 8, -8)

        local lock = self:CreateCheckbox(content, L["Lock tracker"],
            function() return DB:General().lockTracker end,
            function(v)
                DB:General().lockTracker = v
                ns:GetModule("Tracker"):ApplyLockState()
            end,
            L["Disable drag-to-move and resize."])
        lock:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, self.GAP.tabHead)

        local function hideRule(key, label, tooltip)
            return self:CreateCheckbox(content, label,
                function() return DB:General()[key] end,
                function(v)
                    DB:General()[key] = v
                    ns:GetModule("Visibility"):Apply()
                end,
                tooltip)
        end

        local combat = hideRule("hideInCombat", L["Hide tracker in combat"],
            L["Hides the tracker while you are in combat and brings it back when you leave."])
        combat:SetPoint("TOPLEFT", lock, "BOTTOMLEFT", 0, -2)

        local inst = hideRule("hideInInstances", L["Hide tracker in instances"],
            L["Raids, dungeons, delves."])
        inst:SetPoint("TOPLEFT", combat, "BOTTOMLEFT", 0, -2)

        local mapHide = hideRule("hideOnMapOpen", L["Hide tracker when world map is open"],
            L["Hides the tracker while the world map is up, so it does not sit over the map."])
        mapHide:SetPoint("TOPLEFT", inst, "BOTTOMLEFT", 0, -2)

        local prev = mapHide
        -- No Mythic+ API on this client, so the toggle could never fire
        if ns.Has.MythicPlus then
            local mplus = hideRule("hideInMythicPlus", L["Hide tracker in Mythic+"],
                L["Hides the tracker during an active Mythic+ run, then brings it back when the run ends."])
            mplus:SetPoint("TOPLEFT", mapHide, "BOTTOMLEFT", 0, -2)
            prev = mplus
        end

        -- The tooltip has to name what does NOT count, because a player with world quests or a
        -- zone bar on screen and the tracker gone would otherwise read this as a bug.
        local noQuests = hideRule("hideWhenNoQuests",
            L["Hide tracker when no quests are showing"],
            L["Hides the whole tracker while you have no quest or campaign rows, and brings it back the moment you accept one. Nothing else keeps it on screen by itself, including world quests, achievements, the zone progress bar, and the delve or scenario panel."])
        noQuests:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -2)
        prev = noQuests

        local autoTrack = self:CreateCheckbox(content, L["Auto-track accepted quests"],
            function() return DB:General().autoTrackAccepted ~= false end,
            function(v) DB:General().autoTrackAccepted = v end,
            L["Matches Blizzard's default."])
        autoTrack:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -2)

        local restore = self:CreateCheckbox(content, L["Keep focused quest after relog"],
            function() return DB:General().restoreSuperTrackOnLogin ~= false end,
            function(v) DB:General().restoreSuperTrackOnLogin = v end,
            L["Restores the waypoint arrow."])
        restore:SetPoint("TOPLEFT", autoTrack, "BOTTOMLEFT", 0, -2)

        -- Offered only where the other tracker is loaded: a toggle that could never do
        -- anything is worse than no toggle. The condition comes from the module so this row
        -- and the login prompt cannot disagree. owScale below anchors to prev2 because this
        -- row is conditional, not to restore.
        local prev2 = restore
        local Coexist = ns:GetModule("QuestieCoexist")
        if Coexist and Coexist:QuestiePresent() then
            local questie = self:CreateCheckbox(content, L["Hide Questie's quest tracker"],
                function() return DB:General().hideQuestieTracker end,
                function(v)
                    DB:General().hideQuestieTracker = v
                    local Q = ns:GetModule("QuestieCoexist")
                    if v then
                        if Q then Q:Apply() end
                        return
                    end
                    -- Unticking stops this addon hiding it, but showing it again is only
                    -- correct if that addon itself wants it shown.
                    local q, f = Questie, Questie_BaseFrame
                    local wanted = not (type(q) == "table" and type(q.db) == "table"
                                        and type(q.db.profile) == "table")
                                   or q.db.profile.trackerEnabled ~= false
                    if wanted and type(f) == "table" and type(f.Show) == "function" then
                        f:Show()
                    end
                end,
                L["Hides Questie's tracker frame while EQ Objective Tracker is running. It only hides the frame, and Questie's own disable path is never called."])
            questie:SetPoint("TOPLEFT", restore, "BOTTOMLEFT", 0, -2)
            prev2 = questie
        end

        local owScale = self:CreateSlider(content, L["Options Window Scale"], 0.7, 1.4, 0.05,
            function() return (DB:Global() and DB:Global().optionsWindowScale) or 1.0 end,
            function(v)
                local g = DB:Global()
                if g and type(v) == "number" and v > 0 then g.optionsWindowScale = v end
            end,
            L["Resizes this EQ Objective Tracker options window only. It does not change the quest tracker or anything shown in the game world. The new size applies when you let go of the slider."])
        owScale:SetPoint("TOPLEFT", prev2, "BOTTOMLEFT", 0, -18)
        -- The slider sits inside the window it scales, so applying mid-drag fights the drag
        -- and snaps to the ends.
        if owScale.slider then
            owScale.slider:HookScript("OnMouseUp", function() Options:ApplyWindowScale() end)
        end

        -- EQOT-only, approved: EQ has no equivalent anywhere in its Options. Grouped with
        -- Reset all settings at the foot of the column rather than breaking the checkbox run.
        local resetPos = self:CreateButton(content, L["Reset position and size"], 160, function()
            ns:GetModule("Tracker"):ResetPosition()
        end, L["Returns the tracker to its default position and size."])
        resetPos:SetSize(160, 24)
        resetPos:SetPoint("TOPLEFT", owScale, "BOTTOMLEFT", 0, -16)

        local resetAll = self:CreateButton(content, L["Reset all settings"], 160, function()
            local Dialog = ns:GetModule("Dialog")
            if not Dialog then return end
            Dialog:Show({
                title    = "EQ Objective Tracker",
                text     = L["Reset every EQ Objective Tracker setting to defaults? The interface will reload."],
                button1  = L["Reset"],
                button2  = L["Cancel"],
                onAccept = function()
                    -- Covers all three AceDB scopes. schemaVersion is deliberately left
                    -- alone - it is migration state, not a setting, and clearing it would
                    -- re-run every conversion.
                    DB:ResetAll()
                    -- Resetting the stored geometry does not resize the frame already on
                    -- screen, and the reload rebuilds from config rather than from the
                    -- frame - so put the live one back too rather than leaving the two
                    -- disagreeing across the reload.
                    ns:GetModule("Tracker"):ResetPosition()
                    ReloadUI()
                end,
            })
        end, L["Restores every setting on every tab to its default and reloads the interface. This also clears the Options Window Scale, which every character shares, and this character's collapsed sections and individually hidden entries."])
        resetAll:SetSize(160, 24)
        resetAll:SetPoint("TOPLEFT", resetPos, "BOTTOMLEFT", 0, -10)

        local profilesHeader = self:CreateHeading(content, L["Profiles"])
        profilesHeader:SetPoint("TOPLEFT", h, "TOPLEFT", COLUMN_X, 0)
        self:AttachTooltip(profilesHeader, L["Profiles"],
            L["Switching profiles reloads the UI. Profiles are shared across characters. Use them to keep different setups such as raid and solo. |cffEBB706New Profile|r prompts for a name and creates it on the spot."])

        local function profileList()
            local names = {}
            if not (DB.db and DB.db.GetProfiles) then return names end
            for _, name in ipairs(DB.db:GetProfiles()) do
                names[#names + 1] = name
            end
            -- AceDB builds that list with pairs(), so its order is arbitrary and can differ
            -- between sessions with nothing having changed.
            table.sort(names)
            local out = {}
            for _, name in ipairs(names) do out[#out + 1] = { value = name, label = name } end
            return out
        end

        local function currentProfile()
            return (DB.db and DB.db.GetCurrentProfile and DB.db:GetCurrentProfile()) or "Default"
        end

        local function profileExists(name)
            if not (DB.db and DB.db.GetProfiles) then return false end
            for _, p in ipairs(DB.db:GetProfiles()) do
                if p == name then return true end
            end
            return false
        end

        -- Every one of these reloads, exactly as EQ does. Migrate:Run only fires from
        -- DB:OnInitialize, so swapping a profile in place would leave it unconverted.
        local function setProfile(name)
            if not (DB.db and DB.db.SetProfile) then return end
            DB.db:SetProfile(name)
            ReloadUI()
        end

        local function createProfileCopiedFromCurrent(name)
            if not DB.db then return end
            local source = DB.db:GetCurrentProfile()
            DB.db:SetProfile(name)
            if source and source ~= name and DB.db.CopyProfile then
                DB.db:CopyProfile(source, true)
            end
            ReloadUI()
        end

        local profDD = self:CreateDropdown(content, L["Active profile"],
            profileList, currentProfile, setProfile,
            L["Switches to another saved settings profile. The interface reloads immediately when you pick one."])
        profDD:SetPoint("TOPLEFT", profilesHeader, "BOTTOMLEFT", 0, self.GAP.tabHead)

        -- Re-entrant on purpose. Dialog:_finish clears its own opts before calling onAccept,
        -- so re-showing from inside the handler is safe.
        local promptForName
        promptForName = function(seed)
            local Dialog = ns:GetModule("Dialog")
            if not Dialog then return end
            Dialog:Show({
                title       = L["New Profile"],
                text        = L["Profile name:"],
                hasEditBox  = true,
                editBoxText = seed or "",
                maxLetters  = 32,
                button1     = L["Create"],
                button2     = L["Cancel"],
                onAccept = function(text)
                    local name = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
                    -- Asking again rather than closing on an empty name: the dialog simply
                    -- vanishing with no profile created reads as success.
                    if name == "" then return promptForName(text) end
                    if name ~= currentProfile() and profileExists(name) then
                        Dialog:Show({
                            title    = L["Overwrite profile?"],
                            text     = L["A profile named \"%s\" already exists. Overwrite it with a copy of your current settings?"]:format(name),
                            button1  = L["Overwrite"],
                            button2  = L["Cancel"],
                            onAccept = function() createProfileCopiedFromCurrent(name) end,
                        })
                    else
                        createProfileCopiedFromCurrent(name)
                    end
                end,
            })
        end

        local newProfile = self:CreateButton(content, L["New Profile"], 120,
            function() promptForName() end,
            L["Prompts for a name, then creates a profile holding a copy of your current settings and switches to it. The interface reloads."])
        newProfile:SetSize(120, 22)
        newProfile:SetPoint("LEFT", profDD.button, "RIGHT", 6, 0)
    end,
})
