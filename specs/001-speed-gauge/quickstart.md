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
  (0–83.3 m/s, about 0–186 mph), plus "MSpeed 450 / Temperature" on P7
  (−29–54 °C). A control fully down means the sensor is lost.
- Optional: a Lua 5.3 interpreter on PATH for the module tests in step 0.
- The app voice, generated locally (it isn't committed, FR-035). Follow
  `tools/voice/README.md` to install `piper-tts` and download
  `en_US-amy-medium`, then:

  ```powershell
  python tools/voice/make_voice.py --model <path>\en_US-amy-medium.onnx
  ```

  It writes 512 WAVs, `CREDITS.txt` and `index.txt` to
  `src/Apps/AG-SpdGa/voice/` and exits non-zero if a file is missing or a
  number-only file up to 199 is longer than 1.3 s (SC-009).

Deploy to the emulator (PowerShell, from the repo root):

```powershell
$dst = "$env:LOCALAPPDATA\JETI-Studio\Emulator\Apps"
Copy-Item src\Apps\AG-SpdGa.lua $dst
Copy-Item src\Apps\AG-SpdGa $dst -Recurse -Force   # includes voice\ if generated
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
| 22.05 kHz WAV plays (R13) | Transmitter only (the emulator plays no Lua audio), startup announcement on | Amy voice heard. If not, regenerate with `--rate 44100`, record it in `docs/jeti-api-notes.md`, and update FR-034 |
| Temperature unit string (R15) | Probe or console: print `unit` and its byte length for the MSpeed temperature in the emulator and, when possible, on the transmitter | Ends in "C", 2–3 bytes; else adjust the filter and record it |
| Start-up cost of the voice check (R14) | CPU figure after reload with the voice installed | Start-up figure still well below 100% (24% before the voice check) |

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
| 13c | Full screen: correction off, then on at 5,000 ft, then sensor type GPS | AIR DENSITY "OFF"; then "+8%" with ELEVATION 5000 ft and RAW SENSOR speed; then "GPS" | contracts/telemetry-window.md |
| 14 | Speed 150, then 90 | Yellow max marker stays at 150; the cyan arc shrinks below it | US3 #3, FR-017 |
| 15 | Single sample spike to 400 (if the telemetry app can) | Max unchanged | Edge Cases, R5 |
| 16 | Speed 260 (full scale auto 230) | Arc stops at full scale; number shows 260 | US3 #7 |
| 17 | Move P5 fully down (sensor lost) | "---", max kept, no callouts or warnings | US3 #5 |
| 18 | Change colors in settings | Gauge uses them on next draw | US3 #4 |
| 19 | Reset max speed | Max clears, restarts from current | US3 #6 |
| 20 | Read dial only at several speeds | Within 5% of the number | SC-004 |
| 21 | Change speed, watch gauge | Updates within 0.5 s | SC-005 |
| 21a | Full-screen gauge for 5 min | CPU figure in Applications → User Applications below 50% (it's the worst single call; emulator 2026-09-27: 43%) | SC-007 |
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

Temperature source (5,000 ft, correction on, steady sensor 100 mph; P7 is the
MSpeed temperature):

| # | Do | Expect | Spec |
| --- | --- | --- | --- |
| 36 | Temperature source list | Standard / Manual / Sensor; Standard by default; manual intbox enabled only for Manual, sensor list only for Sensor | FR-038 |
| 37 | Sensor list | Only "MSpeed 450 / Temperature" (not Velocity or GPS Speed) | FR-039 |
| 38 | Sensor, P7 at 35 °C (95 °F) | 113 (±1), same as Manual 95 °F; settings "Temp: 95 °F from MSpeed 450" (or °C) | US4 #7, FR-042 |
| 39 | Full screen, each source in turn | TEMP STD / TEMP MANUAL / TEMP SENSOR row with the temperature in use; no row with correction off | FR-044 |
| 40 | P7 fully down (lost) | Within 5 s: standard temperature, 108; "SENSOR OUT"; settings "Sensor not available - using standard"; callouts and warnings continue | US4 #8, FR-040 |
| 41 | P7 back to 35 °C | Sensor used again 10 s (±5) after the last bad read, without touching settings | FR-040 |
| 42 | Settings open during 40–41 | Status label changes live | FR-042, R17 |
| 43 | P7 at max (54 °C), then set sensors.json upper bound to 60 and P7 to 60 °C (140 °F) | 54: used. 60: "SENSOR OUT", standard used; back to 35 → resumes after 10 s | US4 #8a |
| 44 | Move P7 slowly by ±0.5 °C | Displayed speed doesn't change; it changes once the move reaches 1 °C | US4 #9, FR-041 |
| 45 | Change source or temperature while speed is steady | No extra callout caused by the change | FR-041 |
| 46 | Sensor type GPS with source Sensor | 100, no temperature read, no row | FR-043 |
| 47 | Pick the sensor, remove it from sensors.json, reopen settings | "<label> (not found)" selected; status "Sensor not available" | Edge Cases |

Voice (Emulator Telemetry prints each `playFile`/`playNumber` call, so the
console shows which set was used):

| # | Do | Expect | Spec |
| --- | --- | --- | --- |
| 48 | Voice installed, Voice "Speed Gauge"; run scenarios 1, 2, 3, 6, 8 | Console shows `.../voice/...` paths: "stallat", number, unit at startup; "alive"; number + unit callouts; "stall"; "over" | US6 #1, #2 |
| 49 | Speed 520 (full scale 600) | That callout uses `playNumber`, the next one under 500 uses files again | US6 #3, FR-033 |
| 50 | Delete `voice/85.wav`, hold 85 | Callout falls back to `playNumber` for 85 only; never "mph.wav" alone | Edge Cases |
| 51 | Remove `voice/`, reload | Settings show "Voice files missing"; Voice shows Transmitter; callouts use `playNumber`, warnings DFM's files; nothing silent | US6 #4, SC-010 |
| 52 | Voice "Transmitter" with files installed | Same as v2.1: `playNumber` and DFM's files | US6 #5 |

Limits and upgrade:

| # | Do | Expect | Spec |
| --- | --- | --- | --- |
| 53 | Elevation and manual temperature editors | Stop at −300 / 10,000 ft and −20 / 130 °F (−90 / 3,050 m, −29 / 54 °C) | FR-020 |
| 54 | With 0.1.0 installed: set elevation 15,000 ft, temperature standard off, 100 °F; install this version | Elevation shows 10,000 (clamped); source Manual, 100 °F | R16, Edge Cases |
| 55 | Change mph → km/h with manual 130 °F | Temperature converts to 54 °C | data-model.md |

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

Resources: Applications → User Applications shows the worst single call's
share of its budget; below 50% with every window shown (SC-007). For live
per-call numbers, log `system.getCPU()` at the end of `loop()` and the print
function (see `docs/jeti-api-notes.md`). Print `collectgarbage("count")` in the emulator console
before and after 5 minutes of flight; it should level off, not climb.

## Step 4: transmitter

On a dedicated test model, never one that flies the same day: repeat 1–12,
14, 17 and 22–27 with a real pitot sensor on the bench (blow gently into
the pitot). Check that stick vibration is felt on the right stick and that
audio levels are clear over a running motor.

With the app voice installed, also check by ear:

- Number and unit sound like one phrase, no audible pause (SC-009, under
  0.15 s); short callouts keep up with the 2-second interval.
- A stall or overspeed warning during a callout: note whether it cuts the
  callout off (R14) and that the warning is always heard.
- If the MSpeed is fitted, whether it reports a temperature (unconfirmed for
  the MSpeed 450 EX), and what it reads in the sun versus the shade.
