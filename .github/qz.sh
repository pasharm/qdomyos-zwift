# emu-lib: tools/emu/qz.sh sha 5e78ce7e29dd - edit there, then tools/emu/sync.py (T-505)
# Test only (T-505): QZ screens and settings for the emulator scenarios, on top of lib.sh (source lib.sh
# first). One source: tools/emu/qz.sh of the work folder, copied into .github/ by tools/emu/sync.py.
# Base: the T-498 scenario (test/t498-emu, c4c75732f); defects of the old copies - notes/emu-lib-2026-11-10.md.
PKG=org.cagnulen.qdomyoszwift
EMU_APP_RX=${EMU_APP_RX:-QZ|qdomyos}
CONF='files/.config/Roberto Viola/qDomyos-Zwift.conf'
LOG_DEBUG=${LOG_DEBUG:-true}
# The menu button / back arrow by its place (Nexus 6, 3.5 px per dp): the classic header buttons have no
# names. Both looks put it there
MENU=${MENU:-84 168}
# The home page in both looks: a treadmill shows one Pause instead of Start/Stop (T-461)
HOME_RX=${HOME_RX:-'^Start$|^Stop$|^Pause$'}
# The home page is ready (start_case waits for it: 25 s of looks): the support button shows on a home page with
# no speed and power (SupportHelpButton.qml). A case with a running workout never gets it - HOME_READY_RX=
# (empty) before start_case turns the wait off
HOME_READY_RX=${HOME_READY_RX-'^Contact QZ support$'}

# put_conf key=value ...: qz.conf of the app (log_debug and, below API 30, skipLocationServicesDialog
# added unless given); not written - red at once (T-346: the file did not arrive, the run went on)
put_conf() {
  local kv
  {
    printf '[General]\n'
    case " $* " in *" log_debug="*) ;; *) printf 'log_debug=%s\n' "$LOG_DEBUG" ;; esac
    if [ "${EMU_API:-35}" -lt 30 ]; then
      case " $* " in *" skipLocationServicesDialog="*) ;; *) printf 'skipLocationServicesDialog=true\n' ;; esac
    fi
    for kv in "$@"; do printf '%s\n' "$kv"; done
  } > qz.conf
  adb push qz.conf /data/local/tmp/qz.conf < /dev/null > /dev/null 2>&1
  adb shell "run-as $PKG mkdir -p 'files/.config/Roberto Viola'" < /dev/null > /dev/null 2>&1
  adb shell "run-as $PKG cp /data/local/tmp/qz.conf '$CONF'" < /dev/null > /dev/null 2>&1
  adb shell "run-as $PKG ls -l '$CONF'" < /dev/null >> "$STEPLOG" 2>&1 || proves_nothing "qz.conf not written"
}

# qz_dialogs: the hook of ensure_app for the app's own boxes - 0 when it closed one
qz_dialogs() {
  # "Permissions Required" (Bluetooth and location services off, images below API 30), then
  # "Reminder Preference": No (T-318, T-441)
  if grep -q -E "Permissions Required|Reminder Preference" ui.xml && find_ui '^No$'; then
    near dialog "QZ permission box: No"
    set -- $EMU_AT
    adb shell input tap "$1" "$2" < /dev/null > /dev/null 2>&1
    emu_sleep 3
    return 0
  fi
  # "New QZ build": Later
  if find_ui '^Later$'; then
    near dialog "new build box: Later"
    set -- $EMU_AT
    adb shell input tap "$1" "$2" < /dev/null > /dev/null 2>&1
    emu_sleep 2
    return 0
  fi
  return 1
}

# wait_home [seconds]: the home page (by its Start/Stop/Pause) with the windows over it closed
wait_home() {
  local i
  for i in 1 2 3 4; do
    ensure_app
    wait_ui "$HOME_RX" "${1:-30}" --first && return 0
  done
  return 1
}

# start_case <name> [key=value ...]: QZ stopped, qz.conf written, started, the home page; the pid of the
# case in steps.log (for js_errors by side). Home not shown - "!!", a frame <name>-0-no-home, 1
start_case() {
  local name=$1
  shift
  say "== $name: start ($*)"
  adb shell am force-stop "$PKG" < /dev/null > /dev/null 2>&1
  emu_sleep 2
  put_conf "$@"
  adb shell am start -n "$PKG/$PKG.CustomQtActivity" < /dev/null > /dev/null 2>&1
  if ! wait_home; then
    fail "$name: home page not shown"
    shot "$name-0-no-home" now
    return 1
  fi
  say "pid $name $(adb shell pidof "$PKG" < /dev/null | tr -d '\r')"
  # the home page is ready, not only shown: the support button comes after 10 s of zero speed (5 s with no
  # device, SupportHelpButton.qml) - the fixed sleep of 10 s raced it, the frame of the home page had it
  # or not run by run (T-505 pilots 3-5); then a still screen
  # (25 s of looks: a look is a dump, ~5 s on CI - without the button the case loses up to ~55 s; the
  # message without the time and the reason - one step for review_run --summary)
  if [ -n "$HOME_READY_RX" ] && ! wait_ui "$HOME_READY_RX" 25; then
    near home "'$HOME_READY_RX' not shown"
  fi
  ensure_app
  still
  return 0
}

# open_drawer <regex of an entry>: the menu button by its place (it has no name in the classic look),
# repeated until the entry shows
open_drawer() {
  local i
  for i in 1 2 3; do
    ensure_app
    say "tap menu $MENU"
    adb shell input tap $MENU < /dev/null > /dev/null 2>&1
    emu_sleep 3
    if wait_ui "$1" 9; then
      say "outcome 'menu': ok ('$1' shown)"
      return 0
    fi
    near drawer "'$1' not shown after the menu tap $i"
    adb shell input keyevent 4 < /dev/null > /dev/null 2>&1
    emu_sleep 2
  done
  say "outcome 'menu': no-effect"
  fail "the menu did not open ('$1' not shown)"
}

# settings_open: the settings page from the menu
settings_open() {
  open_drawer '^Settings$' || return 1
  tap_ui '^Settings$' '^General Options$'
}

# back_to <regex> [seconds]: the back arrow of the app ("Back" by name in the modern look, the menu place in
# the classic one) - not KEYCODE_BACK: on API 33 it took QZ to the launcher (T-424)
back_to() {
  local i
  for i in 1 2 3; do
    hide_keyboard
    if dump && find_ui '^Back$'; then
      set -- "$1" "${2:-15}" $EMU_AT
      adb shell input tap "$3" "$4" < /dev/null > /dev/null 2>&1
    else
      adb shell input tap $MENU < /dev/null > /dev/null 2>&1
    fi
    wait_ui "$1" "${2:-15}" --first && { say "back to '$1'"; return 0; }
    near back "'$1' not shown after the back tap $i"
  done
  fail "back: '$1' not shown"
}

# close_ok <what>: the box of a save ("Profile Saved" and the like) closed by its OK, if it is there
close_ok() {
  if dump && find_ui '^(OK|ОК)$'; then
    set -- "$1" $EMU_AT
    say "close_ok $1: OK at $2 $3"
    adb shell input tap "$2" "$3" < /dev/null > /dev/null 2>&1
    emu_sleep 2
  else
    say "close_ok $1: no box"
  fi
}

# tap_dot <name> <y from>: the classic StaticAccordionElement header (a Text, not in the dump) by its grey
# dot (x 40..110 px) on the raw frame below <y from> and above the page end; tapped in the middle of the row
tap_dot() {
  local y bot
  frame raw.bin
  dump
  bot=$(uifind ui.xml --band 2>/dev/null | cut -d' ' -f2)
  y=$("$EMU_PY" - raw.bin "$2" "${bot:-2390}" << 'EOF'
import sys
d = open(sys.argv[1], 'rb').read()
w = int.from_bytes(d[0:4], 'little'); h = int.from_bytes(d[4:8], 'little')
off = len(d) - w * h * 4
ys = []
for y in range(int(sys.argv[2]), min(h, int(sys.argv[3]))):
    row = off + y * w * 4
    hit = False
    for x in range(40, 110):
        r, g, b = d[row + x * 4], d[row + x * 4 + 1], d[row + x * 4 + 2]
        if r > 120 and abs(r - g) < 12 and abs(r - b) < 12:
            hit = True
            break
    if hit:
        ys.append(y)
    elif ys:
        break
if 15 <= len(ys) <= 45:
    print((ys[0] + ys[-1]) // 2)
EOF
)
  if [ -n "$y" ]; then
    say "tap_dot $1: header dot at y $y, tap 400 $y"
    adb shell input tap 400 "$y" < /dev/null > /dev/null 2>&1
  else
    fail "tap_dot $1: header dot not found between $2 and ${bot:-2390}"
  fi
}
