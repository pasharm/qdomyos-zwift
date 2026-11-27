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
  local look=$1 c="s$1" modern=false
  [ "$look" = m ] && modern=true
  start_case "$c" ui_modern=$modern ui_theme_mode=light bluetooth_lastdevice_name=TestBike || return 1
  settings_search "$c" "Smooth" '^Smooth Chart Lines.*' || { back_to "$HOME_RX" 20; return 1; }
  expect "$c-1-results" '^Smooth Chart Lines.*' "the search finds the setting"
  back_to "$HOME_RX" 20
}

# charts <value>: the Charts page while the fake bike runs, then Stop and the pictures of the mail
charts() {
  local v=$1 c="c$1" n0 live0 live saved0 saved loads0 i
  HOME_READY_RX=
  start_case "$c" ui_modern=false ui_theme_mode=light applewatch_fakedevice=true bluetooth_lastdevice_name=TestBike \
    chart_smooth_lines=$v confirm_stop_workout=false || return 1
  # the fake bike starts the session: some seconds of points before the page opens
  emu_sleep 20
  loads0=$(count_log '"Path" "chartjs/chart.htm"')
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
  saved0=$(count_log 'savechart')
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
  # the pictures are taken at the end of the first animation of each chart
  emu_sleep 30
  still
  shot "$c-3-end"
  saved=$(( $(count_log 'savechart') - saved0 ))
  say "count $c-3-end: savechart lines after Stop (chart_smooth_lines=$v): $saved"
  echo "$v $saved" >> saved.txt
  back_to "$HOME_RX" 20
}

# saved_same: the same number of savechart lines after Stop with every value, and not 0
saved_same() {
  local first="" v n ok=1
  [ -s saved.txt ] || { fail "check saved: no Stop case counted"; return 1; }
  while read -r v n; do
    [ "${n:-0}" -gt 0 ] || { fail "check saved: no savechart after Stop with chart_smooth_lines=$v"; ok=0; }
    [ -z "$first" ] && first=$n
    [ "$n" = "$first" ] || { fail "check saved: $n savechart lines with chart_smooth_lines=$v, $first with the first value"; ok=0; }
  done < saved.txt
  [ "$ok" = 1 ] && say "check saved: the same $first savechart lines after Stop with $(cut -d' ' -f1 saved.txt | tr '\n' ' '): OK"
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
