#!/bin/bash
# Test only (T-552): the heart rate sensor bar and its list of the modern look by Material 3 (variant B of the
# mockup notes/mockups/t552-hrm-m3-2026-11-14/: the bar as UiNotice, the list card as UiMessageDialog) - before
# (base: feat/modern-ui + the hook) and after (head: the change + the hook). Both builds carry the test hook of
# T-473 (b99a71cb5): with t473_fake_sensors in qz.conf homeform "finds" Forerunner 965 (-58 dBm) 30 s and
# XOSS X2P (-71 dBm) 45 s after it starts, as the background search would (heart_rate_belt_suggest on).
# Cases <side><case>: side b/h; md - modern dark uk (bar, list, Cancel, choice), ml - modern light uk,
# mx - modern dark uk at 170 % text, c - classic en (must stay as on the base).
# Expectations - src/HeartRateSuggestion.qml of the head (9285fa6fc): bar 16 dp from the screen edges
# (:29-31), text 20 dp inside the bar (:55-58), list rows 56 dp or more (:191), title fontTitle (:154);
# base 10 / 12 dp (feat/modern-ui 10f14b93f :26-28, :51). Nexus 6: 3.5 px per dp.
# The modern cases run in Ukrainian: the home page and its support button by their Ukrainian names too (run
# 43588494286: every uk case "home page not shown" while the frame had Пауза/Стоп; uk.ts of feat/modern-ui)
HOME_RX='^(Start|Stop|Pause|Старт|Стоп|Пауза)$'
HOME_READY_RX='^(Contact QZ support|Зв’язатися зі службою підтримки QZ)$'
. .github/lib.sh
. .github/qz.sh

BAR1='^Знайдено пульсометр: Forerunner 965$'
BAR2='^Знайдено пульсометрів: 2$'
LIST='^Виберіть пульсометр$'
ROW1='^Forerunner 965, Сильний сигнал$'
ROW2='^XOSS X2P, Середній сигнал$'

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

# bounds <shot> <regex>: "x1 y1 x2 y2" of the control in the dump of that frame, in steps.log as
# "geom <shot> <what> ..." (the classic sides are compared by these lines at the end)
# (no fail here: geom runs in $(...), a subshell - the caller fails; say only appends to steps.log)
bounds() {
  local at
  at=$(uifind "dumps/$1.xml" "$2" 2>/dev/null) || return 1
  set -- $at
  echo "$5 $6 $7 $8"
}
geom() {
  local b
  if ! b=$(bounds "$1" "$3"); then
    say "geom $1 $2: '$3' not in the dump"
    return 1
  fi
  say "geom $1 $2: $b"
  echo "$b"
}
# geom_must: geom outside a subshell, a failure is red
geom_must() { geom "$@" > /dev/null || fail "geom $1 $2: '$3' not in the dump"; }

# near_px <what> <value> <expected> [tolerance]: a measure within 3 px of the expectation
near_px() {
  local d=$(( $2 - $3 ))
  [ $d -lt 0 ] && d=$(( -d ))
  if [ $d -le "${4:-3}" ]; then
    say "check $1: $2 px (expected $3): OK"
  else
    fail "check $1: $2 px, expected $3"
  fi
}

# tap_gone <regex> <regex that must go>: a tap on the control, then the other one leaves the screen
# (the bar stays in the dump under the modal list, so a landing by a shown control proves nothing)
tap_gone() {
  ensure_app
  dump
  if ! find_ui "$1"; then
    fail "tap '$1': not on the screen ($EMU_WHY)"
    shot "fail-$(date +%s)" now
    return 1
  fi
  set -- $EMU_AT "$1" "$2"
  adb shell input tap "$1" "$2" < /dev/null > /dev/null 2>&1
  say "tap '$9' at $1 $2"
  if wait_gone "${10}" 15; then
    say "outcome '$9': ok ('${10}' gone)"
    return 0
  fi
  fail "after '$9': '${10}' still on the screen"
  shot "fail-$(date +%s)" now
  return 1
}

# open_list <case>: the bar with two sensors, Choose, the list open
open_list() {
  tap_ui '^Вибрати$' "$LIST" 20
}

# modern <case> <theme> [text scale]: the bar with one and two sensors, the list; measured
modern() {
  local c=$1 scale=$3 n1 n2 b row1 row2 x1 side=${1:0:1}
  n1=$(grep -a -c "T-473 test: fake sensor 1" full_logcat.txt)
  n2=$(grep -a -c "T-473 test: fake sensor 2" full_logcat.txt)
  start_case "$c" ui_modern=true ui_theme_mode="$2" app_language=uk fakedevice_treadmill=true \
    heart_rate_belt_suggest=true t473_fake_sensors=true ${scale:+ui_text_scale=$scale} || return 1
  wait_log "$c" "T-473 test: fake sensor 1" "$n1" && wait_ui "$BAR1" 20 && shot "$c-1-one"
  wait_log "$c" "T-473 test: fake sensor 2" "$n2" || return 1
  if ! wait_ui "$BAR2" 20; then
    fail "check $c: the bar with two sensors not shown"
    shot "$c-0-no-bar" now
    return 1
  fi
  shot "$c-2-bar"
  expect "$c-2-bar" '^Вибрати$' "Choose on the bar"
  expect "$c-2-bar" '^Не зараз$' "Not now on the bar"
  if b=$(geom "$c-2-bar" text "$BAR2"); then
    set -- $b
    x1=$1
    # head: 16 dp to the bar + 20 dp to the text; base: 10 + 12 (no system padding at the left in portrait;
    # base 77 px - dump of T-473 dark-2-two-sensors, the same margins)
    if [ -z "$scale" ]; then
      if [ "$side" = h ]; then near_px "$c-2-bar text left" "$x1" 126; else near_px "$c-2-bar text left" "$x1" 77; fi
    fi
  else
    fail "geom $c-2-bar: the bar text not in the dump"
  fi
  open_list || return 1
  shot "$c-3-list"
  expect "$c-3-list" "$LIST" "title"
  expect "$c-3-list" "$ROW1" "row 1 with the signal in words"
  expect "$c-3-list" "$ROW2" "row 2 with the signal in words"
  expect "$c-3-list" '^Скасувати$' "Cancel"
  geom_must "$c-3-list" title "$LIST"
  if row1=$(geom "$c-3-list" row1 "$ROW1") && row2=$(geom "$c-3-list" row2 "$ROW2"); then
    set -- $row1
    local h1=$(( $4 - $2 )) y1=$2
    set -- $row2
    # strongest first; a row 56 dp or more (196 px)
    if [ "$y1" -lt "$2" ]; then say "check $c-3-list order: OK"; else fail "check $c-3-list order: row 1 not above row 2"; fi
    if [ "$h1" -ge 193 ]; then say "check $c-3-list row height: $h1 px: OK"; else fail "check $c-3-list row height: $h1 px < 196"; fi
  else
    fail "geom $c-3-list: rows not in the dump"
  fi
  # the card inside the page: Cancel above the navigation bar
  if b=$(geom "$c-3-list" cancel '^Скасувати$'); then
    set -- $b
    if [ "$4" -le 2390 ]; then say "check $c-3-list Cancel on the screen: OK"; else fail "check $c-3-list Cancel at y $4, below 2390"; fi
  else
    fail "geom $c-3-list: Cancel not in the dump"
  fi
  tap_gone '^Скасувати$' "$LIST" || return 1
  shot "$c-4-cancelled"
  expect "$c-4-cancelled" "$BAR2" "the bar stays after Cancel"
  [ "$c" = "${side}md" ] || return 0
  open_list || return 1
  tap_gone "$ROW1" 'Знайдено пульсометр.*' || return 1
  shot "$c-5-chosen"
  if adb shell "run-as $PKG cat '$CONF'" < /dev/null | tr -d '\r' | grep -q -a '^heart_rate_belt_name=Forerunner 965$'; then
    say "check $c-5-chosen: heart_rate_belt_name saved: OK"
  else
    fail "check $c-5-chosen: heart_rate_belt_name not saved"
  fi
}

# classic <case>: the bar and the list of the classic look, as before (dBm in the row text, no Cancel)
classic() {
  local c=$1 n2
  n2=$(grep -a -c "T-473 test: fake sensor 2" full_logcat.txt)
  start_case "$c" ui_modern=false app_language=en fakedevice_treadmill=true \
    heart_rate_belt_suggest=true t473_fake_sensors=true || return 1
  wait_log "$c" "T-473 test: fake sensor 2" "$n2" || return 1
  if ! wait_ui '^Heart rate sensors found: 2$' 20; then
    fail "check $c: the bar with two sensors not shown"
    shot "$c-0-no-bar" now
    return 1
  fi
  shot "$c-2-bar"
  geom_must "$c-2-bar" text '^Heart rate sensors found: 2$'
  geom_must "$c-2-bar" choose '^Choose$'
  tap_ui '^Choose$' '^Choose a heart rate sensor$' 20 || return 1
  shot "$c-3-list"
  # the row reads the name alone (Accessible.name), the dBm is in its text (frame) - dump of T-473 classic-3-list
  expect "$c-3-list" '^Forerunner 965$' "row named by the sensor alone"
  expect_not "$c-3-list" '^Cancel$' "no Cancel"
  expect_not "$c-3-list" '.*Strong signal.*' "no signal in words"
  geom_must "$c-3-list" title '^Choose a heart rate sensor$'
  geom_must "$c-3-list" row1 '^Forerunner 965$'
}

# same_classic: the geom lines of the classic case equal on both sides (the classic look unchanged)
same_classic() {
  local nb nh
  grep -a '^geom bc-' "$STEPLOG" | sed 's/^geom bc-/geom c-/' > .geom_b.txt
  grep -a '^geom hc-' "$STEPLOG" | sed 's/^geom hc-/geom c-/' > .geom_h.txt
  nb=$(wc -l < .geom_b.txt); nh=$(wc -l < .geom_h.txt)
  if [ "$nb" = 0 ] || [ "$nh" = 0 ]; then
    say "classic geometry not compared (base $nb, head $nh lines)"
  elif cmp -s .geom_b.txt .geom_h.txt; then
    say "check classic geometry: $nh measures as on the base: OK"
  else
    diff .geom_b.txt .geom_h.txt >> "$STEPLOG"
    fail "check classic geometry: differs from the base"
  fi
}

# qml_quiet: no QML warning of HeartRateSuggestion.qml or UiButton.qml from the processes of a side
qml_quiet() {
  local s pid n
  for s in b h; do
    n=0
    for pid in $(grep -a "^pid $s" "$STEPLOG" | cut -d' ' -f3); do
      n=$(( n + $(awk -v p="$pid" '$3 == p' full_logcat.txt | grep -a -c -E 'qrc:/(HeartRateSuggestion|UiButton)[.]qml') ))
    done
    if [ "$(grep -a -c "^pid $s" "$STEPLOG")" = 0 ]; then
      say "qml $s: no process"
    elif [ "$n" = 0 ]; then
      say "check qml $s: no warning of HeartRateSuggestion.qml / UiButton.qml: OK"
    else
      for pid in $(grep -a "^pid $s" "$STEPLOG" | cut -d' ' -f3); do
        awk -v p="$pid" '$3 == p' full_logcat.txt | grep -a -E 'qrc:/(HeartRateSuggestion|UiButton)[.]qml' | head -n 10 >> "$STEPLOG"
      done
      [ "$s" = h ] && fail "check qml h: $n warnings" || say "qml b: $n warnings (base)"
    fi
  done
}

emu_init
logcat_start
adb shell cmd uimode night no < /dev/null > /dev/null 2>&1

for side in b h; do
  if [ "$side" = b ]; then apk=apk-base/android-debug.apk; else apk=apk-head/android-debug.apk; fi
  side_on $side "$apk" || continue
  say "== $side: start"
  install_apk "$apk"
  modern "${side}md" dark
  modern "${side}ml" light
  modern "${side}mx" dark 170
  classic "${side}c"
  adb shell am force-stop "$PKG" < /dev/null > /dev/null 2>&1
done

logcat_stop
same_classic
qml_quiet
finish
