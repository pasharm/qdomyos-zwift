#!/usr/bin/env python3
# Test only (T-441): print the top y of the largest WebView in a uiautomator dump - the chart
# under the tiles. Exit 1 when the dump has no WebView.
#   webtop.py dump.xml
import re
import sys
import xml.etree.ElementTree as ET

try:
    root = ET.parse(sys.argv[1]).getroot()
except (ET.ParseError, OSError, IndexError):
    sys.exit(1)

best = None
for node in root.iter("node"):
    if "WebView" not in (node.get("class") or ""):
        continue
    m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.get("bounds") or "")
    if not m:
        continue
    x1, y1, x2, y2 = map(int, m.groups())
    area = (x2 - x1) * (y2 - y1)
    if area > 0 and (best is None or area > best[0]):
        best = (area, y1)
if best is None:
    sys.exit(1)
print(best[1])
