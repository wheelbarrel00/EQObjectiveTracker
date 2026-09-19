#!/usr/bin/env python3
"""Guard against TOC drift.

Separate per-flavor TOC files are what let a git checkout run in-game with no build
step, but they cost one file list per flavor to keep in sync. This checks six things:

  1. every path referenced by any TOC exists on disk
  2. every authored .lua under SOURCE_DIRS is referenced by at least one TOC, so adding
     UI/Foo.lua and forgetting to list it is caught
  3. every file EXCEPT the FLAVOR_ONLY exemptions is listed by every TOC
  4. each mirror TOC exists and matches the reference TOC line for line: the same files in
     the same order, and the same headers apart from '## Interface:'
  5. '## Version:' and '## X-Curse-Project-ID:' agree across every TOC
  6. every suffixed TOC declares '## Interface:', and every number in it belongs to the
     game type its suffix names

Check 3 is the one that was missing, and it was missing in the worst possible direction:
checks 2 and 4 between them let a shared file be dropped from a flavor TOC and still exit
0, because check 2 only asked whether SOME TOC lists it and check 4 only compared the two
retail files. Proven by mutation: deleting Locales/zhCN.lua from _TBC.toc, and separately
from _Vanilla.toc, passed. A LANGUAGE is as exposed as a flavor file that way - Era and
TBC players would have got an all-English tracker off a green CI run.

Check 2 is deliberately "at least one TOC" rather than "the reference TOC". A flavor
file such as Data/Providers/QuestsClassic.lua is legitimately absent from the retail
TOCs, and a rule anchored on the reference TOC would reject it.

Check 4 has held WoW Forever's _Camelot.toc since 2026-09-17: Forever runs the retail file
list, and check 3 cannot see a retail provider dropped from it, because every retail
provider is a FLAVOR_ONLY exemption. Forever build 69913 loads _Mainline.toc over it, so
today its only effect is the Forever game version on the CurseForge upload. A missing
mirror is an error rather than a skip, because the packager ignores an untracked file and
a commit that forgot it would ship a zip CurseForge does not offer for Forever, with CI
green.

Check 5 exists because the packager reads both out of the TOC, so a one-sided edit ships
a zip whose halves disagree. Before the flavor TOCs landed the retail two were
byte-identical, which is the only reason nothing had ever caught it.

Check 6 is the packager's own rule, copied from its release.sh at the @v2 ref: it exits 1
on a suffixed TOC whose interface numbers are not all of the suffix's game type, which
fails a release AFTER its tag is pushed. An '11509, 16001' line in a _Vanilla.toc is
exactly that shape. It reads the line the packager's way too, because a looser read passed
'##Interface:', a second Interface line and '16001 16002', each of which the packager
rejects.

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
CAMELOT_TOC = "EQObjectiveTracker_Camelot.toc"
MIRRORS = (FALLBACK_TOC, CAMELOT_TOC)
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
    "Data/Providers/Initiative.lua",
    "Data/Providers/Professions.lua",
    "Data/Providers/Quests.lua",
    "Data/Providers/QuestsClassic.lua",
    "Data/Providers/Scenarios.lua",
    "Data/Providers/WorldQuests.lua",
})

# The packager's game_flavor table and toc_to_file_type patterns, in its own order.
SUFFIX_GAME_TYPE = {
    "Mainline": "retail", "Vanilla": "classic", "BCC": "bcc", "TBC": "bcc",
    "Wrath": "wrath", "WOTLKC": "wrath", "Cata": "cata", "Mists": "mists",
    "Camelot": "forever",
}
INTERFACE_GAME_TYPE = (
    ("11", "classic"), ("16", "forever"), ("20", "bcc"), ("30", "wrath"),
    ("40", "cata"), ("50", "mists"), ("380", "wrath"),
)
_SUFFIX = re.compile(r"^EQObjectiveTracker[-_](Classic|" + "|".join(SUFFIX_GAME_TYPE) + r")\.toc$")

_HEADER = re.compile(r"^##\s*([^:]+):\s*(.*?)\s*$")


def game_type(interface):
    if len(interface) == 5:
        for prefix, kind in INTERFACE_GAME_TYPE:
            if interface.startswith(prefix):
                return kind
    return "retail"


def packager_interface(toc: Path):
    """The packager's awk: the first '## Interface:' line, the text up to any further colon,
    spaces and tabs removed, split on commas, a trailing empty value dropped."""
    for line in toc.read_text(encoding="utf-8-sig").splitlines():
        if line.startswith("## Interface:"):
            values = re.sub(r"[ \t]", "", line.split(":")[1]).split(",")
            return values[:-1] if values[-1] == "" else values
    return []


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

    for name in sorted(parsed):
        m = _SUFFIX.match(name)
        if not m:
            continue
        values = packager_interface(root / name)
        declared = ", ".join(values)
        if not values:
            problems.append(f"{name}: declares no ## Interface:, which the packager rejects")
            continue
        kinds = {game_type(v) for v in values}
        suffix = m.group(1)
        if suffix == "Classic":
            if "retail" in kinds:
                problems.append(f"{name}: ## Interface: {declared} includes a retail number, "
                                "which the packager rejects for a Classic TOC")
        elif kinds != {SUFFIX_GAME_TYPE[suffix]}:
            problems.append(f"{name}: ## Interface: {declared} is not all "
                            f"{SUFFIX_GAME_TYPE[suffix]}, which the packager rejects")

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

        # TOCs outside MIRRORS are exempt by design - that is the whole point of having them.
        ref_files, ref_headers = parsed[REFERENCE_TOC]
        listed = set(ref_files)
        for mirror in MIRRORS:
            if mirror not in parsed:
                problems.append(f"missing {mirror}, which must mirror {REFERENCE_TOC}")
                continue
            files, headers = parsed[mirror]
            for rel in files:
                if rel not in listed:
                    problems.append(
                        f"{mirror}: lists {rel}, which {REFERENCE_TOC} does not")
            for rel in ref_files:
                if rel not in set(files):
                    problems.append(
                        f"{REFERENCE_TOC}: lists {rel}, which {mirror} does not")
            if set(files) == listed and files != ref_files:
                problems.append(
                    f"{mirror}: lists {REFERENCE_TOC}'s files in another order or twice")
            for key in sorted((set(headers) | set(ref_headers)) - {"Interface"}):
                if headers.get(key) != ref_headers.get(key):
                    problems.append(
                        f"{mirror}: ## {key}: {headers.get(key)!r} differs from "
                        f"{REFERENCE_TOC}'s {ref_headers.get(key)!r}")

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
