#!/usr/bin/env python3
# emu-lib: tools/emu/emu_frame.py sha c7f41537bf87 - edit there, then tools/emu/sync.py (T-505)
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
#   emu_frame.py page a1.xml [a2.xml ...] -- b1.xml [b2.xml ...] [--rows y1,y2] [--no-bounds]
#       the whole page from the dumps of its screens (class, text, name, checked, enabled), screens glued
#       by their overlap; exit 0 when both pages have the same nodes in the same order - "the same page"
#       when the swipes stopped at other places (T-513) - and the same bounds: width and height, and the
#       place up to a scroll (bounds_diff; T-577 - a list narrowed in the classic look had the same nodes).
#       --no-bounds - the nodes only (before T-577). Rows that repeat one another (the same "On" rows) are
#       glued as an overlap - a row lost among them is not seen
#   emu_frame.py dimmed pre.raw post.raw [--dump post.xml] [--keep x1,y1,x2,y2 ...] [--rows y1,y2] [--max-lit P]
#       an overlay with a scrim (the long press menu, UiPopup, a dialog) darkens the whole page with its header:
#       pre - before it opened, post - with it open, the dump of post gives the rows of the app window (from
#       under statusBarBackground, edge to edge - from under STATUS_BAR, to the navigation bar). Every light
#       pixel of pre (luma > 100) outside the --keep rectangles (the card of the menu, the pressed row; bounds
#       of the dump as they are, [x1,y1][x2,y2], also work) must be 20 darker in post. Prints "light N, not
#       dimmed M (P %)"; exit 0 when P <= 2 (--max-lit), 1 when part of the page stays lit (and where), 2 when
#       nothing to compare. T-574, lesson 6: a light wedge over the header on every frame, the item was in the
#       dump; proven on hl-4-longpress of runs 43954976139 (23.5 %) and 44084590374 (0.1 %)
#   shift and dimmed also read the PNG frames of the evidence of a run (bc-NN.png) when pngread.py is next to it
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


def _scroll_areas(root):
    """{node: the scroll area it is in} - the nearest ancestor with a scrollable child (the ScrollBar or
    ScrollIndicator of a Flickable or ListView is "android.widget.SeekBar" scrollable="true" next to its
    content: T-575, run 44055487521, setup-01-welcome - Start sits beside two such SeekBars, the "◄" of the
    toolbar is outside). A slider or a SpinBox is a scrollable SeekBar too, so its row is an area of its own:
    two nodes of such a row moved together are not seen there - the row itself, named, sits in the outer area
    and is. A node in no area does not scroll."""
    out = {}

    def walk(n, area):
        kids = [c for c in n if c.tag == "node"]
        if any(c.get("scrollable") == "true" for c in kids):
            area = n
        for c in kids:
            out[c] = area
            walk(c, area)
    walk(root, None)
    return out


def page_places(paths, rows=None):
    """page_nodes with the places: a list of (node, [(screen, bounds, area, cut), ...]) - every screen the node
    is seen on (the overlap of two screens shows it twice); area - (screen, n) of its scroll area or None
    (_scroll_areas); cut - the node touches the top or the bottom of its area or of rows, so the edge may cut
    it. None when a dump cannot be read."""
    page = []
    for si, path in enumerate(paths):
        try:
            root = ET.parse(path).getroot()
        except (ET.ParseError, OSError):
            return None
        areas = _scroll_areas(root)
        if not any(v is not None for v in areas.values()):
            # no scroll bar on the screen (a Flickable without one): the whole screen is one area, so a
            # scrolled page is not a finding - and a node moved alone still is
            areas = dict.fromkeys(areas, root)
        top = next((parse_bounds(n.get("bounds")) for n in root.iter("node") if parse_bounds(n.get("bounds"))),
                   None)
        ids = {}
        screen = []
        for n in root.iter("node"):
            t, cd = n.get("text") or "", n.get("content-desc") or ""
            r = parse_bounds(n.get("bounds"))
            if not (t or cd) or not r or (rows and not rows[0] <= r[1] <= rows[1]):
                continue
            area = areas.get(n)
            edge = (parse_bounds(area.get("bounds")) if area is not None and area is not root else None) or top
            y1, y2 = (edge[1], edge[3]) if edge else (r[1], r[3])
            if rows:
                y1, y2 = max(y1, rows[0]), min(y2, rows[1])
            cut = r[1] <= y1 + BOUNDS_TOL or r[3] >= y2 - BOUNDS_TOL
            area = None if area is None else (si, ids.setdefault(id(area), len(ids)))
            screen.append((r[1], r[0], (n.get("class") or "", t, cd, n.get("checked") or "",
                                        n.get("enabled") or ""), r, area, cut))
        screen.sort(key=lambda e: e[:3])
        keys = [e[2] for e in screen]
        k = min(len(page), len(keys))
        while k > 0 and [p[0] for p in page[-k:]] != keys[:k]:
            k -= 1
        for j in range(k):
            page[len(page) - k + j][1].append((si,) + screen[j][3:])
        page += [(e[2], [(si,) + e[3:]]) for e in screen[k:]]
    return page


def page_nodes(paths, rows=None):
    """The whole page from the dumps of its screens, top to bottom, without positions (page_places has
    them): (class, text, content-desc, checked, enabled) of every node with a text or a name, screens glued by the longest
    overlap. None when a dump cannot be read. rows - only nodes whose top is within y1..y2 (no toolbar,
    no navigation bar). Limit: rows that repeat one another (a list of the same "On" rows, or ABAB) are glued
    over as an overlap, so a row lost there is not seen - for such a page compare the counts of its screens."""
    p = page_places(paths, rows)
    return None if p is None else [k for k, _ in p]


# Bounds of one node in two builds of the same page differ by 0 px in the CI emulator (T-577): 138 pairs bc-*
# against hc-* of runs 43953820094, 44040809621 and 44055487521 (T-575 wizard, API 30 and 35) and the
# survey pages of 4, 2 and 3 screens of 43776874657 (T-561) - 0 px on every node but the narrowed list
# (-875 px wide) and a scroll of the whole area (+25 px). Bounds are whole px of the layout, not a render
# with noise; 2 px is for a rounding of dp to px, far below a layout change (a margin is 16 dp = 56 px there).
BOUNDS_TOL = 2


def _place(places):
    """The place a node is compared at: the screen that shows it whole - the tallest, then the first (a node
    cut by the edge of a scrolled list is shorter on the screen where it is cut)."""
    return max(places, key=lambda p: (p[1][3] - p[1][1], p[1][2] - p[1][0], -p[0]))


def bounds_diff(a, b, tol=BOUNDS_TOL):
    """First node whose bounds differ between two pages (page_places; nodes paired by their place in the
    page, the same count of nodes - their texts may differ, a value 751/750): (index, node, bounds a,
    bounds b, why) or None, and None when the counts differ. Not a finding: the same shift of every node of
    one scroll area (_scroll_areas) - a swipe stopped elsewhere (T-575, run 44055487521, setup-01-welcome:
    Start [616,1967] against [616,1992]); the shift of an area is the one most of its nodes have, a tie - the
    smaller one, and an area compared on other screens (two dumps of a page) is another area. A screen with no
    scroll bar at all is one area: everything below an added gap moved the same reads as a scroll there, a
    node moved alone does not. A node the edge may cut on both sides (cut in page_places: a swipe stopped
    elsewhere) - its height and top are not compared. A finding: another width or height; a node moved
    unlike the rest of its area; a node out of any area (a toolbar) that moved."""
    if len(a) != len(b):
        return None
    pa = [_place(p) for _, p in a]
    pb = [_place(p) for _, p in b]

    def near(d, e):
        return abs(d[0] - e[0]) <= tol and abs(d[1] - e[1]) <= tol
    votes = {}
    for (_, ra, xa, ca), (_, rb, xb, cb) in zip(pa, pb):
        if xa is not None and xb is not None and not (ca and cb):
            v = votes.setdefault((xa, xb), {})
            d = (rb[0] - ra[0], rb[1] - ra[1])
            v[d] = v.get(d, 0) + 1
    common = {area: max(v, key=lambda d: (sum(n for e, n in v.items() if near(d, e)),
                                          -abs(d[0]) - abs(d[1])))
              for area, v in votes.items()}
    for i, ((_, ra, xa, ca), (_, rb, xb, cb)) in enumerate(zip(pa, pb)):
        cut = ca and cb
        dw = (rb[2] - rb[0]) - (ra[2] - ra[0])
        dh = 0 if cut else (rb[3] - rb[1]) - (ra[3] - ra[1])
        if abs(dw) > tol or abs(dh) > tol:
            return i, a[i][0], ra, rb, "size %+d,%+d" % (dw, dh)
        d = (rb[0] - ra[0], rb[1] - ra[1])
        c = common.get((xa, xb), (0, 0))
        if cut:
            d, c = (d[0], 0), (c[0], 0)
        if not near(d, c):
            return i, a[i][0], ra, rb, ("moved %+d,%+d, its scroll area %+d,%+d" % (d + c) if (xa, xb) in common
                                        else "moved %+d,%+d, not in a scroll area" % d)
    return None


def page_diff(a, b):
    """First place where two pages differ: (index, node of a or None, node of b or None), or None."""
    for i in range(max(len(a), len(b))):
        x = a[i] if i < len(a) else None
        y = b[i] if i < len(b) else None
        if x != y:
            return i, x, y
    return None


# dimmed: a pixel lighter than this (luma 0..255) is "light" before the press - the background, chips, buttons;
# black text cannot get darker and is not counted (T-574, t574_scrim.py)
LIGHT = 100
# ... and must be at least this much darker with the scrim (Material scrim on a white page: ~120 darker)
DIM_DROP = 20
# share of light pixels left lit that is still "dimmed" - anti-aliased edges of the kept rectangles
DIM_MAX_LIT = 2.0
# The navigation bar of the CI image (48 dp at 560 dpi): API 30 decor ends at 2392 of 2560, API 35 edge to edge
# draws the app under it
NAV_BAR = 168


def window_rows(path, h):
    """(top, bottom) - the rows of the app window in the dump: from under android:id/statusBarBackground (or
    STATUS_BAR when it is not there - edge to edge on API 35, the system bar is drawn over the app and its
    icons are never dimmed) to above navigationBarBackground (or the bottom of decor_content_parent; edge to
    edge, the decor down to the frame bottom - NAV_BAR above it: the light gesture pill is never dimmed, 6.7 %
    of the light pixels of a good dark frame, hd-4-longpress of run 44084590374). None - the dump cannot be
    read."""
    ns = nodes(path)
    if ns is None:
        return None
    top, bottom = STATUS_BAR, h
    nav = False
    decor = None
    for n in ns:
        rid = n.get("resource-id", "")
        b = parse_bounds(n.get("bounds"))
        if b is None:
            continue
        if rid == "android:id/statusBarBackground":
            top = b[3]
        elif rid == "android:id/navigationBarBackground" and b[1] > 0:
            bottom = min(bottom, b[1])
            nav = True
        elif rid == "android:id/decor_content_parent":
            decor = b
    if decor is not None and decor[3] < bottom:
        bottom = decor[3]
    if not nav and bottom >= h:
        bottom = h - NAV_BAR
    return top, bottom


def dimmed(fa, fb, rows, keep=(), light=LIGHT, drop=DIM_DROP, step=2):
    """(light, lit, box): a - the frame before an overlay with a scrim (the long press menu, UiPopup, a dialog),
    b - with it open. In rows y1..y2 (y2 not included) outside the keep rectangles every pixel lighter than
    `light` in a must be at least `drop` darker in b; light - how many such (every `step`-th row and column),
    lit - how many stayed lit, box - (x1, y1, x2, y2) around them or None. None - frames not comparable.
    Why: in Qt 5.15 a rounded Rectangle with a border far wider than the window drew a light wedge over the
    header (T-574, lesson 6: run 44068410854, hl-4-longpress), the menu item in the dump was there anyway."""
    if not fa or not fb or fa[:2] != fb[:2]:
        return None
    w, h, oa, da = fa
    ob, db = fb[2], fb[3]
    y1, y2 = max(0, rows[0]), min(h, rows[1])
    if y2 <= y1:
        return None
    n = lit = 0
    box = None
    for y in range(y1, y2, step):
        spans = [(k[0], k[2]) for k in keep if k[1] <= y < k[3]]
        for x in range(0, w, step):
            if any(a <= x < b for a, b in spans):
                continue
            i = (y * w + x) * 4
            pa, pb = oa + i, ob + i
            la = (299 * da[pa] + 587 * da[pa + 1] + 114 * da[pa + 2]) // 1000
            if la <= light:
                continue
            n += 1
            if (299 * db[pb] + 587 * db[pb + 1] + 114 * db[pb + 2]) // 1000 > la - drop:
                lit += 1
                box = (x, y, x, y) if box is None else (min(box[0], x), min(box[1], y), max(box[2], x),
                                                        max(box[3], y))
    return n, lit, box


def dimmed_main(args):
    """emu_frame.py dimmed pre.raw post.raw [--dump post.xml] [--keep BOUNDS ...] [--rows y1,y2] [--max-lit P]"""
    if len(args) < 2:
        print(USAGE, file=sys.stderr)
        return 2
    fa, fb = read_frame(args[0]), read_frame(args[1])
    keep, dump, rows, max_lit = [], None, None, DIM_MAX_LIT
    opts = args[2:]
    i = 0
    try:
        while i < len(opts):
            if opts[i] == "--keep":
                k = parse_bounds(opts[i + 1])
                if k is None:
                    raise ValueError("--keep is x1,y1,x2,y2 or [x1,y1][x2,y2], got %r" % opts[i + 1])
                keep.append(k)
            elif opts[i] == "--dump":
                dump = opts[i + 1]
            elif opts[i] == "--rows":
                rows = _opts(opts[i:i + 2], ("--rows",))["--rows"]
            elif opts[i] == "--max-lit":
                max_lit = float(opts[i + 1])
            else:
                raise ValueError("unknown option " + opts[i])
            i += 2
    except (ValueError, IndexError) as e:
        print("bad option: %s\n%s" % (e, USAGE), file=sys.stderr)
        return 2
    if not fa or not fb or fa[:2] != fb[:2]:
        print("frames not comparable (unreadable or other sizes)", file=sys.stderr)
        return 2
    if rows is None:
        rows = window_rows(dump, fa[1]) if dump else (STATUS_BAR, fa[1])
        if rows is None:
            print("dump not readable: %s" % dump, file=sys.stderr)
            return 2
    r = dimmed(fa, fb, rows, keep)
    if r is None:
        print("no rows to compare: %d,%d" % rows, file=sys.stderr)
        return 2
    n, lit, box = r
    p = 100.0 * lit / n if n else 0.0
    print("light %d, not dimmed %d (%.1f %%) - rows %d..%d, keep %d%s"
          % (n, lit, p, rows[0], rows[1], len(keep),
             ", lit in %d %d %d %d" % box if box and p > max_lit else ""))
    if not n:
        print("nothing light before the overlay - wrong frame?", file=sys.stderr)
        return 2
    return 0 if p <= max_lit else 1


USAGE = ("usage: emu_frame.py diff a.raw b.raw [...] | layout a.xml b.xml | same a.xml b.xml\n"
         "       | shift a.raw b.raw [--rows y1,y2] [--max N] [--tol N]\n"
         "       | page a1.xml [a2.xml ...] -- b1.xml [b2.xml ...] [--rows y1,y2] [--no-bounds]\n"
         "       | dimmed pre.raw post.raw [--dump post.xml] [--keep x1,y1,x2,y2 ...] [--rows y1,y2] [--max-lit P]")


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
        with_bounds = "--no-bounds" not in args
        args = [x for x in args if x != "--no-bounds"]
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
        pa, pb = args[:args.index("--")], args[args.index("--") + 1:]
        a = page_places(pa, rows)
        b = page_places(pb, rows)
        if a is None or b is None:
            print("dump not readable", file=sys.stderr)
            return 2
        d = page_diff([k for k, _ in a], [k for k, _ in b])
        bd = bounds_diff(a, b) if with_bounds else None

        def names(ps):
            first, last = os.path.basename(ps[0]), os.path.basename(ps[-1])
            return first if len(ps) == 1 else "%s..%s" % (first, last)
        what = "" if d is None else ", first difference at %d: %r / %r" % d
        if bd is not None:
            what += (", bounds differ at %d: %r [%d,%d][%d,%d] / [%d,%d][%d,%d] (%s)"
                     % ((bd[0], bd[1]) + bd[2] + bd[3] + (bd[4],)))
        elif with_bounds:
            # other counts: nodes are paired by their place, and a lost one moves the pairs
            what += ", bounds same" if len(a) == len(b) else ", bounds not compared (other counts)"
        # the line repeats itself: which dumps and rows gave the numbers (T-561, lesson 7: 54/75/81 not reproduced)
        print("nodes %d / %d" % (len(a), len(b)) + what
              + " – %d + %d dumps (%s -- %s), rows %s" % (len(pa), len(pb), names(pa), names(pb),
                                                           "%d,%d" % rows if rows else "all"))
        return 0 if d is None and bd is None else 1
    if argv[0] == "dimmed":
        return dimmed_main(argv[1:])
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
