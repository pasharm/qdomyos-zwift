#!/usr/bin/env python3
# Test only: the control in the same row as another one - "the OK of the App Language row" on
# a page with many OK buttons. Prints the centre "x y" of the control matching TARGET whose
# vertical centre is closest to that of the control matching ANCHOR (at most 150 px away).
#   uirow.py dump.xml 'anchor regex' 'target regex'
# Both regexes match the whole text or content-desc, case-insensitively. Exit 1 when not found.
import re
import sys
import xml.etree.ElementTree as ET

path, anchor, target = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    root = ET.parse(path).getroot()
except (ET.ParseError, OSError):
    sys.exit(1)


def centres(pattern):
    rx = re.compile(pattern, re.I)
    found = []
    for node in root.iter("node"):
        labels = [node.get("text") or "", node.get("content-desc") or ""]
        if not any(label and rx.fullmatch(label.strip()) for label in labels):
            continue
        m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.get("bounds") or "")
        if not m:
            continue
        x1, y1, x2, y2 = map(int, m.groups())
        if x2 > x1 and y2 > y1:
            found.append(((x1 + x2) // 2, (y1 + y2) // 2))
    return found


anchors = centres(anchor)
if not anchors:
    sys.exit(1)
ay = anchors[0][1]
best = None
for x, y in centres(target):
    if abs(y - ay) <= 150 and (best is None or abs(y - ay) < abs(best[1] - ay)):
        best = (x, y)
if best is None:
    sys.exit(1)
print(best[0], best[1])
