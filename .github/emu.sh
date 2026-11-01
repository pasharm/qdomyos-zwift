#!/bin/bash
# Test only (T-375): Rower Options in the modern look, the current beta first, then the build with
# the two hints in the style of the modern look. Same steps for both, frames b-* and a-*.
# QML text is not in the uiautomator dump, so the section is read by the frames.
PKG=org.cagnulen.qdomyoszwift
LOG_DEBUG=${LOG_DEBUG:-true}
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

# put_conf: the settings file of the app before a start - a fake treadmill, so there is no
# first-run wizard; the classic look, English
put_conf() {
  printf '[General]\nlog_debug=%s\nui_modern=true\nvirtual_device_rower=true\nfakedevice_treadmill=true\napp_language=en\n' "$LOG_DEBUG" > qz.conf
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
# A window of another app over QZ (Health Connect, a launcher not responding) closed with the back key
ensure_app() {
  local i pkg
  for i in 1 2 3; do
    dump
    [ -f ui.xml ] || return 0
    pkg=$(python3 .github/uitap.py ui.xml --package)
    [ -z "$pkg" ] || [ "$pkg" = "$PKG" ] && return 0
    echo "!! $pkg over the app: back key" >> $STEPLOG
    adb shell input keyevent KEYCODE_BACK || true
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
# scroll_to 'regex': swipe the page up until the control shows (at most 14 swipes)
scroll_to() {
  local i
  for i in $(seq 1 14); do
    dump
    if [ -f ui.xml ] && python3 .github/uitap.py ui.xml "$1" > /dev/null; then
      echo "scroll to '$1': found after $((i - 1)) swipes" >> $STEPLOG
      return 0
    fi
    adb shell input swipe 700 2000 700 1300 400 || true
    sleep 1
  done
  echo "!! scroll to '$1': NOT FOUND" >> $STEPLOG
  return 1
}

adb logcat -c || true
adb logcat -v threadtime -b main,system,crash > full_logcat.txt 2>/dev/null &
LOGCAT_PID=$!
adb shell settings put system accelerometer_rotation 0 || true
adb shell settings put system user_rotation 0 || true

# case_run <prefix> <apk>: Settings -> Tiles Options, a frame at the top and at every swipe
case_run() {
  local i
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
  tap_drawer '^Settings$' 400 900
  sleep 8
  shot $1-settings
  # T-375, rower hints: Rower Options through the settings search of the modern look
  dump
  tap_ui '🔍|Search settings'
  sleep 2
  tap 470 338 "search field"
  sleep 1
  adb shell input text "Cadence%sGain"
  sleep 3
  if adb shell dumpsys input_method | grep -q "mInputShown=true"; then
    adb shell input keyevent KEYCODE_BACK || true
    sleep 1
  fi
  shot $1-results
  dump
  tap_ui '^Cadence Gain.*' || return 1
  sleep 6
  shot $1-t00
  for i in 1 2 3; do
    adb shell input swipe 700 1800 700 1400 500 || true
    sleep 2
    shot $1-t0$i
  done
}

FAILED=0
case_run b apk-base/android-debug.apk || FAILED=1
adb shell am force-stop $PKG || true
sleep 2
case_run a apk-debug/android-debug.apk || FAILED=1
adb shell am force-stop $PKG || true

kill $LOGCAT_PID 2>/dev/null || true
sleep 1
# The frames decide, but the run proves nothing unless the page with the pace tiles was reached
for side in b a; do
  if grep -l 'Cadence Offset' dumps/$side-t0*.xml > /dev/null 2>&1; then
    echo "check $side: Rower Options in the dump: OK, the frames decide" >> $STEPLOG
  else
    echo "!! check $side: Rower Options NOT reached" >> $STEPLOG
    FAILED=1
  fi
done
echo "== ANR / crash in the whole log:" >> $STEPLOG
grep -E "ANR in|FATAL EXCEPTION|Fatal signal" full_logcat.txt >> $STEPLOG || echo "none" >> $STEPLOG
echo "== QML warnings of the tiles page:" >> $STEPLOG
grep -E "settings-tiles.qml" full_logcat.txt | grep -i -E "warn|error|TypeError|ReferenceError|binding loop" | head -40 >> $STEPLOG || echo "none" >> $STEPLOG
cat $STEPLOG
exit $FAILED
