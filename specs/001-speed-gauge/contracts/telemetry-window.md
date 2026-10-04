# Contract: Telemetry windows

```lua
system.registerTelemetry(1, "Speed Gauge", 0, printGauge)  -- pilot places it single or double
system.registerTelemetry(2, "Speed Gauge (full screen)", 4, printGauge)  -- no status bar (R7, FR-013)
```

Size 0 lets the pilot place window 1 at single or double size. Size 4 is
used for full screen because the desktop's model tile covers a size-3
window's lower-left corner (research R7; the same on the transmitter).

**Sizes and the title bar.** Redesigned 2026-10-03 after the first
transmitter run (see `docs/jeti-api-notes.md`). The transmitter reports only
what is visible and draws the title above the window. The emulator reports
a larger area that includes the title bar and a hidden bottom strip:

| Window | Transmitter (design target) | Emulator: reported → visible |
| --- | --- | --- |
| Single | 150 × 23 | 157 × 60 → ~157 × 34 |
| Double | 150 × 68 | 157 × 127 → ~157 × 101 |
| Full screen | 316 × 159 | 320 × 260 → ~320 × 234 |

The print function subtracts `TITLE_H = 26` from `h` only when `w` is 157 or
320, the emulator's widths. It then chooses the layout from the visible
size. The renderer doesn't clip to the window, so the dial face is cut flat
at the bottom (`ag_gauge.face` with `maxY`).

One print function serves both windows. It reads only cached state (numbers,
cached strings, dial fractions, the layout cache) and never formats strings,
reads sensors or computes trig (constitution VI). All `lcd` calls happen here
or in `ag_gauge` helpers called from here.

Design source: the visual design reference in spec US3
(`docs/vendor/gauge-reference.jpg`). Drawing order and colors: research R6
and R8. Dial edges use 3° steps; the translucent glow keeps 10° steps.

**Smooth dial images (2026-10-03).** The transmitter enlarges Lua lines
about 1.45× without smoothing, so live curves step. For the transmitter's
two dial sizes the face and track ring come from pre-drawn, anti-aliased
PNGs, `/Apps/AG-SpdGa/dial-316x159.png` and `dial-150x68.png`, made by
`tools/dial/make_dial.py` and committed. DFM-InsP's dials are PNGs for the
same reason. The image is loaded once per window size in the print function
and drawn at (0, 0). Without a matching file (the emulator's sizes, or a
missing file) the face and track are drawn live, with a wider translucent
pass under each arc to soften the steps. The overspeed zone, ticks, scale
numbers, value arc and max marker are always live: they depend on settings
or move.

## Choosing a layout (visible size)

| Condition | Layout | Transmitter size |
| --- | --- | --- |
| not `gaugeOk` (R12) | notice | any |
| `h < 45` | strip | 150 × 23 |
| `w < 250` | small dial | 150 × 68 |
| otherwise | full screen | 316 × 159 |

The layout cache is rebuilt when `w`, `h` or the scale (full scale, units,
thresholds, `kDens`) changes.

## Strip (single window, 150 × 23)

```text
+--------------------------------------------+
| 123 mph                          MAX 141   |  speed: largest font that fits
| ████████████████▌······|·····▒▒▒▒▒▒▒       |  (FONT_NORMAL); unit, MAX: FONT_MINI
+--------------------------------------------+
```

- Dark background over the whole window.
- Bar along the bottom, 4 px: track, overspeed zone from `fOver` to the end,
  value in `colCur` up to the overspeed mark and the zone color beyond it,
  and a 2-px max tick in `colMax`, slightly taller than the bar.
- The current and max numbers always stay (FR-015). The max value is in
  `colMax`.

## Small dial (double window, 150 × 68)

```text
+--------------------------------------------+
|   .-''-.          123                      |  speed: FONT_BIG if it fits
|  /      \         mph                      |  unit: FONT_MINI
| |   ↗    |                                 |
|  \      /         MAX                      |  MAX label FONT_MINI,
|   '-  -'          141                      |  value FONT_NORMAL in colMax
+--------------------------------------------+
  270° dial, about 74 px across, on the left
```

- Face, track, overspeed zone with glow, major ticks (no scale numbers, no
  minor ticks), stall and landing marks, value arc with tip, max marker.
- Stall and overspeed have no rows; there's no room (FR-016 is a SHOULD).

## Full screen (316 × 159)

```text
+----------------------------------------------------------------+
|           .-''''''''-.             | STALL              45 mph |
|        /  50    100   \            | OVER              200 mph |
|      | 0      123     150 |        | DENSITY                +8% |
|      |        mph         |        | ELEV              5000 ft |
|       \       MAX        /         | TEMP SENS           95 °F |
|               141                 | RAW               100 mph |
+----------------------------------------------------------------+
  270° dial, about 180 px across        panel about 124 px
```

- The same dial as the small one, larger, with numbered major ticks
  (`FONT_MINI` at this size; `FONT_NORMAL` once the radius is 110 px or more,
  i.e. in the emulator) and one minor tick between majors (four at the
  larger size).
- Current speed in the center in the largest font that fits, unit below.
- MAX in the open bottom of the dial: `FONT_MINI` grey label over the value
  in `FONT_BIG`, `colMax`, centered under the speed.
- Side panel, six one-line rows of about 26 px: `FONT_MINI` grey label on
  the left; value in `FONT_NORMAL` white, right-aligned, followed by its
  unit in `FONT_MINI`:
  - STALL, OVER: always, as entered (FR-016a).
  - DENSITY: always. "+8%" while correction is active, "OFF" when it is off,
    "GPS" when the sensor type is GPS.
  - ELEV, the temperature row and RAW: only while correction is active.
  - The temperature row (FR-044) shows the temperature in use. Its label
    names the source: "TEMP STD", "TEMP MAN" or "TEMP SENS". While the
    sensor reading is rejected (`tStat = 1`, or Sensor with no sensor
    chosen), the label is "SENSOR OUT" in the overspeed color and the value
    is the standard temperature being used.

## Notice (not DS-24 II)

`FONT_MINI` text "Speed Gauge needs DS-24 II" in the theme's foreground
color, centered, no face. Nothing else is drawn (FR-013a).

## States (all layouts)

| State | Gauge | Numbers |
| --- | --- | --- |
| Valid reading | value arc (or bar) and tip to `fCur`, max marker | current, max |
| No data (no sensor, invalid, lost) | face, scale, zone and max marker only; no value arc or bar | current "---", max kept (US3 #5) |
| Max = 0 (just reset, or not flown yet) | no max marker | max "0" |
| Above overspeed | value in `colCur` up to the overspeed mark, overspeed color (and glow) beyond it | current, max |
| Above full scale | value stops at full scale | real value shown (US3 #7) |

**Max marker:** `colMax` (default Yellow), drawn after the value so it stays
visible on top of it (research R6, FR-017).
