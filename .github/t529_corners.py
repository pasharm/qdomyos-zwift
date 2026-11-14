#!/usr/bin/env python3
# Test only (T-529): the corners of the map on a raw frame of the GPX page (adb exec-out screencap, no -p).
#
#   t529_corners.py frame.raw x1 y1 x2 y2 round|square [kmin kmax]
#
# The page colour: the most common colour of the column x1+1 between y1 and y2 (the scenario gives x1 in the
# page margin or in the gap left of the map). The map: the first run of 60 pixels not of the page colour from
# each side - left and right on the middle row of the area, top and bottom on the column 80 px left of the
# right edge of the map (outside a corner of 16 dp = 56 px on the CI Nexus 6; the modern chips are centred).
# 60 in a row: a letter of the classic distance text over the map is shorter.
# Each corner: along the diagonal into the map, k = 0..40 px, the first pixel off the page colour (over 6 in
# one of R, G, B) - "k". A round corner of radius r covers the diagonal up to r (1 - 1/sqrt 2) = 0.29 r:
# 16 at r = 56 px. The bottom left corner holds the copyright notice of the map (over the frame, as the user
# chose) - printed, not judged.
#   round:  top left, top right, bottom right - k >= 8, and kmin <= k <= kmax when given
#   square: the same three - k <= 2 (no frame: the map from its very corner)
# Prints "bg R G B map mx1 my1 mx2 my2 tl K tr K br K bl K" and a verdict line. Exit 0 - as expected,
# 1 - not, 2 - no frame or no map found.
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_frame import read_raw  # noqa: E402

TOL = 6
RUN = 60


def main(argv):
    if len(argv) not in (6, 8):
        print("usage: t529_corners.py frame.raw x1 y1 x2 y2 round|square [kmin kmax]", file=sys.stderr)
        return 2
    r = read_raw(argv[0])
    if not r:
        print("no frame")
        return 2
    w, h, off, d = r
    x1, y1, x2, y2 = (int(v) for v in argv[1:5])
    x1, x2 = max(0, x1), min(w, x2)
    y1, y2 = max(0, y1), min(h, y2)
    mode = argv[5]
    kmin = int(argv[6]) if len(argv) == 8 else None
    kmax = int(argv[7]) if len(argv) == 8 else None

    def px(x, y):
        i = off + (y * w + x) * 4
        return d[i], d[i + 1], d[i + 2]

    counts = {}
    for y in range(y1, y2):
        c = px(x1 + 1, y)
        counts[c] = counts.get(c, 0) + 1
    if not counts:
        print("no area")
        return 2
    bg = max(counts, key=counts.get)

    def off_bg(c):
        return max(abs(c[0] - bg[0]), abs(c[1] - bg[1]), abs(c[2] - bg[2])) > TOL

    def first_run(coords):
        n = 0
        for i, (x, y) in enumerate(coords):
            if off_bg(px(x, y)):
                n += 1
                if n == RUN:
                    return coords[i - RUN + 1]
            else:
                n = 0
        return None

    ym = (y1 + y2) // 2
    a = first_run([(x, ym) for x in range(x1 + 2, x2)])
    b = first_run([(x, ym) for x in range(x2 - 1, x1 + 1, -1)])
    if not a or not b or b[0] - a[0] < 300:
        print("bg %d %d %d no map on row %d" % (bg + (ym,)))
        return 2
    mx1, mx2 = a[0], b[0]
    xc = mx2 - 80
    t = first_run([(xc, y) for y in range(y1, y2)])
    u = first_run([(xc, y) for y in range(y2 - 1, y1 - 1, -1)])
    if not t or not u or u[1] - t[1] < 200:
        print("bg %d %d %d map %d - %d, no top or bottom on column %d" % (bg + (mx1, mx2, xc)))
        return 2
    my1, my2 = t[1], u[1]

    def k_of(cx, cy, dx, dy):
        for k in range(0, 41):
            if off_bg(px(cx + dx * k, cy + dy * k)):
                return k
        return 41

    ks = {
        "tl": k_of(mx1, my1, 1, 1),
        "tr": k_of(mx2, my1, -1, 1),
        "br": k_of(mx2, my2, -1, -1),
        "bl": k_of(mx1, my2, 1, -1),
    }
    print("bg %d %d %d map %d %d %d %d tl %d tr %d br %d bl %d"
          % (bg + (mx1, my1, mx2, my2, ks["tl"], ks["tr"], ks["br"], ks["bl"])))
    bad = []
    for c in ("tl", "tr", "br"):
        k = ks[c]
        if mode == "round":
            if k < 8 or (kmin is not None and not kmin <= k <= kmax):
                bad.append("%s %d" % (c, k))
        elif k > 2:
            bad.append("%s %d" % (c, k))
    if bad:
        print("not %s: %s" % (mode, ", ".join(bad)))
        return 1
    print("%s: ok" % mode)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
