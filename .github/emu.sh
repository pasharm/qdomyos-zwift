#!/bin/bash
# Test only (T-528): the progress of the folder restore. After Allow in the folder picker the pass copies the
# files of a previous install one by one; the list pages show "Restoring files: N of M" over a flat bar
# (UiProgress, Accessible.ProgressBar) until the pass ends, then the list is filled and the toast
# "Files of a previous installation restored: N." comes.
#
# A side: install, start, ~40 files of a previous install (the bundled programs and routes, 16 routes, a
# settings file, a profile), reinstall - the files stay, foreign to the new uid; then the page, the question
# (or Restore files and the question), Yes, the picker, Allow, and at once a burst of dumps and frames.
#   h - GPX page, classic; m - GPX page, modern        (the pass at its own speed)
#   hs, ms - the same with a pause of SLOW_MS after each file (test only Java: files/t528_slow_ms)
#   ss, sm - settings file page, classic / modern, slow
#   ps, pm - profiles page, classic / modern, slow
# Checks: the node of the progress on the page (one, on the screen), N grows over the dumps, after the pass no
# node, the restored rows in the list, the line "files of a previous install restored: N" and the toast on the
# frames (its Text has no accessible name - Toast.qml: a frame by eye, the dark band counted for steps.log).
. .github/lib.sh
. .github/qz.sh

QZDIR=/sdcard/Documents/QZ
UI_MODERN=${UI_MODERN:-false}
ROUTE="T518 route.gpx"
SETUP="t518-setup.qzs"
PROFILE="T518 profile.qzs"
EXTRA_ROUTES=16
QUESTION_RX='(?s).*GPX routes.*previous installation.*'
PROGRESS_RX='^Restoring files: [0-9]+ of [0-9]+$'

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
  # AFTER_ALLOW: a function of the side to run at once after Allow (side n: the toast)
  if [ -n "$AFTER_ALLOW" ]; then $AFTER_ALLOW; fi
}

# ---- T-528

# seed_extra: EXTRA_ROUTES more routes of the previous install (BEFORE_REINSTALL of previous_install), so the
# pass has ~40 files; written as the app, then counted - missing ones end the run
seed_extra() {
  local uid i n name
  uid=$(app_uid)
  for i in $(seq -w 1 "$EXTRA_ROUTES"); do
    name="T528 route $i.gpx"
    sed "s/T518 route/T528 route $i/" route.gpx | \
      adb shell "su $uid,$uid,9997 sh -c 'cat > \"$QZDIR/gpx/$name\"'" >> "$STEPLOG" 2>&1
  done
  n=$(adb shell "ls $QZDIR/gpx" < /dev/null 2>/dev/null | tr -d '\r' | grep -c '^T528 route [0-9]*[.]gpx$')
  say "extra routes seeded: $n of $EXTRA_ROUTES"
  [ "$n" = "$EXTRA_ROUTES" ] || proves_nothing "seed_extra: $n of $EXTRA_ROUTES routes in $QZDIR/gpx"
  say "files of the previous install in the four folders: $(adb shell "ls -R $QZDIR/training $QZDIR/gpx $QZDIR/settings $QZDIR/profiles" < /dev/null 2>/dev/null | tr -d '\r' | grep -c '[.][a-zA-Z]*$')"
}

# slow_on <ms>: the test only pause after each file of the pass (CustomQtActivity.t528Pause)
slow_on() {
  adb shell "run-as $PKG sh -c 'echo $1 > files/t528_slow_ms'" < /dev/null >> "$STEPLOG" 2>&1
  [ "$(adb shell "run-as $PKG cat files/t528_slow_ms" < /dev/null 2>/dev/null | tr -d '\r ')" = "$1" ] \
    || proves_nothing "slow_on: files/t528_slow_ms not written"
  say "pause after each file of the pass: $1 ms"
}

# progress_watch <prefix>: at once after Allow - dumps one after another on the device (a dump takes seconds
# on CI) and PNG frames one after another, each start in logcat (tag T528), so the dumps and frames line up
# with the lines "T528 progress N/M" of the pass; pulled as dumps/<prefix>-d<n>.xml and <prefix>-f<n>.png
PW_DUMPS=${PW_DUMPS:-8}
PW_FRAMES=${PW_FRAMES:-24}
progress_watch() {
  local p i
  adb shell "rm -f /data/local/tmp/$1-*" < /dev/null > /dev/null 2>&1
  adb shell "for i in $(seq -s ' ' 1 "$PW_DUMPS"); do log -t T528 \"dump $1-d\$i\"; uiautomator dump /data/local/tmp/$1-d\$i.xml; done" \
    < /dev/null > /dev/null 2>&1 &
  p=$!
  # raw frames (no -p: no PNG coding on the device, more frames a second); raw_frame.py writes the PNG
  adb shell "for i in $(seq -s ' ' 1 "$PW_FRAMES"); do log -t T528 \"frame $1-f\$i\"; screencap /data/local/tmp/$1-f\$i.raw; done" \
    < /dev/null > /dev/null 2>&1
  wait "$p"
  mkdir -p dumps
  for i in $(seq 1 "$PW_DUMPS"); do
    adb pull "/data/local/tmp/$1-d$i.xml" "dumps/$1-d$i.xml" < /dev/null > /dev/null 2>&1
  done
  # the toast by its dark band (Toast.qml: #222222 at 0.9) in rows 2250-2450 (Nexus 6, T-518 run
  # 43368164916: ~110000 dark pixels with it, ~2000 without on the modern page); the classic page is dark
  # itself - there the frames by eye
  TOAST_FRAMES=0
  for i in $(seq 1 "$PW_FRAMES"); do
    adb pull "/data/local/tmp/$1-f$i.raw" "$1-f$i.raw" < /dev/null > /dev/null 2>&1
    adb shell "rm -f /data/local/tmp/$1-f$i.raw" < /dev/null > /dev/null 2>&1
    [ -s "$1-f$i.raw" ] || continue
    set -- "$1" $("$EMU_PY" .github/raw_frame.py "$1-f$i.raw" "$1-f$i.png" 2250 2450)
    rm -f "$1-f$i.raw"
    say "  $1-f$i: ${2:-?} dark pixels in rows 2250-2450"
    [ "${2:-0}" -ge 50000 ] && TOAST_FRAMES=$((TOAST_FRAMES + 1))
    set -- "$1"
  done
  say "progress_watch $1: $(ls dumps/$1-d*.xml 2>/dev/null | wc -l) dumps, $(ls $1-f*.png 2>/dev/null | wc -l) frames"
}

# progress_check <prefix> <required>: the node in each dump of the burst - its name, how many on the screen;
# required=yes (slow sides): at least two dumps with it and N growing, else a failure
progress_check() {
  local f name n last=-1 seen=0 grew=0 shrank=0 i
  for i in $(seq 1 "$PW_DUMPS"); do
    f="dumps/$1-d$i.xml"
    if [ ! -s "$f" ]; then
      say "  $1-d$i: no dump"
      continue
    fi
    n=$(uifind "$f" --count "$PROGRESS_RX" 2>/dev/null)
    name=$(uifind "$f" "$PROGRESS_RX" --name 2>/dev/null)
    say "  $1-d$i: on the screen ${n:-0}, name '${name:-none}', all in the dump $(uifind "$f" --count "$PROGRESS_RX" --any 2>/dev/null)"
    [ "${n:-0}" -gt 1 ] && fail "check $1-d$i: $n progress nodes on the screen, one expected"
    if [ -n "$name" ]; then
      seen=$((seen + 1))
      set -- "$1" "$2" $(echo "$name" | tr -cs '0-9' ' ')
      say "  $1-d$i: N=$3 M=$4"
      if [ "$last" -ge 0 ]; then
        [ "$3" -gt "$last" ] && grew=1
        [ "$3" -lt "$last" ] && shrank=1
      fi
      last=$3
      set -- "$1" "$2"
    fi
  done
  say "progress_check $1: the node in $seen dumps, N grew: $grew, N fell back: $shrank"
  [ "$shrank" = 1 ] && fail "check $1: N fell back between dumps"
  if [ "$seen" -ge 1 ]; then
    say "check $1-node: 'Restoring files: N of M' on the page after Allow: OK"
  elif [ "$2" = yes ]; then
    fail "check $1-node: no progress node in the dumps after Allow"
  else
    near progress "$1: the pass at its own speed ended before a dump caught the node"
  fi
  if [ "$grew" = 1 ]; then
    say "check $1-grows: N grows over the dumps: OK"
  elif [ "$2" = yes ]; then
    fail "check $1-grows: N did not grow over the dumps (seen in $seen)"
  fi
}

# pass_log <prefix>: the pass in logcat - files to restore, the first and the last step, the restored line,
# the dumps and frames of the burst between them
pass_log() {
  local i
  for i in $(seq 1 30); do
    grep -a -q "files of a previous install restored:" full_logcat.txt && break
    emu_sleep 2
  done
  say "-- $1: the pass in logcat"
  grep -a -E "files to restore|T528 progress|T528 *: (dump|frame)|files of a previous install restored:" full_logcat.txt \
    | sed -n '1,400p' >> "$STEPLOG"
  say "files to restore (log): $(grep -a 'files to restore' full_logcat.txt | tail -n 1 | sed 's/.*restore //' | tr -d '\r')"
  say "progress steps (log): $(grep -a -c 'T528 progress' full_logcat.txt), last $(grep -a 'T528 progress' full_logcat.txt | tail -n 1 | sed 's/.*progress //' | tr -d '\r')"
  RESTORED=$(grep -a "files of a previous install restored:" full_logcat.txt | tail -n 1 | sed 's/.*restored: *//' | tr -d '\r ')
  if [ -n "$RESTORED" ] && [ "$RESTORED" -ge 20 ] 2>/dev/null; then
    say "check $1-restored: $RESTORED files restored in one pass: OK"
  else
    fail "check $1-restored: restored '${RESTORED:-no line}', expected 20 or more"
  fi
}

# the page of the side: open, the question at once or by Restore files, Yes, picker, Allow, the burst
page_open() {
  case "$PAGE" in
    # modern: the question is a Popup over the page, Other folders stays in the dump - No alone is the landing
    # (T-518 side m); the other pages land on Other folders, a question there is caught by question_shown
    gpx) if [ "$UI_MODERN" = true ]; then gpx_open '^&?No$'; else gpx_open; fi ;;
    settings) load_settings_open ;;
    profiles) profiles_open ;;
  esac
}
row_rx() {
  case "$PAGE" in
    gpx) echo '^T528 route 09.*' ;;
    settings) echo '^t518-setup.*' ;;
    profiles) echo '^T518 profile.*' ;;
  esac
}

side_t528() {
  local p=$SIDE rows
  previous_install "$p" apk-head/android-debug.apk
  conf "$p" || proves_nothing "$p: the start after the reinstall did not reach home"
  [ -n "$SLOW_MS" ] && slow_on "$SLOW_MS"
  mark "$p: $PAGE page"
  page_open || near page "$p: the landing of the $PAGE page not seen - the question or the button decides"
  if question_shown 15; then
    say "the question at once on the $PAGE page"
  else
    still
    shot "$p-1-before"
    expect "$p-1-before" '^Restore files$' "the restore button on the $PAGE page"
    tap_ui '^Restore files$' '^&?Yes$' 20 || proves_nothing "$p: no question by Restore files"
    question_shown 10 || proves_nothing "$p: no question by Restore files"
  fi
  shot "$p-2-question" now
  expect "$p-2-question" "$QUESTION_RX" 'the question of the restore' --any
  rows=$(uifind "dumps/$p-2-question.xml" --count "$(row_rx)" --any 2>/dev/null)
  say "restored rows ($(row_rx)) under the question, before the pass: ${rows:-0}"
  mark "$p: yes"
  AFTER_ALLOW="progress_watch $p-3-pass" yes_picker_allow "$p-2-picker" "$p-2-allow"
  mark "$p: allowed"
  pass_log "$p"
  progress_check "$p-3-pass" "${SLOW_MS:+yes}"
  say "toast: the dark band on ${TOAST_FRAMES:-0} frames of the burst"
  emu_sleep 3
  ensure_app
  still
  shot "$p-4-after"
  expect_not "$p-4-after" "$PROGRESS_RX" 'no progress node after the pass' --any
  expect "$p-4-after" "$(row_rx)" 'the restored row in the list after the pass' --any
  say "rows of the list after the pass: $(uifind "dumps/$p-4-after.xml" --count "$(row_rx)" --any 2>/dev/null) ($(row_rx))"
  expect_not "$p-4-after" '^Restore files$' 'the button gone after the grant'
  back_to "$HOME_RX" 20
  wrap_up
}

# wrap_up: the lines of the change and the QML errors of the changed files (listed; one naming UiProgress
# or folderRestore is the change's), the end of the run (finish exits)
wrap_up() {
  logcat_stop
  grep -a -E "T528|restored|previous install|handleRestoreFolderResult|restoreFolderFiles|folderRestore|UiProgress" \
    full_logcat.txt > t528_logcat.txt
  grep -a -o -E "(GPXList|SettingsList|profiles|TrainingProgramsList|TrainingProgramsListJS|UiProgress|main)\.qml.*" full_logcat.txt \
    | grep -a -E "Error|Unable to assign|undefined|ReferenceError|TypeError" | tr -d '\r' | sort -u > qml_side.txt
  say "== QML errors of the changed files ($SIDE): $(wc -l < qml_side.txt)"
  cat qml_side.txt >> "$STEPLOG"
  if grep -a -q -E "UiProgress|folderRestore" qml_side.txt; then
    fail "check qml: QML errors of the progress (UiProgress, folderRestore*)"
  else
    say "check qml: no QML error of the progress: OK"
  fi
  finish
}

emu_init
logcat_start
BEFORE_REINSTALL=seed_extra
SIDE=${SIDE:-h}
say "side $SIDE"
case "$SIDE" in
  h) PAGE=gpx UI_MODERN=false side_t528 ;;
  m) PAGE=gpx UI_MODERN=true side_t528 ;;
  hs) PAGE=gpx UI_MODERN=false SLOW_MS=800 side_t528 ;;
  ms) PAGE=gpx UI_MODERN=true SLOW_MS=800 side_t528 ;;
  ss) PAGE=settings UI_MODERN=false SLOW_MS=800 side_t528 ;;
  sm) PAGE=settings UI_MODERN=true SLOW_MS=800 side_t528 ;;
  ps) PAGE=profiles UI_MODERN=false SLOW_MS=800 side_t528 ;;
  pm) PAGE=profiles UI_MODERN=true SLOW_MS=800 side_t528 ;;
  *) proves_nothing "unknown side $SIDE" ;;
esac
