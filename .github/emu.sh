#!/bin/bash
# Test only (T-290): the accessible state and press action of the classic section headers.
# The reference APK (apk-base: master, `expanded` and `toggle()` that do not exist) and the tested
# APK (apk-debug: the fix) go through the same steps on the classic settings page: the press action
# of a screen reader (ACTION_CLICK from .github/A11yDriver.java, what TalkBack sends on a double
# tap) on "Bike Options" (opens, then closes the section) and on "Tiles Options" (opens its page),
# a frame after each; and the count of "expanded is not defined" in the log of each APK.
PKG=org.cagnulen.qdomyoszwift
UI_MODERN=${UI_MODERN:-false}
LOG_DEBUG=${LOG_DEBUG:-true}
STEPLOG=steps.log
CONF='files/.config/Roberto Viola/qDomyos-Zwift.conf'
: > $STEPLOG
mkdir -p dumps

# install_apk <apk>: a fresh install with the permissions granted
install_apk() {
  adb uninstall $PKG > /dev/null 2>&1 || true
  adb shell rm -rf /sdcard/Documents/QZ || true
  adb install "$1"
  for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION BLUETOOTH_ADVERTISE BLUETOOTH_CONNECT BLUETOOTH_SCAN POST_NOTIFICATIONS; do
    adb shell pm grant $PKG android.permission.$p || true
  done
  adb shell appops set $PKG MANAGE_EXTERNAL_STORAGE allow || true
  # Health Connect: without these the first start opens its request over QZ (T-276)
  for p in EXERCISE DISTANCE TOTAL_CALORIES_BURNED HEART_RATE POWER SPEED CYCLING_PEDALING_CADENCE ELEVATION_GAINED STEPS STEPS_CADENCE HEART_RATE_VARIABILITY; do
    adb shell pm grant $PKG android.permission.health.WRITE_$p || echo "!! health WRITE_$p not granted" >> $STEPLOG
  done
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

# The control tree of the screen into ui.xml (empty when uiautomator gives up)
dump() {
  rm -f ui.xml
  timeout 25 adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1 || true
  adb pull /sdcard/ui.xml ui.xml > /dev/null 2>&1 || true
}
# Another app over QZ (a launcher "not responding" dialog, Health Connect): closed before a step
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
shot() {
  ensure_app
  echo "-- shot $1" >> $STEPLOG
  adb shell screencap -p /sdcard/$1.png || true
  adb pull /sdcard/$1.png || true
  [ -f ui.xml ] || dump
  [ -f ui.xml ] && cp ui.xml dumps/$1.xml
}
# snap name: the frame alone, at once (a toast fades while a dump waits for the screen)
snap() {
  echo "-- snap $1" >> $STEPLOG
  adb shell screencap -p /sdcard/$1.png || true
  adb pull /sdcard/$1.png || true
}
# tap_ui 'regex' [x y]: the control whose text or accessible name matches, else the coordinates
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
# scroll_to 'regex' [max]: swipe the page up until the control shows
scroll_to() {
  local i
  for i in $(seq 1 ${2:-12}); do
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
hide_keyboard() {
  if adb shell dumpsys input_method | grep -q "mInputShown=true"; then
    back "keyboard"
    sleep 1
  fi
}
tap() { ensure_app; echo "tap $1 $2 ($3)" >> $STEPLOG; adb shell input tap $1 $2 || true; }
back() { echo "back ($1)" >> $STEPLOG; adb shell input keyevent KEYCODE_BACK || true; }
MENU="84 168"
open_menu() { tap $MENU "menu"; sleep 3; adb shell input swipe 500 700 500 2300 300 || true; sleep 2; }

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
start_fresh() {
  adb shell am force-stop $PKG || true
  put_conf "applewatch_fakedevice=true\napp_language=en\n$1"
  echo "== start, conf: $1" >> $STEPLOG
  sleep 3
  start_app
}
# row_xy 'anchor' 'target': the control in the row of the anchor
row_xy() {
  [ -f ui.xml ] || dump
  [ -f ui.xml ] && python3 .github/uirow.py ui.xml "$1" "$2"
}
tap_row() {
  local xy
  ensure_app
  xy=$(row_xy "$1" "$2")
  if [ -n "$xy" ]; then
    echo "tap '$2' in the row of '$1' at $xy" >> $STEPLOG
    adb shell input tap $xy || true
  else
    echo "tap '$2' in the row of '$1': NOT FOUND" >> $STEPLOG
    return 1
  fi
}
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
wait_tiles() {
  local i
  for i in $(seq 1 18); do
    dump
    if [ -f ui.xml ] && grep -qE 'content-desc="Speed' ui.xml; then
      echo "tiles shown after $i looks" >> $STEPLOG; return 0
    fi
    sleep 10
  done
  echo "!! tiles NOT shown" >> $STEPLOG
}
# The driver: compiled here against the SDK the emulator action installed (T-222)
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
# drv <name> step...: one connection, all its steps, output in drv/<name>.txt (no dump meanwhile)
drv() {
  local name=$1 args="" a
  shift
  for a in "$@"; do args="$args '$a'"; done
  echo "== drv $name:$args" >> $STEPLOG
  timeout 200 adb shell "CLASSPATH=/data/local/tmp/a11y.jar app_process / A11yDriver$args" > drv/$name.txt 2>&1 || true
  cat drv/$name.txt >> $STEPLOG
  sleep 2
}
# press_steps <prefix>: the settings page, the press action on a section and on a page link
press_steps() {
  local s="$1"
  start_fresh ""
  wait_tiles
  goto_settings || return 1
  shot $s-01-top
  drv $s-bike-open 'find:Bike Options' 'click:Bike Options'
  sleep 3
  snap $s-02-bike-pressed
  drv $s-bike-close 'click:Bike Options'
  sleep 3
  snap $s-03-bike-pressed-again
  scroll_to '^Tiles Options$' 8
  drv $s-tiles 'find:Tiles Options' 'click:Tiles Options'
  sleep 4
  snap $s-04-tiles-pressed
  echo "!! $s: 'expanded is not defined' in the log: $(adb logcat -d | grep -c 'expanded is not defined')" >> $STEPLOG
  echo "!! $s: 'toggle is not defined' in the log: $(adb logcat -d | grep -c 'toggle is not defined')" >> $STEPLOG
}

# 1. Reference: master
install_apk apk-base/android-debug.apk
adb logcat -c || true
press_steps b

# 2. The tested APK
install_apk apk-debug/android-debug.apk
adb logcat -c || true
press_steps a

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
echo "== steps"; cat $STEPLOG
echo "== QML warnings"; grep -iE "qrc:|\.qml:[0-9]+" full_logcat.txt | grep -iE "warning|error|ReferenceError|TypeError" | sort | uniq -c | sort -nr | head -60 || true
