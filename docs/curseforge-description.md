# EQ Objective Tracker

**A standalone replacement for Blizzard's objective tracker. Sort it, filter it, restyle it, and put it where you want it.**

[![Support on Ko-fi](https://img.shields.io/badge/Support-Ko--fi-FF5E5B?style=flat-square&logo=ko-fi)](https://ko-fi.com/wheelbarrel00) [![Donate with PayPal](https://img.shields.io/badge/Donate-PayPal-00457C?style=flat-square&logo=paypal)](https://www.paypal.biz/wheelbarrel00) [![Version](https://img.shields.io/github/v/release/wheelbarrel00/EQObjectiveTracker?color=6D0501&label=Version&style=flat-square)](https://github.com/wheelbarrel00/EQObjectiveTracker/releases) [![Discord](https://img.shields.io/badge/Discord-Join-5865F2?style=flat-square&logo=discord)](https://discord.gg/vm8K2WfQUE) [![Languages](https://img.shields.io/badge/Languages-EN|DE|FR|RU|KO|ZH-6D0501?style=flat-square)](https://github.com/wheelbarrel00/EverythingLocales) [![License](https://img.shields.io/github/license/wheelbarrel00/EQObjectiveTracker?style=flat-square&color=333333)](https://github.com/wheelbarrel00/EQObjectiveTracker/blob/main/LICENSE)

![Retail](https://img.shields.io/badge/Retail-12.1-8B0000?style=flat-square) ![TBC Anniversary](https://img.shields.io/badge/TBC_Anniversary-2.5.6-1E7145?style=flat-square) ![Classic Era](https://img.shields.io/badge/Classic_Era-1.15.9-B8860B?style=flat-square) ![WoW Forever](https://img.shields.io/badge/WoW_Forever-1.60.1_beta-3F7F5F?style=flat-square)

***

## WoW Forever support is a work in progress

Retail, Classic Era and TBC Anniversary are all supported. **WoW Forever support is newer and still a work in progress, so expect bugs.** Please report anything you find rather than assuming it is already known.

The tracker shows your quests on Forever, and with Everything Quests and TomTom installed the quest you are following gets a TomTom arrow, as on Classic. The retail-only sections, such as world quests and scenarios, have stayed empty there so far, and Search on Wowhead opens Wowhead's Forever site.

***

## At a glance

*   Replaces Blizzard's objective tracker with a frame you can move, resize and scroll, and while it is unlocked a gold strip along its top shows where to drag it
*   Prefer Blizzard's own tracker? One checkbox brings it back, and the quest sounds and most other parts that don't need the window keep running
*   Runs on Retail, Classic Era and TBC Anniversary, and on WoW Forever as a work in progress
*   Tracks quests, campaign quests, world quests, bonus objectives, scenarios, delves, achievements, professions and endeavors on Retail, and quests on Classic and Forever
*   Right click any quest for a menu: pin, track, focus, open the quest log, pop out the details, find a group, look it up on Wowhead, or abandon it
*   Shift click a quest to untrack it, or to drop it into chat while a chat box is open
*   Focus a quest on Classic, or follow one on Forever, and with Everything Quests and TomTom an arrow points at it
*   On Retail and Forever, optionally click the quest you are following to unfocus it, or stop the game focusing each quest you accept while nothing is focused
*   Pin a quest to keep it on screen no matter how your filters are set
*   Hover a quest to see its objectives and full rewards, with item level compared against what you have equipped
*   Timed quests count down on their row, in seconds through the last minute
*   Eight sort orders, including by distance and a manual order you drag into place, and an optional button on the tracker to switch between them in two clicks
*   Filter by quest type, or show only the quests with an objective in your current zone, on Retail optionally keeping your campaign quests from every zone
*   An optional filter button on the tracker lists the zone filter and every quest type in one menu, and turns gold while any of them is set to hide quests
*   Split your sections across up to three tabs on Retail, switched from a strip at the top of the tracker
*   Collapse, hide and reorder your sections, and keep a section's header in view while you scroll through it
*   Group your quests under a header for each zone, each collapsing on its own, with the zones on your map first or in alphabetical order
*   Gather your dungeon quests, heroic ones included, under one Dungeons header, with or without zone headers, and keep it at the bottom if you like
*   Fonts, sizes, spacing, colors, progress bars, the card layout, borders and the scroll bar, down to a slim strip, are all yours to change
*   Color quest titles by difficulty, in gold, in your class color, in a color you pick, or the way the game's own tracker does, and give the objective text, progress counts, finished objectives, finished quest titles and the NEW tag their own colors
*   Fade the tracker down to as little as 10% opacity, with it coming back to full under the mouse and the quest you are following kept solid
*   Shows a Mythic+ key's timer, keystone level, affixes and deaths, with the time left for +3 and +2, though it is not yet tested in a real key
*   Hides itself in combat, in instances, on Mythic+ runs, while the world map is open, or when you have no quests showing, each optional
*   Reads in German, French, Russian, Korean, Simplified Chinese and Traditional Chinese as well as English, picked up from your game client automatically
*   Needs no other addon. Everything it uses is bundled.

***

## Works with or without Everything Quests

**On its own.** This is a complete tracker. Install it, and it takes over from Blizzard's objective tracker straight away. It does not need Everything Quests, and it never will.

**Alongside Everything Quests.** [Everything Quests](https://www.curseforge.com/wow/addons/everything-quests) is a full replacement for the WoW quest experience. On Retail it brings nameplate quest icons, world quest map pins, a Midnight chain guide and an account-wide quest history, and on Classic it adds quest markers on the map and minimap and a Quest Browser for looking up almost any quest before you pick it up. The tracker you are reading about now is the tracker half of it, split out so people who only want the tracker can have just that.

**They are already joined up.** As of Everything Quests 1.38.0 there is only one tracker between the two addons, and it is this one. Everything Quests lists it as a dependency, so installing Everything Quests brings this along on its own and both stay updated. There is nothing to set up, and nothing to install twice.

**On Classic and Forever they work together too.** Everything Quests adds the other half of the picture there, map pins and the TomTom arrow among them, and it is what turns the quest you focus or follow into an arrow. Its Classic support is still growing, so check its own page for what it covers today.

If you came from Everything Quests, your tracker settings are read across the first time this loads, so it starts out looking the way yours already did. That includes your per-character state, on every character: pinned quests, which sections you had collapsed, and your saved world quest watches. Nothing is changed on the Everything Quests side.

One copy of the tracker code now means a fix lands in both places at once.

***

## Rather keep Blizzard's tracker?

Tick **Use Blizzard's quest tracker** at the top of the General tab, or the same checkbox in the Tracker section of Everything Quests' General tab. The interface reloads, the tracker window is gone, and the game's own quest tracker is back. The parts that don't need the window keep working: the quest sounds, the flight point highlight, the zone progress bar, which floats on its own then, and on Forever the TomTom arrow Everything Quests draws for the quest you follow. Settings for the window itself, such as its hide rules, the bonus objectives HUD and hiding Questie's tracker, wait until you switch back, and so do Keep focused quest after relog and Focus newly accepted quests, so the game focuses each quest you accept as usual. Untick it to get the window back, again after a reload.

On Retail and Forever both trackers use the game's own list of tracked quests. On Classic Era and TBC Anniversary the game's tracker starts empty, so shift click quests in the quest log to watch them, up to the game's limit of five, and this tracker's own list is kept for when you switch back.

***

## What it does

**Quests and campaign** sit in their own sections, with objectives, progress counts and completion state. Left click a quest to super-track it on Retail and Forever, or to focus it on Classic. On Retail and Forever two options on the Tracker tab change how focusing works: **Click a focused quest to unfocus it** makes a click on the quest you are following unfocus it, and turning off **Focus newly accepted quests** stops the game focusing each quest you accept while nothing is focused. Shift click a quest to untrack it, or with a chat box open to drop it into chat. Right click opens a menu to pin, track or untrack, focus, open it in the map and quest log, pop out its details, find a group, search Wowhead, or abandon it. The Classic menu is shorter, since those clients have no group finder and popping out and abandoning need frames they do not have. Any quest the game will form a group for gets a Find Group button on its row as well. A pinned quest carries a star and stays on the tracker whatever your filters say.

**Zone headers** group the quests in the Quests and Campaign sections under the quest log heading each one sits under, which is its zone for most quests. Each zone gets a header with a count and collapses on its own. The zones with a quest on the map you are in can come first, or every zone can be listed in alphabetical order, and quests inside a zone still follow your sort order. While they are on, the zone label under quest titles is not shown, since the header already names the zone, except on a quest in the Dungeons header. Off by default, on the Appearance tab. On Classic Era and TBC Anniversary they group the Quests section.

**A Dungeons header**, on the Appearance tab's Zone Headers card, gathers every quest the game marks as a dungeon quest, heroic ones included, under one header of its own. With zone headers off your other quests stay as they are and Dungeons comes after them, and with zone headers on dungeon quests leave their zones for it. With the zones on your map listed first, it moves to the top while one of its quests is on your map, unless you tick **Keep Dungeons at the bottom**. A quest under it keeps its zone label, if you show zone labels, so you can tell which dungeon it is for. Both are off by default.

**A sort button**, off by default: tick **Show the sort button on the tracker** on the Tracker tab for a small button at the tracker's top left. It opens the list of sort orders with the current one named at the top, so switching between Level and Distance, or any two, takes two clicks.

**A filter button**, off by default: turn on **Show the filter button on the tracker** on the Tracker tab for a funnel beside the sort button. Its list holds **Show only quests in current zone**, the quest types from the Filters card and **Reset filters to defaults**, and stays open while you check boxes, so several filters change in one go. The funnel turns gold while any of them is set to hide quests.

**Section tabs**, on Retail, off by default: turn on **Show section tabs** on the Section Order card and the number beside each section, World Quests included, picks one of up to three tabs. Once two tabs hold a section, a strip under the top of the tracker switches between them, each tab named after its sections. The scenario panel shows on every tab, and so does a quest popup box, under its own section's header, and each character keeps the tab it was on.

**Quests you hand in from the tracker.** A finished quest that is turned in from the tracker rather than at an NPC, such as a Prey hunt, shows a "click to complete" line, and left clicking it should open the reward window. That could not be tested on a finished hunt before release, so please report anything that looks wrong.

**Timed quests**, on Retail and Forever, count down on their row and in their tooltip, in seconds through the last minute, as they do on Classic. `/eqot timer test` puts a two-minute sample on one of your quests so you can see it without finding a timed quest.

**Hovering any quest** shows its objectives and everything it pays out: money, experience, currencies, and items with their item level set against what you are wearing.

**World quests** get their own capped area at the top or bottom of the tracker, with the quest type drawn on the marker, a color coded countdown as the timer runs down, and a Find Group button where the game allows one. Every world quest in your current zone is listed automatically, not only the ones you have tracked, and you can turn that off. Pick one on the world map and it stays on the tracker wherever you go, for as long as it is the quest you are following. Hovering one also shows its faction and how long is left. They have their own right click menu too.

**Bonus objectives** get a section of their own, the way the default tracker gives them one. They appear when you walk into one and go away when you leave, and they have their own filter, so you can turn them off without touching world quests.

**Scenarios and delves** draw the stage banner and its criteria, including weighted progress bars, along with the stage countdown, the delve tier, and a clickable button for any spell the stage hands you. Two switches on the Tracker tab, on by default, put the lives left and the nemesis groups killed on a delve's tier row, from Tier 4 up, with the game's own icons and tooltips: the lives turn orange at 2 and red at 1, and a check mark shows once every nemesis group is dead.

**Mythic+ keys** get the key's own panel in the stage banner's place, the way the default tracker draws it: the keystone level, the affixes with their descriptions on hover, the time left with a bar that runs down, and the deaths, with the time they cost on hover. Under the bar it lists the time left for +3 and +2, and the bar is marked where each one runs out. The boss and Enemy Forces lines stay under it. Show the Mythic+ timer on the Tracker tab turns it off if you use a separate timer addon, and `/eqot mplus test` draws a sample key so you can see it without running one. **This could not be tested in a real key before release**, so please report anything that looks wrong, with what `/eqot mplus` prints during the key.

**The bonus objectives HUD** is a separate movable readout covering the bonus loot mechanics inside a delve, with a lives and deaths readout for the run. Its background and border can be recolored, or switched off to leave the text floating. Off by default.

**Achievements, professions and endeavors** each get a section. Professions count the reagents you have across every quality tier, and endeavors cover both the Traveler's Log monthly activities and the neighborhood tasks you have tracked.

**Progress bars** are drawn for objectives that report a percentage or a running total, the way the default tracker draws them. Quest rows and scenario criteria each have their own switch, and the bar's texture, fill color, background, border and height are all yours to set.

**Quest items** appear as a usable button on the row of any quest that carries one, with charges, cooldown and an out of range tint.

**Quest popups** appear for newly discovered quests and ones you can hand in remotely.

**World event bars.** The extra bars and status lines the default tracker shows during world events appear here too, where they would otherwise not show up anywhere.

**A zone progress bar** shows how far through a Midnight zone's questlines you are, either floating on its own or docked into the tracker as a section you can reorder.

**Moving it.** Unlock the tracker and the strip along its top turns gold and reads "Drag to move, corner grip to resize.", with a check button that locks it again and a gold outline around the tracker, so you can see exactly what moves. It shows while the options window is open, or right after you unlock it. Right click that strip or the cogwheel to unlock or lock it, reset its position and size, or open the options.

**Make it yours.** Quest titles can be colored by difficulty, all in gold, in your class color, in a color you pick, or in Original Style, the way the game's own tracker colors them on your version of the game. The objective text, a count like 0/5 as it goes from none done to in progress to done, finished objectives, the title of a finished quest and the NEW tag on quests you accepted in the last hour can each take a color of their own. There are 42 bundled fonts plus anything from LibSharedMedia, each shown in its own typeface in the picker, 7 status bar textures, and 31 sounds (27 voice lines and 4 chimes), plus a card layout with quest type tints, border thickness, header bars, section and zone headers that stay in view while you scroll, zone headers with a size, color, bar, divider and indent of their own, and a scroll bar with its own background color, a solid color thumb and a Scroll Bar Width slider that narrows the bar to a flat strip as slim as 4 pixels and gives the quest text the room it frees. Settings live in profiles you can switch between.

**Find any setting.** A search field at the top of the options window's sidebar lists, as you type, every setting whose name matches in your game's language, with the tab and card it lives on. Click one, or press Enter for the first, and the window opens that tab, scrolls to the setting and flashes it.

**Read the changelog in game.** The About tab carries the full release history, the commands, a Discord link, and a live view of what each section is currently producing.

**Extras**: three optional sounds, for when you accept a quest, when it is ready to hand in, and when you hand it in, a highlight on the flight point nearest your tracked quest, and an API other addons can use to add their own right click entries and header icons, or to follow whichever quest you have focused.

***

## On Classic Era and TBC Anniversary

Everything the tracker is actually for works on Classic: quests with zone subtitles, objectives and progress, the sort orders and the sort button, manual drag ordering, per-quest pinning, filters and the filter button, section visibility and ordering, zone headers, the card layout, the scroll bar width, all 42 fonts, the color options, profiles, row tooltips and the row right click menu. Blizzard's own quest watch frame is hidden, so you do not get two trackers.

**No five quest cap.** The tracker keeps its own list of the quests you are tracking rather than using the game's, which on these versions is capped at five and cannot track a quest automatically when you accept it. So "Auto-track accepted quests" works, "Show only tracked quests" can show more than five, and shift clicking a quest in the game's own quest log still tracks and untracks it, with its checkmarks showing this tracker's list.

**Timed quests count down on the row.** An escort or a bombing run shows the time left, counting in seconds through the last minute, and the game's own floating timer box is hidden so you are not left with two timers.

**Focus a quest.** These clients have no super-tracking, so the tracker brings its own. Click a quest's icon to focus it and click the icon again to clear it, or use Focus in the right click menu. The focused quest's title is tinted so you can see at a glance which one you picked. With the companion addon Everything Quests and TomTom both installed, focusing a quest also drops a TomTom arrow on it, and a quest that is ready to hand in points at the person who takes it rather than at the place you farmed it.

**The tracker draws no map pins.** Those come from Everything Quests, which carries the quest database. The tracker itself holds no quest coordinates and is not going to, so on its own a focused quest is the tint and nothing more.

**What Classic does not have.** World quests, bonus objectives, scenarios, achievements, endeavors and tracked recipes have no section there, since most of them need APIs those clients do not have, so those sections simply do not appear rather than sitting there empty. There is no Find Group button, because these clients have no group finder for quests. The zone progress bar stays empty, because its data covers Midnight zones only, and distance sorting does nothing, because the distance API is retail only. A few options still appear that cannot do anything on Classic, for the same reasons.

**Running Questie?** The tracker notices, offers once to hide Questie's tracker so you are not looking at two, and turns that into a permanent toggle on the General tab. It only hides the frame, and Questie's own disable path is never called. Tracking and untracking from this tracker's row menu go through its own list rather than the game's watch functions, so the hooks Questie places on those do not fire for anything you do here.

***

## Slash commands

*   `/eqot` opens the options panel
*   `/eqot lock` and `/eqot unlock` lock or unlock moving and resizing
*   `/eqot reset` restores the default position and size
*   `/eqot toggle` shows or hides the tracker
*   `/eqot status` prints what each section produced and what reached the screen
*   `/eqot debug` toggles entry validation warnings
*   `/eqot bonushud` prints what the bonus objectives HUD can see, or `test` to place it
*   `/eqot mplus` prints what the tracker read for the current Mythic+ key, or `test` or `late` to draw a sample key
*   `/eqot popup` prints the quest popups the tracker read, or `test` to draw a sample Quest Discovered box
*   `/eqot timer` prints the quest timers the tracker read on Retail and Forever, or `test` to put a two-minute sample on a quest
*   `/eqot importeq` replaces this profile with your Everything Quests tracker settings
*   `/eqot modules` lists the optional parts and which are switched off
*   `/eqot disable <name>` switches off one part, or `all`, to narrow down a fault
*   `/eqot enable <name>` switches a part back on, or `all`

***

## Good to know

*   **Retail, Classic Era, TBC Anniversary and WoW Forever.** Retail, Classic Era and TBC Anniversary are supported, and what Classic lacks is listed above. Forever is a work in progress, see the note at the top. Mists of Pandaria Classic is not supported yet.
*   **No dependencies.** Every library it needs is bundled.
*   **Profiles** are supported and shared across all your characters, so you can keep different setups and switch between them.
*   **Translated into German, French, Russian, Korean, Simplified Chinese and Traditional Chinese**, thanks to Stonetwist, Zox, Malevi4, labrie75, 失眠啤酒 and BNS333. Every language covers all 525 of the addon's phrases, and anything a later release adds falls back to English on its own until it is translated, so a partial translation is never a broken one.
*   **World quests sit in their own pinned area** above or below the quest list rather than in the reorderable run, so a long world quest list can never push your quests off screen.
*   Unlock the tracker to move it: drag the gold strip along the top, or the corner grip to resize it, as described under Moving it above.

***

## Found a bug or have an idea?

Open an issue on [GitHub](https://github.com/wheelbarrel00/EQObjectiveTracker/issues), or come and say so in [Discord](https://discord.gg/vm8K2WfQUE). Bug reports with a screenshot and the output of `/eqot status` are the fastest to fix.
