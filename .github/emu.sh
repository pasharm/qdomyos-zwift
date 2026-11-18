#!/bin/bash
# Test only (T-548): Android 9-11 (API 28-30), the display cutout in landscape. CustomQtActivity.java sets
# LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES below API 31, and main.qml getLeftPadding()/getRightPadding()
# give 0 below API 31 - the window goes under a cutout on the short edge, which is the side edge in landscape,
# and nothing keeps the content out of it. The fix: DEFAULT on API 28-30 (Qt 6 QtWindowInsetsController).
# The cutout - the emulation overlay "tall" (centred on the short edge, so in landscape it is on the side,
# level with the tiles). Measured by t548_cut.py: the safe insets of the cutout from `dumpsys window
# displays`, the content of QZ from the dump - how far its leftmost/rightmost node goes into them.
# Base (apk-base) - the build before the fix: on API 28-30 the content under the cutout (shown, not required).
# Head (apk-head): no content under the cutout on every API, in both looks and both landscape sides.
. .github/lib.sh
. .github/qz.sh

CUTOUT=com.android.internal.display.cutout.emulation.tall

# measure <name>: t548_cut.py on dumps/<name>.xml and the display now; CUT_L CUT_R (px under the cutout),
# CUT_LAND; the line to steps.log. 1 - not measured
measure() {
  local out
  CUT_L= CUT_R= CUT_LAND=
  adb shell dumpsys window displays < /dev/null > "dumps/$1.displays.txt" 2>/dev/null
  out=$("$EMU_PY" .github/t548_cut.py "dumps/$1.xml" "dumps/$1.displays.txt" 2>&1)
  say "cut $1: $out"
  CUT_L=$(echo "$out" | awk '/^cut .* under_left/ {for (i = 1; i < NF; i++) if ($i == "under_left") print $(i + 1)}')
  CUT_R=$(echo "$out" | awk '/^cut .* under_right/ {for (i = 1; i < NF; i++) if ($i == "under_right") print $(i + 1)}')
  CUT_LAND=$(echo "$out" | awk '/^cut .* landscape/ {for (i = 1; i < NF; i++) if ($i == "landscape") print $(i + 1)}')
  [ -n "$CUT_L" ] && [ -n "$CUT_R" ]
}

# rotate <0|1|3>: the user rotation, then a still screen
rotate() {
  adb shell settings put system accelerometer_rotation 0 < /dev/null > /dev/null 2>&1
  adb shell settings put system user_rotation "$1" < /dev/null > /dev/null 2>&1
  emu_sleep 8
  still
}

# land <case> <rotation> <side>: the case turned to landscape; head - nothing under the cutout
land() {
  local c=$1 r=$2 side=$3 n="$1-r$2" under
  rotate "$r"
  shot "$n"
  if ! measure "$n"; then
    fail "$n: not measured"
    return 1
  fi
  if [ "$CUT_LAND" != 1 ]; then
    proves_nothing "$n: QZ did not turn to landscape (user_rotation $r)"
  fi
  under=$((CUT_L + CUT_R))
  if [ "$side" = h ]; then
    if [ "$under" = 0 ]; then say "check $n: no content under the cutout: OK"
    else fail "check $n: content under the cutout (left $CUT_L px, right $CUT_R px)"; fi
  else
    say "base $n: under the cutout left $CUT_L px, right $CUT_R px"
  fi
}

# home_case <case> <side> key=value...: the home page, landscape on both sides, back upright
home_case() {
  local c=$1 side=$2
  shift 2
  start_case "$c" "$@" || return 1
  shot "$c-r0"
  land "$c" 1 "$side"
  land "$c" 3 "$side"
  rotate 0
}

emu_init
say "== pages: the display cutout in landscape (T-548)"

# the cutout before anything starts: an overlay switched mid-run restarts SystemUI (check_emu_script)
adb shell cmd overlay list < /dev/null 2>/dev/null | grep -i cutout >> "$STEPLOG"
adb shell cmd overlay enable "$CUTOUT" < /dev/null >> "$STEPLOG" 2>&1
emu_sleep 10
adb shell cmd overlay list < /dev/null 2>/dev/null | grep -q -F "[x] $CUTOUT" ||
  proves_nothing "the cutout overlay $CUTOUT not enabled"
adb shell dumpsys window displays < /dev/null 2>/dev/null | grep -o -m 1 'DisplayCutout{insets=Rect([^)]*)' > cut0.txt
say "cutout upright: $(cat cut0.txt)"
grep -q 'Rect(0, 0 - 0, 0)' cut0.txt && proves_nothing "the cutout has no insets"
[ -s cut0.txt ] || proves_nothing "no DisplayCutout in dumpsys window displays"
logcat_start

for side in b h; do
  if [ "$side" = b ]; then apk=apk-base/android-debug.apk; else apk=apk-head/android-debug.apk; fi
  side_on "$side" "$apk" || continue
  say "== $side: start"
  install_apk "$apk"
  home_case "${side}m" "$side" ui_modern=true fakedevice_treadmill=true
  home_case "${side}c" "$side" ui_modern=false fakedevice_treadmill=true
done

finish
