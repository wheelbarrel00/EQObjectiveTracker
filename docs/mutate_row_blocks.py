"""Prove docs/test_row_blocks.lua actually discriminates, by breaking UI/Row.lua's block builder
on purpose one change at a time and checking the harness notices.

    python docs/mutate_row_blocks.py            (run from the repo root)

Why this exists: docs/mutate_quest_progress.py mutates UI/Row.lua too, but only the BAR half of
it - the half the progress bar feature added. Everything else in buildBlocks had no battery, and
an adversarial pass found five mutants surviving on a green 33-assertion file, all of them in
simplify mode: nothing in that harness ever set a simplify flag, so hideDone was false on every
case and the branch loaded without ever running. One of the five INVERTED the filter, so simplify
would have hidden every unfinished objective and shown only the completed ones.

Every mutation reintroduces a defect the harness is supposed to stand guard over. Any that still
reports "0 failed" is an assertion that does not discriminate, and the run exits 1 naming it -
unless the entry is marked EQUIVALENT, which means the mutation provably cannot change behavior
and so nothing could catch it. There is ONE of those and it is worth reading:

  - flushText returns at its first line when the text run is empty, so clearing _bPct there is
    unreachable for a block index that never gets written. The clear that matters is the one in
    the bar branch, and that mutant is caught.

A CRASHED verdict is reported apart from "caught" on purpose. A mutant that does not parse also
exits nonzero, and counting that as caught is a false pass in the one tool whose job is to find
false passes.

WRITES TO THE TREE. It edits UI/Row.lua in place and restores it after every mutant through a
finally, then verifies the restore and re-checks the baseline before reporting. If you hard-kill
it, recover from your editor's undo history.

Anchors are exact source text and they rot. A SKIPPED line means an anchor stopped matching: fix
the anchor rather than dropping the mutant.
"""
import io
import re
import subprocess
import sys

LUA = r"C:\Users\Big Daddy\Documents\Tools\lua-5.1.5\lua5.1.exe"
SRC = "UI/Row.lua"
HARNESS = "docs/test_row_blocks.lua"
SUMMARY = re.compile(r"^test_row_blocks: (\d+) passed, (\d+) failed$")

HIDEDONE = "    local hideDone = simple or (groups and entry.groupID and groups[entry.groupID]) or false"

MUTANTS = [
    # ------------------------------------------------------------------ simplify mode
    ("simplify stops hiding anything at all",
     HIDEDONE,
     "    local hideDone = false"),

    ("the per-group switch is dropped, so simplifyGroups can never fire",
     HIDEDONE,
     "    local hideDone = simple or false"),

    ("the per-group switch stops reading the entry's own group, so it fires for every section",
     HIDEDONE,
     "    local hideDone = simple or (groups and next(groups) ~= nil) or false"),

    ("the filter is INVERTED, so simplify hides the unfinished objectives and keeps the done ones",
     "        if not (hideDone and ln.completed) then",
     "        if not (hideDone and not ln.completed) then"),

    ("simplify stops stopping at the first line, so it draws the whole run",
     "            if simple then break end",
     "            if false then break end"),

    ("the break is unconditional, so every entry draws one objective",
     "            if simple then break end",
     "            break"),

    # ------------------------------------------------------------------ the all-finished fallback
    ("the all-finished fallback goes, so a finished entry draws a bare title",
     "    if _nBlocks == 0 and hideDone and #lines > 0 then",
     "    if false then"),

    # EQUIVALENT. With hideDone false nothing is skipped, so a run with any line at all leaves
    # _nBlocks >= 1 - a bar increments it directly and text reaches it through flushText. The
    # `_nBlocks == 0 and #lines > 0` pair is therefore already unreachable without hideDone.
    ("EQUIVALENT: the fallback drops the hideDone half of a condition that cannot be met without it",
     "    if _nBlocks == 0 and hideDone and #lines > 0 then",
     "    if _nBlocks == 0 and #lines > 0 then"),

    ("the fallback shows the FIRST line rather than the last one reached",
     "        local last = lines[#lines]",
     "        local last = lines[1]"),

    # ------------------------------------------------------------------ the text path
    ("a completed line loses its checkmark",
     '                        text = "|A:common-icon-checkmark:12:12|a |cff" .. hex .. text .. "|r"',
     '                        text = "|cff" .. hex .. text .. "|r"'),

    ("a NOTE stops being dimmed and reads as an ordinary objective",
     '                    elseif ln.kind == LINE.NOTE then\n'
     '                        text = "|cff999999- " .. text .. "|r"',
     "                    elseif false then"),

    ("the objective-numbers option stops stripping the leading count",
     "                    if hideN then text = Util.StripLeadingCount(text) end",
     "                    -- left in place"),

    ("a finished meter draws its numbers again, where the default tracker shows the label alone",
     "                        if not ln.completed then",
     "                        if true then"),

    # ------------------------------------------------------------------ the bar branch
    ("the bar label keeps the meter Blizzard already put in it, printing the numbers twice",
     '                _bText[_nBlocks] = Util.StripLeadingCount(ln.text or "")',
     '                _bText[_nBlocks] = ln.text or ""'),

    ("a supplied percentage stops flagging the block, so it draws against its own denominator",
     "                _bPct[_nBlocks]  = (ln.kind == LINE.WEIGHTED or ln.percent ~= nil) or nil",
     "                _bPct[_nBlocks]  = (ln.kind == LINE.WEIGHTED) or nil"),

    # EQUIVALENT, and it is worth knowing WHY rather than assuming the zero trap applies here.
    # Lua has only nil and false as falsy values, so `ln.percent` of 0 is truthy and the flag
    # still lands. It stores 0 rather than true, and both consumers - the `if _bPct[i]` branch
    # and blocksKey's `_bPct[i] and " pct"` - are truthiness tests. Nothing compares it to true.
    ("EQUIVALENT: the percentage flag is keyed on truthiness rather than on being non-nil",
     "                _bPct[_nBlocks]  = (ln.kind == LINE.WEIGHTED or ln.percent ~= nil) or nil",
     "                _bPct[_nBlocks]  = (ln.kind == LINE.WEIGHTED or ln.percent) or nil"),

    ("the stale percentage flag survives onto the next count block that reuses the index",
     "                _bPct[_nBlocks]  = (ln.kind == LINE.WEIGHTED or ln.percent ~= nil) or nil",
     "                if ln.kind == LINE.WEIGHTED or ln.percent ~= nil then\n"
     "                    _bPct[_nBlocks] = true\n"
     "                end"),

    # ------------------------------------------------------------------ the repaint key
    ("the key drops the fill, so a bar whose percentage moved never repaints",
     '            _keyBuf[i] = ("%d bar%s %s %s/%s"):format(\n'
     '                i, _bPct[i] and " pct" or "", _bText[i], _bCur[i], _bReq[i])',
     '            _keyBuf[i] = ("%d bar%s %s"):format(\n'
     '                i, _bPct[i] and " pct" or "", _bText[i])'),

    ("the key stops being bounded by the run length, so a shorter run inherits a longer tail",
     '    return table.concat(_keyBuf, "\\n", 1, _nBlocks)',
     '    return table.concat(_keyBuf, "\\n")'),

    # EQUIVALENT. flushText returns at its first line when _nText is 0, so the _bPct clear there
    # is only ever reached for an index it is also about to write. The clear that does the work
    # is the one in the bar branch, and that mutant is the one above.
    ("EQUIVALENT: flushText stops clearing the percentage flag it is about to overwrite",
     "    _bPct[_nBlocks]  = nil\n    _bText[_nBlocks] = table.concat",
     "    _bText[_nBlocks] = table.concat"),
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
        print("CRASHED   %-80s %s" % (name, last))
        survivors.append(name)
    elif verdict == "green" and not equivalent:
        print("SURVIVED  %-80s %s" % (name, last))
        survivors.append(name)
    elif verdict == "failed" and equivalent:
        print("UNEXPECTED %-79s %s" % (name + " (was caught)", last))
        survivors.append(name)
    elif equivalent:
        print("survived  %-80s as expected, it cannot change behavior" % name)
    else:
        print("caught    %-80s %s" % (name, last))

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
