# Jeti Lua Apps

A collection of Lua apps for the JETI DS-24 II transmitter, built with a
spec-driven workflow (GitHub Spec Kit + Claude Code) in VS Code.

## Apps

| App | Script | Status | Spec | Based on |
| --- | --- | --- | --- | --- |
| Speed Gauge | `AG-SpdGa.lua` | Spec written | [001](specs/001-speed-gauge/spec.md) | DFM Speed Announcer by Dave McQueeney (MIT) |

Apps here are for telemetry, timers, announcements and displays only. Nothing
in this repo may control surfaces, throttle or any flight function. See the
constitution: [`.specify/memory/constitution.md`](.specify/memory/constitution.md).

## Layout

```
.specify/memory/constitution.md   Rules every spec, plan and task inherits
.luarc.json                       LuaLS config (Lua 5.3, globals are errors)
.vscode/                          Editor settings, recommended extensions
types/jeti.lua                    LuaLS stubs for the Jeti API (v1.5 + notes)
docs/jeti-api-notes.md            The API facts that shape how apps are written
docs/examples/style/HELLO.lua     Style reference app (not deployed)
docs/examples/                    Other reference code, incl. official Jeti demos
docs/vendor/                      Generated full API text (gitignored)
specs/NNN-<feature>/              spec.md, plan.md, tasks.md per feature
src/Apps/                         Mirrors /Apps on the transmitter SD card
  AG-xxxxx.lua                    One script per app
  AG-xxxxx/                       That app's sounds, images, language files
  lib/ag_xxxxx.lua                Shared modules, require("ag_xxxxx")
tools/check.py                    Syntax, forbidden-API, naming, encoding checks
tools/pdf2md.py                   Converts Jeti's API PDF for local reference
```

### Multiple apps, one repo

- **Names.** Every app script is `AG-` plus up to 5 letters or digits, so it
  fits the transmitter's 8.3 limit and stays grouped apart from other
  authors' apps (`DFM-*`, `RCT-*`). The menu name is separate and can be
  anything. A released filename is never changed, because the transmitter
  ties each model's settings for an app to its filename.
- **Shared code** goes in `src/Apps/lib/` as `ag_xxxxx.lua`. One copy is loaded
  and shared by every app, so modules hold no state of their own.
- **Specs are per feature, not per app.** A new app and a later change to an
  existing app each get the next number in `specs/`.
- **Deploying.** Copy the app's script, its `AG-xxxxx/` folder, and any `lib/`
  modules it uses.

## First-time setup

1. **VS Code extensions.** Open the folder and accept the recommended
   extensions (Lua by sumneko, EditorConfig). LuaLS reads `.luarc.json`, so
   diagnostics also work from the command line and for agents.
2. **Spec Kit.** This repo already contains the constitution. Commit before
   initializing, because `--force` may replace managed files:
   ```bash
   uv tool install specify-cli
   specify init --here --force --integration claude --script ps
   git diff .specify/memory/constitution.md   # restore with git checkout if replaced
   ```
3. **Full API reference (optional, recommended for agents).**
   ```bash
   pip install pypdf
   python tools/pdf2md.py
   ```
   This writes `docs/vendor/jeti-api.md`. It's gitignored because the PDF is
   JETI's copyrighted document.
4. **Lua 5.3 compiler (optional).** `tools/check.py` uses `luac5.3`/`luac` from
   PATH for syntax checks and skips that step with a warning if absent.

## Workflow

1. `/speckit-specify`, `/speckit-plan`, `/speckit-tasks`, `/speckit-implement`
   for each feature under `specs/`.
2. Implement in `src/Apps/` following the naming rules above.
3. `python tools/check.py` must pass. LuaLS must show no errors.
4. Run in the JETI Studio DS-24 II emulator: copy the app into
   `%LOCALAPPDATA%\JETI-Studio\Emulator\Apps`. For sensors, use LeonAirRC's
   [Emulator Telemetry](https://github.com/LeonAirRC/Jeti-Lua-Apps) app.
   Remember the emulator has `os`, `debug` and `coroutine`; the radio does not.
5. Copy the app to `/Apps` on the transmitter's SD card (it mounts as USB mass
   storage). Optionally ship `.lc` bytecode compiled by the matching
   firmware/emulator version; `.lc` files are never committed.
6. First real run on a dedicated test model.

## Style reference: HELLO.lua

`docs/examples/style/HELLO.lua` is a small flight timer started by a
user-assigned switch. It is not deployed, but `check.py` and LuaLS still check
it. It demonstrates the conventions every app follows: lifecycle, a settings
form, `pSave`/`pLoad`, a telemetry window, rate-limited `loop()` and cached
display strings.

## API coverage

`types/jeti.lua` follows the JETI DC/DS Lua API v1.5 (December 2019). DS-24 v2
firmware may add functions that aren't in it. Entries marked `UNVERIFIED` were
inferred where the PDF is silent. When a newer API document turns up, update
the stubs and `docs/jeti-api-notes.md` together.

## Credits

Speed Gauge is based on **DFM Speed Announcer** by DFM (Dave McQueeney),
[github.com/davidmcq137/JetiLuaDFM](https://github.com/davidmcq137/JetiLuaDFM).
Much of its behavior comes from that app, and this rewrite wouldn't exist
without it. See [CREDITS.md](CREDITS.md) for all credits and license notices,
including JETI's demos.

## References

- Official apps and demos: https://github.com/JETImodel/Lua-Apps
- Community apps and emulator telemetry: https://github.com/LeonAirRC/Jeti-Lua-Apps
- Best practices: https://www.rc-thoughts.com/2016/09/lua-for-jeti-considerations-and-best-practices/
- Lua 5.3 manual: https://www.lua.org/manual/5.3/
