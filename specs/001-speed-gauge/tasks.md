---

description: "Task list for Speed Gauge (AG-SpdGa)"
---

# Tasks: Speed Gauge

**Input**: Design documents from `specs/001-speed-gauge/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: The spec does not ask for automated tests. The only test task is
the optional `tests/test_ag_dens.lua` the plan lists (T027). Validation is
the manual emulator scenarios in [quickstart.md](quickstart.md).

**Organization**: Tasks are grouped by user story so each story can be built
and checked on its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1–US5)
- **MANUAL**: Needs a person at JETI Studio or the transmitter. An agent
  can't run the emulator (CLAUDE.md): it prepares the build, lists what to
  check, and leaves the box unticked until the user reports back.

## Rules for every code task

- Follow `docs/examples/style/HELLO.lua`: 2-space indent, every variable and
  function `local` (constitution II), sections in the order given in
  [plan.md](plan.md#source-code-repository-root).
- Call only APIs declared in `types/jeti.lua` (constitution III). Never call
  `system.registerControl`, `system.setControl` or `system.setProperty`.
- `lcd.*` only in the print function or `ag_gauge` helpers called from it;
  `form.*` only in `initForm`, form callbacks and `keyForm` (constitution VI).
- No `string.format`, `..` or `{}` in `loop()` or the print function, except
  when rebuilding a cached string because its value changed (constitution VI).
- Nearly all app work is in the single file `src/Apps/AG-SpdGa.lua`, so tasks
  that touch it run one after another.
- Run `python tools/check.py` after each phase. It must report 0 errors.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Asset folder, credits, and the one emulator fact the layout needs

- [ ] T001 Create `src/Apps/AG-SpdGa/` and copy these five files, byte for byte, from `docs/examples/dfm-speed-announce/DFM-SpdA/`: `airspeed_alive.wav`, `airspeed_cal_factor.wav`, `overspeed.wav`, `stall_speed_warning_at.wav`, `stall_warning.wav`. Do not copy `V_ref_speed.wav` or `Spd_ann_act.wav` (research R11 #12)
- [ ] T002 [P] Create `src/Apps/AG-SpdGa/CREDITS.txt` (UTF-8, LF): state that these WAV files come unmodified from DFM Speed Announcer v2.1 by DFM (Dave McQueeney), https://github.com/davidmcq137/JetiLuaDFM. Include the MIT notice copied verbatim from the Speed Gauge section of `CREDITS.md` ("Copyright (c) 2018, 2019 DFM (Dave McQueeney)" plus the full permission text), and point to `CREDITS.md` in the repository (FR-029, constitution VIII)
- [ ] T003 [P] MANUAL: Measure telemetry window sizes (quickstart step 1, research R7). Copy `docs/examples/jeti-demos/10_telemw.lua` to `%LOCALAPPDATA%\JETI-Studio\Emulator\Apps`, add it, place both windows and note the printed `w x h`. Record the result under "Forms" or a new "Telemetry windows" heading in `docs/jeti-api-notes.md`. If the sizes aren't about 152×69 and 152×146, update the layout sizes in `specs/001-speed-gauge/contracts/telemetry-window.md`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The app file, settings storage, the per-tick speed pipeline and the settings form's frame. Every story builds on these.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [ ] T004 Create `src/Apps/AG-SpdGa.lua` with this header, matching HELLO.lua: line 1 `-- AG-SpdGa.lua — Speed Gauge: speed callouts, stall/overspeed warnings and a speedometer telemetry window.`, then `-- Copyright (c) 2026 Aaron George` and `-- SPDX-License-Identifier: MIT`, then a comment block: "Based on DFM Speed Announcer v2.1 by DFM (Dave McQueeney), https://github.com/davidmcq137/JetiLuaDFM. Portions Copyright (c) 2018, 2019 DFM (Dave McQueeney), MIT License. Full license text in CREDITS.md." plus one line stating the app never controls the model (constitution I). Add constants `APP_NAME = "Speed Gauge"`, `APP_VERSION = "0.1.0"`, `AUDIO_DIR = "/Apps/AG-SpdGa/"`, `TICK_MS = 100`, and the unit tables `UNITS_TEXT = {"mph","km/h","kt","m/s","ft/s"}`, `UNITS_SPOKEN = {"mph","km/h","kt.","m/s","ft./s"}`, `UNITS_MULT = {2.23694, 3.6, 1.94384, 1.0, 3.28084}` (sensor value is m/s, research R3), `UNITS_IMPERIAL = {true, false, true, false, true}`. End with `---@type JetiApp` and `return { init = init, loop = loop, destroy = destroy, author = "Aaron George", version = APP_VERSION, name = APP_NAME }`
- [ ] T005 Add persisted-setting key constants and a `loadSettings()` called from `init()` in `src/Apps/AG-SpdGa.lua`, using exactly the 24 keys, types and defaults of the settings table in `specs/001-speed-gauge/data-model.md`: `sId` int "sensor id, 0 = none" default 0; `sPar` int default 0; `sLbl` "string < 64 B" default ""; `sType` "1 Airspeed, 2 GPS" default 1; `swOn`, `swCont` SwitchItem default nil; `tMin` "1–10" default 2; `tMax` "10–60" default 40; `sens` "1–100" default 10; `vLand` "0–1000" default 60; `vStall` "0–1000" default 45; `vOver` "0–1000" default 200; `cal` "1–200" default 100; `units` "1 mph, 2 km/h, 3 kt, 4 m/s, 5 ft/s" default 1; `numOnly` 0/1 default 0; `startAnn` 0/1 default 1; `densOn` 0/1 default 0; `elev` "−1000–15000 ft / −300–4600 m" default 0; `temp` "−22–122 °F / −30–50 °C" default 59 when `UNITS_IMPERIAL[units]` else 15 (load `units` first); `tStd` 0/1 default 1; `colCur` "1–8" default 1; `colMax` "1–8" default 2; `fScale` "0 = Auto, 10–2000" default 0; `cfgV` default 1. Store booleans as integers 0/1, never floats (constitution IV)
- [ ] T006 Add derived values and their recompute functions in `src/Apps/AG-SpdGa.lua`, per "Derived values" in `specs/001-speed-gauge/data-model.md`: `recomputeSensor()` sets `kSensor = UNITS_MULT[units] * cal / 100`; `recomputeDensity()` sets `kDens = 1` for now (US4 replaces the body); `recomputeScale()` sets `fullScale = fScale` if non-zero, else `math.ceil(vOver * 1.15 / 10) * 10`, then `fStall = clamp(vStall * kDens / fullScale, 0, 1)` and `fOver = clamp(vOver / fullScale, 0, 1)`; `recomputeUnitText()` sets `unitText = UNITS_TEXT[units]` and `unitSpoken = UNITS_SPOKEN[units]`. `recomputeAll()` calls them in order (density before scale) and is called from `init()` after `loadSettings()`
- [ ] T007 Add session state and `resetSession()` in `src/Apps/AG-SpdGa.lua`, per "Session state" in `specs/001-speed-gauge/data-model.md`: `sensorSpd = nil`, `shownSpd = nil`, `maxSpd = 0`, `prevDistinct = nil`, `everAboveHalf = false`, `everAboveLanding = false`, `belowLanding = false`, `aliveSaid = false`, `stallArmed = true`, `overArmed = true`, `lastSpokenSpd = 0`, `lastSpokenAt = 0`, `lastTick = system.getTimeCounter()`, `curText = "---"`, `maxText = "0"`. Call it from `init()`. Do not persist any of these (FR-019)
- [ ] T008 Implement `loop()` in `src/Apps/AG-SpdGa.lua`: return unless `now - lastTick >= TICK_MS`, then set `lastTick = now`. If `sId == 0`, or `system.getSensorValueByID(sId, sPar)` returns nil or `.valid` is false, set `sensorSpd = nil` and `shownSpd = nil` and return: no flags, max, warnings or callouts change (spec Edge Cases). Otherwise set `sensorSpd = value * kSensor` and `shownSpd = sensorSpd * kDens`, then update the flight flags from "State transitions" in data-model.md: `sensorSpd > vLand / 2` → `everAboveHalf = true` (latched); `sensorSpd > vLand` → `everAboveLanding = true`, `belowLanding = false`; `sensorSpd <= vLand` and `everAboveLanding` → `belowLanding = true`. Leave clearly named empty local functions `updateMax()`, `checkWarnings(now)` and `checkCallout(now)`, called in that order, for US3, US2 and US1 to fill in. Add `destroy()` that does nothing but exists for firmware 5.00+
- [ ] T009 Add the settings form frame in `src/Apps/AG-SpdGa.lua`: `system.registerForm(1, MENU_APPS, APP_NAME, initForm, keyForm)` in `init()`. `initForm()` adds the five group headings as `FONT_BOLD` labels in this order: "Sensor and switches", "Callouts", "Warnings", "Air density", "Gauge" (US5 #1). It ends with a right-aligned `FONT_MINI` footer "Speed Gauge 0.1.0 - Based on DFM Speed Announcer by Dave McQueeney", built from `APP_VERSION` (FR-029). `keyForm(keyCode)` is empty. Use plain ASCII in labels: no `·` or `≥` (contracts/settings-form.md "Characters")
- [ ] T010 Add the "Sensor and switches" rows 1, 3, 4 and 5 from `specs/001-speed-gauge/contracts/settings-form.md` in `src/Apps/AG-SpdGa.lua`. Sensor selectbox (`enableForm = true`), rebuilt on every `initForm()` from `system.getSensors()` per research R4: entry 1 "(none)"; skip `param == 0`, `type == 5` and `type == 9`; keep parallel id/param arrays; if the saved `sId`/`sPar` isn't in the list, add "<sLbl> (not found)" and select it. On change, save `sId`, `sPar` and `sLbl` (label cut to 63 bytes); "(none)" saves `sId = 0`. Sensor type selectbox {"Airspeed (pitot)", "GPS"} saves `sType`, calls `recomputeAll()`, and shows a `FONT_MINI` hint "GPS: warnings use ground speed, wind shifts them" only when `sType == 2` (use `form.setProperties(idx, {visible = ...})`). Units selectbox (`UNITS_TEXT`) saves `units` and calls `recomputeAll()`; conversion comes in US5 (T031). Sensor calibration (%) intbox `1, 200, 100, 0, 1` saves `cal`, calls `recomputeSensor()`, with hint row "100 = unchanged"
- [ ] T011 Run `python tools/check.py` and fix any errors in `src/Apps/AG-SpdGa.lua`. Check the VS Code Problems panel (LuaLS) shows no errors for `src/Apps/**`

**Checkpoint**: The app loads, the settings form opens with its groups and sensor rows, and `loop()` computes speeds. Nothing is spoken or drawn yet.

---

## Phase 3: User Story 1 - Hear speed during flight (Priority: P1) 🎯 MVP

**Goal**: Variable-interval speed callouts, fast below landing speed, continuous mode, never overlapping (FR-005–FR-009)

**Independent Test**: In the emulator with a simulated speed sensor, select the sensor and a switch, turn it on and vary the speed. Callouts are ~40 s apart at steady speed, ~20 s with 10-unit changes, 2 s below landing speed (quickstart scenarios 3–5, 11–13).

### Implementation for User Story 1

- [ ] T012 [US1] Add the two switch rows (contracts/settings-form.md rows 6 and 7) to "Sensor and switches" in `src/Apps/AG-SpdGa.lua`: "Callouts on/off switch" and "Continuous callouts switch", each `form.addInputbox(item, true, callback)`, saving `swOn` / `swCont`. Add `local function switchOn(item)` that returns false for nil, else `system.getInputsVal(item) > 0.5`, treating a nil value as false (research R10)
- [ ] T013 [US1] Add the "Callouts" rows 8–14 from `specs/001-speed-gauge/contracts/settings-form.md` in `src/Apps/AG-SpdGa.lua`. Speed labels include the unit, built from `unitText` when the form is built, e.g. "Callout sensitivity (mph)". Rows: `sens` intbox `1, 100, 10, 0, 1` + hint "Speak sooner when speed changes by this much"; "Shortest time between callouts (s)" `tMin` intbox `1, 10, 2, 0, 1`; "Longest time between callouts (s)" `tMax` intbox `10, 60, 40, 0, 1`; "Landing speed (<unit>)" `vLand` intbox `0, 1000, 60, 0, 1` + hint "Callouts every shortest time below this"; "Speak number only (no units)" checkbox saving `numOnly` as 0/1. Each callback saves its key with `system.pSave` immediately
- [ ] T014 [US1] Implement `checkCallout(now)` in `src/Apps/AG-SpdGa.lua` per research R9 and "Callout due" in data-model.md. Let `onSw = switchOn(swOn)` and `contSw = switchOn(swCont)`; return if neither is on. Compute `d = math.min(math.max(math.abs(shownSpd - lastSpokenSpd) / sens, 0.5), 10)` and `interval = math.min(tMin * 10000 / d, tMax * 1000)` ms. If `contSw` or `belowLanding`, use `interval = tMin * 1000`. Speak only if `not system.isPlayback()`, `now >= lastSpokenAt + interval` and (`contSw` or `everAboveHalf`). Then `n = math.floor(shownSpd + 0.5)`, `lastSpokenSpd = n`, `lastSpokenAt = now`. Short form `system.playNumber(n, 0)` when `numOnly == 1`, `contSw`, or `not everAboveLanding or belowLanding`; otherwise `system.playNumber(n, 0, unitSpoken, "Speed")` (contracts/audio-events.md)
- [ ] T015 [US1] MANUAL: Deploy per quickstart "Prerequisites" and run quickstart scenarios 3, 4, 5, 11, 12 and 13. Check SC-001 timings: 38–42 s steady, ~20 s, 2 s ±0.5

**Checkpoint**: US1 works alone. It is the MVP: a working speed announcer.

---

## Phase 4: User Story 2 - Stall, overspeed and "airspeed alive" warnings (Priority: P1)

**Goal**: One warning per threshold crossing, with sound and stick vibration, re-armed after moving back. Stall and landing use sensor speed; overspeed uses shown speed (FR-010–FR-012, FR-028).

**Independent Test**: Raise simulated speed above landing speed, lower it below stall, raise it above overspeed. Each warning plays exactly once per crossing (quickstart scenarios 1, 2, 6–10; SC-002).

### Implementation for User Story 2

- [ ] T016 [US2] Add the "Warnings" rows 17 and 18, and "Callouts" row 15, from `specs/001-speed-gauge/contracts/settings-form.md` in `src/Apps/AG-SpdGa.lua`: "Stall warning at (<unit>)" `vStall` intbox `0, 1000, 45, 0, 1`; "Overspeed warning at (<unit>)" `vOver` intbox `0, 1000, 200, 0, 1`. Both save and call `recomputeScale()`. Add "Announce stall speed at startup" checkbox saving `startAnn` 0/1 (FR-028)
- [ ] T017 [US2] Implement `checkWarnings(now)` in `src/Apps/AG-SpdGa.lua` per "State transitions" in `specs/001-speed-gauge/data-model.md` and `contracts/audio-events.md`. Re-arming always runs: `sensorSpd > vStall` → `stallArmed = true`; `shownSpd <= vOver` → `overArmed = true`. Firing happens only if `switchOn(swOn) or switchOn(swCont)`. Stall: `stallArmed and everAboveLanding and sensorSpd <= vStall` → `stallArmed = false`, `system.playFile(AUDIO_DIR .. "stall_warning.wav", AUDIO_IMMEDIATE)`, `system.vibration(true, 4)`. Overspeed: `overArmed and shownSpd > vOver` → `overArmed = false`, play `overspeed.wav` immediately, `system.vibration(true, 3)`. Alive: `everAboveHalf and not aliveSaid` → `aliveSaid = true`, play `airspeed_alive.wav` immediately. Build the three file paths once as module-level constants, not per call
- [ ] T018 [US2] Add the startup announcement at the end of `init()` in `src/Apps/AG-SpdGa.lua`, only when `startAnn == 1` (contracts/audio-events.md): if `cal ~= 100`, `system.playFile(AUDIO_DIR .. "airspeed_cal_factor.wav", AUDIO_QUEUE)` then `system.playNumber(cal, 0, "%")`; then `system.playFile(AUDIO_DIR .. "stall_speed_warning_at.wav", AUDIO_QUEUE)` and `system.playNumber(vStall, 0, unitSpoken)`
- [ ] T019 [US2] MANUAL: Run quickstart scenarios 1, 2, 6, 7, 8, 9 and 10. Confirm SC-002 (exactly one warning per crossing over 10 crossings, none before first exceeding landing speed) and that vibration fires

**Checkpoint**: US1 + US2 reproduce DFM Speed Announcer v2.1's audio behavior.

---

## Phase 5: User Story 3 - Speedometer gauge on the main screen (Priority: P2)

**Goal**: Round gauge in single and double telemetry windows with current speed, a sticky session max, stall/overspeed marks, colors and "no data" state (FR-013–FR-019)

**Independent Test**: Place the window in each size, vary simulated speed. The current indicator moves, the max marker stays at the peak, both numbers match (quickstart scenarios 14–21).

### Implementation for User Story 3

- [ ] T020 [P] [US3] Create `src/Apps/lib/ag_gauge.lua` per `specs/001-speed-gauge/contracts/lib-modules.md`. Header: one-line description, `-- Copyright (c) 2026 Aaron George`, `-- SPDX-License-Identifier: MIT`, and a note that draw functions may only be called from a registered print function. `local M = {}` with no mutable module-level state (constitution VII). `M.newDial(steps, startDeg, sweepDeg)` defaults 54, 225, 270; returns `{ n = steps, cx = {...}, sy = {...} }` holding `math.cos` / `-math.sin` of each of the `steps + 1` angles going clockwise from `startDeg` (screen y points down). `M.point(dial, f)` clamps `f` to 0..1 and returns an interpolated `cos, sin`. `M.arc(r, dial, cx, cy, radius, f, width)` returns if `f <= 0`, else `r:reset()`, adds the table points up to `floor(f * n)` plus the interpolated end point, `r:renderPolyline(width)`. `M.tick(dial, cx, cy, r1, r2, f)` and `M.needle(dial, cx, cy, radius, f)` use `lcd.drawLine`. `return M`
- [ ] T021 [US3] Implement `updateMax()` in `src/Apps/AG-SpdGa.lua` per research R5: only when `shownSpd ~= prevDistinct`, and only if `prevDistinct` is not nil, set `maxSpd = math.max(maxSpd, math.min(prevDistinct, shownSpd))`; then `prevDistinct = shownSpd`. Rebuild the cached strings only when the rounded value changes: keep `curRounded` / `maxRounded` integers and set `curText = tostring(curRounded)` / `maxText = tostring(maxRounded)` on change. When the reading is invalid (T008 early return), set `curText = "---"` once; don't rebuild it every tick
- [ ] T022 [US3] Add the "Gauge" rows 25–28 from `specs/001-speed-gauge/contracts/settings-form.md` in `src/Apps/AG-SpdGa.lua`. "Gauge full scale (<unit>, 0 = auto)" `fScale` intbox `0, 2000, 0, 0, 10` (step 10 keeps it at 0 or 10–2000). It saves and calls `recomputeScale()`, and updates a hint label "Auto: <fullScale>" via `form.setProperties` when `fScale == 0`. "Current speed color" and "Max speed color" selectboxes over the 8 color names save `colCur` / `colMax`. "Reset max speed" is a `form.addLink` that sets `maxSpd = 0`, `prevDistinct = nil`, `maxRounded = 0`, `maxText = "0"` (US3 #6)
- [ ] T023 [US3] In `src/Apps/AG-SpdGa.lua`, add `local gauge = require("ag_gauge")` and the color preset table from research R8, in this order: Blue (0,100,255), Orange (255,140,0), Red (220,0,0), Green (0,160,0), Magenta (200,0,200), Cyan (0,170,210), Black (0,0,0), White (255,255,255), with names for the selectboxes. In `init()` create `dial = gauge.newDial()` and register both windows: `system.registerTelemetry(1, "Speed Gauge", 1, printGauge)` and `system.registerTelemetry(2, "Speed Gauge large", 2, printGauge)`
- [ ] T024 [US3] Implement `printGauge(w, h)` in `src/Apps/AG-SpdGa.lua` per `specs/001-speed-gauge/contracts/telemetry-window.md`. Compact layout when `h < 100`, large otherwise, sized from `w`/`h`. Create the renderer lazily once (`if not rend then rend = lcd.renderer() end`) and reuse it (research R6). Draw back to front: track (foreground from `lcd.getFgColor()`, alpha ~60, width 2); stall tick at `fStall` (foreground); overspeed tick at `fOver` (red); max arc to `maxSpd / fullScale` width 2 plus tick, in `colMax`, only if `maxSpd > 0`; current arc width 5 and needle in `colCur`, only if `shownSpd` is not nil; then `curText`, `unitText` and "max " + `maxText` (the "max " prefix is a constant; draw it and `maxText` as two `drawText` calls). Current speed fractions clamp to 1; the number shows the real value (US3 #7). No data: no current arc or needle, `curText` shows "---", max stays. When text doesn't fit (`lcd.getTextWidth`), drop threshold labels, then unit text, then the "max" prefix, but never the two numbers. In the large layout show "S<vStall>" and "O<vOver>" labels from strings cached in `recomputeScale()`. Skip ticks in the compact layout if the dial diameter is under 50 px
- [ ] T025 [US3] MANUAL: Run quickstart scenarios 14–21 in both window sizes. Check the renderer-reuse item from quickstart step 1 (no glitches over 5 minutes) and the CPU figure in Applications → User Applications (< 20%, SC-007). If reuse fails, change T024 to create a renderer per frame and re-check CPU; record the finding in `docs/jeti-api-notes.md`

**Checkpoint**: US1–US3 work; the gauge is visible with correct max behavior.

---

## Phase 6: User Story 4 - Correct for air density (Priority: P2)

**Goal**: Optional true-airspeed correction from field elevation and temperature for airspeed sensors (FR-020–FR-023, FR-016a)

**Independent Test**: Steady simulated 100 mph; set 5,000 ft and 95 °F (35 °C); toggle correction. Reads ~113 on, 100 off (quickstart scenarios 22–27; SC-003, SC-003a).

### Tests for User Story 4 (optional, listed in plan.md)

- [ ] T026 [P] [US4] Create `tests/test_ag_dens.lua`: header with `-- Copyright (c) 2026 Aaron George` and `-- SPDX-License-Identifier: MIT`; prepend `src/Apps/lib/?.lua;` to `package.path`; `require("ag_dens")`. Assert within 0.001: `factor(0, nil) = 1.0000`, `factor(1524, nil) = 1.0773`, `factor(1524, 35) = 1.1337`, `factor(4572, 50) = 1.4097` (contracts/lib-modules.md); `stdTempC(0) = 15`; `mToFt(ftToM(5000))` ≈ 5000; `cToF(35) = 95`. Print a table of results and call `error()` on the first mismatch so the process exits non-zero. Do not use `os` (it runs on the desktop, but keep the habit)

### Implementation for User Story 4

- [ ] T027 [P] [US4] Create `src/Apps/lib/ag_dens.lua` per `specs/001-speed-gauge/contracts/lib-modules.md` and research R1. Header as in T020. `local M = {}` with constants `T0 = 288.15`, `LAPSE = 0.0065`, `EXP = 5.25588`. `M.stdTempC(elevM)` = `15 - 0.0065 * elevM`. `M.factor(elevM, tempC)`: `Ts = T0 - LAPSE * elevM`, `delta = (Ts / T0) ^ EXP`, `T = tempC and (tempC + 273.15) or Ts`, `sigma = delta * T0 / T`, return `1 / math.sqrt(sigma)`. `M.ftToM`, `M.mToFt` (0.3048), `M.fToC`, `M.cToF`. `return M`
- [ ] T028 [US4] Add the "Air density" rows 19–24 from `specs/001-speed-gauge/contracts/settings-form.md` in `src/Apps/AG-SpdGa.lua`: "Correct for air density" checkbox saving `densOn` 0/1, disabled via `form.setProperties(idx, {enabled = false})` when `sType == 2`; status label; "Field elevation (ft)" or "(m)" intbox saving `elev`, range `-1000, 15000` ft or `-300, 4600` m, step 10; "Temperature (°F)" or "(°C)" intbox saving `temp`, range `-22, 122` °F or `-30, 50` °C, step 1, disabled while `tStd == 1`; "Use standard temperature" checkbox saving `tStd` 0/1 that enables/disables the temperature intbox; hint "Leave correction off if your sensor already corrects for air density". Units come from `UNITS_IMPERIAL[units]` (FR-023)
- [ ] T029 [US4] Add `local dens = require("ag_dens")` near the top of `src/Apps/AG-SpdGa.lua` (T031 uses it too), then replace the body of `recomputeDensity()`: `elevM = imperial and dens.ftToM(elev) or elev`; `tempC = (tStd == 1) and nil or (imperial and dens.fToC(temp) or temp)`; `kDens = (densOn == 1 and sType == 1) and dens.factor(elevM, tempC) or 1`. Update the status label (form open only) to "Correction: +N%" with `N = math.floor((kDens - 1) * 100 + 0.5)` when on, "Not used with GPS" when `sType == 2`, empty otherwise (FR-022). Call `recomputeDensity()` then `recomputeScale()` from every density-row callback and from the sensor-type callback, so the stall mark moves to `vStall * kDens` (FR-016a). Stall/landing/alive checks keep using `sensorSpd` (FR-011)
- [ ] T030 [US4] MANUAL: Run quickstart scenarios 22–27 and, if a Lua 5.3 interpreter is available, `lua tests/test_ag_dens.lua`. Check SC-003 (100 / 108 / 113 ±1) and SC-003a (stall fires at sensor 40, gauge reads 43, needle on stall mark)

**Checkpoint**: US1–US4 work; readings are true airspeed when correction is on.

---

## Phase 7: User Story 5 - Settings that explain themselves (Priority: P2)

**Goal**: Grouped, plainly worded settings with units shown, illogical thresholds flagged, and units changes that convert values (FR-025, FR-026, Edge Cases)

**Independent Test**: Someone who hasn't seen the app sets up sensor, switch, landing speed and stall warning without help in under 3 minutes (SC-006; quickstart scenarios 28–31, 35).

### Implementation for User Story 5

- [ ] T031 [US5] Implement units conversion in the Units callback in `src/Apps/AG-SpdGa.lua` per "Units change" in `specs/001-speed-gauge/data-model.md`: from old unit A to new unit B, each of `sens`, `vLand`, `vStall`, `vOver` and non-zero `fScale` becomes `round(value · unitsMult[B] / unitsMult[A])`, clamped to its range (`sens` 1–100, speeds 0–1000, `fScale` 10–2000, rounded to a multiple of 10). If `UNITS_IMPERIAL[A] ~= UNITS_IMPERIAL[B]`, convert `elev` (ft↔m, clamp to the new range) and `temp` (°F↔°C, clamp) with `ag_dens`. Save every changed key, call `recomputeAll()`, then `form.reinit()` so labels and values redraw (quickstart scenario 31: 60 mph → 97 km/h)
- [ ] T032 [US5] Add the threshold-order warning (row 16, top of "Warnings") in `src/Apps/AG-SpdGa.lua` per FR-026: a label "Check: stall < landing < overspeed < full scale", visible only when `vStall >= vLand`, `vLand >= vOver`, or `fScale ~= 0 and vOver > fScale`. Add `checkOrder()` that sets `form.setProperties(idx, {visible = bad})`. Call it at the end of `initForm()` and from the `vStall`, `vLand`, `vOver` and `fScale` callbacks. Values are still saved when illogical
- [ ] T033 [US5] Review every label, hint and group in `initForm()` in `src/Apps/AG-SpdGa.lua` against the spec's User Story 5 table and `specs/001-speed-gauge/contracts/settings-form.md`. Row order 1–28 and the five groups must match; every speed setting shows the unit; hints as listed. Confirm SC-008: every v2.1 setting is present under its new name, or listed as changed in research R11
- [ ] T034 [US5] MANUAL: Check `°` renders in the settings form (quickstart step 1). If not, change the labels to "deg F" / "deg C" in `src/Apps/AG-SpdGa.lua` and record it in `docs/jeti-api-notes.md`. Run quickstart scenarios 28–31 and 35 (SC-006)

**Checkpoint**: All five user stories are complete.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, credits, performance review, full validation

- [ ] T035 [P] Update the Apps table in `README.md`: Status "Spec written" → "In development" (→ "Released" at release), and link the script `src/Apps/AG-SpdGa.lua`. Keep the "Based on" credit unchanged (constitution VIII)
- [ ] T036 [P] Update the Apps table in `CLAUDE.md`: change `` `src/Apps/AG-SpdGa.lua` (planned) `` to `` `src/Apps/AG-SpdGa.lua` ``
- [ ] T037 [P] In `CREDITS.md`, add one sentence to the Speed Gauge section pointing to `src/Apps/AG-SpdGa/CREDITS.txt` for the WAV files' credit. Do not remove or shorten any existing text (constitution VIII)
- [ ] T038 [P] Record the verified API facts from T003, T025 and T034 (window sizes, renderer reuse, `°` rendering) in `docs/jeti-api-notes.md`. If any contradicts `types/jeti.lua`, update the stub with a source note
- [ ] T039 Review `loop()`, `checkCallout`, `checkWarnings`, `updateMax` and `printGauge` in `src/Apps/AG-SpdGa.lua` for constitution VI: no `string.format`, `..` or table constructors outside the value-changed branches; no `getSensors`/`getSensorByID` in the loop; trig only in `ag_gauge.newDial`. Confirm `src/Apps/lib/ag_dens.lua` and `src/Apps/lib/ag_gauge.lua` hold no mutable module-level state (constitution VII)
- [ ] T040 Run `python tools/check.py` (0 errors) and confirm the LuaLS Problems panel shows no errors for `src/Apps/AG-SpdGa.lua`, `src/Apps/lib/ag_dens.lua` and `src/Apps/lib/ag_gauge.lua`
- [ ] T041 MANUAL: Run the full `specs/001-speed-gauge/quickstart.md` (steps 0–3, including scenarios 32–34 and the resource checks), then step 4 on a dedicated test model on the transmitter

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies. T003's window sizes are needed before T024
- **Foundational (Phase 2)**: Depends on Setup (T001 for audio paths). BLOCKS all user stories
- **US1 (Phase 3)**: Depends on Foundational
- **US2 (Phase 4)**: Depends on Foundational. Uses `switchOn()` from T012, so do it after US1 or move T012 first
- **US3 (Phase 5)**: Depends on Foundational. T020 can start any time
- **US4 (Phase 6)**: Depends on Foundational. T026/T027 can start any time; T029 moves the stall mark, which is only visible once US3 is done
- **US5 (Phase 7)**: Depends on the rows it reviews and converts, so do it after US1–US4
- **Polish (Phase 8)**: After all desired stories

### User Story Dependencies

```text
Setup → Foundational → US1 (MVP) → US2 → US3 → US4 → US5 → Polish
                         │           ▲
                         └ switchOn ─┘
Independent files, any time after Setup: T020 ag_gauge.lua, T026 test, T027 ag_dens.lua
```

### Within Each User Story

- Settings rows before the logic that reads them
- Logic before the MANUAL validation task that closes the story
- Commit after each task or logical group on `feature/001-speed-gauge`

### Parallel Opportunities

- T002 and T003 run alongside T001
- T020 (`ag_gauge.lua`), T026 (`tests/test_ag_dens.lua`) and T027 (`ag_dens.lua`) are separate files with no dependencies. They can be written at any point, including during Phase 2
- T035–T038 are four different documentation files
- Everything in `src/Apps/AG-SpdGa.lua` is sequential

---

## Parallel Example: User Story 3 and 4 modules

```text
# While Phase 2 is in progress on src/Apps/AG-SpdGa.lua:
Task: "T020 Create src/Apps/lib/ag_gauge.lua per contracts/lib-modules.md"
Task: "T027 Create src/Apps/lib/ag_dens.lua per contracts/lib-modules.md and research R1"
Task: "T026 Create tests/test_ag_dens.lua with the R1 reference values"
```

## Parallel Example: Polish

```text
Task: "T035 Update README.md apps table"
Task: "T036 Update CLAUDE.md apps table"
Task: "T037 Add CREDITS.txt pointer to CREDITS.md"
Task: "T038 Record verified API facts in docs/jeti-api-notes.md"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1: Setup
2. Phase 2: Foundational (blocks everything)
3. Phase 3: US1
4. **STOP and VALIDATE** in the emulator (T015): a working speed announcer
5. Then add US2 so the warnings exist before any real flight. US1 alone is
   not for flying, because it has no stall warning

### Incremental Delivery

1. Setup + Foundational → app loads, settings open
2. + US1 → callouts (MVP, emulator only)
3. + US2 → parity with DFM v2.1 audio; first candidate for a test-model bench run
4. + US3 → gauge
5. + US4 → density correction
6. + US5 → settings polish and units conversion
7. Polish → docs and full validation → merge `feature/001-speed-gauge` into `develop`

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps each task to a user story for traceability
- MANUAL tasks stay unticked until the user reports the result
- Stop at any checkpoint to validate a story on its own
- Never merge to `develop` before T040 passes and the MANUAL tasks are done
