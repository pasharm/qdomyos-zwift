#!/bin/bash
# Test only (T-647): the accent from the wallpaper (Material You) in the modern look.
#   head (h): feat/modern-wallpaper-accent d231ba5aa (test/t647) - settings.qml: "Wallpaper color" first in the
#             accent row where Android 12+ gives the palette (window.ui.systemAccentAvailable, main.qml:370);
#             window.ui.accentName (main.qml:427) - a saved "system" with no palette is violet, the row marks Violet
#   base (b): origin/master 768f306a4 (test/t647-master) - six swatches, "system" unknown: no swatch marked
# Cases (DEV keeps the wizard closed; the light look unless said):
#   s - ui_accent=system saved: head API 31+ - "Wallpaper color" shown and marked, Violet not; Blue tapped -
#       Blue marked, qz.conf ui_accent=blue after a restart; "Wallpaper color" tapped - marked, ui_accent=system after a
#       restart and marked again.
#       head API 30 - no "Wallpaper color", Violet marked (the fix of F1). base - no "Wallpaper color", and
#       Violet NOT marked: the defect the head fixes (a base with Violet marked did not reproduce it - red); then
#       Blue tapped and kept after a restart, as the head, for a pair of the QML warnings of that path
#   d - the same in the dark look: the mark, the frame (the colour of the swatch and of the page accent - for the eye)
#   l - text at 170 % (ui_text_scale_system=false): the swatches and the label "Accent color" all on the screen,
#       the label not over the first swatch, the last swatch within the screen
#   g - the list "Changed": the card of the accent - head API 31+ "Wallpaper color", head API 30 "Violet"
#       (settings.qml searchValueText, accentName); base - printed only
# Anchors: settings.qml of d231ba5aa - section "General UI Options" (8476), label "Accent color" (8596), swatches
# RadioButton (8622) named "Wallpaper color", "Violet" ... "Pink" (8626); master 768f306a4 - the same without
# "Wallpaper color" (Accessible.name of the swatch, settings.qml:8619)
# One job for both sides: qml_quiet compares the warnings of the head with the base
. .github/lib.sh
. .github/qz.sh

# no fakedevice_treadmill: a running workout freezes the home page of the modern look (T-545); a device name with
# no device keeps the first-run wizard closed (homeform.h firstRun())
DEV="bluetooth_lastdevice_name=T647-NONE"
SWATCHES='^(Wallpaper color|Violet|Blue|Teal|Green|Orange|Pink)$'

# head with the wallpaper palette: API 31+ (androidstatusbar.cpp systemAccentColor: apiLevel() < 31 - empty)
palette() { [ "${1:0:1}" = h ] && [ "${EMU_API:-35}" -ge 31 ]; }

# accent_row <case> <shot>: the settings page, General UI Options open, the accent row on the screen
accent_row() {
  settings_open || { shot "$1-0-no-settings" now; return 1; }
  scroll_to '^General UI Options$' 15 --exact --first || return 1
  tap_ui '^General UI Options$' '^Modern interface$' --first --land-below || { shot "$1-0-closed" now; return 1; }
  settle
  scroll_to '^Pink$' 10 --exact --first || { shot "$1-0-no-row" now; return 1; }
  settle
  shot "$2"
}

# marked <case> <shot> <name> <true|false> <what>: the swatch <name> checked or not in the dump of <shot>
marked() {
  local got
  got=$(checked_of "dumps/$2.xml" "^$3\$")
  if [ "$got" = "$4" ]; then
    say "check $2: $5: '$3' checked=$got: OK"
  else
    fail "check $2: $5: '$3' checked='$got', expected $4"
  fi
}

# conf_is <case> <key> <value>: the value stored in qz.conf
conf_is() {
  local got
  got=$(adb shell "run-as $PKG cat '$CONF'" < /dev/null 2>/dev/null | tr -d '\r' | grep -a "^$2=" | head -n 1 | cut -d= -f2-)
  if [ "$got" = "$3" ]; then
    say "check $1: qz.conf $2=$got: OK"
  else
    fail "check $1: qz.conf $2='$got', expected '$3'"
  fi
}

# restart <case>: back to the home page, a pause for Qt.labs.settings to write, QZ stopped and started again
# (qz.conf kept: not start_case, which writes it anew) - as restart of notes/emu/t198-45307253131/emu.sh
restart() {
  back_to "$HOME_RX" 20 || return 1
  emu_sleep 6
  adb shell am force-stop "$PKG" < /dev/null > /dev/null 2>&1
  emu_sleep 2
  adb shell am start -n "$PKG/$PKG.CustomQtActivity" < /dev/null > /dev/null 2>&1
  wait_home || { fail "$1: home page not shown after the restart"; shot "$1-0-no-home" now; return 1; }
  say "pid $1 $(adb shell pidof "$PKG" < /dev/null | tr -d '\r')"
}

# pick <case> <name>: the swatch tapped, the row still
pick() {
  tap_ui "^$2\$" "^$2\$" --first || { shot "$1-0-not-picked" now; return 1; }
  settle
}

# saved <case> <dark|light>: ui_accent=system saved before the start
saved() {
  local c=$1 mode=$2
  start_case "$c" ui_modern=true ui_theme_mode="$mode" ui_accent=system $DEV || return 1
  accent_row "$c" "$c-1-open" || return 1
  # the height of the label at the text size of the system (100 %): the proof of 170 % in the case l
  if [ "$mode" = light ] && find_ui '^Accent color$' --first; then
    read -r -a ACC_AT <<< "$EMU_AT"
    ACC_H=$((ACC_AT[7] - ACC_AT[5]))
    say "$c: the label 'Accent color' ${ACC_H} px high at 100 %"
  fi
  if palette "$c"; then
    expect "$c-1-open" '^Wallpaper color$' "the wallpaper swatch where Android gives the palette"
    marked "$c" "$c-1-open" 'Wallpaper color' true "the saved wallpaper colour marked"
    marked "$c" "$c-1-open" 'Violet' false "Violet not marked with the wallpaper colour"
  else
    expect_not "$c-1-open" '^Wallpaper color$' "no wallpaper swatch without the palette (API $EMU_API, side ${c:0:1})"
    if [ "${c:0:1}" = h ]; then
      marked "$c" "$c-1-open" 'Violet' true "the saved wallpaper colour with no palette shown as Violet"
    else
      # master: accentName is the raw "system" (main.qml:385 of 768f306a4), Accessible.checked compares the swatch
      # names with it (settings.qml:8622), none is "system"
      marked "$c" "$c-1-open" 'Violet' false "master reproduces the defect: no swatch marked"
    fi
  fi
  [ "$mode" = dark ] && return 0
  # Blue and a restart on the base side too (any API): the same pick and the same way out of the page as the
  # head, so a QML warning of the head has its pair on master (UiSettingFrames.qml:114 after Blue on hs
  # only, run 46091320164)
  palette "$c" || [ "${c:0:1}" = b ] || return 0
  pick "$c" Blue || return 1
  dump
  shot "$c-2-blue"
  marked "$c" "$c-2-blue" 'Blue' true "Blue marked after the tap"
  if palette "$c"; then
    marked "$c" "$c-2-blue" 'Wallpaper color' false "the wallpaper swatch not marked after Blue"
  fi
  # each pick written and read back with a value other than the one the case started with (put_conf system):
  # a write that does nothing would keep system and fail the first check
  restart "$c-r1" || return 1
  conf_is "$c-r1" ui_accent blue
  accent_row "$c" "$c-3-restart" || return 1
  marked "$c" "$c-3-restart" 'Blue' true "Blue kept after the restart"
  palette "$c" || return 0
  pick "$c" 'Wallpaper color' || return 1
  dump
  shot "$c-4-wallpaper"
  marked "$c" "$c-4-wallpaper" 'Wallpaper color' true "the wallpaper swatch marked after the tap"
  restart "$c-r2" || return 1
  conf_is "$c-r2" ui_accent system
  accent_row "$c" "$c-5-restart" || return 1
  marked "$c" "$c-5-restart" 'Wallpaper color' true "the wallpaper colour kept after the restart"
}

# bounds_of <dump> <name>: x1 y1 x2 y2 of the node content-desc="<name>" as the dump has it
bounds_of() {
  grep -o "content-desc=\"$2\"[^>]*bounds=\"[^\"]*\"" "$1" | head -n 1 | sed 's/.*bounds="//; s/"$//; s/\]\[/ /; s/[][]//g; s/,/ /g'
}

# large <case>: text at 170 %, the row of swatches on the screen whole
large() {
  local c=$1 n=0 s want lab ref pk lh
  start_case "$c" ui_modern=true ui_theme_mode=light ui_accent=system ui_text_scale_system=false ui_text_scale=170 $DEV || return 1
  accent_row "$c" "$c-1-open" || return 1
  dump || return 1
  for s in 'Wallpaper color' Violet Blue Teal Green Orange Pink; do
    find_ui "^$s\$" --first > /dev/null 2>&1 || continue
    n=$((n + 1))
  done
  if palette "$c"; then want=7; else want=6; fi
  [ "$n" = "$want" ] && say "check $c-1-open: $n swatches on the screen at 170 %: OK" \
    || fail "check $c-1-open: $n swatches on the screen at 170 %, expected $want"
  # 170 % in effect: the label taller than at 100 % in the case s of this side (put_conf checks the key only)
  find_ui '^Accent color$' --first || { fail "check $c-1-open: no label 'Accent color' ($EMU_WHY)"; return 1; }
  read -r -a lab <<< "$EMU_AT"
  lh=$((lab[7] - lab[5]))
  if [ -n "$ACC_H" ]; then
    [ $((lh * 10)) -ge $((ACC_H * 14)) ] && say "check $c-1-open: the label ${lh} px against ${ACC_H} px at 100 %: 170 % in effect: OK" \
      || fail "check $c-1-open: the label ${lh} px against ${ACC_H} px at 100 % - 170 % not in effect, the run proves nothing"
  else
    near scale "$c: no height at 100 % (case s skipped) - the label ${lh} px, 170 % not proven"
  fi
  # Pink whole: the dump bounds are clipped to the screen, so a swatch cut by the edge is narrower than Violet
  read -r -a ref <<< "$(bounds_of "dumps/$c-1-open.xml" Violet)"
  read -r -a pk <<< "$(bounds_of "dumps/$c-1-open.xml" Pink)"
  if [ ${#ref[@]} = 4 ] && [ ${#pk[@]} = 4 ]; then
    if [ $((pk[2] - pk[0] - ref[2] + ref[0])) -ge -2 ]; then
      say "check $c-1-open: Pink ${pk[0]}..${pk[2]} as wide as Violet ${ref[0]}..${ref[2]}: whole: OK"
    else
      fail "check $c-1-open: Pink ${pk[0]}..${pk[2]} narrower than Violet ${ref[0]}..${ref[2]}: cut by the edge"
    fi
  else
    fail "check $c-1-open: no bounds of Violet/Pink in the dump"
  fi
  # the label against the swatches: their nodes are cells of UiSettingsRow and never overlap, the ink of a long
  # label may - by the frame only, for the eye
  say "$c: the label and the row at 170 % - on the frame $c-1-open.png"
}

# changed <case>: the list "Changed" of the settings search, the card of the accent
changed() {
  local c=$1 name want
  start_case "$c" ui_modern=true ui_theme_mode=light ui_accent=system $DEV || return 1
  settings_search_bar "$c" || return 1
  tap_ui "$SEARCH_BAR_RX" '^Changed settings.*|^No changed settings$' --first || { shot "$c-0-no-list" now; return 1; }
  settle
  scroll_to '^Accent color.*' 15 --first --exact || { shot "$c-0-no-card" now; return 1; }
  shot "$c-1-card"
  name=$(uifind ui.xml '^Accent color.*' --first --name 2>/dev/null)
  say "$c: the card '$name'"
  [ "${c:0:1}" = h ] || return 0
  if palette "$c"; then want='Wallpaper color'; else want='Violet'; fi
  case $name in
    *"$want"*) say "check $c-1-card: the card shows '$want': OK" ;;
    *) fail "check $c-1-card: the card '$name', expected '$want'" ;;
  esac
}

emu_init
logcat_start

for side in h b; do
  if [ "$side" = b ]; then apk=apk-base/android-debug.apk; else apk=apk-head/android-debug.apk; fi
  side_on "$side" "$apk" || continue
  say "== $side: start"
  install_apk "$apk"
  saved "${side}s" light
  saved "${side}d" dark
  large "${side}l"
  changed "${side}g"
done

qml_quiet 'settings|main|UiButton|UiSettingFrames|UiIcon|UiFrame'
finish
