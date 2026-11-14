#!/bin/bash
# Test only (T-475): "Return to app" on the T.Zone tile (Ц.зона) in place of its "min-max W %" line, both looks.
# Base (b): beta-2660, run 43646406211 - no button anywhere, T.Zone shows its second line.
# Head (h): feat/modern-beta efcc83a20 + the T.Zone button (t475-beta) + the test hook of test/t475-apk:
# rootItem.targetPowerReleaseVisible replaced by true in both looks, so the button shows on T.Power(W) and
# T.Zone without a bike (as test/t403-emu-apk did for T.Power(W)).
# Code of the head (src/Home.qml of t475-beta): modern look - RoundButton modernRelease visible on
# identificator target_power or target_zone, the second line Text visible: !largeButton && !modernRelease.visible;
# classic look - RoundButton classicRelease, secondLineText visible: !largeButton && !classicRelease.visible.
# The second line text is Accessible.ignored (not in the dump): its absence on h and presence on b are
# told by the frames (review by eye), the scenario checks the button and its place inside the T.Zone tile.
# Cases <side><case>: m - modern uk, c - classic uk. Fake bike (applewatch_fakedevice): T.Zone shows Z1.0 and
# "0-110 Вт 0%" with the default FTP (homeform.cpp, the BIKE branch of the zone tiles).
HOME_RX='^(Start|Stop|Pause|Старт|Стоп|Пауза)$'
HOME_READY_RX='^(Contact QZ support|Зв’язатися зі службою підтримки QZ)$'
. .github/lib.sh
. .github/qz.sh

ZONE='^Ц\.зона: .*'
BTN='^Повернути застосунку$'

# in_tile <shot>: the topmost button below the top of the T.Zone tile lies inside that tile (T.Power(W) is
# put later in the order, so its button is in a lower row)
in_tile() {
  local s=$1 z b zx1 zy1 zx2 zy2 bx by
  z=$(uifind "dumps/$s.xml" "$ZONE") || { fail "check $s: T.Zone tile not on the screen"; return 1; }
  set -- $z; zx1=$5; zy1=$6; zx2=$7; zy2=$8
  b=$(uifind "dumps/$s.xml" "$BTN" --below "$zy1" --first) || { fail "check $s: no button below the T.Zone top $zy1"; return 1; }
  set -- $b; bx=$1; by=$2
  if [ "$bx" -ge "$zx1" ] && [ "$bx" -le "$zx2" ] && [ "$by" -ge "$zy1" ] && [ "$by" -le "$zy2" ]; then
    say "check $s: the button inside the T.Zone tile ($bx $by in $zx1 $zy1 $zx2 $zy2): OK"
  else
    fail "check $s: the button at $bx $by is not inside the T.Zone tile $zx1 $zy1 $zx2 $zy2"
  fi
}

zone_case() {
  local c=$1 side=$2
  start_case "$c" ui_modern="$3" app_language=uk applewatch_fakedevice=true \
    tile_target_zone_enabled=true tile_target_zone_order=0 \
    tile_target_power_enabled=true tile_target_power_order=8 || return 1
  scroll_to "$ZONE" || return 1
  settle
  shot "$c-1-zone"
  expect "$c-1-zone" "$ZONE" "the T.Zone tile"
  if [ "$side" = h ]; then
    expect "$c-1-zone" "$BTN" "Return to app on the screen"
    in_tile "$c-1-zone"
  else
    expect_not "$c-1-zone" "$BTN" "no Return to app before the change"
  fi
}

emu_init
logcat_start

for side in b h; do
  if [ "$side" = b ]; then apk=apk-base/android-debug.apk; else apk=apk-head/android-debug.apk; fi
  side_on $side "$apk" || continue
  say "== $side: start"
  install_apk "$apk"
  zone_case "${side}m" $side true
  zone_case "${side}c" $side false
  adb shell am force-stop "$PKG" < /dev/null > /dev/null 2>&1
done

logcat_stop
finish
