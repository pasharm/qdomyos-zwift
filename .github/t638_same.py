#!/usr/bin/env python3
"""Test only (T-638): on API 31+ the window background must stay hidden - the frame of the branch is the frame of
master (the same case, the home page in landscape).

t638_same.py <base.raw> <head.raw>

There Qt's content extends into the cutout (setDecorFitsSystemWindows(false), LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS),
so the window background the fix changes is under Qt's surface. A pixel differs if one of its channels differs by more
than 6 (the step of a 16-bit colour buffer). What may differ: the running clock of the status bar and the elapsed time
on a tile - a few small boxes. Prints one line:
  same WxH differ N of M (P %) box X1,Y1-X2,Y2 cutout-strip-differ K result ok|wrong
cutout-strip-differ - differing pixels in the left 168 px (the "tall" cutout at user_rotation 1), where the strip of
API 28-30 would be; only said: on API 31+ Qt's content is there too (the clock, a tile). ok - under 1 % of the frame:
a window background showing beside the content is a strip the height of the screen, 168 x 1440 = 6.6 % of 2560 x 1440.
Exit 0 - ok, 1 - wrong, 2 - not compared (no frame, other size).
"""
import struct
import sys

STRIP = 168


def read_raw(path):
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError:
        return None
    if len(data) < 12:
        return None
    w, h = struct.unpack("<II", data[:8])
    head = len(data) - w * h * 4
    if w <= 0 or h <= 0 or head < 12:
        return None
    return w, h, head, data


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 2
    a, b = read_raw(argv[0]), read_raw(argv[1])
    if a is None or b is None:
        print("no frame")
        return 2
    if a[:2] != b[:2]:
        print("other size: %dx%d and %dx%d" % (a[0], a[1], b[0], b[1]))
        return 2
    w, h = a[0], a[1]
    da, db = a[3], b[3]
    oa, ob = a[2], b[2]
    n = strip = 0
    x1, y1, x2, y2 = w, h, -1, -1
    for y in range(h):
        ra, rb = oa + y * w * 4, ob + y * w * 4
        if da[ra:ra + w * 4] == db[rb:rb + w * 4]:
            continue
        for x in range(w):
            i, j = ra + x * 4, rb + x * 4
            if (abs(da[i] - db[j]) > 6 or abs(da[i + 1] - db[j + 1]) > 6
                    or abs(da[i + 2] - db[j + 2]) > 6):
                n += 1
                if x < STRIP:
                    strip += 1
                x1, y1, x2, y2 = min(x1, x), min(y1, y), max(x2, x), max(y2, y)
    part = 100.0 * n / (w * h)
    ok = part < 1.0
    box = "%d,%d-%d,%d" % (x1, y1, x2, y2) if n else "-"
    print("same %dx%d differ %d of %d (%.2f %%) box %s cutout-strip-differ %d result %s"
          % (w, h, n, w * h, part, box, strip, "ok" if ok else "wrong"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
