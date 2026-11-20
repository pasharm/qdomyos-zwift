#!/usr/bin/env python3
# Test only (T-643): how many "OK" buttons a dump has in the row of a label - the OK of a settings row
# is right of its label and centred on it (Layout.alignment: Qt.AlignRight | Qt.AlignVCenter).
#   t643_row.py dump.xml 'label regex'  -> prints the count; exit 2 - no such label, 3 - two labels
# The regex matches the whole text or content-desc, case-insensitively, "." takes a line break
# (as uifind.py). A button with visible: false is not in the dump at all.
import re
import sys
import xml.etree.ElementTree as ET

FLAGS = re.I | re.S


def bounds(n):
    b = n.get("bounds", "")
    nums = [int(x) for x in re.findall(r"-?\d+", b)]
    return nums if len(nums) == 4 else None


def name(n):
    return n.get("text") or n.get("content-desc") or ""


def main():
    dump, rx = sys.argv[1], sys.argv[2]
    nodes = [n for n in ET.parse(dump).iter("node") if bounds(n)]
    labels = [n for n in nodes if re.fullmatch(rx, name(n), FLAGS)]
    if not labels:
        print(0)
        return 2
    if len(labels) > 1:
        print(len(labels))
        return 3
    x1, y1, x2, y2 = bounds(labels[0])
    n = 0
    for o in nodes:
        if name(o) != "OK":
            continue
        ox1, oy1, ox2, oy2 = bounds(o)
        cy = (oy1 + oy2) // 2
        if y1 - 20 <= cy <= y2 + 20 and ox1 >= x1:
            n += 1
    print(n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
