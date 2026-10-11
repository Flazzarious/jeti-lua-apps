# Feature Specification: Turbine Throttle Setup

**Feature Branch**: `feature/002-turbine-throttle-setup`

**Created**: 2026-10-09

**Status**: Draft

**Input**: User description: "Turbine Throttle Setup, a one-time setup wizard
that guides the pilot through the transmitter's native turbine throttle setup
(endpoints, Throttle Cut and Throttle Idle on one two-position safety switch,
failsafe) and then proves the result by checking the live throttle output"
(source: `docs/drafts/turbine-throttle-setup.md`, 2026-10-01).

## Overview

**Turbine Throttle Setup** is a transmitter app that walks a turbine pilot
through setting up the throttle channel so a single two-position safety
switch selects between engine OFF (Throttle Cut) and engine RUN (Throttle
Idle), and then checks that the throttle channel really produces the right
pulse widths in every switch and stick position.

**Problem.** A turbine's ECU needs three throttle positions: cut, idle and
full. On a Jeti transmitter these come from four separate settings in three
different menus: servo endpoints, Throttle Cut, Throttle Idle and the
receiver failsafe. Getting any of them wrong is dangerous. A cut that
doesn't fully cut, an idle that sits too low, or a failsafe that holds the
engine at idle on signal loss all look fine on the bench until something
goes wrong. Pilots set this up rarely, so they rarely remember the details.

**Goal.** The app gives step-by-step instructions with the exact values to
enter, takes the pilot straight to each menu, and then measures the throttle
output in all four switch-and-stick states and reports pass or fail. Once
the setup has passed, the app has done its job: the pilot removes it from the
model and goes on to the ECU's own "learn transmitter" (Teach RC) step, or
skips that step if the targets already match what the ECU was taught.

**What the app can't do.** The transmitter's app interface can read stick,
switch and servo-output positions and can open the transmitter's menus, but
it cannot change model settings. The pilot makes every change by hand; the
app instructs and verifies. The app never drives any output and never
changes any setting (constitution principle I). Nothing at flight time
depends on it.

Proposed script name: `AG-TrbSt.lua`, menu name "Throttle Setup Wizard".
The filename becomes permanent at first release (constitution V).

### Reference setup (from Aaron)

This is the proven manual procedure the app guides, with its default values:

1. Set the throttle channel endpoints to ±80%.
2. Assign Throttle Cut to a two-position switch, in the position chosen as
   engine OFF.
3. Set the Throttle Cut value to −100%.
4. Assign Throttle Idle to the same switch, in the engine RUN position.
5. Set the Throttle Idle offset to 20%.
6. Set the throttle failsafe to OFF, or to −125%, and verify that it works.

With these settings the throttle channel outputs **1100 µs** in Throttle Cut,
**1200 µs** at idle and **1900 µs** at full throttle. Failsafe must give
about 1000 µs (anything outside the normal range) or no pulse at all, so the
ECU recognizes signal loss and shuts the engine down. These are the
Spektrum-era positions Aaron's ECUs were already taught, which let him skip
Teach RC. Other values work too, as long as the pilot understands exactly
what they are doing.

**The app's default targets are 1000 / 1200 / 1900 µs**, not the values
above (clarification 2026-10-10). That is the setup on Aaron's Avanti Mini
(Xicoy ECU): travel −80/+80, Throttle Cut −125%, idle offset 20%. It puts
idle at 22% of the cut-to-full range, inside every documented ECU's band.
The guide reaches the same targets with travel −100/+80, cut −100% and
idle offset 40%.

A locking two-position safety switch, mounted where it is easy to reach in an
emergency, is recommended. Aaron recommends JETI's two-position locking
switch for the DS-24 II: the lever must be pulled out to flip, so it can't
be bumped by accident in flight.

**Aaron's transmitter (example configuration, 2026-10-10).** On his DS-24 II
the throttle safety switch is **SF**, the short silver two-position toggle on
the top-right panel, next to SE (the long blue lever). The red switch on the
top edge is not the throttle switch. Photo:
[`assets/safety-switch-sf.jpg`](assets/safety-switch-sf.jpg). The photo
shows SF in the **RUN** position: Throttle Cut off, engine allowed to run
(Aaron, 2026-10-10). The other position is OFF (Throttle Cut on). Note the
wording: pilots often say "cut off" for RUN, while this spec's "OFF" means
engine off. This is an example
for testing and screenshots, not a default: the app lets every pilot choose
their own switch (FR-001).

### Terms used in this spec

- **Pulse width**: the throttle channel's output, in microseconds (µs). The
  transmitter's servo monitor shows it in percent: µs = 1500 + 5 × %.
- **Targets**: the three pulse widths the pilot wants: cut, idle and full.
  Defaults 1000 / 1200 / 1900 µs.
- **OFF / RUN position**: the two positions of the chosen safety switch.
  OFF selects Throttle Cut; RUN selects Throttle Idle.
- **Verify state**: one combination of switch position and stick position
  that the app measures. There are four (see User Story 2).
- **Idle position**: where idle sits between cut and full, as a share of
  the cut-to-full span: (idle − cut) ÷ (full − cut). Defaults: 200 ÷ 900 =
  22.2%.
- **Tolerance**: how far a measured pulse width may be from its target and
  still pass. Default ±10 µs.
- **Clean run**: one verify run in which all four states pass back to back,
  with no retries. Only a clean run counts toward "Setup complete".

## Clarifications

### Session 2026-10-10

- Q: If one verify state fails and is retried alone after a fix, do earlier
  passes still count toward "Setup complete"? → A: No. Retrying one state is
  for diagnosis only; "Setup complete" needs a clean run (all four states
  pass back to back, no retries).
- Q: When the cut and full targets aren't equally far from 1500 µs, should
  the app give different low and high endpoint values? → A: Yes. Uneven
  targets are allowed and the app shows separate low and high endpoints.
  Context from Aaron: during the ECU's Teach RC the pilot triggers each
  state and the ECU stores the µs it receives, so with Teach RC what matters
  is that each state is repeatable and clearly separated from the others.
  Exact targets matter only when Teach RC is skipped.
- Q: How should the app check where idle sits between cut and full? → A:
  As the idle position, (idle − cut) ÷ (full − cut). Refuse below 10% or
  above 30%; between 10% and 15%, warn that some ECUs (e.g. Xicoy) want at
  least 15%. Sources: Xicoy manual (idle 15–30%; ECU can't tell run from
  stop when the gap is too small), KingTech manual (idle 10–30%).
- Q: Which default targets should the app use? → A: 1000 / 1200 / 1900 µs
  (idle position 22.2%), from Aaron's Xicoy-powered Avanti Mini, replacing
  1100 / 1200 / 1900 (12.5%, which would warn). Aaron expects it to suit
  the other ECUs too.
- Q: What happens to a saved result when the pilot later changes a setup
  input? → A: Any change to a setup input (switch, OFF position, stick,
  output, targets, tolerance) clears the saved result to "Not verified",
  after a confirm prompt that says so. Context from Aaron: the app is used
  once per new model; re-running on the same model is rare, and a model
  copied from a finished one usually doesn't need it either.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Guided setup (Priority: P1)

A pilot setting up a new turbine model opens the app, chooses the safety
switch, which of its positions is OFF, and the throttle stick and throttle
output, and accepts or edits the targets. The app then shows one step per
screen, each with the menu to go to, the exact value to enter for the chosen
targets, and an "Open menu" action that takes the pilot straight to that
menu. The steps are: endpoints, Throttle Cut, Throttle Idle, failsafe, and a
safety-switch recommendation.

**Why this priority**: Getting the values right is the hard part, and the
pilot can't verify what they haven't set up. With only this story the app is
already a better checklist than a forum post.

**Independent Test**: On the emulator, with a fresh model, follow only the
instruction screens using the default targets. Then open the servo monitor
and check that the throttle reads about 1000 / 1200 / 1900 µs in the three
states.

**Acceptance Scenarios**:

1. **Given** the default targets, **When** the pilot reaches the endpoints
   step, **Then** the screen says Travel −100% / +80% and names the menu.
2. **Given** the pilot edits the targets (e.g. cut 1000, idle 1150,
   full 2000), **When** they reach each step, **Then** the values shown are
   the ones that produce those targets (FR-006).
3. **Given** any instruction step, **When** the pilot chooses "Open menu",
   **Then** the transmitter opens the relevant menu.
4. **Given** the pilot leaves the app for a menu and comes back, **Then** the
   wizard resumes at the same step with the same choices.
5. **Given** the failsafe step, **Then** the screen explains that failsafe is
   set in the receiver's settings, which the app cannot read, and must be
   tested by hand.

---

### User Story 2 - Verify the throttle output (Priority: P1)

After the setup steps, or at any time on a model already set up, the pilot
runs verify. The app prompts for each of four states in turn, waits until
the stick is held steady at the end of its travel, measures the throttle
output and shows the target, the measured value and pass or fail:

| Verify state | Switch | Stick | Expected |
| --- | --- | --- | --- |
| Cut | OFF | idle (low) | cut target |
| Cut overrides stick | OFF | full (high) | cut target |
| Idle | RUN | idle (low) | idle target |
| Full | RUN | full (high) | full target |

The second state proves that Throttle Cut really overrides the stick, not
just that the idle-stick number looks right.

**Why this priority**: This is what makes the app trustworthy. A pilot can
copy values from a checklist; only a measurement shows the model actually
does what was intended.

**Independent Test**: On the emulator, set up a model by hand for the app's
targets (default 1000 / 1200 / 1900 µs), run verify only, and check that
all four states pass.
Then introduce one fault at a time (see Edge Cases) and check that verify
fails at the right state with a useful message.

**Acceptance Scenarios**:

1. **Given** a correct setup, **When** the pilot runs verify, **Then** all
   four states pass and the measured values are within tolerance.
2. **Given** the switch is assigned backwards, **When** verify runs its
   output check, **Then** it stops and says to reverse the switch
   assignment.
3. **Given** Throttle Cut is missing or not overriding the stick, **When**
   verify reaches the cut-overrides-stick state, **Then** it fails and
   points to the Throttle Cut setting.
4. **Given** the stick is not yet at the end of its travel, **When** a state
   is being measured, **Then** the app waits and asks for the stick to be
   moved fully, and does not record a value until the stick is steady.
5. **Given** a state fails, **When** the pilot fixes the setting and retries
   that state, **Then** the app re-measures only that state.
6. **Given** a state was retried, **When** it passes, **Then** the app asks
   for a clean run of all four states before the result can count toward
   "Setup complete".

---

### User Story 3 - Failsafe confirmation and completion (Priority: P2)

Once all four states pass, the app asks the pilot to test failsafe by hand:
with the ECU powered and the fuel off, switch the transmitter off and
confirm that the ECU reports signal loss. Only when the pilot confirms this
test does the app report "Setup complete". The summary screen lists the
switch, targets, measured values and the date, and reminds the pilot that
the app can now be removed from the model and that the next step is the
ECU's Teach RC (or skipping it if the targets match what the ECU already
knows).

**Why this priority**: Failsafe is the one safety setting the app cannot
measure. Making the pilot confirm a hand test keeps "complete" honest.

**Independent Test**: On the emulator, pass verify, then decline the
failsafe confirmation and check that the result stays "Incomplete"; then
confirm it and check that the summary shows "Setup complete".

**Acceptance Scenarios**:

1. **Given** all four states passed, **When** the pilot declines or skips the
   failsafe confirmation, **Then** the status is "Incomplete — failsafe not
   confirmed".
2. **Given** all four states passed and the failsafe test is confirmed,
   **Then** the status is "Setup complete" and the summary is shown.
3. **Given** "Setup complete", **When** the pilot removes the app from the
   model, **Then** the throttle behaves exactly as it did during verify.

---

### Edge Cases

- **Switch assigned backwards** (OFF gives idle, RUN gives cut): the output
  check stops with "Switch RUN gave cut. Reverse the switch assignment."
- **Cut doesn't override the stick** (output rises with the stick while
  OFF): the cut-overrides-stick state fails and points to Throttle Cut.
- **Endpoints that don't match the values shown** (e.g. full reads
  1940 µs): the full state fails and shows expected vs. measured. Uneven
  low and high endpoints are not a fault when the targets call for them.
- **Wrong output selected** (the output doesn't move between idle and full
  stick): the app detects no change and asks the pilot to re-select the
  output before continuing.
- **Throttle reversed** (full reads lower than idle): the app detects it and
  points to servo reverse.
- **Stick not fully at the end of travel, or still moving**: the app waits
  until the stick is at the end and steady before measuring.
- **Throttle trim not centered, or digital trim active**: the verify screen
  reminds the pilot that trim shifts the readings and to center it. The app
  can't read trims, so an off-center trim shows up as idle or full failing
  by the trim amount.
- **Flight modes with different throttle settings**: the app verifies the
  current flight mode only and says so.
- **Invalid targets** (cut ≥ idle, idle ≥ full, any value outside
  900–2100 µs, or an idle position below 10% or above 30%): the app refuses
  them and explains why. Too small a cut-to-idle gap risks the ECU
  confusing run with stop after Teach RC.
- **Idle position between 10% and 15%** (e.g. 1100 / 1200 / 1900, 12.5%):
  the app accepts the targets but warns that some ECUs (e.g. Xicoy) want an
  idle position of at least 15%.
- **Targets that need settings outside what the transmitter allows** (e.g.
  endpoints above the maximum): the app says the targets can't be reached
  and why.
- **Failsafe confirmation skipped or declined**: status stays "Incomplete".
- **Model already set up**: the pilot can go straight to verify without the
  instruction steps.
- **Same switch used for other functions**: the app warns if the chosen
  switch is also assigned elsewhere, if that can be detected; otherwise the
  instructions mention it.
- **App left on the model**: it does nothing at flight time; the summary
  reminds the pilot to remove it.
- **Setup input changed after a saved result**: the app asks for
  confirmation, then clears the result to "Not verified" (FR-005a).
- **Model copied from a finished one**: the throttle settings copy with the
  model, so the pilot normally doesn't need the app. If the app and its
  saved result come along too, the summary still shows the original date;
  the pilot can run verify again to refresh it.

## Requirements *(mandatory)*

### Functional Requirements

**Setup inputs**

- **FR-001**: The app MUST let the pilot choose the safety switch and which
  of its two positions is OFF (Throttle Cut).
- **FR-002**: The app MUST let the pilot choose the throttle stick and the
  throttle output channel to measure.
- **FR-003**: The app MUST let the pilot set the three targets (cut, idle,
  full) in µs, defaulting to 1000 / 1200 / 1900, and MUST refuse invalid
  combinations. Valid targets have cut < idle < full, each within
  900–2100 µs, and an idle position from 10% to 30%. For an idle position
  from 10% up to (not including) 15%, the app MUST warn that some ECUs want
  at least 15%.
- **FR-004**: The app MUST let the pilot set the verify tolerance from 5 to
  25 µs, default 10.
- **FR-005**: All setup inputs MUST be saved per model and restored when the
  model or app is reloaded.
- **FR-005a**: Changing any setup input after a result has been saved MUST
  first ask the pilot to confirm, then clear the saved result (verify
  results, failsafe confirmation and date) to "Not verified".

**Instructions**

- **FR-006**: For the chosen targets, the app MUST show the endpoint values,
  the Throttle Cut value and the Throttle Idle offset that produce them.
  For the default targets these are travel −100% / +80%, cut −100% and
  idle offset 40%. When the cut and
  full targets are not equally far from 1500 µs, the app MUST show separate
  low and high endpoint values.
- **FR-007**: Each instruction step MUST name the menu and setting to change
  and the exact value to enter, in the transmitter's own wording.
- **FR-008**: Each instruction step that has a matching transmitter menu
  MUST offer an "Open menu" action that opens that menu.
- **FR-009**: The wizard MUST keep its current step and choices when the
  pilot leaves for a menu and comes back, and when the app is reopened.
- **FR-010**: The failsafe step MUST tell the pilot to set throttle failsafe
  to OFF (no pulse) or to a value that gives about 1000 µs, and explain why.
- **FR-011**: The app MUST recommend a locking two-position safety switch in
  an easy-to-reach position.
- **FR-012**: The pilot MUST be able to skip the instruction steps and go
  straight to verify.

**Verify**

- **FR-013**: Verify MUST measure the four states in User Story 2 and show,
  for each, the target, the measured pulse width and pass or fail.
- **FR-014**: A state MUST pass only when the measured value is within the
  tolerance of its target.
- **FR-015**: The app MUST measure a state only when the switch is in the
  required position and the stick is at the required end of its travel and
  steady.
- **FR-016**: When a state fails, the app MUST name the most likely cause
  (Edge Cases) and the setting to check, and MUST let the pilot retry that
  state alone. A retry is for diagnosis only and never counts toward
  completion.
- **FR-017**: Before measuring, the app MUST check that the selected output
  moves with the stick and in the right direction, and stop with a clear
  message if not.
- **FR-018**: The verify screen MUST remind the pilot to center the throttle
  trim (or have no trim on throttle), and MUST state that only the current
  flight mode is verified. The app cannot read digital trims or the active
  flight mode (plan research R6), so these are standing reminders, not
  detections.

**Completion**

- **FR-019**: The app MUST NOT report "Setup complete" unless the latest
  verify was a clean run (all four states passed back to back, with no
  retries) and the pilot confirmed a hand test of failsafe.
- **FR-020**: The summary MUST list the switch and OFF position, the
  targets, the measured values, the date, and the next step (remove the app;
  run or skip the ECU's Teach RC).

**Safety and independence**

- **FR-021**: The app MUST NOT drive any output or change any transmitter or
  model setting (constitution I).
- **FR-022**: The finished throttle setup MUST work with the app removed.
- **FR-023**: Every screen that asks the pilot to move the throttle MUST
  remind them that the engine must not be able to start (fuel off, or ECU
  disconnected from the engine).
- **FR-024**: The app MUST install standalone: only its script and, if it
  has assets, its own asset folder. It MUST NOT depend on any other app in
  this repository. Any shared module it uses MUST be listed in the plan and
  included in the install instructions and release package.
- **FR-025**: The app MUST work on the DS-24 II / DC-24 II. On other
  transmitters it MUST either work or show a clear "not supported" notice.

### Key Entities

- **Setup**: per model: switch and its OFF position, throttle stick,
  throttle output, targets, tolerance, wizard step, last result.
- **Verify result**: per state: target, measured value, pass or fail, and
  for the run: the failsafe confirmation and the date.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A pilot who has never set up a Jeti turbine throttle can go
  from opening the app to a verified setup in under 10 minutes, without any
  other manual.
- **SC-002**: All four verify states pass only when the measured output is
  within the tolerance (default ±10 µs) of target.
- **SC-003**: The values the app displays agree with the transmitter's servo
  monitor within ±5 µs for every reading in calibration testing, in both
  the emulator and on the DS-24 II. The monitor's percent view converts at
  1500 + 5 µs per percent (plan research R1; the app's own µs readout
  checks this in calibration).
- **SC-004**: Every seeded single fault (wrong switch, reversed switch, cut
  not overriding the stick, wrong endpoint, wrong idle offset, wrong output)
  is reported as FAIL at the right state, in 100% of fault tests.
- **SC-005**: "Setup complete" never appears unless a clean run passed
  all four states and the failsafe hand test was confirmed, including after a
  run in which a state was retried and after any setup input was changed.
- **SC-006**: For any valid targets, entering the values the app shows
  produces those targets within ±10 µs.
- **SC-007**: With the app removed from the model, all four states produce
  the same outputs as during verify.
- **SC-008**: Running the app without making any changes leaves every servo
  output and every model setting unchanged.
- **SC-009**: On a transmitter with no other AG- apps installed, copying
  only this app's files (plus any listed shared modules) is enough to load
  it and complete a full setup and verify.
- **SC-010**: Targets with an idle position below 10% or above 30% are
  refused, and targets from 10% up to 15% show the ECU warning, in 100% of
  boundary tests (e.g. 9.9%, 10%, 14.9%, 15%, 30%, 30.1%).

## Assumptions

- **Target and firmware.** DS-24 II / DC-24 II on firmware 6.x, like the
  other apps here. The emulator runs 6.04.
- **No setting writes.** The JETI Lua API v1.5 has no way to change model
  settings, and the public release notes up to firmware 5.06 add none. If
  firmware 6.x release notes show otherwise, this spec should be revisited.
- **Reading outputs and opening menus.** The app can read servo output
  positions and open transmitter menus by name (firmware 5.01+). Menus
  named in the API include servo setup, "other model options (throttle cut
  etc.)" and the device explorer.
- **Pulse-width mapping.** How the travel, cut and idle percentages map to
  output was measured on two of Aaron's models (plan research R2). How
  the app's output reading (−1..1) maps to µs is checked in the first
  implementation task (research R1).
- **Returning from a menu.** What happens when the pilot backs out of a menu
  the app opened is undocumented. FR-009 is written so the wizard resumes
  correctly either way.
- **Failsafe is not readable.** Failsafe lives in the receiver settings and
  can only be confirmed by a hand test.
- **ECU-agnostic.** The app works with any ECU that learns its throttle
  range from the receiver signal; it doesn't talk to the ECU. During Teach
  RC the pilot triggers each state and the ECU stores the pulse width it
  receives, so after Teach RC the ECU relies on each state being repeatable
  and clearly separated, not on particular µs values. Matching exact
  targets matters only when the pilot skips Teach RC.
- **Bench use only.** The app is used with the engine unable to start. It
  has no role in flight.
- **No voice.** The wizard is silent apart from the transmitter's normal
  sounds; a spoken guide is out of scope.
- **Screen.** Instruction and verify screens are designed for the measured
  window and font sizes in `docs/jeti-api-notes.md`; the form canvas size
  will be measured during planning.

### Open research items (for `/speckit-clarify` and `/speckit-plan`)

1. Calibrate the output reading to µs, and the percentage settings to µs,
   against the servo monitor (emulator and transmitter).
2. Test what happens on returning from a menu the app opened.
3. Confirm, on firmware 6.x, the exact menu names and field labels for
   Throttle Cut, Throttle Idle and receiver failsafe, so the instructions
   match the screen.
4. Check the firmware 6.x release notes for any new Lua API.
5. Measure the app form canvas and choose a screen layout.
6. Check whether copying a model on the transmitter also copies a Lua
   app's saved settings.

### Follow-up ideas (not in this release)

- **Show the model's current settings next to the needed ones** (Aaron,
  2026-10-10). The app would **read** the current model's `.jsn` file on
  the SD card and show, on each instruction step, "Travel −: 80%, set
  100%" or "Idle offset: 20% ✓". It could also flag a wrong switch,
  position or reversed servo before verify runs. Read-only, so
  constitution I still holds: the app never writes the file. The pilot
  still makes every change. Writing the file was considered and rejected:
  the transmitter keeps the model in memory and saves over the file, the
  format is undocumented and changes between firmware versions, and a
  bug could corrupt a turbine's throttle setup.
  Field names seen in Aaron's models (firmware 6.04/6.06): `Servos[n]`
  `Max-Negative` / `Max-Positive` (travel), `Common`
  `Throtle-Cut-Value` (×40, −4000 = −100%), `Throtle-Idle-Value`,
  `Throtle-Cut-Switch` / `Throtle-Idle-Switch`.
  Open questions: which file belongs to the current model; whether edits
  are on the card before the pilot leaves the menu or switches models;
  the memory and CPU needed to decode about 60 KB of JSON; and how to
  match a servo output to the throttle function (`Servo-Code`).
