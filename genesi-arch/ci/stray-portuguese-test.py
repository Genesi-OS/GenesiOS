#!/usr/bin/env python3
"""
stray-portuguese-test.py — no Portuguese-only text reaches an English user.

── Why this exists ──────────────────────────────────────────────────────────

Genesi is written by a Brazilian team for everyone, and pt-BR text kept
leaking into English sessions with nothing to catch it:

  * the AI Mode widget: "Medir o ganho do Turbo", "Nenhum modelo carregado"
  * the AI Mode launcher's notifications: "Modo IA Forçado ativado com sucesso!"
  * the Monitor's whole Mesh page, while every other page followed the
    language switch
  * the CUDA offer notification, the Update Center's terminal output, the
    welcome app (pt-BR whatever the system language), Turbo's CLI output

A user saw them before we did. This reads every string literal in the code
that draws UI or prints to a person and fails on one that is Portuguese and
not one half of a bilingual pair.

── What counts as paired ────────────────────────────────────────────────────

A literal is fine when, within a few lines of it, the code is choosing a
language: a tr()/t() call, a `pt:` key beside an `en:` one, a `pt*)` case
branch, or a dict keyed by language. Files that ARE translation tables or
that parse Portuguese input on purpose are listed in ALLOWED, with the reason.
"""
import io
import os
import re
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

SCAN_PREFIXES = ("genesi-arch/packages/", "genesi-settings-full/usr/")
SCAN_EXTS = (".qml", ".py", ".js", ".sh", ".desktop", "")

ALLOWED = {
    # translation tables: Portuguese is the point
    "genesi-arch/packages/genesi-ui-kit/components/I18n.qml": "the shared EN/PT string table",
    "genesi-arch/packages/genesi-store/catalog_en.py": "PT->EN map for the store catalog",
    "genesi-arch/packages/genesi-store/build-catalog.py": "PT source text; catalog_en.py supplies English",
    "genesi-arch/packages/genesi-store/fetch_themes.py": "PT blurbs; catalog_en.py supplies English",
    "genesi-arch/packages/genesi-store/topbar_looks.py": "PT blurbs; catalog_en.py supplies English",
    "genesi-arch/packages/genesi-welcome/genesi-welcome.py": "STR table keyed by language",
    # parsing what a person types, in either language
    "genesi-arch/packages/genesi-ai-mode/genesi-ai-image": "prompt parser matches PT and EN words",
    "genesi-arch/packages/genesi-ai-mode/genesi-find": "date parser matches PT and EN words",
    "genesi-arch/packages/genesi-ai-mode/monitor/genesi_agent.py": "intent matcher for PT and EN phrases",
    "genesi-arch/packages/genesi-ai-mode/genesi-ai-voice": "language names, each in its own language",
}

PT_CHARS = re.compile(r"[ãõçáéíóúâêôàÃÕÇÁÉÍÓÚÂÊÔÀ]")
PT_WORDS = re.compile(
    r"\b(não|você|para|ganho|medir|abrir|fechar|carregando|carregado|salvar|nenhum|"
    r"nenhuma|desligad[oa]|ligad[oa]|erro|aguarde|baixando|instalando|atualizando|"
    r"pronto|sair|cancelar|reiniciar|arquivo|pasta|tela|janela|modelo|máquina|maquina|"
    r"medido|ainda|nesta|neste|agora|depois|ajuda|sucesso|ativado|restaurado)\b", re.I)
STRING = re.compile(r'"((?:[^"\\\n]|\\.){3,})"|\'((?:[^\'\\\n]|\\.){3,})\'')
LANG_CHOICE = re.compile(
    r"\b(tr|t|i18n\.t|qsTr|say)\s*\(|"         # a translate call
    r"\bpt\s*:|\"pt(-BR)?\"\s*:|"              # { en: ..., pt: ... } / {"pt-BR": ...}
    r"\[pt(_BR)?\]=|"                          # Name[pt_BR]= in .desktop files
    r"lang\s*===?\s*[\"']pt")                  # lang === "pt" ? ... : ...
COMMENT = re.compile(r"^\s*(#|//|\*|/\*)")
WINDOW = 8


def portuguese(text):
    return bool(PT_CHARS.search(text)) or len(PT_WORDS.findall(text)) >= 2


def files():
    out = subprocess.run(["git", "-C", ROOT, "ls-files", "--recurse-submodules"],
                         capture_output=True, text=True, encoding="utf-8").stdout
    for rel in out.split("\n"):
        if not rel.startswith(SCAN_PREFIXES) or rel in ALLOWED:
            continue
        name = os.path.basename(rel)
        if "/ci/" in rel or "/tests/" in rel or "/test/" in rel \
                or name.startswith("test-") or name.endswith(("-test.py", "_test.py")):
            continue
        if os.path.splitext(rel)[1] not in SCAN_EXTS:
            continue
        yield rel


def stray(rel):
    try:
        lines = io.open(os.path.join(ROOT, rel), encoding="utf-8", errors="replace").read().split("\n")
    except OSError:
        return
    in_pt_branch = False            # inside a shell `pt*)` branch, up to its `;;`
    for i, line in enumerate(lines):
        if re.match(r"\s*pt\*\)", line):
            in_pt_branch = True
        if COMMENT.match(line):
            continue
        near = "\n".join(lines[max(0, i - WINDOW):i + WINDOW + 1])
        paired = in_pt_branch or LANG_CHOICE.search(near)
        if ";;" in line:
            in_pt_branch = False
        for m in STRING.finditer(line):
            text = m.group(1) or m.group(2)
            if portuguese(text) and not paired:
                yield i + 1, text


def main():
    if not os.path.isdir(os.path.join(ROOT, "genesi-settings-full", "usr")):
        print("FAIL: genesi-settings-full is missing (check out with submodules)")
        return 1
    bad = []
    for rel in files():
        for line_no, text in stray(rel):
            bad.append("%s:%d  %s" % (rel, line_no, text[:100]))
    if bad:
        print("FAIL: Portuguese-only text an English user would see:")
        for b in bad:
            print("  " + b)
        print("\nWrap it in the file's tr()/t() helper with the English beside it,")
        print("or branch on the language. Only a translation table or a parser of")
        print("Portuguese input belongs in ALLOWED, with the reason.")
        return 1
    print("stray portuguese: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
