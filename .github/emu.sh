#!/bin/bash
# Test only (T-199): how many times a double tap of the real TalkBack fires a control.
# Qt 5.15 clickAction() runs the press action and answers false, and a false answer makes Android
# tap the middle of the node, so a control with Accessible.onPressAction may fire twice.
# Counted from the log of QZ ("Start pressed", "Stop pressed"), the tile value and qz.conf.
# Compare a build with Start/Stop onPressAction against one without (input source).
PKG=org.cagnulen.qdomyoszwift
TBPKG=com.google.android.marvin.talkback
UI_MODERN=${UI_MODERN:-false}
LOG_DEBUG=${LOG_DEBUG:-true}
STEPLOG=steps.log
: > $STEPLOG
mkdir -p dumps drv

adb install apk-debug/android-debug.apk
adb shell pm path $PKG > /dev/null 2>&1 || echo "!! APK NOT INSTALLED - the run proves nothing" >> $STEPLOG
for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION BLUETOOTH_ADVERTISE BLUETOOTH_CONNECT BLUETOOTH_SCAN POST_NOTIFICATIONS; do
  adb shell pm grant $PKG android.permission.$p || true
done
adb shell appops set $PKG MANAGE_EXTERNAL_STORAGE allow || true
for p in EXERCISE DISTANCE TOTAL_CALORIES_BURNED HEART_RATE POWER SPEED CYCLING_PEDALING_CADENCE ELEVATION_GAINED STEPS STEPS_CADENCE HEART_RATE_VARIABILITY; do
  adb shell pm grant $PKG android.permission.health.WRITE_$p || true
done
adb shell cmd uimode night no || true
adb shell settings put global hide_error_dialogs 1 || true

printf '[General]\nlog_debug=%s\nui_modern=%s\napplewatch_fakedevice=true\nbluetooth_lastdevice_name=Fake\nskipLocationServicesDialog=true\n' "$LOG_DEBUG" "$UI_MODERN" > qz.conf
adb push qz.conf /data/local/tmp/qz.conf
adb shell "run-as $PKG mkdir -p 'files/.config/Roberto Viola'"
adb shell "run-as $PKG cp /data/local/tmp/qz.conf 'files/.config/Roberto Viola/qDomyos-Zwift.conf'"

# uiautomator switches TalkBack off: only while TalkBack is off
dump() {
  rm -f ui.xml
  timeout 25 adb shell uiautomator dump /data/local/tmp/ui.xml > /dev/null 2>&1 || true
  adb pull /data/local/tmp/ui.xml ui.xml > /dev/null 2>&1 || true
}
tshot() { echo "-- shot $1" >> $STEPLOG; adb shell screencap -p /sdcard/$1.png >> $STEPLOG 2>&1 || true; adb pull /sdcard/$1.png >> $STEPLOG 2>&1 || true; }
find_ui() { [ -f ui.xml ] && python3 .github/uitap.py ui.xml "$1"; }
tap_ui() {
  local xy=""
  dump
  xy=$(find_ui "$1")
  if [ -n "$xy" ]; then
    echo "tap '$1': by label at $xy" >> $STEPLOG
    adb shell input tap $xy || true
  else
    echo "tap '$1': NOT FOUND, coordinates $2 $3" >> $STEPLOG
    adb shell input tap $2 $3 || true
  fi
}
scroll_to() {
  local i
  for i in $(seq 1 40); do
    dump
    if find_ui "$1" > /dev/null; then
      echo "scroll to '$1': found after $((i - 1)) swipes" >> $STEPLOG
      return 0
    fi
    adb shell input swipe 700 2000 700 1000 400 || true
    sleep 1
  done
  echo "scroll to '$1': NOT FOUND" >> $STEPLOG
  return 1
}
# Anything over the app (Health Connect on the first start): the back key
to_app() {
  local i pkg
  for i in 1 2 3; do
    dump
    pkg=$([ -f ui.xml ] && python3 .github/uitap.py ui.xml --package)
    if [ -z "$pkg" ] || [ "$pkg" = "$PKG" ]; then return 0; fi
    echo "!! $pkg over the app: back key" >> $STEPLOG
    adb shell input keyevent KEYCODE_BACK || true
    sleep 4
  done
}

adb logcat -c || true
adb logcat > full_logcat.txt 2>/dev/null &
LOGCAT_PID=$!
adb shell am start -n $PKG/$PKG.CustomQtActivity
sleep 25
to_app
sleep 15
to_app
tshot h-01-home

# The driver: compiled here against the SDK the emulator action installed
SDK=${ANDROID_SDK_ROOT:-$ANDROID_HOME}
JAR=$SDK/platforms/android-35/android.jar
BT=$(ls -d $SDK/build-tools/*/ | sort -V | tail -n 1)
if javac -source 8 -target 8 -bootclasspath $JAR -d drv .github/A11yDriver.java >> $STEPLOG 2>&1 \
    && ${BT}d8 --lib $JAR --output a11y.jar drv/*.class >> $STEPLOG 2>&1; then
  adb push a11y.jar /data/local/tmp/a11y.jar > /dev/null
  echo "driver built" >> $STEPLOG
else
  echo "driver NOT built" >> $STEPLOG
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
conf() {
  sleep 2
  echo "== conf $1: $(adb shell "run-as $PKG cat 'files/.config/Roberto Viola/qDomyos-Zwift.conf'" | tr -d '\r' | grep -E '^(battery_service|virtual_device_enabled)=' | tr '\n' ' ')" >> $STEPLOG
}

# adbd as root for the preferences of TalkBack: it restarts, so a new logcat from here on
adb shell am force-stop $TBPKG || true
adb root >> $STEPLOG 2>&1 || true
adb wait-for-device
sleep 3
adb logcat > tb_logcat.txt 2>/dev/null &
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

tb_on() {
  echo "== talkback on: $(adb shell dumpsys package $TBPKG | grep -m1 versionName)" >> $STEPLOG
  adb shell settings put secure enabled_accessibility_services $TBPKG/$TBPKG.TalkBackService >> $STEPLOG 2>&1
  adb shell settings put secure accessibility_enabled 1 >> $STEPLOG 2>&1
  adb shell settings put secure touch_exploration_enabled 1 >> $STEPLOG 2>&1
  sleep 15
  adb shell dumpsys accessibility | grep -iE "Bound services|Enabled features" | head -n 4 >> $STEPLOG || true
  adb shell am start -n $PKG/$PKG.CustomQtActivity >> $STEPLOG 2>&1 || true
  sleep 6
}
tb_off() {
  echo "== talkback off" >> $STEPLOG
  adb shell settings put secure touch_exploration_enabled 0 >> $STEPLOG 2>&1
  adb shell settings put secure enabled_accessibility_services null >> $STEPLOG 2>&1
  adb shell settings put secure accessibility_enabled 0 >> $STEPLOG 2>&1
  sleep 10
}

tb_on
tshot t-00-on

# The nodes of the home page, for the record
drv t-list --keep list

# A tile: Accessible.onPressAction in master too. One double tap, the value should go up by one
drv t-plus --keep 'mark:plus' 'focus:Increase Resistance' 'sleep:1500' 'touch:Increase Resistance' \
  'find:Resistance:' 'dtap' 'sleep:2500' 'find:Resistance:' 'dtap' 'sleep:2500' 'find:Resistance:'
tshot t-01-plus

# Start: two double taps, two lines "Start pressed" if each fires once
drv t-start --keep 'mark:start' 'focus:Start' 'sleep:1500' 'touch:Start' 'mark:start-tap-1' 'dtap' 'sleep:3000' \
  'mark:start-tap-2' 'dtap' 'sleep:3000' 'mark:start-end'
tshot t-02-start

# Stop: one double tap
drv t-stop --keep 'mark:stop' 'focus:Stop' 'sleep:1500' 'touch:Stop' 'mark:stop-tap-1' 'dtap' 'sleep:4000' 'mark:stop-end'
tshot t-03-stop

# Off for the walk to the settings page: uiautomator and plain taps need it off
tb_off
for i in 1 2 3; do
  dump
  if find_ui '^Start$' > /dev/null || find_ui '^Pause$' > /dev/null; then break; fi
  echo "back key $i: home page not in front" >> $STEPLOG
  adb shell input keyevent KEYCODE_BACK || true
  sleep 3
done
tshot t-04-home-again
echo "tap 84 168 (menu)" >> $STEPLOG
adb shell input tap 84 168 || true
sleep 3
adb shell input swipe 500 700 500 2300 300 || true
sleep 2
tap_ui '^Settings$' 400 900
sleep 8
if ! scroll_to 'Experimental Features'; then
  tshot t-05-no-section
fi
tap_ui 'Experimental Features' 700 1300
sleep 3
scroll_to 'Simulate Battery Service'
dump
[ -f ui.xml ] && cp ui.xml dumps/settings-before.xml
tshot t-05-settings
conf before

tb_on

# A switch of the settings pages: one double tap should change the setting once
drv t-switch --keep 'mark:switch' 'focus:Simulate Battery Service' 'sleep:1500' 'touch:Simulate Battery Service' \
  'find:Simulate Battery Service' 'dtap' 'sleep:2500' 'find:Simulate Battery Service'
conf switch-1
drv t-switch2 --keep 'mark:switch-2' 'dtap' 'sleep:2500' 'find:Simulate Battery Service'
conf switch-2
tshot t-06-switch

# The accordion switch: the same, and its content opens or closes
drv t-accordion --keep 'mark:accordion' 'focus:Enable Virtual Device' 'sleep:1500' 'touch:Enable Virtual Device' \
  'find:Enable Virtual Device' 'dtap' 'sleep:2500' 'find:Enable Virtual Device'
conf accordion-1
drv t-accordion2 --keep 'mark:accordion-2' 'dtap' 'sleep:2500' 'find:Enable Virtual Device'
conf accordion-2
tshot t-07-accordion

mkdir -p drv/shots
adb pull /data/local/tmp/tbshots/. drv/shots >> $STEPLOG 2>&1 || true
mkdir -p qz-logs
adb shell 'ls -la /sdcard/Documents/QZ/ 2>&1' > qz-logs/listing.txt || true
for f in $(adb shell 'ls /sdcard/Documents/QZ/' | tr -d '\r' | grep -E '\.log$'); do
  adb pull "/sdcard/Documents/QZ/$f" "qz-logs/$f" > /dev/null 2>&1 || true
done

adb shell "ps -A 2>/dev/null || ps" > process_list.txt || true
kill $LOGCAT_PID 2>/dev/null || true
wait $LOGCAT_PID 2>/dev/null || true
kill $TB_LOGCAT_PID 2>/dev/null || true
wait $TB_LOGCAT_PID 2>/dev/null || true
cat full_logcat.txt tb_logcat.txt | grep -E "ANR in|FATAL EXCEPTION" | sed 's/^/!! /' >> $STEPLOG || true

echo "== presses in logcat, in order, with the marks of the driver" >> $STEPLOG
grep -E "A11yDriver: mark|Start pressed|Stop pressed|ACTION_CLICK failed" tb_logcat.txt >> $STEPLOG || true
echo "== presses in the debug log of QZ" >> $STEPLOG
grep -h -E "Start pressed|Stop pressed" qz-logs/*.log 2>/dev/null | cut -c1-160 >> $STEPLOG || true
grep -E "Speaking fragment|A11yDriver" tb_logcat.txt > tb-speech.txt || true

echo "== steps"; cat $STEPLOG
echo "== QML warnings"; cat full_logcat.txt tb_logcat.txt | grep -iE "qrc:|\.qml:[0-9]+" | grep -iE "warning|error|ReferenceError|TypeError" | sort | uniq -c | sort -nr | head -40 || true
