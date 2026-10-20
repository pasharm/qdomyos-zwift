#!/usr/bin/env python3
# Test only (T-199, T-232): what a screen reader and voice control get from the uiautomator
# dumps of an emulator run.
#   a11y.py dumps/ [package] [--json a11y.json] [--compare old-a11y.json]
# Drop-in for .github/a11y.py of the emu branches: same call, same "== summary" at the end.
#
# Findings, per screen (dump), each listed once with the dumps it is in:
#   unnamed   a node the user can act on (clickable, long-clickable, checkable) with neither
#             text nor content-desc: TalkBack says "button" or nothing, voice control cannot
#             name it
#   field     an edit field (android.widget.EditText) without content-desc: TalkBack reads only
#             what is typed in it ("0"), not which setting it is
#   no-action a named node that is not clickable and not focusable, with a child of the same
#             name: a control whose text Qt copied to the node, but without an action - Qt 5.15
#             gives ItemDelegate, MenuItem and the *Delegate controls the role ListItem/MenuItem
#             without a press action. Voice control does not offer it, TalkBack reaches it only
#             as text (the classic side menu items, T-232)
# Not findings: the Android containers around Qt's view (FrameLayout, ViewGroup, View) and
# nodes of zero size (the hidden field of a WebView).
# --json writes the findings for a later run; --compare lists what is new against such a file
# (a run of master against a run of the branch). Exit code 1 if there are findings.
# GITHUB_STEP_SUMMARY, when set, gets a table of the screens.
# No regular expressions, to read easily (rule 5 of AGENTS.md upstream).
import json
import os
import sys
import xml.etree.ElementTree as ET

QT_NODE = "android.view.View$VirtualChild"


def name_of(n):
    return (n.get("content-desc") or "").strip() or (n.get("text") or "").strip()


def area(bounds):
    # "[x1,y1][x2,y2]"
    try:
        a, b = bounds.strip("[]").split("][")
        x1, y1 = (int(v) for v in a.split(","))
        x2, y2 = (int(v) for v in b.split(","))
    except ValueError:
        return 0
    return max(0, x2 - x1) * max(0, y2 - y1)


def is_app_item(n):
    cls = n.get("class") or ""
    return cls == QT_NODE or (cls.startswith("android.widget.") and cls not in ("android.widget.FrameLayout", "android.widget.LinearLayout"))


def check_dump(root, pkg):
    """(nodes of the app, [(rule, name, class, bounds)])"""
    nodes = [n for n in root.iter("node") if n.get("package") == pkg]
    found = []
    for n in nodes:
        if not is_app_item(n) or area(n.get("bounds") or "") == 0:
            continue
        name = name_of(n)
        act = "true" in (n.get("clickable"), n.get("long-clickable"), n.get("checkable"))
        cls = n.get("class")
        if n.get("class") == "android.widget.EditText":
            if not (n.get("content-desc") or "").strip():
                found.append(("field", (n.get("text") or "").strip(), cls, n.get("bounds")))
        elif act and not name:
            found.append(("unnamed", "", cls, n.get("bounds")))
        elif name and not act and n.get("focusable") != "true":
            if name in [name_of(k) for k in n]:
                found.append(("no-action", name, cls, n.get("bounds")))
    return nodes, found


def main(argv):
    args = list(argv)
    opts = {}
    for key in ("--json", "--compare"):
        if key in args:
            k = args.index(key)
            opts[key] = args[k + 1]
            del args[k:k + 2]
    folder = args[0]
    pkg = args[1] if len(args) > 1 else "org.cagnulen.qdomyoszwift"

    summary, table = [], []
    # (rule, name or, without a name, bounds) -> [dumps]: a menu item scrolled to another place
    # is the same finding
    seen = {}
    where_at = {}
    for dump in sorted(os.listdir(folder)):
        if not dump.endswith(".xml"):
            continue
        try:
            root = ET.parse(os.path.join(folder, dump)).getroot()
        except ET.ParseError:
            summary.append(f"{dump}: unreadable dump")
            continue
        nodes, found = check_dump(root, pkg)
        if not nodes:
            summary.append(f"{dump}: no nodes of the app (another window on top)")
            continue
        act = [n for n in nodes if "true" in (n.get("clickable"), n.get("long-clickable"), n.get("checkable"))
               and is_app_item(n) and area(n.get("bounds") or "") > 0]
        named = [n for n in nodes if name_of(n)]
        counts = {r: sum(1 for f in found if f[0] == r) for r in ("unnamed", "field", "no-action")}
        print(f"== {dump}: nodes {len(nodes)}, with a name {len(named)}, actionable {len(act)}, "
              f"unnamed {counts['unnamed']}, fields without a name {counts['field']}, named without action {counts['no-action']}")
        for rule, name, cls, bounds in found:
            key = (rule, name if rule != "field" and name else bounds)
            dumps = seen.setdefault(key, [])
            if dump[:-4] not in dumps:
                dumps.append(dump[:-4])
            where_at.setdefault(key, bounds)
            print(f"   ?? {rule} {cls} {bounds} '{name[:60]}'")
        # The names an actionable control is read by, to see what TalkBack says
        for n in act[:60]:
            label = name_of(n)
            if label:
                state = " checked" if n.get("checked") == "true" else ""
                print(f"   ok {n.get('class')} '{label[:70]}'{state}")
        summary.append(f"{dump}: actionable {len(act)}, without a name {counts['unnamed']}, "
                       f"fields without a name {counts['field']}, named without action {counts['no-action']}, "
                       f"named nodes {len(named)}/{len(nodes)}")
        table.append((dump[:-4], len(act), counts["unnamed"], counts["field"], counts["no-action"]))

    def line(key):
        dumps = seen[key]
        where = ", ".join(dumps[:4]) + (f" (+{len(dumps) - 4})" if len(dumps) > 4 else "")
        label = f"'{key[1][:60]}'" if key[1] != where_at[key] else "(no name)"
        return f"{key[0]} {label} at {where_at[key]} in {len(dumps)} dump(s): {where}"

    print("== findings, each once")
    for key in sorted(seen):
        print(line(key))

    new = None
    if "--compare" in opts:
        with open(opts["--compare"], encoding="utf-8") as f:
            old = {(x["rule"], x["key"]) for x in json.load(f)["findings"]}
        new = sorted(k for k in seen if k not in old)
        print(f"== new against {opts['--compare']}: {len(new)}")
        for key in new:
            print(line(key))
    if "--json" in opts:
        with open(opts["--json"], "w", encoding="utf-8") as f:
            json.dump({"findings": [{"rule": k[0], "key": k[1], "bounds": where_at[k], "dumps": d}
                                    for k, d in sorted(seen.items())]}, f, ensure_ascii=False, indent=1)

    print("== summary")
    for line in summary:
        print(line)
    total = {r: sum(1 for k in seen if k[0] == r) for r in ("unnamed", "field", "no-action")}
    print(f"distinct: unnamed {total['unnamed']}, fields without a name {total['field']}, named without action {total['no-action']}"
          + (f", new {len(new)}" if new is not None else ""))

    step = os.environ.get("GITHUB_STEP_SUMMARY")
    if step:
        with open(step, "a", encoding="utf-8") as f:
            f.write("### Accessibility tree (uiautomator dumps)\n\n")
            f.write(f"Distinct: unnamed **{total['unnamed']}**, fields without a name **{total['field']}**, "
                    f"named without action **{total['no-action']}**" + (f", new **{len(new)}**" if new is not None else "") + "\n\n")
            f.write("| screen | actionable | unnamed | field | no action |\n| --- | --- | --- | --- | --- |\n")
            for row in table:
                f.write("| " + " | ".join(str(v) for v in row) + " |\n")
    return 1 if seen else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
