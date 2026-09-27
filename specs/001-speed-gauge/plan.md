# Implementation Plan: Speed Gauge

**Branch**: `feature/001-speed-gauge` (Gitflow: merges to `develop`, then `main` on release) | **Date**: 2026-09-27 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/001-speed-gauge/spec.md`

## Summary

A new app, **Speed Gauge** (`src/Apps/AG-SpdGa.lua`), that re-implements DFM
Speed Announcer v2.1's callouts and warnings with clearer settings, adds an
optional air-density correction, and draws a speedometer modeled on the
spec's visual design reference (dark face, numbered scale, colored value arc,
overspeed zone, big center number, sticky session-max marker). It targets the
DS-24 II's measured Lua window sizes and shows a notice on other
transmitters.

Approach:

- **One app file plus two new shared modules.** `ag_dens` holds the ISA
  density math; `ag_gauge` holds dial geometry and arc drawing. Both are
  stateless (constitution VII).
- **Two speeds per tick.** *Sensor speed* (calibrated, in the user's units)
  drives stall, landing and "airspeed alive". *Shown speed* (sensor speed ×
  density factor) drives the gauge, callouts, max and overspeed. This is the
  spec's Q1 clarification (FR-011).
- **Cheap per-tick work.** All conversion factors are folded into two
  multipliers when a setting changes. `loop()` does its work every 100 ms
  with two multiplies, a few comparisons and no string or table work.
- **Two windows, three layouts.** A pilot-sized window (single 157 × 60 →
  compact arc; double 157 × 127 → round dial) and a full-screen window
  (320 × 260 → big dial plus side panel). One print function picks the layout
  from its `(w, h)` and draws from a layout cache (research R6, R7).
- **v2.1 kept where the spec is silent.** Callout timing, sounds and vibration
  profiles are unchanged. Every deliberate difference is listed in
  [research.md R11](research.md#r11-behavior-differences-from-dfm-speed-announcer-v21-sc-008).

## Technical Context

**Language/Version**: Lua 5.3.1 on the transmitter (32-bit integers and floats)

**Primary Dependencies**: JETI DC/DS Lua API v1.5 as declared in `types/jeti.lua`: `system`, `lcd` (incl. `lcd.renderer`), `form`. New shared modules `ag_dens` and `ag_gauge`.

**Storage**: `system.pSave`/`pLoad`, per model, 24 keys (25 with the `winSz` fallback) ([data-model.md](data-model.md)). No files written.

**Testing**: `python tools/check.py`; LuaLS diagnostics; optional `tests/test_ag_dens.lua` under any Lua 5.3 (none installed locally, so it's optional like `luac` in check.py); scripted emulator scenarios in [quickstart.md](quickstart.md); bench test on a test model.

**Target Platform**: JETI DS-24 II / DC-24 II, firmware 6.03+ (emulator 6.04). Lua window sizes 157 × 60, 157 × 127 and 320 × 260 (measured; `docs/jeti-api-notes.md`). `lcd.renderer` needs V4.27+. Other transmitters get callouts and warnings, and a notice instead of the gauge (FR-013a)

**Project Type**: Embedded transmitter app (single Lua script, asset folder, shared lib modules)

**Performance Goals**: Gauge reflects speed within 0.5 s (SC-005); logic tick 100 ms; app CPU < 20% with the gauge shown (SC-007)

**Constraints**: No allocation in `loop()` or the print function; call `system.getSensor*` through `system` each time, never a cached local (research R3, Emulator Telemetry swaps them); `lcd` only in print functions; `form` only in form callbacks; ≤ 30 persisted keys; no `os`/`debug`/`coroutine`/`bit32`; never `registerControl`/`setControl`/`setProperty`

**Scale/Scope**: One app (~800–1,000 lines estimated), two modules (~60 and ~120 lines), 5 reused WAV files

All former unknowns are resolved in [research.md](research.md). The window
sizes are now measured. Four API assumptions remain **UNVERIFIED** and are
checked in the emulator before gauge work
([quickstart.md step 1](quickstart.md#step-1-confirm-unverified-api-assumptions-before-gauge-layout-work)):
whether a size-0 window lets the pilot choose single or double (R7, with a
fallback setting), the DS-24 II's `getDeviceType()` string (R12), renderer
reuse across frames (R6), and whether `°` renders. Font heights are also
measured there so the layouts can fit text.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | How the design complies |
| --- | --- | --- |
| I. Nothing flight-critical | PASS | Only reads sensors and switches, plays audio, vibrates sticks, draws. No `registerControl`, `setControl`, `setProperty`, gpio or serial. If the app stops, the model is unaffected |
| II. Everything local | PASS | All app and module symbols `local`; the files export only via their final `return` |
| III. Transmitter APIs only | PASS | Every call is in `types/jeti.lua`, including `getDeviceType`, `renderPolygon` and, for the CPU fallback only, `lcd.createImage`. Uses `math`, `string` only. No `io` needed (the v2.1 `.jsn` calibration file is dropped) |
| IV. State resets on model switch | PASS | Session state initialized in `init()`; settings via `pSave` (ints, strings, SwitchItems); floats (density factor) derived, never saved; 24–25 keys ≤ 30 |
| V. Stable names, UTF-8 | PASS | `AG-SpdGa.lua`, assets in `AG-SpdGa/`, absolute `/Apps/AG-SpdGa/...` paths; UTF-8/LF enforced by check.py; charset check for `°` planned |
| VI. Keep loop() light | PASS | 100 ms tick; `getSensorValueByID` in the loop; strings cached and rebuilt on change; trig precomputed; layout cache per window size; renderer reused if possible; off-screen image fallback if CPU is high (R6) |
| VII. Shared code in lib, stateless | PASS | `ag_dens` pure functions; `ag_gauge.newDial`/`newCircle` return caller-owned tables, and the layout cache lives in the app; neither module registers anything. New modules, so no other apps to re-verify |
| VIII. License and credit | PASS | Planned: header with this repo's copyright + SPDX + DFM MIT notice; settings footer credit; README and CREDITS.md rows; `AG-SpdGa/CREDITS.txt` for the WAVs |

**Post-design re-check (after Phase 1, updated for the gauge design
reference):** PASS. The contracts add nothing that touches principles I–VIII
beyond the table above. `ag_gauge` calls `lcd`, but only from the app's print
function, as its contract states. The `tools/probe/PROBE.lua` change is a dev
tool outside `src/Apps`, never deployed with the app.

## Project Structure

### Documentation (this feature)

```text
specs/001-speed-gauge/
├── spec.md
├── plan.md               # this file
├── research.md           # Phase 0: decisions R1–R12
├── data-model.md         # Phase 1: settings, derived values, session state, transitions
├── quickstart.md         # Phase 1: validation steps
├── contracts/
│   ├── settings-form.md      # rows, order, behavior
│   ├── telemetry-window.md   # windows, compact/round/full-screen layouts, states
│   ├── lib-modules.md        # ag_dens and ag_gauge APIs
│   └── audio-events.md       # sounds, vibration, callouts
├── checklists/requirements.md
└── tasks.md              # /speckit-tasks; regenerate after this plan update
```

### Source Code (repository root)

```text
src/Apps/
├── AG-SpdGa.lua              # the app: settings form, loop logic, print function
├── AG-SpdGa/
│   ├── CREDITS.txt           # DFM credit + MIT notice for the WAVs
│   ├── airspeed_alive.wav    # copied unmodified from docs/examples/dfm-speed-announce/DFM-SpdA/
│   ├── airspeed_cal_factor.wav
│   ├── overspeed.wav
│   ├── stall_speed_warning_at.wav
│   └── stall_warning.wav
└── lib/
    ├── ag_dens.lua           # density factor, unit conversions
    └── ag_gauge.lua          # dial geometry, scale step, face/arc/mark/tick drawing

tools/probe/PROBE.lua         # dev tool (exists): add MODE 3, a size-0 window, for research R7

tests/
└── test_ag_dens.lua          # optional, plain Lua 5.3, asserts R1 reference values

README.md                     # apps table: status, credit
CREDITS.md                    # DFM Speed Announcer entry, full MIT text
CLAUDE.md                     # apps table: drop "(planned)"
```

Inside `AG-SpdGa.lua`, sections follow `docs/examples/style/HELLO.lua`:
constants and persisted keys → settings and derived values → session state →
helpers (unit tables, recompute functions) → settings form → print function →
`init` / `loop` / `destroy` → `return { ... }`.

**Structure Decision**: The repo's standard app layout (constitution V, VII).
`tests/` is new and sits outside `src/` so it is never deployed and check.py's
`src/Apps` layout rule doesn't apply to it.

## Implementation order

For `/speckit-tasks`. Each step leaves check.py passing.

1. **Emulator facts first** (quickstart step 1): window sizes are done; add
   the probe's size-0 mode, then record size-0 behavior, the device string
   and font heights. Update `types/jeti.lua` / `docs/jeti-api-notes.md` with
   anything learned.
2. **`ag_dens` + its test** (US4 math, R1).
3. **App skeleton**: header with credits, settings load/save, form with all
   rows (US5), derived-value recompute, sensor list and selection (R4).
4. **Loop logic**: tick, speeds, flags, warnings, callouts (US1, US2), spike
   filtered max (R5).
5. **`ag_gauge` + print function** (US3): layout selection and cache, then
   the round layout (the reference design), compact, full screen, the notice
   for other transmitters, and a CPU check with the full-screen dial.
6. **Units conversion, order warning, reset max, startup announcement**.
7. **Assets and docs**: WAVs + CREDITS.txt, README, CREDITS.md, CLAUDE.md.
8. **Validation**: quickstart steps 0–3, then step 4 on the test model.

## Complexity Tracking

No constitution violations to justify.
