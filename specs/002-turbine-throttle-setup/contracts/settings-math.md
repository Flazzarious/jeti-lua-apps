# Contract: Targets → settings, validation and µs conversion

One function computes the settings, one validates, and one converts readings.
Each is the only place its rule lives, so a calibration result (research
R1, R2) changes a single constant or line.

## µs conversion (R1, CALIBRATE)

```text
us(v) = 1500 + 500 * v          -- v from system.getInputs("O<n>"), −1..1
```

Constants: `US_CENTER = 1500`, `US_PER_UNIT = 500`.

## Settings for the guide (FR-006, R2; confirmed on two models)

Input: valid targets `cut`, `idle`, `full` (µs, multiples of 5).

| Output | Formula | Defaults 1000 / 1200 / 1900 → |
| --- | --- | --- |
| `travelLo` | (1500 − cut) / 5 | 100 |
| `travelHi` | (full − 1500) / 5 | 80 |
| `cutValue` | −100 | −100 |
| `idleOffset` | (idle − cut) / 5 | 40 |

Constant: `US_PER_PCT = 5`. All results are integers because targets are
multiples of 5.

When `travelLo == travelHi` the guide shows one line, "Travel: +/-80%".
Otherwise it shows two lines, "Travel -: 80%" and "Travel +: 100%"
(clarification Q2).

## Validation (FR-003, clarification Q3)

Rules are checked in this order. The first one that fails gives the
message, which shows under the target fields:

| # | Rule | Message (≤ 32 chars per line) |
| --- | --- | --- |
| 1 | 900 ≤ cut, idle, full ≤ 2100 | "Targets must be 900-2100 us" |
| 2 | cut < 1500 < full | "Cut must be below 1500 us" / "Full must be above 1500 us" |
| 3 | cut < idle < full | "Need cut < idle < full" |
| 4 | 10·(idle − cut) ≥ (full − cut) | "Idle too close to cut:" / "ECU may not tell run from stop" |
| 5 | 10·(idle − cut) ≤ 3·(full − cut) | "Idle too high: over 30%" / "of the cut-full range" |

If all pass and `100·(idle − cut) < 15·(full − cut)`, show the warning
"Idle at 12.5% of range." / "Some ECUs (e.g. Xicoy) want 15%+" (the
percentage computed to one decimal).

"us" stands in for "µs" until `µ` is confirmed in the charset (quickstart
section 3). The guide switches to `µs` if it renders.

The idle position shows live as "Idle position: 22.2%".

## Test vectors (for SC-006 and SC-010)

| cut | idle | full | Result | Settings |
| --- | --- | --- | --- | --- |
| 1000 | 1200 | 1900 | valid, no warning (22.2%; **defaults**, Aaron's Avanti) | −100% / +80%, −100%, 40% |
| 1100 | 1200 | 1900 | valid + warning (12.5%; Aaron's older setup) | ±80%, −100%, 20% |
| 1000 | 1150 | 2000 | valid, no warning (15.0%) | ±100%, −100%, 30% |
| 1100 | 1250 | 2000 | valid (16.7%) | −80% / +100%, −100%, 30% |
| 1100 | 1180 | 1900 | valid + warning (10.0%, boundary) | ±80%, −100%, 16% |
| 1100 | 1175 | 1900 | refused rule 4 (9.4%) | none |
| 1100 | 1340 | 1900 | valid (30.0%, boundary) | ±80%, −100%, 48% |
| 1100 | 1345 | 1900 | refused rule 5 (30.6%) | none |
| 1100 | 1220 | 1900 | valid, no warning (15.0%, boundary) | ±80%, −100%, 24% |
| 1100 | 1215 | 1900 | valid + warning (14.4%) | ±80%, −100%, 23% |
| 1500 | 1600 | 1900 | refused rule 2 | none |
| 850 | 1000 | 1900 | refused rule 1 | none |

Targets move in 5 µs steps, so SC-010's 9.9% / 14.9% / 30.1% examples
can't be entered exactly. The nearest enterable values on each side of
every boundary are listed above.
