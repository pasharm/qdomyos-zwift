#!/bin/bash
# Test only (T-505): the pilot of the emulator library (tools/emu/lib.sh, qz.sh of the QZ work folder) on a
# ready APK - ACTION_CLICK on a Qt control (the a11y driver built on the runner; QZ crashed on it in run
# 42860387276 before the T-508 fix), tap_ui with its outcome, scroll_to, survey_page, expect by the dump of
# the frame. APK: the input head (fdroid-android-trial).
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
    # ACTION_CLICK on the accordion of the classic look (Qt 5.15 accessibility bridge, T-508 fix)
    tap_ui '^General Options$' '^App Language:$' 15 --a11y
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
    tap_ui '^General Options$' '^App Language:$' 15 --a11y
    shot m-3-general
    expect m-3-general '^App Language:$' 'General Options open (modern)'
    survey_page settings-modern 40
  fi
fi

logcat_stop
finish
