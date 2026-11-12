"""Test only (T-495): the program preview in the iOS simulator by accessibility labels (idb) - "HIIT Aerobic"
(a long description) and "HIIT Neuromuscular" (a short one), upright (the simulator is not turned here).

usage: ios_t495.py <idb> <udid> <out_dir> <prefix> <look> <side>
look: classic (the menu and the back arrow are "◄") or modern ("Main menu" on the home page, "Back" on a page).
side: head (this branch: the long description folded with "Show more", "Show less" after a tap, the short one
without the button) or base (master: no button at all).
Prints CHECK lines and a SUMMARY line; exit code 1 when a page was not reached or a check failed.
The helpers are those of ios_t514.py (T-514), which has the history of each of them.
"""
import json
import subprocess
import sys
import time

IDB, UDID, OUT, PREFIX, LOOK, SIDE = sys.argv[1:7]
MENU = "Main menu" if LOOK == "modern" else "◄"
BACK = "Back" if LOOK == "modern" else "◄"
step = 0
failed = []


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


def find(label, exact=False):
    for e in tree():
        text = e.get("AXLabel") or ""
        if text == label or (not exact and text.startswith(label)):
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


def tap_at(x, y, what):
    global tapped_at
    print(f"{time.strftime('%H:%M:%S', time.gmtime())} tap {what} at {x:.0f},{y:.0f}")
    run("ui", "tap", str(round(x)), str(round(y)))
    tapped_at = time.time()
    time.sleep(3)


def tap(label, scrolls=0, exact=False):
    dismiss_alerts()
    for i in range(scrolls + 1):
        e = find(label, exact)
        # an entry under the bottom edge is in the tree with its frame below the screen (T-514)
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


def wait_for(label, timeout=90, exact=False):
    """The page and the tree come 5-30 s after a tap: wait for a label of the next screen."""
    end = time.time() + timeout
    while time.time() < end:
        if find(label, exact):
            print(f"{time.strftime('%H:%M:%S', time.gmtime())} seen {label!r} {time.time() - tapped_at:.0f} s after the tap")
            return True
        time.sleep(2)
    print(f"{time.strftime('%H:%M:%S', time.gmtime())} not seen in {timeout} s: {label!r}")
    return False


def check(ok, what):
    print("CHECK", "OK" if ok else "FAILED", what)
    if not ok:
        failed.append(what)


def on_home():
    """The home page: its Lap button (not Start - the fake device starts a workout by itself)."""
    return find("Lap") is not None


def back_to_list():
    """From the preview back to the program list, then its "Other folders". Modern look: the toolbar arrow steps
    back inside the page (handleBack). Classic look: the toolbar "◄" pops the whole page to the home page
    (main.qml navigateBack(false); seen in 43246979788), so the "← Back" button of the preview itself."""
    if not tap(BACK if LOOK == "modern" else "← Back", exact=True):
        return False
    return wait_for("Other folders", 60)


def open_list():
    if not (tap(MENU) and wait_for("Open Train Program", 30)):
        return False
    if not tap("Open Train Program", scrolls=3):
        return False
    ok = wait_for("Other folders", 120)
    time.sleep(5)
    return ok


def open_program(name, row):
    """The preview of a program. The modern cards are named (PR 5719); the classic rows have no name for the
    screen reader, so the classic look taps the row <row>, below the "←" button of the filter row (rows of
    50 pt at 100 %, the first one 40 pt below its bottom - ios_t514.py)."""
    if LOOK == "modern":
        if not tap(name, scrolls=2, exact=True):
            return False
    else:
        # exact: a prefix would also take "← Back" of a preview still sliding out
        e = find("←", exact=True)
        if not e:
            print("not found: '←'")
            return False
        fr = e["frame"]
        tap_at(200, fr["y"] + fr["height"] + 40 + (row - 1) * 50, f"the program row {row} ({name})")
    return wait_for("Start Workout", 60)


dismiss_alerts()
shot("home")
reached = []
if open_list():
    shot("programs")
    reached.append("programs")
    if open_program("HIIT Aerobic", 2):
        time.sleep(8)
        shot("long")
        reached.append("long")
        if SIDE == "head":
            # the description comes asynchronously and the fold is laid out after it; the iOS tree lags
            # 6-12 s behind a tap: wait for the labels (wait_for returns as soon as one shows)
            more = wait_for("Show more", 60, exact=True)
            check(more, "the long description folded, Show more")
            if more and tap("Show more", exact=True):
                ok = wait_for("Show less", 60, exact=True)
                time.sleep(2)
                shot("long-unfolded")
                check(ok, "Show more unfolds, Show less")
                if ok and tap("Show less", exact=True):
                    ok = wait_for("Show more", 60, exact=True)
                    time.sleep(2)
                    shot("long-folded-again")
                    check(ok, "Show less folds again, Show more")
        else:
            check(find("Show more", exact=True) is None, "master: no Show more")
        if back_to_list() and open_program("HIIT Neuromuscular", 5):
            time.sleep(8)
            shot("short")
            reached.append("short")
            check(find("Show more", exact=True) is None, "the short description has no button")
for _ in range(3):
    if on_home() or not tap(BACK):
        break
    time.sleep(5)
missed = [p for p in ("programs", "long", "short") if p not in reached]
print("SUMMARY", PREFIX, "reached", ",".join(reached) or "-", "missed", ",".join(missed) or "-",
      "failed checks", len(failed))
sys.exit(0 if not missed and not failed else 1)
