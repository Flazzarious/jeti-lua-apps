---

description: "Task list for Speed Gauge (AG-SpdGa)"
---

# Tasks: Speed Gauge

**Input**: Design documents from `specs/001-speed-gauge/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: The spec does not ask for automated tests. The only test task is
the optional `tests/test_ag_dens.lua` the plan lists (T031). Validation is
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
- Call `system.getSensor*` through `system` every time. Never keep a local
  copy of those functions, because the emulator's telemetry app replaces them
  (research R3).
- `lcd.*` only in the print function or `ag_gauge` draw helpers called from
  it; `form.*` only in `initForm`, form callbacks and `keyForm`
  (constitution VI).
- No `string.format`, `..` or `{}` in `loop()` or the print function, except
  when rebuilding a cache because its inputs changed (constitution VI).
- Nearly all app work is in the single file `src/Apps/AG-SpdGa.lua`, so tasks
  that touch it run one after another.
- Run `python tools/check.py` after each phase. It must report 0 errors.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Asset folder, credits, and the emulator facts the gauge layout needs

- [X] T001 Create `src/Apps/AG-SpdGa/` and copy these five files, byte for byte, from `docs/examples/dfm-speed-announce/DFM-SpdA/`: `airspeed_alive.wav`, `airspeed_cal_factor.wav`, `overspeed.wav`, `stall_speed_warning_at.wav`, `stall_warning.wav`. Do not copy `V_ref_speed.wav` or `Spd_ann_act.wav` (research R11 #12)
- [X] T002 [P] Create `src/Apps/AG-SpdGa/CREDITS.txt` (UTF-8, LF): state that these WAV files come unmodified from DFM Speed Announcer v2.1 by DFM (Dave McQueeney), https://github.com/davidmcq137/JetiLuaDFM. Include the MIT notice copied verbatim from the Speed Gauge section of `CREDITS.md` ("Copyright (c) 2018, 2019 DFM (Dave McQueeney)" plus the full permission text), and point to `CREDITS.md` in the repository (FR-029, constitution VIII)
- [x] T003 Measure the telemetry window sizes (research R7). Done 2026-09-27 with `tools/probe/PROBE.lua`: 157 × 60, 157 × 127, 320 × 260, recorded in `docs/jeti-api-notes.md`
- [X] T004 [P] Add `MODE = 3` to `tools/probe/PROBE.lua`: register window 1 "Probe auto" with size 0 and window 2 "Probe small" with size 1, both drawing with the existing `drawInfo`. Update the header comment listing the modes. Keep `MODE` defaulting to its current value
- [ ] T005 MANUAL: With `tools/probe/PROBE.lua` in the emulator (MODE 3, then MODE 1), record in `docs/jeti-api-notes.md`: (a) whether "Probe auto" lets you place it at single or double size, and the sizes it reports (research R7); (b) the "PROBE device:" string from the Lua console, and on the transmitter too if possible (research R12); (c) the font heights from the "fonts N/B/M/Mx" line. If size 0 does not let the pilot choose, write "size 0: use winSz fallback" in the notes, so T028 applies

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The app file, settings storage, the per-tick speed pipeline and the settings form's frame. Every story builds on these.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T006 Create `src/Apps/AG-SpdGa.lua` with this header, matching HELLO.lua: line 1 `-- AG-SpdGa.lua — Speed Gauge: speed callouts, stall/overspeed warnings and a speedometer telemetry window.`, then `-- Copyright (c) 2026 Aaron George` and `-- SPDX-License-Identifier: MIT`, then a comment block: "Based on DFM Speed Announcer v2.1 by DFM (Dave McQueeney), https://github.com/davidmcq137/JetiLuaDFM. Portions Copyright (c) 2018, 2019 DFM (Dave McQueeney), MIT License. Full license text in CREDITS.md." plus one line stating the app never controls the model (constitution I). Add constants `APP_NAME = "Speed Gauge"`, `APP_VERSION = "0.1.0"`, `AUDIO_DIR = "/Apps/AG-SpdGa/"`, `TICK_MS = 100`, and the unit tables `UNITS_TEXT = {"mph","km/h","kt","m/s","ft/s"}`, `UNITS_SPOKEN = {"mph","km/h","kt.","m/s","ft./s"}`, `UNITS_MULT = {2.23694, 3.6, 1.94384, 1.0, 3.28084}` (sensor value is m/s, research R3), `UNITS_IMPERIAL = {true, false, true, false, true}`. End with `---@type JetiApp` and `return { init = init, loop = loop, destroy = destroy, author = "Aaron George", version = APP_VERSION, name = APP_NAME }`
- [X] T007 Add persisted-setting key constants and a `loadSettings()` called from `init()` in `src/Apps/AG-SpdGa.lua`, using exactly the keys, types and defaults of the settings table in `specs/001-speed-gauge/data-model.md`: `sId` int "sensor id, 0 = none" default 0; `sPar` int default 0; `sLbl` "string < 64 B" default ""; `sType` "1 Airspeed, 2 GPS" default 1; `swOn`, `swCont` SwitchItem default nil; `tMin` "1–10" default 2; `tMax` "10–60" default 40; `sens` "1–100" default 10; `vLand` "0–1000" default 60; `vStall` "0–1000" default 45; `vOver` "0–1000" default 200; `cal` "1–200" default 100; `units` "1 mph, 2 km/h, 3 kt, 4 m/s, 5 ft/s" default 1; `numOnly` 0/1 default 0; `startAnn` 0/1 default 1; `densOn` 0/1 default 0; `elev` "−1000–15000 ft / −300–4600 m" default 0; `temp` "−22–122 °F / −30–50 °C" default 59 when `UNITS_IMPERIAL[units]` else 15 (load `units` first); `tStd` 0/1 default 1; `colCur` "1–8" default 1 (Cyan); `colMax` "1–8" default 3 (White); `fScale` "0 = Auto, 10–2000" default 0; `cfgV` default 1. Do not add `winSz` here (T028 adds it only if needed). Store booleans as integers 0/1, never floats (constitution IV)
- [X] T008 Add derived values and their recompute functions in `src/Apps/AG-SpdGa.lua`, per "Derived values" in `specs/001-speed-gauge/data-model.md`: `recomputeSensor()` sets `kSensor = UNITS_MULT[units] * cal / 100`; `recomputeDensity()` sets `kDens = 1` for now (US4 replaces the body); `recomputeScale()` sets `fullScale = fScale` if non-zero, else `math.ceil(vOver * 1.15 / 10) * 10`, then `fStall = clamp(vStall * kDens / fullScale, 0, 1)`, `fLand = clamp(vLand * kDens / fullScale, 0, 1)` and `fOver = clamp(vOver / fullScale, 0, 1)`, and marks the layout cache stale (implemented as a `scaleVer` counter that layouts compare, used by US3); `recomputeUnitText()` sets `unitText = UNITS_TEXT[units]` and `unitSpoken = UNITS_SPOKEN[units]`. `recomputeAll()` calls them in order (density before scale) and is called from `init()` after `loadSettings()`
- [X] T009 Add session state and `resetSession()` in `src/Apps/AG-SpdGa.lua`, per "Session state" in `specs/001-speed-gauge/data-model.md`: `sensorSpd = nil`, `shownSpd = nil`, `maxSpd = 0`, `prevDistinct = nil`, `everAboveHalf = false`, `everAboveLanding = false`, `belowLanding = false`, `aliveSaid = false`, `stallArmed = true`, `overArmed = true`, `lastSpokenSpd = 0`, `lastSpokenAt = 0`, `lastTick = system.getTimeCounter()`, `curText = "---"`, `maxText = "0"`, `sensText = ""`. Call it from `init()`. Do not persist any of these (FR-019)
- [X] T010 Implement `loop()` in `src/Apps/AG-SpdGa.lua`: return unless `now - lastTick >= TICK_MS`, then set `lastTick = now`. If `sId == 0`, or `system.getSensorValueByID(sId, sPar)` (called through `system`, research R3) returns nil or `.valid` is false, set `sensorSpd = nil` and `shownSpd = nil` and return: no flags, max, warnings or callouts change (spec Edge Cases). Otherwise set `sensorSpd = value * kSensor` and `shownSpd = sensorSpd * kDens`, then update the flight flags from "State transitions" in data-model.md: `sensorSpd > vLand / 2` → `everAboveHalf = true` (latched); `sensorSpd > vLand` → `everAboveLanding = true`, `belowLanding = false`; `sensorSpd <= vLand` and `everAboveLanding` → `belowLanding = true`. Leave clearly named empty local functions `updateMax()`, `checkWarnings(now)` and `checkCallout(now)`, called in that order, for US3, US2 and US1 to fill in. Add `destroy()` that does nothing but exists for firmware 5.00+
- [X] T011 Add the settings form frame in `src/Apps/AG-SpdGa.lua`: `system.registerForm(1, MENU_APPS, APP_NAME, initForm, keyForm)` in `init()`. `initForm()` adds the five group headings as `FONT_BOLD` labels in this order: "Sensor and switches", "Callouts", "Warnings", "Air density", "Gauge" (US5 #1). It ends with a right-aligned `FONT_MINI` footer "Speed Gauge 0.1.0 - Based on DFM Speed Announcer by Dave McQueeney", built from `APP_VERSION` (FR-029). `keyForm(keyCode)` is empty. Use plain ASCII in labels: no `·` or `≥` (contracts/settings-form.md "Characters")
- [X] T012 Add the "Sensor and switches" rows 1, 3, 4 and 5 from `specs/001-speed-gauge/contracts/settings-form.md` in `src/Apps/AG-SpdGa.lua`. Sensor selectbox (`enableForm = true`), rebuilt on every `initForm()` from `system.getSensors()` per research R4: entry 1 "(none)"; skip `param == 0`, `type == 5` and `type == 9`; keep parallel id/param arrays; if the saved `sId`/`sPar` isn't in the list, add "<sLbl> (not found)" and select it. On change, save `sId`, `sPar` and `sLbl` (label cut to 63 bytes); "(none)" saves `sId = 0`. Sensor type selectbox {"Airspeed (pitot)", "GPS"} saves `sType`, calls `recomputeAll()`, and shows a `FONT_MINI` hint "GPS: warnings use ground speed, wind shifts them" only when `sType == 2` (`form.setProperties(idx, {visible = ...})`). Units selectbox (`UNITS_TEXT`) saves `units` and calls `recomputeAll()`; conversion comes in US5 (T036). Sensor calibration (%) intbox `1, 200, 100, 0, 1` saves `cal`, calls `recomputeSensor()`, with hint row "100 = unchanged"
- [X] T013 Run `python tools/check.py` and fix any errors in `src/Apps/AG-SpdGa.lua`. Check the VS Code Problems panel (LuaLS) shows no errors for `src/Apps/**`

**Checkpoint**: The app loads, the settings form opens with its groups and sensor rows, and `loop()` computes speeds. Nothing is spoken or drawn yet.

---

## Phase 3: User Story 1 - Hear speed during flight (Priority: P1) 🎯 MVP

**Goal**: Variable-interval speed callouts, fast below landing speed, continuous mode, never overlapping (FR-005–FR-009)

**Independent Test**: In the emulator with `tools/emulator/sensors.json` loaded, select "MSpeed 450 / Velocity" (P5) and a switch, turn it on and move P5. Callouts are ~40 s apart at steady speed, ~20 s with 10-unit changes, 2 s below landing speed (quickstart scenarios 3–5, 11–13).

### Implementation for User Story 1

- [X] T014 [US1] Add the two switch rows (contracts/settings-form.md rows 6 and 7) to "Sensor and switches" in `src/Apps/AG-SpdGa.lua`: "Callouts on/off switch" and "Continuous callouts switch", each `form.addInputbox(item, true, callback)`, saving `swOn` / `swCont`. Add `local function switchOn(item)` that returns false for nil, else `system.getInputsVal(item) > 0.5`, treating a nil value as false (research R10)
- [X] T015 [US1] Add the "Callouts" rows 8–14 from `specs/001-speed-gauge/contracts/settings-form.md` in `src/Apps/AG-SpdGa.lua`. Speed labels include the unit, built from `unitText` when the form is built, e.g. "Callout sensitivity (mph)". Rows: `sens` intbox `1, 100, 10, 0, 1` + hint "Speak sooner when speed changes by this much"; "Shortest time between callouts (s)" `tMin` intbox `1, 10, 2, 0, 1`; "Longest time between callouts (s)" `tMax` intbox `10, 60, 40, 0, 1`; "Landing speed (<unit>)" `vLand` intbox `0, 1000, 60, 0, 1` + hint "Callouts every shortest time below this" (its callback also calls `recomputeScale()` for the landing mark); "Speak number only (no units)" checkbox saving `numOnly` as 0/1. Each callback saves its key with `system.pSave` immediately
- [X] T016 [US1] Implement `checkCallout(now)` in `src/Apps/AG-SpdGa.lua` per research R9 and "Callout due" in data-model.md. Let `onSw = switchOn(swOn)` and `contSw = switchOn(swCont)`; return if neither is on. Compute `d = math.min(math.max(math.abs(shownSpd - lastSpokenSpd) / sens, 0.5), 10)` and `interval = math.min(tMin * 10000 / d, tMax * 1000)` ms. If `contSw` or `belowLanding`, use `interval = tMin * 1000`. Speak only if `not system.isPlayback()`, `now >= lastSpokenAt + interval` and (`contSw` or `everAboveHalf`). Then `n = math.floor(shownSpd + 0.5)`, `lastSpokenSpd = n`, `lastSpokenAt = now`. Short form `system.playNumber(n, 0)` when `numOnly == 1`, `contSw`, or `not everAboveLanding or belowLanding`; otherwise `system.playNumber(n, 0, unitSpoken, "Speed")` (contracts/audio-events.md)
- [ ] T017 [US1] MANUAL: Deploy per quickstart "Prerequisites" and run quickstart scenarios 3, 4, 5, 11, 12 and 13. Check SC-001 timings: 38–42 s steady, ~20 s, 2 s ±0.5

**Checkpoint**: US1 works alone. It is the MVP: a working speed announcer.

---

## Phase 4: User Story 2 - Stall, overspeed and "airspeed alive" warnings (Priority: P1)

**Goal**: One warning per threshold crossing, with sound and stick vibration, re-armed after moving back. Stall and landing use sensor speed; overspeed uses shown speed (FR-010–FR-012, FR-028).

**Independent Test**: Move P5 above landing speed, below stall, then above overspeed. Each warning plays exactly once per crossing (quickstart scenarios 1, 2, 6–10; SC-002).

### Implementation for User Story 2

- [X] T018 [US2] Add the "Warnings" rows 17 and 18, and "Callouts" row 15, from `specs/001-speed-gauge/contracts/settings-form.md` in `src/Apps/AG-SpdGa.lua`: "Stall warning at (<unit>)" `vStall` intbox `0, 1000, 45, 0, 1`; "Overspeed warning at (<unit>)" `vOver` intbox `0, 1000, 200, 0, 1`. Both save and call `recomputeScale()`. Add "Announce stall speed at startup" checkbox saving `startAnn` 0/1 (FR-028)
- [X] T019 [US2] Implement `checkWarnings(now)` in `src/Apps/AG-SpdGa.lua` per "State transitions" in `specs/001-speed-gauge/data-model.md` and `contracts/audio-events.md`. Re-arming always runs: `sensorSpd > vStall` → `stallArmed = true`; `shownSpd <= vOver` → `overArmed = true`. Firing happens only if `switchOn(swOn) or switchOn(swCont)`. Stall: `stallArmed and everAboveLanding and sensorSpd <= vStall` → `stallArmed = false`, `system.playFile(AUDIO_DIR .. "stall_warning.wav", AUDIO_IMMEDIATE)`, `system.vibration(true, 4)`. Overspeed: `overArmed and shownSpd > vOver` → `overArmed = false`, play `overspeed.wav` immediately, `system.vibration(true, 3)`. Alive: `everAboveHalf and not aliveSaid` → `aliveSaid = true`, play `airspeed_alive.wav` immediately. Build the three file paths once as file-level constants, not per call
- [X] T020 [US2] Add the startup announcement at the end of `init()` in `src/Apps/AG-SpdGa.lua`, only when `startAnn == 1` (contracts/audio-events.md): if `cal ~= 100`, `system.playFile(AUDIO_DIR .. "airspeed_cal_factor.wav", AUDIO_QUEUE)` then `system.playNumber(cal, 0, "%")`; then `system.playFile(AUDIO_DIR .. "stall_speed_warning_at.wav", AUDIO_QUEUE)` and `system.playNumber(vStall, 0, unitSpoken)`
- [ ] T021 [US2] MANUAL: Run quickstart scenarios 1, 2, 6, 7, 8, 9 and 10. Confirm SC-002 (exactly one warning per crossing over 10 crossings, none before first exceeding landing speed) and that vibration fires

**Checkpoint**: US1 + US2 reproduce DFM Speed Announcer v2.1's audio behavior.

---

## Phase 5: User Story 3 - Speedometer gauge on the main screen (Priority: P2)

**Goal**: The speedometer from the visual design reference, in a pilot-sized window (compact or round) and a full-screen window, with a sticky session max, and a notice on other transmitters (FR-013–FR-019)

**Independent Test**: Place "Speed Gauge" single and double, and "Speed Gauge (full screen)"; move P5. The value arc moves, the max marker stays at the peak, both numbers match, and each layout matches the reference (quickstart scenarios 13a–21b).

**Depends on**: T005 (size-0 behavior, device string, font heights)

### Implementation for User Story 3

- [X] T022 [P] [US3] Create `src/Apps/lib/ag_gauge.lua` per the `ag_gauge` table in `specs/001-speed-gauge/contracts/lib-modules.md`. Header: one-line description, `-- Copyright (c) 2026 Aaron George`, `-- SPDX-License-Identifier: MIT`, and a note that the draw functions (`face`, `arc`, `mark`, `tick`) may only be called from a registered print function. `local M = {}` with no mutable module-level state (constitution VII); a constant array `STEPS = {10, 20, 25, 50, 100, 200, 250, 500}` is allowed. Implement `M.newDial(steps, startDeg, sweepDeg)` (defaults 54, 225, 270; returns `{ n = steps, cx = {...}, sy = {...} }` with `math.cos` and `-math.sin` of each of the `steps + 1` angles going clockwise from `startDeg`, because screen y points down); `M.newCircle(points)` (default 72, same shape, closed loop); `M.point(dial, f)` (clamp 0..1, linear interpolation between table points, returns `cos, sin`); `M.scaleStep(fullScale)` (first entry of `STEPS` with `fullScale / step <= 8`, else 500); `M.face(r, circle, cx, cy, radius)` (`r:reset()`, add scaled points, `r:renderPolygon()`); `M.arc(r, dial, cx, cy, radius, f0, f1, width)` (clamp both, return if `f1 <= f0`, `r:reset()`, add the interpolated start, the table points strictly between, the interpolated end, `r:renderPolyline(width)`); `M.mark(r, dial, cx, cy, r1, r2, f, width)` (two-point polyline); `M.tick(dial, cx, cy, r1, r2, f)` (`lcd.drawLine` with rounded integer coordinates). `return M`
- [X] T023 [US3] Implement `updateMax()` in `src/Apps/AG-SpdGa.lua` per research R5: when `shownSpd ~= prevDistinct` and `prevDistinct` is not nil, the candidate is `math.min(prevDistinct, shownSpd)`, then `prevDistinct = shownSpd` and `distinctSince = now`; when the reading has held for `HOLD_MS` (1,000 ms), the candidate is `shownSpd` (added after mock testing showed a steady speed never registered); `maxSpd = math.max(maxSpd, candidate)`. Rebuild cached strings only when the rounded value changes: keep integers `curRounded`, `maxRounded`, `sensRounded` and set `curText = tostring(curRounded)`, `maxText = tostring(maxRounded)`, `sensText = tostring(sensRounded)` (from `sensorSpd`) on change. When the reading is invalid (T010 early return), set `curText = "---"` once; don't rebuild it every tick
- [X] T024 [US3] Add the "Gauge" rows 25–28 from `specs/001-speed-gauge/contracts/settings-form.md` in `src/Apps/AG-SpdGa.lua`. "Gauge full scale (<unit>, 0 = auto)" `fScale` intbox `0, 2000, 0, 0, 10` (step 10 keeps it at 0 or 10–2000); it saves, calls `recomputeScale()`, and updates a hint label "Auto: <fullScale>" via `form.setProperties` when `fScale == 0`. "Current speed color" and "Max speed color" selectboxes over the color names from T025 save `colCur` / `colMax`. "Reset max speed" is a `form.addLink` that sets `maxSpd = 0`, `prevDistinct = nil`, `maxRounded = 0`, `maxText = "0"` (US3 #6)
- [X] T025 [US3] In `src/Apps/AG-SpdGa.lua`, add `local gauge = require("ag_gauge")` and the color presets from research R8, in this order with names for the selectboxes: Cyan (0,190,255), Blue (40,110,255), White (255,255,255), Green (0,210,100), Lime (170,240,0), Magenta (230,60,230), Purple (150,100,255), Grey (170,170,170). Add constants for the fixed dial colors from research R6: face (20,24,32), track (70,78,90), overspeed zone (255,80,0), scale (200,200,200), minor ticks (110,118,130). In `init()`: `roundDial = gauge.newDial(54, 225, 270)`, `compactDial = gauge.newDial(36, 180, 180)`, `faceCircle = gauge.newCircle(72)`; `gaugeOk = string.find(system.getDeviceType() or "", "24 II", 1, true) ~= nil` (research R12, using the string T005 recorded if it differs); register `system.registerTelemetry(1, "Speed Gauge", 0, printGauge)` and `system.registerTelemetry(2, "Speed Gauge (full screen)", 3, printGauge)` (research R7)
- [X] T026 [US3] Add the scale cache to `recomputeScale()` in `src/Apps/AG-SpdGa.lua`: `scaleStep = gauge.scaleStep(fullScale)`, and an array of major label strings `tostring(i * scaleStep)` for `i = 0 .. floor(fullScale / scaleStep)`, plus cached row strings for Stall (`tostring(vStall)`) and Overspeed (`tostring(vOver)`), shown as entered (FR-016a). This runs only on setting changes, so building strings here is allowed
- [X] T027 [US3] Implement the layout cache and `printGauge(w, h)` in `src/Apps/AG-SpdGa.lua` per `specs/001-speed-gauge/contracts/telemetry-window.md` and research R6. If `not gaugeOk`, draw only the notice "Speed Gauge needs DS-24 II" (`FONT_MINI`, theme colors, centered) and return (FR-013a). Pick the layout: `h < 100` compact, `w < 250` round, else full screen. Keep one cache table per layout; rebuild it only when `w`, `h` or `layoutKey` changed (T008 clears `layoutKey`): dial center and radii, major/minor tick end points (integers), label positions, face size, text positions, fitted to the font heights from `docs/jeti-api-notes.md` (T005) and `lcd.getTextWidth`. Create the renderer lazily once (`if not rend then rend = lcd.renderer() end`) and reuse it. Draw in the order of research R6: face (round/full: `gauge.face`; compact: `lcd.drawFilledRectangle` over the window), track 0→1, overspeed zone `fOver`→1, major ticks + labels and minor ticks (4 per major in full screen, 1 in round, none in compact), stall and landing ticks at `fStall`/`fLand`, value arc 0→`shownSpd / fullScale` in `colCur` (width 6, or 5 compact) with a 2-px tip `mark`, only if `shownSpd` is not nil; max `mark` at `maxSpd / fullScale` in `colMax`, width 2, only if `maxSpd > 0`; then text. Round and full screen: `curText` in `FONT_MAXI` (or `FONT_BIG` if it doesn't fit) centered, `unitText` below in `FONT_MINI`. Round: corner rows MAX (top-left), STALL (top-right), OVR (bottom-right), label `FONT_MINI` grey over value `FONT_NORMAL` white, MAX value in `colMax`. Full screen: side panel on the right, rows MAX, STALL, OVERSPEED, and AIR DENSITY ("+N%" and "sensor " + `sensText`) only while `kDens ~= 1`; label `FONT_MINI` grey over value `FONT_BIG`. Compact: 180° arc on the left (radius about `h - 12`), `curText` in the largest font that fits to its right, then `unitText` and "MAX " + `maxText` in `FONT_MINI`. Values above full scale stop the arc at the end; the number shows the real value (US3 #7). No data: no value arc or tip, `curText` "---", max kept. Drop order when text doesn't fit follows the contract; current and max numbers always stay. Constant label strings ("MAX", "STALL", "OVR", "OVERSPEED", "AIR DENSITY") are file-level constants
- [ ] T028 [US3] Only if T005 recorded "size 0: use winSz fallback": add the `winSz` key ("1 Single, 2 Double", default 2) to `loadSettings()` and row 28a "Gauge window size" (selectbox Single / Double) in the "Gauge" group of `src/Apps/AG-SpdGa.lua`. Register window 1 with size `winSz` in `init()` instead of 0; on change, save, then `system.unregisterTelemetry(1)` and register it again with the new size. Otherwise mark this task "not needed (size 0 works)" and tick it
- [ ] T029 [US3] MANUAL: Run quickstart scenarios 13a, 13b, 14–21, 21a and 21b in all three layouts, comparing with `docs/vendor/gauge-reference.jpg`. Check renderer reuse (no glitches over 5 minutes) and the CPU figure with the full-screen gauge (< 20%, SC-007). Record the renderer and CPU findings in `docs/jeti-api-notes.md`
- [ ] T030 [US3] Only if T029 found renderer reuse fails or CPU ≥ 20%: in `src/Apps/AG-SpdGa.lua`, create the renderer per frame if reuse failed; if CPU is high, draw the static layers (face, track, zone, ticks) once per layout cache rebuild into an image from `lcd.createImage(w, h)` with `lcd.renderer(image.data)`, and in `printGauge` `lcd.drawImage(0, 0, image)` then draw labels and moving parts live (research R6 fallback). Otherwise mark "not needed" and tick it

**Checkpoint**: US1–US3 work; the gauge is visible in every layout with correct max behavior.

---

## Phase 6: User Story 4 - Correct for air density (Priority: P2)

**Goal**: Optional true-airspeed correction from field elevation and temperature for airspeed sensors (FR-020–FR-023, FR-016a)

**Independent Test**: Hold P5 at a steady 100 mph; set 5,000 ft and 95 °F (35 °C); toggle correction. Reads ~113 on, 100 off (quickstart scenarios 22–27; SC-003, SC-003a).

### Tests for User Story 4 (optional, listed in plan.md)

- [X] T031 [P] [US4] Create `tests/test_ag_dens.lua`: header with `-- Copyright (c) 2026 Aaron George` and `-- SPDX-License-Identifier: MIT`; prepend `src/Apps/lib/?.lua;` to `package.path`; `require("ag_dens")`. Assert within 0.001: `factor(0, nil) = 1.0000`, `factor(1524, nil) = 1.0773`, `factor(1524, 35) = 1.1337`, `factor(4572, 50) = 1.4097` (contracts/lib-modules.md); `stdTempC(0) = 15`; `mToFt(ftToM(5000))` ≈ 5000; `cToF(35) = 95`. Print a table of results and call `error()` on the first mismatch so the process exits non-zero. Do not use `os`

### Implementation for User Story 4

- [X] T032 [P] [US4] Create `src/Apps/lib/ag_dens.lua` per `specs/001-speed-gauge/contracts/lib-modules.md` and research R1. Header as in T022. `local M = {}` with constants `T0 = 288.15`, `LAPSE = 0.0065`, `EXP = 5.25588`. `M.stdTempC(elevM)` = `15 - 0.0065 * elevM`. `M.factor(elevM, tempC)`: `Ts = T0 - LAPSE * elevM`, `delta = (Ts / T0) ^ EXP`, `T = tempC and (tempC + 273.15) or Ts`, `sigma = delta * T0 / T`, return `1 / math.sqrt(sigma)`. `M.ftToM`, `M.mToFt` (0.3048), `M.fToC`, `M.cToF`. `return M`
- [X] T033 [US4] Add the "Air density" rows 19–24 from `specs/001-speed-gauge/contracts/settings-form.md` in `src/Apps/AG-SpdGa.lua`: "Correct for air density" checkbox saving `densOn` 0/1, disabled via `form.setProperties(idx, {enabled = false})` when `sType == 2`; status label; "Field elevation (ft)" or "(m)" intbox saving `elev`, range `-1000, 15000` ft or `-300, 4600` m, step 10; "Temperature (°F)" or "(°C)" intbox saving `temp`, range `-22, 122` °F or `-30, 50` °C, step 1, disabled while `tStd == 1`; "Use standard temperature" checkbox saving `tStd` 0/1 that enables/disables the temperature intbox; hint "Leave correction off if your sensor already corrects for air density". Units come from `UNITS_IMPERIAL[units]` (FR-023)
- [X] T034 [US4] Add `local dens = require("ag_dens")` near the top of `src/Apps/AG-SpdGa.lua` (T036 uses it too), then replace the body of `recomputeDensity()`: `elevM = imperial and dens.ftToM(elev) or elev`; `tempC = (tStd == 1) and nil or (imperial and dens.fToC(temp) or temp)`; `kDens = (densOn == 1 and sType == 1) and dens.factor(elevM, tempC) or 1`. Cache the percent string "+N%" with `N = math.floor((kDens - 1) * 100 + 0.5)` for the settings status label and the full-screen AIR DENSITY row. Update the status label (form open only) to "Correction: +N%" when on, "Not used with GPS" when `sType == 2`, empty otherwise (FR-022). Call `recomputeDensity()` then `recomputeScale()` from every density-row callback and from the sensor-type callback, so the stall and landing marks move to their true-airspeed equivalents (FR-016a). Stall/landing/alive checks keep using `sensorSpd` (FR-011)
- [ ] T035 [US4] MANUAL: Run quickstart scenarios 13c and 22–27 and, if a Lua 5.3 interpreter is available, `lua tests/test_ag_dens.lua`. Check SC-003 (100 / 108 / 113 ±1) and SC-003a (stall fires at sensor 40, gauge reads 43, value-arc tip at the stall mark)

**Checkpoint**: US1–US4 work; readings are true airspeed when correction is on.

---

## Phase 7: User Story 5 - Settings that explain themselves (Priority: P2)

**Goal**: Grouped, plainly worded settings with units shown, illogical thresholds flagged, and units changes that convert values (FR-025, FR-026, Edge Cases)

**Independent Test**: Someone who hasn't seen the app sets up sensor, switch, landing speed and stall warning without help in under 3 minutes (SC-006; quickstart scenarios 28–31, 35).

### Implementation for User Story 5

- [X] T036 [US5] Implement units conversion in the Units callback in `src/Apps/AG-SpdGa.lua` per "Units change" in `specs/001-speed-gauge/data-model.md`: from old unit A to new unit B, each of `sens`, `vLand`, `vStall`, `vOver` and non-zero `fScale` becomes `round(value · unitsMult[B] / unitsMult[A])`, clamped to its range (`sens` 1–100, speeds 0–1000, `fScale` 10–2000, rounded to a multiple of 10). If `UNITS_IMPERIAL[A] ~= UNITS_IMPERIAL[B]`, convert `elev` (ft↔m, clamp to the new range) and `temp` (°F↔°C, clamp) with `ag_dens`. Save every changed key, call `recomputeAll()`, then `form.reinit()` so labels and values redraw (quickstart scenario 31: 60 mph → 97 km/h)
- [X] T037 [US5] Add the threshold-order warning (row 16, top of "Warnings") in `src/Apps/AG-SpdGa.lua` per FR-026: a label "Check: stall < landing < overspeed < full scale", visible only when `vStall >= vLand`, `vLand >= vOver`, or `fScale ~= 0 and vOver > fScale`. Add `checkOrder()` that sets `form.setProperties(idx, {visible = bad})`. Call it at the end of `initForm()` and from the `vStall`, `vLand`, `vOver` and `fScale` callbacks. Values are still saved when illogical
- [X] T038 [US5] Review every label, hint and group in `initForm()` in `src/Apps/AG-SpdGa.lua` against the spec's User Story 5 table and `specs/001-speed-gauge/contracts/settings-form.md`. Row order 1–28 (plus 28a if T028 applied) and the five groups must match; every speed setting shows the unit; hints as listed. Confirm SC-008: every v2.1 setting is present under its new name, or listed as changed in research R11
- [ ] T039 [US5] MANUAL: Check `°` renders in the settings form (quickstart step 1). If not, change the labels to "deg F" / "deg C" in `src/Apps/AG-SpdGa.lua` and record it in `docs/jeti-api-notes.md`. Run quickstart scenarios 28–31 and 35 (SC-006)

**Checkpoint**: All five user stories are complete.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, credits, performance review, full validation

- [X] T040 [P] Update the Apps table in `README.md`: Status "Spec written" → "In development" (→ "Released" at release), and link the script `src/Apps/AG-SpdGa.lua`. Keep the "Based on" credit unchanged (constitution VIII)
- [X] T041 [P] Update the Apps table in `CLAUDE.md`: change `` `src/Apps/AG-SpdGa.lua` (planned) `` to `` `src/Apps/AG-SpdGa.lua` ``
- [X] T042 [P] In `CREDITS.md`, add one sentence to the Speed Gauge section pointing to `src/Apps/AG-SpdGa/CREDITS.txt` for the WAV files' credit. Do not remove or shorten any existing text (constitution VIII)
- [ ] T043 [P] Make sure `docs/jeti-api-notes.md` has every fact verified in T005, T029 and T039 (size 0, device strings, font heights, renderer reuse, CPU, `°`). If any contradicts `types/jeti.lua`, update the stub with a source note
- [X] T044 Review `loop()`, `checkCallout`, `checkWarnings`, `updateMax` and `printGauge` in `src/Apps/AG-SpdGa.lua` for constitution VI: no `string.format`, `..` or table constructors outside cache rebuilds; no `getSensors`/`getSensorByID` in the loop; `system.getSensorValueByID` called through `system`; trig only in `ag_gauge.newDial`/`newCircle`. Confirm `src/Apps/lib/ag_dens.lua` and `src/Apps/lib/ag_gauge.lua` hold no mutable module-level state (constitution VII)
- [X] T045 Run `python tools/check.py` (0 errors) and confirm the LuaLS Problems panel shows no errors for `src/Apps/AG-SpdGa.lua`, `src/Apps/lib/ag_dens.lua` and `src/Apps/lib/ag_gauge.lua`
- [ ] T046 MANUAL: Run the full `specs/001-speed-gauge/quickstart.md` (steps 0–3, including scenarios 32–34 and the resource checks), then step 4 on a dedicated test model on the transmitter

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies. T005 needs T004, and US3 needs T005
- **Foundational (Phase 2)**: Depends on T001 (audio paths). BLOCKS all user stories
- **US1 (Phase 3)**: Depends on Foundational
- **US2 (Phase 4)**: Depends on Foundational. Uses `switchOn()` from T014, so do it after US1
- **US3 (Phase 5)**: Depends on Foundational and T005. T022 can start any time
- **US4 (Phase 6)**: Depends on Foundational. T031/T032 can start any time; T034's marks and AIR DENSITY row are only visible once US3 is done
- **US5 (Phase 7)**: Depends on the rows it reviews and converts, so do it after US1–US4
- **Polish (Phase 8)**: After all desired stories

### User Story Dependencies

```text
Setup (T004 → T005) ─────────────────────────┐
  ↓                                          ↓
Foundational → US1 (MVP) → US2 → US3 ─→ US4 → US5 → Polish
                  └─ switchOn ─┘
Any time after Setup (separate files): T022 ag_gauge.lua, T031 test, T032 ag_dens.lua
Conditional: T028 (only if size 0 fails), T030 (only if reuse fails or CPU ≥ 20%)
```

### Within Each User Story

- Settings rows before the logic that reads them
- Logic before the MANUAL validation task that closes the story
- Commit after each task or logical group on `feature/001-speed-gauge`, and
  pull first: another session also pushes to this branch

### Parallel Opportunities

- T002 and T004 run alongside T001
- T022 (`ag_gauge.lua`), T031 (`tests/test_ag_dens.lua`) and T032 (`ag_dens.lua`) are separate files with no dependencies. They can be written at any point, including during Phase 2
- T040–T043 are four different documentation files
- Everything in `src/Apps/AG-SpdGa.lua` is sequential

---

## Parallel Example: Shared modules during Phase 2

```text
# While Phase 2 is in progress on src/Apps/AG-SpdGa.lua:
Task: "T022 Create src/Apps/lib/ag_gauge.lua per contracts/lib-modules.md"
Task: "T032 Create src/Apps/lib/ag_dens.lua per contracts/lib-modules.md and research R1"
Task: "T031 Create tests/test_ag_dens.lua with the R1 reference values"
```

## Parallel Example: Setup

```text
Task: "T002 Create src/Apps/AG-SpdGa/CREDITS.txt"
Task: "T004 Add MODE 3 (size-0 window) to tools/probe/PROBE.lua"
```

## Parallel Example: Polish

```text
Task: "T040 Update README.md apps table"
Task: "T041 Update CLAUDE.md apps table"
Task: "T042 Add CREDITS.txt pointer to CREDITS.md"
Task: "T043 Record verified API facts in docs/jeti-api-notes.md"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1: Setup. T005 can wait until before US3
2. Phase 2: Foundational (blocks everything)
3. Phase 3: US1
4. **STOP and VALIDATE** in the emulator (T017): a working speed announcer
5. Then add US2 so the warnings exist before any real flight. US1 alone is
   not for flying, because it has no stall warning

### Incremental Delivery

1. Setup + Foundational → app loads, settings open
2. + US1 → callouts (MVP, emulator only)
3. + US2 → parity with DFM v2.1 audio; first candidate for a test-model bench run
4. + US3 → gauge in all three layouts
5. + US4 → density correction
6. + US5 → settings polish and units conversion
7. Polish → docs and full validation → merge `feature/001-speed-gauge` into `develop`

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps each task to a user story for traceability
- MANUAL tasks stay unticked until the user reports the result
- Conditional tasks (T028, T030) are ticked with "not needed" when their condition doesn't apply
- Stop at any checkpoint to validate a story on its own
- Never merge to `develop` before T045 passes and the MANUAL tasks are done
