#!/bin/bash
# Test only (T-390): the one-time Wahoo notice, in English and Russian, signal on a timer of the test build.
PKG=org.cagnulen.qdomyoszwift
UI_MODERN=${UI_MODERN:-false}
LOG_DEBUG=${LOG_DEBUG:-true}
STEPLOG=steps.log
CONF='files/.config/Roberto Viola/qDomyos-Zwift.conf'
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

# A fake treadmill, so there is no first-run wizard; English; the look of the run
put_conf() {
  printf '[General]\nlog_debug=%s\nui_modern=%s\nfakedevice_treadmill=true\napp_language=%s\n' "$LOG_DEBUG" "$UI_MODERN" "$APP_LANGUAGE" > qz.conf
  adb push qz.conf /data/local/tmp/qz.conf
  adb shell "run-as $PKG mkdir -p 'files/.config/Roberto Viola'"
  adb shell "run-as $PKG cp /data/local/tmp/qz.conf '$CONF'"
}
dump() {
  rm -f ui.xml
  timeout 25 adb shell uiautomator dump /sdcard/ui.xml < /dev/null > /dev/null 2>&1 || true
  adb pull /sdcard/ui.xml ui.xml > /dev/null 2>&1 || true
}
# A window of another app over QZ: the launcher of the image hangs on the slow CI machine and its
# "isn't responding" dialog survives the back key (run 41376681046 lost both cases to it), so that
# dialog is answered by its buttons; anything else gets the back key. Logged in steps.log.
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
  ensure_app
  echo "-- shot $1" >> $STEPLOG
  adb shell screencap -p /sdcard/$1.png || true
  adb pull /sdcard/$1.png || true
  [ -f ui.xml ] || dump
  [ -f ui.xml ] && cp ui.xml dumps/$1.xml
}
tap() { ensure_app; echo "tap $1 $2 ($3)" >> $STEPLOG; adb shell input tap $1 $2 || true; }
back() { echo "back ($1)" >> $STEPLOG; adb shell input keyevent KEYCODE_BACK || true; }
# tap_ui 'regex' [x y]: the control whose whole text or accessible name matches, else the coordinates
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
# scroll_to 'regex' [swipes]: swipe the page up until the control shows
scroll_to() {
  local i
  for i in $(seq 1 ${2:-14}); do
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
scroll_top() {
  local i
  for i in 1 2 3 4 5; do adb shell input swipe 700 800 700 2200 150 || true; done
  sleep 1
}

adb logcat -c || true
adb logcat -v threadtime -b main,system,crash > full_logcat.txt 2>/dev/null &
LOGCAT_PID=$!
adb shell settings put system accelerometer_rotation 0 || true
adb shell settings put system user_rotation 0 || true

# The value of the flag in the saved settings, in the log; check_flag <prefix> <expected line or empty>
check_flag() {
  local line
  line=$(adb shell "run-as $PKG cat '$CONF'" | tr -d '\r' | grep -a '^wahoo_wheel_notice_shown')
  echo "   $1: ${line:-no wahoo_wheel_notice_shown}" >> $STEPLOG
  if [ "$line" = "$2" ]; then
    echo "check $1: OK" >> $STEPLOG
  else
    echo "!! check $1: expected '$2'" >> $STEPLOG
    FAILED=1
  fi
}
# The test build fires the signal 25 s and 55 s after the start of homeform.
# case_run <prefix> <language> <title of the notice in that language>
case_run() {
  local prefix="$1"
  APP_LANGUAGE="$2"
  install_apk apk-debug/android-debug.apk
  put_conf
  echo "== $prefix: start, language $2" >> $STEPLOG
  adb shell am start -n $PKG/$PKG.CustomQtActivity
  sleep 50
  shot $prefix-1-notice
  grep -c "$3" ui.xml >> $STEPLOG 2>&1 || echo "!! $prefix: the title is not in the dump" >> $STEPLOG
  sleep 8
  check_flag $prefix-shown 'wahoo_wheel_notice_shown=true'
  tap_ui '^(OK|Ok|ОК)$' || { shot $prefix-1-no-ok; FAILED=1; }
  sleep 45
  shot $prefix-2-after-second-signal
  grep -q "$3" ui.xml && { echo "!! $prefix: shown again after the second signal" >> $STEPLOG; FAILED=1; }

  # A new start: neither signal shows it
  adb shell am force-stop $PKG || true
  sleep 3
  adb shell am start -n $PKG/$PKG.CustomQtActivity
  sleep 90
  rm -f ui.xml
  shot $prefix-3-after-restart
  grep -q "$3" ui.xml && { echo "!! $prefix: shown again after the restart" >> $STEPLOG; FAILED=1; }
  check_flag $prefix-restart 'wahoo_wheel_notice_shown=true'
  adb shell am force-stop $PKG || true
  sleep 2
}

case_run en en 'Wahoo Virtual Gears'
case_run ru ru 'Виртуальные передачи Wahoo'

kill $LOGCAT_PID 2>/dev/null || true
wait $LOGCAT_PID 2>/dev/null || true
echo "== QML warnings of main" >> $STEPLOG
grep -a -E "main\.qml" full_logcat.txt | tail -n 40 >> $STEPLOG || true
echo "== ANR / crash in the whole log:" >> $STEPLOG
grep -a -E "ANR in|FATAL EXCEPTION|Fatal signal" full_logcat.txt >> $STEPLOG || echo "none" >> $STEPLOG
cat $STEPLOG
exit $FAILED
