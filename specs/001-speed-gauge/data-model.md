# Data Model: Speed Gauge

**Feature**: `specs/001-speed-gauge/` | **Date**: 2026-09-27

Two kinds of state: **model settings**, persisted per model with
`system.pSave`, and **session state**, held in locals and rebuilt by `init()`
(constitution IV). Derived values are recomputed only when a setting changes.

## Model settings (persisted)

All values are integers, strings or SwitchItems (no floats). Speeds are stored
in the selected units; elevation and temperature in the unit system the speed
units imply (FR-023). 24 keys, under the limit of 30.

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
| `elev` | int ft or m | −1000–15000 ft / −300–4600 m | 0 | Field elevation |
| `temp` | int °F or °C | −22–122 °F / −30–50 °C | 59 °F / 15 °C | Temperature |
| `tStd` | int 0/1 | | 1 | Use standard temperature |
| `colCur` | int | 1–8 (R8) | 1 Blue | Current speed color |
| `colMax` | int | 1–8 | 2 Orange | Max speed color |
| `fScale` | int unit | 0 = Auto, 10–2000 | 0 | Gauge full scale |
| `cfgV` | int | | 1 | Settings layout version (for future migrations) |

Defaults for speeds match v2.1 (`VrefSpd` 60, `Vs0Spd` 45, `maxSpd` 200 in
mph). Keys are new, so nothing is read from the original app's settings
(FR-027).

### Validation

- Intbox ranges enforce every range above.
- Threshold order is checked, not enforced (FR-026): flag if
  `vStall >= vLand`, `vLand >= vOver`, or `fScale ~= 0 and vOver > fScale`.
- Temperature is ignored while `tStd = 1`.
- Density settings are ignored while `sType = 2` (GPS).

### Units change

When `units` changes from unit A to B, each of `sens`, `vLand`, `vStall`,
`vOver` and non-zero `fScale` becomes `round(value · unitsMult[B] /
unitsMult[A])`, clamped to its range. If A and B are in different systems
(imperial: mph, kt, ft/s; metric: km/h, m/s), `elev` and `temp` are converted
too. All are saved immediately.

## Derived values (recomputed on setting change, never per tick)

| Name | Formula | Recomputed when |
| --- | --- | --- |
| `kSensor` | `unitsMult[units] · cal / 100` (sensor value is m/s, R3) | `units`, `cal` |
| `kDens` | `ag_dens.factor(elevM, tempC or nil)` if `densOn = 1` and `sType = 1`, else 1 | `densOn`, `sType`, `elev`, `temp`, `tStd`, `units` |
| `fullScale` | `fScale`, or if 0: `ceil(vOver · 1.15 / 10) · 10` | `fScale`, `vOver` |
| `fStall`, `fOver` | dial fractions of `vStall · kDens` and `vOver` over `fullScale` (FR-016a) | any of the above |
| `unitText`, `unitSpoken` | display "kt" / spoken "kt." etc. from the v2.1 list | `units` |
| threshold texts | e.g. "Stall 45" | thresholds, `units` |

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
| `everAboveLanding` | bool | false | Sensor speed has exceeded `vLand` this session |
| `belowLanding` | bool | false | Currently at/below `vLand` after being above |
| `everAboveHalf` | bool | false | Sensor speed has exceeded `vLand / 2` this session (FR-009 gate) |
| `aliveSaid` | bool | false | "Airspeed alive" has played |
| `stallArmed` | bool | true | Stall warning may fire |
| `overArmed` | bool | true | Overspeed warning may fire |
| `lastSpokenSpd` | int | 0 | Rounded value of the last callout |
| `lastSpokenAt` | int ms | 0 | `getTimeCounter()` at last callout |
| `lastTick` | int ms | now | Rate limiter for `loop()` (100 ms) |
| `curText`, `maxText` | string | "---", "0" | Cached number strings, rebuilt only when the rounded value changes |

## State transitions

Evaluated every 100 ms tick. "Valid" = sensor selected, reading non-nil and
`.valid`. An invalid reading sets `sensorSpd = shownSpd = nil` and changes
nothing else (Edge Cases): no callouts, no warnings, no max update.

```text
Warnings (a crossing fires only while a switch is on; re-arming is always tracked):

 stall:     armed --[everAboveLanding and sensorSpd <= vStall]--> fired (sound, vibrate 4)
            fired --[sensorSpd > vStall]--> armed
 overspeed: armed --[shownSpd > vOver]--> fired (sound, vibrate 3)
            fired --[shownSpd <= vOver]--> armed
 alive:     not said --[everAboveHalf]--> said (once per session)

Flight flags (whenever valid):
 sensorSpd > vLand / 2         -> everAboveHalf = true (latched)
 sensorSpd > vLand             -> everAboveLanding = true, belowLanding = false
 sensorSpd <= vLand and ever   -> belowLanding = true

Callout due when all hold:
 - a switch is on
 - not system.isPlayback()
 - now >= lastSpokenAt + interval   (R9)
 - continuous on, or everAboveHalf (FR-009)
 Short form (number only) if numOnly, belowLanding (or never above), or continuous.
```

A crossing while no switch is on does not fire and the warning stays armed,
as in v2.1, which returns early when both switches are off.
