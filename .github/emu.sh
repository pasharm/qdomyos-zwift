#!/bin/bash
# Test only (T-196, #5373 review): a language change keeps the ProForm/NordicTrack model flags.
# Models set in qz.conf, both "Specific Model" lists opened (initialized), the bike one changed by
# a tap (the handler must still write the flags), then English -> Ukrainian in General Options.
# The model flags of qz.conf and the combo log lines go to steps.log after each step.
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
# snap name: the frame alone, at once - a dump waits for the screen to settle, so after it a
# toast has already faded
snap() {
  echo "-- snap $1" >> $STEPLOG
  adb shell screencap -p /sdcard/$1.png || true
  adb pull /sdcard/$1.png || true
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
}
# open_settings: from anywhere back to home, then the menu and Settings
open_settings() {
  open_menu
  tap_drawer '^Settings$' 400 900
  sleep 8
}

# tap_row 'anchor' 'target': the control in the row of the anchor (the OK of one setting on a
# page with many OK buttons)
tap_row() {
  local xy=""
  ensure_app
  [ -f ui.xml ] || dump
  [ -f ui.xml ] && xy=$(python3 .github/uirow.py ui.xml "$1" "$2")
  if [ -n "$xy" ]; then
    echo "tap '$2' in the row of '$1' at $xy" >> $STEPLOG
    adb shell input tap $xy || true
  else
    echo "tap '$2' in the row of '$1': NOT FOUND" >> $STEPLOG
    return 1
  fi
}
# pick 'regex': an item of the open combo list, looked for up the list, then down
pick() {
  local i
  for i in $(seq 1 16); do
    dump
    if [ -f ui.xml ] && python3 .github/uitap.py ui.xml "$1" > /dev/null; then
      tap_ui "$1"
      return 0
    fi
    # In the middle of the list (x 718-1218 on the Nexus 6): a swipe outside closes it
    if [ $i -le 6 ]; then
      adb shell input swipe 968 1800 968 1200 300 || true
    else
      adb shell input swipe 968 1200 968 1800 300 || true
    fi
    sleep 1
  done
  echo "pick '$1': NOT FOUND" >> $STEPLOG
  back "combo list"
  return 1
}
# switch_language 'row label' 'current' 'wanted' prefix: the App Language combo, then its OK
switch_language() {
  scroll_to "$1" || return 1
  shot "$4-a-before"
  tap_row "$1" "$2" || return 1
  sleep 2
  shot "$4-b-list"
  pick "$3" || return 1
  sleep 2
  tap_row "$1" '^OK$' || return 1
  echo "OK pressed at $(date +%T.%N)" >> $STEPLOG
  sleep 1
  snap "$4-c-after-1s"
  sleep 4
  shot "$4-d-after-5s"
}

# models_state 'label': the model flags in the settings file and the combo log lines so far
models_state() {
  sleep 5
  echo "== flags ($1):" >> $STEPLOG
  adb shell "run-as $PKG cat 'files/.config/Roberto Viola/qDomyos-Zwift.conf'" |
    grep -E '^(app_language|proform_studio|proform_tdf_10|nordictrack_x22i)=' | tr -d '\r' |
    sed 's/^/   /' >> $STEPLOG || true
  echo "== combo log ($1):" >> $STEPLOG
  adb logcat -d | grep -E 'ModelComboBox' | sed 's/^/   /' >> $STEPLOG || true
}

# A fake treadmill, so the wizard stays closed; English at the start; the bike model "Proform
# Studio Bike" (index 2) and the treadmill model "NordicTrack X22i" (index 4)
put_conf "applewatch_fakedevice=true\napp_language=en\nproform_studio=true\nnordictrack_x22i=true\n"
start_app
shot a-01-home-en
open_settings
models_state "start"

# The bike list: open its section (initializeModel), then pick another model by a tap
scroll_to '^Bike Options$' && tap_ui '^Bike Options$'
sleep 3
scroll_to '^Proform/Norditrack Options$' && tap_ui '^Proform/Norditrack Options$'
sleep 3
scroll_to '^Specific Model:$'
shot b-01-bike-open
models_state "bike section open"
tap_row '^Specific Model:$' '^Proform Studio Bike$' && sleep 2 && shot b-02-bike-list &&
  pick '^Proform TDF 1\.0$'
sleep 2
shot b-03-bike-picked
models_state "bike model picked by a tap: proform_tdf_10 expected"

# The treadmill list: open its section only
scroll_top
scroll_to '^Treadmill Options$' && tap_ui '^Treadmill Options$'
sleep 3
scroll_to '^Proform/Nordictrack Options$' && tap_ui '^Proform/Nordictrack Options$'
sleep 3
scroll_to '^Specific Model:$'
shot b-04-treadmill-open
models_state "treadmill section open"

# The language change with both lists initialized
scroll_top
echo "language change at $(date +%T)" >> $STEPLOG
scroll_to '^General Options$' && tap_ui '^General Options$' 700 1000
sleep 4
switch_language '^App Language:$' '^English$' '^Ukrainian$' c
models_state "after the language change"
back "settings"; sleep 5
shot d-01-home-uk
models_state "after leaving the settings"


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
python3 .github/a11y.py dumps > a11y.txt || true
echo "== steps"; cat $STEPLOG
echo "== a11y summary"; sed -n '/^== summary/,$p' a11y.txt
echo "== QML warnings"; grep -iE "qrc:|\.qml:[0-9]+" full_logcat.txt | grep -iE "warning|error|ReferenceError|TypeError" | sort | uniq -c | sort -nr | head -60 || true
echo "== web page errors"; grep -iE "Uncaught|chromium.*(Error|error)|Error is " full_logcat.txt | tail -n 40 || true
