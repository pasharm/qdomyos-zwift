#!/bin/bash
# Test only (T-618): the value of a classic home tile (myValue, Home.qml) sits in a band of 58 dp; tiles with a
# smaller font (Elapsed 36, Clock 26 on Android, homeform.cpp:509-519) stayed at the top of the band, the PR
# centres it (verticalAlignment AlignVCenter); 48 pt values fill the band and do not move.
#   head (apk-head): test/t618 = fix/classic-tile-value-vcenter (origin/master c326c88f5 + the fix) + CI trim
#   base (apk-base): run 44528855162 = origin/master d4513c297 + CI trim (since then only main.qml changed,
#                    the charts of #5833 - not the home page)
# The run collects frames; its checks say only that the tiles are on the screen. The centre of the digits
# against the 48 pt neighbour is measured on the frames afterwards (the dump gives the box of the Text, not
# its ink).
# Case, on each side x = b | h (the classic look, ui_modern=false, the fake treadmill - a running workout):
#   xn  the clock tile first (tile_datetime_order=0, a key of the emulator only), the top of the home page
. .github/lib.sh
# a running workout never shows the support button (qz.sh HOME_READY_RX)
HOME_READY_RX=
. .github/qz.sh

QZDIR=/sdcard/Documents/QZ

docs_key() {
  if [ "${EMU_API:-35}" -lt 34 ]; then echo android_documents_folder=true; fi
}

app_uid() {
  adb shell "su 0 stat -c %u /data/data/$PKG" < /dev/null 2>/dev/null | tr -d '\r'
}

# wipe_files: Documents/QZ of the previous side, removed by the app uid while the app is installed, then the
# app (T-610 wipe_files)
wipe_files() {
  local uid
  uid=$(app_uid)
  if [ -n "$uid" ]; then
    adb shell am force-stop "$PKG" < /dev/null > /dev/null 2>&1
    adb shell "su $uid,$uid,9997 sh -c 'rm -rf $QZDIR'" < /dev/null >> "$STEPLOG" 2>&1
  fi
  adb uninstall "$PKG" < /dev/null > /dev/null 2>&1
}

# tiles_case <case>: the classic home page with the fake treadmill, the clock tile first; the frame of the top
# rows. The tiles have no names in the dump (Accessible of the delegate: the name and the value), the labels
# are looked for as the start of a name
tiles_case() {
  local c=$1
  start_case "$c" ui_modern=false fakedevice_treadmill=true bluetooth_lastdevice_name=T618-FAKE \
    tile_datetime_order=0 $(docs_key) || return 1
  emu_sleep 5
  still
  shot "$c-1-tiles"
  expect "$c-1-tiles" '^Clock.*' 'the clock tile (26 pt)'
  expect "$c-1-tiles" '^Elapsed.*' 'the elapsed tile (36 pt)'
  expect "$c-1-tiles" '^Speed.*' 'the speed tile (48 pt, plus and minus)'
}

emu_init
logcat_start

for side in b h; do
  if [ "$side" = b ]; then apk=apk-base/android-debug.apk; else apk=apk-head/android-debug.apk; fi
  side_on "$side" "$apk" || continue
  say "== $side: start"
  wipe_files
  install_apk "$apk"
  tiles_case "${side}n"
done

logcat_stop
for side in b h; do
  n=0
  for pid in $(grep -a "^pid $side" "$STEPLOG" | cut -d' ' -f3); do
    n=$(( n + $(awk -v p="$pid" '$3 == p' full_logcat.txt | grep -a -c -E 'Home\.qml:[0-9]+: ') ))
  done
  say "== QML lines of Home.qml, side $side: $n"
done
finish
