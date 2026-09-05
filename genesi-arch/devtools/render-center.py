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


MONITORS = [
    {"name": "HDMI-A-1", "description": "Samsung", "width": 1920, "height": 1080,
     "refresh": 60.0, "x": 0, "y": 0, "scale": 1.0, "transform": 0, "rotation": 0,
     "focused": False, "disabled": False, "mode": "1920x1080@60.0",
     "modes": [{"width": 1920, "height": 1080, "refresh": 60.0, "id": "1920x1080@60.0"},
               {"width": 1920, "height": 1080, "refresh": 100.0, "id": "1920x1080@100.0"},
               {"width": 1600, "height": 900, "refresh": 60.0, "id": "1600x900@60.0"}]},
    {"name": "DP-1", "description": "AOC", "width": 1920, "height": 1080,
     "refresh": 143.98, "x": 1920, "y": 0, "scale": 1.0, "transform": 0, "rotation": 0,
     "focused": True, "disabled": False, "mode": "1920x1080@143.98",
     "modes": [{"width": 2560, "height": 1440, "refresh": 74.97, "id": "2560x1440@74.97"},
               {"width": 1920, "height": 1080, "refresh": 143.98, "id": "1920x1080@143.98"},
               {"width": 1920, "height": 1080, "refresh": 119.98, "id": "1920x1080@119.98"},
               {"width": 1920, "height": 1080, "refresh": 60.0, "id": "1920x1080@60.0"}]},
]


BAR = {
    "current": "20-centrado",
    "presets": [
        {"id": p, "name": n, "description": d,
         "entries": [{"id": e, "enabled": True} for e in ents]}
        for p, n, d, ents in [
            ("10-padrao", "Default · Padrão", "The bar as caelestia ships it",
             ["logo", "workspaces", "spacer", "activeWindow", "spacer", "tray",
              "clock", "statusIcons", "power"]),
            ("20-centrado", "Centred · Centralizado",
             "Logo at the top, workspaces in the middle, the rest at the bottom",
             ["logo", "spacer", "workspaces", "spacer", "tray", "clock",
              "statusIcons", "power"]),
            ("30-minimo", "Minimal · Mínimo", "Workspaces and the time, nothing else",
             ["spacer", "workspaces", "spacer", "clock"]),
            ("40-numeros", "Numbered · Números",
             "Workspaces as numbers instead of dots",
             ["logo", "workspaces", "spacer", "activeWindow", "spacer", "tray",
              "clock", "statusIcons", "power"]),
            ("50-janelas", "Windows · Janelas",
             "Each workspace shows the icons of what is open in it",
             ["logo", "workspaces", "spacer", "activeWindow", "spacer", "tray",
              "clock", "statusIcons", "power"]),
            ("60-informativo", "Dense · Informativo",
             "Everything on: date, audio, microphone, keyboard layout",
             ["logo", "workspaces", "spacer", "activeWindow", "spacer", "tray",
              "clock", "statusIcons", "power"]),
            ("70-compacto", "Compact · Compacto",
             "Tighter icons and fewer workspaces",
             ["logo", "workspaces", "spacer", "tray", "clock", "power"]),
            ("80-limpo", "Clean · Limpo", "No tray and no status icons",
             ["logo", "workspaces", "spacer", "activeWindow", "spacer",
              "clock", "power"]),
            ("90-trilha", "Trail · Trilha", "The active workspace leaves a trail",
             ["logo", "workspaces", "spacer", "activeWindow", "spacer", "tray",
              "clock", "statusIcons", "power"]),
            ("95-oculta", "Auto-hide · Oculta",
             "The bar stays out of the way until you reach for it",
             ["logo", "workspaces", "spacer", "activeWindow", "spacer", "tray",
              "clock", "statusIcons", "power"]),
        ]
    ],
}


class Backend(QObject):
    dataReady = Signal(str)
    displaysReady = Signal(str)
    barPresetsReady = Signal(str)

    @Slot()
    def displays(self):
        self.displaysReady.emit(json.dumps(MONITORS))

    @Slot(list)
    def displayCmd(self, args):
        pass

    @Slot()
    def barPresets(self):
        self.barPresetsReady.emit(json.dumps(BAR))

    @Slot(str)
    def barApply(self, preset):
        pass

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
# A fifth argument names the session to pretend to be ("plasma" or
# "hyprland"), so the rail can be reviewed as each desktop actually sees it.
CAPS = {"hyprland": True, "caelestia": True, "plasma": False}
if len(sys.argv) > 5 and sys.argv[5] == "plasma":
    CAPS = {"hyprland": False, "caelestia": False, "plasma": True}

engine.setInitialProperties({"backend": backend, "treeArt": tree, "caps": CAPS})
print("session:", "plasma" if not CAPS["hyprland"] else "hyprland")
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


# A second argument is a capture time in ms, measured from the moment the data
# arrives. The default waits for everything to finish; a smaller number catches
# the page mid-assembly, which is the only way to see whether the motion is
# actually there rather than trusting that a NumberAnimation ran.
AT = int(sys.argv[2]) if len(sys.argv) > 2 else 1800

# A third argument resizes the window ("1100x720"). Layouts that were fitted by
# eye at one size come apart at another, and the smallest size the window
# allows is where that shows first.
if len(sys.argv) > 3:
    w, _, h = sys.argv[3].partition("x")
    win.setWidth(int(w))
    win.setHeight(int(h))
    settle(120)

if len(sys.argv) > 4:
    win.setProperty("section", sys.argv[4])

settle(300)
backend.dataReady.emit(json.dumps(SAMPLE))
settle(AT)
print(f"captured {AT}ms after the first reading")

img = win.grabWindow()
img.save(OUT)
print(f"saved {OUT}  {img.width()}x{img.height()}")

real = [w for w in warnings if "TypeError" in w or "is not a" in w
        or "Unable to assign" in w or "Cannot assign" in w or "ReferenceError" in w]
print(f"warnings: {len(warnings)}  (structural: {len(real)})")
for w in real[:14]:
    print("  ", w)
