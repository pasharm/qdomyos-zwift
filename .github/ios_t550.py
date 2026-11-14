"""Test only (T-550): drop-down lists and menus of the modern look by Material 3 in the iOS simulator.
Settings -> General Options -> the App Language list open (UiComboBox.qml: the list on UiMenuBackground,
surfaceHigh, corner 16, shadow, the chosen item in an accent block), then Workouts History -> the import
menu open (WorkoutsHistory.qml, modernImportMenu: as wide as its longest item, shadow, no outline; the
classic look has its own Menu - not opened). Frames: general, list, history, import.

usage: ios_t550.py <idb> <udid> <out_dir> <prefix> <look>
The helpers run/tree/shot/find/dismiss_alerts/tap/wait_for are those of .github/ios_t544.py (T-544).
Prints a SUMMARY line; exit code 1 when a step was not reached.
"""
import json
import subprocess
import sys
import time

IDB, UDID, OUT, PREFIX, LOOK = sys.argv[1:6]
MODERN = LOOK != "classic"
MENU = "Main menu" if MODERN else "◄"
step = 0
tapped_at = time.time()


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
        if (e.get("AXLabel") or "") == label:
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


def on_screen(e):
    # describe-all lists controls outside the screen too, with their layout coordinates (T-502, lesson 2):
    # 393 x 852 points, below the status bar (54 points with the Dynamic Island). Not 90 (below the header, as
    # in the list walks): the header buttons are tapped here - Main menu at y 62 was "off the screen" in run
    # 43523164213, the walk stopped at its first tap in all three looks
    fr = e["frame"]
    y = fr["y"] + fr["height"] / 2
    return 54 < y < 840


def tap(label):
    global tapped_at
    dismiss_alerts()
    e = find(label)
    if not e:
        print(f"not found: {label!r}")
        return False
    if not on_screen(e):
        print(f"off the screen: {label!r} at y {e['frame']['y']:.0f}")
        return False
    fr = e["frame"]
    x = fr["x"] + fr["width"] / 2
    y = fr["y"] + fr["height"] / 2
    print(f"{time.strftime('%H:%M:%S', time.gmtime())} tap {label!r} at {x:.0f},{y:.0f}")
    run("ui", "tap", str(round(x)), str(round(y)))
    tapped_at = time.time()
    return True


def tap_at(x, y, why):
    global tapped_at
    print(f"{time.strftime('%H:%M:%S', time.gmtime())} tap {why} at {x},{y}")
    run("ui", "tap", str(x), str(y))
    tapped_at = time.time()


def wait_for(label, timeout=60, gone=False):
    """Wait for a label to show (or to go): the tree comes 5-30 s late on the x86_64 simulator slice."""
    end = time.time() + timeout
    while time.time() < end:
        if (find(label) is None) == gone:
            what = "gone" if gone else "seen"
            print(f"{time.strftime('%H:%M:%S', time.gmtime())} {what} {label!r} {time.time() - tapped_at:.0f} s after the tap")
            return True
        time.sleep(2)
    print(f"{time.strftime('%H:%M:%S', time.gmtime())} not {'gone' if gone else 'seen'} in {timeout} s: {label!r}")
    return False


got = {}
dismiss_alerts()
got["home"] = wait_for("Lap", 90)

# Settings -> General Options -> the App Language field (it reads its value, Auto (System))
if got["home"] and tap(MENU) and wait_for("Settings", 30) and tap("Settings") and wait_for("General Options", 60):
    if tap("General Options") and wait_for("Auto (System)", 30):
        time.sleep(2)
        shot("general")
        if tap("Auto (System)"):
            got["list"] = wait_for("Japanese", 30)
            time.sleep(2)
            shot("list")
            # closed by a tap outside it: the list opens over the right half of the page, the popup is modal
            # and takes the tap (UiComboBox.qml popup: modal: true)
            tap_at(40, 500, "outside the list")
            got["list closed"] = wait_for("Japanese", 30, gone=True)

# Workouts History -> the import button (named "Import FIT File...", WorkoutsHistory.qml) -> the menu
if MODERN and got.get("list closed"):
    # from the settings page: the back arrow of the header ("Back" in the modern look, qz.sh back_to), home,
    # then the menu
    back = tap("Back") and wait_for("Lap", 60)
    if back and tap(MENU) and wait_for("Workouts History", 30) and tap("Workouts History") and wait_for("Calendar", 60):
        time.sleep(2)
        shot("history")
        if tap("Import FIT File..."):
            got["import"] = wait_for("Import from QZ Folder...", 30)
            time.sleep(1)
            shot("import")

want = ["home", "list", "list closed"] + (["import"] if MODERN else [])
print("SUMMARY", PREFIX, " ".join(f"{k}={'yes' if got.get(k) else 'no'}" for k in want))
sys.exit(0 if all(got.get(k) for k in want) else 1)
