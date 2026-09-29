#!/usr/bin/env python3
# Test only: find a control in a uiautomator dump by its text or accessible name and print
# the centre of its bounds as "x y". Exit 1 when nothing matches.
#   uitap.py dump.xml 'regex'
# The regex must match the whole text or content-desc, case-insensitively. Among several
# matches the topmost on the screen wins, so the result does not depend on the dump order.
import re
import sys
import xml.etree.ElementTree as ET

#   uitap.py dump.xml --package
# prints the package of the window on top instead (the first node of the dump).
path, pattern = sys.argv[1], sys.argv[2]
try:
    root = ET.parse(path).getroot()
except (ET.ParseError, OSError):
    sys.exit(1)

if pattern == "--package":
    first = next(root.iter("node"), None)
    if first is None or not first.get("package"):
        sys.exit(1)
    print(first.get("package"))
    sys.exit(0)

rx = re.compile(pattern, re.I)

best = None
for node in root.iter("node"):
    labels = [node.get("text") or "", node.get("content-desc") or ""]
    if not any(label and rx.fullmatch(label.strip()) for label in labels):
        continue
    m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.get("bounds") or "")
    if not m:
        continue
    x1, y1, x2, y2 = map(int, m.groups())
    if x2 <= x1 or y2 <= y1:
        continue
    cand = ((x1 + x2) // 2, (y1 + y2) // 2)
    if best is None or cand[1] < best[1]:
        best = cand

if best is None:
    sys.exit(1)
print(best[0], best[1])
