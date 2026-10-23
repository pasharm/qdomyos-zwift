#!/bin/bash
# Test only (T-282, from T-255): feat/modern-ui after the master merge - "Tile size" (ui_zoom) in
# General UI Options, applied without a restart. The reference APK (apk-base: feat/modern-ui before
# the merge, the row is still "UI Zoom" in General Options) and the tested APK (apk-debug: the
# merge) go through the same steps: Tile size 60 + OK, back to the home page - the tile size is
# measured in the uiautomator dump, and the "Settings changed" restart question is looked for.
# The tested APK then: 80 + OK and the back key at once (the settings page stores its copy 500 ms
# later), 120 together with "Tiles Icons" off in one visit (no key of the home copy lost), and a
# restart (the values kept).
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
# tiles <shot>: the tile size in the dump of that shot
tiles() {
  echo "== $1 $(python3 .github/tilesize.py dumps/$1.xml 2>&1)" >> $STEPLOG
}
# conf: the stored keys of the test
conf() {
  echo "== conf ($1): $(adb shell "run-as $PKG grep -E '^(ui_zoom|theme_tile_icon_enabled|skipLocationServicesDialog)=' '$CONF' < /dev/null" | tr '\r\n' '  ')" >> $STEPLOG
}

# open_tile_size: Settings, General UI Options open, the Tile size field typed with <value>
# (the keyboard closed again); the OK button is left to the caller
open_tile_size() {
  goto_settings || return 1
  scroll_to '^General UI Options$' || return 1
  tap_ui '^General UI Options$' 700 1000
  sleep 4
  # the modern view puts its own rows first, Tile size is below the screen edge
  scroll_to '^Tile size:$' 6 || return 1
  tap_row '^Tile size:$' '^[0-9.]+$' || return 1
  sleep 2
  adb shell input keyevent KEYCODE_MOVE_END || true
  for i in 1 2 3 4 5 6; do adb shell input keyevent KEYCODE_DEL || true; done
  adb shell input text "$1" || true
  sleep 1
  hide_keyboard
  sleep 1
  dump
}
# after_back <shot>: the home page after leaving Settings - the restart question answered No
# (and logged), then the frame and the tile size
after_back() {
  sleep 3
  dump
  if [ -f ui.xml ] && grep -q 'Settings changed' ui.xml; then
    echo "== $1: restart question shown" >> $STEPLOG
    snap $1-question
    tap_ui '^(No|NO)$' || back "restart question"
    sleep 2
  else
    echo "== $1: no restart question" >> $STEPLOG
  fi
  shot $1
  tiles $1
}

# round <prefix>: 100 at start, then 60 + OK and back
round() {
  local s="$1"
  wait_tiles
  sleep 3
  shot $s-01-home-100
  tiles $s-01-home-100
  if open_tile_size 60; then
    tap_row '^Tile size:$' '^OK$'
    sleep 1
    snap $s-02-saved
    sleep 2
    back "settings page"
    after_back $s-03-home-60
  fi
  conf "$s 60"
}

# 1. Reference: master with the tile size rename, without the fix
install_apk apk-base/android-debug.apk
adb shell cmd location set-location-enabled true || true
start_fresh "skipLocationServicesDialog=true"
conf "b start, skip=true before"
round b
# what the reference needs to show 60: a restart
adb shell am force-stop $PKG || true
start_app
wait_tiles
shot b-04-restart
tiles b-04-restart

# 2. The tested APK
install_apk apk-debug/android-debug.apk
# The location reminder: skipped in the file, the GPS on - homeform.cpp resets it at the start,
# after the home page copy has read it; a tile change must not write the old value back
adb shell cmd location set-location-enabled true || true
start_fresh "skipLocationServicesDialog=true"
conf "a start, skip=true before"
round a

# 80 + OK and the back key in one adb call (well within the 500 ms of the settings copy)
if open_tile_size 80; then
  xy=$(row_xy '^Tile size:$' '^OK$')
  echo "quick: OK at $xy and back at once" >> $STEPLOG
  [ -n "$xy" ] && adb shell "input tap $xy; input keyevent KEYCODE_BACK"
  after_back a-04-home-80-quick
  conf "a 80 quick"
fi

# 120 and Tiles Icons off in the same visit
if open_tile_size 120; then
  tap_row '^Tile size:$' '^OK$'
  sleep 2
  if scroll_to '^UI Themes$' 20; then
    tap_ui '^UI Themes$'
    sleep 3
    # IndicatorOnlySwitch toggles only on its indicator at the right end of the row
    if scroll_to '^Tiles Icons$' 4 && xy=$(python3 .github/uiright.py ui.xml '^Tiles Icons$'); then
      echo "tap 'Tiles Icons' switch at $xy" >> $STEPLOG
      adb shell input tap $xy || true
    else
      echo "!! Tiles Icons switch NOT FOUND" >> $STEPLOG
    fi
    sleep 1
    shot a-05-themes
  fi
  back "settings page"
  after_back a-06-home-120-noicons
  sleep 2
  conf "a 120 no icons"
fi

# A restart: 120 and no icons kept
adb shell am force-stop $PKG || true
start_app
wait_tiles
shot a-07-restart
tiles a-07-restart
conf "a after restart"

# Back to 100 without a restart
if open_tile_size 100; then
  tap_row '^Tile size:$' '^OK$'
  sleep 2
  back "settings page"
  after_back a-08-home-100
  conf "a 100"
fi

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
