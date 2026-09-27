# Jeti Lua API — Working Notes

A summary of the facts from the JETI DC/DS Lua API v1.5 (December 2019) that
shape how apps in this repo are written. It is not a substitute for the full
reference: run `tools/pdf2md.sh` to generate `docs/vendor/jeti-api.md` locally
(it is gitignored because the PDF is JETI's copyrighted document).

Official PDF: https://github.com/JETImodel/Lua-Apps/tree/master/Doc

> The v1.5 document predates some DS-24 v2 firmware. Anything added after
> firmware 5.0x will be missing here and from `types/jeti.lua`. When you find a
> newer API document, update both.

## Runtime

- Lua 5.3.1, built with 32-bit integers and floats (`LUA_32BITS`). Integer
  overflow happens at ±2,147,483,647, and float precision is single, about 7
  significant digits. Don't accumulate large millisecond counters in floats.
- Bitwise operators (`&`, `|`, `>>`) are native; `bit32` is absent.
- Available on the radio: `package` (no `loadlib`), `table`, `string`, `math`,
  limited `io`. Absent: `os`, `debug`, `coroutine`.
- The emulator additionally includes `os`, `debug`, `coroutine`, `socket` and
  `mobdebug`, so it will not catch use of those.
- DC/DS-24 runs up to 10 apps per model. The hard 50 kB memory cap applies to
  DC/DS-14/16, not the 24 series, but memory is still shared by all apps.

## Files and names

- Apps live in `/Apps` on the SD card as `NAME.lua`, filename in 8.3 format.
- The app's identity (and all model config for it) is derived from the
  filename. Renaming = losing its telemetry windows and settings.
- `require "mod"` looks in `/Apps/lib/mod.lua`, `/Apps/lib/mod/init.lua`,
  `/Apps/mod.lua`, `/Apps/mod/init.lua`.
- Audio: relative paths resolve under `/Audio` and `/Audio/<lang>`. Foreground
  playback (`AUDIO_IMMEDIATE`, `AUDIO_QUEUE`) is WAV only; background accepts
  MP3.

## App lifecycle

The app file returns a table: `init`, `loop`, `destroy` (5.00+), `author`,
`version`, `name`.

| Callback | When | Restrictions |
| --- | --- | --- |
| `init(code)` | Model loaded/changed (1), fresh load (0), after USB disconnect (2) | No `lcd`, no `form` |
| `loop()` | Every ~20–30 ms, not guaranteed | No `lcd`, limited `form` |
| `destroy()` | Before the Lua environment is torn down | — |
| telemetry print `(w, h)` | When its desktop window is drawn | Canvas cleared before each call |
| form init `(subformId)` | Form opened or `form.reinit()` | Build components here |
| form key `(keyCode)` | Key pressed/released while form open | `form.preventDefault()` to swallow |
| form print `(w, h)` | Form drawn | Canvas cleared before each call |

- Up to 2 telemetry windows and 2 forms per app; a form may have up to 127
  subforms, switched with `form.reinit(n)`.
- Telemetry window size: 0 auto, 1 small, 2 large, 3 full screen with status
  bar, anything else full screen without it.

## Persistence (`system.pSave` / `system.pLoad`)

- Per-model storage, loaded before `init()` runs.
- Storable: 32-bit integer, string (< 64 bytes, printable), SwitchItem, array of
  ≤ 32 integers/strings, `nil` (deletes). **No floats, no keyed tables.**
- Keys: strings < 64 bytes. Keep to ≤ 30 keys per app.
- Written on model switch or power-off, not at the call.
- `SYSTEM` and `MODEL` constants exist for data scope; v1.5 does not document
  how to pass them, so treat everything as model-scoped.
- For larger data, write a file with `io` or `json.encode`.

## Sensors and inputs

- `system.getSensors()` returns every sensor entry; `param == 0` is the sensor's
  name row. Useful in a setup form, too heavy for `loop()`.
- `system.getSensorByID(id, param)` returns a full entry;
  `system.getSensorValueByID(id, param)` returns a lighter one (no label/unit).
  Both return `nil` if the sensor doesn't exist. Always check `.valid`.
- Type 5 is date/time (`decimals == 0` means time), type 9 is GPS (decode
  `valGPS` with bit operations, or use the `gps` library).
- `system.getInputs("P1","SA",...)` returns raw controls in −1..1 (up to 8).
- For user-assigned switches, store a SwitchItem from `form.addInputbox` and read
  it with `system.getInputsVal(item)`.

## Forms

- `form.*` works only while this app's own form is displayed.
- `form.addIntbox` is integer-only (−32768..32767); display decimals by scaling.
- Component functions return an index used with `form.setValue`,
  `form.getValue`, `form.setProperties`.
- `form.setButton(n, text, state)` labels F1–F5 (max 7 chars, or `":icon"`).
- `form.question(...)` blocks the calling code until answered, so never call it
  from `loop()` in flight.

## Audio and alerts

- `system.playNumber(value, decimals, unit, label)`: unit and label must match
  the voice pack's `numbers.jsn` entries.
- `system.playBeep(repeat, freqHz, ms)`, `system.playSystemSound(SOUND_*)`,
  `system.stopPlayback([type])`, `system.vibration(rightStick, profile)`,
  `system.messageBox(text, seconds)`.

## Timing

- `system.getTimeCounter()`: milliseconds, for intervals and rate limiting.
- `system.getTime()`: seconds since 2000-01-01.
- `system.getDateTime()`: table with year, mon, day, hour, min, sec, dst.

## Forbidden in this repo (see constitution)

`system.registerControl`, `system.setControl`, `system.setProperty`, `os.*`,
`debug.*`, `coroutine.*`, and `gpio`/`serial` output without a scoped spec.
