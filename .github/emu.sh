#!/bin/bash
# Test only (T-302): feat/modern-ui merged with master 3036f62b8. The reference APK (apk-base:
# feat/modern-ui before the merge) and the tested APK (apk-debug: the merge) go through the same
# steps with a fake treadmill: start, home with tiles, Start and Stop (the treadmill stop path
# changed in master with #5403), the menu, the settings and Treadmill Options, a rotation.
# At the end the QML warnings of the tested APK that the reference did not have go to steps.log.
PKG=org.cagnulen.qdomyoszwift
UI_MODERN=${UI_MODERN:-false}
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

# put_conf: the settings file of the app before a start - a fake treadmill, so the home page has
# tiles and no first-run wizard
put_conf() {
  printf '[General]\nlog_debug=%s\nui_modern=%s\nfakedevice_treadmill=true\napp_language=en\n' "$LOG_DEBUG" "$UI_MODERN" > qz.conf
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
mark() {
  echo "$(date +%H:%M:%S) $1" >> $STEPLOG
  adb shell log -t T302 "'$1'" || true
}
# tap_ui 'regex' [x y]: the control whose whole text or accessible name matches, else the
# fallback coordinates; without them the step is skipped
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
  echo "!! scroll to '$1': NOT FOUND" >> $STEPLOG
  return 1
}
# The fake treadmill comes after the first search ends: wait for its tiles (at most 3 min)
wait_tiles() {
  local i
  for i in $(seq 1 18); do
    dump
    if [ -f ui.xml ] && grep -q 'content-desc="Speed' ui.xml; then
      echo "tiles shown after $i looks" >> $STEPLOG; return 0
    fi
    sleep 10
  done
  echo "!! tiles NOT shown" >> $STEPLOG
}
back() { echo "back ($1)" >> $STEPLOG; adb shell input keyevent KEYCODE_BACK || true; }
# Toolbar: the menu button on the home page (Nexus 6: 1440x2560 px)
MENU="84 168"

adb logcat -c || true
adb logcat -v threadtime -b main,system,crash > full_logcat.txt 2>/dev/null &
LOGCAT_PID=$!

# run_case <label> <apk>
run_case() {
  local label="$1" pid
  install_apk "$2"
  adb shell settings put system accelerometer_rotation 0 || true
  adb shell settings put system user_rotation 0 || true
  put_conf
  mark "$label: start"
  adb shell am start -n $PKG/$PKG.CustomQtActivity
  sleep 25
  pid=$(adb shell pidof $PKG | tr -d '\r')
  echo "$label: pid $pid" >> $STEPLOG
  echo "$pid" > pid-$label.txt
  wait_tiles
  shot $label-01-home
  mark "$label: Start"
  tap_ui 'Start'
  sleep 20
  shot $label-02-running
  mark "$label: Stop"
  tap_ui 'Stop'
  sleep 5
  shot $label-03-stopped
  mark "$label: menu"
  ensure_app
  echo "tap menu $MENU" >> $STEPLOG
  adb shell input tap $MENU || true
  sleep 3
  shot $label-04-menu
  mark "$label: settings"
  tap_ui 'Settings' && sleep 5
  shot $label-05-settings
  scroll_to 'Treadmill Options' && tap_ui 'Treadmill Options' && sleep 3
  shot $label-06-treadmill-options
  back "settings"
  sleep 3
  back "home"
  sleep 3
  shot $label-07-back-home
  mark "$label: rotation"
  adb shell settings put system user_rotation 1 || true
  sleep 5
  shot $label-08-landscape
  adb shell settings put system user_rotation 0 || true
  sleep 5
  echo "$label: pid at the end: $(adb shell pidof $PKG | tr -d '\r')" >> $STEPLOG
  adb shell dumpsys activity exit-info $PKG < /dev/null > exit-info-$label.txt 2>&1 || true
  mark "$label: done"
  adb shell am force-stop $PKG || true
  sleep 3
}

run_case base apk-base/android-debug.apk
run_case debug apk-debug/android-debug.apk

kill $LOGCAT_PID 2>/dev/null || true
sleep 1
# QML warnings of each process, timestamps and pids cut off, then the ones only the tested APK has
for label in base debug; do
  pid=$(cat pid-$label.txt)
  awk -v p="$pid" '$3 == p { $1 = $2 = $3 = $4 = ""; sub(/^ +/, ""); print }' full_logcat.txt | grep -E "\.qml:|qml:|QML " | sort -u > qml-$label.txt
  echo "$label: QML warnings $(wc -l < qml-$label.txt), crash lines $(awk -v p="$pid" '$3 == p' full_logcat.txt | grep -c -E 'FATAL|SIGSEGV|SIGABRT')" >> $STEPLOG
done
echo "== QML warnings of debug that base did not have:" >> $STEPLOG
comm -13 qml-base.txt qml-debug.txt >> $STEPLOG
echo "== ANR / crash in the whole log:" >> $STEPLOG
grep -E "ANR in|FATAL EXCEPTION|Fatal signal" full_logcat.txt >> $STEPLOG || echo "none" >> $STEPLOG
