#!/bin/bash
# Test only (T-565, issue 5770): the real TalkBack (Google TalkBack 15, image API 35), on before QZ starts,
# on master (apk-base, run 43724446576, e5d634d73) and on PR 4645 with master merged (apk-head, 84bd54a02),
# classic look, fake treadmill. What the blind tester of issue 5770 met on master:
#   1. the header buttons are read by name (head; on master they have none);
#   2. the menu opens, the swipe goes over its entries and not the page under it, Settings and Workout
#      Editor open from it;
#   3. a settings field is read with its value (check_accessibility name-no-value: PR 4645 names the
#      fields without the value - by T-245 Qt 5.15 on Android then does not read it; the first head build
#      read "Player Weight" without 85, run 43737877684, so the head build now has the value in the name);
#   4. Workouts History: the recovery box ("Workout History", Yes/No) and the system folder picker -
#      a survey only (tree and speech), no check.
# The base side has no checks of its own but one of the detector: no "Main menu" in its tree (master has no
# name there), else the checks of the head side prove nothing.
. .github/lib.sh
. .github/qz.sh

DRV_WAIT_RX="^find:Speed: '"

# tb_start <case>: QZ stopped, TalkBack on, QZ started again - TalkBack is on before QZ starts (the tester's
# case; PR 5376 is about it). The home page is waited for by the driver: a dump would switch TalkBack off
tb_start() {
  local c=$1 i
  adb shell am force-stop "$PKG" < /dev/null > /dev/null 2>&1
  emu_sleep 2
  tb_on
  adb shell am start -n "$PKG/$PKG.CustomQtActivity" < /dev/null > /dev/null 2>&1
  for i in 1 2 3 4 5 6; do
    drv "$c-wait$i" --keep 'sleep:4000' 'find:Speed'
    grep -a -q -E "$DRV_WAIT_RX" "drv/$c-wait$i.txt" && return 0
    near tree "$c: no tile in the TalkBack tree, look $i"
  done
  fail "$c: the home page did not reach the TalkBack tree"
  # the frame without a dump (a dump would switch TalkBack off), then TalkBack off: the next case starts
  # with dumps, and a tap under touch exploration presses nothing
  adb exec-out screencap -p > "$c-no-tree.png" 2>> "$STEPLOG"
  tb_end "$c"
  return 1
}

# tb_end <case>: speech frames to tbshots/<case>, TalkBack off, QZ stopped
tb_end() {
  mkdir -p tbshots
  adb pull /data/local/tmp/tbshots "tbshots/$1" < /dev/null >> "$STEPLOG" 2>&1
  tb_off
  adb shell am force-stop "$PKG" < /dev/null > /dev/null 2>&1
  emu_sleep 3
}

# back_key: the system back (a key, not a gesture: TalkBack does not take it over)
back_key() {
  adb shell input keyevent KEYCODE_BACK < /dev/null > /dev/null 2>&1
  emu_sleep 3
}

# side_flow <b|h>: the cases of one side. A partial run names the warm-up too: cases "h-warm h-menu"
# (the warm-up is a start_case of its own, and without it the side stops)
side_flow() {
  local s=$1 c xy
  local -a open_menu
  # warm-up without TalkBack: the first-run boxes closed, weight 85 kg to hear in the field (case 3)
  start_case "${s}-warm" fakedevice_treadmill=true weight=85 || return 1
  shot "${s}-warm-home" now

  # The menu button: by name on head (main.qml:1392 "Main menu"), by place on master (no name, MENU of qz.sh).
  # An array: each step one argument of drv, a step with a space stays whole
  if [ "$s" = h ]; then
    open_menu=('touch:Main menu' 'dtap:Main menu')
  else
    open_menu=("touchat:${MENU// /,}" 'dtap')
  fi

  # 1. header and 2. menu -> Settings -> a field (3.)
  c=${s}-menu
  if case_on "$c" side_flow && tb_start "$c"; then
    drv "$c-home" --keep 'list' "${open_menu[@]}"
    drv "$c-swipe" --keep 'focused' 'swipe:right' 'swipe:right' 'swipe:right' 'swipe:right'
    drv "$c-settings" --keep 'touch:Settings' 'dtap:Settings' 'sleep:4000' 'find:General Options' \
      'touch:General Options' 'dtap:General Options' 'sleep:3000' 'list'
    # The field by its own place: touch:Player Weight would take the label before it, "Player Weight (kg)"
    # (settings.qml:2925-2930, a node of the tree; the field, settings.qml:2943, comes after it)
    # the name with the value (name-no-value fix, settings.qml) or without it (the first head build)
    xy=$(grep -a -m1 -E "^ *'Player Weight(: [0-9.]+)?' class=" "drv/$c-settings.txt" \
      | sed -E 's/.* bounds=\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\].*/\1 \2 \3 \4/')
    if [ -n "$xy" ]; then
      set -- $xy
      drv "$c-weight" --keep "touchat:$(( ($1 + $3) / 2 )),$(( ($2 + $4) / 2 ))"
    else
      : > "drv/$c-weight.txt"
      say "== $c: no node 'Player Weight' in the list of the open General Options"
    fi
    tb_end "$c"
    if [ "$s" = h ]; then
      # main.qml:1392, 1405, 1689 (lockTiles false at start, main.qml:158), 1717
      # list lines are indented by depth: "^ *'<name>'" is a node of the tree, not a step line
      tb_check "^ *'Main menu'" "$c-home" "$c: the menu button by name"
      tb_check "^ *'Floating window'" "$c-home" "$c: Floating window by name"
      tb_check "^ *'(Lock|Unlock) tiles'" "$c-home" "$c: the tile lock by name"
      tb_check "^ *'(Enable|Disable) auto resistance'" "$c-home" "$c: auto resistance by name"
      tb_check "^touch:Main menu: focused 'Main menu'" "$c-home" "$c: the menu button by touch"
      # main.qml:1960 the drawer, 2042 Settings: the swipe in the open menu reaches its entries
      tb_check "^swipe:right: focused '(Profile: |Settings|Workouts History|Swag Bag|Charts)" "$c-swipe" \
        "$c: the swipe goes over the menu entries"
      tb_check "^touch:Settings: focused 'Settings'" "$c-settings" "$c: Settings in the menu by touch"
      # AccordionElement.qml:72 the section header; no such node on the home page
      tb_check "^find:General Options: '" "$c-settings" "$c: Settings opened by a double tap"
      # name-no-value: Qt 5.15 on Android reads only the name, so the value is in it (weight=85 of the
      # warm-up; height 175 and gender Male are the defaults): a text field, a list
      tb_check "^touchat:[0-9,]+: focused 'Player Weight: 85' class=" "$c-weight" "$c: the weight field by touch, with its value"
      tb_check "^ *'Player Height: 175' class=" "$c-settings" "$c: a text field named with its value"
      tb_check "^ *'Gender: Male' class=" "$c-settings" "$c: a list named with its value"
    else
      # the detector: the tree is there (the tiles), and the menu button has no name on master (e5d634d73:1373)
      tb_check "^ *'Speed" "$c-home" "$c: the tree of master is read"
      if grep -a -q -E "^ *'Main menu'" "drv/$c-home.txt"; then
        fail "$c: 'Main menu' in the tree of master - the detector of the head checks is wrong"
      else
        say "check $c: no 'Main menu' on master (the detector): OK"
      fi
    fi
    # the "said" lines are empty on this image (the speech overlay is not in getWindows): the speech is on
    # the frames tbshots/<case>/*
    say "== $c: the focus after each gesture:"
    grep -a -h -E ": focused " drv/"$c"-home.txt drv/"$c"-swipe.txt drv/"$c"-settings.txt drv/"$c"-weight.txt >> "$STEPLOG" 2>&1
  fi

  # 2. menu -> Workout Editor
  c=${s}-editor
  if case_on "$c" side_flow && tb_start "$c"; then
    drv "$c-open" --keep "${open_menu[@]}" 'touch:Workout Editor' 'dtap:Workout Editor' 'sleep:5000' 'find:Back' 'list'
    tb_end "$c"
    if [ "$s" = h ]; then
      # main.qml:2088 the entry; main.qml:1392 the menu button is "Back" on a pushed page (its name only)
      tb_check "^touch:Workout Editor: focused 'Workout Editor'" "$c-open" "$c: Workout Editor in the menu by touch"
      tb_check "^find:Back: 'Back' class=" "$c-open" "$c: a page opened by a double tap (the menu button is Back)"
    fi
  fi

  # 4. menu -> Workouts History: the recovery box and the folder picker - survey
  c=${s}-history
  if case_on "$c" side_flow && tb_start "$c"; then
    drv "$c-open" --keep "${open_menu[@]}" 'touch:Workouts History' 'dtap:Workouts History' 'sleep:5000' 'list' \
      'touch:Yes' 'dtap:Yes' 'sleep:6000' 'focused' 'list' 'swipe:right' 'swipe:right' 'swipe:right'
    tb_end "$c"
    say "== $c: survey (no check): focus"
    grep -a -h -E ": focused |NOT " "drv/$c-open.txt" >> "$STEPLOG" 2>&1
  fi
  return 0
}

emu_init
[ "$EMU_API" -ge 34 ] || proves_nothing "T-565 on API $EMU_API: the driver injects TalkBack gestures from API 34"
# adb root restarts adbd and cuts the logcat: once, before the log (tb_on asks again - already root)
adb root >> "$STEPLOG" 2>&1
adb wait-for-device
emu_sleep 3
logcat_start
a11y_build || proves_nothing "no A11yDriver"

for side in b h; do
  if [ "$side" = b ]; then apk=apk-base/android-debug.apk; else apk=apk-head/android-debug.apk; fi
  [ -f "$apk" ] || { say "== $side: no APK ($apk), skipped"; continue; }
  say "== $side: start"
  adb uninstall "$PKG" < /dev/null > /dev/null 2>&1
  install_apk "$apk"
  side_flow "$side"
done

finish
