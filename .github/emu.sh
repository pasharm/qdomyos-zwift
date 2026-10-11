#!/bin/bash
# Test only (T-199, PR #4645 VoiceOver): what a screen reader gets from the classic look.
# Every shot keeps the uiautomator dump (dumps/<shot>.xml) - the accessibility tree TalkBack
# reads - and .github/a11y.py lists the controls without a name at the end (a11y.txt).
# Run once with the build of master and once with the branch of #4645 to compare.
#
# Phase 1: the first run without a device opens the setup wizard - its first screens.
# Phase 2: a fake treadmill (tiles on the home page): home, side menu, the back key with the
# menu open (#4645 puts drawerInputBlocker over the page), settings, a section, the editor.
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
# app_on_top <what>: the app still on top (the back key may have left it)
app_on_top() {
  dump
  local p=""
  [ -f ui.xml ] && p=$(python3 .github/uitap.py ui.xml --package)
  if [ "$p" = "$PKG" ]; then echo "check app on top ($1): OK" >> $STEPLOG
  else echo "!! check app on top ($1): NOT - '$p'" >> $STEPLOG; fi
}

# Phase 1: the setup wizard
start_app
shot w-01-welcome
tap_ui 'Start' 720 2244; sleep 4
shot w-02-step1
tap_ui 'First-time setup' 720 620; sleep 4
shot w-03-step2
if ! tap_ui 'Next'; then scroll_to 'Next' && tap_ui 'Next'; fi
sleep 4
shot w-04-step3

# Phase 2: a fake treadmill, so the wizard stays closed and the home page has tiles
adb shell am force-stop $PKG
put_conf "applewatch_fakedevice=true\n"
start_app
i=0
while [ $i -lt 18 ]; do
  dump
  if [ -f ui.xml ] && grep -q 'content-desc="Speed' ui.xml; then echo "tiles after $i looks" >> $STEPLOG; break; fi
  i=$((i + 1)); sleep 10
done
shot h-01-home

open_menu
shot m-01-menu
# #4645: drawerInputBlocker (z 9999) over the page while the menu is open - the back key must
# close the menu and keep the app (the author asked about the back gesture)
back "menu open"
sleep 3
shot m-02-after-back
app_on_top "back with the menu open"
if [ -f ui.xml ] && python3 .github/uitap.py ui.xml '^Settings$' > /dev/null; then
  echo "!! menu still open after back (Settings visible)" >> $STEPLOG
fi

open_menu
tap_drawer '^Settings$' 400 900
sleep 8
shot s-01-settings
adb shell input swipe 700 2000 700 1000 400 || true; sleep 1
shot s-02-settings-down
scroll_top
scroll_to '^General Options$' && tap_ui '^General Options$' 700 1000
sleep 4
shot s-03-general
adb shell input swipe 700 2000 700 1200 400 || true; sleep 1
shot s-04-general-down
scroll_top
scroll_to '^Bike Options$' && tap_ui '^Bike Options$' 700 1000
sleep 4
shot s-05-bike
back "settings"
sleep 4
app_on_top "back from settings"
shot s-06-after-back

open_menu
tap_drawer 'Workout Editor' 400 1300
sleep 15
shot e-01-editor
adb shell input swipe 700 2000 700 1000 400 || true; sleep 2
shot e-02-editor-down
back "editor"
sleep 4
app_on_top "back from the editor"


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
