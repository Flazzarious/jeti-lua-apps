# Research: Speed Gauge

**Feature**: `specs/001-speed-gauge/` | **Date**: 2026-09-27, updated 2026-10-03
(R13–R17: app voice, temperature sensor and input limits from the spec
sessions of 2026-09-28 and 2026-09-30)

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
  | −300 ft (−91 m) | −29 °C | 0.9155 | 92 | range edge (FR-020) |
  | −300 ft | 54 °C | 1.0598 | 106 | range edge |
  | 10,000 ft (3,048 m) | −29 °C | 1.1100 | 111 | range edge |
  | 10,000 ft | std (−4.8 °C) | 1.1637 | 116 | range edge |
  | 10,000 ft | 54 °C | 1.2849 | 128 | range edge |

  Rows recomputed 2026-10-03 for the narrower limits of FR-020. The
  standard temperature stays inside the temperature limits across the whole
  elevation range (15.6 °C at −300 ft, −4.8 °C at 10,000 ft), as FR-020
  requires.

  Stall at 40 mph, 5,000 ft, standard: 40 · 1.0773 = 43.09, so the gauge reads
  43 (SC-003a).
- **Single precision:** The transmitter's floats are 32-bit (~7 digits). The
  largest intermediate is `^ 5.25588` on a ratio in 0.93..1.01, well inside
  float range; error is below 0.01%.
- **Alternatives considered:** A lookup table by elevation (smaller code, but
  needs interpolation and a temperature term anyway); the "2% per 1,000 ft"
  pilot rule of thumb (fails the 1% requirement at 15,000 ft).

## R2. Where density math and gauge drawing live

- **Decision:** Two shared modules, both new (no existing users):
  - `src/Apps/lib/ag_dens.lua`: density factor, standard temperature, and
    ft↔m / °F↔°C conversions. Pure functions.
  - `src/Apps/lib/ag_gauge.lua`: dial geometry constructor and arc, tick and
    rim-mark drawing helpers. Called only from the app's print function.
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
- **Always call the `system.getSensor*` functions through `system`** at each
  use, never through a local copy made when the file loads. LeonAirRC's
  Emulator Telemetry app (used for testing, see `tools/emulator/sensors.json`)
  replaces those functions after other apps may already have loaded. A cached
  copy would bypass the emulated sensors.
- **Emulator sensors send m/s**, like real ones: `tools/emulator/sensors.json`
  defines MSpeed 450 Velocity 0–125 m/s (≈ 0–450 km/h) on P5 and GPS Speed
  0–83.3 m/s (≈ 0–300 km/h) on P6.
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

- **Decision:** A value only raises the session max once it is confirmed,
  in one of two ways:
  - **Two distinct readings in a row:** when the reading changes,
    `candidate = math.min(prev, cur)`, where `prev` is the previous distinct
    reading. A single-sample spike never counts. A real peak registers one
    sample late (about 100 ms).
  - **Held for 1 s:** if the reading hasn't changed for `HOLD_MS` (1,000 ms),
    `candidate = cur`. A perfectly steady speed would otherwise never count.
    That happens with the emulator's held controls, and after "Reset max
    speed" at constant speed.

  `max = math.max(max, candidate)`.
- **Rationale:** The spec requires that one bad sample not ruin the max, and
  that the rule be documented. "Distinct" matters because `loop()` ticks
  faster than many sensors update, so the same spike value can be read
  twice. The 1-s hold is longer than any plausible repeat of a single
  telemetry sample.
- **Documented limitation:** Two consecutive bad samples, or a bad value that
  stays on the sensor for a second, will still register. The user can
  "Reset max speed".
- **Found in testing:** The first version had only the distinct-readings rule.
  A mock-API run showed the max never rising at constant speed, so the hold
  rule was added (2026-09-27).
- **Alternatives considered:** Median of three (needs a buffer, same
  staleness issue); acceleration limit (needs airframe assumptions).

## R6. Gauge drawing on the DS-24 II

Design source: the visual design reference in spec US3 (a car head-up-display
speedometer; local copy at `docs/vendor/gauge-reference.jpg`).

- **Findings:** The API has `drawLine`, `drawFilledRectangle`, `drawText`
  and the anti-aliased `lcd.renderer()` (V4.27+, DC/DS-24 only) with
  `renderPolyline(width, alpha)` and `renderPolygon(alpha)`. There is no
  filled-circle or arc primitive, so the dark face is a filled polygon and
  every arc is a polyline.
- **Decision: geometry**
  - Round dial (double and full screen): 270° sweep, zero at lower-left
    (225°), full scale at lower-right (−45°), clockwise, bottom open.
  - Compact dial (single window): 180° sweep from the left (180°) over the
    top to the right (0°), per the spec's "shallow arc".
  - `ag_gauge.newDial(steps, startDeg, sweepDeg)` precomputes unit cos/sin
    once in `init()`: 54 steps (5° each) for the round dial and 36 for the
    compact one. A 72-point unit circle is precomputed for the face polygon.
  - Arcs run from fraction `f0` to `f1`, so one helper draws the track
    (0 → 1), the overspeed zone (fOver → 1) and the value arc (0 → current).
- **Decision: scale**
  - The major tick step is the smallest of 10, 20, 25, 50, 100, 200, 250, 500
    (in the user's units) that gives at most 8 major intervals up to full
    scale. Minor ticks between majors: 4 on the full-screen dial, 1 on the
    double dial, none on the compact dial.
  - Major labels ("0", "50", "100", ...) are built as strings in
    `recomputeScale()`, only when full scale or units change.
- **Decision: draw order, back to front**
  1. Face: a dark polygon (RGB 20, 24, 32) covering the dial. The compact
     layout fills the whole window with `drawFilledRectangle` instead.
  2. Track: arc 0 → 1, grey (70, 78, 90), width 3.
  3. Overspeed zone: arc fOver → 1, orange-red (255, 80, 0), width 4.
  4. Scale: major ticks and labels in light grey (200, 200, 200), minor ticks
     in darker grey.
  5. Stall and landing marks: short light-grey ticks at `fStall` and `fLand`,
     the true-airspeed equivalents (FR-016a).
  6. Value arc: 0 → `fCur` in `colCur`, width 6 (round) or 5 (compact), with a
     bright 2-px tip line at the end. Under it, a glow like the reference:
     concentric arcs in `colCur` just inside the value arc, each fainter
     toward the center (alpha 0.42 down to 0.015). There are 5, 6 or 8 bands,
     2, 3 or 4 px apart, for compact, round and full screen (added after
     emulator review, 2026-09-27). The overspeed zone gets the same glow in its
     own color. Above `fOver` the value arc and its glow are split: `colCur`
     up to `fOver`, the overspeed color from `fOver` to `fCur` (spec FR-014).
  7. Max marker: a tick at `fMax` in `colMax`, from inside the value arc out
     to the rim, width 3 (compact), 4 (round) or 5 (full screen). It is
     drawn after the value arc, so it stays visible while the arc passes
     under it (FR-014).
  8. Text: center number, unit and labeled rows.
- Values above full scale clamp to `f = 1`; the number shows the real value
  (US3 scenario 7).
- **Decision: CPU (SC-007).** Everything that depends only on window size and
  settings (tick end points, label positions, face polygon points, radii)
  goes into a layout cache. It is computed the first time a `(w, h)` is drawn,
  and again only when `w`, `h` or the scale changes. Per frame, the print
  function only walks cached arrays.
  - **Planned fallback, tried and dropped (2026-09-27):** draw the static
    parts once into an off-screen image (`lcd.createImage` and
    `lcd.renderer(image)`) and copy it each frame. On the II emulator the
    image showed nothing and the CPU figure did not drop, so the code was
    removed and everything is drawn live.
  - **What the CPU figure is:** the app list shows the highest per-call
    budget use (`system.getCPU()`), not an average. Measured: start-up 24%,
    loop 0–1%, small/double draw up to 18%, full-screen draw up to 43%. The
    cost is mostly the semi-transparent glow; fills cost almost nothing.
    Fewer points (10° steps for the glow only) and fewer, wider glow bands
    brought full screen from 66% to 43%. SC-007 was revised to "worst call
    below 50%" and the user accepted the current look.
- **Renderer reuse (UNVERIFIED):** Create one renderer lazily inside the print
  function and call `:reset()` between shapes, to avoid allocating per frame.
  If the emulator shows it can't be reused across frames, create one per frame
  and re-check the CPU figure.
- **Alternatives considered:** A pre-rendered PNG dial with `lcd.loadImage`
  (fixed size, can't recolor or re-scale); plain `drawLine` segments (jagged
  at this size); a needle as the main indicator (the reference uses a filled
  arc).

## R7. Telemetry windows and sizes

- **Measured sizes** (spec US3 and `docs/jeti-api-notes.md`, firmware 6.04
  emulator, `tools/probe/PROBE.lua`): single 157 × 60, double 157 × 127, full
  screen 320 × 260 (sizes 3 and 4 identical). These replace the earlier
  estimates.
- **Decision:** FR-013 asks for two windows, the most an app may register:
  - Window 1, "Speed Gauge", registered with **size 0**, so the pilot can
    place it at single or double size.
  - Window 2, full screen, registered with **size 4** (no status bar), titled
    "Speed Gauge (full screen)" (changed 2026-10-03, FR-013: two identical
    names couldn't be told apart in Displayed telemetry).
  - **Changed from size 3 after emulator testing (2026-09-27):** on the
    DS-24 II the desktop's model tile is drawn over a size-3 window's
    lower-left quarter. Size 4 has no overlay. DFM-InsP (MIT, studied only)
    also uses size 4.

  One print function serves both. It picks the layout from `(w, h)` on every
  call, so a window moved between sizes adapts on the next draw.
- **Size 0 (UNVERIFIED):** v1.5 lists size 0 as "auto" without saying what it
  does. Quickstart step 1 checks it with a size-0 mode added to `PROBE.lua`.
  - **Fallback** if the pilot can't choose the size: a "Gauge window size"
    setting (Single / Double, key `winSz`). Window 1 is registered at that size
    in `init()`, and unregistered and registered again when the setting
    changes.
- **Layouts** (details in
  [contracts/telemetry-window.md](contracts/telemetry-window.md)):
  - `h < 100` → compact (single, 157 × 60)
  - `w < 250` → round (double, 157 × 127)
  - otherwise → full screen (320 × 260)
- **Alternatives considered:** Separate single and double windows (the
  previous plan). They would use both slots and leave none for full screen.

## R8. Colors

- **Decision:** The dial face is always dark (spec US3), so the colors are
  chosen for a dark background, not for the transmitter's theme. There are
  nine presets. None is red or orange, so none can be confused with the
  overspeed zone (FR-017):

  | # | Name | RGB |
  | --- | --- | --- |
  | 1 | Cyan | 0, 190, 255 |
  | 2 | Blue | 40, 110, 255 |
  | 3 | White | 255, 255, 255 |
  | 4 | Green | 0, 210, 100 |
  | 5 | Lime | 170, 240, 0 |
  | 6 | Magenta | 230, 60, 230 |
  | 7 | Purple | 150, 100, 255 |
  | 8 | Grey | 170, 170, 170 |
  | 9 | Yellow | 255, 225, 0 |

  Defaults: current speed = Cyan, max = Yellow. Yellow was added last so the
  saved index of every earlier color stays the same. Numbers on the face are white;
  labels are light grey.
- **Rationale:** FR-017 asks for at least 6 colors, a blue/cyan arc and a
  bright yellow max marker by default, and no clash with the red/orange zone.
  In emulator testing a thin white marker was too subtle, so the default
  became yellow and the marker thicker (2026-09-27). Yellow is clearly
  lighter than the orange-red zone. Black is
  dropped because it would vanish on the dark face.
- **Unsupported transmitters:** the notice (R12) uses the theme's foreground
  color, since no face is drawn there.

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

- **"Temperature (blank = standard)":** ~~A "Use standard temperature"
  checkbox under the temperature intbox.~~ **Superseded 2026-09-30** by the
  Temperature source selectbox (Standard / Manual / Sensor, FR-038; R15).
  The manual intbox is enabled only for Manual, the sensor selectbox only for
  Sensor. The old `tStd` key is migrated (data-model.md).
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
| 7 | Window: one text line "Calibrated Airspeed" | Round gauge (pilot-sized window + full screen), session max; DS-24 II only | US3, FR-013a |
| 8 | Debug toggled by sensitivity 99/98 | Removed; debug prints only in the emulator | cleanup |
| 9 | Startup stall announcement always | On by default, can be turned off | FR-028 |
| 10 | Switch on only at `== 1` | `> 0.5` (R10) | R10 |
| 11 | No density correction | Optional, airspeed sensors only | US4 |
| 12 | Unused `V_ref_speed.wav`, `Spd_ann_act.wav` shipped | Not copied | cleanup |
| 13 | Normal callouts need *current* speed > Vref/2 | A "Callouts start above" setting (default 30 mph), latched for the session, gating normal and continuous callouts and "airspeed alive" (changed 2026-10-03) | FR-009, US1 #7 |
| 14 | Transmitter voice for numbers, DFM recordings for warnings | One app voice (Amy) for all speech when installed; v2.1 audio as fallback, or by choice | US6, FR-030–FR-037 |
| 15 | No temperature input | Temperature source Standard / Manual / Sensor for density correction | FR-038–FR-044 |

## R12. Unsupported transmitters (FR-013a)

- **Finding:** `system.getDeviceType()` returns the transmitter's name as a
  string (`types/jeti.lua` gives "JETI DC-24" as an example). The exact
  string on a DS-24 II, and in the emulator, isn't documented. `PROBE.lua`
  already prints it to the console.
- **Decision:** In `init()`, set `gaugeOk` once:
  `gaugeOk = string.find(system.getDeviceType() or "", "24 II", 1, true) ~= nil`.
  When `gaugeOk` is false, the print function draws only
  "Speed Gauge needs DS-24 II" in the theme's colors (`FONT_MINI`) and
  returns. The loop, callouts and warnings never check `gaugeOk` (FR-013a).
- **UNVERIFIED:** the device string on the II and in the emulator. Quickstart
  step 1 reads them from the probe's console output. If the II's string
  doesn't contain "24 II", change the match to what it does contain, and
  record the strings in `docs/jeti-api-notes.md`.
- **Alternatives considered:** Detect by window size (the original DS-24
  reports the same window sizes, so the two can't be told apart); detect by
  `lcd.renderer` being present (also true on the original DS-24).

## R13. Generating the voice set (FR-030, FR-034–FR-036)

- **Decision:** `tools/voice/make_voice.py` (Python 3.9+, the version
  installed here) uses the `piper-tts` Python package with the voice model
  `en_US-amy-medium` (Hugging Face `rhasspy/piper-voices`).
  `tools/voice/README.md` says how to install the package and download the
  model; neither is committed. The script:
  1. Builds the phrase list. Numbers 0–500 are spelled as words by the
     script itself, in US style without "and" ("one hundred twelve"), so
     Piper never has to guess how to read digits. The phrases and units are
     listed in the file table below.
  2. Synthesizes each phrase to an in-memory WAV, with Piper's
     `length_scale` as an option (`--speed`, default 1.0; SC-009 allows
     speeding up later).
  3. Trims leading and trailing silence (samples below about −45 dBFS),
     keeping 20 ms at each end so words don't clip.
  4. Normalizes every file to the same peak level (−1 dBFS). Peak, not
     loudness, keeps the script to the standard library (`wave`, `array`);
     with one voice and short phrases the two give near-identical results.
  5. Writes mono 16-bit WAV at `--rate` (default 22050, Amy's native rate,
     so no resampling). `--rate 44100` doubles each sample with linear
     interpolation, for the case where the transmitter won't play 22.05 kHz.
  6. Writes `voice/CREDITS.txt` (FR-036) and then `voice/index.txt`, listing
     the voice, rate and file count. Writing the index last marks a complete
     run.
  7. Self-checks the result: all 512 files exist; reports the longest
     number-only file for 0–199 and exits non-zero if it is over 1.3 s
     (the half of SC-009 that can be checked offline).
- **File names** (in `src/Apps/AG-SpdGa/voice/`, deployed as
  `/Apps/AG-SpdGa/voice/`). Numbers are flat files so a path is one
  concatenation. DFM's long WAV names already work on the card, so 8.3 isn't
  needed for assets:

  | Files | Spoken |
  | --- | --- |
  | `0.wav` … `500.wav` | "zero" … "five hundred" |
  | `mph.wav`, `kmh.wav`, `kt.wav`, `ms.wav`, `fts.wav` | "miles per hour", "kilometers per hour", "knots", "meters per second", "feet per second" |
  | `pct.wav` | "percent" |
  | `stall.wav`, `over.wav`, `alive.wav` | "stall warning", "overspeed", "airspeed alive" |
  | `stallat.wav`, `cal.wav` | "stall warning at", "airspeed calibration" |

  512 files. At 22.05 kHz mono and about 0.9 s average they are about 20 MB,
  somewhat over the spec's 10–15 MB estimate; 16 kHz would bring it to
  about 14 MB. Either is fine on the SD card.
- **Sample rate (UNVERIFIED):** DFM's recordings are 44.1 kHz (three of the
  five stereo), so the transmitter plays 44.1 kHz. Neither 22.05 nor 16 kHz
  is documented. Quickstart step 1 plays one 22.05 kHz file in the emulator
  and on the transmitter. If it doesn't play, regenerate with
  `--rate 44100` and record the finding in `docs/jeti-api-notes.md`. FR-034
  names 16/22.05 kHz, so in that case the spec needs a one-line update.
- **Committed (FR-035, changed 2026-10-03):** first kept out of git
  (`.gitignore`) because of the Amy model's CC BY-SA license and its
  undocumented training data; the user then chose to commit the set. The
  folder is CC BY-SA 4.0, labeled in `CREDITS.md` and the README.
- **Alternatives considered:** Piper's command-line binary (one process per
  phrase, 512 launches, slower); ffmpeg/sox for trimming and normalizing (an
  extra install for two simple operations); one file per number+unit
  combination (2,505 files, about 100 MB, and only SC-009's gap would
  improve); numbers as digits passed to Piper (its reading of "112" depends
  on the version, e.g. "one hundred and twelve").

## R14. Speaking with the app voice (FR-031–FR-033, FR-037)

- **Decision: startup check.** `init()` sets `voiceOk` once. It is true when
  `io.open(path, "r")` succeeds for all 11 phrase and unit files plus
  `0.wav` and `500.wav` (each closed right away). That is 13 opens, once.
  The cost is UNVERIFIED; the start-up CPU figure (24% today) is re-checked
  in quickstart.
- **Which voice:** `useAppVoice = voiceOk and cfg.voice ~= 2` (key `voice`:
  0 = not chosen, 1 = Speed Gauge, 2 = Transmitter). An unset key therefore
  means Speed Gauge when the files are present and Transmitter otherwise
  (FR-032). The form shows that resolved choice.
- **Callout:** when a callout is due (data-model.md) and `useAppVoice`:
  - `n = round(shownSpd)`. If `n > 500`, use the transmitter's
    `playNumber` for this callout (FR-033).
  - Otherwise build the number path `VOICE .. n .. ".wav"` and check it
    with `io.open`/`io.close`. Present: `playFile(numPath, AUDIO_QUEUE)`,
    then, for a full callout, `playFile(unitPath, AUDIO_QUEUE)`. Missing:
    `playNumber` for this callout only. A phrase is never half app voice
    (Edge Cases).
  - The concatenation and the open happen only when a callout is due (at
    most every `tMin`, ≥ 1 s), not per loop. That fits constitution VI's
    intent. Caching all 501 paths would cost about 20 KB of memory to save
    one concatenation per callout.
  - Unit files were checked at startup, so only the number is checked here.
  - The full callout in the app voice is "eighty-five miles per hour", with
    no "Speed" prefix (US6 #1). The transmitter fallback keeps v2.1's
    `playNumber(n, 0, unitSpoken, "Speed")`.
- **Warnings:** `playFile(VOICE .. "stall.wav", AUDIO_IMMEDIATE)` and so on
  when `useAppVoice`, otherwise DFM's file (FR-037). Paths are constants
  built once in `init()`. `voiceOk` already covers these files, so a warning
  is never left silent (FR-033).
- **Startup announcements:** "stall warning at" + number + unit, and
  "airspeed calibration" + number + "percent", queued with `AUDIO_QUEUE`.
  The whole announcement falls back to v2.1's file + `playNumber` if the
  value is over 500 or its number file is missing.
- **FR-007 unchanged:** a callout starts only while `system.isPlayback()` is
  false, and the number and unit files are queued together, so FR-007 treats
  the phrase as one.
- **Gap between queued files (UNVERIFIED, SC-009):** whether the firmware
  adds a pause between two `AUDIO_QUEUE` files is undocumented. The
  generator trims silence, so any gap comes from the firmware. Check by ear
  on the transmitter (quickstart step 4). The Emulator Telemetry app
  replaces `playFile` with `print`, so with it loaded the emulator shows
  which files were queued but plays nothing. The emulator plays no Lua audio
  even without that app (observed 2026-10-03), so listen on the
  transmitter. If the gap
  is audible, the remedies are a faster `--speed` and "Speak number only";
  a per-combination file set (R13 alternatives) stays rejected for size.
- **Does `AUDIO_IMMEDIATE` cut a queued callout? (UNVERIFIED):** same
  behavior as v2.1, which also queued numbers and played warnings
  immediately. Observe it during quickstart scenarios 6 and 8.
- **Alternatives considered:** check every number file at startup (501
  opens in `init()`, likely over the start-up budget); trust `index.txt`
  alone (an interrupted copy to the SD card can still leave holes, Edge
  Cases); a lib module for "speak number + unit from files" (no second user
  yet, R2's rule).

## R15. Temperature from a sensor (FR-038–FR-044)

- **Choosing the sensor (FR-039):** the temperature selectbox is built from
  the same `system.getSensors()` pass as the speed sensor list, when the
  form opens (R4). It keeps entries whose `unit` ends in "C" or "F" and is
  2–3 bytes long: "°C" is 3 bytes in UTF-8 and 2 in Latin-1, and the
  transmitter's encoding of `°` is UNVERIFIED. The emulator's
  `tools/emulator/sensors.json` already has "MSpeed 450 / Temperature" (°C,
  −29..54, control P7). Saved as `tId`, `tPar`, `tLbl`, with the same
  "(not found)" handling as R4.
- **Reading:** `loop()` reads the temperature sensor every 5 s
  (`TEMP_MS = 5000`, FR-041), only while `densOn = 1`, `sType = 1` and
  `tSrc = 3`. It calls `system.getSensorByID(tId, tPar)` (through `system`,
  R3), not the lighter value call, because it needs `unit` to tell °C from
  °F. Once every 5 s, that cost is negligible. A unit ending in "F" is
  converted with `ag_dens.fToC`.
- **Accept, reject, resume (FR-040):** the limits are checked in the unit
  system the user sees (FR-023): −20..130 °F or −29..54 °C. A read is good
  when the entry exists, `valid` is true and the value is within limits.
  - Status `tStat`: 0 not in use (source isn't Sensor, or correction is off
    or GPS); 1 waiting (rejected); 2 in use.
  - In use → waiting on the first bad read. The correction falls back to
    standard at once.
  - Waiting → in use after **two consecutive good reads** (5 s apart), i.e.
    10 s after the last rejected read, which is how FR-040 itself defines
    the wait.
  - **First read after start-up** (or after choosing Sensor): accepted on a
    single good read. Nothing has been rejected yet, so there is nothing to
    flip back from, and the pilot doesn't see "SENSOR OUT" for the first
    10 s of every session.
- **Hysteresis (FR-041):** while in use, `tUseC` (°C) changes only when a
  good read differs from it by ≥ 1 °C. On acceptance `tUseC` is set to that
  read. 1 °C is used for both unit systems; the spec's "(2 °F)" is the same
  step rounded.
- **Applying it:** a change of `tStat` or `tUseC` calls the same
  `recomputeDensity()` the form callbacks use: `kDens`, the dial fractions,
  the cached row texts and a layout-cache refresh. That builds a few
  strings, at most every 5 s and only on change, which fits constitution VI.
  A change in `kDens` alone never triggers a callout (FR-041): callout timing
  reads only `shownSpd` and `lastSpokenSpd`, as now.
- **Warnings unaffected (FR-043):** stall, landing and "airspeed alive"
  compare `sensorSpd`, which doesn't include `kDens` (FR-011).
- **Alternatives considered:** read the value every tick (FR-041 says at
  most every 5 s, and it would cost a sensor call per tick); require 10 s
  of good reads at start-up too (the pilot would see "SENSOR OUT" on every
  power-on); compare limits in °C only (the user would see, for example,
  130 °F rejected at 54.4 °C, which doesn't match the limit they were
  shown).

## R16. Input limits, clamping and migration (FR-020)

- **Decision:** the intboxes use the FR-020 limits: elevation −300..10000 ft
  or −90..3050 m (step 10), manual temperature −20..130 °F or −29..54 °C.
  The default manual temperature stays 59 °F / 15 °C.
- **Clamp on load (Edge Cases):** `loadSettings()` clamps every integer
  setting to its range, not only elevation and temperature, and saves a
  clamped value back so the form and the correction agree. It runs once in
  `init()`. A units change across systems converts elevation and
  temperature, then clamps them (data-model.md).
- **Migration `cfgV` 1 → 2:** `tStd = 1` → `tSrc = 1` (Standard); `tStd = 0` →
  `tSrc = 2` (Manual); then `system.pSave("tStd", nil)`. `cfgV` becomes 2.
  Settings saved by 0.1.0 therefore keep their meaning.
- **Rationale:** the clarification session of 2026-09-30 set the limits.
  Clamping is the spec's stated rule for values saved by an earlier version
  with wider limits.

## R17. Live temperature status in the settings form (FR-042)

- **Finding:** `system.registerForm` takes a `closeFunction`
  (`types/jeti.lua`), so the app can tell when its form is open.
- **Decision:** `initForm` sets `formOpen = true`; the close function clears
  it. When `tStat` or `tUseC` changes while `formOpen`, `loop()` updates the
  temperature status label with `form.setProperties(idxTStat, {label=...})`.
  This is the only `form.*` call outside `initForm` and callbacks, and the
  flag guarantees the form is open (constitution VI).
- **Status texts** (ASCII except `°`, which T039 checks): "Temp: 15 °C
  standard", "Temp: 20 °C manual", "Temp: 35 °C from MSpeed 450", "Sensor
  not available - using standard". The spec's em dash becomes " - "
  because `—` isn't in the supported charset.
- **Alternatives considered:** update the label only when the form is
  reopened (the pilot couldn't watch it change, and FR-042 asks for the
  temperature in use); draw it in a form print function with `lcd` (form
  layout and scrolling make the position unreliable).
