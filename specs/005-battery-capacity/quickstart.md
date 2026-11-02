# Quickstart: validating Battery Capacity

How to prove the app meets the spec, from static checks to real packs.
Behaviour details are in [data-model.md](data-model.md) and the
[contracts](contracts/); this guide says what to run and what to expect.

## Prerequisites

- `python tools/check.py` and LuaLS (VS Code) set up as for the other apps.
- JETI Studio with the DS-24 II emulator (firmware 6.04). App folder:
  `%LOCALAPPDATA%\JETI-Studio\Emulator\Apps`.
- LeonAirRC's Emulated Telemetry app, with `tools/emulator/sensors.json`
  (MUI 75, Rx and Central Box sensors added, research R13) copied to
  `Apps/EmulatedTelemetry/`.
- Voice files generated: `python tools/voice/make_batcap.py --model
  C:\Users\aaron\piper-voices\en_US-amy-medium.onnx`.
- For sound, layout and real packs: the DS-24 II, a test model, a receiver
  with voltage telemetry, ideally a MUI or Central Box, and a LiPo and a
  LiFe pack with a charger that reports state of charge.

## Deploy

```powershell
$dst = "$env:LOCALAPPDATA\JETI-Studio\Emulator\Apps"   # or the SD card's \Apps
Copy-Item src\Apps\AG-BatCp.lua $dst
Copy-Item src\Apps\AG-BatCp $dst -Recurse -Force
New-Item -ItemType Directory -Force "$dst\lib" | Out-Null
Copy-Item src\Apps\lib\ag_peak.lua "$dst\lib"
```

That's the whole install (FR-037, SC-017).

## 1. Static checks

| Check | Expect |
| --- | --- |
| `python tools/check.py` | 0 errors |
| LuaLS diagnostics on `AG-BatCp.lua` and `lib/ag_peak.lua` | no errors |
| `make_batcap.py` self-check | 518 files; numbers byte-identical to Speed Gauge's; word files under 1.3 s |
| Search for `registerControl`, `setControl`, `setProperty`, `os.`, `debug.`, `coroutine`, `bit32` | none (FR-036, SC-016) |
| `SIM` and `DEBUG_CPU` constants | false in the committed file |

## 2. Emulator scenarios

Add Battery Capacity and Emulated Telemetry in Applications → User
Applications; place window 1 (small) and window 2 (double) on a desktop
page. Callouts appear as console lines.

| # | Setup | Action | Expect |
| --- | --- | --- | --- |
| E1 | Battery 1: Receiver, LiFe 2S, 2500 mAh, capacity = MUI Capacity (P3) | P3 to 1000 mAh, then 1050 | 60% green (yellow is *below* 60), then 58% yellow; fill at that % of the length (US1 #1, SC-003) |
| E2 | Battery 2: Aux on Central Box % (P9) | move P9 | gauge shows the sensor value as is (US1 #2) |
| E3 | Battery 3: Receiver on Rx U Rx (P4), voltage source | move P4 slowly | % follows the LiFe curve, smoothed; no jumps from small moves (US1 #3) |
| E4 | Battery 1 | change chemistry after editing a band | asked before overwriting; unedited values refill (US1 #4–5, SC-002) |
| E5 | any | P3/P4/P9 fully down | grey, "NO TELEM", no console speech (FR-015) |
| E6 | Battery 1 default levels | raise mAh through 30% | "n_rx · 30 · pct" once, then every 5 s; with max repeats 3: three lines total (US2 #1–2, SC-007) |
| E7 | Battery 1, levels 60/50/40/30 on | start the sensor at 35% | only "40" (US2 #4); jitter ±2 around 40: no repeat until above 45 (US2 #5) |
| E8 | 4 batteries, both windows, `DEBUG_CPU` | 5 minutes | print and loop figures logged; under 10% per call; no CPU errors (SC-014 short form) |
| E9 | 1, 2, 3, 4 batteries | delete battery 2 | others shift left in order; unused slots blank (US3 #1–2) |
| E10 | Battery 1 with MUI Voltage (P1), LiPo 2S, per cell | P1 below 7.20 V for 2 s / for 1 s | alarm + red flashing outline in both windows / nothing (US2 #6, #8, SC-008) |
| E11 | Battery 1 with MUI Current (P2), alarm 80 A / 1 s / 10 s | hold P2 at 85 A | "high current 85 amps" after 1 s, again every 10 s (US4 #2, SC-009) |
| E12 | Flight pack on MUI Current | `SIM` spike profile | single-sample spike never becomes max; "max 92 amps" 1 s after the peak (US4 #3–4, SC-010) |
| E13 | `SIM` dropout profiles | +30 points / no jump | new pack: max reset, levels re-armed, "pack not full" check after 3 s when on; brown-out: all held (FR-028, US5) |
| E14 | two low batteries + current alarm at once | | order: low voltage, high current, levels; battery 1 before 2 (FR-034a) |
| E15 | Voice = Transmitter, voice-name file set | trigger a level | console: the name file, then `playNumber(30, 0, "%")` (FR-033) |
| E16 | restart emulator; switch model | | settings kept per model, not on the other model (SC-015) |
| E17 | Custom "WWWWWWWW" | confirm | trimmed, "Shortened to fit"; label fits its slot (R6, SC-013) |

## 3. Transmitter checks (manual, reported by Aaron)

| # | Check | Expect / record |
| --- | --- | --- |
| T1 | Sensor units of Aaron's MUI, Central Box, Rx, ESC, Powerbox | units match research R1; record in `docs/jeti-api-notes.md` |
| T2 | Probe `FONT_MINI` widths (A–Z, 0–9, "-") | fill `MINI_W`; check every default label fits (R6) |
| T3 | Callouts in the app voice and the transmitter voice | one continuous phrase; `playNumber` waits behind the name file (R9); no cut-offs |
| T4 | Layout screenshots (`Screen00n.png`), light and dark theme | small window two text lines don't overlap; % readable on every band incl. white on orange; outlines visible on both themes (SC-005, FR-012a) |
| T5 | Swap a pack; pull the receiver plug for < 1 s | new pack detected / brown-out held (R4) |
| T6 | Flameout Alarm also installed | Flameout's alarm plays first; this app waits (FR-034) |
| T7 | 30 minutes, 4 batteries, both windows | no CPU-limit error (SC-014) |
| T8 | Copy only the app, its folder and `lib/ag_peak.lua` to a card without other AG- apps | loads and runs (SC-017) |

## 4. Bench (manual)

| # | Check | Expect |
| --- | --- | --- |
| B1 | LiPo and LiFe packs at rest at several charge states, voltage source | gauge within ±10% of the charger's state (SC-004; LiFe mid-range expected coarse) |
| B2 | A fresh LiFe pack with the new-pack check on | no "pack not full" (R3 resting top) |
