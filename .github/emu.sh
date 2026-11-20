#!/bin/bash
# Test only (T-643): the buttons of the settings pages on UiButton (Button -> UiButton in settings.qml,
# settings-tts.qml, settings-treadmill-inclination-override.qml).
#   base (apk-base): test/t643-master = origin/master a23bb201d + CI trim
#   head (apk-head): test/t643 = fix/settings-ok-uibutton (a23bb201d + the PR) + CI trim
# Classic look: the same on both sides (frames compared after the run, emu_frame.py diff).
# Modern look (UiButton.qml of master): an OK right after a list is hidden and pressed by the pick
# (applyOnSelect, :21-23, :35-36), unless applyOnSelect: false (App Language: settings.qml ~2896); an OK
# after a field with savedText is grey while unchanged and filled with the accent on a change (savePending, :32).
# Cases, on each side x = b | h:
#   xc  classic: General Options - App Language and Weight rows, the Gender row (OK there on both sides)
#   xl  modern light: the same rows; Gender row - OK on b, none on h; App Language row - OK on both
#   xd  modern dark: the same frames as xl
#   xw  modern light: a change in Player Weight (75 -> 751), the frame - OK grey before, accent after on h
#   xs  modern light: Female picked in the Gender list - h saves at once ("Setting saved!"), b does not
#   xt  modern light / xu classic: TTS section, the row "Summary Each Seconds:" with its OK
#   xi  modern light / xj classic: Treadmill Options > Inclination Overrides, "Inclination Override Gain:"
. .github/lib.sh
. .github/qz.sh

# a device name with no device keeps the first-run wizard closed (homeform.h firstRun())
NODEV="bluetooth_lastdevice_name=T643-NONE"
LIGHT="ui_modern=true ui_theme_mode=light"
DARK="ui_modern=true ui_theme_mode=dark"
CLASSIC="ui_modern=false"

# settings.qml of the branch (a23bb201d + PR): General Options :2862, App Language :2875, Player Weight :2932
# (SettingsNumberField, name in the dump - its value, default 75), Gender :3081 (ValueComboBox, OK okSex :3096)
GEN_SEC='^General Options$'
LANG_LABEL='^App Language:$'
WEIGHT_LABEL='^Player Weight.*'
GENDER_LABEL='^Gender:$'
# settings-tts.qml :31 the page title, :57 "Summary Each Seconds:" with OK :74
TTS_SEC='^TTS \(Text to Speech\) Settings 🔊$'
TTS_LAND='^TTS Enabled$'
TTS_ROW='^Summary Each Seconds:$'
# Treadmill Options :11690, first row "Treadmill as a Bike"; Inclination Overrides :12147 (the page
# settings-treadmill-inclination-override.qml): "Inclination Override Gain:" :41 with OK :58
TM_SEC='^Treadmill Options$'
TM_LAND='^Treadmill as a Bike$'
INC_SEC='^Inclination Overrides$'
INC_LAND='^Treadmill Inclination Overrides$'
INC_ROW='^Inclination Override Gain:$'

# row_ok <shot> <label regex> <expected count> <what>: the OK buttons in the row of that label
row_ok() {
  local s=$1 rx=$2 want=$3 what=$4 n rc
  n=$("$EMU_PY" "$EMU_GH/t643_row.py" "dumps/$s.xml" "$rx")
  rc=$?
  if [ "$rc" != 0 ]; then
    fail "check $s: $what: label '$rx' - exit $rc (2 none, 3 two)"
    return 1
  fi
  if [ "$n" = "$want" ]; then
    say "check $s: $what: $n OK in the row: OK"
  else
    fail "check $s: $what: $n OK in the row, expected $want"
  fi
}

# gen_open <case> <look keys>: the settings, General Options open
gen_open() {
  local c=$1
  shift
  # shellcheck disable=SC2086 # the look keys are words
  start_case "$c" "$@" $NODEV || return 1
  settings_open || { shot "$c-0-no-settings" now; return 1; }
  tap_ui "$GEN_SEC" "$LANG_LABEL" --land-below || { shot "$c-0-closed" now; return 1; }
}

# rows_case <case> <gender OK expected> <look keys>: frames of the top rows and of the Gender row
rows_case() {
  local c=$1 gok=$2
  shift 2
  gen_open "$c" "$@" || return 1
  scroll_to "$WEIGHT_LABEL" 10 --exact || { shot "$c-1-no-weight" now; return 1; }
  settle
  shot "$c-1-top"
  row_ok "$c-1-top" "$LANG_LABEL" 1 'App Language keeps its OK (applyOnSelect: false)'
  row_ok "$c-1-top" '^75$' 1 'Player Weight OK'
  scroll_to "$GENDER_LABEL" 20 --exact || { shot "$c-2-no-gender" now; return 1; }
  settle
  shot "$c-2-gender"
  row_ok "$c-2-gender" "$GENDER_LABEL" "$gok" 'Gender OK'
}

# weight_case <case>: a change in Player Weight - the OK before and after
weight_case() {
  local c=$1
  gen_open "$c" $LIGHT || return 1
  scroll_to '^75$' 10 --exact || { shot "$c-1-no-field" now; return 1; }
  settle
  shot "$c-1-before"
  tap_ui '^75$' '^75$' 10 || { shot "$c-1-no-focus" now; return 1; }
  type_text 1 '^751$' || return 1
  settle
  shot "$c-2-after"
  row_ok "$c-2-after" '^751$' 1 'Player Weight OK after the change'
}

# select_case <case> <side>: Female picked in the Gender list
select_case() {
  local c=$1 side=$2 n i
  gen_open "$c" $LIGHT || return 1
  scroll_to "$GENDER_LABEL" 20 --exact || { shot "$c-1-no-gender" now; return 1; }
  settle
  tap_ui '^Male$' '^Female$' 10 || { shot "$c-1-no-list" now; return 1; }
  shot "$c-2-list"
  tap_ui '^Female$' "$GENDER_LABEL" 10 || { shot "$c-2-no-pick" now; return 1; }
  # the toast "Setting saved!" is not in the accessibility tree (no dump of notes/emu has it) - only the frame;
  # the sign is qz.conf: Qt.labs.settings writes the change after its delay, QSettings syncs it to the file
  shot "$c-3-picked" now
  i=0
  while [ "$i" -lt 5 ]; do
    emu_sleep 3
    n=$(adb shell "run-as $PKG cat '$CONF'" < /dev/null 2>/dev/null | tr -d '\r' | grep -c '^sex=Female$')
    [ "${n:-0}" -ge 1 ] && break
    i=$((i + 1))
  done
  say "$c: sex=Female in qz.conf: ${n:-0} (looks: $(( i < 5 ? i + 1 : 5 )), 3 s apart)"
  if [ "$side" = h ]; then
    # UiButton.applySelection (Qt.callLater after onActivated) presses okSex: settings.sex = "Female"
    [ "${n:-0}" -ge 1 ] && say "check $c: the pick saved at once: OK" \
      || fail "check $c: sex=Female not in qz.conf 15 s after the pick"
  else
    [ "${n:-0}" = 0 ] && say "check $c: master does not save on the pick: OK" \
      || fail "check $c: sex=Female in qz.conf on master without OK"
    row_ok "$c-3-picked" "$GENDER_LABEL" 1 'Gender OK on master'
  fi
}

# page_case <case> <look keys> <section> <landing> <acc|page> [<inner page> <inner landing>] -- <row>
# acc - the section is an accordion (its landing may open below the page: --land-below); page - a NewPageElement
# (stackView.push: the landing is the top of a new page, the full wait of tap_ui, no swipes). The inner one is a page
page_case() {
  local c=$1 keys=$2 sec=$3 land=$4 kind=$5 row below=()
  shift 5
  [ "$kind" = acc ] && below=(--land-below)
  # shellcheck disable=SC2086 # the look keys are words
  start_case "$c" $keys $NODEV || return 1
  settings_open || { shot "$c-0-no-settings" now; return 1; }
  scroll_to "$sec" 30 --exact || { shot "$c-0-no-section" now; return 1; }
  tap_ui "$sec" "$land" --first "${below[@]}" || { shot "$c-0-closed" now; return 1; }
  if [ "$1" != -- ]; then
    scroll_to "$1" 30 --exact || { shot "$c-0-no-inner" now; return 1; }
    tap_ui "$1" "$2" || { shot "$c-0-inner-closed" now; return 1; }
    shift 2
  fi
  shift
  row=$1
  scroll_to "$row" 20 --exact || { shot "$c-1-no-row" now; return 1; }
  settle
  shot "$c-1-row"
  row_ok "$c-1-row" "$row" 1 'the OK of the row'
}

emu_init
logcat_start

for side in b h; do
  if [ "$side" = b ]; then apk=apk-base/android-debug.apk; else apk=apk-head/android-debug.apk; fi
  side_on "$side" "$apk" || continue
  say "== $side: start"
  install_apk "$apk"
  if [ "$side" = b ]; then gok=1; else gok=0; fi
  rows_case "${side}c" 1 $CLASSIC
  rows_case "${side}l" "$gok" $LIGHT
  rows_case "${side}d" "$gok" $DARK
  weight_case "${side}w"
  select_case "${side}s" "$side"
  page_case "${side}t" "$LIGHT" "$TTS_SEC" "$TTS_LAND" page -- "$TTS_ROW"
  page_case "${side}u" "$CLASSIC" "$TTS_SEC" "$TTS_LAND" page -- "$TTS_ROW"
  page_case "${side}i" "$LIGHT" "$TM_SEC" "$TM_LAND" acc "$INC_SEC" "$INC_LAND" -- "$INC_ROW"
  page_case "${side}j" "$CLASSIC" "$TM_SEC" "$TM_LAND" acc "$INC_SEC" "$INC_LAND" -- "$INC_ROW"
done

finish
