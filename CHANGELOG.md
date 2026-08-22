# Changelog

All notable changes to EQ Objective Tracker will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.12.0] - 2026-08-21

Answers a report from Souseiseki87 about the World Quests panel, and about information that
goes missing during scenarios, delves and the events that borrow the scenario panel.

### New Features

- The tracker now draws the extra bars and status lines the game's own tracker shows during
  world events, delves and scenarios. Because this tracker replaces the default one, those
  were not being shown anywhere at all. A new "Show event and scenario widgets" option on the
  Tracker tab turns them off.
- Scenario countdowns are shown again, under the stage banner, where the default tracker puts
  them. The Curse Surge on The Coiled Isle is one of these.
- A delve's tier is on screen again. The changelog for 1.9.1 said it would come back and this
  is that.
- Objectives that report a percentage or a running total now draw a filled bar instead of a
  plain line of text, the way the default tracker does. Applies to quests, World Quests,
  achievements and scenario objectives. A new "Show progress bars" option turns it off. An
  objective that is really a yes or no, such as 0/1, stays as text.
- The group finder eye now appears on ordinary quests that can form a group, not only on World
  Quests. The default tracker has always shown it on both.

### Bug Fixes

- The World Quests section filled up with quests from other zones. The tracker was walking up
  the map hierarchy without a limit, which reaches the whole continent within two steps, and a
  continent lists every world quest in progress anywhere on it. It now stops at the zone.
  Reported by Souseiseki87.
- World quests in your current zone were sometimes not listed, even while you were standing in
  the quest area. The game files those quests against the zone, and reports none at all for the
  smaller maps inside it, so standing in a cave or a building meant an empty list. The tracker
  now asks the zone around it, and only when the map you are on lists nothing of its own.
  Reported by Souseiseki87.
- A tracked world quest with no expiry timer, such as a lair, disappeared from the tracker. It
  was being treated as an expired quest that had not been cleaned up. Having no timer and
  having run out of time are not the same thing, and the tracker now checks whether the quest
  is still on the map or still in your log before dropping it.
- Known, and the next thing being fixed: inside a delve or another instance, a tracked world
  quest that has no expiry timer drops off the list until you leave, and comes back on its own
  once you are outside. The tracker asks whether the quest is on the map you are standing on,
  and inside an instance nothing can answer that, so it reads as gone. Nothing is lost while it
  is hidden.

## [1.11.1] - 2026-08-20

A hotfix for two quest tracker problems, one of them introduced by 1.11.0.

### Bug Fixes

- Opening the world map could put a line in your chat naming this addon next to a game function
  called Button:SetPassThroughButtons. It affected anyone with "Hide tracker when world map is
  open" switched on, and it was new in 1.11.0. The tracker was hiding itself from inside the
  game's own map code, and now waits a moment and does it just after instead. Reported by
  DrahgunFyre.
- "Show only quests in current zone" hid your quests while you were standing in a sub-area of
  the zone they belong to, such as a covenant sanctum, a building interior or a dungeon. The
  game files quests against the zone itself and reports none at all for those smaller maps, so
  the filter saw an empty list and hid everything. When the map you are standing on has no
  quests of its own, the tracker now asks the zone around it instead. Reported by RobSaab, and
  found with his help.
- Worth knowing, since it follows from the same change: inside a dungeon or another instance
  that has no quests of its own, the tracker now lists the quests for the zone around it
  rather than reading empty. You are still in that zone, just inside something within it. A
  map that already showed quests is not affected in any way.

## [1.11.0] - 2026-08-19

Every language complete, and a long round of fixes from a full audit of the addon.

### New Features

- Scheduled quests are their own filter category. Retail has a fourth kind of quest reset
  that this addon did not recognize, so Special Assignments and some meta quests carried no
  category at all, filtered as normal quests, and sorted above weekly ones with nothing
  naming them. They now have their own checkbox and their own place in the Type sort.

### Bug Fixes

- Manual sort dropped a quest one row below the gold line it had just drawn, on every
  downward drag. Nudging a quest into the gap just below itself, which the line drew as no
  change, quietly moved it down one, so repeated drags walked it steadily to the bottom.
- Starting combat mid drag kept the tracker glued to the cursor for the rest of the fight,
  then saved wherever the cursor happened to end up as its new position.
- Hiding the tracker and then entering combat could leave it hidden: with a quest item
  button on screen, the toggle silently did nothing until the fight ended.
- The Recent sort was the same as sorting by title for every quest accepted before the
  current session, and went back to that after every reload.
- Expanding a section near the bottom of a long tracker looked like nothing happened,
  because its rows landed below the visible area. The section now scrolls into view.
- A list that got shorter, such as the World Quests area after untracking one, left blank
  space where the rows used to be until you scrolled back up.
- Quest titles colored by difficulty did not recolor when you leveled up.
- Section header bars stayed a fixed height whatever the Header Size Offset was set to, so
  large text spilled outside the bar.
- Abandoning a quest from the row menu did nothing and said nothing when it could not be
  done, most often because you were in combat. It now tells you why.
- Clicking Abandon, Focus or Pop Out no longer risks acting on a stale quest.
- The scroll bar still worked while the tracker was invisible in combat, so a click in the
  empty gutter scrolled a tracker you could not see.
- The mouse wheel stopped working over the World Quests area during combat, which it never
  needed to.
- The options window scale slider reported sizes the window could not actually take.
- Classic: shift clicking a quest in the quest log to link it in chat also toggled whether
  it was tracked.
- Classic: the tracker's own quest order grew without limit and was never trimmed.
- Classic: the World Quest and Scenario Bonus options appeared with nothing behind them.
- The two color settings that do nothing until another setting is on now dim to say so.
- The Quest Complete Sound list reads None in your own language.
- The reward tooltip rebuilt itself two and a half times a second, for as long as you hovered
  a quest whose rewards had not finished loading.
- Moving between two quests whose rewards were still loading could leave the second one
  showing no rewards at all until you moved away and hovered it again.
- Pressing Cancel on the Quest Title Color Override left "Use title color for completed
  quests" looking available when it was not.
- Hiding the scenario bonus display while hovering its reward icon could strand a tooltip on
  screen.
- A quest log that had not finished loading could drop the times quests were first seen,
  which marked quests you already had as new for an hour and put them wrong in the Recent
  sort.

### Improvements

- Every language is now fully translated. German, French, Korean, Russian, Simplified Chinese
  and Traditional Chinese all cover the whole addon, including the new scheduled quest filter.
- Turning one module back on after `/eqot disable all` now works. It reported success and
  changed nothing, which defeated the purpose of the tool.
- `/eqot status` no longer stops halfway if one part of the addon fails to report.
- Reset all settings now also clears safe mode, so an addon left switched off by
  `/eqot disable all` and forgotten about comes back.

## [1.10.0] - 2026-08-18

German, and it is the most complete translation the addon has.

### New Features

- German. The tracker and its options panel now read in German on a deDE client, covering 386
  of the addon's 390 phrases, which is the most complete translation the addon has.
  Contributed by Stonetwist.

## [1.9.1] - 2026-08-18

Two fixes for errors users reported this addon being named in.

### Bug Fixes

- Scenarios where the game supplies its own display block, which includes delves, now draw the
  addon's own stage banner instead of hosting it. Hosting it meant registering against a widget
  set the game shares with its tooltips, and that was reported breaking the next tooltip to
  close with widgets on it, with an error naming this addon that lasted until the next reload.
  Inside a delve the banner shows the stage and the delve name in the addon's own artwork now,
  and the delve tier that the game's block used to show is not drawn. Getting the tier back
  onto the banner is being worked on and is planned for the next update. The scenario banner
  font size, text shadow and alignment settings apply in these scenarios now, where before
  they did nothing. Reported on Discord.

- Blizzard's own tracker is hidden one frame after it tries to show itself now, rather than
  from inside the code that showed it. Hiding it from there could leave this addon named on a
  blocked action from Blizzard's world map quest pins, reported as "tried to call the protected
  function Button:SetPassThroughButtons()" off a stack carrying none of this addon's code. The
  tracker is still hidden, in combat as well as out of it. Reported by AIR.

## [1.9.0] - 2026-08-17

Traditional Chinese, and the zone filter hides what it says it hides.

### New Features

- Traditional Chinese. The tracker and its options panel now read in Chinese on a zhTW client,
  covering 385 of the addon's 389 phrases, which is the most complete translation the addon
  has. Contributed by BNS333.

### Bug Fixes

- Retail: "Show only quests in current zone" now hides the quests that are not in your zone.
  It had been hiding a quest only when the game could hand back a map pin for it, so on a
  sixteen quest log standing in The Coiled Isle it removed two quests and left fourteen, only
  two of which were actually in the zone. Quests that have no location at all, such as
  profession, battleground and meta quests, are hidden by this filter now as well, since they
  are not in your zone either. In a place that has no quests of its own, such as a capital city
  or inside a dungeon, the tracker reads empty while this setting is on. The setting is off by
  default and is unchanged on Classic Era and TBC Anniversary,
  which decide this a different way.

### Improvements

- The About tab credits Keriaovo for the Simplified Chinese translation and BNS333 for the
  Traditional Chinese.
- The description under the Questie option is more precise about what hiding Questie's tracker
  does and does not change.

## [1.8.0] - 2026-08-16

Classic Era and TBC Anniversary now keep their own tracked quest list.

### Bug Fixes

- Classic Era and TBC Anniversary: the tracker now keeps its own list of which quests you are
  tracking, rather than using the game's. The game only lets you watch five quests at a time and
  puts a red error on screen for the sixth, so "Show only tracked quests" could never show more
  than five of your log however you set it. There is no limit now, and shift clicking in the
  game's own quest log still tracks and untracks exactly as it did, with its checkmarks showing
  the tracker's list rather than the game's shorter one.
- Classic Era and TBC Anniversary: "Auto-track accepted quests" works. It had been shipping turned
  on and doing nothing at all, because this game version has no function for it and the five quest
  limit made the obvious substitute worse than useless.
- Classic Era and TBC Anniversary: "Show only tracked quests" now ships turned off. Until this
  update no character on these game versions had a tracked list of their own, so switching the
  filter on by default would hide a quest log nobody had chosen to filter. If you had deliberately
  left the setting on, it will be off once after this update and you can simply turn it back on.
  Retail is unchanged.
- Classic Era and TBC Anniversary: a quest that comes with a usable item now puts that item on
  the tracker as a button, so you can use it without digging through your bags. The button, its
  cooldown and its range check were all there already, switched off by a check for a function
  that only exists on retail.
- Classic Era and TBC Anniversary: tracking or untracking a quest in Blizzard's own quest log now
  updates the tracker straight away. It used to take a reload, because this game version
  announces nothing at all when the watch list changes.
- "Search on Wowhead" now opens the site for the game version you are playing, and in your own
  language where Wowhead has one. On Classic Era and TBC it was opening the retail page, where
  the same quest number is a different quest or nothing at all.
- Scrolling the tracker with the mouse wheel during combat could put a blocked action error on
  screen, on any game version, whenever a quest with a usable item was on the tracker. The wheel
  now does nothing until combat ends, which is as much as the game permits there.
- Quest progress now refreshes when you close a bank, mailbox, vendor, trade or auction window.
  The game only announces a quest item arriving when you loot it, so taking five of eight out of
  the bank left the tracker reading three of eight until something unrelated came along.
- Classic Era and TBC Anniversary: with another quest addon loaded, the tracker could come up
  empty after logging in and stay that way until you ran a command or changed a setting. That
  addon replaces one of the game's own quest tracking functions a few seconds into login, and the
  tracker was still reading the old answer. It no longer reads that function at all.
- Classic Era and TBC Anniversary: tracking and untracking from the tracker's own row menu no
  longer write into another quest addon's saved data, because neither one calls the game's
  tracking functions any more.
- Classic Era and TBC Anniversary: turning "Auto-track accepted quests" off and then accepting a
  quest could quietly switch every other quest in your log to untracked, for good. If you then
  turned "Show only tracked quests" on, the tracker came up empty with no way back but tracking
  each quest by hand. The same thing could happen if you accepted a quest while the tracker was
  hidden by one of the visibility rules.
- Hiding another quest addon's tracker now takes effect on its own. It could need the setting
  toggled off and on again, because the tracker gave up looking for that addon's frame before
  the addon had built it.
- Retail: daily and weekly quests could have been tagged as the wrong kind on a client that
  reports quest frequency the older way. No live client does, so nothing was mis-tagged in
  practice.

### Improvements

- Section headers now always show both numbers when "Show the visible / total count on section
  headers" is on, so a section with nothing filtered out reads 14/14 rather than dropping to a
  bare 14. The count no longer changes shape depending on what is hidden.

## [1.7.0] - 2026-08-15

Simplified Chinese.

### New Features

- Simplified Chinese. The tracker and its options panel now read in Chinese on a zhCN client,
  covering 380 of the addon's 387 phrases. The seven still in English are the Questie
  coexistence strings and the two Classic focus hints, which are untranslated in every
  language. Contributed by Keriaovo, over the Discord.

## [1.6.1] - 2026-08-13

A fix for the tracker coming up empty on Classic Era and TBC Anniversary.

### Bug Fixes

- Classic Era and TBC Anniversary: the tracker could come up completely empty after logging in
  or reloading, and stay that way until you changed any setting or ran a command. The game
  reports every quest as untracked for a moment during login, and with "Show only tracked
  quests" on, which is the default, that hid the entire quest log. Nothing asked again
  afterwards, so it stayed hidden. The tracker now re-reads the watch list a second later when
  it sees a full quest log with nothing tracked in it, which is not a state this game version
  produces on its own. A quest whose tracked state cannot be read yet is also shown rather than
  hidden, instead of being treated as untracked.

## [1.6.0] - 2026-08-13

Focus a quest on Classic Era and TBC Anniversary, and a fix for overlapping controls on the
Appearance tab.

### New Features

- Classic Era and TBC Anniversary: clicking a quest's icon in the tracker now focuses that
  quest, and clicking the icon again clears it. The focused quest's title is tinted so you can
  see at a glance which one you picked. Retail is unchanged, because it already marks the
  super-tracked quest with its own artwork.
- Classic Era and TBC Anniversary: if Everything Quests is also installed, focusing a quest
  drops a TomTom arrow on it, and a quest that is ready to hand in points at the person who
  takes it rather than at the place you farmed it. The arrow clears itself when you turn the
  quest in or abandon it. The tracker on its own carries no quest coordinates, so without
  Everything Quests and TomTom the focus is the tint alone.
- Classic Era and TBC Anniversary: Focus and Unfocus are in the right-click row menu too, in
  the same place they sit on retail.
- Other addons can follow the focused quest through a new `AddFocusListener` call on the public
  API, alongside the existing `AddMenuItem` and `AddHeaderIcon`.

### Bug Fixes

- Appearance tab: several color pickers overlapped the checkbox beside them, so "Show header
  bars" ran into "Bar Color" and the zone bar's "Background" ran into "Background Color". The
  color pickers now measure the checkbox label they sit next to instead of assuming a width.
  This was worst in French and Russian, where the affected labels are around half again as wide
  as the English ones.

### Changed

- Classic Era and TBC Anniversary: with Split quest click on, left-clicking a quest's title
  opens the quest log and left-clicking its icon sets the focus. Left-clicking anywhere on the
  row used to open the quest log. With Split quest click off the whole row sets the focus and
  the quest log is reached from the right-click menu, which is how retail already behaves.

## [1.5.2] - 2026-08-11

Two fixes for quests going missing from the tracker, and zone progress for the new 12.1 zone.

### Bug Fixes

- A possible fix for quest markers sometimes drawing as a square instead of the round icon.
  Tracker rows get recycled as your quest list changes, and a row that had previously drawn a
  world quest handed on the crop it was using for the world quest ring, so the next quest to
  reuse that row drew its marker through the wrong window. That matched every reading taken
  while it was happening. It was never reproducible on demand, so this is reported as a likely
  rather than a confirmed fix. It turned up most often shortly after logging in and cleared on
  a reload, so if you still see it, please say so.
- "Only current zone" no longer hides quests that are not in any zone. Midnight groups the
  quest log into categories such as Battlegrounds, Dungeon, Professions and Ritual Sites, and
  those quests have no location on any map. The filter was reading "not on this map" as
  "somewhere else" and hiding them, which with that setting turned on could leave the Quests
  section nearly empty. Quests the game can point you to somewhere on the map are still
  hidden, which is what the setting is for.

### Improvements

- The zone progress bar now covers The Coiled Isle, the zone added in patch 12.1.
- `/eqot status` reports more about the quest list: how many entries the game reports against
  how many the tracker read, how many quests it thinks are tracked against how many the game
  says are, and how many the game places in your current zone. Useful when reporting a quest
  that is missing from the tracker.

## [1.5.1] - 2026-08-11

A fix for a Lua error the world map could throw while this addon was loaded.

### Bug Fixes

- The tracker no longer causes the "secret value" Lua error that Blizzard's world map throws
  when you hover a point of interest. It drew its own tooltips on the game's shared tooltip
  frame, which left them carrying the addon's taint, and under Midnight's UI protection rules
  Blizzard's own map tooltip then failed while laying itself out. Every tooltip the tracker
  draws now goes on its own private frame and the shared one is never touched. That error names
  whichever addon last used the shared tooltip, so it can still turn up from something else,
  but the tracker is no longer one of them. Reported by caladorn.

### Improvements

- `/eqot status` now reports what the filters are actually set to and which rule rejected each
  entry, so a quest missing from the tracker can be traced to the setting hiding it instead of
  just showing a count. Useful when reporting a problem.

## [1.5.0] - 2026-08-08

EQ Objective Tracker now runs on Classic Era and Burning Crusade Anniversary. Classic support
is early and a work in progress, so expect rough edges and please report anything you find.
Retail behaviour is unchanged.

### New Features

- Classic Era (1.15.9) and Burning Crusade Anniversary (2.5.6) are now supported. The tracker
  draws your quests with zone subtitles, objective counts and progress, and everything built
  around them comes with it: eight sort modes, manual drag ordering, per-quest pinning, the
  filter list, section visibility and ordering, the card layout, all 42 fonts and the colour
  options, profiles, row tooltips and the row right-click menu.
- Blizzard's own quest watch list is suppressed on Classic, so you do not end up with two
  trackers on screen.
- If Questie is loaded, the tracker offers once to hide Questie's tracker, and that choice
  becomes a permanent toggle on the General tab. It hides the frame and nothing else. Questie's
  own settings and its tracked quests are left alone, and its own disable path is never used.

### Improvements

- The Classic builds track quests only. World quests, scenarios, achievements, endeavors and
  tracked recipes need APIs those clients do not have, so those sections simply do not appear
  rather than showing up empty. The zone progress bar stays empty for the same reason, and
  distance sorting does nothing there.
- Five new phrases came with the Questie option and are English-only for now, so French,
  Russian and Korean sit a little below their previous full coverage until they are picked up.

## [1.4.2] - 2026-08-07

French and Russian are complete.

### Improvements

- French and Russian now cover all 380 of the addon's phrases, up from 255 each, so every
  label, tooltip, message and command reply in the tracker and the options panel reads in your
  language. Translated by Zox and Malevi4. Korean is at 378 of the 380, the two outstanding
  being the World Quests tooltips reworded in 1.4.1.

## [1.4.1] - 2026-08-07

The World Quests section gets the space it was always meant to have and now lists your whole
zone, the font pickers show what each font actually looks like, and Korean covers nearly the
entire addon.

### Bug Fixes

- The World Quests section was squeezed to a single clipped row whenever the quest list was
  long. Quests were handed all the vertical space they asked for and world quests were left a
  68 pixel floor, so once your quest list filled the tracker the Maximum Height setting stopped
  having any say. That cap now applies first and the quest list takes the space that is left,
  which costs it only a scroll. A short world quest list still takes only the room it needs.
- Section headers showed an empty box where the expand marker belongs on a Korean client. The
  marker was an en dash, which the Korean game font has no glyph for, and it is a plain hyphen
  now. Reported with a screenshot by labrie75.

### Improvements

- The world quests in your current zone are now listed by default, rather than only the ones
  you have tracked yourself. Untick Auto-list current-zone world quests on the Tracker tab if
  you would rather see only what you track. If you had already turned that off, this update
  switches it back on once and you will need to untick it again.
- Ticking Set a custom World Quests height now starts at 200 pixels rather than 120, which is
  enough room to be worth turning on.
- The font pickers now draw every font's name in that font, both in the open list and on the
  closed dropdown, so you can tell the 42 bundled typefaces apart without applying one to find
  out what it looks like.
- Korean now covers 378 of the addon's 380 phrases, up from 256, so very nearly every label,
  tooltip and message in the tracker and the options panel reads in Korean. Translated by
  labrie75. The two still in English are the World Quests tooltips reworded in this release.

## [1.4.0] - 2026-08-06

The About tab now tells you what changed, where to get help, and who to thank.

### New Features

- The About tab now carries the full changelog, so what changed in every release can be read
  in game rather than on the addon page.
- A Thanks section on the About tab, crediting DrahgunFyre for the features, fixes and
  reports that shaped the tracker, and Zox, Malevi4 and labrie75 for the French, Russian and
  Korean translations that every non-English string in the addon comes from.
- A Discord link in the top left of the options window and on the About tab, alongside links
  to CurseForge, GitHub and the bug tracker. Clicking one offers the address as selectable
  text, since the game cannot open a browser.

### Improvements

- The About tab's command list now includes `/eqot unhide` and `/eqot importeq`, and lines its
  descriptions up in a column. Both were missing, and they are the two commands you need when
  something has gone wrong: nothing else brings back an entry you hid by shift-clicking it, or
  re-runs the Everything Quests import.

## [1.3.1] - 2026-08-06

Fixes for the right-click menu and the Everything Quests import that shipped in 1.3.0.

### Bug Fixes

- Importing your Everything Quests state now runs on every character. It previously ran only
  on the first character you logged into after installing, so every other character silently
  lost its pinned quests, hidden quests, collapsed sections and saved world quest watches.
- Abandoning a quest from the menu now confirms the quest you actually clicked. If the quest
  left your log while the menu was open it could offer to abandon a different one.
- The abandon confirmation now names the quest even when its details have not loaded yet,
  instead of showing a placeholder.
- `/eqot disable all` now switches off the right-click menu too. It stayed active, which
  defeated the point when using it to track down a fault.
- A star on a pinned quest now sits after the NEW tag rather than before it, matching
  Everything Quests.

### Improvements

- Addons adding their own icons to the tracker header can now remove them again, and can set
  where each one sits. Removing one previously left it on screen until a reload, and adding
  one back could move the others.

## [1.3.0] - 2026-08-06

Right-clicking a quest now opens a menu instead of just untracking it, and quests can be
pinned so they stay on the tracker no matter how you have your filters set.

### New Features

- Right-click a quest for a menu: pin it, track or untrack it, focus it, open it in the map
  and quest log, pop out its details, look it up on Wowhead, or abandon it. World quests get
  their own shorter menu. Achievements, professions and endeavors are unchanged, and still
  untrack on a right-click.
- Pin a quest to keep it on the tracker whatever your filters and "only show tracked" say. A
  pinned quest carries a star, and pinning one you had hidden unhides it.
- Other addons can add their own entries to the row menu and their own icons to the tracker
  header, so a companion addon can put its features where you expect them.

### Improvements

- Importing from Everything Quests now also carries your per-character state: pinned and
  hidden quests, which sections you had collapsed, and your saved world quest watches. Only
  your settings came across before.
- `/eqot status` reports how many quests are pinned.

## [1.2.0] - 2026-08-05

A correctness pass over the whole addon, following a full read of the code. Most of what
changed is settings and saved state that could be lost or quietly ignored, so day to day the
tracker behaves as it did.

### New Features

- `/eqot unhide` brings back every entry you have hidden by shift-clicking it. Hiding was
  previously one way, short of resetting the whole profile.

### Improvements

- Quest icons are drawn at their full size, so the icon fills its ring instead of sitting
  small inside it.
- Importing from Everything Quests now carries the zone progress bar's styling as well as its
  position: bar texture, bar color, border color, zone name color, count color and font.
- Several internal caches are now pruned as you play, instead of growing for a whole session.
- `/eqot status` reports how many entries are hidden, and which sections they came from.

### Bug Fixes

- Reset to Defaults on the Appearance tab no longer switches off a configured zone progress
  bar, or pulls a docked one back out into a floating bar. It restyles the tracker, which is
  what it says it does.
- Canceling the color picker no longer writes a value. Opening Quest Title Color Override
  and pressing Escape used to turn every quest title flat white and silently switch off
  coloring by difficulty. Closing the options window part way through a pick is covered too.
- World quests you tracked by hand are no longer dropped from the saved watch list, so they
  are still tracked when you log back in.
- Bonus objectives reset on leaving a delve, instead of carrying the previous run's progress
  into the next one.
- Quest sounds stop as soon as the setting is switched off, rather than only after a reload.
- Hiding an entry now keeps it hidden. It could previously come back under a different
  section.
- A quest that turns out to be Legendary now takes the matching card tint, not just the
  matching icon.
- Blizzard's quest log no longer opens on a quest you did not select.
- The tracker no longer resizes its contents while you are in combat.

## [1.1.0] - 2026-08-04

Richer tracker tooltips, and a pass over the whole options panel: controls that do nothing
right now are dimmed instead of looking active, related settings are grouped together, and a
number of labels and tooltips that described the wrong thing have been corrected.

### New Features

- Hovering a quest in the tracker now shows its objectives and its full rewards: money,
  currencies, and items with an item level comparison against what you have equipped.
  Previously it showed only the quest name and a note about clicking.
- Hovering a world quest additionally shows its faction and how long is left, with the time
  colored by how close it is to expiring, matching the countdown on the row itself.
- A control that only applies while another setting is on is now dimmed while that setting
  is off, so it is clear at a glance which settings are actually in effect.
- Each of the eight sort orders now explains what it sorts by on hover.
- The zone progress bar has a Background Color of its own. Left unset it keeps the plain
  black fill that fades slightly once the bar is locked.
- The Scenario Bonus Objectives group has a Test button, so the HUD can be positioned and
  sized without waiting to be inside a scenario or delve.

### Improvements

- The zone progress bar's settings are all in one place. Its two switches moved from the
  Tracker tab to join its styling on the Appearance tab.
- Hide scroll bar moved to the Appearance tab, at the top of the scroll bar settings it
  turns off, rather than sitting two tabs away from them.
- Buttons, tabs, dropdowns and color swatches now respond to the mouse.
- Color settings line up in a column, and the whole row is clickable rather than just the
  small swatch.
- A dropdown list marks the setting you are using, opens scrolled to it, and opens upward
  when there is no room below.
- Control text is white throughout instead of gold.
- Spacing around section headings is consistent across all four tabs.
- Show only watched quests is now Show only tracked quests, matching the word the game and
  the rest of the addon use, and its tooltip explains what it hides.
- Show tracked / total on the Quests & Campaign headers is now Show the visible / total
  count on section headers, which is what it has always done.
- The click hint has been removed from quest and world quest tooltips. It described only
  half of what a click does once Split quest click is turned on.

### Bug Fixes

- Canceling the color picker no longer writes a color. Opening an unset color and
  pressing Cancel or Escape used to save white, which turned every quest title white and
  silently stopped difficulty coloring from applying.
- Options Window Scale can no longer push the window's tabs and close button off the top of
  the screen, and the window is kept on screen if dragged to an edge.
- The section visibility tooltips said they hide a section when the box shows it.
- Reset all settings said only the active profile was affected. It also clears the Options
  Window Scale, which every character shares, and this character's collapsed sections and
  hidden entries. The confirmation now says so, and both reset dialogs mention the reload.
- The Appearance tab's Reset to Defaults no longer changes two settings on the Tracker tab.
- Quest Title Color By Difficulty and Show zone label under quest titles could not be
  clicked by their labels, unlike every other checkbox.
- Reset filters to defaults no longer turns Show only tracked quests back on.
- Dropdown lists follow the options window scale, and a list or color picker left open no
  longer floats over the game world after the window is closed.
- The Maximum height slider had no effect while a custom World Quests height was set, with
  nothing to indicate it.
- Creating a profile with an empty name closed the dialog without creating anything.
- Pressing Enter on a confirmation dialog opened the chat box behind it.
- The section reorder arrows kept naming the previous section after a move.
- Filter tooltips read "Show or hide world quests entries in the tracker."
- The tracker no longer rebuilds twice every time a checkbox or color is changed.

## [1.0.0] - 2026-08-03

Out of beta. The options panel has been rebuilt to match Everything Quests control for
control, so moving between the two addons no longer means learning a second layout.

### Improvements

- The options window is rebuilt throughout: wider, laid out in two columns, and restyled to
  match Everything Quests. Dropdowns, buttons, sliders, color swatches and section headers
  all follow the same look now.
- Sort order is a row of buttons instead of a button you had to click through to find the
  mode you wanted. All eight modes are visible at once.
- Section order uses arrows, and section visibility is a plain checkbox list, so reordering
  and hiding are no longer tangled together in one row.
- The Sections tab is gone. Everything on it now lives on a new Tracker tab, alongside the
  tracker settings that used to be spread across General. The tabs are General, Tracker,
  Appearance and About.
- Quest sorting by type is available, ordering weekly above daily above normal.
- Font outline offers the three monochrome options as well, for six in total.
- A new Options Window Scale slider resizes the options window itself.
- Wording throughout the panel now matches Everything Quests, which also means far more of
  it arrives already translated. French and Russian cover 72% of the addon's phrases and
  Korean 66%, up from 44%.
- Many controls gained explanations on hover, and existing ones were reworded to match.

### Bug Fixes

- Reset all settings now genuinely resets everything. The tracker's size and position, any
  collapsed or hidden sections, and the options window scale all return to their defaults;
  previously they survived the reset. Your tracked world quests are deliberately left alone.
- Sliders no longer quietly rewrite a saved value that sits outside their range simply
  because you opened the tab they live on.
- Picking an option from a dropdown stores the setting itself rather than the label shown on
  screen, so dropdowns keep working correctly in every language.
- On-panel description text no longer overflows the window; explanations are on hover.

## [0.7.1] - 2026-08-02

Fixes to the drag ghost and to how equipment slots are named, found by comparing notes with
Everything Quests after v0.7.0 shipped.

### Bug Fixes

- The drag ghost is now genuinely see-through, so you can read the quest you are dropping
  onto. It had a gold outline but a solid interior, which hid the row underneath.
- The drag ghost is now the right width when the tracker is scaled. It was sized in the
  row's own space rather than the screen's, so it came out too narrow on a scaled-up
  tracker and too wide on a scaled-down one.
- Equipment slot names in the quest reward tooltip now come from the game itself, so they
  appear in your language and match the wording on the item tooltip you are comparing
  against. They were previously an English list that only ever showed English.

### Notes

- Three slot names change wording slightly to match the game's own terms.
- The locale check used by the release build now understands the game's numbered format
  placeholders, so a translation that reorders them is no longer reported as an error.

## [0.7.0] - 2026-08-02

The tracker speaks more than English now.

### New Features

- Translations. The addon is partly translated into French, Russian and Korean, and picks
  the language up from your game client automatically. Anything not yet translated shows in
  English on its own, so a partial translation is never a broken one.
- `Locales/` holds the phrase list and one file per language. Adding or correcting a
  translation is a matter of editing the file for that language, and adding a new language
  is a matter of copying one.

### Improvements

- Every dropdown in the options panel now keeps the setting it saves separate from the text
  it shows. Picking an option stores the same value whatever language you play in.
- The Sort button reads Sort: Zone rather than Sort: zone, and the sort names translate with
  the rest of the panel.

### Notes

- A handful of labels changed capitalization to match Everything Quests exactly, such as
  Font Size and Border Color. This is what lets the two addons share translations.
- Fonts, status bar textures and sound names are deliberately left untranslated. Your
  profile stores them by name, so translating them would silently reset your choices.

## [0.6.0] - 2026-08-01

The last of the display options from Everything Quests.

### New Features

- Show a quest's level in front of its title, as [60] Title. Off by default.
- Show a quest's ID after its title, which is handy when reporting a bug. Off by default.
- A NEW tag on quests accepted in the last hour. On by default.
- Split quest click: click a quest's icon to focus it, click its title to open the quest log
  instead. Off by default, so a click anywhere on the row still focuses the quest.
- A cogwheel at the top-right of the tracker that opens the options panel. On by default,
  and it can be turned off under General.

### Notes

- The level, ID and NEW tag appear on quests and campaign quests only, matching Everything
  Quests. Achievements, professions, endeavors and world quests are unaffected.

## [0.5.0] - 2026-08-01

Bringing your setup with you. Settings can now live in named profiles, and if you already run
Everything Quests your tracker settings come across on first install.

### New Features

- Distance sorting. Pick Distance under Sorting on the General tab and quests order by how
  close their objective is, re-sorting as you move. Quests ready to hand in sort by where you
  hand them in, rather than dropping to the bottom of the list.
- Profiles. Keep separate setups and switch between them from the General tab, with a New
  profile button that starts from a copy of your current settings. Profiles are shared across
  all your characters.
- Reset all settings, which returns the active profile to defaults behind a confirmation.
- Everything Quests settings are imported automatically the first time this addon runs, if
  Everything Quests is installed. Position, size, fonts, colors, filters, section order,
  sorting and your manual quest order all come across. Nothing is imported over an existing
  setup, and `/eqot importeq` runs it by hand if you want it later.
- `/eqot status` reports distance sorting state, and whether an Everything Quests
  configuration was found and imported.

### Notes

- Switching, creating or resetting a profile reloads the interface, matching Everything
  Quests.
- The profile list is sorted by name. The library underneath returns it in no particular
  order, which meant it could rearrange itself between sessions on its own.

## [0.4.0] - 2026-08-01

Put the quests in whatever order you want them.

### New Features

- Manual sorting. Pick Manual under Sorting on the General tab, then drag any quest or
  campaign quest to where you want it. A gold line shows where it will land, and the order
  survives logging out. Quests you are not currently showing keep their place in the order,
  so filtering the tracker and rearranging it no longer discards the rest.
- `/eqot status` reports how many quests carry a manual position and how many of those are
  still in your log.

### Notes

- Only quests and campaign quests can be dragged, matching Everything Quests. The drop line
  stays inside the section you picked the quest up from, since a quest cannot move between
  Campaign and Quests.
- The dragged quest is shown on a translucent panel with a gold edge, so the row you are
  dropping it onto stays readable underneath it. Everything Quests draws that panel opaque,
  which covers the row you are aiming at.

## [0.3.0] - 2026-08-01

Getting the tracker out of your way without missing anything. It can now hide itself in
combat, in instances and while the map is open. Quests carrying a usable item get a button
on their row, newly discovered and completed quests get popups, and bonus objectives get
their own movable HUD. Two separate causes of a blocked-action error around the world map
are also fixed.

### New Features

- Bonus objectives HUD, off by default. A small movable checklist of the extra bonus
  objectives that appear during some scenarios and delves, so their rewards are not
  missed. Inside a delve it follows the bonus loot mechanics as well. Drag it anywhere,
  right-click to lock it or reset its position, and size it with its own scale slider.
  Turn it on under General, Scenario Bonus Objectives.
- Hovering a bonus objective's reward icon shows what that step pays out, with each item's
  level and how it compares against what you have equipped.
- Usable quest items now appear as a button on the row of any quest that carries one, with
  its charges, its cooldown, and a tint while the target is out of range. Only rows that
  have an item pay for the space.
- Popups for newly discovered quests and for quests that can be handed in remotely, drawn
  at the top of their section and counted in its header. On by default.
- Accepted quests are now tracked automatically, matching the default UI. On by default.
- Visibility rules: the tracker can hide itself during combat, inside instances, during a
  Mythic+ run, and while the world map is open. Each is its own toggle.
- The zone progress bar can be docked into the tracker as an ordinary section instead of
  floating, and reordered along with the rest.
- Zone progress bar appearance options: bar texture with a live preview of the artwork,
  bar color, scale, font, zone name and count colors, background, border and border color.
- `/eqot bonushud` reports what the bonus objectives HUD can see, and `/eqot bonushud test`
  draws a sample so it can be positioned without being in a delve.
- `/eqot modules`, `/eqot disable <name>` and `/eqot enable <name>` switch individual parts
  of the addon off for a session, to narrow a fault down to one of them. `/eqot disable
  all` is a safe mode that turns off every optional part at once.

### Bug Fixes

- Opening the world map in combat could produce a blocked-action error naming this addon,
  from a stack containing none of its code. Two separate causes are fixed: the options
  window no longer registers for Escape-to-close through the list the panel manager reads
  by name, and the world quest group finder check now resolves off the render path.
- Blizzard's tracker could reappear beside this one for the rest of a fight, because the
  re-hide stood down while in combat. It now runs in combat as well.
- The tracker no longer drifts across the screen as its scale changes. Positions are
  stored in screen units, and a position saved under the old units is converted once.
- The floating zone progress bar no longer drifts as its scale changes, for the same
  reason.
- Turning the scroll bar skin back off could erase the thumb outright rather than restore
  it, where the stock thumb was neither an atlas nor a plain texture. A thumb whose width
  was read before it had been sized also never got that width back.
- An endeavor requirement beginning with a negative number lost its minus sign.

### Improvements

- The tracker is now hidden outright rather than only faded wherever the game allows it.
  In the one case where it can only fade, it no longer swallows clicks, tooltips or the
  mouse wheel.

### Notes

- Blizzard's tracker sub-modules are no longer silenced. Doing that meant writing to
  eleven of its frames, which feed the quest marker system, and Everything Quests has
  never done it.

## [0.2.0] - 2026-07-28

A large step toward the parity needed before Everything Quests can drop its own tracker
and depend on this one. The appearance options, the world quest area, professions,
endeavors and the full scenario and delve display are all ported across.

### New Features

- Title colors: difficulty coloring can now be turned off, titles take an explicit
  color override with a Clear button to undo it, and either titles or section
  headings can use your character's class color.
- Completed entries can use the title color instead of green. This applies to
  finished objective lines as well as titles, so quests, world quests and
  achievements all follow the same setting.
- Card row layout: each entry is drawn on its own bordered panel, with separate
  background and border colors, adjustable border thickness and padding.
- Cards can be tinted by type, giving campaign, legendary, dungeon and raid entries
  their own color. Instance types take priority over storyline ones.
- Section header bars: an optional gradient bar behind each heading, in horizontal
  or vertical style, with its own color, height, and feathered edges.
- Scroll bar skinning: a track background with its own color, a flat single color
  thumb with adjustable color and width, and options to hide the end arrows or the
  scroll bar entirely. Hiding the bar gives its gutter back to the text.
- `/eqot status` now reports the scroll bar's live state, including which thumb
  widget the current client actually uses.
- World quests now render in their own capped, separately scrolling area pinned above
  or below the quest list, rather than as an ordinary section. Its share of the
  tracker is capped, and the quest sections are given their space first, so a long
  world quest list can no longer push quests off screen. The cap is adjustable, or it
  can be replaced with a fixed height.
- Optionally list every world quest on your current map without tracking each one.
- Tracked profession recipes are now shown, with their required reagents and how many
  of each you hold. Reagent counts sum every quality tier, so a stack of nothing but
  rank two or rank three still counts toward the total. Reagents whose amount depends
  on choices made in the crafting window show their range instead of a false total. A
  recipe tracked both normally and as a recraft gets a row for each.
- Endeavors are now tracked, showing each activity and its requirements. Completed
  requirements follow your complete-entry color like every other section, rather than
  being locked to green.
- Tracked world quests now survive logout. Blizzard drops world quest watches between
  sessions, so they are saved per character and restored shortly after login, once the
  world quest data exists. Expired ones are pruned rather than restored, and quests the
  game auto-watches as you walk past are not saved.
- Simplify tracked achievements: show only the criteria you have not finished yet.
- Keep focused quest after relog, on by default. With it off, the waypoint arrow is
  cleared shortly after you log in. Reloading and changing zone never disturb it either
  way.
- Opening the flight map highlights the flight point nearest your focused quest.
- A sound plays when a quest becomes ready to turn in, with 27 voices to pick from and
  a preview when you choose one. On by default, and it can be turned off.
- Everything Quests' seven status bar textures are bundled and offered through
  LibSharedMedia, so they are available to other addons as well.
- Zone progress bar, off by default. Shows how much of the current zone's questlines you
  have finished, as a movable bar you can drag anywhere, with right-click to lock it or
  reset its position. Standing in a capital shows the surrounding zone's progress.
- World quests that support it now carry a Find Group button, which opens the Premade
  Group Finder for that quest. It only appears where a group can actually be made for
  the quest, so most rows will not show one.
- Scenarios, delves, dungeons and battlegrounds now show their current stage and its
  criteria, with progress counts and completion. The content type is worked out from the
  scenario type, texture kit and difficulty together, so Ritual Sites are told apart from
  Delves and Follower Dungeons from ordinary ones, and it is shown in the entry's tooltip.
  Unreleased steps that report an internal build string in place of real criteria text no
  longer show that string. Scenarios draw in their own area pinned above the quest list
  rather than scrolling with it, so the rest of the tracker moves down to make room.
- The scenario banner, with its stage artwork, the content type above the instance name,
  the final-stage filigree on the last stage, and the themed tint some scenarios carry.
  Where a scenario supplies its own display widgets, those replace the banner as they do
  in the default tracker. Criteria that track a percentage draw a progress bar.
- Appearance options for the scenario banner: its own text shadow with color and
  distance, kept separate from the tracker's text shadow, plus banner alignment, banner
  text size and criteria text size.

### Bug Fixes

- World quests now show the quest type on their marker, matching Everything Quests and
  the default tracker: a map pin ring, which brightens while super-tracked, with the
  pet battle, profession or other type icon on it. They previously showed the quest's
  reward instead, which also meant the icon visibly changed as reward data loaded, most
  noticeably when listing every world quest in the zone at once.

### Improvements

- A finished progress bar now reads as its label alone. The tracker was still showing
  the count beside it, so a completed bar read as "100/100 Rescued Villagers" where the
  default tracker and Everything Quests both show just the label.

### Notes

- Entry spacing has a 4px floor while the card layout is on. Below that, adjacent
  card borders touch and a list reads as one merged card.
- World Quests no longer appears in the section reorder list, because a pinned region
  has no position within the scrolling run. Its Top or Bottom placement, and its
  show and hide toggle, moved to the World Quests group on the Sections tab.
- Turning the solid color thumb back off restores the original scroll bar thumb.
  Everything Quests only restores an atlas-based thumb, so where the stock thumb is a
  plain texture it stays stuck as a solid block until the UI is reloaded.

## [0.1.0] - 2026-07-26

First milestone. Not yet released.

### New Features

- Replaces the default objective tracker with a movable, resizable frame that
  remembers its position, size, and collapsed sections across sessions.
- Tracks quests from the quest log, with objective progress, completion state,
  and super-tracking on left-click.
- Section headers show visible and total counts and collapse on click.
- Options panel and slash commands: `/eqot`, plus `lock`, `unlock`, `reset`,
  `toggle`, `status`, `debug`.
- Separate Campaign and Quests sections.
- Tracks watched world quests with their reward icon and a colored expiry countdown.
- Tracks achievements with their criteria and progress bars.
- Filter by quest type: campaign, daily, weekly, normal, and this zone only.
- Sort by zone, title, status, level, or recently added.
- Shift-click a row to hide it from the tracker.
- Appearance options for text and frame: font through LibSharedMedia with 42 bundled
  fonts, size, outline, title and header size offsets, text shadow with its own color
  and distance, tracker scale, line and header spacing, section header and divider
  colors, and a background and border with colors and thickness.
- Every option carries a mouseover description.

### Notes

- Retail only for now. The architecture gates flavor differences at load time, so
  Classic support is additive.
- World quests render as an ordinary section. The capped, separately placed region
  from Everything Quests is not in this milestone.
- Professions, scenarios and quest-item buttons are not in this milestone.
