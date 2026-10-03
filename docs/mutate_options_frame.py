"""Prove docs/test_options_frame.lua actually discriminates, by breaking production on purpose one
change at a time and checking the harness notices.

    python docs/mutate_options_frame.py        (run from the repo root)

Why this exists: since 2.0 Options/Frame.lua is only the EverythingUI context and its forwarders,
and every tab reaches the library through it. No other harness loads it, so a field it stops
passing on switches a whole feature off with everything else green: drop the preview and the live
preview panel is gone, drop the footer and so is every Reset button, drop the refresh and About's
provider counts and the per-view sweeps stop.

Every mutation reintroduces a defect the harness is supposed to stand guard over. Any that still
reports "0 failed" is an assertion that does not discriminate, and the run exits 1 naming it.

WRITES TO THE TREE. It edits in place and restores through a finally, so an interrupted run
still puts the file back, and it verifies the restore and re-checks the baseline before
reporting. This checkout is junctioned into AddOns, so run it from a scratch copy while the game
is open.

Anchors are exact source text and they rot. A SKIPPED line means an anchor stopped matching:
fix the anchor rather than dropping the mutant.
"""
import io
import re
import subprocess
import sys

LUA = r"C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe"
HARNESS = "docs/test_options_frame.lua"

F = "Options/Frame.lua"
C = "Libs/EverythingUI/Context.lua"

MUTANTS = [
    # ------------------------------------------------------------ what each tab hands the library
    ("the tab's refresh is never passed on", [
        (F, "        refresh = def.refresh,\n", "")]),

    ("the preview and its refresh are never passed on, so there is no live preview", [
        (F, "        preview = def.preview,\n        previewRefresh = def.previewRefresh,\n", "")]),

    ("the preview's refresh is never passed on", [
        (F, "        previewRefresh = def.previewRefresh,\n", "")]),

    ("the footer is never passed on, so every Reset button is gone", [
        (F, "        footer  = def.footer,\n", "")]),

    ("the build is never passed on", [
        (F, "        build   = def.build,\n", "")]),

    ("the tab is titled with its id", [
        (F, "        title   = def.title,", "        title   = def.id,")]),

    ("the tab's order is never passed on", [
        (F, "        order   = def.order,\n", "")]),

    ("the tab is registered under its title", [
        (F, "        id      = def.id,", "        id      = def.title,")]),

    ("the nav icons are dropped", [
        (F, "        icon    = TAB_ICONS[def.id] and ui:Texture(TAB_ICONS[def.id]),\n", "")]),

    ("every tab gets the General icon", [
        (F, "        icon    = TAB_ICONS[def.id] and ui:Texture(TAB_ICONS[def.id]),",
            '        icon    = ui:Texture("icon-general"),')]),

    ("Appearance shows the About icon", [
        (F, '    appearance = "icon-appearance", about = "icon-about",',
            '    appearance = "icon-about", about = "icon-about",')]),

    # ------------------------------------------------------------ the context and its labels
    ("the version is hard-coded", [
        (F, "    version = ns.VERSION,", '    version = "1.28.0",')]),

    ("the accent is not the one the library keeps for this addon", [
        (F, "    accent  = EUI.tokens.accents.EQOT.accent,", "    accent  = { 1, 0, 0 },")]),

    ("the shared tooltip is used in place of the addon's own", [
        (F, "    tooltip = ns.Util.Tooltip,", "    tooltip = function() return GameTooltip end,")]),

    ("the Discord button does nothing", [
        (F, "    discord = function() ns:ShowDiscord() end,", "    discord = function() end,")]),

    ("the Discord tooltip text repeats its title", [
        (F, '        discordTip      = L["Click to copy the invite link."],',
            '        discordTip      = L["Join our Discord"],')]),

    ("the speaker's tooltip is never passed on", [
        (F, '        testSound       = L["Plays the currently selected sound."],\n', "")]),

    ("Clear is hard-coded in English", [
        (F, '        clear           = L["Clear"],', '        clear           = "Clear",')]),

    ("the context is never kept, so the tabs and menus cannot find it", [
        (F, "Options.ui = ui\n", "")]),

    # ------------------------------------------------------------ the saved tab and window scale
    ("the last tab is never remembered", [
        (F, "        if c then c.lastOptionsTab = id end", "        if c then c.lastOptionsTab = nil end")]),

    ("the saved tab is never read", [
        (F, "        return c and c.lastOptionsTab", "        return nil")]),

    ("the last tab is saved for the whole account", [
        (F, '        local c = ns:GetModule("DB"):Char()\n        if c then c.lastOptionsTab = id end',
            '        local c = ns:GetModule("DB"):Global()\n        if c then c.lastOptionsTab = id end')]),

    ("a DB not yet ready raises on the first view", [
        (F, "        if c then c.lastOptionsTab = id end", "        c.lastOptionsTab = id")]),

    ("the window scale is read from the wrong key", [
        (F, "        return g and g.optionsWindowScale", "        return g and g.optionsScale")]),

    ("a clamped window scale is never written back", [
        (F, "        if g then g.optionsWindowScale = v end",
            "        if g then g.optionsWindowScale = g.optionsWindowScale end")]),

    ("the window scale is read per character", [
        (F, '        local g = ns:GetModule("DB"):Global()\n        return g and g.optionsWindowScale',
            '        local g = ns:GetModule("DB"):Char()\n        return g and g.optionsWindowScale')]),

    # ------------------------------------------------------------ the forwarders
    ("SelectTab selects nothing", [
        (F, "function Options:SelectTab(id)\n    ui:SelectTab(id)\nend", "function Options:SelectTab(id)\nend")]),

    ("ApplyWindowScale applies nothing, so the scale slider never resizes the window", [
        (F, "function Options:ApplyWindowScale()\n    ui:ApplyWindowScale()\nend",
            "function Options:ApplyWindowScale()\nend")]),

    ("Build builds a new window every time", [
        (F, "    if self.frame then return end\n    self.frame = ui:BuildSettings",
            "    self.frame = ui:BuildSettings")]),

    ("the window loses its global name", [
        (F, 'ui:BuildSettings("EQOTOptionsFrame")', "ui:BuildSettings()")]),

    ("Toggle never builds the window first", [
        (F, "function Options:Toggle()\n    self:Build()\n", "function Options:Toggle()\n")]),

    ("Toggle never toggles", [
        (F, "    self:Build()\n    ui:ToggleSettings()\nend", "    self:Build()\nend")]),

    ("the window is not built at login", [
        (F, "function Options:OnEnable()\n    self:Build()\nend", "function Options:OnEnable()\nend")]),

    ("the window opens at login", [
        (F, "function Options:OnEnable()\n    self:Build()\nend", "function Options:OnEnable()\n    self:Toggle()\nend")]),
    # A DB not yet ready saves nothing anywhere.
    ("the last tab falls back to the account while the character DB is not ready", [
        (F, "        if c then c.lastOptionsTab = id end",
            '        if c then c.lastOptionsTab = id else ns:GetModule("DB"):Global().lastOptionsTab = id end')]),

    ("the window scale falls back to the character while the account DB is not ready", [
        (F, "        if g then g.optionsWindowScale = v end",
            '        if g then g.optionsWindowScale = v else ns:GetModule("DB"):Char().optionsWindowScale = v end')]),

    # The vendored library's own tables, which the harness reads rather than copies.
    ("the library no longer takes getWindowScale", [
        (C, '    getWindowScale = { kind = "function" },\n', "")]),

    ("the library starts requiring accentText", [
        (C, '    accentText = { kind = "rgb" },', '    accentText = { kind = "rgb", required = true },')]),

    ("the library takes its tooltip as a table", [
        (C, '    tooltip    = { kind = "function", required = true },', '    tooltip    = { kind = "table",    required = true },')]),

    ("the library no longer takes the testSound label", [
        (C, "    testSound       = true,\n", "")]),
]

SUMMARY = re.compile(r"^test_options_frame: (\d+) passed, (\d+) failed$")


def run():
    """(verdict, note). verdict is "green", "failed" or "crashed".

    A nonzero exit is NOT evidence that an assertion discriminated - a mutant that does not parse
    exits nonzero too - so the harness's own summary line is matched rather than its exit code,
    and a run that never got that far is its own verdict.
    """
    r = subprocess.run([LUA, HARNESS], capture_output=True, text=True)
    for line in reversed([l for l in r.stdout.splitlines() if l.strip()]):
        m = SUMMARY.match(line.strip())
        if m:
            return ("failed" if int(m.group(2)) else "green"), line.strip()
    err = (r.stderr.strip().splitlines() or r.stdout.strip().splitlines() or ["no output"])
    return "crashed", err[0][:90]


FILES = sorted({f for _, hunks in MUTANTS for f, _, _ in hunks})
original = {f: io.open(f, encoding="utf-8", newline="").read() for f in FILES}


def fit(f, s):
    return s.replace("\n", "\r\n") if "\r\n" in original[f] else s


def restore():
    for f, text in original.items():
        io.open(f, "w", encoding="utf-8", newline="").write(text)


verdict, last = run()
print("baseline: %s\n" % last)
if verdict != "green":
    print("BASELINE IS NOT GREEN - stopping")
    sys.exit(1)

failures = []
for name, hunks in MUTANTS:
    edited, broken = {}, False
    for f, old, new in hunks:
        old, new = fit(f, old), fit(f, new)
        cur = edited.get(f, original[f])
        # Asserted rather than assumed: applying a mutant to a file that still holds the last one
        # is a silent no-op, and the run would report the previous mutant's result under this name.
        if cur.count(old) != 1:
            print("SKIPPED (anchor matched %d times): %s" % (cur.count(old), name))
            broken = True
            break
        edited[f] = cur.replace(old, new, 1)
    if broken:
        failures.append(("SKIPPED", name))
        continue
    try:
        for f, text in edited.items():
            io.open(f, "w", encoding="utf-8", newline="").write(text)
        verdict, last = run()
    finally:
        restore()
    if verdict == "crashed":
        print("CRASHED   %-74s %s" % (name, last))
        failures.append(("CRASHED", name))
    elif verdict == "green":
        print("SURVIVED  %-74s %s" % (name, last))
        failures.append(("SURVIVED", name))
    else:
        print("caught    %-74s %s" % (name, last))

for f in FILES:
    if io.open(f, encoding="utf-8", newline="").read() != original[f]:
        print("\nTHE TREE WAS NOT RESTORED - %s still holds a mutant" % f)
        sys.exit(1)
verdict, last = run()
if verdict != "green":
    print("\nBASELINE IS NOT GREEN AFTER THE RUN - %s" % last)
    sys.exit(1)

print()
if failures:
    # Three different verdicts, never pooled. A SKIPPED anchor reported as a survivor sends the
    # reader hunting a coverage hole that is not there, and a CRASHED one hides an abort.
    for kind, label in (
            ("SURVIVED", "mutant(s) survived - those assertions do not discriminate"),
            ("CRASHED",  "mutant(s) aborted the harness rather than failing it"),
            ("SKIPPED",  "anchor(s) rotted - fix the anchor, never drop the mutant")):
        named = [name for verdict, name in failures if verdict == kind]
        if named:
            print("%d %s:" % (len(named), label))
            for name in named:
                print("  - " + name)
    sys.exit(1)
print("every mutant behaved as expected")
