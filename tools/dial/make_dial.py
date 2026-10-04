"""make_dial.py - pre-drawn, smooth dial backgrounds for Speed Gauge.

Copyright (c) 2026 Aaron George
SPDX-License-Identifier: MIT

The DS-24 II draws Lua lines and shapes at Lua resolution and enlarges them
about 1.45x without smoothing, so live curves look stepped. Images keep
their smoothed edges (DFM-InsP's dials are PNGs). This script draws the
parts of the dial that never change with settings, the face and the track
ring, as anti-aliased PNGs, one per transmitter window size:

    src/Apps/AG-SpdGa/dial-316x159.png   full screen
    src/Apps/AG-SpdGa/dial-150x68.png    double window

The geometry must match buildFull / buildRound in src/Apps/AG-SpdGa.lua,
and the colors C_BG, C_FACE and C_TRACK. Run after changing either:

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
TRACK_W = 3          # same width as the live track
SS = 4               # samples per pixel along each axis


def full_geometry(w, h):
    """buildFull: dial on the left of the full-screen window."""
    r = math.floor(min((h - 4) / 1.707, (w - 130) / 2 - 2))
    cy = math.floor((h - r * 1.707) / 2 + r)
    return r, 2 + r, cy, r - 5


def round_geometry(w, h):
    """buildRound: small dial on the left of the double window."""
    r = math.floor(min((h - 4) / 1.707, w * 0.55 / 2))
    cy = math.floor((h - r * 1.707) / 2 + r)
    return r, 2 + r, cy, r - 3


def in_sweep(dx, dy):
    """True on the dial's 270-degree sweep: everything but the open bottom
    quarter (screen y points down, so the bottom is +dy)."""
    a = math.degrees(math.atan2(-dy, dx)) % 360   # 0 = right, 90 = up
    return not (225 < a < 315)


def render(w, h, geometry):
    r, cx, cy, arc_r = geometry(w, h)
    img_w = min(w, cx + r + 2)    # just the dial; the app fills the rest
    rows = []
    half = TRACK_W / 2
    step = 1 / SS
    for py in range(h):
        row = bytearray()
        for px in range(img_w):
            face = track = 0
            for sy in range(SS):
                y = py + (sy + 0.5) * step
                for sx in range(SS):
                    x = px + (sx + 0.5) * step
                    # Lua draws pixel (px, py) over [px, px+1); centers at +0.5.
                    dx, dy = x - (cx + 0.5), y - (cy + 0.5)
                    d = math.hypot(dx, dy)
                    if d <= r:
                        face += 1
                        if abs(d - arc_r) <= half and in_sweep(dx, dy):
                            track += 1
            n = SS * SS
            f, t = face / n, track / n
            px_col = []
            for c in range(3):
                v = C_BG[c] * (1 - f) + C_FACE[c] * f       # face over background
                v = v * (1 - t) + C_TRACK[c] * t            # track over face
                px_col.append(round(v))
            row += bytes(px_col)
        rows.append(bytes(row))
    return img_w, rows


def write_png(path, w, h, rows):
    raw = b"".join(b"\x00" + row for row in rows)   # filter type 0 per row

    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF))

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))  # 8-bit RGB
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    path.write_bytes(png)


def main():
    for w, h, geometry in ((316, 159, full_geometry), (150, 68, round_geometry)):
        img_w, rows = render(w, h, geometry)
        path = OUT / f"dial-{w}x{h}.png"
        write_png(path, img_w, h, rows)
        r, cx, cy, arc_r = geometry(w, h)
        print(f"{path.relative_to(REPO)}: {img_w} x {h}, R={r} cx={cx} cy={cy} track R={arc_r}")


if __name__ == "__main__":
    main()
