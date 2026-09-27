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
| 6 | Callouts on/off switch | inputbox | proportional allowed |
| 7 | Continuous callouts switch | inputbox | |
| | **Callouts** | | |
| 8 | Callout sensitivity (*unit*) | intbox 1–100 | |
| 9 | *hint* | label | "Speak sooner when speed changes by this much" |
| 10 | Shortest time between callouts (s) | intbox 1–10 | |
| 11 | Longest time between callouts (s) | intbox 10–60 | |
| 12 | Landing speed (*unit*) | intbox 0–1000 | |
| 13 | *hint* | label | "Callouts every shortest time below this" |
| 14 | Speak number only (no units) | checkbox | |
| 15 | Announce stall speed at startup | checkbox | FR-028 |
| | **Warnings** | | |
| 16 | *order warning* | label, hidden unless illogical | "Check: stall < landing < overspeed < full scale" (FR-026) |
| 17 | Stall warning at (*unit*) | intbox 0–1000 | |
| 18 | Overspeed warning at (*unit*) | intbox 0–1000 | |
| | **Air density** | | |
| 19 | Correct for air density | checkbox | disabled with GPS |
| 20 | *status* | label | "Correction: +13%" when on; "Not used with GPS" for GPS (FR-022) |
| 21 | Field elevation (ft \| m) | intbox, step 10 | FR-020, FR-023 |
| 22 | Temperature (°F \| °C) | intbox | disabled while row 23 is checked |
| 23 | Use standard temperature | checkbox | R10 |
| 24 | *hint* | label | "Leave correction off if your sensor already corrects for air density" |
| | **Gauge** | | |
| 25 | Gauge full scale (*unit*, 0 = auto) | intbox 0–2000 | hint shows "Auto: 230" |
| 26 | Current speed color | selectbox | R8 presets |
| 27 | Max speed color | selectbox | |
| 28 | Reset max speed | link | clears session max (FR-019, US3 #6) |
| | *footer* | label `FONT_MINI`, right-aligned | "Speed Gauge 0.1.0 - Based on DFM Speed Announcer by Dave McQueeney" (FR-029) |

Units and calibration are in the first group because they describe the
sensor reading, and because every later speed label shows the unit. The
spec's table doesn't place them in a group.

## Characters

Only characters in the API's supported-charset table render (constitution V).
Check `°` against that table in the emulator; if it doesn't render, use
"deg F" / "deg C". Avoid `·`, `≥` and other symbols in labels.

## Behavior

- Every change callback saves its key with `system.pSave` immediately and
  recomputes only the derived values that depend on it (data-model.md).
- Callbacks that change a derived label (`kDens` %, auto full scale, order
  warning) update it with `form.setProperties(idx, {label=...})`.
- The *unit* placeholders are filled from the current units when the form is
  built. After a units change the form is rebuilt with `form.reinit()`.
- `form.*` is called only from `initForm`, component callbacks and `keyForm`
  (constitution VI). Nothing here calls `form.question`.
- No F-key functions are required. `keyForm` exists only to leave room for
  them.
