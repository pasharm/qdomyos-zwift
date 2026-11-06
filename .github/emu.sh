#!/bin/bash
# Test only (T-253): the App Language list of the commit, with no test translations in the build.
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

# A fake treadmill, so there is no first-run wizard; the saved language; the look of the run
put_conf() {
  printf '[General]\nlog_debug=%s\nui_modern=%s\nfakedevice_treadmill=true\napp_language=%s\n' "$LOG_DEBUG" "$UI_MODERN" "$1" > qz.conf
  adb push qz.conf /data/local/tmp/qz.conf
  adb shell "run-as $PKG mkdir -p 'files/.config/Roberto Viola'"
  adb shell "run-as $PKG cp /data/local/tmp/qz.conf '$CONF'"
}
dump() {
  rm -f ui.xml
  timeout 25 adb shell uiautomator dump /sdcard/ui.xml < /dev/null > /dev/null 2>&1 || true
  adb pull /sdcard/ui.xml ui.xml > /dev/null 2>&1 || true
}
# A window of another app over QZ: the launcher of the image hangs on the slow CI machine and its
# "isn't responding" dialog survives the back key (run 41376681046 lost both cases to it), so that
# dialog is answered by its buttons; anything else gets the back key. Logged in steps.log.
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

wait_boot() {
  local i
  adb wait-for-device
  for i in $(seq 1 90); do
    [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = 1 ] && break
    sleep 2
  done
  sleep 10
}

# To the top of General Options; LANG_OK is the place of the OK of the language row
open_language() {
  tap 84 168 "menu"
  sleep 3
  adb shell input swipe 500 700 500 2300 300 || true
  sleep 2
  tap_drawer '^Settings$' 400 900
  sleep 8
  scroll_to 'General Options' 20 || return 1
  tap_ui 'General Options'
  sleep 5
  rm -f ui.xml
  dump
  LANG_OK=$(python3 .github/uitap.py ui.xml '^OK$')
  echo "language OK at '$LANG_OK'" >> $STEPLOG
  [ -n "$LANG_OK" ]
}
# The list of the language row: the field is left of its OK
open_list() {
  local x=${LANG_OK% *} y=${LANG_OK#* }
  tap $((x - 260)) $y "language field"
  sleep 3
  rm -f ui.xml
}
saved_language() {
  adb shell "run-as $PKG cat '$CONF'" | tr -d '\r' | grep -a '^app_language' | head -n 1
}
# check_saved <name> <line of the conf>
check_saved() {
  local line
  line=$(saved_language)
  if [ "$line" = "$2" ]; then
    echo "check $1: OK ($line)" >> $STEPLOG
  else
    echo "!! check $1: '$line', expected $2" >> $STEPLOG
    FAILED=1
  fi
}
start_app() {
  adb shell am start -n $PKG/$PKG.CustomQtActivity
  sleep 45
}

adb logcat -c || true
adb logcat -v threadtime -b main,system,crash > full_logcat.txt 2>/dev/null &
LOGCAT_PID=$!
adb shell settings put system accelerometer_rotation 0 || true
adb shell settings put system user_rotation 0 || true

# The list of the commit as it is, the frames after the change
echo "== clean: the list" >> $STEPLOG
install_apk apk-debug/android-debug.apk
put_conf auto
start_app
if open_language; then
  open_list
  shot c-1-list-top
  adb shell input swipe 950 2200 950 500 500 || true
  sleep 3
  rm -f ui.xml
  shot c-2-list-end
  if tap_ui '^Hungarian$'; then
    sleep 3
    rm -f ui.xml
    shot c-3-picked
    OK_XY=$(python3 .github/uitap.py ui.xml '^OK$') && adb shell input tap $OK_XY
    sleep 8
    rm -f ui.xml
    shot c-4-hungarian
  else
    FAILED=1
  fi
else
  echo "!! clean: language row not reached" >> $STEPLOG
  FAILED=1
fi
adb shell am force-stop $PKG || true
sleep 3
check_saved "picked Hungarian" app_language=hu

# The search card of a saved language with no translation: Auto, as its page, not Catalan
echo "== search: saved ca" >> $STEPLOG
put_conf ca
start_app
if open_language; then
  tap 1018 168 "search icon"
  sleep 3
  rm -f ui.xml
  dump
  tap_ui 'Search settings' 500 330
  sleep 2
  adb shell input text language || true
  sleep 5
  rm -f ui.xml
  shot s-1-search-ca
  if ! python3 .github/uitap.py ui.xml 'App Language' > /dev/null; then
    echo "!! search: no App Language result" >> $STEPLOG
    FAILED=1
  elif grep -q 'Catalan' ui.xml; then
    echo "!! search: the card shows Catalan" >> $STEPLOG
    FAILED=1
  elif python3 .github/uitap.py ui.xml 'Auto \(System\)' > /dev/null; then
    echo "check search card: OK (Auto, no Catalan)" >> $STEPLOG
  else
    echo "!! search: no Auto on the card" >> $STEPLOG
    FAILED=1
  fi
else
  echo "!! search: language row not reached" >> $STEPLOG
  FAILED=1
fi
adb shell am force-stop $PKG || true
sleep 3
check_saved "search left ca as it is" app_language=ca
kill $LOGCAT_PID 2>/dev/null || true
wait $LOGCAT_PID 2>/dev/null || true

EXPECT='Translated app languages: ("cs", "da", "de", "es", "fr", "hu", "it", "ja", "ko", "nl", "no", "pl", "pt", "ru", "sv", "tr", "uk", "zh_CN")'
echo "== language lines" >> $STEPLOG
grep -a -h -E "Translated app languages|Translation (file is empty|loaded)|No translation available" full_logcat.txt | cut -c1-200 | tail -n 10 >> $STEPLOG || true
if grep -a -q -F -- "$EXPECT" full_logcat.txt; then
  echo "check list: OK" >> $STEPLOG
else
  echo "!! check list: no '$EXPECT'" >> $STEPLOG
  FAILED=1
fi
echo "== ANR / crash in the whole log:" >> $STEPLOG
grep -a -E "ANR in|FATAL EXCEPTION|Fatal signal" full_logcat.txt >> $STEPLOG || echo "none" >> $STEPLOG
cat $STEPLOG
exit $FAILED
