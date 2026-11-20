#!/bin/bash
# Test only (T-627): the hints under the settings in the modern look - textMuted, regular font (not bold
# italic), the hint size; the classic look unchanged.
#   base (apk-base): test/t596-master = master 925472f64 + CI trim (run 44754870875); settings.qml,
#                    AccordionCheckElement.qml, settings-shortcuts.qml, main.qml as in master 47e1a77aa
#   head (apk-head): test/t627 = fix/settings-hints-muted (master 47e1a77aa + the PR) + CI trim
# The checks here say that the screen and the hint were reached; the colour, the font and the classic
# "same on both sides" are measured on the frames after the run (notes/emu/t602-ink.py, emu_frame.py diff).
# Cases, on each side x = b | h:
#   xl, xd  modern light / dark: Bike Options, the hint of "Speed calculates on Power" (settings.qml ~4083,
#           Lime bold italic -> textMuted regular), then the hint "0.005 = Clinchers" (~4221, steelblue ->
#           textMuted)
#   xc      classic: the same two hints - the same on both sides
#   xg      modern light: Training Program Options, the hint "For GPX workouts, ignore inclination changes"
#           (~11602): one of the seven hints with the classic size Qt.application.font.pixelSize - 2,
#           the head has window.fontHint and window.hintGap in the modern look
#   xk      classic: the same GPX hint - the same on both sides
#   xt      modern light: Experimental Features > Enable Virtual Device > Virtual Device Bluetooth, the hint
#           of "Virtual Tacx" (~18440): the classic size was window.fontPx(9), the head window.fontHint
#           (Qt.application.font.pixelSize - 2 at 100 %) - a bigger hint at the default text size
#   xs, xu  modern light, the app text at 170 % (ui_text_scale, the system size off; main.qml textScale):
#           the GPX hint and the Tacx hint - on the head fontHint and hintGap grow with the text size
#           (main.qml fontHint/hintGap), on master the classic size stays
# Both switch sections (virtual_device_enabled, virtual_device_bluetooth) are on by default
# (qzsettings.h:1146, :1151), so their content is open (AccordionCheckElement isOpen from the setting).
. .github/lib.sh
. .github/qz.sh

# a device name with no device keeps the first-run wizard closed (homeform.h firstRun())
NODEV="bluetooth_lastdevice_name=T627-NONE"

# setting_case <case> <section regex> <landing regex> <look keys> -- <shot name> <label regex> [...]:
# the settings, the section open, scrolled to each label in turn, a frame on each
setting_case() {
  local c=$1 sec=$2 land=$3 keys=$4 name label
  shift 4
  # shellcheck disable=SC2086 # the look keys are words
  start_case "$c" $keys $NODEV || return 1
  settings_open || { shot "$c-0-no-settings" now; return 1; }
  # 60 looks: Experimental Features is near the end of the page, further at 170 %
  scroll_to "$sec" 60 --exact || { shot "$c-0-no-section" now; return 1; }
  tap_ui "$sec" "$land" --land-below || { shot "$c-0-closed" now; return 1; }
  while [ $# -ge 2 ]; do
    name=$1 label=$2
    shift 2
    # --exact: a flick carried a hint past the screen to the end of the page (T-602, run 44637707683)
    scroll_to "$label" 40 --first --exact || { shot "$c-$name-no-label" now; continue; }
    settle
    shot "$c-$name"
    expect "$c-$name" "$label" 'the hint'
  done
}

LIGHT="ui_modern=true ui_theme_mode=light"
DARK="ui_modern=true ui_theme_mode=dark"
CLASSIC="ui_modern=false"
# settings.qml (origin/master 47e1a77aa): Bike Options :4058, first row "Speed calculates on Power" :4069, its
# hint :4083; "0.005 = Clinchers" :4221 - three lines in one name (uifind: fullmatch, "." stops at a line
# break, T-602 run 44634788192)
BIKE_SEC='^Bike Options$'
BIKE_LAND='^Speed calculates on Power$'
SPEED_HINT='^QZ calculates speed based on your pedal cadence.*'
ROLL_HINT='^0\.005 = Clinchers[\s\S]*'
# Training Program Options :10608, first row "Stop Treadmill at the End", the GPX hint :11602
PROG_SEC='^Training Program Options$'
PROG_LAND='^Stop Treadmill at the End$'
GPX_HINT='^For GPX workouts, ignore inclination changes.*'
# Experimental Features :17946, first row "Gym Mode" :17957; the Tacx hint :18440
EXP_SEC='^Experimental Features$'
EXP_LAND='^Gym Mode$'
TACX_HINT='^Enables a virtual bluetooth bridge to the Tacx App\.$'
BIG="ui_modern=true ui_theme_mode=light ui_text_scale_system=false ui_text_scale=170"

emu_init
logcat_start

for side in b h; do
  if [ "$side" = b ]; then apk=apk-base/android-debug.apk; else apk=apk-head/android-debug.apk; fi
  side_on "$side" "$apk" || continue
  say "== $side: start"
  install_apk "$apk"
  setting_case "${side}l" "$BIKE_SEC" "$BIKE_LAND" "$LIGHT" 1-speed "$SPEED_HINT" 2-roll "$ROLL_HINT"
  setting_case "${side}d" "$BIKE_SEC" "$BIKE_LAND" "$DARK" 1-speed "$SPEED_HINT" 2-roll "$ROLL_HINT"
  setting_case "${side}c" "$BIKE_SEC" "$BIKE_LAND" "$CLASSIC" 1-speed "$SPEED_HINT" 2-roll "$ROLL_HINT"
  setting_case "${side}g" "$PROG_SEC" "$PROG_LAND" "$LIGHT" 1-gpx "$GPX_HINT"
  setting_case "${side}k" "$PROG_SEC" "$PROG_LAND" "$CLASSIC" 1-gpx "$GPX_HINT"
  setting_case "${side}t" "$EXP_SEC" "$EXP_LAND" "$LIGHT" 1-tacx "$TACX_HINT"
  setting_case "${side}s" "$PROG_SEC" "$PROG_LAND" "$BIG" 1-gpx "$GPX_HINT"
  setting_case "${side}u" "$EXP_SEC" "$EXP_LAND" "$BIG" 1-tacx "$TACX_HINT"
done

finish
