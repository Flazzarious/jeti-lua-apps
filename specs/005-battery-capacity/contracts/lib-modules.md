# Contract: Shared module `ag_peak`

`src/Apps/lib/ag_peak.lua`, loaded with `local peak = require("ag_peak")`.
Speed Gauge's spike-filtered session max (its research R5), as a stateless
module (constitution VII). Decision: research R7.

## Functions

```lua
peak.new() -> st
-- st = { max = 0, prev = nil, prevT = 0 }; the caller owns it.

peak.update(st, value, nowMs) -> max, rose
-- value: number (nil or invalid readings are not passed in)
-- A value counts towards the max when:
--   it differs from st.prev: candidate = math.min(st.prev, value)   (two distinct readings)
--   it equals st.prev and nowMs - st.prevT >= HOLD_MS (1000): candidate = value
-- st.max = math.max(st.max, candidate); rose = true when st.max increased.
-- st.prev / st.prevT updated when the value changes.

peak.reset(st)
-- st.max = 0, st.prev = nil, st.prevT = 0
```

## Rules

- No module-level mutable state; `HOLD_MS` is a constant.
- No `lcd`, `form`, `system` calls; time is passed in.
- A single-sample spike never raises the max; a steady value registers
  after 1 s (spec SC-010).

## Users

| App | Uses it | Note |
| --- | --- | --- |
| Battery Capacity (`AG-BatCp`) | yes, from 0.1.0 | per battery |
| Speed Gauge (`AG-SpdGa`) | no | keeps its own copy; migrating is a separate change that must re-verify Speed Gauge |

Because no released app uses the module yet, adding it needs no
re-verification of other apps. It must be listed in Battery Capacity's
install instructions and release package (FR-037).
