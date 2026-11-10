#!/usr/bin/env python3
# emu-lib: tools/emu/emu_frame.py sha 613ad0d44845 - edit there, then tools/emu/sync.py (T-505)
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


USAGE = "usage: emu_frame.py diff a.raw b.raw [...] | layout a.xml b.xml | same a.xml b.xml"


def main(argv):
    if not argv:
        print(USAGE, file=sys.stderr)
        return 2
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
