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

# editor_views_of <shot>: the number of WebView nodes of the editor page (its inner node carries the <title>
# of index.html, "Workout Editor"); the chart footer of home is a WebView too ("Line Chart", off by default)
editor_views_of() {
  "$EMU_PY" - "dumps/$1.xml" << 'EOF'
import sys
import xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
print(sum(1 for n in root.iter('node')
          if n.get('class') == 'android.webkit.WebView' and n.get('text') == 'Workout Editor'))
EOF
}

# webview_fit <shot>: "fit" - the WebView nodes reach both edges of the window (the root node of the dump),
# 2 px of slack: the outer node ends 1 px short of the root (T-187 dumps, 1439 of 1440); else
# "<right edge> of <window width>"; "none" without a WebView. The native view only - the page laid out anew
# is told by the frame
webview_fit() {
  "$EMU_PY" - "$EMU_GH" "dumps/$1.xml" << 'EOF'
import sys
import xml.etree.ElementTree as ET
sys.path.insert(0, sys.argv[1])
import emu_frame
root = ET.parse(sys.argv[2]).getroot()
nodes = list(root.iter('node'))
views = [emu_frame.parse_bounds(n.get('bounds')) for n in nodes if n.get('class') == 'android.webkit.WebView']
if not views:
    print("none")
    sys.exit(0)
sx1, sy1, sx2, sy2 = emu_frame.parse_bounds(nodes[0].get('bounds'))
x1 = min(v[0] for v in views)
x2 = max(v[2] for v in views)
print("fit" if abs(x1 - sx1) <= 2 and abs(x2 - sx2) <= 2 else "%d..%d of %d..%d" % (x1, x2, sx1, sx2))
EOF
}

# told_or <side> <ok> <shot> <what>: head - a check (fail when ok is not 0); base - told only
told_or() {
  if [ "$1" = b ]; then
    say "before $3: $4: $([ "$2" = 0 ] && echo yes || echo no)"
  elif [ "$2" = 0 ]; then
    say "check $3: $4: OK"
  else
    fail "check $3: $4"
  fi
}

# count_is <n>: the chart card tells n intervals ("Treadmill • Duration 10:00 • 2 intervals",
# workout-editor.js). uifind matches the whole text; with two intervals the card lies below the screen and
# Chrome gives its nodes [0,0][0,0] - those only --offscreen finds
count_is() {
  dump || return 1
  find_ui ".*• $1 intervals" --any && return 0
  uifind ui.xml --offscreen ".*• $1 intervals" > /dev/null 2>&1
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

# home_clean <case> <shot>: back home from the editor, then no WebView of the editor over the home page
home_clean() {
  local c=$1 s=$2 n
  back_to "$HOME_RX" 20 || { fail "$c: home not shown after Back"; return 1; }
  emu_sleep 2
  still
  shot "$s"
  n=$(editor_views_of "$s")
  if [ "$n" = 0 ]; then
    say "check $s: no WebView of the editor over home: OK"
  else
    fail "check $s: $n WebView node(s) of the editor over home after it closed"
  fi
}

# keep <side> <look>: m - modern, c - classic
keep() {
  local side=$1 look=$2 c="$1k$2" modern=false kept=1 ok fit n envs0 envs wk0 wk wkopen
  [ "$look" = m ] && modern=true
  # the kept page is the change: only the head in the modern look keeps the workout
  [ "$side" = h ] && [ "$look" = m ] && kept=2
  start_case "$c" ui_modern=$modern fakedevice_treadmill=true || return 1

  # 1. a workout of two intervals (a fresh page has one), closed and opened again
  open_editor "$c" || return 1
  tap_ui '^Add Interval$' '^Interval 2$' 20
  emu_sleep 3
  still
  shot "$c-1-two"
  count_is 2 || fail "check $c-1-two: no '2 intervals' after Add Interval ($EMU_WHY)"
  # the control of the check at home below: the open editor takes the workout updates and its log
  # reaches logcat - without them a zero at home proves nothing
  wk0=$(grep -cF '] "{"msg":"workout"' full_logcat.txt)
  emu_sleep 10
  wk=$(( $(grep -cF '] "{"msg":"workout"' full_logcat.txt) - wk0 ))
  wkopen=$wk
  [ "$wk" -gt 0 ]; ok=$?
  told_or "$side" $ok "$c-1-two" "the open editor takes the workout updates ($wk in 10 s)"
  home_clean "$c" "$c-2-home"
  # at home the editor takes no workout updates: the kept page is off the server while hidden
  # (main_ws_pause of main_ws_manager.js), master and the classic look destroy it. Each page that
  # takes them logs each one (onmessage), about one a second with the fake treadmill; the home page
  # has a web page of its own that takes them too (run 44704596642: 10 at home, 20 with the editor
  # open, on master too) - so fewer at home than with the editor open, not none. Before the pause
  # the kept page took them all the time (run 44670342156)
  wk0=$(grep -cF '] "{"msg":"workout"' full_logcat.txt)
  emu_sleep 10
  wk=$(( $(grep -cF '] "{"msg":"workout"' full_logcat.txt) - wk0 ))
  [ $(( wk * 3 )) -lt $(( wkopen * 2 )) ]; ok=$?
  told_or "$side" $ok "$c-2-home" "fewer workout updates at home than with the editor open ($wk against $wkopen in 10 s)"
  if [ "$kept" = 2 ]; then
    grep -qF 'Socket is closed while the page is hidden' full_logcat.txt; ok=$?
    told_or "$side" $ok "$c-2-home" "the kept page closed its socket when hidden"
  fi
  # the page asks for the connected machine, FTP and the units at each opening: a fresh page when it
  # loads, the kept one when shown again (qzEditorReopened) - what changed meanwhile is not missed
  envs0=$(grep -c 'WS >> {"msg":"workouteditor_env"' full_logcat.txt)
  open_editor "$c" || return 1
  shot "$c-3-again"
  count_is $kept; ok=$?
  told_or "$side" $ok "$c-3-again" "opened again with $kept interval(s)"
  envs=$(( $(grep -c 'WS >> {"msg":"workouteditor_env"' full_logcat.txt) - envs0 ))
  [ "$envs" -ge 1 ]; ok=$?
  told_or "$side" $ok "$c-3-again" "the environment asked again at the opening ($envs)"
  # (the menu entry with the editor open - not here: the native web view lies over the menu of QML; the
  # phone check of T-596 takes it)
  home_clean "$c" "$c-4-home"

  # 2. turned while closed, opened again: the web view laid out for the new width
  if rotate land "$c"; then
    if open_editor "$c"; then
      shot "$c-5-land"
      fit=$(webview_fit "$c-5-land")
      [ "$fit" = fit ]; ok=$?
      told_or "$side" $ok "$c-5-land" "the editor as wide as the window in landscape ($fit)"
      home_clean "$c" "$c-6-home-land"
    fi
  fi
  rotate port "$c" || return 1
  open_editor "$c" || return 1
  shot "$c-7-port"
  fit=$(webview_fit "$c-7-port")
  [ "$fit" = fit ]; ok=$?
  told_or "$side" $ok "$c-7-port" "the editor as wide as the window upright again ($fit)"

  # 3. Save & Start closes the editor (the workout is saved as "Workout" and started)
  scroll_top
  if dump && find_ui '^Save & ?Start$' --first; then
    set -- $EMU_AT
    say "tap Save & Start at $1 $2"
    starts0=$(grep -c 'Emitting trainprogram_autostart_requested' full_logcat.txt)
    adb shell input tap "$1" "$2" < /dev/null > /dev/null 2>&1
    if wait_gone '^Add Interval$' 30; then
      emu_sleep 3
      shot "$c-8-started"
      n=$(editor_views_of "$c-8-started")
      if [ "$n" = 0 ]; then
        say "check $c-8-started: Save & Start closed the editor: OK"
      else
        fail "check $c-8-started: $n WebView node(s) of the editor after Save & Start"
      fi
      # the start sent once: the editor's queue sent a message with no reply again every 15 s, and the
      # kept page lived on - the workout started again and the editor closed on its next opening
      # (run 44627484058: 22:38:21, :37, :52)
      sleep 35
      starts=$(( $(grep -c 'Emitting trainprogram_autostart_requested' full_logcat.txt) - starts0 ))
      [ "$starts" = 1 ]; ok=$?
      told_or "$side" $ok "$c-8-started" "the workout started once in 35 s after Save & Start ($starts)"
      # opens again after that (the kept page closed by the handler, not lost)
      if open_editor "$c"; then
        shot "$c-9-after-start"
        say "check $c-9-after-start: the editor opens after Save & Start: OK"
      fi
    else
      shot "$c-8-not-closed"
      fail "check $c-8-not-closed: the editor still open 30 s after Save & Start"
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
  # the workouts of the other side out: reinstalled, the app gets a new uid, and on API 35 it does not see the
  # files the old one made in Documents/QZ/training - the list empty, Save & Start finds no saved workout and
  # stays (run 44622297578: h - "programFiles: " empty, b - all of them)
  adb shell rm -rf /sdcard/Documents/QZ/training < /dev/null > /dev/null 2>&1
  install_apk "$apk"
  keep $side m
  keep $side c
done

finish
