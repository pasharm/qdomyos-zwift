#!/bin/bash
# Test only (T-324): Reset in the list of changed settings, classic look.
#  a: "Changed" lists five settings, each with Reset, and Reset all next to the title
#  b: Reset of Player Weight (no restart in the catalog): gone from the list, the toast, and back
#     from the settings asks no restart
#  c: the settings again: Player Weight still not changed (written to the store)
#  d: Reset all: the confirmation, Yes - "No changed settings"; back asks the restart (Debug Log
#     and Fake Treadmill need it in the catalog)
#  e: the settings again: still "No changed settings"
PKG=org.cagnulen.qdomyoszwift
UI_MODERN=${UI_MODERN:-false}
LOG_DEBUG=${LOG_DEBUG:-true}
STEPLOG=steps.log
CONF='files/.config/Roberto Viola/qDomyos-Zwift.conf'
RESTART='Settings changed'
: > $STEPLOG
mkdir -p dumps
FAILED=0

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
  for p in EXERCISE DISTANCE TOTAL_CALORIES_BURNED HEART_RATE POWER SPEED CYCLING_PEDALING_CADENCE ELEVATION_GAINED STEPS STEPS_CADENCE HEART_RATE_VARIABILITY; do
    adb shell pm grant $PKG android.permission.health.WRITE_$p || true
  done
  echo "== installed $1" >> $STEPLOG
}
adb shell cmd uimode night no || true
adb shell settings put global hide_error_dialogs 1 || true

# A fake treadmill, so there is no first-run wizard. Changed from the default: Debug Log and Fake
# Treadmill (restartRequired), Garmin ANT+, Player Weight, FTP value (no restart)
put_conf() {
  printf '[General]\nlog_debug=%s\nui_modern=%s\nfakedevice_treadmill=true\nant_garmin=true\nweight=90\nftp=250\n' "$LOG_DEBUG" "$UI_MODERN" > qz.conf
  adb push qz.conf /data/local/tmp/qz.conf
  adb shell "run-as $PKG mkdir -p 'files/.config/Roberto Viola'"
  adb shell "run-as $PKG cp /data/local/tmp/qz.conf '$CONF'"
  adb shell "run-as $PKG ls -l '$CONF'" >> $STEPLOG 2>&1 || { echo "!! qz.conf not written" >> $STEPLOG; exit 1; }
}
dump() {
  rm -f ui.xml
  timeout 25 adb shell uiautomator dump /sdcard/ui.xml < /dev/null > /dev/null 2>&1 || true
  adb pull /sdcard/ui.xml ui.xml > /dev/null 2>&1 || true
}
# A window of another app over QZ: "isn't responding" answered by its buttons, else the back key
ensure_app() {
  local i pkg xy
  for i in 1 2 3 4 5; do
    dump
    [ -f ui.xml ] || return 0
    pkg=$(python3 .github/uitap.py ui.xml --package)
    [ -z "$pkg" ] || [ "$pkg" = "$PKG" ] && return 0
    if grep -q "t responding" ui.xml && xy=$(python3 .github/uitap.py ui.xml 'Close app'); then
      echo "!! $pkg not responding: Close app at $xy" >> $STEPLOG
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
  rm -f ui.xml
}
shot() {
  echo "-- shot $1" >> $STEPLOG
  adb shell screencap -p /sdcard/$1.png || true
  adb pull /sdcard/$1.png || true
  dump
  [ -f ui.xml ] && cp ui.xml dumps/$1.xml
}
tap() { ensure_app; echo "tap $1 $2 ($3)" >> $STEPLOG; adb shell input tap $1 $2 || true; }
# wait_ui 'regex' <seconds>: 0 once a control with that whole text or name shows
wait_ui() {
  local i
  for i in $(seq 1 $(( ${2:-30} / 3 ))); do
    dump
    [ -f ui.xml ] && python3 .github/uitap.py ui.xml "$1" > /dev/null && return 0
    sleep 2
  done
  return 1
}
# tap_ui 'regex': waits for the control up to 30 s, then taps it
tap_ui() {
  local xy=""
  ensure_app
  if wait_ui "$1" 30; then
    xy=$(python3 .github/uitap.py ui.xml "$1")
    echo "tap '$1': at $xy" >> $STEPLOG
    adb shell input tap $xy || true
    return 0
  fi
  echo "!! tap '$1': NOT FOUND" >> $STEPLOG
  return 1
}
check() {   # check <name> <regex> <seconds>
  if wait_ui "$2" ${3:-15}; then
    echo "check $1: OK" >> $STEPLOG
  else
    echo "!! check $1: '$2' not shown" >> $STEPLOG
    FAILED=1
  fi
}
check_none() {   # check_none <name> <regex>
  dump
  if [ -f ui.xml ] && python3 .github/uitap.py ui.xml "$2" > /dev/null; then
    echo "!! check $1: '$2' still shown" >> $STEPLOG
    FAILED=1
  else
    echo "check $1: OK" >> $STEPLOG
  fi
}
# Frames back to back right after a tap: a toast is gone before a few dumps are taken
frames() {
  local i
  for i in 1 2 3; do
    adb exec-out screencap -p > $1-$i.png || true
  done
  echo "-- frames $1-1..3" >> $STEPLOG
}
# Toolbar buttons are icons without text (Nexus 6: 1440x2560)
BACK_XY="84 168"

# open_changed: from the home page, the settings and their "Changed" list
open_changed() {
  tap $BACK_XY "menu"
  sleep 3
  adb shell input swipe 500 700 500 2300 300 || true
  sleep 2
  tap_ui '^Settings$' || FAILED=1
  wait_ui '^General Options$' 60 || { echo "!! settings not opened" >> $STEPLOG; FAILED=1; }
  # The search bar: the toolbar button is named "Search settings" too, the bar is open when
  # "Changed" shows
  if ! wait_ui '^Changed$' 3; then
    tap_ui '🔍|Search settings'
    sleep 2
  fi
  tap_ui '^Changed$' || FAILED=1
  check "$1: Changed list" '^Changed settings.*|^No changed settings$' 20
}
# back_home <name> <yes|no>: back from the settings; the restart question shown or not
back_home() {
  tap $BACK_XY "back"
  sleep 3
  if [ "$2" = yes ]; then
    check "$1: restart asked" "^$RESTART\$" 15
    shot $1-restart
    tap_ui '^No$' || FAILED=1
    sleep 2
  else
    sleep 3
    shot $1-home
    check_none "$1: no restart asked" "^$RESTART\$"
  fi
  check "$1: home page" '^Start$|^Stop$' 30
}

adb logcat -c || true
adb logcat -v threadtime -b main,system,crash > full_logcat.txt 2>/dev/null &
LOGCAT_PID=$!
adb shell settings put system accelerometer_rotation 0 || true
adb shell settings put system user_rotation 0 || true

echo "== API $(adb shell getprop ro.build.version.sdk | tr -d '\r')" >> $STEPLOG
install_apk apk-debug/android-debug.apk
put_conf
adb shell am start -n $PKG/$PKG.CustomQtActivity
if ! wait_ui '^Start$|^Stop$' 120; then
  echo "!! home page not shown in 120 s" >> $STEPLOG
  shot 00-no-home
  FAILED=1
fi
shot 01-home

echo "== a: Changed" >> $STEPLOG
open_changed a
check "a: five listed" '^Changed settings \(5\)$' 10
check "a: Reset all" '^Reset all$' 5
check "a: Reset of Player Weight" '^Reset: Player Weight.*' 5
shot a-1-changed

echo "== b: Reset of Player Weight" >> $STEPLOG
if tap_ui '^Reset: Player Weight.*'; then
  frames b-1-toast
  sleep 2
  shot b-2-after
  check "b: four left" '^Changed settings \(4\)$' 10
  check_none "b: Player Weight gone" '^Player Weight.*'
  check "b: FTP value still listed" '^FTP value.*' 5
else
  FAILED=1
fi
back_home b no

echo "== c: Changed again" >> $STEPLOG
open_changed c
check "c: four listed" '^Changed settings \(4\)$' 10
check_none "c: Player Weight not changed" '^Player Weight.*'
shot c-1-changed

echo "== d: Reset all" >> $STEPLOG
if tap_ui '^Reset all$'; then
  check "d: confirmation" '^Reset changed settings\?$' 15
  shot d-1-confirm
  tap_ui '^Yes$' || FAILED=1
  frames d-2-toast
  check "d: none left" '^No changed settings$' 15
  shot d-3-after
else
  FAILED=1
fi
back_home d yes

echo "== e: Changed again" >> $STEPLOG
open_changed e
check "e: none listed" '^No changed settings$' 10
shot e-1-changed

adb shell am force-stop $PKG || true
kill $LOGCAT_PID 2>/dev/null || true
wait $LOGCAT_PID 2>/dev/null || true
echo "== QML errors of settings.qml in the whole log:" >> $STEPLOG
grep -a -E "qrc:/settings\.qml" full_logcat.txt | grep -a -E "Error|error|undefined|not a function" | cut -c1-220 | head -n 20 >> $STEPLOG
grep -a -q -E "qrc:/settings\.qml.*(TypeError|ReferenceError)" full_logcat.txt && { echo "!! JS error in settings.qml" >> $STEPLOG; FAILED=1; }
echo "== ANR / crash in the whole log:" >> $STEPLOG
grep -a -E "ANR in|FATAL EXCEPTION|Fatal signal" full_logcat.txt >> $STEPLOG || echo "none" >> $STEPLOG
grep -q "^check " $STEPLOG || { echo "!! no check ran: the run proves nothing" >> $STEPLOG; FAILED=1; }
cat $STEPLOG
exit $FAILED
