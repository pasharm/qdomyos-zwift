"""Test only (T-618): the classic home tiles in the iOS simulator - the value of a tile with a smaller font
(Elapsed, Clock: valueElapsedFontSize / valueTimeFontSize of homeform.cpp, 36 / 26 on iOS) is centred in its
58 pt band after the fix (Home.qml myValue, verticalAlignment AlignVCenter), next to a 48 pt tile.

usage: ios_t618.py <idb> <udid> <out_dir> <prefix>
The landing of the home page is its "Lap" button (the sign of the library); the tiles are measured on the frame
afterwards (notes/emu/t618-*/). SUMMARY line and exit code by the library (tools/ios/iosnav.py).
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from iosnav import init, shot, wait_for, page, summary, dismiss_alerts  # noqa: E402

init(*sys.argv[1:5])

dismiss_alerts()
ok = wait_for("Lap", exact=True)
# the tiles come with the device; the clock ticks - a frame after the page settled
time.sleep(5)
shot("01-home")
page("home", ok)
sys.exit(summary())
