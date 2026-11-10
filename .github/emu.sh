#!/bin/bash
# Test only (T-505): the pilot of the emulator library (tools/emu/lib.sh, qz.sh of the QZ work folder) on a
# ready APK - tap_ui with its outcome, scroll_to, survey_page, expect by the dump of the frame (ACTION_CLICK
# was checked by run 42860387276: the driver builds on the runner, Qt takes it, QZ then crashes - T-508).
# APK: the input head (fdroid-android-trial).
. .github/lib.sh
. .github/qz.sh

emu_init
logcat_start
install_apk apk-head/android-debug.apk

if start_case p ui_modern=false fakedevice_treadmill=true; then
  shot p-1-home
  expect p-1-home "$HOME_RX" 'the home page'
  if settings_open; then
    shot p-2-settings
    expect p-2-settings '^General Options$' 'the settings page'
    # a touch: ACTION_CLICK on an accordion crashes QZ (afterClick, T-508; pilot run 42860387276)
    tap_ui '^General Options$' '^App Language:$' 15
    shot p-3-general
    expect p-3-general '^App Language:$' 'General Options open'
    # a touch on a section below the screen: brought in by swipes, the outcome by its own row
    scroll_to '^Tiles Options$' 30
    tap_ui '^Tiles Options$' '^Speed$' 15
    shot p-4-tiles
    expect p-4-tiles '^Speed$' 'Tiles Options open'
    expect_not p-4-tiles '^General Options$' 'the page scrolled past General Options'
    # the page from the top to its end: the dumps for check_emu_script.py --dumps
    survey_page settings 40
  fi
fi

if start_case m ui_modern=true fakedevice_treadmill=true; then
  shot m-1-home
  expect m-1-home "$HOME_RX" 'the home page (modern)'
  if settings_open; then
    shot m-2-settings
    expect m-2-settings '^General Options$' 'the settings page (modern)'
    tap_ui '^General Options$' '^App Language:$' 15
    shot m-3-general
    expect m-3-general '^App Language:$' 'General Options open (modern)'
    survey_page settings-modern 40
  fi
fi

logcat_stop
finish
