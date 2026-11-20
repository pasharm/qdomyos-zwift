"""Test only (T-595): the workout editor and the program preview in the theme of the app, in the iOS simulator
(WKWebView) - frames of the classic look, the modern light and the modern dark theme, read by eye and measured:
the spacing of the editor (margins, not the flex gap), the spin fields, the surface card of the preview.

usage: ios_t595.py <idb> <udid> <out_dir> <prefix> <look>
look: classic ("◄" is the menu and the back arrow), light or dark (the modern look: "Main menu", "Back").
The program A1spdinc (speed and incline) is put in Documents/training by the workflow; "A1" sorts before the
shipped programs, so it is row 1 of the classic list. The tree of idb has nothing of a WKWebView page (T-187, runs
44352337625, 44352344425): pages are the QML ones - the list, the preview by its Start Workout, the editor by its
toolbar title; the device menu of the page is checked on Android (emu.sh of T-595). SUMMARY line and exit code by
the library (tools/ios/iosnav.py).
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from iosnav import (init, shot, find, find_in, tree, place, middle, press, tap, tap_at, wait_for, home,  # noqa: E402
                    page, summary, dismiss_alerts, swipe, say, _press)

init(*sys.argv[1:5])
LOOK = sys.argv[5] if len(sys.argv) > 5 else "classic"
MODERN = LOOK != "classic"
MENU = "Main menu" if MODERN else "◄"
BACK = "Back" if MODERN else "◄"
# the WebView page loads for 10-30 s after its QML page opens (T-187, run 44352344425): the frame after this
PAGE_WAIT = 30


def open_list():
    if not (press(MENU, scrolls=0) and wait_for("Open Train Program", 30)):
        return False
    ok = tap("Open Train Program", "Other folders", timeout=120)
    time.sleep(5)
    return ok


def open_program(name):
    """The preview of the program. The modern cards are named; the classic rows have no name for the screen
    reader: row 1, 40 pt below the "←" button of the filter row (ios_t187.py, ios_t495.py)."""
    if MODERN:
        return tap(name, "Start Workout", timeout=60, scrolls=2)
    e = find("←", exact=True)
    if not e:
        say("not found: '←'")
        return False
    fr = e["frame"]
    return tap_at(200, fr["y"] + fr["height"] + 40, "Start Workout", f"the program row 1 ({name})", timeout=60)


def editor_title(timeout=120):
    """The editor page by its toolbar title - the QML header, the page itself has no tree; not the menu entry of
    the same text, which is lower (ios_t187.py)."""
    end = time.time() + timeout
    while time.time() < end:
        t = tree()
        for e in t:
            if isinstance(e, dict) and (e.get("AXLabel") or "") == "Workout Editor" \
                    and middle(e)[1] < 130 and place(e, t) == "on":
                say("seen the toolbar title 'Workout Editor'")
                return True
        time.sleep(3)
    say(f"not seen in {timeout} s: the toolbar title 'Workout Editor'")
    return False


def wait_home(timeout=240):
    """The home page by its "Lap", closing the system questions on the way: in run 44641005937 the tree was
    empty at the start, dismiss_alerts() found no question, and the questions came later and covered "Lap" for the
    whole 90 s."""
    end = time.time() + timeout
    while time.time() < end:
        dismiss_alerts()
        if wait_for("Lap", 20, exact=True):
            return True
    return False


def device_menu():
    """The device list of the editor - the menu of the page (qz-modern-select.js), which on iOS opens only when
    WebKit sends the tap to the document (the pointer cursor of the box, the label around the select). The tree
    of idb has nothing of the page, but the list of iOS itself is in it: "Jump Rope" in the tree after the tap
    is the system list, a miss. Two taps: on the field and on its caption above it - in run 44654837781 the
    caption opened the list of iOS (the label focused the select). The places from the frame of that run (402 pt
    wide, Name and Device in one row): the field 204-383 x 142-179, the caption at y 130, the web view from
    y 110. A tap at the left bottom of the page (the backdrop, the menu lies on the right) closes it."""
    t = tree()
    top = None
    for e in t:
        if isinstance(e, dict) and (e.get("AXLabel") or "") in (BACK, "Workout Editor") and middle(e)[1] < 160:
            fr = e["frame"]
            top = max(top or 0, fr["y"] + fr["height"])
    if top is None:
        say("not found: the toolbar of the editor")
        return
    say(f"the web view from y {top:.0f}")
    for name, x, dy in (("field", 294, 51), ("caption", 230, 20)):
        _press(x, top + dy, f"the Device {name}")
        time.sleep(3)
        shot(f"04-menu-{name}")
        system = find("Jump Rope", exact=True) is not None
        say(f"the device list after a tap on the {name}: {'the list of iOS' if system else 'not the list of iOS'}")
        page(f"menu-{name}", not system)
        _press(60, top + 600, "the page beside the menu")
        time.sleep(3)
        shot(f"05-closed-{name}", with_tree=False)


page("home", wait_home())

if page("programs", open_list()):
    if page("preview", open_program("A1spdinc")):
        time.sleep(PAGE_WAIT)
        shot("01-preview")
home(BACK)

# the editor: the top of the page, then the interval card and the chart card below it, a frame a screen
if press(MENU, scrolls=0) and wait_for("Workout Editor", 30) and press("Workout Editor", scrolls=3):
    if page("editor", editor_title()):
        time.sleep(PAGE_WAIT)
        shot("02-editor")
        if MODERN:
            device_menu()
        for i in range(1, 3):
            swipe("up")
            time.sleep(3)
            shot(f"03-editor-down{i}", with_tree=False)
else:
    page("editor", False)
home(BACK)
sys.exit(summary())
