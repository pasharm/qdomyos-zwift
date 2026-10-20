#!/usr/bin/env python3
"""Test only (T-255): the tiles of the home page in a uiautomator dump.

Prints one line: how many tiles, the size of the first one in px and how many are in the first
row. A tile is a node whose accessible name is "<name>: <value>" (Home.qml, Accessible.name of
the delegate).
"""
import sys
import xml.etree.ElementTree as ET


def bounds(text):
    # "[x1,y1][x2,y2]"
    parts = text.replace("][", ",").strip("[]").split(",")
    return [int(p) for p in parts]


def main():
    tiles = []
    for node in ET.parse(sys.argv[1]).getroot().iter("node"):
        desc = node.get("content-desc") or ""
        if ": " not in desc or node.get("package") != "org.cagnulen.qdomyoszwift":
            continue
        x1, y1, x2, y2 = bounds(node.get("bounds") or "[0,0][0,0]")
        if x2 - x1 < 50 or y2 - y1 < 50:
            continue
        tiles.append((y1, x1, x2 - x1, y2 - y1, desc))
    if not tiles:
        print("tiles: none")
        return
    tiles.sort()
    first = tiles[0]
    per_row = sum(1 for t in tiles if t[0] == first[0])
    print("tiles: %d, first %dx%d px, %d in the first row, first: %s" % (len(tiles), first[2], first[3], per_row, first[4]))


main()
