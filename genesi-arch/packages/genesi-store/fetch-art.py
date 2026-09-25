#!/usr/bin/env python3
"""
Draw the pictures the Fastfetch shelf puts where the ASCII logo goes.

The first image cards on that shelf were wallpapers -- a landscape photograph
squeezed into thirty terminal columns, which is a smudge. A picture beside a
fetch is an EMBLEM: square, one subject, a transparent background so the
terminal's own colour shows around it, and a palette the keys of the fetch
can be coloured to match. Nothing like that exists under a licence Genesi can
ship, so these are drawn here, in code, and the PNGs this writes are
committed beside it:

    python fetch-art.py            -> fetch-art/<name>.png

Each is original work for Genesi. Change one here and run it again; the
build only reads the PNGs.
"""
import math
import os
import random
import sys
import tempfile
import urllib.request

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtCore import QPointF, QRectF, Qt  # noqa: E402
from PySide6.QtGui import (QBrush, QColor, QFont, QFontDatabase, QGuiApplication,  # noqa: E402
                           QImage, QLinearGradient, QPainter, QPainterPath,
                           QPen, QRadialGradient)

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "fetch-art")
S = 640          # every picture is square
C = S / 2        # its centre
R = 284          # the disc the scene is drawn in

app = QGuiApplication(sys.argv)

# The seal's character is set in Yuji Syuku, a brush face under the SIL Open
# Font Licence, fetched once into a cache outside the repository -- a font
# only one machine happens to have is a picture nobody else can redraw.
BRUSH_URL = "https://github.com/google/fonts/raw/main/ofl/yujisyuku/YujiSyuku-Regular.ttf"
_cache = os.path.join(tempfile.gettempdir(), "genesi-store-build-cache", "fonts")
os.makedirs(_cache, exist_ok=True)
_brush = os.path.join(_cache, "YujiSyuku-Regular.ttf")
if not os.path.exists(_brush):
    print("fetching", BRUSH_URL)
    urllib.request.urlretrieve(BRUSH_URL, _brush)
BRUSH = QFontDatabase.applicationFontFamilies(QFontDatabase.addApplicationFont(_brush))[0]


def canvas():
    img = QImage(S, S, QImage.Format_ARGB32_Premultiplied)
    img.fill(Qt.transparent)
    p = QPainter(img)
    p.setRenderHint(QPainter.Antialiasing)
    p.setRenderHint(QPainter.SmoothPixmapTransform)
    return img, p


def disc(r=R):
    path = QPainterPath()
    path.addEllipse(QPointF(C, C), r, r)
    return path


def col(hexa, alpha=255):
    c = QColor(hexa)
    c.setAlpha(alpha)
    return c


def vgrad(y0, y1, *stops):
    g = QLinearGradient(0, y0, 0, y1)
    for at, c in stops:
        g.setColorAt(at, QColor(c))
    return QBrush(g)


def ridge(points, base=S):
    """A filled silhouette through `points`, closed along the bottom."""
    path = QPainterPath(QPointF(points[0][0], base))
    for x, y in points:
        path.lineTo(x, y)
    path.lineTo(points[-1][0], base)
    path.closeSubpath()
    return path


def mountain_line(rng, x0, x1, base_y, height, steps, jag):
    pts = []
    for i in range(steps + 1):
        x = x0 + (x1 - x0) * i / steps
        peak = math.sin(i / steps * math.pi * rng.uniform(1.2, 2.2))
        y = base_y - height * (0.35 + 0.65 * abs(peak)) + rng.uniform(-jag, jag)
        pts.append((x, y))
    return pts


def ring(p, color, width, r=R + 10):
    p.setBrush(Qt.NoBrush)
    p.setPen(QPen(color, width))
    p.drawEllipse(QPointF(C, C), r, r)


def brush_ring(p, rng, color, r=R + 14, width=22):
    """An ink circle, painted rather than drawn: many thin arcs, each a little
    off, with a gap where the brush lifted."""
    p.setBrush(Qt.NoBrush)
    start = rng.uniform(0, 360)
    for i in range(38):
        w = width * rng.uniform(0.15, 0.55)
        c = QColor(color)
        c.setAlpha(int(255 * rng.uniform(0.35, 0.9)))
        p.setPen(QPen(c, w, Qt.SolidLine, Qt.RoundCap))
        rr = r + rng.uniform(-width / 2.4, width / 2.4)
        span = rng.uniform(250, 318)
        rect = QRectF(C - rr, C - rr, rr * 2, rr * 2)
        p.drawArc(rect, int((start + rng.uniform(-8, 8)) * 16), int(span * 16))


def save(img, name):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".png")
    img.save(path)
    print("wrote", path)


# ── 創 · Sol nascente ────────────────────────────────────────────────────────
def sol():
    rng = random.Random(7)
    img, p = canvas()
    p.save()
    p.setClipPath(disc())
    p.fillRect(0, 0, S, S, vgrad(0, S, (0, "#15110f"), (1, "#0b0908")))
    # The sun: big, low and off-centre.
    sun = QRadialGradient(QPointF(C + 70, C - 40), 190)
    sun.setColorAt(0, QColor("#ff5a4a"))
    sun.setColorAt(0.85, QColor("#e0443e"))
    sun.setColorAt(1, QColor("#b92f2c"))
    p.setPen(Qt.NoPen)
    p.setBrush(QBrush(sun))
    p.drawEllipse(QPointF(C + 70, C - 40), 168, 168)
    # Mist bands across the sun.
    for i, y in enumerate((C - 30, C + 6, C + 40)):
        p.setBrush(col("#15110f", 235))
        p.drawRoundedRect(QRectF(C - 60 + i * 24, y, 320, 9 - i * 2), 4, 4)
    # Far and near hills.
    p.setBrush(col("#2a211d"))
    p.drawPath(ridge(mountain_line(rng, 0, S, C + 150, 120, 9, 12)))
    p.setBrush(col("#1b1512"))
    p.drawPath(ridge(mountain_line(rng, 0, S, C + 220, 90, 7, 10)))
    # The torii, bone white, standing on the near hill.
    bone = col("#efe6d8")
    p.setBrush(bone)
    x0 = C - 170
    p.drawRect(QRectF(x0 + 38, C - 70, 22, 300))                 # left post
    p.drawRect(QRectF(x0 + 158, C - 70, 22, 300))                # right post
    top = QPainterPath()                                          # kasagi
    top.moveTo(x0 - 18, C - 112)
    top.quadTo(x0 + 109, C - 92, x0 + 236, C - 112)
    top.lineTo(x0 + 226, C - 92)
    top.quadTo(x0 + 109, C - 76, x0 + 8, C - 92)
    top.closeSubpath()
    p.drawPath(top)
    p.drawRect(QRectF(x0 + 10, C - 64, 198, 16))                 # nuki
    p.drawRect(QRectF(x0 + 100, C - 92, 18, 30))                 # gakuzuka
    # Birds.
    p.setPen(QPen(col("#efe6d8", 210), 3, Qt.SolidLine, Qt.RoundCap))
    p.setBrush(Qt.NoBrush)
    for bx, by, s in ((C + 120, C - 170, 1.0), (C + 160, C - 150, 0.7), (C + 92, C - 140, 0.6)):
        bird = QPainterPath(QPointF(bx - 14 * s, by))
        bird.quadTo(bx - 6 * s, by - 8 * s, bx, by)
        bird.quadTo(bx + 6 * s, by - 8 * s, bx + 14 * s, by)
        p.drawPath(bird)
    p.restore()
    brush_ring(p, rng, "#efe6d8")
    # The seal: 創, "to create" -- the first character of genesis.
    p.setPen(Qt.NoPen)
    p.setBrush(col("#e0443e"))
    seal = QRectF(C + 150, C + 150, 92, 92)
    p.drawRoundedRect(seal, 10, 10)
    f = QFont(BRUSH)
    f.setPixelSize(72)
    p.setFont(f)
    p.setPen(col("#f7efe3"))
    p.drawText(seal, Qt.AlignCenter, "創")
    p.end()
    save(img, "sol")


# ── Folha · the Genesi leaf ──────────────────────────────────────────────────
def folha():
    rng = random.Random(3)
    img, p = canvas()
    p.save()
    p.setClipPath(disc())
    glow = QRadialGradient(QPointF(C, C), R)
    glow.setColorAt(0, QColor("#16402f"))
    glow.setColorAt(0.6, QColor("#0d2119"))
    glow.setColorAt(1, QColor("#08120e"))
    p.fillRect(0, 0, S, S, QBrush(glow))
    # Stars of pollen.
    p.setPen(Qt.NoPen)
    for _ in range(70):
        a = rng.uniform(0, 1)
        p.setBrush(col("#8fd6ab", int(60 + 160 * a)))
        rr = rng.uniform(1, 3.2) * a + 0.8
        p.drawEllipse(QPointF(rng.uniform(40, S - 40), rng.uniform(40, S - 40)), rr, rr)
    p.restore()
    # An orbit around it, tilted, with a moon on it.
    p.save()
    p.translate(C, C)
    p.rotate(-24)
    p.setBrush(Qt.NoBrush)
    p.setPen(QPen(col("#39d98a", 120), 3))
    p.drawEllipse(QPointF(0, 0), 250, 96)
    p.setPen(Qt.NoPen)
    p.setBrush(col("#c9f5dc"))
    p.drawEllipse(QPointF(236, -34), 11, 11)
    p.restore()
    # The leaf.
    p.save()
    p.translate(C, C + 6)
    p.rotate(-38)
    leaf = QPainterPath(QPointF(0, 190))
    leaf.cubicTo(-150, 110, -140, -120, 0, -200)
    leaf.cubicTo(140, -120, 150, 110, 0, 190)
    g = QLinearGradient(-120, -200, 120, 190)
    g.setColorAt(0, QColor("#7ff0b0"))
    g.setColorAt(0.5, QColor("#2fc07a"))
    g.setColorAt(1, QColor("#127a4c"))
    p.setPen(Qt.NoPen)
    p.setBrush(QBrush(g))
    p.drawPath(leaf)
    # A darker half, for the fold.
    half = QPainterPath(QPointF(0, 190))
    half.cubicTo(150, 110, 140, -120, 0, -200)
    half.lineTo(0, 190)
    p.setBrush(col("#0b3d27", 90))
    p.drawPath(half)
    # Midrib and veins.
    p.setPen(QPen(col("#eafff3", 230), 6, Qt.SolidLine, Qt.RoundCap))
    p.drawLine(QPointF(0, 230), QPointF(0, -170))
    p.setPen(QPen(col("#eafff3", 170), 3.5, Qt.SolidLine, Qt.RoundCap))
    for y, span in ((-110, 58), (-50, 92), (15, 104), (80, 92), (140, 56)):
        for side in (-1, 1):
            v = QPainterPath(QPointF(0, y + 28))
            v.quadTo(side * span * 0.55, y + 16, side * span, y - 16)
            p.drawPath(v)
    p.restore()
    ring(p, col("#39d98a", 200), 5)
    ring(p, col("#39d98a", 70), 2, R + 24)
    p.end()
    save(img, "folha")


# ── Synthwave ────────────────────────────────────────────────────────────────
def synthwave():
    img, p = canvas()
    p.save()
    p.setClipPath(disc())
    horizon = C + 60
    p.fillRect(QRectF(0, 0, S, horizon), vgrad(0, horizon, (0, "#1a0b3b"), (0.6, "#4a1060"), (1, "#b0287a")))
    # The sun, sliced.
    sun = QLinearGradient(0, C - 190, 0, horizon)
    sun.setColorAt(0, QColor("#ffe66d"))
    sun.setColorAt(0.55, QColor("#ff8a4c"))
    sun.setColorAt(1, QColor("#ff2e88"))
    path = QPainterPath()
    path.addEllipse(QPointF(C, horizon - 40), 170, 170)
    cut = QPainterPath()
    for i in range(7):
        y = horizon - 110 + i * 18
        cut.addRect(QRectF(0, y, S, 3 + i * 1.6))
    cut.addRect(QRectF(0, horizon, S, S))
    p.setPen(Qt.NoPen)
    p.setBrush(QBrush(sun))
    p.drawPath(path.subtracted(cut))
    # Mountains with neon edges.
    rng = random.Random(11)
    for shade, edge, h, base in (("#2a0f4a", "#ff5ea8", 150, horizon + 2), ("#170733", "#00e5ff", 90, horizon + 2)):
        pts = mountain_line(rng, -20, S + 20, base, h, 10, 16)
        m = ridge(pts, base)
        p.setPen(Qt.NoPen)
        p.setBrush(col(shade))
        p.drawPath(m)
        p.setBrush(Qt.NoBrush)
        p.setPen(QPen(col(edge, 220), 3))
        line = QPainterPath(QPointF(*pts[0]))
        for pt in pts[1:]:
            line.lineTo(*pt)
        p.drawPath(line)
    # The floor, and its grid.
    p.fillRect(QRectF(0, horizon, S, S - horizon), vgrad(horizon, S, (0, "#12052a"), (1, "#05010f")))
    p.setPen(QPen(col("#ff2e88", 200), 2))
    for i in range(1, 10):
        t = (i / 9) ** 2.1
        y = horizon + t * (S - horizon)
        p.drawLine(QPointF(0, y), QPointF(S, y))
    p.setPen(QPen(col("#ff2e88", 170), 2))
    for i in range(-12, 13):
        p.drawLine(QPointF(C + i * 12, horizon), QPointF(C + i * 110, S))
    p.setPen(QPen(col("#ffffff", 200), 2))
    p.drawLine(QPointF(0, horizon), QPointF(S, horizon))
    p.restore()
    ring(p, col("#ff5ea8", 230), 6)
    ring(p, col("#00e5ff", 120), 2, R + 24)
    p.end()
    save(img, "synthwave")


# ── Lua · moon over the mountains ────────────────────────────────────────────
def lua():
    rng = random.Random(5)
    img, p = canvas()
    p.save()
    p.setClipPath(disc())
    p.fillRect(0, 0, S, S, vgrad(0, S, (0, "#0a1024"), (0.6, "#16244a"), (1, "#1f3566")))
    p.setPen(Qt.NoPen)
    for _ in range(110):
        a = rng.random()
        p.setBrush(col("#dfe8ff", int(70 + 185 * a)))
        rr = 0.7 + 2.0 * a * a
        p.drawEllipse(QPointF(rng.uniform(0, S), rng.uniform(0, C + 40)), rr, rr)
    # The moon: a halo, then the crescent.
    halo = QRadialGradient(QPointF(C + 60, C - 90), 200)
    halo.setColorAt(0, col("#9fb7ff", 110))
    halo.setColorAt(1, col("#9fb7ff", 0))
    p.setBrush(QBrush(halo))
    p.drawEllipse(QPointF(C + 60, C - 90), 200, 200)
    full = QPainterPath()
    full.addEllipse(QPointF(C + 60, C - 90), 92, 92)
    bite = QPainterPath()
    bite.addEllipse(QPointF(C + 104, C - 122), 86, 86)
    p.setBrush(col("#f1f4ff"))
    p.drawPath(full.subtracted(bite))
    # Three ranges, lighter the further.
    for shade, h, base, steps in (("#34508f", 170, C + 150, 8), ("#22386b", 130, C + 210, 9), ("#141f40", 110, C + 270, 7)):
        p.setBrush(col(shade))
        p.drawPath(ridge(mountain_line(rng, -10, S + 10, base, h, steps, 14)))
    # Pines on the nearest.
    p.setBrush(col("#0b1226"))
    for i in range(14):
        x = 40 + i * 42 + rng.uniform(-10, 10)
        h = rng.uniform(60, 120)
        base = S - 60 + rng.uniform(-10, 10)
        tree = QPainterPath(QPointF(x, base - h))
        tree.lineTo(x + h * 0.22, base)
        tree.lineTo(x - h * 0.22, base)
        tree.closeSubpath()
        p.drawPath(tree)
    p.fillRect(QRectF(0, S - 70, S, 70), col("#0b1226"))
    p.restore()
    ring(p, col("#c9d6ff", 220), 5)
    ring(p, col("#7aa2f7", 90), 2, R + 24)
    p.end()
    save(img, "lua")


# ── Onda · the wave ──────────────────────────────────────────────────────────
def onda():
    rng = random.Random(9)
    img, p = canvas()
    p.save()
    p.setClipPath(disc())
    p.fillRect(0, 0, S, S, vgrad(0, S, (0, "#f1e6cf"), (1, "#e2d2b0")))
    # A small sun, and the mountain far away.
    p.setPen(Qt.NoPen)
    p.setBrush(col("#d9483b"))
    p.drawEllipse(QPointF(C + 150, C - 150), 34, 34)
    fuji = QPainterPath(QPointF(C + 40, C + 60))
    fuji.lineTo(C + 110, C - 20)
    fuji.lineTo(C + 140, C - 20)
    fuji.lineTo(C + 220, C + 60)
    fuji.closeSubpath()
    p.setBrush(col("#3b5a7a"))
    p.drawPath(fuji)
    cap = QPainterPath(QPointF(C + 96, C - 4))
    cap.lineTo(C + 110, C - 20)
    cap.lineTo(C + 140, C - 20)
    cap.lineTo(C + 156, C - 4)
    cap.quadTo(C + 125, C + 6, C + 96, C - 4)
    p.setBrush(col("#f7f1e3"))
    p.drawPath(cap)
    # The great wave: a body rising from the right, curling over to the left.
    body = QPainterPath(QPointF(S, S))
    body.lineTo(S, C + 40)
    body.cubicTo(S - 60, C - 20, C + 60, C - 210, C - 70, C - 170)
    body.cubicTo(C - 190, C - 135, C - 210, C - 20, C - 120, C + 10)
    body.cubicTo(C - 150, C - 60, C - 100, C - 110, C - 40, C - 96)
    body.cubicTo(C + 40, C - 70, C + 30, C + 70, C - 60, C + 120)
    body.cubicTo(C - 160, C + 170, C - 260, C + 150, 0, C + 120)
    body.lineTo(0, S)
    body.closeSubpath()
    g = QLinearGradient(0, C - 200, 0, S)
    g.setColorAt(0, QColor("#2d5f8a"))
    g.setColorAt(1, QColor("#0e2a47"))
    p.setBrush(QBrush(g))
    p.drawPath(body)
    # Bands inside the wave.
    p.setBrush(Qt.NoBrush)
    for i in range(4):
        p.setPen(QPen(col("#8fb8d6", 160 - i * 25), 5 - i * 0.6, Qt.SolidLine, Qt.RoundCap))
        band = QPainterPath(QPointF(S - 30 - i * 30, C + 60 + i * 30))
        band.cubicTo(S - 110 - i * 20, C - 10 + i * 28, C + 60 - i * 20, C - 150 + i * 36, C - 50 + i * 10, C - 130 + i * 30)
        p.drawPath(band)
    # Foam along the crest itself: the rising face, then the lip curling
    # over. Each claw points out from the curve, the way the spray is thrown.
    def bez(p0, p1, p2, p3, t):
        u = 1 - t
        return tuple(u**3 * a + 3 * u * u * t * b + 3 * u * t * t * c + t**3 * d
                     for a, b, c, d in zip(p0, p1, p2, p3))

    face = ((S, C + 40), (S - 60, C - 20), (C + 60, C - 210), (C - 70, C - 170))
    lip = ((C - 70, C - 170), (C - 190, C - 135), (C - 210, C - 20), (C - 120, C + 10))
    samples = [(face, 0.42 + 0.58 * i / 13) for i in range(14)] +               [(lip, 0.03 + 0.55 * i / 9) for i in range(10)]
    p.setPen(Qt.NoPen)
    p.setBrush(col("#f7f1e3"))
    for curve, t in samples:
        x, y = bez(*curve, t)
        x2, y2 = bez(*curve, min(1, t + 0.01))
        dx, dy = x2 - x, y2 - y
        n = math.hypot(dx, dy) or 1
        nx, ny = dy / n, -dx / n          # the outward side of this curve
        size = rng.uniform(11, 19)
        tip = (x + nx * size, y + ny * size)
        claw = QPainterPath(QPointF(x - dx / n * 7, y - dy / n * 7))
        claw.quadTo(QPointF(x + nx * size * 0.5 - dx / n * 12, y + ny * size * 0.5 - dy / n * 12), QPointF(*tip))
        claw.quadTo(QPointF(x + nx * size * 0.35 + dx / n * 4, y + ny * size * 0.35 + dy / n * 4),
                    QPointF(x + dx / n * 8, y + dy / n * 8))
        claw.closeSubpath()
        p.drawPath(claw)
    # Spray thrown off the top.
    for _ in range(34):
        # Only off the lip: spray over the sun reads as a mistake.
        curve, t = rng.choice(samples[9:])
        x, y = bez(*curve, t)
        p.drawEllipse(QPointF(x + rng.uniform(-14, 14), y - rng.uniform(18, 60)), rng.uniform(2, 4.5), rng.uniform(2, 4.5))
    p.restore()
    brush_ring(p, rng, "#1c3a5c")
    p.end()
    save(img, "onda")


# ── Cyber ────────────────────────────────────────────────────────────────────
def cyber():
    rng = random.Random(13)
    img, p = canvas()
    p.save()
    p.setClipPath(disc())
    bg = QRadialGradient(QPointF(C, C), R)
    bg.setColorAt(0, QColor("#0d1f2b"))
    bg.setColorAt(1, QColor("#05090f"))
    p.fillRect(0, 0, S, S, QBrush(bg))
    # A faint grid.
    p.setPen(QPen(col("#00e5ff", 26), 1))
    for i in range(0, S, 24):
        p.drawLine(QPointF(i, 0), QPointF(i, S))
        p.drawLine(QPointF(0, i), QPointF(S, i))
    # Traces running out from the core.
    for k in range(18):
        a = k / 18 * math.tau + rng.uniform(-0.08, 0.08)
        r0, r1 = 120, rng.uniform(200, 280)
        x0, y0 = C + math.cos(a) * r0, C + math.sin(a) * r0
        xm, ym = C + math.cos(a) * (r0 + r1) / 2, C + math.sin(a) * (r0 + r1) / 2
        bend = rng.choice((-1, 1)) * 0.25
        x1, y1 = C + math.cos(a + bend) * r1, C + math.sin(a + bend) * r1
        c = col("#00e5ff" if k % 3 else "#ff4fd8", 200)
        p.setPen(QPen(c, 3, Qt.SolidLine, Qt.RoundCap, Qt.RoundJoin))
        trace = QPainterPath(QPointF(x0, y0))
        trace.lineTo(xm, ym)
        trace.lineTo(x1, y1)
        p.setBrush(Qt.NoBrush)
        p.drawPath(trace)
        p.setPen(Qt.NoPen)
        p.setBrush(c)
        p.drawEllipse(QPointF(x1, y1), 6, 6)
    p.restore()

    def hexagon(r, rot=30):
        path = QPainterPath()
        for i in range(6):
            a = math.radians(60 * i + rot)
            pt = QPointF(C + r * math.cos(a), C + r * math.sin(a))
            path.moveTo(pt) if i == 0 else path.lineTo(pt)
        path.closeSubpath()
        return path

    glow = QRadialGradient(QPointF(C, C), 150)
    glow.setColorAt(0, col("#00e5ff", 110))
    glow.setColorAt(1, col("#00e5ff", 0))
    p.setPen(Qt.NoPen)
    p.setBrush(QBrush(glow))
    p.drawEllipse(QPointF(C, C), 150, 150)
    p.setBrush(col("#07121a"))
    p.drawPath(hexagon(118))
    p.setBrush(Qt.NoBrush)
    for r, c, w in ((118, "#00e5ff", 6), (96, "#ff4fd8", 3), (74, "#00e5ff", 2)):
        p.setPen(QPen(col(c, 230), w, Qt.SolidLine, Qt.RoundCap, Qt.RoundJoin))
        p.drawPath(hexagon(r))
    # The leaf, as a glyph, in the middle.
    p.save()
    p.translate(C, C)
    p.rotate(-38)
    leaf = QPainterPath(QPointF(0, 54))
    leaf.cubicTo(-44, 30, -40, -34, 0, -58)
    leaf.cubicTo(40, -34, 44, 30, 0, 54)
    p.setPen(Qt.NoPen)
    p.setBrush(col("#e6fdff"))
    p.drawPath(leaf)
    p.setPen(QPen(col("#07121a"), 4, Qt.SolidLine, Qt.RoundCap))
    p.drawLine(QPointF(0, 66), QPointF(0, -44))
    p.restore()
    ring(p, col("#00e5ff", 230), 5)
    ring(p, col("#ff4fd8", 110), 2, R + 24)
    p.end()
    save(img, "cyber")


# ── Sakura ───────────────────────────────────────────────────────────────────
def sakura():
    rng = random.Random(21)
    img, p = canvas()
    p.save()
    p.setClipPath(disc())
    p.fillRect(0, 0, S, S, vgrad(0, S, (0, "#2b1a2e"), (1, "#140c17")))
    # A pale moon behind.
    p.setPen(Qt.NoPen)
    moon = QRadialGradient(QPointF(C + 40, C - 30), 200)
    moon.setColorAt(0, QColor("#ffe9f0"))
    moon.setColorAt(0.9, QColor("#f6c6d6"))
    moon.setColorAt(1, QColor("#e9a9bf"))
    p.setBrush(QBrush(moon))
    p.drawEllipse(QPointF(C + 40, C - 30), 190, 190)

    # The branch, from the lower left.
    def branch(x0, y0, x1, y1, w):
        path = QPainterPath(QPointF(x0, y0))
        path.cubicTo(x0 + (x1 - x0) * 0.3, y0 - 40, x0 + (x1 - x0) * 0.7, y1 + 30, x1, y1)
        p.setPen(QPen(col("#1a0f14"), w, Qt.SolidLine, Qt.RoundCap))
        p.setBrush(Qt.NoBrush)
        p.drawPath(path)

    branch(-20, S - 90, C + 60, C - 10, 26)
    branch(C - 80, C + 90, C + 220, C + 40, 14)
    branch(C - 10, C + 40, C - 40, C - 150, 12)
    branch(C + 60, C - 10, C + 240, C - 120, 10)

    def blossom(x, y, r, rot):
        p.save()
        p.translate(x, y)
        p.rotate(rot)
        p.setPen(Qt.NoPen)
        for i in range(5):
            p.save()
            p.rotate(72 * i)
            petal = QPainterPath(QPointF(0, 0))
            petal.cubicTo(-r * 0.7, -r * 0.5, -r * 0.55, -r * 1.25, -r * 0.12, -r * 1.2)
            petal.lineTo(0, -r * 1.02)
            petal.lineTo(r * 0.12, -r * 1.2)
            petal.cubicTo(r * 0.55, -r * 1.25, r * 0.7, -r * 0.5, 0, 0)
            g = QRadialGradient(QPointF(0, 0), r * 1.2)
            g.setColorAt(0, QColor("#ff5c8f"))
            g.setColorAt(1, QColor("#ffc2d6"))
            p.setBrush(QBrush(g))
            p.drawPath(petal)
            p.restore()
        p.setBrush(col("#fff1a8"))
        p.drawEllipse(QPointF(0, 0), r * 0.18, r * 0.18)
        p.restore()

    for x, y, r in ((C + 60, C - 10, 30), (C - 40, C + 70, 26), (C + 130, C + 20, 24), (C - 30, C - 120, 22),
                    (C + 200, C - 100, 22), (C + 20, C - 70, 18), (C + 190, C + 44, 20), (C - 120, C + 120, 22),
                    (C + 100, C - 60, 16), (C - 60, C - 40, 16)):
        blossom(x, y, r, rng.uniform(0, 72))
    # Falling petals.
    p.setPen(Qt.NoPen)
    for _ in range(18):
        x, y = rng.uniform(40, S - 40), rng.uniform(C, S - 40)
        p.save()
        p.translate(x, y)
        p.rotate(rng.uniform(0, 360))
        p.setBrush(col("#ffb3cb", 230))
        p.drawEllipse(QPointF(0, 0), 7, 4)
        p.restore()
    p.restore()
    ring(p, col("#ff8fb1", 220), 5)
    ring(p, col("#ff8fb1", 80), 2, R + 24)
    p.end()
    save(img, "sakura")


if __name__ == "__main__":
    for fn in (sol, folha, synthwave, lua, onda, cyber, sakura):
        fn()
