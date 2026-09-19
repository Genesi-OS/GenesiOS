#!/usr/bin/env python3
"""
sddm-shot.py — render the Genesi login screen without rebooting into it.

SDDM's greeter is a QML application that runs as root, before anybody has
logged in, against context properties SDDM itself injects: `sddm`, the object
with login() and powerOff() on it, and `userModel`/`sessionModel`, which are
list models whose roles have quietly moved between SDDM versions. So there is
no way to open the thing in a window and look at it -- unless those are
stubbed, which is what this does.

Two uses:

    python3 genesi-arch/ci/sddm-shot.py
        Render packages/genesi-store/sddm into that theme's preview.png. That
        file is the Screenshot= its metadata.desktop has always declared, and
        it is the picture on the theme's card in the store -- so the card
        shows the actual login screen this package installs, drawn from the
        actual QML, rather than a mock-up that drifts away from it.

    python3 genesi-arch/ci/sddm-shot.py <theme-dir> <out.png>
        Any SDDM theme, anywhere.

This is a tool, not a check: it needs a Qt that can draw, which a CI runner
may not have. Run it when the greeter changes, and commit the picture.
"""
import io
import os
import sys

from PySide6.QtCore import (QAbstractListModel, QModelIndex, QObject, Qt,
                            QTimer, QUrl, Signal, Slot, qInstallMessageHandler)
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
# Imported for its side effect: without it the engine's root comes back
# as a plain QWindow, which has no grabWindow() on it.
from PySide6.QtQuick import QQuickWindow      # noqa: F401

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
THEME_DEFAULT = os.path.join(ROOT, "genesi-arch", "packages", "genesi-store",
                             "sddm")


class Rows(QAbstractListModel):
    """SDDM's user and session models, near enough.

    The roles are answered by NUMBER as well as by name because that is how
    the real ones have behaved across versions -- a greeter that reads them by
    one name and not the other is the greeter that comes up with a blank
    username, and this is the stub that would hide it.
    """

    def __init__(self, rows):
        super().__init__()
        self._rows = rows

    def rowCount(self, parent=QModelIndex()):
        return len(self._rows)

    def data(self, index, role=Qt.DisplayRole):
        if not index.isValid():
            return None
        name, real = self._rows[index.row()]
        if role in (Qt.UserRole + 1, 257):
            return name
        if role in (Qt.UserRole + 2, 258, Qt.UserRole + 4, 260):
            return real
        return name

    @property
    def count(self):
        return len(self._rows)

    lastIndex = 0


class Sddm(QObject):
    loginSucceeded = Signal()
    loginFailed = Signal()

    @Slot(str, str, int)
    def login(self, user, password, session):
        self.loginFailed.emit()

    @Slot()
    def powerOff(self):
        pass

    @Slot()
    def reboot(self):
        pass

    @Slot()
    def suspend(self):
        pass


def main():
    theme = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else THEME_DEFAULT
    out = (os.path.abspath(sys.argv[2]) if len(sys.argv) > 2
           else os.path.join(theme, "preview.png"))
    if not os.path.isdir(theme):
        sys.exit("%s is not a theme directory" % theme)

    app = QGuiApplication([])
    engine = QQmlApplicationEngine()
    ctx = engine.rootContext()
    ctx.setContextProperty("sddm", Sddm())
    ctx.setContextProperty("userModel", Rows([("genesi", "Genesi"),
                                              ("convidado", "Convidado")]))
    ctx.setContextProperty("sessionModel",
                           Rows([("hyprland", "Hyprland (Genesi)"),
                                 ("plasma", "Plasma (Wayland)")]))
    ctx.setContextProperty("config", {"accent": "#39d98a",
                                      "surface": "#070c09",
                                      "background": "",
                                      "twelveHour": "false"})

    problems = []
    qInstallMessageHandler(lambda mode, c, msg: problems.append(
        "%s:%s: %s" % (c.file, c.line, msg) if c.file else msg))

    # SDDM puts the theme's root Item inside a window of its own, so that is
    # what is built here: the same file, the same size, nothing else.
    #
    # The wrapper goes in a directory of its OWN. Written next to the theme it
    # imports, it becomes part of that directory's implicit module, so the
    # module imports a file that imports the module, and the engine sits there
    # forever without a word.
    import tempfile
    scratch = tempfile.mkdtemp(prefix="genesi-sddm-shot-")
    wrap = os.path.join(scratch, "Shot.qml")
    with io.open(wrap, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("import QtQuick\n"
                 "import \"%s\"\n"
                 "Window {\n"
                 "    width: 1280\n"
                 "    height: 800\n"
                 "    visible: true\n"
                 "    color: \"black\"\n"
                 "    Main { anchors.fill: parent }\n"
                 "}\n" % QUrl.fromLocalFile(theme).toString())
    try:
        engine.load(QUrl.fromLocalFile(wrap))
        roots = engine.rootObjects()
        if not roots:
            print("the greeter did not load:")
            for problem in problems[:10]:
                print("   ", problem)
            return 1
        window = roots[0]

        def shoot():
            window.grabWindow().save(out)
            for problem in problems[:8]:
                print("warning:", problem)
            print("wrote %s" % out)
            app.quit()

        # A moment, so fonts load and whatever animates has settled.
        QTimer.singleShot(1500, shoot)
        app.exec()
        return 0
    finally:
        import shutil
        shutil.rmtree(scratch, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
