# Locale consistency check (dev tool, not shipped).
# Scans every non-Lib .lua file for L["..."] usages and confirms each key is
# listed in Locales/enUS.lua, and that every translation file keys only on
# phrases the manifest knows about. A key in code but missing from the manifest
# still works at runtime (the metatable falls back to English) but will never be
# translated. A key in a translation file that is NOT in the manifest is dead
# weight - usually a phrase that was reworded in the code and orphaned here.
# Every Locales/*.lua here is GENERATED, enUS.lua included. Rebuild them from the shared
# store in ../EverythingLocales first, then run this:
#   scan.py --apply, build.py --apply, check.py   then   python docs/_verify_locale.py
import re, io, glob, sys

KEY = re.compile(r'L\["((?:[^"\\]|\\.)*)"\]')
PAIR = re.compile(r'^\s*L\["((?:[^"\\]|\\.)*)"\]\s*=\s*"((?:[^"\\]|\\.)*)"\s*$')
ANY_ENTRY = re.compile(r'^\s*L\[')
SPEC = re.compile(r'%(?:(\d+)\$)?([-+ #0]*)(\d*)(?:\.(\d+))?([a-zA-Z])')
# %c takes a number in Lua 5.1, so it belongs with the numeric conversions
NUMERIC = set('diouxXeEfgGc')
VALID = set('diouxXeEfgGqsc')

# A key holding one of these instead of its ASCII twin never matches, so the phrase is
# never translated and nothing on screen says why - every one of them reads as correct
# English. Written as \u escapes on purpose: a table of look-alikes spelled with the
# look-alikes themselves cannot be proofread, and it keeps this file ASCII like the rest.
#
# Where it can actually fire is OUR OWN keys, which is why the check runs over the code
# and the manifest and not only over the translation files. A translator's mistake cannot
# reach Locales/*.lua at all - build.py spells every key from the manifest, so a bad key
# in the shared store fails to match and the phrase comes out missing instead. The
# incident behind this was 64 of them in a contributed zhCN file, 21 being EQOT phrases;
# that landed in EverythingLocales, which still has no guard of its own.
CONFUSABLE = {
    '\u2011': "U+2011 non-breaking hyphen (want '-')",
    '\u2010': "U+2010 hyphen (want '-')",
    '\u2012': "U+2012 figure dash (want '-')",
    # U+2014 em dash is deliberately absent: three EQOT keys hold a real one, written
    # \226\128\148, and nothing tells those from a wrong one by character alone. A wrong
    # em dash still surfaces, as an orphan. U+2013 is not exempt - it drew a tofu box on
    # a Korean client and became a plain hyphen in v1.4.1.
    '\u2013': "U+2013 en dash (want '-')",
    '\u00a0': "U+00A0 non-breaking space (want a plain space)",
    '\u2018': "U+2018 left single quote (want ')",
    '\u2019': "U+2019 right single quote (want ')",
    '\u201c': 'U+201C left double quote (want a plain ")',
    '\u201d': 'U+201D right double quote (want a plain ")',
    # what a Chinese IME emits by default, so the likeliest next instance
    '\uff0d': "U+FF0D fullwidth hyphen-minus (want '-')",
    '\u2212': "U+2212 minus sign (want '-')",
    '\u00ad': "U+00AD soft hyphen (invisible, want nothing)",
    '\u3000': "U+3000 ideographic space (want ' ')",
    '\uff08': "U+FF08 fullwidth left paren (want '(')",
    '\uff09': "U+FF09 fullwidth right paren (want ')')",
    '\uff1a': "U+FF1A fullwidth colon (want ':')",
}
ESCAPES = {'a': '\a', 'b': '\b', 'f': '\f', 'n': '\n', 'r': '\r',
           't': '\t', 'v': '\v', '\\': '\\', '"': '"', "'": "'"}
DIGITS = '0123456789'


def decode(s):
    """Lua short-string body -> the BYTES Lua holds at runtime.

    Bytes, not text, so a key mixing a literal character with an escaped one reassembles
    correctly - the two halves are the same encoding by the time they meet. Mirrors
    ../EverythingLocales/lualocale.py, which is what actually decides whether a key matches.
    """
    out, i, n = [], 0, len(s)
    while i < n:
        c = s[i]
        if c != '\\':
            out.append(c.encode('utf-8'))
            i += 1
            continue
        i += 1
        if i >= n:
            break
        e = s[i]
        if e in ESCAPES:
            out.append(ESCAPES[e].encode('utf-8'))
            i += 1
        # ASCII 0-9 only: str.isdigit() also accepts superscripts, which int() then
        # rejects, and an uncaught ValueError here takes the release workflow down
        elif e in DIGITS:
            digits = ''
            while i < n and s[i] in DIGITS and len(digits) < 3:
                digits += s[i]
                i += 1
            out.append(bytes([int(digits) & 0xFF]))
        else:
            out.append(e.encode('utf-8'))
            i += 1
    return b''.join(out)


def confusables_in(key):
    # errors='replace' rather than a try/except around the whole key: one undecodable
    # byte must not silence every confusable beside it
    text = decode(key).decode('utf-8', 'replace')
    return ["%s at position %d" % (CONFUSABLE[c], i + 1)
            for i, c in enumerate(text) if c in CONFUSABLE]


def parse_format(fmt):
    """Map argument index -> conversion type, plus counts and malformed specifiers.

    Compared by ARGUMENT INDEX rather than as a flat list, because WoW's string.format
    supports Blizzard's positional extension (%1$s, %2$d) and reordering is the entire
    point of it - a translator who moves the arguments around is correct, not broken.
    """
    args, bad = {}, []
    positional = plain = 0
    nxt = 1
    stripped = fmt.replace('%%', '')
    consumed = set()
    for m in SPEC.finditer(stripped):
        idx, _flags, width, prec, conv = m.groups()
        consumed.add(m.start())
        if conv not in VALID or len(width or '') > 2 or len(prec or '') > 2:
            bad.append(m.group(0))
            continue
        if idx:
            positional += 1
            i = int(idx)
        else:
            plain += 1
            i = nxt
            nxt += 1
        args[i] = conv
    # A '%' the pattern did not consume is a malformed escape - '%$d', a stray '%z', or a
    # lone trailing '%' where the translator meant '%%'. Lua raises on all three.
    for pos, ch in enumerate(stripped):
        if ch == '%' and pos not in consumed:
            bad.append(stripped[pos:pos + 3])
    return args, positional, plain, bad


def format_problems(key, val):
    """(fails, notes). Only fails are gated - a note is legitimate and common."""
    fails, notes = [], []
    kargs, _kp, _kn, kbad = parse_format(key)
    vargs, vpos, vplain, vbad = parse_format(val)

    for b in vbad:
        fails.append("invalid specifier %r" % b)
    if kbad:
        fails.append("invalid specifier in the ENGLISH KEY: %s" % kbad)
    if vpos and vplain:
        fails.append("mixes positional and plain specifiers in one string")

    for i, conv in sorted(vargs.items()):
        kconv = kargs.get(i)
        if kconv is None:
            fails.append("uses argument %d (%%%s) but the key supplies only %d"
                         % (i, conv, len(kargs)))
        elif conv in NUMERIC and kconv not in NUMERIC:
            fails.append("argument %d is %%%s but the key passes a string (%%%s)"
                         % (i, conv, kconv))

    # Dropping an argument is fine: Lua ignores the surplus one that gets passed, and
    # Russian and Korean have no use for English's "%s" plural suffix.
    missing = sorted(set(kargs) - set(vargs))
    if missing and not fails:
        notes.append("does not use argument(s) " + ", ".join(str(i) for i in missing))
    return fails, notes


def strip_comments(s):
    # drop full-line Lua comments so doc examples like L["English string"] in
    # headers don't register as real keys. (Good enough; no block-comment use.)
    return '\n'.join(l for l in s.splitlines() if not l.lstrip().startswith('--'))


def keyset(path):
    s = strip_comments(io.open(path, encoding='utf-8', errors='replace').read())
    return set(m.group(1) for m in KEY.finditer(s))


manifest = keyset('Locales/enUS.lua')

code = {}
for path in glob.glob('**/*.lua', recursive=True):
    p = path.replace('\\', '/')
    if p.startswith('Libs/') or p.startswith('Locales/'):
        continue
    for k in keyset(p):
        code.setdefault(k, []).append(p)

print("distinct keys used in code:", len(code))
print("keys listed in enUS.lua   :", len(manifest))

problems = 0

missing = {k: v for k, v in code.items() if k not in manifest}
print("\nCODE keys MISSING from manifest (work, but are never translated):")
if missing:
    problems += len(missing)
    for k in sorted(missing):
        print("   !", ascii(k[:60]), "<-", ", ".join(sorted(set(missing[k]))))
else:
    print("   (none - every code key is in the manifest)")

# Checked HERE and not only in the translation files, because the manifest is generated
# from this code: a look-alike we write is copied into enUS.lua before this gate runs, so
# code equals manifest, nothing is orphaned and nothing is flagged. It then ships in the
# English string, and the first report is an ORPHAN against the translator who spelled it
# correctly - blaming the wrong repo. Measured 2026-08-15.
print("\nKEYS with look-alike punctuation (never match, so never translate):")
own = sorted(set(code) | set(manifest))
found = False
for k in own:
    why = confusables_in(k)
    if not why:
        continue
    found = True
    problems += 1
    where = ", ".join(sorted(set(code.get(k, ["Locales/enUS.lua"]))))
    print("   !", ascii(k[:55]), "<-", where)
    for w in why:
        print("     ->", w)
if not found:
    print("   (none)")

print("\nTRANSLATION files:")
for path in sorted(glob.glob('Locales/*.lua')):
    p = path.replace('\\', '/')
    if p.endswith('enUS.lua'):
        continue
    ks = keyset(p)
    orphans = sorted(k for k in ks if k not in manifest)

    # A translation whose format specifiers cannot satisfy its English key makes
    # string.format() raise the first time that line is drawn - at runtime, in one
    # language only, where nobody testing in English ever sees it.
    badfmt, noted, confused, unread = [], [], [], 0
    for line in io.open(p, encoding='utf-8').read().splitlines():
        if line.lstrip().startswith('--'):
            continue
        if not ANY_ENTRY.match(line):
            continue
        m = PAIR.match(line)
        # An L[...] line the parser cannot read would be skipped silently and pass. A
        # false negative in a gate is the dangerous kind, so it counts as a problem.
        if not m:
            unread += 1
            continue
        fails, notes = format_problems(m.group(1), m.group(2))
        if fails:
            badfmt.append((m.group(1), fails))
        if notes:
            noted.append((m.group(1), notes))
        why = confusables_in(m.group(1))
        if why:
            confused.append((m.group(1), why))

    print("   %-18s %4d phrases, %d orphaned, %d bad format, %d confusable, %d note(s)" %
          (p, len(ks), len(orphans), len(badfmt), len(confused), len(noted)))
    if orphans:
        problems += len(orphans)
        for k in orphans:
            print("      ! orphan:", ascii(k[:60]))
    for k, why in confused:
        problems += 1
        print("      ! KEY has look-alike punctuation:", ascii(k[:55]))
        for w in why:
            print("        -> %s" % w)
    if unread:
        problems += unread
        print("      ! %d L[...] line(s) the parser could not read, so they were NOT "
              "checked" % unread)
    for k, why in badfmt:
        problems += 1
        print("      ! %s" % ascii(k[:55]))
        for w in why:
            print("        -> %s" % w)
    for k, why in noted:
        print("      - note: %s (%s)" % (ascii(k[:50]), "; ".join(why)))

sys.exit(1 if problems else 0)
