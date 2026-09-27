# Reference examples

Code for the agent (and you) to learn idioms from. Nothing in this folder is
deployed.

## `style/`

`HELLO.lua`, the style reference for apps in this repo: a small switch-driven
flight timer. Unlike the folders below, it follows every rule in the
constitution, and LuaLS and `tools/check.py` check it.

LuaLS skips `jeti-demos/` and `dfm-speed-announce/`
(`workspace.ignoreDir` in `.luarc.json`), so third-party code written before
these conventions doesn't flood the Problems panel.

## `jeti-demos/`

A subset of JETI's official demos from
[JETImodel/Lua-Apps](https://github.com/JETImodel/Lua-Apps/tree/master/Demos),
copied unmodified under their BSD-style license (notice kept in each file).
Each demo isolates one API area:

| File | Shows |
| --- | --- |
| `04_time.lua` | `system.getTime`, blinking text in a form |
| `05_avgtm.lua` | Timing with `system.getTimeCounter` |
| `08_sensors.lua` | Walking `system.getSensors`, decoding time/date/GPS types |
| `09_input.lua` | `form.addInputbox` + `system.getInputsVal` |
| `10_telemw.lua` | Registering desktop telemetry windows |
| `11_form.lua` | Forms, subforms, links, keys |
| `20_persist.lua` | `system.pSave` / `system.pLoad` with text, number, switch |
| `22_audio.lua` | Audio file picker and playback types |
| `30_json.lua` | `json.encode` / `json.decode` |
| `32_RdLn.lua` | `io.readline` |

**Caveat for the agent:** these demos show API usage, not this repo's
performance rules. For example, `05_avgtm.lua` formats strings inside a print
function every frame, which principle VI forbids. Copy the API calls, not the
structure. `style/HELLO.lua` is the style reference.

The full official repo has more: complete apps (Battery Monitor, Sensor Chart,
Artificial Horizon) and demos for images, drawing, and the renderer. Its
Automatic Trainer Switch app and `28_ctrl.lua` demo use `setProperty` /
`registerControl`, which this repo forbids.

## `dfm-speed-announce/`

DFM Speed Announcer by DFM, Dave McQueeney
([davidmcq137/JetiLuaDFM](https://github.com/davidmcq137/JetiLuaDFM)). It is
the basis of this repo's Speed Gauge app (see `CREDITS.md`). This is
`DFM-SpdA.lua`, version 2.1, copied unmodified from
`/Apps` on Aaron's DS-24 on 2026-09-27. It is MIT-licensed; see the header of
`DFM-SpdA.lua`. The layout mirrors the transmitter: the script sits in `/Apps`,
and its WAV files and README sit in `/Apps/DFM-SpdA/`.

**This is the baseline for a planned rewrite, not a style reference.** The
rewrite should keep what the app does:
- Announcement interval varies with how fast speed changes.
- Fast callouts below Vref for landing.
- Stall, overspeed and "airspeed alive" warnings.
- A continuous-announce switch.
- Unit selection and pitot calibration.

It should then bring the code in line with the constitution. Things to look at
in the original:
- `loop()` does its full work every call: no rate limit, `getSensorByID` rather
  than `getSensorValueByID`, and `string.format` in the announce path.
- The telemetry print function formats and concatenates strings every frame.
- The sensor list is built once in `init()`. Sensors that appear after power-on
  (receiver not yet bound) are missing until the app reloads. The saved
  selectbox index can also point at the wrong sensor if the sensor list order
  changes.
- `io.readall("Apps/DFM-<model>.jsn")` reads a per-model calibration file using
  a relative path; the v1.5 API doc says `io` paths are absolute.
- `select(2, system.getDeviceType())` relies on an undocumented second return
  value (emulator flag) that `types/jeti.lua` doesn't declare.
- Comments and code disagree in places: the header says v1.8 while the code
  says 2.1, and the "airspeed alive" comment says Vref/4 while the code uses
  Vref/2.
- Plays audio in `init()` on every model load, including a cal-factor
  announcement.
