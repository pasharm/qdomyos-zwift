#!/bin/bash
# Test only (T-638): Android 9-11 (API 28-30), the strip beside the display cutout in landscape. There the
# window of QZ reaches into the cutout (LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES) but the decor view fits the
# insets, so Qt's content keeps clear of it and the window background shows in the strip. API 31+: no strip
# (Qt's content goes into the cutout) - the head frame must be the master frame (same_case, t638_same.py). Qt 5.15 sets the background of its theme Theme_Holo_Light
# when it creates its first surface (QtActivityDelegate.createSurface) - a light gradient. The fix
# (CustomQtActivity.java): the background goes back as soon as Qt adds a surface - black in the classic look,
# the page colour (the colour of the status bar) in the modern look.
# The cutout - the emulation overlay "tall" (centred on the short edge, so on the left side in landscape).
# Measured by t638_strip.py on the raw frame: the middle column of the strip, rows 30-90 % of the height.
# Base (apk-base) - master before the fix: the light gradient (shown, not required).
# Head (apk-head): one colour from top to bottom - black (classic), the status bar colour that is the page
# colour (modern dark, light).
. .github/lib.sh
. .github/qz.sh

CUTOUT=com.android.internal.display.cutout.emulation.tall

# displays <name>: dumpsys window displays as dumps/<name>.displays.txt. API 28 prints no DisplayCutout there
# (T-548 run 44291411211): then the last "Cutout insets - Top:t Bottom:b Left:l Right:r" of CustomQtActivity
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

# same_case <case> <side> <frame name>: API 31+ - Qt's content extends into the cutout and the window background the
# fix changes stays under it: the head frame must be the base frame of the same case (t638_same.py). The base raw
# frame waits for the head side; both are removed after the comparison
same_case() {
  local c=$1 side=$2 n=$3 b out rc
  if [ "$side" = b ]; then
    say "base $n: kept for the comparison on API $EMU_API"
    return 0
  fi
  b="b${c#h}-land"
  out=$("$EMU_PY" .github/t638_same.py "$b.raw" "$n.raw" 2>&1)
  rc=$?
  say "same $b $n: $out"
  if [ $rc = 2 ]; then
    proves_nothing "$n: not compared with $b ($out)"
  elif [ $rc = 0 ]; then
    say "check $n: the same as master on API $EMU_API: OK"
  else
    fail "check $n: differs from master on API $EMU_API ($out)"
  fi
  rm -f "$b.raw" "$n.raw"
}

# strip_case <case> <side> <black|bar:RRGGBB> key=value...: the home page in landscape, the strip measured on
# API 28-30 (head - the wanted colour, base - only said), compared with master on API 31+ (same_case)
strip_case() {
  local c=$1 side=$2 want=$3 n out rc
  shift 3
  start_case "$c" "$@" || return 1
  # a failed turn leaves EMU_ROT=land: the next start_case would fail on "not landscape after the start"
  rotate land "$c" || { rotate port "$c"; return 1; }
  n="$c-land"
  shot "$n"
  adb exec-out screencap < /dev/null > "$n.raw" 2>/dev/null
  displays "$n"
  if [ "${EMU_API:-0}" -ge 31 ]; then
    same_case "$c" "$side" "$n"
    rotate port "$c"
    return 0
  fi
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
  # the page colours of the default theme graphite (main.qml themes / lightThemes, bg)
  strip_case "${side}d" "$side" bar:111318 fakedevice_treadmill=true ui_modern=true ui_theme_mode=dark
  strip_case "${side}l" "$side" bar:F4F5F7 fakedevice_treadmill=true ui_modern=true ui_theme_mode=light
done

finish
