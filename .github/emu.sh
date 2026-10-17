#!/bin/bash
# Test only (T-262): the classic look with the text size that follows the system (Android
# font_scale) or the own "Text size" setting. The reference APK (apk-base, master with the tile
# size rename) is shot first at font_scale 1.0; then the tested APK (apk-debug) at 1.0, after a
# change to 1.3 while in the background (no restart), at 2.0 (capped at 150 %) and with the
# switch off at 170 %.
PKG=org.cagnulen.qdomyoszwift
UI_MODERN=${UI_MODERN:-false}
LOG_DEBUG=${LOG_DEBUG:-true}
STEPLOG=steps.log
: > $STEPLOG
mkdir -p dumps

# install_apk <apk>: a fresh install with the permissions granted
install_apk() {
  adb uninstall $PKG > /dev/null 2>&1 || true
  adb install "$1"
  for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION BLUETOOTH_ADVERTISE BLUETOOTH_CONNECT BLUETOOTH_SCAN POST_NOTIFICATIONS; do
    adb shell pm grant $PKG android.permission.$p || true
  done
  adb shell appops set $PKG MANAGE_EXTERNAL_STORAGE allow || true
  echo "== installed $1" >> $STEPLOG
}
install_apk apk-base/android-debug.apk
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

# Taps the node matching rx that is the lowest on the screen, or of class cls when given:
# the Stop of the confirmation lies under the Stop button, the select under its label
tap_node() {
  local rx="$1" cls="$2" xy=""
  dump
  [ -f ui.xml ] && xy=$(python3 -c '
import re, sys, xml.etree.ElementTree as ET
rx, cls = sys.argv[2], sys.argv[3]
best = None
for n in ET.parse(sys.argv[1]).getroot().iter("node"):
    t = (n.get("text") or "") or (n.get("content-desc") or "")
    if not re.fullmatch(rx, t, re.I) or (cls and n.get("class") != cls):
        continue
    m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", n.get("bounds") or "")
    if not m:
        continue
    x1, y1, x2, y2 = map(int, m.groups())
    if x2 <= x1 or y2 <= y1:
        continue
    if best is None or y1 > best[1]:
        best = ((x1 + x2) // 2, y1, (y1 + y2) // 2)
if best:
    print(best[0], best[2])
' ui.xml "$rx" "$cls")
  if [ -n "$xy" ]; then
    echo "tap node '$rx' ${cls:+($cls) }at $xy" >> $STEPLOG
    adb shell input tap $xy || true
  else
    echo "!! tap node '$rx' ${cls:+($cls) }NOT FOUND" >> $STEPLOG
    return 1
  fi
}

wait_tiles() {
  local i
  # The fake device comes after the first search ends: wait for its tiles (at most 3 min)
  for i in $(seq 1 18); do
    dump
    if [ -f ui.xml ] && grep -q 'content-desc="Speed' ui.xml; then
      echo "tiles shown after $i looks" >> $STEPLOG; return 0
    fi
    sleep 10
  done
  echo "!! tiles NOT shown" >> $STEPLOG
}

# One round of the same screens: home, the stop question, the drawer, Settings, General
# Options (top) and General UI Options (the text size block, then one swipe further)
round() {
  local s="$1"
  wait_tiles
  sleep 5
  shot $s-01-home
  tap_ui '^Stop$' 1200 2300
  sleep 3
  shot $s-02-stop-question
  tap_node '(No|Cancel)' || back "stop question"
  sleep 2
  open_menu
  shot $s-03-drawer
  tap_drawer '^Settings$' 400 900
  sleep 8
  shot $s-04-settings
  if scroll_to '^General Options$'; then
    tap_ui '^General Options$' 700 1000
    sleep 4
    shot $s-05-general
    tap_ui '^General Options$' 700 1000
    sleep 3
  fi
  if scroll_to '^General UI Options$'; then
    tap_ui '^General UI Options$' 700 1000
    sleep 4
    shot $s-06-ui-options
    adb shell input swipe 700 2000 700 1300 400 || true
    sleep 2
    shot $s-07-ui-options-2
  fi
}

# start_fresh <font_scale> <extra conf>: stop, settings file, system font size, start
start_fresh() {
  adb shell am force-stop $PKG || true
  put_conf "applewatch_fakedevice=true\nconfirm_stop_workout=true\napp_language=en\n$2"
  adb shell settings put system font_scale $1 || true
  echo "== start: font_scale=$(adb shell settings get system font_scale) conf: $2" >> $STEPLOG
  sleep 3
  start_app
}

# 1. Reference: master with the tile size rename, font_scale 1.0
start_fresh 1.0 ""
round b10

# 2. The tested APK, the same settings file, font_scale 1.0: the switch on by default
install_apk apk-debug/android-debug.apk
start_fresh 1.0 ""
round a10

# 3. font_scale 1.3 while QZ is in the background: back in the foreground the text is bigger
#    without a restart (the page left open on General UI Options)
adb shell input keyevent KEYCODE_HOME || true
sleep 3
adb shell settings put system font_scale 1.3 || true
echo "== font_scale=$(adb shell settings get system font_scale) in the background" >> $STEPLOG
sleep 3
adb shell am start -n $PKG/$PKG.CustomQtActivity || true
sleep 8
shot a13live-06-ui-options
back "settings page"
sleep 3
shot a13live-01-home

# 4. font_scale 2.0 after a restart: capped at 150 %
start_fresh 2.0 ""
round a20

# 5. The switch off, Text size 170 %, font_scale 2.0 left on: the own size wins
start_fresh 2.0 "ui_text_scale_system=false\nui_text_scale=170\n"
round m170

# 6. The switch off, Text size 100 %: as the reference again
start_fresh 1.0 "ui_text_scale_system=false\nui_text_scale=100\n"
round m100
adb shell settings put system font_scale 1.0 || true

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
