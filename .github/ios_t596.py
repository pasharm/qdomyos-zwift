"""Test only (T-596): the workout editor page kept between openings in the modern look, in the iOS simulator
(WKWebView): the page leaves the stack hidden, its native view too - nothing of the editor over the home page -
and opens again at once; the classic look opens it anew every time, as master.

usage: ios_t596.py <idb> <udid> <out_dir> <prefix> <look>
look: classic ("◄" is the menu and the back arrow) or light (the modern look: "Main menu", "Back").
The tree of idb has nothing of a WKWebView page (T-187): the editor is its QML toolbar title; whether its view
covers the home page is read on the frames 02-home (the home tiles must show). The kept workout itself (an
interval added and still there) is checked on Android (emu.sh of T-596). SUMMARY line and exit code by the
library (tools/ios/iosnav.py).
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from iosnav import (init, shot, tree, place, middle, press, wait_for, home, page, summary,  # noqa: E402
                    dismiss_alerts, say)

init(*sys.argv[1:5])
LOOK = sys.argv[5] if len(sys.argv) > 5 else "classic"
MODERN = LOOK != "classic"
MENU = "Main menu" if MODERN else "◄"
BACK = "Back" if MODERN else "◄"
# the web page loads for 10-30 s the first time (T-187): the frame after this
PAGE_WAIT = 30


def editor_title(timeout=120):
    """The editor page by its toolbar title (the QML header, y < 130), not the menu entry of the same text."""
    end = time.time() + timeout
    while time.time() < end:
        t = tree()
        for e in t:
            if isinstance(e, dict) and (e.get("AXLabel") or "") == "Workout Editor" \
                    and middle(e)[1] < 130 and place(e, t) == "on":
                return True
        time.sleep(1)
    say(f"not seen in {timeout} s: the toolbar title 'Workout Editor'")
    return False


def open_editor():
    dismiss_alerts()
    if not (press(MENU, scrolls=0) and wait_for("Workout Editor", 30) and press("Workout Editor", scrolls=3)):
        return False
    start = time.time()
    ok = editor_title()
    if ok:
        say(f"the editor title {time.time() - start:.0f} s after the tap")
    return ok


dismiss_alerts()
page("home", wait_for("Lap", exact=True))

if page("editor", open_editor()):
    time.sleep(PAGE_WAIT)
    shot("01-editor")
page("home-after-editor", home(BACK))
time.sleep(3)
# the home page: its tiles, not the editor page left over it
shot("02-home")

if page("editor-again", open_editor()):
    # kept: the page is there at once - the frame after a short wait shows it drawn, not loading
    time.sleep(3)
    shot("03-again")
page("home-again", home(BACK))
time.sleep(3)
shot("04-home")
sys.exit(summary())
