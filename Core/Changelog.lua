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
        version = "2.17.0", date = "2026-11-19",
        sections = {
            { head = "New Features", items = {
                "Share Quest is now in the right-click menu. While you are in a group, right-click a quest the game lets you share and pick Share Quest to offer it to your party, as the Share button in the quest log does. It works on every version of the game, Classic Era and TBC Anniversary included. It cannot be used during a fight, and says so in chat.",
                "Abandon Quest is now in the right-click menu on Classic Era and TBC Anniversary too, as it already was on retail and WoW Forever. It asks first with the game's own confirmation, which warns you about any quest items you would lose, and it cannot be used during a fight.",
                "On retail and WoW Forever, hovering a quest while you are in a group now also lists your party members' progress on it, under the game's own heading, whenever one of them has the quest, as Blizzard's quest log does. Classic Era and TBC Anniversary do not give addons this information, so nothing changes there.",
                "A new Hide finished objectives box on the Tracker tab, under Simplify Mode, hides the objectives you have already finished and keeps every one still left to do. It is off by default. Simplify Mode, which shows only the first objective left, works as before, and the new box is dimmed while it is on.",
            } },
        },
    },
    {
        version = "2.16.0", date = "2026-11-17",
        sections = {
            { head = "New Features", items = {
                "Elite quests and quest types can now show in the tracker on WoW Forever, Classic Era and TBC Anniversary, the way Blizzard's own tracker shows them on WoW Forever. With Show quest level prefix ticked, on the Tracker tab's Quest Row Details card, an elite quest's level reads [21+], and a new box under it, Show quest type tags, adds the quest's type after its title, such as (Elite), (Dungeon), (Raid) or (PvP), in your game's own words. On TBC Anniversary the game calls elite quests group quests, so there they read (Group). Show quest type tags is on by default, because Blizzard's own quest log shows these, so untick it on the Tracker tab if you would rather not see them. Retail's own tracker shows neither for ordinary quests, so the box is not on the Tracker tab there. Requested by jaerb.",
            } },
        },
    },
    {
        version = "2.15.2", date = "2026-11-14",
        sections = {
            { head = "Bug Fixes", items = {
                "A hidden tracker no longer blocks the mouse. Once a quest item button or a delve or scenario spell button had shown up, hiding the tracker, with /eqot toggle or any of the hide options on the General tab, only made it invisible, and its quest rows, headers, buttons and the bar you drag it by were still there catching clicks and the mouse wheel, so you could not click or target anything behind them. Every part of a hidden tracker now lets the mouse through to whatever is behind it, and takes it back when the tracker shows again. One exception, which the game sets: during a fight an addon cannot change whether the quest item and spell buttons take the mouse, so a tracker hidden mid-fight lets go of them, and of the quest list's mouse wheel, when the fight ends, and one shown mid-fight gets them back then. Reported by ccff00cf0.",
                "Hiding or showing the tracker in the middle of a fight, once a quest item or a delve or scenario spell button had shown up, or a delve or scenario spell button coming or going in a fight, no longer causes a blocked-action error naming EQ Objective Tracker ('Button:EnableMouse()' in BugSack).",
            } },
            { head = "Improvements", items = {
                "/eqot status's visibility line now says how many parts of a hidden tracker let go of the mouse and the mouse wheel.",
            } },
        },
    },
    {
        version = "2.15.1", date = "2026-11-13",
        sections = {
            { head = "Bug Fixes", items = {
                "The Quest Sound could play a minute or more after a quest became ready to turn in. This is the late Quest Sound on WoW Forever that 1.26.0's /eqot status lines were added to track down, though every version of the game could be affected. The tracker waits a fifth of a second before checking the quest log, and now and then a rounding error made that wait read a hair short of done when it ended, so the check waited for a later quest log update, which could be minutes away. The tracker now waits out that last moment instead, so the sound plays when the quest is ready. A change to the event and scenario widgets in the tracker could wait the same way, until something else redrew the tracker.",
            } },
            { head = "Improvements", items = {
                "/eqot status's debounce line now ends with a waited out count: the waits that came up a moment short and were finished rather than dropped, so the fix above can be seen working.",
            } },
        },
    },
    {
        version = "2.15.0", date = "2026-11-10",
        sections = {
            { head = "New Features", items = {
                "What's New. After an update that brings new features, a What's New window opens a few seconds after you log in, listing every update since the last one you read, newest first, with the same notes as the About tab's changelog. From this update on, if you skip a few updates it catches you up on all of them at once. Updates without new features stay quiet and are listed in the next window. It is on by default. The first window starts with a short note and a Go to this setting button that opens the option to change it, and Don't show these again, at the bottom of every window, turns it off. A fresh install opens nothing.",
                "A new Updates card on the General tab sets what happens after an update: Popup window, Chat link (one clickable line in chat instead of the window) or Off, shared by every character on your account. Its Show What's New button, the About tab's What's New button and /eqot whatsnew open the window any time. Reset all settings puts it back to Popup window. If Everything Quests has its own What's New to show when you log in, its window opens too, set slightly apart from this one.",
            } },
            { head = "Improvements", items = {
                "/eqot status now has a what's new line saying how you are told after an update, the last update you read and the last one announced in chat, and how many are still to tell.",
                "Every language stays fully translated. German, French, Russian, Korean, Simplified Chinese and Traditional Chinese cover the new window and its settings, mostly in the words Cooldown Master and Everything Quests already use for their own What's New.",
            } },
        },
    },
    {
        version = "2.14.0", date = "2026-11-09",
        sections = {
            { head = "New Features", items = {
                "Show the button bar at the bottom of the tracker, a new box on the Tracker tab's Headers and Buttons card, moves the bar along the top of the tracker, the one you drag it by and where the cogwheel, the sort and filter buttons and other addons' buttons sit, to the bottom edge beside the corner grip. The quests then start right at the top of the tracker, so it can sit flush against the top of the screen, and section tabs, if you use them, move up to the very top. The bar sits at the bottom of the tracker's box, where the corner grip is, so with Background off and a short quest list it can sit some way below the last quest. Off by default. Requested by Azazel.",
                "Show the buttons only on mouseover, on the same card, hides the cogwheel, the sort and filter buttons and other addons' buttons on the tracker until you point at the bar they sit on, at the top or the bottom, and keeps them up for half a second after you move away. Off by default.",
            } },
            { head = "Improvements", items = {
                "The cogwheel, sort button and filter button tooltips on the Tracker tab now say where each sits on the button bar, wherever the bar is.",
                "/eqot status now has a button bar line saying whether the bar sits at the top or the bottom, and whether its buttons are always shown or wait for the mouse.",
                "Every language stays fully translated. German, French, Russian, Korean, Simplified Chinese and Traditional Chinese cover both new options and the reworded tooltips.",
            } },
        },
    },
    {
        version = "2.13.0", date = "2026-11-07",
        sections = {
            { head = "New Features", items = {
                "On WoW Forever, the zone progress bar now works when Everything Quests 2.10.0 or later is installed. It shows how many of the zone's quests you have turned in, counted by Everything Quests from its own quest data: the quests its Chain Guide lists for the zone and any other quest that starts there, only those your character can take, with dungeon and raid, repeatable, profession and holiday quests left out, as are the quests of the Ahn'Qiraj war effort, which WoW Forever may never run. Most quests the game will no longer offer you, such as the other half of an either-or pair, leave the total, so in most zones the bar can reach 100%. A cave or building counts toward the zone around it, and each capital city is a zone of its own. Without Everything Quests the bar still shows nothing on WoW Forever, and the option's tooltip there now says so. Turn the bar on with Show zone progress bar on the Appearance tab.",
                "Other addons can now supply the zone progress bar's count, which is asked for before the tracker's own, through new calls on the public API: AddZoneCounter, which registers a function asked for the zone's done and total, and ZoneCountChanged, which asks for a recount when those numbers move (RemoveZoneCounter takes the function back). ZoneBarShown says whether Show zone progress bar is turned on.",
            } },
        },
    },
    {
        version = "2.12.0", date = "2026-11-07",
        sections = {
            { head = "New Features", items = {
                "On WoW Forever, Shortest Path Forever's journey column now sits right under the tracker's quests rather than over them, or above or beside the tracker when there is no room below. It follows the list as it grows and shrinks. With Background or Border on, or move mode's outline showing, it keeps clear of the whole tracker box. This needs Shortest Path Forever 1.22.35 or later. Reported by AnotherDamnDave.",
                "On WoW Forever, EllesmereUI's Custom Quest Tracker, a quest tracker window of its own, now hides while this tracker is in use, as EllesmereUI's tracker did before that option existed, so the two no longer sit side by side. If a fight is on, it hides when the fight ends. With Use Blizzard's quest tracker on, EllesmereUI's tracker is left alone.",
                "Other addons can keep their own frames clear of the quest list through new calls on the public API: GetListBounds, which says where the list is drawn, and AddLayoutListener, which registers a function called whenever that changes (RemoveLayoutListener takes it back).",
            } },
        },
    },
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
}
