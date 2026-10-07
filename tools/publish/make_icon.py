"""make_icon.py - draw Speed Gauge's app icon for JETI Studio.

Copyright (c) 2026 Aaron George
SPDX-License-Identifier: MIT

A 64 x 64 PNG (the size of JETI's own app icons) in the gauge's style: a
dark face, the grey track, a cyan speed arc, the orange overspeed zone and
a yellow max mark, with "AG" (Aaron George) in the center; smoothed by
sampling each pixel 8 x 8.

    python tools/publish/make_icon.py            # docs/apps/img/speed-gauge-icon.png
    python tools/publish/make_icon.py --preview  # also all variants, enlarged

Standard library only.
"""

import math
import struct
import sys
import zlib
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / "docs" / "apps" / "img" / "speed-gauge-icon.png"
SIZE = 64
SS = 8

BG = (8, 10, 14)
FACE = (20, 24, 32)
RIM = (46, 52, 64)
TRACK = (70, 78, 90)
CYAN = (0, 190, 255)
ZONE = (255, 80, 0)
YELLOW = (255, 225, 0)
WHITE = (255, 255, 255)

START, SWEEP = 225.0, 270.0     # the dial: zero at lower-left, clockwise


def ang(f):
    """Math angle (degrees, 0 = right, counter-clockwise) at dial fraction f."""
    return START - SWEEP * f


def frac(dx, dy):
    """Dial fraction of a point (screen y down), or None in the open bottom."""
    a = math.degrees(math.atan2(-dy, dx)) % 360
    f = (START - a) % 360 / SWEEP
    return f if f <= 1 else None


def on_seg(px, py, ax, ay, bx, by, half):
    vx, vy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * vx + (py - ay) * vy) / (vx * vx + vy * vy)))
    return math.hypot(px - ax - t * vx, py - ay - t * vy) <= half


MONO_H = 7.0       # half the letter height, px
MONO_STROKE = 1.35  # half the stroke width, px


def monogram(x, y, c):
    """True on the strokes of "AG", centered on (c, c)."""
    h, w = MONO_H, MONO_STROKE
    top, bot = c - h, c + h
    # A: apex, two feet, a crossbar a third of the way up.
    ax0, ax1, apex = c - 12.5, c - 1.0, c - 6.75
    if on_seg(x, y, apex, top, ax0, bot, w) or on_seg(x, y, apex, top, ax1, bot, w):
        return True
    yb = c + h / 3
    t = (yb - top) / (bot - top)
    if on_seg(x, y, apex + (ax0 - apex) * t, yb, apex + (ax1 - apex) * t, yb, w):
        return True
    # G: a ring open between 0 and 50 degrees, plus a bar from its middle
    # to the right edge at 0 degrees.
    gx, gr = c + 7.25, h - w
    d = math.hypot(x - gx, y - c)
    a = math.degrees(math.atan2(-(y - c), x - gx)) % 360
    if abs(d - gr) <= w and not 0 < a < 50:
        return True
    return on_seg(x, y, gx + 0.5, c, gx + gr + w * 0.6, c, w)


VARIANTS = {
    # name: (value fraction, max fraction, overspeed fraction, needle?, glow?)
    "arc": (0.62, 0.74, 0.84, False, True),
    "needle": (0.62, 0.74, 0.84, True, False),
    "bold": (0.70, 0.80, 0.84, False, False),
}


def shade(x, y, variant):
    """Color of one sample point in a 64 x 64 icon (0..64 coordinates)."""
    value, mx, over, needle, glow = VARIANTS[variant]
    c = SIZE / 2
    dx, dy = x - c, y - c
    d = math.hypot(dx, dy)
    # Rounded-square tile.
    r_corner = 12
    qx, qy = max(abs(dx) - (c - r_corner), 0), max(abs(dy) - (c - r_corner), 0)
    if math.hypot(qx, qy) > r_corner:
        return None                      # transparent outside the tile
    col = BG
    R = 29.0                             # face radius
    if d <= R:
        col = RIM if d > R - 1.6 else FACE
    f = frac(dx, dy)
    arc_r, arc_w = 22.5, 6.5 if variant == "bold" else 5.0
    if f is not None:
        on_arc = abs(d - arc_r) <= arc_w / 2
        if on_arc:
            col = TRACK
            if f >= over:
                col = ZONE
            if f <= value:
                col = CYAN
        elif glow and f <= value and arc_r - arc_w / 2 - 9 <= d < arc_r - arc_w / 2:
            k = (arc_r - arc_w / 2 - d) / 9          # 0 at the arc .. 1 inside
            a = 0.45 * (1 - k) ** 2
            col = tuple(round(col[i] * (1 - a) + CYAN[i] * a) for i in range(3))
    # Max mark: a short yellow bar across the arc.
    a = math.radians(ang(mx))
    ux, uy = math.cos(a), -math.sin(a)
    if on_seg(x, y, c + ux * (arc_r - 5), c + uy * (arc_r - 5),
              c + ux * (arc_r + 5), c + uy * (arc_r + 5), 1.6):
        col = YELLOW
    # "AG" (Aaron George) in the center, drawn as strokes so no font is
    # needed: A from two legs and a crossbar, G as an arc open at the upper
    # right with a bar into the middle.
    ag = monogram(x, y, c)
    if ag:
        col = WHITE
    if needle:
        a = math.radians(ang(value))
        ux, uy = math.cos(a), -math.sin(a)
        if on_seg(x, y, c, c, c + ux * (arc_r - 1), c + uy * (arc_r - 1), 1.4):
            col = WHITE
        if d <= 3.6:
            col = WHITE
    return col


def render(variant, size=SIZE):
    rows = []
    step = 1 / SS
    scale = SIZE / size
    for py in range(size):
        row = bytearray()
        for px in range(size):
            acc = [0.0, 0.0, 0.0, 0.0]
            for sy in range(SS):
                for sx in range(SS):
                    col = shade((px + (sx + 0.5) * step) * scale,
                                (py + (sy + 0.5) * step) * scale, variant)
                    if col is not None:
                        acc[0] += col[0]
                        acc[1] += col[1]
                        acc[2] += col[2]
                        acc[3] += 1
            n = acc[3]
            if n:
                row += bytes((round(acc[0] / n), round(acc[1] / n), round(acc[2] / n),
                              round(255 * n / (SS * SS))))
            else:
                row += b"\0\0\0\0"
        rows.append(bytes(row))
    return rows


def write_png(path, size, rows):
    raw = b"".join(b"\x00" + r for r in rows)

    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF))

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"\x89PNG\r\n\x1a\n"
                     + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(raw, 9))
                     + chunk(b"IEND", b""))


def main():
    write_png(OUT, SIZE, render("arc"))
    print(f"wrote {OUT.relative_to(REPO)}")
    if "--preview" in sys.argv:
        for v in VARIANTS:
            p = Path(sys.argv[sys.argv.index("--preview") + 1]) / f"icon-{v}.png"
            write_png(p, SIZE, render(v))
            print(f"preview {v}: {p}")


if __name__ == "__main__":
    main()
