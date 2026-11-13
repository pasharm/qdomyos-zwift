#!/usr/bin/env python3
# Test only (T-530): the route line on a raw frame of the GPX page (adb exec-out screencap, no -p).
#
#   t530_map.py frame.raw x1 y1 x2 y2 color[,color...]
#       prints "line N box lx1 ly1 lx2 ly2 map mx1 my1 mx2 my2 gap L T R B":
#       N - pixels of the line colour (within 40 of one of the colours, RGB) inside the search area x1..x2,
#       y1..y2; box - where they are; map - the light, grey-ish part of the area (the OSM tiles: rows and
#       columns where over half of the pixels are light), an estimate only; gap - from the line box to the map
#       box on each side (0 or less: the line reaches the edge of the map - cut off); "notice y1 y2" - the rows
#       of the blue links of the map notice at its bottom, "above A" - from the lowest line pixel to the top of
#       the notice (A < 0: the line goes down beside or under the notice). Exit 0 with a line, 1
#       without one, 2 when the frame cannot be read.
# Colours: the classic line is 'red', the modern one window.ui.accent (violet: #B69DF8 dark, #6444BE light,
# main.qml); a pixel with green over red minus 10 is never the line (the links of the map notice). The selected card of the modern list is drawn in the accent too - the area must leave the list out.
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_frame import read_raw  # noqa: E402


def hexrgb(s):
    s = s.strip().lstrip("#")
    if s == "red":
        return (255, 0, 0)
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16))


def main(argv):
    if len(argv) != 6:
        print("usage: t530_map.py frame.raw x1 y1 x2 y2 colors", file=sys.stderr)
        return 2
    r = read_raw(argv[0])
    if not r:
        print("no frame", file=sys.stderr)
        return 2
    w, h, off, d = r
    x1, y1, x2, y2 = (int(v) for v in argv[1:5])
    x1, x2 = max(0, x1), min(w, x2)
    y1, y2 = max(0, y1), min(h, y2)
    cols = [hexrgb(c) for c in argv[5].split(",")]
    tol2 = 40 * 40
    n = 0
    lx1 = ly1 = 10 ** 9
    lx2 = ly2 = -1
    light_rows = []
    ny1 = 10 ** 9
    ny2 = -1
    light_cols = [0] * (x2 - x1)
    for y in range(y1, y2):
        base = off + y * w * 4
        row = d[base + x1 * 4:base + x2 * 4]
        lit = 0
        for i in range(0, len(row), 4):
            pr, pg, pb = row[i], row[i + 1], row[i + 2]
            # the links of the map notice ("Thunderforest", "OpenStreetMap"): pure blue
            if pb >= 200 and pr <= 60 and pg <= 60:
                ny1 = min(ny1, y)
                ny2 = max(ny2, y)
            if min(pr, pg, pb) >= 170 and max(pr, pg, pb) - min(pr, pg, pb) <= 60:
                lit += 1
                light_cols[i // 4] += 1
            # green under red: the line colours have it (violet 182,157,248 / 100,68,190; red), the blue links
            # of the map notice smoothed into the page have it over red (181,187,234; 158,164,237) and were
            # once taken for a line - 3688 px on bmp-1-long-open of run 43491552125, a frame with no line
            if pg > pr - 10:
                continue
            for cr, cg, cb in cols:
                if (pr - cr) ** 2 + (pg - cg) ** 2 + (pb - cb) ** 2 <= tol2:
                    n += 1
                    x = x1 + i // 4
                    lx1 = min(lx1, x)
                    lx2 = max(lx2, x)
                    ly1 = min(ly1, y)
                    ly2 = max(ly2, y)
                    break
        if lit * 2 > (x2 - x1):
            light_rows.append(y)
    lc = [x1 + i for i, c in enumerate(light_cols) if c * 2 > (y2 - y1)]
    if light_rows and lc:
        mx1, my1, mx2, my2 = lc[0], light_rows[0], lc[-1], light_rows[-1]
    else:
        mx1 = my1 = mx2 = my2 = -1
    notice = "notice %d %d" % (ny1, ny2) if ny2 >= 0 else "notice - -"
    if n == 0:
        print("line 0 box - - - - map %d %d %d %d gap - - - - %s above -" % (mx1, my1, mx2, my2, notice))
        return 1
    if mx1 >= 0:
        gap = (lx1 - mx1, ly1 - my1, mx2 - lx2, my2 - ly2)
    else:
        gap = ("-",) * 4
    above = str(ny1 - ly2) if ny2 >= 0 else "-"
    print("line %d box %d %d %d %d map %d %d %d %d gap %s %s %s %s %s above %s"
          % ((n, lx1, ly1, lx2, ly2, mx1, my1, mx2, my2) + tuple(str(g) for g in gap) + (notice, above)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
