"""Prove docs/test_sticky_headers.lua actually discriminates, by breaking production on purpose one
change at a time and checking the harness notices.

    python docs/mutate_sticky_headers.py        (run from the repo root)

Why this exists: the sticky headers live in four places that each fail silently. The hand-over
arithmetic picks which section the band shows, the band's two headers copy and place themselves on
every scroll step, ApplyWorldQuestsPosition puts the band into the list's anchor chain, and Render
gives the first header to the band and the band's height back to the list. A wrong sign or a
dropped line in any of them draws a header in the wrong place, or two, with every gate green.

Every mutation reintroduces a defect the harness is supposed to stand guard over. Any that still
reports "0 failed" is an assertion that does not discriminate, and the run exits 1 naming it.

Equivalent mutants left out on purpose: dropping the loop's "else break" (tops only ever rise, so
the scan stops at the same section either way) and widening "offset > top" to ">=" (the push at
equality is zero both ways).

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
HARNESS = "docs/test_sticky_headers.lua"

T = "UI/Tracker.lua"
V = "UI/Visibility.lua"
C = "UI/Commands.lua"
D = "Core/DB.lua"
S = "UI/Sections.lua"

MUTANTS = [
    # --------------------------------------------------------------------- stickyState
    ("a section takes the band as soon as its header reaches the top", [
        (T, "        if tops[i] + bandH <= offset then cur = i else break end",
            "        if tops[i] <= offset then cur = i else break end")]),

    ("the hand-over waits a pixel too long", [
        (T, "        if tops[i] + bandH <= offset then cur = i else break end",
            "        if tops[i] + bandH < offset then cur = i else break end")]),

    ("nothing is ever pushed", [
        (T, "    if cur < n and offset > tops[cur + 1] then push = offset - tops[cur + 1] end\n", "")]),

    ("the push is measured from the band's own section", [
        (T, "    if cur < n and offset > tops[cur + 1] then push = offset - tops[cur + 1] end\n",
            "    if cur < n and offset > tops[cur + 1] then push = offset - tops[cur] end\n")]),

    ("the last section is pushed by an entry past n", [
        (T, "    if cur < n and offset > tops[cur + 1] then", "    if tops[cur + 1] and offset > tops[cur + 1] then")]),

    # -------------------------------------------------------------- the band's two headers
    ("turned off, the band keeps showing its headers", [
        (T, "        for i = 1, #heads do heads[i]:Hide() end\n", "")]),

    ("without clipping a header is still pushed over what sits above", [
        (T, "    if not band.SetClipsChildren then push = 0 end\n", "")]),

    ("the incoming header sits above the band instead of below it", [
        (T, "band, push - bandH)", "band, bandH - push)")]),

    ("the incoming header stays up once the push ends", [
        (T, "    elseif heads[2] then\n        heads[2]:Hide()\n", "    elseif heads[2] then\n")]),

    ("a band header's click collapses whatever it showed first", [
        (T, "    h.groupID = groupID\n", "")]),

    ("a header made mid-scroll wears the stock font", [
        (T, "    if made then Sections:ApplyStyle(h) end\n", "")]),

    ("every scroll step restyles both headers", [
        (T, "    if made then Sections:ApplyStyle(h) end\n", "    Sections:ApplyStyle(h)\n")]),

    ("the band shows the section's title with no count", [
        (T, "        h.count:SetText(src.count:GetText())\n", "")]),

    ("the band shows the wrong collapse sign", [
        (T, "        h.collapse:SetText(src.collapse:GetText())\n", "")]),

    ("a band header is anchored on its left edge alone", [
        (T, "    h:SetPoint(\"TOPRIGHT\", band, \"TOPRIGHT\", 0, dy)\n", "")]),

    ("the status line never learns what the band shows", [
        (T, "    self._stickyShown, self._stickyPush = f._stickyIDs[cur], push\n", "")]),

    # -------------------------------------------------------------- the anchor chain
    ("the list hangs two pixels under the band, splitting a header that crosses the edge", [
        (T, "        scroll:SetPoint(\"TOPLEFT\", band, \"BOTTOMLEFT\", 0, 0)",
            "        scroll:SetPoint(\"TOPLEFT\", band, \"BOTTOMLEFT\", 0, -2)")]),

    ("the band loses the gap the list had under the container", [
        (T, "        band:SetPoint(\"TOPLEFT\",  above, \"BOTTOMLEFT\",  0, -2)",
            "        band:SetPoint(\"TOPLEFT\",  above, \"BOTTOMLEFT\",  0, 0)")]),

    ("with World Quests on top, the band sits under the container instead of the region", [
        (T, "        above = region\n", "")]),

    ("a change of chain never asks for a render", [
        (T, "        f._stickyAnchored = sticky\n        self:Refresh()\n",
            "        f._stickyAnchored = sticky\n")]),

    ("every anchoring pass asks for a render", [
        (T, "    if (f._stickyAnchored or false) ~= sticky then", "    if true then")]),

    ("a frame without a band is anchored to one anyway", [
        (T, "    local sticky = (band and cfg and cfg.stickySectionHeaders ~= false) and true or false",
            "    local sticky = (cfg and cfg.stickySectionHeaders ~= false) and true or false")]),

    ("an unset setting reads as off, against the shipped default", [
        (T, "    local sticky = (band and cfg and cfg.stickySectionHeaders ~= false) and true or false",
            "    local sticky = (band and cfg and cfg.stickySectionHeaders) and true or false")]),

    # -------------------------------------------------------------- the docked zone bar
    ("a zone bar section in the band still draws its header in the list", [
        (T, "    if inBand then\n        header:Hide()\n        added = 0\n    end\n",
            "    if inBand then\n        added = 0\n    end\n")]),

    ("a zone bar section in the band still spaces for its header", [
        (T, "    if inBand then\n        header:Hide()\n        added = 0\n    end\n",
            "    if inBand then\n        header:Hide()\n    end\n")]),

    ("a drawn zone bar section reports nothing drawn", [
        (T, "    return added, true\n", "    return added, false\n")]),

    # -------------------------------------------------------------- Render, by statement
    ("Render gives the SECOND section's header to the band", [
        (T, "                if sticky and stickyN == 1 then", "                if sticky and stickyN == 2 then")]),

    ("Render reads the live setting instead of the anchored chain", [
        (T, "    local sticky = f._stickyAnchored and f.stickyBand",
            "    local sticky = cfg and cfg.stickySectionHeaders and f.stickyBand")]),

    ("the list keeps the height the band took", [
        (T, "available - (wqH or 0) - bandH)", "available - (wqH or 0))")]),

    ("the band is sized in combat through a protected call", [
        (T, "            setRegionHeight(sticky, bandH)", "            sticky:SetHeight(bandH)")]),

    ("the band is a header tall with no gap under it", [
        (T, "        local row1 = Sections:Height() + gap\n", "        local row1 = Sections:Height()\n")]),

    # ------------------------------------------------- the zone row (zone headers, 2.2.0)
    ("the band never grows a zone row", [
        (T, "        local row2 = (stickyZ > 0) and (ZoneHeaders:Height() + gap) or 0\n", "        local row2 = 0\n")]),
    ("the band always keeps a zone row", [
        (T, "        local row2 = (stickyZ > 0) and (ZoneHeaders:Height() + gap) or 0\n",
            "        local row2 = ZoneHeaders:Height() + gap\n")]),
    ("the zone row never knows a zone was drawn", [
        (T, "f._stickyH, f._stickyRow1, f._stickyRow2, f._stickyZoned = bandH, row1, row2, stickyZ > 0",
            "f._stickyH, f._stickyRow1, f._stickyRow2, f._stickyZoned = bandH, row1, row2, false")]),
    ("the zone runs are never cleared between passes", [
        (T, "    wipe(zFirst)\n    wipe(zLast)\n", "")]),
    ("the zone row does not clip, so a pushed zone draws over the section header", [
        (T, "        if row.SetClipsChildren then row:SetClipsChildren(true) end\n", "")]),
    ("the zone row stays put while its section is pushed", [
        (T, '    row:SetPoint("TOPLEFT",  band, "TOPLEFT",  0, push - row1)\n'
            '    row:SetPoint("TOPRIGHT", band, "TOPRIGHT", 0, push - row1)\n',
            '    row:SetPoint("TOPLEFT",  band, "TOPLEFT",  0, -row1)\n'
            '    row:SetPoint("TOPRIGHT", band, "TOPRIGHT", 0, -row1)\n')]),
    ("the zone row is a section row tall", [
        (T, "    row:SetHeight(row2)\n", "    row:SetHeight(row1)\n")]),
    ("a zone takes the row as soon as its header reaches the top", [
        (T, "        if tops[i] + rowH <= offset then cur = i else break end", "        if tops[i] <= offset then cur = i else break end")]),
    ("a zone is pushed from its own top, not the next one's", [
        (T, "    if cur < last and offset > tops[cur + 1] then push = offset - tops[cur + 1] end\n",
            "    if cur < last and offset > tops[cur + 1] then push = offset - tops[cur] end\n")]),
    ("no zone is ever pushed", [
        (T, "    if cur < last and offset > tops[cur + 1] then push = offset - tops[cur + 1] end\n", "")]),
    ("a section's last zone is pushed by the next section's first", [
        (T, "    if cur < last and offset > tops[cur + 1] then", "    if offset > tops[cur + 1] then")]),
    ("a section's last zone is pushed by the next section's first, where there is one", [
        (T, "    if cur < last and offset > tops[cur + 1] then", "    if tops[cur + 1] and offset > tops[cur + 1] then")]),
    ("the zone row never comes back once hidden", [
        (T, "    row:SetHeight(row2)\n    row:Show()\n", "    row:SetHeight(row2)\n")]),
    ("a zone is pushed without clipping", [
        (T, "    if not (clip and row.SetClipsChildren) then zpush = 0 end\n", "")]),
    ("the incoming zone sits on the current one", [
        (T, "placeHead(b, row, zpush - row2)", "placeHead(b, row, zpush)")]),
    ("the next section's first zone never comes in", [
        (T, "    local nf = push > 0 and f._stickyZFirst[cur + 1]\n", "    local nf = false\n")]),
    ("the next section's first zone shows at rest", [
        (T, "    local nf = push > 0 and f._stickyZFirst[cur + 1]\n", "    local nf = f._stickyZFirst[cur + 1]\n")]),
    ("the next section's first zone ignores where the list has it", [
        (T, "placeHead(c, band, offset - tops[nf] - bandH)", "placeHead(c, band, push - bandH)")]),
    ("a zone that drew nothing still gets its slot shown", [
        (T, "    if not ZoneHeaders:Mirror(h, zoneKey) then return nil end\n", "    ZoneHeaders:Mirror(h, zoneKey)\n")]),
    ("a band zone copy is restyled every scroll step", [
        (T, "    if h._gen ~= ZoneHeaders.gen then\n", "    if true then\n")]),
    ("a band zone copy never records the render it was styled for", [
        (T, "        h._gen = ZoneHeaders.gen\n", "")]),
    ("a band zone copy is styled only when made, so a hidden one keeps an old look", [
        (T, "    if h._gen ~= ZoneHeaders.gen then\n", "    if h._gen == nil then\n")]),
    ("a band zone copy is styled before its text is in", [
        (T, "    if not ZoneHeaders:Mirror(h, zoneKey) then return nil end\n", ""),
        (T, "    return h\nend\n\nlocal function hideZoneHeads",
            "    if not ZoneHeaders:Mirror(h, zoneKey) then return nil end\n    return h\nend\n\nlocal function hideZoneHeads")]),
    ("with no zone drawn the copies stay up", [
        (T, "    if not f._stickyZoned then\n        hideZoneHeads(band)\n", "    if not f._stickyZoned then\n")]),
    ("with no zone drawn the status line keeps the last zone", [
        (T, "        self._stickyZone = nil\n        return\n", "        return\n")]),
    ("switching the band off leaves its zone copies up", [
        (T, "        for i = 1, #heads do heads[i]:Hide() end\n        hideZoneHeads(band)\n",
            "        for i = 1, #heads do heads[i]:Hide() end\n")]),
    ("hiding the zone copies leaves the row up", [
        (T, "    if band.zoneRow then band.zoneRow:Hide() end\n", "")]),
    ("a scroll step never updates the zone row", [
        (T, "    self:_UpdateStickyZones(band, cur, push, offset, band.SetClipsChildren ~= nil)\n", "")]),
    ("Render styles the shown zone copies itself again", [
        (T, "    for i = 1, (heads and #heads or 0) do Sections:ApplyStyle(heads[i]) end\n",
            "    for i = 1, (heads and #heads or 0) do Sections:ApplyStyle(heads[i]) end\n"
            "    for _, h in pairs(f.stickyBand and f.stickyBand.zoneHeads or {}) do\n"
            "        if h:IsShown() then ZoneHeaders:ApplyStyle(h, cfg) end\n"
            "    end\n")]),
    ("the band is built without its zone header list", [
        (T, "    stickyBand.zoneHeads = {}\n", "")]),
    ("the hover ignores the band's zone copies", [
        (V, "    if zoneHeads and (over(zoneHeads[1]) or over(zoneHeads[2]) or over(zoneHeads[3])) then return true end\n", "")]),
    ("the hover counts only the band's current zone", [
        (V, "(over(zoneHeads[1]) or over(zoneHeads[2]) or over(zoneHeads[3]))", "(over(zoneHeads[1]))")]),
    ("the status line never names the zone", [
        (T, 'f._stickyZoned and tostring(self._stickyZone) or "row off"', '"row off"')]),

    ("Render never updates the band", [
        (T, "    self:_UpdateSticky()\n", "")]),

    ("Render never styles the band's headers", [
        (T, "    for i = 1, (heads and #heads or 0) do Sections:ApplyStyle(heads[i]) end\n", "")]),

    ("a scroll step never updates the band", [
        (T, "    scroll:HookScript(\"OnVerticalScroll\", function() Tracker:_UpdateSticky() end)\n", "")]),

    ("the band never clips", [
        (T, "    if stickyBand.SetClipsChildren then stickyBand:SetClipsChildren(true) end\n", "")]),

    # -------------------------------------------------------------- around the tracker
    ("the opacity hover ignores the band", [
        (V, "    if heads and (over(heads[1]) or over(heads[2])) then return true end\n", "")]),

    ("the hover counts only the band's first header", [
        (V, "(over(heads[1]) or over(heads[2]))", "(over(heads[1]))")]),

    ("/eqot status drops the line", [
        (C, "    debugLine(\"Tracker\", nil, \"StickyLine\")\n", "")]),

    ("the option ships off", [
        (D, "            stickySectionHeaders = true,\n", "            stickySectionHeaders = false,\n")]),

    ("the band is built without its header list, so every render raises", [
        (T, "    stickyBand.heads = {}\n", "")]),

    ("the band hangs from UIParent, so it ignores the tracker's scale and hide", [
        (T, '    local stickyBand = CreateFrame("Frame", nil, f)\n',
            '    local stickyBand = CreateFrame("Frame", nil, UIParent)\n')]),

    ("a band header once hidden is never shown again", [
        (T, '    h:SetPoint("TOPRIGHT", band, "TOPRIGHT", 0, dy)\n    h:Show()\n',
            '    h:SetPoint("TOPRIGHT", band, "TOPRIGHT", 0, dy)\n')]),

    ("switching off mid-push hides only the band's first header", [
        (T, "        for i = 1, #heads do heads[i]:Hide() end", "        if heads[1] then heads[1]:Hide() end")]),

    ("the band header's click collapses the section it was made for", [
        (S, "Sections:ToggleCollapsed(self.groupID)", "Sections:ToggleCollapsed(groupID)")]),

    ("a header click goes through a click-through tracker", [
        (S, "        if Tracker and Tracker.IsClickThrough and Tracker:IsClickThrough() then return end\n", "")]),

    ("the header asks the click-through check without the tracker, which raises in game", [
        (S, "Tracker:IsClickThrough() then return end", "Tracker.IsClickThrough() then return end")]),

    ("the header takes right clicks instead of left", [
        (S, 'h:RegisterForClicks("LeftButtonUp")', 'h:RegisterForClicks("RightButtonUp")')]),

    ("an expanded section is never scrolled into view", [
        (S, "if not collapsed and Tracker.ScrollSectionIntoView then", "if collapsed and Tracker.ScrollSectionIntoView then")]),

    ("the band is hidden as soon as it is stored, so no header ever shows", [
        (T, "    f.stickyBand = stickyBand\n", "    f.stickyBand = stickyBand\n    stickyBand:Hide()\n")]),

    ("a missing zone bar module reads as a drawn section", [
        (T, "    if not ZoneBar then return 0, false end", "    if not ZoneBar then return 0, true end")]),

    # ------------------------------------------------- the second scan's hand-breaks (zone row)
    # Each survived the harness green until the rig read the profile through Core/DB.lua's own
    # DB:Tracker, recorded the settings each copy was styled with, and ran Render's zone arrays block.
    ("a band zone copy is styled with no settings, which raises in game", [
        (T, "        ZoneHeaders:ApplyStyle(h, ns:GetModule(\"DB\"):Tracker())\n", "        ZoneHeaders:ApplyStyle(h)\n")]),

    ("a band zone copy reads the profile with a dot call, which raises in game", [
        (T, "        ZoneHeaders:ApplyStyle(h, ns:GetModule(\"DB\"):Tracker())\n",
            "        ZoneHeaders:ApplyStyle(h, ns:GetModule(\"DB\").Tracker())\n")]),

    ("a band zone copy is styled from empty settings, so it wears the default look", [
        (T, "        ZoneHeaders:ApplyStyle(h, ns:GetModule(\"DB\"):Tracker())\n", "        ZoneHeaders:ApplyStyle(h, {})\n")]),

    ("Render never keeps the band's zone arrays on the frame", [
        (T, "        f._stickyZKeys, f._stickyZTops, f._stickyZFirst, f._stickyZLast = zKeys, zTops, zFirst, zLast\n", "")]),

    ("the band's zone tops and section firsts are kept crosswise on the frame", [
        (T, "        f._stickyZKeys, f._stickyZTops, f._stickyZFirst, f._stickyZLast = zKeys, zTops, zFirst, zLast\n",
            "        f._stickyZKeys, f._stickyZTops, f._stickyZFirst, f._stickyZLast = zKeys, zFirst, zTops, zLast\n")]),

    ("a first zone below the band raises before it reaches the row", [
        (T, "    if not cur then return nil, 0 end\n", "")]),

    ("the next section's first zone comes in without the range check, so a leftover key shows", [
        (T, "    local c = nf and nf <= (f._stickyZLast[cur + 1] or 0) and stickyZoneHead(band, 3, band, keys[nf])\n",
            "    local c = nf and stickyZoneHead(band, 3, band, keys[nf])\n")]),
]

SUMMARY = re.compile(r"^test_sticky_headers: (\d+) passed, (\d+) failed$")


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
