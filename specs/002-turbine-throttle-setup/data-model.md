# Data Model: Turbine Throttle Setup

Everything is per model. Persisted values use `system.pSave`/`pLoad`
(integers, SwitchItems, one integer array; constitution IV). 14 keys.

## Setup (persisted)

| Key | Type | Default | Valid | Meaning |
| --- | --- | --- | --- | --- |
| `sw` | SwitchItem | nil | assigned | Safety switch (FR-001) |
| `offSg` | int | 0 | −1, 1 (0 = not learned) | Sign of `getInputsVal(sw)` in CUT (research R5); also shown as the CUT position, −100% or +100% |
| `stk` | SwitchItem | nil | assigned, proportional | Throttle stick (FR-002) |
| `idlSg` | int | 0 | −1, 1 (0 = not learned) | Sign of `getInputsVal(stk)` at idle end (R5) |
| `out` | int | 0 | 1–24 (0 = not chosen) | Throttle output `O<n>` (FR-002) |
| `tCut` | int µs | 1000 | see Validation | Cut target |
| `tIdle` | int µs | 1200 | see Validation | Idle target |
| `tFull` | int µs | 1900 | see Validation | Full target |
| `tol` | int µs | 10 | 5–25 | Verify tolerance (FR-004) |

Load clamps out-of-range values to defaults. If the loaded targets fail
validation, all three go back to defaults.

**Setup is complete** when `sw`, `stk`, `out` are set, `offSg` and `idlSg`
are learned, and the targets are valid. Guided setup and verify stay
disabled until then.

### Validation (FR-003, clarification Q3, research R2)

Targets are edited in 5 µs steps. Valid when all hold:

1. 900 ≤ each ≤ 2100 (narrowed to 1000–2000 if research R1 finds the
   reading clips at ±1).
2. cut < 1500 < full ("settings outside what the transmitter allows").
3. cut < idle < full.
4. Idle position p = (idle − cut) ÷ (full − cut) with 0.10 ≤ p ≤ 0.30.

Computed with integers: `10 * (idle − cut)` compared with
`full − cut` and `3 * (full − cut)`, so there are no float edge cases at
exactly 10% or 30%. **Warning** (not a refusal) when
`100 * (idle − cut) < 15 * (full − cut)`. The first failing rule gives the
message ([settings-math.md](contracts/settings-math.md)).

Invalid targets are not saved. The last valid set stays in `pSave`, and
guided setup and verify are disabled until the targets are fixed.

## Wizard position (persisted, FR-009)

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `scr` | int | 1 | Screen to reopen: 1 Home, 2 Inputs, 3 Guide, 4 Verify, 5 Failsafe, 6 Summary |
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
