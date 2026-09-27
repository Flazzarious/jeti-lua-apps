# Contract: Telemetry windows

```lua
system.registerTelemetry(1, "Speed Gauge", 0, printGauge)               -- pilot places it single or double
system.registerTelemetry(2, "Speed Gauge (full screen)", 3, printGauge) -- keeps the status bar
```

Size 0 is **UNVERIFIED** (research R7). If the pilot can't choose the size,
window 1 is registered at the `winSz` setting's size instead (Single = 1,
Double = 2) and re-registered when the setting changes.

One print function serves both windows. It reads only cached state (numbers,
cached strings, dial fractions, the layout cache) and never formats strings,
reads sensors or computes trig (constitution VI). All `lcd` calls happen here
or in `ag_gauge` helpers called from here.

Design source: the visual design reference in spec US3
(`docs/vendor/gauge-reference.jpg`). Drawing order and colors: research R6
and R8.

## Choosing a layout

| Condition | Layout | Measured size |
| --- | --- | --- |
| not `gaugeOk` (R12) | notice | any |
| `h < 100` | compact | 157 × 60 |
| `w < 250` | round | 157 × 127 |
| otherwise | full screen | 320 × 260 |

The layout cache is rebuilt when `w`, `h` or the scale (full scale, units,
thresholds, `kDens`) changes, and holds: dial center and radii, tick end
points, label positions, face polygon points, and text positions. The
positions below are proportions. The implementation fits them to the fonts'
real heights (`lcd.getTextHeight`) and widths (`lcd.getTextWidth`).

## Compact (single window, 157 × 60)

```text
+---------------------------------------------+
|     .--'''--.          123                  |  current: largest font that fits, white
|   /           \        mph                  |  unit: FONT_MINI, light grey
|  |      ---    |      MAX 141               |  FONT_MINI, max in colMax
+---------------------------------------------+
  180° arc, radius about h - 12, left side;       whole window filled dark
```

- The whole window is filled dark; there is no separate face polygon.
- A 180° track, overspeed zone, value arc and max tick. No numbered scale.
- Stall mark only if the arc radius is at least 30 px.
- Drop order when text doesn't fit: unit, then the "MAX" label. The current
  and max numbers always stay (FR-015).

## Round (double window, 157 × 127)

```text
+---------------------------------------------+
| MAX          .-''''''''-.            STALL  |  corner rows: FONT_MINI label,
| 141        /  50    100   \           45    |  value in FONT_NORMAL
|           | 0             150 |              |  scale labels: FONT_MINI
|           |      123         |              |  center number: FONT_MAXI if it fits
|            \     mph        /              |  unit: FONT_MINI
| OVR          '-.       .-'                  |
| 200                                          |
+---------------------------------------------+
  270° dial, about 115-120 px across, centered, dark face
```

- Face, track, overspeed zone, major ticks with labels and one minor tick
  between majors, stall and landing marks, value arc with tip, max marker.
- The center number is current speed with the unit underneath (FR-014a).
- Corner rows: Max, Stall and Overspeed (FR-016). Stall and Overspeed show
  the setting as entered (FR-016a); Max shows the session max.
- Drop order when space is short: minor ticks, scale labels, corner rows
  (Overspeed, then Stall). Max and the center number always stay.

## Full screen (320 × 260)

```text
+----------------------------------------------------------------+
|             .-''''''''''-.            |  MAX                   |
|         /  50    100   150  \         |  141 mph               |
|       | 0                  200 |      |  STALL                 |
|       |        123             |      |  45 mph                |
|        \       mph            /       |  OVERSPEED             |
|          '-.             .-'         |  200 mph               |
|                                       |  AIR DENSITY           |
|                                       |  +8%   (sensor 100)    |
+----------------------------------------------------------------+
  270° dial, about 200-220 px across, left     side panel about 100 px
```

- The same dial as the round layout, larger, with four minor ticks between
  majors.
- Side panel rows, each a `FONT_MINI` grey label over a `FONT_BIG` white value:
  Max (in `colMax`), Stall, Overspeed, and Air density. The last shows the
  correction ("+8%") and the uncorrected sensor speed while correction is on,
  and is hidden otherwise.

## Notice (not DS-24 II)

`FONT_MINI` text "Speed Gauge needs DS-24 II" in the theme's foreground
color, centered, no face. Nothing else is drawn (FR-013a).

## States (all gauge layouts)

| State | Dial | Numbers |
| --- | --- | --- |
| Valid reading | value arc and tip to `fCur`, max marker | current, max |
| No data (no sensor, invalid, lost) | face, scale, zone and max marker only; no value arc | current "---", max kept (US3 #5) |
| Max = 0 (just reset, or not flown yet) | no max marker | max "0" |
| Above full scale | value arc stops at full scale | real value shown (US3 #7) |
