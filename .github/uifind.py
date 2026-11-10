#!/usr/bin/env python3
# emu-lib: tools/emu/uifind.py sha b421c95fdf4a - edit there, then tools/emu/sync.py (T-505)
# Test only (T-505): find a control of a uiautomator dump the way the user sees it - only the part
# of it that is on the screen, not under the app header, not under a popup or the side menu.
# One file for every emu branch, delivered by tools/emu/sync.py as .github/uifind.py.
#
#   uifind.py dump.xml 'regex' [--checkable] [--not-edit] [--below Y] [--right N] [--first]
#                              [--any] [--min PX] [--name]
#       prints "x y checkable checked x1 y1 x2 y2": the point to tap and the visible part
#       (--name: its exact name instead - for the ACTION_CLICK of A11yDriver)
#       exit 0 - one control; 1 - no node with that name in the dump; 2 - two or more different
#       controls on the screen (listed on stderr; --first takes the topmost); 3 - the control is
#       in the dump but not on the screen (stderr: "above", "below", "covered by <name>" or "only N px
#       on the screen, the rest above|below|beside")
#   uifind.py dump.xml --count 'regex' [--any]   number of controls (on the screen; --any - all)
#   uifind.py dump.xml --band                    "top bottom" of the page area between the app
#                                                header and the navigation bar
#   uifind.py dump.xml --package                 package of the window on top
#
# The regex must match the whole text or content-desc, case-insensitively.
# --checkable keeps switches and check boxes, --not-edit skips text fields (the search field
# holds the typed text), --below Y keeps controls whose visible top is below Y, --right N taps
# N px in from the right end (the indicator of a switch row that only turns by its indicator),
# --any takes hidden controls too (their real bounds, as the old uitap.py), --min PX - the
# smallest visible height and width that is still tapped (default 40, about 11 dp on Nexus 6).
#
# Why (notes/emu-lib-2026-11-10.md, T-505): Qt gives uiautomator the real place of a QML item
# even when it is scrolled under the header or below the page (42819262998: Template Settings
# at y 48 under the header, the tap went to the header; T-502: y 8; T-403: y 2545 in the gesture
# bar), and the tree order is not the drawing order (the heart rate card of T-473 comes before
# the page in the tree but is drawn over it). What the dumps show (2850 dumps of notes/emu):
# the QML root View has the header as its first child, the page as the child with the most
# nodes (its bounds are the band between the header and the navigation bar), and everything
# else - side menu, popups, cards, the round help button - drawn over both; which of those is
# over which the dump does not tell (the card of T-473 hides the help button that comes after it).
# Two controls of the same name on the screen are an error, not "take the topmost": the result
# of a tap must not depend on which one the dump lists first (--first only when meant).
import re
import sys
import xml.etree.ElementTree as ET

QT_NODE = "android.view.View$VirtualChild"
MIN_VISIBLE = 40
MERGE_GAP = 60  # px: over layers closer than this are one panel (card title and its buttons: 29 px)


def parse_bounds(s):
    # "[x1,y1][x2,y2]" -> (x1, y1, x2, y2) or None
    parts = (s or "").replace("][", ",").strip("[]").split(",")
    if len(parts) != 4:
        return None
    try:
        return tuple(int(p) for p in parts)
    except ValueError:
        return None


def empty(r):
    return r is None or r[2] <= r[0] or r[3] <= r[1]


def meet(a, b):
    r = (max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3]))
    return None if empty(r) else r


def inside(inner, outer):
    return outer[0] <= inner[0] and outer[1] <= inner[1] and inner[2] <= outer[2] and inner[3] <= outer[3]


def label_of(n):
    return (n.get("content-desc") or "").strip() or (n.get("text") or "").strip()


class Screen:
    """A parsed dump: nodes with parents, the QML layers and the visible part of every node."""

    def __init__(self, root):
        self.root = root
        self.parent = {}
        self.nodes = []
        for n in root.iter("node"):
            self.nodes.append(n)
            for c in n:
                if c.tag == "node":
                    self.parent[c] = n
        first = self.nodes[0] if self.nodes else None
        self.screen = parse_bounds(first.get("bounds")) if first is not None else None
        self.layer = {}       # top-level QML child -> "header" | "page" | "over"
        self.cover = {}       # top-level QML child -> the rect it paints over
        self.top_of = {}      # node -> its top-level QML child
        self.page = None
        self.trusted = {}
        self._layers()

    def _descendant_rects(self, n):
        out = []
        for d in n.iter("node"):
            if d is n:
                continue
            r = parse_bounds(d.get("bounds"))
            if not empty(r):
                out.append(r)
        return out

    def _is_trusted(self, n):
        # Qt gives some containers a place that none of their items even touches (the header:
        # [0,0][1438,83] with its buttons at y 84..251): such a container does not clip.
        if n in self.trusted:
            return self.trusted[n]
        r = parse_bounds(n.get("bounds"))
        ok = False
        if not empty(r):
            kids = self._descendant_rects(n)
            ok = not kids or any(meet(k, r) is not None for k in kids)
        self.trusted[n] = ok
        return ok

    def _page_index(self, tops):
        # The page: the largest top-level child as wide as the screen (the side menu is narrower,
        # and it has more nodes than a short page - so not by the count of nodes); the first of
        # equal ones (API 30: header and page both [0,84][1438,2390]). Not the header (index 0)
        # unless it is the only child. No full-width child - the one with the most nodes.
        if len(tops) == 1:
            return 0
        width = (self.screen[2] - self.screen[0]) if self.screen else 0
        best = None
        for i, t in enumerate(tops[1:], 1):
            r = parse_bounds(t.get("bounds"))
            if empty(r) or (width and r[2] - r[0] < 0.9 * width):
                continue
            if best is None or _area(r) > best[0]:
                best = (_area(r), i)
        if best is not None:
            return best[1]
        counts = [sum(1 for _ in t.iter("node")) for t in tops]
        return max(range(len(tops)), key=lambda i: (counts[i], -i))

    def _layers(self):
        for v in self.nodes:
            if v.get("class") != "android.view.View":
                continue
            tops = [c for c in v if c.tag == "node" and c.get("class") == QT_NODE]
            if not tops:
                continue
            page = self._page_index(tops)
            for i, t in enumerate(tops):
                if i == page:
                    kind = "page"
                    self.page = t
                elif i == 0:
                    kind = "header"
                else:
                    kind = "over"
                self.layer[t] = kind
                r = parse_bounds(t.get("bounds"))
                if self._is_trusted(t) and not empty(r):
                    self.cover[t] = r
                else:
                    rs = self._descendant_rects(t)
                    if rs:
                        self.cover[t] = (min(x[0] for x in rs), min(x[1] for x in rs),
                                         max(x[2] for x in rs), max(x[3] for x in rs))
                for d in t.iter("node"):
                    self.top_of[d] = t
            break  # one QML window per dump
        self.over_areas = self._merge([(r, self._name_in(t) or t.get("bounds"))
                                       for t, r in self.cover.items() if self.layer.get(t) == "over"])

    @staticmethod
    def _merge(areas):
        # Over layers close to each other are one panel: the heart rate card of T-473 is in the tree
        # only as its title and three buttons, each a top-level child, its background is not a node -
        # cut one by one, the page tile between the buttons would count as visible
        areas = list(areas)
        changed = True
        while changed:
            changed = False
            for i in range(len(areas)):
                for j in range(i + 1, len(areas)):
                    a, b = areas[i][0], areas[j][0]
                    grown = (a[0] - MERGE_GAP, a[1] - MERGE_GAP, a[2] + MERGE_GAP, a[3] + MERGE_GAP)
                    if meet(grown, b) is not None:
                        box = (min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3]))
                        areas[i] = (box, areas[i][1])
                        del areas[j]
                        changed = True
                        break
                if changed:
                    break
        return areas

    def visible(self, n):
        """(rect, why): the on-screen part of the node, or None and "above"/"below"/"covered by …"."""
        raw = parse_bounds(n.get("bounds"))
        if empty(raw):
            return None, "no place"
        vis = raw if self.screen is None else meet(raw, self.screen)
        top = self.top_of.get(n)
        a = self.parent.get(n)
        while vis is not None and a is not None:
            if top is not None and a not in self.top_of and a is not top:
                break  # above the QML layers: Android containers, all full screen
            if a is top and self.layer.get(top) == "header":
                pass  # the header container is never a clip (its place is wrong, see above)
            elif self._is_trusted(a):
                vis = meet(vis, parse_bounds(a.get("bounds")))
            if a is top:
                break
            a = self.parent.get(a)
        if vis is None:
            band = self.band()
            mid = (raw[1] + raw[3]) // 2
            if band and mid < band[0]:
                return None, "above"
            return None, "below" if band and mid >= band[1] else "off the screen"
        # drawn over: every over layer covers the page and the header. Over layers do not cut each
        # other - their drawing order is not in the dump (T-473: the round help button comes after
        # the heart rate card in the tree, but the card hides it on the frame)
        if self.layer.get(top) == "over":
            return vis, ""
        for r, name in self.over_areas:
            vis = self._cut(vis, r)
            if vis is None:
                return None, "covered by '%s'" % name
        return vis, ""

    @staticmethod
    def _cut(vis, r):
        # the largest part of vis left beside r (r goes across: above or below; r at a side: left
        # or right); None when r takes all of it
        if meet(vis, r) is None:
            return vis
        parts = [
            (vis[0], vis[1], vis[2], min(vis[3], r[1])),
            (vis[0], max(vis[1], r[3]), vis[2], vis[3]),
            (vis[0], vis[1], min(vis[2], r[0]), vis[3]),
            (max(vis[0], r[2]), vis[1], vis[2], vis[3]),
        ]
        parts = [p for p in parts if not empty(p)]
        if not parts:
            return None
        return max(parts, key=lambda p: (p[2] - p[0]) * (p[3] - p[1]))

    def _name_in(self, t):
        for d in t.iter("node"):
            if label_of(d):
                return label_of(d)[:40]
        return ""

    def band(self):
        """(top, bottom) of the page area: the page layer clipped by the screen, else the screen."""
        if self.page is not None:
            r = parse_bounds(self.page.get("bounds"))
            if not empty(r):
                r = meet(r, self.screen) if self.screen else r
                if r:
                    return r[1], r[3]
        if self.screen:
            return self.screen[1], self.screen[3]
        return None


def load(path):
    try:
        return Screen(ET.parse(path).getroot())
    except (ET.ParseError, OSError):
        return None


def matches(scr, pattern, checkable=False, not_edit=False):
    rx = re.compile(pattern, re.I)
    out = []
    for n in scr.nodes:
        labels = [(n.get("text") or "").strip(), (n.get("content-desc") or "").strip()]
        if not any(lab and rx.fullmatch(lab) for lab in labels):
            continue
        if not_edit and "EditText" in (n.get("class") or ""):
            continue
        if checkable and n.get("checkable") != "true":
            continue
        if empty(parse_bounds(n.get("bounds"))):
            continue
        out.append(n)
    return out


def controls(scr, nodes):
    """Group nodes of one control: a node inside another matched node (a label inside its row,
    the same name on the item and its text) is the same control. Returns lists, outer node first."""
    groups = []
    for n in sorted(nodes, key=lambda n: _area(parse_bounds(n.get("bounds"))), reverse=True):
        r = parse_bounds(n.get("bounds"))
        for g in groups:
            if inside(r, parse_bounds(g[0].get("bounds"))):
                g.append(n)
                break
        else:
            groups.append([n])
    return groups


def _area(r):
    return (r[2] - r[0]) * (r[3] - r[1])


class Found:
    def __init__(self, group, vis, why):
        self.group = group
        self.vis = vis
        self.why = why
        check = next((n for n in group if n.get("checkable") == "true"), group[0])
        self.checkable = check.get("checkable") or "false"
        self.checked = check.get("checked") or "false"
        self.name = label_of(group[0])
        self.raw = parse_bounds(group[0].get("bounds"))

    def point(self, right=None):
        r = self.vis or self.raw
        x = (r[0] + r[2]) // 2 if right is None else max(r[0] + 1, r[2] - right)
        return x, (r[1] + r[3]) // 2

    def line(self, right=None):
        r = self.vis or self.raw
        return "%d %d %s %s %d %d %d %d" % (self.point(right) + (self.checkable, self.checked) + r)


def find(scr, pattern, checkable=False, not_edit=False, below=None, any_place=False, min_px=MIN_VISIBLE):
    """(on_screen, hidden): Found controls on the screen (topmost first) and the hidden ones."""
    on, off = [], []
    for g in controls(scr, matches(scr, pattern, checkable, not_edit)):
        vis, why = None, ""
        for n in g:  # the outer node, else a part of it (a row cut by the header keeps its label)
            vis, why = scr.visible(n)
            if vis is not None:
                break
        if vis is not None and (vis[2] - vis[0] < min_px or vis[3] - vis[1] < min_px):
            raw = parse_bounds(g[0].get("bounds"))
            rest = "above" if raw[1] < vis[1] else "below" if raw[3] > vis[3] else "beside"
            vis, why = None, "only %d px on the screen, the rest %s" % (
                min(vis[2] - vis[0], vis[3] - vis[1]), rest)
        f = Found(g, vis, why)
        if any_place:
            f.vis = None
            on.append(f)
        elif vis is None:
            off.append(f)
        else:
            on.append(f)
    if below is not None:
        on = [f for f in on if (f.vis or f.raw)[1] > below]
    on.sort(key=lambda f: ((f.vis or f.raw)[1], (f.vis or f.raw)[0]))
    return on, off


def main(argv):
    if len(argv) < 2:
        print(__doc__ or "usage: uifind.py dump.xml 'regex' [options]", file=sys.stderr)
        return 1
    scr = load(argv[0])
    if scr is None or not scr.nodes:
        print("no dump: %s" % argv[0], file=sys.stderr)
        return 1
    opts = argv[1:]
    if opts[0] == "--package":
        pkg = scr.nodes[0].get("package")
        if not pkg:
            return 1
        print(pkg)
        return 0
    if opts[0] == "--band":
        b = scr.band()
        if not b:
            return 1
        print(b[0], b[1])
        return 0

    def val(name, kind=int):
        return kind(opts[opts.index(name) + 1]) if name in opts else None

    count = opts[0] == "--count"
    pattern = opts[1] if count else opts[0]
    on, off = find(scr, pattern, checkable="--checkable" in opts, not_edit="--not-edit" in opts,
                   below=val("--below"), any_place="--any" in opts, min_px=val("--min") or MIN_VISIBLE)
    if count:
        print(len(on))
        return 0
    if not on:
        if off:
            f = off[0]
            print("'%s' %s: %s" % (f.name, f.why, " ".join(str(v) for v in f.raw)), file=sys.stderr)
            return 3
        return 1
    if len(on) > 1 and "--first" not in opts:
        for f in on:
            print("'%s' at %s" % (f.name, f.line()), file=sys.stderr)
        return 2
    print(on[0].name if "--name" in opts else on[0].line(val("--right")))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
