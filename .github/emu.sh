#!/bin/bash
# Test only (T-211): the values of the settings search results in the units of their page.
# "Use Miles unit in UI" on, the bike weight 9.979044 kg (22 lbs), the player weight 85 kg, the
# paces at their defaults (5 km: 300 s/km = 00:25:00). Side b is master without the fix (input
# baseline): the results show the stored numbers - 300, 9.979044, 85 - and names without a unit.
# Side a is the build with the fix (input source): 00:25:00, 22 and 187.39 with "(lbs)" in the
# name; then again in Russian, where the name comes from the page's template "Вес велосипеда (%1)".
# Frames b-*, a-*, r-*; steps.log has the checks, read from the dumps of the frames.
PKG=org.cagnulen.qdomyoszwift
STEPLOG=steps.log
CONF='files/.config/Roberto Viola/qDomyos-Zwift.conf'
: > $STEPLOG
mkdir -p dumps

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
  # Health Connect write permissions granted: otherwise QZ opens its request (and the Health
  # Connect onboarding) over itself at the first start (HealthConnectHelper.writePermissions)
  for p in EXERCISE DISTANCE TOTAL_CALORIES_BURNED HEART_RATE POWER SPEED CYCLING_PEDALING_CADENCE ELEVATION_GAINED STEPS STEPS_CADENCE HEART_RATE_VARIABILITY; do
    adb shell pm grant $PKG android.permission.health.WRITE_$p || echo "!! health WRITE_$p not granted" >> $STEPLOG
  done
  echo "== installed $1" >> $STEPLOG
}
adb shell cmd uimode night no || true
adb shell settings put global hide_error_dialogs 1 || true

# put_conf [language]: a fake device, so there is no first-run wizard; miles, the weights
put_conf() {
  printf '[General]\nlog_debug=true\napplewatch_fakedevice=true\nmiles_unit=true\nbike_weight=9.979044\nweight=85\n' > qz.conf
  [ -n "$1" ] && printf 'app_language=%s\n' "$1" >> qz.conf
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
# A window of another app over QZ closed: "<app> isn't responding" with Wait, the rest (Health Connect) with back
ensure_app() {
  local i pkg xy
  for i in 1 2 3; do
    dump
    [ -f ui.xml ] || return 0
    pkg=$(python3 .github/uitap.py ui.xml --package)
    [ -z "$pkg" ] || [ "$pkg" = "$PKG" ] && return 0
    xy=$(python3 .github/uitap.py ui.xml 'Wait')
    if [ -n "$xy" ]; then
      echo "!! $pkg over the app: not responding dialog, Wait" >> $STEPLOG
      adb shell input tap $xy || true
    else
      echo "!! $pkg over the app: back key" >> $STEPLOG
      adb shell input keyevent KEYCODE_BACK || true
    fi
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
tap() { ensure_app; echo "tap $1 $2 ($3)" >> $STEPLOG; adb shell input tap $1 $2 || true; }
# tap_ui 'regex' [x y]: the control whose whole text or accessible name matches
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
# A drawer entry that may be below the fold: one swipe up and a second look
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
# The topmost text field of the screen (the search bar has no accessible name in master)
tap_field() {
  local xy=""
  dump
  [ -f ui.xml ] && xy=$(python3 -c '
import re, sys, xml.etree.ElementTree as ET
best = None
for n in ET.parse(sys.argv[1]).getroot().iter("node"):
    if n.get("class") != "android.widget.EditText":
        continue
    m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", n.get("bounds") or "")
    if not m:
        continue
    x1, y1, x2, y2 = map(int, m.groups())
    if x2 > x1 and y2 > y1 and (best is None or y1 < best[1]):
        best = ((x1 + x2) // 2, y1, (y1 + y2) // 2)
if best:
    print(best[0], best[2])
' ui.xml)
  if [ -n "$xy" ]; then
    echo "tap field: EditText at $xy" >> $STEPLOG
    adb shell input tap $xy || true
  else
    echo "tap field: no EditText in the dump, coordinates 470 338" >> $STEPLOG
    adb shell input tap 470 338 || true
  fi
}
hide_keyboard() {
  if adb shell dumpsys input_method | grep -q "mInputShown=true"; then
    echo "back (keyboard)" >> $STEPLOG
    adb shell input keyevent KEYCODE_BACK || true
    sleep 1
  fi
}
# count_in <dump> 'regex': how many controls of the dump have a whole text or accessible name
# that matches (zero size left out, as uitap.py does)
count_in() {
  python3 - "$1" "$2" <<'PYEOF'
import re, sys, xml.etree.ElementTree as ET
try:
    root = ET.parse(sys.argv[1]).getroot()
except (ET.ParseError, OSError):
    print("no-dump")
    sys.exit(0)
rx = re.compile(sys.argv[2])
n = 0
for node in root.iter("node"):
    labels = [node.get("text") or "", node.get("content-desc") or ""]
    if not any(l and rx.fullmatch(l.strip()) for l in labels):
        continue
    m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.get("bounds") or "")
    if m and int(m.group(3)) > int(m.group(1)) and int(m.group(4)) > int(m.group(2)):
        n += 1
print(n)
PYEOF
}
# query 'text' label count-regex: a new search (spaces as %s for adb), its results heading
# (the count of the results, which the build does not change) waited for, then the frame
query() {
  local i n
  tap_field
  sleep 1
  # the tap puts the cursor where it lands: to the end, then the old text out
  adb shell input keyevent KEYCODE_MOVE_END || true
  for i in $(seq 1 40); do adb shell input keyevent KEYCODE_DEL || true; done
  adb shell input text "$1"
  echo "query '$1'" >> $STEPLOG
  sleep 2
  hide_keyboard
  for i in $(seq 1 10); do
    sleep 2
    dump
    n=$(count_in ui.xml "$3")
    [ "$n" -gt 0 ] 2>/dev/null && break
  done
  echo "results '$1': heading '$3' seen $n" >> $STEPLOG
  shot "$2"
}
# label <dump> 'regex' 'what': one line of steps.log, how many controls show it
label() {
  echo "$3: $(count_in "dumps/$1.xml" "$2")" >> $STEPLOG
}
# open_card 'card regex' 'page label regex' label: a tap on the result opens its setting on its
# page - up when the label of the field is there and the results heading is gone (the text of a
# field is not in the dump of Qt 5.15: the value on the page is read from the frame)
open_card() {
  local i n h
  rm -f ui.xml
  tap_ui "$1" || return 1
  for i in $(seq 1 10); do
    sleep 2
    dump
    n=$(count_in ui.xml "$2")
    h=$(count_in ui.xml 'Search results \([0-9]+\)')
    [ "$n" -gt 0 ] 2>/dev/null && [ "$h" = 0 ] && break
  done
  sleep 2
  shot "$3"
  echo "$3 page label: $(count_in dumps/$3.xml "$2")" >> $STEPLOG
  echo "$3 results heading: $(count_in dumps/$3.xml 'Search results \([0-9]+\)')" >> $STEPLOG
  rm -f ui.xml
  tap_ui '^◄$' || return 1
  for i in $(seq 1 10); do
    sleep 2
    dump
    n=$(count_in ui.xml 'Search results \([0-9]+\)')
    [ "$n" -gt 0 ] 2>/dev/null && break
  done
  echo "$3 back to the results: $n" >> $STEPLOG
}

adb logcat -c || true
adb logcat -v threadtime -b main,system,crash > full_logcat.txt 2>/dev/null &
LOGCAT_PID=$!
adb shell settings put system accelerometer_rotation 0 || true
adb shell settings put system user_rotation 0 || true

# open_search <side>: QZ started, the drawer, Settings, the search bar
open_search() {
  echo "== $1: start" >> $STEPLOG
  adb shell am start -n $PKG/$PKG.CustomQtActivity
  sleep 45
  shot $1-home
  tap 84 168 "menu"
  sleep 3
  adb shell input swipe 500 700 500 2300 300 || true
  sleep 2
  tap_drawer '^(Settings|Настройки)$' 400 900
  sleep 8
  shot $1-settings
  tap_ui '🔍|Search settings|Поиск настроек' || return 1
  sleep 2
}

# The value of a card is in the dump as its own label and in the accessible name of the card
# ("<title>: <value>"); either counts
V='(.*: )?'
case_run() {
  install_apk "$2"
  put_conf
  open_search $1 || return 1
  query "pace%stotal" $1-pace 'Search results \(5\)'
  label $1-pace "${V}300" "$1 pace 300"
  label $1-pace "${V}00:25:00" "$1 pace 00:25:00"
  label $1-pace "${V}06:42|${V}00:06:42" "$1 mile 00:06:42"
  # The fix: the page of the setting shows what the card shows
  [ "$1" = a ] && { open_card '5 km pace \(total time\)(: .*)?' '5 km pace \(total time\):' a-pace-page || return 1; }
  query "weight" $1-weight 'Search results \(5\)'
  label $1-weight "${V}9\.979044" "$1 bike 9.979044"
  label $1-weight "Bike Weight \(lbs\)(: .*)?" "$1 bike title lbs"
  label $1-weight "${V}22" "$1 bike 22"
  label $1-weight "${V}85" "$1 player 85"
  label $1-weight "${V}187\.39" "$1 player 187.39"
  [ "$1" = a ] && { open_card 'Bike Weight \(lbs\)(: .*)?' 'Bike Weight \(lbs\)' a-bike-page || return 1; }
  return 0
}
# ru_run: the build with the fix again, in Russian - the name from the template of the page
ru_run() {
  adb shell am force-stop $PKG || true
  sleep 2
  put_conf ru
  open_search r || return 1
  query "weight" r-weight 'Результаты поиска \(5\)'
  label r-weight "Вес велосипеда \(фунт\)(: .*)?" "r bike title фунт"
  label r-weight "Вес \(фунт\)(: .*)?" "r player title фунт"
  label r-weight "${V}22" "r bike 22"
}

FAILED=0
case_run b apk-base/android-debug.apk || FAILED=1
adb shell am force-stop $PKG || true
sleep 2
case_run a apk-debug/android-debug.apk || FAILED=1
ru_run || FAILED=1
adb shell am force-stop $PKG || true

kill $LOGCAT_PID 2>/dev/null || true
sleep 1
# want <line>: steps.log has it, as the whole line
want() {
  if grep -qx "$1" $STEPLOG; then
    echo "ok: $1" >> $STEPLOG
  else
    echo "!! want '$1', got '$(grep -F "${1% *}" $STEPLOG | grep -v '^ok: ' | tail -1)'" >> $STEPLOG
    FAILED=1
  fi
}
# Master: the stored numbers; the fix: the page's units. Any count above 0: the value is in the
# dump as its label, as the accessible name of the card, or both
want_some() {
  if grep -qE "^$1: [1-9][0-9]*$" $STEPLOG; then echo "ok: $1" >> $STEPLOG
  else echo "!! want '$1' on screen, got '$(grep -F "$1:" $STEPLOG | tail -1)'" >> $STEPLOG; FAILED=1; fi
}
for l in "b pace 300" "b bike 9.979044" "b player 85" \
         "a pace 00:25:00" "a mile 00:06:42" "a bike title lbs" "a bike 22" "a player 187.39" \
         "r bike title фунт" "r player title фунт" "r bike 22" \
         "a-pace-page page label" "a-pace-page back to the results" \
         "a-bike-page page label" "a-bike-page back to the results"; do
  want_some "$l"
done
for l in "a-pace-page results heading: 0" "a-bike-page results heading: 0" "b pace 00:25:00: 0" "b bike title lbs: 0" "b player 187.39: 0" \
         "a pace 300: 0" "a bike 9.979044: 0" "a player 85: 0"; do
  want "$l"
done
echo "== ANR / crash in the whole log:" >> $STEPLOG
grep -E "ANR in|FATAL EXCEPTION|Fatal signal" full_logcat.txt >> $STEPLOG || echo "none" >> $STEPLOG
cat $STEPLOG
exit $FAILED
