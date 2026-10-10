# Contract: Screens

One form, registered under `MENU_APPS` as "Turbine Throttle Setup". Each
screen is a subform (`form.reinit(n)`) built from form components only
(research R9). Text lines are ≤ 32 characters. Live labels update from
`loop()` only while the form is open, at most every 200 ms, and only when
the text changes.

F-key labels are ≤ 7 characters.

## 1. Home

- Status: "Not verified" / "Incomplete - failsafe not confirmed" /
  "Setup complete 2026-10-10" (data-model).
- Links: "Setup inputs", "Guided setup", "Verify", "Summary". Guided setup
  and Verify are disabled until setup is complete. Summary is disabled
  while `res = 0`.
- On a transmitter that isn't a DC/DS-24: only "Turbine Throttle Setup
  needs a DC/DS-24" (R13).

## 2. Setup inputs (FR-001 to FR-005a)

| Row | Component | Notes |
| --- | --- | --- |
| Warning | two labels | "ENGINE MUST NOT BE ABLE TO START" / "(fuel off or ECU unplugged)" (FR-023) |
| Safety switch | inputbox, not proportional | live: "OFF" / "RUN" / "middle" / "not learned" |
| Throttle stick | inputbox, proportional | live: "idle" / "full" / "middle" |
| Learn | label + F3 "Learn" | "Switch to OFF, stick to idle, press Learn." Stores `offSg`, `idlSg` (R5) |
| Throttle output | selectbox "O1".."O24" | live: "1102 us" |
| Cut / Idle / Full | intboxes, 900–2100, step 5 | defaults on long press |
| Idle position | label | "Idle position: 22.2%" |
| Message | label | refusal or warning ([settings-math.md](settings-math.md)) |
| Tolerance | intbox 5–25, step 1 | "+/- 10 us" |

- Choosing a new switch or stick clears `offSg`/`idlSg` (learn again).
- **FR-005a:** while `res > 0`, the first change on this screen asks
  `form.question("Clear saved result?", "Changing setup means it must be",
  "verified again.")`. No puts the value back. Yes sets `res = 0`, clears
  `meas` and `when`, and allows further changes without asking again.
- Learn refusals: "Use a two-position switch" (switch near 0) and "Move
  the stick fully to idle" (|v| < 0.95).

## 3. Guided setup (FR-006 to FR-012)

Title "Step n of 5". F1 "Back", F3 "Open" (hidden for step 5 or when
`openExternal` is missing), F5 "Next" ("Verify" on step 5). Each step
shows the menu path and exact values from
[settings-math.md](settings-math.md). Menu names are confirmed on
firmware 6.x in task 1 (spec research item 3) and changed here if needed.

| Step | Menu (Open) | Content |
| --- | --- | --- |
| 1 Endpoints | `:servoSetup` | "Model > Servo setup > [throttle]" / "Travel -: 100%" / "Travel +: 80%" (one "Travel: +/-X%" line when equal; `±` only if the charset check passes) |
| 2 Throttle Cut | `:otherProps` | "Adv. properties > Other model" / "options > Throttle Cut" / "Switch: your safety switch, OFF" / "Output value: -100%" |
| 3 Throttle Idle | `:otherProps` | "...> Throttle Idle" / "Switch: same switch, RUN" / "Idle offset: 40%" |
| 4 Failsafe | `:devExplorer` | "Device Explorer > receiver >" / "throttle output failsafe:" / "OFF (no pulse), or about 1000 us" / "The app can't read this. You'll" / "test it by hand at the end." (FR-010) |
| 5 Safety switch | none | "Use a locking 2-position switch" / "within easy reach." / "Don't use it for anything else." (FR-011) |

- The step is saved to `gStep` on every change (FR-009).
- From Home, "Verify" skips the guide entirely (FR-012).

## 4. Verify

See [verify.md](verify.md). Rows: standing lines, the prompt and phase
line, four result rows, and the diagnosis (two lines).

## 5. Failsafe confirmation (User Story 3)

- Text: "With the ECU powered and fuel" / "OFF, switch the transmitter off." /
  "Does the ECU show signal loss?"
- F1 "Not yet": leaves `res = 1` and goes to Summary showing "Incomplete -
  failsafe not confirmed".
- F5 "Yes": `res = 2`, goes to Summary.

## 6. Summary (FR-020)

- Status line (as Home).
- "Safety switch: <label>, OFF at -100%" (or +100%, from `offSg`). The
  label comes from `system.getSwitchInfo(sw).label`.
- "Targets: 1000 / 1200 / 1900 us"
- "Measured: 1002 / 1001 / 1199 / 1898"
- "Verified: 2026-10-10"
- Next step: "Remove this app from the model," / "then run the ECU's Teach RC," /
  "or skip it if the ECU already" / "knows these targets."
