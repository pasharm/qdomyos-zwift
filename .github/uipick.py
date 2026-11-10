#!/usr/bin/env python3
# Test only: a node of a uiautomator dump on the screen whose text or name matches the whole
# regex (case-insensitive), the topmost, printed as "x y checkable checked x1 y1 x2 y2".
#   uipick.py dump.xml 'regex' [--not-edit] [--checkable] [--below Y]
# --not-edit skips text fields (the search field holds the typed text), --checkable keeps only
# switches and check boxes, --below Y keeps nodes whose top is below Y. Exit 1 when none.
import re
import sys
import xml.etree.ElementTree as ET

path, pattern = sys.argv[1], sys.argv[2]
opts = sys.argv[3:]
below = int(opts[opts.index('--below') + 1]) if '--below' in opts else -1
try:
    root = ET.parse(path).getroot()
except (ET.ParseError, OSError):
    sys.exit(1)
rx = re.compile(pattern, re.I)
best = None
for n in root.iter('node'):
    labels = [n.get('text') or '', n.get('content-desc') or '']
    if not any(lab and rx.fullmatch(lab.strip()) for lab in labels):
        continue
    if '--not-edit' in opts and 'EditText' in (n.get('class') or ''):
        continue
    if '--checkable' in opts and n.get('checkable') != 'true':
        continue
    m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", n.get('bounds') or '')
    if not m:
        continue
    x1, y1, x2, y2 = map(int, m.groups())
    if x2 <= x1 or y2 <= y1 or y1 <= below:
        continue
    if best is None or y1 < best[5]:
        best = ((x1 + x2) // 2, (y1 + y2) // 2, n.get('checkable'), n.get('checked'), x1, y1, x2, y2)
if best is None:
    sys.exit(1)
print(*best)
