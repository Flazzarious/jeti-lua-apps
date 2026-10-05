# Feature Specification: Flameout Alarm

**Feature Branch**: `003-flameout-alarm`

**Created**: 2026-10-04

**Status**: Draft

**Input**: User description: "Flameout Alarm, an in-flight telemetry app that
warns the pilot by sound and on screen when the turbine appears to have flamed
out" (source: `docs/drafts/flameout-alarm.md`, 2026-10-02, alarm sound
approved by Aaron the same day).

## Overview

**Flameout Alarm** is a transmitter app that watches a turbine's RPM telemetry
and raises an immediate, unmistakable alarm when the engine spools down while
the pilot expects it to be running.

**Problem.** A turbine flameout in flight is easy to miss. The model keeps
flying, the engine noise is already distant, and the pilot may not notice the
loss of thrust until the model is slow, low or out of glide range. Many ECUs
send RPM over telemetry, so the transmitter can tell the moment the engine
spools down.

**Why an app and not a native alarm.** The transmitter's own telemetry alarms
can fire on "RPM below X", optionally gated by a switch, but they can't tell
"the engine has not started yet" from "the engine was running and stopped".
A native low-RPM alarm therefore also sounds through the whole start sequence
and after every shutdown. This app adds **arming**: it alarms only after the
engine has demonstrably been running at idle or above.

The app only listens and informs. It never controls the model or changes any
transmitter setting (constitution principle I), and it does not replace the
ECU's own failsafe, shutdown or auto-restart logic.

Proposed script name: `AG-FlmOt.lua`, menu name "Flameout Alarm". The
filename becomes permanent at first release (constitution V).

### Terms used in this spec

- **Idle RPM**: the idle speed specified in the engine's ECU setup, typed in
  by the pilot. The engine settles to it after a start. Both thresholds
  below are set as percentages of it.
- **Start overshoot**: at the end of a start or relight, RPM typically rises
  above idle RPM and then decays slowly back down to it. By then the engine
  is running on its own.
- **Arming threshold**: an RPM somewhat below idle RPM (default 90% of it).
  RPM at or above it counts as "engine running". It sits below the settled
  idle so normal idle wander doesn't keep crossing it, and above any RPM the
  engine reaches before it is running on its own.
- **Startup range**: RPM below the arming threshold, reached while the
  starter and ignition spin the engine during a start or an ECU auto-restart.
- **Flameout threshold**: an RPM below the arming threshold (default 70% of
  idle RPM). Falling below it while armed is treated as a flameout.
- **Arming time**: how long RPM must stay at or above the arming threshold
  before the app arms, or before an active flameout clears after a relight.

In order, from low to high: startup range < flameout threshold < arming
threshold < idle RPM < start overshoot.
- **Detection delay**: how long RPM must stay below the flameout threshold
  before the alarm starts.
- **Cut switch**: the throttle safety switch and its Cut (engine off)
  position. Selected in this app independently of any other app.
- **Alarm cycle**: one 5-second repetition of the alarm sound: the voice
  callout "Flameout! Flameout! Flameout!" followed by the lock tone.

## Clarifications

### Session 2026-10-04

- Q: Is a Cut switch required before monitoring can be turned on? → A: Yes.
  Monitoring needs both an RPM sensor and a Cut switch. Without one, every
  normal shutdown of an armed engine would sound the alarm (FR-003, FR-005).
- Q: How does the pilot silence an active alarm? → A: With the Cut switch
  only. There is no separate acknowledge action; the draft's "acknowledged
  Flameout" state is dropped. Cut stops the alarm and disarms (FR-016,
  FR-019). Context: the transmitter passes key presses to an app only while
  its settings screen is open, so a key on the main screen was not an option.
  Moving to Cut also commands the ECU to shut down, so it ends any
  auto-restart attempt; a pilot who wants the auto-restart to finish hears the
  alarm until the engine relights.
- Q: Turbine starts overshoot idle and then decay slowly back to the ECU's
  idle (raised by the user). How should idle be determined and used? → A:
  For this release, idle RPM is **typed in only**: the pilot enters the idle
  specified in the ECU setup. The draft's "learn idle" helper is dropped,
  since learning during the decay would record too high a value. Arming and
  relight use a separate **arming threshold** set as a percentage below idle
  (default 90%), so the settled idle and its normal wander sit safely above
  it, while the overshoot simply counts as running (FR-006, FR-007). This
  replaces the earlier assumption of no idle tolerance in v1.
- Q: What does the app show on screen? → A: A double-size telemetry window
  showing RPM with a marker at idle RPM and the RPM as a number, in Speed
  Gauge's color scheme. The earlier plan to list the threshold values in the
  window is dropped: they don't fit at 150 × 68 and are already shown in
  settings.
- Q: What should the double-size layout look like? → A: Like a motorsport
  dash tachometer (the user supplied a Haltech iC-7 dash layout as the
  reference): a segmented sweep bar that curves upward and grows toward the
  high end, with the large RPM number under it. A plain straight bar with
  the number above it is the fallback if the sweep doesn't work on the
  transmitter, and is the layout for single size (User Story 7,
  FR-031–FR-031c).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Hear a flameout the moment it happens (Priority: P1)

A pilot flying a turbine model has the app enabled and configured. In flight,
the engine flames out. Within the detection delay the transmitter starts the
alarm: "Flameout! Flameout! Flameout!" in the app voice, then a rapid
missile-lock beeping, repeating every 5 seconds. The app's telemetry window
shows a large "FLAMEOUT" and the stick vibrates where the transmitter supports
it. The alarm continues until the engine relights and holds at or above the
arming threshold, or the
pilot moves the Cut switch to Cut.

**Why this priority**: This is the reason the app exists. Everything else
supports a timely, correct alarm.

**Independent Test**: In the emulator, with a simulated RPM sensor and the
app enabled, raise RPM above the arming threshold for longer than the arming
time, then drop
it to zero. The alarm must start within (detection delay + 0.5 s) and repeat
its 5-second cycle until stopped.

**Acceptance Scenarios**:

1. **Given** the app is Armed and the Cut switch is not in Cut, **When** RPM
   stays below the flameout threshold for the detection delay, **Then** the
   alarm starts, the telemetry window shows FLAMEOUT, and the stick vibrates
   if supported.
2. **Given** the alarm is active, **When** 5 seconds pass from the start of a
   callout, **Then** the next callout starts, with the lock tone filling the
   time between callouts.
3. **Given** the app is Armed, **When** RPM dips below the flameout threshold
   for less than the detection delay (a glitch or single bad sample), **Then**
   no alarm sounds.
4. **Given** another app is speaking when the alarm starts or a callout is
   due, **Then** the alarm interrupts or pre-empts it rather than waiting
   behind it.

---

### User Story 2 - Silence during normal operation (Priority: P1)

A pilot powers on, starts the turbine, idles, taxis, flies with run-ups and
throttle chops to idle, lands, and shuts down with the Cut switch. The app
makes no flameout alarm at any point. It arms quietly once RPM has held at or
above the arming threshold for the arming time, typically during the start
overshoot or at the settled idle (with an optional short "armed"
confirmation), and disarms silently when the Cut switch goes to Cut.

**Why this priority**: An alarm that cries wolf gets ignored or turned off.
False alarms make the app worse than no app, so this is as important as the
alarm itself.

**Independent Test**: Replay or simulate a full normal flight profile
(power-on, start sequence with RPM rising through the startup range,
overshooting idle and decaying back to it, idle, run-ups, chops to idle,
landing, Cut). Zero flameout alarms.

**Acceptance Scenarios**:

1. **Given** the model has just loaded with monitoring on, **When** RPM is
   zero, invalid or anywhere in the startup range, **Then** the app stays
   Disarmed and silent.
2. **Given** the app is Disarmed and the Cut switch is not in Cut, **When**
   RPM holds at or above the arming threshold for the arming time, **Then**
   the app becomes Armed (with the optional "armed" confirmation if enabled).
3. **Given** the start overshoots idle and RPM then decays slowly to the
   settled idle, **Then** RPM never falls below the arming threshold, the app
   arms and stays Armed, and no alarm sounds.
4. **Given** the app is Armed, **When** the pilot chops throttle from full to
   idle, **Then** RPM stays above the flameout threshold and no alarm sounds.
5. **Given** the app is Armed, **When** the pilot moves the Cut switch to Cut,
   **Then** the app disarms immediately and silently, and the following
   spool-down never alarms.
6. **Given** a start fails or is aborted before RPM holds at or above the
   arming threshold for the arming time, **Then** the app never arms and
   never alarms.

---

### User Story 3 - Per-model setup with an assigned RPM sensor (Priority: P1)

Not every turbine sends RPM telemetry. The pilot opens the app's settings on a
turbine model whose ECU sends RPM, picks that sensor from the model's
telemetry sensors, selects the Cut switch and its Cut position, types in the
idle RPM (and, optionally, the max RPM for the bar display) from the ECU
setup, checks the arming and flameout thresholds
(percentages of idle), arming time and detection delay, and turns monitoring
on. Each model keeps its
own settings; on every other model the app stays off.

**Why this priority**: The alarm cannot work without a correct sensor and
thresholds, and a model without RPM telemetry must never alarm.

**Independent Test**: On a fresh model, open settings: monitoring is off and
cannot be turned on until a sensor and a Cut switch are assigned. Assign both
and enable.
Switch to a second model: monitoring is off there. Restart the transmitter:
both models keep their settings.

**Acceptance Scenarios**:

1. **Given** a model where the app has never been configured, **Then**
   monitoring is off and the telemetry window shows OFF.
2. **Given** no RPM sensor or no Cut switch is assigned, **When** the pilot
   tries to turn monitoring on, **Then** it stays off and the settings screen
   says which one must be assigned first.
3. **Given** the model's sensor list is empty, **When** the pilot opens
   settings, **Then** the screen explains that the turbine's ECU must send RPM
   telemetry and that telemetry must have been received at least once
   (transmitter and receiver powered on).
4. **Given** the pilot types in idle RPM, **Then** settings show the arming
   and flameout thresholds in RPM, computed from their percentages, next to
   the percentages.
5. **Given** the pilot sets a flameout threshold at or above the arming
   threshold, or an arming threshold at or above idle RPM, **Then** settings
   refuse the value and explain why.
6. **Given** monitoring is enabled on model A, **When** the pilot loads model
   B, **Then** monitoring is off on model B unless it was enabled there.

---

### User Story 4 - Auto-restart and relight (Priority: P2)

The engine flames out and the ECU tries an auto-restart. While the starter and
ignition push RPM up through the startup range, the alarm keeps going. If the
engine relights and RPM holds at or above the arming threshold for the arming
time (usually while it overshoots idle), the alarm clears, the app returns to
Armed, and it can announce "relit" (optional). As RPM then decays to the
settled idle it stays above the arming threshold, so the app stays Armed. If the restart fails and RPM falls back, the original flameout
stays active and no second alarm event starts.

**Why this priority**: Without this, an auto-restart attempt could falsely
clear the alarm while the engine is still not producing thrust, or produce a
confusing stream of new alarms.

**Independent Test**: Simulate a flameout, then an RPM profile that climbs
through the startup range, falls back, climbs again, overshoots idle and
decays to it. The alarm must not clear in the startup range, must clear
within (arming time + 0.5 s) of RPM holding at or above the arming
threshold, must stay clear through the decay, and must never start a second
event.

**Acceptance Scenarios**:

1. **Given** the alarm is active, **When** RPM rises anywhere within the
   startup range, **Then** the alarm continues.
2. **Given** the alarm is active, **When** RPM holds at or above the arming
   threshold for the arming time, **Then** the alarm stops, the app returns
   to Armed, and the optional "relit" callout plays.
3. **Given** the alarm has just cleared on a relight overshoot, **When** RPM
   decays to the settled idle, **Then** the app stays Armed and silent.
4. **Given** the alarm is active, **When** RPM wobbles within the startup
   range and falls back, **Then** the same alarm continues and no second
   alarm event starts.

---

### User Story 5 - Stop the alarm with the Cut switch (Priority: P2)

The pilot has heard the alarm and is setting up the dead-stick landing. They
move the Cut switch to Cut, as they would to secure a dead engine. All alarm
sound stops at once and the app goes to Disarmed. It does not alarm again
until the engine has been restarted and RPM has held at or above the arming
threshold for the arming time with the switch out of Cut.

**Why this priority**: A continuous alarm during a dead-stick approach is a
distraction once the pilot knows. Using the switch the pilot already reaches
for avoids a second control.

**Independent Test**: Trigger the alarm in the emulator, move the Cut switch
to Cut: sound stops at once, the window shows DISARMED, and no further
callouts follow while RPM stays low.

**Acceptance Scenarios**:

1. **Given** the alarm is active, **When** the pilot moves the Cut switch to
   Cut, **Then** all alarm sound stops at once, mid-callout or mid-beep, and
   the app is Disarmed.
2. **Given** the app was disarmed by Cut after a flameout, **When** RPM stays
   low or moves within the startup range, **Then** no alarm sounds.
3. **Given** the app was disarmed by Cut, **When** the switch leaves Cut and
   RPM holds at or above the arming threshold for the arming time, **Then**
   the app is Armed again and a
   later flameout alarms normally.

---

### User Story 6 - Tell telemetry loss apart from a flameout (Priority: P2)

While the app is Armed, the RPM sensor stops reporting valid data (receiver
out of range, ECU converter unplugged). The app gives a distinct "telemetry
lost" warning, never the flameout alarm, and shows NO TELEMETRY. When valid
data returns, the app continues from the RPM it then sees.

**Why this priority**: The pilot's response to a dead engine and to lost
telemetry is different; confusing them is dangerous.

**Independent Test**: With the app Armed in the emulator, stop the simulated
RPM sensor. The "telemetry lost" warning plays, not the flameout alarm, and
the window shows NO TELEMETRY.

**Acceptance Scenarios**:

1. **Given** the app is Armed, **When** RPM data stops being valid, **Then**
   the app gives the "telemetry lost" warning and shows NO TELEMETRY, and the
   flameout alarm does not sound.
2. **Given** the model loads and telemetry has never been received, **Then**
   the window shows NO TELEMETRY and the app never alarms.
3. **Given** NO TELEMETRY while Armed, **When** valid data returns with RPM at
   or above the arming threshold, **Then** the app is Armed again with no
   alarm.

---

### User Story 7 - RPM bar display (Priority: P2)

The pilot places the app's telemetry window on the main screen at double
size. It looks like a motorsport dash tachometer (design reference: a
Haltech iC-7 dash layout, kept locally as `docs/vendor/rpm-bar-reference.png`,
not committed). The RPM is a **segmented sweep bar**: a row of blocks running
left to right that curves upward and grows taller toward the high-RPM end.
Segments light up from the left as RPM rises; unlit segments stay visible as
dim outlines. A marker on the sweep shows idle RPM. The RPM is a large number
in the open space under the sweep, labeled "RPM", and the app's state (OFF,
DISARMED, ARMED, FLAMEOUT, NO TELEMETRY) is shown in the window. The pilot
can see at a glance that the engine is running, how far above idle it is,
and that the app is armed before take-off. On a flameout, FLAMEOUT takes
over the window. Colors follow Speed Gauge (dark face, bright colors), not
the reference's amber.

At single size the window falls back to a simple straight bar with an idle
marker beside the RPM number.

**Why this priority**: It's the pilot's everyday view of the engine and
confirms the app is armed before take-off. The audio alarm still carries the
safety value, so it ranks below the P1 stories.

**Independent Test**: Place the window at double size in the emulator, drive
the simulated RPM from 0 through idle to max and back, and step through each
state. The bar tracks RPM, the idle marker sits at idle RPM, the number
matches the sensor, and everything fits and reads clearly in the 150 × 68
transmitter window.

**Acceptance Scenarios**:

1. **Given** valid RPM, **Then** the lit segments of the sweep are in
   proportion to RPM between zero and the bar's full-scale RPM, and the
   number shows the current RPM.
2. **Given** idle RPM is entered, **Then** a marker on the sweep shows where
   idle RPM sits, and the lit segments reach the marker when RPM equals idle
   RPM.
3. **Given** RPM above full scale, **Then** the bar shows full and the number
   still shows the true RPM.
4. **Given** each app state, **Then** the window shows the matching state
   label.
5. **Given** NO TELEMETRY or OFF, **Then** no segments are lit, the number
   shows no value (e.g. "---"), and the state label says why.
6. **Given** the alarm is active, **Then** FLAMEOUT is the dominant element
   of the window, in the alarm color.
7. **Given** the window is placed at single size, **Then** it shows a
   straight bar with the idle marker, the RPM number and the state.

### Edge Cases

- **Turbine has no RPM sensor.** The user leaves monitoring off; the app stays
  silent and shows OFF. Adding the app to such a model never causes alarms.
- **User tries to enable with no sensor assigned.** Blocked, with an
  explanation.
- **No telemetry sensors listed at setup** (receiver off, or ECU not sending).
  Setup explains that telemetry must be received once before a sensor can be
  assigned.
- **Throttle chop from full to idle.** RPM falls fast but stays above the
  flameout threshold. No alarm. This drives how far below idle the default
  threshold sits.
- **Brief telemetry dropout or a single bad sample.** The detection delay
  rides it out; no alarm.
- **Sensor reports 0 or invalid at power-on.** Stays Disarmed.
- **Failed start or hot-start abort.** RPM never holds at or above the
  arming threshold for the arming time, so no arming and no alarm.
- **Start overshoot and slow decay to idle.** RPM rises above idle RPM, then
  decays back to it over several seconds. The app arms during the overshoot
  or at the settled idle, and the decay never crosses the arming threshold,
  so it stays Armed. No alarm.
- **ECU auto-restart after flameout.** The alarm keeps going until RPM holds
  at or above the arming threshold for the arming time (usually during the
  relight overshoot), then clears and the app re-arms. The decay to settled
  idle that follows does not disturb it.
- **Auto-restart fails partway.** RPM rises into the startup range and falls
  back. No clear, no second alarm; the original flameout stays active.
- **Startup RPM peaks close to the arming threshold.** If the engine reaches
  the arming threshold before it is running on its own, a failed restart
  could clear the alarm early. The README explains the rule, and the arming
  percentage can be raised for such an engine.
- **Idle RPM typed in wrong.**
  - Too high (e.g. the pilot entered a run-up RPM): the settled idle sits
    below the arming threshold. The app arms only on a run-up, and after a
    relight the alarm keeps sounding at idle until the pilot opens the
    throttle.
  - Too low: the thresholds sit lower than intended, so the alarm comes
    later in a spool-down and a restart can clear it sooner.
  - Settings show the live RPM next to the typed idle so the pilot can
    compare them with the engine idling, and the README explains both cases.
- **Settled idle wanders** (temperature, altitude, fuel). The arming
  threshold sits a margin below idle RPM (default 10%), so normal wander
  doesn't cross it.
- **Relight or Cut mid-callout or mid-beep.** All alarm sound
  stops at once; no further callouts.
- **Another app (e.g. Speed Gauge) is speaking when the alarm fires or a
  callout is due.** The alarm interrupts or pre-empts it.
- **Alarm audio file missing** (for example, the voice file was not
  generated). The app falls back to the transmitter's built-in beeps plus the
  on-screen FLAMEOUT, and settings shows "voice files missing". A missing file
  never silences the alarm.
- **Pilot flips to Cut during the alarm.** The alarm stops; the state becomes
  Disarmed. This is the only way to silence the alarm without a relight.
- **Pilot wants the ECU auto-restart to finish.** Cut would end the restart,
  so the alarm keeps sounding until the engine relights and holds at or above
  the arming threshold, or the pilot gives up and moves to Cut.
- **Cut switch unassigned or missing** (e.g. a model copied from one with a
  different switch layout). Monitoring cannot be enabled without it; if it
  disappears after enabling, the app treats monitoring as off and settings say
  why.
- **Wrong sensor selected** (e.g. EGT instead of RPM). Setup warns if the
  sensor's unit isn't RPM-like, or if its value never changes.
- **Assigned sensor disappears** after an ECU swap, receiver rebind or model
  copy. The app shows "sensor not found" and stays Disarmed instead of
  erroring; the user can re-assign it or turn monitoring off.
- **Model copied from another model.** The copied sensor assignment may not
  exist on the new model's receiver; handled as above.
- **Thresholds set nonsensically** (flameout threshold at or above the
  arming threshold, or arming threshold at or above idle RPM). Setup blocks
  it and explains.
- **RPM above the bar's full scale** (max RPM entered too low, or not
  entered and the default multiple is too small). The bar shows full; the
  number still shows the true RPM.
- **Max RPM entered at or below idle RPM.** Settings refuse it and explain.
- **Idle RPM never entered.** There is no sensible default (idle differs
  widely between engines), so monitoring can't be turned on until it is.
- **Two engines.** Out of scope for v1 (see Assumptions).

## Requirements *(mandatory)*

### Functional Requirements

**Configuration and per-model state**

- **FR-001**: Monitoring MUST be off by default on every model.
- **FR-002**: Users MUST be able to assign the RPM sensor from the model's
  telemetry sensors.
- **FR-003**: Monitoring MUST NOT be able to be turned on until an RPM
  sensor and a Cut switch are assigned and idle RPM is entered. The settings
  screen MUST say which is missing when the user tries.
- **FR-004**: When the model has no telemetry sensors listed, the settings
  screen MUST explain that the ECU must send RPM telemetry and that telemetry
  must have been received at least once.
- **FR-005**: Users MUST be able to select the Cut switch and its Cut
  position. A Cut switch is required for monitoring (FR-003).
- **FR-006**: Users MUST set idle RPM by typing in the idle specified in the
  ECU setup. It has no default. There is no automatic or learned idle in this
  release.
- **FR-007**: Users MUST be able to set the arming threshold and the
  flameout threshold as editable percentages of idle RPM, defaulting to 90%
  and 70% (see Assumptions). Settings MUST show each one's RPM value next to
  its percentage. Settings MUST refuse an arming threshold at or above idle
  RPM, and a flameout threshold at or above the arming threshold.
- **FR-008**: Users MUST be able to set the arming time (default 3 s) and the
  detection delay (default 1.0 s).
- **FR-009**: Users MUST be able to turn the optional "armed" and "relit"
  confirmations on or off (both default off).
- **FR-010**: Setup MUST warn when the assigned sensor's unit isn't RPM-like,
  and MUST show the live RPM next to the typed idle RPM so the pilot can check
  it against the idling engine.
- **FR-011**: All settings MUST be saved per model and survive a transmitter
  restart. Enabling the app on one model MUST NOT enable it on another.

**Off state**

- **FR-012**: When monitoring is off, or the RPM sensor, Cut switch or idle
  RPM is missing, the app MUST produce no sounds, vibration or warnings in any scenario, including
  telemetry loss, and its telemetry window MUST show OFF.

**Arming and detection**

- **FR-013**: When monitoring is on, the app MUST start Disarmed at model
  load, and RPM that is zero, invalid or within the startup range MUST keep
  it Disarmed.
- **FR-014**: The app MUST arm only when the Cut switch is not in Cut and RPM
  has stayed at or above the arming threshold for the arming time. RPM above
  idle RPM (the start overshoot) counts toward arming like any RPM at or
  above the arming threshold.
- **FR-015**: While Armed, the app MUST raise the flameout alarm when RPM has
  stayed below the flameout threshold for the detection delay and the Cut
  switch is not in Cut.
- **FR-016**: Moving the Cut switch to Cut MUST disarm the app immediately and
  silently from any state, stopping any alarm sound at once.
- **FR-017**: While in Flameout, RPM within the startup range MUST NOT clear
  the flameout and MUST NOT start a new alarm event.
- **FR-018**: A flameout MUST clear only when RPM has stayed at or above the
  arming threshold for the arming time (or when the Cut switch goes to Cut). On clearing by
  relight the app MUST return to Armed and play the "relit" confirmation if
  enabled.
- **FR-019**: The Cut switch MUST be the only way for the pilot to silence an
  active alarm. There is no separate acknowledge action.

**Telemetry loss**

- **FR-020**: When the RPM sensor stops reporting valid data while Armed or in
  Flameout, the app MUST give a "telemetry lost" warning that is clearly
  different from the flameout alarm, and MUST show NO TELEMETRY. Telemetry
  loss MUST never trigger the flameout alarm.
- **FR-021**: When valid data returns, the app MUST resume from the RPM it
  then sees: Armed if RPM is at or above the arming threshold, otherwise following the
  normal detection rules (the detection delay restarts).
- **FR-022**: If the assigned sensor is not found among the model's sensors,
  the app MUST show "sensor not found", stay Disarmed and not error.

**Alarm sound**

- **FR-023**: The alarm MUST repeat a 5-second cycle: a voice callout
  "Flameout! Flameout! Flameout!" (about 2 s), then a rapid, high-pitched
  lock tone filling the rest of the cycle. A new callout MUST start every
  5 s (±0.3 s), callout start to callout start, with no audible gap or
  overlap between callout and tone.
- **FR-024**: The alarm MUST continue until cleared by relight or stopped by
  Cut.
- **FR-025**: The alarm MUST interrupt or pre-empt speech from other apps
  rather than queue behind it.
- **FR-026**: The callout MUST use the same Piper "Amy" voice as Speed Gauge
  (Speed Gauge spec, User Story 6 and FR-030–FR-037), so all AG- apps sound
  consistent, but delivered urgently: about 30% faster, pitch raised about one
  semitone without changing speed, with presence boost and light compression
  so it cuts through wind and engine noise. The approved processing settings
  are recorded in `docs/drafts/flameout-alarm.md`.
- **FR-027**: The lock tone MUST match the approved sample: about 1800 Hz with
  a 3600 Hz overtone, 45 ms on / 35 ms off with short fades (12.5 beeps per
  second).
- **FR-028**: Both alarm sounds MUST be audio files in the app's own asset
  folder (`AG-FlmOt/`), not references to another app's files. The voice file
  MUST follow Speed Gauge's voice rules (generated locally by the repo's voice
  script from the same Amy model, not committed to git, credited for Piper
  and the Amy model in the folder and in `CREDITS.md`). The lock tone, being
  plain synthesized sound, MAY be committed.
- **FR-029**: If an alarm audio file is missing, the app MUST fall back to the
  transmitter's built-in beeps with the on-screen FLAMEOUT, and the settings
  screen MUST show "voice files missing". A missing file MUST never silence
  the alarm.
- **FR-030**: While the alarm is active, the app MUST vibrate the stick where
  the transmitter supports it.

**Display**

- **FR-031**: The app MUST provide a telemetry window designed for double
  size (150 × 68 on the transmitter, title drawn above the window). It MUST
  show:
  - the RPM as a segmented sweep bar in the style of the design reference
    (User Story 7): segments run left to right from zero to the full-scale
    RPM (FR-031b), the sweep curves upward and grows taller toward the high
    end, lit segments show the current RPM and unlit ones stay visible as
    dim outlines;
  - a marker on the sweep at idle RPM;
  - the current RPM as a large number in the space under the sweep, labeled
    "RPM";
  - the state: OFF, DISARMED, ARMED, FLAMEOUT or NO TELEMETRY.
  FLAMEOUT MUST be the dominant element while the alarm is active. If the
  sweep proves unreadable or too costly to draw on the transmitter, the
  layout MAY fall back to the straight-bar layout of FR-031c scaled up to
  double size, with the number above the bar.
- **FR-031a**: The window MUST follow Speed Gauge's look (Speed Gauge
  research R8): an always-dark face, white numbers, light grey labels, cyan
  lit segments, dim grey unlit segment outlines and a yellow idle marker by
  default. Red or orange is used only
  for the flameout alarm, so nothing else on the display can be mistaken for
  it.
- **FR-031b**: Users MUST be able to enter the engine's maximum RPM from the
  ECU setup as the bar's full-scale RPM. If it isn't entered, the bar scales
  to a default multiple of idle RPM (see Assumptions). Max RPM affects only
  the display, never arming or detection, and MUST be above idle RPM.
- **FR-031c**: If the window is placed at single size (150 × 23), it MUST
  show a straight horizontal bar filling left to right with the idle marker,
  the RPM number beside it, and the state. Full screen is out of scope.

**Safety and footprint**

- **FR-032**: The app MUST NOT drive any output or change any transmitter or
  model setting. It only reads telemetry and switches, plays sound, vibrates
  and draws (constitution I).
- **FR-033**: The app MUST install standalone: its script and its own asset
  folder, plus any shared lib modules, which the plan, install instructions
  and any release package MUST list. It MUST NOT depend on any other app.
- **FR-034**: When monitoring is off, the app's per-cycle work MUST be
  negligible.
- **FR-035**: The README MUST state that the app is advisory, does not replace
  the ECU's failsafe, shutdown or auto-restart logic nor the pilot's own
  monitoring, and only works on turbines that send RPM telemetry. It MUST
  also explain: entering idle RPM from the ECU setup; the start overshoot and
  why the arming threshold sits below idle; the arming threshold having to
  stay above any RPM the engine reaches before it runs on its own; and the
  effects of an idle typed too high or too low.

### Key Entities

- **Model configuration** (one per model): monitoring enabled, assigned RPM
  sensor, Cut switch and position, idle RPM (typed in), max RPM for the bar
  display (optional), arming threshold and
  flameout threshold (as percentages of idle RPM), arming time, detection
  delay, confirmation toggles.
- **Engine monitor state** (in memory, reset on model load): one of Off,
  Disarmed, Armed, Flameout, No telemetry;
  plus the timers for arming, detection and the alarm cycle.
- **Alarm assets**: the urgent voice callout and the lock tone, in the app's
  own folder, with their credits.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In replayed or emulated flameout profiles, the alarm starts
  within (detection delay + 0.5 s) of RPM crossing below the threshold in
  100% of runs.
- **SC-002**: Zero alarms across a full normal flight profile: power-on,
  start sequence (including the overshoot above idle and the slow decay back
  to it), idle, run-ups, throttle chops to idle, landing, and shutdown
  via the Cut switch.
- **SC-003**: Zero flameout alarms before the app first arms (start
  sequence, failed starts, cool-down).
- **SC-004**: Telemetry loss produces the "telemetry lost" warning, never the
  flameout alarm, in 100% of tests.
- **SC-005**: A pilot can enable the app for a model and configure sensor,
  switch and thresholds in under 3 minutes without any other manual.
- **SC-006**: The app never changes any transmitter output or setting (servo
  outputs and model file unchanged after a session with no user edits).
- **SC-007**: Copying only the app's files (plus any listed lib modules) to
  `/Apps` on a transmitter with no other AG- apps is enough to load and run.
- **SC-008**: No "CPU limit" errors over a 30-minute emulator session with the
  app enabled and alarming at least once.
- **SC-009**: On a model where monitoring is off (the default), or the RPM
  sensor, Cut switch or idle RPM is missing, the app produces zero sounds or
  warnings in any scenario, including telemetry loss.
- **SC-010**: Enable state and sensor assignment are kept per model: enabling
  it on model A does not enable it on model B, and both settings survive a
  transmitter restart.
- **SC-011**: In replayed auto-restart profiles, the flameout alarm never
  clears while RPM is in the startup range, clears within (arming time +
  0.5 s) of RPM holding at or above the arming threshold, stays clear while
  RPM decays from the relight overshoot to idle, and fires no second alarm
  for the same flameout, in 100% of runs. A failed restart leaves the alarm
  active.
- **SC-012**: While the alarm is active, a callout starts every 5 s (±0.3 s),
  the lock tone plays between callouts with no audible gap or overlap, and the
  cycle continues until relight or Cut, in 100% of tests.
- **SC-013**: At double size on the transmitter, a pilot can read the RPM
  number, the bar's position relative to the idle marker, and the state at a
  glance (under 1 second) with nothing clipped. The display reflects an RPM
  change within 1 second.

## Assumptions

- **Script name** `AG-FlmOt.lua` ("Flameout Alarm") is used unless changed
  before first release.
- **Default thresholds** are placeholders until real RPM logs are reviewed
  (draft open question 4): arming threshold 90% of idle RPM, flameout
  threshold 70% of idle RPM, arming time 3 s, detection delay 1.0 s. Settled
  idle is assumed to wander by less than 10%, and a throttle chop is assumed
  to settle at idle without dipping far below it, so 70% leaves margin.
- **The startup range stays clearly below 90% of idle** on the user's ECUs
  during starts and auto-restarts, i.e. the engine is running on its own
  before it reaches the arming threshold (draft open question 2, to confirm
  from logs).
- **Start overshoot** decays to idle without dipping below the arming
  threshold. Logs should confirm the overshoot height, decay time and how
  much settled idle wanders; they set the 90% default.
- **Idle RPM is typed in only** in this release, from the ECU setup. A
  "learn idle" helper or an idle derived automatically each session is a
  possible later extension; either would need to wait for the overshoot to
  decay before recording.
- **Bar full scale** defaults to 4 × idle RPM when max RPM isn't entered.
  Typical model turbines reach roughly 3–4.5 times their idle speed at full
  throttle, so
  this puts full throttle near the right end of the bar.
- **Display layout** in FR-031 is a starting point for design iteration in
  the plan: the number of segments (the reference has about 16; around 10–14
  is likely at 150 × 68), the curve and taper of the sweep, where the state
  label and idle marker go, and whether threshold marks join the idle
  marker. It is checked on the transmitter's 150 × 68 window, not the
  emulator's larger one. Drawing cost is checked too (constitution VI): the
  sweep is built from plain filled shapes without transparency, which Speed
  Gauge's measurements show are cheap, or from a pre-drawn image of the
  unlit sweep.
- **Detection uses a fixed RPM threshold only** in v1. Rate-of-drop
  detection and ECU status sensors are possible later extensions (draft open
  questions 3 and 5).
- **"Telemetry lost" warning** is a short spoken "Engine telemetry lost" in
  the app voice, given once per loss event, with NO TELEMETRY shown until data
  returns. It does not repeat, because the transmitter already announces
  signal loss itself.
- **One engine per model** in v1. Two-engine models are out of scope; a later
  version could monitor one RPM sensor per engine.
- **Target hardware** is the DS-24 II / DC-24 II on firmware 6.x. The
  emulator plays no Lua audio, so the alarm sound and its timing can only be
  verified on the transmitter.
- **Turbine Throttle Setup** (spec 002, separate app) uses the same physical
  safety switch, but this app selects it independently and does not read the
  other app's settings.
- API availability (sensor validity, audio playback priority and stopping,
  vibration, sensor identity across power cycles) is confirmed during
  planning; the draft's open questions 1–12 feed `/speckit-clarify` and
  `/speckit-plan`.
