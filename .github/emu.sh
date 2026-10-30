#!/bin/bash
# Test only (T-346): the preview of a workout while the history database is in the private
# folder of the app. Every ddb*.sqlite name in Documents/QZ is taken by a folder, so no name
# opens (as after many reinstalls) and the database goes to /data/user/0/<pkg>/files.
# A synthetic workout is in Documents/QZ/fit; the side menu > Workouts History > the workout
# opens its preview, and the log says whether the FIT file was read.
# Run once with the build of master (preview empty) and once with the fix.
PKG=org.cagnulen.qdomyoszwift
UI_MODERN=${UI_MODERN:-false}
LOG_DEBUG=${LOG_DEBUG:-true}
STEPLOG=steps.log
: > $STEPLOG
mkdir -p dumps

adb install apk-debug/android-debug.apk
for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION BLUETOOTH_ADVERTISE BLUETOOTH_CONNECT BLUETOOTH_SCAN POST_NOTIFICATIONS; do
  adb shell pm grant $PKG android.permission.$p || true
done
for p in EXERCISE DISTANCE TOTAL_CALORIES_BURNED HEART_RATE POWER SPEED CYCLING_PEDALING_CADENCE ELEVATION_GAINED STEPS STEPS_CADENCE HEART_RATE_VARIABILITY; do
  adb shell pm grant $PKG android.permission.health.WRITE_$p || true
done
adb shell appops set $PKG MANAGE_EXTERNAL_STORAGE allow || true
adb shell cmd uimode night no || true

# T-346: every database name taken, one workout in the fit folder
QZDIR=/sdcard/Documents/QZ
adb shell mkdir -p $QZDIR/ddb.sqlite
for i in $(seq 1 19); do adb shell mkdir -p $QZDIR/ddb-$i.sqlite; done
# The workout is recorded by the app itself (fake device, Stop): a FIT file put in by adb is
# hidden from the app on API 35 - in Documents it belongs to the shell (scoped storage),
# run-as cannot write there, and a folder of the shell in Android/data is not listed either
adb shell ls -la $QZDIR >> $STEPLOG 2>&1 || true
adb shell settings put global hide_error_dialogs 1 || true

# put_conf <extra lines>: the settings file of the app before a start
put_conf() {
  printf '[General]\nlog_debug=%s\nui_modern=%s\n%b' "$LOG_DEBUG" "$UI_MODERN" "$1" > qz.conf
  adb push qz.conf /data/local/tmp/qz.conf
  adb shell "run-as $PKG mkdir -p 'files/.config/Roberto Viola'"
  adb shell "run-as $PKG cp /data/local/tmp/qz.conf 'files/.config/Roberto Viola/qDomyos-Zwift.conf'"
}
put_conf ""

# The control tree of the screen into ui.xml (empty when uiautomator gives up, for instance
# while something animates without pause)
dump() {
  rm -f ui.xml
  timeout 25 adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1 || true
  adb pull /sdcard/ui.xml ui.xml > /dev/null 2>&1 || true
}
# The emulator itself may put a window over the app: "Pixel Launcher isn't responding", or
# the Health Connect screen left over when the back key went to such a dialog. They made a
# whole run useless once. Clear them before every step: Wait on a "not responding" dialog,
# the back key on anything else that is not the app. Logged in steps.log.
ensure_app() {
  local i pkg xy
  for i in 1 2 3; do
    dump
    [ -f ui.xml ] || return 0
    pkg=$(python3 .github/uitap.py ui.xml --package)
    [ -z "$pkg" ] || [ "$pkg" = "$PKG" ] && return 0
    # Somebody else hanging (the launcher) is closed, the app itself is waited for
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
  # The last dump showed the window that was then closed: not the screen any more
  rm -f ui.xml
}
# ensure_app leaves ui.xml of the app on top: the callers take it instead of a second dump
# of the same screen (a dump costs about 2 s, half of all dumps of a run were such repeats)
shot() {
  if [ "$1" = "01-healthconnect" ]; then rm -f ui.xml; else ensure_app; fi
  echo "-- shot $1" >> $STEPLOG
  adb shell screencap -p /sdcard/$1.png || true
  adb pull /sdcard/$1.png || true
  [ -f ui.xml ] || dump
  [ -f ui.xml ] && cp ui.xml dumps/$1.xml
}
# tap_ui 'regex' [x y]: the control whose whole text or accessible name matches, else the
# fallback coordinates; without them the step is skipped (return 1)
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
# The same for a drawer entry that may be below the fold: one swipe up and a second look
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
# scroll_to 'regex': swipe the page up until the control shows (at most 12 swipes)
scroll_to() {
  local i
  for i in $(seq 1 12); do
    dump
    if [ -f ui.xml ] && python3 .github/uitap.py ui.xml "$1" > /dev/null; then
      echo "scroll to '$1': found after $((i - 1)) swipes" >> $STEPLOG
      return 0
    fi
    adb shell input swipe 700 2000 700 1300 400 || true
    sleep 1
  done
  echo "scroll to '$1': NOT FOUND" >> $STEPLOG
  return 1
}
# The top of a page: a few quick swipes down
scroll_top() {
  local i
  for i in 1 2 3 4 5; do adb shell input swipe 700 800 700 2200 150 || true; done
  sleep 1
}
# The back key closes the keyboard, but only while it is shown: otherwise it leaves the page
hide_keyboard() {
  if adb shell dumpsys input_method | grep -q "mInputShown=true"; then
    back "keyboard"
    sleep 1
  fi
}
tap() { ensure_app; echo "tap $1 $2 ($3)" >> $STEPLOG; adb shell input tap $1 $2 || true; }
back() { echo "back ($1)" >> $STEPLOG; adb shell input keyevent KEYCODE_BACK || true; }
# Toolbar buttons are icons without text: the same place in both looks (Nexus 6: 1440x2560
# px, 3.5 px per dp)
MENU="84 168"          # menu on the home page, back arrow elsewhere
LOCK="1187 168"        # tile lock on the home page
open_menu() { tap $MENU "menu"; sleep 3; adb shell input swipe 500 700 500 2300 300 || true; sleep 2; }


adb logcat -c || true
adb logcat > full_logcat.txt 2>/dev/null &
LOGCAT_PID=$!

# start_app: launch and close the Health Connect screen the first start may show
start_app() {
  adb shell am start -n $PKG/$PKG.CustomQtActivity
  sleep 20
  dump
  if [ -f ui.xml ] && [ "$(python3 .github/uitap.py ui.xml --package)" != "$PKG" ]; then
    back "health connect"
  fi
  sleep 15
  # Home asks to turn on Bluetooth and Location (both off in the emulator): "No" keeps the
  # page under it; the answer holds until the next start
  dump
  if [ -f ui.xml ] && grep -q "Permissions Required\|Потрібні дозволи" ui.xml; then
    tap_ui '^(No|Ні)$' && sleep 3
  fi
}
# open_settings: from anywhere back to home, then the menu and Settings
open_settings() {
  open_menu
  tap_drawer '^Settings$' 400 900
  sleep 8
}

# T-346: a fake treadmill, so the wizard stays closed
put_conf "applewatch_fakedevice=true\nskipLocationServicesDialog=true\nconfirm_stop_workout=true\n"
start_app
shot h-01-home
# about a minute of the session of the fake device, then Stop saves the FIT file
sleep 60
tap_ui 'Stop' 1200 2300
sleep 3
shot h-02-stop-confirm
tap_ui '^(Yes|OK|Stop)$' && echo "stop confirmed" >> $STEPLOG
sleep 15
shot h-03-after-stop
# the end page of the workout, if any, back to home
dump
if [ -f ui.xml ] && ! python3 .github/uitap.py ui.xml 'Stop' > /dev/null; then
  back "end page"; sleep 5
fi
shot h-04-home

open_menu
tap_drawer 'Workouts History' 400 1500
sleep 15
# the database is not ddb.sqlite: the app offers to look for the workouts of a previous install
dump
if [ -f ui.xml ] && grep -q "previous installation" ui.xml; then
  shot w-00-offer
  tap_ui '^No$' && sleep 3
fi
shot w-01-history
# the workout row: "<title>, <date>, <duration>"
if tap_ui '.+, .*20[0-9][0-9].*, .+' 700 750; then
  sleep 12
  shot w-02-preview
  back "preview"; sleep 4
fi

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
mkdir -p qz-logs
for f in $(adb shell "ls $QZDIR/*.log < /dev/null" 2>/dev/null | tr -d '\r'); do
  adb pull "$f" qz-logs/ > /dev/null 2>&1 || true
done
grep -E "ANR in" full_logcat.txt | sed 's/^/!! /' >> $STEPLOG || true

# T-346 verdict: the run proves something only with the database in the private folder
cat full_logcat.txt qz-logs/*.log 2>/dev/null > all.txt
grep -m3 "history database" all.txt | sed 's/^/log: /' >> $STEPLOG || true
grep -m3 "fitfile_preview_clicked called\|Opening FIT file\|FIT file read:\|FIT file does not exist" all.txt | sed 's/^/log: /' >> $STEPLOG || true
FAIL=0
if ! grep -q "every name in the QZ folder is taken" all.txt; then
  echo "!! database not in the private folder: the run proves nothing" >> $STEPLOG; FAIL=1
fi
adb shell ls -la $QZDIR/fit >> $STEPLOG 2>&1 || true
grep -m2 "Processing FIT file" all.txt | sed 's/^/log: /' >> $STEPLOG || true
if ! grep -q "Processing FIT file" all.txt; then
  echo "!! the FIT file never reached the history" >> $STEPLOG; FAIL=1
fi
if grep -q "FIT file does not exist" all.txt; then
  echo "!! preview: FIT file does not exist" >> $STEPLOG; FAIL=1
elif grep -q "FIT file read: [1-9]" all.txt; then
  echo "OK preview: FIT file read" >> $STEPLOG
else
  echo "!! preview never opened" >> $STEPLOG; FAIL=1
fi
rm -f all.txt
echo "== steps"; cat $STEPLOG
echo "== QML warnings"; grep -iE "qrc:|\.qml:[0-9]+" full_logcat.txt | grep -iE "warning|error|ReferenceError|TypeError" | sort | uniq -c | sort -nr | head -40 || true
exit $FAIL
