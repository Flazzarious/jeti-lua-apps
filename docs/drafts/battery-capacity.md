# Draft spec input: Battery Capacity

**Status:** Pre-spec draft v1.19 (2026-10-25, adds battery categories, capacity
callouts, lowest-level repeat and per-category defaults and display orientation, solid 1% fill). Not yet run through Spec Kit.
Visual direction: Aaron's sample image (cylinder cells, green →
yellow → orange → red) is a style reference only. See Open question 1.
**Next step:** iterate this draft, then run `/speckit-specify` with the
*Feature description* below, bring in *Success criteria* and *Edge cases*,
and feed *Open questions / research* to `/speckit-clarify`. Work on its own
`feature/NNN-battery-capacity` branch off `develop`.

Proposed script name: `AG-BatCp.lua` (menu name "Battery Capacity").
8 characters, matching `AG-TrbSt` and `AG-FlmOt`. Confirm the name before
release; constitution V makes filenames permanent.

---

## Feature description (paste into `/speckit-specify`)

Battery Capacity is an in-flight telemetry display app for the Jeti DS-24 II
that shows, at a glance, how much capacity is left in up to four batteries,
with optional current readout and configurable voice alarms.

**Problem.** Receiver packs, auxiliary packs (ECU, smoke pump, lights,
retracts) and electric flight packs all report through different Jeti
telemetry sensors in different forms: mAh consumed, % remaining or only
voltage. Native telemetry windows show raw numbers, one value per window,
with no sense of "how full is this pack" and no chemistry awareness. Pilots
want one clear, attractive gauge per pack that reads the same way no matter
which sensor feeds it.

**Goal.** A high-quality battery gauge for each configured pack, driven by
whatever capacity telemetry the model provides, with chemistry-aware smart
defaults so a new pack is configured in a few selections, and voice alarms
for current draw.

**Scope.**

- Receiver and auxiliary packs (primary target), grouped into battery
  categories (see per-battery configuration).
- Electric flight packs (same features; current display and alarms matter
  most here).
- Up to 4 batteries per model.

**Per-battery configuration (up to 4, saved per model with
`system.pSave` / `system.pLoad`).**

- Category (battery role), picked from a list:
  1. Flight pack
  2. Receiver
  3. Turbine ECU
  4. Lights
  5. Brakes
  6. Landing gear
  7. Aux
  8. Custom (user-named, e.g. "Smoke")

  The list is defined in one table in the code so new categories can be
  added later without changing settings saved on existing models.
- Label shown on the gauge. Defaults from the category ("FLIGHT", "RX",
  "ECU", "LIGHTS", "BRAKES", "GEAR", "AUX", or the custom name), editable.
  Two or more batteries in the same category get numbered labels with a
  hyphen ("RX-1", "RX-2"); the voice says "receiver one", "receiver two".
  Every label, including custom names and numbered labels, must fit above
  the upright battery in the double window with 4 batteries. The label
  editor limits the name to what fits (measured text width at the label
  font; the character limit is set during emulator testing).
- Chemistry: LiPo, LiHV, Li-ion, LiFe (LiFePO4), NiMH/NiCd.
- Cell count (S).
- Rated capacity in mAh.
- Capacity source sensor: any telemetry sensor from `system.getSensors()`.
  The app interprets it by its unit:
  - **mAh consumed** (e.g. MUI-type sensors, Central Box, ESC capacity):
    remaining % = (rated − consumed) / rated.
  - **% remaining** (sensors that report capacity directly): used as is.
  - **Voltage** (packs with no current sensor, typical for receiver packs):
    remaining % estimated from a per-chemistry voltage curve, scaled by cell
    count.
- Voltage sensor (optional): shown numerically and used for cutoff checks
  even when capacity comes from mAh.
- Current sensor (optional): if assigned, current draw is shown numerically
  and current alarms become available. If not assigned, no current is shown.
- Thresholds (smart defaults, all editable, see below):
  - Capacity levels for colour bands: e.g. warning % and critical %.
  - Per-cell voltages: full, nominal, warning, cutoff.
  - Capacity callouts: up to 4 levels in % remaining (see Alarms).
  - Current alarm: one threshold in A per battery, how long it must be
    exceeded, and its repeat interval. No defaults: the user sets them.
  - Low-voltage alarm: threshold and spoken voltage in **per cell** or
    **per pack** mode (see Alarms).
  - New-pack check: on/off and the % threshold (see Alarms).

**Smart defaults.** Choosing chemistry and cell count fills in the voltage
and % thresholds automatically. The user can override any value. Changing
chemistry or cell count later asks before overwriting values the user has
edited. Draft starting values (per cell; to be confirmed, Open question 4):

| Chemistry | Full | Nominal | Warning | Cutoff |
|---|---|---|---|---|
| LiPo | 4.20 | 3.70 | 3.60 | 3.50 |
| LiHV | 4.35 | 3.80 | 3.65 | 3.50 |
| Li-ion | 4.20 | 3.60 | 3.40 | 3.20 |
| LiFe | 3.60 | 3.30 | 3.20 | 3.00 |
| NiMH/NiCd | 1.40 | 1.20 | 1.15 | 1.10 |

**Per-category defaults.** The category picks the default chemistry
suggestion, colour bands, capacity callout levels and whether current
alarms are offered. Chemistry and cell count still set the voltages (table
above). Every value stays editable, and changing the category later asks
before overwriting values the user has edited. The more an empty pack
costs, the earlier the defaults warn. Draft values, to be confirmed
(Open question 4):

| Category | Suggested chemistry | Bands: yellow / orange / red below | Callout slots 1 / 2 / 3 / 4 | Current alarms |
|---|---|---|---|---|
| Flight pack | LiPo | 50 / 30 / 20% | 50 / 40 / 30 / **20%** | Offered |
| Receiver | LiFe | 60 / 45 / 30% | 60 / 50 / 40 / **30%** | Offered |
| Turbine ECU | LiFe | 60 / 45 / 30% | 60 / 50 / 40 / **30%** | Hidden |
| Landing gear | LiFe | 55 / 40 / 30% | 60 / 50 / 40 / **30%** | Offered |
| Brakes | LiFe | 55 / 40 / 30% | 60 / 50 / 40 / **30%** | Offered |
| Lights | LiPo | 40 / 20 / 10% | 40 / 30 / 20 / **10%** | Hidden |
| Aux | LiPo | 50 / 30 / 20% | 50 / 40 / 30 / **20%** | Offered |
| Custom | none (user picks) | 50 / 30 / 20% | 50 / 40 / 30 / **20%** | Offered |

Bold is the lowest slot, the only one on by default in every category.
Receiver and Turbine ECU warn earliest: losing them loses the model or the
engine. Landing gear and Brakes keep a reserve for the landing at the end
of the flight. Lights are non-critical and warn latest. "Hidden" means the
current alarm settings aren't shown unless the user turns on "show all
settings"; it never blocks assigning a current sensor for display. The
per-category defaults live in the same code table as the category list, so
a new category brings its own defaults.

**Display.**

- **Small telemetry window: one battery, lying on its side.** The window
  is wide and short, so the battery is rotated 90° to the right (clockwise):
  terminal cap on the right, base on the left, filling from the left. This makes the battery as large as the
  window allows. The % remaining, name, voltage and (if assigned) current
  go in the space left over; exact placement (inside the cell vs. beside
  it) is iterated on the emulator.
- **Double-size telemetry window: up to 4 batteries standing upright, side
  by side, left-justified.** Like the sample graphics: same size, same
  baseline and cap height, evenly spaced, terminal cap on top, filling
  bottom-up. Batteries start at the left edge in configured order; with
  fewer than 4, each keeps the same width and position it would have with
  4, and the unused space stays empty on the right.
  - **% remaining is overlaid inside the battery, bottom-justified**:
    centred horizontally, sitting just above the bottom of the cell. Text
    colour is picked for contrast with what's behind it (e.g. dark text on
    yellow, white on green, orange and red, and on the background at very
    low %).
  - **Label above the battery**: centred over the terminal cap, outside
    the battery, in the normal window text colour.
  - **Below each battery:** only the current draw in A, shown when a
    current sensor is assigned and reporting. With no current sensor, the
    line stays blank.
  - Voltage is shown only if space allows (to be tested).
- **Solid fill, 1% resolution.** Each gauge is one solid bar, not
  segments: the filled part is a single solid block in the level-band
  colour, and the empty part is left undrawn, so it shows the telemetry window's own
  background colour (whatever the transmitter's display theme uses) inside
  the battery outline. The
  fill boundary moves in 1% steps (0–100), so the bar length matches %
  remaining exactly, rounded to the nearest pixel. Where a battery is
  shorter than 100 px, neighbouring % values can land on the same pixel;
  the large % text always shows the exact value.
- The whole fill changes colour when % crosses a band boundary (one colour
  per battery at a time, as in the sample).
- The same artwork is used in both orientations (rotated for the small
  window), so both views look like one app.
- Layout, battery size, fonts and spacing for 1–4 batteries are expected to
  be iterated on the emulator and transmitter until it looks right.
- Values update once per second to start (tunable). Drawing reuses the last
  computed values so the draw callback stays cheap.

**Alarms.**

- **Current alarm** (v1): one threshold per battery. When current stays
  above it for the set time, "[category], high current, 85 amps" plays,
  repeating at the set interval while it persists. There are **no default
  values**: the threshold, delay and repeat interval are blank on a new
  battery, and the alarm stays off until the user sets all three.
- **Max current callout** (mirrors Speed Gauge's session max speed:
  `specs/001-speed-gauge/spec.md` FR-019/FR-019a and research R5). For any
  battery with a current sensor:
  - **Session max.** The app tracks the highest current reached this
    session. A session runs from app start (transmitter power-on, model load
    or app restart) until the next one, as in Speed Gauge. It resets at the
    start of each session, from a "Reset max current" settings entry, and
    **when a new pack is detected** on that battery (see below). It is not
    saved between sessions. No on-demand "speak max" switch in v1.
  - **New pack detection.** Electric pilots swap packs without restarting
    the transmitter, so a new pack starts a fresh max for that battery
    (and re-arms its capacity callouts). A new pack is detected when the
    capacity telemetry has dropped out (receiver powered off for the swap)
    and comes back with % remaining at least 20 points higher than before
    the gap. Where a voltage reading is available, the voltage-based %
    estimate must also be at least 20 points higher than before the gap
    (so a swap to a partly charged pack still counts, and the new-pack
    check can warn about it); otherwise it is treated as a brown-out and
    the last values are held.
  - **Spike rejection (Speed Gauge R5).** A reading only raises the max once
    it is confirmed: two distinct readings in a row (candidate = the lower of
    the two), or a reading unchanged for 1 s. A single-sample spike never
    counts; a real peak registers about one sample late.
  - **Callout.** A new session max is spoken ("max current" + number +
    "amps", e.g. "max current 92 amps") once it hasn't risen for **1 s**,
    if it beats the last announced max by at least the **max callout
    sensitivity** (in A, default 5 A, editable). Small creeps don't repeat
    it. Callouts never overlap another callout from this app.
  - **Gating.** An optional on/off switch, like Speed Gauge's. With no
    switch assigned, max callouts follow the per-battery enable setting.
  - **"Speak number only"** option, as in Speed Gauge: drops the unit
    ("flight, max 92"). The pack name is always spoken first.
  - **Defaults by category:** max callouts **on** for Flight packs, **off**
    for every other category (still available wherever a current sensor is
    assigned).
  - **Display:** the session max is shown as a number next to current draw
    (e.g. "92 A max") in the small window; on the double window, space
    permitting (to be tested).
- **Capacity callouts.** Each battery has 4 callout slots, each set to a %
  remaining level and switched on or off, so a pack can have 0–4 active
  callouts. Smart defaults fill all 4 levels from the battery's category
  (see Per-category defaults); slots 1–3 are off and only the lowest
  (slot 4) is on.

  - A callout plays once when % remaining falls through its level (e.g.
    "Receiver, 20 percent"; wording depends on Open questions 7 and 12).
  - Each level fires at most once per pack session. It only re-arms after
    % remaining rises a hysteresis margin above the level (default 5%,
    e.g. a fresh pack), so voltage-based readings bouncing around a level
    don't repeat the callout.
  - Levels must be strictly descending among enabled slots; setup blocks
    duplicates or out-of-order values and explains why.
  - If several levels are crossed at once (e.g. power-up on a half-empty
    pack, or a sensor jump), only the lowest crossed level is called out.
  - Turning all 4 off is allowed; the gauge still shows colours.
  - **Lowest-level repeat.** The lowest enabled level (normally slot 4)
    keeps repeating after it first fires:
    - Repeat interval: configurable, default **5 s**, range 3–60 s,
      measured callout start to callout start.
    - Max callouts: optional, default **off** (repeats with no limit);
      when set, 1–20 callouts in total including the first one.
    - Repeating stops when the max count is reached, when % remaining
      rises the hysteresis margin back above the level (fresh pack), or
      when the capacity sensor is lost (the "telemetry lost" indication
      takes over).
    - Higher levels always play once only.
    - These repeat defaults are the same for every category.
- **Low-voltage alarm** (v1). For any battery with a voltage reading (a
  voltage sensor, or a voltage capacity source):
  - **Mode: per cell / per pack** (per battery, default per cell). Per
    cell compares pack voltage ÷ cell count with the per-cell **Warning**
    voltage; per pack compares the pack voltage with a pack threshold
    (default = per-cell Warning × cell count). Switching mode converts the
    threshold, it doesn't reinterpret it.
  - Fires when the voltage stays below the threshold for the alarm delay
    (default 2 s, so short sag under load doesn't trigger it). Default
    **on** wherever voltage is available.
  - **Callout speaks the voltage with decimals**, in the chosen mode:
    "[category], low voltage, 3 point 4 5 volts per cell" (2 decimals) or
    "[category], low voltage, 6 point 9 volts" (1 decimal). In the app
    voice this is the whole-number file, "point", then one digit file per
    decimal; the transmitter fallback is `system.playNumber` with the same
    decimals and "V". The voltage is the value at callout time. Repeats on the
    same interval and optional max count as the lowest capacity callout
    (default 5 s, no limit). Repeating stops when voltage per cell recovers
    0.05 V above the threshold for the alarm delay, or a new pack is
    detected.
  - **Visual:** the battery outline flashes red (about 1 Hz) in both
    windows while the alarm is active, and stays flashing until voltage
    recovers or a new pack is detected. The flash timing comes from the
    system clock in the draw callback, not the 1 s data update, so it
    stays smooth.
  - There is no key press to silence any callout (decided 2026-10-25).
- **New-pack check** (optional, per battery, default **off**). **3 s** after a
  pack is first seen (at power-up, or when a new pack is detected), so
  the resting voltage has settled, if its
  estimated % remaining is below **90%** (editable), the app says once
  "[category], pack not full, 82 percent". It never repeats for that pack.
  The estimate comes from resting voltage and the chemistry curve, since
  an mAh-consumed sensor always starts at 100%; the check needs a voltage
  reading and is hidden for batteries without one.
- A battery with no sensor assigned never produces alarms.

**Voice** (matches Speed Gauge, `specs/001-speed-gauge/spec.md` User Story
6, FR-030–FR-037 and `contracts/audio-events.md`).

- **One app voice for all speech:** Piper US English "Amy", the same model
  and settings as Speed Gauge (normal pace, not Flameout's urgent
  delivery). Each word or phrase is a separate pre-generated file in
  `/Apps/AG-BatCp/voice/`:
  - whole numbers **0–500** (covers % and amps);
  - units: "percent", "amps", "volts", "volts per cell";
  - "point" for decimals (the digits after it reuse the 0–9 files);
  - phrases: "max", "high current", "low voltage", "pack not full",
    "telemetry lost", "battery";
  - one name per category: "flight", "receiver", "E C U", "lights",
    "brakes", "landing gear", "aux". A Custom category speaks "battery".
- **Callouts are built from queued files** that play as one phrase, like
  Speed Gauge's number + unit (FR-031): [category name] + number + unit,
  e.g. "receiver, 30 percent", "flight, max 92 amps", "flight, high
  current, 85 amps". Every callout always starts with the pack name
  (category, plus its number when numbered, e.g. "receiver two"), even
  with only one battery configured.
- **"Speak number only"** drops the unit, as in Speed Gauge (FR-008,
  FR-019a).
- **Voice setting:** "Voice: Battery Capacity / Transmitter". Default is the
  app voice when its files are present, otherwise Transmitter (FR-032).
- **Startup check and fallback** (FR-033): at startup the app checks the
  voice files and shows "voice files missing" in settings if any are
  absent. Any callout it can't fully speak in the app voice (a missing
  file, or a number above 500) is spoken by the transmitter's voice with
  `system.playNumber` (number + unit). A fallback never silences a
  callout.
- **Timing** (FR-007): a new callout never starts while one is playing
  (`system.isPlayback()`); all files go on `AUDIO_QUEUE`, so this app never
  cuts off another app. Flameout Alarm plays immediately and wins.
- **File check cost** (Speed Gauge research R14): file paths are built and
  checked only when a callout is due, never every loop.
- **Generation and licensing** (FR-034–FR-036): generated by the repo's
  `tools/voice/` script from the same Amy model, extended with an AG-BatCp
  phrase list; mono, 16-bit, 16 or 22.05 kHz, silence trimmed, normalized
  to Speed Gauge's loudness. Committed to `src/Apps/AG-BatCp/voice/` like
  Speed Gauge's set, licensed CC BY-SA 4.0, with a `CREDITS.txt` in the
  folder and entries in `CREDITS.md` and the README.
- **Standalone:** the app ships its own copy of the number files rather
  than reading Speed Gauge's folder (constitution: no dependency on other
  AG- apps). Expect a set of about 515 files, similar in size to Speed
  Gauge's (about 23 MB).

**Constraints.**

- Advisory only. The app never drives any output: never calls
  `system.registerControl`, `system.setControl` or `system.setProperty`
  (constitution I). It reads telemetry, draws and plays sound.
- It does not replace native telemetry alarms on a receiver pack; the README
  must say so.
- Low CPU: no heavy work in the draw callback; computation at most once per
  update interval in `loop()`.
- Standalone install: `AG-BatCp.lua` plus its own `AG-BatCp/` folder (audio
  and any image assets). No dependency on other AG- apps. Any shared
  `src/Apps/lib/` module must be listed in the plan, install instructions and
  release package.
- All settings persist per model.

---

## Success criteria

- **SC-001.** A pilot can configure a battery (chemistry, cells, capacity,
  sensor) in under 2 minutes, and all 4 in under 6, without a manual.
- **SC-002.** Selecting chemistry and cell count fills in every threshold
  with the documented default for that combination in 100% of cases.
- **SC-003.** Displayed % remaining matches the computed value from the
  sensor (mAh or %) within ±1%, in emulator and on the DS-24 II.
- **SC-004.** For voltage-only packs, the estimated % stays within ±10% of
  the true state of charge at rest, across the chemistry's range (validated
  against bench measurements).
- **SC-005.** The double window shows 1–4 upright, left-justified batteries,
  and the small window one battery on its side, with % remaining and name
  readable at arm's length outdoors (Aaron's sign-off on the emulator and
  transmitter).
- **SC-006.** A current alarm fires within (alarm delay + 1 update interval)
  of current exceeding the threshold in 100% of emulated runs, and never
  fires while current is below it.
- **SC-007.** Batteries without a sensor, or with no current sensor, produce
  zero alarms in any scenario.
- **SC-008.** No "CPU limit" errors over a 30-minute emulator session with 4
  batteries configured and both windows shown.
- **SC-009.** Settings for each model survive a transmitter restart and do
  not leak to other models.
- **SC-010.** The app never changes any transmitter output or setting
  (servo outputs and model file unchanged after a session with no user edits).
- **SC-011.** Copying only the app's files (plus any listed lib modules) to
  `/Apps` on a transmitter with no other AG- apps is enough to load and run.
- **SC-012.** A new battery has its colour bands and 4 capacity callout
  levels filled with the documented defaults for its category, with only
  the lowest callout switched on, in 100% of cases for every category.
- **SC-013.** Each enabled capacity callout first plays when % remaining
  crosses below its level, within 1 update interval. Levels above the
  lowest enabled one play exactly once and never repeat while the reading
  stays within the hysteresis margin, in 100% of
  emulated discharge profiles (including noisy voltage-based profiles).
- **SC-014.** Once the lowest enabled level fires, the callout repeats
  every configured interval (±0.5 s) and, if a max count is set, stops after
  exactly that many callouts, in 100% of emulated runs.
- **SC-015.** The fill is solid (no segments) and its length tracks %
  remaining in 1% steps, within ±1 pixel of the exact proportion, in both
  windows.
- **SC-016.** With a current sensor assigned, the spoken and displayed max
  current equals the highest confirmed reading (Speed Gauge R5 rule) in
  100% of emulated flight profiles. A single-sample spike never becomes the
  max. A new max is spoken within 1 s (+ one update interval) of it
  stopping rising, only if it beats the last announced max by the
  sensitivity.
- **SC-017.** The low-voltage alarm fires within (alarm delay + 1 update
  interval) of voltage per cell staying below the threshold, never fires
  for sag shorter than the delay, and flashes the battery outline red in
  both windows while active, in 100% of emulated runs.
- **SC-018.** The new-pack check is off on a new battery. With it on, a pack estimated below the
  threshold produces exactly one "pack not full" callout per pack, and a
  pack at or above it produces none, in 100% of tests.
- **SC-019.** Every label (category, numbered or custom) fits above its
  battery in the 4-battery double window, with no clipping or overlap.
- **SC-020.** A low-voltage callout speaks the measured voltage with 2
  decimals per cell or 1 decimal per pack, matching the transmitter's
  telemetry value within one sensor step, in both voices.
- **SC-021.** A new battery has no current alarm values, and no current
  alarm fires until threshold, delay and repeat interval are all set.

## Edge cases

- **Consumed mAh exceeds rated capacity.** Gauge shows 0% (empty, red,
  flashing), never negative.
- **Sensor lost or invalid** (`valid` false). Gauge greys out with "NO TELEM";
  current alarms suppressed; a distinct "telemetry lost" indication, not a
  battery alarm.
- **Sensor unit doesn't fit a capacity mode** (e.g. temperature). Setup warns
  and refuses it as a capacity source.
- **Assigned sensor disappears** (receiver rebind, model copy). "Sensor not
  found"; no errors; user can re-assign.
- **Voltage sag under load** on voltage-only packs makes % jump around.
  Smoothing; possibly estimate only at low current (open question).
- **Pack plugged in not fully charged.** mAh-consumed sensors start at 0 and
  would show 100%. The new-pack check estimates % from resting voltage and
  warns once if it's below 90%. The gauge still shows the sensor's value.
- **Low voltage under heavy load** (punch-out sag). The 2 s alarm delay
  rides it out; a pack that sags below the threshold for longer is
  genuinely low and should alarm.
- **Voltage hovers at the threshold.** The 0.05 V per-cell recovery margin
  stops the alarm toggling on and off.
- **Current alarm partly configured** (threshold set, repeat blank). The
  alarm stays off and settings shows what's missing.
- **Voltage above 500 V or a missing digit file.** The whole callout falls
  back to the transmitter's voice.
- **Low-voltage alarm with no voltage reading.** Not available; the
  setting is hidden for that battery.
- **Custom name too long to fit.** The editor stops accepting characters
  once the label would be wider than the battery.
- **Third pack of a category added** (RX-1, RX-2 exist). It becomes RX-3;
  removing RX-1 does not renumber the others unless the user edits them.
- **Sensor resets mid-flight** (brown-out) and consumed mAh drops to 0.
  Hold the last known value instead of jumping back to full.
- **Pack powered up already below a callout level.** Only the lowest
  crossed enabled level is called out once; higher levels are marked as
  passed and stay silent.
- **Reading jitters around a callout level** (voltage sag, noisy sensor).
  Hysteresis prevents repeats.
- **Repeat interval shorter than the callout itself** (long pack name plus
  number). The next callout waits for the current one to finish; no
  overlap or queue build-up.
- **Lowest level disabled while it is repeating.** Repeating stops; the
  next lowest enabled level becomes the repeating one, without replaying
  if it has already fired.
- **User edits callout levels mid-session.** Levels re-arm from the current
  % remaining; levels already below it stay silent until crossed.
- **Chemistry or cell count changed after manual edits.** Confirm before
  overwriting.
- **Category changed after manual edits.** Same rule: confirm before
  overwriting edited bands, callout levels or current settings; unedited
  values follow the new category.
- **Suggested chemistry differs from what the user picks** (e.g. a LiPo
  receiver pack). Allowed; the suggestion only pre-selects.
- **Cell count doesn't match measured voltage** (e.g. 2S set, 12.4 V seen).
  Warn in setup.
- **Two batteries share one sensor** (e.g. dual-pack switch reporting both).
  Allowed; each battery reads its own sensor parameter.
- **Double window with only 1–3 batteries.** Batteries stay left-justified
  at their 4-battery size and spacing; no stretching or centring.
- **% text over a low fill** (e.g. 5%). The text straddles the fill and the
  background; contrast must hold for both (e.g. outlined text or colour
  based on the area behind most of it). Iterate on the emulator.
- **Current steady from power-up** (e.g. on the bench). The 1 s hold rule
  still registers it as the max, as in Speed Gauge.
- **Model switch mid-session.** The session max resets; settings are per
  model.
- **Pack swapped without restarting the transmitter** (electric flights
  back to back). Detected as a new pack: the max resets and capacity
  callouts re-arm for that battery only.
- **Brown-out that looks like a new pack** (mAh-consumed sensor resets to
  0 after a short dropout). If voltage doesn't confirm a full pack, it's
  treated as a brown-out: last values held, max not reset. With no voltage
  sensor, a brief dropout can't be told apart from a swap; the README says
  so and recommends assigning a voltage sensor.
- **Max callout due while another callout or app is speaking.** It waits;
  capacity and Flameout Alarm callouts take priority.
- **Current sensor assigned but lost.** The current line shows "--" rather
  than the last value.
- **Battery removed or reordered.** The remaining batteries shift left to
  fill the gap, in configured order.
- **Current spikes** (retracts, servo stall). Alarm delay rides them out.
- **Another app is speaking** when a callout is due. This app waits until
  playback ends; it never interrupts. Flameout Alarm uses immediate
  playback and always wins.
- **Voice files missing or partly installed.** Each callout whose files
  aren't all present falls back to the transmitter's voice for the whole
  phrase (number + unit only); settings shows "voice files missing".
- **Number above 500** (e.g. a very high current). Spoken by the
  transmitter's voice, not skipped.

---

## Open questions / research (feed to `/speckit-clarify` and the plan)

1. **Artwork.** The sample image carries a stock-site watermark, so it can't
   ship. The look (metallic caps, glassy cylinder, colour bands)
   must be original: either drawn with `lcd` primitives at runtime, or our
   own PNG shell assets in `AG-BatCp/` with the fill drawn on top. Decide by
   prototyping both in the emulator (quality vs. CPU and memory). The
   Jeti `lcd` API may not rotate images, so PNG shells would need a
   separate horizontal version for the small window; runtime drawing can
   use the same code with x/y swapped.
2. **Telemetry window limit.** The Lua API appears to allow only two
   telemetry windows per app (`system.registerTelemetry` with id 1 or 2).
   That rules out four separate small windows from one app. Proposed: window
   1 = small, user picks which battery; window 2 = double, user picks up to 4.
   Alternatives: let the small window page through batteries. Confirm the
   limit on firmware 6.x.
3. **Capacity sensors available.** List what Aaron actually uses (MUI,
   Central Box, receiver voltage, ESC telemetry, Powerbox/other converters),
   and for each: unit string, scaling, decimals, update rate, behaviour on
   power-up and loss. Drives the unit-detection rules.
4. **Defaults tables.** Category-based defaults are confirmed. Confirm the
   per-chemistry voltages and the per-category bands, callout levels,
   suggested chemistry and current-alarm visibility in the draft tables.
   Decided: the lowest-level repeat defaults (5 s interval, max count off)
   are the same for every category for now.
5. **Voltage-to-% curves.** Source a resting-voltage SoC curve per chemistry;
   decide on load compensation (ignore samples at high current if a current
   sensor exists) and smoothing.
6. **Which alarms are in v1 (decided 2026-10-25).** Capacity callouts
   (0–4 levels, lowest repeats), low-voltage alarm with red flashing
   outline, one current alarm threshold per battery, max current callout
   and the optional new-pack check. No key press to silence. The current
   alarm has no defaults (user sets threshold, delay and repeat). The
   low-voltage callout speaks the voltage with decimals, per cell or per
   pack.
7. **Voice (decided 2026-10-25).** Match Speed Gauge: Amy number and phrase
   files, queued phrases, transmitter fallback. The full 0–500 number set
   (about 23 MB) is accepted. Turbine ECU (electronic control unit) is
   spoken as the letters "E C U".
8. **Update rate.** The firmware calls the draw callback on its own schedule;
   the app throttles data updates to 1 s. Confirm drawing cost for 4 gauges
   and whether 1 s feels responsive enough for current readout.
9. **New-pack check (decided 2026-10-25).** In v1, optional per battery,
   warns once below 90%, checked 3 s after the pack is first seen, off by
   default.
10. **Stub check.** Confirm `types/jeti.lua` covers `registerTelemetry`,
    `getSensors`, `getSensorByID`, `playFile`, `playNumber`, `playBeep` and
    the `lcd` drawing/image functions (`drawFilledRectangle`, `setColor`,
    `loadImage`, `drawImage`, fonts); add any missing ones and note them in
    `docs/jeti-api-notes.md`.
11. **Custom categories (decided 2026-10-25).** A custom name must fit
    above the upright battery graphic; a custom category speaks
    "battery". Set the exact character limit on the emulator.
12. **Category in callouts (decided 2026-10-25).** Every callout always
    names the pack.
13. **Max current (decided 2026-10-25).** Mirrors Speed Gauge (FR-019/
    FR-019a, R5); a new pack resets the max; 5 A default sensitivity
    confirmed; no on-demand switch for now. Still to tune on real packs:
    the new-pack rule (20-point jump, 0.05 V per cell near full, minimum
    dropout length).
