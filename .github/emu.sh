#!/bin/bash
# Test only (T-754): a change of the system colors (the Material You palette, Android 12+) keeps QZ drawn.
#   head (h): fix/android-palette-relaunch eb040bea7 (test/t754) - AndroidManifest.xml: assetsPaths in the
#             configChanges of CustomQtActivity: the activity is not recreated, onConfigurationChanged() runs;
#             CustomQtActivity: a recreation all the same (a change configChanges does not name) restarts the app
#   base (b): origin/master 768f306a4 (test/t647-master) - no assetsPaths: Android recreates the activity in the
#             same process (wm_relaunch_resume_activity), Qt 5.15.0 draws into the old one, the new window is
#             blank (QTBUG-38971; OnePlus 12, notes/emu/t647-op12-2026-11-28/)
# Cases (DEV keeps the wizard closed):
#   p - the classic look; m - the modern look. API 31+: the palette changed twice through the setting SystemUI
#       watches (theme_customization_overlay_packages, ThemeOverlayController): head - no relaunch of the
#       activity, the home page still on the screen, the same pid; base - the relaunch and no home page (the
#       defect: a base with the home page and no relaunch means the change did not reach the app - red, the check
#       proves nothing then). API < 31 - no palette: QZ installs and starts with the new flag in the manifest
#       (minSdk 21: the flag is a number in the binary manifest, old parsers take it as an int)
. .github/lib.sh
. .github/qz.sh

DEV="bluetooth_lastdevice_name=T754-NONE"
OVL=theme_customization_overlay_packages

# palette_set <hex>: the seed colour of the system palette, as Wallpaper & style writes it for a preset colour
palette_set() {
  adb shell "settings put secure $OVL '{\"android.theme.customization.system_palette\":\"$1\",\"android.theme.customization.theme_style\":\"TONAL_SPOT\",\"android.theme.customization.color_source\":\"preset\"}'" < /dev/null > /dev/null 2>&1
}

# relaunches: the count of relaunch events of the activity of QZ in the events buffer
relaunches() {
  adb logcat -d -b events < /dev/null 2>/dev/null | grep -a -c "wm_relaunch[a-z_]*_activity.*$PKG" || true
}

# change <case> <side> <n> <hex>: the palette changed, then what the app shows
change() {
  local c=$1 n=$3 r0 r1 pid0 pid1 home=0
  r0=$(relaunches)
  pid0=$(adb shell pidof "$PKG" < /dev/null | tr -d '\r')
  palette_set "$4"
  say "$c: palette $4 set (change $n)"
  emu_sleep 8
  settle
  # not wait_home: its ensure_app brings QZ back by itself and would hide a blank window
  wait_ui "$HOME_RX" 20 --first && home=1
  dump
  shot "$c-$n-palette"
  r1=$(relaunches)
  pid1=$(adb shell pidof "$PKG" < /dev/null | tr -d '\r')
  say "$c: change $n: relaunch events $r0 -> $r1, pid $pid0 -> $pid1, home page shown: $home"
  if [ "$2" = h ]; then
    [ "$r1" = "$r0" ] && say "check $c-$n: no relaunch of the activity: OK" || fail "check $c-$n: the activity relaunched ($r0 -> $r1) with assetsPaths in configChanges"
    [ "$home" = 1 ] && say "check $c-$n: the home page still drawn: OK" || fail "check $c-$n: no home page after the palette change"
    [ "$pid1" = "$pid0" ] && say "check $c-$n: the same process: OK" || fail "check $c-$n: pid $pid0 -> $pid1"
  else
    if [ "$r1" != "$r0" ] && [ "$home" = 0 ]; then
      say "check $c-$n: master reproduces the defect (relaunch, blank window): OK"
    elif [ "${EMU_API:-35}" -lt 33 ]; then
      # the API 31 image does not apply the palette from the setting (run 46098771916): the palette checks prove
      # nothing there, the bold case does
      near palette "$c-$n: the palette change did not reach the app on API $EMU_API (relaunch $r0 -> $r1, home $home): not a proof"
    else
      fail "check $c-$n: master did not reproduce the defect (relaunch $r0 -> $r1, home $home): the palette change did not reach the app"
    fi
  fi
}

# colors <case> <side> [key=value ...]
colors() {
  local c=$1 side=$2
  shift 2
  start_case "$c" "$@" $DEV || return 1
  shot "$c-1-home"
  if [ "${EMU_API:-35}" -lt 31 ]; then
    say "check $c: QZ starts with assetsPaths in the manifest (API $EMU_API, no palette): OK"
    return 0
  fi
  say "$c: $OVL before: $(adb shell settings get secure $OVL < /dev/null | tr -d '\r')"
  next_color
  change "$c" "$side" 2 "$LAST_COLOR"
  [ "$side" = h ] || return 0
  next_color
  change "$c" "$side" 3 "$LAST_COLOR"
}

# bold <case> <side>: API 31+, Settings > Accessibility > Bold text (font_weight_adjustment) - a config change
# configChanges does not list (fontWeightAdjustment), so Android recreates the activity on every firmware, as
# OxygenOS does with its own bit on a color change. head (eb040bea7): onCreate of the recreated activity
# (getLastNonConfigurationInstance set) restarts the app - a new pid, the home page again; base: the relaunch and no home page
bold() {
  local c=$1 r0 r1 pid0 pid1 home=0 restarts
  start_case "$c" $DEV || return 1
  shot "$c-1-home"
  r0=$(relaunches)
  pid0=$(adb shell pidof "$PKG" < /dev/null | tr -d '\r')
  adb shell settings put secure font_weight_adjustment 300 < /dev/null > /dev/null 2>&1
  say "$c: font_weight_adjustment 300 set"
  emu_sleep 8
  settle
  wait_ui "$HOME_RX" 40 --first && home=1
  dump
  shot "$c-2-bold"
  r1=$(relaunches)
  pid1=$(adb shell pidof "$PKG" < /dev/null | tr -d '\r')
  restarts=$(adb logcat -d < /dev/null 2>/dev/null | grep -a -c "activity recreated while Qt runs" || true)
  adb shell settings put secure font_weight_adjustment 0 < /dev/null > /dev/null 2>&1
  emu_sleep 5
  say "$c: bold text: relaunch events $r0 -> $r1, pid $pid0 -> $pid1, home page shown: $home, restart lines: $restarts"
  if [ "$2" = h ]; then
    [ "$r1" != "$r0" ] && say "check $c: Android recreated the activity: OK" || fail "check $c: no relaunch ($r0 -> $r1): bold text did not reach the app"
    [ "$restarts" -ge 1 ] && say "check $c: the app restarted itself: OK" || fail "check $c: no 'activity recreated while Qt runs' line"
    [ -n "$pid1" ] && [ "$pid1" != "$pid0" ] && say "check $c: a new process: OK" || fail "check $c: pid $pid0 -> $pid1"
    [ "$home" = 1 ] && say "check $c: the home page after the restart: OK" || fail "check $c: no home page after the restart"
  else
    if [ "$r1" != "$r0" ] && [ "$home" = 0 ]; then
      say "check $c: master reproduces the defect (relaunch, blank window): OK"
    else
      fail "check $c: master did not reproduce the defect (relaunch $r0 -> $r1, home $home)"
    fi
  fi
}

# next_color: LAST_COLOR - a seed other than the one set last (the same value again changes nothing); not
# called in $(...): a subshell would not keep it
LAST_COLOR=FF1875F5
next_color() {
  if [ "$LAST_COLOR" = FFB3261E ]; then LAST_COLOR=FF1875F5; else LAST_COLOR=FFB3261E; fi
}

# anr_traces: after an ANR of QZ the stacks Android wrote (/data/anr, root only) to dumps/anr/ of the artifact - the
# main thread at the ANR. Last, before finish: adb root restarts adbd and the logcat with it (lib.sh tb_on)
anr_traces() {
  adb logcat -d < /dev/null 2>/dev/null | grep -a -q "ANR in $PKG" || return 0
  adb root >> "$STEPLOG" 2>&1
  timeout 120 adb wait-for-device < /dev/null >> "$STEPLOG" 2>&1 || { near adb "wait-for-device: no device in 120 s"; return 0; }
  emu_sleep 3
  mkdir -p dumps/anr
  adb pull /data/anr dumps/anr < /dev/null >> "$STEPLOG" 2>&1
  say "== ANR traces: $(find dumps/anr -type f | wc -l) files in dumps/anr"
}

emu_init
logcat_start
OVL_WAS=$(adb shell settings get secure $OVL < /dev/null | tr -d '\r')

for side in h b; do
  if [ "$side" = b ]; then apk=apk-base/android-debug.apk; else apk=apk-head/android-debug.apk; fi
  side_on "$side" "$apk" || continue
  say "== $side: start"
  install_apk "$apk"
  colors "${side}p" "$side"
  colors "${side}m" "$side" ui_modern=true ui_theme_mode=light
  [ "${EMU_API:-35}" -ge 31 ] && bold "${side}w" "$side"
done

if [ "${EMU_API:-35}" -ge 31 ]; then
  if [ -z "$OVL_WAS" ] || [ "$OVL_WAS" = null ]; then
    adb shell settings delete secure $OVL < /dev/null > /dev/null 2>&1
  else
    adb shell "settings put secure $OVL '$OVL_WAS'" < /dev/null > /dev/null 2>&1
  fi
fi

qml_quiet 'main|Home|HomeForm'
anr_traces
finish
