#!/usr/bin/env python3
# Test only (T-529): the corners of the map on a raw frame of the GPX page (adb exec-out screencap, no -p).
#
#   t529_corners.py frame.raw x1 y1 x2 y2 round|square kmin kmax [corners]
#
# The page colour: the most common colour of the column x1+1 between y1 and y2 (the scenario gives x1 in the
# page margin or in the gap left of the map).
# The map: from the middle of the area outwards to a run of 4 pixels of the page colour (within 6 in each of
# R, G, B) - on 15 rows and 15 columns across the inner 60 % of the map, the outermost edge of each side wins.
# From the inside, not from the edge of the area: the black navigation bar under the page (API 35 landscape)
# and a scroll bar beside it are not the page colour and would be taken for the map; a tile close to the page
# colour cuts one row short, the other rows still reach the edge (review of T-529, findings 1-2).
# Each judged corner (corners: comma list of tl tr br bl, default tl,tr,br - bl holds the map notice, over the
# frame as the user chose):
#   k - along the diagonal into the map, the first pixel off the page colour, k = 0..40. A round corner of
#       radius r covers the diagonal up to r (1 - 1/sqrt 2): 16 at r = 56 px (16 dp at 3.5 px/dp)
#   out - the two pixels 3 px outside the edges, 20 px from the corner, are the page colour: the edge found is
#       the edge of the map, not a cut inside it
#   round: kmin <= k <= kmax and out; square: k <= 2 and out. kmin/kmax always: k 41 - a whole diagonal of
#   the page colour - is a tile not drawn, not a round corner (finding 4).
# Prints "bg R G B map mx1 my1 mx2 my2 tl K/out ..." and a verdict line. Exit 0 - as expected, 1 - not,
# 2 - no frame or no map found.
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_frame import read_raw  # noqa: E402

TOL = 6
GAP = 4


def main(argv):
    if len(argv) not in (8, 9):
        print("usage: t529_corners.py frame.raw x1 y1 x2 y2 round|square kmin kmax [corners]", file=sys.stderr)
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
    kmin, kmax = int(argv[6]), int(argv[7])
    judged = (argv[8] if len(argv) == 9 else "tl,tr,br").split(",")

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

    def is_bg(x, y):
        c = px(x, y)
        return max(abs(c[0] - bg[0]), abs(c[1] - bg[1]), abs(c[2] - bg[2])) <= TOL

    def edge(x, y, dx, dy):
        """From (x, y) inside the map to the last map pixel before GAP pixels of the page colour."""
        n = 0
        while x1 <= x + dx < x2 and y1 <= y + dy < y2:
            x += dx
            y += dy
            if is_bg(x, y):
                n += 1
                if n == GAP:
                    return x - dx * GAP, y - dy * GAP
            else:
                n = 0
        return x - dx * n, y - dy * n

    cx, cy = (x1 + x2) // 2, (y1 + y2) // 2
    if is_bg(cx, cy):
        print("bg %d %d %d - the middle of the area %d %d is the page colour, no map" % (bg + (cx, cy)))
        return 2
    # a rough box by the middle row and column, then the 15 + 15 lines inside it
    rx1, rx2 = edge(cx, cy, -1, 0)[0], edge(cx, cy, 1, 0)[0]
    ry1, ry2 = edge(cx, cy, 0, -1)[1], edge(cx, cy, 0, 1)[1]
    mx1, mx2, my1, my2 = rx1, rx2, ry1, ry2
    for i in range(15):
        y = ry1 + (ry2 - ry1) * (20 + 4 * i) // 100
        x = rx1 + (rx2 - rx1) * (20 + 4 * i) // 100
        if not is_bg(cx, y):
            mx1 = min(mx1, edge(cx, y, -1, 0)[0])
            mx2 = max(mx2, edge(cx, y, 1, 0)[0])
        if not is_bg(x, cy):
            my1 = min(my1, edge(x, cy, 0, -1)[1])
            my2 = max(my2, edge(x, cy, 0, 1)[1])
    if mx2 - mx1 < 300 or my2 - my1 < 200:
        print("bg %d %d %d map %d %d %d %d - too small" % (bg + (mx1, my1, mx2, my2)))
        return 2

    corner = {"tl": (mx1, my1, 1, 1), "tr": (mx2, my1, -1, 1), "br": (mx2, my2, -1, -1), "bl": (mx1, my2, 1, -1)}
    res = {}
    for name, (ox, oy, dx, dy) in corner.items():
        k = 41
        for j in range(0, 41):
            if not is_bg(ox + dx * j, oy + dy * j):
                k = j
                break
        # 3 px outside the vertical and the horizontal edge, 20 px along it from the corner
        out = all(0 <= x < w and 0 <= y < h and is_bg(x, y)
                  for x, y in ((ox - 3 * dx, oy + 20 * dy), (ox + 20 * dx, oy - 3 * dy)))
        res[name] = (k, out)
    print("bg %d %d %d map %d %d %d %d " % (bg + (mx1, my1, mx2, my2))
          + " ".join("%s %d/%s" % (n, res[n][0], "out" if res[n][1] else "no-out") for n in ("tl", "tr", "br", "bl")))
    bad = []
    for n in judged:
        k, out = res[n]
        ok = (kmin <= k <= kmax) if mode == "round" else (k <= 2)
        if not ok or not out:
            bad.append("%s k %d%s" % (n, k, "" if out else ", outside not the page colour"))
    if bad:
        print("not %s (%s): %s" % (mode, ",".join(judged), "; ".join(bad)))
        return 1
    print("%s (%s): ok" % (mode, ",".join(judged)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
