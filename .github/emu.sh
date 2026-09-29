#!/bin/bash
# Test only: start an already built APK on the emulator with log_debug on, so the Qt
# warnings (QML errors among them) reach logcat, then keep logcat and screenshots.
# The emulator starts in the day mode of the system: with the appearance on "auto" the
# first screens are the light theme, the last ones the dark theme after "night yes".
#
# UI_MODERN (workflow input "modern"): false runs the same steps in the classic look, for a
# before/after comparison. The two looks place their controls differently, so the steps
# find a control by its text or accessible name in a uiautomator dump (tap_ui, .github/
# uitap.py) and use fixed coordinates only when the dump has no such control. steps.log
# says which way every tap went; dumps/<shot>.xml is the control tree behind every shot.
PKG=org.cagnulen.qdomyoszwift
UI_MODERN=${UI_MODERN:-true}
STEPLOG=steps.log
: > $STEPLOG
mkdir -p dumps

adb install apk-debug/android-debug.apk
for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION BLUETOOTH_ADVERTISE BLUETOOTH_CONNECT BLUETOOTH_SCAN POST_NOTIFICATIONS; do
  adb shell pm grant $PKG android.permission.$p || true
done
adb shell appops set $PKG MANAGE_EXTERNAL_STORAGE allow || true
adb shell cmd uimode night no || true

printf '[General]\nlog_debug=true\nconfirm_stop_workout=true\nui_modern=%s\n' "$UI_MODERN" > qz.conf
adb push qz.conf /data/local/tmp/qz.conf
adb shell "run-as $PKG mkdir -p 'files/.config/Roberto Viola'"
adb shell "run-as $PKG cp /data/local/tmp/qz.conf 'files/.config/Roberto Viola/qDomyos-Zwift.conf'"
adb shell "run-as $PKG ls -la 'files/.config/Roberto Viola'" || true

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
    if grep -q "t responding" ui.xml && xy=$(python3 .github/uitap.py ui.xml 'Wait'); then
      echo "!! $pkg not responding: Wait at $xy" >> $STEPLOG
      adb shell input tap $xy || true
    else
      echo "!! $pkg over the app: back key" >> $STEPLOG
      adb shell input keyevent KEYCODE_BACK || true
    fi
    sleep 3
  done
}
shot() {
  [ "$1" = "01-healthconnect" ] || ensure_app
  echo "-- shot $1" >> $STEPLOG
  adb shell screencap -p /sdcard/$1.png || true
  adb pull /sdcard/$1.png || true
  dump
  [ -f ui.xml ] && cp ui.xml dumps/$1.xml
}
# tap_ui 'regex' [x y]: the control whose whole text or accessible name matches, else the
# fallback coordinates; without them the step is skipped (return 1)
tap_ui() {
  local rx="$1" fx="$2" fy="$3" xy=""
  ensure_app
  dump
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
tap() { ensure_app; echo "tap $1 $2 ($3)" >> $STEPLOG; adb shell input tap $1 $2 || true; }
back() { echo "back ($1)" >> $STEPLOG; adb shell input keyevent KEYCODE_BACK || true; }
# Toolbar buttons are icons without text: the same place in both looks (Nexus 6: 1440x2560
# px, 3.5 px per dp)
MENU="84 168"          # menu on the home page, back arrow elsewhere
LOCK="1187 168"        # tile lock on the home page
open_menu() { tap $MENU "menu"; sleep 3; adb shell input swipe 500 700 500 2300 300 || true; sleep 2; }

adb logcat -c || true
adb shell am start -n $PKG/$PKG.CustomQtActivity
sleep 20
shot 01-healthconnect
back "health connect"
sleep 30
shot 02-first-screen        # the wizard opens on the first run
tap_ui 'Start' 720 2244
sleep 4
shot 03-wizard-step1
tap_ui 'First-time setup' 720 620
sleep 4
shot 03b-wizard-step2
back "wizard"; sleep 2
back "wizard"; sleep 3
back "wizard"; sleep 5
shot 04-home
tap_ui 'Stop' 952 462        # confirmation dialog
sleep 3
shot 04b-stop-dialog
# The classic dialog does not close on the back key: its own button
tap_ui 'Cancel|No' || back "stop dialog"
sleep 2
open_menu
shot 05-drawer
tap_drawer 'Workout Editor' 403 927
sleep 15
shot 05b-editor-light
adb shell input swipe 700 2000 700 900 400 || true
sleep 2
shot 05c-editor-light-scrolled
tap $MENU "back: home"; sleep 3
open_menu
tap_drawer 'Settings' 525 861
sleep 8
shot 07-settings
tap_ui 'General Options' 720 520   # a section header
sleep 4
shot 08-settings-open
adb shell input swipe 700 2100 700 700 400 || true
sleep 3
shot 09-settings-scrolled

# Night mode of the system while the app runs: it is read again on return to the foreground
adb shell cmd uimode night yes || true
sleep 2
adb shell input keyevent KEYCODE_HOME || true
sleep 3
adb shell am start -n $PKG/$PKG.CustomQtActivity
sleep 5
shot 10-settings-dark
tap $MENU "back: home"; sleep 3
shot 11-home-dark
tap_ui 'Stop' 952 462
sleep 3
shot 12-stop-dialog-dark
tap_ui 'Cancel|No' || back "stop dialog"
sleep 2
open_menu
tap_ui 'Profile: .*' 335 434        # classic drawer entry; the modern drawer has a chip there
sleep 5
shot 13-profiles-dark
tap $MENU "back: home"; sleep 3
tap $LOCK "tile lock"               # modern: hidden until the equipment is connected
sleep 1
shot 14-lock-popup-dark
sleep 4                             # the notice closes by itself after 2 s
open_menu
tap_drawer 'Settings' 525 861
sleep 8
tap_ui 'Tiles Options' 717 1239
sleep 6
shot 15-tiles-dark
adb shell input swipe 700 2100 700 900 400 || true
sleep 3
shot 16-tiles-scrolled-dark
tap $MENU "back: settings"; sleep 3
shot 16b-settings-after-tiles-dark  # load and save buttons still in the toolbar
tap $MENU "back: home"; sleep 3

open_menu
tap_drawer 'Workout Editor' 403 927
sleep 15
shot 17-editor-dark
adb shell input swipe 700 2000 700 900 400 || true
sleep 2
shot 18-editor-dark-scrolled
tap $MENU "back: home"; sleep 3
open_menu
tap_drawer 'Open GPX' 346 1096
sleep 8
shot 19-gpx-dark
# Landscape: the list column and the map side by side
adb shell settings put system accelerometer_rotation 0 || true
adb shell settings put system user_rotation 1 || true
sleep 5
shot 19c-gpx-landscape-dark
adb shell settings put system user_rotation 0 || true
sleep 5
tap $MENU "back: home"; sleep 3
open_menu
tap_drawer 'Workouts History' 433 1431
sleep 8
shot 20-history-dark
# Calendar button: on the right of the modern header, on the left of the classic one
if [ "$UI_MODERN" = "true" ]; then
  tap_ui 'Calendar' 1299 322
else
  tap_ui 'Calendar|📅' 126 300
fi
sleep 3
shot 21-calendar-dark
back "calendar"; sleep 2
tap $MENU "back: home"; sleep 3
open_menu
tap_drawer 'Charts' 307 1263
sleep 1
shot 22a-charts-loading-dark        # while loading: the busy indicator, no white page
sleep 9
shot 22-charts-dark
adb shell input swipe 700 2000 700 900 400 || true
sleep 2
shot 23-charts-dark-scrolled
tap_ui 'Close' 720 2364             # the bottom of the charts page
sleep 3
shot 24-after-close-dark            # the home page again

adb shell "ps -A 2>/dev/null || ps" > process_list.txt || true
shot screenshot
adb logcat -d > full_logcat.txt || true
echo "== steps"; cat $STEPLOG
echo "== timing"; grep "QZ-TIMING" full_logcat.txt || true
grep -iE "qrc:|\.qml|warning|critical|fatal" full_logcat.txt | tail -n 80 || true
