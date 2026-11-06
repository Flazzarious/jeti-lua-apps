# Research: Battery Capacity

**Feature**: `specs/005-battery-capacity/` | **Date**: 2026-11-01

Decisions behind [plan.md](plan.md). Each item: decision, rationale,
alternatives. **UNVERIFIED** marks a fact that only the transmitter or a
bench test can settle; each has a quickstart check and a fallback.

## R1. Capacity sensors and units (Open question 2)

- **Decision:** classify a sensor by its `unit` string when the pilot picks
  it in the settings form (`system.getSensors()`, where labels and units are
  available), and save the result as a capacity mode, so `loop()` only ever
  calls the lighter `getSensorValueByID`:

  | Unit (trimmed, case-sensitive) | Mode | % remaining |
  | --- | --- | --- |
  | `mAh` | 1 mAh consumed | `(rated − value) / rated` |
  | `Ah` | 2 Ah consumed | `(rated − value × 1000) / rated` |
  | `%` | 3 % remaining | `value` |
  | `V` | 4 voltage | resting curve (R3) |
  | anything else | refused | setup note (FR-004) |

  Voltage and current sensors are filtered the same way: `V` for voltage,
  `A` for current (`mA` × 0.001 is also accepted). The list of entries
  offered for each picker contains only sensors whose unit fits, plus
  "(none)" and, if the saved sensor isn't present, "<label> (not found)"
  (Speed Gauge R4).
- **Expected sources** (from general knowledge of these products, not
  checked against manuals in this session; units are what the sensors
  declare in their EX description):
  - JETI MUI 30/75/150/200: `V` voltage, `A` current, `mAh` capacity
    consumed. Capacity resets to 0 at power-on unless the MUI is set to
    remember it.
  - JETI Central Box 200/400: per-battery `V` and `A`, and `mAh` consumed
    per battery.
  - Receiver `U Rx` / `Rx voltage`: **not a sensor on the transmitter**.
    Auto-detect in Sensors/Logging Setup lists nothing for a bare receiver,
    and `getSensors()` has no entry for it (DS-24, 2026-11-05; the emulator's
    `sensors.json` fakes it as a sensor). The app adds three fixed entries,
    "Receiver 1 voltage", "Receiver 2 voltage" and "Backup Rx voltage", at
    the top of the capacity and voltage lists. They are saved as sensor id
    −1 with param 1–3 and read from `system.getTxTelemetry()`
    (`rx1Voltage`, `rx2Voltage`, `rxBVoltage`), at most once per 200 ms
    tick. A reading counts only while that receiver's Q (`rx1Percent`,
    `rx2Percent`, `rxBPercent`) is above 0: after a link loss the voltage
    keeps its last value but Q drops to 0 (DS-24 II, PROBE MODE 7,
    2026-11-05). The receiver's Q (%) isn't a sensor
    either, so it can't be picked as a capacity % by mistake.
  - ESC telemetry (YGE, Castle via adaptor, Hobbywing via VSpeak): `V`, `A`,
    `mAh`; some also expose `%` (fuel-gauge style).
  - Powerbox Mercury/Royal/Competition (via the EX bus adaptor): battery
    `V` and `mAh` per pack.
- **UNVERIFIED:** units, decimals and power-up behaviour of Aaron's own
  sensors. Quickstart step T1 lists each sensor's unit with
  `tools/probe/PROBE.lua` (or the settings form's sensor list) and records
  them in `docs/jeti-api-notes.md`. An unrecognised unit is a one-line
  addition to the table above.
- **Alternatives considered:** ask the pilot to choose the mode (a question
  most can't answer; the unit already says it); read the unit in `loop()`
  with `getSensorByID` (heavier, and unnecessary once the mode is saved).

## R2. Update cadence (FR-014, Open question 5)

- **Decision:** two cadences in `loop()`, both driven by
  `system.getTimeCounter()`:
  - **Fast tick, 200 ms:** read every assigned sensor of every battery
    (at most 12 `getSensorValueByID` calls), update validity, the
    low-voltage and current-alarm timers, and the max-current filter (R7).
  - **Slow tick, 1 s (FR-014, tunable constant `SLOW_MS`):** compute
    % remaining, colour band, callout levels, new-pack detection and
    rebuild the cached display strings that changed. The callout scheduler
    (R9) also runs here and whenever playback ends.
- **Rationale:** the max-current spike rule needs distinct consecutive
  readings, which a 1 s sample would miss, and SC-008/SC-009's
  "delay + 1 update interval" is easier to meet with 200 ms timing. Capacity
  moves slowly, so 1 s is plenty for the gauge and keeps string building
  to once a second at most (constitution VI).
- **Cost:** sensor reads are light; Speed Gauge's loop measured 0–1% with a
  100 ms tick. Four batteries are re-measured with `DEBUG_CPU` (quickstart
  E8).
- **Alternatives considered:** everything at 1 s (misses spikes and
  coarsens the alarm delays); everything every loop (wasteful, 20–30 ms).

## R3. Voltage-to-% curves and smoothing (FR-004, SC-004, Open question 4)

- **Decision:** one fixed **resting** (open-circuit) curve per chemistry,
  11 points per cell from 100% to 0% in 10% steps, linear interpolation
  between points, clamped to 0–100. Pack voltage is divided by the cell
  count first. Values in volts per cell:

  | % | LiPo | LiHV | Li-ion | LiFe | NiMH/NiCd |
  | --- | --- | --- | --- | --- | --- |
  | 100 | 4.20 | 4.35 | 4.20 | 3.40 | 1.40 |
  | 90 | 4.11 | 4.25 | 4.08 | 3.34 | 1.33 |
  | 80 | 4.02 | 4.16 | 3.98 | 3.32 | 1.30 |
  | 70 | 3.95 | 4.08 | 3.89 | 3.31 | 1.28 |
  | 60 | 3.87 | 4.00 | 3.81 | 3.30 | 1.27 |
  | 50 | 3.84 | 3.95 | 3.74 | 3.29 | 1.26 |
  | 40 | 3.80 | 3.90 | 3.67 | 3.27 | 1.25 |
  | 30 | 3.77 | 3.86 | 3.61 | 3.25 | 1.23 |
  | 20 | 3.73 | 3.81 | 3.55 | 3.22 | 1.21 |
  | 10 | 3.69 | 3.75 | 3.45 | 3.15 | 1.17 |
  | 0 | 3.50 | 3.50 | 3.20 | 3.00 | 1.10 |

  Stored as integers in centivolts in a constant table.
- **The LiFe and NiMH "Full" values in FR-006 are charge voltages, not
  resting voltages.** A LiFe pack rests at about 3.35–3.40 V/cell within
  minutes of charging, not 3.60. The curve therefore tops out at the
  resting value, and FR-006's Full voltage is used only as the upper bound
  of the cell-count check (R11), never as the 100% point. Otherwise every
  fresh LiFe pack would read about 70% and trigger "pack not full".
- **Cutoff** (FR-006) is the 0% floor: a reading at or below Cutoff shows
  0% even where the curve's own 0% point is lower. **Nominal** has no
  function in the gauge or alarms; it is shown in the settings for
  reference and kept editable so FR-006/FR-008 hold.
- **Smoothing:** voltages read on the fast tick are averaged over each 1 s
  slow tick, then passed through a one-pole filter with a 10 s time
  constant (`α = 0.1` per second). The first reading of a pack session
  initialises the filter directly, so the gauge doesn't climb from 0.
- **Load compensation:** when the battery has a current sensor and current
  is above `max(1 A, rated mAh / 10 000 A)` (0.1 C), voltage-mode % is held
  at its last value instead of updated (it would read low under load). With
  no current sensor, the smoothing and callout hysteresis (5 points) carry
  the sag. The README explains that a voltage-only gauge is a resting
  estimate.
- **UNVERIFIED (SC-004):** the table values are typical published hobby
  figures (LiPo/LiHV from common RC charger tables; LiFe A123-style cells;
  Li-ion NMC 18650; NiMH Eneloop-style), not measurements of Aaron's packs.
  Quickstart B1 bench-checks a LiPo and a LiFe pack at rest against a
  charger's reported state; a table entry is a one-line change. LiFe and
  NiMH are flat between about 20% and 90%, so ±10% there is not expected
  (spec Assumptions, 2026-11-01).
- **Alternatives considered:** a per-pack linear map from Cutoff to Full
  (badly wrong for flat chemistries); a pilot-editable curve (too many
  settings for the 30-key budget, and few pilots have the data).

## R4. New-pack and brown-out detection (FR-028, Open question 6)

- **Decision:** per battery, a three-state telemetry tracker: `NONE` (never
  seen this app run), `LIVE`, `LOST` (was live, now invalid).
  - `LIVE → LOST` when the capacity source has been invalid (`valid ==
    false` or `nil`) for **1 s** (5 fast ticks). Shorter gaps are ignored
    and the last value is held.
  - `LOST → LIVE`: after the first good 1 s slow tick, compare the new %
    with the last % held before the loss. **New pack** when it is at least
    20 points higher and, if a voltage reading exists for the battery and
    the capacity source isn't voltage, the voltage estimate (R3, unsmoothed)
    is also 20 points higher than before. Otherwise **brown-out**: callout
    state, low-voltage state, session max and the new-pack check flag are
    kept.
  - `NONE → LIVE` starts a pack session (app start counts as a new pack).
- **New pack** resets, for that battery only: fired callout levels (then
  re-armed from the current %, US2 #4 rule), repeat counters, low-voltage
  state, the max-current filter and last announced max (FR-027), and
  schedules the new-pack check (FR-029) 3 s later.
- **mAh-consumed sensors that reset to 0 at power-on** look like a full
  pack after every brown-out. That is exactly the case where the voltage
  cross-check matters; without a voltage reading the app can't tell, as the
  spec's edge case says, and the README recommends assigning one.
- **UNVERIFIED:** the 1 s dropout and 20-point thresholds on real packs.
  Both are constants (`LOST_MS`, `NEWPACK_PTS`). Quickstart T5 swaps a pack
  and pulls the receiver plug briefly.
- **Alternatives considered:** detect by voltage alone (fails for % and
  mAh-only sensors); detect by time off (a quick swap takes 20 s, a
  brown-out under 1 s, but a long brown-out exists too).

## R5. Persistence layout (FR-005, Open question 7, constitution IV)

- **Decision:** 18 `pSave` keys: six app keys and three per battery slot (16 at plan time; the window titles, FR-009a, added 2 on 2026-11-01).

  | Key | Type | Content |
  | --- | --- | --- |
  | `cfgV` | int | settings version, 1 |
  | `voice` | int | 0 unset, 1 app voice, 2 transmitter (Speed Gauge R14) |
  | `numOnly` | int | "Speak number only" 0/1 |
  | `smallB` | int | battery shown in the small window, 1–4 |
  | `title1`, `title2` | string | window titles (FR-009a, added 2026-11-01; 18 keys in all) |
  | `b1p` … `b4p` | int array (20) | pack: category, label number, chemistry, cells, mAh, three sensors, voltages, bands, edited mask |
  | `b1a` … `b4a` | int array (18) | alarms: levels, repeat, low voltage, current alarm, max callout, new-pack check, show-all |
  | `b1s` … `b4s` | string array (5) | custom name, voice-name file, three sensor labels |

  Field-by-field layout in [data-model.md](data-model.md). Every array is
  well under the 32-element limit, with room for later fields at the end.
- **Battery order** is slot order. Deleting battery *k* moves slots *k+1…4*
  down one and saves all affected keys; `smallB` follows its battery.
  Empty slots are saved as `nil` (deletes the key).
- **Floats** are scaled: voltages in centivolts (4.20 V → 420; a 14S LiHV
  pack at 60.9 V → 6 090, inside the intbox range), delays in tenths of a
  second, current in whole amps.
- **Category list growth (FR-002):** categories are saved by a fixed id,
  not a list index. New categories get new ids at the end; the display
  order is a separate table.
- **Alternatives considered:** one key per setting (about 130 keys, far over
  30); a JSON file per model (works, but `pSave` is the constitution's
  required store and survives model copies with the model).

## R6. Label width (FR-003, SC-013)

- **Finding:** the four-battery slot is 150 / 4 = 37 px wide. In `FONT_MINI`
  (12 px high on the transmitter) capitals are roughly 6–7 Lua px wide, so
  "BRAKES-2" or "LIGHTS-2" (8 characters) need about 50 px and probably do
  **not** fit, while "RX-2", "ECU", "GEAR-2", "AUX-3" do. **Measured
  2026-11-04** (transmitter, `Screen034.png`): capitals 2–7 px, digits 4;
  "FLIGHT-2" 38, "BRAKES-2" 40, "LIGHTS-2" 38 do not fit 35 px, so they
  use FLT-2, BRK-2, LGT-2; the unnumbered words (31–34 px) fit. Single
  characters read rounded down, so the check adds 0.6 px per character
  (`docs/jeti-api-notes.md`).
- **Decision:**
  1. First implementation task: measure `lcd.getTextWidth(FONT_MINI, c)`
     for `A–Z`, `0–9`, `-` and space on the transmitter with a probe mode,
     and store the widths as a constant table (`MINI_W`). Text drawn at the
     panel's resolution keeps the same advance in Lua coordinates, so the
     table holds for drawing.
  2. A label fits when `sum(MINI_W) ≤ SLOT_W − 2`. The label may be wider
     than the battery body (26 px), centred on its slot.
  3. If a default label with its number doesn't fit, the category uses a
     short default instead, defined next to the category: Brakes "BRK",
     Lights "LGT", Flight "FLT" (FR-003 and the spec's Terms, updated
     2026-11-01).
- **The label editor can't refuse characters as they're typed:**
  `form.addTextbox` only reports the finished text through its callback,
  and `lcd` isn't available in form callbacks. So the callback measures the
  new text with `MINI_W`, trims characters from the end until it fits, saves
  that, and shows "Shortened to fit" under the box for that form session.
  Characters without a measured width count as the widest capital. This is
  the closest the API allows; FR-003 and the "Custom name too long" edge
  case were updated to match on 2026-11-01.
- **Alternatives considered:** a fixed character limit (4 characters would
  fit all widths but cut "GEAR-2"; 6 would let "WWWWWW" overflow);
  measuring in the form's print function (allowed there, but the result
  arrives a frame later and needs `form.setValue` from print, which is
  fragile).

## R7. Max current: reuse Speed Gauge's spike rule (FR-025–FR-027)

- **Decision:** a new shared module `src/Apps/lib/ag_peak.lua` holding Speed
  Gauge's R5 rule as a pure function over a state table the app owns:
  `peak.new()` returns `{ max = 0, prev = nil, prevT = 0 }`;
  `peak.update(st, value, nowMs)` applies "two distinct readings in a row
  (the lower one) or unchanged for 1 s" and returns the new max;
  `peak.reset(st)`. No module-level state (constitution VII).
- **Callout:** per battery, `lastAnnounced` and `riseT` (time the max last
  rose). On the slow tick: if the max is on and `now − riseT ≥ 1000` and
  `max − lastAnnounced ≥ sensitivity`, queue "max" (R9) and set
  `lastAnnounced = max` when it is spoken. The first max of a session is
  announced once it reaches the sensitivity (as Speed Gauge).
- **Speed Gauge is not changed in this feature.** It keeps its own copy of
  the rule; moving it onto `ag_peak` is a separate change that must
  re-verify Speed Gauge (constitution VII), noted in the plan as a follow-up.
  This feature therefore adds a module with one user and no effect on other
  apps.
- **Rationale:** the constitution asks for shared code in `lib` rather than
  a second copy; Battery Capacity is the rule's second user.
- **Alternatives considered:** copy the ten lines into the app (simplest,
  but exactly the copying VII forbids); migrate Speed Gauge now (widens this
  feature's test scope to a released app for no user-visible gain).

## R8. Voice files (FR-030, FR-035)

- **Decision:** a new generator `tools/voice/make_batcap.py`, copied from
  `make_turbine.py`'s structure, writing to `src/Apps/AG-BatCp/voice/`:
  - **Numbers `0.wav` … `500.wav` are copied byte-for-byte from Speed
    Gauge's committed set** (`src/Apps/AG-SpdGa/voice/`) rather than
    re-synthesised. They are then guaranteed identical in voice, pace (1.5)
    and level, and Piper's run-to-run variation can't creep in. The copy
    keeps Battery Capacity standalone on the SD card (FR-037).
  - **Words** are synthesised with Speed Gauge's helpers and pace (speed
    1.5, 22.05 kHz mono, trimmed, −1 dBFS):

    | File | Spoken |
    | --- | --- |
    | `pct.wav` | "percent" |
    | `amps.wav` | "amps" |
    | `volts.wav` | "volts" |
    | `vpc.wav` | "volts per cell" |
    | `point.wav` | "point" |
    | `max.wav` | "max" |
    | `hicur.wav` | "high current" |
    | `lowv.wav` | "low voltage" |
    | `notfull.wav` | "pack not full" |
    | `n_flt.wav` | "flight" |
    | `n_rx.wav` | "receiver" |
    | `n_ecu.wav` | "E C U" |
    | `n_lgt.wav` | "lights" |
    | `n_brk.wav` | "brakes" |
    | `n_gear.wav` | "landing gear" |
    | `n_aux.wav` | "aux" |
    | `n_bat.wav` | "battery" (Custom) |

  - Writes `CREDITS.txt` and `index.txt` (last, marks a complete run);
    self-check: 518 files, each word file under 1.3 s.
- **Size:** about 20 MB, the same as Speed Gauge's set (spec accepts ~23 MB).
- **Numbered packs** speak the category name then the number file ("receiver"
  + `2.wav`).
- **Alternatives considered:** share Speed Gauge's folder at runtime (breaks
  FR-037's standalone install); one file per name+number ("receiver two")
  (more files for no clear gain; the queue gap is checked on the
  transmitter anyway).

## R9. Callout scheduler and phrase building (FR-031, FR-033, FR-034, FR-034a)

- **Decision:** no queue table. Each battery has a small set of **pending
  flags**, one per callout kind, with the value to speak stored alongside
  (`pendLv`, `pendCur`, `pendLvl`, `pendNp`, `pendMax`). Raising a flag
  that's already raised just updates its value, so nothing queues twice and
  a newer max replaces an older one (FR-034a). A reset clears the max flag.
- **Dispatch:** on each slow tick, and on the first fast tick after
  `system.isPlayback()` turns false, if nothing is playing: scan kinds in
  FR-034a order (low voltage, high current, capacity level, pack not full,
  max), and within each kind batteries 1→4; speak the first raised flag,
  clear it, record its start time for repeat timing. One phrase per dispatch,
  so Flameout Alarm's `AUDIO_IMMEDIATE` alarm or another app's speech gets
  in between (FR-034).
- **Repeats** (FR-018, FR-021, FR-024) are timers that raise the flag again
  `interval` after the previous start (start to start). If the app is still
  waiting for playback to end, the flag simply stays raised: no build-up.
- **Phrase, app voice** (`playFile(path, AUDIO_QUEUE)` for each part):
  `name [+ number]` → event word(s) → number(s) → unit (unit omitted with
  "Speak number only"). Examples: `n_rx 2 · 30 · pct`;
  `n_flt · lowv · 3 · point · 5 · 8 · vpc`; `n_flt · max · 92 · amps`.
  Paths are built only at dispatch (at most one phrase per second), and the
  number file is checked with `io.open` at that point (Speed Gauge R14).
- **Fallback (FR-033, clarified 2026-11-01):** if the app voice isn't in
  use, a number is over 500, or a file is missing, the whole phrase goes to
  the transmitter: `playFile(voiceName, AUDIO_QUEUE)` if the battery has a
  voice-name file, then `system.playNumber(value, decimals, unit)` with
  unit `"%"`, `"V"` or `"A"`. The event words aren't available in the
  transmitter's voice; the unit tells the kinds apart.
- **UNVERIFIED:** that `playNumber` waits behind a queued `playFile`
  (rather than cutting it off or playing over it). Quickstart T3. Fallback:
  dispatch the name file, then speak the number on the next dispatch after
  `isPlayback()` clears (the pair is then never split by another of this
  app's callouts, because the number is raised as a "continuation" flag
  with top priority).
- **Startup voice check** (`init()`): `io.open` the 17 word files plus
  `0.wav` and `500.wav`, absolute path then relative (emulator), close
  each. `voiceOk` false → settings shows "voice files missing" and the
  transmitter's voice is used (FR-032, FR-033).

## R10. Drawing the gauges (FR-010–FR-013, FR-022, Open question 1)

- **Decision: draw at runtime, no PNG shells.** Each battery is an outline
  (`lcd.drawRectangle` with radius 2), a cap (`drawFilledRectangle`), the
  fill (`drawFilledRectangle` in the band colour) and up to three texts.
  That's about 6–8 opaque calls per battery, about 30 for the double window:
  the cheap kind of drawing (Flameout's 12 polygons + 12 outlines measured
  5–6%). The same code draws both orientations with swapped axes.
- **Colours (FR-012a, FR-012b):** the outline, cap, label and value text use
  a neutral grey chosen from `lcd.getBgColor()`'s brightness (30,30,30 on a
  light background, 235,235,235 on a dark one). Changed 2026-11-04: on the
  DS-24 II `lcd.getFgColor()` returns the theme's accent colour (green in
  the dark theme, salmon red in the light one, `Screen035/036`), and red
  outlines looked like the low-voltage flash. The empty part is left undrawn so the theme's
  background shows. Band fills are fixed RGB. Text on a fill uses white on
  green, orange and red, dark (`#412402`) on yellow (FR-013). Grey for lost
  telemetry is the foreground colour at alpha 100.
- **Text straddling the fill edge (FR-013, edge case):** the % text is
  drawn twice with clipping: once in the fill's text colour clipped to the
  filled rectangle, once in the theme colour clipped to the empty part.
  `lcd.setClipping` moves the origin (API notes), so coordinates are offset
  by the clip corner. Four extra calls per battery. **UNVERIFIED** cost and
  look; fallback is a single colour chosen by whether the fill covers more
  than half the text height.
- **Low-voltage flash:** outline drawn red when
  `(system.getTimeCounter() // 500) % 2 == 0`, theme colour otherwise
  (about 1 Hz, FR-022), in both windows.
- **Pixel rounding (FR-012, SC-006):** fill length `= (inner × pct + 50) //
  100` with integer maths.
- **Layout numbers** (Lua px, transmitter) are in
  [contracts/telemetry-window.md](contracts/telemetry-window.md); all are
  constants, tuned on the transmitter with screenshots.
- **Supported transmitters:** `gaugeOk` from `system.getDeviceType()`
  containing "24": the DS/DC-24 II and the first version. Changed
  2026-11-05 from Speed Gauge's "24 II" (R12) after the first-version DS-24
  measured 151 × 24 / 151 × 69, the same layout space. Elsewhere the window
  shows "Gauges need a DS/DC-24" (the old "Battery Capacity needs DS-24 II"
  was cut off at "needs DS-24" on the first version); callouts still work.
- **Alternatives considered:** PNG battery shells (would need four images
  per size and orientation, and couldn't follow the theme colour);
  `lcd.renderer` polygons (unnecessary for rectangles).

## R11. Setup checks (edge cases)

- **Cell-count check:** when the settings form is open and a voltage
  reading is valid, compare `v / cells` with the chemistry: above Full +
  0.10 V or below Cutoff − 0.30 V shows "Check cell count: reads N.N V"
  under the cells row. Checked every slow tick while `formOpen` (Speed Gauge
  R17's pattern: `form.setProperties` only while the form is open).
- **Ordered levels (FR-016):** each level's callback checks enabled levels
  are strictly descending; if not, the change is reverted to the previous
  value and a note shows "Levels must go down: 60 > 50 > 40 > 30".
- **Current alarm partly set:** a note lists which of threshold, delay,
  repeat is still 0 ("Current alarm off: set delay").
- **Bands:** yellow > orange > red enforced the same way as levels.
- **Overwrite question (FR-008):** changing chemistry, cells or category
  calls `form.question("Overwrite edited values?", ...)` from the
  selectbox callback (allowed: it's a form callback, never `loop()`), only
  if the battery's edited mask has a bit set for a field that change would
  refill. Yes refills all; No refills only unedited fields.

## R12. Settings form shape (FR-001, FR-007, SC-001)

- **Decision:** one form, subforms via `form.reinit(n)`:
  - **1 Main:** list of configured batteries (a link each: label, category,
    chemistry, cells), "Add battery" (hidden at 4), small-window battery,
    Voice, Speak number only, voice status, credits footer.
  - **2–5 Battery 1–4:** essentials first (category, label, chemistry,
    cells, capacity, sensors), then capacity callouts, low voltage, current,
    new-pack check, voice name file, "Show all settings", "Delete battery",
    "Reset max current".
  - "Show all settings" (per battery) reveals the hidden rows of FR-007
    (current alarm for ECU and Lights) plus the advanced rows (bands,
    voltages, repeat and max count, delays, sensitivity). Hidden by default
    so a battery is set up in a handful of rows (SC-001).
- Full row list in [contracts/settings-form.md](contracts/settings-form.md).

## R13. Testing without packs (constitution verification step 3)

- **Emulator sensors:** add to `tools/emulator/sensors.json`:

  | id | Sensor / label | Unit | Range | Control |
  | --- | --- | --- | --- | --- |
  | 4 | MUI 75 / Voltage | V | 6.0–8.6 | P1 |
  | 4 | MUI 75 / Current | A | 0–120 | P2 |
  | 4 | MUI 75 / Capacity | mAh | 0–5 000 | P3 |
  | 5 | Rx / U Rx | V | 5.6–7.0 | P4 |
  | 6 | Central Box / Battery % | % | 0–100 | P9 |

  Control fully down makes a sensor invalid ("lost").
- **SIM mode** (debug constant, off in releases): scripted profiles replace
  sensor reads for battery 1: slow discharge, noisy voltage, sag shorter
  than the delay, current spikes and a held peak, a dropout with a 30-point
  jump (new pack) and with no jump (brown-out). The emulator shows the
  resulting callouts as console lines (the Emulated Telemetry app prints
  `playFile`/`playNumber`).
- **`DEBUG_CPU`:** logs `system.getCPU()` at the end of `loop()` and of each
  print function.

## R14. Stub check (Open question 8)

Every call the design uses is already declared in `types/jeti.lua`:
`system.getSensors`, `getSensorValueByID`, `getTimeCounter`, `isPlayback`,
`playFile`, `playNumber`, `registerForm`, `registerTelemetry`,
`pLoad`/`pSave`, `getDeviceType`, `getCPU`; `form.addLink`, `addLabel`,
`addIntbox`, `addSelectbox`, `addCheckbox`, `addTextbox`,
`addAudioFilebox`, `setProperties`, `setValue`, `reinit`, `question`;
`lcd.getFgColor`, `getBgColor`, `setColor`, `drawRectangle`,
`drawFilledRectangle`, `drawText`, `getTextWidth`, `setClipping`,
`resetClipping`; Jeti `io.open`/`io.close`. No new stubs.
