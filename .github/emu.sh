#!/bin/bash
# Test only (T-528): the progress of the folder restore. After Allow in the folder picker the pass copies the
# files of a previous install one by one; the list pages show the progress above the list (c8925db6c): "Restoring files of the previous installation" and "N / M" over a flat bar
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
PROGRESS_RX='^Restoring files of the previous installation: [0-9]+ of [0-9]+$'

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
  # the question of a restore may come at once: a native box, its dump is the box alone - its No is a
  # landing too (run 43523520888, ss: the box with No, 'Other folders' under it not in the dump)
  if wait_ui '^Other folders$|^&?No$' 15; then
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
profiles_open() { open_drawer '^Profile:.*' && tap_ui '^Profile:.*' "${1:-^Other folders$|^&?No$}"; }
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

# seed_root: BIG_ROOT=true - ROOT_FILES empty chart-NNNN.png in the root of the QZ folder, as the app (the phone
# of the user: 1442 files there, chart images and logs; the pass listed the root once per subfolder - 9.2 s
# before the bar, T-528); counted after, a shortfall ends the run
ROOT_FILES=${ROOT_FILES:-1500}
seed_root() {
  local uid n
  uid=$(app_uid)
  adb shell "su $uid,$uid,9997 sh -c 'cd $QZDIR && i=1; while [ \$i -le $ROOT_FILES ]; do : > chart-\$i.png; i=\$((i + 1)); done'" \
    < /dev/null >> "$STEPLOG" 2>&1
  n=$(adb shell "ls $QZDIR" < /dev/null 2>/dev/null | tr -d '\r' | grep -c '^chart-[0-9]*[.]png$')
  say "files in the root of the QZ folder: $n chart-*.png of $ROOT_FILES"
  [ "$n" = "$ROOT_FILES" ] || proves_nothing "seed_root: $n of $ROOT_FILES files in $QZDIR"
}
seed_all() {
  seed_extra
  [ "$BIG_ROOT" = true ] && seed_root
  return 0
}

# root_gap <side>: seconds from the return to QZ after Allow (wm_on_resume_called, events buffer) to the line
# "handleRestoreFolderResult files to restore N"; GAP_MAX set (the side after the change) - more is a failure
root_gap() {
  local g
  adb logcat -d -b events -v threadtime < /dev/null > events_logcat.txt 2>/dev/null
  g=$("$EMU_PY" .github/t528_gap.py events_logcat.txt full_logcat.txt "$PKG")
  if [ -z "$g" ]; then
    fail "check $1-gap: no resume or no 'files to restore' line ($(grep -c wm_on_resume_called events_logcat.txt) resumes)"
    return
  fi
  set -- "$1" $g
  say "big root: $2 s from the return to QZ ($3) to 'files to restore' ($4)"
  if [ -n "$GAP_MAX" ]; then
    if awk -v g="$2" -v m="$GAP_MAX" 'BEGIN { exit !(g < m) }'; then
      say "check $1-gap: $2 s to the count with $ROOT_FILES files in the root, under $GAP_MAX s: OK"
    else
      fail "check $1-gap: $2 s to the count with $ROOT_FILES files in the root, $GAP_MAX s or more"
    fi
  fi
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
  # after the dumps of the pass: one more 1.5 s after the line of the end of the pass (dumps/<prefix>-e.xml) -
  # UiProgress holds the count 1 s and closes in 200 ms (c8925db6c), so the node is gone there and the list back
  # (one uiautomator at a time: in the same loop, not a job of its own; on the fast sides the dumps of the pass
  # may end after the pass - then later than 1.5 s, the log lines tell)
  adb shell "for i in $(seq -s ' ' 1 "$PW_DUMPS"); do log -t T528 \"dump $1-d\$i\"; uiautomator dump /data/local/tmp/$1-d\$i.xml; done; timeout 120 logcat -m 1 -e 'files of a previous install restored' > /dev/null; sleep 1.5; log -t T528 \"dump $1-e\"; uiautomator dump /data/local/tmp/$1-e.xml" \
    < /dev/null > /dev/null 2>&1 &
  p=$!
  if [ "$END_BURST" = true ]; then
    # END_BURST: frames one after another from the start of the last but one file (T528 progress 37/) - the
    # last count held ~1 s after the pass and the closing (200 ms); they hold the toast too (toast_watch)
    adb shell "timeout 120 logcat -m 1 -e 'T528 progress 37/' > /dev/null; log -t T528 \"end burst $1\"; for i in $(seq -s ' ' 1 "$END_FRAMES"); do log -t T528 \"frame $1-e\$i\"; screencap /data/local/tmp/$1-e\$i.raw; done" \
      < /dev/null > /dev/null 2>&1 &
  else
    # the toast comes when the pass ends (9-33 s after Allow, run 43444695400 - after the burst): a burst of its
    # own, started on the device by the line of the end of the pass (logcat -m 1 waits for it), 3 s of toast
    adb shell "timeout 120 logcat -m 1 -e 'files of a previous install restored' > /dev/null; log -t T528 \"toast burst $1\"; for i in 1 2 3 4 5 6 7 8; do screencap /data/local/tmp/$1-t\$i.raw; done" \
      < /dev/null > /dev/null 2>&1 &
  fi
  TOAST_PID=$!
  [ "$ROT" = true ] && rot_job "$1"
  # raw frames (no -p: no PNG coding on the device, more frames a second); raw_frame.py writes the PNG
  adb shell "for i in $(seq -s ' ' 1 "$PW_FRAMES"); do log -t T528 \"frame $1-f\$i\"; screencap /data/local/tmp/$1-f\$i.raw; done" \
    < /dev/null > /dev/null 2>&1
  wait "$p"
  mkdir -p dumps
  for i in $(seq 1 "$PW_DUMPS"); do
    adb pull "/data/local/tmp/$1-d$i.xml" "dumps/$1-d$i.xml" < /dev/null > /dev/null 2>&1
  done
  adb pull "/data/local/tmp/$1-e.xml" "dumps/$1-e.xml" < /dev/null > /dev/null 2>&1
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
    say "  $1-f$i: ${2:-?} dark pixels in rows 2250-2450, ${3:-?} x ${4:-?}$([ "${3:-0}" -gt "${4:-0}" ] && echo ' landscape')"
    [ "${2:-0}" -ge 50000 ] && TOAST_FRAMES=$((TOAST_FRAMES + 1))
    set -- "$1"
  done
  say "progress_watch $1: $(ls dumps/$1-d*.xml 2>/dev/null | wc -l) dumps, $(ls $1-f*.png 2>/dev/null | wc -l) frames"
  if [ "$ROT" = true ]; then
    wait "$ROT_PID"
    ROT_LAND=0
    for i in $(seq 1 16); do
      raw_pull "$1-r$i" && ROT_LAND=$((ROT_LAND + 1))
    done
    say "rotation frames $1-r1..r16: $ROT_LAND landscape (r1-r8 after the turn to landscape, r9-r16 after the turn back)"
    if [ "$ROT_LAND" -ge 1 ] && [ "$ROT_LAND" -lt 16 ]; then
      say "check $1-turned: landscape and upright frames in the middle of the pass: OK"
    else
      fail "check $1-turned: $ROT_LAND of 16 rotation frames in landscape - the turn did not happen as planned"
    fi
  fi
  if [ "$LAND" = true ]; then
    LAND_N=$(grep -c "^  $1-f[0-9]*: .*landscape" "$STEPLOG")
    if [ "$LAND_N" -ge 1 ]; then
      say "check $1-landscape: $LAND_N frames of the pass in landscape: OK"
    else
      proves_nothing "$1: no frame of the pass in landscape"
    fi
  fi
}

# button_check <prefix>: "Restore files" is grey while the pass runs (enabled: rootItem.folderRestoreTotal === 0,
# 717777efd) - in each dump of the burst with the progress node its enabled is false; enabled true there
# fails (the build of run 43452662472 had it true, t528_enabled.py on ms-3-pass-d2, ps-3-pass-d2)
button_check() {
  local i f e hidden=0 shown=0
  # Qt 5.15.0 gives every node enabled=true: QAccessibleQuickItem::state() never sets disabled from
  # item()->isEnabled() (qtdeclarative v5.15.0 qaccessiblequickitem.cpp:179-201), the delegate passes
  # !state.disabled (qtbase androidjniaccessibility.cpp:262) - run 43462330183: enabled=true in every dump while
  # the frames show the button grey. The branch hides the grey button from the tree (Accessible.ignored:
  # !enabled, 11bd9757f): in each dump of the pass with the progress node there is no "Restore files" node;
  # the grey itself - on the frames
  for i in $(seq 1 "$PW_DUMPS"); do
    f="dumps/$1-d$i.xml"
    [ -s "$f" ] || continue
    uifind "$f" "$PROGRESS_RX" --any > /dev/null 2>&1 || continue
    e=$("$EMU_PY" .github/t528_enabled.py "$f" "Restore files")
    say "  $1-d$i: progress on, 'Restore files' node: ${e:+there (enabled $e)}${e:-none}"
    if [ -n "$e" ]; then shown=$((shown + 1)); else hidden=$((hidden + 1)); fi
  done
  say "button_check $1: dumps with the progress - without the button $hidden, with it $shown"
  if [ "$shown" -gt 0 ]; then
    fail "check $1-hidden: 'Restore files' in the tree while the restore runs ($shown dumps)"
  elif [ "$hidden" -gt 0 ]; then
    say "check $1-hidden: no 'Restore files' node while the restore runs ($hidden dumps): OK"
  elif [ -n "$SLOW_MS" ]; then
    fail "check $1-hidden: no dump with the progress node"
  fi
}

# toast_watch <prefix>: the frames of the burst at the end of the pass (progress_watch), the dark band counted
toast_watch() {
  local i k=t n=8
  wait "$TOAST_PID"
  # END_BURST: the frames of the end of the pass (progress_watch) hold the toast
  [ "$END_BURST" = true ] && { k=e; n=$END_FRAMES; }
  TOAST_FRAMES=0
  for i in $(seq 1 "$n"); do
    adb pull "/data/local/tmp/$1-$k$i.raw" "$1-$k$i.raw" < /dev/null > /dev/null 2>&1
    adb shell "rm -f /data/local/tmp/$1-$k$i.raw" < /dev/null > /dev/null 2>&1
    [ -s "$1-$k$i.raw" ] || continue
    set -- "$1" $("$EMU_PY" .github/raw_frame.py "$1-$k$i.raw" "$1-$k$i.png" 2250 2450)
    rm -f "$1-$k$i.raw"
    say "  $1-$k$i: ${2:-?} dark pixels in rows 2250-2450"
    [ "${2:-0}" -ge 50000 ] && TOAST_FRAMES=$((TOAST_FRAMES + 1))
    set -- "$1"
  done
  say "toast_watch $1: $(ls $1-$k*.png 2>/dev/null | wc -l) frames at the end of the pass, the dark band on $TOAST_FRAMES"
  if [ "$LAND" = true ]; then
    # rows 2250-2450 are the bottom of the upright Nexus 6 screen; in landscape it is 1440 high
    say "landscape: the toast on the frames $1-t* by eye"
  elif [ "$UI_MODERN" = true ]; then
    if [ "$TOAST_FRAMES" -ge 1 ]; then
      say "check $1-toast: the toast band on $TOAST_FRAMES frames at the end of the pass: OK"
    else
      fail "check $1-toast: no toast band on the frames at the end of the pass"
    fi
  else
    say "classic: the page is dark itself - the toast on the frames $1-t* by eye"
  fi
}

# screen_wh: "width height" of the screen now, by the header of a raw frame
screen_wh() {
  adb exec-out "screencap | head -c 8" < /dev/null 2>/dev/null | od -An -tu4 | tr -s ' ' | sed 's/^ //'
}

# turn_to <0|1> <why>: the screen upright (0) or in landscape (1); emu_init turned auto-rotation off.
# The turn is waited for by the frame size, the setting given again on each look: in run 43476967975 the screen
# did not follow it (hl, pl stayed upright; ml stayed in landscape for the folder picker, its Allow missed) and
# went back by itself 1-2 s after a turn in the middle of the pass (hr, mr, pr frames r2-r4 only)
turn_to() {
  local i w h
  adb shell log -t T528 "\"turn $1: $2\"" < /dev/null > /dev/null 2>&1
  for i in $(seq 1 12); do
    adb shell settings put system accelerometer_rotation 0 < /dev/null > /dev/null 2>&1
    adb shell settings put system user_rotation "$1" < /dev/null > /dev/null 2>&1
    emu_sleep 2
    set -- "$1" "$2" $(screen_wh)
    if [ -n "$4" ] && { { [ "$1" = 1 ] && [ "$3" -gt "$4" ]; } || { [ "$1" = 0 ] && [ "$3" -lt "$4" ]; }; }; then
      say "turn the screen to $1 ($2): $3 x $4 after $i looks"
      return 0
    fi
  done
  fail "turn the screen to $1 ($2): still ${3:-?} x ${4:-?} after 12 looks"
  return 1
}

# rot_job <prefix>: ROT=true - on the device, by the line of the 10th file of the pass: landscape, frames
# <prefix>-r1..r8 one after another, upright again, frames r9..r16; each frame and turn in logcat (tag T528)
rot_job() {
  adb shell "timeout 120 logcat -m 1 -e 'T528 progress 10/' > /dev/null; log -t T528 'turn 1: the middle of the pass'; settings put system user_rotation 1; for i in 1 2 3 4 5 6 7 8; do log -t T528 \"frame $1-r\$i\"; screencap /data/local/tmp/$1-r\$i.raw; sleep 0.3; done; log -t T528 'turn 0: back upright'; settings put system user_rotation 0; for i in 9 10 11 12 13 14 15 16; do log -t T528 \"frame $1-r\$i\"; screencap /data/local/tmp/$1-r\$i.raw; sleep 0.3; done" \
    < /dev/null > /dev/null 2>&1 &
  ROT_PID=$!
}

# raw_pull <name>: /data/local/tmp/<name>.raw to <name>.png; says the size (landscape - width > height)
raw_pull() {
  adb pull "/data/local/tmp/$1.raw" "$1.raw" < /dev/null > /dev/null 2>&1
  adb shell "rm -f /data/local/tmp/$1.raw" < /dev/null > /dev/null 2>&1
  [ -s "$1.raw" ] || return 1
  set -- "$1" $("$EMU_PY" .github/raw_frame.py "$1.raw" "$1.png" 0 0)
  rm -f "$1.raw"
  say "  $1: ${3:-?} x ${4:-?}$([ "${3:-0}" -gt "${4:-0}" ] && echo ' landscape')"
  [ "${3:-0}" -gt "${4:-0}" ]
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
      say "  $1-d$i: N=$3 M=$4, at $(uifind "$f" "$PROGRESS_RX" 2>/dev/null) (x y - - x1 y1 x2 y2), screen $(dump_size "$f")"
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
    say "check $1-node: 'Restoring files of the previous installation: N of M' on the page after Allow: OK"
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

# density: px per dp of the screen (wm density / 160; Nexus 6 - 560, 3.5)
density() {
  adb shell wm density < /dev/null 2>/dev/null | tr -d '\r' | awk '{ d = $NF } END { if (d > 0) printf "%g", d / 160 }'
}

# geom_check <prefix>: c8925db6c puts the progress above the list (PLACE=above; the classic settings file and
# profile pages keep it under their list - PLACE=below) and moves the list down by its height. In each dump of
# the pass with the node: the node, the node above it, the first node under its top (a row of the list or the
# scroll bar of the list - the classic rows have no node), the nodes crossing it; the bar bottom on the frames
# of the burst (t528_geom.py). Checks on the last such dump: (a) no node crosses the progress, the first node
# under it starts at its bottom or lower; (b) the gap from the bar to that node ~12 dp (UiProgress bottomPadding
# 12; numbers only - +-2 px is a near, not a failure); GEOM_P, GEOM_A for after_check
geom_check() {
  local i f g last="" dp
  GEOM_P=""
  GEOM_A=""
  dp=${DP:-3.5}
  for i in $(seq 1 "$PW_DUMPS"); do
    f="dumps/$1-d$i.xml"
    [ -s "$f" ] || continue
    uifind "$f" "$PROGRESS_RX" > /dev/null 2>&1 || continue
    g=$("$EMU_PY" .github/t528_geom.py pass "$f" "$PROGRESS_RX" "$dp" $(ls "$1"-f*.png 2>/dev/null | sort -V))
    say "  geom $1-d$i: $g"
    last=$g
  done
  if [ -z "$last" ]; then
    near geom "$1: no dump of the pass with the node - the place not measured"
    return
  fi
  say "geom $1 ($PLACE the list, the last dump with the node): $last"
  set -- "$1" $last
  local kv p a r gap_node gap_bar bar cross
  for kv in "${@:2}"; do
    case "$kv" in
      p=*) p=${kv#p=} ;;
      a=*) a=${kv#a=} ;;
      r=*) r=${kv#r=} ;;
      gap_node=*) gap_node=${kv#gap_node=} ;;
      gap_bar=*) gap_bar=${kv#gap_bar=} ;;
      bar=*) bar=${kv#bar=} ;;
      cross=*) cross=${kv#cross=} ;;
    esac
  done
  GEOM_P=$p
  GEOM_A=$a
  if [ "$cross" = none ]; then
    say "check $1-overlap: no node crosses the progress ($p): OK"
  else
    fail "check $1-overlap: nodes cross the progress ($p): $cross"
  fi
  if [ "$gap_node" = "?" ]; then
    near geom "$1: no node under the progress"
  elif [ "$gap_node" -ge 0 ]; then
    say "check $1-under: the first node under the progress ($r) starts $gap_node px below its bottom: OK"
  else
    fail "check $1-under: the first node under the progress ($r) starts $(( -gap_node )) px above its bottom"
  fi
  if [ "$gap_bar" = "?" ]; then
    near geom "$1: the bar not found on the frames inside $p - the gap not measured"
  else
    local want
    want=$(awk -v d="$dp" 'BEGIN { printf "%d", 12 * d + 0.5 }')
    say "gap $1: the bar bottom y $bar, the first node under it at y $(echo "$r" | cut -d, -f2); bar to node $gap_bar px = $(awk -v g="$gap_bar" -v d="$dp" 'BEGIN { printf "%.1f", g / d }') dp (12 dp = $want px)"
    if [ "$PLACE" = above ]; then
      if [ $(( gap_bar - want )) -le 2 ] && [ $(( want - gap_bar )) -le 2 ]; then
        say "check $1-gap: $gap_bar px from the bar to the list, 12 dp = $want: OK"
      else
        near gap "$1: $gap_bar px from the bar to the list, 12 dp = $want"
      fi
    fi
  fi
}

# after_check <prefix>: the dump 1.5 s after the line of the end of the pass (progress_watch, dumps/<prefix>-e.xml):
# (c) no node of the progress; PLACE=above - the first node under the node above the progress is back where the
# progress started (the list takes its place, c8925db6c: the list topMargin back from -spacing) and, in the
# modern look, where it was under the question before the pass (the question there is a Popup over the page)
after_check() {
  local f="dumps/$1-e.xml" x1 x2 ya py y pre="" t0 t1
  t0=$(grep -a "files of a previous install restored:" full_logcat.txt | tail -n 1 | awk '{ print $2 }')
  t1=$(grep -a "T528.*dump $1-e" full_logcat.txt | tail -n 1 | awk '{ print $2 }')
  say "after $1: the pass ended $t0, the dump $1-e started $t1"
  if [ ! -s "$f" ]; then
    fail "check $1-after: no dump after the pass"
    return
  fi
  if [ "$(uifind "$f" --count "$PROGRESS_RX" --any 2>/dev/null)" = 0 ]; then
    say "check $1-after: no progress node 1.5 s after the pass: OK"
  else
    fail "check $1-after: the progress node still there 1.5 s after the pass ($(uifind "$f" "$PROGRESS_RX" --any --name 2>/dev/null))"
  fi
  # the map under the list (modern GPX, portrait) stays where it is on master while the progress shows: the
  # progress takes its height from the list, not from the map (the map took it in run 43541767718: 1643 against
  # 1513 on master). The map is not in the dump - measured on the frame of the pass (t528_map_top.py)
  if [ -n "$MAP_TOP" ]; then
    local mf mt
    mf=$(ls "$1"-f8.png "$1"-f*.png 2>/dev/null | head -n 1)
    if [ "${DP:-}" != 3.5 ] || [ "${EMU_API:-}" != 35 ]; then
      near map "$1: the reference $MAP_TOP is for API 35 at 3.5 px per dp, here API ${EMU_API:-unknown} - not compared"
    elif [ -z "$mf" ]; then
      fail "check $1-map: no frame of the pass"
    else
      mt=$("$EMU_PY" .github/t528_map_top.py "$mf" 720 700 2250)
      if [ -n "$mt" ] && [ $(( mt - MAP_TOP )) -le 3 ] && [ $(( MAP_TOP - mt )) -le 3 ]; then
        say "check $1-map: the map starts at $mt during the pass ($mf), at $MAP_TOP on master (run 43461222005): OK"
      else
        fail "check $1-map: the map starts at ${mt:-not found} during the pass ($mf), at $MAP_TOP on master (run 43461222005)"
      fi
    fi
  fi
  [ "$PLACE" = above ] || return 0
  if [ -z "$GEOM_P" ] || [ -z "$GEOM_A" ] || [ "$GEOM_A" = none ]; then
    near geom "$1: no place of the progress from the pass - the list after it not measured"
    return
  fi
  set -- "$1" $(echo "$GEOM_P" | tr ',' ' ')
  x1=$2; py=$3; x2=$4
  ya=$(echo "$GEOM_A" | cut -d: -f1 | cut -d, -f4)
  set -- "$1" $("$EMU_PY" .github/t528_geom.py after "$f" "$x1" "$x2" "$ya" "${DP:-3.5}")
  y=$2
  # QDUMP: the dump of the question (side_t528); the classic question is a native box - its dump is the box
  if [ "$UI_MODERN" = true ] && [ -s "$QDUMP" ]; then
    pre=$("$EMU_PY" .github/t528_geom.py after "$QDUMP" "$x1" "$x2" "$ya" "${DP:-3.5}" | cut -d' ' -f1)
  fi
  say "after $1: the first node under the node above (bottom $ya): ${2:-none} ${3:-} - the progress started at $py, before the pass (the question) ${pre:-not measured}; the gap above the list $(( ${y:-0} - ya )) px"
  if [ -z "$y" ]; then
    near geom "$1: no node under the node above after the pass"
    return
  fi
  if [ $(( y - py )) -le 2 ] && [ $(( py - y )) -le 2 ]; then
    say "check $1-back: the list starts at $y, where the progress started ($py): OK"
  else
    fail "check $1-back: the list starts at $y after the pass, the progress started at $py"
  fi
  if [ -n "$pre" ]; then
    if [ $(( y - pre )) -le 2 ] && [ $(( pre - y )) -le 2 ]; then
      say "check $1-back-pre: the list starts at $y after the pass, at $pre before it: OK"
    else
      # an empty list under the question has no node at its top: the first node there is the box itself
      near back "$1: the list starts at $y after the pass, the first node under the question at $pre (an empty list has no node at its top)"
    fi
  fi
  # against a run known good, not only against this one: a gap that stays the same before and after the pass
  # passes -back-pre (run 43523520888, ml: 781 before and after the pass; -back caught it there only because the
  # progress shown during the pass started at 490), and the list itself moved down would pass both; the list at
  # 490 in run 43489689380 on 82da00a41 (a hidden progress in its own row of the grid under the map)
  if [ -n "$LIST_TOP" ]; then
    if [ "${DP:-}" != 3.5 ] || [ "${EMU_API:-}" != 35 ]; then
      near top "$1: the reference $LIST_TOP is for API 35 at 3.5 px per dp (1440 x 2560), here API ${EMU_API:-unknown} at ${DP:-unknown} - not compared"
    elif [ $(( y - LIST_TOP )) -le 2 ] && [ $(( LIST_TOP - y )) -le 2 ]; then
      say "check $1-top: the list starts at $y after the pass, $LIST_TOP in run 43489689380: OK"
    else
      fail "check $1-top: the list starts at $y after the pass, at $LIST_TOP in run 43489689380 ($(( y - LIST_TOP )) px)"
    fi
    # under the question the first node may be the box of the question, not a row: a near only
    if [ "${DP:-}" = 3.5 ] && [ "${EMU_API:-}" = 35 ] && [ -n "$pre" ] && { [ $(( pre - LIST_TOP )) -gt 2 ] || [ $(( LIST_TOP - pre )) -gt 2 ]; }; then
      near top "$1: the first node under the question at $pre, the list at $LIST_TOP in run 43489689380"
    fi
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
    # modern: the same Popup over the page, both in the dump after Profile: (run 43523520888, pm)
    profiles) if [ "$UI_MODERN" = true ]; then profiles_open '^&?No$'; else profiles_open; fi ;;
  esac
}
row_rx() {
  case "$PAGE" in
    # the list makes rows only on the screen: the seeded route sorts above the extra ones (run 43444695400)
    gpx) echo '^T518 route$' ;;
    settings) echo '^t518-setup.*' ;;
    profiles) echo '^T518 profile.*' ;;
  esac
}

side_t528() {
  local p=$SIDE rows
  # APK: the base side of the big root (rb) takes the APK of the input base
  [ -s "${APK:-apk-head/android-debug.apk}" ] || proves_nothing "$p: no APK ${APK:-apk-head/android-debug.apk}"
  previous_install "$p" "${APK:-apk-head/android-debug.apk}"
  conf "$p" || proves_nothing "$p: the start after the reinstall did not reach home"
  [ -n "$SLOW_MS" ] && slow_on "$SLOW_MS"
  DP=$(density)
  say "density: ${DP:-unknown, 3.5 taken} px per dp"
  # PLACE: above the list (c8925db6c) - the GPX pages, the modern settings file and profile pages; under the
  # list - the classic settings file and profile pages (SettingsList.qml, profiles.qml: "under the folder list")
  if [ "$PAGE" != gpx ] && [ "$UI_MODERN" != true ]; then PLACE=below; else PLACE=above; fi
  # LAND: the page and the question in landscape; the folder picker of the system is tapped by its upright
  # places (yes_picker_allow), so upright for it and landscape again at once after Allow - the pass in landscape
  if [ "$LAND" = true ]; then
    turn_to 1 "$p: the page in landscape" || proves_nothing "$p: the screen did not turn to landscape"
  fi
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
  if [ "$LAND" = true ]; then
    # by the frame: the root of a dump with the native question of the classic look is the dialog (1403 x 1717,
    # run 43476967975), not the screen
    set -- $(screen_wh)
    if [ -n "$2" ] && [ "$1" -gt "$2" ]; then
      say "check $p-question-landscape: the page with the question in landscape ($1 x $2): OK"
    else
      fail "check $p-question-landscape: the page not in landscape (${1:-?} x ${2:-?})"
    fi
    turn_to 0 "$p: upright for the folder picker" || proves_nothing "$p: not upright for the folder picker"
    emu_sleep 3
    dump
  fi
  mark "$p: yes"
  if [ "$LAND" = true ]; then
    AFTER_ALLOW="land_watch $p-3-pass" yes_picker_allow "$p-2-picker" "$p-2-allow"
  else
    AFTER_ALLOW="progress_watch $p-3-pass" yes_picker_allow "$p-2-picker" "$p-2-allow"
  fi
  mark "$p: allowed"
  pass_log "$p"
  [ "$BIG_ROOT" = true ] && root_gap "$p"
  progress_check "$p-3-pass" "${SLOW_MS:+yes}"
  button_check "$p-3-pass"
  geom_check "$p-3-pass"
  QDUMP="dumps/$p-2-question.xml" after_check "$p-3-pass"
  toast_watch "$p-3-pass"
  emu_sleep 3
  ensure_app
  # landscape, modern GPX: the restored route sorts under the bundled ones and the shorter list has no row
  # for it on the screen (runs 43482214843, 43523520888: Box Hill … Crater Lake) - filter by its name.
  # The keyboard of a Qt field never takes the whole landscape screen (IME_FLAG_NO_EXTRACT_UI, Qt 5.15.0
  # QtEditText.java:100), the first row under the filter stays above it
  if [ "$LAND" = true ] && [ "$UI_MODERN" = true ] && [ "$PAGE" = gpx ]; then
    filter_rows "T518" '^Filter: T$' "$(row_rx)"
  fi
  still
  shot "$p-4-after"
  expect_not "$p-4-after" "$PROGRESS_RX" 'no progress node after the pass' --any
  if [ "$UI_MODERN" = true ]; then
    expect "$p-4-after" "$(row_rx)" 'the restored row in the list after the pass' --any
  else
    # the rows of the classic lists have no name in the dump (run 43444695400) - the frame by eye
    say "classic: the rows have no name in the dump - the list on the frame $p-4-after by eye"
  fi
  say "rows of the list after the pass: $(uifind "dumps/$p-4-after.xml" --count "$(row_rx)" --any 2>/dev/null) ($(row_rx))"
  expect_not "$p-4-after" '^Restore files$' 'the button gone after the grant'
  if [ "$LAND" = true ]; then
    turn_to 0 "$p: upright after the pass"
  fi
  back_to "$HOME_RX" 20
  wrap_up
}

# filter_rows <text> <taken regex> <landing regex>: the text into the Filter field of the modern GPX page
# (its name is "Filter: " and the text; the dump trims the space of the empty one), then the keyboard away
# (a back key while it is shown only closes it)
filter_rows() {
  local x y
  dump
  if ! find_ui '^Filter:$'; then
    fail "filter: no empty Filter field ($EMU_WHY)"
    return 1
  fi
  set -- "$@" $EMU_AT
  x=$4; y=$5
  say "tap Filter at $x $y"
  adb shell input tap "$x" "$y" < /dev/null > /dev/null 2>&1
  emu_sleep 1
  type_text "$1" "$2" "$3" || return 1
  # not hide_keyboard: the keyboard is expected here, not a near
  if ime_shown; then
    adb shell input keyevent 4 < /dev/null > /dev/null 2>&1
    emu_sleep 2
  fi
  ime_shown && near keyboard "filter: still shown after the back key"
  return 0
}

# land_watch <prefix>: AFTER_ALLOW of LAND - landscape again at once, then the burst
land_watch() {
  turn_to 1 "$1: landscape at once after Allow" || fail "$1: the pass not in landscape"
  progress_watch "$1"
}

# dump_size <dump>: "width height" of the screen by the root node of a dump
dump_size() {
  "$EMU_PY" - "$1" <<'PY' 2>/dev/null
import sys, xml.etree.ElementTree as ET
n = ET.parse(sys.argv[1]).getroot().find("node")
b = n.get("bounds").replace("][", ",").strip("[]").split(",")
print(b[2], b[3])
PY
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
BEFORE_REINSTALL=seed_all
SIDE=${SIDE:-h}
say "side $SIDE"
case "$SIDE" in
  h) PAGE=gpx UI_MODERN=false side_t528 ;;
  m) PAGE=gpx UI_MODERN=true LIST_TOP=490 side_t528 ;;
  hs) PAGE=gpx UI_MODERN=false SLOW_MS=800 side_t528 ;;
  # ms: also the frames of the end of the pass one after another (END_BURST - the hold and the closing)
  ms) PAGE=gpx UI_MODERN=true SLOW_MS=800 END_BURST=true END_FRAMES=30 LIST_TOP=490 MAP_TOP=1513 side_t528 ;;
  ss) PAGE=settings UI_MODERN=false SLOW_MS=800 side_t528 ;;
  sm) PAGE=settings UI_MODERN=true SLOW_MS=800 side_t528 ;;
  ps) PAGE=profiles UI_MODERN=false SLOW_MS=800 side_t528 ;;
  pm) PAGE=profiles UI_MODERN=true SLOW_MS=800 side_t528 ;;
  # landscape (T-528, the user 13.11): l - the pass in landscape, r - a turn to landscape at the 10th file and back
  hl) PAGE=gpx UI_MODERN=false SLOW_MS=800 LAND=true side_t528 ;;
  ml) PAGE=gpx UI_MODERN=true SLOW_MS=800 LAND=true LIST_TOP=490 side_t528 ;;
  hr) PAGE=gpx UI_MODERN=false SLOW_MS=800 ROT=true side_t528 ;;
  mr) PAGE=gpx UI_MODERN=true SLOW_MS=800 ROT=true side_t528 ;;
  pl) PAGE=profiles UI_MODERN=false SLOW_MS=800 LAND=true side_t528 ;;
  pr) PAGE=profiles UI_MODERN=false SLOW_MS=800 ROT=true side_t528 ;;
  # a big root of the QZ folder (T-528, the user 13.11): rb - the APK without db61038c3 (input base), ra - the head
  rb) PAGE=gpx UI_MODERN=false BIG_ROOT=true APK=apk-base/android-debug.apk side_t528 ;;
  ra) PAGE=gpx UI_MODERN=false BIG_ROOT=true GAP_MAX=2 side_t528 ;;
  *) proves_nothing "unknown side $SIDE" ;;
esac
