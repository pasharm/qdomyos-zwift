#!/bin/bash
# Test only (T-624): the iOS edge-to-edge PR must leave Android as it is - main.qml (applySystemBars, the
# paddings) and ToastManager.qml (bottomMargin through getBottomPadding()) are on the Android path too.
#   head (apk-head): test/t624-android = ui/modern-ios-edge-to-edge (origin/master c326c88f5 + the change) + CI trim
#   base (apk-base): test/t602-master 8402023fa = the tree of origin/master c326c88f5 + CI trim
# Cases, on each side x = b | h:
#   xc  classic: the home page, then Settings (the system bars as before: black status bar)
#   xm  the modern look: the same (transparent bars, the page under them from API 31)
# The frames of the sides compare one to one (review_run.py --baseline): any difference is the change.
. .github/lib.sh
. .github/qz.sh

# a device name with no device keeps the first-run wizard closed (homeform.h firstRun(), as in T-593)
DEV="bluetooth_lastdevice_name=T624-NONE"

# look <case> <look keys>: home and settings frames
look() {
  local c=$1
  shift
  start_case "$c" "$@" $DEV || return 1
  shot "$c-1-home"
  expect "$c-1-home" "$HOME_RX" "home page"
  settings_open || { shot "$c-0-no-settings" now; return 1; }
  settle
  shot "$c-2-settings"
  # the page itself; the bars and paddings are compared frame to frame with the other side
  expect "$c-2-settings" '^General Options$' "settings page"
}

emu_init
logcat_start

for side in b h; do
  if [ "$side" = b ]; then apk=apk-base/android-debug.apk; else apk=apk-head/android-debug.apk; fi
  side_on "$side" "$apk" || continue
  say "== $side: start"
  install_apk "$apk"
  look "${side}c" ui_modern=false
  look "${side}m" ui_modern=true
done

logcat_stop
finish
