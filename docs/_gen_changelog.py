# Regenerate Core/Changelog.lua from CHANGELOG.md.
#
# The About tab renders ns.Changelog, so the in-game history is a pure function of
# CHANGELOG.md and the two can never drift. Run this as part of the release sequence,
# right after CHANGELOG.md gains its new version heading:
#
#   python docs/_gen_changelog.py            # rewrite Core/Changelog.lua
#   python docs/_gen_changelog.py --check    # gate: exit 1 if it is stale
#
# --check regenerates in memory and diffs. It runs in CI, because the release sequence
# asking a human to remember a step is not a gate: a skipped regenerate ships an About
# tab whose newest entry is the PREVIOUS version, and luacheck, check_toc.py and
# _verify_locale.py are all blind to stale content in a file that parses fine.
#
# The [Unreleased] heading is skipped (no version, no date), as is 0.1.0, which was a
# milestone that never shipped. Backticks are stripped - `/eqot status` renders as a
# literal backtick in a FontString. The output is asserted ASCII, because the release
# gate greps every authored .lua for a non-ASCII byte.
#
# Every parse path that cannot represent its input FAILS rather than dropping it. Silent
# truncation here is invisible: the file still parses, the tab still renders, and the only
# symptom is a missing paragraph nobody is looking for.
import io
import re
import sys

SRC = 'CHANGELOG.md'
DST = 'Core/Changelog.lua'
SKIP_VERSIONS = {'0.1.0'}

# The About tab builds every line it shows in one script on its first click. With all 61
# versions that read 313 ms on Classic Era (2026-11-01), and the client had ended the same
# click with "script ran too long". The tab's CurseForge button covers what this leaves out.
MAX_VERSIONS = 30

# The prerelease suffix is deliberate: a tag such as v1.4.0-beta1 is how a risky release
# ships to the beta channel, so a matching heading is a live case. Without it the whole
# version silently vanished from the in-game changelog.
VERSION_RE = re.compile(r'^## \[(\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?)\] - (\d{4}-\d{2}-\d{2})\s*$')
ANY_VERSION_RE = re.compile(r'^## \[(?!Unreleased\])')

HEADER = '''local _, ns = ...

-- The About tab renders this verbatim. Deliberately NOT wrapped in L[...]: the body is
-- long-form English prose no translator is going to be offered, and a translated heading
-- over an English paragraph reads worse than leaving the whole block alone. EQ does the
-- same in its own Core/Changelog.lua.
--
-- GENERATED FILE: produced by docs/_gen_changelog.py from CHANGELOG.md. Do not hand-edit -
-- edit CHANGELOG.md and re-run the generator.
ns.Changelog = {'''


def fail(lineno, line, why):
    sys.exit('%s:%d: %s\n  %r\n'
             '  Fix the heading or bullet in CHANGELOG.md, then re-run the generator.'
             % (SRC, lineno, why, line))


def parse(lines):
    entries, cur, sec, buf, summary = [], None, None, None, []

    def flush_item():
        if buf and sec is not None:
            text = ' '.join(p.strip() for p in buf).strip().replace('`', '')
            if text:
                sec['items'].append(text)

    def flush_summary():
        if cur is not None and summary:
            text = ' '.join(p.strip() for p in summary).strip().replace('`', '')
            if text:
                cur['summary'] = text

    for lineno, raw in enumerate(lines, 1):
        line = raw.rstrip()
        m = VERSION_RE.match(line)
        if m:
            flush_item(); flush_summary()
            buf, sec, summary = None, None, []
            cur = {'version': m.group(1), 'date': m.group(2), 'sections': [], 'summary': None}
            entries.append(cur)
            continue
        if line.startswith('## '):
            # A version-shaped heading the regex could not read would otherwise be dropped
            # whole, exit 0, with the release looking clean.
            if ANY_VERSION_RE.match(line):
                fail(lineno, line, 'version heading does not match "## [N.N.N] - YYYY-MM-DD"')
            flush_item(); flush_summary()
            buf, cur, sec, summary = None, None, None, []
            continue
        if cur is None:
            continue
        m = re.match(r'^### (.+?)\s*$', line)
        if m:
            flush_item(); flush_summary()
            buf, summary = None, []
            sec = {'head': m.group(1), 'items': []}
            cur['sections'].append(sec)
            continue
        if line.startswith('- '):
            flush_item()
            buf = [line[2:]]
            continue
        if not line.strip():
            flush_item()
            buf = None
            continue
        stripped = line.strip()
        if stripped.startswith('- ') or stripped.startswith('* '):
            # An indented sub-bullet would be swallowed into its parent as run-on text, and
            # a "* " bullet would be dropped entirely. Neither is expressible in the flat
            # {head, items} shape the About tab renders.
            fail(lineno, line, 'nested or non-"- " bullet is not supported')
        if buf is not None:
            buf.append(line)
        elif sec is None:
            summary.append(line)
        else:
            # Prose or a code fence sitting under a "###" heading outside any bullet. The
            # old parser discarded this without a word.
            fail(lineno, line, 'text inside a section that is not part of a "- " bullet')

    flush_item()
    flush_summary()
    return [e for e in entries if e['version'] not in SKIP_VERSIONS]


def quote(s):
    out = s.replace('\\', '\\\\').replace('"', '\\"')
    if any(ord(c) > 126 or ord(c) < 32 for c in out):
        sys.exit('non-ASCII or control character in changelog text: %r' % s)
    return '"%s"' % out


def render(entries):
    out = [HEADER]
    for e in entries:
        out.append('    {')
        out.append('        version = "%s", date = "%s",' % (e['version'], e['date']))
        if e.get('summary'):
            out.append('        summary = %s,' % quote(e['summary']))
        out.append('        sections = {')
        for s in e['sections']:
            out.append('            { head = %s, items = {' % quote(s['head']))
            for item in s['items']:
                out.append('                %s,' % quote(item))
            out.append('            } },')
        out.append('        },')
        out.append('    },')
    out.append('}')
    return '\n'.join(out) + '\n'


def main():
    check = '--check' in sys.argv[1:]

    entries = parse(io.open(SRC, encoding='utf-8').read().splitlines())[:MAX_VERSIONS]
    if not entries:
        sys.exit('no released versions found in %s' % SRC)
    text = render(entries)

    if check:
        try:
            on_disk = io.open(DST, encoding='utf-8', newline='').read()
        except IOError:
            sys.exit('%s is missing. Run: python docs/_gen_changelog.py' % DST)
        if on_disk != text:
            sys.exit('%s is STALE - it does not match %s.\n'
                     'Run: python docs/_gen_changelog.py' % (DST, SRC))
        print('%s is up to date with %s (%d versions, %d items)'
              % (DST, SRC, len(entries),
                 sum(len(s['items']) for e in entries for s in e['sections'])))
        return

    io.open(DST, 'w', encoding='utf-8', newline='\n').write(text)
    print('wrote %s: %d versions, %d sections, %d items' % (
        DST, len(entries),
        sum(len(e['sections']) for e in entries),
        sum(len(s['items']) for e in entries for s in e['sections'])))
    for e in entries:
        print('  %-7s %s  %s' % (e['version'], e['date'],
                                 ', '.join('%s(%d)' % (s['head'], len(s['items']))
                                           for s in e['sections'])))


if __name__ == '__main__':
    main()
