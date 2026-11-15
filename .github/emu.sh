#!/bin/bash
# Test only (T-475, PR): "Return to app" on the T.Zone tile in place of its "min-max W %" line, classic look
# (master has no modern tile button), languages en, ru, de.
# Base (b): origin/master e5d634d73 (with PR 5648), branch test/t475-master - the button only on T.Power(W),
# T.Zone shows its second line.
# Head (h): fix/target-zone-hold 57f263787 + the test hook of test/t475-pr-apk: rootItem.targetPowerReleaseVisible
# replaced by true (src/Home.qml, the classic RoundButton targetPowerRelease), so the button shows on T.Power(W)
# and T.Zone without a FitPlus bike.
# Code of the head (src/Home.qml): RoundButton targetPowerRelease visible on identificator target_power or
# target_zone; secondLineText visible: !largeButton && !targetPowerRelease.visible.
# The second line text is Accessible.ignored (not in the dump): its absence on h and presence on b are told by
# the frames (review by eye), the scenario checks the button and its place inside the T.Zone tile.
# Cases <side><lang>: e - en, r - ru, d - de. Fake bike (applewatch_fakedevice): T.Zone shows Z1.0 and
# "0-110 W 0%" with the default FTP (homeform.cpp, the BIKE branch of the zone tiles).
HOME_RX='^(Start|Stop|Pause|Старт|Стоп|Пауза|Stopp)$'
HOME_READY_RX='^(Contact QZ support|Связаться со службой поддержки QZ|QZ-Support kontaktieren)$'
. .github/lib.sh
. .github/qz.sh

# zone_rx / btn_rx <lang>: the T.Zone tile name and the button text (src/translations/qdomyos-zwift_<lang>.ts of
# origin/master: "T.Zone" -> ru "Ц.зона", de "Z.Zone"; "Return to app" -> ru "Вернуть приложению",
# de "Zurück an die App")
zone_rx() {
  case $1 in
    en) echo '^T\.Zone: .*' ;;
    ru) echo '^Ц\.зона: .*' ;;
    de) echo '^Z\.Zone: .*' ;;
  esac
}
btn_rx() {
  case $1 in
    en) echo '^Return to app$' ;;
    ru) echo '^Вернуть приложению$' ;;
    de) echo '^Zurück an die App$' ;;
  esac
}

# in_tile <shot> <zone rx> <button rx>: the topmost button below the top of the T.Zone tile lies inside that
# tile (T.Power(W) is put later in the order, so its button is in a lower row)
in_tile() {
  local s=$1 zrx=$2 brx=$3 z b zx1 zy1 zx2 zy2 bx by
  z=$(uifind "dumps/$s.xml" "$zrx") || { fail "check $s: T.Zone tile not on the screen"; return 1; }
  set -- $z; zx1=$5; zy1=$6; zx2=$7; zy2=$8
  b=$(uifind "dumps/$s.xml" "$brx" --below "$zy1" --first) || { fail "check $s: no button below the T.Zone top $zy1"; return 1; }
  set -- $b; bx=$1; by=$2
  if [ "$bx" -ge "$zx1" ] && [ "$bx" -le "$zx2" ] && [ "$by" -ge "$zy1" ] && [ "$by" -le "$zy2" ]; then
    say "check $s: the button inside the T.Zone tile ($bx $by in $zx1 $zy1 $zx2 $zy2): OK"
  else
    fail "check $s: the button at $bx $by is not inside the T.Zone tile $zx1 $zy1 $zx2 $zy2"
  fi
}

zone_case() {
  local c=$1 side=$2 lang=$3 zrx brx
  zrx=$(zone_rx "$lang"); brx=$(btn_rx "$lang")
  start_case "$c" ui_modern=false app_language="$lang" applewatch_fakedevice=true \
    tile_target_zone_enabled=true tile_target_zone_order=0 \
    tile_target_power_enabled=true tile_target_power_order=8 || return 1
  scroll_to "$zrx" || return 1
  settle
  shot "$c-1-zone"
  expect "$c-1-zone" "$zrx" "the T.Zone tile"
  if [ "$side" = h ]; then
    expect "$c-1-zone" "$brx" "Return to app on the screen"
    in_tile "$c-1-zone" "$zrx" "$brx"
  else
    # master: the button only on T.Power(W), never inside the T.Zone tile
    if b=$(uifind "dumps/$c-1-zone.xml" "$brx" --first); then
      local z zy1 zy2 by
      z=$(uifind "dumps/$c-1-zone.xml" "$zrx"); set -- $z; zy1=$6; zy2=$8
      set -- $b; by=$2
      if [ "$by" -ge "$zy1" ] && [ "$by" -le "$zy2" ]; then
        fail "check $c: a button inside the T.Zone tile on master"
      else
        say "check $c: no button in the T.Zone tile on master: OK"
      fi
    else
      say "check $c: no button in the T.Zone tile on master: OK"
    fi
  fi
}

emu_init
logcat_start

for side in b h; do
  if [ "$side" = b ]; then apk=apk-base/android-debug.apk; else apk=apk-head/android-debug.apk; fi
  side_on $side "$apk" || continue
  say "== $side: start"
  install_apk "$apk"
  zone_case "${side}e" $side en
  zone_case "${side}r" $side ru
  zone_case "${side}d" $side de
  adb shell am force-stop "$PKG" < /dev/null > /dev/null 2>&1
done

logcat_stop
finish
