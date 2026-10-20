#!/bin/bash
# Test only (T-211): the values in the settings search as their page shows them. The reference
# APK (apk-base, master) first, then the tested APK (apk-debug), each with the miles off and on:
# - "5 km pace" shown as 00:25:00 (not 300), 00:24:30 typed there kept as 294 s/km
# - "Warmup Speed (pace)" shown as 00:07:00 (not 420)
# - "Player Weight (kg)": 72,5 typed there kept as 72.5 (not 72)
# - the miles on: "Bike Weight (lbs)" 22 for 9.979044 kg, 25 typed there kept as 11.34 kg;
#   the height 5'9" for 175 cm, 5'10 typed there kept as 177.8 cm; "Max. Speed (mph)" 62.1
#   for 100 km/h, 10 typed there kept as 16.09 km/h
# - the results 1 s after the last key (300 ms instead of 1.5 s)
# Every check goes to checks.txt as PASS/FAIL with what the screen and the settings file had.
PKG=org.cagnulen.qdomyoszwift
CONF="files/.config/Roberto Viola/qDomyos-Zwift.conf"
UI_MODERN=${UI_MODERN:-false}
LOG_DEBUG=${LOG_DEBUG:-true}
STEPLOG=steps.log
CHECKS=checks.txt
: > $STEPLOG
: > $CHECKS
mkdir -p dumps

# install_apk <apk>: a fresh install with the permissions granted
install_apk() {
  adb uninstall $PKG > /dev/null 2>&1 || true
  # Android 14+: files of the previous install in Documents/QZ are hidden from the new one
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

# put_conf <extra lines>: the settings file of the app before a start
put_conf() {
  printf '[General]\nlog_debug=%s\nui_modern=%s\n%b' "$LOG_DEBUG" "$UI_MODERN" "$1" > qz.conf
  adb push qz.conf /data/local/tmp/qz.conf
  adb shell "run-as $PKG mkdir -p 'files/.config/Roberto Viola'"
  adb shell "run-as $PKG cp /data/local/tmp/qz.conf '$CONF'"
}

dump() {
  rm -f ui.xml
  timeout 25 adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1 || true
  adb pull /sdcard/ui.xml ui.xml > /dev/null 2>&1 || true
}
# Windows of other apps over this one (a launcher not responding, Health Connect): closed
ensure_app() {
  local i pkg xy
  for i in 1 2 3; do
    dump
    [ -f ui.xml ] || return 0
    pkg=$(python3 .github/uitap.py ui.xml --package)
    [ -z "$pkg" ] || [ "$pkg" = "$PKG" ] && return 0
    if grep -q "t responding" ui.xml && ! grep -q "QZ\|qdomyos" ui.xml &&
       xy=$(python3 .github/uitap.py ui.xml 'Close app'); then
      echo "!! $pkg: another app not responding, Close app at $xy" >> $STEPLOG
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
# shot name: frame and dump (dumps/<name>.xml); ui.xml stays the dump of this screen
shot() {
  ensure_app
  echo "-- shot $1" >> $STEPLOG
  adb shell screencap -p /sdcard/$1.png || true
  adb pull /sdcard/$1.png || true
  [ -f ui.xml ] || dump
  [ -f ui.xml ] && cp ui.xml dumps/$1.xml
}
# snap name: the frame alone, at once (a toast, the list right after typing)
snap() {
  echo "-- snap $1" >> $STEPLOG
  adb shell screencap -p /sdcard/$1.png || true
  adb pull /sdcard/$1.png || true
}
# tap_ui 'regex' [x y]: the control whose whole label matches, else the coordinates, else skipped
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
    echo "tap '$rx': NOT FOUND, skipped" >> $STEPLOG
    return 1
  fi
}
# tap_row 'anchor' 'target': the control in the row of the anchor (the OK of one field)
tap_row() {
  local xy=""
  ensure_app
  [ -f ui.xml ] || dump
  [ -f ui.xml ] && xy=$(python3 .github/uirow.py ui.xml "$1" "$2")
  if [ -n "$xy" ]; then
    echo "tap '$2' in the row of '$1' at $xy" >> $STEPLOG
    adb shell input tap $xy || true
  else
    echo "tap '$2' in the row of '$1': NOT FOUND" >> $STEPLOG
    return 1
  fi
}
tap() { ensure_app; echo "tap $1 $2 ($3)" >> $STEPLOG; adb shell input tap $1 $2 || true; }
back() { echo "back ($1)" >> $STEPLOG; adb shell input keyevent KEYCODE_BACK || true; }
hide_keyboard() {
  if adb shell dumpsys input_method | grep -q "mInputShown=true"; then
    back "keyboard"
    sleep 1
  fi
}
MENU="84 168"
open_menu() { tap $MENU "menu"; sleep 3; adb shell input swipe 500 700 500 2300 300 || true; sleep 2; }
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

adb logcat -c || true
adb logcat > full_logcat.txt 2>/dev/null &
LOGCAT_PID=$!

start_app() {
  adb shell am start -n $PKG/$PKG.CustomQtActivity
  sleep 20
  dump
  if [ -f ui.xml ] && [ "$(python3 .github/uitap.py ui.xml --package)" != "$PKG" ]; then
    back "health connect"
  fi
  sleep 15
}
# goto_settings: the menu and Settings, looked for by label up to three times
goto_settings() {
  local i
  for i in 1 2 3; do
    open_menu
    dump
    if [ -f ui.xml ] && python3 .github/uitap.py ui.xml '^Settings$' > /dev/null; then
      tap_ui '^Settings$'
      sleep 8
      return 0
    fi
    echo "goto settings: no Settings in the drawer, try $i" >> $STEPLOG
    snap goto-settings-fail-$i
    back "no drawer"
    sleep 3
  done
  return 1
}
# start_fresh <extra conf>: stop, settings file, start
start_fresh() {
  adb shell am force-stop $PKG || true
  put_conf "applewatch_fakedevice=true\napp_language=en\n$1"
  echo "== start: conf: $1" >> $STEPLOG
  sleep 3
  start_app
}
# start_set <key=value> ...: the keys changed in the full settings file the app wrote (a minimal
# file loses keys: Qt.labs.settings writes the defaults of all keys it did not read)
start_set() {
  local kv
  start_fresh ""
  sleep 5
  goto_settings
  sleep 5
  adb shell am force-stop $PKG || true
  for kv in "$@"; do
    adb shell "run-as $PKG sed -i 's/^${kv%%=*}=.*/$kv/' '$CONF'" || true
  done
  echo "== set: $*" >> $STEPLOG
  start_app
}

# conf_value key: the value the settings file keeps
conf_value() {
  adb shell "run-as $PKG cat '$CONF'" | tr -d '\r' | grep "^$1=" | head -1 | cut -d= -f2-
}
# check name ok detail: one line of checks.txt
check() {
  local verdict=FAIL
  [ "$2" = 1 ] && verdict=PASS
  echo "$verdict $TAG $1: $3" >> $CHECKS
}
# check_field name 'title regex' 'expected value': the dump of the screen has the title and the
# expected value among the labels right after it
check_field() {
  local after ok=0
  after=$([ -f ui.xml ] && python3 .github/uicheck.py ui.xml "$2" 6 | tr '\n' '|')
  printf '%s' "$after" | tr '|' '\n' | grep -qxF -- "$3" && ok=1
  check "$1" $ok "want '$3' after '$2', screen: ${after:-title NOT FOUND}"
}
# check_conf name key expected: the settings file keeps the expected number (0.01 off at most)
check_conf() {
  local v ok
  v=$(conf_value $2)
  ok=$(python3 -c 'import sys
try: print(1 if abs(float(sys.argv[1]) - float(sys.argv[2])) < 0.01 else 0)
except ValueError: print(0)' "$v" "$3")
  check "$1" $ok "want $2=$3, file: $2=${v:-(none)}"
}

# search 'text' name: the search of the settings with this text; a frame 1 s after the last key,
# then the screen with the keyboard closed
search() {
  local q="${1// /%s}" i
  if [ "$UI_MODERN" = "true" ]; then
    # Modern: the search field is the top row of the page (the toolbar button shows only once it
    # has scrolled away); the page back to its top first
    for i in 1 2 3; do adb shell input swipe 700 800 700 2200 150 || true; done
    sleep 1
    tap 600 330 "search field"
  else
    # Classic: the toolbar button shows the search bar and puts the focus in its field
    rm -f ui.xml
    tap_ui '^Search settings$' 1018 168
  fi
  sleep 2
  # The text of the previous search out
  adb shell input keyevent KEYCODE_MOVE_END || true
  for i in $(seq 1 20); do adb shell input keyevent KEYCODE_DEL || true; done
  adb shell input text "$q" || true
  sleep 1
  snap $TAG-$2-1s
  sleep 3
  hide_keyboard
  sleep 1
  shot $TAG-$2
}
# type_value 'field regex' 'text' name: the value field (found by its current text) cleared, the
# text typed and OK in its row; the frame with the toast
type_value() {
  if ! tap_ui "$1"; then
    check "$3 typed" 0 "field '$1' NOT FOUND"
    return 1
  fi
  sleep 2
  adb shell input keyevent KEYCODE_MOVE_END || true
  for i in $(seq 1 14); do adb shell input keyevent KEYCODE_DEL || true; done
  adb shell "input text \"$2\"" || true
  sleep 1
  hide_keyboard
  sleep 1
  local typed="${2//%s/ }"
  rm -f ui.xml
  tap_row "^$(printf '%s' "$typed" | sed 's/[.^$*+?()|\\]/\\&/g')$" '^OK$'
  sleep 1
  snap $TAG-$3-toast
  sleep 4
}

# One round in the classic look with the miles off
round_km() {
  search "5 km pace" pace
  check_field "5 km pace shown" '5 km pace.*' "00:25:00"
  # Modern: a time field is picked on wheels, not typed (UiTextField): the frame of the wheels only
  if [ "$UI_MODERN" = "true" ] && tap_ui '^00:25:00$'; then
    sleep 2
    snap $TAG-pace-wheels
    back "wheels"
    sleep 2
  else
    type_value '^(00:25:00|300)$' "00:24:30" pace-typed
    check_conf "5 km pace 00:24:30 kept" pacef_5km 294
  fi
  search "warmup speed" warmup
  check_field "warmup pace shown" 'Warmup Speed.*' "00:07:00"
  search "player weight" weight
  check_field "weight title" 'Player Weight \(kg\)' "75"
  type_value '^75$' "72,5" weight-typed
  check_conf "weight 72,5 kept" weight 72.5
}
# One round with the miles on, the bike weight 9.979044 kg (22 lbs)
round_miles() {
  search "bike weight" bike
  check_field "bike weight in lbs" 'Bike Weight \(lbs\)' "22"
  type_value '^(22|9\.979044)$' "25" bike-typed
  check_conf "bike weight 25 lbs kept" bike_weight 11.3398
  search "player height" height
  check_field "height in ft/in" 'Player Height \(ft/in\)' "5'9\""
  type_value "^(5'9\"|175)$" "5'10" height-typed
  check_conf "height 5'10 kept" height 177.8
  search "max. speed" speed
  check_field "max speed in mph" 'Max\. Speed \(mph\)' "62.1"
  type_value '^(62\.1|100(\.0)?)$' "10" speed-typed
  check_conf "max speed 10 mph kept" treadmill_speed_max 16.0934
}

for apk in apk-base apk-debug; do
  TAG=${apk#apk-}
  install_apk $apk/android-debug.apk
  start_fresh ""
  goto_settings
  shot $TAG-00-settings
  round_km
  start_set miles_unit=true bike_weight=9.979044
  goto_settings
  round_miles
done

adb shell "ps -A 2>/dev/null || ps" > process_list.txt || true
shot screenshot
kill $LOGCAT_PID 2>/dev/null || true
wait $LOGCAT_PID 2>/dev/null || true
adb logcat -d > end_logcat.txt || true
if [ "$(wc -l < full_logcat.txt)" -lt "$(wc -l < end_logcat.txt)" ]; then
  mv end_logcat.txt full_logcat.txt
else
  rm -f end_logcat.txt
fi
grep -E "ANR in" full_logcat.txt | sed 's/^/!! /' >> $STEPLOG || true
echo "== checks"; cat $CHECKS
echo "== steps"; cat $STEPLOG
echo "== QML warnings"; grep -iE "qrc:|\.qml:[0-9]+" full_logcat.txt | grep -iE "warning|error|ReferenceError|TypeError" | sort | uniq -c | sort -nr | head -60 || true
