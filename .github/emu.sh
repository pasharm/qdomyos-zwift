#!/bin/bash
# Test only (T-550): drop-down lists and menus of the modern look by Material 3 - before (base:
# feat/modern-ui 3e6d74e6b) and after (head: + T-550). Cases of each side:
#   <side>l - modern, light (ui_theme_mode=light): the App Language list open (UiComboBox.qml) and the
#             import menu of Workouts History open (WorkoutsHistory.qml, modernImportMenu)
#   <side>d - the same, dark (ui_theme_mode=dark)
#   <side>c - classic: the App Language list - it must look as before (the change is modern only)
# Expected (head): the list on window.ui.surfaceHigh with a shadow, corner 16, the chosen item in an accent
# block (UiComboBox.qml, delegate background; UiMenuBackground.qml); the import menu as wide as its
# longest item, shadow, no outline. The look is judged on the frames; the run checks the screens.
. .github/lib.sh
. .github/qz.sh

# lang <case>: General Options -> the App Language list open and closed again
lang() {
  local c=$1
  settings_open || return 1
  tap_ui '^General Options$' '^App Language:$' || return 1
  emu_sleep 2
  shot "$c-1-general"
  # the field reads its value: Auto (System) with no saved language (dump of t508 42890148192)
  tap_ui '^Auto \(System\)$' '^Italian$' --first || return 1
  emu_sleep 2
  shot "$c-2-list"
  # the list is open: items the field alone does not show
  expect "$c-2-list" '^Italian$' "list open (Italian)" --any
  expect "$c-2-list" '^Japanese$' "list open (Japanese)" --any
  adb shell input keyevent KEYCODE_BACK < /dev/null > /dev/null 2>&1
  emu_sleep 2
  if ! wait_gone '^Japanese$' 10; then
    fail "$c: the list did not close on back"
    shot "$c-2-not-closed" now
    return 1
  fi
  say "$c: list closed"
}

# import <case>: Workouts History -> the import button (named "Import FIT File...",
# WorkoutsHistory.qml:281) -> the menu with "Import from QZ Folder..."
import() {
  local c=$1
  back_to "$HOME_RX" 20 || return 1
  open_drawer '^Workouts History$' || return 1
  tap_ui '^Workouts History$' '^Calendar$' || return 1
  # a clean install asks once over the page whether to look for workouts of a previous installation
  # (popupHistoryRecovery, main.qml:1256; "No" hides it - onNoClicked); the import button is under it
  # (run 43524060119: wrong-screen / no-effect on all four modern cases)
  if wait_ui '^&?No$' 6; then
    tap_ui '^&?No$' '^Calendar$' || return 1
    wait_gone '^&?No$' 10 || { fail "$c: the question about a previous installation did not close"; return 1; }
  fi
  emu_sleep 2
  # the items of a QML Menu are not in the uiautomator dump (T-182, 41751759800; again run 43527738307: the
  # menu open on the frame, the dump has only the button) - the button by its node, the menu on the frame only
  dump
  if ! find_ui '^Import FIT File\.\.\.$'; then
    fail "$c: no import button ($EMU_WHY)"
    shot "$c-3-no-button" now
    return 1
  fi
  set -- $EMU_AT
  shot "$c-3-before" now
  adb shell input tap "$1" "$2" < /dev/null > /dev/null 2>&1
  emu_sleep 2
  shot "$c-3-import"
  # a coarse no-effect check: the frame must change (the menu is judged by eye on $c-3-import.png)
  if cmp -s "$c-3-before.png" "$c-3-import.png"; then
    fail "$c: the frame did not change after the tap on the import button"
  else
    say "$c: import menu - the frame changed, the menu is judged on $c-3-import.png"
  fi
  if ! find_ui '^Calendar$'; then
    fail "$c: the history page left after the tap on the import button"
  fi
  adb shell input keyevent KEYCODE_BACK < /dev/null > /dev/null 2>&1
  emu_sleep 2
}

# modern <case> <theme>
modern() {
  start_case "$1" ui_modern=true ui_theme_mode="$2" fakedevice_treadmill=true || return 1
  lang "$1" && import "$1"
}

classic() {
  start_case "$1" ui_modern=false fakedevice_treadmill=true || return 1
  lang "$1"
}

emu_init
logcat_start

for side in b h; do
  if [ "$side" = b ]; then apk=apk-base/android-debug.apk; else apk=apk-head/android-debug.apk; fi
  side_on "$side" "$apk" || continue
  say "== $side: start"
  install_apk "$apk" || continue
  modern "${side}l" light
  modern "${side}d" dark
  classic "${side}c"
done

# no QML warning of the changed files from the head processes (pid lines of start_case)
logcat_stop
n=0
for pid in $(grep -a '^pid h' "$STEPLOG" | cut -d' ' -f3); do
  n=$(( n + 1 ))
  found=$(awk -v p="$pid" '$3 == p' full_logcat.txt | grep -a -E '(UiComboBox|UiMenuBackground|WorkoutsHistory)\.qml:' | head -5)
  if [ -n "$found" ]; then
    echo "$found" >> "$STEPLOG"
    fail "check qml: pid $pid: QML warnings of the changed files"
  fi
done
if [ "$n" = 0 ]; then
  grep -q '== partial run' "$STEPLOG" || fail "check qml: no head pid in steps.log - QML warnings not checked"
elif [ ! -s full_logcat.txt ]; then
  fail "check qml: full_logcat.txt is empty"
else
  grep -q '^!! check qml' "$STEPLOG" || say "check qml: no warning of the changed files from $n head processes: OK"
fi
finish
