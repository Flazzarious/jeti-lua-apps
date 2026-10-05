---

description: "Task list for Speed Gauge (AG-SpdGa)"
---

# Tasks: Speed Gauge

**Input**: Design documents from `specs/001-speed-gauge/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: The spec does not ask for automated tests. The only test tasks are
the optional `tests/test_ag_dens.lua` the plan lists (T031, extended in T050)
and the voice generator's self-check (T060). Validation is the manual
emulator scenarios in [quickstart.md](quickstart.md).

**Organization**: Tasks are grouped by user story so each story can be built
and checked on its own.

**Versions**: Phases 1–8 (T001–T046) built 0.1.0 and are kept as the record of
that work. Where their details differ from the current design (the
`tStd` checkbox, the elevation/temperature ranges in T007, T033 and T036,
`colMax` default, window 2 size 3, the "R1..R12" header), the 0.2.0 tasks in
Phases 9–12 (T047–T072) supersede them. Only the MANUAL tasks of Phases 1–8
remain open.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1–US6)
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
  (constitution VI). One exception (research R17): `loop()` may update the
  temperature status label, and only while `formOpen` is true.
- No `string.format`, `..` or `{}` in `loop()` or the print function, except
  when rebuilding a cache because its inputs changed, or building the one
  voice-file path when a callout is due (research R14) (constitution VI).
- The voice generator in `tools/voice/` is Python 3.9 on the PC, not Lua. It
  never goes in `src/Apps/`. Its output is committed since 2026-10-03,
  under CC BY-SA 4.0 (FR-035).
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
- [X] T005 MANUAL: Done 2026-09-27 (size 0 works, device "JETI DS-24 II", fonts 18/22/13/40, visible sizes recorded in docs/jeti-api-notes.md). With `tools/probe/PROBE.lua` in the emulator (MODE 3, then MODE 1), record in `docs/jeti-api-notes.md`: (a) whether "Probe auto" lets you place it at single or double size, and the sizes it reports (research R7); (b) the "PROBE device:" string from the Lua console, and on the transmitter too if possible (research R12); (c) the font heights from the "fonts N/B/M/Mx" line. If size 0 does not let the pilot choose, write "size 0: use winSz fallback" in the notes, so T028 applies

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

**Independent Test**: Place "Speed Gauge" single and double, and the full-screen "Speed Gauge"; move P5. The value arc moves, the max marker stays at the peak, both numbers match, and each layout matches the reference (quickstart scenarios 13a–21b).

**Depends on**: T005 (size-0 behavior, device string, font heights)

### Implementation for User Story 3

- [X] T022 [P] [US3] Create `src/Apps/lib/ag_gauge.lua` per the `ag_gauge` table in `specs/001-speed-gauge/contracts/lib-modules.md`. Header: one-line description, `-- Copyright (c) 2026 Aaron George`, `-- SPDX-License-Identifier: MIT`, and a note that the draw functions (`face`, `arc`, `mark`, `tick`) may only be called from a registered print function. `local M = {}` with no mutable module-level state (constitution VII); a constant array `STEPS = {10, 20, 25, 50, 100, 200, 250, 500}` is allowed. Implement `M.newDial(steps, startDeg, sweepDeg)` (defaults 54, 225, 270; returns `{ n = steps, cx = {...}, sy = {...} }` with `math.cos` and `-math.sin` of each of the `steps + 1` angles going clockwise from `startDeg`, because screen y points down); `M.newCircle(points)` (default 72, same shape, closed loop); `M.point(dial, f)` (clamp 0..1, linear interpolation between table points, returns `cos, sin`); `M.scaleStep(fullScale)` (first entry of `STEPS` with `fullScale / step <= 8`, else 500); `M.face(r, circle, cx, cy, radius)` (`r:reset()`, add scaled points, `r:renderPolygon()`); `M.arc(r, dial, cx, cy, radius, f0, f1, width)` (clamp both, return if `f1 <= f0`, `r:reset()`, add the interpolated start, the table points strictly between, the interpolated end, `r:renderPolyline(width)`); `M.mark(r, dial, cx, cy, r1, r2, f, width)` (two-point polyline); `M.tick(dial, cx, cy, r1, r2, f)` (`lcd.drawLine` with rounded integer coordinates). `return M`
- [X] T023 [US3] Implement `updateMax()` in `src/Apps/AG-SpdGa.lua` per research R5: when `shownSpd ~= prevDistinct` and `prevDistinct` is not nil, the candidate is `math.min(prevDistinct, shownSpd)`, then `prevDistinct = shownSpd` and `distinctSince = now`; when the reading has held for `HOLD_MS` (1,000 ms), the candidate is `shownSpd` (added after mock testing showed a steady speed never registered); `maxSpd = math.max(maxSpd, candidate)`. Rebuild cached strings only when the rounded value changes: keep integers `curRounded`, `maxRounded`, `sensRounded` and set `curText = tostring(curRounded)`, `maxText = tostring(maxRounded)`, `sensText = tostring(sensRounded)` (from `sensorSpd`) on change. When the reading is invalid (T010 early return), set `curText = "---"` once; don't rebuild it every tick
- [X] T024 [US3] Add the "Gauge" rows 25–28 from `specs/001-speed-gauge/contracts/settings-form.md` in `src/Apps/AG-SpdGa.lua`. "Gauge full scale (<unit>, 0 = auto)" `fScale` intbox `0, 2000, 0, 0, 10` (step 10 keeps it at 0 or 10–2000); it saves, calls `recomputeScale()`, and updates a hint label "Auto: <fullScale>" via `form.setProperties` when `fScale == 0`. "Current speed color" and "Max speed color" selectboxes over the color names from T025 save `colCur` / `colMax`. "Reset max speed" is a `form.addLink` that sets `maxSpd = 0`, `prevDistinct = nil`, `maxRounded = 0`, `maxText = "0"` (US3 #6)
- [X] T025 [US3] In `src/Apps/AG-SpdGa.lua`, add `local gauge = require("ag_gauge")` and the color presets from research R8, in this order with names for the selectboxes: Cyan (0,190,255), Blue (40,110,255), White (255,255,255), Green (0,210,100), Lime (170,240,0), Magenta (230,60,230), Purple (150,100,255), Grey (170,170,170). Add constants for the fixed dial colors from research R6: face (20,24,32), track (70,78,90), overspeed zone (255,80,0), scale (200,200,200), minor ticks (110,118,130). In `init()`: `roundDial = gauge.newDial(54, 225, 270)`, `compactDial = gauge.newDial(36, 180, 180)`, `faceCircle = gauge.newCircle(72)`; `gaugeOk = string.find(system.getDeviceType() or "", "24 II", 1, true) ~= nil` (research R12, using the string T005 recorded if it differs); register `system.registerTelemetry(1, "Speed Gauge", 0, printGauge)` and `system.registerTelemetry(2, "Speed Gauge (full screen)", 3, printGauge)` (research R7)
- [X] T026 [US3] Add the scale cache to `recomputeScale()` in `src/Apps/AG-SpdGa.lua`: `scaleStep = gauge.scaleStep(fullScale)`, and an array of major label strings `tostring(i * scaleStep)` for `i = 0 .. floor(fullScale / scaleStep)`, plus cached row strings for Stall (`tostring(vStall)`) and Overspeed (`tostring(vOver)`), shown as entered (FR-016a). This runs only on setting changes, so building strings here is allowed
- [X] T027 [US3] Implement the layout cache and `printGauge(w, h)` in `src/Apps/AG-SpdGa.lua` per `specs/001-speed-gauge/contracts/telemetry-window.md` and research R6. If `not gaugeOk`, draw only the notice "Speed Gauge needs DS-24 II" (`FONT_MINI`, theme colors, centered) and return (FR-013a). Pick the layout: `h < 100` compact, `w < 250` round, else full screen. Keep one cache table per layout; rebuild it only when `w`, `h` or `layoutKey` changed (T008 clears `layoutKey`): dial center and radii, major/minor tick end points (integers), label positions, face size, text positions, fitted to the font heights from `docs/jeti-api-notes.md` (T005) and `lcd.getTextWidth`. Create the renderer lazily once (`if not rend then rend = lcd.renderer() end`) and reuse it. Draw in the order of research R6: face (round/full: `gauge.face`; compact: `lcd.drawFilledRectangle` over the window), track 0→1, overspeed zone `fOver`→1, major ticks + labels and minor ticks (4 per major in full screen, 1 in round, none in compact), stall and landing ticks at `fStall`/`fLand`, value arc 0→`shownSpd / fullScale` in `colCur` (width 6, or 5 compact) with a 2-px tip `mark`, only if `shownSpd` is not nil; max `mark` at `maxSpd / fullScale` in `colMax`, width 2, only if `maxSpd > 0`; then text. Round and full screen: `curText` in `FONT_MAXI` (or `FONT_BIG` if it doesn't fit) centered, `unitText` below in `FONT_MINI`. Round: corner rows MAX (top-left), STALL (top-right), OVR (bottom-right), label `FONT_MINI` grey over value `FONT_NORMAL` white, MAX value in `colMax`. Full screen: side panel on the right, rows MAX, STALL, OVERSPEED, and AIR DENSITY ("+N%" and "sensor " + `sensText`) only while `kDens ~= 1`; label `FONT_MINI` grey over value `FONT_BIG`. Compact: 180° arc on the left (radius about `h - 12`), `curText` in the largest font that fits to its right, then `unitText` and "MAX " + `maxText` in `FONT_MINI`. Values above full scale stop the arc at the end; the number shows the real value (US3 #7). No data: no value arc or tip, `curText` "---", max kept. Drop order when text doesn't fit follows the contract; current and max numbers always stay. Constant label strings ("MAX", "STALL", "OVR", "OVERSPEED", "AIR DENSITY") are file-level constants
- [X] T028 [US3] Not needed: size 0 lets the pilot choose (T005, 2026-09-27). Only if T005 recorded "size 0: use winSz fallback": add the `winSz` key ("1 Single, 2 Double", default 2) to `loadSettings()` and row 28a "Gauge window size" (selectbox Single / Double) in the "Gauge" group of `src/Apps/AG-SpdGa.lua`. Register window 1 with size `winSz` in `init()` instead of 0; on change, save, then `system.unregisterTelemetry(1)` and register it again with the new size. Otherwise mark this task "not needed (size 0 works)" and tick it
- [ ] T029 [US3] MANUAL: Run quickstart scenarios 13a, 13b, 14–21, 21a and 21b in all three layouts, comparing with `docs/vendor/gauge-reference.jpg`. Check renderer reuse (no glitches over 5 minutes) and the CPU figure with the full-screen gauge (below 50%, SC-007 as revised; 43% measured 2026-09-27). Record the renderer and CPU findings in `docs/jeti-api-notes.md`
- [X] T030 [US3] Tried 2026-09-27: renderer reuse works; the off-screen image fallback did not render on the II emulator and was removed. CPU handled instead by cheaper glow and the SC-007 revision. Original task: Only if T029 found renderer reuse fails or CPU ≥ 20%: in `src/Apps/AG-SpdGa.lua`, create the renderer per frame if reuse failed; if CPU is high, draw the static layers (face, track, zone, ticks) once per layout cache rebuild into an image from `lcd.createImage(w, h)` with `lcd.renderer(image.data)`, and in `printGauge` `lcd.drawImage(0, 0, image)` then draw labels and moving parts live (research R6 fallback). Otherwise mark "not needed" and tick it

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
- [X] T043 [P] Make sure `docs/jeti-api-notes.md` has every fact verified in T005, T029 and T039 (size 0, device strings, font heights, renderer reuse, CPU, `°`). If any contradicts `types/jeti.lua`, update the stub with a source note
- [X] T044 Review `loop()`, `checkCallout`, `checkWarnings`, `updateMax` and `printGauge` in `src/Apps/AG-SpdGa.lua` for constitution VI: no `string.format`, `..` or table constructors outside cache rebuilds; no `getSensors`/`getSensorByID` in the loop; `system.getSensorValueByID` called through `system`; trig only in `ag_gauge.newDial`/`newCircle`. Confirm `src/Apps/lib/ag_dens.lua` and `src/Apps/lib/ag_gauge.lua` hold no mutable module-level state (constitution VII)
- [X] T045 Run `python tools/check.py` (0 errors) and confirm the LuaLS Problems panel shows no errors for `src/Apps/AG-SpdGa.lua`, `src/Apps/lib/ag_dens.lua` and `src/Apps/lib/ag_gauge.lua`
- [ ] T046 MANUAL: Run the full `specs/001-speed-gauge/quickstart.md` (steps 0–3, including scenarios 32–34 and the resource checks), then step 4 on a dedicated test model on the transmitter

---

## Phase 9: 0.2.0 Foundational (limits, settings keys, migration)

**Purpose**: Settings layout `cfgV` 2 that the temperature source (US4) and the voice (US6) both need, plus the FR-020 limits (research R16)

**⚠️ CRITICAL**: Phases 10 and 11 build on T048 and T049

- [X] T047 In `src/Apps/AG-SpdGa.lua`, set `APP_VERSION = "0.2.0"` and change the header line "Research decisions are cited as R1..R12." to "R1..R17."
- [X] T048 Update `KEYS` and `DEFAULTS` in `src/Apps/AG-SpdGa.lua` per the settings table in `specs/001-speed-gauge/data-model.md` (28 keys, ≤ 30): remove `tStd`; add `tSrc` (int "1 Standard, 2 Manual, 3 Sensor", default 1), `tId` (int "sensor id, 0 = none", default 0), `tPar` (int, default 0), `tLbl` ("string < 64 B", default ""), `voice` (int "0 not chosen, 1 Speed Gauge, 2 Transmitter", default 0); change the `cfgV` default to 2. Then add the `cfgV` 1 → 2 migration to `loadSettings()` (data-model.md "Settings load"): read `cfgV` with `system.pLoad("cfgV", 1)`; if it is below 2, set `tSrc` from `system.pLoad("tStd", 1)` (`1` → `tSrc = 1`, anything else → `tSrc = 2`) with `save("tSrc", ...)`, then `system.pSave("tStd", nil)` and `save("cfgV", 2)`. A fresh install also runs this once and ends with `tSrc = 1`, which is the default
- [X] T049 Add range constants and clamp-on-load in `src/Apps/AG-SpdGa.lua` (FR-020, research R16). File-level constants: `ELEV_FT_LO, ELEV_FT_HI = -300, 10000`, `ELEV_M_LO, ELEV_M_HI = -90, 3050`, `TEMP_F_LO, TEMP_F_HI = -20, 130`, `TEMP_C_LO, TEMP_C_HI = -29, 54`, and a `RANGES` table of `{lo, hi}` for every other integer key: `sType` 1–2, `tMin` 1–10, `tMax` 10–60, `sens` 1–100, `vLand`/`vStall`/`vOver` 0–1000, `cal` 1–200, `units` 1–5, `numOnly`/`startAnn`/`densOn` 0–1, `tSrc` 1–3, `voice` 0–2, `colCur`/`colMax` 1–9, `fScale` 0–2000. At the end of `loadSettings()` (after the migration and the `temp` default) clamp each of these, plus `elev` and `temp` against the range for `UNITS_IMPERIAL[cfg.units]`; a non-zero `fScale` below 10 becomes 10. Call `save(key, value)` only for values that changed. Use the same constants in every intbox and in `onUnitsChanged` (T057), so there is one source for each limit
- [X] T050 [P] Add the research R1 range-edge rows to `cases` in `tests/test_ag_dens.lua`, elevations in meters: `factor(-91.44, -29)` = 0.9155, `factor(-91.44, 54)` = 1.0598, `factor(3048, -29)` = 1.1100, `factor(3048, nil)` = 1.1637, `factor(3048, 54)` = 1.2849. Keep the existing rows, including `factor(4572, 50)` (contracts/lib-modules.md)

**Checkpoint**: Settings saved by 0.1.0 load with their meaning kept (`tStd` → `tSrc`), and nothing outside FR-020 survives a load. `python tools/check.py` passes.

---

## Phase 10: User Story 4 additions - Temperature source (Priority: P2)

**Goal**: Temperature for density correction from Standard, Manual or a live sensor, with reject-and-resume, 1 °C hysteresis, a live status in settings and a Temperature row on the full-screen panel (FR-038–FR-044)

**Independent Test**: Correction on at 5,000 ft, steady P5 at 100 mph, source Sensor with "MSpeed 450 / Temperature" (P7) at 35 °C: reads 113 (±1). P7 fully down: within 5 s the reading drops to 108 and the full-screen row shows "SENSOR OUT". P7 back: it returns to 113 after about 10 s (quickstart scenarios 36–47).

- [X] T051 [US4] Add the temperature session state in `src/Apps/AG-SpdGa.lua` per "Session state" in `specs/001-speed-gauge/data-model.md`: constant `TEMP_MS = 5000`; locals `tStat = 0` ("0 not in use, 1 waiting (rejected), 2 in use"), `tUseC = nil` (accepted °C), `tGood = 0`, `tEver = false`, `tNextRead = 0`, `formOpen = false`, `tempText = ""`, `tempUnitText = "°F"`, `tempLabel` (one of the constants below), `tStatText = ""`. Label constants: `TXT_TEMP_STD = "TEMP STD"`, `TXT_TEMP_MAN = "TEMP MANUAL"`, `TXT_TEMP_SENS = "TEMP SENSOR"`, `TXT_TEMP_OUT = "SENSOR OUT"`. Add `local function resetTempSensor()` that sets `tStat = (cfg.tSrc == 3 and densActive) and 1 or 0`, `tUseC = nil`, `tGood = 0`, `tEver = false`, `tNextRead = system.getTimeCounter()`. Call it from `resetSession()` after `recomputeAll()` has set `densActive`
- [X] T052 [US4] Rewrite the temperature part of `recomputeDensity()` in `src/Apps/AG-SpdGa.lua` per the `tempC` row of "Derived values" in data-model.md: `tSrc = 1` → `tempC = nil`; `tSrc = 2` → the manual `temp`, converted with `dens.fToC` when imperial; `tSrc = 3` → `tUseC` while `tStat == 2`, else nil. `kDens = dens.factor(elevM, tempC)` as before. Then rebuild the cached display strings (allowed: this runs only on a change): the temperature in use in °C is `tempC or dens.stdTempC(elevM)`; `tempText = tostring(math.floor(t + 0.5))` in °F (`dens.cToF`) or °C per FR-023, `tempUnitText = "°F"` or `"°C"`. `tempLabel` = `TXT_TEMP_STD` / `TXT_TEMP_MAN` for sources 1 / 2; for source 3 `TXT_TEMP_SENS` when `tStat == 2`, else `TXT_TEMP_OUT`. `tStatText` (research R17) = "Temp: <t> <unit> standard", "Temp: <t> <unit> manual", "Temp: <t> <unit> from <tLbl>", or "Sensor not available - using standard" (use " - ", never `—`)
- [X] T053 [US4] Add `local function readTemp(now)` to `src/Apps/AG-SpdGa.lua` implementing "Temperature sensor" in data-model.md and research R15, and call it at the top of `loop()`'s tick, **before** the early return for an invalid speed reading (the temperature must be tracked even when speed is lost). It returns at once unless `tStat ~= 0` and `now - tNextRead >= 0`; then `tNextRead = now + TEMP_MS`. Read `local e = nil; if cfg.tId ~= 0 then e = system.getSensorByID(cfg.tId, cfg.tPar) end` (through `system`, research R3). Good read: `e ~= nil`, `e.valid`, and `e.value` within `TEMP_F_LO..TEMP_F_HI` (imperial) or `TEMP_C_LO..TEMP_C_HI` (metric), after converting the reading to the user's system: a unit whose last byte is "F" (`string.sub(e.unit, -1) == "F"`) is °F, anything else °C. `rc` is the reading in °C. Transitions: waiting and good and not `tEver` → `tStat = 2`, `tUseC = rc`, `tEver = true`; waiting and good and `tEver` → `tGood = tGood + 1`, at 2 → `tStat = 2`, `tUseC = rc`; waiting and bad → `tGood = 0`, `tEver = true`; in use and good with `math.abs(rc - tUseC) >= 1` → `tUseC = rc`; in use and bad → `tStat = 1`, `tGood = 0`, `tUseC = nil`, `tEver = true`. Only when `tStat` or `tUseC` changed: call `recomputeDensity()`, `recomputeScale()`, and if `formOpen` the status update from T055. Never touch `lastSpokenAt` or any callout state (FR-041)
- [X] T054 [US4] Extend `buildSensorList()` in `src/Apps/AG-SpdGa.lua` to fill a second list in the same `system.getSensors()` pass (research R15, FR-039): `tempLabels = {"(none)"}`, `tempIds = {0}`, `tempPars = {0}`, `tempNotFoundIdx`. Keep an entry when `param ~= 0`, `type ~= 5` and `~= 9`, `#s.unit` is 2 or 3, and its last byte is "C" or "F". Use the same "<parent> / <label>" text as the speed list. If the saved `tId`/`tPar` isn't present and `tId ~= 0`, add "<tLbl> (not found)" and select it (as R4). Return both selections
- [X] T055 [US4] Replace the "Air density" temperature rows in `initForm()` in `src/Apps/AG-SpdGa.lua` with rows 21–24c of `specs/001-speed-gauge/contracts/settings-form.md`: elevation intbox with `ELEV_FT_*` / `ELEV_M_*`, step 10; "Temperature source" selectbox `{"Standard", "Manual", "Sensor"}` saving `tSrc`; "Temperature, manual (°F)" / "(°C)" intbox with `TEMP_F_*` / `TEMP_C_*`, default 59 / 15, `enabled = cfg.tSrc == 2`; "Temperature sensor" selectbox (`enableForm = true`, dialog) from T054's list saving `tId`, `tPar`, `tLbl` (label cut to 63 bytes, "(none)" saves `tId = 0`), `enabled = cfg.tSrc == 3`; hint "Sensors inside the model can read warmer than outside air"; status label `idxTStat` (row 24b); then the existing "Leave correction off ..." hint. Remove the `tStd` checkbox and `idxTemp`'s `tStd` logic. Changing the source or the sensor calls `resetTempSensor()` then `onDensityChanged()`; changing the manual temperature calls `onDensityChanged()`. Extend `updateDensityRows()` to set the manual intbox and sensor selectbox `enabled` from `tSrc`, and the status label to `tStatText` while `densActive`, else "". Keep every label ASCII except `°` (contracts/settings-form.md "Characters")
- [X] T056 [US4] Track the open form in `src/Apps/AG-SpdGa.lua` (research R17): register with `system.registerForm(1, MENU_APPS, APP_NAME, initForm, keyForm, nil, closeForm)`; `initForm()` sets `formOpen = true` first; new `local function closeForm()` sets `formOpen = false` and sets every stored form index (`idxGpsHint`, `idxDensOn`, `idxDensStatus`, `idxTemp`, `idxTStat`, the sensor and voice indices, `idxAutoHint`, `idxOrder`) to nil. `readTemp` (T053) updates the status label only through `updateDensityRows()` and only while `formOpen`. Also call `resetTempSensor()` from the density checkbox and sensor-type callbacks, since they change `densActive`
- [X] T057 [US4] Update `onUnitsChanged()` in `src/Apps/AG-SpdGa.lua` to clamp the converted `elev` and `temp` with the T049 constants instead of the old −1000/15000, −300/4600, −22/122, −30/50 literals (data-model.md "Units change"). Leave `tId`/`tPar` unchanged; the reading is converted at each read
- [X] T058 [US4] Add the TEMPERATURE row to the full-screen side panel in `src/Apps/AG-SpdGa.lua` per `specs/001-speed-gauge/contracts/telemetry-window.md` (FR-044): in `buildFull()` spread six rows instead of five (`L.rowH = math.min((h - 8) // 6, L.hMini + L.hBig + 14)`, about 38–39 px) and update the comment; give `drawRow()` an optional `labelColor` argument after `unit` (default `C_MINOR`); in `drawFull()`, while `densActive`, draw ELEVATION at row 3, the temperature row at row 4 (`tempLabel`, `tempText`, `FONT_BIG`, `C_TEXT`, unit `tempUnitText`, label color `C_ZONE` when `tempLabel == TXT_TEMP_OUT`), and RAW SENSOR at row 5. No temperature in the single or double windows. In `buildFull()` check that `lcd.getTextWidth(FONT_MINI, TXT_TEMP_MAN)` and `TXT_TEMP_OUT` fit in `w - L.panelX`; if not, note it in a comment and shorten the constants ("TEMP MAN", "TEMP OUT")
- [ ] T059 [US4] MANUAL: Run quickstart step 1's "Temperature unit string" check, then scenarios 36–47 and 53–55. Re-check scenario 21a: full-screen CPU figure still below 50% with six rows (SC-007). Record the unit string findings in `docs/jeti-api-notes.md` (T070)

**Checkpoint**: US4 is complete per the current spec; 0.1.0 settings carry over.

---

## Phase 11: User Story 6 - One clear voice for every callout (Priority: P3)

**Goal**: Every callout, warning and startup announcement in the Piper "Amy" voice when installed, with per-phrase fallback to the transmitter voice and DFM's recordings (FR-030–FR-037, SC-009, SC-010)

**Independent Test**: With the voice generated and deployed and Voice "Speed Gauge", the emulator console (Emulator Telemetry prints audio calls) shows `/Apps/AG-SpdGa/voice/...` paths for callouts, warnings and startup. With `voice/` removed and the app reloaded, settings show "Voice files missing" and every sound falls back (quickstart scenarios 48–52).

- [X] T060 [P] [US6] Create `tools/voice/make_voice.py` (Python 3.9, UTF-8, LF; module docstring with the copyright line "Copyright (c) 2026 Aaron George" and "SPDX-License-Identifier: MIT") per research R13. Arguments: `--model` (required, path to `en_US-amy-medium.onnx`; its `.onnx.json` sits next to it), `--out` (default `src/Apps/AG-SpdGa/voice`, resolved from the repo root, which is two levels above the script), `--rate` (16000, 22050 or 44100; default 22050), `--speed` (float, default 1.0; Piper `length_scale = 1 / speed`). Steps: (1) the phrase list as `(file stem, text)` pairs: `0`…`500` from a built-in US-English `number_words(n)` without "and" (0 "zero", 112 "one hundred twelve", 500 "five hundred"); `mph` "miles per hour", `kmh` "kilometers per hour", `kt` "knots", `ms` "meters per second", `fts` "feet per second", `pct` "percent", `stall` "stall warning", `over` "overspeed", `alive` "airspeed alive", `stallat` "stall warning at", `cal` "airspeed calibration" (512 files). (2) Load the voice once with `piper.PiperVoice.load(model)`, and synthesize each text into an in-memory `wave` file, using the synthesis call that matches the `piper-tts` version pinned in T061 (1.3+: `voice.synthesize_wav(text, wav, syn_config=SynthesisConfig(length_scale=...))`). (3) Convert to mono 16-bit samples with `array('h')`; trim leading and trailing samples below −45 dBFS (abs < 184), keeping 20 ms each side. (4) Scale so the peak is −1 dBFS (29205). (5) Resample to `--rate` by linear interpolation if it differs from the model's rate. (6) Write `<stem>.wav` (mono, 16-bit, `--rate`) into `--out`, creating it if needed, never writing elsewhere. (7) Write `CREDITS.txt`: Piper (MIT, https://github.com/rhasspy/piper) and the voice model "Amy" `en_US-amy-medium` (CC BY-SA 4.0, Mycroft / Rhasspy, https://huggingface.co/rhasspy/piper-voices), with a line saying the generated files are distributed under CC BY-SA 4.0 (FR-036). (8) Write `index.txt` last: voice name, rate, speed, file count. (9) Self-check: 512 `.wav` files present; print the longest number-only duration for 0–199 with its number; exit 1 if any file is missing or that duration is over 1.3 s (SC-009). Use only the standard library plus `piper`
- [X] T061 [P] [US6] Create `tools/voice/requirements.txt` pinning `piper-tts` to the version T060's synthesis call was written for, and `tools/voice/README.md`: what the set is (FR-030), install (`python -m pip install -r tools/voice/requirements.txt`), download `en_US-amy-medium.onnx` and `.onnx.json` from Hugging Face `rhasspy/piper-voices` (`en/en_US/amy/medium/`) to a folder outside the repo, the run command and options from quickstart Prerequisites, what it writes, the self-check, and licensing: the files are gitignored and not committed because the Amy model is CC BY-SA 4.0 with undocumented training-data licensing (FR-035); whoever distributes a generated set must follow CC BY-SA 4.0
- [X] T062 [US6] Generate the voice set (done 2026-10-03 at --speed 1.5; self-check passes, longest 1.28 s; committed per the changed FR-035): install per `tools/voice/README.md`, download the model, run `python tools/voice/make_voice.py --model <path>`. Confirm exit code 0, 512 WAVs plus `CREDITS.txt` and `index.txt` in `src/Apps/AG-SpdGa/voice/`, and that `git status` lists none of them (`.gitignore`). Needs network access and a package install: ask the user before installing, or leave this to the user
- [X] T063 [US6] Add the app-voice plumbing to `src/Apps/AG-SpdGa.lua` per research R14 and `specs/001-speed-gauge/contracts/audio-events.md`: file-level constants `VOICE_DIR = AUDIO_DIR .. "voice/"`, `VOICE_UNITS = { VOICE_DIR .. "mph.wav", VOICE_DIR .. "kmh.wav", VOICE_DIR .. "kt.wav", VOICE_DIR .. "ms.wav", VOICE_DIR .. "fts.wav" }` (indexed by `units`), `V_PCT`, `V_STALL`, `V_OVER`, `V_ALIVE`, `V_STALLAT`, `V_CAL` (`pct`, `stall`, `over`, `alive`, `stallat`, `cal` + `.wav`), `V_MAX_NUM = 500`. `local function fileExists(path)` = `local f = io.open(path, "r"); if f then io.close(f) return true end return false` (Jeti function-style `io`, constitution III). In `init()` after `loadSettings()`, set `voiceOk` true only if all 11 phrase/unit files plus `VOICE_DIR .. "0.wav"` and `"500.wav"` exist. Add `recomputeVoice()` (called from `recomputeAll()`): `useAppVoice = voiceOk and cfg.voice ~= 2`; `sndStall`, `sndOver`, `sndAlive` = the `V_*` paths when `useAppVoice`, else the existing DFM `SND_*` paths; `unitFile = VOICE_UNITS[cfg.units]`. `checkWarnings()` plays `sndStall` / `sndOver` / `sndAlive` with `AUDIO_IMMEDIATE`, vibration unchanged
- [X] T064 [US6] Speak callouts and startup announcements in the app voice in `src/Apps/AG-SpdGa.lua` (research R14, contracts/audio-events.md). `local function numFile(n)`: return nil unless `useAppVoice` and `0 <= n <= V_MAX_NUM`; build `VOICE_DIR .. n .. ".wav"` (only here, only when a callout is due); return it if `fileExists`, else nil. In `checkCallout()`, after `lastSpokenSpd`/`lastSpokenAt` are set: `local nf = numFile(n)`; if `nf`, `system.playFile(nf, AUDIO_QUEUE)` and, for the full form, `system.playFile(unitFile, AUDIO_QUEUE)` with no "Speed" prefix; otherwise the existing `playNumber` calls unchanged. In `init()`'s startup block: calibration `numFile(cfg.cal)` → `V_CAL`, number, `V_PCT` queued, else `SND_CAL` + `playNumber(cfg.cal, 0, "%")`; stall `numFile(cfg.vStall)` → `V_STALLAT`, number, `unitFile` queued, else `SND_STALL_AT` + `playNumber(cfg.vStall, 0, unitSpoken)`. Never play part of a phrase in one voice and the rest in the other (spec Edge Cases)
- [X] T065 [US6] Add rows 15a and 15b of `specs/001-speed-gauge/contracts/settings-form.md` to the "Callouts" group in `src/Apps/AG-SpdGa.lua`, after "Announce stall speed at startup": "Voice" selectbox `{"Speed Gauge", "Transmitter"}`, selected `cfg.voice` if it is 1 or 2, else `voiceOk and 1 or 2` (FR-032); on change `save("voice", i)` and `recomputeVoice()`. Hint "Voice files missing - using transmitter voice", visible only when `not voiceOk` (US6 #4)
- [ ] T066 [US6] MANUAL: Quickstart step 1's "22.05 kHz WAV plays" and "Start-up cost of the voice check" rows, then scenarios 48–52. On the transmitter (quickstart step 4), the SC-009 listening checks and whether `AUDIO_IMMEDIATE` cuts a queued callout. If 22.05 kHz doesn't play, regenerate with `--rate 44100` and flag FR-034 for a spec update

**Checkpoint**: All six user stories are complete.

---

## Phase 12: 0.2.0 Polish & Cross-Cutting Concerns

- [X] T067 [P] Add a "Speed Gauge voice" entry to `CREDITS.md`: Piper (MIT, https://github.com/rhasspy/piper) and the voice model Amy `en_US-amy-medium` (CC BY-SA 4.0, Mycroft / Rhasspy, https://huggingface.co/rhasspy/piper-voices), noting that the generated files aren't in the repo and are produced by `tools/voice/` (FR-036). Do not remove or shorten any existing text (constitution VIII)
- [X] T068 [P] In `README.md`, add a short note under the apps table that Speed Gauge's voice is generated locally with `tools/voice/` before deploying (link `tools/voice/README.md`), and that the app works without it in the transmitter's voice. Keep the "Based on" credit unchanged
- [X] T069 [P] In `tools/probe/PROBE.lua`, at start-up print each `system.getSensors()` entry with `param ~= 0` as "PROBE sensor: <label> unit=<unit> bytes=<#unit>" (research R15), so the transmitter's encoding of `°` in units can be read from the console. Keep the existing modes unchanged
- [ ] T070 [P] (Partly done 2026-10-04: sample rate, temperature unit and CPU recorded under "Verified on the transmitter". Still unmeasured: the pause between queued files, whether AUDIO_IMMEDIATE cuts the queue, the exact unit bytes.) Record in `docs/jeti-api-notes.md` the facts verified by T059 and T066: playable WAV sample rates, the pause between two `AUDIO_QUEUE` files, whether `AUDIO_IMMEDIATE` cuts the queue, the temperature unit string and its bytes, and that `registerForm`'s close callback fires when the form closes. If any contradicts `types/jeti.lua`, update the stub with a source note
- [X] T071 Review the 0.2.0 code in `src/Apps/AG-SpdGa.lua` for constitution VI: `readTemp` does nothing between reads and builds strings only on a change; `checkCallout` builds one path and calls `io.open` only when a callout is due; `form.setProperties` from `loop()` only behind `formOpen`; no `tStd` left. Then run `python tools/check.py` (0 errors) and confirm the LuaLS Problems panel shows no errors for `src/Apps/AG-SpdGa.lua`
- [ ] T072 MANUAL: Run the full `specs/001-speed-gauge/quickstart.md` again with the voice installed (steps 0–3, scenarios 1–55, resource checks), then step 4 on a dedicated test model on the transmitter. This closes T046 as well

---

## Phase 13: Transmitter fixes (first transmitter run, 2026-10-03)

**Purpose**: The first run on the DS-24 II showed that its Lua windows differ from the emulator's (`docs/jeti-api-notes.md`). The user chose the new layouts the same day (spec US3, `contracts/telemetry-window.md`)

- [X] T073 [US3] Name window 2 "Speed Gauge (full screen)" in `src/Apps/AG-SpdGa.lua`, so it can be told apart in Displayed telemetry (FR-013)
- [X] T074 [US6] Regenerate the voice faster: `--speed 1.2`, then 1.3 (user: "slightly slow", then "slightly faster still"; 1.3 is now the default), using `tools/voice/make_voice.py`. Also fix the generator for Python 3.9 (`Path.write_text` has no `newline=` before 3.10)
- [X] T075 [US3] Redesign the layouts in `src/Apps/AG-SpdGa.lua` for the transmitter's sizes per `specs/001-speed-gauge/contracts/telemetry-window.md`: subtract `TITLE_H` only for the emulator's widths (157, 320); strip layout for single (150 × 23); small dial plus numbers for double (150 × 68); full screen 316 × 159 with one-line panel rows; dial edges in 3° steps
- [X] T076 [US6] SC-009 kept at 1.3 s (user, 2026-10-03). The whole voice is now 1.5× (the generator's default), the user's choice over speeding up only the long numbers. Longest number up to 199: 176, 1.28 s; the self-check passes. The hint now says "Try a higher --speed"
- [X] T078 [US3] Smooth dial edges (user still saw choppy arcs, 2026-10-03): `tools/dial/make_dial.py` writes anti-aliased face-and-track PNGs for 316 × 159 and 150 × 68 into `src/Apps/AG-SpdGa/`; `src/Apps/AG-SpdGa.lua` loads the matching one per window size and falls back to live drawing with a soft translucent pass under each arc. Also: the RAW row shows "---" before the first reading. The user chose to keep the max-speed reset as it is (start-up, model load, manual reset)
- [X] T079 [US3] Smoother glow test (user: "fading bands aren't great"): twice as many thinner bands with a geometric alpha fade (`buildGlow`, 9 × 3 px full screen, 6 × 2 px double) on a 5° path, plus a TEMPORARY `DEBUG_CPU` readout (this call / worst `system.getCPU()`, top-left of the full-screen gauge) in `src/Apps/AG-SpdGa.lua`
- [X] T081 [US3] Glow and arcs as filled ring segments (user: band arcs "very chunky"; the zoom showed bright seams where translucent polyline joints overlap): new `band()` in `src/Apps/lib/ag_gauge.lua` (constitution VII: Speed Gauge is its only user); in `src/Apps/AG-SpdGa.lua` the glow is nested layers from the arc inward with solved per-layer alphas, and solid arcs plus their soft edge use `band()`. CPU readout before this change: 17% per redraw, 23% worst, without the speed arc
- [X] T082 [US3] Pre-drawn ring images for the solid arcs (zone, speed arc in each color, speed arc past the limit; `tools/dial/make_dial.py`), shown through `lcd.setClipping` in three 90° sectors. Found on the transmitter: `setClipping` also moves the drawing origin, so images are drawn at minus the clip corner. Then JETI Studio crashed while the speed rose: `ag_gauge.band()` built polygons of up to ~184 points (DFM-InsP's live arcs stay near 50). `band()` now draws pieces of at most 18 dial steps (≤ 44 points); Speed Gauge is the module's only user. MANUAL: confirm the emulator no longer crashes with the speed at full scale, and look for faint seams in the glow
- [X] T083 [US3] Emulator crash persisted after T082's split: Windows logs an access violation in JETI Studio's `dc-sim2.exe` / `Qt6Core.dll` at the same offset each time; the transmitter draws the same polygons fine. In the emulator's windows (widths 157 and 320) `src/Apps/AG-SpdGa.lua` now draws arcs and glow as polylines, as 0.1.0 did (`liveLines`); the transmitter keeps images and filled bands. MANUAL: confirm the emulator no longer crashes with speed at full scale
- [X] T085 [US3] Emulator full screen still stopped with the speed at full scale (no new Windows crash logged, so most likely the per-call CPU limit): the emulator's polyline glow now draws every other band at double width (5 lines, not 9). User confirmed the emulator works, 2026-10-03
- [X] T084 [US5] Rename "Gauge full scale" to "Gauge max limit" with two explanatory hints and "Auto (overspeed + 15%): N" (user request, 2026-10-03); spec US5 table and `contracts/settings-form.md` row 25 updated
- [X] T086 [US3] Live test: the full-screen gauge went blank at the 200 mph overspeed setting (the readout before it showed 43% / 52% worst with no speed and a long overspeed zone). The live glow bands were too expensive on the transmitter, so `tools/dial/make_dial.py` now bakes the glow into the ring images, and `src/Apps/AG-SpdGa.lua` draws no live glow when they exist. `drawRing` clips by quadrant (center lines run along the radius, so neighbors join exactly, glow included); only the moving cut is a straight edge, horizontal or vertical, whichever is closer to the radius
- [X] T087 [US1] "Callouts start above" (`vArm`, default 30 mph, 29 keys): callouts, normal and continuous, and "airspeed alive" wait until sensor speed first exceeds it, then stay armed for the session. Replaces the half-of-landing-speed rule, which continuous mode bypassed (user, 2026-10-03; spec FR-009, US1 #4/#7, US2 #4; settings rows 11a/11b; converted on units change)
- [X] T089 [US5] Settings wording (user, 2026-10-03): short hints under both callout switches; "Landing speed callouts" on/off checkbox (`landOn`, default on; 30 keys, the limit) above "Landing speed (unit)". Off: landing speed no longer makes callouts fast and short, but still arms the stall warning. Unit labels were already generic (they follow Units). Spec FR-006/FR-008 and the settings contract updated
- [X] T090 [US2] Stall warning at most twice per slowdown (`STALL_MAX`, `stallCount` in `src/Apps/AG-SpdGa.lua`); the count resets once above landing speed. Continuous callouts speak only while above "Callouts start above" (FR-009a); hint updated. User request after the live test, 2026-10-03 (no crashes). Quickstart 7a/7b added
- [X] T091 [US1] After live testing (user, 2026-10-04): `DEBUG_CPU = false` (T080 done); no callout below 5 mph or equivalent (FR-008b); "Longest time between callouts" 2–60 s, never below the shortest (FR-005); max-speed callout "max N unit" once the max hasn't risen for 1 s and beats the last announced max by the callout sensitivity (FR-019a). New voice phrase `max.wav`, added with the new `--missing` generator option so the committed files stay unchanged (513 files). Quickstart 13c–13e
- [ ] T088 [US6] MANUAL: "airspeed alive" didn't sound like the callouts on the transmitter. Check Settings → Voice: if it says "Voice files missing", the app didn't find the voice at start-up and everything fell back (transmitter voice for numbers, DFM's recording for "airspeed alive")
- [X] T080 [US3] Decide the glow from the transmitter screenshots and CPU readout (T079): keep the smoother bands if the worst full-screen call stays below 50% (SC-007) with the value arc near full scale, else dial back or switch to a single soft halo. Then set `DEBUG_CPU = false` (or remove it) before any release
- [ ] T077 [US3] MANUAL: On the transmitter, take screenshots of the single, double and full-screen windows with a speed showing, and with correction on. Check that nothing overlaps or is cut off, that arcs look smooth enough, and the full-screen CPU figure (SC-007)

---

## Dependencies & Execution Order

### Phase Dependencies

0.1.0 (Phases 1–8, done except MANUAL tasks):

- **Setup (Phase 1)**: No dependencies. T005 needs T004, and US3 needs T005
- **Foundational (Phase 2)**: Depends on T001 (audio paths). BLOCKS all user stories
- **US1 (Phase 3)**: Depends on Foundational
- **US2 (Phase 4)**: Depends on Foundational. Uses `switchOn()` from T014, so do it after US1
- **US3 (Phase 5)**: Depends on Foundational and T005. T022 can start any time
- **US4 (Phase 6)**: Depends on Foundational. T031/T032 can start any time; T034's marks and AIR DENSITY row are only visible once US3 is done
- **US5 (Phase 7)**: Depends on the rows it reviews and converts, so do it after US1–US4
- **Polish (Phase 8)**: After all desired stories

0.2.0 (Phases 9–12):

- **0.2.0 Foundational (Phase 9)**: T047 → T048 → T049 (same file). T050 any time. BLOCKS Phases 10 and 11
- **US4 temperature (Phase 10)**: After T049. T051 → T052 → T053 → T054 → T055 → T056 → T057 → T058 → T059 (all in `src/Apps/AG-SpdGa.lua` except the MANUAL check)
- **US6 voice (Phase 11)**: T060 and T061 (new files in `tools/voice/`) can start any time, in parallel with Phase 10. T062 needs T060 and T061. T063 needs T049 (the `voice` key) and is in the same file as Phase 10, so do it after T058, or before T051 if the voice comes first. T064 → T065 follow T063. T066 needs T062 (files to play) and T065
- **0.2.0 Polish (Phase 12)**: T067–T069 any time ([P], separate files). T070 after T059 and T066. T071 after the code tasks. T072 last

### User Story Dependencies

```text
0.1.0 (done):
Setup (T004 → T005) ─────────────────────────┐
  ↓                                          ↓
Foundational → US1 (MVP) → US2 → US3 ─→ US4 → US5 → Polish
                  └─ switchOn ─┘

0.2.0:
Phase 9 (T047 → T048 → T049) ─┬─→ Phase 10 US4 temperature (T051 … T058) → T059
                              └─→ Phase 11 US6 app code (T063 → T064 → T065) → T066
tools/voice: T060 + T061 (any time) → T062 (generate) ──────────────────────────┘
Docs any time: T050, T067, T068, T069.  After MANUAL checks: T070.  Then T071 → T072
```

US4's temperature work and US6 are independent of each other in behavior.
They only share `src/Apps/AG-SpdGa.lua`, so their code tasks run one after
another, in either order.

### Within Each User Story

- Settings keys and session state before the logic that reads them
- Logic before the form rows that drive it, and both before the MANUAL task
  that closes the story
- Commit after each task or logical group on `feature/001-speed-gauge`, and
  pull first: another session also pushes to this branch

### Parallel Opportunities

- T050 (`tests/test_ag_dens.lua`), T060 (`tools/voice/make_voice.py`), T061
  (`tools/voice/requirements.txt`, `README.md`), T067 (`CREDITS.md`), T068
  (`README.md`) and T069 (`tools/probe/PROBE.lua`) are separate files. They
  can be written while Phases 9–10 progress in `src/Apps/AG-SpdGa.lua`
- T062 (generating ~512 files) can run in the background while app code is
  written
- Everything in `src/Apps/AG-SpdGa.lua` is sequential

---

## Parallel Example: 0.2.0 alongside the app work

```text
# While T047–T058 are in progress on src/Apps/AG-SpdGa.lua:
Task: "T060 Create tools/voice/make_voice.py per research R13"
Task: "T061 Create tools/voice/requirements.txt and tools/voice/README.md"
Task: "T050 Add the R1 range-edge rows to tests/test_ag_dens.lua"
Task: "T069 Print sensor unit strings in tools/probe/PROBE.lua"
```

## Parallel Example: 0.2.0 Polish

```text
Task: "T067 Add the Piper / Amy entry to CREDITS.md"
Task: "T068 Add the voice note to README.md"
```

## Parallel Example: 0.1.0 (historical)

```text
Task: "T022 Create src/Apps/lib/ag_gauge.lua per contracts/lib-modules.md"
Task: "T032 Create src/Apps/lib/ag_dens.lua per contracts/lib-modules.md and research R1"
Task: "T031 Create tests/test_ag_dens.lua with the R1 reference values"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only) — done in 0.1.0

1. Phase 1: Setup. T005 can wait until before US3
2. Phase 2: Foundational (blocks everything)
3. Phase 3: US1
4. **STOP and VALIDATE** in the emulator (T017): a working speed announcer
5. Then add US2 so the warnings exist before any real flight. US1 alone is
   not for flying, because it has no stall warning

### 0.2.0 delivery

1. Phase 9 → 0.1.0 settings migrate, limits enforced. check.py passes
2. Phase 10 → temperature source; validate with T059 in the emulator (P7
   drives the MSpeed temperature). This is the higher-priority change (P2)
3. Phase 11 → app voice (P3). The app code works without the voice files
   (fallback), so T063–T065 can merge before T062/T066 are done, but the
   story isn't validated until T066
4. Phase 12 → credits, docs, findings, full validation (T072, which also
   closes T046) → merge `feature/001-speed-gauge` into `develop`

### Incremental Delivery (0.1.0, for reference)

1. Setup + Foundational → app loads, settings open
2. + US1 → callouts (MVP, emulator only)
3. + US2 → parity with DFM v2.1 audio; first candidate for a test-model bench run
4. + US3 → gauge in all three layouts
5. + US4 → density correction
6. + US5 → settings polish and units conversion

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps each task to a user story for traceability
- MANUAL tasks stay unticked until the user reports the result
- Conditional tasks (T028, T030) are ticked with "not needed" when their condition doesn't apply
- Stop at any checkpoint to validate a story on its own
- Never merge to `develop` before T071 passes and the MANUAL tasks are done
- Never `git add` anything under `src/Apps/AG-SpdGa/voice/` (FR-035)
