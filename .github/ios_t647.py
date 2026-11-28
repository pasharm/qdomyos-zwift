"""Test only (T-647): the accent row of the modern look on iOS - the PR branch feat/modern-wallpaper-accent, the accent
saved as "system" (the wallpaper colour of Android 12+) in the plist.

usage: ios_t647.py <idb> <udid> <out_dir> <prefix>
iOS has no wallpaper palette (androidstatusbar.cpp systemAccentColor: empty off Android), so: no swatch "Wallpaper
color" in the row (settings.qml model: "system" only with window.ui.systemAccentAvailable), the six fixed swatches
there, Violet marked (main.qml accentName: a saved "system" with no palette is violet) - the ring on the frame "row";
then Blue tapped - the frame "blue". AXValue of the swatches printed: whether the mark reaches the iOS tree is not
proven by it (an empty value is no failure).
Steps: home (the sign Lap of the fake device), Settings by the menu "Main menu" of the modern look, General UI Options
open (the landing - the label "Accent color"), the row on the screen. SUMMARY line and exit code by the library
(tools/ios/iosnav.py).
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from iosnav import (init, shot, wait_for, tap, page, summary, dismiss_alerts, find_in, say,  # noqa: E402
                    tree, place, swipe, screen)

init(*sys.argv[1:5])

MENU = "Main menu"
LABEL = "Accent color"
FIXED = ["Violet", "Blue", "Teal", "Green", "Orange", "Pink"]


def on_screen(label, t=None):
    t = t or tree()
    e = find_in(t, label, exact=True)
    return e if e is not None and place(e, t) == "on" else None


def values(t):
    out = []
    for name in ["Wallpaper color"] + FIXED:
        e = find_in(t, name, exact=True)
        out.append(f"{name}={'-' if e is None else repr(e.get('AXValue') or '')}")
    return " ".join(out)


dismiss_alerts()
ok = wait_for("Lap", exact=True)
page("home", ok)
say(f"screen {screen()} pt")
ok = ok and tap(MENU, "Settings") and tap("Settings", "General Options")
page("settings", ok)
if ok:
    ok = tap("General UI Options", LABEL, scrolls=12)
    page("General UI Options open", ok)
if ok:
    # the label and the last swatch both on the screen: the row whole
    for i in range(10):
        if on_screen(LABEL) and on_screen("Pink"):
            break
        swipe("up")
        time.sleep(2)
    t = tree()
    shot("row")
    page("the accent row on the screen", on_screen(LABEL, t) is not None and on_screen("Pink", t) is not None)
    page("no 'Wallpaper color' on iOS", find_in(t, "Wallpaper color", exact=True) is None)
    page("the six fixed swatches", all(find_in(t, n, exact=True) is not None for n in FIXED))
    say("values: " + values(t))
    blue = tap("Blue", "Blue")
    time.sleep(3)
    t = tree()
    shot("blue")
    page("Blue tapped", blue)
    say("values after Blue: " + values(t))
sys.exit(summary())
