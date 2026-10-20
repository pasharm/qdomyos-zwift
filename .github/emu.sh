#!/bin/bash
# Test only (T-246): which voice speaks the spoken texts of QZ. The test APK logs the speech
# engine of homeform ("T246" lines), says a sample of the summary in the app language 20 s after
# the start (as QZ does now) and again 40 s after the start with the English locale set once
# more; its Java probe writes the same texts to WAV files with the English, the Russian, the
# Ukrainian and the default voice. Each case below is one start of the app:
#   ru     - app in Russian, the system (and the default voice of the engine) in English
#   uk     - the same in Ukrainian
#   sys-ru - the system in Russian too (root, zygote restart), app in Russian
# AUDIO=pa: the sound of the emulator goes to a PulseAudio null sink, recorded per case into
# audio-<case>.wav - what the app itself said.
PKG=org.cagnulen.qdomyoszwift
SCENARIO=${SCENARIO:-full}
AUDIO=${AUDIO:-none}
STEPLOG=steps.log
: > $STEPLOG

adb install apk-debug/android-debug.apk
for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION BLUETOOTH_ADVERTISE BLUETOOTH_CONNECT BLUETOOTH_SCAN POST_NOTIFICATIONS; do
  adb shell pm grant $PKG android.permission.$p || true
done
adb shell appops set $PKG MANAGE_EXTERNAL_STORAGE allow || true
adb shell settings put global hide_error_dialogs 1 || true
# Files of an earlier install are hidden from this one on Android 14+: start clean
adb shell 'rm -rf /sdcard/Documents/QZ/t246' || true

{
  echo "== speech engines of the image"
  adb shell pm list packages | grep -iE 'tts|speech|svox|pico|espeak' || true
  echo "tts_default_synth: $(adb shell settings get secure tts_default_synth)"
  echo "tts_default_locale: $(adb shell settings get secure tts_default_locale)"
  echo "system locale: $(adb shell getprop persist.sys.locale) / $(adb shell getprop ro.product.locale)"
  adb shell dumpsys package com.google.android.tts | grep -m2 -E 'versionName|versionCode' || true
} >> $STEPLOG

start_logcat() {
  adb logcat > logcat-$1.txt 2>/dev/null &
  LOGCAT_PID=$!
}
stop_logcat() {
  kill $LOGCAT_PID 2>/dev/null || true
  wait $LOGCAT_PID 2>/dev/null || true
}

put_conf() {
  printf '[General]\nlog_debug=true\nui_modern=true\ntts_enabled=true\ntts_description_enabled=true\n%b' "$1" > qz.conf
  adb push qz.conf /data/local/tmp/qz.conf
  adb shell "run-as $PKG mkdir -p 'files/.config/Roberto Viola'"
  adb shell "run-as $PKG cp /data/local/tmp/qz.conf 'files/.config/Roberto Viola/qDomyos-Zwift.conf'"
}

# run_case <name> <app language>: one start of the app, 80 s, then its WAV files and lines
run_case() {
  local name="$1" lang="$2" rec=""
  echo "== case $name (app_language=$lang, system $(adb shell getprop persist.sys.locale))" >> $STEPLOG
  adb shell am force-stop $PKG || true
  adb shell 'rm -rf /sdcard/Documents/QZ/t246' || true
  sleep 3
  put_conf "app_language=$lang\n"
  adb logcat -c || true
  start_logcat $name
  if [ "$AUDIO" = "pa" ]; then
    parecord -d qzsink.monitor --file-format=wav audio-$name.wav &
    rec=$!
  fi
  adb shell am start -n $PKG/$PKG.CustomQtActivity
  sleep 80
  [ -n "$rec" ] && { kill $rec 2>/dev/null; wait $rec 2>/dev/null; }
  adb shell screencap -p /sdcard/$name.png || true
  adb pull /sdcard/$name.png || true
  stop_logcat
  mkdir -p t246-$name
  adb shell 'ls -la /sdcard/Documents/QZ/t246/' >> t246-$name/listing.txt 2>&1 || true
  for f in $(adb shell 'ls /sdcard/Documents/QZ/t246/ 2>/dev/null' | tr -d '\r' | grep '[.]wav$'); do
    adb pull "/sdcard/Documents/QZ/t246/$f" "t246-$name/$f" > /dev/null 2>&1 || true
  done
  # Where the probe wrote, in case Documents/QZ is not the dir of the app here
  adb shell "run-as $PKG find . -name '*.wav'" >> t246-$name/listing.txt 2>&1 || true
  grep -E "T246|TextToSpeech|QtTextToSpeech|TTS|UtteranceProgress|GoogleTTS" logcat-$name.txt > t246-$name/lines.txt || true
  echo "T246 lines: $(grep -c T246 logcat-$name.txt), wav: $(ls t246-$name/*.wav 2>/dev/null | wc -l)" >> $STEPLOG
  [ -f audio-$name.wav ] && echo "audio-$name.wav: $(stat -c %s audio-$name.wav) bytes" >> $STEPLOG
  cat logcat-$name.txt >> full_logcat.txt
}

run_case ru ru
if [ "$SCENARIO" = "full" ]; then
  run_case uk uk
  # The system in Russian: the default voice of the engine follows it
  adb root || true
  sleep 5
  adb wait-for-device
  adb shell setprop persist.sys.locale ru-RU || true
  adb shell setprop ctl.restart zygote || true
  sleep 10
  adb wait-for-device
  for i in $(seq 1 60); do
    [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = "1" ] && break
    sleep 3
  done
  sleep 20
  echo "system locale now: $(adb shell getprop persist.sys.locale)" >> $STEPLOG
  run_case sys-ru ru
fi

adb shell "ps -A 2>/dev/null || ps" > process_list.txt || true
mkdir -p qz-logs
for f in $(adb shell 'ls /sdcard/Documents/QZ/ 2>/dev/null' | tr -d '\r' | grep '^debug-.*[.]log$'); do
  adb pull "/sdcard/Documents/QZ/$f" "qz-logs/$f" > /dev/null 2>&1 || true
done
echo "== steps"; cat $STEPLOG
for d in t246-*; do echo "== $d"; grep -E "T246" $d/lines.txt | cut -c1-400; done
echo "== TextToSpeech framework"; grep -hE " TextToSpeech|QtTextToSpeech" t246-*/lines.txt | cut -c1-300 | head -n 80
