#!/bin/bash
# Test only (T-312): the modern home buttons follow the workout state - one wide Start or Pause,
# while paused Resume and a red Stop (no Lap), a new set fades in for 0.5 s and takes taps only
# then; the block under the toolbar is lower (12 / 8 / 16 dp). The tested APK (apk-debug) with a
# fake treadmill: the states and their changes, a double tap on Pause, the largest text size,
# landscape, pause_on_start, the classic look unchanged. The reference APK (apk-base:
# feat/modern-ui before the change) - the same home in both looks, for the before/after frames.
# The buttons are tapped by coordinates (Nexus 6, 1440x2560 px).
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

# put_conf <lang> <modern> [extra lines]: the settings file of the app before a start - a fake
# treadmill, so the home page has tiles and no first-run wizard
put_conf() {
  printf '[General]\nlog_debug=%s\nui_modern=%s\nfakedevice_treadmill=true\napp_language=%s\n%b' "$LOG_DEBUG" "$2" "$1" "$3" > qz.conf
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
# quick <label>: a frame right away, without the control tree (the fade-in is 0.5 s)
quick() {
  echo "-- quick $1" >> $STEPLOG
  adb shell screencap -p /sdcard/$1.png || true
  adb pull /sdcard/$1.png || true
}
mark() {
  echo "$(date +%H:%M:%S) $1" >> $STEPLOG
  adb shell log -t T312 "'$1'" || true
}
# The fake treadmill comes after the first search ends; the tile names are translated, so a
# fixed wait instead of looking for them (T-302: the tiles were there at the first look, 25 s)
wait_tiles() { sleep 20; }
tap_xy() { ensure_app; echo "$(date +%H:%M:%S.%N | cut -c1-12) tap $1 at $2" >> $STEPLOG; adb shell input tap $2 || true; }

# Modern buttons after the change: the row is 12 dp under the toolbar, centre y 421 px
# (measured on run 40645708263).
# One wide Start/Pause 286..1154 px; paused: Resume 286..804, Stop 832..1350
WIDEXY="720 421"
RESUMEXY="545 421"
STOPXY="1091 421"
# the right part of the wide Pause - where Stop comes when it pauses
WIDERIGHTXY="1050 421"
# Before the change (apk-base) and the classic look: Start 286..706, Stop 734..1154, centre y 463
OLDSTARTXY="497 468"
OLDSTOPXY="940 468"

adb logcat -c || true
adb logcat -v threadtime -b main,system,crash > full_logcat.txt 2>/dev/null &
LOGCAT_PID=$!

adb shell settings put system accelerometer_rotation 0 || true
adb shell settings put system user_rotation 0 || true

# launch <label> <lang> <modern> [extra conf lines]: the app (already installed) started fresh
launch() {
  adb shell am force-stop $PKG || true
  sleep 2
  put_conf "$2" "$3" "$4"
  mark "$1: start"
  adb shell am start -n $PKG/$PKG.CustomQtActivity
  sleep 25
  wait_tiles
}
# rotate <0|1>: portrait or landscape
# (run 40645708263: the settings alone with 4 s left the frame in portrait - the window manager
# command as well, and longer)
rotate() {
  adb shell settings put system user_rotation $1 || true
  adb shell cmd window user-rotation lock $1 || true
  sleep 8
  echo "rotation now: $(adb shell dumpsys window displays | grep -o 'mRotation=[0-9A-Z_]*' | head -1)" >> $STEPLOG
}

# --- the reference: home before the change, both looks
install_apk apk-base/android-debug.apk
launch base-modern ru true
shot base-modern-01-running
tap_xy pause "$OLDSTARTXY"
sleep 4
shot base-modern-02-paused
launch base-classic ru false
shot base-classic-01-running

# --- the tested APK, modern look, ru
install_apk apk-debug/android-debug.apk
launch debug-ru ru true
shot debug-ru-01-running
mark "debug-ru: Pause"
tap_xy pause "$WIDEXY"
quick debug-ru-02-fading
sleep 4
shot debug-ru-03-paused
mark "debug-ru: Resume"
tap_xy resume "$RESUMEXY"
sleep 4
shot debug-ru-04-resumed
# A double tap on the right part of Pause: the second tap comes where Stop appears - it must
# not stop the workout (the buttons take taps only after the fade-in)
mark "debug-ru: double tap on Pause"
echo "$(date +%H:%M:%S.%N | cut -c1-12) double tap at $WIDERIGHTXY" >> $STEPLOG
adb shell "input tap $WIDERIGHTXY & sleep 0.15; input tap $WIDERIGHTXY; wait" || true
echo "$(date +%H:%M:%S.%N | cut -c1-12) double tap sent" >> $STEPLOG
sleep 4
shot debug-ru-05-after-double-tap
mark "debug-ru: landscape, paused"
rotate 1
shot debug-ru-06-landscape-paused
rotate 0
mark "debug-ru: Stop"
tap_xy stop "$STOPXY"
sleep 6
shot debug-ru-07-stopped
adb shell input keyevent KEYCODE_BACK || true
sleep 4
shot debug-ru-08-home-stopped
mark "debug-ru: landscape, stopped"
rotate 1
shot debug-ru-09-landscape-stopped
rotate 0
mark "debug-ru: Start after Stop"
tap_xy start "$WIDEXY"
sleep 4
shot debug-ru-10-started-again

# other languages: the paused pair (labels in 148 dp)
for lang in en uk de; do
  launch debug-$lang $lang true
  shot debug-$lang-01-running
  tap_xy pause "$WIDEXY"
  sleep 4
  shot debug-$lang-03-paused
done

# the largest text size (170 %, set in the app): the status line under the buttons, the tiles
launch debug-ru-big ru true 'ui_text_scale_system=false\nui_text_scale=170\n'
shot debug-ru-big-01-running
tap_xy pause "$WIDEXY"
sleep 4
shot debug-ru-big-03-paused

# pause_on_start: the device connect pauses the workout and marks it stopped - one wide Start
launch debug-ru-pos ru true 'pause_on_start_treadmill=true\n'
shot debug-ru-pos-01-connected

# the classic look: two buttons as before, the same place
launch debug-classic ru false
shot debug-classic-01-running
tap_xy pause "$OLDSTARTXY"
sleep 4
shot debug-classic-02-paused
tap_xy stop "$OLDSTOPXY"
sleep 6
shot debug-classic-03-stopped
adb shell am force-stop $PKG || true

kill $LOGCAT_PID 2>/dev/null || true
sleep 1
echo "== ANR / crash in the whole log:" >> $STEPLOG
grep -E "ANR in|FATAL EXCEPTION|Fatal signal" full_logcat.txt >> $STEPLOG || echo "none" >> $STEPLOG
echo "== QML warnings of homeform/HomeForm/Home:" >> $STEPLOG
grep -E "HomeForm.ui.qml|Home.qml" full_logcat.txt | grep -i -E "warn|error|TypeError|ReferenceError|binding loop" | head -40 >> $STEPLOG || echo "none" >> $STEPLOG
