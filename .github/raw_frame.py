"""Test only (T-518): a raw frame of `adb exec-out screencap` (no -p) - the dark pixels in a band of rows, and the
frame written as PNG for the evidence.

usage: python3 raw_frame.py <raw> <png> <y1> <y2>
prints: <dark pixels in rows y1..y2> <width> <height>

The raw frame is a header (12 bytes before API 28, 16 with the colour space after it) and RGBA rows; the header
length is what is left over the width x height x 4 bytes. "Dark" - R, G and B all below 0x50: the toast of QZ
is #222222 at 0.9 opacity (Toast.qml), the pages of the modern look are light; the label text of a button is
dark too, but a few thousand pixels, the toast a band across the screen.
"""
import struct
import sys
import zlib

raw_path, png_path, y1, y2 = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
data = open(raw_path, "rb").read()
w, h = struct.unpack("<II", data[:8])
head = len(data) - w * h * 4
if w <= 0 or h <= 0 or head not in (12, 16):
    print(f"0 {w} {h}")
    sys.exit(1)
px = memoryview(data)[head:]
row = w * 4

dark = 0
for y in range(max(0, y1), min(h, y2 + 1)):
    r = px[y * row:(y + 1) * row]
    for x in range(0, row, 4):
        if r[x] < 0x50 and r[x + 1] < 0x50 and r[x + 2] < 0x50:
            dark += 1


def chunk(kind, body):
    return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)


lines = b"".join(b"\x00" + bytes(px[y * row:(y + 1) * row]) for y in range(h))
with open(png_path, "wb") as f:
    f.write(b"\x89PNG\r\n\x1a\n")
    f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)))
    f.write(chunk(b"IDAT", zlib.compress(lines, 6)))
    f.write(chunk(b"IEND", b""))
print(f"{dark} {w} {h}")
