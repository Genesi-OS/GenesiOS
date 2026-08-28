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
PKGS = ROOT / "packages"
UIKIT = PKGS / "genesi-ui-kit" / "components"

# Every Genesi Qt app is built the same way: a `Backend(QObject)` handed to QML
# as `backend`, and a Main.qml next to it. That uniformity is what lets one
# harness drive all of them.
APPS = {
    "monitor":    ("genesi-ai-mode/monitor", "genesi_ai_monitor"),
    # Same directory, different app: the Quick Chat overlay is its own binary
    # with its own root QML.
    "quickchat":  ("genesi-ai-mode/monitor", "genesi_ai_quick", "QuickChat.qml"),
    # find/ borrows FileCard + FIcon + the icon set from monitor/ at build; the
    # harness has to stage them the same way or the window will not load.
    "find":       ("genesi-ai-mode/find",    "genesi_find_gui", "Main.qml",
                   "genesi-ai-mode/monitor"),
    "forge":      ("genesi-forge/app",       "genesi_forge"),
    "netinspect": ("genesi-netinspect/app",  "genesi_netinspect"),
    "ports":      ("genesi-ports/app",       "genesi_ports"),
    "sandboxes":  ("genesi-sandboxes/app",   "genesi_sandboxes"),
    "snapshots":  ("genesi-snapshots/app",   "genesi_snapshots"),
}


def _stage(appdir, tmp, borrow=None):
    """Lay an app out the way its package installs it: the shared UI-kit
    components sit NEXT TO the app's own QML, because QML resolves a plain
    `Theme { }` from the same directory. Symlinks would need admin rights on
    Windows, so copy.

    The kit goes down FIRST and the app's own files over the top: Forge ships
    its own FIcon/FCard/GButton, and those must win over the kit's."""
    import shutil
    if tmp.exists():
        shutil.rmtree(tmp, ignore_errors=True)
    tmp.mkdir(parents=True, exist_ok=True)
    for src in UIKIT.glob("*.qml"):
        shutil.copy2(src, tmp / src.name)
    if borrow is not None:
        for src in borrow.glob("*.qml"):
            shutil.copy2(src, tmp / src.name)
        if (borrow / "icons").is_dir():
            shutil.copytree(borrow / "icons", tmp / "icons", dirs_exist_ok=True)
    for src in appdir.glob("*.qml"):
        shutil.copy2(src, tmp / src.name)
    icons = appdir / "icons"
    if icons.is_dir():
        shutil.copytree(icons, tmp / "icons", dirs_exist_ok=True)
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

# A small but real automation graph, so the Automations canvas can be looked at
# with cards on it. Shapes match what the daemon writes to disk.
DEMO_AUTOMATION = {
    "id": "a1", "name": "Firefox RAM watch", "enabled": True,
    "nodes": [
        {"id": "n1", "kind": "evt_app", "title": "Firefox opens", "icon": "box",
         "accentKey": "purple", "x": 60, "y": 70,
         "lines": ["firefox", "varName: opened"],
         "config": {"app": "firefox", "transition": "opened", "varName": "opened"}},
        {"id": "n2", "kind": "act_ai", "title": "Measure the RAM", "icon": "bot",
         "accentKey": "violet", "x": 330, "y": 60,
         "lines": ["llama3.2:3b", "advisory", "outputs: ram_before"],
         "config": {"prompt": "how much RAM is firefox using", "exec": "advisory"}},
        {"id": "n3", "kind": "evt_app", "title": "Firefox closes", "icon": "box",
         "accentKey": "purple", "x": 600, "y": 70,
         "lines": ["{{opened.name}}", "waits here"],
         "config": {"app": "{{opened.name}}", "transition": "closed"}},
        {"id": "n4", "kind": "act_cond", "title": "Did it grow?", "icon": "git-branch",
         "accentKey": "blue", "x": 330, "y": 260,
         "lines": ["{{ram_after}} > {{ram_before}}"], "config": {}},
        {"id": "n5", "kind": "act_notify", "title": "Tell me", "icon": "alert",
         "accentKey": "green", "x": 600, "y": 265,
         "lines": ["Firefox: {{ram_before}} to {{ram_after}}"], "config": {}},
    ],
    "links": [
        {"from": "n1", "to": "n2", "fromPort": ""},
        {"from": "n2", "to": "n3", "fromPort": "ok"},
        {"from": "n3", "to": "n4", "fromPort": ""},
        {"from": "n4", "to": "n5", "fromPort": "true"},
    ],
}

DEMO_STATE = {
    "active": True, "mode": "auto", "profile": "auto",
    "cpu": 21.0, "ram": 46.0, "gpu": 12.0, "vram_used": 2100, "vram_total": 6144,
    "governor": "performance", "turbo_running": True, "turbo_model": "llama3.2:3b",
    "ollama": [{"name": "llama3.2:3b", "size": 2019393189}],
}


# PortScope reads listeners from `ss`/`lsof`, which do not exist here, so the
# window comes up empty and there is nothing to design against.
DEMO_PORTS = [
    {"id": "1", "port": 5432, "proto": "tcp", "address": "127.0.0.1",
     "scope": "local", "pid": 1284, "process": "postgres", "user": "postgres",
     "stack": "PostgreSQL", "command": "/usr/bin/postgres -D /var/lib/postgres/data"},
    {"id": "2", "port": 11434, "proto": "tcp", "address": "127.0.0.1",
     "scope": "local", "pid": 2210, "process": "ollama", "user": "matheus",
     "stack": "Ollama", "command": "/usr/bin/ollama serve"},
    {"id": "3", "port": 8080, "proto": "tcp", "address": "0.0.0.0",
     "scope": "all", "pid": 3391, "process": "node", "user": "matheus",
     "stack": "Node.js", "command": "node server.js"},
    {"id": "4", "port": 8737, "proto": "tcp", "address": "127.0.0.1",
     "scope": "local", "pid": 4102, "process": "python3", "user": "matheus",
     "stack": "Genesi Automations", "command": "python3 /usr/bin/genesi-automationd"},
    {"id": "5", "port": 22, "proto": "tcp", "address": "0.0.0.0",
     "scope": "all", "pid": 812, "process": "sshd", "user": "root",
     "stack": "OpenSSH", "command": "sshd: /usr/bin/sshd -D"},
    {"id": "6", "port": 5353, "proto": "udp", "address": "0.0.0.0",
     "scope": "all", "pid": 940, "process": "avahi-daemon", "user": "avahi",
     "stack": "Avahi", "command": "avahi-daemon: running"},
]


# Snapshots needs a Btrfs root, which the dev box does not have, so the app
# only ever shows its "unavailable" branch. This is the working state.
DEMO_SNAP_STATUS = {"btrfs": True, "configured": True, "snapPac": True,
                    "grubBtrfs": True, "count": 5}
DEMO_SNAPS = [
    {"number": 142, "date": "2026-08-26 11:04", "description": "pacman -Syu", "type": "pre"},
    {"number": 141, "date": "2026-08-26 11:04", "description": "pacman -Syu", "type": "post"},
    {"number": 138, "date": "2026-08-25 19:22", "description": "before installing nvidia-dkms", "type": "single"},
    {"number": 131, "date": "2026-08-24 08:15", "description": "timeline", "type": "timeline"},
    {"number": 120, "date": "2026-08-22 21:47", "description": "manual — before the mesh test", "type": "single"},
]


def _demo_snapshots(backend):
    return backend


def _demo_ports(backend):
    from PySide6.QtCore import Slot
    cls = type(backend)

    def _refresh(self):
        # The payload is an OBJECT with a `listeners` key, not a bare array --
        # same shape the CLI's list-json emits.
        self.listenersLoaded.emit(json.dumps({"listeners": DEMO_PORTS}))
    cls.refresh = Slot()(_refresh)
    return backend


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
    cls.listAutomations = Slot(result=str)(lambda self: json.dumps(
        [{"id": "a1", "name": "Firefox RAM watch", "enabled": True}]))
    cls.loadAutomation = Slot(str, result=str)(
        lambda self, aid: json.dumps(DEMO_AUTOMATION))
    cls.modelLabel = Slot(str, result=str)(lambda self, m: m or "llama3.2:3b")

    def _models(self):
        self.modelsLoaded.emit(json.dumps(["llama3.2:3b", "qwen2.5-coder:7b",
                                           "mistral:7b"]))
    cls.loadModels = Slot()(_models)
    return backend


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--app", default="monitor", choices=sorted(APPS),
                    help="which Genesi app to run (default: monitor)")
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

    _entry = APPS[args.app]
    subdir, modname = _entry[0], _entry[1]
    mainqml = _entry[2] if len(_entry) > 2 else "Main.qml"
    appdir = PKGS / subdir
    borrow = PKGS / _entry[3] if len(_entry) > 3 else None
    staged = _stage(appdir,
                    Path(os.environ.get("TEMP", "/tmp")) / ("genesi-preview-" + args.app),
                    borrow)
    sys.path.insert(0, str(appdir))

    from PySide6.QtCore import QUrl, QTimer, QMetaObject, Q_ARG
    from PySide6.QtGui import QGuiApplication, QFont
    from PySide6.QtQml import QQmlApplicationEngine
    from PySide6.QtQuick import QQuickWindow

    import importlib
    if args.app == "netinspect":
        # genesi-netinspect refuses to start without mitmproxy, which is the
        # right behaviour for the app and useless here: the interception engine
        # has nothing to do with what the window looks like. A stub module lets
        # the import succeed; nothing in the preview ever calls into it.
        import types
        for _name in ("mitmproxy", "mitmproxy.tools", "mitmproxy.tools.dump"):
            sys.modules.setdefault(_name, types.ModuleType(_name))
        _mp = sys.modules["mitmproxy"]

        class _Any:
            """Answers to any attribute with a class, because the addon uses
            these names in type ANNOTATIONS (http.HTTPFlow), which are
            evaluated at import time."""
            def __getattr__(self, _name):
                return type(_name, (), {})

        for _attr in ("options", "ctx", "http"):
            setattr(_mp, _attr, _Any())
        sys.modules["mitmproxy.tools.dump"].DumpMaster = object
    mon = importlib.import_module(modname)

    app = QGuiApplication(sys.argv)
    # The apps set these in their own main(), which the harness never calls --
    # without them QSettings refuses to initialise and I18n.qml warns that it
    # cannot persist the language. That warning is the harness's, not the app's,
    # and a harness that cries wolf is worse than no harness.
    app.setOrganizationName("Genesi OS")
    app.setOrganizationDomain("genesios.org")
    app.setApplicationName("Genesi Preview")
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

    # Some apps SUBCLASS another app's Backend and add slots (Quick Chat
    # extends the Monitor's). Instantiating the base class by name would leave
    # those missing, and QML would report them as "not a function" -- an error
    # about the harness dressed up as an error about the app.
    _cls = None
    for _n in dir(mon):
        _c = getattr(mon, _n)
        if (isinstance(_c, type) and _n.endswith("Backend")
                and _c.__module__ == mon.__name__):
            _cls = _c
            break
    backend = (_cls or mon.Backend)()
    if args.demo and args.app == "monitor":
        _demo(backend)
    elif args.demo and args.app == "ports":
        _demo_ports(backend)
    engine.rootContext().setContextProperty("backend", backend)
    # genesi-find-ui reads a second context property its own main() sets; QML
    # cannot see an undefined context property at all, so the file fails to load
    # without it.
    engine.rootContext().setContextProperty("initialScope", "")
    # Relative icon paths ("icons/x.svg") resolve against the file that
    # DECLARES them; inside the stub Icon.qml that is the stub directory,
    # not the app. Hand the stub the app root so it can rebase them.
    engine.rootContext().setContextProperty(
        "genesiAppDir", QUrl.fromLocalFile(str(staged) + "/"))

    warnings = []
    engine.warnings.connect(lambda errs: warnings.extend(str(e) for e in errs))

    engine.load(QUrl.fromLocalFile(str(staged / mainqml)))
    roots = engine.rootObjects()
    if not roots:
        print("FAILED to load " + mainqml)
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
    if args.demo and args.app == "snapshots" and args.seed_chat:
        # --seed-chat doubles as "show the recovery branch" here: booted INTO a
        # snapshot, which is the third code path and the one with the
        # restoreBooted() button on it.
        QTimer.singleShot(200, lambda: (
            backend.statusLoaded.emit(json.dumps(DEMO_SNAP_STATUS)),
            backend.snapshotsLoaded.emit(json.dumps(
                {"configured": True, "snapshots": DEMO_SNAPS})),
            backend.recoveryLoaded.emit(json.dumps(
                {"recovery": True, "number": 138, "target": "/"}))))
    elif args.demo and args.app == "snapshots":
        QTimer.singleShot(200, lambda: (
            backend.statusLoaded.emit(json.dumps(DEMO_SNAP_STATUS)),
            backend.snapshotsLoaded.emit(json.dumps(
                {"configured": True, "snapshots": DEMO_SNAPS}))))
    if args.demo and args.app == "find":
        QTimer.singleShot(200, lambda: backend.resultsReady.emit(
            json.dumps(DEMO_FILES)))
    if args.demo and args.app == "ports":
        # Push the rows in AFTER the tree is up. Overriding refresh() and
        # relying on the app to call it is a guess about startup order; this is
        # not.
        QTimer.singleShot(200, lambda: backend.listenersLoaded.emit(
            json.dumps({"listeners": DEMO_PORTS})))
    if args.seed_chat and args.app == "monitor":
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
