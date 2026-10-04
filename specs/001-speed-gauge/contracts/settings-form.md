# Contract: Settings form

Registered as `system.registerForm(1, MENU_APPS, "Speed Gauge", initForm,
keyForm)`. One form, no subforms except a `form.reinit()` redraw after a
units change. Rows appear in this order (FR-025, US5 #1). Label width 180–220
px as in v2.1; hints are `FONT_MINI` rows.

| # | Row | Component | Notes |
| --- | --- | --- | --- |
| | **Sensor and switches** | label, `FONT_BOLD` | |
| 1 | Speed sensor | selectbox (dialog) | "(none)", sensors, optional "<label> (not found)" (R4) |
| 3 | Sensor type | selectbox | Airspeed (pitot) / GPS; with GPS a hint row reads "GPS: warnings use ground speed, wind shifts them" (spec Assumptions) |
| 4 | Units | selectbox | mph, km/h, kt, m/s, ft/s; converts settings (R10) |
| 5 | Sensor calibration (%) | intbox 1–200 | hint "100 = unchanged" |
| 6 | Callouts on/off switch | inputbox | proportional allowed. Hints (2026-10-03): "Speaks speed: more often as it changes, every" / "shortest time below landing speed" |
| 7 | Continuous callouts switch | inputbox | Hints: "Number only, every shortest time, while above" / "'Callouts start above'; works without on/off" / "Either switch also turns on the warnings" (FR-009a, 2026-10-03) |
| | **Callouts** | | |
| 8 | Callout sensitivity (*unit*) | intbox 1–100 | |
| 9 | *hint* | label | "Speak sooner when speed changes by this much" |
| 10 | Shortest time between callouts (s) | intbox 1–10 | |
| 11 | Longest time between callouts (s) | intbox 10–60 | |
| 11a | Callouts start above (*unit*) | intbox 0–1000, default 30 | FR-009, added 2026-10-03; saves `vArm` |
| 11b | *hint* | label | "No callouts or 'airspeed alive' until first this fast" |
| 11c | Landing speed callouts | checkbox, default on | FR-006, added 2026-10-03; saves `landOn` |
| 12 | Landing speed (*unit*) | intbox 0–1000 | Also arms the stall warning (FR-011) |
| 13 | *hint* | label | "If on: short callouts every shortest time below" / "this. Also arms the stall warning once exceeded" |
| 14 | Speak number only (no units) | checkbox | |
| 15 | Announce stall speed at startup | checkbox | FR-028 |
| 15a | Voice | selectbox Speed Gauge / Transmitter | FR-032. Shows the resolved choice for `voice = 0` (research R14). Saves 1 or 2 |
| 15b | *hint* | label | "Voice files missing - using transmitter voice", shown only while `voiceOk` is false (FR-033, US6 #4) |
| | **Warnings** | | |
| 16 | *order warning* | label, hidden unless illogical | "Check: stall < landing < overspeed < full scale" (FR-026) |
| 17 | Stall warning at (*unit*) | intbox 0–1000 | |
| 18 | Overspeed warning at (*unit*) | intbox 0–1000 | |
| | **Air density** | | |
| 19 | Correct for air density | checkbox | disabled with GPS |
| 20 | *status* | label | "Correction: +13%" when on; "Not used with GPS" for GPS (FR-022) |
| 21 | Field elevation (ft \| m) | intbox −300–10000 / −90–3050, step 10 | FR-020, FR-023 |
| 22 | Temperature source | selectbox Standard / Manual / Sensor | FR-038; saves `tSrc`. Replaces the 0.1.0 "Use standard temperature" checkbox (R10, R16) |
| 23 | Temperature, manual (°F \| °C) | intbox −20–130 / −29–54 | FR-020; enabled only for Manual |
| 24 | Temperature sensor | selectbox (dialog) | FR-039; enabled only for Sensor. "(none)", sensors whose unit is °C/°F, optional "<label> (not found)" (R15, R4) |
| 24a | *hint* | label | "Sensors inside the model can read warmer than outside air" |
| 24b | *temperature status* | label | FR-042, while correction is on: "Temp: 15 °C standard" / "Temp: 20 °C manual" / "Temp: 35 °C from MSpeed 450" / "Sensor not available - using standard". Updated live while the form is open (R17) |
| 24c | *hint* | label | "Leave correction off if your sensor already corrects for air density" |
| | **Gauge** | | |
| 25 | Gauge max limit (*unit*, 0 = auto) | intbox 0–2000 | Renamed from "Gauge full scale" (2026-10-03). Hints: "Highest speed on the dial. To use your sensor's whole range, enter its top speed:" / "MSpeed: 20-350 km/h (12-215 mph)" / "MSpeed 450 EX: 80-450 km/h (50-280 mph)" (sensor ranges from the user, 2026-10-03) and "Auto (overspeed + 15%): 230" |
| 26 | Current speed color | selectbox | R8 presets (no red or orange); default Cyan |
| 27 | Max speed color | selectbox | R8 presets; default Yellow |
| 28 | Reset max speed | link | clears session max (FR-019, US3 #6) |
| | *footer* | label `FONT_MINI`, right-aligned | "Speed Gauge <version> - Based on DFM Speed Announcer by Dave McQueeney" (FR-029) |

Row 28a (Gauge window size) is dropped: size 0 works (research R7).

Units and calibration are in the first group because they describe the
sensor reading, and because every later speed label shows the unit. The
spec's table doesn't place them in a group.

## Characters

Only characters in the API's supported-charset table render (constitution V).
Check `°` against that table in the emulator; if it doesn't render, use
"deg F" / "deg C". Avoid `·`, `≥`, `—` and other symbols in labels (the
spec's em dash in FR-042 is written " - ").

## Behavior

- Every change callback saves its key with `system.pSave` immediately and
  recomputes only the derived values that depend on it (data-model.md).
- Callbacks that change a derived label (`kDens` %, auto full scale, order
  warning) update it with `form.setProperties(idx, {label=...})`.
- The *unit* placeholders are filled from the current units when the form is
  built. After a units change the form is rebuilt with `form.reinit()`.
- `form.*` is called only from `initForm`, component callbacks and `keyForm`
  (constitution VI), with one exception: `loop()` updates row 24b while
  `formOpen` is true. `initForm` sets the flag and the close function
  (`registerForm`'s 7th argument) clears it (research R17). Nothing here
  calls `form.question`.
- Changing Temperature source, the manual temperature or the temperature
  sensor recomputes `kDens` and updates rows 20 and 24b. Choosing Sensor
  resets the sensor status to waiting (data-model.md).
- No F-key functions are required. `keyForm` exists only to leave room for
  them.
