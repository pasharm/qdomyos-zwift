# emu-lib: tools/emu/lib.sh sha bac82c6ad2cd - edit there, then tools/emu/sync.py (T-505)
# Test only (T-505): the common functions of the emulator scenarios (.github/emu.sh of the emu branches).
# One source: tools/emu/lib.sh of the work folder; tools/emu/sync.py copies it with uifind.py, emu_frame.py
# and A11yDriver.java into .github/ of a branch. The scenario does
#     . .github/lib.sh; . .github/qz.sh
# and never copies or redefines these functions (check_emu_script.py: stale-lib, lib-override).
# Background and the defects of the old copies: notes/emu-lib-2026-11-10.md, notes/emu-tools-research-2026-11-10.md.
#
# steps.log lines (tools/emu/review_run.py reads them):
#   !! <what>                      a failure; FAILED=1 (the run is red at `finish`)
#   ~~ near <kind>: <what>         a near miss: the step passed, but only after a fix-up (scrolled
#                                  out of the header, waited for a moving screen, keyboard hidden,
#                                  a tap repeated, ACTION_CLICK fell back to a touch)
#   outcome <step>: ok|no-effect|wrong-screen   what a tap did: the landing shown / nothing changed on
#                                  the screen / the screen changed, but not to the landing
#   check <shot>: <what>: OK       a check passed; `finish` wants at least one
#   -- shot <name>                 a frame <name>.png with its dump dumps/<name>.xml
# Rules for every function here: all variables local, a failure says "!!" and sets FAILED, the
# return code is 0/1 (wait_ui and find also 2 - two controls, 3 - hidden), no "|| true" on a step a
# conclusion rests on.
#
# Settings (before sourcing or before emu_init): PKG (the app), STEPLOG (steps.log), EMU_GH (.github -
# where uifind.py and the others are), EMU_PY (python3), EMU_POLL (3 - seconds of one look at the
# screen: a dump takes ~2.3 s on API 35), EMU_FAST (tests: no sleep), EMU_MASKS ("x1,y1,x2,y2 ..." -
# frame areas that change by themselves: clocks, charts), EMU_APP_RX (regex of the app name in an
# "isn't responding" box; default the package).
EMU_LIB_VERSION=1
: "${STEPLOG:=steps.log}" "${EMU_GH:=.github}" "${EMU_PY:=python3}" "${EMU_POLL:=3}"
FAILED=${FAILED:-0}
EMU_AT=""     # the last find: "x y checkable checked x1 y1 x2 y2"
EMU_WHY=""    # why the last find or wait failed

emu_sleep() { [ -n "$EMU_FAST" ] || sleep "$1"; }
say() { echo "$*" >> "$STEPLOG"; }
fail() { echo "!! $*" >> "$STEPLOG"; FAILED=1; return 1; }
near() { local kind=$1; shift; echo "~~ near $kind: $*" >> "$STEPLOG"; }
# proves_nothing <what>: the run cannot check what it is for - red at once
proves_nothing() { echo "!! $* - the run proves nothing" >> "$STEPLOG"; cat "$STEPLOG"; exit 1; }
uifind() { "$EMU_PY" "$EMU_GH/uifind.py" "$@"; }

# emu_init: a new steps.log, the frames as the user sees them, the API in the log
emu_init() {
  : > "$STEPLOG"
  mkdir -p dumps
  FAILED=0
  adb shell settings put global hide_error_dialogs 1 < /dev/null > /dev/null 2>&1
  adb shell settings put system accelerometer_rotation 0 < /dev/null > /dev/null 2>&1
  adb shell settings put system user_rotation 0 < /dev/null > /dev/null 2>&1
  EMU_API=$(adb shell getprop ro.build.version.sdk < /dev/null | tr -d '\r')
  say "== API $EMU_API lib $EMU_LIB_VERSION"
}

# logcat_start / logcat_stop: the whole log in full_logcat.txt, buffers as separate -b (API 21/23 do not
# take a list - check_emu_script old-logcat)
logcat_start() {
  adb logcat -c < /dev/null > /dev/null 2>&1
  adb logcat -v threadtime -b main -b system -b crash > full_logcat.txt 2>/dev/null &
  EMU_LOGCAT_PID=$!
}
logcat_stop() {
  [ -n "$EMU_LOGCAT_PID" ] || return 0
  kill "$EMU_LOGCAT_PID" 2>/dev/null
  wait "$EMU_LOGCAT_PID" 2>/dev/null
  EMU_LOGCAT_PID=""
}

# dump: ui.xml of the screen now; 1 - no dump. The old file goes first, here and on the device: a
# failed dump must not leave the tree of the screen before (T-181)
dump() {
  rm -f ui.xml
  # /data/local/tmp, not /sdcard: /sdcard is not writable on the API 21/23 images (see shot)
  adb shell rm -f /data/local/tmp/ui.xml < /dev/null > /dev/null 2>&1
  timeout 25 adb shell uiautomator dump /data/local/tmp/ui.xml < /dev/null > /dev/null 2>&1
  adb pull /data/local/tmp/ui.xml ui.xml < /dev/null > /dev/null 2>&1
  [ -s ui.xml ]
}

# app_alive: a process of PKG is running. By ps, not pidof: API 21 has no pidof, and before API 24 adb
# shell sends "pidof: not found" to stdout - it would read as a pid. `ps -A` lists all processes on API
# 26+, plain `ps` - on the older ones; the name is the last column
app_alive() {
  { adb shell ps -A < /dev/null 2>/dev/null; adb shell ps < /dev/null 2>/dev/null; } | tr -d '\r' \
    | awk -v p="$PKG" '$NF == p || index($NF, p ":") == 1 { f = 1 } END { exit !f }'
}

# EMU_ROWS: the rows of a frame compared by tap_ui and still - without the status bar (its clock turns
# a minute: "nothing changed" became wrong-screen, a still screen "moving"); 84 px on the CI Nexus 6
EMU_ROWS="${EMU_STATUS_BAR:-84},100000"

# frame <file>: the raw frame (no PNG coding - for emu_frame.py)
frame() {
  adb exec-out screencap < /dev/null > "$1" 2>/dev/null
  [ -s "$1" ]
}

# shot <name>: <name>.png, then the dump of the same screen as dumps/<name>.xml (exec-out: /sdcard is not
# writable on API 21/23)
shot() {
  say "-- shot $1"
  adb exec-out screencap -p < /dev/null > "$1.png" 2>/dev/null
  [ -s "$1.png" ] || near shot "$1: no frame"
  mkdir -p dumps
  if dump; then
    cp ui.xml "dumps/$1.xml"
  else
    rm -f "dumps/$1.xml"
    near shot "$1: no dump"
  fi
}

# find <regex> [uifind options]: the control on the screen now in ui.xml (no new dump); EMU_AT, EMU_WHY;
# 0 - one, 1 - none, 2 - two or more, 3 - in the dump but hidden
find_ui() {
  local rc
  EMU_AT=$(uifind ui.xml "$@" 2> .emu_err); rc=$?
  EMU_WHY=$(tr '\n' ';' < .emu_err)
  return $rc
}

# wait_ui <regex> [seconds] [uifind options]: until one control with that name is on the screen. At least
# one look, however short the time (the old copies made $((2 / 3)) = 0 looks and failed always, T-498);
# one look takes EMU_POLL seconds. Return: 0, or the code of the last look (1, 2, 3) with EMU_WHY.
# Found later than 2/3 of the time (3 looks or more) - "~~ near wait" in steps.log
wait_ui() {
  local rx=$1 secs=${2:-30} polls i rc=1
  [ $# -ge 2 ] && shift 2 || shift $#
  polls=$(( (secs + EMU_POLL - 1) / EMU_POLL ))
  [ "$polls" -ge 1 ] || polls=1
  for i in $(seq 1 "$polls"); do
    if dump; then
      find_ui "$rx" "$@"; rc=$?
      if [ $rc -eq 0 ]; then
        # found in the last third of the time: the next run on a slower machine may miss it
        [ "$polls" -ge 3 ] && [ $((i * 3)) -gt $((polls * 2)) ] && near wait "'$rx' only at look $i of $polls"
        return 0
      fi
    else
      rc=1; EMU_WHY="no dump"
    fi
    [ "$i" -lt "$polls" ] && emu_sleep $((EMU_POLL > 2 ? EMU_POLL - 2 : 1))
  done
  return $rc
}

# wait_gone <regex> [seconds]: until no control with that name is on the screen
wait_gone() {
  local secs=${2:-30} polls i
  polls=$(( (secs + EMU_POLL - 1) / EMU_POLL ))
  [ "$polls" -ge 1 ] || polls=1
  for i in $(seq 1 "$polls"); do
    dump && [ "$(uifind ui.xml --count "$1")" = 0 ] && return 0
    [ "$i" -lt "$polls" ] && emu_sleep $((EMU_POLL > 2 ? EMU_POLL - 2 : 1))
  done
  return 1
}

# The keyboard is not in the uiautomator dump: over the lower half of the screen it takes the tap
# (42815311112: the tap on a search result typed the suggestion "Model")
ime_shown() { adb shell dumpsys input_method < /dev/null 2>/dev/null | grep -q 'mInputShown=true'; }
hide_keyboard() {
  ime_shown || return 0
  near keyboard "shown over the app: back key"
  adb shell input keyevent 4 < /dev/null > /dev/null 2>&1
  emu_sleep 2
  ime_shown && { fail "the keyboard is still shown"; return 1; }
  return 0
}

# ensure_app: the app on top. A box "… isn't responding": Wait first (the box of the app itself is
# package android too - Close app would kill the app), Close app only for another app's box after Wait
# was tried; any other window - back key; the app's process gone (app_alive) - a failure, no keys. The app's own boxes - the hook qz_dialogs (qz.sh), if defined:
# it closes one and returns 0, or returns 1
ensure_app() {
  local i pkg title anr_seen=""
  for i in 1 2 3 4 5 6; do
    dump || return 0
    pkg=$(uifind ui.xml --package)
    if [ -z "$pkg" ] || [ "$pkg" = "$PKG" ]; then
      if type qz_dialogs > /dev/null 2>&1 && qz_dialogs; then
        continue
      fi
      return 0
    fi
    # the app is gone (a crash): no back key on the launcher - the cause is in the log, not on the screen
    # (T-505 pilot 42860387276: six back keys on the launcher after QZ fell)
    if ! app_alive; then
      fail "the app is not running ($pkg on top) - crashed? see the AndroidRuntime lines of the log"
      return 1
    fi
    if grep -q "t responding" ui.xml; then
      title=$(grep -o 'text="[^"]*t responding"' ui.xml | head -n 1)
      # Close app only after Wait was given a chance (anr_seen), not by the try number: a QZ box closed
      # on try 1 must not make the first ANR box of try 2 a "later" one
      if [ -n "$anr_seen" ] && ! echo "$title" | grep -q -i -E "${EMU_APP_RX:-$PKG}" && find_ui '^Close app$'; then
        near anr "$title: Close app"
      elif anr_seen=1 && find_ui '^Wait$'; then
        near anr "$title: Wait"
      else
        near anr "$title: no button, back key"
        adb shell input keyevent 4 < /dev/null > /dev/null 2>&1
        emu_sleep 3
        continue
      fi
      set -- $EMU_AT
      adb shell input tap "$1" "$2" < /dev/null > /dev/null 2>&1
    else
      near window "$pkg over the app: back key"
      adb shell input keyevent 4 < /dev/null > /dev/null 2>&1
    fi
    emu_sleep 3
  done
  fail "the app is not on top: $pkg"
}

# still [tries]: the screen does not move - two dumps of the same layout (class and place of every node)
# and two frames equal outside the masks (EMU_MASKS, nodes whose text changed, text fields). Leaves the
# last dump in ui.xml and its frame in .emu_f2. Not still after the tries - a near miss, 0 anyway (some
# screens never stop: a running workout); 1 only without a dump
still() {
  local tries=${1:-4} i
  dump || return 1
  cp ui.xml .emu_a.xml
  frame .emu_f1
  for i in $(seq 1 "$tries"); do
    dump || return 1
    frame .emu_f2
    if "$EMU_PY" "$EMU_GH/emu_frame.py" layout .emu_a.xml ui.xml \
       && "$EMU_PY" "$EMU_GH/emu_frame.py" diff .emu_f1 .emu_f2 --dumps .emu_a.xml ui.xml --rows "$EMU_ROWS" \
          $(emu_mask_args) > .emu_diff 2>&1; then
      [ "$i" -gt 1 ] && near moving "the screen was still only after $i looks"
      return 0
    fi
    cp ui.xml .emu_a.xml
    cp .emu_f2 .emu_f1
    emu_sleep 1
  done
  near moving "the screen did not stop in $tries looks: $(cat .emu_diff 2>/dev/null)"
  return 0
}
emu_mask_args() { local m; for m in $EMU_MASKS; do printf -- '--mask %s ' "$m"; done; }

# a11y_build: the TalkBack and ACTION_CLICK driver (A11yDriver.java) as a11y.jar on the device; once
a11y_build() {
  [ -n "$EMU_A11Y" ] && { [ "$EMU_A11Y" = ok ]; return; }
  local sdk jar bt
  sdk=${ANDROID_SDK_ROOT:-$ANDROID_HOME}
  jar=$(ls -d "$sdk"/platforms/android-*/android.jar 2>/dev/null | sort -V | tail -n 1)
  bt=$(ls -d "$sdk"/build-tools/*/ 2>/dev/null | sort -V | tail -n 1)
  mkdir -p drv
  if [ -n "$jar" ] && [ -n "$bt" ] \
     && javac -source 8 -target 8 -bootclasspath "$jar" -d drv "$EMU_GH/A11yDriver.java" >> "$STEPLOG" 2>&1 \
     && "${bt}d8" --lib "$jar" --output a11y.jar drv/*.class >> "$STEPLOG" 2>&1 \
     && adb push a11y.jar /data/local/tmp/a11y.jar < /dev/null > /dev/null 2>&1; then
    EMU_A11Y=ok
  else
    EMU_A11Y=no
    # red, not a near miss: the driver is ours (tools/emu/A11yDriver.java), a compile error must show on
    # the first run, not hide behind the touch fallback (it is not compiled before CI: no javac locally)
    fail "a11y driver not built (javac/d8 output above): ACTION_CLICK steps fall back to a touch"
  fi
  [ "$EMU_A11Y" = ok ]
}

# drv <name> <step...>: run the driver (output in drv/<name>.txt and steps.log). No dump while it runs
drv() {
  local name=$1 args="" a
  shift
  for a in "$@"; do args="$args '$a'"; done
  mkdir -p drv
  say "== drv $name:$args"
  timeout 200 adb shell "CLASSPATH=/data/local/tmp/a11y.jar app_process / A11yDriver$args" < /dev/null > "drv/$name.txt" 2>&1
  cat "drv/$name.txt" >> "$STEPLOG"
  emu_sleep 2
}

# tap_ui <regex> <landing regex> [seconds] [--a11y] [uifind options]: tap a control and see the next screen.
#  before: the control waited for (15 s); hidden above or below - brought into the page by a short swipe;
#          two of that name - a failure (give --first, --below or a closer regex); the keyboard hidden;
#          another window closed; the screen still
#  tap:    at the middle of the visible part (--right N: N px in from its right end); --a11y - the
#          accessibility click on the node instead (the way to the screen under test, not the action
#          under test: it does not go through the touch screen); no driver or no such node - a touch
#  after:  the landing control in [seconds] (30); outcome ok, else no-effect (the frame did not change)
#          or wrong-screen (frames compared below the status bar, EMU_ROWS). A landing that matches any
#          label ('.*', '.+', '^.*$') is refused: it proves nothing; a landing already on the screen
#          before the tap - "~~ near land"
tap_ui() {
  local rx=$1 land=$2 secs=30 a11y="" opts=() rc x y how endx=ui.xml
  shift 2
  if [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; then secs=$1; shift; fi
  while [ $# -gt 0 ]; do
    case $1 in
      --a11y) a11y=1 ;;
      --right|--below|--min) opts+=("$1" "$2"); shift ;;
      *) opts+=("$1") ;;
    esac
    shift
  done
  # not only '.*': '.+', '^.*$', '(.*)' match any label too - a pattern that takes an empty or a
  # random label takes any screen
  if [ -z "$land" ] || printf '\n' | grep -q -E "$land" || printf '%s\n' '~#@!' | grep -q -E "$land"; then
    fail "tap '$rx': landing '$land' proves nothing - name a control of the next screen"
    return 1
  fi
  ensure_app
  hide_keyboard || return 1
  if ! bring_in "$rx" 15 "${opts[@]}"; then
    fail "tap '$rx': $EMU_WHY"
    shot "fail-$(date +%s)"
    return 1
  fi
  still
  find_ui "$rx" "${opts[@]}"; rc=$?
  if [ $rc -ne 0 ]; then
    fail "tap '$rx': gone from the screen before the tap ($EMU_WHY)"
    return 1
  fi
  set -- $EMU_AT
  x=$1; y=$2
  cp .emu_f2 .emu_before 2>/dev/null
  cp ui.xml .emu_before.xml
  # the landing already shown: "ok" would not prove the tap did anything
  if find_ui "$land"; then
    near land "'$land' is on the screen before the tap on '$rx': ok proves nothing"
  fi
  how=touch
  if [ -n "$a11y" ]; then
    if a11y_build && a11y_click "$rx"; then
      how=a11y
    else
      near a11y "'$rx': ACTION_CLICK did not work, a touch at $x $y"
    fi
  fi
  [ "$how" = touch ] && adb shell input tap "$x" "$y" < /dev/null > /dev/null 2>&1
  say "tap '$rx': $how at $x $y"
  emu_sleep 1
  frame .emu_after
  if wait_ui "$land" "$secs"; then
    say "outcome '$rx': ok ('$land' shown)"
    return 0
  fi
  # no-effect: the frame right after the tap and the last one (with the last dump of wait_ui) both
  # equal the one before, outside the status bar and the nodes whose text changed (a field's cursor)
  frame .emu_end
  [ -s ui.xml ] || endx=.emu_before.xml   # the last dump failed: no text masks, the frames alone
  if "$EMU_PY" "$EMU_GH/emu_frame.py" diff .emu_before .emu_after --rows "$EMU_ROWS" $(emu_mask_args) \
       > /dev/null 2>&1 \
     && "$EMU_PY" "$EMU_GH/emu_frame.py" diff .emu_before .emu_end --dumps .emu_before.xml "$endx" \
          --rows "$EMU_ROWS" $(emu_mask_args) > /dev/null 2>&1; then
    say "outcome '$rx': no-effect"
    fail "after '$rx': nothing changed on the screen, '$land' not shown"
  else
    say "outcome '$rx': wrong-screen"
    fail "after '$rx': '$land' not shown ($EMU_WHY)"
  fi
  shot "fail-$(date +%s)"
  return 1
}

# a11y_click <regex>: ACTION_CLICK on the visible node with that exact name (the driver needs the
# name, not a regex: the name is taken from the dump)
a11y_click() {
  local name
  find_ui "$1" || return 1
  name=$(uifind ui.xml "$1" --name 2>/dev/null) || return 1
  drv click "click=$name"
  grep -q "returned true" drv/click.txt
}

# bring_in <regex> [seconds] [uifind options]: wait for the control; if it is in the dump but above or below
# the page, short swipes until it is on the screen (8bfbd0b4f: a node under the header at y 48 and 310).
# 0 - on the screen (EMU_AT), else 1 with EMU_WHY
bring_in() {
  local rx=$1 secs=${2:-15} i rc
  [ $# -ge 2 ] && shift 2 || shift $#
  wait_ui "$rx" "$secs" "$@"; rc=$?
  for i in 1 2 3 4 5 6; do
    [ $rc -eq 3 ] || break
    case $EMU_WHY in
      *above*) near scroll "'$rx' above the page: swipe down"; swipe_page down short ;;
      *below*) near scroll "'$rx' below the page: swipe up"; swipe_page up short ;;
      *) break ;;
    esac
    dump && { find_ui "$rx" "$@"; rc=$?; }
  done
  return $rc
}

# swipe_page up|down [short]: a finger up (the page goes on) or down, in the page band of the last dump,
# in the middle of the screen (by the left edge the page did not move, 42711319419; x by EMU_SWIPE_X)
swipe_page() {
  local band top bot x a b
  band=$(uifind ui.xml --band 2>/dev/null) || band="252 2390"
  set -- "$1" "$2" $band
  top=$3; bot=$4
  x=${EMU_SWIPE_X:-720}
  if [ "$2" = short ]; then
    a=$(( (top + bot) / 2 + 200 )); b=$(( (top + bot) / 2 - 200 ))
  else
    a=$(( bot - (bot - top) / 6 )); b=$(( top + (bot - top) / 6 ))
  fi
  if [ "$1" = up ]; then
    adb shell input swipe "$x" "$a" "$x" "$b" 400 < /dev/null > /dev/null 2>&1
  else
    adb shell input swipe "$x" "$b" "$x" "$a" 400 < /dev/null > /dev/null 2>&1
  fi
  emu_sleep 1
}

# scroll_to <regex> [swipes] [uifind options]: swipe the page until the control is on the screen. The end
# of the page - the layout did not change after a swipe. Not reached - a frame not-reached-<time>, "!!"
scroll_to() {
  local rx=$1 max=${2:-25} i rc
  [ $# -ge 2 ] && shift 2 || shift $#
  for i in $(seq 1 "$max"); do
    dump || { emu_sleep 1; continue; }
    find_ui "$rx" "$@"; rc=$?
    if [ $rc -eq 0 ]; then
      say "scrolled to '$rx' ($i): at $EMU_AT"
      [ "$i" -gt 6 ] && near scroll "'$rx' after $i looks"
      return 0
    fi
    if [ $rc -eq 2 ]; then
      fail "scroll to '$rx': two or more on the screen ($EMU_WHY)"
      return 1
    fi
    cp ui.xml .emu_s.xml
    case $EMU_WHY in
      *above*) swipe_page down short ;;
      *) swipe_page up ;;
    esac
    # the end: the same nodes with the same texts (by the layout only, rows of one height scrolled by
    # whole rows would look like the end)
    if dump && "$EMU_PY" "$EMU_GH/emu_frame.py" same .emu_s.xml ui.xml; then
      fail "scroll to '$rx': end of the page, not found"
      shot "not-reached-$(date +%s)"
      return 1
    fi
  done
  fail "scroll to '$rx': not reached in $max swipes ($EMU_WHY)"
  shot "not-reached-$(date +%s)"
  return 1
}

# scroll_top [swipes]: down until the screen stops changing (the old copies swiped five times blind)
scroll_top() {
  local i
  for i in $(seq 1 "${1:-15}"); do
    dump || return 1
    cp ui.xml .emu_s.xml
    swipe_page down
    dump && "$EMU_PY" "$EMU_GH/emu_frame.py" same .emu_s.xml ui.xml && return 0
  done
  fail "scroll to the top: the page still moves after ${1:-15} swipes"
}

# survey_page <name> [swipes]: the page from the top to its end, a frame and a dump of every screen
# (survey-<name>-NN) - for writing the steps by what is on the screen, not by the QML code;
# check_emu_script.py --dumps <dir> checks the regexes of a scenario against them
survey_page() {
  local i
  ensure_app || { fail "survey $1: the app is not on top"; return 1; }
  scroll_top
  for i in $(seq -w 1 "${2:-30}"); do
    shot "survey-$1-$i"
    cp "dumps/survey-$1-$i.xml" .emu_s.xml 2>/dev/null || { fail "survey $1: no dump of screen $i"; return 1; }
    swipe_page up
    dump && "$EMU_PY" "$EMU_GH/emu_frame.py" same .emu_s.xml ui.xml && { say "survey $1: end of the page at $i"; return 0; }
  done
  near survey "$1: not at the end after ${2:-30} screens"
}

# app_frame <shot> <what>: the frame has a dump, and it is a screen of the app - a check on the launcher
# or another window proves nothing ("not on the screen" passed there: T-505 pilot 42860387276)
app_frame() {
  local pkg
  if [ ! -s "dumps/$1.xml" ]; then
    fail "check $1: $2: no dump of the frame"
    return 1
  fi
  pkg=$(uifind "dumps/$1.xml" --package)
  if [ -n "$pkg" ] && [ "$pkg" != "$PKG" ]; then
    fail "check $1: $2: the frame is not of the app ($pkg on top)"
    return 1
  fi
}

# expect <shot> <regex> <what> [uifind options]: the control is on the screen in the dump of that frame -
# not only in the tree (a page kept under the next one, the header copy under the menu: T-392, T-487)
expect() {
  local s=$1 rx=$2 what=$3 n
  shift 3
  app_frame "$s" "$what" || return 1
  n=$(uifind "dumps/$s.xml" --count "$rx" "$@")
  if [ "${n:-0}" -ge 1 ]; then
    say "check $s: $what: OK"
    return 0
  fi
  uifind "dumps/$s.xml" "$rx" "$@" > /dev/null 2> .emu_err
  fail "check $s: $what: '$rx' not on the screen $(tr '\n' ' ' < .emu_err)"
}

# expect_not <shot> <regex> <what>: no such control on the screen of that frame
expect_not() {
  local n
  app_frame "$1" "$3" || return 1
  n=$(uifind "dumps/$1.xml" --count "$2")
  if [ "${n:-1}" = 0 ]; then
    say "check $1: $3: OK"
  else
    fail "check $1: $3: '$2' is on the screen"
  fi
}

# checked_of <dump> <regex>: true/false of the switch with that name on the screen, empty if none
checked_of() {
  local r
  r=$(uifind "$1" "$2" --checkable 2>/dev/null) || return 1
  set -- $r
  echo "$4"
}

# row_toggle <shot> <regex> [--right N]: the switch row off by a tap and on again - frames <shot>,
# <shot>-off, <shot>-on and a check that the state went b -> !b -> b
row_toggle() {
  local s=$1 rx=$2 b a c x y
  shift 2
  if ! bring_in "$rx" 15 --checkable; then
    fail "$s: no switch row '$rx' ($EMU_WHY)"; shot "$s-none"; return 1
  fi
  still
  shot "$s"
  find_ui "$rx" --checkable "$@" || { fail "$s: '$rx' gone ($EMU_WHY)"; return 1; }
  set -- $EMU_AT
  x=$1; y=$2; b=$4
  say "tap row '$rx' at $x $y (checked $b)"
  adb shell input tap "$x" "$y" < /dev/null > /dev/null 2>&1
  emu_sleep 3
  shot "$s-off"
  a=$(checked_of "dumps/$s-off.xml" "$rx")
  adb shell input tap "$x" "$y" < /dev/null > /dev/null 2>&1
  emu_sleep 3
  shot "$s-on"
  c=$(checked_of "dumps/$s-on.xml" "$rx")
  if [ -n "$b" ] && [ -n "$a" ] && [ "$b" != "$a" ] && [ "$c" = "$b" ]; then
    say "check $s-on: switch row '$rx' off and on again ($b -> $a -> $c): OK"
  else
    fail "check $s-on: switch row '$rx': $b -> $a -> $c"
  fi
}

# install_apk <apk>: a clean install with the permissions a run needs, by API; not installed - red at once
install_apk() {
  local p api
  adb uninstall "$PKG" < /dev/null > /dev/null 2>&1
  adb install "$1" < /dev/null >> "$STEPLOG" 2>&1
  # API 21/23: pm path answers 0 without the package too - look for "package:"
  adb shell pm path "$PKG" < /dev/null 2>/dev/null | grep -q package: || proves_nothing "$1 not installed"
  api=${EMU_API:-$(adb shell getprop ro.build.version.sdk < /dev/null | tr -d '\r')}
  for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION; do
    adb shell pm grant "$PKG" "android.permission.$p" < /dev/null > /dev/null 2>&1
  done
  # API 23-32: the box "access photos, media, and files" over the app (T-415; on API 30 too - the STORAGE box
  # of the T-505 pilot 42862769060); from API 33 READ_MEDIA_* replace them
  [ "$api" -lt 33 ] && for p in READ_EXTERNAL_STORAGE WRITE_EXTERNAL_STORAGE; do
    adb shell pm grant "$PKG" "android.permission.$p" < /dev/null > /dev/null 2>&1
  done
  [ "$api" -ge 31 ] && for p in BLUETOOTH_ADVERTISE BLUETOOTH_CONNECT BLUETOOTH_SCAN; do
    adb shell pm grant "$PKG" "android.permission.$p" < /dev/null > /dev/null 2>&1
  done
  [ "$api" -ge 33 ] && adb shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS < /dev/null > /dev/null 2>&1
  [ "$api" -ge 30 ] && adb shell appops set "$PKG" MANAGE_EXTERNAL_STORAGE allow < /dev/null > /dev/null 2>&1
  # API 34+: without health.WRITE_* the Health Connect onboarding comes over the app (T-276, T-385)
  [ "$api" -ge 34 ] && for p in EXERCISE DISTANCE TOTAL_CALORIES_BURNED HEART_RATE POWER SPEED \
      CYCLING_PEDALING_CADENCE ELEVATION_GAINED STEPS STEPS_CADENCE HEART_RATE_VARIABILITY; do
    adb shell pm grant "$PKG" "android.permission.health.WRITE_$p" < /dev/null > /dev/null 2>&1
  done
  say "== installed $1"
}

# TalkBack on and off (image API 35 with Google TalkBack; recipe - notes/talkback-in-emulator-2026-10-15.md).
# adb root restarts adbd: logcat_start again after it
TB_PKG=com.google.android.marvin.talkback
tb_on() {
  local dir
  adb shell am force-stop "$TB_PKG" < /dev/null > /dev/null 2>&1
  adb root >> "$STEPLOG" 2>&1
  adb wait-for-device
  emu_sleep 3
  printf '%s\n' "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>" '<map>' \
    '    <boolean name="pref_tts_overlay" value="true" />' \
    '    <boolean name="first_time_user" value="false" />' \
    '    <boolean name="pref_has_performed_restore_key" value="true" />' '</map>' > tbprefs.xml
  adb push tbprefs.xml /data/local/tmp/tbprefs.xml < /dev/null > /dev/null 2>&1
  for dir in "/data/user_de/0/$TB_PKG" "/data/data/$TB_PKG"; do
    adb shell "mkdir -p $dir/shared_prefs && cp /data/local/tmp/tbprefs.xml $dir/shared_prefs/${TB_PKG}_preferences.xml \
      && chown -R \$(stat -c %u:%g $dir) $dir/shared_prefs && chmod 771 $dir/shared_prefs \
      && chmod 660 $dir/shared_prefs/${TB_PKG}_preferences.xml && restorecon -R $dir/shared_prefs" < /dev/null >> "$STEPLOG" 2>&1
  done
  adb shell "rm -rf /data/local/tmp/tbshots; mkdir -p /data/local/tmp/tbshots" < /dev/null > /dev/null 2>&1
  adb shell settings put secure enabled_accessibility_services "$TB_PKG/$TB_PKG.TalkBackService" < /dev/null >> "$STEPLOG" 2>&1
  adb shell settings put secure accessibility_enabled 1 < /dev/null >> "$STEPLOG" 2>&1
  adb shell settings put secure touch_exploration_enabled 1 < /dev/null >> "$STEPLOG" 2>&1
  emu_sleep 15
  say "== talkback on"
}
tb_off() {
  say "== talkback off"
  adb shell settings put secure touch_exploration_enabled 0 < /dev/null >> "$STEPLOG" 2>&1
  adb shell settings put secure enabled_accessibility_services null < /dev/null >> "$STEPLOG" 2>&1
  adb shell settings put secure accessibility_enabled 0 < /dev/null >> "$STEPLOG" 2>&1
}
# tb_check <regex> <drv name> <what>: a line of the driver output matches
tb_check() {
  if grep -q -E "$1" "drv/$2.txt"; then
    say "check $2: $3: OK"
  else
    fail "check $2: $3: no /$1/ in drv/$2.txt"
  fi
}

# finish: ANR or crash of the app in the whole log, at least one check, steps.log to the job log, the code
finish() {
  logcat_stop
  say "== ANR / crash in the whole log:"
  if [ -s full_logcat.txt ] && grep -a -E "ANR in $PKG|Process: $PKG,|Fatal signal.*${PKG##*.}" full_logcat.txt >> "$STEPLOG"; then
    fail "check log: ANR or crash"
  else
    say "none"
  fi
  grep -q -E "^check " "$STEPLOG" || fail "no check ran: the run proves nothing"
  say "== near misses: $(grep -c '^~~ near' "$STEPLOG"), failures: $(grep -c '^!! ' "$STEPLOG")"
  cat "$STEPLOG"
  exit "$FAILED"
}
