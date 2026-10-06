---

description: "Task list for Flameout Alarm (AG-FlmOt)"
---

# Tasks: Flameout Alarm

**Input**: Design documents from `specs/003-flameout-alarm/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: The spec doesn't ask for automated tests. The checks are the
sound generator's self-check (T001), the `SIM` profiles (T024) and the
manual scenarios in [quickstart.md](quickstart.md).

**Organization**: Tasks are grouped by user story so each story can be
built and checked on its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1–US8)
- **MANUAL**: Needs a person at JETI Studio or the transmitter. An agent
  can't run the emulator (CLAUDE.md): it prepares the build, lists what to
  check, and leaves the box unticked until the user reports back.

## Rules for every code task

- Follow `docs/examples/style/HELLO.lua`: 2-space indent, every variable and
  function `local` (constitution II), sections in the order given in
  [plan.md](plan.md#source-code-repository-root). Group constants, colors
  and geometry in tables: the main chunk may hold at most 200 locals.
- Call only APIs declared in `types/jeti.lua` (constitution III). Never call
  `system.registerControl`, `system.setControl` or `system.setProperty`.
  No `os`, `debug`, `coroutine`, `bit32`.
- Call `system.getSensor*` through `system` every time; never keep a local
  copy of those functions (the emulator's telemetry app replaces them,
  research R9).
- `lcd.*` only in the print function; `form.*` only in the form's init,
  callbacks and close function. Exception: `loop()` may update form rows
  only while `formOpen` is true (research R10).
- No `string.format`, `..` or `{}` in `loop()` or the print function, except
  rebuilding `rpmText` when RPM / 100 changes (data-model.md).
- `src/Apps/AG-FlmOt.lua` is one file, so tasks that touch it run one after
  another. Generator, docs and emulator config tasks are separate files.
- Run `python tools/check.py` after each phase. It must report 0 errors.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: The alarm sounds, the emulator RPM sensor and the asset folder

- [X] T001 [P] Create `tools/voice/make_flameout.py` (Python 3.9, MIT header like `tools/voice/make_voice.py`) per research R5 and `specs/003-flameout-alarm/contracts/audio-events.md`. Import `synthesize`, `trim`, `normalize`, `resample`, `write_wav`, `write_text` and `PEAK` from `make_voice.py` (add `tools/voice` to `sys.path`; do not modify `make_voice.py`). Arguments: `--model` (required, path to `en_US-amy-medium.onnx`), `--out` (default `src/Apps/AG-FlmOt`), `--rate` (default 22050). Urgent phrase "Flameout!": Piper `SynthesisConfig(length_scale=0.749, noise_scale=0.5)`, then `resample(samples, round(src_rate * 1.07), src_rate)` (treat the audio as 7% faster and convert back, so it plays 7% faster and about one semitone higher: the `asetrate` step, R5; the final resample to `--rate` follows as in `make_voice.py`), then a 150 Hz high-pass biquad, a +4 dB peaking biquad at 3 kHz (Q 1.0) (RBJ cookbook formulas), a compressor (threshold −18 dBFS, ratio 4, attack 3 ms, release 60 ms, makeup +4 dB, peak envelope follower), `trim`, `normalize`. Build the callout as three copies joined by 0.12 s of silence. Calm phrases at Speed Gauge's speed (`length_scale = 1/1.5`, no effects, then `trim`, `normalize`): "Engine telemetry lost", "Flameout alarm armed", "Engine relit". Lock tone generator: 1800 Hz sine plus 3600 Hz overtone at 0.3 relative amplitude, 45 ms on / 35 ms off, 3 ms linear fades, normalized to `PEAK`. Write `cycle.wav` = callout + lock tone to exactly 5.000 s (110,250 samples at 22,050 Hz; scale with `--rate`); `cycletl.wav` = callout + 0.15 s gap + "Engine telemetry lost" + lock tone to exactly 5.000 s; `tlost.wav`, `armed.wav`, `relit.wav`; and `CREDITS.txt` (adapt `make_voice.py`'s CREDITS text: "Flameout Alarm (AG-FlmOt) - alarm sounds", Piper MIT, Amy CC BY-SA 4.0, lock tone synthesized). Self-check, exit 1 on failure: all five WAVs exist; both cycle files exactly 5.000 s; callout part ≤ 2.5 s; voice part of `cycletl.wav` ≤ 4.0 s
- [X] T002 Run `python tools/voice/make_flameout.py --model <path>` (ask the user for the path to `en_US-amy-medium.onnx`; Speed Gauge's generator uses the same model) and confirm the self-check passes. Commit the generated `src/Apps/AG-FlmOt/` folder (FR-028: committed, CC BY-SA 4.0)
- [X] T003 MANUAL: Listen to `src/Apps/AG-FlmOt/cycle.wav` and `cycletl.wav` on the PC: the callout sounds urgent and about one semitone higher than Speed Gauge's voice, the lock tone follows with no gap, and the files end cleanly at 5 s. Approve or ask for parameter changes before the app work depends on them
- [X] T004 [P] Add a "Flameout Alarm" section to `tools/voice/README.md`: what `make_flameout.py` generates (the five files and their purpose), how to run it, the urgent-delivery chain (R5: length scale 0.749, resample ×1.07, high-pass, presence boost, compression) and that the output is committed under CC BY-SA 4.0
- [X] T005 [P] Add the turbine sensor to `tools/emulator/sensors.json` (research R12): an entry `{"id": 3, "param": 0, "decimals": 0, "type": 1, "label": "Turbine", "unit": "", "sensorName": "Turbine"}` and `{"id": 3, "param": 1, "decimals": 0, "type": 1, "label": "RPM", "unit": "rpm", "sensorName": "Turbine", "lowerBound": 0, "upperBound": 160000, "input": "P8"}`. Keep the existing entries unchanged

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The app file, settings storage, derived values, the tick and sensor read, a minimal settings form and a text-only window. Every story builds on these.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T006 Create `src/Apps/AG-FlmOt.lua` with the header style of `src/Apps/AG-SpdGa.lua`: line 1 `-- AG-FlmOt.lua — Flameout Alarm: turbine flameout alarm from RPM telemetry, with an RPM bar window.`, then `-- Copyright (c) 2026 Aaron George` and `-- SPDX-License-Identifier: MIT`, a comment that the app only reads telemetry and switches, plays sound, vibrates and draws and never controls the model (constitution I), and that the sounds in `AG-FlmOt/` are CC BY-SA 4.0 (FR-028). Design pointer: `specs/003-flameout-alarm/`. Constants: `APP_NAME = "Flameout Alarm"`, `APP_VERSION = "0.1.0"`, `AUDIO_DIR = "/Apps/AG-FlmOt/"`, `TICK_MS = 100`, `CYCLE_MS = 5000`, `TITLE_H = 26`, a `SND` table with the five paths (`cycle`, `cycletl`, `tlost`, `armed`, `relit`), and state constants `OFF = 0`, `DISARMED = 1`, `ARMED = 2`, `FLAMEOUT = 3` (in one table). Debug flags `DEBUG_CPU = false`, `SIM = false`. End with `---@type JetiApp` and `return { init = init, loop = loop, destroy = destroy, author = "Aaron George", version = APP_VERSION, name = APP_NAME }`; `destroy()` stops alarm audio if one is sounding
- [X] T007 Add settings in `src/Apps/AG-FlmOt.lua` per "Settings" in `specs/003-flameout-alarm/data-model.md`: a `KEYS` list and `DEFAULTS`/`LIM` tables with exactly: `en` 0/1 default 0; `sId` int default 0; `sPar` int default 0; `sLbl` "string < 64 bytes" default ""; `scl` "1–4" default 1; `swCut` SwitchItem default nil; `idle` "0–1500" default 0 ("Idle RPM / 100 (0 = not set)"); `maxR` "0–3000" default 0 ("0 = auto: 4 × idle"); `armP` "50–98" default 90; `flP` "20–95" default 70; `armT` "10–100" default 30; `detT` "3–50" default 10; `lossT` "5–100" default 20; `sayArm` 0/1 default 0; `sayRel` 0/1 default 0; `swTest` SwitchItem default nil; `cfgV` default 1 (17 keys, limit 30). `loadSettings()` uses `system.pLoad`, clamps every integer to its range, and applies the load rules: if `flP >= armP` restore both defaults; if `maxR ~= 0 and maxR <= idle` set `maxR = 0`; if `sId == 0`, `swCut == nil` or `idle == 0` force `en = 0`. A `save(key, value)` helper calls `system.pSave` and updates the in-memory table
- [X] T008 Add `recompute()` in `src/Apps/AG-FlmOt.lua` per "Derived values" in data-model.md: `active = en == 1 and sId ~= 0 and swCut ~= nil and idle > 0`; `kScale` = 1, 10, 100, 1000 by `scl`; `idleRpm = idle * 100`; `armRpm = idleRpm * armP // 100`; `flRpm = idleRpm * flP // 100`; `fullRpm = maxR * 100` or `4 * idleRpm` when `maxR == 0`; `armMs = armT * 100`, `detMs = detT * 100`, `lossMs = lossT * 100`. Call it from `init()` after `loadSettings()` and after every settings change. If `active` becomes false while `state == FLAMEOUT`, stop the alarm (row 0)
- [X] T009 Add session state and `resetSession()` in `src/Apps/AG-FlmOt.lua` per "Session state" in data-model.md: `state` (`OFF` if not `active`, else `DISARMED`), `rpm = nil`, `sensorFound = true`, `invalidSince = nil`, `lost = false`, `armSince = nil`, `lowSince = nil`, `cycleAt = 0`, `beepAt = nil`, `tlPending = false`, `testOn = false`, `testPrev = true` (so a test switch already on at load needs a toggle, spec edge case), `rpmText = "---"`, `rpmHundreds = -1`, `lastTick = system.getTimeCounter()`. Group them in one `st` table. Never persist them
- [X] T010 Add audio-file checks in `src/Apps/AG-FlmOt.lua` (research R6): a `fileExists(path)` using Jeti's function-style `io.open`/`io.close` (as in `AG-SpdGa.lua`), called once in `init()` for the five `SND` paths. Set `audioOk = fileExists(cycle) and fileExists(cycletl)` and a `fileOk` table for `tlost`, `armed`, `relit`. Never call it from `loop()`
- [X] T011 Implement the `loop()` frame in `src/Apps/AG-FlmOt.lua` per "State transitions" in data-model.md: return unless `now - lastTick >= TICK_MS`; call an empty `stepTest(now)` (US8 fills it); if not `active`, set `state = OFF` and return (row 0, FR-034); read the Cut switch (`system.getInputsVal(swCut) > 0.5`, research R10) and call an empty `onCut(now)` when in Cut (US2 fills it, row 1) then return; read `system.getSensorValueByID(sId, sPar)` through `system`: `nil` → `sensorFound = false`, invalid; `valid == false` → invalid; else `sensorFound = true`, `rpm = value * kScale`, `invalidSince = nil`, `lost = false`. On invalid call an empty `onInvalid(now)` (US6 fills it) and skip the rows below. On valid, dispatch by state to empty `stepDisarmed(now)`, `stepArmed(now)`, `stepFlameout(now)` (filled by US1/US4). Then, on valid and invalid ticks alike, when `state == FLAMEOUT` call an empty `stepCycle(now)` (US1), so the alarm keeps cycling through a telemetry loss (FR-020a). Keep the structure so later tasks only fill functions
- [X] T012 Add the settings form frame in `src/Apps/AG-FlmOt.lua` per `specs/003-flameout-alarm/contracts/settings-form.md`: `system.registerForm(1, MENU_APPS, APP_NAME, initForm, nil, nil, closeForm)` in `init()`; `initForm` sets `formOpen = true`, `closeForm` sets it false. Add rows 1–5, 10 and 20 now: heading "Flameout Alarm"; Monitoring checkbox `en` with the FR-003 rule (refuse with `form.setValue` and show row 3's hint "Needs: RPM sensor, Cut switch, idle RPM" listing only the missing items); heading "Engine"; RPM sensor selectbox built from `system.getSensors()` on each open: "(none)" first, skip `param == 0`, `type == 5` and `type == 9`, entries "Device / Label", a saved sensor not present shown as "<sLbl> (not found)" (FR-022; same approach as `buildSensorList` in `AG-SpdGa.lua`); on change save `sId`, `sPar`, `sLbl` (cut to 63 bytes); Idle RPM (x1000) intbox `idle`, range 0–1500, 1 decimal, step 1, hint "From the ECU setup. Check against Live RPM at idle."; heading "Throttle cut" and Cut switch `form.addInputbox(swCut, false, ...)` with hint "Assign with the switch in the Cut (engine off) position." Every change calls `save()` then `recompute()`; clearing sensor, Cut switch or idle while enabled sets `en = 0`. Footer row (25) "Flameout Alarm 0.1.0. Advisory only; does not replace the ECU's failsafe." built from `APP_VERSION`. Labels ASCII only ("x", not "×")
- [X] T013 Register the window in `init()` of `src/Apps/AG-FlmOt.lua`: `system.registerTelemetry(1, APP_NAME, 0, printRpm)`. For now `printRpm(w, h)` draws only the text layout of `specs/003-flameout-alarm/contracts/telemetry-window.md` in the theme foreground color: state label (OFF, NO SENSOR, NO TELEMETRY, DISARMED, ARMED, FLAMEOUT, TEST per "Window display state" in data-model.md) on line 1 and `rpmText` on line 2 (`FONT_NORMAL`). US7 replaces this for the DS-24 II
- [X] T014 Run `python tools/check.py` and fix any errors in `src/Apps/AG-FlmOt.lua`. Check the VS Code Problems panel (LuaLS) shows no errors

**Checkpoint**: The app loads, shows OFF, the form can set sensor, idle, Cut switch and enable, and `loop()` reads RPM. Nothing arms or sounds yet.

---

## Phase 3: User Story 1 - Hear a flameout the moment it happens (Priority: P1) 🎯 MVP

**Goal**: Once the engine has held the arming threshold, RPM below the flameout threshold for the detection delay starts the repeating alarm with vibration and FLAMEOUT on screen.

**Independent Test**: Emulator, Turbine RPM slider: above 31,500 for 3 s (idle 35.0), then to 0. The console shows `cycle.wav` with `AUDIO_IMMEDIATE` and two vibration lines within 1.5 s, then every 5 s (quickstart 6, 8, 9).

- [X] T015 [US1] Add alarm audio helpers in `src/Apps/AG-FlmOt.lua` per `specs/003-flameout-alarm/contracts/audio-events.md` and research R2, R6, R7: `playCycle(now, file)` → if `audioOk` then `system.playFile(file, AUDIO_IMMEDIATE)`, else `system.playBeep(9, 1800, 120)` and `beepAt = now + 2500`; then `system.vibration(false, 4)` and `system.vibration(true, 4)`. `stopAlarm()` → `system.stopPlayback(AUDIO_IMMEDIATE)`, `beepAt = nil`, `tlPending = false`. In `stepCycle(now)`: if `beepAt` and `now >= beepAt` then `system.playBeep(9, 1800, 120)`, `beepAt = nil`
- [X] T016 [US1] Fill `stepDisarmed(now)` in `src/Apps/AG-FlmOt.lua` (data-model row 3): `rpm >= armRpm` sets `armSince = armSince or now`; when `now - armSince >= armMs` set `state = ARMED`, `armSince = nil`, `lowSince = nil`. Below `armRpm` clears `armSince`. (The "armed" confirmation comes in US2)
- [X] T017 [US1] Fill `stepArmed(now)` in `src/Apps/AG-FlmOt.lua` (row 4, FR-015): `rpm < flRpm` sets `lowSince = lowSince or now`; when `now - lowSince >= detMs` set `state = FLAMEOUT`, `cycleAt = now`, `armSince = nil`, `playCycle(now, SND.cycle)`. `rpm >= flRpm` clears `lowSince`
- [X] T018 [US1] Fill the cycle timing in `stepCycle(now)` in `src/Apps/AG-FlmOt.lua` (row 6, SC-012): when `now - cycleAt >= CYCLE_MS`, advance `cycleAt = cycleAt + CYCLE_MS`, or `cycleAt = now` if still more than one cycle behind, then `playCycle(now, SND.cycle)` (US6 adds the `cycletl` choice). Make sure `stepCycle` also runs on ticks where the sample is invalid (FR-020a), i.e. called from the frame regardless of validity while `state == FLAMEOUT`
- [X] T019 [US1] In the text layout of `printRpm` in `src/Apps/AG-FlmOt.lua`, show FLAMEOUT as the first line in `FONT_BIG` when `state == FLAMEOUT` (FR-031: dominant element)
- [ ] T020 [US1] MANUAL: Emulator, quickstart scenarios 6, 8 and 9: arming after 3 s above 31,500; a dip below 24,500 shorter than 1 s doesn't alarm; holding 0 alarms within 1.5 s and repeats every 5 s with vibration lines

**Checkpoint**: The core alarm works end to end in the emulator.

---

## Phase 4: User Story 2 - Silence during normal operation (Priority: P1)

**Goal**: No alarm through start, overshoot, idle, chops, landing and Cut shutdown; the app disarms silently on Cut and can confirm arming.

**Independent Test**: The `SIM` normal-flight profile and a manual chop and Cut in the emulator produce no `cycle.wav` line (quickstart 7, 20; SC-002, SC-003).

- [ ] T021 [US2] Fill `onCut(now)` in `src/Apps/AG-FlmOt.lua` (row 1, FR-016): if `state == FLAMEOUT` call `stopAlarm()`; set `state = DISARMED`; clear `armSince`, `lowSince`, `invalidSince`, `tlPending`, `lost`. Silent: no sound of its own. Re-arming then needs the switch out of Cut and row 3 again
- [ ] T022 [US2] In `stepDisarmed` in `src/Apps/AG-FlmOt.lua`, after the switch to ARMED, play `SND.armed` with `AUDIO_QUEUE` when `sayArm == 1` and `fileOk.armed` (FR-009)
- [ ] T023 [US2] Add the `SIM` debug mode in `src/Apps/AG-FlmOt.lua` (research R12): when `SIM` is true, the sensor read in the `loop()` frame is replaced by a value from one `SIMP` table of profiles, each a list of `{ms, rpm}` points with linear interpolation and `rpm = -1` meaning invalid. Profiles: (1) normal flight: 0 → startup range 0–20,000 over 20 s, overshoot to 45,000, decay to 35,000 over 8 s, idle, run-ups to 120,000, chops to 35,000, landing, idle; (2) failed start: rises to 25,000 and falls to 0; (3) flameout: armed at 60,000 then falls to 0 over 3 s; (4) auto-restart: flameout, then 10,000 → 28,000 → 8,000 (failed attempt), then → 45,000 overshoot → 35,000; (5) dropouts: armed at 35,000 with invalid gaps of 0.5 s and 3 s. Select the profile with an extra selectbox row shown only when `SIM` is true, and restart the profile when selected. With `SIM` false none of this runs and the row isn't added
- [ ] T024 [US2] MANUAL: Emulator with `SIM` on: profile 1 and 2 give zero alarms (SC-002, SC-003); profile 3 alarms within 1.5 s of crossing 24,500. Without `SIM`: quickstart scenario 7 (chop to 30,000: no alarm) and Cut during ARMED (silent DISARMED). Set `SIM = false` afterwards

**Checkpoint**: The alarm fires on a flameout and stays silent in normal operation.

---

## Phase 5: User Story 3 - Per-model setup with an assigned RPM sensor (Priority: P1)

**Goal**: The complete settings form with validation, live RPM and per-model storage.

**Independent Test**: Quickstart scenarios 1–5, 16 and 17.

- [ ] T025 [US3] Add form rows 6–9 in `src/Apps/AG-FlmOt.lua` per contracts/settings-form.md: hint row 6 shown when `system.getSensors()` returns no sensors ("No telemetry yet. The ECU must send RPM and the receiver must be on. Some adapters take up to a minute.", FR-004); hint row 7 shown when the selected sensor's unit, compared ignoring case, isn't `rpm`, `u/min` or `1/min` ("Unit is '<unit>', not RPM. Check the sensor, or set Sensor scale.", FR-010, R9; take the unit from `system.getSensorByID` at selection and form open, not in `loop()`); Sensor scale selectbox `scl` {"x1", "x10", "x100", "x1000"} (FR-006a); Live RPM label row 9 updated from `loop()` only while `formOpen`, at most every 500 ms, showing the scaled value with thousands separators or "---"
- [ ] T026 [US3] Add form row 11 in `src/Apps/AG-FlmOt.lua`: Max RPM (x1000) intbox `maxR`, range 0–3000, 1 decimal, step 1, "0.0 = auto (4 x idle)" hint; refuse a value `> 0 and <= idle` by setting the box back with `form.setValue` and showing the hint "Max RPM must be above idle." (FR-031b)
- [ ] T027 [US3] Add rows 12–15 in `src/Apps/AG-FlmOt.lua`: heading "Thresholds"; "Arming at % of idle" intbox `armP` 50–98 and "Flameout below % of idle" intbox `flP` 20–95, each with a label showing the RPM value (e.g. "= 31.5k"), rebuilt when idle or the percentage changes; refuse `flP >= armP` (set back, show row 15 "Flameout must be below arming, and arming below idle.") (FR-007)
- [ ] T028 [US3] Add rows 16–18 in `src/Apps/AG-FlmOt.lua`: "Arming time (s)" `armT` 10–100 step 5; "Detection delay (s)" `detT` 3–50 step 1; "Telemetry loss after (s)" `lossT` 5–100 step 5; all 1 decimal (FR-008)
- [ ] T029 [US3] Add rows 21–24 in `src/Apps/AG-FlmOt.lua`: heading "Announcements"; checkboxes Say "armed" (`sayArm`) and Say "relit" (`sayRel`); hint row 24 "Voice files missing: alarm uses beeps." when not `audioOk` (FR-029). Extend the footer with a second line "Voice: Piper, Amy (CC BY-SA 4.0)." (FR-028)
- [ ] T030 [US3] Review the enable rule in `src/Apps/AG-FlmOt.lua` across all rows: turning monitoring on with any requirement missing is refused and row 3 names the missing items; removing a requirement while enabled sets `en = 0`, calls `recompute()` (alarm stops if sounding, state OFF) and shows row 3 (FR-003, FR-012)
- [ ] T031 [US3] MANUAL: Emulator, quickstart scenarios 1–5, 16 and 17 (default OFF, enable blocked, no-sensors hint, full setup in under 3 minutes, threshold refusals, sensor not found, per-model settings across restart)

**Checkpoint**: All three P1 stories work: the MVP.

---

## Phase 6: User Story 4 - Auto-restart and relight (Priority: P2)

**Goal**: The alarm keeps going through restart attempts and clears only when RPM holds the arming threshold for the arming time.

**Independent Test**: `SIM` profile 4 and quickstart scenarios 10–11 (SC-011).

- [ ] T032 [US4] Fill `stepFlameout(now)` in `src/Apps/AG-FlmOt.lua` (row 5, FR-017, FR-018): `rpm >= armRpm` sets `armSince = armSince or now`; when `now - armSince >= armMs`: `stopAlarm()`, `state = ARMED`, `armSince = nil`, `lowSince = nil`, then play `SND.relit` with `AUDIO_QUEUE` if `sayRel == 1` and `fileOk.relit`. `rpm < armRpm` (the startup range) clears `armSince` and starts nothing new
- [ ] T033 [US4] MANUAL: Emulator, `SIM` profile 4: the failed attempt doesn't clear the alarm and no second event starts; the relight clears within 3.5 s of holding 31,500 and stays clear through the decay to 35,000. Without `SIM`: quickstart scenarios 10 and 11

---

## Phase 7: User Story 5 - Stop the alarm with the Cut switch (Priority: P2)

**Goal**: Cut silences the alarm at once and needs a fresh arming before another alarm.

**Independent Test**: Quickstart scenario 12.

- [ ] T034 [US5] Check in `src/Apps/AG-FlmOt.lua` that `onCut` (T021) runs before any other row on the same tick, that it stops both the voice/tone file and pending fallback beeps (`beepAt`), and that after Cut the app stays DISARMED with low RPM and re-arms only after leaving Cut and holding `armRpm` for `armMs` (User Story 5 scenarios 1–3). Fix anything that doesn't
- [ ] T035 [US5] MANUAL: Emulator, quickstart scenario 12, including Cut during the 2.5 s fallback beep wait (rename `cycle.wav` for that part)

---

## Phase 8: User Story 6 - Tell telemetry loss apart from a flameout (Priority: P2)

**Goal**: Loss after the telemetry-loss delay gives "Engine telemetry lost", never the flameout alarm; during an alarm it's spoken once inside the next cycle.

**Independent Test**: Quickstart scenarios 13–16 (SC-004).

- [ ] T036 [US6] Fill `onInvalid(now)` in `src/Apps/AG-FlmOt.lua` (row 2, FR-020, FR-020a): `invalidSince = invalidSince or now`; clear `armSince` and `lowSince`; `rpm = nil`; when `now - invalidSince >= lossMs` and not `lost`: `lost = true`; if `state == ARMED` and `fileOk.tlost`, play `SND.tlost` with `AUDIO_IMMEDIATE`; if `state == FLAMEOUT` set `tlPending = true`. Nothing happens while DISARMED besides the display
- [ ] T037 [US6] In `stepCycle` in `src/Apps/AG-FlmOt.lua`, play `SND.cycletl` instead of `SND.cycle` when `tlPending`, then clear `tlPending` (research R4). With `audioOk` false the beeps continue unchanged
- [ ] T038 [US6] In the frame of `loop()` in `src/Apps/AG-FlmOt.lua`, confirm that a valid sample after a loss resumes from the current RPM (FR-021): ARMED stays ARMED when `rpm >= flRpm`, and detection restarts from zero otherwise (`lowSince` was cleared). In `printRpm`'s text layout show NO SENSOR when `not sensorFound`, NO TELEMETRY when `lost` (not FLAMEOUT), and "NO TELEMETRY" as the second line under FLAMEOUT when both
- [ ] T039 [US6] MANUAL: Emulator, quickstart scenarios 13–16 (slider fully down = invalid; sensor removed from `sensors.json`)

---

## Phase 9: User Story 7 - RPM bar display (Priority: P2)

**Goal**: The double-size segmented sweep and the single-size straight bar of the window contract, in Speed Gauge's colors.

**Independent Test**: Quickstart scenarios 19 and 21 in the emulator; 22 on the transmitter (SC-013).

- [ ] T040 [US7] Add window constants in `src/Apps/AG-FlmOt.lua` per `specs/003-flameout-alarm/contracts/telemetry-window.md`, grouped in tables: colors (background 8,10,14; lit/ARMED 0,190,255; unlit fill 34,38,44 and outline 70,78,90; idle marker 255,225,0; number 255,255,255; labels 170,170,170; banner 255,45,30) and sweep geometry (`N = 12`, `X0 = 4`, `X1 = 146`, `GAP = 2`, bottom `y = 22 + 40 * (1 - t)^2.2`, height `6 + 12 * t`). Red only for FLAMEOUT (FR-031a)
- [ ] T041 [US7] In `init()` of `src/Apps/AG-FlmOt.lua`, precompute the 12 segments' four corner points as integers (the same formulas as `specs/003-flameout-alarm/design/mockup.py`'s `sweep()`), plus each segment's `t` at its left edge for the idle marker. Detect the DS-24 II once: `string.find(system.getDeviceType() or "", "24 II", 1, true)`. Recompute `idleX` (marker x) and its marker top/bottom in `recompute()`
- [ ] T042 [US7] Add `rpmText` caching in `src/Apps/AG-FlmOt.lua`: in `loop()`, when `rpm // 100` differs from `rpmHundreds`, rebuild `rpmText` as the RPM with comma thousands separators ("112,400"); "---" when `rpm` is nil. No other string work per tick
- [ ] T043 [US7] Implement the double layout in `printRpm` of `src/Apps/AG-FlmOt.lua`: layout selection (`w == 157` → `h = h - TITLE_H` and offset x by 3; not DS-24 II → text layout; `h >= 45` → double; else single); one `lcd.renderer()` created on first draw and reused; background fill; segments `1..lit` as cyan filled polygons and the rest as dim fills with a 1 px opaque outline polyline, `lit = math.min(N, math.ceil(N * rpm / fullRpm))`, 0 without data; idle marker as a 2 px filled rectangle from 3 px below to 3 px above the sweep at `idleX`; state label at x 4, y 2 `FONT_MINI` (colors per state, TEST white); RPM number right-aligned at x 146, top y 32, `FONT_BIG`; "RPM" right-aligned at x 146, top y 54, `FONT_MINI`; during FLAMEOUT a red filled 142 × 24 banner at x 4, y 2 with "FLAMEOUT" centered in `FONT_BIG` white, and "NO TELEMETRY" in place of "RPM" when `lost`
- [ ] T044 [US7] Implement the single layout in `printRpm` of `src/Apps/AG-FlmOt.lua`: bar x 4, y 4, 84 × 8 with dim fill and cyan fill to `84 * rpm / fullRpm` (capped); idle marker 2 px wide from y 1 to 15; state label x 4, y 12 `FONT_MINI`; RPM number right-aligned at x 146, top y 2, `FONT_NORMAL`; FLAMEOUT: whole window red, "FLAMEOUT" in `FONT_NORMAL` white on the left, number on the right
- [ ] T045 [US7] Add the `DEBUG_CPU` readout in `src/Apps/AG-FlmOt.lua`: when true, the double layout shows this call's and the worst `system.getCPU()` in `FONT_MINI` at the bottom left (as Speed Gauge's flag). Off by default
- [ ] T046 [US7] MANUAL: Emulator, quickstart scenario 19 at double and single size in every state, and scenario 21 (30 minutes with `DEBUG_CPU`, note the worst figure). Transmitter, scenario 22: screenshot at both sizes and compare with `design/rpm-window-mockup.svg`. If the sweep reads poorly or costs too much, iterate the named constants, drop the outlines, or switch to the straight-bar fallback (FR-031)

---

## Phase 10: User Story 8 - Test the alarm from a switch (Priority: P3)

**Goal**: A test switch plays the real alarm while on, whenever the app isn't Armed or in Flameout.

**Independent Test**: Quickstart 19a in the emulator; transmitter checks 23–26.

- [ ] T047 [US8] Add form row 23a in `src/Apps/AG-FlmOt.lua`: "Test alarm" `form.addInputbox(swTest, false, ...)` with hint "Plays the alarm while on. Not while armed." (FR-030a); saving `swTest` needs no recompute
- [ ] T048 [US8] Fill `stepTest(now)` in `src/Apps/AG-FlmOt.lua` per the "Test alarm" table in data-model.md (research R13): `T = swTest ~= nil and system.getInputsVal(swTest) > 0.5`; T1: `T and not testPrev`, `state` is OFF or DISARMED (OFF also when not `active`), not `testOn` → `testOn = true`, `cycleAt = now`, `playCycle(now, SND.cycle)`; T2: `testOn` and `now - cycleAt >= CYCLE_MS` → next cycle as in `stepCycle` (also fire a pending `beepAt`); T3: `testOn` and (not `T`, or `state` is ARMED or FLAMEOUT) → `testOn = false`, `stopAlarm()`; always `testPrev = T`. Runs before the `active` check so it works with monitoring off. In both window layouts show TEST (white) when `testOn`
- [ ] T049 [US8] MANUAL: Emulator, quickstart 19a. Transmitter, checks 23–26: hold the test switch for the alarm sound and rhythm, Speed Gauge pre-emption, instant stop, fallback beeps (note the beep gap)

---

## Phase 11: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, credits, audits and the release checks

- [ ] T050 [P] Update `README.md`: add Flameout Alarm to the apps table (script `AG-FlmOt.lua`, spec 003, original work); a section stating it is advisory, does not replace the ECU's failsafe, shutdown or auto-restart logic nor the pilot's monitoring, and only works where RPM reaches the transmitter as a normal telemetry sensor; the per-brand support list from research R1 (JetCat, Xicoy, KingTech, Swiwin via VSpeak confirmed; JetCentral, Enjet, Swiwin direct unconfirmed; JetiBox-only or vendor-app-only RPM can't be used); setup guidance (FR-035): idle from the ECU setup, the start overshoot and why arming sits below idle, the arming threshold staying above any RPM before the engine runs on its own, effects of an idle typed too high or too low; the test alarm switch; Swiwin's output-period note; install = `AG-FlmOt.lua` + `AG-FlmOt/`; the sounds' CC BY-SA 4.0 license
- [ ] T051 [P] Update `CREDITS.md`: a Flameout Alarm section for the generated sounds in `src/Apps/AG-FlmOt/` (Piper MIT, Amy model CC BY-SA 4.0 by Mycroft / Rhasspy, files distributed under CC BY-SA 4.0), following the Speed Gauge voice entry's wording (FR-028)
- [ ] T052 [P] Update `CLAUDE.md`'s "Apps in this repo" table: `Flameout Alarm | src/Apps/AG-FlmOt.lua | specs/003-flameout-alarm/ | original`
- [ ] T053 Audit `src/Apps/AG-FlmOt.lua`: no `registerControl`, `setControl`, `setProperty`, `os.`, `debug.`, `coroutine`, `bit32`; `SIM = false` and `DEBUG_CPU = false`; every variable `local`; main-chunk locals well under 200 (LuaLS `local-limit`); no allocation in `loop()`/`printRpm` beyond `rpmText` and the form's live row. Run `python tools/check.py` (0 errors) and LuaLS (no errors)
- [ ] T054 MANUAL: Transmitter checks 27–28 (telemetry-loss timing with the receiver off; install on a card with no other AG- apps, SC-007) and quickstart section 4 bench test with a real ECU (start overshoot never drops below the arming threshold, Cut shutdown silent, sensor label and unit). Record a Jeti log of a start and shutdown for future defaults
- [ ] T055 Record the transmitter findings from T046, T049 and T054 in `docs/jeti-api-notes.md` (gap between `playBeep` repeats, firmware telemetry "valid" timeout, sweep CPU figure, whether `stopPlayback(AUDIO_IMMEDIATE)` cuts mid-file cleanly) and in `specs/003-flameout-alarm/research.md` where they settle an open point

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: T001 → T002 → T003. T004 and T005 any time. The app can be built before T002 (it falls back to beeps), but T020 onward listen for real files only on the transmitter.
- **Foundational (Phase 2)**: depends on Phase 1's T005 for emulator testing only. Blocks all stories.
- **US1 (Phase 3)**: after Phase 2. The MVP core.
- **US2 (Phase 4)**: after US1 (fills `onCut`, uses arming and the alarm).
- **US3 (Phase 5)**: after Phase 2; independent of US1/US2 in code, but run after them since all share one file.
- **US4, US5, US6 (Phases 6–8)**: after US1 (they extend `stepFlameout`, `onCut` and `onInvalid`); US5 after US2.
- **US7 (Phase 9)**: after Phase 2 (only replaces the print function); best after US6 so every state exists to draw.
- **US8 (Phase 10)**: after US1 (reuses `playCycle`/`stopAlarm`).
- **Polish (Phase 11)**: after the stories; T050–T052 can start any time.

### Within Each User Story

- Code tasks in order (one file), then the MANUAL check.
- Run `python tools/check.py` at the end of each phase.

### Parallel Opportunities

- T001, T004, T005 (different files) in Phase 1.
- T050, T051, T052 (README, CREDITS, CLAUDE.md) alongside any app phase.
- MANUAL checks of one phase can run while the next phase's code is written.

---

## Parallel Example: Setup and docs

```text
Task: "T001 Create tools/voice/make_flameout.py"
Task: "T005 Add the turbine sensor to tools/emulator/sensors.json"
Task: "T050 Update README.md"
Task: "T051 Update CREDITS.md"
```

---

## Implementation Strategy

### MVP First (P1 stories: US1–US3)

1. Phase 1 (sounds, emulator sensor) and Phase 2 (app frame).
2. US1: the alarm. **Validate** in the emulator (T020).
3. US2: no false alarms, Cut. **Validate** with `SIM` (T024).
4. US3: full settings. **Validate** (T031). This is a usable alarm.

### Incremental Delivery

5. US4 relight, US5 Cut stop, US6 telemetry loss: each validated in the emulator.
6. US7 the sweep window: emulator, then the transmitter screenshot.
7. US8 test switch: then hear everything on the transmitter (T049).
8. Polish, transmitter and bench checks, docs. Release as `AG-FlmOt-v0.1.0` after a PR to develop and then main (CLAUDE.md).

---

## Notes

- [P] tasks = different files, no dependencies.
- MANUAL tasks stay unticked until the user reports the result.
- Commit after each phase.
- The filename `AG-FlmOt.lua` becomes permanent at the first release (constitution V).
