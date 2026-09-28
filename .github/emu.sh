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
shot() { adb shell screencap -p /sdcard/$1.png || true; adb pull /sdcard/$1.png || true; }
# Nexus 6: 1440x2560 px, 3.5 px per dp
sleep 20
shot 01-healthconnect
adb shell input keyevent KEYCODE_BACK || true
sleep 30
shot 02-first-screen        # the wizard opens on the first run
adb shell input tap 720 2244 || true   # Start
sleep 4
shot 03-wizard-step1
adb shell input tap 720 620 || true    # first answer
sleep 4
shot 03b-wizard-step2
adb shell input keyevent KEYCODE_BACK || true
sleep 2
adb shell input keyevent KEYCODE_BACK || true
sleep 3
adb shell input keyevent KEYCODE_BACK || true
sleep 5
shot 04-home
adb shell input tap 84 168 || true      # menu button on the toolbar
sleep 4
shot 05-drawer
adb shell input swipe 500 2200 500 900 400 || true
sleep 3
shot 06-drawer-scrolled
adb shell input tap 525 861 || true     # Settings entry in the scrolled drawer
sleep 8
shot 07-settings
adb shell input tap 720 520 || true     # a section header
sleep 4
shot 08-settings-open
adb shell input swipe 700 2100 700 700 400 || true
sleep 3
shot 09-settings-scrolled
adb shell "ps -A 2>/dev/null || ps" > process_list.txt || true
shot screenshot
adb logcat -d > full_logcat.txt || true
grep -iE "qrc:|\.qml|warning|critical|fatal" full_logcat.txt | tail -n 80 || true
