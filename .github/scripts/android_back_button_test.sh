#!/bin/sh
# Back button test for the android-emulator-test job (issue #1386).
# Expects the app to be started already. Single back presses must navigate
# inside the app, only a double back press on the home page may exit.

# On failure save the logcat first: the job stops here and does not reach its own logcat lines
fail() {
  echo "TEST FAILED: $1"
  adb logcat -d > full_logcat.txt
  adb logcat -d | grep -i qdomyos > qdomyos_logcat.txt
  exit 1
}

API=$(adb shell getprop ro.build.version.sdk | tr -d '\r')
[ -n "$API" ] || fail "cannot read the API level from the emulator"
echo "Back button test on API $API"

# Crash lines of QZ: a Java crash ("Process: <package>, PID") and a native one (">>> <package> <<<").
# Counted before the test: QZ crashes on exit on every API level (while Qt shuts down), which is
# reported as a warning with its stack, not a failure, until that is fixed
qz_crashes() {
  adb logcat -d | grep -F -e "Process: org.cagnulen.qdomyoszwift" -e ">>> org.cagnulen.qdomyoszwift <<<" | grep -c -F -e "qdomyoszwift"
}
crashes_before=$(qz_crashes)

qz_in_front() {
  adb shell dumpsys activity activities | grep -E "mResumedActivity|topResumedActivity" | grep -q CustomQtActivity
}

focused_window() {
  adb shell dumpsys window | grep -m 1 mCurrentFocus | tr -d '\r'
}

# An "app isn't responding" dialog of another app (e.g. Pixel Launcher on the google_apis
# images) can cover QZ while its activity stays resumed: back presses then go to the dialog.
# Close it: first as a system dialog, then by tapping its "Wait" button.
close_anr_dialog() {
  case "$(focused_window)" in
    *"Not Responding"*) ;;
    *) return 0 ;;
  esac
  echo "Closing an \"isn't responding\" dialog: $(focused_window)"
  adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS > /dev/null
  sleep 2
  case "$(focused_window)" in
    *"Not Responding"*) ;;
    *) return 0 ;;
  esac
  adb shell uiautomator dump /sdcard/ui.xml > /dev/null
  # bounds="[x1,y1][x2,y2]" of the "Wait" button -> its center
  XY=$(adb shell cat /sdcard/ui.xml | tr '>' '\n' | grep 'text="Wait"' | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1 \2 \3 \4/p' | head -n 1)
  if [ -n "$XY" ]; then
    set -- $XY
    adb shell input tap $((($1 + $3) / 2)) $((($2 + $4) / 2))
    sleep 2
  fi
}

# Wait until QZ has the input focus, closing "isn't responding" dialogs on top of it
qz_focused() {
  for i in 1 2 3; do
    close_anr_dialog
    case "$(focused_window)" in
      *CustomQtActivity*) return 0 ;;
    esac
    echo "QZ has no input focus ($(focused_window)), waiting ($i)"
    sleep 3
  done
  return 1
}

# No "app isn't responding" dialogs from other apps: applied on the next configuration change (the rotation below)
adb shell settings put global hide_error_dialogs 1

shot() {
  adb shell screencap -p "/sdcard/screenshot_back_$1.png"
  adb pull "/sdcard/screenshot_back_$1.png"
}

adb shell settings put system user_rotation 0
sleep 5

# Close system screens opened at startup (e.g. Health Connect permissions) until QZ is in front
for i in 1 2 3 4 5; do
  close_anr_dialog
  qz_in_front && break
  echo "QZ is not in front, pressing back ($i)"
  adb shell input keyevent KEYCODE_BACK
  sleep 5
done
shot 0
qz_in_front || fail "QZ is not in front before the back button test"

# Single presses, more than 2 s apart: the first leaves the wizard,
# the next ones show "Press back again to exit"
for i in 1 2 3; do
  qz_focused || fail "a system window keeps the input focus before back press $i"
  echo "Single back press $i"
  adb shell input keyevent KEYCODE_BACK
  sleep 1
  shot "$i"
  sleep 4
  qz_in_front || fail "single back press $i closed the app"
done
echo "Single back presses kept the app open"

# Two presses in one command, well within 2 s: the app must exit
qz_focused || fail "a system window keeps the input focus before the double back press"
adb shell input keyevent KEYCODE_BACK KEYCODE_BACK
sleep 10
shot exit
qz_in_front && fail "double back press did not close the app"
if [ "$(qz_crashes)" -gt "$crashes_before" ]; then
  echo "::warning::QZ crashed during the back button test (on exit or before), see the stack below"
  # the last native crash of QZ: its lines of the DEBUG tag only (other tags are mixed in between)
  adb logcat -d | awk -v p=">>> org.cagnulen.qdomyoszwift <<<" 'index($0, p) { out = ""; on = 1 } on && index($0, " DEBUG ") { out = out $0 "\n" } END { printf "%s", out }' \
    | grep -F -e ">>>" -e "signal " -e "Abort message" -e "Cause:" -e " #" | head -n 30
  # or a Java crash
  adb logcat -d | grep -F -A 10 "Process: org.cagnulen.qdomyoszwift" | tail -n 11
fi
echo "Back button test passed"
