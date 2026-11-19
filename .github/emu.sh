#!/bin/bash
# Test only (T-599, T-601, T-602): the modern look on the type scale and theme tokens.
#   head (apk-head): test/t599 = ui/modern-style-tokens (feat/modern-ui 24a11f51f + Toast inverse tokens and
#                    Body size, Gym mode text sizes, settings warnings in theme colours, program tags Caption)
#                    + the hook commit + CI trim
#   base (apk-base): test/t599-base = feat/modern-ui 24a11f51f + the same hook commit + CI trim
# The hook (main.qml, test only): profile_name=t599 in qz.conf - 6 s after the start a long toast
# (Toast.qml, 120 s) and the lap prompt (main.qml lapPromptOverlay, "Press LAP to continue"); log line
# "QZ-T599 hook". The frames are for the user and the mockup of the lap prompt (T-601): the checks here
# say only that the screen was reached.
# Cases, on each side x = b | h:
#   xd, xl  modern dark / light, the home page with the toast and the lap prompt
#   xc      classic, the same - the classic must be the same on both sides
#   xg, xk  modern light / classic: gym_mode=true with no device - "Select Your Gym Device" (main.qml
#           popupGymMode, opened by gymModeStartupTimer) with Bluetooth off or searching
#   xr      modern light: Bike Options, the hint "0.005 = Clinchers" (settings.qml labelRollingResistanceInfo,
#           steelblue -> textMuted)
#   xa, xn  modern light / dark: Garmin Options, the note "IMPORTANT: You must set your real Garmin device
#           UNIT ID" (Material Orange -> danger)
# Not in the emulator: the login result icons (PZP, Zwift, Peloton - a login first), the ANT+ speed note
# (Android ANT+ only), the cadence sensor note (Advanced Settings > Accessories, three levels down).
. .github/lib.sh
. .github/qz.sh

# a device name with no device keeps the first-run wizard closed (homeform.h firstRun()); no fake device:
# the gym mode window waits for "no connected device"
NODEV="bluetooth_lastdevice_name=T599-NONE"

# hook_case <case> <look keys...>: the home page, the toast and the lap prompt of the hook
hook_case() {
  local c=$1 i pid
  shift
  start_case "$c" "$@" $NODEV profile_name=t599 || return 1
  # the line of this start only: the buffer holds the starts of the cases before
  pid=$(adb shell pidof "$PKG" < /dev/null | tr -d '\r')
  for i in 1 2 3 4 5 6 7 8 9 10; do
    adb logcat -d --pid="$pid" < /dev/null 2>/dev/null | grep -q -F 'QZ-T599 hook' && break
    emu_sleep 2
  done
  if [ -n "$pid" ] && adb logcat -d --pid="$pid" < /dev/null 2>/dev/null | grep -q -F 'QZ-T599 hook'; then
    say "check $c: hook shown: OK"
  else
    fail "check $c: no 'QZ-T599 hook' line - the toast and the lap prompt were not shown"
  fi
  emu_sleep 2
  shot "$c-1-toast-lap"
}

# gym_case <case> <look keys...>: the gym mode window over the home page (no device connected); the home page
# is under a modal popup, so the start is done here and not by start_case (wait_home looks for Start/Stop)
gym_case() {
  local c=$1
  shift
  case_on "$c" "${FUNCNAME[*]}" || { say "== $c: skipped (cases: $EMU_CASES)"; return 1; }
  say "== $c: start ($* gym_mode=true) at $SECONDS s"
  adb shell am force-stop "$PKG" < /dev/null > /dev/null 2>&1
  emu_sleep 2
  put_conf "$@" $NODEV gym_mode=true
  adb shell am start -n "$PKG/$PKG.CustomQtActivity" < /dev/null > /dev/null 2>&1
  say "pid $c $(adb shell pidof "$PKG" < /dev/null | tr -d '\r')"
  # main.qml popupGymMode: the title Label "Select Your Gym Device"
  if wait_ui '^Select Your Gym Device$' 60 --first; then
    say "check $c: gym mode window shown: OK"
  else
    fail "check $c: 'Select Your Gym Device' not shown"
  fi
  still
  shot "$c-1-gym"
}

# setting_case <case> <section regex> <landing regex> <label regex> <look keys...>: the settings, the section
# open, scrolled to the label
setting_case() {
  local c=$1 sec=$2 land=$3 label=$4
  shift 4
  start_case "$c" "$@" $NODEV || return 1
  settings_open || { shot "$c-0-no-settings" now; return 1; }
  scroll_to "$sec" 20 --exact || { shot "$c-0-no-section" now; return 1; }
  tap_ui "$sec" "$land" --land-below || { shot "$c-0-closed" now; return 1; }
  scroll_to "$label" 30 --first || { shot "$c-0-no-label" now; return 1; }
  settle
  shot "$c-1-label"
  expect "$c-1-label" "$label" 'the label of the change'
}

LIGHT="ui_modern=true ui_theme_mode=light"
DARK="ui_modern=true ui_theme_mode=dark"

emu_init
logcat_start

for side in b h; do
  if [ "$side" = b ]; then apk=apk-base/android-debug.apk; else apk=apk-head/android-debug.apk; fi
  side_on "$side" "$apk" || continue
  say "== $side: start"
  install_apk "$apk"
  hook_case "${side}d" $DARK
  hook_case "${side}l" $LIGHT
  hook_case "${side}c" ui_modern=false
  gym_case "${side}g" $LIGHT
  gym_case "${side}k" ui_modern=false
  # settings.qml:4752 Bike Options (first row "Speed calculates on Power", as in test/t593-emu), the hint at :4942
  setting_case "${side}r" '^Bike Options$' '^Speed calculates on Power$' '^0\.005 = Clinchers.*' $LIGHT
  # settings.qml:10420 Garmin Options (first row "Garmin Bluetooth Sensor"), the note at :11587
  setting_case "${side}a" '^Garmin Options.*' '^Garmin Bluetooth Sensor$' '^IMPORTANT: You must set your real Garmin.*' $LIGHT
  setting_case "${side}n" '^Garmin Options.*' '^Garmin Bluetooth Sensor$' '^IMPORTANT: You must set your real Garmin.*' $DARK
done

finish
