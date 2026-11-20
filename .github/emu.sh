#!/bin/bash
# Test only (T-633): the map page follows Maps Type without a restart of QZ, and the 2D / 3D switch in the
# toolbar of the map page (modern look).
# Base (b): origin/master - GoogleMap.qml chooses googlemaps/ (3D) or maps2d/ (2D) once, when the page is
# created, and keeps it in its Loader (main.qml googleMapUI) for the whole run. Head (h): the PR - the page is
# chosen again from the stored settings when the map is shown (StackView.onActivating), and the toolbar of the
# modern look has two segments 2D | 3D on the map page (GoogleMap.setMapsType).
# Which page loaded: the QZ web server logs each request, "Path" "maps2d/maps.htm" (webserverinfosender.cpp:158,
# with log_debug) - the same line on both sides.
# Case <side>m - modern look, light, maps_type=3D, the fake bike, a GPX program running:
#   1. menu -> Open GPX -> Box Hill -> Open -> Pause -> Start (iOS scenario of T-604), the map: googlemaps/ requested
#      (both sides);
#   2. head: the segment 2D in the toolbar - maps2d/ requested, maps_type=2D stored; 3D - googlemaps/ requested
#      again, maps_type=3D stored; base: the map page dumped (its Back), no 2D segment;
#   3. back home, Settings -> Maps -> Maps Type 2D -> OK, back home, the map again: head - maps2d/ requested,
#      base - not (the defect: the 3D page kept).
. .github/lib.sh
. .github/qz.sh

QZDIR=/sdcard/Documents/QZ
ROUTE='Box Hill'

app_uid() {
  adb shell "su 0 stat -c %u /data/data/$PKG" < /dev/null 2>/dev/null | tr -d '\r'
}

# wipe_files: Documents/QZ of the previous side removed by the app uid while it is installed - files of an
# uninstalled app belong to another uid and bring the "previous installation" box on the GPX page (T-514,
# run 43015224696; from test/t529-emu)
wipe_files() {
  local uid
  uid=$(app_uid)
  if [ -n "$uid" ]; then
    adb shell am force-stop "$PKG" < /dev/null > /dev/null 2>&1
    adb shell "su $uid,$uid,9997 sh -c 'rm -rf $QZDIR'" < /dev/null >> "$STEPLOG" 2>&1
  fi
  adb uninstall "$PKG" < /dev/null > /dev/null 2>&1
  if adb shell "ls -d $QZDIR" < /dev/null > /dev/null 2>&1; then
    say "wipe: $QZDIR still there - delete through MediaProvider"
    adb shell "su 0 content delete --uri content://media/external/file --where \"_data LIKE '$QZDIR/%' OR _data LIKE '/storage/emulated/0/Documents/QZ/%'\"" \
      < /dev/null >> "$STEPLOG" 2>&1
    adb shell "su 0 rm -rf /storage/emulated/0/Documents/QZ" < /dev/null >> "$STEPLOG" 2>&1
  fi
  if adb shell "ls -d $QZDIR" < /dev/null > /dev/null 2>&1; then
    adb shell "su 0 ls -lnR $QZDIR" < /dev/null >> "$STEPLOG" 2>&1
    proves_nothing "$QZDIR left from the previous side (uid ${uid:-none})"
  fi
}

# the restore question on the GPX page of a fresh install answered No (from test/t529-emu)
QUESTION_RX='(?s).*previous installation.*'
no_restore() {
  if ! wait_ui "$QUESTION_RX" 15 --any; then
    near question "$1: no restore question on the GPX page"
    return 0
  fi
  if find_ui '^&?No$'; then
    set -- "$1" $EMU_AT
    say "restore question: No at $2 $3"
    adb shell input tap "$2" "$3" < /dev/null > /dev/null 2>&1
  else
    fail "$1: the restore question without a No ($EMU_WHY)"
    return 1
  fi
  if wait_gone "$QUESTION_RX" 15; then
    say "outcome 'No': the question closed"
  else
    fail "$1: the restore question still there after No"
    return 1
  fi
}

log_lines() { wc -l < full_logcat.txt | tr -d ' '; }

# requested <page> <from line> [seconds]: 0 when the QZ web server logged a request of <page>/maps.htm after
# <from> (within [seconds], 20)
requested() {
  local page=$1 from=$2 secs=${3:-20} i
  for i in $(seq 1 "$secs"); do
    tail -n +"$from" full_logcat.txt | grep -a -q -F "\"Path\" \"$page/maps.htm\"" && return 0
    emu_sleep 1
  done
  return 1
}

# stored: maps_type of qz.conf now (run-as, the file of the app)
stored() {
  adb shell "run-as $PKG cat '$CONF'" < /dev/null 2>/dev/null | tr -d '\r' | grep '^maps_type=' | head -1
}

# map_open <shot> <from line>: the map button of the home page (named Map in the modern look) - the page with the
# back arrow; the coordinate line of loadMaps after <from>
map_open() {
  local s=$1 from=$2 i
  if ! tap_ui '^Map$' '^Back$' 30; then
    if tail -n +"$from" full_logcat.txt | grep -a -q 'coordinate is NOT valid for map'; then
      fail "$s: loadMaps - coordinate is NOT valid for map (the program sent no position yet)"
    else
      fail "$s: the map page did not open"
    fi
    return 1
  fi
  # the beacon of the log: loadMaps writes this line (main.qml) - without it "no request" below proves nothing
  for i in 1 2 3 4 5; do
    tail -n +"$from" full_logcat.txt | grep -a -q -F 'coordinate is valid for map' && return 0
    emu_sleep 1
  done
  fail "$s: no 'coordinate is valid for map' in the log after line $from - the log of QZ is silent"
  return 1
}

# expect_page <check> <page> <from line>: the request of <page>/maps.htm after <from> - OK, else a failure
expect_page() {
  if requested "$2" "$3" 25; then
    say "check $1: $2/maps.htm requested: OK"
  else
    fail "check $1: no request of $2/maps.htm after line $3"
  fi
}

# expect_no_page <check> <page> <from line>: no request of <page>/maps.htm after <from> in 25 s - OK (the defect
# of the base), else a failure (the base did reload: the scenario does not show what it says)
expect_no_page() {
  if requested "$2" "$3" 25; then
    fail "check $1: $2/maps.htm requested - the base did reload the page"
  else
    say "check $1: no request of $2/maps.htm in 25 s (the old page kept): OK"
  fi
}

# segment <name>: the toolbar segment 2D or 3D tapped (the map page stays: its Back is the landing)
segment() {
  tap_ui "^$1\$" '^Back$' 20
}

# settings_2d <case>: Settings -> Maps -> Maps Type 2D -> OK (modern settings page of master: the section
# Maps of settings.qml, the row label, its UiComboBox showing 3D and the OK of the row)
settings_2d() {
  local c=$1 lab top
  settings_open || return 1
  # the last section but one of the page: more swipes than bring_in in tap_ui makes
  scroll_to '^Maps.*' 25 --first || return 1
  tap_ui '^Maps.*' '^Maps Type:$' --first --land-below || return 1
  bring_in '^Maps Type:$' || { fail "$c: 'Maps Type:' not on the screen ($EMU_WHY)"; return 1; }
  dump
  lab=$(uifind ui.xml '^Maps Type:$' 2>/dev/null) || { fail "$c: no 'Maps Type:' in the dump"; return 1; }
  set -- $lab
  # the list and the OK of the row lie 59-60 px above the top of the label (RowLayout, dump of t550):
  # 120 px up, below the section header, where there is neither 3D nor OK
  top=$(( $6 - 120 ))
  shot "$c-3-maps-type"
  # the list of the row: 3D shown, 2D comes with the list
  tap_ui '^3D$' '^2D$' --below "$top" --first || return 1
  shot "$c-3-list"
  # the list opens with the current item (3D) over the field: 2D lies above the row (run 44776058469,
  # dump bm-3-list: 2D at y 1985, the label at 2282) - no --below; the one 2D on the page
  tap_ui '^2D$' '^Maps Type:$' || return 1
  emu_sleep 1
  # the OK of the row: the first OK below the top of the row
  tap_ui '^OK$' '^Maps Type:$' --below "$top" --first || return 1
  emu_sleep 2
  shot "$c-3-saved"
}

# modern <case>
modern() {
  local c=$1 from st
  start_case "$c" ui_modern=true ui_theme_mode=light maps_type=3D applewatch_fakedevice=true \
    bluetooth_lastdevice_name=TestBike continuous_moving=true || return 1
  # 1. a GPX program running, the map in 3D
  say "== $c: GPX"
  open_drawer '^Open GPX$' && tap_ui '^Open GPX$' "^$ROUTE\$" 60 && no_restore "$c" || return 1
  shot "$c-1-gpx"
  tap_ui '^Open$' '^Map$' 30 || return 1
  # a GPX opened during a running session is not started; Pause then Start starts it (ios_t604.py, T-604)
  tap_ui '^Pause$' '^Start$' && tap_ui '^Start$' '^Pause$' || return 1
  # the first ticks of the program: its GEO position (trainprogram.cpp, ticks == 1)
  emu_sleep 20
  from=$(log_lines)
  map_open "$c-1-map" "$from" || return 1
  expect_page "$c-1-3d" googlemaps "$from"
  emu_sleep 8
  shot "$c-1-map-3d"
  # 2. the toolbar switch
  if [ "$SIDE" = h ]; then
    from=$(log_lines)
    if segment 2D; then
      expect_page "$c-2-switch-2d" maps2d "$from"
      st=$(stored)
      if [ "$st" = "maps_type=2D" ]; then
        say "check $c-2-stored-2d: $st: OK"
      else
        fail "check $c-2-stored-2d: qz.conf has '${st:-no maps_type}' after the 2D segment"
      fi
      emu_sleep 8
      shot "$c-2-map-2d"
      from=$(log_lines)
      if segment 3D; then
        # the server of QZ sends no cache headers: a new navigation reaches it (t596: workouteditor 3 times)
        expect_page "$c-2-switch-3d" googlemaps "$from"
        st=$(stored)
        if [ "$st" = "maps_type=3D" ]; then
          say "check $c-2-stored-3d: $st: OK"
        else
          fail "check $c-2-stored-3d: qz.conf has '${st:-no maps_type}' after the 3D segment"
        fi
        emu_sleep 5
        shot "$c-2-map-3d-again"
      else
        fail "check $c-2-switch-3d: the 3D segment not tapped"
      fi
    else
      fail "check $c-2-switch-2d: no 2D segment in the toolbar of the map page"
    fi
  else
    # the beacon: a dump of the map page (its Back) - else "no 2D" proves nothing
    if ! dump; then
      fail "check $c-2-no-switch: no dump of the map page"
    elif ! find_ui '^Back$'; then
      fail "check $c-2-no-switch: no Back in the dump - not the map page"
    elif find_ui '^2D$' --any; then
      fail "check $c-2-no-switch: a 2D control on the map page of the base"
    else
      say "check $c-2-no-switch: no 2D segment on the base: OK"
    fi
  fi
  # 3. Maps Type changed in the settings, the map shown again without a restart
  back_to "$HOME_RX" 20 || return 1
  if settings_2d "$c"; then
    back_to "$HOME_RX" 20 || return 1
    st=$(stored)
    if [ "$st" = "maps_type=2D" ]; then
      say "check $c-3-stored: $st after the settings page closed: OK"
    else
      fail "check $c-3-stored: qz.conf has '${st:-no maps_type}' after Maps Type 2D - OK"
    fi
    from=$(log_lines)
    map_open "$c-4-map" "$from" || return 1
    if [ "$SIDE" = h ]; then
      expect_page "$c-4-settings-2d" maps2d "$from"
    else
      expect_no_page "$c-4-settings-2d" maps2d "$from"
    fi
    emu_sleep 8
    shot "$c-4-map"
    back_to "$HOME_RX" 20
  else
    fail "$c: Maps Type not set to 2D in the settings"
  fi
  return 0
}

emu_init
logcat_start

for SIDE in b h; do
  case $SIDE in
    b) apk=apk-base/android-debug.apk ;;
    h) apk=apk-head/android-debug.apk ;;
  esac
  side_on "$SIDE" "$apk" || continue
  say "== $SIDE: start"
  wipe_files
  install_apk "$apk"
  modern "${SIDE}m"
done

logcat_stop
finish
