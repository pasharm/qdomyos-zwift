"""Test only (T-528): the top of the map on a frame of the modern GPX page in portrait.
The map is not in the uiautomator dump (a QtLocation item), so it is found on the frame: in the column
x, from y0 down, the first row that differs from the page colour (the pixel at x, y0) by more than 40 in
one channel and stays so for 40 rows - the empty list above it is the page colour.
usage: t528_map_top.py <frame.png> [x] [y0] [y1]   prints the y, or nothing when not found
"""
import sys
import zlib
import struct


def read_png(path):
    data = open(path, "rb").read()
    pos, chunks = 8, []
    width = height = color = 0
    while pos < len(data):
        n = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + n]
        if kind == b"IHDR":
            width, height, depth, color = struct.unpack(">IIBB", body[:10])
        elif kind == b"IDAT":
            chunks.append(body)
        pos += 12 + n
    bpp = {2: 3, 6: 4}[color]
    raw = zlib.decompress(b"".join(chunks))
    stride = width * bpp
    rows, prev = [], bytearray(stride)
    i = 0
    for _ in range(height):
        f = raw[i]
        line = bytearray(raw[i + 1:i + 1 + stride])
        i += 1 + stride
        for k in range(stride):
            a = line[k - bpp] if k >= bpp else 0
            b = prev[k]
            c = prev[k - bpp] if k >= bpp else 0
            if f == 1:
                line[k] = (line[k] + a) & 255
            elif f == 2:
                line[k] = (line[k] + b) & 255
            elif f == 3:
                line[k] = (line[k] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[k] = (line[k] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(line)
        prev = line
    return width, height, bpp, rows


def main():
    path = sys.argv[1]
    width, height, bpp, rows = read_png(path)
    x = int(sys.argv[2]) if len(sys.argv) > 2 else width // 2
    y0 = int(sys.argv[3]) if len(sys.argv) > 3 else 700
    y1 = int(sys.argv[4]) if len(sys.argv) > 4 else height - 300

    bg = rows[y0][x * bpp:x * bpp + 3]
    xs = range(100, width - 100, 4)

    def off(y):
        # the tiles are pale, close to the page: a row of the map has many pixels a little off the page
        # colour, a row of the page none (a line of text - few)
        line = rows[y]
        n = sum(1 for c in xs if any(abs(line[c * bpp + k] - bg[k]) > 10 for k in range(3)))
        return n > len(xs) * 0.3

    y = y0
    while y < y1 - 40:
        if off(y) and all(off(k) for k in range(y, y + 40)):
            print(y)
            return
        y += 1


main()
