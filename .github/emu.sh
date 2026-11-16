#!/bin/bash
# Test only (T-265, T-560): what the real TalkBack (Google TalkBack 15, image API 35) finds in the side menu
# and in the heart rate sensor bar - before (base: test/t265-master = origin/master fb8bd3a22 + the T-473 hook)
# and after (head: test/t265-diag = the same + no Accessible.ignored on the Drawer + a StaticText node
# focusable, as Qt does since 5.15.9 - QTBUG-77371; or test/t265-fix = the fix of fix/talkback-modal-popups:
# a modal popup is all a screen reader reaches, an ItemDelegate is clickable; or test/t560-fix = the fix of
# fix/talkback-static-text: a text focusable unless inside a focusable or pressable item). The tree with the menu open ('list'),
# a touch on a menu entry, swipes from the menu button, a double tap on Settings; the bar text by touch and
# by a swipe left from Choose. The head is red only where it is not better than the base; the findings are in
# the "talkback <case>:" lines.
# Base master: main.qml:1880 Accessible.ignored: !drawer.opened on the Drawer (QTBUG-83738 in Qt 5.15.0),
# the menu entries of the classic look - ItemDelegate (main.qml ~1930-2010), of the modern look - UiDrawerItem.
# The bar: HeartRateSuggestion.qml, the Label of the text and the buttons Choose / Not now / Don't ask again;
# with t473_fake_sensors homeform "finds" two sensors 30 s and 45 s after it starts (hook b99a71cb5).
# Cases <side><case>: side b/h; c - classic en, m - modern en (both: menu, then the bar); f - T-503, the focus
# after Cancel of the sensor list (head: a build of fix/talkback-focus-after-popup + the hook); s - T-560, how long
# TalkBack takes per swipe on the settings page (classic en).
HOME_RX='^(Start|Stop|Pause)$'
HOME_READY_RX='^Contact QZ support$'
. .github/lib.sh
. .github/qz.sh

# wait_log <case> <text> <count before> [seconds]: the line once more in the log
wait_log() {
  local i
  for i in $(seq 1 "${4:-90}"); do
    if [ "$(grep -a -c "$2" full_logcat.txt)" -gt "$3" ]; then
      say "$1: '$2' after $i s"
      return 0
    fi
    sleep 1
  done
  fail "$1: '$2' not in the log"
  return 1
}

# tb_has <regex> <drv name>: 0 - a line of the driver output matches
tb_has() { grep -q -E "$1" "drv/$2.txt"; }
# yn <regex> <drv name>: yes / no
yn() { if tb_has "$1" "$2"; then echo yes; else echo no; fi; }

# tb_window: TalkBack's own box over the app ("Welcome to the updated TalkBack", run 43799153429: it came
# up between two passes, and the swipes walked it) is closed by the back key
tb_window() {
  # an activity of TalkBack (the box is window type 1, an application's), not the window focus of the window
  # manager: mCurrentFocus did not show it (run 43801005217)
  local top i
  for i in 1 2 3; do
    top=$(adb shell dumpsys activity activities < /dev/null 2>/dev/null | grep -a -m1 -E "mResumedActivity|topResumedActivity")
    say "$1: on top: ${top:-?}"
    echo "$top" | grep -q "$TB_PKG" || return 0
    near tbwindow "$1: a box of TalkBack over the app, back key $i"
    adb shell input keyevent 4 < /dev/null > /dev/null 2>&1
    emu_sleep 2
  done
  fail "$1: the box of TalkBack stays over the app"
}

# tb_start <case>: TalkBack on, its box closed if it is up already
tb_start() {
  tb_on
  tb_window "$1"
}

# drv_tb <name> <driver args...>: a pass of the driver, once more when TalkBack's tutorial ("Welcome to the
# updated TalkBack", TrainingActivity) came over the app during it - it comes on one of the first gestures,
# not after a time (none in 60 s after TalkBack on, then up in a pass: run 43806680584). Disabled by pm
# disable, TalkBack spoke and moved nothing (run 43804496166). Before the second pass: the box closed by
# back, a menu left open closed by back, the app brought back.
drv_tb() {
  local name=$1
  drv "$@"
  grep -a -q -E "updated TalkBack|Close tutorial" "drv/$name.txt" || return 0
  near tbwindow "$name: the tutorial of TalkBack came during the pass, the pass once more"
  mv "drv/$name.txt" "drv/$name-tutorial.txt"
  tb_window "$name"
  adb shell input keyevent 4 < /dev/null > /dev/null 2>&1
  emu_sleep 3
  ensure_app
  drv "$@"
  if grep -a -q -E "updated TalkBack|Close tutorial" "drv/$name.txt"; then
    fail "$name: the tutorial of TalkBack came in the second pass too"
  fi
  tb_no_markup "$name"
}

# tb_no_markup <name>: no stop of TalkBack in the pass says rich text markup (T-560: a text of the bar came
# to TalkBack as raw HTML, "<b>..." read out, and no check saw it). The head fails, the base is noted.
tb_no_markup() {
  local name=$1 bad
  bad=$(grep -a -E ": focused '.*[<>].*' class=" "drv/$name.txt" | head -n 1)
  [ -z "$bad" ] && return 0
  if [ "${name:0:1}" = h ]; then
    fail "$name: a stop with markup: $bad"
  else
    near markup "$name: a stop with markup on the base: $bad"
  fi
}

# results of the base, per case letter: R_<what>_<case>
declare -A R

# compare <case> <what> <value>: the head no worse than the base
compare() {
  local c=$1 what=$2 v=$3 side=${1:0:1} k=${1:1}
  say "talkback $c: $what: $v"
  if [ "$side" = b ]; then
    R[$what.$k]=$v
    return 0
  fi
  if [ "$v" = yes ]; then
    say "check $c: $what: OK"
  elif [ "${R[$what.$k]}" = yes ]; then
    fail "check $c: $what: the base had it, the head not"
  else
    near "$what" "$c: not on the head either (base: ${R[$what.$k]:-not run})"
  fi
}

# talkback <case> <ui_modern>: the menu and the bar with TalkBack on
talkback() {
  local c=$1 modern=$2 n2 menu entry i side=${1:0:1}
  if [ "$modern" = true ]; then menu='Main menu'; else menu='◄'; fi
  n2=$(grep -a -c "T-473 test: fake sensor 2" full_logcat.txt)
  start_case "$c" ui_modern=$modern app_language=en fakedevice_treadmill=true \
    heart_rate_belt_suggest=true t473_fake_sensors=true || return 1
  wait_log "$c" "T-473 test: fake sensor 2" "$n2" || return 1
  tb_start "$c"
  # the menu: opened by a double tap on its button; the tree with it open; a touch on Settings and a double
  # tap on it (in the menu just opened: after swipes it scrolls and a touch misses - run 43793272467, bm-menu2);
  # the settings page shows the header button Search settings, named in both looks (hidden on the home page, main.qml ~1459)
  tb_window "$c"
  drv_tb "$c-menu" --keep "focus:$menu" 'sleep:1500' "dtap:$menu" 'sleep:3000' 'list' 'find:Settings' \
    'touch:Settings' 'dtap:Settings' 'sleep:4000' 'find:Search settings'
  # the settings page, if it opened, back to the home page (the system back closes a page of QZ); the menu
  # left open by a failed press is closed by it too
  adb shell input keyevent 4 < /dev/null > /dev/null 2>&1
  emu_sleep 3
  ensure_app
  # swipes right from the menu button once the menu opened: in the menu, not on the page under it
  tb_window "$c"
  drv_tb "$c-swipe" --keep "focus:$menu" 'sleep:1500' "dtap:$menu" 'sleep:3000' 'swipe:right' 'swipe:right' \
    'swipe:right' 'swipe:right'
  adb shell input keyevent 4 < /dev/null > /dev/null 2>&1
  emu_sleep 3
  ensure_app
  for i in 1 2 3 4; do
    tb_window "$c"
    drv_tb "$c-wait$i" --keep 'sleep:3000' 'find:Heart rate sensors found'
    grep -a -q "^find:Heart rate sensors found: '" "drv/$c-wait$i.txt" && break
    near tree "$c: no bar in the TalkBack tree, look $i"
  done
  # first a touch at another point: a second touch at the same point gives TalkBack no new event
  tb_window "$c"
  drv_tb "$c-bar" --keep 'touch:Choose' 'touch:Heart rate sensors found' 'touch:Choose' 'swipe:left' 'focused'
  adb pull /data/local/tmp/tbshots "tbshots/$c" < /dev/null >> "$STEPLOG" 2>&1
  tb_off
  entry=$(grep -a -m1 "^find:Settings: '" "drv/$c-menu.txt")
  say "talkback $c: Settings node with the menu open: ${entry:-NOT FOUND}"
  compare "$c" "menu-entry-visible" "$(yn "^find:Settings: 'Settings' .* visible=true" "$c-menu")"
  compare "$c" "menu-entry-by-touch" "$(yn "^touch:Settings: focused 'Settings'" "$c-menu")"
  compare "$c" "menu-entry-opens-settings" "$(yn "^find:Search settings: 'Search settings' .* visible=true" "$c-menu")"
  # a swipe that lands on an entry of the menu (MENU_RX of qz.sh plus the modern ones) / on the page or header
  compare "$c" "menu-swipe-in-menu" \
    "$(yn "^swipe:right: focused '(Profile: .*|Settings|Charts|Open Train Program|Open GPX|Save FIT|Save GPX|Workouts History|Swag Bag|Wizard|Community|Quit|Help|Credits|Training programs|Workouts)'" "$c-swipe")"
  # a swipe that lands on the header or the page under the menu: compared with the base (a head without the
  # modality fix, test/t560-fix, does as master does). The menu button is left out: TalkBack's focus stays on
  # it when the menu opens, and the first swipe may stay there too (run 43806680584 hc, hm: the button, the
  # window, then the entries)
  local onpage=$(yn "^swipe:right: focused '(Floating window|Lock tiles|Unlock tiles|Pause|Stop|Start|Lap|QZ Fitness|.*Bluetooth.*|)' " "$c-swipe")
  say "talkback $c: a swipe from the menu button reached the page under the menu: $onpage"
  local menu_ok=no
  [ "$onpage" = no ] && tb_has "^swipe:right: focused '(Profile: .*|Settings|Charts|Open Train Program|Workouts)'" "$c-swipe" &&
    menu_ok=yes
  compare "$c" "menu-swipe-not-on-page" "$menu_ok"
  # T-560: a text inside a menu entry is not a second stop (Qt's focusable text alone gave 'Wizard'
  # twice in a row, run 43793272467 hm)
  local twice
  twice=$(grep -a "^swipe:right: focused '" "drv/$c-swipe.txt" | cut -d"'" -f2 | uniq -d | head -n 1)
  say "talkback $c: the same stop twice in a row: ${twice:-none}"
  compare "$c" "menu-swipe-no-double-stop" "$([ -z "$twice" ] && echo yes || echo no)"
  compare "$c" "bar-text-by-touch" "$(yn "^touch:Heart rate sensors found: focused 'Heart rate sensors found: 2'" "$c-bar")"
  compare "$c" "bar-text-by-swipe-left" "$(yn "^swipe:left: focused 'Heart rate sensors found: 2'" "$c-bar")"
  tb_check "^touch:Choose: focused 'Choose'" "$c-bar" "Choose by touch (as before)"
}

# focusback <case> (T-503): the list of sensors opened by a double tap on Choose, closed by a double tap on Cancel -
# where TalkBack's focus is then (base master: lost, head test/t503: back on Choose); then the list again and a
# sensor chosen (the bar goes away - the focus recorded only). Modern en (the list has Cancel in the modern look).
focusback() {
  local c=$1 n2
  n2=$(grep -a -c "T-473 test: fake sensor 2" full_logcat.txt)
  start_case "$c" ui_modern=true app_language=en fakedevice_treadmill=true \
    heart_rate_belt_suggest=true t473_fake_sensors=true || return 1
  wait_log "$c" "T-473 test: fake sensor 2" "$n2" || return 1
  tb_start "$c"
  for i in 1 2 3 4; do
    tb_window "$c"
    drv_tb "$c-wait$i" --keep 'sleep:3000' 'find:Heart rate sensors found'
    grep -a -q "^find:Heart rate sensors found: '" "drv/$c-wait$i.txt" && break
    near tree "$c: no bar in the TalkBack tree, look $i"
  done
  tb_window "$c"
  drv_tb "$c-cancel" --keep 'touch:Choose' 'dtap:Choose' 'sleep:3000' 'find:Cancel' 'touch:Cancel' 'dtap:Cancel' \
    'sleep:3000' 'find:Cancel' 'focused'
  # T-265: the list fades in (the Material Popup's enter: opacity 0 -> 1) - swipes from Choose once it
  # opened stay in the modal list, not on the bar and the page under it
  tb_window "$c"
  # 'focused' right after the list opened: T-503 moves TalkBack's focus to its title (or first row), as a dialog of Android
  drv_tb "$c-modal" --keep 'touch:Choose' 'dtap:Choose' 'sleep:3000' 'focused' 'swipe:right' 'swipe:right' \
    'swipe:right' 'swipe:right' 'touch:Cancel' 'dtap:Cancel' 'sleep:3000'
  tb_window "$c"
  drv_tb "$c-choose" --keep 'touch:Choose' 'dtap:Choose' 'sleep:3000' 'touch:Forerunner 965' 'dtap:Forerunner 965' \
    'sleep:3000' 'find:Heart rate sensors found' 'focused'
  adb pull /data/local/tmp/tbshots "tbshots/$c" < /dev/null >> "$STEPLOG" 2>&1
  tb_off
  # Choose's press is the list opening (with T-503 the focus moves into it, run 43809823579 hf)
  tb_check "^find:Cancel: 'Cancel' " "$c-cancel" "Choose pressed by a double tap: the list opened"
  # Cancel's press is the list closing: after the double tap the focus is no longer on Cancel, it is gone
  tb_check "^find:Cancel: NOT FOUND" "$c-cancel" "the list closed by Cancel"
  # in the list: a swipe reaches a row or Cancel; on the page: a swipe reaches the bar or the page. Choose is
  # left out: TalkBack's focus stays on it when the list opens, and the first swipe may stay there too
  # (run 43799153429 hf: Choose, the window, then the rows)
  local inlist=no onpage
  grep -a -q -E "^swipe:right: focused '(.*signal|Cancel)'" "drv/$c-modal.txt" && inlist=yes
  onpage=$(yn "^swipe:right: focused '(Not now|Don't ask again|Heart rate sensors found.*|Main menu|Floating window|Pause|Stop|Start|Lap|)' " "$c-modal")
  [ "$onpage" = yes ] && inlist=no
  say "talkback $c: a swipe in the open list reached the page under it: $onpage"
  compare "$c" "dialog-swipe-in-dialog" "$inlist"
  say "talkback $c: the list just opened: $(grep -a -m1 '^focused' "drv/$c-modal.txt")"
  compare "$c" "focus-into-list" "$(yn "^focused: focused '(Choose a heart rate sensor|.*signal|Cancel)'" "$c-modal")"
  say "talkback $c: after Cancel: $(grep -a '^focused' "drv/$c-cancel.txt" | tail -n 1)"
  say "talkback $c: after a sensor chosen: $(grep -a '^focused' "drv/$c-choose.txt" | tail -n 1)"
  compare "$c" "focus-back-on-choose" "$(yn "^focused: focused 'Choose'" "$c-cancel")"
}

# settingstime <case> (T-560, a finding of the reviewer: a text node asks for the node under its centre -
# coveredByActionable, a walk from the root - each time TalkBack asks for it): the settings page of the
# classic look, its many texts and rows, opened without TalkBack; then TalkBack on and swipes right, each
# timed from the end of the swipe to the focus on another node (tswipe of the driver). The head is red when
# its median is above 1.5 times the base's and 150 ms more, or it moved fewer times than the base.
settingstime() {
  local c=$1 side=${1:0:1} steps="" i ms moved med max
  start_case "$c" ui_modern=false app_language=en fakedevice_treadmill=true || return 1
  settings_open || return 1
  tb_start "$c"
  tb_window "$c"
  for i in $(seq 1 25); do steps="$steps tswipe:right"; done
  # shellcheck disable=SC2086
  # inside an open section: its rows have labels of their own beside the fields (texts outside a pressable
  # item - the path of coveredByActionable); on the section list every text is inside a section's button
  # (run 43840993097: both sides 18 equal stops, the path not taken)
  drv_tb "$c-time" --keep 'touch:General Options' 'dtap:General Options' 'sleep:2500' $steps
  tb_off
  ms=$(grep -a "^tswipe:right: moved after " "drv/$c-time.txt" | cut -d' ' -f4 | sort -n)
  moved=$(printf '%s\n' "$ms" | grep -c .)
  med=$(printf '%s\n' "$ms" | awk 'NF { a[n++] = $1 } END { print n ? a[int(n / 2)] : -1 }')
  max=$(printf '%s\n' "$ms" | tail -n 1)
  say "talkback $c: settings, 25 swipes: moved $moved, median ${med} ms, max ${max:-?} ms"
  if [ "$side" = b ]; then
    R[time.med]=$med
    R[time.moved]=$moved
    return 0
  fi
  local bmed=${R[time.med]:--1} bmoved=${R[time.moved]:-0}
  if [ "$bmed" -lt 0 ]; then
    near settingstime "$c: no base to compare with"
  elif [ "$med" -lt 0 ] || [ "$med" -gt $(( bmed * 3 / 2 + 150 )) ]; then
    fail "check $c: settings-swipe-time: median $med ms, base $bmed ms"
  elif [ "$moved" -lt "$bmoved" ]; then
    fail "check $c: settings-swipe-time: moved $moved times, base $bmoved"
  else
    say "check $c: settings-swipe-time: median $med ms (base $bmed ms): OK"
  fi
}

emu_init
[ "$EMU_API" -ge 34 ] || proves_nothing "TalkBack cases on API $EMU_API: the driver injects TalkBack gestures from API 34"
adb shell pm list packages < /dev/null | grep -q "$TB_PKG" || proves_nothing "no TalkBack in the image"
adb root >> "$STEPLOG" 2>&1
adb wait-for-device
emu_sleep 3
logcat_start
a11y_build || proves_nothing "no A11yDriver"
mkdir -p tbshots
for side in b h; do
  if [ "$side" = b ]; then apk=apk-base/android-debug.apk; else apk=apk-head/android-debug.apk; fi
  side_on $side "$apk" || continue
  say "== $side: start"
  install_apk "$apk"
  talkback "${side}c" false
  talkback "${side}m" true
  focusback "${side}f"
  settingstime "${side}s"
  adb uninstall "$PKG" < /dev/null > /dev/null 2>&1
done
finish
