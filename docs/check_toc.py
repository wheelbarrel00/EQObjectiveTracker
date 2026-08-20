#!/usr/bin/env python3
"""Guard against TOC drift.

Separate per-flavor TOC files are what let a git checkout run in-game with no build
step, but they cost one file list per flavor to keep in sync. This checks five things:

  1. every path referenced by any TOC exists on disk
  2. every authored .lua under SOURCE_DIRS is referenced by at least one TOC, so adding
     UI/Foo.lua and forgetting to list it is caught
  3. every file EXCEPT the FLAVOR_ONLY exemptions is listed by every TOC
  4. the two retail TOCs list exactly the same files, checked in both directions, so they
     cannot drift apart
  5. '## Version:' and '## X-Curse-Project-ID:' agree across every TOC

Check 3 is the one that was missing, and it was missing in the worst possible direction:
checks 2 and 4 between them let a shared file be dropped from a flavor TOC and still exit
0, because check 2 only asks whether SOME TOC lists it and check 4 only compares the two
retail files. Proven by mutation: deleting Locales/zhCN.lua from _TBC.toc, and separately
from _Vanilla.toc, passed. A LANGUAGE is as exposed as a flavor file that way - Era and
TBC players would have got an all-English tracker off a green CI run.

Check 2 is deliberately "at least one TOC" rather than "the reference TOC". A flavor
file such as Data/Providers/QuestsClassic.lua is legitimately absent from the retail
TOCs, and a rule anchored on the reference TOC would reject it.

Check 4 exists because the packager reads both out of the TOC, so a one-sided edit ships
a zip whose halves disagree. Before the flavor TOCs landed the retail two were
byte-identical, which is the only reason nothing had ever caught it.

Run locally or in CI. Exits non-zero on any problem. docs/test_check_toc.py proves it
fires on each of these shapes and stays quiet on a good tree.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIRS = ("Locales", "Core", "Data", "UI", "Options")
REFERENCE_TOC = "EQObjectiveTracker_Mainline.toc"
FALLBACK_TOC = "EQObjectiveTracker.toc"
SHARED_HEADERS = ("Version", "X-Curse-Project-ID")

# The only files a TOC may legitimately omit: providers a flavor cannot run, and the three
# non-provider modules that are Classic-only. Everything else - all of Core, all of UI, every
# locale - must be in every TOC. An exemption is a deliberate edit, which is the point: the
# cost of adding a line here is what stops a shared file going missing by accident.
FLAVOR_ONLY = frozenset({
    "Data/Focus.lua",
    "Data/TrackedSet.lua",
    "UI/QuestLogChecks.lua",
    "Data/Providers/Achievements.lua",
    "Data/Providers/Endeavors.lua",
    "Data/Providers/Professions.lua",
    "Data/Providers/Quests.lua",
    "Data/Providers/QuestsClassic.lua",
    "Data/Providers/Scenarios.lua",
    "Data/Providers/WorldQuests.lua",
})

_HEADER = re.compile(r"^##\s*([^:]+):\s*(.*?)\s*$")


def parse_toc(toc: Path):
    files, headers = [], {}
    for raw in toc.read_text(encoding="utf-8-sig").splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("##"):
            m = _HEADER.match(line)
            if m:
                headers[m.group(1).strip()] = m.group(2)
            continue
        if line.startswith("#"):
            continue
        files.append(line.replace("\\", "/"))
    return files, headers


def main(root: Path = ROOT) -> int:
    root = Path(root)
    tocs = sorted(root.glob("*.toc"))
    if not tocs:
        print("error: no .toc files found at repo root")
        return 1

    problems = []
    parsed = {}

    for toc in tocs:
        parsed[toc.name] = parse_toc(toc)
        for rel in parsed[toc.name][0]:
            if not (root / rel).is_file():
                problems.append(f"{toc.name}: references missing file {rel}")

    for field in SHARED_HEADERS:
        seen = {}
        for name in sorted(parsed):
            seen.setdefault(parsed[name][1].get(field), []).append(name)
        if len(seen) > 1:
            detail = "; ".join(
                f"{value!r} in {', '.join(names)}"
                for value, names in sorted(seen.items(), key=lambda kv: str(kv[0]))
            )
            problems.append(f"## {field}: disagrees across TOCs - {detail}")

    if REFERENCE_TOC not in parsed:
        problems.append(f"missing reference TOC {REFERENCE_TOC}")
    else:
        anywhere = set()
        for name in parsed:
            anywhere.update(parsed[name][0])
        for d in SOURCE_DIRS:
            src = root / d
            if not src.is_dir():
                continue
            for lua in sorted(src.rglob("*.lua")):
                rel = lua.relative_to(root).as_posix()
                if rel not in anywhere:
                    problems.append(f"no TOC lists {rel}")

        # Everything that is not explicitly flavor-specific belongs in every TOC.
        universal = anywhere - FLAVOR_ONLY
        for name in sorted(parsed):
            listed = set(parsed[name][0])
            for rel in sorted(universal - listed):
                problems.append(f"{name}: does not list {rel}, which is not flavor-specific")

        # Keeps the exemption list honest: one that every TOC lists anyway is doing nothing
        # but hiding that file from check 3 if it is ever dropped.
        if len(parsed) > 1:
            in_every = set.intersection(*(set(parsed[n][0]) for n in parsed))
            for rel in sorted(FLAVOR_ONLY & in_every):
                problems.append(f"{rel}: listed by every TOC, so remove it from FLAVOR_ONLY")

        # The retail pair must stay in step with each other. Flavor TOCs are exempt by
        # design - that is the whole point of having them.
        listed = set(parsed[REFERENCE_TOC][0])
        if FALLBACK_TOC in parsed:
            for rel in parsed[FALLBACK_TOC][0]:
                if rel not in listed:
                    problems.append(
                        f"{FALLBACK_TOC}: lists {rel}, which {REFERENCE_TOC} does not")
            for rel in listed:
                if rel not in set(parsed[FALLBACK_TOC][0]):
                    problems.append(
                        f"{REFERENCE_TOC}: lists {rel}, which {FALLBACK_TOC} does not")

    if problems:
        for p in problems:
            print(f"error: {p}")
        return 1

    counts = ", ".join(
        f"{name}={len(parsed[name][0])}" for name in sorted(parsed))
    print(f"TOC check passed ({counts})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
