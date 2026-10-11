"""Prove docs/test_title_color.lua actually discriminates, by breaking production on purpose one
change at a time and checking the harness notices.

    python docs/mutate_title_color.py        (run from the repo root)

Why this exists: Quest Title Color replaced three switches on two tabs, and its whole promise is
that a profile written before it draws exactly what it drew. Every way of breaking that is silent:
a mode read in the wrong order, a fallback that turns Gold into difficulty colors, a finished quest
that stops going green. Original Style adds a client test and a hover, both invisible to a
harness that never builds the other client.

Every mutation reintroduces a defect the harness is supposed to stand guard over. Any that still
reports "0 failed" is an assertion that does not discriminate, and the run exits 1 naming it.

Since 2026-10-10 it also breaks the two colors added beside it: Finished Quest Color (read only
for a finished title, in every mode, never lit, never reaching the finished lines, unset by
default) and the NEW tag's color (its cache, its default blue, the reset, and the tag's old window,
switch, provider and order around a pin), and the status line reporting both. A picked Finished
Objective Color must never reach a title, nor may any color with an AceDB default (Count Color: Done,
the objective text, the NEW tag), which the old-profile grid checks over Core/DB.lua's own defaults.

Equivalent mutant left out on purpose: dropping "and ObjectiveTrackerFrame == nil" from the watch
frame test. No client defines both frames, so no real client shows the difference.

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
HARNESS = "docs/test_title_color.lua"

U = "Core/Util.lua"
R = "UI/Row.lua"
D = "Core/DB.lua"
C = "UI/Commands.lua"

MUTANTS = [
    # -------------------------------------------------------- reading an old profile's mode
    ("an override set beside the class switch now wins over it", [
        (U, "    if cfg and cfg.titleColorUseClass then return \"class\" end\n"
            "    local ov = cfg and cfg.titleColorOverride\n"
            "    if ov and ov.r then return \"custom\" end\n",
            "    local ov = cfg and cfg.titleColorOverride\n"
            "    if ov and ov.r then return \"custom\" end\n"
            "    if cfg and cfg.titleColorUseClass then return \"class\" end\n")]),

    ("difficulty switched off still draws difficulty colors", [
        (U, "    if cfg and cfg.colorByDifficulty == false then return \"gold\" end\n", "")]),

    ("a stored mode is ignored and the old switches always decide", [
        (U, "    if TITLE_MODES[m] then return m end\n", "")]),

    ("any stored string is trusted as a mode", [
        (U, "    if TITLE_MODES[m] then return m end\n", "    if m then return m end\n")]),

    ("Original Style is not a mode the stored key can hold", [
        (U, "custom = true, original = true }", "custom = true }")]),

    # -------------------------------------------------------------------- Original Style
    ("the watch frame never brightens a finished title", [
        (U, "        if complete then return normalFontColor() end\n", "")]),

    ("retail ignores the client's header color", [
        (U, "    local c = OBJECTIVE_TRACKER_BLOCK_HEADER_COLOR\n    if c and c.r then return c.r, c.g, c.b end\n", "")]),

    ("retail falls back to the wrong gold without the client's color", [
        (U, "    if c and c.r then return c.r, c.g, c.b end\n    return 0.75, 0.61, 0\nend",
            "    if c and c.r then return c.r, c.g, c.b end\n    return 0.92, 0.72, 0.02\nend")]),

    ("the watch frame gets a hover color", [
        (U, "    if watchFrameClient() then return nil end\n", "")]),

    ("the hover color falls back to white", [
        (U, "    return 1, 0.82, 0\n", "    return 1, 1, 1\n")]),

    ("the watch frame client is never recognized", [
        (U, "    return QuestWatchFrame ~= nil and ObjectiveTrackerFrame == nil\n", "    return false\n")]),

    # ------------------------------------------------------------- the one color per mode
    ("Gold recolors a finished quest instead of keeping it green", [
        (U, "        return Util.OriginalTitleColor(complete)\n    end\nend",
            "        return Util.OriginalTitleColor(complete)\n    elseif mode == \"gold\" then\n"
            "        return 0.92, 0.72, 0.02\n    end\nend")]),

    ("Original Style forgets whether the quest is finished", [
        (U, "        return Util.OriginalTitleColor(complete)\n", "        return Util.OriginalTitleColor(false)\n")]),

    ("Class color gives no color", [
        (U, "    if mode == \"class\" then\n        return Util.GetPlayerClassColor()\n",
            "    if mode == \"class\" then\n        return nil\n")]),

    # ----------------------------------------------------------------------- the row
    ("a finished line forgets it is finished", [
        (R, "    local r, g, b = Util.EffectiveTitleColor(cfg, true)\n",
            "    local r, g, b = Util.EffectiveTitleColor(cfg)\n")]),

    ("the completed box defaults off for a profile that never touched it", [
        (R, "    if complete and not (r and (not cfg or cfg.overrideCompleteGreen ~= false)) then",
            "    if complete and not (r and cfg and cfg.overrideCompleteGreen) then")]),

    ("a failed quest is drawn in the title color", [
        (R, "    if entry.state == STATE.FAILED then return 0.85, 0.27, 0.27, false end\n", "")]),

    ("the Classic focus tint loses to the state colors", [
        (R, "    if FOCUS_TINT and entry.isFocused then", "    if FOCUS_TINT and entry.isFocused and entry.state == STATE.ACTIVE then")]),

    ("every mode with a color is lit by a hover", [
        (R, "    if r then return r, g, b, Util.TitleColorMode(cfg) == \"original\" end",
            "    if r then return r, g, b, true end")]),

    ("Custom with no color picked yet draws difficulty colors", [
        (R, "    if Util.TitleColorMode(cfg) == \"difficulty\" and entry.level",
            "    if Util.TitleColorMode(cfg) ~= \"gold\" and entry.level")]),

    ("the plain gold drifts", [
        (R, "    return 0.92, 0.72, 0.02, false\nend", "    return 0.92, 0.72, 0.03, false\nend")]),

    ("a hover lights a title that is not Original Style's", [
        (R, "    if row._hovered and row._tLit then hr, hg, hb = Util.OriginalTitleHighlight() end",
            "    if row._hovered then hr, hg, hb = Util.OriginalTitleHighlight() end")]),

    ("a row never rendered is painted anyway", [
        (R, "    elseif row._tR then\n", "    else\n")]),

    ("entering a row never lights it", [
        (R, "    row._hovered = true\n    paintTitle(row)\n", "    row._hovered = true\n")]),

    ("leaving a row never puts the color back", [
        (R, "            frame._hovered = nil\n            paintTitle(frame)\n", "            frame._hovered = nil\n")]),

    ("a retired row keeps its hover", [
        (R, "    row._hintShown, row._hintClock, row._hovered = nil, nil, nil\n",
            "    row._hintShown, row._hintClock = nil, nil\n")]),

    ("Render paints the title itself, so a hover is lost on every repaint", [
        (R, "    row._tR, row._tG, row._tB, row._tLit = tr, tg, tb, lit\n    paintTitle(row)\n",
            "    row._tR, row._tG, row._tB, row._tLit = tr, tg, tb, lit\n    row.title:SetTextColor(tr, tg, tb)\n")]),

    ("the status line reports the finished color as the active one", [
        (R, "    local cr, cg, cb = Util.OriginalTitleColor(true)\n",
            "    local cr, cg, cb = Util.OriginalTitleColor(false)\n")]),

    # ----------------------------------------------------------- around the row
    ("the mode gets an AceDB default, so every old profile reads By difficulty", [
        (D, "            titleColorOverride    = nil,\n",
            "            titleColorOverride    = nil,\n            titleColorMode        = \"difficulty\",\n")]),

    ("Reset to Defaults leaves difficulty switched off, so it lands on Gold", [
        (D, "    \"titleColorMode\", \"colorByDifficulty\",\n", "    \"titleColorMode\",\n")]),

    ("/eqot status drops the line", [
        (C, "    debugLine(\"Row\", nil, \"TitleColorLine\")\n", "")]),

    ("Reset to Defaults keeps the custom title color, so the reset profile reads as Custom color", [
        (D, '    "titleColorOverride", "overrideCompleteGreen", "headerColor",', '    "overrideCompleteGreen", "headerColor",')]),

    ("Reset to Defaults keeps the class switch, so the reset profile reads as Class color", [
        (D, '    "titleColorUseClass", "headerColorUseClass",', '    "headerColorUseClass",')]),

    ("the custom title color gets an AceDB default, so every old profile reads as Custom color", [
        (D, "            titleColorOverride    = nil,", "            titleColorOverride    = { r = 1, g = 0.82, b = 0 },")]),

    ("the status line reads the saved key, so an upgraded profile reports By difficulty", [
        (R, "        :format(Util.TitleColorMode(cfg), r, g, b, cr, cg, cb,",
            "        :format(cfg.titleColorMode or \"difficulty\", r, g, b, cr, cg, cb,")]),

    ("the status line never reports the finished quest color", [
        (R, "                picked(cfg and cfg.finishedQuestColor), picked(cfg and cfg.newTagColor))\n",
            "                \"unset\", picked(cfg and cfg.newTagColor))\n")]),

    ("the status line swaps the two picked colors", [
        (R, "                picked(cfg and cfg.finishedQuestColor), picked(cfg and cfg.newTagColor))\n",
            "                picked(cfg and cfg.newTagColor), picked(cfg and cfg.finishedQuestColor))\n")]),

    ("the status line prints a picked color's channels out of order", [
        (R, '        return ("%.2f %.2f %.2f"):format(c.r, c.g, c.b)\n', '        return ("%.2f %.2f %.2f"):format(c.r, c.b, c.g)\n')]),

    ("an empty color in the status line reads as picked", [
        (R, '        if not (c and c.r) then return "unset" end\n', '        if not c then return "unset" end\n')]),

    # ------------------------------------------------------- Finished Quest Color (2026-10-10)
    ("the finished quest color is never read", [
        (R, "    local fq = complete and cfg and cfg.finishedQuestColor\n"
            "    if fq and fq.r then return fq.r, fq.g, fq.b, false end\n", "")]),

    ("the finished quest color colors every title, finished or not", [
        (R, "    local fq = complete and cfg and cfg.finishedQuestColor\n",
            "    local fq = cfg and cfg.finishedQuestColor\n")]),

    ("a picked finished objective color recolors finished titles too", [
        (R, "    local fq = complete and cfg and cfg.finishedQuestColor\n",
            "    local fq = complete and cfg and (cfg.finishedQuestColor or cfg.finishedObjectiveColor)\n")]),

    ("a picked finished objective color wins over a picked finished quest color", [
        (R, "    local fq = complete and cfg and cfg.finishedQuestColor\n",
            "    local fq = complete and cfg and (cfg.finishedObjectiveColor or cfg.finishedQuestColor)\n")]),

    # Each of these has an AceDB default, so in game it recolors every finished title.
    ("an unset finished quest color falls back to Count Color: Done", [
        (R, "    local fq = complete and cfg and cfg.finishedQuestColor\n",
            "    local fq = complete and cfg and (cfg.finishedQuestColor or cfg.countColorDone)\n")]),

    ("an unset finished quest color falls back to the objective text color", [
        (R, "    local fq = complete and cfg and cfg.finishedQuestColor\n",
            "    local fq = complete and cfg and (cfg.finishedQuestColor or cfg.objectiveColor)\n")]),

    ("an unset finished quest color falls back to the NEW tag color", [
        (R, "    local fq = complete and cfg and cfg.finishedQuestColor\n",
            "    local fq = complete and cfg and (cfg.finishedQuestColor or cfg.newTagColor)\n")]),

    ("the status line reports the finished objective color for an unset finished quest color", [
        (R, "picked(cfg and cfg.finishedQuestColor)", "picked(cfg and (cfg.finishedQuestColor or cfg.finishedObjectiveColor))")]),

    ("the status line reports the custom title color for an unset NEW tag color", [
        (R, "picked(cfg and cfg.newTagColor))", "picked(cfg and (cfg.titleColorOverride or cfg.newTagColor)))")]),

    ("the status line reports the NEW tag color for an unset finished quest color", [
        (R, "picked(cfg and cfg.finishedQuestColor)", "picked(cfg and (cfg.finishedQuestColor or cfg.newTagColor))")]),

    ("the status line raises with no profile loaded", [
        (R, "picked(cfg and cfg.finishedQuestColor), picked(cfg and cfg.newTagColor))",
            "picked(cfg.finishedQuestColor), picked(cfg.newTagColor))")]),

    ("an empty color table counts as a picked finished quest color", [
        (R, "    if fq and fq.r then return fq.r, fq.g, fq.b, false end\n",
            "    if fq then return fq.r, fq.g, fq.b, false end\n")]),

    ("a picked finished quest color is lit by a hover", [
        (R, "    if fq and fq.r then return fq.r, fq.g, fq.b, false end\n",
            "    if fq and fq.r then return fq.r, fq.g, fq.b, true end\n")]),

    ("the finished quest color's green and blue are swapped", [
        (R, "    if fq and fq.r then return fq.r, fq.g, fq.b, false end\n",
            "    if fq and fq.r then return fq.r, fq.b, fq.g, false end\n")]),

    ("the finished quest color applies only with the completed box on", [
        (R, "    local fq = complete and cfg and cfg.finishedQuestColor\n",
            "    local fq = complete and cfg and cfg.overrideCompleteGreen ~= false and cfg.finishedQuestColor\n")]),

    ("the finished quest color only replaces green, so a mode's title color beats it", [
        (R, "    local fq = complete and cfg and cfg.finishedQuestColor\n"
            "    if fq and fq.r then return fq.r, fq.g, fq.b, false end\n", ""),
        (R, "    if complete and not (r and (not cfg or cfg.overrideCompleteGreen ~= false)) then\n"
            "        return 0.27, 0.85, 0.27, false\n",
            "    if complete and not (r and (not cfg or cfg.overrideCompleteGreen ~= false)) then\n"
            "        local fq = cfg and cfg.finishedQuestColor\n"
            "        if fq and fq.r then return fq.r, fq.g, fq.b, false end\n"
            "        return 0.27, 0.85, 0.27, false\n")]),

    ("the finished quest color beats the Classic focus tint", [
        (R, "local function titleColor(entry, cfg)\n    if FOCUS_TINT and entry.isFocused then\n",
            "local function titleColor(entry, cfg)\n"
            "    local fq0 = entry.state == STATE.COMPLETE and cfg and cfg.finishedQuestColor\n"
            "    if fq0 and fq0.r then return fq0.r, fq0.g, fq0.b, false end\n"
            "    if FOCUS_TINT and entry.isFocused then\n")]),

    ("finished objective lines follow the finished quest color", [
        (R, "    if f and f.r then return Util.Hex(f.r, f.g, f.b) end\n",
            "    if f and f.r then return Util.Hex(f.r, f.g, f.b) end\n"
            "    local q = cfg and cfg.finishedQuestColor\n"
            "    if q and q.r then return Util.Hex(q.r, q.g, q.b) end\n")]),

    ("the finished quest color gets an AceDB default, so every finished title changes on upgrade", [
        (D, "            newTagColor        = { r = 107 / 255, g = 175 / 255, b = 1 },\n",
            "            newTagColor        = { r = 107 / 255, g = 175 / 255, b = 1 },\n"
            "            finishedQuestColor = { r = 0.27, g = 0.85, b = 0.27 },\n")]),

    ("Reset to Defaults keeps the finished quest color", [
        (D, '    "finishedQuestColor", "newTagColor",\n', '    "newTagColor",\n')]),

    # ------------------------------------------------------------- the NEW tag's color (2026-10-10)
    ("the NEW tag ignores the picked color", [
        (R, "        text = newTagFor(cfg) .. text\n", "        text = NEW_TAG .. text\n")]),

    ("the tag's cache never notices red moving", [
        (R, "    elseif newRGB.r ~= c.r or newRGB.g ~= c.g or newRGB.b ~= c.b then\n",
            "    elseif newRGB.g ~= c.g or newRGB.b ~= c.b then\n")]),

    ("the tag's cache never notices green moving", [
        (R, "    elseif newRGB.r ~= c.r or newRGB.g ~= c.g or newRGB.b ~= c.b then\n",
            "    elseif newRGB.r ~= c.r or newRGB.b ~= c.b then\n")]),

    ("the tag's cache never notices blue moving", [
        (R, "    elseif newRGB.r ~= c.r or newRGB.g ~= c.g or newRGB.b ~= c.b then\n",
            "    elseif newRGB.r ~= c.r or newRGB.g ~= c.g then\n")]),

    ("the tag's cache outlives an unset, so the same pick after it is never taken", [
        (R, "        newTag, newRGB.r = NEW_TAG, nil\n", "        newTag = NEW_TAG\n")]),

    ("the tag's cache stores green as blue, so green moved onto blue's value is never seen", [
        (R, "        newRGB.r, newRGB.g, newRGB.b = c.r, c.g, c.b\n", "        newRGB.r, newRGB.g, newRGB.b = c.r, c.b, c.b\n")]),

    ("an empty color table counts as a picked tag color", [
        (R, "    local c = cfg.newTagColor\n    if not (c and c.r) then\n",
            "    local c = cfg.newTagColor\n    if not c then\n")]),

    ("the tag's red and blue are swapped", [
        (R, '        newTag = "|cff" .. Util.Hex(c.r, c.g, c.b) .. "NEW|r "\n',
            '        newTag = "|cff" .. Util.Hex(c.b, c.g, c.r) .. "NEW|r "\n')]),

    ("a picked tag loses the space before the title", [
        (R, '        newTag = "|cff" .. Util.Hex(c.r, c.g, c.b) .. "NEW|r "\n',
            '        newTag = "|cff" .. Util.Hex(c.r, c.g, c.b) .. "NEW|r"\n')]),

    ("the fallback blue drifts", [
        (R, 'local NEW_TAG    = "|cff6bafffNEW|r "\n', 'local NEW_TAG    = "|cff6bafeeNEW|r "\n')]),

    ("the shipped default blue drifts", [
        (D, "            newTagColor        = { r = 107 / 255, g = 175 / 255, b = 1 },\n",
            "            newTagColor        = { r = 107 / 255, g = 175 / 255, b = 0.9 },\n")]),

    ("Reset to Defaults keeps the NEW tag color", [
        (D, '    "finishedQuestColor", "newTagColor",\n', '    "finishedQuestColor",\n')]),

    ("the NEW tag lasts a second longer", [
        (R, "local NEW_WINDOW = 3600\n", "local NEW_WINDOW = 3601\n")]),

    ("the NEW tag still shows at exactly an hour", [
        (R, "       and (time() - entry.addedAt) < NEW_WINDOW then\n",
            "       and (time() - entry.addedAt) <= NEW_WINDOW then\n")]),

    ("the NEW tag ignores the Tracker tab's switch", [
        (R, "    if cfg.showRecentlyAddedTag ~= false and entry.addedAt and entry.addedAt > 0\n",
            "    if entry.addedAt and entry.addedAt > 0\n")]),

    ("titles are decorated on every provider's rows", [
        (R, "    if not cfg or entry.providerID ~= TITLE_META_PROVIDER then return text end\n",
            "    if not cfg then return text end\n")]),

    ("a pin's star comes before the NEW tag", [
        (R, "    if ns:GetModule(\"Filter\"):IsPinned(entry) then\n        text = PIN_TAG .. text\n    end\n", ""),
        (R, "        text = newTagFor(cfg) .. text\n    end\n    return text\n",
            "        text = newTagFor(cfg) .. text\n    end\n"
            "    if ns:GetModule(\"Filter\"):IsPinned(entry) then text = PIN_TAG .. text end\n    return text\n")]),

    ("the pin test is called with a dot, which raises in game", [
        (R, "    if ns:GetModule(\"Filter\"):IsPinned(entry) then\n",
            "    if ns:GetModule(\"Filter\").IsPinned(entry) then\n")]),

    ("Render draws the bare title, so no tag or level is ever seen", [
        (R, "    row.title:SetText(titleText)\n", "    row.title:SetText(entry.title or \"\")\n")]),
]

SUMMARY = re.compile(r"^test_title_color: (\d+) passed, (\d+) failed$")


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
