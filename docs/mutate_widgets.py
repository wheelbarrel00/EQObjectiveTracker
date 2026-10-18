"""Prove docs/test_widgets.lua actually discriminates, by breaking Data/Widgets.lua on purpose
one change at a time and checking the harness notices.

    python docs/mutate_widgets.py               (run from the repo root)

Why this exists: this file carries the two highest-risk changes in the tree - the UPDATE_UI_WIDGET
set filter that cut the retail render rate, and the first-login crash fix beside it - and it had
no battery at all. An adversarial pass over the harness found two holes on a green run. Inverting
`if not setID then return true end` left 59 passed, 0 failed, because the only case reaching that
guard passed a NIL payload, which the type test one line above answers instead. And a secret set
id read raw failed CLOSED, refusing the repaint and the Invalidate behind it, which is the
opposite of what the comment above the filter promises.

Every mutation reintroduces a defect the harness is supposed to stand guard over. Any that still
reports "0 failed" is an assertion that does not discriminate, and the run exits 1 naming it -
unless the entry is marked EQUIVALENT, which means the mutation provably cannot change behavior
and so nothing could catch it. There are THREE of those and all are worth reading:

  - snapshot() is keyed on the set id, so the key IS the separation between the two callers'
    lists. Reaching that same table through rawget cannot collide any differently.
  - every writer of idsStale calls Invalidate in the same breath, so resolveIDs re-reads on the
    moved generation alone. That clause is a second floor, and it stops being equivalent the day
    something marks the pair stale WITHOUT invalidating - which the battery would then report.
  - a Lua table can never be made to raise on ~= against a number, so comparing the currency id
    raw rather than through num() cannot be told apart from here.

A CRASHED verdict is reported apart from "caught" on purpose. A mutant that does not parse also
exits nonzero, and counting that as caught is a false pass in the one tool whose job is to find
false passes.

WRITES TO THE TREE. It edits Data/Widgets.lua in place and restores it after every mutant through
a finally, then verifies the restore and re-checks the baseline before reporting. If you hard-kill
it, recover from your editor's undo history.

Anchors are exact source text and they rot. A SKIPPED line means an anchor stopped matching: fix
the anchor rather than dropping the mutant.
"""
import io
import re
import subprocess
import sys

LUA = r"C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe"
SRC = "Data/Widgets.lua"
HARNESS = "docs/test_widgets.lua"
SUMMARY = re.compile(r"^test_widgets: (\d+) passed, (\d+) failed$")

MUTANTS = [
    # ------------------------------------------------- the event filter and the login crash
    ("the payload is tested for truthiness, which indexes the login boolean",
     '        if type(widgetInfo) ~= "table" then return true end',
     "        if widgetInfo and widgetInfo.widgetSetID then return true end"),

    ("a payload carrying no set at all is refused instead of failing open",
     "        if not setID then return true end",
     "        if not setID then return false end"),

    ("the set id is read raw, so a secret value fails closed rather than absent",
     "        local setID = num(widgetInfo.widgetSetID)",
     "        local setID = widgetInfo.widgetSetID"),

    ("the staleness test goes, so a scenario that started since the last render is refused",
     "        if idsStale or not (trackerID or scenarioID) then return true end",
     "        if not (trackerID or scenarioID) then return true end"),

    ("the set-moving events stop marking the resolved pair stale",
     "    local function invalidate()\n        idsStale = true\n        self:Invalidate()\n    end",
     "    local function invalidate()\n        self:Invalidate()\n    end"),

    ("a payload with no set stops meaning everything moved",
     '        if type(widgetInfo) ~= "table" then idsStale = true end\n',
     ""),

    ("the filter is deleted outright, which is the render rate this release cut",
     "        if not ours(widgetInfo) then return end",
     "        if false then return end"),

    ("the repaint is refused but the bookkeeping goes with it, so a snapshot outlives its widgets",
     '        self:Invalidate()\n        local DB  = ns:GetModule("DB")',
     '        local DB  = ns:GetModule("DB")'),

    ("the widgets option stops switching the repaint off",
     "        if cfg and cfg.showTrackerWidgets == false then return end",
     "        if false then return end"),

    # ------------------------------------------------------------------ the snapshot cache
    ("the generation is ignored, so a stale snapshot is served forever",
     "    if snap and snap.gen == generation then return snap.list, snap.n end",
     "    if snap then return snap.list, snap.n end"),

    ("the cache is bypassed, which is the per-render API read it exists to stop",
     "    if snap and snap.gen == generation then return snap.list, snap.n end",
     "    if false then return snap.list, snap.n end"),

    ("Invalidate stops bumping the generation",
     "function Widgets:Invalidate()\n    generation = generation + 1",
     "function Widgets:Invalidate()"),

    ("the snapshot hands back the shared pool, so two callers alias one list",
     "    snap.n, snap.gen = outN, generation\n    return list, outN",
     "    snap.n, snap.gen = outN, generation\n    return out, outN"),

    ("the snapshot keeps a longer read's tail behind a shorter one",
     "    for i = outN + 1, #list do list[i] = nil end",
     "    -- tail left in place"),

    ("the prune drops the sets a render can still ask for, throwing away every burst",
     "        if id ~= trackerID and id ~= scenarioID then snaps[id] = nil end",
     "        snaps[id] = nil"),

    # ------------------------------------------------------------------ the read itself
    ("the pool's tail survives into table.sort, dragging a longer read's leftovers in",
     "    for i = outN + 1, #out do out[i] = nil end",
     "    -- tail left in place"),

    ("the ordering tie-break goes, and a bullet list comes out alphabetized",
     "local function byOrder(a, b)\n    if a.order ~= b.order then return a.order < b.order end\n"
     "    return a.seq < b.seq",
     'local function byOrder(a, b)\n    return (a.text or "") < (b.text or "")'),

    # EQUIVALENT today. Every writer of idsStale calls Invalidate in the same breath, so the
    # generation has always moved too and resolveIDs re-reads on that alone. The clause is a
    # second floor under that, and if a future change ever marks the pair stale WITHOUT
    # invalidating, this stops being equivalent and the battery says so by catching it.
    ("EQUIVALENT: resolveIDs leans on the generation alone rather than also on the stale flag",
     "    if idGen == generation and not idsStale then return end",
     "    if idGen == generation then return end"),

    # EQUIVALENT. snapshot() is keyed on the set id, so the key IS the separation between the two
    # callers' lists. Reaching the same table through rawget cannot collide any differently, and
    # snaps carries no metatable for rawget to bypass.
    ("EQUIVALENT: the snapshot table is reached through rawget rather than a plain index",
     "    local snap = snaps[setID]\n    if not snap then",
     "    local snap = rawget(snaps, setID)\n    if not snap then"),

    # ----------------------------------------------------------- the delve counters on the tier row
    ("the counters start at Tier 3",
     "local DELVE_COUNTERS_TIER = 4", "local DELVE_COUNTERS_TIER = 3"),
    ("the counters start at Tier 5",
     "local DELVE_COUNTERS_TIER = 4", "local DELVE_COUNTERS_TIER = 5"),
    ("Tier 4 itself falls below the line",
     "    if tier < DELVE_COUNTERS_TIER or not (showLives or alive) then",
     "    if tier <= DELVE_COUNTERS_TIER or not (showLives or alive) then"),
    ("the row is drawn with nothing to put on it",
     "    if tier < DELVE_COUNTERS_TIER or not (showLives or alive) then",
     "    if tier < DELVE_COUNTERS_TIER then"),
    ("the alive and total currencies are swapped",
     "local NEMESIS_ALIVE, NEMESIS_TOTAL = 3103, 3104", "local NEMESIS_ALIVE, NEMESIS_TOTAL = 3104, 3103"),
    ("this season's affix id is dropped",
     "local NEMESIS_SPELLS = { 1307638, 1270179 }", "local NEMESIS_SPELLS = { 1270179 }"),
    ("the older season's affix id is dropped",
     "local NEMESIS_SPELLS = { 1307638, 1270179 }", "local NEMESIS_SPELLS = { 1307638 }"),
    ("the lives come off the second currency",
     '    local c = type(list) == "table" and list[1]', '    local c = type(list) == "table" and list[2]'),
    ("the lives icon and tooltip are read raw, so secret ones are drawn",
     "    return lives, num(c.iconFileID), str(c.tooltip)",
     "    return lives, c.iconFileID, c.tooltip"),
    ("an empty lives tooltip is kept as text",
     "    return lives, num(c.iconFileID), str(c.tooltip)",
     "    return lives, num(c.iconFileID), plain(c.tooltip)"),
    ("a currency count is read raw, so a secret one raises in the comparison",
     '    return type(c) == "table" and num(c.quantity) or nil',
     '    return type(c) == "table" and c.quantity or nil'),
    ("the last listed affix wins rather than the first",
     "            if not found and isNemesisSpell(id) then",
     "            if isNemesisSpell(id) then"),
    ("an affix's empty tooltip text is kept, hiding the spell's own",
     "                found, tip = id, str(s.tooltip)",
     "                found, tip = id, plain(s.tooltip)"),
    ("the affix icon is read raw, so a secret one is drawn",
     "num((C_Spell.GetSpellTexture(id)))", "C_Spell.GetSpellTexture(id)"),
    ("the affix ids are never cleared, so the status line keeps every read's",
     "    for i = #spellIDs, 1, -1 do spellIDs[i] = nil end\n", ""),
    ("a failed lives read keeps pcall's error as the lives",
     "    if not okLives then lives = nil end\n", ""),
    ("a failed affix read keeps pcall's error as the spell",
     "    if not okSpell then spellID = nil end\n", ""),
    ("the status line forgets the lives",
     "    seenTier, seenLives, seenSpell = tier, lives, spellID",
     "    seenTier, seenLives, seenSpell = tier, nil, spellID"),
    ("the status line forgets the affix",
     "    seenTier, seenLives, seenSpell = tier, lives, spellID",
     "    seenTier, seenLives, seenSpell = tier, lives, nil"),
    ("the lives switch reads unset as off",
     "    local showLives = cfg and cfg.showDelveLives ~= false and lives ~= nil",
     "    local showLives = cfg and cfg.showDelveLives == true and lives ~= nil"),
    ("an unreadable lives number still makes the row",
     "    local showLives = cfg and cfg.showDelveLives ~= false and lives ~= nil",
     "    local showLives = cfg and cfg.showDelveLives ~= false"),
    ("the nemesis switch reads unset as off",
     "    if cfg and cfg.showNemesisGroups ~= false then\n        if nemesisHeld",
     "    if cfg and cfg.showNemesisGroups == true then\n        if nemesisHeld"),
    ("the hold is never served",
     "        if nemesisHeld and heldTotal then", "        if false then"),
    ("the hold is served with nothing held, so a new delve reads no count",
     "        if nemesisHeld and heldTotal then", "        if nemesisHeld then"),
    ("a fresh reading is never kept for the hold",
     "            heldAlive, heldTotal = alive, total\n", ""),
    ("all dead reads as no count, so the check never shows",
     "            if ok and a and t and a >= 0 and t > 0 then alive, total = a, t end",
     "            if ok and a and t and a > 0 and t > 0 then alive, total = a, t end"),
    ("a total of 0 is drawn",
     "            if ok and a and t and a >= 0 and t > 0 then alive, total = a, t end",
     "            if ok and a and t and a >= 0 and t >= 0 then alive, total = a, t end"),
    # The scan of the killed count (2026-10-17): the row draws total minus alive, so a wrong total
    # moves both of the numbers it shows.
    ("the hold serves a fresh total beside the held count",
     "            alive, total = heldAlive, heldTotal",
     "            alive, total = heldAlive, quantity(NEMESIS_TOTAL)"),
    ("a fresh total is never kept for the hold",
     "            heldAlive, heldTotal = alive, total",
     "            heldAlive, heldTotal = alive, heldTotal or total"),
    ("the entry carries three groups whatever the tier",
     "        o.nemAlive, o.nemTotal = alive, total",
     "        o.nemAlive, o.nemTotal = alive, 3"),
    ("a reading above the total never reaches the row",
     "            if ok and a and t and a >= 0 and t > 0 then alive, total = a, t end",
     "            if ok and a and t and a >= 0 and t > 0 and a <= t then alive, total = a, t end"),
    ("the row loses the tier",
     '    o.kind, o.text = "delve", tierText', '    o.kind = "delve"'),
    ("a pooled entry keeps the last read's lives",
     "    o.lives, o.livesIcon, o.livesTip = nil, nil, nil\n", ""),
    ("a pooled entry keeps the last read's nemesis",
     "    o.nemAlive, o.nemTotal, o.nemSpell, o.nemIcon, o.nemTip = nil, nil, nil, nil, nil\n", ""),
    ("a new scenario keeps the held count",
     "        heldAlive, heldTotal = nil, nil\n", ""),
    ("a new scenario keeps the status line's delve",
     "        seenTier, seenLives, seenSpell = nil, nil, nil\n", ""),
    ("the status line drops the held marker",
     'nemesisHeld and " held" or ""', '""'),
    ("the status line's count of groups alive reads like the tier row's count of groups killed",
     "nemesis alive %s/%s%s", "nemesis %s/%s%s"),

    # ------------------------------------------------------------------- the nemesis count's wait
    ("every currency starts the wait",
     "        if currencyID ~= NEMESIS_ALIVE and currencyID ~= NEMESIS_TOTAL then return end\n", ""),
    ("only a report naming both currencies at once starts the wait",
     "        if currencyID ~= NEMESIS_ALIVE and currencyID ~= NEMESIS_TOTAL then return end",
     "        if currencyID ~= NEMESIS_ALIVE or currencyID ~= NEMESIS_TOTAL then return end"),
    # EQUIVALENT here. A Lua table can never be made to raise on ~= against a number, so the
    # harness's secret stand-in cannot tell a raw compare from num(); in the client a secret value
    # raises when compared, which is what num() is for.
    ("EQUIVALENT: the currency id is compared raw",
     "        currencyID = num(currencyID)\n", ""),
    ("a report does not hold the count",
     "        nemesisHeld = true\n        if nemesisTimer", "        if nemesisTimer"),
    ("a second report does not cancel the first wait",
     "        if nemesisTimer then nemesisTimer:Cancel() end\n", ""),
    ("the wait is half a second",
     "local NEMESIS_SETTLE   = 1.0", "local NEMESIS_SETTLE   = 0.5"),
    ("the wait's end keeps holding",
     "        nemesisTimer, nemesisHeld = nil, false", "        nemesisTimer = nil"),
    ("the wait's end keeps the snapshot",
     "        nemesisTimer, nemesisHeld = nil, false\n        self:Invalidate()\n",
     "        nemesisTimer, nemesisHeld = nil, false\n"),
    ("the wait's end never repaints",
     "cfg.showTrackerWidgets ~= false then fire() end", "cfg.showTrackerWidgets ~= false then end"),
    ("the wait's end repaints with the widgets box off",
     "        if cfg and cfg.showNemesisGroups ~= false and cfg.showTrackerWidgets ~= false then fire() end",
     "        if cfg and cfg.showNemesisGroups ~= false then fire() end"),
    ("the wait's end reads the nemesis switch unset as off",
     "        if cfg and cfg.showNemesisGroups ~= false and cfg.showTrackerWidgets ~= false then fire() end",
     "        if cfg and cfg.showNemesisGroups == true and cfg.showTrackerWidgets ~= false then fire() end"),
    ("the currency event is subscribed on every client",
     '    if ns.Has.DelveHeader then Events:On("CURRENCY_DISPLAY_UPDATE", nemesisMoved) end',
     '    Events:On("CURRENCY_DISPLAY_UPDATE", nemesisMoved)'),
    ("the currency event is never subscribed",
     '    if ns.Has.DelveHeader then Events:On("CURRENCY_DISPLAY_UPDATE", nemesisMoved) end',
     '    if false then Events:On("CURRENCY_DISPLAY_UPDATE", nemesisMoved) end'),
]


def run():
    """(verdict, note). verdict is "green", "failed" or "crashed".

    The harness's own summary line is matched rather than its exit code. A mutant that does not
    parse exits nonzero too, and reporting that as "caught" is a false pass in the one tool whose
    job is to catch false passes.
    """
    r = subprocess.run([LUA, HARNESS], capture_output=True, text=True)
    for line in reversed([l for l in r.stdout.splitlines() if l.strip()]):
        m = SUMMARY.match(line.strip())
        if m:
            return ("failed" if int(m.group(2)) else "green"), line.strip()
    return "crashed", (r.stderr.strip().splitlines() or ["no output"])[0][:90]


original = io.open(SRC, encoding="utf-8", newline="").read()
crlf = "\r\n" in original


def fit(s):
    return s.replace("\n", "\r\n") if crlf else s


verdict, last = run()
print("baseline: %s\n" % last)
if verdict != "green":
    print("BASELINE IS NOT GREEN - stopping")
    sys.exit(1)

survivors = []
for name, old, new in MUTANTS:
    old, new = fit(old), fit(new)
    if original.count(old) != 1:
        print("SKIPPED (anchor matched %d times): %s" % (original.count(old), name))
        survivors.append(name)
        continue
    try:
        io.open(SRC, "w", encoding="utf-8", newline="").write(original.replace(old, new, 1))
        verdict, last = run()
    finally:
        io.open(SRC, "w", encoding="utf-8", newline="").write(original)
    equivalent = name.startswith("EQUIVALENT:")
    if verdict == "crashed":
        print("CRASHED   %-78s %s" % (name, last))
        survivors.append(name)
    elif verdict == "green" and not equivalent:
        print("SURVIVED  %-78s %s" % (name, last))
        survivors.append(name)
    elif verdict == "failed" and equivalent:
        print("UNEXPECTED %-77s %s" % (name + " (was caught)", last))
        survivors.append(name)
    elif equivalent:
        print("survived  %-78s as expected, it cannot change behavior" % name)
    else:
        print("caught    %-78s %s" % (name, last))

if io.open(SRC, encoding="utf-8", newline="").read() != original:
    print("\nTHE TREE WAS NOT RESTORED - %s still holds a mutant" % SRC)
    sys.exit(1)
verdict, last = run()
if verdict != "green":
    print("\nBASELINE IS NOT GREEN AFTER THE RUN - %s" % last)
    sys.exit(1)

print()
if survivors:
    print("%d mutant(s) survived - those assertions do not discriminate:" % len(survivors))
    for s in survivors:
        print("  - " + s)
    sys.exit(1)
print("every mutant behaved as expected")
