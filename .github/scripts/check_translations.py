"""Полнота переводов в начатых языках – для CI форка (workflow translations-check.yml).

    python .github/scripts/check_translations.py [база]      база по умолчанию upstream/master

«Начатый» язык – .ts, где есть хоть один готовый перевод (не unfinished). В остальных .ts
переводов нет вовсе, QZ там целиком английский – их не трогаем.

1. Новые строки ветки (от merge-base с базой) – переведены ли во всех начатых языках.
   Новые – литералы qsTr("…") / tr("…") в добавленных строках .qml/.cpp/.h и <source>,
   добавленные в любой .ts, которых нет ни в одном .ts базы. Не хватает – код выхода 1.
2. Отчёт: сколько строк не переведено в каждом начатом .ts целиком (долг апстрима).
   На код выхода не влияет.

Итог печатается и, если задан GITHUB_STEP_SUMMARY, дописывается туда таблицей.
Не видит строк, склеенных из частей ("a" + "b") и собранных через arg() из переменной.
Логика п. 1 – как у tools/check_new_strings.py рабочей папки QZ.
"""
import html
import os
import re
import subprocess
import sys
from pathlib import Path

TR_CALL = re.compile(r'\b(?:qsTr|tr)\(\s*"((?:[^"\\]|\\.)*)"')
MSG = re.compile(r"<message>.*?</message>", re.S)
SRC = re.compile(r"<source>(.*?)</source>", re.S)
TRN = re.compile(r"<translation([^>]*)>(.*?)</translation>", re.S)
TSDIR = "src/translations"


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True,
                          encoding="utf-8", check=True).stdout


def unescape_c(s):
    return re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), s)


def ts_messages(text):
    """список (source, готовый перевод или '') по живым <message> (без vanished/obsolete)"""
    out = []
    for m in MSG.finditer(text):
        s = SRC.search(m.group(0))
        t = TRN.search(m.group(0))
        if not s:
            continue
        attrs = t.group(1) if t else ""
        if "vanished" in attrs or "obsolete" in attrs:
            continue
        done = t and "unfinished" not in attrs and t.group(2).strip()
        out.append((html.unescape(s.group(1)), html.unescape(t.group(2)) if done else ""))
    return out


def lang(name):
    return name.split("qdomyos-zwift_")[-1][:-3]


def main():
    base = sys.argv[1] if len(sys.argv) > 1 else "upstream/master"
    mb = git("merge-base", "HEAD", base).strip()

    base_sources, head = set(), {}
    for n in git("ls-tree", "--name-only", mb, TSDIR + "/").split():
        if n.endswith(".ts"):
            base_sources |= {s for s, _ in ts_messages(git("show", f"{mb}:{n}"))}
    for p in sorted(Path(TSDIR).glob("*.ts")):
        head[p.as_posix()] = ts_messages(p.read_text(encoding="utf-8"))
    started = [n for n, msgs in head.items() if any(t for _, t in msgs)]
    done = {n: {s for s, t in head[n] if t} for n in started}

    new = set()
    diff = git("diff", "-U0", mb, "--", "*.qml", "*.cpp", "*.h")
    for line in diff.splitlines():
        if line.startswith("+") and not line.startswith("+++"):
            new |= {unescape_c(lit) for lit in TR_CALL.findall(line)}
    for msgs in head.values():
        new |= {s for s, _ in msgs}
    new = {s for s in new - base_sources if s}

    md = [f"## Переводы: начатые языки – {', '.join(lang(n) for n in started)}", ""]
    bad = []
    for s in sorted(new):
        miss = [lang(n) for n in started if s not in done[n]]
        if miss:
            bad.append((s, miss))
    if not new:
        md.append("Новых строк в ветке нет.")
    elif not bad:
        md.append(f"Новые строки ветки ({len(new)}) переведены во всех начатых языках.")
    else:
        md += [f"**{len(bad)} из {len(new)} новых строк переведены не везде.**", "",
               "| Строка | Нет перевода |", "| --- | --- |"]
        for s, miss in bad:
            short = s.replace("\n", "\\n").replace("|", "\\|")[:100]
            md.append(f"| {short} | {', '.join(miss)} |")

    md += ["", "### Долг по всему файлу (не блокирует)", "", "| Язык | Не переведено | Всего |",
           "| --- | ---: | ---: |"]
    for n in started:
        total = len(head[n])
        md.append(f"| {lang(n)} | {sum(1 for _, t in head[n] if not t)} | {total} |")

    text = "\n".join(md) + "\n"
    print(text)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(text)
    for s, miss in bad:
        print(f"::error title=Нет перевода ({', '.join(miss)})::{s.replace(chr(10), ' ')[:200]}")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
