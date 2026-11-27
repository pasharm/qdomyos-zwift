#!/bin/bash
# Test only (T-720): Smooth Chart Lines (chart_smooth_lines: 0 Off, 1 Auto, 2..6 - 3/5/10/15/30 s) - the PR branch
# feat/chart-smooth-lines. The head only (Off = master is proved by tests/test_chart_smoothing.py and the stand).
# Checks:
#   - the settings search finds "Smooth Chart Lines" (the catalog entry), both looks
#   - the Charts page (chartjs/dochart.js) with Off, Auto and 5 s opens on the WebView of the API while the fake bike
#     runs, and the page keeps polling (getsessionarray) - the smoothed lines do not break the live redraw
#   - Stop (classic look): the app opens the Charts page again and it sends its pictures for the mail (savechart);
#     the count is the same with Off, Auto and 5 s - the smoothing takes no picture more or less
#   - no uncaught JS error of dochart.js, no QML warning of ChartJsTest.qml (settings.qml - printed)

. .github/lib.sh
. .github/qz.sh

# count_log <text>: lines of full_logcat.txt with the text
count_log() { grep -a -c -F -- "$1" full_logcat.txt; }

# search <look>: the settings search finds the new setting
search() {
  # names start with h: qml_quiet reads the head pid by "^pid h"
  local look=$1 c="hs$1" modern=false rc
  [ "$look" = m ] && modern=true
  # the settings search is not on API 30 (settings_search skips it there)
  [ "$EMU_API" = 30 ] && { say "$c: no settings search on API 30 - skipped"; return 1; }
  start_case "$c" ui_modern=$modern ui_theme_mode=light bluetooth_lastdevice_name=TestBike || return 1
  rc=0
  settings_search "$c" "Smooth" '^Smooth Chart Lines(: .*)?$' || rc=$?
  if [ "$rc" = 2 ]; then
    fail "check $c: the settings search found nothing for Smooth"
  fi
  [ "$rc" = 0 ] || { back_to "$HOME_RX" 20; return 1; }
  expect "$c-1-results" '^Smooth Chart Lines(: .*)?$' "the search finds the setting"
  back_to "$HOME_RX" 20
}

# charts <value>: the Charts page while the fake bike runs, then Stop and the pictures of the mail
charts() {
  local v=$1 c="hc$1" live0 live mark saved last loads0 i
  HOME_READY_RX=
  start_case "$c" ui_modern=false ui_theme_mode=light applewatch_fakedevice=true bluetooth_lastdevice_name=TestBike \
    chart_smooth_lines=$v confirm_stop_workout=false || return 1
  # the fake bike starts the session: some seconds of points before the page opens
  emu_sleep 20
  open_drawer '^Charts$' && tap_ui '^Charts$' '^◄$' 30 || { fail "$c: Charts did not open"; return 1; }
  wait_log '"Path" "chartjs/chart.htm"' 60 || return 1
  emu_sleep 6
  still
  shot "$c-1-page"
  live0=$(count_log '"msg":"getsessionarray')
  emu_sleep 10
  live=$(( $(count_log '"msg":"getsessionarray') - live0 ))
  if [ "$live" -gt 0 ]; then
    say "check $c-1-page: the page asked the session $live times in 10 s (chart_smooth_lines=$v): OK"
  else
    fail "check $c-1-page: no getsessionarray in 10 s (chart_smooth_lines=$v) - no live redraw"
  fi
  shot "$c-2-live"
  back_to "$HOME_RX" 20 || return 1
  emu_sleep 5
  loads0=$(count_log '"Path" "chartjs/chart.htm"')
  # the line of the log from which the replies to savechart of this Stop are counted
  mark=$(( $(wc -l < full_logcat.txt) + 1 ))
  # by hand: what comes after Stop (the RPE question or the Charts page) is judged by the log below
  still
  if dump && find_ui '^Stop$' --first; then
    say "tap Stop at $EMU_AT"
    adb shell input tap $EMU_AT < /dev/null > /dev/null 2>&1
  else
    shot "$c-3-no-stop" now
    fail "$c: no Stop on the home page"
    return 1
  fi
  # the RPE question after Stop (rpeFeelPopupEnabled) - skipped when shown
  if wait_ui '^Skip$' 8; then
    still
    if dump && find_ui '^Skip$' --first; then
      say "tap Skip of the RPE question at $EMU_AT"
      adb shell input tap $EMU_AT < /dev/null > /dev/null 2>&1
    fi
  fi
  for i in $(seq 1 30); do
    [ "$(count_log '"Path" "chartjs/chart.htm"')" -gt "$loads0" ] && break
    emu_sleep 2
  done
  if [ "$(count_log '"Path" "chartjs/chart.htm"')" -le "$loads0" ]; then
    shot "$c-3-no-end-page" now
    fail "check $c-3: the Charts page did not open after Stop"
    return 1
  fi
  # the pictures are taken at the end of the first animation of each chart: the names of the pictures the app
  # answered (R_savechart), counted once each, until the count stays the same 10 s (at most 90 s). The answer is
  # indented JSON (QJsonDocument::toJson), one logcat line per line: "name" is two lines above "msg"
  # (notes/emu/t642-44933490375-r2, api30 full_logcat.grep.txt:5005-5009)
  last=-1 saved=0
  for i in $(seq 1 9); do
    emu_sleep 10
    saved=$(tail -n +"$mark" full_logcat.txt | grep -a -B2 -F '"msg": "R_savechart"' | grep -a -o '"name": "[^"]*"' \
      | sort -u | wc -l)
    [ "$saved" -gt 0 ] && [ "$saved" = "$last" ] && break
    last=$saved
  done
  still
  shot "$c-3-end"
  say "count $c-3-end: pictures saved after Stop (chart_smooth_lines=$v): $saved"
  echo "$v $saved" >> saved.txt
  back_to "$HOME_RX" 20
}

# saved_same: the same number of saved pictures (R_savechart names) after Stop with every value, and not 0
saved_same() {
  local first="" v n ok=1
  [ -s saved.txt ] || { fail "check saved: no Stop case counted"; return 1; }
  while read -r v n; do
    [ "${n:-0}" -gt 0 ] || { fail "check saved: no savechart after Stop with chart_smooth_lines=$v"; ok=0; }
    [ -z "$first" ] && first=$n
    [ "$n" = "$first" ] || { fail "check saved: $n saved pictures with chart_smooth_lines=$v, $first with the first value"; ok=0; }
  done < saved.txt
  [ "$ok" = 1 ] && say "check saved: the same $first saved pictures after Stop with $(cut -d' ' -f1 saved.txt | tr '\n' ' '): OK"
}

# js_quiet: no uncaught JS error of dochart.js in the log
js_quiet() {
  local n
  n=$(grep -a -c -E 'Uncaught.*dochart|dochart\.js.*Uncaught' full_logcat.txt)
  if [ "${n:-0}" = 0 ]; then
    say "check js: no uncaught error of dochart.js ($(grep -a -c 'Uncaught' full_logcat.txt) uncaught in all): OK"
  else
    grep -a -E 'Uncaught.*dochart|dochart\.js.*Uncaught' full_logcat.txt | head -5 >> "$STEPLOG"
    fail "check js: $n uncaught error(s) of dochart.js"
  fi
}

emu_init
logcat_start

for side in h; do
  apk=apk-head/android-debug.apk
  side_on $side "$apk" || continue
  say "== $side: start"
  install_apk "$apk"
  rm -f saved.txt
  search m
  search c
  charts 0
  charts 1
  charts 3
  saved_same
  js_quiet
  # without the base side the warnings master gives too (settings.qml ScrollView) are only printed for settings.qml
  qml_quiet 'settings|ChartJsTest' 'ChartJsTest'
done

finish
