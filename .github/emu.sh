#!/bin/bash
# Test only (T-400): a write of the window (the camera cutout question, main.qml) no longer puts
# back the keys of its Settings copy that changed after the start, and the question waits while
# the settings page is open. Both on the reference APK (master) and on the fix.
PKG=org.cagnulen.qdomyoszwift
STEPLOG=steps.log
CONF='files/.config/Roberto Viola/qDomyos-Zwift.conf'
: > $STEPLOG
mkdir -p dumps
FAILED=0
BASE_APK=$(ls apk-base/*.apk | head -1)
FIX_APK=$(ls apk-debug/*.apk | head -1)
echo "reference: $BASE_APK, fix: $FIX_APK" >> $STEPLOG

# install_apk <apk>: a fresh install with the permissions granted
install_apk() {
  adb uninstall $PKG > /dev/null 2>&1 || true
  adb shell rm -rf /sdcard/Documents/QZ || true
  adb install "$1"
  adb shell pm path $PKG > /dev/null || { echo "!! $1 not installed - the run proves nothing" >> $STEPLOG; exit 1; }
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

# A fake treadmill, so there is no first-run wizard; English; classic look; the question not asked yet
put_conf() {
  printf '[General]\nlog_debug=true\nui_modern=false\nfakedevice_treadmill=true\napp_language=en\nskipLocationServicesDialog=true\nandroid_landscape_cutout_margin=true\nandroid_landscape_cutout_prompt_shown=false\n' > qz.conf
  adb push qz.conf /data/local/tmp/qz.conf
  adb shell "run-as $PKG mkdir -p 'files/.config/Roberto Viola'"
  adb shell "run-as $PKG cp /data/local/tmp/qz.conf '$CONF'"
}
# conf_val <key>: the stored value (empty when the key is not there)
conf_val() {
  adb shell "run-as $PKG cat '$CONF' < /dev/null" | tr -d '\r' | grep -a "^$1=" | head -1 | cut -d= -f2-
}
# conf_set key=value ...: a write of another copy, the window copy does not know of it - like a
# change on the settings page. QSettings of the app reads the file again at its next sync
conf_set() {
  adb shell "run-as $PKG cat '$CONF' < /dev/null" | tr -d '\r' > conf.tmp
  python3 .github/confset.py conf.tmp "$@" >> $STEPLOG
  adb push conf.tmp /data/local/tmp/qz-set.conf > /dev/null
  adb shell "run-as $PKG cp /data/local/tmp/qz-set.conf '$CONF' < /dev/null"
}
# expect <key> <value> <what>: a check of the fix
expect() {
  local v
  v=$(conf_val "$1")
  if [ "$v" = "$2" ]; then
    echo "check $1=$2 ($3): OK" >> $STEPLOG
  else
    echo "!! check $1 ($3): '$v', expected '$2'" >> $STEPLOG
    FAILED=1
  fi
}
# The old file on the device goes first: after a failed dump adb pull gave the tree of the screen
# before (qz-a2, run 41726390567), and the cases decide by the dump whether the question shows
dump() {
  rm -f ui.xml
  adb shell rm -f /sdcard/ui.xml < /dev/null || true
  timeout 25 adb shell uiautomator dump /sdcard/ui.xml < /dev/null > /dev/null 2>&1 || true
  adb pull /sdcard/ui.xml ui.xml > /dev/null 2>&1 || true
}
# A window of another app over QZ: the launcher "isn't responding" dialog is answered by its
# buttons, anything else gets the back key. QZ's own dialogs (the cutout question) are QZ's package
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
# The menu button is an icon without text (Nexus 6 in portrait: 1440x2560 px), as in test/t244-emu
MENU="84 168"
open_menu() { tap $MENU "menu"; sleep 3; adb shell input swipe 500 700 500 2300 300 || true; sleep 2; }
open_settings() { open_menu; tap_drawer '^Settings$' 400 900; sleep 8; }
portrait() { adb shell settings put system user_rotation 0 || true; sleep 4; }
landscape() { echo "rotate to landscape" >> $STEPLOG; adb shell settings put system user_rotation 1 || true; sleep 4; }
# prompt_on: the cutout question is on the screen now
prompt_on() { dump; [ -f ui.xml ] && grep -q 'Camera Cutout' ui.xml; }
# wait_prompt <seconds>: wait for the question, 0 when it showed
wait_prompt() {
  local i
  for i in $(seq 1 $(($1 / 5))); do
    if prompt_on; then echo "   the question after ~$((i * 5)) s" >> $STEPLOG; return 0; fi
    sleep 5
  done
  return 1
}
mark() { adb shell log -t T400 "mark $1" || true; echo "== $1" >> $STEPLOG; }
start_app() {
  portrait
  adb shell am start -n $PKG/$PKG.CustomQtActivity
  sleep 50
}

adb logcat -c || true
adb logcat -v threadtime -b main,system,crash > full_logcat.txt 2>/dev/null &
LOGCAT_PID=$!
adb shell settings put system accelerometer_rotation 0 || true
portrait

# A camera cutout on the short edge: in landscape (rotation 1) it is on the left, wider than the
# system bars there, so the question of main.qml is due (API 31+)
adb shell cmd overlay list < /dev/null | grep -i cutout >> $STEPLOG || true
CUTOUT=""
for o in tall hole corner double; do
  if adb shell cmd overlay list < /dev/null | grep -q "display.cutout.emulation.$o"; then
    adb shell cmd overlay enable com.android.internal.display.cutout.emulation.$o || true
    CUTOUT=$o
    break
  fi
done
if [ -z "$CUTOUT" ]; then
  echo "!! no display cutout overlay in the image - the run proves nothing" >> $STEPLOG
else
  echo "cutout overlay: $CUTOUT" >> $STEPLOG
fi
sleep 5

# A. The settings page is closed. Keys of the window copy are changed by another writer, then
# the window writes the question flag. master: they go back to the values read at the start
case_closed() {
  local tag="$1" apk="$2" kind="$3"
  mark "$tag: the window writes the flag, the page is closed"
  install_apk "$apk"
  put_conf
  start_app
  shot $tag-1-home
  conf_set shortcut_lap=F7 volume_change_gears=true
  sleep 3
  if [ "$(conf_val shortcut_lap)" != "F7" ]; then
    echo "!! $tag: the outside write did not reach the file - the run proves nothing" >> $STEPLOG
  fi
  landscape
  if ! wait_prompt 40; then
    shot $tag-2-no-question
    echo "!! $tag: no cutout question in landscape - the run proves nothing" >> $STEPLOG
    adb shell am force-stop $PKG || true
    return
  fi
  shot $tag-2-question
  sleep 3
  expect android_landscape_cutout_prompt_shown true "$tag: flag written"
  if [ "$kind" = base ]; then
    if [ "$(conf_val shortcut_lap)" = "F7" ] && [ "$(conf_val volume_change_gears)" = "true" ]; then
      echo "!! $tag: master kept the outside write - the run proves nothing" >> $STEPLOG
    else
      echo "check $tag: master put back shortcut_lap='$(conf_val shortcut_lap)' volume_change_gears='$(conf_val volume_change_gears)' - the defect, as expected: OK" >> $STEPLOG
    fi
    tap_ui '^(No|NO)$' || true
  else
    expect shortcut_lap F7 "$tag: kept after the window write"
    expect volume_change_gears true "$tag: kept after the window write"
    # Yes writes the cutout margin through its own copy
    tap_ui '^(Yes|YES)$' || { echo "!! $tag: no Yes button" >> $STEPLOG; FAILED=1; }
    sleep 4
    shot $tag-3-after-yes
    expect android_landscape_cutout_margin false "$tag: Yes written"
    expect shortcut_lap F7 "$tag: kept after Yes"
  fi
  adb shell am force-stop $PKG || true
  sleep 2
}

# B. The settings page is open in landscape: the fix waits with the question until it is closed
# (the page holds both cutout keys in its copy, read when it opened)
case_open() {
  local tag="$1" apk="$2" kind="$3"
  mark "$tag: landscape with the settings page open"
  install_apk "$apk"
  put_conf
  start_app
  open_settings
  shot $tag-1-settings
  grep -q 'General Options' ui.xml 2>/dev/null || echo "!! $tag: the settings page did not open - the run proves nothing" >> $STEPLOG
  landscape
  sleep 16
  shot $tag-2-settings-landscape
  if [ "$kind" = base ]; then
    if grep -q 'Camera Cutout' ui.xml 2>/dev/null; then
      echo "   $tag: master asks over the settings page (as before)" >> $STEPLOG
    else
      echo "   $tag: master did not ask over the settings page" >> $STEPLOG
    fi
  else
    if grep -q 'Camera Cutout' ui.xml 2>/dev/null; then
      echo "!! $tag: the question shows over the settings page" >> $STEPLOG
      FAILED=1
    else
      echo "check $tag: no question while the settings page is open: OK" >> $STEPLOG
    fi
    expect android_landscape_cutout_prompt_shown false "$tag: not asked yet"
    back "to the home page"
    if wait_prompt 30; then
      shot $tag-3-question-at-home
      sleep 3
      expect android_landscape_cutout_prompt_shown true "$tag: asked after the page closed"
    else
      shot $tag-3-no-question
      echo "!! $tag: no question after the settings page closed" >> $STEPLOG
      FAILED=1
    fi
  fi
  adb shell am force-stop $PKG || true
  sleep 2
}

if [ -n "$CUTOUT" ]; then
  case_closed a-base "$BASE_APK" base
  case_closed a-fix "$FIX_APK" fix
  case_open b-base "$BASE_APK" base
  case_open b-fix "$FIX_APK" fix
fi
portrait

kill $LOGCAT_PID 2>/dev/null || true
wait $LOGCAT_PID 2>/dev/null || true
echo "== QML of main.qml and the marks, in order" >> $STEPLOG
grep -a -E "T400|main\.qml" full_logcat.txt | tail -n 80 >> $STEPLOG || true
echo "== ANR / crash in the whole log:" >> $STEPLOG
grep -a -E "ANR in|FATAL EXCEPTION|Fatal signal" full_logcat.txt >> $STEPLOG || echo "none" >> $STEPLOG
cat $STEPLOG
if grep -q 'proves nothing' $STEPLOG; then exit 1; fi
exit $FAILED
