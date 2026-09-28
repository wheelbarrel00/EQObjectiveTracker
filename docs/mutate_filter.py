"""Prove docs/test_filter.lua actually discriminates, by breaking production on purpose one change
at a time and checking the harness notices.

    python docs/mutate_filter.py        (run from the repo root)

Why this exists: the campaign exemption from the current-zone filter is a one-line condition in
Data/Filter.lua, and every way it can go wrong is silent. Dropped, the player who asked for it
loses every campaign quest outside the current zone. Widened, it keeps normal quests the zone
filter should hide, or overrules Show only tracked quests, which the author decided on 2026-09-27
it must never do. Its tag, its checkbox and its default live in three other files, and a key
spelled differently in any of them switches the feature off with nothing on screen to say so.

Every mutation reintroduces a defect the harness is supposed to stand guard over. Any that still
reports "0 failed" is an assertion that does not discriminate, and the run exits 1 naming it.

WRITES TO THE TREE. It edits in place and restores through a finally, so an interrupted run still
puts the files back, and it verifies the restore and re-checks the baseline before reporting.

Anchors are exact source text and they rot. A SKIPPED line means an anchor stopped matching: fix
the anchor rather than dropping the mutant.
"""
import io
import re
import subprocess
import sys

LUA = r"C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe"
HARNESS = "docs/test_filter.lua"

F = "Data/Filter.lua"
D = "Core/DB.lua"
O = "Options/TabTracker.lua"
Q = "Data/Providers/Quests.lua"

EXEMPT = "            if f.campaignAnyZone and entry.tags and entry.tags.campaign then"
KEPT = "                self.campaignKept = self.campaignKept + 1\n"
# Built in pieces only to match the harness, whose needles must hide from the .lua locale scanners.
RESET_NEW = ("L" + '["Turns every category filter back on, clears the current-zone filter and turns'
             ' off Always show campaign quests. Nothing else on this tab is changed."]')
RESET_OLD = ("L" + '["Turns every category filter back on and clears the current-zone filter.'
             ' Nothing else on this tab is changed."]')
RESET_TIP = ("            campaignZone\n"
             "                and " + RESET_NEW + "\n"
             "                or " + RESET_OLD + ")\n")

MUTANTS = [
    # ------------------------------------------------------------------- the exemption itself
    ("the exemption is gone, so the zone filter hides campaign quests again", [
        (F, EXEMPT, "            if false then")]),

    ("the exemption ignores its own switch and ships on for everyone", [
        (F, EXEMPT, "            if entry.tags and entry.tags.campaign then")]),

    ("the exemption keeps every out-of-zone quest, not just campaign ones", [
        (F, EXEMPT, "            if f.campaignAnyZone and entry.tags then")]),

    ("the nil-tags guard is dropped, so an entry with no tags table raises", [
        (F, EXEMPT, "            if f.campaignAnyZone and entry.tags.campaign then")]),

    # Moved ahead of the zone test, it fires with the zone filter off and for a quest already in
    # the zone, which is only visible in the count.
    ("the exemption is asked before the zone test rather than after it", [
        (F, "        if f and f.onlyCurrentZone and provider.IsCurrentZone\n"
            "           and provider:IsCurrentZone(entry) == false then\n",
            "        if f and f.campaignAnyZone and entry.tags and entry.tags.campaign then\n"
            "            self.campaignKept = self.campaignKept + 1\n"
            "        elseif f and f.onlyCurrentZone and provider.IsCurrentZone\n"
            "           and provider:IsCurrentZone(entry) == false then\n"),
        (F, EXEMPT, "            if false then")]),

    # The harness hands Filter a literal tag, so only a grep sees the provider stop writing it.
    ("the quest provider writes the campaign tag under another name", [
        (Q, "if isCampaign(id, info) then tags.campaign = true end",
            "if isCampaign(id, info) then tags.campaigns = true end")]),

    # ---------------------------------------------------- the rules it must never overrule
    ("the exemption jumps Show only tracked quests, against the author's decision", [
        (F, "    if cfg and cfg.showOnlyWatched and entry.isTracked == false then\n",
            "    if cfg and cfg.filters and cfg.filters.campaignAnyZone and entry.tags"
            " and entry.tags.campaign then return true end\n"
            "    if cfg and cfg.showOnlyWatched and entry.isTracked == false then\n")]),

    ("the exemption jumps the Campaign quests category", [
        (F, "        if not self:PassesCategory(entry, f) then\n",
            "        if f and f.campaignAnyZone and entry.tags and entry.tags.campaign"
            " then return true end\n"
            "        if not self:PassesCategory(entry, f) then\n")]),

    # --------------------------------------------------------------------------- the count
    ("a kept row is never counted", [
        (F, KEPT, "")]),

    ("a kept row is counted as a zone reject as well", [
        (F, KEPT, KEPT + "                rejects.zone = rejects.zone + 1\n")]),

    ("BeginPass leaves the last pass's count standing", [
        (F, "    r.popup, r.watched, r.category, r.zone = 0, 0, 0, 0\n"
            "    self.campaignKept = 0\n",
            "    r.popup, r.watched, r.category, r.zone = 0, 0, 0, 0\n")]),

    # ---------------------------------------------------------------------- the status line
    ("the status line prints the zone flag in the campaign slot", [
        (F, "                tostring(f and f.campaignAnyZone and true or false),",
            "                tostring(f and f.onlyCurrentZone and true or false),")]),

    ("the status line loses its no-filters guard and raises on an empty profile", [
        (F, "                tostring(f and f.campaignAnyZone and true or false),",
            "                tostring(f.campaignAnyZone and true or false),")]),

    ("the status line prints a literal zero rather than the count", [
        (F, "r.watched, r.category, r.zone, r.popup, self.campaignKept)",
            "r.watched, r.category, r.zone, r.popup, 0)")]),

    ("the status line drops the switch", [
        (F, "onlyCurrentZone=%s campaignAnyZone=%s | %s", "onlyCurrentZone=%s | %s"),
        (F, "                tostring(f and f.campaignAnyZone and true or false),\n", "")]),

    # --------------------------------------------------------------------------- the default
    ("the default ships ON, changing the tracker for every zone-filter user", [
        (D, "                campaignAnyZone = false,", "                campaignAnyZone = true,")]),

    ("the default is dropped from the filters table", [
        (D, "                campaignAnyZone = false,\n", "")]),

    # ----------------------------------------------------------------------------- the panel
    ("the checkbox writes a key Filter never reads", [
        (O, "function(v) DB().filters.campaignAnyZone = v; render() end,",
            "function(v) DB().filters.campaignAnyZones = v; render() end,")]),

    ("the checkbox reads a key nothing writes", [
        (O, "function() return DB().filters.campaignAnyZone end,",
            "function() return DB().filters.campaignAnyZones end,")]),

    ("Reset filters leaves the exemption on", [
        (O, "                f.campaignAnyZone = false\n", "")]),

    # The author's call on 2026-09-27: the reset tooltip names the campaign option where its box
    # is built, and keeps the old, still true wording and its translations everywhere else.
    ("the reset tooltip names the campaign option on Classic too, where there is no box", [
        (O, RESET_TIP, "            " + RESET_NEW + ")\n")]),

    ("the reset tooltip never names the campaign option", [
        (O, RESET_TIP, "            " + RESET_OLD + ")\n")]),

    # The author's call on 2026-09-27: grayed out while the zone filter was off, it read as an
    # option that only worked in one situation.
    ("the box is grayed out again while the zone filter is off", [
        (O, "            filtersEnd = campaignZone\n",
            "            filtersEnd = campaignZone\n"
            "            self:SetDependent(campaignZone, DB().filters.onlyCurrentZone)\n")]),

    ("the box is built on Classic too, where nothing can tag a campaign quest", [
        (O, '        if Registry:HasTag("campaign") then', "        if true then")]),

    ("Reset filters hangs from the zone filter again and draws over the new box", [
        (O, 'resetFilters:SetPoint("TOPLEFT", filtersEnd, "BOTTOMLEFT", 0, -10)',
            'resetFilters:SetPoint("TOPLEFT", zoneOnly, "BOTTOMLEFT", 0, -10)')]),

    ("the box never becomes the end of the run", [
        (O, "            filtersEnd = campaignZone\n", "")]),

    # A reworded key orphans every translation of it and opens a store round trip.
    ("the label is reworded, orphaning its translations", [
        (O, 'L["Always show campaign quests"]', 'L["Always show all campaign quests"]')]),

    # ------------------------------------------------- hand-broken in the 2026-09-27 scan
    ("an absent campaignAnyZone reads as on", [
        (F, "            if f.campaignAnyZone and entry.tags and entry.tags.campaign then",
            "            if f.campaignAnyZone ~= false and entry.tags and entry.tags.campaign then")]),

    ("a kept row is hidden anyway", [
        (F, "                self.campaignKept = self.campaignKept + 1\n"
            "            else\n"
            "                rejects.zone = rejects.zone + 1\n"
            "                return false\n"
            "            end\n",
            "                self.campaignKept = self.campaignKept + 1\n"
            "            else\n"
            "                rejects.zone = rejects.zone + 1\n"
            "            end\n"
            "            return false\n")]),

    ("the status prints the zone count in the kept slot", [
        (F, "r.watched, r.category, r.zone, r.popup, self.campaignKept)",
            "r.watched, r.category, r.zone, r.popup, r.zone)")]),

    ("the status prints nil rather than false for an absent switch", [
        (F, "                tostring(f and f.campaignAnyZone and true or false),",
            "                tostring(f and f.campaignAnyZone),")]),

    ("the campaign box stores but never re-renders", [
        (O, "function(v) DB().filters.campaignAnyZone = v; render() end,",
            "function(v) DB().filters.campaignAnyZone = v; end,")]),

    ("Reset filters clears the key but leaves the box drawn checked", [
        (O, "                if campaignZone then campaignZone:SetChecked(false) end\n",
            "")]),

    ("filtersEnd starts at the campaign box, which is nil on Classic", [
        (O, "        local filtersEnd = zoneOnly\n",
            "        local filtersEnd = campaignZone\n")]),

    # ------------------------------------------ hand-broken in the second 2026-09-27 scan
    ("the zone rule asks a provider that has no IsCurrentZone, raising on every world quest", [
        (F, "        if f and f.onlyCurrentZone and provider.IsCurrentZone\n",
            "        if f and f.onlyCurrentZone\n")]),

    ("a pin outranks the Complete popup, so the quest shows as a row and a box", [
        (F, "    if self:IsPinned(entry) then return true end\n", ""),
        (F, '    if provider and provider.idSpace == "quest" then\n'
            '        local Popups = ns:GetModule("AutoQuestPopups")\n',
            "    if self:IsPinned(entry) then return true end\n"
            '    if provider and provider.idSpace == "quest" then\n'
            '        local Popups = ns:GetModule("AutoQuestPopups")\n')]),

    ("campaignKept starts nil, so a status read before the first pass raises", [
        (F, "Filter.campaignKept = 0\n", "Filter.campaignKept = nil\n")]),

    ("the campaign box is grayed out again, spelled as a dot call", [
        (O, "            filtersEnd = campaignZone\n",
            "            filtersEnd = campaignZone\n"
            "            self.SetDependent(self, campaignZone, DB().filters.onlyCurrentZone)\n")]),

    ("the campaign box is disabled outright", [
        (O, "            filtersEnd = campaignZone\n",
            "            filtersEnd = campaignZone\n            campaignZone:Disable()\n")]),

    ("the box is built into a shadowing local, so Reset and the tooltip never see it", [
        (O, '            campaignZone = self:CreateCheckbox(content, L["Always show campaign quests"],',
            '            local campaignZone = self:CreateCheckbox(content, L["Always show campaign quests"],')]),

    ("the quest provider stops DECLARING the campaign tag, so the box is never built", [
        (Q, '    tags     = { "campaign", "daily",', '    tags     = { "daily",')]),
]

SUMMARY = re.compile(r"^test_filter: (\d+) passed, (\d+) failed$")


def run():
    """(verdict, note). verdict is "green", "failed" or "crashed".

    A nonzero exit is NOT evidence that an assertion discriminated - a mutant that does not parse
    exits nonzero too, and reporting that as "caught" is a false pass in the one tool whose job
    is to catch false passes. So the harness's own summary line is matched rather than its exit
    code, and a run that never got that far is its own verdict.
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
        # Asserted rather than assumed. Applying a mutant to a file that still holds the last
        # one is a silent no-op, and the run then reports the PREVIOUS mutant's result under
        # this mutant's name - a false pass in the tool meant to find them.
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
    # EQUIVALENT: marks a mutant that provably cannot change behavior, so it is EXPECTED to
    # survive and being caught is the finding.
    expected_equivalent = name.startswith("EQUIVALENT:")
    if verdict == "crashed":
        print("CRASHED   %-74s %s" % (name, last))
        failures.append(("CRASHED", name))
    elif verdict == "green" and not expected_equivalent:
        print("SURVIVED  %-74s %s" % (name, last))
        failures.append(("SURVIVED", name))
    elif verdict != "green" and expected_equivalent:
        print("UNEXPECTED %-73s %s" % (name + " (was caught)", last))
        failures.append(("UNEXPECTED", name))
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
    # Four different verdicts, never pooled. A SKIPPED anchor reported as a survivor sends the
    # reader hunting a coverage hole that is not there, and a CRASHED one hides an abort.
    for kind, label in (
            ("SURVIVED",   "mutant(s) survived - those assertions do not discriminate"),
            ("UNEXPECTED", "EQUIVALENT mutant(s) were caught - the equivalence claim is wrong"),
            ("CRASHED",    "mutant(s) aborted the harness rather than failing it"),
            ("SKIPPED",    "anchor(s) rotted - fix the anchor, never drop the mutant")):
        named = [name for verdict, name in failures if verdict == kind]
        if named:
            print("%d %s:" % (len(named), label))
            for name in named:
                print("  - " + name)
    sys.exit(1)
print("every mutant behaved as expected")
