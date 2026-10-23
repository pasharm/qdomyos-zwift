"""T-196 on the iOS simulator: change the app language in Settings and take frames.

usage: ios_lang.py <idb> <udid> <out_dir> <prefix> <language label>
Settings -> General Options -> App Language list -> <language label> -> OK, then frames and the
labels of the accessibility tree (idb) before and after, to see whether the texts changed.
"""
import json
import subprocess
import sys
import time

IDB, UDID, OUT, PREFIX, LANGUAGE = sys.argv[1:6]
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


def labels(t):
    return [e.get("AXLabel") or "" for e in t if e.get("AXLabel")]


def shot(name):
    global step
    step += 1
    base = f"{OUT}/{PREFIX}-{step:02d}-{name}"
    subprocess.run(["xcrun", "simctl", "io", UDID, "screenshot", base + ".png"], capture_output=True)
    t = tree()
    with open(base + ".ui.json", "w", encoding="utf-8") as f:
        json.dump(t, f, ensure_ascii=False, indent=1)
    print("frame", base)
    print("  labels:", " | ".join(labels(t))[:1500])


def find(label):
    for e in tree():
        text = e.get("AXLabel") or ""
        if text == label or text.startswith(label):
            return e
    return None


def centre(e):
    fr = e["frame"]
    return fr["x"] + fr["width"] / 2, fr["y"] + fr["height"] / 2


def tap_at(x, y, what):
    print(f"tap {what} at {x:.0f},{y:.0f}")
    run("ui", "tap", str(round(x)), str(round(y)))
    time.sleep(3)


def tap(label, scrolls=0):
    for i in range(scrolls + 1):
        e = find(label)
        if e:
            tap_at(*centre(e), repr(label))
            return True
        if i < scrolls:
            run("ui", "swipe", "200", "650", "200", "350", "--duration", "0.3")
            time.sleep(1.5)
    print(f"not found: {label!r}")
    return False


def language_row():
    """The App Language label, its list and its OK button: elements on the same line."""
    t = tree()
    label = None
    for e in t:
        if (e.get("AXLabel") or "").startswith("App Language"):
            label = e
    if not label:
        return None
    _, ly = centre(label)
    row = [e for e in t if e is not label and abs(centre(e)[1] - ly) < 30]
    for e in row:
        print("  row:", e.get("type"), repr(e.get("AXLabel")), e["frame"])
    ok = None
    for e in row:
        if (e.get("AXLabel") or "") == "OK":
            ok = e
    if not ok:
        return None
    combo = None
    ok_x = ok["frame"]["x"]
    for e in row:
        if e is not ok and e["frame"]["x"] < ok_x and e["frame"]["x"] > label["frame"]["x"] + 20:
            combo = e
    combo_xy = centre(combo) if combo else (ok_x - 80, ly)
    return combo_xy, centre(ok)


shot("home")
if not tap("◄"):
    sys.exit("no menu button")
shot("menu")
if not tap("Settings"):
    sys.exit("no Settings")
shot("settings")
if not tap("General Options", scrolls=8):
    sys.exit("no General Options")
row = None
for _ in range(6):
    row = language_row()
    if row:
        break
    run("ui", "swipe", "200", "650", "200", "450", "--duration", "0.3")
    time.sleep(1.5)
shot("general")
if not row:
    sys.exit("no App Language row")
combo_xy, ok_xy = row
tap_at(*combo_xy, "the App Language list")
shot("list-open")
if not tap(LANGUAGE):
    sys.exit(f"no {LANGUAGE} in the list")
shot("picked")
tap_at(*ok_xy, "OK")
time.sleep(5)
shot("after-ok")
time.sleep(10)
shot("after-ok-15s")
if tap("◄") or tap("Back"):
    shot("back-home")
