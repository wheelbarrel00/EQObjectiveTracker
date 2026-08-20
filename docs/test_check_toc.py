#!/usr/bin/env python3
"""Prove check_toc.py fires on each drift shape, and prove it stays quiet on a good tree.

A gate needs a test that it does NOT fire as well as one that it does: the locale format
check in this repo was wrong in both directions before it was right, and both errors were
caught by crafted cases rather than by reading it.

The "stays quiet" cases are the load-bearing half here. A flavor TOC is legitimately a
different file list - it omits providers that flavor cannot run, and it lists
Data/Providers/QuestsClassic.lua, which no retail TOC has. An earlier draft of the gate
would have rejected both. Those two cases are what stop that rule coming back.

Builds throwaway trees under a temp directory, so it never touches the real checkout.
No pytest dependency - every other gate here is a plain script and this matches them.
"""
import copy
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_toc  # noqa: E402

MAINLINE = check_toc.REFERENCE_TOC
FALLBACK = check_toc.FALLBACK_TOC
VANILLA = "EQObjectiveTracker_Vanilla.toc"

HEADER = (
    "## Interface: {interface}\n"
    "## Title: EQ Objective Tracker\n"
    "## Version: {version}\n"
    "## X-Curse-Project-ID: {project}\n"
)

# Locales/enUS.lua stands for every shared file. It is here rather than only Core/Init.lua
# because a LANGUAGE is what the flavor-blind version of this gate let through: dropping a
# locale from a flavor TOC exited 0, and Era and TBC players would have got an all-English
# tracker off a green CI run.
SHARED = ["Core/Init.lua", "Locales/enUS.lua"]

RETAIL_FILES = SHARED + [
    "Data/Providers/Quests.lua",
    "Data/Providers/WorldQuests.lua",
]
CLASSIC_FILES = SHARED + ["Data/Providers/QuestsClassic.lua"]

# Every authored lua the good tree has on disk. QuestsClassic.lua is here on purpose: it
# is listed by the flavor TOC only, which is the shape the real repo has.
LUAS = RETAIL_FILES + ["Data/Providers/QuestsClassic.lua"]

RETAIL_HEAD = {"interface": "120100, 120007, 120005", "version": "1.4.2", "project": "1637002"}

GOOD = {
    MAINLINE: dict(RETAIL_HEAD, files=list(RETAIL_FILES)),
    FALLBACK: dict(RETAIL_HEAD, files=list(RETAIL_FILES)),
    VANILLA: {
        "interface": "11509",
        "version": "1.4.2",
        "project": "1637002",
        "files": list(CLASSIC_FILES),
    },
}


def run(tocs, luas):
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        for d in check_toc.SOURCE_DIRS:
            (root / d).mkdir(parents=True, exist_ok=True)
        for rel in luas:
            p = root / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text("-- test\n", encoding="utf-8")
        for name, spec in tocs.items():
            body = HEADER.format(
                interface=spec["interface"],
                version=spec["version"],
                project=spec["project"],
            )
            body += "\n"
            body += "".join(f.replace("/", "\\") + "\n" for f in spec["files"])
            (root / name).write_text(body, encoding="utf-8")
        return check_toc.main(root)


CASES = []


def case(name, expected, tocs, luas):
    CASES.append((name, expected, tocs, luas))


def _with(**edits):
    tocs = copy.deepcopy(GOOD)
    for toc_name, changes in edits.items():
        tocs[toc_name].update(changes)
    return tocs


# --- must stay quiet -------------------------------------------------------------------

case("a clean tree passes", 0, copy.deepcopy(GOOD), list(LUAS))

# The two shapes a flavor TOC is allowed to have. Both would fail under a rule that made
# every TOC a subset of the reference one, which is why they are named cases and not just
# a property of the fixture above.
case(
    "a flavor TOC may omit a provider the retail TOCs list",
    0,
    _with(**{VANILLA: {"files": list(SHARED)}}),
    [f for f in LUAS if f != "Data/Providers/QuestsClassic.lua"],
)

case(
    "a file listed by the flavor TOC alone passes",
    0,
    copy.deepcopy(GOOD),
    list(LUAS),
)

# --- must fire -------------------------------------------------------------------------

# Keeps QuestsClassic.lua listed, or dropping it would also trip the "no TOC lists it"
# rule and the case would pass for two reasons instead of isolating this one.
case(
    "a TOC referencing a file that is not on disk fails",
    1,
    _with(**{VANILLA: {"files": CLASSIC_FILES + ["UI/NotThere.lua"]}}),
    list(LUAS),
)

case(
    "a mismatched ## Version: fails",
    1,
    _with(**{VANILLA: {"version": "1.4.1"}}),
    list(LUAS),
)

case(
    "a mismatched ## X-Curse-Project-ID: fails",
    1,
    _with(**{VANILLA: {"project": "9999999"}}),
    list(LUAS),
)

case(
    "an authored lua no TOC lists fails",
    1,
    copy.deepcopy(GOOD),
    LUAS + ["UI/Orphan.lua"],
)

# The retail pair must stay in step in both directions. This is the drift the gate was
# rewritten for: the two files were byte-identical, so nothing had ever caught a one-sided
# edit, and Task 7 is the moment they stop being identical.
case(
    "the fallback TOC listing a file the reference does not fails",
    1,
    _with(**{FALLBACK: {"files": RETAIL_FILES + ["Data/Providers/QuestsClassic.lua"]}}),
    list(LUAS),
)

case(
    "the reference TOC listing a file the fallback does not fails",
    1,
    _with(**{FALLBACK: {"files": list(SHARED)}}),
    list(LUAS),
)

# --- check 3: the flavor blindness this gate shipped with ------------------------------
# All three exited 0 before FLAVOR_ONLY existed. Check 2 only asks whether SOME TOC lists a
# file and check 4 only compares the two retail files, so nothing looked at a flavor TOC.

case(
    "a locale missing from a flavor TOC fails",
    1,
    _with(**{VANILLA: {"files": [f for f in CLASSIC_FILES if f != "Locales/enUS.lua"]}}),
    list(LUAS),
)

case(
    "a shared file missing from a flavor TOC fails",
    1,
    _with(**{VANILLA: {"files": [f for f in CLASSIC_FILES if f != "Core/Init.lua"]}}),
    list(LUAS),
)

case(
    "a shared file missing from a retail TOC fails",
    1,
    _with(**{MAINLINE: {"files": [f for f in RETAIL_FILES if f != "Locales/enUS.lua"]}}),
    list(LUAS),
)

# Keeps the exemption list honest. One that every TOC lists anyway hides that file from
# check 3 for nothing, so it has to be noticed rather than left to rot.
case(
    "a flavor-only file listed by every TOC fails",
    1,
    _with(
        **{
            MAINLINE: {"files": RETAIL_FILES + ["Data/Providers/QuestsClassic.lua"]},
            FALLBACK: {"files": RETAIL_FILES + ["Data/Providers/QuestsClassic.lua"]},
        }
    ),
    list(LUAS),
)

case("a tree with no TOC at all fails", 1, {}, list(LUAS))

case(
    "a tree with no reference TOC fails",
    1,
    {VANILLA: copy.deepcopy(GOOD[VANILLA])},
    list(LUAS),
)


def main():
    failures = []
    for name, expected, tocs, luas in CASES:
        print(f"--- {name}")
        got = run(tocs, luas)
        if got != expected:
            print(f"FAIL: expected exit {expected}, got {got}")
            failures.append(name)
        else:
            print(f"ok: exit {got}")
    print()
    if failures:
        for name in failures:
            print(f"FAILED: {name}")
        print(f"{len(failures)} of {len(CASES)} case(s) failed")
        return 1
    print(f"all {len(CASES)} cases passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
