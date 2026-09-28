# Quickstart: validating Speed Gauge

How to check that the built app meets the spec. The steps follow the
constitution's verification order. Claude can run steps 0 and 2; steps 1, 3
and 4 need a person at JETI Studio or the transmitter.

References: [data-model.md](data-model.md),
[contracts/](contracts/), [research.md](research.md).

## Prerequisites

- JETI Studio with the DS-24 II emulator. Its app folder is
  `%LOCALAPPDATA%\JETI-Studio\Emulator\Apps`.
- LeonAirRC's [Emulator Telemetry](https://github.com/LeonAirRC/Jeti-Lua-Apps)
  app, to supply simulated speed sensors. Load
  [`tools/emulator/sensors.json`](../../tools/emulator/sensors.json): "MSpeed
  450 / Velocity" on P5 (0–125 m/s, about 0–280 mph) and "GPS / Speed" on P6
  (0–83.3 m/s, about 0–186 mph). A control fully down means the sensor is
  lost.
- Optional: a Lua 5.3 interpreter on PATH for the module tests in step 0.

Deploy to the emulator (PowerShell, from the repo root):

```powershell
$dst = "$env:LOCALAPPDATA\JETI-Studio\Emulator\Apps"
Copy-Item src\Apps\AG-SpdGa.lua $dst
Copy-Item src\Apps\AG-SpdGa $dst -Recurse -Force
New-Item -ItemType Directory -Force "$dst\lib" | Out-Null
Copy-Item src\Apps\lib\ag_dens.lua, src\Apps\lib\ag_gauge.lua "$dst\lib"
```

## Step 0: static checks

```powershell
python tools/check.py        # must print 0 error(s)
lua tests/test_ag_dens.lua   # optional; prints the reference table, exits 1 on mismatch
```

LuaLS: no errors in the Problems panel for `src/Apps/**`.

## Step 1: confirm UNVERIFIED API assumptions (before gauge layout work)

| Check | How | Expected / action |
| --- | --- | --- |
| Window sizes (R7) | Done 2026-09-27 with `tools/probe/PROBE.lua`: 157 × 60, 157 × 127, 320 × 260 | Recorded in `docs/jeti-api-notes.md` |
| Size 0 window (R7) | Probe's size-0 mode: add "Probe auto" to the desktop | Record whether the pilot can pick single or double, and the size it reports. If not, use the `winSz` fallback |
| Device string (R12) | Probe console output "PROBE device: ..." in the emulator and, when possible, on the transmitter | Record both strings in `docs/jeti-api-notes.md`. The II's string must contain "24 II", or update the match |
| Font heights | Probe's "fonts N/B/M/Mx" line in the large and full-screen windows | Record them; the layouts fit text to these |
| Renderer reuse (R6) | Gauge running 5 min | No drawing glitches with one reused renderer |
| `°` renders | Open settings | Shown correctly, or switch to "deg" |

## Step 2: shared module values (SC-003)

`tests/test_ag_dens.lua` asserts the reference values in
[contracts/lib-modules.md](contracts/lib-modules.md). If no interpreter is
available, check the same values in the emulator's Lua console with
`require("ag_dens").factor(1524, 35)`.

## Step 3: emulator scenarios

Setup: add Speed Gauge in Applications → User Applications, open its
settings, select "MSpeed 450 / Velocity" (P5), and assign a switch for
callouts on/off. Use "GPS / Speed" (P6) for the GPS scenarios.
Defaults: mph, landing 60, stall 45, overspeed 200.

| # | Do | Expect | Spec |
| --- | --- | --- | --- |
| 1 | Speed 0, switch on | "Stall speed warning at 45 mph" at startup; silence after | FR-028, US1 #7 |
| 2 | Raise to 35 | "Airspeed alive" once | US2 #4 |
| 3 | Hold 100 steady | Callouts ~40 s apart (38–42) | SC-001 |
| 4 | Ramp so each callout differs by ~10 | ~20 s apart | SC-001 |
| 5 | Drop to 55 | Short callouts every 2 s (±0.5) | US1 #3, SC-001 |
| 6 | Drop to 44 | Stall warning once + vibration; no repeat while below | US2 #1 |
| 7 | Up to 50, down to 44 again | Stall fires again (re-armed) | US2 #1 |
| 8 | Up to 205 | Overspeed once + vibration | US2 #3 |
| 9 | Repeat crossings 10× each | Exactly one warning per crossing | SC-002 |
| 10 | Restart app, speed 40 without ever > 60 | No stall warning | US2 #2 |
| 11 | Both switches off | Silence; gauge still moves | US1 #5, FR-012 |
| 12 | Continuous switch on | Number every 2 s at any speed | US1 #4 |
| 13 | Set speed that takes > 2 s to speak repeatedly | No backlog; callouts wait | FR-007 |

Gauge (run each in the single, double and full-screen windows; compare with
`docs/vendor/gauge-reference.jpg`):

| # | Do | Expect | Spec |
| --- | --- | --- | --- |
| 13a | Place "Speed Gauge" single, then double; place the full-screen "Speed Gauge" (listed second) | Compact arc, round dial with corner rows, big dial with side panel | US3 #1, #2, #2a, FR-013 |
| 13b | Look at the double and full-screen dials | Dark face, numbered scale, red/orange zone from 200 to full scale, cyan arc, big center number with unit | FR-014, FR-014a |
| 13c | Density on at 5,000 ft, full screen | Side panel shows "+8%" and the sensor speed | contracts/telemetry-window.md |
| 14 | Speed 150, then 90 | Yellow max marker stays at 150; the cyan arc shrinks below it | US3 #3, FR-017 |
| 15 | Single sample spike to 400 (if the telemetry app can) | Max unchanged | Edge Cases, R5 |
| 16 | Speed 260 (full scale auto 230) | Arc stops at full scale; number shows 260 | US3 #7 |
| 17 | Move P5 fully down (sensor lost) | "---", max kept, no callouts or warnings | US3 #5 |
| 18 | Change colors in settings | Gauge uses them on next draw | US3 #4 |
| 19 | Reset max speed | Max clears, restarts from current | US3 #6 |
| 20 | Read dial only at several speeds | Within 5% of the number | SC-004 |
| 21 | Change speed, watch gauge | Updates within 0.5 s | SC-005 |
| 21a | Full-screen gauge for 5 min | CPU < 20% in Applications → User Applications; otherwise apply the R6 off-screen image fallback | SC-007 |
| 21b | Temporarily change the "24 II" match so it fails, reload | Window shows "Speed Gauge needs DS-24 II"; callouts and warnings still work | FR-013a |

Density (steady sensor 100 mph):

| # | Settings | Gauge / callout | Spec |
| --- | --- | --- | --- |
| 22 | Correction off | 100 | US4 #1 |
| 23 | On, 0 ft, standard temp | 100 | US4 #2 |
| 24 | On, 5,000 ft, standard | 108 (±1), settings show "+8%" | US4 #3, #6 |
| 25 | On, 5,000 ft, 95 °F (35 °C) | 113 (±1), "+13%" | US4 #4 |
| 26 | Sensor type GPS | 100, "Not used with GPS" | US4 #5 |
| 27 | 5,000 ft std, stall 40, slow down | Warning at sensor 40; gauge reads 43; value arc tip at the stall mark | SC-003a, FR-016a |

Settings and lifecycle:

| # | Do | Expect | Spec |
| --- | --- | --- | --- |
| 28 | Start with sensor off, open settings, start sensor, reopen | Sensor now listed | FR-002 |
| 29 | Select sensor, remove it, reopen settings | "<label> (not found)" selected | Edge Cases |
| 30 | Set stall 70 (> landing 60) | Order warning shown | FR-026 |
| 31 | Change mph → km/h | Speeds convert (60 → 97), elevation ft → m | Edge Cases, R10 |
| 32 | Switch models and back | Settings kept, max reset | FR-019, FR-024 |
| 33 | Install next to DFM-SpdA | Both run, settings separate | FR-027 |
| 34 | Settings footer | Version and DFM credit visible | FR-029 |
| 35 | Hand the settings to someone new | Sets up sensor, switch, landing, stall in < 3 min | SC-006 |

Resources: Applications → User Applications shows CPU < 20% with the gauge
displayed (SC-007). Print `collectgarbage("count")` in the emulator console
before and after 5 minutes of flight; it should level off, not climb.

## Step 4: transmitter

On a dedicated test model, never one that flies the same day: repeat 1–12,
14, 17 and 22–27 with a real pitot sensor on the bench (blow gently into
the pitot). Check that stick vibration is felt on the right stick and that
audio levels are clear over a running motor.
