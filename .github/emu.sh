#!/bin/bash
# Test only (T-423): the settings search in Russian, the classic look of master. Side b is the
# build of master without the fix (input baseline), side a the build with it (input source):
# the same steps, frames b-* and a-*. QML text of a result card has no accessible name, so it is
# not in the uiautomator dump: the frames decide, steps.log only proves the search was reached.
PKG=org.cagnulen.qdomyoszwift
STEPLOG=steps.log
CONF='files/.config/Roberto Viola/qDomyos-Zwift.conf'
: > $STEPLOG
mkdir -p dumps

# install_apk <apk>: a fresh install with the permissions granted
install_apk() {
  adb uninstall $PKG > /dev/null 2>&1 || true
  adb shell rm -rf /sdcard/Documents/QZ || true
  adb install "$1"
  adb shell pm path $PKG > /dev/null || { echo "!! $1 not installed" >> $STEPLOG; exit 1; }
  for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION BLUETOOTH_ADVERTISE BLUETOOTH_CONNECT BLUETOOTH_SCAN POST_NOTIFICATIONS; do
    adb shell pm grant $PKG android.permission.$p || true
  done
  adb shell appops set $PKG MANAGE_EXTERNAL_STORAGE allow || true
  # Health Connect write permissions granted: otherwise QZ opens its request (and the Health
  # Connect onboarding) over itself at the first start (HealthConnectHelper.writePermissions)
  for p in EXERCISE DISTANCE TOTAL_CALORIES_BURNED HEART_RATE POWER SPEED CYCLING_PEDALING_CADENCE ELEVATION_GAINED STEPS STEPS_CADENCE HEART_RATE_VARIABILITY; do
    adb shell pm grant $PKG android.permission.health.WRITE_$p || echo "!! health WRITE_$p not granted" >> $STEPLOG
  done
  echo "== installed $1" >> $STEPLOG
}
adb shell cmd uimode night no || true
adb shell settings put global hide_error_dialogs 1 || true

# put_conf: a fake device, so there is no first-run wizard; the app in Russian
put_conf() {
  printf '[General]\nlog_debug=true\napplewatch_fakedevice=true\napp_language=ru\n' > qz.conf
  adb push qz.conf /data/local/tmp/qz.conf
  adb shell "run-as $PKG mkdir -p 'files/.config/Roberto Viola'"
  adb shell "run-as $PKG cp /data/local/tmp/qz.conf '$CONF'"
}
# The control tree of the screen into ui.xml (empty when uiautomator gives up)
dump() {
  rm -f ui.xml
  timeout 25 adb shell uiautomator dump /sdcard/ui.xml < /dev/null > /dev/null 2>&1 || true
  adb pull /sdcard/ui.xml ui.xml > /dev/null 2>&1 || true
}
# A window of another app over QZ closed: "<app> isn't responding" with Wait, the rest (Health Connect) with back
ensure_app() {
  local i pkg xy
  for i in 1 2 3; do
    dump
    [ -f ui.xml ] || return 0
    pkg=$(python3 .github/uitap.py ui.xml --package)
    [ -z "$pkg" ] || [ "$pkg" = "$PKG" ] && return 0
    xy=$(python3 .github/uitap.py ui.xml 'Wait')
    if [ -n "$xy" ]; then
      echo "!! $pkg over the app: not responding dialog, Wait" >> $STEPLOG
      adb shell input tap $xy || true
    else
      echo "!! $pkg over the app: back key" >> $STEPLOG
      adb shell input keyevent KEYCODE_BACK || true
    fi
    sleep 3
  done
  rm -f ui.xml
}
# shot <label>: a frame and the control tree behind it
shot() {
  ensure_app
  echo "-- shot $1" >> $STEPLOG
  adb shell screencap -p /sdcard/$1.png || true
  adb pull /sdcard/$1.png || true
  [ -f ui.xml ] || dump
  [ -f ui.xml ] && cp ui.xml dumps/$1.xml
}
tap() { ensure_app; echo "tap $1 $2 ($3)" >> $STEPLOG; adb shell input tap $1 $2 || true; }
# tap_ui 'regex' [x y]: the control whose whole text or accessible name matches
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
    echo "!! tap '$rx': NOT FOUND, skipped" >> $STEPLOG
    return 1
  fi
}
# A drawer entry that may be below the fold: one swipe up and a second look
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
# The topmost text field of the screen (the search bar has no accessible name in master)
tap_field() {
  local xy=""
  dump
  [ -f ui.xml ] && xy=$(python3 -c '
import re, sys, xml.etree.ElementTree as ET
best = None
for n in ET.parse(sys.argv[1]).getroot().iter("node"):
    if n.get("class") != "android.widget.EditText":
        continue
    m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", n.get("bounds") or "")
    if not m:
        continue
    x1, y1, x2, y2 = map(int, m.groups())
    if x2 > x1 and y2 > y1 and (best is None or y1 < best[1]):
        best = ((x1 + x2) // 2, y1, (y1 + y2) // 2)
if best:
    print(best[0], best[2])
' ui.xml)
  if [ -n "$xy" ]; then
    echo "tap field: EditText at $xy" >> $STEPLOG
    adb shell input tap $xy || true
  else
    echo "tap field: no EditText in the dump, coordinates 470 338" >> $STEPLOG
    adb shell input tap 470 338 || true
  fi
}
hide_keyboard() {
  if adb shell dumpsys input_method | grep -q "mInputShown=true"; then
    echo "back (keyboard)" >> $STEPLOG
    adb shell input keyevent KEYCODE_BACK || true
    sleep 1
  fi
}
# query 'text' label: a new search (spaces as %s for adb) and its frame
query() {
  tap_field
  sleep 1
  # the tap puts the cursor where it lands: to the end, then the old text out
  adb shell input keyevent KEYCODE_MOVE_END || true
  for i in $(seq 1 40); do adb shell input keyevent KEYCODE_DEL || true; done
  adb shell input text "$1"
  echo "query '$1'" >> $STEPLOG
  sleep 4
  hide_keyboard
  sleep 1
  shot "$2"
}

adb logcat -c || true
adb logcat -v threadtime -b main,system,crash > full_logcat.txt 2>/dev/null &
LOGCAT_PID=$!
adb shell settings put system accelerometer_rotation 0 || true
adb shell settings put system user_rotation 0 || true

# case_run <side> <apk>: Settings, the search bar, four queries with a frame each
case_run() {
  install_apk "$2"
  put_conf
  echo "== $1: start" >> $STEPLOG
  adb shell am start -n $PKG/$PKG.CustomQtActivity
  sleep 45
  shot $1-home
  tap 84 168 "menu"
  sleep 3
  adb shell input swipe 500 700 500 2300 300 || true
  sleep 2
  shot $1-menu
  tap_drawer '^(Settings|Настройки)$' 400 900
  sleep 8
  shot $1-settings
  tap_ui '🔍|Search settings|Поиск настроек' || return 1
  sleep 2
  shot $1-bar
  query "Chart%sPosition" $1-q1-charts
  query "Life%sFitness%saccount" $1-q2-lifefitness
  query "Inclination%sto%sResistance" $1-q3-table
  query "Action" $1-q4-mywhoosh
}

FAILED=0
case_run b apk-base/android-debug.apk || FAILED=1
adb shell am force-stop $PKG || true
sleep 2
case_run a apk-debug/android-debug.apk || FAILED=1
adb shell am force-stop $PKG || true

kill $LOGCAT_PID 2>/dev/null || true
sleep 1
# The frames decide; the run proves nothing unless each side opened the search bar by its label
# and typed all four queries. Only the lines of the side: from its start to the next install
for side in b a; do
  lines=$(awk -v s="== $side: start" '/^== installed/ { on = 0 } $0 == s { on = 1 } on' $STEPLOG)
  if echo "$lines" | grep -q "Поиск настроек': by label\|Search settings': by label" &&
     [ "$(echo "$lines" | grep -c "^query ")" = 4 ]; then
    echo "check $side: search opened, 4 queries: OK, the frames decide" >> $STEPLOG
  else
    echo "!! check $side: search bar or queries NOT reached" >> $STEPLOG
    FAILED=1
  fi
done
echo "== ANR / crash in the whole log:" >> $STEPLOG
grep -E "ANR in|FATAL EXCEPTION|Fatal signal" full_logcat.txt >> $STEPLOG || echo "none" >> $STEPLOG
cat $STEPLOG
exit $FAILED
