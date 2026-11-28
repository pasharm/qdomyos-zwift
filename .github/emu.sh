#!/bin/bash
# Test only (T-716): a tap on empty space of the settings page drops the focus of a text field and hides the
# keyboard (an item of the Flickable of settings.qml behind the content with a TapHandler, branch
# fix/settings-tap-drops-focus). The empty space is the tallest free run above the keyboard: in the classic look
# that is below the short list of changed settings, out of the content (a handler on the content item missed
# it - T-716 journal), in the modern look a gap between the cards.
# Two sides, the same steps, both looks (m - modern, c - classic):
#   head - the tap on empty space hides the keyboard and takes the focus from the search field;
#   base (origin/master) - the same tap leaves both (nothing on master drops them there) - the defect side.
# The field: the search field of the settings page (settings_search_bar), the list: "Changed" (the changed
# settings - no typing, so API 30 too: typing into this field by adb fails there, qz.sh settings_search).
# Then on both sides the same:
#   - a tap on "Changed" (a button over the TapHandler) still toggles the list: the handler takes no
#     touch a control has taken (qquicksinglepointhandler.cpp v5.15.0, wantsPointerEvent: !exclusiveGrabber);
#   - a drag of the page that starts on empty space (between sections or below them) still scrolls it
#     (QTBUG-75223: TapHandlers in a Flickable could stop the flick on touch in 5.15 - the 6T beta 3769 with
#     the same handler scrolled 8/8, T-716 journal 2026-11-28).
# APKs: inputs head and base (fdroid-android-trial), downloaded by main.yml to apk-head/ and apk-base/.
# One job for both sides: qml_quiet compares the warnings of the head with the base.

. .github/lib.sh
. .github/qz.sh

CHANGED_LIST_RX='^Changed settings \([0-9]+\)$'
# the keyboard of Nexus 6 starts below y 1400 (T-510): taps and drags stay above it
KB_TOP=1350

# field_state <shot>: "focused=<true|false> x y" of the search field in dumps/<shot>.xml
field_state() { "$EMU_PY" .github/t716_field.py "dumps/$1.xml"; }

# kb_state: shown / hidden
kb_state() { if ime_shown; then echo shown; else echo hidden; fi; }

# record <shot>: frame and dump, "keyboard X, field Y" to steps.log; KB, FIELD
record() {
  shot "$1"
  KB=$(kb_state); FIELD=$(field_state "$1")
  say "record $1: keyboard $KB, field $FIELD"
}

# tap_field <case> <shot>: a tap on the search field as the user does; the keyboard and the focus must come
tap_field() {
  local c=$1 st
  dump || return 1
  mkdir -p dumps
  cp ui.xml "dumps/$2-pre.xml"
  st=$(field_state "$2-pre") || { fail "$c: the search field not in the dump"; return 1; }
  set -- ${st#* }
  say "tap the field at $1 $2 ($st)"
  adb shell input tap "$1" "$2" < /dev/null > /dev/null 2>&1
  emu_sleep 2
}

# focus_case <side> <look>
focus_case() {
  local side=$1 look=$2 c="${1}t$2" modern=false g y h st0 st1 y0 y1
  [ "$look" = m ] && modern=true
  start_case "$c" ui_modern=$modern ui_theme_mode=light bluetooth_lastdevice_name=TestBike || return 1
  settings_search_bar "$c" || return 1
  # the list of changed settings: put_conf has changed some (log_debug, ui_modern...), so cards and gaps
  tap_ui '^Changed$' "$CHANGED_LIST_RX" 15 || return 1
  settle
  tap_field "$c" "$c-1" || return 1
  record "$c-1-focused"
  if [ "$KB" != shown ] || [ "${FIELD%% *}" != focused=true ]; then
    fail "$c: keyboard $KB / field $FIELD after the tap on the field - the case proves nothing"
    return 1
  fi
  expect "$c-1-focused" "$CHANGED_LIST_RX" 'the list of changed settings under the field'
  # empty space: a gap between the cards of the list or the page below them, above the keyboard
  g=$("$EMU_PY" .github/t716_field.py "dumps/$c-1-focused.xml" --gap 720 560 "$KB_TOP") || {
    fail "$c: no empty space under x 720 between y 560 and $KB_TOP - the case proves nothing"
    return 1
  }
  set -- $g
  y=$1 h=$2
  say "tap empty space $c at 720 $y (free $h px)"
  adb shell input tap 720 "$y" < /dev/null > /dev/null 2>&1
  emu_sleep 3
  record "$c-2-tapped"
  # the list still there: the tap opened no card
  expect "$c-2-tapped" "$CHANGED_LIST_RX" 'the list still there after the tap on empty space'
  if [ "$side" = h ]; then
    if [ "$KB" = hidden ] && [ "${FIELD%% *}" = focused=false ]; then
      say "check $c-2-tapped: the tap on empty space hid the keyboard and took the focus from the field: OK"
    else
      fail "check $c-2-tapped: after the tap on empty space keyboard $KB, field $FIELD (want hidden, focused=false)"
    fi
  else
    if [ "$KB" = shown ] && [ "${FIELD%% *}" = focused=true ]; then
      say "check $c-2-tapped: master keeps the keyboard and the focus after the tap on empty space (the defect): OK"
    else
      fail "check $c-2-tapped: master after the tap keyboard $KB, field $FIELD - the defect not shown, the head side proves nothing"
    fi
  fi
  # a control over the handler: "Changed" again closes the list, the page sections come back (tap_ui puts
  # the keyboard away first when it is up - the base side)
  tap_ui '^Changed$' '^General Options$' 15 || return 1
  settle
  record "$c-3-list-off"
  expect_not "$c-3-list-off" "$CHANGED_LIST_RX" 'the list closed by the second tap on Changed'
  say "check $c-3-list-off: a tap on Changed still toggles the list: OK"
  # a drag that starts on empty space (between the section titles or below the last one) scrolls the page
  dump || return 1
  cp ui.xml "dumps/$c-4-pre.xml"
  g=$("$EMU_PY" .github/t716_field.py "dumps/$c-4-pre.xml" --gap 720 900 2300) || {
    near drag "$c: no empty space under x 720 between y 900 and 2300 - the drag from empty space not made"
    return 0
  }
  set -- $g
  y=$1
  st0=$(uifind "dumps/$c-4-pre.xml" '^General Options$' --any --first 2>/dev/null)
  y0=$(echo "$st0" | cut -d' ' -f2)
  say "drag $c from empty space: 720 $y -> 720 $((y - 600)); General Options at y ${y0:-?}"
  # swipe_xy says "!!" itself when the screen did not move; the check below says what moved
  swipe_xy 720 "$y" 720 $((y - 600)) 400
  emu_sleep 3
  record "$c-4-dragged"
  st1=$(uifind "dumps/$c-4-dragged.xml" '^General Options$' --any --first 2>/dev/null)
  y1=$(echo "$st1" | cut -d' ' -f2)
  if [ -n "$y0" ] && [ -n "$y1" ] && [ "$y1" -lt $((y0 - 200)) ]; then
    say "check $c-4-dragged: the drag from empty space scrolled the page (General Options $y0 -> $y1): OK"
  elif [ -n "$y0" ] && [ -z "$y1" ]; then
    say "check $c-4-dragged: the drag from empty space scrolled the page (General Options $y0 -> out of the dump): OK"
  else
    fail "check $c-4-dragged: the drag from empty space did not scroll the page (General Options ${y0:-?} -> ${y1:-?})"
  fi
  back_to "$HOME_RX" 20
}

emu_init
logcat_start

for side in b h; do
  if [ "$side" = h ]; then apk=apk-head/android-debug.apk; else apk=apk-base/android-debug.apk; fi
  side_on $side "$apk" || continue
  say "== $side: start"
  install_apk "$apk"
  focus_case $side m
  focus_case $side c
done
# after both sides: it compares the warnings of the head pids with the base ones (run 46105242668 called it per side -
# "no head pid" after the base side)
qml_quiet 'settings' 'settings'

finish
