"""Полнота переводов в начатых языках – для CI форка (workflow translations-check.yml).

    python .github/scripts/check_translations.py [база]      база по умолчанию upstream/master

«Начатый» язык – .ts, где готово (не unfinished) не меньше STARTED_SHARE строк. В остальных
.ts переводов нет или почти нет, QZ там по сути английский – их не трогаем. Порог, а не «хоть
одна строка»: PR #5420 перевёл свои 4 строки во все 14 языков апстрима, и cs, ko, nl, pl, tr
с 4 переводами из ~2000 иначе потребовали бы перевода всех строк ветки.

1. Новые строки ветки (от merge-base с базой) – переведены ли во всех начатых языках.
   Новые – литералы qsTr("…") / tr("…") в добавленных строках .qml/.cpp/.h и пары
   контекст + <source>, добавленные в любой .ts, которых нет в .ts базы. Не хватает – код
   выхода 1. Строка из .qml сверяется парой контекст + текст: контекст – имя файла без
   расширения, как его ставит lupdate (settings.qml → settings); тот же текст, переведённый в
   другом контексте, в этом всё равно английский. Пары нет в .ts вовсе – «нет в .ts», нужен
   lupdate. Для .cpp/.h контекст – имя класса, из диффа его не вывести: сверка по тексту.
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
CONTEXT = re.compile(r"<context>(.*?)</context>", re.S)
NAME = re.compile(r"<name>(.*?)</name>", re.S)
MSG = re.compile(r"<message>.*?</message>", re.S)
SRC = re.compile(r"<source>(.*?)</source>", re.S)
TRN = re.compile(r"<translation([^>]*)>(.*?)</translation>", re.S)
TSDIR = "src/translations"
# Доля готовых переводов, с которой язык считается начатым (см. шапку)
STARTED_SHARE = 0.10


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True,
                          encoding="utf-8", check=True).stdout


def unescape_c(s):
    return re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), s)


def ts_messages(text):
    """список (контекст, source, готовый перевод или '') по живым <message> (без vanished/obsolete)"""
    out = []
    for c in CONTEXT.finditer(text):
        n = NAME.search(c.group(1))
        ctx = html.unescape(n.group(1).strip()) if n else ""
        for m in MSG.finditer(c.group(1)):
            s = SRC.search(m.group(0))
            t = TRN.search(m.group(0))
            if not s:
                continue
            attrs = t.group(1) if t else ""
            if "vanished" in attrs or "obsolete" in attrs:
                continue
            done = t and "unfinished" not in attrs and t.group(2).strip()
            out.append((ctx, html.unescape(s.group(1)), html.unescape(t.group(2)) if done else ""))
    return out


def lang(name):
    return name.split("qdomyos-zwift_")[-1][:-3]


def main():
    base = sys.argv[1] if len(sys.argv) > 1 else "upstream/master"
    mb = git("merge-base", "HEAD", base).strip()

    base_pairs, head = set(), {}
    for n in git("ls-tree", "--name-only", mb, TSDIR + "/").split():
        if n.endswith(".ts"):
            base_pairs |= {(c, s) for c, s, _ in ts_messages(git("show", f"{mb}:{n}"))}
    base_texts = {s for _, s in base_pairs}
    for p in sorted(Path(TSDIR).glob("*.ts")):
        head[p.as_posix()] = ts_messages(p.read_text(encoding="utf-8"))
    started = [n for n, msgs in head.items()
               if msgs and sum(1 for _, _, t in msgs if t) >= STARTED_SHARE * len(msgs)]
    # пары с готовым переводом и все пары языка; для C++ (контекст None) – по одному тексту
    done = {n: {(c, s) for c, s, t in head[n] if t} for n in started}
    present = {n: {(c, s) for c, s, _ in head[n]} for n in started}
    done_texts = {n: {s for _, s in done[n]} for n in started}
    present_texts = {n: {s for _, s in present[n]} for n in started}

    # (контекст, текст); контекст None – строка из C++, сверка только по тексту
    new = set()
    diff = git("diff", "-U0", mb, "--", "*.qml", "*.cpp", "*.h")
    ctx, header = None, False
    for line in diff.splitlines():
        # имя файла – только в шапке до первого @@: добавленная строка «++ …» – не заголовок
        if line.startswith("diff --git "):
            header = True
        elif line.startswith("@@"):
            header = False
        elif header and line.startswith("+++ "):
            ctx = Path(line[4:].strip()).stem if line.strip().endswith(".qml") else None
        elif line.startswith("+") and not header:
            for lit in TR_CALL.findall(line):
                key = (ctx, unescape_c(lit))
                if (key not in base_pairs) if ctx is not None else (key[1] not in base_texts):
                    new.add(key)
    for msgs in head.values():
        new |= {(c, s) for c, s, _ in msgs} - base_pairs
    # строка C++, добавленная и в код, и в .ts, – один раз: парой из .ts
    in_ts = {s for c, s in new if c is not None}
    new = {k for k in new if k[1] and not (k[0] is None and k[1] in in_ts)}

    md = [f"## Переводы: начатые языки – {', '.join(lang(n) for n in started)}", ""]
    bad = []
    for c, s in sorted(new, key=lambda k: (k[0] or "", k[1])):
        if c is None:
            absent = [lang(n) for n in started if s not in present_texts[n]]
            miss = [lang(n) for n in started if s in present_texts[n] and s not in done_texts[n]]
        else:
            absent = [lang(n) for n in started if (c, s) not in present[n]]
            miss = [lang(n) for n in started if (c, s) in present[n] and (c, s) not in done[n]]
        if absent or miss:
            bad.append((c, s, miss, absent))
    if not new:
        md.append("Новых строк в ветке нет.")
    elif not bad:
        md.append(f"Новые строки ветки ({len(new)}) переведены во всех начатых языках.")
    else:
        md += [f"**{len(bad)} из {len(new)} новых строк переведены не везде.**", "",
               "| Контекст | Строка | Нет перевода | Нет в .ts (нужен lupdate) |",
               "| --- | --- | --- | --- |"]
        for c, s, miss, absent in bad:
            short = s.replace("\n", "\\n").replace("|", "\\|")[:100]
            md.append(f"| {c or '(C++)'} | {short} | {', '.join(miss)} | {', '.join(absent)} |")

    md += ["", "### Долг по всему файлу (не блокирует)", "", "| Язык | Не переведено | Всего |",
           "| --- | ---: | ---: |"]
    for n in started:
        total = len(head[n])
        md.append(f"| {lang(n)} | {sum(1 for _, _, t in head[n] if not t)} | {total} |")

    text = "\n".join(md) + "\n"
    print(text)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(text)
    for c, s, miss, absent in bad:
        parts = ([f"нет перевода: {' '.join(miss)}"] if miss else []) + \
                ([f"нет в .ts: {' '.join(absent)}"] if absent else [])
        # значения свойств команды экранируются: «,» делит свойства, «:» – конец заголовка
        title = "; ".join(parts).replace("%", "%25").replace(",", "%2C").replace(":", "%3A")
        print(f"::error title={title}::{(f'[{c}] ' if c else '') + s.replace(chr(10), ' ')[:200]}")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
