#!/bin/bash
# Test only (T-253): the App Language list made from the translations of the build. The build
# holds Swedish at 12% and Finnish at 5%; an empty ca is saved to see the fall back to the system.
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
start_app() {
  adb shell am start -n $PKG/$PKG.CustomQtActivity
  sleep 45
}

adb logcat -c || true
adb logcat -v threadtime -b main,system,crash > full_logcat.txt 2>/dev/null &
LOGCAT_PID=$!
adb shell settings put system accelerometer_rotation 0 || true
adb shell settings put system user_rotation 0 || true

# 1. The device in English, Auto: the list from the translations of the build
echo "== case 1: auto" >> $STEPLOG
install_apk apk-debug/android-debug.apk
put_conf auto
start_app
shot 1-0-home
if open_language; then
  shot 1-1-row
  open_list
  shot 1-2-list-top
  adb shell input swipe 700 2000 700 900 500 || true
  sleep 2
  rm -f ui.xml
  shot 1-3-list-scrolled
  adb shell input swipe 700 2000 700 900 500 || true
  sleep 2
  rm -f ui.xml
  shot 1-4-list-end
  # Swedish holds 12% of the strings: it can be picked and it applies at once
  if tap_ui '^Swedish$'; then
    sleep 3
    rm -f ui.xml
    shot 1-5-picked
    LANG_OK2=$(python3 .github/uitap.py ui.xml '^OK$') && adb shell input tap $LANG_OK2
    sleep 8
    rm -f ui.xml
    shot 1-6-applied
    echo "saved: $(saved_language)" >> $STEPLOG
  fi
else
  echo "!! case 1: language row not reached" >> $STEPLOG
  FAILED=1
fi
adb shell am force-stop $PKG || true
sleep 3

# 2. A saved language with an empty file: the list shows Auto. The search of the settings too
echo "== case 2: saved ca" >> $STEPLOG
put_conf ca
start_app
shot 2-0-home
if open_language; then
  shot 2-1-row-auto
  back "section stays"
  sleep 1
  scroll_top
  rm -f ui.xml
  dump
  if tap_ui 'Search settings' 700 300; then
    sleep 3
    adb shell input text language || true
    sleep 5
    adb shell input keyevent KEYCODE_BACK || true
    sleep 2
    rm -f ui.xml
    shot 2-2-search
  fi
else
  echo "!! case 2: language row not reached" >> $STEPLOG
  FAILED=1
fi
adb shell am force-stop $PKG || true
sleep 3
kill $LOGCAT_PID 2>/dev/null || true
wait $LOGCAT_PID 2>/dev/null || true

# 3. The same saved language on a device in German: it follows the system, as Auto does
echo "== case 3: saved ca, device de-DE" >> $STEPLOG
adb root >> $STEPLOG 2>&1 || true
wait_boot
adb shell setprop persist.sys.locale de-DE
adb reboot
wait_boot
echo "locale $(adb shell getprop persist.sys.locale)" >> $STEPLOG
adb logcat -c || true
adb logcat -v threadtime -b main,system,crash > full_logcat3.txt 2>/dev/null &
LOGCAT_PID=$!
put_conf ca
start_app
shot 3-0-home-german
adb shell am force-stop $PKG || true
sleep 2
kill $LOGCAT_PID 2>/dev/null || true
wait $LOGCAT_PID 2>/dev/null || true

EXPECT='auto,en,it,de,fr,es,pt,pt_BR,ru,zh_CN,ja,ko,tr,pl,uk,nl,cs,sv,no,da'
echo "== T-253 lines" >> $STEPLOG
grep -a -h -E "T-253|Translation (file is empty|loaded)|No translation available" full_logcat.txt full_logcat3.txt | cut -c1-220 | sort -u -k7 | tail -n 60 >> $STEPLOG || true
check() {
  if grep -a -q -- "$2" "$3"; then
    echo "check $1: OK" >> $STEPLOG
  else
    echo "!! check $1: no '$2' in $3" >> $STEPLOG
    FAILED=1
  fi
}
check "list, auto" "T-253 combo saved=auto list=$EXPECT" full_logcat.txt
check "list, saved ca" "T-253 combo saved=ca list=$EXPECT" full_logcat.txt
check "empty file seen" "Translation file is empty" full_logcat.txt
check "German by the system" "Translation loaded successfully for" full_logcat3.txt
echo "== QML warnings of the page" >> $STEPLOG
grep -a -E "settings\.qml|UiComboBox" full_logcat.txt | grep -a -v "T-253" | tail -n 30 >> $STEPLOG || true
echo "== ANR / crash in the whole log:" >> $STEPLOG
grep -a -E "ANR in|FATAL EXCEPTION|Fatal signal" full_logcat.txt full_logcat3.txt >> $STEPLOG || echo "none" >> $STEPLOG
cat full_logcat3.txt >> full_logcat.txt
cat $STEPLOG
exit $FAILED
