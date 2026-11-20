#!/bin/bash
# Test only (T-638): Android 9-11 (API 28-30), the strip beside the display cutout in landscape. There the
# window of QZ keeps clear of the cutout (LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES, the decor view fits the
# insets) and its background shows in the strip. Qt 5.15 sets the background of its theme Theme_Holo_Light
# when it creates its first surface (QtActivityDelegate.createSurface) - a light gradient. The fix
# (CustomQtActivity.java): the background goes back as soon as Qt adds a surface - black in the classic look,
# the page colour (the colour of the status bar) in the modern look.
# The cutout - the emulation overlay "tall" (centred on the short edge, so on the left side in landscape).
# Measured by t638_strip.py on the raw frame: the middle column of the strip, rows 30-90 % of the height.
# Base (apk-base) - master before the fix: the light gradient (shown, not required).
# Head (apk-head): one colour from top to bottom - black (classic), the status bar colour (modern dark, light).
. .github/lib.sh
. .github/qz.sh

CUTOUT=com.android.internal.display.cutout.emulation.tall

# displays <name>: dumpsys window displays as dumps/<name>.displays.txt. API 28 prints no DisplayCutout there
# (T-548 run 44289517868): then the last "Cutout insets - Top:t Bottom:b Left:l Right:r" of CustomQtActivity
# (px; only a window the cutout overlaps logs it) as the same line
displays() {
  local f="dumps/$1.displays.txt" ci
  adb shell dumpsys window displays < /dev/null > "$f" 2>/dev/null
  grep -q 'DisplayCutout{insets=Rect(' "$f" && return 0
  ci=$(grep -a 'CustomQtActivity: Cutout insets' full_logcat.txt | tail -n 1 |
    awk '{for (i = 1; i <= NF; i++) {split($i, kv, ":"); v[kv[1]] = kv[2]}}
         END {if ("Left" in v) printf "DisplayCutout{insets=Rect(%s, %s - %s, %s)", v["Left"], v["Top"], v["Right"], v["Bottom"]}')
  say "$1: no DisplayCutout in dumpsys - from the log of QZ: '$ci'"
  echo "$ci" > "$f"
}

# strip_case <case> <side> <black|bar> key=value...: the home page in landscape, the strip measured;
# head - the wanted colour, base - only said
strip_case() {
  local c=$1 side=$2 want=$3 n out rc
  shift 3
  start_case "$c" "$@" || return 1
  rotate land "$c" || return 1
  n="$c-land"
  shot "$n"
  adb exec-out screencap < /dev/null > "$n.raw" 2>/dev/null
  displays "$n"
  out=$("$EMU_PY" .github/t638_strip.py "$n.raw" "dumps/$n.displays.txt" "$want" 2>&1)
  rc=$?
  say "strip $n: $out"
  if [ $rc = 2 ]; then
    proves_nothing "$n: the strip not measured ($out)"
  elif [ "$side" = h ]; then
    if [ $rc = 0 ]; then say "check $n: the strip is $want: OK"
    else fail "check $n: the strip is not $want ($out)"; fi
  else
    say "base $n: $out"
  fi
  rm -f "$n.raw"
  rotate port "$c"
}

emu_init
say "== the strip beside the display cutout in landscape (T-638)"

# the cutout before anything starts: an overlay switched mid-run restarts SystemUI (check_emu_script)
adb shell cmd overlay list < /dev/null 2>/dev/null | grep -i cutout >> "$STEPLOG"
adb shell cmd overlay enable "$CUTOUT" < /dev/null >> "$STEPLOG" 2>&1
emu_sleep 10
adb shell cmd overlay list < /dev/null 2>/dev/null | grep -q -F "[x] $CUTOUT" ||
  proves_nothing "the cutout overlay $CUTOUT not enabled"
logcat_start

for side in b h; do
  if [ "$side" = b ]; then apk=apk-base/android-debug.apk; else apk=apk-head/android-debug.apk; fi
  side_on "$side" "$apk" || continue
  say "== $side: start"
  install_apk "$apk"
  strip_case "${side}c" "$side" black fakedevice_treadmill=true ui_modern=false
  strip_case "${side}d" "$side" bar fakedevice_treadmill=true ui_modern=true ui_theme_mode=dark
  strip_case "${side}l" "$side" bar fakedevice_treadmill=true ui_modern=true ui_theme_mode=light
done

finish
