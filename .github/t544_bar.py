#!/usr/bin/env python3
# Test only (T-544): how much of the status bar has the colour of a point of the page below it.
#   t544_bar.py <raw frame> <ref x> <ref y> [x0 x1] [--bar N] [--ref-frame <raw>]
# --ref-frame: the reference point is taken from that frame (the home page before a scroll)
# The raw frame of `adb exec-out screencap` (no -p): width, height, format (4 bytes each), on API 28+ a
# colour space too, then RGBA rows - the header is what is left before width*height*4 bytes. Rows 4..bar-8
# (the bar is 84 px on the CI Nexus 6), columns x0..x1 (the whole width by default). Prints
# "share S ref R G B bar R G B": S - the part of those pixels within 8 of the colour at (ref x, ref y), then
# the mean colour of the bar. Exit 0, 2 when the frame cannot be read.
import struct
import sys


def main(argv):
    args = [a for a in argv[1:]]
    bar = 84
    if "--bar" in args:
        i = args.index("--bar")
        bar = int(args[i + 1])
        del args[i:i + 2]
    ref_frame = None
    if "--ref-frame" in args:
        i = args.index("--ref-frame")
        ref_frame = args[i + 1]
        del args[i:i + 2]
    path, rx, ry = args[0], int(args[1]), int(args[2])
    try:
        data = open(path, "rb").read()
        w, h = struct.unpack("<II", data[:8])
        head = len(data) - w * h * 4
        if w <= 0 or h <= 0 or head < 12:
            raise ValueError("size")
    except Exception as e:
        print("cannot read %s: %s" % (path, e))
        return 2
    x0 = int(args[3]) if len(args) > 3 else 0
    x1 = int(args[4]) if len(args) > 4 else w
    x0, x1 = max(0, x0), min(w, x1)

    def px(x, y):
        o = head + (y * w + x) * 4
        return data[o], data[o + 1], data[o + 2]

    ref = px(rx, ry)
    if ref_frame:
        try:
            rd = open(ref_frame, "rb").read()
            rw, rh = struct.unpack("<II", rd[:8])
            o = len(rd) - rw * rh * 4 + (ry * rw + rx) * 4
            ref = rd[o], rd[o + 1], rd[o + 2]
        except Exception as e:
            print("cannot read %s: %s" % (ref_frame, e))
            return 2
    near = total = 0
    sums = [0, 0, 0]
    for y in range(4, max(5, bar - 8)):
        for x in range(x0, x1, 2):
            c = px(x, y)
            total += 1
            for k in range(3):
                sums[k] += c[k]
            if abs(c[0] - ref[0]) <= 8 and abs(c[1] - ref[1]) <= 8 and abs(c[2] - ref[2]) <= 8:
                near += 1
    mean = [s // max(1, total) for s in sums]
    print("share %.2f ref %d %d %d bar %d %d %d" % (near / max(1, total), ref[0], ref[1], ref[2],
                                                    mean[0], mean[1], mean[2]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
