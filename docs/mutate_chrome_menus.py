"""Prove docs/test_chrome_menus.lua actually discriminates, by breaking production on purpose one
change at a time and checking the harness notices.

    python docs/mutate_chrome_menus.py        (run from the repo root)

Why this exists: the right-click menus of the bonus objectives HUD and the floating zone progress
bar had no coverage at all until 2.0 moved them from Blizzard's MenuUtil to the EverythingUI
library's menu. Every way of getting one wrong is quiet: a lock item that names the wrong verb,
an action that writes the saved block after applying it so the frame draws the old state, a reset
that lands somewhere other than the frame's own default, or a field the library does not know,
which raises on every right-click.

Every mutation reintroduces a defect the harness is supposed to stand guard over. Any that still
reports "0 failed" is an assertion that does not discriminate, and the run exits 1 naming it.

WRITES TO THE TREE. It edits in place and restores through a finally, so an interrupted run
still puts the file back, and it verifies the restore and re-checks the baseline before
reporting. Run it from a scratch copy of the repo while anything else may touch the tree.

Anchors are exact source text and they rot. A SKIPPED line means an anchor stopped matching:
fix the anchor rather than dropping the mutant.
"""
import io
import re
import subprocess
import sys

LUA = r"C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe"
HARNESS = "docs/test_chrome_menus.lua"

HUD = "UI/ScenarioBonusHUD.lua"
ZONE = "UI/ZoneProgressBar.lua"


def menu_mutants(tag, f, mod, state_fn, title, reset_y):
    lock = "            if s then s.locked = not s.locked end\n"
    apply_ = "            %s:ApplySettings()\n" % mod
    reset = '            if s then s.point, s.relPoint, s.x, s.y = "CENTER", "CENTER", 0, %s end\n' % reset_y
    tail = '        { kind = "divider" },\n        { text = L["Cancel"] },\n'
    return [
        ("%s: the frame guard is dropped, so a menu opens before the frame exists" % tag, [
            (f, "function %s:_ContextMenu()\n    if not self.frame then return end\n" % mod,
                "function %s:_ContextMenu()\n" % mod)]),

        ("%s: a profile that cannot be read stops the menu with a Lua error" % tag, [
            (f, "    if not self.frame then return end\n    local st = %s() or {}\n" % state_fn,
                "    if not self.frame then return end\n    local st = %s()\n" % state_fn)]),

        ("%s: the library is never asked" % tag, [
            (f, '    ns:GetModule("Options").ui:ShowMenu({', "    local _ = ({")]),

        ("%s: the title row is dropped" % tag, [
            (f, '        { kind = "title", text = L["%s"] },\n' % title, "")]),

        ("%s: the lock item names the state it is in, not the one it leaves" % tag, [
            (f, 'st.locked and L["Unlock (allow moving)"] or L["Lock position"]',
                'st.locked and L["Lock position"] or L["Unlock (allow moving)"]')]),

        ("%s: Lock only ever locks" % tag, [
            (f, lock, "            if s then s.locked = true end\n")]),

        ("%s: Lock applies before it writes, so the frame draws the old lock" % tag, [
            (f, lock + apply_, apply_ + lock)]),

        ("%s: Lock is never applied" % tag, [
            (f, lock + apply_, lock)]),

        ("%s: Lock with no profile indexes nil" % tag, [
            (f, lock, "            s.locked = not s.locked\n")]),

        ("%s: Reset is never applied" % tag, [
            (f, reset + apply_, reset)]),

        ("%s: Reset applies before it writes" % tag, [
            (f, reset + apply_, apply_ + reset)]),

        ("%s: Reset lands at the screen's middle instead of the frame's own default" % tag, [
            (f, '"CENTER", "CENTER", 0, %s end' % reset_y, '"CENTER", "CENTER", 0, 0 end')]),

        ("%s: Reset keeps the old relative point" % tag, [
            (f, 's.point, s.relPoint, s.x, s.y = "CENTER", "CENTER", 0, %s' % reset_y,
                's.point, s.x, s.y = "CENTER", 0, %s' % reset_y)]),

        ("%s: Reset with no profile indexes nil" % tag, [
            (f, reset, '            s.point, s.relPoint, s.x, s.y = "CENTER", "CENTER", 0, %s\n' % reset_y)]),

        ("%s: Reset is marked danger, drawing a harmless action in red" % tag, [
            (f, '        { text = L["Reset position"], onClick = function()',
                '        { text = L["Reset position"], danger = true, onClick = function()')]),

        ("%s: the divider before Cancel is dropped" % tag, [
            (f, tail, '        { text = L["Cancel"] },\n')]),

        ("%s: Cancel is dropped" % tag, [
            (f, tail, '        { kind = "divider" },\n')]),

        # The library raises on a field it does not know, which would be a Lua error on every
        # right-click of the frame.
        ("%s: a row carries a field the library does not know" % tag, [
            (f, '        { text = L["Cancel"] },\n', '        { text = L["Cancel"], id = "cancel" },\n')]),

        # The menu is reached only from the frame's own mouse release.
        ("%s: a right-click opens nothing" % tag, [
            (f, '        if button == "RightButton" then %s:_ContextMenu() end' % mod,
                '        if button == "LeftButton" then %s:_ContextMenu() end' % mod)]),

        ("%s: the frame's mouse release handler is gone" % tag, [
            (f, '    f:SetScript("OnMouseUp", function(_, button)\n'
                '        if button == "RightButton" then %s:_ContextMenu() end\n    end)\n' % mod, "")]),

        ("%s: any button opens the menu, so ending a left drag opens it too" % tag, [
            (f, '        if button == "RightButton" then %s:_ContextMenu() end' % mod,
                '        if button then %s:_ContextMenu() end' % mod)]),

        # Words a literal would leave in English on every other client.
        ("%s: the title is hard-coded in English" % tag, [
            (f, '        { kind = "title", text = L["%s"] },' % title,
                '        { kind = "title", text = "%s" },' % title)]),

        ("%s: Lock position is hard-coded in English" % tag, [
            (f, 'st.locked and L["Unlock (allow moving)"] or L["Lock position"]',
                'st.locked and L["Unlock (allow moving)"] or "Lock position"')]),

        ("%s: Unlock is hard-coded in English" % tag, [
            (f, 'st.locked and L["Unlock (allow moving)"] or L["Lock position"]',
                'st.locked and "Unlock (allow moving)" or L["Lock position"]')]),

        ("%s: Reset position is hard-coded in English" % tag, [
            (f, '        { text = L["Reset position"], onClick = function()',
                '        { text = "Reset position", onClick = function()')]),

        ("%s: Cancel is hard-coded in English" % tag, [
            (f, '        { text = L["Cancel"] },\n', '        { text = "Cancel" },\n')]),
    ]


MENU = "Libs/EverythingUI/Menu.lua"

MUTANTS = (menu_mutants("HUD", HUD, "HUD", "hudState", "Bonus Objectives", "DEFAULT_Y")
           + menu_mutants("zone bar", ZONE, "ZoneBar", "barState", "Zone Progress Bar", "220")
           # The fields the harness checks are read from the vendored library, so a change there is seen.
           + [("the library stops taking kind, which every title row carries", [
               (MENU, 'local ITEM_FIELDS = { kind = "string", text = "string", danger = "boolean", onClick = "function" }',
                'local ITEM_FIELDS = { text = "string", danger = "boolean", onClick = "function" }')])])

SUMMARY = re.compile(r"^test_chrome_menus: (\d+) passed, (\d+) failed$")


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
