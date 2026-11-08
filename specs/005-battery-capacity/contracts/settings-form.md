# Contract: Settings form

`system.registerForm(1, MENU_APPS, "Battery Capacity", initForm, keyForm,
printForm, closeForm)`. Subform 1 is the main page; subforms 2–5 are
batteries 1–4 (`form.reinit(n)`). Decisions: research R11, R12. Every row
change saves immediately with `system.pSave` (committed by the firmware on
model switch or power-off).

## Subform 1: Main

| # | Row | Component | Notes |
| --- | --- | --- | --- |
| 1 | Battery 1…n | `addLink` per battery | text: "RX-1  Receiver  LiFe 2S"; opens subform 1 + k |
| 2 | Add battery | `addLink` | hidden at 4 batteries; creates the next slot with Receiver defaults and opens it (category is the first row) |
| 3 | Small window shows | `addSelectbox` of battery labels | `smallB` |
| 3a | Small window title | `addTextbox`, max 20 | `title1`; "" = "Battery" (FR-009a) |
| 3b | Double window title | `addTextbox`, max 20 | `title2`; "" = "Batteries"; hint "New titles show after the model is reloaded." |
| 4 | Voice | `addSelectbox` {"Battery Capacity", "Transmitter"} | FR-032; first entry disabled with "(files missing)" when `voiceOk` is false |
| 5 | Speak number only | `addCheckbox` | FR-031 |
| 6 | Status | `addLabel`, `FONT_MINI` | "Voice files missing: transmitter voice in use" when relevant |
| 7 | Credits | `addLabel`, `FONT_MINI` | "Voice: Piper, Amy (CC BY-SA 4.0)." and version |

## Subforms 2–5: Battery k

Rows marked **A** appear only with "Show all settings" on (FR-007); rows
marked **V** only when the battery has a voltage reading; **I** only with a
current sensor; **C** only for Custom.

| # | Row | Component | Range / values | Notes |
| --- | --- | --- | --- | --- |
| 1 | Category | selectbox | display order of categories | refills defaults (FR-007); asks before overwriting edited values (FR-008) |
| 2 | Name **C** | `addTextbox`, max 8 | width-checked | trimmed to fit, "Shortened to fit" note (research R6) |
| 3 | Label | label | "RX-2" | computed (FR-003) |
| 4 | Chemistry | selectbox | LiPo, LiHV, Li-ion, LiFe, NiMH/NiCd | refills voltages and low-voltage threshold (FR-006, FR-008) |
| 5 | Cells | intbox | 1–14 | cell-count check note under it (research R11) |
| 6 | Capacity (mAh) | intbox | 100–30 000, step 50 | needed for mAh/Ah sources; while 0 the note under row 7 flashes ("Capacity (mAh) not set: % from voltage for now." or "Set the pack's capacity (mAh).") |
| 7 | Capacity sensor | selectbox | receiver voltages, then sensors with unit mAh, Ah, %, V | refuses other units: they aren't listed; "(not found)" entry kept (FR-004, edge case) |
| 8 | Voltage sensor | selectbox | receiver voltages, sensors with unit V, "(none)" | gives the % when row 7 is "(none)" or an mAh source has capacity 0 (FR-004); note "Also gives the % when there's no capacity sensor or mAh." |
| 9 | Current sensor | selectbox | sensors with unit A or mA, "(none)" | note "When set, the 4-battery window shows current, not voltage." (FR-011) |
| 10 | Live value | label, updated each second while open | "Now: 72%  8.1 V  0.4 A" | helps confirm the sensors |
| | **Callouts** | | | |
| 11–14 | Level 1–4 | row: checkbox + intbox | 1–99 % | strictly descending among enabled (FR-016); revert with note |
| 15 | Repeat lowest every **A** | intbox | 3–60 s | FR-018 |
| 16 | Max repeats **A** | intbox | 0 (no limit), 1–20 | |
| | **Low voltage V** | | | |
| 17 | Low-voltage alarm | selectbox | Off, Per cell, Per pack | converts threshold on change (FR-019) |
| 18 | Threshold | intbox, 2 decimals (per cell) or 1 (per pack, shown from cV) | cV | default Warning (× cells) |
| 19 | Delay **A** | intbox, 1 decimal | 0.5–10 s | FR-020 |
| | **Current I** (hidden for ECU and Lights unless "Show all") | | | |
| 20 | Current alarm above | intbox | 0–500 A, 0 = off | FR-024 |
| 21 | for | intbox, 1 decimal | 0–10 s | |
| 22 | repeat every | intbox | 0–60 s | note lists what's still 0 |
| 23 | Max current callouts | checkbox | | default by category (FR-026) |
| 24 | Max sensitivity **A** | intbox | 1–50 A | |
| 25 | Reset max current | `addLink` | | FR-027 |
| | **New pack V** | | | |
| 26 | Check pack is full | checkbox | default off | FR-029 |
| 27 | Full above **A** | intbox | 50–99 % | |
| | **Voice** | | | |
| 28 | Name for transmitter voice | `addAudioFilebox` | file from /Audio | FR-033; empty = number only |
| | **Advanced A** | | | |
| 29 | Bands yellow / orange / red | three intboxes | descending | FR-007 |
| 30 | Full / Nominal / Warning / Cutoff | four intboxes, 2 decimals | cV per cell | FR-006; editing sets the edited bit |
| 31 | Show all settings | checkbox | | per battery; `form.reinit` |
| 32 | Delete battery | `addLink` → `form.question`; also **F1 "Delete"** on every battery screen | | compacts slots (research R5); F1 added after the emulator review (the row is last on a long screen) |

## Rules

- The sensor lists come from one `system.getSensors()` pass when the
  subform opens, filtered by unit (research R1). Never called from `loop()`.
  The capacity and voltage lists also start with the three receiver
  voltages, read from `getTxTelemetry()` (research R1).
- Only form callbacks and `initForm` build components; `loop()` touches
  the form only through `form.setProperties` on the live-value label and
  setup notes, and only while `formOpen` (Speed Gauge R17).
- `form.question` is only called from callbacks (it blocks).
- Key handling: F5/ESC on a battery subform returns to the main page
  (`form.preventDefault()` + `form.reinit(1)`); on the main page they close
  the form as usual.
- Intbox values never exceed 32 767 (centivolts and mAh both fit).
