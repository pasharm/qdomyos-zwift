#!/bin/bash
# Test only (T-531): the Swag Bag page on master (apk-base) and on the PR branch (apk-head), in the classic
# and the modern look. The emulator has no Google Play: the product is not Registered, so the product card
# (SwagBagItem, visible: product.status == Product.Registered) is not shown on either side - the run proves
# that the page and the item load without QML errors in both looks, and that the classic page of the branch
# matches master. The purchase states themselves are checked on the phone (T-531).
. .github/lib.sh
. .github/qz.sh

# app_uid: the uid of the installed app - the owner of its data folder; empty without the app
app_uid() {
  adb shell "su 0 stat -c %u /data/data/$PKG" < /dev/null 2>/dev/null | tr -d '\r'
}

# wipe: the app of the previous side, so that each side starts from the first run
wipe_app() {
  adb shell am force-stop "$PKG" < /dev/null > /dev/null 2>&1
  adb uninstall "$PKG" < /dev/null > /dev/null 2>&1
  if [ -n "$(app_uid)" ]; then
    proves_nothing "$PKG still installed before the next side"
  fi
}

# snap <name>: the raw frame for the comparison of the sides, then the frame with its dumps
snap() {
  frame "raw-$1" || near frame "$1: no raw frame"
  shot "$1"
}

# same_as_master <page>: the classic frame of the branch matches the one of master
same_as_master() {
  local a=bc-$1 b=hc-$1 out
  if [ ! -s "raw-$a" ] || [ ! -s "raw-$b" ] || [ ! -s "dumps/$a.xml" ] || [ ! -s "dumps/$b.xml" ]; then
    fail "check classic-$1: same as master: no frame of one side"
    return 1
  fi
  out=$("$EMU_PY" "$EMU_GH/emu_frame.py" diff "raw-$a" "raw-$b" --dumps "dumps/$a.xml" "dumps/$b.xml" \
        --rows "$EMU_ROWS" --tol 32 2>&1)
  case $? in
    0) say "check classic-$1: same as master: OK ($out)" ;;
    1) fail "check classic-$1: the branch differs from master: $out" ;;
    *) fail "check classic-$1: frames not compared: $out" ;;
  esac
}

# swagbag <case> <modern>: the Swag Bag page from the side menu; its landing is named in both looks
# ("Restore Purchases", run 43102847972 of T-514)
swagbag() {
  local c=$1 modern=$2
  start_case "$c" ui_modern=$modern fakedevice_treadmill=true || return 1
  if open_drawer '^Swag Bag$' && tap_ui '^Swag Bag$' '^Restore Purchases$'; then
    emu_sleep 2
    snap "$c-7-swagbag"
  else
    fail "$c: the Swag Bag page not opened"
  fi
  back_to "$HOME_RX" 20
}

# qml_lines <from> <to> <side>: QML messages of SwagBagItem/SwagBagView in the lines of full_logcat.txt of
# one side; any of them fails the side (W and E alike: an assignment or a binding loop is a defect too)
qml_lines() {
  local n
  n=$(sed -n "$1,$2p" full_logcat.txt | grep -c -E 'SwagBag(Item|View)\.qml')
  if [ "$n" -gt 0 ]; then
    sed -n "$1,$2p" full_logcat.txt | grep -E 'SwagBag(Item|View)\.qml' | head -20 >> "$STEPLOG"
    fail "$3: $n QML lines of SwagBagItem/SwagBagView"
  else
    say "check $3: no QML lines of SwagBagItem/SwagBagView (logcat lines $1-$2)"
  fi
}

emu_init
say "== pages: swagbag"
logcat_start

# a beacon line that is always there: the logcat of the run is read at all
for side in b h; do
  if [ "$side" = b ]; then apk=apk-base/android-debug.apk; else apk=apk-head/android-debug.apk; fi
  say "== $side: start"
  wipe_app
  from=$(($(wc -l < full_logcat.txt) + 1))
  install_apk "$apk"
  swagbag "${side}c" false
  swagbag "${side}m" true
  to=$(wc -l < full_logcat.txt)
  [ "$to" -gt "$from" ] || fail "$side: the logcat did not grow (lines $from-$to) - the QML check reads nothing"
  grep -q -E 'qml|QML' full_logcat.txt || fail "$side: no QML line in the logcat at all"
  qml_lines "$from" "$to" "$side"
done

say "== classic: the branch against master"
same_as_master 7-swagbag

finish
