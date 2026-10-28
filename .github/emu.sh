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
# A failed install (API 22: the 554 MB APK did not fit the data partition) left a run of steps
# against the launcher that still ended "OK"
adb shell pm path $PKG > /dev/null 2>&1 || echo "!! APK NOT INSTALLED - the run proves nothing" >> $STEPLOG
# Location on: without it QZ shows "Permissions Required" over every screen (API < 30 images)
adb shell settings put secure location_providers_allowed +gps || true
adb shell settings put secure location_providers_allowed +network || true
adb shell settings put secure location_mode 3 || true
for p in READ_EXTERNAL_STORAGE WRITE_EXTERNAL_STORAGE ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION BLUETOOTH_ADVERTISE BLUETOOTH_CONNECT BLUETOOTH_SCAN POST_NOTIFICATIONS; do
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
# T-119: values of every kind the results show as text - a real number, an integer, a list of
# strings, a list of numbers with labels, a password, a MyWhoosh state key (hidden from the results)
printf '[General]\nlog_debug=%s\nconfirm_stop_workout=true\nui_modern=%s\napplewatch_fakedevice=true\nweight=80.5\nftp=250\nstrava_upload_mode=Request\nzwiftplay_gear_lb=1\nfloatingwindow_type=1\npzp_password=secret\nmywhoosh_link_camera_value=3\n' "$LOG_DEBUG" "$UI_MODERN" > qz.conf
adb push qz.conf /data/local/tmp/qz.conf
adb shell "run-as $PKG mkdir -p 'files/.config/Roberto Viola'"
adb shell "run-as $PKG cp /data/local/tmp/qz.conf 'files/.config/Roberto Viola/qDomyos-Zwift.conf'"
adb shell "run-as $PKG ls -la 'files/.config/Roberto Viola'" || true

# The control tree of the screen into ui.xml (empty when uiautomator gives up, for instance
# while something animates without pause)
dump() {
  rm -f ui.xml
  timeout 25 adb shell uiautomator dump /data/local/tmp/ui.xml > /dev/null 2>&1 || true
  adb pull /data/local/tmp/ui.xml ui.xml > /dev/null 2>&1 || true
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
    # QZ's own Android dialog "Permissions Required" (Bluetooth and location services off, API < 30
    # images): it belongs to the app, so the package check below would let it cover every step
    if [ "$pkg" = "$PKG" ] && grep -q "Permissions Required" ui.xml && xy=$(python3 .github/uitap.py ui.xml '^No$'); then
      echo "!! QZ Permissions Required dialog: No at $xy" >> $STEPLOG
      adb shell input tap $xy || true
      sleep 3
      continue
    fi
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
  adb shell screencap -p /data/local/tmp/$1.png || true
  adb pull /data/local/tmp/$1.png || true
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
has() {
  dump
  if [ -f ui.xml ] && python3 .github/uitap.py ui.xml "$1" > /dev/null; then
    echo "check '$1' ($2): OK" >> $STEPLOG
  else
    echo "!! check '$1' ($2): NOT FOUND" >> $STEPLOG
  fi
}

# T-240: "Changed" in the search bar lists the settings that differ from their default.
# qz.conf above changes Debug Log, Confirm Stop Workout, Fake Device and Player Weight; it also
# writes a password (pzp_password), a MyWhoosh state key and a value equal to its default
# (bike_weight=0) - none of them may be listed. Expected: "Changed settings (4)".
CHANGED='^Changed settings.*'
has_quiet() {
  dump
  [ -f ui.xml ] && python3 .github/uitap.py ui.xml "$1" > /dev/null
}
not_has() {
  dump
  if [ -f ui.xml ] && python3 .github/uitap.py ui.xml "$1" > /dev/null; then
    echo "!! check no '$1' ($2): SHOWN" >> $STEPLOG
  else
    echo "check no '$1' ($2): OK" >> $STEPLOG
  fi
}
# The headers and card titles of the results, into steps.log
results() {
  dump
  echo "results ($1):" >> $STEPLOG
  [ -f ui.xml ] && python3 -c '
import re, sys, xml.etree.ElementTree as ET
for n in ET.parse(sys.argv[1]).getroot().iter("node"):
    t = (n.get("text") or "") or (n.get("content-desc") or "")
    if t and n.get("bounds") != "[0,0][0,0]":
        print("   ", repr(t), n.get("bounds"))
' ui.xml | head -60 >> $STEPLOG
}
# The toolbar button is named "Search settings" too: the bar is open when Changed shows
open_search() {
  if ! has_quiet '^Changed$'; then
    tap_ui '🔍|Search settings'
    sleep 2
  fi
}
type_query() {
  # The field of the bar, not the toolbar button of the same name (y below the toolbar)
  # Modern look: the bar scrolls away with the results (after find_card it was off the top and
  # the tap opened a result instead)
  scroll_top
  tap 470 338 "search field"
  sleep 1
  # The tap puts the cursor where it lands, the deletes take only what is before it (T-119:
  # "theme" became "themew type"): to the end first
  adb shell input keyevent KEYCODE_MOVE_END || true
  for i in $(seq 1 30); do adb shell input keyevent KEYCODE_DEL || true; done
  [ -n "$1" ] && adb shell input text "$1"
  sleep 3
  hide_keyboard
}


# T-318: QtInputConnection of the patched QtAndroid.jar references android.view.inputmethod.TextAttribute
# (API 33) in its new methods. The class is loaded when a text field takes the focus and the
# keyboard connects (QtEditText.onCreateInputConnection) - on an old API that is the moment it
# would fail (VerifyError, NoClassDefFoundError, a crash). Steps: the settings search field
# takes the focus, the keyboard shows, text is typed and deleted, the results follow it.
mark() { echo "$(date +%H:%M:%S) $1" >> $STEPLOG; adb shell log -t T318 "'$1'" || true; }
echo "== API $(adb shell getprop ro.build.version.sdk | tr -d '\r')" >> $STEPLOG
open_menu
shot s-menu
tap_drawer '^Settings$' 400 900
sleep 8
shot s-00
open_search
mark "focus search field"
tap 470 338 "search field"
sleep 4
adb shell dumpsys input_method | grep -E "mInputShown|mServedInputConnection|mCurInputConnection|inputType" | sed 's/^/input_method: /' >> $STEPLOG || true
# Without the keyboard shown the field has no focus and QtInputConnection was never loaded: the
# run then proves nothing (runs 40780015706, 40781192936: dialogs over the app, no install on API 22).
# mInputShown, not the connection field: its name differs by API (mServedInputConnectionWrapper on 28)
if adb shell dumpsys input_method | grep -q "mInputShown=true"; then
  echo "keyboard shown for the field: OK" >> $STEPLOG
else
  echo "!! keyboard not shown: the field did not take the focus - the run proves nothing" >> $STEPLOG
fi
shot t-keyboard
mark "type speed"
adb shell input text "speed"
sleep 3
shot t-typed
results "speed"
mark "delete 3"
for i in 1 2 3; do adb shell input keyevent KEYCODE_DEL || true; done
sleep 2
shot t-deleted
results "sp"
hide_keyboard
mark "focus again"
tap 470 338 "search field"
sleep 3
shot t-refocus
adb shell pidof $PKG > /dev/null && echo "app alive at the end: OK" >> $STEPLOG || echo "!! app not running at the end" >> $STEPLOG
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
echo "== web page errors"; grep -iE "Uncaught|chromium.*(Error|error)|Error is " full_logcat.txt | tail -n 40 || true
echo "== T-318 class loading / crashes (none expected)"
grep -E "VerifyError|NoClassDefFoundError|NoSuchMethodError|ClassNotFoundException|TextAttribute|FATAL EXCEPTION|AndroidRuntime: |Rejecting re-init|QtInputConnection" full_logcat.txt | tee t318-errors.txt | sed 's/^/!! /' >> $STEPLOG || true
[ -s t318-errors.txt ] || echo "no class loading errors, no crash: OK" >> $STEPLOG
echo "== steps"; cat $STEPLOG
