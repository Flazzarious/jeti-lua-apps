# Contract: Settings form

One form, registered under the Applications menu as "Flameout Alarm"
(`system.registerForm(1, MENU_APPS, ...)` with a close callback). Keys and
ranges: [data-model.md](../data-model.md). Decisions: research R9, R10.

Rows, top to bottom (`hint` = one `FONT_MINI` line, shown only when stated):

| # | Row | Component | Behavior |
| --- | --- | --- | --- |
| 1 | **Flameout Alarm** | heading | |
| 2 | Monitoring | checkbox `en` | Refused unless sensor, Cut switch and idle RPM are set: box unticks and row 3 names what's missing (FR-003) |
| 3 | hint | label | "Needs: RPM sensor, Cut switch, idle RPM" (only the missing items); hidden when complete |
| 4 | **Engine** | heading | |
| 5 | RPM sensor | selectbox | "(none)" + every sensor except date/time and GPS, as "Device / Label"; a saved sensor that isn't present shows "<label> (not found)" (FR-022). Rebuilt each time the form opens |
| 6 | hint | label | No sensors at all: "No telemetry yet. The ECU must send RPM and the receiver must be on. Some adapters take up to a minute." (FR-004) |
| 7 | hint | label | Unit isn't `rpm`, `U/min` or `1/min`: "Unit is '<unit>', not RPM. Check the sensor, or set Sensor scale." (FR-010, R9) |
| 8 | Sensor scale | selectbox `scl` | "x1", "x10", "x100", "x1000" (FR-006a) |
| 9 | Live RPM | label | Scaled live value, e.g. "34,800", or "---"; updated from `loop()` while the form is open, every 500 ms (FR-010) |
| 10 | Idle RPM (x1000) | intbox `idle`, 1 decimal | 0.0–150.0; "0.0" means not set. Hint below: "From the ECU setup. Check against Live RPM at idle." |
| 11 | Max RPM (x1000) | intbox `maxR`, 1 decimal | 0.0–300.0; 0.0 = auto (4 × idle). Refused if > 0 and ≤ idle (snaps back, hint) |
| 12 | **Thresholds** | heading | |
| 13 | Arming at % of idle | intbox `armP` | 50–98; label shows "= 31.5k" |
| 14 | Flameout below % of idle | intbox `flP` | 20–95; label shows "= 24.5k". Refused if ≥ arming % (FR-007) |
| 15 | hint | label | Shown after a refused value: "Flameout must be below arming, and arming below idle." |
| 16 | Arming time (s) | intbox `armT`, 1 decimal | 1.0–10.0, step 0.5 |
| 17 | Detection delay (s) | intbox `detT`, 1 decimal | 0.3–5.0, step 0.1 |
| 18 | Telemetry loss after (s) | intbox `lossT`, 1 decimal | 0.5–10.0, step 0.5 |
| 19 | **Throttle cut** | heading | |
| 20 | Cut switch | inputbox `swCut`, non-proportional | Hint below: "Assign with the switch in the Cut (engine off) position." (FR-005, R10) |
| 21 | **Announcements** | heading | |
| 22 | Say "armed" | checkbox `sayArm` | FR-009 |
| 23 | Say "relit" | checkbox `sayRel` | FR-009 |
| 23a | Test alarm | inputbox `swTest`, non-proportional | Optional. Hint below: "Plays the alarm while on. Not while armed." (FR-030a, R13) |
| 24 | hint | label | "Voice files missing: alarm uses beeps." when `audioOk` is false (FR-029) |
| 25 | footer | label | "Flameout Alarm <version>. Advisory only; does not replace the ECU's failsafe." and "Voice: Piper, Amy (CC BY-SA 4.0)." |

Behavior:

- Every change saves at once with `system.pSave` and calls the recompute
  function (derived values in data-model.md), which may set `active` false
  and drop the app to OFF (alarm stopped).
- Turning monitoring on with something missing: the checkbox is set back to
  unticked with `form.setValue`, row 3 becomes visible. Removing the sensor,
  Cut switch or idle while enabled also turns `en` off and shows row 3.
- Refused values (rows 11, 14) are set back to the last good value with
  `form.setValue`, and row 15 (or the hint under row 11) shows.
- `formOpen` is set in the form's init and cleared in its close callback;
  `loop()` touches form components only while it's true.
- Labels avoid characters outside the supported charset (constitution V);
  "x" stands in for "×".
