#!/usr/bin/env python3
"""
The README's banner, from the project's own wallpaper and leaf.

    python docs/assets/make-banner.py      -> docs/assets/banner.png

Rubik (SIL Open Font Licence) is fetched once into a cache outside the
repository, the same cache the store's preview scripts use.
"""
import os
import sys
import tempfile
import urllib.request

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtCore import QPointF, QRectF, Qt  # noqa: E402
from PySide6.QtGui import (QColor, QFont, QFontDatabase, QGuiApplication,  # noqa: E402
                           QImage, QLinearGradient, QPainter)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
CACHE = os.path.join(tempfile.gettempdir(), "genesi-store-build-cache", "fonts")
RUBIK = "https://github.com/google/fonts/raw/main/ofl/rubik/Rubik%5Bwght%5D.ttf"
W, H = 1600, 520

app = QGuiApplication(sys.argv)
os.makedirs(CACHE, exist_ok=True)
path = os.path.join(CACHE, "Rubik.ttf")
if not os.path.exists(path):
    urllib.request.urlretrieve(RUBIK, path)
SANS = QFontDatabase.applicationFontFamilies(QFontDatabase.addApplicationFont(path))[0]

img = QImage(W, H, QImage.Format_ARGB32_Premultiplied)
img.fill(Qt.transparent)
p = QPainter(img)
p.setRenderHint(QPainter.Antialiasing)
p.setRenderHint(QPainter.SmoothPixmapTransform)
p.setRenderHint(QPainter.TextAntialiasing)

# The wallpaper, cropped to the band, with rounded corners.
wall = QImage(os.path.join(ROOT, "wallpapers", "wallpaper.png"))
wall = wall.scaledToWidth(W, Qt.SmoothTransformation)
crop = wall.copy(0, (wall.height() - H) // 2 + 40, W, H)
p.setBrush(Qt.NoBrush)
clip = QRectF(0, 0, W, H)
from PySide6.QtGui import QPainterPath  # noqa: E402
rounded = QPainterPath()
rounded.addRoundedRect(clip, 28, 28)
p.setClipPath(rounded)
p.drawImage(0, 0, crop)
# Dark on the left, where the words go.
shade = QLinearGradient(0, 0, W, 0)
shade.setColorAt(0, QColor(2, 8, 14, 235))
shade.setColorAt(0.55, QColor(2, 8, 14, 150))
shade.setColorAt(1, QColor(2, 8, 14, 0))
p.fillRect(0, 0, W, H, shade)

leaf = QImage(os.path.join(ROOT, "wallpapers", "logo", "GenesiOSLogoNoBg.png"))
p.drawImage(QRectF(40, 60, 400, 400), leaf)

p.setPen(QColor("#e9f7f0"))
f = QFont(SANS)
f.setPixelSize(112)
f.setWeight(QFont.Bold)
p.setFont(f)
p.drawText(QPointF(430, 250), "Genesi OS")

f.setPixelSize(34)
f.setWeight(QFont.Normal)
p.setFont(f)
p.setPen(QColor("#9fe3c2"))
p.drawText(QPointF(436, 318), "An Arch-based desktop that is yours from the first boot.")

f.setPixelSize(24)
p.setFont(f)
p.setPen(QColor(233, 247, 240, 170))
p.drawText(QPointF(436, 372), "KDE Plasma  ·  Hyprland + caelestia  ·  local AI, tuned for it")
p.end()

out = os.path.join(HERE, "banner.png")
img.save(out)
print("wrote", out)
