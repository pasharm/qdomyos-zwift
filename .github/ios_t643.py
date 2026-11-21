"""Test only (T-643): the buttons of the settings pages on UiButton in the iOS simulator - modern: the tonal pill,
the OK grey while unchanged, no OK after the Gender list (it saves on the pick); classic: as master.

usage: ios_t643.py <idb> <udid> <out_dir> <prefix> <case>
  case light | dark | classic - Settings > General Options (settings.qml:2860, first row "App Language:" :2873)
                 > the Player Weight row (:2930, SettingsNumberField and OK), then the Gender row (:3079,
                 ValueComboBox and okSex - hidden in the modern look)
  case tts     - modern light: TTS (Text to Speech) Settings (:17849, settings-tts.qml) > "Summary Each Seconds:"
                 (settings-tts.qml:57) with its OK
  case inc     - modern light: Treadmill Options (:11690, first row "Treadmill as a Bike") > Inclination Overrides
                 (:12147, settings-treadmill-inclination-override.qml) > "Inclination Override Gain:" (:41) and OK
  case changed - modern light: the settings search bar, the Changed filter on
  case tmpl    - modern light: Experimental Features > Template Settings > the WebServer template > its Port row
                 (TemplateWebServer.qml) and OK
SUMMARY line and exit code by the library (tools/ios/iosnav.py).
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from iosnav import (init, shot, wait_for, tap, page, summary, dismiss_alerts, tree, find_in, place,  # noqa: E402
                    middle, swipe, say)

init(*sys.argv[1:5])
CASE = sys.argv[5] if len(sys.argv) > 5 else "light"
# the menu button by its name: "◄" in the classic look, "Main menu" in the modern one (ios_t494.py of T-494)
MENU = "◄" if CASE == "classic" else "Main menu"


def bring(label, swipes=40, top=150):
    """Swipe the page until the row is on the screen below the header (middle y >= top, ios_t599.py); True - it
    is (its element said into the log)."""
    for _ in range(swipes + 1):
        t = tree()
        e = find_in(t, label)
        if e is not None:
            where = place(e, t)
            if where == "on" and middle(e)[1] < top:
                swipe("down")
                continue
            if where == "on":
                keys = ("AXLabel", "type", "role", "frame")
                say("row " + json.dumps({k: e.get(k) for k in keys}, ensure_ascii=False))
                return True
            swipe("up" if where == "below" else "down")
            continue
        swipe("up")
    say(f"not brought onto the screen: {label!r}")
    return False


def settings_section(title, landing):
    ok = tap(MENU, "Settings") and tap("Settings", "General Options")
    page("settings", ok)
    if ok:
        ok = tap(title, landing, scrolls=40)
        page(title.lower(), ok)
    return ok


dismiss_alerts()
ok = wait_for("Lap", exact=True)
page("home", ok)
if CASE in ("light", "dark", "classic"):
    if settings_section("General Options", "App Language:"):
        ok = bring("Player Weight")
        shot("weight")
        page("weight row", ok)
        ok = bring("Gender:")
        shot("gender")
        page("gender row", ok)
elif CASE == "tts":
    if settings_section("TTS (Text to Speech) Settings", "TTS Enabled"):
        ok = bring("Summary Each Seconds:")
        shot("tts")
        page("tts row", ok)
elif CASE == "inc":
    if settings_section("Treadmill Options", "Treadmill as a Bike"):
        # below the pinned header of the open section first (y 110-154 in the modern look): press() takes y >= 50
        ok = bring("Inclination Overrides") and tap("Inclination Overrides", "Treadmill Inclination Overrides")
        page("inclination overrides", ok)
        if ok:
            ok = bring("Inclination Override Gain:")
            shot("inc")
            page("inclination row", ok)
elif CASE == "changed":
    # modern light: the search bar of the settings (main.qml "Search settings"), the Changed filter on - the list
    # title "Changed settings (N)" (settings.qml ~2708)
    ok = tap(MENU, "Settings") and tap("Settings", "General Options")
    page("settings", ok)
    if ok:
        ok = tap("Search settings", "Changed")
        page("search bar", ok)
    if ok:
        ok = tap("Changed", "Changed settings")
        shot("changed")
        page("changed on", ok)
elif CASE == "tmpl":
    # modern light: Experimental Features (~17958) > Template Settings (~18907) > the WebServer template the app
    # makes itself ("user_<id> (WebServer)", templateinfosenderbuilder.cpp:246-264) > its Port row and OK
    ok = tap(MENU, "Settings") and tap("Settings", "General Options")
    page("settings", ok)
    if ok:
        ok = tap("Experimental Features", "Gym Mode", scrolls=60)
        page("experimental features", ok)
    if ok:
        ok = bring("Template Settings", swipes=60) and tap("Template Settings", "user_")
        page("template settings", ok)
    if ok:
        # by its full name: a bare "user_" is the first row, user_vlc (TcpClient) on a fresh install (44851642842)
        ok = bring("user_QZWS (WebServer)") and tap("user_QZWS (WebServer)", "user_QZWS Port:")
        page("webserver template", ok)
    if ok:
        ok = bring("user_QZWS Port:")
        shot("tmpl")
        page("template port row", ok)
    if ok:
        ok = bring("user_qz (TcpClient)") and tap("user_qz (TcpClient)", "user_qz Host:")
        page("tcpclient template", ok)
    if ok:
        ok = bring("user_qz Port:")
        shot("tmpl-tcp")
        page("tcpclient port row", ok)
else:
    say(f"unknown case {CASE!r}")
    page(CASE, False)
sys.exit(summary())
