#!/usr/bin/env python3
# Test only (T-199): what a screen reader gets from every uiautomator dump of the run.
#   a11y.py dumps/ [package]
# For each dump: the controls of the app a user can act on (clickable, long-clickable or
# checkable) and how many of them have neither text nor accessible name (content-desc) -
# TalkBack reads those as "button" or skips them, and voice control cannot name them.
# The unnamed ones are listed with class and bounds; a summary line per dump at the end.
import os
import re
import sys
import xml.etree.ElementTree as ET

folder = sys.argv[1]
pkg = sys.argv[2] if len(sys.argv) > 2 else "org.cagnulen.qdomyoszwift"
summary = []
for name in sorted(os.listdir(folder)):
    if not name.endswith(".xml"):
        continue
    try:
        root = ET.parse(os.path.join(folder, name)).getroot()
    except ET.ParseError:
        summary.append(f"{name}: unreadable dump")
        continue
    nodes = [n for n in root.iter("node") if n.get("package") == pkg]
    if not nodes:
        summary.append(f"{name}: no nodes of the app (another window on top)")
        continue
    act = [n for n in nodes if "true" in (n.get("clickable"), n.get("long-clickable"), n.get("checkable"))]
    named = [n for n in nodes if (n.get("text") or "").strip() or (n.get("content-desc") or "").strip()]
    unnamed = [n for n in act if not ((n.get("text") or "").strip() or (n.get("content-desc") or "").strip())]
    print(f"== {name}: nodes {len(nodes)}, with a name {len(named)}, actionable {len(act)}, actionable without a name {len(unnamed)}")
    for n in unnamed[:40]:
        print(f"   ?? {n.get('class')} {n.get('bounds')} clickable={n.get('clickable')} checkable={n.get('checkable')} res={n.get('resource-id')}")
    # The names an actionable control is read by, to see what TalkBack says
    for n in act[:60]:
        label = (n.get("content-desc") or "").strip() or (n.get("text") or "").strip()
        if label:
            state = " checked" if n.get("checked") == "true" else ""
            print(f"   ok {n.get('class')} '{label[:70]}'{state}")
    summary.append(f"{name}: actionable {len(act)}, without a name {len(unnamed)}, named nodes {len(named)}/{len(nodes)}")
print("== summary")
for line in summary:
    print(line)
