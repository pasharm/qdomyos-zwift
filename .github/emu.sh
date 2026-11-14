#!/bin/bash
# Test only (T-554): the press of the inverse buttons of the heart rate sensor bar (UiButton.modernInverse,
# ripple colour alpha(bg, 0.16) of T-473) without the ripple wave - before (base: feat/modern-ui ba8e4563e +
# the hook) and after (head: c001ae733 "pill buttons press without the square wave" + the hook). Both builds
# carry the test hook of T-473 (5b1f9e325): with t473_fake_sensors in qz.conf homeform "finds" two sensors
# 30 s and 45 s after it starts. Scenario of the bar - test/t552-emu (T-552).
# Cases <side><case>: side b/h; d - modern dark uk, l - modern light uk.
# Per case: the bar at rest, a frame in the middle of a 3 s press on Вибрати (highlighted button), the same on
# Не зараз (flat button) - the frames of the press are compared with the bar at rest and with the other side
# by eye and by emu_frame.py; the scenario itself checks only that the press frame differs from rest.
HOME_RX='^(Start|Stop|Pause|Старт|Стоп|Пауза)$'
HOME_READY_RX='^(Contact QZ support|Зв’язатися зі службою підтримки QZ)$'
. .github/lib.sh
. .github/qz.sh

BAR2='^Знайдено пульсометрів: 2$'
LIST='^Виберіть пульсометр$'

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

# hold <name> <regex>: a 3 s press on the control, the frame 1.5 s into it (no dump during the press - the
# frame must hold the press); the frame differs from the bar at rest in the rows of the button
hold() {
  local name=$1 rx=$2 x y pid
  ensure_app
  dump
  if ! find_ui "$rx"; then
    fail "hold '$rx': not on the screen ($EMU_WHY)"
    shot "fail-$(date +%s)" now
    return 1
  fi
  set -- $EMU_AT
  x=$1; y=$2
  adb shell input swipe "$x" "$y" "$x" "$y" 3000 < /dev/null > /dev/null 2>&1 &
  pid=$!
  sleep 1.5
  adb exec-out screencap -p < /dev/null > "$name.png" 2>/dev/null
  wait "$pid"
  say "hold '$rx' at $x $y: frame $name"
  [ -s "$name.png" ] || { fail "hold $name: no frame"; return 1; }
  return 0
}

modern() {
  local c=$1 n2
  n2=$(grep -a -c "T-473 test: fake sensor 2" full_logcat.txt)
  start_case "$c" ui_modern=true ui_theme_mode="$2" app_language=uk fakedevice_treadmill=true \
    heart_rate_belt_suggest=true t473_fake_sensors=true || return 1
  wait_log "$c" "T-473 test: fake sensor 2" "$n2" || return 1
  if ! wait_ui "$BAR2" 20; then
    fail "check $c: the bar with two sensors not shown"
    shot "$c-0-no-bar" now
    return 1
  fi
  shot "$c-1-rest"
  expect "$c-1-rest" '^Вибрати$' "Choose on the bar"
  expect "$c-1-rest" '^Не зараз$' "Not now on the bar"
  hold "$c-2-press-choose" '^Вибрати$' || return 1
  # the release on Вибрати opens the list: close it
  if wait_ui "$LIST" 15; then
    tap_ui '^Скасувати$' "$BAR2" 20 || return 1
  else
    fail "check $c: the list not opened by the release on Вибрати"
    shot "$c-2-no-list" now
    return 1
  fi
  hold "$c-3-press-notnow" '^Не зараз$' || return 1
}

emu_init
logcat_start
adb shell cmd uimode night no < /dev/null > /dev/null 2>&1

for side in b h; do
  if [ "$side" = b ]; then apk=apk-base/android-debug.apk; else apk=apk-head/android-debug.apk; fi
  side_on $side "$apk" || continue
  say "== $side: start"
  install_apk "$apk"
  modern "${side}d" dark
  modern "${side}l" light
  adb shell am force-stop "$PKG" < /dev/null > /dev/null 2>&1
done

logcat_stop
finish
