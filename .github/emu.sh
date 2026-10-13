#!/bin/bash
# Test only (T-222): does the app tell a screen reader that its tree changed?
# Qt 5.15.0 sends no accessibility events, so TalkBack keeps a stale cache of the tree. The
# branch makes CustomQtActivity send TYPE_WINDOW_CONTENT_CHANGED (CONTENT_CHANGE_TYPE_SUBTREE)
# 400 ms and 1.5 s after a touch is released and after back. "uiautomator events" keeps an
# accessibility connection open (so the app sees accessibility on, as with TalkBack) and prints
# every event; each phase below gets its own file and the summary counts the events of the app.
# Run once with the build of the branch and once with a build without the change.
PKG=org.cagnulen.qdomyoszwift
UI_MODERN=${UI_MODERN:-false}
LOG_DEBUG=${LOG_DEBUG:-true}
STEPLOG=steps.log
: > $STEPLOG
mkdir -p dumps events

adb install apk-debug/android-debug.apk
for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION BLUETOOTH_ADVERTISE BLUETOOTH_CONNECT BLUETOOTH_SCAN POST_NOTIFICATIONS; do
  adb shell pm grant $PKG android.permission.$p || true
done
adb shell appops set $PKG MANAGE_EXTERNAL_STORAGE allow || true
adb shell cmd uimode night no || true
adb shell settings put global hide_error_dialogs 1 || true

put_conf() {
  printf '[General]\nlog_debug=%s\nui_modern=%s\n%b' "$LOG_DEBUG" "$UI_MODERN" "$1" > qz.conf
  adb push qz.conf /data/local/tmp/qz.conf
  adb shell "run-as $PKG mkdir -p 'files/.config/Roberto Viola'"
  adb shell "run-as $PKG cp /data/local/tmp/qz.conf 'files/.config/Roberto Viola/qDomyos-Zwift.conf'"
}

# Only one accessibility connection of the shell at a time: no dump while events record
dump() {
  rm -f ui.xml
  timeout 25 adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1 || true
  adb pull /sdcard/ui.xml ui.xml > /dev/null 2>&1 || true
}
shot() {
  echo "-- shot $1" >> $STEPLOG
  adb shell screencap -p /sdcard/$1.png || true
  adb pull /sdcard/$1.png || true
  dump
  [ -f ui.xml ] && cp ui.xml dumps/$1.xml
}
find_ui() { [ -f ui.xml ] && python3 .github/uitap.py ui.xml "$1"; }
tap_ui() {
  local xy=""
  dump
  xy=$(find_ui "$1")
  if [ -n "$xy" ]; then
    echo "tap '$1': by label at $xy" >> $STEPLOG
    adb shell input tap $xy || true
  else
    echo "tap '$1': NOT FOUND, coordinates $2 $3" >> $STEPLOG
    adb shell input tap $2 $3 || true
  fi
}
scroll_to() {
  local i
  for i in $(seq 1 12); do
    dump
    if find_ui "$1" > /dev/null; then
      echo "scroll to '$1': found after $((i - 1)) swipes" >> $STEPLOG
      return 0
    fi
    adb shell input swipe 700 2000 700 1300 400 || true
    sleep 1
  done
  echo "scroll to '$1': NOT FOUND" >> $STEPLOG
  return 1
}
MENU="84 168"
open_menu() { echo "tap $MENU (menu)" >> $STEPLOG; adb shell input tap $MENU || true; sleep 3; adb shell input swipe 500 700 500 2300 300 || true; sleep 2; }
tap_drawer() {
  dump
  if ! find_ui "$1" > /dev/null; then adb shell input swipe 500 2200 500 900 400 || true; sleep 2; fi
  tap_ui "$@"
}

# events_start <phase> / events_stop: record the accessibility events of a phase
events_start() {
  echo "== events $1 start" >> $STEPLOG
  adb shell uiautomator events > events/$1.txt 2>&1 &
  EVENTS_PID=$!
  # the app turns its accessibility on when the connection appears
  sleep 4
}
events_stop() {
  sleep 4
  adb shell pkill -f uiautomator || true
  kill $EVENTS_PID 2>/dev/null || true
  wait $EVENTS_PID 2>/dev/null || true
  sleep 2
}

adb logcat -c || true
adb logcat > full_logcat.txt 2>/dev/null &
LOGCAT_PID=$!

put_conf "applewatch_fakedevice=true\n"
adb shell am start -n $PKG/$PKG.CustomQtActivity
sleep 20
dump
if [ -f ui.xml ] && [ "$(python3 .github/uitap.py ui.xml --package)" != "$PKG" ]; then
  adb shell input keyevent KEYCODE_BACK || true
fi
sleep 15
shot h-01-home

open_menu
tap_drawer '^Settings$' 400 900
sleep 8
scroll_to '^Bike Options$' && tap_ui '^Bike Options$' 700 1000
sleep 4
scroll_to 'Wahoo Options'
WAHOO=$(find_ui 'Wahoo Options')
echo "Wahoo Options at '$WAHOO'" >> $STEPLOG
shot s-01-settings

# Control: accessibility on, nothing touched - no event of the app expected
events_start 0-idle
events_stop

# The gears page opened by a tap (TalkBack ends a double tap with such a tap)
events_start 1-open-gears
echo "tap $WAHOO (Wahoo Options)" >> $STEPLOG
adb shell input tap ${WAHOO:-700 1000} || true
events_stop
shot g-01-gears

# A scroll of the page (TalkBack passes a two finger drag on as a one finger one)
events_start 2-scroll
adb shell input swipe 700 2000 700 900 400 || true
sleep 1
adb shell input swipe 700 2000 700 900 400 || true
events_stop
shot g-02-gears-table

# Back to the settings page
events_start 3-back
echo "back (gears)" >> $STEPLOG
adb shell input keyevent KEYCODE_BACK || true
events_stop
shot s-02-settings-again

adb shell "ps -A 2>/dev/null || ps" > process_list.txt || true
kill $LOGCAT_PID 2>/dev/null || true
wait $LOGCAT_PID 2>/dev/null || true
adb logcat -d > end_logcat.txt || true
if [ "$(wc -l < full_logcat.txt)" -lt "$(wc -l < end_logcat.txt)" ]; then
  mv end_logcat.txt full_logcat.txt
else
  rm -f end_logcat.txt
fi
grep -E "ANR in|FATAL EXCEPTION" full_logcat.txt | sed 's/^/!! /' >> $STEPLOG || true

echo "== steps"; cat $STEPLOG
echo "== events of the app per phase: content changed (subtree) / all"
for f in events/*.txt; do
  total=$(grep -c "PackageName: $PKG" "$f" || true)
  sub=$(grep "PackageName: $PKG" "$f" | grep "TYPE_WINDOW_CONTENT_CHANGED" | grep -c "CONTENT_CHANGE_TYPE_SUBTREE" || true)
  echo "$(basename "$f" .txt): $sub / $total"
done
echo "== the first lines of each phase"
for f in events/*.txt; do echo "-- $f"; head -c 3000 "$f"; echo; done
echo "== CustomQtActivity and Java errors"; grep -E "CustomQtActivity|AndroidRuntime|FATAL" full_logcat.txt | tail -n 40 || true
echo "== QML warnings"; grep -iE "qrc:|\.qml:[0-9]+" full_logcat.txt | grep -iE "warning|error|ReferenceError|TypeError" | sort | uniq -c | sort -nr | head -40 || true
