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
# put_conf ['key=value\n...']: the keys of a case go after the common ones
put_conf() {
  printf '[General]\nlog_debug=true\nui_modern=false\nfakedevice_treadmill=true\napp_language=en\nskipLocationServicesDialog=true\nandroid_landscape_cutout_margin=true\nandroid_landscape_cutout_prompt_shown=false\n%b' "$1" > qz.conf
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
# orientation: portrait or landscape, by the size of a screen capture (run 41741972187: after the
# first turn "settings put system user_rotation 0" left the screen in landscape, unnoticed)
orientation() {
  adb exec-out screencap -p > orient.png 2>/dev/null || true
  python3 -c '
import struct, sys
d = open(sys.argv[1], "rb").read(24)
w, h = struct.unpack(">II", d[16:24]) if len(d) == 24 else (0, 0)
print("portrait" if h > w else "landscape" if w > h else "unknown")
' orient.png
}
# rotate <0|1> <portrait|landscape>: lock the rotation and check it took
rotate() {
  local i now
  adb shell cmd window user-rotation lock $1 || true
  adb shell settings put system user_rotation $1 || true
  for i in 1 2 3 4 5; do
    sleep 2
    now=$(orientation)
    [ "$now" = "$2" ] && { echo "rotation $1: $now" >> $STEPLOG; return 0; }
  done
  echo "!! rotation $1: still $now, expected $2 - the run proves nothing" >> $STEPLOG
  return 1
}
portrait() { rotate 0 portrait; sleep 2; }
landscape() { echo "rotate to landscape" >> $STEPLOG; rotate 1 landscape; sleep 2; }
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
# The launcher keeps portrait by itself, so a capture of it proves nothing (run 41743616538: the
# check said portrait, QZ came up in landscape). The orientation is checked with QZ on top, and
# each case turns back to portrait before QZ is stopped
start_app() {
  local now
  adb shell am start -n $PKG/$PKG.CustomQtActivity
  sleep 50
  ensure_app
  now=$(orientation)
  if [ "$now" != portrait ]; then
    echo "!! QZ started in $now - the run proves nothing" >> $STEPLOG
  else
    echo "QZ started in portrait" >> $STEPLOG
  fi
}
stop_app() {
  portrait
  adb shell am force-stop $PKG || true
  sleep 2
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
  if grep -q 'Camera Cutout' ui.xml 2>/dev/null || [ "$(conf_val android_landscape_cutout_prompt_shown)" = "true" ]; then
    echo "!! $tag: the question came before the outside write - the run proves nothing" >> $STEPLOG
  fi
  conf_set shortcut_lap=F7 volume_change_gears=true
  sleep 3
  if [ "$(conf_val shortcut_lap)" != "F7" ]; then
    echo "!! $tag: the outside write did not reach the file - the run proves nothing" >> $STEPLOG
  fi
  landscape
  if ! wait_prompt 40; then
    shot $tag-2-no-question
    echo "!! $tag: no cutout question in landscape - the run proves nothing" >> $STEPLOG
    stop_app
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
  stop_app
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
      # Why the fix waits: Yes, then a switch of the page - its copy writes back what it read
      tap_ui '^(Yes|YES)$' || true
      sleep 3
      echo "   $tag: after Yes margin='$(conf_val android_landscape_cutout_margin)' flag='$(conf_val android_landscape_cutout_prompt_shown)'" >> $STEPLOG
      tap_ui '^General Options$' || true
      sleep 3
      if tap_switch '^Pause when App Starts$'; then
        sleep 3
        shot $tag-3-after-page-switch
        echo "   $tag: after a switch of the page margin='$(conf_val android_landscape_cutout_margin)' flag='$(conf_val android_landscape_cutout_prompt_shown)' pause_on_start='$(conf_val pause_on_start)'" >> $STEPLOG
      else
        shot $tag-3-no-page-switch
      fi
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
  stop_app
}

# C. The Peloton authentication question (a stored password other than "password" shows it 1 s
# after the start): "Yes" writes the login back to its defaults. master: through the big copy
case_peloton() {
  local tag="$1" apk="$2" kind="$3"
  mark "$tag: Yes in the Peloton question"
  install_apk "$apk"
  put_conf 'peloton_username=me@example.com\npeloton_password=secret\n'
  start_app
  shot $tag-1-question
  if ! grep -q 'Peloton Authentication Change' ui.xml 2>/dev/null; then
    echo "!! $tag: no Peloton question - the run proves nothing" >> $STEPLOG
    stop_app
    return
  fi
  conf_set shortcut_lap=F7
  sleep 3
  tap_ui '^(Yes|YES)$' || { echo "!! $tag: no Yes button - the run proves nothing" >> $STEPLOG; stop_app; return; }
  sleep 6
  shot $tag-2-after-yes
  expect peloton_username username "$tag: login reset by Yes"
  expect peloton_password password "$tag: password reset by Yes"
  if [ "$kind" = base ]; then
    if [ "$(conf_val shortcut_lap)" = "F7" ]; then
      echo "!! $tag: master kept the outside write - the run proves nothing" >> $STEPLOG
    else
      echo "check $tag: master put back shortcut_lap='$(conf_val shortcut_lap)' - the defect, as expected: OK" >> $STEPLOG
    fi
  else
    expect shortcut_lap F7 "$tag: kept after Yes"
  fi
  stop_app
}

# node_height 'regex': the height of the first node with that text in a fresh dump
node_height() {
  dump
  [ -f ui.xml ] && python3 -c '
import re, sys, xml.etree.ElementTree as ET
for n in ET.parse(sys.argv[1]).getroot().iter("node"):
    if re.fullmatch(sys.argv[2], n.get("text") or n.get("content-desc") or "", re.I):
        m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", n.get("bounds") or "")
        if m:
            print(int(m.group(4)) - int(m.group(2)))
            break
' ui.xml "$1"
}
# scroll_to 'regex' [swipes]: swipe the page up (portrait) until the control shows
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

# tap_switch 'regex': an IndicatorOnlySwitch reacts only on its indicator at the right end of the
# row, not on the label (run 41748616998: a tap on the middle of the row changed nothing). Swipes
# the page up (in the current orientation) until the row is on the screen with a size
tap_switch() {
  local i xy
  for i in 1 2 3 4 5 6 7 8; do
    dump
    xy=$([ -f ui.xml ] && python3 -c '
import re, sys, xml.etree.ElementTree as ET
for n in ET.parse(sys.argv[1]).getroot().iter("node"):
    if re.fullmatch(sys.argv[2], n.get("text") or n.get("content-desc") or "", re.I):
        m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", n.get("bounds") or "")
        if m:
            x1, y1, x2, y2 = map(int, m.groups())
            if x2 - x1 > 100 and y2 - y1 > 40:
                print(x2 - 60, (y1 + y2) // 2)
                break
' ui.xml "$1")
    if [ -n "$xy" ]; then
      echo "tap switch '$1' at $xy (after $((i - 1)) swipes)" >> $STEPLOG
      adb shell input tap $xy || true
      return 0
    fi
    if [ "$(orientation)" = landscape ]; then
      adb shell input swipe 1280 1150 1280 650 400 || true
    else
      adb shell input swipe 700 2000 700 1300 400 || true
    fi
    sleep 1
  done
  echo "!! switch '$1' NOT FOUND" >> $STEPLOG
  return 1
}

# D. The text size through setTextScaleOption: "Use System Text Size" off with a stored size of
# 130 % - the page text grows at once (the window font) and the key is written. Here the settings
# page writes the same keys too, so it shows the path works, not which copy wins
case_text_size() {
  local tag="$1" apk="$2" h1 h2
  mark "$tag: Use System Text Size off"
  install_apk "$apk"
  put_conf 'ui_text_scale=130\nui_text_scale_system=true\n'
  start_app
  open_settings
  tap_ui '^General UI Options$' || true
  sleep 3
  if ! scroll_to '^Use System Text Size$'; then
    shot $tag-1-no-switch
    echo "!! $tag: no Use System Text Size - the run proves nothing" >> $STEPLOG
    stop_app
    return
  fi
  h1=$(node_height '^Use System Text Size$')
  shot $tag-1-before
  tap_switch '^Use System Text Size$' || true
  sleep 4
  h2=$(node_height '^Use System Text Size$')
  shot $tag-2-after
  echo "   $tag: height of the switch row $h1 -> $h2 px" >> $STEPLOG
  if [ -n "$h1" ] && [ -n "$h2" ] && [ "$h2" -gt "$h1" ]; then
    echo "check $tag: the text grew at once: OK" >> $STEPLOG
  else
    echo "!! $tag: the text did not grow ($h1 -> $h2)" >> $STEPLOG
    FAILED=1
  fi
  expect ui_text_scale_system false "$tag: written"
  stop_app
}

if [ -n "$CUTOUT" ]; then
  case_closed a-base "$BASE_APK" base
  case_closed a-fix "$FIX_APK" fix
  case_open b-base "$BASE_APK" base
  case_open b-fix "$FIX_APK" fix
fi
case_peloton c-base "$BASE_APK" base
case_peloton c-fix "$FIX_APK" fix
case_text_size d-base "$BASE_APK"
case_text_size d-fix "$FIX_APK"
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
