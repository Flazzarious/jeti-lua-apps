---

description: "Task list for Turbine Throttle Setup (AG-TrbSt)"
---

# Tasks: Turbine Throttle Setup

**Input**: Design documents from `specs/002-turbine-throttle-setup/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: The spec doesn't ask for automated tests. The checks are
`tools/check.py`, LuaLS, the measured table in
[contracts/settings-math.md](contracts/settings-math.md) and the manual
scenarios in [quickstart.md](quickstart.md).

**Organization**: Tasks are grouped by user story so each story can be
built and checked on its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1–US3)
- **MANUAL**: Needs a person at JETI Studio or the transmitter. An agent
  can't run the emulator (CLAUDE.md): it prepares the build, deploys it to
  the emulator, lists what to check, and leaves the box unticked until
  Aaron reports back.

## Rules for every code task

- Follow `docs/examples/style/HELLO.lua`: 2-space indent, every variable and
  function `local` (constitution II), sections in the order given in
  [plan.md](plan.md#source-code-repository-root). Group constants, text,
  thresholds and form-row indexes in tables: the main chunk may hold at
  most 200 locals.
- Call only APIs declared in `types/jeti.lua` (constitution III). Never call
  `system.registerControl`, `system.setControl` or `system.setProperty`.
  No `os`, `debug`, `coroutine`, `bit32`. Never write any model setting
  (FR-021).
- `form.*` only in the form's init, component callbacks, key handler and
  close function. Exception: `loop()` may call `form.setProperties` only
  while `formOpen` is true (research R9). `form.question` only in
  component callbacks or the key handler, never in `loop()`.
- No `string.format`, `..` or `{}` in `loop()` except to rebuild a label's
  text when the value it shows has changed (contract screens.md).
- All on-screen text is ASCII ("us" for µs, "+/-" for ±, "-" for dashes)
  until quickstart section 3 confirms `µ` and `±` render. Lines ≤ 32
  characters, F-key labels ≤ 7.
- F5, ESC and the power key close a form by default (API v1.5, "form.preventDefault").
  Any screen that gives F5 an action (Next, Start, Yes) MUST call
  `form.preventDefault()` for `KEY_5` in the key handler. Links are chosen
  with the rotary press (`KEY_ENTER`), not F5 (emulator, 2026-10-10).
- Switch screens with `form.reinit(1)` only; the screen comes from `cur`.
  `form.reinit(2)` was not shown to work here (emulator, 2026-10-10).
- `src/Apps/AG-TrbSt.lua` is one file, so tasks that touch it run one after
  another. Docs and stub tasks are separate files.
- Run `python tools/check.py` after each phase. It must report 0 errors.
  After each phase, copy `src/Apps/AG-TrbSt.lua` to
  `%LOCALAPPDATA%\JETI-Studio\Emulator\Apps` (no assets, no lib modules).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: The app file and the API stub it relies on

- [X] T001 [P] Update the `system.openExternal` stub comment in `types/jeti.lua`: replace "Opens a .txt/.html/.png/.jpg in the system viewer (async)." with a description that it opens a file **or a system menu** asynchronously, list the menu constants this app uses (`":servoSetup"` Servo setup and gains, `":otherProps"` Other model options (throttle cut etc.), `":devExplorer"` Device Explorer) and add `Source: JETI DC/DS Lua API v1.5 p. 74-75`. Change only comments, not the signature
- [X] T002 Create `src/Apps/AG-TrbSt.lua` with the header style of `src/Apps/AG-FlmOt.lua`: line 1 `-- AG-TrbSt.lua — Turbine Throttle Setup: guides the JETI turbine throttle setup and verifies the throttle output.`, then `-- Copyright (c) 2026 Aaron George` and `-- SPDX-License-Identifier: MIT`, a comment that the app only reads outputs, sticks and switches and opens menus, never changes a setting or drives an output, and is meant to be removed after setup (constitution I, FR-021/022), and the design pointer `specs/002-turbine-throttle-setup/`. Constants: `APP_NAME = "Turbine Throttle Setup"`, `APP_VERSION = "0.1.0"`, `US_CENTER = 1500`, `US_PER_UNIT = 500`, `US_PER_PCT = 5`, a `MENU` table `{ servo = ":servoSetup", other = ":otherProps", dev = ":devExplorer" }`, a `SCR` table `{ HOME = 1, INPUTS = 2, GUIDE = 3, VERIFY = 4, FAILSAFE = 5, SUMMARY = 6 }`, a `RES` table `{ NONE = 0, PASSED = 1, COMPLETE = 2 }`, and a `V` table with the verify constants from `specs/002-turbine-throttle-setup/contracts/verify.md` (`SW_BAND = 0.5`, `END_BAND = 0.95`, `STEADY_MS = 500`, `STICK_JITTER = 0.01`, `OUT_JITTER_US = 2`, `SAMPLE_N = 10`, `SAMPLE_MS = 50`) plus `LABEL_MS = 200`. Empty `init`, `loop`, `destroy`; end with `---@type JetiApp` and `return { init = init, loop = loop, destroy = destroy, author = "Aaron George", version = APP_VERSION, name = APP_NAME }`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Settings storage, the settings math, the form with the Setup inputs screen and live readouts, and the calibration gate. Every story builds on these.

**⚠️ CRITICAL**: No user story work can begin until T008 (calibration) is reported back

- [X] T003 Add settings in `src/Apps/AG-TrbSt.lua` per "Setup", "Wizard position" and "Saved result" in `specs/002-turbine-throttle-setup/data-model.md`: a `KEYS` list and `DEFAULTS`/`RANGES` tables with exactly these 12 keys: `sw` SwitchItem default nil; `offSg` int default 0, valid "-1, 1 (0 = not learned)"; `stk` SwitchItem default nil; `idlSg` int default 0, valid "-1, 1 (0 = not learned)"; `out` int default 0, valid "1-24 (0 = not chosen)"; `ecu` int default 0, valid "1 Xicoy, 2 other (0 = not chosen)"; `tol` "5-25" default 10; `scr` "1-6" default 1; `gStep` "1-5" default 1; `res` "0, 1, 2" default 0; `meas` int[4] default nil; `when` int default 0 ("yyyymmdd"). `loadSettings()` uses `system.pLoad` and clamps every integer to its range (out-of-range -> default). A `save(key, value)` helper calls `system.pSave` and updates the in-memory table. Call `loadSettings()` from `init()`
- [X] T004 Add the recommended settings and targets in `src/Apps/AG-TrbSt.lua` per `specs/002-turbine-throttle-setup/contracts/settings-math.md`: constants `MAX_NEG = -80`, `MAX_POS = 80`, `IDLE_OFS = 20`, `CUT_VAL = { [1] = -125, [2] = -100 }`, `TARGETS = { [1] = { 1000, 1200, 1900 }, [2] = { 1100, 1200, 1900 } }` and `ECU_NAMES = { "--", "Xicoy", "Other" }` (selectbox index = ecu + 1); `toUs(v)` returns `US_CENTER + US_PER_UNIT * v` rounded to an integer; `targetsText(ecu)` returns "Targets: c / i / f us" or "Targets: --". Remove the old target math (`settingsFor`, `validateTargets`, `idlePosText`). Check `TARGETS` against the contract's formulas
- [X] T005 Add the form skeleton in `src/Apps/AG-TrbSt.lua`: `formOpen` flag, a `row` table of component indexes (reset at every form init), `system.registerForm(1, MENU_APPS, APP_NAME, initForm, onKey, nil, closeForm)` in `init()`, `initForm(subformId)` that sets `formOpen = true` and dispatches to one builder per screen in `SCR` (stubs except Home and Setup inputs), `closeForm()` that sets `formOpen = false`, and a `goTo(screen)` helper that saves `scr` and calls `form.reinit(screen)`. `initForm` with no valid saved screen opens Home. `loop()` returns at once when `formOpen` is false (constitution VI)
- [X] T006 Build the Setup inputs screen (`SCR.INPUTS`) in `src/Apps/AG-TrbSt.lua` per section 2 of `specs/002-turbine-throttle-setup/contracts/screens.md`: first the two FR-023 warning lines ("ENGINE MUST NOT BE ABLE TO START" / "(fuel off or ECU unplugged)"), then rows Safety switch (`form.addInputbox(sw, false, cb)`), Throttle stick (`form.addInputbox(stk, true, cb)`), Throttle output (`form.addSelectbox` of "--", "O1".."O24" built once), ECU (`form.addSelectbox(ECU_NAMES, ecu + 1, false, cb)` with hint "Xicoy: cut -125%. Others: -100%."), the Targets label (updated when ECU changes), Tolerance (`form.addIntbox(tol, 5, 25, 10, 0, 1, cb)`). Each live row has a label beside it. Choosing a new switch clears `offSg`, a new stick clears `idlSg`. F1 "Back" -> Home. Leave a placeholder for the FR-005a confirm (T028)
- [X] T007 Add the live readouts and Learn in `src/Apps/AG-TrbSt.lua`: in `loop()`, while `formOpen` and on `SCR.INPUTS`, every `LABEL_MS` read `system.getInputsVal(sw, stk)` and `system.getInputs("O"..out)` (build the "O<n>" string only when `out` changes) and update the three live labels only when the shown text changes: switch "CUT" / "RUN" / "middle" / "not learned" (using `offSg` and `V.SW_BAND`), stick "idle" / "full" / "middle" (using `idlSg` and `V.END_BAND`), output "NNNN us" via `toUs`. F3 "Learn" (key handler): refuse with "Use a two-position switch" if |switch| < `V.SW_BAND`, and "Move the stick fully to idle" if |stick| < `V.END_BAND`; otherwise `save("offSg", sign of switch)` and `save("idlSg", sign of stick)`. Also add temporary F2/F4 buttons "Servo" and "Other" that call `system.openExternal(MENU.servo)` / `(MENU.other)` for calibration only, removed in T013
- [X] T008 MANUAL: Calibration, quickstart section 1. Deploy to the emulator, then the transmitter. Aaron records, for rows a–e of the section 1 table, the servo monitor % and the app's "us" readout, and checks that each Open button lands in its menu and what the app shows after backing out. Also note the 6.x menu and field names for Travel, Throttle Cut "Output value", Throttle Idle "Idle offset" and receiver failsafe, and the travel maximum. **Stop rule**: if row e (CUT, stick high) reads the stick instead of the cut value, stop and revisit the spec. If row b shows clipping at 1000 / 2000 us, narrow the target range per research R1.2 before continuing
- [X] T009 Record T008's results: update research R1 and R3 in `specs/002-turbine-throttle-setup/research.md` (mark "CALIBRATE" items as measured, with numbers and the firmware version), add a "Throttle outputs and menus" section to `docs/jeti-api-notes.md` (`getInputs("O<n>")` is post-mix or not, clipping, µs agreement, `openExternal` return behavior, menu names on 6.x), and if names or ranges differ, update `specs/002-turbine-throttle-setup/contracts/screens.md`, `contracts/settings-math.md` and the constants in `src/Apps/AG-TrbSt.lua` to match

**Checkpoint**: Settings load and save, the math is checked, the Setup inputs screen shows live switch, stick and output values, and the readout is calibrated.

---

## Phase 3: User Story 1 - Guided setup (Priority: P1) 🎯 MVP

**Goal**: The pilot chooses switch, stick, output and targets, then follows five instruction screens that show the exact values to enter and open each menu.

**Independent Test**: On the emulator with a fresh model, follow only the instruction screens with the default targets, then check the servo monitor reads about −100% / −60% / +80% (1000 / 1200 / 1900 us) for cut, idle and full (spec US1; quickstart 2.1–2.6).

- [ ] T010 [US1] Build the Home screen (`SCR.HOME`) in `src/Apps/AG-TrbSt.lua` per section 1 of `contracts/screens.md`: status label from `res` ("Not verified" / "Incomplete - failsafe not confirmed" / "Setup complete yyyy-mm-dd" using `when`), and links "Setup inputs", "Guided setup", "Verify", "Summary" (`form.addLink`). "Guided setup" and "Verify" are `enabled = false` until setup is complete (data-model: `sw`, `stk`, `out` set, `offSg` and `idlSg` learned, targets valid). "Summary" is disabled while `res == RES.NONE`. "Guided setup" opens the guide at `gStep`
- [ ] T011 [US1] Add a `setupComplete()` helper in `src/Apps/AG-TrbSt.lua` used by Home and by the guide and verify screens (open Home instead if it returns false), and a `fmtDate(yyyymmdd)` helper returning "yyyy-mm-dd" (string built only when the screen is built, not in `loop()`)
- [ ] T012 [US1] Build the guide screen (`SCR.GUIDE`) in `src/Apps/AG-TrbSt.lua` per section 3 of `contracts/screens.md`: title "Step n of 5" (`form.setTitle`), the step's label lines from the constants in T004. Step 1 shows "Max negative: -80%" and "Max positive: 80%" plus "Leave the limits at -125/125%." (FR-006). Step 2 shows "Throttle-Cut output value: -100%" or "-125%" with "(Xicoy)" from `CUT_VAL[ecu]`, step 3 "Throttle-Idle offset: 20%" and the tick/cross check, step 4 the failsafe text (FR-010), step 5 the safety-switch text (FR-011, including "Don't use it for anything else."). F1 "Back" (step 1 → Home), F3 "Open" calling `system.openExternal` with `MENU.servo` / `MENU.other` / `MENU.other` / `MENU.dev` for steps 1–4, F5 "Next" ("Verify" on step 5 → `goTo(SCR.VERIFY)`). Save `gStep` on every step change (FR-009)
- [ ] T013 [US1] Remove the temporary calibration buttons from the Setup inputs screen (T007) in `src/Apps/AG-TrbSt.lua`, and hide F3 "Open" on the guide when `system.openExternal` is nil (research R13). The step text still names the menu
- [ ] T014 [US1] Make the wizard resume in `src/Apps/AG-TrbSt.lua` (FR-009, research R4): `initForm` rebuilds the screen named by `scr` (the guide at `gStep`), except Verify always reopens at its start and Failsafe falls back to Summary when `res ~= RES.PASSED`. Check that returning from `openExternal` (whatever T008 found) lands on the same step with the same choices
- [ ] T015 [US1] MANUAL: quickstart scenarios 2.1–2.6 in the emulator (Home states, Setup inputs and Learn, ECU choice and the Targets label for Xicoy and Other, guide values for both ECU types, Open and back out, close and reopen). Report results; tick when they pass

**Checkpoint**: The app is a working guided checklist (US1 alone is useful).

---

## Phase 4: User Story 2 - Verify the throttle output (Priority: P1)

**Goal**: The app runs an output check and measures the four switch-and-stick states, showing target, measured value and pass or fail, with a diagnosis and retry for failures.

**Independent Test**: Set up a model by hand for the default targets, run verify only (from Home), and see all states pass. Then seed one fault at a time and see verify fail at the right state with the right message (spec US2; quickstart 2.7, 2.8, 2.12 and the seeded-fault table).

- [ ] T016 [US2] Add the verify run state in `src/Apps/AG-TrbSt.lua` per "Verify run (session only, never persisted)" in `data-model.md`: one `run` table with `phase` (IDLE, CHECK, WAIT, SETTLE, SAMPLE, FAILED, PASSED), `k` 0–4, `retried`, `m[1..4]`, `ok[1..4]`, `why1`/`why2`, `chkIdle`, `chkFull`, `t0`, `n`, `sum`, `refOut`, `refStk`, `lastWork`. A `STATES` table for k = 1..4 with required switch (CUT/RUN), stick end (idle/full) and which target applies (cut, cut, idle, full), per the sequence table in `contracts/verify.md`. `startRun()` resets everything and sets `phase = CHECK`, `k = 0`
- [ ] T017 [US2] Add position helpers in `src/Apps/AG-TrbSt.lua`: `switchIs(off)` true when `getInputsVal(sw) * offSg >= V.SW_BAND` for CUT and `<= -V.SW_BAND` for RUN; `stickAt(idle)` true when `getInputsVal(stk) * idlSg >= V.END_BAND` for idle and `<= -V.END_BAND` for full (contract verify.md "Position and steadiness"); `near(x, t)` true when `|x - t| <= max(tol, 15)` (used by T018 and T020)
- [ ] T018 [US2] Implement the output check (k = 0) in `loop()` in `src/Apps/AG-TrbSt.lua`, running at most every `V.SAMPLE_MS`: with the switch in RUN, record the output in us when the stick is at the idle end (`chkIdle`) and at the full end (`chkFull`). When both are recorded, check in this order: if `|chkFull - chkIdle| < (full - idle) // 2` and `near(chkIdle, cut)` (targets from `TARGETS[ecu]`), fail with "Switch RUN gave cut." / "Reverse the switch assignment." (a backwards switch holds the output at cut); else if `|chkFull - chkIdle| < (full - idle) // 2`, fail with "Output doesn't move with stick." / "Choose the throttle output."; fail with "Throttle reversed." / "Check Servo setup > Reverse." if `chkFull < chkIdle`, otherwise go to WAIT for k = 1 (FR-017, research R7)
- [ ] T019 [US2] Implement WAIT → SETTLE → SAMPLE in `loop()` in `src/Apps/AG-TrbSt.lua` per `contracts/verify.md`: WAIT until `switchIs` and `stickAt` match the state; SETTLE until stick within `V.STICK_JITTER` and output within `V.OUT_JITTER_US` of the reference for `V.STEADY_MS` (reset the reference and `t0` whenever they move more); SAMPLE `V.SAMPLE_N` readings `V.SAMPLE_MS` apart and average to whole us. Losing the position in SETTLE or SAMPLE goes back to WAIT for the same state (FR-015, US2-4). Then compare with the state's target: within `tol` → `ok[k] = true`, next state or PASSED after k = 4; otherwise FAILED (FR-014)
- [ ] T020 [US2] Implement the diagnosis in `src/Apps/AG-TrbSt.lua` exactly as the "Diagnosis" table in `contracts/verify.md`, top to bottom per failing state, using `near` from T017. Fill X from the constants in T004 (Max negative 80, Max positive 80, idle offset 20, `CUT_VAL[ecu]`) and N as measured − expected with a sign. Store the two lines in `run.why1`/`run.why2` (built once at the failure, not per loop) (FR-016)
- [ ] T021 [US2] Build the verify screen (`SCR.VERIFY`) in `src/Apps/AG-TrbSt.lua` per section 4 of `contracts/screens.md` and `contracts/verify.md`: the three standing lines ("ENGINE MUST NOT BE ABLE TO START" / "(fuel off or ECU unplugged)", "Center throttle trim.", "Checks the current flight mode only.") (FR-018, FR-023), the prompt line naming the required switch and stick position, the phase line ("Waiting..." / "Hold steady..." / "Measuring..." / "Move the stick fully to IDLE|FULL"), four result rows "Name  target  measured  PASS|FAIL" (blank until measured), and two diagnosis lines. `loop()` updates them every `LABEL_MS` while `formOpen`, only on change
- [ ] T022 [US2] Add the verify F-keys in `src/Apps/AG-TrbSt.lua` per the "Actions" table in `contracts/verify.md`: IDLE F1 Back / F5 Start; running F1 Back (abandons the run); FAILED F1 Back / F3 Retry (re-measure state k only, set `retried = true`, clarification Q1) / F5 Restart; PASSED clean F1 Back / F5 Next; PASSED after a retry shows "All passed after a retry." / "Run all four again to save." with F1 Back / F5 Restart. Update the buttons with `form.setButton` whenever `phase` changes (while `formOpen`)
- [ ] T023 [US2] Save a clean pass in `src/Apps/AG-TrbSt.lua` (FR-019, data-model "Transitions"): when `phase` becomes PASSED with `retried == false`, `save("meas", {m1, m2, m3, m4})`, `save("when", yyyymmdd from system.getDateTime())`, `save("res", RES.PASSED)`. F5 Next goes to Failsafe. Failed or retried runs save nothing and never lower a saved result
- [ ] T024 [US2] MANUAL: quickstart 2.7, 2.8 and 2.12, plus every row of the seeded-fault table, in the emulator (SC-004). Report which state failed and the message for each; tick when all match

**Checkpoint**: Verify works on its own from Home on any model already set up (FR-012).

---

## Phase 5: User Story 3 - Failsafe confirmation and completion (Priority: P2)

**Goal**: After a clean pass, the pilot confirms a hand test of failsafe; only then is the setup "complete", and the summary lists everything plus the next step.

**Independent Test**: Pass verify, decline the failsafe confirmation and see "Incomplete - failsafe not confirmed"; confirm it and see "Setup complete" with the summary (spec US3; quickstart 2.9–2.11).

- [ ] T025 [US3] Build the Failsafe screen (`SCR.FAILSAFE`) in `src/Apps/AG-TrbSt.lua` per section 5 of `contracts/screens.md`: the three text lines, F1 "Not yet" (leaves `res = RES.PASSED`, goes to Summary) and F5 "Yes" (`save("res", RES.COMPLETE)`, goes to Summary) (FR-019, US3-1, US3-2)
- [ ] T026 [US3] Build the Summary screen (`SCR.SUMMARY`) in `src/Apps/AG-TrbSt.lua` per section 6 of `contracts/screens.md`: status line, "Safety switch: <label>, CUT at -100%" (or "+100%" when `offSg == 1`) with the label from `system.getSwitchInfo(sw).label` (fallback "?" if nil), "Targets: c / i / f us", "Measured: m1 / m2 / m3 / m4", "Verified: yyyy-mm-dd", and the four next-step lines (remove the app; Teach RC or skip it) (FR-020). F1 "Back" → Home
- [ ] T027 [US3] Wire the Home status and links to the result in `src/Apps/AG-TrbSt.lua`: Home's status text follows `res` and `when` (T010), Summary enables once `res > RES.NONE`, and a new clean pass returns `res` to `RES.PASSED` so failsafe must be confirmed again (data-model "Result" transitions)
- [ ] T028 [US3] Add the FR-005a confirm-and-clear on the Setup inputs screen in `src/Apps/AG-TrbSt.lua` per section 2 of `contracts/screens.md`: while `res > RES.NONE`, the first change to any input (switch, stick, Learn, output, any target, tolerance) calls `form.question("Clear saved result?", "Changing setup means it must be", "verified again.")` from the component callback. No → put the old value back with `form.setValue` (and leave `offSg`/`idlSg` untouched). Yes → `save("res", RES.NONE)`, `save("meas", nil)`, `save("when", 0)`, then apply the change; later changes on the same screen visit don't ask again
- [ ] T029 [US3] Confirm FR-005a's clear-result path exists (T028) and that "Setup complete" can only be reached through T023 + T025 (SC-005): read through every `save("res", ...)` call in `src/Apps/AG-TrbSt.lua` and list them in the task's completion note
- [ ] T030 [US3] MANUAL: quickstart 2.9–2.11 in the emulator. Report results; tick when they pass

**Checkpoint**: All three stories work; the app can be used end to end in the emulator.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Device support, docs, and transmitter and bench validation

- [ ] T031 Add the device check in `src/Apps/AG-TrbSt.lua` (FR-025, research R13): in `init()`, `isDs24 = string.find(system.getDeviceType() or "", "24", 1, true) ~= nil`. If false, every screen builder shows only "Throttle Setup Wizard" / "needs a DC/DS-24" and `loop()` does nothing
- [ ] T032 Review `src/Apps/AG-TrbSt.lua` against the "Rules for every code task" above: count main-chunk locals (must be < 200), search for `string.format`, `..` and `{` inside `loop()` and confirm each is a change-only rebuild, search for `registerControl|setControl|setProperty|os%.|debug%.|coroutine|bit32` (must be none; SC-008), and run LuaLS diagnostics (no errors)
- [ ] T033 [P] Add Throttle Setup Wizard to `README.md`: a row in the apps table (`AG-TrbSt.lua`, "Throttle Setup Wizard", original) and a short section drawn from `docs/apps/throttle-setup-wizard.md` (the app's primary description): one safety switch instead of the trim method (Xicoy's warning about digital trims), the eight "What the app does for you" benefits in brief, that it only reads and instructs and never changes a setting, the recommended values (Max negative/positive -80/80, idle offset 20%, Throttle-Cut -100%, or -125% for Xicoy), that the ECU must always be re-learned (Teach RC) afterwards, that it's removed from the model after setup, the install (one file, no assets, FR-024), and a link to the description page
- [ ] T034 [P] Add the row `| Throttle Setup Wizard | src/Apps/AG-TrbSt.lua | specs/002-turbine-throttle-setup/ | original |` to the apps table in `CLAUDE.md`
- [ ] T035 MANUAL: quickstart section 3 on the DS-24 II: calibration rows a, c, e; every screen readable with no line cut off; whether `µ` and `±` render; verify (2.7) and two seeded faults; CPU figure during verify; SC-008 (outputs and model file unchanged after a no-change run); copied-model check. Report results
- [ ] T036 If T035 shows `µ` and `±` render, switch "us" → "µs" and "+/-" → "±" in all screen text in `src/Apps/AG-TrbSt.lua` and note it in `docs/jeti-api-notes.md`; also fix any line T035 reports as cut off
- [ ] T037 MANUAL: quickstart section 4, bench test with a real ECU and the engine unable to start: full wizard timed (SC-001, under 10 minutes), app removed and all four states re-checked on the servo monitor (SC-007, FR-022), failsafe hand test, Teach RC (or skip) and the ECU reads cut, idle and full correctly. Report results

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: T001 and T002 have no dependencies.
- **Foundational (Phase 2)**: depends on T002. T003 → T004 → T005 → T006 → T007 → T008 (MANUAL) → T009. **T008 gates everything after it**: its stop rule can change the spec.
- **US1 (Phase 3)**: depends on Phase 2.
- **US2 (Phase 4)**: depends on Phase 2. Uses Home (T010) and `setupComplete` (T011) to reach Verify, so build T010–T011 first if US2 is done before the rest of US1.
- **US3 (Phase 5)**: depends on US2 (it needs a saved pass).
- **Polish (Phase 6)**: T031–T032 after all stories; T033–T034 any time after T009; T035 after T032; T036 after T035; T037 last.

### Within each story

All code tasks edit `src/Apps/AG-TrbSt.lua` and run in ID order. MANUAL tasks close each story.

### Parallel Opportunities

- T001 (`types/jeti.lua`) alongside T002 onward.
- T033 (`README.md`) and T034 (`CLAUDE.md`) alongside any code task after T009.
- MANUAL emulator checks for one story can run while the next story's code is written, as long as fixes are folded back in before moving on.

### Parallel Example: after T009

```text
Agent:  T010 → T011 → T012 … (src/Apps/AG-TrbSt.lua, in order)
Agent:  T033 README.md section   [P]
Agent:  T034 CLAUDE.md table row [P]
Aaron:  nothing until T015
```

---

## Implementation Strategy

### MVP first (User Story 1)

1. Phase 1 and Phase 2, including the calibration gate (T008–T009).
2. Phase 3: Home, the guide and resume.
3. **Stop and validate** with T015. Even alone, US1 is a better checklist than a forum post (spec US1).

### Incremental delivery

1. + US2 (verify) → T024: the app now proves the setup.
2. + US3 (failsafe, summary, clear-on-change) → T030: complete in the emulator.
3. Polish → T035 on the transmitter, T037 on the bench → release 0.1.0 via `develop` → `main` and tag `AG-TrbSt-v0.1.0` (ask before PRs and tags, CLAUDE.md).

---

## Notes

- `AG-TrbSt.lua` becomes a permanent name at first release (constitution V). Confirm it with Aaron before the release PR.
- The copied model files in `docs/examples/models/` are gitignored. Never copy their contents (IDs) into committed files.
- Commit after each phase on `feature/002-turbine-throttle-setup`; never directly to `develop` or `main`.
