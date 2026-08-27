-- Locales/enUS.lua
-- Default locale + source-of-truth phrase list for EQ Objective Tracker.
--
-- ns.L["English string"] returns the localized text for the player's client
-- (per GetLocale()), or the English string itself when no translation exists
-- (the metatable __index below). So EVERY wrapped string is safe to use even
-- with zero translations loaded. Untranslated text simply renders in English.
--
-- Translations are bundled directly in the other Locales/*.lua files as
-- L["key"] = "value" lines, NOT fetched through an @localization@ packager
-- token. That token fails the CurseForge build with errorCode 1002 on a project
-- without localization enabled, so it must never be added here.
--
-- Pattern: the English string IS the key (no semantic IDs). Keep keys in sync
-- with the code. If you reword an English string, update it here too or the
-- existing translation orphans (and the new text falls back to English).
--
-- GENERATED FILE: the phrase list is a pure function of the L[...] usages in the
-- code. Do not hand-edit. It is rebuilt by scan.py in the EverythingLocales repo,
-- which also regenerates the translation files from the shared store.


local _, ns = ...

ns.L = setmetatable({}, { __index = function(_, k) return k end })
local L = ns.L

-- Options/TabGeneral.lua
L["General"] = true
L["Lock tracker"] = true
L["Disable drag-to-move and resize."] = true
L["Hide tracker in combat"] = true
L["Hides the tracker while you are in combat and brings it back when you leave."] = true
L["Hide tracker in instances"] = true
L["Raids, dungeons, delves."] = true
L["Hide tracker when world map is open"] = true
L["Hides the tracker while the world map is up, so it does not sit over the map."] = true
L["Hide tracker in Mythic+"] = true
L["Hides the tracker during an active Mythic+ run, then brings it back when the run ends."] = true
L["Auto-track accepted quests"] = true
L["Matches Blizzard's default."] = true
L["Keep focused quest after relog"] = true
L["Restores the waypoint arrow."] = true
L["Hide Questie's quest tracker"] = true
L["Hides Questie's tracker frame while EQ Objective Tracker is running. It only hides the frame, and Questie's own disable path is never called."] = true
L["Options Window Scale"] = true
L["Resizes this EQ Objective Tracker options window only. It does not change the quest tracker or anything shown in the game world. The new size applies when you let go of the slider."] = true
L["Reset position and size"] = true
L["Returns the tracker to its default position and size."] = true
L["Reset all settings"] = true
L["Reset every EQ Objective Tracker setting to defaults? The interface will reload."] = true
L["Reset"] = true
L["Cancel"] = true
L["Restores every setting on every tab to its default and reloads the interface. This also clears the Options Window Scale, which every character shares, and this character's collapsed sections and individually hidden entries."] = true
L["Profiles"] = true
L["Switching profiles reloads the UI. Profiles are shared across characters. Use them to keep different setups such as raid and solo. |cffEBB706New Profile|r prompts for a name and creates it on the spot."] = true
L["Active profile"] = true
L["Switches to another saved settings profile. The interface reloads immediately when you pick one."] = true
L["New Profile"] = true
L["Profile name:"] = true
L["Create"] = true
L["Overwrite profile?"] = true
L["A profile named \"%s\" already exists. Overwrite it with a copy of your current settings?"] = true
L["Overwrite"] = true
L["Prompts for a name, then creates a profile holding a copy of your current settings and switches to it. The interface reloads."] = true

-- Options/TabTracker.lua
L["Zone"] = true
L["Groups entries under the heading they sit under in your quest log."] = true
L["Title"] = true
L["Alphabetical by name."] = true
L["Status"] = true
L["Puts everything that is ready to turn in at the top."] = true
L["Type"] = true
L["Weekly first, then daily, then everything else. Only quests carry a type, so other sections fall back to alphabetical."] = true
L["Level"] = true
L["Lowest quest level first."] = true
L["Distance"] = true
L["Nearest objective first, updated as you move. A quest ready to turn in measures to its turn-in point."] = true
L["Recent"] = true
L["Most recently accepted first."] = true
L["Manual"] = true
L["Your own order. Drag quests up and down in the tracker to set it."] = true
L["Quests the game resets on its own schedule rather than daily or weekly. Special Assignments and some meta quests are what you will see here."] = true
L["Campaign section"] = true
L["Quests section"] = true
L["Profession section"] = true
L["Endeavors section"] = true
L["Achievements section"] = true
L["World Quests section"] = true
L["Top"] = true
L["Bottom"] = true
L["Move %s up"] = true
L["Move %s down"] = true
L["Reorders where this section sits in the tracker. A section only shows while it has something in it, so empty sections won't visibly move."] = true
L["Tracker"] = true
L["On-Screen Tracker"] = true
L["Changes apply immediately to the on-screen tracker."] = true
L["Show only tracked quests"] = true
L["Hides quests that are in your log but not tracked. Matches Blizzard's default tracker."] = true
L["Simplify Mode"] = true
L["Show only the first incomplete objective per quest."] = true
L["Simplify tracked achievements"] = true
L["Show only incomplete criteria for tracked achievements."] = true
L["Sort Order"] = true
L["Drag and drop the quests in the tracker to reorder them however you like."] = true
L["Filters"] = true
L["Show or hide this category of entry in the tracker."] = true
L["Show only quests in current zone"] = true
L["Only show entries with an objective on your current map. Entries whose provider cannot tell are always shown."] = true
L["Reset filters to defaults"] = true
L["Turns every category filter back on and clears the current-zone filter. Nothing else on this tab is changed."] = true
L["Tracker Visibility"] = true
L["Uncheck to hide this section from the tracker even while it has entries."] = true
L["Auto-list current-zone world quests"] = true
L["Lists every WQ in your zone without tracking each."] = true
L["Set a custom World Quests height"] = true
L["By default the World Quests area is capped to a share of the tracker, set by the slider below that. Turn this on to give it a fixed height in pixels instead."] = true
L["World Quests Height"] = true
L["Height in pixels for the world quest area. Only used while Set a custom World Quests height is on."] = true
L["Maximum Height (percent of tracker)"] = true
L["The most of the tracker the world quest area may take. It is capped here first and your quest list takes the space that is left, scrolling for whatever does not fit. Only used while Set a custom World Quests height is off."] = true
L["Section Order"] = true
L["Rearrange the tracker's sections with the arrows below. A section only appears on the tracker while it has something in it, so reordering an empty section won't look like anything changed. World Quests scroll in their own panel and can only sit at the very top or bottom, so use the Top/Bottom control."] = true
L["World Quests Position"] = true
L["Where the World Quests panel sits on the tracker. |cffffffffTop|r puts it above your quests. |cffffffffBottom|r keeps it below your quests, which is the default. World Quests scroll in their own capped panel, which is why they can't be mixed in between the other sections."] = true
L["Options"] = true
L["Quest Title Color By Difficulty"] = true
L["Colors each quest title by how hard it is for your level, the way the quest log does. The Quest Title Color Override on the Appearance tab wins over this while it is set."] = true
L["Show quest level prefix"] = true
L["For example, [60] Title."] = true
L["Show zone label under quest titles"] = true
L["Adds the quest log heading each quest came from as a small line under its title."] = true
L["Show objective progress numbers"] = true
L["For example, 0/4, 1/1, etc."] = true
L["Show progress bars"] = true
L["Draws a filled bar for objectives that report a percentage or a running total, the way the default tracker does, instead of a plain line of text. Applies to quests, World Quests, achievements and scenario objectives."] = true
L["Show event and scenario widgets"] = true
L["Draws the extra bars and status lines the default tracker shows during world events, delves and scenarios, such as an event's progress bar or a delve's tier. This tracker replaces the default one, so without this those are not shown anywhere."] = true
L["Show quest ID"] = true
L["Useful for bug reports."] = true
L["Show the visible / total count on section headers"] = true
L["For example, 3/9. Applies to every section header."] = true
L["Show usable quest item buttons"] = true
L["Puts a button on the tracker row of any quest that carries a usable item, so you can use it without opening your bags."] = true
L["Show Options icon on the tracker"] = true
L["A small cogwheel at the top-right of the tracker that opens the options panel."] = true
L["Show Quest Discovered popups"] = true
L["Boxes for newly discovered / completed quests."] = true
L["Show NEW tag on recently accepted quests"] = true
L["For about an hour after accepting."] = true
L["Split quest click"] = true
L["Click the icon to focus, click the title to open the quest log."] = true
L["Quest Sound"] = true
L["Plays when a quest is ready to turn in."] = true
L["Quest Complete Sound"] = true
L["Which sound plays when a quest becomes ready to turn in."] = true
L["Scenario Bonus Objectives"] = true
L["Show bonus objectives HUD"] = true
L["Shows a small movable checklist of the extra bonus objectives that appear during some scenarios and delves, so you do not miss their rewards. Drag to move, right-click to lock or reset. Off by default."] = true
L["Test"] = true
L["Draws the HUD with two made-up bonus objectives so you can position and size it without being in a scenario or delve. Click again to clear it."] = true
L["HUD Scale"] = true
L["Sizes the bonus objectives HUD."] = true

-- Options/TabAppearance.lua
L["None"] = true
L["Outline"] = true
L["Thick"] = true
L["Mono"] = true
L["Mono Outline"] = true
L["Mono Thick"] = true
L["Plain"] = true
L["Card"] = true
L["Header Bar 1"] = true
L["Header Bar 2"] = true
L["Left"] = true
L["Center"] = true
L["Right"] = true
L["Same as tracker font"] = true
L["Appearance"] = true
L["Font"] = true
L["Fonts registered through LibSharedMedia, so anything from ElvUI or SharedMedia appears here too."] = true
L["Font Size"] = true
L["Base size for objective text. Titles and headers offset from this."] = true
L["Title Size Offset"] = true
L["Sizes quest and achievement titles separately from the objective text. This value is added to the Font Size above: 0 keeps titles the same size as the base font, positive makes them larger, negative smaller."] = true
L["Header Size Offset"] = true
L["Sizes the section headers (Quests, Campaign, and so on) independently of the quest text. Added on top of the Font Size above: the default 4 keeps headers at their current size, lower shrinks them (handy on a low UI scale), higher enlarges them."] = true
L["Font Outline"] = true
L["Outlines keep small text legible over bright terrain."] = true
L["Text Shadow"] = true
L["Draws a soft drop-shadow behind all tracker text so it stays readable over bright or busy backgrounds. Use Shadow Color to tint it and Shadow Size to set how far it's cast."] = true
L["Shadow Color"] = true
L["Shadow color and opacity."] = true
L["Shadow Size"] = true
L["How far the text drop-shadow is cast behind the letters. Higher values give a larger, more pronounced shadow. Lower values keep it tight. Only applies while Text Shadow is on."] = true
L["Scenario"] = true
L["Draws a drop-shadow behind the scenario / delve banner text (the Stage and name lines). This is SEPARATE from the Text Shadow above, which affects only the quest and objective text. The banner is styled on its own."] = true
L["Color and opacity of the banner's drop shadow."] = true
L["How far the scenario banner's drop-shadow is cast. Higher values give a larger, more pronounced shadow. Lower values keep it tight. Only applies while the Scenario Text Shadow above is on."] = true
L["Banner Alignment"] = true
L["Positions the scenario / delve banner within the tracker. Left lines it up with the quest text, Center keeps it centered (the default), and Right pushes it to the tracker's right edge."] = true
L["Banner Text Size"] = true
L["Grows or shrinks the scenario / delve banner's Stage and name text. 0 is the default size. The banner artwork is a fixed size, so large values may overflow it."] = true
L["Criteria Text Size"] = true
L["Sizes the scenario / delve objective (criteria) lines shown under the banner, separately from the Banner Text Size above. Raise it if the criteria text looks small next to your quest and World Quest text."] = true
L["Scroll Bar"] = true
L["Hide scroll bar"] = true
L["Removes the tracker's scroll bar entirely and scrolls with the mouse wheel instead. Everything else in this group styles that bar, so it all stops applying while this is on."] = true
L["Scroll Bar Background"] = true
L["Draws a track behind the scroll bar so it stays visible over bright terrain."] = true
L["Scroll Bar Color"] = true
L["Color and opacity of the scroll bar track."] = true
L["Solid color thumb"] = true
L["Replaces the tracker scroll bar's textured thumb (the draggable block) with a flat single-color block. Use the Thumb Color and Thumb Width controls to style it. Off restores the stock Blizzard bar."] = true
L["Thumb Color"] = true
L["Color and opacity of the draggable block. Only used while Solid color thumb is on."] = true
L["Thumb Width"] = true
L["How wide the draggable block is. Only used while Solid color thumb is on."] = true
L["Hide scroll bar arrows"] = true
L["Hides the up and down arrow buttons at the ends of the tracker scroll bar. The bar still scrolls by dragging the thumb or using the mouse wheel."] = true
L["Background"] = true
L["Fills the tracker behind the text. Useful over bright terrain."] = true
L["Background Color"] = true
L["Background color and opacity."] = true
L["Border"] = true
L["Draws a border around the tracker."] = true
L["Border Color"] = true
L["Border color and opacity."] = true
L["Border Thickness"] = true
L["Border thickness in pixels."] = true
L["Header Bar"] = true
L["Show header bars"] = true
L["Draws a colored gradient bar behind each section header (Quests, Campaign, World Quests, and so on), for a look closer to the default Blizzard tracker. Off by default."] = true
L["Bar Color"] = true
L["Brightest end of the bar gradient. The other end is the same color darkened."] = true
L["Bar Style"] = true
L["Header Bar 1 is a horizontal gradient (bright on the left, dark on the right). Header Bar 2 is a vertical gradient (bright at the top, dark at the bottom). Bar Color, Bar Height, and Soft edges all apply to whichever style you pick."] = true
L["Soft edges"] = true
L["Feathers the top, left, and right edges of the header bar so it blends into the UI instead of sitting in a hard box. The gradient color is unchanged. Only applies while Header bars is on. Off by default."] = true
L["Bar Height"] = true
L["How tall the section-header bar is. The bar is centered on the header row, so larger values fill more of it."] = true
L["Edge Softness"] = true
L["How soft the header bar's feathered edges are when Soft edges is on. Higher is softer, lower tightens toward a hard edge."] = true
L["Colors & Dimensions"] = true
L["Reset to Defaults"] = true
L["Reset every setting on this tab to its defaults? The interface will reload."] = true
L["Restores every control on this tab, including the zone bar block, to its default. Other tabs are left alone."] = true
L["Quest Title Color Override"] = true
L["When cleared, falls back to difficulty coloring or default yellow."] = true
L["Use class color for titles"] = true
L["Colors quest, achievement, and endeavor titles with the class color of the character you are currently logged in on. Overrides the color above while it is on. Off by default."] = true
L["Use title color for completed quests"] = true
L["Instead of green."] = true
L["Section Header Color"] = true
L["Color of the Quests, Campaign and World Quests headings."] = true
L["Use class color for headers"] = true
L["Colors the section headers (Quests, Campaign, and so on) with the class color of the character you are currently logged in on. Overrides the color above while it is on. Off by default."] = true
L["Divider Line Color"] = true
L["Sets the color of the thin line under each section header. Defaults to the original gold."] = true
L["Tracker Scale"] = true
L["Scales the whole tracker. Takes effect immediately out of combat."] = true
L["Block Spacing"] = true
L["Vertical gap between each entry and between sections."] = true
L["Line Spacing"] = true
L["Adds vertical space between a quest's objective lines, across the whole tracker. 0 keeps the default spacing."] = true
L["Header Spacing"] = true
L["Adds or removes space around section headers and beneath each quest's title. 0 keeps the default spacing."] = true
L["Quest Rows"] = true
L["Row Layout"] = true
L["How each quest is drawn in the tracker. |cffffffffPlain|r is the default look - text straight on the tracker background. |cffffffffCard|r gives every quest its own panel with a background and border, which makes long lists easier to read apart."] = true
L["Fill color behind each quest card. Only used while Row Layout is set to Card."] = true
L["Outline color around each quest card. Only used while Row Layout is set to Card."] = true
L["How thick the card outline is, in pixels. 0 hides the outline and leaves just the fill."] = true
L["Card Padding"] = true
L["Breathing room between a card's edge and the text inside it. Larger values make taller cards."] = true
L["Tint cards by quest type"] = true
L["Gives campaign, legendary, dungeon and raid entries their own card color. Anything else uses the plain background color above."] = true
L["Campaign"] = true
L["Card color for campaign entries. Needs Tint cards by quest type switched on."] = true
L["Legendary"] = true
L["Card color for legendary entries. Needs Tint cards by quest type switched on."] = true
L["Dungeon"] = true
L["Card color for dungeon entries. Needs Tint cards by quest type switched on."] = true
L["Raid"] = true
L["Card color for raid entries. Needs Tint cards by quest type switched on."] = true
L["Zone Progress Bar"] = true
L["Show zone progress bar"] = true
L["Approximate questline progress."] = true
L["Float as a movable bar"] = true
L["Drag to move, right-click to lock or reset. Unticked, the bar becomes an ordinary tracker section instead and only Bar Texture and Bar Color still apply to it."] = true
L["Fills the floating bar behind its text."] = true
L["Background color and opacity for the floating bar. While this is unset the bar uses a plain black fill that fades slightly once locked."] = true
L["Draws a border around the floating bar."] = true
L["Border color and opacity for the floating bar."] = true
L["Zone Bar Scale"] = true
L["Size of the floating bar. The docked section follows the tracker's own scale instead."] = true
L["Font for the floating bar's zone name, count and percentage. The docked section uses the tracker font."] = true
L["Bar Texture"] = true
L["Sets the fill texture of the zone progress bar. Textures added by other media addons (such as SharedMedia, ElvUI, or Details) appear here too."] = true
L["Fill color and opacity of the bar itself."] = true
L["Header Color"] = true
L["Color of the zone name on the floating bar. The docked section uses the section header color."] = true
L["Count Color"] = true
L["Color of the completed-of-total count on the floating bar."] = true

-- Options/TabAbout.lua
L["Open this window"] = true
L["Lock moving and resizing"] = true
L["Unlock moving and resizing"] = true
L["Restore the default position and size"] = true
L["Show or hide the tracker"] = true
L["Bring back every entry you have hidden"] = true
L["Import your Everything Quests settings"] = true
L["Print provider status to chat"] = true
L["Toggle entry validation warnings"] = true
L["Special thanks to %s for the many features, fixes, and reports that keep shaping EQ Objective Tracker."] = true
L["Special thanks to %s for the many hours spent translating EQ Objective Tracker into French."] = true
L["Special thanks to %s for the many hours spent translating EQ Objective Tracker into Russian."] = true
L["Special thanks to %s for the many hours spent translating EQ Objective Tracker into Korean."] = true
L["Special thanks to %s for the many hours spent translating EQ Objective Tracker into Simplified Chinese."] = true
L["Special thanks to %s for the many hours spent translating EQ Objective Tracker into Traditional Chinese."] = true
L["Special thanks to %s for the many hours spent translating EQ Objective Tracker into German."] = true
L["About"] = true
L["Version %s"] = true
L["by Wheelbarrel00"] = true
L["A standalone replacement for the default objective tracker. It does not require Everything Quests, and never will."] = true
L["Join our Discord"] = true
L["CurseForge"] = true
L["GitHub"] = true
L["Report a Bug"] = true
L["Commands"] = true
L["Content providers"] = true
L["Providers are gated at load time by which TOC file your game flavor used. A provider that is not listed was never loaded."] = true
L["Thanks"] = true
L["Changelog"] = true
L["Older versions are on CurseForge"] = true

-- Options/Frame.lua
L["Plays the currently selected sound."] = true
L["Clear"] = true
L["Join our Discord!"] = true
L["Click to copy the invite link."] = true

-- Core/Init.lua
L["Copy the link below (it's pre-selected \226\128\148 just press Ctrl+C):"] = true
L["Close"] = true
L["Join the community for help, feedback, and updates.\nCopy the invite below (it's pre-selected \226\128\148 just press Ctrl+C):"] = true

-- Core/Migrate.lua
L["imported %d settings from Everything Quests."] = true

-- Data/Filter.lua
L["World Quests"] = true
L["Bonus Objectives"] = true
L["Campaign quests"] = true
L["Daily quests"] = true
L["Weekly quests"] = true
L["Scheduled quests"] = true
L["Normal quests"] = true

-- Data/Providers/Achievements.lua
L["Left-click to open, right-click to untrack."] = true

-- Data/Providers/Professions.lua
L["%s (Recraft)"] = true
L["Left-click to open the recipe, right-click to untrack."] = true

-- Data/Providers/Scenarios.lua
L["Ritual Site"] = true
L["Delves"] = true
L["Mythic+"] = true
L["Warfront"] = true
L["Proving Grounds"] = true
L["Follower Dungeon"] = true
L["Void Incursion"] = true
L["Battleground"] = true
L["Arena"] = true
L["Stage %d of %d"] = true

-- Data/Providers/WorldQuests.lua
L["Ready to turn in"] = true

-- Data/ScenarioBonus.lua
L["Delve Bonus Loot"] = true
L["Nemesis Strongbox: %d/%d packs"] = true
L["Sanctified Banner: Grand Spoils earned"] = true
L["Sanctified Banner: bonus Spoils secured"] = true
L["Sanctified Banner: kill the Voidfused Rager"] = true
L["Sanctified Banner: find it for bonus loot"] = true
L["Deaths:"] = true
L["Lives:"] = true

-- Data/Widgets.lua
L["Tier %d"] = true

-- UI/AutoQuestPopup.lua
L["Click to view quest"] = true
L["Quest Complete!"] = true
L["Quest Discovered!"] = true

-- UI/Commands.lua
L["tracker locked."] = true
L["tracker unlocked."] = true
L["position and size reset."] = true
L["nothing is hidden."] = true
L["%d hidden entries restored."] = true
L["no Everything Quests configuration found to import."] = true
L["Import from Everything Quests"] = true
L["Reset this profile to defaults and replace it with your Everything Quests tracker settings?\n\nThis cannot be undone. Make a new profile first if you want to keep the current one."] = true
L["Import"] = true
L["commands:"] = true

-- UI/Dialog.lua
L["OK"] = true

-- UI/QuestieCoexist.lua
L["Questie's own quest tracker is on screen alongside this one.\n\nHide Questie's tracker? You can change this later on the General tab. This only hides the frame, and leaves Questie's settings and tracked quests alone."] = true
L["Hide it"] = true
L["Keep both"] = true

-- UI/RewardTooltip.lua
L["Equip \226\128\148 empty slot"] = true
L["Equipped: ilvl %d"] = true
L["+%d ilvl upgrade"] = true
L["%d ilvl lower"] = true
L["Same item level"] = true
L["ilvl %d"] = true
L["%d XP"] = true
L["Choose one:"] = true
L["Time Left: "] = true
L["Click the icon to focus this quest, or again to clear it."] = true
L["Click the title to open the quest log."] = true

-- UI/Row.lua
L["Find Group"] = true
L["Open the Premade Group Finder for this quest."] = true

-- UI/RowMenu.lua
L["You cannot abandon a quest while in combat."] = true
L["This game version cannot abandon quests from the tracker."] = true
L["That quest is no longer in your quest log."] = true
L["Pin to tracker"] = true
L["Unpin from tracker"] = true
L["Track Quest"] = true
L["Untrack Quest"] = true
L["Focus"] = true
L["Unfocus"] = true
L["Super-track (follow arrow)"] = true
L["Open in Map & Quest Log"] = true
L["Pop Out Quest Details"] = true
L["Search on Wowhead"] = true
L["Abandon Quest"] = true

-- UI/Scenario.lua
L["Final Stage"] = true
L["Stage %d"] = true

-- UI/ScenarioBonusHUD.lua
L["Unlock (allow moving)"] = true
L["Lock position"] = true
L["Reset position"] = true

-- UI/Sections.lua
L["Zone Progress"] = true
L["Quests"] = true
L["Achievements"] = true
L["Endeavors"] = true
L["Profession"] = true

-- UI/Tracker.lua
L["Tracker locked"] = true
L["Use /eqot unlock to move it."] = true
L["Drag to move, corner grip to resize."] = true
L["/eqot for options"] = true
L["Open the options panel"] = true
L["a visibility rule is keeping the tracker hidden - see /eqot, General."] = true

-- Convert the `true` sentinels to their key (the self-keyed English default).
for k, v in pairs(L) do if v == true then L[k] = k end end
