#!/bin/bash
# Test only (T-518): files of a previous install in gpx/, settings/ and profiles/. On Android 14+ the work
# folder of QZ is Documents/QZ; a file another install left there belongs to another uid: the folder lists
# leave it out, it cannot be opened. T-195 brought back training/ only; the branch walks training/, gpx/,
# settings/ and profiles/ in one pass with one question and one folder picker, and shows a "Restore files"
# button beside "Other folders" until QZ has a grant on the QZ folder.
#
# A side: install, start (the bundled programs and routes are copied), a route, a settings file and a
# profile written as the app, uninstall, install again - the files stay, owned by the old uid.
#  b (master, input base): the GPX page without a question or a button, the files stay foreign
#  h (branch, input head): the question on the GPX page, No; the button on the GPX, profiles and settings
#    file pages; Restore files on the settings file page, Yes, the picker, Allow; every file owned by the
#    new uid, no .restore_ copies; the button gone; no question after a restart
#  more sides of the branch (each on a clean emulator; the input sides): d - h on API 30 with the "Documents
#    folder" option, o - API 30 without it, g - the grant from the history recovery, r - .restore_ copies, p - a
#    restore under the open profiles list, t - under the open programs list, s - under the open settings file
#    list, k - the question by a .deleted_ marker alone, c - the picker cancelled, u - one subfolder picked,
#    m - h in the modern look
. .github/lib.sh
. .github/qz.sh

QZDIR=/sdcard/Documents/QZ
UI_MODERN=${UI_MODERN:-false}
ROUTE="T518 route.gpx"
SETUP="t518-setup.qzs"
PROFILE="T518 profile.qzs"
QUESTION_RX='(?s).*GPX routes.*previous installation.*'

# app_uid: the uid of the installed app - the owner of its data folder; empty without the app
app_uid() {
  adb shell "su 0 stat -c %u /data/data/$PKG" < /dev/null 2>/dev/null | tr -d '\r'
}
# reads <uid> <path in Documents/QZ>: the app of that uid reads the file through FUSE - a file of its own
# does, a file of a previous install does not (Permission denied, T-195 run 41909273758). The owner is not
# in the file system: every file of Documents/QZ is uid 10201 there, those of the app itself too (run
# 43184819969) - MediaProvider keeps it (owner_package_name, see owners)
LOWER=/data/media/0/Documents/QZ
reads() {
  adb shell "su $1,$1,9997 cat '$QZDIR/$2' > /dev/null" < /dev/null > /dev/null 2>&1
}
# owners <dir...>: the files and their owner package by MediaProvider, for steps.log
owners() {
  local d
  for d in "$@"; do
    say "-- $d: shell"
    adb shell "ls -ln '$QZDIR/$d'" < /dev/null >> "$STEPLOG" 2>&1
  done
  say "-- MediaProvider owners in Documents/QZ:"
  adb shell "content query --uri content://media/external/file --projection _data:owner_package_name --where \"_data LIKE '%/Documents/QZ/%'\"" \
    < /dev/null 2>&1 | grep -v -E '[.](zwo|fit|log)' >> "$STEPLOG"
}
mark() { say "== $1"; adb shell log -t T518 "mark $1" < /dev/null > /dev/null 2>&1; }

# wipe_files: Documents/QZ of the previous side, removed by the app uid while the app is installed
# (MediaProvider forgets the files then; T-514 runs 43019114307, 43021054533)
wipe_files() {
  local uid
  uid=$(app_uid)
  if [ -n "$uid" ]; then
    adb shell am force-stop "$PKG" < /dev/null > /dev/null 2>&1
    adb shell "su $uid,$uid,9997 sh -c 'rm -rf $QZDIR'" < /dev/null >> "$STEPLOG" 2>&1
  fi
  adb uninstall "$PKG" < /dev/null > /dev/null 2>&1
  # files of a previous install of this side the app may not remove (run 43185579383: "Directory not
  # empty" after the reinstall of master): through MediaProvider, which forgets them with the files
  if adb shell "ls -d $QZDIR" < /dev/null > /dev/null 2>&1; then
    say "wipe: $QZDIR still there - delete through MediaProvider"
    adb shell "su 0 content delete --uri content://media/external/file --where \"_data LIKE '$QZDIR/%' OR _data LIKE '/storage/emulated/0/Documents/QZ/%'\"" \
      < /dev/null >> "$STEPLOG" 2>&1
    adb shell "su 0 rm -rf /storage/emulated/0/Documents/QZ" < /dev/null >> "$STEPLOG" 2>&1
  fi
  if adb shell "ls -d $QZDIR" < /dev/null > /dev/null 2>&1; then
    adb shell "su 0 ls -lnR $QZDIR" < /dev/null >> "$STEPLOG" 2>&1
    proves_nothing "$QZDIR left from the previous side (uid ${uid:-none})"
  fi
}

# install_case <apk>: install_apk, then "all files access" taken back: with it the app reads the foreign
# files and the case of a reinstall is gone (T-195)
install_case() {
  install_apk "$1"
  adb shell appops set "$PKG" MANAGE_EXTERNAL_STORAGE default < /dev/null > /dev/null 2>&1
  say "appops MANAGE_EXTERNAL_STORAGE: $(adb shell appops get "$PKG" MANAGE_EXTERNAL_STORAGE < /dev/null 2>&1 | tr -d '\r')"
}

# DOCS=true: the "Documents folder" option (android_documents_folder) - below Android 14 the QZ folder is
# Documents/QZ only with it (homeform::getWritableAppDir), else it is in Android/data
conf() {
  if [ "$DOCS" = true ]; then
    start_case "$1" ui_modern=$UI_MODERN fakedevice_treadmill=true android_documents_folder=true
  else
    start_case "$1" ui_modern=$UI_MODERN fakedevice_treadmill=true
  fi
}

# seed_files: the files a user had made, written as the app (the app uid with the storage group 9997;
# run-as is shut out of /sdcard from API 30)
seed_files() {
  local uid as f
  printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
    '<gpx version="1.1" creator="t518" xmlns="http://www.topografix.com/GPX/1/1"><trk><name>T518 route</name><trkseg>' \
    '<trkpt lat="45.4642" lon="9.1900"><ele>120</ele></trkpt>' \
    '<trkpt lat="45.4700" lon="9.2000"><ele>135</ele></trkpt>' \
    '</trkseg></trk></gpx>' > route.gpx
  printf '[General]\nftp=210\n' > setup.qzs
  printf '[General]\nftp=230\nprofile_name=T518 profile\n' > profile.qzs
  uid=$(app_uid)
  [ -n "$uid" ] || proves_nothing "seed: no uid of $PKG"
  as="su $uid,$uid,9997 sh -c"
  adb shell "$as 'mkdir -p $QZDIR/gpx $QZDIR/settings $QZDIR/profiles'" < /dev/null >> "$STEPLOG" 2>&1
  adb shell "$as 'cat > \"$QZDIR/gpx/$ROUTE\"'" < route.gpx >> "$STEPLOG" 2>&1
  adb shell "$as 'cat > \"$QZDIR/settings/$SETUP\"'" < setup.qzs >> "$STEPLOG" 2>&1
  adb shell "$as 'cat > \"$QZDIR/profiles/$PROFILE\"'" < profile.qzs >> "$STEPLOG" 2>&1
  owners gpx settings profiles
  for f in "gpx/$ROUTE" "settings/$SETUP" "profiles/$PROFILE"; do
    reads "$uid" "$f" || proves_nothing "seed: $f not readable by the app (uid $uid)"
  done
  say "seeded as uid $uid: $ROUTE, $SETUP, $PROFILE"
}

# previous_install <side> <apk>: the files of a previous install, then the app installed again
previous_install() {
  local old new bundled f
  mark "$1: previous install"
  wipe_files
  install_case "$2"
  conf "$1-first" || proves_nothing "$1: the first start did not reach home"
  bundled=$(adb shell "ls $QZDIR/gpx" < /dev/null 2>/dev/null | tr -d '\r' | grep -c '[.]gpx$')
  say "bundled routes after the first start: $bundled"
  [ "${bundled:-0}" -ge 1 ] || proves_nothing "$1: no bundled GPX routes in $QZDIR/gpx"
  seed_files
  # BEFORE_REINSTALL: a function of the side that changes the files of the previous install (side k)
  [ -n "$BEFORE_REINSTALL" ] && "$BEFORE_REINSTALL"
  old=$(app_uid)
  mark "$1: reinstall"
  adb shell am force-stop "$PKG" < /dev/null > /dev/null 2>&1
  adb uninstall "$PKG" < /dev/null > /dev/null 2>&1
  install_case "$2"
  new=$(app_uid)
  say "uid: previous install $old, this one $new"
  [ -n "$new" ] && [ "$new" != "$old" ] || proves_nothing "$1: the reinstall kept the uid ($old)"
  for f in "gpx/$ROUTE" "settings/$SETUP" "profiles/$PROFILE"; do
    adb shell "ls '$QZDIR/$f'" < /dev/null > /dev/null 2>&1 || proves_nothing "$1: $f gone with the uninstall"
    if reads "$new" "$f"; then
      proves_nothing "$1: the new install reads $f - not a foreign file"
    fi
  done
  owners gpx settings profiles
  say "the new install does not read the seeded files: the case of a reinstall is there"
  OLD_UID=$old
  NEW_UID=$new
}

# load_settings_open: the settings page, then its Load settings button - named in the modern look; in the
# classic one it has no name and stands right of "Search settings", as wide as it (T-514)
load_settings_open() {
  local x y w
  settings_open || return 1
  if [ "$UI_MODERN" = true ]; then
    tap_ui '^Load settings$' '^Other folders$'
    return
  fi
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

# beside <shot>: "Restore files" right of "Other folders" in one row (centres within 20 px in height)
beside() {
  local a b
  a=$(uifind "dumps/$1.xml" '^Other folders$' 2>/dev/null) || { fail "check $1: no Other folders"; return 1; }
  b=$(uifind "dumps/$1.xml" '^Restore files$' 2>/dev/null) || { fail "check $1: no Restore files"; return 1; }
  set -- "$1" $a $b
  # $2 $3 - centre of Other folders; the find gives 8 numbers, so Restore files starts at ${10}
  if [ "$2" -lt "${10}" ] && [ $(( $3 - ${11} )) -le 20 ] && [ $(( ${11} - $3 )) -le 20 ]; then
    say "check $1: Restore files beside Other folders ($2,$3 / ${10},${11}): OK"
  else
    fail "check $1: Restore files not beside Other folders ($2,$3 / ${10},${11})"
  fi
  # at the bottom of the page as Other folders on master (y 2390 on Nexus 6, T-514 run 43062774035
  # hc-4-settings-files): without the anchors of the row it stood at y 1928 (run 43198926517)
  if [ "$3" -ge 2250 ]; then
    say "check $1: the button row at the bottom of the page (y $3): OK"
  else
    fail "check $1: the button row is not at the bottom of the page (y $3, master 2390)"
  fi
}

# gpx_open / profiles_open: the pages from the menu
# the branch asks the question at once on the GPX page, the box over the list (run 43189333683): its No is a
# landing too
# [landing]: in the modern look the question is a Popup over the page, Other folders stays in the dump - the
# landing of a visit with the question is No alone there (two matches are a failure of find)
gpx_open() { open_drawer '^Open GPX$' && tap_ui '^Open GPX$' "${1:-^Other folders$|^&?No$}"; }
profiles_open() { open_drawer '^Profile:.*' && tap_ui '^Profile:.*' '^Other folders$|^&?No$'; }
# picker_on: the folder picker of the system has the focus
picker_on() { adb shell dumpsys window < /dev/null 2>/dev/null | grep mCurrentFocus | grep -q documentsui; }

# the question of the restore: the native box (classic) or UiMessageDialog (modern); No/Yes
question_shown() { wait_ui "$QUESTION_RX" "${1:-20}" --any; }

# yes_picker_allow <picker shot> <allow shot>: Yes of the question on screen, then the folder picker of the
# system on Documents/QZ - Use this folder, Allow.
# The picker is another app (no tap_ui: its ensure_app would press back on it), and uiautomator gets no
# dump of it here - the image previews of Documents/QZ keep loading (run 43191860819, frame h-6-picker:
# Documents > QZ with USE THIS FOLDER at the bottom). The window by dumpsys, the buttons by their label if
# a dump comes, else by their place (Nexus 6: USE THIS FOLDER 720 2391 - that frame and T-195 run
# 38488133337; Allow 1174 1488 - T-195 run 41909273758). The proof is the line in the log after it
yes_picker_allow() {
  local i
  if find_ui '^&?Yes$'; then
    set -- "$1" "$2" $EMU_AT
    say "tap 'Yes' at $3 $4"
    adb shell input tap "$3" "$4" < /dev/null > /dev/null 2>&1
  else
    fail "$1: no Yes in the question"
  fi
  for i in $(seq 1 10); do
    picker_on && break
    emu_sleep 2
  done
  if picker_on; then
    say "picker on top: $(adb shell dumpsys window < /dev/null | grep mCurrentFocus | tr -d '\r')"
  else
    fail "$1: the folder picker did not open"
  fi
  emu_sleep 3
  shot "$1" now
  # PICK_INTO "x y": open a subfolder of Documents/QZ first (side u; Nexus 6, frame h-6-picker of run
  # 43229195069: gpx at 930 726 in the grid of folders)
  if [ -n "$PICK_INTO" ]; then
    say "open the subfolder at $PICK_INTO"
    adb shell input tap $PICK_INTO < /dev/null > /dev/null 2>&1
    emu_sleep 4
    shot "$1-into" now
  fi
  if [ -s "dumps/$1.xml" ] && find_ui '^use this folder$'; then
    set -- "$1" "$2" $EMU_AT
    say "tap 'Use this folder' by label at $3 $4"
  else
    set -- "$1" "$2" 720 2391
    near picker "no dump of the picker: 'Use this folder' by its place $3 $4"
  fi
  adb shell input tap "$3" "$4" < /dev/null > /dev/null 2>&1
  emu_sleep 4
  shot "$2" now
  if [ -s "dumps/$2.xml" ] && find_ui '^allow$'; then
    set -- "$1" "$2" $EMU_AT
    say "tap 'Allow' by label at $3 $4"
  else
    set -- "$1" "$2" 1174 1488
    near picker "no dump of the Allow box: 'Allow' by its place $3 $4"
  fi
  adb shell input tap "$3" "$4" < /dev/null > /dev/null 2>&1
}

# restored_check <check name>: the line of the folder pass (it runs in a thread; qDebug, log_debug), three
# seeded files at least
restored_check() {
  local i
  for i in $(seq 1 20); do
    grep -a -q "files of a previous install restored:" full_logcat.txt && break
    emu_sleep 3
  done
  RESTORED=$(grep -a "files of a previous install restored:" full_logcat.txt | tail -n 1 | sed 's/.*restored: *//' | tr -d '\r ')
  say "restored (log): ${RESTORED:-none}"
  if [ -n "$RESTORED" ] && [ "$RESTORED" -ge 3 ] 2>/dev/null; then
    say "check $1: $RESTORED files restored in one pass: OK"
  else
    fail "check $1: restored '${RESTORED:-no line}', expected 3 or more"
  fi
}

# files_own <check prefix>: the seeded files read by the new install, no .restore_ copies, no file of the
# previous install left in the four folders
files_own() {
  local f d left foreign
  for f in "gpx/$ROUTE" "settings/$SETUP" "profiles/$PROFILE"; do
    if reads "$NEW_UID" "$f"; then
      say "check $1: $f read by the app ($NEW_UID): OK"
    else
      fail "check $1: the app ($NEW_UID) still does not read $f"
    fi
  done
  left=$(adb shell "su 0 ls -aR $LOWER" < /dev/null 2>/dev/null | tr -d '\r' | grep -c '^[.]restore_')
  if [ "${left:-0}" = 0 ]; then
    say "check $1: no .restore_ copies left: OK"
  else
    fail "check $1: $left .restore_ copies left"
  fi
  foreign=""
  for d in training gpx settings profiles; do
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      reads "$NEW_UID" "$d/$f" || foreign="$foreign$d/$f
"
    done < <(adb shell "ls '$QZDIR/$d'" < /dev/null 2>/dev/null | tr -d '\r')
  done
  foreign=$(printf '%s' "$foreign" | sed '/^$/d')
  if [ -z "$foreign" ]; then
    say "check $1: no file of the previous install left in the four folders: OK"
  else
    fail "check $1: files of the previous install left: $(echo "$foreign" | tr '\n' ';')"
  fi
}

emu_init
logcat_start

# SIDE (matrix): b - master, h - the branch, each on a clean emulator: a second side after the first left
# files the app may not remove, and after a wipe by root the new install wrote nothing (runs 43185579383,
# 43186663417)
SIDE=${SIDE:-h}
say "side $SIDE"

# ---- b: master
side_b() {
  [ -s apk-base/android-debug.apk ] || proves_nothing "side b without the master APK (input base)"
  previous_install b apk-base/android-debug.apk
  conf b
  mark "b: GPX page"
  if gpx_open; then
    emu_sleep 4
    shot b-1-gpx
    expect_not b-1-gpx '^Restore files$' 'master: no restore button'
    question_shown 6 && fail "b: master asked the question"
  fi
  back_to "$HOME_RX" 20
  if profiles_open; then emu_sleep 3; shot b-2-profiles; fi
  back_to "$HOME_RX" 20
  if load_settings_open; then emu_sleep 3; shot b-3-settings-files; fi
  back_to "$HOME_RX" 20
  for f in "gpx/$ROUTE" "settings/$SETUP" "profiles/$PROFILE"; do
    if reads "$NEW_UID" "$f"; then
      fail "check b-files: master reads $f - the case of a reinstall is not there"
    else
      say "check b-files: $f still foreign to master (master does not restore): OK"
    fi
  done
  wrap_up
}

# ---- h: the branch
side_h() {
previous_install h apk-head/android-debug.apk
conf h

# 1. The GPX page asks (bundled routes of the previous install); No
mark "h: GPX page"
if [ "$UI_MODERN" = true ]; then H_LAND='^&?No$'; else H_LAND=''; fi
if gpx_open $H_LAND; then
  if question_shown 20; then
    shot h-1-question
    expect h-1-question "$QUESTION_RX" 'the question on the GPX page' --any
    tap_ui '^&?No$' '^Other folders$' 20
  else
    fail "h: no question on the GPX page"
    shot h-1-no-question now
  fi
  emu_sleep 3
  still
  shot h-2-gpx-button
  expect h-2-gpx-button '^Restore files$' 'the restore button on the GPX page'
  beside h-2-gpx-button
fi
back_to "$HOME_RX" 20

# 2. Profiles: the button, no second question in the same run
mark "h: profiles page"
if profiles_open; then
  emu_sleep 4
  question_shown 3 && fail "h: a second question on the profiles page"
  shot h-3-profiles-button
  expect h-3-profiles-button '^Restore files$' 'the restore button on the profiles page'
  beside h-3-profiles-button
fi
back_to "$HOME_RX" 20

# 3. Settings files: the button; Restore files - the question, Yes, the picker of the system, Allow
mark "h: settings file page"
if load_settings_open; then
  emu_sleep 3
  shot h-4-settings-button
  expect h-4-settings-button '^Restore files$' 'the restore button on the settings file page'
  beside h-4-settings-button
  if tap_ui '^Restore files$' '^&?Yes$' 20; then
    shot h-5-question
    expect h-5-question "$QUESTION_RX" 'the question by the button' --any
    mark "h: yes"
    yes_picker_allow h-6-picker h-7-allow
    mark "h: allowed"
    restored_check h-restore
    emu_sleep 3
    ensure_app
    still
    shot h-8-settings-after
    expect_not h-8-settings-after '^Restore files$' 'the button gone after the grant'
    say "settings list rows named t518-setup: $(uifind dumps/h-8-settings-after.xml --count '^t518-setup.*' --any)"
  fi
fi

# 4. Every file of the previous install is the app's own now, no temporary copies left
files_own h-files
owners gpx settings profiles
back_to "$HOME_RX" 20

# 5. The GPX page again: the restored route, no button, no question
mark "h: GPX page after"
if gpx_open; then
  emu_sleep 4
  question_shown 3 && fail "h: the question again after the restore"
  shot h-9-gpx-after
  expect_not h-9-gpx-after '^Restore files$' 'no restore button with the grant'
  expect h-9-gpx-after '^Other folders$' 'Other folders still there'
fi
back_to "$HOME_RX" 20

# 6. A new start: the quiet pass by the saved grant, no question, no button
mark "h: restart"
conf h-restart
if profiles_open; then
  emu_sleep 4
  question_shown 3 && fail "h: the question after a restart"
  shot h-10-profiles-restart
  expect_not h-10-profiles-restart '^Restore files$' 'no restore button after a restart'
fi
back_to "$HOME_RX" 20
wrap_up
}

# wrap_up: the lines of the fix, the QML check, the end of the run (finish exits)
wrap_up() {
logcat_stop
grep -a -E "T518|restored|previous install|handleRestoreFolderResult|restoreFolderFiles|openRestoreFolderPicker|recoverRestoreCopies|recovered from temporary|hasQzFolderGrant|deleteTreeDocument|takePersistableUriPermission" \
  full_logcat.txt > t518_logcat.txt
# QML errors of the changed files on this side, the text after the file name (no time, pid, line): an
# error master has too is not the branch's. Master's list - .github/t518_qml_master.txt, the master side of
# run 43186663417 (GPXList.qml "mainRect is not defined", main.qml rootItem at start - T-213)
QML_RX="(GPXList|SettingsList|profiles|TrainingProgramsList|TrainingProgramsListJS|main)\.qml.*(Error|Unable to assign|undefined)"
# The type in "QML <type>: Detected anchors on an item that is managed by a layout" left out: the branch keeps
# the anchors of master's button on the row that holds it now (RowLayout instead of Button, run 43202263306) -
# without them the row left the bottom of the page (run 43198926517)
qml_norm() { sed -e 's/[.]qml\(:[0-9]*\)*/.qml/g' -e 's/QML [A-Za-z]*: Detected anchors/QML item: Detected anchors/' | tr -d '\r' | sort -u; }
grep -a -o -E "$QML_RX.*" full_logcat.txt | qml_norm > qml_side.txt
say "== QML errors of the changed files ($SIDE): $(wc -l < qml_side.txt)"
cat qml_side.txt >> "$STEPLOG"
qml_norm < .github/t518_qml_master.txt > qml_master.txt
comm -13 qml_master.txt qml_side.txt > qml_new.txt
if [ -s qml_new.txt ]; then
  say "not on master (run 43186663417):"
  cat qml_new.txt >> "$STEPLOG"
  fail "check qml: errors of the changed QML files that master does not have"
else
  say "check qml: no QML error of the changed files that master does not have: OK"
fi
finish
}

# ---- o: the branch with the QZ folder in Android/data (API 30, no "Documents folder" option)
# The previous install had the option (its files in Documents/QZ, foreign now), this start has not: the QZ
# folder is Android/data, so no question, no button, no pass - a restore would copy Documents/QZ into a folder
# that goes away with the app (qzFolderRestorable)
side_o() {
  DOCS=true previous_install o apk-head/android-debug.apk
  DOCS=false conf o
  mark "o: GPX page"
  if gpx_open; then
    emu_sleep 4
    question_shown 6 && fail "o: the question with the folder in Android/data"
    shot o-1-gpx
    expect_not o-1-gpx '^Restore files$' 'no restore button with the folder in Android/data'
    expect o-1-gpx '^Other folders$' 'the GPX page is open'
  fi
  back_to "$HOME_RX" 20
  mark "o: profiles page"
  if profiles_open; then
    emu_sleep 4
    question_shown 3 && fail "o: the question on the profiles page"
    shot o-2-profiles
    expect_not o-2-profiles '^Restore files$' 'no restore button on the profiles page'
  fi
  back_to "$HOME_RX" 20
  mark "o: settings file page"
  if load_settings_open; then
    emu_sleep 3
    question_shown 3 && fail "o: the question on the settings file page"
    shot o-3-settings-files
    expect_not o-3-settings-files '^Restore files$' 'no restore button on the settings file page'
  fi
  back_to "$HOME_RX" 20
  if grep -a -q "files of a previous install restored:" full_logcat.txt; then
    fail "check o-pass: a restore pass ran with the folder in Android/data"
  else
    say "check o-pass: no restore pass: OK"
  fi
  for f in "gpx/$ROUTE" "settings/$SETUP" "profiles/$PROFILE"; do
    if reads "$NEW_UID" "$f"; then
      fail "check o-files: $f became the app's own - something restored it"
    else
      say "check o-files: $f left as it was in Documents/QZ: OK"
    fi
  done
  wrap_up
}

# ---- g: the grant on the QZ folder given by the workout history recovery (#5233), not by Restore files.
# The GPX page asks, No; the history page offers its recovery (the database of the previous install is in
# Documents/QZ), Yes, the same folder picker, Allow; then the GPX page restores quietly - no question, no
# button, every file the app's own
HISTORY_RX='(?s).*Workouts of a previous installation.*'
side_g() {
  previous_install g apk-head/android-debug.apk
  adb shell "ls '$QZDIR/ddb.sqlite'" < /dev/null > /dev/null 2>&1 \
    || proves_nothing "g: no ddb.sqlite of the previous install - the history offers no recovery"
  conf g
  mark "g: GPX page"
  if gpx_open; then
    if question_shown 20; then
      shot g-1-question
      tap_ui '^&?No$' '^Other folders$' 20
    else
      fail "g: no question on the GPX page"
    fi
    emu_sleep 3
    shot g-2-gpx-button
    expect g-2-gpx-button '^Restore files$' 'the restore button before the grant'
  fi
  back_to "$HOME_RX" 20
  mark "g: history page"
  # landing: Yes of the question alone - with the page title too the pattern takes two controls, and two
  # are a failure of find (run 43224306787: the question was there)
  if open_drawer '^Workouts History$' && tap_ui '^Workouts History$' '^&?Yes$' 40; then
    if wait_ui "$HISTORY_RX" 40 --any; then
      shot g-3-history-question
      expect g-3-history-question "$HISTORY_RX" 'the recovery question of the history' --any
      mark "g: history yes"
      yes_picker_allow g-4-picker g-5-allow
      mark "g: history allowed"
      emu_sleep 6
      ensure_app
    else
      shot g-3-no-history-question now
      proves_nothing "g: the history page offered no recovery"
    fi
  fi
  back_to "$HOME_RX" 20
  # restored_check reads the last restore line: one before the GPX page would pass for the pass of the page
  grep -a -q "files of a previous install restored:" full_logcat.txt \
    && fail "g: a restore line before the GPX page - the pass of the page cannot be told from it"
  mark "g: GPX page after the grant"
  if gpx_open; then
    restored_check g-restore
    emu_sleep 3
    question_shown 3 && fail "g: the question after the grant"
    still
    shot g-6-gpx-after
    expect_not g-6-gpx-after '^Restore files$' 'no restore button after the grant of the history'
  fi
  files_own g-files
  owners gpx settings profiles
  back_to "$HOME_RX" 20
  wrap_up
}

# ---- r: copies a restore left under the temporary name (.restore_<name>; the app stopped between the copy and
# the rename) take their real name on the next visit of a list, in gpx/, settings/ and profiles/ too
# (CustomQtActivity.recoverRestoreCopies, no folder grant needed). Written as the new install:
#   gpx/.restore_R1.gpx, R1.gpx free                     -> R1.gpx
#   settings/.restore_S2.qzs, S2.qzs with the same bytes -> the copy dropped
#   profiles/.restore_P3.qzs, P3.qzs with other bytes    -> P3_1.qzs, both kept
#   settings/.restore_t518-setup.qzs, the target a file of the previous install -> the copy stays
own_put() { adb shell "su $NEW_UID,$NEW_UID,9997 sh -c 'printf \"$2\" > \"$QZDIR/$1\"'" < /dev/null >> "$STEPLOG" 2>&1; }
has() { adb shell "ls '$QZDIR/$1'" < /dev/null > /dev/null 2>&1; }
own_cat() { adb shell "su $NEW_UID,$NEW_UID,9997 cat '$QZDIR/$1'" < /dev/null 2>/dev/null | tr -d '\r'; }
side_r() {
  local n
  previous_install r apk-head/android-debug.apk
  own_put "gpx/.restore_R1.gpx" "r1"
  own_put "settings/S2.qzs" "same"
  own_put "settings/.restore_S2.qzs" "same"
  own_put "profiles/P3.qzs" "old"
  own_put "profiles/.restore_P3.qzs" "new"
  own_put "settings/.restore_t518-setup.qzs" "copy"
  for f in gpx/.restore_R1.gpx settings/.restore_S2.qzs profiles/.restore_P3.qzs settings/.restore_t518-setup.qzs; do
    has "$f" || proves_nothing "r: $f not written"
  done
  adb shell "su 0 ls -laR $LOWER/gpx $LOWER/settings $LOWER/profiles" < /dev/null >> "$STEPLOG" 2>&1
  conf r-2
  mark "r: GPX page"
  if gpx_open; then
    emu_sleep 4
    question_shown 6 && tap_ui '^&?No$' '^Other folders$' 20
    shot r-1-gpx
  fi
  back_to "$HOME_RX" 20
  adb shell "su 0 ls -laR $LOWER/gpx $LOWER/settings $LOWER/profiles" < /dev/null >> "$STEPLOG" 2>&1
  n=$(grep -a "recovered from temporary copies:" full_logcat.txt | tail -n 1 | sed 's/.*copies: *//' | tr -d '\r ')
  say "recovered (log): ${n:-none}"
  if [ "$n" = 2 ]; then
    say "check r-count: 2 copies took a name (R1.gpx, P3_1.qzs): OK"
  else
    fail "check r-count: recovered '${n:-no line}', expected 2"
  fi
  if has gpx/R1.gpx && ! has gpx/.restore_R1.gpx && [ "$(own_cat gpx/R1.gpx)" = r1 ]; then
    say "check r-free: .restore_R1.gpx took the free name R1.gpx: OK"
  else
    fail "check r-free: R1.gpx not made from its copy"
  fi
  if has settings/S2.qzs && ! has settings/.restore_S2.qzs; then
    say "check r-same: the copy with the same bytes dropped, S2.qzs kept: OK"
  else
    fail "check r-same: .restore_S2.qzs left or S2.qzs gone"
  fi
  if ! has profiles/.restore_P3.qzs && [ "$(own_cat profiles/P3.qzs)" = old ] \
     && [ "$(own_cat profiles/P3_1.qzs)" = new ]; then
    say "check r-other: other bytes under P3_1.qzs, P3.qzs kept: OK"
  else
    fail "check r-other: P3.qzs / P3_1.qzs not as expected"
  fi
  if has settings/.restore_t518-setup.qzs && ! reads "$NEW_UID" "settings/t518-setup.qzs"; then
    say "check r-foreign: the copy beside a file of the previous install stays: OK"
  else
    fail "check r-foreign: .restore_t518-setup.qzs gone or the old file taken over without a pass"
  fi
  wrap_up
}

# ---- p: Restore files pressed on the profiles page - the restore runs under the open profiles list (its
# Connections inside the ListView, next to the model), which reloads after it; the GPX question answered No
side_p() {
  previous_install p apk-head/android-debug.apk
  conf p
  mark "p: GPX page"
  if gpx_open; then
    question_shown 20 && tap_ui '^&?No$' '^Other folders$' 20
  fi
  back_to "$HOME_RX" 20
  mark "p: profiles page"
  if profiles_open; then
    emu_sleep 3
    shot p-1-profiles-button
    expect p-1-profiles-button '^Restore files$' 'the restore button on the profiles page'
    if tap_ui '^Restore files$' '^&?Yes$' 20; then
      mark "p: yes"
      yes_picker_allow p-2-picker p-3-allow
      mark "p: allowed"
      restored_check p-restore
      emu_sleep 3
      ensure_app
      still
      shot p-4-profiles-after
      expect_not p-4-profiles-after '^Restore files$' 'the button gone after the restore, the profiles page still open'
      expect p-4-profiles-after '^Other folders$' 'the profiles page still open'
    fi
  fi
  files_own p-files
  back_to "$HOME_RX" 20
  wrap_up
}

# ---- t: the training programs page (TrainingProgramsListJS.qml - CHARTJS on Android): the question there
# (the first page), No; its Restore files (was "Restore programs" of T-195) - the restore runs under the open
# programs list, which reloads; the page stays, the button goes
programs_open() { open_drawer '^Open Train Program$' && tap_ui '^Open Train Program$' '^Other folders$|^&?No$'; }
side_t() {
  previous_install t apk-head/android-debug.apk
  conf t
  mark "t: programs page"
  if programs_open; then
    if question_shown 20; then
      shot t-1-question
      expect t-1-question "$QUESTION_RX" 'the question on the programs page' --any
      tap_ui '^&?No$' '^Other folders$' 20
    else
      fail "t: no question on the programs page"
    fi
    emu_sleep 3
    still
    shot t-2-programs-button
    expect t-2-programs-button '^Restore files$' 'the restore button on the programs page'
    expect_not t-2-programs-button '^Restore programs$' 'no button of T-195 left'
    if tap_ui '^Restore files$' '^&?Yes$' 20; then
      mark "t: yes"
      yes_picker_allow t-3-picker t-4-allow
      mark "t: allowed"
      restored_check t-restore
      emu_sleep 3
      ensure_app
      still
      shot t-5-programs-after
      expect_not t-5-programs-after '^Restore files$' 'the button gone, the programs page still open'
      expect t-5-programs-after '^Other folders$' 'the programs page still open'
    fi
  fi
  files_own t-files
  back_to "$HOME_RX" 20
  wrap_up
}

# ---- s: the settings file page with its "Settings folder" section open (closed by default; on h it stayed
# closed): Restore files reloads the open list, the restored settings file shows in it.
# The header and the rows have no node in the dump (Text without an accessible name, run 43229195069
# h-4-settings-button.xml), so: the header by its place (Nexus 6, frame h-4: "Settings folder" at 255 789),
# the section open by the frame - the page changes by the tap (the header moves, its arrow turns:
# StaticAccordionElement); the restored row by the frame - the open list changes after the restore.
# The log line "<file> selected" of onCurrentItemChanged is no proof: it comes with the section closed too
# (side h, full logcat of 43229195069, 13:47:07)
SET_HEADER="300 789"
# rows between the top bar (y 251, frame h-4) and the button row (Other folders from y 2307, h-4-settings-button.xml)
S_ROWS=260,2290
# frames_differ <a.raw> <b.raw> <y1,y2>: 0 - the rows differ, 1 - the same; a frame that cannot be read
# (emu_frame.py exit 2) is no answer either way
frames_differ() {
  local r
  "$EMU_PY" "$EMU_GH/emu_frame.py" diff "$1" "$2" --rows "$3" >> "$STEPLOG" 2>&1
  r=$?
  [ "$r" = 2 ] && proves_nothing "s: the frames $1 $2 cannot be read"
  [ "$r" = 1 ]
}
side_s() {
  previous_install s apk-head/android-debug.apk
  conf s
  # the question comes on the first page of a run, and with its box on screen the dump holds the box alone (run
  # 43229195069 h-1-question.xml): load_settings_open lands on Other folders - so the question is answered on
  # the GPX page first, as on h
  mark "s: GPX page"
  if gpx_open; then
    question_shown 20 && tap_ui '^&?No$' '^Other folders$' 20
  fi
  back_to "$HOME_RX" 20
  mark "s: settings file page"
  if load_settings_open; then
    emu_sleep 3
    still
    frame s_closed.raw
    shot s-1-closed
    say "tap the header 'Settings folder' at $SET_HEADER"
    adb shell input tap $SET_HEADER < /dev/null > /dev/null 2>&1
    emu_sleep 3
    still
    frame s_open.raw
    shot s-2-open
    # the page between the top bar and the button row (S_ROWS): the open section moves the header and shows its
    # list there; nothing else on the page changes by the tap
    if frames_differ s_closed.raw s_open.raw "$S_ROWS"; then
      say "check s-open: the page changed by the tap on the header - the section is open: OK"
    else
      fail "check s-open: the page did not change - the section is not open"
    fi
    expect s-2-open '^Restore files$' 'the restore button with the section open'
    if tap_ui '^Restore files$' '^&?Yes$' 20; then
      mark "s: yes"
      yes_picker_allow s-3-picker s-4-allow
      mark "s: allowed"
      restored_check s-restore
      emu_sleep 3
      ensure_app
      still
      frame s_after.raw
      shot s-5-after
      expect_not s-5-after '^Restore files$' 'the button gone after the restore'
      # the header row itself stays (the section still open); the rows under it get the restored file
      expect s-5-after '^Other folders$' 'the settings file page still open'
      # the open list was empty (its only file foreign); after the restore the row of t518-setup shows in it.
      # The toast of the restore is gone by now (3 s, restored_check + emu_sleep 3 + still before the frame)
      if frames_differ s_open.raw s_after.raw "$S_ROWS"; then
        say "check s-row: the open list changed after the restore - the restored row shows (frame s-5-after): OK"
      else
        fail "check s-row: the page as before the restore - the open list did not reload"
      fi
    fi
  fi
  files_own s-files
  back_to "$HOME_RX" 20
  wrap_up
}

# ---- k: the previous install deleted a bundled route (its .deleted_ marker left) and nothing else of the
# bundled files is foreign: the question comes by the marker alone (qzFolderHasLockedFiles). Before the
# reinstall the old app removes its bundled programs and routes (the new install copies them again as its
# own) and writes .deleted_<route>; that route is not copied again (the marker exists, homeform.cpp)
k_marker_only() {
  local uid f
  uid=$(app_uid)
  KNAME=$(adb shell "ls $QZDIR/gpx" < /dev/null 2>/dev/null | tr -d '\r' | grep '[.]gpx$' | grep -v -x -F "$ROUTE" | head -n 1)
  [ -n "$KNAME" ] || proves_nothing "k: no bundled route to mark deleted"
  while IFS= read -r f; do
    [ -n "$f" ] && adb shell "su $uid,$uid,9997 rm -f '$QZDIR/training/$f'" < /dev/null >> "$STEPLOG" 2>&1
  done < <(adb shell "ls $QZDIR/training" < /dev/null 2>/dev/null | tr -d '\r')
  while IFS= read -r f; do
    [ -n "$f" ] && [ "$f" != "$ROUTE" ] && adb shell "su $uid,$uid,9997 rm -f '$QZDIR/gpx/$f'" < /dev/null >> "$STEPLOG" 2>&1
  done < <(adb shell "ls $QZDIR/gpx" < /dev/null 2>/dev/null | tr -d '\r' | grep '[.]gpx$')
  adb shell "su $uid,$uid,9997 sh -c ': > \"$QZDIR/gpx/.deleted_$KNAME\"'" < /dev/null >> "$STEPLOG" 2>&1
  adb shell "ls -a '$QZDIR/training' '$QZDIR/gpx'" < /dev/null >> "$STEPLOG" 2>&1
  adb shell "ls '$QZDIR/gpx/.deleted_$KNAME'" < /dev/null > /dev/null 2>&1 \
    || proves_nothing "k: the marker .deleted_$KNAME not written"
  say "k: the previous install keeps only $ROUTE and the marker .deleted_$KNAME in gpx/, nothing in training/"
}
side_k() {
  BEFORE_REINSTALL=k_marker_only previous_install k apk-head/android-debug.apk
  # the marker must be foreign to the new install, else no question can come by it and k-marker-own proves
  # nothing
  if reads "$NEW_UID" "gpx/.deleted_$KNAME"; then
    proves_nothing "k: the marker .deleted_$KNAME is readable by the new install - not a file of the previous one"
  fi
  conf k
  if has "gpx/$KNAME"; then
    proves_nothing "k: $KNAME copied again in spite of its marker"
  fi
  # the bundled programs and the other routes are the new app's own: only the marker can show the case
  local f n=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    reads "$NEW_UID" "training/$f" || { n=$((n + 1)); say "foreign: training/$f"; }
  done < <(adb shell "ls $QZDIR/training" < /dev/null 2>/dev/null | tr -d '\r')
  [ "$n" = 0 ] || proves_nothing "k: $n bundled programs still foreign - the question would not come by the marker alone"
  mark "k: GPX page"
  if gpx_open; then
    if question_shown 20; then
      shot k-1-question
      expect k-1-question "$QUESTION_RX" 'the question by the marker of a deleted route' --any
    else
      fail "k: no question with only the marker of the previous install"
    fi
    if grep -a "file of a previous install" full_logcat.txt | grep -a -q -F ".deleted_$KNAME"; then
      say "check k-marker: found by the marker .deleted_$KNAME: OK"
    else
      fail "check k-marker: the log does not name the marker ($(grep -a 'file of a previous install' full_logcat.txt | tail -n 1))"
    fi
    if question_shown 3; then
      mark "k: yes"
      yes_picker_allow k-2-picker k-3-allow
      mark "k: allowed"
      restored_check k-restore
      emu_sleep 3
      ensure_app
    fi
  fi
  if reads "$NEW_UID" "gpx/.deleted_$KNAME"; then
    say "check k-marker-own: the marker is the app's own now: OK"
  else
    fail "check k-marker-own: the marker is still foreign"
  fi
  files_own k-files
  back_to "$HOME_RX" 20
  wrap_up
}

# ---- c: the folder picker cancelled (Back): no pass, no grant, the button stays, the files stay foreign. The
# cancel writes no line (CustomQtActivity.handleRestoreFolderResult, nativeOnDocumentPicked return at once):
# the proof is the picker seen, then gone, and no line of a pass after it
side_c() {
  local i f
  previous_install c apk-head/android-debug.apk
  conf c
  mark "c: GPX page"
  if gpx_open; then
    if question_shown 20 && find_ui '^&?Yes$'; then
      set -- $EMU_AT
      say "tap 'Yes' at $1 $2"
      adb shell input tap "$1" "$2" < /dev/null > /dev/null 2>&1
      for i in $(seq 1 10); do
        picker_on && break
        emu_sleep 2
      done
      if picker_on; then
        emu_sleep 3
        shot c-1-picker now
        mark "c: back in the picker"
        # Back may first go up a folder in the picker: again while it is on top, never more than 4 times
        for i in 1 2 3 4; do
          picker_on || break
          adb shell input keyevent 4 < /dev/null > /dev/null 2>&1
          emu_sleep 3
        done
        if picker_on; then
          fail "c: the picker still on top after Back"
        else
          say "check c-cancel: the picker gone after Back ($i): OK"
        fi
      else
        fail "c: the folder picker did not open"
      fi
      emu_sleep 6
      still
      shot c-2-gpx-after
      expect c-2-gpx-after '^Other folders$' 'back on the GPX page'
      expect c-2-gpx-after '^Restore files$' 'the button stays after a cancel'
    else
      fail "c: no question with Yes on the GPX page"
    fi
  fi
  if grep -a -q -E "files of a previous install restored:|handleRestoreFolderResult root=" full_logcat.txt; then
    fail "check c-pass: a restore pass after the cancel"
  else
    say "check c-pass: no restore pass after the cancel: OK"
  fi
  for f in "gpx/$ROUTE" "settings/$SETUP" "profiles/$PROFILE"; do
    if reads "$NEW_UID" "$f"; then
      fail "check c-files: $f became the app's own after a cancel"
    else
      say "check c-files: $f still foreign: OK"
    fi
  done
  back_to "$HOME_RX" 20
  wrap_up
}

# ---- u: one subfolder picked instead of Documents/QZ (gpx): only gpx/ is restored, the grant is not on the QZ
# folder, so the button stays; settings/ and profiles/ stay foreign
side_u() {
  local f
  previous_install u apk-head/android-debug.apk
  conf u
  mark "u: GPX page"
  if gpx_open; then
    question_shown 20 && tap_ui '^&?No$' '^Other folders$' 20
    emu_sleep 3
    if tap_ui '^Restore files$' '^&?Yes$' 20; then
      mark "u: yes"
      PICK_INTO="930 726" yes_picker_allow u-1-picker u-2-allow
      mark "u: allowed"
      restored_check u-restore
      emu_sleep 3
      ensure_app
      still
      shot u-3-gpx-after
      expect u-3-gpx-after '^Restore files$' 'the button stays with a grant on a subfolder'
    else
      fail "u: no question by Restore files"
    fi
  fi
  if grep -a -q "handleRestoreFolderResult root=primary:Documents/QZ/gpx gpx=" full_logcat.txt; then
    say "check u-root: the grant is on Documents/QZ/gpx: OK"
  else
    fail "check u-root: the pass did not run on Documents/QZ/gpx ($(grep -a 'handleRestoreFolderResult root=' full_logcat.txt | head -n 1))"
  fi
  if reads "$NEW_UID" "gpx/$ROUTE"; then
    say "check u-gpx: gpx/$ROUTE restored: OK"
  else
    fail "check u-gpx: gpx/$ROUTE still foreign"
  fi
  for f in "settings/$SETUP" "profiles/$PROFILE"; do
    if reads "$NEW_UID" "$f"; then
      fail "check u-other: $f restored though only gpx was picked"
    else
      say "check u-other: $f left foreign: OK"
    fi
  done
  back_to "$HOME_RX" 20
  wrap_up
}

# ---- w: the modern look, German, text at 170 %: the longest label of the button ("Dateien wiederherstellen")
# does not fit one line beside "Andere Ordner" and wraps (wrapsText) instead of eliding; both pills stay in
# one row inside the screen. The GPX, profiles and settings file pages
# wrapped <shot>: Restore files taller than Other folders (two lines), the same row, inside the screen
wrapped() {
  local a b ha hb
  a=$(uifind "dumps/$1.xml" '^Andere Ordner$' 2>/dev/null) || { fail "check $1: no 'Andere Ordner'"; return 1; }
  b=$(uifind "dumps/$1.xml" '^Dateien wiederherstellen$' 2>/dev/null) \
    || { fail "check $1: no 'Dateien wiederherstellen'"; return 1; }
  set -- "$1" $a $b
  # "x y checkable checked x1 y1 x2 y2" twice: Other folders $2..$9, Restore files ${10}..${17}
  ha=$(( $9 - $7 ))
  hb=$(( ${17} - ${15} ))
  say "check $1: Andere Ordner $6..$8 h $ha, Dateien wiederherstellen ${14}..${16} h $hb"
  # both pills take the height of the taller one (Layout.fillHeight): one line at 170 % is about 165 px on
  # Nexus 6, two lines 251 (run 43315331781, frame w-1-gpx)
  if [ "$hb" -lt 210 ]; then
    fail "!! check $1: 'Dateien wiederherstellen' in one line (h $hb) - the run proves nothing"
    return 1
  fi
  say "check $1: the label wrapped (h $hb): OK"
  if [ "$ha" -eq "$hb" ]; then
    say "check $1: both pills one height: OK"
  else
    fail "check $1: the pills differ in height ($ha / $hb)"
  fi
  if [ "$6" -lt "${14}" ] && [ "$6" -ge 0 ] && [ "${16}" -le 1440 ] && [ "$3" -ge "${15}" ] && [ "$3" -le "${17}" ]; then
    say "check $1: one row inside the screen: OK"
  else
    fail "check $1: not one row inside the screen"
  fi
}

# ---- q: "profiles.qml:20: TypeError: Cannot read property 'top' of null" came in side h after the restart, on
# the profiles page (run 43315331781, 22:07:39), and side b of master has no restart: the same steps on the
# master APK and on the branch APK - profiles, back, restart, profiles, back - and the count by process
side_q() {
  local x apk pid n
  for x in base head; do
    apk=apk-$x/android-debug.apk
    [ -s "$apk" ] || proves_nothing "side q without $apk"
    previous_install "q-$x" "$apk"
    conf "q-$x"
    if profiles_open; then
      question_shown 6 && tap_ui '^&?No$' '^Other folders$' 20
      emu_sleep 3
    fi
    back_to "$HOME_RX" 20
    conf "q-$x-restart"
    pid=$(adb shell pidof "$PKG" < /dev/null | tr -d '\r')
    if profiles_open; then emu_sleep 3; shot "q-$x-profiles-restart"; fi
    back_to "$HOME_RX" 20
    emu_sleep 2
    adb logcat -d -b all < /dev/null > ".q-$x.txt" 2>/dev/null
    n=$(grep -a " $pid " ".q-$x.txt" | grep -a -c "profiles.qml:20: TypeError")
    say "check q-$x: profiles.qml:20 TypeError after the restart (pid $pid): $n"
  done
  wrap_up
}

side_w() {
  local de='ui_modern=true fakedevice_treadmill=true app_language=de ui_text_scale_system=false ui_text_scale=170'
  previous_install w apk-head/android-debug.apk
  HOME_READY_RX='^QZ-Support kontaktieren$' start_case w $de
  mark "w: GPX page"
  # the question is a Popup over the page: Nein alone is the landing
  if open_drawer '^Öffne GPX$' && tap_ui '^Öffne GPX$' '^&?Nein$'; then
    tap_ui '^&?Nein$' '^Andere Ordner$' 20
    emu_sleep 3
    still
    shot w-1-gpx
    wrapped w-1-gpx
  fi
  back_to "$HOME_RX|^Stopp$" 20
  mark "w: profiles page"
  if open_drawer '^Profil:.*' && tap_ui '^Profil:.*' '^Andere Ordner$'; then
    emu_sleep 4
    still
    shot w-2-profiles
    wrapped w-2-profiles
  fi
  back_to "$HOME_RX|^Stopp$" 20
  mark "w: settings file page"
  if open_drawer '^Einstellungen$' && tap_ui '^Einstellungen$' '^Allgemeine Optionen$' \
      && tap_ui '^Einstellungen laden$' '^Andere Ordner$'; then
    emu_sleep 3
    still
    shot w-3-settings
    wrapped w-3-settings
  fi
  back_to "$HOME_RX|^Stopp$" 20
  wrap_up
}

case "$SIDE" in
  t) side_t ;;
  s) side_s ;;
  k) side_k ;;
  c) side_c ;;
  u) side_u ;;
  m) UI_MODERN=true side_h ;;
  w) side_w ;;
  q) side_q ;;
  p) side_p ;;
  r) side_r ;;
  b) side_b ;;
  o) side_o ;;
  d) DOCS=true side_h ;;
  g) side_g ;;
  *) side_h ;;
esac
