# Contract: Telemetry window

```lua
system.registerTelemetry(1, "Speed Gauge", 1, printGauge)        -- single
system.registerTelemetry(2, "Speed Gauge large", 2, printGauge)  -- double
```

One print function for both. It reads only cached state (numbers, cached
strings, dial fractions) and never formats strings, builds tables, reads
sensors or computes trig (constitution VI). All `lcd` calls happen here or in
`ag_gauge` helpers called from here.

## Layouts

Chosen per call from `(w, h)`. Pixel sizes below assume the expected DS-24
windows (research R7) and are re-derived from `w`/`h` in code.

**Compact (`h < 100`, expected 152×69)**

```text
+--------------------------------------+
|  .-~~~-.      123                    |   current: FONT_BIG, right of dial
| /   \   \     mph                    |   unit: FONT_MINI
| |    o  |    max 141                 |   max: FONT_MINI, in max color
|  \_____/                             |
+--------------------------------------+
 dial: diameter h-4, left aligned
```

**Large (`h >= 100`, expected 152×146)**

```text
+--------------------------------------+
|   S45           .-~~~~~-.     O200   |   stall / overspeed labels, FONT_MINI
|             /     123     \          |   current: FONT_MAXI, dial center
|            |      mph      |         |
|             \      o      /          |
|               `-._____.-'           |
|             max 141 mph              |   FONT_NORMAL, in max color
+--------------------------------------+
 dial: diameter min(w, h - 20), centered
```

If a layout's text doesn't fit (`lcd.getTextWidth` against the space left),
drop items in this order: threshold labels, unit text, "max" prefix. Current
and max numbers always stay (US3 #1, FR-015).

## Dial

| Element | Drawn as | Color |
| --- | --- | --- |
| Track | arc 0 → 1, width 2 | foreground, alpha ~60 |
| Stall mark | tick at `fStall` (true-airspeed equivalent, FR-016a) | foreground |
| Overspeed mark | tick at `fOver` | red (220,0,0) |
| Max | arc 0 → `fMax`, width 2, plus tick at `fMax` | `colMax` |
| Current | arc 0 → `fCur`, width 5 | `colCur` |
| Needle | line center → `fCur` at radius − 2 | `colCur` |

Fractions clamp to 0..1; numbers show the real value (US3 #7). Ticks are
drawn only in the large layout if the compact dial is under 50 px.

## States

| State | Dial | Numbers |
| --- | --- | --- |
| Valid reading | current arc + needle, max arc | current, max |
| No data (no sensor, invalid, lost) | track + max only, no needle | current "---", max kept (US3 #5) |
| Max = 0 (just reset / not flown) | no max arc | max "0" |
