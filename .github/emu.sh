#!/bin/bash
# Test only (T-514): frames of the file lists of PR 6a-1 (Open Train Program with its preview, Open GPX,
# Load settings) on master (apk-base) and on the branch (apk-head), in the classic and the modern look.
# The classic frames of both sides must match; the modern ones are the new look.
. .github/lib.sh
. .github/qz.sh

QZDIR=/sdcard/Documents/QZ

# seed: a GPX route and a saved settings file where the lists read them (android_documents_folder=true:
# Documents/QZ on every API; install_apk gives the app MANAGE_EXTERNAL_STORAGE, so files of the shell are read)
seed_files() {
  printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
    '<gpx version="1.1" creator="t514" xmlns="http://www.topografix.com/GPX/1/1"><trk><name>Test route</name><trkseg>' \
    '<trkpt lat="45.4642" lon="9.1900"><ele>120</ele></trkpt>' \
    '<trkpt lat="45.4700" lon="9.2000"><ele>135</ele></trkpt>' \
    '<trkpt lat="45.4780" lon="9.2100"><ele>150</ele></trkpt>' \
    '</trkseg></trk></gpx>' > 'Test route.gpx'
  printf '[General]\nftp=210\n' > 'Saved setup.qzs'
  adb shell "mkdir -p $QZDIR/gpx $QZDIR/settings" < /dev/null > /dev/null 2>&1
  adb push 'Test route.gpx' "$QZDIR/gpx/Test route.gpx" < /dev/null > /dev/null 2>&1
  adb push 'Saved setup.qzs' "$QZDIR/settings/Saved setup.qzs" < /dev/null > /dev/null 2>&1
  adb shell "ls $QZDIR/gpx $QZDIR/settings" < /dev/null >> "$STEPLOG" 2>&1
  adb shell "ls '$QZDIR/gpx/Test route.gpx' '$QZDIR/settings/Saved setup.qzs'" < /dev/null > /dev/null 2>&1 \
    || proves_nothing "seed files not on the device"
}

# load_settings_open <look>: the settings page, then its Load settings button - named in the modern look; in
# the classic one it has no name and stands right of "Search settings" (main.qml: the search button is
# anchored to its left), as wide as it
load_settings_open() {
  settings_open || return 1
  if [ "$1" = m ]; then
    tap_ui '^Load settings$' '^Other folders$'
    return
  fi
  local x y w
  dump
  if ! find_ui '^Search settings$'; then
    fail "classic: 'Search settings' not in the header"
    return 1
  fi
  set -- $EMU_AT
  w=$(( $7 - $5 ))
  x=$(( $7 + w / 2 ))
  y=$2
  say "tap classic Load settings at $x $y (right of Search settings)"
  adb shell input tap "$x" "$y" < /dev/null > /dev/null 2>&1
  if wait_ui '^Other folders$' 15; then
    say "outcome 'Load settings': ok"
  else
    say "outcome 'Load settings': no-effect"
    fail "classic: the settings file list did not open"
    return 1
  fi
}

# one side (b - master, h - branch) in one look (c - classic, m - modern)
pages() {
  local c=$1 modern=$2
  start_case "$c" ui_modern=$modern fakedevice_treadmill=true android_documents_folder=true || return 1

  if open_drawer '^Open Train Program$' && tap_ui '^Open Train Program$' '^Other folders$'; then
    shot "$c-1-programs"
    expect "$c-1-programs" '^Easy intervals$' 'the bundled programs listed'
    if tap_ui '^Easy intervals$' '^Start Workout$' 20; then
      emu_sleep 5
      shot "$c-2-preview"
      expect "$c-2-preview" '^Start Workout$' 'the program preview'
    fi
  fi
  back_to "$HOME_RX" 20

  if open_drawer '^Open GPX$' && tap_ui '^Open GPX$' '^Other folders$'; then
    emu_sleep 5
    shot "$c-3-gpx"
    expect "$c-3-gpx" '^Test route$|^Test route\.gpx$' 'the seeded GPX listed'
  fi
  back_to "$HOME_RX" 20

  if load_settings_open "${c#?}"; then
    emu_sleep 2
    shot "$c-4-settings-files"
    expect "$c-4-settings-files" '^Saved setup$|^Saved setup\.qzs$' 'the seeded settings file listed'
  fi
  back_to "$HOME_RX" 20
}

emu_init
logcat_start

for side in b h; do
  if [ "$side" = b ]; then apk=apk-base/android-debug.apk; else apk=apk-head/android-debug.apk; fi
  say "== $side: start"
  install_apk "$apk"
  seed_files
  pages "${side}c" false
  pages "${side}m" true
done

finish
