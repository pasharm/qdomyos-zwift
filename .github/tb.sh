#!/bin/bash
# Test only (T-324): Reset in the list of changed settings with the real TalkBack, classic look.
# The setup and helpers are those of emu.sh; the steps t1-t4 are described below at "TalkBack".
PKG=org.cagnulen.qdomyoszwift
UI_MODERN=${UI_MODERN:-false}
LOG_DEBUG=${LOG_DEBUG:-true}
STEPLOG=steps.log
CONF='files/.config/Roberto Viola/qDomyos-Zwift.conf'
RESTART='Settings changed'
: > $STEPLOG
mkdir -p dumps
FAILED=0

# install_apk <apk>: a fresh install with the permissions granted
install_apk() {
  adb uninstall $PKG > /dev/null 2>&1 || true
  adb shell rm -rf /sdcard/Documents/QZ || true
  adb install "$1"
  adb shell pm path $PKG > /dev/null || { echo "!! $1 not installed" >> $STEPLOG; exit 1; }
  for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION BLUETOOTH_ADVERTISE BLUETOOTH_CONNECT BLUETOOTH_SCAN POST_NOTIFICATIONS; do
    adb shell pm grant $PKG android.permission.$p || true
  done
  adb shell appops set $PKG MANAGE_EXTERNAL_STORAGE allow || true
  for p in EXERCISE DISTANCE TOTAL_CALORIES_BURNED HEART_RATE POWER SPEED CYCLING_PEDALING_CADENCE ELEVATION_GAINED STEPS STEPS_CADENCE HEART_RATE_VARIABILITY; do
    adb shell pm grant $PKG android.permission.health.WRITE_$p || true
  done
  echo "== installed $1" >> $STEPLOG
}
adb shell cmd uimode night no || true
adb shell settings put global hide_error_dialogs 1 || true

# A fake treadmill, so there is no first-run wizard. Changed from the default: Debug Log and Fake
# Treadmill (restartRequired), Garmin ANT+, Player Weight, FTP value (no restart)
put_conf() {
  printf '[General]\nlog_debug=%s\nui_modern=%s\nfakedevice_treadmill=true\nant_garmin=true\nweight=90\nftp=250\nvirtual_device_bluetooth=false\n' "$LOG_DEBUG" "$UI_MODERN" > qz.conf
  adb push qz.conf /data/local/tmp/qz.conf
  adb shell "run-as $PKG mkdir -p 'files/.config/Roberto Viola'"
  adb shell "run-as $PKG cp /data/local/tmp/qz.conf '$CONF'"
  adb shell "run-as $PKG ls -l '$CONF'" >> $STEPLOG 2>&1 || { echo "!! qz.conf not written" >> $STEPLOG; exit 1; }
}
dump() {
  rm -f ui.xml
  timeout 25 adb shell uiautomator dump /sdcard/ui.xml < /dev/null > /dev/null 2>&1 || true
  adb pull /sdcard/ui.xml ui.xml > /dev/null 2>&1 || true
}
# A window of another app over QZ: "isn't responding" answered by its buttons, else the back key
ensure_app() {
  local i pkg xy
  for i in 1 2 3 4 5; do
    dump
    [ -f ui.xml ] || return 0
    pkg=$(python3 .github/uitap.py ui.xml --package)
    [ -z "$pkg" ] || [ "$pkg" = "$PKG" ] && return 0
    if grep -q "t responding" ui.xml && xy=$(python3 .github/uitap.py ui.xml 'Close app'); then
      echo "!! $pkg not responding: Close app at $xy" >> $STEPLOG
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
  echo "-- shot $1" >> $STEPLOG
  adb shell screencap -p /sdcard/$1.png || true
  adb pull /sdcard/$1.png || true
  dump
  [ -f ui.xml ] && cp ui.xml dumps/$1.xml
}
tap() { ensure_app; echo "tap $1 $2 ($3)" >> $STEPLOG; adb shell input tap $1 $2 || true; }
# wait_ui 'regex' <seconds>: 0 once a control with that whole text or name shows
wait_ui() {
  local i
  for i in $(seq 1 $(( ${2:-30} / 3 ))); do
    dump
    [ -f ui.xml ] && python3 .github/uitap.py ui.xml "$1" > /dev/null && return 0
    sleep 2
  done
  return 1
}
# tap_ui 'regex': waits for the control up to 30 s, then taps it
tap_ui() {
  local xy=""
  ensure_app
  if wait_ui "$1" 30; then
    xy=$(python3 .github/uitap.py ui.xml "$1")
    echo "tap '$1': at $xy" >> $STEPLOG
    adb shell input tap $xy || true
    return 0
  fi
  echo "!! tap '$1': NOT FOUND" >> $STEPLOG
  return 1
}
check() {   # check <name> <regex> <seconds>
  if wait_ui "$2" ${3:-15}; then
    echo "check $1: OK" >> $STEPLOG
  else
    echo "!! check $1: '$2' not shown" >> $STEPLOG
    FAILED=1
  fi
}
check_none() {   # check_none <name> <regex>
  dump
  if [ -f ui.xml ] && python3 .github/uitap.py ui.xml "$2" > /dev/null; then
    echo "!! check $1: '$2' still shown" >> $STEPLOG
    FAILED=1
  else
    echo "check $1: OK" >> $STEPLOG
  fi
}
# in_tree <name> <literal>: in the last dump, on the screen or scrolled away
in_tree() {
  if [ -f ui.xml ] && grep -q -F "$2" ui.xml; then
    echo "check $1: OK" >> $STEPLOG
  else
    echo "!! check $1: '$2' not in the tree" >> $STEPLOG
    FAILED=1
  fi
}
# Frames back to back right after a tap: a toast is gone before a few dumps are taken
frames() {
  local i
  for i in 1 2 3; do
    adb exec-out screencap -p > $1-$i.png || true
  done
  echo "-- frames $1-1..3" >> $STEPLOG
}
# type_search <first letter> <rest>: the first letter until the field has it (the first keys can
# be lost), then the rest, then the keyboard down
type_search() {
  local i
  for i in 1 2 3; do
    tap 470 338 "search field"
    sleep 1
    adb shell input text "$1" || true
    sleep 2
    wait_ui '^Search results.*|^No settings found$|^Changed settings.*' 6 && break
  done
  adb shell input text "$2" || true
  sleep 4
  adb shell input keyevent KEYCODE_BACK || true   # the keyboard down
  sleep 2
}
# Toolbar buttons are icons without text (Nexus 6: 1440x2560)
BACK_XY="84 168"

# open_changed: from the home page, the settings and their "Changed" list
open_changed() {
  local i
  # The menu button has no label: tapped again until the menu shows Settings (right after the
  # start the first tap can be lost, run 42475242602)
  for i in 1 2 3 4 5; do
    tap $BACK_XY "menu"
    sleep 3
    adb shell input swipe 500 700 500 2300 300 || true
    sleep 2
    wait_ui '^Settings$' 6 && break
    echo "menu $i: no Settings yet" >> $STEPLOG
  done
  tap_ui '^Settings$' || FAILED=1
  wait_ui '^General Options$' 60 || { echo "!! settings not opened" >> $STEPLOG; FAILED=1; }
  # The search bar: the toolbar button is named "Search settings" too, the bar is open when
  # "Changed" shows
  if ! wait_ui '^Changed$' 3; then
    tap_ui '🔍|Search settings'
    sleep 2
  fi
  tap_ui '^Changed$' || FAILED=1
  check "$1: Changed list" '^Changed settings.*|^No changed settings$' 20
}
# back_home <name> <yes|no>: back from the settings; the restart question shown or not
back_home() {
  tap $BACK_XY "back"
  sleep 3
  if [ "$2" = yes ]; then
    check "$1: restart asked" "^$RESTART\$" 15
    shot $1-restart
    tap_ui '^No$' || FAILED=1
    sleep 2
  else
    sleep 3
    shot $1-home
    check_none "$1: no restart asked" "^$RESTART\$"
  fi
  check "$1: home page" '^Start$|^Stop$' 30
}

adb logcat -c || true
adb logcat -v threadtime -b main,system,crash > full_logcat.txt 2>/dev/null &
LOGCAT_PID=$!
adb shell settings put system accelerometer_rotation 0 || true
adb shell settings put system user_rotation 0 || true

echo "== API $(adb shell getprop ro.build.version.sdk | tr -d '\r')" >> $STEPLOG
install_apk apk-debug/android-debug.apk
put_conf
adb shell am start -n $PKG/$PKG.CustomQtActivity
if ! wait_ui '^Start$|^Stop$' 120; then
  echo "!! home page not shown in 120 s" >> $STEPLOG
  shot 00-no-home
  FAILED=1
fi
shot 01-home

# ---- TalkBack (T-324): the real Google TalkBack 15 of the image, gestures through its touch
# explorer (A11yDriver --keep, recipe notes/talkback-in-emulator-2026-10-15.md)
#  t1: the nodes of "Changed": Reset all and Reset: <title> visible, clickable
#  t2: swipe right from the title "Changed settings (6)": the focus reaches Reset all, the card
#      and its Reset: <title> (the button is not swallowed by the card)
#  t3: double tap on the focused Reset: Player Weight - the page made again with 5
#  t4: double tap on Reset all - TalkBack reads the confirmation; Yes - "No changed settings"
echo "== t: TalkBack" >> $STEPLOG
TBPKG=com.google.android.marvin.talkback
mkdir -p drv
open_changed t
check "t: six listed" '^Changed settings \(6\)$' 10
shot t-0-changed

SDK=${ANDROID_SDK_ROOT:-$ANDROID_HOME}
JAR=$SDK/platforms/android-35/android.jar
BT=$(ls -d $SDK/build-tools/*/ | sort -V | tail -n 1)
if javac -source 8 -target 8 -bootclasspath $JAR -d drv .github/A11yDriver.java >> $STEPLOG 2>&1 \
    && ${BT}d8 --lib $JAR --output a11y.jar drv/*.class >> $STEPLOG 2>&1; then
  adb push a11y.jar /data/local/tmp/a11y.jar > /dev/null
  echo "driver built" >> $STEPLOG
else
  echo "!! driver NOT built - the TalkBack part proves nothing" >> $STEPLOG
  FAILED=1
fi
drv() {
  local name=$1 args="" a
  shift
  for a in "$@"; do args="$args '$a'"; done
  echo "== drv $name:$args" >> $STEPLOG
  timeout 200 adb shell "CLASSPATH=/data/local/tmp/a11y.jar app_process / A11yDriver$args" > drv/$name.txt 2>&1 || true
  cat drv/$name.txt >> $STEPLOG
  sleep 2
}
# drv_check <name> <drv file> <fixed string>: a line of the driver output has it
drv_check() {
  if grep -q -F "$3" drv/$2.txt 2>/dev/null; then
    echo "check $1: OK" >> $STEPLOG
  else
    echo "!! check $1: '$3' not in drv/$2.txt" >> $STEPLOG
    FAILED=1
  fi
}

# adbd as root for the preferences of TalkBack: it restarts and cuts the logcat, so a second one
adb shell am force-stop $TBPKG || true
adb root >> $STEPLOG 2>&1 || true
adb wait-for-device
sleep 3
adb logcat -v threadtime -b main,system,crash > tb_logcat.txt 2>/dev/null &
TB_LOGCAT_PID=$!
printf '%s\n' "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>" '<map>' \
  '    <boolean name="pref_tts_overlay" value="true" />' \
  '    <boolean name="first_time_user" value="false" />' \
  '    <boolean name="pref_has_performed_restore_key" value="true" />' '</map>' > tbprefs.xml
adb push tbprefs.xml /data/local/tmp/tbprefs.xml > /dev/null
for dir in /data/user_de/0/$TBPKG /data/data/$TBPKG; do
  adb shell "mkdir -p $dir/shared_prefs && cp /data/local/tmp/tbprefs.xml $dir/shared_prefs/${TBPKG}_preferences.xml \
    && chown -R \$(stat -c %u:%g $dir) $dir/shared_prefs && chmod 771 $dir/shared_prefs \
    && chmod 660 $dir/shared_prefs/${TBPKG}_preferences.xml && restorecon -R $dir/shared_prefs" >> $STEPLOG 2>&1 || true
done
adb shell "rm -rf /data/local/tmp/tbshots; mkdir -p /data/local/tmp/tbshots"

echo "== talkback on: $(adb shell dumpsys package $TBPKG | grep -m1 versionName)" >> $STEPLOG
adb shell settings put secure enabled_accessibility_services $TBPKG/$TBPKG.TalkBackService >> $STEPLOG 2>&1
adb shell settings put secure accessibility_enabled 1 >> $STEPLOG 2>&1
adb shell settings put secure touch_exploration_enabled 1 >> $STEPLOG 2>&1
sleep 15
adb shell dumpsys accessibility > tb_dumpsys.txt 2>&1 || true
grep -iE "Bound services|Enabled features" tb_dumpsys.txt | head -n 4 >> $STEPLOG || true
if grep -i "Bound services" tb_dumpsys.txt | grep -q -i talkback; then
  echo "check t: TalkBack bound: OK" >> $STEPLOG
else
  echo "!! check t: TalkBack not bound - the TalkBack part proves nothing" >> $STEPLOG
  FAILED=1
fi
# The notification question of the Accessibility Suite comes over the app: the app to the front
adb shell am start -n $PKG/$PKG.CustomQtActivity >> $STEPLOG 2>&1 || true
sleep 6
adb exec-out screencap -p > t-1-on.png || true

drv t1-list --keep list
# node_check <name> <start of the description>: in the list, visible and clickable
node_check() {
  if grep -F "'$2" drv/t1-list.txt | grep -q -F "visible=true clickable=true"; then
    echo "check $1: OK" >> $STEPLOG
  else
    echo "!! check $1: '$2' not visible and clickable in drv/t1-list.txt" >> $STEPLOG
    FAILED=1
  fi
}
node_check "t1: Reset all" "Reset all'"
node_check "t1: Reset of Player Weight" "Reset: Player Weight (kg)'"
grep -E "'(Reset all|Reset: [^']*|Changed settings[^']*|Player Weight[^']*)'" drv/t1-list.txt | sed 's/^ */   /' >> $STEPLOG || true

# From Clear (a button: a touch focuses it; on the title the touch went to the window, run
# 42476067986), then on through the title, Reset all, the first card and its Reset
drv t2-order --keep 'focus:Clear' 'sleep:1500' 'touch:Clear' \
  'swipe:right' 'swipe:right' 'swipe:right' 'swipe:right' 'swipe:right' 'swipe:right' 'swipe:right' 'swipe:right'
drv_check "t2: Clear focused by touch" t2-order "touch:Clear: focused 'Clear'"
drv_check "t2: swipe reaches Reset all" t2-order "swipe:right: focused 'Reset all'"
drv_check "t2: swipe reaches the card" t2-order "swipe:right: focused 'Player Weight (kg): 90'"
drv_check "t2: swipe reaches Reset of the card" t2-order "swipe:right: focused 'Reset: Player Weight (kg)'"
adb exec-out screencap -p > t-2-order.png || true

drv t3-row --keep 'focus:Reset: Player Weight' 'sleep:1500' 'touch:Reset: Player Weight' 'dtap' 'sleep:4000' \
  'find:Changed settings' 'focused'
drv_check "t3: Reset focused before the double tap" t3-row "touch:Reset: Player Weight: focused 'Reset: Player Weight (kg)'"
drv_check "t3: five left" t3-row "find:Changed settings: 'Changed settings (5)'"
adb exec-out screencap -p > t-3-row.png || true

drv t4-all --keep 'focus:Reset all' 'sleep:1500' 'touch:Reset all' 'dtap' 'sleep:2000' 'list'
drv_check "t4: Reset all focused before the double tap" t4-all "touch:Reset all: focused 'Reset all'"
# The speech overlay is not in getWindows (said [] - notes/talkback-in-emulator): the native
# dialog is told by its buttons (the nodes of Qt are View$VirtualChild); its text - drv/shots
drv_check "t4: the confirmation opened" t4-all "class=android.widget.Button"
adb exec-out screencap -p > t-4-confirm.png || true

# TalkBack off for the dump: Yes of the native dialog by its text
echo "== talkback off" >> $STEPLOG
adb shell settings put secure touch_exploration_enabled 0 >> $STEPLOG 2>&1
adb shell settings put secure enabled_accessibility_services null >> $STEPLOG 2>&1
adb shell settings put secure accessibility_enabled 0 >> $STEPLOG 2>&1
sleep 10
if tap_ui '^Yes$'; then
  check "t4: none left" '^No changed settings$' 15
  shot t-5-after
else
  FAILED=1
fi
mkdir -p drv/shots
adb pull /data/local/tmp/tbshots/. drv/shots > /dev/null 2>&1 || true
kill $TB_LOGCAT_PID 2>/dev/null || true
wait $TB_LOGCAT_PID 2>/dev/null || true
grep -a -E "ANR in|FATAL EXCEPTION|Fatal signal" tb_logcat.txt | sed 's/^/!! /' >> $STEPLOG || true
grep -a -q -E "qrc:/settings\.qml.*(TypeError|ReferenceError)" full_logcat.txt tb_logcat.txt && { echo "!! JS error in settings.qml" >> $STEPLOG; FAILED=1; }
adb shell am force-stop $PKG || true
kill $LOGCAT_PID 2>/dev/null || true
wait $LOGCAT_PID 2>/dev/null || true
grep -q "^check " $STEPLOG || { echo "!! no check ran: the run proves nothing" >> $STEPLOG; FAILED=1; }
cat $STEPLOG
exit $FAILED
