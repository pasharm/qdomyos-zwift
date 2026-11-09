"""Is the chart (a native WebView) drawn over the open drawer? (T-494)

usage: python3 drawercheck.py HOME.png OPEN.png X Y [SIZE]

Compares a SIZE x SIZE patch (default 60) centred on X, Y – a point inside the drawer and inside
the chart – between the home frame (drawer closed) and the frame with the drawer open. The drawer
and its dimming are QML: where they cover the chart the patch changes. An unchanged patch means
the WebView stayed on top of the drawer. Prints "chart over drawer: yes|no (mean diff N)".
Exit code 0 either way, 2 on bad input.
"""
import sys
import zlib
import struct


def read_png(path):
    """RGB rows of an 8-bit PNG (colour type 2 or 6), no external modules."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG: " + path)
    pos, idat, w, h, ctype = 8, b"", 0, 0, 0
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            w, h, depth, ctype = struct.unpack(">IIBB", body[:10])
            if depth != 8 or ctype not in (2, 6):
                raise ValueError("unsupported PNG: depth %d type %d" % (depth, ctype))
        elif kind == b"IDAT":
            idat += body
        pos += 12 + length
    bpp = 3 if ctype == 2 else 4
    raw = zlib.decompress(idat)
    stride = w * bpp
    rows, prev, i = [], bytearray(stride), 0
    for _ in range(h):
        ftype = raw[i]
        line = bytearray(raw[i + 1:i + 1 + stride])
        i += 1 + stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if ftype == 1:
                line[x] = (line[x] + a) & 255
            elif ftype == 2:
                line[x] = (line[x] + b) & 255
            elif ftype == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif ftype == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        rows.append(line)
        prev = line
    return w, h, bpp, rows


def patch(img, cx, cy, size):
    w, h, bpp, rows = img
    out = []
    for y in range(max(0, cy - size // 2), min(h, cy + size // 2)):
        for x in range(max(0, cx - size // 2), min(w, cx + size // 2)):
            out.extend(rows[y][x * bpp:x * bpp + 3])
    return out


def main(argv):
    if len(argv) < 5:
        print(__doc__)
        return 2
    size = int(argv[5]) if len(argv) > 5 else 60
    a = patch(read_png(argv[1]), int(argv[3]), int(argv[4]), size)
    b = patch(read_png(argv[2]), int(argv[3]), int(argv[4]), size)
    if not a or len(a) != len(b):
        print("!! bad patch")
        return 2
    diff = sum(abs(p - q) for p, q in zip(a, b)) / len(a)
    print("chart over drawer: %s (mean diff %.1f)" % ("yes" if diff < 8 else "no", diff))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
