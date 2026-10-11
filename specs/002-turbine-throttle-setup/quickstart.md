# Quickstart: validating Turbine Throttle Setup

Run the sections in order. Section 1 has to pass before the rest of the
app is built on its results (research R1, R2). Sections 3–4 need the
transmitter and are done by Aaron. Claude can't run the emulator.

**Deploy.** Copy `src/Apps/AG-TrbSt.lua` to
`%LOCALAPPDATA%\JETI-Studio\Emulator\Apps` (emulator) or `/Apps` on the SD
card (transmitter). There are no assets and no lib modules (FR-024).

**Test model.** A new, empty airplane model named "TrbSt test" with the
throttle on output 1 (or any output) and a two-position switch free.
Never use a model that will fly the same day (constitution, Verification
step 4).

## 0. Static checks

```powershell
python tools/check.py
```

LuaLS diagnostics on `AG-TrbSt.lua`: no errors. `grep` for
`registerControl|setControl|setProperty` returns nothing (SC-008).

## 1. Calibration (task 1; emulator, then transmitter)

Use the app's Setup inputs screen with the live output readout (µs), next
to the servo monitor (percent). Expected µs = 1500 + 5 × monitor %.
Record each pair in `research.md` R1/R2 and in `docs/jeti-api-notes.md`.

Already measured on the transmitter's servo monitor alone (research R2):
the Flash (reference setup) reads −80 / −80 / −60 / +80%, and the Avanti
(cut −125%) reads −100 / −100 / −60 / +80%. The settings formulas are
settled. What's left is checking the app's µs readout against the
monitor.

| # | Model settings | Stick / switch | Servo monitor expects | App shows |
| --- | --- | --- | --- | --- |
| a | Travel ±100%, no cut/idle | low / mid / high | −100 / 0 / +100% | 1000 / 1500 / 2000 ±5 µs |
| b | Travel ±125%, limit 125% | low / high | −125 / +125% | 875 / 2125, or clipped at 1000 / 2000? (R1.2) |
| c | Reference: ±80%, cut −100%, idle 20% | CUT; RUN low; RUN high | −80 / −60 / +80% | 1100 / 1200 / 1900 ±5 µs |
| d | Avanti: ±80%, cut −125%, idle 20% | CUT; RUN low | −100%; −60% (measured) | 1000; 1200 ±5 µs |
| e | Same as c | CUT, stick high | −80% (cut after mixing, R1.1) | 1100 ±5 µs |

Also check, and record:

- Each "Open" button lands in the named menu. Back out and note what the
  app shows: form still open, re-initialized, or closed (R3, R4).
- Menu and field names on firmware 6.x for Travel, Throttle Cut ("Output
  value"), Throttle Idle ("Idle offset") and receiver failsafe. Update
  [contracts/screens.md](contracts/screens.md) if they differ.
- The travel maximum allowed in Servo setup (R2).

**Stop rule.** If (e) reads the stick and not the cut value, `O<n>` isn't
the final output. Stop and revisit the spec. If (d) shows idle counting
from the stick's low end rather than the cut value, update the idle and
cut rules in [settings-math.md](contracts/settings-math.md) before
building the guide.

## 2. Emulator scenarios

Use the test model, set up for the default targets (travel −100% / +80%,
cut −100%, idle offset 40%) unless a row says otherwise.

| # | Scenario | Expected |
| --- | --- | --- |
| 2.1 | Fresh app: Home | "Not verified". Guided setup and Verify disabled |
| 2.2 | Setup inputs: assign switch, stick, output; Learn | Live labels follow switch and stick. Learn with switch in middle (if 3-pos) is refused |
| 2.3 | Targets: each settings-math test vector | Refusals, warnings and idle position as listed (SC-010) |
| 2.4 | Guide with defaults | Travel -100% / +80%, cut -100%, idle offset 40% shown (US1-1). Custom 1100/1200/1900 shows +/-80%, -100%, 20% plus the 12.5% warning (US1-2) |
| 2.5 | Guide: Open on step 2, back out | Wizard on step 2 with same choices (US1-4, FR-009) |
| 2.6 | Close app, reopen | Same screen and step |
| 2.7 | Verify, correct setup | Output check and 4 states PASS → Failsafe screen (US2-1) |
| 2.8 | Stick at 90% during a state | "Move the stick fully…"; nothing recorded until steady at the end (US2-4) |
| 2.9 | Failsafe "Not yet" | "Incomplete - failsafe not confirmed" (US3-1) |
| 2.10 | Failsafe "Yes" | "Setup complete", summary lists switch, targets, 4 measured values, date, next step (US3-2, FR-020) |
| 2.11 | Change a target after 2.10 | Confirm prompt. No → value reverts. Yes → "Not verified" (FR-005a) |
| 2.12 | Retry then pass | "Run all four again to save". Nothing saved until a clean run (Q1) |

**Seeded faults** (SC-004). Set up correctly, introduce one fault, run
verify, then undo it.

| Fault | Fails at | Message mentions |
| --- | --- | --- |
| Switch assignment reversed | Output check | reverse the switch |
| Throttle Cut not assigned | Cut overrides stick | Throttle Cut |
| Travel + 88% (full 1940) | Full | Travel + |
| Idle offset 45% (idle 1225) | Idle | Idle offset |
| Wrong output chosen | Output check | choose the throttle output |
| Throttle servo reversed | Output check | servo reverse |
| Wrong switch chosen in app | Cut (or Learn mismatch) | switch |

## 3. Transmitter checks (DS-24 II)

- Repeat section 1 (a, c, e) on the transmitter (SC-003).
- Every screen readable: no line cut off at 32 characters. Do `µ` and `±`
  render? If yes, switch "us" to "µs" and "+/-" to "±".
- Run 2.7 and two seeded faults on the transmitter.
- Applications → User Applications: CPU figure stays low during verify.
- **SC-008:** before running the app, note the servo monitor values and
  save a copy of the model file. Run the app through Home, Inputs (no
  changes), Guide and Verify. The outputs and model file are unchanged.
- **Copied model (R11):** copy the finished test model. Does the copy
  carry the app and its "Setup complete"? Record it in `docs/jeti-api-notes.md`.

## 4. Bench test with an ECU (fuel off)

- Run the full wizard on a real turbine model with the engine unable to
  start (FR-023). Time it: under 10 minutes for someone new to it (SC-001).
- Remove the app from the model. Re-check all four states on the servo
  monitor: same values (SC-007, FR-022).
- Do the failsafe hand test: transmitter off, the ECU shows signal loss.
- Run Teach RC (or confirm the ECU accepts the existing teach) and
  confirm the ECU reads cut, idle and full correctly.
