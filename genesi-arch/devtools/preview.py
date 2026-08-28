#!/usr/bin/env python3
"""Run the Genesi AI Mode Monitor UI on a machine that is not Genesi.

The Monitor is a PySide6 + QML app that imports org.kde.kirigami, so until now
it could only be looked at on a real Plasma desktop -- which meant every visual
change to it was written blind and verified by installing a package. That is a
bad loop for design work.

This harness closes it:

  * `kirigami-stub/` provides the nine Kirigami types the app actually uses
    (Units, Theme, Icon, Page, ApplicationWindow, InlineMessage, PromptDialog,
    Dialog, MessageType). Units carries Kirigami's real defaults, so the
    layout rhythm is the one the app will have on the desktop.
  * The backend is the REAL genesi_ai_monitor.Backend. Its OS calls
    (systemctl, ollama, the daemon's state file) simply fail on a non-Genesi
    box and return empty -- which is a state the shipped app has to survive
    anyway. `--demo` layers plausible content on top so the UI is populated
    the way a user's would be, for looking at design rather than behaviour.

    Usage:
        python devtools/preview.py                 # open the window
        python devtools/preview.py --demo          # ...with demo content
        python devtools/preview.py --shot out.png  # render once and exit

Not shipped. Nothing here is imported by the app; it exists so a change to the
UI can be seen before it is committed.
"""
import argparse
import json
import os
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
MONITOR = ROOT / "packages" / "genesi-ai-mode" / "monitor"
UIKIT = ROOT / "packages" / "genesi-ui-kit" / "components"


def _stage(tmp):
    """Lay the app out the way the package installs it: the shared UI-kit
    components sit NEXT TO the app's own QML, because QML resolves plain
    `Theme { }` from the same directory. Symlinks would need admin rights on
    Windows, so copy."""
    import shutil
    tmp.mkdir(parents=True, exist_ok=True)
    for src in MONITOR.glob("*.qml"):
        shutil.copy2(src, tmp / src.name)
    for name in ("Theme.qml", "I18n.qml", "GlassCard.qml", "GButton.qml",
                 "StatusBanner.qml"):
        src = UIKIT / name
        if src.exists():
            shutil.copy2(src, tmp / name)
    icons = MONITOR / "icons"
    if icons.is_dir():
        dest = tmp / "icons"
        if dest.exists():
            shutil.rmtree(dest)
        shutil.copytree(icons, dest)
    return tmp


DEMO_SESSIONS = [
    {"id": "s1", "title": "How can I improve my local AI…", "updated": 0, "count": 6},
    {"id": "s2", "title": "What's the best model for coding?", "updated": 0, "count": 4},
    {"id": "s3", "title": "How do I start using Genesi Find?", "updated": 0, "count": 3},
    {"id": "s4", "title": "What are the benefits of AI Mode?", "updated": 0, "count": 8},
    {"id": "s5", "title": "What's the difference between…", "updated": 0, "count": 2},
]

# A canned conversation, including a Genesi Find answer, so the file cards can
# be looked at without a Linux box and a real index.
DEMO_FILES = {
    "query": "the contract pdf I saved last month",
    "results": [
        {"path": "/home/g/Documents/contrato-locacao-2026.pdf",
         "name": "contrato-locacao-2026.pdf", "dir": "~/Documents",
         "age": "3w", "hsize": "812 KB"},
        {"path": "/home/g/Downloads/contrato-assinado.pdf",
         "name": "contrato-assinado.pdf", "dir": "~/Downloads",
         "age": "1mo", "hsize": "1.4 MB"},
        {"path": "/home/g/Documents/notas/anexo-contrato.odt",
         "name": "anexo-contrato.odt", "dir": "~/Documents/notas",
         "age": "1mo", "hsize": "44 KB"},
        {"path": "/home/g/Imagens/scan-contrato-p1.png",
         "name": "scan-contrato-p1.png", "dir": "~/Imagens",
         "age": "1mo", "hsize": "2.2 MB"},
    ],
}

DEMO_CHAT = {
    "id": "s1", "model": "llama3.2:3b",
    "messages": [
        {"role": "user", "stats": "",
         "body": "Which local model should I use for coding on a 6 GB card?"},
        {"role": "ai", "stats": "",
         "body": "For 6 GB of VRAM, qwen2.5-coder:7b at Q4_K_M is the sweet "
                 "spot: it fits with room for a 8k context and stays well "
                 "ahead of the 3b models on real code. Turn Turbo on so it is "
                 "served by llama-server with full GPU offload."},
        {"role": "user", "stats": "", "body": "the contract pdf I saved last month"},
        {"role": "files", "stats": "", "body": json.dumps(DEMO_FILES)},
    ],
}

DEMO_STATE = {
    "active": True, "mode": "auto", "profile": "auto",
    "cpu": 21.0, "ram": 46.0, "gpu": 12.0, "vram_used": 2100, "vram_total": 6144,
    "governor": "performance", "turbo_running": True, "turbo_model": "llama3.2:3b",
    "ollama": [{"name": "llama3.2:3b", "size": 2019393189}],
}


def _demo(backend):
    """Overlay plausible content on the real backend, without touching its
    logic: the point is to see a populated UI, not to fake behaviour."""
    from PySide6.QtCore import Slot

    cls = type(backend)
    cls.state = Slot(result=str)(lambda self: json.dumps(DEMO_STATE))
    cls.listSessions = Slot(result=str)(lambda self: json.dumps(DEMO_SESSIONS))
    cls.backendInfo = Slot(result=str)(
        lambda self: json.dumps({"backend": "cuda", "gpu": "NVIDIA RTX 3050"}))
    cls.quickModel = Slot(result=str)(lambda self: "llama3.2:3b")
    cls.loadSession = Slot(str, result=str)(lambda self, sid: json.dumps(DEMO_CHAT))
    cls.modelLabel = Slot(str, result=str)(lambda self, m: m or "llama3.2:3b")

    def _models(self):
        self.modelsLoaded.emit(json.dumps(["llama3.2:3b", "qwen2.5-coder:7b",
                                           "mistral:7b"]))
    cls.loadModels = Slot()(_models)
    return backend


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--shot", metavar="PNG",
                    help="render once, save a PNG and exit (no window)")
    ap.add_argument("--tab", type=int, default=None,
                    help="switch to this tab index before the shot")
    ap.add_argument("--demo", action="store_true",
                    help="populate the UI with plausible content")
    ap.add_argument("--seed-chat", action="store_true",
                    help="open a canned conversation (implies --demo --tab 1)")
    ap.add_argument("--size", default="1600x1000", help="window size WxH")
    ap.add_argument("--wait", type=float, default=1.6,
                    help="seconds to settle before the shot")
    args = ap.parse_args()

    # NOT offscreen for --shot. Qt's offscreen plugin on Windows has no font
    # database, so every glyph renders as a missing-glyph box and the shot is
    # useless for looking at type. A real (briefly visible) window it is.
    if args.shot:
        os.environ.setdefault("QT_QUICK_BACKEND", os.environ.get("QT_QUICK_BACKEND", ""))
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")

    staged = _stage(Path(os.environ.get("TEMP", "/tmp")) / "genesi-preview")
    sys.path.insert(0, str(MONITOR))

    from PySide6.QtCore import QUrl, QTimer, QMetaObject, Q_ARG
    from PySide6.QtGui import QGuiApplication, QFont
    from PySide6.QtQml import QQmlApplicationEngine
    from PySide6.QtQuick import QQuickWindow

    import genesi_ai_monitor as mon

    app = QGuiApplication(sys.argv)
    # The app asks for Rubik (shipped by genesi-ttf-rubik-vf) and the
    # offscreen platform has no fontconfig to fall back through, so every
    # glyph came out as a missing-glyph box. Substitute a font this machine
    # really has; the metrics differ slightly from Rubik but the layout,
    # which is what a preview is for, is the same.
    for _want in ("Rubik", "Rubik Variable"):
        QFont.insertSubstitutions(_want, ["Segoe UI", "DejaVu Sans", "Arial"])
    _f = QFont("Segoe UI")
    _f.setPixelSize(13)
    app.setFont(_f)
    engine = QQmlApplicationEngine()
    engine.addImportPath(str(HERE / "kirigami-stub"))

    backend = mon.Backend()
    if args.demo:
        _demo(backend)
    engine.rootContext().setContextProperty("backend", backend)
    # Relative icon paths ("icons/x.svg") resolve against the file that
    # DECLARES them; inside the stub Icon.qml that is the stub directory,
    # not the app. Hand the stub the app root so it can rebase them.
    engine.rootContext().setContextProperty(
        "genesiAppDir", QUrl.fromLocalFile(str(staged) + "/"))

    warnings = []
    engine.warnings.connect(lambda errs: warnings.extend(str(e) for e in errs))

    engine.load(QUrl.fromLocalFile(str(staged / "Main.qml")))
    roots = engine.rootObjects()
    if not roots:
        print("FAILED to load Main.qml")
        for w in warnings:
            print("  " + w)
        return 2

    win = roots[0]
    try:
        w, h = (int(x) for x in args.size.lower().split("x"))
        win.setWidth(w)
        win.setHeight(h)
    except ValueError:
        pass
    if args.tab is not None:
        win.setProperty("currentTab", args.tab)
    if args.seed_chat:
        # openSession() is a plain QML function on the window, which Qt exposes
        # as an invokable method.
        QMetaObject.invokeMethod(win, "openSession", Q_ARG("QVariant", "s1"))

    if not args.shot:
        for line in warnings:
            print("qml: " + line)
        return app.exec()

    def shoot():
        # The root object comes back typed as its QWindow base, so the
        # QQuickWindow method has to be called unbound.
        img = QQuickWindow.grabWindow(win)
        if img.isNull():
            print("grabWindow returned nothing")
            app.exit(3)
            return
        img.save(args.shot)
        print("wrote %s (%dx%d)" % (args.shot, img.width(), img.height()))
        for line in warnings:
            print("qml: " + line)
        app.exit(0)

    QTimer.singleShot(int(args.wait * 1000), shoot)
    # Never hang a CI/scripted run: the app keeps polling timers alive, so
    # without this a failed grab leaves the process running forever.
    QTimer.singleShot(int((args.wait + 25) * 1000), lambda: app.exit(4))
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
