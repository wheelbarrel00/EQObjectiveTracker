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

**Retail, Classic Era (1.15.9) and TBC Anniversary (2.5.6) are all supported.** The Classic
gaps listed below are real ones rather than a disclaimer. Please report anything you find
rather than assuming it is known.

**WoW Forever support is a work in progress, so expect bugs.** The tracker shows your quests
there, and with Everything Quests and TomTom installed the quest you are following gets a TomTom
arrow, as on Classic. The retail-only sections, such as world quests and scenarios, have stayed empty
there so far.

On retail it tracks quests and campaign quests, world quests and bonus objectives, scenarios
and delves, achievements, professions, and endeavors, covering both the Traveler's Log monthly
activities and the neighborhood tasks you have tracked.

### What works on Classic today

Quest tracking and the customization around it: sorting, manual drag ordering, per-quest
pinning, filters, section visibility and ordering, the card layout, fonts and colors,
profiles, row tooltips, and the row right-click menu. Blizzard's own quest watch frame is
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
- The zone progress bar stays empty. Its zone routing data covers Midnight only.
- Distance sorting does nothing, because the distance API is retail-only.
- Some options still appear that cannot do anything on Classic, for the same reasons.

### Questie

If Questie is loaded, EQ Objective Tracker offers once to hide Questie's own tracker, and
that choice becomes a permanent toggle on the General tab. It only hides the frame, and
Questie's own disable path is never called.

Tracking and untracking from this tracker's row menu go through its own list rather than the
game's watch functions, so the hooks Questie places on those do not fire for anything you do
here.

### Everything Quests, the companion addon

Everything Quests adds the other half of the picture, map pins and a TomTom waypoint arrow
among them. It carries the quest database, so it is what turns a focused row into an arrow.
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
until you switch back. Untick it to get the window back, again after a reload.

On retail and WoW Forever both trackers use the game's own list of tracked quests. On Classic Era
and TBC Anniversary the game's tracker starts empty, so shift-click quests in the quest log to
watch them, up to the game's limit of five. This tracker's own list is kept for when you switch
back.

## What it tracks

- **Quests and Campaign**, in separate sections, with objectives, completion, and Find
  Group on any quest the game will form a group for, both as a button on the row and on the
  right-click menu
- **World quests** in their own capped area, with the quest type on the marker, a
  color-coded countdown, and the same Find Group button and menu item where the game allows
  one. Every world quest in your current zone is listed, not only the ones you have tracked,
  which you can turn off. Pick one on the world map and it stays on the tracker wherever you
  go, for as long as it is the quest you are following
- **Bonus objectives**, in a section of their own the way the default tracker gives them one.
  They appear when you walk into one and go away when you leave, and they have their own
  filter, so you can turn them off without touching world quests
- **Scenarios and delves**, with the stage banner, its criteria, the stage countdown, the
  delve tier, and a clickable button for any spell the stage hands you
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
- **Quest popups** for newly discovered quests and ones ready to hand in remotely
- **Hover any quest** for its objectives and full rewards, including item level
  comparisons against what you have equipped. World quests also show their faction and
  how long is left

Also included: a zone progress bar, three optional sounds (when you accept a quest, when its
last objective falls, and when you hand it in), a highlight on the flight point nearest your
tracked quest, and the extra bars and status lines the default tracker shows during world
events, which would otherwise not appear anywhere.

## Usage

| Command | Effect |
|---|---|
| `/eqot` | Open the options panel |
| `/eqot lock` / `unlock` | Lock or unlock moving and resizing |
| `/eqot reset` | Restore the default position and size |
| `/eqot toggle` | Show or hide the tracker |
| `/eqot status` | Print what each provider emitted and what reached the screen |
| `/eqot bonushud` | Print what the bonus objectives HUD can see, or `test` to place it |
| `/eqot importeq` | Replace this profile with your Everything Quests tracker settings |
| `/eqot modules` | List the optional parts, and which are switched off |
| `/eqot disable <name>` | Switch off one part, or `all`, to narrow down a fault |
| `/eqot enable <name>` | Switch a part back on, or `all` |
| `/eqot debug` | Toggle entry validation warnings |

The options window, opened with `/eqot` or the cogwheel on the tracker's header, has a sidebar
with four tabs, General, Tracker, Appearance and About, each laid out in cards. To hide the
cogwheel, untick Show the options cogwheel on the tracker on the Tracker tab, and `/eqot` still
opens the window. The Appearance tab
draws a sample tracker beside its settings that changes as you adjust them.

Drag the strip along the top to move the tracker, and the corner grip to resize it.
Left-click a quest to super-track it on retail and WoW Forever, or to focus it on Classic. A
finished quest that is turned in from the tracker rather than at an NPC, such as a Prey hunt,
shows a click to complete line, and left-clicking it should open the reward window instead. That last part could
not be tested on a finished hunt before release, so please report anything that looks wrong.
Shift-click a quest
while a chat box is open to drop it into chat, or with no chat box open to untrack it. Right-click
opens a menu to pin, track, focus, open the quest log, pop out the details, find a group, look
the quest up on Wowhead, or abandon it - the Classic menu is shorter, since those clients have no
group finder and popping out and abandoning need frames they do not have. A pinned quest stays
on the tracker whatever your filters say. In manual sort mode you can also drag quests into
whatever order you like.

Most settings that only apply while another one is on are dimmed while that one is off, so it
is clear which settings are actually in effect. Always show campaign quests is the exception: it
stays lit, and only acts while Show only quests in current zone is on.

The tracker can hide itself while you are in combat, inside an instance, on a Mythic+ run,
while the world map is open, or while you have no quests showing. Each is its own toggle, and
all are off by default. The last of those counts quest and campaign rows only, so nothing else
keeps the tracker on screen by itself, including world quests, achievements, the zone progress
bar, and the delve or scenario panel.

Almost everything is configurable: fonts (42 bundled, plus anything from LibSharedMedia, each
shown in its own typeface in the picker), sizes, spacing, colors, opacity (back to full under
the mouse, with the quest you are following kept solid), the progress bars, a card
layout that can wrap the delve and scenario panel as well as your quests, section order and
visibility, filters by quest type, and eight sort modes including by distance and by hand.
The current-zone filter shows only quests with an objective on the map you are standing on.
If that map lists none of its own, such as a building interior, a covenant sanctum or a
dungeon, it asks the zone around it instead, so you still get that zone's quests rather
than an empty tracker. On retail, an option keeps your campaign quests on screen from every
zone while that filter is on.

Quest titles can be colored by difficulty, all in gold, in your class color, in a color you pick,
or in Original Style, the way the game's own tracker colors them on your version of the game. The
objective text, a count like 0/5 as it goes from none done to in progress to done, and finished
objectives can each be given their own color as well. Section headers can also stay at the top of
the list while you scroll through their section, so you can always see which one you are in.

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
tracker header, and follow whichever quest is focused, through the global `EQObjectiveTracker`:

```lua
local API = EQObjectiveTracker:GetModule("API")
API:AddMenuItem{ id = "mine", providerID = "quests", label = "Do a thing", order = 35,
                 onClick = function(providerID, questID) end }
API:AddHeaderIcon{ id = "mine", texture = [[Interface\Icons\INV_Misc_QuestionMark]],
                   tooltip = "Do a thing", order = 20, onClick = function() end }
API:AddFocusListener{ id = "mine",
                      onFocus = function(providerID, questID) end }
```

Callbacks receive the provider ID and the entry ID, never the entry table, because entries are
rebuilt on every quest event. `onFocus` is called with a nil quest ID when the focus is
cleared. It fires on Classic Era and TBC, where the tracker owns the focus, and on WoW Forever,
where it follows the quest you super-track and fires again when you click the quest you already
follow. On retail it never fires. `/eqot status` reports what is registered. Everything Quests uses this
for two header icons, its Chain Guide and its own options, for its "Get Directions" menu entry,
and for its TomTom arrow.

## License

[MIT](LICENSE)
