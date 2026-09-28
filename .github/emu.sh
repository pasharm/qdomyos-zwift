#!/bin/bash
# Test only: start an already built APK on the emulator with log_debug on, so the Qt
# warnings (QML errors among them) reach logcat, then keep logcat and screenshots.
PKG=org.cagnulen.qdomyoszwift
adb install apk-debug/android-debug.apk
for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION BLUETOOTH_ADVERTISE BLUETOOTH_CONNECT BLUETOOTH_SCAN POST_NOTIFICATIONS; do
  adb shell pm grant $PKG android.permission.$p || true
done
adb shell appops set $PKG MANAGE_EXTERNAL_STORAGE allow || true

printf '[General]\nlog_debug=true\n' > qz.conf
adb push qz.conf /data/local/tmp/qz.conf
adb shell "run-as $PKG mkdir -p 'files/.config/Roberto Viola'"
adb shell "run-as $PKG cp /data/local/tmp/qz.conf 'files/.config/Roberto Viola/qDomyos-Zwift.conf'"
adb shell "run-as $PKG ls -la 'files/.config/Roberto Viola'" || true

adb logcat -c || true
adb shell am start -n $PKG/$PKG.CustomQtActivity
sleep 20
adb shell screencap -p /sdcard/shot1.png || true
adb pull /sdcard/shot1.png || true
adb shell input keyevent KEYCODE_BACK || true
sleep 40
adb shell "ps -A 2>/dev/null || ps" > process_list.txt || true
adb shell screencap -p /sdcard/screenshot.png || true
adb pull /sdcard/screenshot.png || true
adb logcat -d > full_logcat.txt || true
grep -iE "qrc:|\.qml|warning|critical|fatal" full_logcat.txt | tail -n 80 || true
