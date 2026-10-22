"""Walk QZ in the iOS simulator by accessibility labels (idb) and take frames.

usage: ios_nav.py <idb> <udid> <out_dir> <prefix>
Each step: find an element by its label in "idb ui describe-all", tap its centre,
wait, save a frame and the tree. A label not on screen: swipe up a few times.
"""
import json
import subprocess
import sys
import time

IDB, UDID, OUT, PREFIX = sys.argv[1:5]
step = 0


def run(*args):
    return subprocess.run([IDB, *args, "--udid", UDID], capture_output=True, text=True)


def tree():
    r = run("ui", "describe-all", "--json")
    try:
        return json.loads(r.stdout)
    except ValueError:
        print("describe-all:", r.stderr[-500:])
        return []


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


def tap(label, scrolls=0):
    for i in range(scrolls + 1):
        e = find(label)
        if e:
            fr = e["frame"]
            x = fr["x"] + fr["width"] / 2
            y = fr["y"] + fr["height"] / 2
            print(f"tap {label!r} at {x:.0f},{y:.0f}")
            run("ui", "tap", str(round(x)), str(round(y)))
            time.sleep(3)
            return True
        if i < scrolls:
            run("ui", "swipe", "200", "650", "200", "250", "--duration", "0.3")
            time.sleep(1.5)
    print(f"not found: {label!r}")
    return False


shot("home")
if tap("◄"):
    shot("menu")
    if tap("Settings"):
        shot("settings")
        if tap("General UI Options", scrolls=8):
            shot("general-ui")
            run("ui", "swipe", "200", "650", "200", "350", "--duration", "0.3")
            time.sleep(1.5)
            shot("general-ui-2")
