"""make_dial.py - pre-drawn, smooth dial images for Speed Gauge.

Copyright (c) 2026 Aaron George
SPDX-License-Identifier: MIT

The DS-24 II draws Lua lines and shapes at Lua resolution and enlarges them
about 1.45x without smoothing, so live curves look stepped. Images keep
their smoothed edges (DFM-InsP's dials are PNGs). This script draws, for
each transmitter window size that shows a dial:

    dial-WxH.png       the face and track ring (opaque), drawn first
    ring-WxH-z.png     the overspeed zone ring and its glow, all 270 degrees
    ring-WxH-o.png     the speed arc and glow in the overspeed color
    ring-WxH-1..9.png  the speed arc and glow in each current-speed color

Ring images are transparent and include the glow inside the arc: the live
glow cost too much CPU on the transmitter (a redraw hit the limit at speed
with a long overspeed zone, 2026-10-03).

The app shows only the needed part of a ring with lcd.setClipping. Sizes:
316 x 159 (full screen) and 150 x 68 (double window). Output goes to
src/Apps/AG-SpdGa/.

The geometry must match buildFull / buildRound in src/Apps/AG-SpdGa.lua,
and the colors C_BG, C_FACE, C_TRACK, C_ZONE and COLORS. Run after
changing either:

    python tools/dial/make_dial.py

Standard library only.
"""

import math
import struct
import zlib
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / "src" / "Apps" / "AG-SpdGa"

C_BG = (8, 10, 14)
C_FACE = (20, 24, 32)
C_TRACK = (70, 78, 90)
C_ZONE = (255, 80, 0)
COLORS = [  # COLORS in the app, same order (research R8)
    (0, 190, 255), (40, 110, 255), (255, 255, 255), (0, 210, 100),
    (170, 240, 0), (230, 60, 230), (150, 100, 255), (170, 170, 170),
    (255, 225, 0),
]
TRACK_W = 3          # live track width
GLOW = (0.36, 0.02)  # glow alpha at the arc and at its deepest (app: GLOW)
ZONE_W = 4           # live overspeed zone width
SS = 4               # samples per pixel along each axis


def full_geometry(w, h):
    """buildFull: dial on the left of the full-screen window."""
    r = math.floor(min((h - 4) / 1.707, (w - 130) / 2 - 2))
    cy = math.floor((h - r * 1.707) / 2 + r)
    return {"r": r, "cx": 2 + r, "cy": cy, "arc_r": r - 5, "arc_w": 7,
            "glow_depth": 9 * 3}     # buildGlow(L, 3, 9)


def round_geometry(w, h):
    """buildRound: small dial on the left of the double window."""
    r = math.floor(min((h - 4) / 1.707, w * 0.55 / 2))
    cy = math.floor((h - r * 1.707) / 2 + r)
    return {"r": r, "cx": 2 + r, "cy": cy, "arc_r": r - 3, "arc_w": 4,
            "glow_depth": 6 * 2}     # buildGlow(L, 2, 6)


def in_sweep(dx, dy):
    """True on the dial's 270-degree sweep: everything but the open bottom
    quarter (screen y points down, so the bottom is +dy)."""
    a = math.degrees(math.atan2(-dy, dx)) % 360   # 0 = right, 90 = up
    return not (225 < a < 315)


def coverage(w, h, g, test, near):
    """Fraction of each pixel's SS x SS samples for which test(d, dx, dy) is
    true; pixels whose center isn't near(d) are skipped as 0 or 1."""
    cx, cy = g["cx"] + 0.5, g["cy"] + 0.5   # Lua pixel (x, y) spans [x, x+1)
    out = []
    step = 1 / SS
    for py in range(h):
        row = []
        for px in range(w):
            d0 = math.hypot(px + 0.5 - cx, py + 0.5 - cy)
            hit = near(d0)
            if hit is not None:
                row.append(hit)
                continue
            n = 0
            for sy in range(SS):
                dy = py + (sy + 0.5) * step - cy
                for sx in range(SS):
                    dx = px + (sx + 0.5) * step - cx
                    if test(math.hypot(dx, dy), dx, dy):
                        n += 1
            row.append(n / (SS * SS))
        out.append(row)
    return out


def ring_coverage(w, h, g, radius, width):
    half = width / 2

    def test(d, dx, dy):
        return abs(d - radius) <= half and in_sweep(dx, dy)

    def near(d):
        return 0 if abs(d - radius) > half + 1.5 else None

    return coverage(w, h, g, test, near)


def ring_glow_alpha(w, h, g, radius, width):
    """Alpha of a ring of the given width plus the glow inside the speed arc:
    from the arc's inner edge (arc_r - arc_w / 2) inward over glow_depth px,
    fading geometrically from GLOW[0] to GLOW[1], as the live glow did."""
    half = width / 2
    top = g["arc_r"] - g["arc_w"] / 2
    depth = g["glow_depth"]
    ratio = GLOW[1] / GLOW[0]
    cx, cy = g["cx"] + 0.5, g["cy"] + 0.5
    step = 1 / SS
    out = []
    for py in range(h):
        row = []
        for px in range(w):
            d0 = math.hypot(px + 0.5 - cx, py + 0.5 - cy)
            if d0 > radius + half + 1.5 or d0 < top - depth - 1.5:
                row.append(0)
                continue
            total = 0.0
            for sy in range(SS):
                dy = py + (sy + 0.5) * step - cy
                for sx in range(SS):
                    dx = px + (sx + 0.5) * step - cx
                    if not in_sweep(dx, dy):
                        continue
                    d = math.hypot(dx, dy)
                    if abs(d - radius) <= half:
                        total += 1
                    elif top - depth <= d <= top:
                        total += GLOW[0] * ratio ** ((top - d) / depth)
            row.append(total / (SS * SS))
        out.append(row)
    return out


def face_coverage(w, h, g):
    r = g["r"]

    def test(d, dx, dy):
        return d <= r

    def near(d):
        if d < r - 1.5:
            return 1
        if d > r + 1.5:
            return 0
        return None

    return coverage(w, h, g, test, near)


def write_png(path, w, h, rows, alpha):
    raw = b"".join(b"\x00" + bytes(row) for row in rows)   # filter type 0
    color_type = 6 if alpha else 2                        # RGBA or RGB, 8-bit

    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF))

    path.write_bytes(b"\x89PNG\r\n\x1a\n"
                     + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, color_type, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(raw, 9))
                     + chunk(b"IEND", b""))


def dial_image(w, h, g):
    """Opaque: background, face, track ring."""
    face = face_coverage(w, h, g)
    track = ring_coverage(w, h, g, g["arc_r"], TRACK_W)
    rows = []
    for fr, tr in zip(face, track):
        row = []
        for f, t in zip(fr, tr):
            for c in range(3):
                v = C_BG[c] * (1 - f) + C_FACE[c] * f
                row.append(round(v * (1 - t) + C_TRACK[c] * t))
        rows.append(row)
    return rows


def ring_image(cov, color):
    """Transparent: one color, alpha = coverage."""
    return [[v for a in row for v in (*color, round(255 * a))] for row in cov]


def main():
    for w, h, geometry in ((316, 159, full_geometry), (150, 68, round_geometry)):
        g = geometry(w, h)
        img_w = min(w, g["cx"] + g["r"] + 2)   # just the dial; the app fills the rest
        tag = f"{w}x{h}"
        write_png(OUT / f"dial-{tag}.png", img_w, h, dial_image(img_w, h, g), False)
        zone = ring_glow_alpha(img_w, h, g, g["arc_r"], ZONE_W)
        write_png(OUT / f"ring-{tag}-z.png", img_w, h, ring_image(zone, C_ZONE), True)
        value = ring_glow_alpha(img_w, h, g, g["arc_r"], g["arc_w"])
        write_png(OUT / f"ring-{tag}-o.png", img_w, h, ring_image(value, C_ZONE), True)
        for i, color in enumerate(COLORS, 1):
            write_png(OUT / f"ring-{tag}-{i}.png", img_w, h, ring_image(value, color), True)
        print(f"{tag}: {img_w} x {h}, R={g['r']} cx={g['cx']} cy={g['cy']} "
              f"arc R={g['arc_r']} width {g['arc_w']}, glow {g['glow_depth']} px; 12 images")


if __name__ == "__main__":
    main()
