"""Prove docs/test_about.lua actually discriminates, by breaking production on purpose one change
at a time and checking the harness notices.

    python docs/mutate_about.py        (run from the repo root)

Why this exists: since the 2.0.0 restyle the About tab is five cards whose rows are text blocks
that size themselves, and nearly every way that can go wrong is silent. A row added without
fitHeight keeps a fixed height while its wrapped text runs on over the next one. A link opens the
wrong page. The provider refresh, which is what a bug report reads, prints a wrong count or calls
a provider unavailable. And the theme the author approved (no gold, names bright, dates muted) can
drift back one escape at a time.

Every mutation reintroduces a defect the harness is supposed to stand guard over. Any that still
reports "0 failed" is an assertion that does not discriminate, and the run exits 1 naming it.

WRITES TO THE TREE. It edits in place and restores through a finally, so an interrupted run still
puts the files back, and it verifies the restore and re-checks the baseline before reporting.
This checkout is junctioned into AddOns, so run it from a scratch copy while the game is open.

Anchors are exact source text and they rot. A SKIPPED line means an anchor stopped matching: fix
the anchor rather than dropping the mutant.
"""
import io
import re
import subprocess
import sys

LUA = r"C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe"
HARNESS = "docs/test_about.lua"

A = "Options/TabAbout.lua"

MUTANTS = [
    # --------------------------------------------------------------------------- the cards
    ("Thanks comes before Commands", [
        (A, '        local commands = stack(self:CreateGroup(content, L["Commands"]))',
            '        local thanks = stack(self:CreateGroup(content, L["Thanks"]))\n'
            '        local commands = stack(self:CreateGroup(content, L["Commands"]))'),
        (A, '        local thanks = stack(self:CreateGroup(content, L["Thanks"]))\n        local bright',
            '        local bright')]),
    ("a card is built but never anchored, so it draws at the top of the tab", [
        (A, '        local providers = stack(self:CreateGroup(content, L["Content providers"]))',
            '        local providers = self:CreateGroup(content, L["Content providers"])')]),
    ("the cards touch, with no gap between them", [
        (A, '                card:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -gap)',
            '                card:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, 0)')]),
    ("the top card gets a group label", [
        (A, '        local intro = stack(self:CreateGroup(content, nil))',
            '        local intro = stack(self:CreateGroup(content, L["About"]))')]),

    # --------------------------------------------------------------------------- the top card
    ("the version line is a fixed-height row, so a wrapped description runs over the links", [
        (A, '        intro:Add(blurb, { fitHeight = true })', '        intro:Add(blurb)')]),
    ("the version line is drawn as a plain label", [
        (A, '.. L["by Wheelbarrel00"], "value")', '.. L["by Wheelbarrel00"], "label")')]),
    ("the version is left out of its line", [
        (A, 'L["Version %s"]:format(ns.VERSION)', 'L["Version %s"]')]),
    ("the link strip does not span its row", [
        (A, '        intro:Add(links, { fill = true })', '        intro:Add(links)')]),
    ("the links crowd together", [
        (A, '                b:SetPoint("LEFT", prev, "RIGHT", self:Spacing("buttonGap"), 0)',
            '                b:SetPoint("LEFT", prev, "RIGHT", 0, 0)')]),
    ("every link starts at the strip's left, one over another", [
        (A, '            prev = b\n', '')]),
    ("the Discord link opens a page instead of the invite", [
        (A, 'onClick = function() ns:ShowDiscord() end }', 'onClick = function() ns:ShowURL(CURSEFORGE_URL) end }')]),
    ("the CurseForge link opens GitHub", [
        (A, '{ label = L["CurseForge"],       onClick = function() ns:ShowURL(CURSEFORGE_URL) end }',
            '{ label = L["CurseForge"],       onClick = function() ns:ShowURL(GITHUB_URL) end }')]),
    ("Report a Bug opens the project page, not the issues", [
        (A, 'onClick = function() ns:ShowURL(BUG_URL) end }', 'onClick = function() ns:ShowURL(GITHUB_URL) end }')]),
    ("the bug link points at the wrong page", [
        (A, '"https://github.com/wheelbarrel00/EQObjectiveTracker/issues"',
            '"https://github.com/wheelbarrel00/EQObjectiveTracker/pulls"')]),

    # --------------------------------------------------------------------------- Commands
    ("a command row is full height instead of a list row", [
        (A, '            commands:Add(row, { height = listRow })', '            commands:Add(row)')]),
    ("the command is drawn in the label color like its description", [
        (A, '            row.label:SetTextColor(self:Color("text"))\n            commands:Add',
            '            commands:Add')]),
    ("a command is dropped", [
        (A, '    { "/eqot debug",    L["Toggle entry validation warnings"] },\n', '')]),

    # --------------------------------------------------------------------------- providers
    ("the provider note is a fixed-height row", [
        (A, '        providers:Add(note, { fitHeight = true })', '        providers:Add(note)')]),
    ("the provider note is drawn as a label, not a hint", [
        (A, 'A provider that is not listed was never loaded."], "hint")',
            'A provider that is not listed was never loaded."])')]),
    ("a provider row is full height", [
        (A, '            providers:Add(row, { height = listRow })', '            providers:Add(row)')]),
    ("the refresh cannot find the rows it built", [
        (A, '            content._providerRows[p.id] = row\n', '')]),
    ("every provider reads available", [
        (A, '                if not p._available then', '                if false then')]),
    ("an unavailable provider keeps a bright name", [
        (A, '                    row.label:SetTextColor(self:Color("muted"))\n', '')]),
    ("an available provider's name is muted", [
        (A, '                    row.label:SetTextColor(self:Color("text"))\n', '                    row.label:SetTextColor(self:Color("muted"))\n')]),
    ("a raising provider takes the tab down", [
        (A, '                    local ok, entries = pcall(p.GetEntries, p)',
            '                    local ok, entries = true, p:GetEntries()')]),
    ("a failed count prints -1", [
        (A, ':format(math.max(0, n), muted, table.concat(p.groups, ", ")))',
            ':format(n, muted, table.concat(p.groups, ", ")))')]),
    ("the groups are no longer muted", [
        (A, '("%d entries   %sgroups: %s|r")', '("%d entries   groups: %s%s")')]),
    ("a provider built after the tab breaks the refresh", [
        (A, '            if row then\n', '            do\n')]),

    # --------------------------------------------------------------------------- Thanks
    ("a credit is a fixed-height row", [
        (A, '            thanks:Add(credit, { fitHeight = true })', '            thanks:Add(credit)')]),
    ("the name is drawn in the label color", [
        (A, '        local bright = colorCode(self, "text")', '        local bright = colorCode(self, "label")')]),
    ("the escape around the name is never closed", [
        (A, 't.line:format(bright .. t.name .. "|r")', 't.line:format(bright .. t.name)')]),
    ("the color escape rounds down, so it is not the theme's color", [
        (A, 'math.floor(r * 255 + 0.5)', 'math.floor(r * 255)')]),

    # --------------------------------------------------------------------------- Changelog
    ("a version-less entry throws and blanks the window", [
        (A, '            if entry.version then\n', '            do\n')]),
    ("a version is a fixed-height row", [
        (A, '                changelog:Add(block, { fitHeight = true })', '                changelog:Add(block)')]),
    ("the date is drawn as bright as the version", [
        (A, 'entry.version .. "   " .. muted .. (entry.date or "") .. "|r"',
            'entry.version .. "   " .. (entry.date or "")')]),
    ("the version line is a plain label", [
        (A, '(entry.date or "") .. "|r", "value")', '(entry.date or "") .. "|r", "label")')]),
    ("the summary is drawn as a label", [
        (A, 'block:AddLine(entry.summary, "hint")', 'block:AddLine(entry.summary)')]),
    ("the summary is dropped", [
        (A, '                if entry.summary then block:AddLine(entry.summary, "hint") end\n', '')]),
    ("a section head loses its room above", [
        (A, '"groupLabel", { gap = 10 })', '"groupLabel")')]),
    ("a section head is drawn as a label", [
        (A, 'block:AddLine(sec.head or "", "groupLabel", { gap = 10 })',
            'block:AddLine(sec.head or "", "label", { gap = 10 })')]),
    ("items lose their bullets", [
        (A, 'block:AddLine(item, "label", { bullet = "-" })', 'block:AddLine(item, "label")')]),
    ("the CurseForge link is a secondary button", [
        (A, 'function() ns:ShowURL(CURSEFORGE_URL) end, nil, "ghost"))',
            'function() ns:ShowURL(CURSEFORGE_URL) end))')]),
    ("the CurseForge link at the foot of the changelog goes", [
        (A, '        changelog:Add(self:CreateButton(content, L["Older versions are on CurseForge"], nil,\n'
            '            function() ns:ShowURL(CURSEFORGE_URL) end, nil, "ghost"))\n', '')]),
]

SUMMARY = re.compile(r"^test_about: (\d+) passed, (\d+) failed$")


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
