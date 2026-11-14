#!/bin/bash
# Test only (T-529): rounded corners of the map on the GPX page, modern look.
# Base: the build of the input base (the map square) - first feat/modern-beta de352844c, for the PR the clean
# origin/master c9426b7cd (test/t529-master). Head: the same + T-529 (GPXList.qml: a frame in the page colour,
# ui.bg, over the map with an inner radius of 16 dp; the map notice above it) - for the PR test/t529-pr.
# Cases <side><case>: mp - modern upright, light; ml - modern landscape (turned before the page is opened);
# md - modern upright, dark (ui_theme_mode=dark: the frame takes the dark ui.bg); cp - classic upright (the
# frame is visible: window.ui.modern only - square on both sides).
# In each: the page opened (Box Hill selected at once, GPXList.qml list currentIndex 0), frame 1 and the
# corners measured (t529_corners.py: the diagonal from each corner into the map, k - the first pixel off the
# page colour; 16 dp at 3.5 px/dp: k 16); modern: Govi to Hood picked (the map fits a new route - another zoom,
# fitRoute of the beta, already on both sides), frame 2 and the corners; the map dragged (adb swipe of 2.5 s, a frame in the middle of the
# drag and one after) - the corners stay covered while the map pans.
# Expected: head modern - round (k 12..24; dark: 13..20), base modern and classic on both sides - square
# (k <= 7); the page colour just outside the edges in both.
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
# run 43015224696; from test/t530-emu)
wipe_files() {
  local uid
  uid=$(app_uid)
  if [ -n "$uid" ]; then
    adb shell am force-stop "$PKG" < /dev/null > /dev/null 2>&1
    adb shell "su $uid,$uid,9997 sh -c 'rm -rf $QZDIR'" < /dev/null >> "$STEPLOG" 2>&1
  fi
  adb uninstall "$PKG" < /dev/null > /dev/null 2>&1
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

# rotate <0|1>: portrait or landscape, checked by the root bounds of a dump (from test/t530-emu)
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

log_lines() { wc -l < full_logcat.txt | tr -d ' '; }

# selected_by_log <shot> <route> <from line>: homeform gpxpreview_open_clicked of that route after <from>
selected_by_log() {
  local s=$1 route=$2 from=$3 i got
  for i in 1 2 3 4 5; do
    got=$(tail -n +"$from" full_logcat.txt | grep -a 'gpxpreview_open_clicked' | tail -n 1 | tr -d '\r')
    case $got in *"$route.gpx"*) break ;; esac
    emu_sleep 2
  done
  case $got in
    *"$route.gpx"*) say "check $s: '$route' selected (gpxpreview_open_clicked in the log): OK" ;;
    *) fail "check $s: '$route' not the last gpxpreview_open_clicked after the tap (${got:-none})" ;;
  esac
}

# no_restore <case>: the restore question on the GPX page of a fresh install answered No (from test/t530-emu)
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

open_gpx() {
  local land
  if [ "$MODERN" = true ]; then land="^$LONG\$"; else land='^Other folders$|^&?No$'; fi
  open_drawer '^Open GPX$' && tap_ui '^Open GPX$' "$land" && no_restore "$1"
}

# area <dump>: the part of the screen with the map, AREA="x1 y1 x2 y2"; x1 in the page margin or the gap left
# of the map (t529_corners.py takes the page colour from the column x1+1). Modern upright: under the list
# (0.4 of the page, GPXList.qml modernListBox) and above Other folders, x1 0 - the page margin. Side by side:
# right of the filter row ("Parent folder" in the modern look, "<-" in the classic one) - 3 px into the gap
# (classic: the button ends at 815, the map from 822 - frame h-4-after of run 43462330183)
area() {
  local x1=0 y1 x2=$SCR_W y2=$SCR_H of
  if [ "$MODERN" = true ] && [ "$SCR_W" -lt "$SCR_H" ]; then
    y1=$(( SCR_H * 56 / 100 ))
    of=$(uifind "$1" '^Other folders$' 2>/dev/null) && { set -- $of; y2=$6; }
  else
    local rx
    if [ "$MODERN" = true ]; then rx='^Parent folder$'; else rx='^←$'; fi
    if of=$(uifind "$1" "$rx" 2>/dev/null); then
      set -- $of
      # +4: the classic button ends 7 px before the map, its last pixel is not the page colour (run
      # 43587868726: x1 +3 took the button for the map)
      x1=$(( $7 + 4 ))
    else
      fail "area: no '$rx' in $1 - the left edge of the map area unknown"
      return 1
    fi
    y1=252
  fi
  AREA="$x1 $y1 $x2 $y2"
}

# corners <shot> [<corners>]: a raw frame now, the corners measured and judged by the side and the look.
# <corners> - which ones are judged (t529_corners.py): the classic look - tl only (its ScrollView keeps a
# scroll bar right beside the map, the buttons under it); in the middle of a drag - tl only (the drag left
# opens the right side of the map, tiles not loaded yet are the page colour)
corners() {
  local s=$1 which=${2:-tl,tr,br} mode out rc
  frame "raw-$s" || { fail "$s: no raw frame"; return 1; }
  [ "$MODERN" = true ] || which=tl
  # k by the diagonal: 16 for 16 dp at 3.5 px/dp; dark - the light tiles against the dark page, a sharp arc
  if [ "$MODERN" = true ] && [ "$SIDE" = h ]; then
    if [ "$DARK" = true ]; then mode="round 13 20"; else mode="round 12 24"; fi
  else
    # a light tile pixel at the corner: k 3-5 on a square corner (run 43587868726), 16 on a round one
    mode="square 0 7"
  fi
  out=$("$EMU_PY" .github/t529_corners.py "raw-$s" $AREA $mode "$which")
  rc=$?
  rm -f "raw-$s"
  echo "$s: $AREA $mode: $out" | tr '\n' ' ' >> corners.txt
  echo >> corners.txt
  say "  corners $s ($AREA, $mode): $(echo "$out" | tr '\n' ' ')"
  case $rc in
    0) say "check $s: corners ${mode%% *}: OK" ;;
    1) fail "check $s: corners not ${mode%% *}" ;;
    *) fail "check $s: the map not found on the frame" ;;
  esac
}

# drag <shot>: the map dragged left over 2.5 s from its middle; a frame in the middle of the drag (the corners
# while the map pans) and one after it
drag() {
  local s=$1 x y sw
  set -- $AREA
  x=$(( ($1 + $3) / 2 )); y=$(( ($2 + $4) / 2 ))
  say "drag the map from $x $y by 300 px left"
  adb shell input swipe "$x" "$y" "$(( x - 300 ))" "$y" 2500 < /dev/null > /dev/null 2>&1 &
  sw=$!
  emu_sleep 1
  corners "$s-during" tl
  # only the swipe: a bare wait would wait for the logcat of logcat_start too
  wait "$sw"
  emu_sleep 2
  still
  shot "$s-after"
  corners "$s-after"
}

# gpx <case> <modern> <landscape> <dark>
gpx() {
  local c=$1 from
  MODERN=$2; DARK=$4
  EMU_MASKS=""
  if [ "$MODERN" = true ]; then
    start_case "$c" ui_modern=true ui_theme_mode="$( [ "$DARK" = true ] && echo dark || echo light )" fakedevice_treadmill=true || return 1
  else
    # the classic rows scroll a long name: the screen never stood still (test/t530-emu)
    EMU_MASKS="0,975,2560,1080"
    start_case "$c" ui_modern=false fakedevice_treadmill=true || return 1
  fi
  SCR_W=1440; SCR_H=2560
  if [ "$3" = 1 ]; then
    rotate 1 || { rotate 0; return 1; }
  else
    rotate 0
  fi
  from=$(log_lines)
  say "== $c: GPX page"
  if open_gpx "$c"; then
    emu_sleep 3
    still
    shot "$c-1-long"
    selected_by_log "$c-1-long" "$LONG" "$from"
    if area "dumps/$c-1-long.xml"; then
      corners "$c-1-long"
      if [ "$MODERN" = true ]; then
        from=$(log_lines)
        a11y_build || fail "$c: no a11y driver"
        drv "pick-$c" "click=$SHORT" "sleep:1000"
        if grep -q "returned true" "drv/pick-$c.txt"; then
          emu_sleep 3
          still
          shot "$c-2-short"
          selected_by_log "$c-2-short" "$SHORT" "$from"
          corners "$c-2-short"
          drag "$c-3-drag"
        else
          fail "$c: the accessibility click on '$SHORT' did not work"
        fi
      fi
    fi
  fi
  back_to "$HOME_RX" 20
  [ "$3" = 1 ] && rotate 0
  return 0
}

emu_init
logcat_start
: > corners.txt

for SIDE in b h; do
  case $SIDE in
    b) apk=apk-base/android-debug.apk ;;
    h) apk=apk-head/android-debug.apk ;;
  esac
  side_on "$SIDE" "$apk" || continue
  say "== $SIDE: start"
  wipe_files
  install_apk "$apk"
  gpx "${SIDE}mp" true 0 false
  gpx "${SIDE}ml" true 1 false
  gpx "${SIDE}md" true 0 true
  gpx "${SIDE}cp" false 0 false
done

logcat_stop
finish
