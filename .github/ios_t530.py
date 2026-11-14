"""Test only (T-530): the GPX page in the iOS simulator - Box Hill (selected when the page opens), then Govi to
Hood, then Box Hill again; a frame of each after the map has settled, to see the whole route on the map.
A copy of the helpers of ios_t528.py (T-528).

usage: ios_t530.py <idb> <udid> <out_dir> <prefix> <look>
look: classic (the menu and the back arrow are "◄") or modern ("Main menu" on the home page, "Back" on a page).
The classic rows have no names in the tree (43233374803: only "◄", "←" and "Other folders"), so they are
tapped by place under the "←" button; the modern cards by name when the tree has it, else by place.
Prints a SUMMARY line; exit code 1 when the page was not reached or a route was not tapped.
"""
import json
import subprocess
import sys
import time

IDB, UDID, OUT, PREFIX, LOOK = sys.argv[1:6]
MENU = "Main menu" if LOOK == "modern" else "◄"
BACK = "Back" if LOOK == "modern" else "◄"
SETTLE = 25  # seconds after a selection: the fit and the tiles
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


def now():
    return time.strftime('%H:%M:%S', time.gmtime())


def shot(name):
    """The frame first, then the tree (the tree comes 10-30 s later; the page stands still by then)."""
    global step
    step += 1
    base = f"{OUT}/{PREFIX}-{step:02d}-{name}"
    subprocess.run(["xcrun", "simctl", "io", UDID, "screenshot", base + ".png"], capture_output=True)
    t = tree()
    with open(base + ".ui.json", "w", encoding="utf-8") as f:
        json.dump(t, f, ensure_ascii=False, indent=1)
    print(now(), "frame", base)
    return t


def find(label, t=None):
    for e in (t if t is not None else tree()):
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
    t = tree()
    return t[0]["frame"]["height"] if t else 874


def tap_at(x, y, why):
    global tapped_at
    print(f"{now()} tap {why} at {x:.0f},{y:.0f}")
    run("ui", "tap", str(round(x)), str(round(y)))
    tapped_at = time.time()
    time.sleep(3)


def tap(label, scrolls=0):
    dismiss_alerts()
    for i in range(scrolls + 1):
        e = find(label)
        if e and e["frame"]["y"] + e["frame"]["height"] / 2 > screen_h() - 40 and i < scrolls:
            print(f"{label!r} under the bottom edge (y {e['frame']['y']:.0f}): scroll")
            e = None
        if e:
            fr = e["frame"]
            tap_at(fr["x"] + fr["width"] / 2, fr["y"] + fr["height"] / 2, repr(label))
            return True
        if i < scrolls:
            run("ui", "swipe", "200", "650", "200", "250", "--duration", "0.3")
            time.sleep(1.5)
    print(f"not found: {label!r}")
    return False


def wait_for(label, timeout=90):
    end = time.time() + timeout
    while time.time() < end:
        if find(label):
            print(f"{now()} seen {label!r} {time.time() - tapped_at:.0f} s after the tap")
            return True
        time.sleep(2)
    print(f"{now()} not seen in {timeout} s: {label!r}")
    return False


def dump(name, t):
    """Every labelled element of the page but the list rows, for the head/base compare."""
    for e in t[1:]:
        fr = e["frame"]
        print(f"element {name}: {e.get('AXLabel')!r} {e.get('type')} x {fr['x']:.1f} y {fr['y']:.1f}"
              f" w {fr['width']:.1f} h {fr['height']:.1f}")


def row(name, index):
    """Where to tap the row <index> (0 = Box Hill, 3 = Govi to Hood). Classic (43233374803, frame 03): rows of
    39.7 pt, Box Hill centred 17.7 pt under the bottom of the "←" button (158 pt); modern (43226377560, frame
    04): cards of 64.2 pt, Box Hill centred at 205.5 pt."""
    t = tree()
    e = find(name, t)
    if e and LOOK == "modern":
        fr = e["frame"]
        return fr["x"] + fr["width"] / 2, fr["y"] + fr["height"] / 2, "by name"
    if LOOK == "modern":
        return 150, 205.5 + 64.2 * index, "by place (no name in the tree)"
    arrow = find("←", t)
    if not arrow:
        return None
    bottom = arrow["frame"]["y"] + arrow["frame"]["height"]
    return 100, bottom + 17.7 + 39.7 * index, f"by place under '←' (bottom {bottom:.0f})"


def pick(name, index):
    r = row(name, index)
    if not r:
        print(f"not found: the place of {name!r}")
        return False
    x, y, how = r
    tap_at(x, y, f"{name!r} {how}")
    time.sleep(SETTLE)
    return True


def on_home():
    return find("Lap") is not None


def home():
    for _ in range(3):
        if on_home():
            return True
        if not tap(BACK):
            return wait_for("Lap", 30)
        end = time.time() + 15
        while time.time() < end and not on_home():
            time.sleep(2)
    return on_home()


dismiss_alerts()
shot("home")
done, missed = [], []
if tap(MENU) and wait_for("Open GPX", 30) and tap("Open GPX", scrolls=3) and wait_for("Other folders", 120):
    # Box Hill is selected when the page opens
    time.sleep(SETTLE)
    dump("boxhill", shot("boxhill"))
    done.append("boxhill")
    for name, index, frame in (("Govi to Hood", 3, "govi"), ("Box Hill", 0, "boxhill-again")):
        if pick(name, index):
            t = shot(frame)
            dump(frame, t)
            # the classic page has another page on top when a tap opened the route instead of selecting it
            if find("Other folders", t):
                done.append(frame)
            else:
                print(f"!! {frame}: 'Other folders' gone - the tap did not stay on the list")
                missed.append(frame)
        else:
            missed.append(frame)
else:
    missed.append("gpx page")
if not home():
    print("not back on the home page")
    shot("stuck")
print("SUMMARY", PREFIX, "done", ",".join(done) or "-", "missed", ",".join(missed) or "-")
sys.exit(0 if not missed and len(done) == 3 else 1)
