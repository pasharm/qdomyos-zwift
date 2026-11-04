#!/bin/bash
# Test only (T-091): the Start/Stop row does not come to rest cut on the home page of the classic
# look. Starts an already built APK (test/t091: home/start-row-snap with a QZ-SNAP trace in
# Home.qml) on the emulator with log_debug on and a fake treadmill, so the home page has tiles.
# After every movement the trace logs where the scroll came to rest, measured on the tiles:
# steps.log checks each rest and marks a miss with "!!". Between the top and the first row of
# tiles a rest is the top, the Start/Stop row at the top of the shown area or the first row with
# the gap between rows above it; deeper in the list the list stays where the movement left it.
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
conf_with

dump() {
  rm -f ui.xml
  timeout 25 adb shell uiautomator dump /data/local/tmp/ui.xml > /dev/null 2>&1 || true
  adb pull /data/local/tmp/ui.xml ui.xml > /dev/null 2>&1 || true
}
# Another window over the app (a hanging launcher, Health Connect, QZ's own permission
# dialog): closed before every shot, logged in steps.log
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
restart_with() {
  echo "== restart: $*" >> $STEPLOG
  adb shell am force-stop $PKG || true
  sleep 2
  conf_with "$@"
  adb shell am start -n $PKG/$PKG.CustomQtActivity
  sleep 20
  wait_tiles
}
step() { echo "[$1] expected: $2" >> $STEPLOG; }
drag_up() { adb shell input swipe 700 1800 700 $((1800 - $1)) 1500 || true; sleep 3; }
drag_down() { adb shell input swipe 700 900 700 $((900 + $1)) 1500 || true; sleep 3; }
# A short quick swipe: a small flick
flick_up() { adb shell input swipe 700 1800 700 $((1800 - $1)) 120 || true; sleep 4; }
to_end() { local i; for i in 1 2 3 4 5 6; do adb shell input swipe 700 2000 700 600 150 || true; done; sleep 4; }
scroll_top() { local i; for i in 1 2 3 4 5; do adb shell input swipe 700 800 700 2200 150 || true; done; sleep 3; }

# A mark in logcat before each movement: the check reads the trace after its own mark from the
# log buffer itself (adb logcat -d). Reading the recording file lost lines: adb writes it with a
# buffer, and a rest logged a second before the check was not in it yet (run 41739939135)
MARK_N=0
mark() { MARK_N=$((MARK_N + 1)); MARK="t091-mark-$MARK_N"; adb shell log -t QZ-STEP "$MARK" || true; }
since_mark() { adb logcat -d 2>/dev/null | awk -v m="$MARK" 'found { print } index($0, m) { found = 1 }'; }
# rest_is zone|deep: the last rest after the mark and the end of the movement before it.
#   zone: the movement ended between the top and the first row of tiles: the rest is the top, the
#         Start/Stop row at the top of the shown area, the first row with the gap between rows
#         above it, or the end of the list; the toolbar whole or gone.
#   deep: the movement ended deeper: the list stays where the movement left it (rest = end).
rest_is() {
  local want=$1 seg endl restl verdict
  sleep 1
  seg=$(since_mark)
  # API 35 once gave no rest from logcat -d that the recording had (run 41747112353, the flick):
  # then the recording after the same mark
  if ! echo "$seg" | grep -q "QZ-SNAP rest"; then
    sleep 2
    seg=$(awk -v m="$MARK" 'found { print } index($0, m) { found = 1 }' full_logcat.txt)
  fi
  restl=$(echo "$seg" | grep "QZ-SNAP rest" | tail -1 | sed 's/.*QZ-SNAP rest //')
  endl=$(echo "$seg" | grep "QZ-SNAP end" | tail -1 | sed 's/.*QZ-SNAP end //')
  if [ -z "$restl" ]; then
    echo "!! no rest logged after the step (no movement ended)" >> $STEPLOG
    return
  fi
  verdict=$(printf '%s\n%s\n' "$endl" "$restl" | awk -v want="$want" '
    function abs(x) { return x < 0 ? -x : x }
    { for (i = 1; i <= NF; i++) { split($i, kv, "="); v[NR, kv[1]] = kv[2] } }
    END {
      es = v[1, "s"] + 0
      s = v[2, "s"] + 0; bar = v[2, "bar"] + 0; h = v[2, "h"] + 0; maxS = v[2, "maxS"] + 0
      first = v[2, "first"] + 0; startRow = v[2, "startRow"] + 0
      tileGap = v[2, "tileGap"] + 0; rowGap = v[2, "rowGap"] + 0
      if (!(bar <= 0.5 || abs(bar - h) <= 0.5)) { print "!! toolbar half shown (bar " bar " of " h ")"; exit }
      if (want == "deep") {
        if (es < first - 1) print "!! the movement ended in the top zone (end s " es ", first " first "): not a deep step"
        else if (abs(s - es) <= 1 || abs(s - maxS) <= 1) print "stays where it stopped: OK"
        else print "!! moved after the movement deep in the list (end s " es ", rest s " s ")"
        exit
      }
      if (maxS > 0 && abs(es - maxS) <= 1 && abs(s - maxS) > 1) print "!! went back from the end of the list (end s " es ", rest s " s ")"
      else if (s <= 0.5) print "top: OK"
      else if (abs(s - maxS) <= 1) print "end of the list: OK"
      else if (abs(startRow) <= 1) print "Start/Stop row at the top: OK"
      else if (abs(s - first) <= 1 && abs(tileGap - rowGap) <= 1.5) print "first row with the gap above it: OK"
      else if (s > first + 1) print "!! the movement ended deeper (rest s " s ", first " first "): not a zone step"
      else print "!! cut in the top zone (s " s ", first " first ", startRow " startRow ", tileGap " tileGap ")"
    }')
  echo "  end:  $endl" >> $STEPLOG
  echo "  rest: $restl" >> $STEPLOG
  echo "  -> $verdict" >> $STEPLOG
}
# One movement of the list, then its rest checked: check <zone|deep> <name> <expected> <command...>
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

# 1. From the top, drags of different lengths (px; about 3.5 px per dp): the row of the toolbar
# room (master), then the Start/Stop row zone, then deeper
check zone top-120 "inside the toolbar room: back to the top or the toolbar gone with the list (master)" drag_up 120
scroll_top
check zone top-300 "the Start/Stop row zone: the row at the top under the status bar or the first row" drag_up 300
scroll_top
check zone top-450 "the Start/Stop row zone: the row at the top or the first row" drag_up 450
scroll_top
check zone top-650 "near the first row: the first row with the gap above it" drag_up 650
scroll_top
check deep top-1100 "deeper: the list stays where the drag left it, a row may be cut (as in master)" drag_up 1100
check deep deeper-300 "300 px further: stays where it stopped" drag_up 300

# 2. Back up from deep in the list into the zone, the toolbar shown again
check deep back-250 "250 px down deep in the list: toolbar back, the list where the drag left it" drag_down 250
check zone back-850 "850 px down: into the zone with the toolbar shown (s below 143) - the top or the first row under the toolbar" drag_down 850
scroll_top

# 3. Series and small flicks near the top (T-052: a series of short gestures was the defect the
# emulator did not catch)
step series "from the top, two 200 px drags in a row"
mark
drag_up 200
drag_up 200
rest_is zone
shot t-series
scroll_top
check zone flick-small "a small quick flick from the top: the rest whole (top, the row or the first row)" flick_up 250
scroll_top
check zone flick-small-2 "a slightly longer quick flick from the top" flick_up 400
scroll_top
check deep flick "a fast flick: the glide ends where it ends (deep) or at the end" adb shell input swipe 700 1900 700 1200 120
check zone end "the end of the list" to_end

# 4. Moving the tiles scrolls the grid by contentY: no snap then, and the lock works as before
scroll_top
step lock "tile lock: no Start/Stop row, the 30 gap under the toolbar; a scroll there does not snap (no rest logged)"
tap $LOCK "lock tiles"
sleep 3
mark
adb shell input swipe 1400 1800 1400 1100 800 || true
sleep 3
if since_mark | grep -q "QZ-SNAP rest"; then
  echo "  -> rest logged while locked (look at it)" >> $STEPLOG
else
  echo "  -> no rest while the tiles are moved: OK" >> $STEPLOG
fi
shot t-lock
tap $LOCK "unlock tiles"
sleep 3
shot t-unlock

# 5. Sideways: the same zone
scroll_top
adb shell settings put system accelerometer_rotation 0 || true
adb shell settings put system user_rotation 1 || true
sleep 10
step landscape "sideways, 400 px from the top: the zone rules"
mark
adb shell input swipe 1200 1200 1200 800 1500 || true
sleep 3
rest_is zone
shot t-landscape
adb shell settings put system user_rotation 0 || true
sleep 10

# 6. Top bar off: no Start/Stop row, the 30 gap under the toolbar
restart_with top_bar_enabled=false
check zone no-top-bar-150 "top bar off, 150 px: the top, the toolbar gone with the list or the first row" drag_up 150
scroll_top
check zone no-top-bar-230 "top bar off, 230 px (s between 48 and 71): the 30 gap at the top or the first row with the row gap" drag_up 230
scroll_top
check zone no-top-bar-250 "top bar off, 250 px: the same zone" drag_up 250
scroll_top
check deep no-top-bar-1100 "top bar off, deeper: stays where it stopped" drag_up 1100

# 7. A list a little longer than the page: 7 tiles off, 17 -> 10, 5 rows, maxS about 59 on API 30
# (35 on API 35): between the toolbar height and the first row. At its end it must stay at the end
# (the last row in view), not go back to the Start/Stop row (subagent review of the PR text, 04.11)
restart_with tile_calories_enabled=false tile_odometer_enabled=false tile_pace_enabled=false tile_watt_enabled=false tile_avgwatt_enabled=false tile_ftp_enabled=false tile_jouls_enabled=false
check zone just-over-end "a list just over the page, swipes to its end: the end, the last row in full view" to_end
check zone just-over-back "40 px back down from the end: the end again, the toolbar room (master) or the Start/Stop row" drag_down 40
scroll_top
check zone just-over-250 "250 px from the top: the end or the Start/Stop row, never back from the end" drag_up 250

# 8. A list that fits: nothing snaps away from the top
restart_with ui_zoom=50
step short-list "tiles fit: a drag springs back to the top"
mark
drag_up 400
rest_is zone
shot t-short-list

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
# Home.qml:580 (the tile delegate, y: myValue.bottom) and main.qml stackView.currentItem.title warn
# in master as well (run 41739939135): only the lines around the change, 440-520 of this build
grep -E "Home[.]qml:(4[4-9][0-9]|5[01][0-9]):|FATAL EXCEPTION" full_logcat.txt | grep -vE "qml: |QZ-" > t091-errors.txt || true
head -40 t091-errors.txt | sed 's/^/!! /' >> $STEPLOG
[ -s t091-errors.txt ] || echo "no QML error of the change, no crash: OK" >> $STEPLOG
MISSES=$(grep -c '^  -> !!\|^!!' $STEPLOG)
echo "misses (lines with !!): $MISSES" >> $STEPLOG
echo "== steps"; cat $STEPLOG
