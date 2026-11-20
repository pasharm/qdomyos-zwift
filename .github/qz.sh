# emu-lib: tools/emu/qz.sh sha 537554f5943f - edit there, then tools/emu/sync.py (T-505)
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
# The menu is open: one of its entries in the tree (the labels of the drawer in main.qml, both looks; none
# of them elsewhere on the home page - Workout Editor and Credits are page titles too, hence not here). Checked on the dumps of
# notes/emu (13.11): 0 of 263 home dumps, 107 of 122 drawer dumps (the rest: the menu closed, or the Ukrainian UI - there open_drawer does as before)
MENU_RX=${MENU_RX:-'^(Settings|Charts|Profile: .*|Open Train Program|Open GPX|Save FIT|Save GPX|Workouts History|Swag Bag|Wizard|Community|Quit)$'}
# The home page in both looks: a treadmill shows one Pause instead of Start/Stop (T-461). In the languages of the
# scenarios too (en, uk, ru, de - words from src/translations/*.ts): T-552 lesson 2 - a case with app_language=uk
# and the English words only, all 12 uk cases "home page not shown", ~22 min
HOME_RX=${HOME_RX:-'^(Start|Stop|Pause|Старт|Стоп|Пауза|Stopp)$'}
# The home page is ready (start_case waits for it: 25 s of looks): the support button shows on a home page with
# no speed and power (SupportHelpButton.qml). A case with a running workout never gets it - HOME_READY_RX=
# (empty) before start_case turns the wait off. The same languages (uk, ru, de)
HOME_READY_RX=${HOME_READY_RX-'^(Contact QZ support|Зв’язатися зі службою підтримки QZ|Связаться со службой поддержки QZ|QZ-Support kontaktieren)$'}

# put_conf key=value ...: qz.conf of the app (log_debug and, below API 30, skipLocationServicesDialog
# added unless given); not written - red at once (T-346: the file did not arrive, the run went on).
# ui_text_scale=N alone does nothing where the system size is read: main.qml textScale takes the system size while
# ui_text_scale_system is true (its default) - red at once (T-552 lesson 3: a case at 170 % ran green at 100 %)
put_conf() {
  local kv
  case " $* " in
    *" ui_text_scale="*)
      case " $* " in
        *" ui_text_scale_system=false "*) ;;
        *) proves_nothing "put_conf ui_text_scale=... without ui_text_scale_system=false: main.qml textScale takes the system size" ;;
      esac ;;
  esac
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
  # "New QZ build" (UiBetaUpdate, builds of the beta): Later in the modern look; the classic one shows it as
  # the native box of Android with No/Yes (T-505 pilot 42995009143) - Yes would download the APK
  # (Later alone, as before: whether the modern box puts its title into the dump is not seen in any run).
  # In the languages of the scenarios too, words from src/translations/*.ts (en, uk, ru, de): T-475 run
  # 43649498728 - the modern box in Ukrainian (Пізніше) stayed over the home page of the base, a beta
  # build came out during the run
  local later='^(Later|Пізніше|Позже|Später)$'
  if find_ui "$later" ||
     { grep -q -E "New QZ build|Нова збірка QZ|Новая сборка QZ|Neuer QZ-Build" ui.xml && find_ui '^(No|Ні|Нет|Nein)$'; }; then
    near dialog "new build box: $(uifind ui.xml '^(Later|Пізніше|Позже|Später|No|Ні|Нет|Nein)$' --name 2>/dev/null)"
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
# case in steps.log (for js_errors by side). Home not shown - "!!", a frame <name>-0-no-home, 1.
# A case EMU_CASES does not select (by <name> or <function>/<name>, the function - any caller up the stack,
# land_case of land_case -> empty_case -> start_case too; case_on in lib.sh): "skipped", 1 and nothing done
# - the scenario function stops at its `start_case ... || return 1` (T-534, T-617)
start_case() {
  local name=$1 fn=${FUNCNAME[1]:-main}
  shift
  if ! case_on "$name" "${FUNCNAME[*]:1}"; then
    say "== $name: skipped ($fn; cases: $EMU_CASES)"
    return 1
  fi
  say "== $name: start ($*) in $fn at $SECONDS s"
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
  # rotate land before the start: on API 30 the start turns QZ back to portrait (T-617 run 44612383102) -
  # a landscape case shot in portrait would pass its checks (T-609 lessons 1, 3)
  if [ "$EMU_ROT" = land ]; then
    local w h
    read -r w h <<< "$(frame_wh)"
    if [ "$w" -le "$h" ]; then
      fail "$name: not landscape after the start (API $EMU_API, frame ${w}x$h) - rotate land after start_case"
      shot "$name-0-not-land" now
      return 1
    fi
  fi
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
    # --any: the entry in the tree, on the screen or not - the entries of a closed menu are not in the tree
    # (18 home dumps of notes/emu, none with "Settings"); at 170 % text on API 35 "Settings" lies in the
    # navigation bar, tap_ui brings it in by a swipe (T-514, 43209989589). Wholly below the screen (API 30,
    # 170 %) it is in the tree with [0,0][0,0], and --any drops it too - the next check
    if wait_ui "$1" 9 --any; then
      say "outcome 'menu': ok ('$1' shown)"
      return 0
    fi
    # The menu is open (only its entries are in the tree), the entry wholly beyond the screen, [0,0][0,0]: on
    # API 30 at 170 % "Settings" and all below lie past the end of a menu at its top - drag it up to its end;
    # not there - to its top, as below (T-616; T-612, lesson 6, 44533999395)
    if [ -s ui.xml ] && uifind ui.xml --offscreen "$1" > /dev/null 2>&1; then
      local up
      menu_drag "$1" up && return 0
      up=$EMU_WHY
      menu_drag "$1" down && return 0
      say "outcome 'menu': no-effect"
      fail "the menu is open, '$1' in the tree beyond the screen ([0,0][0,0]) - not shown after dragging the menu up ($up) and down ($EMU_WHY)"
      return 1
    fi
    # The menu is open, the entry not in the tree: the menu keeps the place it was dragged to (API 30:
    # after Credits its top entries are not in the tree), closing and opening it again shows the same -
    # drag it down to its top (T-526; T-525, lesson 3, 43310802748)
    # (no dump: uifind prints nothing - not "open", the old retry below)
    if n=$(uifind ui.xml --count "$MENU_RX" 2>/dev/null) && [ "${n:-0}" -gt 0 ]; then
      menu_drag "$1" down && return 0
      say "outcome 'menu': no-effect"
      fail "the menu is open, '$1' not in the tree after dragging the menu down ($EMU_WHY)"
      return 1
    fi
    near drawer "'$1' not shown after the menu tap $i"
    adb shell input keyevent 4 < /dev/null > /dev/null 2>&1
    emu_sleep 2
  done
  say "outcome 'menu': no-effect"
  fail "the menu did not open ('$1' not shown)"
}

# menu_drag <regex of an entry> <down|up>: the open menu dragged in the menu column - a finger down to its
# top, up to its end - until the entry is in the tree (on the screen or not, as --any takes it) or the menu
# stops moving; EMU_WHY - why it stopped. Up: 1900 -> 600, as settings_open_end of T-612 (44551913972: Settings
# reached on API 30 and 35)
menu_drag() {
  local i a=900 b=2000 edge=top
  [ "$2" = up ] && { a=1900; b=600; edge=end; }
  for i in 1 2 3 4; do
    # no dump after the last drag of the other way: nothing to compare with - this drag is not "the same"
    cp ui.xml .emu_m.xml 2>/dev/null || : > .emu_m.xml
    say "drag the menu $2 $i"
    adb shell input swipe 300 "$a" 300 "$b" 400 < /dev/null > /dev/null 2>&1
    emu_sleep 2
    dump || { EMU_WHY="no dump after drag $i"; return 1; }
    if find_ui "$1" --any; then
      say "outcome 'menu': ok ('$1' shown after dragging the menu $2 $i)"
      return 0
    fi
    "$EMU_PY" "$EMU_GH/emu_frame.py" same .emu_m.xml ui.xml && { EMU_WHY="its $edge: drag $i did not move it"; return 1; }
  done
  EMU_WHY="still moving after 4 drags"
  return 1
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
