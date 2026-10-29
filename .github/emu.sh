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
# A failed install (API 22: the 554 MB APK did not fit the data partition) left a run of steps
# against the launcher that still ended "OK"
adb shell pm path $PKG > /dev/null 2>&1 || echo "!! APK NOT INSTALLED - the run proves nothing" >> $STEPLOG
# Location on: without it QZ shows "Permissions Required" over every screen (API < 30 images)
adb shell settings put secure location_providers_allowed +gps || true
adb shell settings put secure location_providers_allowed +network || true
adb shell settings put secure location_mode 3 || true
for p in READ_EXTERNAL_STORAGE WRITE_EXTERNAL_STORAGE ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION BLUETOOTH_ADVERTISE BLUETOOTH_CONNECT BLUETOOTH_SCAN POST_NOTIFICATIONS; do
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
# T-095: the live update of the Charts page on from the start (the setting is off by default)
printf '[General]\nlog_debug=%s\nconfirm_stop_workout=true\nui_modern=%s\napplewatch_fakedevice=true\nftp=250\ncharts_live_update=true\n' "$LOG_DEBUG" "$UI_MODERN" > qz.conf
adb push qz.conf /data/local/tmp/qz.conf
adb shell "run-as $PKG mkdir -p 'files/.config/Roberto Viola'"
adb shell "run-as $PKG cp /data/local/tmp/qz.conf 'files/.config/Roberto Viola/qDomyos-Zwift.conf'"
adb shell "run-as $PKG ls -la 'files/.config/Roberto Viola'" || true

# The control tree of the screen into ui.xml (empty when uiautomator gives up, for instance
# while something animates without pause)
dump() {
  rm -f ui.xml
  timeout 25 adb shell uiautomator dump /data/local/tmp/ui.xml > /dev/null 2>&1 || true
  adb pull /data/local/tmp/ui.xml ui.xml > /dev/null 2>&1 || true
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
    # QZ's own Android dialog "Permissions Required" (Bluetooth and location services off, API < 30
    # images): it belongs to the app, so the package check below would let it cover every step
    # and after No its follow-up "Reminder Preference" (remind about location next time?)
    if [ "$pkg" = "$PKG" ] && grep -qE "Permissions Required|Reminder Preference" ui.xml && xy=$(python3 .github/uitap.py ui.xml '^No$'); then
      echo "!! QZ permission dialog: No at $xy" >> $STEPLOG
      adb shell input tap $xy || true
      sleep 3
      continue
    fi
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
  adb shell screencap -p /data/local/tmp/$1.png || true
  adb pull /data/local/tmp/$1.png || true
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

# T-095: the Charts page with charts_live_update on (fake bike: the session grows by a point a
# second). The switch at the top right shows while the workout runs and writes the setting;
# the page asks for the new points once a second; Stop hides the switch.
mark() { echo "$(date +%H:%M:%S) $1" >> $STEPLOG; adb shell log -t T095 "'mark $1'" || true; }
conf_value() {
  adb shell "run-as $PKG cat 'files/.config/Roberto Viola/qDomyos-Zwift.conf'" 2>/dev/null | tr -d '\r' | grep '^charts_live_update=' || echo "charts_live_update: not in qz.conf"
}
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
# The texts of the page (WebView nodes) with a digit or the switch, into steps.log
page() {
  dump
  echo "page ($1):" >> $STEPLOG
  [ -f ui.xml ] && python3 -c '
import re, sys, xml.etree.ElementTree as ET
for n in ET.parse(sys.argv[1]).getroot().iter("node"):
    t, d = n.get("text") or "", n.get("content-desc") or ""
    if re.search(r"[0-9]|Live|update", t + d):
        print("   ", n.get("class"), repr(t), repr(d), n.get("checked"), n.get("bounds"))
' ui.xml | head -40 >> $STEPLOG
  cp ui.xml dumps/page-$1.xml 2>/dev/null || true
}
# Taps the node matching rx that is the lowest on the screen: the Stop of the confirmation
# lies under the Stop button
tap_node() {
  local rx="$1" xy=""
  dump
  [ -f ui.xml ] && xy=$(python3 -c '
import re, sys, xml.etree.ElementTree as ET
rx = sys.argv[2]
best = None
for n in ET.parse(sys.argv[1]).getroot().iter("node"):
    t = (n.get("text") or "") or (n.get("content-desc") or "")
    if not re.fullmatch(rx, t, re.I):
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
' ui.xml "$rx")
  if [ -n "$xy" ]; then
    echo "tap node '$rx' at $xy" >> $STEPLOG
    adb shell input tap $xy || true
  else
    echo "!! tap node '$rx' NOT FOUND" >> $STEPLOG
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

wait_tiles
sleep 20                           # some seconds of the session before the page opens
shot h-home
open_menu
shot m-menu
tap_drawer 'Charts' 400 900
sleep 10
shot c-00
page c-00
has 'Live update.*' "switch shown while the workout runs"
mark live-on-start
sleep 60                            # the per-second refreshes measured below
mark live-on-60s
shot c-60
page c-60

# A scroll down: the charts below catch up (they were skipped off screen)
adb shell input swipe 700 2000 700 700 400 || true
sleep 2
shot c-down-2
sleep 5
shot c-down-7
scroll_top
sleep 2

# The switch off: no requests, the setting false
tap_node 'Live update.*' && echo "switch tapped (off)" >> $STEPLOG
sleep 3
mark switch-off
sleep 15
mark switch-off-15s
shot c-off
page c-off
echo "after off: $(conf_value)" >> $STEPLOG

# On again: the requests come back, the setting true
tap_node 'Live update.*' && echo "switch tapped (on)" >> $STEPLOG
sleep 8
shot c-on
page c-on
echo "after on: $(conf_value)" >> $STEPLOG

back "charts"
sleep 5
shot h-back
tap_ui 'Stop' 1200 2300
sleep 3
shot h-stop-confirm
tap_node '(Yes|OK|Stop)' && echo "stop confirmed" >> $STEPLOG
sleep 12
shot e-end
page e-end
dump
if [ -f ui.xml ] && python3 .github/uitap.py ui.xml 'Live update.*' > /dev/null; then
  echo "!! check switch hidden after stop: SHOWN" >> $STEPLOG
else
  echo "check switch hidden after stop: OK" >> $STEPLOG
fi
echo "savechart lines (pictures for the mail; one set from the end page):" >> $STEPLOG
grep -c "savechart" full_logcat.txt >> $STEPLOG || true

adb shell "ps -A 2>/dev/null || ps" > process_list.txt || true
shot screenshot
kill $LOGCAT_PID 2>/dev/null || true
wait $LOGCAT_PID 2>/dev/null || true
adb logcat -d > end_logcat.txt || true
if [ "$(wc -l < full_logcat.txt)" -lt "$(wc -l < end_logcat.txt)" ]; then
  echo "!! logcat recording shorter than the dump at the end: the dump is kept" >> $STEPLOG
  mv end_logcat.txt full_logcat.txt
else
  rm -f end_logcat.txt
fi

# The time of a refresh: the next part is asked for 1 s after the previous redraw ended, so
# (interval between two requests - 1000 ms) is about the cost of one refresh (answer + redraw)
python3 - full_logcat.txt > t095-timing.txt <<'PY'
import sys, datetime
marks, reqs = [], []
for line in open(sys.argv[1], errors="replace"):
    if len(line) < 18:
        continue
    try:
        t = datetime.datetime.strptime("2026-" + line[:18], "%Y-%m-%d %H:%M:%S.%f")
    except ValueError:
        continue
    if "T095" in line and "mark " in line:
        marks.append((t, line.split("mark ", 1)[1].strip().strip("'")))
    elif 'WS >> {"msg":"getsessionarray","content":{"from"' in line:
        reqs.append(t)
def between(a, b):
    ta = [t for t, m in marks if m == a]
    tb = [t for t, m in marks if m == b]
    if not ta or not tb:
        return []
    return [t for t in reqs if ta[0] <= t <= tb[0]]
win = between("live-on-start", "live-on-60s")
gaps = sorted((b - a).total_seconds() * 1000 - 1000 for a, b in zip(win, win[1:]))
print("part requests in the 60 s with the switch on:", len(win))
if gaps:
    print("refresh cost, ms (interval - 1000): median %d, max %d, min %d" % (gaps[len(gaps) // 2], gaps[-1], gaps[0]))
print("part requests in the 15 s after the switch off (0 expected):", len(between("switch-off", "switch-off-15s")))
PY
cat t095-timing.txt >> $STEPLOG

mkdir -p qz-logs
echo "== steps"; cat $STEPLOG
grep -E "ANR in" full_logcat.txt | sed 's/^/!! /' >> $STEPLOG || true
echo "== ANR"; grep -E "ANR in" full_logcat.txt || true
grep -iE "qrc:|\.qml|warning|critical|fatal" full_logcat.txt | tail -n 60 || true
echo "== web page errors"; grep -iE "Uncaught|chromium.*(Error|error)|Error is " full_logcat.txt | tail -n 40 | tee -a $STEPLOG || true
