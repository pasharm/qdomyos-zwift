#!/bin/bash
# Test only (T-468): the settings search of the commit, classic look.
#  r: "ftp" -> a tap on "FTP value" opens it on its page, back returns to the results
#  c: ant_garmin on -> "Changed" lists it; a tap shows the toast "not found on the settings pages",
#     the list stays
PKG=org.cagnulen.qdomyoszwift
UI_MODERN=${UI_MODERN:-false}
LOG_DEBUG=${LOG_DEBUG:-true}
STEPLOG=steps.log
CONF='files/.config/Roberto Viola/qDomyos-Zwift.conf'
TOAST='This setting was not found on the settings pages'
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

# A fake treadmill, so there is no first-run wizard; Garmin ANT+ on: a setting with no place on
# the pages, listed in "Changed" only
put_conf() {
  printf '[General]\nlog_debug=%s\nui_modern=%s\nfakedevice_treadmill=true\nant_garmin=true\n' "$LOG_DEBUG" "$UI_MODERN" > qz.conf
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
# Toolbar buttons are icons without text (Nexus 6: 1440x2560)
BACK_XY="84 168"

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

# Settings from the menu
tap $BACK_XY "menu"
sleep 3
adb shell input swipe 500 700 500 2300 300 || true
sleep 2
tap_ui '^Settings$' || FAILED=1
wait_ui '^General Options$' 60 || { echo "!! settings not opened" >> $STEPLOG; FAILED=1; }
shot 02-settings
# The search bar: the toolbar button is named "Search settings" too, the bar is open when
# "Changed" shows
if ! wait_ui '^Changed$' 3; then
  tap_ui '🔍|Search settings'
  sleep 2
fi
check "search bar open" '^Changed$' 15

# r: "ftp", first letter first until the field has it (the first keys can be lost)
echo "== r: ftp" >> $STEPLOG
for i in 1 2 3; do
  tap 470 338 "search field"
  sleep 1
  adb shell input text f || true
  sleep 2
  wait_ui '^Search results.*|^No settings found$' 6 && break
done
adb shell input text tp || true
sleep 4
adb shell input keyevent KEYCODE_BACK || true   # the keyboard down
sleep 2
check "r: results of ftp" '^Search results.*' 15
shot r-1-results
if tap_ui '^FTP value.*'; then
  sleep 4
  shot r-2-opened
  check_none "r: results closed on the tap" '^Search results.*'
  check "r: FTP value on its page" '^FTP value.*' 10
  tap $BACK_XY "back"
  sleep 4
  shot r-3-back
  check "r: back returns to the results" '^Search results.*' 15
  check "r: FTP value among them" '^FTP value.*' 5
else
  FAILED=1
fi

# c: "Changed" with Garmin ANT+ on
echo "== c: Changed" >> $STEPLOG
tap_ui '^Clear$' || true
sleep 3
if ! wait_ui '^Changed$' 3; then
  tap_ui '🔍|Search settings'
  sleep 2
fi
tap_ui '^Changed$' || FAILED=1
check "c: Changed list" '^Changed settings.*' 20
shot c-1-changed
if tap_ui '^Garmin ANT\+.*'; then
  TOAST_SEEN=0
  for i in 1 2 3 4 5 6; do
    dump
    if [ -f ui.xml ] && grep -q "$TOAST" ui.xml; then TOAST_SEEN=$i; cp ui.xml dumps/c-2-toast.xml; break; fi
    sleep 0.5
  done
  adb shell screencap -p /sdcard/c-2-toast.png || true
  adb pull /sdcard/c-2-toast.png || true
  if [ $TOAST_SEEN -gt 0 ]; then
    echo "check c: toast '$TOAST': OK (dump $TOAST_SEEN)" >> $STEPLOG
  else
    echo "!! check c: toast '$TOAST' not in the dumps" >> $STEPLOG
    FAILED=1
  fi
  sleep 3
  shot c-3-after
  check "c: the list stays" '^Changed settings.*' 10
  check "c: Garmin ANT+ still listed" '^Garmin ANT\+.*' 5
else
  FAILED=1
fi

adb shell am force-stop $PKG || true
kill $LOGCAT_PID 2>/dev/null || true
wait $LOGCAT_PID 2>/dev/null || true
echo "== QML errors of settings.qml in the whole log:" >> $STEPLOG
grep -a -E "qrc:/settings\.qml" full_logcat.txt | grep -a -E "Error|error|undefined|not a function" | cut -c1-220 | head -n 20 >> $STEPLOG
grep -a -q -E "qrc:/settings\.qml.*(TypeError|ReferenceError)" full_logcat.txt && { echo "!! JS error in settings.qml" >> $STEPLOG; FAILED=1; }
echo "== search lines:" >> $STEPLOG
grep -a -E "Unable to (build|load|parse)" full_logcat.txt | cut -c1-200 | head -n 10 >> $STEPLOG
echo "== ANR / crash in the whole log:" >> $STEPLOG
grep -a -E "ANR in|FATAL EXCEPTION|Fatal signal" full_logcat.txt >> $STEPLOG || echo "none" >> $STEPLOG
grep -q "^check " $STEPLOG || { echo "!! no check ran: the run proves nothing" >> $STEPLOG; FAILED=1; }
cat $STEPLOG
exit $FAILED
