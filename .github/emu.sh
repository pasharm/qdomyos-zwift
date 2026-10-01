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
# LOG_DEBUG (workflow input "log_debug"): false runs with the debug log off, to see that the app
# works without it and writes no log file. QML errors do not reach logcat then.
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
# The launcher of the emulator image hangs on the slow CI machine and its "isn't responding"
# dialog came back before every step, however often Wait was tapped: the classic run
# 36505671077 got the dialog on nearly every shot. No error dialogs at all for the run; an
# ANR still reaches logcat and the end of steps.log ("ANR in")
adb shell settings put global hide_error_dialogs 1 || true

# T-060, T-066: a fake treadmill, so the home page has tiles (without a device it shows the search help)
printf '[General]\nlog_debug=%s\nconfirm_stop_workout=true\nui_modern=%s\nfakedevice_treadmill=true\n' "$LOG_DEBUG" "$UI_MODERN" > qz.conf
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
# Recorded from the start: a dump at the end (logcat -d) has lost the first lines of the app by
# then - the main buffer wraps in a long run, so the version line and the settings dump of
# main() were missing in the runs of the modern look
adb logcat > full_logcat.txt 2>/dev/null &
LOGCAT_PID=$!
adb shell am start -n $PKG/$PKG.CustomQtActivity
sleep 20
shot 01-healthconnect
# Only while that screen is on top: once it had closed by itself and the back key closed
# the first-run wizard instead
if [ -f ui.xml ] && [ "$(python3 .github/uitap.py ui.xml --package)" = "$PKG" ]; then
  echo "health connect screen not shown: no back key" >> $STEPLOG
else
  back "health connect"
fi
sleep 30
shot 02-first-screen        # the wizard opens on the first run
# T-060: with the fake treadmill the wizard does not open; its back keys would leave the app
shot 04-home

# T-066: the home list settles on the nearest whole row, or on the end of the list, wherever
# the scroll stops; a flick settles where it stopped by itself. The dumps give the tile bounds
# after the snap (rows line up with the top of the grid, or the last row with its bottom).
wait_tiles() {
  local i
  # The fake treadmill comes after the first search ends: wait for its tiles (at most 3 min)
  for i in $(seq 1 18); do
    dump
    if [ -f ui.xml ] && grep -q 'content-desc="Speed' ui.xml; then
      echo "tiles shown after $i looks" >> $STEPLOG; return 0
    fi
    sleep 10
  done
  echo "!! tiles NOT shown" >> $STEPLOG
}
drag_from_top() {
  scroll_top; sleep 2
  echo "[$1] drag up $2 px (slow)" >> $STEPLOG
  adb shell input swipe 700 1800 700 $((1800 - $2)) 1500 || true
  sleep 3
  shot "h-$1-drag-$2"
}
flick_from_top() {
  scroll_top; sleep 2
  echo "[$1] flick up 700 px in 120 ms" >> $STEPLOG
  adb shell input swipe 700 1900 700 1200 120 || true
  sleep 5
  shot "h-$1-flick"
}
# The app again with other settings (read at start): ui_tile_snap, ui_zoom
restart_with() {
  echo "== restart: $*" >> $STEPLOG
  adb shell am force-stop $PKG || true
  sleep 2
  { printf '[General]\nlog_debug=%s\nconfirm_stop_workout=true\nui_modern=%s\nfakedevice_treadmill=true\n' "$LOG_DEBUG" "$UI_MODERN"
    for kv in "$@"; do echo "$kv"; done; } > qz.conf
  adb push qz.conf /data/local/tmp/qz.conf
  adb shell "run-as $PKG cp /data/local/tmp/qz.conf 'files/.config/Roberto Viola/qDomyos-Zwift.conf'"
  adb shell am start -n $PKG/$PKG.CustomQtActivity
  sleep 20
  wait_tiles
}

wait_tiles
shot h-top
for d in 300 600 900 1300; do drag_from_top on $d; done
flick_from_top on
# The end of the list: quick swipes up, then a slow pull back down
for i in 1 2 3 4 5 6; do adb shell input swipe 700 2000 700 600 150 || true; done
sleep 4
shot h-on-end
echo "[on] drag down 200 px from the end (slow)" >> $STEPLOG
adb shell input swipe 700 1000 700 1200 1500 || true; sleep 3
shot h-on-end-back-200
echo "[on] drag down 350 px from there (slow)" >> $STEPLOG
adb shell input swipe 700 1000 700 1350 1500 || true; sleep 3
shot h-on-end-back-350

# Switched off: the list stays where it stopped
restart_with ui_tile_snap=false
shot h-off-top
drag_from_top off 600
flick_from_top off

# A short list: small tiles, so all of them or nearly all fit on the screen
restart_with ui_zoom=50
shot h-short-top
drag_from_top short 150
drag_from_top short 400
scroll_top; sleep 2

adb shell "ps -A 2>/dev/null || ps" > process_list.txt || true
shot screenshot
kill $LOGCAT_PID 2>/dev/null || true
wait $LOGCAT_PID 2>/dev/null || true
# If the recording broke off (adb restarted), the dump of the end is better than nothing
adb logcat -d > end_logcat.txt || true
if [ "$(wc -l < full_logcat.txt)" -lt "$(wc -l < end_logcat.txt)" ]; then
  echo "!! logcat recording shorter than the dump at the end: the dump is kept" >> $STEPLOG
  mv end_logcat.txt full_logcat.txt
else
  rm -f end_logcat.txt
fi
# The debug logs the app wrote itself (Documents/QZ on Android 14+): none with the log off
mkdir -p qz-logs
adb shell 'ls -la /sdcard/Documents/QZ/ 2>&1' > qz-logs/listing.txt || true
for f in $(adb shell 'ls /sdcard/Documents/QZ/ 2>/dev/null' | tr -d '\r' | grep '^debug-.*[.]log$'); do
  adb pull "/sdcard/Documents/QZ/$f" "qz-logs/$f" > /dev/null 2>&1 || true
done
echo "== app debug logs"; cat qz-logs/listing.txt; ls -la qz-logs
echo "== steps"; cat $STEPLOG
echo "== timing"; grep -E "QZ-TIMING|QZ-THEME" full_logcat.txt || true
# The dialogs are hidden (hide_error_dialogs above), so hangs are only here
grep -E "ANR in" full_logcat.txt | sed 's/^/!! /' >> $STEPLOG || true
echo "== ANR"; grep -E "ANR in" full_logcat.txt || true
grep -iE "qrc:|\.qml|warning|critical|fatal" full_logcat.txt | tail -n 80 || true
