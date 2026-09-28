# Feature Specification: Speed Gauge

**Feature Branch**: `001-speed-gauge`

**Created**: 2026-09-27

**Status**: Draft

**Input**: User description: "Rewrite of DFM Speed Announcer (docs/examples/dfm-speed-announce) with clearer settings labels, air-density (altitude/temperature) correction, and a round speedometer-style telemetry gauge with sticky session max speed"

## Overview

**Speed Gauge** is a transmitter app that speaks the model's airspeed during
flight, warns about stall and overspeed, and shows speed on a round gauge on
the transmitter's main screen.

It is based on **DFM Speed Announcer** by DFM (Dave McQueeney), MIT-licensed.
The original v2.1 is kept unmodified in `docs/examples/dfm-speed-announce/` as
the behavioral baseline. Much of Speed Gauge's behavior comes from that app,
and it is credited as the basis of this one (FR-029, `CREDITS.md`). Speed Gauge
keeps the original's core behavior and adds four things:

1. clearer settings;
2. an air-density correction based on field elevation and temperature;
3. a speedometer-style gauge;
4. a session max-speed marker on the gauge.

The app only listens and informs. It never controls the model (constitution
principle I).

### Terms used in this spec

- **Sensor speed**: the value the chosen telemetry sensor reports, after the
  user's calibration percentage is applied. For a pitot sensor this is
  *indicated airspeed*, the speed the wing "feels".
- **True airspeed**: sensor speed corrected for air density. At high or hot
  fields true airspeed is higher than sensor speed. For example, at 5,000 ft
  and 35 °C, a sensor speed of 100 mph is a true airspeed of about 113 mph.
- **Session**: from when the app starts (transmitter power-on, model load, or
  app reload) until it stops.

## Clarifications

### Session 2026-09-27

- Q: What does density correction apply to? → A: The gauge, callouts,
  session max and overspeed warning use true airspeed. The stall,
  landing-speed and "airspeed alive" checks use sensor speed.
  - **Why, in the user's words:** "if a wing stalls at 40 mph at 0 ft (sea
    level) I want the warning to go off at the equivalent pressure when flying
    at 5000 ft". A pitot sensor measures pressure, so the stall pressure reads
    as the same sensor speed (40) at any altitude. Comparing sensor speed to
    the stall setting therefore fires at the equivalent pressure. The stall
    and landing speeds are entered as the model's sea-level values.
- Q: Does GPS get density correction? → A: No. GPS measures ground speed,
  which air density doesn't affect (confirmed by the user).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Hear speed during flight (Priority: P1)

A pilot selects a speed sensor and an on/off switch. During flight the
transmitter speaks the speed. When the speed is steady it speaks rarely; when
the speed is changing it speaks more often; below landing speed it speaks every
couple of seconds.

**Why this priority**: This is the reason the app exists. Every other story
builds on having a working speed callout.

**Independent Test**: In the emulator, with a simulated speed sensor, select
the sensor and a switch, turn the switch on, and vary the simulated speed. The
spoken interval should shorten as speed changes faster, stay near the maximum
interval when speed is constant, and drop to the fast interval below landing
speed.

**Acceptance Scenarios**:

1. **Given** a sensor and switch are selected and the switch is on, **When**
   the speed stays constant, **Then** callouts come no more often than the
   "longest time between callouts" setting allows (40 s by default).
2. **Given** the switch is on, **When** speed changes by at least the
   "callout sensitivity" amount between callouts, **Then** the next callout
   comes sooner, but never sooner than "shortest time between callouts" (2 s
   by default).
3. **Given** the switch is on and the model has been above landing speed,
   **When** speed drops below landing speed, **Then** callouts come every
   "shortest time between callouts".
4. **Given** the continuous-callouts switch is on, **When** at any speed,
   **Then** speed is spoken every "shortest time between callouts",
   regardless of the on/off switch.
5. **Given** both switches are off, **Then** nothing is spoken.
6. **Given** a callout is still being spoken, **When** the next callout comes
   due, **Then** it waits until speech finishes rather than queueing up.
7. **Given** the model has not yet exceeded half of landing speed this session
   (sitting on the ground, taxiing), **Then** normal callouts stay silent
   unless the continuous-callouts switch is on.

---

### User Story 2 - Stall, overspeed and "airspeed alive" warnings (Priority: P1)

The pilot sets a stall warning speed and an overspeed warning speed. The app
warns once when crossing each threshold, both by voice and with stick
vibration, and re-arms after the speed moves back.

**Why this priority**: These warnings are the most safety-relevant information
the app gives. They are part of the baseline app and must not regress.

**Independent Test**: In the emulator, raise simulated speed above landing
speed, then lower it below the stall speed, then raise it above the overspeed
speed. Each warning should play exactly once per crossing.

**Acceptance Scenarios**:

1. **Given** the model has been above landing speed this session, **When**
   sensor speed drops to or below the stall warning speed, **Then** the stall
   warning plays once and the right stick vibrates, and it re-arms when speed
   rises back above the stall warning speed.
2. **Given** the model has *not* yet been above landing speed this session,
   **When** sensor speed is below the stall warning speed, **Then** no stall
   warning plays (so it doesn't fire on the ground).
3. **Given** speed rises above the overspeed warning speed, **Then** the
   overspeed warning plays once and the stick vibrates, and it re-arms after
   speed drops back to or below the overspeed speed.
4. **Given** it is the first time this session that sensor speed exceeds half
   of landing speed, **Then** "airspeed alive" plays once.
5. **Given** density correction is on at 5,000 ft (standard temperature) and
   the stall warning is set to 40 mph, **When** the model slows, **Then** the
   stall warning fires when sensor speed reaches 40 mph. At that moment the
   gauge reads about 43 mph (true airspeed). The warning fires at the same air
   pressure at which it would fire at 40 mph at sea level.
6. **Given** the same setup, **Then** the landing-speed switch to fast callouts
   and the "airspeed alive" check likewise use sensor speed, so they happen at
   the same wing loading at any field elevation.

---

### User Story 3 - Speedometer gauge on the main screen (Priority: P2)

The pilot adds the app's telemetry window to the transmitter's main screen, in
either the normal (single) or double size. It shows a round speedometer: a
prominent needle or arc for current speed, a subtle marker for the highest
speed reached this session, and the numbers for both.

**Why this priority**: It is the main new feature, but announcements and
warnings are useful on their own without it.

**Independent Test**: In the emulator, place the window on the desktop in each
size, vary the simulated speed, and check that the current-speed indicator
moves, the max marker stays at the peak, and both numbers match.

**Acceptance Scenarios**:

1. **Given** the window is placed in the normal (single) size, **Then** it
   shows the compact arc gauge. The value arc and max marker are visible, and
   the current speed and session max appear as numbers, all readable without
   overlap.
2. **Given** the window is placed in the double size, **Then** it shows the
   full dial from the visual design reference below. That means a dark face,
   rim scale, colored value arc, overspeed zone, max marker, and the current
   speed as a large center number with its unit. Max, stall and overspeed
   appear as small labeled rows as room permits.
2a. **Given** the full-screen window is selected, **Then** it shows a large
   dial with a side panel of labeled values, as in the visual design
   reference.
3. **Given** speed rises to a new peak and then falls, **Then** the max-speed
   marker stays at the peak in its own color while the current-speed indicator
   follows the current speed in front of it.
4. **Given** the current-speed and max-speed colors are changed in settings,
   **Then** the gauge uses the new colors the next time it is drawn.
5. **Given** no valid sensor reading is available (no sensor selected,
   receiver off, sensor lost), **Then** the gauge shows a clear "no data"
   state (for example "---") instead of a stale speed, and the session max
   remains visible.
6. **Given** the user chooses "Reset max speed", **Then** the session max
   clears and the marker restarts from the current speed.
7. **Given** speed is above the gauge's full scale, **Then** the indicator
   stops at full scale and the numeric value still shows the actual speed.

**Visual design reference** (provided by the user, 2026-09-27): a car
head-up-display speedometer. The photo is a third-party product image, so it
isn't committed. A local copy is at `docs/vendor/gauge-reference.jpg` on the
development PC; `docs/vendor/` is gitignored. Open it when planning or building
the gauge. The elements to carry over:

- **Dark round face.** A dark, circular dial background inside the window,
  independent of the transmitter's screen theme. This gives the colored arc
  its contrast.
- **About 270° sweep.** The dial runs clockwise from lower-left (zero) over the
  top to lower-right (full scale), leaving the bottom open.
- **Rim scale.** Major ticks with numbers around the outside, and lighter minor
  ticks between them.
- **Glowing value arc.** Current speed is shown mainly as a thick colored arc
  that fills the rim from zero up to the current speed, like the blue sweep in
  the reference. A thin needle or bright tip at the arc's end is optional.
- **Warning zone.** A red/orange band on the rim from the overspeed warning
  speed to full scale, like the reference's red zone near the top. The stall
  and landing marks sit on the rim as small ticks (FR-016a).
- **Big center number.** Current speed as a large number in the middle of the
  dial, with the unit in smaller text underneath. This is the primary numeric
  readout.
- **Session max, kept subtle.** A thin tick or small dot on the rim in the max
  color. It stays at the peak while the value arc moves beneath it, and the
  max also appears as a small labeled number.
- **Secondary data as small rows.** "Max", "Stall" and "Overspeed", each a
  short label with a value. They go beside or below the dial wherever room
  allows, like the reference's side panel.

**Target screen: DS-24 II only.** The gauge is designed for the DS-24 II
(and the DC-24 II, which shares its display): a 4" color screen that JETI
lists as 480 × 480 px, running the JUi2 interface. Earlier transmitters (the
original DC/DS-24, DC/DS-16/14, DS-12) have smaller screens and are **not
supported for the gauge** (see FR-013a).

**Measured window sizes** (JETI Studio emulator, firmware 6.04, with
`tools/probe/PROBE.lua`, 2026-09-27):

| Window | Size |
| --- | --- |
| Single (small) | **157 × 60 px**, about 2.6 : 1, wide and short |
| Double (large) | **157 × 127 px**, a little wider than tall |
| Full screen | **320 × 260 px** (sizes 3 and 4 measure the same) |

Lua on the II uses these window sizes even though JETI lists the display as
480 × 480. The layout is designed for these numbers and adapts to each size:

- **Double window (157 × 127).** The full ~270° dial, about 110–120 px across,
  centered, with the large center number and unit. The Max / Stall /
  Overspeed rows go in the corners around the dial, because there is no room
  for a side panel.
- **Full screen.** The layout closest to the reference photo: a large dial on
  the left, and on the right a side panel with labeled rows (Max, Stall,
  Overspeed, and room for more, such as density-correction factor or sensor
  speed). At 320 × 260 the dial can be about 200–220 px across, with a
  side panel roughly 100 px wide.
- **Single window (157 × 60).** Too short for a round dial. It uses the compact
  version: a shallow arc (about 180° or less) of the same style, with the
  current speed as a large number and max as a small number beside it. Other
  elements are dropped before the arc becomes unreadable.

---

### User Story 4 - Correct for air density (Priority: P2)

A pilot flying from a high or hot field enters the field elevation and,
optionally, today's temperature. The spoken speed, gauge and max speed then
show true airspeed. If no temperature is entered, the app assumes the standard
temperature for that elevation.

**Why this priority**: Without it, speeds at high fields read noticeably low
(about 8% low at 5,000 ft on a standard day, and more when it's hot). But the
app is fully usable without it.

**Independent Test**: With a steady simulated sensor speed of 100 mph, set the
elevation to 5,000 ft and the temperature to 35 °C, then turn correction on
and off. The gauge and callouts should read about 113 mph when on and 100 mph
when off.

**Acceptance Scenarios**:

1. **Given** correction is off, **Then** displayed and spoken speed equals
   sensor speed.
2. **Given** correction is on at elevation 0 and no temperature set, **Then**
   true airspeed equals sensor speed (within 1%).
3. **Given** correction is on at 5,000 ft with no temperature set, **Then** a
   100 mph sensor speed displays as 108 mph (±1).
4. **Given** correction is on at 5,000 ft and 35 °C, **Then** a 100 mph sensor
   speed displays as 113 mph (±1).
5. **Given** the speed source is set to GPS, **Then** no density correction is
   applied, regardless of the correction setting, because GPS measures ground
   speed.
6. **Given** correction is on, **Then** the settings screen shows the current
   correction factor (e.g. "+13%") so the pilot can see its effect.

---

### User Story 5 - Settings that explain themselves (Priority: P2)

The pilot opens the app's settings from the transmitter menu and can tell what
each item does without reading a manual. Settings are grouped by purpose and
use plain wording. Each setting that uses a speed shows the unit.

**Why this priority**: The unclear labels in the original app are one of the
three reasons for the rewrite. It is cheap to do and affects every user.

**Independent Test**: Give the settings screen to a pilot who hasn't seen
either app. They should be able to set up sensor, switch, landing speed and
stall warning without help, and explain what "callout sensitivity" does after
reading its label and hint.

**Acceptance Scenarios**:

1. **Given** the settings screen, **Then** items are grouped under headings in
   this order: Sensor and switches, Callouts, Warnings, Air density, Gauge.
2. **Given** any speed-valued setting, **Then** its label or value shows the
   selected unit (e.g. "Stall warning at: 45 mph").
3. **Given** the settings from the original app, **Then** each is present
   under the new wording in the table below (functional equivalence), except
   where this spec says otherwise.

| Original label | New label | Meaning |
| --- | --- | --- |
| Select Speed Sensor | Speed sensor | Which telemetry value to use |
| *(new)* | Sensor type: Airspeed (pitot) / GPS | GPS disables density correction |
| Select Enable Switch | Callouts on/off switch | Turns automatic callouts on |
| Select Continuous Ann Switch | Continuous callouts switch | Speak every "shortest time", always |
| Speed change scale factor | Callout sensitivity (speed change) | Speed change that makes callouts come faster. Smaller = chattier. Hint: "Speak sooner when speed changes by this much" |
| Call Speed < Vref every (sec) | Shortest time between callouts (s) | Also the interval below landing speed and in continuous mode |
| Call Speed at least every (sec) | Longest time between callouts (s) | Upper limit when speed is steady |
| Reference speed (Vref) | Landing speed (fast callouts below) | Below this, speak every "shortest time" |
| Stall speed (Vs0) | Stall warning at | Warning threshold |
| Speed Max Warning | Overspeed warning at | Warning threshold |
| Airspeed Calibration Multiplier (%) | Sensor calibration (%) | Scales the sensor reading; 100 = unchanged |
| Select speed units | Units | mph, km/h, knots, m/s, ft/s |
| Short Announcement | Speak number only (no units) | Say "85" instead of "speed 85 mph" |
| *(new)* | Field elevation | For density correction |
| *(new)* | Temperature (blank = standard) | For density correction |
| *(new)* | Correct for air density: on/off | Shows the resulting factor, e.g. "+13%" |
| *(new)* | Current speed color / Max speed color | Gauge colors |
| *(new)* | Gauge full scale | Top of the dial |
| *(new)* | Reset max speed | Clears the session max |

---

### Edge Cases

- **Receiver not yet connected at power-on.** Sensors that appear later must
  become selectable without restarting the app. The original built its sensor
  list only once at startup.
- **Saved sensor missing from the current list** (different receiver, or
  sensor not yet connected). Keep the saved selection and show it as
  "not found" rather than silently switching to another sensor.
- **Sensor list order changes** between sessions. The saved selection must
  still refer to the same sensor, not whatever now sits in the same position.
- **Invalid or stale sensor reading.** No callouts, no warnings, no change to
  session max; the gauge shows "no data".
- **A single implausible spike** (e.g. a pitot glitch). The session max should
  not be ruined by one bad sample. What counts as implausible is a planning
  decision, but it must be documented.
- **Switch not assigned.** Treated as off; continuous switch unassigned is
  treated as off.
- **Landing speed set to 0 or above overspeed.** The settings screen must
  prevent or flag illogical threshold order
  (stall < landing < overspeed < full scale).
- **Units changed after thresholds were set.** Thresholds are entered in the
  selected unit. Changing units does not silently reinterpret them: either
  convert them or warn.
- **Model switch mid-session.** The session max resets (new session);
  settings are per model.
- **Very high temperature or elevation input.** Inputs are limited to
  plausible ranges (see FR-020).
- **Telemetry window size changes** (user moves it between single and double).
  The layout adapts on the next draw.

## Requirements *(mandatory)*

### Functional Requirements

**Speed source**

- **FR-001**: Users MUST be able to select any available telemetry value as
  the speed source, and choose whether it is an airspeed (pitot) or GPS
  sensor.
- **FR-002**: The sensor list MUST include sensors that become available after
  the app starts.
- **FR-003**: The selected sensor MUST be remembered per model and identified
  by the sensor itself, not by its position in a list.
- **FR-004**: Sensor speed MUST be the sensor reading converted to the
  selected units and multiplied by the calibration percentage (1–200%,
  default 100%).

**Callouts**

- **FR-005**: When the on/off switch is on, the app MUST speak speed at a
  variable interval. The interval runs from "shortest time between callouts"
  (1–10 s, default 2 s) to "longest time between callouts" (10–60 s, default
  40 s). It gets shorter as the speed change since the last callout grows
  relative to "callout sensitivity" (1–100 in the selected units, default 10).
  With the default settings, a speed change equal to the sensitivity MUST give
  an interval of roughly 20 s, matching the original app's behavior.
- **FR-006**: Below landing speed (once the model has been above it this
  session), or while the continuous switch is on, callouts MUST occur every
  "shortest time between callouts".
- **FR-007**: A new callout MUST NOT start while the previous one is still
  playing.
- **FR-008**: Callouts MUST be rounded to the nearest whole unit. Units MUST
  be spoken unless "speak number only" is set, or the speed is below landing
  speed, or continuous mode is on (short callouts when timing matters,
  matching the original).
- **FR-009**: Normal callouts MUST stay silent until sensor speed first
  exceeds half of landing speed in the session. Continuous mode overrides
  this.

**Warnings**

- **FR-010**: The app MUST give the stall, overspeed and "airspeed alive"
  warnings as described in User Story 2, each once per crossing, with the
  existing warning sounds and stick vibration patterns.
- **FR-011**: Stall, landing-speed and "airspeed alive" checks MUST compare
  sensor speed (not density-corrected) against the user's settings. Those
  settings are the model's sea-level values, so the warnings fire at the same
  air pressure at any field elevation. The overspeed check MUST use the same
  speed shown on the gauge (true airspeed when correction is on), because the
  overspeed limit is about the airframe's actual speed.
- **FR-012**: Warnings MUST work whenever either switch is on, regardless of
  whether the gauge is displayed.

**Gauge**

- **FR-013**: The app MUST offer two main-screen telemetry windows on the
  DS-24 II (and DC-24 II), the maximum an app may register:
  - "Speed Gauge": the pilot places it at single or double size;
  - a full-screen window, also titled "Speed Gauge" (the user chose not to
    add "(full screen)" to the title, 2026-09-27).
- **FR-013a**: The gauge is not supported on other transmitters. If the app
  runs on one, the telemetry window MUST show a short notice (e.g. "Speed
  Gauge needs DS-24 II") instead of a mis-drawn gauge. Callouts and warnings
  MUST still work, because they don't depend on the screen.
- **FR-014**: The window MUST show a round, speedometer-style gauge following
  the visual design reference in User Story 3:
  - a dark dial face;
  - a rim scale with ticks and numbers;
  - current speed as a filled colored arc from zero to the current speed (the
    dominant indicator);
  - session max as a thin marker in a different color, which the value arc
    passes beneath;
  - an overspeed zone from the overspeed warning speed to full scale;
  - past the overspeed warning speed, the part of the value arc beyond that
    mark is drawn in the overspeed color instead of the current-speed color
    (added 2026-09-27).
- **FR-014a**: Current speed MUST also be shown as a large number with its unit
  at the center of the dial (double size) or next to the arc (single size).
- **FR-015**: The window MUST show current speed and session max speed as
  numbers, with units.
- **FR-016**: In the double size, and in the single size where it fits, the
  window SHOULD show secondary information: stall and overspeed speeds as rim
  marks and as small labeled rows (Max / Stall / Overspeed).
- **FR-016a**: When correction is on, stall and landing-speed marks on the
  dial MUST be placed at their true-airspeed equivalents (setting × correction
  factor). The needle then crosses a mark at the moment its warning or
  callout change happens. Any numeric label for these speeds shows the
  setting as entered.
- **FR-017**: Users MUST be able to choose the current-speed and max-speed
  colors from a preset list of at least 6 distinct colors. The defaults are a
  blue/cyan value arc (as in the reference) and a bright yellow max marker,
  drawn thick enough to stand out from the arc (changed from white after
  emulator testing, 2026-09-27: white was too subtle). Neither color choice
  may be the same as the red/orange overspeed zone.
- **FR-018**: Gauge full scale MUST be user-settable. The default is derived
  from the overspeed warning speed, so overspeed sits near the top of the
  dial.
- **FR-019**: Session max MUST reset at the start of each session and when the
  user chooses "Reset max speed". It is not saved between sessions.

**Air density**

- **FR-020**: Users MUST be able to enter field elevation (−1,000 to 15,000 ft,
  or the metric equivalent) and, optionally, the outside temperature
  (−30 to 50 °C, or the Fahrenheit equivalent). If temperature is not set,
  the standard-atmosphere temperature for the entered elevation is used.
- **FR-021**: When correction is on and the sensor type is airspeed, displayed
  speed, spoken speed, session max and overspeed check MUST use true airspeed,
  computed from the standard atmosphere at the entered elevation and
  temperature. Results MUST be within 1% of the standard density-altitude
  formula across the input ranges.
- **FR-022**: The settings screen MUST show the resulting correction factor as
  a percentage while correction is on.
- **FR-023**: Elevation and temperature MUST use feet/°F when speed units are
  mph, knots or ft/s, and meters/°C otherwise.

**Settings and lifecycle**

- **FR-024**: All settings MUST be saved per model and restored when the model
  is loaded.
- **FR-025**: Settings MUST use the labels, grouping and hints described in
  User Story 5.
- **FR-026**: The settings screen MUST flag an illogical threshold order
  (stall ≥ landing, landing ≥ overspeed, overspeed > full scale).
- **FR-027**: The app MUST NOT affect any model control function, and MUST
  install alongside the original DFM Speed Announcer without replacing it or
  its settings.
- **FR-028**: At startup the app SHOULD announce the stall warning speed, as
  the original did, so the pilot knows the app is running and configured.
  This can be turned off in settings.
- **FR-029**: The app MUST credit DFM Speed Announcer by DFM (Dave McQueeney)
  as its basis in all of these places:
  - **Source file header:** this repo's copyright ("Copyright (c) 2026 Aaron
    George") and license tag (`SPDX-License-Identifier: MIT`), plus a credit
    line and the original's MIT copyright notice ("Copyright (c) 2018, 2019
    DFM (Dave McQueeney)"), with a pointer to `CREDITS.md` for the full
    license text.
  - **Settings screen:** a line at the bottom, e.g. "Based on DFM Speed
    Announcer by Dave McQueeney", next to the app version.
  - **Repository documentation:** the README and `CREDITS.md`.
  - **Asset folder:** reused WAV files keep their credit, via a short credits
    note placed with them.

### Key Entities

- **Model settings**: speed sensor and sensor type; on/off and continuous
  switches; shortest and longest callout times; callout sensitivity; landing,
  stall and overspeed speeds; calibration %; units; number-only flag; field
  elevation; temperature (optional); density correction on/off; gauge colors
  and full scale; startup announcement on/off.
- **Session state**: current sensor speed, current displayed speed, session
  max, whether the model has been above landing speed, whether "airspeed
  alive" has played, and the armed/disarmed state of each warning.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With default settings and a constant speed, callouts are 38–42 s
  apart. With a steady 10-unit change between callouts, they are roughly 20 s
  apart. Below landing speed they are 2 s (±0.5 s) apart, as measured in the
  emulator.
- **SC-002**: Each warning (stall, overspeed, airspeed alive) plays exactly
  once per threshold crossing across 10 simulated crossings, with no warnings
  before the model first exceeds landing speed.
- **SC-003**: With 100 mph sensor speed, the density correction gives 100 mph
  (0 ft, standard temperature), 108 mph (5,000 ft, standard temperature) and
  113 mph (5,000 ft, 35 °C), each ±1 mph.
- **SC-003a**: With correction on at 5,000 ft (standard temperature) and the
  stall warning set to 40 mph, the stall warning fires at a sensor speed of
  40 mph (±1). The gauge then reads 43 mph (±1), and the needle is at the
  dial's stall mark.
- **SC-004**: The gauge is readable at a glance in both single and double
  window sizes. A pilot can read current speed within 5% from the dial alone,
  and read both numbers without overlap, on the DS-24 II screen.
- **SC-005**: The gauge reflects a speed change within 0.5 s.
- **SC-006**: A pilot new to the app configures sensor, switch, landing speed
  and stall warning in under 3 minutes without referring to documentation.
- **SC-007**: Running the app does not noticeably slow the transmitter. Its
  CPU figure in the transmitter's app overview stays below 20% during flight
  with the gauge displayed.
- **SC-008**: Every behavior of the original app is either kept or listed in
  this spec as deliberately changed. No setting disappears without
  explanation.

## Assumptions

- **Target and baseline.** The gauge targets the DS-24 II / DC-24 II
  (firmware 6.x) only, using the measured Lua window sizes (157 × 60 and
  157 × 127), not the panel's 480 × 480. The original app was tested
  only on the original DS-24. The original's
  behavior (v2.1) is the baseline; where this spec is silent, match it.
- **Existing audio.** The existing WAV files (stall warning, overspeed,
  airspeed alive, "stall speed warning at", cal factor) are reused. New voice
  files are out of scope for v1.
- **Pitot sensors report indicated airspeed.** They convert pressure to speed
  using fixed sea-level air density. This holds for the sensors the original
  was tested with (Jeti MSpeed, Digitech, ASSI, Xicoy). A sensor that already
  corrects for density would be double-corrected if correction is on, so the
  in-app help MUST tell the user to leave correction off for such sensors.
- **GPS warnings use ground speed.** With a GPS source, stall and landing
  checks compare ground speed to the settings. Wind makes these approximate;
  the help text says so.
- **Density correction scope.** Correction uses field elevation plus
  temperature, assuming standard sea-level pressure at that elevation. Using a
  live pressure/temperature sensor from the model is out of scope for v1.
  Standard pressure is accurate enough for announcements (typically within a
  few percent).
- **Calibration file dropped.** The original's per-model calibration file
  (`DFM-<model>.jsn`) is not carried over; the calibration setting is saved
  per model like everything else.
- **Session max** is not logged to file or saved. Logging it to the
  transmitter's telemetry log is a possible later feature.
- **English only.** Labels and callouts are English for v1. Spoken numbers and
  units follow the transmitter's voice language.
- **New app, new settings.** The app is named "Speed Gauge" (shown in the
  transmitter's app list and menu). Its script is `AG-SpdGa.lua`, with assets
  in `AG-SpdGa/`, following the repo's naming convention. Because the filename
  differs, it installs next to DFM-SpdA. Settings are not imported from the
  original. Density math and gauge drawing are candidates for shared `lib`
  modules, since other apps may reuse them; the plan decides.

