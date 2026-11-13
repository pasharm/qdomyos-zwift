"""Test only (T-528): where the restore progress stands against the list, by a uiautomator dump and the
frames of the burst.

usage:
  python3 t528_geom.py pass <dump.xml> <progress regex> <density> [<frame.png> ...]
  python3 t528_geom.py after <dump.xml> <x1> <x2> <y above> <density>

pass - the progress node P (the first visible node whose content-desc matches), the node right above it A
(the lowest node ending above P's top), the first node under P's top R (the topmost node starting at P's
top or lower: a row of the list, or the scroll bar of the list, which starts at the list top - the rows of
the classic lists have no node); A and R within P widened by 16 dp on each side - the scroll bar of a
classic list stands right of the progress margin, a box over the page (the question) is wider than the list
column. The nodes that cross P (not the ones holding it whole from above: a node that starts at P's top and
holds it is a row over the progress). On each frame (PNG of raw_frame.py: filter 0 on every row) the bar
bottom: the lowest row inside P that differs from the page under the bar (P's own bottom padding) at a quarter, half and three
quarters of its width - the text and the count are above the bar.
prints one line of key=value: p, a, r (x1,y1,x2,y2 and the name), gap_above (P top - A bottom), gap_node
(R top - P bottom), cross (nodes crossing P), bars (the bar bottom on each frame), bar (the most common),
gap_bar (R top - bar bottom - 1), dp (the density).

after - the first node starting at or below <y above> and within x1..x2 (widened by 16 dp); prints
"y1 name" or nothing.
"""
import re
import struct
import sys
import xml.etree.ElementTree as ET
import zlib
from collections import Counter


def bounds(n):
    s = n.get("bounds", "[0,0][0,0]").replace("][", ",").strip("[]").split(",")
    return [int(v) for v in s]


def label(n):
    t = n.get("content-desc") or n.get("text") or n.get("class", "").split(".")[-1]
    return t.replace(" ", "_")[:40]


def nodes(path):
    out = []
    for n in ET.parse(path).getroot().iter("node"):
        b = bounds(n)
        if b[2] > b[0] and b[3] > b[1]:
            out.append((b, n))
    return out


def across(b, x1, x2):
    return b[0] < x2 and b[2] > x1


def within(b, x1, x2):
    return b[0] >= x1 and b[2] <= x2


def holds(b, p):
    return b[0] <= p[0] and b[1] <= p[1] and b[2] >= p[2] and b[3] >= p[3]


def png_rows(path):
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    pos, w, h, idat = 8, 0, 0, b""
    while pos < len(data):
        ln = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + ln]
        if kind == b"IHDR":
            w, h, depth, colour = struct.unpack(">IIBB", body[:10])
            if depth != 8 or colour != 6:
                return None
        elif kind == b"IDAT":
            idat += body
        pos += 12 + ln
    raw = zlib.decompress(idat)
    stride = w * 4 + 1
    # only the frames of raw_frame.py: no filter on any row
    if any(raw[y * stride] != 0 for y in range(h)):
        return None
    return w, h, raw, stride


def px(frame, x, y):
    w, h, raw, stride = frame
    i = y * stride + 1 + x * 4
    return raw[i], raw[i + 1], raw[i + 2]


def bar_bottom(frame, p):
    w, h = frame[0], frame[1]
    if p[2] > w or p[3] > h:
        return None
    found = []
    for k in (1, 2, 3):
        x = p[0] + (p[2] - p[0]) * k // 4
        bg = px(frame, x, p[3] - 2)
        low = None
        for y in range(p[3] - 2, p[1] - 1, -1):
            c = px(frame, x, y)
            if sum(abs(c[i] - bg[i]) for i in range(3)) > 30:
                low = y
                break
        found.append(low)
    if None in found or max(found) - min(found) > 1:
        return None
    return max(found)


def main():
    mode = sys.argv[1]
    if mode == "after":
        path, x1, x2, ya = sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
        ext = round(16 * float(sys.argv[6]))
        x1, x2 = x1 - ext, x2 + ext
        best = None
        for b, n in nodes(path):
            if b[1] >= ya - 2 and within(b, x1, x2):
                if best is None or b[1] < best[0][1]:
                    best = (b, n)
        if best:
            print(best[0][1], label(best[1]))
        return
    path, rx, dp = sys.argv[2], re.compile(sys.argv[3]), float(sys.argv[4])
    frames = sys.argv[5:]
    all_nodes = nodes(path)
    p = None
    for b, n in all_nodes:
        if rx.search(n.get("content-desc") or "") and n.get("visible-to-user", "true") == "true":
            p = b
            break
    if p is None:
        print("p=none")
        return
    a = r = None
    cross = []
    ext = round(16 * dp)
    for b, n in all_nodes:
        # a container starts above P and holds it whole; a row of the list that starts at P's top and holds
        # it is a node over the progress, not a container
        if b == p or (holds(b, p) and b[1] < p[1]):
            continue
        if across(b, p[0], p[2]) and b[1] < p[3] and b[3] > p[1] + 2:
            cross.append(f"{label(n)}@{b[1]}-{b[3]}")
        if not within(b, p[0] - ext, p[2] + ext):
            continue
        if b[3] <= p[1] + 2 and (a is None or b[3] > a[0][3]):
            a = (b, n)
        if b[1] >= p[1] and (r is None or b[1] < r[0][1]):
            r = (b, n)
    out = [f"dp={dp:g}", "p=" + ",".join(map(str, p))]
    out.append("a=" + (",".join(map(str, a[0])) + ":" + label(a[1]) if a else "none"))
    out.append("r=" + (",".join(map(str, r[0])) + ":" + label(r[1]) if r else "none"))
    out.append(f"gap_above={p[1] - a[0][3]}" if a else "gap_above=?")
    out.append(f"gap_node={r[0][1] - p[3]}" if r else "gap_node=?")
    out.append("cross=" + (";".join(cross) if cross else "none"))
    bars = []
    for f in frames:
        try:
            fr = png_rows(f)
        except Exception:
            fr = None
        v = bar_bottom(fr, p) if fr else None
        bars.append("?" if v is None else str(v))
    out.append("bars=" + (",".join(bars) if bars else "none"))
    known = [int(v) for v in bars if v != "?"]
    if known:
        bar = Counter(known).most_common(1)[0][0]
        out.append(f"bar={bar}")
        out.append(f"gap_bar={r[0][1] - bar - 1}" if r else "gap_bar=?")
    else:
        out.append("bar=?")
        out.append("gap_bar=?")
    print(" ".join(out))


main()
