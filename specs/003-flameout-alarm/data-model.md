# Data Model: Flameout Alarm

Three kinds of data: **settings** (persisted per model), **derived values**
(recomputed when a setting changes) and **session state** (in memory, reset
by `init()` on every model load, constitution IV). Decisions are cited as
R1–R12 ([research.md](research.md)).

## Settings (persisted with `system.pSave`)

Integers, strings and one SwitchItem; booleans as 0/1; times in tenths of
a second; RPM in hundreds. 17 keys (limit 30).

| Key | Type | Range | Default | Meaning | Spec |
| --- | --- | --- | --- | --- | --- |
| `en` | 0/1 | | 0 | Monitoring enabled | FR-001, FR-003 |
| `sId` | int | | 0 | RPM sensor id (0 = none) | FR-002 |
| `sPar` | int | | 0 | RPM sensor param | FR-002 |
| `sLbl` | string | < 64 bytes | "" | Sensor label, for "(not found)" | FR-022 |
| `scl` | int | 1–4 | 1 | Sensor scale: ×1, ×10, ×100, ×1000 | FR-006a |
| `swCut` | SwitchItem | | nil | Cut switch, assigned in the Cut position | FR-005, R10 |
| `idle` | int | 0–1500 | 0 | Idle RPM / 100 (0 = not set) | FR-006 |
| `maxR` | int | 0–3000 | 0 | Max RPM / 100 (0 = auto: 4 × idle) | FR-031b |
| `armP` | int | 50–98 | 90 | Arming threshold, % of idle | FR-007 |
| `flP` | int | 20–95 | 70 | Flameout threshold, % of idle | FR-007 |
| `armT` | int | 10–100 | 30 | Arming time, 0.1 s | FR-008 |
| `detT` | int | 3–50 | 10 | Detection delay, 0.1 s | FR-008 |
| `lossT` | int | 5–100 | 20 | Telemetry-loss delay, 0.1 s | FR-008 |
| `sayArm` | 0/1 | | 0 | Speak "Flameout alarm armed" | FR-009 |
| `sayRel` | 0/1 | | 0 | Speak "Engine relit" | FR-009 |
| `swTest` | SwitchItem | | nil | Test alarm switch or button (optional) | FR-030a, R13 |
| `cfgV` | int | | 1 | Settings layout version, for future migrations | |

(`swCut` and `swTest` are stored as SwitchItems; `pSave(key, nil)` deletes
one.)

**Validation** (settings form, [contracts/settings-form.md](contracts/settings-form.md)):

- `en = 1` only if `sId ≠ 0`, `swCut ≠ nil` and `idle > 0` (FR-003).
- `flP < armP` (FR-007). Arming threshold < idle holds because `armP ≤ 98`.
- `maxR = 0` or `maxR > idle` (FR-031b edge case).
- **On load**, every integer is clamped to its range; if a loaded
  combination is invalid (e.g. `flP ≥ armP` from a hand-edited model), the
  defaults for `armP`/`flP` are restored and `en` is forced to 0 if a
  required item is missing.

## Derived values (recomputed on any setting change, never in `loop()`)

| Name | Formula | Use |
| --- | --- | --- |
| `active` | `en = 1` and `sId ≠ 0` and `swCut ≠ nil` and `idle > 0` | `loop()` returns right after the test-alarm check when false (FR-012, FR-034) |
| `kScale` | 1, 10, 100, 1000 by `scl` | RPM = value × `kScale` |
| `idleRpm` | `idle × 100` | marker, labels |
| `armRpm` | `idleRpm × armP / 100` | arming and relight (FR-014, FR-018) |
| `flRpm` | `idleRpm × flP / 100` | detection (FR-015) |
| `fullRpm` | `maxR × 100`, or `4 × idleRpm` if `maxR = 0` | bar full scale (FR-031b) |
| `armMs`, `detMs`, `lossMs` | tenths × 100 | timers |
| `idleX` | idle marker x per layout: `X0 + (idleRpm / fullRpm) · (X1 − X0)` | window (R11) |
| threshold strings | e.g. "31.5k" | settings rows |

## Session state (reset in `init()`)

| Name | Type | Meaning |
| --- | --- | --- |
| `state` | int | `OFF`, `DISARMED`, `ARMED`, `FLAMEOUT` |
| `rpm` | int or nil | last valid scaled RPM; nil while invalid |
| `sensorFound` | bool | last read returned an entry (false → NO SENSOR) |
| `invalidSince` | ms or nil | first invalid sample of the current loss |
| `lost` | bool | invalid for at least `lossMs` (NO TELEMETRY) |
| `armSince` | ms or nil | RPM ≥ `armRpm` since (DISARMED, or FLAMEOUT for relight) |
| `lowSince` | ms or nil | RPM < `flRpm` since (ARMED) |
| `cycleAt` | ms | start of the current alarm cycle |
| `beepAt` | ms or nil | second fallback beep burst due (R6) |
| `tlPending` | bool | play `cycletl.wav` at the next cycle (R4) |
| `testOn` | bool | a test alarm is playing (R13) |
| `testPrev` | bool | test switch was on last tick (rising-edge detection) |
| `audioOk` | bool | both cycle files exist (checked once in `init()`, R6) |
| `fileOk` | table | per-file existence for the three short phrases |
| `rpmText`, `rpmHundreds` | string, int | cached "112,400" and the value it was built from |
| `lastTick` | ms | 100 ms logic tick (R8) |
| `formOpen` | bool | settings form open (live RPM row) |

## State transitions (each 100 ms tick, R8)

Evaluated in this order. "Valid" = sensor entry exists and `valid` is true.

| # | From | Condition | To | Actions |
| --- | --- | --- | --- | --- |
| 0 | any | `active` is false | OFF | stop alarm if sounding; window shows OFF |
| 1 | any | Cut switch in Cut | DISARMED | `stopPlayback(AUDIO_IMMEDIATE)` if FLAMEOUT; clear all timers, `tlPending`, `lost` (FR-016) |
| 2 | any | sample invalid | (same) | set `invalidSince` if nil; clear `armSince`, `lowSince`; once `now − invalidSince ≥ lossMs` and not `lost`: `lost = true`; if ARMED play `tlost.wav` (I); if FLAMEOUT set `tlPending` (FR-020, FR-020a). Skip rows 3–5 |
| — | any | sample valid | (same) | `invalidSince = nil`, `lost = false`, `rpm = value × kScale` |
| 3 | DISARMED | `rpm ≥ armRpm` held `armMs` | ARMED | play `armed.wav` (Q) if `sayArm` (FR-014) |
| 4 | ARMED | `rpm < flRpm` held `detMs` | FLAMEOUT | start alarm: `cycleAt = now`, play cycle file (I), vibrate (FR-015) |
| 5 | FLAMEOUT | `rpm ≥ armRpm` held `armMs` | ARMED | `stopPlayback(AUDIO_IMMEDIATE)`; play `relit.wav` (Q) if `sayRel` (FR-018) |
| 6 | FLAMEOUT | `now − cycleAt ≥ 5000` | FLAMEOUT | next cycle: `cycletl.wav` if `tlPending` (then clear it) else `cycle.wav`, (I); vibrate; `cycleAt += 5000` (or `now` if more than one cycle behind) |

**Test alarm** (R13), evaluated every tick before row 0 and independent of
`state`. `T` = test switch on (`getInputsVal(swTest) > 0.5`, false if
unassigned):

| # | Condition | Actions |
| --- | --- | --- |
| T1 | `T` and not `testPrev`, state OFF or DISARMED, not `testOn` | `testOn = true`, `cycleAt = now`, play cycle (as row 4, `cycle.wav` only) |
| T2 | `testOn` and `now − cycleAt ≥ 5000` | next cycle, as row 6 |
| T3 | `testOn` and (not `T`, or state became ARMED or FLAMEOUT) | `testOn = false`, `stopPlayback(AUDIO_IMMEDIATE)` |
| — | always | `testPrev = T` |

Row 0 doesn't stop a test (the test works while OFF). A real alarm (row 4)
can't start during a test because the test only runs while not ARMED.

Notes:

- Row 2 runs during FLAMEOUT too, but row 6 still runs: the alarm keeps
  sounding through a telemetry loss (FR-020a).
- In FLAMEOUT, RPM between `flRpm` and `armRpm` (startup range during an
  auto-restart) breaks `armSince` without starting anything new
  (FR-017).
- After DISARMED by Cut, row 3 needs the switch out of Cut **and** RPM held
  at or above `armRpm` (User Story 5).
- `I` = `AUDIO_IMMEDIATE`, `Q` = `AUDIO_QUEUE`. Missing files: [contracts/audio-events.md](contracts/audio-events.md).

## Window display state (derived each frame, no extra storage)

| Shown | When |
| --- | --- |
| TEST | `testOn` (takes precedence over OFF and DISARMED) |
| OFF | `state = OFF` |
| NO SENSOR | active, sensor entry missing |
| NO TELEMETRY | active, `lost`, not FLAMEOUT |
| DISARMED / ARMED | `state` |
| FLAMEOUT | `state = FLAMEOUT`; with "NO TELEMETRY" note when `lost` |
