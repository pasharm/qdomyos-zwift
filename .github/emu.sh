#!/bin/bash
# Test only: start an already built APK on the emulator with log_debug on, so the Qt
# warnings (QML errors among them) reach logcat, then keep logcat and screenshots.
# The emulator starts in the day mode of the system: with the appearance on "auto" the
# first screens are the light theme, the last ones the dark theme after "night yes".
PKG=org.cagnulen.qdomyoszwift
adb install apk-debug/android-debug.apk
for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION BLUETOOTH_ADVERTISE BLUETOOTH_CONNECT BLUETOOTH_SCAN POST_NOTIFICATIONS; do
  adb shell pm grant $PKG android.permission.$p || true
done
adb shell appops set $PKG MANAGE_EXTERNAL_STORAGE allow || true
adb shell cmd uimode night no || true

# UI_MODERN (workflow input "modern"): false runs the same steps in the classic look, for a
# before/after comparison; the taps are laid out for the modern look
UI_MODERN=${UI_MODERN:-true}
printf '[General]\nlog_debug=true\nconfirm_stop_workout=true\nui_modern=%s\n' "$UI_MODERN" > qz.conf
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
adb shell input tap 952 462 || true     # Stop pill: confirmation dialog
sleep 3
shot 04b-stop-dialog
adb shell input keyevent KEYCODE_BACK || true
sleep 2
adb shell input tap 84 168 || true      # menu button on the toolbar
sleep 4
shot 05-drawer
adb shell input tap 403 927 || true     # Workout Editor (drawer still at the top)
sleep 15
shot 05b-editor-light
adb shell input swipe 700 2000 700 900 400 || true
sleep 2
shot 05c-editor-light-scrolled
adb shell input tap 84 168 || true      # back arrow: home page
sleep 3
adb shell input tap 84 168 || true      # menu again
sleep 4
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

# Night mode of the system while the app runs: it is read again on return to the foreground
adb shell cmd uimode night yes || true
sleep 2
adb shell input keyevent KEYCODE_HOME || true
sleep 3
adb shell am start -n $PKG/$PKG.CustomQtActivity
sleep 5
shot 10-settings-dark
adb shell input keyevent KEYCODE_BACK || true
sleep 3
shot 11-home-dark
adb shell input tap 952 462 || true
sleep 3
shot 12-stop-dialog-dark
adb shell input keyevent KEYCODE_BACK || true
sleep 2
# The drawer keeps its scroll position between openings: scroll it to a known end first
adb shell input tap 84 168 || true      # menu
sleep 3
adb shell input swipe 500 700 500 2300 300 || true   # drawer to the top
sleep 2
adb shell input tap 335 434 || true     # profile chip in the drawer
sleep 5
shot 13-profiles-dark
adb shell input tap 84 168 || true      # back arrow: home page
sleep 3
adb shell input tap 1187 168 || true    # lock button on the home toolbar: notice popup
sleep 1
shot 14-lock-popup-dark
sleep 4                                 # the popup closes by itself after 2 s
adb shell input tap 84 168 || true      # menu
sleep 3
adb shell input swipe 500 2200 500 900 400 || true   # drawer scrolled as in step 06
sleep 3
adb shell input tap 525 861 || true     # Settings entry in the scrolled drawer
sleep 8
adb shell input tap 717 1239 || true    # Tiles Options page
sleep 6
shot 15-tiles-dark
adb shell input swipe 700 2100 700 900 400 || true
sleep 3
shot 16-tiles-scrolled-dark

adb shell input tap 84 168 || true      # back arrow: settings
sleep 3
shot 16b-settings-after-tiles-dark      # load and save buttons still in the toolbar
adb shell input tap 84 168 || true      # back arrow: home page
sleep 3
adb shell input tap 84 168 || true      # menu
sleep 3
adb shell input swipe 500 700 500 2300 300 || true   # drawer to the top
sleep 2
adb shell input tap 403 927 || true     # Workout Editor
sleep 15
shot 17-editor-dark
adb shell input swipe 700 2000 700 900 400 || true
sleep 2
shot 18-editor-dark-scrolled
adb shell input tap 84 168 || true      # back arrow: home page
sleep 3
adb shell input tap 84 168 || true      # menu
sleep 3
adb shell input swipe 500 700 500 2300 300 || true   # drawer to the top
sleep 2
adb shell input tap 346 1096 || true    # Open GPX
sleep 8
shot 19-gpx-dark
if [ "$UI_MODERN" = "true" ]; then
  adb shell input tap 400 589 || true   # first route card: selected, its figures as chips
  sleep 5
  shot 19b-gpx-route-dark
fi
# Landscape: the list column and the map side by side
adb shell settings put system accelerometer_rotation 0 || true
adb shell settings put system user_rotation 1 || true
sleep 5
shot 19c-gpx-landscape-dark
adb shell settings put system user_rotation 0 || true
sleep 5
adb shell input tap 84 168 || true      # back arrow: home page
sleep 3
adb shell input tap 84 168 || true      # menu
sleep 3
adb shell input swipe 500 700 500 2300 300 || true   # drawer to the top
sleep 2
adb shell input tap 433 1431 || true    # Workouts History
sleep 8
shot 20-history-dark
# Calendar button: on the right of the modern header, on the left of the classic one
if [ "$UI_MODERN" = "true" ]; then
  adb shell input tap 1299 322 || true
else
  adb shell input tap 126 300 || true
fi
sleep 3
shot 21-calendar-dark
adb shell input keyevent KEYCODE_BACK || true
sleep 2
adb shell input tap 84 168 || true      # back arrow: home page
sleep 3
adb shell input tap 84 168 || true      # menu
sleep 3
adb shell input swipe 500 700 500 2300 300 || true   # drawer to the top
sleep 2
adb shell input tap 307 1263 || true    # Charts
sleep 1
shot 22a-charts-loading-dark            # while loading: the busy indicator, no white page
sleep 9
shot 22-charts-dark
adb shell input swipe 700 2000 700 900 400 || true
sleep 2
shot 23-charts-dark-scrolled
adb shell input tap 720 2364 || true    # Close at the bottom of the charts page
sleep 3
shot 24-after-close-dark                # the home page again

adb shell "ps -A 2>/dev/null || ps" > process_list.txt || true
shot screenshot
adb logcat -d > full_logcat.txt || true
grep -iE "qrc:|\.qml|warning|critical|fatal" full_logcat.txt | tail -n 80 || true
