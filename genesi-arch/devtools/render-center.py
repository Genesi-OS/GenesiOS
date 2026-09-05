"""
render-center.py — draw Genesi Center to a PNG, with no desktop.

    python genesi-arch/devtools/render-center.py out.png

Why this exists: the app is judged on whether it looks right, and "looks right"
cannot be checked by reading QML. Rendering it offscreen and looking at the
result caught, in one pass, a telemetry grid sized for three rows while holding
four -- the eighth tile drew straight through the heading below it -- and
sparklines that stayed blank until the second tick.

It feeds one realistic payload, the same shape `genesi-center-data` prints,
because a dashboard full of em-dashes says nothing about whether the layout
works.

On a machine with no fontconfig (a bare offscreen Qt) every glyph renders as a
box and the output tells you nothing about type. Point Qt at a font directory
first if that happens:

    QT_QPA_FONTDIR=/usr/share/fonts python genesi-arch/devtools/render-center.py out.png
"""
import io
import json
import os
import sys

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
from PySide6.QtCore import QUrl, QTimer, QEventLoop, QObject, Signal, Slot, Qt
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.join(HERE, "..", "packages", "genesi-center", "app")
OUT = sys.argv[1] if len(sys.argv) > 1 else "center.png"

SAMPLE = {
    "telemetry": {
        "cpu_percent": 15,
        "memory": {"used_mb": 6246, "total_mb": 16384, "percent": 38},
        "disk": {"used_gb": 118, "total_gb": 256, "percent": 42},
        "temperature_c": 47,
        "network": {"rx_bps": 3481, "tx_bps": 2764},
        "uptime": {"seconds": 225120, "text": "2d 14h 32m"},
        "processes": 189,
        "users": {"count": 1, "names": ["matheus"]},
    },
    "core": {"kernel": "6.8.7-genesi", "arch": "x86_64", "build": "2025.05.20",
             "session": "Genesi Shell", "name": "Genesi OS", "version": "0.8.3"},
    "storage": {"total_gb": 256, "used_gb": 180, "percent": 70,
                "slices": [{"label": "system", "gb": 68},
                           {"label": "data", "gb": 118},
                           {"label": "other", "gb": 70}]},
    # The same wording genesi-center-data actually prints, so the render is not
    # kinder to the layout than reality is.
    "activity": {"items": [
        {"kind": "package", "text": "upgraded genesi-caelestia-shell", "when": "2026-09-05 00:41"},
        {"kind": "package", "text": "upgraded genesi-center", "when": "2026-09-05 00:41"},
        {"kind": "package", "text": "installed genesi-audio", "when": "2026-09-04 20:58"},
        {"kind": "boot", "text": "system started", "when": "2026-09-04 19:12:14"},
    ]},
}


class Backend(QObject):
    dataReady = Signal(str)

    @Slot(list)
    def launch(self, argv):
        pass


app = QGuiApplication(sys.argv)
engine = QQmlApplicationEngine()
engine.addImportPath(APP)
backend = Backend()
# Resolve the artwork exactly as genesi_center.py does, so this renders the
# page a user gets rather than one without its art.
tree = ""
for cand in (os.path.expanduser("~/.config/genesi/center/tree.png"),
             os.path.join(APP, "art", "tree.png")):
    if os.path.exists(cand):
        tree = "file:///" + os.path.abspath(cand).replace("\\", "/")
        break
engine.setInitialProperties({"backend": backend, "treeArt": tree})
print("artwork:", tree or "(none -- the page draws its own glow)")

warnings = []
engine.warnings.connect(lambda ws: warnings.extend(w.toString() for w in ws))
engine.load(QUrl.fromLocalFile(os.path.join(APP, "Main.qml")))

roots = engine.rootObjects()
if not roots:
    print("LOAD FAILED")
    for w in warnings:
        print("  ", w)
    sys.exit(1)

win = roots[0]


def settle(ms):
    loop = QEventLoop()
    QTimer.singleShot(ms, loop.quit)
    loop.exec()


settle(300)
backend.dataReady.emit(json.dumps(SAMPLE))
# Long enough for the entrance sweep and the ring to finish.
settle(1600)

img = win.grabWindow()
img.save(OUT)
print(f"saved {OUT}  {img.width()}x{img.height()}")

real = [w for w in warnings if "TypeError" in w or "is not a" in w
        or "Unable to assign" in w or "Cannot assign" in w or "ReferenceError" in w]
print(f"warnings: {len(warnings)}  (structural: {len(real)})")
for w in real[:14]:
    print("  ", w)
