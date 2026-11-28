"""Test only (T-716): a tap on empty space of the settings page drops the focus of the search field - the
on-screen keyboard goes (TapHandler on the Flickable of settings.qml, branch fix/settings-tap-drops-focus).

usage: ios_t716.py <idb> <udid> <out_dir> <prefix> <case> <side>
  case classic | modern - the look (the menu button: "◄" in the classic look, "Main menu" in the modern one)
  side head | base - head: the keyboard goes after the tap on empty space; base (master): it stays (the defect)
Steps: Settings -> the search button of the header -> "Changed" (the list of the changed settings: a short list,
the page below it is empty) -> a tap on the search field: the on-screen keyboard is up -> a tap on empty space
between the field and the keyboard (no element of the tree under x 200 there) -> the keyboard by the side ->
"Changed" again: the sections come back (a control over the handler still takes its tap).
No idb ui key in the walk: after it the simulator keeps the hardware keyboard for the rest of the run, and the
second look would have no on-screen keyboard (iosnav keyboard_shown, T-701 lesson 2).
SUMMARY line and exit code by the library (tools/ios/iosnav.py).
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from iosnav import (init, shot, wait_for, tap, tap_at, page, summary, dismiss_alerts, find_in, say,  # noqa: E402
                    tree, place, middle, screen, keyboard_top, keyboard_shown, idb)

init(*sys.argv[1:5])

CASE = sys.argv[5] if len(sys.argv) > 5 else "classic"
SIDE = sys.argv[6] if len(sys.argv) > 6 else "head"
MENU = "◄" if CASE == "classic" else "Main menu"
SECTION = "General Options"
SEARCH = "Search settings"
CHANGED = "Changed"
# a run of y with no element under the tap: smaller is the edge of a row
MIN_FREE = 20


def on_exact(label, t=None):
    """The element whose AXLabel is exactly the label, when it is on the screen; else None."""
    t = tree() if t is None else t
    for e in t:
        if isinstance(e, dict) and (e.get("AXLabel") or "") == label and "frame" in e and place(e, t) == "on":
            return e
    return None


def sections_shown(t=None):
    return on_exact(SECTION, t) is not None


def wait_sections(want, timeout=30):
    """Wait until the section "General Options" is on the screen (want=True) or gone from it (want=False)."""
    end = time.time() + timeout
    while True:
        if sections_shown() == want:
            return True
        if time.time() >= end:
            return False
        time.sleep(2)


def field(t):
    """The search field (ios_t510.py, runs 42978647410, 42990250579): a text field below the header, else - Qt 5.15
    on iOS gives the field as StaticText with an empty label (y 112, x 12, 212 wide) left of "Changed" in its row:
    the widest node there."""
    fields = [e for e in t if isinstance(e, dict) and "frame" in e
              and ("TextField" in (e.get("type") or "") or (e.get("role") or "") == "AXTextField")]
    if fields:
        return min(fields, key=lambda e: e["frame"]["y"])
    c = on_exact(CHANGED, t)
    if c is None:
        return None
    cf = c["frame"]
    row = [e for e in t if isinstance(e, dict) and e is not c and "frame" in e and e.get("type") != "Application"
           and e["frame"]["x"] + e["frame"]["width"] <= cf["x"] + 1
           and e["frame"]["y"] < cf["y"] + cf["height"] and e["frame"]["y"] + e["frame"]["height"] > cf["y"]
           and e["frame"]["width"] > 100]
    return max(row, key=lambda e: e["frame"]["width"]) if row else None


def free_y(t, x, ylo, yhi):
    """The middle of the tallest run of y in [ylo, yhi] with no element of the tree under x (the app element and
    the full-width containers down to the bottom - the keyboard - do not count); (y, height) or None."""
    w, h = screen(t)
    taken = []
    for e in t[1:]:
        fr = e.get("frame") if isinstance(e, dict) else None
        if not fr or fr["width"] <= 0 or fr["height"] <= 0:
            continue
        if fr["width"] >= w - 1 and fr["y"] + fr["height"] >= h - 1:
            continue
        if fr["x"] <= x < fr["x"] + fr["width"]:
            taken.append((fr["y"], fr["y"] + fr["height"]))
    best, start = None, None
    for y in range(int(ylo), int(yhi) + 2):
        free = y <= yhi and not any(a <= y < b for a, b in taken)
        if free and start is None:
            start = y
        if not free and start is not None:
            run = y - start
            if run >= MIN_FREE and (best is None or run > best[1]):
                best = (start + run // 2, run)
            start = None
    return best


def walk():
    dismiss_alerts()
    ok = wait_for("Lap", exact=True)
    page("home", ok)
    ok = ok and tap(MENU, "Settings") and tap("Settings", SECTION)
    page("settings", ok)
    if not ok:
        return
    t = tree()
    named = [e for e in t if isinstance(e, dict) and (e.get("AXLabel") or "") == SEARCH and "frame" in e]
    if not named:
        page("the search button", False)
        return
    x, y = middle(min(named, key=lambda e: e["frame"]["y"]))
    ok = tap_at(x, y, CHANGED, "the search button")
    page("the search bar open", ok)
    if not ok:
        return
    shot("search-open")
    # the list of the changed settings: the plist of the run has changed a few, the page below them is empty
    c = on_exact(CHANGED)
    if c is None:
        page("the Changed button on the screen", False)
        return
    x, y = middle(c)
    say(f"tap Changed at {x:.0f},{y:.0f}")
    idb("ui", "tap", str(round(x)), str(round(y)))
    ok = wait_sections(False)
    shot("changed-list")
    page("the list of the changed settings (the sections gone)", ok)
    if not ok:
        return
    t = tree()
    f = field(t)
    if f is None:
        for e in t:
            if isinstance(e, dict) and "frame" in e:
                say("  node", repr(e.get("AXLabel")), e.get("type"), {k: round(v) for k, v in e["frame"].items()})
        page("the search field in the tree", False)
        return
    fx, fy = middle(f)
    say(f"tap the search field at {fx:.0f},{fy:.0f} ({f.get('type')}, {f['frame']})")
    idb("ui", "tap", str(round(fx)), str(round(fy)))
    if not keyboard_shown("the keyboard after the tap on the field"):
        shot("no-keyboard")
        return
    time.sleep(2)
    t = tree()
    shot("focused")
    kb = keyboard_top(t)
    lo = f["frame"]["y"] + f["frame"]["height"] + 4
    gap = free_y(t, 200, lo, kb - 4)
    say(f"the keyboard from y {kb}, empty space under x 200 between y {lo:.0f} and {kb - 4:.0f}: {gap}")
    if gap is None:
        page("empty space above the keyboard", False)
        return
    say(f"tap empty space at 200,{gap[0]} (free {gap[1]} pt)")
    idb("ui", "tap", "200", str(gap[0]))
    end = time.time() + (15 if SIDE == "head" else 8)
    while time.time() < end:
        if keyboard_top(tree()) is None:
            break
        time.sleep(1)
    time.sleep(2)
    t = tree()
    shot("tapped")
    up = keyboard_top(t) is not None
    if SIDE == "head":
        say("check tapped: the keyboard", "still up - !! NOT AS EXPECTED" if up else "hidden: OK")
        page("the tap on empty space hid the keyboard", not up)
    else:
        say("check tapped: master", "keeps the keyboard (the defect): OK" if up else "hid the keyboard - !! the head "
            "side proves nothing")
        page("master keeps the keyboard after the tap on empty space", up)
    page("the list still open after the tap on empty space", not sections_shown(t))
    # a control over the handler: "Changed" again brings the sections back
    c = on_exact(CHANGED, t)
    if c is None:
        page("Changed toggles the list off", False)
        return
    x, y = middle(c)
    say(f"tap Changed again at {x:.0f},{y:.0f}")
    idb("ui", "tap", str(round(x)), str(round(y)))
    ok = wait_sections(True)
    shot("list-off")
    page("Changed toggles the list off", ok)


walk()
sys.exit(summary())
