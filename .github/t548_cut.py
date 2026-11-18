#!/usr/bin/env python3
"""Test only (T-548): does the content of QZ go under the display cutout in landscape?

t548_cut.py <dump.xml> <dumpsys-window-displays.txt> [--pkg PKG]

The cutout - the first "DisplayCutout{insets=Rect(l, t - r, b)" of `dumpsys window displays` (the display
now, in the current rotation; the safe insets in px). The window - the bounds of the first node of the app
in the dump; the content - the nodes of the app with a text or a name and a non-empty area.
Prints one line:
  cut L T R B window X1 Y1 X2 Y2 content X1 X2 under_left N under_right N landscape 0|1 nodes N
under_left - how far the leftmost content goes into the left safe inset (0 - not under it), the same on the
right. Exit 2 - the cutout or the dump not read.
"""
import sys
import xml.etree.ElementTree as ET


def bounds(s):
    # "[x1,y1][x2,y2]" without regular expressions (upstream rule 5)
    s = s.replace("][", ",").replace("[", "").replace("]", "")
    parts = s.split(",")
    if len(parts) != 4:
        return None
    try:
        return [int(p) for p in parts]
    except ValueError:
        return None


def cutout(text):
    key = "DisplayCutout{insets=Rect("
    i = text.find(key)
    if i < 0:
        return None
    rest = text[i + len(key):]
    j = rest.find(")")
    if j < 0:
        return None
    # "l, t - r, b"
    body = rest[:j].replace(" - ", ",").replace(" ", "")
    parts = body.split(",")
    if len(parts) != 4:
        return None
    try:
        return [int(p) for p in parts]
    except ValueError:
        return None


def main(argv):
    pkg = "org.cagnulen.qdomyoszwift"
    args = []
    k = 0
    while k < len(argv):
        if argv[k] == "--pkg" and k + 1 < len(argv):
            pkg = argv[k + 1]
            k += 2
            continue
        args.append(argv[k])
        k += 1
    if len(args) != 2:
        print(__doc__)
        return 2
    with open(args[1], encoding="utf-8", errors="replace") as f:
        cut = cutout(f.read())
    if cut is None:
        print("no cutout in dumpsys")
        return 2
    try:
        root = ET.parse(args[0]).getroot()
    except (ET.ParseError, OSError) as e:
        print("no dump: %s" % e)
        return 2
    window = None
    left = None
    right = None
    count = 0
    for node in root.iter("node"):
        if node.get("package") != pkg:
            continue
        b = bounds(node.get("bounds", ""))
        if b is None:
            continue
        if window is None:
            window = b
        if b[2] <= b[0] or b[3] <= b[1]:
            continue
        if not (node.get("text") or node.get("content-desc")):
            continue
        count += 1
        left = b[0] if left is None else min(left, b[0])
        right = b[2] if right is None else max(right, b[2])
    if window is None or left is None:
        print("cut %d %d %d %d no app nodes" % tuple(cut))
        return 2
    # the screen width in the current rotation: "cur=2560x1440" of dumpsys (not the window - with the
    # cutout on the right a window kept out of it ends short of the screen edge)
    screen_w = None
    with open(args[1], encoding="utf-8", errors="replace") as f:
        text = f.read()
    i = text.find(" cur=")
    if i < 0 and text.startswith("cur="):
        i = -1
        text = " " + text
        i = 0
    if i >= 0:
        w = text[i + 5:].split("x", 1)[0]
        if w.isdigit():
            screen_w = int(w)
    if screen_w is None:
        print("cut %d %d %d %d no screen size (cur=) in dumpsys" % tuple(cut))
        return 2
    under_left = max(0, cut[0] - left) if cut[0] > 0 else 0
    under_right = max(0, right - (screen_w - cut[2])) if cut[2] > 0 else 0
    landscape = 1 if (window[2] - window[0]) > (window[3] - window[1]) else 0
    print("cut %d %d %d %d window %d %d %d %d content %d %d under_left %d under_right %d landscape %d nodes %d"
          % (cut[0], cut[1], cut[2], cut[3], window[0], window[1], window[2], window[3], left, right,
             under_left, under_right, landscape, count))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
