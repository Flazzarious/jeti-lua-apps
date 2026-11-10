# Contributing

Thanks for your interest in these JETI Lua apps. Bug reports, test results
from your own transmitter, ideas and code are all welcome.

By taking part you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Safety first

These apps run on a radio transmitter, which is flight equipment. The
project's rules are in the constitution,
[`.specify/memory/constitution.md`](.specify/memory/constitution.md), and they
override everything else. The most important one:

**Nothing an app does may affect flight.** Apps are for telemetry,
announcements, alarms, timers and displays. Never call
`system.registerControl`, `system.setControl` or `system.setProperty`, and
never drive outputs. An app that crashes or is removed must leave the model
flying exactly as before. Changes that break this rule can't be accepted.

## Reporting a bug

Open an [issue](https://github.com/Flazzarious/jeti-lua-apps/issues) with:

- the **app and version** (shown at the bottom of most apps' settings
  screens; otherwise the version you installed in JETI Studio);
- your **transmitter** (DS-24 II, DC-24 II, or the first-version DS/DC-24)
  and its **firmware** version;
- for telemetry apps, the **sensor or ECU converter** you use;
- what you did, what you expected and what happened;
- a **screenshot** if it's about the display (the transmitter saves
  `ScreenNNN.png` to the SD card), or the Lua console output from JETI
  Studio's emulator.

**Test results are just as useful:** "works on my first-version DS-24" or
"the alarm is too quiet with a JetCat ECU" helps decide what to fix next.

## Suggesting a feature or a new app

Open an issue describing what you'd like the app to do and why. New apps and
bigger changes are planned spec-first (see below), so a short description of
the problem it solves is the best start.

## Contributing code

### Before you start

- Read [`CLAUDE.md`](CLAUDE.md) (a short summary of the rules and layout),
  the constitution, and the README's **First-time setup**.
- The only Jeti APIs that exist are the ones declared in
  [`types/jeti.lua`](types/jeti.lua). Runtime limits and quirks are in
  [`docs/jeti-api-notes.md`](docs/jeti-api-notes.md).
- Follow the style reference,
  [`docs/examples/style/HELLO.lua`](docs/examples/style/HELLO.lua).

### Spec-first

Each feature, whether a new app or a change to an existing one, gets its own
folder in `specs/NNN-name/` with a spec, plan and task list, made with
[GitHub Spec Kit](https://github.com/github/spec-kit) (`/speckit-specify`,
`/speckit-plan`, `/speckit-tasks`, `/speckit-implement`). Small bug fixes and
documentation changes don't need a spec; say what you changed and why in the
pull request.

### Branches and pull requests

| Branch | Purpose |
| --- | --- |
| `main` | Released versions only. Updated **only** by a pull request from `develop` (GitHub enforces this). |
| `develop` | Finished work waiting for a release. Updated only by pull requests. |
| `feature/NNN-name` | Your work, branched from `develop`, named like its `specs/` folder. |

1. Fork the repository and branch from `develop`.
2. Make your change, and open a pull request **into `develop`**, never into
   `main`.
3. Describe what changed, why, and how you tested it.

The maintainer handles releases: a pull request from `develop` into `main`,
then a tag such as `AG-FlmOt-v0.2.0`.

### Naming and layout

```
src/Apps/AG-xxxxx.lua      one file per app: "AG-" plus 1-5 letters or digits
src/Apps/AG-xxxxx/         that app's sounds, images and language files
src/Apps/lib/ag_xxxxx.lua  shared module, loaded with require("ag_xxxxx")
```

- **Never rename a released app's file.** The transmitter ties each model's
  settings to the filename; renaming loses them.
- Every variable and function is `local`. No `os`, `debug`, `coroutine` or
  `bit32`: the emulator has them, the transmitter doesn't.
- Shared modules hold no state. Changing one means re-checking every app
  that uses it.
- Spoken callouts use the shared Piper "Amy" voice; see
  [`tools/voice/README.md`](tools/voice/README.md).

### Checks

Before opening a pull request:

- `python tools/check.py` passes (syntax, forbidden APIs, naming, UTF-8, LF
  line endings);
- the VS Code Problems panel (LuaLS, configured by `.luarc.json`) shows no
  errors.

### Testing

Say in your pull request how you tested:

1. **JETI Studio emulator:** copy the app to
   `%LOCALAPPDATA%\JETI-Studio\Emulator\Apps`. LeonAirRC's Emulated
   Telemetry app supplies sensors (`tools/emulator/sensors.json`). The
   emulator plays no Lua audio and its windows are larger than the
   transmitter's.
2. **Transmitter:** copy the app to `/Apps` on the SD card and try it on a
   **test model**, never on a model you'll fly the same day. Sound, voice
   and the real window sizes can only be checked here.

Several apps have a `SIM` switch near the top of the file that replays
scripted sensor data for bench tests. Leave it `false` in your pull request.

## Licensing and credit

- The code is **MIT** ([LICENSE](LICENSE)). By contributing, you agree that
  your contribution is licensed under the MIT license too. Every `.lua` file
  starts with the copyright line and `SPDX-License-Identifier: MIT`.
- The generated **voice files** are **CC BY-SA 4.0** (the Piper "Amy"
  model), not MIT. Keep each folder's `CREDITS.txt`.
- If your work builds on someone else's, credit it in the source header, the
  app's settings screen, the README and [CREDITS.md](CREDITS.md), and keep
  their license notice. Don't copy code whose license is unclear or doesn't
  allow it.
