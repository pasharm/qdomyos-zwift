#!/bin/bash
# Test only (T-276): a crash in AndroidStatusBar::insetsChanged() when the screen is turned on
# after QZ has quit with the screen off. In a fork build (#define LICENSE) with no e-mail the
# license popup shows after 10 min and closes itself 2 min later with Qt.quit: main() returns and
# deletes the QML engine, but with the activity paused Qt keeps the activity until it is resumed.
# The reference APK (apk-base: the build that crashed on the phone) and the tested APK (apk-debug:
# the same master plus the fix) go through the same steps: a fresh start, the screen off for
# 13 min, the screen on and unlocked, a rotation - then the crash is looked for in logcat.
PKG=org.cagnulen.qdomyoszwift
LOG_DEBUG=${LOG_DEBUG:-true}
STEPLOG=steps.log
CONF='files/.config/Roberto Viola/qDomyos-Zwift.conf'
# the license timer (600 s) plus the popup auto close (120 s), with a margin
SCREEN_OFF_UNTIL=${SCREEN_OFF_UNTIL:-780}
: > $STEPLOG

# install_apk <apk>: a fresh install with the permissions granted
install_apk() {
  adb uninstall $PKG > /dev/null 2>&1 || true
  adb shell rm -rf /sdcard/Documents/QZ || true
  adb install "$1"
  for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION BLUETOOTH_ADVERTISE BLUETOOTH_CONNECT BLUETOOTH_SCAN POST_NOTIFICATIONS; do
    adb shell pm grant $PKG android.permission.$p || true
  done
  adb shell appops set $PKG MANAGE_EXTERNAL_STORAGE allow || true
  echo "== installed $1" >> $STEPLOG
}
adb shell cmd uimode night no || true
adb shell settings put global hide_error_dialogs 1 || true

# put_conf <extra lines>: the settings file of the app before a start (user_email stays empty)
put_conf() {
  printf '[General]\nlog_debug=%s\n%b' "$LOG_DEBUG" "$1" > qz.conf
  adb push qz.conf /data/local/tmp/qz.conf
  adb shell "run-as $PKG mkdir -p 'files/.config/Roberto Viola'"
  adb shell "run-as $PKG cp /data/local/tmp/qz.conf '$CONF'"
}
snap() {
  echo "-- snap $1" >> $STEPLOG
  adb shell screencap -p /sdcard/$1.png || true
  adb pull /sdcard/$1.png || true
}
mark() {
  echo "$(date +%H:%M:%S) $1" >> $STEPLOG
  adb shell log -t T276 "'$1'" || true
}
# top <label>: the resumed activity into the steps
top() {
  echo "$1: top $(adb shell dumpsys activity activities < /dev/null | grep -m1 topResumedActivity | tr -d '\r')" >> $STEPLOG
}
# qz_on_top: Health Connect onboarding (and the like) over QZ closed with the back key
qz_on_top() {
  local i
  for i in 1 2 3; do
    adb shell dumpsys activity activities < /dev/null | grep -m1 topResumedActivity | grep -q $PKG && return 0
    adb shell input keyevent KEYCODE_BACK || true
    sleep 3
  done
  return 1
}

adb logcat -c || true
adb logcat -b main,system,crash > full_logcat.txt 2>/dev/null &
LOGCAT_PID=$!

# run_case <label> <apk>
run_case() {
  local label="$1" pid t0 left
  install_apk "$2"
  adb shell settings put system accelerometer_rotation 0 || true
  adb shell settings put system user_rotation 0 || true
  put_conf "app_language=en\n"
  mark "$label: start"
  adb shell am start -n $PKG/$PKG.CustomQtActivity
  t0=$(date +%s)
  sleep 30
  qz_on_top || echo "$label: QZ NOT on top" >> $STEPLOG
  sleep 5
  top "$label started"
  pid=$(adb shell pidof $PKG | tr -d '\r')
  echo "$label: pid $pid" >> $STEPLOG
  snap $label-01-started
  mark "$label: screen off"
  adb shell input keyevent KEYCODE_SLEEP || true
  left=$((t0 + SCREEN_OFF_UNTIL - $(date +%s)))
  [ $left -gt 0 ] && sleep $left
  echo "$label: pid after the screen off: $(adb shell pidof $PKG | tr -d '\r')" >> $STEPLOG
  mark "$label: screen on"
  adb shell input keyevent KEYCODE_WAKEUP || true
  sleep 2
  adb shell wm dismiss-keyguard || true
  sleep 5
  top "$label screen on"
  snap $label-02-screen-on
  # the popup closed at the screen on and opened its link over QZ: back to QZ, as on the phone
  mark "$label: back to QZ"
  adb shell am start -n $PKG/$PKG.CustomQtActivity || true
  sleep 5
  top "$label back to QZ"
  echo "$label: pid after back to QZ: $(adb shell pidof $PKG | tr -d '\r')" >> $STEPLOG
  mark "$label: rotation"
  adb shell settings put system user_rotation 1 || true
  sleep 5
  adb shell settings put system user_rotation 0 || true
  sleep 10
  snap $label-03-after
  echo "$label: pid at the end: $(adb shell pidof $PKG | tr -d '\r')" >> $STEPLOG
  adb shell dumpsys activity exit-info $PKG < /dev/null > exit-info-$label.txt 2>&1 || true
  mark "$label: done"
  adb shell am force-stop $PKG || true
  sleep 3
}

run_case base apk-base/android-debug.apk
run_case debug apk-debug/android-debug.apk

adb shell "ps -A 2>/dev/null || ps" > process_list.txt || true
kill $LOGCAT_PID 2>/dev/null || true
wait $LOGCAT_PID 2>/dev/null || true

echo "== steps"; cat $STEPLOG
echo "== markers, main() return, insets, crashes"
grep -E "T276|exit app 0|Insets changed|onApplyWindowInsets - Top|patreon|Fatal signal|AndroidStatusBar|>>> $PKG <<<|Abort message|Cause:" full_logcat.txt | head -160 || true
echo "== exit-info"
for f in exit-info-*.txt; do echo "-- $f"; grep -E "ApplicationExitInfo|reason=|description=|timestamp=|pid=" "$f" | head -12; done
