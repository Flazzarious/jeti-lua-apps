"""Generate the Flameout Alarm RPM window mockup (SVG, Lua coordinates)."""
import sys

FACE = "rgb(18,20,24)"
CYAN = "rgb(0,190,255)"
UNLIT_FILL = "rgb(34,38,44)"
UNLIT_EDGE = "rgb(70,74,80)"
YELLOW = "rgb(255,225,0)"
WHITE = "rgb(255,255,255)"
GREY = "rgb(170,170,170)"
RED = "rgb(255,45,30)"
FONT = "font-family='Arial, Helvetica, sans-serif' font-weight='bold'"

N = 12            # segments
X0, X1 = 4, 146   # sweep extent
GAP = 2


def yb(t):        # bottom edge: rises steeply on the left, flattens on the right
    return 22 + 40 * (1 - t) ** 2.2


def h(t):         # segment height grows toward the high end
    return 6 + 12 * t


def sweep(ox, oy, lit, lit_col, idle_frac):
    w = (X1 - X0 - GAP * (N - 1)) / N
    out = []
    for i in range(N):
        xa = X0 + i * (w + GAP)
        xb = xa + w
        ta, tb = (xa - X0) / (X1 - X0), (xb - X0) / (X1 - X0)
        pts = [(xa, yb(ta)), (xb, yb(tb)), (xb, yb(tb) - h(tb)), (xa, yb(ta) - h(ta))]
        p = " ".join(f"{ox + x:.1f},{oy + y:.1f}" for x, y in pts)
        if i < lit:
            out.append(f"<polygon points='{p}' fill='{lit_col}'/>")
        else:
            out.append(f"<polygon points='{p}' fill='{UNLIT_FILL}' stroke='{UNLIT_EDGE}' stroke-width='0.6'/>")
    # idle marker: a yellow bar across the sweep, poking out above and below
    xi = X0 + idle_frac * (X1 - X0)
    ti = idle_frac
    out.append(f"<line x1='{ox + xi:.1f}' y1='{oy + yb(ti) + 3:.1f}' x2='{ox + xi:.1f}' "
               f"y2='{oy + yb(ti) - h(ti) - 3:.1f}' stroke='{YELLOW}' stroke-width='2'/>")
    return "\n".join(out)


def window(ox, oy, title, body, wh=68):
    return (f"<text x='{ox}' y='{oy - 4}' {FONT} font-size='9' fill='{GREY}'>{title}</text>\n"
            f"<rect x='{ox}' y='{oy}' width='150' height='{wh}' fill='{FACE}'/>\n{body}")


def double_armed(ox, oy):
    rpm, full, idle = 112400, 140000, 35000
    lit = round(N * rpm / full)
    b = sweep(ox, oy, lit, CYAN, idle / full)
    b += (f"\n<text x='{ox + 4}' y='{oy + 13}' {FONT} font-size='12' fill='{CYAN}'>ARMED</text>"
          f"\n<text x='{ox + 146}' y='{oy + 52}' {FONT} font-size='22' fill='{WHITE}' "
          f"text-anchor='end'>112,400</text>"
          f"\n<text x='{ox + 146}' y='{oy + 64}' {FONT} font-size='9' fill='{GREY}' "
          f"text-anchor='end'>RPM</text>")
    return window(ox, oy, "Double size: armed", b)


def double_flameout(ox, oy):
    full, idle = 140000, 35000
    b = sweep(ox, oy, 0, CYAN, idle / full)
    b += (f"\n<rect x='{ox + 4}' y='{oy + 2}' width='142' height='24' fill='{RED}'/>"
          f"\n<text x='{ox + 75}' y='{oy + 21}' {FONT} font-size='20' fill='{WHITE}' "
          f"text-anchor='middle'>FLAMEOUT</text>"
          f"\n<text x='{ox + 146}' y='{oy + 52}' {FONT} font-size='22' fill='{WHITE}' "
          f"text-anchor='end'>4,800</text>"
          f"\n<text x='{ox + 146}' y='{oy + 64}' {FONT} font-size='9' fill='{GREY}' "
          f"text-anchor='end'>RPM</text>")
    return window(ox, oy, "Double size: flameout", b)


def single(ox, oy):
    rpm, full, idle = 112400, 140000, 35000
    bx, bw, by, bh = 4, 84, 8, 8
    b = (f"<rect x='{ox + bx}' y='{oy + by}' width='{bw}' height='{bh}' fill='{UNLIT_FILL}' "
         f"stroke='{UNLIT_EDGE}' stroke-width='0.6'/>"
         f"\n<rect x='{ox + bx}' y='{oy + by}' width='{bw * rpm / full:.1f}' height='{bh}' fill='{CYAN}'/>"
         f"\n<line x1='{ox + bx + bw * idle / full:.1f}' y1='{oy + by - 3}' "
         f"x2='{ox + bx + bw * idle / full:.1f}' y2='{oy + by + bh + 3}' stroke='{YELLOW}' stroke-width='2'/>"
         f"\n<text x='{ox + 146}' y='{oy + 13}' {FONT} font-size='13' fill='{WHITE}' "
         f"text-anchor='end'>112,400</text>"
         f"\n<text x='{ox + 146}' y='{oy + 21}' {FONT} font-size='7' fill='{CYAN}' "
         f"text-anchor='end'>ARMED</text>")
    return window(ox, oy, "Single size: armed", b, 23)


W, H = 330, 200
parts = [double_armed(10, 20), double_flameout(170, 20), single(10, 120)]
note = (f"<text x='170' y='130' {FONT} font-size='7' fill='rgb(120,120,120)'>"
        "Mockup in Lua coordinates (150 x 68 / 150 x 23).</text>"
        f"<text x='170' y='140' {FONT} font-size='7' fill='rgb(120,120,120)'>"
        "Fonts approximate FONT_BIG / FONT_MINI.</text>"
        f"<text x='170' y='150' {FONT} font-size='7' fill='rgb(120,120,120)'>"
        "Yellow bar = idle RPM. Full scale = 4 x idle.</text>")
svg = (f"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 {W} {H}' width='{W * 3}' "
       f"height='{H * 3}'>\n<rect width='{W}' height='{H}' fill='rgb(235,235,235)'/>\n"
       + "\n".join(parts) + "\n" + note + "\n</svg>\n")
with open(sys.argv[1], "w", encoding="utf-8", newline="\n") as f:
    f.write(svg)
