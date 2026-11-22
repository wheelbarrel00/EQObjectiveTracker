# EQ Objective Tracker

A standalone replacement for World of Warcraft's default objective tracker.

It is the tracker half of [Everything Quests](https://github.com/wheelbarrel00/EverythingQuests),
extracted so you can use just the tracker without the rest of EQ. It does not require
Everything Quests, and never will.

The relationship runs the other way: as of Everything Quests v1.38.0, EQ has no tracker of its
own and installs this one as a dependency. There is one copy of the tracker code now, so a fix
lands in both places at once.

[Discord](https://discord.gg/vm8K2WfQUE) &middot;
[CurseForge](https://www.curseforge.com/wow/addons/eq-objective-tracker) &middot;
[Report a bug](https://github.com/wheelbarrel00/EQObjectiveTracker/issues)

## Status

**Retail, Classic Era (1.15.9), TBC Anniversary (2.5.6) and WoW Forever (1.60.1) are all
supported.** The Classic gaps listed below are real ones rather than a disclaimer. Please report
anything you find rather than assuming it is known.

**WoW Forever support is stable**: the tracker has been tested there from Forever's beta through
its launch. It shows your quests there, and with Everything Quests and TomTom installed the quest
you are following gets a TomTom arrow, as on Classic. With Everything Quests 2.10.0 or later
installed, the zone progress bar counts the quests of the zone you are in, once Show zone
progress bar is turned on in the Appearance tab. The retail-only sections, such as world quests
and scenarios, have stayed empty there so far.

On retail it tracks quests and campaign quests, world quests and bonus objectives, scenarios
and delves, achievements, professions, and endeavors, covering both the Traveler's Log monthly
activities and the neighborhood tasks you have tracked.

### What works on Classic today

Quest tracking and the customization around it: sorting, manual drag ordering, per-quest
pinning, filters, To-Do Mode, section visibility and ordering, zone headers, the card layout, fonts
and colors, profiles, row tooltips, and the row right-click menu. Blizzard's own quest watch frame is
suppressed so you do not get two trackers.

The tracker keeps its own list of which quests you are tracking rather than using the game's,
which on these versions is capped at five quests and cannot track a quest automatically when
you accept it. So "Auto-track accepted quests" works, "Show only tracked quests" can show more
than five, and shift-clicking a row in the game's own quest log tracks and untracks exactly as
it always did, with its checkmarks showing this tracker's list.

Timed quests count down on the row. An escort or a bombing run shows the time left where a
retail world quest shows its expiry, counting in seconds through the last minute, and
the game's own floating timer box is hidden so you are not left with two timers.

You can also focus a quest, which these clients have no super-tracking for. Click a row's
icon to focus it and click the icon again to clear it, or use Focus in the right-click menu.
The focused quest's title is tinted. If Everything Quests and TomTom are both installed,
focusing a quest also points a TomTom arrow at it.

### What is missing or limited on Classic

- **No map pins.** Those come from the companion addon - see below. The TomTom arrow needs it
  too, so on the tracker alone a focused quest is the tint and nothing more.
- World quests and bonus objectives, scenarios, achievements, endeavors and tracked recipes
  have no section. Most need APIs these clients do not have.
- **No Find Group button.** These clients have no group finder for quests.
- **No party progress on hover.** These clients do not give addons your party's progress on a
  quest.
- The zone progress bar stays empty. Its zone routing data covers Midnight only, and Everything
  Quests counts zones for it on WoW Forever alone so far.
- **Distances need Everything Quests** (2.14.0 or later), for the Distance sort order and for Show
  distance after quest titles, since these clients cannot measure how far away a quest is. Without
  it the Distance order does nothing and no distance shows.
- Some options still appear that cannot do anything on Classic, for the same reasons.

### Questie

If Questie is loaded, EQ Objective Tracker offers once to hide Questie's own tracker, and
that choice becomes a permanent toggle on the General tab. It only hides the frame, and
Questie's own disable path is never called. The game blocks hiding it during a fight, so
if Questie shows its tracker then, it is hidden again as soon as the fight ends.

Tracking and untracking from this tracker's row menu go through its own list rather than the
game's watch functions, so the hooks Questie places on those do not fire for anything you do
here.

### Shortest Path Forever

On WoW Forever, Shortest Path Forever 1.22.35 or later puts its journey column right under the
tracker's quests, or above or beside the tracker when there is no room below, and moves it as the
list grows and shrinks. With Background or Border on, move mode's outline showing, or the button
bar at the bottom of the tracker, it keeps clear of the whole tracker box. An older version draws
the column over the quests, so update it.

### EllesmereUI

On WoW Forever, EllesmereUI's Custom Quest Tracker option draws a quest tracker window of its own
instead of using the game's tracker. While this tracker's window is in use, EQ Objective
Tracker asks EllesmereUI to hide that window, through the call EllesmereUI uses for the same thing
itself, so the two do not sit side by side. It waits for a fight to end before asking. With Use
Blizzard's quest tracker on, EllesmereUI's tracker is left alone. Without that option, EllesmereUI
uses the game's tracker, which this addon hides already.

### Everything Quests, the companion addon

Everything Quests adds the other half of the picture, map pins and a TomTom waypoint arrow
among them. It carries the quest database, so it is what turns a focused row into an arrow, and
on WoW Forever it is what counts a zone's quests for the zone progress bar. On Classic Era and
TBC Anniversary it is what tells the Distance sort order, and the distance after a quest's title,
how far away each quest is.
Its Classic support is still growing - check its own page for what it covers today.
Installing it pulls this tracker in automatically. Without it, this addon is the tracker only.

If you already ran Everything Quests, your tracker settings are imported the first time this
addon loads, so it starts out looking the way yours already did. Your per-character state
comes across too, on every character: pinned quests, collapsed sections and saved world
quest watches.

### Using the game's own tracker instead

If you would rather keep the game's own quest tracker, tick **Use Blizzard's quest tracker** at
the top of the General tab. Everything Quests has the same checkbox in the Tracker section of its
own General tab. The interface reloads, the EQ Objective Tracker window is gone, and the game's
tracker is back. The parts of this addon that do not need the window keep working, including the
quest sounds, the flight point highlight, the zone progress bar, which floats on its own then, and
on WoW Forever the TomTom arrow Everything Quests draws for the quest you follow. Settings for the
window itself, such as its hide rules, the bonus objectives HUD and hiding Questie's tracker, wait
until you switch back, and so do Keep focused quest after relog and Focus newly accepted quests, so
the game focuses each quest you accept as usual. Untick it to get the window back, again after a
reload.

On retail and WoW Forever both trackers use the game's own list of tracked quests. On Classic Era
and TBC Anniversary the game's tracker starts empty, so shift-click quests in the quest log to
watch them, up to the game's limit of five. This tracker's own list is kept for when you switch
back.

## What it tracks

- **Quests and Campaign**, in separate sections, with objectives, completion, and Find
  Group on any quest the game will form a group for, both as a button on the row and on the
  right-click menu. With zone headers on, both sections group their quests under a header for
  each quest log heading (the zone, for most quests), each header collapsing on its own. An
  optional Dungeons header gathers every dungeon quest in one place, with or without zone headers.
  A timed quest counts down on its row, in seconds through the last minute, and on retail and WoW
  Forever `/eqot timer test` puts a two-minute sample on one so you can see it
- **World quests** in their own capped area, with the quest type on the marker, a
  color-coded countdown, and the same Find Group button and menu item where the game allows
  one. Every world quest in your current zone is listed, not only the ones you have tracked,
  which you can turn off. Pick one on the world map and it stays on the tracker wherever you
  go, for as long as it is the quest you are following
- **Bonus objectives**, in a section of their own the way the default tracker gives them one.
  They appear when you walk into one and go away when you leave, and they have their own
  filter, so you can turn them off without touching world quests
- **Scenarios and delves**, with the stage banner (shrunk to fit a narrow tracker, or swapped
  for one plain line if you prefer), its criteria, the stage countdown, the
  delve tier, and a clickable button for any spell the stage hands you. Two switches, on by
  default, put the lives left and the nemesis groups killed on the tier's row, from Tier 4 up,
  with the game's own icons and tooltips
- **Mythic+ keys**, with the key's own panel in the stage banner's place: the keystone level,
  the affixes, the time left with the +3 and +2 times, and the deaths. It has a switch on the
  Tracker tab for anyone using a separate timer addon, and `/eqot mplus test` draws a sample key.
  It could not be tested in a real key before release, so please report anything that looks
  wrong, with what `/eqot mplus` prints during the key
- **The bonus objectives HUD**, a separate movable readout rather than a tracker section,
  covering the bonus loot mechanics inside a delve and a lives and deaths readout for the run.
  Its background and its border are yours to recolor, or to switch off entirely and leave the
  text floating. Off by default
- **Achievements**, **professions** with reagent counts, and **endeavors**, covering both the
  Traveler's Log monthly activities and the neighborhood tasks you have tracked, which the
  default tracker draws together under that same header
- **Progress bars** for objectives that report a percentage or a running total, drawn the way
  the default tracker draws them with the objective's own text on the line above the bar. Quest
  rows and scenario criteria each have their own switch, and the bar's texture, fill color,
  background, border and height are all yours to set
- **Quest items**, as a button on the row of any quest that carries one
- **Elite quests and quest types** on WoW Forever, Classic Era and TBC Anniversary, as WoW Forever's
  own tracker shows them: the quest's type after its title in the game's own words, such as (Elite),
  (Dungeon), (Raid) or (PvP), with (Group) in place of (Elite) on TBC Anniversary, and an elite
  quest's level as [21+] with the level prefix on
- **Hand-in text** on a quest ready to turn in: one line in place of its finished objectives saying
  where to hand it in, in the game's own words on retail and WoW Forever, or Ready for turn-in where
  the game has none, and Failed in red on a failed quest. On by default
- **XP and distance after a quest's title**, in gray, such as (450 XP, 120 yd), each behind its own
  box on the Tracker tab and off by default. The distance follows you as you move and leaves the
  order of your quests alone, and on Classic Era and TBC Anniversary it needs Everything Quests.
  Neither shows on world quests or bonus objectives
- **Quest popups** for newly discovered quests and ones ready to hand in remotely
- **Hover any quest** for its objectives and full rewards, including item level
  comparisons against what you have equipped. World quests and timed quests also show their
  faction and how long is left. With Show the quest text in its tooltip on, a quest's tooltip also
  shows the quest log's own text: the short paragraph saying what to do and who to go back to, and
  the quest's story

Also included: a zone progress bar, five optional sounds (when you accept a quest, when one of its
objectives moves forward, when one of them is finished, when its last objective falls, and when you
hand it in, the middle three playing only the biggest at once), on the game volume slider you pick
and from any sound other addons share through LibSharedMedia, a highlight on the flight point nearest your
tracked quest, and the extra bars and status lines the default tracker shows during world
events, which would otherwise not appear anywhere.

## Usage

| Command | Effect |
|---|---|
| `/eqot` | Open the options panel |
| `/eqot lock` / `unlock` | Lock or unlock moving and resizing |
| `/eqot reset` | Restore the default position and size |
| `/eqot toggle` | Show or hide the tracker |
| `/eqot whatsnew` | Open the What's New window |
| `/eqot status` | Print what each provider emitted and what reached the screen |
| `/eqot bonushud` | Print what the bonus objectives HUD can see, or `test` to place it |
| `/eqot mplus` | Print what the tracker read for the current Mythic+ key, or `test` or `late` to draw a sample key |
| `/eqot popup` | Print the quest popups the tracker read, or `test` to draw a sample Quest Discovered box |
| `/eqot timer` | Print the quest timers the tracker read, or `test` to put a two-minute sample on a quest (Retail and WoW Forever) |
| `/eqot importeq` | Replace this profile with your Everything Quests tracker settings |
| `/eqot modules` | List the optional parts, and which are switched off |
| `/eqot disable <name>` | Switch off one part, or `all`, to narrow down a fault |
| `/eqot enable <name>` | Switch a part back on, or `all` |
| `/eqot debug` | Toggle entry validation warnings |

The options window, opened with `/eqot` or the cogwheel on the tracker's header, has a sidebar
with four tabs, General, Tracker, Appearance and About, each laid out in cards. To hide the
cogwheel, untick Show the options cogwheel on the tracker on the Tracker tab, and `/eqot` still
opens the window. The Appearance tab
draws a sample tracker beside its settings that changes as you adjust them. A search field at the
top of the sidebar finds any setting as you type: each match shows its tab and card, and clicking
one opens that tab, scrolls to the setting and flashes it. Drag the window by its title bar and it
can hang partly off the left, right or bottom edge of the screen, part of its title bar kept on screen. It
opens where you left it on every character, and Reset all settings puts it back in the middle.

After an update that brings new features, a What's New window opens a few seconds after you log
in and lists every update since the last one you read, newest first, so from 2.15.0 on a player
who skips a few catches up on all of them. Updates without new features stay quiet and are
listed in the next window, and a fresh install opens nothing. The Updates card on the General tab
sets what happens after an update, a Popup window, a Chat link or Off, for every character on the
account, and the first window starts with a short note and a button that opens that setting. `/eqot whatsnew`, the
card's Show What's New button and the About tab's What's New button open the window any time.

While the tracker is unlocked, drag the strip along the top to move it and the corner grip to
resize it. With the options window open, or after an unlock, that strip turns gold with a check
button that locks the tracker again, and a gold outline shows its edges. Right-click the strip or
the cogwheel for Unlock or Lock position, Reset position and size, and Open the options panel. The
strip is the tracker's button bar: the cogwheel sits at its right end and the sort and filter
buttons at its left. Show the button bar at the bottom of the tracker, on the Tracker tab's Headers
and Buttons card, moves it to the bottom edge beside the corner grip, so the quests start at the
very top and the tracker can sit flush against the top of the screen. On Grow upward the corner
grip sits at the top instead, just above the quests. Show the buttons only on
mouseover, on the same card, hides the cogwheel, the sort and filter buttons, the quest log count and
other addons' buttons until you point at the bar. Show the quest log count on the tracker, on the
same card, puts how many quests your log holds and how many it can, such as 14/25, at the bar's
left end, red once the log is full. Button Size, the card's last row, sets the size of every button on
the bar, from 10 to 24. The bar is sized to fit them, and the count grows with larger buttons.

Tracker Growth, on the Appearance tab's Tracker card, decides how the box sizes itself. Fixed size,
the default, keeps the size you set with the corner grip. Grow downward and Grow upward fit the box
to its quests and grow it from its top or bottom edge, never past the size you set with the grip or
the edge of the screen, so Background and Border hug the quests and a tracker at the bottom of the
screen keeps its bottom edge where you put it. On Grow upward the grip moves to the top right
corner, and the box waits for the mouse to leave before it changes size, so a header you click stays
under the cursor. While the tracker is unlocked and the options window is open, or from an unlock
until the next lock, the box shows its full size and its corner grip, which is hidden on a fitted
box. `/eqot status` has a growth line.

Tick Show the sort button on the tracker, on the Tracker tab, for a small button at the left end of
the button bar that opens a list of the sort orders, so switching between Level and Distance, or any other
two, takes two clicks. Pick the order already in use again to reverse it, so Level runs from
highest to lowest or Distance from farthest to nearest, and once more to turn it back. Every order
but Zone and Manual can be reversed, the button's tooltip says when one is, and picking another
order or hiding the button turns the reverse off. Show the filter button on the tracker adds a funnel beside it whose list
holds Show only quests in current zone, the quest types, the zones in your quest log and Reset
filters to defaults, and stays open while you change them. Untick a zone to hide its quests until
you tick it again or its last quest leaves your log. The Hide zones button on the Filters card opens
the same list. The funnel turns gold while any of them is set to hide quests. While
To-Do Mode is on, the list leaves out the current-zone line and that box no longer turns the funnel
gold, since the mode decides which quests are in your zone.
On retail, Show section tabs on the Section Order card splits the tracker into up
to three tabs. The number beside each section picks its tab, and once two tabs hold a section a
strip under the top of the tracker switches between them. The scenario panel shows on every tab,
and so does a quest popup box, under its own section's header, and each character keeps the tab it
was on. The Section Tabs card on the Appearance tab styles the strip: the line under the tab you
are on, the line under the others, the fills, the names' colors and size, and the tab height.
Left-click a quest to super-track it on retail and WoW Forever, or to focus it on Classic. On
retail and WoW Forever two options on the Tracker tab change how focusing works: Click a focused quest
to unfocus it makes a click on the quest you are following unfocus it, and turning off Focus newly
accepted quests stops the game focusing each quest you accept while nothing is focused. With Split
quest click on, clicking a quest's icon focuses it and clicking its title opens it in the quest log,
and a second click on the title closes the map, or the quest log on Classic, again. Clicking another
quest's title while it is open shows that quest instead. A
finished quest that is turned in from the tracker rather than at an NPC, such as a Prey hunt,
shows a click to complete line, and left-clicking it should open the reward window instead. That last part could
not be tested on a finished hunt before release, so please report anything that looks wrong.
Shift-click a quest
while a chat box is open to drop it into chat, or with no chat box open to untrack it. Right-click
opens a menu to pin, fold it to its title, track, focus, open the quest log, pop out the details,
find a group, share it with your group, look the quest up on Wowhead, or abandon it - the Classic
menu is shorter, since those clients have no group finder for quests and no pop-out details window. Share Quest
shows while you are in a group, on a quest the game lets you share, and Abandon Quest asks first
with the game's own confirmation. Neither works from the tracker during a fight, and each says so in
chat. On retail and WoW Forever, hovering a quest while you are in a group also lists your party
members' progress on it, as Blizzard's quest log does. A pinned quest stays
on the tracker whatever your filters say. In manual sort mode you can also drag quests into
whatever order you like, and with zone headers on a quest moves within its own zone, as a dungeon
quest does within the Dungeons header.

Most settings that only apply while another one is on are dimmed while that one is off, so it
is clear which settings are actually in effect. Always show campaign quests is the exception: it
stays lit, and only acts while Show only quests in current zone is on. The zone label box on the
Tracker tab works the other way around: it is dimmed while zone headers are on, since the header
above a quest already names its zone, and lit again while the Dungeons header is on too, since a
quest under that header keeps its label. Hide finished objectives is dimmed while Simplify Mode
is on, since Simplify Mode already shows only the first objective left.

Any quest can be folded down to its title: Minimize Quest and Maximize Quest in its right-click
menu, a + at the end of a folded quest's title line, and, with Show a +/- on each quest ticked, a -
on every quest you can fold. Shift-click a zone or section header to fold or open every quest
under it. Auto minimize finished quests folds each finished quest to its title and (Complete),
leaving open any you open again and any you can hand in by clicking it. Both boxes are off by
default, and folds are saved per character until the quest is handed in or abandoned.

The tracker can hide itself while you are in combat, inside an instance, on a Mythic+ run,
while the world map is open, or while you have no quests showing. Each is its own toggle, and
all are off by default. The last of those counts quest and campaign rows only, so nothing else
keeps the tracker on screen by itself, including world quests, achievements, the zone progress
bar, and the delve or scenario panel.

Almost everything is configurable: fonts (42 bundled, plus anything from LibSharedMedia, each
shown in its own typeface in the picker; a Russian game client offers the 25 with Russian letters,
and a Korean or Chinese client none, so the game's own fonts stay in use there), sizes, spacing, colors, opacity (back to full under
the mouse, with the quest you are following kept solid), a background that fades in while the
mouse is over the tracker, at an opacity you pick, the progress bars, the scroll bar's
width and texture, a card layout that can wrap the delve and scenario panel as well as your quests, section
order, visibility and tabs, filters by quest type, finished objectives hidden or shown, and nine sort modes including by distance, by progress and by hand, all but Zone and Manual reversible from
the sort button.
The current-zone filter shows only quests with an objective on the map you are standing on.
If that map lists none of its own, such as a building interior, a covenant sanctum or a
dungeon, it asks the zone around it instead, so you still get that zone's quests rather
than an empty tracker. On Classic Era and TBC Anniversary, where quest log headings are zone
names, it shows the quests under your zone's heading, and on WoW Forever a quest under that
heading counts as well. On retail, an option keeps your campaign quests on screen from every
zone while that filter is on.

To-Do Mode, off by default and switched on from its own card on the Tracker tab, turns the
Quests header, and the Campaign header on retail, into four counts: your unfinished quests in the
zone you are in, the ones ready to turn in there, every quest there and every quest you have.
Click a count and the section shows exactly those quests, with the count you picked underlined. It starts on your unfinished quests in
the zone, which is the short to-do list it is named for, and each character remembers the count it
picked. While it is on it decides which quests are in your zone, so Show only quests in current
zone is dimmed and keeps your own setting for later, while the quest type filters, Show only
tracked quests, pinned quests and the other sections stay as they are. Always show campaign quests
keeps working too, so your campaign quests from other zones show, and count, in the views for your
zone. The card can hide any of the four counts, color each one, with the Class button, and size them.
Hiding the box of the count you picked keeps that view, with nothing underlined. Unticking Show
section names leaves only the counts on those headers, without the words Quests and Campaign (zone
headers keep theirs), and the Header Size Offset button beside it opens the slider that makes the
words smaller instead. The counts follow that slider, and Count Size Offset sizes them back.

Quest titles can be colored by difficulty, all in gold, in your class color, in a color you pick,
or in Original Style, the way the game's own tracker colors them on your version of the game. The
objective text, a count like 0/5 as it goes from none done to in progress, half done, mostly done
and done, finished
objectives, the title of a finished quest and the NEW tag on quests you accepted in the last hour
can each be given their own color as well. A Class button beside almost every color, from the
tracker's background to the scroll bar, makes that color follow your class color instead, at the
opacity you picked. Section headers can also stay at the top of
the list while you scroll through their section, and with zone headers on, the header of the zone
you are scrolled into stays just under them, so you can always see where you are.

Zone headers, off by default and switched on from the Appearance tab, group the quests in the
Quests and Campaign sections under the quest log heading each one sits under, which is its zone for
most quests. Each zone shows a count and collapses on its own. The zones with a quest on the map
you are in can come first, with the rest in quest log order, or every zone can be listed in
alphabetical order, and quests inside a zone still follow the sort order. The headers have a look
of their own: a size, a color or your class color, an optional bar and divider line, and how far
the quests under them are moved in. On Classic Era and TBC Anniversary they group the Quests
section.

A Dungeons header, also off by default and on the Appearance tab's Zone Headers card, gathers every
quest the game marks as a dungeon quest, heroic ones included, under one header of its own. With
zone headers off, your other quests stay as they are and the Dungeons header comes after them.
With zone headers on, dungeon quests leave their zones for it, and under the current-zone-first
order it moves to the top while one of its quests is on the map you are in, unless Keep Dungeons at
the bottom is ticked. A quest under it keeps its zone label, if you show zone labels, so you can
tell which dungeon it is for.

Settings live in profiles, so you can keep separate setups and switch between them.
Profiles are shared across all your characters.

## Translations

Every file in `Locales/` is generated, including the `enUS.lua` phrase list. The translations
live in [EverythingLocales](https://github.com/wheelbarrel00/EverythingLocales), shared
across all of this author's addons so that a phrase more than one of them uses is only ever
translated once, and so that a phrase moving between addons keeps its translation.

**To add or correct a translation, edit `store/<language>.lua` there and open a pull request
against that repository.** A change made in this repo is overwritten the next time the files
are built. GitHub will not accept a `.lua` file as a comment attachment, so put it in a `.zip`
first or paste it into a code block. If you cannot use GitHub at all, the Discord and the
CurseForge comments both work - the Simplified Chinese arrived over Discord and the Traditional
Chinese over CurseForge.

A phrase that has not been translated yet falls back to English on its own, so a partial
translation is never a broken one, and there is no need to finish a language.

A new language needs adding to that repo's language list, and its `Locales/<code>.lua` listed
in every `.toc` file here.

Every non-English string in this addon is somebody else's work. Thanks to **Zox** for the
French, **Malevi4** for the Russian, **labrie75** for the Korean, **失眠啤酒** for the
Simplified Chinese, **BNS333** for the Traditional
Chinese, and **Stonetwist** for the German.

## Building

There is no build step. The repository is the addon - clone it straight into
`Interface\AddOns\EQObjectiveTracker`, or junction it there.

Releases are produced by the [BigWigs packager](https://github.com/BigWigsMods/packager)
on an annotated `v` tag. A tag whose name carries a prerelease suffix, such as
`v1.4.0-beta1`, publishes to the beta channel instead.

## Extending it

Another addon can add its own entries to a quest's right-click menu and its own icons to the
tracker header, follow whichever quest is focused, keep its own frames clear of the quest
list, count a zone for the zone progress bar, and say how far away each quest is where the game
cannot, through the global `EQObjectiveTracker`:

```lua
local API = EQObjectiveTracker:GetModule("API")
API:AddMenuItem{ id = "mine", providerID = "quests", label = "Do a thing", order = 35,
                 onClick = function(providerID, questID) end }
API:AddHeaderIcon{ id = "mine", texture = [[Interface\Icons\INV_Misc_QuestionMark]],
                   tooltip = "Do a thing", order = 20, onClick = function() end }
API:AddFocusListener{ id = "mine",
                      onFocus = function(providerID, questID) end }
API:AddLayoutListener{ id = "mine", onLayout = function() end }
local left, right, top, bottom = API:GetListBounds()
API:AddZoneCounter{ id = "mine", count = function(mapID) return done, total end }
API:ZoneCountChanged()
local shown = API:ZoneBarShown()
API:AddDistanceSource{ id = "mine", distance = function(questID) return yards end }
API:DistanceChanged()
```

A header icon's tooltip must be a string. Any other value is ignored, and the icon is added
without one.

Callbacks receive the provider ID and the entry ID, never the entry table, because entries are
rebuilt on every quest event. `onFocus` is called with a nil quest ID when the focus is
cleared. It fires on Classic Era and TBC, where the tracker owns the focus, and on WoW Forever,
where it follows the quest you super-track and fires again when you click the quest you already
follow, or with a nil quest ID when Click a focused quest to unfocus it is on, since that click
clears the focus. On retail it never fires. `/eqot status` reports what is registered. Everything Quests uses this
for two header icons, its Chain Guide and its own options, for its "Get Directions" and "Open
Chain Guide" menu entries, and for its TomTom arrow.

`GetListBounds` returns the left, right, top and bottom of what the tracker draws, in UIParent
units, or nil while it is hidden or the game's own tracker is in use. The bottom is where the
last quest ends, or the world quests under them, not the bottom of the window, unless
Background, Border or move mode's outline is on or the button bar sits at the bottom. `onLayout` is called with no arguments a frame
after the list moves, changes size, or is hidden or shown, only when the answer changed, and
once more after any listener is added, so read `GetListBounds` from it. `RemoveLayoutListener(id)` takes a
listener back, as `RemoveFocusListener(id)` does. Shortest Path Forever uses these to keep its
journey column clear of the list.

`count` is called with the uiMapID of the zone the player is in (a cave or building gives the
zone around it, and a map with no zone above it gives its own) and returns how many of its
quests are done and how many there are, or nil for a zone it does not know, which passes the
zone to the next counter and then to the tracker's own Midnight count.
Counters are asked first, and numbers are final: a total of 0 shows no bar. A counter that
raises, or returns anything but two numbers with a finite total of 0 or more, counts as nil, and
`/eqot status` names the raise. Fractions are rounded down. The answer is kept until the zone
changes, a loading screen ends, a quest is turned in or removed, the game's questlines update, a
counter is added or removed, or `ZoneCountChanged()` is called, which drops the kept answer a
frame later however many times it was called, so call it after your own data has caught up.
Never call it from inside `count`, or the count is redone every frame. `RemoveZoneCounter(id)`
takes a counter back.
`ZoneBarShown()` returns true while Show zone progress bar is on and false while it is off. It
reads the option when called, so it stays true in an instance or a zone with no count.
Everything Quests uses these on WoW Forever, where the game has no questlines to count.

`distance` is called with a quest ID and returns how many yards away the quest's nearest point is
(an objective, or where it is handed in once finished), or nil when it does not know or the quest
is on another continent, which sorts the quest last. Sources are asked only on versions of the game
with no distance of their own (Classic Era and TBC Anniversary), only while the sort order is
Distance or Show distance after quest titles is on, and only for the quests that pass the tracker's
filters. The title shows the answer rounded to 10 yards, and nothing for nil. Each answer is kept until the player
moves, five seconds pass, a quest is accepted, a source is added or removed, or `DistanceChanged()`
is called, which drops the kept answers a frame later however many times it was called, so the
tracker's next redraw asks every one of those quests again. The
first number answered in registration order wins. A source that raises, or answers anything but a
finite number of 0 or more, counts as nil, and `/eqot status` names the last raise. Never call
`DistanceChanged` from inside `distance`, or the tracker re-reads and redraws without end.
`RemoveDistanceSource(id)` takes a source back. Everything Quests uses these on Classic Era and TBC
Anniversary.

## License

[MIT](LICENSE)
