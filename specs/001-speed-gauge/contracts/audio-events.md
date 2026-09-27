# Contract: Audio and vibration

Assets are copied unmodified from `docs/examples/dfm-speed-announce/DFM-SpdA/`
to `src/Apps/AG-SpdGa/`, with a `CREDITS.txt` next to them naming DFM
(Dave McQueeney) and the MIT license (FR-029, constitution VIII).

| Event | Condition (data-model.md) | Output |
| --- | --- | --- |
| Startup | `init()`, `startAnn = 1`, `cal ≠ 100` | `playFile("/Apps/AG-SpdGa/airspeed_cal_factor.wav", AUDIO_QUEUE)`, `playNumber(cal, 0, "%")` |
| Startup | `init()`, `startAnn = 1` | `playFile(".../stall_speed_warning_at.wav", AUDIO_QUEUE)`, `playNumber(vStall, 0, unitSpoken)` |
| Airspeed alive | first `everAboveHalf` with a switch on | `playFile(".../airspeed_alive.wav", AUDIO_IMMEDIATE)` |
| Stall | stall armed → fired | `playFile(".../stall_warning.wav", AUDIO_IMMEDIATE)`, `vibration(true, 4)` |
| Overspeed | overspeed armed → fired | `playFile(".../overspeed.wav", AUDIO_IMMEDIATE)`, `vibration(true, 3)` |
| Callout, full | callout due, not short form | `playNumber(round(shownSpd), 0, unitSpoken, "Speed")` |
| Callout, short | callout due, short form | `playNumber(round(shownSpd), 0)` |

- `unitSpoken` uses v2.1's strings, which match the voice pack's
  `numbers.jsn`: `mph`, `km/h`, `kt.`, `m/s`, `ft./s`.
- Callouts are skipped while `system.isPlayback()` is true (FR-007); warnings
  use `AUDIO_IMMEDIATE` and are not delayed, as in v2.1.
- Vibration profiles 3 and 4 are v2.1's. The API doc names them "two short"
  and "three short"; v2.1's comments say 2 and 4 pulses. Keep the profile
  numbers; don't rely on either description.
