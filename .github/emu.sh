#!/bin/bash
# Test only (T-182): the folder import of the history after a reinstall, timed. The same steps
# run on two APKs (matrix of the workflow): the build of plain master and the build of the fix.
#
# On Android 14+ the work folder of QZ is Documents/QZ, and the files a previous install left
# there are foreign to the app: missing from the folder list, exists() by name, unreadable
# without a folder grant. After every reinstall the folder import copies each workout once
# more, so Documents/QZ/fit of a phone held 14 copies of each of 16 workouts (logs of 08.10).
# Here the first install plays the previous ones: run-as (uid of the app) puts 16 synthetic
# workouts x 14 copies (workout-NN.fit, workout-NN_1.fit ... _13.fit) into Documents/QZ/fit,
# then the app is uninstalled and installed again. One more workout copy is put as a file of
# the new install (own-00.fit, the bytes of workout-00) after its start. The history page asks
# about the previous install, Yes opens the folder picker, Use this folder and Allow start
# the import. Measured: seconds from Allow to the end of the Java part (handleFitFolderResult
# in logcat) and to the end of the C++ part (FitDatabaseProcessor import: added ...), the
# files in the folder after it (own and all), the counts of the import.
PKG=org.cagnulen.qdomyoszwift
UI_MODERN=${UI_MODERN:-false}
LOG_DEBUG=${LOG_DEBUG:-true}
STEPLOG=steps.log
: > $STEPLOG
mkdir -p dumps
FIT=/sdcard/Documents/QZ/fit
WORKOUTS=16
COPIES=14
T182_RX="handleFitFolderResult|FolderImport|importContentToAppDirKeepExisting|FitDatabaseProcessor import|openFitFolderPicker|takePersistableUriPermission|deleteOldHistoryDatabase|importFitFilesFromTree"

install_app() {
  adb install apk-debug/android-debug.apk
  adb shell pm path $PKG > /dev/null 2>&1 || echo "!! APK NOT INSTALLED - the run proves nothing" >> $STEPLOG
  for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION BLUETOOTH_ADVERTISE BLUETOOTH_CONNECT BLUETOOTH_SCAN POST_NOTIFICATIONS; do
    adb shell pm grant $PKG android.permission.$p || true
  done
}
# count_fit <when>: files in Documents/QZ/fit as the shell sees them (all) and as the app does
count_fit() {
  local all own
  all=$(adb shell "ls '$FIT/' 2>/dev/null < /dev/null | wc -l" | tr -d '\r ')
  own=$(adb shell "run-as $PKG sh -c \"ls '$FIT/' 2>/dev/null | wc -l\" < /dev/null" | tr -d '\r ')
  echo "fit folder, $1: all $all, seen by the app $own" >> $STEPLOG
  FIT_ALL=$all
  FIT_OWN=$own
}

install_app
echo "appops MANAGE_EXTERNAL_STORAGE: $(adb shell appops get $PKG MANAGE_EXTERNAL_STORAGE 2>&1 | tr -d '\r')" >> $STEPLOG
adb shell cmd uimode night no || true
adb shell settings put global hide_error_dialogs 1 || true

dump() {
  rm -f ui.xml
  adb shell rm -f /sdcard/ui.xml > /dev/null 2>&1 || true
  timeout 25 adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1 || true
  adb pull /sdcard/ui.xml ui.xml > /dev/null 2>&1 || true
}
FOREIGN_OK=
ensure_app() {
  local i pkg xy
  if [ -n "$FOREIGN_OK" ]; then
    dump
    [ -f ui.xml ] && echo "   window on top: $(python3 .github/uitap.py ui.xml --package)" >> $STEPLOG
    return 0
  fi
  for i in 1 2 3; do
    dump
    [ -f ui.xml ] || return 0
    pkg=$(python3 .github/uitap.py ui.xml --package)
    [ -z "$pkg" ] || [ "$pkg" = "$PKG" ] && return 0
    if grep -q "t responding" ui.xml && ! grep -q "QZ\|qdomyos" ui.xml &&
       xy=$(python3 .github/uitap.py ui.xml 'Close app'); then
      echo "!! $pkg: another app not responding, Close app at $xy" >> $STEPLOG
      adb shell input tap $xy || true
    elif grep -q "t responding" ui.xml && xy=$(python3 .github/uitap.py ui.xml 'Wait'); then
      echo "!! $pkg not responding: Wait at $xy" >> $STEPLOG
      adb shell input tap $xy || true
    else
      echo "!! $pkg over the app: back key" >> $STEPLOG
      adb shell input keyevent KEYCODE_BACK || true
    fi
    sleep 3
  done
  rm -f ui.xml
}
shot() {
  ensure_app
  echo "-- shot $1" >> $STEPLOG
  adb shell screencap -p /sdcard/$1.png || true
  adb pull /sdcard/$1.png || true
  [ -f ui.xml ] || dump
  [ -f ui.xml ] && cp ui.xml dumps/$1.xml
}
tap_ui() {
  local rx="$1" fx="$2" fy="$3" xy=""
  ensure_app
  [ -f ui.xml ] || dump
  [ -f ui.xml ] && xy=$(python3 .github/uitap.py ui.xml "$rx")
  if [ -n "$xy" ]; then
    echo "tap '$rx': by label at $xy" >> $STEPLOG
    adb shell input tap $xy || true
  elif [ -n "$fx" ]; then
    echo "tap '$rx': NOT FOUND, coordinates $fx $fy" >> $STEPLOG
    adb shell input tap $fx $fy || true
  else
    echo "tap '$rx': NOT FOUND, skipped" >> $STEPLOG
    return 1
  fi
}
tap_wait() {
  local i
  for i in $(seq 1 "$2"); do
    rm -f ui.xml
    ensure_app
    if [ -f ui.xml ] && python3 .github/uitap.py ui.xml "$1" > /dev/null; then
      tap_ui "$1"
      return 0
    fi
    sleep 3
  done
  echo "tap '$1': NOT FOUND after $2 looks, skipped" >> $STEPLOG
  return 1
}
tap_drawer() {
  local rx="$1" xy=""
  dump
  [ -f ui.xml ] && xy=$(python3 .github/uitap.py ui.xml "$rx")
  if [ -z "$xy" ]; then
    adb shell input swipe 500 2200 500 900 400 || true
    sleep 2
  fi
  tap_ui "$@"
}
tap() { ensure_app; echo "tap $1 $2 ($3)" >> $STEPLOG; adb shell input tap $1 $2 || true; }
back() { echo "back ($1)" >> $STEPLOG; adb shell input keyevent KEYCODE_BACK || true; }
MENU="84 168"
open_menu() { tap $MENU "menu"; sleep 3; adb shell input swipe 500 700 500 2300 300 || true; sleep 2; }

put_conf() {
  printf '[General]\nlog_debug=%s\nui_modern=%s\n%b' "$LOG_DEBUG" "$UI_MODERN" "$1" > qz.conf
  adb push qz.conf /data/local/tmp/qz.conf
  adb shell "run-as $PKG mkdir -p 'files/.config/Roberto Viola'"
  adb shell "run-as $PKG cp /data/local/tmp/qz.conf 'files/.config/Roberto Viola/qDomyos-Zwift.conf'"
}

# epoch times in logcat: the seconds between two lines are read from it
adb logcat -c || true
adb logcat -v epoch > full_logcat.txt 2>/dev/null &
LOGCAT_PID=$!

start_app() {
  adb shell am start -n $PKG/$PKG.CustomQtActivity
  sleep 20
  dump
  if [ -f ui.xml ] && [ "$(python3 .github/uitap.py ui.xml --package)" != "$PKG" ]; then
    back "health connect"
  fi
  sleep 15
}
mark() { echo "== $1" >> $STEPLOG; adb shell log -t T182 "mark $1" || true; }

# The synthetic workouts (no data of a real person), all of one size with different content
python3 .github/make_fit.py fits $WORKOUTS 60
ls -la fits >> $STEPLOG
adb shell "rm -rf /data/local/tmp/t182; mkdir -p /data/local/tmp/t182"
adb push fits/. /data/local/tmp/t182/
adb shell "chmod 644 /data/local/tmp/t182/*"

put_conf "bluetooth_lastdevice_name=T182\n"
mark "first start"
start_app
shot 01-home
echo "== Documents/QZ after the first start" >> $STEPLOG
adb shell "ls -la /sdcard/Documents/QZ/ 2>&1" >> $STEPLOG || true

# The copies of the previous installs, written as the app
mark "copies of previous installs"
adb shell "run-as $PKG sh -c 'mkdir -p $FIT; for f in /data/local/tmp/t182/*.fit; do b=\$(basename \$f .fit); cp \$f $FIT/\$b.fit; n=1; while [ \$n -lt $COPIES ]; do cp \$f $FIT/\${b}_\$n.fit; n=\$((n+1)); done; done' < /dev/null" 2>&1 | tail -n 5 >> $STEPLOG
count_fit "with the copies"
[ "$FIT_OWN" = "$((WORKOUTS * COPIES))" ] || echo "!! the copies were not written ($FIT_OWN of $((WORKOUTS * COPIES))) - the run proves nothing" >> $STEPLOG

mark "reinstall"
adb shell am force-stop $PKG || true
adb uninstall $PKG || true
install_app
put_conf "bluetooth_lastdevice_name=T182\n"
start_app
shot 02-home-reinstalled
count_fit "after the reinstall"
[ "$FIT_ALL" = "$((WORKOUTS * COPIES))" ] || echo "!! the copies are not in place after the reinstall ($FIT_ALL) - the run proves nothing" >> $STEPLOG
# a file of this install, the same bytes as workout-00: the import must take it, not copy again
adb shell "run-as $PKG cp /data/local/tmp/t182/workout-00.fit $FIT/own-00.fit < /dev/null" >> $STEPLOG 2>&1 || true
count_fit "with own-00.fit"

mark "history"
open_menu
tap_drawer '^Workouts History$' || echo "!! Workouts History not found in the drawer" >> $STEPLOG
sleep 8
shot 03-question
mark "yes"
tap_wait '^&?Yes$' 6 || echo "!! no Yes in the dump - the question did not come; the run proves nothing" >> $STEPLOG
sleep 6
FOREIGN_OK=1
shot 04-picker
if ! tap_wait '^Use this folder$' 5; then
  echo "tap USE THIS FOLDER at 720 2391 (03-picker.png of run 38488133337, T-195)" >> $STEPLOG
  adb shell input tap 720 2391 || true
fi
sleep 4
shot 05-allow
tap_wait '^Allow$' 4
FOREIGN_OK=
mark "allowed"
ALLOWED=$(date +%s.%N)

# The end of the import: Java first, then the C++ part; up to 10 min
JAVA_END=
CPP_END=
for i in $(seq 1 600); do
  if [ -z "$JAVA_END" ] && grep -q "handleFitFolderResult requestCode" full_logcat.txt; then
    JAVA_END=$(date +%s.%N)
  fi
  if grep -q "FitDatabaseProcessor import: added" full_logcat.txt; then
    CPP_END=$(date +%s.%N)
    break
  fi
  sleep 1
done
echo "import: Java part $(python3 -c "print(round(${JAVA_END:-0} - $ALLOWED, 1))") s, whole $(python3 -c "print(round(${CPP_END:-0} - $ALLOWED, 1))") s after Allow (host clock, 1 s steps)" >> $STEPLOG
[ -n "$CPP_END" ] || echo "!! the import did not end in 10 min - the run proves nothing" >> $STEPLOG
sleep 3
shot 06-after-import
count_fit "after the import"
# expected: one own copy of each workout (own-00.fit and 15 new), nothing else left over
echo "expected: all $((WORKOUTS * COPIES + WORKOUTS)), seen by the app $WORKOUTS" >> $STEPLOG
echo "== own files after the import" >> $STEPLOG
adb shell "run-as $PKG sh -c \"cd '$FIT' && ls -la && md5sum * | sort\" < /dev/null" >> $STEPLOG 2>&1 || true

# The times from logcat itself (epoch column): the mark, the Java end, the C++ end
python3 - full_logcat.txt >> $STEPLOG <<'EOF'
import sys
marks = {}
for line in open(sys.argv[1], errors="replace"):
    parts = line.split(None, 1)
    if not parts:
        continue
    try:
        t = float(parts[0])
    except ValueError:
        continue
    for key, text in (("allowed", "mark allowed"), ("java", "handleFitFolderResult requestCode"),
                      ("cpp", "FitDatabaseProcessor import: added")):
        if key not in marks and text in line:
            marks[key] = t
if "allowed" in marks:
    for key in ("java", "cpp"):
        if key in marks:
            print("logcat: %s end %.2f s after Allow" % (key, marks[key] - marks["allowed"]))
EOF

adb shell "ps -A 2>/dev/null || ps" > process_list.txt || true
shot screenshot
kill $LOGCAT_PID 2>/dev/null || true
wait $LOGCAT_PID 2>/dev/null || true
adb logcat -d -v epoch > end_logcat.txt || true
if [ "$(wc -l < full_logcat.txt)" -lt "$(wc -l < end_logcat.txt)" ]; then
  echo "!! logcat recording shorter than the dump at the end: the dump is kept" >> $STEPLOG
  mv end_logcat.txt full_logcat.txt
else
  rm -f end_logcat.txt
fi
grep -E "T182|$T182_RX" full_logcat.txt > t182_logcat.txt || true
echo "== logcat of the import" >> $STEPLOG
grep -vE "FolderImport could not read|importContentToAppDirKeepExisting" t182_logcat.txt | tail -n 40 >> $STEPLOG
echo "lines 'could not read': $(grep -c 'FolderImport could not read' t182_logcat.txt)" >> $STEPLOG
mkdir -p qz-logs
adb shell 'ls -la /sdcard/Documents/QZ/ 2>&1' > qz-logs/listing.txt || true
for f in $(adb shell 'ls /sdcard/Documents/QZ/ 2>/dev/null' | tr -d '\r' | grep '^debug-.*[.]log$'); do
  adb pull "/sdcard/Documents/QZ/$f" "qz-logs/$f" > /dev/null 2>&1 || true
done
grep -E "ANR in" full_logcat.txt | sed 's/^/!! /' >> $STEPLOG || true
echo "== steps"; cat $STEPLOG
grep -iE "qrc:|\.qml" full_logcat.txt | tail -n 40 || true
# A "proves nothing" line (no APK, no copies, no question, no end of the import) fails the job
if grep -q "proves nothing" $STEPLOG; then echo "!! steps.log: the run proves nothing - failing the job"; exit 1; fi
