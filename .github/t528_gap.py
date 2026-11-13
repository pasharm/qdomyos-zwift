"""Test only (T-528): seconds from the return to QZ after Allow to the line "files to restore" of the pass.

usage: python3 t528_gap.py <events logcat> <full logcat> <package>
The events logcat (logcat -b events -v threadtime) has wm_on_resume_called of the activity; the last one of
the package before the first "handleRestoreFolderResult files to restore" line of the full logcat is the
return from the folder picker. prints "<seconds> <resume time> <line time>"; nothing and exit 1 - a line missing.
"""
import sys
from datetime import datetime


def stamp(line):
    # "11-13 15:18:51.687  5058 ..." - threadtime; the year does not matter for a difference
    parts = line.split()
    if len(parts) < 2:
        return None
    try:
        return datetime.strptime("2026-" + parts[0] + " " + parts[1], "%Y-%m-%d %H:%M:%S.%f")
    except ValueError:
        return None


events_path, full_path, package = sys.argv[1], sys.argv[2], sys.argv[3]
done = None
for line in open(full_path, encoding="utf-8", errors="replace"):
    if "handleRestoreFolderResult files to restore" in line:
        done = stamp(line)
        break
if done is None:
    sys.exit(1)
resumed = None
for line in open(events_path, encoding="utf-8", errors="replace"):
    if "wm_on_resume_called" in line and package in line:
        t = stamp(line)
        if t is not None and t <= done:
            resumed = t
if resumed is None:
    sys.exit(1)
print("%.2f %s %s" % ((done - resumed).total_seconds(), resumed.strftime("%H:%M:%S.%f")[:-3],
                      done.strftime("%H:%M:%S.%f")[:-3]))
