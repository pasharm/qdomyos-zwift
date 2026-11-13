"""Test only (T-528): the enabled attribute of the nodes of a uiautomator dump whose text or content-desc is
exactly the given name.

usage: python3 t528_enabled.py <dump.xml> <name>
prints one word per matching node, in the order of the dump: "true" or "false"; nothing - no such node.
"""
import sys
import xml.etree.ElementTree as ET

path, name = sys.argv[1], sys.argv[2]
try:
    root = ET.parse(path).getroot()
except Exception:
    sys.exit(1)
found = []
for node in root.iter("node"):
    if node.get("text") == name or node.get("content-desc") == name:
        found.append(node.get("enabled", "?"))
print(" ".join(found))
