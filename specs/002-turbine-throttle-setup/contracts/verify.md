# Contract: Verify

Covers FR-013 to FR-019, User Story 2 and research R7/R8.

## Sequence

| k | State | Switch | Stick | Expected |
| --- | --- | --- | --- | --- |
| 0 | Output check | RUN | idle, then full | output rises by ≥ ½ (full − idle target) |
| 1 | Cut | CUT | idle | cut target |
| 2 | Cut overrides stick | CUT | full | cut target |
| 3 | Idle | RUN | idle | idle target |
| 4 | Full | RUN | full | full target |

Each prompt names the required position, e.g. "Switch CUT, stick at
FULL". The prompt line shows "Waiting...", "Hold steady..." or
"Measuring..." as the phase moves on.

## Position and steadiness (R8)

Constants (one table, tuned on the bench):

| Name | Value | Meaning |
| --- | --- | --- |
| `SW_BAND` | 0.5 | `getInputsVal(sw) * offSign ≥ 0.5` is CUT, `≤ −0.5` is RUN |
| `END_BAND` | 0.95 | `getInputsVal(stk) * idleSign ≥ 0.95` is idle end, `≤ −0.95` is full end |
| `STEADY_MS` | 500 | position held and steady this long before sampling |
| `STICK_JITTER` | 0.01 | max stick movement during steady window |
| `OUT_JITTER_US` | 2 | max output movement during steady window |
| `SAMPLE_N` | 10 | samples averaged |
| `SAMPLE_MS` | 50 | gap between samples, and the loop's work interval |

Losing the position during SETTLE or SAMPLE goes back to WAIT for the same
state. A stick in the middle shows "Move the stick fully to IDLE".

## Pass / fail (FR-014)

A state passes when |measured − expected| ≤ `tol`. The row shows target,
measured and PASS or FAIL, e.g. `Cut   1000  1002  PASS`.

## Diagnosis (FR-016)

Checked top to bottom for the failing state. `near(x, t)` means
|x − t| ≤ max(tol, 15). The text uses the transmitter's wording (FR-007).

| Fails at | Condition | Message |
| --- | --- | --- |
| Output check | output span < ½ (full − idle target) and near(output at idle, cut target) | "Switch RUN gave cut." / "Reverse the switch assignment." |
| Output check | output span < ½ (full − idle target) | "Output doesn't move with stick." / "Choose the throttle output." |
| Output check | output at full < output at idle | "Throttle reversed." / "Check Servo setup > Reverse." |
| Cut (1) | m > cut + tol | "Cut too high. Throttle Cut" / "Output value should be -100%." |
| Cut (1) | otherwise | "Cut low. Check Travel - (X%)" / "and Throttle Cut value (-100%)." |
| Cut overrides (2) | near(m, full target) | "Cut doesn't override stick." / "Check Throttle Cut switch." |
| Cut overrides (2) | otherwise | "Cut changes with stick." / "Check Throttle Cut settings." |
| Idle (3) | near(m, cut target) | "Switch RUN gave cut." / "Check Throttle Idle switch." |
| Idle (3) | otherwise | "Idle off by N us. Check Idle" / "offset (X%) and throttle trim." |
| Full (4) | otherwise | "Full off by N us. Check" / "Travel + (X%) and trim." |

X is the value from [settings-math.md](settings-math.md). N is
measured − expected, with a sign.

## Actions (F-keys on the verify screen)

| Phase | F1 | F3 | F5 |
| --- | --- | --- | --- |
| IDLE | Back | none | Start |
| running | Back (abandons run) | none | none |
| FAILED | Back | Retry | Restart |
| PASSED, clean | Back | none | Next (to Failsafe) |
| PASSED, retried | Back | none | Restart |

PASSED after a retry shows "All passed after a retry." / "Run all four
again to save." (clarification Q1).

## Standing lines (FR-018, FR-023)

Always visible at the top of the verify screen:

- "ENGINE MUST NOT BE ABLE TO START" / "(fuel off or ECU unplugged)"
- "Center throttle trim."
- "Checks the current flight mode only."

## Saving (FR-019, data-model)

A clean pass saves `meas`, `when` (today) and `res = 1`, then opens the
Failsafe screen. Failed or retried runs save nothing.

## Loop cost (constitution VI)

`loop()` returns at once unless the form is open. While verify runs,
work happens at most every `SAMPLE_MS` and is one `getInputs` plus one
`getInputsVal` call. Strings are rebuilt only when the shown value changes.
