"""
render-topbar.py — draw the Genesi bar to a PNG, with no Quickshell.

    python genesi-arch/devtools/render-topbar.py out.png [width]

The bar's visual layer is plain QtQuick and takes everything as properties, so
it renders anywhere Qt does. That split exists FOR this: Quickshell does not
run on the machine this is written on, and a bar built as one file would be the
only thing in the project shipped without anyone having looked at it.

What this cannot check is the half it does not touch -- the layer-shell
anchoring, the exclusive zone, the Hyprland IPC, the real tray. Those are
shell.qml's, and they get checked on hardware.

    QT_QPA_FONTDIR=/usr/share/fonts python genesi-arch/devtools/render-topbar.py out.png
"""
import os
import tempfile
import sys

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
from PySide6.QtCore import QUrl, QTimer, QEventLoop
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlEngine, QQmlComponent
from PySide6.QtQuick import QQuickView

HERE = os.path.dirname(os.path.abspath(__file__))
QS = os.path.join(HERE, "..", "packages", "genesi-topbar", "quickshell")
OUT = sys.argv[1] if len(sys.argv) > 1 else "topbar.png"
WIDTH = int(sys.argv[2]) if len(sys.argv) > 2 else 1600

def stand_in_icons():
    """
    Stand-ins for the icons the desktop database would resolve.

    On a running system shell.qml hands over real paths from the icon theme.
    There is no icon theme on the machine this renders on, so these are drawn
    here: three flat colours, at the size an app icon would be. They prove the
    LAYOUT -- how many fit in a pill, how the row breathes when one appears --
    which is the half this tool exists to check.
    """
    from PySide6.QtGui import QImage, QPainter, QColor
    d = os.path.join(tempfile.gettempdir(), "genesi-topbar-fixture")
    os.makedirs(d, exist_ok=True)
    out = []
    for name, rgb in (("firefox", "#e86a33"), ("code", "#3b82f6"),
                      ("terminal", "#8b5cf6"), ("files", "#eab308")):
        p = os.path.join(d, name + ".png")
        img = QImage(64, 64, QImage.Format_ARGB32)
        img.fill(QColor(0, 0, 0, 0))
        pt = QPainter(img)
        pt.setRenderHint(QPainter.Antialiasing)
        pt.setBrush(QColor(rgb))
        pt.setPen(QColor(0, 0, 0, 0))
        pt.drawRoundedRect(4, 4, 56, 56, 14, 14)
        pt.end()
        img.save(p)
        out.append((name, QUrl.fromLocalFile(p).toString()))
    return dict(out)


ICON = stand_in_icons()

# A desk in use, not an empty one: workspaces holding real windows, one window
# whose class resolves to nothing (it must fall back to a letter, not to a
# broken-image glyph), and one workspace over the icon cap so the "+2" shows.
WORKSPACES = [
    {"id": 1, "occupied": True, "active": False, "windows": 3,
     "icons": [{"name": "firefox", "source": ICON["firefox"]},
               {"name": "code", "source": ICON["code"]},
               {"name": "some-appimage", "source": ""}]},
    {"id": 2, "occupied": True, "active": True, "windows": 1,
     "icons": [{"name": "terminal", "source": ICON["terminal"]}]},
    {"id": 3, "occupied": False, "active": False, "windows": 0, "icons": []},
    {"id": 4, "occupied": False, "active": False, "windows": 0, "icons": []},
    {"id": 5, "occupied": True, "active": False, "windows": 6,
     "icons": [{"name": "files", "source": ICON["files"]},
               {"name": "code", "source": ICON["code"]},
               {"name": "firefox", "source": ICON["firefox"]},
               {"name": "terminal", "source": ICON["terminal"]},
               {"name": "code", "source": ICON["code"]},
               {"name": "files", "source": ICON["files"]}]},
]
TRAY = [
    {"id": "genesi-update", "icon": "", "tooltip": "Genesi Update"},
    {"id": "genesi-ai", "icon": "", "tooltip": "AI Mode"},
    {"id": "containers", "icon": "", "tooltip": "Containers"},
]
STATUS = {"volume": 54, "network": "wifi", "battery": 100}

from PySide6.QtCore import qInstallMessageHandler
_msgs = []
qInstallMessageHandler(lambda m, c, msg: _msgs.append(msg))

app = QGuiApplication(sys.argv)
view = QQuickView()
view.engine().addImportPath(os.path.abspath(QS))
view.setInitialProperties({
    "workspaces": WORKSPACES,
    "activeWindow": "genesi-code — DisplaysPage.qml",
    "clockText": "01:17",
    "dateText": "Fri, Sep 5",
    "trayItems": TRAY,
    "status": STATUS,
})
view.setSource(QUrl.fromLocalFile(os.path.join(QS, "BarContent.qml")))

if view.status() == QQuickView.Error:
    print("LOAD FAILED")
    for e in view.errors():
        print("   ", e.toString())
    sys.exit(1)

# Without this the root Item keeps its own implicitWidth -- which is 0, since
# the bar is meant to be stretched by the panel window. Everything anchored to
# `parent.right` then anchored to nothing and the whole right block vanished.
view.setResizeMode(QQuickView.SizeRootObjectToView)
view.setWidth(WIDTH)
view.setHeight(34)
# The bar sits on a wallpaper, so a transparent capture would be a lie about
# contrast. A mid-dark ground is the honest test.
view.setColor("#0b1210")
view.show()


def settle(ms):
    loop = QEventLoop()
    QTimer.singleShot(ms, loop.quit)
    loop.exec()


settle(700)
img = view.grabWindow()
img.save(OUT)
print(f"saved {OUT}  {img.width()}x{img.height()}")
real = [m for m in _msgs if "TypeError" in m or "ReferenceError" in m
        or "is not a" in m or "Unable to" in m or "Cannot" in m]
print(f"warnings: {len(_msgs)}  (structural: {len(real)})")
for m in real[:12]:
    print("   ", m)
