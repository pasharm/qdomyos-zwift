"""Test only (T-544): the home page and the open drawer in the iOS simulator - the modern look draws the drawer
sheet with a 16 pt corner (main.qml Drawer) and colours the system bars by the page (setSystemBarsColor, the iOS
branch unchanged); the classic look keeps its drawer. Frames: home, the drawer, home again.

usage: ios_t544.py <idb> <udid> <out_dir> <prefix> <look>
The helpers run/tree/shot/find/dismiss_alerts/tap/wait_for are those of .github/ios_t531.py (T-531, T-514).
Prints a SUMMARY line; exit code 1 when the drawer was not opened or not closed.
"""
import json
import subprocess
import sys
import time

IDB, UDID, OUT, PREFIX, LOOK = sys.argv[1:6]
MODERN = LOOK != "classic"
MENU = "Main menu" if MODERN else "◄"
# an entry of the drawer in both looks (main.qml, the menu list)
ENTRY = "Settings"
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
        text = e.get("AXLabel") or ""
        if text == label:
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


def tap(label):
    global tapped_at
    dismiss_alerts()
    e = find(label)
    if not e:
        print(f"not found: {label!r}")
        return False
    fr = e["frame"]
    x = fr["x"] + fr["width"] / 2
    y = fr["y"] + fr["height"] / 2
    print(f"{time.strftime('%H:%M:%S', time.gmtime())} tap {label!r} at {x:.0f},{y:.0f}")
    run("ui", "tap", str(round(x)), str(round(y)))
    tapped_at = time.time()
    return True


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


dismiss_alerts()
home_ok = wait_for("Lap", 90)
shot("home")
opened = closed = False
if home_ok and tap(MENU):
    opened = wait_for(ENTRY, 30)
    time.sleep(2)
    shot("drawer")
    if opened:
        # close it by a tap on the scrim, right of the sheet (the sheet is at most 80 % of the width)
        print(f"{time.strftime('%H:%M:%S', time.gmtime())} tap the scrim at 380,600")
        run("ui", "tap", "380", "600")
        tapped_at = time.time()
        closed = wait_for(ENTRY, 30, gone=True)
        time.sleep(2)
        shot("home-again")
print("SUMMARY", PREFIX, "home", "yes" if home_ok else "no", "drawer", "opened" if opened else "missed",
      "closed" if closed else "not-closed")
sys.exit(0 if (home_ok and opened and closed) else 1)
