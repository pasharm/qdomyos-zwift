#!/bin/bash
# Test only (T-498, PR-5: settings sections of the modern look). Two APKs on one emulator:
# apk-base - origin/master of the same commit, apk-head - the PR. MODE=frames (default):
#  c-<side>: classic look with a fake treadmill - the settings page (closed, General Options open),
#            the tiles page (91 switch sections),
#            the settings folder (Load settings) and the profiles page - frames compared base against
#            head afterwards (the classic look must not change). The two list pages give their only
#            section the rest of the page for a list without a height of its own: the list must show
#            its files (made by the app with its Save buttons in the classic case);
#  m-head:   modern look of the PR: section cards, a nested section, the sticky copy of an open
#            section header while scrolling, the tiles page with a switch section (Speed) turned by
#            a tap on its row and back, the two list pages;
#  t-head:   the real TalkBack (image API 35) on the modern section headers: name, state said
#            (Collapsed / Expanded), double tap opens the section.
# MODE=timing: the settings and the tiles page opened 3 times per side and look; the builds carry a
# test only log line QZ-TIMING at the tap and at the end of the page creation - the deltas are put
# into steps.log (the classic look of head against base: the hidden parts of the modern look must
# not make the page slower).
PKG=org.cagnulen.qdomyoszwift
LOG_DEBUG=${LOG_DEBUG:-true}
MODE=${MODE:-frames}
STEPLOG=steps.log
CONF='files/.config/Roberto Viola/qDomyos-Zwift.conf'
: > $STEPLOG
mkdir -p dumps
FAILED=0
# Toolbar menu / back button by its place (Nexus 6, 3.5 px per dp): classic buttons have no names
MENU="84 168"
# Classic Load settings and Save settings on the settings page, the two rightmost buttons
LOAD="1187 168"
SAVE="1354 168"
DOCS=/sdcard/Documents/QZ

install_apk() {
  adb uninstall $PKG > /dev/null 2>&1 || true
  adb shell rm -rf $DOCS || true
  adb install "$1"
  adb shell pm path $PKG > /dev/null || { echo "!! $1 not installed - the run proves nothing" >> $STEPLOG; cat $STEPLOG; exit 1; }
  for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION BLUETOOTH_ADVERTISE BLUETOOTH_CONNECT BLUETOOTH_SCAN POST_NOTIFICATIONS; do
    adb shell pm grant $PKG android.permission.$p || true
  done
  adb shell appops set $PKG MANAGE_EXTERNAL_STORAGE allow || true
  for p in EXERCISE DISTANCE TOTAL_CALORIES_BURNED HEART_RATE POWER SPEED CYCLING_PEDALING_CADENCE ELEVATION_GAINED STEPS STEPS_CADENCE HEART_RATE_VARIABILITY; do
    adb shell pm grant $PKG android.permission.health.WRITE_$p || true
  done
  echo "== installed $1" >> $STEPLOG
}
adb shell settings put global hide_error_dialogs 1 || true

# put_conf <ui_modern>: fake treadmill (no wizard), the journal for the timing lines
put_conf() {
  printf '[General]\nlog_debug=%s\nui_modern=%s\nfakedevice_treadmill=true\n' "$LOG_DEBUG" "$1" > qz.conf
  adb push qz.conf /data/local/tmp/qz.conf
  adb shell "run-as $PKG mkdir -p 'files/.config/Roberto Viola' < /dev/null"
  adb shell "run-as $PKG cp /data/local/tmp/qz.conf '$CONF' < /dev/null"
  adb shell "run-as $PKG ls -l '$CONF' < /dev/null" >> $STEPLOG 2>&1 || { echo "!! qz.conf not written - the run proves nothing" >> $STEPLOG; cat $STEPLOG; exit 1; }
}
dump() {
  rm -f ui.xml
  timeout 25 adb shell uiautomator dump /sdcard/ui.xml < /dev/null > /dev/null 2>&1 || true
  adb pull /sdcard/ui.xml ui.xml > /dev/null 2>&1 || true
}
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
wait_ui() {
  local i
  for i in $(seq 1 $(( ${2:-30} / 3 ))); do
    dump
    [ -f ui.xml ] && python3 .github/uitap.py ui.xml "$1" > /dev/null && return 0
    sleep 2
  done
  return 1
}
HOME_RX='^Start$|^Stop$|^Pause$'
wait_home() {
  local i
  for i in 1 2 3 4; do
    ensure_app
    wait_ui "$HOME_RX" 30 && return 0
  done
  return 1
}
# expect <shot> 'regex' <what>: the dump of the shot has a control with that whole text or name
expect() {
  if [ -f dumps/$1.xml ] && python3 .github/uitap.py dumps/$1.xml "$2" > /dev/null; then
    echo "check $1: $3: OK" >> $STEPLOG
  else
    echo "!! check $1: $3: '$2' not in the dump" >> $STEPLOG
    FAILED=1
  fi
}
# start_case <name> <ui_modern>
start_case() {
  echo "== $1: start (ui_modern=$2)" >> $STEPLOG
  adb shell am force-stop $PKG || true
  sleep 2
  put_conf "$2"
  adb shell am start -n $PKG/$PKG.CustomQtActivity
  if ! wait_home; then
    echo "!! $1: home page not shown in 120 s" >> $STEPLOG
    shot $1-0-no-home
    FAILED=1
    return 1
  fi
  echo "pid $1 $(adb shell pidof $PKG | tr -d '\r')" >> $STEPLOG
  sleep 10
  dump
  if [ -f ui.xml ] && xy=$(python3 .github/uitap.py ui.xml '^Later$'); then
    echo "tap Later at $xy" >> $STEPLOG
    adb shell input tap $xy || true
    sleep 2
  fi
  return 0
}
# open_drawer 'regex of an entry': menu button (by its place in both looks), then the entry shows
open_drawer() {
  local i
  for i in 1 2 3; do
    ensure_app
    echo "tap menu $MENU" >> $STEPLOG
    adb shell input tap $MENU || true
    sleep 3
    if wait_ui "$1" 9; then
      sleep 1
      echo "drawer open ('$1' shown)" >> $STEPLOG
      return 0
    fi
    adb shell input keyevent KEYCODE_BACK || true
    sleep 2
  done
  echo "!! drawer did not open ('$1' not shown)" >> $STEPLOG
  FAILED=1
  return 1
}
# tap_ui 'regex' 'landing regex' [seconds]: a control (waited for), then the next screen shows its own control
tap_ui() {
  local xy=""
  if ! wait_ui "$1" 15; then
    echo "!! '$1': NOT FOUND" >> $STEPLOG
    FAILED=1
    return 1
  fi
  xy=$(python3 .github/uitap.py ui.xml "$1")
  echo "tap '$1': at $xy" >> $STEPLOG
  adb shell input tap $xy || true
  if wait_ui "$2" ${3:-30}; then
    echo "after '$1': '$2' shown" >> $STEPLOG
    sleep 2
    return 0
  fi
  echo "!! after '$1': '$2' not shown" >> $STEPLOG
  FAILED=1
  return 1
}
# scroll_to 'regex': swipe the page up until the control is on the screen, above the navigation bar
scroll_to() {
  local i xy y last=""
  for i in $(seq 1 ${2:-25}); do
    dump
    if [ -f ui.xml ] && xy=$(python3 .github/uitap.py ui.xml "$1"); then
      y=${xy#* }
      [ "$y" -lt 2000 ] && { echo "scrolled to '$1' ($i): at $xy" >> $STEPLOG; return 0; }
      # the end of the page: the control did not move since the last swipe, above the navigation bar
      [ "$xy" = "$last" ] && [ "$y" -lt 2420 ] && { echo "scrolled to '$1' ($i, end of page): at $xy" >> $STEPLOG; return 0; }
      last=$xy
    fi
    # by the left edge: the controls of an open section in the middle took the swipe
    adb shell input swipe ${3:-150} 1900 ${3:-150} 900 400 || true
    sleep 1
  done
  echo "!! '$1' not reached by scrolling" >> $STEPLOG
  shot not-reached-$(date +%s)
  FAILED=1
  return 1
}
# tap_dot <case> <y from>: the classic StaticAccordionElement header (a Text, not in the dump) found by
# its grey dot (x 16..24 dp) on the raw frame below <y from>, tapped in the middle of the row
tap_dot() {
  local y
  adb exec-out screencap > raw.bin
  y=$(python3 - raw.bin $2 << 'EOF'
import sys
d = open(sys.argv[1], 'rb').read()
w = int.from_bytes(d[0:4], 'little'); h = int.from_bytes(d[4:8], 'little')
off = len(d) - w * h * 4
ys = []
for y in range(int(sys.argv[2]), h - 140):
    row = off + y * w * 4
    hit = False
    for x in range(40, 110):
        r, g, b = d[row + x * 4], d[row + x * 4 + 1], d[row + x * 4 + 2]
        if r > 120 and abs(r - g) < 12 and abs(r - b) < 12:
            hit = True; break
    if hit:
        ys.append(y)
    elif ys:
        break
if 15 <= len(ys) <= 45:
    print((ys[0] + ys[-1]) // 2)
EOF
)
  if [ -n "$y" ]; then
    echo "tap_dot $1: header dot at y $y, tap 400 $y" >> $STEPLOG
    adb shell input tap 400 $y || true
  else
    echo "!! tap_dot $1: header dot not found below $2" >> $STEPLOG; FAILED=1
  fi
}
# close_ok <what>: the confirmation box of a save ("Profile Saved" and the like) closed by its OK
close_ok() {
  local xy
  dump
  if [ -f ui.xml ] && xy=$(python3 .github/uitap.py ui.xml '^OK$'); then
    echo "close_ok $1: OK at $xy" >> $STEPLOG
    adb shell input tap $xy || true
    sleep 2
  else
    echo "close_ok $1: no box" >> $STEPLOG
  fi
}
# checked_of <xml> 'name': the checked attribute of the first node with that content-desc or text
checked_of() {
  python3 - "$1" "$2" << 'EOF'
import sys, xml.etree.ElementTree as ET
for n in ET.parse(sys.argv[1]).iter('node'):
    if sys.argv[2] in (n.get('content-desc'), n.get('text')) and n.get('bounds') != '[0,0][0,0]':
        print(n.get('checked')); break
EOF
}
# count_top <xml> 'name': nodes with that name whose top lies in the upper part of the screen
count_top() {
  python3 - "$1" "$2" << 'EOF'
import sys, xml.etree.ElementTree as ET
c = 0
for n in ET.parse(sys.argv[1]).iter('node'):
    if sys.argv[2] in (n.get('content-desc'), n.get('text')):
        b = n.get('bounds').replace('][', ',').strip('[]').split(',')
        if b != ['0', '0', '0', '0'] and int(b[1]) < 600:
            c += 1
print(c)
EOF
}

adb logcat -c || true
adb logcat -v threadtime -b main,system,crash > full_logcat.txt 2>/dev/null &
LOGCAT_PID=$!
adb shell settings put system accelerometer_rotation 0 || true
adb shell settings put system user_rotation 0 || true
echo "== API $(adb shell getprop ro.build.version.sdk | tr -d '\r') mode $MODE" >> $STEPLOG

# settings_open <modern>: the settings page from the drawer
settings_open() {
  open_drawer '^Settings$' || return 1
  tap_ui '^Settings$' '^General Options$'
}
# back_to <regex>: the back arrow of the app (menu place in the classic look, "Back" in the modern)
back_to() {
  local i xy
  for i in 1 2 3; do
    dump
    if [ -f ui.xml ] && xy=$(python3 .github/uitap.py ui.xml '^Back$'); then
      adb shell input tap $xy || true
    else
      adb shell input tap $MENU || true
    fi
    wait_ui "$1" 15 && return 0
  done
  echo "!! back: '$1' not shown" >> $STEPLOG
  FAILED=1
  return 1
}

# exp_toggle <shot prefix>: Enable Virtual Device (a switch section inside the switch-less section
# Experimental Features, with a switch section inside it) off by a tap on its row, then on again
exp_toggle() {
  local p=$1 b a xy
  scroll_to '^Enable Virtual Device$' 8 720 || return 1
  shot $p-exp
  b=$(checked_of dumps/$p-exp.xml 'Enable Virtual Device')
  xy=$(python3 .github/uitap.py ui.xml '^Enable Virtual Device$')
  echo "tap Enable Virtual Device at $xy (checked $b)" >> $STEPLOG
  adb shell input tap $xy || true
  sleep 3
  shot $p-exp-off
  a=$(checked_of dumps/$p-exp-off.xml 'Enable Virtual Device')
  adb shell input tap $xy || true
  sleep 3
  shot $p-exp-on
  if [ -n "$b" ] && [ -n "$a" ] && [ "$b" != "$a" ] && [ "$(checked_of dumps/$p-exp-on.xml 'Enable Virtual Device')" = "$b" ]; then
    echo "check $p-exp-on: nested switch section off and on again ($b -> $a -> $b): OK" >> $STEPLOG
  else
    echo "!! check $p-exp-on: nested switch section: $b -> $a -> $(checked_of dumps/$p-exp-on.xml 'Enable Virtual Device')" >> $STEPLOG; FAILED=1
  fi
}

frames_side() {
  local side=$1 before after xy
  if start_case c-$side false; then
    if settings_open; then
      shot c-$side-1-settings
      tap_ui '^General Options$' '^App Language:$' && shot c-$side-2-general
      back_to "$HOME_RX"
    fi
    if settings_open; then
      # the same section as the modern frame m-head-2-ui-open, for the pair in the PR image
      tap_ui '^General UI Options$' '^Workout History Charts$' && shot c-$side-2b-ui-open
      back_to "$HOME_RX"
    fi
    if settings_open; then
      # Experimental Features: its classic header is a Text (not in the dump) - by its dot below Video
      if scroll_to '^Maps.*' 40 720; then
        xy=$(python3 .github/uitap.py ui.xml '^Maps.*')
        if [ "${xy#* }" -gt 1300 ]; then
          adb shell input swipe 150 1700 150 1100 600 || true
          sleep 2; dump; xy=$(python3 .github/uitap.py ui.xml '^Maps.*')
        fi
        echo "Maps header at $xy" >> $STEPLOG
        tap_dot c-$side-3 $(( ${xy#* } + 60 ))
        sleep 3
        if scroll_to '^Enable Virtual Device$' 8 720; then
          exp_toggle c-$side-3
        else
          echo "!! Experimental Features: 'Enable Virtual Device' not shown" >> $STEPLOG; FAILED=1
        fi
      fi
      back_to "$HOME_RX"
    fi
    if settings_open; then
      scroll_to '^Tiles Options$' && tap_ui '^Tiles Options$' '^Speed$' && { shot c-$side-4-tiles
        # the classic switch section (AccordionCheckElement): off by a tap, on again - base and head alike
        before=$(checked_of dumps/c-$side-4-tiles.xml 'Speed')
        xy=$(python3 .github/uitap.py ui.xml '^Speed$')
        echo "tap the classic row Speed at $xy (checked $before)" >> $STEPLOG
        adb shell input tap $xy || true
        sleep 3
        shot c-$side-4b-off
        after=$(checked_of dumps/c-$side-4b-off.xml 'Speed')
        if [ -n "$before" ] && [ -n "$after" ] && [ "$before" != "$after" ]; then
          echo "check c-$side-4b-off: classic switch section turned by a tap ($before -> $after): OK" >> $STEPLOG
        else
          echo "!! check c-$side-4b-off: classic switch section not turned ($before -> $after)" >> $STEPLOG; FAILED=1
        fi
        adb shell input tap $xy || true
        sleep 3
        shot c-$side-4c-on
        echo "record c-$side-4c-on: back to $(checked_of dumps/c-$side-4c-on.xml 'Speed') - compare the frames base/head" >> $STEPLOG
      }
      back_to '^General Options$'
      # Files for the lists made by the app itself (QZ sees in Documents only its own files on
      # API 30+): Save settings here, Save on the profiles page below; m-head reuses them
      echo "tap Save settings $SAVE" >> $STEPLOG
      adb shell input tap $SAVE || true
      sleep 3
      adb shell ls $DOCS/settings >> $STEPLOG 2>&1 || echo "!! Save settings made no file" >> $STEPLOG
      close_ok save-settings
      echo "tap Load settings $LOAD" >> $STEPLOG
      adb shell input tap $LOAD || true
      if wait_ui '^Other folders$' 30; then
        # its section starts closed: open it; the file names are plain Text, not in the dump - by the frame
        tap_dot c-$side-5 260
        sleep 2
        shot c-$side-5-settingslist
        echo "record c-$side-5-settingslist: the list of the saved settings - compare the frames base/head" >> $STEPLOG
        back_to '^General Options$'
      else
        echo "!! Load settings: settings folder page not shown" >> $STEPLOG; FAILED=1
      fi
      back_to "$HOME_RX"
    fi
    if open_drawer '^Profile: .*'; then
      tap_ui '^Profile: .*' '^Profile name$' && { sleep 2
        # landing on anything: wait_ui polls every 3 s, so less than 3 s would never look
        tap_ui '^Save$' '.*' 6; sleep 3
        close_ok save-profile
        adb shell ls $DOCS/profiles >> $STEPLOG 2>&1 || echo "!! Save made no profile" >> $STEPLOG
        # the classic page goes back to the home page after the OK of the save box: open it again
        if wait_ui "$HOME_RX" 9; then
          echo "after the save box: home page, open the profiles again" >> $STEPLOG
          open_drawer '^Profile: .*' && tap_ui '^Profile: .*' '^Profile name$' && sleep 2
        fi
        # the section of the profiles is open from the start (isOpen: true)
        shot c-$side-6-profiles
        expect c-$side-6-profiles '^Profile name$' 'the profiles page is on the screen'
        echo "record c-$side-6-profiles: the list (default) - compare the frames base/head" >> $STEPLOG; }
      back_to "$HOME_RX"
    fi
  fi
  adb shell am force-stop $PKG || true
}

modern_head() {
  local before after n
  if start_case m-head true; then
    if settings_open; then
      shot m-head-1-settings
      # Experimental Features: a section with no switch holding switch sections inside switch sections
      scroll_to '^Experimental Features$' 40 720 && tap_ui '^Experimental Features$' '.*' 5 && exp_toggle m-head-5
      back_to "$HOME_RX"
    fi
    if settings_open; then
      tap_ui '^General UI Options$' '^Workout History Charts$' && shot m-head-2-ui-open
      tap_ui '^Workout History Charts$' '.*' 5 && { sleep 2; shot m-head-3-nested; }
      # close the section by its header: the section inside goes away; then open it again
      xy=$(python3 .github/uitap.py ui.xml '^General UI Options$')
      echo "tap header General UI Options at $xy (close)" >> $STEPLOG
      adb shell input tap $xy || true
      sleep 3
      shot m-head-3c-closed
      if python3 .github/uitap.py dumps/m-head-3c-closed.xml '^Workout History Charts$' > /dev/null; then
        echo "!! check m-head-3c-closed: 'Workout History Charts' still shown after closing" >> $STEPLOG; FAILED=1
      else
        echo "check m-head-3c-closed: section closed, 'Workout History Charts' gone: OK" >> $STEPLOG
      fi
      tap_ui '^General UI Options$' '^Workout History Charts$' && shot m-head-3d-reopened
      adb shell input swipe 720 1700 720 1100 600 || true
      sleep 2
      adb shell input swipe 720 1700 720 1100 600 || true
      sleep 2
      shot m-head-4-sticky
      n=$(count_top dumps/m-head-4-sticky.xml 'General UI Options')
      echo "record m-head-4-sticky: 'General UI Options' nodes at the top: $n (the sticky copy over the page)" >> $STEPLOG
      back_to "$HOME_RX"
    fi
    if settings_open; then
      scroll_to '^Tiles Options$' && tap_ui '^Tiles Options$' '^Speed$' && { shot m-head-7-tiles
        before=$(checked_of dumps/m-head-7-tiles.xml 'Speed')
        xy=$(python3 .github/uitap.py ui.xml '^Speed$')
        echo "tap the row Speed at $xy (checked $before)" >> $STEPLOG
        adb shell input tap $xy || true
        sleep 3
        shot m-head-6-toggled
        after=$(checked_of dumps/m-head-6-toggled.xml 'Speed')
        if [ -n "$before" ] && [ -n "$after" ] && [ "$before" != "$after" ]; then
          echo "check m-head-6-toggled: switch section turned by a tap on its row ($before -> $after): OK" >> $STEPLOG
        else
          echo "!! check m-head-6-toggled: switch section not turned ($before -> $after)" >> $STEPLOG; FAILED=1
        fi
        adb shell input tap $xy || true
        sleep 3
        dump; cp ui.xml dumps/m-head-6b-back.xml 2>/dev/null
        echo "record: back to $(checked_of dumps/m-head-6b-back.xml 'Speed')" >> $STEPLOG
        # the switch itself (170 px in from the right end of the row), then the row: after a tap on
        # the switch it must follow the open state again, so the tap on the row moves it back
        sxy=$(python3 - dumps/m-head-6b-back.xml << 'EOF'
import sys, xml.etree.ElementTree as ET
for n in ET.parse(sys.argv[1]).iter('node'):
    if 'Speed' in (n.get('content-desc'), n.get('text')) and n.get('checkable') == 'true':
        b = n.get('bounds').replace('][', ',').strip('[]').split(',')
        print(int(b[2]) - 170, (int(b[1]) + int(b[3])) // 2); break
EOF
)
        if [ -n "$sxy" ]; then
          echo "tap the switch of Speed at $sxy" >> $STEPLOG
          adb shell input tap $sxy || true
          sleep 3
          shot m-head-6c-switch-off
          after=$(checked_of dumps/m-head-6c-switch-off.xml 'Speed')
          echo "tap the row Speed at $xy" >> $STEPLOG
          adb shell input tap $xy || true
          sleep 3
          shot m-head-6d-row-on
          before=$(checked_of dumps/m-head-6d-row-on.xml 'Speed')
          if [ "$after" = false ] && [ "$before" = true ]; then
            echo "check m-head-6d-row-on: switch tap off, then row tap on ($after -> $before): OK" >> $STEPLOG
          else
            echo "!! check m-head-6d-row-on: switch then row: $after -> $before (want false -> true)" >> $STEPLOG; FAILED=1
          fi
        else
          echo "!! switch of Speed: row bounds not found" >> $STEPLOG; FAILED=1
        fi
      }
      back_to '^General Options$'
      tap_ui '^Load settings$' '^Other folders$' && { sleep 2; shot m-head-8a-settingslist-before
        tap_ui '^Settings folder$' '.*' 3; sleep 2; shot m-head-8-settingslist
        echo "record m-head-8-settingslist: the list of the saved settings - by the frame" >> $STEPLOG
        back_to '^General Options$'; }
      back_to "$HOME_RX"
    fi
    if open_drawer '^Profile: .*'; then
      tap_ui '^Profile: .*' '^Profiles$' && { sleep 2; shot m-head-9-profiles
        echo "record m-head-9-profiles: the list (default) - by the frame; the section is open from the start" >> $STEPLOG; }
      back_to "$HOME_RX"
    fi
  fi
  adb shell am force-stop $PKG || true
}

# timing_case <case> <ui_modern>: settings and tiles REPS times each
timing_case() {
  local i
  start_case $1 $2 || return 1
  for i in $(seq 1 $REPS); do
    echo "-- $1 settings $i" >> $STEPLOG
    settings_open && back_to "$HOME_RX"
  done
  settings_open
  scroll_to '^Tiles Options$'
  for i in $(seq 1 $REPS); do
    echo "-- $1 tiles $i" >> $STEPLOG
    tap_ui '^Tiles Options$' '^Speed$' && back_to '^General Options$'
  done
  adb shell am force-stop $PKG || true
}

if [ "$MODE" = timing ]; then
  REPS=7
  # two rounds base, head, base, head: the order of the runs does not decide
  for round in 1 2; do
    for side in base head; do
      install_apk apk-$side/android-debug.apk
      timing_case tc-$side-$round false
    done
  done
  timing_case tm-head true
else
  for side in base head; do
    install_apk apk-$side/android-debug.apk
    frames_side $side
  done
  modern_head
fi

if [ "$MODE" != timing ]; then
# The real TalkBack on the modern section headers: recipe and traps -
# notes/talkback-in-emulator-2026-10-15.md of the work folder; the driver is the one of T-199.
# Last stage: adb root restarts adbd and ends the logcat above; uiautomator dumps switch TalkBack
# off, so from here on only the driver ("focused '<name>'", "said:" after each gesture) and screencap.
tb_check() {
  if grep -q -E "$1" drv/$2.txt; then
    echo "check $2: $3: OK" >> $STEPLOG
  else
    echo "!! check $2: $3: no /$1/ in drv/$2.txt" >> $STEPLOG
    FAILED=1
  fi
}
TBPKG=com.google.android.marvin.talkback
mkdir -p drv
SDK=${ANDROID_SDK_ROOT:-$ANDROID_HOME}
JAR=$SDK/platforms/android-35/android.jar
BT=$(ls -d $SDK/build-tools/*/ | sort -V | tail -n 1)
if [ "$(adb shell getprop ro.build.version.sdk | tr -d '\r')" != 35 ]; then
  echo "== talkback: skipped, not API 35" >> $STEPLOG
elif ! adb shell pm path $TBPKG > /dev/null 2>&1; then
  echo "!! talkback: $TBPKG not in the image" >> $STEPLOG; FAILED=1
elif ! { javac -source 8 -target 8 -bootclasspath $JAR -d drv .github/A11yDriver.java >> $STEPLOG 2>&1 \
         && ${BT}d8 --lib $JAR --output a11y.jar drv/*.class >> $STEPLOG 2>&1; }; then
  echo "!! talkback: driver not built" >> $STEPLOG; FAILED=1
elif start_case t-head true && settings_open; then
  adb push a11y.jar /data/local/tmp/a11y.jar > /dev/null
  drv() {
    local name=$1 args="" a
    shift
    for a in "$@"; do args="$args '$a'"; done
    echo "== drv $name:$args" >> $STEPLOG
    timeout 200 adb shell "CLASSPATH=/data/local/tmp/a11y.jar app_process / A11yDriver$args" > drv/$name.txt 2>&1 || true
    cat drv/$name.txt >> $STEPLOG
    sleep 2
  }
  kill $LOGCAT_PID 2>/dev/null || true
  wait $LOGCAT_PID 2>/dev/null || true
  adb shell am force-stop $TBPKG || true
  adb root >> $STEPLOG 2>&1 || true
  adb wait-for-device
  sleep 3
  adb logcat -v threadtime -b main,system,crash > tb_logcat.txt 2>/dev/null &
  LOGCAT_PID=$!
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
  adb shell dumpsys accessibility | grep -iE "Bound services|Enabled features" | head -n 4 >> $STEPLOG || true
  # the notification question of the suite comes over the app: bring QZ back
  adb shell am start -n $PKG/$PKG.CustomQtActivity >> $STEPLOG 2>&1 || true
  sleep 6
  adb shell screencap -p /sdcard/t-head-0-on.png && adb pull /sdcard/t-head-0-on.png >> $STEPLOG 2>&1 || true
  drv t-list --keep list
  # A section header by touch: its name and its state; a double tap opens it, the state is said again
  drv t-section --keep 'touch:General Options' 'sleep:1500' 'focused' 'dtap' 'sleep:2500' 'focused' 'find:App Language'
  adb shell screencap -p /sdcard/t-head-1-open.png && adb pull /sdcard/t-head-1-open.png >> $STEPLOG 2>&1 || true
  tb_check "^touch:General Options: focused 'General Options" t-section "talkback: the section header read by its name"
  # the speech overlay came empty in the runs of T-487 ("said []"): the state is recorded, not checked
  echo "== record t-section said: $(grep -E ': said ' drv/t-section.txt | tr '\n' ' ' | cut -c1-300)" >> $STEPLOG
  tb_check "^find:App Language.*visible=true" t-section "talkback: the double tap opened the section (its first setting visible)"
  # A switch row with TalkBack: close the section again, the tiles page, then Speed by touch and two
  # double taps - the checked state of the row from the tree (the speech is not recorded)
  drv t-switch --keep 'dtap' 'sleep:2500' 'touch:Tiles Options' 'sleep:1500' 'dtap' 'sleep:5000' \
    'touch:Speed' 'sleep:1500' 'focused' 'find:Speed' 'dtap' 'sleep:2500' 'find:Speed' 'dtap' 'sleep:2500' 'find:Speed'
  adb shell screencap -p /sdcard/t-head-2-switch.png && adb pull /sdcard/t-head-2-switch.png >> $STEPLOG 2>&1 || true
  tb_check "^touch:Speed: focused 'Speed" t-switch "talkback: the switch row read by its name"
  states=$(grep -E "^find:Speed: 'Speed' .*checkable=true" drv/t-switch.txt | sed 's/.* checked=\([a-z]*\).*/\1/' | tr '\n' ' ')
  if [ "$states" = "true false true " ]; then
    echo "check t-switch: talkback: double taps on the switch row turn it off and on ($states): OK" >> $STEPLOG
  else
    echo "!! check t-switch: talkback: switch row states '$states' (want true false true)" >> $STEPLOG; FAILED=1
  fi
  mkdir -p drv/shots
  adb pull /data/local/tmp/tbshots/. drv/shots >> $STEPLOG 2>&1 || true
  echo "== talkback off" >> $STEPLOG
  adb shell settings put secure touch_exploration_enabled 0 >> $STEPLOG 2>&1
  adb shell settings put secure enabled_accessibility_services null >> $STEPLOG 2>&1
  adb shell settings put secure accessibility_enabled 0 >> $STEPLOG 2>&1
  adb shell am force-stop $PKG || true
fi
fi

kill $LOGCAT_PID 2>/dev/null || true
wait $LOGCAT_PID 2>/dev/null || true
[ -f tb_logcat.txt ] && cat tb_logcat.txt >> full_logcat.txt
if [ "$MODE" = timing ]; then
  echo "== timing (ms from the tap to the end of the page creation, per process):" >> $STEPLOG
  python3 - full_logcat.txt >> $STEPLOG << 'EOF'
import sys
rows = {}
start = {}
for line in open(sys.argv[1], errors='replace'):
    i = line.find('QZ-TIMING ')
    if i < 0:
        continue
    f = line.split()
    pid = f[2] if len(f) > 2 else '?'
    w = line[i + 10:].split()
    if len(w) < 3:
        continue
    what, page, ms = w[0], w[1], w[-1]
    try:
        ms = int(ms)
    except ValueError:
        continue
    if what == 'push':
        start[(pid, page)] = ms
    elif what == 'done' and (pid, page) in start:
        rows.setdefault((pid, page), []).append(ms - start.pop((pid, page)))
if not rows:
    print('!! no QZ-TIMING pairs - the timing run proves nothing')
for (pid, page), v in sorted(rows.items()):
    print('pid %s %s: %s' % (pid, page, ' '.join(str(x) for x in v)))
EOF
  grep -q -E "^pid [0-9]+ (settings|tiles):" $STEPLOG || FAILED=1
fi
echo "== QML errors of the section files (for reading):" >> $STEPLOG
grep -a -E "(AccordionElement|AccordionCheckElement|StaticAccordionElement|NewPageElement|UiSectionHeader|UiStickyHeader|UiSettingFrames|settings|settings-tiles|profiles|SettingsList)\.qml.*(TypeError|ReferenceError|Error|Binding loop)" full_logcat.txt | sed 's/.*qDomyos-Zwift: //' | sort | uniq -c | head -n 30 >> $STEPLOG || true
echo "== ANR / crash in the whole log:" >> $STEPLOG
if grep -a -E "ANR in $PKG|Process: $PKG,|Fatal signal.*qdomyoszwift" full_logcat.txt >> $STEPLOG; then
  echo "!! check log: ANR or crash" >> $STEPLOG; FAILED=1
else
  echo "none" >> $STEPLOG
fi
grep -q -E "^check |^pid .*: [0-9]" $STEPLOG || { echo "!! no check ran: the run proves nothing" >> $STEPLOG; FAILED=1; }
cat $STEPLOG
exit $FAILED
