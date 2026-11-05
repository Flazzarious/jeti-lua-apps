# Contract: Telemetry windows

Two windows (the most one app may register):

```lua
system.registerTelemetry(1, title1, 1, printSmall)   -- small: one battery (FR-009, FR-010)
system.registerTelemetry(2, title2, 2, printDouble)  -- double: up to four (FR-009, FR-011)
```

Titles default to "Battery" and "Batteries" and are editable (FR-009a);
registered once in `init()`, so a new title shows after the next start.

Design sketches: [../assets/](../assets/) (arrangement and colours only;
where they differ, this contract and the FRs win). Decisions: research R10.

## Layout selection

```text
if w == 157 then h = h - 26 end   -- emulator draws its title inside (Speed Gauge)
if not gaugeOk -> text notice "Battery Capacity needs DS-24 II" (theme colour, FONT_MINI)
elseif no batteries configured -> "Add a battery in settings" (FONT_MINI)
else -> layout below
```

Coordinates are Lua pixels for the transmitter's 150 × 68 / 150 × 23
windows. In the emulator (157 wide) the layout is offset 3 px right. Every
number below is a named constant, tuned on the transmitter with
screenshots.

## Colours (FR-012a, FR-012b, FR-013)

| Element | Colour |
| --- | --- |
| Outline, cap, label, value text, % text on the empty part | neutral: 30, 30, 30 when `lcd.getBgColor()` is light (luma > 128), else 235, 235, 235 (FR-012a; `getFgColor()` is the theme's accent colour on the DS-24 II) |
| Empty part of the battery | not drawn (theme background shows) |
| Fill | band colour (data-model.md) |
| % text on the fill | band's text colour (white; dark on yellow) |
| Low-voltage flash | outline and cap red 226, 75, 74, alternating with theme every 500 ms |
| Lost telemetry | outline, cap and texts in theme colour at alpha 100; no fill |

## Double window (150 × 68): up to four upright batteries

Slot k (1–4) starts at `x0 = 1 + (k − 1) · 37`; batteries keep slot
positions, unused slots draw nothing (FR-011, clarified 2026-11-01).

| Element | Position (relative to slot) | Font | Content |
| --- | --- | --- | --- |
| Label | centred in the 37-px slot, top y 0 | `FONT_MINI` | "RX-1" (width-checked, research R6) |
| Cap | centred, y 12, 10 × 3 | — | filled |
| Body outline | x 5, y 15, 26 × 40, radius 2 | — | |
| Fill | x 7, bottom at y 52, 22 wide, height `(36 · pct + 50) // 100` | — | band colour, one block |
| % text | centred on the body, top y 40 | `FONT_MINI` | "78%"; straddle rule below |
| Below line | centred in slot, top y 56 | `FONT_MINI` | current "42.5 A"; "--" if current sensor lost; else pack voltage "8.1 V"; else blank (FR-011) |

Fill resolution: 36 px for 100%, about 2.8% per pixel; the % text is exact.
In both windows, at 0–2% the fill is drawn at least 2 px thick (`L.minFill`,
FR-012), so an empty pack shows a red sliver.

## Small window (150 × 23): one battery on its side

The battery chosen by `smallB` (FR-009).

| Element | Position | Font | Content |
| --- | --- | --- | --- |
| Body outline | x 1, y 1, 82 × 21, radius 2 | — | |
| Cap | x 83, y 7, 3 × 9 | — | filled |
| Fill | x 3, y 3, height 17, width `(78 · pct + 50) // 100` from the left | — | band colour |
| % text | centred on the body, top y 2 | `FONT_NORMAL` | "72%"; straddle rule below |
| Label | x 90, top y −1 | `FONT_MINI` | "RX-1" |
| Values | x 90, top y 10 | `FONT_MINI` | "8.1V 0.4A"; each part only when that reading is assigned; "--" for a lost reading |

No max current in the small window (FR-010). Fill resolution about 1.3% per
pixel. **UNVERIFIED:** two `FONT_MINI` lines at y −1 and 10 in 23 px; if
they overlap on the transmitter, the label moves into the body's top-left
in `FONT_MINI` and the values line is vertically centred.

## States

| State | Double window | Small window |
| --- | --- | --- |
| Live | as above | as above |
| Low voltage | outline flashes red ~1 Hz (FR-022) | same |
| Telemetry lost (FR-015) | grey outline, no fill, "NO" / "TELEM" stacked inside the body (`FONT_MINI`, y 24 and 36); label grey | grey outline, "NO TELEM" inside the body |
| No capacity source set | grey outline, "--" inside | same |
| Sensor never seen this run (NONE) | grey outline, "--" inside | same |

If "TELEM" is wider than the body (measured `MINI_W`), it overflows the
outline symmetrically: it is still within the 37-px slot.

## Straddle rule (FR-013, edge case)

When the fill's top edge passes through the % text, the text is drawn
twice: in the fill's text colour with `lcd.setClipping` to the filled
rectangle, and in the theme colour clipped to the empty part.
`setClipping` moves the origin, so each draw is offset by the clip corner;
`lcd.resetClipping()` after. When the text is entirely on one side, it's
drawn once. Fallback (if clipping is costly or looks wrong): one draw, in
the fill's colour when the fill covers at least half the text height.

## Rules

- No allocation per frame: all strings (`txtPct`, `txtLine`, `txtSmall`,
  labels) are rebuilt on the 1 s tick only when their value changed.
- `getBgColor()` read once per frame.
- `lcd` calls only in the two print functions (constitution VI).
- Measured with `DEBUG_CPU`: target under 10% per call with four
  batteries (Flameout's double window measured 5–6%).
