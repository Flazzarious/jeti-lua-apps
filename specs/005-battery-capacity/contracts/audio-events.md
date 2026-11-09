# Contract: Audio events

Voice files in `/Apps/AG-BatCp/voice/` (research R8). Scheduling and
fallback: research R9. All app-voice parts are played with
`system.playFile(path, AUDIO_QUEUE)`; a phrase starts only while
`system.isPlayback()` is false (FR-034), one phrase per dispatch.

## Events (in FR-034a priority order)

| # | Event | Trigger | App voice phrase | Transmitter fallback | Repeat |
| --- | --- | --- | --- | --- | --- |
| 1 | Low voltage (per cell) | vCell below threshold for delay (FR-020) | name · `lowv` · int · `point` · d1 · d2 · `vpc` | name file · `playNumber(v, 2, "V")` | every `rptS`, up to `maxCnt` |
| 1 | Low voltage (per pack) | same, pack voltage | name · `lowv` · int · `point` · d1 · `volts` | name file · `playNumber(v, 1, "V")` | same |
| 2 | High current | current above threshold for delay (FR-024) | name · `hicur` · n · `amps` | name file · `playNumber(n, 0, "A")` | every `iRpt` while above |
| 3 | Capacity level | % falls to a level (FR-017) | name · n · `pct` | name file · `playNumber(n, 0, "%")` | lowest level every `rptS`, up to `maxCnt` (FR-018) |
| 4 | Pack not full | 3 s after a new pack, below threshold (FR-029) | name · `notfull` · n · `pct` | name file · `playNumber(n, 0, "%")` | never |
| 5 | Max current | new max, held 1 s, beats last by sensitivity (FR-026) | name · `max` · n · `amps` | name file · `playNumber(n, 0, "A")` | never; replaced by a newer max |

- **name** = the category's voice file, then the label number's file when
  the battery is numbered (`n_rx` · `2`). Custom speaks `n_bat`.
- With **Speak number only**, the unit file (`pct`, `amps`, `volts`,
  `vpc`) is left out of app-voice phrases. The fallback keeps its unit
  (the transmitter's `playNumber` needs it to tell kinds apart).
- **Numbers** are spoken as integers, rounded: current in whole amps, % as
  the level (event 3) or the measured value (event 4). Voltage digits after
  the point are separate number files ("3 point 5 8").
- Callouts for a battery are suppressed while its telemetry is `LOST` or
  `NONE` (FR-015); pending flags are cleared on loss.
- Nothing is spoken for telemetry loss (FR-015, clarified 2026-11-01).

## Fallback (FR-033)

A phrase goes to the transmitter's voice as a whole when any of:

- `useAppVoice` is false (Voice = Transmitter, or files missing at startup);
- a number in the phrase is over 500;
- the number file fails its `io.open` check at dispatch.

Then: the battery's voice-name file (if set) with `playFile(file,
AUDIO_QUEUE)`, followed by `system.playNumber`. A callout is never silent.

## Files

| File | Spoken |
| --- | --- |
| `0.wav` … `500.wav` | numbers (copied from Speed Gauge's set) |
| `pct.wav`, `amps.wav`, `volts.wav`, `vpc.wav` | "percent", "amps", "volts", "volts per cell" |
| `point.wav` | "point" |
| `max.wav`, `hicur.wav`, `lowv.wav`, `notfull.wav` | "max", "high current", "low voltage", "pack not full" |
| `n_flt`, `n_rx`, `n_ecu`, `n_gear`, `n_brk`, `n_lgt`, `n_aux`, `n_bat` `.wav` | "flight", "receiver", "E C U", "landing gear", "brakes", "lights", "aux", "battery" |
| `CREDITS.txt`, `index.txt` | credits (Piper MIT, Amy CC BY-SA 4.0); generator record |

## Checks

- `init()`: open each word file and `0.wav`, `500.wav` (absolute path, then
  without the leading "/" for the emulator); `voiceOk` = all present.
- Emulator: Emulated Telemetry prints each `playFile`/`playNumber`, so the
  console shows the exact phrase and order. Sound itself: transmitter only.
