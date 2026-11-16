#!/bin/bash
# Test only (T-265, T-560): what the real TalkBack (Google TalkBack 15, image API 35) finds in the side menu
# and in the heart rate sensor bar - before (base: test/t265-master = origin/master fb8bd3a22 + the T-473 hook)
# and after (head: test/t265-diag = the same + no Accessible.ignored on the Drawer + a StaticText node
# focusable, as Qt does since 5.15.9 - QTBUG-77371). A diagnostic run: the tree with the menu open ('list'),
# a touch on a menu entry, swipes from the menu button, a double tap on Settings; the bar text by touch and
# by a swipe left from Choose. The head is red only where it is not better than the base; the findings are in
# the "talkback <case>:" lines.
# Base master: main.qml:1880 Accessible.ignored: !drawer.opened on the Drawer (QTBUG-83738 in Qt 5.15.0),
# the menu entries of the classic look - ItemDelegate (main.qml ~1930-2010), of the modern look - UiDrawerItem.
# The bar: HeartRateSuggestion.qml, the Label of the text and the buttons Choose / Not now / Don't ask again;
# with t473_fake_sensors homeform "finds" two sensors 30 s and 45 s after it starts (hook b99a71cb5).
# Cases <side><case>: side b/h; c - classic en, m - modern en (both: menu, then the bar).
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
  local c=$1 modern=$2 n2 menu entry
  if [ "$modern" = true ]; then menu='Main menu'; else menu='◄'; fi
  n2=$(grep -a -c "T-473 test: fake sensor 2" full_logcat.txt)
  start_case "$c" ui_modern=$modern app_language=en fakedevice_treadmill=true \
    heart_rate_belt_suggest=true t473_fake_sensors=true || return 1
  wait_log "$c" "T-473 test: fake sensor 2" "$n2" || return 1
  tb_on
  # the menu: opened by a double tap on its button; the tree with it open; a touch on Settings and swipes
  drv "$c-menu" --keep "focus:$menu" 'sleep:1500' "dtap:$menu" 'sleep:3000' 'list' 'find:Settings' \
    'touch:Settings' 'swipe:right' 'swipe:right' 'swipe:right'
  # from the menu button with the menu open: what a swipe right reaches next
  drv "$c-menu2" --keep 'touch:Settings' "dtap:Settings" 'sleep:4000' 'find:Settings' 'focused'
  # the settings page, if it opened, back to the home page (the system back closes a page of QZ)
  adb shell input keyevent 4 < /dev/null > /dev/null 2>&1
  emu_sleep 3
  for i in 1 2 3 4; do
    drv "$c-wait$i" --keep 'sleep:3000' 'find:Heart rate sensors found'
    grep -a -q "^find:Heart rate sensors found: '" "drv/$c-wait$i.txt" && break
    near tree "$c: no bar in the TalkBack tree, look $i"
  done
  # first a touch at another point: a second touch at the same point gives TalkBack no new event
  drv "$c-bar" --keep 'touch:Choose' 'touch:Heart rate sensors found' 'touch:Choose' 'swipe:left' 'focused'
  adb pull /data/local/tmp/tbshots "tbshots/$c" < /dev/null >> "$STEPLOG" 2>&1
  tb_off
  entry=$(grep -a -m1 "^find:Settings: '" "drv/$c-menu.txt")
  say "talkback $c: Settings node with the menu open: ${entry:-NOT FOUND}"
  compare "$c" "menu-entry-visible" "$(yn "^find:Settings: 'Settings' .* visible=true" "$c-menu")"
  compare "$c" "menu-entry-by-touch" "$(yn "^touch:Settings: focused 'Settings'" "$c-menu")"
  compare "$c" "menu-entry-opens-settings" "$(yn "^dtap:Settings: focused 'Settings'" "$c-menu2")"
  compare "$c" "bar-text-by-touch" "$(yn "^touch:Heart rate sensors found: focused 'Heart rate sensors found: 2'" "$c-bar")"
  compare "$c" "bar-text-by-swipe-left" "$(yn "^swipe:left: focused 'Heart rate sensors found: 2'" "$c-bar")"
  tb_check "^touch:Choose: focused 'Choose'" "$c-bar" "Choose by touch (as before)"
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
  adb uninstall "$PKG" < /dev/null > /dev/null 2>&1
done
finish
