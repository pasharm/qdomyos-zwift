#!/bin/bash
# Test only (T-596): the workout editor kept between openings in the modern look - before (base: master, a new
# page every opening) and after (head: the PR branch). Checks on the head, modern look:
#   - the workout typed is still there when the editor is opened again (an interval added: "2 intervals")
#   - the closed editor leaves nothing over the home page: no WebView in the dump of home (the page is hidden by
#     StackView and its native view follows - QQuickViewController::onVisibleChanged, Qt 5.15.0)
#   - turned to landscape while closed and opened again: the web view as wide as the screen (not laid out for
#     the old width), and back upright the same
#   - Save & Start closes the kept editor (one handler) and it opens again after that
#   (the menu entry with the editor open - the phone, see step 2)
# Classic look on both sides and the modern look of the base: a new page every opening ("1 intervals") - the
# behaviour of master.

. .github/lib.sh
. .github/qz.sh

# rotate <0|1>: portrait or landscape, then a check by the root bounds of a dump that the app turned
# (T-487, lesson 2: user_rotation once left QZ in portrait and the run proved nothing; from the T-187 scenario)
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

# webviews_of <shot>: the number of android.webkit.WebView nodes in the dump
webviews_of() {
  "$EMU_PY" - "dumps/$1.xml" << 'EOF'
import sys
import xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
print(sum(1 for n in root.iter('node') if n.get('class') == 'android.webkit.WebView'))
EOF
}

# webview_fit <shot>: "fit" - the first WebView is as wide as the screen (the root node of the dump), else
# "<webview width> of <screen width>"; "none" without a WebView
webview_fit() {
  "$EMU_PY" - "$EMU_GH" "dumps/$1.xml" << 'EOF'
import sys
import xml.etree.ElementTree as ET
sys.path.insert(0, sys.argv[1])
import emu_frame
root = ET.parse(sys.argv[2]).getroot()
nodes = list(root.iter('node'))
views = [n for n in nodes if n.get('class') == 'android.webkit.WebView']
if not views:
    print("none")
    sys.exit(0)
sx1, sy1, sx2, sy2 = emu_frame.parse_bounds(nodes[0].get('bounds'))
x1, y1, x2, y2 = emu_frame.parse_bounds(views[0].get('bounds'))
print("fit" if (x1, x2) == (sx1, sx2) else "%d of %d" % (x2 - x1, sx2 - sx1))
EOF
}

# told_or <side> <ok> <what>: head - a check (fail when ok is not 0); base - told only
told_or() {
  if [ "$1" = b ]; then
    say "before: $3: $([ "$2" = 0 ] && echo yes || echo no)"
  elif [ "$2" = 0 ]; then
    say "check: $3: OK"
  else
    fail "check: $3"
  fi
}

# count_is <n>: the chart card tells n intervals ("Treadmill • Duration 10:00 • 2 intervals")
count_is() {
  dump && find_ui "• $1 intervals\$" --any
}

# open_editor <case>: the editor from the drawer, the page loaded (Add Interval on the screen)
open_editor() {
  open_drawer '^Workout Editor$' && tap_ui '^Workout Editor$' '^Add Interval$' 40 || {
    fail "$1: the editor did not open"
    return 1
  }
  emu_sleep 2
  still
}

# home_clean <case> <shot>: back home from the editor, then no WebView over the home page
home_clean() {
  local c=$1 s=$2 n
  # already home (one Back above) - no tap: back_to would tap the menu button there
  if ! { dump && find_ui "$HOME_RX" --first && ! find_ui '^Add Interval$'; }; then
    back_to "$HOME_RX" 20 || { fail "$c: home not shown after Back"; return 1; }
  fi
  emu_sleep 2
  still
  shot "$s"
  n=$(webviews_of "$s")
  if [ "$n" = 0 ]; then
    say "check $s: no WebView over home: OK"
  else
    fail "check $s: $n WebView node(s) over home after the editor closed"
  fi
}

# keep <side> <look>: m - modern, c - classic
keep() {
  local side=$1 look=$2 c="$1k$2" modern=false kept=1 ok fit
  [ "$look" = m ] && modern=true
  # the kept page is the change: only the head in the modern look keeps the workout
  [ "$side" = h ] && [ "$look" = m ] && kept=2
  start_case "$c" ui_modern=$modern fakedevice_treadmill=true || return 1

  # 1. a workout of two intervals, closed and opened again
  open_editor "$c" || return 1
  tap_ui '^New$' '^Add Interval$' 20
  emu_sleep 3
  tap_ui '^Add Interval$' '^Add Interval$' 20
  emu_sleep 3
  still
  shot "$c-1-two"
  count_is 2 || fail "$c-1-two: no '2 intervals' after Add Interval ($EMU_WHY)"
  home_clean "$c" "$c-2-home"
  open_editor "$c" || return 1
  shot "$c-3-again"
  count_is $kept; ok=$?
  told_or "$side" $ok "$c-3-again: opened again with $kept interval(s) (kept=$kept)"

  # 2. (the menu entry with the editor open - not here: the native web view lies over the menu of QML, the
  # phone check of T-596 takes it)
  home_clean "$c" "$c-5-home"

  # 3. turned while closed, opened again: the page laid out for the new width
  if rotate 1; then
    open_editor "$c" && {
      shot "$c-6-land"
      fit=$(webview_fit "$c-6-land")
      [ "$fit" = fit ]; ok=$?
      told_or "$side" $ok "$c-6-land: the editor as wide as the screen in landscape ($fit)"
      home_clean "$c" "$c-7-home-land"
    }
  fi
  if rotate 0; then
    open_editor "$c" && {
      shot "$c-8-port"
      fit=$(webview_fit "$c-8-port")
      [ "$fit" = fit ]; ok=$?
      told_or "$side" $ok "$c-8-port: the editor as wide as the screen upright again ($fit)"
    }
  fi

  # 4. Save & Start closes the editor (the workout of two intervals is saved and started)
  if dump && find_ui '^Save &(amp;)? ?Start$' --first; then
    set -- $EMU_AT
    say "tap Save & Start at $1 $2"
    adb shell input tap "$1" "$2" < /dev/null > /dev/null 2>&1
    if wait_gone '^Add Interval$' 30; then
      emu_sleep 3
      shot "$c-9-started"
      say "check $c-9-started: Save & Start closed the editor: OK"
      n=$(webviews_of "$c-9-started")
      [ "$n" = 0 ] || fail "check $c-9-started: $n WebView node(s) after Save & Start"
      # opens again after that (the kept page was closed by the handler, not lost)
      open_editor "$c" && shot "$c-10-after-start"
    else
      shot "$c-9-not-closed"
      fail "check $c-9-not-closed: the editor still open 30 s after Save & Start"
    fi
  else
    fail "$c: no Save & Start on the screen"
  fi
  back_to "$HOME_RX" 20
}

emu_init
logcat_start

for side in b h; do
  if [ "$side" = b ]; then apk=apk-base/android-debug.apk; else apk=apk-head/android-debug.apk; fi
  side_on $side "$apk" || continue
  say "== $side: start"
  adb uninstall "$PKG" < /dev/null > /dev/null 2>&1
  install_apk "$apk"
  keep $side m
  keep $side c
done

finish
