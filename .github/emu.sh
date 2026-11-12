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
# owner <path in Documents/QZ>: the uid owning the file, empty if there is none
owner() {
  adb shell "su 0 stat -c %u '$QZDIR/$1'" < /dev/null 2>/dev/null | tr -d '\r'
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

conf() { start_case "$1" ui_modern=$UI_MODERN fakedevice_treadmill=true; }

# seed_files: the files a user had made, written as the app (the app uid with the storage group 9997;
# run-as is shut out of /sdcard from API 30)
seed_files() {
  local uid as
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
  for f in "gpx/$ROUTE" "settings/$SETUP" "profiles/$PROFILE"; do
    [ "$(owner "$f")" = "$uid" ] || proves_nothing "seed: $f not written as the app (uid $uid)"
  done
  say "seeded as uid $uid: $ROUTE, $SETUP, $PROFILE"
}

# previous_install <side> <apk>: the files of a previous install, then the app installed again
previous_install() {
  local old new bundled
  mark "$1: previous install"
  wipe_files
  install_case "$2"
  conf "$1-first" || proves_nothing "$1: the first start did not reach home"
  bundled=$(adb shell "ls $QZDIR/gpx" < /dev/null 2>/dev/null | tr -d '\r' | grep -c '[.]gpx$')
  say "bundled routes after the first start: $bundled"
  [ "${bundled:-0}" -ge 1 ] || proves_nothing "$1: no bundled GPX routes in $QZDIR/gpx"
  seed_files
  old=$(app_uid)
  mark "$1: reinstall"
  adb shell am force-stop "$PKG" < /dev/null > /dev/null 2>&1
  adb uninstall "$PKG" < /dev/null > /dev/null 2>&1
  install_case "$2"
  new=$(app_uid)
  say "uid: previous install $old, this one $new"
  [ -n "$new" ] && [ "$new" != "$old" ] || proves_nothing "$1: the reinstall kept the uid ($old)"
  for f in "gpx/$ROUTE" "settings/$SETUP" "profiles/$PROFILE"; do
    [ "$(owner "$f")" = "$old" ] || proves_nothing "$1: $f is not a file of the previous install"
  done
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
}

# gpx_open / profiles_open: the pages from the menu
gpx_open() { open_drawer '^Open GPX$' && tap_ui '^Open GPX$' '^Other folders$'; }
profiles_open() { open_drawer '^Profile:.*' && tap_ui '^Profile:.*' '^Other folders$'; }

# the question of the restore: the native box (classic) or UiMessageDialog (modern); No/Yes
question_shown() { wait_ui "$QUESTION_RX" "${1:-20}" --any; }

emu_init
logcat_start

# ---- b: master
if [ -s apk-base/android-debug.apk ]; then
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
    if [ "$(owner "$f")" = "$OLD_UID" ]; then
      say "check b-files: $f still of the previous install (master does not restore): OK"
    else
      fail "check b-files: $f owner $(owner "$f"), expected the old $OLD_UID"
    fi
  done
fi

# ---- h: the branch
previous_install h apk-head/android-debug.apk
conf h

# 1. The GPX page asks (bundled routes of the previous install); No
mark "h: GPX page"
if gpx_open; then
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
    tap_ui '^&?Yes$' '^use this folder$' 30
    shot h-6-picker
    # the picker is another app: no tap_ui here (its ensure_app would press back on it)
    if wait_ui '^use this folder$' 15; then
      set -- $EMU_AT
      say "tap 'Use this folder' at $1 $2"
      adb shell input tap "$1" "$2" < /dev/null > /dev/null 2>&1
    else
      fail "h: the folder picker has no 'Use this folder'"
    fi
    if wait_ui '^allow$' 20; then
      shot h-7-allow
      set -- $EMU_AT
      say "tap 'Allow' at $1 $2"
      adb shell input tap "$1" "$2" < /dev/null > /dev/null 2>&1
    else
      fail "h: no 'Allow' after the folder"
    fi
    mark "h: allowed"
    # the pass runs in a thread: its line in the log (qDebug, log_debug)
    for i in $(seq 1 20); do
      grep -a -q "files of a previous install restored:" full_logcat.txt && break
      emu_sleep 3
    done
    RESTORED=$(grep -a "files of a previous install restored:" full_logcat.txt | tail -n 1 | sed 's/.*restored: *//' | tr -d '\r ')
    say "restored (log): ${RESTORED:-none}"
    if [ -n "$RESTORED" ] && [ "$RESTORED" -ge 3 ] 2>/dev/null; then
      say "check h-restore: $RESTORED files restored in one pass: OK"
    else
      fail "check h-restore: restored '${RESTORED:-no line}', expected 3 or more"
    fi
    emu_sleep 3
    ensure_app
    still
    shot h-8-settings-after
    expect_not h-8-settings-after '^Restore files$' 'the button gone after the grant'
    say "settings list rows named t518-setup: $(uifind dumps/h-8-settings-after.xml --count '^t518-setup.*' --any)"
  fi
fi

# 4. Every file of the previous install is the app's own now, no temporary copies left
for f in "gpx/$ROUTE" "settings/$SETUP" "profiles/$PROFILE"; do
  if [ "$(owner "$f")" = "$NEW_UID" ]; then
    say "check h-files: $f owned by the app ($NEW_UID): OK"
  else
    fail "check h-files: $f owner '$(owner "$f")', expected $NEW_UID"
  fi
done
LEFT=$(adb shell "su 0 ls -aR $QZDIR" < /dev/null 2>/dev/null | tr -d '\r' | grep -c '^[.]restore_')
if [ "${LEFT:-0}" = 0 ]; then
  say "check h-files: no .restore_ copies left: OK"
else
  fail "check h-files: $LEFT .restore_ copies left"
fi
FOREIGN=$(adb shell "su 0 find $QZDIR/training $QZDIR/gpx $QZDIR/settings $QZDIR/profiles -type f -user $OLD_UID" \
  < /dev/null 2>/dev/null | tr -d '\r')
if [ -z "$FOREIGN" ]; then
  say "check h-files: no file of the previous install left in the four folders: OK"
else
  fail "check h-files: files of the previous install left: $(echo "$FOREIGN" | tr '\n' ';')"
fi
adb shell "su 0 ls -lnR $QZDIR/gpx $QZDIR/settings $QZDIR/profiles" < /dev/null >> "$STEPLOG" 2>&1
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

logcat_stop
grep -a -E "T518|restored|previous install|handleRestoreFolderResult|restoreFolderFiles|openRestoreFolderPicker|recoverRestoreCopies|recovered from temporary|hasQzFolderGrant|deleteTreeDocument|takePersistableUriPermission" \
  full_logcat.txt > t518_logcat.txt
# QML errors of the changed files by side, the text after the file name (no time, no pid): an error master
# has too (T-514 run 43062774035: "mainRect is not defined" at GPXList.qml:95 on master) is not the branch's
QML_RX="(GPXList|SettingsList|profiles|TrainingProgramsList|TrainingProgramsListJS|main)\.qml.*(Error|Unable to assign|undefined)"
qml_errs() {
  awk -v a="$1" -v b="$2" 'index($0, a) { on = 1 } b != "" && index($0, b) { on = 0 } on' full_logcat.txt \
    | grep -a -o -E "$QML_RX.*" | sed -e 's/[.]qml:[0-9]*/.qml/g' | sort -u
}
qml_errs "mark b: previous install" "mark h: previous install" > qml_b.txt
qml_errs "mark h: previous install" "" > qml_h.txt
say "== QML errors of the changed files - master: $(wc -l < qml_b.txt), branch: $(wc -l < qml_h.txt)"
cat qml_h.txt >> "$STEPLOG"
comm -13 qml_b.txt qml_h.txt > qml_new.txt
if [ ! -s apk-base/android-debug.apk ]; then
  say "check qml: no master side - the errors above are not compared (read them)"
elif [ -s qml_new.txt ]; then
  say "only on the branch:"
  cat qml_new.txt >> "$STEPLOG"
  fail "check qml: errors of the changed QML files only on the branch"
else
  say "check qml: no QML error of the changed files that master does not have: OK"
fi
finish
