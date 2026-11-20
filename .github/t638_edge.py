#!/usr/bin/env python3
"""Test only (T-638): on API 31+ the edge of the screen Qt's surface leaves uncovered - the last pixel row and
column of the frame (run 44815452358: master 255 / 233-243, the light gradient of Theme_Holo_Light; the branch of
then 0,0,0) - must be the window background the fix sets.

t638_edge.py <frame.raw> <black|bar:RRGGBB>

Read: the last row from 10 % to 90 % of the width, the last column from 10 % to 90 % of the height (the corners
left out). A pixel is right if each channel is within 6 of the wanted colour (the step of a 16-bit colour buffer).
Prints one line:
  edge row R,G,B..R,G,B (wrong N of M) column R,G,B..R,G,B (wrong N of M) want R,G,B result ok|wrong
Exit 0 - ok, 1 - wrong, 2 - not measured (no frame, a bad colour).
"""
import struct
import sys

TOL = 6


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


def parse_want(text):
    if text == "black":
        return (0, 0, 0)
    if not text.startswith("bar:") or len(text) != 10:
        return None
    try:
        v = int(text[4:], 16)
    except ValueError:
        return None
    return ((v >> 16) & 255, (v >> 8) & 255, v & 255)


def measure(pixels, want):
    wrong = sum(1 for p in pixels if max(abs(p[i] - want[i]) for i in range(3)) > TOL)
    lo = min(pixels)
    hi = max(pixels)
    return "%d,%d,%d..%d,%d,%d (wrong %d of %d)" % (lo + hi + (wrong, len(pixels))), wrong


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 2
    want = parse_want(argv[1])
    frame = read_raw(argv[0])
    if want is None or frame is None:
        print("not measured: %s" % ("bad colour " + argv[1] if want is None else "no frame"))
        return 2
    w, h, head, data = frame

    def px(x, y):
        i = head + (y * w + x) * 4
        return (data[i], data[i + 1], data[i + 2])

    row = [px(x, h - 1) for x in range(w // 10, w * 9 // 10)]
    col = [px(w - 1, y) for y in range(h // 10, h * 9 // 10)]
    rs, rn = measure(row, want)
    cs, cn = measure(col, want)
    ok = rn == 0 and cn == 0
    print("edge row %s column %s want %d,%d,%d result %s" % ((rs, cs) + want + ("ok" if ok else "wrong",)))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
