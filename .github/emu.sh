#!/bin/bash
# Test only (T-091): snap tiles to rows on the home page of the classic look. Starts an already
# built APK (test/t091: home/tile-snap with a QZ-SNAP trace in Home.qml) on the emulator with
# log_debug on and a fake treadmill, so the home page has tiles. After every movement the trace
# logs where the scroll came to rest, measured on the tiles: steps.log checks each rest against
# what the setting promises and marks a miss with "!!".
PKG=org.cagnulen.qdomyoszwift
LOG_DEBUG=${LOG_DEBUG:-true}
STEPLOG=steps.log
: > $STEPLOG
mkdir -p dumps

adb install apk-debug/android-debug.apk
if ! adb shell pm path $PKG > /dev/null 2>&1; then
  echo "!! APK NOT INSTALLED - the run proves nothing" >> $STEPLOG
  cat $STEPLOG
  exit 1
fi
# Location on: without it QZ shows "Permissions Required" over every screen (API < 30 images)
adb shell settings put secure location_providers_allowed +gps || true
adb shell settings put secure location_providers_allowed +network || true
adb shell settings put secure location_mode 3 || true
for p in READ_EXTERNAL_STORAGE WRITE_EXTERNAL_STORAGE ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION BLUETOOTH_ADVERTISE BLUETOOTH_CONNECT BLUETOOTH_SCAN POST_NOTIFICATIONS; do
  adb shell pm grant $PKG android.permission.$p || true
done
adb shell appops set $PKG MANAGE_EXTERNAL_STORAGE allow || true
for p in EXERCISE DISTANCE TOTAL_CALORIES_BURNED HEART_RATE POWER SPEED CYCLING_PEDALING_CADENCE ELEVATION_GAINED STEPS STEPS_CADENCE HEART_RATE_VARIABILITY; do
  adb shell pm grant $PKG android.permission.health.WRITE_$p || true
done
adb shell cmd uimode night no || true
# No error dialogs of other apps (the launcher hangs on the slow CI machine); an ANR still
# reaches logcat and the end of steps.log
adb shell settings put global hide_error_dialogs 1 || true

conf_with() {
  { printf '[General]\nlog_debug=%s\nconfirm_stop_workout=true\nfakedevice_treadmill=true\nskipLocationServicesDialog=true\n' "$LOG_DEBUG"
    for kv in "$@"; do echo "$kv"; done; } > qz.conf
  adb push qz.conf /data/local/tmp/qz.conf
  adb shell "run-as $PKG mkdir -p 'files/.config/Roberto Viola'"
  adb shell "run-as $PKG cp /data/local/tmp/qz.conf 'files/.config/Roberto Viola/qDomyos-Zwift.conf' < /dev/null"
}
# The setting is not in the conf: the default (off) is what the first steps check
conf_with

dump() {
  rm -f ui.xml
  timeout 25 adb shell uiautomator dump /data/local/tmp/ui.xml > /dev/null 2>&1 || true
  adb pull /data/local/tmp/ui.xml ui.xml > /dev/null 2>&1 || true
}
# Another window over the app (a hanging launcher, Health Connect, QZ's own permission
# dialog): closed before every step, logged in steps.log
ensure_app() {
  local i pkg xy
  for i in 1 2 3; do
    dump
    [ -f ui.xml ] || return 0
    pkg=$(python3 .github/uitap.py ui.xml --package)
    if [ "$pkg" = "$PKG" ] && grep -qE "Permissions Required|Reminder Preference" ui.xml && xy=$(python3 .github/uitap.py ui.xml '^No$'); then
      echo "!! QZ permission dialog: No at $xy" >> $STEPLOG
      adb shell input tap $xy || true
      sleep 3
      continue
    fi
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
  if [ "$1" = "01-healthconnect" ]; then rm -f ui.xml; else ensure_app; fi
  echo "-- shot $1" >> $STEPLOG
  adb shell screencap -p /data/local/tmp/$1.png || true
  adb pull /data/local/tmp/$1.png || true
  [ -f ui.xml ] || dump
  [ -f ui.xml ] && cp ui.xml dumps/$1.xml
}
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
scroll_to() {
  local i
  for i in $(seq 1 25); do
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
# The checked state of the control with this label in ui.xml: true, false or none
checked_of() {
  python3 - "$1" <<'EOF'
import re, sys
import xml.etree.ElementTree as ET
rx = re.compile(sys.argv[1], re.I)
try:
    root = ET.parse("ui.xml").getroot()
except (ET.ParseError, OSError):
    print("none"); sys.exit(0)
for node in root.iter("node"):
    labels = [node.get("text") or "", node.get("content-desc") or ""]
    if any(l and rx.fullmatch(l.strip()) for l in labels):
        print(node.get("checked") or "none"); sys.exit(0)
print("none")
EOF
}
back() { echo "back ($1)" >> $STEPLOG; adb shell input keyevent KEYCODE_BACK || true; }
tap() { ensure_app; echo "tap $1 $2 ($3)" >> $STEPLOG; adb shell input tap $1 $2 || true; }
# Nexus 6: 1440x2560 px, 3.5 px per dp
LOCK="1187 168"        # tile lock on the home page

adb logcat -c || true
adb logcat > full_logcat.txt 2>/dev/null &
LOGCAT_PID=$!
adb shell am start -n $PKG/$PKG.CustomQtActivity
sleep 20
shot 01-healthconnect
if [ -f ui.xml ] && [ "$(python3 .github/uitap.py ui.xml --package)" = "$PKG" ]; then
  echo "health connect screen not shown: no back key" >> $STEPLOG
else
  back "health connect"
fi
sleep 30
shot 04-home

wait_tiles() {
  local i
  # The fake treadmill comes after the first search ends: at most 3 min
  for i in $(seq 1 18); do
    dump
    if [ -f ui.xml ] && grep -q 'content-desc="Speed' ui.xml; then
      echo "tiles shown after $i looks" >> $STEPLOG; return 0
    fi
    sleep 10
  done
  echo "!! tiles NOT shown - the run proves nothing" >> $STEPLOG
  echo "== steps"; cat $STEPLOG
  exit 1
}
start_app() {
  adb shell am start -n $PKG/$PKG.CustomQtActivity
  sleep 20
  wait_tiles
}
restart_with() {
  echo "== restart: $*" >> $STEPLOG
  adb shell am force-stop $PKG || true
  sleep 2
  conf_with "$@"
  start_app
}
# The same app settings as they are (a switch flipped in the app stays)
restart_keep() {
  echo "== restart, settings kept" >> $STEPLOG
  adb shell am force-stop $PKG || true
  sleep 2
  start_app
}
step() { echo "[$1] expected: $2" >> $STEPLOG; }
drag_up() { adb shell input swipe 700 1800 700 $((1800 - $1)) 1500 || true; sleep 3; }
drag_down() { adb shell input swipe 700 900 700 $((900 + $1)) 1500 || true; sleep 3; }
to_end() { local i; for i in 1 2 3 4 5 6; do adb shell input swipe 700 2000 700 600 150 || true; done; sleep 4; }
scroll_top() { local i; for i in 1 2 3 4 5; do adb shell input swipe 700 800 700 2200 150 || true; done; sleep 3; }

# Rests logged so far: a step reads only the rest that came after its mark
mark() { REST_N=$(grep -c "QZ-SNAP rest" full_logcat.txt); }
# rest_is on|off: the last rest after the mark, and whether it is what the setting promises.
# on: at the top, the Start/Stop row at the top of the shown area, a row of tiles with the gap
# between rows above it, or the end of the list - and the toolbar whole or gone, not half shown.
# off: the setting is off (where it rests is the user's scroll)
rest_is() {
  local want=$1 n line verdict
  sleep 1
  n=$(grep -c "QZ-SNAP rest" full_logcat.txt)
  if [ "$n" -le "$REST_N" ]; then
    echo "!! no rest logged after the step (no movement ended)" >> $STEPLOG
    return
  fi
  line=$(grep "QZ-SNAP rest" full_logcat.txt | tail -1 | sed 's/.*QZ-SNAP rest //')
  verdict=$(echo "$line" | awk -v want="$want" '
    function abs(x) { return x < 0 ? -x : x }
    { for (i = 1; i <= NF; i++) { split($i, kv, "="); v[kv[1]] = kv[2] } }
    END {
      s = v["s"] + 0; bar = v["bar"] + 0; h = v["h"] + 0; maxS = v["maxS"] + 0
      startRow = v["startRow"] + 0; tileGap = v["tileGap"] + 0; rowGap = v["rowGap"] + 0
      if (want == "off") {
        print (v["snap"] == "false" ? "snap off: OK" : "!! snap=" v["snap"] ", expected off"); exit
      }
      if (v["snap"] != "true") { print "!! snap=" v["snap"] ", expected on"; exit }
      if (!(bar <= 0.5 || abs(bar - h) <= 0.5)) { print "!! toolbar half shown (bar " bar " of " h ")"; exit }
      if (s <= 0.5) print "top: OK"
      else if (abs(s - maxS) <= 1) print "end of the list: OK"
      else if (abs(startRow) <= 1) print "Start/Stop row at the top: OK"
      else if (abs(tileGap - rowGap) <= 1.5) print "row with the gap above it: OK"
      else print "!! NOT on a row (tileGap " tileGap ", rowGap " rowGap ", startRow " startRow ")"
    }')
  echo "  rest: $line" >> $STEPLOG
  echo "  -> $verdict" >> $STEPLOG
}
# One movement of the list, then its rest checked: check <on|off> <name> <expected> <command...>
check() {
  local want=$1 name=$2 what=$3
  shift 3
  step "$name" "$what"
  mark
  "$@"
  rest_is "$want"
  shot "t-$name"
}

echo "== API $(adb shell getprop ro.build.version.sdk | tr -d '\r')" >> $STEPLOG
wait_tiles
shot t-00-top

# 1. Off by default: the scroll stays where the drag left it, as in master
check off off-drag "setting off (default): the list stays where the drag left it, a row may be cut" drag_up 1100
scroll_top

# 2. On in the settings, while the app runs: the home page takes it at once (its own Settings
# copy gets it through window.tileSettingChanged), no restart
step switch "Settings - General UI Options - Snap tiles to rows: off, a tap turns it on"
adb shell input swipe 2 1200 900 1200 300 || true
sleep 3
tap_drawer '^Settings$' 400 900
sleep 8
shot t-01-settings
SWITCH_ON=false
if scroll_to '^General UI Options$' && tap_ui '^General UI Options$'; then
  sleep 3
  if scroll_to '^Snap tiles to rows$'; then
    echo "  switch before the tap: $(checked_of '^Snap tiles to rows$')" >> $STEPLOG
    xy=$(python3 .github/uitap.py ui.xml '^Snap tiles to rows$')
    y=${xy#* }
    # IndicatorOnlySwitch: only the switch at the right end of the row takes the tap
    tap 1330 "$y" "the switch of Snap tiles to rows"
    sleep 2
    dump
    state=$(checked_of '^Snap tiles to rows$')
    echo "  switch after the tap: $state" >> $STEPLOG
    [ "$state" = "true" ] && SWITCH_ON=true
    shot t-02-switch-on
  fi
fi
back "settings"
sleep 4
if [ "$SWITCH_ON" != "true" ]; then
  echo "!! the switch was not turned on in the app: on by the conf instead, the live change is NOT checked" >> $STEPLOG
  restart_with ui_tile_snap=true
fi
shot t-03-home-back
scroll_top

# 3. On: each kind of rest. The cell is 130 dp (455 px), the toolbar about 56 dp; the drags are
# of different lengths so that they stop at different places within a row
check on drag-1100 "a row of tiles at the top under the status bar, the gap between rows above it" drag_up 1100
check on drag-300-more "300 px further: the next or the same row, never half a row" drag_up 300
check on drag-200-more "200 px further: a row" drag_up 200
check on back-150 "150 px down deep in the list: toolbar back or gone (whole), a row at the top of the shown area" drag_down 150
check on back-250 "250 px down: toolbar shown, a row with the gap below the toolbar" drag_down 250
scroll_top
check on top-400 "400 px from the top: the Start/Stop row at the top under the status bar, or the first row" drag_up 400
scroll_top
check on top-650 "650 px from the top: the first row (with the gap) or the Start/Stop row" drag_up 650
scroll_top
check on top-120 "120 px from the top (inside the toolbar room): back to the top or the toolbar gone with the list" drag_up 120
scroll_top
check on flick "a fast flick: the glide ends on a row" adb shell input swipe 700 1900 700 1200 120
check on end "the end of the list: the last row in full view" to_end
check on near-end "200 px back from the end: a row or the end again" drag_down 200

# 4. Moving the tiles scrolls the grid by contentY: no snap then, and the lock works as before
scroll_top
step lock "tile lock: no Start/Stop row, the 30 gap under the toolbar; a scroll there does not snap (no rest logged)"
tap $LOCK "lock tiles"
sleep 3
mark
adb shell input swipe 1400 1800 1400 1100 800 || true
sleep 3
n=$(grep -c "QZ-SNAP rest" full_logcat.txt)
[ "$n" -le "$REST_N" ] && echo "  -> no rest while the tiles are moved: OK" >> $STEPLOG || echo "  -> rest logged while locked (look at it)" >> $STEPLOG
shot t-lock
tap $LOCK "unlock tiles"
sleep 3
shot t-unlock

# 5. The switch is kept: after a restart of the app it is still on
if [ "$SWITCH_ON" = "true" ]; then
  restart_keep
  check on kept "after a restart the setting is still on: a row" drag_up 1100
fi

# 6. Sideways: the same rows
scroll_top
adb shell settings put system accelerometer_rotation 0 || true
adb shell settings put system user_rotation 1 || true
sleep 10
step landscape "sideways: a drag ends on a row"
mark
adb shell input swipe 1200 1200 1200 500 1500 || true
sleep 3
rest_is on
shot t-landscape
adb shell settings put system user_rotation 0 || true
sleep 10

# 7. Top bar off: no Start/Stop row, the 30 gap under the toolbar
restart_with ui_tile_snap=true top_bar_enabled=false
check on no-top-bar "top bar off: a row" drag_up 1100
scroll_top
check on no-top-bar-short "top bar off, 150 px from the top: back to the top (no rest inside the toolbar room)" drag_up 150

# 8. A list just over the screen and one that fits. In T-052 60 % did not overflow the screen:
# the trace gives maxS of each, the one with maxS under the toolbar height is the case of a list
# longer than the page by less than the toolbar (the toolbar then goes only as far as the list)
for z in 60 65 70; do
  restart_with ui_tile_snap=true ui_zoom=$z
  check on just-over-$z "tiles $z %: the end reachable, the last row in full view" to_end
  check on just-over-$z-back "tiles $z %: 150 px back from the end - a row, the end or the top" drag_down 150
done
restart_with ui_tile_snap=true ui_zoom=50
step short-list "tiles fit: a drag springs back, nothing snaps away from the top"
mark
drag_up 400
rest_is on
shot t-short-list

# 9. Off again by the conf: as in master
restart_with ui_tile_snap=false
check off off-again "off: the list stays where the drag left it" drag_up 1100

adb shell pidof $PKG > /dev/null && echo "app alive at the end: OK" >> $STEPLOG || echo "!! app not running at the end" >> $STEPLOG
kill $LOGCAT_PID 2>/dev/null || true
wait $LOGCAT_PID 2>/dev/null || true
adb logcat -d > end_logcat.txt || true
if [ "$(wc -l < full_logcat.txt)" -lt "$(wc -l < end_logcat.txt)" ]; then
  echo "!! logcat recording shorter than the dump at the end: the dump is kept" >> $STEPLOG
  mv end_logcat.txt full_logcat.txt
else
  rm -f end_logcat.txt
fi
mkdir -p qz-logs
adb shell 'ls -la /sdcard/Documents/QZ/ 2>&1' > qz-logs/listing.txt || true
grep -E "ANR in" full_logcat.txt | sed 's/^/!! /' >> $STEPLOG || true
echo "== all snap traces"; grep "QZ-SNAP" full_logcat.txt | sed 's/.*QZ-SNAP/QZ-SNAP/' || true
echo "== QML errors of the change (none expected)"
# settings.qml has warnings of its own in master: only the lines of the new switch (about 7360-7390)
grep -E "(main|Home)[.]qml:[0-9]+|settings[.]qml:73[5-9][0-9]|tile_snap|FATAL EXCEPTION" full_logcat.txt | grep -vE "qml: |QZ-|rootItem is not defined|appModel is not defined|onFoo properties|onTrainingProgramIntervalSoundRequested" > t091-errors.txt || true
head -40 t091-errors.txt | sed 's/^/!! /' >> $STEPLOG
[ -s t091-errors.txt ] || echo "no QML error, no crash: OK" >> $STEPLOG
MISSES=$(grep -c '^  -> !!\|^!!' $STEPLOG)
echo "misses (lines with !!): $MISSES" >> $STEPLOG
echo "== steps"; cat $STEPLOG
