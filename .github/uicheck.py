#!/usr/bin/env python3
# Test only (T-211): what follows a control in a uiautomator dump - the value field of a settings
# search result comes a few nodes after its title. Prints the labels (text or content-desc) of
# the N labelled nodes after the first one matching ANCHOR, one per line. Exit 1 when the anchor
# is not there.
#   uicheck.py dump.xml 'anchor regex' [N]
# The regex must match the whole label, case-insensitively.
import re
import sys
import xml.etree.ElementTree as ET

path, anchor = sys.argv[1], sys.argv[2]
count = int(sys.argv[3]) if len(sys.argv) > 3 else 6
try:
    root = ET.parse(path).getroot()
except (ET.ParseError, OSError):
    sys.exit(1)

rx = re.compile(anchor, re.I)
labels = []
for node in root.iter("node"):
    label = (node.get("text") or "").strip() or (node.get("content-desc") or "").strip()
    if label:
        labels.append(label)

for i, label in enumerate(labels):
    if rx.fullmatch(label):
        print(label)
        for following in labels[i + 1:i + 1 + count]:
            print(following)
        sys.exit(0)
sys.exit(1)
