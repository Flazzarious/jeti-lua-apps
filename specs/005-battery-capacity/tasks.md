---

description: "Task list for Battery Capacity (AG-BatCp)"
---

# Tasks: Battery Capacity

**Input**: Design documents from `specs/005-battery-capacity/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: The spec doesn't ask for automated tests. The checks are the
voice generator's self-check, the `SIM` profiles and the manual scenarios
in [quickstart.md](quickstart.md) (E = emulator, T = transmitter, B = bench).

**Organization**: Tasks are grouped by user story so each story can be
built and checked on its own. Until User Story 6 adds the app voice, every
callout speaks through the transmitter's voice (the FR-033 fallback path),
so US2, US4 and US5 are testable without the voice files.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1–US6)
- **MANUAL**: Needs a person at JETI Studio or the transmitter. An agent
  can't run the emulator (CLAUDE.md): it prepares the build, deploys it to
  the emulator's Apps folder, lists what to check, and leaves the box
  unticked until Aaron reports back.

## Rules for every code task

- Follow `docs/examples/style/HELLO.lua`: 2-space indent, every variable and
  function `local` (constitution II), sections in the order given in
  [plan.md](plan.md#source-code-repository-root). Group constants, tables,
  layout numbers and per-battery state in tables: the main chunk may hold at
  most 200 locals.
- Header of every new Lua and Python file: `-- Copyright (c) 2026 Aaron
  George` / `-- SPDX-License-Identifier: MIT` (Python: `#`).
- Call only APIs declared in `types/jeti.lua` (constitution III; list in
  research R14). Never `system.registerControl`, `system.setControl`,
  `system.setProperty`. No `os`, `debug`, `coroutine`, `bit32`.
- Call `system.getSensor*` through `system` every time (the emulator's
  telemetry app replaces them, Speed Gauge R3).
- `lcd.*` only in the two print functions; `form.*` only in the form's
  init, callbacks and close function. Exception: `loop()` may call
  `form.setProperties` on the live-value label and setup notes only while
  `formOpen` is true (Speed Gauge R17). `form.question` only from callbacks.
- No `string.format`, `..` or `{}` in `loop()` or the print functions,
  except rebuilding cached strings on the 1 s tick when their value changed
  and building a phrase's file paths at dispatch (research R9).
- `src/Apps/AG-BatCp.lua` is one file, so tasks that touch it run one after
  another. Generator, lib, probe, docs and emulator config are separate
  files.
- Run `python tools/check.py` after each phase (Lua 5.3 syntax check
  included since `ee5c8aa`). It must report 0 errors. LuaLS must show no
  errors.
- After each phase that changes the app, deploy to the emulator unasked:
  copy `src/Apps/AG-BatCp.lua`, `src/Apps/AG-BatCp/`, `src/Apps/lib/ag_peak.lua`
  and `tools/emulator/sensors.json` (to `Apps/EmulatedTelemetry/`) into
  `%LOCALAPPDATA%\JETI-Studio\Emulator\Apps`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Measure the font, prepare emulator sensors and the shared max filter

- [X] T001 [P] Add a `FONT_MINI` width mode to `tools/probe/PROBE.lua` (research R6): in its print function, for each character of `"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789- "` call `lcd.getTextWidth(FONT_MINI, c)` once and `print` a single line `MINI_W A=7 B=6 ...` to the console; also print the widths of the full strings `"FLIGHT-2"`, `"BRAKES-2"`, `"LIGHTS-2"`, `"GEAR-2"`, `"RX-2"`, `"NO"`, `"TELEM"`, `"100%"` in `FONT_MINI` and `"100%"` in `FONT_NORMAL`. Follow the probe's existing mode switch; don't change its other modes
- [ ] T002 MANUAL: Run the probe's width mode on the transmitter (and in the emulator for comparison). Record the widths in `docs/jeti-api-notes.md` under "Window sizes" (new "FONT_MINI character widths" bullet). Decide with the numbers: which default labels with a number exceed `SLOT_W − 2` = 35 px and need the short form ("FLT", "BRK", "LGT", FR-003), and whether "TELEM" fits the 26-px body. Then replace the estimated `MINI_W` table in `src/Apps/AG-BatCp.lua` with the measured widths
- [X] T003 [P] Add the test sensors to `tools/emulator/sensors.json` (research R13), keeping existing entries unchanged: name rows `{"id": 4, "param": 0, "decimals": 0, "type": 1, "label": "MUI 75", "unit": "", "sensorName": "MUI 75"}`, `{"id": 5, ... "label": "Rx" ...}`, `{"id": 6, ... "label": "Central Box" ...}`; values `id 4 param 1` "Voltage" `V` decimals 2, 6.0–8.6, input P1; `id 4 param 2` "Current" `A` decimals 1, 0–120, P2; `id 4 param 3` "Capacity" `mAh` decimals 0, 0–5000, P3; `id 5 param 1` "U Rx" `V` decimals 2, 5.6–7.0, P4; `id 6 param 1` "Battery %" `%` decimals 0, 0–100, P9
- [X] T004 [P] Create `src/Apps/lib/ag_peak.lua` per [contracts/lib-modules.md](contracts/lib-modules.md): header comment like `src/Apps/lib/ag_gauge.lua` (purpose, "no mutable state", time passed in); `local HOLD_MS = 1000`; `M.new()` returns `{ max = 0, prev = nil, prevT = 0 }`; `M.update(st, value, nowMs)`: if `st.prev == nil` → `st.prev, st.prevT = value, nowMs`, return `st.max, false`; if `value ~= st.prev` → candidate `math.min(st.prev, value)`, then `st.prev, st.prevT = value, nowMs`; else if `nowMs - st.prevT >= HOLD_MS` → candidate `value`; else no candidate; `st.max = math.max(st.max, candidate)` and return `st.max, rose`; `M.reset(st)` sets `max = 0, prev = nil, prevT = 0`. No `lcd`, `form`, `system` calls; `return M`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Settings, sensor reading, telemetry tracking, the callout scheduler and the core settings form that every story builds on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 Create `src/Apps/AG-BatCp.lua` skeleton: MIT header with a one-paragraph description; `APP_NAME = "Battery Capacity"`, `APP_VERSION = "0.1.0"`, author "Aaron George"; debug constants `SIM = false`, `DEBUG_CPU = false`; `local peak = require("ag_peak")`; constant tables from [data-model.md](data-model.md): `CAT` by id 1–8 (name, label, short label, voice stem, chem, bands Y/O/R, levels 1–4, current rows shown/hidden, max default) and `CAT_ORDER` display list; `CHEM` 1–5 (name, Full, Nominal, Warning, Cutoff in cV) and `CURVE[chem]` 11 cV points 100→0% from research R3; `BAND` colours green 99,153,34 / yellow 242,194,48 / orange 239,159,39 / red 226,75,74 with text colours (white; dark 65,36,2 on yellow); timing constants `FAST_MS = 200`, `SLOW_MS = 1000`, `LOST_MS = 1000`, `NEWPACK_PTS = 20`, `HYST = 5`; `MINI_W` placeholder table (filled from T002); layout constants per [contracts/telemetry-window.md](contracts/telemetry-window.md). End with `return { init = init, loop = loop, destroy = destroy, author = ..., version = APP_VERSION, name = APP_NAME }`
- [X] T006 Settings in `src/Apps/AG-BatCp.lua` per data-model "Saved settings": app keys `cfgV`, `voice`, `numOnly`, `smallB`; per battery N `bNp` (20 ints), `bNa` (18 ints), `bNs` (5 strings) with field indexes as named constants (e.g. `P_CAT = 1 … P_EDITED = 20`, `A_LVL1 = 1 … A_SHOWALL = 18`, `S_NAME = 1 … S_ILBL = 5`). `loadSettings()`: missing key → defaults ("Missing key → default"); clamp every integer to the data-model range and save a clamped value back; unknown category id kept, shown "Unknown (N)" with Custom speech; compact empty slots so batteries 1…n are contiguous; `smallB` > count → 1. `saveBattery(k)` saves the three arrays; `saveApp()`. Battery creation `newBattery(cat)` fills from `CAT`/`CHEM` defaults (lvlOn = 8, rptS 5, maxCnt 0, lvDly 20, iThr/iDly/iRpt 0, maxSens 5, npOn 0, npThr 90, showAll 0); `deleteBattery(k)` moves slots k+1…4 down, saves `nil` for the freed key set, adjusts `smallB` (research R5)
- [X] T007 Derived values in `src/Apps/AG-BatCp.lua` (`recompute(k)`, called after load and after any setting change, never per tick): `label` (Custom name; else category label or short label when it doesn't fit by `MINI_W`; plus `"-" .. num` when num > 0), label numbering rule (a second battery in a category gives the first `num = 1` and itself the next free number; deleting one doesn't renumber the rest, spec edge case "Third pack in a category"), `speech` (voice stem + number), `voltOf` (voltage sensor, else capacity source when capMode 4, else none), `hasV`, `hasI`, `lowest` enabled level, `lvThrCell`, `iOn` (iThr, iDly, iRpt all > 0). App: `useAppVoice = voiceOk and voice ~= 2` (voiceOk false until US6)
- [X] T008 Session state and ticks in `src/Apps/AG-BatCp.lua`: per battery a state table built in `init()` with every field from data-model "Session state" (`tel = NONE`, flags cleared, `peak = peak.new()`); `loop()` returns at once unless a battery exists; fast tick every `FAST_MS` and slow tick every `SLOW_MS` from `system.getTimeCounter()`; `DEBUG_CPU` prints `system.getCPU()` at the end of `loop()`
- [X] T009 Sensor reading and telemetry tracker in `src/Apps/AG-BatCp.lua` (research R1, R4): fast tick reads, per battery, capacity source, voltage reading and current via `system.getSensorValueByID(id, par)` (skip id 0); a reading counts only when the result is non-nil and `.valid`; accumulate voltage into `vSum`/`vN`; current in A (× 0.001 when edited bit 15 marks mA); `badSince` when the capacity source goes invalid; `LIVE → LOST` after `LOST_MS`; shorter gaps hold the last value. Slow tick: `NONE → LIVE` starts a pack session; `LOST → LIVE` compares the new % with `pctLast`: new pack when ≥ `NEWPACK_PTS` higher and (no separate voltage reading, or the unsmoothed voltage estimate is also ≥ 20 higher), else brown-out keeping all state. Provide `startPackSession(k)` that resets fired levels, repeat counters, low-voltage state, `peak.reset`, `lastAnn`, `npDone`, and sets `npDueT = now + 3000` (story tasks hook into it). `SIM` (when true) replaces battery 1's reads with a scripted profile selected by a `SIM_PROFILE` constant; profiles are added by story tasks
- [X] T010 Callout scheduler in `src/Apps/AG-BatCp.lua` (research R9, [contracts/audio-events.md](contracts/audio-events.md)): per battery pending flags and values `pendLv`, `pendCur`, `pendLvl`, `pendNp`, `pendMax`; `raise(k, kind, value)` sets or updates (never duplicates); `clearAll(k)` on loss; `dispatch()` runs on each slow tick and on the first fast tick after `system.isPlayback()` turns false: if nothing is playing, scan kinds in FR-034a order (low voltage, high current, capacity level, pack not full, max), batteries 1→4, speak the first raised flag, clear it, record its start time. Speech output for now is the transmitter path only: `system.playFile(voiceName, AUDIO_QUEUE)` when the battery's `bNs[2]` is set, then `system.playNumber(value, decimals, unit)` with unit `"%"`, `"V"` or `"A"`. A `speak(k, kind, value)` function wraps this so US6 can add the app voice
- [X] T011 Settings form core in `src/Apps/AG-BatCp.lua` per [contracts/settings-form.md](contracts/settings-form.md): `system.registerForm(1, MENU_APPS, APP_NAME, initForm, keyForm, printForm, closeForm)`; `formOpen` flag. Subform 1: battery links (text "RX-1  Receiver  LiFe 2S"), "Add battery" (hidden at 4; creates a Receiver battery and opens it), "Small window shows" selectbox, credits/version label (`FONT_MINI`). Subforms 2–5: rows 1–10 (Category, Name for Custom, Label, Chemistry, Cells 1–14, Capacity 100–30 000 step 50, Capacity / Voltage / Current sensor selectboxes, live value), row 28 voice name (`form.addAudioFilebox`), row 31 "Show all settings", row 32 "Delete battery" (with `form.question`). Sensor lists from one `system.getSensors()` pass on subform open, skipping `param == 0`, filtered by unit per research R1 (capacity: `mAh`, `Ah`, `%`, `V`; voltage: `V`; current: `A`, `mA`), first entry "(none)", saved sensor missing → "<label> (not found)" kept and selected. Choosing a capacity sensor saves capMode from its unit. Key handler: F5/ESC on a battery subform → `form.preventDefault()` and `form.reinit(1)`. Live value label updated from `loop()` each slow tick while `formOpen`
- [X] T012 Defaults and overwrite question in `src/Apps/AG-BatCp.lua` (FR-006–FR-008, research R11): changing category refills chemistry suggestion, bands, levels, current-row visibility, max default; changing chemistry or cells refills the four voltages and the low-voltage threshold. Before refilling, if the edited mask has a bit set for an affected group (bit 0 voltages, 1 bands, 2 levels, 3 low-voltage threshold), ask `form.question("Overwrite edited values?", ...)`; Yes refills all and clears those bits, No refills only unedited groups. Editing a value in a group sets its bit. Then `recompute(k)`, `saveBattery(k)`, `form.reinit` to redraw
- [X] T013 Window registration and empty states in `src/Apps/AG-BatCp.lua`: `system.registerTelemetry(1, "Battery", 1, printSmall)` and `system.registerTelemetry(2, "Batteries", 2, printDouble)`; `gaugeOk` from `system.getDeviceType()` containing "24 II" (Speed Gauge R12); emulator width 157 → `h = h - 26` and a 3-px x offset; not `gaugeOk` → "Battery Capacity needs DS-24 II", no batteries → "Add a battery in settings", both `FONT_MINI` in `lcd.getFgColor()`
- [X] T014 Run `python tools/check.py` (0 errors) and check LuaLS; deploy to the emulator

**Checkpoint**: Batteries can be added, configured with sensors and deleted; settings persist; telemetry state is tracked; windows show the empty state

---

## Phase 3: User Story 1 - See how full a pack is (Priority: P1) 🎯 MVP

**Goal**: One battery in the small window, filled to its % remaining in the band colour, from an mAh, %, or voltage sensor

**Independent Test**: Quickstart E1–E5 and E17: one battery each on mAh, % and voltage sensors; vary the values; check fill, colour, number and NO TELEM in the small window

- [X] T015 [US1] Capacity maths in `src/Apps/AG-BatCp.lua` (FR-004, research R1): on the slow tick per LIVE battery, mode 1 `pct = (mAh − value) · 100 / mAh`, mode 2 `(mAh − value · 1000) · 100 / mAh`, mode 3 `value`, mode 4 voltage (T016); integer, clamped 0–100 ("Consumed mAh exceeds rated capacity" → 0, never negative); mAh = 0 with modes 1–2 → no % (grey "--", note "Set capacity" in the form)
- [X] T016 [US1] Voltage estimate in `src/Apps/AG-BatCp.lua` (research R3): `vNow = vSum / vN` per slow tick (cV), per cell `vNow / cells`; at or below Cutoff → 0; else linear interpolation in `CURVE[chem]`; one-pole filter `vEst = vEst + 0.1 · (raw − vEst)`, initialised directly on the first reading of a pack session; hold (don't update) while a current sensor reads above `max(1, mAh / 10000)` A
- [X] T017 [US1] Band and cached strings in `src/Apps/AG-BatCp.lua`: band = red if `pct < bandR`, orange if `pct < bandO`, yellow if `pct < bandY`, else green (data-model: "below" is strict); rebuild `txtPct` ("72%"), `txtSmall` ("8.1V 0.4A", parts only for assigned readings, "--" for a lost one) only when the underlying rounded value changed
- [X] T018 [US1] `printSmall` in `src/Apps/AG-BatCp.lua` per [contracts/telemetry-window.md](contracts/telemetry-window.md) "Small window": battery `smallB`; outline x 1, y 1, 82 × 21, radius 2 and cap x 83, y 7, 3 × 9 in `lcd.getFgColor()`; fill x 3, y 3, height 17, width `(78 · pct + 50) // 100` in the band colour; `txtPct` centred on the body (`FONT_NORMAL`, top y 2) with the straddle rule (draw clipped twice with `lcd.setClipping`, offset by the clip corner, `lcd.resetClipping()`); label at x 90, y −1 and `txtSmall` at x 90, y 10 in `FONT_MINI`. States: LOST → outline and texts in the foreground colour at alpha 100, no fill, "NO TELEM" inside; NONE or no capacity source → grey "--" inside. No max current here (FR-010)
- [X] T019 [US1] Label width and custom name in `src/Apps/AG-BatCp.lua` (FR-003, research R6): fill `MINI_W` from T002; `labelWidth(s)` sums `MINI_W` (unknown characters count as the widest capital); Name textbox callback trims characters from the end until `labelWidth ≤ SLOT_W − 2`, saves, and shows "Shortened to fit" under the box until the form closes; short category labels used where T002 showed the numbered default doesn't fit
- [X] T020 [US1] Cell-count check in `src/Apps/AG-BatCp.lua` (research R11): while `formOpen` and a voltage reading is valid, under the Cells row show "Check cell count: reads N.N V" when `v / cells` > Full + 10 cV or < Cutoff − 30 cV
- [X] T021 [US1] Add `SIM` profiles 1 (slow discharge 100→0% over 5 min on mAh) and 2 (voltage with ±3% noise) for battery 1 in `src/Apps/AG-BatCp.lua`
- [X] T022 [US1] Run `python tools/check.py`; deploy to the emulator
- [ ] T023 [US1] MANUAL: Emulator, quickstart E1–E5 and E17; `SIM` profiles 1 and 2 (fill tracks %, voltage % smooth). Set `SIM = false` afterwards

**Checkpoint**: The small window shows one battery correctly from any of the three source kinds (MVP)

---

## Phase 4: User Story 2 - Hear when a pack is getting low (Priority: P1)

**Goal**: Capacity callouts with repeats, and the low-voltage alarm with a flashing outline

**Independent Test**: Quickstart E6, E7, E10, E14: discharge through enabled levels and below the low-voltage threshold, including noise and short sags; console shows callouts in order

- [ ] T024 [US2] Callout level rows in `src/Apps/AG-BatCp.lua` (FR-016, contract rows 11–16): four rows of checkbox + intbox "1–99 %"; enabled levels "strictly descending": on a violating change revert to the previous value and show "Levels must go down: 60 > 50 > 40 > 30"; rows 15 "Repeat lowest every" 3–60 s and 16 "Max repeats" 0 (no limit), 1–20 visible only with Show all; editing sets edited bit 2; after any change re-arm levels from the current % (edge case "Callout levels edited mid-session")
- [ ] T025 [US2] Level engine in `src/Apps/AG-BatCp.lua` (FR-017, FR-018, data-model "Capacity level k"): slow tick per LIVE battery: a level fires when `pct <= level` and it is armed; re-arms at `pct >= level + HYST`; when several fire in one tick raise only the lowest (`raise(k, LVL, level)`); at pack session start mark every level with `pct <= level` fired and raise only the lowest (US2 #4). The lowest enabled level, once fired, re-raises every `rptS` start to start, up to `maxCnt` plays (0 = no limit), stopping on re-arm or LOST; if the lowest is disabled while repeating, the next lowest becomes the repeating one without replaying
- [ ] T026 [US2] Low-voltage rows in `src/Apps/AG-BatCp.lua` (FR-019, contract rows 17–19, shown only with a voltage reading): selectbox Off / Per cell / Per pack (default Per cell when `hasV`); threshold intbox in cV shown with 2 decimals per cell or 1 decimal per pack, default `vWarn` or `vWarn · cells`; switching mode converts the threshold; delay 0.5–10 s (5–100 ds) with Show all; editing the threshold sets edited bit 3
- [ ] T027 [US2] Low-voltage alarm in `src/Apps/AG-BatCp.lua` (FR-020–FR-022, data-model "Low-voltage alarm"): fast tick: per-cell voltage below `lvThrCell` continuously for `lvDly` → `lvOn`, `raise(k, LV, v)`; clear after `>= thr + 5 cV` per cell continuously for `lvDly`, or on new pack; repeats every `rptS` up to `maxCnt`. Spoken value: per cell `playNumber(v, 2, "V")`, per pack `playNumber(v, 1, "V")` (transmitter path for now). Flash: in both print functions draw outline and cap red 226,75,74 when `lvOn` and `(system.getTimeCounter() // 500) % 2 == 0`
- [ ] T028 [US2] Add `SIM` profiles 3 (noisy discharge through 60/50/40/30), 4 (voltage sag below threshold for 1.5 s, then for 3 s) and 5 (start at 35%) in `src/Apps/AG-BatCp.lua`
- [ ] T029 [US2] Run `python tools/check.py`; deploy to the emulator
- [ ] T030 [US2] MANUAL: Emulator, quickstart E6, E7, E10 and E14; `SIM` profiles 3–5 (one callout per level, lowest repeats every 5 s and stops at max count, no alarm for the 1.5 s sag, alarm and flash for the 3 s sag). Set `SIM = false` afterwards

**Checkpoint**: A low pack is spoken (in the transmitter's voice) and flashes; US1 still works

---

## Phase 5: User Story 3 - All packs at once in the double window (Priority: P2)

**Goal**: Up to four upright batteries side by side in the double window

**Independent Test**: Quickstart E9: 1–4 batteries; alignment, spacing, blank unused slots, delete shifts left

- [X] T031 [US3] Cached `txtLine` in `src/Apps/AG-BatCp.lua` (FR-011): current "42.5 A" when a current sensor is assigned ("--" when lost); else pack voltage "8.1 V" when a voltage reading exists; else empty; rebuilt only when the rounded value changes
- [X] T032 [US3] `printDouble` in `src/Apps/AG-BatCp.lua` per [contracts/telemetry-window.md](contracts/telemetry-window.md) "Double window": slot k at `x0 = 1 + (k − 1) · 37`; label centred in the slot, top y 0, `FONT_MINI`; cap centred, y 12, 10 × 3; outline x0 + 5, y 15, 26 × 40, radius 2; fill x0 + 7, bottom at y 52, 22 wide, height `(36 · pct + 50) // 100`; `txtPct` centred on the body, top y 40, `FONT_MINI`, with the straddle rule; `txtLine` centred, top y 56. Unused slots draw nothing. States as in T018, with "NO" / "TELEM" stacked at y 24 and 36 when LOST; flash as in T027. Read `lcd.getFgColor()` once per frame
- [X] T063 [US3] Editable window titles (FR-009a, added after the 2026-11-01 emulator review) in `src/Apps/AG-BatCp.lua`: keys `title1`, `title2` (string, "" = default "Battery" / "Batteries", up to 20 characters); main-page textboxes "Small window title" and "Double window title" (contract rows 3a, 3b) with the hint "New titles show after the model is reloaded."; `init()` registers each window with its saved title
- [X] T033 [US3] Run `python tools/check.py`; deploy to the emulator
- [ ] T034 [US3] MANUAL: Emulator, quickstart E9 with 1, 2, 3 and 4 batteries, and E8 (`DEBUG_CPU`: worst print figure under 10%). Transmitter T4: screenshots of both windows in the light and the dark theme; check the small window's two text lines don't overlap, % readable on every band (white on orange; switch to dark text if not, FR-013), outlines visible on both themes (FR-012a). Tune layout constants as needed

**Checkpoint**: Both windows work with four batteries

---

## Phase 6: User Story 4 - Current draw and max current (Priority: P2)

**Goal**: Current shown, one current alarm, and spike-filtered max current callouts

**Independent Test**: Quickstart E11, E12: hold current above the alarm; spike profile for max

- [ ] T035 [US4] Current rows in `src/Apps/AG-BatCp.lua` (FR-024, contract rows 20–25, shown only with a current sensor; hidden for ECU and Lights unless Show all, FR-007): "Current alarm above" 0–500 A (0 = off), "for" 0–10 s (1 decimal), "repeat every" 0–60 s, note listing which are still 0 ("Current alarm off: set delay"); "Max current callouts" checkbox (default from category); "Max sensitivity" 1–50 A with Show all; "Reset max current" link (`peak.reset`, `lastAnn = 0`, clear `pendMax`)
- [ ] T036 [US4] Current alarm in `src/Apps/AG-BatCp.lua` (data-model "Current alarm"): fast tick, only when `iOn`: above `iThr` continuously for `iDly` → raise HICUR with the rounded current; repeats every `iRpt` while above; clears when `i <= iThr`
- [ ] T037 [US4] Max current in `src/Apps/AG-BatCp.lua` (FR-025–FR-027, research R7): fast tick `local m, rose = peak.update(st.peak, i, now)`; `rose` → `riseT = now`; slow tick: when `maxOn`, `now − riseT >= 1000` and `m − lastAnn >= maxSens`, `raise(k, MAX, round(m))` (replaces a waiting value, FR-034a); set `lastAnn` when it is spoken; reset on new pack (T009), "Reset max current", and app start
- [ ] T038 [US4] Add `SIM` profiles 6 (climb-outs with single-sample spikes and a held 92 A peak) and 7 (steady 40 A from power-up) in `src/Apps/AG-BatCp.lua`
- [ ] T039 [US4] Run `python tools/check.py`; deploy to the emulator
- [ ] T040 [US4] MANUAL: Emulator, quickstart E11 and E12; `SIM` 6 (spike never becomes the max; "92" spoken once 1 s after the peak) and 7 (steady current still registers). Set `SIM = false` afterwards

**Checkpoint**: Electric flight packs are fully covered

---

## Phase 7: User Story 5 - Warn about a pack that isn't full (Priority: P3)

**Goal**: One "pack not full" callout 3 s after a new pack when enabled

**Independent Test**: Quickstart E13: power up at 80% and 95%; swap packs mid-session; brown-out

- [ ] T041 [US5] New-pack check rows in `src/Apps/AG-BatCp.lua` (FR-029, contract rows 26–27, only with a voltage reading): "Check pack is full" checkbox (default off); "Full above" 50–99 % (default 90) with Show all
- [ ] T042 [US5] New-pack check in `src/Apps/AG-BatCp.lua`: slow tick, when `npOn`, not `npDone` and `now >= npDueT`: estimate % from the resting curve of the current 1 s voltage (unsmoothed); below `npThr` → `raise(k, NP, pct)`; set `npDone` either way. Brown-outs don't reschedule it (T009)
- [ ] T043 [US5] Add `SIM` profiles 8 (start at 82%), 9 (start at 95%), 10 (dropout and return 30 points higher with voltage) and 11 (dropout, same value: brown-out) in `src/Apps/AG-BatCp.lua`
- [ ] T044 [US5] Run `python tools/check.py`; deploy to the emulator
- [ ] T045 [US5] MANUAL: Emulator, quickstart E13; `SIM` 8–11 (one callout at 82, none at 95, new pack resets max and re-arms levels, brown-out keeps everything). Set `SIM = false` afterwards

**Checkpoint**: All alarm kinds work in the transmitter's voice

---

## Phase 8: User Story 6 - One clear voice for every callout (Priority: P3)

**Goal**: Every callout in the Amy voice with the pack name first, falling back to the transmitter's voice

**Independent Test**: Quickstart E15 and T3: console shows the phrase files in order; on the transmitter the phrases play in Amy, and in the transmitter's voice with the voice folder removed

- [ ] T046 [P] [US6] Create `tools/voice/make_batcap.py` (research R8), starting from `tools/voice/make_turbine.py`: import `synthesize`, `trim`, `normalize`, `resample`, `write_wav`, `write_text`, `PEAK` from `make_voice.py` (add `tools/voice` to `sys.path`; don't modify `make_voice.py`); arguments `--model` (required), `--out` (default `src/Apps/AG-BatCp/voice`), `--rate` 22050, `--speed` 1.5; copy `0.wav`…`500.wav` byte-for-byte from `src/Apps/AG-SpdGa/voice/`; synthesise the 17 word files from the table in research R8 ("E C U" for `n_ecu`); write `CREDITS.txt` ("Battery Capacity (AG-BatCp) - app voice", Piper MIT, Amy CC BY-SA 4.0, numbers copied from Speed Gauge's set) and `index.txt` last; self-check, exit 1 on failure: 518 WAVs, numbers identical to the source, each word file ≤ 1.3 s
- [ ] T047 [US6] Run `python tools/voice/make_batcap.py --model C:\Users\aaron\piper-voices\en_US-amy-medium.onnx`; confirm the self-check passes; commit `src/Apps/AG-BatCp/voice/` (CC BY-SA 4.0)
- [ ] T048 [US6] MANUAL: Listen to the word files on the PC (especially "E C U", "landing gear", "volts per cell"): same voice and pace as Speed Gauge. Approve or ask for changes
- [ ] T049 [US6] Voice check in `src/Apps/AG-BatCp.lua` (research R9): in `init()`, `io.open` each of the 17 word files plus `0.wav` and `500.wav` with the absolute path `/Apps/AG-BatCp/voice/<f>`, then without the leading "/" (emulator); close each; `voiceOk` = all present; `recompute` `useAppVoice`
- [ ] T050 [US6] App-voice phrases in `speak()` in `src/Apps/AG-BatCp.lua` per [contracts/audio-events.md](contracts/audio-events.md): when `useAppVoice` and every number ≤ 500 and its file opens: `playFile(path, AUDIO_QUEUE)` for name (`n_*` + number file when numbered), event word, number(s) (voltage as int · `point` · digits), unit (omitted with `numOnly`); otherwise the whole phrase on the transmitter path (T010). Paths built only here
- [ ] T051 [US6] Main-page voice rows in `src/Apps/AG-BatCp.lua` (FR-031, FR-032, contract rows 4–7): Voice selectbox "Battery Capacity" / "Transmitter" (first shows "(files missing)" when `voiceOk` is false), "Speak number only" checkbox, status label "Voice files missing: transmitter voice in use", credits "Voice: Piper, Amy (CC BY-SA 4.0)."
- [ ] T052 [US6] Run `python tools/check.py`; deploy to the emulator including `AG-BatCp/voice/`
- [ ] T053 [US6] MANUAL: Emulator, quickstart E15 and the E6/E10/E11 phrases with the voice installed (console shows `n_rx`, `2`, `30`, `pct` in order); rename the voice folder and confirm the fallback and the settings status. Transmitter T3: phrases play as one continuous phrase; `playNumber` waits behind the name file (if not, implement research R9's continuation-flag fallback); T6 with Flameout Alarm installed

**Checkpoint**: All stories complete

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Docs, credits, release readiness and real-world checks

- [ ] T054 [P] Add a Battery Capacity section to `README.md`: apps table row, what it does, install (app, `AG-BatCp/`, and `lib/ag_peak.lua`, FR-037), setup steps, voice credit (CC BY-SA 4.0), advice to assign a voltage sensor (brown-out vs swap, research R4) and that a voltage-only gauge is a resting estimate (R3)
- [ ] T055 [P] Add a Battery Capacity section to `CREDITS.md` (Piper MIT, Amy CC BY-SA 4.0, number files shared with Speed Gauge's set)
- [ ] T056 [P] Add the apps table row to `CLAUDE.md`: Battery Capacity | `src/Apps/AG-BatCp.lua` | `specs/005-battery-capacity/` | original
- [ ] T057 [P] Add a Battery Capacity section to `tools/voice/README.md` (what `make_batcap.py` writes, how to run it, numbers copied from Speed Gauge)
- [ ] T058 [P] Record transmitter findings in `docs/jeti-api-notes.md`: sensor units (T060), `playNumber` after a queued `playFile` (T053), clipping-based text cost (T034)
- [ ] T059 Quickstart section 1 static checks: `python tools/check.py` 0 errors; LuaLS clean on `AG-BatCp.lua` and `lib/ag_peak.lua`; search for forbidden APIs (none); `SIM` and `DEBUG_CPU` false
- [ ] T060 MANUAL: Transmitter T1 (units of Aaron's sensors match research R1), T5 (pack swap and a short receiver dropout), T7 (30 minutes, four batteries, both windows, no CPU-limit error), T8 (install on a card with no other AG- apps)
- [ ] T061 MANUAL: Bench B1 (LiPo and LiFe packs at rest vs the charger's state, SC-004) and B2 (fresh LiFe with the new-pack check on: no callout); adjust `CURVE` entries if needed
- [ ] T062 MANUAL: SC-001 timing (one battery under 2 minutes, four under 6) and Aaron's sign-off on readability outdoors in both themes (SC-005), which also confirms or replaces FR-012a

---

## Dependencies & Execution Order

- **Setup (Phase 1)**: T001 → T002 (MANUAL; its widths feed T019). T003, T004 independent.
- **Foundational (Phase 2)**: needs T004 (`require("ag_peak")`). T005 → T013 in order (one file). Blocks every story.
- **US1 (Phase 3)**: after Phase 2. T019 needs T002's widths (a placeholder table works until then).
- **US2 (Phase 4)**: after US1 (needs `pct` and the print functions for the flash).
- **US3 (Phase 5)**: after US1 (reuses band, strings, straddle rule); independent of US2 except the flash, which is added in whichever lands second.
- **US4 (Phase 6)**: after Phase 2; display of current needs US1/US3's strings.
- **US5 (Phase 7)**: after US1 (voltage estimate).
- **US6 (Phase 8)**: T046–T048 can start any time after Phase 1 (separate files); T049–T053 after Phase 2.
- **Polish**: after the stories it documents.

### Within each story

- Code tasks in order (one file), then `check.py`, deploy, MANUAL check.
- MANUAL checks of one phase can run while the next phase's code is written.

---

## Parallel Example: Setup and voice

```text
T001 PROBE.lua width mode        | T003 sensors.json        | T004 ag_peak.lua
T046 make_batcap.py (any time after Phase 1, while app tasks run)
T054–T058 docs (once the behaviour they describe is final)
```

---

## Implementation Strategy

### MVP first

1. Phase 1 and Phase 2.
2. Phase 3 (US1): one battery in the small window. Stop and check E1–E5.

### Incremental delivery

3. US2: low-pack callouts and low-voltage alarm (transmitter voice) — the
   safety value.
4. US3: double window with four batteries.
5. US4, US5: current, max, pack-not-full.
6. US6: the Amy voice.
7. Polish, transmitter and bench checks, then release (PR to `develop`,
   later `develop` → `main`, tag `AG-BatCp-v0.1.0`, publish in Apps.json).

---

## Notes

- [P] = different files, no dependencies.
- MANUAL tasks stay unticked until Aaron reports the result.
- Commit after each phase on `feature/005-battery-capacity`.
