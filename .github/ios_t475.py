"""Test only (T-475, PR fix/target-zone-hold): "Return to app" on the T.Zone tile in the iOS simulator, classic look.
The test hook of test/t475-pr-apk shows the button on T.Power(W) and T.Zone without a FitPlus bike; in the T.Zone
tile it stands in place of the "min-max W %" line (src/Home.qml, RoundButton targetPowerRelease, secondLineText).
The workflow puts T.Zone first (order 0) and T.Power(W) later (order 8). Frame: home.

usage: ios_t475.py <idb> <udid> <out_dir> <prefix>
Prints a SUMMARY line; exit code 1 when a check missed.
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from iosnav import init, say, tree, find_in, middle, place, wait_for, shot, page, summary, dismiss_alerts, _swipe  # noqa: E402

init(*sys.argv[1:5])
ZONE = "T.Zone"
BUTTON = "Return to app"

dismiss_alerts()
home = page("home", wait_for("Lap", 120, exact=True))
if home:
    time.sleep(5)
    shot("home")
    # the tree lists only the tiles the grid has made (run 43724917440: up to Clock), and T.Zone comes after the
    # default tiles: swipe up until its middle is on the screen
    zone, t = None, []
    for _ in range(10):
        t = tree()
        zone = find_in(t, ZONE)
        if zone is not None and place(zone, t) == "on":
            break
        say("T.Zone", "not in the tree" if zone is None else f"at y {middle(zone)[1]:.0f}", "- swipe up")
        _swipe("up")
    time.sleep(3)
    shot("zone")
    t = tree()
    zone = find_in(t, ZONE)
    buttons = [e for e in t if isinstance(e, dict) and (e.get("AXLabel") or "") == BUTTON]
    say("zone tile:", zone and zone.get("AXLabel"), zone and zone.get("frame"))
    for b in buttons:
        say("button at", b.get("frame"))
    page("zone tile", zone is not None and place(zone, t) == "on")
    page("button on the screen", len(buttons) >= 1)
    inside = False
    if zone is not None:
        fr = zone["frame"]
        for b in buttons:
            x, y = middle(b)
            if fr["x"] <= x <= fr["x"] + fr["width"] and fr["y"] <= y <= fr["y"] + fr["height"]:
                inside = True
                say(f"button {x:.0f},{y:.0f} inside the T.Zone tile")
    page("button in the T.Zone tile", inside)
sys.exit(summary())
