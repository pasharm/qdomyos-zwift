#!/bin/bash
# Test only: start an already built APK on the emulator with log_debug on, so the Qt
# warnings (QML errors among them) reach logcat, then keep logcat and screenshots.
# The emulator starts in the day mode of the system: with the appearance on "auto" the
# first screens are the light theme, the last ones the dark theme after "night yes".
#
# UI_MODERN (workflow input "modern"): false runs the same steps in the classic look, for a
# before/after comparison. The two looks place their controls differently, so the steps
# find a control by its text or accessible name in a uiautomator dump (tap_ui, .github/
# uitap.py) and use fixed coordinates only when the dump has no such control. steps.log
# says which way every tap went; dumps/<shot>.xml is the control tree behind every shot.
PKG=org.cagnulen.qdomyoszwift
UI_MODERN=${UI_MODERN:-true}
# LOG_DEBUG (workflow input "log_debug"): false runs with the debug log off, to see that the app
# works without it and writes no log file. QML errors do not reach logcat then.
LOG_DEBUG=${LOG_DEBUG:-true}
STEPLOG=steps.log
: > $STEPLOG
mkdir -p dumps

adb install apk-debug/android-debug.apk
for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION BLUETOOTH_ADVERTISE BLUETOOTH_CONNECT BLUETOOTH_SCAN POST_NOTIFICATIONS; do
  adb shell pm grant $PKG android.permission.$p || true
done
adb shell appops set $PKG MANAGE_EXTERNAL_STORAGE allow || true
adb shell cmd uimode night no || true
# The launcher of the emulator image hangs on the slow CI machine and its "isn't responding"
# dialog came back before every step, however often Wait was tapped: the classic run
# 36505671077 got the dialog on nearly every shot. No error dialogs at all for the run; an
# ANR still reaches logcat and the end of steps.log ("ANR in")
adb shell settings put global hide_error_dialogs 1 || true

# T-060, T-066: a fake treadmill, so the home page has tiles (without a device it shows the search help)
# T-119: values of every kind the results show as text - a real number, an integer, a list of
# strings, a list of numbers with labels, a password, a MyWhoosh state key (hidden from the results)
printf '[General]\nlog_debug=%s\nconfirm_stop_workout=true\nui_modern=%s\napplewatch_fakedevice=true\nweight=80.5\nftp=250\nstrava_upload_mode=Request\nzwiftplay_gear_lb=1\nfloatingwindow_type=1\npzp_password=secret\nmywhoosh_link_camera_value=3\n' "$LOG_DEBUG" "$UI_MODERN" > qz.conf
adb push qz.conf /data/local/tmp/qz.conf
adb shell "run-as $PKG mkdir -p 'files/.config/Roberto Viola'"
adb shell "run-as $PKG cp /data/local/tmp/qz.conf 'files/.config/Roberto Viola/qDomyos-Zwift.conf'"
adb shell "run-as $PKG ls -la 'files/.config/Roberto Viola'" || true

# The control tree of the screen into ui.xml (empty when uiautomator gives up, for instance
# while something animates without pause)
dump() {
  rm -f ui.xml
  timeout 25 adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1 || true
  adb pull /sdcard/ui.xml ui.xml > /dev/null 2>&1 || true
}
# The emulator itself may put a window over the app: "Pixel Launcher isn't responding", or
# the Health Connect screen left over when the back key went to such a dialog. They made a
# whole run useless once. Clear them before every step: Wait on a "not responding" dialog,
# the back key on anything else that is not the app. Logged in steps.log.
ensure_app() {
  local i pkg xy
  for i in 1 2 3; do
    dump
    [ -f ui.xml ] || return 0
    pkg=$(python3 .github/uitap.py ui.xml --package)
    [ -z "$pkg" ] || [ "$pkg" = "$PKG" ] && return 0
    # Somebody else hanging (the launcher) is closed, the app itself is waited for
    if grep -q "t responding" ui.xml && ! grep -q "QZ\|qdomyos" ui.xml &&
       xy=$(python3 .github/uitap.py ui.xml 'Close app'); then
      echo "!! $pkg: another app not responding, Close app at $xy" >> $STEPLOG
      adb shell input tap $xy || true
    elif grep -q "t responding" ui.xml && xy=$(python3 .github/uitap.py ui.xml 'Wait'); then
      echo "!! $pkg not responding: Wait at $xy" >> $STEPLOG
      adb shell input tap $xy || true
    else
      echo "!! $pkg over the app: back key" >> $STEPLOG
      adb shell input keyevent KEYCODE_BACK || true
    fi
    sleep 3
  done
  # The last dump showed the window that was then closed: not the screen any more
  rm -f ui.xml
}
# ensure_app leaves ui.xml of the app on top: the callers take it instead of a second dump
# of the same screen (a dump costs about 2 s, half of all dumps of a run were such repeats)
shot() {
  if [ "$1" = "01-healthconnect" ]; then rm -f ui.xml; else ensure_app; fi
  echo "-- shot $1" >> $STEPLOG
  adb shell screencap -p /sdcard/$1.png || true
  adb pull /sdcard/$1.png || true
  [ -f ui.xml ] || dump
  [ -f ui.xml ] && cp ui.xml dumps/$1.xml
}
# tap_ui 'regex' [x y]: the control whose whole text or accessible name matches, else the
# fallback coordinates; without them the step is skipped (return 1)
tap_ui() {
  local rx="$1" fx="$2" fy="$3" xy=""
  ensure_app
  [ -f ui.xml ] || dump
  [ -f ui.xml ] && xy=$(python3 .github/uitap.py ui.xml "$rx")
  if [ -n "$xy" ]; then
    echo "tap '$rx': by label at $xy" >> $STEPLOG
    adb shell input tap $xy || true
  elif [ -n "$fx" ]; then
    echo "tap '$rx': NOT FOUND, coordinates $fx $fy" >> $STEPLOG
    adb shell input tap $fx $fy || true
  else
    echo "tap '$rx': NOT FOUND, skipped" >> $STEPLOG
    return 1
  fi
}
# The same for a drawer entry that may be below the fold: one swipe up and a second look
tap_drawer() {
  local rx="$1" xy=""
  dump
  [ -f ui.xml ] && xy=$(python3 .github/uitap.py ui.xml "$rx")
  if [ -z "$xy" ]; then
    adb shell input swipe 500 2200 500 900 400 || true
    sleep 2
  fi
  tap_ui "$@"
}
# scroll_to 'regex': swipe the page up until the control shows (at most 12 swipes)
scroll_to() {
  local i
  for i in $(seq 1 12); do
    dump
    if [ -f ui.xml ] && python3 .github/uitap.py ui.xml "$1" > /dev/null; then
      echo "scroll to '$1': found after $((i - 1)) swipes" >> $STEPLOG
      return 0
    fi
    adb shell input swipe 700 2000 700 1300 400 || true
    sleep 1
  done
  echo "scroll to '$1': NOT FOUND" >> $STEPLOG
  return 1
}
# The top of a page: a few quick swipes down
scroll_top() {
  local i
  for i in 1 2 3 4 5; do adb shell input swipe 700 800 700 2200 150 || true; done
  sleep 1
}
# The back key closes the keyboard, but only while it is shown: otherwise it leaves the page
hide_keyboard() {
  if adb shell dumpsys input_method | grep -q "mInputShown=true"; then
    back "keyboard"
    sleep 1
  fi
}
tap() { ensure_app; echo "tap $1 $2 ($3)" >> $STEPLOG; adb shell input tap $1 $2 || true; }
back() { echo "back ($1)" >> $STEPLOG; adb shell input keyevent KEYCODE_BACK || true; }
# Toolbar buttons are icons without text: the same place in both looks (Nexus 6: 1440x2560
# px, 3.5 px per dp)
MENU="84 168"          # menu on the home page, back arrow elsewhere
LOCK="1187 168"        # tile lock on the home page
open_menu() { tap $MENU "menu"; sleep 3; adb shell input swipe 500 700 500 2300 300 || true; sleep 2; }

adb logcat -c || true
# Recorded from the start: a dump at the end (logcat -d) has lost the first lines of the app by
# then - the main buffer wraps in a long run, so the version line and the settings dump of
# main() were missing in the runs of the modern look
adb logcat > full_logcat.txt 2>/dev/null &
LOGCAT_PID=$!
adb shell am start -n $PKG/$PKG.CustomQtActivity
sleep 20
shot 01-healthconnect
# Only while that screen is on top: once it had closed by itself and the back key closed
# the first-run wizard instead
if [ -f ui.xml ] && [ "$(python3 .github/uitap.py ui.xml --package)" = "$PKG" ]; then
  echo "health connect screen not shown: no back key" >> $STEPLOG
else
  back "health connect"
fi
sleep 30
shot 02-first-screen        # the wizard opens on the first run
# T-060: with the fake treadmill the wizard does not open; its back keys would leave the app
shot 04-home

# T-095: the Charts page updates itself while the workout runs (fake bike: the session grows
# by a point a second), the period selector at the top right shows only then, and the page
# opened by Stop draws once and keeps its selector hidden.
wait_tiles() {
  local i
  # The fake bike comes after the first search ends: wait for its tiles (at most 3 min)
  for i in $(seq 1 18); do
    dump
    if [ -f ui.xml ] && grep -q 'content-desc="Speed' ui.xml; then
      echo "tiles shown after $i looks" >> $STEPLOG; return 0
    fi
    sleep 10
  done
  echo "!! tiles NOT shown" >> $STEPLOG
}
# The texts of the page (WebView nodes) with a digit or the selector, into steps.log
page() {
  dump
  echo "page ($1):" >> $STEPLOG
  [ -f ui.xml ] && python3 -c '
import re, sys, xml.etree.ElementTree as ET
for n in ET.parse(sys.argv[1]).getroot().iter("node"):
    t, d = n.get("text") or "", n.get("content-desc") or ""
    if re.search(r"[0-9]|Live|update|Off|screen|Swipe", t + d):
        print("   ", n.get("class"), repr(t), repr(d), n.get("bounds"))
' ui.xml | head -40 >> $STEPLOG
  cp ui.xml dumps/page-$1.xml 2>/dev/null || true
}

# Taps the node matching rx that is the lowest on the screen, or of class cls when given:
# the Stop of the confirmation lies under the Stop button, the select under its label
tap_node() {
  local rx="$1" cls="$2" xy=""
  dump
  [ -f ui.xml ] && xy=$(python3 -c '
import re, sys, xml.etree.ElementTree as ET
rx, cls = sys.argv[2], sys.argv[3]
best = None
for n in ET.parse(sys.argv[1]).getroot().iter("node"):
    t = (n.get("text") or "") or (n.get("content-desc") or "")
    if not re.fullmatch(rx, t, re.I) or (cls and n.get("class") != cls):
        continue
    m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", n.get("bounds") or "")
    if not m:
        continue
    x1, y1, x2, y2 = map(int, m.groups())
    if x2 <= x1 or y2 <= y1:
        continue
    if best is None or y1 > best[1]:
        best = ((x1 + x2) // 2, y1, (y1 + y2) // 2)
if best:
    print(best[0], best[2])
' ui.xml "$rx" "$cls")
  if [ -n "$xy" ]; then
    echo "tap node '$rx' ${cls:+($cls) }at $xy" >> $STEPLOG
    adb shell input tap $xy || true
  else
    echo "!! tap node '$rx' ${cls:+($cls) }NOT FOUND" >> $STEPLOG
    return 1
  fi
}
has() {
  dump
  if [ -f ui.xml ] && python3 .github/uitap.py ui.xml "$1" > /dev/null; then
    echo "check '$1' ($2): OK" >> $STEPLOG
  else
    echo "!! check '$1' ($2): NOT FOUND" >> $STEPLOG
  fi
}

# T-240: "Changed" in the search bar lists the settings that differ from their default.
# qz.conf above changes Debug Log, Confirm Stop Workout, Fake Device and Player Weight; it also
# writes a password (pzp_password), a MyWhoosh state key and a value equal to its default
# (bike_weight=0) - none of them may be listed. Expected: "Changed settings (4)".
CHANGED='^Changed settings.*'
has_quiet() {
  dump
  [ -f ui.xml ] && python3 .github/uitap.py ui.xml "$1" > /dev/null
}
not_has() {
  dump
  if [ -f ui.xml ] && python3 .github/uitap.py ui.xml "$1" > /dev/null; then
    echo "!! check no '$1' ($2): SHOWN" >> $STEPLOG
  else
    echo "check no '$1' ($2): OK" >> $STEPLOG
  fi
}
# The headers and card titles of the results, into steps.log
results() {
  dump
  echo "results ($1):" >> $STEPLOG
  [ -f ui.xml ] && python3 -c '
import re, sys, xml.etree.ElementTree as ET
for n in ET.parse(sys.argv[1]).getroot().iter("node"):
    t = (n.get("text") or "") or (n.get("content-desc") or "")
    if t and n.get("bounds") != "[0,0][0,0]":
        print("   ", repr(t), n.get("bounds"))
' ui.xml | head -60 >> $STEPLOG
}
# The toolbar button is named "Search settings" too: the bar is open when Changed shows
open_search() {
  if ! has_quiet '^Changed$'; then
    tap_ui '🔍|Search settings'
    sleep 2
  fi
}
type_query() {
  # The field of the bar, not the toolbar button of the same name (y below the toolbar)
  # Modern look: the bar scrolls away with the results (after find_card it was off the top and
  # the tap opened a result instead)
  scroll_top
  tap 470 338 "search field"
  sleep 1
  # The tap puts the cursor where it lands, the deletes take only what is before it (T-119:
  # "theme" became "themew type"): to the end first
  adb shell input keyevent KEYCODE_MOVE_END || true
  for i in $(seq 1 30); do adb shell input keyevent KEYCODE_DEL || true; done
  [ -n "$1" ] && adb shell input text "$1"
  sleep 3
  hide_keyboard
}

# T-119: in the modern look a search result shows its value as text and has no editor of its
# own (no switch, no field with OK, no list); a tap opens the setting on its page. The classic
# look keeps the editors of master: the same steps there are the comparison.
# The value is a Label of its own: in the dump a node whose content-desc is the value.
# Editors in the dump: a switch is a checkable node, the field has OK, a page has Open.
editors() {
  dump
  [ -f ui.xml ] && python3 -c '
import sys, xml.etree.ElementTree as ET
sw = ok = op = 0
for n in ET.parse(sys.argv[1]).getroot().iter("node"):
    t = (n.get("text") or "") or (n.get("content-desc") or "")
    if n.get("bounds") == "[0,0][0,0]":
        continue
    sw += n.get("checkable") == "true"
    ok += t == "OK"
    op += t == "Open"
print(sw, ok, op)
' ui.xml
}
# check_editors <what>: none in the modern look, master's in the classic one (logged only)
check_editors() {
  local e
  e=$(editors)
  if [ "$UI_MODERN" = "true" ]; then
    if [ "$e" = "0 0 0" ]; then
      echo "check no editors in the results ($1): OK" >> $STEPLOG
    else
      echo "!! check no editors in the results ($1): switches/OK/Open = $e" >> $STEPLOG
    fi
  else
    echo "classic editors ($1): switches/OK/Open = $e" >> $STEPLOG
  fi
}
# value_is 'Title' 'value regex': in the modern look the card shows that value. The card is a
# button named "Title: value" (the value Label alone would match any card of the screen)
value_is() {
  [ "$UI_MODERN" = "true" ] || return 0
  has "^$1: $2\$" "$1 shows $2"
}
# value_none 'Title': the card has no value at all (named by the title alone)
value_none() {
  [ "$UI_MODERN" = "true" ] || return 0
  not_has "^$1: .*" "$1 shows no value"
}
# card_xy 'name regex': the centre of the result card (the button from the card's left edge, not
# a label inside it - a path label "Wahoo Options" is in every card of that page) on the screen
card_xy() {
  dump
  [ -f ui.xml ] && python3 -c '
import re, sys, xml.etree.ElementTree as ET
for n in ET.parse(sys.argv[1]).getroot().iter("node"):
    t = (n.get("text") or "") or (n.get("content-desc") or "")
    m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", n.get("bounds") or "")
    if m and re.fullmatch(sys.argv[2], t):
        x1, y1, x2, y2 = map(int, m.groups())
        if x1 < 60 and x2 > x1 and y2 > y1 and y1 > 470:
            print((x1 + x2) // 2, (y1 + y2) // 2)
            break
' ui.xml "$1"
}
# find_card 'name regex' [what]: scrolls the results from the top until that card shows (12 swipes
# at most); logged as a check
find_card() {
  local i xy
  scroll_top
  for i in $(seq 1 12); do
    xy=$(card_xy "$1")
    if [ -n "$xy" ]; then
      echo "check card '$1' ($2): OK after $((i - 1)) swipes" >> $STEPLOG
      return 0
    fi
    adb shell input swipe 700 2000 700 1300 400 || true
    sleep 1
  done
  echo "!! check card '$1' ($2): NOT FOUND" >> $STEPLOG
  return 1
}
tap_card() {
  local xy
  find_card "$1" "$2" || return 1
  xy=$(card_xy "$1")
  echo "tap card '$1' at $xy" >> $STEPLOG
  adb shell input tap $xy || true
}
# The switch of a row named exactly 'name', tapped at its right end; its state into steps.log
toggle_switch() {
  local xy
  dump
  xy=$([ -f ui.xml ] && python3 -c '
import re, sys, xml.etree.ElementTree as ET
for n in ET.parse(sys.argv[1]).getroot().iter("node"):
    t = (n.get("text") or "") or (n.get("content-desc") or "")
    m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", n.get("bounds") or "")
    if t == sys.argv[2] and n.get("checkable") == "true" and m:
        x1, y1, x2, y2 = map(int, m.groups())
        print(x2 - 70, (y1 + y2) // 2)
        break
' ui.xml "$1")
  if [ -n "$xy" ]; then
    echo "tap switch '$1' at $xy" >> $STEPLOG
    adb shell input tap $xy || true
  else
    echo "!! tap switch '$1' NOT FOUND" >> $STEPLOG
  fi
  sleep 2
  dump
  [ -f ui.xml ] && python3 -c '
import sys, xml.etree.ElementTree as ET
for n in ET.parse(sys.argv[1]).getroot().iter("node"):
    t = (n.get("text") or "") or (n.get("content-desc") or "")
    if t == sys.argv[2] and n.get("checkable") == "true":
        print("switch " + sys.argv[2] + " checked=" + str(n.get("checked")))
        break
' ui.xml "$1" >> $STEPLOG
}
# query 'text' shot: a new search (spaces as %s for adb), its results into steps.log
query() {
  type_query "$1"
  sleep 2
  shot "q-$2"
  results "$1"
}

open_menu
shot s-menu
tap_drawer '^Settings$' 400 900
sleep 8
shot s-00
open_search
hide_keyboard
shot q-bar

query 'weight' weight
has '^Search results.*' "results for weight"
check_editors "weight"
# With T-211 the title carries the unit of its page: "Player Weight (kg)"
value_is 'Player Weight \(kg\)' '80\.5'
value_is 'Use kg for weight' 'Off'

query 'ftp%svalue' ftp
value_is 'FTP value' '250'

query 'debug%slog' debug
[ "$LOG_DEBUG" = "true" ] && value_is 'Debug Log' 'On'
check_editors "debug log"

query 'strava%supload' strava
value_is 'Strava Upload' 'Request'

query 'power%sup' powerup
value_is 'Power Up \(LB\)' 'Gear Up'

query 'floating%swindow%stype' floating
value_is 'Floating Window Type' 'Horizontal'

query 'theme' theme
value_is 'Theme' 'Graphite'
check_editors "theme"

query 'specific%smodel' model
value_is 'Specific Model' 'Other'
check_editors "specific model"

query '5%skm%space' pace
value_is '5 km pace \(total time\)' '00:25:00'

# A Bluetooth device and a password: no value at all
query 'heart%sbelt' belt
value_none 'Heart Belt Name'
query 'password' password
not_has '^secret$|.*: secret$' "a password is never shown"
value_none 'PZP Password'

# Hidden from the modern results: on no settings page
query 'camera' camera
[ "$UI_MODERN" = "true" ] && not_has '^Camera Action$' "MyWhoosh camera is not listed"
query 'peloton%sbike%socr' ocr
[ "$UI_MODERN" = "true" ] && not_has '^Peloton Bike OCR$' "Peloton Bike OCR is not listed"

# A page among the results: a chevron instead of Open
query 'wahoo' wahoo
has '^Wahoo Options$' "Wahoo Options page listed"
check_editors "wahoo"
[ "$UI_MODERN" = "true" ] && find_card '^Without Wheel Diameter Protocol: Off$' "the Wahoo switch shows Off"
# The page card itself (catalogKind page): it keeps the query on the way out (no jump), and back
# gave the Repeater the same list. A switch of that page, written by its own Settings, must show
# anew on its card. The classic look has the Open button there instead
if [ "$UI_MODERN" = "true" ]; then
  tap_card '^Wahoo Options$' "the page card"
else
  tap_ui '^Open$'
fi
sleep 4
shot q-wahoo-page
toggle_switch 'Without Wheel Diameter Protocol'
shot q-wahoo-on
back "to the results"
sleep 3
shot q-wahoo-back
results "back from Wahoo Options"
# The results come back at their scroll: the header may be off the top, the cards are there
has '^Wahoo Options$|^Search results.*' "back from the page lands on the results"
[ "$UI_MODERN" = "true" ] && find_card '^Without Wheel Diameter Protocol: On$' "the Wahoo switch shows On after the page"
shot q-wahoo-on-card

# A setting its page hides with the current values (kg only with miles on): back to the results
# with a toast that no longer says "change it here". The toast lasts 3 s: looked for first
query 'use%skg' kg
tap_ui '^Use kg for weight$'
# A screen capture takes about a second, a dump two: the pictures first. The toast fades in after
# the jump has run (right after the tap it was not there yet) and lasts 3 s
sleep 1
adb shell screencap -p /sdcard/q-kg-toast-1s.png || true
adb shell screencap -p /sdcard/q-kg-toast-2s.png || true
adb pull /sdcard/q-kg-toast-1s.png || true
adb pull /sdcard/q-kg-toast-2s.png || true
has '^Hidden on its page.*' "the hidden-setting toast"
cp ui.xml dumps/q-kg-toast-first.xml 2>/dev/null || true
[ "$UI_MODERN" = "true" ] && [ -f ui.xml ] && grep -q "change it here" ui.xml &&
  echo "!! the toast says change it here" >> $STEPLOG
shot q-kg-toast
sleep 3

# The value is read again on the way back: Fake Device on, switched off on its page, back
query 'fake%sdevice' fake
value_is 'Fake Device' 'On'
tap_ui '^Fake Device$'
sleep 6
shot q-fake-page
toggle_switch 'Fake Device'
shot q-fake-off
back "to the results"
sleep 3
shot q-fake-back
results "back after Fake Device off"
has '^Fake Device$' "back lands on the results"
value_is 'Fake Device' 'Off'

# Changed: the reset stays, the values the same text
type_query ''
tap_ui '^Changed$'
sleep 4
shot q-changed
results "changed"
has '^Changed settings.*' "changed list"
[ "$UI_MODERN" = "true" ] && has '^Reset$' "a Reset button on the changed cards"
value_is 'Player Weight \(kg\)' '80\.5'
value_is 'Strava Upload' 'Request'
tap_ui '^Changed$'
sleep 2
shot e-end

adb shell "ps -A 2>/dev/null || ps" > process_list.txt || true
shot screenshot
kill $LOGCAT_PID 2>/dev/null || true
wait $LOGCAT_PID 2>/dev/null || true
# If the recording broke off (adb restarted), the dump of the end is better than nothing
adb logcat -d > end_logcat.txt || true
if [ "$(wc -l < full_logcat.txt)" -lt "$(wc -l < end_logcat.txt)" ]; then
  echo "!! logcat recording shorter than the dump at the end: the dump is kept" >> $STEPLOG
  mv end_logcat.txt full_logcat.txt
else
  rm -f end_logcat.txt
fi
# The debug logs the app wrote itself (Documents/QZ on Android 14+): none with the log off
mkdir -p qz-logs
adb shell 'ls -la /sdcard/Documents/QZ/ 2>&1' > qz-logs/listing.txt || true
for f in $(adb shell 'ls /sdcard/Documents/QZ/ 2>/dev/null' | tr -d '\r' | grep '^debug-.*[.]log$'); do
  adb pull "/sdcard/Documents/QZ/$f" "qz-logs/$f" > /dev/null 2>&1 || true
done
echo "== app debug logs"; cat qz-logs/listing.txt; ls -la qz-logs
echo "== steps"; cat $STEPLOG
echo "== timing"; grep -E "QZ-TIMING|QZ-THEME" full_logcat.txt || true
# The dialogs are hidden (hide_error_dialogs above), so hangs are only here
grep -E "ANR in" full_logcat.txt | sed 's/^/!! /' >> $STEPLOG || true
echo "== ANR"; grep -E "ANR in" full_logcat.txt || true
grep -iE "qrc:|\.qml|warning|critical|fatal" full_logcat.txt | tail -n 80 || true
echo "== web page errors"; grep -iE "Uncaught|chromium.*(Error|error)|Error is " full_logcat.txt | tail -n 40 || true
echo "== polling while the charts page was left (between the marks; 0 expected)"
awk '/T095.*mark charts-left/{f=1;next} /T095.*mark home-20s/{f=0} f && /WS >> \{"msg":"getsessionarray"\}/' full_logcat.txt | tee -a $STEPLOG | wc -l
echo "== requests of the charts page: whole / parts (\"from\")"
echo "whole: $(grep -c 'WS >> {"msg":"getsessionarray"}' full_logcat.txt) parts: $(grep -c 'WS >> {"msg":"getsessionarray","content":{"from"' full_logcat.txt)" | tee -a $STEPLOG
