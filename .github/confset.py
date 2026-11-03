#!/usr/bin/env python3
# Test only (T-400): set keys of a QSettings ini file in its [General] section.
#   confset.py qz.conf key=value [key=value ...]
# A key already there is replaced in place; a new one goes right after [General], not at the
# end of the file, where it would fall into another section.
import sys

path, pairs = sys.argv[1], sys.argv[2:]
with open(path, encoding="utf-8", errors="replace") as f:
    lines = f.read().replace("\r\n", "\n").split("\n")

values = dict(p.split("=", 1) for p in pairs)
section = None
done = set()
for i, line in enumerate(lines):
    s = line.strip()
    if s.startswith("[") and s.endswith("]"):
        section = s
        continue
    if section == "[General]" and "=" in line:
        key = line.split("=", 1)[0]
        if key in values:
            lines[i] = key + "=" + values[key]
            done.add(key)

missing = [k + "=" + v for k, v in values.items() if k not in done]
if missing:
    if "[General]" in [l.strip() for l in lines]:
        at = [l.strip() for l in lines].index("[General]") + 1
    else:
        lines.insert(0, "[General]")
        at = 1
    lines[at:at] = missing

with open(path, "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(lines))
print("set:", ", ".join(pairs))
