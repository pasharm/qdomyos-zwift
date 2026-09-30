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

printf '[General]\nlog_debug=%s\nconfirm_stop_workout=true\nui_modern=%s\n' "$LOG_DEBUG" "$UI_MODERN" > qz.conf
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
tap_ui 'Start' 720 2244
sleep 4
shot 03-wizard-step1
tap_ui 'First-time setup' 720 620
sleep 4
shot 03b-wizard-step2
# The short branch to its end: a feature, virtual shifting, Finish, the last page (the
# order of Finish and Back, the progress bar full at the end). Finish turns the gears tile
# on, so the home page below has it and "Changed" lists it
back "wizard"; sleep 3
wizard_done=false
if tap_ui 'Help with a specific feature'; then
  sleep 3
  shot 03c-wizard-features
  if tap_ui 'Virtual Shifting'; then
    sleep 3
    shot 03d-wizard-virtual-shifting
    if tap_ui 'Finish'; then
      sleep 3
      shot 03e-wizard-done
      tap_ui 'Close' && wizard_done=true
      sleep 5
    fi
  fi
fi
if [ "$wizard_done" != true ]; then
  back "wizard"; sleep 2
  back "wizard"; sleep 3
  back "wizard"; sleep 5
fi
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
# Combo box opened again (from the phone: the second tap on the same field did nothing).
# Gender sits at the bottom of the opened section; OK is not pressed, nothing is saved
tap 928 2118 "gender combo, 1st"; sleep 2
shot 08a-combo-open-1
tap_ui '^Female$'; sleep 2
tap 928 2118 "gender combo, 2nd"; sleep 2
shot 08b-combo-open-2
tap_ui '^Male$'; sleep 2
tap 928 2118 "gender combo, 3rd"; sleep 2
back "combo popup"; sleep 2
tap 928 2118 "gender combo, 4th after back"; sleep 2
shot 08c-combo-open-after-back
back "combo popup"; sleep 2
adb shell input swipe 700 2100 700 700 400 || true
sleep 3
shot 09-settings-scrolled
# Accent colours, with the wallpaper colour first where Android offers it (API 31+). They sit
# with the switch of the look in Experimental Features, near the end of the page
if scroll_to 'Experimental Features'; then
  tap_ui 'Experimental Features'
  sleep 3
  if scroll_to 'Accent colour'; then
    shot 09b-accent-colours
    if tap_ui 'Wallpaper colour'; then
      sleep 2
      shot 09c-accent-wallpaper
    fi
  fi
fi

# Night mode of the system while the app runs: it is read again on return to the foreground
adb shell cmd uimode night yes || true
sleep 2
adb shell input keyevent KEYCODE_HOME || true
sleep 3
adb shell am start -n $PKG/$PKG.CustomQtActivity
sleep 5
shot 10-settings-dark
# Modern: the search field on top of the settings, a result opens the setting itself, and
# "Changed" lists what differs from the defaults
if [ "$UI_MODERN" = "true" ]; then
  scroll_top
  tap_ui 'Search settings' 600 330
  sleep 2
  adb shell input text "miles" || true
  sleep 3
  hide_keyboard
  shot 10b-search-dark
  tap_ui 'Use Miles unit in UI'
  sleep 1
  shot 10c-search-jump-dark          # scrolled to the setting, lit for a moment
  sleep 3
  scroll_top
  tap_ui 'Changed'
  sleep 3
  shot 10d-changed-dark
  tap_ui 'Changed'                   # off again
  sleep 2
  # A setting three sections deep (Experimental > Virtual Device > Wahoo direct connect):
  # reported to open the plain settings list instead of the setting
  scroll_top
  tap_ui 'Search settings' 600 330
  sleep 2
  adb shell input text "wah" || true
  sleep 3
  hide_keyboard
  shot 10e-search-wah
  tap_ui 'MyWhoosh Compatibility'
  sleep 1
  shot 10f-jump-mywhoosh
  sleep 2
  shot 10g-jump-mywhoosh-later
  adb shell input keyevent 4          # back: the results again
  sleep 2
  shot 10h-back-to-results
  # A setting on no page (Garmin ANT+): not among the results any more (settings.qml,
  # searchHiddenSettings), steps.log must say "tap 'Garmin ANT\+': NOT FOUND, skipped". Before,
  # its result led nowhere; reported to throw out to the home page
  tap_ui 'Clear'
  sleep 1
  tap_ui 'Search settings' 600 330
  sleep 2
  adb shell input text "garmin%sant" || true
  sleep 3
  hide_keyboard
  shot 10i-search-garmin-ant
  tap_ui 'Garmin ANT\+'
  sleep 2
  shot 10j-tap-garmin-ant            # the same results, without Garmin ANT+
  # A label with its unit on the page: "Bike Weight (kg)" lit itself, not its whole section
  tap_ui 'Clear'
  sleep 1
  tap_ui 'Search settings' 600 330
  sleep 2
  adb shell input text "bike%sweight" || true
  sleep 3
  hide_keyboard
  tap_ui 'Bike Weight'
  sleep 1
  shot 10k-jump-bike-weight
  adb shell input keyevent 4
  sleep 2
  # A title label over its list and OK: lit together, inside the page margins
  tap_ui 'Clear'
  sleep 1
  tap_ui 'Search settings' 600 330
  sleep 2
  adb shell input text "ftms%sbike" || true
  sleep 3
  hide_keyboard
  tap_ui 'FTMS Bike'
  sleep 1
  shot 10l-jump-ftms-bike
  adb shell input keyevent 4
  sleep 2
  # The Wahoo Options page from the results: the +/- fields, the number centred
  tap_ui 'Clear'
  sleep 1
  tap_ui 'Search settings' 600 330
  sleep 2
  adb shell input text "chainring" || true
  sleep 3
  hide_keyboard
  tap_ui 'Chainring Size'
  sleep 3
  shot 10m-wahoo-options-page
  adb shell input keyevent 4
  sleep 2
  # The inclination to resistance table: modern +/- fields instead of the grid
  tap_ui 'Clear'
  sleep 1
  tap_ui 'Search settings' 600 330
  sleep 2
  adb shell input text "resistance%stable" || true
  sleep 3
  hide_keyboard
  tap_ui 'Custom Inclination to Resistance Table'
  sleep 3
  shot 10n-inclination-table
  adb shell input keyevent 4
  sleep 2
fi
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
# Device list: modern – the page's own menu under the field, classic – the system list
tap 1148 426 "editor device select"; sleep 2
shot 17a-editor-device-menu
tap 200 2300 "close the list"; sleep 2
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
# Modern: no Close at the bottom any more, the back arrow of the toolbar; classic: its Close
if [ "$UI_MODERN" = "true" ]; then
  tap $MENU "back: home"
else
  tap_ui 'Close' 720 2364
fi
sleep 3
shot 24-after-close-dark            # the home page again
# Modern: the kept charts page opened again draws its charts at once (?still=), no growing
if [ "$UI_MODERN" = "true" ]; then
  open_menu
  tap_drawer 'Charts' 307 1263
  sleep 1
  shot 24a-charts-reopen
  sleep 3
  shot 24b-charts-reopen-later
  tap $MENU "back: home"
  sleep 3
fi

# Yes to a restart question closes the app (from the phone: after Yes on the FitShow question
# the card stayed on the screen and the process lived on). OK of UI Zoom asks for a restart
# on the way back; the value stays 100
open_menu
tap_drawer 'Settings' 525 861
sleep 8
dump
if [ -z "$(python3 .github/uitap.py ui.xml 'UI Zoom:?' 2>/dev/null)" ]; then
  tap_ui 'General Options' 720 520
  sleep 4
  dump
fi
xy=$(python3 .github/uitap.py ui.xml 'UI Zoom:?' 2>/dev/null)
if [ -n "$xy" ]; then
  tap 1290 "${xy#* }" "UI Zoom OK"
  sleep 2
  tap $MENU "back: home"; sleep 3
  shot 25-restart-question
  tap_ui '^(Yes|YES)$' || true
  sleep 10
  echo "after Yes: pid '$(adb shell pidof $PKG | tr -d '\r')'" >> $STEPLOG
  adb shell screencap -p /sdcard/26-after-yes.png || true
  adb pull /sdcard/26-after-yes.png || true
else
  echo "UI Zoom not found, restart question skipped" >> $STEPLOG
fi

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
