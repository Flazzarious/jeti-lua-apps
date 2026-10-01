# Draft spec input: Turbine Throttle Setup

**Status:** Pre-spec draft (2026-10-01). Not yet run through Spec Kit.
**Next step:** run `/speckit-specify` with the *Feature description* below,
then bring in the *Success criteria* and *Edge cases* sections, and feed the
*Open questions / research* items to `/speckit-clarify`.

Proposed script name: `AG-TrbSt.lua` (menu name "Turbine Throttle Setup").
Confirm the name before release; constitution V makes filenames permanent.

---

## Feature description (paste into `/speckit-specify`)

Turbine Throttle Setup is a one-time setup wizard app for the Jeti DS-24 II.

**Problem.** Setting up a turbine throttle on Jeti has to be done exactly
right, and mistakes are dangerous. The setup covers endpoints, Throttle Cut
and Throttle Idle on one two-position safety switch, and failsafe. Pilots want
a guided setup that proves the result.

**Goal.** The wizard walks the user through the native transmitter setup, then
checks the live throttle output in every switch and stick state. When it is
done, the app is no longer needed. The user then moves on to the ECU's
"learn transmitter" (Teach RC) phase. If the targets already match what the
ECU expects, that phase can be skipped.

**Setup inputs.**

- Two-position switch, and which position is OFF.
- Throttle stick.
- Throttle servo output.
- Target pulse widths. Defaults are cut 1100 us, idle 1200 us and
  full 1900 us, and all three are editable.

**Behavior.**

1. Instruction steps, one per screen. Each screen shows the value to enter for
   the user's targets and has an "Open menu" button
   (`system.openExternal`) that jumps to the right transmitter menu:
   1. Throttle channel endpoints, default +/-80% (`":servoSetup"`).
   2. Throttle Cut on the selected switch and position, value -100%
      (`":otherProps"`).
   3. Throttle Idle on the same switch, opposite position, offset 20%
      (`":otherProps"`).
   4. Throttle failsafe OFF or -125%, which gives about 1000 us or no pulse
      (`":devExplorer"`).
   5. A recommendation to use a locking safety switch in an easy-to-reach
      position.
2. Verify mode. The app prompts for each state and reads the throttle servo
   output with `system.getInputs("O<n>")`:
   - Switch OFF, stick at idle: should read the cut target.
   - Switch OFF, stick at full: should still read the cut target, because
     cut overrides the stick.
   - Switch ON, stick at idle: should read the idle target.
   - Switch ON, stick at full: should read the full target.

   Each state gets pass or fail within a tolerance.
3. Failsafe step. The app cannot read failsafe settings. The user must test
   failsafe by hand (Tx off, ECU sees signal loss and shuts down) and confirm
   before the wizard reports complete.
4. Summary screen listing the values set, with a reminder that the app can
   now be removed from the model.

**Constraints.**

- The Jeti Lua API can't write model settings. The user makes every change by
  hand; the app only instructs and verifies.
- The app never drives any output. It never calls `system.registerControl`,
  `system.setControl` or `system.setProperty` (constitution I).
- Nothing at flight time depends on the app.
- The app installs standalone. It needs only `AG-TrbSt.lua` and, if it has
  assets, its own `AG-TrbSt/` folder. It must not depend on any other app in
  this repo, including Speed Gauge. If it uses a shared module from
  `src/Apps/lib/`, the plan must list that module, and the install
  instructions and any release package must include it.

---

## Reference: the manual setup (from Aaron)

This is the proven manual procedure the wizard automates the guidance for:

1. Set the throttle channel endpoints to +/-80.
2. Assign Throttle Cut to a 2-position switch, in whichever position you want
   the turbine OFF.
3. Set the Throttle Cut value to -100%.
4. Assign Throttle Idle to the same switch, in the position you want the
   turbine to idle.
5. Set the Throttle Idle offset to 20%.
6. Set the throttle failsafe to OFF or -125% and verify that it works.

With these settings, the throttle channel outputs:

- 1100 us with the switch in Throttle Cut;
- 1200 us in Throttle Idle;
- 1900 us at full throttle.

Failsafe must be 1000 us (or anything outside the normal range) or no pulse,
so the ECU recognizes signal loss and shuts down. The servo monitor shows the
throttle in microseconds: press F3 twice.

These values match the Spektrum-era throttle positions all of Aaron's ECUs
were already set up with. That let him skip Teach RC. Other values work too,
as long as the user understands exactly what they're doing.

Use a locking 2-position safety switch, mounted where it's easy to reach in an
emergency.

---

## Success criteria

- **SC-001.** Someone who has never set up a Jeti turbine throttle can go from
  opening the app to a fully verified setup in under 10 minutes, without any
  other manual.
- **SC-002.** All four verify states (cut at idle stick, cut at full stick,
  idle, full) report PASS only when the measured throttle output is within
  ±10 us of target. The tolerance is editable from 5 to 25 us.
- **SC-003.** The values the app shows agree with the transmitter's servo
  monitor (us view) within ±5 us for 100% of readings in calibration testing,
  in both the emulator and on the DS-24 II.
- **SC-004.** Any single setup fault is reported as FAIL, naming the failing
  state, in 100% of seeded-fault tests. Faults covered: wrong switch, reversed
  switch direction, cut not overriding full stick, wrong endpoint, wrong idle
  offset, wrong output selected.
- **SC-005.** The wizard never reports "Setup complete" unless all four verify
  states passed AND the user confirmed a manual failsafe test.
- **SC-006.** For any target values the user enters, the endpoint, cut value
  and idle offset shown on the instruction screens produce those targets
  within ±10 us when entered as shown.
- **SC-007.** After the app is removed from the model, all four throttle states
  produce the same outputs as before. The setup has no runtime dependence on
  the app.
- **SC-008.** The app never changes any transmitter output or setting. To
  check: servo outputs and the model file are unchanged after running the app
  with no user edits.
- **SC-009.** On a transmitter with no other AG- apps installed, copying only
  the app's files (plus any listed lib modules) to `/Apps` is enough for it
  to load and complete a full setup and verify run.

## Edge cases

- **Switch assigned backwards** (cut and idle swapped). Verify fails at the
  cut state with a clear message, e.g. "Switch position OFF produced idle;
  reverse the switch assignment."
- **Cut doesn't override the stick** (the output rises with the stick while
  the switch is OFF). The cut / full-stick state fails, and the message
  points to the Throttle Cut assignment.
- **Asymmetric or wrong endpoints** (e.g. full reads 1940 us). The full state
  fails and shows the expected and measured values.
- **Wrong servo output selected** (the output doesn't move with the stick).
  The app detects no change between idle and full and asks the user to
  re-select the output before verifying.
- **Throttle reversed on the channel** (full reads low). The app detects this
  and points to servo reverse.
- **Stick not fully at idle or full during a step.** The app waits until the
  stick is at the end of its travel and steady before sampling.
- **Throttle trim not centered, or digital trim active.** The app warns that
  trim offsets shift readings and asks the user to center the trim.
- **Flight modes with different throttle settings.** The app verifies the
  current flight mode only and warns that other modes are not checked.
- **Out-of-range targets.** The app blocks targets where cut ≥ idle,
  idle ≥ full, or any value is outside 900–2100 us, and explains why.
- **Failsafe confirmation skipped or declined.** The setup stays
  "Incomplete" and says why.
- **Model already has a throttle setup.** The user can run verify-only mode
  without going through the instructions.

---

## Open questions / research (feed to `/speckit-clarify` and the plan)

1. **us mapping.** How does the `system.getInputs("O<n>")` value (-1..1) map
   to microseconds? Calibrate against the servo monitor (F3 twice) in the
   JETI Studio emulator and on the transmitter. Known data point: endpoints of
   ±80% give 1100 and 1900 us.
2. **Return from `openExternal`.** The call returns immediately. It is not
   documented what happens when the user backs out of the opened menu: do
   they return to the wizard, and does the form keep its step? Test in the
   emulator. Save wizard progress with `pSave` so the wizard can resume
   either way.
3. **Exact menu labels.** Confirm on firmware 6.x the exact wording and
   location of the Throttle Cut / Throttle Idle fields under
   `":otherProps"`, and of receiver failsafe under `":devExplorer"`, so the
   on-screen instructions match.
4. **Firmware 6.x API changes.** The latest public release notes found cover
   up to 5.06 (June 2021) and show no Lua function that writes model
   settings. The repo targets firmware 6.03/6.04. Check the 6.x release
   notes (JETI Studio firmware updater) for any new Lua API before finalizing
   the plan. If anything new appears, update `docs/jeti-api-notes.md` and
   `types/jeti.lua`.
5. **Stub check.** `types/jeti.lua` already declares `system.openExternal`,
   `system.getInputs`, `system.createSwitch` and `system.getSwitchInfo`.
   Confirm that the `getInputs` stub documents the `O1`–`O24` servo output
   codes.

## Research findings so far (2026-10-01)

- **The Lua API can't write model programming.** JETI DC/DS Lua API v1.5 has
  no functions for servo travel or endpoints, trims, Throttle Cut/Idle, mixes,
  logical switches or failsafe. The only things it can change are the app's
  own registered controls and a few system properties (wireless mode,
  volumes, backlight). Both are off-limits here under constitution I.
- **The API can read servo outputs.** `system.getInputs` accepts `O1`–`O24`
  and returns values in -1..1.
- **The API can open transmitter menus.** `system.openExternal` (since
  firmware 5.01) opens named menus, including `":servoSetup"`,
  `":otherProps"` (described as "Other model options (throttle cut etc.)"),
  `":devExplorer"` and `":servoTest"`.
- **Release notes 3.00–5.06** list every Lua addition: switch info, log
  variables, backplate inputs, vario, audio redirect, `openExternal`,
  `createSwitch`, file I/O. None of them modify model settings.

### Sources

- [JETI DC/DS Lua API v1.5 (PDF)](https://github.com/JETImodel/Lua-Apps/blob/master/Doc/JETI%20DCDS_Lua_API_1.5.pdf)
- [JETI Release Notes EN, firmware 3.00–5.06](https://jetiforum.de/media/kunena/attachments/46/ReleaseNotes_EN.pdf)
- [Firmware 5.02 – Highlights And Notes (RC-Thoughts)](https://rc-thoughts.com/2019/12/firmware-5-02-highlights-and-notes/index.html)
- [JETI DS-24 II product page](https://www.jetimodel.com/katalog/duplex-ds-24-ii-gray-lacquer-us-1.htm)
