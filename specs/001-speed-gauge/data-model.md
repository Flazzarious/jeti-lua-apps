# Data Model: Speed Gauge

**Feature**: `specs/001-speed-gauge/` | **Date**: 2026-09-27, updated 2026-10-03
(voice, temperature source, FR-020 limits)

Two kinds of state: **model settings**, persisted per model with
`system.pSave`, and **session state**, held in locals and rebuilt by `init()`
(constitution IV). Derived values are recomputed only when a setting changes.

## Model settings (persisted)

All values are integers, strings or SwitchItems (no floats). Speeds are stored
in the selected units; elevation and temperature in the unit system the speed
units imply (FR-023). 30 keys: the limit of 30 (constitution IV); make room before adding another. The `winSz` fallback
is not needed: size 0 was verified in the emulator (research R7), so the key
is never created.

| Key | Type | Range | Default | Setting (label) |
| --- | --- | --- | --- | --- |
| `sId` | int | sensor id, 0 = none | 0 | Speed sensor |
| `sPar` | int | param | 0 | Speed sensor |
| `sLbl` | string < 64 B | | "" | Speed sensor (shown if not found) |
| `sType` | int | 1 Airspeed, 2 GPS | 1 | Sensor type |
| `swOn` | SwitchItem | | nil | Callouts on/off switch |
| `swCont` | SwitchItem | | nil | Continuous callouts switch |
| `tMin` | int s | 1–10 | 2 | Shortest time between callouts |
| `tMax` | int s | 10–60 | 40 | Longest time between callouts |
| `sens` | int unit | 1–100 | 10 | Callout sensitivity (speed change) |
| `vLand` | int unit | 0–1000 | 60 | Landing speed (fast callouts below) |
| `vStall` | int unit | 0–1000 | 45 | Stall warning at |
| `vOver` | int unit | 0–1000 | 200 | Overspeed warning at |
| `cal` | int % | 1–200 | 100 | Sensor calibration |
| `units` | int | 1 mph, 2 km/h, 3 kt, 4 m/s, 5 ft/s | 1 | Units |
| `numOnly` | int 0/1 | | 0 | Speak number only |
| `startAnn` | int 0/1 | | 1 | Announce stall speed at startup |
| `densOn` | int 0/1 | | 0 | Correct for air density |
| `elev` | int ft or m | −300–10000 ft / −90–3050 m (FR-020) | 0 | Field elevation |
| `temp` | int °F or °C | −20–130 °F / −29–54 °C (FR-020) | 59 °F / 15 °C | Temperature (manual) |
| `tSrc` | int | 1 Standard, 2 Manual, 3 Sensor | 1 | Temperature source (FR-038); replaces `tStd` |
| `tId` | int | sensor id, 0 = none | 0 | Temperature sensor |
| `tPar` | int | param | 0 | Temperature sensor |
| `tLbl` | string < 64 B | | "" | Temperature sensor (shown if not found) |
| `colCur` | int | 1–9 (R8: Cyan, Blue, White, Green, Lime, Magenta, Purple, Grey, Yellow) | 1 Cyan | Current speed color |
| `colMax` | int | 1–9 | 9 Yellow | Max speed color |
| `fScale` | int unit | 0 = Auto, 10–2000 | 0 | Gauge full scale |
| `voice` | int | 0 not chosen, 1 Speed Gauge, 2 Transmitter | 0 | Voice (FR-032). 0 resolves to Speed Gauge if the voice files are present, else Transmitter (research R14) |
| `vArm` | int unit | 0–1000 | 30 | Callouts start above (FR-009, added 2026-10-03). Converted with the other speeds on a units change |
| `landOn` | int 0/1 | | 1 | Landing speed callouts (FR-006, added 2026-10-03). Off: below-landing fast short callouts stop; stall arming unchanged |
| `cfgV` | int | | 2 | Settings layout version. 1 = 0.1.0 (had `tStd`); 2 = this design |

Defaults for speeds match v2.1 (`VrefSpd` 60, `Vs0Spd` 45, `maxSpd` 200 in
mph). Keys are new, so nothing is read from the original app's settings
(FR-027).

### Validation

- Intbox ranges enforce every range above. `loadSettings()` clamps every
  integer setting into its range and saves the clamped value (research R16).
- Threshold order is checked, not enforced (FR-026): flag if
  `vStall >= vLand`, `vLand >= vOver`, or `fScale ~= 0 and vOver > fScale`.
- `temp` is used only while `tSrc = 2`; `tId`/`tPar` only while `tSrc = 3`.
- Migration (`cfgV` 1 → 2): `tStd = 1` becomes `tSrc = 1`, `tStd = 0` becomes
  `tSrc = 2`; then `tStd` is deleted (`pSave("tStd", nil)`).
- Sensor temperature is converted to °C if its unit ends in "F", accepted
  only within the FR-020 limits of the unit system in use (−20–130 °F or
  −29–54 °C), and applied with a 1 °C hysteresis (FR-040, FR-041,
  research R15).
- Density settings are ignored while `sType = 2` (GPS).

### Units change

When `units` changes from unit A to B, each of `sens`, `vLand`, `vStall`,
`vOver` and non-zero `fScale` becomes `round(value · unitsMult[B] /
unitsMult[A])`, clamped to its range. If A and B are in different systems
(imperial: mph, kt, ft/s; metric: km/h, m/s), `elev` and `temp` are converted
too, then clamped to the new system's FR-020 limits. All are saved
immediately. `tId`/`tPar` are unchanged; the sensor reading is converted
from its own unit at each read.

## Derived values (recomputed on setting change, never per tick)

| Name | Formula | Recomputed when |
| --- | --- | --- |
| `kSensor` | `unitsMult[units] · cal / 100` (sensor value is m/s, R3) | `units`, `cal` |
| `kDens` | `ag_dens.factor(elevM, tempC or nil)` if `densOn = 1` and `sType = 1`, else 1. `tempC` is nil (standard) for `tSrc = 1`, the manual value for 2, and the accepted sensor value for 3 (nil while unavailable) | `densOn`, `sType`, `elev`, `temp`, `tSrc`, sensor temperature (≥ 1 °C change), `units` |
| `fullScale` | `fScale`, or if 0: `ceil(vOver · 1.15 / 10) · 10` | `fScale`, `vOver` |
| `fStall`, `fLand`, `fOver` | dial fractions of `vStall · kDens`, `vLand · kDens` and `vOver` over `fullScale` (FR-016a) | any of the above |
| `scaleStep`, scale labels | `ag_gauge.scaleStep(fullScale)`; array of label strings "0", "50", ... | `fullScale`, `units` |
| `unitText`, `unitSpoken` | display "kt" / spoken "kt." etc. from the v2.1 list | `units` |
| `unitFile` | app-voice unit path, e.g. `/Apps/AG-SpdGa/voice/mph.wav` (research R13) | `units` |
| `useAppVoice` | `voiceOk and voice ~= 2` (research R14) | `voice`; `voiceOk` is fixed in `init()` |
| `tempC` | temperature for `kDens`, °C: nil for `tSrc = 1`; manual value (converted) for 2; `tUseC` while `tStat = 2`, else nil, for 3 | `tSrc`, `temp`, `units`, `tStat`, `tUseC` |
| row texts | Stall, Overspeed values as entered (e.g. "45"); unit; density row "+8%"; temperature row value (e.g. "95 °F", the temperature in use, standard included) and source tag (FR-044, contracts/telemetry-window.md) | thresholds, `units`, `kDens`, `tempC` |

`unitsMult` is v2.1's m/s-to-unit table: mph 2.23694, km/h 3.6, kt 1.94384,
m/s 1, ft/s 3.28084.

## Session state (not persisted)

Reset by `init()`, so it resets on power-on, model load and app reload
(FR-019, Edge Cases).

| Name | Type | Initial | Meaning |
| --- | --- | --- | --- |
| `sensorSpd` | number\|nil | nil | Latest valid sensor speed (calibrated, in units). nil = no data |
| `shownSpd` | number\|nil | nil | `sensorSpd · kDens`: shown, spoken, overspeed |
| `maxSpd` | number | 0 | Session max of `shownSpd`, spike-filtered (R5) |
| `prevDistinct` | number\|nil | nil | Previous distinct `shownSpd`, for R5 |
| `distinctSince` | int ms | 0 | When `shownSpd` last changed; a value held 1 s counts for the max (R5) |
| `everAboveLanding` | bool | false | Sensor speed has exceeded `vLand` this session |
| `belowLanding` | bool | false | Currently at/below `vLand` after being above |
| `armed` | bool | false | Sensor speed has exceeded `vArm` this session (FR-009 gate; was `everAboveHalf`, `vLand / 2`) |
| `aliveSaid` | bool | false | "Airspeed alive" has played |
| `stallArmed` | bool | true | Stall warning may fire |
| `overArmed` | bool | true | Overspeed warning may fire |
| `lastSpokenSpd` | int | 0 | Rounded value of the last callout |
| `lastSpokenAt` | int ms | 0 | `getTimeCounter()` at last callout |
| `lastTick` | int ms | now | Rate limiter for `loop()` (100 ms) |
| `curText`, `maxText`, `sensText` | string | "---", "0", "" | Cached number strings, rebuilt only when the rounded value changes. `sensText` is the uncorrected sensor speed for the full-screen density row |
| `gaugeOk` | bool | set in `init()` | Device is a DS-24 II (research R12). Only the print function reads it |
| `voiceOk` | bool | set in `init()` | All phrase and unit files plus `0.wav` and `500.wav` open (research R14) |
| `tStat` | int | 0 | Temperature sensor status: 0 not in use, 1 waiting (rejected), 2 in use (research R15) |
| `tUseC` | number\|nil | nil | Accepted sensor temperature, °C, with 1 °C hysteresis |
| `tGood` | int | 0 | Consecutive good reads while waiting |
| `tEver` | bool | false | A reading has been accepted or rejected since start-up / choosing Sensor (first read needs only one good read) |
| `tNextRead` | int ms | now | Next temperature read (every 5 s) |
| `formOpen` | bool | false | Settings form is open; `loop()` may update the temperature status label (research R17) |
| `tempText`, `tStatText` | string | "" | Cached full-screen temperature value and settings status label, rebuilt when `tempC`, `tStat` or `units` change |
| `layout` | table | nil | Layout cache for the last `(w, h)` per window (research R6); rebuilt when size or scale changes |
| `rend` | Renderer | nil | Created lazily in the print function and reused (research R6) |

## State transitions

Evaluated every 100 ms tick. "Valid" = sensor selected, reading non-nil and
`.valid`. An invalid reading sets `sensorSpd = shownSpd = nil` and changes
nothing else (Edge Cases): no callouts, no warnings, no max update.

```text
Warnings (a crossing fires only while a switch is on; re-arming is always tracked):

 stall:     armed --[everAboveLanding and sensorSpd <= vStall]--> fired (sound, vibrate 4), stallCount += 1
            fired --[sensorSpd > vStall and stallCount < 2]--> armed
            any   --[sensorSpd > vLand]--> stallCount = 0 (then re-arms)
            (at most 2 stall warnings per slowdown, FR-010, 2026-10-03)
 continuous callouts: only while sensorSpd > vArm (FR-009a)
 overspeed: armed --[shownSpd > vOver]--> fired (sound, vibrate 3)
            fired --[shownSpd <= vOver]--> armed
 alive:     not said --[armed]--> said (once per session)

Flight flags (whenever valid):
 sensorSpd > vArm              -> armed = true (latched)
 sensorSpd > vLand             -> everAboveLanding = true, belowLanding = false
 sensorSpd <= vLand and ever   -> belowLanding = true

Callout due when all hold:
 - a switch is on
 - not system.isPlayback()
 - now >= lastSpokenAt + interval   (R9)
 - armed (FR-009; continuous mode no longer bypasses it)
 Short form (number only) if numOnly, belowLanding (or never above), or continuous.
```

A crossing while no switch is on does not fire and the warning stays armed,
as in v2.1, which returns early when both switches are off.

Each sound is chosen by research R14: app voice if `useAppVoice` and every
file of the phrase is present, otherwise the transmitter voice or DFM's
recording.

### Temperature sensor (research R15)

Evaluated every 5 s, only while `densOn = 1`, `sType = 1` and `tSrc = 3`;
otherwise `tStat = 0`. A read is *good* when the entry exists, is `valid`,
and is within the FR-020 limits of the unit system in use.

```text
 not in use (0) --[source becomes Sensor]--> waiting (1), tEver = false, tGood = 0

 waiting:  good and not tEver       -> in use, tUseC = read, tEver = true
           good and tEver           -> tGood += 1; tGood = 2 -> in use, tUseC = read
           bad                      -> tGood = 0, tEver = true
 in use:   good, |read - tUseC| >= 1 °C -> tUseC = read
           good, smaller change     -> nothing
           bad                      -> waiting, tGood = 0, tUseC = nil

 Any change of tStat or tUseC -> recomputeDensity() (kDens, fractions, row
 texts, layout refresh) and, if formOpen, the status label. Never a callout.
```

### Settings load (research R16)

```text
 cfgV = 1: tSrc = (tStd == 1) and 1 or 2; pSave("tStd", nil); cfgV = 2
 every integer key: clamp to its range; save if changed
```
