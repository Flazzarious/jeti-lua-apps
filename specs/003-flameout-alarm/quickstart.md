# Quickstart: validating Flameout Alarm

How to prove the app meets the spec, from static checks to a real engine.
Behavior details are in [data-model.md](data-model.md) and the
[contracts](contracts/); this guide says what to run and what to expect.

## Prerequisites

- `python tools/check.py` and LuaLS (VS Code) set up as for Speed Gauge.
- JETI Studio with the DS-24 II emulator (firmware 6.04). App folder:
  `%LOCALAPPDATA%\JETI-Studio\Emulator\Apps`.
- LeonAirRC's Emulated Telemetry app installed there, with
  `tools/emulator/sensors.json` copied to `Apps/EmulatedTelemetry/` after
  adding the "Turbine" RPM sensor (research R12).
- For sound and the window's real proportions: the DS-24 II, a test model,
  and the generated sounds (`python tools/voice/make_flameout.py --model
  <path>\en_US-amy-medium.onnx`).

## Deploy

```powershell
$dst = "$env:LOCALAPPDATA\JETI-Studio\Emulator\Apps"   # or the SD card's \Apps
Copy-Item src\Apps\AG-FlmOt.lua $dst
Copy-Item src\Apps\AG-FlmOt $dst -Recurse -Force
```

No lib modules: the install is just these two items (FR-033, SC-007).

## 1. Static checks

| Check | Expect |
| --- | --- |
| `python tools/check.py` | 0 errors |
| LuaLS diagnostics on `AG-FlmOt.lua` | no errors |
| `python tools/voice/make_flameout.py ...` | self-check passes: 5 WAVs, both cycle files exactly 5.000 s |
| Search the app for `registerControl`, `setControl`, `setProperty` | none (SC-006) |

## 2. Emulator scenarios

Add the app and Emulated Telemetry in Applications → User Applications.
Place the app's window at double size, then repeat the display checks at
single size. Audio and vibration show as console lines.

| # | Scenario | Steps | Expect | Spec |
| --- | --- | --- | --- | --- |
| 1 | Default off | Fresh model, add app | Window shows OFF; no console audio lines in any scenario below until enabled | FR-001, SC-009 |
| 2 | Enable blocked | Tick Monitoring with nothing set | Box unticks; hint lists sensor, Cut switch, idle | FR-003 |
| 3 | No sensors | Emulated Telemetry not running, open settings | "No telemetry yet..." hint | FR-004 |
| 4 | Setup | Pick Turbine / RPM, Cut switch, idle 35.0; enable | Live RPM follows the slider; thresholds read 31.5k / 24.5k; under 3 minutes | FR-002–FR-010, SC-005 |
| 5 | Threshold rules | Set flameout 92% with arming 90%; max RPM 30.0 | Both refused with hint | FR-007, FR-031b |
| 6 | Arm | Slider above 31,500 for 3 s, Cut off | DISARMED → ARMED | FR-014 |
| 7 | Chop | Armed; slider to 30,000 | No alarm | US2 |
| 8 | Glitch | Armed; slider below 24,500 for under 1 s | No alarm | FR-015 |
| 9 | Flameout | Armed; slider to 0 and hold | Alarm within 1.5 s: `cycle.wav` immediate + vibration lines, then every 5 s; FLAMEOUT banner | FR-015, FR-023, SC-001, SC-012 |
| 10 | Restart wobble | In alarm; slider 10,000–30,000 up and down | Alarm continues, no new event | FR-017, SC-011 |
| 11 | Relight | In alarm; slider above 31,500 for 3 s | Stop line, ARMED within 3.5 s | FR-018, SC-011 |
| 12 | Cut | In alarm; flip Cut | Stop line at once; DISARMED; slider low: silent | FR-016, US5 |
| 13 | Loss while armed | Armed; slider fully down (invalid) | After 2 s: `tlost.wav` line, NO TELEMETRY; never `cycle.wav` | FR-020, SC-004 |
| 14 | Loss in alarm | In alarm; slider fully down | Alarm continues; next cycle `cycletl.wav` once; "NO TELEMETRY" under the number | FR-020a |
| 15 | Return | Armed, lost; slider back above 31,500 | ARMED, no alarm | FR-021 |
| 16 | Sensor gone | Remove the Turbine sensor from sensors.json, restart | NO SENSOR; settings show "(not found)" | FR-022 |
| 17 | Per model | Enable on model A; load model B; restart emulator | B is OFF; A keeps its settings | FR-011, SC-010 |
| 18 | Missing voice | Rename `cycle.wav`, restart | Settings: "Voice files missing"; alarm uses `playBeep` lines | FR-029 |
| 19 | Display | Step through every state at double and single size | Matches the [window contract](contracts/telemetry-window.md); nothing clipped; bar reaches the idle marker at 35,000 | FR-031, SC-013 |
| 19a | Test alarm | Assign a test switch; monitoring off; switch on 12 s, then off | `cycle.wav` and vibration lines at 0, 5 and 10 s, window TEST; stop line when switched off. Armed: switch does nothing. Switch on at model load: nothing until toggled | FR-030a |
| 20 | Simulated profiles | `SIM` on; run each profile | Normal flight: zero alarms (SC-002, SC-003); flameout and restart profiles as in 9–11 | R12 |
| 21 | CPU | `DEBUG_CPU` on; 30 minutes incl. an alarm | No CPU limit errors; note the worst draw figure | SC-008 |

## 3. Transmitter (test model, engine not running)

| # | Check | Expect |
| --- | --- | --- |
| 22 | Window | Screenshot (`Screen00n.png`) at double and single size matches the mockup's proportions |
| 23 | Alarm sound | Hold the test alarm switch (no engine, no sensor needed): callout then lock tone, no gap, new callout every 5 s; urgent and clear over background noise; vibration on both sticks |
| 24 | Pre-emption | Run Speed Gauge too; trigger while it speaks: alarm cuts in. Trigger its stall warning during the alarm: alarm resumes at the next cycle |
| 25 | Stop | Relight and Cut mid-callout and mid-beep: silence at once |
| 26 | Fallback beeps | Remove the cycle files: beeps are clearly an alarm; note the gap between repeats |
| 27 | Loss timing | Switch the receiver off while armed: note seconds until "Engine telemetry lost" (firmware timeout + setting) |
| 28 | Install | Copy only `AG-FlmOt.lua` and `AG-FlmOt/` to a card with no other AG- apps: loads and runs | SC-007 |

## 4. Real engine (bench, test model; never a model flying that day)

With the ECU's telemetry converter connected: check the sensor's label and
unit, set idle from the ECU setup and compare with Live RPM at idle.
Run a normal start: confirm the overshoot and decay never drop below the
arming threshold and no alarm sounds (SC-002). Shut down with Cut: silent.
Record a Jeti log of a start and a shutdown to refine the defaults (spec
Assumptions) and the simulated profiles.
