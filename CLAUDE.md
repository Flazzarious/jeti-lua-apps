# Jeti Lua Apps

Lua 5.3 apps for a JETI DS-24 II transmitter (firmware 6.x), built spec-first
with GitHub Spec Kit (`/speckit-specify`, `/speckit-plan`, `/speckit-tasks`,
`/speckit-implement`).

## Read before writing any code

- `.specify/memory/constitution.md`: the rules. They override everything else,
  including specs and your own suggestions.
- `types/jeti.lua`: the only APIs that exist. If a function isn't declared there,
  don't call it. Check the API doc, add a stub with a source note, then use it.
- `docs/jeti-api-notes.md`: runtime limits, lifecycle, persistence rules.
- `src/Apps/HELLO.lua`: the style reference for a complete app.
- `docs/examples/jeti-demos/`: official demos. Copy their API usage, not their
  structure.

## Hard rules (summary; the constitution has the detail)

- Never call `system.registerControl`, `system.setControl` or
  `system.setProperty`. Nothing an app does may affect flight.
- Every variable and function is `local`. The app file ends with
  `return { init=..., loop=..., author=..., version=..., name=... }`.
- No `os`, `debug`, `coroutine`, `bit32`. The JETI Studio emulator has them, but
  the transmitter doesn't.
- `lcd.*` only inside registered print functions; `form.*` only while the app's
  form is open.
- `system.pSave` stores integers, short strings, SwitchItems and small arrays.
  Scale floats to integers.
- `loop()` runs every 20-30 ms: rate-limit with `system.getTimeCounter()`, and
  don't format strings or build tables per call.
- App filenames in `src/Apps/` are 8.3 (`BATTMON.lua`) and are never renamed
  once released.

## Checking work

- `python tools/check.py` must pass (syntax, forbidden APIs, 8.3 names, UTF-8).
- LuaLS diagnostics must show no errors (configured by `.luarc.json`).
- You can't run the emulator. Say what to test in JETI Studio and on a test
  model instead of claiming the app works.

## Environment

- Windows, PowerShell. Spec Kit scripts are the PowerShell variants.
- The deploy target is `/Apps` on the transmitter's SD card; `src/Apps/` mirrors
  it.
