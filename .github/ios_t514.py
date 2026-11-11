"""Test only (T-514): walk the pages of PR 6a-1 and 6a-2 in the iOS simulator by accessibility labels (idb) and
take frames - the training programs with a program preview, Open GPX, the profiles, Swag Bag, Credits.

usage: ios_t514.py <idb> <udid> <out_dir> <prefix> <look>
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


def tap(label, scrolls=0):
    global tapped_at
    dismiss_alerts()
    for i in range(scrolls + 1):
        e = find(label)
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


def home():
    """Back to the home page: the arrow until the menu button shows (two pages deep at most)."""
    for _ in range(3):
        if find(MENU) and find("Start"):
            return True
        if not tap(BACK):
            return False
        time.sleep(3)
    return bool(find("Start"))


# (menu entry, landing label on the page, frame name); "Profile: " + the profile name, "A very big thanks" -
# the Credits text, which the classic look starts with "Credits" in bold (a prefix match of find() would not
# reach it - the landing there is the page title of the modern look or the thanks)
PAGES = [
    ("Open Train Program", "Other folders", "programs"),
    ("Open GPX", "Other folders", "gpx"),
    ("Profile:", "Other folders", "profiles"),
    ("Swag Bag", "Restore Purchases", "swagbag"),
    ("Credits", None, "credits"),
]

dismiss_alerts()
shot("home")
reached, missed = [], []
for entry, landing, name in PAGES:
    ok = False
    if tap(MENU) and wait_for(entry, 30):
        if tap(entry, scrolls=3):
            if landing is None:
                time.sleep(15)
                ok = True
            else:
                ok = wait_for(landing, 120)
            time.sleep(5)
            shot(name)
            if ok and name == "programs" and tap("Easy intervals") and wait_for("Start Workout", 60):
                time.sleep(8)
                shot("program-preview")
    (reached if ok else missed).append(name)
    if not home():
        print("not back on the home page after", name)
        shot(name + "-stuck")
        break
print("SUMMARY", PREFIX, "reached", ",".join(reached) or "-", "missed", ",".join(missed) or "-")
sys.exit(0 if not missed and len(reached) == len(PAGES) else 1)
