#!/bin/bash
# Test only (T-306): the start button says "Resume" while the workout is paused. The tested APK
# (apk-debug) with a fake treadmill, in several languages: home, Pause, the paused frame, Resume,
# Stop. The reference APK (apk-base: before the change) - the same in en and ru, for the
# before/after frames. The buttons are tapped by coordinates: their labels change with the language.
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

# put_conf <lang>: the settings file of the app before a start - a fake treadmill, so the home
# page has tiles and no first-run wizard
put_conf() {
  printf '[General]\nlog_debug=%s\nui_modern=%s\nfakedevice_treadmill=true\napp_language=%s\n%b' "$LOG_DEBUG" "$UI_MODERN" "$1" "$EXTRA_CONF" > qz.conf
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
  adb shell log -t T306 "'$1'" || true
}
# The fake treadmill comes after the first search ends; the tile names are translated, so a
# fixed wait instead of looking for them (T-302: the tiles were there at the first look, 25 s)
wait_tiles() { sleep 20; }
# The start and the stop buttons of the top bar, both views (Nexus 6: 1440x2560 px)
STARTXY="497 468"
STOPXY="940 468"
tap_xy() { ensure_app; echo "tap $1 at $2" >> $STEPLOG; adb shell input tap $2 || true; }

adb logcat -c || true
adb logcat -v threadtime -b main,system,crash > full_logcat.txt 2>/dev/null &
LOGCAT_PID=$!

# run_lang <label> <lang>: the app (already installed) started in a language, through
# running -> paused -> resumed -> stopped
run_lang() {
  local label="$1-$2"
  adb shell am force-stop $PKG || true
  sleep 2
  put_conf "$2"
  mark "$label: start"
  adb shell am start -n $PKG/$PKG.CustomQtActivity
  sleep 25
  wait_tiles
  shot $label-01-running
  mark "$label: Pause"
  tap_xy pause "$STARTXY"
  sleep 4
  shot $label-02-paused
  mark "$label: Resume"
  tap_xy resume "$STARTXY"
  sleep 4
  shot $label-03-resumed
  mark "$label: Stop"
  tap_xy stop "$STOPXY"
  sleep 4
  shot $label-04-stopped
  mark "$label: done"
}

adb shell settings put system accelerometer_rotation 0 || true
adb shell settings put system user_rotation 0 || true

install_apk apk-base/android-debug.apk
for lang in en ru; do run_lang base $lang; done
install_apk apk-debug/android-debug.apk
for lang in en ru uk de fr cs; do run_lang debug $lang; done

# pause_on_start: the device connect pauses the workout and marks it stopped - the button must
# say "Start" (the next press resets the stats), not "Resume"
adb shell am force-stop $PKG || true
sleep 2
EXTRA_CONF='pause_on_start_treadmill=true\n'
put_conf ru
mark "debug-ru-pos: start"
adb shell am start -n $PKG/$PKG.CustomQtActivity
sleep 25
wait_tiles
shot debug-ru-pos-01-connected
sleep 3
shot debug-ru-pos-02-later
mark "debug-ru-pos: done"
adb shell am force-stop $PKG || true

kill $LOGCAT_PID 2>/dev/null || true
sleep 1
echo "== ANR / crash in the whole log:" >> $STEPLOG
grep -E "ANR in|FATAL EXCEPTION|Fatal signal" full_logcat.txt >> $STEPLOG || echo "none" >> $STEPLOG
