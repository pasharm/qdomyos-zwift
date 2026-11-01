#!/bin/bash
# Test only (T-312): the switch ui_state_buttons in Experimental Features. Off - Start/Pause, Stop
# and Lap all the time, the paused button says Start; on - the buttons follow the workout state.
# Both looks, and the switch tapped in the settings: it applies at once and stays after a restart.
# The buttons are tapped by coordinates (Nexus 6, 1440x2560 px).
PKG=org.cagnulen.qdomyoszwift
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
  # Health Connect write permissions granted: otherwise QZ opens its request (and the Health
  # Connect onboarding) over itself at the first start (HealthConnectHelper.writePermissions)
  for p in EXERCISE DISTANCE TOTAL_CALORIES_BURNED HEART_RATE POWER SPEED CYCLING_PEDALING_CADENCE ELEVATION_GAINED STEPS STEPS_CADENCE HEART_RATE_VARIABILITY; do
    adb shell pm grant $PKG android.permission.health.WRITE_$p || echo "!! health WRITE_$p not granted" >> $STEPLOG
  done
  echo "== installed $1" >> $STEPLOG
}
adb shell cmd uimode night no || true
adb shell settings put global hide_error_dialogs 1 || true

# put_conf <lang> <modern> [extra lines]: the settings file of the app before a start - a fake
# treadmill, so the home page has tiles and no first-run wizard
put_conf() {
  printf '[General]\nlog_debug=%s\nui_modern=%s\nfakedevice_treadmill=true\napp_language=%s\n%b' "$LOG_DEBUG" "$2" "$1" "$3" > qz.conf
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
# A window of another app over QZ (Health Connect, a launcher not responding) closed with the back key
ensure_app() {
  local i pkg
  for i in 1 2 3; do
    dump
    [ -f ui.xml ] || return 0
    pkg=$(python3 .github/uitap.py ui.xml --package)
    [ -z "$pkg" ] || [ "$pkg" = "$PKG" ] && return 0
    echo "!! $pkg over the app: back key" >> $STEPLOG
    adb shell input keyevent KEYCODE_BACK || true
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
# quick <label>: a frame right away, without the control tree (the fade-in is 0.5 s)
quick() {
  echo "-- quick $1" >> $STEPLOG
  adb shell screencap -p /sdcard/$1.png || true
  adb pull /sdcard/$1.png || true
}
mark() {
  echo "$(date +%H:%M:%S) $1" >> $STEPLOG
  adb shell log -t T312 "'$1'" || true
}
# The fake treadmill comes after the first search ends; the tile names are translated, so a
# fixed wait instead of looking for them (T-302: the tiles were there at the first look, 25 s)
wait_tiles() { sleep 20; }
tap_xy() { ensure_app; echo "$(date +%H:%M:%S.%N | cut -c1-12) tap $1 at $2" >> $STEPLOG; adb shell input tap $2 || true; }

tap() { ensure_app; echo "tap $1 $2 ($3)" >> $STEPLOG; adb shell input tap $1 $2 || true; }
back() { echo "back ($1)" >> $STEPLOG; adb shell input keyevent KEYCODE_BACK || true; }
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
# The stored value of the switch, into steps.log
conf_value() {
  echo "conf ($1): $(adb shell "run-as $PKG cat '$CONF'" | grep ui_state_buttons | tr -d '\r')" >> $STEPLOG
}
# Opens the setting from the settings search and taps its switch, then back to the home page
toggle_in_settings() {
  tap $MENU "menu"
  sleep 3
  adb shell input swipe 500 700 500 2300 300 || true
  sleep 2
  dump
  tap_ui '^Settings$' 400 900
  sleep 8
  dump
  tap_ui '🔍|Search settings'
  sleep 2
  tap 470 338 "search field"
  sleep 1
  adb shell input text "Buttons%sfollow"
  sleep 3
  if adb shell dumpsys input_method | grep -q "mInputShown=true"; then
    back "keyboard"
    sleep 1
  fi
  shot "$1-results"
  dump
  tap_ui '^Buttons follow the workout state.*'
  sleep 5
  shot "$1-section"
  dump
  tap_ui '^Buttons follow the workout state$'
  sleep 2
  shot "$1-toggled"
  for i in 1 2 3; do
    adb shell input keyevent KEYCODE_BACK || true
    sleep 3
  done
  shot "$1-back"
}

# Modern buttons by the state (switch on): the row is 12 dp under the toolbar, centre y 421 px.
# One wide Start/Pause 286..1154 px; paused: Resume 286..804, Stop 832..1350
WIDEXY="720 421"
RESUMEXY="545 421"
STOPXY="1091 421"
# Switch off, the same row: Start/Pause 286..706, Stop 734..1154, Lap 1182..1350
OFFSTARTXY="497 421"
OFFSTOPXY="940 421"
# The classic look: Start 286..706, Stop 734..1154, centre y 468
OLDSTARTXY="497 468"
OLDSTOPXY="940 468"
MENU="84 168"

adb logcat -c || true
adb logcat -v threadtime -b main,system,crash > full_logcat.txt 2>/dev/null &
LOGCAT_PID=$!

adb shell settings put system accelerometer_rotation 0 || true
adb shell settings put system user_rotation 0 || true

# launch <label> <lang> <modern> [extra conf lines]: the app (already installed) started fresh
launch() {
  adb shell am force-stop $PKG || true
  sleep 2
  put_conf "$2" "$3" "$4"
  mark "$1: start"
  adb shell am start -n $PKG/$PKG.CustomQtActivity
  sleep 25
  wait_tiles
}

install_apk apk-debug/android-debug.apk

# --- no key in the settings file: the default of this branch is off
launch default ru true
shot default-01-running

# --- switch off, modern look
launch off ru true 'ui_state_buttons=false\n'
shot off-01-running
mark "off: Pause"
tap_xy pause "$OFFSTARTXY"
quick off-02-right-away
sleep 4
shot off-03-paused
mark "off: Start again, a double tap on Pause keeps Stop where it was"
tap_xy start "$OFFSTARTXY"
sleep 4
shot off-04-resumed
tap_xy pause "$OFFSTARTXY"
sleep 4
mark "off: Stop"
tap_xy stop "$OFFSTOPXY"
sleep 6
shot off-05-stopped
adb shell input keyevent KEYCODE_BACK || true
sleep 4
shot off-06-home-stopped
for lang in uk de; do
  launch off-$lang $lang true 'ui_state_buttons=false\n'
  tap_xy pause "$OFFSTARTXY"
  sleep 4
  shot off-$lang-03-paused
done

# --- switch on, modern look: as T-312
launch on ru true 'ui_state_buttons=true\n'
shot on-01-running
mark "on: Pause"
tap_xy pause "$WIDEXY"
quick on-02-fading
sleep 4
shot on-03-paused
tap_xy resume "$RESUMEXY"
sleep 4
shot on-04-resumed
tap_xy pause "$WIDEXY"
sleep 4
mark "on: Stop"
tap_xy stop "$STOPXY"
sleep 6
adb shell input keyevent KEYCODE_BACK || true
sleep 4
shot on-05-home-stopped

# --- the classic look: the label only
launch classic-off ru false 'ui_state_buttons=false\n'
tap_xy pause "$OLDSTARTXY"
sleep 4
shot classic-off-02-paused
launch classic-on ru false 'ui_state_buttons=true\n'
tap_xy pause "$OLDSTARTXY"
sleep 4
shot classic-on-02-paused

# --- at once: paused with the switch on, off in the settings, then on again; en for the names
launch live en true 'ui_state_buttons=true\n'
tap_xy pause "$WIDEXY"
sleep 4
shot live-01-paused-on
mark "live: switch off"
toggle_in_settings live-off
conf_value "after off"
sleep 2
shot live-02-paused-off
mark "live: switch on"
toggle_in_settings live-on
conf_value "after on"
sleep 2
shot live-03-paused-on

# --- kept after a restart: off in the settings, the app started again without a new file
mark "restart: switch off"
toggle_in_settings restart-off
sleep 3
adb shell am force-stop $PKG || true
sleep 2
conf_value "after force-stop"
adb shell am start -n $PKG/$PKG.CustomQtActivity
sleep 45
shot restart-01-running
adb shell am force-stop $PKG || true

kill $LOGCAT_PID 2>/dev/null || true
sleep 1
echo "== ANR / crash in the whole log:" >> $STEPLOG
grep -E "ANR in|FATAL EXCEPTION|Fatal signal" full_logcat.txt >> $STEPLOG || echo "none" >> $STEPLOG
echo "== QML warnings of homeform/HomeForm/Home:" >> $STEPLOG
grep -E "HomeForm.ui.qml|Home.qml" full_logcat.txt | grep -i -E "warn|error|TypeError|ReferenceError|binding loop" | head -40 >> $STEPLOG || echo "none" >> $STEPLOG
