#!/usr/bin/env python3
"""Test only (T-638): the colour of the strip beside the display cutout in landscape on API 28-30.

t638_strip.py <frame.raw> <dumpsys-window-displays.txt> <black|bar:RRGGBB>

There the window of QZ keeps clear of the cutout, and its background shows in the strip. Before the fix it is
the light gradient of Theme_Holo_Light (Qt 5.15 QtActivityDelegate.createSurface). After it: black in the
classic look ("black"), the page colour in the modern look, the same as the status bar above the strip
("bar:RRGGBB": the colour of the status bar at the top of the strip, and that is the page colour RRGGBB).
The cutout - the first "DisplayCutout{insets=Rect(l, t - r, b)" of `dumpsys window displays` (the safe insets
in px, the current rotation). The strip - the side with the inset, its middle column, rows from 30 % to 90 %
of the height (below the status bar, above a navigation bar at the bottom).
The raw frame of `adb exec-out screencap` (no -p): width, height, format (4 bytes each), on API 28+ a colour
space too, then RGBA rows - the header is what is left before width * height * 4 bytes (emu_frame.py).
Prints one line:
  strip left x X rows Y1-Y2 min R,G,B max R,G,B want W [page R,G,B] ref R,G,B result ok|wrong
Exit 0 - the strip is as wanted, 1 - it is not, 2 - not measured (no frame, no cutout on the left - the side
of the "tall" cutout at user_rotation 1).
"""
import struct
import sys


def cutout(text):
    key = "DisplayCutout{insets=Rect("
    i = text.find(key)
    if i < 0:
        return None
    rest = text[i + len(key):]
    j = rest.find(")")
    if j < 0:
        return None
    body = rest[:j].replace(" - ", ",").replace(" ", "")
    parts = body.split(",")
    if len(parts) != 4:
        return None
    try:
        return [int(p) for p in parts]
    except ValueError:
        return None


def read_raw(path):
    with open(path, "rb") as f:
        data = f.read()
    if len(data) < 12:
        return None
    w, h = struct.unpack("<II", data[:8])
    head = len(data) - w * h * 4
    if w <= 0 or h <= 0 or head < 12:
        return None
    return w, h, head, data


def pixel(frame, x, y):
    w, h, head, data = frame
    i = head + (y * w + x) * 4
    return data[i], data[i + 1], data[i + 2]


def want_of(arg):
    """'black' -> ('black', None); 'bar:RRGGBB' -> ('bar', (r, g, b)); else None."""
    if arg == "black":
        return "black", None
    if arg.startswith("bar:") and len(arg) == 10:
        try:
            v = int(arg[4:], 16)
        except ValueError:
            return None
        return "bar", ((v >> 16) & 255, (v >> 8) & 255, v & 255)
    return None


def main(argv):
    want = want_of(argv[2]) if len(argv) == 3 else None
    if want is None:
        print(__doc__)
        return 2
    frame = read_raw(argv[0])
    if frame is None:
        print("no frame")
        return 2
    with open(argv[1], encoding="utf-8", errors="replace") as f:
        cut = cutout(f.read())
    if cut is None:
        print("no cutout in dumpsys")
        return 2
    w, h = frame[0], frame[1]
    if w <= h:
        print("not landscape: %dx%d" % (w, h))
        return 2
    # the scenario turns the screen to user_rotation 1: the "tall" cutout on the left, the navigation bar on the
    # right; a cutout on the right is a stale rotation (there the navigation bar would be in the strip)
    if cut[0] > 0:
        side, x = "left", cut[0] // 2
    else:
        print("no cutout on the left: insets %d %d %d %d" % tuple(cut))
        return 2
    y1, y2 = h * 30 // 100, h * 90 // 100
    lo = [255, 255, 255]
    hi = [0, 0, 0]
    for y in range(y1, y2, 4):
        p = pixel(frame, x, y)
        for k in range(3):
            lo[k] = min(lo[k], p[k])
            hi[k] = max(hi[k], p[k])
    if want[0] == "black":
        ref = (0, 0, 0)
    else:
        ref = pixel(frame, x, 2)
    near = lambda a, b: all(abs(a[k] - b[k]) <= 6 for k in range(3))  # noqa: E731
    # one colour from top to bottom (no gradient) and that colour; 6 - the step of a 16-bit colour buffer.
    # "bar": the status bar is the page colour given (setSystemBars applied) and the strip is the same
    ok = all(hi[k] - lo[k] <= 6 for k in range(3)) and near(hi, ref) and near(lo, ref)
    page = ""
    if want[1] is not None:
        page = " page %d,%d,%d" % want[1]
        ok = ok and near(ref, want[1])
    print("strip %s x %d rows %d-%d min %d,%d,%d max %d,%d,%d want %s%s ref %d,%d,%d result %s"
          % (side, x, y1, y2, lo[0], lo[1], lo[2], hi[0], hi[1], hi[2], want[0], page, ref[0], ref[1], ref[2],
             "ok" if ok else "wrong"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
