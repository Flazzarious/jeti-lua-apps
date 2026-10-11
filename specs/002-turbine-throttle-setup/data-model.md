# Data Model: Turbine Throttle Setup

Everything is per model. Persisted values use `system.pSave`/`pLoad`
(integers, SwitchItems, one integer array; constitution IV). 12 keys.

## Setup (persisted)

| Key | Type | Default | Valid | Meaning |
| --- | --- | --- | --- | --- |
| `sw` | SwitchItem | nil | assigned | Safety switch (FR-001) |
| `offSg` | int | 0 | −1, 1 (0 = not learned) | Sign of `getInputsVal(sw)` in CUT (research R5); also shown as the CUT position, −100% or +100% |
| `stk` | SwitchItem | nil | assigned, proportional | Throttle stick (FR-002) |
| `idlSg` | int | 0 | −1, 1 (0 = not learned) | Sign of `getInputsVal(stk)` at idle end (R5) |
| `out` | int | 0 | 1–24 (0 = not chosen) | Throttle output `O<n>` (FR-002) |
| `ecu` | int | 0 | 1 Xicoy, 2 other (0 = not chosen) | ECU type (FR-003): sets the Throttle-Cut value and targets |
| `tol` | int µs | 10 | 5–25 | Verify tolerance (FR-004) |

Load clamps out-of-range values to defaults.

**Setup is complete** when `sw`, `stk`, `out` and `ecu` are set and `offSg`
and `idlSg` are learned. Guided setup and verify stay disabled until then.

### Targets (derived from `ecu`, never stored or typed)

| `ecu` | Throttle-Cut output value | Cut | Idle | Full |
| --- | --- | --- | --- | --- |
| 1 Xicoy | −125% | 1000 µs | 1200 µs | 1900 µs |
| 2 other | −100% | 1100 µs | 1200 µs | 1900 µs |

Max negative −80%, Max positive 80% and Throttle-Idle offset 20% are the
same for both ([settings-math.md](contracts/settings-math.md)).

## Wizard position (persisted, FR-009)

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `scr` | int | 1 | Screen to reopen: 1 Home, 2 Inputs, 3 Guide, 4 Verify, 5 Failsafe, 6 Summary, 7 Voice callouts |
| `gStep` | int | 1 | Guide step 1–5 |

Verify always reopens at its start screen: a half-finished run is never
resumed.

## Saved result (persisted)

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `res` | int | 0 | 0 Not verified, 1 Passed (failsafe not confirmed), 2 Setup complete |
| `meas` | int[4] | nil | Measured µs for Cut, Cut-overrides, Idle, Full from the clean run |
| `when` | int | 0 | Date `res` last became 1, as `yyyymmdd` from `system.getDateTime()` (shown as yyyy-mm-dd) |

Status text on Home and Summary:

| `res` | Text |
| --- | --- |
| 0 | "Not verified" |
| 1 | "Incomplete - failsafe not confirmed" |
| 2 | "Setup complete" |

(A plain hyphen, not an em dash: only the API's charset table renders.)

## Verify run (session only, never persisted)

| Field | Meaning |
| --- | --- |
| `phase` | IDLE, CHECK, WAIT, SETTLE, SAMPLE, FAILED, PASSED |
| `k` | Current state 0–4 (0 = output check) |
| `retried` | true once any state was retried in this run |
| `m[1..4]` | Measured µs per state, nil if not yet measured |
| `ok[1..4]` | Pass/fail per state |
| `why` | Diagnosis text for the failed state |
| `chkIdle`, `chkFull` | Output at each stick end during the output check |
| `t0` | `getTimeCounter()` when the current settle/sample began |
| `n`, `sum` | Sample count and running sum |
| `ref` | Output and stick values the steadiness window is measured against |

## Transitions

### Result

```text
             clean run, all 4 pass
  0 ───────────────────────────────▶ 1
  ▲                                  │ pilot confirms failsafe test
  │ any setup input change           ▼
  │ (after confirm, FR-005a)         2
  └──────────────── from 1 or 2 ─────┘
  1 or 2 ──── a new verify run that fails or isn't clean ───▶ unchanged
  1 or 2 ──── a new clean run passes ───▶ 1 (failsafe must be confirmed again)
```

- A new clean pass overwrites `meas` and `when` and sets `res = 1`. The
  failsafe confirmation applies to the run it follows (FR-019).
- Declining the failsafe confirmation leaves `res = 1`.
- A failed or retried run never lowers a saved result. It just isn't
  saved. The saved result still describes the setup as it was last
  verified, and any setup change clears it.

### Verify run

```text
IDLE ─Start─▶ CHECK(k=0) ─pass─▶ WAIT(k=1)
WAIT ─switch+stick in position─▶ SETTLE ─steady 500 ms─▶ SAMPLE
SAMPLE ─10 samples─▶ (in tolerance) ─▶ WAIT(k+1), or PASSED after k=4
                     (out of tolerance) ─▶ FAILED
SETTLE/SAMPLE ─position lost─▶ WAIT (same k)
FAILED ─Retry─▶ WAIT(same k), retried = true
FAILED/PASSED ─Restart─▶ CHECK(k=0), retried = false, m/ok cleared
PASSED, retried = false ─▶ "Clean run" ─▶ Failsafe screen
PASSED, retried = true ─▶ "Run all four again for a clean run"
```

After a retry passes, the run continues with the following states. A run
with `retried = true` can reach PASSED but is never saved.
