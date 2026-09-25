#!/usr/bin/env python3
"""
Draw the Fastfetch shelf's picture cards as the terminal will show them.

A card that says "an emblem and three sections" is a card nobody picks. This
draws each theme the way foot prints it: the emblem from fetch-art/, the name
line, the tagline, the three sections under their rules, keys in the theme's
colour and the palette dots -- from fetch_themes, the same table the config
is written from. Run by hand after changing a theme; the build only reads
the pictures it leaves in catalog/thumbs/fetch-*.jpg.

    python fetch-previews.py

JetBrains Mono (SIL Open Font Licence) is fetched once into a cache outside
the repository, for the same reason plugin-previews.py fetches its fonts.
"""
import os
import sys
import tempfile
import urllib.request

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtCore import QPointF, QRectF, Qt  # noqa: E402
from PySide6.QtGui import (QColor, QFont, QFontDatabase, QFontMetricsF,  # noqa: E402
                           QGuiApplication, QImage, QPainter, QPainterPath,
                           QPen, QRadialGradient)

import fetch_themes as ft  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, "fetch-art")
OUT = os.path.join(HERE, "catalog", "thumbs")
CACHE = os.path.join(tempfile.gettempdir(), "genesi-store-build-cache", "fonts")
MONO_URL = ("https://github.com/google/fonts/raw/main/ofl/jetbrainsmono/"
            "JetBrainsMono%5Bwght%5D.ttf")

W, H = 1280, 720
# A terminal palette for the dots row: what `colors` prints is the
# terminal's own sixteen, not the theme's, so the picture uses a neutral set.
DOTS = ["#3b3b3b", "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd",
        "#56b6c2", "#dcdfe4"]

app = QGuiApplication(sys.argv)


def mono_family():
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, "JetBrainsMono.ttf")
    if not os.path.exists(path):
        print("fetching", MONO_URL)
        urllib.request.urlretrieve(MONO_URL, path)
    return QFontDatabase.applicationFontFamilies(QFontDatabase.addApplicationFont(path))[0]


MONO = mono_family()


def rgb(t, a=255):
    return QColor(t[0], t[1], t[2], a)


def draw(theme):
    ident, _, _, _, art, key, rule, tagline = theme
    img = QImage(W, H, QImage.Format_RGB32)
    p = QPainter(img)
    p.setRenderHint(QPainter.Antialiasing)
    p.setRenderHint(QPainter.TextAntialiasing)
    p.setRenderHint(QPainter.SmoothPixmapTransform)

    # A desktop behind the window: the theme's own colour, very dark.
    p.fillRect(0, 0, W, H, QColor(12, 12, 14))
    glow = QRadialGradient(QPointF(W * 0.2, H * 0.25), W * 0.55)
    glow.setColorAt(0, QColor(key[0], key[1], key[2], 70))
    glow.setColorAt(1, QColor(key[0], key[1], key[2], 0))
    p.fillRect(0, 0, W, H, glow)

    # The terminal window.
    win = QRectF(56, 44, W - 112, H - 88)
    path = QPainterPath()
    path.addRoundedRect(win, 18, 18)
    p.fillPath(path, QColor(22, 22, 25))
    p.setBrush(Qt.NoBrush)
    p.setPen(QPen(QColor(255, 255, 255, 22), 1.5))
    p.drawPath(path)

    # The emblem, where fastfetch puts the logo.
    pic = QImage(os.path.join(ART, art + ".png"))
    side = 330
    p.drawImage(QRectF(win.x() + 44, win.y() + 70, side, side), pic)

    font = QFont(MONO)
    font.setPixelSize(19)
    bold = QFont(font)
    bold.setWeight(QFont.Bold)
    fm = QFontMetricsF(font)
    line_h = 24.5
    x0 = win.x() + 44 + side + 50
    key_w = fm.horizontalAdvance("M" * 8) + fm.horizontalAdvance("  ")
    y = win.y() + 44
    value_ink = QColor(214, 214, 220)
    dim = QColor(150, 150, 158)

    for kind, text in ft.SAMPLE:
        if kind == "break":
            y += line_h * 0.55
            continue
        base = y + fm.ascent()
        if kind == "title":
            p.setFont(bold)
            p.setPen(rgb(key))
            p.drawText(QPointF(x0, base), text)
        elif kind == "tagline":
            p.setFont(font)
            p.setPen(rgb(key))
            p.drawText(QPointF(x0, base), "■")
            p.setPen(dim)
            p.drawText(QPointF(x0 + fm.horizontalAdvance("■ "), base), "GENESI · " + tagline)
        elif kind == "rule":
            p.setFont(bold)
            p.setPen(rgb(key))
            head = "── %s " % text
            p.drawText(QPointF(x0, base), head)
            p.setFont(font)
            p.setPen(rgb(rule))
            p.drawText(QPointF(x0 + QFontMetricsF(bold).horizontalAdvance(head), base),
                       "─" * (30 - len(text)))
        elif kind == "colors":
            for i, c in enumerate(DOTS):
                p.setPen(Qt.NoPen)
                p.setBrush(QColor(c))
                p.drawEllipse(QPointF(x0 + 9 + i * 28, y + line_h / 2), 8, 8)
        else:
            # `kind` is the key here and `text` what it reads.
            p.setFont(bold)
            p.setPen(rgb(key))
            p.drawText(QPointF(x0, base), kind)
            p.setFont(font)
            p.setPen(value_ink)
            p.drawText(QPointF(x0 + key_w, base), text)
        y += line_h

    # The prompt waiting under it.
    p.setFont(font)
    p.setPen(rgb(key))
    p.drawText(QPointF(win.x() + 44, win.bottom() - 34), "❯")
    p.setPen(QColor(214, 214, 220, 180))
    p.fillRect(QRectF(win.x() + 44 + fm.horizontalAdvance("❯ "), win.bottom() - 52, 10, 22),
               QColor(214, 214, 220, 200))
    p.end()
    os.makedirs(OUT, exist_ok=True)
    out = os.path.join(OUT, "fetch-%s.jpg" % ident)
    img.save(out, "JPG", 90)
    print("wrote", out)


if __name__ == "__main__":
    for theme in ft.THEMES:
        draw(theme)
