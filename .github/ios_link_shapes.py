"""T-046, test only: link the QtQuick.Shapes plugin that UiIcon.qml of the modern look needs.

usage: ios_link_shapes.py <project.pbxproj>
After every "-L$(QZ_QT_ROOT)/plugins/platforms" of OTHER_LDFLAGS (the app target, Debug and
Release) the Shapes plugin directory, the plugin and its Qt library are added.
"""
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    lines = f.read().split("\n")

anchor = '"-L$(QZ_QT_ROOT)/plugins/platforms",'
# the Debug configuration links the _debug libraries (QT_LIBRARY_SUFFIX), as the other Qt libraries of the project
added = ['"-L$(QZ_QT_ROOT)/qml/QtQuick/Shapes",', '"-lqmlshapesplugin$(QT_LIBRARY_SUFFIX)",',
         '"-lQt5QuickShapes$(QT_LIBRARY_SUFFIX)",']
out = []
count = 0
for line in lines:
    out.append(line)
    if line.strip() == anchor:
        indent = line[:len(line) - len(line.lstrip())]
        out.extend(indent + a for a in added)
        count += 1

print(f"Shapes linked in {count} OTHER_LDFLAGS")
if count == 0:
    sys.exit("no anchor " + anchor)
with open(path, "w", encoding="utf-8") as f:
    f.write("\n".join(out))
