# Jeti Lua Apps

Lua apps for the JETI DS-24 v2 transmitter, built with a spec-driven workflow
(GitHub Spec Kit + an AI coding agent) in VS Code.

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
docs/examples/                    Reference code, incl. official Jeti demos
docs/vendor/                      Generated full API text (gitignored)
specs/<feature>/                  spec.md, plan.md, tasks.md per feature
src/Apps/                         Mirrors /Apps on the transmitter SD card
  HELLO.lua                       Starter app: switch-driven flight timer
tools/check.py                    Syntax + forbidden-API + filename checks
tools/pdf2md.py                   Converts Jeti's API PDF for local reference
```

## First-time setup

1. **VS Code extensions.** Open the folder and accept the recommended
   extensions (Lua by sumneko, EditorConfig). LuaLS reads `.luarc.json`, so
   diagnostics also work from the command line and for agents.
2. **Spec Kit.** This repo already contains the constitution. Commit before
   initializing, because `--force` may replace managed files:
   ```bash
   uv tool install specify-cli
   specify init --here --force --integration <your-agent>
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

1. `/speckit.specify`, `/speckit.plan`, `/speckit.tasks` for each feature under
   `specs/`.
2. Implement in `src/Apps/`. App filenames must be 8.3 (`BATTMON.lua`), and must
   never be renamed once in use: the transmitter keys each app's per-model
   settings to its filename.
3. `python tools/check.py` must pass. LuaLS must show no errors.
4. Run in the JETI Studio DC-24 emulator. For sensors, use LeonAirRC's
   [Emulator Telemetry](https://github.com/LeonAirRC/Jeti-Lua-Apps) app.
   Remember the emulator has `os`, `debug` and `coroutine`; the radio does not.
5. Copy `src/Apps/*` to `/Apps` on the transmitter's SD card (it mounts as USB
   mass storage). Optionally ship `.lc` bytecode compiled by the matching
   firmware/emulator version; `.lc` files are never committed.
6. First real run on a dedicated test model.

## Starter app: HELLO.lua

A flight timer started by a user-assigned switch. It shows elapsed time in a
small desktop telemetry window and announces every N minutes. Settings live in
Applications → Hello Timer (start switch, announce interval; F1 resets). It
demonstrates the lifecycle, a settings form, `pSave`/`pLoad`, a telemetry
window, rate-limited `loop()` and cached display strings.

## API coverage

`types/jeti.lua` follows the JETI DC/DS Lua API v1.5 (December 2019). DS-24 v2
firmware may add functions that aren't in it. Entries marked `UNVERIFIED` were
inferred where the PDF is silent. When a newer API document turns up, update
the stubs and `docs/jeti-api-notes.md` together.

## References

- Official apps and demos: https://github.com/JETImodel/Lua-Apps
- Community apps and emulator telemetry: https://github.com/LeonAirRC/Jeti-Lua-Apps
- Best practices: https://www.rc-thoughts.com/2016/09/lua-for-jeti-considerations-and-best-practices/
- Lua 5.3 manual: https://www.lua.org/manual/5.3/
