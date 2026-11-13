#!/bin/bash
# Test only (T-530): frames for the "before/after" image of the PR - the GPX page with a route selected.
# Before (base: origin/master 3f1945fe7): the map at a fixed zoom level 14 around the centre of the track, a
# long track (Box Hill, 16.8 km) does not fit. After (head: + T-530): the map fits the whole track with a
# margin of 24 px (GPXList.qml fitRoute).
# Cases <side><look><orientation>: side b/h, look c (classic) / m (modern, ui_modern=true), orientation
# p (portrait) / l (landscape: turned before the page is opened). In each: the page opened - the first route,
# Box Hill, is selected at once (ListView currentIndex 0 -> trainprogram_preview, GPXList.qml:409-417 and
# 187-192), frame 1; a tap on Govi to Hood (the shortest bundled route, 9.2 km) - frame 2; a tap on Box Hill
# again - frame 3 (a second tap on the selected row would open the route: GPXList.qml:212, 383).
# Checks: the selected route by the log (homeform::gpxpreview_open_clicked "<name>.gpx" after the tap) and, in
# the modern look, by the dump (the Open button on the row of the route, the km chip); the line of the route
# on the frame (t530_map.py: pixels of its colour, where, the gap to the light map area); no new QML message
# of GPXList.qml on the head side against the base.
. .github/lib.sh
. .github/qz.sh

QZDIR=/sdcard/Documents/QZ
LONG='Box Hill'
SHORT='Govi to Hood'

app_uid() {
  adb shell "su 0 stat -c %u /data/data/$PKG" < /dev/null 2>/dev/null | tr -d '\r'
}

# wipe_files: Documents/QZ of the previous side removed by the app uid while it is installed - files of an
# uninstalled app belong to another uid and bring the "previous installation" box on the GPX page (T-514,
# run 43015224696; the same as test/t534-emu)
wipe_files() {
  local uid
  uid=$(app_uid)
  if [ -n "$uid" ]; then
    adb shell am force-stop "$PKG" < /dev/null > /dev/null 2>&1
    adb shell "su $uid,$uid,9997 sh -c 'rm -rf $QZDIR'" < /dev/null >> "$STEPLOG" 2>&1
  fi
  adb uninstall "$PKG" < /dev/null > /dev/null 2>&1
  # files the app may not remove (run 43474879038: "training: Directory not empty", a file of uid 10190):
  # through MediaProvider, which forgets them with the files (test/t528-emu, run 43185579383)
  if adb shell "ls -d $QZDIR" < /dev/null > /dev/null 2>&1; then
    say "wipe: $QZDIR still there - delete through MediaProvider"
    adb shell "su 0 content delete --uri content://media/external/file --where \"_data LIKE '$QZDIR/%' OR _data LIKE '/storage/emulated/0/Documents/QZ/%'\"" \
      < /dev/null >> "$STEPLOG" 2>&1
    adb shell "su 0 rm -rf /storage/emulated/0/Documents/QZ" < /dev/null >> "$STEPLOG" 2>&1
  fi
  if adb shell "ls -d $QZDIR" < /dev/null > /dev/null 2>&1; then
    adb shell "su 0 ls -lnR $QZDIR" < /dev/null >> "$STEPLOG" 2>&1
    proves_nothing "$QZDIR left from the previous side (uid ${uid:-none})"
  fi
}

# rotate <0|1>: portrait or landscape, then a check by the root bounds of a dump that the app turned (T-487,
# lesson 2; test/t534-emu)
rotate() {
  local want=$1 b w h i
  adb shell settings put system accelerometer_rotation 0 < /dev/null > /dev/null 2>&1
  adb shell settings put system user_rotation "$want" < /dev/null > /dev/null 2>&1
  for i in 1 2 3 4 5 6; do
    emu_sleep 3
    dump || continue
    b=$(grep -o 'bounds="\[0,0\]\[[0-9]*,[0-9]*\]"' ui.xml | head -1 | tr -c '0-9\n' ' ')
    set -- $b
    w=$3; h=$4
    [ -n "$w" ] || continue
    if { [ "$want" = 1 ] && [ "$w" -gt "$h" ]; } || { [ "$want" = 0 ] && [ "$w" -lt "$h" ]; }; then
      say "rotation $want: ${w}x$h"
      SCR_W=$w; SCR_H=$h
      emu_sleep 3
      return 0
    fi
  done
  fail "rotation $want: the screen is ${w:-?}x${h:-?}"
  return 1
}

# log_lines: lines of full_logcat.txt now (the log of the run grows while it runs)
log_lines() { wc -l < full_logcat.txt | tr -d ' '; }

# selected_by_log <shot> <route> <from line>: the preview of that route asked after the line <from>
# (homeform.cpp gpxpreview_open_clicked: qDebug of the file URL; log_debug=true in qz.conf by put_conf)
selected_by_log() {
  local s=$1 route=$2 from=$3 i got
  for i in 1 2 3 4 5; do
    got=$(tail -n +"$from" full_logcat.txt | grep -a 'gpxpreview_open_clicked' | tail -n 1 | tr -d '\r')
    case $got in *"$route.gpx"*) break ;; esac
    emu_sleep 2
  done
  say "  log after line $from: ${got:-no gpxpreview_open_clicked}"
  case $got in
    *"$route.gpx"*) say "check $s: '$route' selected (gpxpreview_open_clicked in the log): OK" ;;
    *) fail "check $s: '$route' not the last gpxpreview_open_clicked after the tap" ;;
  esac
}

# open_beside <shot> <route>: modern look - the Open button on the card of the route (only the selected card
# has it, GPXList.qml:265), the centre of Open within the card height
open_beside() {
  local a o
  # --any: the real bounds - in landscape uifind took a card below the clipped list as covered (run 43474879038)
  a=$(uifind "dumps/$1.xml" "^$2\$" --any 2>/dev/null) || { fail "check $1: no card '$2' in the dump"; return 1; }
  o=$(uifind "dumps/$1.xml" '^Open$' --any 2>/dev/null) || { fail "check $1: no Open button in the dump"; return 1; }
  set -- "$1" "$2" $a $o
  # uifind gives 8 numbers each (x y checkable checked x1 y1 x2 y2): $4 - centre y of the name, ${12} - of Open
  if [ $(( $4 - ${12} )) -le 60 ] && [ $(( ${12} - $4 )) -le 60 ]; then
    say "check $1: Open on the card of '$2' (y $4 / ${12}): the route is selected: OK"
  else
    fail "check $1: Open not on the card of '$2' (y $4 / ${12})"
  fi
}

# line_of <shot>: the route line on a raw frame taken right after the shot (t530_map.py), the area without
# the list: side by side the right part of the screen, the modern look upright - under the list (the list is
# 0.4 of the page high) and above Other folders
line_of() {
  local s=$1 x1 y1 x2 y2 col of out
  frame "raw-$s" || { fail "$s: no raw frame"; return 1; }
  x2=$SCR_W; y2=$SCR_H
  if [ "$MODERN" = true ] && [ "$SCR_W" -lt "$SCR_H" ]; then
    x1=0
    # the list ends at ~0.54 H (0.4 of the page under the filter row, GPXList.qml:174): the selected card is in the
    # accent too
    y1=$(( SCR_H * 56 / 100 ))
    of=$(uifind "dumps/$s.xml" '^Other folders$' 2>/dev/null) && { set -- $of; y2=$6; }
  else
    # the list column ends at the right edge of the filter row: the "<-" button (classic; its right edge 815,
    # the map from 822 - frame h-4-after of run 43462330183) or "Parent folder" (modern); not found - 0.4 W
    x1=$(( SCR_W * 40 / 100 ))
    if [ "$MODERN" = true ]; then of='^Parent folder$'; else of='^←$'; fi
    of=$(uifind "dumps/$s.xml" "$of" 2>/dev/null) && { set -- $of; x1=$(( $7 + 6 )); }
    y1=252
  fi
  if [ "$MODERN" = true ]; then col=B69DF8,6444BE; else col=red; fi
  out=$("$EMU_PY" .github/t530_map.py "raw-$s" "$x1" "$y1" "$x2" "$y2" "$col")
  rm -f "raw-$s"
  say "  map $s: area $x1 $y1 $x2 $y2: $out"
  set -- $out
  if [ "${2:-0}" -ge 200 ]; then
    say "check $s: the route line on the map ($2 px of $col): OK"
  else
    fail "check $s: no route line on the frame (${2:-?} px of $col)"
  fi
}

# tap_row_classic <n> <route>: the classic rows have no names in the dump (GPXList.qml:355 Text in a
# clipped Item) - the row n by its place: 40 dp = 140 px rows on the CI Nexus 6 right under the filter row,
# whose bottom is the bottom of its "<-" button (GPXList.qml:312, 344)
tap_row_classic() {
  local n=$1 route=$2 y
  dump
  if ! find_ui '^←$'; then
    fail "classic: the '<-' button of the filter row not on the screen"
    return 1
  fi
  set -- "$1" "$2" $EMU_AT
  # ${10} - the bottom of the button (x y checkable checked x1 y1 x2 y2 after the two arguments)
  y=$(( ${10} + 70 + (n - 1) * 140 ))
  say "tap classic row $n ($route) at 200 $y"
  adb shell input tap 200 "$y" < /dev/null > /dev/null 2>&1
}

# pick <shot> <route> <row>: the route tapped (modern: the card by its name, the km chip as the landing;
# classic: the row by its place), then 3 s for the tiles, a still screen, the frame and its checks
pick() {
  local s=$1 route=$2 n=$3 from
  from=$(log_lines)
  if [ "$MODERN" = true ]; then
    # the accessibility click (Accessible.onPressAction -> gpxCard.activate, GPXList.qml:224) straight by the
    # driver - the way to the state under test, not the action: the list clips the cards, and tap_ui refused
    # Govi to Hood upright ("only 28 px on the screen") and took the km chip as covered in landscape (run
    # 43474879038); the selection is proved by the log, the Open button and the km chip after it
    a11y_build || { fail "$s: no a11y driver"; return 1; }
    drv "pick-$s" "click=$route" "sleep:1000"
    if grep -q "returned true" "drv/pick-$s.txt"; then
      say "outcome 'pick $route': a11y click returned true"
    else
      fail "$s: the accessibility click on '$route' did not work"
      return 1
    fi
  else
    tap_row_classic "$n" "$route" || return 1
  fi
  frame_route "$s" "$route" "$from"
}

# frame_route <shot> <route> <from line>: the frame of the selected route and its checks
frame_route() {
  local s=$1 route=$2 from=$3 km
  emu_sleep 3
  still
  shot "$s"
  line_of "$s"
  selected_by_log "$s" "$route" "$from"
  if [ "$MODERN" = true ]; then
    open_beside "$s" "$route"
    if [ "$route" = "$LONG" ]; then km='^16\.[0-9] km$'; else km='^9\.[0-9] km$'; fi
    if [ "$(uifind "dumps/$s.xml" --count "$km" --any 2>/dev/null)" -ge 1 ] 2>/dev/null; then
      say "check $s: the km chip of '$route' ($km): OK"
    else
      fail "check $s: no km chip '$km' of '$route' in the dump"
    fi
  else
    # the distance text over the map (GPXList.qml:542) - its node, if Qt gives one
    say "  classic distance text: $(uifind "dumps/$s.xml" '^Distance .*' --name --any 2>/dev/null || echo 'no node')"
  fi
  expect "$s" '^Other folders$' 'still the GPX page (the route not opened)'
}

# no_restore <case>: the restore question master asks on the GPX page of a fresh install too ("Restore files",
# run 43474879038: over the frames of every case) - answered No; not shown in 15 s - on
QUESTION_RX='(?s).*previous installation.*'
no_restore() {
  if ! wait_ui "$QUESTION_RX" 15 --any; then
    near question "$1: no restore question on the GPX page"
    return 0
  fi
  if find_ui '^&?No$'; then
    set -- "$1" $EMU_AT
    say "restore question: No at $2 $3"
    adb shell input tap "$2" "$3" < /dev/null > /dev/null 2>&1
  else
    fail "$1: the restore question without a No ($EMU_WHY)"
    return 1
  fi
  if wait_gone "$QUESTION_RX" 15; then
    say "outcome 'No': the question closed"
  else
    fail "$1: the restore question still there after No"
    return 1
  fi
}

# gpx <case> <modern> <landscape>: the page, Box Hill at once, Govi to Hood, Box Hill again
gpx() {
  local c=$1 from land
  MODERN=$2
  start_case "$c" ui_modern="$MODERN" fakedevice_treadmill=true || return 1
  SCR_W=1440; SCR_H=2560
  if [ "$3" = 1 ]; then
    rotate 1 || { rotate 0; return 1; }
  else
    rotate 0
  fi
  from=$(log_lines)
  say "== $c: GPX page"
  # landing: Other folders, or No of the restore question at once (modern: a popup over the page, Other folders
  # stays in the dump - two matches would fail; test/t528-emu)
  if [ "$MODERN" = true ]; then land='^&?No$'; else land='^Other folders$|^&?No$'; fi
  if open_drawer '^Open GPX$' && tap_ui '^Open GPX$' "$land" && no_restore "$c"; then
    frame_route "$c-1-long-open" "$LONG" "$from"
    # Box Hill again only after Govi to Hood is selected: a tap on the selected row opens the route
    pick "$c-2-short" "$SHORT" 4 && pick "$c-3-long" "$LONG" 1
  fi
  back_to "$HOME_RX" 20
  [ "$3" = 1 ] && rotate 0
  return 0
}

# qml_side: the messages of GPXList.qml by side (pid lines of start_case, the 3rd field of threadtime), the
# text without time, pid and the line number (the change moves the lines below it); a message of the head side the base side has not is the change's
qml_side() {
  local side=$1 pid
  : > "qml_$side.txt"
  for pid in $(grep -a "^pid $side" "$STEPLOG" | cut -d' ' -f3); do
    awk -v p="$pid" '$3 == p' full_logcat.txt | grep -a 'GPXList.qml' | sed 's/^.*GPXList\.qml:[0-9]*:\{0,1\}[0-9]*:\{0,1\} */GPXList.qml: /' | tr -d '\r' >> "qml_$side.txt"
  done
  sort -u -o "qml_$side.txt" "qml_$side.txt"
}
qml_compare() {
  logcat_stop
  qml_side b
  qml_side h
  say "== GPXList.qml messages: base $(wc -l < qml_b.txt) kinds, head $(wc -l < qml_h.txt) kinds"
  cat qml_b.txt | sed 's/^/  b: /' >> "$STEPLOG"
  cat qml_h.txt | sed 's/^/  h: /' >> "$STEPLOG"
  comm -13 qml_b.txt qml_h.txt > qml_new.txt
  if ! grep -a -q '^pid h' "$STEPLOG"; then
    fail "check qml: no head pid in steps.log - not checked"
  elif [ -s qml_new.txt ]; then
    sed 's/^/  new: /' qml_new.txt >> "$STEPLOG"
    fail "check qml: GPXList.qml messages on the head side the base has not ($(wc -l < qml_new.txt))"
  else
    say "check qml: no GPXList.qml message on the head side the base has not: OK"
  fi
}

emu_init
logcat_start

for side in b h; do
  if [ "$side" = b ]; then apk=apk-base/android-debug.apk; else apk=apk-head/android-debug.apk; fi
  side_on "$side" "$apk" || continue
  say "== $side: start"
  wipe_files
  install_apk "$apk"
  gpx "${side}cp" false 0
  gpx "${side}mp" true 0
  gpx "${side}cl" false 1
  gpx "${side}ml" true 1
done

qml_compare
finish
