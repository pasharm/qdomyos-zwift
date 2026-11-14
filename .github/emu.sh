#!/bin/bash
# Test only (T-544): the status bar of the modern look on Android. Base (apk-base) - the beta before the
# change: the status bar black over the app (the theme of Qt 5.15, Theme_Holo_Light, draws no system bar
# backgrounds). Head (apk-head) - the beta with the change: the bar in the colour of the page (transparent
# from API 31, the page colour on API 30), with the drawer open the sheet under it, after a scroll of the
# tiles the header background still under it; the classic look keeps the black bar on both sides.
# Checked by the colour of the bar rows (t544_bar.py): the part of them within 8 of a point of the page.
. .github/lib.sh
. .github/qz.sh

BAR=84          # status bar of the CI Nexus 6: 24 dp at 3.5 px per dp
HEADER_PT="20 120"   # the header background left of the menu button (main.qml header ToolBar)
SHEET_PT="20 400"    # the drawer sheet below its title, left padding (main.qml Drawer, Rectangle)

# app_uid: the uid of the installed app - the owner of its data folder; empty without the app
app_uid() {
  adb shell "su 0 stat -c %u /data/data/$PKG" < /dev/null 2>/dev/null | tr -d '\r'
}

wipe_app() {
  adb shell am force-stop "$PKG" < /dev/null > /dev/null 2>&1
  adb uninstall "$PKG" < /dev/null > /dev/null 2>&1
  if [ -n "$(app_uid)" ]; then
    proves_nothing "$PKG still installed before the next side"
  fi
}

# snap <name>: the raw frame for the colour check, then the frame with its dumps
snap() {
  frame "raw-$1" || near frame "$1: no raw frame"
  shot "$1"
}

# bar_share <name> <x> <y> [x0 x1] [--ref-frame raw]: "share S ..." of t544_bar.py for raw-<name>; S in BAR_S
bar_share() {
  local n=$1 out
  shift
  BAR_S= BAR_D= BAR_L=
  out=$("$EMU_PY" "$EMU_GH/t544_bar.py" "raw-$n" "$@" --bar "$BAR" 2>&1)
  say "bar $n: $out"
  BAR_S=$(echo "$out" | awk '/^share/ {print $2}')
  BAR_D=$(echo "$out" | awk '/^share/ {print $12}')
  BAR_L=$(echo "$out" | awk '/^share/ {print $14}')
  [ -n "$BAR_S" ]
}

# icons <name> <light|dark>: the icons of the bar in the contrast of the page - dark ones on a light page
# (BAR_D, the part darker than 180), light ones on a dark page (BAR_L, lighter than 120). The first run
# (43510037607): API 30, light page - dark 0.000, the icons stayed white; API 35 - dark 0.068
icons() {
  local v=$BAR_D tone=dark ok
  [ "$2" = dark ] && { v=$BAR_L; tone=light; }
  ok=$(awk -v s="$v" 'BEGIN {print (s >= 0.02) ? 1 : 0}')
  if [ "$ok" = 1 ]; then say "check $1: $tone icons on the bar: OK ($tone $v)"
  else fail "check $1: no $tone icons on the bar ($tone $v)"; fi
}

# want <name> <min|max> <limit> <what>: BAR_S at least / at most the limit, or a failure
want() {
  local ok
  if [ "$2" = min ]; then ok=$(awk -v s="$BAR_S" -v l="$3" 'BEGIN {print (s >= l) ? 1 : 0}')
  else ok=$(awk -v s="$BAR_S" -v l="$3" 'BEGIN {print (s <= l) ? 1 : 0}'); fi
  if [ "$ok" = 1 ]; then say "check $1: $4: OK (share $BAR_S, $2 $3)"
  else fail "check $1: $4: share $BAR_S, $2 $3"; fi
}

# modern <case> <light|dark> <side>: home, the drawer, the tiles scrolled up
modern() {
  local c=$1 mode=$2 side=$3 what
  start_case "$c" ui_modern=true ui_theme_mode=$mode fakedevice_treadmill=true || return 1
  emu_sleep 2
  snap "$c-1-home"
  if bar_share "$c-1-home" $HEADER_PT; then
    if [ "$side" = h ]; then
      want "$c-1-home" min 0.6 "the status bar in the colour of the header"
      icons "$c-1-home" "$mode"
    else say "base $c-1-home: share $BAR_S (the black bar)"; fi
  else
    fail "$c-1-home: the bar not measured"
  fi

  # main.qml Drawer: the entries of the menu in the tree (MENU_RX of qz.sh)
  if open_drawer '^Settings$'; then
    emu_sleep 2
    snap "$c-2-drawer"
    # API 31+: the window under the bar, the sheet shows through it (main.qml Drawer, topMargin
    # -topPadding); below 31 the window keeps below the bar, which has the page colour
    # (CustomQtActivity.setSystemBars) - the sheet starts under it, as on the first run (43510037607, API 30)
    if [ "${EMU_API:-35}" -ge 31 ]; then
      bar_share "$c-2-drawer" $SHEET_PT 0 1100; what="the drawer sheet under the status bar"
    else
      bar_share "$c-2-drawer" $HEADER_PT 0 1100 --ref-frame "raw-$c-1-home"; what="the bar in the page colour (API < 31)"
    fi
    if [ -n "$BAR_S" ]; then
      if [ "$side" = h ]; then
        want "$c-2-drawer" min 0.6 "$what"
        icons "$c-2-drawer" "$mode"
      else say "base $c-2-drawer: share $BAR_S"; fi
    else
      fail "$c-2-drawer: the bar not measured"
    fi
    adb shell input keyevent 4 < /dev/null > /dev/null 2>&1
    emu_sleep 2
  else
    fail "$c: the drawer not opened"
  fi
  wait_home 20 || { fail "$c: no home after the drawer"; return 1; }

  # main.qml header: barHidden follows barShift, set by the tile grid of Home.qml when it scrolls up; the
  # buttons of the header are then out of the tree (contentItem.visible). The bar background stays (head)
  adb shell input swipe 720 2100 720 900 400 < /dev/null > /dev/null 2>&1
  emu_sleep 2
  still
  snap "$c-3-scrolled"
  if [ -s "dumps/$c-3-scrolled.xml" ] && grep -q 'content-desc="Main menu"' "dumps/$c-3-scrolled.xml"; then
    near scroll "$c: the header still in the tree after the swipe"
    say "!! $c-3-scrolled: the header did not go - the run proves nothing for the scrolled bar"
    FAILED=1
  elif bar_share "$c-3-scrolled" $HEADER_PT --ref-frame "raw-$c-1-home"; then
    if [ "$side" = h ]; then
      want "$c-3-scrolled" min 0.6 "the header colour under the status bar after the scroll"
      icons "$c-3-scrolled" "$mode"
    else say "base $c-3-scrolled: share $BAR_S"; fi
  else
    fail "$c-3-scrolled: the bar not measured"
  fi

  # the window loses and gets back the focus (the notification shade): Qt 5.15.0 calls updateFullScreen ->
  # setFullScreen(true) -> decorView.setSystemUiVisibility(immersive flags) on every focus gain
  # (QtActivityDelegate.java:864-871 v5.15.0; main.qml visibility: Qt.WindowFullScreen) - the call writes
  # the whole flag set, SYSTEM_UI_FLAG_LIGHT_STATUS_BAR included; QZ does not apply the bars again there
  adb shell cmd statusbar expand-notifications < /dev/null > /dev/null 2>&1
  emu_sleep 2
  adb shell cmd statusbar collapse < /dev/null > /dev/null 2>&1
  emu_sleep 3
  snap "$c-4-shade"
  if bar_share "$c-4-shade" $HEADER_PT --ref-frame "raw-$c-1-home"; then
    if [ "$side" = h ]; then
      icons "$c-4-shade" "$mode"
    else say "base $c-4-shade: share $BAR_S"; fi
  else
    fail "$c-4-shade: the bar not measured"
  fi
}

# classic <case> <side>: the classic home page; the bar stays black on both sides
classic() {
  local c=$1 side=$2
  start_case "$c" ui_modern=false fakedevice_treadmill=true || return 1
  emu_sleep 2
  snap "$c-1-home"
  if bar_share "$c-1-home" $HEADER_PT; then
    say "$side $c-1-home: share $BAR_S"
    # the black bar is near no point of the classic header (theme_status_bar_background_color, blue by default)
    want "$c-1-home" max 0.3 "the classic status bar not in the header colour"
  else
    fail "$c-1-home: the bar not measured"
  fi
}

emu_init
say "== pages: status bar (T-544)"
logcat_start

for side in b h; do
  if [ "$side" = b ]; then apk=apk-base/android-debug.apk; else apk=apk-head/android-debug.apk; fi
  side_on "$side" "$apk" || continue
  say "== $side: start"
  wipe_app
  install_apk "$apk"
  modern "${side}ml" light "$side"
  modern "${side}md" dark "$side"
  classic "${side}c" "$side"
done

finish
