#!/bin/bash
# Test only (T-384): App Language on Auto follows a Norwegian system. Four system locales, each after
# a reboot and a fresh install: nb-NO and nn-NO on Auto, en-US with Norwegian picked by hand, and
# de-DE on Auto as the control that the other languages did not change.
PKG=org.cagnulen.qdomyoszwift
STEPLOG=steps.log
CONF='files/.config/Roberto Viola/qDomyos-Zwift.conf'
: > $STEPLOG
: > full_logcat.txt
mkdir -p dumps qz-logs

wait_boot() {
  local i
  adb wait-for-device
  for i in $(seq 1 90); do
    [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = 1 ] && break
    sleep 2
  done
  sleep 10
}
set_locale() {
  adb root >> $STEPLOG 2>&1 || true
  wait_boot
  adb shell setprop persist.sys.locale "$1"
  adb reboot
  wait_boot
  echo "locale: prop $(adb shell getprop persist.sys.locale | tr -d '\r'), ro $(adb shell getprop ro.product.locale | tr -d '\r'), system_locales $(adb shell settings get system system_locales | tr -d '\r')" >> $STEPLOG
}
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
}
# put_conf [language]: a fake treadmill, so there is no first-run wizard; no language means Auto
put_conf() {
  printf '[General]\nlog_debug=true\nfakedevice_treadmill=true\n' > qz.conf
  [ -n "$1" ] && printf 'app_language=%s\n' "$1" >> qz.conf
  adb push qz.conf /data/local/tmp/qz.conf
  adb shell "run-as $PKG mkdir -p 'files/.config/Roberto Viola'"
  adb shell "run-as $PKG cp /data/local/tmp/qz.conf '$CONF'"
}
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
shot() {
  ensure_app
  echo "-- shot $1" >> $STEPLOG
  adb shell screencap -p /sdcard/$1.png || true
  adb pull /sdcard/$1.png || true
  [ -f ui.xml ] || dump
  [ -f ui.xml ] && cp ui.xml dumps/$1.xml
}

# case_run <prefix> <system locale> <app language or empty> <text expected in the app's log>
FAILED=0
case_run() {
  local prefix="$1" locale="$2" language="$3" expected="$4" f
  echo "== $prefix: system $locale, app language '${language:-auto}'" >> $STEPLOG
  set_locale "$locale"
  adb shell settings put global hide_error_dialogs 1 || true
  adb logcat -c || true
  adb logcat -v threadtime -b main,system,crash >> full_logcat.txt 2>/dev/null &
  local logcat_pid=$!
  install_apk apk-debug/android-debug.apk
  put_conf "$language"
  adb shell am start -n $PKG/$PKG.CustomQtActivity
  sleep 45
  shot $prefix-home
  adb shell input tap 84 168 || true
  sleep 3
  adb shell input swipe 500 700 500 2300 300 || true
  sleep 2
  shot $prefix-menu
  adb shell am force-stop $PKG || true
  kill $logcat_pid 2>/dev/null || true
  mkdir -p qz-logs/$prefix
  adb shell 'ls -la /sdcard/Documents/QZ/ 2>&1' > qz-logs/$prefix/listing.txt || true
  for f in $(adb shell 'ls /sdcard/Documents/QZ/ 2>/dev/null' | tr -d '\r' | grep '^debug-.*[.]log$'); do
    adb pull "/sdcard/Documents/QZ/$f" "qz-logs/$prefix/$f" > /dev/null 2>&1 || true
  done
  grep -h -E "Translation (loaded|file is empty)|No translation available|resolves to English" qz-logs/$prefix/debug-*.log | sed 's/^/   /' >> $STEPLOG
  if grep -h -q -F "$expected" qz-logs/$prefix/debug-*.log; then
    echo "check $prefix: OK ($expected)" >> $STEPLOG
  else
    echo "!! check $prefix: NOT FOUND ($expected)" >> $STEPLOG
    FAILED=1
  fi
}

case_run nb nb-NO "" 'Translation loaded successfully for "language" : "no"'
case_run nn nn-NO "" 'Translation loaded successfully for "language" : "no"'
case_run manual en-US no 'Translation loaded successfully for "locale" : "no"'
case_run de de-DE "" '"de'

echo "== ANR / crash in the whole log:" >> $STEPLOG
grep -E "ANR in|FATAL EXCEPTION|Fatal signal" full_logcat.txt >> $STEPLOG || echo "none" >> $STEPLOG
cat $STEPLOG
exit $FAILED
