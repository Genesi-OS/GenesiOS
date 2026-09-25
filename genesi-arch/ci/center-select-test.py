#!/usr/bin/env python3
"""
A pick from an open dropdown lands on the dropdown, and nowhere else.

Genesi Center's Select draws its list at the top of the scene, over the rows
below it. Drawn over is not the same as catching the click: its rows used a
TapHandler, which takes only a PASSIVE grab, so the press carried on to
whatever lay beneath. On the Displays page, picking "1680 x 1050" from the
resolution list also pressed the 90-degree rotation button under it, and
both fired -- reported as "the click lands on the rotation button".

This opens the real Displays page offscreen against a fake backend, opens the
resolution list, clicks the row lying over a rotation button, and checks the
backend was asked for the mode and nothing else. Then it clicks off the list
and checks that closed it without reaching anything.
"""
import json
import os
import sys
import tempfile

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
from PySide6.QtCore import QObject, QPoint, QPointF, Qt, QUrl, Signal, Slot  # noqa: E402
from PySide6.QtGui import QGuiApplication  # noqa: E402
from PySide6.QtQuick import QQuickView  # noqa: E402
from PySide6.QtTest import QTest  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAGES = os.path.join(ROOT, "packages", "genesi-center", "app", "pages")

MODES = [(2560, 1440), (1920, 1200), (1920, 1080), (1680, 1050), (1600, 900),
         (1440, 900), (1280, 1024), (1280, 720), (1024, 768)]
MONITOR = [{
    "name": "DP-1", "description": "", "width": 2560, "height": 1440,
    "refresh": 60.0, "x": 0, "y": 0, "scale": 1, "transform": 0, "rotation": 0,
    "focused": True, "primary": True, "mode": "2560x1440@60.0",
    "modes": [{"id": f"{w}x{h}@60.0", "width": w, "height": h, "refresh": 60.0}
              for w, h in MODES],
}]

failures = []


def check(ok, what):
    print(("  ok    " if ok else "  FAIL  ") + what)
    if not ok:
        failures.append(what)


class Backend(QObject):
    displaysReady = Signal(str)

    def __init__(self):
        super().__init__()
        self.calls = []

    @Slot()
    def displays(self):
        self.displaysReady.emit(json.dumps(MONITOR))

    @Slot(list)
    def displayCmd(self, args):
        self.calls.append(list(args))


def walk(item, pred, acc):
    if pred(item):
        acc.append(item)
    for c in item.childItems():
        walk(c, pred, acc)
    return acc


def labelled(root, test):
    def pred(i):
        d = i.property("modelData")
        return isinstance(d, dict) and test(str(d.get("label", "")))
    return walk(root, pred, [])


def centre(item):
    p = item.mapToScene(QPointF(item.width() / 2, item.height() / 2))
    return QPoint(int(p.x()), int(p.y()))


app = QGuiApplication(sys.argv)
view = QQuickView()
backend = Backend()
view.rootContext().setContextProperty("fakeBackend", backend)
wrapper = os.path.join(tempfile.mkdtemp(), "Wrapper.qml")
with open(wrapper, "w", encoding="utf-8") as fh:
    fh.write("import QtQuick\n"
             f'import "{QUrl.fromLocalFile(PAGES).toString()}"\n'
             "Item { width: 1200; height: 760\n"
             "  DisplaysPage { anchors.fill: parent; backend: fakeBackend } }\n")
view.setSource(QUrl.fromLocalFile(wrapper))
errors = [e.toString() for e in view.errors()]
check(not errors, "the Displays page loads" + (f": {errors[0]}" if errors else ""))
if errors:
    sys.exit(1)
view.show()
QTest.qWait(300)

scene = view.contentItem()
select = walk(scene, lambda i: i.property("maxShown") is not None, [])[0]
QTest.mouseClick(view, Qt.LeftButton, Qt.NoModifier, centre(select))
QTest.qWait(150)
check(select.property("open") is True, "clicking the resolution field opens its list")

rotations = labelled(scene, lambda s: s.endswith("°"))
rows = labelled(scene, lambda s: "×" in s and "Hz" in s)
pair = None
for r in rows:
    rp = r.mapToScene(QPointF(0, 0))
    for b in rotations:
        c = b.mapToScene(QPointF(b.width() / 2, b.height() / 2))
        if rp.y() <= c.y() <= rp.y() + r.height() and rp.x() <= c.x() <= rp.x() + r.width():
            pair = (r, b)
            break
    if pair:
        break
check(pair is not None, "some resolution row lies over a rotation button (the case under test)")
if pair:
    row, button = pair
    wanted = row.property("modelData")["id"]
    backend.calls.clear()
    QTest.mouseClick(view, Qt.LeftButton, Qt.NoModifier, centre(button))
    QTest.qWait(150)
    check(backend.calls == [["mode", "DP-1", wanted]],
          f"the pick asks for {wanted} and nothing else (got {backend.calls})")
    check(select.property("open") is False, "the list closes after a pick")

QTest.mouseClick(view, Qt.LeftButton, Qt.NoModifier, centre(select))
QTest.qWait(150)
backend.calls.clear()
if rotations:
    # Well away from the list: the rotation buttons that are NOT under it
    # would do, but a click on the page's heading is the plainest case.
    QTest.mouseClick(view, Qt.LeftButton, Qt.NoModifier, QPoint(60, 40))
    QTest.qWait(150)
check(select.property("open") is False and backend.calls == [],
      "a click off the list closes it and reaches nothing")

if failures:
    print(f"\n{len(failures)} failure(s)")
    sys.exit(1)
print("\nall good")
