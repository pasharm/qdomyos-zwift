#!/usr/bin/env python3
# Test only (T-255): the point near the right edge of the control matching a label - the switch
# indicator of IndicatorOnlySwitch, which toggles only when tapped there (mouse.x > width -
# indicator.width), not in the middle of its row.
#   uiright.py dump.xml 'label regex'   -> "x y"; exit 1 when not found
import re
import sys
import xml.etree.ElementTree as ET

try:
    root = ET.parse(sys.argv[1]).getroot()
except (ET.ParseError, OSError):
    sys.exit(1)
rx = re.compile(sys.argv[2], re.I)
for node in root.iter("node"):
    labels = [node.get("text") or "", node.get("content-desc") or ""]
    if not any(label and rx.fullmatch(label.strip()) for label in labels):
        continue
    m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.get("bounds") or "")
    if not m:
        continue
    x1, y1, x2, y2 = map(int, m.groups())
    if x2 > x1 and y2 > y1:
        print(x2 - 60, (y1 + y2) // 2)
        sys.exit(0)
sys.exit(1)
