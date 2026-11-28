#!/usr/bin/env python3
# Test only (T-716).
#
#   t716_field.py <dump.xml>
#       the search field of the settings page: the widest node named "Search settings" (the classic look has
#       the header button of that name too, the modern one only the field). The focus - the focused flag of
#       that node only: a nameless node of the same bounds stays focused after the field lost the focus (run
#       46105242668). Prints "focused=<true|false> x y" or "none"; exit 0 / 1.
#
#   t716_field.py <dump.xml> --gap X YLO YHI
#       empty space of the page under x = X between YLO and YHI: the middle of the tallest run of y where no
#       clickable or checkable node is (a card of the results, a switch, a button - they take a touch; a
#       label does not). The gaps between the cards of the results are 14 px (a-1-changed.xml: 909..924).
#       Prints "y height" or "none"; exit 0 / 1.
import sys
import xml.etree.ElementTree as ET

MIN_GAP = 6


def bounds(node):
    parts = (node.get("bounds") or "").replace("][", ",").strip("[]").split(",")
    if len(parts) != 4:
        return None
    try:
        b = tuple(int(p) for p in parts)
    except ValueError:
        return None
    return b if b[2] > b[0] and b[3] > b[1] else None


def field(nodes):
    # the field - the widest of them: the header button is a square, and the modern look has no header
    # button while the search bar is on the page (main.qml: shown = !modern || searchBarScrolledAway; T-647
    # run 46091320164, hg-1-card.xml - one node [56,280][1032,447])
    named = [(bounds(n), n) for n in nodes if (n.get("content-desc") or n.get("text") or "") == "Search settings"]
    named = [(b, n) for b, n in named if b is not None]
    if not named:
        return None
    f, node = max(named, key=lambda bn: bn[0][2] - bn[0][0])
    # the focus - of the field node itself: the nameless android.view.View of the same bounds (the input
    # view of Qt) stays focused=true after the field lost it, on master as well (run 46105242668, htm-2-tapped
    # and btm-2-tapped; the 6T the same, T-716 journal 2026-11-28)
    focused = node.get("focused") == "true"
    return "focused=%s %d %d" % ("true" if focused else "false", (f[0] + f[2]) // 2, (f[1] + f[3]) // 2)


def gap(nodes, x, ylo, yhi):
    taken = []
    for n in nodes:
        if n.get("clickable") != "true" and n.get("checkable") != "true":
            continue
        b = bounds(n)
        if b and b[0] <= x < b[2]:
            taken.append(b)
    best = None
    start = None
    for y in range(ylo, yhi + 2):
        free = y <= yhi and not any(b[1] <= y < b[3] for b in taken)
        if free and start is None:
            start = y
        if not free and start is not None:
            h = y - start
            if h >= MIN_GAP and (best is None or h > best[1]):
                best = (start + h // 2, h)
            start = None
    return None if best is None else "%d %d" % best


def main(argv):
    nodes = list(ET.parse(argv[1]).iter("node"))
    if len(argv) == 6 and argv[2] == "--gap":
        out = gap(nodes, int(argv[3]), int(argv[4]), int(argv[5]))
    else:
        out = field(nodes)
    print(out or "none")
    return 0 if out else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
