#!/bin/bash
# Test only (T-181): after a reinstall the app must offer to recover the workouts of the
# previous install even when that install was removed right after its own folder import,
# before any restart. Three installs of the same APK, without all-files access (scoped
# storage, as on a phone):
#   1. the first install records a workout (fake device, Stop) and owns ddb.sqlite;
#   2. reinstall: ddb.sqlite is foreign, the app runs on a spare ddb-N.sqlite and offers the
#      recovery; Yes, the folder picker on Documents/QZ, Use this folder, Allow - the import
#      removes the old ddb.sqlite through the folder grant;
#   3. reinstall again with no restart in between: the offer must show again.
# Run once with a build of master (no offer in 3 - the defect) and once with the fix.
PKG=org.cagnulen.qdomyoszwift
UI_MODERN=${UI_MODERN:-false}
LOG_DEBUG=${LOG_DEBUG:-true}
STEPLOG=steps.log
QZDIR=/sdcard/Documents/QZ
: > $STEPLOG
: > before.txt
mkdir -p dumps qz-logs
adb shell settings put global hide_error_dialogs 1 || true
adb shell cmd uimode night no || true

# put_conf <extra lines>: the settings file of the app before a start
put_conf() {
  printf '[General]\nlog_debug=%s\nui_modern=%s\n%b' "$LOG_DEBUG" "$UI_MODERN" "$1" > qz.conf
  adb push qz.conf /data/local/tmp/qz.conf
  adb shell "run-as $PKG mkdir -p 'files/.config/Roberto Viola'"
  adb shell "run-as $PKG cp /data/local/tmp/qz.conf 'files/.config/Roberto Viola/qDomyos-Zwift.conf'"
}

# The control tree of the screen into ui.xml (none when uiautomator gives up). The old file on
# the device goes first: when the dump fails, pull would take the tree of an earlier screen
# (run 41726390567: the folder picker on top, the dump still showed the offer of QZ)
dump() {
  rm -f ui.xml
  adb shell rm -f /sdcard/ui.xml < /dev/null || true
  timeout 25 adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1 || true
  adb pull /sdcard/ui.xml ui.xml > /dev/null 2>&1 || true
}
# A window of another app over QZ ("not responding", Health Connect) is closed before a step.
# Not for the folder picker: that one is wanted on top (shot_any, tap_any).
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
# shot_any <name>: a frame and the control tree of whatever is on top
shot_any() {
  echo "-- shot $1" >> $STEPLOG
  adb shell screencap -p /sdcard/$1.png || true
  adb pull /sdcard/$1.png > /dev/null 2>&1 || true
  dump
  [ -f ui.xml ] && cp ui.xml dumps/$1.xml
}
# shot <name>: the same with QZ on top
shot() {
  ensure_app
  echo "-- shot $1" >> $STEPLOG
  adb shell screencap -p /sdcard/$1.png || true
  adb pull /sdcard/$1.png > /dev/null 2>&1 || true
  [ -f ui.xml ] || dump
  [ -f ui.xml ] && cp ui.xml dumps/$1.xml
}
# tap_ui 'regex' [x y]: the control of QZ whose whole text or accessible name matches, else
# the fallback coordinates; without them the step is skipped (return 1)
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
# tap_any 'regex' [x y]: the same in whatever window is on top (the folder picker). The picker
# may not let uiautomator dump it (thumbnails keep loading): four tries, then the fallback
# coordinates if given
tap_any() {
  local xy="" i
  for i in 1 2 3 4; do
    dump
    [ -f ui.xml ] && xy=$(python3 .github/uitap.py ui.xml "$1") && break
    echo "tap '$1': try $i, $([ -f ui.xml ] && echo "not in $(python3 .github/uitap.py ui.xml --package)" || echo "no dump")" >> $STEPLOG
    sleep 3
  done
  if [ -n "$xy" ]; then
    echo "tap '$1' in $(python3 .github/uitap.py ui.xml --package): at $xy" >> $STEPLOG
    adb shell input tap $xy || true
    return 0
  fi
  if [ -n "$2" ]; then
    echo "tap '$1': NOT FOUND, coordinates $2 $3" >> $STEPLOG
    adb shell input tap $2 $3 || true
    return 0
  fi
  echo "tap '$1': NOT FOUND, skipped" >> $STEPLOG
  return 1
}
# A drawer entry may be below the fold: one swipe up and a second look
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
tap() { ensure_app; echo "tap $1 $2 ($3)" >> $STEPLOG; adb shell input tap $1 $2 || true; }
back() { echo "back ($1)" >> $STEPLOG; adb shell input keyevent KEYCODE_BACK || true; }
# Nexus 6: 1440x2560 px; the menu button of the home page
MENU="84 168"
open_menu() { tap $MENU "menu"; sleep 3; adb shell input swipe 500 700 500 2300 300 || true; sleep 2; }

# start_app: launch and close the Health Connect screen the first start may show
start_app() {
  adb shell am start -n $PKG/$PKG.CustomQtActivity
  sleep 20
  dump
  if [ -f ui.xml ] && [ "$(python3 .github/uitap.py ui.xml --package)" != "$PKG" ]; then
    back "health connect"
  fi
  sleep 15
  # Home asks to turn on Bluetooth and Location (both off in the emulator): "No" keeps the page
  dump
  if [ -f ui.xml ] && grep -q "Permissions Required" ui.xml; then
    tap_ui '^No$' && sleep 3
  fi
}

# mark <text>: a line in steps.log and in logcat, so the verdict can cut logcat by install
mark() {
  echo "== $1" >> $STEPLOG
  adb shell log -t T181 "== $1" < /dev/null || true
}
# The debug logs of the app in the QZ folder; pull_new_logs <dir> takes those that appeared
# since the last call (a reinstall leaves the old ones there)
logs_now() {
  adb shell "ls $QZDIR/ < /dev/null" 2>/dev/null | tr -d '\r' | grep '^debug-.*\.log$' | sort
}
pull_new_logs() {
  mkdir -p qz-logs/$1
  logs_now > after.txt
  for f in $(comm -13 before.txt after.txt); do
    adb pull "$QZDIR/$f" qz-logs/$1/ > /dev/null 2>&1 || true
  done
  cp after.txt before.txt
}
list_qz() {
  echo "-- ls $QZDIR ($1)" >> $STEPLOG
  adb shell "ls -la $QZDIR $QZDIR/fit < /dev/null" >> $STEPLOG 2>&1 || true
}

# No MANAGE_EXTERNAL_STORAGE: with it the app could open the files of another install, and
# the reinstall would not be a reinstall any more
install_app() {
  adb install apk-debug/android-debug.apk
  if ! adb shell "pm path $PKG < /dev/null" | grep -q "package:"; then
    echo "!! APK NOT INSTALLED (install $1)" >> $STEPLOG
    finish
    exit 1
  fi
  for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION BLUETOOTH_ADVERTISE BLUETOOTH_CONNECT BLUETOOTH_SCAN POST_NOTIFICATIONS; do
    adb shell pm grant $PKG android.permission.$p || true
  done
  for p in EXERCISE DISTANCE TOTAL_CALORIES_BURNED HEART_RATE POWER SPEED CYCLING_PEDALING_CADENCE ELEVATION_GAINED STEPS STEPS_CADENCE HEART_RATE_VARIABILITY; do
    adb shell pm grant $PKG android.permission.health.WRITE_$p || true
  done
  # a fake treadmill keeps the wizard closed
  put_conf "applewatch_fakedevice=true\nskipLocationServicesDialog=true\nconfirm_stop_workout=true\n"
}
# open_history <stage>: the side menu > Workouts History; OFFER=1 when the recovery offer
# shows within about 40 s (it waits for the start-up processing of the history)
open_history() {
  local i
  OFFER=0
  open_menu
  tap_drawer 'Workouts History' 400 1500
  for i in 1 2 3 4 5 6 7 8; do
    sleep 5
    dump
    if [ -f ui.xml ] && grep -q "previous installation" ui.xml; then
      OFFER=1
      break
    fi
  done
  echo "recovery offer ($1): $OFFER" >> $STEPLOG
}

LOGCAT_PID=""
finish() {
  adb shell "ps -A 2>/dev/null || ps" > process_list.txt || true
  adb shell screencap -p /sdcard/screenshot.png || true
  adb pull /sdcard/screenshot.png > /dev/null 2>&1 || true
  [ -n "$LOGCAT_PID" ] && kill $LOGCAT_PID 2>/dev/null
  [ -n "$LOGCAT_PID" ] && wait $LOGCAT_PID 2>/dev/null
  pull_new_logs end
  rm -f before.txt after.txt qz.conf ui.xml
  echo "== steps"; cat $STEPLOG
}

adb logcat -c || true
adb logcat > full_logcat.txt 2>/dev/null &
LOGCAT_PID=$!

# --- 1. the previous install: a workout and ddb.sqlite of its own
mark "install 1"
install_app 1
start_app
shot s1-01-home
sleep 60
tap_ui 'Stop' 1200 2300
sleep 3
shot s1-02-stop-confirm
tap_ui '^(Yes|OK|Stop)$' && echo "stop confirmed" >> $STEPLOG
sleep 15
shot s1-03-after-stop
adb shell am force-stop $PKG
sleep 3
list_qz "after install 1"
pull_new_logs s1
if ! adb shell "ls $QZDIR/fit < /dev/null" 2>/dev/null | grep -qi '\.fit'; then
  echo "!! no FIT file after install 1: the run proves nothing" >> $STEPLOG
  finish
  exit 1
fi

# --- 2. reinstall, the recovery through the folder import
mark "install 2"
adb uninstall $PKG
install_app 2
start_app
shot s2-01-home
open_history "install 2"
OFFER2=$OFFER
PICKED=0
if [ "$OFFER2" = 1 ]; then
  shot s2-02-offer
  tap_ui '^Yes$'
  sleep 6
  shot_any s2-03-picker
  # uitap.py matches the whole label, case-insensitively ("USE THIS FOLDER", "ALLOW")
  # fallback: the button at the bottom of the picker (frame s2-03-picker of run 41726390567)
  if tap_any 'use this folder' 720 2391; then
    sleep 4
    shot_any s2-04-allow
    tap_any 'allow' && PICKED=1
  fi
  sleep 25
  shot s2-05-after-import
fi
list_qz "after the import of install 2"
pull_new_logs s2

# --- 3. reinstall again, no restart of install 2 in between
mark "install 3"
adb uninstall $PKG
install_app 3
start_app
shot s3-01-home
open_history "install 3"
OFFER3=$OFFER
if [ "$OFFER3" = 1 ]; then
  shot s3-02-offer
  tap_ui '^No$' && sleep 3
fi
shot s3-03-history
list_qz "install 3"
pull_new_logs s3
mark "end"

# --- verdict: logcat cut by the marks, with the debug logs of the same install
sleep 2
stage() {
  awk -v a="== install $1" -v b="== $2" 'index($0, a) { on = 1; next } index($0, b) { on = 0 } on' full_logcat.txt
  cat qz-logs/s$1/*.log 2>/dev/null
}
stage 2 "install 3" > s2.txt
stage 3 "end" > s3.txt
FAIL=0
for s in 2 3; do
  grep -m2 "history database:" s$s.txt | sed "s/^/log $s: /" >> $STEPLOG || true
done
grep -m6 "deleteOldHistoryDatabase\|handleFitFolderResult\|FitDatabaseProcessor import:\|history database name taken" s2.txt |
  sed 's/^/log 2: /' >> $STEPLOG || true
if ! grep "history database:" s2.txt | grep -q "ddb-[0-9]*\.sqlite"; then
  echo "!! install 2 is not on a spare database: the run proves nothing" >> $STEPLOG; FAIL=1
fi
if [ "$OFFER2" != 1 ] || [ "$PICKED" != 1 ]; then
  echo "!! install 2: offer $OFFER2, folder picked $PICKED - the run proves nothing" >> $STEPLOG; FAIL=1
fi
if ! grep -q "deleteOldHistoryDatabase.*deleted=true" s2.txt; then
  echo "!! install 2: the old ddb.sqlite was not removed - the run proves nothing" >> $STEPLOG; FAIL=1
fi
if [ "$FAIL" = 0 ]; then
  if [ "$OFFER3" = 1 ]; then
    echo "OK T-181: the recovery is offered after the second reinstall" >> $STEPLOG
  else
    echo "!! T-181: no recovery offer after the second reinstall (the defect)" >> $STEPLOG; FAIL=1
  fi
fi
rm -f s2.txt s3.txt
grep -E "ANR in|FATAL EXCEPTION" full_logcat.txt | sed 's/^/!! /' >> $STEPLOG || true
finish
exit $FAIL
