"""Test only (T-627): the hints under the settings in the iOS simulator - modern: textMuted, regular font, the hint
size; classic: Lime bold italic as master.

usage: ios_t627.py <idb> <udid> <out_dir> <prefix> <case>
  case light | dark | classic - Settings > Bike Options (settings.qml:4058, first row "Speed calculates on Power"
                 :4069) > its hint "QZ calculates speed based on your pedal cadence..." (:4083), then the hint
                 "0.005 = Clinchers..." (:4221, three lines in one label; steelblue in the classic look)
  case gpx     - modern light: Settings > Training Program Options (:10608, first row "Stop Treadmill at the
                 End") > the hint "For GPX workouts, ignore inclination changes..." (:11602) - one of the seven
                 hints that had the classic size in both looks
SUMMARY line and exit code by the library (tools/ios/iosnav.py).
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from iosnav import (init, shot, wait_for, tap, page, summary, dismiss_alerts, tree, find_in, place,  # noqa: E402
                    middle, swipe, say)

init(*sys.argv[1:5])
CASE = sys.argv[5] if len(sys.argv) > 5 else "light"
# the menu button by its name: "◄" in the classic look, "Main menu" in the modern one (ios_t494.py of T-494)
MENU = "◄" if CASE == "classic" else "Main menu"
SPEED = "QZ calculates speed based on your pedal cadence"
ROLL = "0.005 = Clinchers"
GPX = "For GPX workouts, ignore inclination changes"


def bring(label, swipes=40, top=150):
    """Swipe the page until the row is on the screen below the header (middle y >= top, ios_t599.py); True - it
    is (its element said into the log)."""
    for _ in range(swipes + 1):
        t = tree()
        e = find_in(t, label)
        if e is not None:
            where = place(e, t)
            if where == "on" and middle(e)[1] < top:
                swipe("down")
                continue
            if where == "on":
                keys = ("AXLabel", "type", "role", "frame")
                say("row " + json.dumps({k: e.get(k) for k in keys}, ensure_ascii=False))
                return True
            swipe("up" if where == "below" else "down")
            continue
        swipe("up")
    say(f"not brought onto the screen: {label!r}")
    return False


def settings_section(title, landing):
    ok = tap(MENU, "Settings") and tap("Settings", "General Options")
    page("settings", ok)
    if ok:
        ok = tap(title, landing, scrolls=40)
        page(title.lower(), ok)
    return ok


dismiss_alerts()
ok = wait_for("Lap", exact=True)
page("home", ok)
if CASE in ("light", "dark", "classic"):
    if settings_section("Bike Options", "Speed calculates on Power"):
        ok = bring(SPEED)
        shot("speed")
        page("speed hint", ok)
        ok = bring(ROLL)
        shot("roll")
        page("rolling resistance hint", ok)
elif CASE == "gpx":
    if settings_section("Training Program Options", "Stop Treadmill at the End"):
        ok = bring(GPX)
        shot("gpx")
        page("gpx hint", ok)
else:
    say(f"unknown case {CASE!r}")
    page(CASE, False)
sys.exit(summary())
