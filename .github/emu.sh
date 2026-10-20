#!/bin/bash
# Test only (T-084): the appearance "As on the phone" (ui_theme_mode=auto) of the modern look.
# Before Android 10 the system has no dark theme, and the reference APK (apk-base) turns the page
# light there; the fix (apk-debug) keeps it dark below API 29 and follows the night mode above.
# Each frame gets its brightness in steps.log (luma.py) and the night bit of the system
# configuration (am get-config: night / notnight).
PKG=org.cagnulen.qdomyoszwift
STEPLOG=steps.log
CONF='files/.config/Roberto Viola/qDomyos-Zwift.conf'
: > $STEPLOG
mkdir -p dumps
API=$(adb shell getprop ro.build.version.sdk | tr -d '\r')
echo "== API $API" >> $STEPLOG

# install_apk <apk>: a fresh install with the permissions granted
install_apk() {
  adb uninstall $PKG > /dev/null 2>&1 || true
  adb shell rm -rf /sdcard/Documents/QZ || true
  adb install "$1"
  for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION BLUETOOTH_ADVERTISE BLUETOOTH_CONNECT BLUETOOTH_SCAN \
           READ_EXTERNAL_STORAGE WRITE_EXTERNAL_STORAGE POST_NOTIFICATIONS; do
    adb shell pm grant $PKG android.permission.$p > /dev/null 2>&1 || true
  done
  adb shell appops set $PKG MANAGE_EXTERNAL_STORAGE allow > /dev/null 2>&1 || true
  echo "== installed $1" >> $STEPLOG
}
adb shell settings put global hide_error_dialogs 1 || true
# Location on, otherwise the "Permissions Required" dialog covers the app (as upstream main.yml)
adb shell settings put secure location_mode 3 || true
adb shell settings put secure location_providers_allowed +gps,+network || true
adb shell cmd location set-location-enabled true || true

# nightbit: the night part of the system configuration as the app reads it
nightbit() {
  local b
  b=$(adb shell am get-config 2>/dev/null | tr -d '\r' | grep '^config:' | tr ' -' '\n\n' | grep -x 'night\|notnight' | head -1)
  echo "${b:-undefined}"
}
# night yes|no: the night mode of the system (cmd uimode; logged when the command is missing)
night() {
  local out
  out=$(adb shell cmd uimode night "$1" 2>&1 | tr -d '\r')
  echo "night $1: '$out', config now: $(nightbit)" >> $STEPLOG
}

# put_conf <ui_modern> <extra lines>: the settings file of the app before a start
put_conf() {
  printf '[General]\nlog_debug=false\napplewatch_fakedevice=true\napp_language=en\nui_modern=%s\n%b' "$1" "$2" > qz.conf
  adb push qz.conf /data/local/tmp/qz.conf > /dev/null
  adb shell "run-as $PKG mkdir -p 'files/.config/Roberto Viola'"
  adb shell "run-as $PKG cp /data/local/tmp/qz.conf '$CONF'"
}

# The control tree of the screen into ui.xml (empty when uiautomator gives up)
dump() {
  rm -f ui.xml
  timeout 25 adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1 || true
  adb pull /sdcard/ui.xml ui.xml > /dev/null 2>&1 || true
}
# Another app over QZ (a "not responding" dialog, Health Connect): closed before a frame
ensure_app() {
  local i pkg xy
  for i in 1 2 3; do
    dump
    [ -f ui.xml ] || return 0
    pkg=$(python3 .github/uitap.py ui.xml --package)
    [ -z "$pkg" ] || [ "$pkg" = "$PKG" ] && return 0
    if grep -q "t responding" ui.xml && xy=$(python3 .github/uitap.py ui.xml '(Close app|Wait|OK)'); then
      echo "!! $pkg not responding: tap at $xy" >> $STEPLOG
      adb shell input tap $xy || true
    else
      echo "!! $pkg over the app: back key" >> $STEPLOG
      adb shell input keyevent KEYCODE_BACK || true
    fi
    sleep 3
  done
}
# shot <name>: the frame, its control tree, its brightness and the night bit
shot() {
  ensure_app
  adb shell screencap -p /sdcard/$1.png || true
  adb pull /sdcard/$1.png > /dev/null 2>&1 || true
  [ -f ui.xml ] && cp ui.xml dumps/$1.xml
  echo "-- shot $1: $(python3 .github/luma.py $1.png 2>&1), config $(nightbit)" >> $STEPLOG
}

adb logcat -c || true
adb logcat > full_logcat.txt 2>/dev/null &
LOGCAT_PID=$!

# start <ui_modern> <extra conf>: the app stopped, its settings written, started again
start() {
  adb shell am force-stop $PKG || true
  put_conf "$1" "$2"
  echo "== start, ui_modern=$1, conf: $2" >> $STEPLOG
  sleep 2
  adb shell am start -n $PKG/$PKG.CustomQtActivity > /dev/null
  sleep 35
}

# 1. Reference, auto: the page at a start without night, then the night turned on while it runs
night no
install_apk apk-base/android-debug.apk
start true "ui_theme_mode=auto\n"
shot b-1-auto-notnight
night yes
sleep 6
shot b-2-auto-night-live
night no

# 2. The fix
install_apk apk-debug/android-debug.apk
start true "ui_theme_mode=auto\n"
shot a-1-auto-notnight
night yes
sleep 6
shot a-2-auto-night-live
night no
sleep 6
shot a-3-auto-notnight-live
# a start while the night is on
night yes
start true "ui_theme_mode=auto\n"
shot a-4-auto-night-start
# "Light" and "Dark" are fixed whatever the night mode
start true "ui_theme_mode=light\n"
shot a-5-light-night
night no
start true "ui_theme_mode=light\n"
shot a-6-light-notnight
start true "ui_theme_mode=dark\n"
shot a-7-dark-notnight
# the classic look: dark as before
start false "ui_theme_mode=auto\n"
shot a-8-classic-notnight

kill $LOGCAT_PID 2>/dev/null || true
wait $LOGCAT_PID 2>/dev/null || true
grep -E "ANR in|FATAL EXCEPTION" full_logcat.txt | sed 's/^/!! /' >> $STEPLOG || true
echo "== steps"; cat $STEPLOG
echo "== QML warnings"; grep -iE "qrc:|\.qml:[0-9]+" full_logcat.txt | grep -iE "warning|error|ReferenceError|TypeError" | sort | uniq -c | sort -nr | head -40 || true
