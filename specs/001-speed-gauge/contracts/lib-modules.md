# Contract: Shared modules

Both modules are new; Speed Gauge is their only user. Per constitution VII
they return a table of functions, hold no mutable module-level state, register
nothing, and follow principles II–VI. Constant lookup tables are allowed.
Any later change must list and re-verify every app that `require`s them.

## `ag_dens` (`src/Apps/lib/ag_dens.lua`)

Pure math. Safe to call anywhere; the app calls it only from `init()` and
form callbacks.

| Function | Returns | Notes |
| --- | --- | --- |
| `factor(elevM, tempC)` | number k ≥ ~0.9 | True airspeed = sensor speed · k. `tempC` nil → standard temperature. Formula in research R1 |
| `stdTempC(elevM)` | number °C | 15 − 0.0065 · elevM |
| `ftToM(ft)` / `mToFt(m)` | number | 0.3048 |
| `fToC(f)` / `cToF(c)` | number | |

Reference values (must hold within 0.001): `factor(0, nil)` = 1.0000,
`factor(1524, nil)` = 1.0773, `factor(1524, 35)` = 1.1337,
`factor(4572, 50)` = 1.4097.

## `ag_gauge` (`src/Apps/lib/ag_gauge.lua`)

Drawing helpers. The draw functions use `lcd` and must only be called from a
registered print function.

| Function | Returns / effect |
| --- | --- |
| `newDial(steps, startDeg, sweepDeg)` | Table `{n, cx[], sy[]}` of unit cos/sin for `steps + 1` points; defaults 54, 225, 270. Owned by the caller. Call once in `init()` |
| `arc(r, dial, cx, cy, radius, f, width)` | Draws an arc from 0 to fraction `f` (clamped 0..1) with renderer `r` (reset first). Nothing drawn if `f <= 0` |
| `tick(dial, cx, cy, r1, r2, f)` | Radial line at fraction `f` between radii `r1` and `r2` |
| `needle(dial, cx, cy, radius, f)` | Line from center to `f` at `radius` |
| `point(dial, f)` | `cos, sin` at fraction `f`, interpolated. Used by the others; public for labels |

Colors are set by the caller with `lcd.setColor` before each call. The
renderer `r` comes from the caller (`lcd.renderer()`), so reuse is the app's
decision (research R6).
