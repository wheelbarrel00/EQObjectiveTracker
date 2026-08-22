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

**Retail is released and stable. Classic Era (1.15.9) and TBC Anniversary (2.5.6) are
supported.** That support is newer than the retail support and has had several rounds of
fixes, so the gaps listed below are real ones rather than a disclaimer. Please report anything
you find rather than assuming it is known.

On retail it tracks quests and campaign quests, world quests, scenarios and delves,
achievements, professions, and Traveler's Log endeavors.

### What works on Classic today

Quest tracking and the customization around it: sorting, manual drag ordering, per-quest
pinning, filters, section visibility and ordering, the card layout, fonts and colours,
profiles, row tooltips, and the row right-click menu. Blizzard's own quest watch frame is
suppressed so you do not get two trackers.

The tracker keeps its own list of which quests you are tracking rather than using the game's,
which on these versions is capped at five quests and cannot track a quest automatically when
you accept it. So "Auto-track accepted quests" works, "Show only tracked quests" can show more
than five, and shift-clicking a row in the game's own quest log tracks and untracks exactly as
it always did, with its checkmarks showing this tracker's list.

You can also focus a quest, which these clients have no super-tracking for. Click a row's
icon to focus it and click the icon again to clear it, or use Focus in the right-click menu.
The focused quest's title is tinted. If Everything Quests and TomTom are both installed,
focusing a quest also points a TomTom arrow at it.

### What is missing or limited on Classic

- **No map pins.** Those come from the companion addon - see below. The TomTom arrow needs it
  too, so on the tracker alone a focused quest is the tint and nothing more.
- World quests, scenarios, achievements, endeavors and tracked recipes have no section.
  Most need APIs these clients do not have.
- **Timed quests show no countdown**, and Blizzard's own timer box is left on screen.
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
comes across too, on every character: pinned quests, hidden quests, collapsed sections and
saved world quest watches.

## What it tracks

- **Quests and Campaign**, in separate sections, with objectives, completion, and a Find
  Group button on any quest the game will form a group for
- **World quests** in their own capped area, with the quest type on the marker, a
  colour-coded countdown, and a Find Group button where the game allows one. Every world
  quest in your current zone is listed, not only the ones you have tracked, which you can
  turn off
- **Scenarios and delves**, with the stage banner, its criteria, the stage countdown and
  the delve tier
- **Bonus objectives**, on their own movable HUD, including the bonus loot
  mechanics inside a delve. Off by default
- **Achievements**, **professions** with reagent counts, and **endeavors**
- **Progress bars** for objectives that report a percentage or a running total, the way the
  default tracker draws them, which you can turn off
- **Quest items**, as a button on the row of any quest that carries one
- **Quest popups** for newly discovered quests and ones ready to hand in remotely
- **Hover any quest** for its objectives and full rewards, including item level
  comparisons against what you have equipped. World quests also show their faction and
  how long is left

Also included: a zone progress bar, a sound when a quest is ready to turn in, a highlight on
the flight point nearest your tracked quest, and the extra bars and status lines the default
tracker shows during world events, which would otherwise not appear anywhere.

## Usage

| Command | Effect |
|---|---|
| `/eqot` | Open the options panel |
| `/eqot lock` / `unlock` | Lock or unlock moving and resizing |
| `/eqot reset` | Restore the default position and size |
| `/eqot toggle` | Show or hide the tracker |
| `/eqot unhide` | Bring back every entry you have hidden from the tracker |
| `/eqot status` | Print what each provider emitted and what reached the screen |
| `/eqot bonushud` | Print what the bonus objectives HUD can see, or `test` to place it |
| `/eqot importeq` | Replace this profile with your Everything Quests tracker settings |
| `/eqot modules` | List the optional parts, and which are switched off |
| `/eqot disable <name>` | Switch off one part, or `all`, to narrow down a fault |
| `/eqot enable <name>` | Switch a part back on, or `all` |
| `/eqot debug` | Toggle entry validation warnings |

Drag the strip along the top to move the tracker, and the corner grip to resize it.
Left-click a quest to super-track it on retail, or to focus it on Classic, and shift-click to
hide it. Right-click opens a menu to pin, track, focus, open the quest log, pop out the
details, look the quest up on Wowhead, or abandon it - the Classic menu is shorter, since
popping out and abandoning need frames those clients do not have. A pinned quest stays on the
tracker whatever your filters say. In manual sort mode you can also drag quests into whatever
order you like.

A setting that only applies while another one is on is dimmed while that one is off, so it is
clear which settings are actually in effect.

The tracker can hide itself while you are in combat, inside an instance, on a Mythic+ run,
or while the world map is open. Each is its own toggle, and all are off by default.

Almost everything is configurable: fonts (42 bundled, plus anything from
LibSharedMedia, each shown in its own typeface in the picker), sizes, spacing, colours, a
card layout, section order and visibility, filters by quest type, and eight sort modes
including by distance and by hand. The current-zone filter shows only quests with an objective
on the map you are standing on, so somewhere with no quests of its own, such as a capital city,
reads empty while that filter is on.

Settings live in profiles, so you can keep separate setups and switch between them.
Profiles are shared across all your characters.

## Translations

Every file in `Locales/` is generated, including the `enUS.lua` phrase list. The translations live in
[EverythingLocales](https://github.com/wheelbarrel00/EverythingLocales), shared across all of
this author's addons so that a phrase more than one of them uses is only ever translated once,
and so that a phrase moving between addons keeps its translation.

**To add or correct a translation, edit `store/<language>.lua` there and open a pull request
against that repository.** A change made in this repo is overwritten the next time the files
are built. GitHub will not accept a `.lua` file as a comment attachment, so put it in a `.zip`
first or paste it into a code block. If you cannot use GitHub at all, the Discord and the
CurseForge comments both work - the Simplified Chinese arrived over Discord and the Traditional
Chinese over CurseForge.

A phrase that has not been translated yet falls back to English on its own, so a partial
translation is never a broken one, and there is no need to finish a language.

A new language needs adding to that repo's language list, and its `Locales/<code>.lua` listed
in all four `.toc` files here.

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
cleared, and only fires on clients with no super-tracking of their own, which today means
Classic Era and TBC. `/eqot status` reports what is registered. Everything Quests uses this
for its Chain Guide icon, its "Get Directions" menu entry, and its TomTom arrow.

## License

[MIT](LICENSE)
