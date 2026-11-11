#!/bin/bash
# Test only (T-514): frames of the file lists of PR 6a-1 (Open Train Program with its preview, Open GPX,
# Load settings) on master (apk-base) and on the branch (apk-head), in the classic and the modern look.
# The classic frames of both sides must match (emu_frame.py diff); the modern ones are the new look - the
# branch cards carry names (Accessible.name), the rows of master and of the classic look have none in the dump.
. .github/lib.sh
. .github/qz.sh

QZDIR=/sdcard/Documents/QZ

# wipe: Documents/QZ of the previous side. A file left by an uninstalled app belongs to another uid, the new
# install does not see it and asks about "programs of a previous installation" (run 43015224696: the native
# box over the classic list, the modern list empty). Removed by the app uid while the app is still installed:
# MediaProvider forgets the files then. The shell may not remove them (run 43019114307), and after a removal
# by root MediaProvider kept them - the next app got "File exists" (run 43021054533)
wipe_files() {
  local uid
  uid=$(app_uid)
  if [ -n "$uid" ]; then
    # a running QZ writes there (run 43023667230: "Directory not empty")
    adb shell am force-stop "$PKG" < /dev/null > /dev/null 2>&1
    adb shell "su $uid,$uid,9997 sh -c 'rm -rf $QZDIR'" < /dev/null >> "$STEPLOG" 2>&1
  fi
  adb uninstall "$PKG" < /dev/null > /dev/null 2>&1
  if adb shell "ls -d $QZDIR" < /dev/null > /dev/null 2>&1; then
    adb shell "su 0 ls -lnR $QZDIR" < /dev/null >> "$STEPLOG" 2>&1
    proves_nothing "$QZDIR left from the previous side (uid ${uid:-none})"
  fi
}

# app_uid: the uid of the installed app - the owner of its data folder; empty without the app
# (run 43021054533: `cmd package list packages -U` gave 10205 for an app of uid 10209)
app_uid() {
  adb shell "su 0 stat -c %u /data/data/$PKG" < /dev/null 2>/dev/null | tr -d '\r'
}

# seed: a GPX route and a saved settings file, written as the app (run-as): from API 30 the app lists in
# Documents only its own files - the files pushed by the shell were not listed (run 43015224696)
seed_files() {
  printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
    '<gpx version="1.1" creator="t514" xmlns="http://www.topografix.com/GPX/1/1"><trk><name>Test route</name><trkseg>' \
    '<trkpt lat="45.4642" lon="9.1900"><ele>120</ele></trkpt>' \
    '<trkpt lat="45.4700" lon="9.2000"><ele>135</ele></trkpt>' \
    '<trkpt lat="45.4780" lon="9.2100"><ele>150</ele></trkpt>' \
    '</trkseg></trk></gpx>' > test-route.gpx
  printf '[General]\nftp=210\n' > saved-setup.qzs
  local uid as
  uid=$(app_uid)
  [ -n "$uid" ] || proves_nothing "seed: no uid of $PKG"
  # run-as is shut out of /sdcard from API 30 (check_emu_script run-as-shared); the app uid with the
  # external storage group 9997 writes there as the app
  as="su $uid,$uid,9997 sh -c"
  adb shell "$as 'mkdir -p $QZDIR/gpx $QZDIR/settings'" < /dev/null >> "$STEPLOG" 2>&1
  adb shell "$as 'cat > $QZDIR/gpx/test-route.gpx'" < test-route.gpx >> "$STEPLOG" 2>&1
  adb shell "$as 'cat > $QZDIR/settings/saved-setup.qzs'" < saved-setup.qzs >> "$STEPLOG" 2>&1
  adb shell "ls -ln $QZDIR/gpx $QZDIR/settings" < /dev/null >> "$STEPLOG" 2>&1
  if ! adb shell "ls $QZDIR/gpx/test-route.gpx $QZDIR/settings/saved-setup.qzs" < /dev/null > /dev/null 2>&1; then
    proves_nothing "seed: the files not written as the app (uid $uid)"
  fi
}

# snap <name>: the raw frame for the comparison of the sides, then the frame with its dumps. The raw one
# right before the PNG: taken after the dumps it differed from the other side in 820 rows where the PNGs
# differed only by one button (run 43025955339)
snap() {
  frame "raw-$1" || near frame "$1: no raw frame"
  shot "$1"
}

# webview_masks <dump>: the WebView rectangles as --mask options - the map tiles and the chart load from
# the network and in their own time; a WebView that moved still shows outside its mask
webview_masks() {
  grep -o 'class="android.webkit.WebView"[^>]*bounds="[^"]*"' "$1" 2>/dev/null \
    | sed -e 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]"/--mask \1,\2,\3,\4/'
}

# same_as_master <page>: the classic frame of the branch matches the one of master outside the WebViews
same_as_master() {
  local a=bc-$1 b=hc-$1 out masks
  if [ ! -s "raw-$a" ] || [ ! -s "raw-$b" ] || [ ! -s "dumps/$a.xml" ] || [ ! -s "dumps/$b.xml" ]; then
    fail "check classic-$1: same as master: no frame of one side"
    return 1
  fi
  masks="$(webview_masks "dumps/$a.xml") $(webview_masks "dumps/$b.xml")"
  # the classic GPX list scrolls a name longer than 30 characters (GPXList.qml of master: "Italy - Passo
  # dello Stelvio", the 5th row) - its row moves by itself; Nexus 6 1440x2560 of the CI image
  [ "$1" = 3-gpx ] && masks="$masks --mask 0,940,830,1100"
  # shellcheck disable=SC2086
  out=$("$EMU_PY" "$EMU_GH/emu_frame.py" diff "raw-$a" "raw-$b" --dumps "dumps/$a.xml" "dumps/$b.xml" \
        --rows "$EMU_ROWS" --tol 32 $masks 2>&1)
  case $? in
    0) say "check classic-$1: same as master: OK ($out)" ;;
    1) fail "check classic-$1: the branch differs from master: $out" ;;
    *) fail "check classic-$1: frames not compared: $out" ;;
  esac
}

# first_program <case>: open the first program of the list. The branch cards in the modern look have a
# name; the rows of master and of the classic look have none - the first row below the filter field
first_program() {
  if [ "$1" = hm ]; then
    tap_ui '^Easy intervals$' '^Start Workout$' 20
    return
  fi
  local x y
  dump
  if ! find_ui '^Search \(recursive\)\.\.\.$'; then
    fail "$1: the filter field not on the screen"
    return 1
  fi
  set -- $EMU_AT
  x=720
  y=$(( $8 + 170 ))
  say "tap the first program row at $x $y (below the filter field)"
  adb shell input tap "$x" "$y" < /dev/null > /dev/null 2>&1
  if wait_ui '^Start Workout$' 20; then
    say "outcome 'first program': ok"
  else
    say "outcome 'first program': no-effect"
    fail "the program preview did not open"
    return 1
  fi
}

# load_settings_open <look>: the settings page, then its Load settings button - named in the modern look; in
# the classic one it has no name and stands right of "Search settings" (main.qml: the search button is
# anchored to its left), as wide as it
load_settings_open() {
  settings_open || return 1
  if [ "$1" = m ]; then
    tap_ui '^Load settings$' '^Other folders$'
    return
  fi
  local x y w
  dump
  if ! find_ui '^Search settings$'; then
    fail "classic: 'Search settings' not in the header"
    return 1
  fi
  set -- $EMU_AT
  w=$(( $7 - $5 ))
  x=$(( $7 + w / 2 ))
  y=$2
  say "tap classic Load settings at $x $y (right of Search settings)"
  adb shell input tap "$x" "$y" < /dev/null > /dev/null 2>&1
  if wait_ui '^Other folders$' 15; then
    say "outcome 'Load settings': ok"
  else
    say "outcome 'Load settings': no-effect"
    fail "classic: the settings file list did not open"
    return 1
  fi
}

# the lists of PR 6a-1 for one side (b - master, h - branch) in one look (c - classic, m - modern)
lists() {
  local c=$1 modern=$2
  start_case "$c" ui_modern=$modern fakedevice_treadmill=true android_documents_folder=true || return 1

  if open_drawer '^Open Train Program$' && tap_ui '^Open Train Program$' '^Other folders$'; then
    emu_sleep 3
    snap "$c-1-programs"
    [ "$c" = hm ] && expect "$c-1-programs" '^Easy intervals$' 'the bundled programs as cards'
    if first_program "$c"; then
      emu_sleep 5
      snap "$c-2-preview"
      expect "$c-2-preview" '^Start Workout$' 'the program preview'
    fi
  fi
  back_to "$HOME_RX" 20

  if open_drawer '^Open GPX$' && tap_ui '^Open GPX$' '^Other folders$'; then
    emu_sleep 5
    snap "$c-3-gpx"
    # the first card: test-route is below the list area, under the map (run 43025955339)
    [ "$c" = hm ] && expect "$c-3-gpx" '^Box Hill$' 'the GPX routes as named cards'
  fi
  back_to "$HOME_RX" 20

  if load_settings_open "${c#?}"; then
    emu_sleep 2
    snap "$c-4-settings-files"
    [ "$c" = hm ] && expect "$c-4-settings-files" '^saved-setup' 'the seeded settings file as a card'
  fi
  back_to "$HOME_RX" 20
}

# credits_in_menu <case>: the open menu dragged up until Credits is on the screen
credits_in_menu() {
  shot "$1-drawer"
  local i
  for i in 1 2 3; do
    dump
    if find_ui '^Credits$'; then
      return 0
    fi
    say "drag the menu up $i"
    adb shell input swipe 300 2000 300 900 400 < /dev/null > /dev/null 2>&1
    emu_sleep 2
  done
  fail "$1: Credits not on the screen after 3 drags of the menu"
  return 1
}

# profile_actions <case>: the modern profile cards after a save - a tap selects the profile and shows Load,
# a long press asks to delete it (Cancel / Delete, UiMessageDialog), Cancel keeps it. The card carries the
# profile name (Accessible.name); no long press in the library: a swipe in place, 1.2 s
profile_actions() {
  local c=$1
  if ! wait_ui '^default$' 15; then
    fail "$c: the saved profile 'default' not in the list"
    return 1
  fi
  tap_ui '^default$' '^Load$' || return 1
  emu_sleep 1
  snap "$c-5c-selected"
  dump
  find_ui '^default$' || { fail "$c: the profile card gone after the selection"; return 1; }
  set -- $EMU_AT
  say "long press the profile card at $1 $2"
  adb shell input swipe "$1" "$2" "$1" "$2" 1200 < /dev/null > /dev/null 2>&1
  if wait_ui '^Delete$' 10; then
    say "outcome 'long press': ok"
    emu_sleep 1
    snap "$c-5d-delete"
    expect "$c-5d-delete" '^Cancel$' 'the delete question keeps a Cancel'
    expect "$c-5d-delete" '^Delete$' 'the delete question names its action'
    tap_ui '^Cancel$' '^Saved profiles$' || return 1
    wait_gone '^Delete$' 10 || fail "$c: the delete question still open after Cancel"
    wait_ui '^default$' 5 || fail "$c: the profile gone after Cancel"
  else
    say "outcome 'long press': no-effect"
    fail "$c: no delete question after a long press on the profile card"
  fi
}

# the pages of PR 6a-2: profiles, Credits, Swag Bag. The landings are named in both looks: "Other folders"
# (profiles), the thanks text (Credits), "Restore Purchases" (Swag Bag)
service() {
  local c=$1 modern=$2
  start_case "$c" ui_modern=$modern fakedevice_treadmill=true android_documents_folder=true || return 1

  # "Profile: " + the profile name; uifind matches the whole name (fullmatch), hence the tail
  if open_drawer '^Profile:.*' && tap_ui '^Profile:.*' '^Other folders$'; then
    emu_sleep 3
    snap "$c-5-profiles"
    if [ "$c" = hm ]; then
      expect "$c-5-profiles" '^Saved profiles$' 'the saved profiles header'
      expect "$c-5-profiles" '^New profile$' 'the new profile button'
    fi
    # Save: the box of the save (UiMessageDialog on the branch - the native dialog in the classic look,
    # a card in the modern one; MessageDialog on master), then the saved profile in the list
    if tap_ui '^Save$' '.*Profile saved correctly.*'; then
      emu_sleep 2
      snap "$c-5b-saved"
      # OK of the save box closes the page too (onOkClicked: stackView.pop())
      close_ok "$c save"
      wait_gone '.*Profile saved correctly.*' 10 || fail "$c: the save box still open after OK"
    fi
    if [ "$c" = hm ]; then
      back_to "$HOME_RX" 20
      open_drawer '^Profile:.*' && tap_ui '^Profile:.*' '^Other folders$' && profile_actions "$c"
    fi
  fi
  back_to "$HOME_RX" 20

  # the classic text starts with "<b>Credits</b><br><br>A very big thanks" (run 43021078003), the modern one
  # with the thanks; the whole name is matched (fullmatch), hence both ends
  # Swag Bag before Credits: the menu keeps the place it was dragged to, and Swag Bag at its top was
  # not on the screen after Credits (API 30, run 43032577399)
  if open_drawer '^Swag Bag$' && tap_ui '^Swag Bag$' '^Restore Purchases$'; then
    emu_sleep 2
    snap "$c-7-swagbag"
  fi
  back_to "$HOME_RX" 20

  # Credits is the last entry of the menu, below the screen on API 30 - not even laid out in the modern
  # menu, bounds 0 (run 43029651629), so bring_in has nothing to aim at: the menu by Swag Bag above it, a
  # frame of the menu, a drag up inside the menu (x 300: in both menus, 948 and 1179 px wide), then Credits
  if open_drawer '^Swag Bag$' && credits_in_menu "$c" && tap_ui '^Credits$' '.*A very big thanks.*'; then
    emu_sleep 2
    snap "$c-6-credits"
  fi
  back_to "$HOME_RX" 20
}

case ${PAGES:-lists} in
  lists) SHOTS="1-programs 2-preview 3-gpx 4-settings-files" ;;
  service) SHOTS="5-profiles 5b-saved 6-credits 7-swagbag" ;;
  *) echo "PAGES=$PAGES: lists or service" >&2; exit 1 ;;
esac

emu_init
logcat_start
say "== pages: ${PAGES:-lists}"

for side in b h; do
  if [ "$side" = b ]; then apk=apk-base/android-debug.apk; else apk=apk-head/android-debug.apk; fi
  say "== $side: start"
  wipe_files
  install_apk "$apk"
  seed_files
  "${PAGES:-lists}" "${side}c" false
  "${PAGES:-lists}" "${side}m" true
done

say "== classic: the branch against master"
for p in $SHOTS; do
  same_as_master "$p"
done

finish
