"""T-470 on the iOS simulator: close the system question that covers the app.

usage: ios_alert.py <idb> <udid>
"… Would Like to Send You Notifications" keeps the app inactive while it is open, so a return to
the app would not reach ApplicationActive. Taps Allow (as ios_search.py of T-468): right after the
start the question can ignore taps, so it asks again, and from the 5th try presses Enter as well.
Exit 1 if the question is still open.
"""
import json
import subprocess
import sys
import time

IDB, UDID = sys.argv[1:3]


def run(*args):
    return subprocess.run([IDB, *args, "--udid", UDID], capture_output=True, text=True)


def tree():
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


def label(e):
    return e.get("AXLabel") or ""


for i in range(10):
    t = tree()
    if not any("Would Like" in label(e) for e in t):
        print(f"no system question (after {i} tries)")
        sys.exit(0)
    for e in t:
        if label(e) in ("Allow", "OK", "Allow While Using App"):
            fr = e["frame"]
            x, y = fr["x"] + fr["width"] / 2, fr["y"] + fr["height"] / 2
            print(f"tap {label(e)} at {x:.0f},{y:.0f}")
            r = run("ui", "tap", str(round(x)), str(round(y)))
            if r.returncode != 0:
                print(f"  idb ui tap: exit {r.returncode} {r.stderr.strip()[-300:]}")
            break
    if i >= 4:
        print("press Enter on the system question")
        run("ui", "key", "40")
    time.sleep(5)
print("the system question is still open after 10 tries")
sys.exit(1)
