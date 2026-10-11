# Contract: Recommended settings, targets and µs conversion

The app recommends one fixed set of values. Only the Throttle-Cut output
value depends on the ECU type (spec FR-003, FR-006; clarification
2026-10-10). Pilots never type targets.

## Recommended settings

| Setting (transmitter wording) | Xicoy | Any other ECU |
| --- | --- | --- |
| Servo Setup → Max negative | −80% | −80% |
| Servo Setup → Max positive | 80% | 80% |
| Other Model Options → Throttle-Cut output value | **−125%** | **−100%** |
| Other Model Options → Throttle-Idle offset | 20% | 20% |

Constants in the app: `MAX_NEG = -80`, `MAX_POS = 80`, `IDLE_OFS = 20`,
and `CUT_VAL = { [1] = -125, [2] = -100 }` indexed by `ecu`.

## Targets verify expects

Derived from the settings with the rules confirmed on four models
(research R1, R2): 5 µs per percent, Throttle-Cut value scaled by travel,
idle offset added to the stick's low end.

| | Formula | Xicoy | Other |
| --- | --- | --- | --- |
| Cut | 1500 + 5 × cut value × 80 / 100 | 1000 µs | 1100 µs |
| Idle | 1500 − 5 × 80 + 5 × 20 | 1200 µs | 1200 µs |
| Full | 1500 + 5 × 80 | 1900 µs | 1900 µs |

The app stores them as a table `TARGETS = { [1] = { 1000, 1200, 1900 },
[2] = { 1100, 1200, 1900 } }` (checked against these formulas when the
table is written, not computed at run time).

## µs conversion (R1, confirmed)

```text
us(v) = 1500 + 500 * v          -- v from system.getInputs("O<n>"), −1..1
```

Constants: `US_CENTER = 1500`, `US_PER_UNIT = 500`.

## Measured on Aaron's models (servo monitor or the app)

| Model | ECU | Settings | Read | Expected |
| --- | --- | --- | --- | --- |
| Flash Ultra EVO | Swiwin | −80/80, −100%, 20% | 1100 / 1100 / 1200 / 1900 | other ✓ |
| Avanti Mini | Xicoy | −80/80, −125%, 20% | 1000 / 1000 / 1200 / 1900 | Xicoy ✓ |
| Test model | — | −80/80, −100%, 20% | 1100 / 1200 / 1900 | other ✓ |

(Order: cut with stick down / cut with stick up / idle / full.)
