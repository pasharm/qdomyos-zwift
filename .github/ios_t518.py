"""Test only (T-518): walk the classic pages with the "Other folders" button in the iOS simulator by accessibility
labels (idb) and take frames - the training programs, Open GPX, the profiles. A copy of ios_t514.py (T-514)
without the program preview, Swag Bag and Credits.

usage: ios_t518.py <idb> <udid> <out_dir> <prefix> <look>
look: classic (the menu and the back arrow are "◄") or modern ("Main menu" on the home page, "Back" on a page).
Every page opens from the menu and goes back by the arrow; each landing is a label of the page. Prints a
SUMMARY line with the pages reached and missed; exit code 1 when a page was not reached.
The helpers run/tree/shot/find/dismiss_alerts/tap/wait_for are those of .github/ios_nav.py (T-281, T-498).
"""
import json
import subprocess
import sys
import time

IDB, UDID, OUT, PREFIX, LOOK = sys.argv[1:6]
MENU = "Main menu" if LOOK == "modern" else "◄"
BACK = "Back" if LOOK == "modern" else "◄"
step = 0


def run(*args):
    return subprocess.run([IDB, *args, "--udid", UDID], capture_output=True, text=True)


def tree():
    # right after a relaunch the tree can come back as one empty element: ask again
    for _ in range(10):
        r = run("ui", "describe-all", "--json")
        try:
            t = json.loads(r.stdout)
        except ValueError:
            print("describe-all:", r.stderr[-500:])
            t = []
        if len(t) > 1:
            return t
        time.sleep(3)
    print("describe-all: empty tree")
    return t


def shot(name):
    global step
    step += 1
    base = f"{OUT}/{PREFIX}-{step:02d}-{name}"
    subprocess.run(["xcrun", "simctl", "io", UDID, "screenshot", base + ".png"], capture_output=True)
    with open(base + ".ui.json", "w", encoding="utf-8") as f:
        json.dump(tree(), f, ensure_ascii=False, indent=1)
    print("frame", base)


def find(label):
    for e in tree():
        text = e.get("AXLabel") or ""
        if text == label or text.startswith(label):
            return e
    return None


def dismiss_alerts():
    """A system question of iOS ("… Would Like to Send You Notifications") covers the app: Allow."""
    for _ in range(3):
        t = tree()
        if not any("Would Like" in (e.get("AXLabel") or "") for e in t):
            return
        for e in t:
            if (e.get("AXLabel") or "") in ("Allow", "OK", "Allow While Using App"):
                fr = e["frame"]
                print("tap the system question:", e["AXLabel"])
                run("ui", "tap", str(round(fr["x"] + fr["width"] / 2)), str(round(fr["y"] + fr["height"] / 2)))
                time.sleep(3)
                break
        else:
            return


tapped_at = time.time()


def screen_h():
    """The height of the screen in points: the frame of the app element, the first of the tree."""
    t = tree()
    return t[0]["frame"]["height"] if t else 874


def tap(label, scrolls=0):
    global tapped_at
    dismiss_alerts()
    for i in range(scrolls + 1):
        e = find(label)
        # an entry under the bottom edge is in the tree with its frame below the screen: the modern
        # menu put Credits at y 867 of 874, and the tap there hit nothing (43063540344, 43099685765)
        if e and e["frame"]["y"] + e["frame"]["height"] / 2 > screen_h() - 40 and i < scrolls:
            print(f"{label!r} under the bottom edge (y {e['frame']['y']:.0f}): scroll")
            e = None
        if e:
            fr = e["frame"]
            x = fr["x"] + fr["width"] / 2
            y = fr["y"] + fr["height"] / 2
            print(f"{time.strftime('%H:%M:%S', time.gmtime())} tap {label!r} at {x:.0f},{y:.0f}")
            run("ui", "tap", str(round(x)), str(round(y)))
            tapped_at = time.time()
            time.sleep(3)
            return True
        if i < scrolls:
            # x 200 of a 402 pt wide iPhone: inside the menu of both looks as well
            run("ui", "swipe", "200", "650", "200", "250", "--duration", "0.3")
            time.sleep(1.5)
    print(f"not found: {label!r}")
    return False


def wait_for(label, timeout=90):
    """The page and the tree come 5-30 s after a tap (more on the x86_64 simulator slice): wait for a label of
    the next screen and say how long it took after the tap."""
    end = time.time() + timeout
    while time.time() < end:
        if find(label):
            print(f"{time.strftime('%H:%M:%S', time.gmtime())} seen {label!r} {time.time() - tapped_at:.0f} s after the tap")
            return True
        time.sleep(2)
    print(f"{time.strftime('%H:%M:%S', time.gmtime())} not seen in {timeout} s: {label!r}")
    return False


def on_home():
    """The home page: its Lap button. Not "Start": the fake device starts a workout by itself, and the
    button reads Pause then (43036999474); not the menu button either - in the classic look the arrow of
    a page is the same "◄", and a tap on it at home opens the menu."""
    return find("Lap") is not None


def home():
    """Back to the home page: the arrow until the home page shows (two pages deep at most)."""
    for _ in range(3):
        if on_home():
            return True
        if not tap(BACK):
            # the page may still be sliding out: the home page came a moment later without an arrow
            # to find (43116037373, after the program preview)
            return wait_for("Lap", 30)
        # the home page or the page under it: wait for the home page before the next arrow, which
        # on the home page of the classic look would open the menu
        end = time.time() + 15
        while time.time() < end and not on_home():
            time.sleep(2)
    return on_home()


# (menu entry, landing label on the page, frame name); "Profile: " + the profile name. The landing of each
# page is the button under test, "Other folders"; the hidden "Restore files" (iOS) must not be in the tree
PAGES = [
    ("Open Train Program", "Other folders", "programs"),
    ("Open GPX", "Other folders", "gpx"),
    ("Profile:", "Other folders", "profiles"),
    # the settings files (SettingsList.qml): the settings page, then its Load settings button
    ("Settings", "Other folders", "settings-files"),
]


def elements(name):
    """The frames of the button and of any "Restore ..." element in the tree, for the head/base compare."""
    for e in tree():
        text = e.get("AXLabel") or ""
        if text.startswith("Other folders") or text.startswith("Restore"):
            fr = e["frame"]
            print(f"element {name}: {text!r} {e.get('type')} x {fr['x']:.1f} y {fr['y']:.1f}"
                  f" w {fr['width']:.1f} h {fr['height']:.1f}")


def open_load_settings():
    """The classic Load settings button of the settings page has no accessible name (iOS tree of
    42850014352: only '◄' and 'Search settings' 258,62 48x48 in the header); it stands right of
    "Search settings" and is as wide (main.qml: toolButtonSettingsSearch anchors.right =
    toolButtonLoadSettings.left), so the tap goes one button width right of its centre."""
    global tapped_at
    if not wait_for("Search settings", 150):
        return False
    e = find("Search settings")
    fr = e["frame"]
    x = fr["x"] + fr["width"] * 1.5
    y = fr["y"] + fr["height"] / 2
    print(f"{time.strftime('%H:%M:%S', time.gmtime())} tap classic Load settings at {x:.0f},{y:.0f}"
          " (right of Search settings)")
    run("ui", "tap", str(round(x)), str(round(y)))
    tapped_at = time.time()
    time.sleep(3)
    return True


dismiss_alerts()
shot("home")
reached, missed = [], []
for entry, landing, name in PAGES:
    ok = False
    if tap(MENU) and wait_for(entry, 30):
        if tap(entry, scrolls=3) and (name != "settings-files" or open_load_settings()):
            if landing is None:
                time.sleep(15)
                ok = True
            else:
                ok = wait_for(landing, 120)
            time.sleep(5)
            shot(name)
            elements(name)
            if ok and name == "settings-files":
                # "Settings folder" is an accordion: a frame with it toggled as well, in case the
                # button moves with the list
                if tap("Settings folder"):
                    time.sleep(8)
                    shot(name + "-toggled")
                    elements(name + "-toggled")
    (reached if ok else missed).append(name)
    if not home():
        print("not back on the home page after", name)
        shot(name + "-stuck")
        break
print("SUMMARY", PREFIX, "reached", ",".join(reached) or "-", "missed", ",".join(missed) or "-")
sys.exit(0 if not missed and len(reached) == len(PAGES) else 1)
