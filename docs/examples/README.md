# Reference examples

Code for the agent (and you) to learn idioms from. Nothing in this folder is
deployed, and LuaLS skips it (`workspace.ignoreDir` in `.luarc.json`), so
examples written before these conventions don't flood the Problems panel.

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
structure. `src/Apps/HELLO.lua` is the style reference.

The full official repo has more: complete apps (Battery Monitor, Sensor Chart,
Artificial Horizon) and demos for images, drawing, and the renderer. Its
Automatic Trainer Switch app and `28_ctrl.lua` demo use `setProperty` /
`registerControl`, which this repo forbids.
