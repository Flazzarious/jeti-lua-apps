# Research: Speed Gauge

**Feature**: `specs/001-speed-gauge/` | **Date**: 2026-09-27

Each section resolves an open point from the plan's Technical Context or a
decision the spec left to planning. Items marked **UNVERIFIED** rest on the
v1.5 API document or on the original app's behavior and must be confirmed in
the JETI Studio emulator as an early implementation task (see
[quickstart.md](quickstart.md), step 1).

## R1. Density correction formula

- **Decision:** ISA troposphere model, computed once whenever a setting
  changes, never in `loop()`:
  - standard temperature `Ts = 288.15 − 0.0065 · h` (K, h in meters)
  - pressure ratio `δ = (Ts / 288.15) ^ 5.25588`
  - actual temperature `T = Ts` if "standard temperature" is set, else
    `t°C + 273.15`
  - density ratio `σ = δ · 288.15 / T`
  - correction factor `k = 1 / √σ`; true airspeed = sensor speed · k.
- **Rationale:** It is the standard density-altitude formula the spec's FR-021
  measures against, so the 1% tolerance holds by construction. Checked
  numerically (Node, double precision):

  | Elevation | Temp | k | 100 mph reads | Spec |
  | --- | --- | --- | --- | --- |
  | 0 | std | 1.0000 | 100 | SC-003 100 ±1 |
  | 5,000 ft (1,524 m) | std | 1.0773 | 108 | SC-003 108 ±1 |
  | 5,000 ft | 35 °C | 1.1337 | 113 | SC-003 113 ±1 |
  | −1,000 ft | 50 °C | 1.0401 | 104 | range edge |
  | 15,000 ft | −30 °C | 1.2228 | 122 | range edge |
  | 15,000 ft | 50 °C | 1.4097 | 141 | range edge |

  Stall at 40 mph, 5,000 ft, standard: 40 · 1.0773 = 43.09, so the gauge reads
  43 (SC-003a).
- **Single precision:** The transmitter's floats are 32-bit (~7 digits). The
  largest intermediate is `^ 5.25588` on a ratio in 0.89..1.02, well inside
  float range; error is below 0.01%.
- **Alternatives considered:** A lookup table by elevation (smaller code, but
  needs interpolation and a temperature term anyway); the "2% per 1,000 ft"
  pilot rule of thumb (fails the 1% requirement at 15,000 ft).

## R2. Where density math and gauge drawing live

- **Decision:** Two shared modules, both new (no existing users):
  - `src/Apps/lib/ag_dens.lua`: density factor, standard temperature, and
    ft↔m / °F↔°C conversions. Pure functions.
  - `src/Apps/lib/ag_gauge.lua`: dial geometry constructor and arc, tick and
    needle drawing helpers. Called only from the app's print function.
- **Rationale:** The constitution (VII) names exactly these two as examples of
  shared code, and the spec's Assumptions leave the call to the plan. Both are
  stateless: `ag_gauge.newDial()` returns a table the app owns; the module
  keeps nothing.
- **Kept in the app:** speed-unit conversion, callout timing, warnings and the
  settings form. They are specific to this app; moving them to `lib` now would
  be speculative.
- **Alternatives considered:** Everything in one file (simplest, but the next
  app that wants a gauge would copy it, which VII forbids).

## R3. Sensor units

- **Decision:** Keep DFM v2.1's assumption: the value from the speed sensor is
  in m/s, and the app converts it with v2.1's `unitsMult` table (mph
  2.23694, km/h 3.6, kt 1.94384, m/s 1, ft/s 3.28084).
- **Rationale:** The user has flown v2.1 and its speeds look correct. A
  JETI forum thread says the same thing: sensors send speed to the
  transmitter in m/s, and a sensor's km/h setting only affects its own
  display ([jetiforum.de: "Einheit m/s => km/h"](https://jetiforum.de/index.php/4-jeti-sender/489-einheit-m-s-km-h)).
  Nothing found about MSpeed contradicts this. The API doc's description of
  `SensorEntry.unit` as the "default (unconverted) unit" fits: it names the
  unit of the transmitted value.
- **Combined multiplier:** `kSensor = unitsMult[units] · cal / 100`,
  recomputed only when units or calibration change. Per tick:
  `sensorSpd = raw · kSensor`, `shownSpd = sensorSpd · kDens`. `loop()` reads
  the sensor with the lighter `getSensorValueByID`.
- **Alternatives considered:** Read `SensorEntry.unit` and convert from it
  (adds a lookup and a retry path for sensors that aren't connected yet, to
  fix a problem nobody has seen); ask the user for the sensor's unit (a
  setting most users couldn't answer).

## R4. Sensor identity, late sensors, "not found"

- **Decision:** Persist sensor `id`, `param` and `label` (label only for
  display). The selectbox list is rebuilt from `system.getSensors()` every
  time the settings form opens, skipping name rows (`param == 0`), date/time
  (`type 5`) and GPS coordinates (`type 9`). Entry 1 is "(none)". If the saved
  id/param is not in the list, an extra entry "<label> (not found)" is added
  and selected, so the saved choice is kept (Edge Cases).
- **Rationale:** FR-002 and FR-003. `loop()` reads by id/param directly, so it
  never needs the list and starts working the moment the sensor appears.
- **32-bit ids:** Sensor ids are read from the API as Lua integers, so they
  round-trip through `pSave` unchanged; the original stored them the same way.

## R5. Spike rejection for session max

- **Decision:** A new maximum must be confirmed by two consecutive *distinct*
  readings: when the reading changes, `max = math.max(max, math.min(prev,
  cur))`, where `prev` is the previous distinct reading. A single-sample spike
  is ignored; a real peak registers one sample late (~100 ms).
- **Rationale:** The spec requires that one bad sample not ruin the max and
  that the rule be documented. "Distinct" matters because `loop()` ticks
  faster than many sensors update, so the same spike value can be read twice.
- **Documented limitation:** Two consecutive bad samples will still register.
  The user can "Reset max speed".
- **Alternatives considered:** Median of three (needs a buffer, same
  staleness issue); acceleration limit (needs airframe assumptions).

## R6. Gauge drawing on the DS-24

- **Findings:** The API has `drawCircle`, `drawLine` and the anti-aliased
  `lcd.renderer()` (V4.27+, DC/DS-24 only) with `renderPolyline(width,
  alpha)`. There is no filled-circle or arc primitive.
- **Decision:**
  - Dial: 270° sweep, zero at lower-left (225°), full scale at lower-right
    (−45°), clockwise.
  - `ag_gauge.newDial(steps)` precomputes unit cos/sin for `steps + 1` points
    (54 steps = 5° each) once at init. Drawing an arc to fraction `f` adds the
    table points up to `f` plus one interpolated end point to a renderer and
    calls `renderPolyline`. No trig per frame.
  - Draw order (back to front): track arc (foreground color, low alpha),
    stall and overspeed ticks, max arc (max color, thin) from 0 to max plus a
    tick at max, current arc (current color, thick) from 0 to current, needle
    line, numbers.
  - Values above full scale clamp to `f = 1`; the number shows the real value
    (US3 scenario 7).
- **Renderer reuse (UNVERIFIED):** Create one renderer lazily inside the print
  function and call `:reset()` between arcs, to avoid allocating per frame. If
  the emulator shows it can't be reused across frames, create one per frame
  and re-check the CPU figure.
- **Alternatives considered:** Pre-rendered PNG dial with `lcd.loadImage`
  (fixed size, can't recolor, doesn't adapt to window size); plain
  `drawLine` segments (jagged at this size).

## R7. Telemetry window sizes

- **Decision:** Register two windows with the same print function:
  window 1, size 1 ("Speed Gauge"), and window 2, size 2 ("Speed Gauge
  large"). The user places whichever fits. The print function lays out from the
  `(w, h)` it is given, so a window moved between sizes adapts on the next
  draw.
- **Expected sizes (UNVERIFIED):** about 152×69 px (single) and 152×146 px
  (double) on the DS-24. Quickstart step 1 measures them with the official
  `10_telemw.lua` demo before layout work starts.
- **Layouts:** see [contracts/telemetry-window.md](contracts/telemetry-window.md).
  Compact when `h < 100`: dial on the left at the full window height, numbers
  on the right. Large otherwise: centered dial, current number in the middle,
  stall/overspeed labels and max below.
- **Alternatives considered:** Size 0 ("auto"): its behavior isn't documented
  in v1.5.

## R8. Colors and theme

- **Decision:** Eight presets: Blue (0,100,255), Orange (255,140,0), Red
  (220,0,0), Green (0,160,0), Magenta (200,0,200), Cyan (0,170,210), Black,
  White. Defaults: current = Blue, max = Orange (distinct hue and lightness,
  both readable on the DS-24 default light theme). The track and text use
  `lcd.getFgColor()` so they follow the user's theme; the track is drawn with
  low alpha.
- **Rationale:** FR-017 asks for at least 6. Red is left non-default because
  pilots read red as an alarm.

## R9. Callout timing (checked against v2.1)

- **Decision:** Keep the original's formula unchanged, with the new ranges:
  - `d = clamp(|shownSpd − lastSpokenSpd| / sensitivity, 0.5, 10)`
  - `interval = min(shortest · 10 / d, longest)` seconds
  - Below landing speed (after having been above it) or with the continuous
    switch on: `interval = shortest`.
- **Check with defaults** (shortest 2, longest 40, sensitivity 10):
  steady → d = 0.5 → 40 s; change of 10 → d = 1 → 20 s; change ≥ 100 → d =
  10 → 2 s. Matches FR-005 and SC-001.
- **Loop cadence:** logic runs every 100 ms (`TICK_MS`), not every 20–30 ms
  loop, meeting SC-005 (0.5 s) with room to spare. Timing error ≤ 0.1 s.

## R10. Settings that the form API can't express directly

- **"Temperature (blank = standard)":** An intbox can't be blank. Use a
  checkbox row "Use standard temperature" directly under the temperature
  intbox, which is disabled (`form.setProperties(..., {enabled=false})`) while
  checked. The hint row reads "Standard = normal for this elevation". Same
  intent as the spec's label.
- **Gauge full scale default:** intbox with 0 meaning "Auto". Auto = overspeed
  × 1.15 rounded up to the next 10. The row's hint shows the resolved value.
- **Units change (Edge Cases):** Convert, don't warn. On a units change all
  speed settings (sensitivity, landing, stall, overspeed, full scale if not
  auto) are converted by the ratio of unit factors and rounded; when the
  change crosses imperial/metric, elevation and temperature are converted too.
  Then `form.reinit()` redraws the values.
- **Threshold order (FR-026):** A warning label at the top of the Warnings
  group, hidden unless stall ≥ landing, landing ≥ overspeed, or overspeed >
  full scale (explicit). Re-evaluated in each threshold's callback. The
  settings are still saved (the user may be mid-edit).
- **Switch "on":** value > 0.5 from `system.getInputsVal`. Same as the
  original's `== 1` for two- and three-position switches; for proportional
  controls it is "on in the upper quarter" instead of "only at the end stop".
  Unassigned (`nil`) is off.

## R11. Behavior differences from DFM Speed Announcer v2.1 (SC-008)

Everything else matches v2.1.

| # | v2.1 | Speed Gauge | Source |
| --- | --- | --- | --- |
| 1 | Sensor list built once at init | Rebuilt each time settings open | FR-002 |
| 2 | Selection saved as list index + id/param | id/param + label; "not found" entry | FR-003 |
| 3 | Calibration file `DFM-<model>.jsn` | Dropped; setting saved per model | Spec Assumptions |
| 4 | "Call at least every" 10–40 s | 10–60 s | FR-005 |
| 5 | "Call < Vref every" default 3 in intbox, 2 on load | 2 everywhere | FR-005 |
| 6 | Flight flags frozen while both switches off | Tracked whenever the reading is valid; only sounds need a switch | FR-012 |
| 7 | Window: one text line "Calibrated Airspeed" | Round gauge, two sizes, session max | US3 |
| 8 | Debug toggled by sensitivity 99/98 | Removed; debug prints only in the emulator | cleanup |
| 9 | Startup stall announcement always | On by default, can be turned off | FR-028 |
| 10 | Switch on only at `== 1` | `> 0.5` (R10) | R10 |
| 11 | No density correction | Optional, airspeed sensors only | US4 |
| 12 | Unused `V_ref_speed.wav`, `Spd_ann_act.wav` shipped | Not copied | cleanup |
| 13 | Normal callouts need *current* speed > Vref/2 | Latched: once exceeded this session, stays open | FR-009, US1 #7 |
