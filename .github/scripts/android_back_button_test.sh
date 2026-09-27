#!/bin/sh
# Back button test for the android-emulator-test job (issue #1386).
# Expects the app to be started already. Single back presses must navigate
# inside the app, only a double back press on the home page may exit.

API=$(adb shell getprop ro.build.version.sdk | tr -d '\r')
echo "Back button test on API $API"

# The API < 30 emulator images have no Bluetooth, so QZ keeps its modal
# "Permissions Required" dialog open (it needs Bluetooth and location) and the
# dialog swallows back presses: the test would not check anything there.
if [ "$API" -lt 30 ]; then
  echo "SKIPPED: no Bluetooth on this emulator image, the Permissions Required dialog blocks the app"
  exit 0
fi

qz_in_front() {
  adb shell dumpsys activity activities | grep -E "mResumedActivity|topResumedActivity" | grep -q CustomQtActivity
}

shot() {
  adb shell screencap -p "/sdcard/screenshot_back_$1.png"
  adb pull "/sdcard/screenshot_back_$1.png"
}

adb shell settings put system user_rotation 0
sleep 5

# Close system screens opened at startup (e.g. Health Connect permissions) until QZ is in front
for i in 1 2 3 4 5; do
  qz_in_front && break
  echo "QZ is not in front, pressing back ($i)"
  adb shell input keyevent KEYCODE_BACK
  sleep 5
done
shot 0
if ! qz_in_front; then
  echo "TEST FAILED: QZ is not in front before the back button test"
  exit 1
fi

# Single presses, more than 2 s apart: the first leaves the wizard,
# the next ones show "Press back again to exit"
for i in 1 2 3; do
  echo "Single back press $i"
  adb shell input keyevent KEYCODE_BACK
  sleep 1
  shot "$i"
  sleep 4
  if ! qz_in_front; then
    echo "TEST FAILED: single back press $i closed the app"
    exit 1
  fi
done
echo "Single back presses kept the app open"

# Two presses in one command, well within 2 s: the app must exit
adb shell input keyevent KEYCODE_BACK KEYCODE_BACK
sleep 10
shot exit
if qz_in_front; then
  echo "TEST FAILED: double back press did not close the app"
  exit 1
fi
echo "Back button test passed"
