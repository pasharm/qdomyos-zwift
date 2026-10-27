"""T-046: walk the modern look of QZ in the iOS simulator by accessibility labels (idb), with frames.

usage: ios_modern.py <idb> <udid> <out_dir> <prefix>
Home -> drawer -> every page of the drawer that has no hardware behind it, each left with the
arrow in the header: iOS has no system back button, so every page needs its own way back.
Each step saves a frame, the accessibility tree and its labels; at the end a summary line per page
says whether the arrow brought the home page back.
"""
import json
import os
import subprocess
import sys
import time

IDB, UDID, OUT, PREFIX = sys.argv[1:5]
step = 0
summary = []


def run(*args):
    return subprocess.run([IDB, *args, "--udid", UDID], capture_output=True, text=True)


def tree():
    # right after a start the tree can come back as one empty element, and describe-all
    # sometimes answers in 10-30 s on macos-26: ask again
    t = []
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


def labels(t):
    return [label(e) for e in t if label(e)]


def screen(t):
    for e in t:
        if e.get("type") == "Application":
            return e["frame"]["width"], e["frame"]["height"]
    return 402, 874


def centre(e):
    fr = e["frame"]
    return fr["x"] + fr["width"] / 2, fr["y"] + fr["height"] / 2


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
    return t


def tap_at(x, y, what):
    print(f"tap {what} at {x:.0f},{y:.0f}")
    run("ui", "tap", str(round(x)), str(round(y)))
    time.sleep(3)


def find(text, t=None):
    t = t if t is not None else tree()
    for e in t:
        if label(e) == text:
            return e
    for e in t:
        if label(e).startswith(text):
            return e
    return None


def dismiss_alerts():
    """A system question of iOS ("… Would Like to Send You Notifications") covers the app: Allow."""
    for _ in range(3):
        t = tree()
        if not any("Would Like" in label(e) for e in t):
            return
        for e in t:
            if label(e) in ("Allow", "OK", "Allow While Using App"):
                tap_at(*centre(e), "the system question: " + label(e))
                break
        else:
            return


def swipe_up(t=None):
    w, h = screen(t if t is not None else tree())
    run("ui", "swipe", str(round(w / 2)), str(round(h * 0.75)), str(round(w / 2)), str(round(h * 0.35)),
        "--duration", "0.3")
    time.sleep(1.5)


def tap(text, scrolls=0):
    dismiss_alerts()
    for i in range(scrolls + 1):
        t = tree()
        e = find(text, t)
        w, h = screen(t)
        # in the tree but under the home indicator or past the screen (Credits at the end of the
        # drawer, run 40305428865): scrolled up first, where the element is
        if e and header_bottom(t) < centre(e)[1] < h * 0.92:
            tap_at(*centre(e), repr(text))
            return True
        if i < scrolls:
            if e and centre(e)[1] <= header_bottom(t):
                # above the top of the list (Profile after the drawer was scrolled to Credits,
                # run 40309303007: a tap at y -86): scrolled down
                x = centre(e)[0]
                run("ui", "swipe", str(round(x)), str(round(h * 0.35)), str(round(x)), str(round(h * 0.8)),
                    "--duration", "0.3")
                time.sleep(1.5)
            elif e:
                x = centre(e)[0]
                run("ui", "swipe", str(round(x)), str(round(h * 0.75)), str(round(x)), str(round(h * 0.45)),
                    "--duration", "0.3")
                time.sleep(1.5)
            else:
                swipe_up(t)
    print(f"not found: {text!r}")
    return False


def header_bottom(t):
    # the header ends well above the first row of the home page (Start/Pause at y 142 of 874)
    return screen(t)[1] * 0.14


def header_button(t):
    """The menu / back arrow, if the tree has it: a button in the top left corner, inside the header
    (run 40296830280: the header buttons of the modern look are not in the tree at all)."""
    w, h = screen(t)
    best = None
    for e in t:
        fr = e["frame"]
        if e.get("type") != "Button" or fr["x"] > w * 0.2 or fr["y"] + fr["height"] > header_bottom(t) or fr["y"] < 30:
            continue
        if best is None or fr["x"] < best["frame"]["x"]:
            best = e
    return best


HEADER_Y = None


def header_y(t):
    """Middle of the header: the title of the home page, the top text under the status bar. Taken
    once on the home page: on other pages the top text can be lower (run 40305428865: y 122 after
    the settings, and the taps missed the menu button)."""
    global HEADER_Y
    if HEADER_Y is not None:
        return HEADER_Y
    best = None
    for e in t:
        fr = e["frame"]
        if e.get("type") in ("Application", "Button") or not label(e) or fr["y"] < 30 or fr["y"] > header_bottom(t):
            continue
        if best is None or fr["y"] < best["frame"]["y"]:
            best = e
    HEADER_Y = centre(best)[1] if best else 86
    print(f"header middle: y {HEADER_Y:.0f}")
    return HEADER_Y


def tap_header(what):
    dismiss_alerts()
    t = tree()
    e = header_button(t)
    if e:
        print(f"  header button: type={e.get('type')} label={label(e)!r} frame={e['frame']}")
        tap_at(*centre(e), what)
    else:
        # not in the tree (no accessible name): where the icon is drawn, in line with the title
        y = header_y(t)
        print(f"  header button: not in the accessibility tree, tap by place at y {y:.0f}")
        tap_at(24, y, what + " (by place)")


def is_home(t):
    # the drawer entries are hidden from the tree while it is closed; the home page has the tiles
    return find("Settings", t) is None and find("Elapsed", t) is not None


def open_drawer():
    # right after the start the first taps on the menu button can get lost (run 40305428865):
    # tried again before the page is given up
    for attempt in range(3):
        tap_header("the menu button")
        t = tree()
        if find("Settings", t) is not None:
            return True
        print(f"  the drawer did not open (attempt {attempt + 1})")
        time.sleep(3)
    return False


def close_drawer():
    # the drawer covers the header button: a tap on the dimmed page to its right closes it
    w, h = screen(tree())
    tap_at(w * 0.93, h / 2, "the page beside the drawer")


def page(entry, name, wait=3, extra=None):
    """Drawer -> entry, a frame, optional extra steps, then back with the header arrow."""
    if not open_drawer():
        summary.append(f"{name}: drawer did not open")
        return
    if not tap(entry, scrolls=4):
        summary.append(f"{name}: no entry {entry!r} in the drawer")
        close_drawer()
        return
    time.sleep(wait)
    shot(name)
    if extra:
        extra()
        # the extra steps can end on the home page already (the arrow from the settings search
        # closes the settings, as the Android back does): no arrow then, it would open the drawer
        t = tree()
        if is_home(t):
            shot(name + "-back")
            summary.append(f"{name}: back -> home (inside the extra steps)")
            return
    tap_header("back from " + name)
    t = shot(name + "-back")
    back = "home" if is_home(t) else "NOT home"
    if back != "home":
        # one more arrow (a page with a step inside, as the settings search)
        tap_header("back again from " + name)
        t = shot(name + "-back2")
        back = "home after 2 arrows" if is_home(t) else "NOT home after 2 arrows"
    summary.append(f"{name}: back -> {back}")


def settings_extra():
    # a section first: General UI Options holds the settings of the modern look
    if tap("General UI Options", scrolls=10):
        shot("general-ui")
        swipe_up()
        shot("general-ui-2")
        swipe_up()
        shot("general-ui-3")
    # the search last: its arrow closes the settings (navigateBack, no handleBack step for typed text)
    if tap("Search settings", scrolls=3):
        shot("search")
        run("ui", "text", "speed")
        time.sleep(3)
        shot("search-speed")
        tap_header("back from the search")
        shot("search-back")


def wizard_extra():
    # the first page of the wizard has one button, Start; the arrow on the next page goes back one
    # step inside the wizard (Wizard.qml handleBack), not out of it
    if not tap("Start"):
        summary.append("wizard: no Start button")
        return
    shot("wizard-2")
    tap_header("back one step in the wizard")
    t = shot("wizard-step-back")
    # home first: its Start/Pause button is labelled Start too
    if is_home(t):
        summary.append("wizard: arrow on page 2 -> home (left the wizard)")
    elif find("Start", t) is not None:
        summary.append("wizard: arrow on page 2 -> page 1 of the wizard")
    else:
        summary.append("wizard: arrow on page 2 -> somewhere else")


dismiss_alerts()
t = shot("home")
summary.append("home: " + ("ok" if is_home(t) else "not recognised"))
if open_drawer():
    shot("drawer")
    close_drawer()
if os.environ.get("WALK") == "short":
    # T-293: the system bars on home, a settings page and a WebView page, then the system
    # appearance switched while the app runs (theme "auto" follows it within the 2 s timer)
    page("Settings", "settings")
    page("Workout Editor", "editor", wait=10)
    shot("home-again")
    switch_to = os.environ.get("SWITCH_TO", "")
    if switch_to:
        subprocess.run(["xcrun", "simctl", "ui", UDID, "appearance", switch_to], capture_output=True)
        time.sleep(6)
        shot("home-system-" + switch_to)
    print("SUMMARY")
    for line in summary:
        print("  " + line)
    sys.exit(0)
page("Settings", "settings", extra=settings_extra)
page("Wizard", "wizard", extra=wizard_extra)
page("Charts", "charts", wait=10)
page("Workout Editor", "editor", wait=10)
page("Workouts History", "history")
page("Open Train Program", "programs", wait=5)
page("Open GPX", "gpx")
page("Credits", "credits")
page("Profile", "profile")

print("SUMMARY")
for line in summary:
    print("  " + line)
