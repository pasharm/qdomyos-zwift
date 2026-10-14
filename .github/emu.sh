#!/bin/bash
# Test only (T-222): what the app does with the accessibility actions TalkBack sends.
# The emulator image has no TalkBack, so .github/A11yDriver.java (built below, run through
# app_process with the UiAutomation connection uiautomator uses) sends them instead: accessibility
# focus on a cell below the screen (the page should scroll to it), scroll forward / backward on
# the value fields (TalkBack's swipe up / down on a seek bar), click on the switch and the buttons
# (TalkBack's double tap). Then the page is opened again to see what was saved.
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

# The driver: compiled here against the SDK the emulator action installed
SDK=${ANDROID_SDK_ROOT:-$ANDROID_HOME}
JAR=$SDK/platforms/android-35/android.jar
BT=$(ls -d $SDK/build-tools/*/ | sort -V | tail -n 1)
mkdir -p drv
if javac -source 8 -target 8 -bootclasspath $JAR -d drv .github/A11yDriver.java >> $STEPLOG 2>&1 \
    && ${BT}d8 --lib $JAR --output a11y.jar drv/*.class >> $STEPLOG 2>&1; then
  adb push a11y.jar /data/local/tmp/a11y.jar > /dev/null
  echo "driver built" >> $STEPLOG
else
  echo "driver NOT built" >> $STEPLOG
fi
# drv <name> step...: one connection, all its steps, output in drv/<name>.txt
drv() {
  local name=$1 args="" a
  shift
  for a in "$@"; do args="$args '$a'"; done
  echo "== drv $name:$args" >> $STEPLOG
  timeout 90 adb shell "CLASSPATH=/data/local/tmp/a11y.jar app_process / A11yDriver$args" > drv/$name.txt 2>&1 || true
  cat drv/$name.txt >> $STEPLOG
  sleep 2
}
conf() {
  echo "== conf $1" >> $STEPLOG
  adb shell "run-as $PKG cat 'files/.config/Roberto Viola/qDomyos-Zwift.conf'" | grep -E "^(gear_|wahoo_)" >> $STEPLOG || true
}

echo "tap $WAHOO (Wahoo Options)" >> $STEPLOG
adb shell input tap ${WAHOO:-700 1000} || true
sleep 6
shot g-01-gears
conf before
drv list list

# TalkBack moves its focus to a cell below the screen: the page should scroll to it
drv focus-low 'find:Gear 12, Rear Cog' 'focus:Gear 12, Rear Cog' 'sleep:1500' 'find:Gear 12, Rear Cog'
shot g-02-focus-gear12

# Swipe up / down on a seek bar = scroll forward / backward
drv values 'focus:Gear 12, Rear Cog' 'fwd:Gear 12, Rear Cog' 'fwd:Gear 12, Rear Cog' 'find:Gear 12, Rear Cog' 'back:Gear 11, Chainring' 'focus:Cog Size:' 'fwd:Cog Size:' 'back:Chainring Size:'
shot g-03-values

# Double tap = click on the focused node
drv switch 'focus:Without Wheel' 'click:Without Wheel'
drv buttons 'focus:Restore Default' 'click:Restore Default' 'focus:Add Gear' 'click:Add Gear' 'sleep:1000' 'find:Gear 13' 'focus:Chainring Size' 'find:Chainring Size'
shot g-04-clicked
conf after

# Saved: leave the page, open it again with TalkBack's double tap on the settings entry
adb shell input keyevent KEYCODE_BACK || true
sleep 4
drv open-by-click 'focus:Wahoo Options' 'click:Wahoo Options' 'sleep:3000' 'find:Virtual Gear Table'
drv reopened 'find:Without Wheel' 'find:Chainring Size:' 'find:Cog Size:' 'find:Gear 11, Chainring' 'find:Gear 12, Rear Cog' 'find:Gear 13'
shot g-05-reopened

# A switch of the settings page (IndicatorOnlySwitch, as on every settings page)
adb shell input keyevent KEYCODE_BACK || true
sleep 4
drv settings-switch 'focus:Restore Gears on Startup' 'click:Restore Gears on Startup' 'sleep:1000' 'find:Restore Gears on Startup'
shot s-03-settings-switch

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
echo "== driver"; for f in drv/*.txt; do echo "-- $f"; cat "$f"; done
echo "== CustomQtActivity and Java errors"; grep -E "CustomQtActivity|AndroidRuntime|FATAL" full_logcat.txt | tail -n 40 || true
echo "== QML warnings"; grep -iE "qrc:|\.qml:[0-9]+" full_logcat.txt | grep -iE "warning|error|ReferenceError|TypeError" | sort | uniq -c | sort -nr | head -40 || true
