# emu-lib: tools/emu/qz.sh sha 2f9f68bbfe25 - edit there, then tools/emu/sync.py (T-505)
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
# and the English words only, all 12 uk cases "home page not shown", ~22 min. On the home page it finds two
# controls at once (Pause and Stop): every wait_ui/find_ui/tap_ui of it - with --first, or it is "ambiguous"
# on the very page it waits for (T-575 lesson 2, T-717 lesson 1)
HOME_RX=${HOME_RX:-'^(Start|Stop|Pause|Старт|Стоп|Пауза|Stopp)$'}
# The home page is ready (start_case waits for it: 25 s of looks): the support button shows on a home page with
# no speed and power (SupportHelpButton.qml). A case with a running workout never gets it - HOME_READY_RX=
# (empty) before start_case turns the wait off. The same languages (uk, ru, de)
HOME_READY_RX=${HOME_READY_RX-'^(Contact QZ support|Зв’язатися зі службою підтримки QZ|Связаться со службой поддержки QZ|QZ-Support kontaktieren)$'}

# put_conf key=value ...: qz.conf of the app (log_debug, ui_modern_new_install_checked=true and, below API 30,
# skipLocationServicesDialog added unless given); not written - red at once (T-346: the file did not arrive, the run went on).
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
    # the first start of the modern look decided already (homeform::startModernForNewInstall(), master since
    # PR 5868): else a QZ with no device turns ui_modern on, any other one asks "Try the new interface?" over the
    # home page of the classic look (T-606 lesson 1: bc and hc "home page not shown"). A case about that start
    # passes ui_modern_new_install_checked=false
    case " $* " in *" ui_modern_new_install_checked="*) ;; *) printf 'ui_modern_new_install_checked=true\n' ;; esac
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

# app_dir: the folder of the app's own files (training/, QZTemplates, logs) on this API - homeform::getWritableAppDir()
# (homeform.cpp:1829 of master): Android 14+ (API 34+) or android_documents_folder=true in the last put_conf -
# /sdcard/Documents/QZ, else /sdcard/Android/data/$PKG/files (T-596 lesson 7: a cleanup by the path of API 35 left
# the workout on API 30 and the case asked "replace it?")
app_dir() {
  local api
  api=${EMU_API:-$(adb shell getprop ro.build.version.sdk < /dev/null | tr -d '\r')}
  if [ "${api:-0}" -ge 34 ] || grep -q '^android_documents_folder=true' qz.conf 2> /dev/null; then
    echo /sdcard/Documents/QZ
  else
    echo "/sdcard/Android/data/$PKG/files"
  fi
}

# rm_app_file <path in app_dir> ...: removed as the app (su <uid>,<uid>,9997 - shell may not remove a file of the
# app on API 30+, run-as does not reach /sdcard), then ls - still there: red at once
rm_app_file() {
  local uid dir f
  dir=$(app_dir)
  uid=$(app_uid)
  [ -n "$uid" ] || proves_nothing "rm_app_file $*: $PKG not installed"
  for f in "$@"; do
    adb shell "su $uid,$uid,9997 sh -c 'rm -rf \"$dir/$f\"'" < /dev/null >> "$STEPLOG" 2>&1
    if dev_exists "$dir/$f"; then
      proves_nothing "rm_app_file: $dir/$f still there"
    fi
    say "== removed $dir/$f"
  done
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

# am_start_problem <answer of am start -W>: what is wrong with the start, one line; empty - QZ started. A line
# "Error..." or "Warning..." (ActivityManagerShellCommand: "Warning: Activity not started, its current task has been
# brought to the front" - another window is on top of the task of QZ), no "Status: ok", "Activity:" not of $PKG.
# T-719 lesson 1: the screen recording window of Android (peloton_bike_ocr) stayed in the task of QZ - the next 3
# cases said only "home page not shown"
am_start_problem() {
  local line bad="" status=""
  while IFS= read -r line; do
    case $line in
      Error*|Warning*) [ -z "$bad" ] && bad=$line ;;
      "Status: "*) status=${line#Status: } ;;
      "Activity: "*) case ${line#Activity: } in "$PKG"/*) ;; *) [ -z "$bad" ] && bad=$line ;; esac ;;
    esac
  done <<< "$1"
  if [ -z "$bad" ] && [ "$status" != ok ]; then
    bad="Status: ${status:-none} (no 'Status: ok')"
  fi
  printf '%s' "$bad"
}

# start_case <name> [key=value ...]: QZ stopped, qz.conf written, started (am start -W: a start that did not bring
# QZ up - its reason and mCurrentFocus in steps.log; no home page after it - "!! <name>: am start: ...", the home
# page after all - "~~ near am-start", not red: ensure_app may close the window by Back), the home page; the pid of the
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
  # landscape left by another case (it returned after `rotate land "$c"` - a failed step): back to portrait
  # before the start, or on API 30 every case after it fails "not landscape after the start" (T-640; T-629,
  # lesson 1). Turned by this case or by a rotate with no case - the check below stays; so a case meant to start
  # in landscape turns with its own name: `rotate land "$c"; start_case "$c"` (T-609 order)
  if [ "$EMU_ROT" = land ] && [ -n "$EMU_ROT_CASE" ] && [ "$EMU_ROT_CASE" != "$name" ]; then
    near rotate "$name: landscape left by $EMU_ROT_CASE - turned back"
    rotate port "$name" || return 1
  fi
  adb shell am force-stop "$PKG" < /dev/null > /dev/null 2>&1
  emu_sleep 2
  put_conf "$@"
  local am_out am_bad
  am_out=$(adb shell am start -W -n "$PKG/$PKG.CustomQtActivity" < /dev/null 2>&1 | tr -d '\r')
  am_bad=$(am_start_problem "$am_out")
  if [ -n "$am_bad" ]; then
    local focus
    focus=$(adb shell dumpsys window < /dev/null 2>&1 | tr -d '\r' | grep -m1 mCurrentFocus | sed 's/^ *//')
    say "   am start: $am_bad; ${focus:-mCurrentFocus: none}"
  fi
  if ! wait_home; then
    [ -n "$am_bad" ] && fail "$name: am start: $am_bad"
    fail "$name: home page not shown"
    shot "$name-0-no-home" now
    return 1
  fi
  # the home page came after all (wait_home -> ensure_app closed the window by Back): not red, the window is a lead
  [ -n "$am_bad" ] && near am-start "$name: $am_bad - the home page came after all"
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

# The texts of the settings page and its search (main.qml :1750 "Search settings", settings.qml "Changed",
# "Searching...", "Search results (N)", "No settings found"), English; search_lang de - the German ones of
# src/translations/qdomyos-zwift_de.ts (master a5104927e, seen on the screen in T-693 run 45100197234, case hg)
search_lang() {
  case $1 in
    en) SET_ENTRY_RX='^Settings$'; SET_PAGE_RX='^General Options$'; SEARCH_RX='^Search settings$'
        SEARCH_BAR_RX='^Changed$'; SEARCH_BUSY_RX='^Searching\.\.\.$'; SEARCH_RESULTS_RX='^Search results \([0-9]+\)$'
        SEARCH_NONE_RX='^No settings found$' ;;
    de) SET_ENTRY_RX='^Einstellungen$'; SET_PAGE_RX='^Allgemeine Optionen$'
        SEARCH_RX='^Einstellungen (durchsuchen|suchen)$'; SEARCH_BAR_RX='^Geändert$'; SEARCH_BUSY_RX='^Suche\.\.\.$'
        SEARCH_RESULTS_RX='^Suchergebnisse \([0-9]+\)$'; SEARCH_NONE_RX='^Keine Einstellungen gefunden$' ;;
    *) fail "search_lang '$1': en or de (other languages - set SET_*_RX and SEARCH_*_RX yourself)"; return 1 ;;
  esac
}
SET_ENTRY_RX=${SET_ENTRY_RX:-'^Settings$'}
SET_PAGE_RX=${SET_PAGE_RX:-'^General Options$'}
SEARCH_RX=${SEARCH_RX:-'^Search settings$'}
SEARCH_BAR_RX=${SEARCH_BAR_RX:-'^Changed$'}
SEARCH_BUSY_RX=${SEARCH_BUSY_RX:-'^Searching\.\.\.$'}
SEARCH_RESULTS_RX=${SEARCH_RESULTS_RX:-'^Search results \([0-9]+\)$'}
SEARCH_NONE_RX=${SEARCH_NONE_RX:-'^No settings found$'}

# settings_open: the settings page from the menu
settings_open() {
  open_drawer "$SET_ENTRY_RX" || return 1
  tap_ui "$SET_ENTRY_RX" "$SET_PAGE_RX"
}

# settings_search_bar <case>: the search bar open ("Changed" on the screen) - the settings page opened first when the
# header has no "Search settings" (the button is on that page only, T-693 lesson 1). For the list "Changed" - then
# tap_ui "$SEARCH_BAR_RX" ...; for a query - settings_search below
settings_search_bar() {
  local c=$1
  if ! { dump && find_ui "$SEARCH_RX" --first; }; then
    settings_open || { shot "$c-0-no-settings" now; fail "$c: settings not opened"; return 1; }
    settle
  fi
  tap_ui "$SEARCH_RX" "$SEARCH_BAR_RX" 15 --first || { shot "$c-0-no-search" now; return 1; }
  settle
}

# settings_search <case> <query> [<result rx>]: the settings search bar opened from the header of the settings page
# - the page opened first (settings_open) when the header has no "Search settings": the button is on that page
# only (T-693 lesson 1, run 45091567599: the copy of T-672 tapped it on the home page, no check made); the query
# typed (type_text: letters, digits, inner spaces), the answer waited for, the keyboard down, the frame
# <case>-1-results shot (its dump - for expect/expect_not of the caller). <result rx>: waited for a while after
# "Search results (N)" (the cards come after the count); not there - no failure, the caller's expect decides.
# Return: 0 - results, 2 - "No settings found", 1 - no answer (a failure) or the query not typed on API 30 (no
# failure, "~~ near input"): typing into this field by adb never worked there - the caret jumps to the start after
# the first key, "og sizec" (T-693 lesson 3, qz-ci-build "Шаги сценария"; other APIs not seen failing); a scheme of
# typing is not to be guessed by runs - the text cases are proved on API 35. The first letter taken at a second try
# may be taken twice ("ccog size", type_text): "No settings found" then proves nothing - a failure, 1 (a base side
# with expect_not would pass falsely). Call with the bar closed.
# The card of a result is not the same tree everywhere: t672 45033028030 (bm-1-results) - "Name: value", "Name" and
# the section as own nodes; T-198 45301968970 (master + the switch) - one node "Modern interface: On", the section on
# the frame only. An expect on <case>-1-results - by a dump of that very card on that branch (survey or a pilot run),
# not by a results dump of another card or branch; the name - '^Name(: .*)?$'
settings_search() {
  local c=$1 q=$2 rx=$3 api=${EMU_API:-35} answer try
  if [ "$api" = 30 ]; then
    near input "$c: settings search '$q' not typed on API $api - adb typing into the search field fails there (T-693 lesson 3)"
    say "== $c: settings search skipped on API $api"
    return 1
  fi
  settings_search_bar "$c" || return 1
  answer="$SEARCH_BUSY_RX|$SEARCH_RESULTS_RX|$SEARCH_NONE_RX"
  type_text "$q" "$answer" "$answer" 20 || return 1
  try=$(grep -a "^type '$q': the first letter taken at try " "$STEPLOG" | tail -n 1)
  try=${try##* }
  wait_gone "$SEARCH_BUSY_RX" 30 || near search "$c: '$SEARCH_BUSY_RX' still shown after 30 s"
  hide_keyboard || return 1
  settle
  if wait_ui "$SEARCH_NONE_RX" 2; then
    shot "$c-1-results"
    if [ "${try:-1}" != 1 ]; then
      fail "$c: no settings found for '$q', its first letter taken at try $try - maybe typed twice, proves nothing"
      return 1
    fi
    say "$c: settings search '$q': no settings found"
    return 2
  fi
  if ! wait_ui "$SEARCH_RESULTS_RX" 20; then
    shot "$c-1-results" now
    fail "$c: no answer of the settings search to '$q' ($EMU_WHY)"
    return 1
  fi
  [ -z "$rx" ] || wait_ui "$rx" 10 --not-edit || near search "$c: '$rx' not shown after the count of results"
  shot "$c-1-results"
  say "$c: settings search '$q': $(uifind ui.xml "$SEARCH_RESULTS_RX" --name 2>/dev/null)"
  return 0
}

# text_size_live <case> <size> <section|-> <label> [screens] [in|out]: the text size changed on the open settings page of
# the modern look, without a restart, and every row of the section cards within its card (T-675; T-664, lesson
# 6: a button with a long uk label widened General UI Options past its card at 130 % set on the open page, the
# scenarios set the size in qz.conf before the start and saw one layout only). The page must be open and the
# own size on: qz.conf ui_text_scale_system=false (the field is read only while the system size is used,
# settings.qml "Text size:" of fork/feat/modern-ui 2026-11-22 :8469-8502). <section> - the title of the section to open
# first ("^General UI Options$", uk "^Загальні параметри інтерфейсу$"), "-" when it is open (the second size);
# <label> - the label of the row ("Text size:", uk "Розмір тексту:", ru "Размер текста:"): the field is named
# "<label> <number>" (Accessible.name). The size goes in by the keys - the end of the field, DEL, type_text -
# and Enter (onAccepted: the same setTextScaleOption as OK, :8494). Proof that it took: the label grew by the
# size (90 % of size/before at least), else the run proves nothing for that size. Then the page is surveyed
# (survey-<case>-NN, at most [screens], 20) and emu_frame.py inside checks its dumps. [want]: in (default) - every
# row within; out - the build with the defect must show it (the case on the base of a proof: a case green on both
# sides did not reproduce the defect, qz-ci-build), rows within are then the failure
# _label_h <label>: SIZE_LABEL_H - the height of the row <label> whole on the page: EMU_AT is the visible part, so
# a row cut by the pinned title of the section (centre above 500) or by the end of the page band is brought in by
# a short swipe first (T-675, review: scroll_to stops at 40 px seen, a cut label - a false "proves nothing")
_label_h() {
  local i at band
  SIZE_LABEL_H=
  for i in 1 2 3; do
    find_ui "^$1\$" --first || { fail "the label '$1' not on the screen ($EMU_WHY)"; return 1; }
    read -r -a at <<< "$EMU_AT"
    band=$(uifind ui.xml --band 2>/dev/null) || band="0 99999"
    band=${band##* }
    if [ "${at[1]}" -lt 500 ]; then
      EMU_SWIPE_X=250 swipe_page down short
    elif [ "${at[7]}" -ge $((band - 1)) ]; then
      EMU_SWIPE_X=250 swipe_page up short
    else
      SIZE_LABEL_H=$((at[7] - at[5]))
      return 0
    fi
    # settle compares frames only: the dump after it, else find_ui reads the screen before the swipe
    settle
    dump || return 1
  done
  fail "the label '$1' still cut by the edge of the page after 3 swipes ($EMU_AT, band to $band)"
  return 1
}

text_size_live() {
  local c=$1 size=$2 sec=$3 lab=$4 n=${5:-20} want=${6:-in} field before h0 h1 i ps at rc
  case $want in
    in|out) ;;
    *) fail "$c: want '$want' - in or out"; return 1 ;;
  esac
  field="^$lab [0-9]+\$"
  if [ "$sec" != - ]; then
    # the closed section may be far down the page (General UI Options - the sixth card)
    scroll_to "$sec" 30 --first --exact || { shot "$c-0-no-section" now; return 1; }
    tap_ui "$sec" "$field" --first --land-below || { shot "$c-0-not-opened" now; return 1; }
  else
    # the section open, the survey of the size before left the page at its end; scroll_to goes down the page only
    # (45047414549, hu2/hr2: "end of the page, not found")
    scroll_top || return 1
  fi
  scroll_to "$field" 30 --first --exact || { shot "$c-0-no-field" now; return 1; }
  # not under the pinned title of the open section (T-561, 43787869713: a tap at y 297 went to it)
  read -r -a at <<< "$EMU_AT"
  if [ "${at[1]:-0}" -lt 500 ]; then
    EMU_SWIPE_X=250 swipe_page down short
    scroll_to "$field" 5 --first --exact || return 1
  fi
  settle
  before=$(uifind ui.xml "$field" --first --name 2>/dev/null)
  before=${before##* }
  case $before in
    ''|*[!0-9]*) fail "$c: the size before not read from '$field'"; return 1 ;;
  esac
  if [ "$size" -le "$before" ]; then
    fail "$c: size $size not above $before - the proof by the grown label needs a larger size"
    return 1
  fi
  _label_h "$lab" || return 1
  h0=$SIZE_LABEL_H
  shot "$c-1-before"
  # the field focused: the keyboard shows (a tap may go before the page is still)
  for i in 1 2 3; do
    find_ui "$field" --first || { fail "$c: the field gone before the tap ($EMU_WHY)"; return 1; }
    read -r -a at <<< "$EMU_AT"
    say "$c: tap the field '$lab $before' at ${at[0]} ${at[1]} ($i)"
    adb shell input tap "${at[0]}" "${at[1]}" < /dev/null > /dev/null 2>&1
    emu_sleep 2
    ime_shown && break
    [ "$i" = 3 ] && { shot "$c-1-nokb" now; fail "$c: the keyboard did not show on the field '$lab $before'"; return 1; }
    dump
  done
  # the cursor at the end (onActiveFocusChanged puts it there; MOVE_END - the same once more), the number deleted
  adb shell input keyevent 123 < /dev/null > /dev/null 2>&1
  for i in 1 2 3 4; do
    adb shell input keyevent 67 < /dev/null > /dev/null 2>&1
  done
  # emptied: no "<label> <number>" left - the empty field is "<label> ", the same name as the label itself
  wait_gone "$field" 6 || { shot "$c-1-not-cleared" now; fail "$c: the field not emptied ('$field' still shown)"; return 1; }
  type_text "$size" "^$lab ${size:0:1}\$" "^$lab $size\$" || return 1
  adb shell input keyevent 66 < /dev/null > /dev/null 2>&1
  emu_sleep 2
  hide_keyboard || return 1
  settle
  scroll_to "^$lab\$" 10 --first --exact || return 1
  _label_h "$lab" || return 1
  h1=$SIZE_LABEL_H
  shot "$c-2-after"
  if [ $((h1 * before * 10)) -lt $((h0 * size * 9)) ]; then
    proves_nothing "$c: the label '$lab' $h0 -> $h1 px after $before -> $size % - the size did not take on the open page"
  fi
  say "check $c: text size $before -> $size % on the open page, the label $h0 -> $h1 px: OK"
  survey_page "$c" "$n" || return 1
  ps=$(ls dumps/survey-"$c"-[0-9]*.xml 2>/dev/null | tr '\n' ' ')
  [ -n "$ps" ] || { fail "check $c: no survey dumps"; return 1; }
  # shellcheck disable=SC2086 # the list of dumps is split on purpose
  "$EMU_PY" "$EMU_GH/emu_frame.py" inside $ps > ".inside-$c" 2>&1
  rc=$?
  case $want/$rc in
    in/0) say "check $c: rows within their cards at $size %: $(head -n 1 ".inside-$c")" ;;
    out/1) say "check $c: the defect shown, rows out of their cards at $size % (want out): $(head -n 3 ".inside-$c" | tr '\n' ' ')" ;;
    out/0) fail "check $c: rows within their cards at $size %, the defect not shown (want out) - the case does not reproduce it: $(head -n 1 ".inside-$c")" ;;
    */1) fail "check $c: rows out of their cards at $size %: $(head -n 6 ".inside-$c" | tr '\n' ' ')" ;;
    *) fail "check $c: emu_frame.py inside: $(head -n 3 ".inside-$c" | tr '\n' ' ') (exit $rc)" ;;
  esac
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

# qml_lines <side> <files>: the QML warnings of <files> (names without .qml, as an ERE alternation:
# 'SettingsTextField|settings') from the processes of the side (the "pid <side><case>" lines of start_case) in
# full_logcat.txt, as "file.qml: text" - the line numbers dropped: an import moves them; the column too, when there
# is one ("main.qml:1992: ReferenceError" has none - T-198 45301968970: 9 warnings of master taken for the PR's)
qml_lines() {
  local pid
  for pid in $(grep -a "^pid $1" "$STEPLOG" | cut -d' ' -f3); do
    awk -v p="$pid" '$3 == p' full_logcat.txt | grep -a -E "($2)\.qml:" \
      | sed -E -e 's/^.*qrc:\///' -e 's/\.qml:[0-9]+(:[0-9]+)?:/.qml:/'
  done | sort -u
}

# qml_quiet <files> [<files of the PR>]: no QML warning of <files> from the head processes (T-689; the copies of
# test/t495-emu, t534, t537, t629, t649, t661 - T-661 lesson 8). A warning the base gives the same way (the file and
# the text without the line number) is not of the PR (T-649 44964369133). Without the base side nothing filters what
# master gives too (settings.qml ScrollView, 45021049226): only <files of the PR> (default - <files>) fail, the
# rest is printed. Red: no head pid, an empty full_logcat.txt. After the cases: stops logcat_start
qml_quiet() {
  local files=$1 pr=${2:-$1} pid n=0 found known key
  if [ -z "$files" ]; then
    fail "qml_quiet: no files given - qml_quiet '<files>' ['<files of the PR>']"
    return 1
  fi
  logcat_stop
  known=$(qml_lines b "$files")
  [ -z "$known" ] || say "check qml: on base too (not of the PR): $(echo "$known" | tr '\n' ';')"
  for pid in $(grep -a '^pid h' "$STEPLOG" | cut -d' ' -f3); do
    n=$(( n + 1 ))
    found=$(awk -v p="$pid" '$3 == p' full_logcat.txt | grep -a -E "($files)\.qml:" \
      | while IFS= read -r line; do
          key=$(echo "$line" | sed -E -e 's/^.*qrc:\///' -e 's/\.qml:[0-9]+(:[0-9]+)?:/.qml:/')
          printf '%s\n' "$known" | grep -qxF -- "$key" || echo "$line"
        done | head -5)
    if [ -n "$found" ] && ! grep -a -q '^pid b' "$STEPLOG"; then
      echo "$found" | grep -a -v -E "($pr)\.qml:" | while IFS= read -r line; do
        say "check qml: no base to compare, not failed: $line"
      done
      found=$(echo "$found" | grep -a -E "($pr)\.qml:")
    fi
    if [ -n "$found" ]; then
      echo "$found" >> "$STEPLOG"
      fail "check qml: pid $pid: QML warnings of the files of the PR"
    fi
  done
  if [ "$n" = 0 ]; then
    fail "check qml: no head pid in steps.log - QML warnings not checked"
  elif [ ! -s full_logcat.txt ]; then
    fail "check qml: full_logcat.txt is empty"
  else
    grep -q '^!! check qml' "$STEPLOG" || say "check qml: no warning of the files of the PR from $n head processes: OK"
  fi
}
