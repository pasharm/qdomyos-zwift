"""Test only (T-552): the heart rate sensor bar and its list in the iOS simulator, after the change of T-552 (the
modern look by Material 3, variant B: the bar as UiNotice, the list card as UiMessageDialog). The test hook of T-473
"finds" Forerunner 965 (-58 dBm) and XOSS X2P (-71 dBm) 30 s and 45 s after homeform starts.

usage: ios_t552.py <idb> <udid> <out_dir> <prefix> <case>
case: md (modern dark, Ukrainian), ml (modern light, Ukrainian), c (classic, English).
Steps: the bar with two sensors (frame), Choose, the list (frame), Cancel - the list goes and the bar stays (frame);
md also chooses Forerunner 965 - the bar goes. Measures in points from describe-all, as on Android (run 43590701420,
3.5 px per dp): modern - the bar text 16 + 20 = 36 pt from the left edge (HeartRateSuggestion.qml: the bar 16 from
the edges, the text 20 inside), a list row 56 pt or more, Cancel on the screen; classic - 10 + 12 = 22 pt, the rows
name the sensor alone, no Cancel. Prints a SUMMARY line; exit code 1 when a step failed.
The helpers run/tree/frame/shot/find/on_screen/dismiss_alerts/tap/wait_for are those of .github/ios_t537.py (T-537).
"""
import json
import subprocess
import sys
import time

IDB, UDID, OUT, PREFIX, CASE = sys.argv[1:6]
MODERN = CASE != "c"
if MODERN:
    BAR2 = "Знайдено пульсометрів: 2"
    CHOOSE, LIST, CANCEL = "Вибрати", "Виберіть пульсометр", "Скасувати"
    ROW1, ROW2 = "Forerunner 965, Сильний сигнал", "XOSS X2P, Середній сигнал"
else:
    BAR2 = "Heart rate sensors found: 2"
    CHOOSE, LIST, CANCEL = "Choose", "Choose a heart rate sensor", "Cancel"
    ROW1, ROW2 = "Forerunner 965", "XOSS X2P"
step = 0
tapped_at = time.time()
screen = {"h": 874}
failures = []


def now():
    return time.strftime('%H:%M:%S', time.gmtime())


def fail(msg):
    print("!!", msg)
    failures.append(msg)


def ok(msg):
    print("check", msg, ": OK")


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
            if t[0].get("frame"):
                screen["h"] = t[0]["frame"]["height"]
            return t
        time.sleep(3)
    print("describe-all: empty tree")
    return t


def frame(name):
    global step
    step += 1
    base = f"{OUT}/{PREFIX}-{step:02d}-{name}"
    subprocess.run(["xcrun", "simctl", "io", UDID, "screenshot", base + ".png"], capture_output=True)
    return base


def shot(name):
    """The picture first, then its tree (the tree of a still screen; T-478 lesson 3)."""
    base = frame(name)
    t = tree()
    with open(base + ".ui.json", "w", encoding="utf-8") as f:
        json.dump(t, f, ensure_ascii=False, indent=1)
    print("frame", base)
    return t


def label(e):
    return e.get("AXLabel") or ""


def find(text, t=None, exact=False):
    for e in (t if t is not None else tree()):
        if label(e) == text or (not exact and label(e).startswith(text)):
            return e
    return None


def on_screen(e):
    # describe-all lists controls outside the screen too (T-502 lesson 2): below the status bar, above the home
    # indicator
    fr = e["frame"]
    y = fr["y"] + fr["height"] / 2
    return 54 < y < screen["h"] - 34


def dismiss_alerts():
    """A system question of iOS ("… Would Like to Send You Notifications") covers the app: Allow."""
    for _ in range(3):
        t = tree()
        if not any("Would Like" in label(e) for e in t):
            return
        for e in t:
            if label(e) in ("Allow", "OK", "Allow While Using App"):
                fr = e["frame"]
                print("tap the system question:", label(e))
                run("ui", "tap", str(round(fr["x"] + fr["width"] / 2)), str(round(fr["y"] + fr["height"] / 2)))
                time.sleep(3)
                break
        else:
            return


def tap(text, exact=True):
    global tapped_at
    dismiss_alerts()
    e = find(text, exact=exact)
    if not e or not on_screen(e):
        fail(f"tap {text!r}: not on the screen")
        return False
    fr = e["frame"]
    x = fr["x"] + fr["width"] / 2
    y = fr["y"] + fr["height"] / 2
    print(f"{now()} tap {text!r} at {x:.0f},{y:.0f}")
    run("ui", "tap", str(round(x)), str(round(y)))
    tapped_at = time.time()
    time.sleep(3)
    return True


def wait_for(text, timeout=90, exact=True):
    end = time.time() + timeout
    while time.time() < end:
        if find(text, exact=exact):
            print(f"{now()} seen {text!r} {time.time() - tapped_at:.0f} s after the tap")
            return True
        time.sleep(2)
    print(f"{now()} not seen in {timeout} s: {text!r}")
    return False


def wait_gone(text, timeout=20):
    end = time.time() + timeout
    while time.time() < end:
        if not find(text, exact=True):
            print(f"{now()} gone {text!r} {time.time() - tapped_at:.0f} s after the tap")
            return True
        time.sleep(2)
    return False


def fr_of(t, text):
    e = find(text, t, exact=True)
    if not e:
        fail(f"{text!r} not in the tree of the frame")
        return None
    fr = e["frame"]
    print(f"geom {text!r}: x {fr['x']:.1f} y {fr['y']:.1f} w {fr['width']:.1f} h {fr['height']:.1f}")
    return fr


def walk():
    # the second sensor comes 45 s after homeform starts; the step waited WAIT s already
    if not wait_for(BAR2, 120):
        shot("no-bar")
        fail("the bar with two sensors not shown")
        return
    t = shot("bar")
    fr = fr_of(t, BAR2)
    if fr:
        want = 36 if MODERN else 22
        if abs(fr["x"] - want) <= 2:
            ok(f"bar text left {fr['x']:.1f} pt (expected {want})")
        else:
            fail(f"bar text left {fr['x']:.1f} pt, expected {want}")
        if fr["x"] + fr["width"] > t[0]["frame"]["width"] + 1:
            fail("bar text past the right edge of the screen")
    if not find(CHOOSE, t, exact=True):
        fail(f"{CHOOSE!r} not on the bar")
    if not tap(CHOOSE) or not wait_for(LIST, 20):
        shot("no-list")
        fail("the list did not open")
        return
    time.sleep(1)
    t = shot("list")
    fr_of(t, LIST)
    r1 = fr_of(t, ROW1)
    r2 = fr_of(t, ROW2)
    if r1 and r2:
        if r1["y"] < r2["y"]:
            ok("order: the strongest first")
        else:
            fail("order: row 1 not above row 2")
        if MODERN:
            if r1["height"] >= 55:
                ok(f"row height {r1['height']:.1f} pt")
            else:
                fail(f"row height {r1['height']:.1f} pt < 56")
    if MODERN:
        c = fr_of(t, CANCEL)
        if c:
            if on_screen(c):
                ok("Cancel on the screen")
            else:
                fail("Cancel off the screen")
        if not tap(CANCEL):
            return
        if wait_gone(LIST):
            ok("Cancel closed the list")
        else:
            fail("the list still open after Cancel")
        t = shot("cancelled")
        if find(BAR2, t, exact=True):
            ok("the bar stays after Cancel")
        else:
            fail("the bar gone after Cancel")
    else:
        if find(CANCEL, t, exact=True):
            fail("classic: a Cancel on the list")
        else:
            ok("classic: no Cancel")
        # the classic list closes by a tap outside: on the status bar area of the page, above the card
        run("ui", "tap", "20", "120")
        time.sleep(2)
    if CASE != "md":
        return
    if not tap(CHOOSE) or not wait_for(LIST, 20):
        fail("the list did not open again")
        return
    if not tap(ROW1):
        return
    if wait_gone(BAR2, 20):
        ok("a sensor chosen: the bar gone")
    else:
        fail("the bar still there after a choice")
    shot("chosen")


walk()
print(f"SUMMARY {PREFIX}: {len(failures)} failures" + ("" if not failures else ": " + "; ".join(failures)))
sys.exit(1 if failures else 0)
