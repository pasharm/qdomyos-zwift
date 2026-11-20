# ios-lib: tools/ios/iosnav.py sha a66d48d6c995 - edit there, then tools/ios/sync.py (T-557)
"""Walk QZ in the iOS simulator by accessibility labels (idb) - the library of the iOS scenarios (T-557).

One source: tools/ios/iosnav.py of the work folder; `python tools/ios/sync.py wt/<name>` copies it into .github/ of
an iOS branch with a stamp (as tools/emu/sync.py does for the emulator). Before T-557 every scenario carried its
own copy of the helpers of .github/ios_nav.py (10 copies in notes/emu), and the fixes of one did not reach the
others: lessons 8 and 9 of T-514.

A scenario (.github/ios_<task>.py, run by the workflow as `python .github/ios_<task>.py <idb> <udid> <out> <prefix> ...`):

    import os, sys
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from iosnav import init, shot, find, wait_for, tap, tap_at, home, page, summary
    init(*sys.argv[1:5])
    shot("home")
    page("settings", tap("◄", "Settings") and tap("Settings", "General UI Options"))
    home("◄")
    sys.exit(summary())

What the library does, and the scenario must not redo:
  - tap(label, landing): only an element on the screen (describe-all gives the scrolled-away ones too, with their
    layout place: the modern menu put Credits at y 867 of 874, the tap hit nothing - lesson 8); one off the screen
    is swiped into the middle part first (scrolls); the landing - a label of the next screen - is required: True
    only when it showed. No landing - "missed", never "reached" by a timeout (lesson 8: landing None counted 15 s
    as reached in three runs).
  - home(back): the arrow, then a wait for the sign of the home page after each arrow (6fcb4efdb, lesson 9: the
    second arrow found the page still sliding out, the third one was not found). The sign - Lap: with the fake
    device the workout runs by itself, the button reads Pause, not Start (lesson 3, run 43036999474).
  - swipe(way, x=200) and survey(name): the page by a column off the side edges (x < 40 or past the width - 40 -
    ValueError: x 6 of ios_t561.py did not move the settings page in two runs, T-561 lesson 5); survey - a frame and
    a tree per screen to the end of the page. A scenario does not call idb("ui", "swipe", ...) itself:
    check_emu_script.py warns own-swipe.
  - page(name, ok) and summary(): "SUMMARY <prefix> reached a,b missed c" and the exit code (1 - a page missed).
  - find(label): the first element whose AXLabel is the label or starts with it (check_emu_script.py --dumps checks
    the labels of tap/wait_for/find against the .ui.json of a past run: unknown-anchor, prefix-anchor).

Tests: python -m unittest tools/ios/test_iosnav.py (a fake idb with screens and a clock - no simulator).
"""
import json
import subprocess
import time

# the sign of the home page (lesson 3 of T-514)
HOME_SIGN = "Lap"
# an element whose middle is this close to the bottom edge is under the home indicator / off the screen (lesson 8)
BOTTOM_GAP = 40
# and to the top: the status bar. Not the page header (y 62-110): the open menu puts its first entry there over the
# header ("Profile: default" at y 62 in the classic look), the modern header has its own buttons in that row
# ("Unlock tiles", "Disable auto resistance") - all on the screen, and the tree does not tell them from content
# scrolled under the header (t468 s-04 "Player Age:" at y 62). Checked on the menu trees of run 43655378751 (T-557,
# a bound at the header bottom made the entry and the buttons untappable)
TOP_GAP = 50
# after a tap the page and the tree come in 5-30 s (more on the x86_64 slice): the default wait for a landing
LANDING_WAIT = 90
# the column of the swipes, and how close to a side edge a swipe is refused (T-561, lesson 5)
SWIPE_X = 200
EDGE_GAP = 40

IDB = UDID = OUT = PREFIX = None
_run = None
_sleep = time.sleep
_clock = time.time
_step = 0
_tapped_at = 0.0
_reached = []
_missed = []
_width = 402  # of the last tree: swipe() refuses a column by a side edge without one more describe-all


def _subprocess(argv):
    r = subprocess.run(argv, capture_output=True, text=True)
    return r.returncode, r.stdout, r.stderr


def _popen(argv):
    return subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)


_spawn = _popen


def init(idb, udid, out, prefix, runner=None, sleep=None, clock=None, spawn=None):
    """Set the simulator and the output; runner(argv) -> (code, stdout, stderr), sleep, clock and spawn(argv) ->
    a process with communicate() and returncode (hold) - for the tests."""
    global IDB, UDID, OUT, PREFIX, _run, _sleep, _clock, _spawn, _step, _tapped_at, _reached, _missed, _width
    IDB, UDID, OUT, PREFIX = idb, udid, out, prefix
    _width = 402
    _run = runner or _subprocess
    _sleep = sleep or time.sleep
    _clock = clock or time.time
    _spawn = spawn or _popen
    _step = 0
    _tapped_at = _clock()
    _reached, _missed = [], []


def stamp():
    return time.strftime("%H:%M:%S", time.gmtime(_clock()))


def say(*words):
    print(stamp(), *words, flush=True)


def idb(*args):
    return _run([IDB, *args, "--udid", UDID])


def tree():
    """The accessibility tree (idb ui describe-all). Right after a relaunch it can come back as one empty element:
    asked again, up to 10 times."""
    t = []
    for _ in range(10):
        code, out, err = idb("ui", "describe-all", "--json")
        try:
            t = json.loads(out)
        except ValueError:
            say("describe-all:", (err or "")[-500:])
            t = []
        if isinstance(t, list) and len(t) > 1:
            global _width
            _width = screen(t)[0]
            return t
        _sleep(3)
    say("describe-all: empty tree")
    return t if isinstance(t, list) else []


def screen(t=None):
    """(width, height) of the screen in points: the frame of the app element, the first of the tree."""
    t = tree() if t is None else t
    if t and isinstance(t[0], dict) and "frame" in t[0]:
        return t[0]["frame"]["width"], t[0]["frame"]["height"]
    return 402, 874


def middle(e):
    fr = e["frame"]
    return fr["x"] + fr["width"] / 2, fr["y"] + fr["height"] / 2


def place(e, t):
    """Where the middle of the element is: "on", "above" (under the status bar), "below" the screen, or "aside"
    (left or right of it)."""
    w, h = screen(t)
    x, y = middle(e)
    if y < TOP_GAP:
        return "above"
    if y > h - BOTTOM_GAP:
        return "below"
    if x < 0 or x > w:
        return "aside"
    return "on"


def find_in(t, label, exact=False):
    for e in t:
        text = (e.get("AXLabel") if isinstance(e, dict) else None) or ""
        if text == label or (not exact and text.startswith(label)):
            return e
    return None


def find(label, exact=False):
    """The first element whose AXLabel is the label or (exact=False) starts with it, on the screen or not; None -
    none. A sign of a screen - exact=True: "Lap" starts "Lap Elapsed" of the tiles page too."""
    return find_in(tree(), label, exact)


def shot(name, with_tree=True):
    """A frame and the tree of the step: <out>/<prefix>-NN-<name>.png and .ui.json (with_tree=False - the frame
    alone: the tree costs 5-30 s more, too long inside a hold)."""
    global _step
    _step += 1
    base = f"{OUT}/{PREFIX}-{_step:02d}-{name}"
    _run(["xcrun", "simctl", "io", UDID, "screenshot", base + ".png"])
    if with_tree:
        with open(base + ".ui.json", "w", encoding="utf-8") as f:
            json.dump(tree(), f, ensure_ascii=False, indent=1)
    say("frame", base)
    return base


HOLD = 20.0  # a hold of idb ui tap --duration: idb and simctl on the x86_64 simulator take 5-56 s a call (T-554)
HOLD_MID = 8.0  # the frame of the hold is started this long after idb


def hold(label, name, secs=HOLD, mid=HOLD_MID):
    """Hold the element for secs seconds (idb ui tap --duration, in the background), a frame mid seconds after the
    start, then a frame right after the release. True only when the hold frame was done before the release and idb
    ended with 0: a frame done later shows the released control (T-554, lesson 7: the frame of a 3 s hold came 17 s
    after it, of a 20 s hold - 38-56 s in dark and classic), and a page on such a frame is missed, not reached.
    Not checked: the start of the press - t0 is taken when idb is spawned, and idb may start the touch later; a frame
    of the untouched control is caught only by looking at it. idb not done secs + 60 s after the frame - killed,
    False."""
    global _tapped_at
    dismiss_alerts()
    t = tree()
    e = find_in(t, label)
    if e is None or place(e, t) != "on":
        say(f"hold {label!r}: not on the screen - not held")
        return False
    x, y = middle(e)
    say(f"hold {label!r} at {x:.0f},{y:.0f} for {secs} s")
    p = _spawn([IDB, "ui", "tap", str(round(x)), str(round(y)), "--duration", str(secs), "--udid", UDID])
    t0 = _clock()
    _sleep(mid)
    shot(name + "-hold", with_tree=False)
    took = _clock() - t0
    in_time = took <= secs
    say(f"the hold frame done {took:.1f} s after the start of idb (hold {secs} s)"
        + ("" if in_time else " - after the release: it does not show the hold"))
    try:
        _, err = p.communicate(timeout=secs + 60)
    except subprocess.TimeoutExpired:
        p.kill()
        p.communicate()
        say(f"hold {label!r}: idb not done {secs + 60:.0f} s after the frame - killed")
        _tapped_at = _clock()
        return False
    _tapped_at = _clock()
    say(f"released, idb code {p.returncode} {(err or '').strip()[-300:]}")
    shot(name + "-release", with_tree=False)
    return in_time and p.returncode == 0


def dismiss_alerts():
    """A system question of iOS ("... Would Like to Send You Notifications") covers the app: Allow."""
    for _ in range(3):
        t = tree()
        if not any("Would Like" in ((e.get("AXLabel") if isinstance(e, dict) else None) or "") for e in t):
            return
        for e in t:
            if (e.get("AXLabel") or "") in ("Allow", "OK", "Allow While Using App"):
                x, y = middle(e)
                say("tap the system question:", e["AXLabel"])
                idb("ui", "tap", str(round(x)), str(round(y)))
                _sleep(3)
                break
        else:
            return


def wait_for(label, timeout=LANDING_WAIT, exact=False):
    """Wait for a label in the tree (on the screen or not); says how long after the last tap it came."""
    end = _clock() + timeout
    while True:
        if find(label, exact):
            say(f"seen {label!r} {_clock() - _tapped_at:.0f} s after the tap")
            return True
        if _clock() >= end:
            break
        _sleep(2)
    say(f"not seen in {timeout} s: {label!r}")
    return False


def _column(x):
    if not EDGE_GAP <= x <= _width - EDGE_GAP:
        raise ValueError(f"swipe at x {x}: closer than {EDGE_GAP} pt to a side edge of the {_width} pt screen - the "
                         f"page does not move there (T-561, lesson 5); x {SWIPE_X} or a column off the controls")


def swipe(way, x=SWIPE_X, dist=300, duration=0.5):
    """A swipe of the page by dist points: "up" brings what is below into the screen, "down" - what is above. x 200
    of a 402 pt wide iPhone: inside the menu of both looks as well. Another column only when x 200 lies on a control
    that takes the drag (the -/+ of a SpinBox changed the number instead: T-561, lesson 3), and never by a side edge -
    ValueError (x 6: the settings page stood still in 25 swipes of two runs, lesson 5)."""
    if way not in ("up", "down"):
        raise ValueError(f"swipe {way!r}: up or down")
    _column(x)
    a, b = (650, 650 - dist) if way == "up" else (350, 350 + dist)
    idb("ui", "swipe", str(round(x)), str(a), str(round(x)), str(b), "--duration", str(duration))
    _sleep(2)



def _signature(t):
    return [((e.get("AXLabel") or ""), (e.get("AXValue") or ""), round((e.get("frame") or {}).get("y", 0)))
            for e in t if isinstance(e, dict)]


def survey(name, n=30, x=SWIPE_X, dist=300):
    """The page from where it is down to its end: a frame and a tree per screen (<prefix>-NN-<name>-sMM), a swipe up
    between; the end - the tree did not change after a swipe. True - the end reached; False - no end in n swipes (the
    swipe fell on a control that takes it, or the page does not move by that column - T-561, lessons 3 and 5)."""
    _column(x)
    prev = None
    for i in range(n + 1):
        base = shot(f"{name}-s{i:02d}")
        try:
            with open(base + ".ui.json", encoding="utf-8") as f:
                t = json.load(f)
            sig = _signature(t) if isinstance(t, list) and len(t) > 1 else None
        except (OSError, ValueError):
            sig = None
        # an empty tree (describe-all gave nothing 10 times) is no sign of the end: two such are equal too
        if prev and sig == prev:
            say(f"survey {name}: the end after {i} swipes")
            return True
        prev = sig
        if i < n:
            swipe("up", x, dist)
    say(f"survey {name}: no end in {n} swipes")
    return False


def _press(x, y, what):
    global _tapped_at
    say(f"tap {what} at {x:.0f},{y:.0f}")
    idb("ui", "tap", str(round(x)), str(round(y)))
    _tapped_at = _clock()


def press(label, scrolls=3):
    """Tap the element on the screen, no landing: for the library (home) and a step whose landing is checked
    by the scenario right after. True - tapped; False - not found or not brought onto the screen."""
    dismiss_alerts()
    waited = False
    i = 0
    while i <= scrolls:
        t = tree()
        e = find_in(t, label)
        if e is not None and place(e, t) == "aside" and not waited:
            # the menu drawer slides in from the left, a page of StackView from the right: the tree has the element
            # before the animation ends - once more after it, not a miss at once
            waited = True
            _sleep(2)
            continue
        i += 1
        if e is None:
            if i <= scrolls:
                swipe("up")
                continue
            say(f"not found: {label!r}")
            return False
        where = place(e, t)
        if where == "on":
            x, y = middle(e)
            _press(x, y, repr(label))
            return True
        if i <= scrolls and where in ("above", "below"):
            say(f"{label!r} {where} the screen (y {middle(e)[1]:.0f}): swipe")
            swipe("up" if where == "below" else "down")
            continue
        say(f"{label!r} not on the screen ({where}, y {middle(e)[1]:.0f}) - not tapped")
        return False
    return False


def tap(label, landing, timeout=LANDING_WAIT, scrolls=3):
    """Tap the element on the screen and wait for the landing - a label of the next screen. True only when the
    landing showed. landing is required: a tap without one proves nothing (lesson 8 of T-514)."""
    if not landing:
        raise ValueError(f"tap({label!r}): a landing label is required - a tap without one proves nothing")
    if not press(label, scrolls):
        return False
    return wait_for(landing, timeout)


def tap_at(x, y, landing, what="a point", timeout=LANDING_WAIT):
    """Tap a point (a row with no name in the tree: the classic program rows) and wait for the landing."""
    if not landing:
        raise ValueError(f"tap_at({x}, {y}): a landing label is required")
    dismiss_alerts()
    _press(x, y, what)
    return wait_for(landing, timeout)


def on_home(sign=HOME_SIGN):
    """The sign of the home page, exactly: the classic tiles page has "Lap Elapsed" in its tree (below the screen),
    a prefix match took it for the home page (review of T-557, dump t513 head-classic-02-tiles-01)."""
    return find(sign, exact=True) is not None


def home(back, sign=HOME_SIGN, depth=12, settle=15):
    """Back to the home page: the arrow, then up to `settle` s for the sign after each arrow (a page slides out for
    seconds: the next arrow too early hits the page under it, or nothing - lesson 9). In the classic look the arrow
    of a page and the menu button of the home page are the same "◄": the sign is checked before every arrow, so an
    arrow more than the pages is never pressed. `depth` 12, not the count of pages the scenario thinks it is in: the
    arrow of the modern look goes one step back (main.qml toolButton -> navigateBack), a wizard page needs an arrow
    per step (T-575, lesson 5: 3 arrows from Zwift Credentials, the run red). Not home - the labels of the screen it
    stopped on go to the log. The arrows stop early when a screen comes back (the arrow did nothing, or the menu
    opened and closed - the sign is not found): 12 such arrows cost minutes of idb (review of T-575 lesson 5)."""
    seen = []
    for _ in range(depth):
        if on_home(sign):
            return True
        if not press(back, scrolls=0):
            # the page may still be sliding out: the home page comes a moment later with no arrow to find
            ok = wait_for(sign, 30, exact=True)
            if not ok:
                say(f"not on the home page ({sign!r}), no {back!r}; on the screen: {_labels_on()}")
            return ok
        end = _clock() + settle
        t = []
        while _clock() < end:
            t = tree()
            if find_in(t, sign, exact=True) is not None:
                return True
            _sleep(2)
        now = tuple((e.get("AXLabel") or "", e.get("AXValue") or "") for e in t if isinstance(e, dict))
        if now in seen[-2:]:
            say(f"not on the home page ({sign!r}): the screen came back after an arrow; on the screen: {_labels_on()}")
            return False
        seen.append(now)
    ok = on_home(sign)
    if not ok:
        say(f"not on the home page ({sign!r}) after {depth} arrows; on the screen: {_labels_on()}")
    return ok


def _labels_on(n=8):
    """The first `n` labels on the screen - where a walk stopped, for the log."""
    t = tree()
    return [e.get("AXLabel") for e in t if isinstance(e, dict) and e.get("AXLabel") and place(e, t) == "on"][:n]


def page(name, ok):
    """Record a page of the walk: reached or missed."""
    (_reached if ok else _missed).append(name)
    say(f"page {name}: {'reached' if ok else 'missed'}")
    return ok


def summary(expected=None):
    """Print "SUMMARY <prefix> reached ... missed ..." and give the exit code: 1 when a page was missed, none was
    reached, or fewer than `expected` were reached."""
    print("SUMMARY", PREFIX, "reached", ",".join(_reached) or "-", "missed", ",".join(_missed) or "-", flush=True)
    if _missed or not _reached:
        return 1
    if expected is not None and len(_reached) < expected:
        return 1
    return 0
