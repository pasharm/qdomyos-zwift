#!/bin/bash
# Test only (T-386): Preset Gear Profiles on the Wahoo Options page, the way the user of issue 5508
# went: pick Reality Bender, leave the page, quit the app, start it again, open the page. The build
# without the change first, then the one with it. Same steps for both, frames b-* and a-*.
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
  printf '[General]\nlog_debug=%s\nui_modern=%s\nfakedevice_treadmill=true\napp_language=en\n' "$LOG_DEBUG" "$UI_MODERN" > qz.conf
  adb push qz.conf /data/local/tmp/qz.conf
  adb shell "run-as $PKG mkdir -p 'files/.config/Roberto Viola'"
  adb shell "run-as $PKG cp /data/local/tmp/qz.conf '$CONF'"
}
dump() {
  rm -f ui.xml
  timeout 25 adb shell uiautomator dump /sdcard/ui.xml < /dev/null > /dev/null 2>&1 || true
  adb pull /sdcard/ui.xml ui.xml > /dev/null 2>&1 || true
}
# A window of another app over QZ closed with the back key
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

# From the home page to the top of Wahoo Options
open_wahoo() {
  tap 84 168 "menu"
  sleep 3
  adb shell input swipe 500 700 500 2300 300 || true
  sleep 2
  tap_drawer '^Settings$' 400 900
  sleep 8
  scroll_to 'Bike Options' 20 || return 1
  tap_ui 'Bike Options'
  sleep 5
  scroll_to 'Wahoo Options' 40 || return 1
  # A link at the very bottom may sit under the navigation bar
  local y
  y=$(python3 .github/uitap.py ui.xml 'Wahoo Options' | cut -d" " -f2)
  if [ -n "$y" ] && [ "$y" -gt 2100 ]; then
    adb shell input swipe 700 1800 700 1200 400 || true
    sleep 2
    rm -f ui.xml
  fi
  tap_ui 'Wahoo Options' || return 1
  sleep 6
}
# The list of presets in view: it is right above the Add Gear button
to_presets() {
  scroll_to 'Add Gear' 12 || return 1
  ADD_XY=$(python3 .github/uitap.py ui.xml 'Add Gear')
}
PRESET_RX='Select a profile.*|(Time Trial|Rolling Hills|Alpine|Reality Bender|Explorer) \(.*'
# What the saved settings say, in the log; check_table <prefix> <start of the table>
check_table() {
  local line
  line=$(adb shell "run-as $PKG cat '$CONF'" | tr -d '\r' | grep -a '^gear_configuration' | cut -c1-48)
  echo "   $1: ${line:-no gear_configuration}" >> $STEPLOG
  case "$line" in
    "gear_configuration=$2"*) echo "check $1: OK" >> $STEPLOG ;;
    *) echo "!! check $1: expected $2" >> $STEPLOG; FAILED=1 ;;
  esac
}

adb logcat -c || true
adb logcat -v threadtime -b main,system,crash > full_logcat.txt 2>/dev/null &
LOGCAT_PID=$!
adb shell settings put system accelerometer_rotation 0 || true
adb shell settings put system user_rotation 0 || true

# case_run <prefix> <apk>
case_run() {
  local prefix="$1" xy x y
  install_apk "$2"
  put_conf
  echo "== $prefix: start" >> $STEPLOG
  adb shell am start -n $PKG/$PKG.CustomQtActivity
  sleep 45
  shot $prefix-0-home
  open_wahoo || { echo "!! $prefix: Wahoo Options not reached" >> $STEPLOG; FAILED=1; return; }
  to_presets || { FAILED=1; return; }
  shot $prefix-1-default
  python3 .github/uitap.py ui.xml "$PRESET_RX" >> $STEPLOG 2>&1 || echo "list not in the dump, by its place above Add Gear" >> $STEPLOG
  x=${ADD_XY% *}
  y=${ADD_XY#* }
  tap_ui "$PRESET_RX" "$x" $((y - 406))
  sleep 3
  shot $prefix-2-list-open
  # The list opens over its field: the fourth item is 3.5 items of 48 dp below its top
  tap_ui 'Reality Bender.*' "$x" $((y - 406 - 84 + 588))
  sleep 4
  shot $prefix-3-picked
  sleep 6
  check_table $prefix-picked '1|75|100|true'

  # Back to the settings and the page opened again
  back "page"
  sleep 4
  scroll_top
  scroll_to 'Wahoo Options' 40
  tap_ui 'Wahoo Options'
  sleep 6
  to_presets
  shot $prefix-4-reopened

  # The app quit and started again: this is what the user of issue 5508 did
  back "page"
  sleep 8
  adb shell am force-stop $PKG || true
  sleep 3
  adb shell am start -n $PKG/$PKG.CustomQtActivity
  sleep 35
  shot $prefix-5-home-after-restart
  open_wahoo || { echo "!! $prefix: Wahoo Options not reached after the restart" >> $STEPLOG; FAILED=1; return; }
  to_presets
  shot $prefix-6-after-restart
  check_table $prefix-after-restart '1|75|100|true'

  # Reset All Gears: the list leaves the preset behind
  scroll_to 'Reset All Gears' 6 && tap_ui 'Reset All Gears'
  sleep 4
  shot $prefix-7-after-reset
  sleep 6
  check_table $prefix-after-reset '1|38|44|true'
  adb shell am force-stop $PKG || true
  sleep 2
}

case_run b apk-base/android-debug.apk
case_run a apk-debug/android-debug.apk

kill $LOGCAT_PID 2>/dev/null || true
wait $LOGCAT_PID 2>/dev/null || true
echo "== QML warnings of the page" >> $STEPLOG
grep -a -E "gears\.qml|UiComboBox" full_logcat.txt | grep -a -v "onCompleted\|onValueChanged\|onCurrentIndexChanged\|onSettingsChanged\|onGearSettingsChanged" | tail -n 40 >> $STEPLOG || true
echo "== ANR / crash in the whole log:" >> $STEPLOG
grep -a -E "ANR in|FATAL EXCEPTION|Fatal signal" full_logcat.txt >> $STEPLOG || echo "none" >> $STEPLOG
cat $STEPLOG
exit $FAILED
