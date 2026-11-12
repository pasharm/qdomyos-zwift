#!/bin/bash
# Test only (T-495): the program preview with a long description (HIIT Aerobic) and a short one (HIIT
# Neuromuscular), before (base: the branch of PR 6a-1) and after (head: + T-495), classic and modern look,
# portrait and landscape. After: the long description folded with "Show more" (named, in the dump), unfolded
# with "Show less" and folded back; the short one without the button; in landscape side by side: no button,
# the chart WebView on the right half (bounds in steps.log); upright again folded.
. .github/lib.sh
. .github/qz.sh

QZDIR=/sdcard/Documents/QZ

# app_uid: the uid of the installed app - the owner of its data folder; empty without the app (T-514)
app_uid() {
  adb shell "su 0 stat -c %u /data/data/$PKG" < /dev/null 2>/dev/null | tr -d '\r'
}

# wipe_files: Documents/QZ of the previous side removed by the app uid while it is installed - files of an
# uninstalled app belong to another uid and bring the "previous installation" box (T-514, run 43015224696)
wipe_files() {
  local uid
  uid=$(app_uid)
  if [ -n "$uid" ]; then
    adb shell am force-stop "$PKG" < /dev/null > /dev/null 2>&1
    adb shell "su $uid,$uid,9997 sh -c 'rm -rf $QZDIR'" < /dev/null >> "$STEPLOG" 2>&1
  fi
  adb uninstall "$PKG" < /dev/null > /dev/null 2>&1
  if adb shell "ls -d $QZDIR" < /dev/null > /dev/null 2>&1; then
    adb shell "su 0 ls -lnR $QZDIR" < /dev/null >> "$STEPLOG" 2>&1
    proves_nothing "$QZDIR left from the previous side (uid ${uid:-none})"
  fi
}

# rotate <0|1>: portrait or landscape, then a check by the root bounds of a dump that the app turned
# (T-487, lesson 2: user_rotation once left QZ in portrait and the run proved nothing)
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
      emu_sleep 3
      return 0
    fi
  done
  fail "rotation $want: the screen is ${w:-?}x${h:-?}"
  return 1
}

# webview_of <shot>: the bounds of the chart WebView in the dump of that frame, to steps.log
webview_of() {
  local b
  b=$(grep -o 'class="android.webkit.WebView"[^>]*bounds="[^"]*"' "dumps/$1.xml" 2>/dev/null | grep -o 'bounds="[^"]*"' | head -1)
  say "chart $1: ${b:-no WebView in the dump}"
}

# bounds_of <shot> <what>: "x1 y1 x2 y2" of the chart WebView (what=chart) or of the screen root (screen)
bounds_of() {
  if [ "$2" = chart ]; then
    grep -o 'class="android.webkit.WebView"[^>]*bounds="[^"]*"' "dumps/$1.xml" 2>/dev/null | grep -o 'bounds="[^"]*"' | head -1 | tr -c '0-9\n' ' '
  else
    grep -o 'bounds="\[0,0\]\[[0-9]*,[0-9]*\]"' "dumps/$1.xml" 2>/dev/null | head -1 | tr -c '0-9\n' ' '
  fi
}

# chart_right <shot> <upright shot>: side by side the chart WebView starts past a third of the screen
# width, is taller than a third of its height (the base has no WebView or a strip under the text) and
# ends no lower than the page: the upright chart reaches the page bottom, so the gap under it there is
# the bar at the bottom (run 43079787273: the text column pushed the chart 85 px under the bar, API 35)
chart_right() {
  local s=$1 up=$2 b sw sh inset
  set -- $(bounds_of "$up" screen); inset=$4
  set -- $(bounds_of "$up" chart); inset=$(( ${inset:-0} - ${4:-0} ))
  set -- $(bounds_of "$s" screen); sw=$3; sh=$4
  b=$(bounds_of "$s" chart)
  set -- $b
  if [ -z "$4" ] || [ -z "$sw" ]; then
    fail "$s: side by side: no WebView or no screen bounds in the dump"
  elif [ "$1" -gt $(( sw / 3 )) ] && [ $(( $4 - $2 )) -gt $(( sh / 3 )) ] && [ "$4" -le $(( sh - inset + 2 )) ]; then
    say "check $s: side by side, the chart on the right $1..$3 x $2..$4, the page bottom $(( sh - inset )): OK"
  else
    fail "$s: side by side: the chart at $1..$3 x $2..$4 of ${sw}x$sh, the page bottom $(( sh - inset ))"
  fi
}

# text_beside_buttons <shot>: side by side the buttons are over the chart only, so the description
# starts at the top of the page, beside them. The text has no node of its own; its scroll bar (a node
# under 40 px wide in the left half, as tall as the text block) gives the block top, and it must be
# above the bottom of "Start Workout" (beta 2374: bar from 525, the button row 270..437, API 35)
text_beside_buttons() {
  local s=$1 sw btn bar
  set -- $(bounds_of "$s" screen); sw=$3
  btn=$(grep -o 'content-desc="Start Workout"[^>]*bounds="[^"]*"' "dumps/$s.xml" 2>/dev/null | grep -o 'bounds="[^"]*"' | head -1 | tr -c '0-9\n' ' ')
  bar=$(grep -o 'bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' "dumps/$s.xml" 2>/dev/null | tr -c '0-9\n' ' ' \
    | awk -v w="${sw:-0}" '$3 - $1 > 0 && $3 - $1 < 40 && $3 < w / 2 && $4 - $2 > 100 { print; exit }')
  set -- $btn
  local by2=$4
  set -- $bar
  if [ -z "$by2" ] || [ -z "$2" ]; then
    fail "$s: text beside the buttons: no Start Workout or no scroll bar of the text in the dump"
  elif [ "$2" -lt "$by2" ]; then
    say "check $s: the text from y $2, beside the buttons (their bottom $by2): OK"
  else
    fail "$s: the text from y $2, under the buttons (their bottom $by2)"
  fi
}

# open_program <case> <name> <row>: the program from the list. Modern cards are named; the classic rows
# have no name - the row <row> below the filter field (50 dp = 175 px rows on the CI Nexus 6, the first one
# 170 px below the field: T-514)
open_program() {
  local c=$1 name=$2 row=$3 x y
  open_drawer '^Open Train Program$' && tap_ui '^Open Train Program$' '^Other folders$' || return 1
  emu_sleep 3
  dump
  # modern look: the card by its name; the beta has no names on the cards (6a-1 added them), so
  # there by the row, as in the classic one, with the card pitch of the frame (1440 px wide)
  if [ "${c#?}" = m ] && find_ui "^$name\$"; then
    tap_ui "^$name\$" '^Start Workout$' 20
    return
  fi
  if ! find_ui '^Search \(recursive\)\.\.\.$'; then
    fail "$c: the filter field not on the screen"
    return 1
  fi
  set -- $EMU_AT
  x=720
  if [ "${c#?}" = m ]; then
    # beta 2348, API 35: the field bottom 447, the card centres 581, 819 ... 1533
    y=$(( $8 + 134 + (row - 1) * 238 ))
  else
    y=$(( $8 + 170 + (row - 1) * 175 ))
  fi
  say "tap the program row $row ($name) at $x $y"
  adb shell input tap "$x" "$y" < /dev/null > /dev/null 2>&1
  if wait_ui '^Start Workout$' 20; then
    say "outcome 'program $name': ok"
  else
    say "outcome 'program $name': no-effect"
    fail "$c: the preview of $name did not open"
    return 1
  fi
}

# preview <case> <modern>: the two programs in one look; the checks of the button only on the head side
preview() {
  local c=$1 modern=$2 head=0
  [ "${c%?}" = h ] && head=1
  start_case "$c" ui_modern=$modern fakedevice_treadmill=true android_documents_folder=true || return 1

  if open_program "$c" 'HIIT Aerobic' 2; then
    emu_sleep 5
    shot "$c-1-long"
    webview_of "$c-1-long"
    if [ $head = 1 ]; then
      expect "$c-1-long" '^Show more$' 'the long description folded, Show more'
      if tap_ui '^Show more$' '^Show less$' 10; then
        emu_sleep 2
        shot "$c-2-long-open"
        webview_of "$c-2-long-open"
        expect "$c-2-long-open" '^Show less$' 'unfolded, Show less'
        tap_ui '^Show less$' '^Show more$' 10 || fail "$c: Show less did not fold the description"
      fi
    fi
    if rotate 1; then
      emu_sleep 4
      shot "$c-3-long-land"
      webview_of "$c-3-long-land"
      if [ $head = 1 ]; then
        # side by side: the whole text scrolls in its column, no button; the chart on the right half
        expect_not "$c-3-long-land" '^Show more$' 'landscape: side by side, no Show more'
        chart_right "$c-3-long-land" "$c-1-long"
        text_beside_buttons "$c-3-long-land"
      fi
    fi
    if rotate 0 && [ $head = 1 ]; then
      emu_sleep 4
      shot "$c-4-long-back"
      webview_of "$c-4-long-back"
      expect "$c-4-long-back" '^Show more$' 'upright again: folded, Show more'
    fi
  fi
  back_to "$HOME_RX" 20

  if open_program "$c" 'HIIT Neuromuscular' 5; then
    emu_sleep 5
    shot "$c-5-short"
    webview_of "$c-5-short"
    [ $head = 1 ] && expect_not "$c-5-short" '^Show more$' 'a short description has no button'
  fi
  back_to "$HOME_RX" 20
}

# qml_quiet: no QML warning of the changed file from the head processes (pid lines of start_case); turning
# upright once warned "Layout: column (1) should be less than the number of columns (1)" and every check
# was green (T-495)
qml_quiet() {
  local pid n=0 found
  logcat_stop
  for pid in $(grep -a '^pid h' "$STEPLOG" | cut -d' ' -f3); do
    n=$(( n + 1 ))
    found=$(awk -v p="$pid" '$3 == p' full_logcat.txt | grep -a 'TrainingProgramsListJS.qml:' | head -5)
    if [ -n "$found" ]; then
      echo "$found" >> "$STEPLOG"
      fail "check qml: pid $pid: QML warnings of TrainingProgramsListJS.qml"
    fi
  done
  if [ "$n" = 0 ]; then
    fail "check qml: no head pid in steps.log - QML warnings not checked"
  elif [ ! -s full_logcat.txt ]; then
    fail "check qml: full_logcat.txt is empty"
  else
    grep -q '^!! check qml' "$STEPLOG" || say "check qml: no TrainingProgramsListJS.qml warning from $n head processes: OK"
  fi
}

emu_init
logcat_start

for side in b h; do
  if [ "$side" = b ]; then apk=apk-base/android-debug.apk; else apk=apk-head/android-debug.apk; fi
  say "== $side: start"
  wipe_files
  install_apk "$apk"
  preview "${side}c" false
  preview "${side}m" true
done

qml_quiet
finish
