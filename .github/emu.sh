#!/bin/bash
# Test only (T-487, PR-4: header and side menu of the modern look). Two APKs on one emulator:
# apk-base - origin/master of the same commit, apk-head - the PR. Cases:
#  c-<apk>: classic look with a fake treadmill: home, open drawer, the Settings page from the drawer -
#           frames compared base against head afterwards (the classic look must not change);
#  b-<apk>-<look>: no equipment (wizard closed by bluetooth_lastdevice_name): the Bluetooth icon of the
#           home page must keep blinking - its screen reader name, read from 8 dumps, shows both states
#           (homeform::getDevice flips on every read: one more binding reading rootItem.device froze it);
#  m-head: modern look of the PR: header names (Main menu, Lock tiles), the drawer with its entries,
#           Settings reached from a drawer entry (the header shows Load/Save settings), Auto resistance
#           hidden with no equipment (b-head-modern).
PKG=org.cagnulen.qdomyoszwift
LOG_DEBUG=${LOG_DEBUG:-true}
STEPLOG=steps.log
CONF='files/.config/Roberto Viola/qDomyos-Zwift.conf'
: > $STEPLOG
mkdir -p dumps
FAILED=0
# Toolbar menu / back button by its place (Nexus 6, 3.5 px per dp): classic buttons have no names
MENU="84 168"

install_apk() {
  adb uninstall $PKG > /dev/null 2>&1 || true
  adb shell rm -rf /sdcard/Documents/QZ || true
  adb install "$1"
  adb shell pm path $PKG > /dev/null || { echo "!! $1 not installed - the run proves nothing" >> $STEPLOG; cat $STEPLOG; exit 1; }
  for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION BLUETOOTH_ADVERTISE BLUETOOTH_CONNECT BLUETOOTH_SCAN POST_NOTIFICATIONS; do
    adb shell pm grant $PKG android.permission.$p || true
  done
  adb shell appops set $PKG MANAGE_EXTERNAL_STORAGE allow || true
  for p in EXERCISE DISTANCE TOTAL_CALORIES_BURNED HEART_RATE POWER SPEED CYCLING_PEDALING_CADENCE ELEVATION_GAINED STEPS STEPS_CADENCE HEART_RATE_VARIABILITY; do
    adb shell pm grant $PKG android.permission.health.WRITE_$p || true
  done
  echo "== installed $1" >> $STEPLOG
}
adb shell settings put global hide_error_dialogs 1 || true

# put_conf <ui_modern> <equipment: fake|none>
put_conf() {
  if [ "$2" = fake ]; then
    printf '[General]\nlog_debug=%s\nui_modern=%s\nfakedevice_treadmill=true\n' "$LOG_DEBUG" "$1" > qz.conf
  else
    printf '[General]\nlog_debug=%s\nui_modern=%s\nbluetooth_lastdevice_name=NO-SUCH-DEVICE\n' "$LOG_DEBUG" "$1" > qz.conf
  fi
  adb push qz.conf /data/local/tmp/qz.conf
  adb shell "run-as $PKG mkdir -p 'files/.config/Roberto Viola' < /dev/null"
  adb shell "run-as $PKG cp /data/local/tmp/qz.conf '$CONF' < /dev/null"
  adb shell "run-as $PKG ls -l '$CONF' < /dev/null" >> $STEPLOG 2>&1 || { echo "!! qz.conf not written - the run proves nothing" >> $STEPLOG; cat $STEPLOG; exit 1; }
}
dump() {
  rm -f ui.xml
  timeout 25 adb shell uiautomator dump /sdcard/ui.xml < /dev/null > /dev/null 2>&1 || true
  adb pull /sdcard/ui.xml ui.xml > /dev/null 2>&1 || true
}
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
wait_ui() {
  local i
  for i in $(seq 1 $(( ${2:-30} / 3 ))); do
    dump
    [ -f ui.xml ] && python3 .github/uitap.py ui.xml "$1" > /dev/null && return 0
    sleep 2
  done
  return 1
}
HOME_RX='^Start$|^Stop$|^Pause$'
wait_home() {
  local i
  for i in 1 2 3 4; do
    ensure_app
    wait_ui "$HOME_RX" 30 && return 0
  done
  return 1
}
# expect <shot> 'regex' <what>: the dump of the shot has a control with that whole text or name
expect() {
  if [ -f dumps/$1.xml ] && python3 .github/uitap.py dumps/$1.xml "$2" > /dev/null; then
    echo "check $1: $3: OK" >> $STEPLOG
  else
    echo "!! check $1: $3: '$2' not in the dump" >> $STEPLOG
    FAILED=1
  fi
}
# expect_not <shot> 'regex' <what>
expect_not() {
  if [ -f dumps/$1.xml ] && ! python3 .github/uitap.py dumps/$1.xml "$2" > /dev/null; then
    echo "check $1: $3: OK" >> $STEPLOG
  else
    echo "!! check $1: $3: '$2' is in the dump" >> $STEPLOG
    FAILED=1
  fi
}
# start_case <name> <ui_modern> <fake|none>
start_case() {
  echo "== $1: start (ui_modern=$2, equipment $3)" >> $STEPLOG
  adb shell am force-stop $PKG || true
  sleep 2
  put_conf "$2" "$3"
  adb shell am start -n $PKG/$PKG.CustomQtActivity
  if ! wait_home; then
    echo "!! $1: home page not shown in 120 s" >> $STEPLOG
    shot $1-0-no-home
    FAILED=1
    return 1
  fi
  echo "pid $1 $(adb shell pidof $PKG | tr -d '\r')" >> $STEPLOG
  sleep 10
  dump
  if [ -f ui.xml ] && xy=$(python3 .github/uitap.py ui.xml '^Later$'); then
    echo "tap Later at $xy" >> $STEPLOG
    adb shell input tap $xy || true
    sleep 2
  fi
  return 0
}
# open_drawer <shot> 'regex of an entry': menu button, then the entry shows (the drawer is open)
open_drawer() {
  local i
  for i in 1 2 3; do
    ensure_app
    echo "tap menu $MENU" >> $STEPLOG
    adb shell input tap $MENU || true
    sleep 3
    if wait_ui "$2" 9; then
      sleep 1
      shot $1
      echo "drawer open ('$2' shown)" >> $STEPLOG
      return 0
    fi
    adb shell input keyevent KEYCODE_BACK || true
    sleep 2
  done
  echo "!! $1: drawer did not open ('$2' not shown)" >> $STEPLOG
  FAILED=1
  return 1
}
# tap_entry 'regex' 'landing regex': an entry of the open drawer, then the page shows its own control
tap_entry() {
  local xy=""
  dump
  [ -f ui.xml ] && xy=$(python3 .github/uitap.py ui.xml "$1")
  if [ -z "$xy" ]; then
    echo "!! entry '$1': NOT FOUND" >> $STEPLOG
    FAILED=1
    return 1
  fi
  echo "tap '$1': at $xy" >> $STEPLOG
  adb shell input tap $xy || true
  if wait_ui "$2" 30; then
    echo "page of '$1' open ('$2' shown)" >> $STEPLOG
    sleep 2
    return 0
  fi
  echo "!! page of '$1': '$2' not shown" >> $STEPLOG
  FAILED=1
  return 1
}
# blink <case>: the Bluetooth icon of the home page names both states over 8 dumps
blink() {
  local i s seen_on=0 seen_off=0
  for i in 1 2 3 4 5 6 7 8; do
    dump
    s=$(grep -o 'Bluetooth connection: Device [a-z ]*connected' ui.xml 2>/dev/null | head -n 1)
    echo "blink $1 $i: '$s'" >> $STEPLOG
    case "$s" in
      *"Device connected") seen_on=1 ;;
      *"Device not connected") seen_off=1 ;;
    esac
    sleep 1
  done
  if [ $seen_on = 1 ] && [ $seen_off = 1 ]; then
    echo "check $1: Bluetooth icon blinks with no equipment: OK" >> $STEPLOG
  else
    echo "!! check $1: Bluetooth icon frozen (connected seen $seen_on, not connected seen $seen_off)" >> $STEPLOG
    FAILED=1
  fi
}

adb logcat -c || true
adb logcat -v threadtime -b main,system,crash > full_logcat.txt 2>/dev/null &
LOGCAT_PID=$!
adb shell settings put system accelerometer_rotation 0 || true
adb shell settings put system user_rotation 0 || true
echo "== API $(adb shell getprop ro.build.version.sdk | tr -d '\r')" >> $STEPLOG

for side in base head; do
  install_apk apk-$side/android-debug.apk
  # Classic look, fake treadmill: frames for the base/head comparison
  if start_case c-$side false fake; then
    shot c-$side-1-home
    if open_drawer c-$side-2-drawer '^Settings$'; then
      tap_entry '^Settings$' '^General Options$|^Search settings$' && shot c-$side-3-settings
    fi
  fi
  adb shell am force-stop $PKG || true
  # Classic look, no equipment: the Bluetooth icon keeps blinking
  if start_case b-$side-classic false none; then
    shot b-$side-classic-1-home
    blink b-$side-classic
  fi
  adb shell am force-stop $PKG || true
done

# Modern look of the PR (apk-head is installed last)
if start_case m-head true fake; then
  shot m-head-1-home
  expect m-head-1-home '^Main menu$' "header: the menu button has its name"
  expect m-head-1-home '^Lock tiles$|^Unlock tiles$' "header: the tiles lock has its name"
  if open_drawer m-head-2-drawer '^Settings$'; then
    expect m-head-2-drawer '^Workouts History$' "drawer: a workout entry"
    expect m-head-2-drawer '^Workout$' "drawer: the Workout group"
    tap_entry '^Settings$' '^Save settings$' && shot m-head-3-settings
    expect m-head-3-settings '^Load settings$' "settings page: Load settings in the header"
    expect m-head-3-settings '^Back$' "settings page: the arrow is named Back"
  fi
fi
adb shell am force-stop $PKG || true
if start_case b-head-modern true none; then
  shot b-head-modern-1-home
  expect_not b-head-modern-1-home '.*auto resistance' "no equipment: Auto resistance hidden"
  blink b-head-modern
fi
adb shell am force-stop $PKG || true

kill $LOGCAT_PID 2>/dev/null || true
wait $LOGCAT_PID 2>/dev/null || true
echo "== QML errors of main.qml / UiDrawerItem.qml (for reading):" >> $STEPLOG
grep -a -E "(main|UiDrawerItem)\.qml.*(TypeError|ReferenceError|Error)" full_logcat.txt | sed 's/.*qDomyos-Zwift: //' | sort | uniq -c | head -n 20 >> $STEPLOG || true
echo "== ANR / crash in the whole log:" >> $STEPLOG
if grep -a -E "ANR in|FATAL EXCEPTION|Fatal signal" full_logcat.txt >> $STEPLOG; then
  echo "!! check log: ANR or crash" >> $STEPLOG; FAILED=1
else
  echo "none" >> $STEPLOG
fi
grep -q "^check " $STEPLOG || { echo "!! no check ran: the run proves nothing" >> $STEPLOG; FAILED=1; }
cat $STEPLOG
exit $FAILED
