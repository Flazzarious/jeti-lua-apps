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

### Session 2026-09-28

- Q: Should callouts use a better voice than the transmitter's built-in one?
  → A: Yes. After comparing three generated samples (Piper "Lessac", "Amy"
  and "Ryan"), the user chose **Amy** as the clearest. All of Speed Gauge's
  speech then uses that one voice: numbers, units, warnings and startup.
  See User Story 6 and FR-030–FR-037.

### Session 2026-09-30

- Q: What limits apply to field elevation and temperature? → A: Elevation is
  **−300 to 10,000 ft** (−90 to 3,050 m). The user proposed −10 to 8,000 ft.
  Checking real airfields showed that range would exclude, among others:
  - Leadville CO (9,934 ft, North America's highest) and Telluride CO
    (9,078 ft);
  - Death Valley's Furnace Creek (−208 ft), Thermal CA (−114 ft) and
    Amsterdam Schiphol (−11 ft).
  The user chose the recommended wider range. Temperature is **−20 to
  130 °F** (−29 to 54 °C). The user first proposed −10 to 120 °F, then chose
  the wider range for margin in extreme cold and desert heat.
- Q: Should Speed Gauge use a temperature sensor, such as the MSpeed's? → A:
  Yes. Temperature can come from a selectable telemetry sensor or be set
  manually; standard temperature stays available (FR-038–FR-043). This
  replaces the earlier assumption that live sensor temperature was out of
  scope for v1. Live pressure stays out of scope: the MSpeed doesn't report
  it.
- Q: What if the sensor reads outside the limits, e.g. heat-soaked in the sun
  before a flight? → A: Use the default (standard temperature) while it's out
  of range. Resume using the sensor automatically once it comes back into
  range, e.g. after cooling to ambient in flight (FR-040).
- Q: Is the sensor temperature shown on the full-screen gauge? → A: It
  wasn't. The side panel now has a Temperature row showing the temperature
  in use and its source (FR-044).

### Session 2026-10-03 (first transmitter tests)

- Q: With callouts on and the model standing still, callouts still came
  (continuous mode ignored the old "half of landing speed" rule). How
  should callouts wait for flight? → A: A new setting, **"Callouts start
  above"** (default 30 mph), arms callouts once sensor speed first exceeds
  it. It stays armed for the session (restart or model change re-arms it),
  so approach and landing callouts continue. It applies to normal and
  continuous callouts and to "airspeed alive", and replaces the hidden
  half-of-landing-speed rule. Stall and overspeed warnings are unaffected
  (FR-009).

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
4. **Given** the continuous-callouts switch is on and callouts are armed
   (FR-009), **When** at any speed, **Then** speed is spoken every
   "shortest time between callouts", regardless of the on/off switch.
5. **Given** both switches are off, **Then** nothing is spoken.
6. **Given** a callout is still being spoken, **When** the next callout comes
   due, **Then** it waits until speech finishes rather than queueing up.
7. **Given** the model has not yet exceeded "Callouts start above" (default
   30 mph) this session (sitting on the ground, taxiing), **Then** no speed
   is spoken, with either switch on (changed 2026-10-03: continuous mode no
   longer bypasses this).

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
4. **Given** it is the first time this session that sensor speed exceeds
   "Callouts start above" (FR-009), **Then** "airspeed alive" plays once.
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
   shows the current speed and session max as numbers over a thin bar
   gauge. The bar's value, overspeed zone and max tick are visible, all
   readable without overlap (changed from a compact arc after transmitter
   testing, 2026-10-03).
2. **Given** the window is placed in the double size, **Then** it shows a
   small dial in the style of the visual design reference below: dark
   face, ticks, colored value arc, overspeed zone, stall and landing marks
   and max marker. The current speed is a large number with its unit beside
   the dial, with MAX below it.
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
  the reference, with a bright tip at its end. A glow in the arc's color
  fades from the arc inward toward the center of the dial, as in the
  reference. Past the overspeed mark, the arc and its glow switch to the
  overspeed color (FR-014).
- **Warning zone.** A red/orange band on the rim from the overspeed warning
  speed to full scale, like the reference's red zone near the top, with the
  same inward glow. The stall and landing marks sit on the rim as small
  ticks (FR-016a).
- **Big center number.** Current speed as a large number in the middle of the
  dial, with the unit in smaller text underneath. This is the primary numeric
  readout.
- **Session max, easy to spot.** A thick tick across the rim in the max color
  (bright yellow by default), drawn on top of the value arc. It stays at the
  peak while the arc moves beneath it, and the max also appears as a labeled
  number. (Originally "kept subtle"; a thin white tick proved too hard to see
  in emulator testing, 2026-09-27.)
- **Secondary data as small rows.** "Max", "Stall" and "Overspeed", each a
  short label with a value. They go beside or below the dial wherever room
  allows, like the reference's side panel.

**Target screen: DS-24 II only.** The gauge is designed for the DS-24 II
(and the DC-24 II, which shares its display): a 4" color screen that JETI
lists as 480 × 480 px, running the JUi2 interface. Earlier transmitters (the
original DC/DS-24, DC/DS-16/14, DS-12) have smaller screens and are **not
supported for the gauge** (see FR-013a).

**Measured window sizes** (`tools/probe/PROBE.lua`; the transmitter's own
screenshots, 2026-10-03):

| Window | DS-24 II transmitter | JETI Studio emulator 6.04 (2026-09-27) |
| --- | --- | --- |
| Single (small) | **150 × 23 px**, all visible | 157 × 60, about 157 × 34 visible |
| Double (large) | **150 × 68 px**, all visible | 157 × 127, about 157 × 101 visible |
| Full screen (sizes 3 and 4) | **316 × 159 px**, all visible | 320 × 260, about 320 × 234 visible |

**The transmitter is the target.** The first design used the emulator's
sizes. On the transmitter (2026-10-03) the single window showed only the
MAX value and the double window a cramped strip. The full-screen gauge was
cut off and filled only part of the screen, because the transmitter's
"full screen" is a titled 316 × 159 area across the top two thirds of the
panel. The transmitter draws each title bar above the window and enlarges
Lua drawing about 1.45×, so curves made of coarse segments look stepped.
The layouts below were chosen by the user that day and adapt to the
emulator's larger windows too:

- **Double window (150 × 68).** A small ~270° dial, about 74 px across, on
  the left: face, track, overspeed zone, major ticks, stall and landing
  marks, value arc and max marker, but no scale numbers (too small to
  read). The current speed is large on the right with its unit below, and
  MAX near the bottom. Stall and overspeed appear only as rim marks; there
  is no room for their rows.
- **Full screen (316 × 159).** The layout closest to the reference photo: a
  dial about 180 px across on the left, with the session max centered in
  its open bottom. On the right, a side panel of **one-line rows**, a small
  label with its value right-aligned: Stall, Over (overspeed), Density (the
  correction, e.g. "+8%", or OFF / GPS) and, while correction is on, Elev
  (field elevation), the temperature in use with its source (FR-044) and
  Raw (the uncorrected sensor speed). Six rows of about 26 px. The window
  uses size 4: with size 3 the desktop's model tile covers its lower-left
  corner.
- **Single window (150 × 23).** No room for an arc. The current speed and
  unit at the left and MAX at the right share one line, over a thin
  horizontal bar: the value in the current-speed color, the overspeed zone
  at the right end, and a max tick in the max color.

---

### User Story 4 - Correct for air density (Priority: P2)

A pilot flying from a high or hot field enters the field elevation and
chooses where the temperature comes from:
- **Standard**: the standard temperature for that elevation;
- **Manual**: today's temperature, typed in;
- **Sensor**: read live from a telemetry sensor that reports temperature,
  such as the MSpeed.
The spoken speed, gauge and max speed then show true airspeed.

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
7. **Given** correction is on at 5,000 ft, Temperature source is Sensor, and
   the selected sensor reads 35 °C, **Then** a 100 mph sensor speed displays
   as 113 mph (±1), the same as entering 35 °C manually. The settings screen
   shows the live reading and its source (e.g. "35 °C from MSpeed").
8. **Given** Temperature source is Sensor, **When** the sensor reading is lost
   or out of range, **Then** the correction uses standard temperature for the
   field elevation. Callouts and warnings continue without interruption, and
   the settings screen says the sensor isn't available.
8a. **Given** a hot day where the model sat in the sun and the sensor reads
   140 °F at takeoff, **Then** the correction uses standard temperature, and
   the full-screen panel shows that the sensor is out of range. **When** the
   sensor cools in flight to 95 °F and stays in range for 10 seconds, **Then**
   the correction switches back to the sensor reading without any action from
   the pilot.
9. **Given** Temperature source is Sensor, **When** the reading drifts by a
   fraction of a degree, **Then** the displayed speed doesn't jitter. The
   correction updates only when the temperature changes by at least 1 °C
   (or 2 °F).

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
| Speed change scale factor | Callout sensitivity (*unit* change), e.g. "(mph change)" | Speed change that makes callouts come faster. Smaller = chattier. Hint: "Speak sooner when speed changes by this much" |
| Call Speed < Vref every (sec) | Shortest time between callouts (s) | Also the interval below landing speed and in continuous mode |
| Call Speed at least every (sec) | Longest time between callouts (s) | Upper limit when speed is steady |
| Reference speed (Vref) | Landing speed callouts (on/off) + Landing speed | On: below landing speed, short callouts every "shortest time". Off: landing speed only arms the stall warning. Toggle added and labels changed 2026-10-03 |
| Stall speed (Vs0) | Stall warning at | Warning threshold |
| Speed Max Warning | Overspeed warning at | Warning threshold |
| Airspeed Calibration Multiplier (%) | Sensor calibration (%) | Scales the sensor reading; 100 = unchanged |
| Select speed units | Units | mph, km/h, knots, m/s, ft/s |
| Short Announcement | Speak number only (no units) | Say "85" instead of "speed 85 mph" |
| *(new)* | Field elevation | For density correction |
| *(new)* | Temperature source: Standard / Manual / Sensor | Where density correction gets temperature (FR-038). Replaces the earlier "Use standard temperature" checkbox |
| *(new)* | Temperature (manual) | Used when source is Manual. Limited to −20 to 130 °F (FR-020) |
| *(new)* | Temperature sensor | Used when source is Sensor. Lists only telemetry values that report a temperature. Hint: "Sensors inside the model can read warmer than outside air" |
| *(new)* | Correct for air density: on/off | Shows the resulting factor, e.g. "+13%" |
| *(new)* | Current speed color / Max speed color | Gauge colors |
| *(new)* | Gauge max limit (0 = auto) | Highest speed on the dial; enter the sensor's top speed to use its whole range. Renamed from "Gauge full scale" after transmitter testing, 2026-10-03 |
| *(new)* | Reset max speed | Clears the session max |
| *(new)* | Announce stall speed at startup | Turns off the startup announcement (FR-028) |
| *(new)* | Voice: Speed Gauge / Transmitter | Which voice speaks callouts (FR-032). Shows "voice files missing" if the Speed Gauge voice isn't installed |

---

### User Story 6 - One clear voice for every callout (Priority: P3)

The pilot hears every callout in the same clear, natural voice, "Amy". That
covers speed numbers, units, warnings and the startup announcement. It is
easier to understand over wind and motor noise than the transmitter's
built-in number voice mixed with older recorded warnings. If the voice files
aren't installed, the app still works with the transmitter's voice.

**Why this priority**: It makes callouts easier to understand, but everything
works without it, so it comes after the core stories.

**Independent Test**: With the voice files installed and "Voice: Speed Gauge"
selected, vary the simulated speed in the emulator. Every callout, the three
warnings and the startup announcement should be in the Amy voice, with no
audible gap between number and unit. Then remove the voice folder and
reload the app. Callouts must continue in the transmitter's voice, and the
settings screen must say the voice files are missing.

**Acceptance Scenarios**:

1. **Given** the voice files are installed and Voice is "Speed Gauge",
   **When** a callout of 85 mph with units is due, **Then** the pilot hears
   "eighty-five miles per hour" in the Amy voice as one continuous phrase.
2. **Given** the same setup, **When** a stall, overspeed or airspeed-alive
   warning fires, **Then** it is spoken in the Amy voice.
3. **Given** a callout value above the highest number in the voice set,
   **Then** that callout uses the transmitter's voice. It is not skipped.
4. **Given** the voice files are missing or incomplete, **Then** callouts use
   the transmitter's voice and the warnings use DFM's original recordings.
   The settings screen shows "voice files missing".
5. **Given** Voice is set to "Transmitter", **Then** the app behaves as
   without this story: the transmitter speaks numbers, and warnings use the
   original recordings.

---

### Edge Cases

- **Voice files partly installed** (e.g. the copy to the SD card was
  interrupted). Any callout whose files aren't all present falls back for
  that callout only; the app never plays half a phrase.
- **Number and unit spoken back to back.** They are two files, and the
  pause between them must not sound like two separate announcements
  (SC-009).

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
- **Temperature sensor inside a warm fuselage.** It may read well above the
  outside air (sun, electronics); +10 °C shifts the correction by about
  1.7%. The app can't detect this, so the help text warns about it, and
  Manual stays available.
- **Temperature sensor appears after startup or isn't found.** Handled the
  same way as the speed sensor (FR-002, FR-003): it becomes selectable when it
  appears, and a saved selection that isn't present shows as "not found".
- **Saved value outside the range** (e.g. saved by an earlier version with
  wider limits, or converted between unit systems). It is clamped into the
  range when loaded, and the clamped value is what the settings show and the
  correction uses.
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
  "shortest time between callouts". The below-landing part applies only
  while **"Landing speed callouts"** is on (default on; added 2026-10-03).
  When it's off, landing speed doesn't change callouts, but it still arms
  the stall warning (FR-011).
- **FR-007**: A new callout MUST NOT start while the previous one is still
  playing.
- **FR-008**: Callouts MUST be rounded to the nearest whole unit. Units MUST
  be spoken unless "speak number only" is set, or the speed is below landing
  speed (only while "Landing speed callouts" is on), or continuous mode is
  on (short callouts when timing matters, matching the original).
- **FR-009**: Callouts, normal and continuous, and "airspeed alive" MUST
  stay silent until sensor speed first exceeds the **"Callouts start
  above"** setting (0–1000 in the selected units, default 30 mph) in the
  session. Once exceeded they stay armed until the session ends (power-on,
  model change or app reload). Stall and overspeed warnings don't depend on
  it. (Changed 2026-10-03 from "half of landing speed", which continuous
  mode overrode.)

**Warnings**

- **FR-010**: The app MUST give the stall, overspeed and "airspeed alive"
  warnings as described in User Story 2, each once per crossing, with stick
  vibration patterns and spoken warnings. The warnings use the Speed Gauge
  voice when available (FR-030), otherwise DFM's original recordings.
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
  - a full-screen window titled "Speed Gauge (full screen)". On 2026-09-27
    the user chose the same title as the first window. Transmitter testing
    on 2026-10-03 showed two identical "Speed Gauge" entries in Displayed
    telemetry, so the user asked for names that tell them apart. The
    full-screen window has no title bar, so the name appears only in that
    list.
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
  at the center of the dial (full screen), beside the dial (double size) or
  above the bar (single size).
- **FR-015**: The window MUST show current speed and session max speed as
  numbers, with units.
- **FR-016**: Where it fits, the window SHOULD show secondary information:
  stall and overspeed speeds as rim marks (double and full screen) and as
  labeled rows (full screen). The double window has room for the marks only,
  and the single window shows the overspeed zone on its bar.
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

- **FR-020**: Users MUST be able to enter field elevation and, optionally,
  the outside temperature, limited to these ranges:

  | Setting | Imperial | Metric |
  | --- | --- | --- |
  | Field elevation | −300 to 10,000 ft | −90 to 3,050 m |
  | Temperature | −20 to 130 °F | −29 to 54 °C |

  The editor MUST not allow values outside these limits. If temperature is
  not set, the standard-atmosphere temperature for the entered elevation is
  used; across the elevation range it stays within the temperature limits
  (about −5 °C at 10,000 ft). Values saved outside the limits are clamped
  when loaded (Edge Cases).
- **FR-021**: When correction is on and the sensor type is airspeed, displayed
  speed, spoken speed, session max and overspeed check MUST use true airspeed,
  computed from the standard atmosphere at the entered elevation and
  temperature. Results MUST be within 1% of the standard density-altitude
  formula across the input ranges.
- **FR-022**: The settings screen MUST show the resulting correction factor as
  a percentage while correction is on.
- **FR-023**: Elevation and temperature MUST use feet/°F when speed units are
  mph, knots or ft/s, and meters/°C otherwise.

**Temperature source**

- **FR-038**: The settings MUST offer **Temperature source: Standard / Manual
  / Sensor**. The default is Standard.
  - **Standard** uses the standard-atmosphere temperature for the field
    elevation.
  - **Manual** uses the entered temperature (FR-020).
  - **Sensor** reads a selected telemetry value live.
- **FR-039**: In Sensor mode, the user MUST be able to pick the temperature
  value from the telemetry sensors. The list shows only values that report a
  temperature unit (°C or °F), such as the MSpeed's temperature. The
  selection is remembered per model and identified by the sensor itself, as
  for the speed sensor (FR-003).
- **FR-040**: A sensor reading MUST be used only while it is valid and within
  the temperature limits of FR-020. A reading that is invalid or out of range
  (e.g. a sensor heat-soaked in the sun before flight) makes the correction
  use the default, standard temperature for the field elevation.
  - **Resuming:** the app MUST switch back to the sensor automatically once
    the reading has been valid and in range for at least 10 seconds (two
    consecutive reads, FR-041). The pilot does nothing. The wait stops a
    reading near a limit from flipping back and forth.
  - **Callouts and warnings:** losing or rejecting the temperature reading
    MUST NOT affect callouts, warnings or the gauge beyond this fallback. The
    switch between sensor and standard temperature is itself a change in the
    correction factor, so FR-041's no-callout rule applies.
  - **What isn't caught:** a heat-soaked sensor reading below the upper limit
    (e.g. 115 °F on a 95 °F day) can't be told apart from a hot day. The
    warm-fuselage caveat and the Manual option cover it.
- **FR-041**: The sensor temperature MUST be read at most every 5 seconds. The
  correction factor MUST update only when the temperature has moved at least
  1 °C (2 °F) from the value in use, so the displayed speed doesn't jitter.
  A change in the factor alone MUST NOT trigger a callout.
- **FR-042**: While correction is on, the settings screen MUST show the
  temperature in use and where it came from: "standard", "manual", "from
  <sensor name>", or "sensor not available — using standard".
- **FR-043**: Temperature source affects only density correction. Stall,
  landing-speed and "airspeed alive" checks still use sensor speed (FR-011),
  and GPS sources still get no correction (User Story 4, scenario 5).
- **FR-044**: The full-screen side panel MUST show a **Temperature** row while
  density correction is active. It shows the temperature in use, with its
  unit (°F or °C per FR-023), and its source: standard, manual or sensor.
  While the sensor reading is being rejected (FR-040), the row MUST make
  that visible, e.g. "SENSOR OUT" with the standard temperature being used.
  The single and double windows don't show temperature; there's no room.

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

**Voice**

- **FR-030**: Speed Gauge MUST support a single app voice for all its speech:
  - whole numbers **0–500**;
  - the unit phrases "miles per hour", "kilometers per hour", "knots",
    "meters per second", "feet per second" and "percent";
  - the phrases "stall warning", "overspeed", "airspeed alive", "stall
    warning at" and "airspeed calibration".
  Each is a separate pre-generated audio file in the app's asset folder
  (`/Apps/AG-SpdGa/voice/`). The default voice is Piper's US English
  **"Amy"**, chosen by the user on 2026-09-28.
- **FR-031**: A callout in the app voice MUST be a number file followed by a
  unit file where units are spoken (FR-008). It is queued so the two play as
  one phrase, and FR-007 applies to the phrase as a whole.
- **FR-032**: The settings MUST offer **Voice: Speed Gauge / Transmitter**.
  The default is Speed Gauge when the voice files are present, otherwise
  Transmitter.
- **FR-033**: At startup the app MUST check that the voice files are
  installed. It uses the app voice only if they are. Any callout it can't
  fully speak in the app voice falls back to the transmitter's voice: a
  number above 500, or a missing file. Warnings fall back to DFM's
  recordings. A fallback MUST never silence a warning.
- **FR-034**: The voice files MUST be generated by a script in the repo
  (`tools/voice/`) from one Piper voice model, so every file matches in
  voice, loudness and pacing. Each file is:
  - mono, 16-bit, at a sample rate the transmitter supports (16 or 22.05 kHz);
  - trimmed of leading and trailing silence;
  - normalized to a common loudness.
  The script MUST be re-runnable to switch voice or regenerate the set.
- **FR-035**: Generated voice files MUST NOT be committed to the repository;
  `.gitignore` covers them. The Amy voice model is CC BY-SA 4.0, and the
  license of the recordings it was trained on is undocumented. The repo holds
  the generator and the instructions, and each developer generates the files
  locally before deploying.
- **FR-036**: `CREDITS.md` MUST credit Piper (MIT) and the Amy voice model
  (CC BY-SA 4.0, Mycroft / Rhasspy). The generated voice folder MUST contain
  a short credits note carrying that attribution.
- **FR-037**: DFM's original warning recordings stay in the asset folder as
  the fallback set, with their existing credit.

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
- **SC-007**: Running the app does not noticeably slow the transmitter, and no
  single call comes close to the transmitter's per-call limit. The CPU figure
  in the app overview is the highest share of a single call's budget seen
  since the app started (the transmitter kills a script at 100%). It stays
  below 50% with every window shown, full screen included, leaving at least 2x
  headroom. (Revised 2026-09-27: the original "below 20% during flight"
  assumed the figure was an overall load. Measured in the emulator: start-up
  24%, loop 0–1%, single/double draw up to 18%, full-screen draw up to 43%;
  the user accepted this with the full-screen glow as designed.)
- **SC-008**: Every behavior of the original app is either kept or listed in
  this spec as deliberately changed. No setting disappears without
  explanation.
- **SC-009**: In the app voice, a number-plus-unit callout plays with no
  audible gap: the pause between the number file and the unit file is under
  0.15 s. A number-only callout (used below landing speed and in continuous
  mode, FR-008) for any value up to 199 lasts at most 1.3 s, so it fits the
  default 2-second interval. Measured with the Amy voice, "one hundred
  twelve" is 1.14 s. Longer callouts with units ("eighty-five miles per
  hour" is about 2.0 s) happen only at the slower automatic intervals, and
  FR-007 stops them queueing up. The generator MAY speed up speech slightly
  (Piper's length scale) if flight testing shows callouts lag.
- **SC-010**: With the voice files removed, every callout and warning in
  quickstart still sounds, in the transmitter voice or DFM's recordings. None
  is silent.

## Assumptions

- **Target and baseline.** The gauge targets the DS-24 II / DC-24 II
  (firmware 6.x) only, using the Lua window sizes measured on the
  transmitter (150 × 23, 150 × 68 and 316 × 159), not the panel's
  480 × 480 or the emulator's larger windows. The original app was tested
  only on the original DS-24. The original's
  behavior (v2.1) is the baseline; where this spec is silent, match it.
- **Audio.** Speed Gauge's own voice set (Amy) is the primary audio when
  installed. DFM's original WAV files (stall warning, overspeed, airspeed
  alive, "stall speed warning at", cal factor) stay as the fallback
  (FR-033, FR-037).
- **Voice files are generated, not committed.** The full set is roughly 510
  short files, about 10–15 MB, in `AG-SpdGa/voice/`. That is fine on the
  SD card but not for git, and the voice's licensing is unclear (FR-035).
- **Pitot sensors report indicated airspeed.** They convert pressure to speed
  using fixed sea-level air density. This holds for the sensors the original
  was tested with (Jeti MSpeed, Digitech, ASSI, Xicoy). A sensor that already
  corrects for density would be double-corrected if correction is on, so the
  in-app help MUST tell the user to leave correction off for such sensors.
- **GPS warnings use ground speed.** With a GPS source, stall and landing
  checks compare ground speed to the settings. Wind makes these approximate;
  the help text says so.
- **Density correction scope.** Correction uses field elevation plus
  temperature, assuming standard sea-level pressure at that elevation.
  Temperature can come from a sensor (FR-038). Live pressure from a sensor is
  out of scope for v1: the MSpeed EX doesn't report it, and standard pressure
  is accurate enough for announcements (typically within a few percent).
- **MSpeed temperature.** Per its manual, the MSpeed EX reports temperature
  alongside airspeed. The manual doesn't say whether this is outside-air or
  housing temperature, hence the warm-fuselage caveat. It is unconfirmed
  whether the MSpeed 450 EX reports temperature.
- **Calibration file dropped.** The original's per-model calibration file
  (`DFM-<model>.jsn`) is not carried over; the calibration setting is saved
  per model like everything else.
- **Session max** is not logged to file or saved. Logging it to the
  transmitter's telemetry log is a possible later feature.
- **English only.** Labels and callouts are English for v1. The app voice is
  US English. With Voice set to Transmitter, spoken numbers and units follow
  the transmitter's language.
- **New app, new settings.** The app is named "Speed Gauge" (shown in the
  transmitter's app list and menu). Its script is `AG-SpdGa.lua`, with assets
  in `AG-SpdGa/`, following the repo's naming convention. Because the filename
  differs, it installs next to DFM-SpdA. Settings are not imported from the
  original. Density math and gauge drawing are candidates for shared `lib`
  modules, since other apps may reuse them; the plan decides.

