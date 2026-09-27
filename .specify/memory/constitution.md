# Jeti Lua Apps Constitution

Apps in this repository run on a JETI DS-24 v2 transmitter (DC/DS-24 family,
Lua 5.3.1). A transmitter is flight equipment: a misbehaving app must never be
able to cause a crash. Every spec, plan and task inherits these principles.
Where a principle cites the API, the source is the JETI DC/DS Lua API v1.5
(see `docs/jeti-api-notes.md`).

## Core Principles

### I. Nothing Flight-Critical (NON-NEGOTIABLE)

Apps are for telemetry, timers, announcements, logging and displays. They MUST
NOT influence anything that can move the model or change how the radio link
behaves.

- MUST NOT call `system.registerControl` or `system.setControl`. A registered
  Lua control can be assigned by the pilot to any model function, including
  throttle and surfaces, and it stops updating if the app stops. If a future
  feature genuinely needs one, it requires an explicit amendment to this
  constitution, a non-critical-use justification in the spec, and a
  control label that says so.
- MUST NOT call `system.setProperty` (it can switch wireless trainer mode).
- MUST NOT drive `gpio` outputs or write to `serial` ports unless a spec
  explicitly scopes that hardware and states why failure is harmless.
- An app that crashes, stalls or is removed MUST leave the model flying
  exactly as it would without the app.

### II. Everything Local

All apps share one global Lua environment on the transmitter. Every variable
and function MUST be declared `local`, including helpers inside functions. A
file's only exports are its final `return`: the app interface table for an
app, or the module table for a `lib` module (Principle VII). LuaLS enforces
this with `lowercase-global` set to Error; a diagnostic here is a build
failure, not a warning.

### III. Transmitter APIs Only

Only libraries present on the transmitter may be used: `system`, `lcd`, `form`,
`dir`, `json`, `gps`, `gpio`, `serial`, plus the Lua standard `string`,
`table`, `math`, `utf8`, `package` (`require`) and Jeti's limited `io`.

- `os`, `debug`, `coroutine` and `bit32` do not exist on the transmitter. They
  DO exist in the JETI Studio emulator, so code that uses them can pass
  emulator testing and fail on the radio. Use `system.getTime()` or
  `system.getTimeCounter()` instead of `os.time()`/`os.clock()`.
- Jeti's `io` is function-style (`io.read(f, n)`, `io.close(f)`), not the
  standard method-style `f:read()`.
- If `types/jeti.lua` does not declare a function, do not call it. Check the
  API PDF, add the stub with a source note, then use it.

### IV. State Resets on Model Switch

The Lua context is destroyed and recreated whenever the model changes, and
`init(code)` runs again. In-memory state MUST be treated as disposable.

- Persist settings with `system.pSave` / `system.pLoad` only.
- `pSave` stores integers (32-bit), strings under 64 bytes, SwitchItems, and
  arrays of up to 32 integers/strings. It does NOT store floats or keyed
  tables: scale floats to integers (e.g. 12.5 V → 125, 1 decimal).
- Keep persisted parameters to 30 or fewer per app.
- Saves are committed on model switch or power-off, not immediately.

### V. Stable Names and UTF-8

This repository holds many apps. They share the transmitter's `/Apps` folder
with other authors' apps (e.g. `DFM-*`, `RCT-*`), so every name carries the
`AG-` prefix.

- **App scripts** MUST be named `AG-xxxxx.lua`: the prefix plus 1–5 letters or
  digits, which keeps them 8.3 (e.g. `AG-SpdGa.lua`). The name shown in menus
  is set separately by the app and can be anything (e.g. "Speed Gauge").
- **Names are permanent once released.** The transmitter keys each app's model
  configuration to its filename. Renaming an app silently discards its
  telemetry windows and settings on every model that uses it.
- **Asset folders:** an app's sounds, images and `.jsn` language files MUST
  live in a folder named exactly like its script without `.lua`
  (`src/Apps/AG-SpdGa/`). Code refers to them by absolute path
  (`/Apps/AG-SpdGa/...`).
- **Nothing else** may sit at the top of `src/Apps/` except those apps, their
  folders and `lib/`. `tools/check.py` enforces this.
- **Encoding:** `.lua` apps and `.jsn` language files MUST be UTF-8 without
  BOM, with LF line endings (`.gitattributes` enforces LF on every OS). Only
  characters in the API's supported-charset table render.

### VI. Keep loop() Light

`loop()` runs every 20–30 ms with no timing guarantee and shares the CPU with
up to 9 other apps.

- No allocation-heavy work in `loop()` or in telemetry print functions:
  avoid `string.format`, string concatenation, and table creation per call.
  Cache formatted strings and rebuild them only when the underlying value
  changes.
- Rate-limit work with `system.getTimeCounter()` rather than doing it every
  loop.
- Read sensors with `system.getSensorValueByID` (lighter) unless labels or
  units are needed.
- `lcd` calls belong only in registered print functions; `init()` and `loop()`
  cannot use `lcd`, and `form` calls only work while the app's form is open.

### VII. Shared Code Lives in lib, Holds No State

Code useful to more than one app (e.g. density-altitude math, gauge drawing)
goes in a shared module rather than being copied between apps.

- **Naming and location:** modules MUST be flat files named `ag_xxxxx.lua`
  (`ag_` plus 1–5 lowercase letters or digits) in `src/Apps/lib/`. They are
  deployed to `/Apps/lib/` and loaded with `require("ag_xxxxx")`. No
  subfolders: the transmitter's `require` search is documented only for
  `/Apps/lib/<name>.lua`.
- **No shared state:** `require` loads a module once per Lua context and hands
  the same table to every app that asks. A module MUST therefore return
  functions (or constructors) and hold no mutable module-level state; each app
  keeps its own state in its own locals.
- **Principles II–VI apply to modules exactly as to apps.** A module MUST
  NOT register forms, telemetry windows or anything else on the app's behalf.
  The app does that and passes in what the module needs.
- **Change carefully:** changing a module's behavior affects every app that
  uses it. The plan for such a change MUST list the affected apps, and each
  of them MUST be re-verified.

### VIII. License and Credit

This repository is MIT-licensed (`LICENSE`, Copyright (c) 2026 Aaron George).

- **License tag:** every app script, `lib` module and style reference MUST
  carry `-- SPDX-License-Identifier: MIT` in its first 15 lines. `check.py`
  enforces this.
- **Derived work** keeps the original author's copyright line as well, as
  described below.


Apps here are often derived from other authors' published work. That work is
credited, and its license terms are honored.

- **Where the credit goes:** an app derived from another app MUST credit the
  original author and app in four places:
  - its source file header, together with the original's copyright and
    license notice as the license requires;
  - its settings screen;
  - the README apps table;
  - `CREDITS.md`, which carries full license texts.
- **Reused assets** (sounds, images) keep their original credit.
- **Existing credits and license notices** MUST NOT be removed or shortened.
- **Unclear or restrictive licenses:** code is not copied from a source whose
  license is unclear or doesn't allow it. Such work may be studied for ideas
  only, and the spec says so.

## Verification

Every feature MUST pass, in order:

1. LuaLS diagnostics clean (no errors) against `types/jeti.lua`.
2. `python tools/check.py` (Lua 5.3 syntax check, forbidden-API scan, naming
   and encoding rules).
3. JETI Studio DS-24 II emulator run, with telemetry supplied by LeonAirRC's
   Emulator Telemetry app where sensors are needed. Watch the app's CPU figure
   in Applications → User Applications and memory via `collectgarbage("count")`.
4. First real run on a dedicated test model on the transmitter, never on a
   model that will fly the same day.

Compiled `.lc` files are build output: produce them from the matching
firmware/emulator version, never commit them, and keep `.lua` as the source.

## Governance

This constitution overrides specs, plans and agent suggestions. Amendments
require a written rationale in the commit message and a version bump below.
Principle I cannot be relaxed for convenience; an amendment to it must name
the specific API, the specific app, and why failure of that app cannot affect
flight.

**Version**: 1.3.0 | **Ratified**: 2026-09-26 | **Last Amended**: 2026-09-27

### Amendment history

- **1.3.0 (2026-09-27):** the repository adopts the MIT license. Principle
  VIII (renamed "License and Credit") requires an SPDX license tag in every
  app and module.
- **1.2.0 (2026-09-27):** new Principle VIII requires crediting and honoring
  the licenses of work apps are derived from. Prompted by Speed Gauge being
  based on DFM Speed Announcer.
- **1.1.0 (2026-09-27):** the repository holds multiple apps. Principle V
  gains the `AG-` naming convention for apps and asset folders; Principle VII
  (new) covers shared `lib` modules. Verification now names `tools/check.py`
  and the DS-24 II emulator.
