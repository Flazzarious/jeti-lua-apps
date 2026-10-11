# Implementation Plan: Turbine Throttle Setup

**Branch**: `feature/002-turbine-throttle-setup` (merges to `develop`, then `main` on release) | **Date**: 2026-10-10 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/002-turbine-throttle-setup/spec.md`

## Summary

A new app, **Turbine Throttle Setup** (`src/Apps/AG-TrbSt.lua`), a bench
wizard that guides the pilot through JETI's own throttle setup and then
proves it by measuring the throttle output. Travel, Throttle Cut and
Throttle Idle go on one two-position safety switch, plus receiver
failsafe. The app only reads and instructs. It never changes a setting or
drives an output.

Approach:

- **One file plus two voice files.** No telemetry window and no lib
  module. The install is `AG-TrbSt.lua` and its folder `AG-TrbSt/`, which
  holds the optional "Turbine off" / "Turbine on" callouts (FR-024, R10,
  R14). The app copies them to `/Audio` on request for JETI's Sounds on
  event and never plays them itself (User Story 4, R15).
- **Read the real output.** `system.getInputs("O<n>")` converted at
  1500 + 500·v µs. **One fixed recipe** (clarification 2026-10-10): Max
  negative −80% / Max positive 80%, idle offset 20%, Throttle-Cut −100%,
  or −125% for Xicoy. The pilot picks the ECU type, which sets the targets
  verify expects (1100 or 1000 / 1200 / 1900 µs). No custom targets. The
  ECU is always re-learned afterwards. Calibration on the transmitter
  confirmed the output read is post-mix and the targets match (R1, R2).
- **Open the menus directly** with `system.openExternal(":servoSetup" |
  ":otherProps" | ":devExplorer")` (API v1.5 p. 74–75, R3). The wizard's
  place lives in locals plus `pSave`, so returning from a menu works
  whatever the firmware does (R4).
- **Learn CUT and idle from the pilot's hands.** One "Learn" press stores
  the switch's CUT sign and the stick's idle sign (R5).
- **Verify = output check + the spec's four states.** It waits for
  position and 500 ms of steadiness, averages 10 samples, and diagnoses
  failures from a fixed table. A retry is for diagnosis only. Only a clean
  run saves (R7, R8, clarification Q1).
- **Forms only.** Every screen is a subform of labels, inputboxes and
  intboxes, with live labels updated while the form is open (R9).
- **Trim and flight mode can't be read.** FR-018 was amended to standing
  reminders (R6).

## Technical Context

**Language/Version**: Lua 5.3.1 on the transmitter (32-bit integers and floats)

**Primary Dependencies**: JETI DC/DS Lua API v1.5 as declared in `types/jeti.lua`: `system` (`getInputs`, `getInputsVal`, `getSwitchInfo`, `openExternal`, `registerForm`, `pSave`/`pLoad`, `getTimeCounter`, `getDateTime`, `getDeviceType`), `form` (`addInputbox`, `addIntbox`, `addSelectbox`, `addLabel`, `addLink`, `setProperties`, `setValue`, `setButton`, `reinit`, `question`, `setTitle`). All are declared. Task 1 updates the `openExternal` stub comment with the menu constants (API p. 74–75). No new functions

**Storage**: `system.pSave`/`pLoad`, per model, 14 keys ([data-model.md](data-model.md)). No files written

**Testing**: `python tools/check.py`; LuaLS diagnostics; calibration against the servo monitor; emulator scenarios and seeded faults; transmitter checks; ECU bench test ([quickstart.md](quickstart.md))

**Target Platform**: JETI DS-24 II / DC-24 II, firmware 6.03+ (emulator 6.04). Other transmitters get a "needs a DC/DS-24" notice (R13)

**Project Type**: Embedded transmitter app (single Lua script)

**Performance Goals**: Readings agree with the servo monitor within ±5 µs (SC-003); a state is measured within about 1.5 s of the stick and switch arriving in position (500 ms steady + 10 × 50 ms samples); `loop()` returns at once when the form is closed

**Constraints**: `form.*` only while the form is open (`formOpen` guard); `form.question` only in form callbacks, never in `loop()`; no allocation in `loop()` except rebuilding a label string when its value changes; ≤ 30 persisted keys; ≤ 200 file-level locals (constants and state grouped in tables); no `os`/`debug`/`coroutine`/`bit32`; never `registerControl`/`setControl`/`setProperty`; intbox values ≤ 32,767; text lines ≤ 32 characters; only charset-table characters ("us", "+/-" until `µ`/`±` are confirmed)

**Scale/Scope**: About 600–800 lines; 6 screens; 5 guide steps; 5 verify steps

Open items are handled in task 1 or in transmitter checks, each with a
fallback:

- `O<n>` is post-mix (R1.1). Stop rule: revisit the spec;
- clipping at ±1 (R1.2). Fallback: narrow targets to 1000–2000 µs;
- idle offset after or scaled by travel (R2). Fallback: change one formula;
- the form's behavior after `openExternal` (R3). The design works either way (R4);
- 6.x menu and field names (spec research item 3). Update the screen text;
- whether a copied model copies app data (R11). Safe either way; documented.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | How the design complies |
| --- | --- | --- |
| I. Nothing flight-critical | PASS | Reads outputs, the stick and the switch; opens menus. No `registerControl`, `setControl`, `setProperty`, gpio or serial. `openExternal` only displays a menu, and the pilot makes every change. Nothing at flight time depends on the app, and the summary says to remove it (FR-021, FR-022) |
| II. Everything local | PASS | All symbols `local`; constants, verify thresholds and screen indexes grouped in tables; one final `return` |
| III. Transmitter APIs only | PASS | Every call is declared in `types/jeti.lua`; `string`/`math` only |
| IV. State resets on model switch | PASS | 14 `pSave` keys (ints, two SwitchItems, one 4-int array); load clamps and validates; a verify run is session-only and never resumed |
| V. Stable names, UTF-8 | PASS | `AG-TrbSt.lua` (8.3, permanent at first release); sounds in `AG-TrbSt/` with 8.3 names, absolute `/Apps/AG-TrbSt/...` paths; copies to `/Audio` only at the pilot's request (R15); ASCII text until `µ`/`±` are confirmed |
| VI. Keep loop() light | PASS | Immediate return when the form is closed; 50 ms work interval in verify; label updates every 200 ms at most and only on change |
| VII. Shared code in lib, stateless | PASS | No lib module added or changed |
| VIII. License and credit | PASS | Original app: MIT SPDX header, no third-party code. ECU manuals and forum posts are cited for facts only. Voice: Piper (MIT) and "Amy" (CC BY-SA 4.0) credited in `AG-TrbSt/CREDITS.txt`, `CREDITS.md`, the README and the Voice callouts screen (FR-029) |

**Post-design re-check (2026-10-10):** PASS. The contracts add no API
beyond the table. Two patterns need care: `form.setProperties` from
`loop()` only while `formOpen` (Flameout Alarm R10), and `form.question`
only from component callbacks.

## Project Structure

### Documentation (this feature)

```text
specs/002-turbine-throttle-setup/
├── spec.md
├── plan.md               # this file
├── research.md           # R1–R13
├── data-model.md         # setup, wizard position, result, verify run, transitions
├── quickstart.md         # calibration, emulator, transmitter, bench
├── contracts/
│   ├── settings-math.md  # recommended values per ECU type, targets, µs conversion
│   ├── screens.md        # six screens, rows, F-keys, text
│   └── verify.md         # sequence, thresholds, diagnosis table
├── checklists/requirements.md
└── tasks.md              # /speckit-tasks
```

### Source Code (repository root)

```text
src/Apps/
├── AG-TrbSt.lua          # NEW: the whole app
└── AG-TrbSt/             # NEW: generated by tools/voice/make_turbine.py, committed (CC BY-SA 4.0)
    ├── TurbOff.wav       # "Turbine off"
    ├── TurbOn.wav        # "Turbine on"
    └── CREDITS.txt

tools/voice/make_turbine.py   # NEW: the two callouts (R14)
tools/voice/README.md         # add a Throttle Setup Wizard section
CREDITS.md                    # Throttle Setup Wizard voice: Piper, Amy (CC BY-SA 4.0)

types/jeti.lua            # openExternal comment: menu constants (API p. 74–75)
docs/jeti-api-notes.md    # calibration results, openExternal return behavior,
                          # copied-model behavior, charset findings
README.md                 # apps table row and a short section
CLAUDE.md                 # apps table row
```

Inside `AG-TrbSt.lua`, sections follow `docs/examples/style/HELLO.lua`:
constants (keys, limits, thresholds, menu names, text) → settings load,
clamp and validate → settings math → live readout helpers → verify
engine and diagnosis → screens (one builder per subform) → form
callbacks → `init` / `loop` / `destroy` → `return { ... }`.
`APP_VERSION` starts at "0.1.0".

**Structure Decision**: The repo's standard single-app layout
(constitution V), without an asset folder. No `lib/` module: the µs
conversion and settings math are a few lines with no second user.

## Implementation order

For `/speckit-tasks`. Each step leaves `check.py` passing.

1. **Calibration skeleton** (R1–R3): header, settings keys with
   load/clamp, `init` registering the form, the Setup inputs screen with
   live switch, stick and output readouts, and temporary Open buttons for
   the three menus. Update the `openExternal` stub comment. Aaron runs
   quickstart section 1. Record the results, and apply the stop rule or
   fallbacks before going on.
2. **Settings math and validation** ([contract](contracts/settings-math.md)):
   the fixed recommended values, Throttle-Cut value and targets per ECU
   type, the ECU and tolerance rows.
3. **Learn and the rest of Setup inputs**: Learn with refusals; clearing
   learned signs on reassignment; FR-005a confirm-and-clear.
4. **Home and guided setup** ([contract](contracts/screens.md)): status,
   enable rules, five steps with computed values, Open, `scr`/`gStep`
   persistence.
5. **Verify** ([contract](contracts/verify.md)): phases, position and
   steadiness, sampling, pass/fail, diagnosis table, retry/restart,
   clean-run rule, standing lines.
6. **Failsafe and Summary**: `res` transitions, the date, summary text.
7. **Device check** (R13) and the `openExternal`-missing fallback.
8. **Docs**: README row and section (what it does, that it's removed
   after use, ECU idle-position guidance), CLAUDE.md table,
   `docs/jeti-api-notes.md` findings.
9. **Validation**: quickstart section 2 in the emulator; sections 3–4 on
   the transmitter and the bench (manual, reported by Aaron).

## Complexity Tracking

No constitution violations to justify.
