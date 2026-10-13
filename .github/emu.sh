#!/bin/bash
# Test only: start an already built APK on the emulator with log_debug on, so the Qt
# warnings (QML errors among them) reach logcat, then keep logcat and screenshots.
#
# UI_MODERN (workflow input "modern"): false runs the classic look. The steps find a control
# by its text or accessible name in a uiautomator dump (tap_ui, .github/uitap.py) and use
# fixed coordinates only when the dump has no such control. steps.log says which way every
# tap went; dumps/<shot>.xml is the control tree behind every shot.
#
# T-195: training programs of a previous install. On Android 14+ the work folder of QZ is
# Documents/QZ, and a file another owner left there (a previous install) is foreign to the
# app: missing from the folder list, exists() by its name, cannot be opened or removed. Here
# the shell plays the previous install: it puts two .zwo files into Documents/QZ/training
# before the APK is installed. The list of training programs must ask whether to look for
# them, open the folder picker on Yes, copy them back as the app's own and say how many.
PKG=org.cagnulen.qdomyoszwift
UI_MODERN=${UI_MODERN:-false}
# LOG_DEBUG (workflow input "log_debug"): false runs with the debug log off. QML errors do
# not reach logcat then.
LOG_DEBUG=${LOG_DEBUG:-true}
STEPLOG=steps.log
: > $STEPLOG
mkdir -p dumps
TRAIN=/sdcard/Documents/QZ/training
TABATA="Tabata with sweet spot.zwo"     # a bundled program (:/zwo/), the app looks for it
CUSTOM="T195 custom.zwo"                # a program the user imported once
# The lines of the fix in logcat (Java Log.d and qDebug with log_debug on)
T195_RX="training folder: file of a previous install|handleTrainingFolderResult|training programs restored|deleteTreeDocument|restoreTrainingFiles|openTrainingFolderPicker|takePersistableUriPermission|importContentToAppDir|trainingProgramsPageOpened|Training programs restored"

# list_training <when>: the folder as the shell sees it and as the app sees it (run-as runs
# with the uid of the app, so the storage rules of the app apply)
list_training() {
  echo "== training folder, $1 (shell)" >> $STEPLOG
  adb shell "ls -la '$TRAIN/' 2>&1" >> $STEPLOG || true
  echo "== training folder, $1 (app uid)" >> $STEPLOG
  adb shell "run-as $PKG ls -la '$TRAIN/' 2>&1" >> $STEPLOG || true
  adb shell "run-as $PKG sh -c \"head -c 60 '$TRAIN/$TABATA'; echo; head -c 60 '$TRAIN/$CUSTOM'; echo\" 2>&1" \
    >> $STEPLOG || true
}

# --- the "previous install": the user's case, install, start, uninstall ---
# The shell may not create .zwo files in Documents on API 35 (run 38485502334: "cp: Operation
# not permitted"), so the previous install itself leaves them: on its first start QZ copies the
# bundled programs into Documents/QZ/training, and after the uninstall they stay there,
# owned by an app that no longer exists
adb install apk-debug/android-debug.apk
# started like the main start below; run 38486301638 waited 30 s after "monkey" and found no
# training folder at all, so wait for the bundled program itself, up to 120 s
adb shell am start -n $PKG/.CustomQtActivity >> $STEPLOG 2>&1 || true
for i in $(seq 1 40); do
  if adb shell "ls '$TRAIN/'" 2>/dev/null | tr -d '\r' | grep -qF "$TABATA"; then
    echo "previous install: bundled programs in place after $((i * 3)) s" >> $STEPLOG
    break
  fi
  sleep 3
done
sleep 3
adb shell am force-stop $PKG || true
echo "== training folder, previous install (shell)" >> $STEPLOG
adb shell "ls -la '$TRAIN/' 2>&1" >> $STEPLOG || true
adb uninstall $PKG || true
echo "== training folder, after the uninstall (shell)" >> $STEPLOG
adb shell "ls -la '$TRAIN/' 2>&1" >> $STEPLOG || true
if adb shell "ls '$TRAIN/'" | tr -d '\r' | grep -qF "$TABATA"; then
  echo "foreign file in place: $TABATA" >> $STEPLOG
else
  echo "!! foreign file NOT in place: $TABATA" >> $STEPLOG
fi

adb install apk-debug/android-debug.apk
for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION BLUETOOTH_ADVERTISE BLUETOOTH_CONNECT BLUETOOTH_SCAN POST_NOTIFICATIONS; do
  adb shell pm grant $PKG android.permission.$p || true
done
# No MANAGE_EXTERNAL_STORAGE here (other runs allow it): with "all files access" the app reads
# the foreign files and the case of a reinstall is gone
echo "appops MANAGE_EXTERNAL_STORAGE: $(adb shell appops get $PKG MANAGE_EXTERNAL_STORAGE 2>&1 | tr -d '\r')" >> $STEPLOG
adb shell cmd uimode night no || true
# The launcher of the emulator image hangs on the slow CI machine: no error dialogs at all
# for the run; an ANR still reaches logcat and the end of steps.log ("ANR in")
adb shell settings put global hide_error_dialogs 1 || true

# The control tree of the screen into ui.xml (empty when uiautomator gives up, for instance
# while something animates without pause)
dump() {
  rm -f ui.xml
  timeout 25 adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1 || true
  adb pull /sdcard/ui.xml ui.xml > /dev/null 2>&1 || true
}
# The emulator itself may put a window over the app: "Pixel Launcher isn't responding", or
# the Health Connect screen. Clear them before every step: Wait on a "not responding" dialog,
# the back key on anything else that is not the app. Logged in steps.log.
# FOREIGN_OK=1: a window of another app is expected (the folder picker of DocumentsUI) and
# stays; only the dump is taken.
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
    # Somebody else hanging (the launcher) is closed, the app itself is waited for
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
  # The last dump showed the window that was then closed: not the screen any more
  rm -f ui.xml
}
# ensure_app leaves ui.xml of the screen on top: the callers take it instead of a second dump
shot() {
  ensure_app
  echo "-- shot $1" >> $STEPLOG
  adb shell screencap -p /sdcard/$1.png || true
  adb pull /sdcard/$1.png || true
  [ -f ui.xml ] || dump
  [ -f ui.xml ] && cp ui.xml dumps/$1.xml
}
# tap_ui 'regex' [x y]: the control whose whole text or accessible name matches, else the
# fallback coordinates; without them the step is skipped (return 1)
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
# tap_wait 'regex' <tries>: tap_ui without fallback, looking again every 3 s (a native dialog
# or the picker may take a moment to show)
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
# The same for a drawer entry that may be below the fold: one swipe up and a second look
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
# Toolbar buttons are icons without text (Nexus 6: 1440x2560 px, 3.5 px per dp)
MENU="84 168"          # menu on the home page, back arrow elsewhere
open_menu() { tap $MENU "menu"; sleep 3; adb shell input swipe 500 700 500 2300 300 || true; sleep 2; }

# put_conf <extra lines>: the settings file of the app before a start
put_conf() {
  printf '[General]\nlog_debug=%s\nui_modern=%s\n%b' "$LOG_DEBUG" "$UI_MODERN" "$1" > qz.conf
  adb push qz.conf /data/local/tmp/qz.conf
  adb shell "run-as $PKG mkdir -p 'files/.config/Roberto Viola'"
  adb shell "run-as $PKG cp /data/local/tmp/qz.conf 'files/.config/Roberto Viola/qDomyos-Zwift.conf'"
}

adb logcat -c || true
adb logcat > full_logcat.txt 2>/dev/null &
LOGCAT_PID=$!

# start_app: launch and close the Health Connect screen the first start may show
start_app() {
  adb shell am start -n $PKG/$PKG.CustomQtActivity
  sleep 20
  dump
  if [ -f ui.xml ] && [ "$(python3 .github/uitap.py ui.xml --package)" != "$PKG" ]; then
    back "health connect"
  fi
  sleep 15
}
# question <shot>: is the question of the restore on the screen? A native dialog has its text
# in the dump; a QML one does not, then only the shot tells
question() {
  if [ -f dumps/$1.xml ] && grep -q "Training Programs\|previous installation" dumps/$1.xml; then
    echo "question on $1: YES (in the dump)" >> $STEPLOG
  else
    echo "question on $1: not in the dump (see $1.png)" >> $STEPLOG
  fi
}
# open_list <shot>: from home the menu and Open Train Program, then a shot
open_list() {
  open_menu
  tap_drawer '^Open Train Program$' || echo "!! Open Train Program not found in the drawer" >> $STEPLOG
  sleep 8
  shot $1
  question $1
}
mark() { echo "== $1" >> $STEPLOG; adb shell log -t T195 "mark $1" || true; }

# The wizard of the first start stays closed with a last device name (homeform::firstRun())
put_conf "bluetooth_lastdevice_name=T195\n"
mark "first start"
start_app
shot 01-home
list_training "after the first start"

# 1. The list: the question "Training Programs" with Yes and No
mark "open the list"
open_list 02-question

# 2. Yes: the folder picker of the system, started on Documents/QZ
mark "yes"
tap_wait '^&?Yes$' 4 || echo "!! no Yes button in the dump: the dialog may be a QML one" >> $STEPLOG
sleep 6
FOREIGN_OK=1
shot 03-picker
tap_wait '^Use this folder$' 5
sleep 4
shot 04-allow
tap_wait '^Allow$' 4
FOREIGN_OK=
mark "allowed"

# 3. The restore runs in the background: the toast and the list
sleep 2
shot 05-after-2s
sleep 3
shot 06-after-5s
sleep 8
shot 07-after-13s
list_training "after the restore"

# 4. Leave the list and open it again: no question any more (one attempt per run, and the
# files are the app's own now)
mark "reopen"
back "list"
sleep 4
shot 08-home
open_list 09-reopen

# 5. A new start of the app: the list without the question, the restored programs in it
mark "restart"
back "list"
sleep 3
adb shell am force-stop $PKG || true
sleep 3
start_app
open_list 10-restart-list
list_training "after the restart"
# The restored Tabata: its preview (the name in the file says "previous install")
tap_ui '^Tabata with sweet spot(\.zwo)?$' && { sleep 6; shot 11-tabata-preview; }

adb shell "ps -A 2>/dev/null || ps" > process_list.txt || true
shot screenshot
kill $LOGCAT_PID 2>/dev/null || true
wait $LOGCAT_PID 2>/dev/null || true
# If the recording broke off (adb restarted), the dump of the end is better than nothing
adb logcat -d > end_logcat.txt || true
if [ "$(wc -l < full_logcat.txt)" -lt "$(wc -l < end_logcat.txt)" ]; then
  echo "!! logcat recording shorter than the dump at the end: the dump is kept" >> $STEPLOG
  mv end_logcat.txt full_logcat.txt
else
  rm -f end_logcat.txt
fi
# The lines of the fix, with the marks of the steps between them
grep -E "T195|$T195_RX" full_logcat.txt > t195_logcat.txt || true
echo "== logcat of the fix" >> $STEPLOG
cat t195_logcat.txt >> $STEPLOG
# The debug logs the app wrote itself (Documents/QZ on Android 14+)
mkdir -p qz-logs
adb shell 'ls -la /sdcard/Documents/QZ/ 2>&1' > qz-logs/listing.txt || true
for f in $(adb shell 'ls /sdcard/Documents/QZ/ 2>/dev/null' | tr -d '\r' | grep '^debug-.*[.]log$'); do
  adb pull "/sdcard/Documents/QZ/$f" "qz-logs/$f" > /dev/null 2>&1 || true
done
# The dialogs are hidden (hide_error_dialogs above), so hangs are only here
grep -E "ANR in" full_logcat.txt | sed 's/^/!! /' >> $STEPLOG || true
echo "== app debug logs"; cat qz-logs/listing.txt; ls -la qz-logs
echo "== steps"; cat $STEPLOG
echo "== ANR"; grep -E "ANR in" full_logcat.txt || true
grep -iE "qrc:|\.qml|warning|critical|fatal" full_logcat.txt | tail -n 80 || true
