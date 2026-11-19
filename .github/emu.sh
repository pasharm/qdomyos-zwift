#!/bin/bash
# Test only (T-595): the workout editor and the program preview in the theme of the app - before (base: master)
# and after (head: the PR branch, modern look of the editor and the preview through qz-theme-bridge.js). Each
# page in the classic look, the modern light and the modern dark theme (ui_theme_mode light/dark).
# Checks on the head: the page is light in the light theme and dark in the dark one and in the classic look
# (median luma of the WebView in the raw frame), the charts of the program are there on both sides, the device
# list of the editor opens as the menu of the page in the modern look (qz-modern-select.js), not as the system
# list of Android. Base: the luma and the charts only told - the frames are the "before" of the PR picture.
# Not here (the phone): a theme change while the page is open (qzthemechange) - the emulator restarts the app
# for every qz.conf change.

. .github/lib.sh
. .github/qz.sh

QZDIR=/sdcard/Documents/QZ

# app_uid: the uid of the installed app - the owner of its data folder; empty without the app (T-514)
app_uid() {
  adb shell "su 0 stat -c %u /data/data/$PKG" < /dev/null 2>/dev/null | tr -d '\r'
}

# wipe_files: Documents/QZ of the previous side removed by the app uid while it is installed - files of an
# uninstalled app belong to another uid and bring the "previous installation" box (T-514, run 43015224696)
wipe_files() {
  local uid
  uid=$(app_uid)
  if [ -n "$uid" ]; then
    adb shell am force-stop "$PKG" < /dev/null > /dev/null 2>&1
    adb shell "su $uid,$uid,9997 sh -c 'rm -rf $QZDIR'" < /dev/null >> "$STEPLOG" 2>&1
  fi
  adb uninstall "$PKG" < /dev/null > /dev/null 2>&1
  if adb shell "ls -d $QZDIR" < /dev/null > /dev/null 2>&1; then
    adb shell "su 0 ls -lnR $QZDIR" < /dev/null >> "$STEPLOG" 2>&1
    proves_nothing "$QZDIR left from the previous side (uid ${uid:-none})"
  fi
}

# put_program <file> <xml body>: a program file of the user in Documents/QZ/training, by the app uid
put_program() {
  local f=$1 uid
  uid=$(app_uid)
  printf '%s\n' "$2" > "$f"
  adb push "$f" "/data/local/tmp/$f" < /dev/null > /dev/null 2>&1
  adb shell "su $uid,$uid,9997 sh -c 'mkdir -p $QZDIR/training && cp /data/local/tmp/$f $QZDIR/training/$f'" < /dev/null >> "$STEPLOG" 2>&1
  adb shell "ls -l $QZDIR/training/$f" < /dev/null >> "$STEPLOG" 2>&1 || proves_nothing "$f not in the training folder"
}

# charts_of <shot>: the number of charts - android.widget.Image nodes (canvas) inside the WebView of the frame
# dump; "none" without a WebView
charts_of() {
  "$EMU_PY" - "dumps/$1.xml" << 'EOF'
import sys
import xml.etree.ElementTree as ET
try:
    root = ET.parse(sys.argv[1]).getroot()
except Exception:
    print("none")
    sys.exit(0)
views = [n for n in root.iter('node') if n.get('class') == 'android.webkit.WebView']
if not views:
    print("none")
    sys.exit(0)
print(sum(1 for n in views[0].iter('node') if n.get('class') == 'android.widget.Image'))
EOF
}

# want_charts <shot> <n> <what>: exactly n charts on both sides (master has the charts of T-187 too)
want_charts() {
  local s=$1 n=$2 what=$3 got
  got=$(charts_of "$s")
  if [ "$got" = "$n" ]; then
    say "check $s: $what: $got chart(s): OK"
  else
    fail "check $s: $what: $got chart(s), $n expected"
  fi
}

# luma_of <shot>: the median luma (0-255) of the WebView of the dump in the raw frame <shot>.raw, sampled
# every 8th pixel; "none" without a WebView or a frame
luma_of() {
  "$EMU_PY" - "$EMU_GH" "$1.raw" "dumps/$1.xml" << 'EOF'
import sys
import xml.etree.ElementTree as ET
sys.path.insert(0, sys.argv[1])
import emu_frame
raw = emu_frame.read_raw(sys.argv[2])
try:
    root = ET.parse(sys.argv[3]).getroot()
except Exception:
    root = None
views = [n for n in root.iter('node') if n.get('class') == 'android.webkit.WebView'] if root is not None else []
if raw is None or not views:
    print("none")
    sys.exit(0)
w, h, off, d = raw
x1, y1, x2, y2 = emu_frame.parse_bounds(views[0].get('bounds'))
values = []
for y in range(max(y1, 0), min(y2, h), 8):
    row = off + y * w * 4
    for x in range(max(x1, 0), min(x2, w), 8):
        p = row + x * 4
        values.append((299 * d[p] + 587 * d[p + 1] + 114 * d[p + 2]) // 1000)
import statistics
print(int(statistics.median(values)) if values else "none")
EOF
}

# want_tone <shot> <light|dark>: head - the page of the WebView light (median luma above 150) or dark (below
# 90); base - told
want_tone() {
  local s=$1 tone=$2 l
  frame "$s.raw" || { near frame "$s: no raw frame"; return 0; }
  l=$(luma_of "$s")
  say "$s: page luma $l"
  if [ "${s:0:1}" = b ]; then
    say "before $s: page luma $l"
    return 0
  fi
  if [ "$l" = none ]; then
    fail "check $s: no WebView or frame for the page tone"
  elif [ "$tone" = light ] && [ "$l" -gt 150 ]; then
    say "check $s: a light page (luma $l): OK"
  elif [ "$tone" = dark ] && [ "$l" -lt 90 ]; then
    say "check $s: a dark page (luma $l): OK"
  else
    fail "check $s: a $tone page expected, luma $l"
  fi
}

# conf_of <look>: the keys of the look - c classic, l modern light, d modern dark
conf_of() {
  case $1 in
    c) echo "ui_modern=false" ;;
    l) echo "ui_modern=true ui_theme_mode=light" ;;
    d) echo "ui_modern=true ui_theme_mode=dark" ;;
  esac
}

# tone_of <look>: the tone the page has to have
tone_of() { [ "$1" = l ] && echo light || echo dark; }

# open_program <case> <look> <name>: the program from the list. Modern cards are named; the classic rows have
# no name - the first row, 170 px below the filter field (T-495 scenario)
open_program() {
  local c=$1 look=$2 name=$3
  open_drawer '^Open Train Program$' && tap_ui '^Open Train Program$' '^Other folders$' || return 1
  emu_sleep 3
  dump
  if [ "$look" != c ] && find_ui "^$name\$"; then
    tap_ui "^$name\$" '^Start Workout$' 20
    return
  fi
  if ! find_ui '^Search \(recursive\)\.\.\.$'; then
    fail "$c: the filter field not on the screen"
    return 1
  fi
  set -- $EMU_AT
  local x=720 y
  if [ "$look" = c ]; then y=$(( $8 + 170 )); else y=$(( $8 + 134 )); fi
  say "tap the program row 1 ($name) at $x $y"
  adb shell input tap "$x" "$y" < /dev/null > /dev/null 2>&1
  if wait_ui '^Start Workout$' 20; then
    say "outcome 'program $name': ok"
  else
    say "outcome 'program $name': no-effect"
    fail "$c: the preview of $name did not open"
    return 1
  fi
}

# preview <side> <look>: the program A1spdinc (speed and incline - two charts) in the preview
preview() {
  local side=$1 look=$2 c="$1p$2"
  start_case "$c" $(conf_of "$look") fakedevice_treadmill=true android_documents_folder=true || return 1
  # A1: sorts before the built-in programs - row 1 of the classic list
  put_program A1spdinc.xml '<?xml version="1.0" encoding="UTF-8"?>
<rows>
<row duration="00:05:00" speed="9.5" inclination="1.5"/>
<row duration="00:05:00" speed="11" inclination="3"/>
</rows>'
  if open_program "$c" "$look" A1spdinc; then
    emu_sleep 5
    still
    shot "$c-1-preview"
    want_charts "$c-1-preview" 2 'speed and incline: a chart each'
    want_tone "$c-1-preview" "$(tone_of "$look")"
  fi
  back_to "$HOME_RX" 20
}

# menu_is_page <shot>: the open device list is the menu of the page - its item "Jump Rope" is a node of the
# WebView, not a CheckedTextView of the system list dialog
menu_is_page() {
  "$EMU_PY" - "dumps/$1.xml" << 'EOF'
import sys
import xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
items = [n for n in root.iter('node') if n.get('text') == 'Jump Rope' or n.get('content-desc') == 'Jump Rope']
if not items:
    print("none")
elif any(n.get('class') == 'android.widget.CheckedTextView' for n in items):
    print("system")
else:
    print("page")
EOF
}

# editor <side> <look>: the workout editor - New makes an interval for the treadmill of the app (speed 9.5,
# incline 1.0: two charts, T-187 scenario); the top of the page, the chart card, and in the modern look the
# device list open
editor() {
  local side=$1 look=$2 c="$1e$2" m
  start_case "$c" $(conf_of "$look") fakedevice_treadmill=true android_documents_folder=true || return 1
  open_drawer '^Workout Editor$' && tap_ui '^Workout Editor$' '^Add Interval$' 40 || return 1
  emu_sleep 3
  tap_ui '^New$' '^Add Interval$' 20
  emu_sleep 3
  still
  shot "$c-2-editor"
  want_tone "$c-2-editor" "$(tone_of "$look")"
  if scroll_to '^Workout Preview$' 6; then
    still
    shot "$c-3-chart"
    want_charts "$c-3-chart" 2 'editor, a new treadmill interval: speed and incline, a chart each'
  else
    fail "$c: the chart card of the editor not reached"
  fi
  if [ "$look" != c ]; then
    scroll_top
    dump
    if find_ui '^Treadmill$' --first; then
      set -- $EMU_AT
      say "tap the device list at $1 $2"
      adb shell input tap "$1" "$2" < /dev/null > /dev/null 2>&1
      emu_sleep 2
      still
      shot "$c-4-menu"
      m=$(menu_is_page "$c-4-menu")
      if [ "$side" = b ]; then
        say "before $c-4-menu: the device list is '$m'"
      elif [ "$m" = page ]; then
        say "check $c-4-menu: the device list is the menu of the page: OK"
      else
        fail "check $c-4-menu: the device list is '$m', the menu of the page expected"
      fi
    else
      fail "$c: the device list (Treadmill) not on the screen"
    fi
  fi
  back_to "$HOME_RX" 20
}

emu_init
logcat_start

for side in b h; do
  if [ "$side" = b ]; then apk=apk-base/android-debug.apk; else apk=apk-head/android-debug.apk; fi
  side_on $side "$apk" || continue
  say "== $side: start"
  wipe_files
  install_apk "$apk"
  for look in c l d; do
    preview $side $look
    editor $side $look
  done
done

finish
