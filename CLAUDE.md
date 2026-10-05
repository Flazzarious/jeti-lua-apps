# Jeti Lua Apps

A collection of Lua 5.3 apps for a JETI DS-24 II transmitter (firmware 6.x),
built spec-first with GitHub Spec Kit (`/speckit-specify`, `/speckit-plan`,
`/speckit-tasks`, `/speckit-implement`). Each feature gets its own
`specs/NNN-name/`. A feature may create a new app or change an existing one.

## Apps in this repo

| App (menu name) | Script | Spec | Based on |
| --- | --- | --- | --- |
| Speed Gauge | `src/Apps/AG-SpdGa.lua` | `specs/001-speed-gauge/` | DFM Speed Announcer (Dave McQueeney, MIT) |

Keep this table current when an app is added.

## License

The repo is MIT (`LICENSE`). Every app, lib module and style reference starts
with:

```lua
-- Copyright (c) 2026 Aaron George
-- SPDX-License-Identifier: MIT
```

`check.py` fails any `.lua` file without the SPDX line.

## Credit what you build on

When an app is derived from someone else's work, credit it everywhere
constitution VIII requires: the source header (with the original license
notice), the app's settings screen, the README, and `CREDITS.md`. Never remove
or shorten an existing credit or license notice.

## Read before writing any code

- `.specify/memory/constitution.md`: the rules. They override everything else,
  including specs and your own suggestions.
- `types/jeti.lua`: the only APIs that exist. If a function isn't declared there,
  don't call it. Check the API doc, add a stub with a source note, then use it.
- `docs/jeti-api-notes.md`: runtime limits, lifecycle, persistence rules.
- `docs/examples/style/HELLO.lua`: the style reference for a complete app.
- `docs/examples/jeti-demos/`: official demos. Copy their API usage, not their
  structure.
- `src/Apps/lib/`: shared modules. Check here before writing a helper another
  app may already have.

## Layout and naming (constitution V and VII)

```
src/Apps/AG-xxxxx.lua      one file per app ("AG-" + 1-5 chars, 8.3)
src/Apps/AG-xxxxx/         that app's sounds, images, .jsn files
src/Apps/lib/ag_xxxxx.lua  shared module, loaded with require("ag_xxxxx")
```

- **Filenames are permanent once released.** Renaming loses users' settings.
- **Asset paths** in code are absolute: `/Apps/AG-xxxxx/sound.wav`.
- **Lib modules** return a table of functions and hold no module-level state.
  One copy is shared by every app. They never register forms or windows
  themselves.
- **Changing a lib module** means listing and re-checking every app that
  uses it.

## Hard rules (summary; the constitution has the detail)

- Never call `system.registerControl`, `system.setControl` or
  `system.setProperty`. Nothing an app does may affect flight.
- Every variable and function is `local`. An app file ends with
  `return { init=..., loop=..., author=..., version=..., name=... }`.
- No `os`, `debug`, `coroutine`, `bit32`. The JETI Studio emulator has them, but
  the transmitter doesn't.
- `lcd.*` only inside registered print functions; `form.*` only while the app's
  form is open.
- `system.pSave` stores integers, short strings, SwitchItems and small arrays.
  Scale floats to integers.
- `loop()` runs every 20-30 ms: rate-limit with `system.getTimeCounter()`, and
  don't format strings or build tables per call.

## Branching (Gitflow)

- Work on `feature/NNN-name`, branched from `develop`, with the same `NNN-name`
  as the spec folder. Never commit directly to `main` or `develop`.
- Features merge into `develop`. Releases go `develop` → `release/x.y.z` →
  `main`, tagged `<script>-v<version>` (e.g. `AG-SpdGa-v1.0.0`). Hotfixes branch
  from `main` and merge into both.
- Spec Kit finds the feature via `.specify/feature.json`, not the branch name,
  so the `feature/` prefix is fine.
- Ask before pushing, merging into `develop`/`main`, or tagging.

## Checking work

- `python tools/check.py` must pass (syntax, forbidden APIs, AG- naming, UTF-8,
  LF).
- LuaLS diagnostics must show no errors (configured by `.luarc.json`).
- You can't run the emulator. Say what to test in JETI Studio and on a test
  model instead of claiming the app works.

## Environment

- **Target:** DS-24 II / DC-24 II only for anything drawn on screen. Design
  for the Lua window sizes measured **on the transmitter**, not the panel's
  480 × 480 or the emulator's: small 150 × 23, large 150 × 68, full screen
  316 × 159, all visible, with the title drawn above the window. The JETI
  Studio emulator (firmware 6.04) reports 157 × 60 / 157 × 127 / 320 × 260
  with a title bar inside. Details, scaling and drawing limits are in
  `docs/jeti-api-notes.md`; measure more with `tools/probe/PROBE.lua`. The
  emulator plays no Lua audio, so voice can only be tested on the
  transmitter.

- Windows, PowerShell. Spec Kit scripts are the PowerShell variants.
- The deploy target is `/Apps` on the transmitter's SD card; `src/Apps/` mirrors
  it. The emulator's copy is `%LOCALAPPDATA%\JETI-Studio\Emulator\Apps`.
