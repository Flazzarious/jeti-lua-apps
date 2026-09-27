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
| `newDial(steps, startDeg, sweepDeg)` | Table `{n, cx[], sy[]}` of unit cos/sin for `steps + 1` points, clockwise from `startDeg` (screen y points down). Defaults 54, 225, 270; the compact dial uses 36, 180, 180. Owned by the caller. Call once in `init()` |
| `newCircle(points)` | Same table shape for a closed unit circle (default 72 points), for the face polygon. Call once in `init()` |
| `point(dial, f)` | `cos, sin` at fraction `f` (clamped 0..1), interpolated. Pure; also used by the app's layout cache for label positions |
| `scaleStep(fullScale)` | Major tick step: the smallest of 10, 20, 25, 50, 100, 200, 250, 500 giving at most 8 intervals up to `fullScale` (research R6). Pure |
| `face(r, circle, cx, cy, radius)` | Filled polygon of the unit circle scaled to `radius`, via `r:renderPolygon()` |
| `arc(r, dial, cx, cy, radius, f0, f1, width)` | Arc from fraction `f0` to `f1` (both clamped 0..1) with renderer `r` (reset first): the interpolated start point, the table points between, the interpolated end point, then `r:renderPolyline(width)`. Nothing drawn if `f1 <= f0` |
| `mark(r, dial, cx, cy, r1, r2, f, width)` | Anti-aliased radial line at `f` between radii `r1` and `r2`, via the renderer. For the max marker and the value-arc tip |
| `tick(dial, cx, cy, r1, r2, f)` | Radial `lcd.drawLine` at `f`. Cheaper than `mark`; for scale ticks and stall/landing marks |

Colors are set by the caller with `lcd.setColor` before each call. The
renderer `r` comes from the caller (`lcd.renderer()`), so reuse is the app's
decision (research R6). Pure functions (`newDial`, `newCircle`, `point`,
`scaleStep`) may also be called outside print functions.
