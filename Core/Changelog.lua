local _, ns = ...

-- The About tab renders this verbatim. Deliberately NOT wrapped in L[...]: the body is
-- long-form English prose no translator is going to be offered, and a translated heading
-- over an English paragraph reads worse than leaving the whole block alone. EQ does the
-- same in its own Core/Changelog.lua.
--
-- GENERATED FILE: produced by docs/_gen_changelog.py from CHANGELOG.md. Do not hand-edit -
-- edit CHANGELOG.md and re-run the generator.
ns.Changelog = {
    {
        version = "2.11.0", date = "2026-11-05",
        sections = {
            { head = "New Features", items = {
                "To-Do Mode's card on the Tracker tab has a new Show section names box. Untick it and the Quests header, and the Campaign header on retail, keep their counts and the collapse sign without their names, so the counts sit on their own. Zone headers keep theirs. To make the names smaller instead, the Header Size Offset button beside the box opens the Appearance tab at that slider. The counts follow it, and Count Size Offset sizes them back. The box starts ticked, so nothing changes until you untick it. Requested by Tjuv.",
            } },
        },
    },
    {
        version = "2.10.3", date = "2026-11-03",
        sections = {
            { head = "Bug Fixes", items = {
                "With Simplify tracked achievements on, an achievement with more than twelve criteria and its first twelve done showed a single finished criterion instead of the ones still left to do. Finished criteria that Simplify hides no longer use up the twelve lines an achievement shows, so up to twelve unfinished ones now appear, and Simplify Mode, which did the same, now shows the first unfinished one. Reported by Rubio9.",
            } },
        },
    },
    {
        version = "2.10.2", date = "2026-11-01",
        sections = {
            { head = "Bug Fixes", items = {
                "Classic Era and TBC: with the quest log scrolled, its tracked checks landed on the wrong rows and Shift-clicking a quest could toggle a different one. Checks now stay on their own quests, and Shift-click toggles the quest you clicked.",
                "Classic Era and TBC: Shift-clicking a quest in the quest log to link it with a chat box open also changed whether it was tracked. It now only links.",
                "A world quest you tracked yourself could be lost at login if the game had auto-watched it first, such as when you log in standing in its area. It now stays tracked.",
                "A quest item button now updates its cooldown sweep and charges right after you use the item, rather than at the tracker's next update.",
                "Under the Distance sort, a quest accepted while standing still now takes its place right away rather than sitting at the bottom until you move.",
                "A tracked recipe's currency reagent count now updates when the currency changes.",
                "A tracked recipe with a reagent the game could not answer for could stop the whole tracker from drawing. The tracker now keeps drawing, though that reagent's count may read low.",
            } },
        },
    },
    {
        version = "2.10.1", date = "2026-11-01",
        sections = {
            { head = "Bug Fixes", items = {
                "The first quest you accept after logging in with an empty quest log, such as a new character's first quest, now shows its NEW tag. It was being saved as a quest you already had, so it never got one.",
                "The first click on the About tab after logging in could end in a \"script ran too long\" error on Classic Era. Its changelog now lists the 30 newest versions instead of all of them, which makes that click far lighter, and the rest are on CurseForge.",
            } },
        },
    },
    {
        version = "2.10.0", date = "2026-10-30",
        sections = {
            { head = "New Features", items = {
                "Every sort order except Zone and Manual can now be reversed. On the sort button's menu (turn on Show the sort button on the tracker), pick the order already in use again to reverse it, and once more to turn it back: Level then runs from highest to lowest, Title from Z to A, Distance from farthest to nearest, and so on. Quests that tie on the order stay in alphabetical order, quests with no known distance stay at the bottom, and the sort button's tooltip says when the order is reversed. Picking another order, on the sort button or on the Tracker tab's Sort Order list, or hiding the sort button turns the reverse off. Requested by Hermonii.",
            } },
            { head = "Bug Fixes", items = {
                "During Abundance, the Abundance Bag bar now shows under the event's objective, as it does in Blizzard's tracker. Blizzard's scenario tracker draws two groups of event widgets under a scenario's objectives, and EQ Objective Tracker never drew either, so anything placed there was missing. Other events and delves that use them now show them too. Reported by hohoook.",
                "With Questie installed and Hide Questie's quest tracker on, killing quest mobs in a fight no longer causes a blocked action error (\"Interface action failed because of an AddOn\", which error reports named as Questie's). EQ Objective Tracker now waits for the fight to end before hiding Questie's tracker, and unticking the box during a fight brings Questie's tracker back when the fight ends. Unticking it now brings back only a tracker EQ Objective Tracker hid, so a Questie tracker that Questie had already hidden itself, with no quests tracked or by its own option to hide in instances, stays hidden.",
                "The zone progress bar now shows in Eversong Woods outside Silvermoon City on game clients that are not in English. It found that zone by its English name, so on every other language it drew nothing there.",
                "In a scenario or delve, an objective whose text only just wraps onto a second line no longer overlaps the objectives around it. Its height was worked out for a slightly wider line than the one drawn.",
                "/eqot status no longer prints the word twice in its scenario spells reading (\"spells spells secret\").",
                "On Russian game clients, the font lists now offer the 25 bundled fonts that have Russian letters, plus WoW Default (Friz Quadrata) and WoW Arial Narrow. Until now none of the bundled fonts was offered there, so the tracker's default font, GothamXNarrow Black, could not load, and the tracker quietly used Friz Quadrata instead. If you play on a Russian client and never picked a font, your tracker now shows GothamXNarrow Black, the default font it was always meant to have. Fonts without Russian letters stay out of the lists there, so no font can turn Russian text into blanks. Korean and Chinese clients are unchanged: none of the bundled fonts has Korean or Chinese characters, so the game's own fonts for those languages stay in use.",
            } },
            { head = "Improvements", items = {
                "/eqot status now names the two groups of event widgets under a scenario's objectives on its widgets line, lists a widget type it cannot read instead of leaving it out, and says when the sort order is reversed.",
                "Updated for World of Warcraft patch 12.1.7.",
            } },
        },
    },
    {
        version = "2.9.0", date = "2026-10-24",
        sections = {
            { head = "New Features", items = {
                "To-Do Mode, on its own card on the Tracker tab, turns the Quests header, and the Campaign header on retail, into four counts: your unfinished quests in the zone you are in, the ones ready to turn in there, every quest there and every quest you have. Click a count and the section shows exactly those quests, with the count you picked underlined. It starts on your unfinished quests in the zone, each character remembers the count it picked, and a header stays up while a count you show is above 0, so you can always switch back. While it is on it decides which quests are in your zone, so Show only quests in current zone is dimmed and keeps your own setting for when you turn it off. The quest type filters, Show only tracked quests, pinned quests and every other section stay as they are, and the counts follow them. Quest popup boxes and pinned quests show whichever count you pick, as they always have. The card can hide any of the four counts, give each one its own color with a Class button, and size them. Off by default, on every version of the game. Requested by Tjuv.",
                "Two new count colors on the Appearance tab's Quest Colors card, Count Color: Half Done and Count Color: Mostly Done, color a count like 5/10 from half done and one like 7/10 from seven tenths done. Both start unset, so no count changes color until you pick one, and Mostly Done takes Half Done's color while it is unset. Requested by Tjuv.",
            } },
            { head = "Improvements", items = {
                "/eqot status now has a To-Do Mode line naming the count you picked and the four counts of each quest section.",
            } },
        },
    },
    {
        version = "2.8.1", date = "2026-10-21",
        sections = {
            { head = "Bug Fixes", items = {
                "On Classic Era and TBC Anniversary, a quest's reward tooltip now lists that quest's own choice of rewards, and the item level beside each reward is that item's own. On Era both came from whichever quest was selected in your quest log, the same problem the XP line once had, so they are now read the way the XP line is and appear a moment after you log in.",
                "On Classic Era and TBC Anniversary, Open in Map & Quest Log in a quest's right-click menu no longer closes a quest log that is already open. It shows that quest in the log instead. With Split quest click on, clicking another quest's title while the log is open now does the same, and clicking the title of the quest the log is already showing still closes it, as on retail. The log cannot switch to a quest whose zone is collapsed in it, so for such a quest the title closes an open log, Open in Map & Quest Log leaves it as it is, and either one opens a closed log on the quest it showed last.",
            } },
            { head = "Improvements", items = {
                "On Classic Era and TBC Anniversary, /eqot status now has a quest timers line, as retail has had since 2.6.0. It says how many quest timers the game reported, how many of them matched an entry in your quest log and which quests are counting down, so a timer missing from the tracker can be traced from one /eqot status report.",
                "The Korean wording is updated throughout the options and the tracker. Translated by labrie75.",
            } },
            { head = "Coming Next", items = {
                "To-Do Mode is coming in a later update: a way to turn the tracker into a short list of the quests you still have to do in the zone you are in. Requested by Tjuv.",
            } },
        },
    },
    {
        version = "2.8.0", date = "2026-10-20",
        sections = {
            { head = "Bug Fixes", items = {
                "Two tooltips now say what their option really does. Split quest click's tooltip also says that a second click on the title closes the quest log, and that a finished quest you can hand in from the tracker is handed in from its title. The Appearance tab's Reset to Defaults tooltip no longer claims to reset everything: it names what it leaves alone, which is the switches for zone headers, the Dungeons header, section tabs, the zone progress bar and the bonus objectives HUD, along with Zone Order, Keep Dungeons at the bottom, Float as a movable bar and where you dragged the zone bar and the HUD.",
            } },
            { head = "New Features", items = {
                "Background on Mouseover, on the Appearance tab's Tracker card, gives the tracker a background while the mouse is over its quests or headers, with a slider for how solid it is. It uses Background Color's color and works with Background off too, so the background shows only while you hover. It starts at Off, so nothing changes until you move it. Requested by silhouetteone.",
                "On retail and WoW Forever, with Split quest click on, clicking a quest's title again now closes the map when the map is showing that quest. Clicking another quest's title still moves the map to that quest, and during combat the map stays open. Classic Era and TBC Anniversary already closed the quest log on a second click. Requested by silhouetteone.",
                "A Section Tabs card on the Appearance tab styles the section tabs: the line under the tab you are on, gold until you change it, the line under the other tabs, how thick both lines are, the fill and name color of the tab you are on and of the others, the size of the names and the height of the tabs. Every color has its own opacity and the Class button. The card also has Show section tabs, the same switch as on the Tracker tab, and the preview shows two sample tabs while it is on. The tab names now use the Font and Font Outline from the Text card, at the same size as before. Retail only, where section tabs are offered.",
            } },
            { head = "Improvements", items = {
                "With Full opacity on mouseover, the tracker now starts fading back half a second after the mouse leaves it, instead of a full second. Background on Mouseover waits the same half second.",
            } },
        },
    },
    {
        version = "2.7.0", date = "2026-10-18",
        sections = {
            { head = "Bug Fixes", items = {
                "The check mark on a finished objective now always sits beside its own line. With a large Line Spacing every check was drawn above its line, and now and then one was at 0 too. A finished objective long enough to wrap now starts its second line under its text rather than under the check.",
                "The bonus objectives HUD's Nemesis Strongbox line now reads the game's own count, the one the delve's tier row shows, so the two always agree. It counted fewer kills when the HUD was switched on partway through a delve, and it now shows from the moment you enter a Tier 4 or higher delve.",
                "If another addon opened the color picker while one of this addon's colors was open in it, closing the options window shut that addon's picker and set this addon's color back. Another addon's picker is now left alone.",
                "In a tracker narrower than about 280 pixels, the scenario and delve banner no longer sticks out past the tracker. It now shrinks to fit, text and all, and the tier row and objectives below it move up to meet it. Reported by Tyrial.",
                "A Quest Complete! or Quest Discovered! box's text no longer runs under its icon in a narrow tracker. The text now has a column of its own beside the icon, centered there and wrapped to fit. Reported by Tyrial.",
                "With Show objective progress numbers off, a finished objective that is only a count, such as a progress bar with no text of its own, now keeps its count beside the check mark rather than showing the check mark alone. Simplify Mode's last line, once everything is finished, does the same.",
            } },
            { head = "New Features", items = {
                "Scroll Bar Texture on the Appearance tab's Scroll Bar card draws the scroll bar's track in any bar texture, the same list the progress bars offer, tinted by Scroll Bar Color. It starts at None, the flat track it has always been, so nothing changes until you pick one. Requested by Tyrial.",
                "Every color on the Appearance tab but three now has a Class button beside its swatch. Turned on, that color follows the class color of the character you are logged in on, at the opacity picked for it, and turned off, a color you had picked comes back. Section Header Color, Zone Header Color and Custom Title Color have no button, since they keep the class color options they already had.",
                "Show the stage banner, on the Appearance tab's Scenario card, can hide the scenario and delve banner. The stage then shows as one plain line under the event title, with the stage's name after it unless that name repeats the title above, as a delve's does. It is on by default, so nothing changes until you untick it. Requested by Tyrial.",
            } },
            { head = "Improvements", items = {
                "Bar Style and Soft edges on the Section Headers card now shape the zone header bars too, the Dungeons header included, so every header bar can share one look. Each kind of bar keeps its own switch and color, and a zone bar still fills its own header.",
                "The settings search now also finds the colors that sit at the end of a checkbox's row, such as Shadow Color beside Text Shadow and Thumb Color beside Solid color thumb, and lists each one right after its row.",
            } },
        },
    },
    {
        version = "2.6.0", date = "2026-10-17",
        sections = {
            { head = "Bug Fixes", items = {
                "On retail and WoW Forever, dragging the opacity bar in a color picker now changes the color as you drag. Before, the new opacity applied only when you pressed Okay. Cancel still puts back the color you started with, and Classic Era and TBC Anniversary already worked this way.",
                "The settings window's scroll bar no longer jumps to the far end when you press its thumb. The thumb now stays under the cursor from wherever you grab it, so dragging moves the list the way you drag.",
                "On WoW Forever, Show only quests in current zone no longer hides the quests listed under the zone you are in, and Current zone first brings that zone's header to the top. A quest whose quest log heading names your zone now counts as in it, as on Classic Era and TBC Anniversary, as well as a quest whose map marker is there.",
            } },
            { head = "New Features", items = {
                "Timed quests count down on retail and WoW Forever, on the quest's row and in its tooltip, as they already did on Classic Era and TBC Anniversary. The game's own tracker drew that timer, so it went missing along with that tracker. The last minute counts down in seconds, and /eqot timer test puts a two-minute sample on one of your quests so you can see it without finding a timed quest. Reported by frkstram.",
                "Two new boxes under Show event and scenario widgets on the Tracker tab, both on by default, put a delve's lives and its nemesis groups on the tier's row, each with the game's own icon and tooltip. The lives turn orange at 2 and red at 1, and the nemesis count shows how many groups of the nemesis's minions have been killed, as the bonus objectives HUD counts them, with a check mark once all of them are dead. Both start at Tier 4, on retail. Requested by Tyrial.",
                "A search field at the top of the settings window's sidebar finds any setting as you type. Each match shows where it lives, such as Tracker > Quest Row Details, and clicking it, or pressing Enter for the first one, opens that tab, scrolls to the setting and flashes it. It searches setting names, card titles and tab names as your game's language shows them.",
            } },
            { head = "Improvements", items = {
                "The Tracker tab's long Options card is now five cards, so each option is easier to find: Quest Row Details for what each quest's row shows, Headers and Buttons, Clicking and Focus, Scenarios and Popups, and Sounds. Every option keeps its setting, the cards above them are unchanged, and the new card titles are translated in every language.",
                "With section tabs on, a Quest Discovered or Quest Complete box now shows on every tab, not only on the tab holding its section. On another tab the section's header is drawn in its usual place with just the box under it, its count reading the boxes alone. /eqot popup test draws a sample Quest Discovered box, which does nothing when clicked, so you can see where the boxes land.",
                "The boxes that hand you a link to copy, from Search on Wowhead, the Discord button and the About tab's links, can no longer be typed in, so a stray key cannot change the link before you press Ctrl+C.",
                "Show section tabs is no longer offered on WoW Forever, where only the quests section ever fills, as on Classic Era and TBC Anniversary. A Forever profile that had tabs on shows one list again, and the tab each section was given stays saved.",
            } },
        },
    },
    {
        version = "2.5.0", date = "2026-10-16",
        sections = {
            { head = "Bug Fixes", items = {
                "Pop Out Quest Details on a quest's right-click menu opened an empty window on WoW Forever. It now opens the quest's details through the game's own quest log code. Reported by DugFromTheEarth.",
                "On Classic Era and TBC Anniversary with no color picker addon installed, the opacity slider in the color picker ran backwards for this addon's colors, so moving it toward opaque made a color more see-through. It now runs the same way as the game's own.",
                "A font that another addon registered but whose file is missing no longer breaks the font list in the options window.",
            } },
            { head = "New Features", items = {
                "A filter button at the top-left of the tracker, beside the sort button. A click opens a list with Show only quests in current zone at the top, then the quest types from the Filters card, then Reset filters to defaults, and the list stays open while you check boxes, so several filters can be changed in one go. The funnel turns gold while any filter in the list is set to hide quests. Show the filter button on the tracker on the Tracker tab turns it on, and it is off by default. Requested by Tyrial and bramer26.",
                "Section tabs. Show section tabs on the Tracker tab's Section Order card splits the tracker into up to three tabs: the number beside each section, World Quests included, picks its tab, and once two tabs hold a section a strip under the top of the tracker switches between them. Each tab is named after its sections, and hovering one lists them in full. The scenario panel shows on every tab, a tab opens at its top, and the tab on screen is remembered for each character. Once a quest item or scenario spell button has been on the tracker since the last login or reload, a tab picked during a fight opens when the fight ends, since those buttons cannot move in combat. A section the tracker does not draw, such as a hidden one or a floating zone bar, has its number dimmed and keeps its tab for when it comes back. It is off by default, and appears on retail and WoW Forever, since Classic Era and TBC Anniversary have one quest section. Requested by bramer26.",
                "Scroll Bar Width on the Appearance tab's Scroll Bar card sets how wide the tracker's scroll bar is, from 4 to 16. At 16, the default, it is the game's own bar. Narrower, it becomes a flat strip in the Thumb Color with no arrows, and the quest text gets the room it frees. Requested by Tyrial.",
            } },
            { head = "Improvements", items = {
                "Moving the tracker is easier to find. While the tracker is unlocked, either with the options window open or after unlocking it, the strip along its top turns gold and reads \"Drag to move, corner grip to resize.\" beside a check button that locks it again, and a gold outline shows the tracker's edges. Right-clicking that strip or the cogwheel opens Unlock (allow moving) or Lock position, Reset position and size, and Open the options panel. The strip's hover highlight now shows only while the tracker is unlocked. Reported by boondox3906.",
                "The zone progress bar in Eversong Woods counts the new Into the Labyrinth questline.",
                "Every language stays fully translated. German, French, Russian, Korean, Simplified Chinese and Traditional Chinese cover every new option, along with a few small wording fixes.",
            } },
        },
    },
    {
        version = "2.4.0", date = "2026-10-11",
        sections = {
            { head = "New Features", items = {
                "Mythic+ runs show the key's own panel at the top of the tracker, the way the default tracker does: the keystone level, the affix icons with each affix's name and description when you hover one, the time left, which turns red when time is up, with a bar that runs down under it, and the deaths, with the time they cost when you hover the count. It marks a key that started depleted, and once time runs out it marks whether the run still gets its loot. Beyond what the default tracker shows, the time left for +3 and +2 is listed under the bar, each turning gray once it has passed, and the bar is marked where each one runs out, worked out the usual way at 60 and 80 percent of the time limit. The panel takes the stage banner's place during a key, with the boss and Enemy Forces lines under it as before. Until now this tracker showed only the stage banner and those lines, because the timer, the affixes and the deaths are drawn by the default tracker, which this one replaces. It is on by default, and Show the Mythic+ timer on the Tracker tab turns it off for anyone using a separate timer addon. This could not be tested in a real key before release, so please report anything that looks wrong, ideally with what /eqot mplus prints during the key. Reported by Hermonii.",
                "/eqot mplus prints what the tracker read for the current key. /eqot mplus test draws a sample key in the tracker while no scenario is running, so the panel can be seen without running a key, and /eqot mplus late draws a depleted one starting fifteen seconds before time runs out. The same command again clears it, and a real scenario starting ends it. /eqot status carries the same two lines.",
            } },
            { head = "Improvements", items = {
                "Every language stays fully translated. German, French, Russian, Korean, Simplified Chinese and Traditional Chinese cover the new Show the Mythic+ timer option.",
            } },
        },
    },
    {
        version = "2.3.0", date = "2026-10-11",
        sections = {
            { head = "New Features", items = {
                "A sort button at the top-left of the tracker. A click opens a list of the sort orders with the current one named at the top, and picking one switches the tracker to it, so changing between, say, Level and Distance takes two clicks. It changes the same Sort Order as the Tracker tab. It is off by default: turn on Show the sort button on the tracker, on the Tracker tab under the cogwheel's switch. Requested by Andreon.",
                "Group dungeon quests under one header, on the Appearance tab's Zone Headers card. Every quest the game marks as a dungeon quest, heroic dungeon quests included, moves into a Dungeons header in each of the Quests and Campaign sections, styled by the zone header controls on the same card. It works with zone headers on or off: with them off, every other quest stays as it is and Dungeons comes last, and with them on, dungeon quests leave their zones for it and, under Current zone first, it comes to the top while one of its quests is in your zone. Keep Dungeons at the bottom, just under it, keeps the header last even then. A quest under the Dungeons header keeps its zone label, even with zone headers on, so you can still tell which dungeon it is for, and Show zone label under quest titles, on the Tracker tab, stays lit while the Dungeons header is on. With zone headers off, the Dungeons header scrolls with the list rather than staying in view under its section header. Both are off by default, and Reset to Defaults leaves both as they are, as it does Show zone headers. The preview beside the settings has a sample dungeon quest to show it. Requested by Andreon.",
                "Finished Quest Color, on the Appearance tab's Quest Colors card, colors the title of a quest whose objectives are all done. It starts unset, so finished quests stay green, or keep the title color while Use title color for completed quests gives one, until you pick a color. Once picked it applies in every Quest Title Color mode, and Clear puts the old color back. Finished objectives keep their own color, Finished Objective Color.",
                "NEW Tag Color, on the same card, colors the NEW tag on quests accepted in the last hour. It starts as the blue the tag has always had, and Reset to Defaults puts that blue back.",
            } },
            { head = "Improvements", items = {
                "Heroic dungeon quests, such as TBC Anniversary's heroic dailies, count as dungeon quests, so Tint cards by quest type gives them the Dungeon color too.",
                "/eqot status reports the Dungeons header and Keep Dungeons at the bottom on its zone headers line, counting only the zones that draw a header, and Finished Quest Color and NEW Tag Color on its title color line.",
                "Every language stays fully translated. German, French, Russian, Korean, Simplified Chinese and Traditional Chinese cover every new option in this release, including the sort button, the Dungeons header and the two new colors.",
            } },
        },
    },
    {
        version = "2.2.0", date = "2026-10-05",
        sections = {
            { head = "New Features", items = {
                "Zone headers, on a new Zone Headers card on the Appearance tab. Show zone headers groups the quests in the Quests and Campaign sections under the quest log heading each one sits under, which is its zone for most quests. Each zone gets a header with a count, the way a section does, and collapses on its own, and expanding one scrolls it into view. Off by default. On retail the quest log heads campaign quests with the campaign's name, so the Campaign section shows a header for each campaign rather than one for each zone. On Classic Era and TBC Anniversary it groups the Quests section.",
                "Zone Order, just under it, puts the zones with a quest on the map you are in first and the rest in the order your quest log lists them, or lists every zone in alphabetical order. Quests inside a zone still follow Sort Order, and with the manual sort order a quest is dragged within its own zone.",
                "The zone headers have a look of their own on the same card: a size added on top of the Font Size, a color or your class color, an optional bar and divider line with colors of their own, and how far the quests under each header are moved in. The preview beside the settings shows two sample zones while zone headers are on. Reset to Defaults puts the look back without turning zone headers off or changing Zone Order.",
                "With Keep section headers in view while scrolling on, the header of the zone you are scrolled into stays in view too, just under its section's header.",
                "Two new options on the Tracker tab, on retail and WoW Forever. Click a focused quest to unfocus it, off by default, makes a click on the quest you are following unfocus it, or a click on its icon while Split quest click is on. Focus newly accepted quests, on by default because that is what the game does, can be turned off so a quest you accept while nothing is focused is left unfocused, which on WoW Forever also keeps the Everything Quests TomTom arrow from jumping to it. Like Keep focused quest after relog, it waits while Use Blizzard's quest tracker is on. Requested by jackfbrownii.",
            } },
            { head = "Improvements", items = {
                "The zone label under quest titles is not shown while zone headers are on, since the header above already names the zone. The setting keeps its value, and its box on the Tracker tab is dimmed while zone headers are on, with a tooltip saying why.",
                "/eqot status reports the zone headers, with their order, how many are collapsed and which zones count as the one you are in, and the two focus options, with how many times the game asked to focus a new quest while nothing was focused and how many of those focuses were taken back.",
                "Every language stays fully translated. German, French, Russian, Korean, Simplified Chinese and Traditional Chinese cover every new option in this release, including zone headers and the two focus options.",
            } },
            { head = "Bug Fixes", items = {
                "A color swatch at the end of a checkbox row on the Appearance tab, such as Bar Color beside Show header bars, no longer has its name run under the swatch.",
            } },
        },
    },
    {
        version = "2.1.0", date = "2026-10-03",
        sections = {
            { head = "New Features", items = {
                "Keep section headers in view while scrolling (Tracker tab): the header of the section you are scrolled into stays at the top of the quest list, and the next section's header pushes it out of the way as you reach it. Clicking it still collapses the section. On by default.",
                "Quest Title Color (Appearance tab) colors quest titles By difficulty, in Gold color, in your Class color, in a Custom color, or in Original Style, the way Blizzard's own tracker colors them on your version of the game. It replaces Use class color for titles and the Tracker tab's Quest Title Color By Difficulty. The Quest Title Color Override picker moves under it as Custom Title Color, and whatever those were set to carries over unchanged.",
                "The objective text, the color of a count like 0/5 (none done, in progress and done), and finished objectives can each be given their own color on the Appearance tab. Every one starts at the color it has always been. Until a finished objective is given its own color, it follows the done color, or the title color while Use title color for completed quests is on and Quest Title Color gives one (Class color, Custom color or Original Style). Requested by Rhinoplasty.",
            } },
            { head = "Improvements", items = {
                "The Appearance tab is reorganized with the most used settings first: Text, Quest Colors, Tracker, Section Headers and Spacing, then Quest Rows, Progress Bars, the Scroll Bar, the Scenario panel, the Scenario Bonus Objectives and the Zone Progress Bar. Every setting keeps its value.",
                "The switch that hides the cogwheel at the top of the tracker is now called Show the options cogwheel on the tracker, so it can be found. It is on the Tracker tab, and /eqot still opens the options with the cogwheel hidden. Requested by zeldakostv.",
                "Every language stays fully translated. German, French, Russian, Korean, Simplified Chinese and Traditional Chinese cover every new option in this release, including Quest Title Color, the objective and count colors, and the sticky section headers.",
            } },
        },
    },
    {
        version = "2.0.0", date = "2026-10-03",
        sections = {
            { head = "Improvements", items = {
                "The options window has a new look: a sidebar for its four tabs, settings grouped into cards on every tab, and redesigned checkboxes, sliders, dropdowns and color swatches. No setting or saved value changes.",
                "The Appearance tab shows a live preview beside its settings: a sample tracker drawn the way your tracker draws, which changes as you adjust fonts, colors, header bars, quest cards, progress bars, the scroll bar, the background and border, and the docked zone bar.",
                "The About tab uses the same cards, with its links as buttons and the changelog listed by version.",
                "Confirmation prompts, the new profile name prompt and the copy-a-link popups match the new look.",
                "The right-click menus on quests, the floating zone progress bar and the bonus objectives HUD match the new look.",
            } },
            { head = "Bug Fixes", items = {
                "A confirmation left open when a fight started no longer keeps every key from reaching the game after Enter was pressed on it.",
            } },
            { head = "Notes", items = {
                "Everything Quests is next in line for this overhaul, so its windows will get the same new look.",
            } },
        },
    },
    {
        version = "1.28.0", date = "2026-09-30",
        sections = {
            { head = "New Features", items = {
                "Use Blizzard's quest tracker, a new option at the top of the General tab, turns off the EQ Objective Tracker window and brings back the game's own quest tracker. The parts that do not need the window keep working, including quest sounds, the flight point highlight on retail and the zone progress bar, which floats on its own while the window is off, and on WoW Forever the TomTom arrow Everything Quests draws for the quest you follow. Settings for the window itself, such as its hide rules, the bonus objectives HUD and hiding Questie's tracker, wait until you switch back. The interface reloads to switch, in either direction. Everything Quests has the same checkbox in the Tracker section of its General tab. Requested by diana_winter.",
                "On retail and WoW Forever both trackers use the game's own list of tracked quests, so what you track carries over when you switch. On Classic Era and TBC Anniversary the game's tracker starts with nothing watched, and you add quests from the quest log as usual. The EQ Objective Tracker window keeps its own list, which still auto-tracks quests you accept in the meantime, and switching back empties the game's watch list again so its five-quest limit never gets in the way.",
            } },
            { head = "Bug Fixes", items = {
                "On Classic Era and TBC Anniversary with Questie installed, EQ Objective Tracker empties the game's watch list behind every quest the game adds to it, and Questie could take that for you untracking the quest, which could leave it marked as untracked in Questie's own settings. Those removals are now flagged the way Questie flags its own.",
            } },
        },
    },
    {
        version = "1.27.0", date = "2026-09-29",
        sections = {
            { head = "New Features", items = {
                "On WoW Forever, the quest you follow now gets a TomTom arrow when Everything Quests and TomTom are both installed, as a focused quest already does on Classic Era and TBC Anniversary. It works for any quest Everything Quests knows the location of. Following a different quest, from the tracker or the map, moves the arrow, clicking the quest you already follow brings it back after TomTom clears it on arrival, and stopping following clears it.",
            } },
            { head = "Notes", items = {
                "WoW Forever no longer forgets every addon's settings when the game restarts. Blizzard fixed the beta client bug listed under Known Issues in 1.25.0 on build 1.60.1.70009.",
            } },
        },
    },
    {
        version = "1.26.0", date = "2026-09-27",
        sections = {
            { head = "New Features", items = {
                "Always show campaign quests, a new retail option on the Tracker tab, keeps your campaign quests from every zone on the tracker, even while Show only quests in current zone is on. It sits just under that filter and is off by default. Unchecking Campaign quests still hides them, and so does Show only tracked quests for a campaign quest you have untracked. Requested by Lokir.",
                "Tracker Opacity, a new slider on the Appearance tab, fades the whole tracker so the game shows through it. Moving the mouse onto your quests or headers brings it back to full, and the quest you are following stays fully solid while the rest is faded. Each of those has its own switch under the slider. The slider starts at 100, so nothing changes until you move it. During combat the followed quest's item button fades along with the rest. Requested by Flamed_1984.",
            } },
            { head = "Improvements", items = {
                "Every language is fully translated again. German, French, Russian, Korean, Simplified Chinese and Traditional Chinese now cover the whole addon, including both new options, the quest accepted and turned in sounds, the progress bar settings, and the reworded Reset all settings tooltip.",
                "/eqot status now shows when the tracker last asked the game to play one of its sounds and what the game answered, and, for the quests that are complete right now, how many the tracker has on record as complete, as unfinished, or not at all. Both are there to help find out why the Quest Sound can play minutes late on WoW Forever.",
            } },
        },
    },
    {
        version = "1.25.1", date = "2026-09-19",
        sections = {
            { head = "Bug Fixes", items = {
                "A finished quest that is turned in from the objective tracker rather than at an NPC, such as a Prey hunt for Astalor Bloodsworn, can now be turned in with this tracker. Left-clicking it opens the reward window, as the default tracker does, and the quest shows the default tracker's \"click to complete\" line. Until now this tracker offered only the Quest Complete box, and a quest that never showed one could not be turned in without the default tracker. This one could not be tested on a finished hunt before release, so please report anything that looks wrong.",
                "Pressing a quest in the tracker and letting go of the mouse button somewhere else no longer counts as clicking it.",
                "A quest whose text wraps onto several lines is no longer drawn over by the quest below it. The tracker now measures each quest again once it has been drawn, and lays itself out again when a height has changed. This was seen on WoW Forever.",
            } },
        },
    },
    {
        version = "1.25.0", date = "2026-09-18",
        sections = {
            { head = "New Features", items = {
                "WoW Forever is now supported, as a work in progress, so expect bugs, and please report anything that looks wrong. The tracker follows your quests there. The retail-only sections, such as world quests and scenarios, have stayed empty there so far.",
                "On WoW Forever, Search on Wowhead in a quest's right-click menu opens Wowhead's Forever pages.",
            } },
            { head = "Improvements", items = {
                "Your tracked neighborhood tasks under Endeavors are now also requested when you enter a new zone, as the default tracker does, so they can appear without waiting for a loading screen.",
            } },
            { head = "Bug Fixes", items = {
                "On WoW Forever, logging in or passing a loading screen with the tracker enabled no longer disconnects you, and neither does /eqot status. Each was asking for neighborhood initiative data, the tasks retail shows under Endeavors, which Forever reports as unavailable. The tracker now asks only when the initiative is available to your character, the same check it already made before showing those tasks.",
            } },
            { head = "Known Issues", items = {
                "Right now the Forever beta forgets every addon's settings when the game restarts. That is a bug in the beta client itself, reported to Blizzard, and until it is fixed the tracker starts from its default settings on each launch.",
            } },
        },
    },
    {
        version = "1.24.2", date = "2026-09-16",
        sections = {
            { head = "Bug Fixes", items = {
                "A quest's tooltip on Classic shows the XP that quest actually awards. On Classic Era the game only reports XP for whichever quest is selected in your quest log, so every quest showed that one quest's figure, and the number jumped whenever something changed the selection. Each quest's XP is now read once with the selection moved onto it and then put back, so your quest log stays where you left it, and it is read again when you level up, since a quest pays less once you outlevel it. Right after logging in or a reload, the XP line can take a little while to appear.",
            } },
        },
    },
    {
        version = "1.24.1", date = "2026-09-13",
        sections = {
            { head = "Bug Fixes", items = {
                "Colors you set no longer come back invisible when ElvUI is loaded on Classic Era or Burning Crusade. ElvUI adds its own controls to the game's color picker, and its opacity box and the opacity slider disagreed about which end meant opaque, so clicking its Class button stored a color with nothing left of it to draw. Header bars were the clearest casualty: they vanished the moment you changed their color, nothing brought them back, and ElvUI's own box went on reporting the color as perfectly normal. The picker now agrees with the opacity ElvUI is showing you, and a color already stored invisible comes back as soon as you set it once more. Nothing about how opacity is read changes on a client whose color picker is the game's own.",
                "Opening a second color swatch without closing the color picker first no longer carries the previous swatch's opacity across. The picker loads its opacity control only when it opens, so aiming an already open picker at a different setting left the old value sitting in it, and whatever color you then picked was stored with an opacity you never chose. On Classic that could also leave the picker with no opacity control visible at all.",
                "The tracker no longer adds a second Class button to the color picker when another addon has already put one there. It stood down for ElvUI alone, so anyone running Color Picker Plus itself, or another fork of it, got two.",
            } },
        },
    },
    {
        version = "1.24.0", date = "2026-09-12",
        sections = {
            { head = "New Features", items = {
                "The event title above the scenario banner can be sized and colored. That is the line naming the scenario itself, and it had no controls of its own while the banner text below it had several. Both settings live in the Scenario group on the Appearance tab, named Event Title Text Size and Event Title Color, and both start at exactly what the tracker already drew, so nothing on your screen moves until you change one. The color is set separately from Section Header Color even though it matches it by default, because the scenario panel is not one of the tracker's sections. Asked for by Entmoot.",
            } },
        },
    },
    {
        version = "1.23.0", date = "2026-09-11",
        sections = {
            { head = "New Features", items = {
                "Timed quests count down on the tracker in Classic Era and Burning Crusade. An escort or a bombing run shows the time left on its row, in the same place a world quest shows its expiry on retail, and the last minute counts down in seconds rather than dropping off.",
            } },
            { head = "Bug Fixes", items = {
                "The game's own floating quest timer box no longer sits beside the tracker. It is a separate frame from the quest tracker, so hiding the tracker never hid it, and it left you with a Blizzard timer next to an EQOT row that said nothing about the timer. It is hidden now, and only where the tracker draws the countdown itself, so nobody loses a timer without getting one back. If you would rather keep the game's own box, /eqot disable Blizzard and a reload turns this addon's suppression off. That switch covers the game's whole tracker rather than just the timer box, so its quest watch frame comes back with it.",
                "Quests you have had for a while no longer turn up marked as new after a slow login. The tracker decided what you already had from the first quest log it managed to read, and the game hands that log back a piece at a time when you first log in, so anything that had not arrived yet was recorded as brand new. It carried the New tag for an hour, and it sat at the top of the Recent order until you turned it in, because that first reading is saved per character. It now waits for the game to say the log is all there before taking that reading.",
                "The tracker no longer trusts the quest log for the moment after a loading screen, while the game is still rebuilding it. A reading taken in that window could show a completed quest as unfinished and an objective as further from done than it is, which is enough to play the objectives sound again for a quest you had finished long before you zoned.",
                "Quests that are simply slow to arrive are no longer mistaken for quests you have dropped. The tracker keeps a little state per quest and clears out anything that leaves your log, and a quest log still streaming in looks exactly like a log with quests missing from it, so a slow login could spend that patience on quests that were only late.",
            } },
        },
    },
    {
        version = "1.22.0", date = "2026-09-08",
        sections = {
            { head = "New Features", items = {
                "Bonus objectives now show up on the tracker. Walking into one, such as a Temple Patrol in the Vaults of Atal'Utek, gave you an objective the game was tracking and the tracker was not, with nothing on screen to say why and no setting that brought it back. They now have a Bonus Objectives section of their own, the way the default tracker gives them one, and the Bonus Objectives filter turns them off again. It arrives under Quests, or at the bottom of the run if you have already rearranged your sections, and you can move it wherever you want it under Tracker, Section Order, the same as any other. Reported by Entmoot.",
            } },
            { head = "Bug Fixes", items = {
                "A long scenario name no longer runs off the side of the tracker. Names such as \"Temple Incursion: Cache of the Three\" were drawn on a single line that simply carried on past the edge of the frame. They wrap onto a second line now, and the header grows to fit. The category line above the name wraps with it. Reported by Entmoot.",
                "The stage name inside the scenario banner wraps instead of being cut short. \"Defeat the Looming Mutagenitor\" read \"Defeat the Looming Mutageni...\" where the default tracker showed it in full. A name too long for the banner art is still shortened, since there is only so much room on it.",
                "The text inside the scenario banner is centered properly. It was lined up on the banner's frame rather than on the banner art itself, and the two are not the same width, so the stage and its name both sat noticeably to the left of the plaque they are drawn on. Reported by Entmoot.",
                "Banner Alignment now puts the banner where it says it will. The banner art is wider than the invisible frame it hangs in, and Left, Center and Right all lined up that frame rather than the art you actually see. Right pushed the banner well off the side of the tracker, Center sat noticeably right of center, and Left was the only setting that looked correct. The frame follows the art now, so all three land where you would expect.",
            } },
        },
    },
    {
        version = "1.21.0", date = "2026-09-07",
        sections = {
            { head = "New Features", items = {
                "Find Group is now on a quest's right-click menu, so you no longer have to hit the small eye icon on the row to reach it. It is there on ordinary quests and on world quests, and only on a quest the game will actually form a group for, so the menu does not offer it where it cannot work. Asked for by AIR.",
            } },
        },
    },
    {
        version = "1.20.1", date = "2026-09-05",
        sections = {
            { head = "Bug Fixes", items = {
                "Fixed the tracker going stale and staying that way until you reloaded. Accepting a quest, finishing an objective or handing a quest in would all leave it showing whatever it showed before, and the only way back was to force a redraw yourself by toggling a setting, opening the options window or reloading. Reported by AIR.",
                "Behind it, the tracker gathers up a burst of game events and redraws once a fraction of a second later, rather than redrawing for every event on its own. If the game ever dropped that scheduled redraw, nothing noticed and nothing scheduled another, so every later request to redraw was folded into one that was never coming. The tracker went quiet for the rest of the session with no error on screen to explain it, and the quest completion sound could stop the same way. A redraw asked for well past its due time now schedules a fresh one, so a dropped redraw costs you one or two rather than all of them.",
            } },
        },
    },
    {
        version = "1.20.0", date = "2026-09-05",
        sections = {
            { head = "Notes", items = {
                "The note in 1.19.1 said that with no chat box open, shift-clicking a quest on the tracker does whatever your ordinary left-click does. That is no longer true as of this release: it untracks the quest. See the first entry below.",
            } },
            { head = "New Features", items = {
                "The bonus objectives HUD can be styled. Its background and its border have a box each and a color each, so the panel can be recolored, made more or less transparent, or have its frame taken away entirely to leave the text floating over the world. Unticking both boxes is what removes the frame. Until you pick a background color it keeps the plain black fill it has always had, which fades a little once the HUD is locked, and picking one hands that opacity to you.",
                "Shift-clicking a quest on the tracker untracks it again, whenever no chat box is open. With a chat box open it still drops the quest into chat, which is what 1.19.0 added, so the two halves of the gesture no longer get in each other's way: start typing and shift-click links the quest, shift-click with chat closed and the quest is untracked. This is not the old hide gesture returning. That was removed in 1.19.0, on every version of the game. The quest stays in your quest log and you track it again from there, the way you always have.",
                "Worth knowing, because the row does not always vanish when you do it: a quest only leaves the tracker if Show only tracked quests is on. With that setting off, for a pinned quest, and for a world quest listed because it is in your zone, the quest is untracked but the row stays where it is.",
            } },
            { head = "Bug Fixes", items = {
                "Fixed a stream of Lua errors reading \"Auras cannot be accessed when secret while tainted by 'EQObjectiveTracker'\", reported in scenarios and other instanced content. The game's own objective tracker goes on laying its sections out even while it is hidden, and its scenario section reads one of your buffs without the check that reading a buff now needs, so the read failed and the error named whichever addon was in the way. This one always is, because hiding the game's tracker is the whole job. It now takes those sections off the hidden tracker instead, so there is nothing left on that path for the game to lay out. Reported by tflo.",
                "A world quest no longer takes up to half a minute to appear after you walk into its area. The tracker had the quest ready the whole time and simply was not redrawing: it noticed world quests coming and going only when the game happened to send it an unrelated quest update, so the row waited, and anything that forced a redraw - opening the options window, toggling a setting - made it appear at once. It now redraws when quests appear around you, and the row arrives at about the same moment the default tracker's does.",
                "A world quest you are super-tracking now appears on the tracker wherever you are standing. The game draws its arrow the moment you click one on the map, and the default tracker lists it, but this one only ever listed world quests you had watched, ones on the map under your feet, or ones already in your quest log. A quest you picked from the map and then flew away from matched none of those, so you were left with an arrow pointing at something the tracker never showed, and it came and went as you crossed zones. It is now listed for as long as it is the quest you are super-tracking.",
                "On Classic Era and TBC Anniversary, the tracker's right-click menu offered Track on a quest that was already being tracked, on any character that had never untracked anything. The tracker keeps its own tracking list on those versions and reads an untouched list as everything tracked, which is what makes the whole log show; the menu was the one place reading it the other way round. It now agrees with the rest, so the menu says Untrack, and the new shift-click untrack above works on those characters instead of doing nothing.",
            } },
            { head = "Improvements", items = {
                "The bonus objectives HUD's settings moved from the Tracker tab to the Appearance tab, under a Scenario Bonus Objectives heading, next to the new frame controls above. The switch that turns the HUD on, the Test button and the HUD Scale slider are the same controls doing the same thing, only somewhere else. It is the move the zone progress bar made in 1.18.0 and for the same reason: a switch sitting two tabs away from the settings it governs leaves you with no way to work out why they appear to do nothing.",
                "Reset to Defaults on the Appearance tab now also restores the bonus objectives HUD's frame and its scale. It deliberately leaves the HUD's own switch and its position alone, so a reset never switches the HUD off and never moves it back to the middle of your screen.",
                "The Lives count in the delve readout is read from the game's own delve header now, rather than being scraped off the text of the hidden tracker. The scrape was why it was unreliable: it could pick up a neighboring number instead, and it only ever worked on an English client. It had to move for the fix above as well, which stops that text being drawn at all.",
            } },
        },
    },
    {
        version = "1.19.1", date = "2026-09-03",
        sections = {
            { head = "Notes", items = {
                "A note on the shift-click change in 1.19.0, which has caused some confusion. It applies to every version of the game, Retail included, and shift-clicking a quest on the tracker has not been removed. What that entry did not make clear is that the replacement needs a chat box to be open: shift-click puts the quest into chat while you are typing, and with no chat box open it does whatever your ordinary left-click does. That is what makes it look like the gesture stopped working. Open chat first and it will link.",
            } },
            { head = "Bug Fixes", items = {
                "The zone progress bar now draws in a zone that sits inside another zone. Standing anywhere in Voidstorm it stayed blank, because the tracker stopped at the first zone it found and a sub-area like Slayer's Rise has no quest routing of its own. It now looks past a zone that nothing is routed to and uses the one that is. Zones that already showed a bar are unchanged.",
                "A world quest you are tracking in a different zone no longer disappears from the tracker. It worked out whether a world quest was still live from its timer, the map you are standing on and your quest log, so a lair quest with no timer, in a zone you have since left, failed all three tests and the row was dropped while Blizzard's own tracker kept showing it. It now asks the game whether the quest is active, so the row stays until the quest really ends.",
            } },
        },
    },
}
