#!/usr/bin/env python3
# emu-lib: tools/emu/emu_frame.py sha 25045e18ed33 - edit there, then tools/emu/sync.py (T-505)
# Test only (T-505): compare two raw frames of `adb exec-out screencap` (no -p) outside masks, and the
# layout of two uiautomator dumps. Delivered with lib.sh by tools/emu/sync.py as .github/emu_frame.py.
#
#   emu_frame.py diff a.raw b.raw [--dumps a.xml b.xml] [--mask x1,y1,x2,y2 ...] [--rows y1,y2] [--tol N]
#       prints "rows N box x1 y1 x2 y2" (N - rows that differ outside the masks; box - where), exit 0
#       when N is 0, 1 when the frames differ, 2 when a frame cannot be read
#   emu_frame.py layout a.xml b.xml
#       exit 0 when both dumps have the same nodes in the same places (class and bounds; texts may
#       differ - a tile counting the time), 1 when something moved, appeared or went away
#   emu_frame.py same a.xml b.xml
#       exit 0 when the dumps are the same with texts and names too - the end of a page after a swipe: a
#       list of rows of one height scrolled by whole rows has the same layout, only other texts (T-505)
#   emu_frame.py shift a.raw b.raw [--rows y1,y2] [--max N] [--tol N]
#       two frames of one page scrolled to other places (base and head, a swipe stops a few px apart):
#       prints "shift S rows N of M" - b is a moved by S px and still differs in N of the M rows compared
#       (tol 32 by default); exit 0 when N is 0. A row between pixels differs only by anti-aliasing: N > 0
#       there is not a layout change by itself - look at the frames or compare the page by `page` (T-513)
#   emu_frame.py page a1.xml [a2.xml ...] -- b1.xml [b2.xml ...] [--rows y1,y2]
#       the whole page from the dumps of its screens, without positions (class, text, name, checked,
#       enabled), screens glued by their overlap; exit 0 when both pages have the same nodes in the same
#       order - "the same page" when the swipes stopped at other places (T-513); rows that repeat one
#       another (the same "On" rows) are glued as an overlap - a row lost among them is not seen
#   shift also reads the PNG frames of the evidence of a run (bc-NN.png) when pngread.py is next to it
#
# Masks: the --mask rectangles, and with --dumps every node whose text or name differs between the
# two dumps (a clock, the value of a tile, a timer), every text field and the deepest focused node
# smaller than a quarter of the screen (a cursor blinks there; QML fields are no EditText). Rows:
# only y1..y2 (the app area; the status bar clock is outside it). The raw frame: width, height and
# format (4 bytes each), on API 28+ also a color space, then RGBA rows - the header is taken as what
# is left before width * height * 4 bytes (the same as tap_dot of the T-498 scenario).
# Why: the screen must be still before a tap (an item still sliding takes the tap elsewhere), and a tap
# that changed nothing at all on the screen is told from one that opened the wrong screen
# (notes/emu-tools-research-2026-11-10.md: UI Automator waitForStable, Maestro settle - only by the
# frame is not enough, a shimmer of 0.6 % fooled Maestro, so moving texts are masked by the dumps).
import os
import sys
import xml.etree.ElementTree as ET

# Render noise of the CI emulator between two builds of the same screen: pixels of c-base-1-settings and
# c-head-1-settings of run 42823136459 (T-498, the classic look not changed by the PR) - 14 967 differ, all
# by less than 32 of 255 except 525 of the status bar clock (64+). A fixed floor, not a share of pixels
# that grows run by run (notes/emu-tools-research-2026-11-10.md, nowinandroid #1646)
RENDER_NOISE = 32
# The status bar of the CI image (Nexus 6, 560 dpi: 24 dp) - its clock differs between any two frames
STATUS_BAR = 84


def read_raw(path):
    try:
        with open(path, "rb") as f:
            d = f.read()
    except OSError:
        return None
    if len(d) < 12:
        return None
    w = int.from_bytes(d[0:4], "little")
    h = int.from_bytes(d[4:8], "little")
    if w <= 0 or h <= 0 or len(d) < w * h * 4 + 12:
        return None
    return w, h, len(d) - w * h * 4, d


def parse_bounds(s):
    parts = (s or "").replace("][", ",").strip("[]").split(",")
    try:
        r = tuple(int(p) for p in parts)
    except ValueError:
        return None
    return r if len(r) == 4 and r[2] > r[0] and r[3] > r[1] else None


def nodes(path):
    try:
        return list(ET.parse(path).getroot().iter("node"))
    except (ET.ParseError, OSError):
        return None


def key_of(n):
    return (n.get("class") or "", n.get("bounds") or "", n.get("resource-id") or "")


def label_of(n):
    return key_of(n) + ((n.get("text") or ""), (n.get("content-desc") or ""))


def layout_same(a, b, key=key_of):
    na, nb = nodes(a), nodes(b)
    if na is None or nb is None:
        return False
    return [key(n) for n in na] == [key(n) for n in nb]


def focus_masks(path):
    """Rects of the deepest focused nodes smaller than a quarter of the screen: a QML text field is not an
    EditText in the dump (`View$VirtualChild` "Search settings", focused), and its cursor blinks (T-505:
    7x52 px of c-*-3s-s1b-nokeyboard, run 42823136459). The focused page itself is not masked."""
    try:
        root = ET.parse(path).getroot()
    except (ET.ParseError, OSError):
        return []
    whole = None
    out = []
    for n in root.iter("node"):
        r = parse_bounds(n.get("bounds"))
        if r and whole is None:
            whole = (r[2] - r[0]) * (r[3] - r[1])
        if n.get("focused") != "true" or not r:
            continue
        if any(c.get("focused") == "true" for c in n.iter("node") if c is not n):
            continue
        if whole and (r[2] - r[0]) * (r[3] - r[1]) * 4 <= whole:
            out.append(r)
    return out


def dump_masks(a, b):
    """Rects of nodes whose label differs between two dumps of the same layout, and text fields."""
    na, nb = nodes(a), nodes(b)
    out = []
    if na is None or nb is None:
        return out
    for n in na + nb:
        if "EditText" in (n.get("class") or ""):
            r = parse_bounds(n.get("bounds"))
            if r:
                out.append(r)
    out += focus_masks(a) + focus_masks(b)
    by_key = {}
    for n in na:
        by_key.setdefault(key_of(n), []).append(n)
    for n in nb:
        others = by_key.get(key_of(n)) or []
        label = ((n.get("text") or ""), (n.get("content-desc") or ""))
        if not any(((o.get("text") or ""), (o.get("content-desc") or "")) == label for o in others):
            r = parse_bounds(n.get("bounds"))
            if r:
                out.append(r)
    return out


def _noisy_span(da, db, ra, rb, s0, s1, tol):
    """(first, last + 1) pixels of the span whose R, G or B differs by more than tol, or None."""
    first = last = None
    for x in range(s0, s1):
        i, j = ra + x * 4, rb + x * 4
        if da[i:i + 3] != db[j:j + 3] and max(abs(da[i] - db[j]), abs(da[i + 1] - db[j + 1]),
                                               abs(da[i + 2] - db[j + 2])) > tol:
            if first is None:
                first = x
            last = x
    return None if first is None else (first, last + 1)


def diff(fa, fb, masks=(), rows=None, tol=0):
    """(rows that differ, box) outside masks, or None when a frame is unreadable or sizes differ. tol - a pixel
    differs only when R, G or B changes by more than that (the render noise of the emulator between two builds:
    below 32 of 255, RENDER_NOISE); 0 - any change (stillness: the same screen captured twice)."""
    if fa is None or fb is None or fa[:2] != fb[:2]:
        return None
    w, h, oa, da = fa
    _, _, ob, db = fb
    y1, y2 = (0, h) if rows is None else (max(0, rows[0]), min(h, rows[1]))
    count = 0
    box = None
    for y in range(y1, y2):
        # the parts of the row outside the masks
        cuts = sorted((max(0, m[0]), min(w, m[2])) for m in masks if m[1] <= y < m[3])
        spans, x = [], 0
        for c0, c1 in cuts:
            if c0 > x:
                spans.append((x, c0))
            x = max(x, c1)
        if x < w:
            spans.append((x, w))
        row_a, row_b = oa + y * w * 4, ob + y * w * 4
        hit = None
        for s0, s1 in spans:
            if da[row_a + s0 * 4:row_a + s1 * 4] != db[row_b + s0 * 4:row_b + s1 * 4]:
                hit = (s0, s1) if not tol else _noisy_span(da, db, row_a, row_b, s0, s1, tol)
                if hit:
                    break
        if hit is None:
            continue
        if count < 64 and not tol:
            # the exact columns, for the first rows only (a whole new screen would take seconds)
            s0, s1 = hit
            while s0 < s1 and da[row_a + s0 * 4:row_a + s0 * 4 + 4] == db[row_b + s0 * 4:row_b + s0 * 4 + 4]:
                s0 += 1
            while s1 > s0 and da[row_a + s1 * 4 - 4:row_a + s1 * 4] == db[row_b + s1 * 4 - 4:row_b + s1 * 4]:
                s1 -= 1
            hit = (s0, s1)
        count += 1
        if box is None:
            box = [hit[0], y, hit[1], y + 1]
        else:
            box = [min(box[0], hit[0]), box[1], max(box[2], hit[1]), y + 1]
    return count, box


# Rows vote for a shift by their pixels in 4 levels per channel: render noise below RENDER_NOISE moves a
# value across a level only near its edge, so most rows of another build still match (exact bytes did not:
# with noise in every row no row voted)
COARSE = bytes(v >> 6 for v in range(256))


def _row_differs(da, db, ra, rb, w, tol):
    if da[ra:ra + w * 4] == db[rb:rb + w * 4]:
        return False
    return not tol or _noisy_span(da, db, ra, rb, 0, w, tol) is not None


def diff_shifted(fa, fb, s, rows, tol):
    """Rows y of b (within rows) that differ from rows y - s of a; rows of a out of the frame are skipped."""
    w, h, oa, da = fa
    _, _, ob, db = fb
    y1, y2 = rows
    n = 0
    for y in range(max(y1, y1 + s), min(y2, y2 + s)):
        if _row_differs(da, db, oa + (y - s) * w * 4, ob + y * w * 4, w, tol):
            n += 1
    return n


def read_frame(path):
    """A raw frame, or a PNG of the evidence of a run (bc-NN.png) through pngread.py next to this file -
    present in tools/emu, not in the copies sync.py puts into a branch (there the frames are raw)."""
    f = read_raw(path)
    if f is not None:
        return f
    try:
        with open(path, "rb") as fh:
            png = fh.read(8) == b"\x89PNG\r\n\x1a\n"
    except OSError:
        return None
    if not png:
        return None
    try:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import pngread
    except ImportError:
        print("%s: a PNG, and pngread.py is not next to emu_frame.py" % path, file=sys.stderr)
        return None
    return pngread.read_png(path)


def best_shift(fa, fb, rows=None, max_shift=120, tol=RENDER_NOISE, tries=5):
    """(shift, rows that still differ, rows compared): b row y shows what a row y - shift shows. Two frames
    of one page that a swipe stopped at other places (T-513: swipe_page exact stopped up to 60 px apart on
    two APKs, and "screen N against screen N" turned red on a page that had not changed). The shift is
    voted by rows that match in coarse levels (COARSE) and are not one plain colour (a background row
    matches at any shift), then the best few are compared with tol; ties go to the smaller shift. A
    pixel differs when R, G or B moves by more than tol - stricter than a grey average: a row of a
    frame between pixels (anti-aliasing) counts here more often than in a greyscale compare."""
    if fa is None or fb is None or fa[:2] != fb[:2]:
        return None
    w, h, oa, da = fa
    _, _, ob, db = fb
    y1, y2 = (STATUS_BAR, h) if rows is None else (max(0, rows[0]), min(h, rows[1]))
    if y2 - y1 <= max_shift:
        # rows out of the frame, the wrong way round or fewer than the shift: nothing would be compared,
        # and "0 rows differ" would read as the same page
        return None
    where = {}
    for y in range(y1, y2):
        row = da[oa + y * w * 4:oa + (y + 1) * w * 4].translate(COARSE)
        if row.count(row[:4]) * 4 != len(row):
            where.setdefault(row, []).append(y)
    votes = {}
    for y in range(y1, y2):
        for ya in where.get(db[ob + y * w * 4:ob + (y + 1) * w * 4].translate(COARSE), ()):
            s = y - ya
            if -max_shift <= s <= max_shift:
                votes[s] = votes.get(s, 0) + 1
    cands = sorted(votes, key=lambda s: (-votes[s], abs(s)))[:tries]
    if 0 not in cands:
        cands.append(0)
    best = None
    for s in cands:
        n = diff_shifted(fa, fb, s, (y1, y2), tol)
        if best is None or (n, abs(s)) < (best[1], abs(best[0])):
            best = (s, n)
    s, n = best
    return s, n, min(y2, y2 + s) - max(y1, y1 + s)


def page_nodes(paths, rows=None):
    """The whole page from the dumps of its screens, top to bottom, without positions: (class, text,
    content-desc, checked, enabled) of every node with a text or a name, screens glued by the longest
    overlap. None when a dump cannot be read. rows - only nodes whose top is within y1..y2 (no toolbar,
    no navigation bar). Limit: rows that repeat one another (a list of the same "On" rows, or ABAB) are glued
    over as an overlap, so a row lost there is not seen - for such a page compare the counts of its screens."""
    page = []
    for path in paths:
        ns = nodes(path)
        if ns is None:
            return None
        screen = []
        for n in ns:
            t, cd = n.get("text") or "", n.get("content-desc") or ""
            r = parse_bounds(n.get("bounds"))
            if not (t or cd) or not r or (rows and not rows[0] <= r[1] <= rows[1]):
                continue
            screen.append((r[1], r[0], (n.get("class") or "", t, cd, n.get("checked") or "",
                                        n.get("enabled") or "")))
        screen = [k for _, _, k in sorted(screen)]
        k = min(len(page), len(screen))
        while k > 0 and page[-k:] != screen[:k]:
            k -= 1
        page += screen[k:]
    return page


def page_diff(a, b):
    """First place where two pages differ: (index, node of a or None, node of b or None), or None."""
    for i in range(max(len(a), len(b))):
        x = a[i] if i < len(a) else None
        y = b[i] if i < len(b) else None
        if x != y:
            return i, x, y
    return None


USAGE = ("usage: emu_frame.py diff a.raw b.raw [...] | layout a.xml b.xml | same a.xml b.xml\n"
         "       | shift a.raw b.raw [--rows y1,y2] [--max N] [--tol N]\n"
         "       | page a1.xml [a2.xml ...] -- b1.xml [b2.xml ...] [--rows y1,y2]")


def _opts(opts, allowed):
    out = {}
    i = 0
    while i < len(opts):
        if opts[i] not in allowed:
            raise ValueError("unknown option " + opts[i])
        v = opts[i + 1]
        out[opts[i]] = tuple(int(p) for p in v.split(",")) if opts[i] == "--rows" else int(v)
        if opts[i] == "--rows" and len(out["--rows"]) != 2:
            raise ValueError("--rows is y1,y2")
        i += 2
    return out


def main(argv):
    if not argv:
        print(USAGE, file=sys.stderr)
        return 2
    if argv[0] == "shift" and len(argv) >= 3:
        try:
            o = _opts(argv[3:], ("--rows", "--max", "--tol"))
        except (ValueError, IndexError) as e:
            print("bad option: %s\n%s" % (e, USAGE), file=sys.stderr)
            return 2
        r = best_shift(read_frame(argv[1]), read_frame(argv[2]), o.get("--rows"), o.get("--max", 120),
                       o.get("--tol", RENDER_NOISE))
        if r is None:
            print("frames not comparable (unreadable, other sizes, or --rows not more than --max rows "
                  "inside the frame)", file=sys.stderr)
            return 2
        print("shift %+d rows %d of %d" % r)
        return 0 if r[1] == 0 else 1
    if argv[0] == "page":
        args = argv[1:]
        rows = None
        if "--rows" in args:
            i = args.index("--rows")
            try:
                rows = _opts(args[i:i + 2], ("--rows",))["--rows"]
            except (ValueError, IndexError) as e:
                print("bad option: %s\n%s" % (e, USAGE), file=sys.stderr)
                return 2
            args = args[:i] + args[i + 2:]
        if "--" not in args or not args[:args.index("--")] or not args[args.index("--") + 1:]:
            print(USAGE, file=sys.stderr)
            return 2
        a = page_nodes(args[:args.index("--")], rows)
        b = page_nodes(args[args.index("--") + 1:], rows)
        if a is None or b is None:
            print("dump not readable", file=sys.stderr)
            return 2
        d = page_diff(a, b)
        print("nodes %d / %d" % (len(a), len(b)) + ("" if d is None else
              ", first difference at %d: %r / %r" % d))
        return 0 if d is None else 1
    if argv[0] == "layout":
        return 0 if layout_same(argv[1], argv[2]) else 1
    if argv[0] == "same":
        return 0 if layout_same(argv[1], argv[2], label_of) else 1
    if argv[0] != "diff" or len(argv) < 3:
        print(USAGE, file=sys.stderr)
        return 2
    opts = argv[3:]
    masks = []
    rows = None
    tol = 0
    i = 0
    try:
        while i < len(opts):
            if opts[i] == "--mask":
                m = tuple(int(v) for v in opts[i + 1].split(","))
                if len(m) != 4:
                    raise ValueError("a mask is x1,y1,x2,y2")
                masks.append(m)
                i += 2
            elif opts[i] == "--dumps":
                masks += dump_masks(opts[i + 1], opts[i + 2])
                i += 3
            elif opts[i] == "--rows":
                rows = tuple(int(v) for v in opts[i + 1].split(","))
                i += 2
            elif opts[i] == "--tol":
                tol = int(opts[i + 1])
                i += 2
            else:
                print("unknown option %s\n%s" % (opts[i], USAGE), file=sys.stderr)
                return 2
    except (ValueError, IndexError) as e:
        # a bad --mask must not read as "the frames differ" (1)
        print("bad option %s: %s\n%s" % (opts[i], e, USAGE), file=sys.stderr)
        return 2
    r = diff(read_raw(argv[1]), read_raw(argv[2]), masks, rows, tol)
    if r is None:
        print("frames not comparable", file=sys.stderr)
        return 2
    n, box = r
    print("rows %d box %s" % (n, " ".join(str(v) for v in box) if box else "-"))
    return 0 if n == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
