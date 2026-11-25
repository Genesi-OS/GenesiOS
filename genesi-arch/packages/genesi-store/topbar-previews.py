#!/usr/bin/env python3
"""
Draw the Bars shelf's top-bar looks, one picture per look in topbar_looks.

The bar itself only runs inside caelestia, so this draws it: the same forms
(the frame is caelestia's border grown to hold the bar, the islands float,
the notch hangs from the edge), the same pieces in the places each look puts
them, in Genesi's own dark scheme, over a desktop with a terminal on it.

    python topbar-previews.py      -> catalog/thumbs/topbar-<id>.jpg

Rubik and Material Symbols Rounded are the fonts the shell draws with; they
come from the same cache plugin-previews.py fills.
"""
import math
import os
import sys
import tempfile
import urllib.request

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtCore import QPointF, QRectF, Qt  # noqa: E402
from PySide6.QtGui import (QColor, QFont, QFontDatabase, QFontMetricsF,  # noqa: E402
                           QGuiApplication, QImage, QLinearGradient, QPainter,
                           QPainterPath, QPen, QRadialGradient)

import topbar_looks  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "catalog", "thumbs")
CACHE = os.path.join(tempfile.gettempdir(), "genesi-store-build-cache", "fonts")
FONTS = {
    "Rubik.ttf": "https://github.com/google/fonts/raw/main/ofl/rubik/Rubik%5Bwght%5D.ttf",
    "MaterialSymbolsRounded.ttf": "https://github.com/google/material-design-icons/raw/master/"
                                  "variablefont/MaterialSymbolsRounded%5BFILL,GRAD,opsz,wght%5D.ttf",
}
# Drawn on a 1920x1080 desk -- the screen the bar is laid out for -- and
# scaled to the thumbnail, so the picture shows the spacing a real screen has.
W, H = 1920, 1080
THUMB_W, THUMB_H = 1280, 720

# Genesi's own dark scheme.
SURFACE = QColor("#121614")
CONTAINER = QColor("#1d2320")
ON = QColor("#e2e6e1")
ON_VAR = QColor("#bcc6be")
OUTLINE = QColor("#87918a")
ACCENTS = {"primary": QColor("#8fd6ab"), "secondary": QColor("#b5ccb9"),
           "tertiary": QColor("#a4cddf")}
INK = QColor("#0c2418")

app = QGuiApplication(sys.argv)
os.makedirs(CACHE, exist_ok=True)
fam = {}
for name, url in FONTS.items():
    path = os.path.join(CACHE, name)
    if not os.path.exists(path):
        print("fetching", url)
        urllib.request.urlretrieve(url, path)
    fam[name] = QFontDatabase.applicationFontFamilies(QFontDatabase.addApplicationFont(path))[0]
SANS, ICONS = fam["Rubik.ttf"], fam["MaterialSymbolsRounded.ttf"]


def font(size, family=SANS, weight=QFont.Normal):
    f = QFont(family)
    f.setPixelSize(size)
    f.setWeight(weight)
    return f


class Bar:
    """Lays pieces out along a row, the way the bar's Row does."""

    def __init__(self, p, cy, height, accent):
        self.p, self.cy, self.h, self.accent = p, cy, height, accent

    def text(self, x, s, size=15, colour=ON, weight=QFont.Normal, measure=False):
        f = font(size, weight=weight)
        w = QFontMetricsF(f).horizontalAdvance(s)
        if not measure:
            self.p.setFont(f)
            self.p.setPen(colour)
            fm = QFontMetricsF(f)
            self.p.drawText(QPointF(x, self.cy + (fm.ascent() - fm.descent()) / 2), s)
        return w

    def icon(self, x, name, size=20, colour=ON_VAR, measure=False):
        f = font(size, ICONS)
        w = QFontMetricsF(f).horizontalAdvance(name)
        w = min(w, size * 1.1)
        if not measure:
            self.p.setFont(f)
            self.p.setPen(colour)
            self.p.drawText(QRectF(x, self.cy - size, size * 1.1, size * 2), Qt.AlignCenter, name)
        return size * 1.1

    def stacked(self, x, top, bottom, measure=False):
        ft, fb = font(11), font(14)
        w = max(QFontMetricsF(ft).horizontalAdvance(top), QFontMetricsF(fb).horizontalAdvance(bottom))
        if not measure:
            self.p.setFont(ft)
            self.p.setPen(OUTLINE)
            self.p.drawText(QPointF(x, self.cy - 3), top)
            self.p.setFont(fb)
            self.p.setPen(ON)
            self.p.drawText(QPointF(x, self.cy + 13), bottom)
        return w

    def ring(self, x, value, icon, label, measure=False):
        d = self.h * 0.64
        lw = self.text(0, label, 13, measure=True)
        if not measure:
            r = QRectF(x + 2, self.cy - d / 2, d - 4, d - 4)
            r.moveTop(self.cy - (d - 4) / 2)
            self.p.setBrush(Qt.NoBrush)
            self.p.setPen(QPen(QColor(255, 255, 255, 30), 3))
            self.p.drawEllipse(r)
            self.p.setPen(QPen(self.accent, 3, Qt.SolidLine, Qt.RoundCap))
            self.p.drawArc(r, 90 * 16, int(-value * 360 * 16))
            self.icon(x + d / 2 - 7, icon, 13)
            self.text(x + d + 4, label, 13, ON)
        return d + 4 + lw

    def numbers(self, x, count, active, occupied, measure=False):
        d = self.h * 0.64
        if not measure:
            for i in range(count):
                n = i + 1
                cx = x + i * d
                if n == active:
                    self.p.setPen(Qt.NoPen)
                    self.p.setBrush(self.accent)
                    self.p.drawEllipse(QRectF(cx + 1, self.cy - d / 2 + 1, d - 2, d - 2))
                colour = INK if n == active else (ON if n in occupied else QColor(135, 145, 138, 170))
                f = font(13, weight=QFont.Medium)
                self.p.setFont(f)
                self.p.setPen(colour)
                self.p.drawText(QRectF(cx, self.cy - d / 2, d, d), Qt.AlignCenter, str(n))
        return d * count

    def dots(self, x, count, active, measure=False):
        w = 0
        for i in range(count):
            dw = self.h * (0.62 if i + 1 == active else 0.26)
            if not measure:
                self.p.setPen(Qt.NoPen)
                self.p.setBrush(self.accent if i + 1 == active else (ON_VAR if i < 3 else QColor(135, 145, 138, 115)))
                self.p.drawRoundedRect(QRectF(x + w, self.cy - self.h * 0.13, dw, self.h * 0.26), 5, 5)
            w += dw + 8
        return w - 8

    def pill(self, x, label, measure=False):
        f = font(12, weight=QFont.DemiBold)
        w = max(self.h * 0.84, QFontMetricsF(f).horizontalAdvance(label) + 16)
        if not measure:
            ph = self.h * 0.56
            self.p.setPen(Qt.NoPen)
            self.p.setBrush(ON_VAR)
            self.p.drawRoundedRect(QRectF(x, self.cy - ph / 2, w, ph), ph / 2, ph / 2)
            self.p.setFont(f)
            self.p.setPen(SURFACE)
            self.p.drawText(QRectF(x, self.cy - ph / 2, w, ph), Qt.AlignCenter, label)
        return w

    def dot(self, x, measure=False):
        if not measure:
            self.p.setPen(Qt.NoPen)
            self.p.setBrush(self.accent)
            self.p.drawEllipse(QPointF(x + 2, self.cy), 2, 2)
        return 4

    def row(self, x, pieces, gap=14, measure=False):
        """Draw `pieces` (callables taking x and measure) from x; return width."""
        w = 0
        for i, piece in enumerate(pieces):
            if i:
                w += gap
            w += piece(x + w, measure)
        return w


def desktop(p, accent):
    g = QLinearGradient(0, 0, W, H)
    g.setColorAt(0, QColor("#0e1a17"))
    g.setColorAt(1, QColor("#1b1426"))
    p.fillRect(0, 0, W, H, g)
    for cx, cy, r, c, a in ((W * 0.2, H * 0.7, 420, accent, 60), (W * 0.85, H * 0.3, 380, QColor("#7a5cff"), 50)):
        rg = QRadialGradient(QPointF(cx, cy), r)
        cc = QColor(c)
        cc.setAlpha(a)
        rg.setColorAt(0, cc)
        cc2 = QColor(c)
        cc2.setAlpha(0)
        rg.setColorAt(1, cc2)
        p.fillRect(0, 0, W, H, rg)


def terminal(p, rect):
    path = QPainterPath()
    path.addRoundedRect(rect, 14, 14)
    p.fillPath(path, QColor(16, 18, 17, 235))
    p.setPen(QPen(QColor(255, 255, 255, 18), 1))
    p.setBrush(Qt.NoBrush)
    p.drawPath(path)
    f = font(15, "Consolas")
    p.setFont(f)
    y = rect.y() + 36
    for colour, line in ((ACCENTS["primary"], "genesi@genesi ~ ❯ fastfetch"),
                         (ON_VAR, ""), (ON_VAR, "  Genesi OS x86_64 · Hyprland · fish"),
                         (ON_VAR, ""), (ACCENTS["primary"], "genesi@genesi ~ ❯ ")):
        p.setPen(colour)
        p.drawText(QPointF(rect.x() + 24, y), line)
        y += 24


def pieces_for(bar, look, place):
    """The bar's pieces in one group, in the order GenesiTopBar has them."""
    s = look
    acc = bar.accent
    out = []
    if place == "left":
        out.append(lambda x, m: bar.icon(x, "eco", 22, acc, m))
        if s.get("topbar.showSidebarButton") == "true":
            out.append(lambda x, m: bar.icon(x, "search", 20, ON_VAR, m))
        if s.get("topbar.windowPlace") == "left":
            out.append(lambda x, m: bar.stacked(x, "foot", "~ - fish", m))
        if s.get("topbar.resourcePlace") == "left":
            out += [lambda x, m: bar.ring(x, 0.5, "memory", "50%", m),
                    lambda x, m: bar.ring(x, 0.27, "memory_alt", "27%", m)]
        if s.get("topbar.showMedia") == "true" and s.get("topbar.mediaPlace") == "left":
            out.append(lambda x, m: bar.icon(x, "graphic_eq", 18, acc, m)
                       + 6 + bar.text(x + 26, "snowfall • Øneheart", 14, ON_VAR, measure=m))
        if s.get("topbar.workspaceStyle") == "numbers":
            n = int(s.get("topbar.workspaceCount", "5"))
            out.append(lambda x, m: bar.numbers(x, n, 2, {1, 2, 4}, m))
        else:
            out.append(lambda x, m: bar.dots(x, 5, 2, m))
    elif place == "centre":
        if s.get("topbar.windowPlace", "centre") == "centre":
            out.append(lambda x, m: bar.text(x, "GitHub — Firefox", 14, ON_VAR, measure=m))
        if s.get("topbar.showMedia") == "true" and s.get("topbar.mediaPlace") == "centre":
            out.append(lambda x, m: bar.icon(x, "graphic_eq", 18, acc, m)
                       + 6 + bar.text(x + 26, "snowfall • Øneheart", 14, ON_VAR, measure=m))
        date = {"numbers": "Thu, 13/08", "long": "Thursday, 13 August"}.get(s.get("topbar.dateStyle"), "Thu, Aug 13")
        out += [lambda x, m: bar.text(x, "20:04", 16, ON, QFont.Medium, m),
                lambda x, m: bar.dot(x, m),
                lambda x, m: bar.text(x, date, 14, ON_VAR, measure=m)]
    else:
        if s.get("topbar.resourcePlace", "right") == "right":
            if s.get("topbar.resourceStyle") == "rings":
                out += [lambda x, m: bar.ring(x, 0.23, "memory", "23%", m),
                        lambda x, m: bar.ring(x, 0.41, "memory_alt", "41%", m)]
            else:
                out += [lambda x, m: bar.icon(x, "memory", 18, ON_VAR, m) + 4 + bar.text(x + 24, "23%", 13, measure=m),
                        lambda x, m: bar.icon(x, "memory_alt", 18, ON_VAR, m) + 4 + bar.text(x + 24, "41%", 13, measure=m)]
        if s.get("topbar.showBrightness") == "true":
            out.append(lambda x, m: bar.icon(x, "brightness_6", 18, ON_VAR, m) + 4 + bar.text(x + 24, "60%", 13, measure=m))
        if s.get("topbar.showVolume") == "true":
            out.append(lambda x, m: bar.icon(x, "volume_up", 18, ON_VAR, m) + 4 + bar.text(x + 24, "45%", 13, measure=m))
        out.append(lambda x, m: bar.icon(x, "wifi", 18, ON_VAR, m))
        if s.get("topbar.showBluetooth") == "true":
            out.append(lambda x, m: bar.icon(x, "bluetooth", 18, ON_VAR, m))
        if s.get("topbar.batteryStyle") == "pill":
            out.append(lambda x, m: bar.pill(x, "60", m))
        else:
            out.append(lambda x, m: bar.icon(x, "battery_full", 18, ON_VAR, m) + 4 + bar.text(x + 24, "60%", 13, measure=m))
        out += [lambda x, m: bar.icon(x, "power_settings_new", 18, ON_VAR, m),
                lambda x, m: bar.icon(x, "tune", 18, ON_VAR, m)]
    return out


def draw(look):
    ident, _, _, _, s = look
    accent = ACCENTS[s.get("topbar.accent", "primary")]
    form = s["topbar.form"]
    img = QImage(W, H, QImage.Format_RGB32)
    p = QPainter(img)
    p.setRenderHint(QPainter.Antialiasing)
    p.setRenderHint(QPainter.TextAntialiasing)
    desktop(p, accent)

    height = int(s.get("topbar.height", "36")) + 6
    side = 12
    if form == "frame":
        band = height
        frame = QPainterPath()
        frame.addRect(QRectF(0, 0, W, H))
        hole = QPainterPath()
        hole.addRoundedRect(QRectF(side, band, W - side * 2, H - band - side), 22, 22)
        terminal(p, QRectF(side + 40, band + 40, W * 0.5, H * 0.46))
        # The border's shadow into the screen, then the border itself.
        p.fillPath(frame.subtracted(hole), QColor(18, 22, 20, 245))
        cy = band / 2
        margin = side + 16
    else:
        terminal(p, QRectF(60, 110, W * 0.5, H * 0.46))
        cy = 10 + height / 2
        margin = 20

    bar = Bar(p, cy, height - 6, accent)
    groups = {g: pieces_for(bar, s, g) for g in ("left", "centre", "right")}
    widths = {g: bar.row(0, groups[g], measure=True) for g in groups}
    xs = {"left": margin, "centre": (W - widths["centre"]) / 2, "right": W - margin - widths["right"]}

    pad = 18
    if form == "islands":
        for g in groups:
            r = QRectF(xs[g] - pad, cy - (height - 6) / 2, widths[g] + pad * 2, height - 6)
            path = QPainterPath()
            path.addRoundedRect(r, r.height() / 2.4, r.height() / 2.4)
            p.fillPath(path.translated(0, 3), QColor(0, 0, 0, 70))
            p.fillPath(path, QColor(29, 35, 32, 235))
        # The flow between them.
        p.setPen(QPen(QColor(135, 145, 138, 120), 2))
        for a, b in (("left", "centre"), ("centre", "right")):
            x0, x1 = xs[a] + widths[a] + pad + 10, xs[b] - pad - 10
            p.drawLine(QPointF(x0, cy), QPointF(x1, cy))
            p.setPen(Qt.NoPen)
            p.setBrush(accent)
            p.drawEllipse(QPointF(x0 + (x1 - x0) * 0.4, cy), 3, 3)
            p.setPen(QPen(QColor(135, 145, 138, 120), 2))
    elif form == "notch":
        r = QRectF(xs["centre"] - pad * 1.5, 0, widths["centre"] + pad * 3, cy + (height - 6) / 2 + 4)
        path = QPainterPath()
        path.moveTo(r.left() - 16, 0)
        path.quadTo(r.left(), 0, r.left(), 16)
        path.lineTo(r.left(), r.bottom() - 16)
        path.quadTo(r.left(), r.bottom(), r.left() + 16, r.bottom())
        path.lineTo(r.right() - 16, r.bottom())
        path.quadTo(r.right(), r.bottom(), r.right(), r.bottom() - 16)
        path.lineTo(r.right(), 16)
        path.quadTo(r.right(), 0, r.right() + 16, 0)
        path.closeSubpath()
        p.fillPath(path, QColor(29, 35, 32, 245))

    for g in groups:
        bar.row(xs[g], groups[g])
    p.end()
    os.makedirs(OUT, exist_ok=True)
    out = os.path.join(OUT, "topbar-%s.jpg" % ident)
    img.scaled(THUMB_W, THUMB_H, Qt.IgnoreAspectRatio, Qt.SmoothTransformation).save(out, "JPG", 90)
    print("wrote", out)


if __name__ == "__main__":
    for look in topbar_looks.LOOKS:
        draw(look)
