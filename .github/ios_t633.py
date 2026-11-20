"""Test only (T-633, the walk of T-604): the 2D / 3D switch in the toolbar of the map page, iOS simulator, the new
look, the head of the PR: menu -> Open GPX -> Box Hill -> Open, Pause -> Start, then the map button of the home page
(maps_type=3D: googlemaps/maps.htm), the segment 2D (maps2d/maps.htm), the segment 3D (googlemaps/maps.htm again).

usage: ios_t633.py <idb> <udid> <out_dir> <prefix>

The segments are AbstractButtons with the text 2D / 3D (main.qml mapsTypeSwitch): their names in the tree. Which
page loaded is judged by the workflow on the QZ log (the web server logs each request, "Path" "maps2d/maps.htm",
webserverinfosender.cpp), in order: the first maps2d after the first googlemaps, a googlemaps after that maps2d.
The script prints a MARK line before each tap of a segment, so the log lines can be put next to the steps.
SUMMARY line and exit code by the library (tools/ios/iosnav.py, T-557).
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from iosnav import init, shot, tap, home, page, summary, dismiss_alerts, wait_for, say  # noqa: E402

init(*sys.argv[1:5])
MENU = "Main menu"
BACK = "Back"

dismiss_alerts()
shot("home")

# the GPX page; Box Hill is the first route and is selected when the page opens (T-530, run 43507076307)
ok = tap(MENU, "Open GPX") and tap("Open GPX", "Other folders") and wait_for("Box Hill", 60)
shot("gpx")
page("gpx", ok)

# Open loads the program and goes back home, where the map button shows
ok = ok and tap("Open", "Map")
shot("program")
page("program", ok)

# a GPX opened during a running session is not started; Pause, then Start starts it (ios_t604.py)
ok = ok and tap("Pause", "Start") and tap("Start", "Pause")
shot("started")
page("started", ok)
if ok:
    # give the program its first ticks (the GEO position, ticks == 1)
    time.sleep(20)
ok = ok and tap("Map", BACK)
if ok:
    time.sleep(15)
    shot("map-3d")
page("map", ok)

# the switch: 2D, then 3D; the landing is the segment itself (the page stays, the switch stays)
say("MARK segment 2D")
ok2 = ok and tap("2D", "3D")
if ok2:
    time.sleep(15)
    shot("map-2d")
page("switch-2d", ok2)
say("MARK segment 3D")
ok3 = ok2 and tap("3D", "2D")
if ok3:
    time.sleep(15)
    shot("map-3d-again")
page("switch-3d", ok3)
home(BACK)
sys.exit(summary())
