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

Proposed script name: `AG-TrbSt.lua`, menu name "Turbine Throttle Setup".
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

A locking two-position safety switch, mounted where it is easy to reach in an
emergency, is recommended.

### Terms used in this spec

- **Pulse width**: the throttle channel's output, in microseconds (µs), as
  shown on the transmitter's servo monitor (µs view).
- **Targets**: the three pulse widths the pilot wants: cut, idle and full.
  Defaults 1100 / 1200 / 1900 µs.
- **OFF / RUN position**: the two positions of the chosen safety switch.
  OFF selects Throttle Cut; RUN selects Throttle Idle.
- **Verify state**: one combination of switch position and stick position
  that the app measures. There are four (see User Story 2).
- **Tolerance**: how far a measured pulse width may be from its target and
  still pass. Default ±10 µs.

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
and check that the throttle reads about 1100 / 1200 / 1900 µs in the three
states.

**Acceptance Scenarios**:

1. **Given** the default targets, **When** the pilot reaches the endpoints
   step, **Then** the screen says ±80% and names the menu.
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

**Independent Test**: On the emulator, set up a model by hand with the
reference values, run verify only, and check that all four states pass.
Then introduce one fault at a time (see Edge Cases) and check that verify
fails at the right state with a useful message.

**Acceptance Scenarios**:

1. **Given** a correct setup, **When** the pilot runs verify, **Then** all
   four states pass and the measured values are within tolerance.
2. **Given** the switch is assigned backwards, **When** verify reaches the
   cut state, **Then** it fails and says to reverse the switch assignment.
3. **Given** Throttle Cut is missing or not overriding the stick, **When**
   verify reaches the cut-overrides-stick state, **Then** it fails and
   points to the Throttle Cut setting.
4. **Given** the stick is not yet at the end of its travel, **When** a state
   is being measured, **Then** the app waits and asks for the stick to be
   moved fully, and does not record a value until the stick is steady.
5. **Given** a state fails, **When** the pilot fixes the setting and retries
   that state, **Then** the app re-measures only that state.

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

- **Switch assigned backwards** (OFF gives idle, RUN gives cut): the cut
  state fails with "Switch position OFF produced idle; reverse the switch
  assignment."
- **Cut doesn't override the stick** (output rises with the stick while
  OFF): the cut-overrides-stick state fails and points to Throttle Cut.
- **Wrong or asymmetric endpoints** (e.g. full reads 1940 µs): the full
  state fails and shows expected vs. measured.
- **Wrong output selected** (the output doesn't move between idle and full
  stick): the app detects no change and asks the pilot to re-select the
  output before continuing.
- **Throttle reversed** (full reads lower than idle): the app detects it and
  points to servo reverse.
- **Stick not fully at the end of travel, or still moving**: the app waits
  until the stick is at the end and steady before measuring.
- **Throttle trim not centered, or digital trim active**: the app warns that
  trim shifts the readings and asks for the trim to be centered.
- **Flight modes with different throttle settings**: the app verifies the
  current flight mode only and says so.
- **Invalid targets** (cut ≥ idle, idle ≥ full, or any value outside
  900–2100 µs): the app refuses them and explains why.
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

## Requirements *(mandatory)*

### Functional Requirements

**Setup inputs**

- **FR-001**: The app MUST let the pilot choose the safety switch and which
  of its two positions is OFF (Throttle Cut).
- **FR-002**: The app MUST let the pilot choose the throttle stick and the
  throttle output channel to measure.
- **FR-003**: The app MUST let the pilot set the three targets (cut, idle,
  full) in µs, defaulting to 1100 / 1200 / 1900, and MUST refuse invalid
  combinations (cut < idle < full, each within 900–2100 µs).
- **FR-004**: The app MUST let the pilot set the verify tolerance from 5 to
  25 µs, default 10.
- **FR-005**: All setup inputs MUST be saved per model and restored when the
  model or app is reloaded.

**Instructions**

- **FR-006**: For the chosen targets, the app MUST show the endpoint values,
  the Throttle Cut value and the Throttle Idle offset that produce them.
  For the default targets these are ±80%, −100% and 20%.
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
  state alone.
- **FR-017**: Before measuring, the app MUST check that the selected output
  moves with the stick and in the right direction, and stop with a clear
  message if not.
- **FR-018**: The app MUST warn when throttle trim is not centered, and MUST
  state that only the current flight mode is verified.

**Completion**

- **FR-019**: The app MUST NOT report "Setup complete" unless all four
  states passed in the same verify run and the pilot confirmed a hand test of
  failsafe.
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
  monitor (µs view) within ±5 µs for every reading in calibration testing,
  in both the emulator and on the DS-24 II.
- **SC-004**: Every seeded single fault (wrong switch, reversed switch, cut
  not overriding the stick, wrong endpoint, wrong idle offset, wrong output)
  is reported as FAIL at the right state, in 100% of fault tests.
- **SC-005**: "Setup complete" never appears unless all four states passed
  and the failsafe hand test was confirmed.
- **SC-006**: For any valid targets, entering the values the app shows
  produces those targets within ±10 µs.
- **SC-007**: With the app removed from the model, all four states produce
  the same outputs as during verify.
- **SC-008**: Running the app without making any changes leaves every servo
  output and every model setting unchanged.
- **SC-009**: On a transmitter with no other AG- apps installed, copying
  only this app's files (plus any listed shared modules) is enough to load
  it and complete a full setup and verify.

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
- **Pulse-width mapping.** How the app's output reading (−1..1) maps to µs,
  and how the endpoint, cut and idle percentages map to µs, will be measured
  during planning against the servo monitor. The reference setup
  (±80% / −100% / 20% → 1100 / 1200 / 1900 µs) is the first calibration
  point.
- **Returning from a menu.** What happens when the pilot backs out of a menu
  the app opened is undocumented. FR-009 is written so the wizard resumes
  correctly either way.
- **Failsafe is not readable.** Failsafe lives in the receiver settings and
  can only be confirmed by a hand test.
- **ECU-agnostic.** The app works with any ECU that learns its throttle
  range from the receiver signal; it doesn't talk to the ECU.
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
