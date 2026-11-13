#!/bin/bash
# Test only (T-537): the scroll bar of the training program list, before (base: feat/modern-ui) and after
# (head: + T-537), classic and modern look. A frame at rest and a frame while a finger drags the list (the
# bar shows only while it moves); the bar width is measured from the frames after the run.
. .github/lib.sh
. .github/qz.sh

QZDIR=/sdcard/Documents/QZ

# app_uid: the uid of the installed app - the owner of its data folder; empty without the app (T-514)
app_uid() {
  adb shell "su 0 stat -c %u /data/data/$PKG" < /dev/null 2>/dev/null | tr -d '\r'
}

# wipe_files: Documents/QZ of the previous side removed by the app uid while it is installed - files of an
# uninstalled app belong to another uid and bring the "previous installation" box (T-514, run 43015224696)
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

# programs: 30 small programs of its own, so the list scrolls in both looks whatever the app brings
programs() {
  local uid i
  uid=$(app_uid)
  for i in $(seq -w 1 30); do
    printf '<workout_file>\n<author>QZ emu</author>\n<name>Emu %s</name>\n<description>Program %s</description>\n<sportType>bike</sportType>\n<workout>\n<SteadyState Duration="300" Power="0.6"/>\n</workout>\n</workout_file>\n' "$i" "$i" > "Emu$i.zwo"
    adb push "Emu$i.zwo" "/data/local/tmp/Emu$i.zwo" < /dev/null > /dev/null 2>&1
  done
  adb shell "su $uid,$uid,9997 sh -c 'cp /data/local/tmp/Emu*.zwo $QZDIR/training/'" < /dev/null >> "$STEPLOG" 2>&1
  i=$(adb shell "ls $QZDIR/training" < /dev/null 2>/dev/null | grep -c '^Emu')
  say "programs pushed: $i"
  [ "$i" -ge 30 ] || proves_nothing "programs: $i of 30 in the training folder"
}

# bar <case> <modern>: the list at rest, then while a finger drags it slowly (2.5 s), a frame at ~1.2 s
bar() {
  local c=$1 modern=$2
  start_case "$c" ui_modern=$modern fakedevice_treadmill=true android_documents_folder=true || return 1
  open_drawer '^Open Train Program$' && tap_ui '^Open Train Program$' '^Other folders$' || return 1
  emu_sleep 4
  shot "$c-1-rest"
  say "drag the list up slowly"
  adb shell input swipe 700 2300 700 1100 2500 < /dev/null > /dev/null 2>&1 &
  sleep 1.2
  adb exec-out screencap -p < /dev/null > "$c-2-moving.png" 2>/dev/null
  [ -s "$c-2-moving.png" ] || fail "$c: no frame while moving"
  wait
  sleep 0.3
  adb exec-out screencap -p < /dev/null > "$c-3-after.png" 2>/dev/null
  emu_sleep 3
  shot "$c-4-stopped"
  find_ui '^Other folders$' || fail "$c: the list page left during the drag"
  back_to "$HOME_RX" 20
}

# qml_quiet: no QML warning of the changed files from the head processes (pid lines of start_case)
qml_quiet() {
  local pid n=0 found
  logcat_stop
  for pid in $(grep -a '^pid h' "$STEPLOG" | cut -d' ' -f3); do
    n=$(( n + 1 ))
    found=$(awk -v p="$pid" '$3 == p' full_logcat.txt | grep -a 'TrainingProgramsList\(JS\)\?.qml:' | head -5)
    if [ -n "$found" ]; then
      echo "$found" >> "$STEPLOG"
      fail "check qml: pid $pid: QML warnings of TrainingProgramsList*.qml"
    fi
  done
  if [ "$n" = 0 ]; then
    fail "check qml: no head pid in steps.log - QML warnings not checked"
  elif [ ! -s full_logcat.txt ]; then
    fail "check qml: full_logcat.txt is empty"
  else
    grep -q '^!! check qml' "$STEPLOG" || say "check qml: no TrainingProgramsList*.qml warning from $n head processes: OK"
  fi
}

emu_init
logcat_start

for side in b h; do
  if [ "$side" = b ]; then apk=apk-base/android-debug.apk; else apk=apk-head/android-debug.apk; fi
  say "== $side: start"
  wipe_files
  install_apk "$apk"
  start_case "${side}0" ui_modern=false fakedevice_treadmill=true android_documents_folder=true
  programs
  bar "${side}c" false
  bar "${side}m" true
done

qml_quiet
finish
